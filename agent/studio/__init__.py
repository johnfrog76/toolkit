"""The Studio: the studio developer's view across their products.

The foyer reads ``/env``'s spaces, every GitHub Space's facts in one read
(``ledger.py``: one GraphQL call for all of them, kept on disk), and the core's
``/status`` per other Space; what this package also serves is the hub's ``design/``
folder, the seed drawer (``notes.py``), and the repositories the Spaces card's +
offers (``spaces.py``). ``api`` is what ``agent/app.py`` mounts,
and it is always mounted: the Studio is core, from day one, with no flag
(D-S13; docs/modules/studio.md). It also serves the agentic prompts,
ToolKit's and the hub's, for the Prompts card (``prompts.py``).

Every route here is a READ. A note is created by ``NewDesign`` and promoted by
``NewItem -FromDesign``, and a Space is added by ``NewSpace``, through
``POST /api/cmd/{name}`` like every other write.
"""

from fastapi import APIRouter

from . import ledger, notes, prompts, spaces

api = APIRouter()
api.include_router(notes.api)
api.include_router(spaces.api)
api.include_router(prompts.api)
api.include_router(ledger.api)

__all__ = ["api"]
