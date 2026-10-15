"""The reminder to attend (Team Agile V1, D-TA15).

A standup reminder is an Organize reminder -- one file in the hub's
``reminders/current/`` with source ``standup`` -- and the CLI writes it
(``Standup -Remind <HH:mm> [-Days ...]``). Attending is marking it done:
opening the standup archives the open one and writes the next, due the next
day in the cadence. Organize grows no recurrence; the ritual re-arms its own
reminder, and the cadence -- ``HH:mm <days>`` -- is the reminder's own
``**Ref:**`` line.

Two routes on the module's router, so both are 404 with ``features.solitaireAgile``
off:

  GET  /api/ritual/standup/remind  the standup reminder as it stands, for the
                                   settings row (organize on or off, the open
                                   reminder's due and cadence)
  POST /api/ritual/standup/attend  attending: the page calls it once per view

The attend route WRITES NOTHING ITSELF. It runs Organize's own two verbs
through the bridge -- ``Reminders <id> -Archive`` and ``NewReminder`` -- so a
reminder has one writer, the same one the CLI's Standup calls. With
``features.organize`` off it does nothing and says so; that is not an error.

The rule -- which days, which due, whether today's was attended already -- is
implemented twice, here and in ``Scripts/Standup-Remind.ps1``, and held to one
table: ``Tests/fixtures/rituals/remind.json``.
"""

from __future__ import annotations

import asyncio
import re
from datetime import datetime, timedelta

from pydantic import BaseModel

from ..ado import bridge
from ..core import log_writer
from ..core.config import API_PREFIX, hub_folder
from ..core.consts import (
    folder_current,
    rituals_attend_route,
    rituals_remind_route,
    rituals_remind_source,
    rituals_remind_title,
    rituals_weekdays,
)
from ..organize.reminders import organize_enabled, read_reminder
from .standup import api

# English day names, Monday first, for -Days Monday,Wednesday. The short names
# are the contract's (consts.json rituals.weekdays); these are only accepted.
_FULL_NAMES = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
_TIME = re.compile(r"^(\d{1,2}):(\d{2})$")
_CADENCE = re.compile(r"^(\S+)\s+(\S+)$")
_STAMP = "%Y-%m-%dT%H:%M"

NEW_REMINDER = "NewReminder"
REMINDERS = "Reminders"


# -- The rule (pure) -------------------------------------------------------------


def _day_index(token: str) -> int:
    t = token.strip().lower()
    for i, short in enumerate(rituals_weekdays()):
        if t == short.lower() or t == _FULL_NAMES[i]:
            return i
    return -1


def parse_days(text: str | None) -> list[int] | None:
    """``Mon-Fri``, ``mon,wed,fri``, ``Monday,Tue-Thu`` -> sorted day indexes
    (0 = Monday), or None when any part is not a day or a range runs backwards."""
    if not text or not text.strip():
        return None
    on: set[int] = set()
    for token in text.split(","):
        if not token.strip():
            return None
        ends = token.split("-")
        if len(ends) > 2:
            return None
        idx = [_day_index(e) for e in ends]
        if any(i < 0 for i in idx):
            return None
        if len(idx) == 1:
            on.add(idx[0])
        else:
            if idx[0] > idx[1]:
                return None
            on.update(range(idx[0], idx[1] + 1))
    return sorted(on)


def format_days(days: list[int]) -> str:
    """A run of three or more days is a range (``Mon-Fri``); anything else a list."""
    names = rituals_weekdays()
    d = sorted(set(days))
    if len(d) >= 3 and d[-1] - d[0] + 1 == len(d):
        return f"{names[d[0]]}-{names[d[-1]]}"
    return ",".join(names[i] for i in d)


def parse_time(text: str | None) -> str | None:
    """``9:00`` / ``09:00`` -> ``09:00``; anything else None."""
    m = _TIME.match((text or "").strip())
    if not m:
        return None
    h, mi = int(m.group(1)), int(m.group(2))
    if h > 23 or mi > 59:
        return None
    return f"{h:02d}:{mi:02d}"


def format_cadence(time: str, days: list[int]) -> str:
    return f"{time} {format_days(days)}"


def parse_cadence(ref: str | None) -> tuple[str, list[int]] | None:
    """A Ref line's ``HH:mm <days>`` -> (time, days), or None if it is not one."""
    m = _CADENCE.match((ref or "").strip())
    if not m:
        return None
    time, days = parse_time(m.group(1)), parse_days(m.group(2))
    if time is None or days is None:
        return None
    return time, days


def _at(day: datetime, time: str) -> datetime:
    h, mi = (int(x) for x in time.split(":"))
    return day.replace(hour=h, minute=mi, second=0, microsecond=0)


def first_due(now: datetime, time: str, days: list[int]) -> str:
    """The first day in the cadence whose time is still AHEAD of now, today included."""
    for k in range(8):
        day = now + timedelta(days=k)
        if day.weekday() not in days:
            continue
        at = _at(day, time)
        if k == 0 and at <= now:
            continue
        return at.strftime(_STAMP)
    raise ValueError("a cadence with no days")


def next_due(now: datetime, time: str, days: list[int]) -> str:
    """The next day in the cadence AFTER today, at the cadence's time."""
    for k in range(1, 8):
        day = now + timedelta(days=k)
        if day.weekday() in days:
            return _at(day, time).strftime(_STAMP)
    raise ValueError("a cadence with no days")


def _due_day(due: str):
    try:
        return datetime.strptime((due or "")[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


class AttendPlan(BaseModel):
    # absent | none | rearm | unreadable
    action: str
    archive: list[str] = []
    next: str = ""
    ref: str = ""


def attend_plan(now: datetime, open_reminders: list[tuple[str, str, str]]) -> AttendPlan:
    """What attending does to the open standup reminders, each (id, due, ref). Pure.

    One whose due is AFTER today means today's was attended already: nothing.
    Otherwise every open one is archived and ONE next is written, from the first
    readable cadence. No readable cadence: left alone.
    """
    if not open_reminders:
        return AttendPlan(action="absent")
    today = now.date()
    for _id, due, _ref in open_reminders:
        day = _due_day(due)
        if day is not None and day > today:
            return AttendPlan(action="none")
    cadence = next((c for c in (parse_cadence(ref) for _i, _d, ref in open_reminders) if c), None)
    if cadence is None:
        return AttendPlan(action="unreadable")
    time, days = cadence
    return AttendPlan(
        action="rearm",
        archive=[i for i, _d, _r in open_reminders],
        next=next_due(now, time, days),
        ref=format_cadence(time, days),
    )


# -- Reading the hub (reads only) ---------------------------------------------------


def _now() -> datetime:
    """The local clock, no offset -- a reminder's times have none. One seam for the tests."""
    return datetime.now().replace(second=0, microsecond=0)


def standup_reminders(now: datetime) -> list:
    """The open reminders whose source is the standup's, soonest due first."""
    folder = hub_folder("reminders") / folder_current()
    if not folder.is_dir():
        return []
    source = rituals_remind_source()
    out = [r for r in (read_reminder(f, now) for f in sorted(folder.glob("*.md"))) if r and r.source == source]
    out.sort(key=lambda r: r.due or "9999")
    return out


# -- The bridge: Organize's own verbs --------------------------------------------


def _run_verb(name: str, params: list[str]) -> str:
    """Run one Organize verb through the bridge. '' on success, else why not."""
    function = bridge.command_map().get(name)
    if not function:
        return f"'{name}' is not in this CLI's command table; the organize module may not be loaded."
    try:
        result = bridge._run(function, params, bridge.command_timeout(name))
    except Exception as e:  # noqa: BLE001 -- OSError, TimeoutExpired: a reason, never a raise
        return f"{name} did not run ({type(e).__name__}: {e})"
    if result.returncode != 0:
        return (result.stderr or result.stdout or "").strip() or f"{name} exited {result.returncode}"
    return ""


# -- The responses -------------------------------------------------------------------


class StandupReminder(BaseModel):
    id: str
    # As stored: "YYYY-MM-DDTHH:MM", "YYYY-MM-DD" or "".
    due: str
    ref: str
    # The cadence read back from ref; "" and [] when ref is not one.
    time: str = ""
    days: list[str] = []


class RemindState(BaseModel):
    organize: bool
    reminder: StandupReminder | None = None


class AttendResponse(BaseModel):
    organize: bool
    # off | absent | none | rearm | unreadable | error
    action: str
    archived: list[str] = []
    next: str = ""
    reason: str = ""


def remind_state(now: datetime | None = None) -> RemindState:
    if not organize_enabled():
        return RemindState(organize=False)
    found = standup_reminders(now or _now())
    if not found:
        return RemindState(organize=True)
    r = found[0]
    cadence = parse_cadence(r.ref)
    names = rituals_weekdays()
    return RemindState(
        organize=True,
        reminder=StandupReminder(
            id=r.id,
            due=r.due,
            ref=r.ref,
            time=cadence[0] if cadence else "",
            days=[names[i] for i in cadence[1]] if cadence else [],
        ),
    )


def attend(now: datetime | None = None) -> AttendResponse:
    """Attending: archive the open standup reminder and write the next, through
    Organize's verbs -- once a day. Never raises: a failure is a reason."""
    if not organize_enabled():
        return AttendResponse(
            organize=False, action="off", reason="features.organize is off, so there is no reminder to re-arm."
        )
    now = now or _now()
    found = standup_reminders(now)
    plan = attend_plan(now, [(r.id, r.due, r.ref) for r in found])
    if plan.action == "unreadable":
        return AttendResponse(
            organize=True,
            action="unreadable",
            reason=f"The standup reminder's ref '{found[0].ref}' is not a cadence (HH:mm days).",
        )
    if plan.action != "rearm":
        return AttendResponse(organize=True, action=plan.action)
    archived: list[str] = []
    for rid in plan.archive:
        why = _run_verb(REMINDERS, [rid, "-Archive"])
        if why:
            return AttendResponse(organize=True, action="error", archived=archived, reason=why)
        archived.append(rid)
    why = _run_verb(
        NEW_REMINDER,
        ["-Title", rituals_remind_title(), "-Due", plan.next, "-Source", rituals_remind_source(), "-Ref", plan.ref],
    )
    if why:
        return AttendResponse(organize=True, action="error", archived=archived, reason=why)
    log_writer.write_log("CMD", f"agent{ATTEND}", f"archived={','.join(archived)} next={plan.next}")
    return AttendResponse(organize=True, action="rearm", archived=archived, next=plan.next)


ATTEND = rituals_attend_route().removeprefix(API_PREFIX)
REMIND = rituals_remind_route().removeprefix(API_PREFIX)


@api.get(REMIND, response_model=RemindState)
def get_remind() -> RemindState:
    return remind_state()


@api.post(ATTEND, response_model=AttendResponse)
async def post_attend() -> AttendResponse:
    # Two child pwsh runs at most; off the event loop.
    return await asyncio.to_thread(attend)
