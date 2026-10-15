"""Is Azure DevOps part of what this machine shows? -- the agent's half of one rule.

``docs/modules/ado.md``. The CLI's copy is
``Scripts/Test-AdoEnabled.ps1``, run over the SAME table by ``Tests/Test-Setup.ps1``.
If PowerShell and Python ever disagree about a row, one of them is wrong.

Run:  python3 -m pytest Tests/test_ado_enabled.py
"""

import json
import os
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

    from agent.core import config
    from agent.core.config import ado_enabled
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

TABLE = json.loads((Path(__file__).parent / "fixtures" / "ado-enabled" / "table.json").read_text())["rows"]


class TheRule(unittest.TestCase):
    def test_every_row_of_the_shared_table(self):
        self.assertGreaterEqual(len(TABLE), 13)
        for row in TABLE:
            with self.subTest(row["why"]):
                self.assertIs(ado_enabled(row["spaceStatus"], row["flag"], row["tracker"]), row["enabled"])

    def test_the_table_distinguishes_a_connected_github_space(self):
        """The row this rule exists for: active, nobody has said, and the tracker is GitHub."""
        rows = [r for r in TABLE if r["spaceStatus"] == "active" and r["flag"] is None]
        self.assertEqual({r["tracker"]: r["enabled"] for r in rows}, {"ado": True, "github": False, "none": False})


class EnvServesIt(unittest.TestCase):
    """The web never re-derives the rule: it reads ``ado.enabled`` from ``/env``."""

    def _env(self, local: dict) -> dict:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        (base / "hub" / "demo" / "current").mkdir(parents=True)
        (base / "hub" / "test" / "current").mkdir(parents=True)
        (base / "hub" / "gh" / "current").mkdir(parents=True)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "commandPrefix": "tk",
                    "features": {},
                    "commands": {},
                    "spaces": [
                        {
                            "slug": "test",
                            "status": "active",
                            "promptsFolder": "test",
                            "org": "https://dev.azure.com/YOUR-ADO-ORG",
                        },
                        {"slug": "demo", "status": "local", "promptsFolder": "demo"},
                        {
                            "slug": "gh",
                            "status": "active",
                            "promptsFolder": "gh",
                            "org": "https://github.com/acme/widgets",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        (base / "config.local.json").write_text(
            json.dumps({"promptsRoot": str(base / "hub"), **local}), encoding="utf-8"
        )
        patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        from agent.app import app

        return TestClient(app).get("/api/env").json()

    def test_it_follows_the_org_you_are_in(self):
        self.assertEqual(self._env({"activeSpace": "demo"})["ado"], {"enabled": False, "explicit": False})

    def test_an_active_space_is_on_without_anyone_saying_so(self):
        self.assertEqual(self._env({})["ado"], {"enabled": True, "explicit": False})

    def test_a_connected_github_space_is_off_and_the_tracker_says_why(self):
        """Active, nobody has said, and the address is GitHub: the same answer the CLI's inventory prints."""
        env = self._env({"activeSpace": "gh"})
        self.assertEqual(env["ado"], {"enabled": False, "explicit": False})
        self.assertEqual(env["tracker"], "github")
        self.assertEqual(env["spaceStatus"], "active")
        self.assertEqual(
            self._env({"activeSpace": "gh", "features": {"ado": True}})["ado"], {"enabled": True, "explicit": True}
        )

    def test_the_explicit_answer_wins_and_says_it_is_explicit(self):
        self.assertEqual(self._env({"features": {"ado": False}})["ado"], {"enabled": False, "explicit": True})
        self.assertEqual(
            self._env({"activeSpace": "demo", "features": {"ado": True}})["ado"], {"enabled": True, "explicit": True}
        )
