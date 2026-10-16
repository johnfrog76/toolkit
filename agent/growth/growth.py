"""GET /growth, GET /growth/{filename}.

The hub's ``growth/current/`` folder, read in the shape ``docs/hub/growth.md``
documents. Nothing here writes one: a new growth item is ``NewGrowth`` through
the bridge (``POST /cmd/NewGrowth``), so the CLI's ``Scripts/New-GrowthItem.ps1``
is the one writer and the browser and the terminal write the same file.

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
from pydantic import BaseModel

from ..core.config import hub_folder, load_config
from ..core.parsers import _heading_value

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


# ---------------------------------------------------------------------------
# Reading a file
# ---------------------------------------------------------------------------


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
