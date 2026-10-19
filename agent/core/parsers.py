"""Prompt-file parsers -- pure, content-only.

These are the canonical parsers for the prompt-file markdown format.
``Scripts/Get-PromptStatus.ps1`` implements the same derivation in PowerShell,
and ``Tests/test_parsers.py`` exercises both against the shared fixtures in
``Tests/fixtures/parsers/`` so the two cannot drift unnoticed.

Nothing here touches the filesystem: state is derived from content, and the
caller supplies the file name and modified date.
"""

import re

# The ONE tracker rule (D-G2): a pure
# function of an address, shared with the Space's own derivation.
from .config import tracker
from .consts import (
    card_id_shape,
    re_card_design_line,
    re_commit_bullet,
    re_design_id,
    re_pr_url_line,
    re_review_line,
    re_started_line,
    stamp_billable,
    status_active,
    status_code_review,
    status_in_progress,
    token_pr_url,
    token_previous_round,
)

# The state vocabulary and the two patterns that derive it come from
# consts.json, the package's contract file -- NOT from literals here. This
# module and Scripts/Get-PromptStatus.ps1 are the two implementations of one
# state machine, and the fixtures only ever caught drift after it was written.
#
_DATED_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}-")


def card_id(name: str, prefixes: list[str] | tuple[str, ...] = ()) -> str | None:
    """The id a card's FILENAME carries, as a string, or None.

    The mirror of ``Get-P20CardId`` in ``Scripts/Resolve-CardName.ps1``, and held
    to it by one shared table, ``Tests/fixtures/parsers/card-ids.json``:

    - an optional type prefix from ``workItemTypes`` (matched ignoring case),
    - the id -- ``consts.json`` ``regex.cardId``, matched case-SENSITIVELY, so a
      lowercase slug can never read as an id,
    - the dash that starts the slug.

    A dated file (``<date>-PR141415``) is not a card. A number is
    normalised: ``0141`` and ``141`` are one work item.
    """
    if _DATED_NAME.match(name):
        return None
    alts = sorted({re.escape(p) for p in prefixes if p})
    head = f"(?i:{'|'.join(alts)})?" if alts else ""
    m = re.match(f"^{head}({card_id_shape()})-", name)
    if not m:
        return None
    found = m.group(1)
    return str(int(found)) if found.isdigit() else found


def card_design(content: str) -> dict | None:
    """The design a card names, or None (docs/hub/cards.md, "Inside the file").

    The line is ``> Design: [<title>](<link>) <id>`` -- what ``NewPrompt
    -Design`` writes under ``> Template:`` -- or the corpus's hand-written
    ``> Spec: [<title>](<link>) <words>``, read as written. ``consts.json``
    ``design.cardLineRegex`` is the pattern; ``Get-P20CardDesign`` in
    ``Scripts/Read-DesignTree.ps1`` is the other reader, and both are held to
    ``Tests/fixtures/parsers/design-lines.json``.

    A card names ONE design: its first Design line, else its first Spec line. An
    empty line names nothing. Returns ``kind`` (design | spec), ``title``,
    ``link``, ``id`` (the design's id when the first word after the link is
    one, else "") and ``note`` (the rest of those words).
    """
    found: dict[str, dict] = {}
    for m in re_card_design_line().finditer(content or ""):
        kind = m.group(1).lower()
        if kind in found:
            continue
        title, link, words = (m.group(2) or "").strip(), (m.group(3) or "").strip(), (m.group(4) or "").strip()
        parts = re.split(r"[ \t]+", words, maxsplit=1)
        doc_id, note = "", words
        if parts[0] and re_design_id().match(parts[0]):
            doc_id, note = parts[0], (parts[1].strip() if len(parts) > 1 else "")
        if m.group(2) is None and m.group(3) is None and not doc_id:
            title, note = words, ""  # no link: a person's words are the title
        if not (title or link or doc_id or note):
            continue  # "> Design:" and nothing after it
        found[kind] = {"kind": kind, "title": title, "link": link, "id": doc_id, "note": note}
    return found.get("design") or found.get("spec")


_STATUS_ORDER = {status_active(): 0, status_in_progress(): 1, status_code_review(): 2}


def status_sort_key(status: str, file_name: str) -> tuple[int, str]:
    """Ledger order: state first, then file name, ordinal.

    The pair is the contract, not just the state: ``Scripts/Get-PromptStatus.ps1``
    sorts by the same two keys with an ordinal comparison, so the CLI's numbering
    and the web's list are the same order for the same hub. Sorting by state
    alone left the tie to the host -- Windows PowerShell 5.1's ``Sort-Object``
    is not stable, so the CLI rotated a list of Active cards while the agent did
    not.

    File name because it is the only within-state key the reader can predict:
    docs/CLI.md ("The workflow") fixes the order of the state CHECKS and says nothing about
    the order of cards inside a state.
    """
    return (_STATUS_ORDER.get(status, 99), file_name)


def _split_heading(heading: str, type_names) -> tuple[str | None, str]:
    """``"Bug 141: Recipe search"`` -> ``("Bug", "Recipe search")``.

    The H1 is the record of a card's TYPE (spec 5.0): the filename prefix is
    lossy -- a bare filename is a Bug only by convention -- so type is read here,
    against the CONFIGURED type names, longest first so "User Story" is not read
    as a type called "User". A heading that names no known type has no type, and
    its whole text is its name.
    """
    for type_name in sorted((t for t in type_names if t), key=len, reverse=True):
        m = re.match(rf"(?i){re.escape(type_name)}\s+(?:{card_id_shape()}|[A-Za-z0-9]+)\s*:\s*(.*)$", heading)
        if m:
            return type_name, m.group(1).strip()
    return None, heading


# The shipped type names, for a caller that has no config to hand (a test, a
# script). The agent passes config's own, so a team's type is known too.
_DEFAULT_TYPE_NAMES = ("User Story", "Task", "Feature", "Bug", "Spike")


def card_billable(content: str) -> bool:
    """False when the card says ``**Billable:** no``; no line means billable.

    The one reader of ``stamps.billable`` in this half: the card model reads it,
    and so does the standup (a not-billable card is not a standup row). The CLI's
    mirror is ``Test-P20CardBillable`` in ``Scripts/Get-PromptFileStatus.ps1``,
    which Daily and the standup read through."""
    return not re.search(r"(?mi)^" + re.escape(stamp_billable()) + r"\s*no\b", content or "")


def _parse_status_metadata(content: str, type_names=_DEFAULT_TYPE_NAMES) -> dict:
    """Extract the file-content-derived fields of PromptInfo.

    Returns a dict with keys: title, type, name, linked, tracker, sprint, progress,
    checked, total, ado_url, pr_url, previous_round, design, commits, status -- the content half of the Card
    model (docs/hub/cards.md, "The model, as the agent serves it"). ``id`` comes from the FILENAME
    (``card_id``), so the caller adds it. Fields that need filesystem access (file
    name, modified date) are filled in by the caller.
    """
    title = ""
    card_type = None
    name = ""
    m = re.search(r"(?m)^#\s+(.+)", content)
    if m:
        title = m.group(1).strip()
        title = re.sub(r"^[\U00002600-\U0001FFFF]\s*", "", title)
        card_type, name = _split_heading(title, type_names)
        if len(title) > 60:
            title = title[:57] + "..."

    checked = len(re.findall(r"(?m)^\s*-\s*\[x\]", content))
    total = len(re.findall(r"(?m)^\s*-\s*\[[x ]\]", content))
    progress = f"{checked}/{total}" if total > 0 else "--"

    ado_url = None
    m = re.search(r"(?m)^\*\*ADO Link:\*\*\s*(https://\S+)", content)
    if m:
        ado_url = m.group(1).strip()

    pr_url = None
    # The TOKEN is the contract (consts.json); capturing what follows it is this
    # half's business, so the pattern is built from the token rather than
    # retyping it.
    m = re.search(r"(?m)^" + re.escape(token_pr_url()) + r"\s*(https://\S+)", content)
    if m:
        pr_url = m.group(1).strip()

    # The card came back after archive: the line under `> Template:` names its
    # latest earlier round, relative to the card's own folder (docs/hub/cards.md).
    # The CLI's reader is Get-P20PreviousRoundPath; one fixture holds the two.
    previous_round = None
    m = re.search(r"(?m)^" + re.escape(token_previous_round()) + r"[ \t]*(\S[^\r\n]*?)[ \t]*\r?$", content)
    if m:
        previous_round = m.group(1)

    sprint = "--"
    m = re.search(r"(?m)^\*\*Sprint:\*\*\s*(.+)", content)
    if m:
        segments = re.split(r"[/\\]", m.group(1).strip())
        sprint = segments[-1].strip()
        if len(sprint) > 20:
            sprint = sprint[:18] + ".."

    # Code Review wins over In Progress wins over Active. Every pattern and every
    # state name here is read from consts.json -- see the import block.
    # Two writers per lane: git's token, or a person's -- the
    # `**Review:**` and `**Started:**` footer lines, for a card with no pull
    # request or nothing checked in. The rule does not care who wrote the line.
    has_pr_url = bool(re_pr_url_line().search(content)) or bool(re_review_line().search(content))
    # How many commit bullets the RECORD carries -- the git token only, not a
    # person's **Started:** line. A card In Progress by a Started line has none,
    # and the web's action model reads this to decide whether Create PR has
    # anything to open a pull request from (web/src/modules/ado/cardActions.ts).
    commits = len(re_commit_bullet().findall(content))
    has_commits = commits > 0 or bool(re_started_line().search(content))
    # The PR URL LINE is the gate, and only the line -- the CLI's rule, word for word
    # (Scripts/Get-PromptStatus.ps1: "the URL's presence is the gate, not the presence
    # of reviewer comments"). This used to be `has_pr_comments or has_pr_url`, so a
    # card with a review heading and no URL was Code Review here and In Progress in
    # the terminal.
    if has_pr_url:
        prompt_status = status_code_review()
    elif has_commits:
        prompt_status = status_in_progress()
    else:
        prompt_status = status_active()

    return {
        "title": title,
        "type": card_type,
        "name": name,
        # A card with a link is an "ADO card". That is the whole difference.
        "linked": ado_url is not None,
        # WHOSE ledger stands behind the card: the tracker rule run over
        # the card's OWN link, never the Space's address -- so a card stays
        # honest when Spaces mingle. "none" exactly when not linked.
        "tracker": tracker(ado_url),
        # No line means billable: the whole existing corpus needs no migration.
        "billable": card_billable(content),
        "sprint": sprint,
        "progress": progress,
        "checked": checked,
        "total": total,
        "ado_url": ado_url,
        "pr_url": pr_url,
        "previous_round": previous_round,
        # The design the card was worked against (toolkit card 4.6): the line as
        # written, or None. Resolving its id to a design is the route's business.
        "design": card_design(content),
        "commits": commits,
        "status": prompt_status,
    }


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
