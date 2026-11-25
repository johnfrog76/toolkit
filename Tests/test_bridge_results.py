"""What ``POST /api/cmd/{name}`` answers, one row per outcome -- the agent's half
of ``Tests/fixtures/bridge/results.json``.

The CLI's half is ``Tests/Test-ExitCodes.ps1``, which runs ``bridge.ps1`` over the
same table the way this route does. The two together hold the contract the web
reads: ``exit_code`` 2 is a STATED refusal (the verb said why, once), 1 is a
failure that stated nothing, -1 is nothing ran, and ``status`` keeps its four
values.

Run with the REAL bridge, in a scratch package: the probe module
(``Tests/fixtures/bridge/probe/``) is copied into its ``Config/`` and switched on
in its ``config.local.json``, so every verb in the table is reached through the
CLI's own command map, the real guard and the real ``bridge.ps1``. A suite that
mocked the subprocess would pass with the PowerShell half broken.

Run directly:  python3 Tests/test_bridge_results.py
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

    from agent.ado import bridge
    from agent.app import app
    from agent.core import config
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

FIXTURES = PKG_ROOT / "Tests" / "fixtures" / "bridge"
TABLE = json.loads((FIXTURES / "results.json").read_text("utf-8"))
ROWS = TABLE["rows"]
FEATURE = "bridgeProbe"

HAVE_PWSH = shutil.which("pwsh") is not None


@unittest.skipUnless(HAVE_PWSH, "needs pwsh to run the bridge for real")
class TheRouteAnswersTheSharedTable(unittest.TestCase):
    """Every row of the table, posted to the route with the real bridge."""

    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.pkg = root / "pkg"
        cls.pkg.mkdir()
        for name in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / name, cls.pkg / name)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, cls.pkg / folder)
        (cls.pkg / "agent" / "ado").mkdir(parents=True)
        shutil.copy(bridge.BRIDGE_PS1, cls.pkg / "agent" / "ado" / "bridge.ps1")
        probe = FIXTURES / "probe"
        for item in probe.iterdir():
            if item.is_dir():
                shutil.copytree(item, cls.pkg / "Config" / item.name)
            else:
                shutil.copy(item, cls.pkg / "Config" / item.name)
        cls.hub = root / "hub"
        cls.hub.mkdir()

        cls._saved = (bridge._map_cache, bridge._map_key)
        env = {k: v for k, v in os.environ.items() if not k.startswith("TEAMS_WEBHOOK_")}
        env.pop("PROMPTS_ROOT", None)
        env.pop("P20_ACTIVE_SPACE", None)
        cls._patches = [
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(bridge, "REPO_ROOT", cls.pkg),
            mock.patch.object(bridge, "UTILITIES", cls.pkg / "utilities.psm1"),
            mock.patch.object(bridge, "BRIDGE_PS1", cls.pkg / "agent" / "ado" / "bridge.ps1"),
            mock.patch.object(bridge, "MODULE_COMMANDS_DIR", cls.pkg / "Config"),
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", cls.pkg / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", cls.pkg / "config.local.json"),
            mock.patch.object(bridge, "_map_cache", {}),
            mock.patch.object(bridge, "_map_key", None),
        ]
        for p in cls._patches:
            p.start()

    @classmethod
    def tearDownClass(cls):
        for p in reversed(cls._patches):
            p.stop()
        bridge._map_cache, bridge._map_key = cls._saved
        cls._tmp.cleanup()

    def _flag(self, on: bool):
        local = {"promptsRoot": str(self.hub), "features": {FEATURE: on}}
        (self.pkg / "config.local.json").write_text(json.dumps(local), encoding="utf-8")
        bridge.command_map(force=True)

    def test_the_table_has_every_case_the_contract_names(self):
        cases = " | ".join(r["case"] for r in ROWS)
        words = ("succeeds", "stated refusal", "wrapper states", "throws", "exits 3", "caught inside")
        words += ("outside", "timeout", "flag is off", "switch")
        for word in words:
            with self.subTest(word=word):
                self.assertIn(word, cases)

    def test_every_row(self):
        for row in ROWS:
            with self.subTest(case=row["case"]):
                self._flag(row["flag"])
                body = client.post(f"/api/cmd/{row['verb']}", json={"params": row["params"]}).json()
                want = row["route"]
                self.assertEqual(body["status"], want["status"], body)
                self.assertEqual(body["exit_code"], want["exit_code"], body)
                if want["error"] is None:
                    self.assertIsNone(body["error"], body)
                else:
                    self.assertEqual((body["error"] or "").strip(), want["error"], body)
                said = body["output"] if want["status"] == "success" else body["error"]
                self.assertIn(want["says"], said or "", body)
                if want["status"] in ("rejected", "timeout"):
                    self.assertIsNone(body["output"], body)

    def test_a_stated_refusal_is_told_from_a_throw_only_by_the_code(self):
        """Both are ``status: error`` with a sentence; the code is the difference."""
        by_case = {r["case"]: r["route"] for r in ROWS}
        stated = next(v for k, v in by_case.items() if k.startswith("a stated refusal"))
        threw = next(v for k, v in by_case.items() if "throws" in k)
        self.assertEqual(stated["status"], threw["status"])
        self.assertEqual((stated["exit_code"], threw["exit_code"]), (2, 1))


if __name__ == "__main__":
    unittest.main(verbosity=2)
