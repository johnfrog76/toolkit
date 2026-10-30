"""GET /api/studio/prompts -- the agentic prompts, the Studio's Prompts card.

The prompts in the package's ``agentic/`` are ToolKit's: some a person opens in
their assistant, two the tools send to a model themselves (``pr-review`` behind
``AddPRReview``, ``pr-suggest`` behind the PR Comments page's Suggest). Their text
shapes what lands on a real tracker, so a person can read each one, see who sends
it and where it lives, and copy it into a chat. ``agentic/prompts.json`` is the
index: for each shipped prompt the ways of working it belongs to (``alone``,
``team``, ``agents`` -- the answers to How do you want to work?), who sends it,
its module and what it drives. ``Tests/test_agentic_index.py`` holds the index to
the folder.

Beside them, YOURS: the ``*.prompt.md`` files in the hub's own ``agentic/``
folder (``hub.json`` ``folders.agentic``) and in this machine's
``agenticExtensionPath``, where a copy under a shipped prompt's name runs
instead of the shipped one (Scripts/Resolve-AgenticPrompt.ps1). They have no
index entry, so they belong to every way of working.

Among yours, the active Space's HOW-WE-WORK NOTE when it has one: the file
``HowWeWork`` writes into the Space's folder in the hub (consts.json
``startWork.howWeWorkNote``) for a Space worked with agents, which ``StartWork``
quotes as how we work there. It is not a ``*.prompt.md`` -- it is the team's
own page, not a prompt -- so it is listed by that one path, under the name
``how-we-work``, beside the package's prompts, with ``agents`` as its way of
working. Absent, there is no row.

And the SPACE'S: the active Space names a repository by its address, not a
folder on this machine, so its own ``agentic/*.prompt.md`` is read the way the
Design tab reads ``design/`` -- through ``agent/ado/repo_read.py``'s
``read_folder_rows`` (one GraphQL call for the folder, the parsed rows kept on
disk by blob sha so an unchanged prompt is never fetched again), behind the same
``repo_gate`` (GitHub, Tier 1, an address that names one repo), cached in memory
for the same short TTL. Its text is read only by the one-prompt route, through
``repo_read.file_text`` (a body served from disk by its sha when read before).

The response says which Space it read (``space``) and whether
that Space is this package itself (``isToolkit``: its repository is the
package's own origin, so its folder is already the shipped set) -- the web
draws a third filter from that one answer and works out nothing. A Space with
no repository, an Azure Space, or an owner-grained address has no space rows.

ONE RECORD for every prompt, wherever it lives: ``title`` (the frontmatter's
``title``, else its one ``# `` heading, else the file name), ``purpose`` (the
frontmatter's ``description``), ``owner`` (``toolkit``, ``yours``, or the Space's
slug -- worked out here from where the file was read, never written in a file)
and ``category`` (a shipped prompt's from the index, any other's from its
frontmatter ``category`` line, ``uncategorized`` when it has none). The card's
row draws those four; the index's other fields stay on every row for the
reading room.

The Studio is core (D-S13): nothing here is gated by a flag of its own. A
shipped prompt that belongs to an add-on (``module`` in the index) follows that
add-on's flag -- off means absent, so it is not listed and its read is a 404 --
because it drives the add-on's verbs.

The list carries each prompt's record but not its text: ``body`` is served by
the one-prompt read alone (the list's route with a ``/{ref}`` after it), which
Copy prompt and the reading room call when asked.

Every route here is a READ. A prompt is changed in its file, by a person.
"""

from __future__ import annotations

import asyncio
import json
import re
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..ado.design import LIST_TTL_SECONDS, _front, parse_doc, repo_gate
from ..ado.repo_read import file_text, read_folder_rows
from ..core import log_writer
from ..core.config import (
    AGENTIC_DIR,
    AGENTIC_INDEX,
    API_PREFIX,
    PROMPT_SUFFIX,
    agentic_extension_path,
    hub_configured,
    hub_folder,
    hub_root,
    load_config,
)
from ..core.consts import repository_url, startwork_how_we_work_note, studio_prompts_route
from ..core.git_history import GITHUB_REMOTE as _GITHUB_REMOTE
from ..core.git_history import folder_history
from ..core.git_history import git_read as _git

api = APIRouter()

ROUTE = studio_prompts_route().removeprefix(API_PREFIX)

# The three groups, and the address segment that reads one: a shipped prompt is
# /studio/prompts/<name>, one of yours /studio/prompts/yours/<name>, the Space's
# /studio/prompts/space/<name>. The web never builds any -- it takes each row's ``ref``.
TOOLKIT = "toolkit"
YOURS = "yours"
SPACE = "space"
BY_HAND = "by hand"
CORE = "core"
# What a prompt with no category reads as -- the agent says it, the web draws it.
UNCATEGORIZED = "uncategorized"

# One prompt's name: the file's name before .prompt.md, no path.
_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

# The Space's folder, listed once per repo for the Design tab's TTL: its rows,
# and each row's blob sha by path (the one-prompt read's key to the body cache).
_space_cache: dict[str, tuple[float, list[PromptRow], dict[str, str]]] = {}

# The disk cache of parsed Space rows. Bump the number when ``_space_fields`` changes.
SPACE_ROWS_NAMESPACE = "prompts-rows-2"


def clear_cache() -> None:
    """Forget every cached Space folder (the tests' reset)."""
    _space_cache.clear()


class PromptRow(BaseModel):
    name: str = ""  # pr-ship
    ref: str = ""  # the address after /studio/prompts/: pr-ship, yours/bench-billing, or space/deck-contract
    group: str = TOOLKIT  # toolkit | yours | space
    path: str = ""  # where it lives: agentic/pr-ship.prompt.md, or your folder's
    file_path: str = ""  # the absolute path, for the reading room's File line; the Space's file's address on GitHub
    title: str = ""  # the frontmatter's `title`, else the first `# ` heading, else the name
    description: str = ""  # the frontmatter's `description`, "" when none
    purpose: str = ""  # the same sentence, under the record's name for it
    owner: str = TOOLKIT  # toolkit | yours | the Space's slug -- from where the file lives
    category: str = UNCATEGORIZED  # the index's (shipped), else the frontmatter's `category`
    workflows: list[str] = []  # the index's; [] for one of yours -- every way of working
    sender: str = ""  # 'by hand', else the verb or route that sends it; "" for yours
    by_hand: bool = True
    module: str = CORE
    drives: str = ""
    overrides: bool = False  # yours, in agenticExtensionPath, under a shipped name: it runs instead
    changed: str = ""  # the local day it last changed (git, else the file's time)
    history: str = ""  # its history on GitHub, "" when the folder is not a GitHub clone
    body: str = ""  # the whole file: what Copy prompt copies -- the one-prompt read serves it, never the list


class SpaceInfo(BaseModel):
    """Which Space the list was read for: its slug, name and repository
    (``owner/name``, "" when the address names none), and whether that
    repository is this package's own origin -- then its ``agentic/`` is the
    shipped set already, and there are no space rows."""

    slug: str = ""
    name: str = ""
    repo: str = ""
    isToolkit: bool = False


class PromptsResponse(BaseModel):
    count: int = 0
    prompts: list[PromptRow] = []
    space: SpaceInfo = SpaceInfo()
    # The index's category vocabulary, in its order: the card's category row
    # draws them in this order, and any category outside it after them.
    categories: list[str] = []


def record(text: str, name: str) -> tuple[str, str, str]:
    """(title, purpose, frontmatter category) from one prompt's text: the one
    reader every group goes through."""
    front, _ = _front(text)
    title, description, *_ = parse_doc(text, name)
    return front.get("title") or title, description, front.get("category", "").strip().lower()


def read_index() -> dict[str, dict]:
    """agentic/prompts.json's entries by name; {} when the file is unreadable."""
    try:
        return dict(json.loads(AGENTIC_INDEX.read_text(encoding="utf-8-sig")).get("prompts") or {})
    except (OSError, ValueError):
        return {}


def read_categories() -> list[str]:
    """agentic/prompts.json's ``categories``, in the file's order; [] when unreadable."""
    try:
        found = json.loads(AGENTIC_INDEX.read_text(encoding="utf-8-sig")).get("categories") or []
    except (OSError, ValueError):
        return []
    return [str(c) for c in found]


def _modified(path: Path) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(path.stat().st_mtime))


def _files(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    return sorted(
        (p for p in folder.iterdir() if p.is_file() and p.name.endswith(PROMPT_SUFFIX) and _NAME.match(stem(p.name))),
        key=lambda p: p.name.lower(),
    )


def stem(file_name: str) -> str:
    return file_name.removesuffix(PROMPT_SUFFIX)


def _label(folder: Path) -> str:
    """Where a folder of yours lives, as a person names it: hub-relative when it
    is inside the hub, else its absolute path."""
    if hub_configured():
        try:
            return folder.resolve().relative_to(hub_root().resolve()).as_posix()
        except ValueError:
            pass
    return str(folder)


def yours_folders() -> list[tuple[Path, bool]]:
    """(folder, is the extension folder) for each folder of yours that exists:
    agenticExtensionPath first -- its copy is the one that runs -- then the
    hub's agentic/ when it is a different folder."""
    out: list[tuple[Path, bool]] = []
    ext = agentic_extension_path()
    if ext is not None:
        out.append((ext, True))
    if hub_configured():
        hub = hub_folder("agentic")
        if hub.is_dir() and (ext is None or hub.resolve() != ext):
            out.append((hub.resolve(), False))
    return out


def module_on(module: str, features: dict) -> bool:
    return module == CORE or bool(features.get(module, False))


def _row(path: Path, group: str, where: str, history: tuple[dict, str], name: str = "", **extra) -> PromptRow:
    text = path.read_text(encoding="utf-8-sig")
    name = name or stem(path.name)
    title, purpose, category = record(text, name)
    extra.setdefault("category", category or UNCATEGORIZED)
    changes, base = history
    day, sha = changes.get(path.name, ("", ""))
    return PromptRow(
        name=name,
        ref=name if group == TOOLKIT else f"{YOURS}/{name}",
        group=group,
        path=f"{where}/{path.name}",
        file_path=str(path),
        title=title,
        description=purpose,
        purpose=purpose,
        owner=group,
        changed=day or _modified(path),
        history=base.format(sha=sha) + path.name if base and sha else "",
        body=text,
        **extra,
    )


def shipped_rows(features: dict) -> list[PromptRow]:
    index = read_index()
    history = folder_history(AGENTIC_DIR)
    rows: list[PromptRow] = []
    for path in _files(AGENTIC_DIR):
        entry = index.get(stem(path.name)) or {}
        module = str(entry.get("module") or CORE)
        if not module_on(module, features):
            continue
        sender = str(entry.get("sender") or BY_HAND)
        rows.append(
            _row(
                path,
                TOOLKIT,
                AGENTIC_DIR.name,
                history,
                workflows=[str(w) for w in entry.get("workflows") or []],
                sender=sender,
                by_hand=sender == BY_HAND,
                module=module,
                drives=str(entry.get("drives") or ""),
                category=str(entry.get("category") or UNCATEGORIZED),
            )
        )
    return rows


# The how-we-work note's row name: its file's name before .md, and the reading
# room's address after yours/.
HOW_WE_WORK = "how-we-work"
# The one way of working the note belongs to: only the orchestrating answer has one.
HOW_WE_WORK_WORKFLOW = "agents"


def how_we_work_note() -> Path | None:
    """The active Space's how-we-work note -- ``startWork.howWeWorkNote`` under the
    Space's folder in the hub -- or None when no hub is configured or the file
    is not there. The verb that writes it is ``HowWeWork``; nothing here writes."""
    if not hub_configured():
        return None
    root = hub_root()
    folder = str(load_config().get("promptsFolder") or "")
    note = (root / folder if folder else root) / startwork_how_we_work_note()
    return note if note.is_file() else None


def how_we_work_row() -> PromptRow | None:
    note = how_we_work_note()
    if note is None:
        return None
    return _row(
        note,
        YOURS,
        _label(note.parent),
        folder_history(note.parent),
        name=HOW_WE_WORK,
        workflows=[HOW_WE_WORK_WORKFLOW],
        sender="",
        by_hand=True,
    )


def yours_rows(shipped: set[str]) -> list[PromptRow]:
    rows: list[PromptRow] = []
    seen: set[str] = set()
    for folder, is_extension in yours_folders():
        history = folder_history(folder)
        where = _label(folder)
        for path in _files(folder):
            name = stem(path.name)
            if name in seen:
                continue  # the extension folder's copy is the one that runs
            seen.add(name)
            rows.append(
                _row(path, YOURS, where, history, sender="", by_hand=True, overrides=is_extension and name in shipped)
            )
    note = how_we_work_row()
    if note is not None and note.name not in seen:
        rows.append(note)
    return rows


def package_repo() -> str:
    """``owner/name`` of this package's own repository: its git origin on GitHub
    -- the same read ``folder_history`` makes for a shipped row's history -- and,
    when there is none to read (a copy installed without ``.git``), the shipped
    address in consts.json. The origin wins when it is there, so a fork that
    makes itself a Space reads as the fork; "" when neither names GitHub."""
    origin = (_git(["remote", "get-url", "origin"], AGENTIC_DIR) or "").strip()
    for address in (origin, repository_url()):
        m = _GITHUB_REMOTE.search(address)
        if m:
            return f"{m.group(1)}/{m.group(2)}"
    return ""


def space_info(cfg: dict, repo: str | None) -> SpaceInfo:
    """The active Space as the response names it. ``repo`` is what the gate
    allowed (None when it did not); ``isToolkit`` compares it with the package's
    own origin, case ignored -- GitHub reads ``owner/name`` that way."""
    slug = str(cfg.get("activeSpace") or "")
    entry = next((s for s in cfg.get("spaces") or [] if s.get("slug") == slug), {})
    return SpaceInfo(
        slug=slug,
        name=str(entry.get("name") or slug),
        repo=repo or "",
        isToolkit=bool(repo) and repo.lower() == package_repo().lower(),
    )


def _space_fields(text: str) -> dict:
    """What a Space row needs from a prompt's TEXT ALONE (the disk cache keeps
    this by blob sha, so it may not depend on the file's name): the heading or
    frontmatter title ("" when there is none -- the name stands in at build
    time), the purpose and the category."""
    title, purpose, category = record(text, "")
    return {"title": title, "purpose": purpose, "category": category}


def _space_row(name: str, path: str, url: str, fields: dict) -> PromptRow:
    return PromptRow(
        name=name,
        ref=f"{SPACE}/{name}",
        group=SPACE,
        path=path,
        file_path=url,
        title=fields.get("title") or name,
        description=fields.get("purpose", ""),
        purpose=fields.get("purpose", ""),
        owner=SPACE,
        category=fields.get("category") or UNCATEGORIZED,
        sender="",
        by_hand=True,
    )


def _space_folder(repo: str) -> tuple[list[PromptRow], dict[str, str]]:
    """(the Space's rows, each path's blob sha), cached per repo. No such folder
    is empty, cached; a repo gh cannot read is empty too, said in the log and not
    cached -- never a refused card."""
    hit = _space_cache.get(repo)
    if hit and time.monotonic() - hit[0] < LIST_TTL_SECONDS:
        return hit[1], hit[2]
    folder = AGENTIC_DIR.name
    read = read_folder_rows(
        repo,
        [folder],
        namespace=SPACE_ROWS_NAMESPACE,
        parse=_space_fields,
        keep=lambda n: n.endswith(PROMPT_SUFFIX) and bool(_NAME.match(stem(n))),
    )
    if read.reason:
        log_writer.write_log("ERR", "agent/studio", f"{repo}/{folder}: {read.reason}")
        return [], {}  # not cached: the next read asks again
    rows = [
        _space_row(stem(e.name), e.path, read.file_url(e.path), read.rows.get(e.path) or {})
        for e in read.folders.get(folder, [])
    ]
    _space_cache[repo] = (time.monotonic(), rows, read.shas)
    return rows, read.shas


def space_rows(repo: str) -> list[PromptRow]:
    """The Space's own ``agentic/*.prompt.md`` -- records without their text."""
    return _space_folder(repo)[0]


async def gated_space_repo() -> str | None:
    """The active Space's repo when the Design tab's gate lets it be read,
    else None. The gate's stated refusal of an owner-grained address is, here,
    simply no third group -- a prompt list is never a 400."""
    try:
        return await repo_gate()
    except HTTPException:
        return None


def owned_by(rows: list[PromptRow], slug: str) -> list[PromptRow]:
    """The Space's rows with the Space's slug as their owner: the folder is
    cached per repository, the owner is the Space that read it."""
    return [r.model_copy(update={"owner": slug or SPACE}) for r in rows]


def list_prompts(repo: str | None = None) -> PromptsResponse:
    cfg = load_config()
    features = cfg.get("features") or {}
    shipped = shipped_rows(features)
    rows = shipped + yours_rows({stem(p.name) for p in _files(AGENTIC_DIR)})
    space = space_info(cfg, repo)
    if space.repo and not space.isToolkit:
        rows += owned_by(space_rows(space.repo), space.slug)
    return PromptsResponse(count=len(rows), prompts=rows, space=space, categories=read_categories())


def _absent(ref: str) -> HTTPException:
    return HTTPException(
        status_code=404,
        detail=(
            f"No prompt {ref} -- a prompt is one <name>{PROMPT_SUFFIX} in agentic/, in your hub's, "
            "or in the Space's repository."
        ),
    )


def read_prompt(ref: str, repo: str | None = None) -> PromptRow:
    group, _, name = ref.rpartition("/")
    if group not in ("", YOURS, SPACE) or not _NAME.match(name):
        raise _absent(ref)
    if group == SPACE:
        space = space_info(load_config(), repo)
        rows = []
        if space.repo and not space.isToolkit:
            found_rows, shas = _space_folder(space.repo)
            rows = owned_by(found_rows, space.slug)
            row = next((r for r in rows if r.name == name), None)
            if row is not None:
                text, _entry, why = file_text(space.repo, row.path, shas.get(row.path, ""))
                if why:
                    log_writer.write_log("ERR", "agent/studio", f"{space.repo}/{row.path}: {why}")
                    raise _absent(ref)
                rows = [row.model_copy(update={"body": text or ""})]
    elif group == YOURS:
        rows = yours_rows({stem(p.name) for p in _files(AGENTIC_DIR)})
    else:
        if not (AGENTIC_DIR / f"{name}{PROMPT_SUFFIX}").is_file():
            raise _absent(ref)
        entry = read_index().get(name) or {}
        module = str(entry.get("module") or CORE)
        if not module_on(module, load_config().get("features") or {}):
            raise HTTPException(
                status_code=404,
                detail=(
                    f"{name} belongs to the {module} module, which is not enabled. "
                    f"Set features.{module} in config.local.json."
                ),
            )
        rows = shipped_rows(load_config().get("features") or {})
    found = next((r for r in rows if r.name == name), None)
    if found is None:
        raise _absent(ref)
    return found


# The list is the card's rows; the text of every prompt is not in it. A row's
# body is read on demand (GET .../{ref}) when Copy prompt or the reading room
# asks, so the list stays a few KB however long the prompts are.
LIST_EXCLUDES = {"prompts": {"__all__": {"body"}}}


@api.get(ROUTE, response_model=PromptsResponse, response_model_exclude=LIST_EXCLUDES)
async def get_prompts():
    # The gate is asked first, so a Space that is not GitHub, not Tier 1 or not
    # one repo never reaches gh; the folders on disk are read as before.
    repo = await gated_space_repo()
    resp = await asyncio.to_thread(list_prompts, repo)
    yours = sum(1 for p in resp.prompts if p.group == YOURS)
    space = sum(1 for p in resp.prompts if p.group == SPACE)
    log_writer.write_log(
        "CMD",
        "agent/studio",
        f"{resp.count - yours - space} shipped prompts, {yours} of yours, {space} of the Space's ({resp.space.repo})",
    )
    return resp


@api.get(ROUTE + "/{ref:path}", response_model=PromptRow)
async def get_prompt(ref: str):
    repo = await gated_space_repo() if ref.startswith(f"{SPACE}/") else None
    return await asyncio.to_thread(read_prompt, ref, repo)
