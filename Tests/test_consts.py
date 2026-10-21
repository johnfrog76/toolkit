"""consts.json parses here, this half reads it, and no Python source retypes it.

``consts.json`` at the package root holds the literals that cross a half
boundary. Three tests, one per side, guard it: this one, ``Tests/Test-Consts.ps1``
and ``web/src/shell/consts.test.ts``. Together they are the parity check the
issue asked for -- every half reports the value it resolved for every key, and
a value that stops agreeing fails somewhere rather than drifting.

Run directly:  python3 Tests/test_consts.py
Under pytest:  python3 -m pytest Tests/
"""

import ipaddress
import json
import re
import sys
import unittest
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module  # noqa: E402

try:
    from agent.core import consts as C
except Exception as e:  # pragma: no cover
    skip_module(f"cannot import agent.core.consts ({type(e).__name__}: {e})")

CONSTS_PATH = PKG_ROOT / "consts.json"

# The values, written out. This is the point of a parity test: if someone edits
# consts.json, THIS file is where they are made to say so out loud, and the
# PowerShell and TypeScript sides assert the same strings.
EXPECTED = {
    # The package's own repository: the agent's fallback for a Space that is this
    # package itself when a copy has no git origin to read.
    ("repository", "url"): "https://github.com/johnfrog76/toolkit",
    ("stamps", "closed"): "**Closed:**",
    ("stamps", "created"): "**Created:**",
    ("stamps", "billable"): "**Billable:**",
    # Who takes a card with no issue behind it (D-AR10): Route -Assign writes it.
    ("stamps", "assigned"): "**Assigned:**",
    ("stamps", "started"): "**Started:**",
    ("stamps", "outcome"): "**Outcome:**",
    ("stamps", "review"): "**Review:**",
    ("tokens", "prUrl"): "PR URL:",
    ("tokens", "prReviewHeading"): "## PR Review Comments",
    ("tokens", "previousRound"): "> Previous round:",
    # The design a card names (docs/hub/cards.md).
    ("tokens", "design"): "> Design:",
    ("tokens", "spec"): "> Spec:",
    ("regex", "prUrlLine"): r"(?m)^PR URL:\s*https://",
    ("regex", "prReviewHeading"): r"(?m)^##\s+PR Review Comments",
    ("regex", "commitBullet"): r"(?m)^\s*-\s+`?([0-9a-f]{7,})`?",
    ("regex", "startedLine"): r"(?m)^\*\*Started:\*\*",
    ("regex", "reviewLine"): r"(?m)^\*\*Review:\*\*",
    ("regex", "sessionName"): r"^(?:([a-z0-9]+(?:-[a-z0-9]+)*)-)?(\d{4}-\d{2}-\d{2})\.md$",
    ("regex", "cardId"): r"(?:\d+|(?=[A-Z0-9]{0,3}[0-9])(?=[A-Z0-9]{0,3}[A-Z])[ACDEFGHJKMNPQRTUVWXY234679]{4})",
    ("status", "backlog"): "Backlog",
    ("status", "active"): "Active",
    ("status", "inProgress"): "In Progress",
    ("status", "codeReview"): "Code Review",
    ("status", "done"): "Done",
    ("folders", "current"): "current",
    ("folders", "archive"): "archive",
    ("folders", "backlog"): "backlog",
    ("reviews", "fileName"): "review.md",
    ("reviews", "slugSetSeparator"): "+",
    ("features", "spaceScoped"): ["sprintAwareness", "trainingHoursPerQuarter", "suggestions"],
    ("env", "activeSpace"): "P20_ACTIVE_SPACE",
    ("env", "features"): "P20_FEATURES",
    ("env", "agentPort"): "P20_AGENT_PORT",
    ("env", "teamsWebhookPrefix"): "TEAMS_WEBHOOK_",
    ("env", "testRunMarker"): "P20_TEST_RUN",
    ("agent", "bindHost"): "127.0.0.1",
    ("stamps", "sent"): "Sent to",
    ("stamps", "due"): "**Due:**",
    ("stamps", "source"): "**Source:**",
    ("stamps", "ref"): "**Ref:**",
    # A card's pictures (docs/hub/cards.md).
    ("stamps", "cover"): "**Cover:**",
    ("stamps", "before"): "**Before:**",
    ("folders", "assets"): "assets",
    ("assets", "coverExtensions"): ["png", "jpg", "jpeg", "webp", "gif"],
    ("assets", "coverMaxBytes"): 5242880,
    ("regex", "dueLine"): r"(?m)^\*\*Due:\*\*[ \t]*(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}))?",
    ("reminders", "buckets"): ["overdue", "today", "upcoming"],
    ("reminders", "snooze"): ["1h", "tomorrow", "nextweek"],
    # The three halves a test run covers: Test writes them, log.py serves them.
    ("tests", "halves"): ["agent", "cli", "web"],
    ("tests", "legacyHalf"): "cli",
    ("visibility", "public"): "public",
    ("visibility", "private"): "private",
    ("visibility", "unknown"): "unknown",
    ("visibility", "publicLine"): "This repository is public",
    ("docs", "readme"): "README.md",
    ("docs", "root"): "docs",
    ("docs", "segment"): r"^[A-Za-z0-9_][A-Za-z0-9._-]*$",
    ("docs", "landingUrl"): "https://johnfrog76.github.io/toolkit/",
    ("spaces", "renamed"): {"test": "azure-demo"},
    ("studio", "noteName"): r"^[A-Za-z0-9][A-Za-z0-9._-]*\.md$",
    ("studio", "threadLine"): "> GitHub:",
    ("studio", "promoteLabel"): "design",
    ("studio", "promptsRoute"): "/api/studio/prompts",
    ("design", "idKey"): "id",
    ("design", "idRegex"): r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    ("design", "states"): ["Design", "Spec", "Complete", "Archived"],
    ("design", "outcomes"): ["shipped", "dropped"],
    ("design", "docsLine"): "> Docs:",
    ("design", "docsRegex"): r"(?m)^>\s*Docs:\s*(\S.*?)\s*$",
    (
        "design",
        "cardLineRegex",
    ): r"(?m)^>[ \t]*(Design|Spec):[ \t]*(?:\[([^\]\r\n]*)\]\(([^)\r\n]*)\))?[ \t]*([^\r\n]*?)[ \t]*\r?$",
    ("studio", "threadRegex"): r"(?m)^>\s*GitHub:\s*(https://github\.com/([^/\s]+)/([^/\s]+)/issues/(\d+))\s*$",
    ("rituals", "route"): "/api/ritual/standup",
    ("rituals", "triageRoute"): "/api/ritual/triage",
    ("rituals", "assignMe"): "me",
    ("rituals", "ceremoniesFile"): "Config/ceremonies.json",
    ("rituals", "vocabularyFile"): "Config/standup-vocabulary.json",
    ("rituals", "workerLabelPrefix"): "Routed to",
    ("rituals", "walkLabel"): "verify-close",
    ("rituals", "labelWidth"): 9,
    ("rituals", "attendRoute"): "/api/ritual/standup/attend",
    ("rituals", "remindRoute"): "/api/ritual/standup/remind",
    ("rituals", "remindSource"): "standup",
    ("rituals", "remindTitle"): "Standup",
    ("rituals", "remindDays"): "Mon-Fri",
    ("rituals", "weekdays"): ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    # The work grain (D-TA20).
    ("rituals", "grains"): ["detail", "work", "brief"],
    ("rituals", "numberWords"): [
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
    ],
    ("rituals", "workHeadRegex"): r"^(?:[A-Za-z]+:\s+)?(.+?)(?:\s+--\s+|:\s+|$)",
    ("rituals", "workThreadRegex"): r"(?m)^>\s*GitHub:\s*<?(?:https://github\.com/[^/\s>]+/[^/\s>]+/issues/|#)(\d+)",
    ("rituals", "workDesignRegex"): r"design/([A-Za-z0-9][A-Za-z0-9_-]*)\.md",
    ("rituals", "workSmallWordRegex"): r"^[a-z]{1,3}$",
    # The also-ons fold (D-SA9): the most groups a folded sentence names.
    ("rituals", "proseFoldNames"): 4,
    # The dress (D-SA11): the guard's checks in order, and its four patterns.
    ("rituals", "dressGuards"): [
        "empty",
        "ref-added",
        "ref-dropped",
        "number",
        "count-dropped",
        "kind",
        "name-dropped",
        "name",
    ],
    (
        "rituals",
        "dressRefRegex",
    ): r"#\d+|(?<![\w#])(?=[A-Z0-9]{0,3}[0-9])(?=[A-Z0-9]{0,3}[A-Z])[ACDEFGHJKMNPQRTUVWXY234679]{4}(?!\w)",
    ("rituals", "dressNumberRegex"): r"(?<![\w#])\d+(?!\w)",
    ("rituals", "dressNameRegex"): r"(?<![\w'-])[A-Z][A-Za-z0-9'-]*",
    ("rituals", "dressPronounRegex"): r"^I(?:'[a-z]+)?$",
    # What moved: a slot item's motion, and the hash its card's bullet threads.
    ("rituals", "motions"): ["closed", "started", "inProgress"],
    ("rituals", "suggestShapes"): ["start", "delegate", "route", "place"],
    ("rituals", "suggestOwnerSeat"): "fable",
    ("rituals", "suggestExclusions"): ["notBillable", "waiting", "inFlight", "theirs", "dismissed"],
    ("rituals", "text"): {
        "title": "Standup -- {date}",
        "dateFormat": "dddd d MMMM yyyy",
        "queueHeading": "Waiting on you",
        "queueEmpty": "Nothing is waiting on you.",
        "walk": "Walk",
        "tracker": "Tracker",
        "yesterday": "Yesterday",
        "today": "Today",
        "blockers": "Blockers",
        "mug": "Mug",
        "yesterdayEmpty": "nothing closed",
        "todayEmpty": "nothing in flight",
        "blockersEmpty": "no blockers",
        "blockerSuffix": " (verify-close)",
        "noWorkers": "No worker labels in this Space.",
        "adoTracker": "Azure DevOps is the human team's board, and its standup is the one the team holds; "
        "Team Agile reads a GitHub Space's issues and cards, or a local Space's cards.",
        "check": "Check",
        "checkCardArchived": "{item} -- the card is archived, but the issue is still open.",
        "checkIssueClosed": "{item} -- the issue is closed, but the card is not archived.",
        "briefWalkOne": "walk",
        "briefWalkMany": "walks",
        "briefDecideOne": "decision",
        "briefDecideMany": "decisions",
        "briefLookOne": "look",
        "briefLookMany": "looks",
        "briefAllPc": "all on the PC",
        "briefWhoPc": "the PC",
        "briefWhoYou": "you",
        "briefClosed": "{n} closed yesterday",
        "briefClosedNone": "nothing yesterday",
        "briefOpen": "{n} open",
        "briefOpenNone": "nothing open",
        "briefInFlight": "none in flight",
        "briefBlocker": "{n} blocker",
        "briefBlockers": "{n} blockers",
        "briefWorkerNone": "nothing today",
        "briefInFlightUnknown": "In flight is not yet known: every routed issue reads as open.",
        "briefNext": "Next: the {kind} -- {n} on {who}.",
        "briefNextNone": "Next: nothing is waiting on you.",
        "suggestNext": "Next: {sentence} ({command})",
        "suggestStart": "{ref} is {why} -- start it?",
        "suggestDelegate": "{ref} is {size}-sized and well defined -- send it to the crew?",
        "suggestRoute": "{ref} is {why}{nobody} -- route it?",
        "suggestNobody": " and nobody has it",
        "suggestPlace": "{ref} is {size}-sized but has no milestone -- place it?",
        "suggestWhyLast": "the last open {noun} in milestone {milestone}",
        "suggestWhyMilestone": "the oldest open {kind} in milestone {milestone}",
        "suggestWhyOldest": "the oldest open {kind}",
        "suggestNounCard": "card",
        "suggestNounIssue": "issue",
        "suggestCommandStart": "StartWork {arg}",
        "suggestCommandRoute": "Route {arg} -Assign <me|size>",
        "suggestCommandPlace": "Route {arg} -Milestone <title>",
        "suggestCommandPlaceCard": "Plan {arg} -Milestone <title>",
        "workYesterday": "{name}, {n} closed",
        "workToday": "{name}, {n}",
        "workBlockers": "{name}, {n} to walk",
        "workWalk": "{name}, {n} to walk",
        "workGroup": "{name}, {n}",
        # The prose: the work grain spoken as standup language.
        "proseSentence": "{lead} {body}.",
        "proseYesterday": "Yesterday I closed",
        "proseYesterdayAlso": "I also closed",
        "proseToday": "Today I'm on",
        "proseTodayAlso": "I'm also on",
        "proseBlockers": "Blocked on",
        "proseBlockersAlso": "Also blocked on",
        "proseBlockersNone": "Nothing blocked.",
        "proseWalk": "Waiting on you to walk",
        "proseWalkAlso": "Also to walk",
        "proseDecide": "Waiting on you to decide",
        "proseDecideAlso": "Also to decide",
        "proseLook": "Waiting on you to look at",
        "proseLookAlso": "Also to look at",
        "proseOne": "{n} in {name}: {item}",
        "proseTodayOne": "{name}: {item}",
        "proseMany": "{n} in {name} ({refs})",
        "proseBare": "{item}",
        "proseItem": "{ref}, {clause}",
        "proseRefSeparator": ", ",
        "proseTodayFold": "{n} more: {names}",
        "proseTodayFoldCount": "{n} more designs",
        "proseNameSeparator": ", ",
        "proseNameLast": " and ",
        "itemMotion": "{ref} ({motion}) {title}",
        "motionStarted": "started",
        "commitOne": "{n} commit",
        "commitMany": "{n} commits",
        "countsTotal": "Since {date}: {counts}.",
        "countsNone": "nothing moved",
        "countsSeparator": ", ",
        "countsClosed": "{n} closed",
        "countsStarted": "{n} started",
        "countsInProgress": "{n} in progress",
    },
    # StartWork's hand-off block (D-AR5): the CLI types these four, the web's copy
    # box finds the block's title by the first; Tests/fixtures/start-work/ holds
    # the block they make, which Tests/test_bridge.py reads back through the bridge.
    ("startWork", "text"): {
        "head": "# Start work: {kind} {id} -- {title}",
        "howWeWork": "## How we work in {space} ({source})",
        "work": "## The work: {kind} {id} ({source})",
        "prompt": "## The prompt ({source})",
    },
}


class TheFileParses(unittest.TestCase):
    def test_it_is_json_and_has_every_group(self):
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        for group in (
            "repository",
            "stamps",
            "tokens",
            "regex",
            "status",
            "folders",
            "reviews",
            "features",
            "reminders",
            "env",
            "docs",
            "visibility",
            "spaces",
            "studio",
            "design",
            "rituals",
            "startWork",
            "assets",
            "tests",
            "agent",
        ):
            self.assertIn(group, raw)

    def test_every_expected_value_is_what_the_file_says(self):
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        for (group, key), value in EXPECTED.items():
            with self.subTest(key=f"{group}.{key}"):
                self.assertEqual(raw[group][key], value)

    def test_every_key_in_the_file_is_accounted_for(self):
        """A key added to consts.json without a line here is a key nobody agreed to."""
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        found = {(g, k) for g, body in raw.items() if isinstance(body, dict) for k in body if not k.startswith("_")}
        self.assertEqual(found, set(EXPECTED), "consts.json and this test disagree about its keys")


# The product's version, typed once in consts.json. The module manifest and the
# web package carry their own literal, so each is held to it here by name.
# MUST match Tests/Test-Consts.ps1's and web/src/shell/consts.test.ts's.
EXPECTED_VERSION = "1.1.0"


class OneVersion(unittest.TestCase):
    """A bump is one edit in three files, and a partial one fails naming the file left behind."""

    MANIFEST = PKG_ROOT / "Prompt20Toolkit" / "Prompt20Toolkit.psd1"
    PACKAGE = PKG_ROOT / "web" / "package.json"

    def test_the_contract_states_the_version(self):
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        self.assertEqual(raw["version"], EXPECTED_VERSION)
        self.assertRegex(raw["version"], r"^\d+\.\d+\.\d+$")
        self.assertEqual(C.version(), EXPECTED_VERSION)

    def test_the_one_top_level_value_is_the_version(self):
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        scalars = sorted(k for k, v in raw.items() if not k.startswith("_") and not isinstance(v, dict))
        self.assertEqual(scalars, ["version"])

    def test_the_module_manifest_carries_the_same_version(self):
        m = re.search(r"(?m)^\s*ModuleVersion\s*=\s*'([^']*)'", self.MANIFEST.read_text(encoding="utf-8-sig"))
        found = m.group(1) if m else None
        self.assertEqual(
            found,
            C.version(),
            f"Prompt20Toolkit/Prompt20Toolkit.psd1 says {found!r}, consts.json says {C.version()!r}",
        )

    def test_the_web_package_carries_the_same_version(self):
        found = json.loads(self.PACKAGE.read_text(encoding="utf-8-sig")).get("version")
        self.assertEqual(found, C.version(), f"web/package.json says {found!r}, consts.json says {C.version()!r}")


class ThisHalfReadsIt(unittest.TestCase):
    def test_the_accessors_return_the_contract_values(self):
        self.assertEqual(C.repository_url(), EXPECTED[("repository", "url")])
        self.assertEqual(C.stamp_closed(), EXPECTED[("stamps", "closed")])
        self.assertEqual(C.stamp_created(), EXPECTED[("stamps", "created")])
        self.assertEqual(C.token_pr_url(), EXPECTED[("tokens", "prUrl")])
        self.assertEqual(C.token_pr_review_heading(), EXPECTED[("tokens", "prReviewHeading")])
        self.assertEqual(C.token_previous_round(), EXPECTED[("tokens", "previousRound")])
        self.assertEqual(C.status_active(), EXPECTED[("status", "active")])
        self.assertEqual(C.status_in_progress(), EXPECTED[("status", "inProgress")])
        self.assertEqual(C.status_code_review(), EXPECTED[("status", "codeReview")])
        self.assertEqual(C.status_done(), EXPECTED[("status", "done")])
        self.assertEqual(C.folder_current(), EXPECTED[("folders", "current")])
        self.assertEqual(C.folder_archive(), EXPECTED[("folders", "archive")])
        self.assertEqual(C.folder_backlog(), EXPECTED[("folders", "backlog")])
        self.assertEqual(C.status_backlog(), EXPECTED[("status", "backlog")])
        self.assertEqual(C.folder_assets(), EXPECTED[("folders", "assets")])
        self.assertEqual(C.stamp_cover(), EXPECTED[("stamps", "cover")])
        self.assertEqual(C.stamp_before(), EXPECTED[("stamps", "before")])
        self.assertEqual(list(C.cover_extensions()), EXPECTED[("assets", "coverExtensions")])
        self.assertEqual(C.cover_max_bytes(), EXPECTED[("assets", "coverMaxBytes")])
        self.assertEqual(C.review_file_name(), EXPECTED[("reviews", "fileName")])
        self.assertEqual(C.review_slug_separator(), EXPECTED[("reviews", "slugSetSeparator")])
        self.assertEqual(list(C.space_scoped_features()), EXPECTED[("features", "spaceScoped")])
        self.assertEqual(C.docs_readme(), EXPECTED[("docs", "readme")])
        self.assertEqual(list(C.test_halves()), EXPECTED[("tests", "halves")])
        self.assertEqual(C.test_legacy_half(), EXPECTED[("tests", "legacyHalf")])
        self.assertEqual(C.docs_root(), EXPECTED[("docs", "root")])
        self.assertTrue(C.re_docs_segment().match("CLI.md"))
        self.assertFalse(C.re_docs_segment().match(".."))
        self.assertEqual(C.docs_landing_url(), EXPECTED[("docs", "landingUrl")])
        self.assertEqual(C.renamed_spaces(), EXPECTED[("spaces", "renamed")])
        self.assertEqual(C.visibility_public(), EXPECTED[("visibility", "public")])
        self.assertEqual(C.visibility_private(), EXPECTED[("visibility", "private")])
        self.assertEqual(C.visibility_unknown(), EXPECTED[("visibility", "unknown")])
        self.assertEqual(C.visibility_public_line(), EXPECTED[("visibility", "publicLine")])
        self.assertEqual(C.studio_thread_line(), EXPECTED[("studio", "threadLine")])
        self.assertTrue(C.re_studio_note_name().match("board-ideas.md"))
        self.assertEqual(C.studio_prompts_route(), EXPECTED[("studio", "promptsRoute")])
        self.assertFalse(C.re_studio_note_name().match("../hub.json"))
        self.assertEqual(C.re_studio_thread().search("x\n> GitHub: https://github.com/o/r/issues/7\n").group(4), "7")
        self.assertEqual(C.design_id_key(), EXPECTED[("design", "idKey")])
        self.assertEqual(list(C.design_states()), EXPECTED[("design", "states")])
        self.assertEqual(list(C.design_outcomes()), EXPECTED[("design", "outcomes")])
        self.assertEqual(C.stamp_outcome(), EXPECTED[("stamps", "outcome")])
        self.assertEqual(C.design_docs_line(), EXPECTED[("design", "docsLine")])
        self.assertEqual(C.token_design(), EXPECTED[("tokens", "design")])
        self.assertEqual(C.token_spec(), EXPECTED[("tokens", "spec")])
        m = C.re_card_design_line().search(
            "# T\r\n> Design: [Board ideas](../../design/board-ideas.md) ee925272-9564-4816-8944-e6b39c86339c\r\n"
        )
        self.assertEqual(
            m.groups(), ("Design", "Board ideas", "../../design/board-ideas.md", "ee925272-9564-4816-8944-e6b39c86339c")
        )
        self.assertTrue(C.re_card_design_line().pattern.startswith("(?m)^>"))
        self.assertTrue(C.token_design().startswith(">") and C.token_spec().startswith(">"))
        self.assertEqual(
            C.re_design_docs().search("# S\n\n> Docs: docs/hub/design.md\n").group(1), "docs/hub/design.md"
        )
        self.assertTrue(C.re_design_id().match("ee925272-9564-4816-8944-e6b39c86339c"))
        self.assertFalse(C.re_design_id().match("EE925272-9564-4816-8944-e6b39c86339c"))  # lowercase only
        self.assertFalse(C.re_design_id().match("ee925272-9564-1816-8944-e6b39c86339c"))  # v4 only
        self.assertFalse(C.re_design_id().match("ee925272956448168944e6b39c86339c"))  # hyphenated
        self.assertEqual(C.rituals_route(), EXPECTED[("rituals", "route")])
        self.assertEqual(C.rituals_triage_route(), EXPECTED[("rituals", "triageRoute")])
        self.assertEqual(C.rituals_ceremonies_file(), EXPECTED[("rituals", "ceremoniesFile")])
        self.assertEqual(C.rituals_vocabulary_file(), EXPECTED[("rituals", "vocabularyFile")])
        self.assertEqual(C.rituals_worker_label_prefix(), EXPECTED[("rituals", "workerLabelPrefix")])
        self.assertEqual(C.rituals_walk_label(), EXPECTED[("rituals", "walkLabel")])
        self.assertEqual(C.rituals_label_width(), EXPECTED[("rituals", "labelWidth")])
        self.assertEqual(C.rituals_text(), EXPECTED[("rituals", "text")])
        self.assertEqual(C.rituals_grains(), tuple(EXPECTED[("rituals", "grains")]))
        self.assertEqual(C.rituals_number_words(), tuple(EXPECTED[("rituals", "numberWords")]))
        self.assertEqual(C.rituals_work_head_regex(), EXPECTED[("rituals", "workHeadRegex")])
        self.assertEqual(C.rituals_work_thread_regex(), EXPECTED[("rituals", "workThreadRegex")])
        self.assertEqual(C.rituals_work_design_regex(), EXPECTED[("rituals", "workDesignRegex")])
        self.assertEqual(C.rituals_work_small_word_regex(), EXPECTED[("rituals", "workSmallWordRegex")])
        self.assertEqual(C.rituals_prose_fold_names(), EXPECTED[("rituals", "proseFoldNames")])
        self.assertEqual(C.rituals_dress_guards(), tuple(EXPECTED[("rituals", "dressGuards")]))
        self.assertEqual(C.rituals_dress_ref_regex(), EXPECTED[("rituals", "dressRefRegex")])
        self.assertEqual(C.rituals_dress_number_regex(), EXPECTED[("rituals", "dressNumberRegex")])
        self.assertEqual(C.rituals_dress_name_regex(), EXPECTED[("rituals", "dressNameRegex")])
        self.assertEqual(C.rituals_dress_pronoun_regex(), EXPECTED[("rituals", "dressPronounRegex")])
        self.assertEqual(C.rituals_motions(), tuple(EXPECTED[("rituals", "motions")]))
        self.assertEqual(C.rituals_suggest_shapes(), tuple(EXPECTED[("rituals", "suggestShapes")]))
        self.assertEqual(C.rituals_suggest_exclusions(), tuple(EXPECTED[("rituals", "suggestExclusions")]))
        self.assertEqual(C.rituals_suggest_owner_seat(), EXPECTED[("rituals", "suggestOwnerSeat")])

    def test_the_worker_rule_reads_the_contract(self):
        """The pane's worker chips and the standup read one prefix, not two."""
        from agent.ado import accounting

        self.assertEqual(accounting.WORKER_LABEL_PREFIX, C.rituals_worker_label_prefix())

    def test_the_flag_scope_rule_reads_the_contract(self):
        """config.SPACE_FEATURES is the file's list, not a tuple typed beside it."""
        from agent.core import config

        self.assertEqual(tuple(config.SPACE_FEATURES), C.space_scoped_features())
        source = (PKG_ROOT / "agent" / "core" / "config.py").read_text(encoding="utf-8")
        self.assertNotIn('SPACE_FEATURES = ("sprintAwareness",)', source)

    def test_the_patterns_compile_and_match_real_card_text(self):
        self.assertTrue(C.re_pr_url_line().search("# Card\nPR URL: https://dev.azure.com/x"))
        self.assertFalse(C.re_pr_url_line().search("# Card\nPR URL: not-a-url"))
        self.assertTrue(C.re_commit_bullet().search("Commits:\n- 80e2168 add grid"))
        self.assertFalse(C.re_commit_bullet().search("Commits:\n- (pending)"))
        # One group: findall returns the hashes, and their number is the lane rule's count.
        self.assertEqual(
            C.re_commit_bullet().findall("- 80e2168 a\n- `abcdef1234` b\n- (pending)"), ["80e2168", "abcdef1234"]
        )
        self.assertTrue(C.re_pr_review_heading().search("## PR Review Comments -- Round 2 (PR 35)"))
        m = C.re_closed_stamp_date().search("body\n**Closed:** 2026-09-17\n")
        self.assertEqual(m.group(1), "2026-09-17")

    def test_the_state_machine_agrees_with_the_contract(self):
        """parsers.py derives its vocabulary from the file, not from literals."""
        from agent.core import parsers

        self.assertEqual(
            set(parsers._STATUS_ORDER),
            {C.status_active(), C.status_in_progress(), C.status_code_review(), C.status_backlog()},
        )


class NoPythonSourceRetypesIt(unittest.TestCase):
    """The grep-based half of the guard, for the literals distinctive enough to grep.

    ``Active``, ``current`` and ``archive`` are ordinary English -- they appear
    as org statuses, week selectors and prose -- so a text search for them would
    report noise rather than drift. Those keys are held by the parity assertions
    above instead, which is the stronger check anyway: all three halves state the
    value they resolved.
    """

    GUARDED = [
        ("stamps.closed", "**Closed:**"),
        ("stamps.created", "**Created:**"),
        ("tokens.prUrl", "PR URL:"),
        ("tokens.prReviewHeading", "## PR Review Comments"),
        ("tokens.previousRound", "> Previous round:"),
        ("regex.commitBullet", r"[0-9a-f]{7,}"),
        ("reviews.fileName", "review.md"),
        ("env.agentPort", "P20_AGENT_PORT"),
        ("env.testRunMarker", "P20_TEST_RUN"),
        ("env.activeSpace", "P20_ACTIVE_SPACE"),
        ("env.features", "P20_FEATURES"),
        ("stamps.due", "**Due:**"),
        ("stamps.cover", "**Cover:**"),
        ("stamps.before", "**Before:**"),
        ("stamps.outcome", "**Outcome:**"),
        ("studio.threadLine", "GitHub:\\s*(https"),
        ("rituals.workerLabelPrefix", "Routed to"),
        ("rituals.text.queueHeading", "Waiting on you"),
        ("rituals.text.queueEmpty", "Nothing is waiting on you."),
        # Quoted: "has nothing in flight" is ordinary English in /env's tier note.
        ("rituals.text.todayEmpty", '"nothing in flight"'),
        ("rituals.text.yesterdayEmpty", '"nothing closed"'),
        ("rituals.text.noWorkers", "No worker labels in this Space."),
        ("rituals.route", "/api/ritual/standup"),
        ("studio.promptsRoute", "/api/studio/prompts"),
        ("rituals.text.workBlockers", "{n} to walk"),
        ("rituals.text.proseBlockersNone", "Nothing blocked."),
        ("rituals.text.proseYesterday", "Yesterday I closed"),
        ("visibility.publicLine", "This repository is public"),
    ]

    # The allowlist, and why each entry is on it:
    #   agent/core/consts.py -- the reader. It names keys, not values.
    #   Tests/                -- the tests, which must state the values to check them.
    # Comment and docstring lines are skipped everywhere rather than whole files
    # being excused: explaining a literal is fine, comparing against one is not.
    ALLOWED = {"agent/core/consts.py"}

    def test_no_runtime_python_carries_a_contract_literal(self):
        offenders = []
        for py in sorted((PKG_ROOT / "agent").rglob("*.py")):
            rel = py.relative_to(PKG_ROOT).as_posix()
            if rel in self.ALLOWED:
                continue
            for i, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
                code = line.strip()
                if code.startswith(("#", '"""', "*")):
                    continue
                # A docstring body is not code either; the cheap test is whether
                # the line assigns or compares rather than merely mentions.
                for key, value in self.GUARDED:
                    if value in line and re.search(r"[=(\[]|\bin\b|re\.", line):
                        offenders.append(f"{rel}:{i}  ({key})  {code[:80]}")
        self.assertEqual(offenders, [], "\n".join(offenders))


class TheAgentListensOnTheLoopbackOnly(unittest.TestCase):
    """The agent has no authentication of its own: its bind address is the boundary.

    docs/ARCHITECTURE.md, "Trust model". The host is a cross-half literal
    (``agent.bindHost``); the one place the agent is started reads it, and the
    one other place a port is published binds the same interface.
    """

    START_AGENT = PKG_ROOT / "Scripts" / "Start-Agent.ps1"
    COMPOSE = PKG_ROOT / "web" / "docker-compose.yml"

    VITE_CONFIG = PKG_ROOT / "web" / "vite.config.ts"
    DEFAULT_CONFIG = PKG_ROOT / "config.default.json"

    # A key that would name an interface. ``address`` is not here on purpose: a
    # Space's ``address`` is a tracker's, not a listener's.
    INTERFACE_KEY = re.compile(r"^(host|hostname|bind\w*|listen\w*|interface|iface)$", re.IGNORECASE)

    def test_the_contract_names_a_loopback_host(self):
        self.assertIn(C.agent_bind_host(), ("127.0.0.1", "localhost"))

    def test_the_contract_host_is_a_loopback_address_and_never_a_wildcard(self):
        host = C.agent_bind_host()
        self.assertNotIn(host, ("", "0.0.0.0", "::", "*"), "a wildcard publishes the agent on every interface")
        if host != "localhost":
            addr = ipaddress.ip_address(host)
            self.assertTrue(addr.is_loopback, f"{host} is not a loopback address")
            self.assertFalse(addr.is_unspecified)

    def test_the_default_comes_from_the_one_contract_file_and_not_a_copy(self):
        # Read the file the launcher reads, with no help from the loader under
        # test: the value the launcher passes is exactly this key's.
        raw = json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))
        self.assertEqual(raw["agent"]["bindHost"], C.agent_bind_host())
        self.assertIn(raw["agent"]["bindHost"], ("127.0.0.1", "localhost"))

    def test_no_setting_in_the_shipped_config_names_an_interface(self):
        # config.default.json is what every merge starts from and what the
        # settings schema is derived from, so a key that is not here is not one
        # a person can set. The only network keys are a port and CORS origins.
        found = []

        def walk(node, path):
            if isinstance(node, dict):
                for key, value in node.items():
                    if self.INTERFACE_KEY.match(key):
                        found.append(".".join(path + [key]))
                    walk(value, path + [key])
            elif isinstance(node, list):
                for i, value in enumerate(node):
                    walk(value, path + [str(i)])

        walk(json.loads(self.DEFAULT_CONFIG.read_text(encoding="utf-8-sig")), [])
        self.assertEqual(found, [], "a setting that names an interface could widen the agent's bind")

    def test_the_launcher_takes_no_host_parameter_and_the_verb_advertises_none(self):
        text = self.START_AGENT.read_text(encoding="utf-8-sig")
        param = re.search(r"^param\((.*?)^\)", text, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(param, "Start-Agent.ps1 has a param() block")
        self.assertNotRegex(param.group(1), r"(?i)\$\w*(host|bind|listen|interface)\w*\b")
        config = json.loads(self.DEFAULT_CONFIG.read_text(encoding="utf-8-sig"))
        agent = json.dumps(config["commands"]["Agent"]["switches"]) + config["commands"]["Agent"]["usage"]
        self.assertNotRegex(agent, r"(?i)-(host|bind\w*|listen|interface)\b")

    def test_the_dev_server_sets_no_host(self):
        # Vite listens on localhost when it is given none. A `host:` here would
        # be the one line that publishes the UI, so it is absent on purpose.
        text = self.VITE_CONFIG.read_text(encoding="utf-8")
        lines = [ln for ln in text.splitlines() if not ln.strip().startswith(("//", "*", "/*"))]
        code = "\n".join(lines)
        self.assertNotRegex(code, r"(?m)^\s*host\s*:")
        package = json.loads((PKG_ROOT / "web" / "package.json").read_text(encoding="utf-8-sig"))
        for name, command in package["scripts"].items():
            self.assertNotRegex(command, r"--host\b", f"npm script {name!r} widens the dev server")

    def test_the_launcher_hands_uvicorn_the_contract_host(self):
        text = self.START_AGENT.read_text(encoding="utf-8-sig")
        code = [ln for ln in text.splitlines() if not ln.strip().startswith("#")]
        self.assertTrue(
            any(re.match(r"\s*\$bindHost\s*=\s*\(Get-P20Consts\)\.agent\.bindHost\s*$", ln) for ln in code),
            "Start-Agent.ps1 must read the host from consts.json agent.bindHost",
        )
        starts = [ln for ln in code if "'uvicorn'" in ln]
        self.assertEqual(len(starts), 1, "the agent is started in exactly one place")
        m = re.search(r"'--host',\s*(\S+?),\s*'--port'", starts[0])
        self.assertIsNotNone(m, "the uvicorn argument list names --host")
        self.assertEqual(m.group(1), "$bindHost", "--host is the contract's host, never a literal")

    def test_the_docker_image_publishes_its_port_on_the_loopback_only(self):
        text = self.COMPOSE.read_text(encoding="utf-8-sig")
        ports = re.findall(r'^\s*-\s*"([^"]+:\d+:\d+)"\s*$|^\s*-\s*"(\d+:\d+)"\s*$', text, re.MULTILINE)
        published = [a or b for a, b in ports]
        self.assertTrue(published, "docker-compose.yml publishes a port")
        for spec in published:
            self.assertTrue(
                spec.startswith(C.agent_bind_host() + ":"),
                f"published port {spec!r} must name the loopback host, not every interface",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
