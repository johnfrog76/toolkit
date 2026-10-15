"""A review folder can belong to more than one org, and membership is a SET.

`reviews/<slug-set>/<year>/<start>_<end>/review.md`. The slug-set segment is
the sorted org slugs joined by `+`, so a review generated across two
engagements lives in one folder and surfaces under both of them.

The clause that needs a test rather than a comment is what "belongs to" means.
It is split-on-`+` set membership, not a substring search: `first` must not
match `firstclass`, and a folder named `first+second` must surface for `first`
and for `second` and for nobody else. A substring implementation passes every
happy-path example and quietly puts one engagement's review in another's list.

Carried from the package this was carved out of, with its slugs made neutral
and its imports pointed at where the code lives now: ``_scan_reviews`` and the
two slug-set readers are in ``agent/ado/reporting.py`` -- the engagement
reporting card was their first caller and still is -- while the routes that
serve this data are the growth module's.

Run directly:  python3 Tests/test_reviews_multi_org.py
Under pytest:  python3 -m pytest Tests/
"""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))

from agent.ado import reporting  # noqa: E402
from agent.growth.reviews import ReviewGenerateRequest  # noqa: E402


def _review(base: Path, slug_dir: str, year: str, date_range: str, body: str) -> Path:
    directory = base / "reviews" / slug_dir / year / date_range
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "review.md"
    path.write_text(body, encoding="utf-8")
    return path


def _frontmatter(orgs_line: str, title: str = "A review") -> str:
    return f"---\n{orgs_line}\nperiod: 2026-04-01_2026-04-30\ngenerator: scaffold\n---\n\n# {title}\n"


class _HubCase(unittest.TestCase):
    """Each test gets a throwaway hub; nothing touches a real one."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.hub = Path(self._tmp.name)
        # Both, because reporting reads the hub root directly for archive
        # folders and reads reviews/ through hub_folder -- the hub-root sibling
        # names are declared in hub.json now, not spelled at each use.
        self._patches = [
            mock.patch.object(reporting, "hub_root", lambda: self.hub),
            mock.patch.object(reporting, "hub_folder", lambda name: self.hub / name),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()


class SlugSetFromPathTests(_HubCase):
    def _slugs(self, slug_dir: str) -> list[str]:
        path = _review(self.hub, slug_dir, "2026", "2026-04-01_2026-04-30", _frontmatter("orgs: [x]"))
        return reporting._slug_set_from_path(path)

    def test_one_slug(self):
        self.assertEqual(self._slugs("first"), ["first"])

    def test_two_slugs_come_back_sorted(self):
        self.assertEqual(self._slugs("first+second"), ["first", "second"])

    def test_the_order_in_the_folder_name_does_not_matter(self):
        self.assertEqual(self._slugs("second+first"), ["first", "second"])

    def test_a_year_directory_is_not_a_slug_set(self):
        # A review written before slug-set folders existed sits directly under
        # reviews/<year>/, and its orgs come from the frontmatter instead.
        directory = self.hub / "reviews" / "2026" / "2026-04-01_2026-04-30"
        directory.mkdir(parents=True)
        path = directory / "review.md"
        path.write_text(_frontmatter("orgs: [first]"), encoding="utf-8")
        self.assertEqual(reporting._slug_set_from_path(path), [])


class SlugSetFromFrontmatterTests(_HubCase):
    def _slugs(self, orgs_line: str) -> list[str]:
        path = _review(self.hub, "2026", "x", "y", _frontmatter(orgs_line))
        return reporting._slug_set_from_frontmatter(path)

    def test_reads_the_orgs_list(self):
        self.assertEqual(self._slugs("orgs: [second, first]"), ["first", "second"])

    def test_still_reads_the_old_scalar_field(self):
        self.assertEqual(self._slugs("org: first"), ["first"])

    def test_the_list_wins_over_the_scalar(self):
        self.assertEqual(self._slugs("orgs: [first, second]\norg: third"), ["first", "second"])

    def test_no_frontmatter_at_all_is_not_an_error(self):
        path = _review(self.hub, "2026", "x", "y", "# Just a heading\n")
        self.assertEqual(reporting._slug_set_from_frontmatter(path), [])


class MembershipTests(_HubCase):
    """The clause the whole file exists for."""

    def setUp(self):
        super().setUp()
        _review(
            self.hub,
            "first+second",
            "2026",
            "2026-04-01_2026-04-30",
            _frontmatter("orgs: [first, second]", "Combined review"),
        )
        _review(self.hub, "first", "2026", "2026-03-01_2026-03-31", _frontmatter("orgs: [first]", "First only"))
        _review(
            self.hub,
            "firstclass",
            "2026",
            "2026-02-01_2026-02-28",
            _frontmatter("orgs: [firstclass]", "A different org entirely"),
        )

    def _titles(self, slug):
        return sorted(t for _f, _s, _e, t, _p, _o in reporting._scan_reviews(slug=slug))

    def test_a_combined_review_surfaces_under_its_first_org(self):
        self.assertIn("Combined review", self._titles("first"))

    def test_and_under_its_second(self):
        self.assertIn("Combined review", self._titles("second"))

    def test_and_under_neither_of_anyone_elses(self):
        self.assertNotIn("Combined review", self._titles("firstclass"))

    def test_a_slug_is_not_a_substring_of_another_slug(self):
        # 'first' must not drag in 'firstclass', and 'firstclass' must not
        # drag in 'first'.
        self.assertNotIn("A different org entirely", self._titles("first"))
        self.assertNotIn("First only", self._titles("firstclass"))

    def test_an_unknown_slug_matches_nothing(self):
        self.assertEqual(self._titles("nobody"), [])

    def test_no_slug_at_all_returns_every_review(self):
        self.assertEqual(len(reporting._scan_reviews(slug=None)), 3)

    def test_the_orgs_come_back_with_each_review(self):
        by_title = {t: o for _f, _s, _e, t, _p, o in reporting._scan_reviews(slug=None)}
        self.assertEqual(by_title["Combined review"], ["first", "second"])
        self.assertEqual(by_title["First only"], ["first"])

    def test_a_folder_that_is_not_a_date_range_is_not_a_review(self):
        _review(self.hub, "first", "2026", "notes", _frontmatter("orgs: [first]", "Not a review"))
        self.assertNotIn("Not a review", self._titles("first"))


class CountOrgReviewsUnreadableTests(_HubCase):
    """An unreadable review lists with empty fields, never the previous review's text.

    The old blind ``except Exception`` left ``text`` bound to the last review
    that DID read, so the unreadable one inherited its summary and tags. The
    narrowed ``except OSError`` resets it. A directory named ``review.md`` is
    unreadable on every host (PermissionError on Windows, IsADirectoryError
    elsewhere -- both OSError).
    """

    def test_an_unreadable_review_does_not_borrow_the_previous_ones_text(self):
        # Newest-first, so the 2026-05 review is read before the 2026-04 one.
        _review(
            self.hub,
            "first",
            "2026",
            "2026-05-01_2026-05-31",
            _frontmatter("orgs: [first]", "Readable") + "\nBuilt it in Python.\n",
        )
        broken = self.hub / "reviews" / "first" / "2026" / "2026-04-01_2026-04-30" / "review.md"
        broken.mkdir(parents=True)

        count, items = reporting._count_org_reviews("first")

        self.assertEqual(count, 2)
        by_period = {i["period"]: i for i in items}
        readable = by_period["2026-05-01 \u2013 2026-05-31"]
        unreadable = by_period["2026-04-01 \u2013 2026-04-30"]
        self.assertIn("Python", readable["tags"])
        self.assertEqual(unreadable["summary"], "")
        self.assertEqual(unreadable["tags"], [])


class ReviewGenerateRequestTests(unittest.TestCase):
    """The request model itself -- what the route is handed before it validates."""

    def test_slugs_default_to_an_empty_list_not_to_none(self):
        req = ReviewGenerateRequest(start_date="2026-04-01", end_date="2026-04-30")
        self.assertEqual(req.slugs, [])

    def test_a_list_of_slugs_survives_verbatim(self):
        req = ReviewGenerateRequest(start_date="2026-04-01", end_date="2026-04-30", slugs=["second", "first"])
        # Sorting is the route's job, not the model's: the model carries what
        # the caller said.
        self.assertEqual(req.slugs, ["second", "first"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
