"""GET /api/reference -- the hub's reference documents, listed, searched and read.

A reference document is one ``.md`` file in the hub's ``reference/current/`` --
the folder the hub names (``hubFolders.reference``, default ``reference``), a
sibling of ``reminders/`` and ``growth/``. It is kept for reading, not for
doing: a company holiday list, a policy guide. Its shape is
docs/hub/reference.md: a ``# Title``, then ``**Source:**``, ``**Valid:**
<from> to <to>``, ``**Added:**`` and an optional ``**Original:**`` header lines,
then ``---`` and the content. A header line that is missing reads empty, and a
file with none is still a document.

Two reads and nothing else: the list (with ``?q=`` -- every word, any order,
case ignored: the rule the hub's other searches apply, ``design.match_words``)
and one document's text by file name. A missing or empty folder is an empty
list, not an error. Nothing is written, moved or archived here -- a person
files these by hand -- and the same gate as every Organize route: off is 404.

The folder name is read with ``hub_folders().get("reference", "reference")``
rather than a key of ``DEFAULT_HUB_FOLDERS``: that table is mirrored by the
CLI's (``Test-HubJson.ps1`` holds the two equal), so the key is added to both
when the CLI's ``Reference`` verb lands, and a hub's override starts to work
then. Tests/fixtures/reference/table.json holds the header's reading to one
table, for the CLI's side to assert too.
"""

from __future__ import annotations

import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..ado.design import match_words, search_words
from ..core.config import hub_folders, hub_root
from ..core.consts import folder_current, stamp_source
from .reminders import _require_organize

api = APIRouter(dependencies=[Depends(_require_organize)])

# The folder's name when the hub declares none.
DEFAULT_FOLDER = "reference"
# The header's other stamps. Only this half types them today; they move to
# consts.json when the CLI's Reference verb (#315) reads them too.
STAMP_VALID = "**Valid:**"
STAMP_ADDED = "**Added:**"
STAMP_ORIGINAL = "**Original:**"

_H1 = re.compile(r"(?m)^#\s+(.+)$")
# The header ends at the first line that is only a rule.
_RULE = re.compile(r"(?m)^---[ \t]*$")
# How much of a document's content the list carries: the card clamps it to two lines.
EXCERPT_CHARS = 240
_TABLE_RULE = re.compile(r"(?m)^\s*\|?[\s:|-]+\|[\s:|-]*$")
_LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
# A document's file name: one .md file in the folder, never a path.
_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ -]*\.md$")


class ReferenceDoc(BaseModel):
    # The file name: the document's address.
    name: str
    title: str
    source: str
    # "<from> to <to>" exactly as written, or "".
    valid: str
    added: str
    original: str
    # The first line carrying a search word, when the list was searched.
    line: str = ""
    # The start of the content after the header, as plain words, for the list's
    # card item to clamp to two lines.
    excerpt: str = ""


class ReferenceList(BaseModel):
    count: int
    items: list[ReferenceDoc]
    # The search the list answers, "" for all of them.
    query: str


class ReferenceText(ReferenceDoc):
    # The file's whole text -- the header is part of what is read.
    body: str
    # Where the file lives on the agent's machine, for the page's copy-path line
    # (shared/FilePath): the thing handed to an assistant in a chat window.
    path: str


def _stamp(text: str, stamp: str) -> str:
    m = re.search(r"(?m)^" + re.escape(stamp) + r"[ \t]*(.*)$", text)
    return m.group(1).strip() if m else ""


def excerpt_of(text: str) -> str:
    """The first words of a document's content as one plain line: what follows the
    header's rule (else what follows the title), its markdown syntax dropped --
    heading marks, emphasis, code ticks, a link to its text, a table's pipes and
    its rule row -- the whitespace collapsed and the whole cut at ``EXCERPT_CHARS``
    on a word."""
    rule = _RULE.search(text)
    if rule:
        body = text[rule.end() :]
    else:
        h1 = _H1.search(text)
        body = text[h1.end() :] if h1 else text
    body = _TABLE_RULE.sub(" ", body)
    body = _LINK.sub(r"\1", body)
    body = re.sub(r"(?m)^\s{0,3}#{1,6}\s+", "", body)
    body = re.sub(r"[*_`|>]+", " ", body)
    body = " ".join(body.split())
    if len(body) <= EXCERPT_CHARS:
        return body
    return body[:EXCERPT_CHARS].rsplit(" ", 1)[0].rstrip(",;:") + "..."


def reference_dir() -> Path:
    return hub_root() / hub_folders().get("reference", DEFAULT_FOLDER) / folder_current()


def read_document(path: Path) -> tuple[ReferenceDoc, str]:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    h1 = _H1.search(text)
    doc = ReferenceDoc(
        name=path.name,
        title=h1.group(1).strip() if h1 else path.stem,
        source=_stamp(text, stamp_source()),
        valid=_stamp(text, STAMP_VALID),
        added=_stamp(text, STAMP_ADDED),
        original=_stamp(text, STAMP_ORIGINAL),
        excerpt=excerpt_of(text),
    )
    return doc, text


def list_documents(q: str = "") -> ReferenceList:
    folder = reference_dir()
    words = search_words(q)
    items: list[ReferenceDoc] = []
    if folder.is_dir():  # a hub with no reference folder has no documents, and that is not an error
        for f in sorted(folder.glob("*.md"), key=lambda p: p.name.lower()):
            if not f.is_file():
                continue
            doc, text = read_document(f)
            if words:
                line = match_words(text, words)
                if line is None:
                    continue
                doc.line = line
            items.append(doc)
    items.sort(key=lambda d: (d.title.lower(), d.name.lower()))
    return ReferenceList(count=len(items), items=items, query=" ".join(words))


@api.get("/reference", response_model=ReferenceList)
def get_reference(q: str = "") -> ReferenceList:
    return list_documents(q)


@api.get("/reference/{name}", response_model=ReferenceText)
def get_reference_document(name: str) -> ReferenceText:
    # The name is the rule's, checked before the disk is: no slash, no dots-only
    # segment, only .md. A refused name is a 404, like one that is not there.
    path = reference_dir() / name
    if not _NAME.match(name) or ".." in name or not path.is_file():
        raise HTTPException(status_code=404, detail=f"no reference document {name}")
    doc, text = read_document(path)
    return ReferenceText(**doc.model_dump(), body=text, path=str(path))


__all__ = ["api", "list_documents", "read_document", "reference_dir"]
