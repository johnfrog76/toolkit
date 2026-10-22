"""Tier resolution -- the canonical decision, shared by /env and /dashboard.

Tier is a statement about capability, not about whether the tracker happens to
have data right now: Tier 1 is full ADO access, Tier 2 is local-only, Tier 3 is
minimal. ``_tier_from`` is pure so it can be parity-tested against
``Scripts/Resolve-TierDecision.ps1``; the two MUST agree on all 64 input
combinations (Tests/test_tier_parity.py).
"""

import shutil
import subprocess  # noqa: F401 -- the suites patch tier.subprocess.run; run_read calls the same module
import threading
import time

from .child import run_read
from .config import hub_root, tracker, tracker_owner

# How long one reachability answer is good for, in seconds.
#
# The probe is a cold `az` start -- 3 to 4 seconds on Windows, up to the 15s
# timeout when it hangs -- and every page load in the web UI gates on /env, so
# a user paid for one per navigation. Reachability is a fact about this
# machine's ADO access rather than about this request: it does not change
# between two page loads, and the PowerShell side has always treated the tier
# probe as a session-time fact ($global:P20Env). 45s is the middle of the 30-60
# window the report asked for -- long enough that a burst of page loads costs
# one probe, short enough that `az login` in another terminal is picked up
# without restarting the agent. `/env?refresh=1` and a `/switch-mode` bypass it
# outright.
ADO_PROBE_TTL_SECONDS = 45

# probe key -> (monotonic timestamp, reachable). The key is what the probe
# ASKS, not which Space asked (``_probe_key``): the owner for a GitHub address,
# the org URL for Azure DevOps. Answered under a lock because the probe runs in
# the threadpool -- /env, /dashboard and the accounting routes all resolve tier
# off the event loop.
_probe_cache: dict[str, tuple[float, bool]] = {}
_probe_lock = threading.Lock()


class _Flight:
    """One probe in flight, shared by every caller that missed on its key.

    The first caller to miss makes the probe (the leader); the rest wait on
    ``done`` and read what it left. A probe that RAISED leaves ``error``, and
    every caller sharing that flight re-raises it -- nothing is cached, so the
    next ask makes a fresh probe.
    """

    __slots__ = ("done", "error", "reachable")

    def __init__(self) -> None:
        self.done = threading.Event()
        self.reachable = False
        self.error: BaseException | None = None


# probe key -> the flight a miss is waiting on; guarded by ``_probe_lock``.
_probe_flights: dict[str, _Flight] = {}


def probe_cache_clear() -> None:
    """Forget every cached reachability answer.

    Called by /switch-mode, and by the tests -- a cache that survived between
    cases would make the second one depend on the first. A probe already in
    flight finishes and answers its waiters, but is not written back.
    """
    with _probe_lock:
        _probe_cache.clear()
        _probe_flights.clear()


def _probe_key(org_url: str) -> str:
    """What one reachability answer is good FOR.

    GitHub: the OWNER. The probe is ``gh api users/<owner>``, which does not
    depend on the repository, so one answer serves every Space under that
    owner (a developer's ten Spaces are one probe, not ten). Case-folded,
    because GitHub logins are. Azure DevOps: the org URL as given -- the probe
    is ``az devops project list --org <url>``, one answer per organisation,
    and two Spaces on one org already share a URL.
    """
    if tracker(org_url) == "github":
        owner = tracker_owner(org_url)
        if owner:
            return "github:" + owner.lower()
    return org_url or ""


def _probe_tracker_cached(org_url: str, refresh: bool = False) -> bool:
    """`_probe_tracker` behind the TTL, and merged. Never called from the event loop.

    Concurrent misses on one key join ONE probe. ``refresh`` goes past the
    cached answer but still joins a probe that is already running -- that
    answer is as fresh as the one it would have made.
    """
    key = _probe_key(org_url)
    with _probe_lock:
        if not refresh:
            hit = _probe_cache.get(key)
            if hit is not None and (time.monotonic() - hit[0]) < ADO_PROBE_TTL_SECONDS:
                return hit[1]
        flight = _probe_flights.get(key)
        leader = flight is None
        if leader:
            flight = _probe_flights[key] = _Flight()
    if not leader:
        flight.done.wait()
        if flight.error is not None:
            raise flight.error
        return flight.reachable
    try:
        flight.reachable = _probe_tracker(org_url)
    except BaseException as e:
        flight.error = e
        raise
    else:
        with _probe_lock:
            if _probe_flights.get(key) is flight:  # not cleared while it ran
                _probe_cache[key] = (time.monotonic(), flight.reachable)
        return flight.reachable
    finally:
        with _probe_lock:
            if _probe_flights.get(key) is flight:
                del _probe_flights[key]
        flight.done.set()


def _probe_tracker(org_url: str) -> bool:
    # "Reachable" means: do we actually have access to the tracker this board's
    # address names (D-G2)? Each tracker is
    # probed via the same path its real calls use -- the az CLI for ADO, the gh
    # CLI for GitHub -- because that reflects true access. A raw HTTP probe is
    # unreliable: unauthenticated it follows a sign-in redirect to a 200 (false
    # positive), and the Bearer-token path can 302 even when the CLI works.
    if not org_url:
        return False
    if tracker(org_url) == "github":
        return _probe_github(org_url)
    return _probe_ado(org_url)


def _probe_ado(org_url: str) -> bool:
    # `az devops project list` returns 0 with data when you have access,
    # non-zero otherwise. (docs/CLI.md, "Tiers: what works without ADO")
    try:
        result = run_read(
            ["az", "devops", "project", "list", "--org", org_url, "--query", "value[0].name", "-o", "tsv"],
            15,
        )
        return result.returncode == 0 and bool(result.stdout.strip())
    except Exception:  # noqa: BLE001 -- a probe that raised is a probe that failed: a lower tier, never a raise
        return False


def _probe_github(org_url: str) -> bool:
    # The gh CLI, authenticated: `gh api users/<owner>` answers 0 with the
    # login when the owner exists and the token works. The owner is the
    # address's first path segment; an address that names none cannot be
    # probed and reads unreachable, which is what it is.
    owner = tracker_owner(org_url)
    if not owner:
        return False
    try:
        result = run_read(["gh", "api", f"users/{owner}", "-q", ".login"], 15)
        return result.returncode == 0 and bool(result.stdout.strip())
    except Exception:  # noqa: BLE001 -- a probe that raised is a probe that failed: a lower tier, never a raise
        return False


def _tier_from(repo_ok: bool, git_ok: bool, az_ok: bool, ado_reachable: bool, status: str) -> int:
    # The canonical tier DECISION (docs/CLI.md, "Tiers: what works without ADO"). Pure function of its
    # inputs — no I/O — so it can be parity-tested against the PowerShell
    # Resolve-TierDecision. PowerShell MUST implement this identically.
    if not repo_ok or not git_ok:
        return 3
    if status in ("local", "archive"):  # config wins — declared offline / rolled off
        return 2
    if not az_ok:
        return 2
    return 1 if ado_reachable else 2


def _resolve_tier(org_url: str, status: str = "", refresh: bool = False) -> tuple[int, bool]:
    # Gather environment inputs, then defer the decision to _tier_from. Tier is
    # based on capability (filesystem + real ADO access), not whether ADO happens
    # to have data right now. The probe (which uses `az`) already encompasses
    # auth, so az_ok is folded into it; we skip the probe entirely when it can't
    # matter (missing repo/git or a declared-local org). The probe itself is
    # behind a short TTL (ADO_PROBE_TTL_SECONDS); `refresh=True` goes past it.
    #
    # THIS FUNCTION BLOCKS. It shells out to `az`. Every caller runs it off the
    # event loop -- asyncio.to_thread -- and a new one that forgets is a stalled
    # agent, not a slow route: an async handler that blocks holds every other
    # request with it.
    #
    # These two inputs mean what Get-Environment.ps1 means by them: the hub is
    # THERE, and git is INSTALLED. The package this was carved from read the
    # second as "the hub has a .git directory", which quietly demanded that the
    # prompt store be a git repository and dropped a perfectly good hub to Tier
    # 3. The store does not have to be versioned (storeSync defaults to none);
    # whether it happens to be is reported separately by /env's gitHistory row.
    repo_ok = hub_root().exists()
    git_ok = shutil.which("git") is not None
    ado_reachable = False
    if repo_ok and git_ok and status not in ("local", "archive"):
        ado_reachable = _probe_tracker_cached(org_url, refresh=refresh)
    tier = _tier_from(repo_ok, git_ok, True, ado_reachable, status)
    return tier, ado_reachable
