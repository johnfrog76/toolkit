"""The day each file in a folder last changed, from ONE ``git log``.

Two readers want the same fact about a folder of files -- when each one last
changed -- and both used to be able to ask git once per file. One log for the
whole folder answers all of them: ``git log`` is newest first, so the first time
a file is named is its last change.

- ``folder_changes`` is the one call: a set of pathspecs under one folder, every
  file directly inside one of them, keyed by its path relative to the folder.
  The status route reads a Space's ``current/`` and ``backlog/`` with it in one
  call (agent/ado/status.py).
- ``folder_history`` is the Studio prompts' read of one folder: the same map by
  file name, plus the URL base its rows link a file's history from
  (agent/studio/prompts.py).

The CLI's twin is Scripts/Get-PromptStatus.ps1's one log for ``current/``;
Tests/fixtures/status-modified/ pins the day both derive, from both suites.
Without a rename or merge commit that dropped a change, the first naming is
exactly what ``git log -1 -- <file>`` answered per card: a renamed or moved
card's day is the commit that renamed or moved it, in both.

Read only; nothing raises. Outside a clone, or when git cannot answer, there is
no map, and each caller falls back to the file's mtime.
"""

from __future__ import annotations

import re
import subprocess
from collections.abc import Sequence
from pathlib import Path

from .child import ChildReadError, run_read
from .clock import local_day

GITHUB_REMOTE = re.compile(r"github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$")

# The record separator: a NUL before each commit line, which no path can hold.
_LOG_FORMAT = "--format=%x00%H %at"


def git_read(args: list[str], cwd: Path) -> str | None:
    """stdout of one git read in ``cwd``, or None when git cannot answer."""
    try:
        result = run_read(["git", *args], 10, shell=False, cwd=str(cwd))
    except (OSError, subprocess.SubprocessError, ValueError, ChildReadError):
        return None
    return result.stdout if result.returncode == 0 else None


def folder_changes(folder: Path, paths: Sequence[str] = (".",)) -> dict[str, tuple[str, str]] | None:
    """{path relative to ``folder``: (local day, sha)} from ONE ``git log``.

    ``paths`` are pathspecs relative to ``folder`` (``"."`` is the folder
    itself); a file counts when it sits directly inside one of them, so a
    subfolder's files are not mixed in. Keys use ``/``: ``"x.md"`` for ``"."``,
    ``"current/x.md"`` for ``"current"``. None when git could not answer -- not
    a clone, no git, a timeout -- which is a different answer from ``{}``, a
    clone with nothing committed under those paths.
    """
    if not folder.is_dir():
        return None
    specs = [p.strip("/") or "." for p in paths]
    log = git_read(["-c", "core.quotepath=off", "log", _LOG_FORMAT, "--name-only", "--relative", "--", *specs], folder)
    if log is None:
        return None
    parents = {"" if s == "." else s for s in specs}
    changes: dict[str, tuple[str, str]] = {}
    for record in log.split("\x00"):
        lines = [ln.strip() for ln in record.strip().splitlines() if ln.strip()]
        if not lines:
            continue
        sha, _, at = lines[0].partition(" ")
        for name in lines[1:]:
            parent = name.rpartition("/")[0]
            if parent in parents and name not in changes:
                changes[name] = (local_day(at) or "", sha)
    return changes


def folder_history(folder: Path) -> tuple[dict[str, tuple[str, str]], str]:
    """({file name: (local day, sha)}, history URL base) for one folder.

    One ``git log`` for the whole folder (``folder_changes``). The base is
    ``https://github.com/<owner>/<repo>/commits/{sha}/<prefix>`` when the clone's
    origin is on GitHub, "" otherwise -- and nothing at all outside a clone.
    """
    changes = folder_changes(folder)
    if changes is None:
        return {}, ""
    base = ""
    origin = (git_read(["remote", "get-url", "origin"], folder) or "").strip()
    m = GITHUB_REMOTE.search(origin)
    prefix = git_read(["rev-parse", "--show-prefix"], folder)
    if m and prefix is not None:
        base = f"https://github.com/{m.group(1)}/{m.group(2)}/commits/{{sha}}/{prefix.strip()}"
    return changes, base
