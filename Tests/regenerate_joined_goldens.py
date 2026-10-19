"""Regenerate the goldens of Tests/fixtures/rituals/standup-joined.json.

Goldens are generated, never typed: every case that names a ``text``, ``work``
or ``brief`` file is filled by the agent's joined fill and rendered, and the
bytes are written LF-only. The CLI's half (tkTestToolkit -Rituals) then holds
its own rendering to the same files, so a disagreement between the halves is
a red suite, not a quietly rewritten golden.

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


def filled_case(table: dict, case: dict) -> "standup.Standup":
    filled = standup.fill_joined_standup(
        datetime.fromisoformat(table["asOf"]),
        table["workerLabels"],
        case["issues"],
        {"ok": True, "reason": ""},
        case["cards"],
        space=table["space"],
        space_name=table["spaceName"],
    )
    filled.text = standup.render_standup(filled)
    filled.work.text = standup.render_work(filled)
    filled.brief = standup.render_brief(filled)
    return filled


def goldens() -> dict[str, str]:
    table = json.loads((FIXTURES / TABLE_FILE).read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for case in table["cases"]:
        exp = case["expected"]
        filled = filled_case(table, case)
        for key, text in (("text", filled.text), ("work", filled.work.text), ("brief", filled.brief)):
            if exp.get(key):
                out[exp[key]] = text
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
