"""Windows 8.3 short names, both ways, for the suites that build scratch trees.

On a Windows account whose name does not fit 8.3 (for example ``j.doe``), ``%TEMP%`` and
Python's ``tempfile`` hand out the SHORT form, ``C:\\Users\\<name>~1.<domain>\\...``.
PowerShell accepts it in ``Test-Path`` and refuses it in every call that
normalises a path through the FileSystem provider (``Push-Location``,
``Set-Location``, ``Move-Item``, ``Remove-Item``): "An object at the specified
path ``C:\\Users\\<name>~1.<domain>`` does not exist."

So a suite that hands a scratch path to a verb takes it LONG (``long_path``), and
the short form is tested on purpose, in its own case (``short_path``), so the
product's handling of it stays visible rather than accidental.

Both are the path unchanged off Windows, and whenever the OS has nothing to change.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def _kernel32_path(fn_name: str, path: str | os.PathLike) -> Path:
    p = str(path)
    if sys.platform != "win32":
        return Path(p)
    import ctypes

    fn = getattr(ctypes.windll.kernel32, fn_name)
    size = fn(p, None, 0)
    if not size:
        return Path(p)
    buf = ctypes.create_unicode_buffer(size)
    if not fn(p, buf, size):
        return Path(p)
    return Path(buf.value)


def long_path(path: str | os.PathLike) -> Path:
    """``path`` with every 8.3 short segment expanded (GetLongPathNameW). Must exist."""
    if sys.platform != "win32" or "~" not in str(path):
        return Path(path)
    return _kernel32_path("GetLongPathNameW", path)


def short_path(path: str | os.PathLike) -> Path:
    """``path`` in its 8.3 short form (GetShortPathNameW), or unchanged when the volume
    makes no short names. Must exist. A caller compares and skips on equality."""
    return _kernel32_path("GetShortPathNameW", path)
