"""Docs -- a GitHub Space's README and docs/ tree, read from its repo (D-S12).

Design is what the product WILL be; Docs is what it IS. Three routes, all
read THROUGH THE TRACKER the way ``design.py`` reads -- ``gh api
repos/{owner}/{repo}/contents/{path}``, a subprocess, JSON back, one sentence
when gh does not answer:

- ``GET /docs`` -- the repo's ``README.md`` and its ``docs/`` tree (recursive,
  ``.md`` only, sorted by path). Names and paths, no file text: the README's
  own Documentation table is the index, and this list is the fallback for a
  repo whose README does not link everything -- so it costs ONE gh call
  (``repo_read.read_folder_rows``: the root and ``docs/`` to ``MAX_DEPTH``
  levels, one GraphQL query), however the folders nest.
- ``GET /docs/{path}`` -- one document's text, ``path`` relative to the repo
  root (``README.md``, ``docs/CLI.md``, ``docs/modules/ado.md``).
- ``GET /docs/asset/{path}`` -- the bytes of an image a document references
  (``docs/images/board.jpg``, ``assets/logo.png``), decoded from the contents
  route -- or, past the 1 MB that route inlines, from the blobs route by the
  file's sha -- and served with its content type, so the README's pictures
  render in the room, a private repository's too. ``ASSET_MAX_BYTES`` is the
  ceiling; an image past it is a 413 that says so, and the blob is never asked.

A document also says where its repository's issues are (``issues``), so the
room can make a ``#N`` in its text a link; "" when the repository has issues
turned off or GitHub did not say, and the ``#N`` stays text.

THE SAME GATE AS ``/design`` (``design.repo_gate``): a GitHub Space at Tier 1
whose address names one repo. An ADO Space, a Space with no tracker, or Tier 2
answers ``supported: false`` and gh is never asked. The same cache: the
listing for a short TTL per process, a file's text by its blob sha (the very
dict the Design tab fills -- a sha is a sha).

THE PATH RULE is written once, ``doc_path``: ``README.md`` itself, or a
markdown path under ``docs/``; an image anywhere in the repository; never a
``..``, an empty or dot segment, a backslash or a leading slash. A refused
path is a 404 that says the rule, before gh is asked. The two roots are the
contract's (consts.json ``docs``), because the web's link resolver decides
which links open in the room by the same rule.
"""

import asyncio
import base64
import mimetypes
import re
import time

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from ..core import log_writer
from ..core.config import DOCS_ASSET_ROUTE, DOCS_README, DOCS_ROOT, DOCS_ROUTE
from ..core.consts import re_docs_segment
from . import design
from .design import _file_text, _gh, parse_doc
from .repo_read import read_folder_rows

api = APIRouter()

LIST_TTL_SECONDS = design.LIST_TTL_SECONDS
# A repository's issues switch changes about as often as its visibility, which
# the foyer holds for 600 s (accounting.VISIBILITY_TTL_SECONDS).
ISSUES_TTL_SECONDS = 600
# How many levels of docs/ the listing reads (docs/ itself is the first).
# docs/hub/ and docs/modules/ are one level down; a fifth is a tree nobody is
# browsing from a list. The depth is a nesting of one query, not a call per level.
MAX_DEPTH = 4
# The repository root, as the shared reader names it: HEAD:<"">.
REPO_ROOT = ""

# One path segment: what a repo's file and folder names look like here -- the
# contract's (consts.json docs.segment), because the web's resolver applies
# it too. What the routes accept is exactly what the listing can produce.
_SEGMENT = re_docs_segment()
# What the asset route serves, by extension. An image a document shows -- not
# a script, not a page.
ASSET_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
}
# The contents route inlines a file up to 1 MB; past that an image is read
# from the blobs route by its sha, up to this ceiling. A picture in a document
# is rarely past a few MB, and the bytes cross a subprocess pipe as base64 --
# past this it is a 413 that says so, and the reader opens it on GitHub.
ASSET_MAX_BYTES = 10 * 1024 * 1024
# A git object id (SHA-1 or SHA-256), checked before it goes in a gh argument.
_SHA = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
# An SVG is a document that can carry script; opened on its own at this origin
# it must not run any. An <img> never runs it either way.
_ASSET_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
    "Cache-Control": "private, max-age=300",
}

OWNER_GRAINED_REASON = (
    "This Space's address names a GitHub owner, not a repository -- the Docs tab reads one "
    "repo's README.md and docs/. Give the address a repo (github.com/<owner>/<repo>)."
)
PATH_RULE = f"the Docs tab reads {DOCS_README}, the markdown under {DOCS_ROOT}/ and the repository's images"

_list_cache: dict[str, tuple[float, "DocsListResponse"]] = {}
_issues_cache: dict[str, tuple[float, str]] = {}


def clear_cache() -> None:
    """Forget every cached listing and file -- the Docs tab's AND the shared
    text cache (the tests' reset)."""
    _list_cache.clear()
    _issues_cache.clear()
    design.clear_cache()


def doc_path(path: str, *, asset: bool = False) -> bool:
    """Is ``path`` one the Docs routes may read?

    A document: ``README.md``, or a ``.md`` file under ``docs/``. An asset: an
    image (``ASSET_TYPES``) anywhere in the repository -- under ``docs/``,
    beside the README, or in a folder of its own. Never ``..`` anywhere, never an empty or dot segment, a backslash
    or an absolute path -- checked as text, before anything is asked."""
    if not path or ".." in path or "\\" in path or path.startswith("/"):
        return False
    parts = path.split("/")
    if not all(_SEGMENT.match(p) for p in parts):
        return False
    name = parts[-1]
    if asset:
        return any(name.lower().endswith(ext) for ext in ASSET_TYPES)
    if path == DOCS_README:
        return True
    return parts[0] == DOCS_ROOT and len(parts) >= 2 and name.endswith(".md")


class DocEntry(BaseModel):
    path: str = ""  # relative to the repo root: README.md, docs/CLI.md
    name: str = ""  # the file name
    folder: str = ""  # the folder it is in: "", docs, docs/modules
    url: str = ""  # the file on github.com


class DocsListResponse(BaseModel):
    supported: bool = True
    repo: str = ""
    readme: DocEntry | None = None
    items: list[DocEntry] = []
    reason: str | None = None


class DocDetail(DocEntry):
    supported: bool = True
    repo: str = ""
    title: str = ""  # the first `# ` heading, else the name
    body: str = ""
    issues: str = ""  # the repository's issues on github.com; "" when it has none
    reason: str | None = None


def _entry(row: dict) -> DocEntry:
    path = row.get("path", "")
    return DocEntry(path=path, name=row.get("name", ""), folder=path.rpartition("/")[0], url=row.get("html_url", ""))


def list_docs(repo: str) -> DocsListResponse:
    """The README and the markdown under ``docs/``, in ONE gh call whatever the
    nesting: the repository root (its files) and ``docs/`` (``MAX_DEPTH`` levels
    of it) through the shared reader, names and shas only -- no file's text is
    asked for, because the room opens a document on its own."""
    hit = _list_cache.get(repo)
    if hit and time.monotonic() - hit[0] < LIST_TTL_SECONDS:
        return hit[1]
    read = read_folder_rows(
        repo, [REPO_ROOT, DOCS_ROOT], keep=lambda name: name.endswith(".md"), depth={DOCS_ROOT: MAX_DEPTH}
    )
    if read.reason:
        return DocsListResponse(repo=repo, reason=f"{repo}: {read.reason}")
    # Whatever the walk found, the path rule decides: it is the one place that
    # says which paths the routes will read, so the list can never offer one
    # they refuse. (It also drops a file under a folder whose name is not a
    # plain segment, as the contents walk did.)
    entries = [e for folder in (REPO_ROOT, DOCS_ROOT) for e in read.folders.get(folder, []) if doc_path(e.path)]
    rows = [
        DocEntry(path=e.path, name=e.name, folder=e.path.rpartition("/")[0], url=read.file_url(e.path)) for e in entries
    ]
    readme = next((r for r in rows if r.path == DOCS_README), None)
    items = sorted((r for r in rows if r is not readme), key=lambda d: d.path.lower())
    resp = DocsListResponse(repo=repo, readme=readme, items=items)
    _list_cache[repo] = (time.monotonic(), resp)
    if read.repo_url and read.has_issues is not None:
        # The same answer carries the issues switch: a document read right after
        # the list needs no call of its own to link its `#N`.
        _issues_cache[repo] = (time.monotonic(), f"{read.repo_url}/issues" if read.has_issues else "")
    log_writer.write_log("CMD", "agent/docs", f"{len(items)} documents ({repo}; {read.calls} gh call)")
    return resp


def issues_url(repo: str) -> str:
    """The repository's issues on github.com, or "" when it has issues turned
    off -- or GitHub did not say, which is not cached, so the next read asks.
    Filled by the listing's own call when the list was read first; asked for
    (``gh api repos/<repo>``) only on a cold document read."""
    hit = _issues_cache.get(repo)
    if hit and time.monotonic() - hit[0] < ISSUES_TTL_SECONDS:
        return hit[1]
    row, why = _gh([f"repos/{repo}"])
    if why or not isinstance(row, dict):
        return ""
    html = str(row.get("html_url") or "")
    url = f"{html}/issues" if row.get("has_issues") and html else ""
    _issues_cache[repo] = (time.monotonic(), url)
    return url


def read_doc(repo: str, path: str) -> DocDetail:
    text, row, why = _file_text(repo, path)
    if why == "not found":
        raise HTTPException(status_code=404, detail=f"No {path} in {repo}.")
    if why:
        return DocDetail(repo=repo, path=path, name=path.rpartition("/")[2], reason=f"{repo}: {why}")
    entry = _entry(row or {"path": path, "name": path.rpartition("/")[2]})
    title = parse_doc(text or "", entry.name)[0]
    log_writer.write_log("CMD", "agent/docs", f"{path} ({repo})")
    return DocDetail(**entry.model_dump(), repo=repo, title=title, body=text or "", issues=issues_url(repo))


def read_asset(repo: str, path: str) -> tuple[bytes, str]:
    """(bytes, content type) of one image: decoded from the contents route,
    or from the blobs route by its sha when it is past what that route inlines."""
    row, why = _gh([f"repos/{repo}/contents/{path}"])
    if why == "not found" or (row is not None and not (isinstance(row, dict) and row.get("type") == "file")):
        raise HTTPException(status_code=404, detail=f"No {path} in {repo}.")
    if why:
        raise HTTPException(status_code=502, detail=f"{repo}: {why}")
    size = row.get("size") if isinstance(row.get("size"), int) else 0
    if size > ASSET_MAX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"{path} is {size / 1048576:.1f} MB -- the Docs tab serves an image up to "
            f"{ASSET_MAX_BYTES // 1048576} MB. Open it on GitHub.",
        )
    raw = row.get("content") or ""
    if row.get("encoding", "base64") != "base64" or (not raw and size):
        # Past the 1 MB the contents route inlines, it answers with no content:
        # the bytes are the blob's, asked for by the sha it did answer with.
        raw = _blob(repo, path, str(row.get("sha") or ""))
    try:
        data = base64.b64decode(raw)
    except ValueError:
        raise HTTPException(status_code=502, detail=f"{path} did not decode.")
    ext = "." + path.rsplit(".", 1)[-1].lower()
    return data, ASSET_TYPES.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"


def _blob(repo: str, path: str, sha: str) -> str:
    """One blob's base64 text, by its sha -- the large image's way in."""
    if not _SHA.match(sha):
        raise HTTPException(status_code=502, detail=f"{path}: GitHub gave no object id to read it by.")
    blob, why = _gh([f"repos/{repo}/git/blobs/{sha}"])
    if why:
        raise HTTPException(status_code=502, detail=f"{repo}: {why}")
    if not isinstance(blob, dict) or blob.get("encoding") != "base64":
        raise HTTPException(status_code=502, detail=f"{path}: the blob did not come back as base64.")
    return str(blob.get("content") or "")


def _refuse(path: str, what: str = "document") -> HTTPException:
    return HTTPException(status_code=404, detail=f"No {what} {path} -- {PATH_RULE}, and never a '..'.")


@api.get(DOCS_ROUTE, response_model=DocsListResponse)
async def get_docs():
    repo = await design.repo_gate(OWNER_GRAINED_REASON)
    if repo is None:
        return DocsListResponse(supported=False)
    return await asyncio.to_thread(list_docs, repo)


# Registered BEFORE the document route, whose {path:path} would otherwise
# claim asset/... first.
@api.get(DOCS_ASSET_ROUTE + "/{path:path}")
async def get_doc_asset(path: str):
    if not doc_path(path, asset=True):
        raise _refuse(path, "image")
    repo = await design.repo_gate(OWNER_GRAINED_REASON)
    if repo is None:
        raise HTTPException(status_code=404, detail="The Docs tab reads a GitHub repo -- this Space has none.")
    data, media_type = await asyncio.to_thread(read_asset, repo, path)
    return Response(content=data, media_type=media_type, headers=_ASSET_HEADERS)


@api.get(DOCS_ROUTE + "/{path:path}", response_model=DocDetail)
async def get_doc(path: str):
    if not doc_path(path):
        raise _refuse(path)
    repo = await design.repo_gate(OWNER_GRAINED_REASON)
    if repo is None:
        return DocDetail(supported=False)
    return await asyncio.to_thread(read_doc, repo, path)
