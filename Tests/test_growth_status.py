"""What a growth file says about itself is what the Growth page says about it.

The owner, looking at a talk given in April reading "Active": "this is
very important that these don't regress ... make sure they read the same logic as
they did before." The rewrite of this parser demanded the CURRENT template's
heading (``## Outcome & Follow-Up``); files written from the earlier one head the
same section ``## Outcome``. The predecessor read both. Nothing tested it.

Every status rule, for all three types, as a table -- so the next rewrite cannot
change one quietly.

Run:  python3 -m pytest Tests/test_growth_status.py
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.growth.growth import parse_growth_file
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")


def _status(name: str, body: str) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / name
        path.write_text(body, encoding="utf-8")
        item = parse_growth_file(path)
        assert item is not None, name
        return item.status


def _presentation(heading: str, delivered: str | None) -> str:
    line = f"- **Delivered**: {delivered}\n" if delivered is not None else ""
    return (
        f"# Presentation\n\n## Title\nA talk\n\n## Date & Time\n2026-04-23\n\n"
        f"## Slides\n### Slide 1 -- Delivered: Yes (a slide that says so is not the outcome)\n\n"
        f"{heading}\n{line}- **Recording**: none\n\n### Feedback\nGood.\n"
    )


class APresentationIsCompleteWhenItWasGiven(unittest.TestCase):
    CASES = [
        (
            "## Outcome",
            "Yes -- 2026-04-23",
            "complete",
            "the EARLIER template's heading -- the file someone was looking at",
        ),
        ("## Outcome & Follow-Up", "Yes", "complete", "the current template's heading"),
        ("## Outcome & Follow-up", "yes", "complete", "case does not matter, in the heading or the answer"),
        ("## Outcome", "No", "active", "not given yet"),
        ("## Outcome & Follow-Up", "No", "active", "not given yet, current heading"),
        ("## Outcome", None, "active", "an outcome section with no Delivered line"),
        ("## Notes", "Yes", "active", "Delivered: Yes under some OTHER heading is not the outcome"),
    ]

    def test_every_case(self):
        for heading, delivered, want, why in self.CASES:
            with self.subTest(why):
                got = _status("presentation-2026-04-23-a-talk.prompt.md", _presentation(heading, delivered))
                self.assertEqual(got, want)


class ATrainingSaysItsStatusInWords(unittest.TestCase):
    """The predecessor's rule, unchanged: the first line under ``## Status``."""

    CASES = [
        ("Not Started", "new"),
        ("not started yet", "new"),
        ("Completed", "complete"),
        ("Complete -- all 8 chapters", "complete"),
        ("Completed (work shipped)", "complete"),
        ("Achieved", "complete"),
        ("In progress", "active"),
        ("Week 3 of 6", "active"),
        ("", "active"),
    ]

    def test_every_word(self):
        for words, want in self.CASES:
            with self.subTest(words or "(empty)"):
                body = (
                    "# Training\n\n## Title\nA course\n\n## Date(s)\n2026-03-02 to 2026-04-30\n\n"
                    f"## Status\n{words}\n\n## Outcome\n- notes\n"
                )
                self.assertEqual(_status("training-2026-03-02-a-course.prompt.md", body), want)


class AGoalSaysItsStatusInItsOutcome(unittest.TestCase):
    CASES = [
        ("## Outcome", "Achieved", "complete"),
        ("## Outcome & Follow-Up", "Completed in Q3", "complete"),
        ("## Outcome", "Not Started", "new"),
        ("## Outcome", "On track", "active"),
    ]

    def test_every_case(self):
        for heading, words, want in self.CASES:
            with self.subTest(f"{heading} / {words}"):
                body = (
                    "# Goal\n\n## Goal\nGet better\n\n## Time Frame\n2026-01-01 to 2026-12-31\n\n"
                    f"{heading}\n- **Status**: {words}\n"
                )
                self.assertEqual(_status("goal-2026-get-better.prompt.md", body), want)
