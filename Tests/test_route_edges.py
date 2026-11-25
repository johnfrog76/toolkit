"""Four rules at the edges of the agent's routes, each with its own failure."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent import growth
    from agent.ado import bridge, reporting, sprint
    from agent.app import create_app
    from agent.core import child
except ImportError as e:
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")


class TheGrowthModulesDataIsItsOwn(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(client_dir=None))

    def flag(self, on: bool):
        return mock.patch.object(growth, "load_config", return_value={"features": {"growth": on}})

    def test_the_review_list_is_absent_with_the_module_off(self):
        with self.flag(False):
            self.assertEqual(self.client.get("/api/engagement/all/reviews").status_code, 404)

    def test_it_answers_with_the_module_on(self):
        with self.flag(True), mock.patch.object(reporting, "_count_org_reviews", return_value=(0, [])):
            self.assertEqual(self.client.get("/api/engagement/all/reviews").status_code, 200)

    def test_the_summary_counts_no_reviews_with_the_module_off(self):
        org = {"name": "A Space", "projects": []}
        with (
            self.flag(False),
            mock.patch.object(reporting, "_engagement_org_config", return_value=org),
            mock.patch.object(reporting, "_count_org_reviews", return_value=(7, [])) as counted,
            mock.patch.object(reporting, "_count_archive_items", return_value=0),
            mock.patch.object(reporting, "_read_billing_data", return_value=(None, None, 0)),
            mock.patch.object(reporting, "_count_pr_comments", return_value=0),
        ):
            body = self.client.get("/api/engagement/a/summary").json()
        self.assertEqual(body["stats"]["reviewsGenerated"], 0)
        counted.assert_not_called()


class TheCommandTableWatchesTheHub(unittest.TestCase):
    def test_a_change_to_hub_json_changes_the_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "hub.json"
            with mock.patch.object(bridge._config, "hub_root", return_value=Path(tmp)):
                absent = bridge._map_key_now()
                manifest.write_text('{"spaces": []}', encoding="utf-8")
                written = bridge._map_key_now()
                manifest.write_text('{"spaces": [{"slug": "a", "howIWork": "agents"}]}', encoding="utf-8")
                changed = bridge._map_key_now()
        self.assertNotEqual(absent, written)
        self.assertNotEqual(written, changed)


PARENT = """
    import subprocess, sys, time
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    open(sys.argv[1], "w").write(str(child.pid))
    time.sleep(60)
"""


def alive(pid: int) -> bool:
    if sys.platform == "win32":
        out = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True, check=False
        ).stdout
        return str(pid) in out
    probe = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True, check=False)
    state = probe.stdout.strip()
    return bool(state) and not state.startswith("Z")


class ATimeoutEndsTheWholeTree(unittest.TestCase):
    def test_what_the_child_started_goes_with_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            pid_file = Path(tmp) / "pid.txt"
            started = time.monotonic()
            with self.assertRaises(subprocess.TimeoutExpired):
                child.run_tree([sys.executable, "-c", textwrap.dedent(PARENT), str(pid_file)], 3)
            self.assertLess(time.monotonic() - started, 3 + child.TREE_KILL_SECONDS + 2)
            pid = int(pid_file.read_text(encoding="utf-8"))
            deadline = time.monotonic() + 5
            while alive(pid) and time.monotonic() < deadline:
                time.sleep(0.1)
            self.assertFalse(alive(pid), "the grandchild outlived the timeout")

    def test_a_child_that_finishes_answers_as_subprocess_run_does(self):
        result = child.run_tree([sys.executable, "-c", "print('hi')"], 30, text=True, encoding="utf-8")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "hi"))


class ARepoKeyIsAName(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.hub = Path(self.tmp.name) / "hub"
        self.hub.mkdir()
        (self.hub / "stress-log.json").write_text("{}", encoding="utf-8")
        (self.hub / "stress-log.toolkit.json").write_text("{}", encoding="utf-8")
        patcher = mock.patch.object(sprint, "hub_root", return_value=self.hub)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_every_row(self):
        with mock.patch.object(sprint, "_stress_log_default", return_value=self.hub / "stress-log.json"):
            for repo, name in (
                ("toolkit", "stress-log.toolkit.json"),
                ("absent", "stress-log.json"),
                (None, "stress-log.json"),
                ("", "stress-log.json"),
                ("../x", "stress-log.json"),
                ("..\\x", "stress-log.json"),
                ("a/../../b", "stress-log.json"),
                (".hidden", "stress-log.json"),
            ):
                with self.subTest(repo=repo):
                    self.assertEqual(sprint._stress_log_path(repo).name, name)

    def test_a_route_holds_its_repo_to_a_name_before_it_names_a_file(self):
        for repo, want in (("toolkit", "toolkit"), ("../x", None), ("a/b", None), (".x", None), (None, None)):
            with self.subTest(repo=repo):
                self.assertEqual(sprint._repo_key(repo), want)
        with (
            mock.patch.object(sprint, "_active_space_feature", return_value=True),
            mock.patch.object(sprint, "_stress_log_path", return_value=self.hub / "absent.json") as path,
            mock.patch.object(sprint, "_config_sprint_context", return_value=None) as context,
        ):
            TestClient(create_app(client_dir=None)).get("/api/stress-status?repo=../x")
        path.assert_called_once_with(None)
        self.assertIsNone(context.call_args.args[1])

    def test_a_file_read_stays_in_its_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "hub"
            folder.mkdir()
            for name in ("../outside.json", "a/../../outside.json", str(Path(tmp) / "outside.json"), "."):
                with self.subTest(name=name):
                    self.assertIsNone(sprint._file_in(folder, name))
            self.assertEqual(sprint._file_in(folder, "stress-log.widget.json").name, "stress-log.widget.json")

    def test_a_history_file_is_read_and_a_bad_one_is_no_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(sprint._read_history(folder, "widget"), [])
            path = folder / "stress-history.widget.json"
            path.write_text('[{"date": "2026-01-02"}]', encoding="utf-8")
            self.assertEqual(sprint._read_history(folder, "widget"), [{"date": "2026-01-02"}])
            path.write_text("not json", encoding="utf-8")
            self.assertEqual(sprint._read_history(folder, "widget"), [])

    def test_history_rows_are_objects_of_a_list(self):
        self.assertEqual(sprint._history_rows([{"a": 1}, 2, "x", None]), [{"a": 1}])
        self.assertEqual(sprint._history_rows({"a": 1}), [])

    def test_the_repo_list_is_empty_with_sprint_awareness_off(self):
        client = TestClient(create_app(client_dir=None))
        with mock.patch.object(sprint, "_active_space_feature", return_value=False):
            body = client.get("/api/stress-repos").json()
        self.assertEqual(body, {"repos": [], "defaultRepo": None})

    def test_a_log_that_is_not_an_object_is_a_reason_not_an_error(self):
        client = TestClient(create_app(client_dir=None))
        path = Path(self.tmp.name) / "list.json"
        path.write_text(json.dumps([1, 2]), encoding="utf-8")
        with (
            mock.patch.object(sprint, "_active_space_feature", return_value=True),
            mock.patch.object(sprint, "_stress_log_path", return_value=path),
            mock.patch.object(sprint, "_config_sprint_context", return_value=None),
        ):
            reply = client.get("/api/stress-status")
        self.assertEqual(reply.status_code, 200)
        self.assertIn("not an object", reply.json()["detail"])


TODAY = date(2026, 11, 25)
SPACE = "acme"
STATUS_OFF = {
    "enabled": False,
    "org": SPACE,
    "detail": "sprint awareness is off for this org",
    "generatedAt": None,
    "sourceRepo": None,
    "sprintSource": None,
    "context": None,
    "sprintStress": None,
    "originStress": None,
    "communicationStress": None,
    "teamDynamicsStress": None,
}


class ASprintLogReadsOneWay(unittest.TestCase):
    """The stress log, read by both sprint routes: one reading of every field, no shape a 500,
    and a log that is another Space's or another repository's refused by both in one sentence."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.hub = Path(self.tmp.name) / "hub"
        (self.hub / SPACE).mkdir(parents=True)
        self.space: dict = {"slug": SPACE, "promptsFolder": SPACE}
        self.on = True
        for target, value in (("hub_root", lambda: self.hub), ("_today", lambda: TODAY)):
            patcher = mock.patch.object(sprint, target, side_effect=value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(sprint, "load_config", side_effect=self.config)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.client = TestClient(create_app(client_dir=None), raise_server_exceptions=False)

    def config(self):
        return {"activeSpace": SPACE, "spaces": [self.space], "features": {"sprintAwareness": self.on}}

    def log(self, sprint_block=None, **fields):
        body = {"org": SPACE, "repoKey": "widget", "sprint": {"name": "S1", "daysRemaining": 10}}
        if sprint_block is not None:
            body["sprint"] = sprint_block
        body.update(fields)
        self.write_log(json.dumps(body))

    def write_log(self, text, name="stress-log.json"):
        (self.hub / name).write_bytes(text.encode("utf-8") if isinstance(text, str) else text)

    def history(self, rows, repo="widget"):
        (self.hub / SPACE / f"stress-history.{repo}.json").write_text(json.dumps(rows), encoding="utf-8")

    def status(self, repo="widget"):
        reply = self.client.get("/api/stress-status" + (f"?repo={repo}" if repo else ""))
        self.assertEqual(reply.status_code, 200, reply.text)
        return reply.json()

    def activity(self, repo="widget"):
        reply = self.client.get("/api/stress-sprint-activity" + (f"?repo={repo}" if repo else ""))
        self.assertEqual(reply.status_code, 200, reply.text)
        return reply.json()

    def day_reasons(self, body):
        return [r for dim in ("sprintStress",) for r in body[dim]["reasons"] if "daysRemaining" in r]

    def test_a_number_or_nothing(self):
        for raw, want in (
            (3, 3),
            (2.5, 2.5),
            (-1, -1),
            (0, 0),
            (None, None),
            ("4", None),
            ("soon", None),
            (True, None),
            (False, None),
            (float("nan"), None),
            (float("inf"), None),
            ([1], None),
            ({"a": 1}, None),
        ):
            with self.subTest(raw=raw):
                self.assertEqual(sprint._number(raw), want)

    def test_days_remaining_with_no_date_is_the_stored_number_or_no_countdown(self):
        # (stored daysRemaining, the countdown served, the day reason the score carries)
        for stored, days, reason in (
            ("absent", None, None),
            (None, None, None),
            ("soon", None, None),
            ("4", None, None),
            (True, None, None),
            (-2, 0, "daysRemaining <= 3"),
            (2.5, 2, "daysRemaining <= 3"),
            (4, 4, "daysRemaining <= 5"),
            (10, 10, "daysRemaining > 5"),
        ):
            with self.subTest(stored=stored):
                block = {"name": "S1"}
                if stored != "absent":
                    block["daysRemaining"] = stored
                self.log(block)
                body = self.status()
                self.assertEqual(body["detail"], "ok")
                self.assertEqual(body["context"]["daysRemaining"], days)
                self.assertEqual(self.day_reasons(body), [reason] if reason else [])

    def test_a_nan_in_the_log_is_no_number(self):
        self.write_log('{"org": "acme", "sprint": {"daysRemaining": NaN, "mergeVelocity": Infinity}}')
        body = self.status(repo=None)
        self.assertIsNone(body["context"]["daysRemaining"])
        self.assertEqual(body["context"]["mergeVelocity"], 0)

    def test_days_remaining_is_worked_out_from_an_end_date_at_read_time(self):
        # (the log's endDate, the Space's configured endDate, stored, the countdown served)
        for log_end, space_end, stored, days in (
            ("2026-12-01", None, 10, 6),
            ("2026-11-27", None, 10, 2),
            ("2026-11-25", None, 10, 0),
            ("2026-11-01", None, 10, 0),
            (None, "2026-12-05", 1, 10),
            ("2026-12-01", "2026-12-05", 1, 6),
            ("not a day", "2026-12-05", 1, 10),
            (7, None, 1, 1),
            ("not a day", None, None, None),
        ):
            with self.subTest(log_end=log_end, space_end=space_end):
                block = {"name": "S1", "daysRemaining": stored}
                if log_end is not None:
                    block["endDate"] = log_end
                self.space["sprint"] = {"endDate": space_end} if space_end else {}
                self.log(block)
                body = self.status()
                self.assertEqual(body["context"]["daysRemaining"], days)
                if days is not None and days <= 3:
                    self.assertEqual(body["sprintStress"]["level"], "High")
                    self.assertIn("daysRemaining <= 3", body["sprintStress"]["reasons"])

    def test_every_number_the_score_compares_is_a_number_or_its_default(self):
        defaults = {"mergeVelocity": 0, "upstreamMerges": 0, "surfaceAreaChange": 0, "visibilityScore": 0.5}
        where = {
            "mergeVelocity": "sprint",
            "upstreamMerges": "origin",
            "surfaceAreaChange": "origin",
            "visibilityScore": "communication",
        }
        for field, default in defaults.items():
            for raw, want in ((None, default), ("x", default), (-3, -3), (1.5, 1.5), (True, default)):
                with self.subTest(field=field, raw=raw):
                    block = {"name": "S1", "daysRemaining": 10}
                    parts = {"sprint": block, "origin": {}, "communication": {}}
                    parts[where[field]][field] = raw
                    self.log(parts["sprint"], origin=parts["origin"], communication=parts["communication"])
                    served = self.status()["context"][field]
                    self.assertEqual(served, int(want) if isinstance(default, int) else want)

    def test_no_shape_of_a_block_is_a_500(self):
        for fields in (
            {"sprint": []},
            {"sprint": "S1"},
            {"origin": [1]},
            {"communication": 3},
            {"teamDynamics": "x"},
            {"origin": {"conflictZones": 5}},
            {"origin": {"conflictZones": ["a", 1, None]}},
            {"origin": {"rebasePressure": 4}},
            {"teamDynamics": {"xxlPrAuthors": 2, "silentRefactorers": "ab"}},
            {"generatedAt": 5, "sourceRepo": [], "sprintSource": {}},
        ):
            with self.subTest(fields=fields):
                self.write_log(json.dumps({"org": SPACE, **fields}))
                body = self.status(repo=None)
                self.assertEqual(body["detail"], "ok")
                self.activity(repo=None)
        # a list is counted whatever it holds, as it always was; the card is served its strings
        self.write_log(json.dumps({"org": SPACE, "origin": {"conflictZones": ["a", 1, None]}}))
        body = self.status(repo=None)
        self.assertEqual(body["context"]["conflictZones"], ["a"])
        self.assertIn("conflictZones.length > 0", body["originStress"]["reasons"])
        self.write_log(json.dumps({"org": SPACE, "teamDynamics": {"xxlPrAuthors": [{}], "silentRefactorers": [1]}}))
        self.assertEqual(self.status(repo=None)["teamDynamicsStress"]["level"], "High")

    def test_a_log_that_cannot_be_read_is_a_reason_on_both_routes(self):
        self.history([{"date": "2026-11-20", "sprint": "S9", "mine": 1, "team": 2}])
        for text, reason in (
            (None, "view-only -- no live signal on this machine"),
            ("", "could not read stress-log.json: JSONDecodeError"),
            ("{not json", "could not read stress-log.json: JSONDecodeError"),
            (b"\xff\xfe\x00{", "could not read stress-log.json: UnicodeDecodeError"),
            ("[1, 2]", "could not read stress-log.json: it is not an object"),
            ('"a string"', "could not read stress-log.json: it is not an object"),
            ("7", "could not read stress-log.json: it is not an object"),
            ("null", "could not read stress-log.json: it is not an object"),
        ):
            with self.subTest(text=text):
                log = self.hub / "stress-log.json"
                if text is None:
                    log.unlink(missing_ok=True)
                else:
                    self.write_log(text)
                status = self.status()
                self.assertTrue(status["detail"].startswith(reason), status["detail"])
                self.assertIsNotNone(status["context"])
                activity = self.activity()
                self.assertEqual(activity["detail"], status["detail"])
                self.assertEqual([e["count"] for e in activity["mine"]], [1])

    def test_a_log_that_is_not_this_space_and_repository_is_refused_by_both_in_one_sentence(self):
        self.history([{"date": "2026-11-20", "sprint": "S-widget", "mine": 1, "team": 2}])
        frame = {"name": "S-other", "endDate": "2026-12-09", "daysRemaining": 2}
        for fields, sentence in (
            ({"org": "elsewhere"}, "view-only \u2014 live log on this machine is for 'elsewhere'"),
            ({"org": None}, "view-only \u2014 the live log on this machine names no Space"),
            ({"org": ""}, "view-only \u2014 the live log on this machine names no Space"),
            ({"repoKey": "other"}, "view-only \u2014 live log on this machine is for 'other', not 'widget'"),
            (
                {"repoKey": None, "sourceRepo": "https://example.com/acme/other.git"},
                "view-only \u2014 live log on this machine is for 'other', not 'widget'",
            ),
        ):
            with self.subTest(fields=fields):
                body = {"org": SPACE, "repoKey": "widget", "sprint": frame, **fields}
                self.write_log(json.dumps({k: v for k, v in body.items() if v is not None}))
                status = self.status()
                self.assertEqual(status["detail"], sentence)
                self.assertIsNone(status["sprintStress"])
                activity = self.activity()
                self.assertEqual(activity["detail"], sentence)
                # the log's sprint frame is not used: the window is the history's own
                self.assertEqual((activity["startDate"], activity["endDate"]), ("2026-11-20", "2026-11-20"))
                self.assertEqual([e["count"] for e in activity["mine"]], [1])

    def test_a_log_that_is_this_space_and_repository_frames_the_activity(self):
        self.history([{"date": "2026-11-20", "sprint": "S1", "mine": 1, "team": 2, "mineChurn": "x"}])
        for fields in ({}, {"repoKey": None, "sourceRepo": "https://example.com/acme/widget.git"}):
            with self.subTest(fields=fields):
                body = {"org": SPACE, "repoKey": "widget", "sprint": {"name": "S1", "endDate": "2026-12-01"}}
                body.update(fields)
                self.write_log(json.dumps({k: v for k, v in body.items() if v is not None}))
                self.assertEqual(self.status()["detail"], "ok")
                activity = self.activity()
                self.assertEqual(activity["detail"], "ok")
                self.assertEqual((activity["startDate"], activity["endDate"]), ("2026-11-20", "2026-12-01"))
                self.assertEqual(activity["mine"], [{"date": "2026-11-20", "count": 1, "churn": 0}])

    def test_with_sprint_awareness_off_both_routes_answer_as_before_and_read_nothing(self):
        self.on = False
        self.write_log("{not json")
        with mock.patch.object(sprint, "_stress_log_path") as path:
            self.assertEqual(self.status(), STATUS_OFF)
            self.assertEqual(
                self.activity(), {"startDate": "2026-11-25", "endDate": "2026-11-25", "mine": [], "team": []}
            )
        path.assert_not_called()


if __name__ == "__main__":
    unittest.main()
