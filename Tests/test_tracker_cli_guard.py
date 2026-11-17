"""No test reaches a real ``az`` or ``gh`` (``Tests/_tracker_cli.py``).

The guard is proved the way the overrides are: a child pytest runs the cases in
``Tests/fixtures/tracker-cli/guard_cases.py`` under this same conftest, and this
file reads how each one ended. A call nobody stood in for fails its test and the
message names the command, whether this process made it or a child found the
tool on the PATH; a marked call and a stubbed one pass.
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path

import _tracker_cli
from _tracker_cli import unreachable

PKG_ROOT = Path(__file__).resolve().parent.parent
CASES = "Tests/fixtures/tracker-cli/guard_cases.py"


def _run_case(name: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", f"{CASES}::{name}"],
        check=False,
        cwd=PKG_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


class AnUnaskedCallFailsItsTest(unittest.TestCase):
    def test_a_call_from_this_process_fails_and_is_named(self):
        done = _run_case("test_an_unasked_call_in_this_process")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("1 failed", done.stdout)
        self.assertIn("gh api user -q .login", done.stdout)
        self.assertIn("reached a tracker tool it did not stand in for", done.stdout)

    def test_a_call_from_a_child_fails_and_is_named(self):
        done = _run_case("test_an_unasked_call_from_a_child")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("1 failed", done.stdout)
        self.assertIn("az account show", done.stdout)

    def test_a_mark_for_another_tool_does_not_cover_it(self):
        done = _run_case("test_a_mark_covers_only_the_tools_it_names")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("gh api user -q .login", done.stdout)


class AnAskedCallDoesNot(unittest.TestCase):
    def test_a_marked_call_passes(self):
        done = _run_case("test_a_marked_call")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 passed", done.stdout)

    def test_a_stubbed_call_passes(self):
        done = _run_case("test_a_stubbed_call")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 passed", done.stdout)


class TheToolsAreOutOfReach(unittest.TestCase):
    def test_the_stand_ins_are_first_on_the_path(self):
        first = os.environ["PATH"].split(os.pathsep)[0]
        self.assertEqual(Path(first), _tracker_cli.STAND_IN_DIR)

    @unreachable("az", "gh")
    def test_a_refused_call_reads_as_a_tool_that_is_not_installed(self):
        for argv in (["az", "account", "show"], ["gh", "auth", "status"]):
            with self.subTest(tool=argv[0]):
                with self.assertRaises(FileNotFoundError) as caught:
                    subprocess.run(argv, capture_output=True, check=False)
                self.assertIn(" ".join(argv), str(caught.exception))

    def test_a_tool_named_by_its_own_path_is_the_tests_own(self):
        self.assertFalse(_tracker_cli._is_stand_in([sys.executable], None))
        self.assertIsNone(_tracker_cli._tool_of([sys.executable, "-c", "gh"]))
        self.assertEqual(_tracker_cli._tool_of(["GH.exe", "api"]), "gh")
        self.assertEqual(_tracker_cli._tool_of(["az.cmd"]), "az")


if __name__ == "__main__":
    unittest.main()
