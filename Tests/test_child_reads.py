"""How the agent reads a gh, az or git child: UTF-8, through one helper.

On Windows ``subprocess.run(..., text=True)`` with no ``encoding`` decodes the
child's bytes with the console code page (cp1252), while gh, az and git write
UTF-8. A byte cp1252 has no character for killed the reader thread and the call
came back exit 0 with ``stdout=None`` -- read as an empty list. ``agent/core/child.py``
``run_read`` is the one way the agent reads such a child; this suite pins what it
does and holds every other ``text=True`` call in ``agent/`` to an explicit encoding.

No network, no child: ``subprocess.run`` is stubbed.

Run:  python3 -m pytest Tests/test_child_reads.py
"""

import ast
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

REPO_ROOT = Path(__file__).resolve().parent.parent
try:
    from agent.ado import accounting, design
    from agent.core import child
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

# An em dash, curly quotes and U+00CF, whose UTF-8 (C3 8F) holds the 0x8f byte
# that killed the standup's read on Windows.
TITLE = "Build the foyer counts — Chloé’s “Ïle” row"

# Calls in agent/ allowed to use text=True without an encoding, and why. Neither
# reads gh or az: status.py's git prints a probe exit code and %at digits, and
# reporting.py's child is the billing script under PowerShell.
NOT_GH_OR_AZ = {
    "agent/ado/status.py": 2,
    "agent/ado/reporting.py": 1,
}


def _cp1252_console(raw: bytes):
    """``subprocess.run`` as CPython runs it on a cp1252 console (see test_rituals)."""
    seen: list[dict] = []

    def run(argv, **kw):
        seen.append(kw)
        if kw.get("encoding"):
            out = raw.decode(kw["encoding"], kw.get("errors") or "strict")
        elif kw.get("text"):
            try:
                out = raw.decode("cp1252")
            except UnicodeDecodeError:
                out = None
        else:
            out = raw
        return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="" if out is not None else None)

    run.seen = seen
    return run


class TheHelper(unittest.TestCase):
    def test_it_asks_for_utf8_with_replacement(self):
        run = _cp1252_console(TITLE.encode("utf-8"))
        with mock.patch.object(subprocess, "run", side_effect=run):
            result = child.run_read(["gh", "issue", "list"], 30)
        self.assertEqual(result.stdout, TITLE)
        self.assertEqual((run.seen[0]["encoding"], run.seen[0]["errors"]), ("utf-8", "replace"))
        self.assertTrue(run.seen[0]["capture_output"])

    def test_a_byte_that_is_not_utf8_is_replaced_not_fatal(self):
        run = _cp1252_console(b"caf\xe9 ok")
        with mock.patch.object(subprocess, "run", side_effect=run):
            self.assertEqual(child.run_read(["gh"], 30).stdout, "caf� ok")

    def test_no_stdout_raises_rather_than_reading_empty(self):
        def dead(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=None, stderr=None)

        with mock.patch.object(subprocess, "run", side_effect=dead), self.assertRaises(child.ChildReadError) as cm:
            child.run_read(["gh", "label", "list"], 30)
        self.assertEqual(str(cm.exception), "gh's output could not be read (exit code 0)")

    def test_the_shell_rule_is_unchanged(self):
        run = _cp1252_console(b"")
        with (
            mock.patch.object(subprocess, "run", side_effect=run),
            mock.patch.object(child.platform, "system", return_value="Windows"),
        ):
            child.run_read(["gh"], 30)
            child.run_read(["git"], 5, shell=False)
        self.assertEqual([k["shell"] for k in run.seen], [True, False])

    def test_did_not_answer_keeps_the_old_sentence_for_a_timeout(self):
        self.assertEqual(
            child.did_not_answer("gh", subprocess.TimeoutExpired(["gh"], 30)), "gh did not answer (TimeoutExpired)"
        )
        self.assertEqual(
            child.did_not_answer("gh", child.ChildReadError("gh's output could not be read")),
            "gh's output could not be read",
        )


class TheReads(unittest.TestCase):
    """Each gh/az read, on a cp1252 console, keeps the title whole -- and a dead
    reader is a reason, never an empty success."""

    def _issues(self):
        return json.dumps([{"number": 1, "title": TITLE, "body": TITLE}], ensure_ascii=False).encode("utf-8")

    def test_gh_issues(self):
        with mock.patch.object(subprocess, "run", side_effect=_cp1252_console(self._issues())):
            rows, why = accounting._gh_issues("o/r", True, "all", body=True)
        self.assertIsNone(why)
        self.assertEqual(rows[0]["title"], TITLE)

    def test_gh_json(self):
        with mock.patch.object(subprocess, "run", side_effect=_cp1252_console(self._issues())):
            rows, why = accounting._gh_json(["gh", "issue", "view", "1"])
        self.assertIsNone(why)
        self.assertEqual(rows[0]["body"], TITLE)

    def test_design_gh(self):
        with mock.patch.object(subprocess, "run", side_effect=_cp1252_console(self._issues())):
            rows, why = design._gh(["repos/o/r/contents/design"])
        self.assertIsNone(why)
        self.assertEqual(rows[0]["title"], TITLE)

    def test_az_json(self):
        with (
            mock.patch.object(subprocess, "run", side_effect=_cp1252_console(self._issues())),
            mock.patch.object(accounting.log_writer, "write_log"),
        ):
            rows, why = accounting._az_json(["az", "boards", "query"], "agent/test", "boards query", "P")
        self.assertIsNone(why)
        self.assertEqual(rows[0]["title"], TITLE)

    def test_a_dead_reader_is_a_reason_everywhere(self):
        def dead(argv, **_kw):
            return subprocess.CompletedProcess(argv, 0, stdout=None, stderr=None)

        with (
            mock.patch.object(subprocess, "run", side_effect=dead),
            mock.patch.object(accounting.log_writer, "write_log"),
        ):
            self.assertEqual(
                accounting._gh_issues("o/r", True), ([], "o/r: gh's output could not be read (exit code 0)")
            )
            self.assertEqual(accounting._gh_labels("o/r"), ([], "o/r: gh's output could not be read (exit code 0)"))
            self.assertEqual(
                accounting._gh_json(["gh", "api", "x"]), (None, "gh's output could not be read (exit code 0)")
            )
            self.assertEqual(design._gh(["x"]), (None, "gh's output could not be read (exit code 0)"))
            rows, why = accounting._az_json(["az", "x"], "agent/test", "x", "P")
            self.assertEqual(rows, [])
            self.assertIn("could not be read", why)


class NoOtherCallDecodesWithTheLocale(unittest.TestCase):
    def test_every_text_call_in_agent_names_an_encoding(self):
        found: dict[str, int] = {}
        for path in sorted((REPO_ROOT / "agent").rglob("*.py")):
            rel = path.relative_to(REPO_ROOT).as_posix()
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                kw = {k.arg: k.value for k in node.keywords if k.arg}
                text = kw.get("text")
                if isinstance(text, ast.Constant) and text.value is True and "encoding" not in kw:
                    found[rel] = found.get(rel, 0) + 1
        self.assertEqual(
            found,
            NOT_GH_OR_AZ,
            "a text=True call with no encoding decodes with the console code page on "
            "Windows -- read gh/az/git through agent/core/child.py run_read",
        )


if __name__ == "__main__":
    unittest.main()
