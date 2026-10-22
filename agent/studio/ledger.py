"""The Spaces card's ledger: every GitHub Space's facts in one read.

The foyer used to ask three routes per GitHub row -- ``/issue-report``,
``/deploys`` and ``/visibility`` -- each a ``gh`` subprocess, each resolving
the tier with a ``gh api users/<owner>`` probe of its own, nothing kept between
loads: 60 subprocesses and 6.7 s for ten GitHub Spaces on a cold agent, 20 on
every mount after. This is the one read that replaced them, on the rule 6NEP
set for the Design tab: list once, fetch a detail when it is asked for, cache
the bytes.

``read_ledger(cfg, refresh=)`` answers ``{slug: SpaceLedger}`` for every
declared GitHub Space:

1. **One GraphQL call for every repository**, one alias each
   (``repository(owner:, name:)``): its ``visibility``, its open and closed
   issue counts, its open issues' labels and milestone, and its most recently
   updated closed issues' ``closedAt`` -- everything ``IssueReport`` counts.
   Chunked at ``LEDGER_CHUNK`` repositories a call. A repository GitHub cannot
   resolve fails alone (its alias is null, the others answer).
2. **The newest runs through ``gh run list``**, one per repository, in
   parallel: GraphQL has no listing of a repository's workflow runs across
   branches (a commit's check suites are one branch's head), and the row's
   "last deploy" is the newest run anywhere. ``accounting._github_deploys`` is
   that read, unchanged.
3. **Kept on disk per Space** (``agent/core/disk_cache.py``,
   ``ledger-<version>/<slug>.json``) for ``LEDGER_TTL_SECONDS`` -- the visibility
   cache's 600 s, as the floor -- keyed by the Space's repositories and status,
   so a changed address is a miss. A foyer mounted twice in ten minutes, or
   after an agent restart, reads GitHub once. ``refresh`` (the card's Refresh)
   is the one thing that asks again. A Space whose read did not fully answer is
   not kept, so the next mount asks again, as the visibility cache never holds
   an unknown.

**No tier probe on the way.** The old routes resolved the tier per request,
and a GitHub probe is itself a ``gh`` call. Here the tier's inputs are the
hub, git, the Space's status and whether the tracker answers -- and the
GraphQL call IS the tracker answering. Only when that call does not answer at
all is the tier resolved the old way (``accounting._resolve_tier``), so a
signed-out ``gh`` still reads as "not connected" and a timeout as its reason.
The answer seeds ``accounting``'s visibility cache too -- each repository's
whole record: visibility, ``has_issues`` and ``url`` -- and a disk hit seeds it
again after a restart, so the shell's ``/visibility`` read and the Docs tab ask
nothing for the same repositories.
"""

from __future__ import annotations

import asyncio
import shutil
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter
from pydantic import BaseModel

from ..ado import accounting, repo_read
from ..ado.accounting import (
    _LABEL_TO_TYPE,
    DeploysResponse,
    IssueReport,
    MilestoneCount,
    RepoVisibility,
    SpaceVisibility,
    fold_visibility,
    gh_repo_reason,
    visibility_word,
)
from ..core import disk_cache, log_writer
from ..core.config import API_PREFIX, hub_root, load_config, tracker, tracker_repos
from ..core.consts import studio_ledger_route, visibility_unknown

# How long a Space's ledger is good for: the visibility cache's own TTL, read
# from it, so the two can never disagree about how stale a foyer may be.
LEDGER_TTL_SECONDS = accounting.VISIBILITY_TTL_SECONDS
# Repositories per GraphQL call. Each asks for up to PAGE open issues with
# their labels; twenty keeps one call well inside GitHub's node limit.
LEDGER_CHUNK = 20
# Issues per page, and how many pages one connection may run to: 1000 rows,
# the ceiling the old ``gh issue list --limit 1000`` read had.
PAGE = 100
MAX_PAGES = 10
# The disk namespace, with a version in it: bump it when SpaceLedger's shape or
# the counting changes, and every Space is read again.
LEDGER_DIR = "ledger-1"
DEPLOY_WORKERS = 8
SEV_LABELS = ("sev1", "sev2", "sev3")

_fetch_lock = threading.Lock()

api = APIRouter()
ROUTE = studio_ledger_route().removeprefix(API_PREFIX)


class SpaceLedger(BaseModel):
    """One GitHub Space's row facts: the same three answers the foyer used to
    ask three routes for, in those routes' own shapes."""

    report: IssueReport
    deploys: DeploysResponse
    visibility: SpaceVisibility


class StudioLedger(BaseModel):
    spaces: dict[str, SpaceLedger] = {}


# -- The one query ----------------------------------------------------------------


def _rows(kind: str, after: str = "") -> str:
    """One issues connection the ledger reads: ``openRows`` (labels and
    milestone) or ``recentRows`` (when each was closed and last updated).
    ``after`` is the cursor argument a later page adds."""
    if kind == "openRows":
        args, nodes = "states: OPEN", "labels(first: 100) { nodes { name } } milestone { title }"
        order = "CREATED_AT"
    else:
        args, nodes = "states: CLOSED", "closedAt updatedAt"
        order = "UPDATED_AT"
    return (
        f"issues({args}, first: {PAGE}{after}, orderBy: {{field: {order}, direction: DESC}}) "
        f"{{ pageInfo {{ hasNextPage endCursor }} nodes {{ {nodes} }} }}"
    )


def _ledger_query(n: int) -> str:
    """``n`` repositories, one alias each, through one fragment. Open issues are
    read newest-created first, as ``gh issue list`` reads them, so milestones
    that tie keep the order they always had; closed ones by last update, so
    every issue closed this week is on the first page (``closedAt`` is never
    after ``updatedAt``)."""
    params = ", ".join(f"$o{i}: String!, $n{i}: String!" for i in range(n))
    parts = "\n".join(f"  r{i}: repository(owner: $o{i}, name: $n{i}) {{ ...ledger }}" for i in range(n))
    return (
        f"query({params}) {{\n{parts}\n}}\n"
        "fragment ledger on Repository {\n"
        "  visibility hasIssuesEnabled url\n"
        "  open: issues(states: OPEN) { totalCount }\n"
        "  closed: issues(states: CLOSED) { totalCount }\n"
        f"  openRows: {_rows('openRows')}\n"
        f"  recentRows: {_rows('recentRows')}\n"
        "}\n"
    )


def _page_query(kind: str) -> str:
    return (
        "query($owner: String!, $name: String!, $after: String!) {\n"
        f"  repository(owner: $owner, name: $name) {{ page: {_rows(kind, ', after: $after')} }}\n"
        "}\n"
    )


def _repo_fields(i: int, repo: str) -> list[str]:
    owner, _, name = repo.partition("/")
    return ["-f", f"o{i}={owner}", "-f", f"n{i}={name}"]


def _week_ago() -> datetime:
    return datetime.now(UTC) - timedelta(days=7)


def _parse_when(raw: object) -> datetime | None:
    try:
        return datetime.fromisoformat(str(raw or ""))
    except ValueError:
        return None


def _more(repo: str, kind: str, conn: dict, week_ago: datetime) -> tuple[list[dict], int]:
    """The rest of one repository's connection, past its first page: (every
    node, the gh calls it took). Open rows run to the end (a backlog past a
    hundred); recent rows only while the page still reaches into this week.
    Both stop at MAX_PAGES. The usual repository needs none of this."""
    nodes = list(conn.get("nodes") or [])
    calls = 0
    info = conn.get("pageInfo") or {}
    owner, _, name = repo.partition("/")
    pages = 1
    while info.get("hasNextPage") and info.get("endCursor") and pages < MAX_PAGES:
        if kind == "recentRows":
            last = _parse_when((nodes[-1] if nodes else {}).get("updatedAt"))
            if last is None or last < week_ago:
                break
        data, why = repo_read._graphql(
            _page_query(kind), ["-f", f"owner={owner}", "-f", f"name={name}", "-f", f"after={info['endCursor']}"]
        )
        calls += 1
        page = ((data or {}).get("repository") or {}).get("page") if not why else None
        if not isinstance(page, dict):
            break
        nodes += page.get("nodes") or []
        info = page.get("pageInfo") or {}
        pages += 1
    return nodes, calls


def _read_repos(repos: list[str]) -> tuple[dict[str, dict], dict[str, str], str | None, int]:
    """({repo: its alias's answer, nodes complete}, {repo: why it failed},
    why the whole call failed, gh calls). One GraphQL call per LEDGER_CHUNK."""
    answers: dict[str, dict] = {}
    errors: dict[str, str] = {}
    calls = 0
    week_ago = _week_ago()
    for start in range(0, len(repos), LEDGER_CHUNK):
        chunk = repos[start : start + LEDGER_CHUNK]
        fields: list[str] = []
        for i, repo in enumerate(chunk):
            fields += _repo_fields(i, repo)
        data, alias_errors, why = repo_read.graphql_aliases(_ledger_query(len(chunk)), fields)
        calls += 1
        if why:
            # The call itself did not answer: say so for this chunk only.
            return answers, errors, why, calls
        for i, repo in enumerate(chunk):
            node = data.get(f"r{i}")
            if not isinstance(node, dict):
                errors[repo] = alias_errors.get(f"r{i}") or "gh returned an error"
                continue
            for kind in ("openRows", "recentRows"):
                conn = node.get(kind) or {}
                nodes, more = _more(repo, kind, conn, week_ago)
                calls += more
                node[kind] = {"nodes": nodes}
            answers[repo] = node
    return answers, errors, None, calls


# -- Counting: the old report's rule, over the GraphQL rows ------------------------


def issue_report(repos: list[str], answers: dict[str, dict], errors: dict[str, str]) -> IssueReport:
    """``IssueReport`` for one Space, counted as ``accounting._github_issue_report``
    counts ``gh issue list --state all``: open and closed are GitHub's totals;
    severities, kinds and milestones are read off the open issues; closed this
    week off the recently closed ones. Tests/test_ledger.py feeds both readers
    the same issues and asserts one report."""
    if not repos:
        return IssueReport(reason="This GitHub space names no repository.")
    week_ago = _week_ago()
    rep = IssueReport()
    mil: dict[str, int] = {}
    failures: list[str] = []
    for repo in repos:
        node = answers.get(repo)
        if node is None:
            failures.append(gh_repo_reason(repo, errors.get(repo, "")))
            continue
        rep.open += int((node.get("open") or {}).get("totalCount") or 0)
        rep.closed += int((node.get("closed") or {}).get("totalCount") or 0)
        for row in (node.get("recentRows") or {}).get("nodes") or []:
            when = _parse_when(row.get("closedAt"))
            if when is not None and when >= week_ago:
                rep.closed_recent += 1
        for row in (node.get("openRows") or {}).get("nodes") or []:
            labels = [lab.get("name", "") for lab in ((row.get("labels") or {}).get("nodes") or [])]
            for lab in labels:
                if lab in SEV_LABELS:
                    rep.sev[lab] = rep.sev.get(lab, 0) + 1
            k = next((_LABEL_TO_TYPE[lab] for lab in labels if lab in _LABEL_TO_TYPE), None)
            if k:
                key = "feat" if k == "Feature" else "bug"
                rep.kind[key] = rep.kind.get(key, 0) + 1
            m = (row.get("milestone") or {}).get("title", "") if row.get("milestone") else ""
            if m:
                mil[m] = mil.get(m, 0) + 1
    rep.milestones = [MilestoneCount(title=t, open=n) for t, n in sorted(mil.items(), key=lambda x: -x[1])]
    rep.reason = failures[0] if (failures and rep.open == 0 and rep.closed == 0) else None
    return rep


def _visibility(repos: list[str], answers: dict[str, dict]) -> tuple[SpaceVisibility, dict[str, dict]]:
    """The Space's visibility, and each repository's whole record -- visibility,
    has_issues, url -- held in the visibility cache, so the Docs tab and the
    shell's /visibility read ask nothing for these repositories."""
    rows = []
    records: dict[str, dict] = {}
    for repo in repos:
        node = answers.get(repo) or {}
        word = visibility_word(node.get("visibility"))
        records[repo] = accounting.repo_record(word, node.get("hasIssuesEnabled"), node.get("url"))
        accounting.remember_repo_record(repo, records[repo])
        rows.append(RepoVisibility(repo=repo, visibility=word))
    return SpaceVisibility(visibility=fold_visibility([r.visibility for r in rows]), repos=rows), records


def _unsupported(org: str, projects: list[dict]) -> SpaceLedger:
    """Below Tier 1: what the three routes answered there, with gh not asked."""
    return SpaceLedger(
        report=IssueReport(supported=False),
        deploys=DeploysResponse(supported=False),
        visibility=SpaceVisibility(
            visibility=visibility_unknown(),
            repos=[RepoVisibility(repo=r, visibility=visibility_unknown()) for r in tracker_repos(org, projects)],
        ),
    )


# -- The disk cache ---------------------------------------------------------------


def _cached(slug: str, repos: list[str], status: str) -> SpaceLedger | None:
    entry = disk_cache.get_json(LEDGER_DIR, f"{slug}.json")
    if not entry or entry.get("repos") != repos or entry.get("status") != status:
        return None
    try:
        age = time.time() - float(entry.get("fetchedAt") or 0)
    except (TypeError, ValueError):
        return None
    if not (0 <= age < LEDGER_TTL_SECONDS):
        return None
    try:
        ledger = SpaceLedger.model_validate(entry.get("ledger") or {})
    except ValueError:
        return None
    # An agent restart forgot the visibility cache; the records come back from
    # here, as old as the entry, so the 600 s still counts from the read.
    for repo, record in (entry.get("records") or {}).items():
        if repo in repos and isinstance(record, dict):
            accounting.remember_repo_record(repo, record, age)
    return ledger


def _keep(slug: str, repos: list[str], status: str, ledger: SpaceLedger, records: dict[str, dict]) -> None:
    if ledger.report.reason or ledger.deploys.reason:
        return  # not fully answered: the next mount asks again
    disk_cache.put_json(
        {
            "repos": repos,
            "status": status,
            "fetchedAt": time.time(),
            "ledger": ledger.model_dump(),
            "records": records,
        },
        LEDGER_DIR,
        f"{slug}.json",
    )


def _forget_removed(cfg: dict) -> None:
    """Drop the ledger file of any Space no longer declared, read the way
    ``_read_ledger`` reads the Spaces. Rides a write; never fails it."""
    try:
        declared = {
            f"{space.get('slug')}.json"
            for space in cfg.get("spaces", []) or []
            if space.get("slug") and tracker(str(space.get("org") or "")) == "github"
        }
        folder = disk_cache.cache_path(LEDGER_DIR)
        if folder is None:
            return
        for entry in list(folder.iterdir()):
            if entry.is_file() and not entry.name.startswith(".") and entry.name not in declared:
                entry.unlink(missing_ok=True)
    except Exception:  # noqa: BLE001, S110 -- a prune never fails a write
        pass


# -- The read ---------------------------------------------------------------------


def read_ledger(cfg: dict, refresh: bool = False) -> StudioLedger:
    """Every declared GitHub Space's ledger. Blocking: gh runs here."""
    with _fetch_lock:  # two tabs at once read GitHub once; the second finds the disk warm
        return _read_ledger(cfg, refresh)


def _read_ledger(cfg: dict, refresh: bool) -> StudioLedger:
    started = time.monotonic()
    out: dict[str, SpaceLedger] = {}
    can_reach = hub_root().exists() and shutil.which("git") is not None
    stale: list[tuple[str, str, str, list[dict], list[str]]] = []
    fresh = 0
    for space in cfg.get("spaces", []) or []:
        slug, org = str(space.get("slug") or ""), str(space.get("org") or "")
        if not slug or tracker(org) != "github":
            continue
        status = str(space.get("status") or "")
        projects = space.get("projects", []) or []
        repos = tracker_repos(org, projects)
        if not can_reach or status in ("local", "archive"):
            out[slug] = _unsupported(org, projects)
            continue
        if not repos:
            out[slug] = SpaceLedger(
                report=IssueReport(reason="This GitHub space names no repository."),
                deploys=DeploysResponse(reason="This GitHub space names no repository."),
                visibility=SpaceVisibility(visibility=visibility_unknown()),
            )
            continue
        hit = None if refresh else _cached(slug, repos, status)
        if hit is not None:
            out[slug] = hit
            fresh += 1
            continue
        stale.append((slug, org, status, projects, repos))

    calls = 0
    if stale:
        wanted = list(dict.fromkeys(r for *_, repos in stale for r in repos))
        answers, errors, why, calls = _read_repos(wanted)
        live: list[tuple[str, str, str, list[dict], list[str]]] = []
        for item in stale:
            slug, org, status, projects, repos = item
            if why and not any(r in answers for r in repos):
                # The tracker did not answer at all: ask the tier the old way,
                # so a signed-out gh reads "not connected" rather than an error.
                tier, _ = accounting._resolve_tier(org, status, refresh)
                if tier != 1:
                    out[slug] = _unsupported(org, projects)
                    continue
                errors.update({r: why for r in repos if r not in answers})
            live.append(item)
        with ThreadPoolExecutor(max_workers=DEPLOY_WORKERS) as pool:
            runs = dict(
                zip(
                    [slug for slug, *_ in live],
                    pool.map(lambda it: accounting._github_deploys(it[1], it[3]), live),
                    strict=True,
                )
            )
        calls += sum(len(repos) for *_, repos in live)
        for slug, _org, status, _projects, repos in live:
            visibility, records = _visibility(repos, answers)
            ledger = SpaceLedger(
                report=issue_report(repos, answers, errors),
                deploys=runs[slug],
                visibility=visibility,
            )
            _keep(slug, repos, status, ledger, records)
            out[slug] = ledger
        _forget_removed(cfg)
    log_writer.write_log(
        "CMD",
        "agent/studio/ledger",
        f"{len(out)} GitHub Spaces, {fresh} from the disk cache, {len(stale)} read, {calls} gh calls,"
        f" {time.monotonic() - started:.2f}s{' (refresh)' if refresh else ''}",
    )
    return StudioLedger(spaces=out)


@api.get(ROUTE, response_model=StudioLedger)
async def get_ledger(refresh: int = 0):
    """Every GitHub Space's row facts for the Spaces card, in one read.
    Ungated: the Studio is core (D-S13); each Space's own tier decides whether
    its tracker is asked. ``?refresh=1`` (the card's Refresh) goes past the
    disk cache."""
    return await asyncio.to_thread(read_ledger, load_config(), bool(refresh))
