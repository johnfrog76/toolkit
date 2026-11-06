"""Four rules at the edges of the agent's routes, each with its own failure."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
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


if __name__ == "__main__":
    unittest.main()
