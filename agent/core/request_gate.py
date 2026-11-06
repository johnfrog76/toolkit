"""Which requests the agent will look at: the first thing every request meets.

The agent binds to the loopback and has no accounts, so a request from another
machine never arrives. A browser on this machine is different: it will send
requests to the agent on behalf of whatever page is open. Three checks keep
those to the product's own pages, ahead of routing and before a body is read:

- **Host.** The name the request was addressed to is a loopback name, or the
  host of an origin in ``web.corsOrigins``. Every path.
- **Sec-Fetch-Site.** A browser that sends it and says ``cross-site`` is refused
  for anything under the API prefix. A navigation to the page itself is not.
- **Origin.** A state-changing method carrying an ``Origin`` must carry one in
  ``web.corsOrigins``, or the agent's own: the one the request's ``Host`` names.
  ``Sec-Fetch-Site: same-origin`` also passes, which is how a page behind a
  proxy (the dev server, the Docker image) is recognised on any port: its
  ``Origin`` is its own, and the browser says the request stayed there. The Host
  check has already run, so a page cannot earn that by renaming itself. A missing
  ``Origin`` passes: browsers send one on such a request, and the CLI's own
  calls (``SendTeams``, ``Agent -Status``) are not browsers.

A refusal is a plain 403 naming the setting. It is not a module gate, so "off
means absent" does not apply here. The allowed origins are bound at startup, as
CORS's are. docs/ARCHITECTURE.md, "Trust model", is the long version.
"""

from __future__ import annotations

from urllib.parse import urlsplit

from starlette.responses import JSONResponse

# Not a frozenset: Tests/conftest.py adds the test client's own name.
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}
READ_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
CROSS_SITE = "cross-site"
SAME_ORIGIN = "same-origin"

REFUSED_HOST = "This agent answers only to its loopback names and the hosts in web.corsOrigins."
REFUSED_SITE = "This agent does not take requests from another site."
REFUSED_ORIGIN = "This agent takes changes only from its own pages and the origins in web.corsOrigins."


def host_name(host: str) -> str:
    """The lowercase name in a ``Host`` value, without its port or brackets."""
    return (urlsplit(f"//{host.strip()}").hostname or "").lower()


def origin_key(origin: str) -> str:
    """An origin as compared: lowercase, no trailing slash."""
    return origin.strip().rstrip("/").lower()


def allowed_hosts(origins: list[str]) -> set[str]:
    """The loopback names, plus the host of each configured origin."""
    named = {(urlsplit(origin_key(o)).hostname or "") for o in origins}
    return LOOPBACK_HOSTS | (named - {""})


def refusal(
    method: str,
    path: str,
    host: str,
    origin: str | None,
    site: str | None,
    origins: list[str],
    api_prefix: str,
) -> str | None:
    """Why this request is refused, or None. The whole rule, as one table can
    hold it: Tests/test_request_gate.py has a row for each input it tells apart."""
    if host_name(host) not in allowed_hosts(origins):
        return REFUSED_HOST
    under_api = path == api_prefix or path.startswith(f"{api_prefix}/")
    if under_api and (site or "").lower() == CROSS_SITE:
        return REFUSED_SITE
    if method.upper() in READ_METHODS or origin is None or (site or "").lower() == SAME_ORIGIN:
        return None
    key = origin_key(origin)
    own = urlsplit(key).netloc == host.strip().lower()
    if not own and key not in {origin_key(o) for o in origins}:
        return REFUSED_ORIGIN
    return None


class RequestGate:
    """Pure ASGI, so a refused request's body is never read."""

    def __init__(self, app, origins: list[str], api_prefix: str):
        self.app = app
        self.origins = origins
        self.api_prefix = api_prefix

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope["headers"]}
        why = refusal(
            scope["method"],
            scope["path"],
            headers.get("host", ""),
            headers.get("origin"),
            headers.get("sec-fetch-site"),
            self.origins,
            self.api_prefix,
        )
        if why is None:
            await self.app(scope, receive, send)
            return
        await JSONResponse({"detail": why}, status_code=403)(scope, receive, send)
