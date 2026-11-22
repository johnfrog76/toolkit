"""The requirements-floors check: installed packages against the agent's requirements files.

``Scripts/requirements_floors.py`` is what the Test verb's summary and ``Env``'s
"Python packages" line both ask. These cases hold the comparison over a table, with
the installed set handed in, so nothing here depends on what this machine has; and the
live case runs the check against this tree's two files, which proves it reads them. How a
line, a name and a version are read is ``Scripts/requirement_rules.py``'s, held by the shared
table in ``Tests/test_requirement_rules.py``.

Stdlib only; no agent import, so it never skips.

Run:  python3 -m pytest Tests/test_requirements_floors.py
"""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("requirements_floors", ROOT / "Scripts" / "requirements_floors.py")
F = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(F)

# One row per case the comparison tells apart: (requirement line, installed version or
# None for not installed, the finding's kind or "" for no finding).
ROWS = [
    ("fastapi>=0.162.2", "0.160.0", "below"),
    ("fastapi>=0.162.2", "0.162.2", ""),
    ("fastapi>=0.162.2", "0.170.1", ""),
    ("anthropic>=2.7.0", "1.15.0", "below"),
    ("anthropic>=2.7.0", "2.7", ""),  # 2.7 is 2.7.0
    ("anthropic>=2.7.0", "2.10.0", ""),  # numbers, not strings: 10 > 7
    ("anthropic>=2.7.0", "2.7.0rc1", "below"),  # a pre-release sorts before its release
    ("anthropic>=2.7.0", "2.7.0.post1", ""),
    ("ruff==0.17.5", "0.17.5", ""),
    ("ruff==0.17.5", "0.17.6", "differs"),  # an exact pin differs either way
    ("ruff==0.17.5", "0.17.4", "differs"),
    ("httpx>=0.28.1", None, "missing"),
    ("uvicorn[standard]>=0.54.0", "0.53.9", "below"),  # extras taken off the name
    ("uvicorn[standard]>=0.54.0", "0.54.0", ""),
    ("pytest>=9.2.0  # the suite's floor", "9.1.0", "below"),  # a trailing comment
    ("pytest>=9.2.0  # the suite's floor", "9.2.0", ""),
    ('pydantic>=2.14.3; python_version >= "3.12"', "2.14.2", "below"),  # a marker
    ("Pydantic_Core>=2.0", "2.1.0", ""),  # the name normalised: case and _ against -
    ("zope.interface>=6", "5.9", "below"),  # . is - too
    ("anthropic>=2.7.0", "not-a-version", "unreadable"),
    ("pkg>=1.0,<3", "3.1", "outside"),  # a ceiling this check does not add, still read
    ("pkg~=2.7.1", "2.7.9", ""),
    ("pkg~=2.7.1", "2.8.0", "below"),
]


class TestTable(unittest.TestCase):
    def test_every_row(self):
        for line, have, kind in ROWS:
            with self.subTest(line=line, installed=have):
                req = F.parse_requirement(line)
                self.assertIsNotNone(req)
                installed = {} if have is None else {F.normalise_name(req[0]): have}
                found = F.check([(req[0], req[2], "agent/requirements.txt")], installed)
                self.assertEqual([f["kind"] for f in found], [kind] if kind else [])

    def test_a_finding_names_the_package_the_version_the_floor_and_the_file(self):
        req = F.parse_requirement("anthropic>=2.7.0")
        (f,) = F.check([(req[0], req[2], "agent/requirements.txt")], {"anthropic": "1.15.0"})
        self.assertEqual(f["text"], "anthropic 1.15.0 is below >=2.7.0 in agent/requirements.txt")
        (f,) = F.check([("ruff", [("==", "0.17.5")], "agent/requirements-dev.txt")], {"ruff": "0.17.4"})
        self.assertEqual(f["text"], "ruff 0.17.4 is not the pinned ==0.17.5 in agent/requirements-dev.txt")
        (f,) = F.check([("httpx", [(">=", "0.28.1")], "agent/requirements-dev.txt")], {})
        self.assertEqual(f["text"], "httpx is not installed; agent/requirements-dev.txt wants >=0.28.1")


class TestFiles(unittest.TestCase):
    def test_an_include_is_followed_once_and_a_name_reported_once(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            (base / "runtime.txt").write_text("# runtime\nfastapi>=1.0\n", encoding="utf-8")
            (base / "dev.txt").write_text("-r runtime.txt\npytest>=9\nFastAPI>=2.0\n", encoding="utf-8")
            reqs = F.read_requirements([base / "runtime.txt", base / "dev.txt"], root=base)
            self.assertEqual(
                [(n, lbl) for n, _, lbl in reqs],
                [("fastapi", "runtime.txt"), ("pytest", "dev.txt"), ("FastAPI", "dev.txt")],
            )
            found = F.check(reqs, {"fastapi": "0.1", "pytest": "9.0"})
            self.assertEqual([(f["name"], f["file"]) for f in found], [("fastapi", "runtime.txt")])

    def test_the_live_files_are_the_list(self):
        reqs = F.read_requirements([ROOT / f for f in F.REQUIREMENTS])
        names = {F.normalise_name(n) for n, _, _ in reqs}
        for name in ("fastapi", "uvicorn", "pydantic", "anthropic", "pytest", "httpx", "ruff"):
            self.assertIn(name, names)
        self.assertEqual({lbl for _, _, lbl in reqs}, set(F.REQUIREMENTS))
        # Every requirement carries a version: a floor or the pin.
        self.assertTrue(all(specs for _, specs, _ in reqs))


class TestTheCommand(unittest.TestCase):
    def test_json_for_a_caller_exit_zero_whatever_it_finds(self):
        with tempfile.TemporaryDirectory() as d:
            req = Path(d) / "req.txt"
            req.write_text("surely-not-installed-anywhere>=1.0\n", encoding="utf-8")
            run = subprocess.run(
                [sys.executable, str(ROOT / "Scripts" / "requirements_floors.py"), "--json", str(req)],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(run.returncode, 0, run.stderr)
        answer = json.loads(run.stdout)
        self.assertEqual([f["kind"] for f in answer["findings"]], ["missing"])
        self.assertEqual(answer["fix"], "-m pip install -r agent/requirements-dev.txt")


if __name__ == "__main__":
    unittest.main()
