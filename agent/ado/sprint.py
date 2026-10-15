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
from datetime import date
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


def _classify_stress(log: dict) -> dict:
    """Classify a stress-log dict into the four risk dimensions.

    This is the only implementation in this package: the PowerShell twin it
    was parity-tested against did not come across, because sprint awareness is
    off by default here and no command writes the log. The rules are carried
    unchanged so that a hub which already has a stress-log.json reads the same
    way it did.
    """
    sprint = log.get("sprint") or {}
    origin = log.get("origin") or {}
    comm = log.get("communication") or {}
    team = log.get("teamDynamics") or {}

    days = int(sprint.get("daysRemaining", 99))
    velocity = int(sprint.get("mergeVelocity", 0))
    refactor = bool(sprint.get("refactorWaveActive", False))
    int_window = bool(sprint.get("integrationWindowClosing", False))

    upstream = int(origin.get("upstreamMerges", 0))
    surface = int(origin.get("surfaceAreaChange", 0))
    conflicts = len(origin.get("conflictZones") or [])
    rebase = origin.get("rebasePressure") or _rebase_pressure(upstream, surface)

    broadcasted = bool(comm.get("prBroadcasted", False))
    visibility = float(comm.get("visibilityScore", 0.5))
    cadence = comm.get("updateCadence", "Normal")

    xxl = len(team.get("xxlPrAuthors") or [])
    silent = len(team.get("silentRefactorers") or [])

    # sprintStress
    sprint_high = _held(
        [
            ("daysRemaining <= 3", days <= 3),
            ('rebasePressure == "High"', rebase == "High"),
            ("mergeVelocity >= 10", velocity >= 10),
            ("refactorWaveActive == true", refactor),
            ("integrationWindowClosing == true", int_window),
        ]
    )
    sprint_medium = _held(
        [
            ("daysRemaining <= 5", days <= 5),
            ('rebasePressure == "Medium"', rebase == "Medium"),
        ]
    )
    sprint_low = _held(
        [
            ("daysRemaining > 5", days > 5),
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


def _stress_context(log: dict) -> StressContext:
    sprint = log.get("sprint") or {}
    origin = log.get("origin") or {}
    comm = log.get("communication") or {}
    return StressContext(
        sprintName=str(sprint.get("name", "Sprint")),
        sprintFullName=str(sprint.get("fullName", sprint.get("name", "Sprint"))),
        daysRemaining=int(sprint.get("daysRemaining", 0)),
        mergeVelocity=int(sprint.get("mergeVelocity", 0)),
        upstreamMerges=int(origin.get("upstreamMerges", 0)),
        surfaceAreaChange=int(origin.get("surfaceAreaChange", 0)),
        rebasePressure=str(origin.get("rebasePressure", "Low")),
        conflictZones=list(origin.get("conflictZones") or []),
        prBroadcasted=bool(comm.get("prBroadcasted", False)),
        visibilityScore=float(comm.get("visibilityScore", 0.5)),
        updateCadence=str(comm.get("updateCadence", "Normal")),
    )


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
        hist_path = org_dir / f"stress-history.{repo}.json"
        if hist_path.exists():
            try:
                raw = json.loads(hist_path.read_text(encoding="utf-8-sig"))
                if isinstance(raw, list) and raw:
                    latest = max(raw, key=lambda e: e.get("date", ""))
                    name = latest.get("sprint")
            except (json.JSONDecodeError, OSError):
                pass
    name = str(name or "Sprint")
    end_date_str = sprint.get("endDate")
    days_remaining: int | None
    if end_date_str:
        try:
            end_dt = date.fromisoformat(end_date_str)
            days_remaining = max((end_dt - date.today()).days, 0)
        except ValueError:
            days_remaining = None
    else:
        # No end date configured -- don't fabricate a countdown. A hardcoded
        # +7 was wrong for any org whose sprint is not a fortnight starting
        # where the one it was written against started.
        days_remaining = None
    return StressContext(sprintName=name, sprintFullName=name, daysRemaining=days_remaining)


def _stress_log_path(repo: str | None) -> Path:
    """Resolve the stress-log path for an optional repo key, falling back to
    the unnamespaced file when repo is omitted or its namespaced file is absent."""
    if repo:
        namespaced = hub_root() / f"stress-log.{repo}.json"
        if namespaced.exists():
            return namespaced
    return _stress_log_default()


@api.get("/stress-status", response_model=StressStatusResponse)
async def get_stress_status(repo: str | None = None):
    cfg = load_config()
    active = cfg.get("activeSpace", "")

    # Gate: feature off ⇒ report off without reading the log.
    if not _active_space_feature("sprintAwareness"):
        return StressStatusResponse(
            enabled=False,
            org=active,
            detail="sprint awareness is off for this org",
        )

    org = next((o for o in (cfg.get("spaces") or []) if o.get("slug") == active), {})

    log_path = _stress_log_path(repo)
    if not log_path.exists():
        return StressStatusResponse(
            enabled=True,
            org=active,
            detail="view-only -- no live signal on this machine; "
            "the stress log is written where the repo is checked out",
            context=_config_sprint_context(org, repo),
        )

    try:
        log = json.loads(log_path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError) as exc:
        return StressStatusResponse(
            enabled=True,
            org=active,
            detail=f"could not read stress-log.json: {exc}",
            context=_config_sprint_context(org, repo),
        )

    # Stale-guard: the log is a single, non-namespaced file. If it was generated
    # for a different org (you switched orgs without rebuilding), refuse to serve
    # cross-org data — report stale instead of silently showing the wrong org.
    log_org = log.get("org")
    if log_org and log_org != active:
        return StressStatusResponse(
            enabled=True,
            org=active,
            detail=f"view-only — live log on this machine is for '{log_org}'",
            context=_config_sprint_context(org, repo),
        )

    # Same guard, per-repo: _stress_log_path falls back to the unnamespaced
    # stress-log.json when no stress-log.<repo>.json exists. Without this
    # check, a multi-repo org would silently show one repo's live numbers
    # under a different repo's name whenever a namespaced log is missing —
    # same org passes the check above, but it's still the wrong repo's data.
    log_repo_key = log.get("repoKey")
    if repo and log_repo_key and log_repo_key != repo:
        return StressStatusResponse(
            enabled=True,
            org=active,
            detail=f"view-only — live log on this machine is for '{log_repo_key}', not '{repo}'",
            context=_config_sprint_context(org, repo),
        )

    dims = _classify_stress(log)
    return StressStatusResponse(
        enabled=True,
        org=log.get("org", active),
        detail="ok",
        generatedAt=log.get("generatedAt"),
        sourceRepo=log.get("sourceRepo"),
        sprintSource=log.get("sprintSource"),
        context=_stress_context(log),
        sprintStress=StressDimension(**dims["sprintStress"]),
        originStress=StressDimension(**dims["originStress"]),
        communicationStress=StressDimension(**dims["communicationStress"]),
        teamDynamicsStress=StressDimension(**dims["teamDynamicsStress"]),
    )


# GET /api/stress-sprint-activity — per-day mine/team activity for SprintVelocity
#
# Reads {slug}/stress-history.{repoName}.json from the hub -- a
# per-slug, per-repo full sprint-window cache derived from git. Repo name is
# extracted from stress-log.json's sourceRepo field (last path segment, no .git).
# Parallel to /api/stress-status — separate call, separate cache. Gated on
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


@api.get("/stress-sprint-activity", response_model=SprintActivityResponse)
async def get_sprint_activity(repo: str | None = None):
    from datetime import timedelta

    cfg = load_config()
    active = cfg.get("activeSpace", "")
    today = date.today().isoformat()

    if not _active_space_feature("sprintAwareness"):
        return SprintActivityResponse(startDate=today, endDate=today, mine=[], team=[])

    # Sprint frame + sourceRepo from stress-log.json (live, this-machine signal)
    end_date = today
    sprint_name: str | None = None
    source_repo = ""
    repo_key = ""
    log_path = _stress_log_path(repo)
    if log_path.exists():
        try:
            log = json.loads(log_path.read_text(encoding="utf-8-sig"))
            if log.get("org") == active:
                sprint = log.get("sprint") or {}
                end_date = sprint.get("endDate") or today
                sprint_name = sprint.get("name")
                source_repo = log.get("sourceRepo") or ""
                repo_key = log.get("repoKey") or ""
        except (json.JSONDecodeError, OSError):
            pass

    # Resolve per-slug, per-repo history path. Prefer the explicit `repo` query
    # param (view path — works with no live stress-log at all, e.g. a machine
    # with no local stress log) over
    # repoKey/sourceRepo from the ephemeral log, since the log may be stale,
    # missing, or belong to a different repo than the one the UI has selected.
    org_config = next((o for o in (load_config().get("spaces") or []) if o.get("slug") == active), {})
    folder = org_config.get("promptsFolder", "")
    org_dir = (hub_root() / folder) if folder else hub_root()
    repo_name = repo or repo_key or (_repo_name_from_url(source_repo) if source_repo else "default")
    hist_path = org_dir / f"stress-history.{repo_name}.json"

    # If the live log didn't give us a sprint name (missing/stale/wrong repo),
    # fall back to the committed history file's own latest sprint label so
    # view-only machines still see data — no ephemeral log required.
    if not sprint_name and hist_path.exists():
        try:
            raw_probe = json.loads(hist_path.read_text(encoding="utf-8-sig"))
            if isinstance(raw_probe, list) and raw_probe:
                latest = max(raw_probe, key=lambda e: e.get("date", ""))
                sprint_name = latest.get("sprint")
                end_date = max((e.get("date", "") for e in raw_probe), default=end_date) or end_date
        except (json.JSONDecodeError, OSError):
            pass

    # No sprint name means we can't scope history — return empty shell
    if not sprint_name:
        try:
            end_dt = date.fromisoformat(end_date)
        except ValueError:
            end_dt = date.today()
        start_date = (end_dt - timedelta(days=20)).isoformat()
        return SprintActivityResponse(startDate=start_date, endDate=end_date, mine=[], team=[])

    # Read history — file is already scoped to org+repo; filter to current sprint only
    history: list[dict] = []
    if hist_path.exists():
        try:
            raw = json.loads(hist_path.read_text(encoding="utf-8-sig"))
            if isinstance(raw, list):
                history = [e for e in raw if e.get("sprint") == sprint_name]
        except (json.JSONDecodeError, OSError):
            pass

    # Deduplicate by date (safety net; full rewrite should already be clean)
    by_date: dict[str, dict] = {}
    for entry in history:
        d = entry.get("date", "")
        if d:
            by_date[d] = entry

    # startDate: earliest history date for this sprint (git is source of truth when
    # history exists); fallback estimates from endDate without assuming sprint length.
    if by_date:
        start_date = min(by_date.keys())
    else:
        try:
            end_dt = date.fromisoformat(end_date)
        except ValueError:
            end_dt = date.today()
        start_date = (end_dt - timedelta(days=20)).isoformat()

    mine_entries = [
        SprintActivityEntry(date=d, count=int(e.get("mine") or 0), churn=int(e.get("mineChurn") or 0))
        for d, e in sorted(by_date.items())
    ]
    team_entries = [
        SprintActivityEntry(date=d, count=int(e.get("team") or 0), churn=int(e.get("teamChurn") or 0))
        for d, e in sorted(by_date.items())
    ]

    return SprintActivityResponse(
        startDate=start_date,
        endDate=end_date,
        mine=mine_entries,
        team=team_entries,
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
            if log.get("org") == active:
                default_repo = log.get("repoKey") or None
        except (json.JSONDecodeError, OSError):
            pass
    if (default_repo is None or default_repo not in names) and repos:
        default_repo = repos[0].name

    return StressReposResponse(repos=repos, defaultRepo=default_repo)
