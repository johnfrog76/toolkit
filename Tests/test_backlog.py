"""The Backlog's rows: ``backlog_rows`` and ``GET /api/backlog``.

The rule is one shared table, ``Tests/fixtures/parsers/backlog-order.json``,
which ``tkTestToolkit -Backlog`` asserts from the CLI's half too: the rows of
``backlog/`` milestone by milestone, ranked by the milestone's file, then the
cards with no milestone; rank, age, the heading's type and title, and the
filters. The route is a folder read over a scratch hub -- no tracker is asked
-- and on an Azure DevOps Space, or for an undeclared Space, it is a 404.

Run:  python3 -m pytest Tests/test_backlog.py
"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import backlog
    from agent.core.parsers import backlog_card, backlog_rows
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

TABLE = json.loads((PKG_ROOT / "Tests/fixtures/parsers/backlog-order.json").read_text(encoding="utf-8"))
KEYS = ["rank", "id", "title", "type", "milestone", "tags", "age", "in_play"]
GH_ORG = "https://github.com/someone/product"
ADO_ORG = "https://dev.azure.com/acme"


def _case_rows(case):
    eol = "\r\n" if case["crlf"] else "\n"
    cards = [
        c
        for c in (
            backlog_card(k["file"], k["folder"], eol.join(k["lines"]), TABLE["typeNames"], TABLE["prefixes"])
            for k in case["cards"]
        )
        if c
    ]
    files = {m["file"]: eol.join(m["lines"]) for m in case["milestones"]}
    f = case["filter"]
    rows = backlog_rows(cards, files, case["today"], f["milestone"], f["tag"], f["type"])
    return [{k: r[k] for k in KEYS} for r in rows]


class TheSharedTable(unittest.TestCase):
    def test_every_case(self):
        for case in TABLE["cases"]:
            with self.subTest(case["name"]):
                self.assertEqual(_case_rows(case), case["rows"])

    def test_the_table_has_a_case_for_every_rule(self):
        names = " | ".join(c["name"] for c in TABLE["cases"])
        for shape in (
            "with a file first",
            "a card in play is a row in its ranked place",
            "a card in play the order does not list",
            "stale id",
            "not at the title's slug",
            "no Created",
            "no milestone",
            "impossible date",
            "emoji",
            "Sprint line",
            "filter by milestone",
            "filter by tag",
            "filter by type",
            "filters AND",
            "CRLF",
            "cards are all in play is no group",
            "an empty Space",
        ):
            self.assertIn(shape, names)


def _write(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes("\n".join(lines).encode("utf-8"))


class TheRoute(unittest.TestCase):
    """The route over a scratch Space: the first case of the table with rows in
    play, written to disk, read back the same."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="p20-backlog-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        case = next(c for c in TABLE["cases"] if "a card in play is a row in its ranked place" in c["name"])
        self.case = case
        self.space = self.root / "home"
        for k in case["cards"]:
            _write(self.space / k["folder"] / k["file"], k["lines"])
        for m in case["milestones"]:
            _write(self.space / "milestones" / m["file"], m["lines"])
        # A file that is not a card is not a row.
        _write(self.space / "backlog" / "notes.md", ["# Notes"])
        app = FastAPI()
        app.include_router(backlog.api, prefix="/api")
        self.client = TestClient(app)

    def _get(self, org=GH_ORG, query="", spaces=None):
        cfg = {
            "org": org,
            "activeSpace": "home",
            "workItemTypes": {n: {"filePrefix": p} for n, p in zip(TABLE["typeNames"], TABLE["prefixes"])},
            "spaces": spaces or [{"slug": "home", "org": org, "promptsFolder": "home"}],
        }
        with (
            mock.patch.object(backlog, "load_config", return_value=cfg),
            mock.patch.object(backlog, "resolve_dirs", return_value=(self.space / "current", self.space / "archive")),
            mock.patch.object(backlog, "org_folder", side_effect=lambda e: self.root / e["promptsFolder"]),
            mock.patch.object(backlog, "date") as clock,
        ):
            clock.today.return_value.isoformat.return_value = self.case["today"]
            return self.client.get(f"/api/backlog{query}")

    def test_a_github_space_serves_the_table_rows(self):
        r = self._get()
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["space"], "home")
        self.assertEqual([{k: row[k] for k in KEYS} for row in body["rows"]], self.case["rows"])
        self.assertEqual(body["count"], len(self.case["rows"]))
        self.assertTrue(all(row["file"].endswith(".prompt.md") for row in body["rows"]))

    def test_a_space_with_no_tracker_serves_them_too(self):
        r = self._get(org="")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.json()["rows"]), len(self.case["rows"]))

    def test_the_filters_travel_as_query_arguments(self):
        r = self._get(query="?milestone=m2&type=bug")
        self.assertEqual([row["id"] for row in r.json()["rows"]], ["141"])
        r = self._get(query="?milestone=M2")
        self.assertEqual([row["in_play"] for row in r.json()["rows"]][:2], [True, False])
        r = self._get(query="?tag=nothing")
        self.assertEqual(r.json()["rows"], [])

    def test_an_azure_devops_space_is_a_404_naming_mywork(self):
        r = self._get(org=ADO_ORG)
        self.assertEqual(r.status_code, 404)
        self.assertIn("MyWork", r.json()["detail"])

    def test_a_named_space_reads_its_own_folder_and_its_own_tracker(self):
        spaces = [
            {"slug": "home", "org": ADO_ORG, "promptsFolder": "elsewhere"},
            {"slug": "product", "org": GH_ORG, "promptsFolder": "home"},
        ]
        r = self._get(org=ADO_ORG, query="?space=product", spaces=spaces)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["space"], "product")
        self.assertEqual(len(r.json()["rows"]), len(self.case["rows"]))
        spaces[1]["org"] = ADO_ORG
        self.assertEqual(self._get(org=GH_ORG, query="?space=product", spaces=spaces).status_code, 404)

    def test_an_undeclared_space_is_a_404_naming_it(self):
        r = self._get(query="?space=nowhere")
        self.assertEqual(r.status_code, 404)
        self.assertIn("nowhere", r.json()["detail"])

    def test_a_space_with_no_folders_has_no_rows(self):
        shutil.rmtree(self.space)
        r = self._get()
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {"space": "home", "count": 0, "rows": []})

    def test_reading_writes_nothing(self):
        before = {p: p.read_bytes() for p in self.space.rglob("*") if p.is_file()}
        self._get()
        self._get(query="?milestone=M2")
        after = {p: p.read_bytes() for p in self.space.rglob("*") if p.is_file()}
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
