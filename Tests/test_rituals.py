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
from datetime import datetime, timedelta
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
    from agent.core import config, disk_cache
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


def _fill(case: dict, size=None) -> "standup.Standup":
    filled = standup.fill_standup(
        datetime.fromisoformat(case["asOf"]),
        _labels(case),
        case["issues"],
        case["tracker"],
        space="toolkit",
        size=size,
    )
    filled.text = standup.render_standup(filled)
    return filled


def _fill_route(case: dict, size=None) -> "standup.Standup":
    """What the route fills for the toolkit Space with no card in its folders: the
    joined fill over the case's read -- the labelled workers' rows, and the
    engineer's, idle, named for the Space (its slug: the test Space has no name)."""
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(case["asOf"]),
        _labels(case),
        case["issues"],
        case["tracker"],
        [],
        space="toolkit",
        size=size,
    )
    filled.text = standup.render_standup(filled)
    return filled


def _less_engineer(text: str, name: str) -> str:
    """A rendering with the engineer's rows set aside: the detail's block under
    ``name`` (the name line and its indented rows) and the brief's ``name: ...``
    line. What is left is the labelled workers' own, which the issues fill's
    goldens hold byte for byte."""
    out: list[str] = []
    skipping = False
    for line in text.split("\n"):
        if line == name:
            skipping = True
            continue
        if skipping and line.startswith("  "):
            continue
        skipping = False
        if line.startswith(name + ": "):
            continue
        out.append(line)
    return "\n".join(out)


REASONS = json.loads((FIXTURES / "tracker-reasons.json").read_text(encoding="utf-8"))
NOTHING_BANNED = json.loads((FIXTURES / "standup-nothing-banned.json").read_text(encoding="utf-8"))["words"]


def _tracker_word(line: str) -> str:
    """The first standup-nothing-banned.json word ``line`` holds, whole word, any case; "" for none."""
    for word in NOTHING_BANNED:
        if re.search(r"\b" + r"\s+".join(re.escape(part) for part in word.split()) + r"\b", line, re.IGNORECASE):
            return word
    return ""


def _idle_said(exp: dict) -> tuple[str, list[str]]:
    """A fixture worker row's ``excuse`` and ``status``, from its two indexes: an idle
    worker says nothing[nothingIndex] and nothingToday[nothingTodayIndex], and its
    excuse is the first; a worker with something to say has neither."""
    if exp["nothingIndex"] is None:
        assert exp["nothingTodayIndex"] is None, exp
        return "", []
    pair = [VOCAB["nothing"][exp["nothingIndex"]], VOCAB["nothingToday"][exp["nothingTodayIndex"]]]
    return pair[0], pair


def _indexes(w) -> dict:
    """A filled worker's two indexes into the made-up families, as a fixture row states them."""
    if not w.status:
        return {"nothingIndex": None, "nothingTodayIndex": None}
    return {
        "nothingIndex": VOCAB["nothing"].index(w.status[0]),
        "nothingTodayIndex": VOCAB["nothingToday"].index(w.status[1]),
    }


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
                    self.assertEqual((got.excuse, got.status), _idle_said(exp))

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
        """Empty is two made-up items, the vocabulary's `nothing` line and its `nothingToday`
        line, each at (day of year + position) mod its own length -- on the wire as
        ``status``, with ``excuse`` its first, which the long text says; two idle workers on
        one day say different lines."""
        nothing, today = VOCAB["nothing"], VOCAB["nothingToday"]
        for name in ("friday", "monday"):
            case = CASES[name]
            d = case["expected"]["dayOfYear"]
            filled = _fill(case)
            empties = [(i, w) for i, w in enumerate(filled.workers) if w.empty]
            self.assertTrue(empties, name)
            for i, w in empties:
                with self.subTest(case=name, worker=w.label):
                    self.assertEqual(w.status, [nothing[(d + i) % len(nothing)], today[(d + i) % len(today)]])
                    self.assertEqual(w.excuse, w.status[0])
                    row = C.rituals_text()["mug"].ljust(C.rituals_label_width())
                    self.assertIn(f'  {row}  "{w.excuse}"', filled.text)
        monday = [w.status for w in _fill(CASES["monday"]).workers if w.empty]
        self.assertEqual(len(monday), 2)
        self.assertNotEqual(monday[0][0], monday[1][0])
        self.assertNotEqual(monday[0][1], monday[1][1])
        for w in _fill(CASES["friday"]).workers:
            if not w.empty:
                with self.subTest(worker=w.label):
                    self.assertEqual((w.excuse, w.status), ("", []))

    def test_no_nothing_line_claims_tracker_work(self):
        """A `nothing` or `nothingToday` line is the day around the work and never names what
        the tracker would show -- no word of standup-nothing-banned.json, whole word, any case;
        the same list tkTestToolkit -Rituals reads. Each family has more than one line, and none
        twice, so the pick rotates."""
        self.assertTrue(NOTHING_BANNED)
        for family in ("nothing", "nothingToday"):
            lines = VOCAB[family]
            with self.subTest(family=family):
                self.assertGreater(len(lines), 1)
                self.assertEqual(len(lines), len(set(lines)), f"a {family} line appears twice")
            for line in lines:
                with self.subTest(family=family, line=line):
                    self.assertEqual(_tracker_word(line), "", line)

    def test_the_two_made_up_families_are_apart_and_never_in_step(self):
        """A worker's yesterday and today are two different items: no sentence is in both
        families, and their lengths share no factor, so the pair a worker says does not
        repeat in step."""
        from math import gcd

        nothing, today = VOCAB["nothing"], VOCAB["nothingToday"]
        self.assertEqual(sorted(set(nothing) & set(today)), [])
        self.assertEqual(gcd(len(nothing), len(today)), 1, (len(nothing), len(today)))

    def test_the_tracker_word_guard_has_teeth(self):
        """The guard's own rule over made-up lines: a banned word anywhere, in any case, is caught;
        a word that only contains one is not."""
        for line in ("Opened a PR.", "Went over the  Pull  Request.", "Two cards moved.", "Ran the tests."):
            with self.subTest(line=line):
                self.assertNotEqual(_tracker_word(line), "")
        for line in ("Fixed my standing desk.", "Fixed my PATH.", "Read the protest notes.", "Carded nothing."):
            with self.subTest(line=line):
                self.assertEqual(_tracker_word(line), "")

    def test_the_nothing_family_is_picked_deterministically(self):
        """index = (day of year + position) mod length, each family by its own length, so a
        longer family rotates; the cards tile is picked by its position the same way."""
        longer = dict(VOCAB, nothing=["A.", "B.", "C."], nothingToday=["X.", "Y."])
        for as_of, d in (("2026-10-02T09:00:00-04:00", 275), ("2026-10-03T09:00:00-04:00", 276)):
            with mock.patch.object(standup, "vocabulary", return_value=longer):
                labels = [{"name": f"w{i}", "description": C.rituals_worker_label_prefix() + f"W{i}"} for i in range(3)]
                filled = standup.fill_standup(datetime.fromisoformat(as_of), labels, [], {"ok": True, "reason": ""})
                cards = standup.fill_cards_standup(datetime.fromisoformat(as_of), [], space="widgets")
            want = [[longer["nothing"][(d + i) % 3], longer["nothingToday"][(d + i) % 2]] for i in range(3)]
            self.assertEqual([w.status for w in filled.workers], want)
            self.assertEqual([w.excuse for w in filled.workers], [p[0] for p in want])
            self.assertEqual([w.status for w in cards.workers], want[:1])
        later = [standup.Worker(label=f"w{i}", name=f"W{i}", empty=True) for i in range(3)]
        standup.set_idle(later, 275, longer)
        self.assertEqual([w.status for w in later], [["C.", "Y."], ["A.", "X."], ["B.", "Y."]])
        without = [standup.Worker(label="w", name="W", empty=True)]
        standup.set_idle(without, 275, dict(longer, nothingToday=[]))
        self.assertEqual((without[0].excuse, without[0].status), ("", []))

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
                self.assertEqual((w.excuse, w.status), _idle_said(exp))

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

    # -- why the tracker was not read: Tests/fixtures/rituals/tracker-reasons.json,
    # the SAME rows Tests/Test-Rituals.ps1 asserts from the CLI.
    def test_every_tracker_key_has_a_reason_row(self):
        keys = {k for k in C.rituals_text() if re.match(r"^tracker[A-Z]", k) or k == "adoTracker"}
        self.assertEqual(keys, {row["key"] for row in REASONS["rows"]})

    def test_every_reason_says_its_line_from_its_key(self):
        for row in REASONS["rows"]:
            with self.subTest(reason=row["reason"]):
                self.assertEqual(solitaire_tracker.tracker_reason(row["key"], **row["values"]), row["line"])

    def test_the_gh_reader_says_each_failure_as_its_row(self):
        repo = REASONS["repo"]
        for row in REASONS["rows"]:
            if "gh" not in row or "agent" not in row["halves"]:
                continue
            gh = row["gh"]

            def run(argv, _timeout, gh=gh, **_kw):
                if "raises" in gh:
                    raise getattr(subprocess, gh["raises"])(argv, 30)
                return subprocess.CompletedProcess(argv, gh["exit"], gh.get("stdout", ""), gh.get("stderr", ""))

            with self.subTest(reason=row["reason"]), mock.patch.object(accounting, "run_read", side_effect=run):
                solitaire_tracker.forget()
                self.assertEqual(solitaire_tracker.labels(repo, refresh=True), ([], row["line"]))
                self.assertEqual(solitaire_tracker.issues(repo, "all", body=True, refresh=True), ([], row["line"]))

    def test_no_gh_to_run_is_the_missing_row(self):
        line = next(r["line"] for r in REASONS["rows"] if r["reason"] == "gh-missing")
        with mock.patch.object(accounting, "run_read", side_effect=FileNotFoundError("gh")):
            solitaire_tracker.forget()
            self.assertEqual(solitaire_tracker.labels(REASONS["repo"], refresh=True), ([], line))

    def test_the_checks_before_gh_say_their_rows(self):
        lines = {r["reason"]: r for r in REASONS["rows"]}
        with mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(1, True)):
            row = lines["no-repo"]
            got = solitaire_tracker.github_repos(row["target"]["org"], "active", [], ritual="the standup")
            self.assertEqual(got, ([], {"ok": False, "reason": row["line"]}))
            got = solitaire_tracker.github_repos("https://dev.azure.com/acme-org", "active", [], ritual="triage")
            self.assertEqual(got, ([], {"ok": False, "reason": lines["not-github"]["line"]}))
        with mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(2, False)):
            got = solitaire_tracker.github_repos("https://github.com/acme/widgets", "active", [], ritual="the standup")
            self.assertEqual(got, ([], {"ok": False, "reason": lines["tier"]["line"]}))
        with (
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(accounting, "_gh_labels", side_effect=ValueError("boom")),
        ):
            got = solitaire_tracker.read_tracker("https://github.com/acme/widgets", "active", [], state="all")
            self.assertEqual(got, ([], [], {"ok": False, "reason": lines["read-failed"]["line"]}))
        self.assertEqual(standup.standup_source("https://dev.azure.com/acme-org", "active")[1], lines["ado"]["line"])

    def test_a_cards_title_from_its_heading(self):
        for row in CARDS_TABLE["titles"]:
            with self.subTest(file=row["file"]):
                self.assertEqual(standup.card_title(row["content"], row["file"], row["id"]), row["title"])


# -- The dates read: its query and its parse ---------------------------------
DATES_TABLE = json.loads((FIXTURES / "standup-dates.json").read_text(encoding="utf-8"))


class TheDatesTable(unittest.TestCase):
    """standup-dates.json -- the same rows tkTestToolkit -Rituals asserts
    against Get-P20StandupDatesQuery and ConvertFrom-P20StandupDates."""

    def test_the_query_line_for_line(self):
        q = DATES_TABLE["query"]
        self.assertEqual(standup.dates_query(q["hashes"], q["numbers"]), "\n".join(q["lines"]) + "\n")

    def test_each_answer_parses_to_its_two_maps(self):
        for case in DATES_TABLE["cases"]:
            with self.subTest(case=case["name"]):
                commits, starts = standup.dates_from_answer(
                    case["answer"], case["hashes"], case["numbers"], DATES_TABLE["workerLabels"]
                )
                self.assertEqual(commits, case["expected"]["commitDates"])
                self.assertEqual({str(k): v for k, v in starts.items()}, case["expected"]["issueStarts"])

    def test_a_hash_that_is_not_hex_is_never_written_into_the_query(self):
        self.assertNotIn("evil", standup.dates_query(['a0a1111") { x } evil: object(expression: "'], []))


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
        window=case.get("window", ""),
        commit_dates=case.get("commitDates"),
        issue_starts=case.get("issueStarts"),
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
                "linked-card-issue-unrouted",
                "custom-card-alone",
                "issue-alone",
                "not-billable",
                "together",
                "counts",
                "not-billable-counts",
                "window-three-days",
                "commits-window",
                "issue-labelled-in-window",
                "issue-assigned-before-window",
                "dates-not-read",
            ],
        )

    def test_the_source_and_the_window(self):
        for name, case in JOINED_CASES.items():
            with self.subTest(case=name):
                filled = _fill_joined(case)
                want = case["expected"].get("since", JOINED_TABLE["since"])
                self.assertEqual((filled.source, filled.since), ("both", want))

    def test_each_items_motion_and_commits(self):
        """What moved: every row with a motions map, ref -> [motion, commits]."""
        for name, case in JOINED_CASES.items():
            want = case["expected"].get("motions")
            if want is None:
                continue
            filled = _fill_joined(case)
            got = {
                _ref(i): [i.motion, i.commits]
                for w in filled.workers
                for slot in ("yesterday", "today", "blockers")
                for i in getattr(w, slot)
            }
            with self.subTest(case=name):
                self.assertEqual(got, want)

    def test_the_counts_per_worker_and_in_total(self):
        """The counts line's numbers: per worker, in total, a hash once however many cards thread it."""
        for name, case in JOINED_CASES.items():
            want = case["expected"].get("counts")
            if want is None:
                continue
            counts = _fill_joined(case).counts
            fields = ("closed", "started", "inProgress", "commits", "undated")

            def wanted(row: dict) -> dict:
                return {**row, "undated": row.get("undated", 0)}  # absent is none undated

            with self.subTest(case=name):
                self.assertEqual(
                    [{"label": c.label, **{f: getattr(c, f) for f in fields}} for c in counts.workers],
                    [wanted(r) for r in want["workers"]],
                )
                self.assertEqual({f: getattr(counts.total, f) for f in fields}, wanted(want["total"]))

    def test_the_counts_line_opens_the_brief(self):
        t = C.rituals_text()
        filled = _fill_joined(JOINED_CASES["counts"])
        self.assertEqual(
            filled.brief.split("\n")[0], "Since Thursday 1 October 2026: 2 closed, 2 started, 2 in progress, 5 commits."
        )
        self.assertTrue(filled.brief.startswith(t["countsTotal"].split("{date}")[0]))
        quiet = _fill_joined(JOINED_CASES["not-billable-counts"])
        self.assertEqual(quiet.brief.split("\n")[0], "Since Thursday 1 October 2026: 1 in progress.")

    def test_commits_outside_the_window_are_not_counted(self):
        """One before the window and one after asOf are dropped; with no dates read every bullet counts."""
        dated = _fill_joined(JOINED_CASES["commits-window"])
        plain = _fill_joined(JOINED_CASES["dates-not-read"])
        self.assertEqual((dated.counts.total.commits, plain.counts.total.commits), (3, 7))
        self.assertEqual(plain.counts.total.undated, 0)

    def test_an_undated_commit_is_said_not_counted(self):
        filled = _fill_joined(JOINED_CASES["commits-window"])
        self.assertEqual(filled.counts.total.undated, 2)
        first = filled.brief.split("\n")[0]
        self.assertEqual(first, "Since Thursday 1 October 2026: 1 started, 1 in progress, 3 commits (2 undated).")
        none_dated = standup.MotionCount(undated=2)
        self.assertEqual(standup.counts_said(none_dated), "0 commits (2 undated)")

    def test_an_issue_labelled_in_the_window_is_started(self):
        filled = _fill_joined(JOINED_CASES["issue-labelled-in-window"])
        self.assertEqual([(i.number, i.motion) for i in filled.workers[1].today], [(171, "started")])
        before = _fill_joined(JOINED_CASES["issue-assigned-before-window"])
        self.assertEqual(
            [(i.number, i.motion) for i in before.workers[0].today], [(172, "inProgress"), (173, "inProgress")]
        )

    def test_the_window_hashes_rule(self):
        at = datetime.fromisoformat(JOINED_TABLE["asOf"])
        since = datetime.fromisoformat(JOINED_TABLE["since"])
        self.assertEqual(standup.window_hashes(["a0a1111"], None, since, at), (["a0a1111"], []))
        self.assertEqual(
            standup.window_hashes(
                ["a0a1111", "b0b2222", "c0c3333", "d0d4444"],
                {"A0A1111FFFF": "2026-10-01T04:00:00Z", "b0b2222": "2026-09-30T23:59:59-04:00", "c0c3333": None},
                since,
                at,
            ),
            (["a0a1111"], ["c0c3333", "d0d4444"]),
        )

    def test_the_asks_are_the_counted_cards_and_the_open_issues_alone(self):
        case = JOINED_CASES["dates-not-read"]
        hashes, numbers = standup.date_asks(_fill_joined(case), case["cards"])
        self.assertEqual(hashes, ["a0a1111", "b0b2222", "c0c3333", "d0d4444", "a0a9999", "e0e5555", "f0f6666"])
        self.assertEqual(numbers, [])
        lone = JOINED_CASES["issue-assigned-before-window"]
        self.assertEqual(standup.date_asks(_fill_joined(lone), lone["cards"]), ([], [172]))

    def test_one_dates_read_per_repo_per_standup(self):
        """The dates read is one gh api graphql per repo, kept for the TTL; a failed read keeps today's rule."""
        from agent.solitaire import tracker

        calls: list[list[str]] = []

        def fake_run(cmd, timeout, **_kw):
            calls.append(cmd)
            query = Path(cmd[cmd.index("-F") + 1].split("@", 1)[1]).read_text(encoding="utf-8")
            repo = {}
            for i, h in enumerate(re.findall(r'object\(expression: "([0-9a-f]+)"\)', query)):
                repo[f"c{i}"] = {"oid": h + "0" * (40 - len(h)), "authoredDate": "2026-10-01T10:00:00Z"}
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"data": {"repository": repo}}), "")

        tracker.forget()
        try:
            with mock.patch("agent.ado.repo_read.run_read", side_effect=fake_run):
                hashes = ["a0a1111", "b0b2222"]
                got = tracker.dates(["acme/widgets", "acme/gears"], hashes, {"acme/widgets": [171]}, ["opus"])
                self.assertEqual(len(calls), 2)
                self.assertTrue(all(c[:3] == ["gh", "api", "graphql"] for c in calls))
                self.assertEqual(got[0], {h: "2026-10-01T10:00:00Z" for h in hashes})
                self.assertIsNone(got[2])
                tracker.dates(["acme/widgets", "acme/gears"], hashes, {"acme/widgets": [171]}, ["opus"])
                self.assertEqual(len(calls), 2, "the second standup is served from the kept read")
                many = [f"{i:07x}" for i in range(standup.DATES_CHUNK + 1)]
                tracker.dates(["acme/widgets"], many, {}, ["opus"])
                self.assertEqual(len(calls), 4, "past one chunk's aliases, one call more")
            with mock.patch(
                "agent.ado.repo_read.run_read",
                return_value=subprocess.CompletedProcess([], 1, "", "HTTP 502: down"),
            ):
                tracker.forget()
                self.assertEqual(tracker.dates(["acme/widgets"], ["a0a1111"], {}, []), (None, None, "HTTP 502: down"))
        finally:
            tracker.forget()

    def test_a_window_is_a_day_on_or_before_today(self):
        at = datetime.fromisoformat(JOINED_TABLE["asOf"])
        self.assertEqual(standup.since_refusal(at, ""), "")
        self.assertEqual(standup.since_refusal(at, "2026-10-02"), "")
        self.assertEqual(standup.since_refusal(at, "2026-09-29"), "")
        for bad in ("2026-10-03", "yesterday", "2026-9-29", "2026-02-30", "29/09/2026"):
            with self.subTest(since=bad):
                self.assertTrue(standup.since_refusal(at, bad))
                with self.assertRaises(ValueError):
                    standup.window_start(at, bad)
        self.assertEqual(standup.window_start(at, "2026-09-29").isoformat(), "2026-09-29T00:00:00-04:00")
        self.assertEqual(standup.window_start(at, ""), standup.previous_working_day_start(at))

    def test_a_card_hash_is_counted_by_its_first_seven_characters(self):
        self.assertEqual(
            standup.card_hashes({"commits": ["A1B2C3D", "a1b2c3d4e5f6", "b2c3d4e", ""]}), ["a1b2c3d", "b2c3d4e"]
        )
        self.assertEqual(standup.card_hashes({}), [])

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
                    **_indexes(w),
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
            self.assertTrue(exp.get("work") and exp.get("brief"), name)
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

    def test_with_no_card_in_play_it_reads_as_the_issues_and_the_idle_engineer(self):
        """No card: the issues fill's own rows, then the engineer's -- idle, with a
        made-up Status row as an idle labelled worker has -- and the source says both.
        The engineer takes the round's first turn."""
        friday = CASES["friday"]
        at = datetime.fromisoformat(friday["asOf"])
        alone = standup.fill_standup(at, _labels(friday), friday["issues"], friday["tracker"], space="toolkit")
        joined = standup.fill_joined_standup(
            at, _labels(friday), friday["issues"], friday["tracker"], [], space="toolkit", space_name="Toolkit"
        )
        self.assertEqual(joined.source, "both")
        self.assertEqual([w.model_dump() for w in joined.workers[:-1]], [w.model_dump() for w in alone.workers])
        engineer = joined.workers[-1]
        n, d = len(alone.workers), at.timetuple().tm_yday
        self.assertEqual(
            (engineer.label, engineer.name, engineer.empty, engineer.present), ("toolkit", "Toolkit", True, True)
        )
        self.assertEqual(
            engineer.status,
            [
                VOCAB["nothing"][(d + n) % len(VOCAB["nothing"])],
                VOCAB["nothingToday"][(d + n) % len(VOCAB["nothingToday"])],
            ],
        )
        for render in (standup.render_standup, standup.render_brief):
            with self.subTest(render=render.__name__):
                self.assertNotEqual(render(joined), render(alone))
                self.assertEqual(_less_engineer(render(joined), "Toolkit"), render(alone))
        self.assertEqual(joined.work.workers[0].label, "toolkit")
        self.assertEqual(joined.work.queue.model_dump(), alone.work.queue.model_dump())

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
            # The table's rows are the members'; the invented cast members that fill
            # the room follow them, with no group: the golden text holds their lines.
            members = [w for w in filled.work.workers if not w.cast]
            invented = filled.work.workers[len(members) :]
            with self.subTest(case=name, what="order"):
                self.assertEqual([w.label for w in members], [w["label"] for w in want])
                self.assertTrue(all(w.cast and not (w.yesterday or w.today or w.blockers) for w in invented))
            for got, exp in zip(members, want):
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
                body = row["body"] + "9" * row.get("digits", 0)
                self.assertEqual(
                    standup.work_key(row["milestone"], body, row["type"], row["threads"]),
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
    elif case["source"] == "both":
        # The joined fill, with the case's dates read when it has one (absent is not read).
        filled = standup.fill_joined_standup(
            at,
            PROSE_TABLE["workerLabels"],
            case["issues"],
            case["tracker"],
            case["cards"],
            space=case["space"],
            space_name=case["spaceName"],
            commit_dates=case.get("commitDates"),
            issue_starts=case.get("issueStarts"),
        )
    else:
        filled = standup.fill_standup(at, PROSE_TABLE["workerLabels"], case["issues"], case["tracker"])
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    return filled


class TheProseTable(unittest.TestCase):
    """Every row and case of standup-prose.json -- the same rows tkTestToolkit
    -Rituals asserts against Get-P20StandupProseSentence and Format-P20StandupWork."""

    def test_the_table_has_its_cases(self):
        self.assertEqual(
            set(PROSE_CASES),
            {"friday", "quiet", "no-tracker", "cards", "eight-groups", "walked", "one-slot", "worked", "cards-worked"},
        )

    def test_every_unsaid_row(self):
        """A slot a member with something to say has nothing in says its fixed line,
        or for yesterday the refs of its open items worked in the window -- named up to
        proseFoldNames, counted past it -- and never a made-up item."""
        rows = PROSE_TABLE["unsaid"]
        limit = C.rituals_prose_fold_names()
        sizes = {len(r["worked"]) for r in rows if r["slot"] == "yesterday"}
        self.assertTrue({0, 1, 2, limit, limit + 1} <= sizes, "a row each side of every edge")
        made_up = set(VOCAB["nothing"] + VOCAB["nothingToday"])
        for row in rows:
            with self.subTest(slot=row["slot"], worked=row["worked"]):
                self.assertEqual(standup.prose_unsaid(row["slot"], row["worked"]), row["lines"])
                self.assertFalse(set(row["lines"]) & made_up)

    def test_an_item_worked_in_the_window_is_a_start_or_a_dated_commit(self):
        """The real yesterday: an open item whose work began in the window, or whose card
        threads a commit authored in it -- known only where the dates were read. An item
        merely in progress, or with commits nobody dated, is no fact; a closed one is yesterday's."""
        rows = PROSE_TABLE["itemWorked"]
        self.assertEqual({r["motion"] for r in rows}, set(C.rituals_motions()), "a row for every motion")
        for row in rows:
            with self.subTest(row=row):
                item = standup.SlotItem(number=1, motion=row["motion"], commits=row["commits"])
                self.assertEqual(standup.item_worked(item, row["dated"]), row["worked"])

    def test_a_member_with_something_has_a_yesterday_and_a_today(self):
        """Every present member that is not idle says a yesterday and a today: its real
        sentences, else the fixed line for the slot (prose_unsaid) -- the made-up lists
        are only an idle member's."""
        t = C.rituals_text()
        made_up = set(VOCAB["nothing"] + VOCAB["nothingToday"])
        unsaid = {t["proseYesterdayNone"], t["proseTodayNone"]}
        for name, case in PROSE_CASES.items():
            filled = _fill_prose(case)
            grained = {w.label: w for w in filled.work.workers if not w.cast}
            for w in (w for w in filled.workers if w.present and not w.empty):
                prose = grained[w.label].prose
                with self.subTest(case=name, worker=w.label):
                    self.assertTrue(prose[1].startswith("Yesterday I "), prose)
                    self.assertTrue(any(x.startswith(("Today I'm on", "Today I'll")) for x in prose), prose)
                    self.assertFalse(set(prose) & made_up)
                    if not w.yesterday:
                        self.assertTrue(prose[1] in unsaid or prose[1].startswith("Yesterday I worked on"), prose)
                    if not w.today:
                        self.assertIn(t["proseTodayNone"], prose)
                    else:
                        self.assertNotIn(t["proseTodayNone"], prose)

    def test_the_four_branches_are_in_the_table(self):
        """Missing today; missing yesterday with a real fact (a start, a dated commit, a
        timeline, a card's start) and with none; blockers only -- each pinned by a case."""
        t = C.rituals_text()
        turns = {(n, w.label): w.prose for n, c in PROSE_CASES.items() for w in _fill_prose(c).work.workers}
        one = {k[1]: v for k, v in turns.items() if k[0] == "one-slot"}
        self.assertEqual(one["fable"][1:3], [t["proseYesterdayNone"], t["proseTodayNone"]], "blockers only")
        self.assertEqual(one["opus"][2], t["proseTodayNone"], "missing today")
        self.assertEqual(one["sonnet"][1], t["proseYesterdayNone"], "missing yesterday, no fact")
        worked = {k[1]: v[1] for k, v in turns.items() if k[0] == "worked"}
        self.assertEqual(worked["fable"], t["proseYesterdayWorked"].replace("{refs}", "#911"), "a card's start")
        self.assertEqual(worked["opus"], t["proseYesterdayWorked"].replace("{refs}", "#921"), "a dated commit")
        self.assertEqual(
            worked["sonnet"], t["proseYesterdayWorkedMany"].replace("{n}", C.rituals_number_words()[5]), "timelines"
        )
        cards = turns[("cards-worked", "widgets")][1]
        self.assertEqual(cards, t["proseYesterdayWorked"].replace("{refs}", "150"), "undated commits are no fact")

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
            # The table's rows are the members'; an invented cast member says two
            # made-up items in the same frame, and the golden text holds its line.
            t = C.rituals_text()
            spoken = _fill_prose(case).work.workers
            got = [{"label": w.label, "prose": w.prose} for w in spoken if not w.cast]
            with self.subTest(case=name):
                self.assertEqual(got, case["expected"]["workers"])
                for w in (w for w in spoken if w.cast):
                    self.assertEqual(
                        (w.prose[0], w.prose[3:]), (t["turnOpen"], [t["proseBlockersNone"], t["turnClose"]])
                    )
                    self.assertIn(w.prose[1], VOCAB["nothing"])
                    self.assertIn(w.prose[2], VOCAB["nothingToday"])

    def test_the_chairs_own_turn(self):
        """The chair gives its status last, in the workers' frame and its own first
        person: a yesterday, a today, no blockers; no turn when no tracker answered."""
        for name, case in PROSE_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_prose(case).work.chairProse, case["expected"]["chair"])

    def test_every_chair_yesterday_row(self):
        rows = PROSE_TABLE["chairYesterday"]
        limit = C.rituals_prose_fold_names()
        self.assertTrue(
            {0, 1, 2, limit, limit + 1} <= {len(r["walked"]) for r in rows}, "a row each side of every edge"
        )
        for row in rows:
            with self.subTest(sentence=row["sentence"]):
                self.assertEqual(standup.chair_yesterday(row["walked"], row["day"], row["workers"]), row["sentence"])

    def test_a_chair_with_nothing_walked_takes_the_place_after_the_last_worker(self):
        nothing = VOCAB["nothing"]
        for row in (r for r in PROSE_TABLE["chairYesterday"] if not r["walked"]):
            with self.subTest(day=row["day"], workers=row["workers"]):
                self.assertEqual(row["sentence"], nothing[(row["day"] + row["workers"]) % len(nothing)])

    def test_every_chair_today_row(self):
        for row in PROSE_TABLE["chairToday"]:
            with self.subTest(sentence=row["sentence"]):
                self.assertEqual(standup.chair_today(row["queue"]), row["sentence"])

    def test_the_chair_never_says_the_board_or_you(self):
        """Its own voice: no queue sentence again, and never the word "you"."""
        for name, case in PROSE_CASES.items():
            filled = _fill_prose(case)
            with self.subTest(case=name):
                self.assertFalse(set(filled.work.chairProse) & set(filled.work.queueProse))
                self.assertFalse([x for x in filled.work.chairProse if re.search(r"\byou\b", x, re.IGNORECASE)])
        for row in PROSE_TABLE["chairYesterday"] + PROSE_TABLE["chairToday"]:
            with self.subTest(sentence=row["sentence"]):
                self.assertNotRegex(row["sentence"], r"(?i)\byou\b")

    def test_the_chair_walked_what_closed_with_the_walk_label_in_the_window(self):
        """chair.walked: the walk items closed inside the window, worker or none, by number."""
        got = {name: [i.number for i in _fill_prose(case).chair.walked] for name, case in PROSE_CASES.items()}
        self.assertEqual(got["walked"], [530, 531])
        self.assertEqual({k: v for k, v in got.items() if k != "walked"}, {k: [] for k in got if k != "walked"})

    def test_every_turn_is_in_the_frame(self):
        """turnOpen first, turnClose last, for every worker that says anything and for the chair."""
        t = C.rituals_text()
        for name, case in PROSE_CASES.items():
            filled = _fill_prose(case)
            for said in [w.prose for w in filled.work.workers] + [filled.work.chairProse]:
                if not said:
                    continue
                with self.subTest(case=name, said=said[1]):
                    self.assertEqual((said[0], said[-1]), (t["turnOpen"], t["turnClose"]))

    def test_an_idle_worker_says_its_two_items_in_the_frame(self):
        """A worker with nothing on the tracker says its status -- yesterday, then today --
        and no blockers, inside the frame; never a made-up item beside a real one."""
        t = C.rituals_text()
        for name, case in PROSE_CASES.items():
            filled = _fill_prose(case)
            grained = {w.label: w for w in filled.work.workers}
            for w in filled.workers:
                with self.subTest(case=name, worker=w.label):
                    if w.empty:
                        self.assertEqual(
                            grained[w.label].prose,
                            [t["turnOpen"], *w.status, t["proseBlockersNone"], t["turnClose"]],
                        )
                    else:
                        self.assertFalse(set(grained[w.label].prose) & set(VOCAB["nothing"] + VOCAB["nothingToday"]))

    def test_the_work_text_is_the_golden_file_byte_for_byte(self):
        for name, case in PROSE_CASES.items():
            with self.subTest(case=name):
                self.assertEqual(_fill_prose(case).work.text, _golden(case["expected"]["text"]))

    def test_the_issues_example_sentences(self):
        """The prose grain's own words: "Yesterday I closed two in Team Agile (...). Today I'm on the Studio:
        #<n>, the archived-repository mark. No blockers." -- as this table spells them, in the turn's frame."""
        t = C.rituals_text()
        text = _fill_prose(PROSE_CASES["friday"]).work.text
        self.assertIn(f"Opus: {t['turnOpen']} Yesterday I closed two in Team Agile (#501, #502). ", text)
        self.assertIn(
            f"Fable: {t['turnOpen']} {t['proseYesterdayNone']} "
            "Today I'm on the Studio: #511, the archived-repository mark. ",
            text,
        )
        self.assertIn(f" {t['proseBlockersNone']} {t['turnClose']}\n", text)

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


TEAM_TABLE = json.loads((FIXTURES / "standup-team.json").read_text(encoding="utf-8"))


def _fill_team(case: dict) -> "standup.Standup":
    """A standup-team.json case with its stored teamSize: the issues fill over the
    table's labels, or -- for a case that states ``cards`` -- the joined fill over
    its own labels, issues and cards."""
    at = datetime.fromisoformat(case["asOf"])
    ok = {"ok": True, "reason": ""}
    if "cards" in case:
        filled = standup.fill_joined_standup(
            at,
            case["labels"],
            case["issues"],
            ok,
            case["cards"],
            space=case["space"],
            space_name=case["spaceName"],
            size=case["teamSize"],
        )
    else:
        filled = standup.fill_standup(
            at, TEAM_TABLE["workerLabels"], case["issues"], ok, space="widgets", size=case["teamSize"]
        )
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    filled.brief = standup.render_brief(filled)
    return filled


def _room(row: dict) -> dict:
    """A ``room`` or ``seats`` row through ``room_seats``."""
    engineer = row.get("engineer")
    return standup.room_seats(
        row["size"],
        (engineer["label"], engineer["empty"]) if engineer else None,
        [(w["label"], w["empty"]) for w in row.get("labels", row.get("workers", []))],
    )


# The room's rules (docs/modules/solitaire-agile.md, "The room's rules"), each stated
# once, so a failure names the rule it broke. tkTestToolkit -Rituals states the same
# four over the same rows.


def assert_the_size_seen_is_the_size_picked(tc: unittest.TestCase, size: int, speakers: int) -> None:
    """The round's members plus the chair are exactly the size."""
    tc.assertEqual(speakers + 1, size, "the size seen is the size picked: the round plus the chair")


def assert_the_desks_are_past_the_size(tc: unittest.TestCase, size: int, desks: int) -> None:
    """The empty desks are the windows past the size: the windows taken are the size."""
    windows = len(C.rituals_room()["windows"])
    tc.assertEqual(desks, windows - size, "the empty desks are only the windows past the size")


def assert_the_engineer_sits(tc: unittest.TestCase, speakers: list[dict], engineer: dict | None) -> None:
    """Whenever the fill has an engineer, it is in the round -- first, never invented --
    under the Space's name when the row names one."""
    if engineer is None:
        return
    tc.assertTrue(speakers, "the engineer's seat is the owner's: the round is empty")
    first = speakers[0]
    tc.assertEqual(first["label"], engineer["label"], "the engineer's seat is the owner's: first in the round")
    tc.assertFalse(first["cast"], "the engineer's seat is the owner's: never an invented member")
    if "name" in engineer:
        tc.assertEqual(first["name"], engineer["name"], "the engineer's seat is the owner's: the Space's name")


def assert_everyone_speaks(tc: unittest.TestCase, speakers: list[dict], work_text: str) -> None:
    """Every member of the round has a turn in the rendered work grain, in round order;
    an idle member's turn is its two made-up items, never empty and never omitted."""
    text = C.rituals_text()
    lines = work_text.split("\n")
    at = -1
    for s in speakers:
        head = s["name"] + ": "
        found = [i for i, line in enumerate(lines) if line.startswith(head)]
        tc.assertEqual(len(found), 1, f"everyone speaks: {s['name']} has one turn in the work grain")
        tc.assertGreater(found[0], at, f"everyone speaks: {s['name']}'s turn is in round order")
        at = found[0]
        line = lines[at][len(head) :]
        tc.assertTrue(line.startswith(text["turnOpen"] + " "), f"everyone speaks: {s['name']}'s turn opens")
        tc.assertTrue(line.endswith(" " + text["turnClose"]), f"everyone speaks: {s['name']}'s turn closes")
        body = line[len(text["turnOpen"]) + 1 : -len(text["turnClose"]) - 1]
        tc.assertTrue(body.strip(), f"everyone speaks: {s['name']}'s turn says something")
        if s["idle"]:
            pairs = {f"{y} {t} {text['proseBlockersNone']}" for y in VOCAB["nothing"] for t in VOCAB["nothingToday"]}
            tc.assertIn(body, pairs, f"everyone speaks: idle {s['name']}'s turn is a made-up pair")


def _speakers(filled: "standup.Standup") -> list[dict]:
    """The round as the rules read it: each speaker's label, name, cast, and whether it
    is idle -- an invented member always, a member of the record by its own ``empty``."""
    empty = {w.label: w.empty for w in filled.workers}
    return [
        {"label": w.label, "name": w.name, "cast": w.cast, "idle": w.cast or empty.get(w.label, True)}
        for w in filled.work.workers
    ]


class TheRoomsRules(unittest.TestCase):
    """The room's rules over every ``room`` row and every case of standup-team.json:
    the size seen is the size picked, everyone speaks, the desks are past the size,
    and the engineer sits."""

    def test_every_room_row_keeps_the_rules(self):
        for row in TEAM_TABLE["room"]:
            with self.subTest(row=row["name"]):
                got = _room(row)
                assert_the_size_seen_is_the_size_picked(self, row["size"], len(got["round"]))
                assert_the_desks_are_past_the_size(self, row["size"], len(got["desks"]))
                assert_the_engineer_sits(self, got["round"], row["engineer"])

    def test_every_case_keeps_the_rules(self):
        windows = len(C.rituals_room()["windows"])
        for case in TEAM_TABLE["cases"]:
            with self.subTest(case=case["name"]):
                filled = _fill_team(case)
                speakers = _speakers(filled)
                assert_the_size_seen_is_the_size_picked(self, filled.team.size, len(speakers))
                assert_the_desks_are_past_the_size(self, filled.team.size, windows - 1 - len(speakers))
                assert_everyone_speaks(self, speakers, filled.work.text)
                engineer = {"label": case["space"], "name": case["spaceName"]} if "cards" in case else None
                assert_the_engineer_sits(self, speakers, engineer)

    def test_the_standup_runs_on_a_day_with_no_work_at_every_size(self):
        """No labels, no issues, no card: a room at each size all the same."""
        idle = {c["teamSize"]: c for c in TEAM_TABLE["cases"] if c["name"].startswith("idle-room")}
        self.assertEqual(sorted(idle), sorted(C.rituals_team_sizes()))
        for size, case in idle.items():
            with self.subTest(size=size):
                self.assertEqual(case["labels"] + case["issues"] + case["cards"], [])
                filled = _fill_team(case)
                self.assertTrue(all(s["idle"] for s in _speakers(filled)))
                self.assertEqual(filled.team.size, size)
                # The chair speaks last, as on any other day.
                self.assertIn("\n" + " ".join(filled.work.chairProse) + "\n", filled.work.text)


class TheTeamTable(unittest.TestCase):
    """Every row of standup-team.json -- the same rows tkTestToolkit -Rituals asserts
    against Get-P20TeamSize, Get-P20StandupRoomSeats, Invoke-P20StandupFill and
    Invoke-P20StandupJoinedFill."""

    def test_the_table_has_its_sections(self):
        self.assertGreaterEqual(len(TEAM_TABLE["sizes"]), 8)
        self.assertGreaterEqual(len(TEAM_TABLE["seats"]), 6)
        self.assertGreaterEqual(len(TEAM_TABLE["room"]), 16)
        self.assertEqual(
            {c["name"] for c in TEAM_TABLE["cases"]},
            {
                "absent",
                "idle-sits",
                "unset",
                "work-unsaid",
                "walk-size-3",
                "walk-size-6",
                "walk-size-9",
                "idle-room",
                "idle-room-3",
                "idle-room-6",
            },
        )

    def test_every_size_row(self):
        for row in TEAM_TABLE["sizes"]:
            with self.subTest(stored=row["stored"]):
                self.assertEqual(standup.team_size(row["stored"]), row["size"])
                self.assertEqual(row["stored"] == row["size"] and not isinstance(row["stored"], bool), row["set"])

    def test_the_sizes_and_the_default_are_the_contracts(self):
        self.assertEqual(standup.team_size(None), C.rituals_team_size_default())
        for n in C.rituals_team_sizes():
            self.assertEqual(standup.team_size(n), n)

    def test_every_seat_row(self):
        """Labels only: who sits, said in the workers' own order."""
        for row in TEAM_TABLE["seats"]:
            with self.subTest(row=row["name"]):
                seated = _room(row)["present"]
                self.assertEqual([w["label"] for w in row["workers"] if w["label"] in seated], row["present"])

    def test_every_room_row(self):
        """The size is the team: who sits, each speaker's window, and the desks left."""
        for row in TEAM_TABLE["room"]:
            with self.subTest(row=row["name"]):
                got = _room(row)
                self.assertEqual(got["present"], row["present"])
                self.assertEqual(got["round"], row["round"])
                self.assertEqual(got["desks"], row["desks"])

    def test_every_room_row_fills_the_seats_it_can(self):
        """Every seat the size counts is filled -- by a member, or by an invented cast
        member -- so the desks are the windows past the size; nobody shares a window
        or a label, and the chair's window is never a member's."""
        room = C.rituals_room()
        members = [w["id"] for w in room["windows"] if w["id"] != room["chair"]]
        for row in TEAM_TABLE["room"]:
            with self.subTest(row=row["name"]):
                seats = row["size"] - 1
                windows = [r["window"] for r in row["round"]]
                self.assertEqual(len(row["round"]), seats)
                self.assertEqual(len(row["desks"]), len(members) - seats)
                self.assertEqual(sorted(windows + row["desks"]), sorted(members))
                self.assertEqual(len({r["label"] for r in row["round"]}), seats)
                everyone = len(row["labels"]) + (1 if row["engineer"] else 0)
                self.assertEqual(sum(1 for r in row["round"] if r["cast"]), max(seats - everyone, 0))
                self.assertTrue(all(r["window"] == r["label"] for r in row["round"] if r["cast"]))

    def test_the_walk_rows_are_the_three_rooms(self):
        """A Space with no worker labels whose engineer has work, at 3, 6 and 9: the
        chair, the engineer, and 1, 4 and 7 invented cast members; 6, 3 and 0 desks."""
        rows = {r["size"]: r for r in TEAM_TABLE["room"] if r["name"].startswith("walk-size-")}
        self.assertEqual(sorted(rows), [3, 6, 9])
        for size, row in rows.items():
            with self.subTest(size=size):
                self.assertEqual(row["engineer"], {"label": "widgets", "empty": False})
                self.assertEqual(row["labels"], [])
                self.assertEqual(
                    row["round"][0], {"label": "widgets", "cast": False, "window": C.rituals_room()["engineer"]}
                )
                self.assertEqual(sum(1 for r in row["round"] if r["cast"]), size - 2)
                self.assertEqual(len(row["desks"]), 9 - size)

    def test_every_case_end_to_end(self):
        for case in TEAM_TABLE["cases"]:
            exp = case["expected"]
            with self.subTest(case=case["name"]):
                filled = _fill_team(case)
                self.assertEqual(filled.team.model_dump(), exp["team"])
                got = [
                    {"label": w.label, "name": w.name, "empty": w.empty, "present": w.present} for w in filled.workers
                ]
                self.assertEqual(got, exp["workers"])
                # The round: the seated in seat order, then the invented cast members.
                spoken = [{"label": w.label, "name": w.name, "cast": w.cast} for w in filled.work.workers]
                self.assertEqual(spoken, exp["round"])
                self.assertEqual(
                    {w["label"] for w in spoken if not w["cast"]}, {w["label"] for w in exp["workers"] if w["present"]}
                )
                self.assertEqual(len(spoken), min(filled.team.size - 1, 8) if len(spoken) > len(got) else len(spoken))
                # The counts keep every worker of the record, and never an invented one.
                self.assertEqual([c.label for c in filled.counts.workers], [w["label"] for w in exp["workers"]])
                self.assertEqual(filled.text, _golden(exp["text"]))
                self.assertEqual(filled.work.text, _golden(exp["work"]))
                self.assertEqual(filled.brief, _golden(exp["brief"]))
                # An invented cast member is in the round only: not in the detail, not in the brief.
                for w in (w for w in spoken if w["cast"]):
                    self.assertIn(w["name"] + ": ", filled.work.text)
                    self.assertNotIn(w["name"], filled.text)
                    self.assertNotIn(w["name"], filled.brief)
                # The dress is offered the seated members only: never an absent worker's
                # facts, never an invented cast member's.
                said = {f["id"].split("/")[0] for f in standup.dress_facts(filled)}
                self.assertTrue(said <= {w["label"] for w in exp["workers"] if w["present"]}, said)

    def test_the_walk_cases_seat_the_three_rooms(self):
        """On a Space with no worker labels: at 9 the chair, the engineer and seven
        invented members with no empty desk; at 6 three desks; at 3 six."""
        for size, invented in ((3, 1), (6, 4), (9, 7)):
            case = next(c for c in TEAM_TABLE["cases"] if c["name"] == f"walk-size-{size}")
            filled = _fill_team(case)
            with self.subTest(size=size):
                self.assertEqual([w.label for w in filled.workers], ["widgets"])
                self.assertEqual([w.cast for w in filled.work.workers], [False] + [True] * invented)
                self.assertEqual(8 - len(filled.work.workers), 9 - size, "the empty desks")
                self.assertIn("Today I'm on R4T7, Wire the export.", filled.work.workers[0].prose)

    def test_a_full_idle_room_never_repeats_a_made_up_line(self):
        """Eight idle members -- the engineer and seven invented -- say two different
        made-up items each, none repeated on one day, and the chair's own made-up
        yesterday is none of them: every day of a year, leap day included."""
        case = next(c for c in TEAM_TABLE["cases"] if c["name"] == "idle-room")
        self.assertEqual(len(_fill_team(case).work.workers), 8)
        for day in range(367):
            at = datetime.fromisoformat("2028-01-01T09:00:00-05:00") + timedelta(days=day)
            filled = _fill_team({**case, "asOf": at.isoformat()})
            members = filled.work.workers
            lines = [line for w in members for line in w.prose[1:3]]
            with self.subTest(day=at.date().isoformat()):
                self.assertEqual(len(members), 8)
                self.assertEqual(len(set(lines)), 16, lines)
                self.assertTrue(
                    all(w.prose[1] in VOCAB["nothing"] and w.prose[2] in VOCAB["nothingToday"] for w in members)
                )
                self.assertIn(filled.work.chairProse[1], VOCAB["nothing"])
                self.assertNotIn(filled.work.chairProse[1], lines)

    def test_an_absent_worker_keeps_its_made_up_items_by_its_label_position(self):
        """The idle pick's i is the worker's place in the label order, whoever is absent:
        a worker's made-up items do not move when the room's size does."""
        case = next(c for c in TEAM_TABLE["cases"] if c["name"] == "absent")
        small = _fill_team(case)
        whole = _fill_team({**case, "teamSize": None})
        self.assertEqual([w.status for w in small.workers], [w.status for w in whole.workers])

    def test_the_cards_fill_seats_the_engineer_and_fills_the_room(self):
        cards = standup.fill_cards_standup(datetime.fromisoformat("2026-10-02T09:00:00-04:00"), [], space="s", size=3)
        self.assertEqual((cards.team.size, [w.present for w in cards.workers]), (3, [True]))
        self.assertEqual([(w.label, w.cast) for w in cards.work.workers], [("s", False), ("ops-dev", True)])

    def test_a_standup_nobody_seated_speaks_its_present_workers(self):
        """A reading that carries no round -- read back from JSON -- speaks the workers
        marked present, in their order."""
        case = next(c for c in TEAM_TABLE["cases"] if c["name"] == "absent")
        filled = _fill_team(case)
        back = standup.Standup.model_validate(json.loads(filled.model_dump_json(by_alias=True)))
        self.assertEqual(standup.render_work(back), filled.work.text)
        again = standup.build_work(back, {})
        self.assertEqual([w.label for w in again.workers], [w.label for w in back.workers if w.present])


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
        """The groups' ids are their places in a turn: the opener is place 0 and is never dressed."""
        reply = DRESS_TABLE["reply"]
        t = C.rituals_text()
        turn = [t["turnOpen"], *[g["floor"] for g in DRESS_GROUPS], t["proseBlockersNone"], t["turnClose"]]
        filled = standup.Standup(work=standup.Work(workers=[standup.WorkWorker(label="opus", name="Opus", prose=turn)]))
        spoken = standup.spoken_from(filled, DRESS_GROUPS, reply["answer"], "m")
        self.assertEqual(
            spoken.workers[0].prose, [t["turnOpen"], *reply["said"], t["proseBlockersNone"], t["turnClose"]]
        )
        self.assertEqual((spoken.dressed, spoken.refused, spoken.model), (reply["dressed"], reply["refused"], "m"))

    def test_the_facts_are_the_workers_sentences_and_nothing_else(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        facts = standup.dress_facts(filled)
        prose = {w.label: w.prose for w in filled.work.workers}
        # Position 0 is the turn's opener, which is the frame's and never dressed.
        # The first worker's yesterday is the fixed line at position 1, which is not a fact either.
        self.assertEqual([f["id"] for f in facts], ["fable/2", "fable/3", "fable/4", "opus/1", "opus/2", "opus/3"])
        for f in facts:
            label, at = f["id"].split("/")
            with self.subTest(fact=f["id"]):
                self.assertEqual(f["floor"], prose[label][int(at)])
                self.assertEqual(standup.dress_guard(f, f["floor"]), "")
        said = {f["floor"] for f in facts}
        self.assertNotIn(C.rituals_text()["proseBlockersNone"], said)
        self.assertFalse(said & set(filled.work.queueProse), "the queue's sentences are the chair's, not dressed")
        self.assertFalse(said & set(filled.work.chairProse), "the chair's own turn is not dressed")
        self.assertFalse(said & set(VOCAB["nothing"] + VOCAB["nothingToday"]), "a made-up item is not dressed")
        self.assertFalse(
            said & {C.rituals_text()["turnOpen"], C.rituals_text()["turnClose"]}, "the frame is not dressed"
        )
        self.assertNotIn(C.rituals_text()["proseYesterdayNone"], said, "a fixed line is not dressed")
        opus = next(f for f in facts if f["id"] == "opus/1")
        self.assertEqual(
            (opus["name"], opus["count"], opus["refs"], opus["first"], opus["slot"]),
            ("Team Agile", 2, ["#501", "#502"], True, "yesterday"),
        )
        self.assertEqual(opus["titles"]["#501"], "Feature: Team Agile -- wire the stage")

    def test_no_unsaid_line_is_a_fact(self):
        """A slot with nothing says a fixed line, or the refs worked in the window: neither
        is a group, so neither goes to the model -- every case, every member."""
        t = C.rituals_text()
        for name, case in PROSE_CASES.items():
            filled = _fill_prose(case)
            facts = standup.dress_facts(filled)
            prose = {w.label: w.prose for w in filled.work.workers}
            fixed = {t["proseYesterdayNone"], t["proseTodayNone"]}
            with self.subTest(case=name):
                for f in facts:
                    label, at = f["id"].split("/")
                    self.assertEqual(f["floor"], prose[label][int(at)])
                    self.assertNotIn(f["floor"], fixed)
                    self.assertFalse(f["floor"].startswith("Yesterday I worked on"), f["floor"])
                    self.assertTrue(f["refs"] or f["count"], f)

    def test_a_folded_sentence_is_one_fact(self):
        """The dress is handed the folded sentence as it is handed any other: one entry,
        the names it says, the count of its groups, and no ref of its own."""
        filled = _fill_prose(PROSE_CASES["eight-groups"])
        facts = {f["id"]: f for f in standup.dress_facts(filled)}
        prose = {w.label: w.prose for w in filled.work.workers}
        self.assertEqual(
            sorted(facts),
            ["fable/2", "fable/3", "opus/2", "opus/3", "sonnet/1", "sonnet/2", "sonnet/3", "sonnet/4", "sonnet/5"],
        )
        for f in facts.values():
            label, at = f["id"].split("/")
            with self.subTest(fact=f["id"]):
                self.assertEqual(f["floor"], prose[label][int(at)])
                self.assertEqual(standup.dress_guard(f, f["floor"]), "")
        fable, opus = facts["fable/3"], facts["opus/3"]
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
        self.assertEqual(facts["opus/1"]["kinds"], {"bugs": 2})
        self.assertEqual(facts["opus/3"]["kinds"], {"features": 1})
        self.assertEqual(facts["opus/2"]["kinds"], {})
        cards = {f["id"]: f for f in standup.dress_facts(_fill_prose(PROSE_CASES["cards"]))}
        bug = next(f for f in cards.values() if f["name"] == "Bug")
        self.assertEqual(bug["kinds"], {"bugs": bug["count"]})

    def test_the_prompt_offers_the_verbs_and_never_the_fake_work(self):
        facts = standup.dress_facts(_fill_prose(PROSE_CASES["friday"]))
        system, prompt = standup.dress_prompt(facts)
        for verb in VOCAB["verbs"]:
            self.assertIn(verb, system)
        for family in ("fakeWork", "excuses", "phrasebook", "nothing", "nothingToday"):
            for phrase in VOCAB[family]:
                with self.subTest(family=family, phrase=phrase):
                    self.assertNotIn(phrase, system + prompt)
        self.assertEqual(json.loads(prompt), facts)

    def test_a_model_that_answers_is_dressed_and_guarded(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        complete, calls = _answering(
            {
                "opus/1": "Smashed two in Team Agile (#501, #502).",
                "opus/3": "Plumbing for two in Team Agile (#504, #505), and #999.",
            }
        )
        with mock.patch.object(standup.model, "complete", complete):
            spoken = asyncio.run(standup.dress_standup(filled))
        self.assertEqual(len(calls), 1)
        opus = next(w for w in spoken.workers if w.label == "opus")
        work = next(w for w in filled.work.workers if w.label == "opus")
        self.assertEqual(opus.prose, [work.prose[0], "Smashed two in Team Agile (#501, #502).", *work.prose[2:]])
        fable = next(w for w in spoken.workers if w.label == "fable")
        self.assertEqual(fable.prose, next(w for w in filled.work.workers if w.label == "fable").prose)
        self.assertEqual((spoken.dressed, spoken.refused), (1, 5))
        self.assertEqual(
            filled.work.text, _golden(PROSE_CASES["friday"]["expected"]["text"]), "the work text is untouched"
        )

    def test_the_same_groups_are_dressed_once(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        complete, calls = _answering({"opus/1": "Smashed two in Team Agile (#501, #502)."})
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

    def test_begun_and_commits(self):
        """What moved: begun is the **Started:** day, else the **Created:** day;
        commits every `- <hash>` bullet's hash, as the card has it."""
        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp)
            (space / "current").mkdir()
            files = {
                "current/Task139-write-the-docs.prompt.md": (
                    "# Task 139: Write the docs\n\nCommits:\n- a41c2e9 first\n  - `b52d3f0aa` second\n"
                    "- not a hash\n\n---\n\n**Created:** 2026-09-20\n**Started:** 2026-10-01\n"
                ),
                "current/TaskK7M2-wire-the-board.prompt.md": (
                    "# Task K7M2: Wire the board\n\nCommits:\n- (pending)\n\n---\n\n**Created:** 2026-09-30\n"
                ),
                "current/140-no-footer.prompt.md": "# Bug 140: No footer\n",
            }
            for rel, text in files.items():
                (space / rel).write_bytes(text.encode("utf-8"))
            rows = standup.read_cards(space, ["Task", "Bug"], ["Task", ""])
        got = {r["id"]: (r["begun"], r["commits"]) for r in rows}
        self.assertEqual(
            got,
            {
                "139": ("2026-10-01", ["a41c2e9", "b52d3f0aa"]),
                "K7M2": ("2026-09-30", []),
                "140": (None, []),
            },
        )

    def test_a_space_with_no_folders_is_no_cards(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(standup.read_cards(Path(tmp) / "missing", [], []), [])

    def test_a_card_routed_to_a_size_is_taken_by_that_size(self):
        """A card routed with Route -Assign sonnet carries the Agent line alone: the
        standup's row and the suggestion see it as sonnet (the CLI: the same)."""
        from agent.solitaire import suggest

        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp)
            (space / "current").mkdir()
            (space / "current" / "TaskR2DW-routed-to-sonnet.prompt.md").write_bytes(
                b"# Task R2DW: Routed to sonnet\n\n---\n\n**Agent:** claude-sonnet-5-5\n**Created:** 2026-09-20\n"
            )
            rows = standup.read_cards(space, ["Task"], ["Task"])
        self.assertEqual([(r["id"], r["assigned"]) for r in rows], [("R2DW", "sonnet")])
        labels = [{"name": "sonnet", "description": "Routed to sonnet -- the crew"}]
        items = suggest.suggest_items(labels, [], rows, set())
        self.assertEqual([(i["ref"], i["who"]) for i in items], [("R2DW", "sonnet")])

    def test_what_the_suggestion_reads(self):
        """The milestone a card's **Sprint:** line names (whole), its **Created:**
        day, its Tags and who takes it -- the suggestion's four card fields."""
        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp)
            (space / "current").mkdir()
            (space / "current" / "Task23A3-route-the-git-calls.prompt.md").write_bytes(
                b"# Task 23A3: Route the git calls\r\nTags: spec, sev2, sonnet\r\n\r\n---\r\n\r\n"
                b"**Sprint:** M2 -- 1.2.0, the standup sees the work\r\n**Assigned:** me\r\n"
                b"**Created:** 2026-09-20\r\n"
            )
            (space / "current" / "TaskK7M2-bare.prompt.md").write_bytes(b"# Task K7M2: Bare\n")
            rows = {r["id"]: r for r in standup.read_cards(space, ["Task"], ["Task"])}
        got = {k: (r["sprint"], r["created"], r["tags"], r["assigned"]) for k, r in rows.items()}
        self.assertEqual(
            got,
            {
                "23A3": ("M2 -- 1.2.0, the standup sees the work", "2026-09-20", ["spec", "sev2", "sonnet"], "me"),
                "K7M2": ("", None, [], ""),
            },
        )


SUGGEST = json.loads((REPO_ROOT / "Tests" / "fixtures" / "suggestion" / "table.json").read_text(encoding="utf-8"))


def _suggest_brief(case: dict) -> "standup.Standup":
    """A briefs case of the suggestion table: the joined fill, the suggestion
    attached, the three texts rendered -- exactly what the regenerator writes."""
    from agent.solitaire import suggest

    b = SUGGEST["briefs"]
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(b["asOf"]),
        b["workerLabels"],
        case["issues"],
        {"ok": True, "reason": ""},
        case["cards"],
        space=b["space"],
        space_name=b["spaceName"],
    )
    on = suggest.suggestions_on(True, case["suggestions"])
    suggest.attach_suggestions(
        filled, b["workerLabels"], case["issues"], case["cards"], case["howIWork"], on, b["prefix"]
    )
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    filled.brief = standup.render_brief(filled)
    return filled


class TheSuggestionTable(unittest.TestCase):
    """Tests/fixtures/suggestion/table.json -- the rule, the nearest milestone, the
    switch and the chair's line -- the SAME rows tkTestToolkit -Rituals asserts
    against Scripts/Suggest-Rules.ps1 (docs/modules/solitaire-agile.md, "The
    suggestion: one next move, derived")."""

    def setUp(self):
        from agent.solitaire import suggest

        self.suggest = suggest

    def test_the_table_has_every_shape_the_rule_distinguishes(self):
        names = [r["name"] for r in SUGGEST["rows"]]
        for shape in (
            "sev1-beats-a-nearer-milestone",
            "two-in-one-milestone-pick-the-older",
            "one-left-beats-three-left",
            "no-milestone-sorts-last",
            "crew-sized-on-agents-is-a-delegation",
            "unrouted-on-agents-is-a-route",
            "in-flight-is-excluded",
            "not-billable-is-excluded-first",
            "waiting-on-you-is-excluded-before-in-flight",
            "the-empty-space",
            "a-dismissed-item-yields-the-next",
        ):
            self.assertIn(shape, names)
        # Every shape and every exclusion the contract names has a row that reaches it.
        shapes = {r["expected"].get("shape") for r in SUGGEST["rows"]}
        self.assertTrue(set(C.rituals_suggest_shapes()) <= shapes)
        met = {why for r in SUGGEST["rows"] for why in r["expected"]["excluded"].values()}
        self.assertEqual(met, set(C.rituals_suggest_exclusions()))

    def test_the_nearest_milestone(self):
        for row in SUGGEST["nearest"]:
            with self.subTest(row=row["name"]):
                order = self.suggest.nearest_milestones(row["milestones"])
                self.assertEqual(order, row["order"])
                self.assertEqual(order[0] if order else "", row["nearest"])

    def test_every_row(self):
        for row in SUGGEST["rows"]:
            with self.subTest(row=row["name"]):
                picked, excluded = self.suggest.suggest(
                    row["items"], row["howIWork"], row["dismissed"], bool(row.get("launch"))
                )
                exp = row["expected"]
                self.assertEqual([p["ref"] for p in picked], exp["order"])
                self.assertEqual(excluded, exp["excluded"])
                if exp["pick"] is None:
                    self.assertEqual(picked, [])
                    continue
                first = picked[0]
                self.assertEqual(
                    (first["ref"], first["shape"], first["sentence"], first["command"]),
                    (exp["pick"], exp["shape"], exp["sentence"], exp["command"]),
                )

    def test_the_switch(self):
        for row in SUGGEST["switch"]:
            with self.subTest(row=row):
                self.assertEqual(self.suggest.suggestions_on(row["solitaireAgile"], row["suggestions"]), row["on"])

    def test_the_briefs_end_to_end_byte_for_byte(self):
        for case in SUGGEST["briefs"]["cases"]:
            with self.subTest(case=case["name"]):
                filled = _suggest_brief(case)
                exp = case["expected"]
                self.assertEqual([s.ref for s in filled.suggestions], exp["order"])
                self.assertEqual(filled.suggestion.ref if filled.suggestion else None, exp["pick"])
                self.assertEqual(
                    filled.brief,
                    (REPO_ROOT / "Tests" / "fixtures" / "suggestion" / exp["brief"]).read_bytes().decode("utf-8"),
                )

    def test_the_waiting_line_stays_first_and_the_next_line_is_todays(self):
        """D-AR7: with something waiting the suggestion is computed but the Next line is the queue's."""
        t = C.rituals_text()
        case = next(c for c in SUGGEST["briefs"]["cases"] if c["name"] == "waiting")
        lines = _suggest_brief(case).brief.rstrip("\n").split("\n")
        self.assertTrue(lines[1].startswith(t["queueHeading"] + ": "))
        self.assertTrue(lines[-1].startswith(t["briefNext"].split("{")[0]))
        off = next(c for c in SUGGEST["briefs"]["cases"] if c["name"] == "switched-off")
        self.assertEqual(_suggest_brief(off).brief.rstrip("\n").split("\n")[-1], t["briefNextNone"])
        on = next(c for c in SUGGEST["briefs"]["cases"] if c["name"] == "suggested")
        filled = _suggest_brief(on)
        self.assertEqual(filled.brief.rstrip("\n").split("\n")[-1], filled.suggestion.line)
        self.assertTrue(filled.suggestion.line.startswith("Next: #141 is opus-sized"))

    def test_who_me_is_triages_read_and_someone_elses_item_is_theirs(self):
        """An assignee who is the signed-in gh user reads `me` (triage's rule) and is a
        candidate; another assignee is `@<login>` and excluded `theirs`. With no viewer
        every assignee is someone else's."""
        labels = SUGGEST["briefs"]["workerLabels"]
        issues = [
            {"number": 7, "title": "Mine", "state": "OPEN", "labels": [], "assignees": [{"login": "Me-Dev"}]},
            {"number": 8, "title": "Theirs", "state": "OPEN", "labels": [], "assignees": ["octocat"]},
        ]
        items = self.suggest.suggest_items(labels, issues, [], set(), viewer="me-dev")
        self.assertEqual([i["who"] for i in items], [C.rituals_assign_me(), "@octocat"])
        picked, excluded = self.suggest.suggest(items, "agents")
        self.assertEqual(([p["ref"] for p in picked], excluded), (["#7"], {"#8": "theirs"}))
        blind = self.suggest.suggest_items(labels, issues, [], set())
        self.assertEqual(self.suggest.suggest(blind, "agents")[1], {"#7": "theirs", "#8": "theirs"})

    def test_the_items_count_a_milestone_once_per_id(self):
        """The joined list as items: a card that tracks an issue is that issue's row,
        and the milestone's open count is its billable rows, once each."""
        case = next(c for c in SUGGEST["briefs"]["cases"] if c["name"] == "suggested")
        tracking = dict(case["cards"][0], id="150", file="150-fix-the-header.prompt.md", status="In Progress")
        items = self.suggest.suggest_items(
            SUGGEST["briefs"]["workerLabels"], case["issues"], case["cards"] + [tracking], set()
        )
        by_ref = {i["ref"]: i for i in items}
        self.assertEqual(sorted(by_ref), ["#141", "#150", "23A3"])
        self.assertEqual(by_ref["#150"]["lane"], "In Progress")
        self.assertEqual(by_ref["#150"]["milestone"]["open"], 2)
        self.assertEqual(by_ref["#141"]["milestone"]["open"], 1)
        self.assertEqual(
            (by_ref["#141"]["severity"], by_ref["#141"]["size"], by_ref["#141"]["who"]), ("sev2", "opus", "opus")
        )


CORNER = json.loads((FIXTURES / "corner.json").read_text(encoding="utf-8"))


class TheCornerTable(unittest.TestCase):
    """Tests/fixtures/rituals/corner.json -- the PM Corner's line (docs/modules/
    solitaire-agile.md, "The PM Corner: the line, the chevron, the confetti"), the SAME
    rows tkTestToolkit -Rituals asserts against Scripts/Corner-Rules.ps1."""

    def setUp(self):
        sys.path.insert(0, str(REPO_ROOT / "Tests"))
        import regenerate_joined_goldens as regen

        from agent.solitaire import corner, suggest

        self.regen = regen
        self.corner = corner
        self.suggest = suggest

    def _line(self, row: dict) -> dict:
        cards = self.regen.corner_card_rows(row["cards"])
        items = self.suggest.suggest_items(CORNER["workerLabels"], row["issues"], cards, set())
        since = datetime.fromisoformat(CORNER["since"])
        as_of = datetime.fromisoformat(CORNER["asOf"])
        # howIWork and launch are the row's when it names them: alone and off otherwise.
        return self.corner.corner(
            items,
            self.corner.corner_closed(row["issues"], cards, since, as_of),
            row.get("howIWork", "alone"),
            bool(row.get("launch")),
        )

    def test_every_shape_has_a_row(self):
        names = {r["name"] for r in CORNER["rows"]}
        for want in (
            "one-left",
            "several-left",
            "reached",
            "nothing-in-reach",
            "a-card-and-its-issue-counted-once",
            "a-card-and-an-issue-are-items-and-a-long-title-is-read-whole",
        ):
            self.assertIn(want, names)
        self.assertEqual({r["expected"]["shape"] for r in CORNER["rows"]}, set(C.rituals_corner_shapes()))

    def test_the_rows(self):
        for row in CORNER["rows"]:
            with self.subTest(row["name"]):
                got = self._line(row)
                self.assertEqual({k: got[k] for k in row["expected"]}, row["expected"])

    def test_a_long_milestone_is_read_whole_never_the_models_shortened_sprint(self):
        """Section 11's trap: the card model cuts sprint at eighteen characters. The
        row's milestone is longer than twenty, and the card counts toward it."""
        row = next(r for r in CORNER["rows"] if r["name"].endswith("long-title-is-read-whole"))
        self.assertGreater(len(row["expected"]["milestone"]), 20)
        self.assertEqual(row["expected"]["remaining"], 2)
        # The card model's sprint for the same file is NOT the milestone: reading it
        # would have split one milestone into two of one left each.
        from agent.core.parsers import _parse_status_metadata

        text = "\n".join(row["cards"][0]["lines"]) + "\n"
        self.assertNotEqual(_parse_status_metadata(text).get("sprint"), row["expected"]["milestone"])

    def test_the_words_are_the_contracts(self):
        t = C.rituals_text()
        for row in CORNER["rows"]:
            exp = row["expected"]
            key = {
                "oneLeft": "cornerOneLeft",
                "manyLeft": "cornerManyLeft",
                "reached": "cornerReached",
                "nothingInReach": "cornerNothingInReach",
            }[exp["shape"]]
            head = t[key].split("{")[0]
            with self.subTest(row["name"]):
                self.assertTrue(exp["line"].startswith(head), (exp["line"], head))
                self.assertEqual(bool(exp["command"]), exp["shape"] in ("oneLeft", "manyLeft"))

    def test_the_briefs_byte_for_byte(self):
        for case in CORNER["briefs"]["cases"]:
            with self.subTest(case["name"]):
                filled = self.regen.filled_corner_case(CORNER, case)
                exp = case["expected"]
                self.assertEqual(filled.corner.shape if filled.corner else None, exp["shape"])
                self.assertEqual(filled.brief, _golden(exp["brief"]))
                if filled.corner:
                    # The Corner is the brief's LAST line, after the Next line.
                    self.assertEqual(filled.brief.rstrip("\n").split("\n")[-1], filled.corner.brief)
                sug = filled.suggestion
                shared = bool(filled.corner and filled.corner.command and sug and sug.ref == filled.corner.ref)
                if shared and sug.shape == C.rituals_suggest_shapes()[1]:
                    # One pick, one command: a delegation's is the suggestion's, -Launch and all.
                    self.assertEqual(filled.corner.command, sug.command)

    def test_the_launch_rows_differ_only_in_the_command(self):
        """Launch on and off over one read: the same line and pick, and only the
        delegation's command gains -Launch."""
        rows = {r["name"]: r for r in CORNER["rows"]}
        off = rows["a-delegation-with-the-launch-off-is-a-plain-start"]
        on = rows["a-delegation-with-the-launch-on-names-the-launch"]
        self.assertEqual((off["issues"], off["cards"]), (on["issues"], on["cards"]))
        self.assertEqual((bool(off.get("launch")), bool(on.get("launch"))), (False, True))
        t = C.rituals_text()
        arg = on["expected"]["ref"].lstrip("#")
        self.assertEqual(off["expected"]["command"], t["suggestCommandStart"].replace("{arg}", arg))
        self.assertEqual(on["expected"]["command"], t["suggestCommandLaunch"].replace("{arg}", arg))
        self.assertEqual(
            {k: v for k, v in off["expected"].items() if k != "command"},
            {k: v for k, v in on["expected"].items() if k != "command"},
        )


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
    "team",
    "queue",
    "workers",
    "work",
    "spoken",
    "text",
    "brief",
    "checks",
    "links",
    "counts",
    "suggestions",
    "suggestion",
    "corner",
    "agenda",
}
AGENDA_FIELDS = {
    "ref",
    "number",
    "id",
    "kind",
    "title",
    "url",
    "path",
    "file",
    "lane",
    "day",
    "review",
    "cover",
    "checked",
    "total",
    "progress",
}
SUGGESTION_FIELDS = {"ref", "number", "id", "kind", "shape", "sentence", "command", "line"}
CORNER_FIELDS = {"shape", "milestone", "remaining", "ref", "number", "id", "kind", "noun", "line", "command", "brief"}


def _brief_less_corner(body: dict) -> str:
    """The served brief with the PM Corner's last line set aside: the chair's reading
    the goldens hold. The Corner rides the route wherever the suggestion does
    (corner.py) and is always the brief's LAST line when it is there."""
    brief = body["brief"]
    corner = body.get("corner")
    if corner and corner.get("brief"):
        tail = corner["brief"] + "\n"
        assert brief.endswith(tail), (brief, tail)
        return brief[: -len(tail)]
    return brief


WORK_FIELDS = {"queue", "workers", "queueProse", "chairProse", "text"}
GROUP_FIELDS = {"name", "by", "count", "refs", "phrase"}
WORKER_FIELDS = {"label", "name", "yesterday", "today", "blockers", "empty", "excuse", "status", "present"}
WALK_FIELDS = {"number", "id", "title", "url", "path", "motion", "commits", "worker"}
ITEM_FIELDS = {"number", "id", "title", "url", "path", "motion", "commits"}
COUNT_FIELDS = {"label", "name", "closed", "started", "inProgress", "commits", "undated"}


def _graphql_answer(argv: list[str], when: str) -> "subprocess.CompletedProcess":
    """A stub's answer to the standup's dates read: every hash the query asks
    for a commit authored at ``when``, every issue a timeline with no event."""
    query = Path(argv[argv.index("-F") + 1].split("@", 1)[1]).read_text(encoding="utf-8")
    repo: dict = {}
    for i, h in enumerate(re.findall(r'object\(expression: "([0-9a-f]+)"\)', query)):
        repo[f"c{i}"] = {"oid": h + "0" * (40 - len(h)), "authoredDate": when}
    for n in re.findall(r"\bi(\d+): issue\(", query):
        repo[f"i{n}"] = {"timelineItems": {"nodes": []}}
    return subprocess.CompletedProcess(argv, 0, stdout=json.dumps({"data": {"repository": repo}}), stderr="")


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
    # The toolkit Space's own features block (spaces[].features): the suggestion's switch lives there.
    space_features: dict | None = None
    # The room the Space states (spaces[].features.teamSize), as the fill is handed it.
    room = None
    # With the suggestion on, the standup asks who "me" is once (triage's gh api user).
    viewer_reads: list = [["gh", "api", "user"]]

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
                            **({"features": self.space_features} if self.space_features is not None else {}),
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
            if argv[:3] == ["gh", "api", "graphql"]:
                return _graphql_answer(argv, fx["asOf"])
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
        filled = _fill_route(CASES["friday"], self.room)
        filled.work.text = standup.render_work(filled)
        self.assertEqual(body["work"]["text"], filled.work.text)

    def test_a_model_that_answers_is_spoken_beside_work_and_text_and_brief_are_untouched(self):
        filled = _fill_route(CASES["friday"], self.room)
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
        self.assertEqual(_less_engineer(body["text"], "toolkit"), _golden("standup-friday.txt"))
        self.assertEqual(_less_engineer(_brief_less_corner(body), "toolkit"), _golden("standup-friday.brief.txt"))
        self.assertEqual(body["register"], "real", "dressed facts are still facts")

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_route(), "/api/ritual/standup")

    def test_on_it_answers_the_fixtures_friday_byte_for_byte(self):
        res, calls = self._get("/api/ritual/standup?space=toolkit")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        # An active GitHub Space reads both; with no card in its folders the text is
        # the issues' rows and the engineer's, idle: the friday golden once its block is set aside.
        self.assertEqual(body["text"], _fill_route(CASES["friday"], self.room).text)
        self.assertEqual(_less_engineer(body["text"], "toolkit"), _golden("standup-friday.txt"))
        self.assertEqual(_less_engineer(_brief_less_corner(body), "toolkit"), _golden("standup-friday.brief.txt"))
        self.assertEqual((body["ceremony"], body["register"], body["space"]), ("standup", "real", "toolkit"))
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual(body["source"], "both")
        self.assertEqual((body["workers"][-1]["label"], body["workers"][-1]["empty"]), ("toolkit", True))
        self.assertEqual((body["checks"], body["links"]), ([], []))
        # The two reads, then who "me" is -- once, for the suggestion (triage's gh api user).
        # The two reads, the dates read for what they counted, then who "me" is.
        self.assertEqual(
            [c[:3] for c in calls],
            [["gh", "label", "list"], ["gh", "issue", "list"], ["gh", "api", "graphql"], *self.viewer_reads],
        )
        self.assertIn("johnfrog76/toolkit", calls[0])
        self.assertIn("all", calls[1])
        # The work grain reads the milestone and the body.
        fields = calls[1][calls[1].index("--json") + 1].split(",")
        self.assertIn("milestone", fields)
        self.assertIn("body", fields)
        # An open issue's age: the suggestion's order and the Agenda's "Open since" read it, as the CLI's read does.
        self.assertIn("createdAt", fields)
        filled = _fill_route(CASES["friday"], self.room)
        filled.work.text = standup.render_work(filled)
        self.assertEqual(body["work"]["text"], filled.work.text)

    def test_the_room_is_the_spaces_team_size(self):
        """spaces[].features.teamSize, read per request: the response's team.size, every
        worker kept and marked present -- the detail and the brief keep them all -- and
        the round (work.workers, work.text) is the room: the seated members, the
        engineer first, then the invented cast members that fill the seats left."""
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        size = standup.team_size(self.room)
        self.assertEqual(body["team"], {"size": size})
        filled = _fill_route(CASES["friday"], self.room)
        self.assertEqual([w["present"] for w in body["workers"]], [w.present for w in filled.workers])
        spoken = body["work"]["workers"]
        self.assertEqual([(w["label"], w["cast"]) for w in spoken], [(w.label, w.cast) for w in filled.work.workers])
        self.assertEqual(len(spoken), size - 1, "every seat the size counts is filled")
        self.assertEqual(spoken[0]["label"], "toolkit", "the engineer takes the first turn")
        self.assertEqual(
            {w["label"] for w in spoken if not w["cast"]}, {w["label"] for w in body["workers"] if w["present"]}
        )
        self.assertEqual(sum(1 for w in spoken if w["cast"]), max(size - 1 - len(body["workers"]), 0))
        self.assertEqual(_less_engineer(body["text"], "toolkit"), _golden("standup-friday.txt"))

    def test_the_response_field_names_are_section_4bs(self):
        body = self._get("/api/ritual/standup")[0].json()
        self.assertEqual(set(body), TOP_FIELDS)
        self.assertEqual(set(body["agenda"]), {"moved", "waiting"})
        tiles = body["agenda"]["moved"] + body["agenda"]["waiting"]
        self.assertTrue(tiles, "friday has closes and routed issues")
        for tile in tiles:
            self.assertEqual(set(tile), AGENDA_FIELDS)
        self.assertEqual(set(body["tracker"]), {"ok", "reason"})
        self.assertEqual(set(body["chair"]), {"open", "close", "walked"})
        self.assertEqual(set(body["team"]), {"size"})
        self.assertEqual(set(body["queue"]), {"walk", "decide", "look"})
        self.assertEqual(set(body["queue"]["walk"][0]), WALK_FIELDS)
        self.assertEqual(set(body["work"]), WORK_FIELDS)
        self.assertEqual(set(body["work"]["queue"]), {"walk", "decide", "look"})
        self.assertEqual(set(body["work"]["queue"]["walk"][0]), GROUP_FIELDS)
        for w in body["work"]["workers"]:
            self.assertEqual(set(w), {"label", "name", "yesterday", "today", "blockers", "prose", "cast"})
        self.assertEqual(set(body["counts"]), {"workers", "total"})
        self.assertEqual(set(body["counts"]["total"]), COUNT_FIELDS)
        for c in body["counts"]["workers"]:
            self.assertEqual(set(c), COUNT_FIELDS)
        self.assertEqual(body["queue"]["walk"][0]["worker"], "Fable")
        self.assertEqual(body["queue"]["walk"][1]["worker"], "")
        for w in body["workers"]:
            self.assertEqual(set(w), WORKER_FIELDS)
            for slot in ("yesterday", "today", "blockers"):
                for item in w[slot]:
                    self.assertEqual(set(item), ITEM_FIELDS)
        for sug in body["suggestions"]:
            self.assertEqual(set(sug), SUGGESTION_FIELDS)
        if body["corner"] is not None:
            self.assertEqual(set(body["corner"]), CORNER_FIELDS)

    def test_the_suggestion_rides_the_same_read(self):
        """Team Agile on and the Space's switch unset: every open candidate in the
        rule's order, the first is the suggestion, each line names its command.
        The friday case has walks, so the brief's Next line stays the queue's (D-AR7)."""
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertGreater(len(body["suggestions"]), 0)
        self.assertEqual(body["suggestion"], body["suggestions"][0])
        for sug in body["suggestions"]:
            self.assertIn(sug["shape"], C.rituals_suggest_shapes())
            self.assertTrue(sug["line"].startswith("Next: " + sug["sentence"]))
            self.assertTrue(sug["line"].endswith(sug["command"] + ")"))
        self.assertNotIn(body["suggestion"]["line"], body["brief"])
        self.assertIn(C.rituals_text()["briefNext"].split("{")[0], _brief_less_corner(body).splitlines()[-1])

    def test_the_corner_rides_the_same_read(self):
        """Team Agile on, the suggestion on: the Corner is on the response, a shape of
        the contract, and the brief's last line is its brief line."""
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertIsNotNone(body["corner"])
        self.assertIn(body["corner"]["shape"], C.rituals_corner_shapes())
        self.assertEqual(body["brief"].rstrip("\n").split("\n")[-1], body["corner"]["brief"])

    def test_no_space_is_the_active_one(self):
        body = self._get("/api/ritual/standup")[0].json()
        self.assertEqual(body["space"], "toolkit")

    def test_since_widens_yesterdays_window(self):
        """?since=<yyyy-MM-dd> moves yesterday's lower bound back (Standup -Since); the counts line says the day."""
        res = self._get("/api/ritual/standup?space=toolkit&since=2026-09-28")[0]
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["since"], "2026-09-28T00:00:00-04:00")
        self.assertTrue(body["brief"].startswith("Since Monday 28 September 2026: "), body["brief"])
        self.assertEqual(set(body["counts"]), {"workers", "total"})

    def test_a_since_that_is_not_a_day_before_today_is_a_422_naming_it(self):
        for bad in ("yesterday", "2026-10-03"):
            with self.subTest(since=bad):
                res, calls = self._get(f"/api/ritual/standup?space=toolkit&since={bad}")
                self.assertEqual(res.status_code, 422)
                self.assertIn(bad, res.json()["detail"])
                self.assertEqual(calls, [])

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
        # The Azure path is untouched: no suggestion and no PM Corner, and no Corner line in the brief.
        self.assertEqual((body["suggestions"], body["suggestion"], body["corner"]), ([], None, None))
        self.assertNotIn(C.rituals_text()["cornerBrief"].split("{")[0], body["brief"])

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
        # The two reads, then who "me" is -- once, for the suggestion (triage's gh api user).
        # The two reads, the dates read for what they counted, then who "me" is.
        self.assertEqual(
            [c[:3] for c in calls],
            [["gh", "label", "list"], ["gh", "issue", "list"], ["gh", "api", "graphql"], *self.viewer_reads],
        )
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
            body["tracker"], {"ok": False, "reason": "gh did not answer for johnfrog76/toolkit: TimeoutExpired"}
        )
        self.assertEqual(body["text"], _golden("standup-no-tracker.txt"))

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
        self.assertEqual(_less_engineer(body["text"], "toolkit"), _golden("standup-friday.txt"))
        self.assertIn(
            "#101 Build the foyer counts \u2014 Chlo\u00e9\u2019s \u201c\u00cfle\u201d row\n",
            body["text"],
        )
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
        self.assertEqual(
            tracker["reason"], "gh did not answer for johnfrog76/toolkit: gh's output could not be read (exit code 0)"
        )

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
    test_since_widens_yesterdays_window = None
    test_a_since_that_is_not_a_day_before_today_is_a_422_naming_it = None
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
    test_the_suggestion_rides_the_same_read = None
    test_the_corner_rides_the_same_read = None
    test_the_room_is_the_spaces_team_size = None


class TheRouteWithSuggestionsOff(TheRoute):
    """spaces.toolkit.features.suggestions=false: the standup is the same, with no suggestion."""

    space_features = {"suggestions": False}
    viewer_reads: list = []

    def test_the_suggestion_rides_the_same_read(self):
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertEqual((body["suggestions"], body["suggestion"]), ([], None))

    def test_the_corner_rides_the_same_read(self):
        """The switch that removes the suggestion removes the Corner (D-AR8, D-AR9)."""
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertIsNone(body["corner"])
        self.assertNotIn(C.rituals_text()["cornerBrief"].split("{")[0], body["brief"])


class TheRouteInARoomOfThree(TheRoute):
    """spaces.toolkit.features.teamSize=3: two seats. The engineer always sits, so it
    takes the first and the friday case's first worker with work the second; its
    other worker with work and its idle third are absent -- the detail and the brief
    keep everyone, the round is two."""

    space_features = {"teamSize": 3}
    room = 3

    def test_the_engineer_sits_first_and_the_ledger_keeps_everyone(self):
        body = self._get("/api/ritual/standup?space=toolkit")[0].json()
        self.assertEqual(body["team"], {"size": 3})
        self.assertEqual(
            [(w["label"], w["present"]) for w in body["workers"]],
            [("fable", True), ("opus", False), ("sonnet", False), ("toolkit", True)],
        )
        self.assertEqual(
            [(w["label"], w["cast"]) for w in body["work"]["workers"]], [("toolkit", False), ("fable", False)]
        )
        for name in ("Opus", "Sonnet"):
            self.assertNotIn(name + ":", body["work"]["text"])
            self.assertIn(name, body["text"])
            self.assertIn(name + ":", _brief_less_corner(body))


class TheAppMountsIt(unittest.TestCase):
    def test_the_app_serves_the_route(self):
        from agent.app import app

        paths = set(
            app.openapi()["paths"]
        )  # fastapi >=0.142 includes routers lazily, so app.routes no longer lists them
        self.assertIn(C.rituals_route(), paths)


class TheBacklogIsNotInPlay(unittest.TestCase):
    """A NEGATIVE requirement (docs/hub/cards.md, "Where it lives"): a card in a
    Space's backlog/ is planned, not in play, so the standup never mentions it.
    Not "no code was added for it" -- a card is put there and shown absent.
    Tests/Test-Rituals.ps1 holds the CLI's Get-P20StandupCards to the same."""

    def test_read_cards_reads_current_and_archive_and_never_backlog(self):
        with tempfile.TemporaryDirectory() as tmp:
            space = Path(tmp)
            for folder, name in (
                (C.folder_current(), "TaskK7M2-in-play.prompt.md"),
                (C.folder_backlog(), "TaskR9PX-planned.prompt.md"),
                (C.folder_archive(), "TaskW3X7-done.prompt.md"),
            ):
                (space / folder).mkdir()
                (space / folder / name).write_text(
                    "# Task X: a card\n\n## Git\nCommits:\n- (pending)\n\n**Created:** 2026-10-19\n", encoding="utf-8"
                )
            rows = standup.read_cards(space, ["Task"], ["Task"])
            self.assertEqual(sorted(r["id"] for r in rows), ["K7M2", "W3X7"])
            self.assertNotIn(C.folder_backlog(), {r["folder"] for r in rows})
            self.assertNotIn("R9PX", {c["id"] for c in standup.cards_in_play(rows)})


# -- One tracker read, one dress per fact (toolkit card QP33) --------------------


class TheOneTrackerRead(unittest.TestCase):
    """Each gh answer is kept for READ_TTL_SECONDS (tracker.py), shared by the
    standup and triage: a second GET inside the TTL starts no subprocess, triage
    after the standup is served from the standup's all-states read, and Refresh
    (``?refresh=1``) or a verb through the bridge reads again. Output is unchanged."""

    features = {"solitaireAgile": True}
    space_features = None

    def setUp(self):
        TheRoute.setUp(self)
        fx = CASES["friday"]
        self.calls: list[list[str]] = []
        self.fail_next = False
        self.issues = [dict(i, labels=[{"name": n} for n in i["labels"]]) for i in fx["issues"]]

        def fake_run(argv, **_kw):
            self.calls.append(list(argv))
            if self.fail_next:
                self.fail_next = False
                raise subprocess.TimeoutExpired(argv, 30)
            if argv[:3] == ["gh", "label", "list"]:
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(_labels(fx)), stderr="")
            if argv[:3] == ["gh", "api", "user"]:
                return subprocess.CompletedProcess(argv, 0, stdout="johnfrog76\n", stderr="")
            if argv[:3] == ["gh", "api", "graphql"]:
                return _graphql_answer(argv, fx["asOf"])
            state = argv[argv.index("--state") + 1]
            rows = [i for i in self.issues if state == "all" or i["state"].lower() == state]
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(rows), stderr="")

        self.more = [
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(1, True)),
            mock.patch.object(standup, "_now", return_value=datetime.fromisoformat(fx["asOf"])),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
            mock.patch.object(standup.model, "complete", _unavailable),
        ]
        for p in self.more:
            p.start()

    def tearDown(self):
        for p in reversed(self.more):
            p.stop()
        TheRoute.tearDown(self)

    def _gh(self, *head: str) -> int:
        return sum(1 for c in self.calls if c[1 : 1 + len(head)] == list(head))

    def _reads(self) -> tuple[int, int, int]:
        """(label reads, issue reads, viewer reads) since the last reset."""
        return self._gh("label", "list"), self._gh("issue", "list"), self._gh("api", "user")

    def test_two_standups_inside_the_ttl_read_the_tracker_once(self):
        first = self.client.get("/api/ritual/standup?space=toolkit").json()
        second = self.client.get("/api/ritual/standup?space=toolkit").json()
        self.assertEqual(self._reads(), (1, 1, 1))
        self.assertEqual(self._gh("api", "graphql"), 1, "the dates read is kept like the others")
        self.assertEqual(first, second, "the same facts, the same words")
        self.assertEqual(_less_engineer(first["text"], "toolkit"), _golden("standup-friday.txt"))

    def test_two_triages_inside_the_ttl_read_the_tracker_once(self):
        first = self.client.get("/api/ritual/triage?space=toolkit").json()
        second = self.client.get("/api/ritual/triage?space=toolkit").json()
        self.assertEqual(self._reads(), (1, 1, 1))
        self.assertEqual(first, second)

    def test_triage_after_the_standup_starts_no_subprocess_and_says_the_same(self):
        self.client.get("/api/ritual/standup?space=toolkit")
        self.calls.clear()
        served = self.client.get("/api/ritual/triage?space=toolkit").json()
        self.assertEqual(self.calls, [], "the open issues come from the standup's all-states read")
        read = self.client.get("/api/ritual/triage?space=toolkit&refresh=1").json()
        self.assertEqual(self._reads(), (1, 1, 1))
        self.assertIn(
            ["--state", "open"], [c[c.index("--state") : c.index("--state") + 2] for c in self.calls if "--state" in c]
        )
        self.assertEqual(served, read, "served from the standup's read, triage says what its own read says")
        self.assertGreater(sum(g["open"] for g in read["groups"]), 0)

    def test_an_all_states_read_at_its_limit_does_not_answer_for_triage(self):
        # At the limit the read may not hold every open issue: triage reads its own.
        with mock.patch.object(solitaire_tracker, "ISSUE_LIMIT_ALL", len(self.issues)):
            self.client.get("/api/ritual/standup?space=toolkit")
            self.calls.clear()
            self.client.get("/api/ritual/triage?space=toolkit")
        self.assertEqual(self._reads(), (0, 1, 0))

    def test_refresh_reads_again(self):
        self.client.get("/api/ritual/standup?space=toolkit")
        self.client.get("/api/ritual/standup?space=toolkit&refresh=1")
        self.assertEqual(self._reads(), (2, 2, 2))
        self.calls.clear()
        self.client.get("/api/ritual/standup?space=toolkit")
        self.assertEqual(self.calls, [], "the refreshed read is kept like any other")
        self.client.get("/api/ritual/triage?space=toolkit&refresh=1")
        self.assertEqual(self._reads(), (1, 1, 1))

    def test_past_the_ttl_it_reads_again(self):
        with mock.patch.object(solitaire_tracker, "READ_TTL_SECONDS", 0):
            self.client.get("/api/ritual/standup?space=toolkit")
            self.client.get("/api/ritual/standup?space=toolkit")
        self.assertEqual(self._reads(), (2, 2, 2))

    def test_a_failed_read_is_never_kept(self):
        self.fail_next = True
        failed = self.client.get("/api/ritual/standup?space=toolkit").json()
        self.assertFalse(failed["tracker"]["ok"])
        answered = self.client.get("/api/ritual/standup?space=toolkit").json()
        self.assertTrue(answered["tracker"]["ok"])
        self.assertEqual(self._gh("label", "list"), 2)

    def test_a_verb_through_the_bridge_forgets_every_read(self):
        from agent.ado import bridge

        async def ran(name, req=None):
            return None

        self.client.get("/api/ritual/triage?space=toolkit")
        with mock.patch.object(bridge, "_run_command", ran):
            asyncio.run(bridge.run_command("Route", None))
        self.client.get("/api/ritual/triage?space=toolkit")
        self.assertEqual(self._reads(), (2, 2, 2), "a Route may have moved a label: the next triage reads again")

    def test_the_kept_limits_are_the_readers(self):
        """The completeness rule reads the limits ``_gh_issues`` builds its --limit
        from: one pair of constants in core/config.py, imported by both, so the
        argv the reader builds IS the number the rule tests against."""
        self.assertIs(solitaire_tracker.ISSUE_LIMIT_OPEN, config.ISSUE_LIMIT_OPEN)
        self.assertIs(solitaire_tracker.ISSUE_LIMIT_ALL, config.ISSUE_LIMIT_ALL)
        for state, limit in (("open", config.ISSUE_LIMIT_OPEN), ("all", config.ISSUE_LIMIT_ALL)):
            self.calls.clear()
            accounting._gh_issues("johnfrog76/toolkit", True, state, body=True)
            argv = self.calls[0]
            with self.subTest(state=state):
                self.assertEqual(argv[argv.index("--limit") + 1], str(limit))


class TheDressIsKeptByItsFacts(unittest.TestCase):
    """A dressed reply is kept by a hash of the model, the register and the facts,
    in memory and on disk (core/disk_cache.py): the same facts are dressed once,
    across a restart; a changed fact or model is asked again; and the guard runs on
    every kept reply as on a fresh one. The model is stubbed: no test calls one."""

    REPLY = {"opus/1": "Smashed two in Team Agile (#501, #502)."}

    def _dress(self, filled, complete):
        with mock.patch.object(standup.model, "complete", complete):
            return asyncio.run(standup.dress_standup(filled))

    def test_identical_facts_are_served_with_no_model_call(self):
        complete, calls = _answering(self.REPLY)
        first = self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        second = self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        self.assertEqual(len(calls), 1)
        self.assertEqual(first, second)
        self.assertEqual(first.dressed, 1)

    def test_a_fresh_dress_prunes_the_folder_past_the_cap(self):
        complete, _calls = _answering(self.REPLY)
        folder = disk_cache.cache_path(standup.DRESS_CACHE)
        folder.mkdir(parents=True)
        for n in range(4):  # older replies, none seen for longer than the age
            stale = folder / f"old{n}.json"
            stale.write_text("{}")
            os.utime(stale, (1.0, 1.0))
        self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        self.assertEqual(len(list(folder.iterdir())), 1, "only the reply just kept remains")

    def test_a_restart_keeps_the_dress_on_disk(self):
        complete, calls = _answering(self.REPLY)
        first = self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        standup.clear_dressed()  # what an agent restart forgets
        second = self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        self.assertEqual(len(calls), 1, "the disk kept the reply")
        self.assertEqual(first, second)

    def test_a_changed_fact_is_asked_again(self):
        complete, calls = _answering(self.REPLY)
        self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        changed = _fill_prose(PROSE_CASES["friday"])
        # Position 2: the first worker's first sentence that says a group (position 1 is its fixed yesterday line).
        changed.work.workers[0].prose[2] += " Also on a new one."
        self._dress(changed, complete)
        self.assertEqual(len(calls), 2)

    def test_a_changed_model_is_asked_again(self):
        complete, calls = _answering(self.REPLY)
        self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        with mock.patch.object(standup.model, "model_id", return_value="another-model"):
            self._dress(_fill_prose(PROSE_CASES["friday"]), complete)
        self.assertEqual(len(calls), 2)

    def test_the_guard_runs_on_a_kept_reply(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        facts = standup.dress_facts(filled)
        key = standup.dress_key(standup.model.model_id(), filled.register_, facts)
        # Kept before the guard learned better: one sentence it refuses, one it passes.
        kept = {
            "opus/1": "Smashed two in Team Agile (#501, #502) and #999.",
            "opus/3": "Plumbing for two in Team Agile (#504, #505).",
        }
        self.assertTrue(disk_cache.put_json({"reply": kept}, standup.DRESS_CACHE, f"{key}.json"))
        complete, calls = _answering({})
        spoken = self._dress(filled, complete)
        self.assertEqual(calls, [], "a kept reply is not asked again")
        opus = next(w for w in spoken.workers if w.label == "opus")
        work = next(w for w in filled.work.workers if w.label == "opus")
        self.assertEqual(opus.prose[1], work.prose[1], "the refused sentence is the prose")
        self.assertEqual(standup.dress_guard(next(f for f in facts if f["id"] == "opus/3"), kept["opus/3"]), "")
        self.assertEqual(opus.prose[3], kept["opus/3"])
        self.assertEqual((spoken.dressed, spoken.refused), (1, len(facts) - 1))

    def test_a_kept_file_that_is_not_a_reply_is_a_miss(self):
        filled = _fill_prose(PROSE_CASES["friday"])
        key = standup.dress_key(standup.model.model_id(), filled.register_, standup.dress_facts(filled))
        disk_cache.put_json({"reply": "not an object"}, standup.DRESS_CACHE, f"{key}.json")
        complete, calls = _answering(self.REPLY)
        self._dress(filled, complete)
        self.assertEqual(len(calls), 1)


class TheAgenda(unittest.TestCase):
    """The Agenda (agent/solitaire/agenda.py; docs/modules/solitaire-agile.md, "The page"):
    what moved in the window and what is waiting on you, over the standup's own read.
    One row per shape the rule tells apart -- the table is the scenario below."""

    AS_OF = "2026-10-26T09:00:00-04:00"  # a Monday: the window opens on Friday 23 October

    def setUp(self):
        from agent.core.config import card_types
        from agent.solitaire import agenda, suggest

        self.agenda, self.suggest = agenda, suggest
        self.tmp = tempfile.TemporaryDirectory()
        space = Path(self.tmp.name)
        for folder in ("current", "archive", "backlog"):
            (space / folder).mkdir()

        def card(folder: str, name: str, body: str) -> None:
            (space / folder / name).write_text(body, encoding="utf-8")

        card(
            "current",
            "TaskK7M2-wire-the-board.prompt.md",
            "# Task K7M2: Wire the board\n- [x] one\n- [ ] two\n\n**Created:** 2026-10-23\n",
        )
        card(
            "current",
            "TaskP4X8-in-hand.prompt.md",
            "# Task P4X8: In hand\n- abc1234 a commit\n\n**Created:** 2026-10-21\n",
        )
        card(
            "current",
            "TaskB1B1-not-billable.prompt.md",
            "# Task B1B1: Not billable\n\n**Billable:** no\n**Created:** 2026-10-21\n",
        )
        card(
            "current",
            "203-in-progress.prompt.md",
            "# Bug 203: In progress\n- def5678 a commit\n\n**Created:** 2026-10-21\n",
        )
        card(
            "current",
            "206-in-review.prompt.md",
            "# Bug 206: In review\n\n**Created:** 2026-10-20\n**Review:** 2026-10-22\n",
        )
        card(
            "archive",
            "TaskQ3R9-photo-import.prompt.md",
            "# Task Q3R9: Photo import\n\n**Created:** 2026-10-20\n**Closed:** 2026-10-24\n",
        )
        card("backlog", "TaskZ9Z9-planned.prompt.md", "# Task Z9Z9: Planned\n\n**Created:** 2026-10-19\n")
        names, prefixes = card_types()
        self.cards = standup.read_cards(space, names, prefixes)
        walk = C.rituals_walk_label()
        self.labels = [
            {"name": "opus", "description": C.rituals_worker_label_prefix() + "Opus"},
            {"name": walk, "description": "walk"},
        ]

        def issue(n, state, labels, created=None, closed=None, assignee=None):
            return {
                "number": n,
                "title": f"Issue {n}",
                "state": state,
                "labels": [{"name": x} for x in labels],
                "createdAt": created,
                "closedAt": closed,
                "url": f"https://github.com/acme/widgets/issues/{n}",
                "assignees": [{"login": assignee}] if assignee else [],
            }

        self.issues = [
            issue(201, "OPEN", ["opus"], "2026-10-20T14:00:00Z"),  # routed, no card
            issue(202, "OPEN", [], "2026-10-19T14:00:00Z"),  # nobody has it: Triage's, not the Agenda's
            issue(203, "OPEN", ["opus"]),  # its card is In Progress: in somebody's hands
            issue(204, "OPEN", ["opus", walk], "2026-10-18T10:00:00Z"),  # on the walk
            issue(205, "CLOSED", ["opus"], None, "2026-10-24T02:30:00Z"),  # closed Friday evening, local time
            issue(206, "OPEN", ["opus"]),  # its card is in Code Review
            issue(207, "OPEN", [], "2026-10-19T14:00:00Z", assignee="someone"),  # someone else's
        ]
        self.filled = standup.fill_joined_standup(
            datetime.fromisoformat(self.AS_OF),
            self.labels,
            self.issues,
            {"ok": True, "reason": ""},
            self.cards,
            space="widgets",
            space_name="Widgets",
        )

    def tearDown(self):
        self.tmp.cleanup()

    def _agenda(self):
        return self.agenda.build_agenda(self.filled, self.labels, self.issues, self.cards, "", "widgets")

    def test_what_moved_is_the_windows_closes_once_each_dated_in_the_standups_own_offset(self):
        moved = self._agenda().moved
        self.assertEqual(
            [(i.ref, i.kind, i.day, i.review) for i in moved],
            [("#205", "issue", "2026-10-23", False), ("Q3R9", "card", "2026-10-24", False)],
        )
        # An archived card is not on the card page (it reads current/): no file to open.
        self.assertEqual(moved[1].file, "")
        self.assertEqual(moved[0].url, "https://github.com/acme/widgets/issues/205")

    def test_waiting_is_active_cards_code_review_and_routed_issues_never_in_progress_or_backlog(self):
        waiting = self._agenda().waiting
        self.assertEqual(
            [(i.ref, i.kind, i.lane, i.day, i.review) for i in waiting],
            [
                ("#201", "issue", "", "2026-10-20", False),
                ("K7M2", "card", C.status_active(), "2026-10-23", False),
                ("#204", "issue", "", "2026-10-18", True),
                ("#206", "issue", C.status_code_review(), "2026-10-22", True),
            ],
        )
        refs = {i.ref for i in waiting}
        for absent in ("#202", "#203", "#207", "P4X8", "B1B1", "Z9Z9"):
            self.assertNotIn(absent, refs)

    def test_a_cards_tile_carries_the_boards_face_and_the_file_the_card_page_opens(self):
        k7 = next(i for i in self._agenda().waiting if i.ref == "K7M2")
        self.assertEqual((k7.checked, k7.total, k7.progress), (1, 2, "1/2"))
        self.assertEqual(k7.file, "TaskK7M2-wire-the-board.prompt.md")
        self.assertIsNone(k7.cover)
        review = next(i for i in self._agenda().waiting if i.ref == "#206")
        self.assertEqual(review.file, "206-in-review.prompt.md")

    def test_the_suggestions_pick_is_first_wherever_it_is_on_the_agenda(self):
        # Take the unrouted issue out: the pick is then a routed one, and it leads.
        self.issues = [i for i in self.issues if i["number"] != 202]
        self.suggest.attach_suggestions(self.filled, self.labels, self.issues, self.cards, "agents", True, "tk")
        self.assertEqual(self._agenda().waiting[0].ref, self.filled.suggestion.ref)

    def test_no_tracker_no_agenda(self):
        filled = standup.fill_joined_standup(
            datetime.fromisoformat(self.AS_OF), [], [], {"ok": False, "reason": "gh is away"}, self.cards
        )
        empty = self.agenda.build_agenda(filled, [], [], self.cards)
        self.assertEqual((empty.moved, empty.waiting), ([], []))

    def test_a_cards_space_is_its_cards(self):
        filled = standup.fill_cards_standup(datetime.fromisoformat(self.AS_OF), self.cards, space="solo")
        got = self.agenda.build_agenda(filled, [], [], self.cards)
        self.assertEqual([i.ref for i in got.moved], ["Q3R9"])
        self.assertEqual([i.ref for i in got.waiting], ["K7M2", "206"])
        self.assertTrue(got.waiting[1].review)


if __name__ == "__main__":
    unittest.main(verbosity=2)
