"""Who "me" is, for the agent -- the one answer /prs, /dashboard and /work-items ask.

The CLI has answered this since it was written: ``Resolve-P20Identity`` in
``utilities.psm1`` takes the configured ``email``, and when that is empty asks
``az account show --query user.name -o tsv``, because az already knows and a
tool should not warn about something it can work out.

The agent did not. It read ``cfg["email"]`` and stopped, so on a machine with no
``email`` in its (gitignored, per-machine) ``config.local.json`` the browser
showed no pull requests while ``tkMyPRs`` in the same shell listed them --
silently, because ``/prs`` returned its empty shape *before* its own log line.

THE ORDER, and both halves must keep it:

  1. ``email`` from config -- ``config.local.json`` over ``config.default.json``.
     Explicit configuration always wins, so a shared machine or a second account
     can override what az thinks.
  2. ``branchUser``, but only if it is an address. It usually is not -- it is the
     branch-name segment (``v-someone``) -- and a bare name would be sent to
     ``--creator`` where ADO wants a unique name, so it is taken only when it
     carries an ``@``.
  3. ``az account show --query user.name -o tsv``.

Nothing resolves to nothing, and that is reported rather than rendered as "no
pull requests" -- see ``IDENTITY_MISSING_REASON``.

CACHED PER PROCESS, behind the same TTL style the ADO reachability probe uses
(``tier.ADO_PROBE_TTL_SECONDS``, 45s): the az probe is a cold CLI start, every
dashboard load would otherwise pay for one, and 45s is short enough that an
``az login`` in another terminal is picked up without restarting the agent.

BLOCKING. ``resolve_identity`` shells out to az. Every caller runs it off the
event loop -- ``await asyncio.to_thread(resolve_identity)`` -- exactly as
``_resolve_tier`` is called, and a route that forgets stalls the whole agent
rather than just itself.
"""

import subprocess  # noqa: F401 -- the suites patch identity.subprocess.run; run_read calls the same module
import threading
import time

from . import log_writer
from .child import run_read
from .config import load_config
from .tier import ADO_PROBE_TTL_SECONDS

# The sentence the routes report and log when identity resolves to nothing. It
# names the missing config key AND the remedy, which is the CLI's refusal
# contract (a stated reason and a hint, never a silent empty result) applied to
# a route that cannot refuse outright without taking the page down with it.
IDENTITY_MISSING_REASON = "No identity: set `email` in config.local.json, or run `az login`."

# Where the answer came from, for /env and the System card. "" when unresolved.
IDENTITY_SOURCE_CONFIG = "config"
IDENTITY_SOURCE_BRANCH_USER = "branchUser"
IDENTITY_SOURCE_AZ = "az"

# (monotonic timestamp, email, source). One process, one answer, for the TTL.
_cache: tuple[float, str, str] | None = None
_lock = threading.Lock()


def identity_cache_clear() -> None:
    """Forget the cached identity.

    Called by the tests -- a cache that survived between cases would make the
    second one depend on the first -- and by /switch-mode, since a different
    org may be configured with a different address.
    """
    global _cache
    with _lock:
        _cache = None


def _az_account_email() -> str:
    """``az account show --query user.name -o tsv``, or "" if az cannot say."""
    try:
        # Through the shell on Windows (az.cmd needs it), read as UTF-8.
        result = run_read(["az", "account", "show", "--query", "user.name", "-o", "tsv"], 15)
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:  # noqa: BLE001 -- FileNotFoundError, TimeoutExpired, anything az does: no identity
        return ""
    return ""


def resolve_identity(refresh: bool = False) -> tuple[str, str]:
    """Return ``(email, source)``; ``("", "")`` when nothing answers.

    BLOCKS -- call it with ``asyncio.to_thread``.
    """
    global _cache
    if not refresh:
        with _lock:
            hit = _cache
        if hit is not None and (time.monotonic() - hit[0]) < ADO_PROBE_TTL_SECONDS:
            return hit[1], hit[2]

    cfg = load_config()

    email = (cfg.get("email") or "").strip()
    source = IDENTITY_SOURCE_CONFIG if email else ""

    if not email:
        branch_user = (cfg.get("branchUser") or "").strip()
        if "@" in branch_user:
            email, source = branch_user, IDENTITY_SOURCE_BRANCH_USER

    if not email:
        probed = _az_account_email()
        if probed:
            email, source = probed, IDENTITY_SOURCE_AZ

    if not email:
        source = ""

    with _lock:
        _cache = (time.monotonic(), email, source)
    return email, source


def identity_block(refresh: bool = False) -> dict:
    """What /env reports, so the System card can show where the address came from."""
    email, source = resolve_identity(refresh=refresh)
    return {"email": email, "source": source}


def warn_no_identity(route: str) -> None:
    """One WARN per empty answer, with the same sentence the route returns.

    The bug this file exists for was not the empty list -- it was that nothing
    was written anywhere, so the day's log had no ``agent/prs`` entry at all and
    the page looked like "you have no PRs".
    """
    log_writer.write_log("WARN", route, IDENTITY_MISSING_REASON)
