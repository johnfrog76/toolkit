"""The Design tab's agent half -- /design on a GitHub Space (Studio S2, D-S11).

Two routes: ``GET /api/design`` lists the product repo's ``design/`` and
``spec/`` through ``agent/ado/repo_read.py`` -- one ``gh api graphql`` call for
the four folders' shape, one more for the texts of blobs never parsed, the
parsed rows kept on disk by blob sha -- and ``GET /api/design/{folder}/{name}``
reads one file through ``gh api repos/{owner}/{repo}/contents/{path}``, or from
the disk by its sha. No network: subprocess is stubbed with a fake repo that
answers both, and the assertions are about the listing, the frontmatter, the
thread line, an empty folder, the gate, and how many times gh is asked.

Run:  python3 -m pytest Tests/test_design.py
"""

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.ado import design
    from agent.app import app
    from agent.core.consts import env_agent_cache_dir
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

REPO = "johnfrog76/toolkit"
ORG = f"https://github.com/{REPO}"

STUDIO_SPEC = """---
description: "Design contract for the Studio: the room where products are made."
---

# The Studio

> GitHub: https://github.com/johnfrog76/toolkit/issues/90

Body.
"""
NOTE = "# A note about the board\n\nNo frontmatter, no thread.\n"
NO_HEADING = "Just prose, and\n## a second-level heading only\n"
# A note the public export has been over: no `> GitHub:` header and no Journey
# `Thread:` line, the shape a note has from NewDesign until MoveDesign threads it.
EXPORTED_NOTE = (
    '---\ndescription: "Exported, no thread"\n---\n\n# Feature: exported\n\n'
    "> **The living card.** Its spec is spec/exported.spec.md.\n\n## Journey\n\n"
    "- 2026-10-04 Design: written as design/exported.md in the repository.\n"
    "- 2026-10-05 Spec: became spec/exported.spec.md in the repository.\n"
)
BINARY_NAME = "diagram.png"


def blob_sha(text: str) -> str:
    """The sha git gives these bytes, as GitHub answers it."""
    data = text.encode()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def _file(path: str, text: str, sha: str) -> dict:
    return {
        "type": "file",
        "name": path.split("/")[-1],
        "path": path,
        "sha": sha,
        "html_url": f"https://github.com/{REPO}/blob/main/{path}",
        "encoding": "base64",
        "content": base64.b64encode(text.encode()).decode(),
    }


def _entry(path: str, sha: str) -> dict:
    return {k: v for k, v in _file(path, "", sha).items() if k not in ("content", "encoding")}


class FakeRepo:
    """gh api over a dict of folders: the GraphQL shape and blob queries the
    listing asks, the contents call the detail asks, and code search. A folder
    that is absent is a null object (GraphQL) or a 404 (contents). A name in
    ``null_text`` is a blob GitHub will not inline: its GraphQL text is null.

    Every call is asserted free of ``&`` (cmd's on Windows), and a GraphQL query
    must arrive as ``-F query=@<file>``, never as argv text."""

    def __init__(self, folders: dict[str, dict[str, str]], fail: str = "", null_text: tuple[str, ...] = ()):
        self.folders = folders
        self.fail = fail
        self.null_text = set(null_text)
        self.calls: list[list[str]] = []
        self.queries: list[str] = []  # each GraphQL query's text
        self.query_files: list[str] = []  # and the file it arrived in

    def kinds(self) -> list[str]:
        """Each call by what it asked: shape, blobs, contents or search."""
        out = []
        for c in self.calls:
            if c[2] == "graphql":
                out.append(c[-1])
            elif c[2] == "-X":
                out.append("search")
            else:
                out.append("contents")
        return out

    def _ok(self, argv, body):
        return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(body), stderr="")

    def __call__(self, argv, **_kw):
        assert "&" not in " ".join(argv), argv
        if self.fail:
            self.calls.append([*argv, "failed"])
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr=self.fail)
        assert argv[:2] == ["gh", "api"], argv
        if argv[2] == "graphql":
            return self.graphql(argv)
        self.calls.append(list(argv))
        if argv[2] == "-X":
            return self.search(argv)
        path = argv[2].split(f"repos/{REPO}/contents/", 1)[1]
        if path in self.folders:
            listing = [_entry(f"{path}/{n}", blob_sha(t)) for n, t in self.folders[path].items()]
            listing.append({"type": "dir", "name": "old", "path": f"{path}/old"})
            return self._ok(argv, listing)
        folder, _, name = path.rpartition("/")
        if folder in self.folders and name in self.folders[folder]:
            text = self.folders[folder][name]
            return self._ok(argv, _file(path, text, blob_sha(text)))
        return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not Found (HTTP 404)")

    def graphql(self, argv):
        assert argv[3] == "-F" and argv[4].startswith("query=@"), argv
        query = Path(argv[4][len("query=@") :]).read_text(encoding="utf-8")
        self.queries.append(query)
        self.query_files.append(argv[4][len("query=@") :])
        fields = {
            argv[i + 1].split("=", 1)[0]: argv[i + 1].split("=", 1)[1]
            for i in range(3, len(argv) - 1)
            if argv[i] in ("-f", "-F")
        }
        assert f"{fields['owner']}/{fields['name']}" == REPO, fields
        by_sha = {blob_sha(t): (n, t) for files in self.folders.values() for n, t in files.items()}
        if "object(expression:" in query:
            self.calls.append([*argv, "shape"])
            with_text = "... on Blob" in query
            repo: dict = {"url": f"https://github.com/{REPO}", "defaultBranchRef": {"name": "main"}}
            for key, value in fields.items():
                if not re.fullmatch(r"f\d+", key):
                    continue
                folder = value.removeprefix("HEAD:")
                if folder not in self.folders:
                    repo[key] = None
                    continue
                entries = []
                for n, t in self.folders[folder].items():
                    obj = {"text": None if n in self.null_text else t} if with_text else {}
                    entries.append({"name": n, "type": "blob", "oid": blob_sha(t), "object": obj})
                entries.append({"name": "old", "type": "tree", "oid": "0" * 40, "object": {}})
                repo[key] = {"entries": entries}
            return self._ok(argv, {"data": {"repository": repo}})
        self.calls.append([*argv, "blobs"])
        repo = {}
        for alias, sha in re.findall(r'(b\d+): object\(oid: "([0-9a-f]+)"\)', query):
            name, text = by_sha.get(sha, ("", None))
            repo[alias] = None if text is None else {"text": None if name in self.null_text else text}
        return self._ok(argv, {"data": {"repository": repo}})

    def search(self, argv):
        """``gh api -X GET -H <accept> search/code -f q=<words> repo:<r> path:<root>
        -F per_page=50``: the files under that root whose text carries every
        word, with a fragment. The query travels as a field, never in the URL
        (an `&` there is cmd's on Windows)."""
        assert argv[2:4] == ["-X", "GET"] and argv[4] == "-H", argv
        assert argv[5].startswith("Accept: application/vnd.github.text-match+json"), argv
        assert argv[6] == "search/code" and "&" not in " ".join(argv), argv
        fields = {
            argv[i + 1].split("=", 1)[0]: argv[i + 1].split("=", 1)[1]
            for i in range(len(argv) - 1)
            if argv[i] in ("-f", "-F")
        }
        assert fields.get("per_page") == "50", argv
        q = fields["q"]
        terms = q.split()
        root = next(t[len("path:") :] for t in terms if t.startswith("path:"))
        words = [t for t in terms if not t.startswith(("path:", "repo:"))]
        items = []
        for folder, files in self.folders.items():
            if folder.split("/")[0] != root:
                continue
            for name, text in files.items():
                low = text.lower()
                if all(w.lower() in low for w in words):
                    line = next((ln for ln in text.splitlines() if any(w.lower() in ln.lower() for w in words)), "")
                    items.append(
                        {
                            "path": f"{folder}/{name}",
                            "name": name,
                            "html_url": f"https://github.com/{REPO}/blob/main/{folder}/{name}",
                            "text_matches": [{"fragment": f"...\n{line}\n..."}],
                        }
                    )
        return subprocess.CompletedProcess(
            argv, 0, stdout=json.dumps({"total_count": len(items), "items": items}), stderr=""
        )


class TheListing(unittest.TestCase):
    def setUp(self):
        design.clear_cache()

    def _list(self, fake: FakeRepo):
        with mock.patch.object(design.subprocess, "run", side_effect=fake):
            return design.list_design(REPO)

    def test_note_first_spec_beside_each_by_name(self):
        fake = FakeRepo(
            {
                "spec": {"toolkit-studio.spec.md": STUDIO_SPEC, BINARY_NAME: "x"},
                "design": {"board-note.md": NOTE, "a-prose.md": NO_HEADING},
            }
        )
        resp = self._list(fake)
        self.assertEqual(
            [(d.folder, d.name) for d in resp.items],
            [
                ("design", "a-prose.md"),
                ("design", "board-note.md"),
                ("spec", "toolkit-studio.spec.md"),
            ],
        )
        self.assertIsNone(resp.reason)
        self.assertEqual(resp.repo, REPO)

    def test_title_description_and_thread(self):
        resp = self._list(
            FakeRepo(
                {
                    "spec": {"toolkit-studio.spec.md": STUDIO_SPEC},
                    "design": {"board-note.md": NOTE, "a-prose.md": NO_HEADING},
                }
            )
        )
        by = {d.name: d for d in resp.items}
        spec = by["toolkit-studio.spec.md"]
        self.assertEqual(spec.title, "The Studio")
        self.assertEqual(spec.description, "Design contract for the Studio: the room where products are made.")
        self.assertEqual(spec.thread, "https://github.com/johnfrog76/toolkit/issues/90")
        self.assertEqual(spec.thread_number, 90)
        self.assertEqual(spec.thread_repo, REPO)
        self.assertEqual(spec.path, "spec/toolkit-studio.spec.md")
        self.assertTrue(spec.url.endswith("/blob/main/spec/toolkit-studio.spec.md"))
        note = by["board-note.md"]
        self.assertEqual(
            (note.title, note.description, note.thread, note.thread_number), ("A note about the board", "", "", None)
        )
        # no `# ` heading: the file's name is its title
        self.assertEqual(by["a-prose.md"].title, "a-prose.md")

    def test_an_exported_note_with_no_thread_lines_still_parses(self):
        resp = self._list(
            FakeRepo(
                {
                    "design": {"exported.md": EXPORTED_NOTE},
                    "spec": {"exported.spec.md": "# Exported (spec)\n"},
                }
            )
        )
        by = {d.name: d for d in resp.items}
        note = by["exported.md"]
        self.assertEqual(
            (note.title, note.description, note.thread, note.thread_number, note.thread_repo),
            ("Feature: exported", "Exported, no thread", "", None, ""),
        )
        self.assertEqual(by["exported.spec.md"].title, "Exported (spec)")
        self.assertEqual(by["exported.spec.md"].thread, "")
        # the lifecycle's reader says the same of the file by itself
        doc = design.parse_design_doc(EXPORTED_NOTE, "design/exported.md")
        self.assertEqual((doc.kind, doc.title, doc.thread, doc.thread_number), ("note", "Feature: exported", "", None))
        # and a thread line that is there is still read: only the export drops them
        threaded = EXPORTED_NOTE.replace("# Feature: exported\n", f"# Feature: exported\n\n> GitHub: {ORG}/issues/7\n")
        self.assertEqual(design.parse_doc(threaded, "x.md")[2:4], (f"{ORG}/issues/7", 7))

    def test_a_folder_that_does_not_exist_is_an_empty_list(self):
        resp = self._list(FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}}))
        self.assertEqual([d.folder for d in resp.items], ["spec"])
        self.assertIsNone(resp.reason)
        design.clear_cache()
        resp = self._list(FakeRepo({}))
        self.assertEqual(resp.items, [])
        self.assertIsNone(resp.reason)

    def test_a_cold_listing_is_one_graphql_call_for_the_four_folders(self):
        # The four folders (L2), in reading order: each root, then its archive --
        # asked as fields, the query in a file, and every text inline because
        # nothing has been parsed yet.
        fake = FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}})
        self._list(fake)
        self.assertEqual(fake.kinds(), ["shape"])
        call = fake.calls[0]
        self.assertEqual(call[:4], ["gh", "api", "graphql", "-F"])
        self.assertTrue(call[4].startswith("query=@"))
        fields = [call[i + 1] for i in range(4, len(call) - 1) if call[i] in ("-f", "-F")]
        self.assertEqual(
            fields,
            [
                "owner=johnfrog76",
                "name=toolkit",
                "f0=HEAD:design",
                "f1=HEAD:design/archive",
                "f2=HEAD:spec",
                "f3=HEAD:spec/archive",
            ],
        )
        # The query lived in a temporary file, gone once gh answered.
        self.assertFalse(Path(fake.query_files[0]).exists())
        self.assertIn("... on Blob { text }", fake.queries[0])

    def test_the_listing_is_cached_for_its_ttl_and_its_rows_on_disk(self):
        fake = FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}})
        first = self._list(fake)
        self._list(fake)
        self.assertEqual(fake.kinds(), ["shape"])  # within the TTL: no gh at all
        design._list_cache.clear()
        again = self._list(fake)
        # Past it: the shape again, and the text from nowhere -- its row is on disk.
        self.assertEqual(fake.kinds(), ["shape", "shape"])
        self.assertEqual(again.model_dump(), first.model_dump())

    @staticmethod
    def _notes(n: int, prefix: str = "n") -> dict[str, dict[str, str]]:
        half = n // 2
        return {
            "design": {f"{prefix}{i:03}.md": f"# Note {prefix}{i}\n" for i in range(half)},
            "design/archive": {f"{prefix}{i:03}.md": f"# Old note {prefix}{i}\n" for i in range(half, n)},
        }

    def _own_cache(self):
        """A cache of its own for one subtest: the fixture's is per test."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return mock.patch.dict(os.environ, {env_agent_cache_dir(): tmp.name})

    def test_the_number_of_gh_calls_does_not_grow_with_the_number_of_notes(self):
        for n in (3, 60, 190):
            with self.subTest(n=n), self._own_cache():
                design.clear_cache()
                folders = self._notes(n)
                cold = FakeRepo(folders)
                resp = self._list(cold)
                self.assertEqual(len(resp.items), n)
                self.assertEqual(cold.kinds(), ["shape"])  # cold: one call, every text inline
                design.clear_cache()  # a restart: the memory is gone, the disk is not
                warm = FakeRepo(folders)
                self.assertEqual(self._list(warm).model_dump(), resp.model_dump())
                self.assertEqual(warm.kinds(), ["shape"])
                # One note changed: the shape, and one ask for that one text.
                design.clear_cache()
                folders["design"]["n000.md"] = "# Note n0, edited\n"
                edited = FakeRepo(folders)
                self.assertEqual(self._list(edited).items[0].title, "Note n0, edited")
                self.assertEqual(edited.kinds(), ["shape", "blobs"])

    def test_new_texts_are_asked_for_together_a_hundred_at_a_time(self):
        # The cache holds rows already, so the shape is asked without text and
        # the new blobs come in one aliased query per hundred.
        self._list(FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}}))
        for n, asks in ((3, 1), (100, 1), (101, 2), (190, 2)):
            with self.subTest(n=n):
                design.clear_cache()
                fake = FakeRepo(self._notes(n, prefix=f"c{n}-"))
                self.assertEqual(len(self._list(fake).items), n)
                self.assertEqual(fake.kinds(), ["shape"] + ["blobs"] * asks)
                self.assertNotIn("... on Blob", fake.queries[0])  # names and shas alone

    def test_an_unchanged_sha_is_never_fetched_again_by_a_new_process(self):
        folders = {
            "design": {"pair.md": _front(ID_A, "The pair") + "# Feature: the pair\n"},
            "spec": {"pair.spec.md": _front(ID_A) + "# Pair (spec)\n"},
        }
        self._list(FakeRepo(folders))
        root = Path(__file__).resolve().parent.parent
        code = (
            "import json, sys\n"
            "from unittest import mock\n"
            "from test_design import FakeRepo, REPO\n"
            "from agent.ado import design\n"
            "fake = FakeRepo(json.loads(sys.argv[1]))\n"
            "with mock.patch.object(design.subprocess, 'run', side_effect=fake):\n"
            "    resp = design.list_design(REPO)\n"
            "print(json.dumps({'kinds': fake.kinds(), 'titles': [d.title for d in resp.designs]}))\n"
        )
        env = dict(os.environ, PYTHONPATH=os.pathsep.join([str(root), str(root / "Tests")]))
        child = subprocess.run(
            [sys.executable, "-c", code, json.dumps(folders)],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(root),
            timeout=120,
            check=False,
        )
        self.assertEqual(child.returncode, 0, child.stderr)
        answer = json.loads(child.stdout.strip().splitlines()[-1])
        self.assertEqual(answer, {"kinds": ["shape"], "titles": ["Feature: the pair"]})

    def test_a_blob_with_no_inline_text_is_read_by_the_contents_call_alone(self):
        folders = {"design": {"big.md": "# Too big to inline\n", "small.md": "# Small\n"}}
        cold = FakeRepo(folders, null_text=("big.md",))
        resp = self._list(cold)
        self.assertEqual([d.title for d in resp.items], ["Too big to inline", "Small"])
        # Cold: the shape carried every text it could; the null one is the contents call, once.
        self.assertEqual(cold.kinds(), ["shape", "contents"])
        self.assertEqual(cold.calls[1], ["gh", "api", f"repos/{REPO}/contents/design/big.md"])
        # Kept like any other row: the next read asks for nothing.
        design.clear_cache()
        warm = FakeRepo(folders, null_text=("big.md",))
        self._list(warm)
        self.assertEqual(warm.kinds(), ["shape"])
        # Warm with a new big note: the batch first, then the contents call for it.
        design.clear_cache()
        folders["design"]["bigger.md"] = "# Bigger still\n"
        newer = FakeRepo(folders, null_text=("big.md", "bigger.md"))
        self.assertEqual({d.name: d.title for d in self._list(newer).items}["bigger.md"], "Bigger still")
        self.assertEqual(newer.kinds(), ["shape", "blobs", "contents"])

    def test_the_structure_says_which_roots_exist(self):
        self.assertEqual(
            self._list(FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}})).structure.model_dump(),
            {"design": False, "spec": True},
        )
        design.clear_cache()
        self.assertEqual(self._list(FakeRepo({})).structure.model_dump(), {"design": False, "spec": False})
        design.clear_cache()
        self.assertEqual(
            self._list(FakeRepo({"design": {}, "spec": {}})).structure.model_dump(), {"design": True, "spec": True}
        )

    def test_a_readme_in_a_design_folder_is_not_a_design_and_is_not_counted(self):
        resp = self._list(FakeRepo({"design": {"README.md": "# Index\n", "board-note.md": NOTE}}))
        self.assertEqual([d.name for d in resp.items], ["board-note.md"])
        self.assertEqual([n.path for n in resp.notShown], ["design/board-note.md"])

    def test_gh_not_answering_is_a_reason(self):
        resp = self._list(FakeRepo({}, fail="gh: To get started with GitHub CLI, please run:  gh auth login"))
        self.assertEqual(resp.items, [])
        self.assertIn("gh auth login", resp.reason)
        self.assertIn(REPO, resp.reason)


class TheAgentCache(unittest.TestCase):
    """Where the rows and bodies go (docs/CONFIGURATION.md, "The agent's
    cache"): the override when it is set, else the platform's user cache folder
    -- never the hub, never the package."""

    def test_the_override_wins_and_each_platform_has_its_folder(self):
        from agent.core import disk_cache

        self.assertEqual(disk_cache.cache_root(), Path(os.environ[env_agent_cache_dir()]))
        home = Path("/home/someone")
        rows = [
            (
                "Windows",
                {"LOCALAPPDATA": "C:/Users/someone/AppData/Local"},
                Path("C:/Users/someone/AppData/Local/ToolKit/Cache"),
            ),
            ("Darwin", {}, home / "Library" / "Caches" / "ToolKit"),
            ("Linux", {"XDG_CACHE_HOME": "/xdg"}, Path("/xdg/toolkit")),
            ("Linux", {}, home / ".cache" / "toolkit"),
        ]
        for system, env, expected in rows:
            with self.subTest(system=system, env=env):
                clean = {
                    k: v
                    for k, v in os.environ.items()
                    if k not in (env_agent_cache_dir(), "LOCALAPPDATA", "XDG_CACHE_HOME")
                }
                with (
                    mock.patch.dict(os.environ, {**clean, **env}, clear=True),
                    mock.patch.object(disk_cache.platform, "system", return_value=system),
                    mock.patch.object(disk_cache.Path, "home", return_value=home),
                ):
                    root = disk_cache.cache_root()
                self.assertEqual(root, expected)
                self.assertNotIn(Path(__file__).resolve().parent.parent, root.parents)

    def test_a_key_is_a_plain_name_and_a_miss_is_none(self):
        from agent.core import disk_cache

        self.assertIsNone(disk_cache.cache_path("rows", "../escape.json"))
        self.assertIsNone(disk_cache.cache_path("bodies", ""))
        self.assertIsNone(disk_cache.get_text("bodies", "0" * 40))
        self.assertTrue(disk_cache.put_text("a\r\nb\n", "bodies", "0" * 40))
        self.assertEqual(disk_cache.get_text("bodies", "0" * 40), "a\r\nb\n")  # the bytes, endings kept
        self.assertTrue(disk_cache.put_json({"rows": {}}, "rows", "x-1.json"))
        self.assertEqual(disk_cache.get_json("rows", "x-1.json"), {"rows": {}})


class TheParser(unittest.TestCase):
    ROWS = [
        # text, name -> title, description, thread number
        ("# Title\n", "x.md", ("Title", "", None)),
        ("---\ndescription: one line\n---\n# T\n", "x.md", ("T", "one line", None)),
        ("---\ntitle: not read\n---\nno heading\n", "x.md", ("x.md", "", None)),
        ("# T\n> GitHub: https://github.com/o/r/issues/7\n", "x.md", ("T", "", 7)),
        ("# T\n> GitHub: https://github.com/o/r/pull/7\n", "x.md", ("T", "", None)),
        ("## Not a title\n# Deep in the body\n", "x.md", ("x.md", "", None)),  # #147: not a title
        ("---\r\ndescription: 'crlf'\r\n---\r\n# CRLF\r\n", "x.md", ("CRLF", "crlf", None)),
    ]

    def test_the_table(self):
        for text, name, (title, desc, num) in self.ROWS:
            got = design.parse_doc(text, name)
            self.assertEqual((got[0], got[1], got[3]), (title, desc, num), text)


TITLES = Path(__file__).parent / "fixtures" / "design" / "titles.json"


class TheTitleRule(unittest.TestCase):
    """How a note's or a spec's title is read, over the ONE table both halves
    assert (Tests/fixtures/design/titles.json; tkTestToolkit -Design is the
    CLI's side), row for row -- through parse_doc (a hub note, a doc) and
    through the repo listing's row (design_fields, then design_doc), for a
    note in design/ and a spec in spec/ alike."""

    def test_every_row(self):
        table = json.loads(TITLES.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["rows"]), 4)
        for row in table["rows"]:
            with self.subTest(row["name"]):
                text = ("\r\n" if row["crlf"] else "\n").join(row["lines"]) + "\n"
                self.assertEqual(design.parse_doc(text, row["file"])[0], row["expected"])
                folder = "spec" if row["file"].endswith(".spec.md") else "design"
                doc = design.parse_design_doc(text, f"{folder}/{row['file']}")
                self.assertEqual(doc.title, row["expected"])


FIXTURE = Path(__file__).parent / "fixtures" / "design" / "states.json"
ID_A = "aaaaaaaa-0000-4000-8000-000000000001"
ID_B = "aaaaaaaa-0000-4000-8000-000000000002"
ID_C = "aaaaaaaa-0000-4000-8000-000000000003"
ID_D = "aaaaaaaa-0000-4000-8000-000000000004"
ID_E = "aaaaaaaa-0000-4000-8000-000000000005"


def _front(doc_id: str, description: str = "") -> str:
    desc = f'description: "{description}"\n' if description else ""
    return f"---\nid: {doc_id}\n{desc}---\n\n"


class TheStateRule(unittest.TestCase):
    """design_state over the ONE table both halves assert (Tests/fixtures/design/
    states.json; tkTestToolkit -Design is the CLI's side), row for row."""

    def test_every_row(self):
        table = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["rows"]), 7)
        for row in table["rows"]:
            with self.subTest(row["name"]):
                note_text = "# N\n\n" + "\n".join(row["noteLines"]) + "\n"
                spec_text = "# S\n\n" + "\n".join(row["specLines"]) + "\n"
                got = design.design_state(row["note"], row["spec"], note_text, spec_text)
                e = row["expected"]
                self.assertEqual(
                    got,
                    {
                        "state": e["state"],
                        "outcome": e["outcome"] or "",
                        "mismatch": e["mismatch"],
                        "closed": e["closed"],
                    },
                )


class TheGrouping(unittest.TestCase):
    """GET /api/design's new shape (L2): designs grouped by id with their state,
    the files not shown with a reason, and the words of a row."""

    def setUp(self):
        design.clear_cache()

    def _list(self, folders: dict) -> design.DesignListResponse:
        with mock.patch.object(design.subprocess, "run", side_effect=FakeRepo(folders)):
            return design.list_design(REPO)

    def test_the_four_folders_group_by_id_in_road_order(self):
        resp = self._list(
            {
                "design": {
                    "pair.md": _front(ID_A, "The pair's one line")
                    + "# Feature: the pair\n\n> GitHub: https://github.com/o/r/issues/7\n",
                    "alone.md": _front(ID_B) + "# A note alone\n",
                    "left.md": _front(ID_E) + "# Left behind\n",
                    "unstamped.md": "# No id here\n",
                },
                "design/archive": {
                    "dropped.md": _front(ID_C)
                    + "# An idea that never made it\n\n**Closed:** 2026-11-20\n**Outcome:** dropped\n"
                },
                "spec": {"pair.spec.md": _front(ID_A, "not the row's line") + "# Pair (spec)\n"},
                "spec/archive": {
                    "built.spec.md": _front(ID_D, "Built and documented")
                    + "# Built (spec)\n\n> Docs: docs/hub/built.md\n\n**Closed:** 2026-10-01\n",
                    "left.spec.md": _front(ID_E) + "# Left (spec)\n\n**Closed:** 2026-10-02\n",
                },
            }
        )
        self.assertIsNone(resp.reason)
        self.assertEqual(
            [(d.state, d.title) for d in resp.designs],
            [
                ("Design", "A note alone"),
                ("Spec", "Feature: the pair"),
                ("Complete", "Built (spec)"),
                ("Complete", "Left behind"),
                ("Archived", "An idea that never made it"),
            ],
        )
        by = {d.id: d for d in resp.designs}
        pair = by[ID_A]
        self.assertEqual(
            (pair.short, pair.description, pair.thread_number, pair.thread_repo),
            ("aaaaaaaa", "The pair's one line", 7, "o/r"),
        )
        self.assertEqual(
            (pair.note.path, pair.spec.path, pair.closed, pair.mismatch),
            ("design/pair.md", "spec/pair.spec.md", "", ""),
        )
        self.assertEqual(
            (pair.note.kind, pair.note.archived, pair.spec.kind, pair.spec.archived), ("note", False, "spec", False)
        )
        dropped = by[ID_C]
        self.assertEqual(
            (dropped.outcome, dropped.closed, dropped.note.archived, dropped.spec),
            ("dropped", "2026-11-20", True, None),
        )
        built = by[ID_D]
        self.assertEqual(
            (built.description, built.docs, built.closed, built.note),
            ("Built and documented", "docs/hub/built.md", "2026-10-01", None),
        )
        left = by[ID_E]
        self.assertEqual(left.state, "Complete")
        self.assertIn("left behind in design/", left.mismatch)
        self.assertEqual([(n.path, n.reason) for n in resp.notShown], [("design/unstamped.md", "no id")])
        self.assertEqual(resp.structure.model_dump(), {"design": True, "spec": True})

    def test_two_notes_with_one_id_are_a_conflict_and_neither_is_shown(self):
        resp = self._list({"design": {"a.md": _front(ID_A) + "# A\n", "b.md": _front(ID_A) + "# B\n"}})
        self.assertEqual(resp.designs, [])
        self.assertEqual(
            [(n.path, n.reason) for n in resp.notShown],
            [("design/a.md", "2 notes carry the id aaaaaaaa"), ("design/b.md", "2 notes carry the id aaaaaaaa")],
        )

    def test_an_id_outside_the_contracts_shape_is_no_id(self):
        resp = self._list(
            {
                "design": {
                    "a.md": "---\nid: 12\n---\n# A\n",
                    "b.md": "---\nid: AAAAAAAA-0000-4000-8000-000000000001\n---\n# B\n",
                }
            }
        )
        self.assertEqual([n.reason for n in resp.notShown], ["no id", "no id"])

    def test_a_note_archived_before_its_spec_is_still_a_spec_and_says_so(self):
        resp = self._list(
            {
                "design/archive": {"x.md": _front(ID_A) + "# X\n\n**Closed:** 2026-11-20\n"},
                "spec": {"x.spec.md": _front(ID_A) + "# X (spec)\n"},
            }
        )
        d = resp.designs[0]
        self.assertEqual((d.state, d.closed), ("Spec", ""))
        self.assertIn("archived before its spec", d.mismatch)

    def test_a_live_note_with_an_outcome_line_reads_as_design_with_none(self):
        resp = self._list({"design": {"x.md": _front(ID_A) + "# X\n\n**Outcome:** shipped\n"}})
        self.assertEqual((resp.designs[0].state, resp.designs[0].outcome), ("Design", ""))


class TheSearch(unittest.TestCase):
    """Search inside a repo (L2b): the box's words through gh's code search,
    scoped to each root, mapped to the designs the files belong to."""

    FOLDERS = {
        "design": {
            "pair.md": _front(ID_A, "The pair") + "# Feature: the pair\n\nThe lounge is an ambient room.\n",
            "alone.md": _front(ID_B) + "# A note alone\n\nNothing ambient here.\n",
            "unstamped.md": "# No id here\n\nAn ambient room too.\n",
        },
        "design/archive": {
            "dropped.md": _front(ID_C)
            + "# Dropped\n\nambient, dropped\n\n**Closed:** 2026-11-20\n**Outcome:** dropped\n"
        },
        "spec": {"pair.spec.md": _front(ID_A) + "# Pair (spec)\n\nThe contract for the ambient room.\n"},
    }

    def setUp(self):
        design.clear_cache()
        self.fake = FakeRepo(self.FOLDERS)

    def _search(self, q: str) -> design.DesignSearchResponse:
        with mock.patch.object(design.subprocess, "run", side_effect=self.fake):
            return design.search_design(REPO, q)

    def test_the_words_rule(self):
        self.assertEqual(design.search_words("  Ambient ROOM "), ["ambient", "room"])
        self.assertEqual(
            design.match_words("# T\n\nThe Lounge is an ambient room.\n", ["ambient", "lounge"]),
            "The Lounge is an ambient room.",
        )
        self.assertIsNone(design.match_words("# T\n\nambient only\n", ["ambient", "lounge"]))
        self.assertIsNone(design.match_words("anything", []))

    def test_hits_name_the_design_its_state_and_the_line_in_road_order(self):
        resp = self._search("ambient")
        self.assertTrue(resp.available)
        self.assertEqual(resp.repo, REPO)
        # Road order, a file with no id last: it is still a hit, so the search never hides what it found.
        self.assertEqual(
            [(h.path, h.state, h.title) for h in resp.hits],
            [
                ("design/alone.md", "Design", "A note alone"),
                ("design/pair.md", "Spec", "Feature: the pair"),
                ("spec/pair.spec.md", "Spec", "Feature: the pair"),
                ("design/archive/dropped.md", "Archived", "Dropped"),
                ("design/unstamped.md", "", "No id here"),
            ],
        )
        by = {h.path: h for h in resp.hits}
        self.assertEqual(by["design/pair.md"].line, "The lounge is an ambient room.")
        self.assertEqual((by["design/pair.md"].state, by["design/pair.md"].id), ("Spec", ID_A))
        self.assertEqual(
            (by["design/archive/dropped.md"].state, by["design/archive/dropped.md"].archived), ("Archived", True)
        )
        self.assertEqual((by["design/unstamped.md"].state, by["design/unstamped.md"].title), ("", "No id here"))
        self.assertEqual([h.state for h in resp.hits], ["Design", "Spec", "Spec", "Archived", ""])
        self.assertEqual(resp.note, design.CODE_SEARCH_NOTE)

    def test_every_word_must_match_and_the_search_is_scoped_to_each_root(self):
        resp = self._search("ambient lounge")
        self.assertEqual([h.path for h in resp.hits], ["design/pair.md"])
        searches = [c for c in self.fake.calls if c[2] == "-X"]
        self.assertEqual(len(searches), 2)
        self.assertEqual(searches[0][8], f"q=ambient lounge repo:{REPO} path:design")
        self.assertEqual(searches[1][8], f"q=ambient lounge repo:{REPO} path:spec")
        self.assertEqual(searches[0][6], "search/code")

    def test_no_words_asks_nothing(self):
        resp = self._search("   ")
        self.assertEqual(resp.hits, [])
        self.assertEqual([c for c in self.fake.calls if c[2] == "-X"], [])

    def test_gh_not_answering_is_a_reason_not_an_error(self):
        with mock.patch.object(design.subprocess, "run", side_effect=self.fake):
            design.list_design(REPO)  # the listing is cached
        failing = FakeRepo(self.FOLDERS, fail="gh: API rate limit exceeded for search")
        with mock.patch.object(design.subprocess, "run", side_effect=failing):
            resp = design.search_design(REPO, "ambient")
        self.assertFalse(resp.available)
        self.assertIn("rate limit", resp.reason)
        self.assertEqual(resp.hits, [])
        self.assertEqual(resp.note, design.CODE_SEARCH_NOTE)


class TheRoutes(unittest.TestCase):
    """The gate: GitHub only, Tier 1 only, and the address must name a repo."""

    def setUp(self):
        design.clear_cache()
        self.client = TestClient(app)

    def _get(self, url: str, org: str, tier: int = 1, fake: FakeRepo | None = None):
        fake = fake or FakeRepo({"spec": {"toolkit-studio.spec.md": STUDIO_SPEC}})
        with (
            mock.patch.object(design, "load_config", return_value={"org": org, "status": "active"}),
            mock.patch.object(design, "_resolve_tier", return_value=(tier, "")),
            mock.patch.object(design.subprocess, "run", side_effect=fake),
        ):
            return self.client.get(url)

    def test_a_repo_grained_github_space_lists(self):
        res = self._get("/api/design", ORG)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertTrue(body["supported"])
        self.assertEqual([i["name"] for i in body["items"]], ["toolkit-studio.spec.md"])

    def test_an_owner_grained_address_is_refused_with_a_sentence(self):
        res = self._get("/api/design", "https://github.com/johnfrog76")
        self.assertEqual(res.status_code, 400)
        self.assertIn("names a GitHub owner, not a repository", res.json()["detail"])

    def test_an_ado_space_or_tier_2_is_not_supported(self):
        self.assertFalse(self._get("/api/design", "https://dev.azure.com/acme").json()["supported"])
        self.assertFalse(self._get("/api/design", ORG, tier=2).json()["supported"])
        self.assertFalse(self._get("/api/design", "").json()["supported"])

    def test_one_document_reads_with_its_body(self):
        res = self._get("/api/design/spec/toolkit-studio.spec.md", ORG)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["title"], "The Studio")
        self.assertEqual(body["thread_number"], 90)
        self.assertTrue(body["body"].startswith("---\ndescription:"))

    def test_a_missing_document_is_404_and_a_bad_path_never_reaches_gh(self):
        self.assertEqual(self._get("/api/design/spec/nope.md", ORG).status_code, 404)
        fake = FakeRepo({})
        for url in (
            "/api/design/issues/x.md",
            "/api/design/spec/x.png",
            "/api/design/spec/..md",
            "/api/design/spec/old/x.md",
            "/api/design/design/archive/sub/x.md",
            "/api/design/x.md",
        ):
            self.assertEqual(self._get(url, ORG, fake=fake).status_code, 404, url)
        self.assertEqual(fake.calls, [])

    def test_an_archived_document_reads_by_its_path_and_knows_it_is_archived(self):
        text = (
            "---\nid: aaaaaaaa-0000-4000-8000-000000000001\n---\n\n# Old\n\n"
            "**Closed:** 2026-11-20\n**Outcome:** shipped\n"
        )
        res = self._get("/api/design/design/archive/old.md", ORG, fake=FakeRepo({"design/archive": {"old.md": text}}))
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(
            (body["path"], body["folder"], body["kind"], body["archived"]),
            ("design/archive/old.md", "design/archive", "note", True),
        )
        self.assertEqual(
            (body["id"], body["closed"], body["outcome"]),
            ("aaaaaaaa-0000-4000-8000-000000000001", "2026-11-20", "shipped"),
        )
        self.assertTrue(body["body"].startswith("---\nid:"))

    def test_search_inside_is_its_own_route_before_the_document_read(self):
        fake = FakeRepo(TheSearch.FOLDERS)
        res = self._get("/api/design/search?q=ambient%20lounge", ORG, fake=fake)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual((body["supported"], body["available"], body["query"]), (True, True, "ambient lounge"))
        self.assertEqual([h["path"] for h in body["hits"]], ["design/pair.md"])
        self.assertEqual(body["hits"][0]["line"], "The lounge is an ambient room.")
        self.assertIn("default branch only", body["note"])
        # Not supported on an ADO Space, and never asked of gh.
        quiet = FakeRepo({})
        self.assertFalse(
            self._get("/api/design/search?q=x", "https://dev.azure.com/acme", fake=quiet).json()["supported"]
        )
        self.assertEqual(quiet.calls, [])

    def test_the_list_carries_the_grouped_shape(self):
        body = self._get("/api/design", ORG).json()
        self.assertEqual(set(body) >= {"items", "designs", "notShown", "structure"}, True)
        self.assertEqual(body["structure"], {"design": False, "spec": True})
        # The fixture spec has no id, so it is counted and not shown.
        self.assertEqual(body["designs"], [])
        self.assertEqual(body["notShown"], [{"path": "spec/toolkit-studio.spec.md", "reason": "no id"}])

    def test_a_row_carries_the_active_spaces_cards_that_name_it_read_fresh(self):
        """Toolkit card C3: a repo design's row lists the active Space's
        cards whose `> Design:` line carries its id -- current/ first, then
        archive/ as Done -- read on every request over the cached listing."""
        import tempfile

        doc_id = "53913fc8-08cc-4b3f-9da7-40050b690010"
        spec = f"---\nid: {doc_id}\n---\n\n# Toolkit card\n"
        line = f"> Design: [Toolkit card](https://github.com/{REPO}/blob/HEAD/spec/toolkit-card.spec.md) {doc_id}"
        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp) / "toolkit"
            (space / "current").mkdir(parents=True)
            (space / "archive").mkdir()
            (space / "current" / "157-the-bindings.prompt.md").write_text(
                f"# Bug 157: The bindings\n\n{line}\n", encoding="utf-8"
            )
            (space / "archive" / "155-the-cover.prompt.md").write_text(
                f"# Bug 155: The cover\n\n{line}\n", encoding="utf-8"
            )
            (space / "current" / "158-unrelated.prompt.md").write_text("# Bug 158: Unrelated\n", encoding="utf-8")
            fake = FakeRepo({"spec": {"toolkit-card.spec.md": spec}})
            with mock.patch.object(design, "resolve_dirs", return_value=(space / "current", space / "archive")):
                first = self._get("/api/design", ORG, fake=fake).json()
                (space / "current" / "158-unrelated.prompt.md").write_text(
                    f"# Bug 158: Now bound\n\n{line}\n", encoding="utf-8"
                )
                second = self._get("/api/design", ORG, fake=fake).json()
        cards = first["designs"][0]["cards"]
        self.assertEqual(
            [(c["file"], c["id"], c["status"], c["archived"]) for c in cards],
            [("157-the-bindings.prompt.md", "157", "Active", False), ("155-the-cover.prompt.md", "155", "Done", True)],
        )
        # The listing came from the cache; the cards did not.
        self.assertEqual([c["id"] for c in second["designs"][0]["cards"]], ["157", "158", "155"])

    def test_an_opened_note_is_served_from_the_disk_while_the_listing_is_fresh(self):
        text = _front(ID_A) + "# A\n\nBody.\n"
        fake = FakeRepo({"design": {"a.md": text}})
        self._get("/api/design", ORG, fake=fake)
        first = self._get("/api/design/design/a.md", ORG, fake=fake).json()
        self.assertEqual(fake.kinds(), ["shape", "contents"])  # the first open reads it
        again = self._get("/api/design/design/a.md", ORG, fake=fake).json()
        self.assertEqual(fake.kinds(), ["shape", "contents"])  # the second does not
        self.assertEqual(again, first)
        self.assertEqual(again["body"], text)
        self.assertEqual(again["url"], f"https://github.com/{REPO}/blob/main/design/a.md")
        # A restart: the listing's one call, and the body still from the disk.
        design.clear_cache()
        self._get("/api/design", ORG, fake=fake)
        self.assertEqual(self._get("/api/design/design/a.md", ORG, fake=fake).json()["body"], text)
        self.assertEqual(fake.kinds(), ["shape", "contents", "shape"])
        # A listing past its TTL is not trusted for the sha: the open asks gh.
        when, listed, shas = design._list_cache[REPO]
        design._list_cache[REPO] = (when - design.LIST_TTL_SECONDS - 1, listed, shas)
        self._get("/api/design/design/a.md", ORG, fake=fake)
        self.assertEqual(fake.kinds()[-1], "contents")

    def test_a_changed_note_opens_with_its_new_text(self):
        folders = {"design": {"a.md": _front(ID_A) + "# A\n\nOld.\n"}}
        fake = FakeRepo(folders)
        self._get("/api/design", ORG, fake=fake)
        self._get("/api/design/design/a.md", ORG, fake=fake)
        design.clear_cache()
        folders["design"]["a.md"] = _front(ID_A) + "# A\n\nNew.\n"
        self._get("/api/design", ORG, fake=fake)
        body = self._get("/api/design/design/a.md", ORG, fake=fake).json()["body"]
        self.assertTrue(body.endswith("New.\n"))


if __name__ == "__main__":
    unittest.main()
