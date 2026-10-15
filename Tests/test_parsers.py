"""Tests for the prompt-file parsers in the agent.

The Python parsers (_parse_status_metadata, _parse_pr_comments) are canonical
for the prompt-file markdown format. Get-PromptStatus.ps1 implements
equivalent logic in PowerShell against the same fixtures in
Tests/fixtures/parsers/; if you change either parser, run this suite to verify
behaviour still matches the fixture expectations.

Run directly:  python3 Tests/test_parsers.py
Under pytest:  python3 -m pytest Tests/
"""

import os
import sys
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent.ado.pr_comments import _parse_pr_comments
    from agent.ado.reporting import _closed_dates
    from agent.core import log as agent_log
    from agent.core.log import _parse_test_log, _scope_entries_to_org
    from agent.core.parsers import _parse_status_metadata, status_sort_key
except Exception as e:
    skip_module(f"cannot import agent ({type(e).__name__}: {e})")

FIXTURES = Path(__file__).parent / "fixtures" / "parsers"


def _read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class StatusMetadataTests(unittest.TestCase):
    def test_active_status(self):
        meta = _parse_status_metadata(_read("active.md"))
        self.assertEqual(meta["status"], "Active")

    def test_active_title(self):
        # Fixture title is 62 chars; parser truncates at 60 (57 + "...").
        meta = _parse_status_metadata(_read("active.md"))
        self.assertEqual(
            meta["title"],
            "Bug 59: Redirect URI mismatch on localhost with trailing ...",
        )

    def test_active_progress(self):
        meta = _parse_status_metadata(_read("active.md"))
        self.assertEqual(meta["checked"], 0)
        self.assertEqual(meta["total"], 3)
        self.assertEqual(meta["progress"], "0/3")

    def test_active_sprint(self):
        meta = _parse_status_metadata(_read("active.md"))
        self.assertEqual(meta["sprint"], "Demo Sprint 1")

    def test_active_ado_url(self):
        # The fixtures carry the template org, not anyone's real one -- the
        # package ships with `https://dev.azure.com/YOUR-ADO-ORG` in
        # config.default.json and a fixture that said otherwise was a second
        # committed copy of a real org name.
        #
        # Asserted by SHAPE rather than by the literal, so editing the fixture
        # does not turn a second file red: what the parser owes us is the whole
        # link off the `**ADO Link:**` line, ending in the work item id.
        meta = _parse_status_metadata(_read("active.md"))
        self.assertIsNotNone(meta["ado_url"])
        self.assertTrue(meta["ado_url"].startswith("https://dev.azure.com/"))
        self.assertTrue(meta["ado_url"].endswith("/_workitems/edit/59"))
        self.assertEqual(
            meta["ado_url"],
            "https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/59",
        )
        self.assertIsNone(meta["pr_url"])

    def test_a_card_that_came_back_names_its_previous_round(self):
        """The `> Previous round:` token (consts.json tokens.previousRound). The CLI
        reads it with Get-P20PreviousRoundPath; Tests/Test-Archive.ps1 asserts the
        SAME fixtures, so the two readers cannot drift."""
        meta = _parse_status_metadata(_read("previous-round.md"))
        self.assertEqual(
            meta["previous_round"],
            "../archive/59-redirect-uri-mismatch-on-localhost-with-trailing-slash-r2.prompt.md",
        )
        crlf = _read("previous-round.md").replace("\r\n", "\n").replace("\n", "\r\n")
        self.assertEqual(_parse_status_metadata(crlf)["previous_round"], meta["previous_round"])
        # No line, no previous round -- the common case.
        self.assertIsNone(_parse_status_metadata(_read("active.md"))["previous_round"])

    def test_the_design_a_card_names_by_the_shared_table(self):
        """The `> Design:` / `> Spec:` line (docs/hub/cards.md,
        consts.json design.cardLineRegex). The CLI reads it with
        Get-P20CardDesign; Tests/Test-Design.ps1 asserts the SAME table,
        Tests/fixtures/parsers/design-lines.json, so the two readers cannot drift."""
        import json

        from agent.core.parsers import card_design

        table = json.loads((FIXTURES / "design-lines.json").read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["rows"]), 10)
        for row in table["rows"]:
            with self.subTest(row=row["name"]):
                eol = "\r\n" if row["crlf"] else "\n"
                text = eol.join(row["lines"]) + eol
                self.assertEqual(card_design(text), row["expected"])
                # The model carries it as the card's `design`.
                self.assertEqual(_parse_status_metadata(text)["design"], row["expected"])

    def test_in_progress_status(self):
        meta = _parse_status_metadata(_read("in-progress.md"))
        self.assertEqual(meta["status"], "In Progress")

    def test_in_progress_progress(self):
        meta = _parse_status_metadata(_read("in-progress.md"))
        self.assertEqual(meta["checked"], 2)
        self.assertEqual(meta["total"], 4)
        self.assertEqual(meta["progress"], "2/4")

    def test_in_progress_sprint_last_segment(self):
        # "Search Coach\Sprint 4" -> "Sprint 4"
        meta = _parse_status_metadata(_read("in-progress.md"))
        self.assertEqual(meta["sprint"], "Sprint 4")

    def test_a_persons_started_line_is_in_progress_with_nothing_committed(self):
        """Two writers per lane. Tests/Test-Status.ps1 asserts the SAME
        fixture."""
        meta = _parse_status_metadata(_read("started-line.md"))
        self.assertEqual(meta["status"], "In Progress")

    def test_commits_counts_the_git_token_and_not_a_persons_started_line(self):
        """`commits` is what the web's Create PR gate reads (web/src/modules/ado/
        cardActions.ts): In Progress by a **Started:** line has nothing to open a
        pull request from, and says so. `- (pending)` is a placeholder, not a commit."""
        self.assertEqual(
            {
                name: _parse_status_metadata(_read(name))["commits"]
                for name in ("active.md", "in-progress.md", "started-line.md", "code-review.md")
            },
            {"active.md": 0, "in-progress.md": 2, "started-line.md": 0, "code-review.md": 1},
        )
        self.assertEqual(_parse_status_metadata("")["commits"], 0)

    def test_a_persons_review_line_is_code_review_with_no_pull_request(self):
        """...and, like the PR URL line, it outranks the commit bullet."""
        meta = _parse_status_metadata(_read("review-line.md"))
        self.assertEqual(meta["status"], "Code Review")
        self.assertIsNone(meta["pr_url"])

    def test_a_review_heading_without_a_pr_url_line_is_not_code_review(self):
        """The PR URL LINE is the gate -- the CLI's rule, and Tests/Test-Status.ps1
        asserts this SAME fixture. The agent once read it as Code Review.
        """
        meta = _parse_status_metadata(_read("review-heading-no-url.md"))
        self.assertEqual(meta["status"], "In Progress")
        self.assertIsNone(meta["pr_url"])

    def test_code_review_status(self):
        meta = _parse_status_metadata(_read("code-review.md"))
        self.assertEqual(meta["status"], "Code Review")

    def test_code_review_pr_url(self):
        meta = _parse_status_metadata(_read("code-review.md"))
        self.assertTrue(meta["pr_url"].endswith("/pullrequest/140123"))

    def test_empty_content(self):
        meta = _parse_status_metadata("")
        self.assertEqual(meta["status"], "Active")
        self.assertEqual(meta["title"], "")
        self.assertEqual(meta["progress"], "--")
        self.assertEqual(meta["sprint"], "--")
        self.assertEqual(meta["checked"], 0)
        self.assertEqual(meta["total"], 0)
        self.assertIsNone(meta["ado_url"])
        self.assertIsNone(meta["pr_url"])

    def test_title_truncation(self):
        long_title = "x" * 100
        meta = _parse_status_metadata(f"# {long_title}\n")
        self.assertEqual(len(meta["title"]), 60)
        self.assertTrue(meta["title"].endswith("..."))

    def test_sprint_truncation(self):
        # Sprint > 20 chars truncates to 18 + ".."
        meta = _parse_status_metadata("**Sprint:** A very long sprint name indeed\n")
        self.assertEqual(len(meta["sprint"]), 20)
        self.assertTrue(meta["sprint"].endswith(".."))


class LineEndingTests(unittest.TestCase):
    """A card written on Windows and a card written on macOS parse the same.

    The toolkit writes LF and keeps whatever a file already has (see
    Scripts/Add-ClosedStamp.ps1's Write-CardText), but a hub is a user's own
    folder: a card edited in Notepad comes back CRLF, and one saved by an editor
    that "helpfully" adds a BOM comes back with one. Neither may change an
    answer. The readers are all multiline regexes, so this is the assertion that
    keeps them that way.
   
    """

    FIXTURES = [
        "active.md",
        "in-progress.md",
        "code-review.md",
        "review-heading-no-url.md",
        "started-line.md",
        "review-line.md",
    ]

    def test_crlf_and_lf_parse_identically(self):
        for name in self.FIXTURES:
            with self.subTest(fixture=name):
                lf = _read(name).replace("\r\n", "\n")
                crlf = lf.replace("\n", "\r\n")
                self.assertEqual(_parse_status_metadata(crlf), _parse_status_metadata(lf))

    def test_crlf_does_not_leak_into_a_field(self):
        crlf = _read("code-review.md").replace("\r\n", "\n").replace("\n", "\r\n")
        meta = _parse_status_metadata(crlf)
        for key in ("title", "sprint", "progress", "ado_url", "pr_url", "status"):
            value = meta[key]
            if isinstance(value, str):
                self.assertNotIn("\r", value, f"{key} carried a carriage return")

    def test_pr_comments_parse_identically(self):
        lf = _read("pr-multi-round.md").replace("\r\n", "\n")
        crlf = lf.replace("\n", "\r\n")
        self.assertEqual(_parse_pr_comments(crlf), _parse_pr_comments(lf))


class ClosedStampTests(unittest.TestCase):
    """The "**Closed:**" stamp is a contract between the CLI and this half.

    agent/ado/reporting.py derives the billing timeline from it, so the date it
    reads out of an archived card cannot depend on which host stamped it: CRLF
    or LF, BOM or none. The CLI side asserts the same thing in
    Tests/Test-Archive.ps1.
    """

    BODY = "# US-900 Something\n\n**Created:** 2026-01-02\n**Closed:** 2026-03-04\n"

    def test_every_byte_shape_yields_the_same_date(self):
        import tempfile
        from unittest import mock

        from agent.ado import reporting

        shapes = {
            "lf-nobom": (self.BODY, "utf-8"),
            "crlf-nobom": (self.BODY.replace("\n", "\r\n"), "utf-8"),
            "lf-bom": (self.BODY, "utf-8-sig"),
            "crlf-bom": (self.BODY.replace("\n", "\r\n"), "utf-8-sig"),
            # The exact shape seen on Windows: CRLF file, one bare LF at the end.
            "crlf-plus-bare-lf": (
                self.BODY.replace("\n", "\r\n")[: -len("**Closed:** 2026-03-04\r\n")] + "**Closed:** 2026-03-04\n",
                "utf-8",
            ),
        }
        for name, (text, encoding) in shapes.items():
            with self.subTest(shape=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                archive = root / "test" / "archive"
                archive.mkdir(parents=True)
                (archive / "US-900-something.prompt.md").write_text(text, encoding=encoding)
                with mock.patch.object(reporting, "hub_root", lambda root=root: root):
                    self.assertEqual(_closed_dates({"promptsFolder": "test"}), ["2026-03-04"])


class PrCommentsTests(unittest.TestCase):
    def test_no_pr_section(self):
        pr_id, round_num, comments = _parse_pr_comments(_read("active.md"))
        self.assertEqual(pr_id, 0)
        self.assertEqual(round_num, 1)
        self.assertEqual(comments, [])

    def test_single_round_pr_id(self):
        pr_id, round_num, _ = _parse_pr_comments(_read("code-review.md"))
        self.assertEqual(pr_id, 140123)
        self.assertEqual(round_num, 1)

    def test_single_round_comment_count(self):
        _, _, comments = _parse_pr_comments(_read("code-review.md"))
        self.assertEqual(len(comments), 2)

    def test_comment_fields(self):
        _, _, comments = _parse_pr_comments(_read("code-review.md"))
        c = comments[0]
        self.assertEqual(c["number"], 1)
        self.assertEqual(c["thread_id"], 1342185)
        self.assertEqual(c["file_path"], "/src/components/Foo.tsx")
        self.assertEqual(c["line"], 23)
        self.assertEqual(c["reviewer"], "PR Assistant (AI Code Review)")
        self.assertEqual(c["severity"], "High")
        self.assertEqual(c["category"], "Accessibility")
        self.assertEqual(c["status"], "active")
        self.assertTrue(c["is_open"])

    def test_resolved_comment_is_not_open(self):
        _, _, comments = _parse_pr_comments(_read("code-review.md"))
        c = comments[1]
        self.assertEqual(c["decision"], "take")
        self.assertEqual(c["reply"], "Fixed in abc1234.")
        self.assertFalse(c["is_open"])

    def test_multi_round_picks_highest_round(self):
        pr_id, round_num, comments = _parse_pr_comments(_read("pr-multi-round.md"))
        self.assertEqual(pr_id, 140123)
        self.assertEqual(round_num, 2)
        self.assertEqual(len(comments), 2)


class TestLogOrgColumnTests(unittest.TestCase):
    """The test-results log gained a 7th org column. Org-scoped suites (Billing,
    Review) are tagged with the active Space; system suites carry no org. Legacy
    6-column rows must still parse as system (empty org)."""

    def setUp(self):
        # Drive _parse_test_log at a unique machine name so it reads our temp
        # log and never collides with a real test-results.{machine}.log.
        self._machine = "PARSERTEST-ORGCOL"
        self._prev_computername = os.environ.get("COMPUTERNAME")
        os.environ["COMPUTERNAME"] = self._machine
        self._log_path = agent_log.REPO_ROOT / f"test-results.{self._machine}.log"
        rows = [
            "# header comment is skipped",
            # org-scoped rows under two different orgs
            "2026-05-30T07:48:00\tBilling\tfail\t53\t87\tFAIL billing\tdemo",
            "2026-05-30T07:50:00\tBilling\tpass\t87\t87\tok\tglobex",
            # system row — no org tag
            "2026-05-30T07:48:10\tCompat\tpass\t311\t311\tok\t",
            # legacy 6-column row (no org column at all)
            "2026-05-30T07:48:20\tSnapshot\tpass\t34\t34\tok",
        ]
        self._log_path.write_text("\n".join(rows) + "\n", encoding="utf-8")

    def tearDown(self):
        self._log_path.unlink(missing_ok=True)
        if self._prev_computername is None:
            os.environ.pop("COMPUTERNAME", None)
        else:
            os.environ["COMPUTERNAME"] = self._prev_computername

    def test_org_column_parsed(self):
        by_suite = {(e["suite"], e["org"]): e for e in _parse_test_log()}
        self.assertEqual(by_suite[("Billing", "demo")]["result"], "fail")
        self.assertEqual(by_suite[("Billing", "globex")]["result"], "pass")

    def test_system_row_has_empty_org(self):
        compat = next(e for e in _parse_test_log() if e["suite"] == "Compat")
        self.assertEqual(compat["org"], "")

    def test_legacy_six_column_row_parses_as_system(self):
        snap = next(e for e in _parse_test_log() if e["suite"] == "Snapshot")
        self.assertEqual(snap["org"], "")
        self.assertEqual(snap["passed"], 34)


class ScopeEntriesToOrgTests(unittest.TestCase):
    ENTRIES = [
        {"suite": "Compat", "org": ""},  # system — always shown
        {"suite": "Billing", "org": "demo"},
        {"suite": "Billing", "org": "globex"},
        {"suite": "Snapshot"},  # legacy: no org key at all
    ]

    def test_active_space_includes_system_and_matching(self):
        kept = _scope_entries_to_org(self.ENTRIES, "demo")
        suites = [(e["suite"], e.get("org", "")) for e in kept]
        self.assertIn(("Compat", ""), suites)
        self.assertIn(("Billing", "demo"), suites)
        self.assertIn(("Snapshot", ""), suites)
        self.assertNotIn(("Billing", "globex"), suites)

    def test_other_org_excludes_nonmatching(self):
        kept = _scope_entries_to_org(self.ENTRIES, "globex")
        orgs = {e.get("org", "") for e in kept}
        self.assertNotIn("demo", orgs)
        self.assertEqual(len(kept), 3)  # system + legacy + globex Billing


class StatusSortOrderTests(unittest.TestCase):
    """The ledger's order, which the CLI and the agent must agree on.

    ``tkStatus`` printed a different order on Windows PowerShell 5.1 than on
    pwsh 7 against the same hub, because it sorted on state alone and 5.1's
    ``Sort-Object`` is not stable. Both halves now sort on (state, file name),
    ordinal. The names below are the ones that reproduced it, and
    Tests/Test-Status.ps1 runs Get-PromptStatus.ps1 for real against the same
    set and expects the same list.
    """

    ACTIVE = [
        "US-142-foxtrot.prompt.md",
        "141-charlie.prompt.md",
        "Task139-delta.prompt.md",
        "114-alpha.prompt.md",
        "US-119-echo.prompt.md",
        "137-bravo.prompt.md",
    ]

    def test_one_state_orders_by_file_name(self):
        rows = [("Active", name) for name in self.ACTIVE]
        ordered = [f for _, f in sorted(rows, key=lambda r: status_sort_key(*r))]
        self.assertEqual(
            ordered,
            [
                "114-alpha.prompt.md",
                "137-bravo.prompt.md",
                "141-charlie.prompt.md",
                "Task139-delta.prompt.md",
                "US-119-echo.prompt.md",
                "US-142-foxtrot.prompt.md",
            ],
        )

    def test_state_outranks_the_name(self):
        # Named to sort first if the state were ignored.
        rows = [
            ("Code Review", "002-code-review.prompt.md"),
            ("In Progress", "001-in-progress.prompt.md"),
            ("Active", "114-alpha.prompt.md"),
        ]
        ordered = [f for _, f in sorted(rows, key=lambda r: status_sort_key(*r))]
        self.assertEqual(
            ordered,
            [
                "114-alpha.prompt.md",
                "001-in-progress.prompt.md",
                "002-code-review.prompt.md",
            ],
        )

    def test_an_unknown_state_sorts_last_rather_than_raising(self):
        rows = [("Nonsense", "a.prompt.md"), ("Code Review", "z.prompt.md")]
        ordered = [f for _, f in sorted(rows, key=lambda r: status_sort_key(*r))]
        self.assertEqual(ordered, ["z.prompt.md", "a.prompt.md"])

    def test_the_route_sorts_with_this_key(self):
        # The route must not carry its own copy of the ordering.
        source = (PKG_ROOT / "agent" / "ado" / "status.py").read_text(encoding="utf-8")
        self.assertIn("status_sort_key(p.status, p.file)", source)


def _run() -> int:
    loader = unittest.defaultTestLoader
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2, stream=sys.stdout)
    result = runner.run(suite)
    total = result.testsRun
    passed = total - len(result.failures) - len(result.errors)
    print(f"\n  Results: {passed}/{total} passed")
    return 0 if result.wasSuccessful() else 1


class CardModelTests(unittest.TestCase):
    """The Card model (docs/hub/cards.md): type and name are FIELDS,
    read from the H1 against the configured type names -- not a sentence the web
    has to take apart."""

    def _meta(self, heading, names=("User Story", "Task", "Feature", "Bug", "Spike"), body=""):
        return _parse_status_metadata(f"# {heading}\n\n{body}", names)

    def test_type_and_name_come_out_of_the_heading(self):
        m = self._meta("Bug 141: Recipe search returns duplicates")
        self.assertEqual((m["type"], m["name"]), ("Bug", "Recipe search returns duplicates"))

    def test_a_two_word_type_is_not_read_as_its_first_word(self):
        m = self._meta("User Story 119: Refactor usePlayerHook")
        self.assertEqual((m["type"], m["name"]), ("User Story", "Refactor usePlayerHook"))

    def test_a_card_with_no_work_item_has_a_type_like_any_other(self):
        m = self._meta("Spike K7M2: Wallet ticket from a QR code")
        self.assertEqual((m["type"], m["name"]), ("Spike", "Wallet ticket from a QR code"))

    def test_a_large_story_keeps_its_type_behind_the_emoji(self):
        m = self._meta("\U0001f966 User Story 144: Import flow")
        self.assertEqual(m["type"], "User Story")

    def test_a_teams_own_type_is_known_when_config_names_it(self):
        self.assertIsNone(self._meta("Chore 12: Rotate the keys")["type"])
        m = self._meta("Chore 12: Rotate the keys", names=("Bug", "Chore"))
        self.assertEqual((m["type"], m["name"]), ("Chore", "Rotate the keys"))

    def test_a_heading_that_names_no_type_has_no_type_and_keeps_its_words(self):
        m = self._meta("Notes from Tuesday")
        self.assertEqual((m["type"], m["name"]), (None, "Notes from Tuesday"))

    def test_linked_is_the_whole_difference_between_an_ado_card_and_any_other(self):
        linked = self._meta("Bug 141: x", body="**ADO Link:** https://dev.azure.com/o/p/_workitems/edit/141\n")
        unlinked = self._meta("Bug K7M2: x", body="**ADO Link:** (not linked -- created offline with -Title)\n")
        self.assertTrue(linked["linked"])
        self.assertFalse(unlinked["linked"])
        # ...and nothing else about the two differs.
        self.assertEqual(linked["status"], unlinked["status"])

    def test_title_is_still_the_whole_heading_for_what_already_reads_it(self):
        self.assertEqual(self._meta("Bug 141: Recipe search")["title"], "Bug 141: Recipe search")


class CardIdTests(unittest.TestCase):
    """One table, two readers. ``fixtures/parsers/card-ids.json`` is read here
    AND by ``Tests/Test-Archive.ps1`` against ``Scripts/Resolve-CardName.ps1``.
    If Python and PowerShell ever disagree about a row, one of them is wrong."""

    @classmethod
    def setUpClass(cls):
        import json

        cls.table = json.loads((FIXTURES / "card-ids.json").read_text(encoding="utf-8"))

    def test_every_name_in_the_shared_table(self):
        from agent.core.parsers import card_id

        for name, expected in self.table["names"]:
            with self.subTest(name=name):
                self.assertEqual(card_id(name, self.table["prefixes"]), expected)

    def test_an_id_is_a_string_even_when_it_is_a_number(self):
        from agent.core.parsers import card_id

        self.assertEqual(card_id("141-x.prompt.md"), "141")
        self.assertIsInstance(card_id("141-x.prompt.md"), str)

    def test_with_no_prefixes_a_prefixed_card_has_no_id(self):
        """The prefixes are a CLOSED set from config, never "any run of letters":
        that is what stops ``goal-2027-...`` reading as id 2027."""
        from agent.core.parsers import card_id

        self.assertIsNone(card_id("Task139-x.prompt.md"))
        self.assertEqual(card_id("Task139-x.prompt.md", ["Task"]), "139")


if __name__ == "__main__":
    sys.exit(_run())
