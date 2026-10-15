"""The test summary covers three halves.

``test-summary.{machine}.json`` used to hold the CLI runner's suites alone, so
the System page's Health card reported the CLI's health as the machine's.
``{cliPrefix}Test`` now writes a ``half`` on every suite entry and a ``halves``
block with one record per half; ``agent/core/log.py`` serves both on
``GET /api/test-history``. These pin the reader:

- a file from before the halves still reads, every entry the CLI's, and its CLI
  half summed from those entries -- the rule Setup reads through
  ``Get-P20TestHalfRecords`` in Scripts/TestAll-Rules.ps1;
- a three-half file serves each half's record in run order, a skipped half
  with its reason;
- a file that does not parse is left out, not an error.

Run directly:  python Tests/test_test_summary.py
Under pytest:  python -m pytest Tests/test_test_summary.py
"""

import asyncio
import json
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent.core import consts as C
    from agent.core import log as log_mod
    from agent.core.log import TEST_HALVES, _load_machine_summaries
except Exception as e:
    skip_module(f"cannot import agent ({type(e).__name__}: {e})")


LEGACY = {
    "machine": "OLDBOX",
    "timestamp": "2026-09-22T10:00:00",
    "grandTotal": 7,
    "suites": {
        "Menu": {"result": "pass", "passed": 5, "total": 5, "seconds": 1.5, "description": "menu", "org": ""},
        "Web": {"result": "fail", "passed": 1, "total": 2, "seconds": 2.0, "description": "web launcher", "org": ""},
    },
}

THREE = {
    "machine": "NEWBOX",
    "timestamp": "2026-10-06T12:00:00",
    "suites": {
        "Menu": {
            "half": "cli",
            "result": "pass",
            "passed": 5,
            "total": 5,
            "seconds": 1.5,
            "description": "menu",
            "org": "",
        },
        "pytest": {
            "half": "agent",
            "result": "pass",
            "passed": 900,
            "total": 900,
            "skipped": 3,
            "description": "the agent",
        },
        "jest": {
            "half": "web",
            "result": "warn",
            "passed": 0,
            "total": 0,
            "description": "the web UI",
            "detail": "web/node_modules is missing -- run npm ci in web/",
        },
    },
    "halves": {
        "web": {"half": "web", "result": "skip", "reason": "web/node_modules is missing -- run npm ci in web/"},
        "cli": {"half": "cli", "result": "pass", "passed": 5, "failed": 0, "skipped": 0, "total": 5, "seconds": 2.0},
        "agent": {
            "half": "agent",
            "result": "pass",
            "passed": 900,
            "failed": 0,
            "skipped": 3,
            "total": 903,
            "seconds": 312.4,
        },
    },
}


class SummaryHalves(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def _write(self, name: str, data, *, bom: bool = False) -> None:
        text = data if isinstance(data, str) else json.dumps(data)
        (self.root / f"test-summary.{name}.json").write_text(text, encoding="utf-8-sig" if bom else "utf-8")

    def _machine(self, name: str):
        return next(m for m in _load_machine_summaries(self.root) if m.machine == name)

    def test_the_halves_are_the_contracts(self):
        self.assertEqual(list(TEST_HALVES), list(C.test_halves()))
        self.assertEqual(list(TEST_HALVES), ["agent", "cli", "web"])

    def test_a_file_from_before_the_halves_reads_as_the_cli(self):
        self._write("OLDBOX", LEGACY, bom=True)  # the runner wrote it with a BOM on 5.1
        m = self._machine("OLDBOX")
        self.assertEqual({s.half for s in m.suites.values()}, {C.test_legacy_half()})
        self.assertEqual(list(m.halves), ["cli"])
        cli = m.halves["cli"]
        self.assertEqual((cli.result, cli.passed, cli.failed, cli.total), ("fail", 6, 1, 7))

    def test_three_halves_in_run_order_with_a_skip_and_its_reason(self):
        self._write("NEWBOX", THREE)
        m = self._machine("NEWBOX")
        self.assertEqual(list(m.halves), ["agent", "cli", "web"])
        self.assertEqual(m.halves["agent"].passed, 900)
        self.assertEqual(m.halves["agent"].skipped, 3)
        self.assertEqual(m.halves["web"].result, "skip")
        self.assertIn("node_modules", m.halves["web"].reason)
        self.assertEqual(m.suites["pytest"].half, "agent")
        self.assertEqual(m.suites["jest"].half, "web")
        self.assertEqual(m.suites["Menu"].half, "cli")

    def test_a_file_that_does_not_parse_is_left_out(self):
        self._write("NEWBOX", THREE)
        self._write("BROKEN", "{ not json")
        names = [m.machine for m in _load_machine_summaries(self.root)]
        self.assertEqual(names, ["NEWBOX"])

    def test_a_warn_entry_is_served_as_warn(self):
        """#241: the web half's jest entry in THREE is a warn; the reader serves the word."""
        self._write("NEWBOX", THREE)
        m = self._machine("NEWBOX")
        self.assertEqual(m.suites["jest"].result, "warn")
        self.assertEqual((m.suites["jest"].passed, m.suites["jest"].total), (0, 0))

    def test_a_legacy_file_counts_a_warn_as_a_skip_not_a_pass_or_a_fail(self):
        data = json.loads(json.dumps(LEGACY))
        data["suites"]["Web"] = {"result": "warn", "passed": 0, "total": 0, "description": "ran nothing", "org": ""}
        self._write("OLDBOX", data)
        cli = self._machine("OLDBOX").halves["cli"]
        self.assertEqual((cli.result, cli.passed, cli.failed, cli.skipped, cli.total), ("pass", 5, 0, 1, 5))


class WarnInTheHistory(unittest.TestCase):
    """The daily log's warn line is neither a pass nor a failure on the Health card's feed."""

    def test_a_warn_line_is_a_warn_and_does_not_break_the_streak(self):
        from datetime import datetime

        today = datetime.now().strftime("%Y-%m-%d")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            machine = os.environ.get("COMPUTERNAME") or socket.gethostname().split(".")[0]
            rows = [
                f"{today}T09:00:00\tAlpha\tpass\t6\t6\tok\t",
                f"{today}T09:00:01\tZero\twarn\t0\t0\tok\t",
            ]
            (root / f"test-results.{machine}.log").write_text("\n".join(rows) + "\n", encoding="utf-8")
            saved_root = log_mod.REPO_ROOT
            saved_cfg = log_mod.load_config
            log_mod.REPO_ROOT = root
            log_mod.load_config = dict
            try:
                resp = asyncio.run(log_mod.get_test_history())
            finally:
                log_mod.REPO_ROOT = saved_root
                log_mod.load_config = saved_cfg
        day = resp.days[-1]
        by_name = {sr.suite: sr for sr in day.suites}
        self.assertEqual(by_name["Zero"].result, "warn")
        self.assertEqual(by_name["Zero"].detail, "ok")
        self.assertEqual(by_name["Alpha"].result, "pass")
        self.assertEqual((day.passed, day.total), (6, 6))
        self.assertEqual(resp.streak, 1)


if __name__ == "__main__":
    unittest.main()
