"""The join: who is in the standup's room, from today's members, the Space's seats
and its sessions.

Pure functions over plain data and the model map (docs/modules/solitaire-agile.md,
"Where the room's members come from"):

- ``model_name`` -- a member's models -> the name its most recent one gives it.
- ``join_members`` -- today's members (the labelled workers, the members the
  cards name, the engineer), the seats reader's seats and the session reader's
  pairs, each as its reader returns it -> the members, each with ``models``,
  plus ``source`` and ``unknown``. It reads neither source itself.

Members are keyed by family, as today: two ids of one family are one member, and
an id the map does not know is a member of its own keyed by the id, never folded
into a family whose word it holds. Each source ADDS members; none takes one away
and none moves an item: the cards still decide who reports what.

The CLI's twin is ``Join-P20StandupMembers`` in Scripts/Standup-Rules.ps1, and one
table holds the two to each other: Tests/fixtures/rituals/standup-sessions.json,
its ``join`` and ``room`` sections, asserted from Tests/test_rituals.py and
``tkTestToolkit -Rituals``. Nothing calls it yet.
"""

from __future__ import annotations

from collections.abc import Sequence

from ..core.models import model_object, read_model_current

NAMINGS = ("today", "map")


def model_name(models: Sequence[dict], current: dict[str, str] | None = None) -> str:
    """The name a member's models give it: the ``name`` of its most recent known
    model -- the one the map's ``current`` block names for the family, when the
    member has that id, else the last of them in id order -- and "" when it has no
    known model. The map is read, never the id: a session carries no time the join
    may order by, so "most recent" is the map's word for it. The mirror of
    ``Get-P20StandupModelName``."""
    known = [m for m in models if m and m.get("known")]
    if not known:
        return ""
    now = ""
    family = str(known[0].get("family") or "").lower()
    for size, mid in (read_model_current() if current is None else current).items():
        if str(size).lower() == family:
            now = str(mid)
    for m in known:
        if now and m["id"] == now:
            return str(m["name"])
    return str(max(known, key=lambda m: m["id"])["name"])


def _key(model: dict) -> str:
    """A model's member key: its family, else its id as written, compared ignoring case."""
    return str(model.get("family") or model["id"]).lower()


def _copy(row: dict, in_record: bool) -> dict:
    out = dict(row)
    out["models"] = []
    out["session"] = False
    out["record"] = in_record
    return out


def _sorted_by_label(rows: list[dict]) -> list[dict]:
    """Label order, ordinal, the earlier first on a tie: the fills' own order."""
    return [r for _, _, r in sorted((str(r["label"]), i, r) for i, r in enumerate(rows))]


def join_members(
    labelled: Sequence[dict],
    members: Sequence[dict],
    engineer: dict | None,
    cards: Sequence[str | None] = (),
    seats: Sequence[dict] = (),
    sessions: Sequence[dict] = (),
    naming: str = "today",
) -> dict:
    """The join. Pure over its inputs and the model map.

    ``labelled`` are the labelled workers and ``members`` the members the cards
    name that no label routes to, as the fill builds them (a worker's fields as a
    dict); ``engineer`` the engineer's tile, or None. ``cards`` are the model ids
    the cards in play name (``resolve_card_agent``'s id); ``seats`` the seats
    reader's answer; ``sessions`` the session reader's pairs.

    ``naming`` is ``today`` (the default: a member is named as the room names it
    today -- a labelled worker by the tracker's word, a card member by its family
    with a capital, an unknown id as written, and a member the seats or sessions
    add the same way) or ``map``: every member made from a card, a seat or a
    session is named by its most recent model (``model_name``); a labelled worker
    keeps the tracker's word, the engineer the Space's name, and an unknown id is
    named as written.

    A key no member holds adds a member with nothing to report, made as a card
    member is (``card_member``); a card id adds nobody, because the cards already
    decided who is in today's room. Returns ``{members, source, unknown}``:
    ``members`` today's record and the added members in label order, then the
    engineer, each a copy of its input with ``models`` (one model object per
    distinct id, by id; ``sessionId`` the ordinally last session that shows it,
    else None), ``session`` (a session shows it) and ``record`` (false for a member
    only a seat or a session adds); ``source`` ``seats+sessions``, ``sessions``,
    ``seats`` or ``room``; ``unknown`` the ids among the models the map has no row
    for, sorted."""
    from .standup import card_member  # the one rule a card member is made by

    if naming not in NAMINGS:
        raise ValueError(f"naming is one of {', '.join(NAMINGS)}")
    current = read_model_current()
    team: list[dict] = []
    by_key: dict[str, dict] = {}
    named_by_model: set[str] = set()
    for row, kind in [(w, "label") for w in labelled] + [(w, "card") for w in members]:
        c = _copy(row, True)
        team.append(c)
        low = str(c["label"]).lower()
        if low not in by_key:
            by_key[low] = c
            if kind == "card":
                named_by_model.add(low)
    engineer_copy = _copy(engineer, True) if engineer is not None else None

    found: list[tuple[str, str, str | None]] = []
    added: list[dict] = []
    session_keys: set[str] = set()
    seat_count = session_count = 0

    def add(model: dict) -> None:
        k = _key(model)
        if k in by_key:
            return
        made = card_member(str(model.get("family") or model["id"]), as_written=not model["known"]).model_dump()
        made["empty"] = True
        c = _copy(made, False)
        by_key[k] = c
        named_by_model.add(k)
        added.append(c)

    for seat in seats:
        spec = seat.get("model", seat) if isinstance(seat, dict) else None
        model = model_object((spec or {}).get("id"), None)
        if model is None:
            continue
        seat_count += 1
        add(model)
        found.append((_key(model), model["id"], None))
    for pair in sessions:
        model = model_object(pair.get("id"), pair.get("sessionId"))
        if model is None:
            continue
        session_count += 1
        add(model)
        session_keys.add(_key(model))
        found.append((_key(model), model["id"], model["sessionId"]))
    for mid in cards:
        model = model_object(mid, None)
        if model is not None:
            found.append((_key(model), model["id"], None))

    ids: dict[str, dict[str, str | None]] = {}
    for k, mid, sid in found:
        if k not in by_key:
            continue
        last = ids.setdefault(k, {}).setdefault(mid, None)
        if sid and (last is None or sid > last):
            ids[k][mid] = sid
    unknown: set[str] = set()
    for k, seen in ids.items():
        member = by_key[k]
        models = [model_object(mid, seen[mid]) for mid in sorted(seen)]
        member["models"] = models
        unknown.update(m["id"] for m in models if not m["known"])
        if k in session_keys:
            member["session"] = True
        if naming == "map" and k in named_by_model:
            named = model_name(models, current) or (models[0]["id"] if models else "")
            if named:
                member["name"] = named

    if seat_count and session_count:
        source = "seats+sessions"
    elif session_count:
        source = "sessions"
    elif seat_count:
        source = "seats"
    else:
        source = "room"
    out = _sorted_by_label(team + added) + ([engineer_copy] if engineer_copy is not None else [])
    return {"members": out, "source": source, "unknown": sorted(unknown)}
