"""Accounting -- the organisation's ledger, read from Azure DevOps.

/prs, /work-items, /dashboard and the lazy per-project /dashboard/pipelines.
Every route here is Tier 1 only: when ADO is not reachable, or the org is
declared local or archive, they return empty rather than failing, so a machine
without the tracker still renders the page.

An empty answer at Tier 1 says WHY, in ``reason``, when there is something to
fix: no identity (``core/identity.py``), no ``projects`` on the org, or the
first ``az`` call that failed -- a timeout, a missing CLI, stderr, output that
was not JSON. The log always had the failure; the card could not tell "nothing
assigned to you" from "the call failed" until it did too.
A
populated list carries no reason: a warning beside rows reads as a failure that
did not happen.
"""

import asyncio
import json
import re
import subprocess
import threading
import time
from datetime import UTC

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core import log_writer
from ..core.child import ChildReadError, did_not_answer, run_read
from ..core.clock import local_stamp
from ..core.config import (
    ACTIVE_LEDGER_KEY,
    ISSUE_LIMIT_ALL,
    ISSUE_LIMIT_OPEN,
    REPO_ROOT,
    hub_root,
    load_config,
    resolve_dirs,
    tracker,
    tracker_repos,
)
from ..core.consts import (
    rituals_worker_label_prefix,
    visibility_private,
    visibility_public,
    visibility_unknown,
)
from ..core.identity import IDENTITY_MISSING_REASON, resolve_identity, warn_no_identity
from ..core.tier import _resolve_tier

api = APIRouter()

AZ_TIMEOUT_SECONDS = 30


def no_projects_reason(slug: str) -> str:
    """The stated reason when the active Space has no project to ask about."""
    return (
        f"No projects configured for {slug or 'the active Space'}: add `projects` "
        "to the org in hub.json (feature-config-cannot-set-an-orgs-projects)."
    )


def _az_json(cmd: list[str], route: str, verb: str, target: str) -> tuple[list[dict], str | None]:
    """Run one ``az`` command and parse its JSON.

    ``(rows, None)`` on success; ``([], reason)`` on any failure, with the
    reason a sentence a card can show and the same sentence written to the log.
    ``WARNING`` lines az prints on stdout are dropped before parsing.
    """
    try:
        result = run_read(cmd, AZ_TIMEOUT_SECONDS)  # through the shell on Windows: az.cmd needs it
        lines = [ln for ln in result.stdout.splitlines() if not ln.startswith("WARNING")]
        text = "\n".join(lines).strip()
        if result.returncode == 0 and text:
            return json.loads(text), None
        stderr = result.stderr.strip().splitlines()
        detail = stderr[0][:200] if stderr else f"exit code {result.returncode}, no output"
        reason = f"`az {verb}` failed for {target}: {detail}"
        log_writer.write_log("WARN", route, reason)
    except subprocess.TimeoutExpired:
        reason = f"`az {verb}` timed out after {AZ_TIMEOUT_SECONDS}s for {target}"
        log_writer.write_log("WARN", route, reason)
    except FileNotFoundError:
        reason = "az CLI not found on PATH -- install it, or start the agent from a shell that has it."
        log_writer.write_log("ERR", route, reason)
    except json.JSONDecodeError as e:
        reason = f"`az {verb}` returned output that is not JSON for {target}: {e}"
        log_writer.write_log("ERR", route, reason)
    except ChildReadError as e:
        reason = f"`az {verb}` failed for {target}: {e}"
        log_writer.write_log("ERR", route, reason)
    return [], reason


class PRInfo(BaseModel):
    pull_request_id: int
    title: str
    role: str  # Author | Reviewer
    project: str
    repo: str
    created: str
    source_branch: str
    target_branch: str
    url: str


class PRsResponse(BaseModel):
    count: int
    prs: list[PRInfo]
    # Why the list is empty, when it is empty for a reason the user can fix.
    # None at Tier 2/3, which is not a gap: a local or unreachable org
    # legitimately has no PRs and the tier badge already says so.
    reason: str | None = None


# ---------------------------------------------------------------------------
def _az_pr_list(org: str, project: str, repo: str, role_flag: str, email: str) -> tuple[list[dict], str | None]:
    """``az repos pr list`` -- ``(rows, None)``, or ``([], why)``."""
    cmd = [
        "az",
        "repos",
        "pr",
        "list",
        "--org",
        org,
        "--project",
        project,
        "--repository",
        repo,
        "--status",
        "active",
        role_flag,
        email,
        "--output",
        "json",
    ]
    return _az_json(cmd, "agent/prs", "repos pr list", f"{project}/{repo}")


@api.get("/prs", response_model=PRsResponse)
async def get_prs(creator_only: bool = False):
    cfg = load_config()
    org = cfg.get("org", "")
    projects = cfg.get("projects", [])

    # Tier gate: PRs are ADO-derived — Tier 1 only (docs/CLI.md, "Tiers: what works without ADO")
    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))
    if tier != 1 or not org:
        return PRsResponse(count=0, prs=[])

    targets = [(p.get("name", ""), p.get("repo", "")) for p in projects if p.get("hasRepo", True)]
    targets = [(pn, rn) for pn, rn in targets if pn and rn]

    # Who "me" is. Not cfg["email"]: the CLI has always fallen back to az and
    # this route did not, so the browser showed nothing while tkMyPRs in the
    # same shell listed the PR.
    #
    email, _src = await asyncio.to_thread(resolve_identity)
    if not email:
        # Empty WITH a reason, and a log line. The silence was the bug: this
        # returned before the write_log below, so the day's log had no
        # agent/prs entry to explain the empty card.
        warn_no_identity("agent/prs")
        return PRsResponse(count=0, prs=[], reason=IDENTITY_MISSING_REASON)

    if not targets:
        reason = no_projects_reason(cfg.get("activeSpace", ""))
        log_writer.write_log("WARN", "agent/prs", reason)
        return PRsResponse(count=0, prs=[], reason=reason)

    all_prs: list[PRInfo] = []
    author_ids: set[int] = set()
    failures: list[str] = []

    for proj_name, repo_name in targets:
        # PRs I created
        created, failed = await asyncio.to_thread(_az_pr_list, org, proj_name, repo_name, "--creator", email)
        if failed:
            failures.append(failed)
        for pr in created:
            pr_id = pr.get("pullRequestId", 0)
            author_ids.add(pr_id)
            src = pr.get("sourceRefName", "").replace("refs/heads/", "")
            tgt = pr.get("targetRefName", "").replace("refs/heads/", "")
            created_date = pr.get("creationDate", "")[:10]
            proj_encoded = proj_name.replace(" ", "%20")
            url = f"{org}/{proj_encoded}/_git/{repo_name}/pullrequest/{pr_id}"
            all_prs.append(
                PRInfo(
                    pull_request_id=pr_id,
                    title=pr.get("title", ""),
                    role="Author",
                    project=proj_name,
                    repo=repo_name,
                    created=created_date,
                    source_branch=src,
                    target_branch=tgt,
                    url=url,
                )
            )

        # PRs where I'm a reviewer
        if not creator_only:
            reviewing, failed = await asyncio.to_thread(_az_pr_list, org, proj_name, repo_name, "--reviewer", email)
            if failed:
                failures.append(failed)
            for pr in reviewing:
                pr_id = pr.get("pullRequestId", 0)
                if pr_id in author_ids:
                    continue  # already listed as author
                src = pr.get("sourceRefName", "").replace("refs/heads/", "")
                tgt = pr.get("targetRefName", "").replace("refs/heads/", "")
                created_date = pr.get("creationDate", "")[:10]
                proj_encoded = proj_name.replace(" ", "%20")
                url = f"{org}/{proj_encoded}/_git/{repo_name}/pullrequest/{pr_id}"
                all_prs.append(
                    PRInfo(
                        pull_request_id=pr_id,
                        title=pr.get("title", ""),
                        role="Reviewer",
                        project=proj_name,
                        repo=repo_name,
                        created=created_date,
                        source_branch=src,
                        target_branch=tgt,
                        url=url,
                    )
                )

    # Sort: Authors first, then by created date descending
    all_prs.sort(key=lambda p: (0 if p.role == "Author" else 1, p.created), reverse=False)

    log_writer.write_log("CMD", "agent/prs", f"{len(all_prs)} PRs")
    # The first failure, and only beside an empty list -- see the module docstring.
    reason = failures[0] if (failures and not all_prs) else None
    return PRsResponse(count=len(all_prs), prs=all_prs, reason=reason)


# GET /api/work-items — work items assigned to me (mirrors Get-MyWorkItems.ps1)
# ---------------------------------------------------------------------------
class WorkItemInfo(BaseModel):
    id: int
    title: str
    type: str
    state: str
    project: str
    sprint: str
    updated: str
    url: str
    # Who holds it -- filled by the GitHub path, where the ALL view exists
    # and "whose is this" is the row's first question. The ADO path leaves
    # it empty (that view is assigned-to-me by construction).
    assignee: str = ""
    # Raw label names, GitHub path only -- the sev chips and the pane's
    # filters read these; the ADO path leaves them empty.
    labels: list[str] = []
    # WHO WORKS IT: the label that routes the issue to a worker -- one
    # whose description starts "Routed to" (opus, fable, sonnet on this
    # repo). Read from the label's own description, never a list here, so a
    # fourth worker is a label away. GitHub path only; "" when none.
    worker: str = ""
    # The day it closed, GitHub path only -- "" while open. Closed rows sort
    # after open ones, newest-closed first.
    closed: str = ""
    # PINNED ON THE TRACKER: GitHub's own pin, `isPinned` on the row --
    # no second store, so a pin set on github.com or from another machine
    # reads here too. The web sorts these first. GitHub path only.
    pinned: bool = False


class WorkItemsResponse(BaseModel):
    count: int
    items: list[WorkItemInfo]
    reason: str | None = None


def _az_wiql(org: str, project: str, wiql: str) -> tuple[list[dict], str | None]:
    """``az boards query --wiql`` -- ``(rows, None)``, or ``([], why)``."""
    cmd = ["az", "boards", "query", "--org", org, "--project", project, "--wiql", wiql, "--output", "json"]
    return _az_json(cmd, "agent/work-items", "boards query", project)


# The GitHub half of /work-items -- the BACKLOG VIEW. One route,
# dispatched by the space's address like every tracker seam: gh issue list per
# repo, assigned-to-me by default, ?all=1 for the unassigned many -- which is
# the view's whole point ("until I assign something we see nothing"). The
# label folds to the house's type words so the card's badges keep working.
_LABEL_TO_TYPE = {"bug": "Bug", "enhancement": "Feature"}

# The ledger's STATE axis: open is the default and the everyday view;
# closed and all are the opt-in that pulls the closed ones -- "read the old
# issues before filing a new one". gh's own words, so they pass straight
# through. The assignee axis is the separate ``all`` parameter.
GH_ISSUE_STATES = ("open", "closed", "all")

# A label that ROUTES an issue to a worker says so in its description:
# "Routed to <worker> -- ...". The description is the data, so the worker chips
# are whatever labels a repo carries in this shape. The prefix is the contract's
# (consts.json rituals.workerLabelPrefix): the standup reads the same rule.
WORKER_LABEL_PREFIX = rituals_worker_label_prefix()

# What gh says when the repository is not there for this login -- GraphQL's
# "Could not resolve to a Repository" (issue list) and REST's "Not Found (HTTP
# 404)" (api, run list). Both mean one thing a person can act on, so both read
# as one sentence (the GitHub demo's repo may not be seeded yet, and a
# repo can be private to another account). Every other line passes through.
REPO_UNREADABLE = (
    "gh cannot read this repository -- it does not exist yet, or it is private to an account this gh login is not"
)
_REPO_MISSING_MARKERS = ("could not resolve to a repository", "not found (http 404)", "http 404")


def gh_repo_reason(repo: str, why: str) -> str:
    """A failed gh read of ``repo``, as the sentence a card shows."""
    text = (why or "").strip() or "gh returned an error"
    if any(m in text.lower() for m in _REPO_MISSING_MARKERS):
        text = REPO_UNREADABLE
    return f"{repo}: {text}"


def _gh_issues(repo: str, all_items: bool, state: str = "open", body: bool = False) -> tuple[list[dict], str | None]:
    # A closed history is longer than an open backlog, so the opt-in reads further.
    limit = str(ISSUE_LIMIT_OPEN if state == "open" else ISSUE_LIMIT_ALL)
    fields = "number,title,state,labels,assignees,milestone,updatedAt,closedAt,url,isPinned"
    # The standup's work grain reads the design card an issue's body names; its
    # suggestion and its Agenda read an open issue's age, as the CLI's read does.
    if body:
        fields += ",body,createdAt"
    cmd = ["gh", "issue", "list", "--repo", repo, "--state", state, "--limit", limit, "--json", fields]
    if not all_items:
        cmd += ["--assignee", "@me"]
    try:
        result = run_read(cmd, 30)
    except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
        return [], f"{repo}: {did_not_answer('gh', exc)}"
    if result.returncode != 0:
        why = (result.stderr or "").strip().splitlines()
        return [], gh_repo_reason(repo, why[0] if why else "")
    try:
        return json.loads(result.stdout or "[]"), None
    except ValueError:
        return [], f"{repo}: gh answered with something that is not JSON"


def _gh_labels(repo: str) -> tuple[list[dict], str | None]:
    """``gh label list`` -- name and description, the data the worker rule reads.

    The standup (agent/solitaire/standup.py) finds its workers here: a label
    whose description starts with WORKER_LABEL_PREFIX. Same timeout, same
    failure sentences as ``_gh_issues``.
    """
    cmd = ["gh", "label", "list", "--repo", repo, "--limit", "200", "--json", "name,description"]
    try:
        result = run_read(cmd, 30)
    except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
        return [], f"{repo}: {did_not_answer('gh', exc)}"
    if result.returncode != 0:
        why = (result.stderr or "").strip().splitlines()
        return [], gh_repo_reason(repo, why[0] if why else "")
    try:
        return json.loads(result.stdout or "[]"), None
    except ValueError:
        return [], f"{repo}: gh answered with something that is not JSON"


def _worker_of(labels: list[dict]) -> str:
    """The first label whose description routes the issue to a worker."""
    for lab in labels:
        if str(lab.get("description") or "").startswith(WORKER_LABEL_PREFIX):
            return lab.get("name", "")
    return ""


def _github_work_items(org: str, projects: list[dict], all_items: bool, state: str = "open") -> WorkItemsResponse:
    if state not in GH_ISSUE_STATES:
        state = "open"
    repos = tracker_repos(org, projects)
    if not repos:
        return WorkItemsResponse(
            count=0,
            items=[],
            reason="This GitHub space names no repository -- give the address a repo, or add one to projects.",
        )
    # Sorted by the RAW timestamp, sliced to a date only for display -- two
    # same-day issues still order by the minute (the test that caught this).
    stamped: list[tuple[tuple[str, str], WorkItemInfo]] = []
    failures: list[str] = []
    for repo in repos:
        rows, why = _gh_issues(repo, all_items, state)
        if why:
            failures.append(why)
            continue
        short = repo.split("/", 1)[1]
        for r in rows:
            labels = [lab.get("name", "") for lab in (r.get("labels") or [])]
            kind = next((_LABEL_TO_TYPE[lab] for lab in labels if lab in _LABEL_TO_TYPE), "Issue")
            milestone = (r.get("milestone") or {}).get("title", "") if r.get("milestone") else ""
            raw = str(r.get("updatedAt", ""))
            is_closed = str(r.get("state", "open")).lower() == "closed"
            closed_raw = str(r.get("closedAt") or "") if is_closed else ""
            # Open rows first (newest update first), then closed rows (newest
            # close first): the key's first element is the lane.
            key = ("0", closed_raw) if is_closed else ("1", raw)
            stamped.append(
                (
                    key,
                    WorkItemInfo(
                        labels=labels,
                        worker=_worker_of(r.get("labels") or []),
                        closed=closed_raw[:10],
                        pinned=bool(r.get("isPinned")),
                        id=int(r.get("number", 0)),
                        title=r.get("title", ""),
                        type=kind,
                        state="closed" if is_closed else "open",
                        project=short,
                        sprint=milestone,
                        updated=raw[:10],
                        url=r.get("url", ""),
                        assignee=", ".join(a.get("login", "") for a in (r.get("assignees") or [])),
                    ),
                )
            )
    stamped.sort(key=lambda t: t[0], reverse=True)
    items = [i for _, i in stamped]
    log_writer.write_log("CMD", "agent/work-items", f"{len(items)} issues (gh, all={int(all_items)}, state={state})")
    reason = failures[0] if (failures and not items) else None
    return WorkItemsResponse(count=len(items), items=items, reason=reason)


# GET /api/issue-report -- the pane's REPORTS: how the product's
# backlog stands, in GitHub's own vocabulary -- open/closed, severities, kinds,
# milestones -- never an ADO word in a gh costume. Tracker-gated like the rest.
class MilestoneCount(BaseModel):
    title: str
    open: int


class IssueReport(BaseModel):
    supported: bool = True
    open: int = 0
    closed: int = 0
    closed_recent: int = 0
    sev: dict[str, int] = {}
    kind: dict[str, int] = {}
    milestones: list[MilestoneCount] = []
    reason: str | None = None


def _github_issue_report(org: str, projects: list[dict]) -> IssueReport:
    """The report as ``gh issue list --state all`` counts it, one call per repo.
    No route calls it any more -- ``/issue-report`` reads the Studio ledger's
    entry -- it stays as the rule the ledger's GraphQL counting is held to
    (``Tests/test_ledger.py`` feeds both the same backlog and asserts one report)."""
    repos = tracker_repos(org, projects)
    if not repos:
        return IssueReport(reason="This GitHub space names no repository.")
    from datetime import datetime, timedelta

    week_ago = datetime.now(UTC) - timedelta(days=7)
    rep = IssueReport()
    mil: dict[str, int] = {}
    failures: list[str] = []
    for repo in repos:
        cmd = [
            "gh",
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "all",
            "--limit",
            "1000",
            "--json",
            "state,labels,milestone,closedAt",
        ]
        try:
            result = run_read(cmd, 30)
        except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
            failures.append(f"{repo}: {did_not_answer('gh', exc)}")
            continue
        if result.returncode != 0:
            why = (result.stderr or "").strip().splitlines()
            failures.append(gh_repo_reason(repo, why[0] if why else ""))
            continue
        try:
            rows = json.loads(result.stdout or "[]")
        except ValueError:
            failures.append(f"{repo}: gh answered with something that is not JSON")
            continue
        for r in rows:
            labels = [lab.get("name", "") for lab in (r.get("labels") or [])]
            if str(r.get("state", "")).upper() == "CLOSED":
                rep.closed += 1
                closed_at = str(r.get("closedAt") or "")
                if closed_at:
                    try:
                        when = datetime.fromisoformat(closed_at)
                        if when >= week_ago:
                            rep.closed_recent += 1
                    except ValueError:
                        pass
                continue
            rep.open += 1
            for lab in labels:
                if lab in ("sev1", "sev2", "sev3"):
                    rep.sev[lab] = rep.sev.get(lab, 0) + 1
            k = next((_LABEL_TO_TYPE[lab] for lab in labels if lab in _LABEL_TO_TYPE), None)
            if k:
                key = "feat" if k == "Feature" else "bug"
                rep.kind[key] = rep.kind.get(key, 0) + 1
            m = (r.get("milestone") or {}).get("title", "") if r.get("milestone") else ""
            if m:
                mil[m] = mil.get(m, 0) + 1
    rep.milestones = [MilestoneCount(title=t, open=n) for t, n in sorted(mil.items(), key=lambda x: -x[1])]
    rep.reason = failures[0] if (failures and rep.open == 0 and rep.closed == 0) else None
    log_writer.write_log("CMD", "agent/issue-report", f"open={rep.open} closed={rep.closed}")
    return rep


# GET /api/milestones -- where the work is GOING: one row per GitHub
# milestone, read in one call per repo (``gh api .../milestones?state=all``),
# which carries its own open and closed counts, state, due date and closed
# date. "Reached" is DERIVED, the way a card's state is: every issue closed and
# at least one issue. A reached milestone that is still open on GitHub is the
# one thing left to do on the tracker, so the row says so. Read only: making
# and closing a milestone stays on GitHub. Tracker-gated like the rest.
class Milestone(BaseModel):
    title: str = ""
    number: int = 0
    repo: str = ""
    url: str = ""
    state: str = "open"  # GitHub's: open | closed
    open: int = 0
    closed: int = 0
    due: str = ""  # the day, "" when none is set
    closed_at: str = ""  # the day GitHub closed it, "" while open
    created_at: str = ""  # the day it was made on GitHub
    updated_at: str = ""  # the day GitHub last changed it -- an issue closing in it is one
    reached: bool = False  # every issue closed, and at least one issue


class MilestonesResponse(BaseModel):
    supported: bool = True
    milestones: list[Milestone] = []
    reason: str | None = None


def milestone_reached(open_count: int, closed_count: int) -> bool:
    """The reached rule: at least one issue, and none of them open.

    GitHub's own ``state`` is not consulted -- a milestone nobody closed is
    still reached, and a closed one with an issue reopened in it is not."""
    return closed_count > 0 and open_count == 0


def github_milestone_rows(repo: str) -> tuple[list[Milestone], str | None]:
    """One repo's milestones, every state, in ONE ``gh api`` call: (rows, None),
    or ([], the reason). The one reader both ``GET /api/milestones`` and Team
    Agile's ``GET /api/ritual/milestones`` (agent/solitaire/milestones.py) use."""
    # Query parameters go as flags, never in the URL: on Windows the call runs
    # through cmd.exe (shell=True, for az.cmd), and an unquoted `&` splits the
    # command -- "'per_page' is not recognized as an internal or external
    # command". _gh_json refuses such an argument before it runs.
    rows, why = _gh_json(
        ["gh", "api", "--method", "GET", f"repos/{repo}/milestones", "-f", "state=all", "-F", "per_page=100"]
    )
    if why:
        return [], gh_repo_reason(repo, why)
    short = repo.split("/", 1)[1]
    out: list[Milestone] = []
    for r in rows or []:
        n_open = int(r.get("open_issues") or 0)
        n_closed = int(r.get("closed_issues") or 0)
        out.append(
            Milestone(
                title=str(r.get("title", "")),
                number=int(r.get("number") or 0),
                repo=short,
                url=str(r.get("html_url", "")),
                state=str(r.get("state", "open")).lower(),
                open=n_open,
                closed=n_closed,
                due=str(r.get("due_on") or "")[:10],
                closed_at=str(r.get("closed_at") or "")[:10],
                created_at=str(r.get("created_at") or "")[:10],
                updated_at=str(r.get("updated_at") or "")[:10],
                reached=milestone_reached(n_open, n_closed),
            )
        )
    return out, None


def _github_milestones(org: str, projects: list[dict]) -> MilestonesResponse:
    repos = tracker_repos(org, projects)
    if not repos:
        return MilestonesResponse(reason="This GitHub space names no repository.")
    rows_out: list[Milestone] = []
    failures: list[str] = []
    for repo in repos:
        rows, why = github_milestone_rows(repo)
        if why:
            failures.append(why)
            continue
        rows_out += rows
    resp = MilestonesResponse(milestones=rows_out)
    resp.reason = failures[0] if (failures and not rows_out) else None
    log_writer.write_log(
        "CMD", "agent/milestones", f"{len(rows_out)} milestones, {sum(1 for m in rows_out if m.reached)} reached (gh)"
    )
    return resp


# GET /api/issue/{number} -- the pane's READING ROOM: the body,
# the thread and the timeline's high signal, read through gh and dispatched by
# the space's address like every tracker seam. "List and details" was the
# walk's verdict; this is the details half. Read, then act, one place -- the
# page's actions run the same verbs the bridge already carries.
class IssueComment(BaseModel):
    author: str = ""
    when: str = ""
    body: str = ""


class TimelineItem(BaseModel):
    kind: str = ""  # "commit" | "pr" | "xref"
    text: str = ""
    url: str = ""
    when: str = ""


class IssueDetail(BaseModel):
    supported: bool = True
    number: int = 0
    title: str = ""
    state: str = ""
    body: str = ""
    author: str = ""
    created: str = ""
    closed: str = ""
    url: str = ""
    labels: list[str] = []
    kind: str = "Issue"
    milestone: str = ""
    assignee: str = ""
    repo: str = ""
    # GitHub's own pin: the reading room says so beside the state.
    pinned: bool = False
    comments: list[IssueComment] = []
    timeline: list[TimelineItem] = []
    reason: str | None = None


CMD_METACHARS = "&|<>"


def unsafe_for_shell(cmd: list[str]) -> str | None:
    """The first argument cmd.exe would split, or None. The gh calls run
    through a shell on Windows (az.cmd needs it), so a `&` in a URL is a
    second command there. Query parameters travel as -f/-F flags."""
    for arg in cmd:
        if any(ch in arg for ch in CMD_METACHARS):
            return arg
    return None


def _gh_json(cmd: list[str], timeout: int = 30):
    """One gh call, answered as (parsed JSON, why-not). The same three
    failure sentences every gh read in this file speaks."""
    bad = unsafe_for_shell(cmd)
    if bad is not None:
        return None, f"refused before running: argument {bad!r} would be split by cmd.exe on Windows"
    try:
        result = run_read(cmd, timeout)
    except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
        return None, did_not_answer("gh", exc)
    if result.returncode != 0:
        why = (result.stderr or "").strip().splitlines()
        return None, why[0] if why else "gh returned an error"
    try:
        return json.loads(result.stdout or "null"), None
    except ValueError:
        return None, "gh answered with something that is not JSON"


def _github_issue_detail(org: str, projects: list[dict], number: int, short: str) -> IssueDetail:
    repos = tracker_repos(org, projects)
    if not repos:
        return IssueDetail(reason="This GitHub space names no repository.")
    # The Backlog row says which repo its issue lives in (the short name);
    # with no hint, a one-repo space needs none and a many-repo space gets
    # the first -- the row always passes the hint.
    repo = repos[0]
    if short:
        repo = next((r for r in repos if r.split("/", 1)[1] == short), repo)
    row, why = _gh_json(
        [
            "gh",
            "issue",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "number,title,state,body,author,createdAt,closedAt,url,labels,milestone,assignees,comments,isPinned",
        ]
    )
    if why:
        return IssueDetail(reason=f"{repo}: {why}")
    labels = [lab.get("name", "") for lab in (row.get("labels") or [])]
    detail = IssueDetail(
        number=int(row.get("number", 0)),
        title=row.get("title", ""),
        state=str(row.get("state", "")).lower(),
        body=row.get("body", "") or "",
        author=(row.get("author") or {}).get("login", ""),
        created=str(row.get("createdAt", ""))[:10],
        closed=str(row.get("closedAt") or "")[:10],
        url=row.get("url", ""),
        labels=labels,
        kind=next((_LABEL_TO_TYPE[lab] for lab in labels if lab in _LABEL_TO_TYPE), "Issue"),
        milestone=(row.get("milestone") or {}).get("title", "") if row.get("milestone") else "",
        assignee=", ".join(a.get("login", "") for a in (row.get("assignees") or [])),
        repo=repo.split("/", 1)[1],
        pinned=bool(row.get("isPinned")),
        comments=[
            IssueComment(
                author=(c.get("author") or {}).get("login", ""),
                when=str(c.get("createdAt", ""))[:10],
                body=c.get("body", "") or "",
            )
            for c in (row.get("comments") or [])
        ],
    )
    # The timeline is best-effort: the page reads fine without it, so a
    # failure here says nothing -- the body and thread are the record.
    events, _ = _gh_json(["gh", "api", f"repos/{repo}/issues/{number}/timeline?per_page=100"])
    for ev in events or []:
        kind = ev.get("event", "")
        when = str(ev.get("created_at", ""))[:10]
        if kind == "referenced" and ev.get("commit_id"):
            detail.timeline.append(
                TimelineItem(
                    kind="commit",
                    text=str(ev["commit_id"])[:7],
                    url=str(ev.get("commit_url", ""))
                    .replace("api.github.com/repos", "github.com")
                    .replace("/commits/", "/commit/"),
                    when=when,
                )
            )
        elif kind == "cross-referenced":
            src = (ev.get("source") or {}).get("issue") or {}
            if not src:
                continue
            is_pr = "pull_request" in src
            detail.timeline.append(
                TimelineItem(
                    kind="pr" if is_pr else "xref",
                    text=f"#{src.get('number', '')} {src.get('title', '')}".strip(),
                    url=src.get("html_url", ""),
                    when=when,
                )
            )
    log_writer.write_log("CMD", "agent/issue", f"#{number} ({detail.repo}) {len(detail.comments)} comments")
    return detail


@api.get("/issue/{number}", response_model=IssueDetail)
async def get_issue_detail(number: int, repo: str = "", space: str = ""):
    # `space`: a hub design note's thread lives in some product's repo, which
    # need not be the active Space's (Studio S2b) -- read it through the Space
    # whose repos hold it, the same seam the foyer's two routes use.
    org, status, projects = space_scope(load_config(), space)
    if tracker(org) != "github":
        return IssueDetail(supported=False)
    tier, _ = await asyncio.to_thread(_resolve_tier, org, status)
    if tier != 1:
        return IssueDetail(supported=False)
    return await asyncio.to_thread(_github_issue_detail, org, projects, number, repo)


# GET /api/deploys -- the pane's LAST DEPLOY (spec 5c's final row): the
# newest workflow runs per repo, read through gh run list. The CLI's
# Dashboard grew these rows in tracker M1 step 7; this is their web face.
class DeployRun(BaseModel):
    repo: str = ""
    title: str = ""
    status: str = ""  # completed | in_progress | queued
    conclusion: str = ""  # success | failure | cancelled | "" while running
    branch: str = ""
    when: str = ""
    url: str = ""


class DeploysResponse(BaseModel):
    supported: bool = True
    runs: list[DeployRun] = []
    reason: str | None = None


def _github_deploys(org: str, projects: list[dict]) -> DeploysResponse:
    repos = tracker_repos(org, projects)
    if not repos:
        return DeploysResponse(reason="This GitHub space names no repository.")
    runs: list[tuple[str, DeployRun]] = []
    failures: list[str] = []
    for repo in repos:
        rows, why = _gh_json(
            [
                "gh",
                "run",
                "list",
                "--repo",
                repo,
                "--limit",
                "5",
                "--json",
                "displayTitle,workflowName,status,conclusion,headBranch,updatedAt,url",
            ]
        )
        if why:
            failures.append(gh_repo_reason(repo, why))
            continue
        short = repo.split("/", 1)[1]
        for r in rows or []:
            raw = str(r.get("updatedAt", ""))
            runs.append(
                (
                    raw,
                    DeployRun(
                        repo=short,
                        title=r.get("workflowName") or r.get("displayTitle") or "",
                        status=str(r.get("status", "")),
                        conclusion=str(r.get("conclusion") or ""),
                        branch=str(r.get("headBranch", "")),
                        when=raw[:10],
                        url=str(r.get("url", "")),
                    ),
                )
            )
    runs.sort(key=lambda t: t[0], reverse=True)
    resp = DeploysResponse(runs=[r for _, r in runs])
    resp.reason = failures[0] if (failures and not resp.runs) else None
    log_writer.write_log("CMD", "agent/deploys", f"{len(resp.runs)} runs (gh)")
    return resp


def space_scope(cfg: dict, space: str = "") -> tuple[str, str, list[dict]]:
    """(address, status, projects) for the Space a tracker read is ABOUT.

    No ``space``: the active one, exactly as every route here always read it.
    A slug: that Space's own entry in ``spaces[]`` -- the Studio's foyer reads
    each GitHub Space's report and deploys without switching into it (Studio
    S2b; ``docs/modules/studio.md``, "The routes"). The CLI's ``Dashboard``
    takes the same three things off the Space it names. An unknown slug is a
    404 naming it: a foyer row for a Space that is not declared is a bug to
    see, not an empty report to believe.
    """
    if not space:
        return cfg.get("org", ""), cfg.get("status", ""), cfg.get("projects", []) or []
    entry = space_entry(cfg, space)
    return entry.get("org", "") or "", entry.get("status", "") or "", entry.get("projects", []) or []


def space_entry(cfg: dict, space: str) -> dict:
    """The declared ``spaces[]`` entry a ``space`` argument names -- the one
    lookup behind every route that takes one (the tracker reads above, and
    ``GET /api/status``'s folder read). An unknown slug is a 404 naming it."""
    entry = next((s for s in cfg.get("spaces", []) or [] if s.get("slug") == space), None)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"No Space '{space}' is declared.")
    return entry


# ---------------------------------------------------------------------------
# A Space's visibility: whether its repository is public -- whether a
# write there is read by strangers. ONE `gh api repos/{owner}/{repo}` per
# repository, held like the pinned set (status.py) but longer, because a
# repository's visibility changes far less often than its pinned issues. An
# unanswered call is not cached, so the next read asks again; and it is never
# guessed -- what gh does not say is `unknown`. GitHub Spaces only, Tier 1 like
# every tracker read; an Azure DevOps Space, or one with no tracker, has none
# (supported: false): a tenant is not public, and the rule is not asked there.
# ``?refresh=1`` (the Spaces card's Refresh) goes past the cache for the
# Space's repositories -- and past the tier probe's -- the way /env?refresh=1 does.
#
# What is held per repository is one RECORD, not only the word: its
# `visibility`, `has_issues` (whether the repository takes issues -- True,
# False, or None when gh did not say) and `url` (its page on GitHub, "" when
# not said). The same `repos/{repo}` answer carries all three, and so does the
# Studio's ledger query (`hasIssuesEnabled`, `url`), so the Spaces card and the
# Docs tab read them from one place.
VISIBILITY_TTL_SECONDS = 600
_visibility_cache: dict[str, tuple[float, dict]] = {}
_visibility_lock = threading.Lock()


def repo_record(visibility: str, has_issues: object = None, url: object = "") -> dict:
    """The record the visibility cache holds for one repository."""
    return {
        "visibility": visibility,
        "has_issues": has_issues if isinstance(has_issues, bool) else None,
        "url": str(url or ""),
    }


def visibility_cache_clear() -> None:
    """Forget every cached visibility. Called by tests."""
    with _visibility_lock:
        _visibility_cache.clear()


def visibility_word(raw: object) -> str:
    """gh's answer (PUBLIC | PRIVATE | INTERNAL, any case) as the contract's word.
    INTERNAL -- an enterprise repository -- is not read by strangers, so it is
    private. Anything else, or nothing, is unknown."""
    text = str(raw or "").strip().lower()
    if text == "public":
        return visibility_public()
    if text in ("private", "internal"):
        return visibility_private()
    return visibility_unknown()


def cached_repo_record(repo: str) -> dict | None:
    """``owner/name``'s held record while it is inside the TTL, else None. Asks
    nothing: a reader that only wants what is already known calls this."""
    with _visibility_lock:
        hit = _visibility_cache.get(repo)
    if hit is not None and (time.monotonic() - hit[0]) < VISIBILITY_TTL_SECONDS:
        return dict(hit[1])
    return None


def gh_repo_record(repo: str, refresh: bool = False) -> dict:
    """``owner/name``'s record -- visibility, has_issues, url. Blocking: one
    ``gh api repos/{repo}`` when nothing is held. ``refresh`` drops this
    repository's held record and asks gh again. A record whose visibility is
    unknown is answered but never held."""
    if refresh:
        with _visibility_lock:
            _visibility_cache.pop(repo, None)
    hit = cached_repo_record(repo)
    if hit is not None:
        return hit
    data, why = _gh_json(["gh", "api", f"repos/{repo}"])
    row = data if (not why and isinstance(data, dict)) else {}
    record = repo_record(visibility_word(row.get("visibility")), row.get("has_issues"), row.get("html_url"))
    remember_repo_record(repo, record)
    return record


def _gh_repo_visibility(repo: str, refresh: bool = False) -> str:
    """``owner/name``'s visibility, as the contract's word. Blocking. ``refresh``
    drops this repository's cached answer and asks gh again."""
    return gh_repo_record(repo, refresh)["visibility"]


def remember_repo_record(repo: str, record: dict, age: float = 0.0) -> None:
    """Hold a record -- from ``repos/{repo}``, or one another read already had
    (the Studio's ledger asks visibility, ``hasIssuesEnabled`` and ``url`` in
    its one GraphQL call) -- under one rule: an unknown visibility is never
    held, and a held record is good for ``VISIBILITY_TTL_SECONDS`` from when it
    was read: ``age`` seconds ago (a record the ledger kept on disk)."""
    if record.get("visibility") != visibility_unknown() and 0 <= age < VISIBILITY_TTL_SECONDS:
        with _visibility_lock:
            _visibility_cache[repo] = (time.monotonic() - age, dict(record))


def fold_visibility(words: list[str]) -> str:
    """One Space's visibility from its repositories': public when ANY is (a
    write may land there), private when ALL are, unknown otherwise -- and
    unknown for a Space that names none."""
    if visibility_public() in words:
        return visibility_public()
    if words and all(w == visibility_private() for w in words):
        return visibility_private()
    return visibility_unknown()


class RepoVisibility(BaseModel):
    repo: str
    visibility: str


class SpaceVisibility(BaseModel):
    # False for a Space whose tracker is not GitHub: it has no visibility.
    supported: bool = True
    # public | private | unknown (consts.json `visibility`); "" when unsupported.
    visibility: str = ""
    repos: list[RepoVisibility] = []


def _github_visibility(org: str, projects: list[dict], tier: int, refresh: bool = False) -> SpaceVisibility:
    repos = tracker_repos(org, projects)
    if tier != 1:
        # The tracker is not asked below Tier 1, so it has not answered.
        rows = [RepoVisibility(repo=r, visibility=visibility_unknown()) for r in repos]
    else:
        rows = [RepoVisibility(repo=r, visibility=_gh_repo_visibility(r, refresh)) for r in repos]
    return SpaceVisibility(visibility=fold_visibility([r.visibility for r in rows]), repos=rows)


@api.get("/visibility", response_model=SpaceVisibility)
async def get_visibility(space: str = "", refresh: int = 0):
    """The Space's repository visibility: the active Space with no argument,
    the named one with ``space`` (the foyer's rows, without switching).
    ``?refresh=1`` asks gh again for this Space's repositories."""
    org, status, projects = space_scope(load_config(), space)
    if tracker(org) != "github":
        return SpaceVisibility(supported=False)
    tier, _ = await asyncio.to_thread(_resolve_tier, org, status, bool(refresh))
    return await asyncio.to_thread(_github_visibility, org, projects, tier, bool(refresh))


@api.get("/deploys", response_model=DeploysResponse)
async def get_deploys(space: str = ""):
    org, status, projects = space_scope(load_config(), space)
    if tracker(org) != "github":
        return DeploysResponse(supported=False)
    tier, _ = await asyncio.to_thread(_resolve_tier, org, status)
    if tier != 1:
        return DeploysResponse(supported=False)
    return await asyncio.to_thread(_github_deploys, org, projects)


@api.get("/issue-report", response_model=IssueReport)
async def get_issue_report(space: str = "", refresh: int = 0):
    """The pane's issue report, read from the Studio ledger's entry for the Space
    and not from ``gh`` here: warm, no ``gh`` call at all; cold (nothing kept, or
    the entry past ``VISIBILITY_TTL_SECONDS``), one ledger read of this Space.
    ``?refresh=1`` reads past the kept entry, as the ledger's own ``?refresh=1``
    does. The ledger resolves the tier itself (``supported: false`` below it)."""
    cfg = load_config()
    org, status, projects = space_scope(cfg, space)
    if tracker(org) != "github":
        return IssueReport(supported=False)
    from ..studio import ledger  # here: the ledger imports this module

    slug = space or str(cfg.get("activeSpace") or "")
    entry = {"slug": slug or ACTIVE_LEDGER_KEY, "org": org, "status": status, "projects": projects}
    return await asyncio.to_thread(ledger.read_space_report, entry, bool(refresh))


@api.get("/milestones", response_model=MilestonesResponse)
async def get_milestones():
    cfg = load_config()
    org = cfg.get("org", "")
    if tracker(org) != "github":
        return MilestonesResponse(supported=False)
    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))
    if tier != 1:
        return MilestonesResponse(supported=False)
    return await asyncio.to_thread(_github_milestones, org, cfg.get("projects", []))


@api.get("/work-items", response_model=WorkItemsResponse)
async def get_work_items(all: int = 0, state: str = "open"):
    cfg = load_config()
    org = cfg.get("org", "")
    projects = cfg.get("projects", [])

    # Tier gate: work items are tracker-derived — Tier 1 only (docs/CLI.md, "Tiers: what
    # works without ADO"). The probe underneath already speaks the board's own tool.
    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))
    if tier != 1 or not org:
        return WorkItemsResponse(count=0, items=[])

    # WHICH tracker answers follows the address (D-G2).
    if tracker(org) == "github":
        return await asyncio.to_thread(_github_work_items, org, projects, bool(all), state)

    # The same resolver the other two routes use, so all three answer the
    # question the same way the CLI does. This route degrades further than they
    # do -- ADO's own @Me still names the signed-in user -- so an unresolved
    # identity is reported rather than fatal, and the query still runs.
    email, _src = await asyncio.to_thread(resolve_identity)
    missing_identity = not email
    if missing_identity:
        warn_no_identity("agent/work-items")

    assigned_filter = f"[System.AssignedTo] = '{email}'" if email else "[System.AssignedTo] = @Me"
    wiql = (
        "SELECT [System.Id],[System.Title],[System.State],[System.WorkItemType],"
        "[System.TeamProject],[System.IterationPath],[System.ChangedDate] FROM WorkItems "
        f"WHERE {assigned_filter} "
        "AND [System.State] NOT IN ('Closed','Done','Removed','Resolved') "
        "ORDER BY [System.ChangedDate] DESC"
    )

    names = [p.get("name", "") for p in projects if p.get("name", "")]
    if not names:
        reason = no_projects_reason(cfg.get("activeSpace", ""))
        log_writer.write_log("WARN", "agent/work-items", reason)
        return WorkItemsResponse(count=0, items=[], reason=reason)

    all_items: list[WorkItemInfo] = []
    seen_ids: set[int] = set()
    failures: list[str] = []
    for proj_name in names:
        rows, failed = await asyncio.to_thread(_az_wiql, org, proj_name, wiql)
        if failed:
            failures.append(failed)
        for row in rows:
            f = row.get("fields", {})
            wi_id = row.get("id", 0)
            if wi_id in seen_ids:
                continue
            seen_ids.add(wi_id)
            sprint_path = f.get("System.IterationPath", "")
            sprint_segs = re.split(r"[/\\]", sprint_path)
            sprint = sprint_segs[-1].strip() if sprint_segs else sprint_path
            changed = f.get("System.ChangedDate", "")[:10]
            actual_proj = f.get("System.TeamProject", proj_name)
            proj_encoded = actual_proj.replace(" ", "%20")
            url = f"{org}/{proj_encoded}/_workitems/edit/{wi_id}"
            all_items.append(
                WorkItemInfo(
                    id=wi_id,
                    title=f.get("System.Title", ""),
                    type=f.get("System.WorkItemType", ""),
                    state=f.get("System.State", ""),
                    project=actual_proj,
                    sprint=sprint,
                    updated=changed,
                    url=url,
                )
            )

    all_items.sort(key=lambda x: x.updated, reverse=True)
    log_writer.write_log("CMD", "agent/work-items", f"{len(all_items)} items")
    # A reason only when there is nothing to show AND something to fix: @Me may
    # well have answered, and a populated list with a warning on it reads as a
    # failure that did not happen. Identity first, then the first call that failed.
    reason = None
    if not all_items:
        if missing_identity:
            reason = IDENTITY_MISSING_REASON
        elif failures:
            reason = failures[0]
    return WorkItemsResponse(count=len(all_items), items=all_items, reason=reason)


# ---------------------------------------------------------------------------
# GET /api/dashboard -- aggregated dashboard (last 20 pipeline runs per project filtered
# to repo, + repo health + counts)
# ---------------------------------------------------------------------------
class PipelineRun(BaseModel):
    pipeline_name: str
    result: str  # succeeded | failed | canceled | partiallySucceeded | running
    branch: str
    finished: str | None  # ISO or None if still running
    url: str
    build_id: int


class ProjectPipelines(BaseModel):
    project: str
    repo: str
    runs: list[PipelineRun]
    reason: str | None = None


class ProjectInfo(BaseModel):
    project: str
    repo: str


class RepoHealth(BaseModel):
    last_commit: str | None
    unpushed: int
    uncommitted: int
    recent_errors: int


class DashboardResponse(BaseModel):
    tier: int
    projects: list[ProjectInfo]  # names only; runs fetched lazily via /dashboard/pipelines/{project}
    repo: RepoHealth
    pr_count: int
    work_item_count: int
    prompt_count: int
    reason: str | None = None


def _az_pipeline_runs(org: str, project: str, top: int = 5) -> tuple[list[dict], str | None]:
    """``az pipelines runs list`` -- ``(rows, None)``, or ``([], why)``."""
    cmd = ["az", "pipelines", "runs", "list", "--org", org, "--project", project, "--top", str(top), "--output", "json"]
    return _az_json(cmd, "agent/dashboard", "pipelines runs list", project)


def _get_repo_health() -> RepoHealth:
    """Gather local git repo health stats."""
    try:
        cwd = str(hub_root())
        # %at on this machine's clock, the same string Get-DailyDashboard.ps1
        # prints -- not %ai in the author's zone.
        last = run_read(["git", "log", "-1", "--format=%at%x09%an"], 5, shell=False, cwd=cwd)
        last_commit = None
        if last.returncode == 0 and last.stdout.strip():
            at, _, who = last.stdout.strip().partition("\t")
            try:
                last_commit = f"{local_stamp(float(at))} ({who})"
            except ValueError:
                last_commit = None

        unpushed = run_read(["git", "log", "--oneline", "@{u}..HEAD"], 5, shell=False, cwd=cwd)
        unpushed_count = (
            len([ln for ln in unpushed.stdout.splitlines() if ln.strip()]) if unpushed.returncode == 0 else 0
        )

        uncommitted = run_read(["git", "status", "--porcelain"], 5, shell=False, cwd=cwd)
        uncommitted_count = (
            len([ln for ln in uncommitted.stdout.splitlines() if ln.strip()]) if uncommitted.returncode == 0 else 0
        )

        # Count recent errors from log files
        recent_errors = 0
        cutoff = time.time() - 86400  # 24 hours ago
        for log_file in REPO_ROOT.glob("usage.*.log"):
            try:
                for line in log_file.read_text(encoding="utf-8-sig", errors="replace").splitlines():
                    parts = line.split("\t")
                    if len(parts) >= 2 and parts[1] == "ERR":
                        try:
                            ts = time.mktime(time.strptime(parts[0][:19], "%Y-%m-%dT%H:%M:%S"))
                            if ts >= cutoff:
                                recent_errors += 1
                        except ValueError:
                            pass
            except OSError:
                pass

        return RepoHealth(
            last_commit=last_commit,
            unpushed=unpushed_count,
            uncommitted=uncommitted_count,
            recent_errors=recent_errors,
        )
    except Exception:  # noqa: BLE001 -- a repo the dashboard cannot read is a row of zeros, not a failed dashboard
        return RepoHealth(last_commit=None, unpushed=0, uncommitted=0, recent_errors=0)


@api.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard():
    cfg = load_config()
    org = cfg.get("org", "")
    projects = cfg.get("projects", [])

    # Resolve tier from environment capability (shared with /api/env). This is
    # the authoritative gate: ADO-derived data is only fetched at Tier 1.
    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))

    current_dir, _ = resolve_dirs()
    prompt_count = len(list(current_dir.glob("*.prompt.md"))) if current_dir.exists() else 0

    # Repo health (always available)
    repo = await asyncio.to_thread(_get_repo_health)

    # ADO calls only at Tier 1 — never contact ADO for a local/unreachable org.
    # Pipeline runs are NOT fetched here — that's the expensive, per-project az
    # call and the UI only ever shows one project's runs at a time (the active
    # tab). Fetching all N projects' runs upfront was pure waste for the N-1
    # tabs a session usually never opens, and made every dashboard load pay for
    # N concurrent `az pipelines runs list` calls. Runs are now fetched lazily,
    # one project at a time, via GET /dashboard/pipelines/{project} — see below.
    project_list: list[ProjectInfo] = [
        ProjectInfo(project=p["name"], repo=p.get("repo", ""))
        for p in projects
        if p.get("hasRepo", True) and p.get("name", "")
    ]
    pr_count = 0
    work_item_count = 0
    reason = None
    failures: list[str] = []

    email = ""

    if tier == 1 and org and not any(p.get("name", "") for p in projects):
        reason = no_projects_reason(cfg.get("activeSpace", ""))
        log_writer.write_log("WARN", "agent/dashboard", reason)
    elif tier == 1 and org:
        # Who "me" is -- one resolver, three routes. This route used to drop
        # every PR target when cfg["email"] was empty (`if pn and rn and
        # email`), so pr_count was 0 with nothing said anywhere.
        #
        email, _src = await asyncio.to_thread(resolve_identity)
        if not email:
            warn_no_identity("agent/dashboard")
            reason = IDENTITY_MISSING_REASON

        # No separate token warm-up needed here: _resolve_tier above already ran
        # _probe_tracker (on an ADO board, an `az devops project list` call), which primes az's token
        # cache before we reach this fan-out.
        #
        # Cap concurrent az CLI subprocesses. Unlimited gather is fast on platforms
        # where az's token cache handles concurrent access cleanly (e.g. macOS
        # keychain-backed), but on Windows the flat-file cache contends under an
        # unbounded fan-out — reproduced 6 concurrent calls taking 33s vs ~6s solo,
        # enough to trip the 30s subprocess timeout. A small cap keeps most of the
        # parallelism win without the pileup.
        az_limit = asyncio.Semaphore(3)

        async def _az_call(fn, *args):
            async with az_limit:
                return await asyncio.to_thread(fn, *args)

        async def count_prs():
            targets = [(p.get("name", ""), p.get("repo", "")) for p in projects if p.get("hasRepo", True)]
            targets = [(pn, rn) for pn, rn in targets if pn and rn and email]
            results = await asyncio.gather(
                *[_az_call(_az_pr_list, org, pn, rn, "--creator", email) for pn, rn in targets]
            )
            failures.extend(why for _rows, why in results if why)
            return sum(len(rows) for rows, _why in results)

        async def count_work_items():
            wiql = (
                "SELECT [System.Id] FROM WorkItems "
                "WHERE [System.AssignedTo] = @Me "
                "AND [System.State] NOT IN ('Closed','Done','Removed','Resolved')"
            )
            names = [p.get("name", "") for p in projects if p.get("name", "")]
            results = await asyncio.gather(*[_az_call(_az_wiql, org, pn, wiql) for pn in names])
            failures.extend(why for _rows, why in results if why)
            seen_ids: set[int] = set()
            for rows, _why in results:
                for row in rows:
                    seen_ids.add(row.get("id", 0))
            return len(seen_ids)

        pr_count, work_item_count = await asyncio.gather(count_prs(), count_work_items())
        # Identity first; else the first call that failed, when the counts
        # have nothing to show for it.
        if reason is None and failures and pr_count == 0 and work_item_count == 0:
            reason = failures[0]

    log_writer.write_log(
        "CMD", "agent/dashboard", f"tier={tier} projects={len(project_list)} prs={pr_count} items={work_item_count}"
    )
    return DashboardResponse(
        tier=tier,
        projects=project_list,
        repo=repo,
        pr_count=pr_count,
        work_item_count=work_item_count,
        prompt_count=prompt_count,
        reason=reason,
    )


@api.get("/dashboard/pipelines/{project}", response_model=ProjectPipelines)
async def get_dashboard_pipelines(project: str, repo: str = ""):
    """Lazy per-project pipeline runs, fetched on tab click rather than upfront
    (see get_dashboard). RTK Query caches this per project+repo argument on the
    client, so switching back to a previously-viewed tab costs nothing.
    `repo` disambiguates when one ADO project has multiple configured repos."""
    cfg = load_config()
    org = cfg.get("org", "")
    projects = cfg.get("projects", [])

    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))
    proj_cfg = next(
        (p for p in projects if p.get("name") == project and (not repo or p.get("repo", "") == repo)),
        None,
    )
    repo_name = proj_cfg.get("repo", "") if proj_cfg else ""

    if tier != 1 or not org or not proj_cfg:
        return ProjectPipelines(project=project, repo=repo_name, runs=[])

    # top=8: UI shows 3 rows (VISIBLE_ROWS) with an expand toggle; 8 leaves headroom
    # for the repo filter below to find matches without overfetching history.
    runs_raw, failed = await asyncio.to_thread(_az_pipeline_runs, org, project, 8)
    all_runs = []
    filtered_runs = []
    for r in runs_raw:
        defn = r.get("definition", {})
        name = defn.get("name", "Unknown")[:30]
        result_str = r.get("result") or r.get("status", "running")
        branch = (r.get("sourceBranch", "") or "").replace("refs/heads/", "").strip()
        finished = r.get("finishTime")
        build_id = r.get("id", 0)
        proj_encoded = project.replace(" ", "%20")
        url = f"{org}/{proj_encoded}/_build/results?buildId={build_id}"
        run = PipelineRun(
            pipeline_name=name,
            result=result_str,
            branch=branch,
            finished=finished,
            url=url,
            build_id=build_id,
        )
        all_runs.append(run)
        r_repo = (r.get("repository", {}) or {}).get("name", "")
        if repo_name and r_repo and r_repo == repo_name:
            filtered_runs.append(run)
    runs = filtered_runs if filtered_runs else all_runs

    log_writer.write_log("CMD", "agent/dashboard-pipelines", f"project={project} repo={repo_name} runs={len(runs)}")
    return ProjectPipelines(
        project=project, repo=repo_name, runs=runs, reason=failed if (failed and not runs) else None
    )
