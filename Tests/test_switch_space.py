"""POST /api/switch-mode, end to end: the active Space changes, /env says so at
once, and the machine's file comes out in the one spelling -- activeSpace, the
old activeOrg dropped ("I am having some
problems switching back and forth between Spaces" was the day's rename skew,
and the one defect it found was the old key surviving beside the new)."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import config
    from agent.core import env as envmod
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")


class SwitchSpace(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        tmp = Path(self._tmp.name)
        self.hub = tmp / "hub"
        for slug in ("a", "b"):
            (self.hub / slug / "current").mkdir(parents=True)
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "hub": 1,
                    "spaces": [
                        {"slug": "a", "name": "A", "status": "local", "promptsFolder": "a"},
                        {"slug": "b", "name": "B", "status": "local", "promptsFolder": "b"},
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.default = tmp / "config.default.json"
        self.default.write_text(
            json.dumps({"activeSpace": "a", "spaces": [], "promptsRoot": str(self.hub), "features": {}}),
            encoding="utf-8",
        )
        self.local = tmp / "config.local.json"
        # An OLD-spelled machine file: the switch must migrate it, not stack keys.
        self.local.write_text(json.dumps({"activeOrg": "a"}), encoding="utf-8")
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.object(envmod, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(self.hub)}, clear=False),
        ]
        for p in self._patches:
            p.start()
        self.client = TestClient(app)

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def _active(self) -> str:
        return self.client.get("/api/env").json()["config"]["activeSpace"]

    def test_switching_back_and_forth_is_read_at_once_and_writes_one_spelling(self):
        self.assertEqual(self._active(), "a")
        self.assertEqual([s["slug"] for s in self.client.get("/api/env").json()["config"]["spaces"]], ["a", "b"])
        self.assertEqual(self.client.post("/api/switch-mode", json={"mode": "b"}).status_code, 200)
        self.assertEqual(self._active(), "b")
        written = json.loads(self.local.read_text(encoding="utf-8"))
        self.assertEqual(written.get("activeSpace"), "b")
        self.assertNotIn("activeOrg", written, "the old key must not survive beside the new")
        self.assertEqual(self.client.post("/api/switch-mode", json={"mode": "a"}).status_code, 200)
        self.assertEqual(self._active(), "a")
        self.assertEqual(json.loads(self.local.read_text(encoding="utf-8")), {"activeSpace": "a"})

    def test_an_unknown_space_is_refused_and_writes_nothing(self):
        before = self.local.read_text(encoding="utf-8")
        r = self.client.post("/api/switch-mode", json={"mode": "nowhere"})
        self.assertEqual(r.status_code, 400)
        self.assertIn("Unknown Space", r.json()["detail"])
        self.assertEqual(self.local.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
