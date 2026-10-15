"""A card whose issue is pinned says so: ``pinned`` on the card model.

The agent serves it: true when the card's tracker is github, its link is an
issue of the Space's repository, and the number is in that repository's pinned
set -- ONE ``gh api graphql`` call per repo. Only on a GitHub Space at Tier 1;
at Tier 2, on Azure DevOps and on no tracker ``gh`` is not asked. No network:
``_gh_json`` and the tier are stubbed, and the assertions are about what was
ASKED and what came back.

Run:  python3 -m pytest Tests/test_card_pinned.py
"""

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.ado import status
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

GH_ORG = "https://github.com/johnfrog76/toolkit"
ADO_ORG = "https://dev.azure.com/o"
ISSUE = "https://github.com/johnfrog76/toolkit/issues/{n}"


def _card(n, tracker="github", url=None):
    if url is None:
        url = ISSUE.format(n=n) if tracker == "github" else None
    return status.PromptInfo(
        file=f"Task{n}-x.prompt.md",
        id=str(n),
        tracker=tracker,
        linked=url is not None,
        ado_url=url,
        title="t",
        sprint="--",
        progress="--",
        checked=0,
        total=0,
        modified="",
    )


def _answer(numbers):
    return {"data": {"repository": {"pinnedIssues": {"nodes": [{"issue": {"number": n}} for n in numbers]}}}}


class ThePinnedFlag(unittest.TestCase):
    def setUp(self):
        status.pinned_cache_clear()
        self.addCleanup(status.pinned_cache_clear)

    def _run(self, cards, org=GH_ORG, tier=1, pinned=(7,), projects=()):
        cfg = {"org": org, "status": "active", "projects": list(projects)}
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(tier, tier == 1)),
            mock.patch.object(status, "_gh_json", return_value=(_answer(pinned), None)) as gh,
        ):
            status._pinned_cards(cards)
        return gh

    def test_a_pinned_issue_with_a_card_is_pinned_and_an_unpinned_one_is_not(self):
        cards = [_card(7), _card(8)]
        gh = self._run(cards)
        self.assertEqual([c.pinned for c in cards], [True, False])
        self.assertEqual(gh.call_count, 1)  # ONE call for the repo, not one per card
        argv = gh.call_args[0][0]
        self.assertEqual(argv[:3], ["gh", "api", "graphql"])
        self.assertIn("pinnedIssues", " ".join(argv))

    def test_a_card_with_no_link_is_not_pinned_and_asks_nothing(self):
        cards = [_card(7, tracker="none")]
        gh = self._run(cards)
        self.assertFalse(cards[0].pinned)
        gh.assert_not_called()

    def test_a_card_linked_to_another_repository_is_not_pinned(self):
        cards = [_card(7, url="https://github.com/someone/else/issues/7")]
        self._run(cards)
        self.assertFalse(cards[0].pinned)

    def test_tier_two_asks_gh_nothing(self):
        cards = [_card(7)]
        gh = self._run(cards, tier=2)
        self.assertFalse(cards[0].pinned)
        gh.assert_not_called()

    def test_an_azure_devops_space_asks_gh_nothing_and_its_card_is_never_pinned(self):
        cards = [_card(7, tracker="ado", url="https://dev.azure.com/o/p/_workitems/edit/7")]
        gh = self._run(cards, org=ADO_ORG)
        self.assertFalse(cards[0].pinned)
        gh.assert_not_called()

    def test_a_space_with_no_tracker_asks_nothing(self):
        cards = [_card(7)]
        gh = self._run(cards, org="")
        self.assertFalse(cards[0].pinned)
        gh.assert_not_called()

    def test_the_set_is_held_and_dropped_when_asked(self):
        cards = [_card(7)]
        cfg = {"org": GH_ORG, "status": "active", "projects": []}
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(status, "_gh_json", return_value=(_answer([7]), None)) as gh,
        ):
            status._pinned_cards(cards)
            status._pinned_cards(cards)
            self.assertEqual(gh.call_count, 1)  # the second read came from the hold
            status.pinned_cache_clear()
            status._pinned_cards(cards)
            self.assertEqual(gh.call_count, 2)

    def test_an_unanswered_gh_leaves_cards_unpinned_and_is_not_cached(self):
        cards = [_card(7)]
        cfg = {"org": GH_ORG, "status": "active", "projects": []}
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(status, "_gh_json", return_value=(None, "gh did not answer")) as gh,
        ):
            status._pinned_cards(cards)
            status._pinned_cards(cards)
        self.assertFalse(cards[0].pinned)
        self.assertEqual(gh.call_count, 2)


class EditItemDropsTheSet(unittest.TestCase):
    def test_the_bridge_clears_it_when_edititem_runs(self):
        import asyncio
        import subprocess

        from agent.ado import bridge

        status._pinned_cache["johnfrog76/toolkit"] = (1e12, {7})
        done = subprocess.CompletedProcess([], 0, stdout="ok", stderr="")
        with (
            mock.patch.object(bridge, "resolve_host", return_value=object()),
            mock.patch.object(bridge, "command_map", return_value={"EditItem": "Edit-WorkItem"}),
            mock.patch.object(bridge, "_run", return_value=done),
        ):
            asyncio.run(bridge.run_command("EditItem", bridge.CommandRequest(params=["7", "-Unpin"])))
        self.assertEqual(status._pinned_cache, {})


if __name__ == "__main__":
    unittest.main()
