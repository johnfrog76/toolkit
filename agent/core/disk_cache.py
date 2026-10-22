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

Two of the things kept here grow one record per thing ever read -- the parsed
rows (one per blob sha) and the standup's dressed replies (one file each) -- so
both are pruned by one rule when they are written: unseen for
``config.AGENT_CACHE_MAX_AGE_DAYS``, or past ``AGENT_CACHE_MAX_RECORDS`` records,
oldest-unseen first (``prune_seen``, ``prune_folder``). A prune never raises and
never fails the write it rides on.

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
import time
from pathlib import Path

from .config import AGENT_CACHE_MAX_AGE_DAYS, AGENT_CACHE_MAX_RECORDS
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


SECONDS_PER_DAY = 86400


def prune_seen(
    records: dict,
    seen: dict,
    *,
    now: float | None = None,
    max_records: int | None = None,
    max_age_days: float | None = None,
) -> tuple[dict, dict]:
    """``(records, seen)`` with the stale and the surplus gone.

    ``seen`` maps a record's key to the time it was last seen (epoch seconds). A
    record with no entry is stamped ``now`` -- a file written before the cap
    existed keeps its records for one full age, and is pruned from then on. Gone:
    every record unseen for ``max_age_days``, then -- past ``max_records`` -- the
    oldest-unseen first. The inputs are not changed; on any error they are
    returned as they were, because a prune that cannot run leaves the cache alone."""
    try:
        moment = time.time() if now is None else now
        max_records = AGENT_CACHE_MAX_RECORDS if max_records is None else max_records
        max_age_days = AGENT_CACHE_MAX_AGE_DAYS if max_age_days is None else max_age_days
        stamps = {k: (seen[k] if isinstance(seen.get(k), (int, float)) else moment) for k in records}
        cutoff = moment - max_age_days * SECONDS_PER_DAY
        keep = [k for k in records if stamps[k] >= cutoff]
        if len(keep) > max_records:
            keep.sort(key=lambda k: stamps[k], reverse=True)  # stable: ties keep their order
            keep = keep[:max_records]
        return {k: records[k] for k in keep}, {k: stamps[k] for k in keep}
    except Exception:  # noqa: BLE001 -- a prune never fails a write
        return records, seen


def touch(*segments: str) -> None:
    """Mark a file as seen now (its modification time), for ``prune_folder``."""
    path = cache_path(*segments)
    if path is not None:
        try:
            os.utime(path, None)
        except OSError:
            pass


def prune_folder(
    *segments: str,
    now: float | None = None,
    max_records: int | None = None,
    max_age_days: float | None = None,
) -> int:
    """Delete the files of one cache folder unseen for ``max_age_days``, then --
    past ``max_records`` -- the oldest-unseen first; the number deleted. A file's
    last-seen time is its modification time: a write sets it and ``touch`` sets it
    again on a hit, so no second record of it is kept. Any error stops the prune
    where it is and leaves the rest: the caller carries on."""
    folder = cache_path(*segments)
    if folder is None:
        return 0
    gone = 0
    try:
        moment = time.time() if now is None else now
        max_records = AGENT_CACHE_MAX_RECORDS if max_records is None else max_records
        max_age_days = AGENT_CACHE_MAX_AGE_DAYS if max_age_days is None else max_age_days
        cutoff = moment - max_age_days * SECONDS_PER_DAY
        files = []
        for entry in os.scandir(folder):
            # A dot-file beside the target is a write in flight.
            if entry.is_file() and not entry.name.startswith("."):
                files.append((entry.stat().st_mtime, entry.path))
        files.sort(reverse=True)  # newest-seen first
        for index, (mtime, path) in enumerate(files):
            if mtime < cutoff or index >= max_records:
                Path(path).unlink(missing_ok=True)
                gone += 1
    except Exception:  # noqa: BLE001, S110 -- a prune never fails a write
        pass
    return gone
