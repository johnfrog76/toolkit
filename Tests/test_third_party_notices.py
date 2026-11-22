"""THIRD-PARTY-NOTICES.md is true to the repository.

The live case runs ``Scripts/third_party_notices.py``'s check against this tree: the web list
generated from ``web/package-lock.json``, every agent requirement listed at or above its floor, and
every font, picture, sound and ``web/public/`` file accounted for. The other cases hand the same functions a made-up
tree and prove each way the page can go stale is caught, by name. How a requirement line, a name
and a version are read is ``Scripts/requirement_rules.py``'s, held by the shared table in
``Tests/test_requirement_rules.py``.

Stdlib only; no agent import, so it never skips.

Run:  python3 -m pytest Tests/test_third_party_notices.py
"""

import importlib.util
import json
import tempfile
import unittest
from email.message import Message
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


# The agent section's table, as --write-agent draws it.
AGENT_BLOCK = """
From `agent/requirements.txt`, with the packages they pull in: 3 packages.

| License | Package | Version |
| --- | --- | --- |
| MIT | `fastapi` | 0.162.2 |
| BSD-3-Clause | `uvicorn` | 0.54.0 |
| Apache-2.0 | `anthropic` | 2.11.0 |
"""

# One row per input the floor comparison distinguishes: (requirement line, the problem it raises
# against AGENT_BLOCK, or None when it raises none).
FLOOR_TABLE = [
    ("fastapi>=0.163.0", "lists fastapi 0.162.2, below the floor fastapi>=0.163.0"),
    ("fastapi>=0.162.2", None),
    ("fastapi>=0.162", None),
    ("anthropic>=2.7.0", None),
    ("anthropic>=2.12", "lists anthropic 2.11.0, below the floor anthropic>=2.12"),
    ("uvicorn[standard]>=0.54.0", None),
    ("uvicorn[standard]>=0.55.0  # why", "lists uvicorn 0.54.0, below the floor uvicorn>=0.55.0"),
    ("pydantic>=2.14.3", "requires pydantic, which the agent section does not list"),
    ("Anthropic>=2.11.0", None),
    ("anthropic", None),
]


class TestAgentFloors(unittest.TestCase):
    def test_each_requirement_line_against_the_listed_versions(self):
        for line, want in FLOOR_TABLE:
            with self.subTest(line=line):
                found = N.agent_problems(AGENT_BLOCK, line + "\n")
                if want is None:
                    self.assertEqual(found, [])
                else:
                    self.assertEqual(len(found), 1, found)
                    self.assertIn(want, found[0])
                    self.assertIn(N.REQUIREMENTS, found[0])
                    self.assertIn("python Scripts/third_party_notices.py --write-agent", found[0])

    def test_the_rows_are_read_by_normalised_name(self):
        rows = N.listed_agent_packages(AGENT_BLOCK + "| MIT | `typing_extensions` | 4.16.0 |\n")
        self.assertEqual(rows[N.norm("Typing-Extensions")], ("typing_extensions", "4.16.0"))
        self.assertNotIn(N.norm("License"), rows)

    def test_the_floor_is_the_lowest_version_allowed(self):
        self.assertEqual(N.floor([(">=", "1.2"), ("<", "2")]), "1.2")
        self.assertEqual(N.floor([("==", "1.4.*")]), "1.4")
        self.assertEqual(N.floor([("~=", "2.1")]), "2.1")
        self.assertIsNone(N.floor([("<", "2"), ("!=", "1.5")]))
        self.assertIsNone(N.floor([]))


class Dist:
    """A stand-in for an installed distribution: a version and its METADATA headers."""

    def __init__(self, name, version, *headers):
        self.version = version
        self.metadata = Message()
        self.metadata["Name"] = name
        for key, value in headers:
            self.metadata[key] = value


def installed(*dists):
    table = {N.norm(d.metadata["Name"]): d for d in dists}

    def distribution(name):
        if N.norm(name) not in table:
            raise LookupError(name)
        return table[N.norm(name)]

    return distribution


ENV = dict(N.marker_environment(), sys_platform="linux", python_version="3.12", python_full_version="3.12.4")


class TestAgentResolve(unittest.TestCase):
    def test_the_walk_follows_markers_and_only_the_extras_asked_for(self):
        found = N.resolve_agent_packages(
            "web>=1.0\nsrv[standard]>=0.5\n",
            installed(
                Dist("web", "1.2", ("License-Expression", "MIT"), ("Requires-Dist", "core>=2"),
                     ("Requires-Dist", "old; python_version < '3.11'"), ("Requires-Dist", "full; extra == 'all'")),
                Dist("srv", "0.6", ("License", "BSD-3-Clause"), ("Requires-Dist", "fast; extra == 'standard'"),
                     ("Requires-Dist", "loop; sys_platform != 'win32' and extra == 'standard'")),
                Dist("core", "2.1", ("License", "MIT License"),
                     ("Classifier", "License :: OSI Approved :: Apache Software License"),
                     ("Classifier", "License :: OSI Approved :: MIT License"), ("Requires-Dist", "web")),
                Dist("fast", "3", ("License-Expression", "ISC")),
                Dist("loop", "0.1", ("License-Expression", "MIT")),
            ),
            ENV,
        )  # fmt: skip
        self.assertEqual(
            found,
            [
                ("core", "2.1", "MIT OR Apache-2.0"),
                ("fast", "3", "ISC"),
                ("loop", "0.1", "MIT"),
                ("srv", "0.6", "BSD-3-Clause"),
                ("web", "1.2", "MIT"),
            ],
        )

    def test_a_missing_or_too_old_requirement_stops_the_walk_by_name(self):
        with self.assertRaisesRegex(LookupError, "web .*not installed"):
            N.resolve_agent_packages("web>=1\n", installed(), ENV)
        with self.assertRaisesRegex(LookupError, "web 0.9 is installed, below the floor 1"):
            N.resolve_agent_packages("web>=1\n", installed(Dist("web", "0.9", ("License-Expression", "MIT"))), ENV)

    def test_a_license_nobody_declared_is_refused_rather_than_guessed(self):
        with self.assertRaisesRegex(LookupError, "odd: .*no license classifier"):
            N.package_license(Dist("odd", "1", ("License", "see the LICENSE file")).metadata)
        with self.assertRaisesRegex(LookupError, "unknown classifier"):
            N.package_license(Dist("odd", "1", ("Classifier", "License :: Other/Proprietary License")).metadata)

    def test_markers_read_as_pep_508_does(self):
        table = [
            ("", True),
            ("python_version < '3.13'", True),
            ("python_version >= '3.13'", False),
            ("python_full_version >= '3.12.4'", True),
            ("sys_platform != 'win32' and (sys_platform != 'cygwin' and platform_python_implementation != 'PyPy')",
             ENV["platform_python_implementation"] != "PyPy"),
            ("sys_platform == 'win32' or python_version == '3.12'", True),
            ("extra == 'standard'", False),
            ("'linux' in sys_platform", True),
            ("sys_platform not in 'win32 cygwin'", True),
        ]  # fmt: skip
        for marker, want in table:
            with self.subTest(marker=marker):
                self.assertEqual(N.marker_holds(marker, ENV), want)
        self.assertTrue(N.marker_holds("extra == 'Standard'", dict(ENV, extra="standard")))
        with self.assertRaises(ValueError):
            N.marker_holds("python_version <", ENV)

    def test_the_block_states_the_python_the_platform_and_the_date(self):
        block = N.render_pip_block(
            [("a", "1", "MIT"), ("b", "2", "ISC"), ("c", "3", "MIT")], "3.12.4", "Linux", "2026-01-02"
        )
        self.assertIn("3 packages", block)
        self.assertIn("Python 3.12.4 (Linux) on 2026-01-02", block)
        self.assertLess(block.index("| MIT | `c` | 3 |"), block.index("| ISC | `b` | 2 |"))
        self.assertEqual(N.listed_agent_packages(block)["b"], ("b", "2"))


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
