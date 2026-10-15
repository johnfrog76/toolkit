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
that table, asserted from both suites. An Azure DevOps Space keeps its
``Tracker`` line (D-TA19).

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
from datetime import datetime, time, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, PrivateAttr

from ..ado import accounting
from ..core import log_writer, model
from ..core.config import API_PREFIX, REPO_ROOT, load_config, org_folder, tracker, tracker_repos
from ..core.consts import (
    folder_archive,
    folder_current,
    re_closed_stamp_date,
    rituals_ceremonies_file,
    rituals_dress_name_regex,
    rituals_dress_number_regex,
    rituals_dress_pronoun_regex,
    rituals_dress_ref_regex,
    rituals_label_width,
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
    status_code_review,
    status_done,
    status_in_progress,
)
from ..core.parsers import _parse_status_metadata, card_id
from ..core.tier import _resolve_tier

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
    # Which source filled it: "issues", "cards", or "none" when nothing answered.
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
    return SlotItem(
        number=int(issue.get("number", 0)), title=issue.get("title", "") or "", url=issue.get("url", "") or ""
    )


def fill_standup(
    as_of: datetime, labels: list[dict], issues: list[dict], tracker_state: dict, space: str = ""
) -> Standup:
    """The standup's slots, queue and vocabulary from labels and issues. Pure.

    ``as_of`` is offset-aware; every comparison is between offset-aware times.
    ``tracker_state`` is ``{"ok": bool, "reason": str}``; when it is not ok the
    labels and issues are not read -- the ritual is the chair's lines and the reason.
    """
    words = vocabulary()
    phrasebook, nothing = words["phrasebook"], words["nothing"]
    d = as_of.timetuple().tm_yday
    since = previous_working_day_start(as_of)
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
    # A `> GitHub:` thread is named by its issue's head: every issue in the read.
    threads = {str(int(i.get("number", 0))): str(i.get("title") or "") for i in issues or []}
    key_of: dict[str, tuple[str, str]] = {}

    walk: list[WalkItem] = []
    for issue in sorted(issues or [], key=lambda i: int(i.get("number", 0))):
        key_of[f"#{int(issue.get('number', 0))}|"] = work_key(issue.get("milestone"), issue.get("body"), "", threads)
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
    return out


# -- The second source: cards ------------------------------------------


def standup_source(address: str, status: str) -> tuple[str, str]:
    """(source, reason) for a Space. Pure; the mirror of ``Get-P20StandupSource``.

    ``issues``: a GitHub Space that is not local or archive. ``cards``: no
    tracker address, or a local or archive Space. ``none``: Azure DevOps -- the
    human team's board (D-TA19), with ``rituals.text.adoTracker`` as the reason.
    """
    kind = tracker(address)
    if kind == "ado":
        return "none", rituals_text()["adoTracker"]
    if kind == "none" or status in ("local", "archive"):
        return "cards", ""
    return "issues", ""


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


def read_cards(space_dir: Path, type_names: list[str], prefixes: list[str]) -> list[dict]:
    """The thin layer: a Space's ``current/`` and ``archive/`` as card rows --
    ``{file, folder, status, closed, title, id, path}``. A file with no id by the
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
                }
            )
    return rows


def fill_cards_standup(as_of: datetime, cards: list[dict], space: str = "", space_name: str = "") -> Standup:
    """The second fill, from card rows. Pure; the mirror of ``Invoke-P20StandupCardsFill``.

    yesterday: in ``archive/``, ``closed`` (a day) in [since's day, asOf's day].
    today: in ``current/``, In Progress or Code Review. queue.walk: in
    ``current/``, Code Review. An Active card is nowhere; so is an archived card
    with no Closed day. ONE worker, the engineer, named for the Space.
    Within a slot, file-name order.
    """
    words = vocabulary()
    phrasebook, nothing = words["phrasebook"], words["nothing"]
    d = as_of.timetuple().tm_yday
    since = previous_working_day_start(as_of)
    first, last = since.date().isoformat(), as_of.date().isoformat()
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
    worker = Worker(label=space, name=name)
    walk: list[WalkItem] = []
    seen: set[str] = set()
    key_of: dict[str, tuple[str, str]] = {}
    for card in sorted(cards or [], key=lambda c: str(c.get("file", ""))):
        file = str(card.get("file", ""))
        if file in seen:
            continue
        seen.add(file)
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
        out._marks[item.id or ""] = [str(card.get("type") or "")]
        if folder == folder_archive():
            day = str(card.get("closed") or "")[:10]
            if day and first <= day <= last:
                worker.yesterday.append(item)
            continue
        state = card.get("status")
        if state in (status_in_progress(), status_code_review()):
            worker.today.append(item)
        if state == status_code_review():
            walk.append(WalkItem(**item.model_dump(), worker=name))
    if not (worker.yesterday or worker.today or worker.blockers):
        worker.empty = True
        worker.excuse = nothing[d % len(nothing)]
    out.queue = Queue(walk=walk)
    out.workers = [worker]
    out.work = build_work(out, key_of)
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

_PLACEHOLDER = re.compile(r"\{(n|names|name|item|refs|ref|clause|lead|body)\}")


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
                    lines += [row(t[slot], numbered(i, suffix)) for i in items]
                else:
                    lines.append(row(t[slot], t[f"{slot}Empty"]))
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
    lines += ["", f'"{filled.chair.close}"']
    return "\n".join(lines) + "\n"


def render_brief(filled: Standup) -> str:
    """The chair's reading: a few lines, every one a count or a derived fact,
    no model. LF-joined and LF-terminated, every fixed word from ``rituals.text``.
    Pure; the mirror of ``Format-P20StandupBrief``, held by the ``.brief.txt`` goldens.

    An issues Space says its walks are all on one machine (every walk there is a verify-close) and
    "none in flight"; a cards Space says neither, and its walks wait on "you".
    With the tracker not ok the brief is the Tracker line and nothing else."""
    t = rituals_text()
    if not filled.tracker.ok:
        return f"{t['tracker']}: {filled.tracker.reason}\n"
    issues = filled.source == "issues"
    who = t["briefWhoPc"] if issues else t["briefWhoYou"]
    lines: list[str] = []
    best_noun, best_count = "", 0
    for kind in ceremonies()[CEREMONY]["queue"]:
        count = len(getattr(filled.queue, kind))
        if not count:
            continue
        cap = kind[:1].upper() + kind[1:]
        noun = t[f"brief{cap}One"] if count == 1 else t[f"brief{cap}Many"]
        line = f"{t['queueHeading']}: {count} {noun}"
        if issues and kind == "walk":
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
        bits = [
            t["briefClosed"].replace("{n}", str(len(w.yesterday))) if w.yesterday else t["briefClosedNone"],
            t["briefOpen"].replace("{n}", str(opened)) if opened else t["briefOpenNone"],
        ]
        if issues:
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
    if best_count:
        lines.append(t["briefNext"].replace("{kind}", best_noun).replace("{n}", str(best_count)).replace("{who}", who))
    else:
        lines.append(t["briefNextNone"])
    return "\n".join(lines) + "\n"


# -- The gh layer -------------------------------------------------------------

NOT_GITHUB_REASON = "This Space's tracker is not GitHub -- the standup reads a GitHub Space's issues."
NO_REPO_REASON = "This GitHub space names no repository."


def _read_tracker(org: str, status: str, projects: list[dict]) -> tuple[list[dict], list[dict], dict]:
    """(labels, issues, tracker state) for a Space. Never raises: a failure is a reason.

    Any repo that fails fails the whole read: a standup over half the repos would
    say "no blockers" when it does not know (principle 2).
    """
    if tracker(org) != "github":
        return [], [], {"ok": False, "reason": NOT_GITHUB_REASON}
    tier, _ = _resolve_tier(org, status)
    if tier != 1:
        return [], [], {"ok": False, "reason": f"The tracker is not reachable from here (tier {tier})."}
    repos = tracker_repos(org, projects)
    if not repos:
        return [], [], {"ok": False, "reason": NO_REPO_REASON}
    labels: dict[str, dict] = {}
    issues: list[dict] = []
    try:
        for repo in repos:
            rows, why = accounting._gh_labels(repo)
            if why:
                return [], [], {"ok": False, "reason": why}
            for r in rows:
                labels.setdefault(str(r.get("name", "")), r)
            rows, why = accounting._gh_issues(repo, True, "all", body=True)
            if why:
                return [], [], {"ok": False, "reason": why}
            issues += rows
    except Exception as exc:  # noqa: BLE001 -- a reader that raised is a tracker that did not answer
        return [], [], {"ok": False, "reason": f"The tracker read failed: {exc.__class__.__name__}: {exc}"}
    return list(labels.values()), issues, {"ok": True, "reason": ""}


def _now() -> datetime:
    """The local clock, offset-aware, to the second -- one seam for the tests."""
    return datetime.now().astimezone().replace(microsecond=0)


def _space_entry(cfg: dict, space: str) -> dict:
    """The Space's own entry in ``spaces[]`` -- the named one, else the active one."""
    slug = space or cfg.get("activeSpace", "")
    return next((s for s in cfg.get("spaces", []) or [] if s.get("slug") == slug), {}) or {}


def standup_for(space: str = "", as_of: datetime | None = None) -> Standup:
    """The whole standup for a Space -- the active one when ``space`` is ""."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    now = as_of or _now()
    slug = space or cfg.get("activeSpace", "")
    source, reason = standup_source(org, status)
    if source == "cards":
        # Imported here, not at the top: status.py is the ledger route's module.
        from ..ado.status import _card_types

        entry = _space_entry(cfg, space)
        type_names, prefixes = _card_types()
        cards = read_cards(org_folder(entry), type_names, prefixes)
        filled = fill_cards_standup(now, cards, space=slug, space_name=str(entry.get("name") or ""))
    else:
        if source == "none":
            labels, issues, state = [], [], {"ok": False, "reason": reason}
        else:
            labels, issues, state = _read_tracker(org, status, projects)
        filled = fill_standup(now, labels, issues, state, space=slug)
    filled.text = render_standup(filled)
    filled.work.text = render_work(filled)
    filled.brief = render_brief(filled)
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"space={filled.space} source={filled.source} ok={int(filled.tracker.ok)} "
        f"workers={len(filled.workers)} walk={len(filled.queue.walk)}",
    )
    return filled


ROUTE = rituals_route().removeprefix(API_PREFIX)


@api.get(ROUTE, response_model=Standup)
async def get_standup(space: str = ""):
    # space_scope raises the 404 for an unknown slug, exactly as /issue-report does.
    # The tier probe and gh both block, so the whole read runs off the event loop.
    filled = await asyncio.to_thread(standup_for, space)
    # The dress: after the read, on the loop -- the model call is async.
    filled.spoken = await dress_standup(filled)
    return filled
