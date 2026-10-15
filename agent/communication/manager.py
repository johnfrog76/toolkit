"""The 1:1 surface: read and write session files, send the retro, rewrite notes.

Four routes over ``<promptsRoot>/manager/`` plus two that are not about files at
all. The four are the only ``PUT`` in the whole API, and the reason is the same
one the prompt store exists for: a session file is the record, so the thing that
changes it has to be able to change it in place rather than append a new one.
A session is CREATED by the CLI's ``NewMeeting``, run through the bridge -- the
agent scaffolds nothing of its own (see ``create_manager_session``).

``manager/`` is a sibling of the per-org folders, not nested inside one. A 1:1
history spans engagements the way a career record does -- it must not reset when
``activeOrg`` does -- and that is also why the ``manager`` recipient lives in a
top-level ``managerWorkflow`` block instead of on an org.

Everything here is gated on ``features.communication``, an engineer-scoped flag:
with it off the routes are not answerable at all. That is new behaviour. In the
package this was carved from nothing gated these pages -- the flag only reached
the send -- so an install that had never heard of 1:1s still served them.
"""

import asyncio
import re
from datetime import date
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from ..ado import bridge
from ..core import log_writer, model
from ..core.config import hub_folder, hub_root, load_config
from ..core.consts import folder_archive, folder_current, re_session_name
from . import comms

# The verb that scaffolds a session -- a key in the CLI's command table, which is
# what the bridge admits. Config/communication.commands.psd1 declares it, and
# it is in the table only while features.communication is on, which is also
# the gate on every route here.
NEW_MEETING_COMMAND = "NewMeeting"


# ---------------------------------------------------------------------------
# The gate.
#
# A dependency rather than a conditional mount, so the answer is re-read per
# request: config.local.json is hand-editable and a flag flipped in another
# terminal must not need a restart to take effect. Off is a 404 -- not a 403,
# not an empty success. The module is absent, and absent is what a client that
# asks for something that is not there should be told.
# ---------------------------------------------------------------------------
def communication_enabled() -> bool:
    return bool((load_config().get("features") or {}).get("communication", False))


def _require_communication() -> None:
    if not communication_enabled():
        raise HTTPException(
            status_code=404,
            detail="the communication module is off (features.communication)",
        )


api = APIRouter(dependencies=[Depends(_require_communication)])


# ---------------------------------------------------------------------------
# Where the sessions live.
# ---------------------------------------------------------------------------
def _manager_dir(folder: str) -> Path:
    # The sibling's NAME is the hub's to declare (hub.json "folders"); this used
    # to be a literal here and a second one in Scripts/New-Meeting.ps1.
    return hub_folder("manager") / folder


# current/ and archive/ mean the same thing under every hub-root sibling as they
# do under an org, so the two names come from consts.json rather than from here.
_FOLDERS = (folder_current(), folder_archive())


# A record's name is the contract's rule (consts.json regex.sessionName, read by
# the CLI's two meeting verbs too): ``[<series>-]YYYY-MM-DD.md``. The 1:1 is the
# DEFAULT series and its records are named by the date alone, exactly as they
# always were; any other series -- a client weekly, a team sync -- carries its
# name in front, the way a card carries its type, so two meetings on one day
# cannot collide (docs/modules/communication.md).
_SESSION_NAME = re_session_name()
_SERIES_SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DEFAULT_SERIES = ""  # the 1:1: no name in the file, and an IC with one meeting never sees the word


def _series_of(filename: str) -> str:
    """The series a record belongs to, "" for the default (the 1:1)."""
    m = _SESSION_NAME.match(filename)
    return (m.group(1) or "") if m else ""


def _session_filename(series: str, date_str: str) -> str:
    return f"{series}-{date_str}.md" if series else f"{date_str}.md"


def _series_title(series: str, date_str: str) -> str:
    return f"{series} -- {date_str}" if series else f"1:1 -- {date_str}"


def _safe_name(filename: str) -> str:
    """A session filename and nothing else. The hub is a directory this process
    can write to, so a name that can traverse out of it is refused outright
    rather than normalised into something plausible."""
    if "/" in filename or "\\" in filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    return filename


def _session_location(filename: str) -> tuple[Path, str] | None:
    """The session file and the folder it is in -- current/ or archive/ -- or None."""
    for folder in _FOLDERS:
        path = _manager_dir(folder) / filename
        if path.exists() and path.is_file():
            return path, folder
    return None


def _session_path(filename: str) -> Path | None:
    """The session file, in current/ or archive/, or None."""
    found = _session_location(filename)
    return found[0] if found else None


# ---------------------------------------------------------------------------
# The file shape.
#
# One shape, written down once: docs/hub/manager.md documents it,
# templates/ManagerSession.template.md is what a session is CREATED from
# (by NewMeeting, which POST /manager runs), Tests/fixtures/hub/manager/ is an
# example of it, and _build_session_file below is the one thing in Python that
# writes it -- on an EDIT only, never a create. A change to any of those is a
# change to all of them. The placeholders are the template's own words, so a
# section a person emptied is written back as the template wrote it.
# ---------------------------------------------------------------------------
_PLACEHOLDERS = {
    "carried": "(filled by the Plan pass)",
    "agenda": "(populated by the Plan pass)",
    "prep": "(populated at the Prep stage)",
    "retro": "(populated by the Retro pass)",
    "sent": "(nothing sent yet)",
}


def _heading_value(lines: list[str], heading: str) -> str | None:
    """The first non-empty line under a ## heading, matched case-insensitively."""
    needle = heading.lower()
    found = False
    for line in lines:
        if found:
            stripped = line.strip()
            if stripped:
                return stripped
            if line.startswith("##"):
                return None  # next heading -- give up
        elif line.strip().lower().startswith("## ") and line.strip()[3:].lower() == needle:
            found = True
    return None


def _section_content(lines: list[str], heading: str) -> str:
    """Everything between a ## heading and the next one, with a placeholder read
    as empty so a freshly scaffolded file does not pre-fill the form with its
    own instructions."""
    needle = heading.lower()
    capturing = False
    result: list[str] = []
    for line in lines:
        if line.strip().lower().startswith("## ") and line.strip()[3:].lower() == needle:
            capturing = True
            continue
        if capturing:
            if line.startswith("##"):
                break
            result.append(line)
    return _strip_placeholder("\n".join(result).strip())


def _strip_placeholder(content: str) -> str:
    if content.startswith("(") and content.endswith(")"):
        return ""
    if content.startswith("<!--") and content.endswith("-->"):
        return ""
    return content


def _carried_section(lines: list[str]) -> tuple[str, str]:
    """(prior date, body) from the ``## Carried from <date>`` heading. The date
    is in the heading rather than the body because that is what makes the thread
    traceable by eye -- you can see which session it came from without opening
    that one."""
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.lower().startswith("## carried from"):
            prior = stripped[len("## Carried from") :].strip()
            body: list[str] = []
            for rest in lines[i + 1 :]:
                if rest.startswith("##"):
                    break
                body.append(rest)
            return prior, _strip_placeholder("\n".join(body).strip())
    return "", ""


# ---------------------------------------------------------------------------
# Which session a record carries from.
#
# The heading is filled ONCE, when NewMeeting creates the session. A session
# added later for an earlier date, or a heading edited by hand, leaves it naming
# a session that is no longer the latest earlier one in the series. This reader
# says so and rewrites nothing -- the heading is the record. The rule is
# docs/hub/manager.md, "Which session a record carries from"; the CLI's twin is
# Resolve-P20CarriedFrom in Scripts/Resolve-CarriedFrom.ps1, and one shared
# table holds the two together (Tests/fixtures/carried-from/table.json).
# ---------------------------------------------------------------------------
NO_PRIOR = "(none)"
CARRIED_OK = "ok"  # the heading names the latest earlier record, or (none) when there is none
CARRIED_STALE = "stale"  # it names an earlier record, or (none), and a later earlier one exists
CARRIED_MISSING = "missing"  # it names no earlier record in this series
CARRIED_ABSENT = "absent"  # there is no "## Carried from" heading at all
_CARRIED_HEADING = re.compile(r"^## carried from(\s|$)", re.IGNORECASE)


def _carried_heading(lines: list[str]) -> str | None:
    """The text after ``## Carried from``, or None when the session has no such heading."""
    for line in lines:
        stripped = line.strip()
        if _CARRIED_HEADING.match(stripped):
            return stripped[len("## Carried from") :].strip()
    return None


def carried_from_check(session_name: str, heading: str | None, names: list[str]) -> dict:
    """{verdict, named, expected} for one record, over file names only.

    ``names`` is every file name in the meeting folder's current/ and archive/
    together: which folder a record is in does not change which one it follows.
    ``expected`` is the latest earlier record's date in the same series, or
    ``(none)``.
    """
    own = _SESSION_NAME.match(session_name)
    earlier: set[str] = set()
    if own:
        series = own.group(1) or ""
        for name in names:
            m = _SESSION_NAME.match(name)
            if m and (m.group(1) or "") == series and m.group(2) < own.group(2):
                earlier.add(m.group(2))
    expected = max(earlier) if earlier else NO_PRIOR
    named = (heading or "").strip()

    if heading is None:
        verdict = CARRIED_ABSENT
    elif named == expected:
        verdict = CARRIED_OK
    elif named == NO_PRIOR or named in earlier:
        verdict = CARRIED_STALE
    else:
        verdict = CARRIED_MISSING
    return {"verdict": verdict, "named": named, "expected": expected}


def carried_from_note(check: dict) -> str:
    """The one sentence a reader shows when the check is not ok; "" when it is."""
    verdict = check["verdict"]
    if verdict == CARRIED_OK:
        return ""
    expected = check["expected"]
    latest = (
        "there is no earlier session in this series"
        if expected == NO_PRIOR
        else f"the latest earlier session in this series is {expected}"
    )
    tail = "The heading is not rewritten; edit it by hand if it should change."
    if verdict == CARRIED_ABSENT:
        return f"This session has no '## Carried from' heading, and {latest}. {tail}"
    if verdict == CARRIED_STALE:
        return f"Carried from {check['named']}, but {latest}. {tail}"
    return f"Carried from {check['named']}, which is not an earlier session in this series; {latest}. {tail}"


def _carried_from_on_disk(filename: str, lines: list[str]) -> dict:
    names: list[str] = []
    for folder in _FOLDERS:
        directory = _manager_dir(folder)
        if directory.exists():
            names.extend(p.name for p in directory.iterdir() if p.is_file() and p.suffix == ".md")
    return carried_from_check(filename, _carried_heading(lines), names)


def _build_session_file(
    date_str: str,
    *,
    series: str = "",
    stage: str = "draft",
    carried_from: str = "",
    carried: str = "",
    since: str = "",
    forward: str = "",
    agenda: str = "",
    prep: str = "",
    retro: str = "",
    sent: str = "",
) -> str:
    def body(value: str, key: str) -> str:
        return value if value else _PLACEHOLDERS[key]

    return (
        f"# {series + ' ' if series else ''}{date_str}\n\n"
        f"## Stage\n{stage}\n\n"
        f"## Carried from {carried_from or '(none)'}\n{body(carried, 'carried')}\n\n"
        f"## Since Last Session\n{since}\n\n"
        f"## Unresolved / Forward\n{forward}\n\n"
        f"## Agenda\n{body(agenda, 'agenda')}\n\n"
        f"## Prep\n{body(prep, 'prep')}\n\n"
        f"## Retro\n{body(retro, 'retro')}\n\n"
        f"## Sent\n{body(sent, 'sent')}\n"
    )


# ---------------------------------------------------------------------------
# Response models.
# ---------------------------------------------------------------------------
class ManagerItem(BaseModel):
    filename: str
    series: str = ""  # "" is the 1:1, the default series   # "<date>.md"
    date: str  # "<date>"
    stage: str  # "draft" | "prep" | "retro"
    folder: str  # "current" | "archive"
    summary: str


class ManagerResponse(BaseModel):
    items: list[ManagerItem]


class ManagerDetailResponse(BaseModel):
    filename: str
    series: str = ""  # "" is the 1:1
    date: str = ""
    path: str = ""  # absolute, on the agent's machine -- for handing to an assistant
    # Which folder the file is in, "current" or "archive" (consts.json folders).
    # GET serves a closed session; PUT will not write one. A client that sends
    # the retro and then records it has to know which it is looking at BEFORE
    # the send, or it posts a message it cannot record.
    folder: str = ""
    stage: str  # record type -- "session" is the only one left
    session_stage: str  # "draft" | "prep" | "retro"
    title: str
    purpose: str
    content: str
    since: str = ""
    forward: str = ""
    retro_input: str = ""
    sent: str = ""
    # The "## Carried from" check (docs/hub/manager.md, "Which session a record
    # carries from"): what the heading names, the latest earlier record in the
    # series, the verdict, and the sentence to show -- "" when the heading is right.
    carried_from: str = ""
    carried_from_expected: str = ""
    carried_from_verdict: str = ""
    carried_from_note: str = ""


def _carried_fields(filename: str, lines: list[str]) -> dict:
    check = _carried_from_on_disk(filename, lines)
    return {
        "carried_from": check["named"],
        "carried_from_expected": check["expected"],
        "carried_from_verdict": check["verdict"],
        "carried_from_note": carried_from_note(check),
    }


def _parse_manager_session(path: Path, folder: str) -> ManagerItem | None:
    match = _SESSION_NAME.match(path.name)
    if not match:
        return None
    try:
        lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    except OSError:  # an unreadable session parses to nothing, like a misnamed one
        return None
    stage = _heading_value(lines, "stage") or "draft"
    # First real line of the most finished section there is. Placeholder-aware,
    # because a freshly scaffolded session used to list itself as "(populated
    # by ...)" -- which is the file describing its own template, not a summary.
    summary = ""
    for heading in ("retro", "summary", "agenda"):
        content = _section_content(lines, heading)
        if content:
            summary = content.splitlines()[0].strip()
            break
    return ManagerItem(
        filename=path.name,
        series=match.group(1) or "",
        date=match.group(2),
        stage=stage,
        folder=folder,
        summary=summary,
    )


# ---------------------------------------------------------------------------
# GET /api/manager -- every session, newest first.
# ---------------------------------------------------------------------------
@api.get("/manager", response_model=ManagerResponse)
async def get_manager():
    items: list[ManagerItem] = []
    for folder in _FOLDERS:
        directory = _manager_dir(folder)
        if not directory.exists():
            continue
        for path in sorted(directory.iterdir(), reverse=True):
            if path.is_file() and path.suffix == ".md":
                item = _parse_manager_session(path, folder)
                if item:
                    items.append(item)
    items.sort(key=lambda i: i.date, reverse=True)
    return ManagerResponse(items=items)


# ---------------------------------------------------------------------------
# GET /api/manager/{filename} -- one session, parsed and raw.
# ---------------------------------------------------------------------------
@api.get("/manager/{filename}", response_model=ManagerDetailResponse)
async def get_manager_detail(filename: str):
    filename = _safe_name(filename)
    found = _session_location(filename)
    if not found:
        raise HTTPException(status_code=404, detail=f"{filename} not found")
    path, folder = found

    item = _parse_manager_session(path, folder)
    if not item:
        raise HTTPException(status_code=400, detail="Could not parse session file")

    content = path.read_text(encoding="utf-8-sig", errors="replace")
    lines = content.splitlines()
    return ManagerDetailResponse(
        filename=filename,
        series=item.series,
        date=item.date,
        path=str(path.resolve()),
        folder=folder,
        stage="session",
        session_stage=_heading_value(lines, "stage") or "draft",
        title=_series_title(item.series, item.date),
        purpose=item.summary,
        content=content,
        since=_section_content(lines, "since last session"),
        forward=_section_content(lines, "unresolved / forward"),
        retro_input=_section_content(lines, "retro"),
        sent=_section_content(lines, "sent"),
        **_carried_fields(filename, lines),
    )


# ---------------------------------------------------------------------------
# POST /api/manager -- create a session, by running NewMeeting through the
# bridge. PUT /api/manager/{f} -- rewrite one, natively.
#
# The create follows the rule every other write follows: one implementation,
# the CLI's. This route used to build the file in Python, from its own
# copy of the shape, and the two scaffolds drifted from the day they were
# written -- HTML comments in the template, parenthesised placeholders here.
#Now the verb
# writes the file, from the template, with the one card writer, and this route
# reads it back to answer in the shape it always answered in.
#
# The PUT stays native, and that is the one place the "every write is a CLI
# call" rule bends. It bends for a reason worth stating: it saves a form the
# user is typing into, and round-tripping keystrokes through a PowerShell
# process start would make the editor unusable. _build_session_file is the one
# thing in Python that writes a session, and it never creates one.
# ---------------------------------------------------------------------------
class ManagerCreateRequest(BaseModel):
    # Everything else about a session is an edit: notes go through PUT, after
    # the verb has scaffolded the file. `extra="forbid"` so a caller that sends
    # `since` here is told, rather than having it dropped.
    model_config = ConfigDict(extra="forbid")

    # The series: "" or absent is the 1:1; otherwise a slug.
    series: str = ""
    date: str = ""


class ManagerSaveRequest(BaseModel):
    since: str = ""
    forward: str = ""
    retro: str = ""
    # One line to add to the Sent section, e.g. "Sent to manager: <date>".
    # Appended here rather than composed by the caller so the caller never has
    # to read the file back to add to it.
    append_sent: str = ""


@api.post("/manager", response_model=ManagerDetailResponse)
async def create_manager_session(req: ManagerCreateRequest):
    try:
        date.fromisoformat(req.date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date -- use YYYY-MM-DD")

    series = (req.series or "").strip()
    if series and not _SERIES_SLUG.match(series):
        raise HTTPException(
            status_code=400, detail=f"'{series}' is not a series name -- lower-case letters, digits and dashes"
        )
    filename = _session_filename(series, req.date)
    path = _manager_dir(folder_current()) / filename

    # The verb refuses both of these too -- an existing session is reported and
    # left alone, a closed one is a stated refusal -- and both are read here
    # first so the answer is a 409 that names the folder rather than a verb's
    # sentence mapped after the fact. The session DATE is the file's identity
    # (docs/hub/manager.md), so "already exists" means EITHER folder.
    #
    if path.exists():
        raise HTTPException(status_code=409, detail=f"{filename} already exists -- use PUT to update")
    archived = _manager_dir(folder_archive()) / filename
    if archived.exists():
        raise HTTPException(
            status_code=409,
            detail=f"{filename} is already closed, in manager/archive/ -- a closed session is the record, not a draft",
        )

    function = bridge.command_map().get(NEW_MEETING_COMMAND)
    if not function:
        raise HTTPException(
            status_code=503,
            detail=f"'{NEW_MEETING_COMMAND}' is not in this CLI's command table; "
            "the communication module may not be loaded.",
        )
    params = ["-Date", req.date] + (["-Type", series] if series else [])
    try:
        result = await asyncio.to_thread(
            bridge._run,
            function,
            params,
            bridge.command_timeout(NEW_MEETING_COMMAND),
            # The hub this process resolved, so the verb writes where this
            # route will read. PROMPTS_ROOT wins over config in the CLI too.
            {"PROMPTS_ROOT": str(hub_root())},
        )
    except OSError as e:
        log_writer.write_log("ERR", "agent/manager", str(e)[:200])
        raise HTTPException(status_code=500, detail=f"Could not run {NEW_MEETING_COMMAND}: {e}")

    said = (result.stderr or result.stdout or "").strip()
    if result.returncode != 0:
        # A stated refusal (exit 2) or a failure. The two refusals were read
        # above, so this is the race, or a hub the verb could not find.
        status = 409 if "already" in said else 500
        raise HTTPException(status_code=status, detail=said or f"{NEW_MEETING_COMMAND} exited {result.returncode}")
    if not path.exists():
        # "already exists" is exit 0 from the verb (it returns the card), and
        # would be a race here; anything else is the verb writing elsewhere.
        raise HTTPException(
            status_code=500,
            detail=f"{NEW_MEETING_COMMAND} reported success but {filename} is not in {path.parent}: {said}",
        )

    log_writer.write_log("CMD", "agent/manager", f"created {filename} via {NEW_MEETING_COMMAND}")
    return await get_manager_detail(filename)


@api.put("/manager/{filename}", response_model=ManagerDetailResponse)
async def update_manager_session(filename: str, req: ManagerSaveRequest):
    filename = _safe_name(filename)
    path = _manager_dir(folder_current()) / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="Session not found")

    lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    # Everything the form does not own is read back off the file and written
    # again unchanged. The agent-written sections in particular: a save from the
    # notes form must never be able to delete an agenda.
    carried_from, carried = _carried_section(lines)
    sent = _section_content(lines, "sent")
    if req.append_sent:
        sent = f"{sent}\n{req.append_sent}".strip() if sent else req.append_sent

    # The name rule's groups are (series, date): group 1 is the SERIES, None for
    # the 1:1. This read group 1 as the date, so every save rewrote a 1:1's
    # heading as "# None" and a series record's as its series with no date --
    # and dropped the series from the heading either way.
    #
    match = _SESSION_NAME.match(filename)
    series = (match.group(1) or "") if match else ""
    date_str = match.group(2) if match else filename
    stage = _heading_value(lines, "stage") or "draft"

    content = _build_session_file(
        date_str,
        series=series,
        stage=stage,
        carried_from=carried_from,
        carried=carried,
        since=req.since,
        forward=req.forward,
        agenda=_section_content(lines, "agenda"),
        prep=_section_content(lines, "prep"),
        retro=req.retro,
        sent=sent,
    )
    path.write_text(content, encoding="utf-8")
    log_writer.write_log("CMD", "agent/manager", f"saved {filename}")

    item = _parse_manager_session(path, folder_current())
    return ManagerDetailResponse(
        filename=filename,
        series=series,
        date=date_str,
        path=str(path.resolve()),
        folder=folder_current(),
        stage="session",
        session_stage=stage,
        title=_series_title(series, date_str),
        purpose=item.summary if item else "",
        content=content,
        since=req.since,
        forward=req.forward,
        retro_input=req.retro,
        sent=sent,
        **_carried_fields(filename, content.splitlines()),
    )


# ---------------------------------------------------------------------------
# POST /api/comms/send -- the outbound channel.
#
# A thin wrapper: validate the body's shape, hand the message object to the
# engine, return its {status, detail}. Deliberately NOT /cmd/{name} -- it sends
# a message, it does not run a verb. The engine owns gating, formatting,
# transport and failure, and never raises.
# ---------------------------------------------------------------------------
class CommsSection(BaseModel):
    heading: str = ""
    body: str = ""


class CommsSendRequest(BaseModel):
    caller: str
    recipient: str
    subject: str
    sections: list[CommsSection]
    tone: str = "broadcast"
    dryRun: bool = False


class CommsSendResponse(BaseModel):
    status: str
    detail: str
    target: dict | None = None
    payload: str | None = None


@api.post("/comms/send", response_model=CommsSendResponse)
async def comms_send(req: CommsSendRequest):
    result = await asyncio.to_thread(comms.send, req.model_dump())
    return CommsSendResponse(
        status=result.get("status", "error"),
        detail=result.get("detail", ""),
        target=result.get("target"),
        payload=result.get("payload"),
    )


# ---------------------------------------------------------------------------
# POST /api/rewrite -- tidy a raw notes textarea.
#
# A legibility pass and nothing more: spelling, grammar, and rambling broken
# into bullets. Not the reframing the 1:1 agent prompt does later -- meaning,
# voice and every specific detail stay exactly as written. It belongs to this
# module because the notes fields it serves do.
# ---------------------------------------------------------------------------
_REWRITE_SYSTEM_PROMPT = (
    "You clean up raw, informally-typed notes before someone uses them in a "
    "work document. Fix spelling and grammar. Break rambling sentences into "
    "short, scannable bullet points where that helps. Preserve the writer's "
    "meaning, voice, and every specific detail exactly -- never summarize, "
    "reframe, soften, or add anything they did not say. Reply with only the "
    "cleaned-up text: no preamble, no explanation, no markdown fences."
)


class RewriteRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=8000)


class RewriteResponse(BaseModel):
    text: str


@api.post("/rewrite", response_model=RewriteResponse)
async def rewrite_text(req: RewriteRequest):
    try:
        cleaned = await model.complete(
            req.text,
            system=_REWRITE_SYSTEM_PROMPT,
            max_tokens=1024,
        )
        return RewriteResponse(text=cleaned.strip())
    except model.ModelUnavailable as why:
        # No key, or no SDK, is a decline with a reason, in the same shape the
        # PR-comment suggest route uses -- 412, the profile's sentence: the
        # client renders the detail, and the button that offers this is hidden
        # when /env says there is no key anyway.
        log_writer.write_log("WARN", "agent/rewrite", str(why))
        raise HTTPException(status_code=412, detail=str(why))
    except Exception as e:  # noqa: BLE001 -- whatever the model call raised is the route's 502, logged
        log_writer.write_log("ERR", "agent/rewrite", str(e)[:200])
        raise HTTPException(status_code=502, detail=str(e))


# ---------------------------------------------------------------------------
# What /env says about this module.
#
# Gate 2 -- whether a recipient's webhook variable is actually set -- can only
# be answered at runtime, and the UI needs the answer BEFORE the click so it can
# offer a disabled button that names the variable instead of discovering the
# problem afterwards.
#
# The two places recipients live are rendered honestly rather than flattened:
# `scope` says which block an entry came from, because "the manager recipient is
# top-level and the team channels are the org's" is a real property of the
# config, and a UI that hides it cannot explain why switching org changed one
# list and not the other.
# ---------------------------------------------------------------------------
def communication_env() -> dict:
    cfg = load_config()
    workflow = comms.manager_workflow()

    entries: list[dict] = []
    seen: set[str] = set()

    def add(key: str, entry: dict, scope: str) -> None:
        if key in seen:
            return
        seen.add(key)
        entries.append(
            {
                "key": key,
                "display": entry.get("display", key),
                "type": entry.get("type", ""),
                "scope": scope,
                # Both answers come from the engine. /env must not have its own
                # opinion about which variable a recipient uses, or it will
                # eventually disagree with the thing that actually sends.
                "webhookEnv": comms.webhook_env_name(key, entry),
                "configured": comms.webhook_configured(key, entry),
            }
        )

    active_slug = cfg.get("activeSpace", "")
    active_space = next((o for o in cfg.get("spaces", []) if o.get("slug") == active_slug), {}) or {}
    for key, entry in ((active_space.get("communication", {}) or {}).get("recipients", {}) or {}).items():
        add(key, entry or {}, "org")
    for key, entry in ((workflow.get("communication", {}) or {}).get("recipients", {}) or {}).items():
        add(key, entry or {}, "managerWorkflow")

    return {
        "postRetroSummary": bool(workflow.get("postRetroSummary", False)),
        "retroChannel": workflow.get("retroChannel", "manager"),
        "recipients": entries,
    }
