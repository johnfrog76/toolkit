"""The FastAPI application: CORS, the /api router, and module mounting.

Run it from the package root:

    python3 -m uvicorn agent.app:app --port 4100

Two modules mount today. ``core`` is always on -- health, env, tier, the log
and the prompt-file parsers. ``ado`` is the Azure DevOps surface: prompt
status, PR comments, accounting, reporting over the archive, sprint awareness
(gated on features.sprintAwareness) and the CLI bridge.

``growth`` is the first opt-in module: /growth*, /resume*, /reviews*,
/review-preview and /review/generate, gated per request on features.growth and
404 when it is off (docs/modules/growth.md). ``communication`` and
``organize`` follow the same shape: organize's one route is GET /reminders,
gated on features.organize, and every reminder write goes through the bridge.

Deliberately absent, each accounted for rather than dropped:
/narrate (the deck module, docs/modules/deck.md); the two native ADO mutations
/create-ado-item and /resolve-bug, retired as duplicates of bridge calls
(docs/ARCHITECTURE.md, "The bridge"); the two engagement reads
/engagement/{slug}/activity and /engagement/{slug}/billing-timeline, retired
with no caller left in web/src; and POST /growth, a second writer of a growth
item beside NewGrowth, which the Growth page now runs through the bridge.

Nothing here reaches outside the package for code, and nothing derives the
prompt store from where this file happens to live -- see core/config.py.
"""

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import APIRouter, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .ado import accounting, bridge, design, docs, pr_comments, reporting, sprint, status
from .communication import api as communication_router
from .core import assets, config_routes, env, log, surfaces
from .core.config import API_PREFIX, REPO_ROOT, cors_origins
from .growth import growth_router
from .organize import api as organize_router
from .solitaire import api as solitaire_router
from .studio import api as studio_router

# In production, the built web UI is served from this package's own tree. The
# prompt store holds cards, not a front end, so this is never resolved
# through promptsRoot.
CLIENT_DIR = REPO_ROOT / "web" / "dist" / "client"

# The methods the routes use. OPTIONS is the preflight itself and is implied.
CORS_METHODS = ["GET", "POST", "PUT"]


def build_api() -> APIRouter:
    """Every route, under the one prefix."""
    api = APIRouter(prefix=API_PREFIX)
    api.include_router(env.api)
    api.include_router(config_routes.api)
    api.include_router(surfaces.api)
    api.include_router(log.api)
    api.include_router(status.api)
    # A card's pictures (docs/hub/cards.md, "A card's pictures"): core, no flag.
    api.include_router(assets.api)
    api.include_router(pr_comments.api)
    api.include_router(accounting.api)
    api.include_router(design.api)
    api.include_router(docs.api)
    api.include_router(reporting.api)
    api.include_router(sprint.api)
    api.include_router(bridge.api)
    api.include_router(growth_router())
    api.include_router(communication_router)
    api.include_router(organize_router)
    api.include_router(studio_router)
    api.include_router(solitaire_router)
    return api


def mount_client(app: FastAPI, client_dir: Path) -> None:
    """Serve a built web UI from ``client_dir``: its assets, and ``index.html``
    for every path the API router did not claim.

    Registered AFTER the router, so a real route always wins. The one thing
    the catch-all must not do is answer for a route that does not exist: a
    typo, a retired route, a client built against a newer agent used to get
    ``200 text/html`` here, and a fetch that parses a page as JSON fails a long
    way from the cause. An unmatched path under the API prefix is a JSON 404
    that names the path.
    """
    api_prefix = API_PREFIX.strip("/") + "/"

    app.mount("/assets", StaticFiles(directory=str(client_dir / "assets")), name="assets")

    @app.get("/{path:path}")
    async def spa_fallback(path: str):
        if path.startswith(api_prefix) or path == API_PREFIX.strip("/"):
            raise HTTPException(status_code=404, detail=f"No such API route: /{path}")
        return FileResponse(str(client_dir / "index.html"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """On start, drop picture uploads nobody attached (``p20-upload-*`` in the temp folder, a day old)."""
    assets.sweep_stale_uploads()
    yield


def create_app(client_dir: Path | None = CLIENT_DIR) -> FastAPI:
    """The app: CORS, the router, and the built client when there is one."""
    app = FastAPI(title="Toolkit Agent", version="0.1.0", lifespan=lifespan)

    # Dev-server origins come from config (web.corsOrigins) with the same defaults
    # as before. A fixed pair of port numbers in source is a portability bug: the
    # person running this decides which ports their dev servers use. The methods
    # are every one a route is registered with: PUT is /config and
    # /manager/{filename}, and a browser that calls the agent directly (the case
    # web.corsOrigins exists for) fails their preflight without it.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins(),
        allow_methods=CORS_METHODS,
        allow_headers=["*"],
    )

    app.include_router(build_api())

    if client_dir is not None and client_dir.exists():
        mount_client(app, client_dir)
    return app


app = create_app()
