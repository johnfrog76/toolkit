"""A refusal is not a success, all the way out to the browser.

``POST /api/cmd/{name}`` types every outcome, and the type comes from the child
process's exit code. Before the refusal contract (AGENTS.md) a verb that caught
its own failure, printed ``Error: ...`` and returned cleanly exited 0, so
archiving a card that had already been moved, renamed or archived from another
shell answered::

    {"status": "success", "exit_code": 0, "error": null}

-- and ``usage.<MACHINE>.log`` recorded ``Archive ok`` for a file that never
moved.

Nothing in ``agent/ado/`` decides this. ``bridge.ps1`` exits on whether the
FUNCTION threw, on purpose; the CLI's guard is what re-raises a stated refusal
for a non-interactive caller. These cases run the real thing end to end,
because a suite that mocked the subprocess would pass with that half broken.

Archiving a name that matches nothing WRITES NOTHING, on any hub -- which is
what makes it safe to run for real here, against whatever hub this machine is
configured for.

Run directly:  python3 Tests/test_bridge_refusals.py
Under pytest:  python3 -m pytest Tests/
"""

import os
import shutil
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core.config import resolve_dirs
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

HAVE_PWSH = shutil.which("pwsh") is not None

# Unique per run, so it cannot collide with a real card on the machine that
# happens to be running this.
NO_SUCH_CARD = f"does-not-exist-card-{uuid.uuid4().hex[:8]}"


@unittest.skipUnless(HAVE_PWSH, "needs pwsh to run the CLI")
class ArchiveWithNoMatchIsAnError(unittest.TestCase):
    """The one case the issue reported, end to end."""

    @classmethod
    def setUpClass(cls):
        r = client.post("/api/cmd/Archive", json={"params": [NO_SUCH_CARD]})
        cls.status_code = r.status_code
        cls.body = r.json()

    def test_the_route_still_answers_200_with_a_typed_body(self):
        """A refusal is data, not an exception -- unchanged by this fix."""
        self.assertEqual(self.status_code, 200)
        self.assertEqual(self.body["command"], "Archive")

    def test_it_is_not_reported_as_a_success(self):
        self.assertNotEqual(self.body["status"], "success")

    def test_it_is_reported_as_an_error(self):
        self.assertEqual(self.body["status"], "error", self.body)

    def test_the_exit_code_is_not_zero(self):
        self.assertNotEqual(self.body["exit_code"], 0)

    def test_the_stated_message_comes_back(self):
        """The reason, not "exit code 2" and not an empty error field."""
        error = self.body.get("error") or ""
        self.assertTrue(error.strip(), f"no message came back: {self.body}")
        self.assertIn("No file matching", error)
        self.assertIn(NO_SUCH_CARD, error)

    def test_the_message_is_a_sentence_and_not_a_stack_trace(self):
        error = self.body.get("error") or ""
        for noise in ("System.Management.Automation", "at <ScriptBlock>", "+ CategoryInfo"):
            self.assertNotIn(noise, error)


@unittest.skipUnless(HAVE_PWSH, "needs pwsh to run the CLI")
class AnIdIsNotASubstring(unittest.TestCase):
    """``Archive 39`` on a hub holding ``Task139`` is an error, not a move.

    The CLI once fell back to ``*39*`` over ``current/``, matched
    exactly one card and archived it -- through the bridge that came back
    ``status: success`` for a card the caller never named.

    Run against a SCRATCH hub, pointed at with ``PROMPTS_ROOT`` -- the one
    override both halves read. The other cases here can run against whatever
    hub this machine has because they provably write nothing; this one asserts
    that a specific card was NOT moved, so it has to own the card.
    """

    @classmethod
    def setUpClass(cls):
        cls._previous_root = os.environ.get("PROMPTS_ROOT")
        cls._tmp = tempfile.mkdtemp(prefix="p20-bridge-hub-")
        os.environ["PROMPTS_ROOT"] = cls._tmp
        current, _archive = resolve_dirs()
        current.mkdir(parents=True, exist_ok=True)
        cls.card = current / "Task139-extract-scoring-rules.prompt.md"
        cls.card.write_text("# Task 139: extract scoring rules\n", encoding="utf-8")

        r = client.post("/api/cmd/Archive", json={"params": ["39"]})
        cls.status_code = r.status_code
        cls.body = r.json()

    @classmethod
    def tearDownClass(cls):
        if cls._previous_root is None:
            os.environ.pop("PROMPTS_ROOT", None)
        else:
            os.environ["PROMPTS_ROOT"] = cls._previous_root
        shutil.rmtree(cls._tmp, ignore_errors=True)

    def test_it_is_reported_as_an_error(self):
        self.assertEqual(self.status_code, 200)
        self.assertEqual(self.body["status"], "error", self.body)

    def test_the_exit_code_is_not_zero(self):
        self.assertNotEqual(self.body["exit_code"], 0)

    def test_the_message_says_no_card_carries_that_id(self):
        error = self.body.get("error") or ""
        self.assertIn("No card with id '39'", error, self.body)

    def test_the_card_that_merely_contains_39_did_not_move(self):
        self.assertTrue(self.card.exists(), "Task139 was archived by `Archive 39`")


@unittest.skipUnless(HAVE_PWSH, "needs pwsh to run the CLI")
class ARefusalIsStillNotARejection(unittest.TestCase):
    """`rejected` means nothing ran. A refusal ran and said no."""

    def test_archive_is_in_the_command_table(self):
        r = client.post("/api/cmd/Archive", json={"params": [NO_SUCH_CARD]})
        self.assertNotEqual(r.json()["status"], "rejected", r.json())


if __name__ == "__main__":
    unittest.main(verbosity=2)
