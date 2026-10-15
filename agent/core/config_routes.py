"""Reading and writing configuration over HTTP -- and every write goes through the CLI.

Three routes, and the shape of them is the whole point:

    GET  /api/config/schema   what may be set: key, scope, type, allowed values,
                              help. The web card's tooltips come from here.
    GET  /api/config          every resolved setting with the file it came from.
    PUT  /api/config          {"set": {...}, "unset": [...]} -- applied by
                              running the CLI's ``Config`` verb through the
                              bridge, exactly as the Archive button runs
                              ``Archive``.

**Nothing here writes a config file.** ``agent/core/env.py``'s ``/switch-mode``
still writes ``activeSpace`` itself, which predates the verb and is left alone
because the CLI has always had ``SwitchSpace`` beside it; everything this module
does goes out through ``POST /cmd`` machinery so there is one implementation of
"what may be set, where it lands, and what a legal value is" -- the schema in
``Scripts/Get-ConfigSchema.ps1`` -- rather than a second one in Python that
would agree with it only until someone edited one of them.

THE ARGV. The bridge splats a flat argv list into the PowerShell function, so a
repeated ``-Set`` is "Set is specified more than once" and a bare extra token
has nowhere positional to land. The verb therefore also reads ONE JSON object of
key -> value, and that is what ``_build_params`` sends: two argv tokens for any
number of pairs, with each value keeping its own JSON type.

THE CACHES. ``load_config()`` is re-read per request, so an org, a path or a
feature flag is live on the next call with no restart. Two answers are not:
the ADO reachability probe and the resolved identity, both behind a 45-second
TTL. A successful write clears them, which is what makes "set ``email`` from the
card, see ``/env.identity`` change" true within a second rather than within a
minute.

The schema is cached for the life of the process instead: it is derived from
files that only change with a commit, and reading it costs a PowerShell start.
"""

import asyncio
import json
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..ado.bridge import CommandRequest, CommandResponse, command_map, run_command
from .identity import identity_cache_clear
from .tier import probe_cache_clear

api = APIRouter()

# The CLI verb this module drives. A name, in one place, because it is also the
# allowlist key the bridge checks it against.
CONFIG_COMMAND = "Config"

# Cached for the life of the process -- see the module docstring.
_schema_cache: list[dict] | None = None


def schema_cache_clear() -> None:
    """Forget the cached schema. For the tests, and for a reload if one ever
    needs it: a schema changes with a commit, not with a setting."""
    global _schema_cache
    _schema_cache = None


def _to_set_value(value: Any) -> Any:
    """One value as the verb's JSON object carries it.

    Passed straight through: the verb turns each one back into the same string
    the ``key=value`` form would have produced and runs the one validator. A
    number is sent as a number and a list as a list, so `web.agentPort` and
    `web.corsOrigins` need no special case on either side.
    """
    return value


def build_params(set_map: dict[str, Any] | None, unset: list[str] | None) -> list[str]:
    """The argv for ``Config``, per the bridge's contract.

    Pure, and the mirror of ``web/src/modules/ado/cliBridge.ts``'s
    ``buildConfigEdit``: the browser builds the same two structures and this
    turns them into the two argv tokens the verb reads.
    """
    params: list[str] = []
    if set_map:
        params += ["-Set", json.dumps({k: _to_set_value(v) for k, v in set_map.items()})]
    if unset:
        params += ["-Unset", json.dumps(list(unset))]
    return params


async def _run_config(params: list[str]) -> CommandResponse:
    """One ``Config`` call through the bridge, with everything the bridge gives:
    the allowlist, the parameter limits, the per-command timeout and the four
    statuses."""
    return await run_command(CONFIG_COMMAND, CommandRequest(params=params))


def _parse_json_output(result: CommandResponse) -> Any | None:
    """The verb's ``-AsJson`` output, or None.

    The last line that opens an object or an array, for the same reason the
    command-map read takes the last one: under ``-File`` PowerShell folds the
    warning stream into stdout, so a config warning on the way up would
    otherwise sit in front of the JSON.
    """
    if result.status != "success" or not result.output:
        return None
    text = result.output
    start = min(
        (i for i in (text.find("{"), text.find("[")) if i != -1),
        default=-1,
    )
    if start == -1:
        return None
    try:
        return json.loads(text[start:])
    except json.JSONDecodeError:
        return None


# ---------------------------------------------------------------------------
# GET /api/config/schema
# ---------------------------------------------------------------------------
@api.get("/config/schema")
async def get_config_schema(refresh: int = 0):
    """What may be set. Cached per process; ``?refresh=1`` re-reads it."""
    global _schema_cache
    if _schema_cache is not None and not refresh:
        return {"schema": _schema_cache, "error": None}

    result = await _run_config(["-Schema", "-AsJson"])
    rows = _parse_json_output(result)
    if rows is None:
        # A schema the agent could not read is reported, not guessed at: the
        # card renders read-only rather than offering fields it cannot validate.
        return {"schema": [], "error": result.error or "The CLI could not describe the config schema."}
    _schema_cache = list(rows)
    return {"schema": _schema_cache, "error": None}


# ---------------------------------------------------------------------------
# GET /api/config
# ---------------------------------------------------------------------------
@api.get("/config")
async def get_config():
    """Every resolved setting with its source -- ``Config -List -AsJson``."""
    result = await _run_config(["-List", "-AsJson"])
    payload = _parse_json_output(result)
    if payload is None:
        return {
            "activeSpace": "",
            "files": {},
            "settings": [],
            "error": result.error or "The CLI could not read the configuration.",
        }
    payload["error"] = None
    return payload


# ---------------------------------------------------------------------------
# PUT /api/config
# ---------------------------------------------------------------------------
class ConfigWriteRequest(BaseModel):
    set: dict[str, Any] = Field(default_factory=dict)
    unset: list[str] = Field(default_factory=list)
    # The two switches the verb takes. `local` sends a spaces.<slug>.* write to
    # this machine's patch; `hub` writes the hub's own declaration.
    local: bool = False
    hub: bool = False


@api.put("/config")
async def put_config(body: ConfigWriteRequest | None = None):
    """Apply a set of edits by running the CLI, and hand back both halves.

    Always 200 with ``result`` typed as a ``CommandResponse``, refusals
    included -- the same contract ``POST /cmd/{name}`` has, so the browser
    renders rejected, error and timeout as what they are rather than as a
    failed fetch. ``config`` is the re-read list, so a card never has to guess
    what landed.
    """
    body = body or ConfigWriteRequest()
    params = build_params(body.set, body.unset)
    if not params:
        empty = CommandResponse(
            command=CONFIG_COMMAND,
            status="rejected",
            exit_code=-1,
            output=None,
            error="Nothing to change: neither 'set' nor 'unset' was given.",
            duration=0,
        )
        return {"result": empty.model_dump(), "config": await get_config()}

    if body.local:
        params.append("-Local")
    if body.hub:
        params.append("-Hub")

    result = await _run_config(params)

    if result.status == "success":
        # The answers that are NOT re-read per request. Cleared here so a
        # change of `email` or of org shows in /env on the next call instead of
        # after the 45-second TTL -- which is the difference between the card
        # working and the card looking broken.
        await asyncio.to_thread(identity_cache_clear)
        await asyncio.to_thread(probe_cache_clear)
        # And the bridge's allowlist: this very write went through the bridge,
        # which primed its cache with the command table as it stood BEFORE a
        # module flag flipped. Re-read now, so the module's verbs are callable
        # on the next request rather than after a restart.
        #
        await asyncio.to_thread(command_map, True)

    return {"result": result.model_dump(), "config": await get_config()}
