"""How the agent reads a ``gh``, ``az`` or ``git`` child: one helper, UTF-8.

Every tracker read in the agent is ``subprocess.run`` with the output captured.
With ``text=True`` and no ``encoding``, Python decodes the child's bytes with the
locale's code page -- cp1252 on a Windows console -- while ``gh``, ``az`` and
``git`` write UTF-8. A byte cp1252 has no character for (0x81, 0x8d, 0x8f, 0x90,
0x9d) kills subprocess's reader thread, the call returns ``stdout=None`` with
exit code 0, and a caller that reads ``result.stdout or "[]"`` answers an empty
success. That is how the standup's issue read with bodies came back with
every worker empty on Windows while ``Standup`` in the CLI listed dozens.

So every such read goes through :func:`run_read`: decoded as UTF-8 with
``errors="replace"`` (a byte that is not UTF-8 becomes U+FFFD, it does not end
the read), and an output that still could not be read raises
:class:`ChildReadError` -- a caller states it as a reason, the way it states a
timeout, and never as an empty list.

The shell rule lives here. On Windows ``az`` is a ``.cmd`` file and needs the
shell; ``gh`` and ``git`` are real executables and do not, so they run without
one, on every host. An argv that is still bound for the shell may not carry a
character the shell reads as syntax: :func:`run_read` refuses it, for every
caller, as a reason and never a run.
"""

from __future__ import annotations

import platform
import subprocess

CHILD_ENCODING = "utf-8"

# The tools that need the shell on Windows: each is a .cmd, not an executable.
SHELL_TOOLS = frozenset({"az"})
# What cmd.exe reads as syntax, inside quotes or out.
SHELL_SYNTAX = '"&|<>^%\r\n'


class ChildReadError(RuntimeError):
    """The child ran, but what it wrote could not be read."""


def needs_shell(cmd: list[str]) -> bool:
    """Whether this argv runs through the shell by default: on Windows, for a
    tool that is a ``.cmd``."""
    return platform.system() == "Windows" and bool(cmd) and cmd[0] in SHELL_TOOLS


def shell_syntax_in(cmd: list[str]) -> str | None:
    """The first character of ``cmd`` the shell would read as syntax, or None."""
    for arg in cmd:
        for ch in arg:
            if ch in SHELL_SYNTAX:
                return ch
    return None


def run_read(
    cmd: list[str],
    timeout: float,
    *,
    shell: bool | None = None,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """Run ``cmd`` and return it with ``stdout``/``stderr`` as UTF-8 text.

    ``shell`` defaults to :func:`needs_shell`. A shell-bound argv holding shell
    syntax is refused with :class:`ChildReadError`, and nothing runs. ``env`` is the child's whole environment when
    given (the agent's own otherwise). Raises what ``subprocess.run`` raises (a
    missing CLI, ``TimeoutExpired``) and :class:`ChildReadError` when the output
    did not arrive -- never an empty success.
    """
    if shell is None:
        shell = needs_shell(cmd)
    if shell:
        ch = shell_syntax_in(cmd)
        if ch is not None:
            tool = cmd[0] if cmd else "the child"
            raise ChildReadError(f"{tool} was not run: an argument holds {ch!r}, which the shell would read")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding=CHILD_ENCODING,
        errors="replace",
        timeout=timeout,
        shell=shell,
        cwd=cwd,
        env=env,
        check=False,
    )
    if result.stdout is None:
        tool = cmd[0] if cmd else "the child"
        raise ChildReadError(f"{tool}'s output could not be read (exit code {result.returncode})")
    return result


def did_not_answer(tool: str, exc: BaseException) -> str:
    """The sentence for a read that raised: the unreadable output's own words,
    else ``<tool> did not answer (<ExceptionName>)`` -- the shape every gh read
    in the agent already speaks for a timeout or a missing CLI."""
    if isinstance(exc, ChildReadError):
        return str(exc)
    return f"{tool} did not answer ({exc.__class__.__name__})"
