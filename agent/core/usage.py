"""The current Claude Code burn: ``GET /api/usage/burn``.

Today and this week -- this machine's Claude Code session files plus the day
records the other machines logged into the hub's ``usage/`` -- as the CLI's
``Burn -AsJson`` answers it (docs/hub/usage.md, "Today and this week").

**One reader, the CLI's.** The route does not read a session file itself: it runs
``Burn -AsJson`` in a child PowerShell through the bridge's own runner
(``bridge._run``, the function resolved out of the CLI's command table, the
parameter as argv) and serves what the verb printed. The terminal and the System
page's tile therefore show the same numbers by construction, and the rules that
are easy to get subtly wrong -- one response counted once across its lines, the
week starting Friday 05:00, another machine's record counting toward the week it
starts in -- live in one place, ``Scripts/Read-ClaudeUsage.ps1``.

**Kept on disk for an hour.** A read costs a PowerShell start and a pass over a
week of transcripts (seconds), so the answer is kept in the agent's cache
(``agent/core/disk_cache.py``, ``burn-1/current.json``) for ``BURN_TTL_SECONDS``,
the way ``/studio/ledger`` keeps its answer, keyed by the hub it was read
against. It is also never served past the verb's own ``nextBoundaryAt`` -- the
next local midnight or the next Friday 05:00, whichever is sooner -- because
after it the windows themselves are different. ``?refresh=1`` (the tile's
Refresh) goes past the cache. A read that failed is not kept.

**Present where on, absent where not.** The gate is ``claude_usage()`` -- the
Claude Code usage inventory row's rule, carried on ``/env`` under consts.json
``usage.envFlag`` -- checked per request: where this machine has no Claude Code
session files the route is 404, as an opt-in surface that is off is.

Read-only: the verb opens Claude Code's files for reading and writes nothing
into the hub. It does write its own CMD line to the usage log, as every verb does.
"""

from __future__ import annotations

import asyncio
import json
import threading
import time
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException

from ..ado import bridge
from . import disk_cache
from .config import API_PREFIX, claude_usage, hub_root
from .consts import usage_burn_route
from .log_writer import write_log

# How long one reading is served: an hour (the owner's call). The CLI's
# nextBoundaryAt can make it shorter, never longer.
BURN_TTL_SECONDS = 3600
# The disk namespace, with a version in it: bump it when the served shape changes.
BURN_DIR = "burn-1"
BURN_FILE = "current.json"
# The verb, by its name in the CLI's command table; the function is the table's.
BURN_COMMAND = "Burn"

api = APIRouter()
ROUTE = usage_burn_route().removeprefix(API_PREFIX)

_read_lock = threading.Lock()


def _parse_instant(raw: object) -> float | None:
    """An ISO instant (``...Z``) as seconds since the epoch, or None."""
    try:
        return datetime.fromisoformat(str(raw or "")).astimezone(UTC).timestamp()
    except ValueError:
        return None


def _json_object(stdout: str) -> dict | None:
    """The one JSON object ``Burn -AsJson`` prints, or None. From the first ``{``
    to the last ``}``: a warning on the way up would sit in front of it."""
    start, end = stdout.find("{"), stdout.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        data = json.loads(stdout[start : end + 1])
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def _cached(hub: str, now: float) -> dict | None:
    """The kept reading, when it is for this hub, under an hour old and not past
    its own next boundary; else None."""
    entry = disk_cache.get_json(BURN_DIR, BURN_FILE)
    if not entry or entry.get("hub") != hub or not isinstance(entry.get("burn"), dict):
        return None
    try:
        fetched = float(entry.get("fetchedAt") or 0)
    except (TypeError, ValueError):
        return None
    if not (0 <= now - fetched < BURN_TTL_SECONDS):
        return None
    boundary = _parse_instant(entry["burn"].get("nextBoundaryAt"))
    if boundary is None or now >= boundary:
        return None
    return {**entry["burn"], "fetchedAt": _stamp(fetched), "fromCache": True}


def _stamp(epoch: float) -> str:
    """Seconds since the epoch as the verb writes an instant: ``...T..:..:..sssZ``."""
    return datetime.fromtimestamp(epoch, UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _run_burn() -> dict:
    """``Burn -AsJson`` through the bridge's runner, parsed. Raises HTTPException
    with the verb's own sentence when it does not answer."""
    function = bridge.command_map().get(BURN_COMMAND)
    if not function:
        raise HTTPException(status_code=503, detail=f"'{BURN_COMMAND}' is not in this CLI's command table.")
    try:
        result = bridge._run(function, ["-AsJson"], bridge.command_timeout(BURN_COMMAND))
    except Exception as e:  # OSError, TimeoutExpired: a reason, never a crash
        write_log("ERR", f"Agent/{BURN_COMMAND}", f"{type(e).__name__}: {e}"[:200])
        raise HTTPException(status_code=502, detail=f"{BURN_COMMAND} did not run ({type(e).__name__}: {e})") from e
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() or f"{BURN_COMMAND} exited {result.returncode}"
        write_log("ERR", f"Agent/{BURN_COMMAND}", detail[:200])
        raise HTTPException(status_code=502, detail=detail)
    data = _json_object(result.stdout or "")
    if data is None:
        raise HTTPException(status_code=502, detail=f"{BURN_COMMAND} -AsJson produced no readable JSON object")
    return data


def read_burn(refresh: bool = False) -> dict:
    """The current burn: the kept reading when it is good, else a fresh one,
    kept. Blocking: PowerShell runs here."""
    with _read_lock:  # two tabs at once run the verb once; the second finds the disk warm
        hub = str(hub_root())
        now = time.time()
        if not refresh:
            hit = _cached(hub, now)
            if hit is not None:
                return hit
        data = _run_burn()
        fetched = time.time()
        disk_cache.put_json({"hub": hub, "fetchedAt": fetched, "burn": data}, BURN_DIR, BURN_FILE)
        return {**data, "fetchedAt": _stamp(fetched), "fromCache": False}


@api.get(ROUTE)
async def get_burn(refresh: int = 0):
    """Today's and this week's Claude Code burn, as ``Burn -AsJson`` answers it,
    plus ``fetchedAt`` (when the verb ran) and ``fromCache``. 404 where this
    machine has no Claude Code session files. ``?refresh=1`` goes past the
    hour-long cache."""
    if not claude_usage():
        raise HTTPException(status_code=404, detail="No Claude Code session files on this machine.")
    return await asyncio.to_thread(read_burn, bool(refresh))
