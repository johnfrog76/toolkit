"""Core shell routes: /health, /env, /switch-mode.

/env is what the web shell gates on before it renders anything, so it answers
three questions in one round trip: can the hub be read, what tier are we at,
and which optional features are on for the active Space.
"""

import asyncio
import json
import os
import platform
import socket
import time
from dataclasses import dataclass

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from . import consts, log_writer, model
from .config import (
    LOCAL_CONFIG_PATH,
    REPO_ROOT,
    ado_enabled,
    anthropic_configured,
    card_types,
    how_i_work,
    hub_configured,
    hub_detail,
    hub_manifest_detail,
    hub_root,
    lane_names,
    load_config,
    offered_spaces,
    read_config_file,
    renamed_slug,
    resolve_dirs,
    tracker,
)
from .hosts import host_env_block
from .identity import identity_block, identity_cache_clear
from .tier import _resolve_tier, probe_cache_clear

api = APIRouter()


def _warn(detail: str) -> None:
    log_writer.write_log("WARN", "agent/env", detail)


def _display_name(cfg: dict, identity: dict | None = None) -> str:
    """Who the shell greets. The config's branchUser if set, else the local
    part of the email -- the configured one, or the one the identity chain
    RESOLVED (az), so the avatar and the Environment card's Identity row never
    name two different people -- else a neutral fallback, so a fresh clone
    shows a name that belongs to nobody."""
    branch_user = (cfg.get("branchUser") or "").strip()
    if branch_user:
        return branch_user
    email = (cfg.get("email") or (identity or {}).get("email") or "").strip()
    if email and "@" in email:
        local_part = email.split("@", 1)[0].strip()
        if local_part:
            return local_part
    if email:
        return email
    return "Toolkit"


# GET /api/health
# ---------------------------------------------------------------------------
@api.get("/health")
async def health():
    root = hub_root()
    current_dir, _ = resolve_dirs()
    prompts_ok = root.exists() and current_dir.exists()
    return {
        "status": "ok" if prompts_ok else "degraded",
        "prompts_root": str(root) if hub_configured() else "",
        "prompts_readable": prompts_ok,
        # Which checkout this agent runs from. prompts_root says whose DATA it
        # serves; this says whose PROCESS it is, so Start-Agent.ps1 can stop an
        # agent this checkout started from another shell -- and restart one
        # serving a hub the caller's environment no longer asks for -- without
        # touching another package's.
        "package_root": str(REPO_ROOT),
    }


# GET /api/env — environment tier detection (ported from Express)
# ---------------------------------------------------------------------------
def _git_history_check(git_present: bool, store_sync: str) -> dict:
    """The Git history row. A hub that is not a repository is a first-class case
     (storeSync 'none', docs/CONFIGURATION.md) and the hub every first run makes,
     so `.git not found` in red told a new user something was wrong with a
     machine doing exactly what it was told. It FAILS only when git was wanted
    ."""
    if git_present:
        return {"ok": True, "detail": ".git found"}
    if store_sync == "git":
        return {"ok": False, "detail": ".git not found -- storeSync is 'git', so the hub should be a repository"}
    return {"ok": True, "detail": "not a git repository -- storeSync is 'none', nothing reads history"}


def _identity_check(identity: dict, ado_on: bool) -> dict:
    """The Identity row. Who a work item is assigned to, and who the PR routes
    filter by: with Azure DevOps not in use nothing reads it, so an empty one is
    a note rather than a failure."""
    email = (identity or {}).get("email") or ""
    if email:
        return {"ok": True, "detail": f"{email} (from {identity['source']})"}
    if not ado_on:
        return {"ok": True, "detail": "not set -- only Azure DevOps uses it"}
    return {"ok": False, "detail": "no identity -- set `email` in config.local.json, or run `az login`"}


def _ado_access_check(space_status: str, org_url: str, reachable: bool) -> dict:
    """The "ADO Add-on" row. Only an ACTIVE org can fail it.

    Azure DevOps is an add-on (docs/modules/ado.md), so a local org
    without it is the expected shape, not a gap. Scripts/Get-Environment.ps1 prints
    the same words.
    """
    if space_status == "archive":
        return {"ok": True, "detail": "not contacted -- archived"}
    if space_status == "local":
        return {"ok": True, "detail": "not configured (expected)"}
    name = org_url.rstrip("/").split("/")[-1] if org_url else ""
    if reachable:
        return {"ok": True, "detail": f"connected ({name})"}
    return {"ok": False, "detail": f"unreachable ({name})" if org_url else "no org URL configured"}


@dataclass(frozen=True)
class _Probe:
    """What /env learned by looking: the hub on disk, the tracker, the bridge's
    host and who "me" is. Gathered once per request by ``_probe``; the check rows
    and the top-level fields both read it, so nothing is asked twice."""

    prompts_readable: bool
    prompts_writable: bool
    git_history: bool
    active_count: int
    tier: int
    ado_reachable: bool
    bridge_host: dict
    identity: dict


async def _probe(cfg: dict, refresh: int) -> _Probe:
    """Every probe /env reports, gathered in one place."""
    org_url = cfg.get("org", "")
    root = hub_root()
    # Check 1: Prompts volume readable. An unconfigured or missing promptsRoot
    # is a plain report, not an exception -- every read route below degrades.
    prompts_readable = root.exists()

    # Check 2: Prompts writable
    prompts_writable = os.access(str(root), os.W_OK) if prompts_readable else False

    # Check 4: Git history available
    git_history = (root / ".git").exists()

    # Check 5: Active prompts count
    active_count = 0
    current_dir, _ = resolve_dirs()
    if current_dir.exists():
        for f in current_dir.iterdir():
            if f.is_file() and f.name.endswith(".prompt.md"):
                active_count += 1

    # Check 6 + tier: probe ADO and resolve tier via shared helper.
    #
    # OFF THE EVENT LOOP. _resolve_tier shells out to `az` -- 3-4s warm, 15s
    # when it hangs -- and this handler is async, so running it inline blocked
    # the whole agent for the length of the probe: /health and /status, which
    # touch nothing, queued behind it and the browser's own gate sat there.
    #
    # Every other tier-resolving route already did this; /env was the one that
    # did not.
    tier, ado_reachable = await asyncio.to_thread(_resolve_tier, org_url, cfg.get("status", ""), bool(refresh))

    # Check 7: which PowerShell the bridge will start. Reported because the
    # web half's entire write path is that child process, and a machine with
    # neither host can only be told so here -- a button that fails on click is
    # how a Windows PowerShell-only machine found this.
    bridge_host = host_env_block()

    # Check 8: who "me" is, and where that came from. Reported because the three
    # ADO routes filter by it and a machine with no `email` in its own
    # config.local.json rendered a config gap as "you have no pull requests".
    #
    # OFF THE EVENT LOOP for the same reason the tier probe is: the fallback is
    # a cold `az account show`. Behind the same TTL, so a burst of page loads
    # costs one probe.
    identity = await asyncio.to_thread(identity_block, bool(refresh))

    return _Probe(
        prompts_readable=prompts_readable,
        prompts_writable=prompts_writable,
        git_history=git_history,
        active_count=active_count,
        tier=tier,
        ado_reachable=ado_reachable,
        bridge_host=bridge_host,
        identity=identity,
    )


def _module_blocks(cfg: dict) -> dict:
    """What a module adds to /env, asked of the module rather than known here.

    The communication module needs one thing reported before any of its UI
    renders: whether each recipient's webhook environment variable is actually
    set. That is gate 2, it can only be answered at runtime, and discovering
    it on click is how a send button lies about being available.

    The import is lazy AND inside the flag check on purpose. core does not
    depend on a module -- it asks one that is switched on to describe itself,
    and a checkout without the module still serves /env. A module that cannot
    describe itself is not fatal, and it is not silent either: its block is left
    out and the log says why.
    """
    module_blocks = {}
    if (cfg.get("features") or {}).get("communication"):
        try:
            from ..communication.manager import communication_env

            module_blocks["communication"] = communication_env()
        except Exception as exc:  # noqa: BLE001 -- a module that cannot describe itself is not fatal
            _warn(f"communication could not describe itself: {exc}")
    return module_blocks


def _org_state_label(space_status: str, tier: int) -> str:
    """Org state -- full | local | archive (active surfaces as "full"). This is the
    three-way status the tier badge can't show, since local and archive are both
    Tier 2. Informational row; always "ok".

    Derived from the resolved tier, not raw config status: active + probe pass =
    full; active + probe fail = local (Tier 2); local/archive always = their label.
    """
    if space_status == "archive":
        return "archive"
    if space_status == "local":
        return "local"
    if tier == 1:
        return "full"
    return "local"


def _checks(cfg: dict, probe: _Probe, ado_on: bool) -> dict:
    """The ``checks`` rows -- one {ok, detail} per row the Environment card lists."""
    org_url = cfg.get("org", "")
    space_status = cfg.get("status", "local")

    # Check 3: Config loaded
    config_loaded = bool(cfg)
    config_problems = cfg.get("configProblems") or []

    active_count = probe.active_count
    bridge_host = probe.bridge_host
    return {
        "promptsVolume": {
            "ok": probe.prompts_readable,
            "detail": hub_detail(),
        },
        # Whether the hub declared its own orgs. Informational, never a
        # failure: a hub with no hub.json is the ordinary case and every
        # org then comes from config alone.
        "hubManifest": {
            "ok": True,
            "detail": hub_manifest_detail(),
        },
        "promptsWritable": {
            "ok": probe.prompts_writable,
            "detail": "writable" if probe.prompts_writable else "read-only",
        },
        # A config file that would not parse is skipped, not fatal; this row
        # is where the user is told so (the sentence names the file).
        "configLoaded": {
            "ok": config_loaded and not config_problems,
            "detail": (
                " ".join(config_problems)
                if config_problems
                else ("config loaded" if config_loaded else "config not found")
            ),
        },
        "gitHistory": _git_history_check(probe.git_history, str(cfg.get("storeSync") or "none")),
        # An ARCHIVED org is supposed to have nothing in flight: none is the
        # expected answer there, not a failure.
        "activePrompts": {
            "ok": active_count > 0 or space_status == "archive",
            "detail": (
                "none -- an archived organisation has nothing in flight"
                if space_status == "archive" and active_count == 0
                else f"{active_count} active prompt{'s' if active_count != 1 else ''}"
            ),
        },
        # "Tried and failed" is a failure. "Never asked" is not: an archived org
        # and a local one are never probed (docs/CLI.md, "Tiers: what works without ADO"), so a red
        # "no org URL configured" told a person something was wrong with a
        # machine doing exactly what it was configured to do. The owner's rule:
        # "archive doesn't request at all, and local tried and failed."
        "adoReachable": _ado_access_check(space_status, org_url, probe.ado_reachable),
        "orgState": {
            "ok": True,
            "detail": _org_state_label(space_status, probe.tier),
        },
        # Not ok when nothing resolved: the PR routes filter by this address
        # and return empty without it, which is a config gap rather than an
        # empty board.
        "identity": _identity_check(probe.identity, ado_on),
        "bridgeHost": {
            "ok": bridge_host["resolved"] is not None,
            "detail": (
                f"{bridge_host['resolved']} ({bridge_host['path']})"
                if bridge_host["resolved"]
                else "no pwsh or powershell on PATH"
            ),
        },
    }


def _config_block(cfg: dict) -> dict:
    """The ``config`` block: the active Space's settings and the Spaces offered."""
    return {
        "org": cfg.get("org", ""),
        "projects": cfg.get("projects", []),
        "promptsFolder": cfg.get("promptsFolder", ""),
        "activeSpace": cfg.get("activeSpace", ""),
        # What a person is OFFERED -- the switcher, Settings, Reviews' org
        # chips all read this list, so none of them needs a rule of its own.
        # Each carries the tracker its address names (D-G2), derived here
        # and never in the browser: the Studio's foyer is one row per
        # GitHub Space (D-S2), and it asks this list which those are.
        # Each carries its lane names too, resolved the way the active
        # Space's `laneNames` below is ({contract word: display name}), so
        # the foyer counts another Space's cards under ITS names.
        "spaces": [
            {**o, "tracker": tracker(o.get("org", "")), "laneNames": lane_names(o)}
            for o in offered_spaces(
                cfg.get("spaces", []), cfg.get("activeSpace", ""), cfg.get("isDemoDismissed", False)
            )
        ],
        "isDemoDismissed": bool(cfg.get("isDemoDismissed", False)),
        # {contract word: display name} for the active Space's lanes.
        "laneNames": cfg.get("laneNames", {}),
        # The first-run banner's switch. The web renders it only when this
        # is true AND the deck module is on.
        "firstRunWelcome": bool((cfg.get("firstRun") or {}).get("welcome", False)),
    }


@api.get("/env")
async def get_env(refresh: int = 0):
    """The one round trip the web shell gates on.

    ``?refresh=1`` bypasses the reachability cache. Everything else reads a
    probe that is at most ADO_PROBE_TTL_SECONDS old, because the shell gates
    EVERY page on this route and the probe is a cold `az` start.

    Composed from three parts: what was probed (``_probe``), the check rows
    built from it (``_checks``) and the config block (``_config_block``). The
    top-level keys and their order are the shell's contract, so they are all
    written in the one literal below.
    """
    cfg = load_config()
    org_url = cfg.get("org", "")
    probe = await _probe(cfg, refresh)
    tier = probe.tier
    identity = probe.identity
    bridge_host = probe.bridge_host
    module_blocks = _module_blocks(cfg)
    # Whether Azure DevOps is part of what is SHOWN -- derived once, read by the
    # `ado` block and by the Identity row.
    ado_on = ado_enabled(cfg.get("status", "local"), (cfg.get("features") or {}).get("ado"), tracker(org_url))

    tier_labels = {1: "Full (Tier 1)", 2: "Local (Tier 2)", 3: "Minimal (Tier 3)"}

    return {
        # Which build this is -- consts.json's version, the same string Env prints.
        "version": consts.version(),
        "machine": socket.gethostname(),
        "os": f"{platform.system()} {platform.machine()}",
        "pythonVersion": platform.python_version(),
        "container": False,
        "tier": tier,
        "tierLabel": tier_labels[tier],
        "spaceStatus": cfg.get("status", "local"),
        # What the hub itself declared -- read/not read, and how many orgs.
        "hub": cfg.get("hub", {"manifest": False, "path": "", "spaces": 0}),
        "hubFolders": cfg.get("hubFolders", {}),
        "features": cfg.get("features", {}),
        # Whether Azure DevOps is part of what is SHOWN -- derived here, once, so
        # the web never re-derives it. `explicit` says whether someone set
        # features.ado or the org answered (docs/modules/ado.md).
        "ado": {
            "enabled": ado_on,
            "explicit": "ado" in (cfg.get("features") or {}),
        },
        # WHICH tracker the active board's address names -- "ado", "github" or
        # "none" -- derived here, once, so the web never re-derives it
        # (D-G2). Whether it is contacted
        # is the tier's business, as ever.
        "tracker": tracker(org_url),
        # How do you want to work in this Space? -- the active Space's
        # answer, resolved once in load_config: answer, source (derived, chosen
        # or default), tracker, locked, and Team Agile's switch as set. The
        # Settings control draws from it and never re-derives it.
        "howIWork": cfg.get("howIWork") or how_i_work(org_url),
        "anthropicConfigured": anthropic_configured(),
        # The provider profile: what every model call sends, from ai.model.
        "aiModel": model.model_id(),
        "bridgeHost": bridge_host,
        "displayName": _display_name(cfg, identity),
        # The prefix every verb is typed with here, so the web UI can name a
        # real command instead of a bare verb.
        "cliPrefix": cfg.get("commandPrefix", ""),
        # CardType names (docs/hub/cards.md, "The filename"), in config's order, so
        # the web's "New card" dialog offers a team's own types and never a
        # hardcoded four.
        "cardTypes": card_types(cfg)[0],
        # {email, source} -- source is "config", "branchUser", "az" or "" when
        # nothing answered. tkEnv prints the same two facts.
        "identity": identity,
        "uptime": int(time.monotonic()),
        "checks": _checks(cfg, probe, ado_on),
        **module_blocks,
        "config": _config_block(cfg),
    }


# ---------------------------------------------------------------------------
# POST /api/switch-mode — swap active org and reload in-memory
# ---------------------------------------------------------------------------
class SwitchModeRequest(BaseModel):
    mode: str  # org slug, as listed in config.default.json spaces[]


@api.post("/switch-mode")
async def switch_mode(body: SwitchModeRequest):
    slug = body.mode.lower()
    # Validate slug against orgs array
    orgs = load_config().get("spaces", [])
    valid_slugs = [o["slug"] for o in orgs]
    # A renamed shipped Space's old slug is the new one (test -> azure-demo).
    slug = renamed_slug(slug, valid_slugs)
    if slug not in valid_slugs:
        raise HTTPException(status_code=400, detail=f"Unknown Space: {slug}. Available: {', '.join(valid_slugs)}")
    # Write activeSpace into config.local.json -- the file's spelling since
    # the Space rename; a file that still said activeOrg comes out saying the new
    # name and not the old.
    local_path = LOCAL_CONFIG_PATH
    local, problem = read_config_file(local_path)
    if problem:
        # Writing activeSpace into a file we could not read would replace
        # whatever the person had in it; say so and leave it alone.
        raise HTTPException(status_code=409, detail=problem)
    local.pop("activeOrg", None)
    local["activeSpace"] = slug
    local_path.write_text(json.dumps(local, indent=2) + "\n", encoding="utf-8")
    # A different org is a different question, and the answer the cache holds is
    # the old org's. Probe again rather than report the previous org's tier --
    # and re-resolve identity, since a different org may be configured with a
    # different address.
    probe_cache_clear()
    identity_cache_clear()
    return await get_env(refresh=1)
