"""Design -- a GitHub Space's designs and specs, read from its repo (Studio S2, D-S11;
the design lifecycle's reader, L2; docs/modules/studio.md, "The file shape, and how a note is read").

``GET /design`` lists the product repo's four folders -- ``design/``,
``design/archive/``, ``spec/`` and ``spec/archive/`` -- and answers DESIGNS
grouped by id: one row per id, with its state read from where its files are
(4.3), its note and its spec, plus ``notShown`` (the files that are not designs:
no ``id:``, or an id two notes share) and ``structure`` (which of the two folders
exist), so the web decides nothing. ``GET /design/{path}`` returns one markdown
file by its repo path. Both read THROUGH THE TRACKER, through
``agent/ado/repo_read.py``: the listing is one GraphQL call for the four
folders' shape (names and blob shas) plus one for the texts of the blobs it has
never parsed, and the detail is one ``gh api repos/{owner}/{repo}/contents/{path}``
when its body is not already on disk. A design is owned by the product it is for
(D-S10), so it is read where the product keeps it, never copied into the hub.

The state rule lives here ONCE, ``design_state``, and the hub's seed drawer
(``agent/studio/notes.py``) groups its own folders through the same
``group_designs``: one contract, two places it applies (D-DL12). The CLI's
``Scripts/Read-DesignTree.ps1`` is the other implementation of the rule, and
``Tests/fixtures/design/states.json`` holds the two to one table.

Gated like every tracker read and by nothing else: a Space whose address is not
GitHub, or a machine below Tier 1, answers ``supported: false`` (the Design tab
is the ADO core's tab on a GitHub Space, not a module -- no flag). The address
must name ONE repository: an owner-grained address (``github.com/<owner>``)
is refused with a stated 400, because a design folder is one repo's.

A folder that does not exist is an empty list, not an error -- most repos have
no ``design/`` yet, and the tab then teaches the structure rather than going
blank (D-DL11). The listing is cached per process for a short TTL. Under it,
two things are kept ON DISK by blob sha, which never changes for the same bytes
(``agent/core/disk_cache.py``; docs/CONFIGURATION.md, "The agent's cache"): a
note's parsed row fields (``design_fields`` -- no body), so a restart refetches
nothing unchanged, and a note's body once it has been opened, so the detail
route serves an unchanged note without asking gh.
"""

import asyncio
import re
import subprocess  # noqa: F401 -- the suites patch design.subprocess.run; run_read calls the same module
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core import log_writer
from ..core.config import card_types, load_config, org_folder, resolve_dirs, tracker, tracker_owner
from ..core.consts import (
    design_id_key,
    design_outcomes,
    design_states,
    folder_archive,
    folder_current,
    re_design_docs,
    re_design_id,
    re_studio_thread,
    stamp_closed,
    stamp_outcome,
    status_done,
)
from ..core.parsers import _parse_status_metadata, card_design, card_id
from ..core.tier import _resolve_tier
from .repo_read import GH_TIMEOUT_SECONDS, _gh, read_folder_rows
from .repo_read import file_text as _file_text

__all__ = ["GH_TIMEOUT_SECONDS", "_file_text", "_gh"]  # docs.py and studio/prompts.py read through these

api = APIRouter()

# The two roots. Note first, spec beside it (D-S11: "no spec really exists
# without design"); each has an archive/ under it (D-DL1), named by the card's
# own archive folder (consts.json folders.archive).
DESIGN_FOLDERS = ("design", "spec")
LIST_TTL_SECONDS = 60
# The disk cache of parsed rows (repo_read.read_folder_rows). The number is the
# parse's version: change what design_fields reads and bump it, so every row is
# parsed again rather than read as the old rule left it.
DESIGN_ROWS = "design-rows-2"

# A document's name: one markdown file, no path. What the route accepts is
# exactly what the listing can produce -- nothing else reaches gh.
_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.md$")
# The thread a document names: a `> GitHub: <issue url>` line, the same line a
# card and an issue file carry. The pattern is the contract's (consts.json
# studio.threadRegex): the CLI writes the line when a hub note is promoted, and
# a hub note and a repo's design/ are read by this one rule.
_THREAD = re_studio_thread()

# repo -> (when, the listing, {path: blob sha}); the shas are what the detail
# route looks a body up by while the listing is fresh.
_list_cache: dict[str, tuple[float, "DesignListResponse", dict[str, str]]] = {}

NOTE, SPEC = "note", "spec"
LIVE, ARCHIVE = "live", "archive"


def clear_cache() -> None:
    """Forget every cached listing (the tests' reset). The disk cache is not
    touched: it is keyed by content, so nothing in it can be stale."""
    _list_cache.clear()


def design_folders() -> tuple[tuple[str, str, str], ...]:
    """The four folders in reading order: (folder path, kind, where)."""
    arc = folder_archive()
    return (
        ("design", NOTE, LIVE),
        (f"design/{arc}", NOTE, ARCHIVE),
        ("spec", SPEC, LIVE),
        (f"spec/{arc}", SPEC, ARCHIVE),
    )


def folder_of(path: str) -> tuple[str, str, str] | None:
    """The (folder, kind, where) a repo path sits in, or None when it is not one
    of the four -- ``design/x.md``, ``spec/archive/x.spec.md``."""
    folder, _, name = path.rpartition("/")
    if not folder or not _NAME.match(name):
        return None
    for row in design_folders():
        if row[0] == folder:
            return row
    return None


class DesignDoc(BaseModel):
    folder: str = ""  # design | design/archive | spec | spec/archive
    name: str = ""  # the file name
    path: str = ""  # folder/name, as the repo has it
    title: str = ""  # the first `# ` heading, else the name
    description: str = ""  # the YAML frontmatter's one-line `description`
    thread: str = ""  # the `> GitHub:` issue URL, "" when none
    thread_number: int | None = None
    thread_repo: str = ""  # owner/name of the thread's repo
    url: str = ""  # the file on github.com
    # The lifecycle's reads (L2): the frontmatter id, and the stamps.
    id: str = ""  # frontmatter `id:`, "" when the file has none
    kind: str = ""  # note | spec
    archived: bool = False  # in an archive/ folder
    closed: str = ""  # the Closed stamp's date, yyyy-mm-dd, alone
    outcome: str = ""  # the Outcome stamp's word, shipped or dropped, lowercase
    docs: str = ""  # `> Docs: <path>` on a spec


class NotShown(BaseModel):
    path: str = ""
    reason: str = ""


class Structure(BaseModel):
    design: bool = False  # the repo (or hub) has a design/ folder
    spec: bool = False  # ... and a spec/ folder


class BoundCard(BaseModel):
    """A card that names a design by its id -- its ``> Design:`` line
    (docs/hub/cards.md, "Inside the file"). Derived by reading the cards on
    every request; stored nowhere."""

    file: str = ""  # the card's file name
    id: str | None = None  # the card's own id, by the one id rule
    title: str = ""  # the card's heading, as the status route serves it
    status: str = ""  # Active | In Progress | Code Review | Done (archive/)
    space: str = ""  # the Space whose folder holds the card
    archived: bool = False  # in archive/


class Design(BaseModel):
    """One design: one id, a note and at most one spec (4.3)."""

    id: str = ""
    short: str = ""  # the first eight characters, as a person reads it
    state: str = ""  # Design | Spec | Complete | Archived
    title: str = ""
    description: str = ""
    thread: str = ""
    thread_number: int | None = None
    thread_repo: str = ""
    closed: str = ""  # a fact about a Complete or Archived design
    outcome: str = ""  # a fact about an Archived note without a spec
    mismatch: str = ""  # the two files disagree about where the design is: the sentence, or ""
    docs: str = ""  # where a Complete spec's durable part landed
    note: DesignDoc | None = None
    spec: DesignDoc | None = None
    # The hub's rows carry two more words (agent/studio/notes.py); "" in a repo.
    space: str = ""
    thread_space: str = ""
    # The cards worked against this design (toolkit card C3): every card
    # whose `> Design:` line carries this id, current/ before archive/.
    cards: list[BoundCard] = []


class DesignListResponse(BaseModel):
    supported: bool = True
    repo: str = ""
    items: list[DesignDoc] = []  # every file read, in folder then name order
    designs: list[Design] = []  # grouped by id, in road order then by title
    notShown: list[NotShown] = []  # files in the four folders that are not designs
    structure: Structure = Structure()
    reason: str | None = None


class DesignDocDetail(DesignDoc):
    supported: bool = True
    repo: str = ""
    body: str = ""
    reason: str | None = None


# -- Search inside (L2b; 4.6 "Search") -----------------------------------------
# The same words the box filters titles by, run over the documents' TEXT: on
# disk for the hub (agent/studio/notes.py), through the tracker's code search
# for a repo. A hit names the design, its state and the matching line.


class SearchHit(BaseModel):
    path: str = ""  # the file, folder/name
    name: str = ""
    line: str = ""  # the matching line, or GitHub's fragment, trimmed
    url: str = ""  # the file on github.com, "" in the hub
    id: str = ""  # the design's id, "" for a file that is not a design
    title: str = ""
    state: str = ""  # Design | Spec | Complete | Archived, "" when the file carries no id
    kind: str = ""  # note | spec
    archived: bool = False


class DesignSearchResponse(BaseModel):
    supported: bool = True
    repo: str = ""
    query: str = ""
    available: bool = True  # False when the search engine could not answer; reason says why
    reason: str = ""
    note: str = ""  # what this search cannot see, said every time
    hits: list[SearchHit] = []


CODE_SEARCH_NOTE = (
    "GitHub's code search reads the default branch only, and lags a push by minutes: "
    "a design on a branch, or pushed just now, is not found."
)


def search_words(q: str) -> list[str]:
    """The words of a search, lowercased: every one must appear (the box's rule)."""
    return [w for w in (q or "").lower().split() if w]


def match_words(text: str, words: list[str]) -> str | None:
    """The first line of ``text`` that carries one of ``words`` when EVERY word is
    somewhere in the text, else None. The rule the hub's search inside applies,
    the same "every word, any order, case ignored" the box applies to titles."""
    if not words:
        return None
    low = (text or "").lower()
    if not all(w in low for w in words):
        return None
    for line in (text or "").replace("\r\n", "\n").split("\n"):
        line_low = line.lower()
        if any(w in line_low for w in words):
            return line.strip()
    return ""


def hits_from_matches(docs: list[DesignDoc], designs: list[Design], matches: list[tuple[str, str]]) -> list[SearchHit]:
    """``(path, line)`` matches turned into hits that name the design each file
    belongs to, in road order then by title; a file with no id is a hit with no
    state, so the search never hides what it found."""
    by_path = {d.path: d for d in docs}
    by_id = {d.id: d for d in designs}
    order = {s: i for i, s in enumerate(design_states())}
    seen: set[str] = set()
    hits: list[SearchHit] = []
    for path, line in matches:
        if path in seen:
            continue
        seen.add(path)
        doc = by_path.get(path)
        if doc is None:
            continue
        design = by_id.get(doc.id) if doc.id else None
        hits.append(
            SearchHit(
                path=path,
                name=doc.name,
                line=line,
                url=doc.url,
                id=design.id if design else "",
                title=design.title if design else doc.title,
                state=design.state if design else "",
                kind=doc.kind,
                archived=doc.archived,
            )
        )
    hits.sort(key=lambda h: (order.get(h.state, 99), h.title.lower()))
    return hits


def _fragment_line(fragment: str, words: list[str]) -> str:
    """The line of a code-search fragment that carries a word, trimmed."""
    for line in (fragment or "").replace("\r\n", "\n").split("\n"):
        if any(w in line.lower() for w in words):
            return line.strip()
    return (fragment or "").strip().split("\n")[0].strip()


def search_design(repo: str, q: str) -> DesignSearchResponse:
    """A repo's search inside, through ``gh api search/code`` scoped to the
    two roots (each with its archive under it), asked for text matches."""
    words = search_words(q)
    if not words:
        return DesignSearchResponse(repo=repo, query=q, note=CODE_SEARCH_NOTE)
    listing = list_design(repo)
    if listing.reason:
        return DesignSearchResponse(repo=repo, query=q, available=False, reason=listing.reason, note=CODE_SEARCH_NOTE)
    matches: list[tuple[str, str]] = []
    for root in DESIGN_FOLDERS:
        # The query goes as -f/-F fields, never in the URL: the agent runs gh
        # through the shell on Windows, where an `&` in a URL is cmd's.
        rows, why = _gh(
            [
                "-X",
                "GET",
                "-H",
                "Accept: application/vnd.github.text-match+json",
                "search/code",
                "-f",
                f"q={' '.join(words)} repo:{repo} path:{root}",
                "-F",
                "per_page=50",
            ]
        )
        if why:
            return DesignSearchResponse(
                repo=repo, query=q, available=False, reason=f"{repo}: {why}", note=CODE_SEARCH_NOTE
            )
        for item in (rows or {}).get("items", []) if isinstance(rows, dict) else []:
            path = item.get("path", "")
            if folder_of(path) is None:
                continue
            fragments = [m.get("fragment", "") for m in item.get("text_matches", []) or []]
            line = _fragment_line(fragments[0], words) if fragments else ""
            matches.append((path, line))
    hits = hits_from_matches(listing.items, listing.designs, matches)
    log_writer.write_log("CMD", "agent/design", f"search '{q}': {len(hits)} hits ({repo})")
    return DesignSearchResponse(repo=repo, query=q, hits=hits, note=CODE_SEARCH_NOTE)


def space_repo(org_url: str) -> str | None:
    """``owner/name`` when the address names a repository, else None."""
    owner = tracker_owner(org_url)
    rest = (org_url or "").strip().split("://", 1)[-1].split("/")
    if owner and len(rest) >= 3 and rest[2]:
        return f"{owner}/{rest[2]}"
    return None


OWNER_GRAINED_REASON = (
    "This Space's address names a GitHub owner, not a repository -- the Design tab reads one "
    "repo's design/ and spec/ folders. Give the address a repo (github.com/<owner>/<repo>)."
)


def _front(text: str) -> tuple[dict[str, str], int]:
    """The YAML frontmatter's one-line keys, and the index of the first body line.
    A block is ``---`` on line 0 closed by ``---``; no block, an empty dict and 0."""
    lines = (text or "").replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, 0
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            found: dict[str, str] = {}
            for fm in lines[1:i]:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", fm)
                if m and m.group(1) not in found:
                    found[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            return found, i + 1
    return {}, 0


# A markdown heading line, and the section the design contract template puts
# a note's title under (its text on the next line, not on the heading's).
_HEADING = re.compile(r"^(#{1,6})(?:[ \t]+(.*?))?[ \t]*$")
_TITLE_SECTION = "Title"


def doc_title(lines: list[str]) -> str:
    """A document's title from its body lines (frontmatter already cut), "" for
    none -- the ONE rule, pinned row for row by Tests/fixtures/design/titles.json
    (Scripts/Read-DesignTree.ps1 Get-P20DesignTitle is the CLI's side):

    1. the FIRST heading, when it is level one (``# Title``) -- a ``# `` deeper in
       the body, after any other heading, is a sentence, not the title;
    2. else the first non-empty line after the first ``## Title`` heading, unless
       that line is itself a heading;
    3. else "" (the caller stands the file name in)."""
    first = True
    for i, line in enumerate(lines):
        m = _HEADING.match(line)
        if not m:
            continue
        hashes, words = m.group(1), (m.group(2) or "").strip()
        if first and hashes == "#" and words:
            return words
        first = False
        if hashes == "##" and words == _TITLE_SECTION:
            for nxt in lines[i + 1 :]:
                if nxt.strip():
                    return "" if _HEADING.match(nxt) else nxt.strip()
            return ""
    return ""


def parse_doc(text: str, name: str) -> tuple[str, str, str, int | None, str]:
    """(title, description, thread url, thread number, thread repo) from a file's text."""
    front, start = _front(text)
    lines = (text or "").replace("\r\n", "\n").split("\n")
    description = front.get("description", "")
    title = doc_title(lines[start:]) or name
    t = _THREAD.search(text or "")
    if t:
        return title, description, t.group(1), int(t.group(4)), f"{t.group(2)}/{t.group(3)}"
    return title, description, "", None, ""


def _stamp(text: str, stamp: str) -> str:
    """The text after a ``**Stamp:**`` line, "" when the file has none."""
    m = re.search(r"(?m)^" + re.escape(stamp) + r"\s*(.*?)\s*$", text or "")
    return m.group(1).strip() if m else ""


def design_fields(text: str) -> dict:
    """What a row needs from a file, read from its TEXT ALONE -- the dict the
    disk cache keeps by blob sha, so it may not depend on the file's name or
    folder: ``heading`` is ``doc_title``'s answer or "" (the name stands in at
    build time), and ``docs`` is read on every file (only a spec's is shown)."""
    heading, description, thread, number, thread_repo = parse_doc(text, "")
    front, _ = _front(text)
    raw_id = front.get(design_id_key(), "")
    closed = _stamp(text, stamp_closed())
    m = re.match(r"^\d{4}-\d{2}-\d{2}", closed)
    outcome = _stamp(text, stamp_outcome()).lower()
    d = re_design_docs().search(text or "")
    return {
        "heading": heading,
        "description": description,
        "thread": thread,
        "thread_number": number,
        "thread_repo": thread_repo,
        "id": raw_id if re_design_id().match(raw_id) else "",
        "closed": m.group(0) if m else "",
        "outcome": outcome if outcome in design_outcomes() else "",
        "docs": d.group(1).strip() if d else "",
    }


def design_doc(
    fields: dict, path: str, url: str = "", kind: str | None = None, archived: bool | None = None
) -> DesignDoc:
    """A DesignDoc from ``design_fields``' dict and where the file is. ``path`` is
    the repo (or hub) path, ``folder/name``; in a repo the folder says what the
    file is, and a hub -- whose folders may be renamed through hub.json -- says
    so itself with ``kind`` and ``archived``."""
    folder, _, name = path.rpartition("/")
    row = folder_of(path)
    if kind is None:
        kind, where = (row[1], row[2]) if row else ("", LIVE)
    else:
        where = ARCHIVE if archived else LIVE
    return DesignDoc(
        folder=folder,
        name=name,
        path=path,
        title=fields.get("heading") or name,
        description=fields.get("description", ""),
        thread=fields.get("thread", ""),
        thread_number=fields.get("thread_number"),
        thread_repo=fields.get("thread_repo", ""),
        url=url,
        id=fields.get("id", ""),
        kind=kind,
        archived=(where == ARCHIVE),
        closed=fields.get("closed", ""),
        outcome=fields.get("outcome", ""),
        docs=fields.get("docs", "") if kind == SPEC else "",
    )


def parse_design_doc(
    text: str, path: str, url: str = "", kind: str | None = None, archived: bool | None = None
) -> DesignDoc:
    """One file of the four folders, every field read -- the lifecycle's reader
    of a document: ``design_fields`` over the text, ``design_doc`` over where it is."""
    return design_doc(design_fields(text), path, url, kind, archived)


def design_state(note: str | None, spec: str | None, note_text: str = "", spec_text: str = "") -> dict:
    """The state rule (4.3) over one design. ``note`` and ``spec`` say where each
    file is: ``"live"``, ``"archive"`` or None for none.

    Returns ``state``, ``outcome`` ("" unless an Archived note says shipped or
    dropped), ``mismatch`` (the two files disagree about where the design is;
    the spec's folder wins) and ``closed`` (a fact about a design that has
    reached an archive state: the spec's date for Complete, the note's for
    Archived). Pinned by Tests/fixtures/design/states.json, from both halves.
    """
    s_design, s_spec, s_complete, s_archived = design_states()
    state, mismatch = s_design, False
    if spec == ARCHIVE:
        state = s_complete
        mismatch = note == LIVE
    elif spec == LIVE:
        state = s_spec
        mismatch = note == ARCHIVE
    elif note == ARCHIVE:
        state = s_archived
    outcome = ""
    if state == s_archived:
        word = _stamp(note_text, stamp_outcome()).lower()
        outcome = word if word in design_outcomes() else ""
    closed = ""
    if state == s_complete:
        closed = _stamp(spec_text, stamp_closed())
    elif state == s_archived:
        closed = _stamp(note_text, stamp_closed())
    m = re.match(r"^\d{4}-\d{2}-\d{2}", closed)
    return {"state": state, "outcome": outcome, "mismatch": mismatch, "closed": m.group(0) if m else ""}


def _mismatch_sentence(note: DesignDoc, spec: DesignDoc) -> str:
    if spec.archived and not note.archived:
        return f"The spec is archived and the note was left behind in {note.folder}/."
    return f"The note was archived before its spec: {spec.folder}/{spec.name} is still live."


def group_designs(docs: list[DesignDoc]) -> tuple[list[Design], list[NotShown]]:
    """Designs grouped by id from the files of the four folders, in road order
    then by title; and the files that are not shown, each with its reason."""
    not_shown: list[NotShown] = []
    by_id: dict[str, list[DesignDoc]] = {}
    for d in docs:
        if not d.id:
            not_shown.append(NotShown(path=d.path, reason="no id"))
            continue
        by_id.setdefault(d.id, []).append(d)

    designs: list[Design] = []
    for doc_id, members in by_id.items():
        short = doc_id[:8]
        notes = [m for m in members if m.kind == NOTE]
        specs = [m for m in members if m.kind == SPEC]
        conflict = False
        if len(notes) > 1:
            conflict = True
            not_shown.extend(NotShown(path=n.path, reason=f"{len(notes)} notes carry the id {short}") for n in notes)
        if len(specs) > 1:
            conflict = True
            not_shown.extend(NotShown(path=s.path, reason=f"{len(specs)} specs carry the id {short}") for s in specs)
        if conflict:
            continue
        note = notes[0] if notes else None
        spec = specs[0] if specs else None
        where = lambda d: None if d is None else (ARCHIVE if d.archived else LIVE)  # noqa: E731
        # The stamps are already on the docs; the rule reads them from the text,
        # so it is handed the lines it needs rather than a second parse.
        r = design_state(where(note), where(spec), _lines_for(note), _lines_for(spec))
        lead = note or spec
        assert lead is not None
        thread_doc = note if note and note.thread else (spec if spec and spec.thread else None)
        designs.append(
            Design(
                id=doc_id,
                short=short,
                state=r["state"],
                title=lead.title,
                description=lead.description,
                thread=thread_doc.thread if thread_doc else "",
                thread_number=thread_doc.thread_number if thread_doc else None,
                thread_repo=thread_doc.thread_repo if thread_doc else "",
                closed=r["closed"],
                outcome=r["outcome"],
                mismatch=_mismatch_sentence(note, spec) if (r["mismatch"] and note and spec) else "",
                docs=spec.docs if spec else "",
                note=note,
                spec=spec,
            )
        )

    order = {s: i for i, s in enumerate(design_states())}
    designs.sort(key=lambda d: (order.get(d.state, 99), d.title.lower()))
    return designs, not_shown


def _lines_for(doc: DesignDoc | None) -> str:
    """The stamp lines a parsed doc carries, re-spelled for the rule."""
    if doc is None:
        return ""
    out = []
    if doc.closed:
        out.append(f"{stamp_closed()} {doc.closed}")
    if doc.outcome:
        out.append(f"{stamp_outcome()} {doc.outcome}")
    return "\n".join(out)


def _is_design_file(name: str) -> bool:
    """A markdown file of the four folders, other than the folder's README."""
    return bool(_NAME.match(name)) and name.lower() != "readme.md"


def list_design(repo: str) -> DesignListResponse:
    hit = _list_cache.get(repo)
    if hit and time.monotonic() - hit[0] < LIST_TTL_SECONDS:
        return hit[1]
    folders = design_folders()
    read = read_folder_rows(
        repo, [f for f, _k, _w in folders], namespace=DESIGN_ROWS, parse=design_fields, keep=_is_design_file
    )
    if read.reason:
        return DesignListResponse(repo=repo, reason=f"{repo}: {read.reason}")
    items: list[DesignDoc] = []
    structure = Structure()
    for folder, _kind, where in folders:
        entries = read.folders.get(folder)
        if entries is None:
            continue  # no such folder: an empty list, not an error
        if where == LIVE:
            setattr(structure, folder, True)
        items.extend(design_doc(read.rows[e.path], e.path, read.file_url(e.path)) for e in entries)
    designs, not_shown = group_designs(items)
    resp = DesignListResponse(repo=repo, items=items, designs=designs, notShown=not_shown, structure=structure)
    _list_cache[repo] = (time.monotonic(), resp, read.shas)
    log_writer.write_log(
        "CMD",
        "agent/design",
        f"{len(designs)} designs, {len(not_shown)} not shown ({repo}; {read.calls} gh calls)",
    )
    return resp


def _listed(repo: str, path: str) -> tuple[str, str]:
    """(blob sha, file url) of ``path`` from a listing still inside its TTL, else
    ("", ""). A sha older than the TTL is not trusted: the note may have changed."""
    hit = _list_cache.get(repo)
    if not hit or time.monotonic() - hit[0] >= LIST_TTL_SECONDS:
        return "", ""
    doc = next((d for d in hit[1].items if d.path == path), None)
    return hit[2].get(path, ""), doc.url if doc else ""


def read_design_doc(repo: str, path: str) -> DesignDocDetail:
    # The listing's sha, while it is fresh, finds the body on disk: an unchanged
    # note opens with no gh call. Otherwise one contents call, kept by its sha.
    sha, url = _listed(repo, path)
    text, row, why = _file_text(repo, path, sha)
    if why == "not found":
        raise HTTPException(status_code=404, detail=f"No {path} in {repo}.")
    folder, _, name = path.rpartition("/")
    if why:
        return DesignDocDetail(repo=repo, folder=folder, name=name, path=path, reason=f"{repo}: {why}")
    doc = parse_design_doc(text or "", path, url or (row or {}).get("html_url", ""))
    log_writer.write_log("CMD", "agent/design", f"{path} ({repo}{'' if row else '; from the cache'})")
    return DesignDocDetail(**doc.model_dump(), repo=repo, body=text or "")


# -- The cards a design was worked against (toolkit card C3) ----------------------
# A card names its design by a `> Design: [<title>](<link>) <id>` line
# (consts.json design.cardLineRegex; agent/core/parsers.py card_design). A
# design's row lists every card whose line carries its id -- read from the cards
# on every request, stored nowhere (docs/hub/cards.md, "Inside the file"). A
# hand-written `> Spec:` line carries no id, so it binds nothing here.


def space_card_folders(spaces: list[dict]) -> list[tuple[str, Path]]:
    """(slug, the Space's folder) for every declared Space, the hub-root folder
    for one that names none."""
    return [(str(s.get("slug") or ""), org_folder(s)) for s in spaces or []]


def bound_cards(folders: list[tuple[str, Path]]) -> dict[str, list[BoundCard]]:
    """Every card in these Spaces' current/ and archive/ whose design line names
    a design by id, grouped by that id."""
    type_names, prefixes = card_types()
    out: dict[str, list[BoundCard]] = {}
    seen: set[Path] = set()
    for slug, folder in folders:
        for sub, archived in ((folder_current(), False), (folder_archive(), True)):
            where = folder / sub
            if not where.is_dir() or where in seen:
                continue
            seen.add(where)
            for f in sorted(where.iterdir(), key=lambda p: p.name):
                if not f.is_file() or not f.name.endswith(".md"):
                    continue
                try:
                    text = f.read_text(encoding="utf-8-sig", errors="replace")
                except OSError:
                    continue
                design = card_design(text)
                if not design or not design["id"]:
                    continue
                meta = _parse_status_metadata(text, type_names)
                out.setdefault(design["id"], []).append(
                    BoundCard(
                        file=f.name,
                        id=card_id(f.name, prefixes),
                        title=meta["title"],
                        status=status_done() if archived else meta["status"],
                        space=slug,
                        archived=archived,
                    )
                )
    for cards in out.values():
        cards.sort(key=lambda c: (c.archived, c.file))
    return out


def attach_cards(designs: list[Design], folders: list[tuple[str, Path]]) -> None:
    """Give each design its cards (in place)."""
    by_id = bound_cards(folders)
    for d in designs:
        d.cards = by_id.get(d.id, [])


async def repo_gate(owner_reason: str = OWNER_GRAINED_REASON) -> str | None:
    """The Space's repo when a repo-reading tab may read, None when it is not
    supported. ONE gate for the Design and Docs tabs: GitHub, Tier 1,
    and an address that names a repo -- asked before gh is, so a Space that is
    not supported never reaches a subprocess."""
    cfg = load_config()
    org = cfg.get("org", "")
    if tracker(org) != "github":
        return None
    tier, _ = await asyncio.to_thread(_resolve_tier, org, cfg.get("status", ""))
    if tier != 1:
        return None
    repo = space_repo(org)
    if not repo:
        raise HTTPException(status_code=400, detail=owner_reason)
    return repo


@api.get("/design", response_model=DesignListResponse)
async def get_design():
    repo = await repo_gate()
    if repo is None:
        return DesignListResponse(supported=False)
    listed = await asyncio.to_thread(list_design, repo)
    # The listing is cached; the cards are read fresh, onto a copy, so a card
    # bound a second ago is on the next read (toolkit card C3).
    resp = listed.model_copy(deep=True)
    # The active Space's own cards: a repo's design is that product's.
    folders = [(str(load_config().get("activeSpace") or ""), resolve_dirs()[0].parent)]
    await asyncio.to_thread(attach_cards, resp.designs, folders)
    return resp


@api.get("/design/search", response_model=DesignSearchResponse)
async def get_design_search(q: str = ""):
    # Search inside a repo's four folders (L2b): asked on request, never on the
    # tab's first draw -- GitHub's code search is Tier 1, rate-limited and slow
    # on a cold agent, so the tab degrades the way its other reads do:
    # the groups are already drawn, and a search that cannot run says why.
    repo = await repo_gate()
    if repo is None:
        return DesignSearchResponse(supported=False, query=q, note=CODE_SEARCH_NOTE)
    return await asyncio.to_thread(search_design, repo, q)


@api.get("/design/{path:path}", response_model=DesignDocDetail)
async def get_design_doc(path: str):
    # The path is one of the four folders then a name -- design/x.md,
    # spec/archive/x.spec.md -- and nothing else reaches gh.
    if folder_of(path) is None:
        raise HTTPException(
            status_code=404,
            detail=f"No {path} -- the Design tab reads markdown in design/, design/archive/, spec/ and spec/archive/.",
        )
    repo = await repo_gate()
    if repo is None:
        return DesignDocDetail(supported=False)
    return await asyncio.to_thread(read_design_doc, repo, path)
