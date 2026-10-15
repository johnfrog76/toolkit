"""The config routes read and write through the CLI, and nothing else.

``GET /api/config/schema``, ``GET /api/config`` and ``PUT /api/config`` exist so
the browser can change a setting; the claim this suite holds is that none of
them knows anything about configuration beyond how to run one verb:

  (a) the argv is the bridge's contract -- one ``-Set`` token carrying a JSON
      object and one ``-Unset`` token carrying a JSON array, because the bridge
      splats a flat list and a repeated ``-Set`` cannot survive that;
  (b) every reply is typed the way ``POST /cmd/{name}`` is, refusals included,
      so a rejected write is a body the card can render rather than a 500;
  (c) a successful write clears the identity and tier caches, which is the only
      reason ``/env`` reflects a new ``email`` within a second instead of within
      the 45-second TTL;
  (d) the schema is cached per process, so the card's tooltips cost one
      PowerShell start rather than one per page load.

Most cases stub the bridge -- what is under test is this module's argv and its
cache behaviour, not PowerShell. Two run for real where pwsh is on the machine:
the schema read and a live ``-Set`` into a scratch package, because a suite that
only mocks the subprocess would pass with the verb broken.

Run directly:  python3 Tests/test_config_routes.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado.bridge import CommandResponse
    from agent.app import app
    from agent.core import config_routes
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

HAVE_PWSH = shutil.which("pwsh") is not None


def _ok(output: str) -> CommandResponse:
    return CommandResponse(command="Config", status="success", exit_code=0, output=output, error=None, duration=1)


def _refused(reason: str) -> CommandResponse:
    return CommandResponse(command="Config", status="error", exit_code=2, output=None, error=reason, duration=1)


class ArgvIsTheBridgeContract(unittest.TestCase):
    """One token per structure, and the values keep their JSON types."""

    def setUp(self):
        config_routes.schema_cache_clear()

    def test_a_set_map_is_one_json_object(self):
        params = config_routes.build_params({"email": "a@b.c", "features.growth": True}, [])
        self.assertEqual(params[0], "-Set")
        self.assertEqual(len(params), 2, params)
        parsed = json.loads(params[1])
        self.assertEqual(parsed["email"], "a@b.c")
        self.assertIs(parsed["features.growth"], True)

    def test_a_list_value_stays_a_list(self):
        params = config_routes.build_params({"web.corsOrigins": ["http://localhost:5174"]}, [])
        self.assertEqual(json.loads(params[1])["web.corsOrigins"], ["http://localhost:5174"])

    def test_unset_is_one_json_array(self):
        params = config_routes.build_params({}, ["email", "wsRoot"])
        self.assertEqual(params[0], "-Unset")
        self.assertEqual(json.loads(params[1]), ["email", "wsRoot"])

    def test_both_together(self):
        params = config_routes.build_params({"email": "a@b.c"}, ["wsRoot"])
        self.assertEqual(params[0], "-Set")
        self.assertEqual(params[2], "-Unset")

    def test_nothing_produces_nothing(self):
        self.assertEqual(config_routes.build_params({}, []), [])


class TheRoutesRunTheVerb(unittest.TestCase):
    """With the bridge stubbed: what is sent, and what comes back."""

    def setUp(self):
        config_routes.schema_cache_clear()

    def test_put_sends_the_argv_and_returns_both_halves(self):
        calls = []

        async def fake(name, req):
            calls.append((name, list(req.params)))
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "test", "files": {}, "settings": []}))
            return _ok("  [+] email  (unset) -> a@b.c")

        with mock.patch.object(config_routes, "run_command", fake):
            r = client.put("/api/config", json={"set": {"email": "a@b.c"}})

        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["result"]["status"], "success")
        self.assertEqual(body["config"]["activeSpace"], "test")
        # The write, then the re-read. Both through the one verb.
        self.assertEqual(calls[0][0], "Config")
        self.assertEqual(calls[0][1][0], "-Set")
        self.assertIn("-List", calls[1][1])

    def test_the_two_switches_are_forwarded(self):
        seen = []

        async def fake(name, req):
            seen.append(list(req.params))
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))
            return _ok("ok")

        with mock.patch.object(config_routes, "run_command", fake):
            client.put("/api/config", json={"set": {"spaces.acme.status": "archive"}, "local": True})
            client.put("/api/config", json={"set": {"storeSync": "git"}, "hub": True})

        self.assertIn("-Local", seen[0])
        self.assertIn("-Hub", seen[2])

    def test_a_refusal_comes_back_as_a_body_not_an_exception(self):
        async def fake(name, req):
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))
            return _refused("'commands' is defined in config.default.json, which this command never writes.")

        with mock.patch.object(config_routes, "run_command", fake):
            r = client.put("/api/config", json={"set": {"commands": "nope"}})

        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["result"]["status"], "error")
        self.assertIn("config.default.json", body["result"]["error"])

    def test_an_empty_body_is_rejected_without_running_anything(self):
        async def fake(name, req):
            # Only the re-read may run.
            self.assertIn("-List", req.params)
            return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))

        with mock.patch.object(config_routes, "run_command", fake):
            r = client.put("/api/config", json={"set": {}, "unset": []})

        self.assertEqual(r.json()["result"]["status"], "rejected")

    def test_a_successful_write_clears_the_two_ttl_caches(self):
        cleared = {"identity": 0, "probe": 0}

        async def fake(name, req):
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))
            return _ok("ok")

        with (
            mock.patch.object(config_routes, "run_command", fake),
            mock.patch.object(
                config_routes, "identity_cache_clear", lambda: cleared.__setitem__("identity", cleared["identity"] + 1)
            ),
            mock.patch.object(
                config_routes, "probe_cache_clear", lambda: cleared.__setitem__("probe", cleared["probe"] + 1)
            ),
        ):
            client.put("/api/config", json={"set": {"email": "a@b.c"}})

        self.assertEqual(cleared["identity"], 1)
        self.assertEqual(cleared["probe"], 1)

    def test_a_successful_write_re_reads_the_bridge_allowlist(self):
        """The write itself went through the bridge and primed its cache with
        the pre-flip table, so the route forces a re-read.
        """
        forced = []

        async def fake(name, req):
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))
            return _ok("ok")

        with (
            mock.patch.object(config_routes, "run_command", fake),
            mock.patch.object(config_routes, "identity_cache_clear", lambda: None),
            mock.patch.object(config_routes, "probe_cache_clear", lambda: None),
            mock.patch.object(config_routes, "command_map", lambda force=False: forced.append(force) or {}),
        ):
            client.put("/api/config", json={"set": {"features.growth": True}})

        self.assertEqual(forced, [True])

    def test_a_failed_write_clears_nothing(self):
        cleared = {"n": 0}

        async def fake(name, req):
            if "-List" in req.params:
                return _ok(json.dumps({"activeSpace": "", "files": {}, "settings": []}))
            return _refused("no")

        with (
            mock.patch.object(config_routes, "run_command", fake),
            mock.patch.object(
                config_routes, "identity_cache_clear", lambda: cleared.__setitem__("n", cleared["n"] + 1)
            ),
            mock.patch.object(
                config_routes, "command_map", lambda force=False: cleared.__setitem__("n", cleared["n"] + 1)
            ),
        ):
            client.put("/api/config", json={"set": {"email": "a@b.c"}})

        self.assertEqual(cleared["n"], 0)

    def test_a_list_that_cannot_be_read_is_reported_not_guessed(self):
        async def fake(name, req):
            return _refused("no PowerShell on this machine")

        with mock.patch.object(config_routes, "run_command", fake):
            body = client.get("/api/config").json()

        self.assertEqual(body["settings"], [])
        self.assertIn("PowerShell", body["error"])

    def test_warnings_in_front_of_the_json_are_tolerated(self):
        # Under -File, PowerShell folds the warning stream into stdout. The
        # command-map read takes the last JSON line for the same reason.
        noisy = "WARNING: no config.local.json found\n" + json.dumps(
            {"activeSpace": "test", "files": {}, "settings": [{"key": "email"}]}
        )

        async def fake(name, req):
            return _ok(noisy)

        with mock.patch.object(config_routes, "run_command", fake):
            body = client.get("/api/config").json()

        self.assertEqual(body["activeSpace"], "test")


class TheSchemaIsCachedPerProcess(unittest.TestCase):
    def setUp(self):
        config_routes.schema_cache_clear()

    def test_the_second_read_costs_nothing(self):
        runs = {"n": 0}

        async def fake(name, req):
            runs["n"] += 1
            return _ok(
                json.dumps(
                    [
                        {
                            "key": "email",
                            "scope": "machine",
                            "type": "string",
                            "allowed": [],
                            "required": False,
                            "file": "config.local.json",
                            "help": "who me is",
                        }
                    ]
                )
            )

        with mock.patch.object(config_routes, "run_command", fake):
            first = client.get("/api/config/schema").json()
            second = client.get("/api/config/schema").json()

        self.assertEqual(runs["n"], 1)
        self.assertEqual(first["schema"], second["schema"])
        self.assertEqual(first["schema"][0]["key"], "email")

    def test_refresh_re_reads(self):
        runs = {"n": 0}

        async def fake(name, req):
            runs["n"] += 1
            return _ok(json.dumps([]))

        with mock.patch.object(config_routes, "run_command", fake):
            client.get("/api/config/schema")
            client.get("/api/config/schema?refresh=1")

        self.assertEqual(runs["n"], 2)

    def test_a_schema_that_cannot_be_read_is_empty_with_a_reason(self):
        async def fake(name, req):
            return _refused("the CLI is not there")

        with mock.patch.object(config_routes, "run_command", fake):
            body = client.get("/api/config/schema").json()

        self.assertEqual(body["schema"], [])
        self.assertIn("not there", body["error"])


@unittest.skipUnless(HAVE_PWSH, "needs pwsh")
class AgainstTheRealVerb(unittest.TestCase):
    """The cheap end-to-end half: the real CLI, in a scratch package.

    The package is a copy, and `Config` is run against it directly rather than
    through `POST /cmd` -- the bridge always imports the manifest beside
    ITSELF, which is this checkout, and a test that wrote into this checkout's
    config.local.json would be editing the engineer's machine.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        tmp = Path(self._tmp.name)
        self.pkg = tmp / "pkg"
        self.pkg.mkdir()
        for name in ("config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / name, self.pkg / name)
        shutil.copytree(PKG_ROOT / "Scripts", self.pkg / "Scripts")
        self.verb = self.pkg / "Scripts" / "Set-ToolkitConfig.ps1"

    def tearDown(self):
        self._tmp.cleanup()

    def _run(self, *args):
        import subprocess

        return subprocess.run(
            ["pwsh", "-NoProfile", "-File", str(self.verb), *args],
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ, "NO_COLOR": "1", "TOOLKIT_QUIET_STARTUP": "1"},
            check=False,
        )

    def test_the_schema_the_agent_would_serve_parses(self):
        result = self._run("-Schema", "-AsJson")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)
        self.assertTrue(rows)
        keys = {r["key"] for r in rows}
        self.assertIn("email", keys)
        self.assertIn("features.growth", keys)
        for row in rows:
            self.assertIn(row["scope"], {"machine", "org", "hub", "default"}, row)
            self.assertTrue(row["help"], row)

    def test_the_argv_this_module_builds_is_what_the_verb_takes(self):
        params = config_routes.build_params({"email": "someone@example.com", "features.growth": True}, [])
        result = self._run(*params)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        written = json.loads((self.pkg / "config.local.json").read_text(encoding="utf-8"))
        self.assertEqual(written["email"], "someone@example.com")
        self.assertIs(written["features"]["growth"], True)

        # And the unset half of the same contract.
        result = self._run(*config_routes.build_params({}, ["email"]))
        self.assertEqual(result.returncode, 0, result.stderr)
        written = json.loads((self.pkg / "config.local.json").read_text(encoding="utf-8"))
        self.assertNotIn("email", written)

    def test_a_refusal_exits_two_with_the_sentence(self):
        result = self._run(*config_routes.build_params({"commands": "nope"}, []))
        self.assertEqual(result.returncode, 2)
        self.assertIn("config.default.json", result.stdout + result.stderr)
        self.assertFalse((self.pkg / "config.local.json").exists())


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
