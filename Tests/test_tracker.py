"""Which tracker answers for a board? -- the agent's half of one rule.

D-G2. The CLI's copy is
``Scripts/Resolve-Tracker.ps1``, run over the SAME table by ``Tests/Test-Setup.ps1``.
If PowerShell and Python ever disagree about a row, one of them is wrong.

Run:  python3 -m pytest Tests/test_tracker.py
"""

import json
import os
import subprocess
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
    from agent.core.config import tracker, tracker_owner
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

TABLE = json.loads((Path(__file__).parent / "fixtures" / "tracker" / "table.json").read_text())["rows"]


class TheRule(unittest.TestCase):
    def test_every_row_of_the_shared_table(self):
        self.assertGreaterEqual(len(TABLE), 10)
        for row in TABLE:
            with self.subTest(row["why"]):
                self.assertEqual(tracker(row["org"]), row["tracker"])

    def test_none_is_none(self):
        self.assertEqual(tracker(None), "none")

    def test_the_owner_rule_over_the_rows_that_pin_it(self):
        for row in TABLE:
            if "owner" in row:
                with self.subTest(row["org"] or "(blank)"):
                    self.assertEqual(tracker_owner(row["org"]), row["owner"])


class TheProbeDispatch(unittest.TestCase):
    """The tier probe asks the tracker the ADDRESS names, through its own CLI --
    gh for a GitHub board, az for an ADO one. No network: subprocess is stubbed."""

    def _argv(self, org_url: str) -> list[str]:
        from agent.core import tier

        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout="x", stderr="")

        with mock.patch.object(tier.subprocess, "run", side_effect=fake_run):
            self.assertTrue(tier._probe_tracker(org_url))
        self.assertEqual(len(calls), 1)
        return calls[0]

    def test_a_github_board_probes_gh_by_owner(self):
        argv = self._argv("https://github.com/johnfrog76")
        self.assertEqual(argv[0], "gh")
        self.assertIn("users/johnfrog76", argv)

    def test_an_ado_board_probes_az(self):
        argv = self._argv("https://dev.azure.com/SomeoneDemo")
        self.assertEqual(argv[0:2], ["az", "devops"])

    def test_a_blank_address_probes_nothing(self):
        from agent.core import tier

        with mock.patch.object(tier.subprocess, "run") as run:
            self.assertFalse(tier._probe_tracker(""))
        run.assert_not_called()


class EnvServesIt(unittest.TestCase):
    """The web never re-derives the rule: it reads ``tracker`` from ``/env``."""

    def _env(self, local: dict) -> dict:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        (base / "hub" / "gh" / "current").mkdir(parents=True)
        (base / "hub" / "demo" / "current").mkdir(parents=True)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": "gh",
                    "commandPrefix": "tk",
                    "features": {},
                    "commands": {},
                    "spaces": [
                        {
                            "slug": "gh",
                            "status": "active",
                            "promptsFolder": "gh",
                            "org": "https://github.com/johnfrog76",
                        },
                        {"slug": "demo", "status": "local", "promptsFolder": "demo"},
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

    def test_a_github_address_serves_github(self):
        self.assertEqual(self._env({})["tracker"], "github")

    def test_a_local_board_serves_none(self):
        self.assertEqual(self._env({"activeSpace": "demo"})["tracker"], "none")
