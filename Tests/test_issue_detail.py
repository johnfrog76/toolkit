"""The reading room's agent half -- /issue/{number} on a GitHub space.

One route: ``gh issue view --json`` for the body, the meta and the thread,
then the timeline API for the high signal -- commits, the linked PR,
cross-references. "List and details" was the walk's verdict; an earlier change built the
list, this reads one issue. No network: subprocess is stubbed, and the
assertions are about ARGV and the mapping.

Run:  python3 -m pytest Tests/test_issue_detail.py
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.ado import accounting
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

ORG = "https://github.com/johnfrog76/toolkit"

VIEW = {
    "number": 60,
    "title": "Feature: issue details in the GUI",
    "state": "OPEN",
    "body": "The body, **markdown**.",
    "author": {"login": "johnfrog76"},
    "createdAt": "2026-09-27T10:00:00Z",
    "closedAt": None,
    "url": "https://github.com/johnfrog76/toolkit/issues/60",
    "labels": [{"name": "enhancement"}, {"name": "sev2"}],
    "milestone": {"title": "Milestone P"},
    "assignees": [{"login": "johnfrog76"}],
    "comments": [
        {"author": {"login": "johnfrog76"}, "createdAt": "2026-09-27T11:00:00Z", "body": "First."},
        {"author": {"login": "opus"}, "createdAt": "2026-09-27T12:00:00Z", "body": "Second."},
    ],
}

TIMELINE = [
    {
        "event": "referenced",
        "commit_id": "abc1234def",
        "created_at": "2026-09-27T13:00:00Z",
        "commit_url": "https://api.github.com/repos/johnfrog76/toolkit/commits/abc1234def",
    },
    {
        "event": "cross-referenced",
        "created_at": "2026-09-27T14:00:00Z",
        "source": {
            "issue": {
                "number": 58,
                "title": "The backlog PR",
                "html_url": "https://github.com/johnfrog76/toolkit/pull/58",
                "pull_request": {},
            }
        },
    },
    {
        "event": "cross-referenced",
        "created_at": "2026-09-27T15:00:00Z",
        "source": {
            "issue": {
                "number": 62,
                "title": "The umbrella",
                "html_url": "https://github.com/johnfrog76/toolkit/issues/62",
            }
        },
    },
    {"event": "labeled", "created_at": "2026-09-27T16:00:00Z"},
]


class TheReadingRoom(unittest.TestCase):
    def _run(self, short=""):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            out = json.dumps(VIEW) if argv[1] == "issue" else json.dumps(TIMELINE)
            return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            detail = accounting._github_issue_detail(ORG, [], 60, short)
        return detail, calls

    def test_the_two_reads_and_their_argv(self):
        _, calls = self._run()
        self.assertEqual(calls[0][:5], ["gh", "issue", "view", "60", "--repo"])
        self.assertIn("johnfrog76/toolkit", calls[0])
        self.assertEqual(calls[1][:2], ["gh", "api"])
        self.assertIn("repos/johnfrog76/toolkit/issues/60/timeline?per_page=100", calls[1])

    def test_the_mapping(self):
        d, _ = self._run()
        self.assertEqual(d.number, 60)
        self.assertEqual(d.state, "open")
        self.assertEqual(d.body, "The body, **markdown**.")
        self.assertEqual(d.author, "johnfrog76")
        self.assertEqual(d.created, "2026-09-27")
        self.assertEqual(d.labels, ["enhancement", "sev2"])
        self.assertEqual(d.kind, "Feature")
        self.assertEqual(d.milestone, "Milestone P")
        self.assertEqual(d.assignee, "johnfrog76")
        self.assertEqual(d.repo, "toolkit")
        self.assertEqual([c.author for c in d.comments], ["johnfrog76", "opus"])
        self.assertEqual(d.comments[0].when, "2026-09-27")

    def test_the_timeline_keeps_the_high_signal_only(self):
        d, _ = self._run()
        self.assertEqual([t.kind for t in d.timeline], ["commit", "pr", "xref"])
        commit = d.timeline[0]
        self.assertEqual(commit.text, "abc1234")
        self.assertEqual(commit.url, "https://github.com/johnfrog76/toolkit/commit/abc1234def")
        self.assertEqual(d.timeline[1].text, "#58 The backlog PR")
        self.assertEqual(d.timeline[2].text, "#62 The umbrella")

    def test_a_failed_view_states_the_repo_and_the_reason(self):
        def fake_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="boom\nmore")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            d = accounting._github_issue_detail(ORG, [], 60, "")
        self.assertIn("johnfrog76/toolkit", d.reason)
        self.assertIn("boom", d.reason)

    def test_a_failed_timeline_says_nothing(self):
        def fake_run(argv, **_kw):
            if argv[1] == "issue":
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(VIEW), stderr="")
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="rate limited")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            d = accounting._github_issue_detail(ORG, [], 60, "")
        self.assertIsNone(d.reason)
        self.assertEqual(d.timeline, [])
        self.assertEqual(d.number, 60)

    def test_no_repo_is_a_stated_reason(self):
        d = accounting._github_issue_detail("https://github.com/johnfrog76", [], 60, "")
        self.assertIn("names no repository", d.reason)


if __name__ == "__main__":
    unittest.main()


DEPLOY_ROWS = [
    {
        "displayTitle": "fix: the strip",
        "workflowName": "CI",
        "status": "completed",
        "conclusion": "success",
        "headBranch": "main",
        "updatedAt": "2026-09-27T18:00:00Z",
        "url": "https://github.com/johnfrog76/toolkit/actions/runs/2",
    },
    {
        "displayTitle": "older",
        "workflowName": "",
        "status": "completed",
        "conclusion": "failure",
        "headBranch": "main",
        "updatedAt": "2026-09-26T18:00:00Z",
        "url": "https://github.com/johnfrog76/toolkit/actions/runs/1",
    },
]


class TheDeploysFace(unittest.TestCase):
    def test_argv_mapping_and_order(self):
        calls = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(DEPLOY_ROWS), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_deploys(ORG, [])
        self.assertEqual(calls[0][:4], ["gh", "run", "list", "--repo"])
        self.assertIn("johnfrog76/toolkit", calls[0])
        self.assertEqual([r.title for r in resp.runs], ["CI", "older"])
        self.assertEqual(resp.runs[0].conclusion, "success")
        self.assertEqual(resp.runs[0].when, "2026-09-27")
        self.assertEqual(resp.runs[0].repo, "toolkit")
        self.assertIsNone(resp.reason)

    def test_a_failure_states_itself(self):
        def fake_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="no workflows")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_deploys(ORG, [])
        self.assertIn("no workflows", resp.reason)
        self.assertEqual(resp.runs, [])
