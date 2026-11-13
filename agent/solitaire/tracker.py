"""The GitHub tracker read both ceremonies share -- the standup and triage.

One reader, so the two cannot drift on what a failed read means: any repo that
fails fails the whole read, and a reader that raised is a tracker that did not
answer. The ceremonies differ only in which issues they ask for.

One read per repo per ``READ_TTL_SECONDS`` (toolkit card QP33). Each gh answer --
a repo's labels, a repo's issues in a state, the signed-in login, the standup's
dates read (``dates``) -- is kept in
memory for the design list's TTL, so the Triage page opened after the standup,
or the standup re-mounted after attending, pays no subprocess. Triage's open
issues are served from the standup's all-states read while it is fresh and
complete (fewer rows than its limit, so every issue is in it): the open ones, in
gh's order, to the open read's limit, without the bodies triage did not ask for
-- exactly the rows ``gh issue list --state open`` would answer. A failed read
is never kept. ``refresh`` (the routes' ``?refresh=1``, the Triage page's Refresh)
reads again and keeps the new answer; a verb run through the bridge forgets
every read (``forget``), because a write may have moved the tracker
(``agent/ado/bridge.py``). docs/modules/solitaire-agile.md, "One tracker read, kept a minute".
"""

from __future__ import annotations

import copy
import time
from collections.abc import Callable

from ..ado import accounting
from ..ado.design import LIST_TTL_SECONDS
from ..core.config import ISSUE_LIMIT_ALL, ISSUE_LIMIT_OPEN, tracker, tracker_repos
from ..core.tier import _resolve_tier

NO_REPO_REASON = "This GitHub space names no repository."

# How long one gh answer is served again: the design list's TTL.
READ_TTL_SECONDS = LIST_TTL_SECONDS
_OPEN = "OPEN"

# key -> (when, the answer). A key is ("labels", repo), ("issues", repo, state,
# body), ("milestones", repo) -- the Milestones tab's read (milestones.py) --
# ("dates", repo, hashes, numbers) -- the standup's commit dates and issue
# timelines (``dates``) -- or ("viewer",).
_reads: dict[tuple, tuple[float, object]] = {}


def forget() -> None:
    """Forget every kept read: a write happened, or a test starts."""
    _reads.clear()


def _fresh(key: tuple) -> object | None:
    hit = _reads.get(key)
    if hit and time.monotonic() - hit[0] < READ_TTL_SECONDS:
        return hit[1]
    return None


def remember(key: tuple, refresh: bool, read: Callable[[], tuple[object, str | None]]) -> tuple[object, str | None]:
    """``read()``'s (answer, reason), kept for the TTL when there is no reason.
    ``refresh`` reads again whatever is kept."""
    if not refresh:
        kept = _fresh(key)
        if kept is not None:
            return kept, None
    answer, why = read()
    if not why:
        _reads[key] = (time.monotonic(), answer)
    return answer, why


def labels(repo: str, refresh: bool = False) -> tuple[list[dict], str | None]:
    rows, why = remember(("labels", repo), refresh, lambda: accounting._gh_labels(repo))
    return copy.deepcopy(rows), why  # a copy: a caller never edits what is kept


def _from_all(repo: str, body: bool) -> list[dict] | None:
    """Every open issue of ``repo`` from a fresh, complete all-states read, as the
    open read would answer them; None when no such read is kept."""
    for with_body in (body, True):
        rows = _fresh(("issues", repo, "all", with_body))
        if rows is None or len(rows) >= ISSUE_LIMIT_ALL:
            continue
        opened = [r for r in rows if str(r.get("state", "")).upper() == _OPEN][:ISSUE_LIMIT_OPEN]
        if with_body and not body:
            opened = [{k: v for k, v in r.items() if k != "body"} for r in opened]
        return opened
    return None


def issues(repo: str, state: str, body: bool = False, refresh: bool = False) -> tuple[list[dict], str | None]:
    """``repo``'s issues in ``state`` (every assignee), kept for the TTL."""
    if not refresh and state == "open":
        derived = _from_all(repo, body)
        if derived is not None and _fresh(("issues", repo, state, body)) is None:
            return copy.deepcopy(derived), None
    rows, why = remember(
        ("issues", repo, state, body), refresh, lambda: accounting._gh_issues(repo, True, state, body=body)
    )
    return copy.deepcopy(rows), why


def _dates_chunk(repo: str, hashes: list[str], numbers: list[int]) -> tuple[object, str | None]:
    """One GraphQL call for one chunk: (the ``repository`` object, None), or
    (None, why). An alias GitHub could not resolve is null in the answer, not a
    failure of the call."""
    from ..ado import repo_read
    from .standup import dates_query

    owner, _, name = repo.partition("/")
    data, _errors, why = repo_read.graphql_aliases(
        dates_query(hashes, numbers), ["-f", f"owner={owner}", "-f", f"name={name}"]
    )
    if why:
        return None, why
    return (data or {}).get("repository") or {}, None


def dates(
    repos: list[str],
    hashes: list[str],
    numbers_by_repo: dict[str, list[int]],
    worker_labels: list[str],
    refresh: bool = False,
) -> tuple[dict | None, dict | None, str | None]:
    """The standup's dates read: (hash -> authored instant or None, issue number
    -> its start, None), or (None, None, why) when any call failed -- the
    standup then counts as it did before the read existed. Every hash is asked
    of every repo (a card does not say which one it was committed to) and dated
    by the first that knows it; an issue is asked of its own repo. One
    ``gh api graphql`` per repo per ``standup.DATES_CHUNK`` aliases, each kept
    for the TTL like every other read here. Never raises."""
    from .standup import DATES_CHUNK, dates_from_answer

    commits: dict[str, str | None] = {h: None for h in hashes}
    starts: dict[int, str] = {}
    try:
        for repo in repos:
            numbers = sorted(set(numbers_by_repo.get(repo, [])))
            asks = [("c", h) for h in hashes] + [("i", n) for n in numbers]
            for at in range(0, len(asks), DATES_CHUNK):
                chunk = asks[at : at + DATES_CHUNK]
                ch = [v for k, v in chunk if k == "c"]
                cn = [v for k, v in chunk if k == "i"]
                answer, why = remember(
                    ("dates", repo, tuple(ch), tuple(cn)), refresh, lambda r=repo, a=ch, b=cn: _dates_chunk(r, a, b)
                )
                if why:
                    return None, None, why
                got_commits, got_starts = dates_from_answer(answer, ch, cn, worker_labels)
                for h, when in got_commits.items():
                    if when and not commits.get(h):
                        commits[h] = when
                starts.update(got_starts)
    except Exception as exc:  # noqa: BLE001 -- a reader that raised is a tracker that did not answer
        return None, None, f"The dates read failed: {exc.__class__.__name__}: {exc}"
    return commits, starts, None


def github_repos(
    org: str, status: str, projects: list[dict], *, ritual: str, refresh: bool = False
) -> tuple[list[str], dict]:
    """(the Space's repos, tracker state) -- the checks every ceremony makes before
    asking gh anything: a GitHub Space, tier 1, and at least one repo. Never raises."""
    if tracker(org) != "github":
        reason = f"This Space's tracker is not GitHub -- {ritual} reads a GitHub Space's issues."
        return [], {"ok": False, "reason": reason}
    tier, _ = _resolve_tier(org, status, refresh)
    if tier != 1:
        return [], {"ok": False, "reason": f"The tracker is not reachable from here (tier {tier})."}
    repos = tracker_repos(org, projects)
    if not repos:
        return [], {"ok": False, "reason": NO_REPO_REASON}
    return repos, {"ok": True, "reason": ""}


def read_tracker(
    org: str,
    status: str,
    projects: list[dict],
    *,
    state: str,
    body: bool = False,
    ritual: str = "the standup",
    refresh: bool = False,
) -> tuple[list[dict], list[dict], dict]:
    """(labels, issues in ``state``, tracker state) for a Space. Never raises: a failure is a reason.

    Any repo that fails fails the whole read: a standup over half the repos would
    say "no blockers" when it does not know. ``body`` asks for each issue's body;
    ``ritual`` names the reader in the not-GitHub sentence; ``refresh`` reads
    the tracker again past the kept answers (and past the tier probe's cache).
    """
    repos, state_ = github_repos(org, status, projects, ritual=ritual, refresh=refresh)
    if not state_["ok"]:
        return [], [], state_
    found: dict[str, dict] = {}
    rows_in: list[dict] = []
    try:
        for repo in repos:
            rows, why = labels(repo, refresh)
            if why:
                return [], [], {"ok": False, "reason": why}
            for r in rows:
                found.setdefault(str(r.get("name", "")), r)
            rows, why = issues(repo, state, body, refresh)
            if why:
                return [], [], {"ok": False, "reason": why}
            rows_in += rows
    except Exception as exc:  # noqa: BLE001 -- a reader that raised is a tracker that did not answer
        return [], [], {"ok": False, "reason": f"The tracker read failed: {exc.__class__.__name__}: {exc}"}
    return list(found.values()), rows_in, {"ok": True, "reason": ""}
