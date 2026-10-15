"""The backlog view's agent half -- /work-items dispatched to gh.

One route, the tracker seam's rule: on a GitHub space the work-items read
runs ``gh issue list`` per repo -- assigned-to-me by default, ``?all=1`` for
the unassigned many, which is the backlog view's whole point. No network:
subprocess is stubbed, and the assertions are about ARGV and the mapping.

Run:  python3 -m pytest Tests/test_backlog_github.py
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
    from agent.core.config import tracker_repos
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

ORG = "https://github.com/johnfrog76/toolkit"

GH_ROWS = [
    {
        "number": 55,
        "title": "Feature: the backlog view",
        "labels": [{"name": "enhancement"}],
        "assignees": [],
        "milestone": {"title": "Next three: GitHub tracker"},
        "updatedAt": "2026-09-27T05:00:00Z",
        "url": "https://github.com/johnfrog76/toolkit/issues/55",
    },
    {
        "number": 56,
        "title": "Improve: a tracker verb names its space",
        "labels": [{"name": "bug"}],
        "assignees": [{"login": "johnfrog76"}],
        "milestone": None,
        "updatedAt": "2026-09-27T06:00:00Z",
        "url": "https://github.com/johnfrog76/toolkit/issues/56",
    },
    {
        "number": 9,
        "title": "No labels at all",
        "labels": [],
        "assignees": [],
        "milestone": None,
        "updatedAt": "2026-09-26T00:00:00Z",
        "url": "https://github.com/johnfrog76/toolkit/issues/9",
    },
]


class TheGithubPath(unittest.TestCase):
    def _run(self, all_items: bool):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(GH_ROWS), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_work_items(ORG, [], all_items)
        return resp, calls

    def test_a_repo_grained_address_needs_no_projects(self):
        self.assertEqual(tracker_repos(ORG, []), ["johnfrog76/toolkit"])

    def test_mine_by_default_all_on_request(self):
        _, calls = self._run(all_items=False)
        self.assertIn("--assignee", calls[0])
        self.assertIn("@me", calls[0])
        _, calls = self._run(all_items=True)
        self.assertNotIn("--assignee", calls[0])

    def test_the_mapping_speaks_the_house_words(self):
        resp, _ = self._run(all_items=True)
        by_id = {i.id: i for i in resp.items}
        self.assertEqual(by_id[55].type, "Feature")  # enhancement folds
        self.assertEqual(by_id[56].type, "Bug")
        self.assertEqual(by_id[9].type, "Issue")  # no label, no guess
        self.assertEqual(by_id[55].sprint, "Next three: GitHub tracker")
        self.assertEqual(by_id[56].assignee, "johnfrog76")
        self.assertEqual(by_id[55].project, "toolkit")
        self.assertEqual(by_id[56].updated, "2026-09-27")
        self.assertEqual(by_id[56].labels, ["bug"])
        # newest first, the worklist's own order
        self.assertEqual([i.id for i in resp.items][:2], [56, 55])

    def test_gh_not_answering_degrades_to_a_reason(self):
        def fail_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not logged in")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fail_run):
            resp = accounting._github_work_items(ORG, [], True)
        self.assertEqual(resp.count, 0)
        self.assertIn("Not logged in", resp.reason)


# The STATE axis and the WORKER chip. Closed rows wear their state and
# sort after open ones; the worker is the label whose description routes it.
LEDGER_ROWS = [
    {
        "number": 70,
        "title": "closed long ago",
        "state": "CLOSED",
        "labels": [],
        "assignees": [],
        "milestone": None,
        "updatedAt": "2026-09-29T00:00:00Z",
        "closedAt": "2026-09-01T00:00:00Z",
        "url": "u70",
    },
    {
        "number": 71,
        "title": "closed lately",
        "state": "CLOSED",
        "labels": [{"name": "sonnet", "description": "Routed to Sonnet -- well-scoped"}],
        "assignees": [],
        "milestone": None,
        "updatedAt": "2026-09-20T00:00:00Z",
        "closedAt": "2026-09-28T00:00:00Z",
        "url": "u71",
    },
    {
        "number": 72,
        "title": "open, old update",
        "state": "OPEN",
        "labels": [
            {"name": "sev2", "description": "Severity 2"},
            {"name": "opus", "description": "Routed to Opus -- the crash-through volume"},
        ],
        "assignees": [],
        "milestone": None,
        "updatedAt": "2026-09-02T00:00:00Z",
        "closedAt": None,
        "url": "u72",
    },
    {
        "number": 73,
        "title": "open, a label that routes to a fourth worker",
        "state": "OPEN",
        "labels": [{"name": "haiku", "description": "Routed to Haiku -- quick ones"}],
        "assignees": [],
        "milestone": None,
        "updatedAt": "2026-09-03T00:00:00Z",
        "closedAt": None,
        "url": "u73",
    },
]


class TheLedgerStateAxis(unittest.TestCase):
    def _run(self, state: str | None, rows=LEDGER_ROWS):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(rows), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            if state is None:
                resp = accounting._github_work_items(ORG, [], True)
            else:
                resp = accounting._github_work_items(ORG, [], True, state)
        return resp, calls

    def _state_of(self, argv: list[str]) -> str:
        return argv[argv.index("--state") + 1]

    def test_open_is_the_default(self):
        _, calls = self._run(None)
        self.assertEqual(self._state_of(calls[0]), "open")

    def test_each_state_passes_through_and_nothing_else_does(self):
        for state, argv_state in [
            ("open", "open"),
            ("closed", "closed"),
            ("all", "all"),
            ("bogus", "open"),
            ("", "open"),
        ]:
            _, calls = self._run(state)
            self.assertEqual(self._state_of(calls[0]), argv_state, state)

    def test_closed_rows_wear_their_state_and_sort_after_open_ones(self):
        resp, _ = self._run("all")
        self.assertEqual([i.id for i in resp.items], [73, 72, 71, 70])
        by_id = {i.id: i for i in resp.items}
        self.assertEqual(by_id[71].state, "closed")
        self.assertEqual(by_id[71].closed, "2026-09-28")
        self.assertEqual(by_id[72].state, "open")
        self.assertEqual(by_id[72].closed, "")

    def test_the_worker_is_read_from_the_labels_description(self):
        resp, _ = self._run("all")
        by_id = {i.id: i for i in resp.items}
        self.assertEqual(by_id[72].worker, "opus")  # sev2 first, not a worker
        self.assertEqual(by_id[71].worker, "sonnet")
        self.assertEqual(by_id[73].worker, "haiku")  # a fourth is a label away
        self.assertEqual(by_id[70].worker, "")
        self.assertEqual(by_id[72].labels, ["sev2", "opus"])

    def test_a_row_without_state_reads_open(self):
        resp, _ = self._run("open", rows=GH_ROWS)
        self.assertTrue(all(i.state == "open" for i in resp.items))


REPORT_ROWS = [
    {
        "state": "OPEN",
        "labels": [{"name": "bug"}, {"name": "sev1"}],
        "milestone": {"title": "Next three: GitHub tracker"},
        "closedAt": None,
    },
    {"state": "OPEN", "labels": [{"name": "enhancement"}], "milestone": None, "closedAt": None},
    {
        "state": "OPEN",
        "labels": [{"name": "sev2"}],
        "milestone": {"title": "Next three: GitHub tracker"},
        "closedAt": None,
    },
    {"state": "CLOSED", "labels": [{"name": "bug"}], "milestone": None, "closedAt": "2099-01-01T00:00:00Z"},
    {"state": "CLOSED", "labels": [], "milestone": None, "closedAt": "2000-01-01T00:00:00Z"},
]


class TheReport(unittest.TestCase):
    def test_counts_speak_githubs_own_words(self):
        def fake_run(argv, **_kw):
            self.assertEqual(argv[:3], ["gh", "issue", "list"])
            self.assertIn("--state", argv)
            self.assertIn("all", argv)
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(REPORT_ROWS), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            rep = accounting._github_issue_report(ORG, [])
        self.assertEqual((rep.open, rep.closed), (3, 2))
        self.assertEqual(rep.closed_recent, 1)  # 2099 counts, 2000 does not
        self.assertEqual(rep.sev, {"sev1": 1, "sev2": 1})
        self.assertEqual(rep.kind, {"bug": 1, "feat": 1})
        self.assertEqual(rep.milestones[0].title, "Next three: GitHub tracker")
        self.assertEqual(rep.milestones[0].open, 2)


class ThePin(unittest.TestCase):
    """#100 -- GitHub's own pin, read from ``isPinned`` on the row; no second store."""

    ROWS = [
        {
            "number": 1,
            "title": "pinned, open",
            "state": "OPEN",
            "labels": [],
            "assignees": [],
            "milestone": None,
            "updatedAt": "2026-09-01T00:00:00Z",
            "closedAt": None,
            "url": "u1",
            "isPinned": True,
        },
        {
            "number": 2,
            "title": "not pinned",
            "state": "OPEN",
            "labels": [],
            "assignees": [],
            "milestone": None,
            "updatedAt": "2026-09-02T00:00:00Z",
            "closedAt": None,
            "url": "u2",
            "isPinned": False,
        },
        {
            "number": 3,
            "title": "pinned, closed",
            "state": "CLOSED",
            "labels": [],
            "assignees": [],
            "milestone": None,
            "updatedAt": "2026-09-03T00:00:00Z",
            "closedAt": "2026-09-03T00:00:00Z",
            "url": "u3",
            "isPinned": True,
        },
        {
            "number": 4,
            "title": "a row that does not say",
            "state": "OPEN",
            "labels": [],
            "assignees": [],
            "milestone": None,
            "updatedAt": "2026-09-04T00:00:00Z",
            "closedAt": None,
            "url": "u4",
        },
    ]

    def test_pinned_is_read_from_is_pinned_and_asked_for(self):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(self.ROWS), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_work_items(ORG, [], True, "all")
        self.assertIn("isPinned", calls[0][calls[0].index("--json") + 1])
        self.assertEqual({i.id: i.pinned for i in resp.items}, {1: True, 2: False, 3: True, 4: False})

    def test_the_reading_room_says_it_too(self):
        row = {
            "number": 5,
            "title": "t",
            "state": "OPEN",
            "body": "",
            "author": {"login": "a"},
            "createdAt": "2026-09-01T00:00:00Z",
            "closedAt": None,
            "url": "u",
            "labels": [],
            "milestone": None,
            "assignees": [],
            "comments": [],
            "isPinned": True,
        }

        def fake_run(argv, **_kw):
            out = json.dumps(row) if argv[:3] == ["gh", "issue", "view"] else "[]"
            return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            detail = accounting._github_issue_detail(ORG, [], 5, "")
        self.assertTrue(detail.pinned)
