"""``GET /api/surfaces`` -- the optional-surface inventory with its states, and the
settings-by-workflow entries, as ONE answer (docs/CONFIGURATION.md, "Settings by workflow:
the questions, and the one list behind them").

The state of a surface -- ``on``, ``off``, ``not configured`` -- is computed by the
CLI's resolver (``Scripts/Get-OptionalSurfaces.ps1``) and by nothing else (D-W2):
this route runs ``Get-P20SurfaceInventory`` in a child PowerShell through the same
bridge script the command map is read through, and hands the JSON on. The web's
"How do I" section and the tips at the foot of Home read it; the questions
themselves come from ``Config/settings-workflows.json``, which the CLI put on
every row.

Cached against the same key as the command map (the module, the two config
files) plus a short clock, because two of the surfaces are environment
variables that change without any file changing. A failed read is not cached.
"""

from __future__ import annotations

import json
import subprocess
import time

from fastapi import APIRouter, HTTPException

from ..ado.bridge import BRIDGE_PS1, NO_HOST_ERROR, REPO_ROOT, _child_env, _map_key_now
from .hosts import host_argv
from .log_writer import write_log

api = APIRouter()

_TIMEOUT_SECONDS = 60
_TTL_SECONDS = 30.0
_cache: dict | None = None
_cache_key: tuple | None = None
_cache_at = 0.0


def read_inventory() -> dict | None:
    """Run Get-P20SurfaceInventory and parse its one line of JSON; None when it
    could not be read, with the reason logged once per call."""
    argv = host_argv(str(BRIDGE_PS1), "Get-P20SurfaceInventory")
    if argv is None:
        write_log("ERR", "Agent/surfaces", NO_HOST_ERROR)
        return None
    try:
        result = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_TIMEOUT_SECONDS,
            cwd=str(REPO_ROOT),
            env=_child_env(),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        write_log("ERR", "Agent/surfaces", f"{type(e).__name__}: {e}")
        return None
    if result.returncode != 0:
        write_log("ERR", "Agent/surfaces", (result.stderr or "").strip()[:200])
        return None
    lines = [ln.strip() for ln in result.stdout.splitlines() if ln.strip().startswith("{")]
    if not lines:
        write_log("ERR", "Agent/surfaces", "no JSON object in output")
        return None
    try:
        parsed = json.loads(lines[-1])
    except json.JSONDecodeError as e:
        write_log("ERR", "Agent/surfaces", f"unparseable inventory: {e}")
        return None
    return parsed if isinstance(parsed, dict) else None


def invalidate() -> None:
    global _cache, _cache_key
    _cache = None
    _cache_key = None


def inventory(force: bool = False) -> dict | None:
    global _cache, _cache_key, _cache_at
    key = _map_key_now()
    fresh_enough = (time.monotonic() - _cache_at) < _TTL_SECONDS
    if _cache is not None and not force and key == _cache_key and fresh_enough:
        return _cache
    data = read_inventory()
    if data is not None:
        _cache, _cache_key, _cache_at = data, key, time.monotonic()
    return data


@api.get("/surfaces")
async def get_surfaces(refresh: int = 0):
    data = inventory(force=bool(refresh))
    if data is None:
        raise HTTPException(
            status_code=503,
            detail="The optional-surface inventory is the CLI's, and PowerShell did not answer -- "
            "see the agent log. The settings rows still work; the questions do not.",
        )
    return data
