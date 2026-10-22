"""Regenerate the rituals' goldens: the standup's -- standup-joined.json's, standup.json's and
standup-cards.json's -- and triage's, triage.json's triage-<name>.txt.

Goldens are generated, never typed: every case that names a ``text``, ``work``
or ``brief`` file is filled by the agent's fill for its table (the joined fill,
the issues fill, the cards fill) and rendered, and the bytes are written LF-only.
The CLI's half (tkTestToolkit -Rituals) then holds its own rendering to the
same files, so a disagreement between the halves is a red suite, not a quietly
rewritten golden. The work grain of standup.json and standup-cards.json is
held by standup-work.json and standup-prose.json, whose goldens this does not
write: those two tables name only ``text``, and it is the work text. Triage's
goldens are filled by agent/solitaire/triage.py's fill over triage.json (each
case's labels, issues, tracker and viewer) and rendered; tkTestToolkit -Triage
holds the CLI's rendering to the same files.

The suggestion table's chair readings (Tests/fixtures/suggestion/table.json,
its ``briefs`` cases) are written beside it the same way: the joined fill, the
suggestion attached (agent/solitaire/suggest.py), the brief rendered.

The PM Corner's chair readings (Tests/fixtures/rituals/corner.json, its ``briefs``
cases) are written beside the rituals' goldens: the joined fill, the suggestion
and the Corner attached (agent/solitaire/corner.py), the brief rendered. A card in
corner.json is given as its file's LINES; ``corner_card_rows`` reads each through
the agent's one card reader, as ``read_cards`` does.

Run:  python3 Tests/regenerate_joined_goldens.py          (writes)
      python3 Tests/regenerate_joined_goldens.py --check  (exit 1 if any differs)
"""

import json
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from agent.solitaire import standup, triage  # noqa: E402

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "rituals"
TABLE_FILE = "standup-joined.json"
ISSUES_TABLE_FILE = "standup.json"
CARDS_TABLE_FILE = "standup-cards.json"
TRIAGE_TABLE_FILE = "triage.json"
SUGGEST_DIR = REPO_ROOT / "Tests" / "fixtures" / "suggestion"
CORNER_TABLE_FILE = "corner.json"


def filled_triage_case(table: dict, case: dict) -> "triage.Triage":
    """A triage.json case, filled and rendered."""
    filled = triage.fill_triage(
        table["labels"], case["issues"], case["tracker"], space=case["space"], viewer=case.get("viewer", "")
    )
    filled.text = triage.render_triage(filled)
    return filled


def _rendered(filled: "standup.Standup") -> "standup.Standup":
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    filled.brief = standup.render_brief(filled)
    return filled


def filled_case(table: dict, case: dict) -> "standup.Standup":
    """A standup-joined.json case, filled and rendered."""
    return _rendered(
        standup.fill_joined_standup(
            datetime.fromisoformat(table["asOf"]),
            table["workerLabels"],
            case["issues"],
            {"ok": True, "reason": ""},
            case["cards"],
            space=table["space"],
            space_name=table["spaceName"],
            window=case.get("window", ""),
        )
    )


def filled_issues_case(table: dict, case: dict) -> "standup.Standup":
    """A standup.json case (the issues fill), filled and rendered."""
    labels = table["workerLabels"] if case["labels"] == "workerLabels" else case["labels"]
    return _rendered(
        standup.fill_standup(
            datetime.fromisoformat(case["asOf"]), labels, case["issues"], case["tracker"], space="toolkit"
        )
    )


def filled_cards_case(case: dict) -> "standup.Standup":
    """A standup-cards.json case (the cards fill), filled and rendered."""
    return _rendered(
        standup.fill_cards_standup(
            datetime.fromisoformat(case["asOf"]), case["cards"], space=case["space"], space_name=case["spaceName"]
        )
    )


def filled_suggest_case(table: dict, case: dict) -> "standup.Standup":
    """A briefs case of Tests/fixtures/suggestion/table.json: the joined fill, the
    suggestion attached, rendered."""
    from agent.solitaire import suggest

    b = table["briefs"]
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(b["asOf"]),
        b["workerLabels"],
        case["issues"],
        {"ok": True, "reason": ""},
        case["cards"],
        space=b["space"],
        space_name=b["spaceName"],
    )
    on = suggest.suggestions_on(True, case["suggestions"])
    suggest.attach_suggestions(
        filled, b["workerLabels"], case["issues"], case["cards"], case["howIWork"], on, b["prefix"]
    )
    return _rendered(filled)


def corner_card_rows(cards: list[dict]) -> list[dict]:
    """corner.json's cards, each given as its file's ``lines``, as the card rows
    ``read_cards`` makes: the **Sprint:** line WHOLE (card_milestone), the Tags,
    who takes it and whether it is billable, through the agent's one card reader."""
    from agent.core.parsers import card_assigned, card_billable, card_milestone, card_tags

    rows = []
    for c in cards:
        text = "\n".join(c["lines"]) + "\n"
        rows.append(
            {
                **{k: v for k, v in c.items() if k != "lines"},
                "sprint": card_milestone(text),
                "tags": card_tags(text),
                "assigned": card_assigned(text),
                "billable": card_billable(text),
            }
        )
    return rows


def filled_corner_case(table: dict, case: dict) -> "standup.Standup":
    """A briefs case of Tests/fixtures/rituals/corner.json: the joined fill, the
    suggestion and the Corner attached, rendered."""
    from agent.solitaire import corner, suggest

    b = table["briefs"]
    cards = corner_card_rows(case["cards"])
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(table["asOf"]),
        table["workerLabels"],
        case["issues"],
        {"ok": True, "reason": ""},
        cards,
        space=b["space"],
        space_name=b["spaceName"],
    )
    on = suggest.suggestions_on(True, case["suggestions"])
    suggest.attach_suggestions(filled, table["workerLabels"], case["issues"], cards, case["howIWork"], on, b["prefix"])
    corner.attach_corner(filled, table["workerLabels"], case["issues"], cards, on, b["prefix"])
    return _rendered(filled)


def goldens() -> dict[str, str]:
    """Every golden by its path relative to Tests/fixtures/rituals/ -- a rituals golden is its
    file name; the suggestion table's are ``../suggestion/<file>``."""
    out: dict[str, str] = {}

    def take(exp: dict, filled: "standup.Standup", keys: tuple[str, ...]) -> None:
        texts = {"text": filled.text, "work": filled.work.text, "brief": filled.brief}
        for key in keys:
            if exp.get(key):
                out[exp[key]] = texts[key]

    table = json.loads((FIXTURES / TABLE_FILE).read_text(encoding="utf-8"))
    for case in table["cases"]:
        take(case["expected"], filled_case(table, case), ("text", "work", "brief"))
    issues = json.loads((FIXTURES / ISSUES_TABLE_FILE).read_text(encoding="utf-8"))
    for case in issues["cases"]:
        take(case["expected"], filled_issues_case(issues, case), ("text", "brief"))
    cards = json.loads((FIXTURES / CARDS_TABLE_FILE).read_text(encoding="utf-8"))
    for case in cards["cases"]:
        take(case["expected"], filled_cards_case(case), ("text", "brief"))
    tri = json.loads((FIXTURES / TRIAGE_TABLE_FILE).read_text(encoding="utf-8"))
    for case in tri["cases"]:
        out[case["expected"]["text"]] = filled_triage_case(tri, case).text
    sug = json.loads((SUGGEST_DIR / "table.json").read_text(encoding="utf-8"))
    for case in sug["briefs"]["cases"]:
        out["../" + SUGGEST_DIR.name + "/" + case["expected"]["brief"]] = filled_suggest_case(sug, case).brief
    cor = json.loads((FIXTURES / CORNER_TABLE_FILE).read_text(encoding="utf-8"))
    for case in cor["briefs"]["cases"]:
        out[case["expected"]["brief"]] = filled_corner_case(cor, case).brief
    return out


def main(argv: list[str]) -> int:
    check = "--check" in argv
    stale = []
    for key, text in goldens().items():
        path = (FIXTURES / key).resolve()
        name = str(path.relative_to(REPO_ROOT))
        if check:
            if not path.exists() or path.read_bytes().decode("utf-8") != text:
                stale.append(name)
            continue
        path.write_bytes(text.encode("utf-8"))
        print(f"wrote {path.relative_to(REPO_ROOT)}")
    for name in stale:
        print(f"stale: {name}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
