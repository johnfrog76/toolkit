"""The provider profile (``agent/core/model.py``).

One module calls the model for every model-assisted route. What it is held
to: the model id is ``ai.model`` in config and nothing else; a missing key, or
a missing SDK, is a stated reason BEFORE any network call -- the sentence the
routes serve as 412; and the one call it makes carries the profile's model,
the caller's system prompt and the low-effort setting. The SDK itself is
stood in for: no suite here reaches the network.
"""

from __future__ import annotations

import asyncio
import os
import sys
import types
import unittest
from unittest import mock

from agent.core import model


class ModelId(unittest.TestCase):
    def test_the_shipped_config_names_the_model(self):
        # No patch: the real config.default.json, which ships ai.model.
        self.assertEqual(model.model_id(), model.DEFAULT_MODEL)

    def test_config_wins_over_the_fallback(self):
        with mock.patch.object(model, "load_config", return_value={"ai": {"model": "claude-sonnet-5-5"}}):
            self.assertEqual(model.model_id(), "claude-sonnet-5-5")

    def test_a_config_with_no_ai_block_falls_back_to_the_literal(self):
        for cfg in ({}, {"ai": None}, {"ai": {}}, {"ai": {"model": "  "}}, {"ai": "claude-x"}):
            with self.subTest(cfg=cfg), mock.patch.object(model, "load_config", return_value=cfg):
                self.assertEqual(model.model_id(), model.DEFAULT_MODEL)

    def test_the_shipped_default_and_the_literal_agree(self):
        import json

        from agent.core.config import DEFAULT_CONFIG_PATH

        shipped = json.loads(DEFAULT_CONFIG_PATH.read_text(encoding="utf-8-sig"))
        self.assertEqual(
            shipped["ai"]["model"], model.DEFAULT_MODEL, "config.default.json and core/model.py name different models"
        )


class Declines(unittest.TestCase):
    def _no_keys(self):
        return mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "", "CLAUDE_API_KEY": ""})

    def test_no_key_is_a_stated_reason_before_any_import(self):
        with (
            self._no_keys(),
            mock.patch.dict(sys.modules, {"anthropic": None}),
            self.assertRaises(model.ModelUnavailable) as held,
        ):
            asyncio.run(model.complete("hi", system="s"))
        self.assertIn("ANTHROPIC_API_KEY", str(held.exception))

    def test_the_fallback_key_name_counts(self):
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "", "CLAUDE_API_KEY": "sk-fallback"}):
            from agent.core.config import anthropic_api_key, anthropic_configured

            self.assertEqual(anthropic_api_key(), "sk-fallback")
            self.assertTrue(anthropic_configured())

    def test_no_sdk_is_a_stated_reason_naming_the_install(self):
        with (
            mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-test"}),
            mock.patch.dict(sys.modules, {"anthropic": None}),
            self.assertRaises(model.ModelUnavailable) as held,
        ):
            asyncio.run(model.complete("hi", system="s"))
        self.assertIn("requirements.txt", str(held.exception))


class TheCall(unittest.TestCase):
    """A fake ``anthropic`` module records the one call the profile makes."""

    def _fake_sdk(self, record: dict):
        class _Block:
            def __init__(self, type_, text=""):
                self.type = type_
                self.text = text

        class _Messages:
            async def create(self, **kwargs):
                record.update(kwargs)
                return types.SimpleNamespace(
                    content=[
                        _Block("thinking", ""),
                        _Block("text", ' {"a": 1} '),
                        _Block("text", ""),
                    ]
                )

        class _AsyncAnthropic:
            def __init__(self, **kwargs):
                record["client"] = kwargs
                self.messages = _Messages()

        return types.SimpleNamespace(AsyncAnthropic=_AsyncAnthropic)

    def test_the_call_carries_the_profile(self):
        seen: dict = {}
        with (
            mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-test"}),
            mock.patch.dict(sys.modules, {"anthropic": self._fake_sdk(seen)}),
            mock.patch.object(model, "load_config", return_value={"ai": {"model": "claude-test-1"}}),
        ):
            text = asyncio.run(model.complete("the prompt", system="the system", max_tokens=42))
        self.assertEqual(text, '{"a": 1}', "text blocks joined and stripped; the thinking block ignored")
        self.assertEqual(seen["client"]["api_key"], "sk-test")
        self.assertEqual(seen["model"], "claude-test-1")
        self.assertEqual(seen["max_tokens"], 42)
        self.assertEqual(seen["system"], "the system")
        self.assertEqual(seen["messages"], [{"role": "user", "content": "the prompt"}])
        self.assertEqual(seen["output_config"], {"effort": model.EFFORT})

    def test_describe_says_the_model_and_whether_a_key_is_set(self):
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "", "CLAUDE_API_KEY": ""}):
            d = model.describe()
        self.assertEqual(d["model"], model.model_id())
        self.assertFalse(d["configured"])
        self.assertIn("sdk", d)


try:
    import anthropic as _real_sdk
    import httpx2 as _httpx  # the SDK's HTTP layer since 1.0; it rejects a plain httpx client
except ImportError:  # pragma: no cover -- the stubbed tests above still run
    _real_sdk = _httpx = None


_NO_SDK = "the anthropic SDK (and its httpx2) is not installed; CI installs requirements"


@unittest.skipUnless(_real_sdk and _httpx, _NO_SDK)
class TheRealSdk(unittest.TestCase):
    """The stub above accepts any keyword, so a renamed or removed SDK parameter
    would pass it. This runs ``complete()`` through the REAL client with the HTTP
    transport replaced by a canned response: no network, no key that is real."""

    def test_complete_runs_end_to_end_through_the_installed_sdk(self):
        sent: dict = {}

        def handler(request):
            import json

            sent["path"] = request.url.path
            sent["body"] = json.loads(request.content)
            return _httpx.Response(
                200,
                json={
                    "id": "msg_test",
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-test-1",
                    "content": [{"type": "text", "text": " hello "}],
                    "stop_reason": "end_turn",
                    "stop_sequence": None,
                    "usage": {"input_tokens": 1, "output_tokens": 1},
                },
            )

        real = _real_sdk.AsyncAnthropic

        def client(**kwargs):
            # model.py's own keywords go to the real constructor; only the transport is ours.
            return real(http_client=_httpx.AsyncClient(transport=_httpx.MockTransport(handler)), **kwargs)

        with (
            mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-dummy-not-real"}),
            mock.patch.object(_real_sdk, "AsyncAnthropic", client),
            mock.patch.object(model, "load_config", return_value={"ai": {"model": "claude-test-1"}}),
        ):
            text = asyncio.run(model.complete("the prompt", system="the system", max_tokens=42))
        self.assertEqual(text, "hello")
        self.assertEqual(sent["path"], "/v1/messages")
        body = sent["body"]
        self.assertEqual(body["model"], "claude-test-1")
        self.assertEqual(body["max_tokens"], 42)
        self.assertEqual(body["system"], "the system")
        self.assertEqual(body["messages"], [{"role": "user", "content": "the prompt"}])
        self.assertEqual(body["output_config"], {"effort": model.EFFORT})


class NoSecondTransport(unittest.TestCase):
    def test_no_route_module_calls_the_api_itself(self):
        from agent.core.config import REPO_ROOT

        offenders = []
        for py in sorted((REPO_ROOT / "agent").rglob("*.py")):
            if py.name == "model.py" or "__pycache__" in py.parts:
                continue
            text = py.read_text(encoding="utf-8")
            if "api.anthropic.com" in text or "x-api-key" in text or "_ANTHROPIC_MODEL" in text:
                offenders.append(py.relative_to(REPO_ROOT).as_posix())
        self.assertEqual(offenders, [], "a second transport: " + ", ".join(offenders))


if __name__ == "__main__":
    unittest.main()
