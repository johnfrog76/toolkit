"""The Organize add-on's GET /api/reference -- the header's reading, the search, the gate.

The header's reading is held to ONE table, Tests/fixtures/reference/table.json,
which the CLI's Reference verb (#315) asserts from the other side when it lands.

Run:  python3 -m pytest Tests/test_reference.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

REPO_ROOT = Path(__file__).resolve().parent.parent
try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.organize import api as organize_api
    from agent.organize import reference
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "reference"
TABLE = json.loads((FIXTURES / "table.json").read_text(encoding="utf-8"))


class _Hub(unittest.TestCase):
    features = {"organize": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.hub = base / "hub"
        (self.hub / "reference").mkdir(parents=True)
        shutil.copytree(FIXTURES / "current", self.hub / "reference" / "current")
        default_path = base / "config.default.json"
        local_path = base / "config.local.json"
        default_path.write_text(
            json.dumps(
                {
                    "activeSpace": "test",
                    "features": self.features,
                    "promptsRoot": str(self.hub),
                    "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
                }
            ),
            encoding="utf-8",
        )
        local_path.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local_path),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        app = FastAPI()
        app.include_router(organize_api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()


class TheHeader(_Hub):
    def test_every_row_of_the_shared_table(self):
        listed = {d.name: d for d in reference.list_documents().items}
        self.assertEqual(sorted(listed), sorted(r["file"] for r in TABLE["documents"]))
        for row in TABLE["documents"]:
            with self.subTest(file=row["file"]):
                d = listed[row["file"]]
                self.assertEqual(
                    (d.title, d.source, d.valid, d.added, d.original),
                    (row["title"], row["source"], row["valid"], row["added"], row["original"]),
                )

    def test_a_file_that_is_not_markdown_is_not_a_document(self):
        self.assertNotIn("readme.txt", [d["name"] for d in self.client.get("/api/reference").json()["items"]])

    def test_the_list_is_in_title_order(self):
        titles = [d["title"] for d in self.client.get("/api/reference").json()["items"]]
        self.assertEqual(titles, sorted(titles, key=str.lower))


class TheExcerpt(_Hub):
    def test_the_content_after_the_header_as_plain_words(self):
        listed = {d.name: d for d in reference.list_documents().items}
        self.assertEqual(
            listed["sample-notes.md"].excerpt,
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt.",
        )
        # A table reads as its words: no pipes, no rule row.
        self.assertTrue(
            listed["days-off-2027.md"].excerpt.startswith("Date Holiday 2027-01-01 New Year's Day 2027-05-31")
        )

    def test_a_file_with_no_header_reads_after_its_title(self):
        listed = {d.name: d for d in reference.list_documents().items}
        self.assertEqual(
            listed["bare-notes.md"].excerpt, "Written with no header at all: a document is still a document."
        )

    def test_markdown_syntax_is_dropped(self):
        content = "## Heading\n**bold** and `code` and [a link](http://x.test/y) and _more_\n"
        text = f"# T\n\n---\n\n{content}"
        self.assertEqual(reference.excerpt_of(text), "Heading bold and code and a link and more")

    def test_a_long_document_is_cut_on_a_word(self):
        text = "# T\n\n---\n\n" + "word " * 200
        out = reference.excerpt_of(text)
        self.assertTrue(out.endswith("word..."))
        self.assertLessEqual(len(out), reference.EXCERPT_CHARS + 3)


class TheSearch(_Hub):
    def test_every_row_of_the_shared_table(self):
        for row in TABLE["search"]:
            with self.subTest(q=row["q"]):
                body = self.client.get("/api/reference", params={"q": row["q"]}).json()
                self.assertEqual(sorted(d["name"] for d in body["items"]), sorted(row["files"]))
                self.assertEqual(body["count"], len(row["files"]))

    def test_a_hit_says_the_line_that_matched(self):
        body = self.client.get("/api/reference", params={"q": "memorial"}).json()
        self.assertIn("Memorial Day", body["items"][0]["line"])


class TheRead(_Hub):
    def test_a_document_is_returned_whole(self):
        body = self.client.get("/api/reference/days-off-2027.md").json()
        self.assertEqual(body["title"], "2027 Observed Days Off")
        self.assertEqual(body["valid"], "2027-01-01 to 2027-12-31")
        self.assertIn("| 2027-05-31 | Memorial Day |", body["body"])

    def test_a_document_says_where_its_file_lives(self):
        body = self.client.get("/api/reference/days-off-2027.md").json()
        self.assertEqual(Path(body["path"]), self.hub / "reference" / "current" / "days-off-2027.md")

    def test_a_missing_document_is_404(self):
        self.assertEqual(self.client.get("/api/reference/nope.md").status_code, 404)

    def test_a_name_that_is_a_path_or_not_markdown_is_404(self):
        for name in ("readme.txt", "..%2Fhub.json", "current%2Fsample-notes.md", "..", ".md"):
            with self.subTest(name=name):
                self.assertEqual(self.client.get(f"/api/reference/{name}").status_code, 404)


class TheGate(_Hub):
    def test_a_hub_with_no_reference_folder_answers_empty_not_an_error(self):
        shutil.rmtree(self.hub / "reference")
        body = self.client.get("/api/reference").json()
        self.assertEqual((body["count"], body["items"]), (0, []))

    def test_an_empty_folder_answers_empty(self):
        for f in (self.hub / "reference" / "current").iterdir():
            f.unlink()
        self.assertEqual(self.client.get("/api/reference").json()["count"], 0)


class WithOrganizeOff(_Hub):
    features = {"organize": False}

    def test_both_routes_are_404_not_403(self):
        self.assertEqual(self.client.get("/api/reference").status_code, 404)
        self.assertEqual(self.client.get("/api/reference/days-off-2027.md").status_code, 404)


if __name__ == "__main__":
    unittest.main()
