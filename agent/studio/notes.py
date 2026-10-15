"""GET /api/studio/design -- the hub's designs and specs, the Studio's seed drawer.

A design note that belongs to no product yet is the engineer's, and lives in
the hub's ``design/`` folder (D-S3, D-S10; docs/modules/studio.md) -- the
folder the hub names (``hub.json`` ``folders.design``, default ``design``), a
sibling of ``growth/`` and ``reminders/``, never under a Space. Since the design
lifecycle's reader (L2, D-DL12)
the hub keeps the same FOUR folders a product's repo keeps -- ``design/``,
``design/archive/``, ``spec/`` (``folders.spec``) and ``spec/archive/`` -- and
the drawer answers the same shape ``GET /api/design`` does: designs grouped by
id with their state read from where the files are, the files not shown, and
which folders exist. The grouping and the state rule are ``agent/ado/design.py``'s;
nothing here re-derives them.

Read the way a repo's design/ is read: the title is the first ``# `` heading,
the description the YAML frontmatter's one line, the thread the ``> GitHub:``
line (the contract's ``studio.threadRegex``). A note may also name the Space
it is for (frontmatter ``space:``).

Every route here is a READ. A note is created by ``NewDesign``, promoted by
``NewItem -FromDesign`` and moved along its road by ``MoveDesign`` (L3), which
the web reaches through ``POST /api/cmd/{name}``: there is no second writer to
get the byte contract wrong.
"""

from __future__ import annotations

import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..ado.design import (
    ARCHIVE,
    LIVE,
    NOTE,
    SPEC,
    Design,
    DesignDoc,
    DesignSearchResponse,
    NotShown,
    Structure,
    attach_cards,
    group_designs,
    hits_from_matches,
    match_words,
    parse_design_doc,
    parse_doc,
    search_words,
    space_card_folders,
)
from ..core import log_writer
from ..core.config import hub_folder, load_config, tracker, tracker_repos
from ..core.consts import folder_archive, re_studio_note_name

# The Studio is core, from day one (D-S13):
# no flag, no gate. A `features.studio` line left in a machine's config is
# ignored here as everywhere else.
api = APIRouter()

_SPACE = re.compile(r"^space:\s*(.*)$")


class DesignNote(BaseModel):
    name: str = ""  # the file name, e.g. board-ideas.md
    title: str = ""  # the first `# ` heading, else the name
    description: str = ""  # the frontmatter's one-line `description`
    space: str = ""  # the frontmatter's `space`, "" when it names none
    thread: str = ""  # the `> GitHub:` issue URL, "" when none
    thread_number: int | None = None
    thread_repo: str = ""  # owner/name of the thread's repo
    thread_space: str = ""  # the declared GitHub Space whose repos hold the thread, "" when none does


class DesignNotesResponse(BaseModel):
    folder: str = ""  # the hub's design folder's name, as the hub calls it
    specFolder: str = ""  # ... and its spec folder's
    exists: bool = True  # False when the hub has no design folder -- a hub an older Start copied out
    count: int = 0  # the live notes, as before
    items: list[DesignNote] = []  # the live notes in design/, as before (the + and Promote read these)
    designs: list[Design] = []  # grouped by id, in road order -- the drawer's groups (L2)
    notShown: list[NotShown] = []
    structure: Structure = Structure()


class DesignNoteDetail(DesignNote):
    path: str = ""  # the file's hub-relative path, e.g. design/archive/old.md
    kind: str = ""  # note | spec
    archived: bool = False
    body: str = ""


def front_space(text: str) -> str:
    """The frontmatter's ``space:`` value, or ""."""
    lines = (text or "").replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = _SPACE.match(line)
        if m:
            return m.group(1).strip().strip('"').strip("'")
    return ""


def thread_space(thread_repo: str, spaces: list[dict]) -> str:
    """The slug of the declared GitHub Space whose repos hold ``thread_repo``.

    The reading room reads a thread through ``GET /api/issue/{n}?space=<slug>``,
    so it needs to know WHICH Space can answer for that repo. Matched without
    case, the way GitHub matches an owner and a repo. "" when no Space does --
    the page then links the thread rather than reading it.
    """
    want = (thread_repo or "").lower()
    if not want:
        return ""
    for space in spaces or []:
        org = space.get("org", "") or ""
        if tracker(org) != "github":
            continue
        if want in (r.lower() for r in tracker_repos(org, space.get("projects", []) or [])):
            return str(space.get("slug", ""))
    return ""


def read_note(text: str, name: str, spaces: list[dict]) -> DesignNote:
    title, description, thread, number, repo = parse_doc(text, name)
    return DesignNote(
        name=name,
        title=title,
        description=description,
        space=front_space(text),
        thread=thread,
        thread_number=number,
        thread_repo=repo,
        thread_space=thread_space(repo, spaces),
    )


def hub_design_folders() -> list[tuple[Path, str, str, str]]:
    """The hub's four folders: (path, hub-relative label, kind, where)."""
    design = hub_folder("design")
    spec = hub_folder("spec")
    arc = folder_archive()
    return [
        (design, design.name, NOTE, LIVE),
        (design / arc, f"{design.name}/{arc}", NOTE, ARCHIVE),
        (spec, spec.name, SPEC, LIVE),
        (spec / arc, f"{spec.name}/{arc}", SPEC, ARCHIVE),
    ]


def resolve_hub_doc(path: str) -> tuple[Path, str, str, str] | None:
    """A hub-relative path -- a bare name (the live note, as the route always
    took), or ``<folder>/<name>`` in one of the four -- to (file, label, kind,
    where), or None when it is not one the drawer could have listed."""
    rule = re_studio_note_name()
    folders = hub_design_folders()
    if "/" not in path:
        name = path
        if not rule.match(name):
            return None
        d, label, kind, where = folders[0]
        return d / name, label, kind, where
    label, _, name = path.rpartition("/")
    if not rule.match(name):
        return None
    for d, lab, kind, where in folders:
        if lab == label:
            return d / name, lab, kind, where
    return None


def _hub_docs(spaces: list[dict]) -> tuple[list[DesignDoc], list[DesignNote], Structure, dict[str, str]]:
    """The hub's four folders read once: the docs, the live notes (the + and
    Promote's), which roots exist, and each file's text by its hub path (for
    search inside, which runs over the text on disk)."""
    rule = re_studio_note_name()
    docs: list[DesignDoc] = []
    live_notes: list[DesignNote] = []
    texts: dict[str, str] = {}
    structure = Structure()
    for folder, label, kind, where in hub_design_folders():
        if not folder.is_dir():
            continue
        if where == LIVE:
            setattr(structure, "design" if kind == NOTE else "spec", True)
        for path in sorted(folder.iterdir(), key=lambda p: p.name.lower()):
            if not path.is_file() or not rule.match(path.name) or path.name.lower() == "readme.md":
                continue
            text = path.read_text(encoding="utf-8-sig")
            docs.append(parse_design_doc(text, f"{label}/{path.name}", kind=kind, archived=(where == ARCHIVE)))
            texts[f"{label}/{path.name}"] = text
            if kind == NOTE and where == LIVE:
                live_notes.append(read_note(text, path.name, spaces))
    return docs, live_notes, structure, texts


def list_hub_designs(spaces: list[dict], with_cards: bool = True) -> DesignNotesResponse:
    docs, live_notes, structure, _texts = _hub_docs(spaces)
    designs, not_shown = group_designs(docs)
    # A hub design belongs to no product, so a card in ANY Space may name it:
    # every declared Space's cards are read for the rows' cards (toolkit card C3).
    if with_cards:
        attach_cards(designs, space_card_folders(spaces))
    # The hub's rows carry the Space a note names and which Space can read
    # its thread -- the chip and the reading room need them (S2b).
    by_name = {n.name: n for n in live_notes}
    for d in designs:
        note = by_name.get(d.note.name) if d.note is not None and not d.note.archived else None
        if note is not None:
            d.space = note.space
        if d.thread_repo:
            d.thread_space = thread_space(d.thread_repo, spaces)
    return DesignNotesResponse(
        folder=hub_folder("design").name,
        specFolder=hub_folder("spec").name,
        exists=hub_folder("design").is_dir(),
        count=len(live_notes),
        items=live_notes,
        designs=designs,
        notShown=not_shown,
        structure=structure,
    )


@api.get("/studio/design", response_model=DesignNotesResponse)
async def list_notes():
    spaces = load_config().get("spaces", []) or []
    resp = list_hub_designs(spaces)
    log_writer.write_log("CMD", "agent/studio", f"{len(resp.designs)} hub designs, {len(resp.notShown)} not shown")
    return resp


HUB_SEARCH_NOTE = "Searched on disk, in the hub's design/, spec/ and their archives, as they are right now."


def search_hub_designs(spaces: list[dict], q: str) -> DesignSearchResponse:
    """Search inside the hub's four folders (L2b): the box's words -- every one,
    any order, case ignored -- over each file's text on disk; a hit names the
    design, its state and the first matching line."""
    words = search_words(q)
    docs, _live, _structure, texts = _hub_docs(spaces)
    designs, _not_shown = group_designs(docs)
    matches: list[tuple[str, str]] = []
    if words:
        for doc in docs:
            line = match_words(texts.get(doc.path, ""), words)
            if line is not None:
                matches.append((doc.path, line))
    return DesignSearchResponse(
        repo="the hub", query=q, hits=hits_from_matches(docs, designs, matches), note=HUB_SEARCH_NOTE
    )


@api.get("/studio/design/search", response_model=DesignSearchResponse)
async def search_notes(q: str = ""):
    # Declared before the {path} read, which would otherwise take "search" as a
    # document's name.
    spaces = load_config().get("spaces", []) or []
    resp = search_hub_designs(spaces, q)
    log_writer.write_log("CMD", "agent/studio", f"search '{q}': {len(resp.hits)} hits")
    return resp


@api.get("/studio/design/{path:path}", response_model=DesignNoteDetail)
async def get_note(path: str):
    found = resolve_hub_doc(path)
    if found is None:
        raise HTTPException(
            status_code=404,
            detail=f"No {path} -- a hub design is one .md file in design/, design/archive/, spec/ or spec/archive/.",
        )
    file, label, kind, where = found
    if not file.is_file():
        raise HTTPException(status_code=404, detail=f"No {path} in the hub's {label}/.")
    text = file.read_text(encoding="utf-8-sig")
    note = read_note(text, file.name, load_config().get("spaces", []) or [])
    return DesignNoteDetail(
        **note.model_dump(), path=f"{label}/{file.name}", kind=kind, archived=(where == ARCHIVE), body=text
    )
