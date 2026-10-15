"""GET /api/surfaces: the inventory and the entries come from the CLI's resolver,
as one answer; a machine with no PowerShell gets a stated 503, not a guess; and
-- run for real when pwsh is here -- every surface carries a question and every
entry names a surface (the parity the CLI suite also holds, seen from the agent's
side). docs/CONFIGURATION.md, "Settings by workflow: the questions, and the one list behind them"; D-W1, D-W2."""

import shutil
import sys
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import surfaces
except Exception as e:  # pragma: no cover
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)

STUB = {
    "surfaces": [
        {
            "key": "promptsRoot",
            "title": "Your hub",
            "state": "on",
            "config": "tkConfig -Set promptsRoot=<folder>",
            "note": "/hub",
            "question": "Where do my cards live, and can I move them?",
        },
        {
            "key": "features.lounge",
            "title": "Lounge module",
            "state": "not configured",
            "config": "tkConfig -Set features.lounge=true",
            "note": "",
            "question": "Is there somewhere to look up from the work?",
        },
    ],
    "entries": [
        {
            "id": "cards-live",
            "question": "Where do my cards live, and can I move them?",
            "sentence": "s",
            "surfaces": ["promptsRoot"],
            "door": "change",
            "anchor": "promptsRoot",
        },
        {
            "id": "lounge",
            "question": "Is there somewhere to look up from the work?",
            "sentence": "s",
            "surfaces": ["features.lounge"],
            "door": "change",
            "anchor": "features.lounge",
            "tip": "Turn on the Lounge.",
        },
    ],
    "activeSpace": "toolkit",
    "prefix": "tk",
}


class TheRoute(unittest.TestCase):
    def setUp(self):
        surfaces.invalidate()

    def test_hands_the_resolver_answer_on_and_caches_it(self):
        with mock.patch.object(surfaces, "read_inventory", return_value=STUB) as read:
            a = client.get("/api/surfaces")
            b = client.get("/api/surfaces")
        self.assertEqual(a.status_code, 200)
        self.assertEqual(a.json()["surfaces"][0]["key"], "promptsRoot")
        self.assertEqual(a.json()["entries"][1]["tip"], "Turn on the Lounge.")
        self.assertEqual(b.json(), a.json())
        self.assertEqual(read.call_count, 1, "the second read within the TTL is the cache")

    def test_refresh_reads_again(self):
        with mock.patch.object(surfaces, "read_inventory", return_value=STUB) as read:
            client.get("/api/surfaces")
            client.get("/api/surfaces?refresh=1")
        self.assertEqual(read.call_count, 2)

    def test_no_powershell_is_a_stated_503(self):
        with mock.patch.object(surfaces, "read_inventory", return_value=None):
            r = client.get("/api/surfaces")
        self.assertEqual(r.status_code, 503)
        self.assertIn("PowerShell", r.json()["detail"])


@unittest.skipUnless(shutil.which("pwsh") or shutil.which("powershell"), "needs a PowerShell host")
class TheRealResolver(unittest.TestCase):
    def test_every_surface_has_a_question_and_every_entry_a_surface(self):
        surfaces.invalidate()
        data = surfaces.read_inventory()
        self.assertIsNotNone(data, "Get-P20SurfaceInventory did not answer")
        keys = [s["key"] for s in data["surfaces"]]
        self.assertEqual(keys[0], "promptsRoot")
        self.assertEqual(
            [s["key"] for s in data["surfaces"] if not s.get("question")], [], "a surface with no question"
        )
        for e in data["entries"]:
            for k in e["surfaces"]:
                self.assertIn(k, keys, f"entry {e['id']} names a surface the inventory does not have")
            self.assertIn(e["door"], ("change", "walk", "sentence"))
            if e["door"] == "change":
                self.assertTrue(e.get("anchor"), f"entry {e['id']}: change with no anchor")


if __name__ == "__main__":
    unittest.main()
