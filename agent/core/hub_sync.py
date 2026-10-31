"""The hub's distance from its remote, for a hub whose storeSync is git.

Two numbers, and they are not known the same way (docs/CONFIGURATION.md,
"Syncing the hub from the web app"):

* **ahead** is LOCAL -- what this clone has that its remote-tracking branch does
  not. No network. It rides on every ``/env``, behind the TTL the tracker
  reachability probe uses (``tier.ADO_PROBE_TTL_SECONDS``) and joined by
  concurrent askers the way that probe is, because reading it costs one
  PowerShell start.
* **behind** is known only after a ``git fetch``. Nothing here fetches on a
  timer. A fetch happens when someone ASKS -- ``POST /api/hub-sync/check``,
  which the System page sends once when it opens and again after Sync the hub
  -- and a second ask inside the TTL of the last one is answered from it.
  ``?refresh=1`` goes past it.

What a fetch leaves is kept as the LAST KNOWN state: ``behind`` and the time it
was read (``checkedAt``). A fetch that fails keeps both and says so separately
(``checkFailed``), so a remote that is unreachable for a minute does not wipe a
count that was true a minute ago. Before the first fetch ``behind`` and
``checkedAt`` are null: the card says it has not checked yet, never "in step".

Every git call is the CLI half's: ``Scripts/Get-HubSyncState.ps1``, through
``Invoke-P20TrackerRead`` (AGENTS.md, "Traps worth knowing"). The agent starts
it the way it starts the billing script, ``host_argv``.

Under any storeSync but git, nothing here runs: the block says ``off`` and
carries no numbers.
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import threading
import time
from datetime import UTC, datetime

from fastapi import APIRouter

from .child import ChildReadError, did_not_answer, run_read
from .config import HUB_SYNC_SCRIPT, hub_root, load_config
from .hosts import NO_HOST_ERROR, host_argv
from .tier import ADO_PROBE_TTL_SECONDS

api = APIRouter()

# The store-sync value this module acts on, and the states the block reports --
# the inventory's (Scripts/Get-OptionalSurfaces.ps1, the storeSync row): `on`
# for git, `off` for anything else. There is no third state: the shipped config
# answers `none`, so storeSync is never unset.
STORE_SYNC_GIT = "git"
STATE_ON = "on"
STATE_OFF = "off"

# How long one answer is good for -- the reachability probe's, on purpose: the
# same "a burst of page loads costs one child" reasoning, and one number to tune.
HUB_SYNC_TTL_SECONDS = ADO_PROBE_TTL_SECONDS

# A local read is a PowerShell start and two git calls; a fetch is the network.
LOCAL_TIMEOUT_SECONDS = 30
FETCH_TIMEOUT_SECONDS = 90

_lock = threading.Lock()

# The local read for one hub root: {"root", "at", "ahead", "error"}.
_local: dict = {}
_local_flight: threading.Event | None = None

# The last fetch for one hub root: {"root", "attempted", "behind", "checkedAt", "checkFailed"}.
_last: dict = {}
_fetch_flight: threading.Event | None = None


def hub_sync_cache_clear() -> None:
    """Forget every answer. For the tests."""
    global _local, _last
    with _lock:
        _local = {}
        _last = {}


def local_cache_clear() -> None:
    """Forget the ahead count only. The bridge calls this after a verb ran: a
    write into a git hub is a commit, so the next /env reads ahead again. The
    last fetch's ``behind`` is untouched -- a local commit does not change it."""
    global _local
    with _lock:
        _local = {}


def _now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def _run(root: str, fetch: bool) -> dict:
    """Run the script and return its fields, or ``{"runError": sentence}``."""
    args = ["-HubRoot", root]
    if fetch:
        args.append("-Fetch")
    argv = host_argv(str(HUB_SYNC_SCRIPT), *args)
    if argv is None:
        return {"runError": NO_HOST_ERROR}
    # A fetch over https with no stored credential would otherwise wait on a
    # prompt nobody can answer, until the timeout.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    timeout = FETCH_TIMEOUT_SECONDS if fetch else LOCAL_TIMEOUT_SECONDS
    try:
        result = run_read(argv, timeout, shell=False, env=env)
    except (OSError, subprocess.SubprocessError, ChildReadError) as exc:
        return {"runError": did_not_answer("the hub sync read", exc)}
    lines = [ln.strip() for ln in (result.stdout or "").splitlines() if ln.strip().startswith("{")]
    try:
        data = json.loads(lines[-1]) if lines else None
    except ValueError:
        data = None
    if not isinstance(data, dict):
        said = (result.stderr or result.stdout or "").strip().splitlines()
        return {"runError": "the hub sync read answered nothing readable" + (f": {said[0]}" if said else "")}
    return data


def _keep_local(root: str, data: dict) -> None:
    """Hold a local read's answer. Caller holds ``_lock``."""
    global _local
    ahead = data.get("ahead")
    _local = {
        "root": root,
        "at": time.monotonic(),
        "ahead": ahead if isinstance(ahead, int) else None,
        "error": data.get("runError") or data.get("error") or None,
    }


def _read_local(root: str, refresh: bool) -> tuple[int | None, str | None]:
    """The ahead count and the local read's error, behind the TTL. Concurrent
    misses join one read; ``refresh`` goes past the cache but still joins a read
    already running -- that answer is as fresh as the one it would make."""
    global _local_flight
    with _lock:
        fresh = _local.get("root") == root and (time.monotonic() - _local["at"]) < HUB_SYNC_TTL_SECONDS
        if fresh and not refresh:
            return _local["ahead"], _local["error"]
        flight = _local_flight
        leader = flight is None
        if leader:
            flight = _local_flight = threading.Event()
    if not leader:
        flight.wait()
        with _lock:
            return _local.get("ahead"), _local.get("error")
    try:
        data = _run(root, fetch=False)
        with _lock:
            _keep_local(root, data)
            return _local["ahead"], _local["error"]
    finally:
        with _lock:
            _local_flight = None
        flight.set()


def _off_block(store_sync: str) -> dict:
    return {
        "storeSync": store_sync,
        "state": STATE_OFF,
        "ahead": None,
        "behind": None,
        "checkedAt": None,
        "checkFailed": None,
        "checking": False,
        "error": None,
    }


def _on_block(root: str, ahead: int | None, error: str | None) -> dict:
    with _lock:
        known = _last if _last.get("root") == root else {}
        checking = _fetch_flight is not None
        return {
            "storeSync": STORE_SYNC_GIT,
            "state": STATE_ON,
            "ahead": ahead,
            "behind": known.get("behind"),
            "checkedAt": known.get("checkedAt"),
            "checkFailed": known.get("checkFailed"),
            "checking": checking,
            "error": error,
        }


def hub_sync_block(store_sync: str, refresh: bool = False) -> dict:
    """What ``/env`` reports as ``hubSync``. Never fetches. BLOCKS (a child
    PowerShell on a cache miss): call it off the event loop."""
    store_sync = store_sync or "none"
    if store_sync != STORE_SYNC_GIT:
        return _off_block(store_sync)
    root = str(hub_root())
    ahead, error = _read_local(root, refresh)
    return _on_block(root, ahead, error)


def check(store_sync: str, refresh: bool = False) -> dict:
    """Fetch, and answer the block with ``behind`` as of now. BLOCKS.

    One fetch at a time: an ask that arrives while one runs waits for it and
    reads what it left. An ask inside the TTL of the last attempt -- success or
    failure -- is answered from it, unless ``refresh``.
    """
    global _last, _fetch_flight
    store_sync = store_sync or "none"
    if store_sync != STORE_SYNC_GIT:
        return _off_block(store_sync)
    root = str(hub_root())
    with _lock:
        attempted = _last.get("attempted") if _last.get("root") == root else None
        recent = attempted is not None and (time.monotonic() - attempted) < HUB_SYNC_TTL_SECONDS
        flight = _fetch_flight
        leader = flight is None and (refresh or not recent)
        if leader:
            flight = _fetch_flight = threading.Event()
    if flight is not None and not leader:
        flight.wait()
    if leader:
        try:
            data = _run(root, fetch=True)
            with _lock:
                record = dict(_last) if _last.get("root") == root else {}
                record.update(root=root, attempted=time.monotonic())
                if data.get("fetched"):
                    behind = data.get("behind")
                    record.update(
                        behind=behind if isinstance(behind, int) else None,
                        checkedAt=_now_iso(),
                        checkFailed=None,
                    )
                else:
                    # The fetch did not happen or did not finish: say so, and
                    # keep the last count and its time on screen.
                    record["checkFailed"] = (
                        data.get("fetchError") or data.get("runError") or data.get("error") or "the fetch did not run"
                    )
                _last = record
                if "runError" not in data:
                    # The fetch's own local read is the newest there is.
                    _keep_local(root, data)
        finally:
            with _lock:
                _fetch_flight = None
            flight.set()
    ahead, error = _read_local(root, False)
    return _on_block(root, ahead, error)


# POST /api/hub-sync/check -- the one route that fetches.
# ---------------------------------------------------------------------------
@api.post("/hub-sync/check")
async def post_check(refresh: int = 0):
    """Fetch and report. The System page sends this once when it opens and
    again after Sync the hub; nothing else does, and nothing sends it on a
    timer. Off the event loop: a fetch is the network."""
    cfg = load_config()
    return await asyncio.to_thread(check, str(cfg.get("storeSync") or "none"), bool(refresh))
