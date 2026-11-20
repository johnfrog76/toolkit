"""The model map: what a card's ``**Agent:**`` line names.

A card worked by an agent carries the model's id on its ``**Agent:**`` line
(``parsers.card_agent``). The id is what the price table and the usage records
use, so a card can be joined to what its work cost; everything a reader SHOWS
about it -- the provider, the family, the display name -- comes from one map, the
file ``consts.json`` names as ``models.file``, read by every half.

The id is never parsed. ``claude-sonnet-5-5`` is family ``sonnet`` because its
row says so, not because the word is in it, and an id with no row reads as
written: ``known`` is false, the name is the id, and there is no provider or
family to guess. Adding a model is one row in the map.

The CLI's mirror is ``Get-P20ModelInfo`` in ``Scripts/Get-PromptFileStatus.ps1``,
and ``Tests/fixtures/parsers/models.json`` holds the two to one table.
"""

from __future__ import annotations

import functools
import json
from pathlib import Path

from .consts import CONSTS_PATH, models_file


def _map_file() -> dict:
    """The whole model map file; {} when it is missing, unreadable or not a JSON object."""
    path = CONSTS_PATH.parent / models_file()
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


@functools.lru_cache(maxsize=1)
def model_map() -> dict[str, dict]:
    """The map's rows by id, read once per process from the package's model map.

    A map that is missing, unreadable or not the expected JSON reads as EMPTY, so
    every id is unknown and reads as written -- a card is never refused for it."""
    rows = _map_file().get("models")
    return rows if isinstance(rows, dict) else {}


def model_info(model_id: str | None) -> dict:
    """What the map says about a model id: ``{id, known, provider, family, name}``.

    A known id takes its provider, family and display name from its row. An
    unknown one is reported, never guessed at: ``known`` false, ``name`` the id
    as written, ``provider`` and ``family`` None."""
    mid = "" if model_id is None else str(model_id)
    row = model_map().get(mid)
    if not isinstance(row, dict):
        return {"id": mid, "known": False, "provider": None, "family": None, "name": mid}
    return {
        "id": mid,
        "known": True,
        "provider": row.get("provider"),
        "family": row.get("family"),
        "name": row.get("name") or mid,
    }


def read_model_map(path=None) -> dict[str, dict]:
    """The map's rows by id, for the readers that must never throw: a missing or
    unreadable file reads as an empty map, so every id is unknown and no trailer
    names a model. ``path`` defaults to the package's model map. The mirror of
    ``Get-P20ModelMap``."""
    target = CONSTS_PATH.parent / models_file() if path is None else path
    try:
        rows = json.loads(Path(target).read_text(encoding="utf-8-sig")).get("models")
    except (OSError, ValueError, AttributeError):
        return {}
    return rows if isinstance(rows, dict) else {}


def model_by_co_author(name: str | None, models: dict[str, dict] | None = None) -> str | None:
    """The model id whose row's ``coAuthor`` is this trailer name -- both trimmed,
    compared ignoring case -- or None.

    A lookup, never a parse: a name no row carries (a person, a model the map
    does not know) names no model, and a row with no ``coAuthor`` is never named
    by a trailer. ``models`` is the map; None reads the shipped one. The mirror of
    ``Get-P20ModelByCoAuthor``; ``Tests/fixtures/parsers/agent-source.json`` holds
    the two to one table."""
    want = (name or "").strip().lower()
    if not want:
        return None
    rows = read_model_map() if models is None else models
    for mid, row in rows.items():
        co = row.get("coAuthor") if isinstance(row, dict) else None
        if co is not None and str(co).strip().lower() == want:
            return mid
    return None


def read_model_current(path=None) -> dict[str, str]:
    """The map's top-level ``current`` block -- a worker size (a family alias:
    ``sonnet``, ``opus``) -> the model id it resolves to today. Absent, missing or
    unreadable reads as empty, never a throw. ``parsers.resolve_card_agent``'s
    ``assigned`` source reads it. The mirror of ``Get-P20ModelCurrent``."""
    target = CONSTS_PATH.parent / models_file() if path is None else path
    try:
        block = json.loads(Path(target).read_text(encoding="utf-8-sig")).get("current")
    except (OSError, ValueError, AttributeError):
        return {}
    return {str(k): str(v) for k, v in block.items()} if isinstance(block, dict) else {}


def current_model(family: str | None) -> str | None:
    """The id a worker size (a family: ``sonnet``, ``opus``) resolves to when a card
    is routed to it -- the map's ``current`` entry, matched ignoring case -- else
    None: a size the map has no entry for, or a map that is missing or broken.
    A size is a family alias, not an id, so this is the one place it becomes one.
    The CLI's mirror is ``Get-P20ModelForSize``."""
    want = ("" if family is None else str(family)).strip().lower()
    current = _map_file().get("current")
    if not want or not isinstance(current, dict):
        return None
    for size, mid in current.items():
        if str(size).lower() == want and isinstance(mid, str) and mid:
            return mid
    return None
