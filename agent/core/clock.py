"""The one way the agent turns a timestamp into a day or a time.

A day in this product is the engineer's LOCAL day. git's ``%ai`` carries the
AUTHOR's zone, so its first ten characters are the day where the commit was
made; every git read here asks for ``%at`` (seconds since the epoch) and
converts on the reader's clock. The CLI's twin is
``Scripts/ConvertTo-LocalDay.ps1``; ``Tests/fixtures/clock/local-days.json``
holds the two to one answer.
"""

from __future__ import annotations

from datetime import datetime, tzinfo


def local_day(epoch: str | float, tz: tzinfo | None = None) -> str | None:
    """Seconds since the epoch -> 'YYYY-MM-DD' on the local clock (or ``tz``).

    ``None`` for anything that is not a number.
    """
    try:
        seconds = float(str(epoch).strip())
    except (TypeError, ValueError):
        return None
    return datetime.fromtimestamp(seconds, tz).strftime("%Y-%m-%d")


def local_stamp(epoch: float, tz: tzinfo | None = None) -> str:
    """Seconds since the epoch -> 'YYYY-MM-DD HH:MM' on the local clock (or ``tz``)."""
    return datetime.fromtimestamp(epoch, tz).strftime("%Y-%m-%d %H:%M")
