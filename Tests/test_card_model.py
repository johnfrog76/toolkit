"""The Card model, end to end through ``GET /api/status``.

``docs/hub/cards.md``, "The model, as the agent serves it": a card has a model -- id, type, name, linked,
state -- and the status route serves it as FIELDS. ``test_parsers.py`` holds the
parser; this holds the route: that ``id`` comes from the filename by the one id
rule, that ``type`` is matched against the CONFIGURED types (so a team's own type
is known), and that a card with no work item is a card like any other.

Run:  python3 -m pytest Tests/test_card_model.py
"""

import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.core.consts import stamp_assigned, stamp_billable, stamp_milestone
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

CARD = """# {heading}

## Branch
you/{id}-slug

## Git
Commits:
- {commit}

## Done when
- [x] one
- [ ] two

---

**Sprint:** RecipeBox\\Sprint 8
**ADO Link:** {link}
**Created:** 2026-09-20
"""


def _hub(cards: dict[str, str]) -> tempfile.TemporaryDirectory:
    tmp = tempfile.TemporaryDirectory()
    current = Path(tmp.name) / "test" / "current"
    current.mkdir(parents=True)
    for name, text in cards.items():
        (current / name).write_text(text, encoding="utf-8")
    return tmp


class TheRouteServesTheModel(unittest.TestCase):
    def setUp(self):
        self.hub = _hub(
            {
                "141-recipe-search.prompt.md": CARD.format(
                    heading="Bug 141: Recipe search returns duplicates",
                    id="141",
                    commit="(pending)",
                    link="https://dev.azure.com/o/p/_workitems/edit/141",
                ),
                "Spike-K7M2-wallet-ticket.prompt.md": CARD.format(
                    heading="Spike K7M2: Wallet ticket from a QR code",
                    id="K7M2",
                    commit="a41c2e9 try it",
                    link="(not linked -- created offline with -Title)",
                ),
                "Chore-Q4TN-rotate-the-keys.prompt.md": CARD.format(
                    heading="Chore Q4TN: Rotate the keys", id="Q4TN", commit="(pending)", link="(not linked)"
                ),
                # The line comes from consts.json, so this test does not retype it.
                "TaskW3X7-bench-reading.prompt.md": CARD.format(
                    heading="Task W3X7: Bench reading",
                    id="W3X7",
                    commit="(pending)",
                    link="(not linked)",
                ).replace(
                    "**Created:**",
                    f"{stamp_billable()} no\n{stamp_assigned()} me\n{stamp_milestone()} v0.3 -- Share\n**Created:**",
                ),
                "notes-from-tuesday.prompt.md": "# Notes from Tuesday\n\nNot a card.\n",
                # A GitHub-born card in the same (local) Space: the mingling the tracker badge is for.
                "Task54-badge-the-tracker.prompt.md": CARD.format(
                    heading="Task 54: Badge the tracker",
                    id="54",
                    commit="(pending)",
                    link="https://github.com/johnfrog76/toolkit/issues/54",
                ),
            }
        )
        self.cfg = tempfile.TemporaryDirectory()
        base = Path(self.cfg.name)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "commandPrefix": "tk",
                    "features": {},
                    "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
                    "commands": {},
                    "workItemTypes": {
                        "_comment": "a comment key is not a type",
                        "User Story": {"filePrefix": "US-"},
                        "Task": {"filePrefix": "Task"},
                        "Bug": {"filePrefix": ""},
                        "Spike": {"filePrefix": "Spike-"},
                    },
                }
            ),
            encoding="utf-8",
        )
        # A TEAM'S OWN type, added on this machine: config, not code.
        (base / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": self.hub.name,
                    "workItemTypes": {"Chore": {"filePrefix": "Chore-"}},
                }
            ),
            encoding="utf-8",
        )
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in self.patches:
            p.start()
        from agent.app import app

        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.cfg.cleanup()
        self.hub.cleanup()

    def _by_file(self):
        body = self.client.get("/api/status").json()
        return {p["file"]: p for p in body["prompts"]}

    def test_a_linked_card(self):
        card = self._by_file()["141-recipe-search.prompt.md"]
        self.assertEqual(
            (card["id"], card["type"], card["name"], card["linked"]),
            ("141", "Bug", "Recipe search returns duplicates", True),
        )
        self.assertEqual(card["title"], "Bug 141: Recipe search returns duplicates")

    def test_a_card_with_no_work_item_is_a_card_like_any_other(self):
        card = self._by_file()["Spike-K7M2-wallet-ticket.prompt.md"]
        self.assertEqual((card["id"], card["type"], card["linked"]), ("K7M2", "Spike", False))
        # Same states, same derivation: a commit bullet is In Progress, linked or not.
        self.assertEqual(card["status"], "In Progress")
        self.assertEqual(card["progress"], "1/2")

    def test_a_card_in_backlog_is_served_as_backlog_and_listed_after_the_cards_in_play(self):
        """backlog/ is the Space's third card folder (docs/hub/cards.md): the route
        reads it beside current/, the folder state is read FIRST -- a commit bullet
        there is still Backlog -- and the ledger's order puts it after the cards in
        play. The card's own page finds it too."""
        backlog = Path(self.hub.name) / "test" / "backlog"
        backlog.mkdir()
        (backlog / "TaskR9PX-plan-it.prompt.md").write_text(
            CARD.format(heading="Task R9PX: Plan it", id="R9PX", commit="a41c2e9 by hand", link="(not linked)"),
            encoding="utf-8",
        )
        body = self.client.get("/api/status").json()
        files = [p["file"] for p in body["prompts"]]
        card = {p["file"]: p for p in body["prompts"]}["TaskR9PX-plan-it.prompt.md"]
        self.assertEqual((card["id"], card["type"], card["status"]), ("R9PX", "Task", "Backlog"))
        self.assertEqual(files[-1], "TaskR9PX-plan-it.prompt.md")
        self.assertEqual(body["count"], len(files))
        detail = self.client.get("/api/status/TaskR9PX-plan-it.prompt.md").json()
        self.assertEqual((detail["status"], detail["name"]), ("Backlog", "Plan it"))
        self.assertTrue(detail["path"].endswith(str(Path("test") / "backlog" / "TaskR9PX-plan-it.prompt.md")))

    def test_a_teams_own_type_from_the_machines_config(self):
        card = self._by_file()["Chore-Q4TN-rotate-the-keys.prompt.md"]
        self.assertEqual((card["id"], card["type"]), ("Q4TN", "Chore"))

    def test_a_file_that_is_not_a_card_has_no_id_and_no_type(self):
        card = self._by_file()["notes-from-tuesday.prompt.md"]
        self.assertEqual((card["id"], card["type"], card["name"]), (None, None, "Notes from Tuesday"))

    def test_a_card_is_billable_unless_it_says_otherwise(self):
        """No line means billable: no existing card needed migrating."""
        cards = self._by_file()
        self.assertIs(cards["141-recipe-search.prompt.md"]["billable"], True)
        self.assertIs(cards["Spike-K7M2-wallet-ticket.prompt.md"]["billable"], True)
        self.assertIs(cards["TaskW3X7-bench-reading.prompt.md"]["billable"], False)
        detail = self.client.get("/api/status/TaskW3X7-bench-reading.prompt.md").json()
        self.assertIs(detail["billable"], False)

    def test_the_card_model_says_who_takes_it(self):
        """D-AR10: the **Assigned:** line Route -Assign writes, read as `assigned`;
        no line is nobody, ""."""
        cards = self._by_file()
        self.assertEqual(cards["TaskW3X7-bench-reading.prompt.md"]["assigned"], "me")
        self.assertEqual(cards["Spike-K7M2-wallet-ticket.prompt.md"]["assigned"], "")
        detail = self.client.get("/api/status/TaskW3X7-bench-reading.prompt.md").json()
        self.assertEqual(detail["assigned"], "me")

    def test_the_card_model_serves_the_milestone_whole_and_the_tags(self):
        """The two planning lines and the tags (docs/hub/cards.md, "Milestone and sprint:
        two lines"): a card's own **Milestone:** line is its milestone, and a card with
        none reads its **Sprint:** line, as before -- served whole, beside the board's
        shortened `sprint`; `tags` is the Tags: line split. On the list and the detail."""
        cards = self._by_file()
        w3x7 = cards["TaskW3X7-bench-reading.prompt.md"]
        self.assertEqual(w3x7["milestone"], "v0.3 -- Share")
        # An old card: no milestone line, so its sprint line names it, whole.
        self.assertEqual(cards["141-recipe-search.prompt.md"]["milestone"], "RecipeBox\\Sprint 8")
        self.assertEqual(cards["141-recipe-search.prompt.md"]["sprint"], "Sprint 8")
        for card in cards.values():
            self.assertIn("milestone", card)
            self.assertIsInstance(card["tags"], list)
        detail = self.client.get("/api/status/TaskW3X7-bench-reading.prompt.md").json()
        self.assertEqual(detail["milestone"], "v0.3 -- Share")
        self.assertIsInstance(detail["tags"], list)

    def test_the_route_serves_how_many_commits_the_card_records(self):
        """What the web's Create PR gate reads: a placeholder is not a commit."""
        cards = self._by_file()
        self.assertEqual(cards["141-recipe-search.prompt.md"]["commits"], 0)
        self.assertEqual(cards["Spike-K7M2-wallet-ticket.prompt.md"]["commits"], 1)
        detail = self.client.get("/api/status/Spike-K7M2-wallet-ticket.prompt.md").json()
        self.assertEqual(detail["commits"], 1)

    def test_each_card_names_its_own_tracker_from_its_own_link(self):
        """#54: the tracker rule over the CARD'S link, never the Space's address --
        this Space is local, and it holds an ADO card and a GitHub card anyway.
        ``tracker`` is "none" exactly when ``linked`` is false: one rule, two faces."""
        cards = self._by_file()
        self.assertEqual(
            {f: c["tracker"] for f, c in cards.items()},
            {
                "141-recipe-search.prompt.md": "ado",
                "Spike-K7M2-wallet-ticket.prompt.md": "none",
                "Chore-Q4TN-rotate-the-keys.prompt.md": "none",
                "TaskW3X7-bench-reading.prompt.md": "none",
                "notes-from-tuesday.prompt.md": "none",
                "Task54-badge-the-tracker.prompt.md": "github",
            },
        )
        for c in cards.values():
            self.assertEqual(c["linked"], c["tracker"] != "none", c["file"])
        detail = self.client.get("/api/status/Task54-badge-the-tracker.prompt.md").json()
        self.assertEqual((detail["linked"], detail["tracker"]), (True, "github"))

    def test_the_detail_route_serves_the_same_model(self):
        body = self.client.get("/api/status/Spike-K7M2-wallet-ticket.prompt.md").json()
        self.assertEqual((body["id"], body["type"], body["linked"]), ("K7M2", "Spike", False))

    def test_the_detail_route_serves_the_files_absolute_path(self):
        """What a person hands to an assistant so it can open the record."""
        body = self.client.get("/api/status/Spike-K7M2-wallet-ticket.prompt.md").json()
        path = Path(body["path"])
        self.assertTrue(path.is_absolute(), body["path"])
        self.assertEqual(
            path, (Path(self.hub.name) / "test" / "current" / "Spike-K7M2-wallet-ticket.prompt.md").resolve()
        )
        self.assertTrue(path.is_file())

    def test_env_serves_the_lanes_names_for_the_org(self):
        """Org-scoped display names, keyed by the CONTRACT's words; an org that
        says nothing is called by those words, so an ADO user sees no change.
        """
        from agent.core.config import lane_names

        self.assertEqual(
            lane_names(None),
            {
                "Backlog": "Backlog",
                "Active": "Active",
                "In Progress": "In Progress",
                "Code Review": "Code Review",
                "Done": "Done",
            },
        )
        demo = lane_names(
            {
                "laneNames": {
                    "active": "To do",
                    "inProgress": "Doing",
                    "codeReview": "Waiting",
                    "done": "Done",
                    "planned": "ignored",
                }
            }
        )
        self.assertEqual(
            demo,
            {"Backlog": "Backlog", "Active": "To do", "In Progress": "Doing", "Code Review": "Waiting", "Done": "Done"},
        )
        self.assertEqual(lane_names({"laneNames": {"active": "  "}})["Active"], "Active")
        self.assertEqual(lane_names({"laneNames": "nonsense"})["Done"], "Done")
        body = self.client.get("/api/env").json()
        self.assertEqual(body["config"]["laneNames"]["Code Review"], "Code Review")

    def test_env_says_whether_the_first_run_banner_is_on(self):
        """firstRun.welcome: off unless this machine said so -- tkStart does, and
        the banner's Start the tour or Dismiss turns it off (Local Example, item 5)."""
        self.assertIs(self.client.get("/api/env").json()["config"]["firstRunWelcome"], False)
        local = Path(self.cfg.name) / "config.local.json"
        patch = json.loads(local.read_text(encoding="utf-8"))
        local.write_text(json.dumps({**patch, "firstRun": {"welcome": True}}), encoding="utf-8")
        self.assertIs(self.client.get("/api/env").json()["config"]["firstRunWelcome"], True)

    def test_env_carries_the_decks_put_away_on_this_machine(self):
        """deck.archived: the decks this machine has put away, by id (docs/modules/deck.md,
        "A deck's page"). None unless this machine said so; a list of ids is served in
        order, each once; anything that is not a list of strings reads as none."""
        self.assertEqual(self.client.get("/api/env").json()["config"]["deckArchived"], [])
        local = Path(self.cfg.name) / "config.local.json"
        patch = json.loads(local.read_text(encoding="utf-8"))
        for written, served in [
            (["the-toolkit"], ["the-toolkit"]),
            (["a", "b", "a", " ", 3], ["a", "b"]),
            ("the-toolkit", []),
            (None, []),
        ]:
            local.write_text(json.dumps({**patch, "deck": {"archived": written}}), encoding="utf-8")
            self.assertEqual(self.client.get("/api/env").json()["config"]["deckArchived"], served, written)

    def test_env_carries_the_wip_limit_and_only_a_real_one(self):
        """limits.inPlay: unset is null (no line, the opt-in rule); a whole number of 1
        or more is served as is; zero, negative, text and a bool are no limit. A line
        the board says, never a gate (docs/CONFIGURATION.md, `limits.inPlay`)."""
        local = Path(self.cfg.name) / "config.local.json"
        patch = json.loads(local.read_text(encoding="utf-8"))
        table = [
            (None, None),
            (5, 5),
            ("5", 5),
            (1, 1),
            (0, None),
            (-2, None),
            ("lots", None),
            (True, None),
            (2.5, None),
        ]
        for stored, served in table:
            limits = {} if stored is None else {"limits": {"inPlay": stored}}
            local.write_text(json.dumps({**patch, **limits}), encoding="utf-8")
            with self.subTest(stored=stored):
                self.assertEqual(self.client.get("/api/env").json()["config"]["inPlayLimit"], served)

    def test_env_tells_the_web_which_card_types_exist(self):
        """What the "New card" dialog offers: config's types, in config's order,
        a team's own included, the comment key not."""
        body = self.client.get("/api/env").json()
        self.assertEqual(body["cardTypes"], ["User Story", "Task", "Bug", "Spike", "Chore"])

    def test_the_agent_reads_the_type_table_without_its_comment_key(self):
        types = config.load_config()["workItemTypes"]
        self.assertNotIn("_comment", types)
        self.assertEqual(types["Chore"]["filePrefix"], "Chore-")
        self.assertEqual(types["Spike"]["filePrefix"], "Spike-")


if __name__ == "__main__":
    unittest.main()


@unittest.skipUnless(shutil.which("pwsh") or shutil.which("powershell"), "needs a PowerShell host")
class AFinishedWeekCanStillChange(unittest.TestCase):
    """``GET /billing?week=last`` was once cached in the agent's memory,
    on the theory that a finished week cannot change. It can: a card closed on
    Friday is marked not billable on Monday. Asked twice around that change, the
    route has to give two answers."""

    def setUp(self):
        today = date.today()
        self.last_monday = today - timedelta(days=today.weekday() + 7)
        created, closed = self.last_monday.isoformat(), (self.last_monday + timedelta(days=2)).isoformat()
        self.hub = tempfile.TemporaryDirectory()
        archive = Path(self.hub.name) / "test" / "archive"
        archive.mkdir(parents=True)
        (Path(self.hub.name) / "test" / "current").mkdir()
        self.card = archive / "TaskW3X7-bench-reading.prompt.md"
        self.card.write_text(
            f"# Task W3X7: Bench reading\n\n---\n\n**Created:** {created}\n**Closed:** {closed}\n", encoding="utf-8"
        )
        self.cfg = tempfile.TemporaryDirectory()
        base = Path(self.cfg.name)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "commandPrefix": "tk",
                    "features": {},
                    "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
                    "commands": {},
                    "workItemTypes": {"Task": {"filePrefix": "Task"}},
                }
            ),
            encoding="utf-8",
        )
        (base / "config.local.json").write_text(json.dumps({"promptsRoot": self.hub.name}), encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in self.patches:
            p.start()
        from agent.app import app

        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.cfg.cleanup()
        self.hub.cleanup()

    def test_marking_a_closed_card_changes_last_week(self):
        before = self.client.get("/api/billing?week=last").json()
        self.assertIn("W3X7", before["raw"], before)
        self.assertEqual((before["source"], before["nonBillable"]), ("stamps", 0))

        text = self.card.read_text(encoding="utf-8")
        self.card.write_text(text.replace("**Created:**", f"{stamp_billable()} no\n**Created:**"), encoding="utf-8")

        after = self.client.get("/api/billing?week=last").json()
        self.assertNotIn("W3X7", after["raw"], "last week was served from memory")
        self.assertEqual(after["nonBillable"], 1)

    def test_a_week_that_could_not_be_built_says_so_in_its_own_field(self):
        """`days: []` is what an empty week looks like too. The page reads `error`,
         so a broken billing can never again pass for a quiet week
        ."""
        from agent.ado import reporting

        with mock.patch.object(reporting, "BILLING_SCRIPT", Path(self.cfg.name) / "gone.ps1"):
            broken = self.client.get("/api/billing").json()
        self.assertEqual((broken["days"], broken["error"]), ([], "Billing script not found."))
        self.assertEqual(broken["raw"], broken["error"])

        # An EMPTY week is not an error: this hub's only card closed last week.
        quiet = self.client.get("/api/billing?week=current").json()
        self.assertEqual((quiet["days"], quiet["error"]), ([], ""))


class TheAgentNamesTheBillingFolder(unittest.TestCase):
    """Get-WeeklyBilling.ps1 resolves no Space: the agent passes -PromptsFolder on
    every call, so the folder Daily bills is the one the rest of the agent reads.
    The script used to work it out again, and the two disagreed where the agent
    falls back -- an activeSpace nobody declares is the agent's first Space, and
    was the script's hub root."""

    def _argv(self, default_cfg: dict, local_cfg: dict) -> tuple[list[str], str]:
        from agent.ado import reporting

        with tempfile.TemporaryDirectory() as cfg_dir, tempfile.TemporaryDirectory() as hub:
            base = Path(cfg_dir)
            (base / "config.default.json").write_text(json.dumps(default_cfg), encoding="utf-8")
            (base / "config.local.json").write_text(json.dumps(local_cfg), encoding="utf-8")
            seen: list[list[str]] = []

            def fake_run(args, **_kwargs):
                seen.append(list(args))
                quiet = '{"days": [], "raw": "No activity found."}'
                return subprocess.CompletedProcess(args, 0, stdout=quiet, stderr="")

            with (
                mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
                mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
                mock.patch.dict(os.environ, {"PROMPTS_ROOT": hub}, clear=False),
                mock.patch.object(reporting, "host_argv", lambda script, *a: ["pwsh", "-File", script, *a]),
                mock.patch.object(reporting.subprocess, "run", fake_run),
            ):
                resolved = str(config.load_config().get("promptsFolder", "") or "")
                answer = asyncio.run(reporting.get_billing())
        self.assertEqual(answer.error, "")
        self.assertEqual(len(seen), 1)
        argv = seen[0]
        return argv[argv.index("-PromptsFolder") + 1], resolved

    def test_unknown_active_org_matches_agent_fallback(self):
        passed, resolved = self._argv(
            {
                "activeSpace": "alpha",
                "spaces": [
                    {"slug": "alpha", "status": "local", "promptsFolder": "alpha-cards"},
                    {"slug": "beta", "status": "local", "promptsFolder": "beta-cards"},
                ],
            },
            {"activeSpace": "nobody-declares-this"},
        )
        self.assertEqual(resolved, "alpha-cards", "the agent's own fallback is its first Space")
        self.assertEqual(passed, resolved)

    def test_a_space_at_the_hub_root_is_passed_as_a_dot(self):
        passed, resolved = self._argv(
            {"activeSpace": "root", "spaces": [{"slug": "root", "status": "local", "promptsFolder": ""}]},
            {},
        )
        self.assertEqual((resolved, passed), ("", "."))
