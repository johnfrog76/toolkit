"""``GET /api/status``: what it reads, and how many times.

A card's ``modified`` day is DERIVED, so it must keep reading what the files
already say (AGENTS.md, "When something READS wrong, ask what it read before").
It used to be one ``git log -1 -- <card>`` per card; it is one ``git log`` for
the Space's ``current/`` and ``backlog/`` (agent/core/git_history.py
``folder_changes``). ``Tests/fixtures/status-modified/history.json`` pins the
day for every shape that matters -- a renamed card, a card moved between
folders, a card changed since its last commit, a card never committed, a hub
that is not a repository -- and the CLI's suite (tkTestToolkit -PromptStatus)
asserts the same table against Get-PromptStatus.ps1.

And the card's own page: its design line is resolved against the design
listings, read ONCE per request and passed down to the lookup, and not at all
for a line that names no id.

Run:  python3 -m pytest Tests/test_status.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.ado import design as design_mod
    from agent.core import config
    from agent.core.git_history import folder_changes
    from agent.studio import notes as notes_mod
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "status-modified" / "history.json"
SPACE = "test"


def _noon(day: str) -> int:
    """Noon UTC of ``day``, as seconds: the same local day on any clock within 11 h of UTC."""
    return int(datetime.strptime(day, "%Y-%m-%d").replace(hour=12, tzinfo=UTC).timestamp())


def build_hub(hub: Path, scenario: dict) -> None:
    """The scenario's Space under ``hub``, as history.json's ``_`` describes it."""
    space = hub / SPACE
    for d in ("current", "backlog", "archive"):
        (space / d).mkdir(parents=True, exist_ok=True)

    def git(*args: str, day: str = "") -> None:
        env = dict(os.environ)
        if day:
            stamp = f"{_noon(day)} +0000"
            env.update(GIT_AUTHOR_DATE=stamp, GIT_COMMITTER_DATE=stamp)
        subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *args],
            cwd=hub,
            env=env,
            check=True,
            capture_output=True,
        )

    def write(rel: str, note: str) -> None:
        path = space / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"# {Path(rel).stem}\n\n{note}\n", encoding="utf-8")

    committed: set[str] = set()
    if scenario["repository"]:
        git("init", "-q")
        for commit in scenario["commits"]:
            for rel in commit.get("write", []):
                write(rel, f"written {commit['day']}")
                committed.add(rel)
            for old, new in commit.get("move", {}).items():
                (space / new).parent.mkdir(parents=True, exist_ok=True)
                git("mv", f"{SPACE}/{old}", f"{SPACE}/{new}")
                committed.discard(old)
                committed.add(new)
            git("add", "-A")
            git("commit", "-q", "-m", commit["day"], day=commit["day"])
        stale = _noon(scenario["staleMtime"])
        for rel in committed:
            os.utime(space / rel, (stale, stale))
    for item in scenario.get("uncommitted", []):
        write(item["write"], "on disk")
        stamp = _noon(item["mtime"])
        os.utime(space / item["write"], (stamp, stamp))


class StatusCase(unittest.TestCase):
    def setUp(self):
        self._hub = tempfile.TemporaryDirectory()
        self.hub = Path(self._hub.name)
        self._cfg = tempfile.TemporaryDirectory()
        base = Path(self._cfg.name)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": SPACE,
                    "commandPrefix": "tk",
                    "features": {},
                    "spaces": [{"slug": SPACE, "status": "local", "promptsFolder": SPACE}],
                    "commands": {},
                    "workItemTypes": {"Task": {"filePrefix": "Task"}, "Bug": {"filePrefix": ""}},
                }
            ),
            encoding="utf-8",
        )
        (base / "config.local.json").write_text(json.dumps({"promptsRoot": str(self.hub)}), encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in self.patches:
            p.start()
        from agent.app import app

        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self._cfg.cleanup()
        self._hub.cleanup()

    def read_status(self) -> tuple[dict[str, str], list[list[str]]]:
        """({file: modified}, every subprocess the read started)."""
        calls: list[list[str]] = []
        real = subprocess.run

        def counting(args, *a, **kw):
            calls.append(list(args))
            return real(args, *a, **kw)

        with mock.patch.object(subprocess, "run", counting):
            res = self.client.get("/api/status")
        self.assertEqual(res.status_code, 200, res.text)
        return {p["file"]: p["modified"] for p in res.json()["prompts"]}, calls


@unittest.skipUnless(shutil.which("git"), "git is not on PATH")
class TheModifiedDayTable(StatusCase):
    """history.json, every scenario and every row: the day, and the cost."""

    def test_every_row_reads_its_day(self):
        table = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(len(table["scenarios"]), 2)
        for scenario in table["scenarios"]:
            with self.subTest(scenario=scenario["name"]):
                for child in self.hub.iterdir():
                    shutil.rmtree(child) if child.is_dir() else child.unlink()
                build_hub(self.hub, scenario)
                days, calls = self.read_status()
                expected = {Path(row["card"]).name: row["day"] for row in scenario["expect"]}
                # Every card listed is a row, and every row is listed: archive/ and a
                # subfolder of current/ are not cards of this route.
                self.assertEqual(sorted(days), sorted(expected))
                for row in scenario["expect"]:
                    with self.subTest(card=row["card"]):
                        self.assertEqual(days[Path(row["card"]).name], row["day"], row["why"])
                git = [c for c in calls if c and c[0] == "git"]
                # ONE git call for every card in both folders, repository or not --
                # outside one it is the call that says so, and there is no probe.
                self.assertEqual(len(git), 1, git)
                self.assertEqual(git[0][git[0].index("--") + 1 :], ["current", "backlog"])
                self.assertEqual(len(calls), 1, calls)

    def test_one_git_call_for_many_cards(self):
        scenario = {
            "repository": True,
            "staleMtime": "2025-12-31",
            "commits": [{"day": "2026-04-01", "write": [f"current/Task{n}-card.prompt.md" for n in range(1, 41)]}],
        }
        build_hub(self.hub, scenario)
        days, calls = self.read_status()
        self.assertEqual(len(days), 40)
        self.assertEqual(set(days.values()), {"2026-04-01"})
        self.assertEqual([c[0] for c in calls], ["git"])

    def test_a_space_with_only_current_names_only_current(self):
        build_hub(self.hub, {"repository": False, "uncommitted": []})
        (self.hub / SPACE / "backlog").rmdir()
        (self.hub / SPACE / "current" / "Task1-x.prompt.md").write_text("# x\n", encoding="utf-8")
        _days, calls = self.read_status()
        self.assertEqual(calls[0][calls[0].index("--") + 1 :], ["current"])


@unittest.skipUnless(shutil.which("git"), "git is not on PATH")
class FolderChanges(unittest.TestCase):
    """The shared reader itself: keys, the subfolder rule, and None outside a clone."""

    def test_keys_are_relative_to_the_folder_and_a_subfolder_is_not_mixed_in(self):
        with tempfile.TemporaryDirectory() as tmp:
            hub = Path(tmp)
            build_hub(
                hub,
                {
                    "repository": True,
                    "staleMtime": "2025-12-31",
                    "commits": [{"day": "2026-05-01", "write": ["current/a.md", "current/sub/b.md", "backlog/c.md"]}],
                },
            )
            changes = folder_changes(hub / SPACE, ["current", "backlog"])
            self.assertEqual(sorted(changes), ["backlog/c.md", "current/a.md"])
            self.assertEqual(sorted(folder_changes(hub / SPACE / "current")), ["a.md"])

    def test_outside_a_clone_there_is_no_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(folder_changes(Path(tmp)))
            self.assertIsNone(folder_changes(Path(tmp) / "missing"))


DESIGN_ID = "ee925272-9564-4816-8944-e6b39c86339c"


def _listing(state: str, path: str) -> SimpleNamespace:
    doc = SimpleNamespace(path=path)
    return SimpleNamespace(designs=[SimpleNamespace(id=DESIGN_ID, state=state, spec=None, note=doc, title="Board")])


class TheCardsDesignIsReadOncePerRequest(StatusCase):
    """The detail route reads each design listing once, and passes it down."""

    def card(self, line: str) -> None:
        current = self.hub / SPACE / "current"
        current.mkdir(parents=True, exist_ok=True)
        (current / "Task1-x.prompt.md").write_text(f"# Task 1: X\n\n{line}\n\n## Branch\n", encoding="utf-8")

    def detail(self) -> tuple[dict, mock.Mock, mock.Mock]:
        repo_listing = mock.Mock(return_value=_listing("Design", "design/board.md"))
        hub_listing = mock.Mock(return_value=_listing("Complete", "design/archive/board.md"))

        async def gate():
            return "acme/kit"

        with (
            mock.patch.object(design_mod, "list_design", repo_listing),
            mock.patch.object(design_mod, "repo_gate", gate),
            mock.patch.object(notes_mod, "list_hub_designs", hub_listing),
        ):
            res = self.client.get("/api/status/Task1-x.prompt.md")
        self.assertEqual(res.status_code, 200, res.text)
        return res.json()["design"], repo_listing, hub_listing

    def test_a_repo_design_reads_each_listing_once(self):
        self.card(f"> Design: [Board](https://github.com/acme/kit/blob/HEAD/design/board.md) {DESIGN_ID}")
        found, repo_listing, hub_listing = self.detail()
        self.assertEqual((repo_listing.call_count, hub_listing.call_count), (1, 1))
        self.assertEqual((found["state"], found["where"], found["path"]), ("Design", "repo", "design/board.md"))

    def test_a_hub_design_reads_the_hub_listing_once_and_no_repo(self):
        self.card(f"> Design: [Board](../../design/board.md) {DESIGN_ID}")
        found, repo_listing, hub_listing = self.detail()
        self.assertEqual((repo_listing.call_count, hub_listing.call_count), (0, 1))
        self.assertEqual((found["state"], found["where"]), ("Complete", "hub"))

    def test_a_line_with_no_id_reads_no_listing(self):
        self.card("> Spec: [Board](../../spec/board.spec.md) the first cut")
        found, repo_listing, hub_listing = self.detail()
        self.assertEqual((repo_listing.call_count, hub_listing.call_count), (0, 0))
        self.assertEqual((found["kind"], found["state"]), ("spec", ""))


if __name__ == "__main__":
    unittest.main()
