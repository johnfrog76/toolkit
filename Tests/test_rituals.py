"""Solitaire Agile's GET /api/ritual/standup -- the slot rule, the text, the gate.

The standup is implemented twice, here (agent/solitaire/standup.py) and in the
CLI's Standup, and held to ONE table: Tests/fixtures/rituals/standup.json and
the golden texts beside it, which tkTestToolkit -Rituals asserts from the other
side (docs/modules/solitaire-agile.md, "The file shape, and how a standup is read"). Parity only holds for
the shapes a table has; the web shows ``text`` verbatim, so the goldens are the
parity test for all three halves.

No network: gh and the tier probe are stubbed.

Run:  python3 -m pytest Tests/test_rituals.py
"""

import asyncio
import json
import os
import re
import subprocess
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

    from agent.ado import accounting
    from agent.core import config
    from agent.core import consts as C
    from agent.solitaire import standup
    from agent.solitaire import tracker as solitaire_tracker
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "rituals"
TABLE = json.loads((FIXTURES / "standup.json").read_text(encoding="utf-8"))
VOCAB = json.loads((REPO_ROOT / C.rituals_vocabulary_file()).read_text(encoding="utf-8"))
CASES = {c["name"]: c for c in TABLE["cases"]}


def _labels(case: dict) -> list[dict]:
    return TABLE["workerLabels"] if case["labels"] == "workerLabels" else case["labels"]


def _fill(case: dict) -> "standup.Standup":
    filled = standup.fill_standup(
        datetime.fromisoformat(case["asOf"]), _labels(case), case["issues"], case["tracker"], space="toolkit"
    )
    filled.text = standup.render_standup(filled)
    return filled


def _golden(name: str) -> str:
    # Bytes, not text mode: a CRLF checkout would be translated, and LF is the law.
    return (FIXTURES / name).read_bytes().decode("utf-8")


class TheTable(unittest.TestCase):
    """Every case of the shared fixture, issues in, slots out."""

    def test_since_is_the_start_of_the_previous_working_day(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill(case).since, case["expected"]["since"])

    def test_the_day_of_year_is_the_fixtures(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                self.assertEqual(
                    datetime.fromisoformat(case["asOf"]).timetuple().tm_yday, case["expected"]["dayOfYear"]
                )

    def test_the_chair_speaks_the_phrasebook_at_the_fixtures_indices(self):
        book = VOCAB["phrasebook"]
        for name, case in CASES.items():
            with self.subTest(case=name):
                want = case["expected"]["chair"]
                chair = _fill(case).chair
                self.assertEqual(chair.open, book[want["openIndex"]])
                self.assertEqual(chair.close, book[want["closeIndex"]])

    def test_the_queue(self):
        for name, case in CASES.items():
            with self.subTest(case=name):
                q = _fill(case).queue
                want = case["expected"]["queue"]
                self.assertEqual([i.number for i in q.walk], want["walk"])
                self.assertEqual([i.number for i in q.decide], want["decide"])
                self.assertEqual([i.number for i in q.look], want["look"])

    def test_each_workers_slots_by_number(self):
        for name, case in CASES.items():
            filled = _fill(case)
            want = case["expected"]["workers"]
            with self.subTest(case=name, what="order"):
                self.assertEqual([(w.label, w.name) for w in filled.workers], [(w["label"], w["name"]) for w in want])
            for got, exp in zip(filled.workers, want):
                with self.subTest(case=name, worker=exp["label"]):
                    self.assertEqual([i.number for i in got.yesterday], exp["yesterday"])
                    self.assertEqual([i.number for i in got.today], exp["today"])
                    self.assertEqual([i.number for i in got.blockers], exp["blockers"])
                    self.assertEqual(got.empty, exp["empty"])
                    if exp["nothingIndex"] is None:
                        self.assertEqual(got.excuse, "")
                    else:
                        self.assertEqual(got.excuse, VOCAB["nothing"][exp["nothingIndex"]])

    def test_the_text_is_the_golden_file_byte_for_byte(self):
        for name, case in CASES.items():
            golden = case["expected"]["text"]
            if not golden:
                continue
            with self.subTest(case=name):
                self.assertEqual(_fill(case).text, _golden(golden))

    def test_the_brief_is_the_golden_file_byte_for_byte(self):
        """The chair's reading: every case, including the ones with no long-form golden."""
        for name, case in CASES.items():
            with self.subTest(case=name):
                brief = standup.render_brief(_fill(case))
                self.assertEqual(brief, _golden(case["expected"]["brief"]))
                self.assertTrue(brief.endswith("\n") and not brief.endswith("\n\n") and "\r" not in brief)

    def test_the_real_register_never_says_fake_work(self):
        """D-SA5: a thin day shows the mug and a status, never plausible work -- and never an excuse."""
        for name, case in CASES.items():
            text = _fill(case).text
            for phrase in VOCAB["fakeWork"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, text)

    def test_the_agent_source_never_names_the_fake_work_family(self):
        source = (REPO_ROOT / "agent" / "solitaire" / "standup.py").read_text(encoding="utf-8")
        self.assertNotIn("fakeWork", source)

    def test_the_real_register_never_says_an_excuse(self):
        """#255: the excuses are the nonsense register's, beside fakeWork; the real register's
        worker with nothing says the `nothing` family, in the text and on the wire."""
        for name, case in CASES.items():
            filled = _fill(case)
            for phrase in VOCAB["excuses"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, filled.text)
                    self.assertNotIn(phrase, filled.model_dump_json())
        for name, case in CARD_CASES.items():
            for phrase in VOCAB["excuses"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, _fill_cards(case).text)

    def test_the_agent_source_never_names_the_excuses_family(self):
        source = (REPO_ROOT / "agent" / "solitaire" / "standup.py").read_text(encoding="utf-8")
        self.assertNotIn("excuses", source.replace("excuses are", ""))
        self.assertNotIn('"excuses"', source)

    def test_an_empty_worker_reports_the_nothing_sentence_in_both_registers_of_text(self):
        """#255: empty is the vocabulary's `nothing` line -- 'Nothing on the board for me.
        All green, no blockers.' -- in the worker, the long text, the brief-free work text."""
        want = VOCAB["nothing"][0]
        self.assertEqual(want, "Nothing on the board for me. All green, no blockers.")
        for name in ("friday", "monday"):
            filled = _fill(CASES[name])
            empties = [w for w in filled.workers if w.empty]
            self.assertTrue(empties, name)
            for w in empties:
                self.assertEqual(w.excuse, want)
            self.assertIn(f'Mug        "{want}"', filled.text)

    def test_the_nothing_family_is_picked_deterministically(self):
        """index = (day of year + position) mod length, so a longer family rotates."""
        longer = dict(VOCAB, nothing=["A.", "B.", "C."])
        for as_of, d in (("2026-10-02T09:00:00-04:00", 275), ("2026-10-03T09:00:00-04:00", 276)):
            with mock.patch.object(standup, "vocabulary", return_value=longer):
                labels = [{"name": f"w{i}", "description": C.rituals_worker_label_prefix() + f"W{i}"} for i in range(3)]
                filled = standup.fill_standup(datetime.fromisoformat(as_of), labels, [], {"ok": True, "reason": ""})
            self.assertEqual([w.excuse for w in filled.workers], [longer["nothing"][(d + i) % 3] for i in range(3)])

    def test_the_tracker_reason_is_in_the_text_when_it_does_not_answer(self):
        filled = _fill(CASES["no-tracker"])
        self.assertFalse(filled.tracker.ok)
        self.assertIn(CASES["no-tracker"]["tracker"]["reason"], filled.text)
        self.assertNotIn(C.rituals_text()["queueHeading"], filled.text)


class TheSmallerRules(unittest.TestCase):
    def test_the_worker_name_stops_at_the_separator(self):
        self.assertEqual(standup.worker_name("Routed to Opus -- the crash-through volume"), "Opus")
        self.assertEqual(standup.worker_name("Routed to  Fable  "), "Fable")

    def test_an_issues_worker_is_its_first_worker_label(self):
        issue = {"number": 1, "title": "t", "state": "OPEN", "labels": ["sonnet", "fable"], "closedAt": None, "url": ""}
        filled = standup.fill_standup(
            datetime.fromisoformat("2026-10-02T09:00:00-04:00"), TABLE["workerLabels"], [issue], {"ok": True}
        )
        by = {w.label: [i.number for i in w.today] for w in filled.workers}
        self.assertEqual(by, {"fable": [], "opus": [], "sonnet": [1]})

    def test_gh_label_objects_read_the_same_as_names(self):
        case = CASES["friday"]
        as_objects = [dict(i, labels=[{"name": n, "description": ""} for n in i["labels"]]) for i in case["issues"]]
        filled = standup.fill_standup(
            datetime.fromisoformat(case["asOf"]), TABLE["workerLabels"], as_objects, case["tracker"]
        )
        filled.text = standup.render_standup(filled)
        self.assertEqual(filled.text, _golden("standup-friday.txt"))

    def test_the_window_compares_offsets_not_clock_faces(self):
        # 03:59Z on Thursday 1 October is 23:59 on Wednesday at -04:00: outside.
        as_of = datetime.fromisoformat("2026-10-02T09:00:00-04:00")

        def mk(n, at):
            return {"number": n, "title": "t", "state": "CLOSED", "labels": ["opus"], "closedAt": at, "url": ""}

        filled = standup.fill_standup(
            as_of,
            TABLE["workerLabels"],
            [mk(1, "2026-10-01T03:59:00Z"), mk(2, "2026-10-01T04:00:00Z"), mk(3, "2026-10-02T13:00:01Z")],
            {"ok": True},
        )
        opus = next(w for w in filled.workers if w.label == "opus")
        self.assertEqual([i.number for i in opus.yesterday], [2])

    def test_sunday_reads_back_to_friday(self):
        self.assertEqual(
            standup.previous_working_day_start(datetime.fromisoformat("2026-10-04T10:00:00+01:00")).isoformat(),
            "2026-10-02T00:00:00+01:00",
        )

    def test_the_date_is_invariant_and_unpadded(self):
        self.assertEqual(
            standup.format_date(datetime(2026, 3, 1), C.rituals_text()["dateFormat"]), "Sunday 1 March 2026"
        )


# -- The second source: cards -----------------------------------------
CARDS_TABLE = json.loads((FIXTURES / "standup-cards.json").read_text(encoding="utf-8"))
CARD_CASES = {c["name"]: c for c in CARDS_TABLE["cases"]}


def _fill_cards(case: dict) -> "standup.Standup":
    filled = standup.fill_cards_standup(
        datetime.fromisoformat(case["asOf"]), case["cards"], space=case["space"], space_name=case["spaceName"]
    )
    filled.text = standup.render_standup(filled)
    return filled


class TheCardsTable(unittest.TestCase):
    """Every case of standup-cards.json, cards in, slots out -- the same table
    tkTestToolkit -Rituals asserts against Invoke-P20StandupCardsFill."""

    def test_the_table_has_its_cases(self):
        self.assertEqual(len(CARD_CASES), 4)

    def test_since_and_the_day_of_year(self):
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_cards(case).since, case["expected"]["since"])
                self.assertEqual(
                    datetime.fromisoformat(case["asOf"]).timetuple().tm_yday, case["expected"]["dayOfYear"]
                )

    def test_the_chair(self):
        book = VOCAB["phrasebook"]
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                want, chair = case["expected"]["chair"], _fill_cards(case).chair
                self.assertEqual((chair.open, chair.close), (book[want["openIndex"]], book[want["closeIndex"]]))

    def test_the_source_and_the_tracker(self):
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                filled = _fill_cards(case)
                self.assertEqual(filled.source, "cards")
                self.assertEqual((filled.tracker.ok, filled.tracker.reason), (True, ""))
                self.assertEqual(filled.space, case["space"])

    def test_the_queue_by_card_id(self):
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                q, want = _fill_cards(case).queue, case["expected"]["queue"]
                self.assertEqual([i.id for i in q.walk], want["walk"])
                self.assertEqual([i.id for i in q.decide], want["decide"])
                self.assertEqual([i.id for i in q.look], want["look"])
                for i in q.walk:
                    self.assertIsNone(i.number)
                    self.assertEqual(i.worker, case["expected"]["worker"]["name"])

    def test_one_worker_named_for_the_space(self):
        for name, case in CARD_CASES.items():
            filled, exp = _fill_cards(case), case["expected"]["worker"]
            with self.subTest(case=name):
                self.assertEqual([(w.label, w.name) for w in filled.workers], [(exp["label"], exp["name"])])
                w = filled.workers[0]
                self.assertEqual([i.id for i in w.yesterday], exp["yesterday"])
                self.assertEqual([i.id for i in w.today], exp["today"])
                self.assertEqual([i.id for i in w.blockers], exp["blockers"])
                self.assertEqual(w.empty, exp["empty"])
                want_excuse = "" if exp["nothingIndex"] is None else VOCAB["nothing"][exp["nothingIndex"]]
                self.assertEqual(w.excuse, want_excuse)

    def test_a_card_item_has_an_id_and_a_path_and_no_number_or_url(self):
        filled = _fill_cards(CARD_CASES["friday"])
        item = filled.workers[0].yesterday[0]
        self.assertEqual(
            (item.number, item.id, item.url, item.path), (None, "198", "", "archive/198-fix-the-export.prompt.md")
        )
        self.assertEqual(set(item.model_dump()), ITEM_FIELDS)

    def test_the_text_is_the_golden_file_byte_for_byte(self):
        for name, case in CARD_CASES.items():
            golden = case["expected"]["text"]
            if not golden:
                continue
            with self.subTest(case=name):
                self.assertEqual(_fill_cards(case).text, _golden(golden))

    def test_the_brief_is_the_golden_file_byte_for_byte(self):
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(standup.render_brief(_fill_cards(case)), _golden(case["expected"]["brief"]))

    def test_the_json_round_trip_renders_the_same_text(self):
        for name, case in CARD_CASES.items():
            with self.subTest(case=name):
                filled = _fill_cards(case)
                back = standup.Standup.model_validate(json.loads(filled.model_dump_json(by_alias=True)))
                self.assertEqual(standup.render_standup(back), filled.text)

    def test_the_real_register_never_says_fake_work(self):
        for name, case in CARD_CASES.items():
            text = _fill_cards(case).text
            for phrase in VOCAB["fakeWork"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, text)

    def test_which_source_a_space_chooses(self):
        for row in CARDS_TABLE["sources"]:
            with self.subTest(address=row["address"], status=row["status"]):
                reason = C.rituals_text()[row["reason"]] if row["reason"] else ""
                self.assertEqual(standup.standup_source(row["address"], row["status"]), (row["source"], reason))

    def test_a_cards_title_from_its_heading(self):
        for row in CARDS_TABLE["titles"]:
            with self.subTest(file=row["file"]):
                self.assertEqual(standup.card_title(row["content"], row["file"], row["id"]), row["title"])


# -- Both: issues and cards, joined on the id -------------------------------
JOINED_TABLE = json.loads((FIXTURES / "standup-joined.json").read_text(encoding="utf-8"))
JOINED_CASES = {c["name"]: c for c in JOINED_TABLE["cases"]}


def _fill_joined(case: dict, tracker_state: dict | None = None) -> "standup.Standup":
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(JOINED_TABLE["asOf"]),
        JOINED_TABLE["workerLabels"],
        case["issues"],
        tracker_state or {"ok": True, "reason": ""},
        case["cards"],
        space=JOINED_TABLE["space"],
        space_name=JOINED_TABLE["spaceName"],
    )
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    filled.brief = standup.render_brief(filled)
    return filled


def _ref(item) -> str:
    return f"#{item.number}" if item.number is not None else (item.id or "")


class TheJoinedTable(unittest.TestCase):
    """Every case of standup-joined.json -- the same rows tkTestToolkit -Rituals
    asserts against Invoke-P20StandupJoinedFill."""

    def test_the_table_has_its_shapes(self):
        self.assertEqual(
            list(JOINED_CASES),
            [
                "linked-card-open-issue",
                "linked-card-archived-issue-open",
                "issue-closed-card-current",
                "custom-card-alone",
                "issue-alone",
                "not-billable",
                "together",
            ],
        )

    def test_the_source_and_the_window(self):
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                filled = _fill_joined(case)
                self.assertEqual((filled.source, filled.since), ("both", JOINED_TABLE["since"]))

    def test_the_walk_by_ref(self):
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                self.assertEqual([_ref(i) for i in _fill_joined(case).queue.walk], case["expected"]["walk"])

    def test_every_workers_slots_by_ref(self):
        for name, case in JOINED_CASES.items():
            filled = _fill_joined(case)
            got = [
                {
                    "label": w.label,
                    "name": w.name,
                    **{slot: [_ref(i) for i in getattr(w, slot)] for slot in ("yesterday", "today", "blockers")},
                    "empty": w.empty,
                }
                for w in filled.workers
            ]
            with self.subTest(case=name):
                self.assertEqual(got, case["expected"]["workers"])

    def test_the_check_lines(self):
        t = C.rituals_text()
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                want = [t[c["key"]].replace("{item}", c["item"]) for c in case["expected"]["checks"]]
                self.assertEqual(_fill_joined(case).checks, want)

    def test_the_links(self):
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                got = [{"number": lk.number, "id": lk.id, "lane": lk.lane} for lk in _fill_joined(case).links]
                self.assertEqual(got, case["expected"]["links"])

    def test_the_goldens_byte_for_byte(self):
        for name, case in JOINED_CASES.items():
            exp = case["expected"]
            if not exp.get("text"):
                continue
            filled = _fill_joined(case)
            with self.subTest(case=name, grain="detail"):
                self.assertEqual(filled.text, _golden(exp["text"]))
            with self.subTest(case=name, grain="work"):
                self.assertEqual(filled.work.text, _golden(exp["work"]))
            with self.subTest(case=name, grain="brief"):
                self.assertEqual(filled.brief, _golden(exp["brief"]))

    def test_the_goldens_are_the_scripts(self):
        """Generated, never typed: the regeneration script finds nothing to change."""
        sys.path.insert(0, str(REPO_ROOT / "Tests"))
        import regenerate_joined_goldens as regen

        for name, text in regen.goldens().items():
            with self.subTest(golden=name):
                self.assertEqual(_golden(name), text)

    def test_the_json_round_trip_renders_the_same_texts(self):
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                filled = _fill_joined(case)
                back = standup.Standup.model_validate(json.loads(filled.model_dump_json(by_alias=True)))
                self.assertEqual(
                    (standup.render_standup(back), standup.render_work(back), standup.render_brief(back)),
                    (filled.text, filled.work.text, filled.brief),
                )

    def test_with_no_card_in_play_it_reads_as_the_issues_alone(self):
        """No card: the issues fill's own text, brief and work, only the source says both."""
        friday = CASES["friday"]
        at = datetime.fromisoformat(friday["asOf"])
        alone = standup.fill_standup(at, _labels(friday), friday["issues"], friday["tracker"], space="toolkit")
        joined = standup.fill_joined_standup(
            at, _labels(friday), friday["issues"], friday["tracker"], [], space="toolkit", space_name="Toolkit"
        )
        self.assertEqual(joined.source, "both")
        for render in (standup.render_standup, standup.render_brief):
            with self.subTest(render=render.__name__):
                self.assertEqual(render(joined), render(alone))
        self.assertEqual(joined.work.model_dump(), alone.work.model_dump())

    def test_the_tracker_not_answering_is_the_tracker_line_and_no_card(self):
        filled = _fill_joined(JOINED_CASES["together"], {"ok": False, "reason": "gh did not answer"})
        self.assertEqual((filled.source, filled.workers, filled.checks, filled.links), ("none", [], [], []))
        self.assertNotIn("K7M2", filled.text)

    def test_a_card_round_in_current_is_the_card(self):
        """Rounds share an id: the one in current/ is the card, so an earlier round in
        archive/ is not 'archived while the issue is open'."""
        case = {
            "issues": [{"number": 141, "title": "Build", "state": "OPEN", "labels": ["opus"], "closedAt": None}],
            "cards": [
                {"file": "141-build-r1.prompt.md", "folder": "archive", "status": "Done", "closed": "2026-09-01"},
                {"file": "141-build.prompt.md", "folder": "current", "status": "In Progress", "closed": None},
            ],
        }
        for card in case["cards"]:
            card["id"] = "141"
        filled = _fill_joined(case)
        self.assertEqual(filled.checks, [])
        self.assertEqual([(lk.lane, lk.path) for lk in filled.links], [("In Progress", "current/141-build.prompt.md")])

    def test_the_real_register_never_says_fake_work(self):
        for name, case in JOINED_CASES.items():
            filled = _fill_joined(case)
            for phrase in VOCAB["fakeWork"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, filled.text + filled.work.text + filled.brief)


# -- The work grain (D-TA20) ---------------------------------------------
WORK_TABLE = json.loads((FIXTURES / "standup-work.json").read_text(encoding="utf-8"))
WORK_CASES = {c["name"]: c for c in WORK_TABLE["cases"]}


def _fill_work(case: dict) -> "standup.Standup":
    at = datetime.fromisoformat(case["asOf"])
    if case["source"] == "cards":
        filled = standup.fill_cards_standup(at, case["cards"], space=case["space"], space_name=case["spaceName"])
    else:
        filled = standup.fill_standup(at, WORK_TABLE["workerLabels"], case["issues"], case["tracker"])
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    return filled


class TheWorkTable(unittest.TestCase):
    """Every case and small table of standup-work.json -- the same rows
    tkTestToolkit -Rituals asserts against Group-P20StandupWork."""

    def test_the_table_has_its_cases(self):
        self.assertEqual(set(WORK_CASES), {"friday", "no-tracker", "cards"})

    def test_the_queues_groups(self):
        for name, case in WORK_CASES.items():
            filled = _fill_work(case)
            for kind in ("walk", "decide", "look"):
                with self.subTest(case=name, kind=kind):
                    got = [g.model_dump() for g in getattr(filled.work.queue, kind)]
                    self.assertEqual(got, case["expected"]["queue"][kind])

    def test_each_workers_groups(self):
        for name, case in WORK_CASES.items():
            filled = _fill_work(case)
            want = case["expected"]["workers"]
            with self.subTest(case=name, what="order"):
                self.assertEqual([w.label for w in filled.work.workers], [w["label"] for w in want])
            for got, exp in zip(filled.work.workers, want):
                for slot in ("yesterday", "today", "blockers"):
                    with self.subTest(case=name, worker=exp["label"], slot=slot):
                        self.assertEqual([g.model_dump() for g in getattr(got, slot)], exp[slot])

    def test_the_work_text_is_the_golden_file_byte_for_byte(self):
        for name, case in WORK_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_work(case).work.text, _golden(case["expected"]["text"]))

    def test_the_issues_example_phrases(self):
        """The work grain's own words, as its groups' phrases: "Team Agile, three closed; the Studio, one." --
        the text speaks them as prose (TheProseTable)."""
        opus = next(w for w in _fill_work(WORK_CASES["friday"]).work.workers if w.label == "opus")
        self.assertEqual("; ".join(g.phrase for g in opus.yesterday), "Team Agile, three closed; the Studio, one")
        self.assertEqual("; ".join(g.phrase for g in opus.today), "Team Agile, two")

    def test_the_json_round_trip_renders_the_same_work_text(self):
        for name, case in WORK_CASES.items():
            with self.subTest(case=name):
                filled = _fill_work(case)
                back = standup.Standup.model_validate(json.loads(filled.model_dump_json(by_alias=True)))
                self.assertEqual(standup.render_work(back), filled.work.text)

    def test_the_work_grain_never_says_fake_work(self):
        for name, case in WORK_CASES.items():
            text = _fill_work(case).work.text
            for phrase in VOCAB["fakeWork"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, text)

    def test_a_titles_head(self):
        for row in WORK_TABLE["heads"]:
            with self.subTest(title=row["title"]):
                self.assertEqual(standup.title_head(row["title"]), row["head"])

    def test_what_an_item_belongs_to(self):
        for row in WORK_TABLE["keys"]:
            with self.subTest(milestone=row["milestone"], body=row["body"], type=row["type"]):
                self.assertEqual(
                    standup.work_key(row["milestone"], row["body"], row["type"], row["threads"]),
                    (row["name"], row["by"]),
                )

    def test_a_cards_type(self):
        for row in WORK_TABLE["types"]:
            with self.subTest(content=row["content"]):
                self.assertEqual(standup.card_type(row["content"], row["id"]), row["type"])

    def test_a_count_as_the_voice_says_it(self):
        for row in WORK_TABLE["counts"]:
            with self.subTest(n=row["n"]):
                self.assertEqual(standup.count_word(row["n"]), row["word"])

    def test_the_grains(self):
        self.assertEqual(C.rituals_grains(), ("detail", "work", "brief"))


# -- The prose -----------------------------------------------------------
PROSE_TABLE = json.loads((FIXTURES / "standup-prose.json").read_text(encoding="utf-8"))
PROSE_CASES = {c["name"]: c for c in PROSE_TABLE["cases"]}


def _fill_prose(case: dict) -> "standup.Standup":
    at = datetime.fromisoformat(case["asOf"])
    if case["source"] == "cards":
        filled = standup.fill_cards_standup(at, case["cards"], space=case["space"], space_name=case["spaceName"])
    else:
        filled = standup.fill_standup(at, PROSE_TABLE["workerLabels"], case["issues"], case["tracker"])
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    return filled


class TheProseTable(unittest.TestCase):
    """Every row and case of standup-prose.json -- the same rows tkTestToolkit
    -Rituals asserts against Get-P20StandupProseSentence and Format-P20StandupWork."""

    def test_the_table_has_its_cases(self):
        self.assertEqual(set(PROSE_CASES), {"friday", "quiet", "no-tracker", "cards", "eight-groups"})

    def test_every_fold_row(self):
        """The also-ons fold (D-SA9): one sentence for the groups after today's first --
        their names up to proseFoldNames, the count alone past it; other slots never fold."""
        for row in PROSE_TABLE["folds"]:
            with self.subTest(slot=row["slot"], groups=len(row["groups"])):
                groups = [standup.WorkGroup(**g) for g in row["groups"]]
                self.assertEqual(standup.prose_sentences(row["slot"], groups, row["titles"]), row["sentences"])

    def test_a_folded_sentence_says_no_ref_but_a_group_names_own(self):
        """The thought bubble keeps every number; the folded sentence keeps none of its own."""
        for row in PROSE_TABLE["folds"]:
            groups = [standup.WorkGroup(**g) for g in row["groups"]]
            if not standup.prose_folds(row["slot"], groups):
                continue
            folded = row["sentences"][1]
            refs = {r for g in row["groups"][1:] for r in g["refs"]}
            with self.subTest(sentence=folded):
                self.assertFalse([r for r in refs if re.search(re.escape(r) + r"(?!\d)", folded)], folded)

    def test_the_folds_boundary_is_the_contracts(self):
        rows = [r for r in PROSE_TABLE["folds"] if r["slot"] == "today"]
        rest = {len(r["groups"]) - 1 for r in rows}
        limit = C.rituals_prose_fold_names()
        self.assertTrue({1, 2, limit, limit + 1} <= rest, "a row each side of every edge")

    def test_every_sentence_row(self):
        for row in PROSE_TABLE["sentences"]:
            with self.subTest(sentence=row["sentence"]):
                group = standup.WorkGroup(**row["group"])
                self.assertEqual(
                    standup.prose_sentence(row["slot"], row["first"], group, row["titles"]), row["sentence"]
                )

    def test_the_queues_sentences(self):
        for name, case in PROSE_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_prose(case).work.queueProse, case["expected"]["queue"])

    def test_each_workers_sentences(self):
        for name, case in PROSE_CASES.items():
            got = [{"label": w.label, "prose": w.prose} for w in _fill_prose(case).work.workers]
            with self.subTest(case=name):
                self.assertEqual(got, case["expected"]["workers"])

    def test_the_work_text_is_the_golden_file_byte_for_byte(self):
        for name, case in PROSE_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_prose(case).work.text, _golden(case["expected"]["text"]))

    def test_the_issues_example_sentences(self):
        """The prose grain's own words: "Yesterday I closed two in Team Agile (...). Today I'm on the Studio:
        #<n>, the archived-repository mark. Nothing blocked." -- as this table spells them."""
        text = _fill_prose(PROSE_CASES["friday"]).work.text
        self.assertIn("Opus: Yesterday I closed two in Team Agile (#501, #502). ", text)
        self.assertIn("Fable: Today I'm on the Studio: #511, the archived-repository mark. ", text)
        self.assertIn(" Nothing blocked.\n", text)

    def test_the_json_round_trip_renders_the_same_text(self):
        for name, case in PROSE_CASES.items():
            with self.subTest(case=name):
                filled = _fill_prose(case)
                back = standup.Standup.model_validate(json.loads(filled.model_dump_json(by_alias=True)))
                self.assertEqual(standup.render_work(back), filled.work.text)

    def test_the_prose_never_says_fake_work(self):
        for name, case in PROSE_CASES.items():
            text = _fill_prose(case).work.text
            for phrase in VOCAB["fakeWork"]:
                with self.subTest(case=name, phrase=phrase):
                    self.assertNotIn(phrase, text)

    def test_every_fixed_word_is_the_contracts(self):
        """No sentence adds a word the contract does not hold: strip each row's
        names, refs, numbers and clauses, and what is left is rituals.text's."""
        t = C.rituals_text()
        fixed = " ".join(v for k, v in t.items() if k.startswith("prose"))
        for row in PROSE_TABLE["sentences"]:
            rest = row["sentence"]
            for value in [row["group"]["name"], *row["group"]["refs"], *row["titles"].values()]:
                rest = rest.replace(standup.title_head(value), " ").replace(value, " ")
            for word in re.findall(r"[A-Za-z']+", rest):
                with self.subTest(sentence=row["sentence"], word=word):
                    self.assertTrue(word in fixed or word in C.rituals_number_words(), word)
        for row in PROSE_TABLE["folds"]:
            for sentence in row["sentences"]:
                rest = sentence
                values = [v for g in row["groups"] for v in (g["name"], *g["refs"])] + list(row["titles"].values())
                for value in sorted(values, key=len, reverse=True):
                    rest = rest.replace(standup.title_head(value), " ").replace(value, " ")
                for word in re.findall(r"[A-Za-z']+", rest):
                    with self.subTest(sentence=sentence, word=word):
                        self.assertTrue(word in fixed or word in C.rituals_number_words(), word)


# -- The dress -----------------------------------------------------------
DRESS_TABLE = json.loads((FIXTURES / "standup-dress.json").read_text(encoding="utf-8"))
DRESS_GROUPS = DRESS_TABLE["groups"]


def _unavailable(*_a, **_kw):
    raise standup.model.ModelUnavailable(standup.model.NO_MODEL_KEY_DETAIL)


def _answering(reply: dict):
    """A stub for model.complete that answers ``reply`` as JSON and writes down each call."""
    calls: list[tuple[str, str]] = []

    async def complete(prompt: str, *, system: str, max_tokens: int = 1024) -> str:
        calls.append((system, prompt))
        return "Here you go:\n" + json.dumps(reply)

    return complete, calls


class TheDressTable(unittest.TestCase):
    """Every row of standup-dress.json -- the same rows tkTestToolkit -Rituals asserts
    against Test-P20StandupDress -- and the dress around it, the model stubbed: no
    test here, or anywhere, calls a model."""

    def setUp(self):
        standup._DRESSED.clear()

    def test_every_groups_prose_sentence_passes_its_own_guard(self):
        for g in DRESS_GROUPS:
            with self.subTest(group=g["id"]):
                self.assertEqual(standup.dress_guard(g, g["floor"]), "")

    def test_every_row(self):
        for row in DRESS_TABLE["rows"]:
            with self.subTest(sentence=row["sentence"]):
                self.assertEqual(standup.dress_guard(DRESS_GROUPS[row["group"]], row["sentence"]), row["reason"])

    def test_every_reason_is_a_guard_of_the_contract_and_every_guard_has_a_row(self):
        reasons = {row["reason"] for row in DRESS_TABLE["rows"] if row["reason"]}
        self.assertEqual(reasons, set(C.rituals_dress_guards()))

    def test_the_issues_own_rows(self):
        """The guard rejecting a line that names a number the read lacks; and the comment's
        "ate 20g of protein and smashed 10 bugs" -- the persona's colour passes, the work is counted."""
        g0, g2 = DRESS_GROUPS[0], DRESS_GROUPS[2]
        self.assertEqual(
            standup.dress_guard(g0, "Wired up three in Team Agile (#501, #502, #506) and #999."), "ref-added"
        )
        self.assertEqual(
            standup.dress_guard(
                g2,
                "Ate 20g of protein and smashed 10 bugs in Phase 6 "
                "(#601, #602, #603, #604, #605, #606, #607, #608, #609, #610).",
            ),
            "",
        )

    def test_a_reply_that_names_999_keeps_the_prose_for_that_group(self):
        reply = DRESS_TABLE["reply"]
        filled = standup.Standup(
            work=standup.Work(
                workers=[
                    standup.WorkWorker(
                        label="opus", name="Opus", prose=[g["floor"] for g in DRESS_GROUPS] + ["Nothing blocked."]
                    )
                ]
            )
        )
        spoken = standup.spoken_from(filled, DRESS_GROUPS, reply["answer"], "m")
        self.assertEqual(spoken.workers[0].prose, reply["said"] + ["Nothing blocked."])
        self.assertEqual((spoken.dressed, spoken.refused, spoken.model), (reply["dressed"], reply["refused"], "m"))

    def test_the_facts_are_the_workers_sentences_and_nothing_else(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        facts = standup.dress_facts(filled)
        prose = {w.label: w.prose for w in filled.work.workers}
        self.assertEqual([f["id"] for f in facts], ["fable/0", "fable/1", "fable/2", "opus/0", "opus/1", "opus/2"])
        for f in facts:
            label, at = f["id"].split("/")
            with self.subTest(fact=f["id"]):
                self.assertEqual(f["floor"], prose[label][int(at)])
                self.assertEqual(standup.dress_guard(f, f["floor"]), "")
        said = {f["floor"] for f in facts}
        self.assertNotIn(C.rituals_text()["proseBlockersNone"], said)
        self.assertFalse(said & set(filled.work.queueProse), "the queue's sentences are the chair's, not dressed")
        opus = next(f for f in facts if f["id"] == "opus/0")
        self.assertEqual(
            (opus["name"], opus["count"], opus["refs"], opus["first"], opus["slot"]),
            ("Team Agile", 2, ["#501", "#502"], True, "yesterday"),
        )
        self.assertEqual(opus["titles"]["#501"], "Feature: Team Agile -- wire the stage")

    def test_a_folded_sentence_is_one_fact(self):
        """The dress is handed the folded sentence as it is handed any other: one entry,
        the names it says, the count of its groups, and no ref of its own."""
        filled = _fill_prose(PROSE_CASES["eight-groups"])
        facts = {f["id"]: f for f in standup.dress_facts(filled)}
        prose = {w.label: w.prose for w in filled.work.workers}
        self.assertEqual(
            sorted(facts),
            ["fable/0", "fable/1", "opus/0", "opus/1", "sonnet/0", "sonnet/1", "sonnet/2", "sonnet/3", "sonnet/4"],
        )
        for f in facts.values():
            label, at = f["id"].split("/")
            with self.subTest(fact=f["id"]):
                self.assertEqual(f["floor"], prose[label][int(at)])
                self.assertEqual(standup.dress_guard(f, f["floor"]), "")
        fable, opus = facts["fable/1"], facts["opus/1"]
        self.assertEqual((fable["name"], fable["count"], fable["refs"], fable["first"]), ("", 7, [], False))
        self.assertEqual((opus["name"], opus["count"], opus["refs"]), ("Phase 6, Phase 7, the Studio and Docs", 4, []))
        self.assertEqual(
            standup.dress_guard(opus, "Also chipping at four more: Phase 6, Phase 7, the Studio and Docs."), ""
        )
        self.assertEqual(
            standup.dress_guard(opus, "Also on four more, #712 among them: Phase 6, Phase 7, the Studio and Docs."),
            "ref-added",
        )
        self.assertEqual(standup.dress_guard(fable, "Plus seven more designs on the go."), "")
        self.assertEqual(standup.dress_guard(fable, "Plus eight more designs on the go."), "number")
        thread = standup.dress_facts(_fill_work(WORK_CASES["friday"]))
        folded = next(f for f in thread if f["floor"].startswith("I'm also on two more"))
        self.assertEqual((folded["refs"], standup.dress_guard(folded, folded["floor"])), (["#999"], ""))

    def test_the_kinds_are_counted_from_the_labels_and_a_cards_type(self):
        case = json.loads(json.dumps(PROSE_CASES["friday"]))
        for issue in case["issues"]:
            if issue["number"] in (501, 502):
                issue["labels"].append("bug")
            if issue["number"] == 504:
                issue["labels"].append("enhancement")
        facts = {f["id"]: f for f in standup.dress_facts(_fill_prose(case))}
        self.assertEqual(facts["opus/0"]["kinds"], {"bugs": 2})
        self.assertEqual(facts["opus/2"]["kinds"], {"features": 1})
        self.assertEqual(facts["opus/1"]["kinds"], {})
        cards = {f["id"]: f for f in standup.dress_facts(_fill_prose(PROSE_CASES["cards"]))}
        bug = next(f for f in cards.values() if f["name"] == "Bug")
        self.assertEqual(bug["kinds"], {"bugs": bug["count"]})

    def test_the_prompt_offers_the_verbs_and_never_the_fake_work(self):
        facts = standup.dress_facts(_fill_prose(PROSE_CASES["friday"]))
        system, prompt = standup.dress_prompt(facts)
        for verb in VOCAB["verbs"]:
            self.assertIn(verb, system)
        for family in ("fakeWork", "excuses", "phrasebook"):
            for phrase in VOCAB[family]:
                with self.subTest(family=family, phrase=phrase):
                    self.assertNotIn(phrase, system + prompt)
        self.assertEqual(json.loads(prompt), facts)

    def test_a_model_that_answers_is_dressed_and_guarded(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        complete, calls = _answering(
            {
                "opus/0": "Smashed two in Team Agile (#501, #502).",
                "opus/2": "Plumbing for two in Team Agile (#504, #505), and #999.",
            }
        )
        with mock.patch.object(standup.model, "complete", complete):
            spoken = asyncio.run(standup.dress_standup(filled))
        self.assertEqual(len(calls), 1)
        opus = next(w for w in spoken.workers if w.label == "opus")
        work = next(w for w in filled.work.workers if w.label == "opus")
        self.assertEqual(opus.prose, ["Smashed two in Team Agile (#501, #502).", *work.prose[1:]])
        fable = next(w for w in spoken.workers if w.label == "fable")
        self.assertEqual(fable.prose, next(w for w in filled.work.workers if w.label == "fable").prose)
        self.assertEqual((spoken.dressed, spoken.refused), (1, 5))
        self.assertEqual(
            filled.work.text, _golden(PROSE_CASES["friday"]["expected"]["text"]), "the work text is untouched"
        )

    def test_the_same_groups_are_dressed_once(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        complete, calls = _answering({"opus/0": "Smashed two in Team Agile (#501, #502)."})
        with mock.patch.object(standup.model, "complete", complete):
            first = asyncio.run(standup.dress_standup(filled))
            second = asyncio.run(standup.dress_standup(_fill_prose(PROSE_CASES["friday"])))
        self.assertEqual(len(calls), 1)
        self.assertEqual(first, second)

    def test_no_key_is_the_prose_never_silence(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "", "CLAUDE_API_KEY": ""}):
            self.assertIsNone(asyncio.run(standup.dress_standup(filled)))
        self.assertEqual(filled.work.text, _golden(PROSE_CASES["friday"]["expected"]["text"]))
        self.assertEqual(standup._DRESSED, {}, "a decline is not cached")

    def test_a_model_that_fails_is_the_prose(self):
        async def broken(*_a, **_kw):
            raise RuntimeError("the API said no")

        with mock.patch.object(standup.model, "complete", broken):
            self.assertIsNone(asyncio.run(standup.dress_standup(_fill_prose(PROSE_CASES["friday"]))))

    def test_nothing_to_dress_asks_nothing(self):
        complete, calls = _answering({})
        with mock.patch.object(standup.model, "complete", complete):
            self.assertIsNone(asyncio.run(standup.dress_standup(_fill_prose(PROSE_CASES["no-tracker"]))))
        self.assertEqual(calls, [])

    def test_a_reply_that_is_not_json_says_the_prose(self):
        async def chatty(*_a, **_kw):
            return "Sure! Here is a standup."

        filled = _fill_prose(PROSE_CASES["friday"])
        with mock.patch.object(standup.model, "complete", chatty):
            spoken = asyncio.run(standup.dress_standup(filled))
        self.assertEqual([w.prose for w in spoken.workers], [w.prose for w in filled.work.workers])
        self.assertEqual(spoken.dressed, 0)


class TheCardReader(unittest.TestCase):
    """read_cards, the thin layer: a real folder pair into the rows the fill takes."""

    def test_state_closed_title_id_and_what_is_not_a_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp)
            (space / "current").mkdir()
            (space / "archive").mkdir()
            files = {
                "current/K7M2-wire-the-board.prompt.md": "# Task K7M2: Wire the board\n\n- [x] a\n",
                "current/Task139-write-the-docs.prompt.md": "# Task 139: Write the docs\n\n- a41c2e9 first\n",
                "current/US-144-read-the-board.prompt.md": "# User Story 144: Read the board\r\n\r\nPR URL: https://example.com/pr/1\r\n",
                "current/notes.md": "# Just a note\n",
                "current/.hidden.prompt.md": "# Hidden\n",
                "archive/198-fix-the-export.prompt.md": "# Bug 198: Fix the export\n\n**Closed:** 2026-10-01\n",
                "archive/151-never-stamped.prompt.md": "# Bug 151: Never stamped\n",
                "archive/2026-05-14-PR141415.prompt.md": "# PR comments\n\n**Closed:** 2026-10-01\n",
                "archive/160-off-the-clock.prompt.md": (
                    "# Bug 160: Off the clock\n\n**Billable:** no\n**Closed:** 2026-10-01\n"
                ),
            }
            for rel, text in files.items():
                (space / rel).write_bytes(text.encode("utf-8"))
            rows = standup.read_cards(
                space, ["User Story", "Task", "Feature", "Bug", "Spike"], ["US-", "Task", "Feat-", "", "Spike-"]
            )
        # A card that says **Billable:** no reads billable False -- the card model's own reader.
        off_the_clock = {r["file"] for r in rows if not r["billable"]}
        self.assertEqual(off_the_clock, {"160-off-the-clock.prompt.md"}, "only the card that says no")
        rows = [r for r in rows if r["file"] != "160-off-the-clock.prompt.md"]
        got = {r["file"]: (r["folder"], r["status"], r["closed"], r["title"], r["id"]) for r in rows}
        # The work grain reads each card's type and body.
        self.assertEqual({r["file"]: r["type"] for r in rows}["Task139-write-the-docs.prompt.md"], "Task")
        self.assertTrue(all(r["body"] for r in rows))
        self.assertEqual(
            got,
            {
                "K7M2-wire-the-board.prompt.md": ("current", "Active", None, "Wire the board", "K7M2"),
                "Task139-write-the-docs.prompt.md": ("current", "In Progress", None, "Write the docs", "139"),
                "US-144-read-the-board.prompt.md": ("current", "Code Review", None, "Read the board", "144"),
                "198-fix-the-export.prompt.md": ("archive", "Done", "2026-10-01", "Fix the export", "198"),
                "151-never-stamped.prompt.md": ("archive", "Done", None, "Never stamped", "151"),
            },
        )

    def test_a_space_with_no_folders_is_no_cards(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(standup.read_cards(Path(tmp) / "missing", [], []), [])


# The response's field names, exactly as the contract's JSON spells them.
TOP_FIELDS = {
    "ceremony",
    "register",
    "asOf",
    "since",
    "space",
    "source",
    "tracker",
    "chair",
    "queue",
    "workers",
    "work",
    "spoken",
    "text",
    "brief",
    "checks",
    "links",
}
WORK_FIELDS = {"queue", "workers", "queueProse", "text"}
GROUP_FIELDS = {"name", "by", "count", "refs", "phrase"}
WORKER_FIELDS = {"label", "name", "yesterday", "today", "blockers", "empty", "excuse"}
WALK_FIELDS = {"number", "id", "title", "url", "path", "worker"}
ITEM_FIELDS = {"number", "id", "title", "url", "path"}

TOOLKIT = "https://github.com/johnfrog76/toolkit"
ACME = "https://dev.azure.com/acme"


def _cp1252_console(payload):
    """Stand in for ``subprocess.run`` the way CPython runs it on a Windows console
    whose code page is cp1252. ``payload(argv)`` is the child's UTF-8 bytes.
    With an ``encoding`` the bytes are decoded with it; with bare ``text=True`` they
    are decoded as cp1252, and a byte cp1252 cannot map kills the reader thread --
    the call then comes back exit 0 with ``stdout=None``, which is what it did."""

    def run(argv, **kw):
        raw = payload(argv)
        if kw.get("encoding"):
            out = raw.decode(kw["encoding"], kw.get("errors") or "strict")
        elif kw.get("text"):
            try:
                out = raw.decode("cp1252")
            except UnicodeDecodeError:
                out = None
        else:
            out = raw
        return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="" if out is not None else None)

    return run


class TheRoute(unittest.TestCase):
    features = {"solitaireAgile": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        hub = base / "hub"
        (hub / "toolkit" / "current").mkdir(parents=True)
        default = base / "config.default.json"
        local = base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "toolkit",
                    "features": self.features,
                    "promptsRoot": str(hub),
                    "spaces": [
                        # Answered with agents: Team Agile's routes answer only
                        # where the active Space works with agents.
                        {
                            "slug": "toolkit",
                            "status": "active",
                            "promptsFolder": "toolkit",
                            "org": TOOLKIT,
                            "howIWork": "agents",
                        },
                        {"slug": "solo", "name": "Solo Work", "status": "local", "promptsFolder": "solo", "org": ""},
                        {
                            "slug": "acme",
                            "status": "active",
                            "promptsFolder": "acme",
                            "org": ACME,
                            "projects": [{"name": "Platform", "repo": "platform"}],
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        local.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        for var in ("PROMPTS_ROOT", C.env_active_space(), C.env_features()):
            os.environ.pop(var, None)
        app = FastAPI()
        app.include_router(standup.api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def _get(self, path: str, case: str = "friday", tier: int = 1, gh_fails: bool = False, complete=_unavailable):
        # The model is ALWAYS stubbed: a machine with a real key in its
        # environment must not call a model from a test. Unavailable by default.
        standup._DRESSED.clear()
        fx = CASES[case]
        calls: list[list[str]] = []

        def fake_run(argv, **_kw):
            calls.append(list(argv))
            if gh_fails:
                raise subprocess.TimeoutExpired(argv, 30)
            if argv[:3] == ["gh", "label", "list"]:
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(_labels(fx)), stderr="")
            issues = [dict(i, labels=[{"name": n} for n in i["labels"]]) for i in fx["issues"]]
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(issues), stderr="")

        with (
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(tier, True)),
            mock.patch.object(standup, "_now", return_value=datetime.fromisoformat(fx["asOf"])),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
            mock.patch.object(standup.model, "complete", complete),
        ):
            res = self.client.get(path)
        return res, calls

    def test_no_model_key_is_spoken_null_and_the_prose_stands(self):
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertIsNone(body["spoken"])
        filled = _fill(CASES["friday"])
        filled.work.text = standup.render_work(filled)
        self.assertEqual(body["work"]["text"], filled.work.text)

    def test_a_model_that_answers_is_spoken_beside_work_and_text_and_brief_are_untouched(self):
        filled = _fill(CASES["friday"])
        facts = standup.dress_facts(filled)
        self.assertGreater(len(facts), 1)
        complete, calls = _answering(
            {
                facts[0]["id"]: "Ate 20g of protein. " + facts[0]["floor"],
                facts[-1]["id"]: facts[-1]["floor"] + " And #999.",
            }
        )
        body = self._get("/api/ritual/standup?space=toolkit", complete=complete)[0].json()
        self.assertEqual(len(calls), 1)
        self.assertEqual(set(body["spoken"]), {"model", "workers", "dressed", "refused"})
        self.assertEqual((body["spoken"]["dressed"], body["spoken"]["refused"]), (1, len(facts) - 1))
        self.assertEqual([w["label"] for w in body["spoken"]["workers"]], [w["label"] for w in body["work"]["workers"]])
        said = [s for w in body["spoken"]["workers"] for s in w["prose"]]
        self.assertNotIn("#999", " ".join(said))
        self.assertEqual(body["text"], _golden("standup-friday.txt"))
        self.assertEqual(body["brief"], _golden("standup-friday.brief.txt"))
        self.assertEqual(body["register"], "real", "dressed facts are still facts")

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_route(), "/api/ritual/standup")

    def test_on_it_answers_the_fixtures_friday_byte_for_byte(self):
        res, calls = self._get("/api/ritual/standup?space=toolkit")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["text"], _golden("standup-friday.txt"))
        self.assertEqual(body["brief"], _golden("standup-friday.brief.txt"))
        self.assertEqual((body["ceremony"], body["register"], body["space"]), ("standup", "real", "toolkit"))
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        # An active GitHub Space reads both; with no card in its folders the text is the issues' alone.
        self.assertEqual(body["source"], "both")
        self.assertEqual((body["checks"], body["links"]), ([], []))
        self.assertEqual([c[:3] for c in calls], [["gh", "label", "list"], ["gh", "issue", "list"]])
        self.assertIn("johnfrog76/toolkit", calls[0])
        self.assertIn("all", calls[1])
        # The work grain reads the milestone and the body.
        fields = calls[1][calls[1].index("--json") + 1].split(",")
        self.assertIn("milestone", fields)
        self.assertIn("body", fields)
        filled = _fill(CASES["friday"])
        filled.work.text = standup.render_work(filled)
        self.assertEqual(body["work"]["text"], filled.work.text)

    def test_the_response_field_names_are_section_4bs(self):
        body = self._get("/api/ritual/standup")[0].json()
        self.assertEqual(set(body), TOP_FIELDS)
        self.assertEqual(set(body["tracker"]), {"ok", "reason"})
        self.assertEqual(set(body["chair"]), {"open", "close"})
        self.assertEqual(set(body["queue"]), {"walk", "decide", "look"})
        self.assertEqual(set(body["queue"]["walk"][0]), WALK_FIELDS)
        self.assertEqual(set(body["work"]), WORK_FIELDS)
        self.assertEqual(set(body["work"]["queue"]), {"walk", "decide", "look"})
        self.assertEqual(set(body["work"]["queue"]["walk"][0]), GROUP_FIELDS)
        for w in body["work"]["workers"]:
            self.assertEqual(set(w), {"label", "name", "yesterday", "today", "blockers", "prose"})
        self.assertEqual(body["queue"]["walk"][0]["worker"], "Fable")
        self.assertEqual(body["queue"]["walk"][1]["worker"], "")
        for w in body["workers"]:
            self.assertEqual(set(w), WORKER_FIELDS)
            for slot in ("yesterday", "today", "blockers"):
                for item in w[slot]:
                    self.assertEqual(set(item), ITEM_FIELDS)

    def test_no_space_is_the_active_one(self):
        body = self._get("/api/ritual/standup")[0].json()
        self.assertEqual(body["space"], "toolkit")

    def test_an_ado_space_is_still_a_standup_and_gh_is_never_asked(self):
        res, calls = self._get("/api/ritual/standup?space=acme")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertTrue(body["tracker"]["reason"])
        self.assertEqual((body["workers"], body["queue"]["walk"]), ([], []))
        self.assertIn(body["tracker"]["reason"], body["text"])
        self.assertTrue(body["chair"]["open"] and body["chair"]["close"])
        self.assertEqual(calls, [])
        # D-TA19: the reason is the contract's sentence, and no card is read for it.
        self.assertEqual(body["tracker"]["reason"], C.rituals_text()["adoTracker"])
        self.assertEqual(body["source"], "none")

    def test_a_local_space_fills_from_its_cards_and_gh_is_never_asked(self):
        hub = Path(self.tmp.name) / "hub" / "solo"
        (hub / "current").mkdir(parents=True)
        (hub / "archive").mkdir(parents=True)
        (hub / "current" / "K7M2-wire-the-board.prompt.md").write_text(
            "# Task K7M2: Wire the board\n\n---\n\n**Review:** 2026-10-01\n", encoding="utf-8"
        )
        (hub / "archive" / "198-fix-the-export.prompt.md").write_text(
            "# Bug 198: Fix the export\n\n---\n\n**Closed:** 2026-10-01\n", encoding="utf-8"
        )
        res, calls = self._get("/api/ritual/standup?space=solo")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(calls, [])
        self.assertEqual((body["source"], body["tracker"]), ("cards", {"ok": True, "reason": ""}))
        self.assertEqual([(w["label"], w["name"]) for w in body["workers"]], [("solo", "Solo Work")])
        self.assertEqual([i["id"] for i in body["queue"]["walk"]], ["K7M2"])
        self.assertEqual(set(body["queue"]["walk"][0]), WALK_FIELDS)
        item = body["workers"][0]["yesterday"][0]
        self.assertEqual(set(item), ITEM_FIELDS)
        self.assertEqual((item["number"], item["id"], item["url"]), (None, "198", ""))
        self.assertTrue(item["path"].endswith("198-fix-the-export.prompt.md"))
        self.assertIn("  Walk       K7M2 Wire the board\n", body["text"])
        self.assertIn("  Yesterday  198 Fix the export\n", body["text"])

    def test_a_github_space_joins_its_cards_to_its_issues(self):
        """The both source over real folders: a card of its own is a row under you, a
        card linked to a closed issue is a Check line, a not-billable card is nothing,
        and the hub is read, never written."""
        hub = Path(self.tmp.name) / "hub" / "toolkit"
        (hub / "archive").mkdir(parents=True)
        cards = {
            "current/K7M2-wire-the-board.prompt.md": "# Task K7M2: Wire the board\n\n- a41c2e9 first\n",
            # 102 is CLOSED in the friday case.
            "current/102-rename-the-slug.prompt.md": "# Task 102: Rename the slug\n\n- b52d3f0 first\n",
            "current/C4D7-bench.prompt.md": "# Task C4D7: Bench\n\n- c63e4a1 first\n\n**Billable:** no\n",
        }
        for rel, text in cards.items():
            (hub / rel).write_text(text, encoding="utf-8")
        before = {f: f.stat().st_mtime_ns for f in hub.rglob("*") if f.is_file()}
        res, calls = self._get("/api/ritual/standup?space=toolkit")
        self.assertEqual(res.status_code, 200, res.text)
        body = res.json()
        self.assertEqual(body["source"], "both")
        self.assertEqual([c[:3] for c in calls], [["gh", "label", "list"], ["gh", "issue", "list"]])
        self.assertEqual(body["workers"][-1]["label"], "toolkit")
        self.assertEqual([i["id"] for i in body["workers"][-1]["today"]], ["K7M2"])
        self.assertNotIn("C4D7", body["text"])
        self.assertEqual([(lk["number"], lk["id"], lk["lane"]) for lk in body["links"]], [(102, "102", "In Progress")])
        item = "#102 Rename the slug"
        self.assertEqual(body["checks"], [C.rituals_text()["checkIssueClosed"].replace("{item}", item)])
        self.assertIn(f"  Check      {body['checks'][0]}\n", body["text"])
        self.assertEqual(before, {f: f.stat().st_mtime_ns for f in hub.rglob("*") if f.is_file()})

    def test_below_tier_1_is_still_a_standup(self):
        res, calls = self._get("/api/ritual/standup?space=toolkit", tier=2)
        self.assertEqual(res.status_code, 200)
        self.assertFalse(res.json()["tracker"]["ok"])
        self.assertEqual(calls, [])

    def test_gh_not_answering_is_the_no_tracker_golden(self):
        res, _calls = self._get("/api/ritual/standup?space=toolkit", gh_fails=True)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(
            body["tracker"], {"ok": False, "reason": "johnfrog76/toolkit: gh did not answer (TimeoutExpired)"}
        )
        # The golden's reason has no repo in front of it; otherwise the bytes are the same.
        self.assertEqual(body["text"].replace("johnfrog76/toolkit: ", ""), _golden("standup-no-tracker.txt"))

    # -- on Windows the child is read as UTF-8, and an unreadable answer is not empty --
    def _get_windows(self, path: str, run):
        fx = CASES["friday"]
        with (
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(standup, "_now", return_value=datetime.fromisoformat(fx["asOf"])),
            mock.patch.object(accounting.subprocess, "run", side_effect=run),
        ):
            return self.client.get(path)

    def test_on_a_cp1252_console_the_issues_are_read_whole(self):
        # The friday table's issue 101 carries an em dash, curly quotes and U+00CF, whose UTF-8
        # (C3 8F) has a byte cp1252 has no character for -- the one that killed the read.
        fx = CASES["friday"]
        self.assertIn("\u00cf", fx["issues"][0]["title"])
        issues = [
            dict(
                i,
                labels=[{"name": n} for n in i["labels"]],
                body="Seen on the PC \u2014 \u201cit\u2019s empty\u201d \u00cf",
            )
            for i in fx["issues"]
        ]

        def gh(argv):
            rows = _labels(fx) if argv[:3] == ["gh", "label", "list"] else issues
            return json.dumps(rows, ensure_ascii=False).encode("utf-8")

        res = self._get_windows("/api/ritual/standup?space=toolkit", _cp1252_console(gh))
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual(body["text"], _golden("standup-friday.txt"))
        self.assertIn("#101 Build the foyer counts \u2014 Chlo\u00e9\u2019s \u201c\u00cfle\u201d row\n", body["text"])
        opus = next(w for w in body["workers"] if w["label"] == "opus")
        self.assertEqual([i["title"] for i in opus["today"]], [fx["issues"][0]["title"]])

    def test_an_answer_that_could_not_be_read_is_not_an_empty_success(self):
        def dead_reader(argv, **_kw):
            # What CPython hands back when its reader thread raised: exit 0, no stdout.
            return subprocess.CompletedProcess(argv, 0, stdout=None, stderr=None)

        res = self._get_windows("/api/ritual/standup?space=toolkit", dead_reader)
        self.assertEqual(res.status_code, 200)
        tracker = res.json()["tracker"]
        self.assertFalse(tracker["ok"])
        self.assertEqual(tracker["reason"], "johnfrog76/toolkit: gh's output could not be read (exit code 0)")

    def test_a_reader_that_raises_is_a_tracker_that_did_not_answer(self):
        with mock.patch.object(accounting, "_gh_labels", side_effect=ValueError("boom")):
            res = self._get_windows("/api/ritual/standup?space=toolkit", lambda argv, **_kw: None)
        tracker = res.json()["tracker"]
        self.assertFalse(tracker["ok"])
        self.assertEqual(tracker["reason"], "The tracker read failed: ValueError: boom")

    def test_an_unknown_space_is_404_naming_it(self):
        res, calls = self._get("/api/ritual/standup?space=nowhere")
        self.assertEqual(res.status_code, 404)
        self.assertIn("nowhere", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_nothing_is_written_to_the_hub(self):
        hub = Path(self.tmp.name) / "hub"
        before = sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*"))
        self._get("/api/ritual/standup")
        self.assertEqual(sorted(p.relative_to(hub).as_posix() for p in hub.rglob("*")), before)


class TheRouteWithTheFlagOff(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        res, calls = self._get("/api/ritual/standup?space=toolkit")
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_the_flag_is_read_per_request(self):
        self.assertEqual(self._get("/api/ritual/standup")[0].status_code, 404)
        with mock.patch.dict(os.environ, {C.env_features(): json.dumps({"solitaireAgile": True})}):
            self.assertEqual(self._get("/api/ritual/standup")[0].status_code, 200)

    # Every on-only assertion is skipped by name rather than inherited into a 404.
    test_on_it_answers_the_fixtures_friday_byte_for_byte = None
    test_the_response_field_names_are_section_4bs = None
    test_no_space_is_the_active_one = None
    test_an_ado_space_is_still_a_standup_and_gh_is_never_asked = None
    test_a_local_space_fills_from_its_cards_and_gh_is_never_asked = None
    test_below_tier_1_is_still_a_standup = None
    test_gh_not_answering_is_the_no_tracker_golden = None
    test_an_unknown_space_is_404_naming_it = None
    test_no_model_key_is_spoken_null_and_the_prose_stands = None
    test_a_model_that_answers_is_spoken_beside_work_and_text_and_brief_are_untouched = None
    test_on_a_cp1252_console_the_issues_are_read_whole = None
    test_an_answer_that_could_not_be_read_is_not_an_empty_success = None
    test_a_reader_that_raises_is_a_tracker_that_did_not_answer = None
    test_a_github_space_joins_its_cards_to_its_issues = None


class TheAppMountsIt(unittest.TestCase):
    def test_the_app_serves_the_route(self):
        from agent.app import app

        paths = set(
            app.openapi()["paths"]
        )  # fastapi >=0.142 includes routers lazily, so app.routes no longer lists them
        self.assertIn(C.rituals_route(), paths)


if __name__ == "__main__":
    unittest.main(verbosity=2)
