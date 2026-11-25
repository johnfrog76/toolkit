"""The seats reader: who the org chart seats in a Space, as model objects.

The chart is the org reader's answer (``org.py``, ``read_org_chart`` /
``find_org_chart``), its validity verdict and all; nothing here reads or checks
the org file again. From the chart's tree in use, a seat counts for a Space when
its ``space`` is the Space's slug exactly, it names a ``model`` and it names no
``person``. A seat with no ``space`` (an org-wide seat), another Space's seat, a
vacant seat -- the chart's own rule: a seat that names no model is vacant, and
its position's ``defaultModel`` does not fill it -- a person's seat and a pool
add nobody.

A seat's ``model`` is free text, read by lookup and never parsed
(``seat_model_id``): an id the model map has a row for, matched exactly; else a
key of the map's ``current`` block, matched ignoring case as every worker size
is (``current_model``: ``opus`` is ``current.opus``'s id); else the text as
written, which ``model_object`` names as an id the map does not know.

What leaves: ``{"seat", "position", "model"}`` per seat, ``model`` the model
object with a null ``sessionId``, in the chart's own order (its positions in
tree order, each position's seats in file order), and nothing else. A seat's
``machine`` and ``person`` are read here and dropped.

The CLI's twin is ``Get-P20StandupOrgSeats`` in Scripts/Standup-Rules.ps1, and
one table holds the two to each other: Tests/fixtures/rituals/standup-sessions.json,
its ``seats`` section, asserted from Tests/test_rituals.py and
``tkTestToolkit -Rituals``. It is its own module, not part of ``sessions.py``,
because it reads the org chart and no session file: the two readers share
nothing but the model object. Nothing here raises, and nothing calls it yet.
"""

from __future__ import annotations

from typing import Any

from ..core.models import current_model, model_info, model_object


def seat_model_id(model: str | None) -> str:
    """The model id a seat's free-text ``model`` names; '' for no text."""
    text = "" if model is None else str(model).strip()
    if not text:
        return ""
    if model_info(text)["known"]:
        return text
    return current_model(text) or text


def space_seats(chart: dict | None, space: str | None) -> list[dict]:
    """A Space's seats in an org chart response, as ``{seat, position, model}``.
    Pure over the chart and the model map."""
    tree = chart.get("tree") if isinstance(chart, dict) else None
    if not space or not isinstance(tree, dict):
        return []
    out: list[dict] = []
    for position in tree.get("positions") or []:
        if not isinstance(position, dict):
            continue
        for seat in position.get("seats") or []:
            if not isinstance(seat, dict) or seat.get("space") != space or seat.get("person"):
                continue
            model = model_object(seat_model_id(seat.get("model")), None)
            if model is None:
                continue
            out.append({"seat": seat.get("id"), "position": position.get("id"), "model": model})
    return out


def standup_seats(result: Any, space: str | None, team_agile: bool = True) -> list[dict]:
    """The seats reader for a Space: ``result`` is the org reader's ``OrgResult``,
    read once by the caller. Team Agile off, no result, no org file and a
    file that fails its checks (any status but ``ok``) are no seats."""
    if not team_agile or result is None or getattr(result, "status", None) != "ok":
        return []
    try:
        return space_seats(getattr(result, "chart", None), space)
    except Exception:  # noqa: BLE001 -- the reader never refuses: no seats is the answer
        return []
