"""The Studio's Prompts card, its agent half.

GET /api/studio/prompts lists agentic/'s shipped prompts with the index's marks
(agentic/prompts.json: the ways of working, who sends it, the module, what it
drives), and yours beside them -- the hub's agentic/ and this machine's
agenticExtensionPath. GET /api/studio/prompts/{ref} reads one. A shipped prompt of
an add-on that is off is absent (404, not 403); a name outside the folders is a
404. Last changed is git's, linked to its history on GitHub when the clone's
origin is there. Every row, wherever it lives, carries one record: title,
purpose, owner and category.

No network: git runs only against scratch repositories this file makes.

Run:  python -m pytest Tests/test_studio_prompts.py
"""

import base64
import json
import os
import shutil
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
    from agent.core import config
    from agent.studio import prompts
except Exception as exc:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(exc).__name__}: {exc})")

FIXTURE_HUB = PKG_ROOT / "Tests" / "fixtures" / "hub"
INDEX = json.loads((PKG_ROOT / "agentic" / "prompts.json").read_text(encoding="utf-8"))["prompts"]
CONSTS = json.loads((PKG_ROOT / "consts.json").read_text(encoding="utf-8"))
ROUTE = CONSTS["studio"]["promptsRoute"]


class PromptsCase(unittest.TestCase):
    """A scratch copy of the fixture hub, and a config that points at it."""

    features: dict = {}
    extension = ""
    # The one Space, as the fixture hub declares it unless a case says otherwise.
    org = ""
    status = ""
    space_name = ""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.base = base
        self.hub = base / "hub"
        shutil.copytree(FIXTURE_HUB, self.hub)
        default = base / "config.default.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "features": self.features,
                    "promptsRoot": str(self.hub),
                    "agenticExtensionPath": self.extension,
                    "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
                }
            ),
            encoding="utf-8",
        )
        # The fixture hub's hub.json declares 'test' itself (an Azure address,
        # local, named Example) over the shipped entry; a case that wants another
        # address, status or name patches it from this machine's layer, which
        # has the last word.
        patch = {k: v for k, v in (("org", self.org), ("status", self.status), ("name", self.space_name)) if v}
        local = base / "config.local.json"
        local.write_text(json.dumps({"spaces": {"test": patch}} if patch else {}), encoding="utf-8")
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self._patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        self.client = TestClient(app)

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def rows(self) -> dict:
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 200)
        return {p["ref"]: p for p in res.json()["prompts"]}


class TheShippedSet(PromptsCase):
    def test_every_core_prompt_is_listed_with_the_index_marks(self):
        rows = self.rows()
        core = {n for n, e in INDEX.items() if e["module"] == "core"}
        self.assertEqual({r for r, p in rows.items() if p["group"] == "toolkit"}, core)
        for name in core:
            row, entry = rows[name], INDEX[name]
            with self.subTest(name=name):
                self.assertEqual(row["workflows"], entry["workflows"])
                self.assertEqual(row["sender"], entry["sender"])
                self.assertEqual(row["by_hand"], entry["sender"] == "by hand")
                self.assertEqual(row["drives"], entry["drives"])
                self.assertEqual(row["path"], f"agentic/{name}.prompt.md")
                self.assertTrue(row["changed"])

    def test_the_two_the_tools_send_say_so(self):
        rows = self.rows()
        self.assertEqual((rows["pr-review"]["sender"], rows["pr-review"]["by_hand"]), ("AddPRReview", False))
        self.assertFalse(rows["pr-suggest"]["by_hand"])
        self.assertTrue(rows["pr-ship"]["by_hand"])

    def test_a_row_carries_the_whole_file_to_copy_and_its_description(self):
        rows = self.rows()
        text = (PKG_ROOT / "agentic" / "pr-ship.prompt.md").read_text(encoding="utf-8-sig")
        self.assertEqual(rows["pr-ship"]["body"], text)
        self.assertTrue(rows["pr-ship"]["description"].startswith("Ship-it flow, stage 1"))

    def test_every_shipped_row_reads_its_title_and_purpose_from_the_header(self):
        # One header shape (Tests/test_agentic_index.py holds it): the row's purpose line is
        # the frontmatter's description, and its title the one '# ' heading, never the file name.
        for name, row in self.rows().items():
            if row["group"] != "toolkit":
                continue
            with self.subTest(name=name):
                self.assertTrue(row["description"], "no description: the purpose line would be empty")
                self.assertNotEqual(row["title"], name, "no '# ' title: the row fell back to the file name")

    def test_an_add_ons_prompts_are_absent_while_it_is_off(self):
        rows = self.rows()
        for name, entry in INDEX.items():
            if entry["module"] != "core":
                self.assertNotIn(name, rows)
        res = self.client.get(f"{ROUTE}/generate-review")
        self.assertEqual(res.status_code, 404)
        self.assertIn("growth", res.json()["detail"])

    def test_one_prompt_reads_by_its_name(self):
        res = self.client.get(f"{ROUTE}/pr-review")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["name"], "pr-review")
        self.assertIn("{diff}", res.json()["body"])

    def test_a_name_outside_the_folder_is_a_404(self):
        for ref in ("nope", "..%2Fconsts", "README", "prompts.json", "a/b", "yours/nope", "-x"):
            with self.subTest(ref=ref):
                self.assertEqual(self.client.get(f"{ROUTE}/{ref}").status_code, 404)


class WithTheAddOnsOn(PromptsCase):
    features = {"growth": True, "communication": True}

    def test_their_prompts_are_listed(self):
        rows = self.rows()
        self.assertEqual({r for r, p in rows.items() if p["group"] == "toolkit"}, set(INDEX))
        self.assertEqual(rows["manager1on1"]["module"], "communication")
        self.assertEqual(self.client.get(f"{ROUTE}/generate-review").status_code, 200)


class Yours(PromptsCase):
    def setUp(self):
        super().setUp()
        (self.hub / "agentic").mkdir()
        (self.hub / "agentic" / "bench-billing.prompt.md").write_text(
            '---\ndescription: "Reconstruct a week"\n---\n\n# Bench Billing\n', encoding="utf-8"
        )
        (self.hub / "agentic" / "notes.md").write_text("# not a prompt\n", encoding="utf-8")

    def test_the_hubs_own_are_listed_as_yours_for_every_way_of_working(self):
        row = self.rows()["yours/bench-billing"]
        self.assertEqual(
            (row["group"], row["name"], row["path"], row["workflows"], row["overrides"], row["description"]),
            ("yours", "bench-billing", "agentic/bench-billing.prompt.md", [], False, "Reconstruct a week"),
        )
        self.assertNotIn("yours/notes", self.rows())

    def test_one_of_yours_reads_by_its_ref(self):
        res = self.client.get(f"{ROUTE}/yours/bench-billing")
        self.assertEqual(res.status_code, 200)
        self.assertIn("# Bench Billing", res.json()["body"])

    def test_no_hub_folder_lists_the_shipped_set_alone(self):
        shutil.rmtree(self.hub / "agentic")
        self.assertEqual({p["group"] for p in self.rows().values()}, {"toolkit"})


class AnExtensionFolder(PromptsCase):
    extension = "tuned"

    def setUp(self):
        super().setUp()
        (self.hub / "tuned").mkdir()
        (self.hub / "tuned" / "pr-review.prompt.md").write_text("# PR review, tuned\n", encoding="utf-8")
        (self.hub / "agentic").mkdir()
        (self.hub / "agentic" / "pr-review.prompt.md").write_text("# PR review, a hub copy\n", encoding="utf-8")

    def test_a_copy_under_a_shipped_name_runs_instead_and_wins_over_the_hubs(self):
        rows = self.rows()
        row = rows["yours/pr-review"]
        self.assertEqual(
            (row["path"], row["overrides"], row["title"]), ("tuned/pr-review.prompt.md", True, "PR review, tuned")
        )
        # The shipped one is still listed, as ToolKit's.
        self.assertEqual(rows["pr-review"]["group"], "toolkit")


SPACE_REPO = "acme/wasteland"
SPACE_ORG = f"https://github.com/{SPACE_REPO}"
DECK = '---\ndescription: "What a deck must carry"\n---\n\n# Deck contract\n\nBody.\n'
TRAPS = "# Traps\n\nNo frontmatter.\n"


REAL_RUN = subprocess.run


class FakeFolder:
    """``gh api repos/<repo>/contents/<path>`` over one ``agentic/`` folder, the
    shape ``Tests/test_design.py``'s FakeRepo has: ``None`` is a repository with
    no such folder (404); ``fail`` makes every call gh's error. ``git`` (the
    shipped set's history) runs for real: the patch is on ``subprocess.run``."""

    def __init__(self, files: dict[str, str] | None, fail: str = ""):
        self.files = files
        self.fail = fail
        self.calls: list[list[str]] = []

    def _entry(self, name: str) -> dict:
        return {
            "type": "file",
            "name": name,
            "path": f"agentic/{name}",
            "sha": f"sha-{name}",
            "html_url": f"https://github.com/{SPACE_REPO}/blob/main/agentic/{name}",
        }

    def __call__(self, argv, **kw):
        if not argv or argv[0] != "gh":
            return REAL_RUN(argv, **kw)
        self.calls.append(list(argv))
        if self.fail:
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr=self.fail)
        assert argv[:2] == ["gh", "api"], argv
        path = argv[2].split(f"repos/{SPACE_REPO}/contents/", 1)[1]
        if self.files is not None and path == "agentic":
            listing = [self._entry(n) for n in self.files]
            listing.append({"type": "dir", "name": "drafts", "path": "agentic/drafts"})
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(listing), stderr="")
        folder, _, name = path.rpartition("/")
        if self.files is not None and folder == "agentic" and name in self.files:
            row = {
                **self._entry(name),
                "encoding": "base64",
                "content": base64.b64encode(self.files[name].encode()).decode(),
            }
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(row), stderr="")
        return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not Found (HTTP 404)")


class TheSpacesFolder(PromptsCase):
    """The active Space's own agentic/, read through gh behind the Design tab's gate."""

    org = SPACE_ORG
    status = "active"
    space_name = "Wasteland Studio"

    def setUp(self):
        super().setUp()
        prompts.clear_cache()
        design.clear_cache()

    def read(self, fake: FakeFolder, url: str = ROUTE, tier: int = 1, package: str = "johnfrog76/toolkit"):
        with (
            mock.patch.object(design.subprocess, "run", side_effect=fake),
            mock.patch.object(design, "_resolve_tier", return_value=(tier, "")),
            mock.patch.object(prompts, "package_repo", return_value=package),
        ):
            return self.client.get(url)

    def test_the_folder_is_listed_as_the_spaces_group_and_the_response_names_the_space(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK, "traps.prompt.md": TRAPS, "notes.md": "# not one\n"})
        res = self.read(fake)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(
            body["space"], {"slug": "test", "name": "Wasteland Studio", "repo": SPACE_REPO, "isToolkit": False}
        )
        rows = {p["ref"]: p for p in body["prompts"]}
        self.assertEqual([r for r in rows if rows[r]["group"] == "space"], ["space/deck-contract", "space/traps"])
        self.assertNotIn("space/notes", rows)
        row = rows["space/deck-contract"]
        self.assertEqual(
            (row["name"], row["path"], row["workflows"], row["sender"], row["by_hand"], row["module"]),
            ("deck-contract", "agentic/deck-contract.prompt.md", [], "", True, "core"),
        )
        self.assertEqual(row["file_path"], f"https://github.com/{SPACE_REPO}/blob/main/agentic/deck-contract.prompt.md")
        self.assertEqual((row["title"], row["description"]), ("Deck contract", "What a deck must carry"))
        self.assertEqual(row["body"], DECK)
        # The contents read carries no commit: blank, never a guess.
        self.assertEqual((row["changed"], row["history"]), ("", ""))
        # ToolKit's and yours are listed as before, beside them.
        self.assertEqual(rows["pr-ship"]["group"], "toolkit")
        self.assertEqual(body["count"], len(rows))
        # The reads go through gh api contents: the folder, then each file.
        self.assertEqual(fake.calls[0], ["gh", "api", f"repos/{SPACE_REPO}/contents/agentic"])
        self.assertEqual(fake.calls[1], ["gh", "api", f"repos/{SPACE_REPO}/contents/agentic/deck-contract.prompt.md"])

    def test_one_of_the_spaces_reads_by_its_ref(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK})
        res = self.read(fake, f"{ROUTE}/space/deck-contract")
        self.assertEqual(res.status_code, 200)
        self.assertEqual((res.json()["group"], res.json()["body"]), ("space", DECK))
        self.assertEqual(self.read(fake, f"{ROUTE}/space/nope").status_code, 404)

    def test_toolkit_on_itself_serves_is_toolkit_and_no_space_rows(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK})
        for package in (SPACE_REPO, "Acme/Wasteland"):
            with self.subTest(package=package):
                prompts.clear_cache()
                body = self.read(fake, package=package).json()
                self.assertEqual(body["space"]["isToolkit"], True)
                self.assertEqual(body["space"]["repo"], SPACE_REPO)
                self.assertEqual([p for p in body["prompts"] if p["group"] == "space"], [])
        self.assertEqual(fake.calls, [])  # its folder is the shipped set: gh is never asked
        self.assertEqual(self.read(fake, f"{ROUTE}/space/deck-contract", package=SPACE_REPO).status_code, 404)

    def test_a_space_with_no_folder_serves_none_and_no_error(self):
        fake = FakeFolder(None)
        res = self.read(fake)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["space"]["repo"], SPACE_REPO)
        self.assertEqual([p for p in res.json()["prompts"] if p["group"] == "space"], [])
        self.assertEqual(len(fake.calls), 1)

    def test_the_folder_is_read_once_for_the_ttl_and_a_failed_read_is_not_kept(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK})
        self.read(fake)
        n = len(fake.calls)
        self.read(fake)
        self.assertEqual(len(fake.calls), n)
        prompts.clear_cache()
        failing = FakeFolder({"deck-contract.prompt.md": DECK}, fail="gh: HTTP 500 Internal Server Error")
        res = self.read(failing)
        self.assertEqual(res.status_code, 200)
        self.assertEqual([p for p in res.json()["prompts"] if p["group"] == "space"], [])
        self.read(failing)
        self.assertEqual(len(failing.calls), 2)  # asked again: a failure is not cached

    def test_below_tier_1_or_an_owner_grained_address_has_no_repo_and_no_refusal(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK})
        body = self.read(fake, tier=2).json()
        self.assertEqual((body["space"]["repo"], body["space"]["isToolkit"]), ("", False))
        self.assertEqual(fake.calls, [])
        with mock.patch.object(
            design, "load_config", return_value={"org": "https://github.com/acme", "status": "active"}
        ):
            res = self.read(fake)
        self.assertEqual(res.status_code, 200)  # the Design tab's 400 is, here, no third group
        self.assertEqual(res.json()["space"]["repo"], "")


class OneRecordForEveryPrompt(PromptsCase):
    """Title, purpose, owner and category on every row, wherever the prompt lives:
    a shipped one, one of the hub's and one of the Space's, read in one response.
    The owner is worked out from where the file was read; the category is the
    index's for a shipped prompt and the frontmatter's for any other."""

    org = SPACE_ORG
    status = "active"
    space_name = "Wasteland Studio"
    read = TheSpacesFolder.read

    def setUp(self):
        super().setUp()
        prompts.clear_cache()
        design.clear_cache()
        (self.hub / "agentic").mkdir()
        (self.hub / "agentic" / "bench-billing.prompt.md").write_text(
            '---\ntitle: "Bench billing"\ndescription: "Reconstruct a week"\ncategory: Growth\n---\n\n# Heading\n',
            encoding="utf-8",
        )
        (self.hub / "agentic" / "loose.prompt.md").write_text("No frontmatter, no heading.\n", encoding="utf-8")

    def test_the_four_fields_on_a_shipped_a_hub_and_a_space_prompt(self):
        space = '---\ndescription: "What a deck must carry"\ncategory: design\n---\n\n# Deck contract\n'
        fake = FakeFolder({"deck-contract.prompt.md": space, "traps.prompt.md": TRAPS})
        rows = {p["ref"]: p for p in self.read(fake).json()["prompts"]}
        four = lambda r: (r["title"], r["purpose"], r["owner"], r["category"])  # noqa: E731
        ship = (PKG_ROOT / "agentic" / "pr-ship.prompt.md").read_text(encoding="utf-8")
        self.assertEqual(
            four(rows["pr-ship"]),
            (
                "PR Ship -- stage 1 of 2 (draft PR)",
                design.parse_doc(ship, "pr-ship")[1],
                "toolkit",
                INDEX["pr-ship"]["category"],
            ),
        )
        # The hub's: the frontmatter's title over its heading, its category lowercased.
        self.assertEqual(four(rows["yours/bench-billing"]), ("Bench billing", "Reconstruct a week", "yours", "growth"))
        # No frontmatter and no heading: the file name, no purpose, uncategorized.
        self.assertEqual(four(rows["yours/loose"]), ("loose", "", "yours", "uncategorized"))
        # The Space's: owned by the Space that read it, by its slug.
        self.assertEqual(
            four(rows["space/deck-contract"]), ("Deck contract", "What a deck must carry", "test", "design")
        )
        self.assertEqual(four(rows["space/traps"]), ("Traps", "", "test", "uncategorized"))
        # The purpose is the description, which the reading room still reads.
        for row in rows.values():
            with self.subTest(ref=row["ref"]):
                self.assertEqual(row["purpose"], row["description"])

    def test_every_shipped_row_carries_its_index_category(self):
        for name, row in self.rows().items():
            if row["group"] == "toolkit":
                with self.subTest(name=name):
                    self.assertEqual((row["owner"], row["category"]), ("toolkit", INDEX[name]["category"]))

    def test_the_response_carries_the_category_vocabulary_in_its_order(self):
        # The card's category row is drawn in the index's order, so the agent
        # serves the vocabulary rather than the web reading the file itself.
        vocabulary = json.loads((PKG_ROOT / "agentic" / "prompts.json").read_text(encoding="utf-8"))["categories"]
        self.assertEqual(self.read(FakeFolder({})).json()["categories"], vocabulary)

    def test_one_prompt_read_alone_carries_the_same_record(self):
        res = self.read(FakeFolder({"deck-contract.prompt.md": DECK}), f"{ROUTE}/space/deck-contract")
        self.assertEqual((res.json()["owner"], res.json()["category"]), ("test", "uncategorized"))
        mine = self.client.get(f"{ROUTE}/yours/bench-billing").json()
        self.assertEqual((mine["owner"], mine["category"], mine["title"]), ("yours", "growth", "Bench billing"))


class APackageWithNoGit(PromptsCase):
    """A copy of the package installed without .git: no origin to read, so the
    shipped address in consts.json says which repository the package is."""

    org = CONSTS["repository"]["url"]
    status = "active"
    space_name = "Toolkit"

    def setUp(self):
        super().setUp()
        prompts.clear_cache()
        design.clear_cache()
        self.pkg = self.base / "pkg"
        shutil.copytree(PKG_ROOT / "agentic", self.pkg / "agentic")

    def test_the_space_that_is_this_package_reads_as_itself(self):
        fake = FakeFolder({"pr-ship.prompt.md": DECK})
        with (
            mock.patch.object(prompts, "AGENTIC_DIR", self.pkg / "agentic"),
            mock.patch.object(design.subprocess, "run", side_effect=fake),
            mock.patch.object(design, "_resolve_tier", return_value=(1, "")),
        ):
            self.assertEqual(prompts.folder_history(self.pkg / "agentic"), ({}, ""))  # no clone: no origin
            self.assertEqual(prompts.package_repo(), "johnfrog76/toolkit")
            res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(
            body["space"], {"slug": "test", "name": "Toolkit", "repo": "johnfrog76/toolkit", "isToolkit": True}
        )
        self.assertEqual([p for p in body["prompts"] if p["group"] == "space"], [])
        self.assertEqual(fake.calls, [])
        self.assertIn("pr-ship", {p["ref"] for p in body["prompts"]})  # the shipped set still reads from the copy

    def test_an_origin_wins_over_the_shipped_address(self):
        with mock.patch.object(prompts, "_git", return_value="git@github.com:acme/fork.git\n"):
            self.assertEqual(prompts.package_repo(), "acme/fork")
        with mock.patch.object(prompts, "_git", return_value="https://dev.azure.com/acme/_git/kit\n"):
            self.assertEqual(prompts.package_repo(), "johnfrog76/toolkit")  # an origin off GitHub: the shipped address


class ASpaceOffGitHub(PromptsCase):
    """The fixture's own Space: an Azure address, local, named Example. Off
    GitHub the gate answers before gh or the tier is asked, active or not."""

    def test_an_azure_space_has_no_repo_and_the_response_still_names_it(self):
        fake = FakeFolder({"deck-contract.prompt.md": DECK})
        for status in ("", "active"):
            with self.subTest(status=status), mock.patch.object(design.subprocess, "run", side_effect=fake):
                if status:
                    (self.base / "config.local.json").write_text(
                        json.dumps({"spaces": {"test": {"status": status}}}), encoding="utf-8"
                    )
                body = self.client.get(ROUTE).json()
                self.assertEqual(body["space"], {"slug": "test", "name": "Example", "repo": "", "isToolkit": False})
                self.assertEqual([p for p in body["prompts"] if p["group"] == "space"], [])
        self.assertEqual(fake.calls, [])
        self.assertEqual(self.client.get(f"{ROUTE}/space/deck-contract").status_code, 404)


@unittest.skipUnless(shutil.which("git"), "git is not on PATH")
class LastChanged(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name) / "repo"
        (self.repo / "agentic").mkdir(parents=True)
        (self.repo / "agentic" / "a.prompt.md").write_text("# A\n", encoding="utf-8")

        def git(*args):
            subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)

        git("init", "-q")
        git("-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".")
        git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "a")
        self.sha = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.repo, capture_output=True, text=True, check=True
        ).stdout.strip()
        self.git = git

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_clone_on_github_links_the_files_history(self):
        self.git("remote", "add", "origin", "https://github.com/acme/kit.git")
        changes, base = prompts.folder_history(self.repo / "agentic")
        self.assertEqual(changes["a.prompt.md"][1], self.sha)
        self.assertRegex(changes["a.prompt.md"][0], r"^\d{4}-\d{2}-\d{2}$")
        self.assertEqual(
            base.format(sha=self.sha) + "a.prompt.md",
            f"https://github.com/acme/kit/commits/{self.sha}/agentic/a.prompt.md",
        )

    def test_a_clone_elsewhere_has_a_day_and_no_link(self):
        self.git("remote", "add", "origin", "https://dev.azure.com/acme/_git/kit")
        changes, base = prompts.folder_history(self.repo / "agentic")
        self.assertIn("a.prompt.md", changes)
        self.assertEqual(base, "")

    def test_a_folder_outside_any_clone_answers_nothing(self):
        outside = Path(self._tmp.name) / "plain"
        outside.mkdir()
        self.assertEqual(prompts.folder_history(outside), ({}, ""))


if __name__ == "__main__":
    unittest.main()
