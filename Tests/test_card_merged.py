"""A Code Review card whose pull request is merged says so: ``merged`` on the
card model -- what the web's Land is offered on (cardActions.ts).

The pinned set's twin (test_card_pinned.py): ONE ``gh pr list --state merged``
per repository a Code Review card's pull request is in, held briefly. Only on a
GitHub Space at Tier 1, and only for a card in Code Review whose ``PR URL:`` is
a GitHub pull request; at Tier 2, on Azure DevOps, on no tracker and for every
other card ``gh`` is not asked. No network: ``_gh_json`` and the tier are
stubbed, and the assertions are about what was ASKED and what came back.

Run:  python3 -m pytest Tests/test_card_merged.py
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
    from agent.core.consts import status_active, status_code_review
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

GH_ORG = "https://github.com/acme/widgets"
ADO_ORG = "https://dev.azure.com/o"
PR = "https://github.com/acme/widgets/pull/{n}"


def _card(n, pr_url=None, lane=None):
    return status.PromptInfo(
        file=f"Task{n}-x.prompt.md",
        id=str(n),
        tracker="github",
        title="t",
        sprint="--",
        progress="--",
        checked=0,
        total=0,
        modified="",
        pr_url=pr_url if pr_url is not None else PR.format(n=n + 100),
        status=lane or status_code_review(),
    )


class TheMergedFlag(unittest.TestCase):
    def setUp(self):
        status.merged_cache_clear()
        self.addCleanup(status.merged_cache_clear)

    def _run(self, cards, org=GH_ORG, tier=1, merged=(175,), why=None):
        cfg = {"org": org, "status": "active", "projects": []}
        answer = None if why else [{"number": n} for n in merged]
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(tier, tier == 1)),
            mock.patch.object(status, "_gh_json", return_value=(answer, why)) as gh,
        ):
            status._merged_cards(cards)
        return gh

    def test_a_code_review_card_whose_pr_merged_is_merged_and_an_open_one_is_not(self):
        cards = [_card(75), _card(76)]  # pull requests 175 and 176
        gh = self._run(cards)
        self.assertEqual([c.merged for c in cards], [True, False])
        self.assertEqual(gh.call_count, 1)  # ONE call for the repository, not one per card
        argv = gh.call_args[0][0]
        self.assertEqual(argv[:3], ["gh", "pr", "list"])
        self.assertIn("--repo", argv)
        self.assertEqual(argv[argv.index("--repo") + 1], "acme/widgets")
        self.assertEqual(argv[argv.index("--state") + 1], "merged")
        self.assertFalse(any("&" in a for a in argv))  # a query travels as fields, never a URL

    def test_a_card_not_in_code_review_is_never_merged_and_asks_nothing(self):
        cards = [_card(75, lane=status_active())]
        gh = self._run(cards)
        self.assertFalse(cards[0].merged)
        gh.assert_not_called()

    def test_a_card_with_no_pr_url_asks_nothing(self):
        cards = [_card(75, pr_url="")]
        gh = self._run(cards)
        self.assertFalse(cards[0].merged)
        gh.assert_not_called()

    def test_an_azure_devops_pull_request_is_not_read(self):
        cards = [_card(75, pr_url="https://dev.azure.com/o/p/_git/r/pullrequest/175")]
        gh = self._run(cards)
        self.assertFalse(cards[0].merged)
        gh.assert_not_called()

    def test_tier_two_an_azure_devops_space_and_no_tracker_ask_gh_nothing(self):
        for org, tier in ((GH_ORG, 2), (ADO_ORG, 1), ("", 1)):
            with self.subTest(org=org, tier=tier):
                status.merged_cache_clear()
                cards = [_card(75)]
                gh = self._run(cards, org=org, tier=tier)
                self.assertFalse(cards[0].merged)
                gh.assert_not_called()

    def test_a_pull_request_in_another_repository_is_asked_about_in_that_repository(self):
        cards = [_card(75, pr_url="https://github.com/acme/deck/pull/175")]
        gh = self._run(cards)
        self.assertTrue(cards[0].merged)
        argv = gh.call_args[0][0]
        self.assertEqual(argv[argv.index("--repo") + 1], "acme/deck")

    def test_the_set_is_held(self):
        cards = [_card(75)]
        cfg = {"org": GH_ORG, "status": "active", "projects": []}
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(status, "_gh_json", return_value=([{"number": 175}], None)) as gh,
        ):
            status._merged_cards(cards)
            status._merged_cards(cards)
            self.assertEqual(gh.call_count, 1)  # the second read came from the hold
            status.merged_cache_clear()
            status._merged_cards(cards)
            self.assertEqual(gh.call_count, 2)

    def test_an_unanswered_gh_leaves_cards_unmerged_and_is_not_cached(self):
        cards = [_card(75)]
        cfg = {"org": GH_ORG, "status": "active", "projects": []}
        with (
            mock.patch.object(status, "load_config", return_value=cfg),
            mock.patch.object(status, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(status, "_gh_json", return_value=(None, "gh did not answer")) as gh,
        ):
            status._merged_cards(cards)
            status._merged_cards(cards)
        self.assertFalse(cards[0].merged)
        self.assertEqual(gh.call_count, 2)


if __name__ == "__main__":
    unittest.main()
