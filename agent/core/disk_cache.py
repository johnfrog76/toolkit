"""The agent's on-disk cache: what it may keep between runs, and where.

The agent keeps one kind of thing on disk that is not the hub's: what it has
already READ through the tracker and can prove has not changed. A git blob's sha
is a hash of its bytes, so anything worked out from a blob -- a design note's
parsed row, a note's body -- is valid for exactly as long as the sha is, which is
forever. ``agent/ado/repo_read.py`` is the one reader that writes here.

Where it lives (docs/CONFIGURATION.md, "The agent's cache"):

- ``P20_AGENT_CACHE_DIR`` (``consts.json`` ``env.agentCacheDir``), when set --
  the test runners point it at a scratch folder, so no suite writes the real one;
- else the platform's user cache folder: ``%LOCALAPPDATA%\\ToolKit\\Cache`` on
  Windows, ``~/Library/Caches/ToolKit`` on macOS, ``$XDG_CACHE_HOME/toolkit``
  (``~/.cache/toolkit``) elsewhere.

Never the hub, which is the engineer's record and may be synced; never the
package, whose tree ``Update`` refuses to move while it is dirty. Everything here
can be deleted at any time: the next read fetches it again.

Reads never raise: a missing, unreadable or malformed file is a miss. Writes go
to a temporary file beside the target and are moved into place, so a reader on
another thread sees the old file or the new one, never half of one; a write that
fails is dropped, because a cache that cannot be written is only slower.
"""

from __future__ import annotations

import json
import os
import platform
import re
import tempfile
from pathlib import Path

from .consts import env_agent_cache_dir

APP_DIR = "ToolKit"
# A segment of a cache path: letters, digits, dot, dash, underscore. Anything a
# caller names a namespace or a key with is held to it, so no key reaches outside
# the folder.
_SEGMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def cache_root() -> Path:
    """Where the agent's cache lives. Re-read per call, so a test that sets the
    variable after import still takes effect."""
    override = (os.environ.get(env_agent_cache_dir()) or "").strip()
    if override:
        return Path(override)
    system = platform.system()
    home = Path.home()
    if system == "Windows":
        base = os.environ.get("LOCALAPPDATA") or str(home / "AppData" / "Local")
        return Path(base) / APP_DIR / "Cache"
    if system == "Darwin":
        return home / "Library" / "Caches" / APP_DIR
    xdg = (os.environ.get("XDG_CACHE_HOME") or "").strip()
    return (Path(xdg) if xdg else home / ".cache") / APP_DIR.lower()


def cache_path(*segments: str) -> Path | None:
    """``cache_root()/a/b/...``, or None when a segment is not a plain name."""
    if not segments or not all(_SEGMENT.match(s or "") for s in segments):
        return None
    return cache_root().joinpath(*segments)


def _write(path: Path, data: str) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
                fh.write(data)
            os.replace(tmp, path)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
        return True
    except OSError:
        return False


def get_json(*segments: str) -> dict | None:
    """The JSON object at ``segments``, or None when there is none to read."""
    path = cache_path(*segments)
    if path is None:
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def put_json(data: dict, *segments: str) -> bool:
    path = cache_path(*segments)
    return False if path is None else _write(path, json.dumps(data, ensure_ascii=False, sort_keys=True))


def get_text(*segments: str) -> str | None:
    path = cache_path(*segments)
    if path is None:
        return None
    try:
        # Bytes, then decoded: read_text would turn a CRLF body into LF.
        return path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def put_text(text: str, *segments: str) -> bool:
    path = cache_path(*segments)
    return False if path is None else _write(path, text)
