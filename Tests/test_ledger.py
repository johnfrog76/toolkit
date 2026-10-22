"""The Spaces card's ledger (docs/modules/studio.md, "The routes").

Every GitHub Space's row facts in ONE read: one aliased ``gh api graphql`` call
for every repository (issue counts, open issues' labels and milestones, recently
closed issues, visibility), one ``gh run list`` per repository in parallel, all
kept on disk per Space for the visibility cache's 600 s. What is pinned here:

- the GraphQL call count does not grow with the number of Spaces (one per
  ``LEDGER_CHUNK`` repositories), and no tier probe is made on the way;
- a second read inside the TTL -- a second mount, or an agent restart -- makes
  no gh call at all; Refresh, an expired entry or a changed address does;
- a Space whose read did not fully answer is not kept;
- the report counts what ``accounting._github_issue_report`` counts, from the
  same issues;
- no argv carries a character cmd.exe would split (the Windows ``&`` trap).

No network: ``subprocess.run`` is stubbed and answers like gh.

Run:  python3 -m pytest Tests/test_ledger.py
"""

import json
import re
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.app import app
    from agent.core import disk_cache
    from agent.core.consts import studio_ledger_route
    from agent.studio import ledger
except Exception as exc:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(exc).__name__}: {exc})")

NOW = datetime.now(UTC)
THIS_WEEK = (NOW - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
LONG_AGO = "2000-01-01T00:00:00Z"

# One backlog, every shape the report distinguishes: severities, a kind from
# either label, an issue with BOTH kind labels (the first one counts), two
# milestones that tie (the newest-created first keeps its place), closed this
# week and long ago, and an open issue with nothing on it.
ISSUES = [
    {"state": "OPEN", "labels": ["bug", "sev1"], "milestone": "M2", "closedAt": None},
    {"state": "OPEN", "labels": ["enhancement"], "milestone": "M1", "closedAt": None},
    {"state": "OPEN", "labels": ["sev2", "enhancement", "bug"], "milestone": "M1", "closedAt": None},
    {"state": "OPEN", "labels": ["sev1"], "milestone": "M2", "closedAt": None},
    {"state": "OPEN", "labels": [], "milestone": None, "closedAt": None},
    {"state": "CLOSED", "labels": ["bug"], "milestone": "M1", "closedAt": THIS_WEEK},
    {"state": "CLOSED", "labels": [], "milestone": None, "closedAt": LONG_AGO},
]


def gh_issue_list_rows(issues):
    """The rows ``gh issue list --json state,labels,milestone,closedAt`` gives."""
    return [
        {
            "state": i["state"],
            "labels": [{"name": n} for n in i["labels"]],
            "milestone": {"title": i["milestone"]} if i["milestone"] else None,
            "closedAt": i["closedAt"],
        }
        for i in issues
    ]


def repo_node(issues, visibility="PUBLIC", open_total=None, has_next=False):
    """One alias's answer to the ledger query, from the same issues."""
    opened = [i for i in issues if i["state"] == "OPEN"]
    closed = [i for i in issues if i["state"] == "CLOSED"]
    return {
        "visibility": visibility,
        "open": {"totalCount": len(opened) if open_total is None else open_total},
        "closed": {"totalCount": len(closed)},
        "openRows": {
            "pageInfo": {"hasNextPage": has_next, "endCursor": "CUR1" if has_next else None},
            "nodes": [
                {
                    "labels": {"nodes": [{"name": n} for n in i["labels"]]},
                    "milestone": {"title": i["milestone"]} if i["milestone"] else None,
                }
                for i in opened
            ],
        },
        "recentRows": {
            "pageInfo": {"hasNextPage": False, "endCursor": None},
            "nodes": [{"closedAt": i["closedAt"], "updatedAt": i["closedAt"]} for i in closed],
        },
    }


RUNS = [
    {
        "displayTitle": "ci",
        "workflowName": "CI",
        "status": "completed",
        "conclusion": "success",
        "headBranch": "main",
        "updatedAt": "2026-10-20T10:00:00Z",
        "url": "u",
    }
]


def space(slug, repo=None, status="active", org=None):
    return {"slug": slug, "org": org or f"https://github.com/johnfrog76/{repo or slug}", "status": status}


class FakeGh:
    """``subprocess.run`` as gh answers it. ``nodes`` holds each repository's
    alias answer (a missing one is NOT_FOUND); ``down`` makes every call fail
    the way a signed-out gh does."""

    def __init__(self, nodes=None, down=False, page=None):
        self.nodes = nodes or {}
        self.down = down
        self.page = page
        self.calls: list[list[str]] = []
        self.queries: list[str] = []

    def kinds(self):
        return [" ".join(c[1:3]) for c in self.calls]

    def __call__(self, argv, **_kw):
        argv = list(argv)
        self.calls.append(argv)
        if self.down:
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: To get started, run gh auth login")
        if argv[:3] == ["gh", "run", "list"]:
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(RUNS), stderr="")
        if argv[:3] == ["gh", "api", "graphql"]:
            qfile = next(a.split("@", 1)[1] for a in argv if a.startswith("query=@"))
            query = Path(qfile).read_text(encoding="utf-8")
            self.queries.append(query)
            fields = dict(a.split("=", 1) for a in argv[argv.index("graphql") + 1 :] if "=" in a)
            if "page:" in query:
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(self.page), stderr="")
            data, errors = {}, []
            for key in sorted(k for k in fields if re.fullmatch(r"o\d+", k)):
                i = key[1:]
                repo = f"{fields[key]}/{fields['n' + i]}"
                if repo in self.nodes:
                    data[f"r{i}"] = self.nodes[repo]
                else:
                    data[f"r{i}"] = None
                    errors.append(
                        {
                            "type": "NOT_FOUND",
                            "path": [f"r{i}"],
                            "message": f"Could not resolve to a Repository with the name '{repo}'.",
                        }
                    )
            out = {"data": data, **({"errors": errors} if errors else {})}
            return subprocess.CompletedProcess(argv, 1 if errors else 0, stdout=json.dumps(out), stderr="")
        return subprocess.CompletedProcess(argv, 0, stdout="johnfrog76", stderr="")


class LedgerCase(unittest.TestCase):
    def setUp(self):
        self.hub = tempfile.mkdtemp()
        accounting.visibility_cache_clear()
        patches = [
            mock.patch.object(ledger, "hub_root", return_value=Path(self.hub)),
            mock.patch.object(ledger.shutil, "which", return_value="/usr/bin/git"),
            mock.patch.object(ledger.log_writer, "write_log"),
            mock.patch.object(accounting.log_writer, "write_log"),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def read(self, cfg, gh, refresh=False, tier=1):
        with (
            mock.patch.object(accounting.subprocess, "run", side_effect=gh),
            mock.patch.object(accounting, "_resolve_tier", return_value=(tier, tier == 1)) as probe,
        ):
            out = ledger.read_ledger(cfg, refresh=refresh)
        self.probe = probe
        return out

    @staticmethod
    def cfg(*spaces):
        return {"spaces": list(spaces)}


class TheCallCount(LedgerCase):
    def test_one_graphql_call_whatever_the_number_of_spaces(self):
        for n in (1, 3, 8):
            with self.subTest(spaces=n):
                spaces = [space(f"p{i}") for i in range(n)]
                gh = FakeGh({f"johnfrog76/p{i}": repo_node(ISSUES) for i in range(n)})
                out = self.read(self.cfg(*spaces), gh, refresh=True)
                self.assertEqual(gh.kinds().count("api graphql"), 1)
                self.assertEqual(gh.kinds().count("run list"), n)
                self.assertEqual(len(gh.calls), n + 1)
                self.assertEqual(set(out.spaces), {f"p{i}" for i in range(n)})

    def test_past_the_chunk_one_more_call_per_chunk(self):
        n = ledger.LEDGER_CHUNK + 5
        spaces = [space(f"p{i}") for i in range(n)]
        gh = FakeGh({f"johnfrog76/p{i}": repo_node(ISSUES) for i in range(n)})
        out = self.read(self.cfg(*spaces), gh)
        self.assertEqual(gh.kinds().count("api graphql"), 2)
        self.assertEqual(out.spaces["p24"].report.open, 5)

    def test_no_tier_probe_is_made_when_the_call_answers(self):
        gh = FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)})
        self.read(self.cfg(space("toolkit")), gh)
        self.probe.assert_not_called()
        self.assertNotIn("api users/johnfrog76", gh.kinds())

    def test_two_spaces_on_one_repository_ask_it_once(self):
        gh = FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)})
        out = self.read(self.cfg(space("a", "toolkit"), space("b", "toolkit")), gh)
        self.assertEqual(len(gh.queries), 1)
        self.assertEqual(gh.queries[0].count("repository("), 1)
        self.assertEqual(out.spaces["a"].report, out.spaces["b"].report)

    def test_a_backlog_past_a_page_reads_its_next_page_and_counts_it(self):
        extra = [{"state": "OPEN", "labels": ["sev1"], "milestone": None, "closedAt": None}]
        page = {
            "data": {
                "repository": {
                    "page": {
                        "pageInfo": {"hasNextPage": False, "endCursor": None},
                        "nodes": [{"labels": {"nodes": [{"name": "sev1"}]}, "milestone": None}],
                    }
                }
            }
        }
        gh = FakeGh({"johnfrog76/big": repo_node(ISSUES, open_total=6, has_next=True)}, page=page)
        out = self.read(self.cfg(space("big")), gh)
        self.assertEqual(gh.kinds().count("api graphql"), 2)
        page_argv = gh.calls[[i for i, k in enumerate(gh.kinds()) if k == "api graphql"][1]]
        self.assertIn("after=CUR1", page_argv)
        self.assertEqual(out.spaces["big"].report.sev["sev1"], 2 + len(extra))


class TheDiskCache(LedgerCase):
    def setUp(self):
        super().setUp()
        self.spaces = self.cfg(space("toolkit"), space("deck", "connected-deck"))
        self.nodes = {"johnfrog76/toolkit": repo_node(ISSUES), "johnfrog76/connected-deck": repo_node([])}

    def test_a_second_read_inside_the_ttl_asks_nothing(self):
        first = self.read(self.spaces, FakeGh(self.nodes))
        gh = FakeGh(self.nodes)
        second = self.read(self.spaces, gh)
        self.assertEqual(gh.calls, [])
        self.assertEqual(second, first)

    def test_an_agent_restart_reads_the_disk(self):
        self.read(self.spaces, FakeGh(self.nodes))
        accounting.visibility_cache_clear()  # nothing held in memory survives a restart
        gh = FakeGh(self.nodes)
        out = self.read(self.spaces, gh)
        self.assertEqual(gh.calls, [])
        self.assertEqual(out.spaces["toolkit"].report.open, 5)
        self.assertTrue(disk_cache.get_json(ledger.LEDGER_DIR, "toolkit.json"))

    def test_refresh_asks_again(self):
        self.read(self.spaces, FakeGh(self.nodes))
        gh = FakeGh(self.nodes)
        self.read(self.spaces, gh, refresh=True)
        self.assertEqual(gh.kinds().count("api graphql"), 1)

    def test_past_the_ttl_asks_again(self):
        self.read(self.spaces, FakeGh(self.nodes))
        gh = FakeGh(self.nodes)
        later = time.time() + ledger.LEDGER_TTL_SECONDS + 1
        with mock.patch.object(ledger.time, "time", return_value=later):
            self.read(self.spaces, gh)
        self.assertEqual(gh.kinds().count("api graphql"), 1)

    def test_the_ttl_is_the_visibility_caches(self):
        self.assertEqual(ledger.LEDGER_TTL_SECONDS, accounting.VISIBILITY_TTL_SECONDS)
        self.assertGreaterEqual(ledger.LEDGER_TTL_SECONDS, 600)

    def test_only_the_space_that_changed_is_read_again(self):
        self.read(self.spaces, FakeGh(self.nodes))
        moved = self.cfg(space("toolkit"), space("deck", "deck-two"))
        gh = FakeGh({**self.nodes, "johnfrog76/deck-two": repo_node([])})
        self.read(moved, gh)
        self.assertEqual(len(gh.queries), 1)
        self.assertIn("n0=deck-two", gh.calls[0])
        self.assertEqual(gh.kinds().count("run list"), 1)

    def test_a_read_that_did_not_answer_is_not_kept(self):
        gh = FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)})  # connected-deck: not found
        out = self.read(self.spaces, gh)
        self.assertIn("connected-deck", out.spaces["deck"].report.reason)
        self.assertIn(accounting.REPO_UNREADABLE, out.spaces["deck"].report.reason)
        self.assertIsNone(disk_cache.get_json(ledger.LEDGER_DIR, "deck.json"))
        again = FakeGh(self.nodes)
        self.read(self.spaces, again)
        self.assertEqual(len(again.queries), 1)
        self.assertIn("n0=connected-deck", again.calls[0])


class TheTier(LedgerCase):
    def test_local_and_archived_spaces_are_unsupported_and_ask_nothing(self):
        gh = FakeGh()
        out = self.read(self.cfg(space("demo", status="local"), space("old", status="archive")), gh)
        self.assertEqual(gh.calls, [])
        for slug in ("demo", "old"):
            self.assertFalse(out.spaces[slug].report.supported)
            self.assertFalse(out.spaces[slug].deploys.supported)

    def test_only_github_spaces_have_a_row(self):
        cfg = self.cfg(space("toolkit"), {"slug": "acme", "org": "https://dev.azure.com/acme", "status": "active"})
        out = self.read(cfg, FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)}))
        self.assertEqual(set(out.spaces), {"toolkit"})

    def test_no_hub_is_below_tier_1(self):
        with mock.patch.object(ledger, "hub_root", return_value=Path(self.hub) / "nowhere"):
            gh = FakeGh()
            out = self.read(self.cfg(space("toolkit")), gh)
        self.assertEqual(gh.calls, [])
        self.assertFalse(out.spaces["toolkit"].report.supported)

    def test_a_signed_out_gh_reads_not_connected_as_before(self):
        gh = FakeGh(down=True)
        out = self.read(self.cfg(space("toolkit")), gh, tier=2)
        self.probe.assert_called_once()
        self.assertFalse(out.spaces["toolkit"].report.supported)
        self.assertEqual(gh.kinds(), ["api graphql"])

    def test_a_call_that_failed_with_the_tracker_there_says_why(self):
        gh = FakeGh(down=True)
        out = self.read(self.cfg(space("toolkit")), gh, tier=1)
        rep = out.spaces["toolkit"].report
        self.assertTrue(rep.supported)
        self.assertIn("johnfrog76/toolkit", rep.reason)
        self.assertIn("gh auth login", rep.reason)
        self.assertIsNone(disk_cache.get_json(ledger.LEDGER_DIR, "toolkit.json"))


class TheReport(LedgerCase):
    def test_it_counts_what_the_pane_report_counts_from_the_same_issues(self):
        def old_gh(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(gh_issue_list_rows(ISSUES)), stderr="")

        with mock.patch.object(accounting.subprocess, "run", side_effect=old_gh):
            old = accounting._github_issue_report("https://github.com/johnfrog76/toolkit", [])
        new = ledger.issue_report(["johnfrog76/toolkit"], {"johnfrog76/toolkit": repo_node(ISSUES)}, {})
        self.assertEqual(new.model_dump(), old.model_dump())
        self.assertEqual((new.open, new.closed, new.closed_recent), (5, 2, 1))
        self.assertEqual(new.sev, {"sev1": 2, "sev2": 1})
        self.assertEqual(new.kind, {"bug": 1, "feat": 2})
        self.assertEqual([m.title for m in new.milestones], ["M2", "M1"])

    def test_the_deploys_are_the_pane_deploys(self):
        gh = FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)})
        out = self.read(self.cfg(space("toolkit")), gh)
        runs = out.spaces["toolkit"].deploys.runs
        self.assertEqual((runs[0].repo, runs[0].title, runs[0].conclusion), ("toolkit", "CI", "success"))


class TheVisibility(LedgerCase):
    def test_the_answer_is_the_contracts_word_and_seeds_the_visibility_cache(self):
        gh = FakeGh({"johnfrog76/toolkit": repo_node([], "PUBLIC"), "johnfrog76/katie-site": repo_node([], "PRIVATE")})
        out = self.read(self.cfg(space("toolkit"), space("katie-site")), gh)
        self.assertEqual(out.spaces["toolkit"].visibility.visibility, "public")
        self.assertEqual(out.spaces["katie-site"].visibility.visibility, "private")
        later = FakeGh()
        with mock.patch.object(accounting.subprocess, "run", side_effect=later):
            self.assertEqual(accounting._gh_repo_visibility("johnfrog76/toolkit"), "public")
        self.assertEqual(later.calls, [])

    def test_a_repository_gh_cannot_read_is_unknown_and_not_held(self):
        out = self.read(self.cfg(space("ghost")), FakeGh())
        self.assertEqual(out.spaces["ghost"].visibility.visibility, "unknown")
        self.assertNotIn("johnfrog76/ghost", accounting._visibility_cache)


class TheArgv(LedgerCase):
    def test_no_argument_carries_what_cmd_exe_would_split(self):
        page = {"data": {"repository": {"page": {"pageInfo": {"hasNextPage": False}, "nodes": []}}}}
        gh = FakeGh(
            {"johnfrog76/a": repo_node(ISSUES, open_total=6, has_next=True), "johnfrog76/b": repo_node([])},
            page=page,
        )
        self.read(self.cfg(space("a"), space("b")), gh)
        self.assertGreaterEqual(len(gh.calls), 4)
        for argv in gh.calls:
            self.assertIsNone(accounting.unsafe_for_shell(argv), argv)
        graphql = [c for c in gh.calls if c[:3] == ["gh", "api", "graphql"]]
        for argv in graphql:
            self.assertTrue(any(a.startswith("query=@") for a in argv), argv)


class TheRoute(LedgerCase):
    def test_get_answers_every_github_space_and_a_second_get_asks_nothing(self):
        cfg = self.cfg(space("toolkit"))
        client = TestClient(app)
        gh = FakeGh({"johnfrog76/toolkit": repo_node(ISSUES)})
        with (
            mock.patch.object(ledger, "load_config", return_value=cfg),
            mock.patch.object(accounting.subprocess, "run", side_effect=gh),
        ):
            first = client.get(studio_ledger_route())
            n = len(gh.calls)
            second = client.get(studio_ledger_route())
            self.assertEqual(len(gh.calls), n)
            client.get(studio_ledger_route() + "?refresh=1")
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.json(), second.json())
        self.assertEqual(first.json()["spaces"]["toolkit"]["report"]["open"], 5)
        self.assertEqual(gh.kinds().count("api graphql"), 2)


if __name__ == "__main__":
    unittest.main()
