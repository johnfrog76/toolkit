"""GET /api/ritual/org -- the org chart, read from the hub's org file (Team Agile).

The contract is docs/hub/org.md. Two readers implement it -- this file and the
CLI's ``Scripts/Read-OrgChart.ps1`` (the ``OrgChart`` verb) -- and one table
holds them to each other: ``Tests/fixtures/org/table.json`` and the responses
beside it, asserted from ``Tests/test_org.py`` and ``tkTestToolkit -OrgChart``.
The ``kind`` of a failure is the contract; the sentence is the CLI's wording.

Three layers, so the rule is testable without a hub:

- ``read_org_chart`` -- PURE over the file's text and a test of whether a
  prompt name is in any of the folders a role is looked up in. The same checks
  in the same order, the same tolerance of an unknown key (said, never
  refused), the same derived seat ``state``, the
  positions in tree order with their ``level``. It never raises.
- ``find_org_chart`` -- the hub layer: where the file is, whether a hub was
  named at all, and the folders a position's prompt is looked up in
  (``prompt_dirs``: the hub's agentic/org/, the hub's agentic/, the toolkit's
  agentic/org/).
- the route -- the thin layer: ``find_org_chart`` plus each position's prompt
  as the Studio's reading room knows it (``promptTitle``, ``promptRef``), taken
  through ``agent/studio/prompts.py``'s one record, never a second parser.

The route is a READ and the file is hand-edited: nothing here writes.
"""

from __future__ import annotations

import asyncio
import json
import math
import re
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from ..core import log_writer
from ..core.config import API_PREFIX, ORG_PRESETS_DIR, hub_configured, hub_folder, hub_root
from ..core.consts import org_file, org_roles_folder, rituals_org_presets_route, rituals_org_route
from ..studio import prompts
from .standup import api

ROUTE = rituals_org_route().removeprefix(API_PREFIX)
PRESETS_ROUTE = rituals_org_presets_route().removeprefix(API_PREFIX)

# The kinds the reader's callers add to the file's own (docs/hub/org.md, "What is checked").
KIND_NO_HUB = "no-hub"
KIND_MISSING = "missing"
KIND_UNKNOWN_TREE = "unknown-tree"

# What a key may be, level by level: anything else is said and ignored.
_KNOWN_KEYS = {
    "top": ("activeTree", "trees"),
    "tree": ("id", "name", "machines", "positions"),
    "position": ("id", "title", "prompt", "reportsTo", "defaultModel", "seats"),
    "seat": ("id", "model", "person", "machine", "space", "active"),
}

_PATH_SEPARATOR = re.compile(r"[\\/]")


@dataclass
class OrgResult:
    """What a read found. ``status`` is ``ok`` (``chart`` is the response),
    ``missing`` or ``invalid`` (``kind`` and ``message`` say what is wrong)."""

    status: str
    kind: str = ""
    message: str = ""
    warnings: list[str] = field(default_factory=list)
    active_tree: str = ""
    chart: dict | None = None
    seat_count: int = 0
    path: str = ""


# -- Reading a field the way the CLI's reader does -----------------------------


def _field(obj: Any, name: str) -> Any:
    """One field of a JSON object by its exact spelling; None when absent or
    when ``obj`` is not an object."""
    return obj.get(name) if isinstance(obj, dict) else None


def _text(value: Any) -> str:
    """A field as text: a string or a number is its trimmed text, anything else
    (absent, null, an object, an array, a boolean) is ''."""
    if isinstance(value, bool) or value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isfinite(value) and value.is_integer() and abs(value) < 1e15:
            return str(int(value))
        return repr(value)
    return ""


def _items(value: Any) -> list:
    """The elements of a JSON array field; a field that is not an array holds none."""
    return value if isinstance(value, list) else []


# -- Reading the document ------------------------------------------------------


def _warnings(data: dict, file_name: str) -> list[str]:
    """An unknown key is tolerated, like hub.json's: ignored, and said once. A
    key that starts with an underscore is a note and is never said."""
    found: list[str] = []

    def check(obj: Any, level: str, where: str) -> None:
        if not isinstance(obj, dict):
            return
        for key in obj:
            if key.startswith("_") or key in _KNOWN_KEYS[level]:
                continue
            found.append(f"{file_name}: '{key}' is not a key this tool reads{where} -- ignored.")

    check(data, "top", "")
    for tree in _items(_field(data, "trees")):
        tree_id = _text(_field(tree, "id"))
        check(tree, "tree", f" in tree '{tree_id}'")
        for position in _items(_field(tree, "positions")):
            position_id = _text(_field(position, "id"))
            check(position, "position", f" in position '{position_id}' of tree '{tree_id}'")
            for seat in _items(_field(position, "seats")):
                seat_id = _text(_field(seat, "id"))
                check(seat, "seat", f" in seat '{seat_id}' of position '{position_id}' in tree '{tree_id}'")
    return found


def _model(data: dict) -> tuple[list[dict] | None, tuple[str, str] | None]:
    """The document as plain trees -> positions -> seats, or the first entry
    with no id in document order: ``(trees, None)`` or ``(None, (kind, message))``."""
    trees: list[dict] = []
    for t_index, tree in enumerate(_items(_field(data, "trees")), start=1):
        tree_id = _text(_field(tree, "id"))
        if not tree_id:
            return None, ("missing-id", f"Tree {t_index} has no id.")
        machines = [m for m in (_text(x) for x in _items(_field(tree, "machines"))) if m]
        positions: list[dict] = []
        for p_index, position in enumerate(_items(_field(tree, "positions")), start=1):
            position_id = _text(_field(position, "id"))
            if not position_id:
                return None, ("missing-id", f"Position {p_index} of tree '{tree_id}' has no id.")
            seats: list[dict] = []
            for s_index, seat in enumerate(_items(_field(position, "seats")), start=1):
                seat_id = _text(_field(seat, "id"))
                if not seat_id:
                    return None, (
                        "missing-id",
                        f"Seat {s_index} of position '{position_id}' in tree '{tree_id}' has no id.",
                    )
                raw_active = _field(seat, "active")
                seats.append(
                    {
                        "id": seat_id,
                        "model": _text(_field(seat, "model")),
                        "person": _text(_field(seat, "person")),
                        "machine": _text(_field(seat, "machine")),
                        "space": _text(_field(seat, "space")),
                        "active": raw_active if isinstance(raw_active, bool) else None,
                    }
                )
            positions.append(
                {
                    "id": position_id,
                    "title": _text(_field(position, "title")) or position_id,
                    "prompt": _text(_field(position, "prompt")),
                    "reportsTo": _text(_field(position, "reportsTo")),
                    "defaultModel": _text(_field(position, "defaultModel")),
                    "seats": seats,
                }
            )
        trees.append(
            {
                "id": tree_id,
                "name": _text(_field(tree, "name")) or tree_id,
                "machines": machines,
                "positions": positions,
            }
        )
    return trees, None


def _first_duplicate(ids: list[str]) -> str:
    seen: set[str] = set()
    for one in ids:
        if one in seen:
            return one
        seen.add(one)
    return ""


def prompt_places(agentic_folder: str) -> str:
    """The three folders a position's prompt is looked up in, as the
    unknown-prompt sentence names them -- the CLI's words exactly."""
    roles = org_roles_folder()
    return (
        f"the hub's {agentic_folder}/{roles}/ or {agentic_folder}/ folder "
        f"or the toolkit's {prompts.AGENTIC_DIR.name}/{roles}/"
    )


def _check_tree(tree: dict, prompt_exists: Callable[[str], bool], agentic_folder: str) -> tuple[str, str] | None:
    """One tree's rules, in a fixed order, the first broken one a failure: a
    position or seat id used twice, a reportsTo that names nothing, a loop, not
    exactly one root, a prompt that is in none of the folders a role is looked
    up in."""
    tree_id = tree["id"]
    positions = tree["positions"]
    dup = _first_duplicate([p["id"] for p in positions])
    if dup:
        return "duplicate-position", f"Two positions in tree '{tree_id}' share the id '{dup}'."
    for position in positions:
        dup = _first_duplicate([s["id"] for s in position["seats"]])
        if dup:
            return (
                "duplicate-seat",
                f"Two seats in position '{position['id']}' of tree '{tree_id}' share the id '{dup}'.",
            )
    by_id = {p["id"]: p for p in positions}
    for position in positions:
        if position["reportsTo"] and position["reportsTo"] not in by_id:
            return (
                "unknown-reports-to",
                (
                    f"Position '{position['id']}' in tree '{tree_id}' reports to '{position['reportsTo']}', "
                    "which is not a position in that tree."
                ),
            )
    # A loop: walk up from each position, in file order; the first chain that
    # meets itself names the loop from the position where it closes.
    for position in positions:
        path: list[str] = []
        current: dict | None = position
        while current is not None:
            if current["id"] in path:
                loop = path[path.index(current["id"]) :] + [current["id"]]
                return "cycle", f"Positions in tree '{tree_id}' report to each other in a loop: {' -> '.join(loop)}."
            path.append(current["id"])
            current = by_id[current["reportsTo"]] if current["reportsTo"] else None
    roots = [p["id"] for p in positions if not p["reportsTo"]]
    if not roots:
        return "no-root", f"Tree '{tree_id}' has no root: exactly one position reports to nobody."
    if len(roots) > 1:
        return (
            "several-roots",
            f"Tree '{tree_id}' has {len(roots)} roots ({', '.join(roots)}): exactly one position reports to nobody.",
        )
    for position in positions:
        name = position["prompt"]
        if not name:
            continue
        is_name = not _PATH_SEPARATOR.search(name) and name not in (".", "..")
        if not (is_name and prompt_exists(name)):
            return (
                "unknown-prompt",
                (
                    f"Position '{position['id']}' in tree '{tree_id}' names the prompt '{name}', "
                    f"which is not a file in {prompt_places(agentic_folder)}."
                ),
            )
    return None


def _chart(tree: dict, active_tree: str) -> dict:
    """One validated tree as the response (docs/hub/org.md, "The response"): its
    positions in tree order -- the root, then each position's reports in file
    order, depth first -- each with its level and its seats' derived state."""
    children: dict[str, list[dict]] = {}
    root: dict | None = None
    for position in tree["positions"]:
        if not position["reportsTo"]:
            root = position
        else:
            children.setdefault(position["reportsTo"], []).append(position)
    ordered: list[dict] = []
    stack: list[tuple[dict, int]] = [(root, 0)] if root else []
    while stack:
        position, level = stack.pop()
        seats = [
            {
                "id": s["id"],
                "model": s["model"] or None,
                "person": s["person"] or None,
                "machine": s["machine"] or None,
                "space": s["space"] or None,
                "active": s["active"],
                "state": "staffed" if (s["model"] or s["person"]) else "vacant",
            }
            for s in position["seats"]
        ]
        ordered.append(
            {
                "id": position["id"],
                "title": position["title"],
                "prompt": position["prompt"] or None,
                "reportsTo": position["reportsTo"] or None,
                "defaultModel": position["defaultModel"] or None,
                "level": level,
                "seats": seats,
            }
        )
        for child in reversed(children.get(position["id"], [])):
            stack.append((child, level + 1))
    return {
        "activeTree": active_tree,
        "tree": {"id": tree["id"], "name": tree["name"], "machines": list(tree["machines"]), "positions": ordered},
    }


def _no_constant(name: str):
    raise ValueError(f"{name} is not valid JSON")


def read_org_chart(
    text: str,
    prompt_exists: Callable[[str], bool],
    agentic_folder: str = "agentic",
    tree_id: str = "",
    file_name: str = "",
) -> OrgResult:
    """The org chart in ``text`` (the file's contents), for the tree in use or
    ``tree_id``. ``prompt_exists`` says whether a name is a file in any of the
    folders a role is looked up in (``prompt_dirs``); ``agentic_folder`` is the
    hub's agentic folder's name, for the sentence. Never raises."""
    file_name = file_name or org_file()
    try:
        data = json.loads(text.lstrip("﻿"), parse_constant=_no_constant)
    except ValueError as e:
        return OrgResult("invalid", "unreadable", f"{file_name} is not valid JSON ({e}).")
    if not isinstance(data, dict):
        return OrgResult("invalid", "unreadable", f"{file_name} must be a JSON object at the top level.")

    warnings = _warnings(data, file_name)

    def fail(kind: str, message: str) -> OrgResult:
        return OrgResult("invalid", kind, message, warnings)

    raw_trees = _field(data, "trees")
    if not isinstance(raw_trees, list) or not raw_trees:
        return fail("no-trees", f"{file_name} has no trees: 'trees' must be an array with at least one tree.")
    trees, failure = _model(data)
    if failure:
        return fail(*failure)
    assert trees is not None

    tree_ids = [t["id"] for t in trees]
    dup = _first_duplicate(tree_ids)
    if dup:
        return fail("duplicate-tree", f"Two trees share the id '{dup}'.")

    active = _text(_field(data, "activeTree"))
    if not active:
        if len(trees) != 1:
            return fail(
                "no-active-tree",
                f"'activeTree' is not set and {file_name} has {len(trees)} trees ({', '.join(tree_ids)}): "
                "name the one in use.",
            )
        active = trees[0]["id"]
    if active not in tree_ids:
        return fail(
            "unknown-active-tree", f"'activeTree' names '{active}', which is not a tree. Trees: {', '.join(tree_ids)}."
        )

    for tree in trees:
        broken = _check_tree(tree, prompt_exists, agentic_folder)
        if broken:
            return fail(*broken)

    chosen = active
    if tree_id:
        if tree_id not in tree_ids:
            return fail(
                KIND_UNKNOWN_TREE,
                f"-Tree names '{tree_id}', which is not a tree in {file_name}. Trees: {', '.join(tree_ids)}.",
            )
        chosen = tree_id
    picked = next(t for t in trees if t["id"] == chosen)
    chart = _chart(picked, active)
    seat_count = sum(len(p["seats"]) for p in chart["tree"]["positions"])
    return OrgResult("ok", warnings=warnings, active_tree=active, chart=chart, seat_count=seat_count)


# -- The hub -------------------------------------------------------------------


def prompt_dirs() -> list[Path]:
    """Where a position's prompt is looked for, in order (docs/hub/org.md,
    "Where a position's prompt is found"): the hub's agentic/org/, the hub's
    agentic/ as it has always been read, then the toolkit's own agentic/org/.
    The first that has the file wins, so a hub's own role under a shipped name
    is the one used. The CLI's ``Get-P20OrgPromptDirs`` is the same list."""
    agentic = hub_folder("agentic")
    return [agentic / org_roles_folder(), agentic, prompts.shipped_roles_dir()]


def find_prompt(file_name: str) -> Path | None:
    """The first folder's copy of a prompt file NAME, or None."""
    for folder in prompt_dirs():
        path = folder / file_name
        if path.is_file():
            return path
    return None


def find_org_chart(tree_id: str = "") -> OrgResult:
    """Read the chart from the hub the agent resolved. ``no-hub`` when nobody
    said where the hub is ("the hub resolved" is not "a hub was configured"),
    ``missing`` when there is no file at its root -- a hub that is not there
    (an unplugged drive) is the same answer, as the CLI's reader gives it."""
    if not hub_configured():
        return OrgResult("missing", KIND_NO_HUB, f"No hub is configured, so there is no {org_file()} to read.")
    root = hub_root()
    path = root / org_file()
    if not root.is_dir() or not path.is_file():
        return OrgResult("missing", KIND_MISSING, f"There is no {org_file()} in the hub.", path=str(path))
    try:
        text = path.read_bytes().decode("utf-8", errors="replace")
    except OSError as e:
        return OrgResult("invalid", "unreadable", f"{org_file()} is not readable ({e}).", path=str(path))

    def prompt_exists(name: str) -> bool:
        return find_prompt(name) is not None

    result = read_org_chart(text, prompt_exists, hub_folder("agentic").name, tree_id.strip())
    result.path = str(path)
    return result


# -- Each position's prompt, as the reading room knows it -----------------------


def prompt_fields(file_name: str) -> tuple[str | None, str | None]:
    """(title, ref) of a position's prompt: ``prompts.record``'s title -- the
    front matter's ``title``, else the one ``#`` heading, else the file's name --
    and the reading-room reference the Studio's own rows carry
    (``yours/<name>`` for one of yours, ``<name>`` for the toolkit's). The file
    read is the one the room opens: the machine's extension folder's copy first,
    then the lookup's order (``prompt_dirs``) -- the hub's roles, the hub's
    agentic folder, the toolkit's roles. A file the room does not list (not
    ``<name>.prompt.md``) has a title and no ref."""
    if not file_name:
        return None, None
    name = prompts.stem(file_name)
    shipped = prompts.shipped_roles_dir()
    folders = [folder for folder, _ in prompts.yours_folders()]
    folders += prompt_dirs()
    text = ""
    found: Path | None = None
    for folder in folders:
        path = folder / file_name
        if path.is_file():
            try:
                text = path.read_text(encoding="utf-8-sig")
            except OSError:
                continue
            found = folder
            break
    title = prompts.record(text, name)[0] if text else name
    ref = None
    if prompts.listed(file_name):
        ref = name if found == shipped else f"{prompts.YOURS}/{name}"
    return title or name, ref


def with_prompts(chart: dict) -> dict:
    """The chart with ``promptTitle`` and ``promptRef`` on every position: both
    null for a position with no prompt."""
    for position in chart["tree"]["positions"]:
        position["promptTitle"], position["promptRef"] = prompt_fields(position["prompt"] or "")
    return chart


def _refusal(result: OrgResult) -> HTTPException:
    """The answer to a read that found no chart. Absent is 404 (the hub has no
    file, or names none), a file that fails its checks is 409 -- the request is
    fine, the stored file conflicts -- and a ``tree`` the file does not have is
    422, as ``standup``'s ``since`` is. Every detail is ``{kind, message}``."""
    if result.status == "missing":
        code = 404
    elif result.kind == KIND_UNKNOWN_TREE:
        code = 422
    else:
        code = 409
    return HTTPException(status_code=code, detail={"kind": result.kind, "message": result.message})


def org_chart(tree: str = "") -> dict:
    result = find_org_chart(tree)
    for warning in result.warnings:
        log_writer.write_log("WARN", f"agent{ROUTE}", warning)
    if result.status != "ok" or result.chart is None:
        log_writer.write_log("ERR", f"agent{ROUTE}", f"{result.kind}: {result.message}")
        raise _refusal(result)
    chart = with_prompts(result.chart)
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"tree={chart['tree']['id']} positions={len(chart['tree']['positions'])} seats={result.seat_count}",
    )
    return chart


@api.get(ROUTE)
async def get_org(tree: str = "") -> dict:
    # The gate is the router's (Team Agile, per request). The file is the
    # engineer's, so there is no ``space``: the Space only decides whether the
    # module is on. ``tree`` asks for another tree of the file, as -Tree does.
    return await asyncio.to_thread(org_chart, tree)


# -- The presets ------------------------------------------------------------------
#
# docs/hub/org.md, "Org presets": three starting orgs the toolkit ships in
# samples/org-presets/, each ONE tree in org.json's shape plus what it is
# called and what it fits. The route serves them for the Org tab to preview;
# nothing here writes, and a preset never reaches a hub. A preset's own fields
# are read by name and anything else is ignored without a word, so a later
# field (the swag, the ways of working) reads fine in a reader that predates it.

# The fields a preset carries beside its tree, in the order the response lists them.
PRESET_FIELDS = ("id", "size", "title", "shortDescription", "description", "teamSize")


def read_preset(text: str, prompt_exists: Callable[[str], bool], file_name: str = "") -> dict | None:
    """One preset file's text as ``{id, size, title, shortDescription,
    description, teamSize, chart}``, or None when it is not a preset whose tree
    passes every check ``read_org_chart`` makes. The tree is the preset's
    ``positions`` under its ``id``, named by its ``title``; a position's or a
    seat's unknown key is ignored, as the hub's file has it."""
    try:
        data = json.loads(text.lstrip("\ufeff"), parse_constant=_no_constant)
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    preset_id = _text(_field(data, "id"))
    title = _text(_field(data, "title")) or preset_id
    team_size = _field(data, "teamSize")
    tree = {"id": preset_id, "name": title, "positions": _items(_field(data, "positions"))}
    result = read_org_chart(json.dumps({"trees": [tree]}), prompt_exists, file_name=file_name or f"{preset_id}.json")
    if not preset_id or result.status != "ok" or result.chart is None:
        return None
    return {
        "id": preset_id,
        "size": _text(_field(data, "size")),
        "title": title,
        "shortDescription": _text(_field(data, "shortDescription")),
        "description": _text(_field(data, "description")),
        "teamSize": team_size if isinstance(team_size, int) and not isinstance(team_size, bool) else None,
        "chart": result.chart,
    }


# The order the presets are offered in: smallest first.
_SIZE_ORDER = ("S", "M", "L")


def org_presets(folder: Path | None = None) -> list[dict]:
    """Every preset in ``folder`` (the package's samples/org-presets/), S, M,
    L, then any other size by id. A preset names only the roles the toolkit
    ships, so its prompts are looked up in the toolkit's roles folder alone. A
    file that does not read as a preset is left out and said in the log."""
    folder = folder or ORG_PRESETS_DIR
    shipped = prompts.shipped_roles_dir()

    def prompt_exists(name: str) -> bool:
        return (shipped / name).is_file()

    found: list[dict] = []
    for path in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        try:
            text = path.read_bytes().decode("utf-8", errors="replace")
        except OSError:
            text = ""
        preset = read_preset(text, prompt_exists, path.name)
        if preset is None:
            log_writer.write_log("ERR", f"agent{PRESETS_ROUTE}", f"{path.name} is not a preset this tool reads -- left out.")
            continue
        found.append(preset)

    def rank(p: dict) -> tuple[int, str]:
        size = p["size"]
        return (_SIZE_ORDER.index(size) if size in _SIZE_ORDER else len(_SIZE_ORDER), p["id"])

    return sorted(found, key=rank)


def org_presets_response() -> dict:
    presets = org_presets()
    for preset in presets:
        with_prompts(preset["chart"])
    log_writer.write_log("CMD", f"agent{PRESETS_ROUTE}", f"presets={len(presets)}")
    return {"presets": presets}


@api.get(PRESETS_ROUTE)
async def get_org_presets() -> dict:
    # Team Agile's gate, as the chart's own route. The presets are the
    # package's, so no hub is needed to read them.
    return await asyncio.to_thread(org_presets_response)
