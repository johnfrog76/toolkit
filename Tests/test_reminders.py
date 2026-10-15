"""The Organize add-on's GET /api/reminders -- the bucket rule, the route, the gate.

The bucket rule (overdue / today / upcoming) is implemented twice, here and in
the CLI's Reminders, and held to ONE table: Tests/fixtures/reminders/buckets.json,
which Tests/Test-Reminders.ps1 asserts from the other side. Parity only holds for
the shapes a table has.

Run:  python3 -m pytest Tests/test_reminders.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from datetime import datetime
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
    from agent.organize import reminders
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

TABLE = json.loads((REPO_ROOT / "Tests" / "fixtures" / "reminders" / "buckets.json").read_text(encoding="utf-8"))
FIXTURE_HUB = REPO_ROOT / "Tests" / "fixtures" / "hub"


def _at(text: str) -> datetime:
    return datetime.strptime(text, "%Y-%m-%dT%H:%M")


class TheBucketRule(unittest.TestCase):
    def test_every_row_of_the_shared_table(self):
        for row in TABLE["buckets"]:
            with self.subTest(why=row["why"]):
                self.assertEqual(reminders.reminder_bucket(row["due"] or "", _at(row["now"])), row["bucket"])

    def test_a_value_that_is_not_a_date_is_upcoming_not_an_error(self):
        self.assertEqual(reminders.reminder_bucket("soon", _at("2026-09-23T10:00")), "upcoming")


class TheRoute(unittest.TestCase):
    features = {"organize": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.hub = base / "hub"
        shutil.copytree(FIXTURE_HUB, self.hub)
        self.default_path = base / "config.default.json"
        self.local_path = base / "config.local.json"
        self.default_path.write_text(
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
        self.local_path.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        app = FastAPI()
        app.include_router(reminders.api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def test_the_fixture_reads_in_bucket_order_against_a_fixed_clock(self):
        body = reminders.list_reminders(now=_at("2026-09-23T10:00"))
        self.assertEqual([r.id for r in body.items], ["K7M2", "Q4TN", "W3X7"])
        self.assertEqual([r.bucket for r in body.items], ["overdue", "today", "upcoming"])
        self.assertEqual(body.buckets, {"overdue": 1, "today": 1, "upcoming": 1})
        self.assertEqual(body.asOf, "2026-09-23T10:00")

    def test_a_reminder_carries_its_fields_as_stored(self):
        q = next(r for r in reminders.list_reminders(now=_at("2026-09-23T10:00")).items if r.id == "Q4TN")
        self.assertEqual(
            (q.title, q.due, q.source, q.ref, q.created),
            ("Review the sprint goals", "2026-09-23T14:00", "ado", "41", "2026-09-20"),
        )

    def test_a_file_with_no_id_is_not_a_reminder(self):
        body = self.client.get("/api/reminders").json()
        self.assertNotIn("notes.md", [r["filename"] for r in body["items"]])
        self.assertEqual(body["count"], 3)

    def test_a_hub_that_has_never_had_a_reminder_answers_empty(self):
        shutil.rmtree(self.hub / "reminders")
        body = self.client.get("/api/reminders").json()
        self.assertEqual((body["count"], body["items"]), (0, []))
        self.assertEqual(body["buckets"], {"overdue": 0, "today": 0, "upcoming": 0})

    def test_the_folder_is_the_hubs_to_name(self):
        (self.hub / "reminders").rename(self.hub / "todo")
        manifest = json.loads((self.hub / "hub.json").read_text(encoding="utf-8"))
        manifest["folders"]["reminders"] = "todo"
        (self.hub / "hub.json").write_text(json.dumps(manifest), encoding="utf-8")
        self.assertEqual(self.client.get("/api/reminders").json()["count"], 3)

    def test_nothing_derived_is_stored(self):
        for f in (self.hub / "reminders" / "current").glob("*.md"):
            text = f.read_text(encoding="utf-8").lower()
            for word in TABLE["buckets"][0]["bucket"], "overdue", "today":
                self.assertNotIn(f"**{word}", text)


class ARefThatNamesACard(TheRoute):
    """A ref resolves to a card only when the WHOLE ref has an id's shape and a
    card in the ACTIVE Space's current/ or archive/ carries that id."""

    def setUp(self):
        super().setUp()
        # The shipped card types, so a Task card's filename reads as its id.
        shipped = json.loads((REPO_ROOT / "config.default.json").read_text(encoding="utf-8"))
        cfg = json.loads(self.default_path.read_text(encoding="utf-8"))
        cfg["workItemTypes"] = shipped["workItemTypes"]
        self.default_path.write_text(json.dumps(cfg), encoding="utf-8")

    def _card(self, folder: str, name: str, heading: str):
        target = self.hub / folder
        target.mkdir(parents=True, exist_ok=True)
        (target / name).write_text(f"# {heading}\n\nBody.\n", encoding="utf-8")

    def _reminder(self, rid: str, ref: str):
        (self.hub / "reminders" / "current" / f"{rid}-about-a-card.md").write_text(
            f"# About a card\n\n---\n\n**Source:** ado\n**Ref:** {ref}\n**Created:** 2026-09-20\n",
            encoding="utf-8",
        )

    def _item(self, rid: str):
        body = self.client.get("/api/reminders").json()
        return next(r for r in body["items"] if r["id"] == rid)

    def test_a_number_resolves_to_the_work_item_card_in_current(self):
        # The fixture's own Task401 card, in the active Space's current/.
        self._reminder("T6RA", "401")
        self.assertEqual(
            self._item("T6RA")["card"],
            {
                "id": "401",
                "title": "Add retry to the upload client",
                "folder": "current",
                "file": "Task401-add-retry-to-upload.prompt.md",
            },
        )

    def test_a_number_is_normalised_by_the_one_id_rule(self):
        self._reminder("T6RA", "0401")
        self.assertEqual(self._item("T6RA")["card"]["id"], "401")

    def test_a_lettered_id_resolves_to_a_card_with_no_work_item(self):
        self._card("test/current", "K9AC-tidy-the-hub.prompt.md", "Tidy the hub")
        self._reminder("T6RA", "K9AC")
        card = self._item("T6RA")["card"]
        self.assertEqual((card["id"], card["title"], card["folder"]), ("K9AC", "Tidy the hub", "current"))

    def test_a_ref_to_an_archived_card_resolves_with_its_folder(self):
        self._card("test/archive", "Task388-old-work.prompt.md", "Task 388: Old work")
        self._reminder("T6RA", "388")
        card = self._item("T6RA")["card"]
        self.assertEqual((card["id"], card["title"], card["folder"]), ("388", "Old work", "archive"))

    def test_current_wins_over_archive_for_one_id(self):
        self._card("test/archive", "Task401-add-retry-to-upload.prompt.md", "Task 401: The earlier round")
        self._reminder("T6RA", "401")
        self.assertEqual(self._item("T6RA")["card"]["folder"], "current")

    def test_a_ref_that_is_prose_stays_plain_text(self):
        for ref in ("401 and the review", "daily at 09:00", "2026-09-24", "k9ac", "41-retry"):
            with self.subTest(ref=ref):
                self._reminder("T6RA", ref)
                item = self._item("T6RA")
                self.assertEqual((item["ref"], item["card"]), (ref, None))

    def test_an_id_no_card_carries_stays_plain_text(self):
        # The fixture's Q4TN carries ref 41, and no card in the Space is 41.
        self.assertIsNone(self._item("Q4TN")["card"])

    def test_a_card_in_another_space_is_not_resolved(self):
        self._card("elsewhere/current", "M3QD-another-spaces-card.prompt.md", "Another Space's card")
        self._reminder("T6RA", "M3QD")
        self.assertIsNone(self._item("T6RA")["card"])

    def test_no_ref_has_no_card(self):
        self.assertIsNone(self._item("K7M2")["card"])

    def test_the_id_shape_is_the_contracts(self):
        self.assertEqual(reminders.ref_card_id(" K9AC "), "K9AC")
        self.assertIsNone(reminders.ref_card_id("Task401"))
        self.assertIsNone(reminders.ref_card_id(""))


class TheGate(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        r = self.client.get("/api/reminders")
        self.assertEqual(r.status_code, 404)
        self.assertIn("features.organize", r.json()["detail"])

    # The inherited cases describe a module that is ON; with it off they do not apply.
    def test_the_fixture_reads_in_bucket_order_against_a_fixed_clock(self):
        pass

    def test_a_reminder_carries_its_fields_as_stored(self):
        pass

    def test_a_file_with_no_id_is_not_a_reminder(self):
        pass

    def test_a_hub_that_has_never_had_a_reminder_answers_empty(self):
        pass

    def test_the_folder_is_the_hubs_to_name(self):
        pass
