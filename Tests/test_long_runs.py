"""A long run of spaces or blank lines costs a card reader nothing, and the patterns
keep reading what they read. Tests/fixtures/parsers/long-runs.json is the table the
CLI's suite asserts too (tkTestToolkit -Consts)."""

from __future__ import annotations

import json
import re
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from agent.ado import design
    from agent.core import consts, parsers
except ImportError as e:
    skip_module(f"cannot import the agent ({type(e).__name__}: {e})")

TABLE = json.loads((ROOT / "Tests/fixtures/parsers/long-runs.json").read_text(encoding="utf-8"))
STAMP = re.escape(TABLE["stamp"])
RUN = TABLE["longRun"]
# It was 17 seconds. Far above a real answer, so a busy machine cannot trip it.
LIMIT_SECONDS = 2.0


class WhatThePatternsRead(unittest.TestCase):
    def test_a_value_line(self):
        for row in TABLE["values"]:
            with self.subTest(row["why"]):
                m = re.search(r"(?m)^" + STAMP + consts.consts()["regex"][row["key"]], row["text"])
                self.assertEqual((m.group(1) or "") if m else None, row["want"])

    def test_bullets_and_checkboxes(self):
        for row in TABLE["bullets"]:
            with self.subTest(row["why"]):
                self.assertEqual(len(consts.re_commit_bullet().findall(row["text"])), row["commits"])
                self.assertEqual(len(consts.re_task_checked().findall(row["text"])), row["checked"])
                self.assertEqual(len(consts.re_task_any().findall(row["text"])), row["any"])

    def test_a_heading(self):
        for row in TABLE["headings"]:
            with self.subTest(row["text"]):
                m = consts.re_design_heading().match(row["text"])
                self.assertEqual(m.group(1) if m else None, row["hashes"])
                self.assertEqual((m.group(2) or "") if m else None, row["words"])

    def test_a_docs_line(self):
        for row in TABLE["docs"]:
            with self.subTest(row["text"]):
                m = consts.re_design_docs().search(row["text"])
                self.assertEqual(m.group(1) if m else None, row["want"])


class ALongRunCostsNothing(unittest.TestCase):
    def assert_cheap(self, name: str, read) -> None:
        with self.subTest(name):
            started = time.perf_counter()
            read()
            self.assertLess(time.perf_counter() - started, LIMIT_SECONDS)

    def test_the_real_readers(self):
        spaces, blank = " " * RUN, "\n" * RUN
        assigned = f"**Assigned:** a{spaces}b"
        sprint = f"**Sprint:** a{spaces}b"
        design_line = f"> Design: a{spaces}b"
        self.assert_cheap("card_assigned", lambda: parsers.card_assigned(assigned))
        self.assert_cheap("card_milestone", lambda: parsers.card_milestone(sprint))
        self.assert_cheap("card_design", lambda: parsers.card_design(design_line))
        self.assert_cheap("the whole parse, blank lines", lambda: parsers._parse_status_metadata(f"# T\n{blank}x"))
        card = f"# T\n{assigned}\n{sprint}"
        self.assert_cheap("the whole parse, spaces", lambda: parsers._parse_status_metadata(card))
        self.assert_cheap("_stamp", lambda: design._stamp(f"**Outcome:** a{spaces}b", "**Outcome:**"))
        self.assert_cheap("doc_title", lambda: design.doc_title([f"# a{spaces}b"]))
        self.assert_cheap("the docs line", lambda: consts.re_design_docs().search(f"> Docs: a{spaces}b"))

    def test_a_bare_cr_is_no_worse(self):
        spaces = " " * RUN
        self.assert_cheap("a value line", lambda: parsers.card_assigned(f"**Assigned:**{spaces}\rb"))
        self.assert_cheap("a design line", lambda: parsers.card_design(f"> Design:{spaces}\rb"))
        self.assert_cheap("a design line with a word", lambda: parsers.card_design(f"> Design: a{spaces}\rb"))


if __name__ == "__main__":
    unittest.main()
