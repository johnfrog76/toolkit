"""The session reader: which models worked in a Space's checkout during a window.

Read from Claude Code's own session files -- the files ``Burn`` reads
(docs/hub/usage.md, "Where the numbers come from"):

    <projects>/<project folder>/<session id>.jsonl
    <projects>/<project folder>/<session id>/subagents/agent-*.jsonl

A subagent's lines carry the PARENT's sessionId, so they count toward it.

The CLI's twin is ``Read-P20StandupSessions`` in Scripts/Standup-Rules.ps1, and
one table holds the two to each other: Tests/fixtures/rituals/standup-sessions.json,
its ``inside``, ``porcelain``, ``sessions`` and ``privacy`` sections, asserted from
Tests/test_rituals.py and ``tkTestToolkit -Rituals``.

Three pure rules and two thin reads:

- ``path_inside`` -- is this cwd inside one of these roots (separators either
  way; a Windows root compared ignoring case; ``/repo-two`` is not in ``/repo``).
- ``parse_worktree_porcelain`` -- ``git worktree list --porcelain`` -> roots.
- ``worktree_roots`` -- the ONE git read: the checkout, then its own worktrees;
  the checkout alone when git cannot answer.
- ``session_pairs`` -- (projects folder, window, roots) -> pairs.
- ``read_sessions`` -- the two together, only where ``claude_usage()`` says the
  projects folder is there.

What leaves: ``{"id", "sessionId"}`` pairs, distinct, ordered by id then by
sessionId, and nothing else. Only ``type``, ``message.model``, ``sessionId``,
``timestamp`` and ``cwd`` are read from a line; the cwd is compared here and
dropped. No path, project folder name or message text is returned or logged.
Files are opened read-only. Nothing here raises, and nothing calls it yet.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path

from ..core import config
from ..core import consts as C
from ..core.git_history import git_read


def _norm(path: str | None) -> str:
    """A path as the reader compares it: ``\\`` read as ``/``, trailing
    separators off (``/`` alone stays ``/``, ``C:/`` stays ``C:/``)."""
    if path is None:
        return ""
    p = str(path).strip().replace("\\", "/")
    if not p:
        return ""
    trimmed = p.rstrip("/")
    if not trimmed:
        return "/"
    if len(trimmed) == 2 and trimmed[1] == ":" and trimmed[0].isascii() and trimmed[0].isalpha():
        return trimmed + "/"
    return trimmed


def _windows_root(root: str) -> bool:
    return (len(root) >= 3 and root[0].isascii() and root[0].isalpha() and root[1:3] == ":/") or root.startswith("//")


def path_inside(path: str | None, roots: Sequence[str]) -> bool:
    """Whether ``path`` is one of ``roots`` or inside one, past a separator. Pure."""
    p = _norm(path)
    if not p:
        return False
    for root in roots:
        r = _norm(root)
        if not r:
            continue
        a, b = (p.casefold(), r.casefold()) if _windows_root(r) else (p, r)
        if a == b:
            return True
        prefix = b if b.endswith("/") else b + "/"
        if a.startswith(prefix):
            return True
    return False


def parse_worktree_porcelain(text: str | None) -> list[str]:
    """``git worktree list --porcelain`` -> the working folder of every worktree
    it lists, in its order; a bare entry is left out. CRLF or LF. Pure."""
    roots: list[str] = []
    current: str | None = None
    bare = False
    for line in (text or "").replace("\r", "").split("\n"):
        if not line or line.startswith("worktree "):
            if current is not None and not bare:
                roots.append(current)
            current = line[len("worktree ") :] if line else None
            bare = False
            continue
        if line == "bare":
            bare = True
    if current is not None and not bare:
        roots.append(current)
    return roots


def worktree_roots(checkout: str) -> list[str]:
    """The checkout, then its own git worktrees, from ONE ``git worktree list
    --porcelain`` in it; the checkout alone when git cannot answer."""
    roots = [checkout]
    try:
        out = git_read(["worktree", "list", "--porcelain"], Path(checkout))
    except Exception:  # noqa: BLE001 -- the fallback is the rule
        out = None
    if out is None:
        return roots
    for r in parse_worktree_porcelain(out):
        key = _norm(r).casefold()
        if all(_norm(x).casefold() != key for x in roots):
            roots.append(r)
    return roots


def _instant(value) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def _session_files(projects_root: Path, since: datetime) -> list[tuple[Path, str]]:
    """(path, the file's session) for every session file and subagent transcript
    last written on or after ``since`` -- Burn's walk, ``Get-P20ClaudeSessionFiles``."""
    cutoff = since.timestamp()
    files: list[tuple[Path, str]] = []

    def fresh(f: Path) -> bool:
        try:
            return f.is_file() and f.stat().st_mtime >= cutoff
        except OSError:
            return False

    try:
        projects = [d for d in projects_root.iterdir() if d.is_dir()]
    except OSError:
        return files
    for project in projects:
        try:
            entries = list(project.iterdir())
        except OSError:
            continue
        for f in entries:
            if f.suffix == ".jsonl" and fresh(f):
                files.append((f, f.stem))
        for d in entries:
            sub = d / "subagents"
            if not d.is_dir() or not sub.is_dir():
                continue
            try:
                subs = list(sub.iterdir())
            except OSError:
                continue
            for f in subs:
                if f.suffix == ".jsonl" and fresh(f):
                    files.append((f, d.name))
    return sorted(files, key=lambda pair: str(pair[0]))


def session_pairs(projects_root: Path, since: datetime, as_of: datetime, roots: Sequence[str]) -> list[dict]:
    """Every (model, session) with an assistant line in ``[since, as_of]`` whose
    model is not in ``models.notModels`` and whose cwd is inside ``roots``."""
    if since.tzinfo is None or as_of.tzinfo is None or not Path(projects_root).is_dir():
        return []
    start, end = since.astimezone(UTC), as_of.astimezone(UTC)
    not_models = set(C.model_not_models())
    seen: set[tuple[str, str]] = set()
    for path, file_session in _session_files(Path(projects_root), start):
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if '"assistant"' not in line:
                        continue
                    try:
                        o = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(o, dict) or o.get("type") != "assistant":
                        continue
                    message = o.get("message")
                    model = message.get("model") if isinstance(message, dict) else None
                    if not isinstance(model, str) or not model or model in not_models:
                        continue
                    at = _instant(o.get("timestamp"))
                    if at is None or at < start or at > end:
                        continue
                    cwd = o.get("cwd")
                    if not isinstance(cwd, str) or not path_inside(cwd, roots):
                        continue
                    session = o.get("sessionId")
                    session = file_session if session is None or session == "" else str(session)
                    seen.add((model, session))
        except OSError:
            continue
    return [{"id": mid, "sessionId": sid} for mid, sid in sorted(seen)]


def read_sessions(checkout: str | None, since: datetime, as_of: datetime) -> list[dict]:
    """The session read for a Space's checkout, where this machine has Claude
    Code's projects folder (``claude_usage()``); otherwise none, and nothing is
    opened."""
    if not checkout or not config.claude_usage():
        return []
    return session_pairs(config.claude_projects_root(), since, as_of, worktree_roots(checkout))
