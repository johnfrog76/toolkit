"""The Solitaire Agile add-on: the ceremonies, played alone, from the tracker.

M0 is one ceremony, the standup (``standup.py``); V1 adds triage (``triage.py``,
the open issues by milestone). Each is derived on every request from
what the Space's GitHub tracker says now -- nothing is stored
(docs/modules/solitaire-agile.md, "What it owns"). ``api`` is what
``agent/app.py`` mounts; it is gated per request on the engineer-scoped
``features.solitaireAgile`` and answers 404 when that is off -- the status a
module that was never written would give.

Every route but one is a READ. The CLI's ``Standup`` renders the same text from
the same two data files, and one fixture holds both halves to it. The one that
is not -- attending, in ``remind.py`` -- writes nothing itself either: it
re-arms the standup's Organize reminder by running Organize's own verbs through
the bridge.
"""

from . import (
    remind,  # noqa: F401 -- registers the reminder's two routes on ``api``
    triage,  # noqa: F401  -- registers GET /api/ritual/triage on the same router (V1)
)
from .standup import api

__all__ = ["api"]
