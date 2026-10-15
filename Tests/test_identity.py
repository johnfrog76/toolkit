"""The agent resolves identity the way the CLI does, and never empties a card silently.

``Resolve-P20Identity`` in ``utilities.psm1`` has always fallen back to
``az account show`` when ``email`` is empty. The agent read ``cfg["email"]`` and
stopped, so on a machine whose (gitignored, per-machine) ``config.local.json``
has no ``email`` the browser showed no pull requests while ``tkMyPRs`` in the
same shell listed them -- and ``/prs`` returned before its own log line, so the
day's log had no ``agent/prs`` entry either.

Everything here runs with ``az`` STUBBED. Nothing in this file may start a real
``az``: the fallback is the thing under test, so a machine that happens to be
signed in must not be able to make a failing assertion pass.

Run directly:  python3 Tests/test_identity.py
Under pytest:  python3 -m pytest Tests/
"""

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
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.app import app
    from agent.core import env as env_route
    from agent.core import identity, tier
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

# An org the tier gate lets through on any machine -- /prs and /dashboard only
# reach the identity question at Tier 1.
PROBED_ORG = "https://dev.azure.com/YOUR-ADO-ORG"

AZ_USER = "someone@example.com"
CONFIG_USER = "configured@example.com"
BRANCH_USER_ADDRESS = "branch-user@example.com"


def _cfg(**over):
    base = {
        "org": PROBED_ORG,
        "status": "active",
        "activeSpace": "demo",
        "email": "",
        "branchUser": "",
        "features": {},
        "projects": [],
        "spaces": [{"slug": "demo", "name": "Demo", "status": "active"}],
    }
    base.update(over)
    return base


def _az_stub(stdout="", returncode=0):
    """Stand in for ``subprocess.run`` inside identity.py.

    Asserts the command it was handed is the one the CLI runs, so a rewritten
    query string cannot pass by returning the right string.
    """

    def run(cmd, **kwargs):
        run.calls.append(cmd)
        assert cmd[:2] == ["az", "account"], cmd
        assert "user.name" in cmd, cmd
        return mock.Mock(returncode=returncode, stdout=stdout, stderr="")

    run.calls = []
    return run


class _Tier1:
    """Patches that get a route past the tier gate on any machine, with no az."""

    def __init__(self, cfg):
        self._cfg = cfg

    def __enter__(self):
        self._patches = [
            mock.patch.object(accounting, "load_config", lambda: self._cfg),
            mock.patch.object(env_route, "load_config", lambda: self._cfg),
            mock.patch.object(identity, "load_config", lambda: self._cfg),
            mock.patch.object(tier, "hub_root", lambda: PKG_ROOT),
            mock.patch.object(tier, "shutil", mock.Mock(which=lambda _n: "/usr/bin/git")),
            mock.patch.object(tier, "_probe_ado", lambda _org: True),
        ]
        for p in self._patches:
            p.start()
        return self

    def __exit__(self, *exc):
        for p in self._patches:
            p.stop()
        return False


class ResolutionOrder(unittest.TestCase):
    """config email, else branchUser if it is an address, else az."""

    def setUp(self):
        identity.identity_cache_clear()

    def tearDown(self):
        identity.identity_cache_clear()

    def test_config_email_wins_and_az_is_never_asked(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg(email=CONFIG_USER)), mock.patch.object(identity.subprocess, "run", az):
            email, source = identity.resolve_identity()
        self.assertEqual(email, CONFIG_USER)
        self.assertEqual(source, identity.IDENTITY_SOURCE_CONFIG)
        self.assertEqual(az.calls, [], "config answered; az must not be started")

    def test_az_is_the_fallback_when_config_is_empty(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            email, source = identity.resolve_identity()
        self.assertEqual(email, AZ_USER)
        self.assertEqual(source, identity.IDENTITY_SOURCE_AZ)
        self.assertEqual(len(az.calls), 1)

    def test_branch_user_is_used_only_when_it_is_an_address(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg(branchUser=BRANCH_USER_ADDRESS)), mock.patch.object(identity.subprocess, "run", az):
            email, source = identity.resolve_identity()
        self.assertEqual(email, BRANCH_USER_ADDRESS)
        self.assertEqual(source, identity.IDENTITY_SOURCE_BRANCH_USER)

        identity.identity_cache_clear()
        az = _az_stub(stdout=AZ_USER + "\n")
        # The ordinary case: branchUser is a branch-name segment, not an
        # address, and ADO wants a unique name -- so it is skipped.
        with _Tier1(_cfg(branchUser="v-someone")), mock.patch.object(identity.subprocess, "run", az):
            email, source = identity.resolve_identity()
        self.assertEqual(email, AZ_USER)
        self.assertEqual(source, identity.IDENTITY_SOURCE_AZ)

    def test_nothing_resolves_to_nothing_with_no_source(self):
        az = _az_stub(stdout="", returncode=1)
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            email, source = identity.resolve_identity()
        self.assertEqual(email, "")
        self.assertEqual(source, "")

    def test_an_az_that_is_not_installed_is_not_an_exception(self):
        def boom(cmd, **kwargs):
            raise FileNotFoundError("az")

        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", boom):
            email, source = identity.resolve_identity()
        self.assertEqual((email, source), ("", ""))


class CachedForTheTTL(unittest.TestCase):
    """One az start per TTL window, not one per page load."""

    def setUp(self):
        identity.identity_cache_clear()

    def tearDown(self):
        identity.identity_cache_clear()

    def test_repeat_calls_within_the_ttl_start_az_once(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            for _ in range(5):
                self.assertEqual(identity.resolve_identity()[0], AZ_USER)
        self.assertEqual(len(az.calls), 1, "az was started once per call")

    def test_refresh_goes_past_the_cache(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            identity.resolve_identity()
            identity.resolve_identity(refresh=True)
        self.assertEqual(len(az.calls), 2)

    def test_the_answer_expires(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            identity.resolve_identity()
            # Age the cache past the TTL rather than sleeping through it.
            stamp, email, source = identity._cache
            identity._cache = (stamp - identity.ADO_PROBE_TTL_SECONDS - 1, email, source)
            identity.resolve_identity()
        self.assertEqual(len(az.calls), 2)

    def test_the_ttl_is_the_one_the_probe_uses(self):
        self.assertEqual(identity.ADO_PROBE_TTL_SECONDS, tier.ADO_PROBE_TTL_SECONDS)


class TheRoutesUseIt(unittest.TestCase):
    """/prs, /dashboard and /work-items answer the same question the same way."""

    def setUp(self):
        identity.identity_cache_clear()
        tier.probe_cache_clear()

    def tearDown(self):
        identity.identity_cache_clear()
        tier.probe_cache_clear()

    def test_prs_filters_by_the_az_fallback(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        seen = []

        def fake_pr_list(org, project, repo, role_flag, email):
            seen.append(email)
            return [], None

        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_pr_list", fake_pr_list),
        ):
            r = client.get("/api/prs")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["reason"], None)
        self.assertTrue(seen, "the route never reached the PR lookup")
        self.assertEqual(set(seen), {AZ_USER})

    def test_prs_with_no_identity_states_the_reason_and_logs_it(self):
        az = _az_stub(stdout="", returncode=1)
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            r = client.get("/api/prs")
        body = r.json()
        self.assertEqual(r.status_code, 200)
        self.assertEqual(body["count"], 0)
        self.assertEqual(body["prs"], [])
        self.assertEqual(body["reason"], identity.IDENTITY_MISSING_REASON)
        self.assertIn("email", body["reason"])
        self.assertIn("config.local.json", body["reason"])
        self.assertIn("az login", body["reason"])

    def test_prs_with_no_identity_writes_one_warn(self):
        az = _az_stub(stdout="", returncode=1)
        with (
            _Tier1(_cfg()),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(identity.log_writer, "write_log") as log,
        ):
            client.get("/api/prs")
        warns = [c.args for c in log.call_args_list if c.args and c.args[0] == "WARN"]
        self.assertEqual(len(warns), 1, f"expected one WARN, got {log.call_args_list}")
        self.assertEqual(warns[0][1], "agent/prs")
        self.assertEqual(warns[0][2], identity.IDENTITY_MISSING_REASON)

    def test_dashboard_counts_prs_with_the_resolved_identity(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        seen = []

        def fake_pr_list(org, project, repo, role_flag, email):
            seen.append(email)
            return [{"pullRequestId": 35}], None

        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_pr_list", fake_pr_list),
            mock.patch.object(accounting, "_az_wiql", lambda *a: ([], None)),
        ):
            r = client.get("/api/dashboard")
        body = r.json()
        self.assertEqual(body["pr_count"], 1, "the PR target was dropped for want of an email")
        self.assertEqual(body["reason"], None)
        self.assertEqual(set(seen), {AZ_USER})

    def test_dashboard_with_no_identity_states_the_reason(self):
        az = _az_stub(stdout="", returncode=1)
        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_pr_list", lambda *a: ([{"pullRequestId": 1}], None)),
            mock.patch.object(accounting, "_az_wiql", lambda *a: ([], None)),
        ):
            r = client.get("/api/dashboard")
        body = r.json()
        self.assertEqual(body["pr_count"], 0)
        self.assertEqual(body["reason"], identity.IDENTITY_MISSING_REASON)

    def test_work_items_uses_the_resolved_identity_in_the_wiql(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        seen = []

        def fake_wiql(org, project, wiql):
            seen.append(wiql)
            return [], None

        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_wiql", fake_wiql),
        ):
            r = client.get("/api/work-items")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["reason"], None)
        self.assertTrue(seen)
        self.assertIn(AZ_USER, seen[0])

    def test_work_items_still_falls_back_to_at_me_but_says_so(self):
        """@Me is a real answer -- the route degrades, it does not go blank."""
        az = _az_stub(stdout="", returncode=1)
        seen = []

        def fake_wiql(org, project, wiql):
            seen.append(wiql)
            return [], None

        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_wiql", fake_wiql),
        ):
            r = client.get("/api/work-items")
        body = r.json()
        self.assertIn("@Me", seen[0])
        self.assertEqual(body["count"], 0)
        self.assertEqual(body["reason"], identity.IDENTITY_MISSING_REASON)

    def test_work_items_that_found_rows_carries_no_reason(self):
        az = _az_stub(stdout="", returncode=1)
        row = {
            "id": 137,
            "fields": {
                "System.Title": "Something",
                "System.WorkItemType": "Bug",
                "System.State": "Active",
                "System.TeamProject": "Demo",
                "System.IterationPath": "Demo\\Sprint 1",
                "System.ChangedDate": "2026-09-17T00:00:00Z",
            },
        }
        cfg = _cfg(projects=[{"name": "Demo", "repo": "WebApp", "hasRepo": True}])
        with (
            _Tier1(cfg),
            mock.patch.object(identity.subprocess, "run", az),
            mock.patch.object(accounting, "_az_wiql", lambda *a: ([row], None)),
        ):
            body = client.get("/api/work-items").json()
        self.assertEqual(body["count"], 1)
        self.assertIsNone(body["reason"], "@Me answered -- a warning here reads as a failure")


class EnvReportsIt(unittest.TestCase):
    """/env says who "me" is and where that came from, as tkEnv does."""

    def setUp(self):
        identity.identity_cache_clear()
        tier.probe_cache_clear()

    def tearDown(self):
        identity.identity_cache_clear()
        tier.probe_cache_clear()

    def test_env_reports_the_address_and_its_source(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            body = client.get("/api/env").json()
        self.assertEqual(body["identity"]["email"], AZ_USER)
        self.assertEqual(body["identity"]["source"], identity.IDENTITY_SOURCE_AZ)
        self.assertTrue(body["checks"]["identity"]["ok"])
        self.assertIn(AZ_USER, body["checks"]["identity"]["detail"])
        self.assertIn("az", body["checks"]["identity"]["detail"])

    def test_env_names_config_as_the_source_when_config_answered(self):
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg(email=CONFIG_USER)), mock.patch.object(identity.subprocess, "run", az):
            body = client.get("/api/env").json()
        self.assertEqual(body["identity"]["source"], identity.IDENTITY_SOURCE_CONFIG)
        self.assertIn(CONFIG_USER, body["checks"]["identity"]["detail"])

    def test_env_marks_the_row_not_ok_and_names_the_remedy(self):
        az = _az_stub(stdout="", returncode=1)
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            body = client.get("/api/env").json()
        self.assertEqual(body["identity"], {"email": "", "source": ""})
        self.assertFalse(body["checks"]["identity"]["ok"])
        self.assertIn("config.local.json", body["checks"]["identity"]["detail"])
        self.assertIn("az login", body["checks"]["identity"]["detail"])

    def test_the_avatar_is_the_person_the_identity_row_names(self):
        """An address resolved from az names the avatar too. It used to read
        config alone, so the Environment card said who you are and the avatar
        beside it said "Toolkit"."""
        az = _az_stub(stdout=AZ_USER + "\n")
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            body = client.get("/api/env").json()
        self.assertEqual(body["displayName"], AZ_USER.split("@", 1)[0])

    def test_nobody_resolved_is_still_the_neutral_name(self):
        az = _az_stub(stdout="", returncode=1)
        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", az):
            body = client.get("/api/env").json()
        self.assertEqual(body["displayName"], "Toolkit")

    def test_env_does_not_hold_the_event_loop_for_the_az_probe(self):
        """The identity probe runs off the loop, like the tier probe."""

        def slow(cmd, **kwargs):
            time.sleep(0.4)
            return mock.Mock(returncode=0, stdout=AZ_USER, stderr="")

        import asyncio

        import httpx

        async def run():
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(transport=transport, base_url="http://agent") as ac:
                env_task = asyncio.create_task(ac.get("/api/env"))
                await asyncio.sleep(0.05)
                started = time.monotonic()
                health = await ac.get("/api/health")
                elapsed = time.monotonic() - started
                await env_task
                return health, elapsed

        with _Tier1(_cfg()), mock.patch.object(identity.subprocess, "run", slow):
            health, elapsed = asyncio.run(run())
        self.assertEqual(health.status_code, 200)
        self.assertLess(elapsed, 0.3, "/health queued behind the identity probe")


if __name__ == "__main__":
    unittest.main(verbosity=2)
