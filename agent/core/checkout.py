"""A Space's checkout on this machine -- ``spaceCheckouts.<slug>.path``.

Where a Space's own repository is cloned here, as this machine says
(config.local.json only; never hub.json, which other machines read and whose
clones sit elsewhere). Written by ``Config -Set``, the one writer.

The CLI's resolver is the one that SEARCHES (Scripts/Resolve-SpaceCheckout.ps1,
``Resolve-P20SpaceCheckout``: this setting first, then the folder you stand in,
then the nav shortcuts). The agent asks a narrower question, for the Design
tab's product rows: does the CONFIGURED path name a clone of the Space's
repository? One candidate, the same rule -- the folder is inside a git
repository whose GitHub origin is the Space's repo, compared ignoring case.
``MoveDesign -Space <slug>``, which the rows run through the bridge, then tries
that same path first. Tests/fixtures/space-checkout/table.json holds the path
and origin rules to the CLI's, from both suites.

Read only; nothing raises.
"""

from __future__ import annotations

import re
from pathlib import Path

from pydantic import BaseModel

from .config import load_config
from .git_history import git_read

# The same pattern as Get-P20GitHubOriginRepo (Scripts/Resolve-Tracker.ps1),
# ignoring case as that one does.
_ORIGIN = re.compile(r"github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", re.IGNORECASE)


class SpaceCheckout(BaseModel):
    """What the Design tab needs to know about the Space's checkout."""

    # The Space it was checked for: what MoveDesign -Space takes.
    space: str = ""
    # The setting, spelled for Config -Set: spaceCheckouts.<slug>.path.
    key: str = ""
    # As written in config.local.json ("" when unset).
    path: str = ""
    # The clone's top level, when the path names a clone of the Space's repo.
    root: str = ""
    # True only then: the rows offer the moves.
    ready: bool = False
    # Why not, in a sentence the tab prints ("" when ready or unset).
    reason: str = ""


def checkout_key(slug: str) -> str:
    return f"spaceCheckouts.{slug}.path"


def checkout_path(written: str) -> str:
    """A configured path as written: absolute, or under ``~``. A relative path
    has nothing on this machine to be relative to, so it is ""."""
    p = (written or "").strip()
    if not p:
        return ""
    if p == "~" or p.startswith(("~/", "~\\")):
        rest = p[1:].lstrip("/\\")
        return str(Path.home() / rest) if rest else str(Path.home())
    return p if Path(p).is_absolute() else ""


def origin_repo(url: str) -> str:
    """``owner/name`` from a GitHub remote URL, "" for anything else."""
    m = _ORIGIN.search((url or "").strip())
    return f"{m.group(1)}/{m.group(2)}" if m else ""


def configured_checkout(slug: str, cfg: dict | None = None) -> str:
    """The path spaceCheckouts.<slug>.path names here, as written ("")."""
    table = (cfg if cfg is not None else load_config()).get("spaceCheckouts") or {}
    entry = table.get(slug) if isinstance(table, dict) else None
    if isinstance(entry, dict):
        return str(entry.get("path") or "")
    return ""


def space_checkout(slug: str, repo: str, cfg: dict | None = None) -> SpaceCheckout:
    """The Space's configured checkout, checked against its repository."""
    key = checkout_key(slug)
    written = configured_checkout(slug, cfg)
    out = SpaceCheckout(space=slug, key=key, path=written)
    if not written.strip():
        return out
    path = checkout_path(written)
    if not path:
        out.reason = f"{key} is '{written}', which is neither an absolute path nor under ~."
        return out
    folder = Path(path)
    if not folder.is_dir():
        out.reason = f"{key} is {path}, but that is not a folder on this machine."
        return out
    top = (git_read(["rev-parse", "--show-toplevel"], folder) or "").strip()
    if not top:
        out.reason = f"{key} is {path}, but it is not inside a git repository."
        return out
    found = origin_repo(git_read(["remote", "get-url", "origin"], Path(top)) or "")
    if found.lower() != (repo or "").lower():
        why = (
            f"it is a clone of {found}, not {repo}"
            if found
            else f"its origin is not on GitHub, so it is not a clone of {repo}"
        )
        out.reason = f"{key} is {path}, but {why}."
        return out
    out.root = str(Path(top))
    out.ready = True
    return out
