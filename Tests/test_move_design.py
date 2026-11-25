"""MoveDesign (the Studio, core; design lifecycle L3; docs/modules/studio.md, "The verbs").

The verb typed in a fresh shell -- this package's module and nothing else, per
AGENTS.md "One toolkit per shell" -- standing in a scratch repository, or with
-Hub against a scratch hub. Nothing here touches this repository's own design/.

Every road (Spec, Archive shipped or dropped, Complete), every refusal in the
spec's table (exit 2, one sentence, nothing written), the journey lines, the
stamps, the bytes (LF for the scaffolded spec, a CRLF note kept CRLF), staging
without a commit in a repo, and storeSync in the hub.

Run:  python3 -m pytest Tests/test_move_design.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _shortpath import long_path  # noqa: E402

CONSTS = json.loads((PKG_ROOT / "consts.json").read_text(encoding="utf-8"))
CLOSED = CONSTS["stamps"]["closed"]
OUTCOME = CONSTS["stamps"]["outcome"]
DOCS = CONSTS["design"]["docsLine"]

ID_A = "aaaaaaaa-0000-4000-8000-000000000001"
ID_B = "bbbbbbbb-0000-4000-8000-000000000002"
ID_C = "cccccccc-0000-4000-8000-000000000003"
ID_D = "dddddddd-0000-4000-8000-000000000004"
ID_E = "eeeeeeee-0000-4000-8000-000000000005"
ID_F = "ffffffff-0000-4000-8000-000000000006"
TODAY_RX = r"\d{4}-\d{2}-\d{2}"


def _pwsh():
    return shutil.which("pwsh")


def _git(path: Path, *args: str) -> str:
    out = subprocess.run(["git", "-C", str(path), *args], capture_output=True, text=True, check=False)
    return out.stdout + out.stderr


def _staged(path: Path) -> list[str]:
    """The index as A / D / M lines, renames split: what was staged, not how git pairs it."""
    return sorted(_git(path, "status", "--porcelain", "--no-renames").strip().splitlines())


@unittest.skipIf(_pwsh() is None, "pwsh is not on this machine")
class TheMoveDesignVerb(unittest.TestCase):
    NOTE = (
        f'---\nid: {ID_A}\ndescription: "What the board could show next"\n---\n\n# Board ideas\n\n'
        "> GitHub: https://github.com/o/r/issues/90\n\n## The idea\n\nText.\n\n**Created:** 2026-10-01\n"
    )
    CRLF_NOTE = f"---\r\nid: {ID_B}\r\n---\r\n\r\n# A second room\r\n\r\nCRLF note.\r\n"
    PAIR_NOTE = f"---\nid: {ID_C}\ndescription: 'The pair'\n---\n\n# The pair\n\n**Created:** 2026-09-01\n"
    PAIR_SPEC = f"---\nid: {ID_C}\n---\n\n# The pair (spec)\n\nContract.\n"
    LONELY_SPEC = f"---\nid: {ID_D}\n---\n\n# Lonely (spec)\n"
    DONE_NOTE = f"---\nid: {ID_E}\n---\n\n# Done\n\n{CLOSED} 2026-09-30\n"

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = long_path(self._tmp.name)
        self.pkg = base / "pkg"
        self.hub = base / "hub"
        self.repo = base / "repo"
        self.pkg.mkdir()
        for item in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / item, self.pkg / item)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        self.log = base / "log"
        self.log.mkdir()
        # The hub: a declared Space with its own design/, the root design/ and spec/, under git.
        (self.hub / "demo" / "current").mkdir(parents=True)
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "storeSync": "git",
                    "orgs": [
                        {"slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo"},
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.write(
            self.hub / "design/hub-note.md", f"---\nid: {ID_A}\n---\n\n# A hub note\n\n**Created:** 2026-10-02\n"
        )
        self.write(self.hub / "demo/design/space-note.md", f"---\nid: {ID_B}\n---\n\n# A Space's note\n")
        self.init_repo(self.hub)
        self.commit(self.hub)
        # The repository.
        self.write(self.repo / "design/board-ideas.md", self.NOTE)
        self.write(self.repo / "design/a-second-room.md", self.CRLF_NOTE)
        self.write(self.repo / "design/the-pair.md", self.PAIR_NOTE)
        self.write(self.repo / "spec/the-pair.spec.md", self.PAIR_SPEC)
        self.write(self.repo / "spec/lonely.spec.md", self.LONELY_SPEC)
        self.write(self.repo / "design/archive/done.md", self.DONE_NOTE)
        self.write(self.repo / "design/unstamped.md", "# No id\n")
        self.write(self.repo / "docs/board.md", "# Board docs\n")
        self.init_repo(self.repo)
        subprocess.run(
            ["git", "-C", str(self.repo), "remote", "add", "origin", "https://github.com/o/r.git"], check=True
        )
        self.commit(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    @staticmethod
    def init_repo(path: Path):
        subprocess.run(["git", "init", "-q", str(path)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(path), "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", str(path), "config", "user.name", "t"], check=True)

    @staticmethod
    def commit(path: Path):
        subprocess.run(["git", "-C", str(path), "add", "-A"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(path), "commit", "-q", "-m", "init"], check=True, capture_output=True)

    @staticmethod
    def write(path: Path, text: str):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    @staticmethod
    def read(path: Path) -> str:
        return path.read_bytes().decode("utf-8")

    @staticmethod
    def snapshot(root: Path) -> dict:
        return {str(p): p.read_bytes() for p in root.rglob("*") if p.is_file() and ".git" not in p.parts}

    def run_verbs(self, snippet: str, at: Path | None = None, local: dict | None = None) -> str:
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": self.hub.as_posix(),
                    "activeOrg": "demo",
                    "quietStart": True,
                    **(local or {}),
                }
            ),
            encoding="utf-8",
        )

        def q(p):
            return str(p).replace("'", "''")

        at = at or self.repo
        body = (
            f"$env:PSModulePath = '{q(self.pkg)}'; $env:PROMPTS_ROOT = ''; $env:P20_USAGE_LOG_DIR = '{q(self.log)}'; "
            f"Import-Module '{q(self.pkg)}/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>$null 6>$null; "
            f"try {{ Set-Location -LiteralPath '{q(at)}' -ErrorAction Stop }} "
            f"catch {{ 'CD-FAILED: ' + $_; exit 97 }}; {snippet}"
        )
        env = {k: v for k, v in os.environ.items() if k != "PROMPTS_ROOT" and not k.startswith("TEAMS_WEBHOOK_")}
        out = subprocess.run(
            [_pwsh(), "-NoProfile", "-NonInteractive", "-Command", body],
            capture_output=True,
            text=True,
            timeout=240,
            env=env,
            check=False,
        )
        return out.stdout + out.stderr

    def move(self, args: str, at: Path | None = None, local: dict | None = None) -> str:
        return self.run_verbs(f"tkMoveDesign {args}; 'X=' + $LASTEXITCODE", at, local)

    def assert_refused(self, args: str, sentence: str, at: Path | None = None, local: dict | None = None):
        before = self.snapshot(at or self.repo)
        out = self.move(args, at, local)
        self.assertIn("X=2", out)
        self.assertEqual(out.count("Error:"), 1, out)
        self.assertIn(sentence, out)
        self.assertEqual(self.snapshot(at or self.repo), before, "a refusal wrote something")
        return out

    # -- The verb is there --------------------------------------------------------

    def test_the_bridge_can_call_it_and_help_answers(self):
        out = self.run_verbs("'MAP=' + (Get-P20CommandMap); tkMoveDesign -Help")
        self.assertIn('"MoveDesign"', out)
        self.assertIn("-To Spec|Archive|Complete", out)

    def test_what_if_names_the_git_root_and_writes_nothing(self):
        before = self.snapshot(self.repo)
        out = self.move("board-ideas -To Spec -WhatIf")
        first = out.strip().split("\n")[0]
        self.assertTrue(first.startswith("Git root: ") and first.endswith("repo"), out)
        self.assertIn("Would scaffold spec/board-ideas.spec.md", out)
        self.assertIn("Would append to design/board-ideas.md", out)
        self.assertIn("X=0", out)
        self.assertEqual(self.snapshot(self.repo), before)
        self.assertEqual(_git(self.repo, "status", "--porcelain").strip(), "")

    # -- -To Spec -------------------------------------------------------------------

    def test_to_spec_scaffolds_the_spec_and_writes_the_journey(self):
        out = self.move("board-ideas -To Spec")
        self.assertIn("X=0", out)
        spec = self.repo / "spec/board-ideas.spec.md"
        raw = spec.read_bytes()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), "a BOM")
        self.assertNotIn(b"\r\n", raw, "the scaffolded spec is LF")
        text = raw.decode("utf-8")
        self.assertTrue(
            text.startswith(
                f'---\nid: {ID_A}\ndescription: "What the board could show next"\n---\n\n'
                "# Board ideas (spec)\n\n> GitHub: https://github.com/o/r/issues/90\n\nVersion 0.1"
            ),
            text[:260],
        )
        note = self.read(self.repo / "design/board-ideas.md")
        self.assertRegex(
            note,
            r"## Journey\n\n- 2026-10-01 Design: written as design/board-ideas\.md in o/r\. "
            r"Thread: https://github\.com/o/r/issues/90\n- "
            + TODAY_RX
            + r" Spec: became spec/board-ideas\.spec\.md in o/r\.\n\n\*\*Created:\*\* 2026-10-01\n$",
        )
        # Staged, never committed: the product's history is the engineer's.
        self.assertEqual(_staged(self.repo), ["A  spec/board-ideas.spec.md", "M  design/board-ideas.md"])
        self.assertEqual(_git(self.repo, "rev-list", "--count", "HEAD").strip(), "1")
        self.assertIn("Staged, not committed", out)
        self.assertIn('git commit -m "design: Board ideas graduates to spec/board-ideas.spec.md"', out)

    def test_a_note_with_no_thread_gets_a_spec_without_the_line(self):
        self.move("a-second-room -To Spec")
        text = self.read(self.repo / "spec/a-second-room.spec.md")
        self.assertTrue(
            text.startswith(f'---\nid: {ID_B}\ndescription: ""\n---\n\n# A second room (spec)\n\nVersion 0.1'),
            text[:200],
        )
        self.assertNotIn("> GitHub:", text)
        # The CRLF note keeps its endings, journey and all; no Created line, so the
        # journey closes the file.
        raw = (self.repo / "design/a-second-room.md").read_bytes()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "a bare LF")
        self.assertIn(b"## Journey\r\n\r\n- ", raw)

    def test_to_spec_refusals(self):
        self.assert_refused("the-pair -To Spec", "already carries its id in spec/the-pair.spec.md")
        self.assert_refused("lonely -To Spec", "has no note to graduate")
        self.assert_refused("done -To Spec", "a note in design/archive/ does not graduate")
        self.write(self.repo / "spec/board-ideas.spec.md", "# Already here\n")
        self.assert_refused("board-ideas -To Spec", "spec/board-ideas.spec.md already exists. Not overwriting it.")

    # -- -To Archive ----------------------------------------------------------------

    def test_to_archive_shipped(self):
        out = self.move("a-second-room.md -To Archive")
        self.assertIn("X=0", out)
        self.assertFalse((self.repo / "design/a-second-room.md").exists())
        raw = (self.repo / "design/archive/a-second-room.md").read_bytes()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "a bare LF line in a CRLF note")
        text = raw.decode("utf-8").replace("\r\n", "\n")
        self.assertRegex(text, rf"{re.escape(CLOSED)} {TODAY_RX}\n{re.escape(OUTCOME)} shipped\n")
        self.assertRegex(
            text,
            r"\n- "
            + TODAY_RX
            + r" Shipped: shipped as written\. This note is now design/archive/a-second-room\.md in o/r\.\n",
        )
        # The journey sits above the stamps, not under them.
        self.assertLess(text.index("## Journey"), text.index(CLOSED))
        self.assertEqual(_staged(self.repo), ["A  design/archive/a-second-room.md", "D  design/a-second-room.md"])

    def test_to_archive_dropped_needs_its_reason_and_writes_it(self):
        self.assert_refused("a-second-room -To Archive -Dropped", "-Dropped needs -Reason")
        out = self.move('a-second-room -To Archive -Dropped -Reason "The Lounge already does this"')
        self.assertIn("X=0", out)
        text = self.read(self.repo / "design/archive/a-second-room.md").replace("\r\n", "\n")
        self.assertIn(f"{OUTCOME} dropped\n", text)
        self.assertRegex(
            text,
            r"- "
            + TODAY_RX
            + r" Dropped: The Lounge already does this\. This note is now design/archive/a-second-room\.md in o/r\.",
        )

    def test_to_archive_refusals(self):
        self.assert_refused(
            "the-pair -To Archive", "its spec spec/the-pair.spec.md is live, so the note does not archive alone"
        )
        self.assert_refused("lonely -To Archive", "has no note to archive")
        self.assert_refused("done -To Archive", "already in design/archive/done.md")
        self.write(self.repo / "design/archive/board-ideas.md", "# Already here\n")
        self.assert_refused(
            "board-ideas -To Archive", "design/archive/board-ideas.md already exists. Not overwriting it."
        )
        self.assert_refused("board-ideas -To Spec -Dropped", "-Dropped belongs to -To Archive")

    # -- -To Complete ---------------------------------------------------------------

    def test_to_complete_archives_both_and_writes_the_docs_line(self):
        out = self.move("cccccccc -To Complete -Doc docs/board.md")
        self.assertIn("X=0", out)
        self.assertFalse((self.repo / "design/the-pair.md").exists())
        self.assertFalse((self.repo / "spec/the-pair.spec.md").exists())
        spec = self.read(self.repo / "spec/archive/the-pair.spec.md")
        self.assertTrue(
            spec.startswith(f"---\nid: {ID_C}\n---\n\n# The pair (spec)\n\n{DOCS} docs/board.md\n\nContract.\n"), spec
        )
        self.assertRegex(spec, rf"{re.escape(CLOSED)} {TODAY_RX}\n$")
        note = self.read(self.repo / "design/archive/the-pair.md")
        self.assertRegex(
            note,
            r"- 2026-09-01 Design: written as design/the-pair\.md in o/r\.\n- "
            + TODAY_RX
            + r" Complete: built\. The docs are docs/board\.md\. This note is now design/archive/the-pair\.md "
            r"and the spec is spec/archive/the-pair\.spec\.md, in o/r\.\n",
        )
        self.assertRegex(note, rf"\*\*Created:\*\* 2026-09-01\n{re.escape(CLOSED)} {TODAY_RX}\n$")
        self.assertEqual(
            _staged(self.repo),
            [
                "A  design/archive/the-pair.md",
                "A  spec/archive/the-pair.spec.md",
                "D  design/the-pair.md",
                "D  spec/the-pair.spec.md",
            ],
        )
        self.assertEqual(_git(self.repo, "rev-list", "--count", "HEAD").strip(), "1")

    def test_a_spec_standing_alone_completes_without_a_note(self):
        out = self.move("lonely -To Complete -Doc docs/board.md")
        self.assertIn("X=0", out)
        self.assertTrue((self.repo / "spec/archive/lonely.spec.md").exists())
        self.assertIn(f"{DOCS} docs/board.md", self.read(self.repo / "spec/archive/lonely.spec.md"))

    # -- The Docs line: under the title the title rule finds, never above the frontmatter --

    TITLED_NOTE = f"---\nid: {ID_F}\n---\n\n# Titled\n"

    def complete_spec(self, spec_text: str) -> bytes:
        """A stamped note and its spec (the spec's text as given), completed: the archived spec's bytes."""
        self.write(self.repo / "design/titled.md", self.TITLED_NOTE)
        self.write(self.repo / "spec/titled.spec.md", spec_text)
        self.commit(self.repo)
        out = self.move("ffffffff -To Complete -Doc docs/board.md")
        self.assertIn("X=0", out)
        self.assertNotIn("Error:", out)
        return (self.repo / "spec/archive/titled.spec.md").read_bytes()

    def read_id(self, path: Path) -> str:
        """The id the CLI's reader takes from the file, '' for none."""
        scripts = str(self.pkg / "Scripts").replace("'", "''")
        file = str(path).replace("'", "''")
        out = self.run_verbs(
            f". (Join-Path '{scripts}' 'Read-DesignTree.ps1'); "
            f"'ID=' + (Get-P20FileId -Text ([System.IO.File]::ReadAllText('{file}')))"
        )
        m = re.search(r"ID=(\S*)", out)
        return m.group(1) if m else ""

    def test_a_spec_titled_by_a_second_level_heading_keeps_its_frontmatter_and_its_id(self):
        raw = self.complete_spec(f"---\nid: {ID_F}\n---\n\n## Title\nThe titled spec\n\n## Contract\n\nWords.\n")
        text = raw.decode("utf-8")
        self.assertTrue(text.startswith(f"---\nid: {ID_F}\n---\n"), text)
        self.assertEqual(text.count(DOCS), 1, text)
        self.assertTrue(
            text.startswith(
                f"---\nid: {ID_F}\n---\n\n## Title\nThe titled spec\n\n{DOCS} docs/board.md\n\n## Contract\n"
            ),
            text,
        )
        self.assertEqual(self.read_id(self.repo / "spec/archive/titled.spec.md"), ID_F)

    def test_a_crlf_spec_titled_by_a_second_level_heading_stays_crlf(self):
        raw = self.complete_spec(f"---\r\nid: {ID_F}\r\n---\r\n\r\n## Title\r\nThe titled spec\r\n\r\nWords.\r\n")
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "a bare LF line in a CRLF spec")
        self.assertTrue(
            raw.startswith(
                f"---\r\nid: {ID_F}\r\n---\r\n\r\n## Title\r\nThe titled spec\r\n\r\n{DOCS} docs/board.md\r\n\r\n"
                "Words.\r\n".encode()
            ),
            raw,
        )
        self.assertEqual(self.read_id(self.repo / "spec/archive/titled.spec.md"), ID_F)

    def test_a_spec_with_frontmatter_and_no_title_gets_the_line_as_its_first_body_line(self):
        raw = self.complete_spec(f"---\nid: {ID_F}\n---\n\n## Contract\n\nWords.\n")
        text = raw.decode("utf-8")
        self.assertTrue(text.startswith(f"---\nid: {ID_F}\n---\n\n{DOCS} docs/board.md\n\n## Contract\n"), text)
        self.assertEqual(self.read_id(self.repo / "spec/archive/titled.spec.md"), ID_F)

    def test_the_docs_line_placement_table(self):
        """The placement rule row by row, text in and text out, over the writer's own text half."""
        rows = [
            # A '# ' title: under it, as before.
            ("---\nid: x\n---\n\n# T\n\nWords.\n", "---\nid: x\n---\n\n# T\n\nD\n\nWords.\n"),
            ("---\nid: x\n---\n\n# T\nWords.\n", "---\nid: x\n---\n\n# T\n\nD\n\nWords.\n"),
            # A '## Title' section: under the title line, so the title still reads.
            ("---\nid: x\n---\n\n## Title\nT\n\n## C\n", "---\nid: x\n---\n\n## Title\nT\n\nD\n\n## C\n"),
            ("## Title\n\nT\n## C\n", "## Title\n\nT\n\nD\n\n## C\n"),
            # Frontmatter and no title the rule reads: the body's first line.
            ("---\nid: x\n---\n\n## C\n", "---\nid: x\n---\n\nD\n\n## C\n"),
            ("---\nid: x\n---\n## C\n\n# Deep\n", "---\nid: x\n---\n\nD\n\n## C\n\n# Deep\n"),
            ("---\nid: x\n---\n\n## Title\n\n## C\n", "---\nid: x\n---\n\nD\n\n## Title\n\n## C\n"),
            ("---\nid: x\n---\n", "---\nid: x\n---\n\nD\n"),
            # No frontmatter, no heading: the top, as before.
            ("Just words.\n", "\nD\n\nJust words.\n"),
            # The line is there already: nothing changes.
            ("---\nid: x\n---\n\n> Docs: a.md\n", "---\nid: x\n---\n\n> Docs: a.md\n"),
        ]
        payload = json.dumps([r[0] for r in rows]).replace("'", "''")
        scripts = str(self.pkg / "Scripts").replace("'", "''")
        out = self.run_verbs(
            f". (Join-Path '{scripts}' 'Read-DesignTree.ps1'); "
            f"$rows = '{payload}' | ConvertFrom-Json; "
            "$res = @(foreach ($r in $rows) { Add-P20DocsLineText -Text $r -DocsLine 'D' }); "
            "'JSON=' + (ConvertTo-Json -InputObject $res -Compress)"
        )
        got = json.loads(out[out.index("JSON=") + 5 :].strip().splitlines()[0])
        for (given, want), have in zip(rows, got, strict=True):
            self.assertEqual(have, want, given)

    def test_to_complete_refusals(self):
        self.assert_refused("the-pair -To Complete", "-Doc <path> names the document it landed in")
        self.assert_refused(
            "the-pair -To Complete -Doc docs/nope.md", "-Doc docs/nope.md does not exist in this repository"
        )
        self.assert_refused("board-ideas -To Complete -Doc docs/board.md", "'Board ideas' is Design, not Spec")
        self.assert_refused("done -To Complete -Doc docs/board.md", "is Archived, not Spec")

    # -- -To Archive -Dropped on a Spec ---------------------------------------------

    def test_dropping_a_spec_archives_both_files_together(self):
        self.assert_refused("the-pair -To Archive -Dropped", "-Dropped needs -Reason")
        out = self.move('cccccccc -To Archive -Dropped -Reason "Never built"')
        self.assertIn("X=0", out)
        self.assertFalse((self.repo / "design/the-pair.md").exists())
        self.assertFalse((self.repo / "spec/the-pair.spec.md").exists())
        spec = self.read(self.repo / "spec/archive/the-pair.spec.md")
        self.assertRegex(spec, rf"{re.escape(CLOSED)} {TODAY_RX}\n{re.escape(OUTCOME)} dropped\n$")
        self.assertNotIn(DOCS, spec)
        note = self.read(self.repo / "design/archive/the-pair.md")
        self.assertRegex(
            note,
            r"- 2026-09-01 Design: written as design/the-pair\.md in o/r\.\n- "
            + TODAY_RX
            + r" Dropped: Never built\. This note is now design/archive/the-pair\.md "
            r"and the spec is spec/archive/the-pair\.spec\.md, in o/r\.\n",
        )
        self.assertRegex(note, rf"{re.escape(CLOSED)} {TODAY_RX}\n{re.escape(OUTCOME)} dropped\n$")
        self.assertEqual(
            _staged(self.repo),
            [
                "A  design/archive/the-pair.md",
                "A  spec/archive/the-pair.spec.md",
                "D  design/the-pair.md",
                "D  spec/the-pair.spec.md",
            ],
        )

    def test_a_live_spec_still_refuses_archive_without_dropped(self):
        self.assert_refused("the-pair -To Archive", "its spec spec/the-pair.spec.md is live")
        self.assert_refused("the-pair -To Archive", "-To Archive -Dropped -Reason <text> drops both")

    def test_a_spec_standing_alone_can_be_dropped(self):
        out = self.move('lonely -To Archive -Dropped -Reason "No longer wanted"')
        self.assertIn("X=0", out)
        self.assertRegex(self.read(self.repo / "spec/archive/lonely.spec.md"), rf"{re.escape(OUTCOME)} dropped\n$")

    # -- A move never contradicts a line the file already carries ---------------------

    def note_with_outcome(self, value: str) -> Path:
        """board-ideas with an **Outcome:** line already written by hand."""
        path = self.repo / "design/board-ideas.md"
        self.write(path, self.NOTE + f"{OUTCOME} {value}\n")
        self.commit(self.repo)
        return path

    def test_a_different_doc_from_the_specs_docs_line_is_refused(self):
        self.write(
            self.repo / "spec/the-pair.spec.md", self.PAIR_SPEC.replace("Contract.", f"{DOCS} docs/a.md\n\nContract.")
        )
        self.commit(self.repo)
        for what_if in ("", " -WhatIf"):
            out = self.assert_refused(
                f"the-pair -To Complete -Doc docs/board.md{what_if}",
                f"spec/the-pair.spec.md already carries '{DOCS} docs/a.md', and -Doc names docs/board.md",
            )
            self.assertIn("MoveDesign the-pair -To Complete -Doc docs/a.md", out)
            self.assertNotIn("Would write", out)

    def test_the_same_doc_as_the_specs_docs_line_completes_and_writes_it_once(self):
        self.write(
            self.repo / "spec/the-pair.spec.md",
            self.PAIR_SPEC.replace("Contract.", f"{DOCS} docs/board.md\n\nContract."),
        )
        self.commit(self.repo)
        out = self.move("the-pair -To Complete -Doc docs/board.md -WhatIf")
        self.assertIn("X=0", out)
        self.assertIn(f"Would keep '{DOCS} docs/board.md' in spec/archive/the-pair.spec.md", out)
        out = self.move("the-pair -To Complete -Doc ./docs/board.md")
        self.assertIn("X=0", out)
        spec = self.read(self.repo / "spec/archive/the-pair.spec.md")
        self.assertEqual(spec.count(DOCS), 1, spec)
        self.assertIn("The docs are docs/board.md.", self.read(self.repo / "design/archive/the-pair.md"))

    def test_a_plain_archive_over_a_written_dropped_is_refused(self):
        self.note_with_outcome("dropped")
        for what_if in ("", " -WhatIf"):
            out = self.assert_refused(
                f"board-ideas -To Archive{what_if}",
                f"design/board-ideas.md already carries '{OUTCOME} dropped', and -To Archive would record it shipped",
            )
            self.assertIn("MoveDesign board-ideas -To Archive -Dropped -Reason", out)
            self.assertNotIn("Would stamp", out)

    def test_a_plain_archive_over_an_outcome_that_is_neither_word_is_refused(self):
        for value in ("Shipped 2026-11-20", "maybe"):
            self.note_with_outcome(value)
            for what_if in ("", " -WhatIf"):
                self.assert_refused(
                    f"board-ideas -To Archive{what_if}",
                    f"design/board-ideas.md already carries '{OUTCOME} {value}', which reads as no outcome",
                )

    def test_dropped_over_a_written_shipped_is_refused(self):
        self.note_with_outcome("shipped")
        for what_if in ("", " -WhatIf"):
            out = self.assert_refused(
                f'board-ideas -To Archive -Dropped -Reason "No"{what_if}',
                f"design/board-ideas.md already carries '{OUTCOME} shipped', "
                "and -To Archive -Dropped would record it dropped",
            )
            self.assertIn("MoveDesign board-ideas -To Archive", out)
        # On a Spec, the spec's own line is read too.
        self.write(self.repo / "spec/the-pair.spec.md", self.PAIR_SPEC + f"\n{OUTCOME} shipped\n")
        self.commit(self.repo)
        self.assert_refused(
            'the-pair -To Archive -Dropped -Reason "No"',
            f"spec/the-pair.spec.md already carries '{OUTCOME} shipped'",
        )

    def test_a_written_outcome_that_agrees_is_kept_and_said_once(self):
        self.note_with_outcome("Shipped")
        out = self.move("board-ideas -To Archive -WhatIf")
        self.assertIn("X=0", out)
        self.assertIn(f"and keep its {OUTCOME} Shipped", out)
        out = self.move("board-ideas -To Archive")
        self.assertIn("X=0", out)
        text = self.read(self.repo / "design/archive/board-ideas.md")
        self.assertEqual(text.count(OUTCOME), 1, text)
        self.assertIn("Shipped: shipped as written.", text)

    def test_a_dropped_spec_line_refuses_a_completion(self):
        self.write(self.repo / "spec/the-pair.spec.md", self.PAIR_SPEC + f"\n{OUTCOME} dropped\n")
        self.commit(self.repo)
        self.assert_refused(
            "the-pair -To Complete -Doc docs/board.md",
            f"spec/the-pair.spec.md already carries '{OUTCOME} dropped', and -To Complete would record it built",
        )

    def test_archiving_the_note_of_a_completed_design_is_refused(self):
        # The spec completed alone: the note is still live, the design reads Complete.
        self.write(self.repo / "spec/archive/board-ideas.spec.md", f"---\nid: {ID_A}\n---\n\n# Board ideas (spec)\n")
        self.commit(self.repo)
        for args in (
            "board-ideas -To Archive",
            "board-ideas -To Archive -WhatIf",
            'board-ideas -To Archive -Dropped -Reason "No"',
        ):
            out = self.assert_refused(
                args, "'Board ideas' is Complete: its spec is already spec/archive/board-ideas.spec.md"
            )
            self.assertIn("design/archive/", out)
            self.assertNotIn("shipped as written", out)

    # -- Naming the design ------------------------------------------------------------

    def test_names_an_id_prefix_a_file_or_a_stem_and_refuses_the_ambiguous_and_the_unknown(self):
        self.assert_refused("nothing-here -To Spec", "No design named 'nothing-here' in this repository")
        self.assert_refused("unstamped -To Spec", "design/unstamped.md is not a design yet: it carries no id")
        self.write(self.repo / "design/twin.md", "---\nid: aaaaaaaa-1111-4000-8000-000000000009\n---\n\n# Twin\n")
        self.assert_refused("aaaaaaaa -To Spec", "'aaaaaaaa' names 2 designs in this repository")
        self.assert_refused("-To Spec", "MoveDesign needs the design to move")
        self.assert_refused("board-ideas", "MoveDesign needs -To")
        out = self.move("the-pair.spec.md -To Complete -Doc docs/board.md -WhatIf")
        self.assertIn("Would move spec/the-pair.spec.md", out)

    # -- The hub: -Hub, -Hub -Space, storeSync ----------------------------------------

    def test_hub_moves_follow_store_sync(self):
        out = self.move("hub-note -To Archive -Hub", at=self.hub)
        self.assertIn("X=0", out)
        first = out.strip().split("\n")[0]
        self.assertTrue(first.startswith("Hub: ") and first.endswith("hub"), out)
        self.assertTrue((self.hub / "design/archive/hub-note.md").exists())
        self.assertIn("Committed.", out)
        self.assertEqual(_git(self.hub, "rev-list", "--count", "HEAD").strip(), "2")
        self.assertEqual(_git(self.hub, "status", "--porcelain").strip(), "")
        text = self.read(self.hub / "design/archive/hub-note.md")
        self.assertIn("This note is now design/archive/hub-note.md in the hub.", text)

    def test_a_hub_move_whose_commit_fails_is_a_stated_refusal(self):
        hook = self.hub / ".git" / "hooks" / "pre-commit"
        hook.write_bytes(b"#!/bin/sh\necho 'hook says no'\nexit 1\n")
        hook.chmod(0o755)  # git runs a hook only when it is executable; Windows ignores the bit
        out = self.move("hub-note -To Archive -Hub", at=self.hub)
        self.assertIn("X=2", out)
        self.assertEqual(out.count("Error:"), 1, out)
        self.assertIn("is not committed", out)
        self.assertIn("hook says no", out)
        self.assertIn("Hint:", out)
        self.assertNotIn("Committed.", out)
        self.assertTrue((self.hub / "design/archive/hub-note.md").exists(), "the move is on disk")
        self.assertFalse((self.hub / "design/hub-note.md").exists())
        self.assertEqual(_git(self.hub, "rev-list", "--count", "HEAD").strip(), "1")

    def test_hub_space_moves_that_spaces_own_folder(self):
        out = self.move("space-note -To Archive -Hub -Space demo -Dropped -Reason because", at=self.hub)
        self.assertIn("X=0", out)
        self.assertTrue((self.hub / "demo/design/archive/space-note.md").exists())
        self.assertIn("in the hub (demo).", self.read(self.hub / "demo/design/archive/space-note.md"))
        self.assert_refused("space-note -To Archive -Hub -Space nowhere", "No Space 'nowhere' is declared", at=self.hub)
        # -Space alone is the Space's own repository; Demo has no GitHub address, so no checkout.
        self.assert_refused(
            "space-note -To Archive -Space demo", "The Demo Space has no checkout here to move a design in", at=self.hub
        )
        self.assert_refused("space-note -To Archive -Space nowhere", "No Space 'nowhere' is declared", at=self.hub)

    # -- -Hub -Space -To Complete: -Doc is the Space's repository's, not the hub's ------

    def test_hub_space_complete_finds_the_clone_through_its_configured_checkout(self):
        archived = self.space_with_a_spec("https://github.com/o/r")
        local = {"spaceCheckouts": {"prod": {"path": self.repo.as_posix()}}}
        out = self.move("shipped -Hub -Space prod -To Complete -Doc docs/board.md", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertRegex(out, r"Doc: docs/board\.md in o/r at .*repo")
        self.assertIn(f"{DOCS} docs/board.md", self.read(archived))

    # -- -Space alone: the Space's own repository, in its checkout here (#146) ---------

    def commits(self, path: Path) -> int:
        return len(_git(path, "rev-list", "--all").split())

    def test_space_moves_stage_in_its_configured_checkout_and_never_commit(self):
        self.space_with_a_spec("https://github.com/o/r")
        local = {"spaceCheckouts": {"prod": {"path": self.repo.as_posix()}}}
        before = self.commits(self.repo)
        # Standing in the hub -- as the bridge stands in the package: the setting finds the clone.
        out = self.move("board-ideas -To Archive -Space prod", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertNotIn("Error:", out)
        first = out.strip().split("\n")[0]
        self.assertRegex(first, r"^Git root: .*repo \(the Prod Space's checkout\)$")
        self.assertIn("Staged, not committed. Suggested:", out)
        self.assertIn('git commit -m "design: Board ideas archived (shipped)"', out)
        self.assertNotIn("Committed.", out)
        self.assertEqual(self.commits(self.repo), before, "the move committed")
        self.assertEqual(_staged(self.repo), ["A  design/archive/board-ideas.md", "D  design/board-ideas.md"])
        self.assertIn(
            "This note is now design/archive/board-ideas.md in o/r.",
            self.read(self.repo / "design/archive/board-ideas.md"),
        )
        # The hub is untouched.
        self.assertEqual(_git(self.hub, "status", "--porcelain").strip(), "")

    def test_space_moves_take_every_road(self):
        self.space_with_a_spec("https://github.com/o/r")
        local = {"spaceCheckouts": {"prod": {"path": (self.repo / "design").as_posix()}}}  # a folder inside the clone
        out = self.move("board-ideas -To Spec -Space prod", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertTrue((self.repo / "spec/board-ideas.spec.md").exists())
        out = self.move("the-pair -To Complete -Doc docs/board.md -Space prod", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertTrue((self.repo / "spec/archive/the-pair.spec.md").exists())
        out = self.move("a-second-room -To Archive -Dropped -Reason no -Space prod", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertIn("Staged, not committed.", out)

    def test_a_space_with_no_checkout_here_refuses_and_names_the_setting(self):
        self.space_with_a_spec("https://github.com/o/r")
        out = self.assert_refused(
            "board-ideas -To Archive -Space prod",
            "The Prod Space has no checkout here to move a design in",
            at=self.hub,
        )
        self.assertIn("spaceCheckouts.prod.path is not set", out)
        self.assertIn("Config -Set spaceCheckouts.prod.path=", out)
        self.assertEqual(_staged(self.repo), [])

    def test_a_configured_checkout_of_another_repository_is_passed_over_and_said(self):
        self.space_with_a_spec("https://github.com/o/other")
        local = {"spaceCheckouts": {"prod": {"path": self.repo.as_posix()}}}
        out = self.assert_refused(
            "board-ideas -To Archive -Space prod", "The Prod Space has no checkout here", at=self.hub, local=local
        )
        self.assertIn("is a clone of o/r, not o/other", out)
        self.assertEqual(_staged(self.repo), [])

    def test_the_configured_checkout_wins_over_the_folder_you_stand_in(self):
        # A second clone of o/r: the setting is the one used, wherever you stand.
        second = self.hub.parent / "second"
        shutil.copytree(self.repo, second)
        self.space_with_a_spec("https://github.com/o/r")
        local = {"spaceCheckouts": {"prod": {"path": second.as_posix()}}}
        out = self.move("board-ideas -To Archive -Space prod", at=self.repo, local=local)
        self.assertIn("X=0", out)
        self.assertRegex(out.strip().split("\n")[0], r"second \(the Prod Space's checkout\)$")
        self.assertTrue((second / "design/archive/board-ideas.md").exists())
        self.assertTrue((self.repo / "design/board-ideas.md").exists())

    def space_with_a_spec(self, org: str) -> Path:
        """A Space 'prod' whose design and spec live in the hub, its address `org`."""
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "storeSync": "git",
                    "orgs": [
                        {"slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo"},
                        {"slug": "prod", "name": "Prod", "status": "local", "promptsFolder": "prod", "org": org},
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.write(self.hub / "prod/spec/shipped.spec.md", f"---\nid: {ID_D}\n---\n\n# Shipped (spec)\n\nContract.\n")
        # A document of the same name in the hub's own Space folder: never what -Doc means.
        self.write(self.hub / "prod/docs/hub-only.md", "# In the hub\n")
        self.commit(self.hub)
        return self.hub / "prod/spec/archive/shipped.spec.md"

    def test_hub_space_complete_finds_the_doc_in_the_clone_you_stand_in(self):
        archived = self.space_with_a_spec("https://github.com/o/r")
        # docs/board.md is in the repository (origin o/r), not in the hub.
        self.assertFalse((self.hub / "prod/docs/board.md").exists())
        out = self.move("shipped -Hub -Space prod -To Complete -Doc docs/board.md", at=self.repo)
        self.assertIn("X=0", out)
        self.assertNotIn("Error:", out)
        self.assertRegex(out, r"Doc: docs/board\.md in o/r at .*repo")
        self.assertIn(f"{DOCS} docs/board.md", self.read(archived))
        self.assertFalse((self.hub / "prod/spec/shipped.spec.md").exists())
        self.assertIn("Committed.", out)

    def test_hub_space_complete_finds_the_clone_through_a_nav_shortcut(self):
        archived = self.space_with_a_spec("https://github.com/o/r")
        local = {"aliases": {"Product": {"path": self.repo.as_posix(), "description": "the product"}}}
        out = self.move("shipped -Hub -Space prod -To Complete -Doc docs/board.md", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertRegex(out, r"Doc: docs/board\.md in o/r at .*repo")
        self.assertIn(f"{DOCS} docs/board.md", self.read(archived))

    def test_hub_space_complete_finds_the_clone_at_ws_root(self):
        # <wsRoot>/<repo name> is asked after the caller's candidates: a clone of o/r at ws/r.
        archived = self.space_with_a_spec("https://github.com/o/r")
        ws = self.repo.parent / "ws"
        clone = ws / "r"
        self.write(clone / "docs/board.md", "# Board docs\n")
        self.init_repo(clone)
        subprocess.run(["git", "-C", str(clone), "remote", "add", "origin", "https://github.com/o/r.git"], check=True)
        self.commit(clone)
        out = self.move(
            "shipped -Hub -Space prod -To Complete -Doc docs/board.md", at=self.hub, local={"wsRoot": ws.as_posix()}
        )
        self.assertIn("X=0", out)
        self.assertRegex(out, r"Doc: docs/board\.md in o/r at .*ws[/\\]r")
        self.assertIn(f"{DOCS} docs/board.md", self.read(archived))

    def test_hub_space_complete_with_no_clone_here_takes_the_doc_as_written(self):
        archived = self.space_with_a_spec("https://github.com/o/not-cloned-here")
        out = self.move("shipped -Hub -Space prod -To Complete -Doc docs/anywhere.md", at=self.hub)
        self.assertIn("X=0", out)
        self.assertNotIn("Error:", out)
        self.assertIn("Note: -Doc docs/anywhere.md is taken as written, not checked: for the Prod Space,", out)
        self.assertIn("no clone of o/not-cloned-here was found on this machine", out)
        self.assertIn(f"{DOCS} docs/anywhere.md", self.read(archived))

    def test_hub_space_complete_refuses_a_doc_missing_from_the_clone_and_says_where_it_looked(self):
        self.space_with_a_spec("https://github.com/o/r")
        local = {"aliases": {"Product": {"path": self.repo.as_posix(), "description": "the product"}}}
        for doc in ("docs/nope.md", "prod/docs/hub-only.md", "docs/hub-only.md"):
            out = self.assert_refused(
                f"shipped -Hub -Space prod -To Complete -Doc {doc}",
                f"-Doc {doc} does not exist in o/r, the Prod Space's repository, checked out at ",
                at=self.hub,
                local=local,
            )
            self.assertRegex(out, r"checked out at .*repo")
        self.assertTrue((self.hub / "prod/spec/shipped.spec.md").exists())

    def test_in_repo_and_hub_root_complete_still_look_in_their_own_tree(self):
        # In a repository, -Doc is that repository's, whatever the Spaces say.
        self.space_with_a_spec("https://github.com/o/r")
        self.assert_refused(
            "the-pair -To Complete -Doc docs/nope.md", "-Doc docs/nope.md does not exist in this repository"
        )
        out = self.move("lonely -To Complete -Doc docs/board.md")
        self.assertIn("X=0", out)
        self.assertNotIn("Doc: docs/board.md in", out)
        # -Hub with no -Space: the hub's own tree, as before.
        self.write(self.hub / "spec/hub-note.spec.md", f"---\nid: {ID_A}\n---\n\n# A hub note (spec)\n")
        self.commit(self.hub)
        self.assert_refused("hub-note -Hub -To Complete -Doc docs/board.md", "does not exist in the hub.", at=self.hub)

    def test_to_spec_makes_the_spec_folder_when_there_is_none(self):
        # The one move that did not create its target folder threw from the writer.
        self.assertFalse((self.hub / "spec").exists())
        out = self.move("hub-note -To Spec -Hub", at=self.hub)
        self.assertIn("X=0", out)
        self.assertNotIn("Could not find a part of the path", out)
        self.assertTrue((self.hub / "spec/hub-note.spec.md").exists(), out)
        self.assertIn(f"id: {ID_A}", self.read(self.hub / "spec/hub-note.spec.md"))
        # and the same in a repository whose design/ has never graduated anything
        shutil.rmtree(self.repo / "spec")
        _git(self.repo, "add", "-A")
        out = self.move("board-ideas -To Spec")
        self.assertIn("X=0", out)
        self.assertNotIn("Could not find a part of the path", out)
        self.assertTrue((self.repo / "spec/board-ideas.spec.md").exists(), out)

    def test_a_completion_stamps_the_spec_after_a_blank_line(self):
        out = self.move("cccccccc -To Complete -Doc docs/board.md")
        self.assertIn("X=0", out)
        spec = self.read(self.repo / "spec/archive/the-pair.spec.md")
        self.assertRegex(spec, rf"Contract\.\n\n{re.escape(CLOSED)} {TODAY_RX}\n$")

    def test_outside_a_repository_it_refuses_and_points_at_hub(self):
        bare = self.hub.parent / "bare"
        bare.mkdir()
        out = self.move("x -To Spec", at=bare)
        self.assertIn("X=2", out)
        self.assertIn("is not inside a git repository", out)

    # -- -Ready: what the tree says is ready, and what is held -----------------------

    def rid(self, n: int) -> str:
        return f"10000000-0000-4000-8000-{n:012d}"

    def marked_tree(self):
        """One design per row of the marker's table that the read tells apart, in the repository."""
        r = self.repo
        rid = self.rid
        note = lambda n, title, tail="": f"---\nid: {rid(n)}\n---\n\n# {title}\n\nText.\n{tail}"  # noqa: E731
        spec = lambda n, title, tail="": f"---\nid: {rid(n)}\n---\n\n# {title}\n\n{tail}Contract.\n"  # noqa: E731
        self.write(
            r / "design/m01-shipped.md",
            note(1, "Shipped as written", f"\n**Created:** 2026-10-01\n{OUTCOME} shipped\n"),
        )
        self.write(r / "design/m02-loud.md", note(2, "Shipped, loudly", f"\n{OUTCOME} SHIPPED\n"))
        self.write(r / "design/m03-dropped.md", note(3, "Marked dropped", f"\n{OUTCOME} dropped\n"))
        self.write(r / "design/m04-dated.md", note(4, "Shipped with a date", f"\n{OUTCOME} shipped 2026-11-20\n"))
        self.write(r / "design/m06-pair.md", note(6, "A note marked over a live spec", f"\n{OUTCOME} shipped\n"))
        self.write(r / "spec/m06-pair.spec.md", spec(6, "Pair (spec)"))
        self.write(r / "design/m07-docs.md", note(7, "Built and documented"))
        self.write(r / "spec/m07-docs.spec.md", spec(7, "Docs (spec)", f"{DOCS} docs/board.md\n\n"))
        self.write(r / "spec/m07b-alone.spec.md", spec(17, "A spec alone, documented", f"{DOCS} docs/board.md\n\n"))
        self.write(r / "design/m08-conflict.md", note(8, "Documented but dropped", f"\n{OUTCOME} dropped\n"))
        self.write(r / "spec/m08-conflict.spec.md", spec(8, "Conflict (spec)", f"{DOCS} docs/board.md\n\n"))
        self.write(r / "spec/m10-missing.spec.md", spec(10, "Docs nowhere (spec)", f"{DOCS} docs/nope.md\n\n"))
        self.write(r / "design/archive/m11-early.md", note(11, "A note archived early", f"\n{CLOSED} 2026-10-01\n"))
        self.write(r / "spec/m11-early.spec.md", spec(11, "Early (spec)", f"{DOCS} docs/board.md\n\n"))
        self.write(
            r / "design/archive/m12-done.md", note(12, "Long done", f"\n{CLOSED} 2026-09-01\n{OUTCOME} shipped\n")
        )
        self.write(r / "spec/archive/m12-done.spec.md", spec(12, "Done (spec)", f"{DOCS} docs/board.md\n\n"))
        self.write(r / "design/m13-left.md", note(13, "Left behind", f"\n{OUTCOME} shipped\n"))
        self.write(r / "spec/archive/m13-left.spec.md", spec(13, "Left (spec)", f"{CLOSED} 2026-10-02\n\n"))
        self.write(
            r / "spec/m15-titled.spec.md",
            f"---\nid: {rid(15)}\n---\n\n## Title\n\nTitled the second way\n\n{DOCS} docs/board.md\n",
        )
        self.commit(r)
        # An open card worked against the first design, in the hub's Space.
        self.write(
            self.hub / "demo/current/Task141-board-work.md",
            f"# Task 141: Board work\n\n> Design: [Shipped as written](../../x.md) {rid(1)}\n",
        )
        self.commit(self.hub)

    READY_IDS = {1: "Archive", 2: "Archive", 7: "Complete", 17: "Complete", 11: "Complete", 15: "Complete"}
    HELD_IDS = {3, 4, 6, 8, 10, 13}

    def ready_json(self, flags: str = "", at: Path | None = None, local: dict | None = None) -> dict:
        out = self.run_verbs(f"tkMoveDesign -Ready -AsJson {flags}; 'X=' + $LASTEXITCODE", at, local)
        self.assertIn("X=0", out)
        lines = [line for line in out.splitlines() if line.startswith("{")]
        self.assertEqual(len(lines), 1, f"-AsJson prints one JSON line and nothing else:\n{out}")
        others = [line for line in out.splitlines() if line.strip() and not line.startswith("{") and line != "X=0"]
        self.assertEqual(others, [], out)
        return json.loads(lines[0])

    def test_ready_with_nothing_marked_says_so_in_one_line(self):
        before = self.snapshot(self.repo)
        out = self.move("-Ready")
        self.assertIn("X=0", out)
        lines = [line for line in out.strip().splitlines() if line.strip() and line != "X=0"]
        self.assertEqual(len(lines), 2, out)
        self.assertRegex(lines[0], r"^Git root: ")
        self.assertEqual(
            lines[1], "No design in this repository is marked finished: nothing is ready, and nothing is held."
        )
        self.assertEqual(self.ready_json(), {"ready": [], "held": [], "counts": {"ready": 0, "held": 0}})
        self.assertEqual(self.snapshot(self.repo), before)

    def test_ready_lists_the_ready_and_the_held_and_moves_nothing(self):
        self.marked_tree()
        before_repo, before_hub = self.snapshot(self.repo), self.snapshot(self.hub)
        data = self.ready_json()
        ready = {d["id"]: d for d in data["ready"]}
        held = {d["id"]: d for d in data["held"]}
        self.assertEqual(set(ready), {self.rid(n) for n in self.READY_IDS})
        self.assertEqual(set(held), {self.rid(n) for n in self.HELD_IDS})
        self.assertEqual(data["counts"], {"ready": 6, "held": 6})
        for n, to in self.READY_IDS.items():
            row = ready[self.rid(n)]
            self.assertEqual(set(row), {"id", "title", "state", "call", "args", "notes"})
            self.assertEqual(row["state"], "Design" if to == "Archive" else "Spec")
            if to == "Archive":
                self.assertEqual(row["call"], f"tkMoveDesign {self.rid(n)} -To Archive")
                self.assertEqual(row["args"], [self.rid(n), "-To", "Archive"])
            else:
                self.assertEqual(row["call"], f'tkMoveDesign {self.rid(n)} -To Complete -Doc "docs/board.md"')
                self.assertEqual(row["args"], [self.rid(n), "-To", "Complete", "-Doc", "docs/board.md"])
        # A shipped mark with an open card is ready; the card is named, as information.
        self.assertEqual(
            ready[self.rid(1)]["notes"],
            [
                (
                    "Open card worked against it: Task141-board-work. "
                    "The mark is the decision; the move does not wait for them."
                )
            ],
        )
        self.assertIn("Its note is already design/archive/m11-early.md", ready[self.rid(11)]["notes"][0])
        self.assertEqual(ready[self.rid(7)]["notes"], [])
        reasons = {n: held[self.rid(n)]["reason"] for n in self.HELD_IDS}
        self.assertIn("-To Archive -Dropped -Reason", reasons[3])
        self.assertIn("'**Outcome:** shipped 2026-11-20', which is neither shipped nor dropped", reasons[4])
        self.assertIn("its spec spec/m06-pair.spec.md is live", reasons[6])
        self.assertIn("the two marks disagree", reasons[8])
        self.assertEqual(
            reasons[10], "MoveDesign would refuse it: -Doc docs/nope.md does not exist in this repository."
        )
        self.assertIn("It is Complete: its spec is already spec/archive/m13-left.spec.md", reasons[13])
        self.assertIn("by hand", reasons[13])
        self.assertNotIn("#", reasons[13].replace("## Journey", ""), "no issue number in the output")
        self.assertEqual({held[self.rid(n)]["state"] for n in (3, 4)}, {"Design"})
        self.assertEqual(held[self.rid(13)]["state"], "Complete")

        # The text says the same, ready first, then held, then one count line.
        text = self.move("-Ready")
        self.assertIn("X=0", text)
        for row in data["ready"]:
            self.assertIn(f"  {row['title']} ({row['state']}, {row['id']})\n    {row['call']}\n", text)
            for note in row["notes"]:
                self.assertIn(f"    Note: {note}", text)
        for row in data["held"]:
            self.assertIn(f"  {row['title']} ({row['state']}, {row['id']})\n    {row['reason']}\n", text)
        self.assertLess(text.index("Ready (6)"), text.index("Held (6)"))
        self.assertIn("6 ready, 6 held in this repository. Nothing was moved.", text)
        self.assertNotIn("Error:", text)
        # Nothing moved, nothing written, nothing staged -- with -WhatIf too.
        self.assertIn("6 ready, 6 held", self.move("-Ready -WhatIf"))
        self.assertEqual(self.snapshot(self.repo), before_repo)
        self.assertEqual(self.snapshot(self.hub), before_hub)
        self.assertEqual(_staged(self.repo), [])

    def test_every_ready_call_run_as_printed_succeeds_and_a_held_one_is_refused(self):
        self.marked_tree()
        data = self.ready_json()
        script = "; ".join(f"{row['call']}; 'X{row['id']}=' + $LASTEXITCODE" for row in data["ready"])
        out = self.run_verbs(script)
        for row in data["ready"]:
            self.assertIn(f"X{row['id']}=0", out)
        self.assertNotIn("Error:", out)
        r = self.repo
        for name in ("m01-shipped", "m02-loud"):
            self.assertTrue((r / f"design/archive/{name}.md").exists(), name)
            self.assertIn(f"{OUTCOME} shipped".lower(), self.read(r / f"design/archive/{name}.md").lower())
        for name in ("m07-docs", "m07b-alone", "m11-early", "m15-titled"):
            self.assertTrue((r / f"spec/archive/{name}.spec.md").exists(), name)
            self.assertFalse((r / f"spec/{name}.spec.md").exists(), name)
        self.assertTrue((r / "design/archive/m07-docs.md").exists())
        # The read now lists only what is held.
        after = self.ready_json()
        self.assertEqual(after["ready"], [])
        self.assertEqual({d["id"] for d in after["held"]}, {self.rid(n) for n in self.HELD_IDS})
        # Each held design's implied move is refused by MoveDesign itself.
        before = self.snapshot(self.repo)
        implied = {
            3: "-To Archive",
            4: "-To Archive",
            6: "-To Archive",
            8: '-To Complete -Doc "docs/board.md"',
            10: '-To Complete -Doc "docs/nope.md"',
            13: "-To Archive",
        }
        for n, move in implied.items():
            self.assertIn("X=2", self.move(f"{self.rid(n)} {move}"), n)
        self.assertEqual(self.snapshot(self.repo), before)

    def test_ready_refuses_anything_that_names_or_shapes_a_move(self):
        self.marked_tree()
        for args in (
            "-Ready -To Archive",
            f"{self.rid(1)} -Ready",
            "-Ready -Doc docs/board.md",
            "-Ready -Dropped",
            "-Ready -Reason why",
        ):
            self.assert_refused(args, "-Ready only lists: it moves nothing, so it takes no ")
        self.assert_refused("-Ready -To Archive -WhatIf", "-Ready only lists")
        self.assert_refused(f"{self.rid(1)} -To Archive -AsJson", "-AsJson belongs to -Ready")

    def test_ready_in_the_hub_carries_the_flags_and_says_an_unchecked_docs_path(self):
        self.space_with_a_spec("https://github.com/o/not-cloned-here")
        self.write(
            self.hub / "prod/spec/shipped.spec.md",
            f"---\nid: {ID_D}\n---\n\n# Shipped (spec)\n\n{DOCS} docs/anywhere.md\n",
        )
        self.write(self.hub / "design/hub-note.md", f"---\nid: {ID_A}\n---\n\n# A hub note\n\n{OUTCOME} shipped\n")
        self.commit(self.hub)
        before = self.snapshot(self.hub)
        data = self.ready_json("-Hub -Space prod", at=self.hub)
        self.assertEqual(len(data["ready"]), 1, data)
        row = data["ready"][0]
        self.assertEqual(row["call"], f'tkMoveDesign {ID_D} -To Complete -Doc "docs/anywhere.md" -Hub -Space prod')
        self.assertEqual(row["args"][-3:], ["-Hub", "-Space", "prod"])
        self.assertEqual(len(row["notes"]), 1)
        self.assertTrue(
            row["notes"][0].startswith("-Doc docs/anywhere.md is taken as written, not checked: for the Prod Space,")
        )
        hub_root = self.ready_json("-Hub", at=self.hub)
        self.assertEqual([r["call"] for r in hub_root["ready"]], [f"tkMoveDesign {ID_A} -To Archive -Hub"])
        self.assertEqual(self.snapshot(self.hub), before)
        self.assertEqual(_git(self.hub, "status", "--porcelain").strip(), "")
        # Where the Space's clone IS here and the path is missing from it, MoveDesign would refuse: held.
        self.space_with_a_spec("https://github.com/o/r")
        local = {"spaceCheckouts": {"prod": {"path": self.repo.as_posix()}}}
        self.write(
            self.hub / "prod/spec/shipped.spec.md", f"---\nid: {ID_D}\n---\n\n# Shipped (spec)\n\n{DOCS} docs/nope.md\n"
        )
        data = self.ready_json("-Hub -Space prod", at=self.hub, local=local)
        self.assertEqual(data["ready"], [])
        self.assertIn("MoveDesign would refuse it: -Doc docs/nope.md does not exist in o/r", data["held"][0]["reason"])
        # And the call as printed for a checked path runs.
        self.write(
            self.hub / "prod/spec/shipped.spec.md",
            f"---\nid: {ID_D}\n---\n\n# Shipped (spec)\n\n{DOCS} docs/board.md\n",
        )
        self.commit(self.hub)
        data = self.ready_json("-Hub -Space prod", at=self.hub, local=local)
        self.assertEqual(data["ready"][0]["notes"], [])
        out = self.run_verbs(f"{data['ready'][0]['call']}; 'X=' + $LASTEXITCODE", at=self.hub, local=local)
        self.assertIn("X=0", out)
        self.assertTrue((self.hub / "prod/spec/archive/shipped.spec.md").exists())

    def test_ready_for_a_space_repository_carries_its_flag(self):
        self.space_with_a_spec("https://github.com/o/r")
        self.marked_tree()
        local = {"spaceCheckouts": {"prod": {"path": self.repo.as_posix()}}}
        data = self.ready_json("-Space prod", at=self.hub, local=local)
        self.assertIn(f"tkMoveDesign {self.rid(1)} -To Archive -Space prod", [r["call"] for r in data["ready"]])
        out = self.run_verbs(
            f"tkMoveDesign {self.rid(1)} -To Archive -Space prod; 'X=' + $LASTEXITCODE", self.hub, local
        )
        self.assertIn("X=0", out)


if __name__ == "__main__":
    unittest.main()
