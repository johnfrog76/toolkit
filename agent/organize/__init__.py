"""The Organize add-on: where the things a person keeps in order live.

Reminders is its first surface (``reminders.py``); Reference, the hub's documents
kept for reading, is its second (``reference.py``). ``api`` is what
``agent/app.py`` mounts; it is gated per request on the engineer-scoped
``features.organize`` and answers 404 when that is off -- the status a module
that was never written would give.

Every route here is a READ. A reminder is created, snoozed and archived by the
CLI's two verbs (NewReminder, Reminders), which the web reaches through
``POST /api/cmd/{name}`` like every other write: there is no second writer to
get the byte contract wrong. A reference document is filed by hand, and nothing
here writes it.
"""

from fastapi import APIRouter

from . import reference, reminders

# One router for the module: both surfaces carry the same organize gate.
api = APIRouter()
api.include_router(reminders.api)
api.include_router(reference.api)

__all__ = ["api"]
