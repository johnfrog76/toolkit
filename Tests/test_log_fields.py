"""One log entry is one line, whatever the caller puts in it.

``usage.{machine}.log`` is tab-separated columns, one entry per line, and the
reader splits on exactly those two things. A ``detail`` carrying a newline could
therefore forge a second entry with any timestamp it liked, and a tab in
``source`` or ``detail`` moved the columns. Callers pass work item titles,
refusal sentences and exception text, so the writer cannot trust any of them:
it turns a tab or a line break into one space, and the entry reads back whole.

Run directly:  python3 Tests/test_log_fields.py
Under pytest:  python3 -m pytest Tests/
"""

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
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import log_writer
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

FORGED = "\n2030-01-01T00:00:00\tERR\tHOST\tforged\tnot a real entry"


class OneEntryIsOneLine(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory(prefix="p20-log-fields-")
        self._previous = os.environ.get(log_writer.LOG_DIR_ENV)
        os.environ[log_writer.LOG_DIR_ENV] = self._dir.name

    def tearDown(self):
        if self._previous is None:
            os.environ.pop(log_writer.LOG_DIR_ENV, None)
        else:
            os.environ[log_writer.LOG_DIR_ENV] = self._previous
        self._dir.cleanup()

    def _entries(self):
        r = client.get("/api/log-entries")
        self.assertEqual(r.status_code, 200)
        return r.json()["entries"]

    def test_a_forged_second_line_stays_inside_one_entry(self):
        detail = "failed" + FORGED
        r = client.post("/api/log", json={"log_type": "WARN", "source": "web", "detail": detail})
        self.assertEqual(r.status_code, 200)
        entries = self._entries()
        self.assertEqual(len(entries), 1, entries)
        self.assertEqual(entries[0]["type"], "WARN")
        self.assertEqual(entries[0]["detail"], "failed " + FORGED[1:].replace("\t", " "))

    def test_a_tab_in_detail_does_not_truncate_it(self):
        client.post("/api/log", json={"log_type": "INFO", "source": "web", "detail": "one\ttwo\tthree"})
        entries = self._entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["detail"], "one two three")

    def test_a_tab_in_source_does_not_shift_the_columns(self):
        client.post("/api/log", json={"log_type": "INFO", "source": "a\tb", "detail": "ok"})
        entries = self._entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual((entries[0]["source"], entries[0]["detail"]), ("a b", "ok"))

    def test_carriage_returns_and_the_other_line_ends_are_one_space_each(self):
        client.post("/api/log", json={"log_type": "ERR", "source": "s", "detail": "a\r\nb c\x85d"})
        entries = self._entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["detail"], "a  b c d")

    def test_a_plain_entry_is_unchanged(self):
        log_writer.write_log("CMD", "status", "ok: 3 cards")
        entries = self._entries()
        self.assertEqual((entries[0]["source"], entries[0]["detail"]), ("status", "ok: 3 cards"))


if __name__ == "__main__":
    unittest.main()
