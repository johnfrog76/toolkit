"""GET /api/usage/burn -- the current Claude Code burn, and /env's claudeUsage flag.

docs/hub/usage.md, "Today and this week"; agent/core/usage.py. Holds:

1. The gate: ``claude_usage()`` over the shared table
   (Tests/fixtures/usage/projects-root.json, which tkTestToolkit -Burn asserts
   from the CLI's inventory row too), carried on /env under consts.json
   ``usage.envFlag``; and the route is 404 where it is false -- no verb run.
2. One reader: the route runs ``Burn -AsJson`` through the bridge's runner,
   by the function the CLI's command table names, and serves what it printed.
3. The cache: an hour on disk, keyed by the hub and the config files; never past the verb's own
   ``nextBoundaryAt``; ``?refresh=1`` goes past it; a failed read is not kept.
4. The burndown: served as the verb answered it; a new typed reading in
   ``usage/<readingsFolder>/`` is a miss at once; never served past its ``renewsAt``.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import config as config_mod
    from agent.core import usage
    from agent.core.consts import usage_burn_route, usage_env_flag, usage_readings_folder
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

ROOT = Path(__file__).resolve().parent
TABLE = json.loads((ROOT / "fixtures" / "usage" / "projects-root.json").read_text(encoding="utf-8"))


def _iso(dt: datetime) -> str:
    return dt.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _answer(boundary_in: timedelta = timedelta(hours=6), renews_in: timedelta = timedelta(hours=3)) -> dict:
    now = datetime.now(UTC)
    return {
        "burn": 1,
        "machine": "build-box",
        "asOf": _iso(now),
        "weekStarts": "Friday 05:00 local",
        "nextBoundaryAt": _iso(now + boundary_in),
        "today": {"totals": {"messages": 3, "costUsdDerived": 0.5}, "byModel": [], "machines": []},
        "week": {"totals": {"messages": 9, "costUsdDerived": 1.5}, "byModel": [], "machines": []},
        "cost": {"derived": True, "priceNotes": []},
        "burndown": {
            "product": "claude",
            "cacheHours": 4,
            "cachedAt": _iso(now - timedelta(hours=1)),
            "renewsAt": _iso(now + renews_in),
            "due": False,
            "buckets": [{"key": "general", "label": "General", "percent": 43, "pace": 60, "gap": -17}],
        },
    }


class TheGateIsOneTable(unittest.TestCase):
    """claude_usage() is the inventory row's rule, row for row."""

    def test_every_row(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            for row in TABLE["rows"]:
                folder = Path(tmp) / row["dir"]
                if row["projects"] != "absent":
                    folder.mkdir(parents=True, exist_ok=True)
                if row["projects"] == "folder":
                    (folder / "projects").mkdir(exist_ok=True)
                elif row["projects"] == "file":
                    (folder / "projects").write_text("not a folder", encoding="utf-8")
                value = f"  {folder}  " if row["pad"] else str(folder)
                with mock.patch.dict("os.environ", {"CLAUDE_CONFIG_DIR": value}):
                    self.assertIs(config_mod.claude_usage(), row["on"], row["name"])

    def test_unset_reads_the_home_folder(self):
        with mock.patch.dict("os.environ", {}, clear=False) as env:
            env.pop("CLAUDE_CONFIG_DIR", None)
            self.assertEqual(config_mod.claude_projects_root(), Path.home() / ".claude" / "projects")


class EnvCarriesTheFlag(unittest.TestCase):
    def test_true_and_false_by_the_contract_name(self):
        self.assertEqual(usage_env_flag(), "claudeUsage")
        client = TestClient(app)
        for on in (True, False):
            with mock.patch("agent.core.env.claude_usage", return_value=on):
                body = client.get("/api/env").json()
            self.assertIs(body[usage_env_flag()], on)


class TheRoute(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.path = usage_burn_route()
        self.calls: list[tuple[str, list[str]]] = []
        self.reply = _answer()
        self.code = 0
        patches = [
            mock.patch("agent.core.usage.claude_usage", return_value=True),
            mock.patch("agent.ado.bridge.command_map", return_value={"Burn": "Invoke-P20Burn"}),
            mock.patch("agent.ado.bridge._run", side_effect=self._run),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _run(self, function, params, timeout, extra_env=None):
        self.calls.append((function, list(params)))
        out = "  a warning on the way up\n" + json.dumps(self.reply, indent=2) if self.code == 0 else ""
        err = "Error: it refused" if self.code else ""
        return subprocess.CompletedProcess(["pwsh"], self.code, stdout=out, stderr=err)

    def test_the_route_is_the_contract_path(self):
        self.assertEqual(self.path, "/api/usage/burn")

    def test_404_where_there_are_no_session_files_and_no_verb_runs(self):
        with mock.patch("agent.core.usage.claude_usage", return_value=False):
            res = self.client.get(self.path)
        self.assertEqual(res.status_code, 404)
        self.assertEqual(self.calls, [])

    def test_one_reader_burn_asjson_through_the_bridge(self):
        body = self.client.get(self.path).json()
        self.assertEqual(self.calls, [("Invoke-P20Burn", ["-AsJson"])])
        self.assertEqual(body["week"]["totals"]["messages"], 9)
        self.assertIs(body["fromCache"], False)
        self.assertTrue(body["fetchedAt"].endswith("Z"))

    def test_kept_for_the_hour_then_refresh_goes_past_it(self):
        first = self.client.get(self.path).json()
        second = self.client.get(self.path).json()
        self.assertEqual(len(self.calls), 1, "the second read is the disk's")
        self.assertIs(second["fromCache"], True)
        self.assertEqual(second["fetchedAt"], first["fetchedAt"])
        third = self.client.get(f"{self.path}?refresh=1").json()
        self.assertEqual(len(self.calls), 2)
        self.assertIs(third["fromCache"], False)

    def test_an_hour_old_reading_is_read_again(self):
        self.client.get(self.path)
        later = time.time() + usage.BURN_TTL_SECONDS + 1
        with mock.patch("agent.core.usage.time.time", return_value=later):
            self.client.get(self.path)
        self.assertEqual(len(self.calls), 2)

    def test_never_served_past_its_own_boundary(self):
        # A reading taken at 23:59 is not today's at 00:01, whatever its age.
        self.reply = _answer(boundary_in=timedelta(minutes=1))
        self.client.get(self.path)
        later = time.time() + 120
        with mock.patch("agent.core.usage.time.time", return_value=later):
            self.client.get(self.path)
        self.assertEqual(len(self.calls), 2)

    def test_another_hub_is_a_miss(self):
        self.client.get(self.path)
        with mock.patch("agent.core.usage.hub_root", return_value=Path("/elsewhere/hub")):
            self.client.get(self.path)
        self.assertEqual(len(self.calls), 2)

    def test_a_config_change_is_a_miss(self):
        # Config -Set burn.weekStarts changes config.local.json; the agent never
        # reads the key, it notices the file changed.
        self.client.get(self.path)
        with mock.patch("agent.core.usage._inputs", return_value="another config"):
            self.client.get(self.path)
        self.assertEqual(len(self.calls), 2)

    def test_the_burndown_is_the_verbs(self):
        body = self.client.get(self.path).json()
        self.assertEqual(body["burndown"]["buckets"][0]["gap"], -17)
        self.assertEqual(body["burndown"]["cacheHours"], 4)

    def test_a_new_reading_is_a_miss(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            usage_dir = Path(tmp)
            readings = usage_dir / usage_readings_folder()
            with mock.patch("agent.core.usage.hub_folder", return_value=usage_dir):
                self.client.get(self.path)
                self.client.get(self.path)
                self.assertEqual(len(self.calls), 1, "nothing changed: the disk's")
                readings.mkdir()
                (readings / "2026-11-06-build-box.json").write_text(
                    '{"readings": 1, "entries": []}\n', encoding="utf-8"
                )
                self.assertIs(self.client.get(self.path).json()["fromCache"], False)
                self.assertEqual(len(self.calls), 2)

    def test_never_served_past_its_renewal(self):
        # The kept answer said "not due"; once renewsAt passes, that is no longer true.
        self.reply = _answer(renews_in=timedelta(minutes=1))
        self.client.get(self.path)
        later = time.time() + 120
        with mock.patch("agent.core.usage.time.time", return_value=later):
            self.client.get(self.path)
        self.assertEqual(len(self.calls), 2)

    def test_a_failed_read_says_why_and_is_not_kept(self):
        self.code = 2
        res = self.client.get(self.path)
        self.assertEqual(res.status_code, 502)
        self.assertIn("it refused", res.json()["detail"])
        self.code = 0
        self.assertEqual(self.client.get(self.path).json()["fromCache"], False)
        self.assertEqual(len(self.calls), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
