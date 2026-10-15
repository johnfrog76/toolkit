"""The hub is config, not layout.

The package this agent was carved from resolved the prompt store as the parent
folder of its own toolkit directory. That silently required the tool to live
*inside* the store, and it is the single assumption this suite exists to keep
severed. Three claims:

  (a) promptsRoot from config decides the hub -- not where this code sits;
  (b) a hub with no toolkit inside it still resolves every per-org path;
  (c) no promptsRoot at all degrades to a path that does not exist, and
      nothing raises.

Run directly:  python3 Tests/test_config.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))

from agent.core import config  # noqa: E402


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


class HubResolutionTests(unittest.TestCase):
    """Each test builds a throwaway hub and a throwaway pair of config files,
    then points the config module at them. Nothing touches the real files."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

        # A hub that is deliberately NOT a parent or child of this package,
        # and that contains no toolkit, no .git and no scripts -- just cards.
        self.hub = self.tmp / "somewhere-else" / "my-cards"
        (self.hub / "acme" / "current").mkdir(parents=True)
        (self.hub / "acme" / "archive").mkdir(parents=True)
        (self.hub / "acme" / "current" / "77-a-card.prompt.md").write_text("# Bug 77: A card\n", encoding="utf-8")

        self.default_path = self.tmp / "config.default.json"
        self.local_path = self.tmp / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "acme",
                "promptsRoot": "",
                "spaces": [
                    {
                        "slug": "acme",
                        "name": "Acme",
                        "status": "local",
                        "promptsFolder": "acme",
                        "org": "",
                        "projects": [],
                    },
                    {
                        "slug": "other",
                        "name": "Other",
                        "status": "local",
                        "promptsFolder": "other",
                        "org": "",
                        "projects": [],
                    },
                ],
            },
        )

        # PROMPTS_ROOT is an explicit override only; it must not leak in from
        # the ambient environment while these tests run.
        self._env = mock.patch.dict(os.environ, {}, clear=False)
        self._env.start()
        os.environ.pop("PROMPTS_ROOT", None)

        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._env.stop()
        self._tmp.cleanup()

    # -- (a) config wins over any sibling assumption ------------------------

    def test_prompts_root_comes_from_config(self):
        _write(self.local_path, {"promptsRoot": str(self.hub)})
        self.assertEqual(config.hub_root(), self.hub)

    def test_hub_is_not_the_parent_of_the_package(self):
        _write(self.local_path, {"promptsRoot": str(self.hub)})
        self.assertNotEqual(config.hub_root(), config.REPO_ROOT.parent)
        self.assertNotEqual(config.hub_root(), config.REPO_ROOT)

    def test_local_overrides_default_prompts_root(self):
        _write(
            self.default_path,
            {
                **json.loads(self.default_path.read_text(encoding="utf-8")),
                "promptsRoot": str(self.tmp / "not-this-one"),
            },
        )
        _write(self.local_path, {"promptsRoot": str(self.hub)})
        self.assertEqual(config.hub_root(), self.hub)

    def test_env_var_is_an_explicit_override(self):
        _write(self.local_path, {"promptsRoot": str(self.tmp / "from-config")})
        with mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(self.hub)}):
            self.assertEqual(config.hub_root(), self.hub)

    def test_relative_prompts_root_resolves_against_the_package(self):
        _write(self.local_path, {"promptsRoot": "Tests/fixtures/hub"})
        self.assertEqual(config.hub_root(), config.REPO_ROOT / "Tests/fixtures/hub")

    # -- (b) a hub with no toolkit inside still resolves every path ---------

    def test_per_org_dirs_resolve_in_a_toolkit_free_hub(self):
        _write(self.local_path, {"promptsRoot": str(self.hub)})
        self.assertFalse((self.hub / "Scripts").exists(), "fixture hub must hold no toolkit")
        self.assertFalse((self.hub / ".git").exists(), "fixture hub must not be a repo")
        current, archive = config.resolve_dirs()
        self.assertEqual(current, self.hub / "acme" / "current")
        self.assertEqual(archive, self.hub / "acme" / "archive")
        self.assertTrue(current.exists())
        self.assertTrue(archive.exists())

    def test_org_folder_follows_the_per_org_prompts_folder(self):
        _write(self.local_path, {"promptsRoot": str(self.hub)})
        orgs = {o["slug"]: o for o in config.load_config()["spaces"]}
        self.assertEqual(config.org_folder(orgs["acme"]), self.hub / "acme")
        self.assertEqual(config.org_folder(orgs["other"]), self.hub / "other")

    def test_switching_active_space_moves_the_per_org_path(self):
        _write(self.local_path, {"promptsRoot": str(self.hub), "activeSpace": "other"})
        current, _ = config.resolve_dirs()
        self.assertEqual(current, self.hub / "other" / "current")

    # -- (c) missing promptsRoot degrades, does not raise -------------------

    def test_missing_prompts_root_does_not_raise(self):
        _write(self.local_path, {})
        self.assertFalse(config.hub_configured())
        root = config.hub_root()  # must not raise
        self.assertFalse(root.exists())
        current, archive = config.resolve_dirs()  # must not raise
        self.assertFalse(current.exists())
        self.assertFalse(archive.exists())

    def test_missing_prompts_root_is_reported_in_words(self):
        _write(self.local_path, {})
        detail = config.hub_detail()
        self.assertIn("promptsRoot", detail)
        self.assertIn("not set", detail)

    def test_configured_but_absent_hub_is_reported_as_not_found(self):
        _write(self.local_path, {"promptsRoot": str(self.tmp / "no-such-hub")})
        self.assertTrue(config.hub_configured())
        self.assertFalse(config.hub_root().exists())
        self.assertIn("not found", config.hub_detail())


class EnvironmentStandInTests(unittest.TestCase):
    """``consts.json`` ``env.activeSpace`` and ``env.features`` stand in for two of
    config.local.json's keys, per process, so ``Web -Dev -Fixture`` can start an
    agent against the fixture hub without writing the machine's file. Each
    REPLACES the one key it names, and a malformed features value falls back to
    the files rather than switching everything off."""

    def setUp(self):
        from agent.core.consts import env_active_space, env_features

        self.space_var = env_active_space()
        self.features_var = env_features()
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.default_path = self.tmp / "config.default.json"
        self.local_path = self.tmp / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "acme",
                "features": {"deck": True},
                "spaces": [
                    {"slug": "acme", "name": "Acme", "status": "local", "promptsFolder": "acme"},
                    {"slug": "test", "name": "Example", "status": "local", "promptsFolder": "test"},
                ],
            },
        )
        _write(
            self.local_path,
            {
                "activeSpace": "acme",
                "features": {"growth": True, "communication": True, "organize": True},
                "email": "someone@example.invalid",
            },
        )
        self._env = mock.patch.dict(os.environ, {}, clear=False)
        self._env.start()
        for name in ("PROMPTS_ROOT", self.space_var, self.features_var):
            os.environ.pop(name, None)
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._env.stop()
        self._tmp.cleanup()

    def test_the_names_are_the_contracts(self):
        self.assertEqual(self.space_var, "P20_ACTIVE_SPACE")
        self.assertEqual(self.features_var, "P20_FEATURES")

    def test_unset_the_files_decide(self):
        cfg = config.load_config()
        self.assertEqual(cfg["activeSpace"], "acme")
        self.assertTrue(cfg["features"]["growth"])

    def test_the_space_override_wins_over_config_local(self):
        os.environ[self.space_var] = "test"
        cfg = config.load_config()
        self.assertEqual(cfg["activeSpace"], "test")
        self.assertEqual(cfg["promptsFolder"], "test")

    def test_an_unknown_space_falls_back_the_way_an_unknown_file_value_does(self):
        os.environ[self.space_var] = "no-such-space"
        self.assertEqual(config.load_config()["activeSpace"], "acme")

    def test_an_empty_object_is_no_flag_set_at_all(self):
        os.environ[self.features_var] = "{}"
        feats = config.load_config()["features"]
        self.assertNotIn("growth", feats)
        self.assertNotIn("communication", feats)
        self.assertNotIn("organize", feats)
        # It replaces the LOCAL block; the shipped defaults still stand under it.
        self.assertTrue(feats["deck"])

    def test_the_features_override_replaces_rather_than_patches(self):
        os.environ[self.features_var] = '{"growth": true, "communication": true}'
        feats = config.load_config()["features"]
        self.assertTrue(feats["growth"])
        self.assertTrue(feats["communication"])
        self.assertNotIn("organize", feats, "the file's organize must not leak through a replacement")

    def test_a_malformed_features_value_is_ignored_not_obeyed(self):
        for bad in ("not json", "[1, 2]", '"growth"'):
            with self.subTest(value=bad):
                os.environ[self.features_var] = bad
                self.assertTrue(config.load_config()["features"]["growth"])

    def test_the_rest_of_config_local_still_applies(self):
        os.environ[self.space_var] = "test"
        os.environ[self.features_var] = "{}"
        self.assertEqual(config.load_config()["email"], "someone@example.invalid")

    def test_nothing_is_written(self):
        before = self.local_path.read_bytes()
        os.environ[self.space_var] = "test"
        os.environ[self.features_var] = "{}"
        config.load_config()
        self.assertEqual(self.local_path.read_bytes(), before)


class FixtureHubTests(unittest.TestCase):
    """Tests/fixtures/hub is a hub with no toolkit in it and no .git. It is
    what the live smoke run points promptsRoot at, so it is worth a check that
    it stays a two-card store deriving one Active and one Code Review."""

    HUB = PKG_ROOT / "Tests" / "fixtures" / "hub"

    def test_the_fixture_hub_holds_no_toolkit_and_no_repo(self):
        self.assertTrue(self.HUB.exists())
        self.assertFalse((self.HUB / "Scripts").exists())
        self.assertFalse((self.HUB / ".git").exists())

    def test_the_two_cards_derive_one_active_and_one_code_review(self):
        from agent.core.parsers import _parse_status_metadata

        current = self.HUB / "test" / "current"
        states = sorted(
            _parse_status_metadata(f.read_text(encoding="utf-8"))["status"] for f in current.glob("*.prompt.md")
        )
        self.assertEqual(states, ["Active", "Code Review"])


class MergeSemanticsTests(unittest.TestCase):
    """The Python merge must behave as Merge-SpacePatch does: nested maps merge
    key-by-key, scalars and lists replace wholesale."""

    def test_nested_map_merges_key_by_key(self):
        base = {"features": {"sprintAwareness": True, "growth": False}}
        out = config._deep_merge(base, {"features": {"growth": True}})
        self.assertEqual(out["features"], {"sprintAwareness": True, "growth": True})

    def test_scalar_replaces(self):
        self.assertEqual(config._deep_merge({"status": "active"}, {"status": "local"})["status"], "local")

    def test_list_replaces_wholesale(self):
        out = config._deep_merge({"projects": [{"name": "A"}, {"name": "B"}]}, {"projects": [{"name": "C"}]})
        self.assertEqual(out["projects"], [{"name": "C"}])


class OrgsPatchShapeTests(unittest.TestCase):
    """``orgs`` has two shapes on purpose and only one of them is a patch.

    ``config.default.json`` holds an ARRAY -- the list of orgs, each carrying
    its own slug. ``config.local.json`` holds an OBJECT KEYED BY SLUG, because
    it patches one of those entries. A reader who mirrors the shipped file
    writes the array form, which matches nothing -- and did so in silence,
    on the key that decides which org everything scopes to. Mirrors
    Clause 9 of the PowerShell Portability suite.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.default_path = self.tmp / "config.default.json"
        self.local_path = self.tmp / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "acme",
                "promptsRoot": "",
                "spaces": [
                    {
                        "slug": "acme",
                        "name": "Acme",
                        "status": "active",
                        "promptsFolder": "acme",
                        "org": "",
                        "projects": [],
                    },
                ],
            },
        )
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def _load(self):
        with mock.patch.object(config.log_writer, "write_log") as logged:
            cfg = config.load_config()
        return cfg, [c.args for c in logged.call_args_list]

    def test_object_keyed_by_slug_is_applied(self):
        _write(self.local_path, {"spaces": {"acme": {"status": "local"}}})
        cfg, warnings = self._load()
        self.assertEqual(cfg["spaces"][0]["status"], "local")
        self.assertEqual(warnings, [])

    def test_array_form_applies_nothing(self):
        _write(self.local_path, {"spaces": [{"slug": "acme", "status": "local"}]})
        cfg, _ = self._load()
        self.assertEqual(cfg["spaces"][0]["status"], "active")

    def test_array_form_warns(self):
        _write(self.local_path, {"spaces": [{"slug": "acme", "status": "local"}]})
        _, warnings = self._load()
        self.assertEqual(len(warnings), 1, warnings)
        level, _source, detail = warnings[0]
        self.assertEqual(level, "WARN")
        self.assertIn("'spaces' is an array", detail)

    def test_the_warning_names_the_shape_it_wanted(self):
        _write(self.local_path, {"spaces": [{"slug": "acme"}]})
        _, warnings = self._load()
        self.assertIn("keyed by slug", warnings[0][2])

    def test_no_orgs_key_is_not_a_warning(self):
        _write(self.local_path, {"activeSpace": "acme"})
        _, warnings = self._load()
        self.assertEqual(warnings, [])


class CorsOriginsTests(unittest.TestCase):
    def test_defaults_are_unchanged_when_config_is_silent(self):
        self.assertEqual(config.DEFAULT_CORS_ORIGINS, ["http://localhost:5174", "http://localhost:5173"])

    def test_committed_config_serves_the_same_two_ports(self):
        self.assertEqual(sorted(config.cors_origins()), sorted(config.DEFAULT_CORS_ORIGINS))


def _run() -> int:
    loader = unittest.defaultTestLoader
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2, stream=sys.stdout).run(suite)
    total = result.testsRun
    passed = total - len(result.failures) - len(result.errors)
    print(f"\n  Results: {passed}/{total} passed")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(_run())
