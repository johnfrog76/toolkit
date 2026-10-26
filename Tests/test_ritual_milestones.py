"""Team Agile's GET /api/ritual/milestones -- the table, the kept read, the gate.

The Milestones tab's read (docs/modules/solitaire-agile.md, "Milestones: the tab
and the award"). Its rows are the ado core's own (accounting.github_milestone_rows,
the reader behind GET /api/milestones, whose reached rule Tests/test_milestones.py
pins), so this suite holds the table and Team Agile's shape around it. One table,
Tests/fixtures/rituals/milestones.json: gh's own milestone rows in, the route's
rows out -- open with and without a due date, every issue closed while GitHub
still shows it open, closed on GitHub with and without an issue still open, and
empty, open and closed. The page's own test draws from the same `expected`.

No network: gh and the tier probe are stubbed.

Run:  python3 -m pytest Tests/test_ritual_milestones.py
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

REPO_ROOT = Path(__file__).resolve().parent.parent
try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.core import config
    from agent.core import consts as C
    from agent.solitaire import api as solitaire_api
    from agent.solitaire import tracker as solitaire_tracker
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

TABLE = json.loads((REPO_ROOT / "Tests" / "fixtures" / "rituals" / "milestones.json").read_text(encoding="utf-8"))
REPO = TABLE["repo"]
WIDGETS = f"https://github.com/{REPO}"
ACME = "https://dev.azure.com/acme"


class TheTable(unittest.TestCase):
    """gh's rows in, the route's rows out: every shape the reached rule distinguishes."""

    def _served(self) -> list[dict]:
        def fake_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(TABLE["rows"]), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            rows, why = accounting.github_milestone_rows(REPO)
        self.assertIsNone(why)
        return [m.model_dump() for m in rows]

    def test_gh_rows_in_the_routes_rows_out(self):
        self.assertEqual(self._served(), TABLE["expected"])

    def test_reached_by_shape(self):
        """One row a shape: (title, GitHub's state, open, closed) -> reached."""
        got = {m["title"]: (m["state"], m["open"], m["closed"], m["reached"]) for m in TABLE["expected"]}
        self.assertEqual(
            got,
            {
                "Someday": ("open", 2, 0, False),  # nothing closed yet, no due date
                "M4b -- 1.5.0": ("open", 0, 12, True),  # every issue closed, GitHub still open
                "M4c -- 1.6.0": ("open", 3, 5, False),  # in flight, with a due date
                "M2 -- 1.3.0": ("closed", 0, 9, True),  # every issue closed, closed on GitHub
                "M3 -- the spike": ("closed", 1, 4, False),  # closed on GitHub, an issue still open
                "Parking lot": ("open", 0, 0, False),  # no issues at all
                "Abandoned": ("closed", 0, 0, False),  # no issues, closed on GitHub
            },
        )

    def test_an_empty_milestone_is_never_reached(self):
        """The zero-issue decision: 0/0 is not an achievement, open or closed on the tracker."""
        empties = [m for m in TABLE["expected"] if m["open"] + m["closed"] == 0]
        self.assertEqual({m["state"] for m in empties}, {"open", "closed"})
        self.assertTrue(all(not m["reached"] for m in empties))
        self.assertFalse(accounting.milestone_reached(0, 0))

    def test_due_dates_with_and_without(self):
        dues = [m["due"] for m in TABLE["expected"]]
        self.assertIn("", dues)
        self.assertIn("2026-11-15", dues)

    def test_the_bar_is_the_trackers_own_numbers(self):
        by_number = {r["number"]: r for r in TABLE["rows"]}
        for m in TABLE["expected"]:
            with self.subTest(milestone=m["title"]):
                row = by_number[m["number"]]
                self.assertEqual((m["open"], m["closed"]), (row["open_issues"], row["closed_issues"]))

    def test_the_dates_the_award_says(self):
        m = next(m for m in TABLE["expected"] if m["title"] == "M4b -- 1.5.0")
        self.assertEqual((m["created_at"], m["updated_at"], m["closed_at"]), ("2026-10-01", "2026-10-24", ""))

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_milestones_route(), "/api/ritual/milestones")


class TheRoute(unittest.TestCase):
    features = {"solitaireAgile": True}

    def setUp(self):
        solitaire_tracker.forget()
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        hub = base / "hub"
        (hub / "widgets" / "current").mkdir(parents=True)
        default = base / "config.default.json"
        local = base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "widgets",
                    "features": self.features,
                    "promptsRoot": str(hub),
                    "spaces": [
                        {
                            "slug": "widgets",
                            "status": "active",
                            "promptsFolder": "widgets",
                            "org": WIDGETS,
                            "howIWork": "agents",
                        },
                        {
                            "slug": "acme",
                            "status": "active",
                            "promptsFolder": "acme",
                            "org": ACME,
                            "projects": [{"name": "Platform", "repo": "platform"}],
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        local.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        for var in ("PROMPTS_ROOT", C.env_active_space(), C.env_features()):
            os.environ.pop(var, None)
        app = FastAPI()
        app.include_router(solitaire_api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()
        solitaire_tracker.forget()

    def _get(self, path: str, tier: int = 1, gh_fails: bool = False):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            if gh_fails:
                raise subprocess.TimeoutExpired(argv, 30)
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(TABLE["rows"]), stderr="")

        with (
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(tier, True)),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
        ):
            res = self.client.get(path)
        return res, calls

    def test_on_it_answers_the_table(self):
        res, calls = self._get("/api/ritual/milestones?space=widgets")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(set(body), {"ceremony", "space", "tracker", "milestones"})
        self.assertEqual((body["ceremony"], body["space"]), ("milestones", "widgets"))
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual(body["milestones"], TABLE["expected"])
        self.assertEqual(len(calls), 1)

    def test_gh_is_asked_with_fields_never_a_url_query(self):
        """On Windows gh runs through the shell: an `&` in the argv would be cmd's."""
        _res, calls = self._get("/api/ritual/milestones")
        argv = calls[0]
        self.assertEqual(argv[:4], ["gh", "api", "--method", "GET"])
        self.assertIn(f"repos/{REPO}/milestones", argv)
        self.assertIn("state=all", argv)
        self.assertIn("per_page=100", argv)
        self.assertFalse(any("&" in a or "?" in a for a in argv), argv)

    def test_a_second_read_inside_the_minute_asks_gh_nothing_and_refresh_asks_again(self):
        self._get("/api/ritual/milestones")
        _res, calls = self._get("/api/ritual/milestones")
        self.assertEqual(calls, [])
        _res, calls = self._get("/api/ritual/milestones?refresh=1")
        self.assertEqual(len(calls), 1)

    def test_no_space_is_the_active_one(self):
        self.assertEqual(self._get("/api/ritual/milestones")[0].json()["space"], "widgets")

    def test_an_ado_space_is_a_tracker_line_and_gh_is_never_asked(self):
        res, calls = self._get("/api/ritual/milestones?space=acme")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertIn("not GitHub", body["tracker"]["reason"])
        self.assertEqual(body["milestones"], [])
        self.assertEqual(calls, [])

    def test_below_tier_1_is_a_tracker_line(self):
        res, calls = self._get("/api/ritual/milestones", tier=2)
        self.assertFalse(res.json()["tracker"]["ok"])
        self.assertEqual(calls, [])

    def test_gh_not_answering_is_a_reason_and_is_not_kept(self):
        res, _calls = self._get("/api/ritual/milestones", gh_fails=True)
        body = res.json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertTrue(body["tracker"]["reason"].startswith(f"{REPO}: "), body["tracker"]["reason"])
        self.assertEqual(body["milestones"], [])
        _res, calls = self._get("/api/ritual/milestones")
        self.assertEqual(len(calls), 1)

    def test_an_unknown_space_is_404_naming_it(self):
        res, calls = self._get("/api/ritual/milestones?space=nowhere")
        self.assertEqual(res.status_code, 404)
        self.assertIn("nowhere", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_nothing_is_written_to_the_hub(self):
        hub = Path(self.tmp.name) / "hub"
        before = sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*"))
        self._get("/api/ritual/milestones")
        self.assertEqual(sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*")), before)


class TheRouteWithTheFlagOff(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        res, calls = self._get("/api/ritual/milestones?space=widgets")
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])
        self.assertEqual(calls, [])

    test_on_it_answers_the_table = None
    test_gh_is_asked_with_fields_never_a_url_query = None
    test_a_second_read_inside_the_minute_asks_gh_nothing_and_refresh_asks_again = None
    test_no_space_is_the_active_one = None
    test_an_ado_space_is_a_tracker_line_and_gh_is_never_asked = None
    test_below_tier_1_is_a_tracker_line = None
    test_gh_not_answering_is_a_reason_and_is_not_kept = None
    test_an_unknown_space_is_404_naming_it = None


class TheAppMountsIt(unittest.TestCase):
    def test_the_app_serves_the_route(self):
        from agent.app import app

        self.assertIn(C.rituals_milestones_route(), set(app.openapi()["paths"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
