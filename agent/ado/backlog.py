"""GET /api/backlog -- the Backlog: a Space's waiting cards as ranked rows, each
milestone's cards in play shown in their place.

The same rows the CLI's ``Backlog`` prints, from the same rule
(``backlog_rows`` in ``agent/core/parsers.py``; ``Get-P20BacklogRows`` in
``Scripts/Read-Backlog.ps1``), held together by
``Tests/fixtures/parsers/backlog-order.json``. A folder read: the Space's
``current/`` and ``backlog/`` and its ``milestones/`` files. No tracker is
asked, nothing is written, and it answers offline.

On an Azure DevOps Space there is no backlog in ToolKit -- the company's is in
Azure DevOps, and a card there is work assigned to you -- so the route is a 404
naming ``MyWork``, the way the verb refuses (docs/modules/ado.md).
"""

from datetime import date

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from ..core.config import backlog_dir, card_types, load_config, org_folder, resolve_dirs, tracker
from ..core.consts import folder_backlog, folder_current, folder_milestones
from ..core.parsers import backlog_card, backlog_rows
from .accounting import space_entry

api = APIRouter()


class BacklogRow(BaseModel):
    """One waiting card (docs/hub/milestones.md, "The Backlog: the order as a table")."""

    rank: int | None = None  # its place among the milestone's ranked cards; None when unranked
    id: str
    title: str = ""
    type: str = ""  # a configured type name, "" when the heading names none
    milestone: str = ""
    tags: list[str] = []
    age: int | None = None  # days since the card was created; None without a date
    created: str = ""
    file: str = ""
    in_play: bool = False  # a card in current/: shown in its milestone's place, not waiting


class BacklogResponse(BaseModel):
    space: str
    count: int
    rows: list[BacklogRow]


def _read_folder(folder, name: str, type_names, prefixes) -> list[dict]:
    if not folder.is_dir():
        return []
    cards = []
    for f in sorted(folder.iterdir()):
        if not f.is_file() or not f.name.endswith(".md") or f.name.startswith("."):
            continue
        card = backlog_card(f.name, name, f.read_text(encoding="utf-8-sig", errors="replace"), type_names, prefixes)
        if card:
            cards.append(card)
    return cards


@api.get("/backlog", response_model=BacklogResponse)
async def get_backlog(space: str = "", milestone: str = "", tag: str = "", card_type: str = Query("", alias="type")):
    """The Backlog's rows for a Space -- the active one with no ``space`` -- filtered
    by ``milestone``, ``tag`` and ``type`` (AND, ignoring case). 404 on an Azure
    DevOps Space, and for a slug no Space declares."""
    cfg = load_config()
    active = cfg.get("activeSpace", "")
    if space and space != active:
        entry = space_entry(cfg, space)
        current_dir = org_folder(entry) / folder_current()
        org_url = entry.get("org", "")
    else:
        current_dir, _ = resolve_dirs()
        org_url = cfg.get("org", "")
    if tracker(org_url) == "ado":
        raise HTTPException(
            status_code=404,
            detail="This Space's backlog is in Azure DevOps; MyWork lists what is assigned to you.",
        )

    type_names, prefixes = card_types(cfg)
    space_dir = current_dir.parent
    cards = _read_folder(current_dir, folder_current(), type_names, prefixes)
    cards += _read_folder(backlog_dir(current_dir), folder_backlog(), type_names, prefixes)
    files: dict[str, str] = {}
    milestones = space_dir / folder_milestones()
    if milestones.is_dir():
        for f in sorted(milestones.iterdir()):
            if f.is_file() and f.name.endswith(".md"):
                files[f.name] = f.read_text(encoding="utf-8-sig", errors="replace")

    rows = backlog_rows(cards, files, date.today().isoformat(), milestone, tag, card_type)
    return BacklogResponse(space=space or active, count=len(rows), rows=[BacklogRow(**r) for r in rows])
