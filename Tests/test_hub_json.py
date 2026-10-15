"""The hub declares its own orgs.

``<promptsRoot>/hub.json`` is optional and is the engineer's data, not the
tool's: a private ADO org must never be written into the committed
``config.default.json``, and the hub is where that engineer's work already
lives ("data separate from software").

The rules this suite pins, and they are the same rules ``utilities.psm1``
implements:

  (a) resolution order -- shipped orgs, then hub orgs merged by slug, then the
      per-machine ``config.local.json`` patches, last;
  (b) a hub declares orgs, folder names and ``storeSync`` and nothing else:
      machine-scoped keys and engineer feature flags are ignored **with a
      warning**, while an org-scoped flag (``SPACE_FEATURES``) is honoured exactly
      as on a shipped org;
  (c) absent changes nothing, malformed is a readable warning naming the path,
      and an unusable org entry is skipped rather than half-applied.

Run directly:  python3 Tests/test_hub_json.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))

from agent.core import config  # noqa: E402

PARITY_FIXTURE = PKG_ROOT / "Tests" / "fixtures" / "hub-parity"


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


class HubManifestCase(unittest.TestCase):
    """A throwaway hub and a throwaway pair of config files, per test."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.hub = self.tmp / "hub"
        (self.hub / "test" / "current").mkdir(parents=True)

        self.default_path = self.tmp / "config.default.json"
        self.local_path = self.tmp / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "test",
                "promptsRoot": "",
                "storeSync": "none",
                "spaces": [
                    {
                        "slug": "test",
                        "name": "Example",
                        "status": "active",
                        "orgType": "portfolio",
                        "org": "https://dev.azure.com/YOUR-ADO-ORG",
                        "tenant": "",
                        "promptsFolder": "test",
                        "projects": [{"name": "YourProject", "repo": "your-repo"}],
                    },
                ],
            },
        )
        _write(self.local_path, {"promptsRoot": str(self.hub)})

        # PROMPTS_ROOT is an explicit override only; it must not leak in from
        # whatever shell the suite is running in and shadow the config above.
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

    # -- helpers ------------------------------------------------------------

    def write_hub(self, data) -> Path:
        path = self.hub / config.HUB_MANIFEST_NAME
        if isinstance(data, str):
            path.write_text(data, encoding="utf-8")
        else:
            _write(path, data)
        return path

    def write_local(self, data: dict) -> None:
        _write(self.local_path, {"promptsRoot": str(self.hub), **data})

    def load(self):
        """Load, returning (cfg, [warning detail, ...])."""
        with mock.patch.object(config.log_writer, "write_log") as logged:
            cfg = config.load_config()
        return cfg, [c.args[2] for c in logged.call_args_list]

    def slugs(self, cfg) -> list:
        return [o["slug"] for o in cfg["spaces"]]

    def org(self, cfg, slug) -> dict:
        return next(o for o in cfg["spaces"] if o["slug"] == slug)


class AbsentManifestTests(HubManifestCase):
    """A hub with no hub.json is the ordinary case and must cost nothing."""

    def test_no_manifest_leaves_the_shipped_orgs_alone(self):
        cfg, warnings = self.load()
        self.assertEqual(self.slugs(cfg), ["test"])
        self.assertEqual(warnings, [])

    def test_no_manifest_is_reported_as_not_read(self):
        cfg, _ = self.load()
        self.assertFalse(cfg["hub"]["manifest"])
        self.assertEqual(cfg["hub"]["spaces"], 0)

    def test_no_prompts_root_at_all_does_not_look_for_one(self):
        _write(self.local_path, {})
        cfg, warnings = self.load()
        self.assertFalse(cfg["hub"]["manifest"])
        self.assertEqual(cfg["hub"]["path"], "")
        self.assertEqual(warnings, [])

    def test_the_detail_sentence_says_there_is_none(self):
        self.assertIn("no hub.json", config.hub_manifest_detail())


class MalformedManifestTests(HubManifestCase):
    """Malformed is a readable warning naming the path, never a crash."""

    def test_broken_json_does_not_raise(self):
        self.write_hub("{ this is not json")
        cfg, _ = self.load()  # must not raise
        self.assertEqual(self.slugs(cfg), ["test"])

    def test_broken_json_warns_with_the_path(self):
        path = self.write_hub("{ this is not json")
        _, warnings = self.load()
        self.assertTrue(warnings, "a malformed manifest must warn")
        self.assertIn(str(path), warnings[0])

    def test_a_json_array_at_the_top_level_is_refused(self):
        self.write_hub("[]")
        cfg, warnings = self.load()
        self.assertFalse(cfg["hub"]["manifest"])
        self.assertIn("JSON object", warnings[0])

    def test_orgs_as_an_object_is_refused_by_shape(self):
        self.write_hub({"hub": 1, "spaces": {"acme": {"promptsFolder": "acme"}}})
        cfg, warnings = self.load()
        self.assertEqual(self.slugs(cfg), ["test"])
        self.assertIn("must be an array", warnings[0])


class HubOrgMergeTests(HubManifestCase):
    """Shipped orgs, then hub orgs by slug, then the machine's patches."""

    def test_a_new_slug_is_appended(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {
                        "slug": "acme",
                        "name": "Acme",
                        "status": "local",
                        "orgType": "engagement",
                        "promptsFolder": "acme",
                    },
                ],
            }
        )
        cfg, warnings = self.load()
        self.assertEqual(self.slugs(cfg), ["test", "acme"])
        self.assertEqual(self.org(cfg, "acme")["name"], "Acme")
        self.assertEqual(warnings, [])

    def test_a_new_slug_can_be_the_active_space(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "name": "Acme", "status": "local", "promptsFolder": "acme"},
                ],
            }
        )
        self.write_local({"activeSpace": "acme"})
        cfg, _ = self.load()
        self.assertEqual(cfg["activeSpace"], "acme")
        self.assertEqual(cfg["promptsFolder"], "acme")

    def test_a_shipped_slug_is_deep_merged_not_replaced(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {
                        "slug": "test",
                        "name": "Contoso",
                        "promptsFolder": "test",
                        "org": "https://dev.azure.com/contoso",
                    },
                ],
            }
        )
        cfg, _ = self.load()
        merged = self.org(cfg, "test")
        self.assertEqual(self.slugs(cfg), ["test"], "merging must not duplicate the slug")
        self.assertEqual(merged["name"], "Contoso")  # the hub's value
        self.assertEqual(merged["org"], "https://dev.azure.com/contoso")
        self.assertEqual(merged["orgType"], "portfolio")  # the shipped sibling survives
        self.assertEqual(merged["projects"], [{"name": "YourProject", "repo": "your-repo"}])

    def test_the_patch_config_writes_for_a_shipped_org_keeps_its_name_and_status(self):
        # `Config -Set orgs.test.org=<url>` writes exactly this -- slug,
        # promptsFolder, the field -- and the Example org must stay Example and
        # active, not become a local org called "test".
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "test", "promptsFolder": "test", "org": "https://dev.azure.com/SomeOrg"},
                ],
            }
        )
        cfg, _ = self.load()
        merged = self.org(cfg, "test")
        self.assertEqual(merged["name"], "Example")
        self.assertEqual(merged["status"], "active")
        self.assertEqual(merged["org"], "https://dev.azure.com/SomeOrg")

    def test_a_local_patch_wins_over_the_hub(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "test", "name": "Contoso", "status": "active", "promptsFolder": "test"},
                ],
            }
        )
        self.write_local({"spaces": {"test": {"status": "local"}}})
        cfg, _ = self.load()
        merged = self.org(cfg, "test")
        self.assertEqual(merged["status"], "local")  # the machine's last word
        self.assertEqual(merged["name"], "Contoso")  # everything it did not name is the hub's

    def test_a_local_patch_reaches_an_org_the_hub_invented(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "name": "Acme", "status": "active", "promptsFolder": "acme"},
                ],
            }
        )
        self.write_local({"spaces": {"acme": {"status": "archive"}}})
        cfg, _ = self.load()
        self.assertEqual(self.org(cfg, "acme")["status"], "archive")

    def test_an_unknown_status_on_a_hub_space_still_fails_closed(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "status": "whatever", "promptsFolder": "acme"},
                ],
            }
        )
        cfg, warnings = self.load()
        self.assertEqual(self.org(cfg, "acme")["status"], "local")
        self.assertTrue(any("unknown status" in w for w in warnings))

    def test_the_count_of_declared_orgs_is_reported(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "promptsFolder": "acme"},
                    {"slug": "beta", "promptsFolder": "beta"},
                ],
            }
        )
        cfg, _ = self.load()
        self.assertTrue(cfg["hub"]["manifest"])
        self.assertEqual(cfg["hub"]["spaces"], 2)
        self.assertIn("2 Spaces declared", config.hub_manifest_detail())


class UnusableOrgEntryTests(HubManifestCase):
    """An org that cannot be keyed or located is skipped, with a warning."""

    def test_an_org_with_no_slug_is_skipped(self):
        self.write_hub({"hub": 1, "spaces": [{"name": "Nameless", "promptsFolder": "x"}]})
        cfg, warnings = self.load()
        self.assertEqual(self.slugs(cfg), ["test"])
        self.assertTrue(any("no 'slug'" in w for w in warnings), warnings)

    def test_an_org_with_no_prompts_folder_is_skipped(self):
        self.write_hub({"hub": 1, "spaces": [{"slug": "acme", "name": "Acme"}]})
        cfg, warnings = self.load()
        self.assertEqual(self.slugs(cfg), ["test"])
        self.assertTrue(any("promptsFolder" in w and "acme" in w for w in warnings), warnings)

    def test_a_usable_sibling_still_lands(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme"},
                    {"slug": "beta", "promptsFolder": "beta"},
                ],
            }
        )
        cfg, _ = self.load()
        self.assertEqual(self.slugs(cfg), ["test", "beta"])


class IgnoredKeyTests(HubManifestCase):
    """hub.json carries orgs and folders. Everything else is the machine's."""

    MACHINE_KEYS = {
        "activeSpace": "acme",
        "promptsRoot": "/somewhere/else",
        "email": "someone@example.com",
        "branchUser": "someone",
        "wsRoot": "/ws",
        "web": {"agentPort": 9999},
        "commands": {"Status": {"category": "prompt"}},
        "features": {"growth": True},
    }

    def test_each_machine_key_is_ignored_and_warns(self):
        for key, value in self.MACHINE_KEYS.items():
            with self.subTest(key=key):
                self.write_hub({"hub": 1, key: value, "spaces": []})
                cfg, warnings = self.load()
                self.assertTrue(any(f"'{key}'" in w for w in warnings), f"{key} must warn; got {warnings}")
                self.assertEqual(cfg["promptsRoot"], str(self.hub))
                self.assertEqual(cfg["activeSpace"], "test")
                self.assertEqual(cfg["features"], {})

    def test_an_underscore_comment_key_is_not_a_warning(self):
        self.write_hub({"hub": 1, "_comment": "mine, not the tool's", "spaces": []})
        _, warnings = self.load()
        self.assertEqual(warnings, [])

    def test_the_version_marker_is_not_a_warning(self):
        self.write_hub({"hub": 1, "spaces": [], "folders": {}})
        _, warnings = self.load()
        self.assertEqual(warnings, [])


class HubOrgFeatureTests(HubManifestCase):
    """An org-scoped flag is honoured; an engineer flag is somebody's flag in
    the wrong file, and is ignored with a warning."""

    def test_sprint_awareness_on_a_hub_space_is_honoured(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "status": "local", "promptsFolder": "acme", "features": {"sprintAwareness": True}},
                ],
            }
        )
        self.write_local({"activeSpace": "acme"})
        cfg, warnings = self.load()
        self.assertTrue(cfg["features"]["sprintAwareness"])
        self.assertEqual(warnings, [])

    def test_sprint_awareness_on_a_merged_shipped_org_is_honoured(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "test", "promptsFolder": "test", "features": {"sprintAwareness": True}},
                ],
            }
        )
        cfg, _ = self.load()
        self.assertTrue(cfg["features"]["sprintAwareness"])

    def test_an_engineer_flag_on_a_hub_space_is_ignored(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "status": "local", "promptsFolder": "acme", "features": {"growth": True}},
                ],
            }
        )
        self.write_local({"activeSpace": "acme"})
        cfg, warnings = self.load()
        self.assertNotIn("growth", cfg["features"])
        self.assertNotIn("features", self.org(cfg, "acme"))
        self.assertTrue(any("features.growth" in w for w in warnings), warnings)

    def test_the_warning_says_where_the_flag_belongs(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "acme", "promptsFolder": "acme", "features": {"communication": True}},
                ],
            }
        )
        _, warnings = self.load()
        self.assertTrue(any("config.local.json" in w for w in warnings), warnings)

    def test_an_engineer_flag_does_not_clobber_a_merged_org(self):
        # features.growth is dropped before the merge, so a shipped org that
        # carried sprintAwareness keeps it rather than losing the whole map.
        _write(
            self.default_path,
            {
                "activeSpace": "test",
                "promptsRoot": "",
                "spaces": [
                    {"slug": "test", "status": "local", "promptsFolder": "test", "features": {"sprintAwareness": True}}
                ],
            },
        )
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "test", "promptsFolder": "test", "features": {"growth": True}},
                ],
            }
        )
        cfg, _ = self.load()
        self.assertTrue(cfg["features"]["sprintAwareness"])


class HubFolderTests(HubManifestCase):
    """The hub-root sibling names: defaults unless the hub renames them."""

    def test_the_defaults_are_the_names_the_modules_have_always_read(self):
        self.assertEqual(
            config.DEFAULT_HUB_FOLDERS,
            {
                "growth": "growth",
                "manager": "manager",
                "reviews": "reviews",
                "resume": "resume",
                "agentic": "agentic",
                # The Organize add-on's -- named for the data, not the module.
                "reminders": "reminders",
                # The Studio's seed drawer.
                "design": "design",
                # The hub's specs (design lifecycle L2).
                "spec": "spec",
            },
        )

    def test_no_manifest_means_the_defaults(self):
        cfg, _ = self.load()
        self.assertEqual(cfg["hubFolders"], config.DEFAULT_HUB_FOLDERS)
        self.assertEqual(config.hub_folder("growth"), self.hub / "growth")
        self.assertEqual(config.hub_folder("manager"), self.hub / "manager")
        self.assertEqual(config.hub_folder("reviews"), self.hub / "reviews")
        self.assertEqual(config.hub_folder("resume"), self.hub / "resume")

    def test_a_declared_name_is_followed(self):
        self.write_hub({"hub": 1, "folders": {"growth": "development", "manager": "1on1s"}})
        cfg, warnings = self.load()
        self.assertEqual(cfg["hubFolders"]["growth"], "development")
        self.assertEqual(config.hub_folder("growth"), self.hub / "development")
        self.assertEqual(config.hub_folder("manager"), self.hub / "1on1s")
        self.assertEqual(warnings, [])

    def test_an_absent_key_keeps_its_default(self):
        self.write_hub({"hub": 1, "folders": {"growth": "development"}})
        cfg, _ = self.load()
        self.assertEqual(cfg["hubFolders"]["reviews"], "reviews")
        self.assertEqual(config.hub_folder("resume"), self.hub / "resume")

    def test_a_folder_key_nothing_reads_warns(self):
        self.write_hub({"hub": 1, "folders": {"growht": "development"}})
        cfg, warnings = self.load()
        self.assertEqual(cfg["hubFolders"], config.DEFAULT_HUB_FOLDERS)
        self.assertTrue(any("folders.growht" in w for w in warnings), warnings)

    def test_a_folder_value_that_is_not_a_name_is_ignored(self):
        self.write_hub({"hub": 1, "folders": {"growth": ""}})
        cfg, warnings = self.load()
        self.assertEqual(cfg["hubFolders"]["growth"], "growth")
        self.assertTrue(any("folders.growth" in w for w in warnings), warnings)


class HubStoreSyncTests(HubManifestCase):
    """Whether the store is a git repo is a fact about the HUB, so the hub may
    declare it -- and then two machines agree without either setting it."""

    def test_no_manifest_leaves_the_configured_value(self):
        cfg, _ = self.load()
        self.assertEqual(cfg["storeSync"], "none")

    def test_the_hub_can_turn_it_on_for_every_machine(self):
        self.write_hub({"hub": 1, "storeSync": "git"})
        cfg, warnings = self.load()
        self.assertEqual(cfg["storeSync"], "git")
        self.assertEqual(warnings, [], "storeSync is a hub declaration, not a machine key")

    def test_a_machine_can_override_the_hub(self):
        # The machine that must never push says so here, and nothing about the
        # hub has to change for the other one.
        self.write_hub({"hub": 1, "storeSync": "git"})
        self.write_local({"storeSync": "none"})
        cfg, _ = self.load()
        self.assertEqual(cfg["storeSync"], "none")

    def test_a_machine_that_says_nothing_takes_the_hub_value(self):
        self.write_hub({"hub": 1, "storeSync": "git"})
        self.write_local({"activeSpace": "test"})
        cfg, _ = self.load()
        self.assertEqual(cfg["storeSync"], "git")

    def test_a_value_that_is_not_one_of_the_two_warns_and_falls_back(self):
        self.write_hub({"hub": 1, "storeSync": "yes"})
        cfg, warnings = self.load()
        self.assertEqual(cfg["storeSync"], "none")
        self.assertTrue(any("storeSync" in w for w in warnings), warnings)

    def test_a_value_that_is_not_a_string_warns_and_falls_back(self):
        self.write_hub({"hub": 1, "storeSync": True})
        cfg, warnings = self.load()
        self.assertEqual(cfg["storeSync"], "none")
        self.assertTrue(any("storeSync" in w for w in warnings), warnings)

    def test_the_two_values_are_the_ones_the_cli_knows(self):
        self.assertEqual(config.STORE_SYNC_VALUES, ("git", "none"))


RENAMED_TABLE = PKG_ROOT / "Tests" / "fixtures" / "space-renamed" / "table.json"


class RenamedSpaceTests(HubManifestCase):
    """#116: the shipped Azure demo was ``test`` and is ``azure-demo``.

    A machine whose hub.json or config.local.json still names ``test`` keeps
    its Space -- the old slug is accepted and read as the new one. The rule is
    one table, Tests/fixtures/space-renamed/table.json, which
    Tests/Test-HubJson.ps1 asserts against the PowerShell half.
    """

    def setUp(self):
        super().setUp()
        # The SHIPPED config, not the case's own: the rename is about what ships.
        shutil.copy(PKG_ROOT / "config.default.json", self.default_path)
        (self.hub / "azure-demo" / "current").mkdir(parents=True)

    def table(self) -> dict:
        return json.loads(RENAMED_TABLE.read_text(encoding="utf-8"))

    def test_the_contract_names_the_rename(self):
        self.assertEqual(config.RENAMED_SPACES, {"test": "azure-demo"})

    def test_every_slug_row(self):
        for row in self.table()["slugs"]:
            with self.subTest(why=row["why"]):
                self.assertEqual(config.renamed_slug(row["slug"], row["slugs"]), row["expect"])

    def test_every_entry_row(self):
        for row in self.table()["entries"]:
            with self.subTest(why=row["why"]):
                entry = dict(row["entry"])
                out = config.rename_legacy_hub_spaces([entry], row["shipped"])
                self.assertEqual(out[0]["slug"], row["expect"])
                self.assertEqual(out[0]["promptsFolder"], row["entry"]["promptsFolder"])

    def test_a_machine_that_connected_the_old_example_keeps_it(self):
        # What `Config -Set spaces.test.org=... ` / `Connect test -Address` wrote
        # before the rename, and an activeSpace that still says test.
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {
                        "slug": "test",
                        "promptsFolder": "test",
                        "org": "https://dev.azure.com/SomeOrg",
                        "status": "active",
                    },
                ],
            }
        )
        self.write_local({"activeSpace": "test"})
        cfg, _ = self.load()
        self.assertNotIn("test", self.slugs(cfg))
        self.assertEqual(cfg["activeSpace"], "azure-demo")
        merged = self.org(cfg, "azure-demo")
        self.assertEqual(merged["name"], "Azure demo")
        self.assertEqual(merged["org"], "https://dev.azure.com/SomeOrg")
        self.assertEqual(merged["status"], "active")
        self.assertEqual(merged["promptsFolder"], "test")  # where its cards are

    def test_a_local_patch_under_the_old_slug_reaches_the_new_space(self):
        self.write_local({"spaces": {"test": {"status": "archive"}}})
        cfg, _ = self.load()
        self.assertEqual(self.org(cfg, "azure-demo")["status"], "archive")

    def test_the_new_slug_has_the_last_word_over_the_old(self):
        self.write_local({"spaces": {"test": {"status": "archive"}, "azure-demo": {"status": "active"}}})
        cfg, _ = self.load()
        self.assertEqual(self.org(cfg, "azure-demo")["status"], "active")

    def test_a_space_that_names_itself_test_is_its_own(self):
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "test", "name": "Mine", "status": "local", "promptsFolder": "test"},
                ],
            }
        )
        self.write_local({"activeSpace": "test"})
        cfg, _ = self.load()
        self.assertEqual(self.slugs(cfg), ["azure-demo", "test"])
        self.assertEqual(cfg["activeSpace"], "test")
        self.assertEqual(self.org(cfg, "azure-demo")["promptsFolder"], "azure-demo")


class FixtureHubManifestTests(unittest.TestCase):
    """Tests/fixtures/hub is what the smoke run points promptsRoot at, so the
    committed manifest there has to be the no-op it claims to be."""

    HUB = PKG_ROOT / "Tests" / "fixtures" / "hub"

    def test_the_fixture_hub_declares_the_test_org_and_the_default_folders(self):
        hub = config.read_hub_manifest(self.HUB)
        self.assertTrue(hub["manifest"])
        self.assertEqual([o["slug"] for o in hub["spaces"]], ["test"])
        self.assertEqual({**config.DEFAULT_HUB_FOLDERS, **hub["folders"]}, config.DEFAULT_HUB_FOLDERS)

    def test_reading_the_fixture_manifest_warns_about_nothing(self):
        with mock.patch.object(config.log_writer, "write_log") as logged:
            config.read_hub_manifest(self.HUB)
        self.assertEqual([c.args for c in logged.call_args_list], [])

    def test_it_declares_status_local_so_it_cannot_change_a_tier(self):
        # Deliberate: two suites here declare the same slug as status "local",
        # and a hub-declared "active" would flip them into a live `az` probe.
        # It once said nothing and took "local" from the shipped Space it
        # patched; the shipped one is azure-demo now, so it says it itself.
        hub = config.read_hub_manifest(self.HUB)
        self.assertEqual(hub["spaces"][0]["status"], "local")

    def test_its_test_space_is_its_own_beside_the_shipped_azure_demo(self):
        # The entry names itself, so it is NOT read as a patch on the
        # renamed shipped Space -- the fixture keeps 'test', the shipped
        # azure-demo stands beside it, and the fixture's Space answers as before.
        env = mock.patch.dict(
            os.environ, {"PROMPTS_ROOT": str(self.HUB), config.env_active_space(): "test"}, clear=False
        )
        with env, mock.patch.object(config, "LOCAL_CONFIG_PATH", self.HUB / "no-such-config.local.json"):
            cfg = config.load_config()
        self.assertEqual([o["slug"] for o in cfg["spaces"]], ["azure-demo", "test"])
        self.assertEqual(cfg["activeSpace"], "test")
        self.assertEqual(cfg["promptsFolder"], "test")
        self.assertEqual(cfg["status"], "local")


class ParityTests(unittest.TestCase):
    """Both loaders answer the same question and must not disagree about it.

    ``Tests/fixtures/hub-parity`` is one config.default.json, one hub.json and
    one config.local.json, plus the resolved org list both halves must produce.
    The PowerShell suite (``Tests/Test-HubJson.ps1``) asserts against the same
    expectation file, so a drift in either loader turns one of the two red --
    and when pwsh is on the machine, this case runs the real module and
    compares the two answers directly.
    """

    @classmethod
    def _expected(cls) -> list:
        return json.loads((PARITY_FIXTURE / "expected-orgs.json").read_text(encoding="utf-8"))

    @classmethod
    def _expected_scalars(cls) -> dict:
        """The hub-wide values, kept beside the org list rather than inside it:
        ``storeSync`` belongs to the hub, not to any one org."""
        return json.loads((PARITY_FIXTURE / "expected-scalars.json").read_text(encoding="utf-8"))

    def _resolved(self, cfg: dict) -> list:
        """The shape the two halves compare: slug, status, org, promptsFolder
        and sprintAwareness, in resolution order."""
        out = []
        for o in cfg["spaces"]:
            out.append(
                {
                    "slug": o.get("slug", ""),
                    "status": o.get("status", ""),
                    "org": o.get("org", ""),
                    "promptsFolder": o.get("promptsFolder", ""),
                    "sprintAwareness": bool((o.get("features") or {}).get("sprintAwareness", False)),
                }
            )
        return out

    HUB = PARITY_FIXTURE / "hub"

    def test_python_resolves_the_fixture_as_expected(self):
        # PROMPTS_ROOT names the hub, so the committed fixture does not have to
        # carry an absolute path that is only right on one machine.
        env = mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(self.HUB)}, clear=False)
        env.start()
        patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", PARITY_FIXTURE / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", PARITY_FIXTURE / "config.local.json"),
        ]
        for p in patches:
            p.start()
        try:
            cfg = config.load_config()
            scalars = self._expected_scalars()
            self.assertEqual(self._resolved(cfg), self._expected())
            self.assertEqual(cfg["hubFolders"]["growth"], scalars["growthFolder"])
            self.assertEqual(cfg["storeSync"], scalars["storeSync"])
        finally:
            for p in patches:
                p.stop()
            env.stop()

    SPACES_FIXTURE = PARITY_FIXTURE.parent / "hub-parity-spaces"

    def test_python_resolves_the_spaces_spelling_to_the_same_answer(self):
        # The same three files spelled `spaces` / `activeSpace`
        # resolve to exactly the expectation the older spelling does.
        env = mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(self.SPACES_FIXTURE / "hub")}, clear=False)
        env.start()
        patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.SPACES_FIXTURE / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.SPACES_FIXTURE / "config.local.json"),
        ]
        for p in patches:
            p.start()
        try:
            cfg = config.load_config()
            self.assertEqual(self._resolved(cfg), self._expected())
            self.assertEqual(cfg["activeSpace"], "test")
            self.assertEqual(cfg["storeSync"], self._expected_scalars()["storeSync"])
        finally:
            for p in patches:
                p.stop()
            env.stop()

    def test_space_keys_reads_both_spellings_and_the_new_one_wins(self):
        # The reader's canonical form is the NEW name (stage 3): an older file's
        # keys become spaces / activeSpace, the new spelling wins when both are
        # there, and the old keys are dropped.
        both = config.space_keys({"activeOrg": "old", "activeSpace": "new", "orgs": [1], "spaces": [1, 2]})
        self.assertEqual(both["activeSpace"], "new")
        self.assertEqual(both["spaces"], [1, 2])
        self.assertNotIn("activeOrg", both)
        self.assertNotIn("orgs", both)
        self.assertEqual(config.space_keys({"activeOrg": "old", "activeSpace": ""})["activeSpace"], "old")
        self.assertEqual(config.space_keys({"orgs": [1]})["spaces"], [1])
        self.assertEqual(config.space_keys({"spaces": [1]})["spaces"], [1])
        self.assertIsNone(config.space_keys(None))

    @unittest.skipUnless(shutil.which("pwsh"), "pwsh not installed")
    def test_powershell_resolves_the_fixture_the_same_way(self):
        with tempfile.TemporaryDirectory() as tmp:
            pkg = Path(tmp) / "pkg"
            pkg.mkdir()
            shutil.copy(PKG_ROOT / "utilities.psm1", pkg / "utilities.psm1")
            # The contract file is part of a package: the module reads its
            # org-scoped flag list from it at import (consts.json features.spaceScoped).
            shutil.copy(PKG_ROOT / "consts.json", pkg / "consts.json")
            shutil.copytree(PKG_ROOT / "Scripts", pkg / "Scripts")
            shutil.copy(PARITY_FIXTURE / "config.default.json", pkg / "config.default.json")
            shutil.copy(PARITY_FIXTURE / "config.local.json", pkg / "config.local.json")
            script = (
                "$ErrorActionPreference='SilentlyContinue';"
                f"$env:PROMPTS_ROOT='{self.HUB}';"
                f"Import-Module '{pkg / 'utilities.psm1'}' -Force -DisableNameChecking *>$null;"
                "$out = [ordered]@{ spaces = @($global:P20Config.Spaces | ForEach-Object {"
                " [ordered]@{ slug = [string]$_.slug; status = [string]$_.status;"
                " org = [string]$_.org; promptsFolder = [string]$_.promptsFolder;"
                " sprintAwareness = [bool]($_.features -and $_.features.sprintAwareness) } });"
                " storeSync = [string]$global:P20Config.StoreSync;"
                " promptsRoot = [string]$global:P20Config.PromptsRoot;"
                " growthFolder = [string]$global:P20Config.HubFolders['growth'] };"
                "ConvertTo-Json -InputObject $out -Depth 5 -Compress"
            )
            out = subprocess.run(
                ["pwsh", "-NoProfile", "-Command", script], capture_output=True, text=True, timeout=180, check=False
            )
            payload = out.stdout.strip().splitlines()[-1] if out.stdout.strip() else ""
            self.assertTrue(payload, f"pwsh produced nothing: {out.stderr[-800:]}")
            resolved = json.loads(payload)
            scalars = self._expected_scalars()
            self.assertEqual(resolved["spaces"], self._expected())
            self.assertEqual(resolved["storeSync"], scalars["storeSync"])
            self.assertEqual(resolved["growthFolder"], scalars["growthFolder"])

            # Where the hub IS, not only what is in it. PROMPTS_ROOT is set for
            # both halves here, and it is an explicit override that wins over
            # the fixture's promptsRoot -- which the module's PromptsRoot
            # ignored outright once, so the agent served one hub
            # while the CLI wrote into another under this very environment.
            #
            with mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(self.HUB)}, clear=False):
                patches = [
                    mock.patch.object(config, "DEFAULT_CONFIG_PATH", PARITY_FIXTURE / "config.default.json"),
                    mock.patch.object(config, "LOCAL_CONFIG_PATH", PARITY_FIXTURE / "config.local.json"),
                ]
                for p in patches:
                    p.start()
                try:
                    python_root = config.hub_root()
                finally:
                    for p in patches:
                        p.stop()
            self.assertEqual(
                Path(resolved["promptsRoot"]).resolve(),
                python_root.resolve(),
                "the CLI and the agent resolved different hubs from one environment",
            )


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
