"""The agent's disk cache is capped (``agent/core/disk_cache.py``, prune_seen and
prune_folder; the cap is ``config.AGENT_CACHE_MAX_RECORDS`` and
``AGENT_CACHE_MAX_AGE_DAYS``).

Two things grow one record per thing ever read: the rows cache
(``rows/<reader>.json``, one record per blob sha) and the standup's dress cache
(``standup-dress-1/``, one file per reply). Both are pruned on write, unseen for
the age or past the count, oldest-unseen first, and a prune that errors leaves the
cache as it was. The tests point the cache at a scratch folder (conftest.py).

Run:  python3 -m pytest Tests/test_cache_prune.py
"""

import os
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from agent.ado import repo_read
    from agent.core import config, disk_cache
except Exception as exc:  # pragma: no cover
    skip_module(f"the agent's dependencies are not installed: {exc}")

DAY = disk_cache.SECONDS_PER_DAY
NS = "prune-test-1"


def sha(n: int) -> str:
    return f"{n:040x}"


def stored() -> tuple[dict, dict]:
    data = disk_cache.get_json(repo_read.ROWS_DIR, f"{NS}.json") or {}
    return data.get("rows") or {}, data.get("seen") or {}


class TheCapIsOneRule(unittest.TestCase):
    def test_the_numbers_are_the_configs(self):
        self.assertEqual(config.AGENT_CACHE_MAX_RECORDS, 3000)
        self.assertEqual(config.AGENT_CACHE_MAX_AGE_DAYS, 30)


class PruneSeen(unittest.TestCase):
    def test_past_the_count_the_oldest_unseen_go(self):
        now = 1_000_000_000.0
        records = {f"k{i}": {"i": i} for i in range(10)}
        seen = {f"k{i}": now - i * 60 for i in range(10)}  # k0 is the newest
        kept, stamps = disk_cache.prune_seen(records, seen, now=now, max_records=4)
        self.assertEqual(sorted(kept), ["k0", "k1", "k2", "k3"])
        self.assertEqual(sorted(stamps), sorted(kept))

    def test_an_entry_past_the_age_is_pruned_and_a_recent_one_survives(self):
        now = 1_000_000_000.0
        records = {"old": {}, "recent": {}, "edge": {}}
        seen = {"old": now - 31 * DAY, "recent": now - 1 * DAY, "edge": now - 29 * DAY}
        kept, _ = disk_cache.prune_seen(records, seen, now=now, max_age_days=30)
        self.assertEqual(sorted(kept), ["edge", "recent"])

    def test_a_record_with_no_stamp_is_stamped_now_not_dropped(self):
        now = 1_000_000_000.0
        kept, stamps = disk_cache.prune_seen({"legacy": {}}, {}, now=now)
        self.assertEqual(kept, {"legacy": {}})
        self.assertEqual(stamps, {"legacy": now})

    def test_a_prune_that_errors_returns_its_input(self):
        records, seen = {"a": {}}, {"a": 1.0}
        with mock.patch.object(disk_cache, "time") as clock:
            clock.time.side_effect = RuntimeError("boom")
            self.assertEqual(disk_cache.prune_seen(records, seen), (records, seen))


class TheRowsCache(unittest.TestCase):
    def test_filling_past_the_cap_reads_back_under_it_oldest_unseen_gone(self):
        with (
            mock.patch.object(disk_cache, "AGENT_CACHE_MAX_RECORDS", 5),
            mock.patch.object(
                disk_cache.prune_seen, "__kwdefaults__", {**disk_cache.prune_seen.__kwdefaults__, "max_records": 5}
            ),
        ):
            for n in range(8):
                with mock.patch.object(repo_read.time, "time", return_value=1_000_000.0 + n):
                    repo_read._save_rows(NS, {sha(n): {"n": n}})
        rows, seen = stored()
        self.assertEqual(len(rows), 5)
        self.assertEqual(sorted(rows), [sha(n) for n in range(3, 8)])
        self.assertEqual(sorted(seen), sorted(rows))

    def test_a_row_seen_again_outlives_one_that_was_not(self):
        now = time.time()
        with mock.patch.object(repo_read.time, "time", return_value=now - 10 * DAY):
            repo_read._save_rows(NS, {sha(1): {"n": 1}, sha(2): {"n": 2}})
        # Day 10: sha(1) is a hit on a read; sha(2) is not.
        with mock.patch.object(repo_read.time, "time", return_value=now - 1 * DAY):
            repo_read._save_rows(NS, {}, {sha(1)})
        rows, seen = stored()
        self.assertEqual(sorted(rows), [sha(1), sha(2)])
        self.assertGreater(seen[sha(1)], seen[sha(2)])
        # Thirty-one days after sha(2) was last seen, only the hit remains.
        with mock.patch.object(repo_read.time, "time", return_value=now + 21 * DAY):
            repo_read._save_rows(NS, {sha(3): {"n": 3}})
        rows, _ = stored()
        self.assertEqual(sorted(rows), [sha(1), sha(3)])

    def test_a_fresh_hit_does_not_rewrite_the_file(self):
        repo_read._save_rows(NS, {sha(1): {"n": 1}})
        with mock.patch.object(disk_cache, "put_json") as put:
            repo_read._save_rows(NS, {}, {sha(1)})
        put.assert_not_called()

    def test_a_prune_error_leaves_the_rows_and_the_write_stands(self):
        repo_read._save_rows(NS, {sha(1): {"n": 1}})
        with mock.patch.object(disk_cache, "AGENT_CACHE_MAX_RECORDS", "not a number"):
            repo_read._save_rows(NS, {sha(2): {"n": 2}})
        rows, _ = stored()
        self.assertEqual(sorted(rows), [sha(1), sha(2)])


class TheDressFolder(unittest.TestCase):
    FOLDER = "standup-dress-1"

    def _put(self, name: str, age_days: float = 0.0, now: float | None = None) -> Path:
        self.assertTrue(disk_cache.put_json({"reply": {"a": name}}, self.FOLDER, f"{name}.json"))
        path = disk_cache.cache_path(self.FOLDER, f"{name}.json")
        stamp = (time.time() if now is None else now) - age_days * DAY
        os.utime(path, (stamp, stamp))
        return path

    def _names(self) -> list[str]:
        return sorted(p.stem for p in disk_cache.cache_path(self.FOLDER).iterdir())

    def test_past_the_count_the_oldest_unseen_files_go(self):
        now = time.time()
        for n in range(8):
            self._put(f"k{n}", age_days=n, now=now)  # k0 newest
        gone = disk_cache.prune_folder(self.FOLDER, now=now, max_records=5)
        self.assertEqual(gone, 3)
        self.assertEqual(self._names(), [f"k{n}" for n in range(5)])

    def test_a_file_past_the_age_is_pruned_and_a_recent_one_survives(self):
        now = time.time()
        self._put("old", age_days=31, now=now)
        self._put("recent", age_days=2, now=now)
        disk_cache.prune_folder(self.FOLDER, now=now)
        self.assertEqual(self._names(), ["recent"])

    def test_a_touched_file_survives_what_an_untouched_one_does_not(self):
        now = time.time()
        self._put("hit", age_days=40, now=now)
        self._put("miss", age_days=40, now=now)
        disk_cache.touch(self.FOLDER, "hit.json")
        disk_cache.prune_folder(self.FOLDER, now=now)
        self.assertEqual(self._names(), ["hit"])

    def test_a_write_in_flight_is_not_a_record(self):
        now = time.time()
        folder = disk_cache.cache_path(self.FOLDER)
        folder.mkdir(parents=True)
        tmp = folder / ".k.json.abc"
        tmp.write_text("{}")
        os.utime(tmp, (now - 90 * DAY, now - 90 * DAY))
        disk_cache.prune_folder(self.FOLDER, now=now)
        self.assertTrue(tmp.exists())

    def test_a_prune_error_leaves_the_folder_as_it_was(self):
        now = time.time()
        for n in range(3):
            self._put(f"k{n}", age_days=60, now=now)
        with mock.patch.object(disk_cache.os, "scandir", side_effect=OSError("denied")):
            self.assertEqual(disk_cache.prune_folder(self.FOLDER, now=now), 0)
        self.assertEqual(self._names(), ["k0", "k1", "k2"])

    def test_a_missing_folder_is_nothing_to_prune(self):
        self.assertEqual(disk_cache.prune_folder(self.FOLDER), 0)


if __name__ == "__main__":
    unittest.main()
