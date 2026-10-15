"""The growth module's half of the agent: training, presentations, goals,
reviews and the resume.

Three hub-root folders, all of them the ENGINEER's rather than any one org's:

    <promptsRoot>/growth/current/    training, presentation and goal artifacts
    <promptsRoot>/reviews/<slugs>/   generated work reviews, per slug-set
    <promptsRoot>/resume/resume.md   the career record

They sit beside the per-org folders, not inside one, for the reason the module
flag is engineer-scoped: a training you took does not stop having happened when
you switch org, and a resume is not an engagement's.

Every route here is <= Tier 2 -- files on disk, no ADO, no network -- and every
path is resolved from ``promptsRoot`` rather than from where this package
happens to sit.

``/api/engagement/{slug}/skills`` is the one growth-shaped read that is NOT
here: it counts tags across one org's ``archive/``, which is ADO card data, and
it already lives in ``ado/reporting.py``. Moving it would have bought a tidier
folder and a worse boundary. SkillsSnapshot is growth's component and calls it.
"""

from fastapi import APIRouter, Depends, HTTPException

from ..core.config import load_config

FEATURE = "growth"


def require_growth() -> None:
    """404 when the module is switched off.

    ABSENT, not forbidden. "Off means absent" is the rule the web shell already
    applies to a module's routes and nav, and a 403 would say something
    different: that the route exists and you may not have it. It does not exist.

    Checked per request rather than at mount time on purpose. Config is re-read
    on every request everywhere else in this agent -- a switch-org from another
    shell, a hand-edited config.local.json -- and gating at import would make
    this one flag the only thing in the system that needs a restart, while
    /env, which the web UI gates on, would already be reporting the new value.
    """
    if not bool((load_config().get("features") or {}).get(FEATURE, False)):
        raise HTTPException(
            status_code=404,
            detail="The growth module is not enabled. Set features.growth in config.local.json.",
        )


def growth_router() -> APIRouter:
    """The module's routes, behind one gate.

    The dependency is declared on the router rather than repeated on each
    route: a route added later is gated by existing, which is the opposite of
    the usual arrangement where it is gated by someone remembering.
    """
    from . import growth, resume, reviews

    api = APIRouter(dependencies=[Depends(require_growth)])
    api.include_router(growth.api)
    api.include_router(resume.api)
    api.include_router(reviews.api)
    return api
