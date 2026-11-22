"""The one reading of a requirement line, a package name and a version.

``Scripts/requirement_rules.py`` is what ``Scripts/requirements_floors.py`` and
``Scripts/third_party_notices.py`` both read requirements and compare versions with, so the two
checks cannot disagree about whether a package is below its floor. Every row of the shared table
``Tests/fixtures/requirements/table.json`` is asserted here, and each script is shown to read
through this module rather than a copy of its own.

Stdlib only; no agent import, so it never skips.

Run:  python3 -m pytest Tests/test_requirement_rules.py
"""

import importlib.util
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "Scripts"
TABLE = json.loads((ROOT / "Tests" / "fixtures" / "requirements" / "table.json").read_text(encoding="utf-8"))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R = _load("requirement_rules")


class TestLines(unittest.TestCase):
    def test_every_line(self):
        for line, want in TABLE["lines"]:
            with self.subTest(line=line):
                got = R.parse_requirement(line)
                if want is None:
                    self.assertIsNone(got)
                    continue
                self.assertIsNotNone(got)
                name, extras, specs, marker = got
                self.assertEqual(name, want["name"])
                self.assertEqual(sorted(extras), want["extras"])
                self.assertEqual([list(s) for s in specs], want["specs"])
                self.assertEqual(marker, want["marker"])


class TestNames(unittest.TestCase):
    def test_every_name(self):
        for name, want in TABLE["names"]:
            with self.subTest(name=name):
                self.assertEqual(R.normalise_name(name), want)


class TestVersions(unittest.TestCase):
    def test_ascending_is_strictly_increasing(self):
        keys = [R.version_key(v) for v in TABLE["versions"]["ascending"]]
        self.assertNotIn(None, keys)
        for (a, ka), (b, kb) in zip(
            zip(TABLE["versions"]["ascending"], keys), zip(TABLE["versions"]["ascending"][1:], keys[1:])
        ):
            with self.subTest(lower=a, higher=b):
                self.assertLess(ka, kb)

    def test_equal_pairs_read_as_one_version(self):
        for a, b in TABLE["versions"]["equal"]:
            with self.subTest(a=a, b=b):
                self.assertIsNotNone(R.version_key(a))
                self.assertEqual(R.version_key(a), R.version_key(b))

    def test_unreadable_text_is_none(self):
        for text in TABLE["versions"]["unreadable"]:
            with self.subTest(text=text):
                self.assertIsNone(R.version_key(text))

    def test_the_release_as_written(self):
        for text, want in TABLE["release"]:
            with self.subTest(text=text):
                self.assertEqual(R.release(text), want)


class TestBothChecksReadThroughIt(unittest.TestCase):
    """Each script uses this module's functions, not a copy, whether run or loaded by path."""

    def test_loaded_by_path(self):
        floors = _load("requirements_floors")
        notices = _load("third_party_notices")
        shared = sys.modules["requirement_rules"]
        for fn in ("parse_requirement", "version_key", "normalise_name", "release"):
            self.assertIs(getattr(floors, fn), getattr(shared, fn), fn)
        for fn in ("parse_requirement", "version_key"):
            self.assertIs(getattr(notices, fn), getattr(shared, fn), fn)
        self.assertIs(notices.norm, shared.normalise_name)

    def test_neither_script_defines_its_own(self):
        for script in ("requirements_floors.py", "third_party_notices.py"):
            text = (SCRIPTS / script).read_text(encoding="utf-8")
            for fn in ("def parse_requirement", "def version_key", "def normalise_name", "def norm("):
                with self.subTest(script=script, fn=fn):
                    self.assertNotIn(fn, text)


if __name__ == "__main__":
    unittest.main()
