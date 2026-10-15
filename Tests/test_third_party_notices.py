"""THIRD-PARTY-NOTICES.md is true to the repository.

The live case runs ``Scripts/third_party_notices.py``'s check against this tree: the web list
generated from ``web/package-lock.json``, every agent requirement named, and every font, picture,
sound and ``web/public/`` file accounted for. The other cases hand the same functions a made-up
tree and prove each way the page can go stale is caught, by name.

Stdlib only; no agent import, so it never skips.

Run:  python3 -m pytest Tests/test_third_party_notices.py
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("third_party_notices", ROOT / "Scripts" / "third_party_notices.py")
N = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(N)

LOCK = {
    "packages": {
        "": {"name": "toolkit-web", "license": "MIT"},
        "node_modules/react": {"version": "19.0.0", "license": "MIT"},
        "node_modules/@scope/pkg": {"version": "1.2.3", "license": "ISC"},
        "node_modules/a/node_modules/react": {"version": "18.0.0", "license": "MIT"},
        "node_modules/vite": {"version": "7.0.0", "license": "MIT", "dev": True},
        "node_modules/odd": {"version": "0.1.0"},
    }
}

PAGE = """# Notices

## Web

<!-- notices:npm begin -->
old
<!-- notices:npm end -->

## Fonts, artwork and audio

| Where | What |
|---|---|
| `art/` | a folder |
| `pics/*.png` | a glob |
| `one/file.svg` | one file |
| `no/such/thing.png` | stale |
"""


class TestNoticesCases(unittest.TestCase):
    def test_production_packages_skip_dev_and_the_root(self):
        rows = N.production_packages(LOCK)
        self.assertEqual(
            rows,
            [
                ("@scope/pkg", "1.2.3", "ISC"),
                ("odd", "0.1.0", "UNKNOWN"),
                ("react", "18.0.0", "MIT"),
                ("react", "19.0.0", "MIT"),
            ],
        )

    def test_rendered_block_groups_by_license_with_one_line_each(self):
        block = N.render_npm_block(N.production_packages(LOCK))
        self.assertIn("4 packages", block)
        self.assertIn("#### MIT (2)", block)
        self.assertIn("| `react` | 18.0.0 |", block)
        self.assertIn("| `react` | 19.0.0 |", block)
        self.assertIn("| `@scope/pkg` | 1.2.3 |", block)
        self.assertIn("#### UNKNOWN (1)", block)
        self.assertNotIn("vite", block)

    def test_a_changed_lockfile_changes_the_block(self):
        later = json.loads(json.dumps(LOCK))
        later["packages"]["node_modules/react"]["version"] = "19.0.1"
        self.assertNotEqual(
            N.render_npm_block(N.production_packages(LOCK)), N.render_npm_block(N.production_packages(later))
        )

    def test_markers_must_both_be_there_in_order(self):
        self.assertIsNotNone(N.split_block(PAGE))
        self.assertIsNone(N.split_block(PAGE.replace(N.BEGIN, "")))
        self.assertIsNone(N.split_block(PAGE.replace(N.END, "")))
        self.assertIsNone(N.split_block(N.END + "\n" + N.BEGIN))

    def test_artwork_files_are_fonts_pictures_sounds_and_everything_served(self):
        files = ["a.woff2", "b.PNG", "c.mp3", "d.ts", "web/public/x/y.html", "web/src/z.tsx", "e.svg", "f.ttf"]
        self.assertEqual(N.artwork_files(files), ["a.woff2", "b.PNG", "c.mp3", "e.svg", "f.ttf", "web/public/x/y.html"])

    def test_entries_are_the_first_column_paths_only(self):
        body = N.section(PAGE, N.ASSETS_HEADING)
        self.assertEqual(N.entries(body), ["art/", "pics/*.png", "one/file.svg", "no/such/thing.png"])
        self.assertEqual(
            N.entries("| `@fluentui/react-icons` and `svg/` | `elsewhere/x` |"), ["@fluentui/react-icons", "svg/"]
        )
        self.assertEqual(N.entries("prose with `a/b` outside a table"), [])

    def test_an_entry_covers_a_file_a_folder_or_a_glob(self):
        self.assertTrue(N.covers("art/", "art/deep/x.png"))
        self.assertFalse(N.covers("art/", "artwork/x.png"))
        self.assertTrue(N.covers("pics/*.png", "pics/a.png"))
        self.assertFalse(N.covers("pics/*.png", "pics/a.jpg"))
        self.assertTrue(N.covers("one/file.svg", "one/file.svg"))
        self.assertFalse(N.covers("one/file.svg", "one/file.svg.bak"))

    def test_a_font_file_nobody_listed_is_uncovered(self):
        listed = N.entries(N.section(PAGE, N.ASSETS_HEADING))
        uncovered = [
            r
            for r in N.artwork_files(["art/a.png", "fonts/Plex.woff2", "web/public/s.html"])
            if not any(N.covers(e, r) for e in listed)
        ]
        self.assertEqual(uncovered, ["fonts/Plex.woff2", "web/public/s.html"])

    def test_requirement_names_ignore_extras_bounds_comments_and_includes(self):
        text = "# c\nfastapi>=0.1\nuvicorn[standard]>=0.5  # why\n-r other.txt\n\nPyYAML==6\n"
        self.assertEqual(N.requirement_names(text), ["fastapi", "uvicorn", "PyYAML"])
        self.assertEqual(N.norm("typing_extensions"), N.norm("Typing-Extensions"))


class TestNoticesAreTrueOnACrlfCheckout(unittest.TestCase):
    def test_the_page_is_read_as_lf_whatever_the_checkout_wrote(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "page.md").write_bytes(b"a\r\nb\r\n")
            original = N.ROOT
            N.ROOT = Path(tmp)
            try:
                self.assertEqual(N._read("page.md"), "a\nb\n")
            finally:
                N.ROOT = original


class TestNoticesAreTrue(unittest.TestCase):
    def test_the_page_agrees_with_the_repository(self):
        self.assertEqual(N.problems(), [])


if __name__ == "__main__":
    unittest.main()
