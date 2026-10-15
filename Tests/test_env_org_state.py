"""The Environment card's rows tell "never asked" from "tried and failed".

The owner, looking at an archived org whose card read "ADO unreachable" and
"0 active prompts" in red: "archive doesn't request at all, and local tried and
failed to get access." An archived org and a local one are never probed, so neither
can FAIL the ADO row; and an archived org is supposed to have nothing in flight.

Run:  python3 -m pytest Tests/test_env_org_state.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.core.env import _ado_access_check, _git_history_check, _identity_check
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

URL = "https://dev.azure.com/YOUR-ADO-ORG"


class TheAdoAccessRow(unittest.TestCase):
    def test_an_archived_org_is_never_asked_so_it_cannot_fail(self):
        for url in (URL, ""):
            row = _ado_access_check("archive", url, False)
            self.assertTrue(row["ok"], row)
            self.assertEqual(row["detail"], "not contacted -- archived")
            self.assertNotIn("unreachable", row["detail"])

    def test_a_local_org_is_never_asked_either(self):
        row = _ado_access_check("local", "", False)
        self.assertEqual((row["ok"], row["detail"]), (True, "not configured (expected)"))

    def test_only_an_active_space_can_fail_and_it_says_which_way(self):
        self.assertEqual(_ado_access_check("active", URL, False), {"ok": False, "detail": "unreachable (YOUR-ADO-ORG)"})
        self.assertEqual(_ado_access_check("active", "", False), {"ok": False, "detail": "no org URL configured"})
        self.assertEqual(_ado_access_check("active", URL, True), {"ok": True, "detail": "connected (YOUR-ADO-ORG)"})


class TheGitHistoryRow(unittest.TestCase):
    """A hub that is not a repository is the ordinary case; it fails only when git was wanted."""

    def test_no_repository_with_storesync_none_is_ok_and_says_why(self):
        row = _git_history_check(False, "none")
        self.assertTrue(row["ok"], row)
        self.assertIn("storeSync is 'none'", row["detail"])

    def test_no_repository_with_storesync_git_is_the_one_failure(self):
        row = _git_history_check(False, "git")
        self.assertFalse(row["ok"], row)
        self.assertIn("storeSync is 'git'", row["detail"])

    def test_a_repository_is_ok_either_way(self):
        for sync in ("git", "none"):
            self.assertEqual(_git_history_check(True, sync), {"ok": True, "detail": ".git found"})


class TheIdentityRow(unittest.TestCase):
    """Only Azure DevOps reads an identity, so without it an empty one is a note."""

    def test_no_identity_with_ado_off_is_a_note(self):
        row = _identity_check({"email": "", "source": ""}, False)
        self.assertEqual(row, {"ok": True, "detail": "not set -- only Azure DevOps uses it"})

    def test_no_identity_with_ado_on_is_a_failure_that_names_the_fix(self):
        row = _identity_check({"email": "", "source": ""}, True)
        self.assertFalse(row["ok"], row)
        self.assertIn("config.local.json", row["detail"])

    def test_an_identity_is_ok_and_says_where_it_came_from(self):
        row = _identity_check({"email": "me@example.com", "source": "config"}, False)
        self.assertEqual(row, {"ok": True, "detail": "me@example.com (from config)"})
