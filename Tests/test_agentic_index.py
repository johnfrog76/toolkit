"""agentic/prompts.json describes exactly the shipped prompts: every ``*.prompt.md`` has an
entry, every entry has a file, each entry names at least one of the three ways of working
(``alone``, ``team``, ``agents``), who sends it, and a category from the index's vocabulary. The
Studio's Prompts card reads this index, so a prompt added without a line here would be invisible
there."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENTIC = ROOT / "agentic"
# The three ways of working are the answers to "How do you want to work?" -- the
# values Config/settings-workflows.json's answers write to spaces[].howIWork, the
# words /env's howIWork answers in. The web picks a Space's prompts by them.
_SETTINGS = json.loads((ROOT / "Config" / "settings-workflows.json").read_text(encoding="utf-8-sig"))
WORKFLOWS = {
    a["value"]
    for e in _SETTINGS["entries"]
    if e.get("answerKey") == "spaces.{slug}.howIWork"
    for a in e.get("answers", [])
}


def test_the_ways_of_working_are_the_how_i_work_answers():
    assert WORKFLOWS == {"alone", "team", "agents"}


def _index() -> dict:
    return json.loads((AGENTIC / "prompts.json").read_text(encoding="utf-8"))


def _shipped() -> set:
    return {p.name[: -len(".prompt.md")] for p in AGENTIC.glob("*.prompt.md")}


def test_every_shipped_prompt_has_an_entry_and_every_entry_a_prompt():
    entries = set(_index()["prompts"])
    shipped = _shipped()
    assert shipped, "no prompts found under agentic/"
    assert shipped - entries == set(), f"prompts with no entry in agentic/prompts.json: {sorted(shipped - entries)}"
    assert entries - shipped == set(), f"entries with no prompt file: {sorted(entries - shipped)}"


def test_every_entry_names_a_workflow_a_sender_and_a_module():
    for name, entry in _index()["prompts"].items():
        workflows = entry.get("workflows")
        assert workflows and set(workflows) <= WORKFLOWS, (
            f"{name}: workflows must be a non-empty subset of {sorted(WORKFLOWS)}"
        )
        assert entry.get("sender"), f"{name}: sender is required ('by hand', a verb, or a route)"
        modules = {"core", "growth", "communication", "organize", "solitaireAgile"}
        assert entry.get("module") in modules, f"{name}: module"


# The category vocabulary: a small fixed list in the index, which agentic/README.md
# ("The shape of a prompt") describes one row each. Every shipped entry carries one
# of them; the Studio's Prompts card shows it on the row.
def test_every_entry_carries_a_category_from_the_vocabulary():
    vocabulary = _index().get("categories")
    assert vocabulary and len(vocabulary) == len(set(vocabulary)), "categories: a non-empty list with no repeats"
    assert "uncategorized" not in vocabulary, "uncategorized is what NO category reads as, not a category"
    for name, entry in _index()["prompts"].items():
        assert entry.get("category") in vocabulary, f"{name}: category must be one of {vocabulary}"


def test_the_readme_describes_the_vocabulary_exactly():
    text = (AGENTIC / "README.md").read_text(encoding="utf-8")
    section = text.split("## The shape of a prompt", 1)[1].split("\n## ", 1)[0]
    rows = re.findall(r"^\| `([a-z-]+)` \|", section, re.MULTILINE)
    assert rows == _index()["categories"], "agentic/README.md's category table and prompts.json's categories differ"


def test_the_two_prompts_the_tools_send_are_not_by_hand():
    prompts = _index()["prompts"]
    assert prompts["pr-review"]["sender"] == "AddPRReview"
    assert prompts["pr-suggest"]["sender"].startswith("POST /api/pr-comments/")


# One header shape for every shipped prompt: YAML frontmatter on line 1 with the
# three keys an editor's prompt-file feature and the Studio's Prompts card read --
# `description` (one sentence: the card's purpose line), `argument-hint` and
# `agent` -- then one `# ` title. `tools` is optional. agentic/README.md, "The
# shape of a prompt", is the rule this holds.
REQUIRED_KEYS = ("description", "argument-hint", "agent")
OPTIONAL_KEYS = ("tools",)


def _header(path: Path) -> tuple[dict, list]:
    lines = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").split("\n")
    assert lines[0] == "---", f"{path.name}: does not open with frontmatter"
    close = lines.index("---", 1)
    keys = {}
    for line in lines[1:close]:
        key, sep, value = line.partition(":")
        assert sep, f"{path.name}: frontmatter line is not 'key: value': {line!r}"
        keys[key.strip()] = value.strip().strip('"')
    return keys, lines[close + 1 :]


def test_every_prompt_opens_with_one_header_shape():
    for path in sorted(AGENTIC.glob("*.prompt.md")):
        keys, body = _header(path)
        for key in REQUIRED_KEYS:
            assert keys.get(key), f"{path.name}: frontmatter has no {key}"
        extra = set(keys) - set(REQUIRED_KEYS) - set(OPTIONAL_KEYS)
        assert not extra, f"{path.name}: frontmatter keys outside the shape: {sorted(extra)}"
        description = keys["description"]
        assert description.endswith("."), f"{path.name}: description is not one sentence ending in a period"
        assert not re.search(r"[.!?] +[A-Z]", description), f"{path.name}: description is more than one sentence"
        titles = [ln for ln in body if ln.startswith("# ")]
        assert len(titles) == 1, f"{path.name}: expected one '# ' title after the frontmatter, found {len(titles)}"


def test_no_prompt_carries_its_own_history():
    # A gap that is fixed is the commit's and the tracker's record; an open one is a
    # row in docs/KNOWN-GAPS.md that the prompt links to. The instructions say the rule.
    for path in sorted(AGENTIC.glob("*.prompt.md")):
        text = path.read_text(encoding="utf-8-sig")
        assert not re.search(r"Known gap(?!s)", text), f"{path.name}: a known-gap note belongs in docs/KNOWN-GAPS.md"
        assert "the note stays as the record" not in text, f"{path.name}: history in the instructions"
        assert not re.search(r"(?<![\w{/])#\d+\b", text), f"{path.name}: names an issue number"
