"""Sprint awareness -- /stress-status, /stress-sprint-activity, /stress-repos.

All three are gated per org on ``features.sprintAwareness`` and return a
declining payload when the feature is off, which is the default: an org that
has not opted in never pays for this.

They read ``stress-log*.json`` from the hub root -- a hub-root sibling in the
same class as ``growth/`` and ``reviews/``, written by whatever produces it on
that machine. There is no writer in this package, so in practice these routes
report "no log yet" until one exists; nothing raises either way.
"""

import json
import math
import os
import re
from datetime import date, timedelta
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..core.config import (
    DEFAULT_CONFIG_PATH,
    LOCAL_CONFIG_PATH,
    hub_root,
    load_config,
)

api = APIRouter()


def _today() -> date:
    """The reader's day. One seam for the tests."""
    return date.today()


def _number(value: object) -> int | float | None:
    """A JSON number, or None: null, a string, a boolean, a list, an object and a NaN or an
    infinity are no number. Every number read from the stress log goes through here, so no
    shape of the log can fail a route."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value if math.isfinite(value) else None


def _int(value: object, default: int) -> int:
    """A number read as a whole one, or ``default``."""
    number = _number(value)
    return default if number is None else int(number)


def _float(value: object, default: float) -> float:
    """A number, or ``default``."""
    number = _number(value)
    return default if number is None else float(number)


def _object(value: object) -> dict:
    """A block of the log, or an empty one when the log holds anything else there."""
    return value if isinstance(value, dict) else {}


def _strings(value: object) -> list[str]:
    """A list's strings; nothing when the log holds anything but a list there."""
    return [v for v in value if isinstance(v, str)] if isinstance(value, list) else []


def _count(value: object) -> int:
    """How many entries a list holds; 0 when the log holds anything but a list there."""
    return len(value) if isinstance(value, list) else 0


def _text(value: object) -> str | None:
    """A string, or None."""
    return value if isinstance(value, str) else None


def _day(value: object) -> date | None:
    """A yyyy-mm-dd day, or None."""
    try:
        return date.fromisoformat(value) if isinstance(value, str) else None
    except ValueError:
        return None


def _days_left(log: dict, org: dict) -> int | None:
    """Days left in the sprint, worked out at read time: from the log's own end date, else the
    Space's configured ``sprint.endDate``; the log's stored ``daysRemaining`` only when no day is
    known. None -- no countdown -- when there is neither. Never below 0."""
    sprint = _object(log.get("sprint"))
    end = _day(sprint.get("endDate")) or _day(_object(org.get("sprint")).get("endDate"))
    if end is not None:
        return max((end - _today()).days, 0)
    stored = _number(sprint.get("daysRemaining"))
    return None if stored is None else max(int(stored), 0)


def _stress_log_default() -> Path:
    """The hub-root stress log. Resolved per call, because the hub is
    config-driven and can change without restarting the agent."""
    return hub_root() / "stress-log.json"


def _rebase_pressure(upstream_merges: int, surface_area_change: int) -> str:
    """Rebase pressure: how far the branch has drifted from upstream."""
    if upstream_merges > 4 or surface_area_change > 100:
        return "High"
    if upstream_merges > 2 or surface_area_change > 50:
        return "Medium"
    return "Low"


def _held(pairs: list[tuple[str, bool]]) -> list[str]:
    """Return the reason strings whose predicate held, preserving order."""
    return [text for text, when in pairs if when]


def _classify_stress(log: dict, days: int | None) -> dict:
    """Classify a stress-log dict into the four risk dimensions.

    This is the only implementation in this package: the PowerShell twin it
    was parity-tested against did not come across, because sprint awareness is
    off by default here and no command writes the log. The rules are carried
    unchanged so that a hub which already has a stress-log.json reads the same
    way it did -- with one exception: ``days`` is the caller's (``_days_left``), and
    when there is none no reason is scored from it, where a missing value once read as 99.
    """
    sprint = _object(log.get("sprint"))
    origin = _object(log.get("origin"))
    comm = _object(log.get("communication"))
    team = _object(log.get("teamDynamics"))

    velocity = _int(sprint.get("mergeVelocity"), 0)
    refactor = bool(sprint.get("refactorWaveActive", False))
    int_window = bool(sprint.get("integrationWindowClosing", False))

    upstream = _int(origin.get("upstreamMerges"), 0)
    surface = _int(origin.get("surfaceAreaChange"), 0)
    conflicts = _count(origin.get("conflictZones"))
    rebase = _text(origin.get("rebasePressure")) or _rebase_pressure(upstream, surface)

    broadcasted = bool(comm.get("prBroadcasted", False))
    visibility = _float(comm.get("visibilityScore"), 0.5)
    cadence = comm.get("updateCadence", "Normal")

    xxl = _count(team.get("xxlPrAuthors"))
    silent = _count(team.get("silentRefactorers"))
    dated = days is not None

    # sprintStress
    sprint_high = _held(
        [
            ("daysRemaining <= 3", dated and days <= 3),
            ('rebasePressure == "High"', rebase == "High"),
            ("mergeVelocity >= 10", velocity >= 10),
            ("refactorWaveActive == true", refactor),
            ("integrationWindowClosing == true", int_window),
        ]
    )
    sprint_medium = _held(
        [
            ("daysRemaining <= 5", dated and days <= 5),
            ('rebasePressure == "Medium"', rebase == "Medium"),
        ]
    )
    sprint_low = _held(
        [
            ("daysRemaining > 5", dated and days > 5),
            ('rebasePressure == "Low"', rebase == "Low"),
            ("mergeVelocity < 10", velocity < 10),
        ]
    )
    if sprint_high:
        sprint_dim = {"level": "High", "reasons": sprint_high}
    elif sprint_medium:
        sprint_dim = {"level": "Medium", "reasons": sprint_medium}
    else:
        sprint_dim = {"level": "Low", "reasons": sprint_low}

    # originStress
    origin_high = _held(
        [
            ("upstreamMerges > 4", upstream > 4),
            ("surfaceAreaChange > 100", surface > 100),
            ("conflictZones.length > 0", conflicts > 0),
        ]
    )
    origin_medium = _held(
        [
            ("upstreamMerges > 2", upstream > 2),
            ("surfaceAreaChange > 50", surface > 50),
        ]
    )
    origin_low = _held(
        [
            ("upstreamMerges <= 2", upstream <= 2),
            ("surfaceAreaChange <= 50", surface <= 50),
            ("conflictZones.length == 0", conflicts == 0),
        ]
    )
    if origin_high:
        origin_dim = {"level": "High", "reasons": origin_high}
    elif origin_medium:
        origin_dim = {"level": "Medium", "reasons": origin_medium}
    else:
        origin_dim = {"level": "Low", "reasons": origin_low}

    # communicationStress — High is an AND
    if (not broadcasted) and visibility < 0.5:
        comm_dim = {"level": "High", "reasons": ["prBroadcasted == false", "visibilityScore < 0.5"]}
    elif (not broadcasted) or cadence == "Behind":
        comm_dim = {
            "level": "Medium",
            "reasons": _held(
                [
                    ("prBroadcasted == false", not broadcasted),
                    ('updateCadence == "Behind"', cadence == "Behind"),
                ]
            ),
        }
    else:
        comm_dim = {
            "level": "Low",
            "reasons": _held(
                [
                    ("prBroadcasted == true", broadcasted),
                    ("visibilityScore >= 0.8", visibility >= 0.8),
                    ('updateCadence == "Normal"', cadence == "Normal"),
                ]
            ),
        }

    # teamDynamicsStress — High is an AND (the table is authoritative over the
    # illustrative example, which loosely shows both lists non-empty at Medium)
    if xxl > 0 and silent > 0:
        team_dim = {"level": "High", "reasons": ["xxlPrAuthors.length > 0", "silentRefactorers.length > 0"]}
    elif xxl > 0 or silent > 0:
        team_dim = {
            "level": "Medium",
            "reasons": _held(
                [
                    ("xxlPrAuthors.length > 0", xxl > 0),
                    ("silentRefactorers.length > 0", silent > 0),
                ]
            ),
        }
    else:
        team_dim = {"level": "Low", "reasons": ["xxlPrAuthors.length == 0", "silentRefactorers.length == 0"]}

    return {
        "sprintStress": sprint_dim,
        "originStress": origin_dim,
        "communicationStress": comm_dim,
        "teamDynamicsStress": team_dim,
    }


def _active_space_feature(feature: str) -> bool:
    """Read a boolean features.<feature> flag from the merged view load_config
    builds (org-scoped keys off the active Space, engineer-scoped keys off the
    top-level block -- see core/config.py SPACE_FEATURES). Default False."""
    return bool((load_config().get("features") or {}).get(feature, False))


class StressDimension(BaseModel):
    level: str
    reasons: list[str]


class StressContext(BaseModel):
    """Display-only headline values from the log. NOT classification inputs —
    the dials (and their reasons) are the contract; this is the human-facing
    detail a dashboard shows alongside them."""

    sprintName: str = "Sprint"
    sprintFullName: str = "Sprint"  # full ADO iteration name (descriptive theme)
    daysRemaining: int | None = 0
    mergeVelocity: int = 0
    upstreamMerges: int = 0
    surfaceAreaChange: int = 0
    rebasePressure: str = "Low"
    conflictZones: list[str] = Field(default_factory=list)
    prBroadcasted: bool = False
    visibilityScore: float = 0.5
    updateCadence: str = "Normal"


class StressStatusResponse(BaseModel):
    enabled: bool
    org: str
    detail: str
    generatedAt: str | None = None
    sourceRepo: str | None = None
    sprintSource: str | None = None  # ado-iteration | config-pinned | config | card | default
    context: StressContext | None = None
    sprintStress: StressDimension | None = None
    originStress: StressDimension | None = None
    communicationStress: StressDimension | None = None
    teamDynamicsStress: StressDimension | None = None


def _stress_context(log: dict, days: int | None) -> StressContext:
    """What the card shows beside the dials. ``days`` is the one reading ``_classify_stress``
    scored, so a log with no countdown shows none rather than 0."""
    sprint = _object(log.get("sprint"))
    origin = _object(log.get("origin"))
    comm = _object(log.get("communication"))
    return StressContext(
        sprintName=str(sprint.get("name", "Sprint")),
        sprintFullName=str(sprint.get("fullName", sprint.get("name", "Sprint"))),
        daysRemaining=days,
        mergeVelocity=_int(sprint.get("mergeVelocity"), 0),
        upstreamMerges=_int(origin.get("upstreamMerges"), 0),
        surfaceAreaChange=_int(origin.get("surfaceAreaChange"), 0),
        rebasePressure=str(origin.get("rebasePressure", "Low")),
        conflictZones=_strings(origin.get("conflictZones")),
        prBroadcasted=bool(comm.get("prBroadcasted", False)),
        visibilityScore=_float(comm.get("visibilityScore"), 0.5),
        updateCadence=str(comm.get("updateCadence", "Normal")),
    )


def _file_in(folder: Path, name: str) -> Path | None:
    """The file ``name`` directly inside ``folder``, or None if it would land
    anywhere else. A caller has already held the name to a key; this is the
    check at the read itself."""
    root = os.path.realpath(folder)
    full = os.path.realpath(os.path.join(root, name))
    return Path(full) if full.startswith(root + os.sep) else None


def _read_history(folder: Path, repo: str) -> list[dict]:
    """A repo's committed history rows; none if the file is missing or unreadable."""
    path = _file_in(folder, f"stress-history.{repo}.json")
    if path is None or not path.exists():
        return []
    try:
        return _history_rows(json.loads(path.read_text(encoding="utf-8-sig")))
    except (json.JSONDecodeError, OSError):
        return []


def _history_rows(raw: object) -> list[dict]:
    """A history file's rows: what is an object, of what is a list."""
    return [row for row in raw if isinstance(row, dict)] if isinstance(raw, list) else []


def _config_sprint_context(org: dict, repo: str | None = None) -> StressContext:
    """Fallback context built from org config alone — no live stress-log.json
    required. `sprint.name`/`sprint.endDate` are manually-maintained config, not
    git-derived, so they're always available on any
    machine regardless of local checkout. Git-derived fields
    (mergeVelocity, upstreamMerges, rebasePressure, conflictZones) stay at
    their StressContext defaults — those genuinely need a live log and are
    correctly omitted here rather than fabricated.

    When the org has no `sprint.name` configured at all,
    don't fall back to the bare schema default "Sprint" — that reads as a
    placeholder/bug, not a real value. Instead borrow the latest entry's
    `sprint` label from the committed stress-history file, the same fallback
    already used by get_sprint_activity."""
    sprint = org.get("sprint") or {}
    name = sprint.get("name")
    if not name and repo:
        folder = org.get("promptsFolder", "")
        org_dir = (hub_root() / folder) if folder else hub_root()
        raw = _read_history(org_dir, repo)
        if raw:
            name = _text(max(raw, key=_row_date).get("sprint"))
    name = str(name or "Sprint")
    # No end date configured -- don't fabricate a countdown. A hardcoded
    # +7 was wrong for any org whose sprint is not a fortnight starting
    # where the one it was written against started.
    end_dt = _day(sprint.get("endDate"))
    days_remaining = None if end_dt is None else max((end_dt - _today()).days, 0)
    return StressContext(sprintName=name, sprintFullName=name, daysRemaining=days_remaining)


# A repo key names a file beside the hub's others, so it is a name, never a path.
_REPO_KEY = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def _repo_key(repo: str | None) -> str | None:
    """A repo key if it is one, else None. Every route takes its ``repo`` through
    this, and a key read from a log does too, before either names a file."""
    return repo if isinstance(repo, str) and _REPO_KEY.fullmatch(repo) else None


def _stress_log_path(repo: str | None) -> Path:
    """Resolve the stress-log path for an optional repo key, falling back to
    the unnamespaced file when repo is omitted or its namespaced file is absent."""
    if repo:
        namespaced = _file_in(hub_root(), f"stress-log.{repo}.json")
        if namespaced is not None and namespaced.exists():
            return namespaced
    return _stress_log_default()


_NO_LOG = "view-only -- no live signal on this machine; the stress log is written where the repo is checked out"


def _log_repo(log: dict) -> str | None:
    """The repository a log names: its ``repoKey``, else the last segment of its ``sourceRepo``."""
    source = _text(log.get("sourceRepo"))
    return _repo_key(_text(log.get("repoKey")) or (_repo_name_from_url(source) if source else None))


def _log_refusal(log: dict, active: str, repo: str | None) -> str | None:
    """Why this log is not the active Space's and the asked repository's, or None when it is.

    Both sprint routes ask it, so one log is refused by both in one sentence. The log is a single
    file a machine writes for one Space and one repository: one that names another Space, or none,
    is not this Space's; one that names another repository than the one asked for is not that
    repository's, which is what ``_stress_log_path`` falling back to the unnamespaced file would
    otherwise serve under the asked name."""
    log_org = _text(log.get("org"))
    if not log_org:
        return "view-only — the live log on this machine names no Space"
    if log_org != active:
        return f"view-only — live log on this machine is for '{log_org}'"
    log_repo = _log_repo(log)
    if repo and log_repo and log_repo != repo:
        return f"view-only — live log on this machine is for '{log_repo}', not '{repo}'"
    return None


def _read_log(repo: str | None, active: str) -> tuple[dict | None, str]:
    """The stress log both sprint routes read, and the one reason it is not used.

    ``(log, "ok")`` when the file is there, is an object, and is this Space's and this repository's
    (``_log_refusal``); otherwise ``(None, reason)`` -- missing, unreadable, not an object, or
    another Space's or repository's. No shape of the file raises."""
    path = _stress_log_path(repo)
    if not path.exists():
        return None, _NO_LOG
    try:
        log = json.loads(path.read_text(encoding="utf-8-sig"))
    except (ValueError, OSError) as exc:
        return None, f"could not read stress-log.json: {exc.__class__.__name__}"
    if not isinstance(log, dict):
        return None, "could not read stress-log.json: it is not an object"
    refusal = _log_refusal(log, active, repo)
    return (None, refusal) if refusal else (log, "ok")


def _active_org(cfg: dict) -> dict:
    active = cfg.get("activeSpace", "")
    return next((o for o in (cfg.get("spaces") or []) if o.get("slug") == active), {})


@api.get("/stress-status", response_model=StressStatusResponse)
async def get_stress_status(repo: str | None = None):
    repo = _repo_key(repo)
    cfg = load_config()
    active = cfg.get("activeSpace", "")

    # Gate: feature off ⇒ report off without reading the log.
    if not _active_space_feature("sprintAwareness"):
        return StressStatusResponse(
            enabled=False,
            org=active,
            detail="sprint awareness is off for this org",
        )

    org = _active_org(cfg)
    log, detail = _read_log(repo, active)
    if log is None:
        return StressStatusResponse(
            enabled=True,
            org=active,
            detail=detail,
            context=_config_sprint_context(org, repo),
        )

    days = _days_left(log, org)
    dims = _classify_stress(log, days)
    return StressStatusResponse(
        enabled=True,
        org=active,
        detail="ok",
        generatedAt=_text(log.get("generatedAt")),
        sourceRepo=_text(log.get("sourceRepo")),
        sprintSource=_text(log.get("sprintSource")),
        context=_stress_context(log, days),
        sprintStress=StressDimension(**dims["sprintStress"]),
        originStress=StressDimension(**dims["originStress"]),
        communicationStress=StressDimension(**dims["communicationStress"]),
        teamDynamicsStress=StressDimension(**dims["teamDynamicsStress"]),
    )


# GET /api/stress-sprint-activity — per-day mine/team activity for SprintVelocity
#
# Reads {slug}/stress-history.{repoName}.json from the hub -- a
# per-slug, per-repo full sprint-window cache derived from git. Repo name is
# the asked repo, else the log's (repoKey, else sourceRepo's last segment).
# Parallel to /api/stress-status -- separate call, the same log reader, so a log
# the status route refuses frames no window here either. Gated on
# features.sprintAwareness; returns an empty window when the feature is off.
# ---------------------------------------------------------------------------
def _repo_name_from_url(url: str) -> str:
    clean = url.rstrip("/\\").removesuffix(".git")
    parts = [p for p in clean.replace("\\", "/").split("/") if p]
    return parts[-1] if parts else "default"


class SprintActivityEntry(BaseModel):
    date: str
    count: int
    # Lines added + deleted on the default branch that day. Defaults to 0 so pre-churn
    # history files read as "not recorded".
    churn: int = 0


class SprintActivityResponse(BaseModel):
    startDate: str
    endDate: str
    mine: list[SprintActivityEntry]
    team: list[SprintActivityEntry]
    # Why the stress log framed this window or did not, in the status route's words: "ok", or
    # the reason it was not used. Absent where sprint awareness is off.
    detail: str | None = None


def _row_date(row: dict) -> str:
    return _text(row.get("date")) or ""


def _window_start(end_date: str) -> str:
    """With no history to say where the sprint started, an estimate back from its end."""
    end_dt = _day(end_date) or _today()
    return (end_dt - timedelta(days=20)).isoformat()


@api.get("/stress-sprint-activity", response_model=SprintActivityResponse, response_model_exclude_none=True)
async def get_sprint_activity(repo: str | None = None):
    repo = _repo_key(repo)
    cfg = load_config()
    active = cfg.get("activeSpace", "")
    today = _today().isoformat()

    if not _active_space_feature("sprintAwareness"):
        return SprintActivityResponse(startDate=today, endDate=today, mine=[], team=[])

    # Sprint frame + repo from stress-log.json (live, this-machine signal), only when
    # the log is this Space's and this repository's -- the status route's own check.
    end_date = today
    sprint_name: str | None = None
    log_repo: str | None = None
    log, detail = _read_log(repo, active)
    if log is not None:
        sprint = _object(log.get("sprint"))
        end_date = _text(sprint.get("endDate")) or today
        sprint_name = _text(sprint.get("name"))
        log_repo = _log_repo(log)

    # Resolve per-slug, per-repo history path. Prefer the explicit `repo` query
    # param (view path — works with no live stress-log at all, e.g. a machine
    # with no local stress log) over the log's own repository.
    folder = _active_org(cfg).get("promptsFolder", "")
    org_dir = (hub_root() / folder) if folder else hub_root()
    repo_name = repo or log_repo or "default"
    raw = _read_history(org_dir, repo_name)

    # If the live log didn't give us a sprint name (missing/stale/wrong repo),
    # fall back to the committed history file's own latest sprint label so
    # view-only machines still see data — no ephemeral log required.
    if not sprint_name and raw:
        latest = max(raw, key=_row_date)
        sprint_name = _text(latest.get("sprint"))
        end_date = max((_row_date(e) for e in raw), default=end_date) or end_date

    # No sprint name means we can't scope history — return empty shell
    if not sprint_name:
        return SprintActivityResponse(
            startDate=_window_start(end_date), endDate=end_date, mine=[], team=[], detail=detail
        )

    # Read history — file is already scoped to org+repo; filter to current sprint only.
    # Deduplicate by date (safety net; full rewrite should already be clean).
    by_date: dict[str, dict] = {}
    for entry in raw:
        d = _row_date(entry)
        if d and entry.get("sprint") == sprint_name:
            by_date[d] = entry

    # startDate: earliest history date for this sprint (git is source of truth when
    # history exists); fallback estimates from endDate without assuming sprint length.
    start_date = min(by_date.keys()) if by_date else _window_start(end_date)

    def entries(count: str, churn: str) -> list[SprintActivityEntry]:
        return [
            SprintActivityEntry(date=d, count=_int(e.get(count), 0), churn=_int(e.get(churn), 0))
            for d, e in sorted(by_date.items())
        ]

    return SprintActivityResponse(
        startDate=start_date,
        endDate=end_date,
        mine=entries("mine", "mineChurn"),
        team=entries("team", "teamChurn"),
        detail=detail,
    )


class StressRepoInfo(BaseModel):
    name: str
    hasLocalCheckout: bool
    hasData: bool


class StressReposResponse(BaseModel):
    repos: list[StressRepoInfo]
    defaultRepo: str | None = None


def _alias_paths_by_basename() -> dict[str, str]:
    """The toolkit's global `aliases` map (config.local.json, `go<Name>`
    shortcuts) already resolves every project the engineer works with to a
    local path on this machine — that's the same signal 'is this checked out
    here' needs, and it's the toolkit's existing source of truth for local
    paths rather than a sprint-awareness-specific one. Keyed by path basename
    so a repo name matches the nav alias pointing at that checkout without
    assuming the alias key itself follows any naming convention."""
    try:
        defaults = json.loads(DEFAULT_CONFIG_PATH.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        defaults = {}
    try:
        local = json.loads(LOCAL_CONFIG_PATH.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        local = {}
    aliases = {**(defaults.get("aliases") or {}), **(local.get("aliases") or {})}
    result: dict[str, str] = {}
    for alias in aliases.values():
        path_str = alias.get("path") if isinstance(alias, dict) else None
        if path_str:
            result[Path(path_str).name] = path_str
    return result


@api.get("/stress-repos", response_model=StressReposResponse)
async def get_stress_repos():
    """List repos this org can show sprint data for, sourced from the org's
    `projects` config — the same field EngagementSummary/WorkBreakdown already
    scope to, and already present wherever a project is set up. No dependency
    on the gitignored, machine-local stress-log.json for repo identity: this
    endpoint's job is just to say what's known and what of that is
    viewable/runnable on this machine."""
    if not _active_space_feature("sprintAwareness"):
        return StressReposResponse(repos=[], defaultRepo=None)

    cfg = load_config()
    active = cfg.get("activeSpace", "")
    org = next((o for o in (cfg.get("spaces") or []) if o.get("slug") == active), {})
    projects: list[dict] = org.get("projects") or []
    repo_paths: dict = org.get("repoPaths") or {}
    folder = org.get("promptsFolder", "")
    org_dir = (hub_root() / folder) if folder else hub_root()
    alias_paths = _alias_paths_by_basename()

    # Only projects that actually declare a `repo` — a project entry with no
    # `repo` (docs, design, non-code work) has no git signal to ever show and
    # must not fall back to its display `name` as if it were one.
    names = [p["repo"] for p in projects if p.get("repo") and p.get("hasRepo", True)]

    def _is_local_checkout(path_str: str) -> bool:
        # Directory existence alone isn't enough — a stale/emptied/wrong
        # folder at a configured path would otherwise read as "Local".
        path = Path(path_str)
        return path.is_dir() and (path / ".git").exists()

    def _local_checkout_path(name: str) -> str | None:
        # repoPaths (org-scoped) is an explicit override for when the
        # alias-named-after-the-repo convention does not apply -- a nav alias
        # is often named for the client, not the repository. Checked first so
        # it wins.
        return repo_paths.get(name) or alias_paths.get(name)

    repos = [
        StressRepoInfo(
            name=name,
            hasLocalCheckout=bool(_local_checkout_path(name)) and _is_local_checkout(_local_checkout_path(name)),
            hasData=(org_dir / f"stress-history.{name}.json").exists(),
        )
        for name in names
    ]

    default_repo: str | None = None
    if _stress_log_default().exists():
        try:
            log = json.loads(_stress_log_default().read_text(encoding="utf-8-sig"))
            # stress-log.json is a single global file — only trust its repoKey
            # when it was actually written for the active Space, else a stale
            # run from a different org leaks its selection in here.
            if isinstance(log, dict) and log.get("org") == active:
                default_repo = log.get("repoKey") or None
        except (json.JSONDecodeError, OSError):
            pass
    if (default_repo is None or default_repo not in names) and repos:
        default_repo = repos[0].name

    return StressReposResponse(repos=repos, defaultRepo=default_repo)
