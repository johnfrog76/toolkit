"""StampDesign (the Studio add-on; design lifecycle L1; docs/modules/studio.md, "The verbs").

The verb typed in a fresh shell -- this package's module and nothing else, per
AGENTS.md "One toolkit per shell" -- standing in a scratch repository, or with
-Hub against a scratch hub. Nothing here touches this repository's own design/.

Run:  python3 -m pytest Tests/test_stamp_design.py
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

from _shortpath import long_path, short_path  # noqa: E402

CONSTS = json.loads((PKG_ROOT / "consts.json").read_text(encoding="utf-8"))
ID_RX = CONSTS["design"]["idRegex"]


def _pwsh():
    return shutil.which("pwsh")


@unittest.skipIf(_pwsh() is None, "pwsh is not on this machine")
class TheStampDesignVerb(unittest.TestCase):
    EXISTING = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    KEPT = f'---\nid: {EXISTING}\ndescription: "already stamped"\n---\n\n# Kept\n\nbody\n'

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # LONG, once: tempfile is the 8.3 short form on some Windows accounts, and the
        # snippet's Set-Location refuses that form. The short form is tested on
        # purpose below.
        base = long_path(self._tmp.name)
        self.pkg = base / "pkg"
        self.hub = base / "hub"
        self.repo = base / "repo"
        self.bare = base / "norepo"
        self.pkg.mkdir()
        for item in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / item, self.pkg / item)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.hub / "demo" / "current").mkdir(parents=True)
        (self.hub / "hub.json").write_text(
            json.dumps(
                {
                    "orgs": [
                        {"slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo"},
                    ]
                }
            ),
            encoding="utf-8",
        )
        self.log = base / "log"
        self.log.mkdir()
        self.repo.mkdir()
        self.bare.mkdir()
        self.write(self.repo / "design/with-front.md", '---\ndescription: "has a block"\n---\n\n# With front\n')
        self.write(
            self.repo / "design/no-front.md",
            "# Feature: no block at all\n\n> GitHub: https://github.com/o/r/issues/1\n",
        )
        self.write(self.repo / "design/crlf-note.md", "# Windows note\r\n\r\nline two\r\n")
        self.write(self.repo / "design/kept.md", self.KEPT)
        self.write(self.repo / "design/README.md", "# Not a design\n")
        self.write(self.repo / "design/archive/old.md", "# Old\n")
        self.write(self.repo / "spec/with-front.spec.md", '---\ndescription: "the spec"\n---\n\n# With front (spec)\n')
        self.write(self.repo / "spec/kept.spec.md", "# Kept spec, its note is stamped\n")
        self.write(self.repo / "spec/lonely.spec.md", "# A spec with no note\n")
        self.write(self.repo / "spec/README.md", "# Not a spec\n")
        self.write(self.repo / "spec/archive/old.spec.md", "# Old spec\n")
        self.init_repo(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    @staticmethod
    def init_repo(path: Path):
        subprocess.run(["git", "init", "-q", str(path)], check=True, capture_output=True)

    @staticmethod
    def write(path: Path, text: str):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    @staticmethod
    def read(path: Path) -> str:
        return path.read_bytes().decode("utf-8")

    @staticmethod
    def snapshot(root: Path) -> dict:
        return {
            str(p): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in root.rglob("*")
            if p.is_file() and ".git" not in p.parts
        }

    @staticmethod
    def id_of(text: str):
        m = re.search(r"(?m)^id:\s*(\S+)\s*$", text)
        return m.group(1) if m else None

    def run_verbs(self, snippet: str, at: Path | None = None, hub: Path | None = None) -> str:
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": (hub or self.hub).as_posix(),
                    "activeOrg": "demo",
                    "quietStart": True,
                }
            ),
            encoding="utf-8",
        )

        def q(p):
            return str(p).replace("'", "''")

        at = at or self.repo
        # A Set-Location that fails must stop the snippet: carrying on would run the
        # verb wherever pytest stands -- this checkout -- and stamp ITS design/.
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

    def test_the_bridge_can_call_it(self):
        out = self.run_verbs("'MAP=' + (Get-P20CommandMap)")
        self.assertIn('"StampDesign"', out)

    def test_what_if_names_every_file_and_writes_none(self):
        before = self.snapshot(self.repo)
        out = self.run_verbs("tkStampDesign -WhatIf; 'X=' + $LASTEXITCODE")
        first = out.split("\n")[0]
        self.assertTrue(first.startswith("Git root: ") and first.endswith("repo"), out)
        for name in (
            "design/with-front.md",
            "design/no-front.md",
            "design/crlf-note.md",
            "design/archive/old.md",
            "spec/with-front.spec.md",
            "spec/kept.spec.md",
            "spec/lonely.spec.md",
            "spec/archive/old.spec.md",
        ):
            self.assertIn(name, out)
        self.assertNotIn("design/kept.md", out)
        self.assertNotIn("README", out)
        self.assertIn("Would stamp 8 files", out)
        self.assertIn("X=0", out)
        self.assertEqual(self.snapshot(self.repo), before, "-WhatIf wrote something")

    def test_the_stamp_pairing_and_the_bytes(self):
        out = self.run_verbs("tkStampDesign; 'X=' + $LASTEXITCODE")
        self.assertIn("Stamped 8 files; 1 already had an id", out)
        self.assertIn("X=0", out)
        with_front = self.read(self.repo / "design/with-front.md")
        id_a = self.id_of(with_front)
        self.assertRegex(with_front, r'\A---\nid: [0-9a-f-]{36}\ndescription: "has a block"\n---\n\n# With front\n\Z')
        self.assertRegex(id_a, ID_RX)
        self.assertRegex(
            self.read(self.repo / "design/no-front.md"),
            r"\A---\nid: [0-9a-f-]{36}\n---\n\n# Feature: no block at all\n\n> GitHub: https://github.com/o/r/issues/1\n\Z",
        )
        # a spec takes its note's id: the new one, and the one the note already had
        self.assertEqual(self.id_of(self.read(self.repo / "spec/with-front.spec.md")), id_a)
        self.assertEqual(self.id_of(self.read(self.repo / "spec/kept.spec.md")), self.EXISTING)
        old_note = self.id_of(self.read(self.repo / "design/archive/old.md"))
        self.assertRegex(old_note, ID_RX)
        self.assertEqual(self.id_of(self.read(self.repo / "spec/archive/old.spec.md")), old_note)
        ids = [
            self.id_of(self.read(self.repo / n))
            for n in (
                "design/with-front.md",
                "design/no-front.md",
                "design/crlf-note.md",
                "design/archive/old.md",
                "spec/lonely.spec.md",
            )
        ]
        self.assertEqual(len(set(ids)), 5, ids)
        self.assertTrue(all(re.match(ID_RX, i) for i in ids), ids)
        # README is not a design; an id that was there is untouched, byte for byte
        self.assertEqual(self.read(self.repo / "design/README.md"), "# Not a design\n")
        self.assertEqual(self.read(self.repo / "spec/README.md"), "# Not a spec\n")
        self.assertEqual(self.read(self.repo / "design/kept.md"), self.KEPT)
        # line endings: CRLF stays CRLF on every line, LF stays LF, no BOM
        crlf = (self.repo / "design/crlf-note.md").read_bytes()
        self.assertEqual(crlf.count(b"\n"), crlf.count(b"\r\n"), crlf)
        self.assertRegex(crlf.decode("utf-8"), r"\A---\r\nid: [0-9a-f-]{36}\r\n---\r\n\r\n# Windows note\r\n")
        for p in (self.repo / "design").rglob("*.md"):
            self.assertFalse(p.read_bytes().startswith(b"\xef\xbb\xbf"), p)
        self.assertNotIn(b"\r", (self.repo / "design/with-front.md").read_bytes())

    def test_a_second_run_writes_nothing(self):
        self.run_verbs("tkStampDesign")
        before = self.snapshot(self.repo)
        out = self.run_verbs("tkStampDesign; 'X=' + $LASTEXITCODE; tkStampDesign -WhatIf")
        self.assertIn("Stamped 0 files; 9 already had an id", out)
        self.assertIn("Would stamp 0 files", out)
        self.assertIn("X=0", out)
        self.assertEqual(self.snapshot(self.repo), before, "a second run changed a file (bytes or mtime)")

    def test_a_pair_that_disagrees_is_left_alone(self):
        self.write(self.repo / "design/split.md", "---\nid: 11111111-1111-4111-8111-111111111111\n---\n\n# Split\n")
        self.write(
            self.repo / "spec/split.spec.md", "---\nid: 22222222-2222-4222-8222-222222222222\n---\n\n# Split spec\n"
        )
        out = self.run_verbs("tkStampDesign")
        self.assertIn("conflict: 'split'", out)
        self.assertEqual(self.id_of(self.read(self.repo / "design/split.md")), "11111111-1111-4111-8111-111111111111")
        self.assertEqual(
            self.id_of(self.read(self.repo / "spec/split.spec.md")), "22222222-2222-4222-8222-222222222222"
        )

    def test_the_refusals_exit_2_once_and_write_nothing(self):
        out = self.run_verbs("tkStampDesign; 'X=' + $LASTEXITCODE", at=self.bare)
        self.assertIn("not inside a git repository", out)
        self.assertIn("X=2", out)
        self.assertEqual(out.count("Error:"), 1, out)
        empty = self.bare.parent / "emptyrepo"
        empty.mkdir()
        self.init_repo(empty)
        out = self.run_verbs("tkStampDesign; 'X=' + $LASTEXITCODE", at=empty)
        self.assertIn("has no design/ folder", out)
        self.assertIn("X=2", out)
        self.assertFalse((empty / "design").exists())
        out = self.run_verbs("tkStampDesign -Hub; 'X=' + $LASTEXITCODE", at=empty)
        self.assertIn("no design/ or spec/ folder", out)
        self.assertIn("X=2", out)

    def test_hub_stamps_the_hubs_folders_and_a_spaces_own_and_nothing_else(self):
        self.write(self.hub / "design/seed.md", "# Seed\n")
        self.write(self.hub / "spec/seed.spec.md", "# Seed spec\n")
        self.write(self.hub / "demo/spec/rules.spec.md", "# A Space's own spec\n")
        self.write(self.hub / "growth/design/ignored.md", "# Not a Space\n")
        self.write(self.repo / "design/should-not-change.md", "# In the repo\n")
        out = self.run_verbs("tkStampDesign -Hub -WhatIf; tkStampDesign -Hub; 'X=' + $LASTEXITCODE", at=self.bare)
        self.assertTrue(out.split("\n")[0].startswith("Hub: "), out)
        seed = self.id_of(self.read(self.hub / "design/seed.md"))
        self.assertRegex(seed, ID_RX)
        self.assertEqual(self.id_of(self.read(self.hub / "spec/seed.spec.md")), seed)
        self.assertRegex(self.id_of(self.read(self.hub / "demo/spec/rules.spec.md")), ID_RX)
        self.assertIsNone(self.id_of(self.read(self.hub / "growth/design/ignored.md")))
        self.assertEqual(self.read(self.repo / "design/should-not-change.md"), "# In the repo\n")
        self.assertIn("Stamped 3 files", out)
        self.assertIn("X=0", out)

    @unittest.skipUnless(sys.platform == "win32", "8.3 short names are a Windows thing")
    def test_a_hub_reached_through_a_short_windows_path(self):
        """promptsRoot as ``C:\\Users\\<name>~1.<domain>\\...``: the hub is named and walked in its
        long form, and stamped."""
        self.write(self.hub / "design/seed.md", "# Seed\n")
        short = short_path(self.hub)
        if short == self.hub:
            self.skipTest("this volume does not make 8.3 names")
        out = self.run_verbs("tkStampDesign -Hub; 'X=' + $LASTEXITCODE", at=self.bare, hub=short)
        first = out.split("\n")[0]
        self.assertTrue(first.startswith("Hub: "), out)
        self.assertNotIn("~", first, "the hub is named in its long form")
        self.assertNotIn("Error:", out)
        self.assertIn("Stamped 1 file;", out)
        self.assertIn("X=0", out)
        self.assertRegex(self.id_of(self.read(self.hub / "design/seed.md")), ID_RX)

    def test_what_new_design_writes_needs_no_stamp(self):
        self.run_verbs("tkNewDesign -Title 'Born stamped'", at=self.bare)
        out = self.run_verbs("tkStampDesign -Hub -WhatIf", at=self.bare)
        self.assertIn("Would stamp 0 files", out)


if __name__ == "__main__":
    unittest.main()
