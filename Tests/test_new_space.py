"""NewSpace -- the verb, typed in a fresh shell, and the + dialog's route.

The verb runs in a fresh pwsh holding this package's module and nothing else
(AGENTS.md, "One toolkit per shell"), against a scratch copy of the package and a
scratch hub -- never a real one. `gh` is ALWAYS a stand-in: either a function the
snippet defines (signed in, two repositories, one of them already a Space), or
taken off the PATH entirely (absent). The real gh is never called and no
repository is ever created.

GET /api/spaces/candidates is the picker's read: the verb's -Discover -AsJson
through the bridge. Here the bridge call is stubbed with answers of the verb's own
shape -- one of them the verb's real output from the scratch package -- and with
the two ways it cannot answer.

Run:  python3 -m pytest Tests/test_new_space.py
"""

import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _shortpath import long_path, short_path  # noqa: E402
from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.ado.bridge import CommandResponse
    from agent.app import app
    from agent.studio import spaces
except Exception as exc:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(exc).__name__}: {exc})")


def _pwsh():
    return shutil.which("pwsh")


# The stand-in for gh: signed in as `tester`, two repositories of their own (one
# of them already the `toolkit` Space), one repository that does not exist.
GH_SIGNED_IN = r"""
function global:gh {
    $a = @($args)
    $global:LASTEXITCODE = 0
    $global:GhCalls += @($a -join ' ')
    if ($a[0] -eq 'auth') { return 'Logged in to github.com as tester' }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/orgs') { return '[{"login":"acme"}]' }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/repos' -and $env:P20_TEST_MANY) {
        # A long list shared with you, served a page of 100 at a time as GitHub does.
        $total = [int]$env:P20_TEST_MANY
        $page = 1
        foreach ($x in $a) { if ([string]$x -like 'page=*') { $page = [int]([string]$x).Substring(5) } }
        $from = ($page - 1) * 100 + 1
        $to = [Math]::Min($total, $page * 100)
        if ($from -gt $to) { return '[]' }
        return '[' + ((($from..$to) | ForEach-Object { '{"name":"shared-' + $_ + '","owner":{"login":"friend"},"visibility":"private","archived":false,"permissions":{"push":true,"pull":true}}' }) -join ',') + ']'
    }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/repos') {
        return '[{"name":"upstream","owner":{"login":"someone"},"visibility":"public","archived":false,"description":"","permissions":{"push":false,"pull":true}}]'
    }
    if ($a[0] -eq 'api') { return 'tester' }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'view') {
        if ($a[2] -eq 'tester/ghost') { $global:LASTEXITCODE = 1; return 'GraphQL: Could not resolve to a Repository with the name tester/ghost.' }
        if ($a[2] -eq 'tester/juggling-engine') { return '{"visibility":"PUBLIC"}' }
        if ($a[2] -eq 'tester/old-thing') { return '{"visibility":"PRIVATE","isArchived":true}' }
        if ($a[2] -eq 'someone/upstream') { return '{"visibility":"PUBLIC","isArchived":false,"viewerPermission":"READ"}' }
        return '{"visibility":"PRIVATE","isArchived":false}'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'nobody') {
        # On the error stream, as the real gh writes it to stderr.
        $global:LASTEXITCODE = 1; Write-Error "GraphQL: Could not resolve to a RepositoryOwner with the login of 'nobody'."; return
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'big') {
        # An owner with P20_TEST_MANY repositories, of which gh returns --limit.
        $lim = [int]$a[[array]::IndexOf($a, '--limit') + 1]
        $n = [Math]::Min([int]$env:P20_TEST_MANY, $lim)
        return '[' + (((1..$n) | ForEach-Object { '{"name":"r' + $_ + '","owner":{"login":"big"},"visibility":"PUBLIC","isArchived":false,"viewerPermission":"WRITE","description":""}' }) -join ',') + ']'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'acme') {
        return '[{"name":"site","owner":{"login":"acme"},"visibility":"PUBLIC","isArchived":false,"viewerPermission":"READ","description":""},{"name":"api","owner":{"login":"acme"},"visibility":"PRIVATE","isArchived":false,"viewerPermission":"WRITE","description":""}]'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list') {
        return '[{"name":"juggling-engine","owner":{"login":"tester"},"visibility":"PUBLIC","description":"Balls in the air"},{"name":"toolkit","owner":{"login":"johnfrog76"},"visibility":"PRIVATE","description":""},{"name":"Notes_App","owner":{"login":"tester"},"visibility":"PRIVATE","isArchived":false,"description":"x"},{"name":"old-thing","owner":{"login":"tester"},"visibility":"PRIVATE","isArchived":true,"description":"done"}]'
    }
    $global:LASTEXITCODE = 9
    return "unexpected gh call: $($a -join ' ')"
}
"""  # noqa: E501 -- a PowerShell script; its line length is PowerShell's

# gh absent: every PATH entry holding a gh is dropped for this shell, and no
# function stands in -- so Get-Command gh finds nothing.
GH_ABSENT = r"""
$sep = [System.IO.Path]::PathSeparator
$env:PATH = (@($env:PATH -split [regex]::Escape([string]$sep)) | Where-Object { $_ -and -not (Test-Path (Join-Path $_ 'gh')) -and -not (Test-Path (Join-Path $_ 'gh.exe')) }) -join $sep
"""  # noqa: E501 -- a PowerShell script; its line length is PowerShell's


@unittest.skipIf(_pwsh() is None, "pwsh is not on this machine")
class TheNewSpaceVerb(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # LONG, once: tempfile is the 8.3 short form on some Windows accounts,
        # and the short form is tested on purpose below, not by accident everywhere.
        base = long_path(self._tmp.name)
        self.pkg = base / "pkg"
        self.hub = base / "hub"
        self.log = base / "log"
        self.pkg.mkdir()
        self.log.mkdir()
        for item in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(PKG_ROOT / item, self.pkg / item)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(PKG_ROOT / folder, self.pkg / folder)
        (self.hub / "demo" / "current").mkdir(parents=True)
        (self.hub / "toolkit" / "current").mkdir(parents=True)
        self.write_hub(
            {
                "hub": 1,
                "spaces": [
                    {"slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo"},
                    {
                        "slug": "toolkit",
                        "name": "Toolkit",
                        "status": "active",
                        "promptsFolder": "toolkit",
                        "org": "https://github.com/johnfrog76/toolkit",
                    },
                ],
            }
        )
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": self.hub.as_posix(),
                    "activeSpace": "demo",
                    "quietStart": True,
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self):
        self._tmp.cleanup()

    def write_hub(self, data):
        self.hub.mkdir(parents=True, exist_ok=True)
        (self.hub / "hub.json").write_text(json.dumps(data, indent=2), encoding="utf-8")

    def hub_json(self) -> dict:
        return json.loads((self.hub / "hub.json").read_text(encoding="utf-8"))

    def space(self, slug):
        return next((s for s in self.hub_json().get("spaces", []) if s.get("slug") == slug), None)

    def snapshot(self) -> dict:
        roots = [self.hub, self.pkg / "config.local.json"]
        out = {}
        for root in roots:
            items = [root] if root.is_file() else list(root.rglob("*"))
            for p in items:
                out[str(p)] = p.read_bytes() if p.is_file() else "dir"
        return out

    def run_verbs(self, snippet: str, gh: str = GH_SIGNED_IN, hub: Path | None = None) -> str:
        def q(p):
            return str(p).replace("'", "''")

        body = (
            GH_ABSENT + "\n" + f"$env:PSModulePath = '{q(self.pkg)}'; $env:PROMPTS_ROOT = '{q(hub or self.hub)}'; "
            f"$env:P20_USAGE_LOG_DIR = '{q(self.log)}'\n"
            f"Import-Module '{q(self.pkg)}/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>$null 6>$null\n"
            + gh
            + "\n"
            + snippet
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

    @staticmethod
    def last_json(text: str):
        lines = [ln for ln in text.splitlines() if ln.strip().startswith("{")]
        return json.loads(lines[-1]) if lines else None

    # -- registration ----------------------------------------------------------------
    def test_it_is_a_core_verb_the_bridge_can_call(self):
        out = self.run_verbs("'MAP=' + (Get-P20CommandMap); tkNewSpace -Help")
        self.assertIn('"NewSpace":"New-P20Space"', out.replace(" ", ""))
        self.assertIn("NewSpace [<slug>] [-Repo <owner/name>]", out)
        manifest = (PKG_ROOT / "Prompt20Toolkit" / "Prompt20Toolkit.psd1").read_text(encoding="utf-8")
        self.assertIn("'tkNewSpace',", manifest)

    # -- the three forms -----------------------------------------------------------------
    def test_a_repository_is_a_github_space_named_from_it(self):
        out = self.run_verbs("tkNewSpace -Repo tester/juggling-engine; 'X=' + $LASTEXITCODE")
        self.assertIn("X=0", out)
        s = self.space("juggling-engine")
        self.assertIsNotNone(s, out)
        self.assertEqual(s["name"], "Juggling Engine")
        self.assertEqual(s["status"], "active")
        self.assertEqual(s["org"], "https://github.com/tester/juggling-engine")
        self.assertEqual(s["promptsFolder"], "juggling-engine")
        self.assertTrue((self.hub / "juggling-engine" / "current").is_dir())
        self.assertTrue((self.hub / "juggling-engine" / "archive").is_dir())
        self.assertIn("PUBLIC", out)
        # It does not switch, and its last line is the command that does.
        local = json.loads((self.pkg / "config.local.json").read_text(encoding="utf-8"))
        self.assertEqual(local["activeSpace"], "demo")
        last = [ln for ln in out.splitlines() if ln.strip()][-2]
        self.assertEqual(last.strip(), "tkSwitchSpace juggling-engine")

    def test_a_pasted_address_reads_as_owner_name_and_name_and_slug_can_be_given(self):
        out = self.run_verbs("tkNewSpace jug -Repo https://github.com/tester/Notes_App.git -Name 'My notes' -AsJson")
        r = self.last_json(out)
        self.assertEqual(
            (r["slug"], r["name"], r["repo"], r["visibility"]), ("jug", "My notes", "tester/Notes_App", "PRIVATE"), out
        )
        self.assertEqual(self.space("jug")["org"], "https://github.com/tester/Notes_App")

    def test_an_address_is_an_azure_devops_space_and_names_the_next_step(self):
        out = self.run_verbs("tkNewSpace acme -Address https://dev.azure.com/acme; 'X=' + $LASTEXITCODE")
        self.assertIn("X=0", out)
        s = self.space("acme")
        self.assertEqual((s["org"], s["status"], s["name"]), ("https://dev.azure.com/acme", "active", "Acme"))
        self.assertIn("tkConnect acme -Discover", out)
        self.assertNotIn("projects", s)

    def test_a_slug_alone_is_your_own_cards_local(self):
        out = self.run_verbs("tkNewSpace side-notes -AsJson")
        r = self.last_json(out)
        self.assertEqual((r["status"], r["tracker"], r["address"], r["name"]), ("local", "none", "", "Side Notes"), out)
        s = self.space("side-notes")
        self.assertEqual(s["status"], "local")
        self.assertFalse(s.get("org"))
        self.assertEqual(r["next"], "tkSwitchSpace side-notes")

    def test_the_proposals_follow_the_shared_table(self):
        table = json.loads((PKG_ROOT / "Tests" / "fixtures" / "spaces" / "proposals.json").read_text(encoding="utf-8"))
        lines = "; ".join(
            f"'ROW={row['repo']}'; tkNewSpace -Repo 'tester/{row['repo']}' -WhatIf -AsJson; 'X=' + $LASTEXITCODE"
            for row in table["rows"]
        )
        out = self.run_verbs(lines)
        chunks = out.split("ROW=")[1:]
        self.assertEqual(len(chunks), len(table["rows"]), out)
        for row, chunk in zip(table["rows"], chunks):
            with self.subTest(repo=row["repo"]):
                if row["valid"]:
                    r = self.last_json(chunk)
                    self.assertIsNotNone(r, chunk)
                    self.assertEqual((r["slug"], r["name"]), (row["slug"], row["name"]))
                else:
                    self.assertIn("X=2", chunk)
                    self.assertIn(f"does not make a slug ('{row['slug']}')", chunk)

    # -- adoption ---------------------------------------------------------------------
    def test_an_existing_folder_is_adopted_untouched_and_its_cards_counted(self):
        cur = self.hub / "old-work" / "current"
        arc = self.hub / "old-work" / "archive"
        cur.mkdir(parents=True)
        arc.mkdir(parents=True)
        (cur / "Task7-a-card.prompt.md").write_bytes(b"# Task 7\r\n")
        (cur / "8-another.prompt.md").write_bytes(b"# 8\n")
        (arc / "Task3-done.prompt.md").write_bytes(b"# 3\n")
        before = {str(p): p.read_bytes() for p in (self.hub / "old-work").rglob("*") if p.is_file()}
        out = self.run_verbs("tkNewSpace old-work -AsJson; tkNewSpace other")
        r = next(json.loads(ln) for ln in out.splitlines() if ln.strip().startswith('{"slug":"old-work"'))
        self.assertTrue(r["adopted"])
        self.assertEqual(r["cards"], 3)
        after = {str(p): p.read_bytes() for p in (self.hub / "old-work").rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        text = self.run_verbs("tkNewSpace -Repo tester/juggling-engine -WhatIf")
        self.assertIn("make", text)
        (self.hub / "kept" / "current").mkdir(parents=True)
        (self.hub / "kept" / "current" / "1-x.prompt.md").write_bytes(b"# 1\n")
        said = self.run_verbs("tkNewSpace kept")
        self.assertIn("adopted as it is: 1 cards (1 current, 0 archive)", said)

    # -- -WhatIf --------------------------------------------------------------------------
    def test_what_if_names_every_key_and_the_folder_and_writes_nothing(self):
        before = self.snapshot()
        out = self.run_verbs("tkNewSpace -Repo tester/juggling-engine -WhatIf; 'X=' + $LASTEXITCODE")
        self.assertEqual(before, self.snapshot())
        for key in (
            "spaces.juggling-engine.name=Juggling Engine",
            "spaces.juggling-engine.status=active",
            "spaces.juggling-engine.promptsFolder=juggling-engine",
            "spaces.juggling-engine.org=https://github.com/tester/juggling-engine",
        ):
            self.assertIn(f"[WhatIf] tkConfig -Set {key} -Hub", out)
        self.assertIn("juggling-engine", out)
        self.assertIn("X=0", out)
        j = self.last_json(self.run_verbs("tkNewSpace x1 -WhatIf -AsJson"))
        self.assertTrue(j["whatIf"])
        self.assertEqual(before, self.snapshot())

    # -- refusals: exit 2, one sentence, nothing written --------------------------------------
    def assert_refused(self, snippet, *words):
        before = self.snapshot()
        out = self.run_verbs(snippet + "; 'X=' + $LASTEXITCODE")
        self.assertIn("X=2", out, out)
        self.assertEqual(out.count("Error:"), 1, out)
        for w in words:
            self.assertIn(w, out)
        self.assertEqual(before, self.snapshot(), "a refusal wrote something")
        return out

    def test_no_arguments_names_the_three_forms(self):
        self.assert_refused(
            "tkNewSpace", "-Repo owner/name", "-Address https://dev.azure.com/<org>", "for your own cards"
        )

    def test_each_refusal(self):
        self.assert_refused("tkNewSpace demo", "already a Space 'demo'")
        self.assert_refused("tkNewSpace Bad_Slug", "'Bad_Slug' is not a slug")
        self.assert_refused("tkNewSpace -Repo not-a-repo", "'not-a-repo' is not owner/name")
        self.assert_refused("tkNewSpace x -Repo a/b -Address https://dev.azure.com/a", "not both")
        self.assert_refused("tkNewSpace -Repo johnfrog76/TOOLKIT", "already a Space: Toolkit (toolkit)")
        self.assert_refused("tkNewSpace -Address https://dev.azure.com/acme", "needs a slug")
        self.assert_refused("tkNewSpace growth", "the hub's own folder")
        self.assert_refused("tkNewSpace test", "already a Space")  # the Azure demo's old slug
        self.assert_refused("tkNewSpace x -Address https://github.com/tester", "is an owner")

    def test_a_folder_another_space_keeps_is_refused(self):
        hub = self.hub_json()
        hub["spaces"].append({"slug": "elsewhere", "name": "Elsewhere", "status": "local", "promptsFolder": "shared"})
        self.write_hub(hub)
        self.assert_refused("tkNewSpace shared", "already Elsewhere (elsewhere)'s cards")

    # -- gh: asked, never required ------------------------------------------------------------
    def test_without_gh_the_space_is_added_and_the_repository_not_checked(self):
        out = self.run_verbs("tkNewSpace -Repo tester/juggling-engine; 'X=' + $LASTEXITCODE", gh="")
        self.assertIn("X=0", out)
        self.assertIn("not checked: gh is not installed", out)
        self.assertEqual(self.space("juggling-engine")["status"], "active")

    def test_a_failed_check_adds_the_space_anyway_and_says_why(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Repo tester/ghost -AsJson"))
        self.assertFalse(r["checked"])
        self.assertIn("Could not resolve", r["note"])
        self.assertIsNotNone(self.space("ghost"))

    # -- a hub reached through a Windows 8.3 short name ------------------------------
    @unittest.skipUnless(sys.platform == "win32", "8.3 short names are a Windows thing")
    def test_a_hub_reached_through_a_short_windows_path(self):
        """``C:\\Users\\<name>~1.<domain>\\...`` passes Test-Path and fails Move-Item; NewSpace said
        "Error: An object at the specified path ... does not exist." and exited 0."""
        short = short_path(self.hub)
        if short == self.hub:
            self.skipTest("this volume does not make 8.3 names")
        (self.pkg / "config.local.json").write_text(
            json.dumps(
                {
                    "promptsRoot": str(short),
                    "activeSpace": "demo",
                    "quietStart": True,
                }
            ),
            encoding="utf-8",
        )
        out = self.run_verbs("tkNewSpace side-notes -AsJson; 'X=' + $LASTEXITCODE", hub=short)
        self.assertNotIn("Error:", out)
        self.assertIn("X=0", out)
        r = self.last_json(out)
        self.assertIsNotNone(r, out)
        self.assertNotIn("~", r["folder"], "the hub is named in its long form")
        self.assertEqual(self.space("side-notes")["status"], "local")
        self.assertTrue((self.hub / "side-notes" / "current").is_dir())
        self.assertFalse((self.hub / "hub.json.p20tmp").exists(), "the atomic write left its temp file")

    # -- -Discover -----------------------------------------------------------------------------
    def test_discover_lists_your_repositories_and_marks_the_spaces(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Discover -AsJson"))
        self.assertTrue(r["available"])
        self.assertEqual(r["account"], "tester")
        rows = {x["repo"]: x for x in r["repos"]}
        self.assertEqual(rows["johnfrog76/toolkit"]["space"], "toolkit")
        self.assertEqual(rows["tester/juggling-engine"]["space"], "")
        self.assertEqual(rows["tester/juggling-engine"]["proposedSlug"], "juggling-engine")
        self.assertEqual(rows["tester/Notes_App"]["proposedName"], "Notes App")
        self.assertEqual(rows["tester/Notes_App"]["proposedSlug"], "notes-app")
        self.assertEqual(rows["tester/juggling-engine"]["command"], "tkNewSpace -Repo tester/juggling-engine")
        # GitHub-archived: carried on the row, the Space's status untouched.
        self.assertTrue(rows["tester/old-thing"]["isArchived"])
        self.assertFalse(rows["tester/juggling-engine"]["isArchived"])
        text = self.run_verbs("tkNewSpace -Discover")
        self.assertRegex(text, r"tester/old-thing\s+private\s+ARCHIVED tkNewSpace -Repo tester/old-thing")
        self.assertNotRegex(text, r"juggling-engine\s+public\s+ARCHIVED")
        self.assertIn("tkNewSpace -Repo tester/juggling-engine", text)
        self.assertIn("already a Space: Toolkit (toolkit)", text)

    def test_repo_reads_isarchived_from_the_same_view_and_prints_it(self):
        r = self.last_json(self.run_verbs("tkNewSpace old -Repo tester/old-thing -WhatIf -AsJson"))
        self.assertTrue(r["isArchived"], r)
        self.assertEqual(r["status"], "active")
        self.assertIn("PRIVATE ARCHIVED", self.run_verbs("tkNewSpace old -Repo tester/old-thing -WhatIf"))
        self.assertFalse(
            self.last_json(self.run_verbs("tkNewSpace jug -Repo tester/juggling-engine -WhatIf -AsJson"))["isArchived"]
        )

    def test_discover_without_gh_says_what_is_unavailable(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Discover -AsJson", gh=""))
        self.assertFalse(r["available"])
        self.assertIn("gh, the GitHub CLI, is not installed", r["reason"])
        self.assertEqual(r["repos"], [])
        text = self.run_verbs("tkNewSpace -Discover; 'X=' + $LASTEXITCODE", gh="")
        self.assertIn("X=2", text)
        self.assertIn("not installed", text)

    # -- -Discover -Owner ----------------------------------------------------------
    def test_discover_offers_the_owners_you_your_organisations_and_collaborator(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Discover -AsJson"))
        self.assertEqual(
            [(o["value"], o["kind"]) for o in r["owners"]],
            [("tester", "user"), ("acme", "organization"), ("collaborator", "collaborator")],
        )
        self.assertEqual(r["owner"], "tester")

    def test_owner_lists_an_organisations_repositories_and_marks_the_read_only_one(self):
        out = self.run_verbs("tkNewSpace -Discover -Owner acme -AsJson; 'CALLS=' + ($global:GhCalls -join '|')")
        r = self.last_json(out)
        self.assertEqual(r["owner"], "acme")
        rows = {x["repo"]: x for x in r["repos"]}
        self.assertEqual(sorted(rows), ["acme/api", "acme/site"])
        self.assertEqual(
            (rows["acme/site"]["viewerPermission"], rows["acme/site"]["readOnly"], rows["acme/site"]["visibility"]),
            ("READ", True, "PUBLIC"),
        )
        self.assertEqual((rows["acme/api"]["viewerPermission"], rows["acme/api"]["readOnly"]), ("WRITE", False))
        self.assertIn("repo list acme --json", out)
        self.assertNotIn("&", out.split("CALLS=")[-1])
        text = self.run_verbs("tkNewSpace -Discover -Owner acme")
        self.assertRegex(text, r"acme/site\s+public\s+READ-ONLY tkNewSpace -Repo acme/site")
        self.assertIn("Owners: tester (yours), acme, collaborator", text)

    def test_owner_collaborator_reads_the_repositories_shared_with_you_through_f_fields(self):
        out = self.run_verbs("tkNewSpace -Discover -Owner collaborator -AsJson; 'CALLS=' + ($global:GhCalls -join '|')")
        r = self.last_json(out)
        row = r["repos"][0]
        self.assertEqual(
            (row["repo"], row["visibility"], row["viewerPermission"], row["readOnly"]),
            ("someone/upstream", "PUBLIC", "READ", True),
        )
        calls = out.split("CALLS=")[-1]
        self.assertIn("api user/repos -X GET -f affiliation=collaborator -f per_page=100", calls)
        self.assertNotIn("&", calls)

    def test_repo_reads_the_permission_with_the_visibility(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Repo someone/upstream -WhatIf -AsJson"))
        self.assertEqual((r["visibility"], r["viewerPermission"], r["readOnly"]), ("PUBLIC", "READ", True))
        self.assertIn("PUBLIC READ-ONLY", self.run_verbs("tkNewSpace -Repo someone/upstream -WhatIf"))
        mine = self.last_json(self.run_verbs("tkNewSpace jug -Repo tester/juggling-engine -WhatIf -AsJson"))
        self.assertFalse(mine["readOnly"])

    def test_owner_refusals(self):
        self.assert_refused(
            "tkNewSpace -Discover -Owner nobody", "The repositories of 'nobody' cannot be listed", "Hint:"
        )
        self.assert_refused("tkNewSpace -Discover -Owner 'a&b'", "'a&b' is not an owner")
        self.assert_refused("tkNewSpace -Owner acme", "it does not add a Space")
        r = self.last_json(self.run_verbs("tkNewSpace -Discover -Owner nobody -AsJson"))
        self.assertFalse(r["available"])
        self.assertEqual(len(r["owners"]), 3)

    # -- -Discover -Repo: a typed repository, read before it is added ------------------------
    def test_discover_repo_reads_one_repository_before_it_is_added(self):
        out = self.run_verbs(
            "tkNewSpace -Discover -Repo tester/juggling-engine -AsJson; 'CALLS=' + ($global:GhCalls -join '|')"
        )
        r = self.last_json(out)
        self.assertTrue(r["available"])
        self.assertEqual(len(r["repos"]), 1)
        row = r["repos"][0]
        self.assertEqual(
            (row["repo"], row["visibility"], row["proposedSlug"], row["proposedName"], row["note"]),
            ("tester/juggling-engine", "PUBLIC", "juggling-engine", "Juggling Engine", ""),
        )
        calls = out.split("CALLS=")[-1]
        self.assertIn("repo view tester/juggling-engine --json name,owner,visibility", calls)
        self.assertNotIn("user/orgs", calls)
        self.assertNotIn("&", calls)

    def test_a_repository_gh_cannot_see_is_said_not_visible_to_this_login(self):
        r = self.last_json(self.run_verbs("tkNewSpace -Discover -Repo tester/ghost -AsJson"))
        row = r["repos"][0]
        self.assertEqual(row["visibility"].lower(), "unknown", "the contract's word for no answer")
        self.assertTrue(row["note"].startswith("not visible to this login: gh answered"), row["note"])
        self.assertEqual(row["command"], "tkNewSpace -Repo tester/ghost")
        # ... and the Add says the same, rather than "not checked".
        added = self.last_json(self.run_verbs("tkNewSpace -Repo tester/ghost -WhatIf -AsJson"))
        self.assertFalse(added["checked"])
        self.assertTrue(added["note"].startswith("not visible to this login"), added["note"])

    def test_discover_repo_refusals(self):
        self.assert_refused("tkNewSpace -Discover -Repo a/b -Owner acme", "not both: give -Owner or -Repo")
        self.assert_refused("tkNewSpace -Discover -Repo not-a-repo", "'not-a-repo' is not owner/name")

    # -- Paging: past 200, to the ceiling, and said past it ------------------------------------
    def test_an_owners_list_is_read_past_200_and_said_past_the_ceiling(self):
        out = self.run_verbs(
            "$env:P20_TEST_MANY = '250'; tkNewSpace -Discover -Owner big -AsJson; "
            "'CALLS=' + ($global:GhCalls -join '|')"
        )
        r = self.last_json(out)
        self.assertEqual((len(r["repos"]), r["more"], r["ceiling"]), (250, False, 1000))
        self.assertRegex(out.split("CALLS=")[-1], r"repo list big --json \S+ --limit 1001")
        r = self.last_json(self.run_verbs("$env:P20_TEST_MANY = '1200'; tkNewSpace -Discover -Owner big -AsJson"))
        self.assertEqual((len(r["repos"]), r["more"]), (1000, True))

    def test_the_repositories_shared_with_you_are_read_a_page_at_a_time(self):
        out = self.run_verbs(
            "$env:P20_TEST_MANY = '250'; tkNewSpace -Discover -Owner collaborator -AsJson; "
            "'CALLS=' + ($global:GhCalls -join '|')"
        )
        r = self.last_json(out)
        self.assertEqual((len(r["repos"]), r["more"]), (250, False))
        calls = out.split("CALLS=")[-1].strip().splitlines()[0].split("|")
        pages = [c for c in calls if c.startswith("api user/repos")]
        self.assertEqual(
            pages,
            [f"api user/repos -X GET -f affiliation=collaborator -f per_page=100 -f page={n}" for n in (1, 2, 3)],
        )
        self.assertFalse(any("&" in c for c in calls))
        r = self.last_json(
            self.run_verbs("$env:P20_TEST_MANY = '1250'; tkNewSpace -Discover -Owner collaborator -AsJson")
        )
        self.assertEqual((len(r["repos"]), r["more"]), (1000, True))

    def test_the_route_reads_the_verbs_own_answer(self):
        out = self.run_verbs("tkNewSpace -Discover -AsJson")
        stub = _Stub(_ok(out))
        with _patched(spaces, stub):
            body = asyncio.run(spaces.get_candidates())
        self.assertTrue(body.available)
        self.assertEqual(
            {c.repo for c in body.repos},
            {"tester/juggling-engine", "johnfrog76/toolkit", "tester/Notes_App", "tester/old-thing"},
        )
        self.assertTrue({c.repo: c.isArchived for c in body.repos}["tester/old-thing"])
        self.assertEqual(body.ceiling, 1000)
        # A typed repository gh cannot see, the verb's real answer, served as the row says it.
        stub = _Stub(_ok(self.run_verbs("tkNewSpace -Discover -Repo tester/ghost -AsJson")))
        with _patched(spaces, stub):
            body = asyncio.run(spaces.get_candidates(repo="tester/ghost"))
        self.assertEqual(stub.calls, [("NewSpace", ["-Discover", "-AsJson", "-Repo", "tester/ghost"])])
        self.assertEqual((body.repos[0].visibility, body.repos[0].proposedSlug), ("UNKNOWN", "ghost"))
        self.assertTrue(body.repos[0].note.startswith("not visible to this login"))


# -- The route, with the bridge stubbed ------------------------------------------------------


def _ok(output: str):
    return CommandResponse(command="NewSpace", status="success", exit_code=0, output=output, error=None, duration=1)


class _Stub:
    def __init__(self, answer):
        self.answer = answer
        self.calls = []

    async def __call__(self, name, req=None):
        self.calls.append((name, list(req.params) if req else []))
        return self.answer


class _patched:
    def __init__(self, module, stub):
        self.module, self.stub = module, stub

    def __enter__(self):
        self.saved = self.module.run_command
        self.module.run_command = self.stub

    def __exit__(self, *exc):
        self.module.run_command = self.saved


class TheCandidatesRoute(unittest.TestCase):
    """GET /api/spaces/candidates: NewSpace -Discover -AsJson through the bridge. A read."""

    def setUp(self):
        self.spaces = spaces
        self.client = TestClient(app)

    def get(self, stub):
        with _patched(self.spaces, stub):
            return self.client.get("/api/spaces/candidates")

    def test_it_runs_the_verb_and_serves_its_rows(self):
        verb = json.dumps(
            {
                "available": True,
                "reason": "",
                "hint": "",
                "account": "tester",
                "repos": [
                    {
                        "repo": "tester/a",
                        "name": "a",
                        "owner": "tester",
                        "visibility": "PRIVATE",
                        "description": "",
                        "proposedSlug": "a",
                        "proposedName": "A",
                        "space": "",
                        "spaceName": "",
                        "command": "tkNewSpace -Repo tester/a",
                        "isArchived": True,
                    },
                ],
            }
        )
        stub = _Stub(_ok("warming up\n" + verb + "\n"))
        res = self.get(stub)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(stub.calls, [("NewSpace", ["-Discover", "-AsJson"])])
        self.assertTrue(body["available"])
        self.assertEqual(body["repos"][0]["visibility"], "PRIVATE")
        self.assertEqual(body["repos"][0]["proposedSlug"], "a")
        self.assertIs(body["repos"][0]["isArchived"], True)

    def test_owner_is_the_verbs_owner_and_the_owners_and_read_only_are_served(self):
        verb = json.dumps(
            {
                "available": True,
                "reason": "",
                "hint": "",
                "account": "tester",
                "owner": "acme",
                "owners": [
                    {"value": "tester", "label": "tester", "kind": "user"},
                    {"value": "acme", "label": "acme", "kind": "organization"},
                    {"value": "collaborator", "label": "Collaborator", "kind": "collaborator"},
                ],
                "repos": [
                    {
                        "repo": "acme/site",
                        "name": "site",
                        "owner": "acme",
                        "visibility": "PUBLIC",
                        "viewerPermission": "READ",
                        "readOnly": True,
                        "isArchived": False,
                    }
                ],
            }
        )
        stub = _Stub(_ok(verb))
        with _patched(self.spaces, stub):
            body = self.client.get("/api/spaces/candidates", params={"owner": "acme"}).json()
        self.assertEqual(stub.calls, [("NewSpace", ["-Discover", "-AsJson", "-Owner", "acme"])])
        self.assertEqual(body["owner"], "acme")
        self.assertEqual([o["kind"] for o in body["owners"]], ["user", "organization", "collaborator"])
        self.assertIs(body["repos"][0]["readOnly"], True)
        self.assertEqual(body["repos"][0]["viewerPermission"], "READ")
        # An older verb that says nothing of either reads as not read-only, no owners.
        old = json.dumps({"available": True, "account": "tester", "repos": [{"repo": "tester/a", "readOnly": None}]})
        body = self.get(_Stub(_ok(old))).json()
        self.assertIs(body["repos"][0]["readOnly"], False)
        self.assertEqual(body["owners"], [])

    def test_gh_absent_is_unavailable_with_the_verbs_sentence(self):
        verb = json.dumps(
            {
                "available": False,
                "reason": "Your repositories cannot be listed: gh, the GitHub CLI, is not installed.",
                "hint": "Install gh",
                "account": "",
                "repos": [],
            }
        )
        body = self.get(_Stub(_ok(verb))).json()
        self.assertFalse(body["available"])
        self.assertIn("not installed", body["reason"])
        self.assertEqual(body["repos"], [])

    def test_a_bridge_that_cannot_answer_is_unavailable_never_an_error(self):
        failed = CommandResponse(
            command="NewSpace",
            status="error",
            exit_code=-1,
            output=None,
            error="Could not start PowerShell: no host",
            duration=0,
        )
        body = self.get(_Stub(failed)).json()
        self.assertFalse(body["available"])
        self.assertIn("Could not start PowerShell", body["reason"])
        body = self.get(_Stub(_ok("no json here"))).json()
        self.assertFalse(body["available"])
        self.assertTrue(body["reason"])

    def test_repo_is_the_verbs_repo_and_its_note_is_served(self):
        verb = json.dumps(
            {
                "available": True,
                "account": "tester",
                "owner": "tester",
                "owners": [],
                "ceiling": 1000,
                "more": False,
                "repos": [
                    {
                        "repo": "tester/ghost",
                        "name": "ghost",
                        "owner": "tester",
                        "visibility": "UNKNOWN",
                        "proposedSlug": "ghost",
                        "proposedName": "Ghost",
                        "command": "tkNewSpace -Repo tester/ghost",
                        "note": "not visible to this login: gh answered 'GraphQL: Could not resolve'",
                    }
                ],
            }
        )
        stub = _Stub(_ok(verb))
        with _patched(self.spaces, stub):
            body = self.client.get("/api/spaces/candidates", params={"repo": "tester/ghost", "owner": "acme"}).json()
        # -Repo is one repository: it takes the place of -Owner, never beside it.
        self.assertEqual(stub.calls, [("NewSpace", ["-Discover", "-AsJson", "-Repo", "tester/ghost"])])
        row = body["repos"][0]
        self.assertEqual(row["visibility"], "UNKNOWN")
        self.assertTrue(row["note"].startswith("not visible to this login"))
        # The verb's argv is a list: nothing is joined into a string a shell could split.
        for _, params in stub.calls:
            self.assertFalse(any("&" in p for p in params))

    def test_the_ceiling_and_more_are_served(self):
        verb = json.dumps({"available": True, "account": "tester", "ceiling": 1000, "more": True, "repos": []})
        body = self.get(_Stub(_ok(verb))).json()
        self.assertEqual((body["ceiling"], body["more"]), (1000, True))
        # An older verb that says nothing of either: no ceiling stated, nothing more.
        old = json.dumps({"available": True, "account": "tester", "repos": []})
        body = self.get(_Stub(_ok(old))).json()
        self.assertEqual((body["ceiling"], body["more"]), (0, False))
        self.assertEqual(self.get(_Stub(_ok(json.dumps({"available": True, "ceiling": "x"})))).json()["ceiling"], 0)

    def test_it_is_a_read(self):
        res = self.client.post("/api/spaces/candidates")
        self.assertEqual(res.status_code, 405)


if __name__ == "__main__":
    unittest.main()
