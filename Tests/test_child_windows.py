"""The child rule on a real Windows console: what run_read hands to the OS.

Everything here needs CreateProcess and cmd.exe themselves, so it is skipped
elsewhere and run by its own step in the Windows CI job. The child is harmless:
Python printing its own arguments, and a one-line az.cmd stand-in. The marker
file is how a value that left its argument would show.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agent.core import child

PRINT_ARGV = "import sys; print(sys.argv[1])"


@unittest.skipUnless(sys.platform == "win32", "needs cmd.exe")
class TestOnARealConsole(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.root = Path(self.dir.name)
        self.marker = self.root / "marker.txt"

    def test_a_value_reaches_a_shell_free_child_whole(self):
        """The default route for anything but az: one argument, untouched."""
        value = f'"&echo x>"{self.marker}"&"'
        result = child.run_read([sys.executable, "-c", PRINT_ARGV, value], 30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.rstrip("\r\n"), value)
        self.assertFalse(self.marker.exists())

    def test_percent_stays_literal_without_the_shell(self):
        result = child.run_read([sys.executable, "-c", PRINT_ARGV, "%PATH%"], 30)
        self.assertEqual(result.stdout.rstrip("\r\n"), "%PATH%")

    def test_az_still_runs_through_the_shell_and_is_refused_shell_syntax(self):
        (self.root / "az.cmd").write_text("@echo off\r\necho ran %*\r\n", encoding="ascii")
        env = {**os.environ, "PATH": f"{self.root}{os.pathsep}{os.environ['PATH']}"}
        with mock.patch.dict(os.environ, env):
            ok = child.run_read(["az", "account", "show", "--query", "a b"], 30)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertIn("ran account show", ok.stdout)
            with self.assertRaises(child.ChildReadError):
                child.run_read(["az", "boards", "query", "--wiql", f'"&echo x>"{self.marker}"&"'], 30)
        self.assertFalse(self.marker.exists())


if __name__ == "__main__":
    unittest.main()
