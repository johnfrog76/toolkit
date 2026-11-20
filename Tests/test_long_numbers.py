"""A number read from text is bounded before it is converted.

Python refuses to convert a very long run of digits, and the CLI's [int] stops at
ten. Text from a tracker or a card can hold any run, so each reader takes a number
of a sensible length or none, and a longer one reads as no number at all.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.ado import design, pr_comments, reporting, status
    from agent.core.consts import token_pr_review_heading
except ImportError as e:
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

LONG = "9" * 5000


class ATrackerUrl(unittest.TestCase):
    def test_a_real_number_is_read(self):
        m = status._GH_ISSUE_URL.search("https://github.com/o/r/issues/123")
        self.assertEqual(m.group(3), "123")

    def test_a_long_one_is_none(self):
        self.assertIsNone(status._GH_ISSUE_URL.search(f"https://github.com/o/r/issues/{LONG}"))


class ADesignNote(unittest.TestCase):
    def test_a_long_thread_number_reads_as_no_thread(self):
        text = f"# A note\n\n> GitHub: https://github.com/o/r/issues/{LONG}\n"
        self.assertIsNone(design._THREAD.search(text))


class AReportingRead(unittest.TestCase):
    def test_a_sprint_label(self):
        self.assertEqual(reporting._extract_sprint("Sprint: 12"), "Sprint 12")
        self.assertEqual(reporting._extract_sprint("Sprint: Sprint 12"), "Sprint 12")
        self.assertEqual(reporting._extract_sprint(f"Sprint: {LONG}"), "")
        self.assertEqual(reporting._extract_sprint(f"Sprint: Sprint {LONG}"), "")


class ACardsCommentSection(unittest.TestCase):
    def test_a_long_id_reads_as_no_section(self):
        heading = token_pr_review_heading()
        self.assertEqual(pr_comments._parse_pr_comments(f"{heading} (PR {LONG})\n")[0], 0)

    def test_a_github_sized_id_is_still_read(self):
        heading = token_pr_review_heading()
        text = f"{heading} (PR 7)\n\n### Comment 1 (Thread 12345678901)\n"
        self.assertEqual(pr_comments._parse_pr_comments(text)[0], 7)


if __name__ == "__main__":
    unittest.main()
