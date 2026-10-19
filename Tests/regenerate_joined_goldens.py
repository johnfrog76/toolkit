"""Regenerate the standup's goldens: standup-joined.json's, standup.json's and standup-cards.json's.

Goldens are generated, never typed: every case that names a ``text``, ``work``
or ``brief`` file is filled by the agent's fill for its table (the joined fill,
the issues fill, the cards fill) and rendered, and the bytes are written LF-only.
The CLI's half (tkTestToolkit -Rituals) then holds its own rendering to the
same files, so a disagreement between the halves is a red suite, not a quietly
rewritten golden. The work grain of standup.json and standup-cards.json is
held by standup-work.json and standup-prose.json, whose goldens this does not
write: those two tables name only ``text``, and it is the work text.

Run:  python3 Tests/regenerate_joined_goldens.py          (writes)
      python3 Tests/regenerate_joined_goldens.py --check  (exit 1 if any differs)
"""

import json
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from agent.solitaire import standup  # noqa: E402

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "rituals"
TABLE_FILE = "standup-joined.json"
ISSUES_TABLE_FILE = "standup.json"
CARDS_TABLE_FILE = "standup-cards.json"


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


def goldens() -> dict[str, str]:
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
    return out


def main(argv: list[str]) -> int:
    check = "--check" in argv
    stale = []
    for name, text in goldens().items():
        path = FIXTURES / name
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
