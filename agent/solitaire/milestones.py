"""GET /api/ritual/milestones -- the Space's milestones, for Team Agile's Milestones tab.

The tab's read (docs/modules/solitaire-agile.md, "Milestones: the tab and the
award"): one row per milestone of every repo the Space's tracker names, each with
its open and closed counts AS THE TRACKER KEEPS THEM -- GitHub's ``open_issues``
and ``closed_issues`` -- so the page's bar is the tracker's numbers and nothing
here re-counts issues. A READ: nothing is written, here or on the tracker.

There is no second milestone rule here. Each row is the ado core's own
``Milestone`` from ``accounting.github_milestone_rows`` -- the reader behind
``GET /api/milestones`` and the Stats tab's Milestones card -- and ``reached`` is
its ``milestone_reached``: every issue closed, and at least one issue, whatever
GitHub's own state says. So a milestone with no issues is never reached, and
never awarded. ``awarded`` is not the agent's at all: it is a reached milestone
whose award dialog this browser has shown (the page's mark, celebrate.ts).

What this route adds over ``/api/milestones`` is Team Agile's shape: the module's
gate (off is 404, the standup's dependency), ``?space=<slug>``, the tracker
state the ceremonies answer with (``tracker.ok`` and a reason, never a raise --
any repo that fails fails the read, as the standup's does), and the tracker's
kept reads -- one gh call per repo per minute (``tracker.remember``, key
``("milestones", repo)``), forgotten when a verb runs through the bridge.

``Tests/fixtures/rituals/milestones.json`` is the one table, asserted from
``Tests/test_ritual_milestones.py`` and drawn by the page's own test.
"""

from __future__ import annotations

import asyncio

from pydantic import BaseModel

from ..ado import accounting
from ..ado.accounting import Milestone
from ..core import log_writer
from ..core.config import API_PREFIX, load_config
from ..core.consts import rituals_milestones_route
from .standup import api
from .tracker import github_repos, remember

CEREMONY = "milestones"


class TrackerState(BaseModel):
    ok: bool = True
    reason: str = ""


class Milestones(BaseModel):
    ceremony: str = CEREMONY
    space: str = ""
    tracker: TrackerState = TrackerState()
    milestones: list[Milestone] = []


def read_milestones(repo: str, refresh: bool = False) -> tuple[list[Milestone], str | None]:
    """``repo``'s milestones, every state, kept for the tracker's TTL."""
    rows, why = remember(("milestones", repo), refresh, lambda: accounting.github_milestone_rows(repo))
    # Copies: a caller never edits what is kept.
    return [m.model_copy() for m in rows or []], why


def milestones_for(space: str = "", refresh: bool = False) -> Milestones:
    """Every milestone of a Space -- the active one when ``space`` is "". Never
    raises for the tracker: a failed read is ``tracker.ok`` false and no rows."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    out = Milestones(space=space or cfg.get("activeSpace", ""))
    repos, state = github_repos(org, status, projects, ritual="the Milestones tab", refresh=refresh)
    rows: list[Milestone] = []
    if state["ok"]:
        for repo in repos:
            got, why = read_milestones(repo, refresh)
            if why:
                # Half the milestones would read as the whole of them.
                state, rows = {"ok": False, "reason": why}, []
                break
            rows += got
    out.milestones = rows
    out.tracker = TrackerState(ok=bool(state["ok"]), reason=str(state["reason"] or ""))
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"space={out.space} ok={int(out.tracker.ok)} milestones={len(rows)} "
        f"reached={sum(1 for m in rows if m.reached)}",
    )
    return out


ROUTE = rituals_milestones_route().removeprefix(API_PREFIX)


@api.get(ROUTE, response_model=Milestones)
async def get_milestones(space: str = "", refresh: int = 0):
    # space_scope raises the 404 for an unknown slug, as the standup's does.
    # ?refresh=1 reads the tracker again past the kept read.
    return await asyncio.to_thread(milestones_for, space, bool(refresh))
