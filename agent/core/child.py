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

The shell rule is the callers', unchanged: on Windows ``gh`` and ``az`` run
through the shell (``az.cmd`` needs it), so a ``&`` in an argument is cmd's
(AGENTS.md, "On Windows the agent runs gh through the shell");
``accounting.unsafe_for_shell`` refuses such an argv before it gets here.
"""

from __future__ import annotations

import platform
import subprocess

CHILD_ENCODING = "utf-8"


class ChildReadError(RuntimeError):
    """The child ran, but what it wrote could not be read."""


def run_read(
    cmd: list[str], timeout: float, *, shell: bool | None = None, cwd: str | None = None
) -> subprocess.CompletedProcess:
    """Run ``cmd`` and return it with ``stdout``/``stderr`` as UTF-8 text.

    ``shell`` defaults to True on Windows, which ``gh`` and ``az`` need; a
    ``git`` read passes False. Raises what ``subprocess.run`` raises (a missing
    CLI, ``TimeoutExpired``) and :class:`ChildReadError` when the output did not
    arrive -- never an empty success.
    """
    if shell is None:
        shell = platform.system() == "Windows"
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding=CHILD_ENCODING,
        errors="replace",
        timeout=timeout,
        shell=shell,
        cwd=cwd,
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
