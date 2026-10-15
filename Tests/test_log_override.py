"""A test run is not an event, and must not land in the engineer's log.

``usage.{machine}.log`` is the file ``tkLog -Errors``, the web UI's Log card and
its error count read as this engineer's history. Both test runners appended to
it: after a Windows verification run the Log card showed 97 entries with 10 errors, and
nine of the ten were assertions -- the bridge's refusal cases, a fixture hub's
config warnings, a comms dry run, the rewrite route declining an unset key.

``P20_USAGE_LOG_DIR`` is the one override both halves read (``log_writer.py``
here, ``Get-ToolkitLogDir`` in ``utilities.psm1``), and ``Tests/conftest.py``
points it at a temp directory for the whole session. These cases assert the
mechanism and, for the run they are part of, the outcome.

Run directly:  python3 Tests/test_log_override.py
Under pytest:  python3 -m pytest Tests/
"""

import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent.core import log_writer
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the log writer ({type(e).__name__}: {e})")


def _digest(path: Path) -> str:
    """A file that is not there has a digest too -- 'absent' is a state the run
    must also leave unchanged."""
    if not path.exists():
        return "absent"
    return hashlib.sha256(path.read_bytes()).hexdigest()


class TheOverrideMovesTheLog(unittest.TestCase):
    def test_unset_means_the_repo_root(self):
        previous = os.environ.pop(log_writer.LOG_DIR_ENV, None)
        try:
            self.assertEqual(log_writer.log_dir(), log_writer.REPO_ROOT)
        finally:
            if previous is not None:
                os.environ[log_writer.LOG_DIR_ENV] = previous

    def test_the_variable_is_the_same_name_the_cli_reads(self):
        """One name, both halves. utilities.psm1 is the other reader."""
        self.assertEqual(log_writer.LOG_DIR_ENV, "P20_USAGE_LOG_DIR")
        utilities = (PKG_ROOT / "utilities.psm1").read_text(encoding="utf-8")
        self.assertIn("P20_USAGE_LOG_DIR", utilities)

    def test_a_write_lands_in_the_override_and_nowhere_else(self):
        machine = log_writer._machine_name()
        real = log_writer.REPO_ROOT / f"usage.{machine}.log"
        before = _digest(real)

        with tempfile.TemporaryDirectory() as tmp:
            previous = os.environ.get(log_writer.LOG_DIR_ENV)
            os.environ[log_writer.LOG_DIR_ENV] = tmp
            try:
                log_writer.write_log("ERR", "test/log-override", "this is an assertion, not an event")
                scratch = Path(tmp) / f"usage.{machine}.log"
                self.assertTrue(scratch.exists(), "nothing was written to the override directory")
                self.assertIn("this is an assertion", scratch.read_text(encoding="utf-8"))
            finally:
                if previous is None:
                    os.environ.pop(log_writer.LOG_DIR_ENV, None)
                else:
                    os.environ[log_writer.LOG_DIR_ENV] = previous

        self.assertEqual(before, _digest(real), "the real usage log changed during the test")

    def test_this_run_is_already_redirected(self):
        """The session fixture, asserted from inside the session it configures.

        Run under pytest this is conftest.py's doing. Run directly
        (python3 Tests/test_log_override.py) there is no fixture, so the case
        says what it checked rather than failing on a runner difference.
        """
        configured = (os.environ.get(log_writer.LOG_DIR_ENV) or "").strip()
        if "pytest" not in sys.modules:
            self.skipTest("no session fixture outside pytest")
        self.assertTrue(configured, "P20_USAGE_LOG_DIR is not set for this run")
        self.assertNotEqual(
            Path(configured).resolve(),
            log_writer.REPO_ROOT.resolve(),
            "this run is logging into the repo root",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
