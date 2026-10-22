"""The tier probe is keyed by what it asks, and concurrent misses share one probe (PAN7).

A GitHub probe is ``gh api users/<owner>``: it does not depend on the
repository, so one answer serves every Space under an owner. A cold page that
asks for ten Spaces at once used to start ten probes (and, across several
routes, thirty-five); it now starts one per owner. Everything here runs against
a STUBBED probe -- no ``gh`` and no ``az``.

Run directly:  python3 Tests/test_tier_probe_merge.py
Under pytest:  python3 -m pytest Tests/
"""

import sys
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent.core import tier
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the agent ({type(e).__name__}: {e})")


def _slow(counter, seconds=0.2, answer=True):
    def probe(_url):
        counter.append(_url)
        time.sleep(seconds)
        return answer

    return probe


def _ask_all(urls, **kw):
    with ThreadPoolExecutor(max_workers=len(urls)) as pool:
        return list(pool.map(lambda u: tier._probe_tracker_cached(u, **kw), urls))


class TheKeyIsWhatTheProbeAsks(unittest.TestCase):
    def test_a_github_address_is_keyed_by_its_owner_alone(self):
        key = tier._probe_key
        self.assertEqual(key("https://github.com/Owner/one"), key("https://github.com/owner/two"))
        self.assertEqual(key("https://github.com/owner"), key("https://github.com/owner/one"))
        self.assertNotEqual(key("https://github.com/owner/one"), key("https://github.com/other/one"))

    def test_an_ado_address_keeps_its_url(self):
        self.assertEqual(tier._probe_key("https://dev.azure.com/one"), "https://dev.azure.com/one")
        self.assertNotEqual(tier._probe_key("https://dev.azure.com/one"), tier._probe_key("https://dev.azure.com/two"))

    def test_an_owner_less_github_address_falls_back_to_the_url(self):
        self.assertEqual(tier._probe_key("https://github.com"), "https://github.com")

    def test_an_ado_org_named_like_a_github_owner_is_a_different_key(self):
        self.assertNotEqual(tier._probe_key("https://github.com/acme"), tier._probe_key("https://dev.azure.com/acme"))


class ConcurrentMissesShareOneProbe(unittest.TestCase):
    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_n_spaces_under_one_owner_asked_at_once_make_one_probe(self):
        seen = []
        urls = [f"https://github.com/owner/repo{i}" for i in range(10)]
        with mock.patch.object(tier, "_probe_github", _slow(seen)):
            answers = _ask_all(urls)
        self.assertEqual(len(seen), 1, f"ten Spaces, one owner: {len(seen)} probes")
        self.assertEqual(answers, [True] * 10)

    def test_two_owners_make_two_probes(self):
        seen = []
        urls = [f"https://github.com/{o}/repo{i}" for o in ("alpha", "beta") for i in range(5)]
        with mock.patch.object(tier, "_probe_github", _slow(seen)):
            _ask_all(urls)
        self.assertEqual(len(seen), 2)
        self.assertEqual({tier.tracker_owner(u) for u in seen}, {"alpha", "beta"})

    def test_a_sequential_ask_for_a_sibling_space_reads_the_cache(self):
        seen = []
        with mock.patch.object(tier, "_probe_github", _slow(seen, 0)):
            tier._probe_tracker_cached("https://github.com/owner/one")
            tier._probe_tracker_cached("https://github.com/owner/two")
        self.assertEqual(len(seen), 1)

    def test_a_negative_answer_is_shared_and_held_like_any_other(self):
        seen = []
        urls = [f"https://github.com/owner/repo{i}" for i in range(6)]
        with mock.patch.object(tier, "_probe_github", _slow(seen, 0.1, answer=False)):
            answers = _ask_all(urls)
            again = tier._probe_tracker_cached(urls[0])
        self.assertEqual(len(seen), 1)
        self.assertEqual(answers, [False] * 6)
        self.assertIs(again, False)

    def test_azure_devops_misses_on_one_org_merge_too(self):
        seen = []
        urls = ["https://dev.azure.com/one"] * 4 + ["https://dev.azure.com/two"] * 4
        with mock.patch.object(tier, "_probe_ado", _slow(seen)):
            _ask_all(urls)
        self.assertEqual(sorted(seen), ["https://dev.azure.com/one", "https://dev.azure.com/two"])

    def test_refresh_joins_a_probe_that_is_already_running(self):
        seen = []
        started = threading.Event()

        def probe(url):
            seen.append(url)
            started.set()
            time.sleep(0.3)
            return True

        with mock.patch.object(tier, "_probe_github", probe), ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(tier._probe_tracker_cached, "https://github.com/owner/a")
            started.wait(5)
            second = pool.submit(tier._probe_tracker_cached, "https://github.com/owner/b", True)
            self.assertTrue(first.result() and second.result())
        self.assertEqual(len(seen), 1)

    def test_refresh_alone_goes_past_the_cache(self):
        seen = []
        with mock.patch.object(tier, "_probe_github", _slow(seen, 0)):
            tier._probe_tracker_cached("https://github.com/owner/a")
            tier._probe_tracker_cached("https://github.com/owner/b", refresh=True)
        self.assertEqual(len(seen), 2)


class AProbeThatRaisedIsNotKept(unittest.TestCase):
    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_every_caller_of_the_failed_probe_gets_its_error_and_the_next_ask_retries(self):
        seen = []

        def boom(url):
            seen.append(url)
            time.sleep(0.2)
            raise RuntimeError("probe blew up")

        urls = [f"https://github.com/owner/repo{i}" for i in range(5)]
        with mock.patch.object(tier, "_probe_github", boom), ThreadPoolExecutor(max_workers=5) as pool:
            futures = [pool.submit(tier._probe_tracker_cached, u) for u in urls]
            errors = [f.exception() for f in futures]
        self.assertEqual(len(seen), 1, "the failure was not shared by the callers that waited on it")
        self.assertTrue(all(isinstance(e, RuntimeError) for e in errors), errors)
        self.assertFalse(tier._probe_cache, "a probe that raised was cached")
        self.assertFalse(tier._probe_flights, "a finished flight was left behind")

        with mock.patch.object(tier, "_probe_github", _slow(seen, 0)):
            self.assertTrue(tier._probe_tracker_cached(urls[0]))
        self.assertEqual(len(seen), 2, "the next ask did not probe again")

    def test_the_failure_does_not_reach_a_caller_that_arrives_after_it(self):
        def boom(_url):
            raise RuntimeError("once")

        with mock.patch.object(tier, "_probe_github", boom), self.assertRaises(RuntimeError):
            tier._probe_tracker_cached("https://github.com/owner/a")
        with mock.patch.object(tier, "_probe_github", return_value=True):
            self.assertTrue(tier._probe_tracker_cached("https://github.com/owner/a"))


class TheTtlStillExpires(unittest.TestCase):
    def setUp(self):
        tier.probe_cache_clear()

    def tearDown(self):
        tier.probe_cache_clear()

    def test_an_expired_owner_answer_is_probed_again(self):
        seen = []
        with mock.patch.object(tier, "_probe_github", _slow(seen, 0)):
            tier._probe_tracker_cached("https://github.com/owner/a")
            tier._probe_tracker_cached("https://github.com/owner/b")
            self.assertEqual(len(seen), 1)
            with mock.patch.object(tier, "ADO_PROBE_TTL_SECONDS", 0):
                tier._probe_tracker_cached("https://github.com/owner/c")
        self.assertEqual(len(seen), 2)

    def test_clearing_the_cache_forgets_the_owner(self):
        seen = []
        with mock.patch.object(tier, "_probe_github", _slow(seen, 0)):
            tier._probe_tracker_cached("https://github.com/owner/a")
            tier.probe_cache_clear()
            tier._probe_tracker_cached("https://github.com/owner/a")
        self.assertEqual(len(seen), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
