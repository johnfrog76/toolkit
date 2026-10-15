"""GET /api/reminders -- the open reminders, each with its bucket worked out.

A reminder is one file in the hub's ``reminders/current/`` -- the folder the hub
names (``hub.json`` ``folders.reminders``, default ``reminders``), a sibling of
``growth/`` and ``manager/``, never under an org. Its id is in the filename, read
by the one id rule (``regex.cardId``); its fields are footer lines -- Due, Source,
Ref and Created -- whose labels come from ``consts.json`` and are never typed here.

The bucket -- overdue, today, upcoming -- is DERIVED here, against the local
clock, and never stored: a file that stored it would be wrong by morning. The
CLI's ``Reminders`` works it out the same way, and the two are held to one table,
``Tests/fixtures/reminders/buckets.json``. Times are local with no offset; a due
date with no time is due at the end of its day.

A reminder's ``ref`` is free text. When the WHOLE of it has the shape of a card's
id (``regex.cardId``) and a card in the active Space's ``current/`` or
``archive/`` carries that id -- read by ``card_id()``, the one id rule -- the
item gains ``card``: what the web needs to link to it. Anything else stays the
plain text it was (docs/modules/organize.md, "A ref that names a card").
"""

from __future__ import annotations

import re
from datetime import date, datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..core.config import hub_folder, load_config, resolve_dirs
from ..core.consts import (
    card_id_shape,
    folder_archive,
    folder_current,
    re_due_line,
    reminder_buckets,
    stamp_created,
    stamp_ref,
    stamp_source,
)
from ..core.parsers import _parse_status_metadata, card_id


def organize_enabled() -> bool:
    return bool((load_config().get("features") or {}).get("organize", False))


def _require_organize() -> None:
    # A dependency, not a conditional mount: re-read per request, so a flag
    # flipped in another terminal needs no restart. Off is 404, not 403.
    if not organize_enabled():
        raise HTTPException(status_code=404, detail="the organize module is off (features.organize)")


api = APIRouter(dependencies=[Depends(_require_organize)])

# A reminder's filename: the id, then the dash that starts the slug. No type
# prefix -- a reminder has none -- and the id shape is the contract's.
_ID = re.compile(r"^(" + card_id_shape() + r")-")
_H1 = re.compile(r"(?m)^#\s+(.+)$")


def _footer(text: str, stamp: str) -> str:
    m = re.search(r"(?m)^" + re.escape(stamp) + r"[ \t]*(.*)$", text)
    return m.group(1).strip() if m else ""


def reminder_bucket(due: str, now: datetime) -> str:
    """overdue | today | upcoming for a stored due value against ``now``.

    No due -> upcoming. A date alone is due at the END of that day. A time is
    overdue only once its minute has passed.
    """
    overdue, today, upcoming = reminder_buckets()
    if not due:
        return upcoming
    try:
        if "T" in due:
            at = datetime.strptime(due, "%Y-%m-%dT%H:%M")
        else:
            day = datetime.strptime(due, "%Y-%m-%d").date()
            if day < now.date():
                return overdue
            return today if day == now.date() else upcoming
    except ValueError:
        return upcoming
    if at < now.replace(second=0, microsecond=0):
        return overdue
    return today if at.date() == now.date() else upcoming


class ReminderCard(BaseModel):
    """The card a reminder's ref names, when it names one."""

    id: str
    # What the work is called -- the heading after "Type id:", else the heading.
    title: str
    # consts.json folders: current | archive. Done is the folder.
    folder: str
    # The card's filename: the address the web's card page is keyed by.
    file: str


class Reminder(BaseModel):
    id: str
    filename: str
    title: str
    # The stored value exactly: "YYYY-MM-DD", "YYYY-MM-DDTHH:MM", or "".
    due: str
    bucket: str
    source: str
    ref: str
    created: str
    # The card ``ref`` names in the active Space, or None: a ref that is prose,
    # or an id no card there carries, stays plain text.
    card: ReminderCard | None = None


class RemindersResponse(BaseModel):
    count: int
    # How many are in each bucket, in display order -- the card's chip counts.
    buckets: dict[str, int]
    items: list[Reminder]
    # The local moment the buckets were worked out against.
    asOf: str


def read_reminder(path: Path, now: datetime) -> Reminder | None:
    m = _ID.match(path.name)
    if not m:
        return None  # not a reminder: no id
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    h1 = _H1.search(text)
    due = ""
    dm = re_due_line().search(text)
    if dm:
        due = dm.group(1) + (f"T{dm.group(2)}" if dm.group(2) else "")
    return Reminder(
        id=m.group(1),
        filename=path.name,
        title=h1.group(1).strip() if h1 else path.stem,
        due=due,
        bucket=reminder_bucket(due, now),
        source=_footer(text, stamp_source()),
        ref=_footer(text, stamp_ref()),
        created=_footer(text, stamp_created()),
    )


def ref_card_id(ref: str) -> str | None:
    """The card id a ref IS, or None. The whole ref must have the id's shape --
    ``41`` or ``K7M2``, not ``41 and the review`` -- and it is normalised by the
    one id rule, so ``0041`` and ``41`` name one work item."""
    ref = (ref or "").strip()
    if not re.fullmatch(card_id_shape(), ref):
        return None
    return card_id(f"{ref}-")


def _card_types() -> tuple[list[str], list[str]]:
    """(type names, file prefixes) from ``workItemTypes`` -- read per request,
    as the status route reads them, so a type a team adds needs no restart."""
    types = load_config().get("workItemTypes", {}) or {}
    names = [n for n in types if not n.startswith("_")]
    return names, [str((types[n] or {}).get("filePrefix") or "") for n in names]


def card_index() -> dict[str, ReminderCard]:
    """Every card id in the active Space, to the card it names. ``current/``
    wins over ``archive/``: a card that came back is the one being worked."""
    names, prefixes = _card_types()
    found: dict[str, ReminderCard] = {}
    for folder, label in zip(resolve_dirs(), (folder_current(), folder_archive())):
        if not folder.is_dir():
            continue
        for f in sorted(folder.glob("*.md")):
            cid = card_id(f.name, prefixes)
            if not cid or cid in found:
                continue
            meta = _parse_status_metadata(f.read_text(encoding="utf-8-sig", errors="replace"), names)
            found[cid] = ReminderCard(id=cid, title=meta["name"] or meta["title"] or f.stem, folder=label, file=f.name)
    return found


def resolve_refs(items: list[Reminder]) -> None:
    """Fill ``card`` on every reminder whose ref names a card. The Space is read
    only when some ref has an id's shape."""
    wanted = {r.id: ref_card_id(r.ref) for r in items}
    if not any(wanted.values()):
        return
    index = card_index()
    for r in items:
        cid = wanted[r.id]
        if cid and cid in index:
            r.card = index[cid]


def list_reminders(now: datetime | None = None) -> RemindersResponse:
    now = now or datetime.now()
    folder = hub_folder("reminders") / folder_current()
    items: list[Reminder] = []
    if folder.is_dir():  # a hub that has never had a reminder has no folder, and that is not an error
        for f in sorted(folder.glob("*.md")):
            r = read_reminder(f, now)
            if r:
                items.append(r)
    resolve_refs(items)
    order = {b: i for i, b in enumerate(reminder_buckets())}
    # Bucket order, then soonest due first, then undated last, then title.
    items.sort(key=lambda r: (order.get(r.bucket, 9), r.due or "9999", r.title.lower()))
    counts = {b: 0 for b in reminder_buckets()}
    for r in items:
        counts[r.bucket] = counts.get(r.bucket, 0) + 1
    return RemindersResponse(count=len(items), buckets=counts, items=items, asOf=now.strftime("%Y-%m-%dT%H:%M"))


@api.get("/reminders", response_model=RemindersResponse)
def get_reminders() -> RemindersResponse:
    return list_reminders()


# Keep date importable for callers that type a "today" (and the tests).
__all__ = ["api", "date", "list_reminders", "read_reminder", "ref_card_id", "reminder_bucket", "resolve_refs"]
