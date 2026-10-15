"""Remove a scratch tree the way Windows needs it removed.

``shutil.rmtree(p, ignore_errors=True)`` leaves a folder behind on Windows the
moment one file in it is read-only -- a git object under a scratch hub is --
and says nothing, so ``%TEMP%`` fills with the suites' leftovers.
This clears
the read-only bit and retries, and REPORTS what it still could not delete rather
than swallowing it. Python 3.12 renamed the hook (``onexc``); both spellings work.
"""

from __future__ import annotations

import os
import shutil
import stat
import sys
from pathlib import Path


def remove_tree(path: str | os.PathLike) -> list[str]:
    """Delete ``path`` and everything under it. Returns the paths it could not delete."""
    leftovers: list[str] = []

    def _clear_and_retry(func, target, exc_info):
        try:
            os.chmod(target, stat.S_IWRITE | stat.S_IREAD)
            func(target)
        except Exception:  # reported below, never raised
            leftovers.append(str(target))

    p = Path(path)
    if not p.exists():
        return leftovers
    shutil.rmtree(p, onexc=_clear_and_retry)
    if p.exists() and str(p) not in leftovers:
        leftovers.append(str(p))
    for left in leftovers:
        print(f"Tests: could not remove {left}", file=sys.stderr)
    return leftovers
