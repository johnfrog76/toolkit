"""A config file that will not parse is a readable warning, never a crash.

Run:  python -m pytest Tests/test_config_malformed.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.core import config, env
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

DEFAULTS = {
    "activeSpace": "alpha",
    "spaces": [
        {"slug": "alpha", "status": "local", "org": "", "promptsFolder": "alpha"},
        {"slug": "beta", "status": "local", "org": "", "promptsFolder": "beta"},
    ],
    "commandPrefix": "tk",
}
BAD = '{"activeSpace": "beta",}'  # the stray comma


class MalformedConfig(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.base, True)
        self.default = self.base / "config.default.json"
        self.local = self.base / "config.local.json"
        self.default.write_text(json.dumps(DEFAULTS), encoding="utf-8")
        for p in (
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.object(env, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ):
            p.start()
            self.addCleanup(p.stop)

    def _client(self):
        from agent.app import app

        return TestClient(app)

    def test_a_malformed_local_file_falls_back_to_the_defaults(self):
        self.local.write_text(BAD, encoding="utf-8")
        cfg = config.load_config()
        self.assertEqual(cfg["activeSpace"], "alpha")
        self.assertEqual(cfg["commandPrefix"], "tk")
        self.assertEqual(len(cfg["configProblems"]), 1)
        self.assertIn("config.local.json", cfg["configProblems"][0])

    def test_startup_reads_cors_origins_on_a_malformed_file(self):
        self.local.write_text(BAD, encoding="utf-8")
        self.assertEqual(config.cors_origins(), config.DEFAULT_CORS_ORIGINS)

    def test_a_top_level_that_is_not_an_object_is_the_same_case(self):
        self.local.write_text("[1, 2]", encoding="utf-8")
        cfg = config.load_config()
        self.assertEqual(cfg["activeSpace"], "alpha")
        self.assertIn("JSON object", cfg["configProblems"][0])

    def test_a_malformed_default_file_does_not_raise_either(self):
        self.default.write_text("{nope", encoding="utf-8")
        cfg = config.load_config()
        self.assertIn("config.default.json", cfg["configProblems"][0])

    def test_a_good_pair_reports_no_problem(self):
        self.local.write_text(json.dumps({"activeSpace": "beta"}), encoding="utf-8")
        cfg = config.load_config()
        self.assertEqual((cfg["activeSpace"], cfg["configProblems"]), ("beta", []))

    def test_a_file_broken_while_running_keeps_the_routes_answering_and_env_says_so(self):
        client = self._client()
        self.local.write_text(json.dumps({"activeSpace": "beta"}), encoding="utf-8")
        self.assertTrue(client.get("/api/env").json()["checks"]["configLoaded"]["ok"])
        self.local.write_text(BAD, encoding="utf-8")
        res = client.get("/api/env")
        self.assertEqual(res.status_code, 200)
        row = res.json()["checks"]["configLoaded"]
        self.assertFalse(row["ok"])
        self.assertIn("config.local.json", row["detail"])
        self.assertIn("not valid JSON", row["detail"])
        self.assertEqual(client.get("/api/health").status_code, 200)

    def test_switch_mode_reads_the_local_file_through_the_guard_and_leaves_it_alone(self):
        self.local.write_text(BAD, encoding="utf-8")
        res = self._client().post("/api/switch-mode", json={"mode": "beta"})
        self.assertEqual(res.status_code, 409)
        self.assertIn("config.local.json", res.json()["detail"])
        self.assertEqual(self.local.read_text(encoding="utf-8"), BAD)


if __name__ == "__main__":
    unittest.main()
