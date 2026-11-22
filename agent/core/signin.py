"""Is `az` signed in, for the sign-in strip -- the one answer /env carries as ``azSignIn``.

The CLI answers the same question in ``Scripts/Test-TrackerSignIn.ps1`` (``az account show``,
exit 0 with output) and this is its mirror. The strip is SHOWN only where it can
be acted on, which is what ``needed`` says: an ACTIVE Space whose address names
Azure DevOps, with ``az`` installed and not signed in. A local or archived Space
never asks ``az`` for anything, a GitHub Space is ``gh``'s business, and a machine
with no ``az`` has a different next step (install it), which the Environment card
already says. The agent runs no sign-in: it reports the command and nothing more.

CACHED behind the same TTL as the reachability probe, so a burst of page loads costs one
``az account show``; ``refresh`` goes past it, which is what the strip's "Check again" asks.

BLOCKING. Call it with ``asyncio.to_thread``.
"""

import shutil
import subprocess  # noqa: F401 -- the suites patch signin.subprocess.run; run_read calls the same module
import threading
import time

from . import consts
from .child import run_read
from .config import tracker
from .tier import ADO_PROBE_TTL_SECONDS

# (monotonic timestamp, signed in). One machine, one answer, for the TTL.
_cache: tuple[float, bool] | None = None
_lock = threading.Lock()


def signin_cache_clear() -> None:
    """Forget the cached answer -- the tests, and a Space switch."""
    global _cache
    with _lock:
        _cache = None


def _az_signed_in(refresh: bool) -> bool:
    global _cache
    if not refresh:
        with _lock:
            hit = _cache
        if hit is not None and (time.monotonic() - hit[0]) < ADO_PROBE_TTL_SECONDS:
            return hit[1]
    try:
        result = run_read(["az", "account", "show", "--output", "json"], 15)
        signed_in = result.returncode == 0 and bool(result.stdout.strip())
    except Exception:  # noqa: BLE001 -- az that cannot answer is az that is not signed in
        signed_in = False
    with _lock:
        _cache = (time.monotonic(), signed_in)
    return signed_in


def sign_in_block(org_url: str, status: str, refresh: bool = False) -> dict:
    """``{needed, installed, signedIn, command}``. ``installed`` and ``signedIn`` are
    null where ``az`` is not asked (not an active Azure DevOps Space)."""
    command = consts.az_login_command()
    if tracker(org_url) != "ado" or status != "active":
        return {"needed": False, "installed": None, "signedIn": None, "command": command}
    if shutil.which("az") is None:
        return {"needed": False, "installed": False, "signedIn": None, "command": command}
    signed_in = _az_signed_in(refresh)
    return {"needed": not signed_in, "installed": True, "signedIn": signed_in, "command": command}
