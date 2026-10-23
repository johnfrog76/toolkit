"""The first run's board, as the agent serves it from the sample hub.

``docs/QUICKSTART.md``, "The first run: one command": a fresh ``Start`` copies
``samples/hub`` out, and the Demo board holds five tutorial cards -- the first in
Backlog, the other four in To do, nothing else in To do -- so the lane can empty
as they are walked. ``Tests/Test-Start.ps1`` holds the same set through the CLI
(and walks each lesson's act); this holds what ``GET /api/status`` and
``GET /api/env`` serve for it, from an untouched copy, with the shipped config.

Run:  python3 -m pytest Tests/test_first_run.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.core.consts import consts
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

PKG_ROOT = Path(__file__).resolve().parent.parent

# The set, in the order it is walked: filename and the lane a fresh Start shows.
TUTORIAL = [
    ("TaskH3RE-start-here-pull-me-onto-the-board.prompt.md", "backlog"),
    ("TaskT6CK-open-me-and-tick-my-boxes.prompt.md", "active"),
    ("Spike-F7ND-find-out-one-thing-and-write-it-down.prompt.md", "active"),
    ("US-R3VU-say-look-at-this.prompt.md", "active"),
    ("D9NE-drop-me-on-done.prompt.md", "active"),
]


class AFreshStartsBoard(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.hub = base / "hub"
        shutil.copytree(PKG_ROOT / "samples" / "hub", self.hub)
        # What Start writes: the hub, and Demo active. The shipped config is the default.
        local = base / "config.local.json"
        local.write_text(json.dumps({"promptsRoot": str(self.hub), "activeSpace": "demo"}), encoding="utf-8")
        self._patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", PKG_ROOT / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self._patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        from agent.app import app

        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        self._tmp.cleanup()

    def test_the_first_card_is_in_backlog_and_the_other_four_in_active(self):
        served = {p["file"]: p["status"] for p in self.client.get("/api/status").json()["prompts"]}
        for name, lane in TUTORIAL:
            self.assertEqual(served.get(name), consts()["status"][lane], name)

    def test_nothing_else_is_active_so_the_to_do_lane_can_empty(self):
        tutorial = {name for name, _ in TUTORIAL}
        others = [
            p["file"]
            for p in self.client.get("/api/status").json()["prompts"]
            if p["status"] == consts()["status"]["active"] and p["file"] not in tutorial
        ]
        self.assertEqual(others, [])

    def test_demo_calls_active_to_do_and_backlog_keeps_its_name(self):
        names = self.client.get("/api/env").json()["config"]["laneNames"]
        self.assertEqual(names.get(consts()["status"]["active"]), "To do")
        # Demo's laneNames name no Backlog, so it keeps the contract's word.
        backlog = consts()["status"]["backlog"]
        self.assertEqual(names.get(backlog, backlog), backlog)


if __name__ == "__main__":
    unittest.main()
