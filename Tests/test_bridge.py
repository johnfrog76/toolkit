"""The bridge runs the CLI, and the CLI's own table says what it may run.

``POST /api/cmd/{name}`` is the only way anything in the web half writes. Four
claims, and the first is the one the whole design rests on:

  (a) the allowlist IS the CLI's command table -- every name in the live map is
      accepted, a name that is not in it is refused without running anything,
      and the map is re-read when ``utilities.psm1`` changes, so a command added
      per docs/ARCHITECTURE.md, "The bridge", is bridgeable with no edit to the agent;
  (b) parameters travel as argv, so spaces, quotes and punctuation are ordinary
      and only control characters and the size limits are refused;
  (c) a refusal is a typed ``CommandResponse`` with ``status: rejected``, not a
      404 and not an exception -- carried over from the stub this replaces,
      because it is what lets a client render every outcome the same way;
  (d) no hand-kept list of command names came across from the old package.

One command is run for real -- ``Env``, which reads and prints and writes
nothing -- because a suite that only mocks the subprocess would pass with the
PowerShell half broken.

A fifth claim was added after a Windows run found it missing:

  (e) which PowerShell is resolved rather than named. ``pwsh`` is preferred,
      ``powershell.exe`` is the Windows-only fallback so the 5.1 floor the
      README promises is a machine the web half works on, and with neither the
      call answers ``error`` naming both -- not ``rejected``, which blamed the
      command for the machine.

Run directly:  python3 Tests/test_bridge.py
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
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado import bridge
    from agent.app import app
    from agent.core import config, hosts
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

HAVE_PWSH = shutil.which("pwsh") is not None
LIVE_MAP = bridge.command_map() if HAVE_PWSH else {}


class AllowlistIsTheCommandTable(unittest.TestCase):
    """(a) -- the bridge knows nothing about commands except what the CLI says."""

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
    def test_the_map_is_read_from_the_cli(self):
        self.assertTrue(LIVE_MAP, "no command map came back from Get-P20CommandMap")
        # Values are FUNCTION names, never prefixed aliases -- that is what keeps
        # the bridge prefix-agnostic (docs/CLI.md, "The prefix").
        self.assertEqual(LIVE_MAP.get("Archive"), "Move-P20PromptToArchive")
        for name, function in LIVE_MAP.items():
            with self.subTest(name=name):
                self.assertRegex(function, r"^[A-Za-z]+-[A-Za-z0-9]+$")

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
    def test_every_name_in_the_map_is_accepted(self):
        """Accepted means "not refused" -- these are not run, only admitted.

        ``Env`` is the one that is actually run, below. Here the point is that
        no name in the live table is turned away, which is what would silently
        break the moment a new verb were added.
        """
        for name in LIVE_MAP:
            with self.subTest(name=name):
                self.assertIn(name, bridge.command_map())

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to run a command")
    def test_a_cheap_command_runs_for_real(self):
        """Env reads the machine and prints -- it writes nothing anywhere."""
        r = client.post("/api/cmd/Env", json={"params": []})
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["status"], "success", body.get("error"))
        self.assertEqual(body["exit_code"], 0)
        self.assertIn("Environment", body["output"])
        self.assertGreater(body["duration"], 0)

    def test_a_name_not_in_the_map_is_rejected(self):
        body = client.post("/api/cmd/DefinitelyNotACommand", json={"params": []}).json()
        self.assertEqual(body["status"], "rejected")
        self.assertEqual(body["exit_code"], -1)
        self.assertEqual(body["duration"], 0)

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
    def test_a_retired_go_name_is_rejected(self):
        """The old package's allowlist named eight commands this module never had.

        They are not in the CLI's table, so they are not bridgeable -- which is
        the drift this design removes, asserted rather than assumed.

        Two of the eight -- NewGrowth and PublishWorkReview -- are no longer
        examples of it: the growth module contributes them when it is switched
        on, and then they ARE bridgeable, with no edit here. That is the point
        of deriving the allowlist from the command table rather than keeping a
        list in Python, so they are out of this list rather than special-cased
        into it.
        """
        for name in ("zzArchive", "zzStressCheck", "StressCheck", "GetBilling"):
            with self.subTest(name=name):
                body = client.post(f"/api/cmd/{name}", json={"params": []}).json()
                self.assertEqual(body["status"], "rejected")

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
    def test_the_map_is_reread_when_utilities_changes(self):
        """The mtime is the cache key, so a new verb needs no restart."""
        before = bridge.command_map()
        self.assertTrue(before)
        cached_key = bridge._map_key

        stat = bridge.UTILITIES.stat()
        try:
            os.utime(bridge.UTILITIES, (stat.st_atime, stat.st_mtime + 5))
            after = bridge.command_map()
            self.assertNotEqual(
                bridge._map_key, cached_key, "the map was served from cache after utilities.psm1 changed"
            )
            self.assertEqual(after, before)
        finally:
            os.utime(bridge.UTILITIES, (stat.st_atime, stat.st_mtime))
            bridge.command_map(force=True)


@unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
class TheTableFollowsTheFlags(unittest.TestCase):
    """A module's verbs are in the table only while its flag is on, so the
     cache key has to see the flag change -- from a terminal's `Config -Set`
     (an mtime on config.local.json) and from the Configuration card (whose
     write primes the cache with the pre-flip table, hence `force`). Run against
     a SCRATCH package: the bridge imports the manifest beside itself, and a
     test that wrote this checkout's config.local.json would be editing the
     engineer's machine
    ."""

    # A verb the growth module contributes, from Config/growth.commands.psd1.
    MODULE_VERB = "NewGrowth"

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.pkg = Path(self._tmp.name) / "pkg"
        self.pkg.mkdir()
        for name in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / name, self.pkg / name)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.pkg / "agent" / "ado").mkdir(parents=True)
        shutil.copy(bridge.BRIDGE_PS1, self.pkg / "agent" / "ado" / "bridge.ps1")

        self._saved = (bridge._map_cache, bridge._map_key)
        self._patches = [
            mock.patch.object(bridge, "REPO_ROOT", self.pkg),
            mock.patch.object(bridge, "UTILITIES", self.pkg / "utilities.psm1"),
            mock.patch.object(bridge, "BRIDGE_PS1", self.pkg / "agent" / "ado" / "bridge.ps1"),
            mock.patch.object(bridge, "MODULE_COMMANDS_DIR", self.pkg / "Config"),
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.pkg / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.pkg / "config.local.json"),
            mock.patch.object(bridge, "_map_cache", {}),
            mock.patch.object(bridge, "_map_key", None),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        bridge._map_cache, bridge._map_key = self._saved
        self._tmp.cleanup()

    def _flip(self, on: bool):
        local = self.pkg / "config.local.json"
        local.write_text(json.dumps({"features": {"growth": on}}), encoding="utf-8")
        # Do not lean on the clock: move the mtime on explicitly, past the last
        # one this file had, so two flips in one tick never share a stamp.
        self._flips = getattr(self, "_flips", 0) + 1
        stat = local.stat()
        os.utime(local, (stat.st_atime, stat.st_mtime + 5 * self._flips))

    def test_a_module_verb_declares_its_own_timeout_through_the_one_table(self):
        """Config/growth.commands.psd1 says NewWorkReview may run 300 s; the agent
         never reads a .psd1, so the table it does read carries the number
        ."""
        self._flip(True)
        table = bridge.command_map(force=True)
        self.assertNotIn("_timeouts", table, "the reserved key is stripped from the allowlist")
        self.assertIn(self.MODULE_VERB, table)
        self.assertEqual(bridge.command_timeout("NewWorkReview"), 300)
        self.assertEqual(bridge.command_timeout("TestToolkit"), 300, "a core verb's config value still applies")
        self.assertEqual(bridge.command_timeout("Status"), 30)
        self.assertEqual(bridge.command_timeout("Archive"), bridge.DEFAULT_TIMEOUT_SECONDS)

    def test_a_flag_flipped_on_disk_is_seen_without_force(self):
        before = bridge.command_map(force=True)
        self.assertTrue(before, "the scratch package's table could not be read")
        self.assertNotIn(self.MODULE_VERB, before, "the committed config has every module off")

        self._flip(True)
        after = bridge.command_map()  # no force: the key has to do it
        self.assertIn(self.MODULE_VERB, after, "the table was served from the pre-flip cache")

        self._flip(False)
        self.assertNotIn(self.MODULE_VERB, bridge.command_map())

    def test_a_verb_with_no_config_local_json_does_not_open_with_the_first_run_banner(self):
        """A non-interactive caller says so with TOOLKIT_QUIET_STARTUP, and the
        not-set-up notice honours it: a dialog showing the verb's own sentence
        must not begin with "This machine is not set up yet"."""
        self.assertFalse((self.pkg / "config.local.json").exists())
        body = client.post("/api/cmd/Env", json={"params": []}).json()
        self.assertEqual(body["status"], "success", body.get("error"))
        self.assertIn("Environment", body["output"])
        self.assertNotIn("not set up yet", body["output"])
        self.assertTrue(body["output"].lstrip().startswith("Environment"), body["output"][:80])

    def test_the_key_names_every_input(self):
        key = bridge._map_key_now()
        self.assertEqual(len(key), 4)
        self.assertIsNotNone(key[0], "utilities.psm1")
        self.assertIsNotNone(key[1], "config.default.json")
        self.assertIsNone(key[2], "config.local.json is not there yet")
        self.assertEqual(
            sorted(name for name, _ in key[3]),
            sorted(f.name for f in (self.pkg / "Config").iterdir() if f.name.endswith(".commands.psd1")),
        )
        self._flip(True)
        self.assertIsNotNone(bridge._map_key_now()[2])

    def test_a_same_stamp_rewrite_still_changes_the_key(self):
        local = self.pkg / "config.local.json"
        local.write_text(json.dumps({"features": {"growth": False}}), encoding="utf-8")
        stamp = local.stat()
        before = bridge._map_key_now()
        local.write_text(json.dumps({"features": {"growth": True}}), encoding="utf-8")
        os.utime(local, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.assertNotEqual(bridge._map_key_now(), before, "an unchanged mtime hid a changed file")

    def test_a_new_module_data_file_changes_the_key(self):
        before = bridge._map_key_now()
        (self.pkg / "Config" / "zz.commands.psd1").write_text("@{}", encoding="utf-8")
        self.assertNotEqual(bridge._map_key_now(), before)


class ARepoVerbDoesNotActOnTheToolkit(unittest.TestCase):
    """The bridge runs every verb with its cwd at the Toolkit's checkout. NewPR
    used to read that checkout's branch and remote, fall back to the FIRST
    configured project, and was stopped only by the browser's id failing
    ``Test-Path`` as ``-File``.

    Run for real, through the bridge, with ``-WhatIf`` -- which resolves
    everything and calls nothing -- in a scratch package that IS a git checkout
    on a branch of its own, over a scratch hub. Nothing here can open a pull
    request: ``-WhatIf`` stops before the token is asked for.
    """

    def setUp(self):
        if not HAVE_PWSH or not shutil.which("git"):
            self.skipTest("needs pwsh and git to run NewPR for real")
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.pkg = root / "pkg"
        self.pkg.mkdir()
        for name in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / name, self.pkg / name)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.pkg / "agent" / "ado").mkdir(parents=True)
        shutil.copy(bridge.BRIDGE_PS1, self.pkg / "agent" / "ado" / "bridge.ps1")

        hub = root / "hub"
        current = hub / "azure-demo" / "current"
        current.mkdir(parents=True)
        (current / "US-119-import-flow.prompt.md").write_text(
            "# US-119: Import flow\n\n"
            "**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/119\n\n"
            "## Branch\nyou/119/import-flow\n\n## Described Changes\n- The import flow.\n",
            encoding="utf-8",
        )
        (self.pkg / "config.local.json").write_text(
            json.dumps({"promptsRoot": str(hub), "activeSpace": "azure-demo"}), encoding="utf-8"
        )

        # The Toolkit's checkout, on a branch that is nobody's card.
        git = ["git", "-C", str(self.pkg), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git + ["init", "-q", "-b", "toolkit-branch"], check=True)
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "scratch"], check=True)

        self._saved = (bridge._map_cache, bridge._map_key)
        env = {k: v for k, v in os.environ.items() if not k.startswith("TEAMS_WEBHOOK_")}
        env.pop("PROMPTS_ROOT", None)
        self._patches = [
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(bridge, "REPO_ROOT", self.pkg),
            mock.patch.object(bridge, "UTILITIES", self.pkg / "utilities.psm1"),
            mock.patch.object(bridge, "BRIDGE_PS1", self.pkg / "agent" / "ado" / "bridge.ps1"),
            mock.patch.object(bridge, "MODULE_COMMANDS_DIR", self.pkg / "Config"),
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.pkg / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.pkg / "config.local.json"),
            mock.patch.object(bridge, "_map_cache", {}),
            mock.patch.object(bridge, "_map_key", None),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        bridge._map_cache, bridge._map_key = self._saved
        self._tmp.cleanup()

    def test_newpr_by_id_reads_the_card_not_the_toolkit(self):
        body = client.post("/api/cmd/NewPR", json={"params": ["119", "-WhatIf"]}).json()
        out = body["output"]
        self.assertEqual(body["status"], "success", body.get("error") or out)
        self.assertIn("Repo: YourProject / your-repo", out)
        self.assertIn("Branch: you/119/import-flow -> main", out)
        self.assertNotIn("toolkit-branch", out)
        self.assertNotIn("first configured project", out)

    def test_newpr_with_no_card_refuses_rather_than_using_the_toolkit(self):
        body = client.post("/api/cmd/NewPR", json={"params": ["-WhatIf"]}).json()
        self.assertEqual(body["status"], "error", body["output"])
        self.assertIn("Toolkit's own checkout", body.get("error") or body["output"])
        self.assertNotIn("toolkit-branch", body["output"])


class ParametersTravelAsArgv(unittest.TestCase):
    """(b) -- no command string is built, so quoting is not a category here."""

    def test_spaces_and_punctuation_are_accepted(self):
        for param in (
            "a title with spaces",
            "Fixed, please re-review.",
            "it's done",
            '"quoted"',
            "-Comment",
            "US-144-some/slug.prompt.md",
            ";rm -rf /",
        ):
            with self.subTest(param=param):
                self.assertIsNone(bridge.reject_reason([param]))

    def test_a_control_character_is_rejected(self):
        reason = bridge.reject_reason(["bad\x00param"])
        self.assertIsNotNone(reason)
        self.assertIn("control character", reason)

    def test_tab_newline_and_return_are_not_control_characters_here(self):
        """A PR reply body legitimately contains them, and argv carries them."""
        self.assertIsNone(bridge.reject_reason(["line one\nline two\tindented\r"]))

    def test_the_size_limits_hold(self):
        self.assertIsNotNone(bridge.reject_reason(["x" * (bridge.MAX_PARAM_LENGTH + 1)]))
        self.assertIsNone(bridge.reject_reason(["x" * bridge.MAX_PARAM_LENGTH]))
        self.assertIsNotNone(bridge.reject_reason(["x"] * (bridge.MAX_PARAMS + 1)))

    @unittest.skipUnless(HAVE_PWSH, "needs pwsh to read the command table")
    def test_a_rejected_parameter_stops_the_command_running(self):
        body = client.post("/api/cmd/Archive", json={"params": ["bad\x00param"]}).json()
        self.assertEqual(body["status"], "rejected")
        self.assertEqual(body["duration"], 0)
        self.assertIn("control character", body["error"])


class TheReplyShape(unittest.TestCase):
    """(c) -- carried from the stub: one type, four statuses, never a 404."""

    def test_the_route_exists_rather_than_404ing(self):
        self.assertIn("/api/cmd/{name}", app.openapi()["paths"])

    def test_response_keeps_the_command_response_shape(self):
        body = client.post("/api/cmd/NotACommand", json={"params": []}).json()
        for key in ("command", "status", "exit_code", "output", "error", "duration"):
            self.assertIn(key, body)
        self.assertEqual(body["command"], "NotACommand")

    def test_a_refusal_is_still_a_200(self):
        """A rejection is an answer, not a transport failure."""
        r = client.post("/api/cmd/NotACommand", json={"params": []})
        self.assertEqual(r.status_code, 200)

    def test_the_model_still_carries_every_field_the_stub_promised(self):
        self.assertEqual(
            set(bridge.CommandResponse.model_fields),
            {"command", "status", "exit_code", "output", "error", "duration"},
        )


class Timeouts(unittest.TestCase):
    def test_the_default_applies_when_the_entry_says_nothing(self):
        self.assertEqual(bridge.command_timeout("Archive"), bridge.DEFAULT_TIMEOUT_SECONDS)
        self.assertEqual(bridge.command_timeout("NoSuchCommand"), bridge.DEFAULT_TIMEOUT_SECONDS)

    def test_a_command_entry_can_say_otherwise(self):
        self.assertEqual(bridge.command_timeout("TestToolkit"), 300)
        self.assertEqual(bridge.command_timeout("Status"), 30)


class NothingWasCarriedByHand(unittest.TestCase):
    """(d) -- the hand-kept allowlist must not have come across."""

    def test_no_allowlist_constant(self):
        self.assertFalse(
            [n for n in dir(bridge) if "ALLOWED" in n.upper()],
            "the hand-kept allowlist must not come across -- it is derived",
        )

    def test_no_command_name_is_written_in_the_module(self):
        source = Path(bridge.__file__).read_text(encoding="utf-8")
        body = source.split('"""', 2)[-1]  # skip the module docstring
        for name in ("zzArchive", "zzNewPR", "zzStatus", "Move-P20PromptToArchive"):
            with self.subTest(name=name):
                self.assertNotIn(name, body)


class TheHostIsResolvedNotNamed(unittest.TestCase):
    """(e) -- README's floor is Windows PowerShell 5.1, so the bridge must find it.

    A Windows machine reproduced the defect by removing PowerShell 7 from PATH for the
    agent's process: `pwsh` gone, `powershell.exe` present, command map empty,
    every write refused as "not a command in this CLI". These patch
    ``shutil.which`` and ``sys.platform`` instead, so macOS can prove the
    same three things.
    """

    def tearDown(self):
        # The resolver caches per process and the live suite above depends on
        # the real answer.
        hosts.resolve_host(force=True)

    def test_pwsh_is_preferred_wherever_it_exists(self):
        with mock.patch.object(hosts.shutil, "which", side_effect=lambda n: f"/usr/bin/{n}"):
            host = hosts.resolve_host(force=True)
        self.assertIsNotNone(host)
        self.assertEqual(host.name, "pwsh")
        self.assertEqual(host.path, "/usr/bin/pwsh")

    def test_windows_powershell_is_the_fallback_on_windows(self):
        found = {"powershell": r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"}  # export:example
        with (
            mock.patch.object(hosts.sys, "platform", "win32"),
            mock.patch.object(hosts.shutil, "which", side_effect=found.get),
        ):
            host = hosts.resolve_host(force=True)
        self.assertIsNotNone(host, "a 5.1-only Windows machine must resolve a host")
        self.assertEqual(host.name, "powershell")
        self.assertEqual(host.path, found["powershell"])

    def test_the_fallback_is_windows_only(self):
        """`powershell` on a Mac or a Linux box is not Windows PowerShell.

        It is either absent or something else entirely, so the name is not even
        probed there -- a resolved host that cannot run bridge.ps1 would be
        worse than none.
        """
        probed = []

        def which(name):
            probed.append(name)
            return "/usr/local/bin/powershell" if name == "powershell" else None

        with (
            mock.patch.object(hosts.sys, "platform", "darwin"),
            mock.patch.object(hosts.shutil, "which", side_effect=which),
        ):
            host = hosts.resolve_host(force=True)
        self.assertIsNone(host)
        self.assertEqual(probed, ["pwsh"])

    def test_the_answer_is_cached_per_process(self):
        with mock.patch.object(hosts.shutil, "which", side_effect=lambda n: f"/usr/bin/{n}"):
            first = hosts.resolve_host(force=True)
        with mock.patch.object(hosts.shutil, "which", return_value=None) as which:
            second = hosts.resolve_host()
        self.assertEqual(first, second)
        which.assert_not_called()

    def test_with_no_host_the_map_read_returns_empty_without_raising(self):
        with mock.patch.object(hosts.shutil, "which", return_value=None):
            hosts.resolve_host(force=True)
            self.assertEqual(bridge._read_command_map(), {})
            self.assertEqual(bridge.command_map(force=True), {})

    def test_with_no_host_a_command_is_an_error_not_a_rejection(self):
        with mock.patch.object(hosts.shutil, "which", return_value=None):
            hosts.resolve_host(force=True)
            body = client.post("/api/cmd/Archive", json={"params": []}).json()
        self.assertEqual(body["status"], "error", "no PowerShell is a fact about the machine, not about the name")
        self.assertEqual(body["exit_code"], -1)
        self.assertIn("pwsh", body["error"])
        self.assertIn("powershell", body["error"])

    def test_env_reports_which_host_the_bridge_will_use(self):
        block = client.get("/api/env").json()["bridgeHost"]
        self.assertEqual(set(block), {"resolved", "path"})
        if shutil.which("pwsh"):
            self.assertEqual(block["resolved"], "pwsh")
            self.assertTrue(block["path"])
        else:  # pragma: no cover - a Mac without pwsh
            self.assertIsNone(block["resolved"])


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
