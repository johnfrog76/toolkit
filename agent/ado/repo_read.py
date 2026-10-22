"""Reading folders of a GitHub repository through the tracker: list once, fetch a
detail when it is asked for, cache the bytes by their hash.

The Design tab reads a product's ``design/`` and ``spec/`` (each with an
``archive/``) THROUGH THE TRACKER rather than a clone (D-DL12: designs show on
any machine without a checkout). Reading it one ``gh api .../contents/<file>``
per note made a repository with a large archive cost one subprocess per file,
serially, every agent restart and every minute past the listing's TTL -- 191
calls and about 85 seconds for a studio with 189 notes. This module is the
reader that replaced it, built to be shared: any folder of any repository, any
parse.

``read_folder_rows(repo, folders, namespace=, parse=, keep=)`` is the one entry:

1. **One GraphQL call for the shape**: every folder's entries by name and blob
   sha (``repository.object(expression: "HEAD:<folder>")``). A folder that does
   not exist is absent, not an error.
2. **Nothing more for a sha already parsed.** ``parse`` turns a file's text into
   a small JSON-able dict, and that dict is kept on disk under the sha
   (``agent/core/disk_cache.py``), so an agent restart refetches nothing that has
   not changed.
3. **One GraphQL call for the texts of the shas that are new**, as aliased
   ``object(oid:)`` lookups, chunked at ``BLOB_CHUNK``. When the namespace has
   no rows at all (a new machine, a cleared cache) the shape call carries every
   text instead, so a cold listing is ONE call.
4. A blob whose ``text`` comes back null (binary, or past what GitHub inlines)
   falls back to the contents call for that one file, so correctness never
   depends on the batch.

The query travels in a file (``-F query=@<file>``) and every value as a ``-f`` /
``-F`` field, never in a URL and never as argv text the shell could split: the
agent runs ``gh`` through the shell on Windows, where an ``&`` is cmd's and a
newline ends the command (AGENTS.md, "On Windows the agent runs gh through the
shell").

Two options serve the Docs tab (``agent/ado/docs.py``), which lists a repository's
``README.md`` and the markdown under ``docs/`` and never needs a file's text:

- ``depth`` -- how many levels of subfolders to read, in the SAME call. The
  shape query nests ``entries`` to that depth (``object { ... on Tree {
  entries ... } }``), so a nested tree costs one call whatever its folders,
  where the contents route costs one per folder and the tree route walks the
  whole repository and truncates on a big one. A folder's entries then include
  every blob beneath it, by path. An int for every folder, or a mapping from
  folder to its depth; 1, the default, is the folder alone.
- ``parse=None`` -- names and shas only: no text is asked for, nothing is
  parsed, nothing is written to the disk cache. ``""`` as a folder is the
  repository root.

``file_text(repo, path, sha)`` is the detail read: one file's text, served from
the disk cache by its sha when the caller knows the sha and the body was read
before, fetched (and kept) otherwise.
"""

from __future__ import annotations

import base64
import json
import os
import re
import tempfile
import threading
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field

from ..core import disk_cache
from ..core.child import did_not_answer, run_read

GH_TIMEOUT_SECONDS = 30
# Aliased object(oid:) lookups per GraphQL call. 189 small notes answered in one
# 3.1 MB response when measured; a chunk this size keeps any one answer well
# under GitHub's limits for markdown.
BLOB_CHUNK = 100
# A blob's sha: SHA-1, or SHA-256 for a repository that uses it. Only a value of
# this shape is written into a query or used as a cache file's name.
_SHA = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
ROWS_DIR = "rows"
BODIES_DIR = "bodies"

_rows_lock = threading.Lock()


def _gh(args: list[str]):
    """One ``gh api`` call: (parsed JSON, None), or (None, why). A 404 is
    reported as the literal "not found" so a missing folder can read as empty."""
    cmd = ["gh", "api", *args]
    try:
        result = run_read(cmd, GH_TIMEOUT_SECONDS)
    except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
        return None, did_not_answer("gh", exc)
    if result.returncode != 0:
        err = (result.stderr or "").strip()
        if "404" in err or "Not Found" in err:
            return None, "not found"
        lines = err.splitlines()
        return None, lines[0] if lines else "gh returned an error"
    try:
        return json.loads(result.stdout or "null"), None
    except ValueError:
        return None, "gh answered with something that is not JSON"


def _graphql(query: str, fields: list[str]):
    """``gh api graphql`` with the query in a temporary file and the variables as
    fields: (the ``data`` object, None), or (None, why)."""
    fd, path = tempfile.mkstemp(prefix="p20-gql-", suffix=".graphql")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(query)
        out, why = _gh(["graphql", "-F", f"query=@{path}", *fields])
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    if why:
        return None, why
    data = out.get("data") if isinstance(out, dict) else None
    if not isinstance(data, dict):
        return None, "gh answered with no data"
    return data, None


def graphql_aliases(query: str, fields: list[str]) -> tuple[dict | None, dict[str, str], str | None]:
    """``gh api graphql`` for a query of aliased lookups, one of which may fail
    alone: (the ``data`` object, {alias: GitHub's message}, None), or (None, {},
    why) when the call itself did not answer.

    GitHub answers a query whose one ``repository(...)`` cannot be resolved with
    the other aliases' data AND an ``errors`` entry whose ``path`` names the
    failed alias; ``gh`` then exits 1 with that whole answer on stdout. So the
    answer is read from stdout whatever the exit code, and only an answer with no
    ``data`` is a failure of the call. The query travels in a file and every
    value as a field, as ``_graphql``'s does."""
    fd, path = tempfile.mkstemp(prefix="p20-gql-", suffix=".graphql")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(query)
        cmd = ["gh", "api", "graphql", "-F", f"query=@{path}", *fields]
        try:
            result = run_read(cmd, GH_TIMEOUT_SECONDS)
        except Exception as exc:  # noqa: BLE001 -- gh missing, the clock ran out, or its output unreadable: a reason, never a raise
            return None, {}, did_not_answer("gh", exc)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    try:
        out = json.loads(result.stdout or "null")
    except ValueError:
        out = None
    data = out.get("data") if isinstance(out, dict) else None
    if not isinstance(data, dict):
        if result.returncode == 0:
            return None, {}, "gh answered with no data"
        lines = (result.stderr or "").strip().splitlines()
        return None, {}, lines[0] if lines else "gh returned an error"
    errors: dict[str, str] = {}
    for err in out.get("errors") or []:
        where = (err or {}).get("path") or []
        if where and isinstance(where[0], str):
            errors.setdefault(where[0], str(err.get("message") or "gh returned an error"))
    return data, errors, None


def is_sha(value: str) -> bool:
    return bool(_SHA.match(value or ""))


# -- One file: the detail read --------------------------------------------------


def file_text(repo: str, path: str, sha: str = "") -> tuple[str | None, dict | None, str | None]:
    """(text, the contents entry, why-not) for one file.

    With a ``sha`` whose body was read before, the text comes from the disk cache
    and the contents entry is None: no call. Otherwise one ``gh api
    repos/{repo}/contents/{path}``, and the body is kept under the sha the
    answer names, for the next open."""
    if is_sha(sha):
        cached = disk_cache.get_text(BODIES_DIR, sha)
        if cached is not None:
            return cached, None, None
    row, why = _gh([f"repos/{repo}/contents/{path}"])
    if why:
        return None, None, why
    if not isinstance(row, dict) or row.get("type") != "file":
        return None, None, "not found"
    raw = row.get("content") or ""
    try:
        text = base64.b64decode(raw).decode("utf-8") if row.get("encoding", "base64") == "base64" else str(raw)
    except (ValueError, UnicodeDecodeError):
        return None, None, f"{path} is not UTF-8 text"
    if is_sha(row.get("sha", "")):
        disk_cache.put_text(text, BODIES_DIR, row["sha"])
    return text, row, None


# -- Folders: the listing read --------------------------------------------------


@dataclass
class Entry:
    name: str  # the file's name
    path: str  # folder/name, as the repository has it
    sha: str  # the blob's sha


@dataclass
class FolderRows:
    """What ``read_folder_rows`` answers. ``folders`` holds every folder that
    exists (an absent one is not a key), each with the entries ``keep`` let
    through in name order; ``rows`` is ``parse``'s dict for every one of those
    paths; ``url`` is ``https://github.com/<owner>/<repo>/blob/<default branch>``
    -- a file's page is ``url + "/" + path``. ``reason`` is the one sentence when
    the tracker did not answer, and then nothing else is filled."""

    folders: dict[str, list[Entry]] = field(default_factory=dict)
    rows: dict[str, dict] = field(default_factory=dict)
    shas: dict[str, str] = field(default_factory=dict)  # path -> sha
    url: str = ""
    repo_url: str = ""  # https://github.com/<owner>/<repo>
    has_issues: bool | None = None  # the repository's issues switch; None when GitHub did not say
    reason: str | None = None
    calls: int = 0  # gh calls this read made (the tests', and the log's)

    def file_url(self, path: str) -> str:
        return f"{self.url}/{path}" if self.url else ""


def _entries_block(depth: int, with_text: bool) -> str:
    """``entries { name type oid ... }`` nested ``depth`` levels. At depth 1 a
    blob's text rides in ``object`` when ``with_text``; deeper, ``object`` is a
    tree's next level and (with text) a blob's text, side by side."""
    blob = "... on Blob { text }"
    if depth <= 1:
        return "entries { name type oid" + (f" object {{ {blob} }}" if with_text else "") + " }"
    deeper = _entries_block(depth - 1, with_text)
    text = f" {blob}" if with_text else ""
    return f"entries {{ name type oid object {{{text} ... on Tree {{ {deeper} }} }} }}"


def _shape_query(n: int, with_text: bool, depths: list[int] | None = None) -> str:
    """The shape of ``n`` folders: entries by name, type and sha, and -- with
    ``with_text`` -- each blob's text; ``depths[i]`` levels of folder ``i``.
    Two queries rather than one with an ``@include``: asking for a blob's
    ``object`` at all makes GitHub load every blob, text or not -- measured on
    190 notes, 1.5 to 4 s against 0.55 s for names and shas alone -- so a warm
    read must not name it. (A nested read names ``object`` on every entry to
    reach the subfolders, and so pays some of that: 0.65 to 1.3 s for a
    four-level ``docs/`` against 0.4 to 0.6 s flat, in ONE call where the
    contents route made one per folder.)"""
    params = "".join(f", $f{i}: String!" for i in range(n))
    levels = depths or [1] * n
    parts = "\n".join(
        f"    f{i}: object(expression: $f{i}) {{ ... on Tree {{ {_entries_block(levels[i], with_text)} }} }}"
        for i in range(n)
    )
    return (
        f"query($owner: String!, $name: String!{params}) {{\n"
        f"  repository(owner: $owner, name: $name) {{\n"
        f"    url\n    hasIssuesEnabled\n    defaultBranchRef {{ name }}\n{parts}\n  }}\n}}\n"
    )


def _blob_query(shas: list[str]) -> str:
    parts = "\n".join(f'    b{i}: object(oid: "{sha}") {{ ... on Blob {{ text }} }}' for i, sha in enumerate(shas))
    return (
        f"query($owner: String!, $name: String!) {{\n  repository(owner: $owner, name: $name) {{\n{parts}\n  }}\n}}\n"
    )


def _owner_fields(repo: str) -> list[str]:
    owner, _, name = repo.partition("/")
    return ["-f", f"owner={owner}", "-f", f"name={name}"]


def _load_rows(namespace: str) -> dict[str, dict]:
    data = disk_cache.get_json(ROWS_DIR, f"{namespace}.json")
    rows = (data or {}).get("rows")
    return rows if isinstance(rows, dict) else {}


def _save_rows(namespace: str, new: dict[str, dict]) -> None:
    if not new:
        return
    with _rows_lock:
        rows = _load_rows(namespace)
        rows.update(new)
        disk_cache.put_json({"rows": rows}, ROWS_DIR, f"{namespace}.json")


def blob_texts(repo: str, entries: list[Entry], *, batch: bool = True) -> tuple[dict[str, str], int]:
    """({sha: text}, the number of gh calls) for these blobs: one GraphQL call per
    ``BLOB_CHUNK`` shas, and the contents call for any blob whose text came back
    null -- straight away with ``batch=False``, for blobs GraphQL has already
    answered null. A blob that still could not be read is missing from the answer."""
    texts: dict[str, str] = {}
    calls = 0
    wanted = [e for e in entries if is_sha(e.sha)]
    unique = list(dict.fromkeys(e.sha for e in wanted)) if batch else []
    for start in range(0, len(unique), BLOB_CHUNK):
        chunk = unique[start : start + BLOB_CHUNK]
        data, why = _graphql(_blob_query(chunk), _owner_fields(repo))
        calls += 1
        repo_data = (data or {}).get("repository") or {}
        for i, sha in enumerate(chunk):
            blob = repo_data.get(f"b{i}") or {}
            if isinstance(blob.get("text"), str):
                texts[sha] = blob["text"]
    for e in wanted:
        if e.sha in texts:
            continue
        text, _row, why = file_text(repo, e.path)
        calls += 1
        if text is not None and not why:
            texts[e.sha] = text
    return texts, calls


def _collect(
    rows: list, prefix: str, keep: Callable[[str], bool] | None, entries: list[Entry], inline: dict[str, str]
) -> None:
    """The blobs of one level of the shape answer, and -- where a row's
    ``object`` is a tree because ``depth`` asked for it -- the levels beneath."""
    for row in rows:
        name = str(row.get("name") or "")
        obj = row.get("object") or {}
        path = f"{prefix}/{name}" if prefix else name
        if row.get("type") == "tree":
            if isinstance(obj.get("entries"), list):
                _collect(obj["entries"], path, keep, entries, inline)
            continue
        if row.get("type") != "blob" or (keep is not None and not keep(name)):
            continue
        entry = Entry(name=name, path=path, sha=str(row.get("oid") or ""))
        entries.append(entry)
        if isinstance(obj.get("text"), str) and entry.sha:
            inline[entry.sha] = obj["text"]


def read_folder_rows(
    repo: str,
    folders: list[str],
    *,
    namespace: str = "",
    parse: Callable[[str], dict] | None = None,
    keep: Callable[[str], bool] | None = None,
    depth: int | Mapping[str, int] = 1,
) -> FolderRows:
    """Every file of ``folders`` in ``repo``'s default branch, parsed.

    ``namespace`` names the disk cache of parsed rows (one per reader, with a
    version in it: bump it when ``parse`` changes, and every row is parsed
    again); ``parse(text) -> dict`` must depend on the text alone, because a row
    is shared by every path whose blob has that sha; ``keep(name)`` picks the
    files (every blob when omitted). A blob whose text could not be read is
    parsed as "" and not kept, so the next read asks again.

    ``depth`` reads that many levels of subfolders in the same call (see the
    module doc): an int for every folder, or a mapping from folder to its depth
    (a folder not in it reads 1). ``parse=None`` reads names and shas only --
    ``rows`` stays empty and the disk cache is not touched."""
    names_only = parse is None
    cached = {} if names_only else _load_rows(namespace)
    with_text = not names_only and not cached
    fields = _owner_fields(repo)
    for i, folder in enumerate(folders):
        fields += ["-f", f"f{i}=HEAD:{folder}"]
    depths = [max(1, int(depth if isinstance(depth, int) else depth.get(f, 1))) for f in folders]
    data, why = _graphql(_shape_query(len(folders), with_text, depths), fields)
    out = FolderRows(calls=1)
    if why:
        out.reason = why
        return out
    repository = data.get("repository") or {}
    branch = (repository.get("defaultBranchRef") or {}).get("name") or "HEAD"
    out.url = f"{repository['url']}/blob/{branch}" if repository.get("url") else ""
    out.repo_url = str(repository.get("url") or "")
    flag = repository.get("hasIssuesEnabled")
    out.has_issues = flag if isinstance(flag, bool) else None
    inline: dict[str, str] = {}
    for i, folder in enumerate(folders):
        tree = repository.get(f"f{i}")
        if not isinstance(tree, dict) or not isinstance(tree.get("entries"), list):
            continue  # no such folder (or a file by that name): absent, not an error
        entries: list[Entry] = []
        _collect(tree["entries"], folder, keep, entries, inline)
        entries.sort(key=lambda e: e.path.lower())
        out.folders[folder] = entries

    every = [e for entries in out.folders.values() for e in entries]
    if parse is None:
        out.shas = {e.path: e.sha for e in every}
        return out
    missing = [e for e in every if e.sha not in cached and e.sha not in inline]
    texts = dict(inline)
    if missing:
        # In a cold read the shape call carried every text it could, so what is
        # missing came back null: the contents call, not a second GraphQL ask.
        fetched, calls = blob_texts(repo, missing, batch=not with_text)
        texts.update(fetched)
        out.calls += calls
    new: dict[str, dict] = {}
    for e in every:
        out.shas[e.path] = e.sha
        if e.sha in cached:
            out.rows[e.path] = cached[e.sha]
        elif e.sha in texts:
            row = new.get(e.sha) or parse(texts[e.sha])
            new[e.sha] = row
            out.rows[e.path] = row
        else:
            out.rows[e.path] = parse("")
    _save_rows(namespace, {sha: row for sha, row in new.items() if is_sha(sha)})
    return out
