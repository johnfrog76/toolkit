"""GET /growth, POST /growth, GET /growth/{filename}.

The hub's ``growth/current/`` folder, read and written in the shape
``docs/hub/growth.md`` documents. That document is the contract, not this file
and not ``Scripts/New-GrowthItem.ps1`` -- two consumers of one file format stay
honest by both being held to a written shape, and ``Tests/test_growth.py``
asserts the two write the same bytes for the same inputs.

Three types, distinguished by filename prefix, because the filename is the one
piece of a markdown file a person can see without opening it:

    training-YYYY-MM-DD-slug.prompt.md
    presentation-YYYY-MM-DD-slug.prompt.md
    goal-YYYY-slug.prompt.md
"""

import asyncio
import calendar
import re
from datetime import date
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..core.config import hub_folder, load_config

api = APIRouter()

TYPES = ("training", "presentation", "goal")


def growth_dir() -> Path:
    """The hub's growth folder, current/. Resolved per call, because the hub is
    config-driven and can change without restarting the agent -- and the folder
    NAME is the hub's to declare (hub.json "folders"), not a literal here."""
    return hub_folder("growth") / "current"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class GrowthItem(BaseModel):
    filename: str
    type: str  # training | presentation | goal
    title: str
    date: str  # the display string as written in the file
    due_date: str | None = None  # ISO date of the deadline, when one parses
    status: str  # new | active | complete
    provider: str | None = None  # trainings only
    hours: str | None = None  # trainings only


class TrainingQuarter(BaseModel):
    """Where the engineer stands against a Space's quarterly training requirement."""

    quarter: str  # "Q3 2026"
    hours: float | int  # hours of COMPLETE trainings dated inside the quarter
    required: int  # the Space's trainingHoursPerQuarter
    daysLeft: int  # whole days from today to the quarter's last day
    planned: float | int = 0  # hours of trainings dated inside it that are not complete yet


class GrowthResponse(BaseModel):
    items: list[GrowthItem]
    # null when the active Space states no requirement: off means absent, so the
    # page has nothing to draw and nothing to fetch.
    trainingQuarter: TrainingQuarter | None = None


class GrowthDetailResponse(BaseModel):
    filename: str
    path: str = ""  # absolute, on the agent's machine -- for handing to an assistant
    title: str
    type: str
    status: str
    content: str


class CreateGrowthRequest(BaseModel):
    type: str
    title: str = Field(..., min_length=1, max_length=200)
    date: str  # YYYY-MM-DD
    due_date: str | None = None  # YYYY-MM-DD; required for a training
    provider: str | None = None
    hours: str | None = None
    notes: str | None = None


# ---------------------------------------------------------------------------
# Reading a file
# ---------------------------------------------------------------------------


def _heading_value(lines: list[str], heading: str) -> str | None:
    """The first line of VALUE under a ``## Heading``, or None.

    Not the first non-empty line: the section ends at the next ``##``, and two
    kinds of line inside it are not values. The writer puts ``---`` between
    groups of headings and writes every heading even when it is empty, so a
    training with no provider used to read its provider as ``---``; and a file
    made by hand from ``templates/Training.template.md`` keeps the template's
    ``<!-- ... -->`` hints, which used to be read as its title, date and status.
    docs/hub/growth.md promises that a template-made file reads the same as a
    generated one, and this is where that promise is kept.
    """
    needle = heading.lower()
    found = False
    in_comment = False
    for line in lines:
        stripped = line.strip()
        if not found:
            if stripped.lower().startswith("## ") and stripped[3:].strip().lower() == needle:
                found = True
            continue
        if in_comment:
            if "-->" in stripped:
                in_comment = False
            continue
        if stripped.startswith("##"):
            return None  # the next heading -- the section was empty
        if not stripped or stripped == "---":
            continue
        if stripped.startswith("<!--"):
            if "-->" not in stripped:
                in_comment = True
            continue
        return stripped
    return None


def _section(lines: list[str], heading: str, prefix: bool = False) -> str:
    """Everything between a ``## Heading`` and the next one.

    ``prefix`` matches a heading that STARTS WITH the word. The files in a hub
    outlive the template they were made from: a presentation written in April is
    headed ``## Outcome`` and one written in July ``## Outcome & Follow-Up``, and
    both say whether the talk was given. The predecessor read both; an exact match
    here read the April one as never delivered.
    """
    needle = heading.lower()
    capturing = False
    out: list[str] = []
    for line in lines:
        stripped = line.strip().lower()
        is_heading = stripped.startswith("## ")
        name = stripped[3:].strip() if is_heading else ""
        if is_heading and (name.startswith(needle) if prefix else name == needle):
            capturing = True
            continue
        if capturing:
            if line.startswith("##"):
                break
            out.append(line)
    return "\n".join(out).strip()


def _parse_due_date(value: str | None) -> str | None:
    """The deadline out of a date field.

    A range reads ``<start> to <end>`` and the deadline is the end of
    it. A single date is its own deadline. TBA is not a date.
    """
    if not value or value.strip().upper() == "TBA":
        return None
    for separator in (" to ", " — ", " – ", " - "):
        if separator in value:
            end = value.split(separator)[-1].strip()
            m = re.search(r"\d{4}-\d{2}-\d{2}", end)
            return m.group(0) if m else None
    m = re.search(r"\d{4}-\d{2}-\d{2}", value)
    return m.group(0) if m else None


def parse_growth_file(path: Path) -> GrowthItem | None:
    """One file to one item, or None if the name says it is not one of ours."""
    stem = path.stem
    item_type = next((t for t in TYPES if stem.startswith(f"{t}-")), None)
    if item_type is None:
        return None

    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return None

    lines = text.splitlines()
    provider = _heading_value(lines, "provider")
    hours = _heading_value(lines, "hours")

    if item_type == "presentation":
        title = _heading_value(lines, "title") or stem
        date_str = _heading_value(lines, "date & time") or "TBA"
        # Status comes from the outcome block: a talk is complete when it has
        # been given, and the file says so in one line.
        delivered = re.search(
            r"\*\*Delivered\*\*[^:]*:\s*(Yes|No)", _section(lines, "outcome", prefix=True), re.IGNORECASE
        )
        status = "complete" if (delivered and delivered.group(1).lower() == "yes") else "active"
        due_date = _parse_due_date(date_str)
    elif item_type == "goal":
        title = _heading_value(lines, "goal") or stem
        date_str = _heading_value(lines, "time frame") or ""
        raw_status = ""
        m = re.search(r"\*\*Status\*\*[^:]*:\s*(.+)", _section(lines, "outcome", prefix=True))
        if m:
            raw_status = m.group(1).strip()
        status = _status_word(raw_status)
        due_date = _parse_due_date(date_str)
    else:
        title = _heading_value(lines, "title") or stem
        date_str = _heading_value(lines, "date(s)") or ""
        status = _status_word(_heading_value(lines, "status") or "")
        # An explicit Due Date heading wins over the end of the range.
        explicit = _heading_value(lines, "due date")
        due_date = _parse_due_date(explicit) if explicit else _parse_due_date(date_str)

    return GrowthItem(
        filename=path.name,
        type=item_type,
        title=title,
        date=date_str,
        due_date=due_date,
        status=status,
        provider=provider,
        hours=hours,
    )


def _status_word(raw: str) -> str:
    """The file's own words for progress, in the three the UI sorts on."""
    text = raw.strip().lower()
    if text.startswith("not start"):
        return "new"
    if text.startswith(("complet", "achiev")):
        return "complete"
    return "active"


# ---------------------------------------------------------------------------
# Writing a file -- the CLI writes exactly these bytes, see docs/hub/growth.md
# ---------------------------------------------------------------------------


def _training_file(title: str, date_str: str, provider: str | None, hours: str | None, notes: str | None) -> str:
    return f"""# Training Artifact

---

## Title

{title}

## Type

Voluntary

## Date(s)

{date_str}

## Hours

{hours or "TBD"}

## Provider

{provider or ""}

---

## Description

{(notes or "").strip()}

---

## Status

Not Started

## Key Takeaways

-
-
-

---

## Outcome

- **Completed**: No
- **Certificate / badge**:
- **Applied to work**:
"""


def _presentation_file(title: str, date_str: str, notes: str | None, presenter: str) -> str:
    return f"""# Presentation Artifact

---

## Title

{title}

## Presenter

{presenter}

## Date & Time

{date_str}

## Format

## Prep Estimate

## Audience

---

## Context & Intent

{(notes or "").strip()}

---

## Outline / Slide Summary

### Section 1 -
### Section 2 -
### Section 3 -

---

## Key Themes

---

## Outcome & Follow-Up

- **Delivered**: No
- **Audience size**:
- **Feedback received**:
- **Follow-up actions**:
- **Recording / materials link**:
"""


def _goal_file(title: str, date_str: str, notes: str | None) -> str:
    return f"""# Goal Artifact

---

## Goal

{title}

## Category

## Time Frame

{date_str}

---

## Why This Matters

{(notes or "").strip()}

---

## Milestones

- [ ]
- [ ]
- [ ]

---

## Progress Log

| Date | Update |
|------|--------|
|      |        |

---

## Outcome

- **Status**: Not Started
- **Evidence**:
- **Impact**:
"""


def build_growth_file(req: CreateGrowthRequest, presenter: str = "") -> tuple[str, str]:
    """(filename, content) for a request, and the single place either consumer
    decides what a new growth file is called and contains."""
    # ASCII 'to', not a dash: this string is parsed back by both readers, and a
    # PS 5.1 shell on a Windows-1252 code page misreads an en dash inside a
    # double-quoted string -- so the CLI cannot write one.
    date_str = f"{req.date} to {req.due_date}" if req.due_date else req.date
    slug = re.sub(r"[^a-z0-9]+", "-", req.title.lower()).strip("-")[:40].rstrip("-")

    if req.type == "goal":
        # A goal is dated by YEAR: it belongs to a review period, not to an
        # afternoon.
        filename = f"goal-{req.date[:4]}-{slug}.prompt.md"
        content = _goal_file(req.title, date_str, req.notes)
    elif req.type == "training":
        filename = f"training-{req.date}-{slug}.prompt.md"
        content = _training_file(req.title, date_str, req.provider, req.hours, req.notes)
    else:
        filename = f"presentation-{req.date}-{slug}.prompt.md"
        content = _presentation_file(req.title, date_str, req.notes, presenter)
    return filename, content


def _presenter() -> str:
    """Whose name goes on a presentation. Config, never a name in source."""
    return (load_config().get("branchUser") or "").strip()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

_STATUS_ORDER = {"new": 0, "active": 1, "complete": 2}


def _read_all() -> list[GrowthItem]:
    directory = growth_dir()
    if not directory.exists():
        return []
    items = []
    for path in sorted(directory.iterdir()):
        if path.is_file() and path.name.endswith(".prompt.md"):
            item = parse_growth_file(path)
            if item:
                items.append(item)
    # Not started first, then in flight by how soon they are due, then done.
    # The page is a to-do list before it is an archive.
    items.sort(key=lambda it: (_STATUS_ORDER.get(it.status, 3), it.due_date or "9999-99-99"))
    return items


def space_training_hours() -> int | None:
    """The active Space's ``features.trainingHoursPerQuarter``, or None for no requirement.

    Read off the Space itself (hub.json, then config.local.json's ``spaces.<slug>``
    patch -- both already merged by ``load_config``), because the merged
    ``features`` map carries boolean flags only. Anything that is not a positive
    whole number is no requirement."""
    cfg = load_config()
    active = cfg.get("activeSpace", "")
    space = next((s for s in (cfg.get("spaces") or []) if s.get("slug") == active), None)
    value = ((space or {}).get("features") or {}).get("trainingHoursPerQuarter")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    hours = int(value)
    return hours if hours > 0 else None


def _hours_of(raw: str | None) -> float:
    """Hours out of the training file's ``## Hours`` text -- ``8``, ``2.5``, ``8 hours``.
    Text with no number in it (TBA) is no hours."""
    m = re.search(r"\d+(?:\.\d+)?", raw or "")
    return float(m.group(0)) if m else 0.0


def _tidy(hours: float) -> float | int:
    return int(hours) if float(hours).is_integer() else round(hours, 2)


def training_quarter(items: list[GrowthItem], required: int | None, today: date) -> TrainingQuarter | None:
    """The quarter line: trainings whose deadline falls in today's calendar quarter.

    A training counts on its END date (``due_date``, the same reading ``_parse_due_date``
    gives a range), so a training with no parseable date is not counted at all. A
    ``complete`` training is banked; a ``new`` or ``active`` one is planned. None
    when there is no requirement."""
    if not required:
        return None
    q = (today.month - 1) // 3 + 1
    first = date(today.year, 3 * q - 2, 1)
    last = date(today.year, 3 * q, calendar.monthrange(today.year, 3 * q)[1])
    banked = planned = 0.0
    for item in items:
        if item.type != "training" or not item.due_date:
            continue
        try:
            due = date.fromisoformat(item.due_date)
        except ValueError:
            continue
        if not (first <= due <= last):
            continue
        if item.status == "complete":
            banked += _hours_of(item.hours)
        else:
            planned += _hours_of(item.hours)
    return TrainingQuarter(
        quarter=f"Q{q} {today.year}",
        hours=_tidy(banked),
        required=required,
        daysLeft=(last - today).days,
        planned=_tidy(planned),
    )


@api.get("/growth", response_model=GrowthResponse)
async def get_growth():
    items = await asyncio.to_thread(_read_all)
    return GrowthResponse(
        items=items,
        trainingQuarter=training_quarter(items, space_training_hours(), date.today()),
    )


@api.post("/growth", response_model=GrowthDetailResponse)
async def create_growth(req: CreateGrowthRequest):
    if req.type not in TYPES:
        raise HTTPException(status_code=400, detail=f"type must be one of: {', '.join(TYPES)}")
    try:
        date.fromisoformat(req.date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date -- use YYYY-MM-DD")
    if req.due_date:
        try:
            date.fromisoformat(req.due_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid due_date -- use YYYY-MM-DD")
    if req.type == "training" and not req.due_date:
        raise HTTPException(status_code=400, detail="due_date is required for a training item")

    filename, content = build_growth_file(req, presenter=_presenter())
    directory = growth_dir()
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / filename
    if path.exists():
        raise HTTPException(status_code=409, detail=f"{filename} already exists")
    # newline="\n" and no BOM: the same bytes the CLI writes, on every platform.
    path.write_text(content, encoding="utf-8", newline="\n")
    return GrowthDetailResponse(filename=filename, title=req.title, type=req.type, status="new", content=content)


@api.get("/growth/{filename}", response_model=GrowthDetailResponse)
async def get_growth_detail(filename: str):
    # growth/current/ and nothing else. A filename is a name, not a path.
    if "/" in filename or "\\" in filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    path = growth_dir() / filename
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail=f"{filename} not found")
    item = parse_growth_file(path)
    if not item:
        raise HTTPException(status_code=400, detail=f"{filename} is not a growth artifact")
    return GrowthDetailResponse(
        filename=filename,
        path=str(path.resolve()),
        title=item.title,
        type=item.type,
        status=item.status,
        content=path.read_text(encoding="utf-8-sig", errors="replace"),
    )
