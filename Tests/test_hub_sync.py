"""The hub's distance from its remote: /env's ``hubSync`` and POST /api/hub-sync/check.

The rules, each pinned here (agent/core/hub_sync.py; docs/CONFIGURATION.md,
"Syncing the hub from the web app"):

  * under any storeSync but git nothing runs, and the block says ``off``;
  * ``ahead`` is local and rides on /env; /env NEVER fetches;
  * ``behind`` and ``checkedAt`` are null until a fetch -- never "in step" by default;
  * a fetch happens only through the check route, once per TTL unless refreshed;
  * a failed fetch keeps the last count and its time, and says it failed;
  * the bridge forgets the ahead count after a verb runs.

The script itself is exercised end to end against a real remote at the foot,
where pwsh and git are on the machine.

Run directly:  python3 Tests/test_hub_sync.py
Under pytest:  python3 -m pytest Tests/
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.app import app
    from agent.core import env as env_route
    from agent.core import hub_sync
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

client = TestClient(app)


def _config(store_sync: str) -> dict:
    # A local Space: tier never probes a tracker, so /env runs nothing but this.
    return {
        "org": "",
        "status": "local",
        "activeSpace": "demo",
        "features": {},
        "storeSync": store_sync,
        "spaces": [{"slug": "demo", "name": "Demo", "status": "local"}],
    }


class _FakeRun:
    """Stands in for the script. Records every call; answers from ``answers``."""

    def __init__(self, ahead=1, behind=2):
        self.calls: list[bool] = []
        self.ahead = ahead
        self.behind = behind
        self.fetch_answer: dict | None = None

    def __call__(self, root: str, fetch: bool) -> dict:
        self.calls.append(fetch)
        if fetch and self.fetch_answer is not None:
            return dict(self.fetch_answer)
        return {
            "ahead": self.ahead,
            "behind": self.behind if fetch else None,
            "fetched": fetch,
            "fetchError": None,
            "error": None,
        }

    @property
    def fetches(self) -> int:
        return sum(1 for f in self.calls if f)

    @property
    def local_reads(self) -> int:
        return sum(1 for f in self.calls if not f)


class HubSyncCase(unittest.TestCase):
    store_sync = "git"

    def setUp(self):
        hub_sync.hub_sync_cache_clear()
        self.run = _FakeRun()
        self.patches = [
            mock.patch.object(hub_sync, "_run", self.run),
            mock.patch.object(hub_sync, "hub_root", lambda: PKG_ROOT),
            mock.patch.object(hub_sync, "load_config", lambda: _config(self.store_sync)),
            mock.patch.object(env_route, "load_config", lambda: _config(self.store_sync)),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        hub_sync.hub_sync_cache_clear()

    def env_block(self, **params) -> dict:
        r = client.get("/api/env", params=params)
        self.assertEqual(r.status_code, 200)
        return r.json()["hubSync"]

    def check(self, refresh: int = 0) -> dict:
        r = client.post("/api/hub-sync/check", params={"refresh": refresh})
        self.assertEqual(r.status_code, 200)
        return r.json()


class UnderNone(HubSyncCase):
    store_sync = "none"

    def test_env_says_off_and_carries_no_numbers(self):
        block = self.env_block()
        self.assertEqual(block["state"], "off")
        self.assertEqual(block["storeSync"], "none")
        for key in ("ahead", "behind", "checkedAt", "checkFailed", "error"):
            self.assertIsNone(block[key], key)

    def test_nothing_runs_not_even_on_a_check(self):
        self.env_block()
        self.assertEqual(self.check(refresh=1)["state"], "off")
        self.assertEqual(self.run.calls, [], "no child is started for a hub that is not git")


class UnderGit(HubSyncCase):
    def test_env_reports_ahead_and_has_not_checked_yet(self):
        block = self.env_block()
        self.assertEqual(block["state"], "on")
        self.assertEqual(block["ahead"], 1)
        # Not 0, not "in step": nothing has fetched, so behind is unknown.
        self.assertIsNone(block["behind"])
        self.assertIsNone(block["checkedAt"])
        self.assertFalse(block["checking"])

    def test_env_never_fetches(self):
        for _ in range(3):
            self.env_block()
        self.env_block(refresh=1)
        self.assertEqual(self.run.fetches, 0, "/env must never run git fetch")

    def test_env_holds_the_local_read_for_the_ttl(self):
        self.env_block()
        self.env_block()
        self.assertEqual(self.run.local_reads, 1, "a burst of page loads costs one read")
        self.env_block(refresh=1)
        self.assertEqual(self.run.local_reads, 2, "refresh=1 reads again")

    def test_check_fetches_and_stamps_the_time(self):
        block = self.check()
        self.assertEqual(self.run.fetches, 1)
        self.assertEqual(block["behind"], 2)
        self.assertEqual(block["ahead"], 1)
        self.assertIsNotNone(block["checkedAt"])
        self.assertIsNone(block["checkFailed"])
        # And /env now carries the last known state without fetching again.
        after = self.env_block()
        self.assertEqual((after["behind"], after["checkedAt"]), (2, block["checkedAt"]))
        self.assertEqual(self.run.fetches, 1)

    def test_a_second_check_inside_the_ttl_does_not_fetch_and_refresh_does(self):
        self.check()
        self.check()
        self.assertEqual(self.run.fetches, 1, "the page opened twice in a minute fetches once")
        self.check(refresh=1)
        self.assertEqual(self.run.fetches, 2, "Sync the hub fetches past the cache")

    def test_a_failed_fetch_keeps_the_last_count_and_its_time(self):
        first = self.check()
        self.run.fetch_answer = {
            "ahead": 1,
            "behind": None,
            "fetched": False,
            "fetchError": "fatal: unable to access 'https://example.invalid/hub.git/'",
            "error": None,
        }
        failed = self.check(refresh=1)
        self.assertEqual(failed["behind"], 2, "the last known count stays")
        self.assertEqual(failed["checkedAt"], first["checkedAt"], "and so does its time")
        self.assertIn("unable to access", failed["checkFailed"])
        # A fetch that then succeeds clears the failure.
        self.run.fetch_answer = None
        self.run.behind = 0
        ok = self.check(refresh=1)
        self.assertIsNone(ok["checkFailed"])
        self.assertEqual(ok["behind"], 0)

    def test_a_failed_first_fetch_still_has_not_checked(self):
        self.run.fetch_answer = {"runError": "the hub sync read did not answer (TimeoutExpired)"}
        block = self.check()
        self.assertIsNone(block["behind"])
        self.assertIsNone(block["checkedAt"])
        self.assertIn("TimeoutExpired", block["checkFailed"])

    def test_a_local_error_is_reported_not_raised(self):
        self.run.ahead = None
        with mock.patch.object(
            hub_sync, "_run", lambda root, fetch: {"ahead": None, "error": "fatal: no upstream configured"}
        ):
            block = self.env_block(refresh=1)
        self.assertEqual(block["state"], "on")
        self.assertIsNone(block["ahead"])
        self.assertIn("no upstream", block["error"])

    def test_the_bridge_forgets_the_ahead_count_after_a_verb(self):
        self.env_block()
        hub_sync.local_cache_clear()
        self.env_block()
        self.assertEqual(self.run.local_reads, 2)


def _tools():
    return shutil.which("pwsh") is not None and shutil.which("git") is not None


@unittest.skipIf(not _tools(), "pwsh or git is not on this machine")
class TheScriptAgainstARealRemote(unittest.TestCase):
    """Scripts/Get-HubSyncState.ps1, run the way the agent runs it."""

    def git(self, cwd: Path, *args: str) -> None:
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid"}
        env.update(GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
        subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, env=env)

    def setUp(self):
        hub_sync.hub_sync_cache_clear()
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.remote = self.tmp / "remote.git"
        self.hub = self.tmp / "hub"
        self.other = self.tmp / "other"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.remote)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.hub)], check=True)
        self.git(self.hub, "commit", "-q", "--allow-empty", "-m", "one")
        self.git(self.hub, "remote", "add", "origin", str(self.remote))
        self.git(self.hub, "push", "-q", "-u", "origin", "main")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        hub_sync.hub_sync_cache_clear()

    def test_ahead_locally_then_behind_after_a_fetch(self):
        self.git(self.hub, "commit", "-q", "--allow-empty", "-m", "mine")
        subprocess.run(["git", "clone", "-q", "-b", "main", str(self.remote), str(self.other)], check=True)
        for n in ("a", "b"):
            self.git(self.other, "commit", "-q", "--allow-empty", "-m", n)
        self.git(self.other, "push", "-q")

        local = hub_sync._run(str(self.hub), fetch=False)
        self.assertEqual(local["ahead"], 1)
        self.assertIsNone(local["behind"], "no fetch, no behind")

        fetched = hub_sync._run(str(self.hub), fetch=True)
        self.assertTrue(fetched["fetched"])
        self.assertEqual((fetched["ahead"], fetched["behind"]), (1, 2))

    def test_an_unreachable_remote_is_a_fetch_error_and_ahead_still_reads(self):
        self.git(self.hub, "remote", "set-url", "origin", str(self.tmp / "nowhere.git"))
        out = hub_sync._run(str(self.hub), fetch=True)
        self.assertFalse(out["fetched"])
        self.assertTrue(out["fetchError"])
        self.assertEqual(out["ahead"], 0)

    def test_a_folder_that_is_not_the_root_says_so(self):
        sub = self.hub / "sub"
        sub.mkdir()
        out = hub_sync._run(str(sub), fetch=False)
        self.assertIsNone(out["ahead"])
        self.assertIn("not the root of a git repository", out["error"])


if __name__ == "__main__":
    unittest.main()
