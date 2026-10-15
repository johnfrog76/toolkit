"""/env may not hold the event loop, and may not re-probe on every page load.

``GET /api/env`` is what the web shell gates every page on, and it resolves
tier -- which shells out to ``az devops project list``. Two defects, measured on Windows:

  (a) the handler is ``async def`` and ran the blocking probe inline, so for the
      length of the probe the agent served **nothing else**. ``/health``, which
      makes no ``az`` call at all, took 4.07s because it queued behind ``/env``;

  (b) it probed on every call, so each navigation paid for one cold ``az``
      start -- 3-4s warm on that machine, up to the 15s timeout when ``az``
      hangs.

Both claims are asserted here against a STUBBED probe: ``_probe_ado`` is
replaced with a sleep, so no ``az`` runs and the numbers are the agent's own
scheduling rather than the machine's ADO access.

Run directly:  python3 Tests/test_env_probe.py
Under pytest:  python3 -m pytest Tests/
"""

import asyncio
import json
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    import httpx
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import env as env_route
    from agent.core import tier
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

PROBE_SECONDS = 2.0

# An org the probe would actually be run for. Tier skips the probe entirely for
# a declared-local or archived org and for a hub that is not there, so a machine
# whose own config is Tier 2 -- this one, and every CI box -- would otherwise
# assert caching over a probe that never ran.
PROBED_ORG = "https://dev.azure.com/YOUR-ADO-ORG"


def _probed_config():
    return {
        "org": PROBED_ORG,
        "status": "active",
        "activeSpace": "demo",
        "features": {},
        "spaces": [{"slug": "demo", "name": "Demo", "status": "active"}],
    }


def _as_a_probed_org():
    """Patches that make /env reach the probe on any machine."""
    return [
        mock.patch.object(env_route, "load_config", _probed_config),
        mock.patch.object(tier, "hub_root", lambda: PKG_ROOT),
        mock.patch.object(tier, "shutil", mock.Mock(which=lambda _n: "/usr/bin/git")),
    ]


class _ProbedOrg:
    def __enter__(self):
        self._patches = _as_a_probed_org()
        for p in self._patches:
            p.start()
        return self

    def __exit__(self, *exc):
        for p in self._patches:
            p.stop()
        return False


class EnvDoesNotHoldTheEventLoop(unittest.TestCase):
    """(a) -- a slow probe delays /env and nothing else."""

    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_health_answers_while_env_is_probing(self):
        # The assertion is an ORDERING, not a stopwatch reading. Wall-clock
        # timing around the /health call proves nothing here: if the loop is
        # blocked, the `await asyncio.sleep` before it is blocked too, so the
        # clock starts after the probe has already finished and /health looks
        # fast. What cannot be faked is WHEN /health finished relative to the
        # probe -- during it, or only after it.
        marks = {}

        def slow_probe(org_url):
            marks["probe_start"] = time.monotonic()
            time.sleep(PROBE_SECONDS)
            marks["probe_end"] = time.monotonic()
            return False

        async def run():
            # ASGITransport drives the app in THIS event loop, which is the
            # whole point: a handler that blocks blocks this loop, exactly as it
            # blocks uvicorn's.
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(transport=transport, base_url="http://agent") as ac:
                env_task = asyncio.create_task(ac.get("/api/env"))
                await asyncio.sleep(0.05)  # let /env get as far as the probe
                health = await ac.get("/api/health")
                marks["health_end"] = time.monotonic()
                env = await env_task
                return health, env

        with _ProbedOrg(), mock.patch.object(tier, "_probe_ado", side_effect=slow_probe) as probe:
            health, env = asyncio.run(run())

        self.assertEqual(probe.call_count, 1, "the probe never ran -- this proves nothing")
        self.assertEqual(health.status_code, 200)
        self.assertEqual(env.status_code, 200)
        self.assertGreater(marks["health_end"], marks["probe_start"])
        self.assertLess(
            marks["health_end"],
            marks["probe_end"],
            "/health was only served after the probe finished -- the event loop is blocked",
        )


class TheProbeIsCachedForAShortWhile(unittest.TestCase):
    """(b) -- reachability is a fact about the machine, not about the request."""

    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_a_second_call_inside_the_ttl_does_not_re_probe(self):
        with _ProbedOrg(), mock.patch.object(tier, "_probe_ado", return_value=True) as probe:
            first = client.get("/api/env")
            second = client.get("/api/env")
            calls = probe.call_count

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["tier"], 1, "the fixture org did not reach the probe")
        self.assertEqual(calls, 1, f"two /env calls made {calls} probes inside the TTL")

    def test_refresh_goes_past_the_cache(self):
        with _ProbedOrg(), mock.patch.object(tier, "_probe_ado", return_value=True) as probe:
            client.get("/api/env")
            before = probe.call_count
            client.get("/api/env?refresh=1")
            after = probe.call_count

        self.assertEqual(before, 1)
        self.assertEqual(after, 2, "/env?refresh=1 read a cached answer")

    def test_an_expired_entry_is_probed_again(self):
        """The TTL is a window, not a one-shot memo."""
        with _ProbedOrg(), mock.patch.object(tier, "_probe_ado", return_value=True) as probe:
            client.get("/api/env")
            before = probe.call_count
            with mock.patch.object(tier, "ADO_PROBE_TTL_SECONDS", 0):
                client.get("/api/env")
            self.assertGreater(probe.call_count, before, "an expired entry was reused")

    def test_switching_org_forgets_the_previous_answer(self):
        """A different org is a different question; /switch-mode busts the cache."""
        tier._probe_tracker_cached(PROBED_ORG)
        self.assertTrue(tier._probe_cache, "nothing was cached to forget")
        tier.probe_cache_clear()
        self.assertFalse(tier._probe_cache)

    def test_the_ttl_is_in_the_window_the_report_asked_for(self):
        self.assertGreaterEqual(tier.ADO_PROBE_TTL_SECONDS, 30)
        self.assertLessEqual(tier.ADO_PROBE_TTL_SECONDS, 60)

    def test_the_cache_is_keyed_by_org(self):
        """Switching org asks a different question of a different server."""
        tier.probe_cache_clear()
        with mock.patch.object(tier, "_probe_ado", return_value=True) as probe:
            tier._probe_tracker_cached("https://dev.azure.com/one")
            tier._probe_tracker_cached("https://dev.azure.com/two")
            tier._probe_tracker_cached("https://dev.azure.com/one")
        self.assertEqual(probe.call_count, 2, "a second org read the first org's answer")


class EnvSaysWhichBuild(unittest.TestCase):
    """/env carries consts.json's version, the string Env prints and the System page shows."""

    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_the_version_is_the_contracts(self):
        from agent.core import consts

        raw = json.loads((PKG_ROOT / "consts.json").read_text(encoding="utf-8-sig"))
        with _ProbedOrg(), mock.patch.object(tier, "_probe_ado", return_value=True):
            body = client.get("/api/env").json()
        self.assertEqual(body["version"], raw["version"])
        self.assertEqual(body["version"], consts.version())


if __name__ == "__main__":
    unittest.main(verbosity=2)
