"""Team Agile's GET /api/ritual/releases -- the timeline's read, its placement rule, the gate.

The Releases timeline (docs/modules/solitaire-agile.md, "Releases: the timeline").
Two tables:

- Tests/fixtures/releases/repo.json: a Space's repository, built here as a real
  git repository in a temporary folder -- commits on fixed days, release tags and
  a -rc checkpoint, a changelog and the entries waiting in changelog.d/ -- plus
  gh's milestone rows; `expected` is what the route serves, release by release.
- Tests/fixtures/releases/placement.json: where a milestone belongs, the one pure
  rule (``place_milestones``), case by case.

git runs for real; gh and the tier probe are stubbed. No network.

Run:  python3 -m pytest Tests/test_ritual_releases.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

REPO_ROOT = Path(__file__).resolve().parent.parent
try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import accounting
    from agent.ado.accounting import Milestone
    from agent.core import config
    from agent.core import consts as C
    from agent.solitaire import api as solitaire_api
    from agent.solitaire import releases as R
    from agent.solitaire import tracker as solitaire_tracker
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

if shutil.which("git") is None:  # pragma: no cover
    skip_module("git is not installed")

FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "releases"
REPO_TABLE = json.loads((FIXTURES / "repo.json").read_text(encoding="utf-8"))
PLACEMENT = json.loads((FIXTURES / "placement.json").read_text(encoding="utf-8"))
REPO = REPO_TABLE["repo"]
WIDGETS = f"https://github.com/{REPO}"
_REAL_RUN = subprocess.run


def _git(root: Path, *args: str, day: str = "") -> None:
    env = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_SYSTEM": os.devnull,
        "GIT_AUTHOR_NAME": "Fixture",
        "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
        "GIT_COMMITTER_NAME": "Fixture",
        "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
    }
    if day:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"{day}T12:00:00Z"
    _REAL_RUN(["git", *args], cwd=root, env=env, check=True, capture_output=True)


def build_repo(root: Path, table: dict = REPO_TABLE) -> Path:
    """The table's repository at ``root``: its commits, tags and files."""
    root.mkdir(parents=True, exist_ok=True)
    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "core.autocrlf", "false")
    _git(root, "remote", "add", "origin", f"https://github.com/{table['repo']}.git")
    for c in table["commits"]:
        if c.get("files"):
            for rel, text in table["files"].items():
                f = root / rel
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_bytes(text.encode("utf-8"))
            _git(root, "add", "-A")
        message = c["subject"] + (f"\n\n{c['body']}" if c["body"] else "")
        _git(root, "commit", "-q", "--allow-empty", "-m", message, day=c["day"])
        for tag in c.get("tags", []):
            _git(root, "tag", tag, day=c["day"])
    return root


def _summary(release: dict) -> dict:
    """A served release as the table states it: numbers for refs, titles for milestones."""
    out = {k: release[k] for k in ("tag", "version", "inProgress", "date", "since", "previous", "commits", "url")}
    out["notes"] = release["notes"]
    out["pulls"] = [p["number"] for p in release["pulls"]]
    out["issues"] = [i["number"] for i in release["issues"]]
    out["milestones"] = [m["title"] for m in release["milestones"]]
    return out


class ThePlacementRule(unittest.TestCase):
    """placement.json: where a milestone belongs, case by case."""

    def test_every_case(self):
        for case in PLACEMENT["cases"]:
            with self.subTest(case=case["name"]):
                tags = [tuple(t) for t in case["tags"]]
                ms = [Milestone(**m) for m in case["milestones"]]
                got = R.place_milestones(tags, ms)
                self.assertEqual({k: [m.title for m in v] for k, v in got.items()}, case["expected"])

    def test_the_reached_day_is_the_awards(self):
        self.assertEqual(
            R.reached_on(Milestone(reached=True, closed_at="2026-10-05", updated_at="2026-10-06")), "2026-10-05"
        )
        self.assertEqual(R.reached_on(Milestone(reached=True, updated_at="2026-10-06")), "2026-10-06")
        self.assertEqual(R.reached_on(Milestone(reached=False, closed_at="2026-10-05")), "")


class TheNotes(unittest.TestCase):
    def test_a_changelog_section_by_version_unreleased_left_out(self):
        got = R.parse_changelog(REPO_TABLE["files"]["CHANGELOG.md"])
        self.assertEqual(list(got), ["0.3.0", "0.2.0", "0.1.0"])
        self.assertEqual(
            [n.model_dump() for n in got["0.2.0"]],
            [
                {"heading": "Changed", "entries": ["The list is sorted by name."]},
                {"heading": "Fixed", "entries": ["An empty list says so, instead of showing nothing."]},
            ],
        )

    def test_the_waiting_entries_by_kind_in_keep_a_changelog_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "changelog.d"
            folder.mkdir()
            for rel, text in REPO_TABLE["files"].items():
                if rel.startswith("changelog.d/"):
                    (Path(tmp) / rel).write_text(text, encoding="utf-8")
            (folder / ".DS_Store").write_text("x", encoding="utf-8")
            (folder / "9.unknown.md").write_text("- not a kind\n", encoding="utf-8")
            got = [n.model_dump() for n in R.waiting_notes(folder)]
        self.assertEqual(got, REPO_TABLE["expected"][0]["notes"])

    def test_no_folder_is_no_notes(self):
        self.assertEqual(R.waiting_notes(Path("/nonexistent-p20/changelog.d")), [])


class TheRoute(unittest.TestCase):
    features = {"solitaireAgile": True}

    def setUp(self):
        solitaire_tracker.forget()
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        hub = base / "hub"
        (hub / "widgets" / "current").mkdir(parents=True)
        self.clone = build_repo(base / "widgets-clone")
        default = base / "config.default.json"
        self.local = base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "widgets",
                    "features": self.features,
                    "promptsRoot": str(hub),
                    "spaces": [
                        {
                            "slug": "widgets",
                            "status": "active",
                            "promptsFolder": "widgets",
                            "org": WIDGETS,
                            "howIWork": "agents",
                        },
                        {"slug": "elsewhere", "status": "active", "promptsFolder": "elsewhere", "org": WIDGETS},
                    ],
                }
            ),
            encoding="utf-8",
        )
        self._checkout(str(self.clone))
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for p in self.patches:
            p.start()
        for var in ("PROMPTS_ROOT", C.env_active_space(), C.env_features()):
            os.environ.pop(var, None)
        app = FastAPI()
        app.include_router(solitaire_api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()
        solitaire_tracker.forget()

    def _checkout(self, path: str) -> None:
        table = {"widgets": {"path": path}} if path else {}
        self.local.write_text(json.dumps({"spaceCheckouts": table}), encoding="utf-8")

    def _get(self, path: str, tier: int = 1, gh_fails: bool = False):
        calls: list[list[str]] = []

        def fake_run(argv, *args, **kw):
            if argv and argv[0] != "gh":
                return _REAL_RUN(argv, *args, **kw)  # git runs for real
            calls.append(list(argv))
            if gh_fails:
                raise subprocess.TimeoutExpired(argv, 30)
            return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(REPO_TABLE["milestones"]), stderr="")

        with (
            mock.patch.object(solitaire_tracker, "_resolve_tier", return_value=(tier, True)),
            mock.patch.object(accounting.subprocess, "run", side_effect=fake_run),
        ):
            res = self.client.get(path)
        return res, calls

    def test_on_it_answers_the_table(self):
        res, calls = self._get("/api/ritual/releases?space=widgets")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(set(body), {"ceremony", "space", "repo", "source", "tracker", "releases"})
        self.assertEqual((body["ceremony"], body["space"], body["repo"]), ("releases", "widgets", REPO))
        self.assertEqual(body["source"], {"ok": True, "reason": ""})
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual([_summary(r) for r in body["releases"]], REPO_TABLE["expected"])
        self.assertEqual(len(calls), 1)

    def test_a_pull_request_carries_its_subject_and_links(self):
        body = self._get("/api/ritual/releases")[0].json()
        pull = body["releases"][0]["pulls"][0]
        self.assertEqual(pull, {"number": 13, "title": "Export the list", "url": f"{WIDGETS}/pull/13"})
        self.assertEqual(body["releases"][0]["issues"][0]["url"], f"{WIDGETS}/issues/12")

    def test_a_milestone_carries_the_day_it_was_reached(self):
        body = self._get("/api/ritual/releases")[0].json()
        by_title = {m["title"]: m for r in body["releases"] for m in r["milestones"]}
        self.assertEqual(by_title["Search"]["reachedOn"], "2026-10-05")
        self.assertEqual(by_title["Sorting"]["reachedOn"], "2026-10-01")
        self.assertEqual(by_title["Export"]["reachedOn"], "")
        self.assertTrue(by_title["Search"]["reached"])

    def test_the_rc_tag_is_not_a_release(self):
        body = self._get("/api/ritual/releases")[0].json()
        self.assertNotIn("v0.3.0-rc.1", [r["tag"] for r in body["releases"]])

    def test_no_tracker_still_answers_every_release_with_no_milestone(self):
        res, calls = self._get("/api/ritual/releases", tier=2)
        body = res.json()
        self.assertEqual(res.status_code, 200)
        self.assertFalse(body["tracker"]["ok"])
        self.assertTrue(body["tracker"]["reason"])
        self.assertTrue(body["source"]["ok"])
        self.assertEqual([r["version"] for r in body["releases"]], ["Unreleased", "0.3.0", "0.2.0", "0.1.0"])
        self.assertTrue(all(r["milestones"] == [] for r in body["releases"]))
        self.assertEqual(calls, [])

    def test_gh_not_answering_is_a_reason(self):
        body = self._get("/api/ritual/releases", gh_fails=True)[0].json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertTrue(body["tracker"]["reason"].startswith(f"{REPO}: "), body["tracker"]["reason"])
        self.assertEqual(len(body["releases"]), 4)

    def test_no_checkout_is_a_sentence_naming_the_setting(self):
        self._checkout("")
        res, _calls = self._get("/api/ritual/releases")
        body = res.json()
        self.assertEqual(res.status_code, 200)
        self.assertFalse(body["source"]["ok"])
        self.assertIn("spaceCheckouts.widgets.path", body["source"]["reason"])
        self.assertEqual(body["releases"], [])
        self.assertTrue(body["tracker"]["ok"])

    def test_a_checkout_of_another_repository_is_refused_by_name(self):
        other = build_repo(
            Path(self.tmp.name) / "other", {**REPO_TABLE, "repo": "acme/gadgets", "commits": REPO_TABLE["commits"][:1]}
        )
        self._checkout(str(other))
        body = self._get("/api/ritual/releases")[0].json()
        self.assertFalse(body["source"]["ok"])
        self.assertIn("acme/gadgets", body["source"]["reason"])

    def test_no_tag_yet_is_one_release_in_progress(self):
        bare = build_repo(
            Path(self.tmp.name) / "bare", {**REPO_TABLE, "commits": [{**c, "tags": []} for c in REPO_TABLE["commits"]]}
        )
        self._checkout(str(bare))
        body = self._get("/api/ritual/releases", tier=2)[0].json()
        self.assertEqual(
            [(r["version"], r["commits"], r["previous"]) for r in body["releases"]], [("Unreleased", 8, "")]
        )

    def test_an_unknown_space_is_404_naming_it(self):
        res, calls = self._get("/api/ritual/releases?space=nowhere")
        self.assertEqual(res.status_code, 404)
        self.assertIn("nowhere", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_nothing_is_written_to_the_clone_or_the_hub(self):
        def tree():
            base = Path(self.tmp.name)
            return sorted(
                (p.relative_to(base).as_posix(), p.stat().st_size)
                for p in base.rglob("*")
                if p.is_file() and "/.git/" not in p.as_posix() and p.name != "config.local.json"
            )

        before = tree()
        self._get("/api/ritual/releases")
        self.assertEqual(tree(), before)

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_releases_route(), "/api/ritual/releases")


class TheRouteWithTheFlagOff(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        res, calls = self._get("/api/ritual/releases?space=widgets")
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])
        self.assertEqual(calls, [])

    test_on_it_answers_the_table = None
    test_a_pull_request_carries_its_subject_and_links = None
    test_a_milestone_carries_the_day_it_was_reached = None
    test_the_rc_tag_is_not_a_release = None
    test_no_tracker_still_answers_every_release_with_no_milestone = None
    test_gh_not_answering_is_a_reason = None
    test_no_checkout_is_a_sentence_naming_the_setting = None
    test_a_checkout_of_another_repository_is_refused_by_name = None
    test_no_tag_yet_is_one_release_in_progress = None
    test_an_unknown_space_is_404_naming_it = None
    test_nothing_is_written_to_the_clone_or_the_hub = None


class TheRouteWhereTheSpaceWorksAlone(TheRoute):
    """The switch on, but the Space answered `alone`: Team Agile is off there too."""

    def setUp(self):
        super().setUp()
        cfg = json.loads(config.DEFAULT_CONFIG_PATH.read_text(encoding="utf-8"))
        cfg["spaces"][0]["howIWork"] = "alone"
        config.DEFAULT_CONFIG_PATH.write_text(json.dumps(cfg), encoding="utf-8")

    def test_off_in_this_space_is_404(self):
        res, calls = self._get("/api/ritual/releases")
        self.assertEqual(res.status_code, 404)
        self.assertIn("howIWork", res.json()["detail"])
        self.assertEqual(calls, [])

    for _name in [n for n in dir(TheRoute) if n.startswith("test_") and n != "test_the_route_is_the_contracts"]:
        locals()[_name] = None
    del _name


if __name__ == "__main__":
    unittest.main()
