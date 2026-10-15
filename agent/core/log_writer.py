"""Unified log writer for the Python side of the Toolkit.

Appends tab-separated entries to ``usage.{machine}.log`` beside the CLI's own
log, in the same format Write-ToolkitLog uses. Each machine writes its own file
so syncing between boxes never conflicts.

The log lives next to the module, at the repository root -- the same place the
PowerShell writer puts it ($PSScriptRoot). It is not derived from the prompt
store, which may be anywhere (see config.py).

Usage:
    from .log_writer import write_log
    write_log('CMD', 'status', 'ok')
    write_log('ERR', 'status', 'KeyError: decision line 47')
"""

import datetime
import os
import socket
from pathlib import Path

# agent/core/log_writer.py -> agent/core -> agent -> repo root
REPO_ROOT = Path(__file__).resolve().parents[2]

# The one override both halves read; utilities.psm1 reads the same variable.
#
# Unset means the repo root, exactly as before. It is a DIRECTORY rather than a
# file because every reader on both sides globs ``usage.*.log`` to merge
# machines, so a writer-only redirect would leave the readers on the real log.
#
# It exists because a test run is not an event: pytest and the PowerShell suites
# appended their fixtures' warnings and their refusal assertions to the
# engineer's own usage log, which is what ``tkLog -Errors`` and the web UI's Log
# card read as history.
# ``Tests/conftest.py`` points it at a temp directory for the whole pytest
# session, and ``Tests/Test-Toolkit.ps1`` does the same for the suites.
#
# ``test-results.{machine}.log`` deliberately does NOT follow it: the Health
# card reading real test results is the point of that file.
LOG_DIR_ENV = "P20_USAGE_LOG_DIR"


def log_dir() -> Path:
    """Where ``usage.{machine}.log`` is written and read. Re-read per call, so a
    fixture that sets the variable after import still takes effect."""
    override = (os.environ.get(LOG_DIR_ENV) or "").strip()
    return Path(override) if override else REPO_ROOT


def _machine_name() -> str:
    return os.environ.get("COMPUTERNAME") or socket.gethostname().split(".")[0]


def _resolve_log_path(machine: str) -> str:
    return str(log_dir() / f"usage.{machine}.log")


def write_log(log_type: str, source: str, detail: str) -> None:
    """Append one entry to usage.{machine}.log.

    Args:
        log_type: CMD | ERR | WARN | INFO
        source: command name or layer (e.g. 'status')
        detail: result or error message
    """
    if log_type not in ("CMD", "ERR", "WARN", "INFO"):
        raise ValueError(f"Invalid log type: {log_type!r}")

    timestamp = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    machine = _machine_name()
    entry = f"{timestamp}\t{log_type}\t{machine}\t{source}\t{detail}\n"

    try:
        with open(_resolve_log_path(machine), "a", encoding="utf-8") as f:
            f.write(entry)
    except OSError:
        # Logging must never take a request down.
        pass
