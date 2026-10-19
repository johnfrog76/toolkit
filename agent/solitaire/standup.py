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
brief opens on that counts line. ``window_start`` widens yesterday's lower bound
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
from ..core import log_writer, model
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
    rituals_route,
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
from ..core.parsers import _parse_status_metadata, card_billable, card_id
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


class Chair(BaseModel):
    open: str = ""
    close: str = ""


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
    # inProgress (open). An issue with no card is closed or inProgress; a card,
    # or the card an issue's number names, is started when its **Started:** day,
    # else its **Created:** day, falls in the window. ``commits`` is the distinct
    # hashes of that card's ``- <hash>`` bullets; 0 with no card.
    motion: str = ""
    commits: int = 0


class WalkItem(SlotItem):
    worker: str = ""  # the worker's NAME ("<worker>"), "" when no label routes it


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
    # The wire name is historical: it is the empty worker's one status sentence,
    # from the `nothing` family, not an excuse. Both renderers and every golden read it.
    excuse: str = ""


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
    # The prose: the worker's sentences, in order -- one a group, then
    # "Nothing blocked." when it has something to say and no blockers. Empty for
    # a worker with nothing, who is its status sentence.
    prose: list[str] = []


class Work(BaseModel):
    # The work grain (D-TA20): the same standup, grouped -- the queue's
    # kinds and each worker's slots -- and its text, one line a worker.
    queue: WorkQueue = WorkQueue()
    workers: list[WorkWorker] = []
    # The prose: the queue's sentences, one a group, kind by kind.
    queueProse: list[str] = []
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
    label: str = ""
    name: str = ""
    closed: int = 0
    started: int = 0
    inProgress: int = 0
    commits: int = 0


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
    # What kind each item is: ref -> its label names (an issue) or its
    # type (a card), read against the ceremony's kinds. Not served.
    _marks: dict[str, list[str]] = PrivateAttr(default_factory=dict)


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
    # An issue alone says closed or in progress: the read has no fact that
    # marks when its work began. A card joined to it may say started.
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


def fill_standup(
    as_of: datetime, labels: list[dict], issues: list[dict], tracker_state: dict, space: str = "", window: str = ""
) -> Standup:
    """The standup's slots, queue and vocabulary from labels and issues. Pure.

    ``as_of`` is offset-aware; every comparison is between offset-aware times.
    ``tracker_state`` is ``{"ok": bool, "reason": str}``; when it is not ok the
    labels and issues are not read -- the ritual is the chair's lines and the reason.
    ``window`` is ``since``'s day (``window_start``); "" is the previous working day.
    """
    words = vocabulary()
    phrasebook, nothing = words["phrasebook"], words["nothing"]
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
    for i, (label, _name) in enumerate(routes):
        w = workers[label]
        if not (w.yesterday or w.today or w.blockers):
            w.empty = True
            w.excuse = nothing[(d + i) % len(nothing)]
    out.workers = [workers[label] for label, _ in routes]
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
    m = re.search(r"(?m)^" + re.escape(stamp) + r"\s*(\d{4}-\d{2}-\d{2})", content or "")
    return m.group(1) if m else None


def read_cards(space_dir: Path, type_names: list[str], prefixes: list[str]) -> list[dict]:
    """The thin layer: a Space's ``current/`` and ``archive/`` as card rows --
    ``{file, folder, status, closed, title, id, path, type, body, billable, begun, commits}``. A file with no id by the
    one id rule is not a card and is skipped. State is the parser's rule; a card
    in ``archive/`` is Done and carries its Closed stamp's day."""
    rows: list[dict] = []
    closed_rx = re_closed_stamp_date()
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
    as_of: datetime, cards: list[dict], label: str, name: str, marks: dict, since: datetime | None = None
) -> tuple[Worker, list[WalkItem], dict[str, tuple[str, str]], dict[str, list[str]]]:
    """Cards (already in play) -> one worker's slots, its walk items, the
    work keys and each item's hashes. yesterday: in ``archive/``, ``closed`` (a
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
        hashes[f"{item.id}|{item.path}"] = card_hashes(card)
        item.commits = len(hashes[f"{item.id}|{item.path}"])
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
    return worker, walk, key_of, hashes


def fill_cards_standup(
    as_of: datetime, cards: list[dict], space: str = "", space_name: str = "", window: str = ""
) -> Standup:
    """The second fill, from card rows. Pure; the mirror of ``Invoke-P20StandupCardsFill``.

    The cards in play (``cards_in_play``: a not-billable card is left out) on
    ONE worker, the engineer, named for the Space, by ``_cards_tile``'s mapping.
    Within a slot, file-name order.
    """
    words = vocabulary()
    phrasebook, nothing = words["phrasebook"], words["nothing"]
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
    )
    worker, walk, key_of, hashes = _cards_tile(as_of, cards_in_play(cards), space, name, out._marks, since)
    if not (worker.yesterday or worker.today or worker.blockers):
        worker.empty = True
        worker.excuse = nothing[d % len(nothing)]
    out.queue = Queue(walk=walk)
    out.workers = [worker]
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
#     named for it, by the cards fill's mapping, after the worker tiles, and
#     only when it has something to say. Its Code Review cards follow the
#     issues on the walk.
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
) -> Standup:
    """The issues fill, joined with the cards on the id. Pure; the mirror of
    ``Invoke-P20StandupJoinedFill``. With the tracker not answering it is the
    issues fill as it stands: the chair's lines and the reason. A joined card
    gives its issue's row its commits, and says started for an open one whose
    card began in the window."""
    out = fill_standup(as_of, labels, issues, tracker_state, space=space, window=window)
    if not out.tracker.ok:
        return out
    out.source = "both"
    t = rituals_text()
    since = datetime.fromisoformat(out.since)
    first, last = since.date().isoformat(), as_of.date().isoformat()
    _closed, started, in_progress = rituals_motions()
    hashes: dict[str, list[str]] = {}
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
        hashes[f"#{number}|"] = card_hashes(card)
        begun = card_begun_in(card, first, last)
        for it in issue_items:
            if it.number == number:
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

    tile, walk, card_keys, tile_hashes = _cards_tile(as_of, alone, space, space_name or space, out._marks, since)
    if tile.yesterday or tile.today or tile.blockers:
        out.workers.append(tile)
    out.queue.walk.extend(walk)
    out.work = build_work(out, {**issue_keys(issues), **card_keys})
    out.counts = standup_counts(out, {**hashes, **tile_hashes})
    return out


def standup_counts(filled: Standup, hashes: dict[str, list[str]]) -> Counts:
    """What moved in the window, per worker (in the workers' order) and in total:
    each slot item by its motion, and the distinct hashes its card threads --
    ``hashes`` maps an item's ``<ref>|<path>`` to them. A hash is counted once
    per worker and once in the total, however many cards thread it; an issue
    with no card, and a card with no bullets, count none. Pure; the mirror of
    ``Get-P20StandupCounts``."""
    closed, started, in_progress = rituals_motions()
    out = Counts()
    every: list[str] = []
    for w in filled.workers:
        c = MotionCount(label=w.label, name=w.name)
        mine: list[str] = []
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
        c.commits = len(mine)
        every += [h for h in mine if h not in every]
        out.workers.append(c)
        out.total.closed += c.closed
        out.total.started += c.started
        out.total.inProgress += c.inProgress
    out.total.commits = len(every)
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


def build_work(filled: Standup, key_of: dict[str, tuple[str, str]]) -> Work:
    """The filled standup's work grain, text left empty. ``key_of`` maps an item's
    ``<ref>|<path>`` to its ``work_key``. Pure."""
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
    for w in filled.workers:
        slots: dict[str, list[WorkGroup]] = {}
        prose: list[str] = []
        for slot in cer["slots"]:
            slots[slot], said = groups(getattr(w, slot), slot)
            prose += said
        workers.append(WorkWorker(label=w.label, name=w.name, prose=prose_close(prose, slots), **slots))
    return Work(queue=WorkQueue(**queue), workers=workers, queueProse=queue_prose)


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
# A worker with something to say and no blockers ends on text.proseBlockersNone.
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
    """A worker's sentences, closed: "Nothing blocked." after them when there are
    any and the blockers slot has none. A worker with nothing says nothing."""
    if said and not slots.get("blockers"):
        return said + [rituals_text()["proseBlockersNone"]]
    return said


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
# Dressed replies kept in memory, by a hash of the facts: the same day is dressed once.
_DRESS_CACHE_SIZE = 64
_DRESSED: OrderedDict[str, dict] = OrderedDict()

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
    group -- not the closing proseBlockersNone, not the queue's sentences (they
    are the chair's, not a worker's first person), not an excuse (the empty worker reports "nothing").
    A folded sentence (prose_folds) is one entry: its name is the names it says
    (none past proseFoldNames), its count the groups', and its refs only what
    those names spell. Pure."""
    cer = ceremonies()[CEREMONY]
    by_label = {w.label: w for w in filled.workers}
    facts: list[dict] = []
    for ww in filled.work.workers:
        w = by_label.get(ww.label)
        if w is None or w.empty:
            continue
        at = 0
        for slot in cer["slots"]:
            items = getattr(w, slot)
            titles = {(f"#{i.number}" if i.number is not None else (i.id or "")): i.title for i in items}
            groups = getattr(ww, slot)
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
    key = hashlib.sha256(json.dumps({"model": model_name, "facts": facts}, sort_keys=True).encode("utf-8")).hexdigest()
    reply = _DRESSED.get(key)
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
        _DRESSED[key] = reply
        while len(_DRESSED) > _DRESS_CACHE_SIZE:
            _DRESSED.popitem(last=False)
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
    joined, or ``text.countsNone`` when nothing moved."""
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
    if c.commits:
        bits.append(commits_said(c.commits))
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
                lines.append(row(t["mug"], f'"{w.excuse}"'))
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
    """The work grain's text, spoken as prose: the long form's frame --
    the title, the chair's lines, the Tracker line when nothing answered -- with ONE
    line for the queue (its sentences, or queueEmpty when it has none) and one per
    worker (its name, then its sentences). An empty slot says nothing; an empty
    worker is its status sentence. LF-joined and LF-terminated. Pure; the mirror of
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
        if not filled.workers:
            lines.append(t["noWorkers"])
        grained = {w.label: w for w in filled.work.workers}
        for w in filled.workers:
            if w.empty:
                lines.append(f'{w.name}: "{w.excuse}"')
                continue
            ww = grained.get(w.label)
            lines.append(f"{w.name}: {' '.join(ww.prose if ww else [])}")
        if filled.checks:
            lines.append("")
            lines += [f"{t['check']}: {c}" for c in filled.checks]
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
    closes are ``countsClosed``, not "closed yesterday".
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
    counted = {c.label: c for c in filled.counts.workers}
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
    for w in filled.workers:
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
        mine = counted.get(w.label) or MotionCount()
        if mine.started:
            bits.append(t["countsStarted"].replace("{n}", str(mine.started)))
        if mine.commits:
            bits.append(commits_said(mine.commits))
        if issues and not (filled.source == "both" and w.label == filled.space):
            bits.append(t["briefInFlight"])
        if blockers > 1:
            bits.append(t["briefBlockers"].replace("{n}", str(blockers)))
        elif blockers == 1:
            bits.append(t["briefBlocker"].replace("{n}", "1"))
        else:
            bits.append(t["blockersEmpty"])
        lines.append(f"{w.name}: {', '.join(bits)}.")
    if not filled.workers:
        lines.append(t["noWorkers"])
    elif issues:
        lines.append(t["briefInFlightUnknown"])
    lines += [f"{t['check']}: {c}" for c in filled.checks]
    if best_count:
        lines.append(t["briefNext"].replace("{kind}", best_noun).replace("{n}", str(best_count)).replace("{who}", who))
    else:
        lines.append(t["briefNextNone"])
    return "\n".join(lines) + "\n"


# -- The gh layer -------------------------------------------------------------


def _now() -> datetime:
    """The local clock, offset-aware, to the second -- one seam for the tests."""
    return datetime.now().astimezone().replace(microsecond=0)


def _space_entry(cfg: dict, space: str) -> dict:
    """The Space's own entry in ``spaces[]`` -- the named one, else the active one."""
    slug = space or cfg.get("activeSpace", "")
    return next((s for s in cfg.get("spaces", []) or [] if s.get("slug") == slug), {}) or {}


def standup_for(space: str = "", as_of: datetime | None = None, since: str = "") -> Standup:
    """The whole standup for a Space -- the active one when ``space`` is "".
    ``since`` (yyyy-MM-dd) widens yesterday's window back to that day; a day that
    is not one, or is after today, is a 422 with ``since_refusal``'s reason."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    now = as_of or _now()
    why = since_refusal(now, since)
    if why:
        raise HTTPException(status_code=422, detail=why)
    slug = space or cfg.get("activeSpace", "")
    source, reason = standup_source(org, status)
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
        filled = fill_cards_standup(now, cards, space=slug, space_name=name, window=since)
    elif source == "both":
        labels, issues, state = read_tracker(org, status, projects, state="all", body=True)
        filled = fill_joined_standup(now, labels, issues, state, cards, space=slug, space_name=name, window=since)
    else:
        if source == "none":
            labels, issues, state = [], [], {"ok": False, "reason": reason}
        else:
            labels, issues, state = read_tracker(org, status, projects, state="all", body=True)
        filled = fill_standup(now, labels, issues, state, space=slug, window=since)
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
async def get_standup(space: str = "", since: str = ""):
    # space_scope raises the 404 for an unknown slug, exactly as /issue-report does;
    # a since that is not a day, or is after today, is a 422 (standup_for).
    # The tier probe and gh both block, so the whole read runs off the event loop.
    filled = await asyncio.to_thread(standup_for, space, None, since)
    # The dress: after the read, on the loop -- the model call is async.
    filled.spoken = await dress_standup(filled)
    return filled
