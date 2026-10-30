"""A Space's checkout on this machine (spaceCheckouts.<slug>.path, #146).

The agent's half: agent/core/checkout.py reads the configured path and checks it
names a clone of the Space's repository -- the rule the CLI's resolver applies to
the same path first (Scripts/Resolve-SpaceCheckout.ps1). The path and origin rules
are held to the CLI's by Tests/fixtures/space-checkout/table.json, which
tkTestToolkit -Design asserts too. GET /api/design carries the answer for the
Design tab, read fresh on every request; the setting comes from config.local.json
only. docs/CONFIGURATION.md, "A Space's checkout on this machine".

Run:  python3 -m pytest Tests/test_space_checkout.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado import design
    from agent.app import app
    from agent.core import checkout, config
except Exception as e:  # pragma: no cover
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

TABLE = json.loads((PKG_ROOT / "Tests/fixtures/space-checkout/table.json").read_text(encoding="utf-8"))


def _git(path: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True)


class TheSharedTable(unittest.TestCase):
    def test_a_path_as_written(self):
        for row in TABLE["paths"]:
            with self.subTest(written=row["written"]):
                if "home" in row:
                    want = str(Path.home() / row["home"]) if row["home"] else str(Path.home())
                else:
                    want = row["expect"]
                self.assertEqual(checkout.checkout_path(row["written"]), want)

    def test_the_repository_a_remote_names(self):
        for row in TABLE["origins"]:
            with self.subTest(url=row["url"]):
                self.assertEqual(checkout.origin_repo(row["url"]), row["repo"])

    def test_a_match_ignores_case(self):
        for row in TABLE["matches"]:
            with self.subTest(row=row):
                same = bool(row["origin"]) and row["origin"].lower() == row["space"].lower()
                self.assertEqual(same, row["match"])


class TheConfiguredCheckout(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name).resolve()
        self.clone = self.base / "clone"
        (self.clone / "design").mkdir(parents=True)
        _git(self.base, "init", "-q", str(self.clone))
        _git(self.clone, "remote", "add", "origin", "git@github.com:o/r.git")

    def tearDown(self):
        self._tmp.cleanup()

    def ask(self, written, repo="o/r"):
        cfg = {"spaceCheckouts": {"prod": {"path": written}} if written is not None else {}}
        return checkout.space_checkout("prod", repo, cfg)

    def test_unset_is_not_ready_and_says_nothing(self):
        got = self.ask(None)
        self.assertEqual(
            (got.space, got.key, got.path, got.ready, got.reason), ("prod", "spaceCheckouts.prod.path", "", False, "")
        )

    def test_a_clone_of_the_repo_is_ready_from_any_folder_inside_it(self):
        for written in (str(self.clone), str(self.clone / "design")):
            got = self.ask(written, repo="O/R")
            self.assertTrue(got.ready, got.reason)
            self.assertEqual(Path(got.root).resolve(), self.clone)

    def test_every_reason_names_the_setting(self):
        other = self.base / "other"
        other.mkdir()
        cases = {
            "relative/path": "neither an absolute path nor under ~",
            str(self.base / "missing"): "not a folder on this machine",
            str(other): "not inside a git repository",
        }
        for written, words in cases.items():
            got = self.ask(written)
            self.assertFalse(got.ready)
            self.assertIn("spaceCheckouts.prod.path", got.reason)
            self.assertIn(words, got.reason)
        got = self.ask(str(self.clone), repo="o/other")
        self.assertFalse(got.ready)
        self.assertIn("is a clone of o/r, not o/other", got.reason)
        _git(self.clone, "remote", "set-url", "origin", "https://gitlab.com/o/r.git")
        self.assertIn("its origin is not on GitHub", self.ask(str(self.clone)).reason)


class TheConfigLayer(unittest.TestCase):
    """config.local.json's spaceCheckouts reaches load_config; the shipped file never does."""

    def test_only_this_machine_names_a_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            local = Path(tmp) / "config.local.json"
            local.write_text(json.dumps({"spaceCheckouts": {"prod": {"path": "/srv/r"}}}), encoding="utf-8")
            env = {k: v for k, v in os.environ.items() if k != "PROMPTS_ROOT"}
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(config, "LOCAL_CONFIG_PATH", local):
                cfg = config.load_config()
            self.assertEqual(cfg["spaceCheckouts"], {"prod": {"path": "/srv/r"}})
            self.assertEqual(checkout.configured_checkout("prod", cfg), "/srv/r")
        default = json.loads((PKG_ROOT / "config.default.json").read_text(encoding="utf-8"))
        self.assertNotIn("spaceCheckouts", default, "a path is this machine's; the shipped config never names one")


class TheDesignRoute(unittest.TestCase):
    """GET /api/design carries the active Space's checkout, fresh on every request."""

    def setUp(self):
        design.clear_cache()
        self.client = TestClient(app)

    def test_the_listing_carries_the_checkout_of_the_space_you_are_in(self):
        listed = design.DesignListResponse(repo="o/r")
        answers = [
            checkout.SpaceCheckout(key="spaceCheckouts.prod.path"),
            checkout.SpaceCheckout(key="spaceCheckouts.prod.path", path="/c", root="/c", ready=True),
        ]
        calls = []

        def fake(slug, repo, cfg=None):
            calls.append((slug, repo))
            return answers[len(calls) - 1]

        with (
            mock.patch.object(design, "repo_gate", return_value="o/r"),
            mock.patch.object(design, "list_design", return_value=listed),
            mock.patch.object(design, "load_config", return_value={"activeSpace": "prod"}),
            mock.patch.object(
                design, "resolve_dirs", return_value=(Path("/nowhere/current"), Path("/nowhere/archive"))
            ),
            mock.patch.object(design, "space_checkout", side_effect=fake),
        ):
            first = self.client.get("/api/design").json()
            second = self.client.get("/api/design").json()
        self.assertEqual(calls, [("prod", "o/r"), ("prod", "o/r")])
        self.assertFalse(first["checkout"]["ready"])
        self.assertEqual(first["checkout"]["key"], "spaceCheckouts.prod.path")
        self.assertTrue(second["checkout"]["ready"])


if __name__ == "__main__":
    unittest.main()
