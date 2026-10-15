"""The agent's one card writer keeps the card's bytes.

``agent/core/cards.write_card_text`` is the Python side of the rule
``Scripts/Write-CardText.ps1`` keeps for the CLI: UTF-8 with no BOM, and an
EDIT keeps the line ending the file already has. A CRLF card -- most of a
Windows hub -- edited with a bare ``write_text`` came back mixed
(item 2).

Run directly:  python3 Tests/test_card_writer.py
Under pytest:  python3 -m pytest Tests/
"""

import sys
import tempfile
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))

from agent.core.cards import CRLF, LF, detect_newline, write_card_text  # noqa: E402

BODY = "# Bug 62: A card\n\n## Section\n\nDecision: take\nReply: Fixed.\n"


class DetectNewline(unittest.TestCase):
    def test_lf(self):
        self.assertEqual(detect_newline(b"a\nb\n"), LF)
        self.assertEqual(detect_newline("a\nb\n"), LF)

    def test_crlf(self):
        self.assertEqual(detect_newline(b"a\r\nb\r\n"), CRLF)

    def test_a_mixed_file_reads_as_crlf(self):
        """One CRLF anywhere is the file's ending -- a mixed file is one a bad
        writer touched, and the next edit makes it consistent again."""
        self.assertEqual(detect_newline(b"a\r\nb\nc\n"), CRLF)

    def test_empty_is_lf(self):
        self.assertEqual(detect_newline(b""), LF)


class WriteCardText(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.card = Path(self._tmp.name) / "62-a-card.prompt.md"

    def tearDown(self):
        self._tmp.cleanup()

    def test_an_edit_of_a_crlf_card_comes_out_all_crlf(self):
        self.card.write_bytes(BODY.replace("\n", "\r\n").encode("utf-8"))
        write_card_text(self.card, BODY.replace("Reply: Fixed.", "Reply: Done."))
        data = self.card.read_bytes()
        self.assertEqual(data, BODY.replace("Reply: Fixed.", "Reply: Done.").replace("\n", "\r\n").encode("utf-8"))
        self.assertNotIn(b"[^\r]\n", data)
        self.assertEqual(data.count(b"\r\n"), data.count(b"\n"), "a bare LF slipped in")

    def test_an_edit_of_an_lf_card_comes_out_all_lf(self):
        self.card.write_bytes(BODY.encode("utf-8"))
        # The content handed in carries CRLF -- as an editor on Windows would.
        write_card_text(self.card, BODY.replace("\n", "\r\n"))
        data = self.card.read_bytes()
        self.assertEqual(data, BODY.encode("utf-8"))
        self.assertNotIn(b"\r", data)

    def test_a_mixed_card_comes_out_consistent(self):
        self.card.write_bytes(b"# Card\r\n\r\nDecision: take\nReply:\n")
        write_card_text(self.card, "# Card\n\nDecision: take\nReply: Done.\n")
        data = self.card.read_bytes()
        self.assertEqual(data, b"# Card\r\n\r\nDecision: take\r\nReply: Done.\r\n")

    def test_never_a_bom(self):
        self.card.write_bytes(b"\xef\xbb\xbf" + BODY.encode("utf-8"))
        write_card_text(self.card, BODY)
        self.assertFalse(self.card.read_bytes().startswith(b"\xef\xbb\xbf"))

    def test_utf8_survives(self):
        self.card.write_bytes(BODY.encode("utf-8"))
        write_card_text(self.card, BODY + "Reply: café — done\n")
        self.assertIn("café — done", self.card.read_text(encoding="utf-8"))

    def test_the_ado_core_has_one_card_writer(self):
        """No module in the ADO core -- the half that handles cards -- writes a
        file with a bare write_text: every edit goes through
        cards.write_card_text, as every CLI edit goes through Write-CardText.
        The two opt-in modules write their own records under their own
        contracts (docs/hub/manager.md, docs/hub/growth.md) and are not in
        scope here."""
        offenders = []
        for py in sorted((PKG_ROOT / "agent" / "ado").glob("*.py")):
            rel = py.relative_to(PKG_ROOT).as_posix()
            for i, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
                code = line.strip()
                if code.startswith("#"):
                    continue
                if ".write_text(" in code or ".write_bytes(" in code:
                    offenders.append(f"{rel}:{i}  {code[:80]}")
        self.assertEqual(offenders, [], "\n".join(offenders))


if __name__ == "__main__":
    unittest.main()
