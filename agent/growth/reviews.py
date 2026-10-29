"""GET /reviews, GET /reviews/{folder}, GET /review-preview, POST /review/generate.

``<promptsRoot>/reviews/<slug-set>/<year>/<start>_<end>/review.md``. A folder
name is a date range, so the same range can exist under several orgs; the
slug-set segment is what disambiguates, and ``?slugs=first+second`` is how a
link says which one it meant.

The two routes that DO something -- generating a scaffold, committing the
folder -- go through the bridge, not through a PowerShell command string built
here. The package this was carved from had its own ``pwsh -Command`` builder
alongside the bridge, which meant two places that knew how to start the CLI,
two sets of quoting rules and one of them getting a comma-separated slug list
wrong often enough to need a comment explaining the workaround. Parameters
travel as argv through ``bridge._run`` and nothing is quoted anywhere.

``ReviewPage`` in the ADO module reads ``/review-preview`` and ``/reviews/{folder}``
from here (spec D-RP (a)): the page is an ADO card and this module serves its
data, so with growth switched off the page shows "no reviews" rather than
breaking. That is a dependency, not a fork.
"""

import asyncio
import json
import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..ado import bridge
from ..ado.reporting import _scan_reviews
from ..core.config import load_config
from ..core.log_writer import write_log

api = APIRouter()


class PendingFile(BaseModel):
    """One uncommitted file, as the CLI's -Preview reports it."""

    file: str
    content: str


class ReviewPreviewResponse(BaseModel):
    files: list[PendingFile]


class ReviewListItem(BaseModel):
    period: str  # "<start> - <end>"
    folder: str  # "<start>_<end>"
    start_date: str
    end_date: str
    title: str  # the first H1 in the file


class ReviewsListResponse(BaseModel):
    count: int
    reviews: list[ReviewListItem]


class ReviewDetailResponse(BaseModel):
    folder: str
    period: str
    title: str
    content: str
    path: str = ""  # absolute, on the agent's machine -- for handing to an assistant


class ReviewGenerateRequest(BaseModel):
    start_date: str  # YYYY-MM-DD
    end_date: str  # YYYY-MM-DD
    slugs: list[str] = []  # non-empty; every one must be a known org slug


class ReviewGenerateResponse(BaseModel):
    review: str
    file_path: str
    files_scanned: int
    files_included: int


# ---------------------------------------------------------------------------
# Running a CLI verb that answers in JSON
# ---------------------------------------------------------------------------


async def run_cli_json(command: str, params: list[str]) -> dict:
    """Run one CLI verb through the bridge and parse its JSON.

    The bridge's allowlist is the CLI's own command table, so a verb this
    module contributes is callable here the moment its module is switched on --
    which it must be, or these routes are 404 anyway.
    """
    table = bridge.command_map()
    function = table.get(command)
    if not function:
        raise HTTPException(
            status_code=503,
            detail=f"'{command}' is not in this CLI's command table; the growth module may not be loaded.",
        )
    try:
        result = await asyncio.to_thread(bridge._run, function, params, bridge.command_timeout(command))
    except OSError as e:
        write_log("ERR", f"Agent/{command}", str(e)[:200])
        raise HTTPException(status_code=500, detail=f"Could not run {command}: {e}")

    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() or f"{command} exited {result.returncode}"
        raise HTTPException(status_code=500, detail=detail)

    data = _json_object(result.stdout or "")
    if data is None:
        raise HTTPException(status_code=500, detail=f"{command} produced no readable JSON object")
    return data


def _json_object(stdout: str) -> dict | None:
    """The JSON object in a verb's output, or None.

    ConvertTo-Json pretty-prints by default, so the payload is usually several
    lines with a bare ``{`` on the first one -- and a verb may legitimately say
    something before it. So: try the whole thing, then the span from the first
    ``{`` to the last ``}``, then any single line that is an object on its own
    (``-Compress``). Reading only the last line that opens an object, which is
    what the bridge's own command-map read does, works for a compressed one-liner
    and silently fails on a pretty-printed one.
    """
    text = stdout.strip()
    if not text:
        return None

    candidates = [text]
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end > start:
        candidates.append(text[start : end + 1])
    candidates.extend(
        ln.strip() for ln in reversed(text.splitlines()) if ln.strip().startswith("{") and ln.strip().endswith("}")
    )

    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@api.get("/review-preview", response_model=ReviewPreviewResponse)
async def get_review_preview():
    data = await run_cli_json("PublishWorkReview", ["-Preview"])
    return ReviewPreviewResponse(files=[PendingFile(**f) for f in data.get("files", [])])


@api.post("/review/generate", response_model=ReviewGenerateResponse)
async def generate_review(req: ReviewGenerateRequest):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", req.start_date) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", req.end_date):
        raise HTTPException(status_code=400, detail="Dates must be YYYY-MM-DD")
    if not req.slugs:
        raise HTTPException(status_code=400, detail="slugs must be a non-empty list")

    known = [o["slug"] for o in load_config().get("spaces", [])]
    unknown = [s for s in req.slugs if s not in known]
    if unknown:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown org(s): {', '.join(unknown)}. Available: {', '.join(known)}",
        )

    sorted_slugs = sorted(req.slugs)
    data = await run_cli_json(
        "NewWorkReview",
        [
            "-StartDate",
            req.start_date,
            "-EndDate",
            req.end_date,
            # One argv entry. The carved-out version joined parameters into a
            # command string, where "first,second" was read by PowerShell's comma
            # operator as an array and rejected by a [string] parameter -- and was
            # worked around with hand-added quotes. argv has no such reading.
            "-Slugs",
            ",".join(sorted_slugs),
        ],
    )

    if "error" in data:
        raise HTTPException(status_code=400, detail=data["error"])
    missing = {"review", "file_path", "files_scanned", "files_included"} - data.keys()
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"NewWorkReview answered incompletely (missing: {', '.join(sorted(missing))})",
        )

    write_log(
        "CMD",
        "Agent/review/generate",
        f"{data.get('file_path', '?')} -- {data.get('files_included', 0)} files, "
        f"{'+'.join(sorted_slugs)}, {req.start_date}-{req.end_date}",
    )
    return ReviewGenerateResponse(**data)


@api.get("/reviews", response_model=ReviewsListResponse)
async def list_reviews():
    # Scoped to the active Space, so the list matches the context the rest of the
    # app is in. A review folder belongs to a slug when that slug is in its
    # slug-set, so a combined first+second review appears under both.
    active_slug = load_config().get("activeSpace") or None
    items = [
        ReviewListItem(
            period=f"{start} – {end}",
            folder=folder,
            start_date=start,
            end_date=end,
            title=title,
        )
        for folder, start, end, title, _path, _orgs in await asyncio.to_thread(_scan_reviews, active_slug)
    ]
    return ReviewsListResponse(count=len(items), reviews=items)


@api.get("/reviews/{folder}", response_model=ReviewDetailResponse)
async def get_review_detail(folder: str, slugs: str | None = None, archived: bool = False):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}", folder):
        raise HTTPException(status_code=400, detail="Invalid folder format")
    # A folder name is only a date range, so the same one can exist under
    # several orgs. ?slugs=first+second names the slug-set; a link without it
    # falls back to the active Space.
    target = sorted(slugs.split("+")) if slugs else None
    active_slug = None if slugs else (load_config().get("activeSpace") or None)

    # ?archived=true reads reviews/archive/ -- an archived review is still there to open.
    for name, start, end, title, path, orgs in await asyncio.to_thread(_scan_reviews, active_slug, archived):
        if name != folder:
            continue
        if target is not None and sorted(orgs) != target:
            continue
        return ReviewDetailResponse(
            folder=folder,
            period=f"{start} – {end}",
            title=title,
            content=path.read_text(encoding="utf-8-sig", errors="replace"),
            path=str(path.resolve()),
        )
    raise HTTPException(status_code=404, detail=f"Review not found: {folder}")
