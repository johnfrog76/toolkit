"""The GitHub tracker read both ceremonies share -- the standup and triage.

One reader, so the two cannot drift on what a failed read means: any repo that
fails fails the whole read, and a reader that raised is a tracker that did not
answer. The ceremonies differ only in which issues they ask for.
"""

from __future__ import annotations

from ..ado import accounting
from ..core.config import tracker, tracker_repos
from ..core.tier import _resolve_tier

NO_REPO_REASON = "This GitHub space names no repository."


def read_tracker(
    org: str, status: str, projects: list[dict], *, state: str, body: bool = False, ritual: str = "the standup"
) -> tuple[list[dict], list[dict], dict]:
    """(labels, issues in ``state``, tracker state) for a Space. Never raises: a failure is a reason.

    Any repo that fails fails the whole read: a standup over half the repos would
    say "no blockers" when it does not know. ``body`` asks for each issue's body;
    ``ritual`` names the reader in the not-GitHub sentence.
    """
    if tracker(org) != "github":
        reason = f"This Space's tracker is not GitHub -- {ritual} reads a GitHub Space's issues."
        return [], [], {"ok": False, "reason": reason}
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
            rows, why = accounting._gh_issues(repo, True, state, body=body)
            if why:
                return [], [], {"ok": False, "reason": why}
            issues += rows
    except Exception as exc:  # noqa: BLE001 -- a reader that raised is a tracker that did not answer
        return [], [], {"ok": False, "reason": f"The tracker read failed: {exc.__class__.__name__}: {exc}"}
    return list(labels.values()), issues, {"ok": True, "reason": ""}
