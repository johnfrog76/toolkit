"""The request gate: one row for each input the rule tells apart."""

from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.app import create_app
    from agent.core import assets, request_gate
    from agent.core.config import API_PREFIX, DEFAULT_CORS_ORIGINS
    from agent.core.consts import consts
except ImportError as e:
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

H, S, F = request_gate.REFUSED_HOST, request_gate.REFUSED_SITE, request_gate.REFUSED_ORIGIN
D = request_gate.REFUSED_DEST
API = f"{API_PREFIX}/status"
OWN = "localhost:4100"

# method, path, Host, Origin, Sec-Fetch-Site, why
TABLE = [
    # The Host: every way this machine names itself, with and without a port.
    ("GET", API, "localhost:4100", None, None, None),
    ("GET", API, "LOCALHOST:4100", None, None, None),
    ("GET", API, "127.0.0.1:4100", None, None, None),
    ("GET", API, "[::1]:4100", None, None, None),
    ("GET", API, "localhost", None, None, None),  # a proxy that forwards the page's host, no port
    ("GET", API, "127.0.0.1", None, None, None),
    ("GET", API, "example.test:4100", None, None, H),
    ("GET", API, "localhost.example.test:4100", None, None, H),
    ("GET", API, "127.0.0.1.example.test", None, None, H),
    ("GET", API, "", None, None, H),
    ("GET", "/", "example.test:4100", None, None, H),
    ("POST", API, "example.test:4100", "http://example.test:4100", None, H),
    # Sec-Fetch-Site: another site, under the API prefix only.
    ("GET", API, OWN, None, "cross-site", S),
    ("GET", API, OWN, None, "CROSS-SITE", S),
    ("GET", API_PREFIX, OWN, None, "cross-site", S),
    ("GET", API, OWN, None, "same-origin", None),
    ("GET", API, OWN, None, "same-site", None),
    ("GET", API, OWN, None, "none", None),
    ("GET", "/", OWN, None, "cross-site", None),  # a link from elsewhere opens the page
    ("GET", "/apiary", OWN, None, "cross-site", None),
    ("POST", API, OWN, None, "cross-site", S),
    # Origin: on a change, from the product's pages and nothing else.
    ("POST", API, OWN, "http://localhost:5174", "same-site", None),
    ("PUT", API, OWN, "http://localhost:5173", None, None),
    ("POST", API, OWN, "http://localhost:5174/", None, None),
    ("POST", API, OWN, "HTTP://LOCALHOST:5174", None, None),
    ("POST", API, OWN, "http://localhost:4100", "same-origin", None),  # the agent serving its own client
    ("POST", API, "127.0.0.1:4100", "http://127.0.0.1:4100", "same-origin", None),
    ("POST", API, OWN, None, None, None),  # the CLI: not a browser
    # A page behind a proxy: Host is the proxy's, Origin the page's, on any port.
    ("POST", API, OWN, "http://localhost:6123", "same-origin", None),  # the dev server, on a port of its own
    ("POST", API, "localhost", "http://localhost:5174", "same-origin", None),  # nginx forwards the page's host
    ("POST", API, "127.0.0.1", "http://127.0.0.1:5174", "same-origin", None),
    ("POST", API, "example.test", "http://example.test", "same-origin", H),  # the same claim from a renamed page
    ("POST", API, OWN, "http://localhost:6123", "same-site", F),  # another app on this machine
    ("POST", API, OWN, "http://example.test", None, F),
    ("POST", API, OWN, "http://localhost:9999", None, F),
    ("POST", API, OWN, "http://localhost:4101", None, F),
    ("POST", API, OWN, "null", None, F),
    ("PUT", API, OWN, "https://example.test", None, F),
    ("DELETE", API, OWN, "http://example.test", None, F),
    ("PATCH", API, OWN, "http://example.test", None, F),
    # Reads are not asked for an Origin; CORS decides whether a page sees them.
    ("GET", API, OWN, "http://example.test", None, None),
    ("HEAD", API, OWN, "http://example.test", None, None),
    ("OPTIONS", API, OWN, "http://example.test", None, None),
]


# path, Sec-Fetch-Dest, why -- a same-origin GET, as a page drawing a picture sends it.
DESTS = [
    (API, "empty", None),
    (API, None, None),
    (API, "image", D),
    (API, "document", D),
    (API, "iframe", D),
    (API, "script", D),
    (API, "style", D),
    (f"{API_PREFIX}/design/search", "image", D),
    (f"{API_PREFIX}/assets/space/key/a.png", "image", None),
    (f"{API_PREFIX}/assets/space/key/a.png", "document", None),
    (f"{API_PREFIX}/assets/space/key/a.png", "script", D),
    (f"{API_PREFIX}/docs/asset/docs/a.png", "image", None),
    (f"{API_PREFIX}/docs/assets", "image", D),
    ("/", "document", None),
    ("/assets/index.js", "script", None),
]


class TheRule(unittest.TestCase):
    def test_every_destination(self):
        for path, dest, why in DESTS:
            with self.subTest(path=path, dest=dest):
                got = request_gate.refusal(
                    "GET", path, OWN, None, "same-origin", DEFAULT_CORS_ORIGINS, API_PREFIX, dest
                )
                self.assertEqual(got, why)

    def test_every_row(self):
        for method, path, host, origin, site, why in TABLE:
            with self.subTest(method=method, path=path, host=host, origin=origin, site=site):
                got = request_gate.refusal(method, path, host, origin, site, DEFAULT_CORS_ORIGINS, API_PREFIX)
                self.assertEqual(got, why)

    def test_a_configured_origin_brings_its_host_with_it(self):
        origins = ["http://dev.example.test:8080"]
        self.assertIsNone(request_gate.refusal("GET", API, "dev.example.test", None, None, origins, API_PREFIX))
        self.assertIsNone(request_gate.refusal("POST", API, "localhost:4100", origins[0], None, origins, API_PREFIX))

    def test_a_wildcard_origin_allows_nothing_extra(self):
        origins = ["*"]
        got = request_gate.refusal("POST", API, OWN, "http://example.test", None, origins, API_PREFIX)
        self.assertEqual(got, F)
        self.assertEqual(request_gate.refusal("GET", API, "example.test", None, None, origins, API_PREFIX), H)

    def test_the_shipped_names_are_the_loopback_only(self):
        source = Path(request_gate.__file__).read_text(encoding="utf-8")
        self.assertIn('LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}', source)


class TheRunningApp(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(client_dir=None))

    def test_a_refusal_is_a_403_before_any_route(self):
        reply = self.client.get(f"{API_PREFIX}/no-such-route", headers={"Host": "example.test:4100"})
        self.assertEqual((reply.status_code, reply.json()["detail"]), (403, H))

    def test_a_request_from_a_page_elsewhere_runs_no_verb(self):
        with mock.patch("agent.ado.bridge._run") as run:
            reply = self.client.post(f"{API_PREFIX}/cmd/Sync", headers={"Origin": "http://example.test"})
        self.assertEqual((reply.status_code, reply.json()["detail"]), (403, F))
        run.assert_not_called()

    def test_a_refused_body_is_never_read(self):
        """Straight at the gate: a test client reads a body up front, whoever refuses."""
        received, sent = [], []

        async def receive():
            received.append(1)
            return {"type": "http.request", "body": b"x", "more_body": False}

        async def send(message):
            sent.append(message)

        async def inner(*_args):
            self.fail("the request went past the gate")

        scope = {
            "type": "http",
            "method": "POST",
            "path": f"{API_PREFIX}/assets/upload",
            "headers": [(b"host", b"localhost:4100"), (b"origin", b"http://example.test")],
        }
        gate = request_gate.RequestGate(inner, origins=DEFAULT_CORS_ORIGINS, api_prefix=API_PREFIX)
        asyncio.run(gate(scope, receive, send))
        self.assertEqual(received, [])
        self.assertEqual(sent[0]["status"], 403)

    def test_every_answer_carries_the_headers_a_refusal_too(self):
        wanted = consts()["agent"]["responseHeaders"]
        for reply in (
            self.client.get(f"{API_PREFIX}/health"),
            self.client.get(f"{API_PREFIX}/health", headers={"Host": "example.test"}),
        ):
            for name, value in wanted.items():
                self.assertEqual(reply.headers[name], value)

    def test_only_a_skin_may_be_framed_and_only_by_this_origin(self):
        agent = consts()["agent"]
        client = TestClient(create_app(client_dir=None), raise_server_exceptions=False)
        skin = client.get("/lounge/temple.html")
        self.assertEqual(skin.headers["X-Frame-Options"], "SAMEORIGIN")
        self.assertEqual(skin.headers["Content-Security-Policy"], agent["framableHeaders"]["Content-Security-Policy"])
        self.assertIn("frame-ancestors 'self'", skin.headers["Content-Security-Policy"])
        for path in ("/lounge", "/", f"{API_PREFIX}/health"):
            reply = client.get(path)
            self.assertEqual(reply.headers["X-Frame-Options"], "DENY", path)
            self.assertIn("frame-ancestors 'none'", reply.headers["Content-Security-Policy"], path)

    def test_a_picture_of_the_api_runs_nothing(self):
        reply = self.client.get(
            f"{API_PREFIX}/design/search?q=word",
            headers={"Sec-Fetch-Site": "same-origin", "Sec-Fetch-Dest": "image"},
        )
        self.assertEqual((reply.status_code, reply.json()["detail"]), (403, D))

    def test_a_dev_server_page_passes(self):
        reply = self.client.get(f"{API_PREFIX}/health", headers={"Origin": DEFAULT_CORS_ORIGINS[0]})
        self.assertEqual(reply.status_code, 200)


class TheUploadLimit(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(client_dir=None))
        limit = mock.patch.object(assets, "cover_max_bytes", return_value=16)
        limit.start()
        self.addCleanup(limit.stop)
        url = f"{API_PREFIX}/assets/upload?name=a.png"
        self.url = url

    def test_a_declared_length_over_the_limit_is_refused(self):
        reply = self.client.post(self.url, content=b"x" * 17)
        self.assertEqual(reply.status_code, 413)
        self.assertIn("17 bytes", reply.json()["detail"])

    def test_a_body_with_no_length_stops_at_the_limit(self):
        def stream():
            yield b"x" * 10
            yield b"x" * 10

        reply = self.client.post(self.url, content=stream())
        self.assertEqual(reply.status_code, 413)
        self.assertIn("over the 16 bytes", reply.json()["detail"])

    def test_a_picture_at_the_limit_is_taken(self):
        reply = self.client.post(self.url, content=b"x" * 16)
        self.assertEqual(reply.status_code, 200)
        self.addCleanup(assets.remove_upload, reply.json()["path"])


if __name__ == "__main__":
    unittest.main()
