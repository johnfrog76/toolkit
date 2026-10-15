"""GET /resume, GET /resume-preview.

``<promptsRoot>/resume/resume.md`` -- one file, a hub-root sibling of the
per-org folders. The Skills page renders it; nothing here writes it.

The preview is the uncommitted diff, and it does NOT come from this process
reading git: it comes from running the CLI's own UpdateResume -Preview through
the bridge. One implementation of "what is pending in resume/", in the half
that owns it.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core.clock import local_stamp
from ..core.config import hub_folder
from .reviews import PendingFile, run_cli_json

api = APIRouter()


class ResumeResponse(BaseModel):
    content: str
    last_modified: str | None = None
    path: str = ""  # absolute, on the agent's machine -- for handing to an assistant


class ResumePreviewResponse(BaseModel):
    files: list[PendingFile]


@api.get("/resume", response_model=ResumeResponse)
async def get_resume():
    path = hub_folder("resume") / "resume.md"
    if not path.exists():
        raise HTTPException(status_code=404, detail="resume/resume.md not found in the hub")
    content = path.read_text(encoding="utf-8-sig", errors="replace")
    last_modified = None
    try:
        # Local, like every other time the product shows (it was UTC, unlabelled,
        # seven hours ahead on the Resume page).
        last_modified = local_stamp(path.stat().st_mtime)
    except OSError:
        pass
    return ResumeResponse(content=content, last_modified=last_modified, path=str(path.resolve()))


@api.get("/resume-preview", response_model=ResumePreviewResponse)
async def get_resume_preview():
    data = await run_cli_json("UpdateResume", ["-Preview"])
    return ResumePreviewResponse(files=[PendingFile(**f) for f in data.get("files", [])])
