"""GET /api/spaces/candidates -- the repositories the + on the Spaces card offers.

The picker in the New Space dialog lists the signed-in account's GitHub
repositories, each marked when it is already a Space, with the slug and the name
the verb would give it. All of that is the CLI's: this route runs
``NewSpace -Discover -AsJson`` through the bridge (the same in-process call
``config_routes`` makes for ``Config``), so the rule that proposes a slug and the
rule that says "already a Space" exist once, in ``Scripts/New-Space.ps1``.

It is a READ, and it is never refused: with no ``gh``, ``gh`` signed out, or a
bridge that cannot run, it answers ``available: false`` and the sentence saying
why, and the dialog offers a plain ``owner/name`` field instead. Adding the Space
is ``POST /api/cmd/NewSpace`` -- there is no native write here.

``?owner=`` is the verb's ``-Owner``: an organisation's repositories, or
``collaborator`` for the ones shared with you. The answer names the owners the
dialog's selector offers (``owners``) -- the verb's list, so the terminal and the
dialog offer the same things -- and each row says whether you can only read it
(``readOnly``, the verb's rule over gh's permission).

``?repo=owner/name`` is the verb's ``-Discover -Repo``: the one repository a person
typed into the search, read before it is added (the dialog's **Add owner/name**
row), so its visibility is said first. A repository this login cannot see is a
row all the same, its ``visibility`` the contract's unknown and its ``note``
saying so (``not visible to this login: gh answered ...``).

A list is read to a ceiling (``ceiling``, the verb's), not one page: past it the
answer holds the first ``ceiling`` and says ``more``, and the dialog says that a
repository past them is typed as ``owner/name``.

Not tier-gated, on purpose: tier is a fact about the ACTIVE Space's tracker, and
these are the account's repositories, offered precisely when the Space you are in
is a local one (the Demo, on a first run). Whether ``gh`` can answer is the only
gate, and the verb asks it.
"""

from __future__ import annotations

import json

from fastapi import APIRouter
from pydantic import BaseModel

from ..ado.bridge import CommandRequest, CommandResponse, run_command

api = APIRouter()

# The CLI verb this route drives -- also the bridge's allowlist key.
NEW_SPACE_COMMAND = "NewSpace"
DISCOVER_PARAMS = ["-Discover", "-AsJson"]


class SpaceCandidate(BaseModel):
    repo: str = ""  # owner/name
    name: str = ""  # the repository's name
    owner: str = ""
    visibility: str = ""  # PUBLIC | PRIVATE | INTERNAL, as gh says it
    isArchived: bool = False  # GitHub has archived it: read-only there
    viewerPermission: str = ""  # ADMIN | MAINTAIN | WRITE | TRIAGE | READ, "" when gh did not say
    readOnly: bool = False  # you can read it and not write to it -- the verb's rule
    description: str = ""
    proposedSlug: str = ""  # what NewSpace -Repo would name the Space's slug
    proposedName: str = ""  # ...and its display name
    space: str = ""  # the slug of the Space this repository already is, "" when none
    spaceName: str = ""
    command: str = ""  # the exact line that adds it, in this machine's prefix
    note: str = ""  # why gh said nothing of a typed repository, "" when it did


class SpaceOwner(BaseModel):
    value: str = ""  # what -Owner takes
    label: str = ""
    kind: str = ""  # user | organization | collaborator


class SpaceCandidates(BaseModel):
    available: bool = False
    reason: str = ""  # why not, when not -- one sentence
    hint: str = ""
    account: str = ""  # the gh login, when signed in
    owner: str = ""  # whose repositories these are; the account when none was asked
    owners: list[SpaceOwner] = []  # what the dialog's owner selector offers
    ceiling: int = 0  # how many repositories one list is read to; 0 when the verb did not say
    more: bool = False  # the list stopped at the ceiling and there are more
    repos: list[SpaceCandidate] = []


def _verb_json(result: CommandResponse) -> dict | None:
    """The verb's one JSON line: the last line of its output that opens an object
    (the bridge folds anything a startup printed into stdout ahead of it)."""
    if result.status != "success" or not result.output:
        return None
    for line in reversed(result.output.splitlines()):
        text = line.strip()
        if text.startswith("{"):
            try:
                value = json.loads(text)
            except ValueError:
                return None
            return value if isinstance(value, dict) else None
    return None


def _model_row(model, row: dict, flags: tuple[str, ...] = ()):
    """One row of the verb's JSON as a model: a null flag is False, any other null ""."""
    return model(
        **{
            k: (False if k in flags and v is None else "" if v is None else v)
            for k, v in row.items()
            if k in model.model_fields
        }
    )


def _int(value) -> int:
    try:
        return max(int(value or 0), 0)
    except (TypeError, ValueError):
        return 0


@api.get("/spaces/candidates", response_model=SpaceCandidates)
async def get_candidates(owner: str = "", repo: str = ""):
    params = list(DISCOVER_PARAMS)
    if repo.strip():
        params += ["-Repo", repo.strip()]
    elif owner.strip():
        params += ["-Owner", owner.strip()]
    result = await run_command(NEW_SPACE_COMMAND, CommandRequest(params=params))
    data = _verb_json(result)
    if data is None:
        why = (result.error or "").strip().splitlines()
        return SpaceCandidates(
            available=False,
            reason=why[0] if why else "The CLI did not answer with your repositories.",
            hint="Type the repository as owner/name instead.",
        )
    repos = [
        _model_row(SpaceCandidate, r, ("isArchived", "readOnly"))
        for r in (data.get("repos") or [])
        if isinstance(r, dict)
    ]
    owners = [_model_row(SpaceOwner, o) for o in (data.get("owners") or []) if isinstance(o, dict)]
    return SpaceCandidates(
        available=bool(data.get("available")),
        reason=str(data.get("reason") or ""),
        hint=str(data.get("hint") or ""),
        account=str(data.get("account") or ""),
        owner=str(data.get("owner") or ""),
        owners=owners,
        ceiling=_int(data.get("ceiling")),
        more=bool(data.get("more")),
        repos=repos,
    )
