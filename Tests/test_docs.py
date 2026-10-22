"""The Docs tab's agent half -- /docs on a GitHub Space (D-S12).

Three routes: ``GET /api/docs`` lists the repo's README.md and its docs/ tree,
``GET /api/docs/{path}`` reads one document, ``GET /api/docs/asset/{path}``
serves one image's bytes. No network: subprocess is stubbed with a fake repo
(the way Tests/test_design.py does), and the assertions are about the path
rule, the gate, the listing and the asset decode.

Run:  python3 -m pytest Tests/test_docs.py
"""

import base64
import hashlib
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.ado import design, docs
    from agent.app import app
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

REPO = "johnfrog76/toolkit"
ORG = f"https://github.com/{REPO}"

README = "# ToolKit\n\nSee [the CLI](docs/CLI.md).\n\n![The board](docs/images/board.png)\n"
CLI = "# The CLI\n\n## The workflow\n"
ADO = "# Azure DevOps\n"
# Eight bytes that are not UTF-8: the decode must not go through text.
PNG = b"\x89PNG\r\n\x1a\n\x00\xff"

FILES: dict[str, bytes] = {
    "README.md": README.encode(),
    "AGENTS.md": b"# Not a doc\n",
    "docs/CLI.md": CLI.encode(),
    "docs/modules/ado.md": ADO.encode(),
    "docs/modules/deep/a/b/too-deep.md": b"# Too deep\n",
    "docs/images/board.png": PNG,
    "assets/logo.png": PNG,
    "docs/notes.txt": b"not markdown",
}


def _row(path: str, data: bytes) -> dict:
    return {
        "type": "file",
        "name": path.split("/")[-1],
        "path": path,
        "sha": f"sha-{path}",
        "size": len(data),
        "html_url": f"https://github.com/{REPO}/blob/main/{path}",
        "encoding": "base64",
        "content": base64.b64encode(data).decode(),
    }


class FakeRepo:
    """gh api over a dict of files; folders are derived; anything else is 404."""

    def __init__(
        self,
        files: dict[str, bytes] | None = None,
        fail: str = "",
        big: str = "",
        size: int | None = None,
        has_issues: bool | None = True,
    ):
        self.files = FILES if files is None else files
        self.fail = fail
        self.big = big  # a file the contents route answers with no content, as it does past 1 MB
        self.size = size  # the size the contents route reports for `big`
        self.has_issues = has_issues  # None: the repository read fails
        self.calls: list[list[str]] = []
        self.queries: list[str] = []  # each GraphQL query's text

    def _blob_sha(self, path: str) -> str:
        return hashlib.sha1(path.encode()).hexdigest()

    def __call__(self, argv, **_kw):
        self.calls.append(list(argv))
        # On Windows gh runs through the shell, so an `&` in an argument is cmd's.
        assert "&" not in " ".join(argv), argv
        if self.fail:
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr=self.fail)
        assert argv[:2] == ["gh", "api"], argv
        if argv[2] == "graphql":
            return self.graphql(argv)
        if argv[2] == f"repos/{REPO}":
            if self.has_issues is None:
                return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Server Error (HTTP 502)")
            row = {"html_url": f"https://github.com/{REPO}", "has_issues": self.has_issues}
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(row), stderr="")
        if argv[2].startswith(f"repos/{REPO}/git/blobs/"):
            sha = argv[2].rsplit("/", 1)[1]
            for f, data in self.files.items():
                if self._blob_sha(f) == sha:
                    blob = {
                        "sha": sha,
                        "size": len(data),
                        "encoding": "base64",
                        "content": base64.b64encode(data).decode(),
                    }
                    return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(blob), stderr="")
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not Found (HTTP 404)")
        path = argv[2].split(f"repos/{REPO}/contents/", 1)[1]
        if path in self.files:
            row = _row(path, self.files[path])
            if path == self.big:
                row.update(content="", encoding="none", sha=self._blob_sha(path))
                if self.size is not None:
                    row["size"] = self.size
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(row), stderr="")
        children = {}
        for f in self.files:
            if f.startswith(path + "/"):
                head = f[len(path) + 1 :].split("/")[0]
                full = f"{path}/{head}"
                children[head] = (
                    _row(full, self.files[full]) if full in self.files else {"type": "dir", "name": head, "path": full}
                )
        if children:
            listing = [{k: v for k, v in r.items() if k not in ("content", "encoding")} for r in children.values()]
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(listing), stderr="")
        return subprocess.CompletedProcess(argv, 1, stdout="", stderr="gh: Not Found (HTTP 404)")


def _graphql(self, argv):
    """The shape query the listing asks: ``f<i>: object(expression: $f<i>)`` per
    folder, ``entries`` nested as deep as the query nests them. The query must
    arrive as ``-F query=@<file>`` and ask for NO text -- the listing never
    needs one, and naming a blob's text makes GitHub load every blob."""
    assert argv[3] == "-F" and argv[4].startswith("query=@"), argv
    query = Path(argv[4][len("query=@") :]).read_text(encoding="utf-8")
    self.queries.append(query)
    assert "Blob" not in query and "text" not in query, query
    fields = {
        argv[i + 1].split("=", 1)[0]: argv[i + 1].split("=", 1)[1]
        for i in range(3, len(argv) - 1)
        if argv[i] in ("-f", "-F")
    }
    assert f"{fields['owner']}/{fields['name']}" == REPO, fields

    def level(folder: str, depth: int) -> list[dict]:
        prefix = f"{folder}/" if folder else ""
        names = {f[len(prefix) :].split("/")[0] for f in self.files if f.startswith(prefix)}
        rows = []
        for name in sorted(names):
            full = prefix + name
            if full in self.files:
                rows.append({"name": name, "type": "blob", "oid": self._blob_sha(full)})
            else:
                row = {"name": name, "type": "tree", "oid": "0" * 40}
                if depth > 1:
                    row["object"] = {"entries": level(full, depth - 1)}
                rows.append(row)
        return rows

    repo: dict = {"url": ORG, "defaultBranchRef": {"name": "main"}}
    if self.has_issues is not None:
        repo["hasIssuesEnabled"] = self.has_issues
    for line in query.splitlines():
        m = re.match(r"\s+(f\d+): object\(expression: \$f\d+\)", line)
        if not m:
            continue
        folder = fields[m.group(1)].removeprefix("HEAD:")
        if folder and not any(f.startswith(folder + "/") for f in self.files):
            repo[m.group(1)] = None
            continue
        repo[m.group(1)] = {"entries": level(folder, line.count("entries {"))}
    return subprocess.CompletedProcess(argv, 0, stdout=json.dumps({"data": {"repository": repo}}), stderr="")


FakeRepo.graphql = _graphql


class ThePathRule(unittest.TestCase):
    """One row per input the rule distinguishes -- the table the web's
    docRooms.test.ts reads too (Tests/fixtures/docs/paths.json)."""

    TABLE = json.loads((Path(__file__).resolve().parent / "fixtures" / "docs" / "paths.json").read_text("utf-8"))

    def test_the_shared_table(self):
        for path, is_doc, is_asset in self.TABLE["paths"]:
            self.assertEqual(docs.doc_path(path), is_doc, f"document: {path!r}")
            self.assertEqual(docs.doc_path(path, asset=True), is_asset, f"asset: {path!r}")

    def test_the_roots_are_the_contracts(self):
        from agent.core import consts as C

        self.assertEqual((docs.DOCS_README, docs.DOCS_ROOT), (C.docs_readme(), C.docs_root()))


class TheListing(unittest.TestCase):
    def setUp(self):
        docs.clear_cache()

    def _list(self, fake: FakeRepo):
        with mock.patch.object(design.subprocess, "run", side_effect=fake):
            return docs.list_docs(REPO)

    def test_the_readme_and_the_markdown_under_docs_sorted_by_path(self):
        resp = self._list(FakeRepo())
        self.assertIsNone(resp.reason)
        self.assertEqual(resp.readme.path, "README.md")
        self.assertEqual([d.path for d in resp.items], ["docs/CLI.md", "docs/modules/ado.md"])
        self.assertEqual(resp.items[1].folder, "docs/modules")
        self.assertTrue(resp.items[0].url.endswith("/blob/main/docs/CLI.md"))

    def test_no_docs_folder_is_the_readme_alone(self):
        resp = self._list(FakeRepo({"README.md": b"# R\n"}))
        self.assertEqual((resp.readme.path, resp.items, resp.reason), ("README.md", [], None))

    def test_the_listing_is_cached(self):
        fake = FakeRepo()
        self._list(fake)
        n = len(fake.calls)
        self._list(fake)
        self.assertEqual(len(fake.calls), n)
        docs.clear_cache()
        self._list(fake)
        self.assertEqual(len(fake.calls), 2 * n)

    def test_the_list_is_one_call_however_the_docs_nest(self):
        """A flat docs/, a handful of folders and a tree four levels deep with
        many folders all cost the same one gh call -- not one per folder."""
        deep = {
            "README.md": b"# R\n",
            "docs/a.md": b"# a\n",
            "docs/hub/b.md": b"# b\n",
            "docs/hub/cards/c.md": b"# c\n",
            "docs/hub/cards/old/d.md": b"# d\n",  # the fourth level: listed
            "docs/hub/cards/old/older/e.md": b"# e\n",  # the fifth: not
            **{f"docs/m{i}/n{i}/f{i}.md": b"# x\n" for i in range(12)},
        }
        counts = []
        for files in ({"README.md": b"# R\n", "docs/a.md": b"# a\n"}, FILES, deep):
            docs.clear_cache()
            fake = FakeRepo(files)
            resp = self._list(fake)
            self.assertIsNone(resp.reason)
            self.assertEqual([c[2] for c in fake.calls], ["graphql"], list(files)[:3])
            counts.append(len(fake.calls))
        self.assertEqual(counts, [1, 1, 1])
        paths = [d.path for d in resp.items]
        self.assertIn("docs/hub/cards/old/d.md", paths)
        self.assertNotIn("docs/hub/cards/old/older/e.md", paths)
        self.assertEqual(len(paths), 4 + 12)
        self.assertEqual(resp.items[2].folder, "docs/hub/cards")

    def test_a_row_is_what_the_contents_walk_made_it(self):
        resp = self._list(FakeRepo())
        self.assertEqual(
            resp.readme.model_dump(),
            {"path": "README.md", "name": "README.md", "folder": "", "url": f"{ORG}/blob/main/README.md"},
        )
        self.assertEqual(
            resp.items[1].model_dump(),
            {
                "path": "docs/modules/ado.md",
                "name": "ado.md",
                "folder": "docs/modules",
                "url": f"{ORG}/blob/main/docs/modules/ado.md",
            },
        )

    def test_nothing_is_asked_again_for_a_listing_read_before(self):
        """After the in-memory state is cleared (a restart, in effect) the next
        list is the same one shape call: no text, no blob, no contents call."""
        fake = FakeRepo()
        first = self._list(fake)
        docs.clear_cache()
        second = self._list(fake)
        self.assertEqual(second.model_dump(), first.model_dump())
        self.assertEqual([c[2] for c in fake.calls], ["graphql", "graphql"])
        self.assertTrue(all("&" not in " ".join(c) for c in fake.calls))
        self.assertTrue(all(c[3] == "-F" and c[4].startswith("query=@") for c in fake.calls))
        self.assertFalse(any("/blobs/" in " ".join(c) or "/contents/" in " ".join(c) for c in fake.calls))

    def test_the_list_carries_the_issues_switch_so_a_document_read_needs_no_call_for_it(self):
        fake = FakeRepo()
        with mock.patch.object(design.subprocess, "run", side_effect=fake):
            docs.list_docs(REPO)
            self.assertEqual(docs.issues_url(REPO), f"{ORG}/issues")
        self.assertEqual([c[2] for c in fake.calls], ["graphql"])
        off = FakeRepo(has_issues=False)
        docs.clear_cache()
        with mock.patch.object(design.subprocess, "run", side_effect=off):
            docs.list_docs(REPO)
            self.assertEqual(docs.issues_url(REPO), "")
        self.assertEqual([c[2] for c in off.calls], ["graphql"])

    def test_gh_not_answering_is_a_reason(self):
        resp = self._list(FakeRepo(fail="gh: To get started with GitHub CLI, please run:  gh auth login"))
        self.assertIn("gh auth login", resp.reason)
        self.assertIn(REPO, resp.reason)


class TheRoutes(unittest.TestCase):
    def setUp(self):
        docs.clear_cache()
        self.client = TestClient(app)

    def _get(self, url: str, org: str = ORG, tier: int = 1, fake: FakeRepo | None = None):
        fake = fake if fake is not None else FakeRepo()
        with (
            mock.patch.object(design, "load_config", return_value={"org": org, "status": "active"}),
            mock.patch.object(design, "_resolve_tier", return_value=(tier, "")),
            mock.patch.object(design.subprocess, "run", side_effect=fake),
        ):
            return self.client.get(url)

    def test_the_list(self):
        body = self._get("/api/docs").json()
        self.assertTrue(body["supported"])
        self.assertEqual(body["readme"]["path"], "README.md")
        self.assertEqual([i["path"] for i in body["items"]], ["docs/CLI.md", "docs/modules/ado.md"])

    def test_the_gate_asks_nothing_where_it_is_not_supported(self):
        """ADO, no tracker, Tier 2: supported false, and gh is never asked."""
        rows = [
            ("an ADO Space", "https://dev.azure.com/acme", 1),
            ("no tracker", "", 1),
            ("GitHub at Tier 2", ORG, 2),
        ]
        for name, org, tier in rows:
            for url in ("/api/docs", "/api/docs/README.md"):
                fake = FakeRepo()
                res = self._get(url, org, tier, fake)
                self.assertEqual(res.status_code, 200, (name, url))
                self.assertFalse(res.json()["supported"], (name, url))
                self.assertEqual(fake.calls, [], (name, url))
            fake = FakeRepo()
            self.assertEqual(self._get("/api/docs/asset/docs/images/board.png", org, tier, fake).status_code, 404, name)
            self.assertEqual(fake.calls, [], name)

    def test_an_owner_grained_address_is_refused_with_a_sentence(self):
        res = self._get("/api/docs", "https://github.com/johnfrog76")
        self.assertEqual(res.status_code, 400)
        self.assertIn("Docs tab reads one repo's README.md", res.json()["detail"])

    def test_one_document_reads_with_its_body_and_title(self):
        body = self._get("/api/docs/docs/CLI.md").json()
        self.assertEqual((body["path"], body["title"], body["folder"]), ("docs/CLI.md", "The CLI", "docs"))
        self.assertEqual(body["body"], CLI)
        self.assertEqual(self._get("/api/docs/README.md").json()["title"], "ToolKit")

    def test_a_missing_document_is_404(self):
        self.assertEqual(self._get("/api/docs/docs/nope.md").status_code, 404)

    def test_a_refused_path_never_reaches_gh(self):
        fake = FakeRepo()
        for url in (
            "/api/docs/AGENTS.md",
            "/api/docs/spec/x.spec.md",
            "/api/docs/docs/notes.txt",
            "/api/docs/docs/%2E%2E/AGENTS.md",
            "/api/docs/docs/..%2FAGENTS.md",
            "/api/docs/asset/AGENTS.md",
            "/api/docs/asset/docs/%2E%2E/x.png",
        ):
            res = self._get(url, fake=fake)
            self.assertEqual(res.status_code, 404, url)
            self.assertIn("never a '..'", res.json()["detail"], url)
        self.assertEqual(fake.calls, [])

    def test_an_asset_is_its_bytes_decoded_with_its_type(self):
        res = self._get("/api/docs/asset/docs/images/board.png")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.content, PNG)
        self.assertEqual(res.headers["content-type"], "image/png")
        self.assertEqual(res.headers["x-content-type-options"], "nosniff")

    def test_a_missing_asset_is_404(self):
        self.assertEqual(self._get("/api/docs/asset/docs/images/nope.png").status_code, 404)

    def test_an_image_past_what_the_contents_route_inlines_comes_from_its_blob(self):
        fake = FakeRepo(big="docs/images/board.png", size=3 * 1048576)
        res = self._get("/api/docs/asset/docs/images/board.png", fake=fake)
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(res.content, PNG)
        self.assertEqual(res.headers["content-type"], "image/png")
        sha = fake._blob_sha("docs/images/board.png")
        self.assertEqual([c[2] for c in fake.calls][-1], f"repos/{REPO}/git/blobs/{sha}")

    def test_an_image_past_the_ceiling_is_a_413_that_says_so_and_no_blob_is_asked(self):
        fake = FakeRepo(big="docs/images/board.png", size=docs.ASSET_MAX_BYTES + 1)
        res = self._get("/api/docs/asset/docs/images/board.png", fake=fake)
        self.assertEqual(res.status_code, 413)
        self.assertIn(f"up to {docs.ASSET_MAX_BYTES // 1048576} MB", res.json()["detail"])
        self.assertFalse(any("/git/blobs/" in c[2] for c in fake.calls), fake.calls)

    def test_an_image_at_the_ceiling_is_served(self):
        fake = FakeRepo(big="docs/images/board.png", size=docs.ASSET_MAX_BYTES)
        self.assertEqual(self._get("/api/docs/asset/docs/images/board.png", fake=fake).status_code, 200)

    def test_a_large_image_with_no_object_id_is_a_502_not_an_empty_picture(self):
        class NoSha(FakeRepo):
            def _blob_sha(self, path):
                return "not-a-sha"

        res = self._get("/api/docs/asset/docs/images/board.png", fake=NoSha(big="docs/images/board.png"))
        self.assertEqual(res.status_code, 502)

    def test_an_image_outside_docs_is_served_the_same_way(self):
        res = self._get("/api/docs/asset/assets/logo.png")
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(res.content, PNG)

    def test_an_image_path_that_climbs_out_of_the_repository_never_reaches_gh(self):
        fake = FakeRepo()
        for url in (
            "/api/docs/asset/%2E%2E/logo.png",
            "/api/docs/asset/assets/%2E%2E/%2E%2E/logo.png",
            "/api/docs/asset/docs/..%2F..%2Flogo.png",
        ):
            res = self._get(url, fake=fake)
            self.assertEqual(res.status_code, 404, url)
            self.assertIn("never a '..'", res.json()["detail"], url)
        self.assertEqual(fake.calls, [])


class TheIssuesLink(unittest.TestCase):
    """A document says where its repository's issues are, so the room can link
    a `#N`; a repository with issues off, or one GitHub did not describe, says
    nothing and the `#N` stays text."""

    def setUp(self):
        docs.clear_cache()

    def _read(self, fake: FakeRepo):
        with mock.patch.object(design.subprocess, "run", side_effect=fake):
            return docs.read_doc(REPO, "README.md")

    def test_a_repository_with_issues(self):
        self.assertEqual(self._read(FakeRepo()).issues, f"https://github.com/{REPO}/issues")

    def test_a_repository_with_issues_off(self):
        self.assertEqual(self._read(FakeRepo(has_issues=False)).issues, "")

    def test_an_unanswered_read_is_text_and_asked_again(self):
        fake = FakeRepo(has_issues=None)
        self.assertEqual(self._read(fake).issues, "")
        self._read(fake)
        self.assertEqual(sum(1 for c in fake.calls if c[2] == f"repos/{REPO}"), 2)

    def test_an_answer_is_cached(self):
        fake = FakeRepo()
        self._read(fake)
        docs.design.clear_cache()
        self._read(fake)
        self.assertEqual(sum(1 for c in fake.calls if c[2] == f"repos/{REPO}"), 1)


if __name__ == "__main__":
    unittest.main()
