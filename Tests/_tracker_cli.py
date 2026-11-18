"""No test reaches a real ``az`` or ``gh``: the guard ``conftest.py`` installs.

The agent's tests are meant to run with no tracker at all, and a machine that is
signed in to either tool must not answer differently from one that is not. So
for the whole run the two tools are out of reach, in two layers, because a test
can start them two ways:

1. **A stand-in on the PATH**, for every child: a folder holding an ``az`` and a
   ``gh`` goes first on ``PATH`` at import. A child PowerShell a test starts (the
   bridge, a typed verb) that calls either one gets the stand-in, which writes
   the command to a recording file, says so on stderr and exits non-zero.
2. **A check in this process**, on ``subprocess.run`` and ``subprocess.Popen``:
   an argv whose tool resolves, on the PATH the call would use, to the stand-in
   is refused before anything starts, and the command is recorded. The refusal
   is a ``FileNotFoundError``, so the code under test sees a tool that is not
   installed. It is needed beside the first layer because on Windows a process
   started without the shell only ever finds a ``.exe``, so it would walk past a
   ``.cmd`` stand-in to the real tool.

``conftest.py`` reads both recordings after every test and fails the test,
naming each command. A refusal alone would not do it: the agent's reads catch
every exception and answer "unreachable", which is how these calls went unseen.

**What counts as asking.** A test that stands in for the tool is never refused,
whichever way it does it: it patches ``subprocess.run`` (``mock.patch.object(
tier.subprocess, "run", fake)``), it puts a folder with its own ``gh`` ahead on
the PATH, or it defines a ``gh`` function in the child PowerShell. A test whose
code under test asks a tool in passing, and which only needs the answer "not
there", says so with the marker, on a test or a class::

    from _tracker_cli import unreachable

    @unreachable("az", "gh")

(``pytest.mark.tracker_cli_unreachable`` is the same thing.) The named tools
stay out of reach and the calls to them are not held against the test.
"""

from __future__ import annotations

import atexit
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _rmtree import remove_tree

TOOLS = ("az", "gh")
MARKER = "tracker_cli_unreachable"
STAND_IN_EXIT = 97
_SUFFIXES = (".exe", ".cmd", ".bat")

# The folder of stand-ins and the file they write to, made by install(): a test
# file run on its own imports this module for the marker and installs nothing.
STAND_IN_DIR: Path | None = None
RECORDING: Path | None = None

_REAL_RUN = subprocess.run
_REAL_POPEN = subprocess.Popen

# The calls this process refused since the last drain: "<tool> <arguments>".
_refused: list[str] = []


class TrackerCliNotStubbed(FileNotFoundError):
    """A test reached ``az`` or ``gh`` without standing in for it."""


def _write_stand_ins() -> None:
    """One stand-in per tool: a ``sh`` script, or on Windows a ``.cmd`` that
    hands its arguments to this Python, so nothing is echoed through cmd.exe."""
    recorder = STAND_IN_DIR / "record_call.py"
    recorder.write_text(
        "import sys\n"
        f"with open({str(RECORDING)!r}, 'a', encoding='utf-8') as f:\n"
        "    f.write(' '.join(sys.argv[1:]) + '\\n')\n"
        "sys.stderr.write(sys.argv[1] + ': the test run keeps this tool out of reach (Tests/_tracker_cli.py)\\n')\n"
        f"sys.exit({STAND_IN_EXIT})\n",
        encoding="utf-8",
    )
    for tool in TOOLS:
        if os.name == "nt":
            (STAND_IN_DIR / f"{tool}.cmd").write_text(
                f'@"{sys.executable}" "{recorder}" {tool} %*\r\n', encoding="utf-8"
            )
        else:
            script = STAND_IN_DIR / tool
            script.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"{tool} $*\" >> '{RECORDING}'\n"
                f"echo '{tool}: the test run keeps this tool out of reach (Tests/_tracker_cli.py)' >&2\n"
                f"exit {STAND_IN_EXIT}\n",
                encoding="utf-8",
            )
            script.chmod(0o755)


def _argv(args) -> list[str]:
    if isinstance(args, (str, bytes, os.PathLike)):
        text = os.fsdecode(args)
        return text.split() if isinstance(args, (str, bytes)) else [text]
    return [os.fsdecode(a) for a in args]


def _tool_of(argv: list[str]) -> str | None:
    """The guarded tool this argv starts, or None: ``gh``, ``gh.exe``, ``az.cmd``."""
    if not argv:
        return None
    name = argv[0].lower()
    for suffix in _SUFFIXES:
        name = name.removesuffix(suffix)
    return name if name in TOOLS else None


def _is_stand_in(argv: list[str], env) -> bool:
    """Whether the PATH this call would use answers ``argv[0]`` with the
    stand-in. A test's own stub, ahead on the PATH or named by its path, is not
    the stand-in; nor is a PATH with neither on it."""
    if STAND_IN_DIR is None:
        return False
    path = (env or os.environ).get("PATH", "")
    found = shutil.which(argv[0], path=path)
    if found is None:
        return False
    try:
        return Path(found).resolve().parent == STAND_IN_DIR.resolve()
    except OSError:
        return False


def _refuse(args, env) -> None:
    argv = _argv(args)
    tool = _tool_of(argv)
    if tool is None or not _is_stand_in(argv, env):
        return
    command = " ".join([tool, *argv[1:]])
    _refused.append(command)
    raise TrackerCliNotStubbed(f"a test called `{command}` without standing in for it (Tests/_tracker_cli.py)")


def _guarded_run(*popenargs, **kwargs):
    args = popenargs[0] if popenargs else kwargs.get("args")
    if args is not None:
        _refuse(args, kwargs.get("env"))
    return _REAL_RUN(*popenargs, **kwargs)


class _GuardedPopen(_REAL_POPEN):
    def __init__(self, args, *rest, **kwargs):
        _refuse(args, kwargs.get("env"))
        super().__init__(args, *rest, **kwargs)


def install() -> None:
    """Put both layers in place. Called once, when ``conftest.py`` is imported:
    collection already starts children."""
    global STAND_IN_DIR, RECORDING
    STAND_IN_DIR = Path(tempfile.mkdtemp(prefix="p20-test-tracker-cli-"))
    RECORDING = STAND_IN_DIR / "calls.txt"
    _write_stand_ins()
    os.environ["PATH"] = str(STAND_IN_DIR) + os.pathsep + os.environ.get("PATH", "")
    subprocess.run = _guarded_run
    subprocess.Popen = _GuardedPopen
    atexit.register(remove_tree, str(STAND_IN_DIR))


def drain() -> list[str]:
    """Every command recorded since the last drain, from both layers, and forget
    them: ``"gh api user -q .login"``."""
    calls = list(_refused)
    _refused.clear()
    text = ""
    if RECORDING is not None:
        try:
            text = RECORDING.read_text(encoding="utf-8", errors="replace")
            RECORDING.unlink()
        except OSError:
            text = ""
    calls.extend(line for line in text.splitlines() if line.strip())
    return calls


def unasked(calls: list[str], declared: tuple[str, ...]) -> list[str]:
    """The calls a test is answerable for: those to a tool it did not name in
    its marker."""
    return [c for c in calls if c.split(" ", 1)[0] not in declared]


def unreachable(*tools: str):
    """The marker, as a decorator for a test or a class: ``@unreachable("az")``.
    Without pytest (a test file run on its own) it changes nothing."""
    try:
        import pytest
    except ImportError:
        return lambda decorated: decorated
    return getattr(pytest.mark, MARKER)(*tools)
