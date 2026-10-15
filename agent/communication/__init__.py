"""The communication module: manager 1:1 sessions and the Teams engine.

Two halves, and only one of them is a design exercise. ``manager.py`` is the
read/write surface over ``<promptsRoot>/manager/`` -- the only PUT in the whole
API -- plus the route the retro send posts through. ``comms.py`` is the
communication engine itself, which shipped and was tested long before this
module existed and came across whole.

``api`` is what ``agent/app.py`` mounts. It is gated on the engineer-scoped
``features.communication``: the router mounts unconditionally, and every route
checks the flag per request through a dependency and answers 404 when it is
off -- the same status a module that was never written would give, chosen so
a client cannot tell "off" from "absent" (see manager.py).
"""

from .manager import api

__all__ = ["api"]
