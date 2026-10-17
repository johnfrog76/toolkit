"""What the app serves around the routes: the SPA fallback, and CORS.

The production agent serves the built web UI itself, from ``web/dist/client``,
through a catch-all registered after the API router. That block only exists
when the directory does -- a dev checkout never builds it -- which is why no
test had ever covered it and why the catch-all answered ``200 text/html`` for
``/api/nope`` for as long as it existed.
Each test
here builds a scratch ``dist/client`` and mounts it on an app of its own, so
the behaviour exists under test whether or not anyone has run ``npm run build``.
"""

import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent import app as app_module
    from agent.core.config import API_PREFIX
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")


INDEX_HTML = '<!doctype html><html><body><div id="root">scratch client</div></body></html>\n'


class SpaFallbackTests(unittest.TestCase):
    """A scratch client directory, mounted the way production mounts the real one."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.client_dir = Path(self._tmp.name) / "dist" / "client"
        (self.client_dir / "assets").mkdir(parents=True)
        (self.client_dir / "index.html").write_text(INDEX_HTML, encoding="utf-8")
        (self.client_dir / "assets" / "app.js").write_text("console.log('scratch');\n", encoding="utf-8")
        self.client = TestClient(app_module.create_app(self.client_dir))

    def tearDown(self):
        self._tmp.cleanup()

    def test_root_serves_index_html(self):
        r = self.client.get("/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.headers["content-type"].startswith("text/html"))
        self.assertIn("scratch client", r.text)

    def test_deep_link_serves_index_html(self):
        r = self.client.get("/daily/some/deep/link")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.headers["content-type"].startswith("text/html"))
        self.assertIn("scratch client", r.text)

    def test_assets_are_served_from_the_client_dir(self):
        r = self.client.get("/assets/app.js")
        self.assertEqual(r.status_code, 200)
        self.assertIn("scratch", r.text)

    def test_registered_route_still_wins_over_the_fallback(self):
        r = self.client.get(f"{API_PREFIX}/health")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.headers["content-type"].startswith("application/json"))

    def test_unmatched_api_path_is_a_json_404_not_the_page(self):
        r = self.client.get(f"{API_PREFIX}/definitely-not-a-route")
        self.assertEqual(r.status_code, 404)
        self.assertTrue(r.headers["content-type"].startswith("application/json"), r.headers["content-type"])
        self.assertIn("definitely-not-a-route", r.json()["detail"])
        self.assertNotIn("scratch client", r.text)

    def test_the_bare_prefix_is_a_404_too(self):
        r = self.client.get(API_PREFIX)
        self.assertEqual(r.status_code, 404)
        self.assertTrue(r.headers["content-type"].startswith("application/json"))

    def test_the_prefix_is_read_from_the_agents_constants(self):
        """The catch-all's refusal is built from API_PREFIX, not a retyped string."""
        source = (REPO_ROOT / "agent" / "app.py").read_text(encoding="utf-8")
        self.assertNotIn('"api/"', source)
        self.assertNotIn("'api/'", source)
        self.assertIn("API_PREFIX", source)


class CorsTests(unittest.TestCase):
    """A browser that calls the agent directly -- the case ``web.corsOrigins``
    exists for -- preflights every write. ``allow_methods`` said GET and POST
    while ``PUT /api/config`` and ``PUT /api/manager/{filename}`` existed, so the
    Configuration card's Save and every 1:1 edit failed preflight from such a
    browser."""

    ORIGIN = "http://localhost:5174"

    def setUp(self):
        self.client = TestClient(app_module.create_app(None))

    def _preflight(self, path: str, method: str):
        return self.client.options(
            path,
            headers={
                "Origin": self.ORIGIN,
                "Access-Control-Request-Method": method,
                "Access-Control-Request-Headers": "content-type",
            },
        )

    def test_put_config_passes_preflight(self):
        r = self._preflight(f"{API_PREFIX}/config", "PUT")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.headers.get("access-control-allow-origin"), self.ORIGIN)
        self.assertIn("PUT", r.headers.get("access-control-allow-methods", ""))

    def test_every_registered_method_is_allowed(self):
        """The allowed list is derived from what is registered, not remembered."""
        # fastapi >=0.142 includes routers lazily, so app.routes no longer lists their
        # methods; the OpenAPI paths do.
        paths = app_module.create_app(None).openapi()["paths"]
        registered = {m.upper() for operations in paths.values() for m in operations} - {"HEAD", "OPTIONS"}
        self.assertTrue(registered, "no methods found in the OpenAPI paths; the check would pass on nothing")
        self.assertEqual(registered - set(app_module.CORS_METHODS), set(), registered)

    def test_a_method_nothing_registers_still_fails_preflight(self):
        r = self._preflight(f"{API_PREFIX}/config", "DELETE")
        self.assertEqual(r.status_code, 400)


class DeliberatelyAbsentRoutes(unittest.TestCase):
    """The routes app.py's docstring and agent/README.md's "Deliberately absent"
    table name: each is 404 and out of the OpenAPI schema. The two engagement
    reads joined the list with no caller left in web/src.

    ``POST /growth`` is absent beside a ``GET /growth`` that is not, so its
    path is answered with a 405 rather than a 404: the METHOD is what is gone.
    """

    ABSENT = [
        ("post", "/narrate"),
        ("post", "/pr-comments/test/save"),
        ("post", "/create-ado-item"),
        ("post", "/resolve-bug"),
        ("get", "/engagement/test/activity"),
        ("get", "/engagement/test/billing-timeline"),
        ("post", "/growth"),
    ]

    # A path that keeps another method answers 405 for the one that went.
    SIBLING_KEPT = {"/growth"}

    def setUp(self):
        self.app = app_module.create_app(None)
        self.client = TestClient(self.app)

    def test_each_is_404(self):
        for method, path in self.ABSENT:
            with self.subTest(path=path):
                r = self.client.request(method.upper(), f"{API_PREFIX}{path}", json={})
                expected = 405 if path in self.SIBLING_KEPT else 404
                self.assertEqual(r.status_code, expected, r.text)

    def test_none_is_in_the_schema(self):
        paths = self.app.openapi()["paths"]
        for method, path in self.ABSENT:
            with self.subTest(path=path):
                template = path.replace("/test/", "/{slug}/")
                self.assertNotIn(method, paths.get(f"{API_PREFIX}{template}", {}))
        # And the siblings that stayed are still there, so the check is not vacuous.
        self.assertIn(f"{API_PREFIX}/engagement/{{slug}}/summary", paths)
        self.assertIn("get", paths[f"{API_PREFIX}/growth"])


class NoClientDirTests(unittest.TestCase):
    """A dev checkout: no built client, so no fallback and no assets mount."""

    def test_an_absent_client_dir_mounts_nothing(self):
        missing = Path(tempfile.gettempdir()) / "p20-no-such-client-dir"
        client = TestClient(app_module.create_app(missing))
        self.assertEqual(client.get("/").status_code, 404)
        self.assertEqual(client.get(f"{API_PREFIX}/health").status_code, 200)


if __name__ == "__main__":
    unittest.main()
