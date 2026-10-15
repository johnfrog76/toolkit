"""Which PowerShell this machine actually has.

The Python twin of ``Scripts/Resolve-Python.ps1``, and it exists for the same
reason: something has to start a child process, the name it starts is not the
same on every host, and the answer must have exactly one implementation. That
file answers "which Python" for the PowerShell side; this one answers "which
PowerShell" for the Python side.

The defect it closes: the bridge ran ``pwsh`` by name, twice, with no fallback.
docs/QUICKSTART.md's Requirements table promises Windows PowerShell 5.1 as the floor, so a
PC with only ``powershell.exe`` is a supported machine -- and on one, every
``POST /api/cmd/{name}`` failed, reported as "not a command in this CLI"
because the allowlist read had quietly come back empty.

Two names, in preference order:

  ``pwsh``        PowerShell 7+, on every platform. The daily shell, and the
                  only one that exists on macOS and Linux.
  ``powershell``  Windows PowerShell 5.1, the built-in. **Windows only** --
                  the name is not probed elsewhere, where it would either find
                  nothing or find something that is not PowerShell at all.

Unlike ``Resolve-Python``, a candidate is not run to prove itself. The Windows
App Execution Alias problem that forces that there has no equivalent here:
neither PowerShell name is shimmed by the Store, and an extra process start on
the path of every bridge call would cost more than it proves.

Cached per process, because PATH does not change under a running agent and the
bridge asks on every request. ``resolve_host(force=True)`` re-reads it, which
is what the tests use.
"""

import shutil
import sys
from typing import NamedTuple

#: PowerShell 7+, preferred wherever it exists.
PWSH = "pwsh"

#: Windows PowerShell 5.1's executable, probed on Windows only.
WINDOWS_POWERSHELL = "powershell"

#: What a caller says when neither is on PATH. Names both, because "PowerShell
#: was not found" leaves a reader on the 5.1 floor wondering whether their
#: 5.1 counts.
NO_HOST_ERROR = (
    f"No PowerShell host found on PATH: tried '{PWSH}' (PowerShell 7+) "
    f"and '{WINDOWS_POWERSHELL}' (Windows PowerShell 5.1, Windows only)."
)


class PowerShellHost(NamedTuple):
    """``name`` is what a reader can retype; ``path`` is what gets executed."""

    name: str
    path: str


_cache: PowerShellHost | None = None
_resolved = False


def _find() -> PowerShellHost | None:
    found = shutil.which(PWSH)
    if found:
        return PowerShellHost(PWSH, found)
    if sys.platform == "win32":
        found = shutil.which(WINDOWS_POWERSHELL)
        if found:
            return PowerShellHost(WINDOWS_POWERSHELL, found)
    return None


def resolve_host(force: bool = False) -> PowerShellHost | None:
    """The PowerShell the agent's child processes run, or None if there is none."""
    global _cache, _resolved
    if _resolved and not force:
        return _cache
    _cache = _find()
    _resolved = True
    return _cache


def host_argv(script: str, *args: str) -> list[str] | None:
    """``<host> -NoProfile -File <script> [args...]``, or None with no host.

    One argv shape for both hosts. ``-NoProfile -File`` means the same thing to
    Windows PowerShell 5.1 as it does to PowerShell 7 -- the tokens after the
    script path are handed to it positionally, as strings -- so the contract
    ``bridge.ps1`` reads out of ``$args`` does not change with the host.
    """
    host = resolve_host()
    if host is None:
        return None
    return [host.path, "-NoProfile", "-File", script, *args]


def host_env_block() -> dict[str, str | None]:
    """What ``/env`` reports: which host was resolved, and where it is."""
    host = resolve_host()
    return {
        "resolved": host.name if host else None,
        "path": host.path if host else "",
    }
