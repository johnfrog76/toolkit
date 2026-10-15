"""The agent's one writer for a card that already exists.

The CLI has one, ``Write-CardText`` in ``Scripts/Write-CardText.ps1``, and the
rule it keeps is the card's byte contract (docs/CLI.md, "The bytes a card is
written with"): UTF-8 with no BOM, and a file the tool EDITS keeps the line
ending it already has. The agent edits one kind of card natively -- the PR
comments ``save`` writes a decision and a reply into it -- and it once
did so with a bare ``write_text``, which on a CRLF card (most of a Windows
hub) wrote the edited section LF and left the file mixed
(item 2).

So: every agent-side edit of a card goes through ``write_card_text``, which
reads the file's terminator first and writes with it. There is deliberately no
create here. A card is CREATED by the CLI, through ``POST /api/cmd/NewPrompt``
and its siblings, and the web has no second implementation to get that wrong
(AGENTS.md, "``current/`` is protected").
"""

from pathlib import Path

CRLF = "\r\n"
LF = "\n"


def detect_newline(data: bytes | str) -> str:
    """The terminator a file already uses: CRLF if any ``\\r\\n`` is in it, else LF.

    "Any" rather than "the first": a card that has been edited by a writer that
    got this wrong is mixed, and the next edit through here makes it consistent
    again in the ending the file was born with.
    """
    if isinstance(data, bytes):
        return CRLF if b"\r\n" in data else LF
    return CRLF if CRLF in data else LF


def write_card_text(path: Path, text: str) -> None:
    """Write ``text`` over the card at ``path``: UTF-8, no BOM, the file's own
    line ending throughout.

    ``text`` may carry either ending, or both -- it is normalised to LF and
    written with ``newline=`` set to what the file had, so a caller that read
    the card with universal newlines (``read_text``) and edited it in LF hands
    back exactly the bytes the card had, plus its edit. A card that is not
    there yet is written LF, because a file the tool creates is LF -- but a
    create belongs to the CLI, and nothing in the agent calls this on a path
    that does not exist.
    """
    try:
        newline = detect_newline(path.read_bytes())
    except OSError:
        newline = LF
    normalised = text.replace(CRLF, LF)
    with open(path, "w", encoding="utf-8", newline=newline) as handle:
        handle.write(normalised)
