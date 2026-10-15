"""The Studio's agent half (docs/modules/studio.md, S2b).

The foyer is one row per GitHub Space, read from the routes the pane already
has -- /api/issue-report and /api/deploys -- for THAT Space, through their
``space`` argument (the one new seam, the spec's trap 1). With no argument the
routes read the active Space exactly as they always did. /env tells the web
which Spaces are GitHub, so the browser never re-derives a tracker.

No network: gh and the tier probe are stubbed.

Run:  python3 -m pytest Tests/test_studio.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi import HTTPException
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.app import app
    from agent.core import config
    from agent.studio import notes
except Exception as exc:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(exc).__name__}: {exc})")

ACTIVE = "https://dev.azure.com/acme"
TOOLKIT = "https://github.com/johnfrog76/toolkit"
WASTELAND = "https://github.com/johnfrog76"

CFG = {
    "org": ACTIVE,
    "status": "active",
    "projects": [{"name": "Platform", "repo": "platform"}],
    "spaces": [
        {"slug": "acme", "org": ACTIVE, "status": "active", "projects": [{"name": "Platform", "repo": "platform"}]},
        {"slug": "toolkit", "org": TOOLKIT, "status": "active", "projects": []},
        {"slug": "wasteland", "org": WASTELAND, "status": "local", "projects": [{"name": "W", "repo": "wasteland"}]},
    ],
}


class TheScope(unittest.TestCase):
    """Which Space a tracker read is about."""

    def test_no_space_is_the_active_one_exactly_as_before(self):
        self.assertEqual(accounting.space_scope(CFG), (ACTIVE, "active", CFG["projects"]))
        self.assertEqual(accounting.space_scope(CFG, ""), (ACTIVE, "active", CFG["projects"]))

    def test_a_slug_is_that_spaces_own_address_status_and_projects(self):
        self.assertEqual(accounting.space_scope(CFG, "toolkit"), (TOOLKIT, "active", []))
        self.assertEqual(
            accounting.space_scope(CFG, "wasteland"), (WASTELAND, "local", [{"name": "W", "repo": "wasteland"}])
        )

    def test_an_unknown_slug_is_a_404_naming_it(self):
        with self.assertRaises(HTTPException) as ctx:
            accounting.space_scope(CFG, "nowhere")
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("nowhere", ctx.exception.detail)

    def test_a_config_with_no_spaces_list_still_answers_for_the_active_one(self):
        # The pane's own tests stub load_config with no `spaces` key at all.
        self.assertEqual(accounting.space_scope({"org": TOOLKIT, "status": "active"}), (TOOLKIT, "active", []))


class TheRoutes(unittest.TestCase):
    """The pane's two routes, asked about a Space you are not in."""

    def setUp(self):
        self.client = TestClient(app)

    def _get(self, path: str, tier: int = 1, stdout: str = "[]"):
        gh_calls: list[list[str]] = []
        tier_calls: list[tuple] = []

        def fake_run(argv, **_kw):
            gh_calls.append(list(argv))
            out = stdout if argv[:3] == ["gh", "issue", "view"] else "[]"
            return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="")

        def fake_tier(org, status):
            tier_calls.append((org, status))
            return tier, ""

        with (
            mock.patch.object(accounting, "load_config", return_value=CFG),
            mock.patch.object(accounting, "_resolve_tier", side_effect=fake_tier),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
        ):
            res = self.client.get(path)
        return res, gh_calls, tier_calls

    def test_the_issue_report_reads_the_named_spaces_repo(self):
        res, calls, tiers = self._get("/api/issue-report?space=toolkit")
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.json()["supported"])
        self.assertEqual(tiers, [(TOOLKIT, "active")])
        self.assertEqual(len(calls), 1)
        self.assertIn("johnfrog76/toolkit", calls[0])

    def test_deploys_read_the_named_spaces_repos(self):
        res, calls, tiers = self._get("/api/deploys?space=toolkit")
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.json()["supported"])
        self.assertEqual(tiers, [(TOOLKIT, "active")])
        self.assertEqual(calls[0][:3], ["gh", "run", "list"])
        self.assertIn("johnfrog76/toolkit", calls[0])

    def test_an_owner_grained_space_spans_its_projects(self):
        _res, calls, tiers = self._get("/api/issue-report?space=wasteland")
        self.assertEqual(tiers, [(WASTELAND, "local")])
        self.assertIn("johnfrog76/wasteland", calls[0])

    def test_an_ado_space_is_unsupported_and_gh_is_never_asked(self):
        for path in ("/api/issue-report?space=acme", "/api/deploys?space=acme"):
            res, calls, tiers = self._get(path)
            self.assertEqual(res.json()["supported"], False, path)
            self.assertEqual((calls, tiers), ([], []), path)

    def test_without_the_argument_the_active_space_answers_as_it_always_did(self):
        # The active Space here is Azure DevOps: unsupported, nothing asked.
        res, calls, _tiers = self._get("/api/issue-report")
        self.assertEqual(res.json()["supported"], False)
        self.assertEqual(calls, [])

    def test_below_tier_1_the_named_space_is_unsupported(self):
        res, calls, _tiers = self._get("/api/deploys?space=toolkit", tier=2)
        self.assertEqual(res.json()["supported"], False)
        self.assertEqual(calls, [])

    def test_a_hub_notes_thread_is_read_through_the_space_that_holds_it(self):
        # The reading room's "document with a thread" face (S2b): the active
        # Space is Azure DevOps here, and the thread is still read -- through
        # the toolkit Space, whose repo it is in.
        issue = json.dumps(
            {
                "number": 90,
                "title": "Feature: the Studio",
                "state": "OPEN",
                "body": "b",
                "comments": [],
                "labels": [],
                "url": "https://github.com/johnfrog76/toolkit/issues/90",
            }
        )
        res, calls, tiers = self._get("/api/issue/90?repo=toolkit&space=toolkit", stdout=issue)
        self.assertEqual(res.status_code, 200)
        self.assertEqual((res.json()["number"], res.json()["repo"]), (90, "toolkit"))
        self.assertEqual(tiers, [(TOOLKIT, "active")])
        self.assertEqual(calls[0][:4], ["gh", "issue", "view", "90"])
        self.assertIn("johnfrog76/toolkit", calls[0])

    def test_the_issue_route_without_a_space_is_the_active_ones(self):
        res, calls, _tiers = self._get("/api/issue/90")
        self.assertEqual(res.json()["supported"], False)
        self.assertEqual(calls, [])

    def test_an_unknown_space_is_404(self):
        for path in ("/api/issue-report?space=nowhere", "/api/deploys?space=nowhere", "/api/issue/1?space=nowhere"):
            res, calls, _tiers = self._get(path)
            self.assertEqual(res.status_code, 404, path)
            self.assertIn("nowhere", res.json()["detail"])
            self.assertEqual(calls, [])


class ThreeSpaceHub(unittest.TestCase):
    """A scratch hub of three Spaces -- no tracker, GitHub, Azure DevOps -- the
    first of them active."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        tmp = Path(self._tmp.name)
        hub = tmp / "hub"
        for slug in ("a", "gh", "ado"):
            (hub / slug / "current").mkdir(parents=True)
        (hub / "hub.json").write_text(
            json.dumps(
                {
                    "hub": 1,
                    "spaces": [
                        {"slug": "a", "name": "A", "status": "local", "promptsFolder": "a"},
                        {"slug": "gh", "name": "Gh", "status": "local", "promptsFolder": "gh", "org": TOOLKIT},
                        {
                            "slug": "ado",
                            "name": "Ado",
                            "status": "local",
                            "promptsFolder": "ado",
                            "org": ACTIVE,
                            "laneNames": {"active": "To do", "inProgress": "Doing"},
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        default = tmp / "config.default.json"
        default.write_text(
            json.dumps({"activeSpace": "a", "spaces": [], "promptsRoot": str(hub), "features": {}}), encoding="utf-8"
        )
        local = tmp / "config.local.json"
        local.write_text("{}", encoding="utf-8")
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(hub)}, clear=False),
        ]
        for p in self._patches:
            p.start()
        self.client = TestClient(app)

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()


class TheEnv(ThreeSpaceHub):
    """/env says which tracker each offered Space's address names."""

    def test_each_space_carries_its_tracker(self):
        spaces = self.client.get("/api/env").json()["config"]["spaces"]
        self.assertEqual({s["slug"]: s["tracker"] for s in spaces}, {"a": "none", "gh": "github", "ado": "ado"})

    def test_each_space_carries_its_own_lane_names_by_contract_word(self):
        # The foyer counts another Space's cards under THAT Space's names.
        spaces = {s["slug"]: s for s in self.client.get("/api/env").json()["config"]["spaces"]}
        self.assertEqual(spaces["ado"]["laneNames"]["Active"], "To do")
        self.assertEqual(spaces["ado"]["laneNames"]["In Progress"], "Doing")
        self.assertEqual(spaces["ado"]["laneNames"]["Code Review"], "Code Review")
        self.assertEqual(
            spaces["a"]["laneNames"],
            {"Active": "Active", "In Progress": "In Progress", "Code Review": "Code Review", "Done": "Done"},
        )


class TheStatusSpaceArgument(ThreeSpaceHub):
    """GET /api/status?space=<slug>: another Space's cards, read from its
    own folder without switching into it. A folder read: no tracker, no tier."""

    def setUp(self):
        super().setUp()
        hub = Path(os.environ["PROMPTS_ROOT"])
        (hub / "a" / "current" / "Task1-here.md").write_text("# Task 1: here\n", encoding="utf-8")
        (hub / "ado" / "current" / "7-there.md").write_text("# Bug 7: there\n", encoding="utf-8")
        (hub / "ado" / "current" / "8-moving.md").write_text(
            "# Bug 8: moving\n\n- 80e2168 a commit\n", encoding="utf-8"
        )

    def _files(self, res):
        self.assertEqual(res.status_code, 200, res.text)
        return {p["file"]: p["status"] for p in res.json()["prompts"]}

    def test_the_argument_reads_another_spaces_cards(self):
        with (
            mock.patch("agent.ado.status._pinned_cards") as pinned,
            mock.patch("agent.ado.status._resolve_tier") as tier,
        ):
            got = self._files(self.client.get("/api/status?space=ado"))
        self.assertEqual(got, {"7-there.md": "Active", "8-moving.md": "In Progress"})
        # A folder read: the tracker is never asked about another Space.
        pinned.assert_not_called()
        tier.assert_not_called()

    def test_without_the_argument_the_active_space_answers_as_it_always_did(self):
        self.assertEqual(self._files(self.client.get("/api/status")), {"Task1-here.md": "Active"})

    def test_naming_the_active_space_is_the_same_answer(self):
        self.assertEqual(self._files(self.client.get("/api/status?space=a")), {"Task1-here.md": "Active"})

    def test_a_space_with_no_cards_answers_empty(self):
        self.assertEqual(self._files(self.client.get("/api/status?space=gh")), {})

    def test_an_unknown_space_is_404_naming_it(self):
        res = self.client.get("/api/status?space=nowhere")
        self.assertEqual(res.status_code, 404)
        self.assertIn("nowhere", res.json()["detail"])


FIXTURE_HUB = PKG_ROOT / "Tests" / "fixtures" / "hub"
CONSTS = json.loads((PKG_ROOT / "consts.json").read_text(encoding="utf-8"))


class HubCase(unittest.TestCase):
    """A scratch copy of the fixture hub, and a config that points at it."""

    features = {}
    spaces = [
        {"slug": "test", "status": "local", "promptsFolder": "test"},
        {"slug": "toolkit", "status": "active", "promptsFolder": "toolkit", "org": TOOLKIT},
    ]

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.hub = base / "hub"
        shutil.copytree(FIXTURE_HUB, self.hub)
        default = base / "config.default.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "features": self.features,
                    "promptsRoot": str(self.hub),
                    "spaces": self.spaces,
                }
            ),
            encoding="utf-8",
        )
        local = base / "config.local.json"
        local.write_text("{}", encoding="utf-8")
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self._patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        self.client = TestClient(app)

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()


class TheSeedDrawer(HubCase):
    """GET /api/studio/design and /api/studio/design/{name} -- the hub's design/ notes."""

    def test_the_list_reads_each_note(self):
        body = self.client.get("/api/studio/design").json()
        self.assertEqual(body["folder"], "design")
        self.assertEqual(body["count"], 1)
        note = body["items"][0]
        self.assertEqual(note["name"], "board-ideas.md")
        self.assertEqual(note["title"], "Board ideas")
        self.assertEqual(note["description"], "What the board could show next")
        self.assertEqual(note["space"], "test")
        self.assertEqual(note["thread"], "https://github.com/johnfrog76/toolkit/issues/90")
        self.assertEqual((note["thread_number"], note["thread_repo"]), (90, "johnfrog76/toolkit"))
        # The thread's repo is the toolkit Space's, so that Space can read it.
        self.assertEqual(note["thread_space"], "toolkit")

    def test_one_note_carries_its_text(self):
        res = self.client.get("/api/studio/design/board-ideas.md")
        self.assertEqual(res.status_code, 200)
        self.assertIn("## The idea", res.json()["body"])
        self.assertEqual(res.json()["title"], "Board ideas")

    def test_a_file_that_is_not_a_note_is_not_listed(self):
        (self.hub / "design" / "notes.txt").write_text("not markdown", encoding="utf-8")
        (self.hub / "design" / ".hidden.md").write_text("# no", encoding="utf-8")
        (self.hub / "design" / "sub").mkdir()
        names = [n["name"] for n in self.client.get("/api/studio/design").json()["items"]]
        self.assertEqual(names, ["board-ideas.md"])

    def test_a_note_with_no_frontmatter_or_thread_reads_plainly(self):
        (self.hub / "design" / "a-plain-note.md").write_text("# A plain note\n\nText.\n", encoding="utf-8")
        note = self.client.get("/api/studio/design").json()["items"][0]
        self.assertEqual(
            (note["name"], note["title"], note["description"], note["space"], note["thread"], note["thread_space"]),
            ("a-plain-note.md", "A plain note", "", "", "", ""),
        )

    def test_a_hub_with_no_design_folder_answers_empty(self):
        shutil.rmtree(self.hub / "design")
        body = self.client.get("/api/studio/design").json()
        self.assertEqual(body["items"], [])
        # A hub an older Start copied out has no design/: the answer says so, so
        # the Hub Designs card can name the folder rather than fail.
        self.assertEqual((body["exists"], body["folder"]), (False, "design"))
        self.assertTrue(self.client.get("/api/studio/design").status_code == 200)

    def test_the_folder_that_is_there_says_so(self):
        self.assertTrue(self.client.get("/api/studio/design").json()["exists"])

    def test_a_name_outside_the_rule_is_404_before_any_read(self):
        for name in ("..%2Fhub.json", "notes.txt", ".hidden.md", "missing.md"):
            self.assertEqual(self.client.get(f"/api/studio/design/{name}").status_code, 404, name)

    def test_the_folder_renamed_through_hub_json_is_followed(self):
        manifest = json.loads((self.hub / "hub.json").read_text(encoding="utf-8"))
        manifest["folders"]["design"] = "ideas"
        (self.hub / "hub.json").write_text(json.dumps(manifest), encoding="utf-8")
        (self.hub / "design").rename(self.hub / "ideas")
        body = self.client.get("/api/studio/design").json()
        self.assertEqual((body["folder"], body["count"]), ("ideas", 1))
        # The grouped rows follow the rename too, and name the file by the hub's folder.
        self.assertEqual(body["designs"][0]["note"]["path"], "ideas/board-ideas.md")
        self.assertEqual(self.client.get("/api/studio/design/ideas/board-ideas.md").status_code, 200)
        self.assertEqual(self.client.get("/api/studio/design/design/board-ideas.md").status_code, 404)

    # -- The four folders and the grouped shape (design lifecycle L2) --------

    ID = "aaaaaaaa-0000-4000-8000-00000000000"

    def _write(self, rel: str, text: str) -> None:
        path = self.hub / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_the_drawer_groups_the_hubs_four_folders_by_id_and_state(self):
        self._write(
            "spec/board-ideas.spec.md", "---\nid: b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11\n---\n\n# Board ideas (spec)\n"
        )
        self._write("design/alone.md", f"---\nid: {self.ID}1\n---\n\n# Alone\n")
        self._write(
            "design/archive/dropped.md",
            f"---\nid: {self.ID}2\n---\n\n# Dropped\n\n**Closed:** 2026-11-20\n**Outcome:** dropped\n",
        )
        self._write(
            "spec/archive/built.spec.md",
            f"---\nid: {self.ID}3\n---\n\n# Built (spec)\n\n> Docs: docs/x.md\n\n**Closed:** 2026-10-01\n",
        )
        self._write("design/unstamped.md", "# No id\n")
        self._write("design/README.md", "# Not a design\n")
        body = self.client.get("/api/studio/design").json()
        self.assertEqual(
            (body["folder"], body["specFolder"], body["structure"]), ("design", "spec", {"design": True, "spec": True})
        )
        # items and count stay what they were: the live notes, for the + and Promote.
        self.assertEqual([n["name"] for n in body["items"]], ["alone.md", "board-ideas.md", "unstamped.md"])
        self.assertEqual(body["count"], 3)
        self.assertEqual(
            [(d["state"], d["title"]) for d in body["designs"]],
            [("Design", "Alone"), ("Spec", "Board ideas"), ("Complete", "Built (spec)"), ("Archived", "Dropped")],
        )
        promoted = body["designs"][1]
        # The hub's rows carry the Space the note names and which Space reads its thread (S2b).
        self.assertEqual(
            (promoted["space"], promoted["thread_space"], promoted["thread_number"]), ("test", "toolkit", 90)
        )
        self.assertEqual(
            (promoted["note"]["path"], promoted["spec"]["path"]), ("design/board-ideas.md", "spec/board-ideas.spec.md")
        )
        self.assertEqual((body["designs"][3]["outcome"], body["designs"][3]["closed"]), ("dropped", "2026-11-20"))
        self.assertEqual(body["designs"][2]["docs"], "docs/x.md")
        self.assertEqual(body["notShown"], [{"path": "design/unstamped.md", "reason": "no id"}])

    def test_an_archived_note_and_a_spec_read_by_their_hub_path(self):
        self._write("design/archive/old.md", f"---\nid: {self.ID}2\n---\n\n# Old\n\n**Closed:** 2026-11-20\n")
        self._write(
            "spec/board-ideas.spec.md", "---\nid: b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11\n---\n\n# Board ideas (spec)\n"
        )
        old = self.client.get("/api/studio/design/design/archive/old.md").json()
        self.assertEqual(
            (old["path"], old["kind"], old["archived"], old["title"]), ("design/archive/old.md", "note", True, "Old")
        )
        spec = self.client.get("/api/studio/design/spec/board-ideas.spec.md").json()
        self.assertEqual((spec["path"], spec["kind"], spec["archived"]), ("spec/board-ideas.spec.md", "spec", False))
        # The bare name is still the live note, as the route always read it.
        bare = self.client.get("/api/studio/design/board-ideas.md").json()
        self.assertEqual((bare["path"], bare["kind"]), ("design/board-ideas.md", "note"))
        for path in (
            "design/archive/missing.md",
            "spec/archive/x.md",
            "growth/x.md",
            "design/archive/sub/x.md",
            "design/../hub.json",
        ):
            self.assertEqual(self.client.get(f"/api/studio/design/{path}").status_code, 404, path)

    def test_a_hub_with_only_a_design_folder_has_no_spec_structure(self):
        body = self.client.get("/api/studio/design").json()
        self.assertEqual(body["structure"], {"design": True, "spec": False})
        self.assertEqual([d["state"] for d in body["designs"]], ["Design"])

    # -- Search inside, on disk (L2b) ------------------------------------------

    def test_search_inside_runs_the_words_over_the_text_on_disk_across_every_state(self):
        self._write(
            "spec/board-ideas.spec.md",
            "---\nid: b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11\n---\n\n"
            "# Board ideas (spec)\n\nWhat is waiting on whom, as a contract.\n",
        )
        self._write(
            "design/archive/dropped.md",
            f"---\nid: {self.ID}2\n---\n\n# A second room\n\nWaiting for nobody.\n\n"
            "**Closed:** 2026-11-20\n**Outcome:** dropped\n",
        )
        self._write("design/unstamped.md", "# No id\n\nwaiting too\n")
        body = self.client.get("/api/studio/design/search?q=Waiting").json()
        self.assertEqual(
            (body["supported"], body["available"], body["repo"], body["query"]), (True, True, "the hub", "Waiting")
        )
        self.assertEqual(
            [(h["path"], h["state"], h["line"]) for h in body["hits"]],
            [
                ("design/board-ideas.md", "Spec", "The board shows lanes; it could show what is waiting on whom."),
                ("spec/board-ideas.spec.md", "Spec", "What is waiting on whom, as a contract."),
                ("design/archive/dropped.md", "Archived", "Waiting for nobody."),
                ("design/unstamped.md", "", "waiting too"),
            ],
        )
        self.assertEqual(body["hits"][0]["title"], "Board ideas")
        self.assertIn("on disk", body["note"])
        # Every word must match; nothing typed asks nothing.
        self.assertEqual(
            [h["path"] for h in self.client.get("/api/studio/design/search?q=waiting%20nobody").json()["hits"]],
            ["design/archive/dropped.md"],
        )
        self.assertEqual(self.client.get("/api/studio/design/search?q=").json()["hits"], [])
        # "search" is the route, not a note's name: the document read still answers for real names.
        self.assertEqual(self.client.get("/api/studio/design/board-ideas.md").status_code, 200)

    def test_the_thread_space_rule(self):
        spaces = [
            {"slug": "acme", "org": "https://dev.azure.com/acme", "projects": [{"repo": "toolkit"}]},
            {"slug": "w", "org": "https://github.com/JohnFrog76", "projects": [{"repo": "Wasteland"}]},
            {"slug": "t", "org": TOOLKIT},
        ]
        self.assertEqual(notes.thread_space("johnfrog76/toolkit", spaces), "t")
        self.assertEqual(notes.thread_space("johnfrog76/wasteland", spaces), "w")  # case is GitHub's business
        self.assertEqual(notes.thread_space("someone/else", spaces), "")
        self.assertEqual(notes.thread_space("", spaces), "")


class TheStudioIsCore(HubCase):
    """D-S13: there is no features.studio. A line left in a machine's
    config -- true or false -- is ignored, and is never an error."""

    def test_a_leftover_flag_true_or_false_changes_nothing(self):
        for leftover in (True, False):
            with self.subTest(studio=leftover):
                config.LOCAL_CONFIG_PATH.write_text(json.dumps({"features": {"studio": leftover}}), encoding="utf-8")
                for path in ("/api/studio/design", "/api/studio/design/board-ideas.md"):
                    self.assertEqual(self.client.get(path).status_code, 200, path)


class TheContract(unittest.TestCase):
    def test_the_note_name_rule(self):
        rule = notes.re_studio_note_name()
        for good in ("board-ideas.md", "a.md", "Spike_2.md", "v1.2-notes.md"):
            self.assertTrue(rule.match(good), good)
        for bad in ("..md", ".hidden.md", "notes.txt", "a/b.md", "-x.md", "", "x.md/"):
            self.assertFalse(rule.match(bad), bad)

    def test_the_repo_design_tab_reads_the_same_thread_line(self):
        from agent.ado import design

        self.assertEqual(design._THREAD.pattern, CONSTS["studio"]["threadRegex"])
        self.assertTrue(CONSTS["studio"]["threadRegex"].startswith("(?m)^>"))
        self.assertTrue(CONSTS["studio"]["threadLine"].startswith(">"))


def _pwsh() -> str | None:
    return shutil.which("pwsh")


@unittest.skipIf(_pwsh() is None, "pwsh is not on this machine")
class TheVerbTyped(unittest.TestCase):
    """NewDesign, typed as a verb in a fresh shell with this package's module and
    nothing else (AGENTS.md, "A suite that runs a script directly does not test
    the verb"). The CLI half of the seed drawer: the file, its bytes, its refusals."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.pkg = base / "pkg"
        self.hub = base / "hub"
        self.pkg.mkdir()
        for item in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / item, self.pkg / item)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.hub / "demo" / "current").mkdir(parents=True)
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "orgs": [
                        {"slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo"},
                    ]
                }
            ),
            encoding="utf-8",
        )
        self.log = base / "log"
        self.log.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def run_verbs(self, snippet: str, features: dict | None = None) -> str:
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": self.hub.as_posix(),
                    "activeSpace": "demo",
                    "quietStart": True,
                    "features": features or {},
                }
            ),
            encoding="utf-8",
        )

        def q(p):
            return str(p).replace("'", "''")

        body = (
            f"$env:PSModulePath = '{q(self.pkg)}'; $env:PROMPTS_ROOT = ''; $env:P20_USAGE_LOG_DIR = '{q(self.log)}'; "
            f"Import-Module '{q(self.pkg)}/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>$null 6>$null; {snippet}"
        )
        env = {k: v for k, v in os.environ.items() if k != "PROMPTS_ROOT"}
        out = subprocess.run(
            [_pwsh(), "-NoProfile", "-NonInteractive", "-Command", body],
            capture_output=True,
            text=True,
            timeout=240,
            env=env,
            check=False,
        )
        return out.stdout + out.stderr

    def test_the_verbs_are_core_whatever_a_leftover_flag_says(self):
        """D-S13: no flag to find. With no features block, and with a leftover
        features.studio of either value, both verbs resolve, Menu -All lists
        them under Studio, -Help answers from the core table, and the bridge
        can call them."""
        probe = (
            "'NEW=' + [bool](Get-Command tkNewDesign -ErrorAction SilentlyContinue); "
            "'STAMP=' + [bool](Get-Command tkStampDesign -ErrorAction SilentlyContinue); "
            "'MAP=' + (Get-P20CommandMap); tkMenu -All 6>&1 | Out-String; tkNewDesign -Help 6>&1 | Out-String"
        )
        for features in ({}, {"studio": True}, {"studio": False}):
            with self.subTest(features=features):
                out = self.run_verbs(probe, features=features)
                self.assertIn("NEW=True", out)
                self.assertIn("STAMP=True", out)
                self.assertIn('"NewDesign"', out)
                self.assertIn('"StampDesign"', out)
                self.assertIn("Studio", out)
                self.assertIn("tkStampDesign", out)
                self.assertIn("Scaffold a design note in the hub", out)
                self.assertNotIn("features.studio", out)

    def test_the_verbs_autoload_in_a_profile_less_shell(self):
        """No Import-Module: the manifest's AliasesToExport is what resolves them."""
        manifest = (PKG_ROOT / "Prompt20Toolkit" / "Prompt20Toolkit.psd1").read_text(encoding="utf-8")
        self.assertIn("'tkNewDesign',", manifest)
        self.assertIn("'tkStampDesign',", manifest)
        self.assertFalse((PKG_ROOT / "Config" / "studio.commands.psd1").exists(), "the studio data file is gone")
        self.assertFalse((PKG_ROOT / "Config" / "studio.commands.ps1").exists())

    def test_config_set_features_studio_is_refused_in_one_sentence(self):
        for value in ("true", "false"):
            with self.subTest(value=value):
                out = self.run_verbs(f"tkConfig -Set features.studio={value}; 'C=' + $LASTEXITCODE")
                self.assertIn("C=2", out)
                self.assertIn("The Studio is part of the core and has no switch", out)
                self.assertEqual(out.count("Error:"), 1, out)
                local = json.loads((self.pkg / "config.local.json").read_text(encoding="utf-8"))
                self.assertEqual(local.get("features"), {}, "nothing was written")

    def test_on_the_verb_writes_one_note_from_the_template(self):
        out = self.run_verbs(
            "tkNewDesign -Title 'Board ideas: the next lane' -Description 'What the \"board\" could show'; "
            "'A=' + $LASTEXITCODE; "
            "'MAP=' + (Get-P20CommandMap)"
        )
        self.assertIn("A=0", out)
        self.assertIn("Created design note: design/board-ideas-the-next-lane.md", out)
        self.assertIn('"NewDesign"', out)  # the bridge can call it
        path = self.hub / "design" / "board-ideas-the-next-lane.md"
        raw = path.read_bytes()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), "no BOM")
        self.assertNotIn(b"\r\n", raw, "created LF")
        text = raw.decode("utf-8")
        self.assertRegex(text, r'\A---\nid: [0-9a-f-]{36}\ndescription: "What the \'board\' could show"\n---\n')
        self.assertNotIn("space:", text.split("---")[1], "no -Space, no space line")
        self.assertIn("\n# Board ideas: the next lane\n", text)
        self.assertIn("## The idea", text)
        self.assertRegex(text, r"\*\*Created:\*\* \d{4}-\d{2}-\d{2}\n$")
        self.assertRegex(path.name, CONSTS["studio"]["noteName"])

    def test_it_never_overwrites(self):
        self.run_verbs("tkNewDesign -Title 'Board ideas'")
        path = self.hub / "design" / "board-ideas.md"
        path.write_text("# Board ideas\n\nMy own words.\n", encoding="utf-8")
        out = self.run_verbs("tkNewDesign -Title 'Board ideas'; 'B=' + $LASTEXITCODE")
        self.assertIn("B=2", out)
        self.assertIn("already exists. Not overwriting it.", out)
        self.assertEqual(path.read_text(encoding="utf-8"), "# Board ideas\n\nMy own words.\n")

    def test_the_space_it_names_is_written_and_must_be_declared(self):
        out = self.run_verbs(
            "tkNewDesign -Title 'Spike' -Space demo; 'S=' + $LASTEXITCODE; "
            "tkNewDesign -Title 'Elsewhere' -Space nowhere; 'N=' + $LASTEXITCODE"
        )
        self.assertIn("S=0", out)
        self.assertIn("\nspace: demo\n", (self.hub / "design" / "spike.md").read_text(encoding="utf-8"))
        self.assertIn("N=2", out)
        self.assertIn("No Space 'nowhere' is declared.", out)
        self.assertFalse((self.hub / "design" / "elsewhere.md").exists())

    def test_the_refusals_are_stated(self):
        out = self.run_verbs("tkNewDesign; 'T=' + $LASTEXITCODE; tkNewDesign -Title '!!!'; 'U=' + $LASTEXITCODE")
        self.assertIn("A design note needs a title.", out)
        self.assertIn("T=2", out)
        self.assertIn("has no letter or digit", out)
        self.assertIn("U=2", out)
        self.assertFalse((self.hub / "design").exists() and any((self.hub / "design").iterdir()))

    def test_the_agent_reads_what_the_verb_wrote(self):
        self.run_verbs("tkNewDesign -Title 'Round trip' -Description 'One writer, one reader' -Space demo")
        text = (self.hub / "design" / "round-trip.md").read_text(encoding="utf-8")
        note = notes.read_note(text, "round-trip.md", [])
        self.assertEqual(
            (note.title, note.description, note.space, note.thread),
            ("Round trip", "One writer, one reader", "demo", ""),
        )

    def test_the_note_carries_an_id_of_the_contracts_shape(self):
        """L1: NewDesign stamps `id:` at birth, and the readers that already exist still
        take the title and description from a file that opens with it."""
        from agent.core import consts as C

        self.run_verbs("tkNewDesign -Title 'Born stamped' -Description 'One line'")
        text = (self.hub / "design" / "born-stamped.md").read_text(encoding="utf-8")
        lines = text.split("\n")
        self.assertEqual(lines[0], "---")
        self.assertTrue(lines[1].startswith(C.design_id_key() + ": "), lines[1])
        self.assertRegex(lines[1].split(": ", 1)[1], C.re_design_id())
        note = notes.read_note(text, "born-stamped.md", [])
        self.assertEqual((note.title, note.description), ("Born stamped", "One line"))
        self.run_verbs("tkNewDesign -Title 'Another one'")
        other = (self.hub / "design" / "another-one.md").read_text(encoding="utf-8").split("\n")[1]
        self.assertNotEqual(other, lines[1], "two notes, two ids")


PROMOTE_PREAMBLE = r"""
$env:PSModulePath = '{pkg}'
$env:PROMPTS_ROOT = '{hub}'
$env:P20_USAGE_LOG_DIR = '{log}'
Get-ChildItem Env: | Where-Object {{ $_.Name -like 'TEAMS_WEBHOOK_*' }} | ForEach-Object {{ Remove-Item "Env:\$($_.Name)" -ErrorAction SilentlyContinue }}
function global:gh {{
    # One line per call: a multi-line --body is written with its newlines as \n.
    Add-Content -Path '{calls}' -Value ("gh " + (($args | ForEach-Object {{ ("$_" -replace "`r?`n", '\n') }}) -join ' | '))
    if ($args[0] -eq 'issue' -and $args[1] -eq 'create') {{
        $global:LASTEXITCODE = 0
        return 'https://github.com/acme/widgets/issues/41'
    }}
    $global:LASTEXITCODE = 0
}}
Import-Module '{pkg}/utilities.psm1' -Force -DisableNameChecking *>$null
# Tier 1: the tracker "answers" -- the stub above is what it answers with.
$global:P20Env = [pscustomobject]@{{ Tier = 1; Tracker = 'github' }}
"""  # noqa: E501 -- a PowerShell script; its line length is PowerShell's


@unittest.skipIf(_pwsh() is None, "pwsh is not on this machine")
class ThePromote(unittest.TestCase):
    """Promote: NewItem -FromDesign <note>, typed as the verb, gh stubbed as a
    function that writes down what it was asked and answers with an issue URL.
    The issue is the note's title and body, labelled design; its URL comes back
    into the note as the thread line, through Write-CardText (an EDIT: the note
    keeps its own line endings)."""

    NOTE = (
        '---\ndescription: "What the board could show next"\nspace: widgets\n---\n\n'
        "# Board ideas\n\n## Problem\n\nLanes only.\n\n**Created:** 2026-10-01\n"
    )

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.pkg, self.hub, self.log, self.calls = base / "pkg", base / "hub", base / "log", base / "calls.log"
        self.pkg.mkdir()
        self.log.mkdir()
        for item in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / item, self.pkg / item)
        for folder in ("Scripts", "Config", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.hub / "design").mkdir(parents=True)
        for slug in ("widgets", "board"):
            (self.hub / slug / "current").mkdir(parents=True)
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "hub": 1,
                    "spaces": [
                        {
                            "slug": "widgets",
                            "name": "Widgets",
                            "status": "active",
                            "promptsFolder": "widgets",
                            "org": "https://github.com/acme/widgets",
                        },
                        {
                            "slug": "board",
                            "name": "Board",
                            "status": "active",
                            "promptsFolder": "board",
                            "org": "https://dev.azure.com/acme-org",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.note = self.hub / "design" / "board-ideas.md"
        self.note.write_bytes(self.NOTE.encode("utf-8"))

    def tearDown(self):
        self._tmp.cleanup()

    def promote(self, snippet: str, space: str = "widgets"):
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "quietStart": True,
                    "promptsRoot": self.hub.as_posix(),
                    "activeSpace": space,
                }
            ),
            encoding="utf-8",
        )
        if self.calls.exists():
            self.calls.unlink()

        def q(x):
            return str(x).replace("'", "''")

        runner = self.pkg.parent / "run.ps1"
        runner.write_text(
            PROMOTE_PREAMBLE.format(pkg=q(self.pkg), hub=q(self.hub), log=q(self.log), calls=q(self.calls))
            + "\n"
            + snippet
            + "\n'EXIT=' + $LASTEXITCODE\n",
            encoding="utf-8",
        )
        env = {k: v for k, v in os.environ.items() if not k.startswith("TEAMS_WEBHOOK_")}
        out = subprocess.run(
            [_pwsh(), "-NoProfile", "-File", str(runner)],
            capture_output=True,
            text=True,
            timeout=240,
            env=env,
            check=False,
        )
        calls = self.calls.read_text(encoding="utf-8").splitlines() if self.calls.exists() else []
        return out.stdout + out.stderr, calls

    def test_promote_opens_the_issue_from_the_note_and_writes_the_thread_back(self):
        out, calls = self.promote("tkNewItem -FromDesign board-ideas.md")
        self.assertIn("EXIT=0", out)
        creates = [c for c in calls if c.startswith("gh issue | create")]
        self.assertEqual(len(creates), 1, calls)
        args = creates[0].split(" | ")
        self.assertEqual(args[args.index("--repo") + 1], "acme/widgets")
        self.assertEqual(args[args.index("--title") + 1], "Board ideas")
        self.assertEqual(args[args.index("--label") + 1], CONSTS["studio"]["promoteLabel"])
        body = args[args.index("--body") + 1]
        self.assertTrue(body.startswith("## Problem"), body)  # the note, without its frontmatter or its title
        self.assertNotIn("description:", body)
        text = self.note.read_text(encoding="utf-8")
        self.assertIn("# Board ideas\n\n> GitHub: https://github.com/acme/widgets/issues/41\n\n## Problem", text)
        self.assertTrue(text.startswith("---\ndescription:"), "the frontmatter is kept")
        self.assertRegex(text, CONSTS["studio"]["threadRegex"])
        self.assertIn("Wrote the thread into design/board-ideas.md", out)
        # And the agent reads it back as the note's thread.
        note = notes.read_note(text, "board-ideas.md", [])
        self.assertEqual((note.thread_number, note.thread_repo), (41, "acme/widgets"))

    def test_a_crlf_note_keeps_its_endings(self):
        self.note.write_bytes(self.NOTE.replace("\n", "\r\n").encode("utf-8"))
        out, _calls = self.promote("tkNewItem -FromDesign board-ideas.md")
        self.assertIn("EXIT=0", out)
        raw = self.note.read_bytes()
        self.assertIn(b"> GitHub: https://github.com/acme/widgets/issues/41\r\n", raw)
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "every line CRLF still")
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"))

    def test_read_only_creates_nothing_and_writes_nothing(self):
        out, calls = self.promote("tkNewItem -FromDesign board-ideas.md -ReadOnly")
        self.assertIn("EXIT=0", out)
        self.assertIn("[DRY RUN]", out)
        self.assertIn("Labels:    design", out)
        self.assertEqual([c for c in calls if "create" in c], [])
        self.assertEqual(self.note.read_text(encoding="utf-8"), self.NOTE)

    def test_the_refusals_write_nothing_and_ask_nothing(self):
        promoted = self.NOTE.replace(
            "# Board ideas\n", "# Board ideas\n\n> GitHub: https://github.com/acme/widgets/issues/7\n"
        )
        cases = [
            ("a promoted note", promoted, "widgets", "tkNewItem -FromDesign board-ideas.md", "already has its thread"),
            (
                "another Space's note",
                self.NOTE,
                "board",
                "tkNewItem -FromDesign board-ideas.md",
                "is for the Space 'widgets'",
            ),
            ("no such note", self.NOTE, "widgets", "tkNewItem -FromDesign missing.md", "No note design/missing.md"),
            (
                "not a note's name",
                self.NOTE,
                "widgets",
                "tkNewItem -FromDesign ../hub.json",
                "is not a design note's name",
            ),
            (
                "a title beside it",
                self.NOTE,
                "widgets",
                "tkNewItem -FromDesign board-ideas.md -Title X",
                "-Title has nothing to do",
            ),
        ]
        for why, content, space, snippet, said in cases:
            with self.subTest(why=why):
                self.note.write_text(content, encoding="utf-8")
                out, calls = self.promote(snippet, space=space)
                self.assertIn(said, out)
                self.assertIn("EXIT=2", out)
                self.assertEqual([c for c in calls if "create" in c], [])
                self.assertEqual(self.note.read_text(encoding="utf-8"), content)

    def test_an_unspaced_note_on_an_ado_space_is_refused_d_s9(self):
        self.note.write_text(self.NOTE.replace("space: widgets\n", ""), encoding="utf-8")
        out, calls = self.promote("tkNewItem -FromDesign board-ideas.md", space="board")
        self.assertIn("this Space's tracker is not GitHub", out)
        self.assertIn("EXIT=2", out)
        self.assertEqual(calls, [])


class TheSampleHubIsDressed(HubCase):
    """#257: the sample hub `Start` copies out carries one design of each state, and the reader reads them as is."""

    def setUp(self):
        super().setUp()
        shutil.rmtree(self.hub)
        shutil.copytree(PKG_ROOT / "samples" / "hub", self.hub)

    def test_four_designs_one_in_each_state_and_nothing_unread(self):
        body = self.client.get("/api/studio/design").json()
        self.assertTrue(body["exists"])
        self.assertEqual(body["notShown"], [])
        by_title = {d["title"]: d for d in body["designs"]}
        self.assertEqual(
            sorted((d["state"], d.get("outcome") or "") for d in body["designs"]),
            [("Archived", "dropped"), ("Complete", ""), ("Design", ""), ("Spec", "")],
        )
        self.assertEqual(by_title["Read a recipe from a photo"]["space"], "demo")
        done = by_title["Import a recipe from a URL"]
        self.assertTrue(done["closed"])
        self.assertTrue((self.hub / done["docs"]).is_file(), done["docs"])


class TheBoundCards(HubCase):
    """A design's row lists the cards worked against it, and a card's page names
    its design (docs/hub/cards.md): read from the
    cards' `> Design:` lines on every request, stored nowhere."""

    BOARD = "b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11"  # Tests/fixtures/hub/design/board-ideas.md

    def setUp(self):
        super().setUp()
        line = f"> Design: [Board ideas](../../design/board-ideas.md) {self.BOARD}"
        cur = self.hub / "test" / "current"
        (cur / "K7M2-lanes-part-one.prompt.md").write_text(
            f"# Task K7M2: Lanes, part one\n\n> Template: [Task.template.md](x)\n{line}\n\n## Branch\nx\n",
            encoding="utf-8",
        )
        # Another Space's card, archived, and CRLF: still the design's.
        arc = self.hub / "toolkit" / "archive"
        arc.mkdir(parents=True)
        (arc / "Q4TN-lanes-part-zero.prompt.md").write_bytes(
            f"# Task Q4TN: Lanes, part zero\r\n\r\n{line}\r\n".encode()
        )
        # A hand-written Spec line carries no id, so it binds nothing.
        (cur / "US-459-view-prize-vault.prompt.md").write_text(
            "# User Story 459: View Prize Vault\n\n> Spec: [Prize-Store.spec.md](../spec/Prize-Store.spec.md) (D4)\n",
            encoding="utf-8",
        )

    def test_the_row_lists_the_cards_that_name_it_from_every_space(self):
        body = self.client.get("/api/studio/design").json()
        row = next(d for d in body["designs"] if d["id"] == self.BOARD)
        self.assertEqual(
            [(c["file"], c["id"], c["space"], c["status"], c["archived"]) for c in row["cards"]],
            [
                ("K7M2-lanes-part-one.prompt.md", "K7M2", "test", "Active", False),
                ("Q4TN-lanes-part-zero.prompt.md", "Q4TN", "toolkit", "Done", True),
            ],
        )
        self.assertEqual(row["cards"][0]["title"], "Task K7M2: Lanes, part one")

    def test_a_card_written_a_moment_ago_is_on_the_next_read(self):
        (self.hub / "test" / "current" / "K7M2-lanes-part-one.prompt.md").unlink()
        row = next(d for d in self.client.get("/api/studio/design").json()["designs"] if d["id"] == self.BOARD)
        self.assertEqual([c["id"] for c in row["cards"]], ["Q4TN"])

    def test_the_card_page_names_its_design_resolved_against_the_hub(self):
        body = self.client.get("/api/status/K7M2-lanes-part-one.prompt.md").json()
        self.assertEqual(
            body["design"],
            {
                "kind": "design",
                "title": "Board ideas",
                "link": "../../design/board-ideas.md",
                "id": self.BOARD,
                "short": self.BOARD[:8],
                "note": "",
                "state": "Design",
                "where": "hub",
                "path": "design/board-ideas.md",
            },
        )

    def test_a_hand_written_spec_line_is_read_as_written_and_resolves_nothing(self):
        body = self.client.get("/api/status/US-459-view-prize-vault.prompt.md").json()
        self.assertEqual(
            (body["design"]["kind"], body["design"]["title"], body["design"]["note"]),
            ("spec", "Prize-Store.spec.md", "(D4)"),
        )
        self.assertEqual((body["design"]["id"], body["design"]["state"], body["design"]["where"]), ("", "", ""))

    def test_an_id_no_design_carries_keeps_the_line_as_last_written(self):
        cur = self.hub / "test" / "current"
        (cur / "W3KC-gone.prompt.md").write_text(
            "# Task W3KC: Gone\n\n> Design: [An old idea](../../design/old.md) 7d2e4f60-1a2b-4c3d-8e9f-aabbccddeeff\n",
            encoding="utf-8",
        )
        d = self.client.get("/api/status/W3KC-gone.prompt.md").json()["design"]
        self.assertEqual((d["title"], d["short"], d["state"], d["where"]), ("An old idea", "7d2e4f60", "", ""))

    def test_the_list_carries_each_cards_design_unresolved(self):
        with mock.patch("agent.ado.status._pinned_cards"):
            prompts = {p["file"]: p for p in self.client.get("/api/status").json()["prompts"]}
        d = prompts["K7M2-lanes-part-one.prompt.md"]["design"]
        self.assertEqual((d["id"], d["short"], d["state"]), (self.BOARD, self.BOARD[:8], ""))
        self.assertIsNone(prompts["Task401-add-retry-to-upload.prompt.md"]["design"])


if __name__ == "__main__":
    unittest.main()
