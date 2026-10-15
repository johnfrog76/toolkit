"""An empty ledger says why.

``/prs``, ``/work-items``, ``/dashboard`` and ``/dashboard/pipelines/{project}``
read Azure DevOps through ``az``. When the call fails -- a timeout, no ``az`` on
PATH, stderr, output that is not JSON -- the helpers used to log it and return
``[]``, and the card could not tell "nothing assigned to you" from "the call
failed". An org with no ``projects`` was the same empty answer for a third
reason.

Every case here stubs ``subprocess.run`` INSIDE ``accounting.py`` so the
failure is the one under test and a signed-in machine cannot pass a failing
assertion. Identity is fixed by config so that resolver never starts ``az``
either.

Run directly:  python3 Tests/test_accounting_reasons.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.app import app
    from agent.core import env as env_route
    from agent.core import identity, tier
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

ORG = "https://dev.azure.com/example"
EMAIL = "someone@example.com"
PROJECT = {"name": "Demo", "repo": "WebApp", "hasRepo": True}


def _cfg(**over):
    base = {
        "org": ORG,
        "status": "active",
        "activeSpace": "demo",
        "email": EMAIL,
        "branchUser": "",
        "projects": [PROJECT],
        "spaces": [{"slug": "demo", "name": "Demo", "status": "active"}],
    }
    base.update(over)
    return base


def _az_that(*, returncode=0, stdout="", stderr="", raises=None):
    """Stand in for ``subprocess.run`` inside accounting.py: one behaviour for
    every az call, and a record of what was asked."""

    def run(cmd, **kwargs):
        run.calls.append(cmd)
        if raises is not None:
            raise raises
        return mock.Mock(returncode=returncode, stdout=stdout, stderr=stderr)

    run.calls = []
    return run


class _Tier1:
    """Past the tier gate on any machine, with no az and a fixed identity."""

    def __init__(self, cfg, az):
        self._cfg = cfg
        self._az = az

    def __enter__(self):
        self._patches = [
            mock.patch.object(accounting, "load_config", lambda: self._cfg),
            mock.patch.object(env_route, "load_config", lambda: self._cfg),
            mock.patch.object(identity, "load_config", lambda: self._cfg),
            mock.patch.object(tier, "hub_root", lambda: PKG_ROOT),
            mock.patch.object(tier, "shutil", mock.Mock(which=lambda _n: "/usr/bin/git")),
            mock.patch.object(tier, "_probe_ado", lambda _org: True),
            mock.patch.object(accounting.subprocess, "run", self._az),
        ]
        for p in self._patches:
            p.start()
        identity.identity_cache_clear()
        tier.probe_cache_clear()
        return self

    def __exit__(self, *exc):
        for p in self._patches:
            p.stop()
        identity.identity_cache_clear()
        tier.probe_cache_clear()
        return False


class PrsReasons(unittest.TestCase):
    def test_stderr_is_the_reason_and_names_the_target(self):
        az = _az_that(returncode=1, stderr="TF400813: The user is not authorized to access this resource.\nmore")
        with _Tier1(_cfg(), az):
            body = client.get("/api/prs").json()
        self.assertEqual(body["count"], 0)
        self.assertIn("TF400813", body["reason"])
        self.assertIn("Demo/WebApp", body["reason"])
        self.assertIn("repos pr list", body["reason"])
        self.assertNotIn("more", body["reason"], "only the first line of stderr")

    def test_a_missing_az_is_said_in_words(self):
        az = _az_that(raises=FileNotFoundError("az"))
        with _Tier1(_cfg(), az):
            body = client.get("/api/prs").json()
        self.assertIn("az CLI not found", body["reason"])

    def test_a_timeout_is_the_reason(self):
        az = _az_that(raises=subprocess.TimeoutExpired(cmd="az", timeout=30))
        with _Tier1(_cfg(), az):
            body = client.get("/api/prs").json()
        self.assertIn("timed out", body["reason"])
        self.assertIn("Demo/WebApp", body["reason"])

    def test_output_that_is_not_json_is_the_reason(self):
        az = _az_that(stdout="Please run 'az login'")
        with _Tier1(_cfg(), az):
            body = client.get("/api/prs").json()
        self.assertIn("not JSON", body["reason"])

    def test_no_projects_is_the_reason_and_names_the_org(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(projects=[]), az):
            body = client.get("/api/prs").json()
        self.assertEqual(body["count"], 0)
        self.assertIn("No projects configured for demo", body["reason"])
        self.assertIn("hub.json", body["reason"])
        self.assertEqual(az.calls, [], "with no project there is nothing to ask az")

    def test_a_project_with_no_repo_counts_as_no_project(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(projects=[{"name": "Demo"}]), az):
            body = client.get("/api/prs").json()
        self.assertIn("No projects configured", body["reason"])

    def test_the_first_failure_wins_and_the_rest_are_logged(self):
        answers = iter(
            [
                mock.Mock(returncode=1, stdout="", stderr="first failure"),
                mock.Mock(returncode=1, stdout="", stderr="second failure"),
            ]
        )
        az = _az_that()
        az_run = lambda cmd, **kw: next(answers)  # noqa: E731
        with (
            _Tier1(_cfg(), az),
            mock.patch.object(accounting.subprocess, "run", az_run),
            mock.patch.object(accounting.log_writer, "write_log") as log,
        ):
            body = client.get("/api/prs").json()
        self.assertIn("first failure", body["reason"])
        warns = [c.args[2] for c in log.call_args_list if c.args and c.args[0] == "WARN"]
        self.assertEqual(len(warns), 2, warns)

    def test_rows_from_one_project_carry_no_reason_for_anothers_failure(self):
        """A populated list with a warning on it reads as a failure that did not happen."""
        pr = {
            "pullRequestId": 7,
            "title": "x",
            "sourceRefName": "refs/heads/a",
            "targetRefName": "refs/heads/main",
            "creationDate": "2026-09-22T00:00:00Z",
        }

        def run(cmd, **kw):
            if "One" in cmd:
                return mock.Mock(returncode=0, stdout=json.dumps([pr]), stderr="")
            return mock.Mock(returncode=1, stdout="", stderr="boom")

        cfg = _cfg(projects=[{"name": "One", "repo": "R1"}, {"name": "Two", "repo": "R2"}])
        with _Tier1(cfg, run):
            body = client.get("/api/prs?creator_only=1").json()
        self.assertEqual(body["count"], 1)
        self.assertIsNone(body["reason"])

    def test_a_clean_empty_answer_has_no_reason(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(), az):
            body = client.get("/api/prs").json()
        self.assertEqual(body["count"], 0)
        self.assertIsNone(body["reason"], "nothing failed: an empty list is the answer")


class WorkItemsReasons(unittest.TestCase):
    def test_a_failed_query_is_the_reason(self):
        az = _az_that(returncode=1, stderr="ERROR: TF51005: The query references a field that does not exist.")
        with _Tier1(_cfg(), az):
            body = client.get("/api/work-items").json()
        self.assertEqual(body["count"], 0)
        self.assertIn("TF51005", body["reason"])
        self.assertIn("boards query", body["reason"])
        self.assertIn("Demo", body["reason"])

    def test_no_projects_is_the_reason(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(projects=[]), az):
            body = client.get("/api/work-items").json()
        self.assertIn("No projects configured for demo", body["reason"])
        self.assertEqual(az.calls, [])

    def test_a_missing_identity_still_comes_first(self):
        az = _az_that(returncode=1, stderr="boom")
        with _Tier1(_cfg(email=""), az):
            body = client.get("/api/work-items").json()
        self.assertEqual(body["reason"], identity.IDENTITY_MISSING_REASON)

    def test_a_clean_empty_answer_has_no_reason(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(), az):
            body = client.get("/api/work-items").json()
        self.assertIsNone(body["reason"])


class DashboardReasons(unittest.TestCase):
    def test_a_failure_behind_zero_counts_is_the_reason(self):
        az = _az_that(raises=FileNotFoundError("az"))
        with _Tier1(_cfg(), az):
            body = client.get("/api/dashboard").json()
        self.assertEqual(body["tier"], 1)
        self.assertEqual((body["pr_count"], body["work_item_count"]), (0, 0))
        self.assertIn("az CLI not found", body["reason"])

    def test_no_projects_is_the_reason(self):
        az = _az_that(stdout="[]")
        with _Tier1(_cfg(projects=[]), az):
            body = client.get("/api/dashboard").json()
        self.assertIn("No projects configured for demo", body["reason"])
        # Repo health still runs git through the same subprocess; az is not asked.
        self.assertEqual([c for c in az.calls if c[0] == "az"], [])

    def test_pipelines_for_a_project_carry_the_failure(self):
        az = _az_that(returncode=1, stderr="TF400813: not authorized")
        with _Tier1(_cfg(), az):
            body = client.get("/api/dashboard/pipelines/Demo?repo=WebApp").json()
        self.assertEqual(body["runs"], [])
        self.assertIn("TF400813", body["reason"])
        self.assertIn("pipelines runs list", body["reason"])

    def test_pipelines_that_ran_carry_no_reason(self):
        run = {
            "id": 1,
            "definition": {"name": "CI"},
            "result": "succeeded",
            "sourceBranch": "refs/heads/main",
            "finishTime": None,
            "repository": {"name": "WebApp"},
        }
        az = _az_that(stdout=json.dumps([run]))
        with _Tier1(_cfg(), az):
            body = client.get("/api/dashboard/pipelines/Demo?repo=WebApp").json()
        self.assertEqual(len(body["runs"]), 1)
        self.assertIsNone(body["reason"])


class HelperShape(unittest.TestCase):
    """The helpers answer ``(rows, why)`` -- a caller that forgets the second
    half cannot unpack the first."""

    def test_a_warning_line_on_stdout_is_dropped_before_parsing(self):
        az = _az_that(stdout='WARNING: something az wants to say\n[{"id": 1}]')
        with mock.patch.object(accounting.subprocess, "run", az):
            rows, why = accounting._az_wiql(ORG, "Demo", "SELECT [System.Id] FROM WorkItems")
        self.assertEqual(rows, [{"id": 1}])
        self.assertIsNone(why)

    def test_no_output_with_exit_zero_is_a_stated_failure(self):
        az = _az_that(returncode=0, stdout="", stderr="")
        with mock.patch.object(accounting.subprocess, "run", az):
            rows, why = accounting._az_pr_list(ORG, "Demo", "WebApp", "--creator", EMAIL)
        self.assertEqual(rows, [])
        self.assertIn("no output", why)


class GhRepoUnreadable(unittest.TestCase):
    """A repository gh cannot read -- the GitHub demo's before it is seeded,
    or one private to another account -- is one honest sentence, not gh's
    GraphQL line and not an error. Every row is a shape gh actually prints."""

    TABLE = [
        ("GraphQL: Could not resolve to a Repository with the name 'johnfrog76/recipe-box-demo'. (repository)", True),
        ("gh: Not Found (HTTP 404)", True),
        ("HTTP 404: Not Found (https://api.github.com/repos/johnfrog76/recipe-box-demo/actions/runs)", True),
        ("HTTP 401: Bad credentials", False),
        ("", False),
    ]

    def test_the_table(self):
        for line, missing in self.TABLE:
            with self.subTest(line=line):
                said = accounting.gh_repo_reason("johnfrog76/recipe-box-demo", line)
                self.assertTrue(said.startswith("johnfrog76/recipe-box-demo: "), said)
                self.assertEqual(accounting.REPO_UNREADABLE in said, missing, said)
        self.assertIn("gh returned an error", accounting.gh_repo_reason("o/r", ""))

    def test_the_issues_list_says_it_and_answers_200(self):
        gh = mock.Mock(
            return_value=subprocess.CompletedProcess(
                args=[],
                returncode=1,
                stdout="",
                stderr="GraphQL: Could not resolve to a Repository with the name "
                "'johnfrog76/recipe-box-demo'. (repository)\n",
            )
        )
        with mock.patch.object(accounting.subprocess, "run", gh):
            resp = accounting._github_work_items("https://github.com/johnfrog76/recipe-box-demo", [], True)
        self.assertEqual(resp.items, [])
        self.assertEqual(resp.reason, f"johnfrog76/recipe-box-demo: {accounting.REPO_UNREADABLE}")


if __name__ == "__main__":
    unittest.main()
