"""Configuration and hub-path resolution.

Two jobs, and the second is the reason this file exists:

1. Load ``config.default.json`` + ``config.local.json`` with exactly the merge
   semantics the CLI uses (``Merge-SpacePatch`` in ``utilities.psm1``).
2. Resolve the **hub** -- the prompt store -- from ``promptsRoot`` in that
   config, never from the shape of the repository this code happens to sit in.

The package this was carved from resolved the hub as the parent folder of the
toolkit directory, which silently required the toolkit to live *inside* the
prompt store. It does not have to, and here it does not: the hub is wherever
``promptsRoot`` says, the per-org subfolder is ``spaces[].promptsFolder``, and a
``PROMPTS_ROOT`` environment variable remains only as an explicit override.

When ``promptsRoot`` is unset or points at a folder that is not there, nothing
raises: ``hub_root()`` returns a path that does not exist, ``/env`` says so in
words, and every read route degrades to empty.

The hub may also declare **its own orgs**. ``<promptsRoot>/hub.json`` is
optional, belongs to the engineer's data rather than to the tool, and is read
after ``config.default.json`` and before ``config.local.json`` -- see
``read_hub_manifest`` for the rules and docs/CONFIGURATION.md for the reasoning. A
private org therefore never has to be written into the committed file.
"""

import json
import os
import shutil
from pathlib import Path
from typing import Any

from . import log_writer
from .consts import (
    docs_readme,
    docs_root,
    env_active_space,
    env_features,
    folder_archive,
    folder_backlog,
    folder_current,
    renamed_spaces,
    space_scoped_features,
)

# agent/core/config.py -> agent/core -> agent -> repo root
CORE_DIR = Path(__file__).resolve().parent
AGENT_DIR = CORE_DIR.parent
REPO_ROOT = AGENT_DIR.parent

DEFAULT_CONFIG_PATH = REPO_ROOT / "config.default.json"
LOCAL_CONFIG_PATH = REPO_ROOT / "config.local.json"

# The agent's on-disk cache is capped by one rule (core/disk_cache.py, prune_seen
# and prune_folder): a record or file unseen for this many days goes, and past
# this many records the oldest-unseen go first. It covers the rows cache (one
# record per blob sha) and the standup's dress cache (one file per dressed reply).
AGENT_CACHE_MAX_RECORDS = 3000
AGENT_CACHE_MAX_AGE_DAYS = 30

# The shipped agentic prompts: the package's ``agentic/`` folder, each prompt a
# ``<name>.prompt.md``, and the index of which way of working each belongs to.
# The CLI's Scripts/Resolve-AgenticPrompt.ps1 names the same folder; the agent
# reads it for pr-suggest (ado/pr_comments.py) and the Studio's Prompts card
# (studio/prompts.py).
AGENTIC_DIR = REPO_ROOT / "agentic"
AGENTIC_INDEX = AGENTIC_DIR / "prompts.json"
PROMPT_SUFFIX = ".prompt.md"

# The module-private copy of the billing script: a path
# relative to the agent's own tree, not to the hub.
BILLING_SCRIPT = AGENT_DIR / "ado" / "Get-WeeklyBilling.ps1"

# Stand-in for "no hub configured". Deliberately a path that cannot exist, so
# every `.exists()` guard already in the read routes does the right thing
# without a second code path.
UNCONFIGURED_HUB = Path("/nonexistent-prompts-root")

# The hub's own manifest. Optional, lives at the hub root, and is the engineer's
# data -- "data separate from software". It declares orgs,
# hub-root folder names and how the store is synced, and nothing else: every
# machine-scoped key (``activeOrg``, ``promptsRoot``, ``email``, ``branchUser``,
# ``wsRoot``, ``web``, ``commands``, top-level ``features``) stays in config,
# and a copy here is ignored with a warning.
HUB_MANIFEST_NAME = "hub.json"
HUB_MANIFEST_KEYS = ("hub", "spaces", "orgs", "folders", "storeSync")

# The container is a SPACE (D-G13, stage 2). Its keys are ``spaces`` -- an
# array in config.default.json and hub.json, an object keyed by slug in
# config.local.json -- and ``activeSpace``. The older spelling, ``orgs`` and
# ``activeOrg``, is what every file on every machine carried before the Space rename,
# so both are READ: a parsed config comes out carrying the canonical (older)
# names the merge reads, the new spelling winning when a file has both. Nothing
# is written here; the writer follows in the next step. MUST mirror
# ``ConvertTo-P20SpaceKeys`` in Scripts/Resolve-HubConfig.ps1 --
# Tests/fixtures/hub-parity-spaces pins the two together.
SPACE_KEYS = (("spaces", "orgs"), ("activeSpace", "activeOrg"))


def space_keys(data):
    """Read the container's keys in both spellings; returns ``data`` itself,
    carrying the NEW names (stage 3): an older file's ``orgs`` / ``activeOrg``
    become ``spaces`` / ``activeSpace`` unless the file already says so, and
    the old keys are dropped so nothing downstream sees two spellings."""
    if not isinstance(data, dict):
        return data
    for new, old in SPACE_KEYS:
        if old in data:
            value = data.pop(old)
            if data.get(new) in (None, ""):
                data[new] = value
    return data
    for new, old in SPACE_KEYS:
        value = data.get(new)
        if value is not None and value != "":
            data[old] = value
    return data


# How the prompt store is kept in sync -- 'git' or 'none'. Whether the hub is a
# git repository is a fact about the HUB, not about the machine reading it, so
# the hub may declare it and both machines then agree without either one having
# to set it locally. A machine may still override (config.local.json), which is
# how a machine that must never push says so. MUST mirror
# Get-P20StoreSyncValues in Scripts/Resolve-HubConfig.ps1.
STORE_SYNC_VALUES = ("git", "none")

# The hub-root siblings the modules read, and the name each one has unless the
# hub says otherwise. One named constant per half, per AGENTS.md's "one place
# for magic strings" -- these used to be nine string literals across two
# languages. MUST mirror $script:DefaultHubFolders in utilities.psm1.
DEFAULT_HUB_FOLDERS = {
    "growth": "growth",
    "manager": "manager",
    "reviews": "reviews",
    "resume": "resume",
    "agentic": "agentic",
    # The Organize add-on's reminders -- named for the data, not the module.
    "reminders": "reminders",
    # The Studio's seed drawer: design notes that belong to no product yet (D-S3).
    "design": "design",
    # The hub's specs (design lifecycle L2): the same four folders a product
    # keeps -- design/, design/archive/, spec/, spec/archive/ -- at the hub's root (D-DL12).
    "spec": "spec",
}

DEFAULT_CORS_ORIGINS = [
    "http://localhost:5174",
    "http://localhost:5173",
]

# The one prefix every route is mounted under. app.py builds the router with
# it, and the SPA fallback refuses a path that starts with it, so a request
# for a route that does not exist answers 404 rather than 200 HTML.
API_PREFIX = "/api"

# How far one ``gh issue list`` reads, per state: an open backlog is short, a
# closed history longer, so the ``all`` read goes further. ``accounting._gh_issues``
# builds its ``--limit`` from these, and ``solitaire/tracker.py`` reads the same
# two to tell whether a kept all-states read is complete (fewer rows than the
# limit means every issue is in it).
ISSUE_LIMIT_OPEN = 100
ISSUE_LIMIT_ALL = 300

# The verbs that write an issue on the tracker. A kept read of the active Space's
# issues (the Studio ledger's entry, which ``/issue-report`` serves) is dropped
# when the bridge runs one, so the count the pane refetches after a close or an
# edit has moved.
TRACKER_WRITE_VERBS = ("NewItem", "EditItem", "CloseItem", "Route")

# The ledger's disk key for the active Space when ``activeSpace`` names none.
ACTIVE_LEDGER_KEY = "active-space"

# The Docs tab's routes and the two roots they read (D-S12). The roots
# are the contract's (consts.json ``docs``) because the web's link resolver
# applies the same rule; the routes are this half's, mounted under API_PREFIX.
DOCS_ROUTE = "/docs"
DOCS_ASSET_ROUTE = f"{DOCS_ROUTE}/asset"
DOCS_README = docs_readme()
DOCS_ROOT = docs_root()


# A shipped Space whose slug changed, old -> new (consts.json spaces.renamed;
# the Azure demo was ``test``), so a machine whose hub.json or
# config.local.json still names the old slug keeps its Space. MUST mirror
# Resolve-P20RenamedSlug and Rename-P20LegacyHubSpaces in
# Scripts/Resolve-HubConfig.ps1 -- Tests/fixtures/space-renamed/table.json pins
# the two together.
RENAMED_SPACES = renamed_spaces()


def renamed_slug(slug: str, slugs) -> str:
    """The slug to read ``slug`` as, given the Spaces that exist.

    An old slug means its new Space while nothing is declared under the old one
    and something is under the new one; every other slug is itself.
    """
    known = set(slugs)
    new = RENAMED_SPACES.get(slug)
    if new and slug not in known and new in known:
        return new
    return slug


def rename_legacy_hub_spaces(hub_spaces: list, shipped_slugs) -> list:
    """The hub's entries, each nameless one under an old slug moved to the new one.

    Such an entry is a patch on the renamed shipped Space -- what
    ``Config -Set spaces.test.org=...`` wrote -- so it is read under the new
    slug, judged against the SHIPPED slugs, keeping its promptsFolder so the
    cards stay where they are. One that carries a ``name`` declares a Space of
    its own and keeps its slug (Tests/fixtures/hub's ``test``).
    """
    shipped = list(shipped_slugs)
    for entry in hub_spaces:
        if "name" not in entry:
            entry["slug"] = renamed_slug(entry.get("slug", ""), shipped)
    return hub_spaces


def _deep_merge(base: dict, patch: dict) -> dict:
    """Recursively merge ``patch`` into ``base`` and return ``base``.

    Nested dicts merge key-by-key, so a per-machine patch that sets one key
    inside a map keeps the default's sibling keys instead of clobbering the
    whole map. Scalars and lists replace wholesale. MUST mirror Merge-SpacePatch
    in utilities.psm1 -- the config-merge suite asserts the two agree.
    """
    for key, val in patch.items():
        existing = base.get(key)
        if isinstance(val, dict) and isinstance(existing, dict):
            base[key] = _deep_merge(dict(existing), val)
        else:
            base[key] = val
    return base


# Feature flags have a scope, and the default scope is the ENGINEER. The owner's rule:
# "nothing other than the ADO flow -- the core experience -- is
# org-dependent." So every flag belongs to the person and lives in the
# top-level ``features`` block, holding steady across ``activeOrg`` (switching
# from an active Space to an archived one must not make Growth appear and
# disappear), EXCEPT the flags that are part of the ADO core itself and
# describe one org's board or store. Those are read from ``spaces[].features``;
# an org cannot set anything else. WHICH flags those are is the contract's
# (consts.json ``features.spaceScoped``), read here and by the CLI's
# ``SpaceScopedFeatures`` alike, so the second org-scoped flag cannot be added
# to one half and not the other.
SPACE_FEATURES = space_scoped_features()


def ado_enabled(space_status: str | None, flag: bool | None, tracker_kind: str | None) -> bool:
    """Is Azure DevOps part of what this machine SHOWS?

    ``docs/modules/ado.md``, and the mirror of the CLI's
    ``Scripts/Test-AdoEnabled.ps1``: ``features.ado`` when someone has set it,
    else whether the ACTIVE org's status is ``active`` AND its tracker -- what
    ``tracker()`` names from the address -- is ``ado``. It follows the org you
    are in, so the machine ``Start`` leaves (in Demo, ``local``) is off, a
    person in their client's org sees what they always saw, and a connected
    GitHub Space, active with a GitHub tracker, is off: its own row says it is
    connected. One shared table, ``Tests/fixtures/ado-enabled/table.json``,
    holds the two halves together.

    It decides what is shown. It gates no route: an ADO route on an org with no
    ADO already answers with its tier sentence, and that is unchanged.
    """
    if flag is not None:
        return bool(flag)
    return space_status == "active" and tracker_kind == "ado"


def tracker(org_url: str | None) -> str:
    """WHICH tracker answers for a board -- derived from its address.

    D-G2, the mirror of the CLI's
    ``Scripts/Resolve-Tracker.ps1``: a board carries one address
    (``spaces[].org``) and the address decides. Blank is ``none`` (a local
    board); a ``github.com`` host is ``github``; every other address is
    ``ado``, which is exactly what every address meant before this rule
    existed (GitHub Enterprise is the spec's open item). WHETHER the tracker
    is contacted stays ``ado_enabled``'s and the tier's business; this only
    names which one would answer. One shared table,
    ``Tests/fixtures/tracker/table.json``, holds the two halves together.
    """
    url = (org_url or "").strip().lower()
    if not url:
        return "none"
    authority = url.split("://", 1)[-1].split("/", 1)[0]
    authority = authority.split("@")[-1].split(":")[0]
    if authority in ("github.com", "www.github.com"):
        return "github"
    return "ado"


# How do you want to work in this Space? -- the answers a Space may STORE;
# ``team`` is derived from an Azure DevOps address and never stored.
HOW_I_WORK_STORED = ("alone", "agents")
# The one module the answer gates: Team Agile, on only where the answer is agents.
HOW_I_WORK_GATED_FEATURE = "solitaireAgile"


def how_i_work(org_url: str | None, stored: Any = None) -> dict:
    """How do you want to work in this Space? -- the answer, and whether it is asked.

    docs/CONFIGURATION.md, "`spaces[].howIWork`", and the mirror of the
    CLI's ``Scripts/Resolve-HowIWork.ps1``: the tracker the address names
    decides. Azure DevOps is ``team`` and no tracker is ``alone``, both derived
    and locked; a GitHub Space is asked -- ``spaces[].howIWork`` when it says
    ``alone`` or ``agents`` (``chosen``), else ``alone`` (``default``). A stored
    value on a Space whose tracker decides is ignored. One shared table,
    ``Tests/fixtures/how-i-work/table.json``, holds the two halves together.
    """
    kind = tracker(org_url)
    if kind == "ado":
        return {"answer": "team", "source": "derived", "tracker": kind, "locked": True}
    if kind != "github":
        return {"answer": "alone", "source": "derived", "tracker": kind, "locked": True}
    said = stored.strip().lower() if isinstance(stored, str) else ""
    if said in HOW_I_WORK_STORED:
        return {"answer": said, "source": "chosen", "tracker": kind, "locked": False}
    return {"answer": "alone", "source": "default", "tracker": kind, "locked": False}


def apply_how_i_work(features: dict, answer: str) -> dict:
    """The resolved features map with the Space's answer applied, in place.

    Team Agile's switch is the person's; the module is on only where the switch
    is on AND the answer is ``agents``. An absent flag stays absent. The mirror
    of ``Invoke-P20HowIWorkGate``; the shared table's ``gate`` rows hold both.
    """
    if features.get(HOW_I_WORK_GATED_FEATURE) and answer != "agents":
        features[HOW_I_WORK_GATED_FEATURE] = False
    return features


def tracker_owner(org_url: str | None) -> str:
    """The address's FIRST PATH SEGMENT: the GitHub owner, the ADO org name.

    The thing a probe asks after and a report prints. Case preserved -- it is
    a display name as much as an API argument. ``""`` when the address has no
    path (blank, or the legacy ``*.visualstudio.com`` shape whose org lives in
    the host). The CLI's copy is ``Get-P20TrackerOwner`` in
    ``Scripts/Resolve-Tracker.ps1``, held by the same shared table.
    """
    url = (org_url or "").strip()
    if not url:
        return ""
    rest = url.split("://", 1)[-1]
    parts = rest.split("/")
    return parts[1] if len(parts) >= 2 else ""


def tracker_repos(org_url: str | None, projects: list[dict] | None) -> list[str]:
    """Every repository a GitHub READ may span -- ``owner/name`` each.

    The mirror of the CLI's ``Get-P20TrackerRepos``: a repo-grained address
    names one; otherwise every ``projects[]`` entry with a ``repo``. A read
    may fan out where a write must name exactly one -- listing issues across
    the board's repos is the WIQL org-wide shape, and wrong-repo ambiguity
    cannot corrupt a read.
    """
    owner = tracker_owner(org_url)
    if not owner:
        return []
    rest = (org_url or "").strip().split("://", 1)[-1].split("/")
    if len(rest) >= 3 and rest[2]:
        return [f"{owner}/{rest[2]}"]
    return [f"{owner}/{p['repo']}" for p in (projects or []) if p.get("repo")]


# The five lanes' display names -- ORG-scoped, like sprintAwareness, because which
# words fit is a fact about the org: a client's ADO board wants "Code Review", the
# sample hub's Demo wants "Waiting". The CONTRACT's words (consts.json `status`)
# are what is stored, compared and served as `status`; these only change what the
# board and the list print. Served keyed by the contract word, so the web never
# has to know the config's camelCase keys (docs/hub/cards.md).
LANE_KEYS = {
    "backlog": "Backlog",
    "active": "Active",
    "inProgress": "In Progress",
    "codeReview": "Code Review",
    "done": "Done",
}


def offered_spaces(spaces: list[dict], active_slug: str, dismissed: bool) -> list[dict]:
    """The orgs a person is OFFERED to pick from -- not the orgs that exist.

    An org marked ``example: true`` is left out when ``isDemoDismissed`` is true,
    unless it is the active Space: never hide where you are. Nothing is removed
    from config. Scripts/Select-OfferedSpaces.ps1 is the CLI's copy, and
    Tests/fixtures/offered-orgs/table.json holds the two to one table.
    """
    return [o for o in spaces if not (dismissed and o.get("example") is True and o.get("slug") != active_slug)]


def card_types(cfg: dict | None = None) -> tuple[list[str], list[str]]:
    """(type names, file prefixes) from ``workItemTypes`` -- CardType, in config's
    order. Read per request when ``cfg`` is not given, like every other config
    read here, so a type a team adds needs no restart."""
    types = (load_config() if cfg is None else cfg).get("workItemTypes", {}) or {}
    names = [n for n in types if not n.startswith("_")]
    return names, [str((types[n] or {}).get("filePrefix") or "") for n in names]


def lane_names(org: dict | None) -> dict[str, str]:
    """``{contract word: display name}`` for one org -- the contract's own words
    where the org says nothing, its ``laneNames`` where it does."""
    names = {word: word for word in LANE_KEYS.values()}
    raw = (org or {}).get("laneNames")
    if isinstance(raw, dict):
        for key, word in LANE_KEYS.items():
            value = raw.get(key)
            if isinstance(value, str) and value.strip():
                names[word] = value.strip()
    return names


def effective_features(top_level: dict | None, org_features: dict | None) -> dict:
    """The merged features map /env serves: org-scoped keys (SPACE_FEATURES) from
    the active Space, every other key from the top-level block only. A Space key that
    holds a number (trainingHoursPerQuarter) is a value, not a flag: it stays on the
    Space and is not folded into this boolean map -- see ``space_training_hours``."""
    merged = {k: bool(v) for k, v in (top_level or {}).items() if k not in SPACE_FEATURES}
    for k in SPACE_FEATURES:
        v = (org_features or {}).get(k)
        if isinstance(v, bool):
            merged[k] = v
    return merged


def _warn(detail: str) -> None:
    log_writer.write_log("WARN", "agent/config", detail)


def _resolve_root(raw: str) -> Path:
    """Turn a configured ``promptsRoot`` string into a path, the one way.

    Relative values resolve against the repository root so a committed config
    stays portable. Shared by ``hub_root`` and by the manifest read inside
    ``load_config``, which must look in exactly the same place.
    """
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path


def _sanitise_hub_space(org: dict, label: str) -> dict | None:
    """One entry from ``hub.json``'s ``orgs``, or None if it cannot be used.

    Two fields are load-bearing and an entry without them is skipped rather
    than half-applied: ``slug`` (what the merge and ``SwitchSpace`` key on) and
    ``promptsFolder`` (where its cards live). Feature flags are filtered to the
    org-scoped set -- a hub org may set ``sprintAwareness`` exactly as a shipped
    org may, and an engineer flag there is somebody's flag in the wrong file.
    """
    slug = org.get("slug")
    slug = slug.strip() if isinstance(slug, str) else ""
    if not slug:
        _warn(f"{label}: a Space with no 'slug' was skipped -- a hub Space needs 'slug' and 'promptsFolder'.")
        return None
    folder = org.get("promptsFolder")
    folder = folder.strip() if isinstance(folder, str) else ""
    if not folder:
        _warn(
            f"{label}: org '{slug}' has no 'promptsFolder' and was skipped -- "
            "a hub org needs 'slug' and 'promptsFolder'."
        )
        return None
    org["slug"] = slug
    org["promptsFolder"] = folder

    feats = org.get("features")
    if feats is None:
        return org
    if not isinstance(feats, dict):
        _warn(f"{label}: org '{slug}' has a 'features' that is not an object -- ignored.")
        org.pop("features", None)
        return org
    kept = {}
    for key, val in feats.items():
        if key in SPACE_FEATURES:
            kept[key] = val
        else:
            _warn(
                f"{label}: org '{slug}' sets features.{key}, which is the engineer's flag and not the "
                f"org's -- ignored. It belongs in config.local.json's top-level 'features'."
            )
    if kept:
        org["features"] = kept
    else:
        org.pop("features", None)
    return org


def read_hub_manifest(root: Path | None) -> dict:
    """Read ``<root>/hub.json``. Never raises; a bad file is a warning.

    Returns ``{"manifest": bool, "path": str, "spaces": [...], "folders": {...},
    "storeSync": str}`` where ``orgs`` holds only usable entries, ``folders``
    holds only declared overrides -- the defaults are applied by ``hub_folders``
    -- and ``storeSync`` is "" unless the hub declared a usable one. MUST mirror
    ``Read-P20HubManifest`` in utilities.psm1; Tests/fixtures/hub-parity pins
    the two together.
    """
    result: dict = {"manifest": False, "path": "", "spaces": [], "folders": {}, "storeSync": ""}
    if root is None:
        return result
    path = root / HUB_MANIFEST_NAME
    result["path"] = str(path)
    if not path.is_file():
        return result

    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:  # unreadable or malformed JSON is a readable warning, never a crash
        _warn(f"{path}: not valid JSON ({exc}) -- the hub declared nothing. Fix the file or delete it.")
        return result
    if not isinstance(data, dict):
        _warn(f"{path}: expected a JSON object at the top level -- the hub declared nothing.")
        return result

    result["manifest"] = True
    label = str(path)
    data = space_keys(data)

    for key in data:
        if key.startswith("_") or key in HUB_MANIFEST_KEYS:
            continue
        _warn(
            f"{label}: '{key}' is a machine setting, not a hub declaration -- ignored. "
            f"hub.json carries 'spaces' and 'folders'; everything else stays in config.local.json."
        )

    raw_orgs = data.get("spaces", [])
    if raw_orgs and not isinstance(raw_orgs, list):
        _warn(f"{label}: 'spaces' must be an array of Space entries, the shape config.default.json uses -- ignored.")
        raw_orgs = []
    for entry in raw_orgs or []:
        if not isinstance(entry, dict):
            _warn(f"{label}: an entry in 'orgs' is not an object -- skipped.")
            continue
        org = _sanitise_hub_space(dict(entry), label)
        if org is not None:
            result["spaces"].append(org)

    raw_folders = data.get("folders", {})
    if raw_folders and not isinstance(raw_folders, dict):
        _warn(f"{label}: 'folders' must be an object of name -> folder -- ignored.")
        raw_folders = {}
    for key, val in (raw_folders or {}).items():
        if key not in DEFAULT_HUB_FOLDERS:
            known = ", ".join(sorted(DEFAULT_HUB_FOLDERS))
            _warn(f"{label}: 'folders.{key}' is not a hub-root folder this tool reads -- ignored. Known: {known}.")
            continue
        if not isinstance(val, str) or not val.strip():
            _warn(f"{label}: 'folders.{key}' must be a folder name -- ignored, keeping '{DEFAULT_HUB_FOLDERS[key]}'.")
            continue
        result["folders"][key] = val.strip()

    if "storeSync" in data:
        raw_sync = data.get("storeSync")
        value = raw_sync.strip() if isinstance(raw_sync, str) else ""
        if value in STORE_SYNC_VALUES:
            result["storeSync"] = value
        else:
            known = " or ".join(f"'{v}'" for v in STORE_SYNC_VALUES)
            _warn(f"{label}: 'storeSync' must be {known} -- ignored, keeping the configured value.")

    return result


# -- Two per-PROCESS stand-ins for config.local.json ----------------------
# ``PROMPTS_ROOT`` has always been an environment override for WHERE the hub is.
# These two are its siblings for the other two things a smoke run needs to set --
# which Space is active and which flags are on -- so ``Web -Dev -Fixture`` can
# start an agent against Tests/fixtures/hub without rewriting the machine's own
# config.local.json (and without a forgotten restore leaving the real hub
# unplugged). Their NAMES are the contract's (consts.json ``env.activeSpace``,
# ``env.features``); MUST mirror Get-P20ActiveSpaceOverride /
# Get-P20FeaturesOverride in Scripts/Resolve-HubConfig.ps1.
#
# Each REPLACES the one key it names in config.local.json and nothing else: the
# rest of that file (a Space patch, the port, the prefix) still applies.


def active_space_override() -> str:
    """The Space slug the environment names, or ``""`` when it names none."""
    return os.environ.get(env_active_space(), "").strip()


def features_override() -> dict | None:
    """The features block the environment supplies, or ``None`` when the files decide.

    A JSON object -- ``{"growth": true}``; ``{}`` means "no flag set", which is
    config.local.json with no ``features`` block. Anything else is a warning and
    is ignored, so a typo falls back to the files rather than switching every
    module off in silence.
    """
    raw = os.environ.get(env_features(), "").strip()
    if not raw:
        return None
    try:
        value = json.loads(raw)
    except ValueError:
        value = None
    if not isinstance(value, dict):
        _warn(f"{env_features()} is not a JSON object -- ignored, config.local.json's features stand.")
        return None
    return value


def read_config_file(path: Path) -> tuple[dict, str]:
    """Read one config file as ``(data, problem)``. Never raises.

    A missing file is ``({}, "")`` -- the ordinary case. An unreadable file,
    malformed JSON or a top level that is not an object is ``({}, <sentence>)``
    and the sentence is also logged, so the caller falls back to the layers
    below and ``/env`` can say why. Same posture as ``read_hub_manifest``.
    """
    if not path.exists():
        return {}, ""
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        problem = f"{path.name} is not valid JSON ({exc}) -- ignored, the defaults stand. Fix the file or delete it."
        _warn(f"{path}: {problem}")
        return {}, problem
    if not isinstance(data, dict):
        problem = f"{path.name} must hold a JSON object at the top level -- ignored, the defaults stand."
        _warn(f"{path}: {problem}")
        return {}, problem
    return data, ""


def load_config() -> dict:
    """Resolve the effective config: defaults, then per-machine overrides.

    An unreadable or malformed config file never raises: it is skipped, and the
    sentence lands in ``configProblems`` for ``/env`` to report.
    """
    defaults, default_problem = read_config_file(DEFAULT_CONFIG_PATH)
    defaults = space_keys(defaults)
    local, local_problem = read_config_file(LOCAL_CONFIG_PATH)
    local = space_keys(local)
    config_problems = [p for p in (default_problem, local_problem) if p]
    # The environment's stand-ins, applied to the local layer so every reader
    # below (and every route that reads load_config) sees one answer.
    slug_override = active_space_override()
    if slug_override:
        local["activeSpace"] = slug_override
    flags_override = features_override()
    if flags_override is not None:
        local["features"] = flags_override

    # Resolve active org from orgs array. Apply per-machine overrides first:
    # config.local.json may carry sparse per-org patches keyed by slug
    # (e.g. {"spaces": {"team": {"status": "local"}}}).
    _VALID_STATUSES = {"active", "local", "archive"}

    spaces = [dict(o) for o in defaults.get("spaces", [])]

    # The hub declares its own orgs, and they land BETWEEN the two config files.
    # config.default.json is the team's shipped list, hub.json is the engineer's
    # (a private org must never reach the committed file), config.local.json is
    # this machine's last word on either. Merging by slug means a hub entry
    # either deep-merges over a shipped org or is appended as a new one.
    raw_root = (
        os.environ.get("PROMPTS_ROOT", "").strip()
        or (local.get("promptsRoot") or defaults.get("promptsRoot") or "").strip()
    )
    hub = read_hub_manifest(_resolve_root(raw_root) if raw_root else None)
    by_slug = {o.get("slug"): o for o in spaces}
    rename_legacy_hub_spaces(hub["spaces"], by_slug)
    for hub_space in hub["spaces"]:
        existing = by_slug.get(hub_space["slug"])
        if existing is None:
            spaces.append(hub_space)
            by_slug[hub_space["slug"]] = hub_space
        else:
            _deep_merge(existing, hub_space)

    local_patches = local.get("spaces", {})
    if isinstance(local_patches, list):
        # The two files hold ``orgs`` in two different shapes on purpose: the
        # shipped file's is an ARRAY (the list of orgs, each carrying its own
        # slug), the local file's is an OBJECT keyed by slug (a sparse patch).
        # A reader who mirrors the shipped file writes the array form, which
        # matches nothing -- and used to do so in silence, on the one key that
        # decides which org everything scopes to. Mirrors the same warning in
        # utilities.psm1.
        log_writer.write_log(
            "WARN",
            "agent/config",
            "config.local.json: 'spaces' is an array, so nothing in it was applied. "
            "Patch spaces as an object keyed by slug -- "
            '{"spaces": {"<slug>": {"status": "local"}}} -- not as a list of '
            "entries carrying 'slug'. See docs/CONFIGURATION.md.",
        )
    elif isinstance(local_patches, dict):
        slugs = [o.get("slug") for o in spaces]
        for o in spaces:
            # A patch under a renamed Space's old slug lands first, then one
            # under its new slug, which has the last word.
            for key, patch in local_patches.items():
                if key != o.get("slug") and renamed_slug(key, slugs) == o.get("slug") and isinstance(patch, dict):
                    _deep_merge(o, patch)
            patch = local_patches.get(o.get("slug"))
            if isinstance(patch, dict):
                _deep_merge(o, patch)

    # Validate status values -- an unknown status must never reach Tier 1.
    for o in spaces:
        raw = o.get("status", "")
        if raw and raw not in _VALID_STATUSES:
            log_writer.write_log(
                "WARN",
                "agent/config",
                f"org '{o.get('slug', '?')}': unknown status '{raw}' -- treating as 'local' (fail-closed)",
            )
            o["status"] = "local"

    active_slug = renamed_slug(
        local.get("activeSpace") or defaults.get("activeSpace", ""), [o.get("slug") for o in spaces]
    )
    active_space = next((o for o in spaces if o["slug"] == active_slug), None)
    if not active_space and spaces:
        # Archive orgs are selectable -- include them in the fallback.
        active_space = next((o for o in spaces if o.get("status") in ("active", "local", "archive")), spaces[0])

    # The person's switches, then the active Space's answer applied to the one
    # module it gates. ``howIWork`` carries the answer for /env, with the
    # switch as set -- the Settings control says when the switch is what is off.
    features = effective_features(
        _deep_merge(dict(defaults.get("features", {}) or {}), local.get("features", {}) or {}),
        (active_space or {}).get("features", {}),
    )
    how = how_i_work((active_space or {}).get("org", ""), (active_space or {}).get("howIWork"))
    how["switch"] = features.get(HOW_I_WORK_GATED_FEATURE)
    apply_how_i_work(features, how["answer"])

    cfg = {
        "spaces": spaces,
        "activeSpace": active_space["slug"] if active_space else "",
        "org": (active_space or {}).get("org", ""),
        "status": (active_space or {}).get("status", ""),
        "promptsFolder": (active_space or {}).get("promptsFolder", ""),
        "projects": (active_space or {}).get("projects", []),
        "laneNames": lane_names(active_space),
        "features": features,
        "howIWork": how,
        "email": local.get("email") or defaults.get("email", ""),
        "branchUser": local.get("branchUser") or defaults.get("branchUser", ""),
        "wsRoot": local.get("wsRoot") or defaults.get("wsRoot", ""),
        # What every verb is typed with on this machine. The web UI names real
        # commands ("run tkAgent"), and a prefix is config, never a literal.
        "commandPrefix": local.get("commandPrefix") or defaults.get("commandPrefix", ""),
        "promptsRoot": local.get("promptsRoot") or defaults.get("promptsRoot", ""),
        # This machine's own folder of agentic prompts: the Studio's Prompts
        # card lists what it holds as yours (agentic_extension_path). Local, then
        # the shipped default, as utilities.psm1 merges it.
        "agenticExtensionPath": local.get("agenticExtensionPath") or defaults.get("agenticExtensionPath", ""),
        # config.default.json, then the hub, then this machine. Whether the
        # store is a git repo is a fact about the hub, so the hub can settle it
        # for every machine that reads it; config.local.json still has the last
        # word, which is how one machine says "never push from here".
        "storeSync": (local.get("storeSync") or hub["storeSync"] or defaults.get("storeSync", "")),
        "web": _deep_merge(dict(defaults.get("web", {})), local.get("web", {}) or {}),
        # What the first run shows: firstRun.welcome is the Home banner tkStart
        # turns on and its Dismiss turns off, through Config.
        # Hide the shipped Example org from what is offered (offered_spaces).
        "isDemoDismissed": bool(local.get("isDemoDismissed", defaults.get("isDemoDismissed", False))),
        # The WIP limit (limits.inPlay): a line Status and the board say, never a gate.
        "limits": _deep_merge(dict(defaults.get("limits", {}) or {}), local.get("limits", {}) or {}),
        # Where each Space's repository is cloned on THIS machine
        # (spaceCheckouts.<slug>.path; agent/core/checkout.py). This machine's
        # file only -- never the shipped one, never hub.json -- as utilities.psm1
        # reads it.
        "spaceCheckouts": local.get("spaceCheckouts") if isinstance(local.get("spaceCheckouts"), dict) else {},
        "firstRun": _deep_merge(dict(defaults.get("firstRun", {}) or {}), local.get("firstRun", {}) or {}),
        # The verb table's own metadata. The bridge reads one key off it --
        # bridgeTimeoutSeconds -- and a per-machine config may patch an entry,
        # so it merges rather than being taken from the defaults alone.
        # CardType (docs/hub/cards.md, "The filename"): name -> filePrefix, template,
        # branchSeparator. Configuration, so a team may add a type -- and the agent
        # reads it the way the CLI does (defaults, then this machine's patch), or
        # it could not tell a team's "Chore-12-..." from a file that is not a card.
        "workItemTypes": {
            k: v
            for k, v in _deep_merge(
                dict(defaults.get("workItemTypes", {}) or {}), local.get("workItemTypes", {}) or {}
            ).items()
            if isinstance(v, dict)
        },
        "commands": _deep_merge(
            {k: dict(v) for k, v in (defaults.get("commands", {}) or {}).items() if isinstance(v, dict)},
            local.get("commands", {}) or {},
        ),
        # The hub-root sibling names every module reads, defaults where the hub
        # said nothing, and a plain report of whether a manifest was found.
        "hubFolders": {**DEFAULT_HUB_FOLDERS, **hub["folders"]},
        "hub": {
            "manifest": hub["manifest"],
            "path": hub["path"],
            "spaces": len(hub["spaces"]),
        },
        # One sentence per config file that could not be read (read_config_file).
        "configProblems": config_problems,
    }
    return cfg


# Config is re-read on every request that touches it. The JSON files are tiny
# and on local disk, so the I/O is negligible -- and it matches how the CLI
# reads config on each shell invocation. External edits (a switch-org from
# another shell, a hand-edited config.local.json) take effect on the next
# request instead of waiting for a restart.


def hub_configured() -> bool:
    """Whether a hub root has been named at all (env override or config)."""
    return bool(os.environ.get("PROMPTS_ROOT", "").strip() or (load_config().get("promptsRoot") or "").strip())


def hub_root() -> Path:
    """The prompt store's root.

    ``PROMPTS_ROOT`` in the environment is an explicit override and wins;
    otherwise the value is ``promptsRoot`` from config. A relative value is
    read against the repository root so a committed config stays portable.
    Unconfigured returns a path that does not exist, never ``None``.
    """
    raw = os.environ.get("PROMPTS_ROOT", "").strip()
    if not raw:
        raw = (load_config().get("promptsRoot") or "").strip()
    if not raw:
        return UNCONFIGURED_HUB
    return _resolve_root(raw)


def hub_detail() -> str:
    """One plain sentence about the hub, for ``/env``'s promptsVolume row."""
    if not hub_configured():
        return "promptsRoot is not set in config.default.json or config.local.json"
    root = hub_root()
    return f"{root} -- readable" if root.exists() else f"{root} -- not found"


def resolve_dirs() -> tuple[Path, Path]:
    """Return (current_dir, archive_dir) for the active Space's promptsFolder.

    The two folder names come from ``consts.json`` -- the CLI's
    ``Get-PromptFolders`` and the web's session filter spell them too.
    """
    root = hub_root()
    folder = load_config().get("promptsFolder", "")
    current, archive = folder_current(), folder_archive()
    if folder:
        return (root / folder / current, root / folder / archive)
    return (root / current, root / archive)


def backlog_dir(current_dir: Path) -> Path:
    """The Space's ``backlog/`` -- cards planned, not yet in play -- beside its
    ``current/``. A sibling, as ``archive/`` is; kept out of ``resolve_dirs``'s
    pair so every reader that means "the cards in play" (health, the standup,
    Daily's counts) keeps meaning exactly that. The CLI's Get-PromptFolders
    carries the same third path as ``Backlog``."""
    return current_dir.parent / folder_backlog()


def org_folder(org_config: dict) -> Path:
    """The hub folder for one org entry from ``spaces[]``."""
    folder = (org_config or {}).get("promptsFolder", "")
    return hub_root() / folder if folder else hub_root()


def hub_folders() -> dict:
    """The hub-root sibling names in force: the declared ones over the defaults."""
    declared = load_config().get("hubFolders") or {}
    return {**DEFAULT_HUB_FOLDERS, **declared}


def hub_folder(name: str) -> Path:
    """The path of one hub-root sibling -- ``hub_folder("growth")``.

    The single accessor the growth, communication and reporting modules read,
    so the name of a hub folder is a declaration in one file rather than a
    string literal at every use.
    """
    return hub_root() / hub_folders().get(name, DEFAULT_HUB_FOLDERS.get(name, name))


def agentic_extension_path() -> Path | None:
    """The machine's own folder of agentic prompts (``agenticExtensionPath``),
    resolved, or None when none is set or it does not exist.

    Absolute, ``~``-relative, or relative to the hub -- the rule
    Get-P20AgenticExtensionPath in Scripts/Resolve-AgenticPrompt.ps1 applies,
    where a tuned copy of a shipped prompt wins on this machine.
    """
    raw = str(load_config().get("agenticExtensionPath") or "").strip()
    if not raw:
        return None
    if raw.startswith("~"):
        rest = raw[1:].lstrip("/\\")
        path = Path.home() / rest if rest else Path.home()
    else:
        path = Path(raw)
        if not path.is_absolute():
            if not hub_configured():
                return None
            path = hub_root() / path
    return path.resolve() if path.is_dir() else None


def hub_manifest_detail() -> str:
    """One plain sentence about ``hub.json``, for ``/env``'s hubManifest row."""
    hub = load_config().get("hub") or {}
    if not hub.get("manifest"):
        return "no hub.json -- Spaces come from config alone"
    count = hub.get("spaces", 0)
    return f"hub.json read -- {count} Space{'s' if count != 1 else ''} declared"


def cors_origins() -> list[str]:
    """Dev-server origins allowed to call the API. Config-driven, same
    defaults as before (5173 / 5174) so nothing changes if config is silent."""
    web = load_config().get("web", {}) or {}
    origins = web.get("corsOrigins")
    if isinstance(origins, list) and origins:
        return [str(o) for o in origins]
    return list(DEFAULT_CORS_ORIGINS)


def anthropic_api_key() -> str:
    """The model key, from the environment and nowhere else.

    ``ANTHROPIC_API_KEY`` first; ``CLAUDE_API_KEY`` is the fallback name
    ``.env.example`` documents for a machine where something else already
    owns the first, and ``Scripts/Invoke-PRReview.ps1`` reads the pair in the
    same order. A key never comes from a file this tool writes.
    """
    for name in ("ANTHROPIC_API_KEY", "CLAUDE_API_KEY"):
        value = (os.environ.get(name) or "").strip()
        if value:
            return value
    return ""


def anthropic_configured() -> bool:
    """Whether the model-assisted routes have a credential to work with."""
    return bool(anthropic_api_key())


def in_play_limit(cfg: dict | None = None) -> int | None:
    """The WIP limit, ``limits.inPlay``: a whole number of 1 or more, else ``None``.

    Unset, zero, negative, a bool or anything that is not a whole number reads as no
    limit (the opt-in rule), exactly as ``Scripts/Get-InPlayLine.ps1`` reads it. It is
    a line the board and ``Status`` SAY, never a gate: nothing here refuses a card.
    """
    raw = ((cfg if cfg is not None else load_config()).get("limits") or {}).get("inPlay")
    if isinstance(raw, bool):
        return None
    try:
        n = int(str(raw).strip())
    except (TypeError, ValueError):
        return None
    return n if n >= 1 else None


def start_work_launch() -> bool:
    """Whether ``StartWork <id> -Launch`` has a session to start: ``claude`` on the
    PATH (D-AR13). The launch row in ``Scripts/Get-OptionalSurfaces.ps1`` (keyed by
    consts.json ``startWork.launchEnvFlag``) is the same rule -- on where the tool is
    found, not configured otherwise. Asked of THIS process's PATH on purpose: the
    page's button runs the verb through the bridge, whose child pwsh inherits it.
    """
    return shutil.which("claude") is not None
