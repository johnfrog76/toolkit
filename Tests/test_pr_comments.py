"""``GET /api/pr-comments`` is a file read, at every tier.

The list route reports the cards in ``current/`` that carry open review
threads. Those threads were written into the cards by ``GetPRComments`` at some
earlier moment, so whether Azure DevOps is reachable NOW says nothing about
them -- yet the route used to demand Tier 1 on any org that was not ``local``
and answer ``count=0`` with no reason when the probe failed.
These
tests run the route against a copy of the fixture hub on an ACTIVE org, with the
tier probe stubbed to fail and instrumented, and assert both that the comments
are listed and that nothing probed.

The same hub serves the model route's tests: ``suggest`` declines
with a typed 412 naming ``ANTHROPIC_API_KEY`` and sends the prompt file in
``agentic/``; ``save`` goes through the agent's one card writer and keeps a
CRLF card CRLF.

Run directly:  python3 Tests/test_pr_comments.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import pr_comments
    from agent.core import config, model, tier
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURE_HUB = REPO_ROOT / "Tests" / "fixtures" / "hub"
# A card with two review rounds and one open thread, in the shape GetPRComments
# writes -- the same fixture the parsers are held to.
MULTI_ROUND = REPO_ROOT / "Tests" / "fixtures" / "parsers" / "pr-multi-round.md"
CARD_NAME = "62-carousel-pause-control-missing.prompt.md"


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


class _PrCommentsCase(unittest.TestCase):
    """A copy of the fixture hub, the org ACTIVE, and the ADO probe failing."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.hub = base / "hub"
        shutil.copytree(FIXTURE_HUB, self.hub)
        shutil.copy(MULTI_ROUND, self.hub / "test" / "current" / CARD_NAME)

        default_path = base / "config.default.json"
        local_path = base / "config.local.json"
        _write(
            default_path,
            {
                "activeSpace": "test",
                "promptsRoot": str(self.hub),
                "spaces": [
                    {
                        "slug": "test",
                        "status": "active",
                        "promptsFolder": "test",
                        "org": "https://dev.azure.com/YOUR-ADO-ORG",
                        "projects": [{"name": "YourProject", "repo": "your-repo"}],
                    }
                ],
            },
        )
        _write(local_path, {})

        # Tier 2: the probe fails. Instrumented, so the test can say it was
        # never asked -- a signed-in machine must not be able to pass this.
        self.probe = mock.Mock(return_value=False)
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local_path),
            mock.patch.object(tier, "_probe_ado", self.probe),
            mock.patch.object(tier, "_probe_tracker_cached", self.probe),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in self.patches:
            p.start()

        app = FastAPI()
        app.include_router(pr_comments.api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self._tmp.cleanup()


class PrCommentsListTests(_PrCommentsCase):
    """The list route is a file read at every tier."""

    def test_an_active_space_at_tier_2_lists_the_open_threads(self):
        body = self.client.get("/api/pr-comments").json()
        self.assertEqual(body["count"], 1, body)
        item = body["items"][0]
        self.assertEqual(item["file"], CARD_NAME)
        self.assertEqual(item["pr_id"], 140123)
        self.assertEqual(item["open_count"], 1)
        self.assertEqual(item["total_count"], 2)
        self.assertIn("Carousel", item["title"])

    def test_the_route_never_probes_ado(self):
        self.client.get("/api/pr-comments")
        self.assertEqual(self.probe.call_count, 0, "a file read asked the tracker")

    def test_the_source_has_no_tier_gate(self):
        """The gate does not come back under another name."""
        source = (REPO_ROOT / "agent" / "ado" / "pr_comments.py").read_text(encoding="utf-8")
        self.assertNotIn("_resolve_tier", source)
        self.assertNotIn("load_config", source)

    def test_the_detail_route_reads_the_same_card(self):
        body = self.client.get(f"/api/pr-comments/{CARD_NAME}").json()
        self.assertEqual(body["round_num"], 2)
        self.assertEqual(body["open_count"], 1)
        self.assertEqual([c["thread_id"] for c in body["comments"]], [5000001, 5000002])

    def test_a_card_with_no_open_thread_is_not_listed(self):
        card = self.hub / "test" / "current" / CARD_NAME
        text = card.read_text(encoding="utf-8")
        text = text.replace("Decision:\nReply:\n", "Decision: take\nReply: Done.\n")
        card.write_text(text, encoding="utf-8")
        body = self.client.get("/api/pr-comments").json()
        self.assertEqual(body["count"], 0, body)

    def test_a_hub_with_no_current_folder_is_empty_not_an_error(self):
        shutil.rmtree(self.hub / "test" / "current")
        r = self.client.get("/api/pr-comments")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {"count": 0, "items": []})


class SuggestTests(_PrCommentsCase):
    """``suggest`` declines before it builds anything when there is no key,
    and the prompt it sends is the file in agentic/, not an f-string. The
    model call is the profile's (``core/model.complete``), and that is what
    the suite stands in for."""

    BODY = {
        "thread_id": 5000002,
        "comment_text": "Use const.",
        "file_path": "/src/Carousel.tsx",
        "line": 18,
        "reviewer": "bot",
        "code_suggestion": "",
    }

    def test_no_key_is_a_typed_decline_naming_the_variable(self):
        called = []

        async def fake(prompt, **kwargs):
            called.append(1)
            return ""

        with (
            mock.patch.dict(os.environ, {}, clear=False),
            mock.patch.object(model, "_client", side_effect=model.ModelUnavailable(model.NO_MODEL_KEY_DETAIL)),
        ):
            os.environ.pop("ANTHROPIC_API_KEY", None)
            os.environ.pop("CLAUDE_API_KEY", None)
            r = self.client.post(f"/api/pr-comments/{CARD_NAME}/suggest", json=self.BODY)
        self.assertEqual(r.status_code, pr_comments.NO_MODEL_KEY_STATUS)
        self.assertLess(r.status_code, 500, "a missing key is not the model failing")
        self.assertIn("ANTHROPIC_API_KEY", r.json()["detail"])
        self.assertEqual(called, [], "the model was called with no key")

    def test_no_sdk_is_the_same_shape_of_decline_naming_the_install(self):
        with mock.patch.object(model, "_client", side_effect=model.ModelUnavailable(model.NO_SDK_DETAIL)):
            r = self.client.post(f"/api/pr-comments/{CARD_NAME}/suggest", json=self.BODY)
        self.assertEqual(r.status_code, pr_comments.NO_MODEL_KEY_STATUS)
        self.assertIn("requirements.txt", r.json()["detail"])

    def test_the_prompt_is_read_from_the_file_in_agentic(self):
        seen = {}

        async def fake(prompt, **kwargs):
            seen["prompt"] = prompt
            seen["kwargs"] = kwargs
            return json.dumps({"recommendation": "take", "confidence": "high", "draft_reply": "Done."})

        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"}), mock.patch.object(model, "complete", fake):
            r = self.client.post(f"/api/pr-comments/{CARD_NAME}/suggest", json=self.BODY)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["recommendation"], "take")
        self.assertEqual(r.json()["draft_reply"], "Done.")
        self.assertIn("system", seen["kwargs"])
        prompt = seen["prompt"]
        instruction = pr_comments.prompt_instruction(
            (REPO_ROOT / "agentic" / "pr-suggest.prompt.md").read_text(encoding="utf-8")
        )
        # The file's own first line, verbatim, and its rules; then the thread's fields in place.
        self.assertTrue(instruction.strip().startswith("Analyze this PR code review comment"), instruction[:80])
        self.assertTrue(prompt.startswith(instruction.strip().splitlines()[0]), prompt[:80])
        self.assertIn('"recommendation": one of "take", "reject", or "modify"', prompt)
        self.assertIn("- File: /src/Carousel.tsx", prompt)
        self.assertIn("- Line: 18", prompt)
        self.assertIn("- Comment: Use const.", prompt)
        self.assertIn("- Code suggestion: none", prompt)
        self.assertNotIn("{file_path}", prompt)
        self.assertNotIn("is sent verbatim", prompt, "the prose above the fence leaked")
        self.assertNotIn("description:", prompt, "the frontmatter leaked")

    def test_a_model_that_answers_prose_is_a_502_not_a_guess(self):
        async def fake(prompt, **kwargs):
            return "Sure! Here is my take: accept it."

        with mock.patch.object(model, "complete", fake):
            r = self.client.post(f"/api/pr-comments/{CARD_NAME}/suggest", json=self.BODY)
        self.assertEqual(r.status_code, 502)

    def test_the_prompt_file_exists_and_is_documented(self):
        self.assertTrue(pr_comments.SUGGEST_PROMPT_PATH.is_file())
        self.assertIn("pr-suggest", (REPO_ROOT / "agentic" / "README.md").read_text(encoding="utf-8"))
        source = (REPO_ROOT / "agent" / "ado" / "pr_comments.py").read_text(encoding="utf-8")
        self.assertNotIn("Analyze this PR code review comment", source, "the prompt is still inline")


class SaveIsRetired(_PrCommentsCase):
    """The agent writes no card from this module. ``save`` was a second
    writer of the card's ``Decision:`` and ``Reply:`` slots beside ``ReplyPR``,
    which the page already runs through the bridge and which fills the slot
    through ``Write-CardText``. Retired, not hidden: the route is gone, and so
    is the module's import of the Python card writer."""

    def test_the_route_is_gone(self):
        r = self.client.post(
            f"/api/pr-comments/{CARD_NAME}/save", json={"thread_id": 5000002, "decision": "take", "reply": "Done."}
        )
        self.assertIn(r.status_code, (404, 405))

    def test_the_module_imports_no_card_writer(self):
        source = (REPO_ROOT / "agent" / "ado" / "pr_comments.py").read_text(encoding="utf-8")
        self.assertNotIn(
            "write_card_text", source.split('"""', 2)[2], "pr_comments.py reaches for the card writer again"
        )
        self.assertNotIn("api.anthropic.com", source, "the transport is back in the route module")

    def test_the_page_posts_replies_through_the_verb(self):
        page = (REPO_ROOT / "web" / "src" / "modules" / "ado" / "PRCommentsDetail.tsx").read_text(encoding="utf-8")
        self.assertIn('name: "ReplyPR"', page)
        self.assertNotIn("/save", page)


if __name__ == "__main__":
    unittest.main()
