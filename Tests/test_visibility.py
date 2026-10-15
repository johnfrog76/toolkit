"""A Space says whether its repository is public -- the agent's half.

GET /api/visibility reads a GitHub Space's repository visibility once per
repository (``gh api repos/{owner}/{repo}`` -> ``visibility``), caches it, and
serves ``public``, ``private`` or ``unknown`` -- never a guess. An Azure DevOps
Space, or one with no tracker, has none (``supported: false``). Below Tier 1
the tracker is not asked, so the answer is ``unknown``.

No network: gh and the tier probe are stubbed.

Run:  python3 -m pytest Tests/test_visibility.py
"""

import sys
import unittest
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
    from agent.core import consts as C
except Exception as exc:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(exc).__name__}: {exc})")

ADO = "https://dev.azure.com/acme"
DECK = "https://github.com/johnfrog76/connected-deck"
STUDIO = "https://github.com/johnfrog76"

CFG = {
    "org": DECK,
    "status": "active",
    "projects": [],
    "spaces": [
        {"slug": "acme", "org": ADO, "status": "active", "projects": [{"name": "P", "repo": "p"}]},
        {"slug": "deck", "org": DECK, "status": "active", "projects": []},
        {
            "slug": "wasteland",
            "org": STUDIO,
            "status": "active",
            "projects": [{"name": "A", "repo": "open-one"}, {"name": "B", "repo": "closed-one"}],
        },
        {"slug": "own", "org": "", "status": "local", "projects": []},
        {"slug": "demo", "org": DECK, "status": "local", "projects": []},
    ],
}


class TheWords(unittest.TestCase):
    """gh's answer, as the contract's word -- one row per input the rule tells apart."""

    def test_the_table(self):
        for raw, word in [
            ("PUBLIC", "public"),
            ("public", "public"),
            ("PRIVATE", "private"),
            ("INTERNAL", "private"),
            ("", "unknown"),
            (None, "unknown"),
            ("something-new", "unknown"),
        ]:
            with self.subTest(raw=raw):
                self.assertEqual(accounting.visibility_word(raw), word)

    def test_the_words_are_the_contracts(self):
        self.assertEqual(
            (C.visibility_public(), C.visibility_private(), C.visibility_unknown()),
            ("public", "private", "unknown"),
        )

    def test_a_space_of_several_repositories(self):
        for words, folded in [
            (["private", "public"], "public"),
            (["public", "unknown"], "public"),
            (["private", "private"], "private"),
            (["private", "unknown"], "unknown"),
            ([], "unknown"),
        ]:
            with self.subTest(words=words):
                self.assertEqual(accounting.fold_visibility(words), folded)


class TheRoute(unittest.TestCase):
    def setUp(self):
        accounting.visibility_cache_clear()
        self.client = TestClient(app)
        self.answers = {
            "repos/johnfrog76/connected-deck": ({"visibility": "PUBLIC"}, None),
            "repos/johnfrog76/open-one": ({"visibility": "public"}, None),
            "repos/johnfrog76/closed-one": ({"visibility": "private"}, None),
        }
        self.calls: list[list[str]] = []

    def tearDown(self):
        accounting.visibility_cache_clear()

    def _gh(self, cmd, timeout=30):
        self.calls.append(list(cmd))
        return self.answers.get(cmd[2], (None, "gh did not answer"))

    def _get(self, path: str, tier: int = 1):
        with (
            mock.patch.object(accounting, "load_config", return_value=CFG),
            mock.patch.object(accounting, "_resolve_tier", return_value=(tier, "")),
            mock.patch.object(accounting, "_gh_json", side_effect=self._gh),
        ):
            return self.client.get(path)

    def test_a_public_repository_says_public(self):
        res = self._get("/api/visibility?space=deck")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["visibility"], "public")
        self.assertTrue(res.json()["supported"])
        self.assertEqual(res.json()["repos"], [{"repo": "johnfrog76/connected-deck", "visibility": "public"}])
        self.assertEqual(self.calls, [["gh", "api", "repos/johnfrog76/connected-deck"]])

    def test_without_the_argument_it_is_the_active_spaces(self):
        res = self._get("/api/visibility")
        self.assertEqual(res.json()["visibility"], "public")

    def test_an_owner_grained_space_is_public_when_any_repository_is(self):
        res = self._get("/api/visibility?space=wasteland")
        self.assertEqual(res.json()["visibility"], "public")
        self.assertEqual([r["visibility"] for r in res.json()["repos"]], ["public", "private"])

    def test_private_when_every_repository_is(self):
        self.answers["repos/johnfrog76/connected-deck"] = ({"visibility": "PRIVATE"}, None)
        self.assertEqual(self._get("/api/visibility?space=deck").json()["visibility"], "private")

    def test_a_tracker_that_does_not_answer_is_unknown_not_a_guess(self):
        del self.answers["repos/johnfrog76/connected-deck"]
        res = self._get("/api/visibility?space=deck")
        self.assertEqual(res.json()["visibility"], "unknown")
        self.assertTrue(res.json()["supported"])

    def test_below_tier_1_gh_is_not_asked_and_the_answer_is_unknown(self):
        res = self._get("/api/visibility?space=demo", tier=2)
        self.assertEqual(res.json()["visibility"], "unknown")
        self.assertEqual(self.calls, [])

    def test_an_azure_devops_space_has_no_visibility_and_gh_is_never_asked(self):
        res = self._get("/api/visibility?space=acme")
        self.assertEqual(res.json(), {"supported": False, "visibility": "", "repos": []})
        self.assertEqual(self.calls, [])

    def test_a_space_with_no_tracker_has_none_either(self):
        res = self._get("/api/visibility?space=own")
        self.assertFalse(res.json()["supported"])
        self.assertEqual(self.calls, [])

    def test_an_unknown_space_is_404(self):
        self.assertEqual(self._get("/api/visibility?space=nowhere").status_code, 404)

    def test_an_answer_is_read_once_per_repository(self):
        self._get("/api/visibility?space=deck")
        self._get("/api/visibility?space=deck")
        self._get("/api/visibility?space=demo")  # the same repo, another Space -- Tier 1 here
        self.assertEqual(len(self.calls), 1)

    def test_an_unanswered_read_is_asked_again(self):
        del self.answers["repos/johnfrog76/connected-deck"]
        self._get("/api/visibility?space=deck")
        self._get("/api/visibility?space=deck")
        self.assertEqual(len(self.calls), 2)

    # The Spaces card's Refresh: ?refresh=1 goes past the cache for THIS
    # Space's repositories, the way /env?refresh=1 goes past the probe's.
    def test_refresh_asks_again_past_the_cache(self):
        self._get("/api/visibility?space=deck")
        self.answers["repos/johnfrog76/connected-deck"] = ({"visibility": "PRIVATE"}, None)
        self.assertEqual(self._get("/api/visibility?space=deck").json()["visibility"], "public")
        self.assertEqual(len(self.calls), 1)
        res = self._get("/api/visibility?space=deck&refresh=1")
        self.assertEqual(res.json()["visibility"], "private")
        self.assertEqual(len(self.calls), 2)
        # ... and the fresh answer is the one cached now.
        self.assertEqual(self._get("/api/visibility?space=deck").json()["visibility"], "private")
        self.assertEqual(len(self.calls), 2)

    def test_refresh_drops_only_that_spaces_repositories(self):
        self._get("/api/visibility?space=deck")
        self._get("/api/visibility?space=wasteland")
        self.assertEqual(len(self.calls), 3)
        self._get("/api/visibility?space=wasteland&refresh=1")
        self.assertEqual(len(self.calls), 5)
        self._get("/api/visibility?space=deck")
        self.assertEqual(len(self.calls), 5)

    def test_refresh_goes_past_the_tier_probe_too(self):
        with (
            mock.patch.object(accounting, "load_config", return_value=CFG),
            mock.patch.object(accounting, "_resolve_tier", return_value=(1, "")) as tier,
            mock.patch.object(accounting, "_gh_json", side_effect=self._gh),
        ):
            self.client.get("/api/visibility?space=deck")
            self.client.get("/api/visibility?space=deck&refresh=1")
        self.assertEqual([c.args[2] for c in tier.call_args_list], [False, True])

    def test_refresh_on_a_space_with_no_visibility_asks_nothing(self):
        res = self._get("/api/visibility?space=acme&refresh=1")
        self.assertFalse(res.json()["supported"])
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
