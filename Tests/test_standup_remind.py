"""The reminder to attend (Team Agile V1, D-TA15) -- the agent's half.

The cadence rule is implemented twice, here (agent/solitaire/remind.py) and in
the CLI's Scripts/Standup-Remind.ps1, and held to ONE table:
Tests/fixtures/rituals/remind.json, which tkTestToolkit -StandupRemind asserts
from the other side.

The routes: POST /api/ritual/standup/attend runs Organize's own verbs through
the bridge -- stubbed here by a fake ``bridge._run`` that does to the scratch hub
what the verb would, so "twice in a day writes nothing more" is the real
sequence -- and GET /api/ritual/standup/remind reads what the settings row shows.
Both are 404 with features.solitaireAgile off.

Run:  python3 -m pytest Tests/test_standup_remind.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

REPO_ROOT = Path(__file__).resolve().parent.parent
try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import bridge
    from agent.core import config
    from agent.core import consts as C
    from agent.solitaire import remind, standup
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

TABLE = json.loads((REPO_ROOT / "Tests" / "fixtures" / "rituals" / "remind.json").read_text(encoding="utf-8"))


def _at(text: str) -> datetime:
    return datetime.strptime(text, "%Y-%m-%dT%H:%M")


class TheTable(unittest.TestCase):
    """Every row of the shared fixture."""

    def test_days(self):
        for row in TABLE["days"]:
            with self.subTest(input=row["input"]):
                got = remind.parse_days(row["input"])
                self.assertEqual(None if got is None else remind.format_days(got), row["days"])

    def test_times(self):
        for row in TABLE["times"]:
            with self.subTest(input=row["input"]):
                self.assertEqual(remind.parse_time(row["input"]), row["time"])

    def test_the_first_due_remind_writes(self):
        for row in TABLE["first"]:
            with self.subTest(row["name"]):
                days = remind.parse_days(row["days"])
                self.assertEqual(remind.first_due(_at(row["now"]), row["time"], days), row["due"])

    def test_what_attending_does(self):
        for row in TABLE["attend"]:
            with self.subTest(row["name"]):
                plan = remind.attend_plan(_at(row["now"]), [("K7M2", row["due"], row["ref"])])
                self.assertEqual(plan.action, row["action"])
                self.assertEqual(plan.next, row["next"])
                if row["action"] == "rearm":
                    self.assertEqual(plan.archive, ["K7M2"])

    def test_the_contract(self):
        self.assertEqual(C.rituals_attend_route(), "/api/ritual/standup/attend")
        self.assertEqual(C.rituals_remind_route(), "/api/ritual/standup/remind")
        self.assertEqual(C.rituals_remind_source(), "standup")
        self.assertEqual(C.rituals_weekdays()[0], "Mon")


class TheSmallerRules(unittest.TestCase):
    def test_a_cadence_round_trips_through_its_ref(self):
        self.assertEqual(remind.parse_cadence("09:00 Mon-Fri"), ("09:00", [0, 1, 2, 3, 4]))
        self.assertEqual(remind.format_cadence("09:00", [0, 2, 4]), "09:00 Mon,Wed,Fri")
        self.assertIsNone(remind.parse_cadence("09:00"))
        self.assertIsNone(remind.parse_cadence("whenever Mon"))

    def test_two_open_and_one_already_ahead_is_nothing(self):
        plan = remind.attend_plan(
            _at("2026-10-02T10:00"),
            [("A1B2", "2026-10-01T09:00", "09:00 Mon-Fri"), ("C3D4", "2026-10-05T09:00", "09:00 Mon-Fri")],
        )
        self.assertEqual(plan.action, "none")

    def test_two_open_and_both_behind_archives_both_and_writes_one(self):
        plan = remind.attend_plan(
            _at("2026-10-02T10:00"),
            [("A1B2", "2026-09-30T09:00", "09:00 Mon-Fri"), ("C3D4", "2026-10-01T09:00", "09:00 Mon-Fri")],
        )
        self.assertEqual((plan.action, plan.archive, plan.next), ("rearm", ["A1B2", "C3D4"], "2026-10-05T09:00"))


FRIDAY = "2026-10-02T10:00"


class TheRoutes(unittest.TestCase):
    features = {"solitaireAgile": True, "organize": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.hub = base / "hub"
        (self.hub / "toolkit" / "current").mkdir(parents=True)
        self.current = self.hub / "reminders" / "current"
        self.archive = self.hub / "reminders" / "archive"
        self.current.mkdir(parents=True)
        default = base / "config.default.json"
        local = base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "toolkit",
                    "features": self.features,
                    "promptsRoot": str(self.hub),
                    # A GitHub address answered with agents -- the one kind of
                    # Space Team Agile's routes answer in; local, so nothing is asked of gh.
                    "spaces": [
                        {
                            "slug": "toolkit",
                            "status": "local",
                            "promptsFolder": "toolkit",
                            "org": "https://github.com/acme/toolkit",
                            "howIWork": "agents",
                        }
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
            mock.patch.object(
                bridge, "command_map", return_value={"Reminders": "Get-P20Reminders", "NewReminder": "New-P20Reminder"}
            ),
            mock.patch.object(bridge, "command_timeout", return_value=30),
            mock.patch.object(bridge, "_run", side_effect=self._fake_run),
            mock.patch.object(remind, "_now", side_effect=lambda: _at(self.now)),
        ]
        for p in self.patches:
            p.start()
        for var in ("PROMPTS_ROOT", C.env_active_space(), C.env_features()):
            os.environ.pop(var, None)
        self.now = FRIDAY
        self.calls: list[tuple[str, list[str]]] = []
        self.ids = iter(["N7X4", "N9X3", "N3X7"])
        app = FastAPI()
        app.include_router(standup.api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    # What Organize's verbs do to the hub, done here instead of in a child pwsh.
    def _fake_run(self, function, params, _timeout, extra_env=None):
        self.calls.append((function, list(params)))
        if function == "Get-P20Reminders":
            rid = params[0]
            src = next(self.current.glob(f"{rid}-*.md"))
            self.archive.mkdir(exist_ok=True)
            src.rename(self.archive / src.name)
        elif function == "New-P20Reminder":
            args = dict(zip(params[0::2], params[1::2]))
            self._write(next(self.ids), args["-Title"], args["-Due"], args["-Source"], args["-Ref"])
        return subprocess.CompletedProcess([function], 0, stdout="", stderr="")

    def _write(self, rid, title, due, source, ref):
        (self.current / f"{rid}-{title.lower()}.md").write_text(
            f"# {title}\n\n---\n\n**Due:** {due}\n**Source:** {source}\n**Ref:** {ref}\n**Created:** 2026-10-01\n",
            encoding="utf-8",
        )

    def _open(self):
        return sorted(p.name for p in self.current.glob("*.md"))

    def test_the_routes_are_the_contracts(self):
        paths = set(
            self.client.app.openapi()["paths"]
        )  # fastapi >=0.142: app.routes holds the lazy router, not its paths
        self.assertIn(C.rituals_attend_route(), paths)
        self.assertIn(C.rituals_remind_route(), paths)

    def test_attending_archives_fridays_and_writes_mondays(self):
        self._write("K7M2", "Standup", "2026-10-02T09:00", "standup", "09:00 Mon-Fri")
        res = self.client.post("/api/ritual/standup/attend")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual((body["action"], body["archived"], body["next"]), ("rearm", ["K7M2"], "2026-10-05T09:00"))
        self.assertEqual(
            self.calls,
            [
                ("Get-P20Reminders", ["K7M2", "-Archive"]),
                (
                    "New-P20Reminder",
                    ["-Title", "Standup", "-Due", "2026-10-05T09:00", "-Source", "standup", "-Ref", "09:00 Mon-Fri"],
                ),
            ],
        )
        self.assertEqual(self._open(), ["N7X4-standup.md"])
        self.assertTrue((self.archive / "K7M2-standup.md").is_file())

    def test_twice_in_a_day_writes_nothing_more(self):
        self._write("K7M2", "Standup", "2026-10-02T09:00", "standup", "09:00 Mon-Fri")
        self.client.post("/api/ritual/standup/attend")
        self.calls.clear()
        body = self.client.post("/api/ritual/standup/attend").json()
        self.assertEqual(body["action"], "none")
        self.assertEqual(self.calls, [])
        self.assertEqual(self._open(), ["N7X4-standup.md"])

    def test_no_standup_reminder_is_nothing_to_do(self):
        self._write("Q4TN", "Review the sprint goals", "2026-10-01T09:00", "manual", "")
        body = self.client.post("/api/ritual/standup/attend").json()
        self.assertEqual(body["action"], "absent")
        self.assertEqual(self.calls, [])

    def test_a_ref_that_is_not_a_cadence_is_left_alone_and_said(self):
        self._write("K7M2", "Standup", "2026-10-01T09:00", "standup", "whenever")
        body = self.client.post("/api/ritual/standup/attend").json()
        self.assertEqual(body["action"], "unreadable")
        self.assertIn("whenever", body["reason"])
        self.assertEqual(self.calls, [])

    def test_a_verb_that_refuses_is_a_reason_not_a_500(self):
        self._write("K7M2", "Standup", "2026-10-02T09:00", "standup", "09:00 Mon-Fri")
        with mock.patch.object(
            bridge,
            "_run",
            return_value=subprocess.CompletedProcess(["x"], 1, stdout="", stderr="No open reminder with id 'K7M2'."),
        ):
            res = self.client.post("/api/ritual/standup/attend")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["action"], "error")
        self.assertIn("K7M2", res.json()["reason"])

    def test_the_remind_route_reads_the_cadence_back(self):
        self.assertEqual(self.client.get("/api/ritual/standup/remind").json(), {"organize": True, "reminder": None})
        self._write("K7M2", "Standup", "2026-10-05T09:00", "standup", "09:00 Mon,Wed,Fri")
        body = self.client.get("/api/ritual/standup/remind").json()
        self.assertEqual(
            body["reminder"],
            {
                "id": "K7M2",
                "due": "2026-10-05T09:00",
                "ref": "09:00 Mon,Wed,Fri",
                "time": "09:00",
                "days": ["Mon", "Wed", "Fri"],
            },
        )

    def test_the_attend_route_writes_nothing_itself(self):
        # Every change above came through the (fake) bridge; with _run doing
        # nothing, the hub does not move.
        self._write("K7M2", "Standup", "2026-10-02T09:00", "standup", "09:00 Mon-Fri")
        before = sorted(p.relative_to(self.hub).as_posix() for p in self.hub.rglob("*"))
        with mock.patch.object(
            bridge, "_run", return_value=subprocess.CompletedProcess(["x"], 0, stdout="", stderr="")
        ):
            self.client.post("/api/ritual/standup/attend")
        self.assertEqual(sorted(p.relative_to(self.hub).as_posix() for p in self.hub.rglob("*")), before)


class TheRoutesWithOrganizeOff(TheRoutes):
    features = {"solitaireAgile": True}

    def test_attending_with_organize_off_does_nothing_and_says_so(self):
        self._write("K7M2", "Standup", "2026-10-02T09:00", "standup", "09:00 Mon-Fri")
        res = self.client.post("/api/ritual/standup/attend")
        self.assertEqual(res.status_code, 200)
        self.assertEqual((res.json()["organize"], res.json()["action"]), (False, "off"))
        self.assertIn("features.organize", res.json()["reason"])
        self.assertEqual(self.calls, [])
        self.assertEqual(self.client.get("/api/ritual/standup/remind").json(), {"organize": False, "reminder": None})

    test_attending_archives_fridays_and_writes_mondays = None
    test_twice_in_a_day_writes_nothing_more = None
    test_no_standup_reminder_is_nothing_to_do = None
    test_a_ref_that_is_not_a_cadence_is_left_alone_and_said = None
    test_a_verb_that_refuses_is_a_reason_not_a_500 = None
    test_the_remind_route_reads_the_cadence_back = None


class TheRoutesWithTheModuleOff(TheRoutes):
    features = {"organize": True}

    def test_off_is_404_not_403(self):
        self.assertEqual(self.client.post("/api/ritual/standup/attend").status_code, 404)
        self.assertEqual(self.client.get("/api/ritual/standup/remind").status_code, 404)
        self.assertEqual(self.calls, [])

    test_attending_archives_fridays_and_writes_mondays = None
    test_twice_in_a_day_writes_nothing_more = None
    test_no_standup_reminder_is_nothing_to_do = None
    test_a_ref_that_is_not_a_cadence_is_left_alone_and_said = None
    test_a_verb_that_refuses_is_a_reason_not_a_500 = None
    test_the_remind_route_reads_the_cadence_back = None
    test_the_attend_route_writes_nothing_itself = None


class TheAppMountsThem(unittest.TestCase):
    def test_the_app_serves_both_routes(self):
        from agent.app import app

        paths = set(
            app.openapi()["paths"]
        )  # fastapi >=0.142 includes routers lazily, so app.routes no longer lists them
        self.assertIn(C.rituals_attend_route(), paths)
        self.assertIn(C.rituals_remind_route(), paths)


if __name__ == "__main__":
    unittest.main(verbosity=2)
