"""The Milestones card's agent half -- GET /api/milestones.

A GitHub milestone carries its own open and closed counts, a state, an
optional due date and a closed date, in one call per repo. "Reached" is
DERIVED, the way a card's state is: every issue closed and at least one issue.
The rule is pinned as a table; the route's gate (GitHub only, Tier 1 only) is
pinned against the app. No network: gh is stubbed.

Run:  python3 -m pytest Tests/test_milestones.py
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
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.app import app
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

ORG = "https://github.com/johnfrog76/toolkit"


def gh_row(number, title, open_issues, closed_issues, state="open", due_on=None, closed_at=None):
    return {
        "number": number,
        "title": title,
        "state": state,
        "open_issues": open_issues,
        "closed_issues": closed_issues,
        "due_on": due_on,
        "closed_at": closed_at,
        "html_url": f"https://github.com/johnfrog76/toolkit/milestone/{number}",
    }


class TheReachedRule(unittest.TestCase):
    """Every shape the rule distinguishes, one row each."""

    # (why, open, closed, GitHub's state, reached)
    ROWS = [
        ("0 of 0 -- an empty milestone has reached nothing", 0, 0, "open", False),
        ("0 of 0, closed on GitHub -- still nothing reached", 0, 0, "closed", False),
        ("0 of n -- nothing closed yet", 3, 0, "open", False),
        ("n of n, open on GitHub -- reached, not closed", 0, 7, "open", True),
        ("n of n, closed on GitHub -- reached and closed", 0, 4, "closed", True),
        ("mixed -- in flight", 2, 3, "open", False),
        ("mixed, closed on GitHub with an issue reopened -- not reached", 1, 5, "closed", False),
    ]

    def test_the_table(self):
        for why, n_open, n_closed, _state, want in self.ROWS:
            self.assertEqual(accounting.milestone_reached(n_open, n_closed), want, why)

    def test_the_mapping_carries_the_rule_whatever_github_says(self):
        rows = [gh_row(i + 1, why, o, c, state=s) for i, (why, o, c, s, _w) in enumerate(self.ROWS)]

        def fake_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(rows), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_milestones(ORG, [])
        self.assertEqual([m.reached for m in resp.milestones], [w for *_x, w in self.ROWS])


class TheRead(unittest.TestCase):
    def test_one_gh_api_call_per_repo_state_all(self):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout="[]", stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_milestones(ORG, [])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:2], ["gh", "api"])
        self.assertEqual(calls[0][2:5], ["--method", "GET", "repos/johnfrog76/toolkit/milestones"])
        self.assertIn("state=all", calls[0])
        self.assertIn("per_page=100", calls[0])
        # No argument may carry a cmd.exe metacharacter: on Windows gh runs through
        # the shell and `?state=all&per_page=100` became two commands.
        self.assertTrue(all(not any(ch in a for ch in "&|<>") for a in calls[0]), calls[0])
        self.assertEqual(resp.milestones, [])
        self.assertIsNone(resp.reason)  # an empty list is a fine answer

    def test_the_fields(self):
        rows = [
            gh_row(6, "Phase 8: the rename", 0, 1),
            gh_row(9, "Shipped", 0, 2, state="closed", due_on="2026-09-01T07:00:00Z", closed_at="2026-09-03T10:00:00Z"),
        ]

        def fake_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(rows), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fake_run):
            resp = accounting._github_milestones(ORG, [])
        first, second = resp.milestones
        self.assertEqual((first.title, first.number, first.repo), ("Phase 8: the rename", 6, "toolkit"))
        self.assertEqual((first.open, first.closed, first.state), (0, 1, "open"))
        self.assertEqual((first.due, first.closed_at), ("", ""))
        self.assertEqual(first.url, "https://github.com/johnfrog76/toolkit/milestone/6")
        self.assertEqual((second.state, second.due, second.closed_at), ("closed", "2026-09-01", "2026-09-03"))

    def test_gh_not_answering_is_a_reason(self):
        def fail_run(argv, **_kw):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not logged in")

        with mock.patch.object(accounting.subprocess, "run", side_effect=fail_run):
            resp = accounting._github_milestones(ORG, [])
        self.assertEqual(resp.milestones, [])
        self.assertIn("Not logged in", resp.reason)

    def test_an_owner_grained_address_names_no_repository(self):
        resp = accounting._github_milestones("https://github.com/johnfrog76", [])
        self.assertIn("names no repository", resp.reason)


class TheGate(unittest.TestCase):
    """GitHub only, Tier 1 only -- elsewhere the answer is supported: false and gh is never asked."""

    def setUp(self):
        self.client = TestClient(app)

    def _get(self, org: str, tier: int = 1):
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps([gh_row(1, "M", 0, 1)]), stderr="")

        with (
            mock.patch.object(accounting, "load_config", return_value={"org": org, "status": "active"}),
            mock.patch.object(accounting, "_resolve_tier", return_value=(tier, "")),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
        ):
            return self.client.get("/api/milestones").json(), calls

    def test_a_github_space_at_tier_1_reads(self):
        body, calls = self._get(ORG)
        self.assertTrue(body["supported"])
        self.assertEqual(body["milestones"][0]["reached"], True)
        self.assertEqual(len(calls), 1)

    def test_an_ado_space_no_tracker_or_tier_2_is_not_supported(self):
        for org, tier in (("https://dev.azure.com/acme", 1), ("", 1), (ORG, 2)):
            body, calls = self._get(org, tier)
            self.assertFalse(body["supported"], org)
            self.assertEqual(body["milestones"], [])
            self.assertEqual(calls, [], org)


if __name__ == "__main__":
    unittest.main()


class GhArgumentsAreShellSafe(unittest.TestCase):
    """_gh_json refuses an argument cmd.exe would split, before running anything."""

    def test_an_ampersand_in_a_url_is_refused_without_running(self):
        with mock.patch.object(accounting.subprocess, "run") as run:
            data, why = accounting._gh_json(["gh", "api", "repos/o/r/milestones?state=all&per_page=100"])
        run.assert_not_called()
        self.assertIsNone(data)
        self.assertIn("cmd.exe", why)

    def test_flags_pass(self):
        self.assertIsNone(
            accounting.unsafe_for_shell(["gh", "api", "--method", "GET", "repos/o/r/milestones", "-f", "state=all"])
        )
