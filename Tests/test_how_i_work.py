"""How do you want to work in this Space? -- the agent's half of one rule.

The answer is the Space's, derived from the tracker its address names and asked
only on GitHub; Team Agile is on only where its switch is on AND the active
Space's answer is ``agents``. The CLI's copy is ``Scripts/Resolve-HowIWork.ps1``,
run over the SAME table by ``tkTestToolkit -Environment``. If PowerShell and
Python ever disagree about a row, one of them is wrong.

Run:  python -m pytest Tests/test_how_i_work.py
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
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.core import consts as C
    from agent.core.config import apply_how_i_work, how_i_work, load_config
    from agent.solitaire import standup
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

TABLE = json.loads((Path(__file__).parent / "fixtures" / "how-i-work" / "table.json").read_text(encoding="utf-8"))

GITHUB = "https://github.com/acme/widgets"
AZURE = "https://dev.azure.com/acme"


class TheRule(unittest.TestCase):
    def test_every_row_of_the_shared_table(self):
        self.assertGreaterEqual(len(TABLE["rows"]), 10)
        for row in TABLE["rows"]:
            with self.subTest(org=row["org"], stored=row["stored"]):
                want = {k: row[k] for k in ("answer", "source", "tracker", "locked")}
                self.assertEqual(how_i_work(row["org"], row["stored"]), want)

    def test_every_gate_row(self):
        for row in TABLE["gate"]:
            with self.subTest(row=row):
                features = {} if row["switch"] is None else {"solitaireAgile": row["switch"]}
                out = apply_how_i_work(features, row["answer"])
                self.assertEqual(out.get("solitaireAgile"), row["on"])

    def test_the_gate_touches_no_other_flag(self):
        out = apply_how_i_work({"solitaireAgile": True, "growth": True}, "alone")
        self.assertEqual(out, {"solitaireAgile": False, "growth": True})

    def test_team_is_never_a_stored_answer(self):
        self.assertNotIn("team", config.HOW_I_WORK_STORED)


class TheConfig(unittest.TestCase):
    """load_config applies the answer: the features map /env serves is the gated
    one, and ``howIWork`` carries the answer with the switch as set."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.hub = base / "hub"
        for slug in ("widgets", "solo", "acme", "fresh"):
            (self.hub / slug / "current").mkdir(parents=True)
        self.default = base / "config.default.json"
        self.local = base / "config.local.json"
        self.local.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        for var in ("PROMPTS_ROOT", C.env_active_space(), C.env_features()):
            os.environ.pop(var, None)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def _write(self, active: str, switch=True):
        features = {} if switch is None else {"solitaireAgile": switch, "growth": True}
        self.default.write_text(
            json.dumps(
                {
                    "activeSpace": active,
                    "features": features,
                    "promptsRoot": str(self.hub),
                    "spaces": [
                        {
                            "slug": "widgets",
                            "status": "active",
                            "promptsFolder": "widgets",
                            "org": GITHUB,
                            "howIWork": "agents",
                        },
                        {"slug": "solo", "status": "local", "promptsFolder": "solo", "org": "", "howIWork": "agents"},
                        {"slug": "acme", "status": "active", "promptsFolder": "acme", "org": AZURE},
                        {"slug": "fresh", "status": "local", "promptsFolder": "fresh", "org": GITHUB},
                    ],
                }
            ),
            encoding="utf-8",
        )

    def test_a_github_space_answered_with_agents_is_on(self):
        self._write("widgets")
        cfg = load_config()
        self.assertTrue(cfg["features"]["solitaireAgile"])
        self.assertEqual(
            cfg["howIWork"],
            {"answer": "agents", "source": "chosen", "tracker": "github", "locked": False, "switch": True},
        )

    def test_switching_space_re_evaluates_and_leaves_the_other_flags(self):
        for slug, answer, source in (
            ("solo", "alone", "derived"),
            ("acme", "team", "derived"),
            ("fresh", "alone", "default"),
        ):
            with self.subTest(slug):
                self._write(slug)
                cfg = load_config()
                self.assertFalse(cfg["features"]["solitaireAgile"])
                self.assertTrue(cfg["features"]["growth"])
                self.assertEqual((cfg["howIWork"]["answer"], cfg["howIWork"]["source"]), (answer, source))
                self.assertTrue(cfg["howIWork"]["switch"])

    def test_the_switch_off_stays_off_whatever_the_answer(self):
        self._write("widgets", switch=False)
        cfg = load_config()
        self.assertFalse(cfg["features"]["solitaireAgile"])
        self.assertFalse(cfg["howIWork"]["switch"])

    def test_a_switch_nobody_set_stays_absent(self):
        self._write("widgets", switch=None)
        cfg = load_config()
        self.assertNotIn("solitaireAgile", cfg["features"])
        self.assertIsNone(cfg["howIWork"]["switch"])

    def test_a_local_patch_answers_too(self):
        self._write("fresh")
        self.local.write_text(json.dumps({"spaces": {"fresh": {"howIWork": "agents"}}}), encoding="utf-8")
        self.assertTrue(load_config()["features"]["solitaireAgile"])

    def test_the_routes_follow_the_answer_and_say_which_is_off(self):
        app = FastAPI()
        app.include_router(standup.api, prefix="/api")
        client = TestClient(app)
        self._write("solo")
        res = client.get("/api/ritual/standup/remind")
        self.assertEqual(res.status_code, 404)
        self.assertIn("howIWork", res.json()["detail"])
        self._write("solo", switch=False)
        res = client.get("/api/ritual/standup/remind")
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])


if __name__ == "__main__":
    unittest.main()
