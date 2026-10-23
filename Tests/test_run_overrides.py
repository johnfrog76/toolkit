"""A set P20_ACTIVE_SPACE or PROMPTS_ROOT does not reach a test.

The two per-shell overrides beat the config files, so a shell that holds them
would point every suite that copies samples/hub at a Space or folder that hub
lacks. conftest removes them for the run and puts them back after, as it does
the webhooks. This file proves it two ways: a child pytest started with both set
sees neither, and the scrub hands back what it took so the caller's values return.
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path

import conftest

PKG_ROOT = Path(__file__).resolve().parent.parent
BOGUS = {
    conftest.RUN_OVERRIDES[0]: "nonexistent-space",
    conftest.RUN_OVERRIDES[1]: "/nonexistent",
}


class TheOverridesAreNotInherited(unittest.TestCase):
    def test_this_run_holds_neither(self):
        for name in conftest.RUN_OVERRIDES:
            self.assertNotIn(name, os.environ)

    def test_scrub_returns_what_it_removed(self):
        env = dict(BOGUS, UNRELATED="keep")
        saved = conftest.scrub_overrides(env)
        self.assertEqual(saved, BOGUS)
        self.assertEqual(env, {"UNRELATED": "keep"})
        env.update(saved)
        self.assertEqual(env, dict(BOGUS, UNRELATED="keep"))

    def test_a_child_run_started_with_both_set_sees_neither(self):
        env = dict(os.environ, **BOGUS)
        target = f"Tests/{Path(__file__).name}::TheOverridesAreNotInherited::test_this_run_holds_neither"
        done = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", target],
            check=False,
            cwd=PKG_ROOT,
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 passed", done.stdout)
        # The child is a separate process: what this shell holds is untouched.
        for name, value in BOGUS.items():
            self.assertNotEqual(os.environ.get(name), value)
