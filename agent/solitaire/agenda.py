"""The Agenda: the standup's two questions as tiles (docs/modules/solitaire-agile.md, "The page").

The Team Agile page opens on it. Two lanes, both read from the same read the
standup made -- no second ``gh`` call, no second folder walk:

- ``moved`` -- what moved since the standup's window began: the items in every
  worker's yesterday slot (an issue closed, a card archived in the window), in
  the workers' order, once each.
- ``waiting`` -- what is waiting on you: a card in ``current/`` that is Active
  (nothing started) or in Code Review, and an open issue that is routed (someone
  has it, by the triage rule, and it is not someone else's) or on the queue. An In
  Progress card is in somebody's hands, and is not here; a ``backlog/`` card is
  never read. The suggestion's order (``suggest``), so the first is the pick
  wherever the pick is on the Agenda; then what the rule sets aside as waiting or in
  flight, in the joined list's order.

Each item carries what its tile draws and nothing it does not: the ref, title and
link, the card's lane (``consts.json`` ``status``; "" for an issue with no card),
the day its one fact line is dated with (``yyyy-MM-dd``, "" when the record has
none), whether its one action is a review, and the card's cover and progress.

The agent's alone, like ``spoken``: the CLI's ``Standup`` prints text, and
``Standup -AsJson`` has no such key. Pure; ``standup_for`` attaches it.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from ..core.assets import card_images
from ..core.consts import (
    folder_current,
    stamp_created,
    stamp_review,
    status_code_review,
    status_in_progress,
)
from ..core.parsers import _parse_status_metadata
from .standup import Agenda, AgendaItem, Standup, _stamp_day, _when, cards_in_play
from .suggest import queue_refs, suggest, suggest_items


def _local_day(stamp, as_of: datetime) -> str:
    """An ISO instant (gh's closedAt, createdAt) as the day it was in the standup's offset."""
    when = _when(stamp)
    if when is None:
        return ""
    if when.tzinfo is not None and as_of.tzinfo is not None:
        when = when.astimezone(as_of.tzinfo)
    return when.date().isoformat()


def _face(card: dict | None, space: str) -> dict:
    """What the board's face draws for a card: its cover and its progress."""
    if not card:
        return {}
    body = str(card.get("body") or "")
    meta = _parse_status_metadata(body)
    path = str(card.get("path") or "")
    images = card_images(body, Path(path), space) if path else {"cover": None}
    return {
        "cover": images.get("cover"),
        "checked": meta["checked"],
        "total": meta["total"],
        "progress": meta["progress"],
        "path": path,
        "file": str(card.get("file") or "") if card.get("folder") == folder_current() else "",
    }


def _card_day(card: dict) -> str:
    """The day a waiting card's fact line names: in review since its **Review:** day,
    active since its **Created:** day; "" when the card carries neither."""
    body = str(card.get("body") or "")
    if card.get("status") == status_code_review():
        return _stamp_day(body, stamp_review()) or ""
    return _stamp_day(body, stamp_created()) or ""


def build_agenda(
    filled: Standup,
    labels: list[dict],
    issues: list[dict],
    cards: list[dict],
    viewer: str = "",
    space: str = "",
) -> Agenda:
    """The Agenda over the standup's own read. Pure but for the cover's file check.

    ``issues`` is the tracker's read ([] on a cards Space), ``cards`` the
    ``read_cards`` rows; ``viewer`` the signed-in gh login, "" when it was not asked
    (then every assignee is someone else's, as the suggestion reads it)."""
    out = Agenda()
    if not filled.tracker.ok:
        return out
    in_play = cards_in_play(cards)
    by_path = {str(c.get("path") or ""): c for c in in_play}
    by_number = {int(i.get("number", 0)): i for i in issues or []}
    link_of = {link.number: by_path.get(link.path) for link in filled.links}

    seen: set[str] = set()
    for worker in filled.workers:
        for it in worker.yesterday:
            ref = f"#{it.number}" if it.number is not None else (it.id or "")
            if not ref or ref in seen:
                continue
            seen.add(ref)
            if it.number is not None:
                card = link_of.get(it.number)
                day = _local_day((by_number.get(it.number) or {}).get("closedAt"), datetime.fromisoformat(filled.asOf))
                kind = "issue"
            else:
                card = by_path.get(it.path)
                day = str((card or {}).get("closed") or "")[:10]
                kind = "card"
            face = _face(card, space)
            out.moved.append(
                AgendaItem(
                    ref=ref,
                    number=it.number,
                    id=it.id if it.number is None else None,
                    kind=kind,
                    title=it.title,
                    url=it.url,
                    lane=str((card or {}).get("status") or "") if card else "",
                    day=day,
                    **{"path": it.path, **face},
                )
            )

    as_of = datetime.fromisoformat(filled.asOf)
    waiting = queue_refs(filled)
    items = suggest_items(labels, issues, cards, waiting, viewer)
    current = {str(c.get("id") or ""): c for c in in_play if str(c.get("folder", "")) == folder_current()}
    kept: list[dict] = []
    for item in items:
        if item.get("billable", True) is False or item.get("lane") == status_in_progress():
            continue
        if item["kind"] == "issue":
            card = current.get(str(item["number"]))
            who = str(item.get("who") or "")
            routed = bool(who) and not who.startswith("@")
            if not (routed or item.get("waiting") or (card and card.get("status") == status_code_review())):
                continue
        kept.append(item)

    candidates, _excluded = suggest(kept, "alone")
    first = [c["ref"] for c in candidates]
    rest = [i["ref"] for i in kept if i["ref"] not in first]
    by_ref = {i["ref"]: i for i in kept}
    for ref in first + rest:
        item = by_ref[ref]
        if item["kind"] == "issue":
            issue = by_number.get(int(item["number"])) or {}
            card = current.get(str(item["number"]))
            lane = str(card.get("status") or "") if card else ""
            day = _card_day(card) if card else _local_day(issue.get("createdAt"), as_of)
            url = str(issue.get("url") or "")
        else:
            card = current.get(str(item["id"]))
            lane = str(item.get("lane") or "")
            day = _card_day(card) if card else ""
            url = ""
        out.waiting.append(
            AgendaItem(
                ref=ref,
                number=item.get("number"),
                id=item.get("id"),
                kind=item["kind"],
                title=str(item.get("title") or ""),
                url=url,
                lane=lane,
                day=day,
                review=bool(item.get("waiting")) or lane == status_code_review(),
                **_face(card, space),
            )
        )
    return out
