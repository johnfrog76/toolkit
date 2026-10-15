"""Team Agile's GET /api/ritual/triage -- the grouping rule, the text, the gate.

Triage is implemented twice, here (agent/solitaire/triage.py) and in the CLI's
Triage (Scripts/Triage-Rules.ps1), and held to ONE table:
Tests/fixtures/rituals/triage.json and the golden texts beside it, which
tkTestToolkit -Triage asserts from the other side. The route is a READ; the
answers are the CLI's Route through the bridge, which this suite does not run.

No network: gh and the tier probe are stubbed.

Run:  python3 -m pytest Tests/test_triage.py
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
    from agent.solitaire import triage
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "rituals"
TABLE = json.loads((FIXTURES / "triage.json").read_text(encoding="utf-8"))
CASES = {c["name"]: c for c in TABLE["cases"]}
CEREMONIES = json.loads((REPO_ROOT / C.rituals_ceremonies_file()).read_text(encoding="utf-8"))

TOOLKIT = "https://github.com/johnfrog76/toolkit"
ACME = "https://dev.azure.com/acme"


def _fill(case: dict) -> "triage.Triage":
    filled = triage.fill_triage(TABLE["labels"], case["issues"], case["tracker"], space=case["space"])
    filled.text = triage.render_triage(filled)
    return filled


def _golden(name: str) -> str:
    return (FIXTURES / name).read_bytes().decode("utf-8")


class TheCeremonyIsData(unittest.TestCase):
    def test_ceremonies_json_declares_triage_with_its_three_questions(self):
        row = CEREMONIES["triage"]
        self.assertEqual(row["slots"], ["milestone", "severity", "size"])
        self.assertEqual(row["severities"], ["sev1", "sev2", "sev3"])
        self.assertEqual(row["deepWaterLabel"], "deep-water")

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_triage_route(), "/api/ritual/triage")


class TheTable(unittest.TestCase):
    """Every case of the shared fixture, issues in, groups out."""

    def test_the_groups_in_order_with_their_counts_and_numbers(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                got = [
                    {
                        "milestone": g.milestone,
                        "open": g.open,
                        "routed": g.routed,
                        "unrouted": g.unrouted,
                        "context": g.context,
                        "issues": [i.number for i in g.issues],
                    }
                    for g in _fill(case).groups
                ]
                self.assertEqual(got, case["expected"]["groups"])

    def test_each_issues_worker_size_severity_and_deep_water(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                got = {
                    str(i.number): {
                        "worker": i.worker,
                        "size": i.size,
                        "severity": i.severity,
                        "deepWater": i.deepWater,
                    }
                    for g in _fill(case).groups
                    for i in g.issues
                }
                self.assertEqual(got, case["expected"]["issues"])

    def test_the_sizes_are_the_repos_worker_labels(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                self.assertEqual([s.label for s in _fill(case).sizes], case["expected"]["sizes"])

    def test_the_text_is_the_golden_file_byte_for_byte(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill(case).text, _golden(case["expected"]["text"]))

    def test_the_group_with_no_milestone_comes_first_even_when_smaller(self):
        issues = [
            {"number": n, "title": "t", "state": "OPEN", "labels": [], "milestone": {"title": "Big"}, "url": ""}
            for n in (1, 2, 3)
        ]
        issues.append({"number": 9, "title": "t", "state": "OPEN", "labels": [], "milestone": None, "url": ""})
        groups = triage.fill_triage([], issues, {"ok": True}).groups
        self.assertEqual([g.milestone for g in groups], ["", "Big"])

    def test_a_closed_issue_is_read_past(self):
        groups = _fill(CASES["mixed"]).groups
        self.assertNotIn(139, [i.number for g in groups for i in g.issues])


class TheRoute(unittest.TestCase):
    features = {"solitaireAgile": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        hub = base / "hub"
        (hub / "toolkit" / "current").mkdir(parents=True)
        default = base / "config.default.json"
        local = base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "toolkit",
                    "features": self.features,
                    "promptsRoot": str(hub),
                    "spaces": [
                        # Answered with agents: the routes answer only there.
                        {
                            "slug": "toolkit",
                            "status": "active",
                            "promptsFolder": "toolkit",
                            "org": TOOLKIT,
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

    def _get(self, path: str, case: str = "mixed", tier: int = 1, gh_fails: bool = False):
        fx = CASES[case]
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            if gh_fails:
                raise subprocess.TimeoutExpired(argv, 30)
            if argv[:3] == ["gh", "label", "list"]:
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(TABLE["labels"]), stderr="")
            # gh's own shape: label objects; only the open ones, as --state open asks.
            issues = [
                dict(i, labels=[lab if isinstance(lab, dict) else {"name": lab} for lab in i["labels"]])
                for i in fx["issues"]
                if i["state"] == "OPEN"
            ]
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(issues), stderr="")

        with (
            mock.patch.object(triage, "_resolve_tier", return_value=(tier, True)),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
        ):
            res = self.client.get(path)
        return res, calls

    def test_on_it_answers_the_fixtures_mixed_byte_for_byte(self):
        res, calls = self._get("/api/ritual/triage?space=toolkit")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["text"], _golden("triage-mixed.txt"))
        self.assertEqual((body["ceremony"], body["space"]), ("triage", "toolkit"))
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual(body["slots"], ["milestone", "severity", "size"])
        self.assertEqual(body["severities"], ["sev1", "sev2", "sev3"])
        self.assertEqual(body["deepWaterLabel"], "deep-water")
        self.assertEqual(
            body["sizes"],
            [
                {"label": "fable", "name": "Fable"},
                {"label": "opus", "name": "Opus"},
                {"label": "sonnet", "name": "Sonnet"},
            ],
        )
        self.assertEqual([c[:3] for c in calls], [["gh", "label", "list"], ["gh", "issue", "list"]])
        self.assertIn("johnfrog76/toolkit", calls[1])
        self.assertEqual(calls[1][calls[1].index("--state") + 1], "open")
        self.assertIn("milestone", calls[1][calls[1].index("--json") + 1].split(","))

    def test_the_response_field_names(self):
        body = self._get("/api/ritual/triage")[0].json()
        self.assertEqual(
            set(body),
            {"ceremony", "space", "tracker", "slots", "severities", "deepWaterLabel", "sizes", "groups", "text"},
        )
        self.assertEqual(set(body["groups"][0]), {"milestone", "open", "routed", "unrouted", "context", "issues"})
        self.assertEqual(
            set(body["groups"][0]["issues"][0]), {"number", "title", "url", "worker", "size", "severity", "deepWater"}
        )

    def test_no_space_is_the_active_one(self):
        self.assertEqual(self._get("/api/ritual/triage")[0].json()["space"], "toolkit")

    def test_an_ado_space_answers_with_the_tracker_line_and_gh_is_never_asked(self):
        res, calls = self._get("/api/ritual/triage?space=acme")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertEqual(body["groups"], [])
        self.assertIn("  Tracker    " + body["tracker"]["reason"], body["text"])
        self.assertEqual(calls, [])

    def test_below_tier_1_is_a_tracker_line(self):
        res, calls = self._get("/api/ritual/triage?space=toolkit", tier=2)
        self.assertEqual(res.status_code, 200)
        self.assertFalse(res.json()["tracker"]["ok"])
        self.assertEqual(calls, [])

    def test_gh_not_answering_is_the_no_tracker_golden(self):
        res, _calls = self._get("/api/ritual/triage?space=toolkit", gh_fails=True)
        body = res.json()
        self.assertEqual(
            body["tracker"], {"ok": False, "reason": "johnfrog76/toolkit: gh did not answer (TimeoutExpired)"}
        )
        self.assertEqual(
            body["text"].replace("johnfrog76/toolkit: ", "").replace(" (TimeoutExpired)", ""),
            _golden("triage-no-tracker.txt"),
        )

    def test_an_unknown_space_is_404_naming_it(self):
        res, calls = self._get("/api/ritual/triage?space=nowhere")
        self.assertEqual(res.status_code, 404)
        self.assertIn("nowhere", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_nothing_is_written_to_the_hub(self):
        hub = Path(self.tmp.name) / "hub"
        before = sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*"))
        self._get("/api/ritual/triage")
        self.assertEqual(sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*")), before)


class TheRouteWithTheFlagOff(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        res, calls = self._get("/api/ritual/triage?space=toolkit")
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])
        self.assertEqual(calls, [])

    test_on_it_answers_the_fixtures_mixed_byte_for_byte = None
    test_the_response_field_names = None
    test_no_space_is_the_active_one = None
    test_an_ado_space_answers_with_the_tracker_line_and_gh_is_never_asked = None
    test_below_tier_1_is_a_tracker_line = None
    test_gh_not_answering_is_the_no_tracker_golden = None
    test_an_unknown_space_is_404_naming_it = None


class TheAppMountsIt(unittest.TestCase):
    def test_the_app_serves_the_route(self):
        from agent.app import app

        paths = set(
            app.openapi()["paths"]
        )  # fastapi >=0.142 includes routers lazily, so app.routes no longer lists them
        self.assertIn(C.rituals_triage_route(), paths)


if __name__ == "__main__":
    unittest.main(verbosity=2)
