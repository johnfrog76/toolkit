"""GET /api/ritual/triage -- the open issues by milestone (Team Agile V1).

The ritual the owner asked for (D-TA5): the open issues grouped by
milestone, the group with no milestone FIRST because nobody has placed them,
then the milestones by open count, most first (a tie by title, ordinal). Each
issue carries its worker (the size, D-TA3: the worker label IS the size), who
has it (D-AR10: its GitHub assignee -- "me" when that is you -- else its size,
else nobody), its severity label and the deep-water mark; each group its
context line, "N open, M routed, K unrouted", routed meaning someone has it.

Two halves implement it -- this file and the CLI's ``Scripts/Get-Triage.ps1``
(over ``Scripts/Triage-Rules.ps1``) -- and one table holds them to each other:
``Tests/fixtures/rituals/triage.json`` and the golden texts beside it,
asserted from ``Tests/test_triage.py`` and ``tkTestToolkit -Triage``.

This route is a READ. The answers are the CLI's ``Route`` verb, which the web
calls only through ``POST /api/cmd/Route`` -- every move a real label or
milestone on the tracker (D-TA2), nothing stored here.

The ceremony's words, slots, severities and deep-water label are
``Config/ceremonies.json``'s ``triage`` row; the worker rule and the Tracker
line are the standup's (``standup.py``), so the two ceremonies cannot disagree
about who an issue is routed to.
"""

from __future__ import annotations

import asyncio
import re

from pydantic import BaseModel

from ..ado import accounting
from ..core import log_writer
from ..core.child import run_read
from ..core.config import API_PREFIX, load_config
from ..core.consts import (
    rituals_assign_me,
    rituals_label_width,
    rituals_text,
    rituals_triage_route,
    rituals_worker_label_prefix,
)
from .standup import _label_names, api, ceremonies, worker_name
from .tracker import read_tracker, remember

CEREMONY = "triage"


# -- The response -------------------------------------------------------------


class TrackerState(BaseModel):
    ok: bool = True
    reason: str = ""


class Size(BaseModel):
    label: str  # the worker label ("<worker>") -- what Route -Size writes
    name: str  # the worker's name from the label's description ("<worker>")


class TriageIssue(BaseModel):
    number: int
    title: str = ""
    url: str = ""
    worker: str = ""  # the worker's NAME, "" when no label routes it
    size: str = ""  # the worker LABEL, "" when none
    assignee: str = ""  # the first GitHub assignee's login, "" when none
    who: str = ""  # D-AR10: "me", "@<login>", the size, or "" -- nobody (who())
    severity: str = ""  # the first severity label it carries, "" when none
    deepWater: bool = False


class TriageGroup(BaseModel):
    milestone: str = ""  # "" is the group with no milestone
    open: int = 0
    routed: int = 0
    unrouted: int = 0
    context: str = ""
    issues: list[TriageIssue] = []


class Triage(BaseModel):
    ceremony: str = CEREMONY
    space: str = ""
    tracker: TrackerState = TrackerState()
    slots: list[str] = []
    severities: list[str] = []
    deepWaterLabel: str = ""
    sizes: list[Size] = []
    groups: list[TriageGroup] = []
    text: str = ""


# -- The rule -----------------------------------------------------------------


def _row() -> dict:
    return ceremonies()[CEREMONY]


def _milestone_title(issue: dict) -> str:
    m = issue.get("milestone")
    if isinstance(m, dict):
        return str(m.get("title") or "")
    return str(m or "")


def _assignees(issue: dict) -> list[str]:
    """An issue's assignee logins: gh gives ``{"login": ...}`` objects, the fixture strings."""
    out = []
    for a in issue.get("assignees") or []:
        login = a.get("login") if isinstance(a, dict) else a
        if login:
            out.append(str(login))
    return out


def who(assignee: str, size: str, viewer: str = "") -> str:
    """Who has an item (D-AR10), one rule: the first assignee -- ``rituals.assignMe``
    ("me") when it is the viewer (ignoring case, as GitHub's logins are),
    ``@<login>`` otherwise -- else the size, else "" (nobody). The CLI's
    ``Get-P20TriageWho`` is the same rule over the same table."""
    if assignee:
        if viewer and assignee.lower() == viewer.lower():
            return rituals_assign_me()
        return "@" + assignee
    return size


def _context(n_open: int, routed: int) -> str:
    return (
        _row()["text"]["context"]
        .replace("{open}", str(n_open))
        .replace("{routed}", str(routed))
        .replace("{unrouted}", str(n_open - routed))
    )


def fill_triage(
    labels: list[dict], issues: list[dict], tracker_state: dict, space: str = "", viewer: str = ""
) -> Triage:
    """The groups from labels and issues. Pure.

    ``tracker_state`` is ``{"ok": bool, "reason": str}``; when it is not ok the
    labels and issues are not read -- the ceremony is its title and the reason.
    ``viewer`` is the signed-in gh user's login ("" when unknown): an issue
    assigned to them reads "me".
    """
    row = _row()
    severities = list(row["severities"])
    deep = row["deepWaterLabel"]
    state = TrackerState(ok=bool(tracker_state.get("ok")), reason=str(tracker_state.get("reason") or ""))
    out = Triage(space=space, tracker=state, slots=list(row["slots"]), severities=severities, deepWaterLabel=deep)
    if not state.ok:
        return out

    prefix = rituals_worker_label_prefix()
    routes = sorted(
        (
            (str(lab.get("name", "")), worker_name(str(lab.get("description") or "")))
            for lab in labels or []
            if str(lab.get("description") or "").startswith(prefix) and lab.get("name")
        ),
        key=lambda t: t[0],
    )
    names = dict(routes)
    out.sizes = [Size(label=label, name=name) for label, name in routes]

    groups: dict[str, list[TriageIssue]] = {}
    for issue in sorted(issues or [], key=lambda i: int(i.get("number", 0))):
        if str(issue.get("state", "OPEN")).upper() != "OPEN":
            continue
        tags = _label_names(issue.get("labels"))
        size = next((t for t in tags if t in names), "")
        assignee = next(iter(_assignees(issue)), "")
        item = TriageIssue(
            number=int(issue.get("number", 0)),
            title=issue.get("title", "") or "",
            url=issue.get("url", "") or "",
            worker=names.get(size, ""),
            size=size,
            assignee=assignee,
            who=who(assignee, size, viewer),
            severity=next((t for t in tags if t in severities), ""),
            deepWater=deep in tags,
        )
        groups.setdefault(_milestone_title(issue), []).append(item)

    def order(title: str) -> tuple:
        # No milestone first; then most open first; a tie by title, ordinal.
        return (0 if title == "" else 1, -len(groups[title]), title)

    for title in sorted(groups, key=order):
        members = groups[title]
        # Routed: someone has it -- a worker label or an assignee (D-AR10).
        routed = sum(1 for i in members if i.who)
        out.groups.append(
            TriageGroup(
                milestone=title,
                open=len(members),
                routed=routed,
                unrouted=len(members) - routed,
                context=_context(len(members), routed),
                issues=members,
            )
        )
    return out


def render_triage(filled: Triage) -> str:
    """The text, LF-joined and LF-terminated, exactly as the golden files have it. Pure."""
    t = _row()["text"]
    lines = [t["title"].replace("{space}", filled.space), ""]
    if not filled.tracker.ok:
        label = rituals_text()["tracker"].ljust(rituals_label_width())
        lines.append(f"  {label}  {filled.tracker.reason}")
    elif not filled.groups:
        lines.append(t["nothingOpen"])
    else:
        for n, g in enumerate(filled.groups):
            if n:
                lines.append("")
            heading = g.milestone or t["noMilestone"]
            lines.append(t["group"].replace("{milestone}", heading).replace("{context}", g.context))
            for i in g.issues:
                # Who: "me", "@<login>", the size's worker name, or nobody.
                shown = i.worker if i.size and i.who == i.size else i.who
                tags = [shown or t["nobody"], i.severity or t["none"]]
                if i.deepWater:
                    tags.append(filled.deepWaterLabel)
                lines.append(
                    t["issue"]
                    .replace("{number}", str(i.number))
                    .replace("{title}", i.title)
                    .replace("{tags}", ", ".join(tags))
                )
    return "\n".join(lines) + "\n"


# -- The gh layer -------------------------------------------------------------


_LOGIN = re.compile(r"^[A-Za-z0-9-]+$")


def _read_viewer() -> tuple[str, str | None]:
    try:
        result = run_read(["gh", "api", "user", "-q", ".login"], 15)
    except Exception:  # noqa: BLE001 -- gh missing or slow: nobody is "me", nothing fails
        return "", "gh did not answer"
    login = (result.stdout or "").strip() if result.returncode == 0 else ""
    return (login, None) if _LOGIN.match(login) else ("", "gh named nobody")


def _viewer(refresh: bool = False) -> str:
    """The signed-in gh user's login (``gh api user -q .login``), "" when gh cannot say.

    Best effort: without it every assignee reads ``@<login>`` and the triage
    still answers. The CLI's Get-Triage.ps1 makes the same read. Kept for the
    tracker read's TTL (tracker.py); a login gh could not give is not kept."""
    login, _why = remember(("viewer",), refresh, _read_viewer)
    return str(login or "")


def triage_for(space: str = "", refresh: bool = False) -> Triage:
    """The whole triage for a Space -- the active one when ``space`` is "".
    ``refresh`` reads the tracker again past the kept read (tracker.py)."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    labels, issues, state = read_tracker(org, status, projects, state="open", ritual="triage", refresh=refresh)
    viewer = _viewer(refresh) if state.get("ok") else ""
    filled = fill_triage(labels, issues, state, space=space or cfg.get("activeSpace", ""), viewer=viewer)
    filled.text = render_triage(filled)
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"space={filled.space} ok={int(filled.tracker.ok)} groups={len(filled.groups)} "
        f"open={sum(g.open for g in filled.groups)}",
    )
    return filled


ROUTE = rituals_triage_route().removeprefix(API_PREFIX)


@api.get(ROUTE, response_model=Triage)
async def get_triage(space: str = "", refresh: int = 0):
    # space_scope raises the 404 for an unknown slug, as the standup's does.
    # ?refresh=1 (the page's Refresh) reads the tracker again past the TTL.
    return await asyncio.to_thread(triage_for, space, bool(refresh))
