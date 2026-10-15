"""The bridge: POST /cmd/{name} -- every write goes through the CLI.

Reads stay native Python because a page render must not fork a PowerShell
process per card. Writes do the opposite: they go into the Toolkit's own
PowerShell so there is exactly one implementation of archiving a card, opening
a PR or closing a work item, and the web UI and the terminal cannot drift.

Three things make this a bridge rather than a second command surface:

**The allowlist is derived, not kept.** It is the key set of the CLI's own
``$script:ModuleState.CommandMap``, read through ``Get-P20CommandMap`` and cached against
the mtimes of everything the table depends on: ``utilities.psm1``, the two
config files (a module's verbs are in the table only while its ``features.*``
flag is on) and ``Config/*.commands.psd1`` (D-CM, where a module declares
them). Nothing in this file names a command. Add a verb as docs/ARCHITECTURE.md,
"The bridge", says and it is bridgeable with no edit here; delete
one and it stops being bridgeable the moment the module file changes; flip a
flag from a terminal or from the Configuration card and the next request sees
the new table. The package this was carved from hand-kept a Python dict of prefixed
names instead, eight of which named commands this module does not own -- the
drift that pattern produces is the reason for this one.

**The function is invoked, never a prefixed alias.** The map's values are
function names (``Move-P20PromptToArchive``). The prefix is data and can be
anything, or several things at once, so an alias is not a stable name.

**Parameters travel as process argv.** ``bridge.ps1`` reads them out of
``$args``; no command string is built or parsed anywhere on either side. That
is why a card title with spaces, a comment with an apostrophe and a parameter
that begins with ``-`` all pass through untouched, and why the old regex that
refused anything containing a space is gone -- it was guarding a string
concatenation that no longer exists.

Timeouts are per command, on the command's own config entry
(``commands.<Name>.bridgeTimeoutSeconds``), defaulting to
``DEFAULT_TIMEOUT_SECONDS``.

**Which PowerShell** is ``core.hosts``' answer, not a literal here: ``pwsh``
where it exists, ``powershell.exe`` on a Windows machine that has only the 5.1
floor the README promises. With neither, nothing can run, and a call says so --
``status: error`` naming both names it tried, rather than ``rejected``, which
would blame the command for the machine.
"""

import asyncio
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..core import config as _config
from ..core.assets import remove_upload
from ..core.config import REPO_ROOT, load_config
from ..core.hosts import NO_HOST_ERROR, host_argv, resolve_host
from ..core.log_writer import write_log
from .status import pinned_cache_clear

api = APIRouter()

BRIDGE_PS1 = Path(__file__).resolve().parent / "bridge.ps1"
UTILITIES = REPO_ROOT / "utilities.psm1"

# Where a module declares its verbs (D-CM): the CLI's `$moduleCommandDir` and
# the filter it lists with, in utilities.psm1's module loader.
MODULE_COMMANDS_DIR = REPO_ROOT / "Config"
MODULE_COMMANDS_SUFFIX = ".commands.psd1"

# Absent a `bridgeTimeoutSeconds` on the command's config entry. Generous on
# purpose: the floor is one PowerShell start plus a module import, and a verb
# that talks to ADO is slower than that again. A command that genuinely needs
# a shorter leash says so in config rather than here.
DEFAULT_TIMEOUT_SECONDS = 120

# Reading the map costs a PowerShell start, so it is cached -- but keyed on the
# mtimes of what the table is built from, not forever. Edit utilities.psm1,
# flip a flag in config.local.json or add a Config/*.commands.psd1 and the next
# request re-reads it; that is what makes "add a row, it is bridgeable" and "a
# flag change needs no restart" true.
_MAP_TIMEOUT_SECONDS = 60

# Parameter limits. Not injection guards -- argv cannot be injected into -- but
# resource ones: a caller must not be able to hand a child process a megabyte
# of argv or a thousand arguments.
MAX_PARAMS = 32
MAX_PARAM_LENGTH = 4096

# Control characters have no meaning in a work-item id, a filename or a review
# comment, and several of them mean something to a terminal. Tab, newline and
# carriage return are the exceptions: they are ordinary inside a PR reply body
# and argv carries them without escaping.
_PERMITTED_CONTROL = {"\t", "\n", "\r"}


def _child_env() -> dict[str, str]:
    """Environment for the child PowerShell.

    ``NO_COLOR`` because PowerShell 7 writes VT colour sequences even to a
    redirected stdout, and the output of a command is shown to a person in a
    browser, not to a terminal that can render them. ``TOOLKIT_QUIET_STARTUP``
    belts-and-braces the same suppression ``bridge.ps1`` sets for itself.
    """
    return {**os.environ, "NO_COLOR": "1", "TOOLKIT_QUIET_STARTUP": "1"}


class CommandRequest(BaseModel):
    params: list[str] = Field(default_factory=list)


class CommandResponse(BaseModel):
    command: str
    status: str  # success | error | rejected | timeout
    exit_code: int
    output: str | None = None
    error: str | None = None
    duration: int  # milliseconds


# --------------------------------------------------------------------------
# The allowlist, derived from the CLI's command table
# --------------------------------------------------------------------------

_map_cache: dict[str, str] = {}
_map_key: tuple | None = None

# "Logged once": see _read_command_map.
_no_host_logged = False


def _mtime(path: Path) -> tuple | None:
    """A file's identity for the cache key: ``None`` when it is not there, else
    ``(mtime_ns, size, content digest)``. The mtime alone can repeat across two
    writes (a coarse filesystem clock, or a write in the same tick as the last
    read), so the size and a digest of the bytes decide it too."""
    try:
        st = path.stat()
        digest = hashlib.blake2b(path.read_bytes(), digest_size=8).hexdigest()
        return (st.st_mtime_ns, st.st_size, digest)
    except OSError:
        return None


def _map_key_now() -> tuple:
    """Everything the command table depends on, as one comparable value.

    ``utilities.psm1`` defines the core verbs; the two config files decide
    which module flags are on, and a module's verbs are in the table only while
    its flag is; ``Config/*.commands.psd1`` is where a module declares them. A
    file that is not there is ``None``, so its appearance is a change too.
    """
    modules: list[tuple[str, tuple | None]] = []
    try:
        for f in sorted(MODULE_COMMANDS_DIR.iterdir()):
            if f.is_file() and f.name.endswith(MODULE_COMMANDS_SUFFIX):
                modules.append((f.name, _mtime(f)))
    except OSError:
        pass
    return (
        _mtime(UTILITIES),
        _mtime(_config.DEFAULT_CONFIG_PATH),
        _mtime(_config.LOCAL_CONFIG_PATH),
        tuple(modules),
    )


def _read_command_map() -> dict[str, str]:
    """Run Get-P20CommandMap through the bridge and parse its one line of JSON."""
    argv = host_argv(str(BRIDGE_PS1), "Get-P20CommandMap")
    if argv is None:
        # No PowerShell at all: an empty map, not an exception -- /env still
        # answers and the route below reports the real cause. Logged once per
        # process, because a failed read is deliberately not cached and this
        # would otherwise write a line per request forever.
        global _no_host_logged
        if not _no_host_logged:
            write_log("ERR", "Agent/command-map", NO_HOST_ERROR)
            _no_host_logged = True
        return {}

    try:
        result = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_MAP_TIMEOUT_SECONDS,
            cwd=str(REPO_ROOT),
            env=_child_env(),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        write_log("ERR", "Agent/command-map", f"{type(e).__name__}: {e}")
        return {}

    if result.returncode != 0:
        write_log("ERR", "Agent/command-map", (result.stderr or "").strip()[:200])
        return {}

    # The last line that opens an object. Under -File, PowerShell folds the
    # warning stream into stdout, so anything the toolkit says on its way up
    # would otherwise sit in front of the JSON. bridge.ps1 silences the import
    # for exactly this reason; this is the second lock on the same door.
    lines = [ln.strip() for ln in result.stdout.splitlines() if ln.strip().startswith("{")]
    if not lines:
        write_log("ERR", "Agent/command-map", "no JSON object in output")
        return {}

    try:
        parsed = json.loads(lines[-1])
    except json.JSONDecodeError as e:
        write_log("ERR", "Agent/command-map", f"unparseable map: {e}")
        return {}

    if not isinstance(parsed, dict):
        write_log("ERR", "Agent/command-map", "map is not an object")
        return {}

    # The reserved key carries every declared bridgeTimeoutSeconds -- a core
    # verb's from config, a module verb's from its data file -- so the agent
    # reads ONE table and never a .psd1. It is kept beside the map, keyed the
    # same way, and stripped from what callers see as the allowlist.
    global _timeouts
    raw_timeouts = parsed.pop("_timeouts", None)
    if isinstance(raw_timeouts, dict):
        _timeouts = {str(k): int(v) for k, v in raw_timeouts.items() if str(v).isdigit()}
    else:
        _timeouts = {}

    return {str(k): str(v) for k, v in parsed.items()}


def command_map(force: bool = False) -> dict[str, str]:
    """The live ``Name -> Function`` table, cached against ``_map_key_now()``.

    ``force`` re-reads whatever the key says; ``PUT /api/config`` passes it
    after a successful write, because the write itself went through the bridge
    and primed the cache with the table as it stood BEFORE the flag flipped.

    A failed read is not cached: the next request tries again rather than
    leaving the bridge permanently refusing everything because PowerShell was
    briefly unavailable.
    """
    global _map_cache, _map_key

    key = _map_key_now()
    if _map_cache and not force and key[0] is not None and key == _map_key:
        return _map_cache

    fresh = _read_command_map()
    if fresh:
        _map_cache = fresh
        _map_key = key
    return fresh


_timeouts: dict[str, int] = {}


def command_timeout(name: str) -> int:
    """Per-command timeout: what the command table declared (a core verb's
    ``commands.<Name>.bridgeTimeoutSeconds``, a module verb's Help entry --
    both arrive in the map's ``_timeouts``), else the config entry, else the
    default."""
    command_map()
    if name in _timeouts:
        return _timeouts[name]
    entry = (load_config().get("commands") or {}).get(name) or {}
    value = entry.get("bridgeTimeoutSeconds")
    try:
        seconds = int(value)
    except (TypeError, ValueError):
        return DEFAULT_TIMEOUT_SECONDS
    if seconds <= 0:
        return DEFAULT_TIMEOUT_SECONDS
    return seconds


def reject_reason(params: list[str]) -> str | None:
    """Why these parameters cannot be passed on, or None if they can."""
    if len(params) > MAX_PARAMS:
        return f"Too many parameters: {len(params)} (limit {MAX_PARAMS})."
    for p in params:
        if len(p) > MAX_PARAM_LENGTH:
            return f"Parameter too long: {len(p)} characters (limit {MAX_PARAM_LENGTH})."
        for ch in p:
            if ch in _PERMITTED_CONTROL:
                continue
            if ord(ch) < 0x20 or ord(ch) == 0x7F:
                return f"Parameter contains a control character (0x{ord(ch):02X})."
    return None


# --------------------------------------------------------------------------
# The route
# --------------------------------------------------------------------------


def _run(
    function: str,
    params: list[str],
    timeout: int,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """Run one function of the CLI in a child PowerShell.

    ``extra_env`` is for a caller that has to tell the child something the
    child would otherwise resolve on its own -- the manager create passes
    ``PROMPTS_ROOT`` so the verb writes into the hub this process resolved,
    not a hub the child's own config read might name differently.
    """
    argv = host_argv(str(BRIDGE_PS1), function, *params)
    if argv is None:
        raise OSError(NO_HOST_ERROR)
    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        cwd=str(REPO_ROOT),
        env={**_child_env(), **(extra_env or {})},
        check=False,
    )


@api.post("/cmd/{name}", response_model=CommandResponse)
async def run_command(name: str, req: CommandRequest | None = None):
    """Run one allowlisted CLI verb (see ``_run_command``), then drop any upload folder
    among its parameters: a picture the browser staged for ``Cover`` or
    ``NewPrompt -Cover`` is a temp file the verb only copies, so whatever the
    outcome, the folder is finished with. ``remove_upload`` touches nothing that
    is not a ``p20-upload-`` folder directly under the system temp."""
    try:
        return await _run_command(name, req)
    finally:
        for p in req.params if req else []:
            remove_upload(p)


async def _run_command(name: str, req: CommandRequest | None = None):
    """Run one allowlisted CLI verb and report what it did.

    Always 200 with a typed body, including refusals: a client that types the
    reply as a ``CommandResponse`` renders every outcome the same way, and the
    four ``status`` values say which outcome it was.

      success   the verb ran and exited 0
      error     the verb ran and exited non-zero; ``error`` is its stderr --
                or nothing could run because this machine has no PowerShell,
                which is a fact about the machine and not about the name
      rejected  nothing ran -- the name is not in the CLI's command table, or a
                parameter broke the limits above
      timeout   the verb ran past its ``bridgeTimeoutSeconds`` and was killed
    """
    params = list(req.params) if req else []
    start = time.monotonic()

    # Before the allowlist, because with no host the allowlist is empty and
    # every name would otherwise be refused as "not a command in this CLI" --
    # which is what a machine with only Windows PowerShell saw, and it misstates the cause.
    if resolve_host() is None:
        write_log("ERR", f"Agent/{name}", NO_HOST_ERROR[:200])
        return CommandResponse(
            command=name,
            status="error",
            exit_code=-1,
            output=None,
            error=NO_HOST_ERROR,
            duration=0,
        )

    table = command_map()
    if name not in table:
        detail = (
            f"'{name}' is not a command in this CLI."
            if table
            else "The CLI command table could not be read; no command can run."
        )
        write_log("ERR", f"Agent/{name}", detail[:200])
        return CommandResponse(
            command=name,
            status="rejected",
            exit_code=-1,
            output=None,
            error=detail,
            duration=0,
        )

    bad = reject_reason(params)
    if bad:
        write_log("ERR", f"Agent/{name}", bad[:200])
        return CommandResponse(
            command=name,
            status="rejected",
            exit_code=-1,
            output=None,
            error=bad,
            duration=0,
        )

    function = table[name]
    timeout = command_timeout(name)

    try:
        result = await asyncio.to_thread(_run, function, params, timeout)
    except subprocess.TimeoutExpired:
        duration = int((time.monotonic() - start) * 1000)
        write_log("ERR", f"Agent/{name}", f"timeout after {timeout}s")
        return CommandResponse(
            command=name,
            status="timeout",
            exit_code=-1,
            output=None,
            error=f"Command timed out after {timeout} seconds.",
            duration=duration,
        )
    except OSError as e:
        duration = int((time.monotonic() - start) * 1000)
        write_log("ERR", f"Agent/{name}", f"{type(e).__name__}: {e}")
        return CommandResponse(
            command=name,
            status="error",
            exit_code=-1,
            output=None,
            error=f"Could not start PowerShell: {e}",
            duration=duration,
        )

    duration = int((time.monotonic() - start) * 1000)

    if name == "EditItem":
        # A pin may have changed; the Board's pinned set is read again.
        pinned_cache_clear()

    if result.returncode == 0:
        write_log("CMD", f"Agent/{name}", "ok")
        return CommandResponse(
            command=name,
            status="success",
            exit_code=0,
            output=result.stdout,
            error=None,
            duration=duration,
        )

    stderr = (result.stderr or "").strip()
    write_log("ERR", f"Agent/{name}", stderr[:200])
    return CommandResponse(
        command=name,
        status="error",
        exit_code=result.returncode,
        output=result.stdout,
        error=stderr,
        duration=duration,
    )
