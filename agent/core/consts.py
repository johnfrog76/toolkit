"""The agent's reader for ``consts.json`` -- the package's contract file.

``consts.json`` at the package root holds the literals that cross a half
boundary: a string or pattern the CLI, the agent and the web UI must agree on to
the character. It is JSON because it is the one format all three read with no
new dependency -- ``ConvertFrom-Json`` on the PowerShell 5.1 floor,
``json.load`` here, a build-time ``import`` in Vite.

Read it through the accessors below rather than reaching into the dict, so a
misspelled key is an ``AttributeError`` at the call site instead of a silent
``None`` that compiles to a regex matching nothing.

A missing or malformed file raises. It is not configuration with a sensible
default -- it is the contract the three halves agree on, and guessing at it is
how two halves quietly stop agreeing. ``config.py`` keeps its own job: orgs,
commands and ``workItemTypes`` are CONFIGURATION, which a team may change; these
are the CONTRACT, which nobody may change alone.
"""

import functools
import json
import re
from pathlib import Path

# agent/core/consts.py -> agent/core -> agent -> package root
CONSTS_PATH = Path(__file__).resolve().parents[2] / "consts.json"


@functools.lru_cache(maxsize=1)
def consts() -> dict:
    """The parsed contract file. Cached for the process."""
    return json.loads(CONSTS_PATH.read_text(encoding="utf-8-sig"))


# -- The values, named ------------------------------------------------------
# One accessor per key the agent actually uses. A key nothing here reads is
# still in the file for the other halves; adding an accessor is how this half
# starts depending on it.


def version() -> str:
    """The product's version: the one string Env, /api/env and the System page say."""
    return consts()["version"]


def repository_url() -> str:
    """The package's own repository, as an address -- what a Space's repository is
    compared with when the package has no git origin to read."""
    return consts()["repository"]["url"]


def stamp_closed() -> str:
    return consts()["stamps"]["closed"]


def stamp_created() -> str:
    return consts()["stamps"]["created"]


def token_pr_url() -> str:
    return consts()["tokens"]["prUrl"]


def token_pr_review_heading() -> str:
    return consts()["tokens"]["prReviewHeading"]


def token_previous_round() -> str:
    return consts()["tokens"]["previousRound"]


def status_active() -> str:
    return consts()["status"]["active"]


def status_in_progress() -> str:
    return consts()["status"]["inProgress"]


def status_code_review() -> str:
    return consts()["status"]["codeReview"]


def status_done() -> str:
    return consts()["status"]["done"]


def folder_current() -> str:
    return consts()["folders"]["current"]


def folder_archive() -> str:
    return consts()["folders"]["archive"]


def folder_assets() -> str:
    """The Space's folder for what a card keeps that is not text -- its cover."""
    return consts()["folders"]["assets"]


def stamp_cover() -> str:
    """``**Cover:**`` -- a card's picture, ``../assets/<card key>/<file>``."""
    return consts()["stamps"]["cover"]


def stamp_before() -> str:
    """``**Before:**`` -- the other half of a before/after proof."""
    return consts()["stamps"]["before"]


def cover_extensions() -> tuple[str, ...]:
    """The image types a cover may be, lowercase, no dot."""
    return tuple(consts()["assets"]["coverExtensions"])


def cover_max_bytes() -> int:
    """The largest image ``Cover`` copies."""
    return int(consts()["assets"]["coverMaxBytes"])


def review_file_name() -> str:
    return consts()["reviews"]["fileName"]


def review_slug_separator() -> str:
    return consts()["reviews"]["slugSetSeparator"]


def space_scoped_features() -> tuple[str, ...]:
    """The feature flags an ORG may set (``spaces[].features``); every other flag
    is the engineer's. The CLI's ``SpaceScopedFeatures`` reads the same list."""
    return tuple(consts()["features"]["spaceScoped"])


# -- The patterns, compiled once --------------------------------------------
# They travel as strings so all three halves can hold the same one; each half
# compiles its own. ``(?m)`` is inside the pattern rather than passed as a flag
# for the same reason -- .NET and Python both read it, JS does not take a
# leading inline flag, so the web's consts.ts strips it where it needs to.


@functools.cache
def pattern(group: str, key: str) -> re.Pattern:
    return re.compile(consts()[group][key])


def re_pr_url_line() -> re.Pattern:
    return pattern("regex", "prUrlLine")


def re_pr_review_heading() -> re.Pattern:
    return pattern("regex", "prReviewHeading")


def re_commit_bullet() -> re.Pattern:
    return pattern("regex", "commitBullet")


def re_started_line() -> re.Pattern:
    """``**Started:**`` -- a person's In Progress, for a card with nothing checked in."""
    return pattern("regex", "startedLine")


def re_review_line() -> re.Pattern:
    """``**Review:**`` -- a person's Code Review, for a card with no pull request."""
    return pattern("regex", "reviewLine")


def re_session_name() -> re.Pattern:
    """A meeting record's filename: ``[<series>-]YYYY-MM-DD.md``. Group 1 is the
    series (None for the default, the 1:1), group 2 the date."""
    return pattern("regex", "sessionName")


def stamp_started() -> str:
    return consts()["stamps"]["started"]


def stamp_review() -> str:
    return consts()["stamps"]["review"]


def stamp_billable() -> str:
    """``**Billable:**`` -- the line that takes a card off a timesheet when it says no."""
    return consts()["stamps"]["billable"]


def card_id_shape() -> str:
    """The shape of a card's id, WITHOUT anchors: a work item number, or the
    four-character id of a card with no work item. A string, not a pattern --
    the caller composes ``^(prefix)?(<shape>)-`` around it, exactly as
    ``Scripts/Resolve-CardName.ps1`` does."""
    return consts()["regex"]["cardId"]


def re_closed_stamp_date() -> re.Pattern:
    """``**Closed:** yyyy-mm-dd`` -- the stamp plus the date the engagement summary reads.

    Built from the stamp rather than retyped: the date shape belongs to this
    half (nothing else parses it), the stamp does not.
    """
    return re.compile(r"(?m)^" + re.escape(stamp_closed()) + r"\s*(\d{4}-\d{2}-\d{2})")


def env_teams_webhook_prefix() -> str:
    """The front of every ``TEAMS_WEBHOOK_<RECIPIENT>`` variable."""
    return consts()["env"]["teamsWebhookPrefix"]


def env_test_run_marker() -> str:
    """Set by every test runner; while it is set, nothing posts to a real webhook."""
    return consts()["env"]["testRunMarker"]


def agent_bind_host() -> str:
    """The interface the agent listens on: the loopback, never a wildcard."""
    return consts()["agent"]["bindHost"]


def env_active_space() -> str:
    """Names a Space slug that stands in for config.local.json's ``activeSpace``."""
    return consts()["env"]["activeSpace"]


def env_features() -> str:
    """Holds a JSON object that stands in for config.local.json's top-level ``features``."""
    return consts()["env"]["features"]


def stamp_sent() -> str:
    """The line a send writes under ``## Sent``: "Sent to <recipient>: <date>"."""
    return consts()["stamps"]["sent"]


def stamp_due() -> str:
    """A reminder's ``**Due:**`` footer line (Organize)."""
    return consts()["stamps"]["due"]


def stamp_source() -> str:
    return consts()["stamps"]["source"]


def stamp_ref() -> str:
    return consts()["stamps"]["ref"]


def re_due_line() -> re.Pattern:
    """``**Due:** YYYY-MM-DD`` or ``YYYY-MM-DDTHH:MM``: group 1 the date, group 2 the time."""
    return pattern("regex", "dueLine")


def reminder_buckets() -> tuple[str, ...]:
    """overdue, today, upcoming -- derived at read time, never stored."""
    return tuple(consts()["reminders"]["buckets"])


def reminder_snooze_words() -> tuple[str, ...]:
    return tuple(consts()["reminders"]["snooze"])


def test_halves() -> tuple[str, ...]:
    """agent, cli, web -- the halves a test run covers, in the order ``Test`` runs them."""
    return tuple(consts()["tests"]["halves"])


def test_legacy_half() -> str:
    """What a ``test-summary`` suite entry with no ``half`` is read as."""
    return consts()["tests"]["legacyHalf"]


def docs_readme() -> str:
    """The Docs tab's landing page, at the repo root."""
    return consts()["docs"]["readme"]


def docs_root() -> str:
    """The folder whose markdown tree the Docs tab lists."""
    return consts()["docs"]["root"]


def re_docs_segment() -> re.Pattern:
    """One path segment the Docs routes accept: never '..', '.' or empty."""
    return re.compile(consts()["docs"]["segment"])


def docs_landing_url() -> str:
    """The public landing page's deployed address (GitHub Pages) -- not a Docs-tab
    file. The README's Documentation table links it as a literal; this is the
    same address the web app's Home foot reads."""
    return consts()["docs"]["landingUrl"]


def visibility_public() -> str:
    """A GitHub Space's repository is public: ``public``."""
    return consts()["visibility"]["public"]


def visibility_private() -> str:
    """...private, or INTERNAL as gh says it: ``private``."""
    return consts()["visibility"]["private"]


def visibility_unknown() -> str:
    """...not answered by the tracker -- never a guess: ``unknown``."""
    return consts()["visibility"]["unknown"]


def visibility_public_line() -> str:
    """The one line a write to a public repository carries."""
    return consts()["visibility"]["publicLine"]


def renamed_spaces() -> dict[str, str]:
    """A shipped Space's old slug -> its new one (``test`` -> ``azure-demo``)."""
    return dict(consts()["spaces"]["renamed"])


def re_studio_note_name() -> re.Pattern:
    """One design note's file name -- one markdown file, no path (Studio S2b)."""
    return pattern("studio", "noteName")


def studio_thread_line() -> str:
    """The line that names a document's thread: ``> GitHub:`` then the issue URL."""
    return consts()["studio"]["threadLine"]


def re_studio_thread() -> re.Pattern:
    """A ``> GitHub: <issue url>`` line: group 1 the URL, 2 owner, 3 repo, 4 number."""
    return pattern("studio", "threadRegex")


def studio_prompts_route() -> str:
    """The Studio's Prompts card's read: ``/api/studio/prompts``."""
    return consts()["studio"]["promptsRoute"]


# -- The design lifecycle's identity (L1; docs/hub/design.md) --


def design_id_key() -> str:
    """The frontmatter key a design's id is written under: ``id``."""
    return consts()["design"]["idKey"]


def re_design_id() -> re.Pattern:
    """The shape of a design's id: a UUID v4, lowercase, hyphenated (anchored)."""
    return pattern("design", "idRegex")


def design_states() -> list[str]:
    """The four states a design can be in, in road order."""
    return list(consts()["design"]["states"])


def design_outcomes() -> list[str]:
    """What an archived note without a spec may say became of it."""
    return list(consts()["design"]["outcomes"])


def stamp_outcome() -> str:
    """``**Outcome:**`` -- shipped or dropped, on a note archived without a spec (L2 reads, L3 writes)."""
    return consts()["stamps"]["outcome"]


def design_docs_line() -> str:
    """``> Docs:`` -- where a Complete spec's durable part landed."""
    return consts()["design"]["docsLine"]


def re_design_docs() -> re.Pattern:
    """A ``> Docs: <path>`` line: group 1 the path."""
    return pattern("design", "docsRegex")


def token_design() -> str:
    """``> Design:`` -- the line a card carries naming the design it was worked against (toolkit card 4.6)."""
    return consts()["tokens"]["design"]


def token_spec() -> str:
    """``> Spec:`` -- the corpus's hand-written form of the same line, read as written."""
    return consts()["tokens"]["spec"]


def re_card_design_line() -> re.Pattern:
    """A card's ``> Design:`` / ``> Spec:`` line: group 1 the word, 2 the link's
    text, 3 its target, 4 what follows (the id, or a person's words)."""
    return pattern("design", "cardLineRegex")


# -- Solitaire Agile's Ritual Engine (docs/modules/solitaire-agile.md) --
# The CLI's Standup and GET /api/ritual/standup render the SAME text, so every
# fixed word of it is read from here, never typed in agent/solitaire/.


def rituals_route() -> str:
    """The standup's route, with the /api prefix: ``/api/ritual/standup``."""
    return consts()["rituals"]["route"]


def rituals_triage_route() -> str:
    """Triage's route, with the /api prefix: ``/api/ritual/triage``."""
    return consts()["rituals"]["triageRoute"]


def rituals_ceremonies_file() -> str:
    """The ceremonies' slot lists, relative to the package root."""
    return consts()["rituals"]["ceremoniesFile"]


def rituals_vocabulary_file() -> str:
    """phrasebook, nothing, excuses, fakeWork -- relative to the package root."""
    return consts()["rituals"]["vocabularyFile"]


def rituals_worker_label_prefix() -> str:
    """A label routes to a worker when its description starts with this."""
    return consts()["rituals"]["workerLabelPrefix"]


def rituals_walk_label() -> str:
    """The label that puts an open issue in the human's walk queue."""
    return consts()["rituals"]["walkLabel"]


def rituals_label_width() -> int:
    """The column a slot label is padded to, before two spaces."""
    return int(consts()["rituals"]["labelWidth"])


def rituals_text() -> dict[str, str]:
    """Every fixed string of the standup's rendering, by its key."""
    return dict(consts()["rituals"]["text"])


# -- The reminder to attend (D-TA15) --------------------------------------
# An Organize reminder the CLI writes and the attend route re-arms; the cadence
# is its own Ref line, ``HH:mm <days>`` in these day names.


def rituals_attend_route() -> str:
    """POST: attending re-arms the standup reminder. ``/api/ritual/standup/attend``."""
    return consts()["rituals"]["attendRoute"]


def rituals_remind_route() -> str:
    """GET: the standup reminder as it stands. ``/api/ritual/standup/remind``."""
    return consts()["rituals"]["remindRoute"]


def rituals_remind_source() -> str:
    """The **Source:** tag a standup reminder carries: ``standup``."""
    return consts()["rituals"]["remindSource"]


def rituals_remind_title() -> str:
    """The title a standup reminder is written with."""
    return consts()["rituals"]["remindTitle"]


def rituals_remind_days() -> str:
    """The cadence ``-Days`` defaults to."""
    return consts()["rituals"]["remindDays"]


def rituals_weekdays() -> tuple[str, ...]:
    """The day names a cadence is written in, Monday first."""
    return tuple(consts()["rituals"]["weekdays"])


# -- The work grain (D-TA20) ---------------------------------------------


def rituals_grains() -> tuple[str, ...]:
    """The three registers of detail -- detail, work, brief -- the CLI's -Grain and the page choose from."""
    return tuple(consts()["rituals"]["grains"])


def rituals_number_words() -> tuple[str, ...]:
    """A count as the voice says it, by index; digits past the list's end."""
    return tuple(consts()["rituals"]["numberWords"])


def rituals_work_head_regex() -> str:
    """A title's head: a one-word type tag dropped, cut at ' -- ' or ': ' (group 1)."""
    return consts()["rituals"]["workHeadRegex"]


def rituals_work_thread_regex() -> str:
    """The ``> GitHub:`` thread an issue's body names; group 1 is its number."""
    return consts()["rituals"]["workThreadRegex"]


def rituals_work_design_regex() -> str:
    """The ``design/<note>.md`` an issue's body names; group 1 is the note's stem."""
    return consts()["rituals"]["workDesignRegex"]


def rituals_work_small_word_regex() -> str:
    """A trailing word the common stem does not count ('the', 'of')."""
    return consts()["rituals"]["workSmallWordRegex"]


def rituals_prose_fold_names() -> int:
    """The most groups a folded sentence names; past it, the sentence says the count alone."""
    return int(consts()["rituals"]["proseFoldNames"])


# -- What moved ---------------------------------------------


def rituals_motions() -> tuple[str, ...]:
    """A slot item's motion, by index: closed, started, inProgress -- also the counts' field names."""
    return tuple(consts()["rituals"]["motions"])


# -- The dress (D-SA11) ---------------------------------------------------


def rituals_dress_guards() -> tuple[str, ...]:
    """The dress guard's checks, in the order they run; the first that fails is the reason."""
    return tuple(consts()["rituals"]["dressGuards"])


def rituals_dress_ref_regex() -> str:
    """A ref in a dressed sentence: an issue's ``#n``, or a card-id-shaped word."""
    return consts()["rituals"]["dressRefRegex"]


def rituals_dress_number_regex() -> str:
    """A number in a dressed sentence: digits standing alone (not ``#<n>``, not ``20g``)."""
    return consts()["rituals"]["dressNumberRegex"]


def rituals_dress_name_regex() -> str:
    """A capitalised word in a dressed sentence -- read as a name unless the facts have it."""
    return consts()["rituals"]["dressNameRegex"]


def rituals_dress_pronoun_regex() -> str:
    """The first person's capital I (``I``, ``I'm``, ``I've``), which is no name."""
    return consts()["rituals"]["dressPronounRegex"]
