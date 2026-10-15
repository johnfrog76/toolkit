"""Tests for the communication engine (agent/communication/comms.py).

Tone formatting, recipient resolution, the master switch, validation and
rejection, dry-run, and fail-soft failure handling. The network POST
(_post_to_webhook) is always mocked -- these tests never reach Teams.

Carried across the module carve with every assertion unchanged: the engine
moved packages, and this file is the evidence that it did not change behaviour
while it moved. Only the import path and the harness above it are new.

Run directly:  python3 Tests/test_comms_format.py
Or:            python3 -m pytest Tests/test_comms_format.py
"""

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent.communication import comms
except Exception as e:  # pragma: no cover
    skip_module(f"cannot import comms ({type(e).__name__}: {e})")


# A config with the master switch ON and one channel recipient.
ENABLED_CFG = {
    "activeSpace": "test",
    "features": {"communication": True},
    "communication": {
        "recipients": {
            "dev-team-pr": {"type": "channel", "display": "Dev Team PR", "webhookEnv": "TEAMS_WEBHOOK_DEV_TEAM_PR"},
            "manager": {"type": "person", "display": "My Manager", "upn": "m@org.com"},
        }
    },
}

DISABLED_CFG = {"activeSpace": "demo", "features": {"communication": False}, "communication": {}}


# Silence the engine's log writes so the suite never pollutes usage.*.log.
_log_patch = None


def setUpModule():
    global _log_patch
    _log_patch = mock.patch.object(comms.log_writer, "write_log")
    _log_patch.start()


def tearDownModule():
    if _log_patch:
        _log_patch.stop()


def _msg(**over):
    base = {
        "caller": "test",
        "recipient": "dev-team-pr",
        "subject": "PR ready",
        "sections": [
            {"heading": "PR", "body": "[#1 Fix](https://x)"},
            {"heading": "Ask", "body": "Please review"},
        ],
        "tone": "broadcast",
    }
    base.update(over)
    return base


class FormattingTests(unittest.TestCase):
    def test_broadcast_shape(self):
        out = comms._render(_msg(tone="broadcast"))
        self.assertIn("**PR ready**", out)
        self.assertIn("**PR**: [#1 Fix](https://x)", out)
        self.assertIn("**Ask**: Please review", out)

    def test_alert_warning_marker(self):
        out = comms._render(_msg(tone="alert"))
        self.assertTrue(out.startswith("**⚠ PR ready**"))

    def test_personal_drops_headings(self):
        out = comms._render(_msg(tone="personal"))
        self.assertIn("**PR ready**", out)
        self.assertNotIn("**PR**:", out)
        self.assertIn("[#1 Fix](https://x)", out)

    def test_empty_heading_renders_body_only(self):
        out = comms._render(_msg(sections=[{"heading": "", "body": "just prose"}]))
        self.assertIn("just prose", out)
        self.assertNotIn("**: just prose", out)

    def test_unicode_dashes_normalized(self):
        out = comms._render(_msg(subject="A — B – C"))
        self.assertNotIn("—", out)
        self.assertNotIn("–", out)
        self.assertIn("A -- B - C", out)


class PayloadTests(unittest.TestCase):
    def test_workflows_adaptive_card_envelope(self):
        # A Workflows webhook expects the Adaptive Card envelope, not {"text"}.
        p = comms._build_payload("**hi**")
        self.assertEqual(p["type"], "message")
        card = p["attachments"][0]
        self.assertEqual(card["contentType"], "application/vnd.microsoft.card.adaptive")
        block = card["content"]["body"][0]
        self.assertEqual(block["type"], "TextBlock")
        self.assertEqual(block["text"], "**hi**")
        self.assertTrue(block["wrap"])


class RecipientResolutionTests(unittest.TestCase):
    def test_explicit_webhook_env(self):
        with mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_DEV_TEAM_PR": "https://hook"}, clear=False):
            r = comms._resolve_recipient("dev-team-pr", ENABLED_CFG["communication"])
        self.assertTrue(r["ok"])
        self.assertEqual(r["url"], "https://hook")

    def test_convention_env_var(self):
        cfg = {"recipients": {"my-chan": {"type": "channel", "display": "X"}}}
        with mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_MY_CHAN": "https://conv"}, clear=False):
            r = comms._resolve_recipient("my-chan", cfg)
        self.assertTrue(r["ok"])
        self.assertEqual(r["url"], "https://conv")

    def test_fallback_default_url(self):
        cfg = {"recipients": {"c": {"type": "channel"}}}
        env = {"TEAMS_WEBHOOK_URL": "https://default"}
        with mock.patch.dict(os.environ, env, clear=True):
            r = comms._resolve_recipient("c", cfg)
        self.assertTrue(r["ok"])
        self.assertEqual(r["url"], "https://default")

    def test_unknown_key(self):
        r = comms._resolve_recipient("nope", ENABLED_CFG["communication"])
        self.assertFalse(r["ok"])

    def test_unset_env_var(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            r = comms._resolve_recipient("dev-team-pr", ENABLED_CFG["communication"])
        self.assertFalse(r["ok"])

    def test_person_deferred(self):
        r = comms._resolve_recipient("manager", ENABLED_CFG["communication"])
        self.assertFalse(r["ok"])


class GatingTests(unittest.TestCase):
    def test_disabled_org_never_resolves_or_posts(self):
        with (
            mock.patch.object(comms, "_post_to_webhook") as post,
            mock.patch.object(comms, "_resolve_recipient") as resolve,
        ):
            res = comms.send(_msg(), config=DISABLED_CFG)
        self.assertEqual(res["status"], "disabled")
        post.assert_not_called()
        resolve.assert_not_called()


class ValidationTests(unittest.TestCase):
    def test_missing_field_rejected_no_post(self):
        bad = _msg()
        del bad["subject"]
        with mock.patch.object(comms, "_post_to_webhook") as post:
            res = comms.send(bad, config=ENABLED_CFG)
        self.assertEqual(res["status"], "rejected")
        post.assert_not_called()

    def test_invalid_tone_rejected(self):
        res = comms.send(_msg(tone="shout"), config=ENABLED_CFG)
        self.assertEqual(res["status"], "rejected")

    def test_subject_only_post_allowed(self):
        # The SendTeams one-liner shape: subject, no sections.
        msg = {
            "caller": "ad-hoc",
            "recipient": "dev-team-pr",
            "subject": "deploy done",
            "sections": [],
            "tone": "broadcast",
        }
        with (
            mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_DEV_TEAM_PR": "https://hook"}, clear=False),
            mock.patch.object(comms, "_post_to_webhook", return_value=(True, "HTTP 200")),
        ):
            res = comms.send(msg, config=ENABLED_CFG)
        self.assertEqual(res["status"], "ok")
        self.assertEqual(comms._render(msg), "**deploy done**")


class DryRunTests(unittest.TestCase):
    def test_dry_run_no_post_returns_payload(self):
        with (
            mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_DEV_TEAM_PR": "https://hook"}, clear=False),
            mock.patch.object(comms, "_post_to_webhook") as post,
        ):
            res = comms.send(_msg(dryRun=True), config=ENABLED_CFG)
        self.assertEqual(res["status"], "dry-run")
        self.assertIn("**PR ready**", res["payload"])
        post.assert_not_called()

    def test_dry_run_still_honors_disabled(self):
        res = comms.send(_msg(dryRun=True), config=DISABLED_CFG)
        self.assertEqual(res["status"], "disabled")

    def test_dry_run_still_honors_skipped(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            res = comms.send(_msg(dryRun=True), config=ENABLED_CFG)
        self.assertEqual(res["status"], "skipped")


class FailureTests(unittest.TestCase):
    def test_post_failure_returns_error_no_raise(self):
        with (
            mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_DEV_TEAM_PR": "https://hook"}, clear=False),
            mock.patch.object(comms, "_post_to_webhook", return_value=(False, "HTTP 500")),
        ):
            res = comms.send(_msg(), config=ENABLED_CFG)
        self.assertEqual(res["status"], "error")
        self.assertIn("500", res["detail"])

    def test_success(self):
        with (
            mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_DEV_TEAM_PR": "https://hook"}, clear=False),
            mock.patch.object(comms, "_post_to_webhook", return_value=(True, "HTTP 200")) as post,
        ):
            res = comms.send(_msg(), config=ENABLED_CFG)
        self.assertEqual(res["status"], "ok")
        post.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
