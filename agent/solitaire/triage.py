"""GET /api/ritual/triage -- the open issues by milestone (Team Agile V1).

The ritual the owner asked for (D-TA5): the open issues grouped by
milestone, the group with no milestone FIRST because nobody has placed them,
then the milestones by open count, most first (a tie by title, ordinal). Each
issue carries its worker (the size, D-TA3: the worker label IS the size), its
severity label and the deep-water mark; each group its context line,
"N open, M routed, K unrouted".

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

from pydantic import BaseModel

from ..ado import accounting
from ..core import log_writer
from ..core.config import API_PREFIX, load_config, tracker, tracker_repos
from ..core.consts import rituals_label_width, rituals_text, rituals_triage_route, rituals_worker_label_prefix
from ..core.tier import _resolve_tier
from .standup import NO_REPO_REASON, _label_names, api, ceremonies, worker_name

CEREMONY = "triage"

NOT_GITHUB_REASON = "This Space's tracker is not GitHub -- triage reads a GitHub Space's issues."


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


def _context(n_open: int, routed: int) -> str:
    return (
        _row()["text"]["context"]
        .replace("{open}", str(n_open))
        .replace("{routed}", str(routed))
        .replace("{unrouted}", str(n_open - routed))
    )


def fill_triage(labels: list[dict], issues: list[dict], tracker_state: dict, space: str = "") -> Triage:
    """The groups from labels and issues. Pure.

    ``tracker_state`` is ``{"ok": bool, "reason": str}``; when it is not ok the
    labels and issues are not read -- the ceremony is its title and the reason.
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
        item = TriageIssue(
            number=int(issue.get("number", 0)),
            title=issue.get("title", "") or "",
            url=issue.get("url", "") or "",
            worker=names.get(size, ""),
            size=size,
            severity=next((t for t in tags if t in severities), ""),
            deepWater=deep in tags,
        )
        groups.setdefault(_milestone_title(issue), []).append(item)

    def order(title: str) -> tuple:
        # No milestone first; then most open first; a tie by title, ordinal.
        return (0 if title == "" else 1, -len(groups[title]), title)

    for title in sorted(groups, key=order):
        members = groups[title]
        routed = sum(1 for i in members if i.size)
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
                tags = [i.worker or t["none"], i.severity or t["none"]]
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


def _read_tracker(org: str, status: str, projects: list[dict]) -> tuple[list[dict], list[dict], dict]:
    """(labels, open issues, tracker state) for a Space. Never raises: a failure is a reason."""
    if tracker(org) != "github":
        return [], [], {"ok": False, "reason": NOT_GITHUB_REASON}
    tier, _ = _resolve_tier(org, status)
    if tier != 1:
        return [], [], {"ok": False, "reason": f"The tracker is not reachable from here (tier {tier})."}
    repos = tracker_repos(org, projects)
    if not repos:
        return [], [], {"ok": False, "reason": NO_REPO_REASON}
    labels: dict[str, dict] = {}
    issues: list[dict] = []
    try:
        for repo in repos:
            rows, why = accounting._gh_labels(repo)
            if why:
                return [], [], {"ok": False, "reason": why}
            for r in rows:
                labels.setdefault(str(r.get("name", "")), r)
            rows, why = accounting._gh_issues(repo, True, "open")
            if why:
                return [], [], {"ok": False, "reason": why}
            issues += rows
    except Exception as exc:  # noqa: BLE001 -- a reader that raised is a tracker that did not answer
        return [], [], {"ok": False, "reason": f"The tracker read failed: {exc.__class__.__name__}: {exc}"}
    return list(labels.values()), issues, {"ok": True, "reason": ""}


def triage_for(space: str = "") -> Triage:
    """The whole triage for a Space -- the active one when ``space`` is ""."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    labels, issues, state = _read_tracker(org, status, projects)
    filled = fill_triage(labels, issues, state, space=space or cfg.get("activeSpace", ""))
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
async def get_triage(space: str = ""):
    # space_scope raises the 404 for an unknown slug, as the standup's does.
    return await asyncio.to_thread(triage_for, space)
