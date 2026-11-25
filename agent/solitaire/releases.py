"""GET /api/ritual/releases -- the Space's releases, for Team Agile's Releases timeline.

The timeline's read (docs/modules/solitaire-agile.md, "Releases: the timeline").
A release is a tag, and what it said is its section of the changelog; the one in
progress runs from the last tag to the checkout's HEAD, and what it will say is
the entries still waiting in ``changelog.d/``. All of that is read LOCALLY, from
the Space's checkout on this machine (``spaceCheckouts.<slug>.path``, checked by
``core.checkout.space_checkout`` exactly as the Design tab checks it):

- the tags and their days: ONE ``git for-each-ref refs/tags``;
- each release's commits, pull requests and issues: one ``git log <prev>..<tag>``
  per release -- a squash merge's subject ends ``(#N)``, the pull request, and a
  ``Refs #N`` / ``Closes #N`` / ``Fixes #N`` names an issue;
- the notes: ``CHANGELOG.md`` and ``changelog.d/`` at the checkout's root, by the
  shapes ``consts.json`` ``changelog`` states (the web's What's New parses the
  toolkit's own changelog by the same heading; ``Scripts/Fold-Changelog.ps1``
  folds by the same fragment name).

The one fact that needs the tracker is the GitHub milestones, read through the
ado core's one reader (``milestones.read_milestones``, kept a minute) when the
tracker answers; when it does not, ``tracker.ok`` is false with its reason and
every release is still there. Where each milestone belongs is ONE pure rule,
``place_milestones`` -- reached between two tags is the later tag's, reached after
the last tag (or not reached at all) is the release in progress's -- pinned by
``Tests/fixtures/releases/placement.json`` so a future verb answers the same.

A READ: nothing is written, here, in the checkout or on the tracker. Pre-release
tags (``-rc.N``) are not releases here; they are #326's checkpoints, not built.
"""

from __future__ import annotations

import asyncio
import re
from pathlib import Path

from pydantic import BaseModel

from ..ado import accounting
from ..ado.accounting import Milestone
from ..core import log_writer
from ..core.checkout import space_checkout
from ..core.clock import local_day
from ..core.config import API_PREFIX, load_config, tracker_repos
from ..core.consts import (
    changelog_file,
    changelog_folder,
    changelog_fragment_regex,
    changelog_kinds,
    changelog_release_heading_regex,
    rituals_releases_route,
)
from ..core.git_history import git_read
from .milestones import TrackerState, read_milestones
from .standup import api
from .tracker import github_repos

CEREMONY = "releases"
# The version a release in progress is called by, as Keep a Changelog calls it.
IN_PROGRESS_VERSION = "Unreleased"
# A release tag: vX.Y.Z or X.Y.Z, nothing after it (a -rc.N is a checkpoint).
_TAG = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
_PULL = re.compile(r"\(#(\d+)\)\s*$")
_ISSUE = re.compile(r"\b(?:refs|closes|closed|fixes|fixed|resolves|resolved)\s+#(\d+)", re.IGNORECASE)
_GROUP = re.compile(r"^###\s+(.+?)\s*$")
_ANY_HEADING = re.compile(r"^#{1,6}\s")
_ENTRY = re.compile(r"^-\s+(.*)$")
# The record and field separators of the one log format: NUL and US, which no
# subject or body holds.
_LOG_FORMAT = "--format=%x00%H%x1f%s%x1f%b"
# A release in progress with no tag before it is the whole history; past this
# many commits the count says "at least".
LOG_LIMIT = 2000


class Note(BaseModel):
    """One heading of a release's notes: Added, Changed, Removed, Fixed."""

    heading: str = ""
    entries: list[str] = []


class Ref(BaseModel):
    """A pull request or an issue, by number, linked on the Space's repository."""

    number: int = 0
    title: str = ""
    url: str = ""


class ReleaseMilestone(Milestone):
    """The core's milestone, with the day it was reached ("" while it is not)."""

    reachedOn: str = ""


class Release(BaseModel):
    tag: str = ""  # "" for the release in progress
    version: str = ""  # "1.7.0"; IN_PROGRESS_VERSION for the one in progress
    inProgress: bool = False
    date: str = ""  # the tag's day; "" in progress
    since: str = ""  # the previous tag's day; "" for the first
    previous: str = ""  # the previous tag; "" for the first
    commits: int = 0
    url: str = ""  # the GitHub Release; the compare view in progress
    notes: list[Note] = []
    pulls: list[Ref] = []
    issues: list[Ref] = []
    milestones: list[ReleaseMilestone] = []


class Releases(BaseModel):
    ceremony: str = CEREMONY
    space: str = ""
    repo: str = ""
    # The checkout: git answered there, and its files were read.
    source: TrackerState = TrackerState()
    # The milestones: the tracker answered.
    tracker: TrackerState = TrackerState()
    releases: list[Release] = []


# -- The notes ----------------------------------------------------------------


def _entries(lines: list[str]) -> list[str]:
    """`- ` entries, each continuation line joined to the one above with a space."""
    out: list[str] = []
    open_ = False
    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            open_ = False
            continue
        m = _ENTRY.match(line)
        if m:
            out.append(m.group(1))
            open_ = True
        elif open_ and out:
            out[-1] += f" {line.strip()}"
    return out


def parse_changelog(text: str) -> dict[str, list[Note]]:
    """{version: its notes} for every released section; ``[Unreleased]`` is not one."""
    heading = re.compile(changelog_release_heading_regex())
    out: dict[str, list[Note]] = {}
    notes: list[Note] | None = None
    group: list[str] | None = None
    groups: list[tuple[str, list[str]]] = []

    def close() -> None:
        if notes is not None:
            notes.extend(Note(heading=h, entries=_entries(body)) for h, body in groups)

    for raw in text.splitlines():
        line = raw.rstrip()
        m = heading.match(line)
        if m:
            close()
            groups = []
            group = None
            version = m.group(1)
            notes = None if version.lower() == IN_PROGRESS_VERSION.lower() else out.setdefault(version, [])
            continue
        if notes is None:
            continue
        g = _GROUP.match(line)
        if g:
            group = []
            groups.append((g.group(1), group))
            continue
        if _ANY_HEADING.match(line):
            group = None
            continue
        if group is not None:
            group.append(line)
    close()
    return out


def waiting_notes(folder: Path) -> list[Note]:
    """``changelog.d/``'s entries under their headings, in Keep a Changelog order,
    each heading's files in name order -- what the fold will write next."""
    if not folder.is_dir():
        return []
    shape = re.compile(changelog_fragment_regex(), re.IGNORECASE)
    kinds = changelog_kinds()
    by_kind: dict[str, list[str]] = {k: [] for k in kinds}
    for f in sorted(folder.iterdir(), key=lambda p: p.name):
        m = shape.match(f.name)
        if not f.is_file() or f.name.lower() == "readme.md" or f.name.startswith(".") or not m:
            continue
        kind = m.group(2).lower()
        if kind not in by_kind:
            continue
        try:
            text = f.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
        by_kind[kind] += _entries(text.splitlines())
    return [Note(heading=kinds[k], entries=v) for k, v in by_kind.items() if v]


# -- The tags and their ranges ------------------------------------------------


def read_tags(root: Path) -> list[tuple[str, str]] | None:
    """[(tag, day)] for every release tag, newest version first; None when git
    could not answer."""
    out = git_read(["for-each-ref", "--format=%(refname:short)%09%(creatordate:unix)", "refs/tags"], root)
    if out is None:
        return None
    tags: list[tuple[tuple[int, int, int], str, str]] = []
    for line in out.splitlines():
        name, _, at = line.partition("\t")
        m = _TAG.match(name.strip())
        if m:
            tags.append(((int(m.group(1)), int(m.group(2)), int(m.group(3))), name.strip(), local_day(at) or ""))
    tags.sort(reverse=True)
    return [(name, day) for _, name, day in tags]


def read_range(root: Path, rev: str, base_url: str) -> tuple[int, list[Ref], list[Ref]]:
    """(commits, pull requests, issues) of one ``git log`` range, numbers ascending."""
    out = git_read(["log", _LOG_FORMAT, f"--max-count={LOG_LIMIT}", rev], root) or ""
    commits = 0
    pulls: dict[int, str] = {}
    issues: set[int] = set()
    for record in out.split("\x00"):
        if not record.strip():
            continue
        commits += 1
        _sha, _, rest = record.partition("\x1f")
        subject, _, body = rest.partition("\x1f")
        m = _PULL.search(subject)
        if m:
            pulls[int(m.group(1))] = _PULL.sub("", subject).strip()
        issues.update(int(n) for n in _ISSUE.findall(f"{subject}\n{body}"))
    issues -= set(pulls)
    return (
        commits,
        [Ref(number=n, title=t, url=f"{base_url}/pull/{n}") for n, t in sorted(pulls.items())],
        [Ref(number=n, url=f"{base_url}/issues/{n}") for n in sorted(issues)],
    )


# -- Where a milestone belongs ------------------------------------------------


def reached_on(m: Milestone) -> str:
    """The day it was reached -- GitHub's close, else its last change (the last
    issue closing), the award's own rule (award.ts reachedDay) -- "" if it is not."""
    return (m.closed_at or m.updated_at or "") if m.reached else ""


def place_milestones(tags: list[tuple[str, str]], milestones: list[Milestone]) -> dict[str, list[ReleaseMilestone]]:
    """{tag: its milestones}, "" the release in progress. ``tags`` newest first.

    A milestone reached on day d is the OLDEST tag dated d or later's: reached
    between two tags is the later one's, and the day of a tag counts in it. One
    reached after the last tag, or not reached at all -- open, or empty, or closed
    on GitHub with an issue reopened -- is the release in progress's: the one it
    is still aimed at. Each release keeps the tracker's order."""
    out: dict[str, list[ReleaseMilestone]] = {"": []}
    for tag, _ in tags:
        out[tag] = []
    oldest_first = list(reversed(tags))
    for m in milestones:
        day = reached_on(m)
        home = ""
        if day:
            home = next((tag for tag, tag_day in oldest_first if tag_day and tag_day >= day), "")
        out[home].append(ReleaseMilestone(**m.model_dump(), reachedOn=day))
    return out


# -- The read -----------------------------------------------------------------


def _space_repo(org: str, projects: list[dict]) -> str:
    repos = tracker_repos(org, projects)
    return repos[0] if repos else ""


def releases_for(space: str = "", refresh: bool = False) -> Releases:
    """Every release of a Space -- the active one when ``space`` is "". Never
    raises: no checkout is ``source.ok`` false and no release, no tracker is
    ``tracker.ok`` false and no milestone."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    slug = space or str(cfg.get("activeSpace") or "")
    repo = _space_repo(org, projects)
    out = Releases(space=slug, repo=repo)

    # The milestones first: their read does not depend on the checkout.
    milestones: list[Milestone] = []
    repos, state = github_repos(org, status, projects, ritual="the Releases tab", refresh=refresh)
    if state["ok"]:
        for r in repos:
            got, why = read_milestones(r, refresh)
            if why:
                state, milestones = {"ok": False, "reason": why}, []
                break
            milestones += got
    out.tracker = TrackerState(ok=bool(state["ok"]), reason=str(state["reason"] or ""))

    if not repo:
        out.source = TrackerState(ok=False, reason="This Space names no repository, so it has no tags to read.")
        return _logged(out)
    checkout = space_checkout(slug, repo, cfg)
    if not checkout.ready:
        out.source = TrackerState(
            ok=False,
            reason=checkout.reason
            or f"{checkout.key} is not set: the releases are read from {repo}'s clone on this machine.",
        )
        return _logged(out)
    root = Path(checkout.root)
    tags = read_tags(root)
    if tags is None:
        out.source = TrackerState(ok=False, reason=f"git did not answer in {root}.")
        return _logged(out)

    base = f"https://github.com/{repo}"
    try:
        shipped = parse_changelog((root / changelog_file()).read_text(encoding="utf-8-sig", errors="replace"))
    except OSError:
        shipped = {}
    placed = place_milestones(tags, milestones)

    last = tags[0][0] if tags else ""
    commits, pulls, issues = read_range(root, f"{last}..HEAD" if last else "HEAD", base)
    releases = [
        Release(
            version=IN_PROGRESS_VERSION,
            inProgress=True,
            since=tags[0][1] if tags else "",
            previous=last,
            commits=commits,
            url=f"{base}/compare/{last}...HEAD" if last else f"{base}/commits",
            notes=waiting_notes(root / changelog_folder()),
            pulls=pulls,
            issues=issues,
            milestones=placed[""],
        )
    ]
    for i, (tag, day) in enumerate(tags):
        prev, prev_day = tags[i + 1] if i + 1 < len(tags) else ("", "")
        commits, pulls, issues = read_range(root, f"{prev}..{tag}" if prev else tag, base)
        version = _TAG.match(tag)
        number = ".".join(version.groups()) if version else tag
        releases.append(
            Release(
                tag=tag,
                version=number,
                date=day,
                since=prev_day,
                previous=prev,
                commits=commits,
                url=f"{base}/releases/tag/{tag}",
                notes=shipped.get(number, []),
                pulls=pulls,
                issues=issues,
                milestones=placed[tag],
            )
        )
    out.releases = releases
    return _logged(out)


def _logged(out: Releases) -> Releases:
    log_writer.write_log(
        "CMD",
        f"agent{ROUTE}",
        f"space={out.space} source={int(out.source.ok)} tracker={int(out.tracker.ok)} "
        f"releases={len(out.releases)} milestones={sum(len(r.milestones) for r in out.releases)}",
    )
    return out


ROUTE = rituals_releases_route().removeprefix(API_PREFIX)


@api.get(ROUTE, response_model=Releases)
async def get_releases(space: str = "", refresh: int = 0):
    # space_scope raises the 404 for an unknown slug, as its siblings' do.
    # ?refresh=1 reads the tracker again past the kept read.
    return await asyncio.to_thread(releases_for, space, bool(refresh))
