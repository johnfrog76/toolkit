"""The shared folder reader's nesting and names-only options (``agent/ado/repo_read.py``).

``read_folder_rows`` is exercised end to end by Tests/test_design.py (depth 1,
with text, cached on disk) and Tests/test_docs.py (nested, names only). This file
holds what is about the helper itself: the query it writes for ``depth``, how a
nested answer becomes paths, and that ``parse=None`` asks for no text and writes
nothing to the disk cache. No network: ``run_read`` is replaced.

Run:  python3 -m pytest Tests/test_repo_read.py
"""

import hashlib
import json
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
    from agent.ado import repo_read
    from agent.core import disk_cache
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

SHA = hashlib.sha1(b"a.md").hexdigest()


def blob(name: str, text: str | None = None) -> dict:
    row = {"name": name, "type": "blob", "oid": hashlib.sha1(name.encode()).hexdigest()}
    if text is not None:
        row["object"] = {"text": text}
    return row


def tree(name: str, entries: list[dict] | None = None) -> dict:
    row = {"name": name, "type": "tree", "oid": "0" * 40}
    if entries is not None:
        row["object"] = {"entries": entries}
    return row


class Canned:
    """One GraphQL answer, whatever is asked; the queries are kept."""

    def __init__(self, repository: dict):
        self.repository = {"url": "https://github.com/o/r", "defaultBranchRef": {"name": "main"}, **repository}
        self.queries: list[str] = []
        self.argv: list[list[str]] = []

    def __call__(self, cmd, _timeout):
        self.argv.append(list(cmd))
        self.queries.append(Path(cmd[cmd.index("-F") + 1].split("@", 1)[1]).read_text(encoding="utf-8"))
        body = {"data": {"repository": self.repository}}
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(body), stderr="")


class TheNestingOption(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        patch = mock.patch.dict("os.environ", {"P20_AGENT_CACHE_DIR": self._tmp.name})
        patch.start()
        self.addCleanup(patch.stop)

    def _read(self, canned: Canned, folders: list[str], **kw):
        with mock.patch.object(repo_read, "run_read", side_effect=canned):
            return repo_read.read_folder_rows("o/r", folders, **kw)

    def test_depth_one_writes_the_query_it_always_wrote(self):
        self.assertIn(
            "f0: object(expression: $f0) { ... on Tree { entries { name type oid } } }",
            repo_read._shape_query(1, False),
        )
        self.assertIn(
            "entries { name type oid object { ... on Blob { text } } }",
            repo_read._shape_query(1, True),
        )

    def test_depth_nests_entries_and_asks_for_a_blobs_text_only_when_told_to(self):
        names = repo_read._shape_query(1, False, [3])
        self.assertEqual(names.count("entries {"), 3)
        self.assertNotIn("Blob", names)
        text = repo_read._shape_query(1, True, [3])
        self.assertEqual(text.count("entries {"), 3)
        self.assertEqual(text.count("... on Blob { text }"), 3)

    def test_a_nested_answer_is_every_blob_beneath_the_folder_by_path_in_one_call(self):
        canned = Canned(
            {
                "f0": {
                    "entries": [
                        tree("hub", [blob("b.md"), tree("cards", [blob("c.md"), blob("z.txt")])]),
                        blob("a.md"),
                        blob("skip.txt"),
                    ]
                }
            }
        )
        read = self._read(canned, ["docs"], keep=lambda n: n.endswith(".md"), depth=3)
        self.assertEqual([e.path for e in read.folders["docs"]], ["docs/a.md", "docs/hub/b.md", "docs/hub/cards/c.md"])
        self.assertEqual(read.calls, 1)
        self.assertEqual(len(canned.queries), 1)
        self.assertEqual(canned.queries[0].count("entries {"), 3)

    def test_a_tree_the_query_did_not_open_is_not_a_blob_and_not_an_error(self):
        read = self._read(Canned({"f0": {"entries": [tree("hub"), blob("a.md")]}}), ["docs"], depth=1)
        self.assertEqual([e.path for e in read.folders["docs"]], ["docs/a.md"])

    def test_depth_per_folder_and_the_repository_root(self):
        canned = Canned(
            {
                "f0": {"entries": [blob("README.md"), blob("LICENSE")]},
                "f1": {"entries": [tree("hub", [blob("b.md")])]},
            }
        )
        read = self._read(canned, ["", "docs"], keep=lambda n: n.endswith(".md"), depth={"docs": 2})
        self.assertEqual([e.path for e in read.folders[""]], ["README.md"])
        self.assertEqual([e.path for e in read.folders["docs"]], ["docs/hub/b.md"])
        query = canned.queries[0]
        f0 = next(ln for ln in query.splitlines() if ln.strip().startswith("f0:"))
        f1 = next(ln for ln in query.splitlines() if ln.strip().startswith("f1:"))
        self.assertEqual((f0.count("entries {"), f1.count("entries {")), (1, 2))
        self.assertIn("f0=HEAD:", canned.argv[0])
        self.assertIn("f1=HEAD:docs", canned.argv[0])

    def test_an_absent_folder_is_absent(self):
        read = self._read(Canned({"f0": None}), ["docs"], depth=4)
        self.assertEqual((read.folders, read.reason), ({}, None))

    def test_the_issues_switch_rides_the_same_call(self):
        on = self._read(Canned({"f0": None, "hasIssuesEnabled": True}), ["docs"])
        off = self._read(Canned({"f0": None, "hasIssuesEnabled": False}), ["docs"])
        unsaid = self._read(Canned({"f0": None}), ["docs"])
        self.assertEqual((on.has_issues, off.has_issues, unsaid.has_issues), (True, False, None))
        self.assertEqual(on.repo_url, "https://github.com/o/r")

    def test_depth_with_text_reads_nested_blobs_from_the_one_call_and_keeps_their_rows(self):
        canned = Canned(
            {"f0": {"entries": [tree("hub", [blob("b.md", "# B\n")]), blob("a.md", "# A\n")]}},
        )
        parsed: list[str] = []

        def parse(text: str) -> dict:
            parsed.append(text)
            return {"n": len(text)}

        read = self._read(canned, ["docs"], namespace="t-v1", parse=parse, depth=2)
        self.assertEqual(read.calls, 1)
        self.assertEqual(sorted(parsed), ["# A\n"] * 1 + ["# B\n"] * 1)
        self.assertEqual(set(read.rows), {"docs/a.md", "docs/hub/b.md"})

    def test_names_only_asks_for_no_text_parses_nothing_and_writes_no_cache(self):
        canned = Canned({"f0": {"entries": [blob("a.md")]}})
        read = self._read(canned, ["docs"])
        self.assertNotIn("Blob", canned.queries[0])
        self.assertEqual((read.rows, read.calls), ({}, 1))
        self.assertEqual(read.shas, {"docs/a.md": SHA})
        self.assertFalse(disk_cache.cache_root().joinpath(repo_read.ROWS_DIR).exists())

    def test_no_ampersand_and_the_query_in_a_file(self):
        canned = Canned({"f0": None})
        self._read(canned, ["docs"], depth=4)
        argv = canned.argv[0]
        self.assertNotIn("&", " ".join(argv))
        self.assertEqual(argv[:5], ["gh", "api", "graphql", "-F", argv[4]])
        self.assertTrue(argv[4].startswith("query=@"))


if __name__ == "__main__":
    unittest.main()
