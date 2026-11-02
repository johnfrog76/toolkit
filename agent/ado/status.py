"""Prompt status: GET /status and GET /status/{filename}.

The ledger view. Reads every file in the active Space's ``current/`` folder and
derives each card's state from its content -- there is no status field
anywhere. Reads stay native Python rather than forking the CLI, because a page
render must not start a PowerShell process per card; the shared-fixture parity
test is what keeps the two derivations honest.
"""

import asyncio
import re
import threading
import time

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core.assets import card_images
from ..core.config import (
    backlog_dir,
    card_types,
    load_config,
    org_folder,
    resolve_dirs,
    tracker,
    tracker_repos,
)
from ..core.consts import folder_current
from ..core.git_history import folder_changes
from ..core.parsers import _parse_status_metadata, card_id, status_sort_key
from ..core.tier import _resolve_tier
from .accounting import _gh_json, space_entry

api = APIRouter()


class CardDesign(BaseModel):
    """The design a card names (docs/hub/cards.md, "Inside the file"): its
    `> Design:` line, or the corpus's hand-written `> Spec:` line, as written
    (agent/core/parsers.py card_design). On the card's own page the id is
    resolved -- the hub's designs from disk, the active GitHub Space's repo
    through the Design tab's own (cached) listing -- and ``state``, ``where``
    and ``path`` say what was found; "" when it could not be read."""

    kind: str = ""  # design | spec
    title: str = ""  # the line's link text, as last written
    link: str = ""  # the line's link target, as written
    id: str = ""  # the design's id, "" for a Spec line
    short: str = ""  # the id's first eight characters
    note: str = ""  # what the line says after the link and the id
    state: str = ""  # Design | Spec | Complete | Archived, once resolved
    where: str = ""  # hub | repo, once resolved
    path: str = ""  # the document to open: design/x.md, spec/archive/x.spec.md


class PromptInfo(BaseModel):
    """The Card model (docs/hub/cards.md, "The model, as the agent serves it"), as the status route
    serves it. ``title`` is the whole heading and predates the model; ``id``,
    ``type`` and ``name`` are the same facts as FIELDS, so nothing downstream
    parses a sentence or a filename to find them."""

    file: str
    id: str | None = None
    type: str | None = None
    name: str = ""
    linked: bool = False
    # Whose ledger: the tracker rule over the card's OWN link -- github | ado |
    # none. Declared here or Pydantic drops the key (ecb2bb7's lesson).
    tracker: str = "none"
    billable: bool = True
    # Who takes it: the card's **Assigned:** line -- "me", or a size -- "" for
    # nobody (D-AR10; Route -Assign writes it). docs/hub/cards.md.
    assigned: str = ""
    # The meeting record an agenda line came from: the card's **From:** line --
    # the record's file stem -- else None (NewPrompt -From writes it). docs/hub/cards.md.
    from_record: str | None = None
    title: str
    sprint: str
    # The card's milestone, WHOLE -- its **Milestone:** line, else an old card's
    # **Sprint:** line (card_milestone) -- and its Tags: line, split. "" and [] for
    # none. The board's milestone and tag filters read them. docs/hub/cards.md.
    milestone: str = ""
    tags: list[str] = []
    progress: str
    checked: int
    total: int
    modified: str
    ado_url: str | None = None
    pr_url: str | None = None
    # The `> Previous round:` path of a card that came back after archive, as the
    # card wrote it (relative to the card's folder), else None (docs/hub/cards.md).
    previous_round: str | None = None
    # Commit bullets in the file -- the git token, not a **Started:** line. What
    # the web's Create PR gate reads (docs/hub/cards.md).
    commits: int = 0
    # The card's pictures (docs/hub/cards.md, "A card's pictures"): the URL of
    # GET /api/assets/... for the file its **Cover:** / **Before:** line names,
    # or None -- no line, a file that is missing, or a path outside the Space's
    # assets/ (agent/core/assets.py; Tests/fixtures/parsers/covers.json).
    cover: str | None = None
    before: str | None = None
    # The design the card was worked against, as its line says (toolkit card C3).
    design: CardDesign | None = None
    # Derived, never stored: consts.json `status` -- Backlog (a card in backlog/,
    # planned and not in play) | Active | In Progress | Code Review. Done is a card
    # in archive/, which this route does not list. docs/hub/cards.md.
    status: str = "New"
    # The tracker's own pin on the card's ISSUE: true only on a GitHub
    # Space at Tier 1, for a card whose link is an issue in that Space's
    # repository and whose number is in the repository's pinned set. False
    # everywhere else, and in every one of those cases `gh` was not asked.
    pinned: bool = False


class StatusResponse(BaseModel):
    count: int
    prompts: list[PromptInfo]


class PromptDetailResponse(BaseModel):
    filename: str
    # The file's absolute path on the machine the agent runs on -- what a person
    # hands to an assistant so it can open the record (docs/hub/cards.md).
    path: str = ""
    id: str | None = None
    type: str | None = None
    name: str = ""
    linked: bool = False
    tracker: str = "none"
    billable: bool = True
    assigned: str = ""
    from_record: str | None = None
    title: str
    sprint: str
    milestone: str = ""
    tags: list[str] = []
    status: str
    ado_url: str | None = None
    pr_url: str | None = None
    previous_round: str | None = None
    commits: int = 0
    cover: str | None = None
    before: str | None = None
    design: CardDesign | None = None
    checked: int
    total: int
    progress: str
    content: str


# ---------------------------------------------------------------------------
# The pinned set: ONE `gh api graphql` call per repository, the tracker's
# own list of pinned issues, held briefly so the Board's polling does not ask gh
# on every tick, and dropped the moment EditItem runs (bridge.run_command) so an
# Unpin is on the next read.
PINNED_TTL_SECONDS = 60
GH_PINNED_QUERY = (
    "query($owner:String!,$name:String!){repository(owner:$owner,name:$name)"
    "{pinnedIssues(first:3){nodes{issue{number}}}}}"
)
_GH_ISSUE_URL = re.compile(r"github\.com/([^/]+)/([^/]+)/issues/(\d+)", re.IGNORECASE)
_pinned_cache: dict[str, tuple[float, set[int]]] = {}
_pinned_lock = threading.Lock()


def pinned_cache_clear() -> None:
    """Forget every cached pinned set. Called when EditItem runs, and by tests."""
    with _pinned_lock:
        _pinned_cache.clear()


def _gh_pinned_set(repo: str) -> set[int]:
    """The issue numbers pinned in ``owner/name``; empty when gh cannot say
    (an unanswered call is not cached, so the next read asks again)."""
    with _pinned_lock:
        hit = _pinned_cache.get(repo)
    if hit is not None and (time.monotonic() - hit[0]) < PINNED_TTL_SECONDS:
        return hit[1]
    owner, _, name = repo.partition("/")
    data, why = _gh_json(
        ["gh", "api", "graphql", "-f", f"query={GH_PINNED_QUERY}", "-f", f"owner={owner}", "-f", f"name={name}"]
    )
    if why or not isinstance(data, dict):
        return set()
    try:
        nodes = data["data"]["repository"]["pinnedIssues"]["nodes"] or []
        found = {int(n["issue"]["number"]) for n in nodes if n and n.get("issue")}
    except (KeyError, TypeError, ValueError):
        return set()
    with _pinned_lock:
        _pinned_cache[repo] = (time.monotonic(), found)
    return found


def _pinned_cards(prompts: list["PromptInfo"]) -> None:
    """Set ``pinned`` on the cards whose issue is pinned. Blocking (it shells
    out to gh); runs off the event loop. Gates first, so on ADO, on no tracker
    and below Tier 1 nothing is asked."""
    if not any(p.tracker == "github" for p in prompts):
        return
    cfg = load_config()
    org = cfg.get("org", "")
    if not org or tracker(org) != "github":
        return
    tier, _ = _resolve_tier(org, cfg.get("status", ""))
    if tier != 1:
        return
    pinned: dict[str, set[int]] = {}
    for repo in tracker_repos(org, cfg.get("projects", [])):
        pinned[repo.lower()] = _gh_pinned_set(repo)
    for p in prompts:
        m = _GH_ISSUE_URL.search(p.ado_url or "") if p.tracker == "github" else None
        if m:
            p.pinned = int(m.group(3)) in pinned.get(f"{m.group(1)}/{m.group(2)}".lower(), set())


@api.get("/status", response_model=StatusResponse)
async def get_status(space: str = ""):
    """The cards in a Space's ``current/`` (in play) and ``backlog/`` (planned).

    A card read from ``backlog/`` is served with status Backlog whatever its
    text says (card_status, the folder read first); the board draws it in its
    first column, and a reader that means "in play" filters it out by status.

    No ``space``: the active Space, exactly as it always read. A slug: that
    Space's own folder, so the Studio's Spaces card counts a row's cards without
    switching into it. It is a folder read -- no tracker is asked for a
    named Space, and nothing is gated beyond what this route always had. The
    slug is looked up the way the tracker reads' ``space`` argument is
    (``space_entry``, behind ``space_scope``), so an undeclared one is the same
    404 naming it.
    """
    cfg = load_config()
    active = cfg.get("activeSpace", "")
    # Another Space's cards: its own folder, and its pins are not asked for.
    elsewhere = bool(space) and space != active
    if space:
        current_dir = org_folder(space_entry(cfg, space)) / folder_current()
    else:
        current_dir, _ = resolve_dirs()
    planned_dir = backlog_dir(current_dir)
    folders = [d for d in (current_dir, planned_dir) if d.exists()]
    if not folders:
        return StatusResponse(count=0, prompts=[])

    files = [f for d in folders for f in sorted(d.iterdir())]
    type_names, prefixes = card_types()
    space = space or active
    prompts: list[PromptInfo] = []

    # The day each card last changed: ONE ``git log`` for the Space's folders,
    # not one per card (agent/core/git_history.py). The hub need not be a git
    # repository (docs/CONFIGURATION.md); outside one there is no map, and every
    # card reads its mtime below. The CLI's Get-PromptStatus.ps1 makes the same
    # one read of current/, and Tests/fixtures/status-modified/ holds the two to
    # one day.
    space_dir = current_dir.parent
    days = await asyncio.to_thread(folder_changes, space_dir, [d.name for d in folders]) or {}

    for f in files:
        if not f.is_file() or f.name.startswith("."):
            continue
        content = f.read_text(encoding="utf-8-sig", errors="replace")
        meta = _parse_status_metadata(content, type_names, folder=f.parent.name)
        if meta["design"]:
            meta["design"] = {**meta["design"], "short": meta["design"]["id"][:8]}

        # Last modified -- the folder's git log when the hub is a repository, the
        # mtime below when it is not, or when the log never named this card.
        modified = days.get(f"{f.parent.name}/{f.name}", ("", ""))[0]
        if not modified:
            mtime = f.stat().st_mtime
            modified = time.strftime("%Y-%m-%d", time.localtime(mtime))

        prompts.append(
            PromptInfo(
                file=f.name, id=card_id(f.name, prefixes), modified=modified, **card_images(content, f, space), **meta
            )
        )

    # The pinned set is the ACTIVE Space's tracker's; a named Space's
    # read is a folder read and asks no tracker.
    if not elsewhere:
        await asyncio.to_thread(_pinned_cards, prompts)
    prompts.sort(key=lambda p: status_sort_key(p.status, p.file))
    return StatusResponse(count=len(prompts), prompts=prompts)


# GET /api/status/{filename}
@api.get("/status/{filename}", response_model=PromptDetailResponse)
async def get_status_detail(filename: str):
    if "/" in filename or "\\" in filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    current_dir, _ = resolve_dirs()
    # current/ first, then backlog/: a card is in one of them, planned or in play.
    path = next(
        (p for p in (current_dir / filename, backlog_dir(current_dir) / filename) if p.is_file()),
        current_dir / filename,
    )
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail=f"{filename} not found")
    content = path.read_text(encoding="utf-8-sig", errors="replace")
    type_names, prefixes = card_types()
    meta = _parse_status_metadata(content, type_names, folder=path.parent.name)
    images = card_images(content, path, load_config().get("activeSpace", ""))
    # The design listings are read ONCE for the request and handed to the lookup,
    # and not at all for a card whose line names no id.
    line = meta["design"]
    rows = await design_listings(line["link"]) if line and line.get("id") else []
    meta["design"] = resolve_card_design(line, rows)
    return PromptDetailResponse(
        filename=filename, path=str(path.resolve()), id=card_id(filename, prefixes), content=content, **images, **meta
    )


async def design_listings(link: str) -> list[tuple[str, object]]:
    """Every design a card's id may name, as (where, design) rows, read once per
    request: the active Space's repo through the Design tab's own (cached)
    listing when the line's link is a GitHub URL and the tab's gate passes (a
    GitHub Space at Tier 1), then the hub's designs from disk. One call to each
    listing at most, whatever the caller then looks up in them."""
    from ..studio.notes import list_hub_designs  # notes.py imports design.py, not this
    from .design import list_design, repo_gate

    rows: list[tuple[str, object]] = []
    if link.startswith("https://github.com/"):
        try:
            repo = await repo_gate()
        except HTTPException:
            repo = None
        if repo:
            listed = await asyncio.to_thread(list_design, repo)
            rows += [("repo", d) for d in listed.designs]
    hub = await asyncio.to_thread(list_hub_designs, load_config().get("spaces", []) or [], False)
    rows += [("hub", d) for d in hub.designs]
    return rows


def resolve_card_design(line: dict | None, rows: list[tuple[str, object]]) -> CardDesign | None:
    """The card's design line, and -- when it carries an id -- what that id is
    now: its state and the document to open (docs/hub/cards.md,
    "Inside the file"), looked up in ``rows`` (``design_listings``, read by the
    caller once per request). A design that cannot be found leaves the line as
    it was written -- "the short id and the title last seen"."""
    if not line:
        return None
    found = CardDesign(**line, short=line.get("id", "")[:8])
    if not found.id:
        return found
    for where, d in rows:
        if d.id == found.id:
            doc = d.spec or d.note
            found.state, found.where, found.path = d.state, where, doc.path if doc else ""
            found.title = found.title or d.title
            break
    return found
