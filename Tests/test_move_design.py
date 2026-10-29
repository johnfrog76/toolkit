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

    def test_to_complete_refusals(self):
        self.assert_refused("the-pair -To Complete", "-Doc <path> names the document it landed in")
        self.assert_refused(
            "the-pair -To Complete -Doc docs/nope.md", "-Doc docs/nope.md does not exist in this repository"
        )
        self.assert_refused("board-ideas -To Complete -Doc docs/board.md", "'Board ideas' is Design, not Spec")
        self.assert_refused("done -To Complete -Doc docs/board.md", "is Archived, not Spec")

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
        self.assert_refused("space-note -To Archive -Space demo", "-Space is the hub's", at=self.hub)

    # -- -Hub -Space -To Complete: -Doc is the Space's repository's, not the hub's ------

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


if __name__ == "__main__":
    unittest.main()
