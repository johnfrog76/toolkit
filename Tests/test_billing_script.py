"""agent/ado/Get-WeeklyBilling.ps1, run for real against a scratch git hub.

The script once had no test at all, which is how two defects sat in
it from the day the orgs moved into the hub:

  - it resolved the active Space from config.default.json only, so an org the HUB
    declares -- which every real org is -- had no folder, git was asked about
    current/ and archive/ at the hub root, and a week of commits read as
    "no activity";
  - that early no-activity exit printed prose under -AsJson, and the agent
    reported it to the browser as a JSON parse error.

These run the script the way agent/ado/reporting.py does: a child PowerShell,
-PromptsRoot, -PromptsFolder and -AsJson, stdout parsed as JSON. The Space is
the caller's to resolve, so the first defect above cannot come back: the script
reads no Space at all. The package's own config files are NOT touched: the
script reads its work item types from config.local.json beside itself, so each
case runs a COPY of the script from a scratch package with its own config.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard
from _rmtree import remove_tree
from _shortpath import short_path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "agent" / "ado" / "Get-WeeklyBilling.ps1"
HAVE_PWSH = shutil.which("pwsh") is not None
HAVE_GIT = shutil.which("git") is not None


# A fixed WEDNESDAY, and the week around it. Billing renders weekdays only, so a
# card committed "now" is invisible when "now" is a Saturday -- which is exactly
# how these tests, green on the Friday they were written, went red the next
# morning. A test about billing must not depend on the day it runs:
# every commit is dated WORK_DAY, and the script is asked for WEEK.
WORK_DAY = "2026-09-16T12:00:00"
WEEK = ("-Since", "2026-09-14", "-Until", "2026-09-18")


def _git(cwd, *args, when: str = WORK_DAY, committed: str | None = None):
    import os

    env = dict(os.environ, GIT_AUTHOR_DATE=when, GIT_COMMITTER_DATE=committed or when)
    subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )


def _scratch_package(root: Path, local_config: dict) -> Path:
    """A package just big enough for the script: itself, the scripts it
    dot-sources, a shipped config and a local config (read for the work item
    types only -- the Space is the caller's to resolve)."""
    (root / "agent" / "ado").mkdir(parents=True)
    (root / "Scripts").mkdir()
    shutil.copy(SCRIPT, root / "agent" / "ado" / SCRIPT.name)
    # The billing script reads cards with the ONE id rule and the contract file.
    for name in (
        "Get-Consts.ps1",
        "Resolve-CardName.ps1",
        "ConvertTo-LocalDay.ps1",
        "Write-ConfigParseWarning.ps1",
        # The one reader of **Billable:**, shared with the standup.
        "Get-PromptFileStatus.ps1",
    ):
        shutil.copy(REPO / "Scripts" / name, root / "Scripts" / name)
    shutil.copy(REPO / "consts.json", root / "consts.json")
    (root / "config.default.json").write_text(
        json.dumps(
            {
                "activeSpace": "test",
                "promptsRoot": "",
                "spaces": [{"slug": "test", "promptsFolder": "test", "status": "active"}],
            }
        )
    )
    (root / "config.local.json").write_text(json.dumps(local_config))
    return root / "agent" / "ado" / SCRIPT.name


def _run(script: Path, hub: Path, folder: str = "test") -> dict:
    where = ["-PromptsRoot", str(hub), "-PromptsFolder", folder]
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(script), *where, "-AsJson", *WEEK],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    # A script that failed quietly used to pass this runner and fail three
    # asserts later with a KeyError. Nothing on stderr is part of "it worked".
    assert result.stderr.strip() == "", result.stderr
    # The whole point of -AsJson: stdout is JSON, in every exit path.
    return json.loads(result.stdout)


def _run_raw(script: Path, hub: Path, *extra: str, folder: str | None = "test") -> subprocess.CompletedProcess:
    where = ["-PromptsFolder", folder] if folder is not None else []
    return subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(script), "-PromptsRoot", str(hub), *where, "-AsJson", *extra],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )


@unittest.skipUnless(HAVE_PWSH and HAVE_GIT, "needs pwsh and git")
class BillingScript(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="p20-billing-"))
        self.addCleanup(remove_tree, self.tmp)
        self.hub = self.tmp / "hub"
        self.hub.mkdir()
        _git(self.hub, "init", "-q", "-b", "main")

    def _commit_card(self, folder: str, name: str):
        current = self.hub / folder / "current"
        current.mkdir(parents=True, exist_ok=True)
        (current / name).write_text("# Bug 140: a card\n\n**Created:** 2026-01-01\n")
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", f"new: {name}")

    def test_without_the_callers_folder_the_script_refuses(self):
        """The script resolved the active Space a second time from the package's
        files, and answered differently from the agent wherever the two disagreed.
        It resolves nothing now: no -PromptsFolder is a stated refusal, never a
        guess at the hub root."""
        self._commit_card("test", "140-a-card.prompt.md")
        script = _scratch_package(self.tmp / "pkg", {"activeSpace": "test"})
        result = _run_raw(script, self.hub, *WEEK, folder=None)
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("-PromptsFolder is required", result.stderr)

    def test_a_dot_is_a_space_whose_cards_sit_at_the_hub_root(self):
        """Windows PowerShell 5.1 drops an empty argument, so the agent says the
        hub root as '.'. The script reads that folder and no other."""
        self._commit_card(".", "140-at-the-root.prompt.md")
        self._commit_card("test", "141-in-a-folder.prompt.md")
        script = _scratch_package(self.tmp / "pkg", {"activeSpace": "test"})

        data = _run(script, self.hub, folder=".")

        ids = {str(item["id"]) for day in data["days"] for item in day["items"]}
        self.assertEqual(ids, {"140"}, data.get("raw"))

    def test_a_hub_folder_two_levels_down(self):
        """promptsFolder is a path inside the hub, not only a name."""
        self._commit_card("clients/acme", "141-another.prompt.md")
        script = _scratch_package(self.tmp / "pkg", {})

        data = _run(script, self.hub, folder="clients/acme")

        ids = [str(item["id"]) for day in data["days"] for item in day["items"]]
        self.assertIn("141", ids, data.get("raw"))

    def test_a_mechanical_commit_is_not_work(self):
        """A link refresh or a stamp backfill touches cards nobody worked on."""
        self._commit_card("acme", "140-a-card.prompt.md")
        archive = self.hub / "acme" / "archive"
        archive.mkdir(parents=True)
        old = archive / "99-shipped-last-year.prompt.md"
        old.write_text("# Bug 99: shipped long ago\n")
        _git(self.hub, "add", "-A")
        # The archived card arrives by a mechanical commit, then is touched by two more.
        _git(self.hub, "commit", "-q", "-m", "backfill: seed an old archived card")
        old.write_text("# Bug 99: shipped long ago\n\n**Closed:** 2025-01-01\n")
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", "backfill: Created/Closed stamps from git history")
        old.write_text("# Bug 99: shipped long ago\n\n> Template: x\n**Closed:** 2025-01-01\n")
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", "sync: refresh package links after a move")
        script = _scratch_package(self.tmp / "pkg", {})

        data = _run(script, self.hub, folder="acme")

        ids = [str(item["id"]) for day in data["days"] for item in day["items"]]
        self.assertIn("140", ids, "real work is still billed")
        self.assertNotIn("99", ids, "a card only mechanical commits touched is not billed")

    def test_half_a_window_is_refused_not_ignored(self):
        """-Since without -Until used to be ignored in silence and the current week billed."""
        script = _scratch_package(self.tmp / "pkg", {})
        result = _run_raw(script, self.hub, "-Since", "2026-09-14")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("-Since and -Until go together", result.stderr)

    def test_a_re_archived_round_still_reads_code_review_on_its_review_day(self):
        """The PR-URL check used to look for the item's NEWEST name (X-r2) at the
        commit that touched X, found nothing, and billed the review day as active."""
        script = _scratch_package(self.tmp / "pkg", {})
        current = self.hub / "test" / "current"
        archive = self.hub / "test" / "archive"
        current.mkdir(parents=True)
        archive.mkdir(parents=True)
        (archive / "150-came-back.prompt.md").write_text(
            "# Bug 150: came back\n\n**Created:** 2026-09-01\n**Closed:** 2026-09-02\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-14T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "the first round, archived", when="2026-09-14T12:00:00")
        (current / "150-came-back.prompt.md").write_text(
            "# Bug 150: came back\n\n"
            "PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/1\n\n"
            "**Created:** 2026-09-15\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-15T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "in review", when="2026-09-15T12:00:00")
        (archive / "150-came-back.prompt.md").rename(archive / "150-came-back-r1.prompt.md")
        (current / "150-came-back.prompt.md").rename(archive / "150-came-back-r2.prompt.md")
        (archive / "150-came-back-r2.prompt.md").write_text(
            "# Bug 150: came back\n\n"
            "PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/1\n\n"
            "**Created:** 2026-09-15\n**Closed:** 2026-09-17\n"
        )
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", "archive again")
        data = _run(script, self.hub)
        tuesday = next(d for d in data["days"] if d["date"] == "2026-09-15")
        line = next(item for item in tuesday["items"] if str(item["id"]) == "150")
        self.assertEqual(line["status"], "code review", line)

    def _review_day_status(self, script, name: str, heading: str, card_id: str) -> str:
        """A card open from Monday, given a PR URL by a commit on Tuesday; the
        status the week reads for it on that Tuesday."""
        current = self.hub / "test" / "current"
        current.mkdir(parents=True)
        card = current / name
        card.write_text(f"# {heading}\n\n**Created:** 2026-09-14\n")
        _git(self.hub, "add", "-A", when="2026-09-14T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "new card", when="2026-09-14T12:00:00")
        card.write_text(
            f"# {heading}\n\nPR URL: https://dev.azure.com/x/y/_git/z/pullrequest/7\n\n**Created:** 2026-09-14\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-15T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "in review", when="2026-09-15T12:00:00")
        data = _run(script, self.hub)
        return self._status_on(data, "2026-09-15", card_id)

    def test_a_lettered_id_reads_its_git_review_day(self):
        """The git pass read ids with a pattern that knew only numbers, so a card
        with no work item (K7M2) got no review day from its PR-URL commit."""
        script = _scratch_package(self.tmp / "pkg", {})
        status = self._review_day_status(script, "K7M2-photo-import.prompt.md", "Bug K7M2: Photo import", "K7M2")
        self.assertEqual(status, "code review")

    def test_a_configured_type_prefix_reads_its_git_review_day(self):
        """A prefix beyond the shipped four is a card because config says so, in
        the git pass as much as in the cards pass."""
        script = _scratch_package(self.tmp / "pkg", {"workItemTypes": {"Chore": {"filePrefix": "Chore-"}}})
        status = self._review_day_status(
            script, "Chore-170-rotate-the-keys.prompt.md", "Chore 170: Rotate the keys", "170"
        )
        self.assertEqual(status, "code review")

    def _week(self, script, since, until):
        result = _run_raw(script, self.hub, "-Since", since, "-Until", until)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    @staticmethod
    def _status_on(data, day, card_id):
        for d in data["days"]:
            if d["date"] == day:
                for item in d["items"]:
                    if str(item["id"]) == card_id:
                        return item["status"]
        return None

    def test_a_saturday_close_is_billed_on_the_monday_after(self):
        """Only weekdays render, so a Saturday **Closed:** vanished --
        active Thu and Fri, then gone. Time is in by Friday 5pm (the owner's rule),
        so a weekend event bills to the FOLLOWING week's Monday."""
        script = _scratch_package(self.tmp / "pkg", {})
        archive = self.hub / "test" / "archive"
        archive.mkdir(parents=True)
        (archive / "160-done-on-saturday.prompt.md").write_text(
            "# Bug 160: done on saturday\n\n**Created:** 2026-09-17\n**Closed:** 2026-09-19\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-19T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "archive on saturday", when="2026-09-19T12:00:00")

        this_week = self._week(script, "2026-09-14", "2026-09-18")
        self.assertEqual(self._status_on(this_week, "2026-09-17", "160"), "active")
        self.assertEqual(
            self._status_on(this_week, "2026-09-18", "160"), "active", "still open on the Friday the week was submitted"
        )
        next_week = self._week(script, "2026-09-21", "2026-09-25")
        self.assertEqual(
            self._status_on(next_week, "2026-09-21", "160"), "resolved", "the Saturday close lands on the Monday after"
        )
        self.assertIsNone(self._status_on(next_week, "2026-09-22", "160"), "and nothing after it")

    def test_the_pr_url_check_gives_the_same_week_one_hash_a_batch(self):
        """The git grep behind the review days runs in batches under a character
        budget, because one call carrying every hash and path can pass Windows'
        32K command-line limit, and fails silently behind 2>$null.
        A budget of 1 is one hash a batch; the week must not change."""
        import os

        script = _scratch_package(self.tmp / "pkg", {})
        current = self.hub / "test" / "current"
        current.mkdir(parents=True)
        for n, day in ((151, "2026-09-15"), (152, "2026-09-16"), (153, "2026-09-17")):
            (current / f"{n}-in-review.prompt.md").write_text(
                f"# Bug {n}: in review\n\n"
                f"PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/{n}\n\n"
                "**Created:** 2026-09-14\n"
            )
            _git(self.hub, "add", "-A", when=f"{day}T12:00:00")
            _git(self.hub, "commit", "-q", "-m", f"{n} in review", when=f"{day}T12:00:00")

        def review_days(data):
            return sorted(
                (d["date"], str(i["id"])) for d in data["days"] for i in d["items"] if i["status"] == "code review"
            )

        whole = review_days(_run(script, self.hub))
        with mock.patch.dict(os.environ, {"P20_BILLING_GREP_BUDGET": "1"}):
            batched = review_days(_run(script, self.hub))
        # Each card reads code review from its own commit's day -- which only
        # the git grep can say (with it disabled, none of these rows exist).
        for first in (("2026-09-15", "151"), ("2026-09-16", "152"), ("2026-09-17", "153")):
            self.assertIn(first, whole)
        self.assertEqual(batched, whole)

    @unittest.skipUnless(sys.platform == "win32", "8.3 short names are a Windows thing")
    def test_a_short_windows_path_bills_the_same_week(self):
        """A hub reached through a short name (``C:\\Users\\<name>~1.<domain>``) passes Test-Path and used
        to fail Push-Location quietly, reporting an empty week with exit 0."""
        script = _scratch_package(self.tmp / "pkg", {})
        self._commit_card("test", "141-a-card.prompt.md")
        # The same conversion the NewSpace and StampDesign short-path cases use.
        short = short_path(self.hub)
        if short == self.hub:
            self.skipTest("this volume does not make 8.3 names")
        data = _run(script, short)
        self.assertTrue(data["days"], data)

    def test_a_persons_review_line_reads_code_review_from_that_day(self):
        """`Move -To CodeReview` writes **Review:** on a card with no pull request;
        Daily reads it the way it reads git's review day, and a **Started:** line the
        way it reads a commit day."""
        script = _scratch_package(self.tmp / "pkg", {})
        current = self.hub / "test" / "current"
        current.mkdir(parents=True)
        (current / "N4WQ-a-meeting.prompt.md").write_text(
            "# Meeting N4WQ: a meeting\n\n**Created:** 2026-09-14\n**Started:** 2026-09-15\n**Review:** 2026-09-16\n"
        )
        data = _run(script, self.hub)
        by_day = {d["date"]: {str(i["id"]): i for i in d["items"]} for d in data["days"]}
        self.assertEqual(by_day["2026-09-15"]["N4WQ"]["status"], "active")
        self.assertEqual(by_day["2026-09-16"]["N4WQ"]["status"], "code review")
        self.assertEqual(by_day["2026-09-17"]["N4WQ"]["status"], "code review", "carried forward")
        self.assertEqual(by_day["2026-09-16"]["N4WQ"]["type"], "Meeting")

    def _card_into_review(self, authored: str, committed: str) -> dict:
        """A card open all week, and the commit that gives it a PR URL."""
        script = _scratch_package(self.tmp / "pkg", {})
        current = self.hub / "test" / "current"
        current.mkdir(parents=True)
        card = current / "160-late-sync.prompt.md"
        card.write_text("# Bug 160: late sync\n\n**Created:** 2026-09-14\n")
        _git(self.hub, "add", "-A", when="2026-09-14T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "new card", when="2026-09-14T12:00:00")
        card.write_text(
            "# Bug 160: late sync\n\n"
            "PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/9\n\n"
            "**Created:** 2026-09-14\n"
        )
        _git(self.hub, "add", "-A", when=authored, committed=committed)
        _git(self.hub, "commit", "-q", "-m", "in review", when=authored, committed=committed)
        data = _run(script, self.hub)
        return {d["date"]: {str(i["id"]): i for i in d["items"]} for d in data["days"]}

    def test_a_commit_rebased_after_the_week_still_bills_its_own_day(self):
        """Sync's `pull --rebase` resets a commit's COMMITTER date to the sync.
        git's --until filters on that date, so Thursday's review commit, synced
        on Monday, fell outside the week and Thursday read "active". The day is
        the AUTHOR's instant on the local clock."""
        by_day = self._card_into_review("2026-09-17T12:00:00", committed="2026-09-21T09:00:00")
        self.assertEqual(by_day["2026-09-16"]["160"]["status"], "active")
        self.assertEqual(by_day["2026-09-17"]["160"]["status"], "code review")
        self.assertEqual(by_day["2026-09-18"]["160"]["status"], "code review", "carried forward")

    def test_a_commit_authored_after_the_week_is_not_in_it(self):
        """git's window is widened by a week to catch the case above, so a commit
        AUTHORED after the week now reaches the script -- and must be dropped by
        its own day, not bill the week with a review that had not happened yet."""
        by_day = self._card_into_review("2026-09-21T12:00:00", committed="2026-09-21T12:00:00")
        self.assertEqual(by_day["2026-09-18"]["160"]["status"], "active")

    def test_a_hub_that_is_a_subfolder_of_a_repository_reads_git(self):
        """git prints a path from the REPOSITORY's root, and the patterns that
        read it are anchored at the hub's -- so a hub kept in a subfolder of a
        repository matched nothing and lost every day git knows: here, the day
        the card went into review read "active"."""
        script = _scratch_package(self.tmp / "pkg", {})
        hub = self.hub / "notes" / "hub"
        current = hub / "test" / "current"
        current.mkdir(parents=True)
        card = current / "170-kept-in-a-subfolder.prompt.md"
        card.write_text("# Bug 170: kept in a subfolder\n\n**Created:** 2026-09-14\n")
        _git(self.hub, "add", "-A", when="2026-09-14T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "new card", when="2026-09-14T12:00:00")
        card.write_text(
            "# Bug 170: kept in a subfolder\n\n"
            "PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/170\n\n"
            "**Created:** 2026-09-14\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-16T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "in review", when="2026-09-16T12:00:00")
        data = _run(script, hub)
        self.assertEqual(data["source"], "stamps+git")
        self.assertEqual(self._status_on(data, "2026-09-15", "170"), "active")
        self.assertEqual(self._status_on(data, "2026-09-16", "170"), "code review", data["raw"])

    def test_root_level_org_does_not_leak_into_prefixed_org(self):
        """An org's billing read the hub ROOT's current/ and archive/ too, for a
        layout no hub has any more -- so a card at the root lent its git days to
        the active org's card of the same name: here, a review it never had."""
        script = _scratch_package(self.tmp / "pkg", {})
        mine = self.hub / "test" / "current" / "180-same-name.prompt.md"
        theirs = self.hub / "current" / "180-same-name.prompt.md"
        mine.parent.mkdir(parents=True)
        theirs.parent.mkdir(parents=True)
        mine.write_text("# Bug 180: same name\n\n**Created:** 2026-09-14\n")
        theirs.write_text("# Bug 180: same name\n\n**Created:** 2026-09-14\n")
        _git(self.hub, "add", "-A", when="2026-09-14T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "two cards", when="2026-09-14T12:00:00")
        theirs.write_text(
            "# Bug 180: same name\n\n"
            "PR URL: https://dev.azure.com/x/y/_git/z/pullrequest/180\n\n"
            "**Created:** 2026-09-14\n"
        )
        _git(self.hub, "add", "-A", when="2026-09-16T12:00:00")
        _git(self.hub, "commit", "-q", "-m", "the root card into review", when="2026-09-16T12:00:00")
        data = _run(script, self.hub)
        self.assertEqual(self._status_on(data, "2026-09-16", "180"), "active", data["raw"])
        self.assertEqual(self._status_on(data, "2026-09-18", "180"), "active", data["raw"])

    def test_no_activity_is_json_not_prose(self):
        """A hub with history but nothing under the org this week."""
        (self.hub / "README.md").write_text("hub\n")
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", "init")
        script = _scratch_package(self.tmp / "pkg", {"activeSpace": "test"})

        data = _run(script, self.hub)

        self.assertEqual(data["days"], [])
        self.assertIn("No activity", data["raw"])


def _card(heading: str, created: str, closed: str | None = None, extra: str = "") -> str:
    lines = [f"# {heading}", "", "## Git", "Commits:", "- (pending)", "", extra, "---", "", f"**Created:** {created}"]
    if closed:
        lines.append(f"**Closed:** {closed}")
    return "\n".join(lines) + "\n"


@unittest.skipUnless(HAVE_PWSH, "needs pwsh")
class TheCardsDecide(unittest.TestCase):
    """Roadmap phase 3: billing is built from the cards' own dates, and
    git only enriches. WEEK is a Monday through the Friday after it."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="p20-billing-cards-"))
        self.addCleanup(remove_tree, self.tmp)
        self.hub = self.tmp / "hub"
        (self.hub / "test" / "current").mkdir(parents=True)
        (self.hub / "test" / "archive").mkdir(parents=True)
        self.script = _scratch_package(self.tmp / "pkg", {"activeSpace": "test"})

    def _put(self, where: str, name: str, text: str):
        (self.hub / "test" / where / name).write_text(text)

    def _days(self, data):
        return {d["date"]: {str(i["id"]): i["status"] for i in d["items"]} for d in data["days"]}

    def test_a_hub_that_is_not_a_git_repository_is_billed(self):
        """It had NO billing: the script was `git log`. It is what a first run makes."""
        self._put("current", "TaskK7M2-wallet-ticket.prompt.md", _card("Task K7M2: Wallet ticket", "2026-09-15"))
        data = _run(self.script, self.hub)
        days = self._days(data)
        self.assertEqual(data["source"], "stamps")
        self.assertNotIn("K7M2", days.get("2026-09-14", {}), "not open yet on Monday")
        for day in ("2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"):
            self.assertEqual(days[day].get("K7M2"), "active", day)

    def test_a_card_is_open_from_created_to_closed_and_resolved_on_its_closing_day(self):
        self._put("archive", "US-142-paginate.prompt.md", _card("User Story 142: Paginate", "2026-09-10", "2026-09-16"))
        days = self._days(_run(self.script, self.hub))
        self.assertEqual(days["2026-09-14"].get("142"), "active", "opened before the week, still open")
        self.assertEqual(days["2026-09-16"].get("142"), "resolved")
        self.assertNotIn("142", days.get("2026-09-17", {}), "closed: not carried past its closing day")

    def test_a_card_closed_before_the_week_is_not_in_it(self):
        self._put("archive", "140-old.prompt.md", _card("Bug 140: Old", "2026-08-01", "2026-09-01"))
        self.assertEqual(_run(self.script, self.hub)["days"], [])

    def test_billable_no_takes_a_card_off_the_timesheet_and_is_counted(self):
        self._put(
            "current",
            "Spike-Q4TN-bench-reading.prompt.md",
            _card("Spike Q4TN: Bench reading", "2026-09-14", extra="**Billable:** no\n"),
        )
        self._put("current", "141-search.prompt.md", _card("Bug 141: Search", "2026-09-14"))
        data = _run(self.script, self.hub)
        ids = {i for d in self._days(data).values() for i in d}
        self.assertEqual(ids, {"141"})
        self.assertEqual(data["nonBillable"], 1)

    def test_no_billable_line_means_billable(self):
        self._put("current", "141-search.prompt.md", _card("Bug 141: Search", "2026-09-14"))
        self.assertEqual(_run(self.script, self.hub)["nonBillable"], 0)

    def test_a_file_that_is_not_a_card_is_never_billed(self):
        self._put("current", "notes-from-tuesday.prompt.md", _card("Notes from Tuesday", "2026-09-14"))
        self._put("archive", "2026-09-15-PR141.prompt.md", _card("PR 141 review", "2026-09-15", "2026-09-15"))
        self.assertEqual(_run(self.script, self.hub)["days"], [])

    def test_a_card_with_no_date_is_counted_not_guessed(self):
        self._put("current", "141-no-stamp.prompt.md", "# Bug 141: No stamp\n")
        data = _run(self.script, self.hub)
        self.assertEqual(data["days"], [])
        self.assertEqual(data["unstamped"], 1)

    def test_a_type_the_heading_names_is_the_type_billed(self):
        self._put("current", "Spike-K7M2-photo-import.prompt.md", _card("Spike K7M2: Photo import", "2026-09-14"))
        data = _run(self.script, self.hub)
        item = data["days"][0]["items"][0]
        self.assertEqual((item["type"], str(item["id"])), ("Spike", "K7M2"))
        self.assertIn("Spike K7M2: Photo import", data["raw"])

    def test_a_teams_own_type_from_the_machines_config_is_billed(self):
        """Types are config, not code. A `Chore-` card is a card because
        config.local.json says so -- and a card the id rule cannot read is a card
        that is silently never billed."""
        script = _scratch_package(
            self.tmp / "pkg2", {"activeSpace": "test", "workItemTypes": {"Chore": {"filePrefix": "Chore-"}}}
        )
        self._put("current", "Chore-Q4TN-rotate-the-keys.prompt.md", _card("Chore Q4TN: Rotate the keys", "2026-09-14"))
        self.assertIn("Chore Q4TN: Rotate the keys", _run(script, self.hub)["raw"])
        # ...and without that line in config it is not a card at all.
        self.assertNotIn("Q4TN", _run(self.script, self.hub)["raw"])

    def test_the_callers_folder_wins_over_the_packages_own_config(self):
        """The agent has already resolved the active Space; the script must not
        resolve it a second time and disagree. Found when a route test
        passed or failed by whichever org the developer had selected in their own
        UI, because the script re-read the package's real config.local.json."""
        (self.hub / "elsewhere" / "current").mkdir(parents=True)
        (self.hub / "elsewhere" / "current" / "141-over-here.prompt.md").write_text(
            _card("Bug 141: Over here", "2026-09-14")
        )
        self._put("current", "142-not-this-one.prompt.md", _card("Bug 142: Not this one", "2026-09-14"))
        result = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-File",
                str(self.script),
                "-PromptsRoot",
                str(self.hub),
                "-PromptsFolder",
                "elsewhere",
                "-AsJson",
                *WEEK,
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        raw = json.loads(result.stdout)["raw"]
        self.assertIn("Bug 141: Over here", raw)
        self.assertNotIn("142", raw)

    def test_a_two_word_type_keeps_its_title(self):
        """Found by running the sample hub: every User Story was billed
        as "US 209:  (active)". A second -match had replaced $Matches before the
        title was read out of it."""
        self._put(
            "current", "US-209-paginate.prompt.md", _card("User Story 209: Paginate the recipe list", "2026-09-14")
        )
        data = _run(self.script, self.hub)
        item = data["days"][0]["items"][0]
        self.assertEqual((item["type"], item["title"]), ("US", "Paginate the recipe list"))
        self.assertIn("US 209: Paginate the recipe list", data["raw"])

    @unittest.skipUnless(HAVE_GIT, "needs git")
    def test_a_folder_move_bills_nobody_on_a_day_they_were_not_open(self):
        """A hub folder move: a move commit touches every
        card. An ARCHIVED card it touched used to come back onto the timesheet."""
        _git(self.hub, "init", "-q", "-b", "main")
        self._put(
            "archive", "140-closed-in-august.prompt.md", _card("Bug 140: Closed in August", "2026-08-01", "2026-08-20")
        )
        self._put("current", "141-open.prompt.md", _card("Bug 141: Open", "2026-09-14"))
        _git(self.hub, "add", "-A")
        _git(self.hub, "commit", "-q", "-m", "reorganise the hub: move every card", "--date", WORK_DAY)
        data = _run(self.script, self.hub)
        ids = {i for d in self._days(data).values() for i in d}
        self.assertEqual(data["source"], "stamps+git")
        self.assertEqual(ids, {"141"}, "the card closed in August stays closed")


if __name__ == "__main__":
    unittest.main()
