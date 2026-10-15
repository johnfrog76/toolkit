"""Feature flags have a scope, and the default scope is the engineer.

The owner's rule: nothing other than the ADO flow -- the core experience -- is
org-dependent. Every flag is the person's and holds steady across activeOrg
(switching between an active globex, an archived initech and an active demo
must not make Growth appear and disappear), except the ADO core's own
org-scoped keys, sprintAwareness today, which describe one org's board.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from agent.core import config  # noqa: E402


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


class FeatureScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.default_path = base / "config.default.json"
        self.local_path = base / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "globex",
                "features": {"growth": True},
                "spaces": [
                    {"slug": "globex", "status": "active", "features": {"sprintAwareness": True}},
                    {"slug": "initech", "status": "archive", "features": {"growth": False}},
                    {"slug": "demo", "status": "active"},
                ],
            },
        )
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def _features_for(self, org: str) -> dict:
        _write(self.local_path, {"activeSpace": org})
        return config.load_config()["features"]

    def test_engineer_flag_holds_across_every_org(self):
        for org in ("globex", "initech", "demo"):
            self.assertTrue(self._features_for(org).get("growth"), org)

    def test_org_flag_switches_with_the_org(self):
        self.assertTrue(self._features_for("globex").get("sprintAwareness"))
        self.assertFalse(self._features_for("demo").get("sprintAwareness", False))

    def test_an_org_cannot_override_an_engineer_flag(self):
        # initech says growth: false on the org; the engineer's flag wins.
        self.assertTrue(self._features_for("initech")["growth"])

    def test_local_config_can_set_an_engineer_flag(self):
        _write(self.local_path, {"activeSpace": "demo", "features": {"communication": True}})
        feats = config.load_config()["features"]
        self.assertTrue(feats["communication"])
        self.assertTrue(feats["growth"])  # the default's sibling survives the merge

    def test_engineer_flag_absent_means_off(self):
        _write(self.default_path, {"activeSpace": "demo", "spaces": [{"slug": "demo"}]})
        self.assertNotIn("deck", self._features_for("demo"))

    def test_a_flag_nobody_has_named_yet_is_the_engineers_by_default(self):
        # A later module's flag needs no registration: top-level means engineer.
        _write(self.local_path, {"activeSpace": "globex", "features": {"someFutureModule": True}})
        self.assertTrue(config.load_config()["features"]["someFutureModule"])
        _write(
            self.local_path, {"activeSpace": "globex", "spaces": {"globex": {"features": {"someFutureModule": True}}}}
        )
        self.assertNotIn("someFutureModule", config.load_config()["features"])

    def test_effective_features_is_pure(self):
        merged = config.effective_features({"growth": 1, "deck": 0}, {"sprintAwareness": True, "growth": False})
        self.assertEqual(merged, {"sprintAwareness": True, "growth": True, "deck": False})


if __name__ == "__main__":
    unittest.main()
