"""GET /api/ritual/releases -- the Space's releases, for Team Agile's Releases timeline.

The timeline's read (docs/modules/solitaire-agile.md, "Releases: the timeline").
A release is a tag merged into the Space's default branch, and what it said is its
section of the changelog; the one in progress runs from the last such tag to the
tip of the default branch, and what it will say is the entries waiting in
``changelog.d/`` there. "The tip" is the default branch, never whatever the clone
has checked out: ``origin/<branch>`` when the clone has that ref, else the local
``<branch>``, else HEAD, and ``source.ref`` names which was read. The branch is
named by the CLI's base-branch order (Thread-CommitHash.ps1, ``Resolve-P20BaseBranch``):
the Space project's ``defaultBranch``, else origin's HEAD, else ``main`` or ``master``.
All of that is read LOCALLY, from the Space's checkout on this machine
(``spaceCheckouts.<slug>.path``, checked by ``core.checkout.space_checkout``
exactly as the Design tab checks it):

- which ref is the default branch: ONE ``git for-each-ref`` over the branches;
- the tags merged into it and their instants: ONE ``git for-each-ref --merged``;
- each release's commits, pull requests and issues: one ``git log <prev>..<tag>``
  per release -- a squash merge's subject ends ``(#N)``, the pull request, and a
  ``Refs #N`` / ``Closes #N`` / ``Fixes #N`` names an issue;
- the notes: ``CHANGELOG.md`` (one ``git show <ref>:CHANGELOG.md``) and
  ``changelog.d/`` (one ``git grep`` of the folder at the ref) on the default
  branch, by the shapes ``consts.json`` ``changelog`` states (the web's What's New parses the
  toolkit's own changelog by the same heading; ``Scripts/Fold-Changelog.ps1``
  folds by the same fragment name).

The one fact that needs the tracker is the GitHub milestones, read through the
ado core's one reader (``milestones.read_milestones``, kept a minute) when the
tracker answers; when it does not, ``tracker.ok`` is false with its reason and
every release is still there. Where each milestone belongs is ONE pure rule,
``place_milestones`` -- reached between two tags is the later tag's, reached after
the last tag (or not reached at all) is the release in progress's; GitHub's close
instant against the tag's where both are known, else the day -- pinned by
``Tests/fixtures/releases/placement.json`` so a future verb answers the same.

The panel's issue titles are the tracker's, so they are a second read,
``GET rituals.releaseTitlesRoute``: the numbers of one release's issues, the
first ``TITLES_LIMIT`` of them asked in ONE ``gh api graphql`` call of aliased
``issueOrPullRequest`` lookups (the standup's dates read is the same shape), the
owner and name as fields, kept for the tracker's TTL like every ritual read.

A READ: nothing is written, here, in the checkout or on the tracker. Pre-release
tags (``-rc.N``) are not releases here; release-candidate checkpoints are not built yet.
"""

from __future__ import annotations

import asyncio
import re
from datetime import UTC, datetime
from pathlib import Path

from fastapi import HTTPException
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
    rituals_release_titles_route,
    rituals_releases_route,
)
from ..core.git_history import git_read
from .milestones import TrackerState, read_milestones
from .standup import api
from .tracker import github_repos, remember

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
# How many issue titles one panel asks for: past it, the rest keep their numbers.
TITLES_LIMIT = 50


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


class SourceState(TrackerState):
    """The checkout: git answered there, and its files were read -- at ``ref``,
    the default branch as the clone has it (``origin/main``, ``main``) or HEAD
    when it has neither."""

    ref: str = ""


class Releases(BaseModel):
    ceremony: str = CEREMONY
    space: str = ""
    repo: str = ""
    source: SourceState = SourceState()
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


def fragment_notes(files: list[tuple[str, str]]) -> list[Note]:
    """``changelog.d/``'s entries, given as (file name, text), under their
    headings in Keep a Changelog order, each heading's files in name order --
    what the fold will write next. README.md, a dotfile and a name of no kind
    are not entries."""
    shape = re.compile(changelog_fragment_regex(), re.IGNORECASE)
    kinds = changelog_kinds()
    by_kind: dict[str, list[str]] = {k: [] for k in kinds}
    for name, text in sorted(files, key=lambda f: f[0]):
        m = shape.match(name)
        if name.lower() == "readme.md" or name.startswith(".") or not m:
            continue
        kind = m.group(2).lower()
        if kind in by_kind:
            by_kind[kind] += _entries(text.splitlines())
    return [Note(heading=kinds[k], entries=v) for k, v in by_kind.items() if v]


def read_fragments(root: Path, ref: str) -> list[tuple[str, str]]:
    """[(file name, text)] of every file directly in ``changelog.d/`` at ``ref``,
    from ONE ``git grep`` -- each line comes back as ``<ref>:<path>`` NUL
    ``<line>``, so the files and their text are one answer. A folder that is not
    there (or holds nothing) is []."""
    folder = changelog_folder().strip("/")
    out = git_read(
        [
            "-c",
            "grep.lineNumber=false",
            "-c",
            "grep.column=false",
            "grep",
            "--null",
            "-I",
            "-e",
            "",
            ref,
            "--",
            f"{folder}/",
        ],
        root,
    )
    lines: dict[str, list[str]] = {}
    for line in (out or "").splitlines():
        where, sep, text = line.partition("\x00")
        if not sep:
            continue
        path = where.removeprefix(f"{ref}:")
        parent, _, name = path.rpartition("/")
        if parent != folder or not name:
            continue
        lines.setdefault(name, []).append(text)
    return [(name, "\n".join(body) + "\n") for name, body in lines.items()]


# -- The default branch -------------------------------------------------------


def configured_branch(repo: str, projects: list[dict]) -> str:
    """The Space project's ``defaultBranch`` for ``repo`` (``owner/name``), matched
    by the entry's repo -- ``name`` or ``owner/name``, ignoring case, as NewPR and
    ThreadHash match it -- "" when no entry names one."""
    name = repo.rsplit("/", 1)[-1].lower()
    for p in projects or []:
        written = str(p.get("repo") or "").lower()
        if written and (written == repo.lower() or written.rsplit("/", 1)[-1] == name) and p.get("defaultBranch"):
            return str(p["defaultBranch"])
    return ""


def pick_default_ref(listing: str, configured: str = "") -> tuple[str, str, str]:
    """(the branch's name, the full ref to read, the ref as ``source.ref`` says
    it) from a ``for-each-ref --format=%(refname)%09%(symref)`` listing of the
    clone's branches. The name: ``configured``, else what origin's HEAD points
    at, else ``main`` or ``master`` (the CLI's last resort). The ref:
    ``origin/<name>`` when the clone has it, else the local ``<name>``, else
    HEAD -- the branch checked out, said as such."""
    refs: dict[str, str] = {}
    for line in listing.splitlines():
        ref, _, sym = line.partition("\t")
        if ref.strip():
            refs[ref.strip()] = sym.strip()
    remote = "refs/remotes/origin/"
    name = configured
    if not name and refs.get(f"{remote}HEAD", "").startswith(remote):
        name = refs[f"{remote}HEAD"].removeprefix(remote)
    if not name:
        name = next((n for n in ("main", "master") if f"refs/heads/{n}" in refs), "")
    if name and f"{remote}{name}" in refs:
        return name, f"{remote}{name}", f"origin/{name}"
    if name and f"refs/heads/{name}" in refs:
        return name, f"refs/heads/{name}", name
    return name, "HEAD", "HEAD"


def default_ref(root: Path, configured: str = "") -> tuple[str, str, str] | None:
    """``pick_default_ref`` over the clone's branches, ONE ``git for-each-ref``;
    None when git could not answer."""
    out = git_read(["for-each-ref", "--format=%(refname)%09%(symref)", "refs/heads", "refs/remotes/origin"], root)
    return None if out is None else pick_default_ref(out, configured)


# -- The tags and their ranges ------------------------------------------------


def _instant(unix: str) -> str:
    try:
        return datetime.fromtimestamp(int(unix.strip()), UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, OverflowError, OSError):
        return ""


def read_tags(root: Path, ref: str = "HEAD") -> list[tuple[str, str, str]] | None:
    """[(tag, day, instant)] for every release tag merged into ``ref``, newest
    version first -- a tag on a branch never merged is not a release. ONE
    ``git for-each-ref --merged``; None when git could not answer."""
    out = git_read(
        ["for-each-ref", f"--merged={ref}", "--format=%(refname:short)%09%(creatordate:unix)", "refs/tags"], root
    )
    if out is None:
        return None
    tags: list[tuple[tuple[int, int, int], str, str, str]] = []
    for line in out.splitlines():
        name, _, at = line.partition("\t")
        m = _TAG.match(name.strip())
        if m:
            version = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
            tags.append((version, name.strip(), local_day(at) or "", _instant(at)))
    tags.sort(reverse=True)
    return [(name, day, at) for _, name, day, at in tags]


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


def _when(text: str) -> datetime | None:
    try:
        at = datetime.fromisoformat(text.strip())
    except (ValueError, AttributeError):
        return None
    return at if at.tzinfo else None


def place_milestones(tags: list[tuple], milestones: list[Milestone]) -> dict[str, list[ReleaseMilestone]]:
    """{tag: its milestones}, "" the release in progress. ``tags`` newest first,
    each (tag, day) or (tag, day, instant).

    Only a reached milestone belongs to a tag. Where GitHub gave its close time
    and every tag carries its instant, the instants decide: it is the OLDEST tag
    made at or after the close, so one closed on a tag's day but after the tag
    is the next release's. Otherwise the day decides, as it always did: reached
    on day d, it is the oldest tag dated d or later's, the day of a tag counting
    in it. One reached after the last tag, or not reached at all -- open, or
    empty, or closed on GitHub with an issue reopened -- is the release in
    progress's: the one it is still aimed at. Each release keeps the tracker's
    order."""
    out: dict[str, list[ReleaseMilestone]] = {"": []}
    for t in tags:
        out[t[0]] = []
    oldest_first = list(reversed(tags))
    instants = [_when(t[2]) if len(t) > 2 and t[2] else None for t in oldest_first]
    every_instant = bool(oldest_first) and all(instants)
    for m in milestones:
        day = reached_on(m)
        home = ""
        if day:
            closed = _when(m.closed_time) if m.closed_time else None
            if closed is not None and every_instant:
                home = next((t[0] for t, at in zip(oldest_first, instants, strict=True) if at and at >= closed), "")
            else:
                home = next((t[0] for t in oldest_first if t[1] and t[1] >= day), "")
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
        out.source = SourceState(ok=False, reason="This Space names no repository, so it has no tags to read.")
        return _logged(out)
    checkout = space_checkout(slug, repo, cfg)
    if not checkout.ready:
        out.source = SourceState(
            ok=False,
            reason=checkout.reason
            or f"{checkout.key} is not set: the releases are read from {repo}'s clone on this machine.",
        )
        return _logged(out)
    root = Path(checkout.root)
    picked = default_ref(root, configured_branch(repo, projects))
    if picked is None:
        out.source = SourceState(ok=False, reason=f"git did not answer in {root}.")
        return _logged(out)
    branch, ref, said = picked
    tags = read_tags(root, ref)
    if tags is None:
        out.source = SourceState(ok=False, reason=f"git did not answer in {root}.", ref=said)
        return _logged(out)
    out.source = SourceState(ref=said)

    base = f"https://github.com/{repo}"
    shipped = parse_changelog(git_read(["show", f"{ref}:{changelog_file()}"], root) or "")
    placed = place_milestones(tags, milestones)

    last = tags[0][0] if tags else ""
    tip = branch if ref != "HEAD" else "HEAD"
    commits, pulls, issues = read_range(root, f"refs/tags/{last}..{ref}" if last else ref, base)
    releases = [
        Release(
            version=IN_PROGRESS_VERSION,
            inProgress=True,
            since=tags[0][1] if tags else "",
            previous=last,
            commits=commits,
            url=f"{base}/compare/{last}...{tip}" if last else f"{base}/commits/{tip}",
            notes=fragment_notes(read_fragments(root, ref)),
            pulls=pulls,
            issues=issues,
            milestones=placed[""],
        )
    ]
    for i, (tag, day, _at) in enumerate(tags):
        prev, prev_day = (tags[i + 1][0], tags[i + 1][1]) if i + 1 < len(tags) else ("", "")
        rev = f"refs/tags/{prev}..refs/tags/{tag}" if prev else f"refs/tags/{tag}"
        commits, pulls, issues = read_range(root, rev, base)
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


# -- The titles of a release's issues -----------------------------------------


class IssueTitle(BaseModel):
    number: int = 0
    title: str = ""


class ReleaseTitles(BaseModel):
    space: str = ""
    repo: str = ""
    tracker: TrackerState = TrackerState()
    # How many numbers were asked, and how many one read takes: past the limit,
    # the first ``limit`` (ascending) are read and the rest keep their numbers.
    asked: int = 0
    limit: int = TITLES_LIMIT
    # Ascending; a number GitHub could not resolve is not here.
    titles: list[IssueTitle] = []


def titles_query(numbers: list[int]) -> str:
    """The one GraphQL query a titles read sends: ``i<n>`` issue (or pull
    request) n's title. The owner and name travel as variables; each number is an
    int, written by ``int()``, so nothing but digits reaches the query text."""
    lines = ["query($owner: String!, $name: String!) {", "  repository(owner: $owner, name: $name) {"]
    for n in numbers:
        lines.append(
            f"    i{int(n)}: issueOrPullRequest(number: {int(n)}) "
            "{ ... on Issue { title } ... on PullRequest { title } }"
        )
    lines += ["  }", "}"]
    return "\n".join(lines) + "\n"


def _read_titles(repo: str, numbers: list[int]) -> tuple[object, str | None]:
    from ..ado import repo_read

    owner, _, name = repo.partition("/")
    data, _errors, why = repo_read.graphql_aliases(
        titles_query(numbers), ["-f", f"owner={owner}", "-f", f"name={name}"]
    )
    if why:
        return None, accounting.gh_repo_reason(repo, why)
    node = (data or {}).get("repository") or {}
    out: dict[int, str] = {}
    for n in numbers:
        hit = node.get(f"i{int(n)}")
        if isinstance(hit, dict) and hit.get("title"):
            out[int(n)] = str(hit["title"])
    return out, None


def parse_numbers(text: str) -> list[int]:
    """``?numbers=12,8`` as distinct ints, ascending; a part that is not a
    positive number is a 422 naming it."""
    out: set[int] = set()
    for part in (text or "").split(","):
        part = part.strip()
        if not part:
            continue
        if not part.isdigit() or int(part) < 1:
            raise HTTPException(status_code=422, detail=f"'{part}' is not an issue number.")
        out.add(int(part))
    return sorted(out)


def titles_for(space: str = "", numbers: list[int] | None = None, refresh: bool = False) -> ReleaseTitles:
    """The titles of one release's issues -- the active Space when ``space`` is "".
    No number is no call; no tracker is ``tracker.ok`` false and no title. Never
    raises for the tracker."""
    cfg = load_config()
    org, status, projects = accounting.space_scope(cfg, space)
    asked = list(numbers or [])
    out = ReleaseTitles(
        space=space or str(cfg.get("activeSpace") or ""), repo=_space_repo(org, projects), asked=len(asked)
    )
    if not asked:
        return out
    _repos, state = github_repos(org, status, projects, ritual="the Releases tab", refresh=refresh)
    if state["ok"] and not out.repo:
        state = {"ok": False, "reason": "This Space names no repository."}
    if state["ok"]:
        wanted = asked[:TITLES_LIMIT]
        got, why = remember(("titles", out.repo, tuple(wanted)), refresh, lambda: _read_titles(out.repo, wanted))
        if why:
            state = {"ok": False, "reason": why}
        else:
            out.titles = [IssueTitle(number=n, title=t) for n, t in sorted(dict(got or {}).items())]
    out.tracker = TrackerState(ok=bool(state["ok"]), reason=str(state["reason"] or ""))
    log_writer.write_log(
        "CMD",
        f"agent{TITLES_ROUTE}",
        f"space={out.space} tracker={int(out.tracker.ok)} asked={out.asked} titles={len(out.titles)}",
    )
    return out


TITLES_ROUTE = rituals_release_titles_route().removeprefix(API_PREFIX)


@api.get(TITLES_ROUTE, response_model=ReleaseTitles)
async def get_release_titles(space: str = "", numbers: str = "", refresh: int = 0):
    # The numbers are the panel's release's issues; the route reads only their
    # titles, in one call, so the timeline's own read never waits on the tracker
    # for them.
    return await asyncio.to_thread(titles_for, space, parse_numbers(numbers), bool(refresh))
