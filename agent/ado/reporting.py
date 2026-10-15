"""Reporting over the archive -- /billing and the four /engagement routes.

Everything here reads files: the archive folder, the weekly-billing script's
JSON, and git history. No ADO call is made, so these routes work at Tier 2 and
are the reason a machine with no tracker still produces a usable record.

Two severings live in this file:

* ``Get-WeeklyBilling.ps1`` is invoked from the agent's own tree
  (``agent/ado/Get-WeeklyBilling.ps1``), not from inside the prompt store. The
  hub holds cards, not code.
* The per-org ``billing/`` folder is gone from the hub layout. Billed days are
  now derived from the ``**Closed:**`` stamp that archiving writes into every
  card (docs/CLI.md, "The two dates a card carries, and the cards that never got them");
  with no archive folder, the summary's billed days are simply zero.

Two routes were retired -- ``/engagement/{slug}/activity`` and
``/engagement/{slug}/billing-timeline``. Nothing in ``web/src`` requested
either: the components that drew them (``ActivityHeatmap``, ``BillingTimeline``)
were deliberately not carried at the wasteland split, and the deck that
prefetched the timeline left with it. They are on the deliberately-absent list
in ``app.py`` and ``agent/README.md``.
"""

import asyncio
import re
import subprocess
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core import log_writer
from ..core.config import BILLING_SCRIPT, hub_folder, hub_root, load_config
from ..core.consts import (
    folder_archive,
    re_closed_stamp_date,
    review_file_name,
    review_slug_separator,
)
from ..core.hosts import NO_HOST_ERROR, host_argv

api = APIRouter()

# What Get-WeeklyBilling.ps1 reads as "the hub root" for -PromptsFolder: the
# script and this file are one half's, and the script names the same value.
BILLING_HUB_ROOT_FOLDER = "."

# ---------------------------------------------------------------------------


class BillingItem(BaseModel):
    id: str
    type: str
    title: str
    status: str


class BillingDay(BaseModel):
    date: str
    day_name: str
    items: list[BillingItem]
    raw: str  # paste-ready text for this day
    compact_raw: str = ""  # compact paste-ready text for this day


class BillingResponse(BaseModel):
    days: list[BillingDay]
    raw: str  # full paste-ready text
    compact: str = ""  # compact paste-ready text (one line per status group)
    # What the week was built from, so the reader knows what they are looking at:
    # "stamps" (the cards' own dates -- works on a hub with no git) or
    # "stamps+git" (the same, plus the days git says a card was touched).
    source: str = ""
    # Cards left OFF the timesheet because they say `**Billable:** no`.
    nonBillable: int = 0
    # Cards with no date on them at all: counted, never guessed.
    unstamped: int = 0
    # Set ONLY when the week could not be built: no script, no PowerShell, a
    # timeout, a script that failed. `days` is empty then too, and an empty week
    # and a broken one are different facts to someone filling in a timesheet --
    # so the page reads this field, not the emptiness.
    error: str = ""


def _ascii_safe(text: str) -> str:
    """Normalize non-ASCII characters for billing output."""
    text = re.sub(r"[\u2018\u2019\u0060\u00B4]", "'", text)
    text = re.sub(r"[\u201C\u201D]", '"', text)
    text = re.sub(r"[\u2013\u2014]", "--", text)
    text = re.sub(r"\u2026", "...", text)
    text = re.sub(r"[\u00C6\u00E6]", "ae", text)
    text = re.sub(r"[\u00D4\u00F4]", "o", text)
    text = re.sub(r"[^\x20-\x7E]", "", text)
    return text


# There is deliberately NO server-side cache here. Once, "last week"
# was kept in memory for the life of the process, on the theory that a finished
# week cannot change. It can: a card closed on Friday is marked `**Billable:** no`
# on Monday, and the timesheet someone is about to copy has to say so. The cache
# that belongs to this route is the browser's -- RTK Query, dropped by the
# `Billing` tag whenever a card is archived or its Billable line changes.


def _billing_failure(sentence: str) -> BillingResponse:
    """One shape for every way the week can fail to be built. `raw` keeps the
    sentence too, for a caller that only ever read `raw`."""
    return BillingResponse(days=[], raw=sentence, error=sentence)


@api.get("/billing", response_model=BillingResponse)
async def get_billing(week: str = "current"):
    """Delegate to Get-WeeklyBilling.ps1 -AsJson (single source of truth)."""
    import json as _json

    if not BILLING_SCRIPT.exists():
        return _billing_failure("Billing script not found.")
    # Same resolver the bridge uses: this is the other place the agent starts a
    # PowerShell, and a second hardcoded `pwsh` here would be the same defect
    # in a second file.
    # The folder is passed, not left for the script to work out again: the agent
    # has already resolved the active Space, and one resolution cannot disagree with
    # itself. (It could, and did -- the script re-read the package's config files,
    # so a test that pointed the agent at a scratch config passed or failed by
    # whichever org the developer had selected in their own UI.)
    args = host_argv(str(BILLING_SCRIPT), "-PromptsRoot", str(hub_root()), "-AsJson")
    if args is None:
        return _billing_failure(NO_HOST_ERROR)
    # ALWAYS, and "." for a Space whose cards sit at the hub root: Windows
    # PowerShell 5.1 drops an empty argv entry, and the switch after it would then
    # be read as this parameter's value. The root case used to be left to the
    # script, which resolved the Space again from the package's files and could
    # answer a different folder (an activeSpace nobody declares is this agent's
    # first Space and was the script's hub root). The script now refuses without it.
    folder = str(load_config().get("promptsFolder", "") or "")
    args += ["-PromptsFolder", folder or BILLING_HUB_ROOT_FOLDER]
    if week == "last":
        args.append("-LastWeek")

    try:
        result = await asyncio.to_thread(
            subprocess.run,
            args,
            capture_output=True,
            text=True,
            timeout=90,
        )
        if result.returncode != 0:
            stderr = result.stderr.strip() if result.stderr else "unknown error"
            return _billing_failure(f"Billing script failed: {stderr}")

        if not result.stdout.strip():
            # The script writes nothing when it has no hub to read. Say that,
            # rather than reporting a parse failure on an empty string.
            stderr = result.stderr.strip() if result.stderr else ""
            reason = stderr or "promptsRoot is not configured or does not exist"
            return _billing_failure(f"No billing data: {reason}")

        data = _json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        return _billing_failure("Billing script timed out.")
    except (FileNotFoundError, _json.JSONDecodeError) as exc:
        return _billing_failure(f"Billing error: {exc}")

    days = []
    for d in data.get("days", []):
        items = [
            BillingItem(id=i["id"], type=i["type"], title=i["title"], status=i["status"]) for i in d.get("items", [])
        ]
        days.append(
            BillingDay(
                date=d["date"],
                day_name=d["day_name"],
                items=items,
                raw=d.get("raw", ""),
                compact_raw=d.get("compact_raw", ""),
            )
        )

    response = BillingResponse(
        days=days,
        raw=data.get("raw", ""),
        compact=data.get("compact", ""),
        source=data.get("source", ""),
        nonBillable=int(data.get("nonBillable", 0) or 0),
        unstamped=int(data.get("unstamped", 0) or 0),
    )

    return response


# GET /api/engagement/{slug}/summary   — Phase 1 archive card
# GET /api/engagement/{slug}/reviews   — Phase 1 archive card
# All endpoints read only from files; zero ADO calls.
# ---------------------------------------------------------------------------


class EngagementStats(BaseModel):
    daysBilled: int
    prsReviewed: int
    workItemsClosed: int
    reviewsGenerated: int


class EngagementSummaryResponse(BaseModel):
    client: str
    role: str
    startDate: str | None = None
    endDate: str | None = None
    totalDays: int
    projects: list[dict]
    stats: EngagementStats


class EngagementReviewItem(BaseModel):
    period: str
    generatedDate: str
    artifactsScanned: int
    link: str
    summary: str
    tags: list[str] = []
    spaces: list[str] = []  # member Space slugs, sorted ascending; ≥1 entry


def _engagement_org_config(slug: str) -> dict | None:
    """Return the org entry from config for the given slug, or None."""
    cfg = load_config()
    for o in cfg.get("spaces", []):
        if o.get("slug") == slug:
            return o
    return None


def _count_archive_items(org_config: dict) -> int:
    """Count archived prompt files for an org (used as workItemsClosed proxy)."""
    folder = org_config.get("promptsFolder", "")
    if folder:
        archive_dir = hub_root() / folder / folder_archive()
    else:
        archive_dir = hub_root() / folder_archive()
    if not archive_dir.exists():
        return 0
    return sum(1 for f in archive_dir.iterdir() if f.is_file() and f.name.endswith(".prompt.md"))


# ---------------------------------------------------------------------------
# reviews/ is a hub-root sibling owned by the growth spec; the engagement cards
# only count and title what is there, and an absent folder reads as zero.
# ---------------------------------------------------------------------------
def _slug_set_from_path(review_md: Path) -> list[str]:
    """Derive the slug-set for a review from its path under reviews/.

    reviews/globex/2026/...      → ["globex"]
    reviews/demo+globex/2026/... → ["demo", "globex"]
    reviews/2026/... (legacy)    → [] (no slug segment; caller uses frontmatter)

    The top-level child of reviews/ is the slug-set segment.  We detect whether
    it is a slug-set segment by checking it does NOT look like a YYYY year dir.
    """
    reviews_dir = hub_folder("reviews")
    try:
        rel = review_md.relative_to(reviews_dir)
    except ValueError:
        return []
    parts = rel.parts
    # parts[0] is the immediate child of reviews/; if it looks like a 4-digit
    # year it is a legacy review with no slug segment.
    if not parts or re.fullmatch(r"\d{4}", parts[0]):
        return []
    return sorted(parts[0].split(review_slug_separator()))


def _slug_set_from_frontmatter(review_md: Path) -> list[str]:
    """Read orgs: list or legacy org: scalar from a review file's frontmatter."""
    try:
        with review_md.open(encoding="utf-8-sig", errors="replace") as f:
            content = f.read(2000)
        m = re.match(r"---\r?\n(.+?)\r?\n---", content, re.DOTALL)
        if not m:
            return []
        fm_text = m.group(1)
        # orgs: [demo, globex]  or  orgs:\n  - demo\n  - globex
        orgs_list_m = re.search(r"^orgs:\s*\[([^\]]+)\]", fm_text, re.MULTILINE)
        if orgs_list_m:
            return sorted(s.strip() for s in orgs_list_m.group(1).split(",") if s.strip())
        # scalar legacy: org: globex
        org_m = re.search(r"^org:\s*(\S+)", fm_text, re.MULTILINE)
        if org_m:
            return [org_m.group(1).strip()]
    except OSError:  # an unreadable review names no orgs
        pass
    return []


def _scan_reviews(slug: str | None = None) -> list[tuple[str, str, str, str, Path, list[str]]]:
    """Return (folder, start, end, title, path, orgs) tuples sorted newest-first.

    Membership rule: a review folder belongs to slug S iff
    S is a member of that folder's slug-set.  The slug-set is derived by
    splitting the top-level reviews/ child directory name on '+'.  This is
    SET-CONTAINS, not substring — 'demo' does NOT match 'democorp'.

    A combined folder reviews/demo+globex/ surfaces under _scan_reviews("demo")
    AND _scan_reviews("globex"), but NOT under _scan_reviews("acme").

    Legacy reviews sitting directly under reviews/ (no slug segment) fall back
    to frontmatter orgs:/org: for their slug-set.
    """
    reviews_dir = hub_folder("reviews")
    if not reviews_dir.exists():
        return []
    results = []
    for review_md in sorted(reviews_dir.rglob(review_file_name()), reverse=True):
        folder_name = review_md.parent.name
        m = re.match(r"(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})", folder_name)
        if not m:
            continue
        start, end = m.group(1), m.group(2)

        # Derive slug-set for membership filtering
        path_slugs = _slug_set_from_path(review_md)
        if path_slugs:
            review_spaces = path_slugs
        else:
            # Legacy review directly under reviews/ — use frontmatter
            review_spaces = _slug_set_from_frontmatter(review_md)

        # Filter by requested slug using set-contains (not substring)
        if slug is not None and slug not in review_spaces:
            continue

        title = folder_name
        try:
            with review_md.open(encoding="utf-8-sig", errors="replace") as f:
                for line in f:
                    tm = re.match(r"^#\s+(.+)", line)
                    if tm:
                        title = tm.group(1).strip()
                        break
        except OSError:  # an unreadable review keeps its folder name as the title
            pass
        results.append((folder_name, start, end, title, review_md, review_spaces))
    return results


def _count_org_reviews(slug: str | None) -> tuple[int, list[dict]]:
    """Return (count, review_items) for the given org slug.

    slug=None (or "all") returns every review across all orgs — used by the
    Reviews collection's "All" filter so it can surface reviews for orgs other
    than the active one (e.g. a demo-only review while another org is active).
    """
    scan_slug = None if slug in (None, "all") else slug
    items = []
    for folder, start, end, title, path, review_spaces in _scan_reviews(slug=scan_slug):
        try:
            mtime = path.stat().st_mtime
            gen_date = time.strftime("%Y-%m-%d", time.localtime(mtime))
        except OSError:
            gen_date = end

        # Extract artifacts_scanned from review body if present
        # An unreadable review still lists, with no count, summary or tags -- and
        # never with the PREVIOUS review's text, which the old blind excepts let through.
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            text = ""
        artifacts = 0
        m = re.search(r"Total work items[^\d]*(\d+)", text)
        if m:
            artifacts = int(m.group(1))

        # First non-heading paragraph as summary (up to 200 chars)
        summary = ""
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith(("#", "|", "-")):
                summary = line[:200]
                break

        # Extract skill tags from review text using the same allowlist as _build_skills
        tags: list[str] = []
        text_lower = text.lower()
        for tokens_list in _SKILLS_ALLOWLIST.values():
            for token in tokens_list:
                if token.lower() in text_lower and token not in tags:
                    tags.append(token)

        items.append(
            {
                "period": f"{start} – {end}",
                "generatedDate": gen_date,
                "artifactsScanned": artifacts,
                "link": f"/reviews/{folder}",
                "summary": summary,
                "tags": tags,
                "spaces": sorted(review_spaces) if review_spaces else ([scan_slug] if scan_slug else []),
            }
        )
    return len(items), items


def _org_archive_dir(org_config: dict) -> Path:
    folder = org_config.get("promptsFolder", "")
    archive = folder_archive()
    return hub_root() / folder / archive if folder else hub_root() / archive


def _infer_work_type(text: str, filename: str) -> str:
    """Infer work item type from YAML frontmatter or heading.

    Spec says read frontmatter `type:` first; archive files predate that pattern
    so fall back to the first heading line (# Bug / # User Story / # Feature).
    """
    for line in text.splitlines()[:30]:
        m = re.match(r"^type:\s*(\S+)", line, re.IGNORECASE)
        if m:
            t = m.group(1).lower().rstrip("\"'")
            if t in ("bug", "story", "feature", "task"):
                return t
    for line in text.splitlines()[:5]:
        low = line.lower().lstrip("# ").lstrip("﻿")
        if low.startswith(("bug ", "bug:")):
            return "bug"
        if low.startswith(("user story ", "user story:")):
            return "story"
        if low.startswith(("feature ", "feature:")):
            return "feature"
    return "task"


def _extract_sprint(text: str) -> str:
    """Extract sprint label from prompt file content."""
    m = re.search(r"sprint[:\s]+sprint\s+(\d+)", text, re.IGNORECASE)
    if m:
        return f"Sprint {m.group(1)}"
    m = re.search(r"\bsprint[:\s]+(\d+)\b", text, re.IGNORECASE)
    if m:
        return f"Sprint {m.group(1)}"
    return ""


# ---------------------------------------------------------------------------
# Phase 2 — Work Breakdown
# ---------------------------------------------------------------------------


class WorkBreakdownByType(BaseModel):
    bug: int
    story: int
    feature: int
    task: int
    prReviews: int


class WorkBreakdownSprintEntry(BaseModel):
    sprint: str
    bug: int
    story: int
    feature: int
    task: int


class WorkBreakdownResponse(BaseModel):
    byType: WorkBreakdownByType
    bySprint: list[WorkBreakdownSprintEntry]


def _build_work_breakdown(archive_dir: Path) -> WorkBreakdownResponse:
    counts: dict[str, int] = {"bug": 0, "story": 0, "feature": 0, "task": 0}
    sprint_map: dict[str, dict[str, int]] = {}

    if archive_dir.exists():
        for f in archive_dir.iterdir():
            if not (f.is_file() and f.name.endswith(".prompt.md")):
                continue
            try:
                text = f.read_text(encoding="utf-8-sig", errors="replace")
            except OSError:  # an unreadable card is not counted
                continue
            wtype = _infer_work_type(text, f.name)
            if wtype not in counts:
                log_writer.write_log("WARN", "agent/engagement", f"{f.name}: unknown type '{wtype}' — counting as task")
                wtype = "task"
            counts[wtype] += 1
            sprint = _extract_sprint(text) or "Unsorted"
            if sprint not in sprint_map:
                sprint_map[sprint] = {"bug": 0, "story": 0, "feature": 0, "task": 0}
            sprint_map[sprint][wtype] += 1

    # Sort sprints: numeric sprints first (ascending), then "Unsorted"
    def sprint_sort_key(s: str) -> tuple:
        m = re.search(r"(\d+)", s)
        return (0, int(m.group(1))) if m else (1, 0)

    by_sprint = [WorkBreakdownSprintEntry(sprint=s, **sprint_map[s]) for s in sorted(sprint_map, key=sprint_sort_key)]

    return WorkBreakdownResponse(
        byType=WorkBreakdownByType(**counts, prReviews=0),
        bySprint=by_sprint,
    )


@api.get("/engagement/{slug}/work-breakdown", response_model=WorkBreakdownResponse)
async def get_engagement_work_breakdown(slug: str):
    org = _engagement_org_config(slug)
    if org is None:
        raise HTTPException(status_code=404, detail=f"Unknown Space slug: {slug}")
    archive_dir = _org_archive_dir(org)
    return await asyncio.to_thread(_build_work_breakdown, archive_dir)


# ---------------------------------------------------------------------------
# Phase 2 — Activity Heatmap
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The archive's close stamps -- what the summary's billed days are read from
# ---------------------------------------------------------------------------


def _closed_dates(org_config: dict) -> list[str]:
    """Every distinct "**Closed:** yyyy-mm-dd" stamp in the org's archive.

    Archiving writes that stamp into the card, which makes the archive
    itself the billing record -- the separate per-org ``billing/`` folder the
    package this was carved from read is not part of the hub layout any more.
    An absent archive is not an error; it is an empty record.
    """
    archive_dir = _org_archive_dir(org_config)
    if not archive_dir.exists():
        return []
    dates: set[str] = set()
    for f in sorted(archive_dir.iterdir()):
        if not f.is_file() or not f.name.endswith(".md"):
            continue
        try:
            text = f.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
        # The stamp is the contract (consts.json); the date shape after it is
        # this half's own -- see consts.re_closed_stamp_date.
        m = re_closed_stamp_date().search(text)
        if m:
            dates.add(m.group(1))
    return sorted(dates)


# ---------------------------------------------------------------------------
# Phase 2 — Skills Snapshot
# ---------------------------------------------------------------------------

# Maintained allowlist — tokens matched case-insensitively against review text.
# Add entries here when a new technology appears in a review; keep it traceable.
_SKILLS_ALLOWLIST: dict[str, list[str]] = {
    "Languages": ["TypeScript", "JavaScript", "Python", "PowerShell", "CSS", "HTML", "SCSS"],
    "Frameworks": [
        "React",
        "Fluent UI",
        "FluentUI",
        "RTK Query",
        "Redux",
        "Vite",
        "Jest",
        "recharts",
        "FastAPI",
        "uvicorn",
        "Playwright",
    ],
    "Domains": [
        "A11y",
        "Accessibility",
        "WCAG",
        "Screen Reader",
        "VoiceOver",
        "Narrator",
        "PLG",
        "Billing",
        "Auth",
        "Telemetry",
    ],
    "Tools": ["ADO", "Azure DevOps", "GitHub", "VS Code", "Figma", "pnpm", "npm"],
    "A11y": [
        "aria-label",
        "aria-hidden",
        "focus order",
        "keyboard navigation",
        "high contrast",
        "HCL",
        "color contrast",
        "alt text",
    ],
    "Auth": ["MSAL", "OAuth", "SSO", "JWT", "token"],
    "Patterns": ["RTK", "custom hook", "compound component", "lazy load", "Suspense", "feature flag", "flight flag"],
}


def _build_skills(archive_dir: Path, reviews_slug: str) -> dict:
    """Collect skills from area: frontmatter and allowlist matches in review text."""
    found: dict[str, set[str]] = {g: set() for g in _SKILLS_ALLOWLIST}

    # Source 1: area: frontmatter on archive files
    area_map = {
        "a11y": "A11y",
        "auth": "Auth",
        "plg": "Domains",
        "telemetry": "Domains",
        "billing": "Domains",
    }
    if archive_dir.exists():
        for f in archive_dir.iterdir():
            if not (f.is_file() and f.name.endswith(".prompt.md")):
                continue
            try:
                for line in f.read_text(encoding="utf-8-sig", errors="replace").splitlines()[:20]:
                    m = re.match(r"^area:\s*(.+)", line, re.IGNORECASE)
                    if m:
                        tag = m.group(1).strip().lower()
                        group = area_map.get(tag, "Domains")
                        found[group].add(m.group(1).strip())
            except OSError:  # an unreadable card names no area
                continue

    # Source 2: allowlist tokens in review text
    review_text = ""
    for _, _, _, _, path, _ in _scan_reviews(slug=reviews_slug):
        try:
            review_text += path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:  # an unreadable review adds no tokens
            pass

    for group, tokens_list in _SKILLS_ALLOWLIST.items():
        for token in tokens_list:
            if re.search(re.escape(token), review_text, re.IGNORECASE):
                found[group].add(token)

    return {g: sorted(found[g]) for g in _SKILLS_ALLOWLIST}


class SkillGroups(BaseModel):
    Languages: list[str]
    Frameworks: list[str]
    Domains: list[str]
    Tools: list[str]
    A11y: list[str]
    Auth: list[str]
    Patterns: list[str]


class SkillsSnapshotResponse(BaseModel):
    groups: SkillGroups


@api.get("/engagement/{slug}/skills", response_model=SkillsSnapshotResponse)
async def get_engagement_skills(slug: str):
    org = _engagement_org_config(slug)
    if org is None:
        raise HTTPException(status_code=404, detail=f"Unknown Space slug: {slug}")
    archive_dir = _org_archive_dir(org)
    groups = await asyncio.to_thread(_build_skills, archive_dir, slug)
    return SkillsSnapshotResponse(groups=SkillGroups(**groups))


def _count_pr_comments(org_config: dict) -> int:
    """Count peer reviews recorded in <org>/pr-comments/ -- files prefixed 'reviewed-'."""
    folder = org_config.get("promptsFolder", "")
    pr_dir = (hub_root() / folder / "pr-comments") if folder else (hub_root() / "pr-comments")
    if not pr_dir.exists():
        return 0
    return sum(1 for f in pr_dir.iterdir() if f.is_file() and f.name.startswith("reviewed-"))


def _read_billing_data(org_config: dict) -> tuple[str | None, str | None, int]:
    """Return (startDate, endDate, daysBilled) from the archive's close stamps."""
    all_dates = _closed_dates(org_config)
    if not all_dates:
        return None, None, 0
    return all_dates[0], all_dates[-1], len(all_dates)


@api.get("/engagement/{slug}/summary", response_model=EngagementSummaryResponse)
async def get_engagement_summary(slug: str):
    org = _engagement_org_config(slug)
    if org is None:
        raise HTTPException(status_code=404, detail=f"Unknown Space slug: {slug}")

    review_count, _ = _count_org_reviews(slug)
    closed_count = _count_archive_items(org)
    start_date, end_date, days_billed = _read_billing_data(org)
    prs_reviewed = _count_pr_comments(org)

    return EngagementSummaryResponse(
        client=org.get("name", slug),
        role=org.get("role", ""),
        startDate=start_date,
        endDate=end_date,
        totalDays=days_billed,
        projects=org.get("projects", []),
        stats=EngagementStats(
            daysBilled=days_billed,
            prsReviewed=prs_reviewed,
            workItemsClosed=closed_count,
            reviewsGenerated=review_count,
        ),
    )


@api.get("/engagement/{slug}/reviews", response_model=list[EngagementReviewItem])
async def get_engagement_reviews(slug: str):
    # "all" is a cross-org view, not a real org — skip the org-config check.
    if slug != "all":
        org = _engagement_org_config(slug)
        if org is None:
            raise HTTPException(status_code=404, detail=f"Unknown Space slug: {slug}")
    _, items = _count_org_reviews(slug)
    return [EngagementReviewItem(**item) for item in items]
