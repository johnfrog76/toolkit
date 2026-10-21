"""The suggestion: one next move, derived from the joined list (Team Agile, AR-3).

The contract is docs/modules/solitaire-agile.md, "The suggestion: one next move,
derived" (spec prompt20-agent-in-the-room, section 6). Two halves implement it --
this file and the CLI's ``Scripts/Suggest-Rules.ps1`` -- and ONE table holds them
to each other: ``Tests/fixtures/suggestion/table.json``, asserted from
``Tests/test_rituals.py`` and ``tkTestToolkit -Rituals``.

Never invented: every noun is the tracker's or the card's, every number a count,
and the sentence names the rule that chose the item, so anyone reproduces the pick
by hand.

- ``nearest_milestones`` -- PURE. Milestones in, the nearest first: the fewest open
  items, a tie by the earlier due date (none after every one with one), then the
  title, ordinal. The table's ``nearest`` rows.
- ``suggest`` -- PURE. Items already joined in (ref, kind, severity, milestone
  {title, open, due}, created, size, who, lane, billable, waiting), the Space's
  howIWork and the refs dismissed on this surface; out the candidates in order,
  each with its shape, sentence and command, and every excluded ref with the FIRST
  exclusion it met (``rituals.suggestExclusions``). The table's ``rows``.
- ``suggest_items`` -- PURE. The joined list as the standup reads it -- the labels,
  the issues, the card rows and the refs on the queue -- turned into items: an
  open issue is one row, a card that tracks it adds its lane, a card of its own is
  its own row, and a milestone's open count is its billable rows, once per id.
- ``suggestions_on`` -- PURE. Team Agile's resolved switch and the Space's
  ``features.suggestions``: unset is on wherever Team Agile is on. The table's
  ``switch`` rows.
- ``attach_suggestions`` -- the step the route and the goldens run after the fill.

The words are ``consts.json`` ``rituals.text.suggest*``; the chair's line replaces
``briefNextNone`` only, and only when nothing waits (D-AR7) -- ``render_brief``.
"""

from __future__ import annotations

import re

from ..core.consts import (
    folder_current,
    rituals_assign_me,
    rituals_suggest_exclusions,
    rituals_suggest_owner_seat,
    rituals_suggest_shapes,
    rituals_text,
    rituals_worker_label_prefix,
    status_active,
    status_code_review,
    status_in_progress,
)
from .standup import Standup, Suggestion, _label_names, ceremonies, worker_name
from .triage import who

# A due date or a created day that is not there sorts after every one that is.
_LAST_DAY = "9999-99-99"
_PLACEHOLDER = re.compile(r"\{(ref|why|size|nobody|noun|milestone|kind|sentence|command|arg)\}")


def _fill(template: str, values: dict[str, str]) -> str:
    """One pass over a template's placeholders: a value is never read as one."""
    return _PLACEHOLDER.sub(lambda m: values.get(m.group(1), m.group(0)), template)


def _day(value) -> str:
    """A date-ish value as its yyyy-MM-dd, or "" -- a created stamp, an ISO time, a due date."""
    text = str(value or "").strip()
    return text[:10] if re.match(r"^\d{4}-\d{2}-\d{2}", text) else ""


def severities() -> list[str]:
    """The triage ceremony's severities, most severe first (Config/ceremonies.json)."""
    return list(ceremonies()["triage"]["severities"])


# -- The nearest milestone -----------------------------------------------------


def nearest_milestones(milestones: list[dict]) -> list[str]:
    """Milestone titles, the nearest first: fewest open items, then the earlier due
    date (a milestone with none after every one with one), then the title, ordinal.
    One entry per title (the first seen). The mirror of ``Get-P20NearestMilestones``."""
    seen: dict[str, dict] = {}
    for m in milestones or []:
        title = str((m or {}).get("title") or "")
        if title and title not in seen:
            seen[title] = m
    return sorted(
        seen,
        key=lambda t: (int(seen[t].get("open") or 0), _day(seen[t].get("due")) or _LAST_DAY, t),
    )


# -- The rule ------------------------------------------------------------------


def _is_theirs(who: str) -> bool:
    """Whether ``who`` is another person: an assignee who is not you (``@<login>``)."""
    return who.startswith("@")


def _is_yours(who: str) -> bool:
    """Whether the item is yours to start: you (``me``), or the owner's own seat (D-AR10)."""
    return who in (rituals_assign_me(), rituals_suggest_owner_seat())


def _command(template_key: str, ref: str) -> str:
    return _fill(rituals_text()[template_key], {"arg": ref.lstrip("#")})


def _sentence(item: dict, how: str) -> tuple[str, str, str]:
    """(shape, sentence, command) for one candidate. Pure."""
    t = rituals_text()
    start, delegate, route, place = rituals_suggest_shapes()
    ref = str(item.get("ref") or "")
    noun = t["suggestNounCard"] if item.get("kind") == "card" else t["suggestNounIssue"]
    kind = str(item.get("severity") or "") or noun
    milestone = item.get("milestone") or None
    title = str((milestone or {}).get("title") or "")
    if title and int((milestone or {}).get("open") or 0) == 1:
        why = _fill(t["suggestWhyLast"], {"noun": noun, "milestone": title})
    elif title:
        why = _fill(t["suggestWhyMilestone"], {"kind": kind, "milestone": title})
    else:
        why = _fill(t["suggestWhyOldest"], {"kind": kind})
    who = str(item.get("who") or "")
    if how != "agents" or _is_yours(who):
        return start, _fill(t["suggestStart"], {"ref": ref, "why": why}), _command("suggestCommandStart", ref)
    if who:
        size = str(item.get("size") or who)
        if title:
            # Well defined is not a judgement: a size label and a milestone.
            return (
                delegate,
                _fill(t["suggestDelegate"], {"ref": ref, "size": size}),
                _command("suggestCommandStart", ref),
            )
        # Sized, but no destination: route it to a milestone.
        return place, _fill(t["suggestPlace"], {"ref": ref, "size": size}), _command("suggestCommandPlace", ref)
    return (
        route,
        _fill(t["suggestRoute"], {"ref": ref, "why": why, "nobody": t["suggestNobody"]}),
        _command("suggestCommandRoute", ref),
    )


def excluded_by(item: dict, dismissed: set[str]) -> str:
    """The first exclusion an item meets, in rituals.suggestExclusions' order; "" for none."""
    not_billable, waiting, in_flight, theirs, was_dismissed = rituals_suggest_exclusions()
    if item.get("billable", True) is False:
        return not_billable
    if item.get("waiting"):
        return waiting
    if item.get("lane") in (status_in_progress(), status_code_review()):
        return in_flight
    if _is_theirs(str(item.get("who") or "")):
        return theirs
    if str(item.get("ref") or "") in dismissed:
        return was_dismissed
    return ""


def suggest(items: list[dict], how: str, dismissed: list[str] | None = None) -> tuple[list[dict], dict[str, str]]:
    """The candidates in order and the excluded refs. Pure; the mirror of ``Select-P20Suggestion``.

    Each candidate is the item with ``shape``, ``sentence`` and ``command`` added; the
    first is the pick. Order: severity (severities() in order, then none), the nearest
    milestone (``nearest_milestones``; none after every milestone), age (the oldest
    created day first; none last), then the ref without its ``#``, ordinal."""
    gone = set(dismissed or [])
    excluded: dict[str, str] = {}
    kept: list[dict] = []
    for item in items or []:
        why = excluded_by(item, gone)
        if why:
            excluded[str(item.get("ref") or "")] = why
        else:
            kept.append(item)
    sev = severities()
    rank = {title: i for i, title in enumerate(nearest_milestones([i.get("milestone") or {} for i in kept]))}

    def order(item: dict) -> tuple:
        s = str(item.get("severity") or "")
        title = str((item.get("milestone") or {}).get("title") or "")
        return (
            sev.index(s) if s in sev else len(sev),
            rank.get(title, len(rank)),
            _day(item.get("created")) or _LAST_DAY,
            str(item.get("ref") or "").lstrip("#"),
        )

    out = []
    for item in sorted(kept, key=order):
        shape, sentence, command = _sentence(item, how)
        out.append({**item, "shape": shape, "sentence": sentence, "command": command})
    return out, excluded


# -- The switch ----------------------------------------------------------------


def suggestions_on(team_agile, stored) -> bool:
    """Whether the suggestion shows: Team Agile on (its resolved switch) AND the
    Space's ``features.suggestions`` not false -- unset is on. The mirror of
    ``Test-P20SuggestionsOn``; the table's ``switch`` rows."""
    return bool(team_agile) and stored is not False


# -- The joined list, as items ---------------------------------------------------


def _assignee(issue: dict) -> str:
    for a in issue.get("assignees") or []:
        login = a.get("login") if isinstance(a, dict) else a
        if login:
            return str(login)
    return ""


def suggest_items(
    labels: list[dict], issues: list[dict], cards: list[dict], waiting: set[str], viewer: str = ""
) -> list[dict]:
    """The joined list as the rule's items. Pure; the mirror of ``Get-P20SuggestionItems``.

    An OPEN issue is one item: its severity and size from its labels (the triage
    ceremony's severities, the worker labels), who has it by the triage rule (its
    first assignee -- ``me`` when it is ``viewer``, the signed-in gh user, else
    ``@<login>`` -- else its size), its milestone and due date, its
    createdAt, and its lane from the card in ``current/`` whose id is its number
    (Active without one). A card in ``current/`` whose id is no issue in the read
    is its own item: severity and size from its Tags line, who from its
    **Assigned:** line (else its size), its milestone from its **Sprint:** line,
    its **Created:** day and its lane. A not-billable card is an item with
    ``billable`` false and adds nothing to an issue. ``waiting`` is every ref on
    the queue. A milestone's ``open`` counts its billable items, once per id."""
    prefix = rituals_worker_label_prefix()
    sizes = {
        str(lab.get("name", ""))
        for lab in labels or []
        if str(lab.get("description") or "").startswith(prefix) and worker_name(str(lab.get("description") or ""))
    }
    sev = severities()
    numbers = {str(int(i.get("number", 0))) for i in issues or []}
    current = [c for c in cards or [] if str(c.get("folder", "")) == folder_current()]
    lane_of = {
        str(c.get("id") or ""): str(c.get("status") or "")
        for c in current
        if c.get("billable", True) is not False and str(c.get("id") or "") in numbers
    }
    items: list[dict] = []
    for issue in sorted(issues or [], key=lambda i: int(i.get("number", 0))):
        if str(issue.get("state", "")).upper() != "OPEN":
            continue
        n = str(int(issue.get("number", 0)))
        tags = _label_names(issue.get("labels"))
        size = next((t for t in tags if t in sizes), "")
        assignee = _assignee(issue)
        m = issue.get("milestone")
        title = str((m.get("title") if isinstance(m, dict) else m) or "")
        due = _day(m.get("dueOn")) if isinstance(m, dict) else ""
        items.append(
            {
                "ref": f"#{n}",
                "number": int(n),
                "id": None,
                "kind": "issue",
                "title": str(issue.get("title") or ""),
                "severity": next((t for t in tags if t in sev), ""),
                "milestone": {"title": title, "open": 0, "due": due or None} if title else None,
                "created": _day(issue.get("createdAt")) or None,
                "size": size,
                "who": who(assignee, size, viewer),
                "lane": lane_of.get(n, status_active()),
                "billable": True,
                "waiting": f"#{n}" in waiting,
            }
        )
    for card in sorted(current, key=lambda c: str(c.get("file", ""))):
        cid = str(card.get("id") or "")
        if not cid or cid in numbers:
            continue
        tags = [str(t) for t in card.get("tags") or []]
        size = next((t for t in tags if t in sizes), "")
        title = str(card.get("sprint") or "")
        items.append(
            {
                "ref": cid,
                "number": None,
                "id": cid,
                "kind": "card",
                "title": str(card.get("title") or ""),
                "severity": next((t for t in tags if t in sev), ""),
                "milestone": {"title": title, "open": 0, "due": None} if title else None,
                "created": _day(card.get("created")) or None,
                "size": size,
                "who": str(card.get("assigned") or "") or size,
                "lane": str(card.get("status") or ""),
                "billable": card.get("billable", True) is not False,
                "waiting": cid in waiting,
            }
        )
    opens: dict[str, int] = {}
    for item in items:
        if item["billable"] and item["milestone"]:
            opens[item["milestone"]["title"]] = opens.get(item["milestone"]["title"], 0) + 1
    for item in items:
        if item["milestone"]:
            item["milestone"]["open"] = opens.get(item["milestone"]["title"], 0)
    return items


def queue_refs(filled: Standup) -> set[str]:
    """Every ref on the standup's queue, any kind: what waits on you."""
    refs: set[str] = set()
    for kind in ceremonies()["standup"]["queue"]:
        for it in getattr(filled.queue, kind):
            refs.add(f"#{it.number}" if it.number is not None else (it.id or ""))
    return refs


def attach_suggestions(
    filled: Standup,
    labels: list[dict],
    issues: list[dict],
    cards: list[dict],
    how: str,
    on: bool,
    prefix: str,
    viewer: str = "",
) -> Standup:
    """The suggestion attached to a filled standup, in place: every candidate in
    order and the first. Nothing with the switch off, or with the tracker not
    answering (a ritual with no read has no list to choose from). ``prefix`` is the
    CLI's, for the command the chair's line names; ``viewer`` the signed-in gh user's
    login (triage's one read), "" when gh cannot say -- then every assignee is
    someone else's, and a suggestion is never someone else's work."""
    filled.suggestions = []
    filled.suggestion = None
    if not on or not filled.tracker.ok:
        return filled
    items = suggest_items(
        labels, issues if filled.source in ("issues", "both") else [], cards, queue_refs(filled), viewer
    )
    picked, _excluded = suggest(items, how)
    t = rituals_text()
    filled.suggestions = [
        Suggestion(
            ref=p["ref"],
            number=p.get("number"),
            id=p.get("id"),
            kind=p["kind"],
            shape=p["shape"],
            sentence=p["sentence"],
            command=p["command"],
            line=_fill(t["suggestNext"], {"sentence": p["sentence"], "command": prefix + p["command"]}),
        )
        for p in picked
    ]
    filled.suggestion = filled.suggestions[0] if filled.suggestions else None
    return filled
