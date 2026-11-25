"""``file_in_folder``: a hub file is taken from its folder's own listing, by exact name.

One table, the rule's whole input space: the names the helper must not find,
one row per shape, and the names it must find. Every route that opens a hub file
by a requested name goes through it, and each route's own suite asserts the
route's answer for the same shapes.

Run:  python3 -m pytest Tests/test_file_in_folder.py
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from agent.core.config import file_in_folder
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the agent ({type(e).__name__}: {e})")

NAME = "2026-03-01.md"


class FileInFolder(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.folder = self.base / "hub" / "current"
        self.folder.mkdir(parents=True)
        (self.folder / NAME).write_text("# inside\n", encoding="utf-8")
        (self.folder / "a dir.md").mkdir()
        (self.base / "hub" / "beside.md").write_text("# beside\n", encoding="utf-8")
        (self.base / "outside.md").write_text("# outside\n", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_names_it_finds(self):
        found = file_in_folder(self.folder, NAME)
        self.assertEqual(found, self.folder / NAME)
        self.assertEqual(found.read_text(encoding="utf-8"), "# inside\n")
        (self.folder / "with space.prompt.md").write_text("x", encoding="utf-8")
        self.assertEqual(file_in_folder(self.folder, "with space.prompt.md"), self.folder / "with space.prompt.md")
        self.assertEqual(file_in_folder(str(self.folder), NAME), self.folder / NAME)

    def test_the_names_it_does_not_find(self):
        rows = {
            "a name that climbs": "../beside.md",
            "a name that climbs twice": "../../outside.md",
            "two dots alone": "..",
            "one dot alone": ".",
            "a forward slash in the name": f"sub/{NAME}",
            "a backslash in the name": f"..\\{NAME}",
            "an absolute path": str(self.base / "outside.md"),
            "an absolute path to a file in the folder": str(self.folder / NAME),
            "a colon in the name": f"D:{NAME}",
            "a colon in the name, same letter twice": f"C:{NAME}",
            "a name starting with a tilde": f"~/{NAME}",
            "a tilde alone": "~",
            "an empty name": "",
            "a NUL in the name": f"{NAME}\0",
            "a very long name": "x" * 4096 + ".md",
            "a directory's name": "a dir.md",
            "the name in other letter case": NAME.upper(),
            "the name with a trailing space": f"{NAME} ",
            "a name not in the folder": "2099-01-01.md",
        }
        for shape, name in rows.items():
            with self.subTest(shape=shape):
                self.assertIsNone(file_in_folder(self.folder, name))

    def test_a_link_is_not_a_regular_file(self):
        try:
            os.symlink(self.base / "outside.md", self.folder / "link.md")
            os.symlink(self.folder / NAME, self.folder / "inner-link.md")
        except (OSError, NotImplementedError) as e:
            self.skipTest(f"this host cannot create a symbolic link ({type(e).__name__})")
        self.assertIsNone(file_in_folder(self.folder, "link.md"))
        self.assertIsNone(file_in_folder(self.folder, "inner-link.md"))

    def test_a_folder_that_is_not_there_or_not_a_folder_has_no_files(self):
        self.assertIsNone(file_in_folder(self.base / "missing", NAME))
        self.assertIsNone(file_in_folder(self.folder / NAME, NAME))
        self.assertIsNone(file_in_folder(Path(f"{self.folder}\0"), NAME))


if __name__ == "__main__":
    unittest.main()
