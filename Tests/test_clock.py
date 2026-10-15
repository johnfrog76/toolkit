"""A day from git is the reader's LOCAL day -- the agent's half of one table.

git's ``%ai`` carries the AUTHOR's zone, so ``%ai[:10]`` was the day where a
commit was made, and ``agent/ado/status.py`` could show a card one date while
``tkStatus`` showed another. Every git read now asks for ``%at`` and converts
with ``agent/core/clock.py``.

``Tests/fixtures/clock/local-days.json`` is read here AND by
``Tests/Test-BackfillStamps.ps1``: both halves must give every row one answer.
Fixed offsets, not zone names, so the rows hold on Windows with no tzdata.

Run directly:  python3 Tests/test_clock.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import re
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))

from agent.core.clock import local_day, local_stamp  # noqa: E402

TABLE = json.loads((PKG_ROOT / "Tests/fixtures/clock/local-days.json").read_text(encoding="utf-8"))


class OneInstantManyClocks(unittest.TestCase):
    def test_every_row(self):
        for epoch, offset, day, why in TABLE["rows"]:
            with self.subTest(why=why):
                self.assertEqual(local_day(epoch, timezone(timedelta(minutes=offset))), day)

    def test_the_epoch_may_arrive_as_git_prints_it(self):
        epoch, offset, day, _ = TABLE["rows"][0]
        self.assertEqual(local_day(f"{epoch}\n", timezone(timedelta(minutes=offset))), day)

    def test_not_a_number_is_no_day(self):
        self.assertIsNone(local_day("soon"))
        self.assertIsNone(local_day(""))

    def test_no_zone_is_the_machines_own_clock(self):
        epoch = TABLE["rows"][0][0]
        self.assertEqual(local_day(epoch), datetime.fromtimestamp(epoch).strftime("%Y-%m-%d"))

    def test_the_stamp_reads_the_same_clock(self):
        epoch = TABLE["rows"][0][0]
        self.assertEqual(local_stamp(epoch, timezone(timedelta(minutes=-420))), "2026-09-23 23:30")


class NoReaderAsksGitForAZonedDate(unittest.TestCase):
    """%ai/%ad/%ci/%cd and --date=short print a day in someone's zone."""

    def test_the_agent_asks_for_epochs(self):
        zoned = []
        for path in (PKG_ROOT / "agent").rglob("*.py"):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                if re.search(r"--format=[^\"']*%(ad|ai|aI|cd|ci|cI)\b", line) or "--date=short" in line:
                    zoned.append(f"{path.relative_to(PKG_ROOT)}:{n}")
        self.assertEqual(zoned, [])


if __name__ == "__main__":
    unittest.main()
