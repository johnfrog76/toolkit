"""The quarter's training line: a Space states a requirement, the agent adds up the hours.

``spaces[].features.trainingHoursPerQuarter`` is a Space-scoped key like
``sprintAwareness``. Unset, ``GET /api/growth`` answers
``trainingQuarter: null`` and the page draws nothing -- off means absent. Set, it
answers ``{quarter, hours, required, daysLeft, planned}``:

  * a training counts on its END date (``due_date``), inside today's calendar quarter;
  * a training with no parseable date is not counted;
  * ``complete`` hours are banked, ``new`` and ``active`` hours are planned;
  * the quarter's first and last days are inside it, the days either side are not.

Run directly:  python3 Tests/test_growth_quarter.py
Under pytest:  python3 -m pytest Tests/
"""

import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard and test_growth

from _skipguard import skip_module  # noqa: E402

try:
    from test_growth import _client

    from agent.core import config  # noqa: F401
    from agent.growth.growth import GrowthItem, space_training_hours, training_quarter
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")


def _training(due: str | None, hours: str | None, status: str = "complete") -> GrowthItem:
    return GrowthItem(
        filename=f"training-{due}.prompt.md",
        type="training",
        title="t",
        date=due or "",
        due_date=due,
        status=status,
        hours=hours,
    )


TODAY = date(2026, 8, 17)  # Q3 2026: 1 July - 30 September, 44 days left


class TrainingQuarterRule(unittest.TestCase):
    def test_no_requirement_is_none(self):
        self.assertIsNone(training_quarter([_training("2026-08-01", "4")], None, TODAY))
        self.assertIsNone(training_quarter([_training("2026-08-01", "4")], 0, TODAY))

    def test_the_answer_names_the_quarter_and_the_days_left(self):
        q = training_quarter([], 8, TODAY)
        self.assertEqual((q.quarter, q.hours, q.required, q.daysLeft, q.planned), ("Q3 2026", 0, 8, 44, 0))

    def test_hours_are_summed_only_inside_the_quarter(self):
        items = [
            _training("2026-07-10", "2"),
            _training("2026-09-01", "4"),
            _training("2026-06-30", "8"),  # Q2
            _training("2026-10-01", "8"),  # Q4
            _training("2025-08-10", "8"),  # a year ago
        ]
        q = training_quarter(items, 8, TODAY)
        self.assertEqual(q.hours, 6)

    def test_a_training_with_no_date_is_not_counted(self):
        q = training_quarter([_training(None, "8"), _training("2026-08-01", "3")], 8, TODAY)
        self.assertEqual(q.hours, 3)

    def test_the_quarters_first_and_last_days_are_inside_it(self):
        inside = training_quarter([_training("2026-07-01", "1"), _training("2026-09-30", "2")], 8, TODAY)
        self.assertEqual(inside.hours, 3)
        outside = training_quarter([_training("2026-06-30", "1"), _training("2026-10-01", "2")], 8, TODAY)
        self.assertEqual(outside.hours, 0)

    def test_the_boundary_is_the_calendar_quarter_not_the_fiscal_year(self):
        q1 = training_quarter([_training("2026-03-31", "5")], 8, date(2026, 1, 2))
        self.assertEqual((q1.quarter, q1.hours, q1.daysLeft), ("Q1 2026", 5, 88))
        q4 = training_quarter([_training("2026-12-31", "5")], 8, date(2026, 12, 31))
        self.assertEqual((q4.quarter, q4.hours, q4.daysLeft), ("Q4 2026", 5, 0))

    def test_only_complete_trainings_are_banked_the_rest_are_planned(self):
        items = [
            _training("2026-08-01", "6", "complete"),
            _training("2026-09-15", "4", "new"),
            _training("2026-09-20", "1.5", "active"),
        ]
        q = training_quarter(items, 8, TODAY)
        self.assertEqual((q.hours, q.planned), (6, 5.5))

    def test_hours_text_is_read_for_its_number(self):
        q = training_quarter(
            [_training("2026-08-01", "2.5 hours"), _training("2026-08-02", "TBA"), _training("2026-08-03", None)],
            8,
            TODAY,
        )
        self.assertEqual(q.hours, 2.5)

    def test_goals_and_talks_are_not_training(self):
        goal = GrowthItem(
            filename="goal-x.prompt.md",
            type="goal",
            title="g",
            date="",
            due_date="2026-08-01",
            status="complete",
            hours="9",
        )
        self.assertEqual(training_quarter([goal], 8, TODAY).hours, 0)


class TrainingQuarterRoute(unittest.TestCase):
    """GET /api/growth over a scratch hub, the requirement set on the active Space."""

    def _hub(self, dates_and_hours: list[tuple[str, str, str]]) -> Path:
        hub = Path(self._tmp.name)
        folder = hub / "growth" / "current"
        folder.mkdir(parents=True)
        for n, (due, hours, status) in enumerate(dates_and_hours):
            (folder / f"training-{due}-t{n}.prompt.md").write_text(
                f"# Training Artifact\n\n## Title\n\nT{n}\n\n## Date(s)\n\n{due}\n\n## Hours\n\n{hours}\n\n"
                f"## Status\n\n{status}\n",
                encoding="utf-8",
            )
        return hub

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._cleanup = []

    def tearDown(self):
        for p in reversed(self._cleanup):
            p.stop()
        self._tmp.cleanup()

    def _client(self, hub: Path, features: dict | None):
        space = {"slug": "test", "status": "local", "promptsFolder": "test"}
        if features is not None:
            space["features"] = features
        client, patches, tmp = _client(hub, extra_default={"spaces": [space]})
        self._cleanup += patches
        self._cleanup_tmp = tmp
        self.addCleanup(tmp.cleanup)
        return client

    def test_no_requirement_answers_null(self):
        hub = self._hub([(date.today().isoformat(), "4", "Complete")])
        body = self._client(hub, None).get("/api/growth").json()
        self.assertIsNone(body["trainingQuarter"])
        self.assertEqual(len(body["items"]), 1)

    def test_a_requirement_answers_the_quarter(self):
        today = date.today()
        year_ago = today - timedelta(days=366)
        hub = self._hub(
            [
                (today.isoformat(), "4", "Complete"),
                (year_ago.isoformat(), "8", "Complete"),
            ]
        )
        q = self._client(hub, {"trainingHoursPerQuarter": 8}).get("/api/growth").json()["trainingQuarter"]
        self.assertEqual((q["hours"], q["required"]), (4, 8))
        self.assertEqual(q["quarter"], f"Q{(today.month - 1) // 3 + 1} {today.year}")
        self.assertGreaterEqual(q["daysLeft"], 0)
        self.assertLessEqual(q["daysLeft"], 92)

    def test_a_requirement_that_is_not_a_positive_whole_number_is_no_requirement(self):
        hub = self._hub([(date.today().isoformat(), "4", "Complete")])
        for bad in (0, -3, True, "eight", None):
            with self.subTest(bad=bad):
                body = self._client(hub, {"trainingHoursPerQuarter": bad}).get("/api/growth").json()
                self.assertIsNone(body["trainingQuarter"])

    def test_the_number_does_not_leak_into_the_features_flags(self):
        # A Space states the number; the merged features map /env serves is flags only.
        hub = self._hub([])
        client = self._client(hub, {"trainingHoursPerQuarter": 8, "sprintAwareness": True})
        features = client.get("/api/env").json()["features"]
        self.assertNotIn("trainingHoursPerQuarter", features)
        self.assertIs(features["sprintAwareness"], True)
        self.assertEqual(space_training_hours(), 8)


if __name__ == "__main__":
    unittest.main()
