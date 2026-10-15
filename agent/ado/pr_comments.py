"""PR review comments -- the side record of a card under review.

``GetPRComments`` writes review threads into the prompt file; these routes read
them back. The parse is shared with ``Test-PRComments.ps1`` through the
fixtures.

``suggest`` is the one model-assisted route in this module: a draft reply to
one thread, through the provider profile in ``core/model.py`` (the model is
``ai.model`` in config, the key is in the environment). With no key or no SDK
it declines before anything is built -- a typed 412 whose detail says what is
missing, the same answer ``/env``'s ``anthropicConfigured`` gives in advance --
and the prompt it sends is ``agentic/pr-suggest.prompt.md``, a file a person
can edit and fork, not an f-string here. The PR Comments page calls it from
the reply box of an open thread.

This module writes NO card. The reply a person posts goes through the bridge
as ``ReplyPR``, which posts to the tracker and fills the card's ``Reply:``
slot through ``Write-CardText`` -- one writer, the CLI's. The native ``save``
route that used to do the same from Python was retired as the second
writer it was.
"""

import json
import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core import log_writer, model
from ..core.config import AGENTIC_DIR, PROMPT_SUFFIX, resolve_dirs
from ..core.consts import token_pr_review_heading

api = APIRouter()


# ---------------------------------------------------------------------------
class PRCommentItem(BaseModel):
    number: int
    thread_id: int
    file_path: str
    line: int | None = None
    published_date: str | None = None
    reviewer: str
    severity: str
    category: str
    status: str
    comment_text: str
    code_suggestion: str
    decision: str
    reply: str
    is_open: bool


class PRCommentSummary(BaseModel):
    file: str
    title: str
    pr_id: int
    open_count: int
    total_count: int


class PRCommentsListResponse(BaseModel):
    count: int
    items: list[PRCommentSummary]


class PRCommentsDetailResponse(BaseModel):
    file: str
    title: str
    pr_id: int
    round_num: int
    open_count: int
    total_count: int
    comments: list[PRCommentItem]


class SuggestRequest(BaseModel):
    thread_id: int
    comment_text: str
    file_path: str
    line: int | None = None
    reviewer: str
    code_suggestion: str


class SuggestResponse(BaseModel):
    recommendation: str
    confidence: str
    draft_reply: str


# ---------------------------------------------------------------------------
# PR Comment Review — helpers
# ---------------------------------------------------------------------------
_OPEN_DECISION = "take / reject / modify"


def _parse_pr_comments(content: str) -> tuple[int, int, list[dict]]:
    """Parse all PR Review Comment blocks from a prompt file.
    Returns (pr_id, round_num, comments_list).
    """
    # Find PR ID and highest round from all section headers
    pr_id = 0
    round_num = 1
    # The heading is the contract (consts.json); the round and PR-id suffix
    # after it are this half's own reading of the CLI's section.
    header = re.escape(token_pr_review_heading()) + r"(?:\s*--\s*Round\s*(\d+))?\s*\(PR\s*(\d+)\)"
    for m in re.finditer(header, content):
        pr_id = int(m.group(2))
        if m.group(1):
            round_num = int(m.group(1))

    if not pr_id:
        return 0, 1, []

    # Split on each ### Comment header
    blocks = re.split(r"(?=### Comment \d+ \(Thread \d+\))", content)
    comments: list[dict] = []

    for block in blocks:
        header_m = re.match(r"### Comment (\d+) \(Thread (\d+)\)", block)
        if not header_m:
            continue

        number = int(header_m.group(1))
        thread_id = int(header_m.group(2))

        file_path = ""
        line = None
        lm = re.search(r"^Line: `([^`]+)` L(\S+)", block, re.MULTILINE)
        if lm:
            file_path = lm.group(1)
            try:
                line = int(re.sub(r"\D.*", "", lm.group(2)))
            except ValueError:
                line = None

        reviewer = ""
        severity = ""
        category = ""
        rm = re.search(r"^Reviewer/Bot: (.+)", block, re.MULTILINE)
        if rm:
            reviewer_line = rm.group(1).strip()
            reviewer = re.sub(r"\s*--\s*.*", "", reviewer_line).strip()
            sm = re.search(r"-- Severity: ([^-\n]+)", reviewer_line)
            if sm:
                severity = sm.group(1).strip()
            cm = re.search(r"-- Category: ([^-\n]+)", reviewer_line)
            if cm:
                category = cm.group(1).strip()

        published_date = None
        pdm = re.search(r"^Published: (.+)", block, re.MULTILINE)
        if pdm:
            published_date = pdm.group(1).strip()

        status = ""
        stm = re.search(r"^Status: (.+)", block, re.MULTILINE)
        if stm:
            status = stm.group(1).strip()

        comment_text = ""
        ctm = re.search(r"^Comment: (.+)", block, re.MULTILINE)
        if ctm:
            comment_text = ctm.group(1).strip()

        code_suggestion = ""
        # Try to find "Code suggestion:\n```\n...\n```"
        csm = re.search(r"^Code suggestion:\s*\n```[^\n]*\n(.*?)\n```", block, re.MULTILINE | re.DOTALL)
        if csm:
            code_suggestion = csm.group(1).strip()

        decision = _OPEN_DECISION
        dm = re.search(r"^Decision: (.+)", block, re.MULTILINE)
        if dm:
            decision = dm.group(1).strip()

        reply = ""
        rpm = re.search(r"^Reply: (.*)", block, re.MULTILINE)
        if rpm:
            reply = rpm.group(1).strip()

        is_open = (decision == _OPEN_DECISION) or (not reply)

        comments.append(
            {
                "number": number,
                "thread_id": thread_id,
                "file_path": file_path,
                "line": line,
                "published_date": published_date,
                "reviewer": reviewer,
                "severity": severity,
                "category": category,
                "status": status,
                "comment_text": comment_text,
                "code_suggestion": code_suggestion,
                "decision": decision,
                "reply": reply,
                "is_open": is_open,
            }
        )

    return pr_id, round_num, comments


def _get_prompt_title(content: str) -> str:
    m = re.search(r"(?m)^#\s+(.+)", content)
    if not m:
        return ""
    title = m.group(1).strip()
    title = re.sub(r"^[\U00002600-\U0001FFFF]\s*", "", title)
    if len(title) > 80:
        title = title[:77] + "..."
    return title


# The prompt behind suggest: frontmatter and prose for a person above the
# fence, the instruction below it -- the same shape agentic/pr-review.prompt.md
# has for AddPRReview, read the same way Scripts/Invoke-PRReview.ps1 reads that
# one (Get-P20PromptInstruction in Scripts/Resolve-AgenticPrompt.ps1).
SUGGEST_PROMPT_PATH = AGENTIC_DIR / f"pr-suggest{PROMPT_SUFFIX}"
_PROMPT_FENCE = "\n---\n"


def prompt_instruction(text: str) -> str:
    """The part of a tool-sent prompt file that goes to the model: everything
    below the first ``---`` line that follows the frontmatter. A file with no
    frontmatter fences on its first ``---`` line; a file with no fence is sent
    whole. Either line ending reads the same."""
    text = (text or "").replace("\r\n", "\n")
    start = 0
    if text.startswith("---\n"):
        close = text.find(_PROMPT_FENCE, 3)
        if close != -1:
            start = close + len(_PROMPT_FENCE)
    fence = text.find(_PROMPT_FENCE, max(start - 1, 0))
    return text[fence + len(_PROMPT_FENCE) :] if fence != -1 else text[start:]

# The decline, in words a person can act on. 412: the route exists and the
# request was fine; a precondition on this machine is not met. The sentences
# are the profile's (core/model.py), so /rewrite says the same thing.
NO_MODEL_KEY_STATUS = 412
NO_MODEL_KEY_DETAIL = model.NO_MODEL_KEY_DETAIL

_SUGGEST_SYSTEM = "You are a concise code review assistant."


def _suggest_prompt(req: "SuggestRequest") -> str:
    """The prompt file's instruction, with the thread's fields in place.

    Replaced by name rather than ``str.format`` because the instruction ends in
    a JSON object whose braces are its own.
    """
    body = prompt_instruction(SUGGEST_PROMPT_PATH.read_text(encoding="utf-8"))
    fields = {
        "{file_path}": req.file_path or "unknown",
        "{line}": str(req.line) if req.line is not None else "unknown",
        "{reviewer}": req.reviewer or "unknown",
        "{comment_text}": req.comment_text,
        "{code_suggestion}": req.code_suggestion or "none",
    }
    for key, value in fields.items():
        body = body.replace(key, value)
    return body.strip()


# ---------------------------------------------------------------------------
# GET /api/pr-comments — list current/ files with open PR comments
# ---------------------------------------------------------------------------
@api.get("/pr-comments", response_model=PRCommentsListResponse)
async def list_pr_comments():
    """The cards in ``current/`` with open review threads -- a file read, and
    nothing but a file read.

    It used to demand Tier 1 first on any org that was not ``local``, and answer
    ``count=0`` with no reason when the probe failed, so on an active org
    without ``az`` -- a laptop on a plane -- the card was empty while
    ``current/`` held the comments. The rounds were written by ``GetPRComments``
    at some earlier moment; whether ADO is reachable NOW says nothing about
    them. No probe, no tier, no ``az``: the route reads the same files at every
    tier.
    """
    current_dir, _ = resolve_dirs()
    if not current_dir.exists():
        return PRCommentsListResponse(count=0, items=[])

    items: list[PRCommentSummary] = []
    for f in sorted(current_dir.iterdir()):
        if not f.is_file() or not f.name.endswith(".prompt.md"):
            continue
        content = f.read_text(encoding="utf-8-sig", errors="replace")
        if token_pr_review_heading() not in content:
            continue
        pr_id, _, comments = _parse_pr_comments(content)
        if not comments:
            continue
        open_count = sum(1 for c in comments if c["is_open"])
        if open_count == 0:
            continue
        items.append(
            PRCommentSummary(
                file=f.name,
                title=_get_prompt_title(content),
                pr_id=pr_id,
                open_count=open_count,
                total_count=len(comments),
            )
        )

    log_writer.write_log("CMD", "agent/pr-comments/list", f"{len(items)} file(s) with open comments")
    return PRCommentsListResponse(count=len(items), items=items)


# ---------------------------------------------------------------------------
# GET /api/pr-comments/{filename} — full parsed comments for one file
# ---------------------------------------------------------------------------
@api.get("/pr-comments/{filename}", response_model=PRCommentsDetailResponse)
async def get_pr_comments(filename: str):
    # Reject path traversal
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    current_dir, archive_dir = resolve_dirs()
    f = current_dir / filename
    if not f.exists():
        # Fall back to archive/ — a triaged review still has viewable comments.
        f = archive_dir / filename
    if not f.exists():
        log_writer.write_log("WARN", "agent/pr-comments/detail", f"not found: {filename}")
        raise HTTPException(status_code=404, detail=f"{filename} not found")
    content = f.read_text(encoding="utf-8-sig", errors="replace")
    pr_id, round_num, comments = _parse_pr_comments(content)
    if not pr_id:
        log_writer.write_log("WARN", "agent/pr-comments/detail", f"no PR section in {filename}")
        raise HTTPException(status_code=404, detail=f"No {token_pr_review_heading()} section found")
    open_count = sum(1 for c in comments if c["is_open"])
    log_writer.write_log("CMD", "agent/pr-comments/detail", f"{filename} — {len(comments)} comments, {open_count} open")
    return PRCommentsDetailResponse(
        file=filename,
        title=_get_prompt_title(content),
        pr_id=pr_id,
        round_num=round_num,
        open_count=open_count,
        total_count=len(comments),
        comments=[PRCommentItem(**c) for c in comments],
    )


# ---------------------------------------------------------------------------
# POST /api/pr-comments/{filename}/suggest — AI recommendation for a comment
# ---------------------------------------------------------------------------
@api.post("/pr-comments/{filename}/suggest", response_model=SuggestResponse)
async def suggest_comment(filename: str, req: SuggestRequest):
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    prompt = _suggest_prompt(req)

    try:
        raw = await model.complete(prompt, system=_SUGGEST_SYSTEM, max_tokens=300)
    except model.ModelUnavailable as why:
        log_writer.write_log("WARN", "agent/pr-comments/suggest", str(why))
        raise HTTPException(status_code=NO_MODEL_KEY_STATUS, detail=str(why))

    try:
        # Strip any markdown fences if model ignores instructions
        raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw.strip(), flags=re.MULTILINE).strip()
        result = json.loads(raw)
        rec = str(result.get("recommendation", "")).strip()
        conf = str(result.get("confidence", "")).strip()
        log_writer.write_log("CMD", "agent/pr-comments/suggest", f"{filename} thread {req.thread_id} → {rec} ({conf})")
        return SuggestResponse(
            recommendation=rec,
            confidence=conf,
            draft_reply=str(result.get("draft_reply", "")).strip(),
        )
    except json.JSONDecodeError as e:
        log_writer.write_log("ERR", "agent/pr-comments/suggest", f"JSON parse error: {e}")
        raise HTTPException(status_code=502, detail=f"AI returned unparseable response: {e}")
    except Exception as e:  # noqa: BLE001 -- whatever the model call raised is the route's 502, logged
        log_writer.write_log("ERR", "agent/pr-comments/suggest", str(e)[:200])
        raise HTTPException(status_code=502, detail=str(e))
