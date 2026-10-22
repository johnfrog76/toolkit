"""The PM Corner: one derived line at the head of the Team Agile page (AR-4).

The contract is docs/modules/solitaire-agile.md, "The PM Corner: the line, the
chevron, the confetti" (spec prompt20-agent-in-the-room, section 7; D-AR11,
D-AR14). Two halves implement it -- this file and the CLI's
``Scripts/Corner-Rules.ps1`` -- and ONE table holds them to each other:
``Tests/fixtures/rituals/corner.json``, asserted from ``Tests/test_rituals.py``
and ``tkTestToolkit -Rituals``.

Nothing here is a second rule. The milestone is the suggestion's nearest
(``suggest.nearest_milestones``), over the suggestion's own candidates in the
suggestion's own order (``suggest.suggest``), and the id is the suggestion's pick
inside that milestone. The remaining count is the joined list's own open count
(``suggest.suggest_items``): the open issues that name the milestone plus the open
cards whose ``**Sprint:**`` line names it, WHOLE, counted once per id.

- ``corner`` -- PURE. The joined list's items and what closed in the window, in;
  the line out: its shape (``rituals.cornerShapes``), the milestone, the remaining
  count, the pick, the noun, the line and the command the chevron runs.
- ``corner_closed`` -- PURE. The read's issues and card rows, and the standup's
  window, in; every item that names a milestone and closed in the window, out,
  once per id -- what ``reached`` is decided from.
- ``attach_corner`` -- the step the route and the goldens run after the
  suggestion: the line on the standup, and the brief's last line.

The words are ``consts.json`` ``rituals.text.corner*``.
"""

from __future__ import annotations

from datetime import datetime

from ..core.consts import folder_archive, rituals_corner_shapes, rituals_text
from .standup import Corner, Standup
from .suggest import _day, _fill, nearest_milestones, queue_refs, suggest, suggest_items


def _plural(kinds: set[str]) -> str:
    t = rituals_text()
    if kinds == {"card"}:
        return t["cornerNounCards"]
    if kinds == {"issue"}:
        return t["cornerNounIssues"]
    return t["cornerNounItems"]


def corner(items: list[dict], closed: list[dict]) -> dict:
    """The Corner's line. Pure; the mirror of ``Get-P20CornerLine``.

    ``items`` is the joined list as ``suggest_items`` hands it (each milestone's
    ``open`` already its billable items, once per id). ``closed`` is
    ``corner_closed``'s answer: what named a milestone and closed in the window.

    1. REACHED: a milestone some billable closed item names and no open billable
       item names. The latest close first, then the title, ordinal.
    2. The nearest milestone among the suggestion's candidates; the pick is the
       first candidate in it, and the remaining count its ``open``. One left
       names the pick's noun (card, issue); more names the remaining rows' --
       cards, issues, or items for a mix.
    3. Else nothing in reach."""
    one_left, many_left, reached, nothing = rituals_corner_shapes()
    t = rituals_text()
    open_titles: dict[str, set[str]] = {}
    for item in items or []:
        m = item.get("milestone") or None
        if item.get("billable", True) is not False and m and m.get("title"):
            open_titles.setdefault(str(m["title"]), set()).add(str(item.get("kind") or ""))
    done: dict[str, str] = {}
    for c in closed or []:
        title = str(c.get("milestone") or "")
        if not title or c.get("billable", True) is False or title in open_titles:
            continue
        day = _day(c.get("day"))
        if title not in done or day > done[title]:
            done[title] = day
    out = {
        "shape": nothing,
        "milestone": "",
        "remaining": 0,
        "ref": "",
        "number": None,
        "id": None,
        "kind": "",
        "noun": "",
        "line": t["cornerNothingInReach"],
        "command": "",
    }
    if done:
        # The latest close; a tie by title, ordinal (max keeps the first of the sorted titles).
        title = max(sorted(done), key=lambda k: done[k])
        return {**out, "shape": reached, "milestone": title, "line": _fill(t["cornerReached"], {"milestone": title})}
    candidates, _excluded = suggest(items or [], "alone")
    in_reach = [c for c in candidates if (c.get("milestone") or {}).get("title")]
    if not in_reach:
        return out
    title = nearest_milestones([c["milestone"] for c in in_reach])[0]
    pick = next(c for c in in_reach if c["milestone"]["title"] == title)
    remaining = int(pick["milestone"].get("open") or 0)
    ref = str(pick.get("ref") or "")
    kind = str(pick.get("kind") or "")
    if remaining <= 1:
        noun = t["suggestNounCard"] if kind == "card" else t["suggestNounIssue"]
        line = _fill(t["cornerOneLeft"], {"noun": noun, "ref": ref, "milestone": title})
        shape = one_left
    else:
        noun = _plural(open_titles.get(title, {kind}))
        line = _fill(t["cornerManyLeft"], {"n": str(remaining), "noun": noun, "ref": ref, "milestone": title})
        shape = many_left
    return {
        **out,
        "shape": shape,
        "milestone": title,
        "remaining": remaining,
        "ref": ref,
        "number": pick.get("number"),
        "id": pick.get("id"),
        "kind": kind,
        "noun": noun,
        "line": line,
        "command": _fill(t["suggestCommandStart"], {"arg": ref.lstrip("#")}),
    }


def _when(stamp) -> datetime | None:
    text = str(stamp or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def corner_closed(issues: list[dict], cards: list[dict], since: datetime, as_of: datetime) -> list[dict]:
    """What named a milestone and closed in the window, once per id. Pure; the
    mirror of ``Get-P20CornerClosed``.

    An issue is CLOSED with a milestone and its ``closedAt`` in [since, as_of] --
    the standup's own test for yesterday's closes. A card is in ``archive/``, its
    Closed day in [since's day, as_of's day] (the cards fill's test), its
    ``**Sprint:**`` line naming the milestone, and its id no issue in the read --
    a card that tracks an issue is that issue's row, as on the joined list. Each
    is ``{ref, kind, milestone, day, billable}``."""
    numbers = {str(int(i.get("number", 0))) for i in issues or []}
    first, last = since.date().isoformat(), as_of.date().isoformat()
    out: list[dict] = []
    seen: set[str] = set()
    for issue in sorted(issues or [], key=lambda i: int(i.get("number", 0))):
        if str(issue.get("state", "")).upper() != "CLOSED":
            continue
        m = issue.get("milestone")
        title = str((m.get("title") if isinstance(m, dict) else m) or "")
        when = _when(issue.get("closedAt"))
        ref = f"#{int(issue.get('number', 0))}"
        if not title or when is None or not (since <= when <= as_of) or ref in seen:
            continue
        seen.add(ref)
        out.append(
            {"ref": ref, "kind": "issue", "milestone": title, "day": str(issue.get("closedAt"))[:10], "billable": True}
        )
    for card in sorted(cards or [], key=lambda c: str(c.get("file", ""))):
        cid = str(card.get("id") or "")
        title = str(card.get("sprint") or "")
        day = str(card.get("closed") or "")[:10]
        if str(card.get("folder", "")) != folder_archive() or not cid or cid in numbers or cid in seen or not title:
            continue
        if not (day and first <= day <= last):
            continue
        seen.add(cid)
        out.append(
            {
                "ref": cid,
                "kind": "card",
                "milestone": title,
                "day": day,
                "billable": card.get("billable", True) is not False,
            }
        )
    return out


def attach_corner(
    filled: Standup,
    labels: list[dict],
    issues: list[dict],
    cards: list[dict],
    on: bool,
    prefix: str,
    viewer: str = "",
) -> Standup:
    """The Corner attached to a filled standup, in place: ``corner`` and nothing
    else. None with the switch off (the suggestion's -- the Corner is its second
    surface, D-AR8), or with the tracker not answering. ``prefix`` is the CLI's,
    for the brief's command; ``viewer`` the signed-in gh user's login, as the
    suggestion takes it -- the pick is the suggestion's, so the exclusions are."""
    filled.corner = None
    if not on or not filled.tracker.ok:
        return filled
    use = issues if filled.source in ("issues", "both") else []
    items = suggest_items(labels, use, cards, queue_refs(filled), viewer)
    since = datetime.fromisoformat(filled.since)
    as_of = datetime.fromisoformat(filled.asOf)
    got = corner(items, corner_closed(use, cards, since, as_of))
    t = rituals_text()
    if got["command"]:
        brief = _fill(
            t["cornerBriefCommand"],
            {"line": got["line"], "chevron": t["cornerChevron"], "command": prefix + got["command"]},
        )
    else:
        brief = _fill(t["cornerBrief"], {"line": got["line"]})
    filled.corner = Corner(**got, brief=brief)
    return filled
