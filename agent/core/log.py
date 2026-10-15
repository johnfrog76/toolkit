"""Log routes: /log, /log-entries, /test-history.

All three read or write files that live beside this package at the repository
root -- ``usage.{machine}.log``, ``test-results.{machine}.log`` and
``test-summary.{machine}.json`` -- the same files the PowerShell CLI writes.
The summary covers the machine's three halves: each suite entry carries a
``half`` (``cli``, ``agent``, ``web``; an entry written before halves existed is
the CLI's), and a ``halves`` block holds one record per half -- its counts, its
seconds, and for a half ``{cliPrefix}Test`` could not run, the reason.
They are a property of the tool, not of the prompt store, so none of them is
resolved through the hub. ``usage.*.log`` alone can be moved, by
``P20_USAGE_LOG_DIR`` -- the override a test run sets so it does not write into
the engineer's own history.
"""

import json
import os
import socket

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from . import consts, log_writer
from .config import REPO_ROOT, load_config

api = APIRouter()


class LogRequest(BaseModel):
    log_type: str = Field(pattern=r"^(CMD|ERR|WARN|INFO)$")
    source: str
    detail: str


# POST /api/log — direct import of log_writer.py
# ---------------------------------------------------------------------------
@api.post("/log")
async def write_log(req: LogRequest):
    try:
        log_writer.write_log(req.log_type, req.source, req.detail)
        return {"status": "ok"}
    except Exception as e:  # noqa: BLE001 -- a write that failed is the route's 500, with its message
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# GET /api/log-entries — read usage.*.log files natively
# ---------------------------------------------------------------------------
class LogEntry(BaseModel):
    timestamp: str
    type: str
    machine: str
    source: str
    detail: str


class LogEntriesResponse(BaseModel):
    count: int
    entries: list[LogEntry]


@api.get("/log-entries", response_model=LogEntriesResponse)
async def get_log_entries(
    count: int = 500,
    type_filter: str | None = None,
    errors_only: bool = False,
):
    # Read from wherever the writer writes -- the repo root, or what
    # P20_USAGE_LOG_DIR names (see log_writer.log_dir).
    log_files = sorted(log_writer.log_dir().glob("usage.*.log"))
    raw_lines: list[str] = []
    for lf in log_files:
        try:
            raw_lines.extend(lf.read_text(encoding="utf-8-sig", errors="replace").splitlines())
        except OSError:  # a log file that cannot be read adds no lines
            pass

    raw_lines.sort()  # timestamp is first field, lexicographic sort works

    entries: list[LogEntry] = []
    for line in raw_lines:
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        entry_type = parts[1].strip()
        if errors_only and entry_type != "ERR":
            continue
        if type_filter and entry_type != type_filter.upper():
            continue
        entries.append(
            LogEntry(
                timestamp=parts[0].strip(),
                type=entry_type,
                machine=parts[2].strip(),
                source=parts[3].strip(),
                detail=parts[4].strip(),
            )
        )

    # Most recent first, capped at count
    entries = entries[-count:][::-1]
    return LogEntriesResponse(count=len(entries), entries=entries)


# ---------------------------------------------------------------------------
# GET /api/test-history — test results with latest-per-suite-per-day aggregation
# ---------------------------------------------------------------------------

HISTORY_DAYS = 14


# The three halves a test run covers, in the order ``{cliPrefix}Test`` runs them,
# and what a suite entry with no ``half`` is read as -- consts.json ``tests``,
# which Scripts/TestAll-Rules.ps1 and the Health card read too.
TEST_HALVES = consts.test_halves()
DEFAULT_HALF = consts.test_legacy_half()


class SuiteResult(BaseModel):
    suite: str
    result: str  # pass | fail | warn
    passed: int
    total: int
    detail: str
    description: str = ""
    half: str = DEFAULT_HALF


class HalfResult(BaseModel):
    """One half's record from the last run that touched it. ``result`` is
    pass | fail | skip; a skip carries its ``reason`` and no counts."""

    half: str
    result: str
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    total: int = 0
    seconds: float = 0
    reason: str = ""
    timestamp: str = ""


class TestDay(BaseModel):
    date: str
    passed: int
    total: int
    suites: list[SuiteResult]


class TestSummaryMachine(BaseModel):
    machine: str
    timestamp: str
    suites: dict[str, SuiteResult]
    halves: dict[str, HalfResult] = {}


class TestHistoryResponse(BaseModel):
    machine: str  # local machine name
    active_space: str  # org context the shown org-scoped results ran under
    days: list[TestDay]
    last_run: str | None
    streak: int  # consecutive clean days (most recent backward)
    machines: list[TestSummaryMachine]


def _parse_test_log() -> list[dict]:
    """Parse the local test-results.{machine}.log into a list of dicts."""
    machine = os.environ.get("COMPUTERNAME") or socket.gethostname().split(".")[0]
    log_path = REPO_ROOT / f"test-results.{machine}.log"
    if not log_path.exists():
        return []

    entries = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue  # skip malformed lines
        try:
            entries.append(
                {
                    "timestamp": parts[0],
                    "date": parts[0][:10],  # yyyy-mm-dd
                    "suite": parts[1],
                    "result": parts[2],
                    "passed": int(parts[3]),
                    "total": int(parts[4]),
                    "detail": parts[5] if len(parts) > 5 else "ok",
                    # org tag (7th column). Empty = system suite. Legacy 6-column
                    # rows have no org and are treated as system.
                    "org": parts[6] if len(parts) > 6 else "",
                }
            )
        except (ValueError, IndexError):
            continue  # skip unparseable lines
    return entries


def _scope_entries_to_org(entries: list[dict], active_space: str) -> list[dict]:
    """Keep system rows (no org tag) plus org-scoped rows that ran under the
    active org. This is what lets an active Space and an archived one coexist in one log without one
    overwriting the other's card. Pure function — unit-tested in test_parsers."""
    return [e for e in entries if not e.get("org") or e.get("org") == active_space]


def _half_records(data: dict, suites: dict[str, SuiteResult]) -> dict[str, HalfResult]:
    """The ``halves`` block, in run order; for a file that predates it, the CLI
    half summed from its suite entries (the rule Setup reads through
    Get-P20TestHalfRecords)."""
    raw = data.get("halves") or {}
    out: dict[str, HalfResult] = {}
    for half in TEST_HALVES:
        rec = raw.get(half)
        if not isinstance(rec, dict):
            continue
        out[half] = HalfResult(
            half=half,
            result=str(rec.get("result", "fail")),
            passed=int(rec.get("passed") or 0),
            failed=int(rec.get("failed") or 0),
            skipped=int(rec.get("skipped") or 0),
            total=int(rec.get("total") or 0),
            seconds=float(rec.get("seconds") or 0),
            reason=str(rec.get("reason") or ""),
            timestamp=str(rec.get("timestamp") or ""),
        )
    if DEFAULT_HALF not in out:
        cli = [s for s in suites.values() if s.half == DEFAULT_HALF]
        if cli:
            passed = sum(s.passed for s in cli)
            total = sum(s.total for s in cli)
            out[DEFAULT_HALF] = HalfResult(
                half=DEFAULT_HALF,
                result="fail" if any(s.result == "fail" for s in cli) else "pass",
                passed=passed,
                failed=total - passed,
                total=total,
                skipped=sum(1 for s in cli if s.result == "warn"),
                timestamp=str(data.get("timestamp", "")),
            )
    return dict(sorted(out.items(), key=lambda kv: TEST_HALVES.index(kv[0])))


def _load_machine_summaries(root=None) -> list[TestSummaryMachine]:
    """Load all test-summary.*.json files for cross-machine status."""
    machines = []
    for p in (root or REPO_ROOT).glob("test-summary.*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8-sig"))
            suites = {}
            for name, info in data.get("suites", {}).items():
                suites[name] = SuiteResult(
                    suite=name,
                    result=info.get("result", "fail"),
                    passed=info.get("passed", 0),
                    total=info.get("total", 0),
                    detail="ok" if info.get("result") in ("pass", "warn") else "fail",
                    description=info.get("description", ""),
                    half=info.get("half") or DEFAULT_HALF,
                )
            machines.append(
                TestSummaryMachine(
                    machine=data.get("machine", p.stem.replace("test-summary.", "")),
                    timestamp=data.get("timestamp", ""),
                    suites=suites,
                    halves=_half_records(data, suites),
                )
            )
        except (json.JSONDecodeError, KeyError, TypeError, ValueError, AttributeError):
            continue
    return machines


@api.get("/test-history", response_model=TestHistoryResponse)
async def get_test_history():
    from collections import defaultdict
    from datetime import datetime, timedelta

    active_space = load_config().get("activeSpace", "")

    # Scope to the active Space: system suites (no org tag) always show; org-scoped
    # suites only when they ran under the active Space. So two Spaces coexist in
    # the log without one overwriting the other's card.
    entries = _scope_entries_to_org(_parse_test_log(), active_space)

    cutoff = (datetime.now() - timedelta(days=HISTORY_DAYS)).strftime("%Y-%m-%d")

    # Filter to HISTORY_DAYS window
    recent = [e for e in entries if e["date"] >= cutoff]

    # Latest-per-suite-per-day aggregation
    latest: dict[tuple[str, str], dict] = {}  # (date, suite) -> entry
    for e in recent:
        key = (e["date"], e["suite"])
        if key not in latest or e["timestamp"] > latest[key]["timestamp"]:
            latest[key] = e

    # Group by date
    by_date: dict[str, list[dict]] = defaultdict(list)
    for (date, _suite), entry in latest.items():
        by_date[date].append(entry)

    # Build days (sorted chronologically)
    days = []
    for date in sorted(by_date.keys()):
        day_entries = by_date[date]
        total_passed = sum(e["passed"] for e in day_entries)
        total_total = sum(e["total"] for e in day_entries)
        suites = [
            SuiteResult(suite=e["suite"], result=e["result"], passed=e["passed"], total=e["total"], detail=e["detail"])
            for e in sorted(day_entries, key=lambda x: x["suite"])
        ]
        days.append(TestDay(date=date, passed=total_passed, total=total_total, suites=suites))

    # Last run timestamp
    last_run = max((e["timestamp"] for e in entries), default=None) if entries else None

    # Streak: consecutive days (from the most recent day with data, backward)
    # where all suites passed. Starting from the latest recorded day rather
    # than today avoids zeroing the streak before today's run has landed.
    streak = 0
    latest = max(by_date.keys(), default=None)
    if latest:
        cursor = datetime.strptime(latest, "%Y-%m-%d").date()
        for i in range(HISTORY_DAYS):
            check_date = (cursor - timedelta(days=i)).strftime("%Y-%m-%d")
            if check_date in by_date:
                # A warn (a suite that ran nothing) is neither a pass nor a
                # failure: it does not break the streak.
                all_pass = all(e["result"] in ("pass", "warn") for e in by_date[check_date])
                if all_pass:
                    streak += 1
                else:
                    break
            else:
                break  # gap in data = streak broken

    machines = _load_machine_summaries()

    # Build description and half lookups from machine summaries
    desc_map: dict[str, str] = {}
    half_map: dict[str, str] = {}
    for m in machines:
        for name, sr in m.suites.items():
            if sr.description and name not in desc_map:
                desc_map[name] = sr.description
            if name not in half_map:
                half_map[name] = sr.half

    # Attach descriptions and halves to daily suite results
    for day in days:
        for sr in day.suites:
            if not sr.description and sr.suite in desc_map:
                sr.description = desc_map[sr.suite]
            sr.half = half_map.get(sr.suite, DEFAULT_HALF)

    return TestHistoryResponse(
        machine=os.environ.get("COMPUTERNAME") or socket.gethostname().split(".")[0],
        active_space=active_space,
        days=days,
        last_run=last_run,
        streak=streak,
        machines=machines,
    )
