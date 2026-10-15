"""Which orgs a person is OFFERED to pick from.

ONE table, two readers: this file runs agent/core/config.py's offered_spaces over
Tests/fixtures/offered-orgs/table.json, and Tests/Test-Config.ps1 runs
Scripts/Select-OfferedSpaces.ps1 over the same rows.

Run:  python3 -m pytest Tests/test_offered_spaces.py
"""

import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from agent.core.config import offered_spaces, space_keys  # noqa: E402

TABLE = json.loads((REPO_ROOT / "Tests" / "fixtures" / "offered-orgs" / "table.json").read_text(encoding="utf-8"))[
    "rows"
]


class TheOfferedOrgsRule(unittest.TestCase):
    def test_every_row_of_the_shared_table(self):
        for row in TABLE:
            with self.subTest(row["why"]):
                org = {"slug": "test", "example": row["example"]}
                active = "test" if row["active"] else "other"
                got = offered_spaces([org], active, row["dismissed"])
                self.assertEqual(bool(got), row["offered"])

    def test_order_is_kept_and_nothing_else_is_touched(self):
        orgs = [{"slug": "a"}, {"slug": "test", "example": True}, {"slug": "b"}]
        self.assertEqual([o["slug"] for o in offered_spaces(orgs, "a", True)], ["a", "b"])
        self.assertEqual([o["slug"] for o in offered_spaces(orgs, "a", False)], ["a", "test", "b"])

    def test_only_a_real_true_marks_the_example(self):
        """A string is not a flag: "false" must not hide an org."""
        self.assertEqual(len(offered_spaces([{"slug": "x", "example": "false"}], "a", True)), 1)

    def test_every_org_that_ships_is_marked_the_same_way(self):
        """The owner's rule: "whatever ships -- as example or demo -- follow the same pattern".
        The template org in config.default.json and the sample hub's Demo are both samples."""
        shipped = space_keys(json.loads((REPO_ROOT / "config.default.json").read_text(encoding="utf-8")))
        self.assertIs(shipped["isDemoDismissed"], False)
        self.assertEqual([o["slug"] for o in shipped["spaces"] if o.get("example") is True], ["azure-demo"])
        # The Azure demo: Example renamed and made honest -- local, no
        # address, so a cold machine's Environment card never reads it unreachable.
        azure = next(o for o in shipped["spaces"] if o["slug"] == "azure-demo")
        self.assertEqual((azure["name"], azure["status"], azure["org"]), ("Azure demo", "local", ""))
        # The sample hub is spelled `spaces` since the Space rename; the loader's own
        # canonicaliser reads either, and so does this test.
        sample = space_keys(json.loads((REPO_ROOT / "samples" / "hub" / "hub.json").read_text(encoding="utf-8")))
        # Demo and the GitHub demo: every Space the sample hub declares is a sample.
        self.assertEqual([o["slug"] for o in sample["spaces"] if o.get("example") is True], ["demo", "github-demo"])
        self.assertEqual(len(sample["spaces"]), 2)


if __name__ == "__main__":
    unittest.main()
