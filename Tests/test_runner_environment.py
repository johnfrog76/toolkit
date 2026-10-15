"""The test runners own their environment.

A webhook variable no list could name is removed for the run; the run marker is
set; the engine's one POST refuses while it is; and the scratch-tree remover
clears a read-only file rather than leaving the folder behind.

Run:  python3 -m pytest Tests/test_runner_environment.py
"""

import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _rmtree import remove_tree
from _skipguard import skip_module
from conftest import TEST_RUN_MARKER, WEBHOOK_PREFIX, scrub_webhooks

try:
    from agent.communication.comms import _post_to_webhook
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")


class TheRunnerScrubsByPattern(unittest.TestCase):
    def test_no_suite_sees_a_webhook_variable(self):
        self.assertEqual([n for n in os.environ if n.startswith(WEBHOOK_PREFIX)], [])

    def test_a_name_no_list_could_contain_is_removed_and_handed_back(self):
        env = {"TEAMS_WEBHOOK_SOMETHING_NEW": "https://example.invalid/hook", "PATH": "/bin"}
        saved = scrub_webhooks(env)
        self.assertEqual(saved, {"TEAMS_WEBHOOK_SOMETHING_NEW": "https://example.invalid/hook"})
        self.assertEqual(env, {"PATH": "/bin"})

    def test_the_run_marker_is_set_for_this_process(self):
        self.assertEqual(os.environ.get(TEST_RUN_MARKER), "1")


class TheEngineRefusesDuringARun(unittest.TestCase):
    def test_the_one_post_refuses_while_the_marker_is_set(self):
        ok, detail = _post_to_webhook("https://example.invalid/hook", "hello")
        self.assertFalse(ok)
        self.assertIn("test run", detail)


class TheScratchRemover(unittest.TestCase):
    def test_a_read_only_file_does_not_keep_the_folder_alive(self):
        root = Path(tempfile.mkdtemp(prefix="p20-rmtree-"))
        stubborn = root / "objects" / "ab" / "cd"
        stubborn.parent.mkdir(parents=True)
        stubborn.write_text("x")
        os.chmod(stubborn, stat.S_IREAD)
        leftovers = remove_tree(root)
        self.assertEqual(leftovers, [])
        self.assertFalse(root.exists())
