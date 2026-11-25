"""GET /api/ritual/standup -- the standup, filled from the tracker (Solitaire Agile M0).

The contract is docs/modules/solitaire-agile.md, "The file shape, and how a standup is read". Two halves
implement it -- this file and the CLI's ``Scripts/Get-Standup.ps1`` -- and one
table holds them to each other: ``Tests/fixtures/rituals/standup.json`` and the
golden texts beside it, asserted from ``Tests/test_rituals.py`` and
``tkTestToolkit -Rituals``. The web shows ``text`` verbatim, so parity is one
string comparison.

Three layers, so the rule is testable without a network:

- ``fill_standup`` -- PURE. Labels and issues in (the shapes ``gh label list``
  and ``gh issue list`` return), the slots, the queue and the vocabulary pick out.
- ``render_standup`` -- PURE. The filled standup in, the text out, every fixed
  word read from ``consts.json`` ``rituals.text``.
- ``build_work`` and ``render_work`` -- PURE. The work grain (D-TA20): each
  slot's items grouped by milestone, design card, card type or the titles'
  common stem, one phrase a group; held by
  ``Tests/fixtures/rituals/standup-work.json``. Its text is the PROSE:
  ``prose_sentence`` speaks each group as one standup sentence, a grammar over
  the groups and no model; held by ``Tests/fixtures/rituals/standup-prose.json``.
- ``dress_standup`` -- the one step that may call a model: each worker
  sentence re-said in the standup register through ``core/model.py``, every one
  held by ``dress_guard`` (pure, ``Tests/fixtures/rituals/standup-dress.json``)
  and the prose kept wherever it adds, drops or changes a fact. ``spoken`` in the
  response; null with no key, and the prose stands.
- the route -- the thin gh layer: which Space, whether it is GitHub and
  reachable, ``_gh_labels`` and ``_gh_issues`` from ``agent/ado/accounting.py``.

A second source: a Space with no tracker address, or a local or archive
one, fills from its CARDS -- ``standup_source`` chooses, ``read_cards`` is the
thin folder layer, ``fill_cards_standup`` the pure fill, and the SAME
``render_standup`` draws it. ``Tests/fixtures/rituals/standup-cards.json`` is
that table, asserted from both suites. An active GitHub Space reads BOTH,
joined on the id (``fill_joined_standup``, held by
``Tests/fixtures/rituals/standup-joined.json``). An Azure DevOps Space keeps its
``Tracker`` line (D-TA19).

What moved: every slot item carries its ``motion`` (closed,
started or inProgress) and its card's ``commits`` -- a detail line says only what
adds to its slot, ``started`` and the commits; ``standup_counts`` sums them
per worker and in total -- a hash once however many cards thread it -- and the
brief opens on that counts line. On a GitHub Space one batched dates read
(``tracker.dates``, ``date_asks``) keeps a card's commits to those authored in
the window -- a hash it cannot date is counted ``undated`` and said, not
counted -- and lets an open issue with no card say ``started`` from its
timeline. ``window_start`` widens yesterday's lower bound
(``?since=<yyyy-MM-dd>``); today and the blockers are what is open now.

The ritual happens anyway (principle 3): an Azure DevOps Space, a tier below 1,
or a gh that does not answer is still a 200 -- the chair's two lines, an empty
queue and no workers, and the reason in ``tracker.reason`` and in the text.

The real register never reads the vocabulary's fake-work family (D-SA5):
nothing in this file names it, and the suite greps every rendered case
against it.
"""

from __future__ import annotations

import asyncio
import functools
import hashlib
import json
import re
from collections import OrderedDict
from datetime import date, datetime, time, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, PrivateAttr

from ..ado import accounting
from ..core import disk_cache, log_writer, model
from ..core.config import API_PREFIX, REPO_ROOT, load_config, org_folder, tracker
from ..core.consts import (
    folder_archive,
    folder_current,
    re_closed_stamp_date,
    re_commit_bullet,
    rituals_ceremonies_file,
    rituals_dress_name_regex,
    rituals_dress_number_regex,
    rituals_dress_pronoun_regex,
    rituals_dress_ref_regex,
    rituals_label_width,
    rituals_motions,
    rituals_number_words,
    rituals_prose_fold_names,
    rituals_room,
    rituals_route,
    rituals_team_size_default,
    rituals_team_sizes,
    rituals_text,
    rituals_vocabulary_file,
    rituals_walk_label,
    rituals_work_design_regex,
    rituals_work_head_regex,
    rituals_work_small_word_regex,
    rituals_work_thread_regex,
    rituals_worker_label_prefix,
    stamp_created,
    stamp_started,
    status_code_review,
    status_done,
    status_in_progress,
)
from ..core.models import read_model_current, read_model_map
from ..core.parsers import (
    _parse_status_metadata,
    card_agent,
    card_assigned,
    card_billable,
    card_id,
    card_milestone,
    card_milestone_from_github,
    card_tags,
    resolve_card_agent,
)
from .tracker import read_tracker

FEATURE = "solitaireAgile"
CEREMONY = "standup"

# The worker's name ends at this separator: "Routed to <worker> -- the volume" names <worker>.
_NAME_SEPARATOR = " -- "


def solitaire_enabled() -> bool:
    # The resolved map already carries the active Space's answer: the
    # switch is on AND the Space works with agents.
    return bool((load_config().get("features") or {}).get(FEATURE, False))


def _require_solitaire() -> None:
    # A dependency, not a conditional mount: re-read per request, so a flag
    # flipped -- or a Space switched, or answered -- in another terminal needs no
    # restart. Off is 404, not 403, and the detail says which of the two is off.
    cfg = load_config()
    if (cfg.get("features") or {}).get(FEATURE, False):
        return
    how = cfg.get("howIWork") or {}
    if how.get("switch"):
        raise HTTPException(
            status_code=404,
            detail=(
                f"the solitaire agile module is off in this Space: {cfg.get('activeSpace', '')} works "
                f"{how.get('answer', 'alone')} (spaces.<slug>.howIWork)"
            ),
        )
    raise HTTPException(status_code=404, detail=f"the solitaire agile module is off (features.{FEATURE})")


api = APIRouter(dependencies=[Depends(_require_solitaire)])


# -- The two data files, read once per process --------------------------------


@functools.lru_cache(maxsize=1)
def ceremonies() -> dict:
    return json.loads((REPO_ROOT / rituals_ceremonies_file()).read_text(encoding="utf-8-sig"))


@functools.lru_cache(maxsize=1)
def vocabulary() -> dict:
    return json.loads((REPO_ROOT / rituals_vocabulary_file()).read_text(encoding="utf-8-sig"))


# -- The response, field names exactly as the contract's JSON ------------------


class TrackerState(BaseModel):
    ok: bool = True
    reason: str = ""
    # How many worker labels the tracker answered; 0 where no tracker was read.
    workerLabels: int = 0


class Team(BaseModel):
    # The room: how many windows the standup has, the chair included
    # (spaces[].features.teamSize, ``team_size``) -- so ``size - 1`` workers sit.
    size: int = Field(default_factory=rituals_team_size_default)


class SlotItem(BaseModel):
    # The same five keys whichever source filled the item: an issue has a
    # number and a url, and its id is null and its path ""; a card has an id
    # (the filename's, by the one id rule) and a path, and its number is null
    # and its url "".
    number: int | None = None
    id: str | None = None
    title: str = ""
    url: str = ""
    path: str = ""
    # What moved: ``rituals.motions`` -- closed (yesterday's), started or
    # inProgress (open). A card, or the card an issue's number names, is started
    # when its **Started:** day, else its **Created:** day, falls in the window;
    # an open issue with no card is started when its timeline's first worker
    # label or assignment does (``issue_starts``). ``commits`` is the distinct
    # hashes of that card's ``- <hash>`` bullets -- only those authored inside
    # the window when the commit dates were read; 0 with no card.
    motion: str = ""
    commits: int = 0


class WalkItem(SlotItem):
    worker: str = ""  # the worker's NAME ("<worker>"), "" when no label routes it


class Chair(BaseModel):
    open: str = ""
    close: str = ""
    # What you walked: the issues carrying the walk label (rituals.walkLabel)
    # CLOSED inside the window, by number -- the chair's real yesterday
    # (``chair_yesterday``). [] for a fill that reads no issues.
    walked: list[SlotItem] = []


class Queue(BaseModel):
    walk: list[WalkItem] = []
    decide: list[SlotItem] = []
    look: list[SlotItem] = []


class Worker(BaseModel):
    label: str
    name: str
    yesterday: list[SlotItem] = []
    today: list[SlotItem] = []
    blockers: list[SlotItem] = []
    empty: bool = False
    # The first of ``status``, kept for a reader that knows only this field. The
    # wire name is historical: it is a status sentence, not an excuse. Both
    # renderers and every golden read it.
    excuse: str = ""
    # The empty worker's two made-up items, [yesterday, today]: the `nothing` and
    # `nothingToday` families (``set_idle``); [] for a worker with something to say.
    status: list[str] = []
    # In the room today (``seat_room``): the round -- the work grain, the stage --
    # speaks the present only; the ledger -- the detail, the counts, the brief --
    # keeps every worker. True for a reader that knows nothing of the room.
    present: bool = True
    # The plate a member a card names wears when its family keeps no window
    # (``card_member``): the family in capitals, ``GROK``. "" for a labelled
    # worker, the engineer and a kept family, whose window's plate stands.
    plate: str = ""


class WorkGroup(BaseModel):
    # One group of a slot at the work grain: what the items belong to,
    # how that was found (milestone|design|type|stem), how many, which, and the
    # phrase the ritual says for it.
    name: str = ""
    by: str = ""
    count: int = 0
    refs: list[str] = []
    phrase: str = ""


class WorkQueue(BaseModel):
    walk: list[WorkGroup] = []
    decide: list[WorkGroup] = []
    look: list[WorkGroup] = []


class WorkWorker(BaseModel):
    label: str
    name: str
    yesterday: list[WorkGroup] = []
    today: list[WorkGroup] = []
    blockers: list[WorkGroup] = []
    # The prose: the worker's turn, in order -- turnOpen, one sentence a group,
    # a slot with nothing its fixed line (``prose_unsaid``; an idle worker's two
    # made-up items instead), proseBlockersNone when nothing blocks it, then
    # turnClose. Empty only when there is nothing to say.
    prose: list[str] = []
    # An invented cast member (``seat_room``): it fills a seat the team size counts
    # and no member takes. Its label is its cast id, its name the plate; it is in
    # the round only -- never in ``workers``, the counts or the brief.
    cast: bool = False


class Work(BaseModel):
    # The work grain (D-TA20): the same standup, grouped -- the queue's
    # kinds and each worker's slots -- and its text, one line a worker.
    queue: WorkQueue = WorkQueue()
    workers: list[WorkWorker] = []
    # The prose: the queue's sentences, one a group, kind by kind.
    queueProse: list[str] = []
    # The chair's own turn, last, in the workers' frame and in its own first
    # person: its yesterday, its today, its blockers line -- never the queue's
    # sentences again (``chair_turn``). Empty when no tracker answered.
    chairProse: list[str] = []
    text: str = ""


class SpokenWorker(BaseModel):
    # A worker's sentences as the stage says them: the work row's prose,
    # with each sentence the model dressed and the guard let through in its place.
    label: str
    prose: list[str] = []


class CardLink(BaseModel):
    # A card joined to the issue its id names (the "both" source): the issue
    # keeps its row; the card adds what only it knows -- its lane, read the way
    # Status reads it (Done in archive/) -- and where it is.
    number: int
    id: str = ""
    lane: str = ""
    path: str = ""


class MotionCount(BaseModel):
    # One worker's motion in the window (``label`` and ``name`` "" for the
    # total): its items by motion, and the distinct commits their cards thread.
    # ``undated`` is the distinct hashes whose commit date the read could not
    # give: not counted in ``commits``, and said beside them. 0 when no dates
    # were read.
    label: str = ""
    name: str = ""
    closed: int = 0
    started: int = 0
    inProgress: int = 0
    commits: int = 0
    undated: int = 0


class Counts(BaseModel):
    # The velocity at a glance: per worker, in the workers' order, and in
    # total -- a hash counted once however many cards thread it.
    workers: list[MotionCount] = []
    total: MotionCount = MotionCount()


class Spoken(BaseModel):
    # The dress (D-SA11): present only when a model answered. ``dressed``
    # counts the sentences in the model's words, ``refused`` the ones where the
    # guard kept the prose sentence (a fact added, dropped or changed, or no line).
    model: str = ""
    workers: list[SpokenWorker] = []
    dressed: int = 0
    refused: int = 0


class Suggestion(BaseModel):
    # One derived next move (suggest.py; docs/modules/solitaire-agile.md, "The
    # suggestion: one next move, derived"). ``ref`` is how the standup names it
    # (#<n>, or the card's id); ``shape`` one of rituals.suggestShapes; ``command``
    # the verb and its argument, unprefixed; ``line`` the chair's Next line as the
    # brief prints it -- the web shows it verbatim.
    ref: str = ""
    number: int | None = None
    id: str | None = None
    kind: str = ""
    shape: str = ""
    sentence: str = ""
    command: str = ""
    line: str = ""


class Corner(BaseModel):
    # The PM Corner's line (corner.py; docs/modules/solitaire-agile.md, "The PM
    # Corner: the line, the chevron, the confetti"). ``shape`` one of
    # rituals.cornerShapes; ``milestone`` its title, whole ("" with nothing in
    # reach); ``remaining`` the open items that name it, once per id;
    # ``ref``/``number``/``id``/``kind`` the pick the chevron starts ("" and null
    # for reached and nothing in reach); ``noun`` the word the line counts in;
    # ``line`` the sentence the page shows; ``command`` the verb and its argument,
    # unprefixed ("" with no pick); ``brief`` the brief's last line, prefixed.
    shape: str = ""
    milestone: str = ""
    remaining: int = 0
    ref: str = ""
    number: int | None = None
    id: str | None = None
    kind: str = ""
    noun: str = ""
    line: str = ""
    command: str = ""
    brief: str = ""


class AgendaItem(BaseModel):
    # One tile of the Agenda (agenda.py; docs/modules/solitaire-agile.md, "The page").
    # How the standup names it: `#<n>` for an issue, the card's id.
    ref: str = ""
    number: int | None = None
    id: str | None = None
    kind: str = ""  # issue | card
    title: str = ""
    url: str = ""  # the issue's; "" for a card of its own
    path: str = ""  # the card's; "" for an issue with no card
    # The card's filename while it is in current/ -- what the card page opens; "" otherwise.
    file: str = ""
    # The card's lane (consts.json status), "" for an issue with no card.
    lane: str = ""
    # The day the tile's fact line names: an issue's closedAt or createdAt (in the
    # standup's own offset), a card's **Closed:**, **Review:** or **Created:** day.
    day: str = ""
    # Waiting on a review or a merge -- in Code Review, or on the queue: its one
    # action is Review it, not Work it now. Always false in ``moved``.
    review: bool = False
    # The card's cover (GET /api/assets/...) and progress, as the board's face reads them.
    cover: str | None = None
    checked: int = 0
    total: int = 0
    progress: str = ""


class Agenda(BaseModel):
    moved: list[AgendaItem] = []
    waiting: list[AgendaItem] = []


class Standup(BaseModel):
    # ``register`` is a BaseModel attribute, so the field is held under another
    # name and SERVED as "register" -- FastAPI serialises by alias. A caller
    # dumping it by hand passes by_alias=True.
    model_config = ConfigDict(populate_by_name=True)

    ceremony: str = CEREMONY
    register_: str = Field("", alias="register")
    asOf: str = ""
    since: str = ""
    space: str = ""
    # Which source filled it: "issues", "cards", "both" (an active GitHub
    # Space: its issues and its cards, joined on the id), or "none" when
    # nothing answered.
    source: str = "none"
    tracker: TrackerState = TrackerState()
    chair: Chair = Chair()
    # The room's size (spaces[].features.teamSize), the chair included.
    team: Team = Field(default_factory=Team)
    queue: Queue = Queue()
    workers: list[Worker] = []
    # The work grain: the items grouped, one phrase a group.
    work: Work = Work()
    # The dress: the work grain's worker sentences in standup language,
    # when a model key is set and the model answered; null otherwise, and the
    # stage speaks ``work`` -- the prose is the floor and the fallback.
    spoken: Spoken | None = None
    text: str = ""
    # The chair's reading: a few lines, every one a count or a derived fact.
    brief: str = ""
    # The "both" source: where a card and its issue disagree, one sentence
    # each (rituals.text.checkCardArchived / checkIssueClosed), by issue number.
    # Said, never fixed: Route stays the only write.
    checks: list[str] = []
    # The "both" source: each in-play card joined to its issue, by number.
    links: list[CardLink] = []
    # What moved in the window, per worker and in total; the brief's first line.
    counts: Counts = Counts()
    # The suggestion: every candidate in the rule's order (the web dismisses one
    # and shows the next), and the first -- the chair's Next line when nothing
    # waits. Empty and null with the Space's switch off (features.suggestions).
    suggestions: list[Suggestion] = []
    suggestion: Suggestion | None = None
    # The PM Corner (corner.py): one derived line -- the nearest milestone, what is
    # left in it and the suggestion's pick inside it, or a milestone reached in the
    # window. Null wherever the suggestion is off, or the tracker did not answer.
    corner: Corner | None = None
    # The Agenda (agenda.py): what moved in the window and what is waiting on you,
    # as the page's tiles draw them. The agent's alone: Standup -AsJson has no such key.
    agenda: Agenda = Agenda()
    # What kind each item is: ref -> its label names (an issue) or its
    # type (a card), read against the ceremony's kinds. Not served.
    _marks: dict[str, list[str]] = PrivateAttr(default_factory=dict)
    # The round (``seat_room``): who speaks, in seat order -- the seated members,
    # then the invented cast members, the last ``_invented`` of it. None for a
    # standup nobody seated: the round is then the present workers, in their order.
    # Not served: ``work.workers`` is the round as the response carries it.
    _round: list[Worker] | None = PrivateAttr(default=None)
    _invented: int = PrivateAttr(default=0)


# -- The rule -----------------------------------------------------------------


def previous_working_day_start(as_of: datetime) -> datetime:
    """Local midnight at the start of the previous working day, Monday to Friday,
    in ``as_of``'s own offset: Friday's is Thursday; Saturday's, Sunday's and
    Monday's are Friday. A rule with a fixture row, not a ``-1 day`` (trap 6)."""
    back = {0: 3, 6: 2, 5: 1}.get(as_of.weekday(), 1)
    day = (as_of - timedelta(days=back)).date()
    return datetime.combine(day, time(0, 0), tzinfo=as_of.tzinfo)


_DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def since_refusal(as_of: datetime, since: str) -> str:
    """'' when ``since`` is a window the standup can read: empty (the default,
    the previous working day) or a ``yyyy-MM-dd`` day no later than ``as_of``'s.
    Else the reason, which the route answers with a 422. The mirror of
    ``Test-P20StandupSince``."""
    text = (since or "").strip()
    if not text:
        return ""
    try:
        day = date.fromisoformat(text) if _DAY.match(text) else None
    except ValueError:
        day = None
    if day is None:
        return f"since '{since}' is not a day: yyyy-MM-dd."
    if day > as_of.date():
        return f"since '{since}' is after {as_of.date().isoformat()}: a window looks back."
    return ""


def window_start(as_of: datetime, since: str = "") -> datetime:
    """Yesterday's lower bound: the previous working day's start, or -- given a
    window's first day (``Standup -Since``, ``?since=``) -- local midnight of that
    day in ``as_of``'s offset. Today and the blockers do not move with it: they are
    what is open now. Raises ValueError with ``since_refusal``'s reason."""
    text = (since or "").strip()
    if not text:
        return previous_working_day_start(as_of)
    why = since_refusal(as_of, text)
    if why:
        raise ValueError(why)
    return datetime.combine(date.fromisoformat(text), time(0, 0), tzinfo=as_of.tzinfo)


def card_hashes(card: dict) -> list[str]:
    """A card row's commits: its ``commits`` hashes, distinct by their first seven
    characters (lowercase, so a short and a full hash of one commit are one), in
    first-seen order. A card with no bullets has none."""
    seen: list[str] = []
    for h in card.get("commits") or []:
        key = str(h).strip().lower()[:7]
        if key and key not in seen:
            seen.append(key)
    return seen


def card_begun_in(card: dict, first: str, last: str) -> bool:
    """Whether a card row's ``begun`` day (its **Started:** day, else its
    **Created:** day) is in [first, last], as yyyy-MM-dd days."""
    day = str(card.get("begun") or "")[:10]
    return bool(day) and first <= day <= last


# A hash as a dates read asks for it: what ``card_hashes`` keeps, and nothing
# else is written into a query.
_HASH = re.compile(r"^[0-9a-f]{7,40}$")
# Aliased lookups per dates call; a timeline is at most this many events.
DATES_CHUNK = 50
TIMELINE_FIRST = 50


def commit_in_window(when, since: datetime, as_of: datetime) -> bool:
    """Whether a commit's authored instant falls in [since, as_of]. A date
    that does not read is not in it."""
    at = _when(when)
    return at is not None and since <= at <= as_of


def window_hashes(
    hashes: list[str], commit_dates: dict | None, since: datetime, as_of: datetime
) -> tuple[list[str], list[str]]:
    """(the hashes to count, the hashes with no date) for one card. With
    ``commit_dates`` None -- the dates were not read: a cards Space, or a read
    that failed -- every hash counts, as it always has. Otherwise a hash counts
    when its authored date is in the window, is dropped when it is outside it,
    and is undated when the read gave it no date. The mirror of
    ``Select-P20StandupWindowHashes``."""
    if commit_dates is None:
        return list(hashes), []
    dates = {str(k).strip().lower()[:7]: v for k, v in commit_dates.items()}
    inside: list[str] = []
    undated: list[str] = []
    for h in hashes:
        when = dates.get(h)
        if _when(when) is None:
            undated.append(h)
        elif commit_in_window(when, since, as_of):
            inside.append(h)
    return inside, undated


def issue_started(nodes: list, worker_labels: list[str]) -> str | None:
    """An issue's start from its timeline: the earliest of a worker label
    being added and the issue being assigned, as the timeline states it; None
    when neither happened. A label that routes to no worker is not a start. The
    mirror of ``Get-P20StandupIssueStart``."""
    best: tuple[datetime, str] | None = None
    names = set(worker_labels or [])
    for node in nodes or []:
        if not isinstance(node, dict):
            continue
        kind = node.get("__typename")
        if kind == "LabeledEvent":
            if str((node.get("label") or {}).get("name") or "") not in names:
                continue
        elif kind != "AssignedEvent":
            continue
        at = _when(node.get("createdAt"))
        if at is not None and (best is None or at < best[0]):
            best = (at, str(node.get("createdAt")))
    return best[1] if best else None


def dates_query(hashes: list[str], numbers: list[int], trailers: list[str] | None = None) -> str:
    """The one GraphQL query a dates read sends for a repo: ``c<i>`` the
    i-th hash's commit, ``i<n>`` issue n's labelled and assigned events, then
    ``t<i>`` the i-th trailer hash's commit with its message -- the hashes whose
    co-author trailers the standup reads (``trailer_asks``), riding the same
    call. With no trailer hashes the text is what it was before they existed.
    The owner and name travel as variables. The mirror of
    ``Get-P20StandupDatesQuery``; standup-dates.json holds the text."""
    lines = ["query($owner: String!, $name: String!) {", "  repository(owner: $owner, name: $name) {"]
    for i, h in enumerate(hashes):
        if _HASH.match(h):
            lines.append(f'    c{i}: object(expression: "{h}") {{ ... on Commit {{ oid authoredDate }} }}')
    for n in numbers:
        lines.append(
            f"    i{int(n)}: issue(number: {int(n)}) {{ timelineItems(itemTypes: [LABELED_EVENT, ASSIGNED_EVENT], "
            f"first: {TIMELINE_FIRST}) {{ nodes {{ __typename ... on LabeledEvent {{ createdAt label {{ name }} }} "
            "... on AssignedEvent { createdAt } } } }"
        )
    for i, h in enumerate(trailers or []):
        if _HASH.match(h):
            lines.append(f'    t{i}: object(expression: "{h}") {{ ... on Commit {{ oid authoredDate message }} }}')
    lines += ["  }", "}"]
    return "\n".join(lines) + "\n"


def dates_from_answer(
    repository: dict | None,
    hashes: list[str],
    numbers: list[int],
    worker_labels: list[str],
    trailers: list[str] | None = None,
) -> tuple[dict[str, str | None], dict[int, str], dict[str, str]]:
    """A dates answer's ``repository`` object -> (hash -> its authored instant,
    or None; issue number -> its start; a trailer hash's first seven
    characters, lower case -> its commit message, the shape
    ``parsers.resolve_card_agent``'s ``messages`` takes). A commit is dated only
    when the object GitHub resolved is a commit whose oid begins with the hash
    asked -- a missing or ambiguous hash is None, never a guess. A trailer hash
    GitHub resolved dates its commit too when it has no date yet; one it did not
    (a null object) is skipped. An issue with no start is not a key. The mirror
    of ``ConvertFrom-P20StandupDates``."""
    repo = repository if isinstance(repository, dict) else {}
    commits: dict[str, str | None] = {}
    for i, h in enumerate(hashes):
        node = repo.get(f"c{i}")
        node = node if isinstance(node, dict) else {}
        oid = str(node.get("oid") or "").lower()
        when = node.get("authoredDate")
        commits[h] = str(when) if oid and oid.startswith(h) and _when(when) is not None else None
    starts: dict[int, str] = {}
    for n in numbers:
        node = repo.get(f"i{int(n)}")
        timeline = (node or {}).get("timelineItems") if isinstance(node, dict) else None
        start = issue_started((timeline or {}).get("nodes") or [], worker_labels)
        if start:
            starts[int(n)] = start
    messages: dict[str, str] = {}
    for i, h in enumerate(trailers or []):
        node = repo.get(f"t{i}")
        if not isinstance(node, dict):
            continue
        oid = str(node.get("oid") or "").lower()
        if not oid or not oid.startswith(h):
            continue
        messages.setdefault(h.lower()[:7], str(node.get("message") or ""))
        when = node.get("authoredDate")
        if not commits.get(h) and _when(when) is not None:
            commits[h] = str(when)
    return commits, starts, messages


def trailer_asks(filled: Standup, cards: list[dict]) -> list[str]:
    """The hashes whose co-author trailers the standup reads, from its own
    fill: the commits of every card the fill places that has no ``**Agent:**``
    line (``parsers.card_agent``) -- a card item in a slot, by its own path, and
    every card joined to an issue in the read, by its link's path (the issues
    read is the open ones and the ones closed in the window). Never the whole
    archive, and never a card whose line already answers. Distinct by the first
    seven characters, in first-seen order. The mirror of
    ``Get-P20StandupTrailerAsks``."""
    by_path = {str(c.get("path") or f"{c.get('folder', '')}/{c.get('file', '')}"): c for c in cards or []}
    paths: list[str] = []
    for w in filled.workers:
        for slot in ceremonies()[CEREMONY]["slots"]:
            for it in getattr(w, slot):
                if it.number is None and it.path and it.path not in paths:
                    paths.append(it.path)
    for lk in filled.links:
        if lk.path and lk.path not in paths:
            paths.append(lk.path)
    hashes: list[str] = []
    for p in paths:
        card = by_path.get(p)
        if card is None or card_agent(str(card.get("body") or "")):
            continue
        for h in card_hashes(card):
            if h not in hashes:
                hashes.append(h)
    return hashes


def date_asks(filled: Standup, cards: list[dict]) -> tuple[list[str], list[int]]:
    """What a standup asks the dates read for, from its own fill: the hashes
    of every card a slot item counts (an issue's joined card, by its link's
    path; a card item, by its own), and the numbers of the open issues with no
    card that read in progress -- the only ones a timeline can make started.
    Distinct, in first-seen order; the numbers ascending. The mirror of
    ``Get-P20StandupDateAsks``."""
    by_path = {str(c.get("path") or f"{c.get('folder', '')}/{c.get('file', '')}"): c for c in cards or []}
    linked = {lk.number: lk.path for lk in filled.links}
    _closed, _started, in_progress = rituals_motions()
    hashes: list[str] = []
    numbers: set[int] = set()
    for w in filled.workers:
        for slot in ceremonies()[CEREMONY]["slots"]:
            for it in getattr(w, slot):
                path = linked.get(it.number) if it.number is not None else it.path
                if it.number is not None and it.number not in linked and it.motion == in_progress:
                    numbers.add(it.number)
                card = by_path.get(path or "")
                for h in card_hashes(card) if card else []:
                    if h not in hashes:
                        hashes.append(h)
    return hashes, sorted(numbers)


def worker_name(description: str) -> str:
    """The text after the prefix, up to the separator, trimmed."""
    rest = (description or "")[len(rituals_worker_label_prefix()) :]
    return rest.split(_NAME_SEPARATOR, 1)[0].strip()


def _label_names(labels) -> list[str]:
    # gh gives label objects; the fixture gives names. Both read the same.
    return [lab.get("name", "") if isinstance(lab, dict) else str(lab) for lab in (labels or [])]


def _when(stamp) -> datetime | None:
    if not stamp:
        return None
    try:
        return datetime.fromisoformat(str(stamp))
    except ValueError:
        return None


def _item(issue: dict) -> SlotItem:
    # An issue alone says closed or in progress here: the issue read has no
    # fact that marks when its work began. The joined fill may say started --
    # from a card joined to it, else from its timeline (``issue_starts``).
    closed, _started, in_progress = rituals_motions()
    is_open = str(issue.get("state", "")).upper() == "OPEN"
    return SlotItem(
        number=int(issue.get("number", 0)),
        title=issue.get("title", "") or "",
        url=issue.get("url", "") or "",
        motion=in_progress if is_open else closed,
    )


def issue_keys(issues: list[dict]) -> dict[str, tuple[str, str]]:
    """Every issue's work-grain key, ``#<n>|`` -> (name, by). A `> GitHub:`
    thread is named by its issue's head: every issue in the read. The mirror of
    ``Get-P20StandupIssueKeys``."""
    threads = {str(int(i.get("number", 0))): str(i.get("title") or "") for i in issues or []}
    return {
        f"#{int(i.get('number', 0))}|": work_key(i.get("milestone"), i.get("body"), "", threads) for i in issues or []
    }


def set_idle(workers: list[Worker], d: int, words: dict, start: int = 0) -> None:
    """The idle worker's turn: each of ``workers`` (in order) that is ``empty``
    says two made-up items, ``status = [yesterday, today]`` --
    ``nothing[(d + i) mod len]`` and ``nothingToday[(d + i) mod len2]``, ``d`` the
    day of the year (1-based), ``i`` the worker's position among ``workers``
    (0-based) after ``start`` -- the places before it are someone else's (the
    record's, when ``workers`` are the invented cast members: ``seat_room``).
    The two lengths share no factor, so the pair does not repeat in
    step. ``excuse`` is the first of the two, for a reader that knows only that
    field. A worker with something to say gets ``""`` and ``[]``. With either
    family empty, no worker says a made-up item. The mirror of ``Set-P20StandupIdle``."""
    yesterday, today = words.get("nothing") or [], words.get("nothingToday") or []
    for i, w in enumerate(workers, start):
        w.excuse, w.status = "", []
        if w.empty and yesterday and today:
            w.status = [yesterday[(d + i) % len(yesterday)], today[(d + i) % len(today)]]
            w.excuse = w.status[0]


def team_size(stored) -> int:
    """A Space's ``features.teamSize`` as the room's size: the stored value when it
    is a whole JSON number in ``rituals.teamSizes`` (a string, a boolean or a
    fraction is not one), else ``rituals.teamSizeDefault`` -- unset reads the
    default too. The mirror of ``Get-P20TeamSize``; standup-team.json's ``sizes``."""
    if isinstance(stored, int) and not isinstance(stored, bool) and stored in rituals_team_sizes():
        return stored
    return rituals_team_size_default()


def room_seats(size: int, engineer: tuple[str, bool] | None, labels: list[tuple[str, bool]]) -> dict:
    """The room, from who there is. Pure over plain data; the mirror of
    ``Get-P20StandupRoomSeats``; standup-team.json's ``room`` rows.

    ``size`` is the room's windows, the chair's one of them, so ``size - 1``
    members sit. ``engineer`` is ``(label, empty)`` or None for a fill with no
    engineer; ``labels`` the labelled workers as ``(label, empty)``, in label order.

    - The seats go to the engineer, then the labelled workers with something to
      say, then the idle ones, each run in label order. Whoever is past the seats
      is absent.
    - A seat nobody takes is filled by an invented cast member: the member
      windows nobody sits in, in grid order (``rituals.room.windows``, the chair's
      left out), each labelled with its cast id.
    - A window is a member's own when its label is a key of ``rituals.room.kept``
      or is itself a member window's cast id (compared in lowercase). A seated
      member sits in its own window; an absent one keeps it empty. The engineer
      otherwise takes ``rituals.room.engineer`` when no member of the record owns
      it. Everyone else is dealt the free windows in grid order -- the engineer
      first, then the labels in their order -- and takes a window an absent
      member keeps only when the free ones run out.

    Returns ``present`` (the labels seated, in seat order), ``round`` (each
    speaker in turn order: ``label``, ``cast``, ``window``) and ``desks`` (the
    member windows left empty, in grid order)."""
    room = rituals_room()
    members = [w["id"] for w in room["windows"] if w["id"] != room["chair"]]
    kept = room["kept"]

    def own(label: str) -> str:
        low = label.lower()
        return kept.get(low) or (low if low in members else "")

    seats = max(size - 1, 0)
    # A member is its kind and its label: the engineer and a labelled worker can
    # share a label (a Space whose slug is one of its worker labels) and stay two.
    people = ([(True, engineer[0])] if engineer else []) + [(False, label) for label, _ in labels]
    order = (
        ([(True, engineer[0])] if engineer else [])
        + [(False, label) for label, empty in labels if not empty]
        + [(False, label) for label, empty in labels if empty]
    )
    seated = order[:seats]
    reserved = {own(label) for _, label in people if own(label)}
    window: dict[tuple[bool, str], str] = {}
    dealing = [m for m in people if m in seated]
    for m in dealing:
        if own(m[1]) and own(m[1]) not in window.values():
            window[m] = own(m[1])
    me = (True, engineer[0]) if engineer else None
    if me and me in seated and me not in window and room["engineer"] not in reserved:
        window[me] = room["engineer"]
    taken = set(window.values())
    opened = [m for m in members if m not in reserved and m not in taken]
    opened += [m for m in members if m in reserved and m not in taken]
    for m in dealing:
        if m not in window:
            window[m] = opened.pop(0)
    taken = set(window.values())
    invented = [m for m in members if m not in taken and m not in reserved][: max(seats - len(seated), 0)]
    spoken = [{"label": m[1], "cast": False, "window": window[m]} for m in seated]
    spoken += [{"label": m, "cast": True, "window": m} for m in invented]
    filled = taken | set(invented)
    seated = [label for _, label in seated]
    return {"present": seated, "round": spoken, "desks": [m for m in members if m not in filled]}


def seat_room(out: Standup, engineer: Worker | None, d: int, words: dict) -> None:
    """Seat ``out``: the team size is the team. ``out.workers`` is the record --
    the labelled workers in label order, then ``engineer`` (the card tile) when
    the fill has one -- and it is kept whole: each member gets its made-up items
    when idle (``set_idle``, by its place in the record) and ``present`` by
    ``room_seats``. The round (``out._round``) is who speaks, in seat order: the
    seated members, then the invented cast members that fill the seats left --
    each an idle worker named by its plate, its made-up items picked at the
    places after the record's last. The mirror of ``Set-P20StandupRoom``."""
    set_idle(out.workers, d, words)
    labels = [w for w in out.workers if w is not engineer]
    room = room_seats(
        out.team.size,
        (engineer.label, engineer.empty) if engineer is not None else None,
        [(w.label, w.empty) for w in labels],
    )
    # The engineer is the first seat when there is one; the rest are the labels.
    by_label: dict[str, Worker] = {}
    for w in labels:
        by_label.setdefault(w.label, w)
    skip = 1 if engineer is not None else 0
    seated = [by_label[label] for label in room["present"][skip:]]
    if engineer is not None and room["present"]:
        seated.insert(0, engineer)
    for w in out.workers:
        w.present = any(w is s for s in seated)
    plates = {w["id"]: w["plate"] for w in rituals_room()["windows"]}
    invented = [Worker(label=r["label"], name=plates[r["label"]], empty=True) for r in room["round"] if r["cast"]]
    # Their made-up items follow the record's: the same picker, the places after it.
    set_idle(invented, d, words, start=len(out.workers))
    out._round = seated + invented
    out._invented = len(invented)


def fill_standup(
    as_of: datetime,
    labels: list[dict],
    issues: list[dict],
    tracker_state: dict,
    space: str = "",
    window: str = "",
    size=None,
) -> Standup:
    """The standup's slots, queue and vocabulary from labels and issues. Pure.

    ``as_of`` is offset-aware; every comparison is between offset-aware times.
    ``tracker_state`` is ``{"ok": bool, "reason": str}``; when it is not ok the
    labels and issues are not read -- the ritual is the chair's lines and the reason.
    ``window`` is ``since``'s day (``window_start``); "" is the previous working day.
    ``size`` is the Space's ``features.teamSize`` as stored (``team_size`` reads it):
    the response's ``team.size``, and who is in the room (``seat_room``). This fill
    has no engineer: the seats its labels leave are the invented cast members'.
    """
    words = vocabulary()
    phrasebook = words["phrasebook"]
    d = as_of.timetuple().tm_yday
    since = window_start(as_of, window)
    state = TrackerState(ok=bool(tracker_state.get("ok")), reason=str(tracker_state.get("reason") or ""))
    out = Standup(
        register_=ceremonies()[CEREMONY]["registers"][0],
        asOf=as_of.isoformat(),
        since=since.isoformat(),
        space=space,
        tracker=state,
        chair=Chair(open=phrasebook[d % len(phrasebook)], close=phrasebook[(d + 1) % len(phrasebook)]),
        team=Team(size=team_size(size)),
    )
    if not state.ok:
        return out
    out.source = "issues"

    prefix, walk_label = rituals_worker_label_prefix(), rituals_walk_label()
    routes = sorted(
        (
            (str(lab.get("name", "")), worker_name(str(lab.get("description") or "")))
            for lab in labels or []
            if str(lab.get("description") or "").startswith(prefix)
        ),
        key=lambda t: t[0],
    )
    names = dict(routes)
    state.workerLabels = len(routes)
    workers = {label: Worker(label=label, name=name) for label, name in routes}
    key_of = issue_keys(issues)

    walk: list[WalkItem] = []
    for issue in sorted(issues or [], key=lambda i: int(i.get("number", 0))):
        tags = _label_names(issue.get("labels"))
        out._marks[f"#{int(issue.get('number', 0))}"] = tags
        owner = next((t for t in tags if t in names), "")
        is_open = str(issue.get("state", "")).upper() == "OPEN"
        on_walk = walk_label in tags
        if is_open and on_walk:
            walk.append(WalkItem(**_item(issue).model_dump(), worker=names.get(owner, "")))
        # What you walked: a walk item closed inside the window, worker or none.
        if on_walk and str(issue.get("state", "")).upper() == "CLOSED":
            done = _when(issue.get("closedAt"))
            if done is not None and since <= done <= as_of:
                out.chair.walked.append(_item(issue))
        if not owner:
            continue
        w = workers[owner]
        if is_open:
            (w.blockers if on_walk else w.today).append(_item(issue))
        else:
            closed = _when(issue.get("closedAt"))
            if closed is not None and since <= closed <= as_of:
                w.yesterday.append(_item(issue))

    out.queue = Queue(walk=walk)
    out.workers = [workers[label] for label, _ in routes]
    for w in out.workers:
        w.empty = not (w.yesterday or w.today or w.blockers)
    seat_room(out, None, d, words)
    out.work = build_work(out, key_of)
    out.counts = standup_counts(out, {})
    return out


# -- The second source: cards ------------------------------------------


def standup_source(address: str, status: str) -> tuple[str, str]:
    """(source, reason) for a Space. Pure; the mirror of ``Get-P20StandupSource``.

    ``both``: a GitHub Space that is not local or archive -- its issues AND its
    cards, joined on the id (``fill_joined_standup``). ``cards``: no tracker
    address, or a local or archive Space. ``none``: Azure DevOps -- the human
    team's board (D-TA19), with ``rituals.text.adoTracker`` as the reason.
    ``fill_standup`` alone still says ``issues``; no Space chooses it.
    """
    kind = tracker(address)
    if kind == "ado":
        return "none", rituals_text()["adoTracker"]
    if kind == "none" or status in ("local", "archive"):
        return "cards", ""
    return "both", ""


_HEADING = re.compile(r"(?m)^#[ \t]+([^\r\n]+)")


def card_title(content: str, file: str, cid: str | None) -> str:
    """A card's text -> the title its slot line shows. The first H1; when the part
    before its first colon ends with the card's id ("Task 139: Write the docs"),
    only the part after it. No heading: the filename without ``.prompt.md``.
    The mirror of ``Get-P20StandupCardTitle``; the fixture's ``titles`` table holds them."""
    m = _HEADING.search(content or "")
    if not m:
        for ext in (".prompt.md", ".md"):
            if file.lower().endswith(ext):
                return file[: -len(ext)]
        return file
    heading = m.group(1).strip()
    colon = heading.find(":")
    if colon > 0 and cid:
        before, after = heading[:colon].rstrip(), heading[colon + 1 :].strip()
        if after and re.search(r"(^|\s)" + re.escape(cid) + r"$", before):
            return after
    return heading


def _stamp_day(content: str, stamp: str) -> str | None:
    """The yyyy-MM-dd a footer stamp (``**Started:**``, ``**Created:**``) carries; None without one."""
    m = re.search(r"(?m)^" + re.escape(stamp) + r"[ \t]*(\d{4}-\d{2}-\d{2})", content or "")
    return m.group(1) if m else None


def read_cards(space_dir: Path, type_names: list[str], prefixes: list[str]) -> list[dict]:
    """The thin layer: a Space's ``current/`` and ``archive/`` as card rows --
    ``{file, folder, status, closed, title, id, path, type, body, billable, begun, commits,
    sprint, milestoneFromGitHub, created, tags, assigned}``. A file with no id by the
    one id rule is not a card and is skipped. State is the parser's rule; a card
    in ``archive/`` is Done and carries its Closed stamp's day."""
    rows: list[dict] = []
    closed_rx = re_closed_stamp_date()
    # The model map and its current block, read once for every card.
    model_rows, sizes = read_model_map(), read_model_current()
    for folder in (folder_current(), folder_archive()):
        d = space_dir / folder
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if not f.is_file() or f.name.startswith("."):
                continue
            cid = card_id(f.name, prefixes)
            if not cid:
                continue
            content = f.read_text(encoding="utf-8-sig", errors="replace")
            closed = None
            if folder == folder_current():
                state = _parse_status_metadata(content, type_names)["status"]
            else:
                state = status_done()
                m = closed_rx.search(content)
                closed = m.group(1) if m else None
            rows.append(
                {
                    "file": f.name,
                    "folder": folder,
                    "status": state,
                    "closed": closed,
                    "title": card_title(content, f.name, cid),
                    "id": cid,
                    "path": str(f),
                    "type": card_type(content, cid),
                    "body": content,
                    # A card that says `**Billable:** no` is not a standup row.
                    "billable": card_billable(content),
                    # What moved: the day its work began, and its commit bullets.
                    "begun": _stamp_day(content, stamp_started()) or _stamp_day(content, stamp_created()),
                    "commits": re_commit_bullet().findall(content),
                    # What the suggestion reads (suggest.py): the release its
                    # planning line names, whole (card_milestone), and whether that
                    # title is its issue's GitHub milestone; its **Created:** day; its
                    # Tags (a severity, a size); and who takes it -- the card's
                    # agent's family by the one reader (resolve_card_agent, the
                    # shipped order, no messages: its Agent line, else an older
                    # card's Assigned worker), else its Assigned line as written
                    # (``me``, an ``@<login>``, or "").
                    "sprint": card_milestone(content),
                    "milestoneFromGitHub": card_milestone_from_github(content),
                    "created": _stamp_day(content, stamp_created()),
                    "tags": card_tags(content),
                    "assigned": resolve_card_agent(content, "", None, model_rows, None, current=sizes)["family"]
                    or card_assigned(content),
                }
            )
    return rows


def cards_in_play(cards: list[dict]) -> list[dict]:
    """The cards a standup may mention: one per file, in file-name order, and
    none that says ``**Billable:** no`` (a row with no ``billable`` key is
    billable -- no line means billable, the rule Daily reads). The mirror of
    ``Get-P20StandupCardsInPlay``."""
    seen: set[str] = set()
    out: list[dict] = []
    for card in sorted(cards or [], key=lambda c: str(c.get("file", ""))):
        file = str(card.get("file", ""))
        if file in seen:
            continue
        seen.add(file)
        if card.get("billable", True) is False:
            continue
        out.append(card)
    return out


def _cards_tile(
    as_of: datetime,
    cards: list[dict],
    label: str,
    name: str,
    marks: dict,
    since: datetime | None = None,
    commit_dates: dict | None = None,
) -> tuple[Worker, list[WalkItem], dict[str, tuple[str, str]], dict[str, list[str]], dict[str, list[str]]]:
    """Cards (already in play) -> one worker's slots, its walk items, the
    work keys, each item's hashes to count and each item's undated hashes
    (``window_hashes`` over ``commit_dates``). yesterday: in ``archive/``, ``closed`` (a
    day) in [since's day, asOf's day]. today: in ``current/``, In Progress or
    Code Review. walk: in ``current/``, Code Review. An Active card is nowhere;
    so is an archived card with no Closed day. A yesterday item is closed; a
    today item started when its ``begun`` day is in the window, else in
    progress. ``empty`` is the caller's. The mirror of ``Get-P20StandupCardTile``."""
    since = since or previous_working_day_start(as_of)
    first, last = since.date().isoformat(), as_of.date().isoformat()
    closed, started, in_progress = rituals_motions()
    worker = Worker(label=label, name=name)
    walk: list[WalkItem] = []
    key_of: dict[str, tuple[str, str]] = {}
    hashes: dict[str, list[str]] = {}
    undated: dict[str, list[str]] = {}
    for card in cards:
        file = str(card.get("file", ""))
        folder = str(card.get("folder", ""))
        item = SlotItem(
            number=None,
            id=str(card.get("id") or ""),
            title=str(card.get("title") or ""),
            url="",
            path=str(card.get("path") or f"{folder}/{file}"),
        )
        # A card groups by the design card it names, else its type.
        key_of[f"{item.id}|{item.path}"] = work_key(None, card.get("body"), card.get("type"), {})
        marks[item.id or ""] = [str(card.get("type") or "")]
        ref = f"{item.id}|{item.path}"
        hashes[ref], undated[ref] = window_hashes(card_hashes(card), commit_dates, since, as_of)
        item.commits = len(hashes[ref])
        if folder == folder_archive():
            item.motion = closed
            day = str(card.get("closed") or "")[:10]
            if day and first <= day <= last:
                worker.yesterday.append(item)
            continue
        item.motion = started if card_begun_in(card, first, last) else in_progress
        state = card.get("status")
        if state in (status_in_progress(), status_code_review()):
            worker.today.append(item)
        if state == status_code_review():
            walk.append(WalkItem(**item.model_dump(), worker=name))
    return worker, walk, key_of, hashes, undated


class _CardMembers:
    """Who reports a card, once a card exists (docs/modules/solitaire-agile.md,
    "Where the room's members come from"): the family of the card's agent by the
    one reader (``resolve_card_agent``, the shipped order, the label never passed;
    ``messages`` the trailer read's, None for none) -- the labelled worker whose
    label is that family (ignoring case), else a member of its own, one per
    family, made the first time a card names it -- or None, the engineer, when
    the card names nobody. The mirror of ``Get-P20StandupCardMember``."""

    def __init__(self, labelled: list[Worker], messages: dict | None) -> None:
        self.by_low = {w.label.lower(): w for w in labelled}
        self.members: dict[str, Worker] = {}
        self.messages = messages
        self.rows, self.sizes = read_model_map(), read_model_current()

    def dest(self, card: dict) -> Worker | None:
        answer = resolve_card_agent(str(card.get("body") or ""), "", self.messages, self.rows, None, current=self.sizes)
        family = answer["family"]
        if not family:
            return None
        low = str(family).lower()
        if low in self.by_low:
            return self.by_low[low]
        if low not in self.members:
            # An id the map does not know is seated, and named, as written.
            unknown = bool(answer["id"]) and answer["id"] not in self.rows
            self.members[low] = card_member(str(family), as_written=unknown)
        return self.members[low]

    def seated(self) -> list[Worker]:
        """The members with something to say: one a card in scope names, and none
        that ends with nothing."""
        return [w for w in self.members.values() if w.yesterday or w.today or w.blockers]


def card_member(family: str, as_written: bool = False) -> Worker:
    """A member a card names that no worker label routes to: labelled with the
    family as written, named with its first letter in capitals -- or, for an id
    the map does not know (``as_written``), named as written -- and wearing the
    family in capitals on its plate unless the family keeps a window
    (``rituals.room.kept``). The mirror of ``New-P20StandupCardMember``."""
    plate = "" if family.lower() in rituals_room()["kept"] else family.upper()
    name = family if as_written else family[:1].upper() + family[1:]
    return Worker(label=family, name=name, plate=plate)


def _slot_order(w: Worker) -> None:
    """A slot's issues first, by number, then its cards in the order they came."""
    for slot in ceremonies()[CEREMONY]["slots"]:
        getattr(w, slot).sort(key=lambda i: (i.number is None, i.number or 0))


def _member_tiles(
    as_of: datetime,
    cards: list[dict],
    route: _CardMembers,
    engineer_label: str,
    engineer_name: str,
    marks: dict,
    since: datetime,
    commit_dates: dict | None,
) -> tuple[Worker, list[WalkItem], dict, dict, dict]:
    """Cards in file order -> the engineer's tile, with every card that names
    nobody, and each other card's items added to the member it names, each by
    ``_cards_tile``'s mapping; the walk in the cards' order, the work keys, the
    hashes and the undated."""
    groups: dict[int, tuple[Worker | None, list[dict]]] = {}
    for card in cards:
        target = route.dest(card)
        groups.setdefault(id(target), (target, []))[1].append(card)
    position = {str(c.get("path") or f"{c.get('folder', '')}/{c.get('file', '')}"): i for i, c in enumerate(cards)}
    engineer_cards = groups.pop(id(None), (None, []))[1]
    tile, walk, keys, hashes, undated = _cards_tile(
        as_of, engineer_cards, engineer_label, engineer_name, marks, since, commit_dates
    )
    for target, group in groups.values():
        part, part_walk, part_keys, part_hashes, part_undated = _cards_tile(
            as_of, group, target.label, target.name, marks, since, commit_dates
        )
        for slot in ceremonies()[CEREMONY]["slots"]:
            getattr(target, slot).extend(getattr(part, slot))
        walk += part_walk
        keys.update(part_keys)
        hashes.update(part_hashes)
        undated.update(part_undated)
    walk.sort(key=lambda w: position.get(w.path, 0))
    return tile, walk, keys, hashes, undated


def fill_cards_standup(
    as_of: datetime, cards: list[dict], space: str = "", space_name: str = "", window: str = "", size=None
) -> Standup:
    """The second fill, from card rows. Pure; the mirror of ``Invoke-P20StandupCardsFill``.

    The cards in play (``cards_in_play``: a not-billable card is left out) on
    ONE worker, the engineer, named for the Space, by ``_cards_tile``'s mapping.
    Within a slot, file-name order.
    """
    words = vocabulary()
    phrasebook = words["phrasebook"]
    d = as_of.timetuple().tm_yday
    since = window_start(as_of, window)
    name = space_name or space
    out = Standup(
        register_=ceremonies()[CEREMONY]["registers"][0],
        asOf=as_of.isoformat(),
        since=since.isoformat(),
        space=space,
        source="cards",
        tracker=TrackerState(ok=True, reason=""),
        chair=Chair(open=phrasebook[d % len(phrasebook)], close=phrasebook[(d + 1) % len(phrasebook)]),
        team=Team(size=team_size(size)),
    )
    # Each card is reported by the member its agent names (its Agent line, else
    # an older card's Assigned worker: no messages here), else by the engineer.
    route = _CardMembers([], None)
    worker, walk, key_of, hashes, _undated = _member_tiles(
        as_of, cards_in_play(cards), route, space, name, out._marks, since, None
    )
    members = sorted(route.seated(), key=lambda w: w.label)
    for w in [*members, worker]:
        _slot_order(w)
        w.empty = not (w.yesterday or w.today or w.blockers)
    out.queue = Queue(walk=walk)
    out.workers = [*members, worker]
    # The tile is the engineer: the first seat, and the record's last member.
    seat_room(out, worker, d, words)
    out.work = build_work(out, key_of)
    out.counts = standup_counts(out, hashes)
    return out


# -- Both: issues and cards, joined on the id -------------------------------
#
# The card is the job record, the tracker the product record; an active GitHub
# Space reads both (Tests/fixtures/rituals/standup-joined.json is the law):
#
#   a card whose id is an issue's number in the read IS that issue's job record:
#     ONE row, the issue's, placed by the issue as the issues fill places it.
#     The card adds its lane (``links``) and, where the two disagree, one
#     ``Check`` line: archived while the issue is open, or not archived while
#     the issue is closed. Rounds share an id: the one in current/ is the card,
#     else the archived one closed last.
#   any other card -- an id of its own, or a number the read has no issue for --
#     is its own row, under you: one tile labelled with the Space's slug and
#     named for it, by the cards fill's mapping, after the worker tiles. The
#     tile is the engineer, and it is always there: with no card to say, it is
#     idle, as a labelled worker with nothing routed is. Its Code Review cards
#     follow the issues on the walk.
#   a linked card whose issue got no slot at all (no worker label, so the
#     issues fill placed it nowhere) still gives the issue its link and its
#     row stays the issue's alone -- but when that card is itself in
#     current/, it also joins the under-you tile, in the slot its own lane
#     maps to, the same path an unlinked card of its own already takes.
#   a not-billable card is not a row and adds nothing to one.


def fill_joined_standup(
    as_of: datetime,
    labels: list[dict],
    issues: list[dict],
    tracker_state: dict,
    cards: list[dict],
    space: str = "",
    space_name: str = "",
    window: str = "",
    commit_dates: dict | None = None,
    issue_starts: dict | None = None,
    size=None,
    messages: dict | None = None,
) -> Standup:
    """The issues fill, joined with the cards on the id. Pure; the mirror of
    ``Invoke-P20StandupJoinedFill``. With the tracker not answering it is the
    issues fill as it stands: the chair's lines and the reason. A joined card
    gives its issue's row its commits, and says started for an open one whose
    card began in the window.

    The dates read (``tracker.dates``), when there was one: ``commit_dates``
    (hash -> its authored instant, or None) keeps a card's commits to those
    inside the window and counts the rest undated; ``issue_starts`` (issue
    number -> its timeline's start) says started for an open issue with no card
    whose work began in the window. None for either is not read, and today's
    rule stands: every bullet counts, and an issue alone is in progress.
    Once a card exists the card decides who reports it (``_CardMembers``: its
    Agent line, else an older card's Assigned worker, else the trailers its
    commits carry -- ``messages``, short hash -> commit message, the trailer
    read's -- else the engineer): a joined issue's row moves to that member, and
    every other card is that member's. An issue with no card stays with its
    label's worker."""
    out = fill_standup(as_of, labels, issues, tracker_state, space=space, window=window, size=size)
    if not out.tracker.ok:
        return out
    out.source = "both"
    t = rituals_text()
    since = datetime.fromisoformat(out.since)
    first, last = since.date().isoformat(), as_of.date().isoformat()
    _closed, started, in_progress = rituals_motions()
    hashes: dict[str, list[str]] = {}
    undated: dict[str, list[str]] = {}
    issue_items = [i for w in out.workers for slot in ceremonies()[CEREMONY]["slots"] for i in getattr(w, slot)]
    issue_items += list(out.queue.walk)
    by_number = {int(i.get("number", 0)): i for i in issues or []}
    joined: dict[int, list[dict]] = {}
    alone: list[dict] = []
    for card in cards_in_play(cards):
        cid = str(card.get("id") or "")
        if cid.isdigit() and int(cid) in by_number:
            joined.setdefault(int(cid), []).append(card)
        else:
            alone.append(card)
    unrouted: list[dict] = []
    chosen: list[tuple[int, dict]] = []
    for number in sorted(joined):
        rounds = joined[number]
        current = [c for c in rounds if str(c.get("folder", "")) == folder_current()]
        if current:
            card = current[0]
        else:
            # The archived round closed last; the later file breaks a tie.
            card = max(rounds, key=lambda c: (str(c.get("closed") or "")[:10], str(c.get("file", ""))))
        path = str(card.get("path") or f"{card.get('folder', '')}/{card.get('file', '')}")
        out.links.append(
            CardLink(number=number, id=str(card.get("id") or ""), lane=str(card.get("status") or ""), path=path)
        )
        hashes[f"#{number}|"], undated[f"#{number}|"] = window_hashes(card_hashes(card), commit_dates, since, as_of)
        chosen.append((number, card))
        begun = card_begun_in(card, first, last)
        placed = False
        for it in issue_items:
            if it.number == number:
                placed = True
                it.commits = len(hashes[f"#{number}|"])
                if begun and it.motion == in_progress:
                    it.motion = started
        issue = by_number[number]
        is_open = str(issue.get("state", "")).upper() == "OPEN"
        item = f"#{number} {issue.get('title', '') or ''}"
        if current and not is_open:
            out.checks.append(t["checkIssueClosed"].replace("{item}", item))
        elif not current and is_open:
            out.checks.append(t["checkCardArchived"].replace("{item}", item))
        # The issue gave it no slot at all (no worker label) -- its own card,
        # if it is in current/, falls back to the under-you tile by its lane.
        if not placed and current:
            unrouted.append(card)

    # An open issue with no card: its timeline says when its work began.
    starts = {int(k): v for k, v in (issue_starts or {}).items()}
    for it in issue_items:
        if it.number is None or it.number in joined or it.motion != in_progress:
            continue
        if commit_in_window(starts.get(it.number), since, as_of):
            it.motion = started

    # Once a card exists the card decides: a joined issue's row moves from its
    # label's worker to the member the card names, or to the engineer.
    labelled = list(out.workers)
    route = _CardMembers(labelled, messages)
    engineer_name = space_name or space
    moved: dict[str, list[SlotItem]] = {slot: [] for slot in ceremonies()[CEREMONY]["slots"]}
    for number, card in chosen:
        target = route.dest(card)
        for holder in labelled:
            if holder is target:
                continue
            for slot in ceremonies()[CEREMONY]["slots"]:
                items = getattr(holder, slot)
                mine = [i for i in items if i.number == number]
                if not mine:
                    continue
                setattr(holder, slot, [i for i in items if i.number != number])
                (getattr(target, slot) if target is not None else moved[slot]).extend(mine)
        for w in out.queue.walk:
            if w.number == number:
                w.worker = target.name if target is not None else engineer_name

    tile_cards = sorted(alone + unrouted, key=lambda c: str(c.get("file", "")))
    tile, walk, card_keys, tile_hashes, tile_undated = _member_tiles(
        as_of, tile_cards, route, space, engineer_name, out._marks, since, commit_dates
    )
    for slot, items in moved.items():
        getattr(tile, slot).extend(items)
    out.workers = sorted([*labelled, *route.seated()], key=lambda w: w.label)
    # The engineer is always in the room: the record's last member, the first seat.
    out.workers.append(tile)
    for w in out.workers:
        _slot_order(w)
        w.empty = not (w.yesterday or w.today or w.blockers)
    seat_room(out, tile, as_of.timetuple().tm_yday, vocabulary())
    out.queue.walk.extend(walk)
    out.work = build_work(out, {**issue_keys(issues), **card_keys}, dated=commit_dates is not None)
    out.counts = standup_counts(out, {**hashes, **tile_hashes}, {**undated, **tile_undated})
    return out


def standup_counts(
    filled: Standup, hashes: dict[str, list[str]], undated: dict[str, list[str]] | None = None
) -> Counts:
    """What moved in the window, per worker (in the workers' order) and in total:
    each slot item by its motion, and the distinct hashes its card threads --
    ``hashes`` maps an item's ``<ref>|<path>`` to them, and ``undated`` to the
    ones the dates read gave no date. A hash is counted once
    per worker and once in the total, however many cards thread it; an issue
    with no card, and a card with no bullets, count none. Pure; the mirror of
    ``Get-P20StandupCounts``."""
    closed, started, in_progress = rituals_motions()
    out = Counts()
    every: list[str] = []
    every_undated: list[str] = []
    for w in filled.workers:
        c = MotionCount(label=w.label, name=w.name)
        mine: list[str] = []
        mine_undated: list[str] = []
        for slot in ceremonies()[CEREMONY]["slots"]:
            for it in getattr(w, slot):
                if it.motion == closed:
                    c.closed += 1
                elif it.motion == started:
                    c.started += 1
                elif it.motion == in_progress:
                    c.inProgress += 1
                ref = f"#{it.number}" if it.number is not None else (it.id or "")
                for h in hashes.get(f"{ref}|{it.path}", []):
                    if h not in mine:
                        mine.append(h)
                for h in (undated or {}).get(f"{ref}|{it.path}", []):
                    if h not in mine_undated:
                        mine_undated.append(h)
        c.commits = len(mine)
        c.undated = len(mine_undated)
        every += [h for h in mine if h not in every]
        every_undated += [h for h in mine_undated if h not in every_undated]
        out.workers.append(c)
        out.total.closed += c.closed
        out.total.started += c.started
        out.total.inProgress += c.inProgress
    out.total.commits = len(every)
    out.total.undated = len(every_undated)
    return out


# -- The work grain (D-TA20) ---------------------------------------------
#
# The ritual speaks at the grain of the WORK, not the ticket: each worker's slot
# items grouped by what they belong to, one phrase per group with the count
# behind it ("Team Agile, three closed; the Studio, one"). No model groups
# anything. The mirror of the CLI's Group-P20StandupWork and friends;
# Tests/fixtures/rituals/standup-work.json holds the two to one table.
#
#   1. milestone  the issue's milestone title                          by milestone
#   2. design     the design card the body names: a `> GitHub:` thread (named
#                 by that issue's head when the read has it, else #<n>), else
#                 a design/<note>.md (its stem, title-cased)            by design
#   3. type       a card's type, from its heading                       by type
#   4. stem       what is left in the slot, by the titles' common stem: heads
#                 sharing their first two words or more (a trailing small word
#                 not counted) group under the words they all share     by stem
#
# Groups with the same name (ignoring case) are one, named as first seen. Most
# items first; a tie keeps the slot's order.


def title_head(title: str) -> str:
    """A title's head, by ``rituals.workHeadRegex``; the trimmed title when that leaves nothing."""
    text = (title or "").strip()
    m = re.match(rituals_work_head_regex(), text)
    head = m.group(1).strip() if m else ""
    return head or text


def design_name(stem: str) -> str:
    """A design note's stem, title-cased: ``team-agile`` -> ``Team Agile``."""
    return " ".join(w[:1].upper() + w[1:] for w in re.split(r"[-_]+", stem or "") if w)


def card_type(content: str, cid: str | None) -> str:
    """A card's type, from its heading: the words before its id ("Task 139: x" is Task).
    The mirror of ``Get-P20StandupCardType``."""
    m = _HEADING.search(content or "")
    if not m or not cid:
        return ""
    heading = m.group(1).strip()
    colon = heading.find(":")
    if colon <= 0:
        return ""
    tm = re.match(r"^(.*\S)\s+" + re.escape(cid) + r"$", heading[:colon].rstrip())
    return tm.group(1).strip() if tm else ""


def work_key(milestone, body, kind, threads: dict[str, str]) -> tuple[str, str]:
    """(name, by) for one item: rules 1 to 3, in order; ("", "") leaves it to the stem.
    ``milestone`` is gh's object ({"title": ...}) or the fixture's string."""
    title = milestone.get("title", "") if isinstance(milestone, dict) else (milestone or "")
    title = str(title or "").strip()
    if title:
        return title, "milestone"
    text = str(body or "")
    tm = re.search(rituals_work_thread_regex(), text)
    if tm:
        n = str(int(tm.group(1)))
        return (title_head(threads[n]) if n in threads else f"#{n}"), "design"
    dm = re.search(rituals_work_design_regex(), text)
    if dm:
        return design_name(dm.group(1)), "design"
    kind = str(kind or "").strip()
    if kind:
        return kind, "type"
    return "", ""


def count_word(n: int) -> str:
    """A count as the voice says it: ``rituals.numberWords[n]``, digits past its end."""
    words = rituals_number_words()
    return words[n] if 0 <= n < len(words) else str(n)


def _common_words(a: list[str], b: list[str]) -> int:
    """Leading words two heads share, ignoring case, not counting a trailing small word."""
    k = 0
    while k < len(a) and k < len(b) and a[k].lower() == b[k].lower():
        k += 1
    small = rituals_work_small_word_regex()
    while k > 0 and re.match(small, a[k - 1]):
        k -= 1
    return k


def group_work(entries: list[dict], first: str, rest: str) -> list[WorkGroup]:
    """One slot's entries -- ``{ref, title, name, by}`` in the slot's order -- as its groups.
    ``first`` is the phrase template of the slot's first group, ``rest`` the others'."""
    names = [str(e.get("name") or "") for e in entries]
    bys = [str(e.get("by") or "") for e in entries]
    left = [i for i, n in enumerate(names) if not n]
    heads = {i: title_head(str(entries[i].get("title") or "")) for i in left}
    words = {i: heads[i].split() for i in left}
    for i in left:
        if names[i]:
            continue
        members, shared = [i], None
        for j in left:
            if j <= i or names[j]:
                continue
            k = _common_words(words[i], words[j])
            if k >= 2:
                members.append(j)
                shared = k if shared is None else min(shared, k)
        name = " ".join(words[i][:shared]) if shared else heads[i]
        for m in members:
            names[m], bys[m] = name, "stem"
    groups: list[dict] = []
    at: dict[str, int] = {}
    for i, e in enumerate(entries):
        key = names[i].lower()
        if key not in at:
            at[key] = len(groups)
            groups.append({"name": names[i], "by": bys[i], "refs": []})
        groups[at[key]]["refs"].append(str(e.get("ref") or ""))
    groups.sort(key=lambda g: -len(g["refs"]))  # stable: a tie keeps first appearance
    return [
        WorkGroup(
            name=g["name"],
            by=g["by"],
            count=len(g["refs"]),
            refs=g["refs"],
            phrase=(first if n == 0 else rest).replace("{name}", g["name"]).replace("{n}", count_word(len(g["refs"]))),
        )
        for n, g in enumerate(groups)
    ]


def work_template(slot: str) -> str:
    """The first group's phrase template for a slot or queue kind: ``text.work<Slot>``, else ``workGroup``."""
    t = rituals_text()
    return t.get(f"work{slot[:1].upper()}{slot[1:]}") or t["workGroup"]


def item_worked(item: SlotItem, dated: bool) -> bool:
    """Whether an open item holds real work inside the window, the fact a
    yesterday may say when it closed nothing: its work began inside it (its
    motion is started -- a card's **Started:** or **Created:** day, or an issue's
    timeline) or, where the commit dates were read (``dated``), its card threads a
    commit authored inside it. Undated commits prove nothing, and an item merely
    in progress is no fact. Pure; the mirror of ``Test-P20StandupItemWorked``."""
    closed, started, _in_progress = rituals_motions()
    if item.motion == closed:
        return False
    return item.motion == started or (dated and item.commits > 0)


def prose_unsaid(slot: str, worked: list[str]) -> list[str]:
    """What a member with something to say says for a slot it has nothing in:
    ``text.prose<Slot>Worked`` with ``worked`` (the refs of its open items worked
    inside the window, ``item_worked``) where the slot has that template and
    there are some -- ``prose<Slot>WorkedMany`` with their count past
    proseFoldNames -- else the fixed line ``text.prose<Slot>None``; nothing when
    the slot has neither. Never a made-up item. Pure; the mirror of
    ``Get-P20StandupProseUnsaid``; standup-prose.json's ``unsaid`` rows."""
    t = rituals_text()
    cap = slot[:1].upper() + slot[1:]
    if worked and t.get(f"prose{cap}Worked"):
        return [_chair_refs(f"prose{cap}Worked", worked)]
    line = t.get(f"prose{cap}None") or ""
    return [line] if line else []


def build_work(filled: Standup, key_of: dict[str, tuple[str, str]], dated: bool = False) -> Work:
    """The filled standup's work grain, text left empty. ``key_of`` maps an item's
    ``<ref>|<path>`` to its ``work_key``; ``dated`` is whether the commit dates
    were read, so a card's commits are only those inside the window
    (``item_worked``). Pure."""
    rest = rituals_text()["workGroup"]

    def groups(items, slot: str) -> tuple[list[WorkGroup], list[str]]:
        rows = []
        for it in items:
            ref = f"#{it.number}" if it.number is not None else (it.id or "")
            name, by = key_of.get(f"{ref}|{it.path}", ("", ""))
            rows.append({"ref": ref, "title": it.title, "name": name, "by": by})
        grouped = group_work(rows, work_template(slot), rest)
        return grouped, prose_sentences(slot, grouped, {r["ref"]: r["title"] for r in rows})

    cer = ceremonies()[CEREMONY]
    queue: dict[str, list[WorkGroup]] = {}
    queue_prose: list[str] = []
    for kind in cer["queue"]:
        queue[kind], said = groups(getattr(filled.queue, kind), kind)
        queue_prose += said
    workers = []
    # The round (``seat_room``): the seated members in seat order, then the invented
    # cast members. An absent worker has no row. A standup nobody seated speaks
    # its present workers, in their order.
    speakers = filled._round if filled._round is not None else [w for w in filled.workers if w.present]
    first_cast = len(speakers) - filled._invented
    for at, w in enumerate(speakers):
        slots: dict[str, list[WorkGroup]] = {}
        sentences: dict[str, list[str]] = {}
        for slot in cer["slots"]:
            slots[slot], sentences[slot] = groups(getattr(w, slot), slot)
        if w.empty:
            # An idle worker's sentences are its two made-up items, yesterday and today.
            said = prose_close(list(w.status), slots)
        else:
            # Real facts where there are any; a slot with none says its fixed line
            # (prose_unsaid) -- never a made-up item beside a real one.
            mine = {
                (f"#{i.number}" if i.number is not None else (i.id or ""))
                for slot in cer["slots"]
                for i in getattr(w, slot)
                if item_worked(i, dated)
            }
            worked = [r for slot in cer["slots"] for g in slots[slot] for r in g.refs if r in mine]
            said = [x for slot in cer["slots"] for x in (sentences[slot] or prose_unsaid(slot, worked))]
        workers.append(WorkWorker(label=w.label, name=w.name, prose=prose_turn(said), cast=at >= first_cast, **slots))
    chair = chair_turn(filled, queue) if filled.tracker.ok else []
    return Work(queue=WorkQueue(**queue), workers=workers, queueProse=queue_prose, chairProse=chair)


# -- The prose -----------------------------------------------------------
#
# The work grain spoken as standup language: a grammar over the groups, no model.
# One sentence a group -- text.proseSentence joins a LEAD and a BODY:
#
#   lead  text.prose<Slot> for the slot's (or queue kind's) first group,
#         text.prose<Slot>Also for the rest     "Yesterday I closed" / "I also closed"
#   body  a group of one whose name IS its item's clause: text.proseBare
#                                               "#413, Rename the slug"
#         a group of one: text.prose<Slot>One, else text.proseOne
#                                               "one in the Studio: #<n>, Count the foyer rows"
#         a group of more: text.prose<Slot>Many, else text.proseMany
#                                               "two in Team Agile"
#
# {item} is text.proseItem -- the ref, then the title trimmed to its clause (its
# head, by workHeadRegex); {refs} the group's refs joined by proseRefSeparator.
# A slot with a text.prose<Slot>Fold template (today's) FOLDS when two or more
# groups follow its first (D-SA9: a group and a count, never a list): the
# first group is its own sentence, as above, and the rest are ONE sentence --
#
#   lead  text.prose<Slot>Also                  "I'm also on"
#   body  up to proseFoldNames groups: text.prose<Slot>Fold, {n} the number of
#         groups, {names} their names (proseNameSeparator, the last proseNameLast)
#                                               "three more: the Studio, Phase 6 and Docs"
#         past it: text.prose<Slot>FoldCount    "seven more designs"
#
# No ref in a folded sentence: the thought bubble keeps every number.
# A worker with something to say and no blockers ends on text.proseBlockersNone,
# and says a yesterday and a today: a slot it has nothing in says text.prose<Slot>None
# -- for yesterday, first the refs of its open items worked inside the window,
# text.prose<Slot>Worked. Only a worker with nothing at all says made-up items.
# The mirror of the CLI's Get-P20StandupProseSentence and Get-P20StandupProse;
# standup-prose.json is the table.

_PLACEHOLDER = re.compile(r"\{(n|names|name|item|refs|ref|clause|lead|body|motion|title|date|counts)\}")


def _fill(template: str, values: dict[str, str]) -> str:
    """One pass over a template's placeholders: a value is never read as a placeholder."""
    return _PLACEHOLDER.sub(lambda m: values.get(m.group(1), m.group(0)), template)


def prose_sentence(slot: str, first: bool, group: WorkGroup, titles: dict[str, str]) -> str:
    """One group of a slot (or queue kind) as one standup sentence. ``titles`` maps
    a ref to its title. Pure."""
    t = rituals_text()
    cap = slot[:1].upper() + slot[1:]
    lead = t[f"prose{cap}"] if first else t[f"prose{cap}Also"]
    n = count_word(group.count)
    if group.count == 1 and group.refs:
        ref = group.refs[0]
        clause = title_head(titles.get(ref, ""))
        item = _fill(t["proseItem"], {"ref": ref, "clause": clause})
        if group.name.lower() == clause.lower():
            body = _fill(t["proseBare"], {"item": item})
        else:
            body = _fill(t.get(f"prose{cap}One") or t["proseOne"], {"n": n, "name": group.name, "item": item})
    else:
        refs = t["proseRefSeparator"].join(group.refs)
        body = _fill(t.get(f"prose{cap}Many") or t["proseMany"], {"n": n, "name": group.name, "refs": refs})
    return _fill(t["proseSentence"], {"lead": lead, "body": body})


def prose_folds(slot: str, groups: list[WorkGroup]) -> bool:
    """Whether a slot's groups after its first are said as one sentence: the slot
    has a text.prose<Slot>Fold template and two or more groups follow the first."""
    return bool(rituals_text().get(f"prose{slot[:1].upper()}{slot[1:]}Fold")) and len(groups) > 2


def _fold_names(groups: list[WorkGroup]) -> str:
    """The groups' names as a sentence says them: "a, b and c"."""
    t = rituals_text()
    names = [g.name for g in groups]
    if len(names) < 2:
        return "".join(names)
    return t["proseNameSeparator"].join(names[:-1]) + t["proseNameLast"] + names[-1]


def prose_fold_sentence(slot: str, groups: list[WorkGroup]) -> str:
    """The groups after a slot's first as ONE sentence: their count and, up to
    proseFoldNames of them, their names; no refs. Pure."""
    t = rituals_text()
    cap = slot[:1].upper() + slot[1:]
    n = count_word(len(groups))
    if len(groups) > rituals_prose_fold_names():
        body = _fill(t[f"prose{cap}FoldCount"], {"n": n})
    else:
        body = _fill(t[f"prose{cap}Fold"], {"n": n, "names": _fold_names(groups)})
    return _fill(t["proseSentence"], {"lead": t[f"prose{cap}Also"], "body": body})


def prose_sentences(slot: str, groups: list[WorkGroup], titles: dict[str, str]) -> list[str]:
    """A slot's groups as its sentences, in the groups' order -- one a group, or
    the first and one fold sentence for the rest (prose_folds). Pure."""
    if prose_folds(slot, groups):
        return [prose_sentence(slot, True, groups[0], titles), prose_fold_sentence(slot, groups[1:])]
    return [prose_sentence(slot, i == 0, g, titles) for i, g in enumerate(groups)]


def prose_close(said: list[str], slots: dict[str, list[WorkGroup]]) -> list[str]:
    """An idle worker's sentences, closed: proseBlockersNone after them when there
    are any and the blockers slot has none. No sentences say nothing."""
    if said and not slots.get("blockers"):
        return said + [rituals_text()["proseBlockersNone"]]
    return said


def _ref_list(refs: list[str]) -> str:
    """Refs as a sentence says them: one alone, two joined by proseNameLast, more by
    proseNameSeparator and the last by proseNameLast."""
    t = rituals_text()
    if len(refs) < 2:
        return "".join(refs)
    return t["proseNameSeparator"].join(refs[:-1]) + t["proseNameLast"] + refs[-1]


def _chair_refs(key: str, refs: list[str]) -> str:
    """``text.<key>`` with its refs, or past proseFoldNames of them ``text.<key>Many``
    with their count: the chair names a few and counts a crowd."""
    t = rituals_text()
    if len(refs) > rituals_prose_fold_names():
        return _fill(t[f"{key}Many"], {"n": count_word(len(refs))})
    return _fill(t[key], {"refs": _ref_list(refs)})


def chair_yesterday(walked: list[str], d: int, workers: int) -> str:
    """The chair's yesterday: what you walked (``walked``, the refs of
    ``chair.walked``) as text.chairYesterday; with none, the made-up
    ``nothing[(d + n) mod len]`` -- ``d`` the day of the year, ``n`` the number
    of workers, the position after the last; "" with the family empty. Pure;
    the mirror of ``Get-P20StandupChairYesterday``; standup-prose.json's ``chairYesterday`` rows."""
    if walked:
        return _chair_refs("chairYesterday", walked)
    made_up = vocabulary().get("nothing") or []
    if not made_up:
        return ""
    return made_up[(d + workers) % len(made_up)]


def chair_today(queue: dict[str, list[list[str]]]) -> str:
    """The chair's today, from what waits: ``queue`` maps a queue kind to its
    groups' refs. One clause a kind that has items, in the ceremony's order --
    text.chair<Kind> with its refs in the groups' order, or text.chair<Kind>Many
    past proseFoldNames -- joined by chairClauseSeparator, the last by
    chairClauseLast, in text.chairToday; with nothing waiting,
    text.chairTodayNone. Pure; the mirror of ``Get-P20StandupChairToday``;
    standup-prose.json's ``chairToday`` rows."""
    t = rituals_text()
    clauses = []
    for kind in ceremonies()[CEREMONY]["queue"]:
        refs = [r for g in queue.get(kind) or [] for r in g]
        if refs:
            clauses.append(_chair_refs(f"chair{kind[:1].upper()}{kind[1:]}", refs))
    if not clauses:
        return t["chairTodayNone"]
    head = t["chairClauseSeparator"].join(clauses[:-1])
    body = clauses[0] if len(clauses) == 1 else head + t["chairClauseLast"] + clauses[-1]
    return _fill(t["chairToday"], {"body": body})


def chair_turn(filled: Standup, queue: dict[str, list[WorkGroup]]) -> list[str]:
    """The chair's own turn, in its own first person and never the board's words:
    turnOpen, its yesterday, its today, proseBlockersNone, turnClose. Pure."""
    d = datetime.fromisoformat(filled.asOf).timetuple().tm_yday
    walked = [f"#{i.number}" for i in filled.chair.walked]
    today = chair_today({kind: [g.refs for g in groups] for kind, groups in queue.items()})
    # Its made-up yesterday is picked at the place after the last member's: the
    # record's, then the invented cast members'.
    said = [x for x in (chair_yesterday(walked, d, len(filled.workers) + filled._invented), today) if x]
    return prose_turn([*said, rituals_text()["proseBlockersNone"]])


def prose_turn(said: list[str]) -> list[str]:
    """Sentences as one turn: turnOpen before them and turnClose after, the frame
    every speaker's status is said in. Nothing said is no turn. Pure; the mirror
    of ``Get-P20StandupTurn``."""
    if not said:
        return []
    t = rituals_text()
    return [t["turnOpen"], *said, t["turnClose"]]


# -- The dress (D-SA11) ---------------------------------------------------
#
# A model may DRESS a worker's prose sentence in the standup register and never
# ADD a fact. The prose above is the floor and the fallback: each group's facts
# (its name, count, refs, titles and kind counts, and the prose sentence) go to
# the model through the provider profile (core/model.py), one sentence comes back
# per group, and dress_guard holds each one -- the first check it fails is the
# reason the prose sentence stands instead. The checks are rituals.dressGuards,
# in order:
#
#   empty          blank, or more than one line
#   ref-added      a ref (dressRefRegex: #n, or a card-id-shaped word) not the group's
#   ref-dropped    a ref of the group the sentence does not say
#   number         a number (dressNumberRegex, or a numberWords word) that is not the
#                  count, a kind count, or a number in the facts' own words
#   count-dropped  a group of two or more whose count is not said
#   kind           a kind noun (ceremonies' standup.kinds) for a kind the group has
#                  none of, or after a number that is not that kind's count
#   name-dropped   the group's name not said (a group of one named by its own
#                  clause may re-say the clause)
#   name           a capitalised word (dressNameRegex) that is not sentence-initial,
#                  not the first person's I (dressPronounRegex), and not a word of
#                  the facts -- the worker's name, the group's, the titles, the prose
#
# A number glued to a unit ("20g of protein") is no number and a lowercase word is
# no name: the persona's colour is not checked, the work is (the issue's comment).
# The mirror of the CLI's Test-P20StandupDress; standup-dress.json is the table.
# Only the agent calls a model; the CLI's Standup prints the prose.

# A page load waits on the model at most this long, then the prose stands.
DRESS_TIMEOUT_SECONDS = 30
# Dressed replies, by a hash of the model, the register and the facts (each
# sentence's prose floor among them): the same facts are dressed once. Kept in
# memory, and on disk (core/disk_cache.py) so an agent restart keeps them. The
# namespace's number is the reply's version: change what a kept reply means and
# bump it, so every sentence is dressed again rather than read as the old rule left it.
_DRESS_CACHE_SIZE = 64
_DRESSED: OrderedDict[str, dict] = OrderedDict()
DRESS_CACHE = "standup-dress-1"

_WORD = re.compile(r"[A-Za-z0-9#'-]+")
_NAME_WORD = re.compile(r"[A-Za-z0-9'-]+")


def _kinds() -> list[dict]:
    return list(ceremonies()[CEREMONY].get("kinds") or [])


def _number_words_regex() -> re.Pattern:
    words = "|".join(re.escape(w) for w in rituals_number_words())
    return re.compile(r"(?<![\w'-])(?:" + words + r")(?![\w'-])", re.IGNORECASE)


def _number_value(token: str) -> int | None:
    """A word as a number: digits, or a numberWords word (ignoring case); else None."""
    if re.fullmatch(r"\d+", token):
        return int(token)
    low = token.lower()
    words = [w.lower() for w in rituals_number_words()]
    return words.index(low) if low in words else None


def _numbers(text: str) -> list[int]:
    """Every number a text says: standalone digits and numberWords words."""
    said = [int(m.group(0)) for m in re.finditer(rituals_dress_number_regex(), text or "")]
    said += [_number_value(m.group(0)) for m in _number_words_regex().finditer(text or "")]
    return [n for n in said if n is not None]


def _possessive(word: str) -> str:
    return word.removesuffix("'s")


def dress_guard(facts: dict, sentence: str) -> str:
    """'' when a dressed sentence keeps every fact of its group and adds none;
    else the first of rituals.dressGuards it fails. Pure; the mirror of
    ``Test-P20StandupDress``, held by ``Tests/fixtures/rituals/standup-dress.json``."""
    s = sentence or ""
    if not s.strip() or "\n" in s or "\r" in s:
        return "empty"
    refs = [str(r) for r in facts.get("refs") or []]
    for m in re.finditer(rituals_dress_ref_regex(), s):
        if m.group(0) not in refs:
            return "ref-added"
    for r in refs:
        pattern = (re.escape(r) + r"(?!\d)") if r.startswith("#") else (r"(?<![\w#])" + re.escape(r) + r"(?!\w)")
        if not re.search(pattern, s):
            return "ref-dropped"
    name = str(facts.get("name") or "")
    titles = {str(k): str(v) for k, v in (facts.get("titles") or {}).items()}
    kinds = {str(k): int(v) for k, v in (facts.get("kinds") or {}).items()}
    count = int(facts.get("count") or 0)
    allowed = {count, *kinds.values()}
    for r in refs:
        digits = r.lstrip("#")
        if digits.isdigit():
            allowed.add(int(digits))
    for text in [name, str(facts.get("worker") or ""), *titles.values()]:
        allowed.update(_numbers(text))
    said = _numbers(s)
    if any(n not in allowed for n in said):
        return "number"
    if count >= 2 and count not in said:
        return "count-dropped"
    for kind in _kinds():
        nouns = re.compile(
            r"(?<![\w'-])(?:" + re.escape(kind["many"]) + "|" + re.escape(kind["one"]) + r")(?![\w'-])", re.IGNORECASE
        )
        have = kinds.get(kind["many"], 0)
        for m in nouns.finditer(s):
            if have <= 0:
                return "kind"
            for token in reversed(_WORD.findall(s[: m.start()])[-3:]):
                value = _number_value(token)
                if value is not None:
                    if value != have:
                        return "kind"
                    break
    clause = title_head(titles.get(refs[0], "")) if refs else ""
    bare = count == 1 and len(refs) == 1 and name.lower() == clause.lower()
    if not bare and name.lower() not in s.lower():
        return "name-dropped"
    known = " ".join([name, str(facts.get("worker") or ""), str(facts.get("floor") or ""), *titles.values()])
    words = {_possessive(w).lower() for w in _NAME_WORD.findall(known)}
    for m in re.finditer(rituals_dress_name_regex(), s):
        word = _possessive(m.group(0))
        if re.match(rituals_dress_pronoun_regex(), word):
            continue
        before = re.sub(r"[\s\"'(]+$", "", s[: m.start()])
        if not before or before[-1] in ".!?:":
            continue
        if word.lower() not in words:
            return "name"
    return ""


def dress_facts(filled: Standup) -> list[dict]:
    """The facts the model is given: one entry per worker sentence that says a
    group -- not the closing proseBlockersNone, not a slot's line from
    ``prose_unsaid`` (a fixed line, or the refs worked in the window: no group
    speaks it), not the queue's sentences (they
    are the chair's, not a worker's first person), not an excuse (the empty worker reports "nothing").
    A folded sentence (prose_folds) is one entry: its name is the names it says
    (none past proseFoldNames), its count the groups', and its refs only what
    those names spell. Pure."""
    cer = ceremonies()[CEREMONY]
    by_label = {w.label: w for w in filled.workers}
    facts: list[dict] = []
    for ww in filled.work.workers:
        # An invented cast member says made-up items only, and its label is a cast
        # id, which a worker label may also be: it is never read against the record.
        w = None if ww.cast else by_label.get(ww.label)
        if w is None or w.empty:
            continue
        # The turn opens on turnOpen, which is the frame's and not dressed.
        at = 1 if ww.prose else 0
        for slot in cer["slots"]:
            items = getattr(w, slot)
            titles = {(f"#{i.number}" if i.number is not None else (i.id or "")): i.title for i in items}
            groups = getattr(ww, slot)
            if not groups:
                # A slot with nothing says its line from prose_unsaid -- a fixed
                # line, or the refs worked in the window -- and no group: not a
                # fact to reword, so it is passed over like the frame.
                at += len(prose_unsaid(slot, []))
                continue
            if prose_folds(slot, groups):
                if at < len(ww.prose):
                    facts.append(_fact(filled, ww, slot, True, at, groups[0], titles))
                    at += 1
                if at < len(ww.prose):
                    rest = groups[1:]
                    named = len(rest) <= rituals_prose_fold_names()
                    said = _fold_names(rest) if named else ""
                    facts.append(
                        {
                            "id": f"{ww.label}/{at}",
                            "worker": ww.name,
                            "slot": slot,
                            "first": False,
                            "floor": ww.prose[at],
                            "name": said,
                            "count": len(rest),
                            # A group named by a thread the read does not hold ("#999") says its ref.
                            "refs": [m.group(0) for m in re.finditer(rituals_dress_ref_regex(), said)],
                            "titles": {},
                            "kinds": {},
                        }
                    )
                    at += 1
                continue
            for i, g in enumerate(groups):
                if at >= len(ww.prose):
                    break
                facts.append(_fact(filled, ww, slot, i == 0, at, g, titles))
                at += 1
    return facts


def _fact(filled: Standup, ww: WorkWorker, slot: str, first: bool, at: int, g: WorkGroup, titles: dict) -> dict:
    """One group's facts for the dress: the prose sentence it replaces and what is true of it."""
    counts: dict[str, int] = {}
    for kind in _kinds():
        n = sum(
            1
            for r in g.refs
            if kind["label"] in filled._marks.get(r, [])
            or any(m.lower() == str(kind["type"]).lower() for m in filled._marks.get(r, []))
        )
        if n:
            counts[kind["many"]] = n
    return {
        "id": f"{ww.label}/{at}",
        "worker": ww.name,
        "slot": slot,
        "first": first,
        "floor": ww.prose[at],
        "name": g.name,
        "count": g.count,
        "refs": list(g.refs),
        "titles": {r: titles.get(r, "") for r in g.refs},
        "kinds": counts,
    }


DRESS_SYSTEM = (
    "You speak for the workers at a software team's daily standup. You are given a JSON list: one "
    "entry per sentence, each with the true sentence it replaces (floor) and the facts behind it "
    "(the group's name, its count, its refs, the items' titles, and kinds -- how many of the items "
    "are bugs or features). Re-say each floor sentence once, in the first person, in standup "
    "language: how a person says it at a standup, not how a ledger lists it.\n\n"
    "Rules. A sentence that breaks one is thrown away and the floor sentence is said instead:\n"
    "- Keep every ref exactly as written (an issue's #n, or a card's id), and add none.\n"
    "- Keep the group's name exactly as written, and its count.\n"
    "- Say no number, issue, milestone, card or name that the entry does not give.\n"
    '- Count by kind ("smashed two bugs") only with the count the entry\'s kinds give.\n'
    "- You may add a short, light remark about your own day that names no work.\n"
    "- One sentence per entry, on one line, no markdown.\n\n"
    "Words of the register you may use: {verbs}.\n\n"
    "Answer with only a JSON object mapping each entry's id to its sentence."
)


def dress_prompt(facts: list[dict]) -> tuple[str, str]:
    """(system, user) for the model: the register's words from the vocabulary's
    ``verbs`` family -- the only family it is shown -- and the facts. Pure."""
    verbs = ", ".join(f'"{v}"' for v in vocabulary().get("verbs") or [])
    return DRESS_SYSTEM.replace("{verbs}", verbs), json.dumps(facts, indent=1, ensure_ascii=False)


def _dress_reply(raw: str) -> dict[str, str]:
    """The model's answer as id -> sentence; {} when it is not that JSON object."""
    text = raw or ""
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return {}
    try:
        data = json.loads(text[start : end + 1])
    except ValueError:
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(k): v for k, v in data.items() if isinstance(v, str)}


def spoken_from(filled: Standup, facts: list[dict], reply: dict[str, str], model_name: str = "") -> Spoken:
    """Each worker's prose, with each sentence the guard lets through in the
    model's words and the prose sentence everywhere else. Pure."""
    by_id = {f["id"]: f for f in facts}
    out = Spoken(model=model_name)
    for ww in filled.work.workers:
        prose = list(ww.prose)
        for at in range(len(prose)):
            f = by_id.get(f"{ww.label}/{at}")
            if f is None:
                continue
            said = str(reply.get(f["id"]) or "").strip()
            if said and not dress_guard(f, said):
                prose[at] = said
                out.dressed += 1
            else:
                out.refused += 1
        out.workers.append(SpokenWorker(label=ww.label, prose=prose))
    return out


def dress_key(model_name: str, register: str, facts: list[dict]) -> str:
    """What a dressed reply is kept by: a hash of the model, the register and the
    facts. A changed fact, or a changed model, is a new key and is asked again. Pure."""
    data = {"model": model_name, "register": register, "facts": facts}
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def _keep_dressed(key: str, reply: dict) -> None:
    _DRESSED[key] = reply
    _DRESSED.move_to_end(key)
    while len(_DRESSED) > _DRESS_CACHE_SIZE:
        _DRESSED.popitem(last=False)


def _dressed_on_disk(key: str) -> dict[str, str] | None:
    """The reply kept on disk for ``key``, or None (a miss, or a file that is not one)."""
    kept = disk_cache.get_json(DRESS_CACHE, f"{key}.json")
    reply = (kept or {}).get("reply")
    if not isinstance(reply, dict):
        return None
    disk_cache.touch(DRESS_CACHE, f"{key}.json")  # seen now: what the prune ranks by
    return {str(k): v for k, v in reply.items() if isinstance(v, str)}


def clear_dressed() -> None:
    """Forget the replies kept in memory (what an agent restart forgets). The disk
    keeps its own: that is what survives the restart."""
    _DRESSED.clear()


async def dress_standup(filled: Standup) -> Spoken | None:
    """The dress, or None when there is nothing to dress or no model answered --
    then the stage speaks ``work``, the prose. A machine with no model key gets
    the profile's stated decline (logged), never a failed standup."""
    if not filled.tracker.ok:
        return None
    facts = dress_facts(filled)
    if not facts:
        return None
    model_name = model.model_id()
    key = dress_key(model_name, filled.register_, facts)
    reply = _DRESSED.get(key)
    if reply is None:
        reply = _dressed_on_disk(key)
        if reply is not None:
            _keep_dressed(key, reply)
    if reply is None:
        system, prompt = dress_prompt(facts)
        try:
            raw = await asyncio.wait_for(
                model.complete(prompt, system=system, max_tokens=min(4096, 200 + 150 * len(facts))),
                timeout=DRESS_TIMEOUT_SECONDS,
            )
        except model.ModelUnavailable as why:
            log_writer.write_log("INFO", f"agent{ROUTE}", f"dress declined: {why}")
            return None
        except Exception as exc:  # noqa: BLE001 -- the ritual happens anyway (principle 3)
            log_writer.write_log(
                "WARN", f"agent{ROUTE}", f"dress failed, the prose stands: {type(exc).__name__}: {exc}"
            )
            return None
        reply = _dress_reply(raw)
        _keep_dressed(key, reply)
        if disk_cache.put_json({"reply": reply}, DRESS_CACHE, f"{key}.json"):
            disk_cache.prune_folder(DRESS_CACHE)
    # The guard runs on a kept reply as on a fresh one (spoken_from): a kept
    # sentence the guard now refuses is the prose again.
    spoken = spoken_from(filled, facts, reply, model_name)
    log_writer.write_log("CMD", f"agent{ROUTE}", f"dressed={spoken.dressed} refused={spoken.refused}")
    return spoken


# -- The rendering ------------------------------------------------------------

_ENGLISH_DAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
_ENGLISH_MONTHS = (
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
)
# The .NET custom-format tokens the contract's dateFormat uses, invariant culture.
_DATE_TOKENS = re.compile(r"dddd|MMMM|yyyy|d")


def format_date(when: datetime, pattern: str) -> str:
    """``rituals.text.dateFormat`` ("dddd d MMMM yyyy") the way .NET's invariant
    culture renders it: English names, no zero-padding. Python's ``%A`` follows
    the process locale, which is why this does not use strftime."""
    sub = {
        "dddd": _ENGLISH_DAYS[when.weekday()],
        "MMMM": _ENGLISH_MONTHS[when.month - 1],
        "yyyy": f"{when.year:04d}",
        "d": str(when.day),
    }
    return _DATE_TOKENS.sub(lambda m: sub[m.group(0)], pattern)


def commits_said(n: int) -> str:
    """A commit count as the standup says it: ``text.commitOne`` or ``commitMany``, in digits."""
    t = rituals_text()
    return _fill(t["commitOne"] if n == 1 else t["commitMany"], {"n": str(n)})


def motion_said(item: SlotItem) -> str:
    """What an item's line adds to its slot: ``started`` when it began in the
    window, then its commits when it has any ("started, 2 commits", "3 commits").
    Closed under Yesterday and in progress under Today or Blockers are what the
    slot label already says, so a closed or in-progress item with no commits
    says nothing; "" too for an item that carries no motion (the queue's, or an
    older response's). Pure; the mirror of ``Get-P20StandupMotionText``."""
    t = rituals_text()
    motions = rituals_motions()
    if (item.motion or "") not in motions:
        return ""
    bits = []
    if item.motion == motions[1]:
        bits.append(t["motionStarted"])
    if item.commits:
        bits.append(commits_said(item.commits))
    return t["countsSeparator"].join(bits)


def counts_said(c: MotionCount) -> str:
    """One count as its non-zero parts -- closed, started, in progress, commits --
    joined, or ``text.countsNone`` when nothing moved. Commits the dates read
    could not date follow the commits as ``text.countsUndated``."""
    t = rituals_text()
    bits = [
        _fill(t[key], {"n": str(n)})
        for key, n in (
            ("countsClosed", c.closed),
            ("countsStarted", c.started),
            ("countsInProgress", c.inProgress),
        )
        if n
    ]
    if c.commits or c.undated:
        said = commits_said(c.commits)
        if c.undated:
            said += " " + _fill(t["countsUndated"], {"n": str(c.undated)})
        bits.append(said)
    return t["countsSeparator"].join(bits) if bits else t["countsNone"]


def render_counts(filled: Standup) -> str:
    """The counts line: the window's first day and what moved in it, in total.
    The brief's first line. Pure; the mirror of ``Format-P20StandupCounts``."""
    t = rituals_text()
    since = datetime.fromisoformat(filled.since)
    return _fill(
        t["countsTotal"],
        {"date": format_date(since, t["dateFormat"]), "counts": counts_said(filled.counts.total)},
    )


def render_standup(filled: Standup) -> str:
    """The text, LF-joined and LF-terminated, exactly as the golden files have it. Pure."""
    t = rituals_text()
    width = rituals_label_width()

    def row(label: str, body: str) -> str:
        return f"  {label.ljust(width)}  {body}"

    def numbered(item: SlotItem, suffix: str = "") -> str:
        # An issue is "#<number>"; a card is its id.
        ref = f"#{item.number}" if item.number is not None else (item.id or "")
        return f"{ref} {item.title}{suffix}"

    def moved(item: SlotItem, suffix: str = "") -> str:
        # A slot line says what moved after the ref, where it adds to the slot: "#141 (started, 2 commits) ...".
        said = motion_said(item)
        if not said:
            return numbered(item, suffix)
        ref = f"#{item.number}" if item.number is not None else (item.id or "")
        return _fill(t["itemMotion"], {"ref": ref, "motion": said, "title": item.title}) + suffix

    as_of = datetime.fromisoformat(filled.asOf)
    lines = [t["title"].replace("{date}", format_date(as_of, t["dateFormat"])), f'"{filled.chair.open}"', ""]
    if not filled.tracker.ok:
        lines += [row(t["tracker"], filled.tracker.reason), ""]
    else:
        lines.append(t["queueHeading"])
        if filled.queue.walk:
            lines += [row(t["walk"], numbered(i)) for i in filled.queue.walk]
        else:
            lines.append(f"  {t['queueEmpty']}")
        lines.append("")
        if not filled.workers:
            lines.append(t["noWorkers"])
        for w in filled.workers:
            lines.append(w.name)
            if w.empty:
                # Its made-up items, one row each, as a slot repeats its label.
                lines += [row(t["mug"], f'"{said}"') for said in (w.status or [w.excuse])]
                continue
            # The slot list is the ceremony's, declared in Config/ceremonies.json.
            for slot in ceremonies()[CEREMONY]["slots"]:
                items = getattr(w, slot)
                suffix = t["blockerSuffix"] if slot == "blockers" else ""
                if items:
                    lines += [row(t[slot], moved(i, suffix)) for i in items]
                else:
                    lines.append(row(t[slot], t[f"{slot}Empty"]))
        lines.append("")
        # Where a card and its issue disagree: said, one line each, never fixed.
        if filled.checks:
            lines += [row(t["check"], c) for c in filled.checks]
            lines.append("")
    lines.append(f'"{filled.chair.close}"')
    return "\n".join(lines) + "\n"


def render_work(filled: Standup) -> str:
    """The work grain's text, spoken as prose: the round of the room. The long
    form's frame -- the title, the chair's lines, the Tracker line when nothing
    answered -- with ONE line for the queue (its sentences, or queueEmpty when it
    has none), one per PRESENT worker (its name, then its turn: turnOpen, its
    sentences, turnClose; an idle worker's are its two made-up items, and so are
    an invented cast member's; an absent worker says nothing -- ``seat_room``),
    in seat order, and the chair's own
    turn last (``chairProse``: its own voice, in the same frame). An empty slot
    beside a filled one says its fixed line (``prose_unsaid``). LF-joined and LF-terminated. Pure; the mirror of
    ``Format-P20StandupWork``, held by the ``standup-prose-*.txt`` goldens."""
    t = rituals_text()
    width = rituals_label_width()

    as_of = datetime.fromisoformat(filled.asOf)
    lines = [t["title"].replace("{date}", format_date(as_of, t["dateFormat"])), f'"{filled.chair.open}"', ""]
    if not filled.tracker.ok:
        lines.append(f"  {t['tracker'].ljust(width)}  {filled.tracker.reason}")
    else:
        said = filled.work.queueProse
        lines.append(" ".join(said) if said else t["queueEmpty"])
        lines.append("")
        if not filled.work.workers:
            lines.append(t["noWorkers"])
        # The round, in seat order: an absent worker is not in it, so it has no
        # line, not even its name; an invented cast member has one.
        for ww in filled.work.workers:
            lines.append(f"{ww.name}: {' '.join(ww.prose)}")
        if filled.checks:
            lines.append("")
            lines += [f"{t['check']}: {c}" for c in filled.checks]
        # The chair's own turn, last, in the same frame and its own voice.
        if filled.work.chairProse:
            lines += ["", " ".join(filled.work.chairProse)]
    lines += ["", f'"{filled.chair.close}"']
    return "\n".join(lines) + "\n"


def render_brief(filled: Standup) -> str:
    """The chair's reading: a few lines, every one a count or a derived fact,
    no model. LF-joined and LF-terminated, every fixed word from ``rituals.text``.
    Pure; the mirror of ``Format-P20StandupBrief``, held by the ``.brief.txt`` goldens.

    An issues Space says its walks are all on one machine (every walk there is a verify-close) and
    "none in flight"; a cards Space says neither, and its walks wait on "you". A
    both Space reads as an issues Space, except that a card on its walk puts the
    walks on "you", and its card tile (labelled with the Space's slug) does not
    say "none in flight"; its Check lines follow the workers.
    It opens on the counts line (``render_counts``), and a worker's line adds its
    own started and commits; under a window wider than yesterday a worker's
    closes are ``countsClosed``, not "closed yesterday". With nothing waiting, the Next
    line is the suggestion's ``line`` when one is attached (suggest.py; D-AR7), else
    ``briefNextNone``. Its last line is the PM Corner's ``brief`` when one is attached
    (corner.py), after the Next line.
    With the tracker not ok the brief is the Tracker line and nothing else."""
    t = rituals_text()
    if not filled.tracker.ok:
        return f"{t['tracker']}: {filled.tracker.reason}\n"
    issues = filled.source in ("issues", "both")
    on_pc = issues and all(i.number is not None for i in filled.queue.walk)
    who = t["briefWhoPc"] if on_pc else t["briefWhoYou"]
    # A window wider than yesterday (?since=) says a worker's closes without "yesterday".
    as_of = datetime.fromisoformat(filled.asOf)
    widened = filled.since != previous_working_day_start(as_of).isoformat()
    counted = filled.counts.workers  # one per member, in the members' order
    # The counts line opens the reading: what moved in the window, in total.
    lines: list[str] = [render_counts(filled)]
    best_noun, best_count = "", 0
    for kind in ceremonies()[CEREMONY]["queue"]:
        count = len(getattr(filled.queue, kind))
        if not count:
            continue
        cap = kind[:1].upper() + kind[1:]
        noun = t[f"brief{cap}One"] if count == 1 else t[f"brief{cap}Many"]
        line = f"{t['queueHeading']}: {count} {noun}"
        if on_pc and kind == "walk":
            line += f", {t['briefAllPc']}"
        lines.append(line + ".")
        if count > best_count:
            best_noun, best_count = noun, count
    if not best_count:
        lines.append(t["queueEmpty"])
    for at, w in enumerate(filled.workers):
        if w.empty:
            lines.append(f"{w.name}: {t['briefWorkerNone']}.")
            continue
        blockers = len(w.blockers)
        opened = len(w.today) + blockers
        closed_key, none_key = ("countsClosed", "yesterdayEmpty") if widened else ("briefClosed", "briefClosedNone")
        bits = [
            t[closed_key].replace("{n}", str(len(w.yesterday))) if w.yesterday else t[none_key],
            t["briefOpen"].replace("{n}", str(opened)) if opened else t["briefOpenNone"],
        ]
        # What moved, the worker's own: how many of the open began in the window, and the commits.
        mine = counted[at] if at < len(counted) else MotionCount()
        if mine.started:
            bits.append(t["countsStarted"].replace("{n}", str(mine.started)))
        if mine.commits:
            bits.append(commits_said(mine.commits))
        if issues and not (filled.source == "both" and at == len(filled.workers) - 1):
            bits.append(t["briefInFlight"])
        if blockers > 1:
            bits.append(t["briefBlockers"].replace("{n}", str(blockers)))
        elif blockers == 1:
            bits.append(t["briefBlocker"].replace("{n}", "1"))
        else:
            bits.append(t["blockersEmpty"])
        lines.append(f"{w.name}: {', '.join(bits)}.")
    # The line the members end on is about the tracker: with no worker label the Space routes nothing,
    # whoever a card seats; the tracker's own count says so.
    if not filled.workers or (issues and not filled.tracker.workerLabels):
        lines.append(t["noWorkers"])
    elif issues:
        lines.append(t["briefInFlightUnknown"])
    lines += [f"{t['check']}: {c}" for c in filled.checks]
    if best_count:
        lines.append(t["briefNext"].replace("{kind}", best_noun).replace("{n}", str(best_count)).replace("{who}", who))
    elif filled.suggestion is not None and filled.suggestion.line:
        # D-AR7: the suggestion replaces only "nothing is waiting on you", and
        # only when nothing waits -- the queue's line above always wins.
        lines.append(filled.suggestion.line)
    else:
        lines.append(t["briefNextNone"])
    # The PM Corner (corner.py): the brief's last line, after the Next line,
    # wherever it is attached -- its own line, never in place of another.
    if filled.corner is not None and filled.corner.brief:
        lines.append(filled.corner.brief)
    return "\n".join(lines) + "\n"


# -- The gh layer -------------------------------------------------------------


def _now() -> datetime:
    """The local clock, offset-aware, to the second -- one seam for the tests."""
    return datetime.now().astimezone().replace(microsecond=0)


def _space_entry(cfg: dict, space: str) -> dict:
    """The Space's own entry in ``spaces[]`` -- the named one, else the active one."""
    slug = space or cfg.get("activeSpace", "")
    return next((s for s in cfg.get("spaces", []) or [] if s.get("slug") == slug), {}) or {}


def _issue_repo(issue: dict, repos: list[str]) -> str:
    """The repo an issue row came from, by its url; the first repo when the url does not say."""
    m = re.match(r"^https://github\.com/([^/]+/[^/]+)/issues/\d+", str(issue.get("url") or ""))
    found = m.group(1) if m else ""
    return next((r for r in repos if r.lower() == found.lower()), repos[0] if repos else "")


def _dated(
    filled: Standup,
    org: str,
    projects: list[dict],
    labels: list[dict],
    issues: list[dict],
    cards: list[dict],
    now: datetime,
    slug: str,
    name: str,
    since: str,
    refresh: bool,
) -> Standup:
    """The joined fill again, with the dates read: the commit dates of the
    hashes the fill counts and the timelines of the open issues with no card
    (``date_asks``). Nothing to ask, or a read that failed, keeps the fill as it
    is -- today's rule."""
    from ..core.config import tracker_repos
    from . import tracker as tracker_read

    hashes, numbers = date_asks(filled, cards)
    trailers = trailer_asks(filled, cards)
    if not hashes and not numbers and not trailers:
        return filled
    repos = tracker_repos(org, projects)
    by_number = {int(i.get("number", 0)): i for i in issues or []}
    numbers_by_repo: dict[str, list[int]] = {}
    for n in numbers:
        numbers_by_repo.setdefault(_issue_repo(by_number.get(n, {}), repos), []).append(n)
    prefix = rituals_worker_label_prefix()
    workers = [str(lab.get("name", "")) for lab in labels or [] if str(lab.get("description") or "").startswith(prefix)]
    commit_dates, issue_starts, messages, why = tracker_read.dates(
        repos, hashes, numbers_by_repo, workers, refresh, trailers=trailers
    )
    if why:
        return filled
    if not hashes and not numbers:
        # Trailers alone, with no date asked: the fill again with the messages
        # only, so every bullet still counts.
        commit_dates, issue_starts = None, None
    return fill_joined_standup(
        now,
        labels,
        issues,
        filled.tracker.model_dump(),
        cards,
        space=slug,
        space_name=name,
        window=since,
        commit_dates=commit_dates,
        issue_starts=issue_starts,
        size=filled.team.size,
        messages=messages,
    )


def standup_for(space: str = "", as_of: datetime | None = None, since: str = "", refresh: bool = False) -> Standup:
    """The whole standup for a Space -- the active one when ``space`` is "".
    ``since`` (yyyy-MM-dd) widens yesterday's window back to that day; a day that
    is not one, or is after today, is a 422 with ``since_refusal``'s reason.
    ``refresh`` reads the tracker again past the kept read (tracker.py)."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    now = as_of or _now()
    why = since_refusal(now, since)
    if why:
        raise HTTPException(status_code=422, detail=why)
    slug = space or cfg.get("activeSpace", "")
    source, reason = standup_source(org, status)
    # The room (spaces[].features.teamSize, the chair included): the fill reads it
    # through team_size, keeps every worker and marks who is present.
    size = (_space_entry(cfg, space).get("features") or {}).get("teamSize")
    cards: list[dict] = []
    name = ""
    if source in ("cards", "both"):
        # Imported here, not at the top: status.py is the ledger route's module.
        from ..core.config import card_types

        entry = _space_entry(cfg, space)
        type_names, prefixes = card_types()
        cards = read_cards(org_folder(entry), type_names, prefixes)
        name = str(entry.get("name") or "")
    if source == "cards":
        filled = fill_cards_standup(now, cards, space=slug, space_name=name, window=since, size=size)
    elif source == "both":
        labels, issues, state = read_tracker(org, status, projects, state="all", body=True, refresh=refresh)
        filled = fill_joined_standup(
            now, labels, issues, state, cards, space=slug, space_name=name, window=since, size=size
        )
        if filled.tracker.ok:
            filled = _dated(filled, org, projects, labels, issues, cards, now, slug, name, since, refresh)
    else:
        if source == "none":
            labels, issues, state = [], [], {"ok": False, "reason": reason}
        else:
            labels, issues, state = read_tracker(org, status, projects, state="all", body=True, refresh=refresh)
        filled = fill_standup(now, labels, issues, state, space=slug, window=since, size=size)
    # The suggestion (suggest.py): over the same read, before the brief renders it.
    from ..core.config import how_i_work, start_work_launch
    from .suggest import attach_suggestions, suggestions_on

    entry = _space_entry(cfg, space)
    on = suggestions_on(solitaire_enabled(), (entry.get("features") or {}).get("suggestions"))
    how = how_i_work(entry.get("org", ""), entry.get("howIWork"))["answer"]
    if on and source in ("cards", "both"):
        # Who "me" is: triage's one read (gh api user), once per standup, and only
        # where an issue read happened -- a cards Space has no assignee to compare.
        from .triage import _viewer

        viewer = _viewer(refresh) if source == "both" and filled.tracker.ok else ""
        attach_suggestions(
            filled,
            labels if source == "both" else [],
            issues if source == "both" else [],
            cards,
            how,
            True,
            str(cfg.get("commandPrefix") or ""),
            viewer,
            start_work_launch(),
        )
        # The PM Corner (corner.py): the suggestion's second surface, the same
        # switch, the same read and the same pick.
        from .corner import attach_corner

        attach_corner(
            filled,
            labels if source == "both" else [],
            issues if source == "both" else [],
            cards,
            True,
            str(cfg.get("commandPrefix") or ""),
            viewer,
            how,
            start_work_launch(),
        )
    # The Agenda (agenda.py): the page's tiles, over the same read. The viewer is
    # the suggestion's, asked only while it is on; "" leaves an assignee someone else's.
    from .agenda import build_agenda

    filled.agenda = build_agenda(
        filled,
        labels if source == "both" else [],
        issues if source == "both" else [],
        cards,
        viewer if on and source in ("cards", "both") else "",
        slug,
    )
    filled.text = render_standup(filled)
    filled.work.text = render_work(filled)
    filled.brief = render_brief(filled)
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"space={filled.space} source={filled.source} ok={int(filled.tracker.ok)} "
        f"workers={len(filled.workers)} walk={len(filled.queue.walk)} since={filled.since}",
    )
    return filled


ROUTE = rituals_route().removeprefix(API_PREFIX)


@api.get(ROUTE, response_model=Standup)
async def get_standup(space: str = "", since: str = "", refresh: int = 0):
    # space_scope raises the 404 for an unknown slug, exactly as /issue-report does;
    # a since that is not a day, or is after today, is a 422 (standup_for).
    # The tier probe and gh both block, so the whole read runs off the event loop.
    # ?refresh=1 reads the tracker again past the TTL (tracker.py).
    filled = await asyncio.to_thread(standup_for, space, None, since, bool(refresh))
    # The dress: after the read, on the loop -- the model call is async.
    filled.spoken = await dress_standup(filled)
    return filled
