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
import re
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


def _commit(root: Path, table: dict, c: dict) -> None:
    files = table["files"] if c.get("files") is True else (c.get("files") or {})
    for rel, text in files.items():
        f = root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(text.encode("utf-8"))
    if files:
        _git(root, "add", "-A")
    message = c["subject"] + (f"\n\n{c['body']}" if c["body"] else "")
    _git(root, "commit", "-q", "--allow-empty", "-m", message, day=c["day"])
    for tag in c.get("tags", []):
        _git(root, "tag", tag, day=c["day"])


def build_repo(root: Path, table: dict = REPO_TABLE, origin: bool = True) -> Path:
    """The table's repository at ``root``: its commits, tags and files on main,
    the origin ref when the table names one (and ``origin`` is not turned off),
    then its side branches, ending on the one marked ``checkout``."""
    root.mkdir(parents=True, exist_ok=True)
    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "core.autocrlf", "false")
    _git(root, "remote", "add", "origin", f"https://github.com/{table['repo']}.git")
    for c in table["commits"]:
        _commit(root, table, c)
    if origin and table.get("origin"):
        _git(root, "update-ref", f"refs/remotes/origin/{table['origin']}", table["origin"])
    final = "main"
    for side in table.get("side", []):
        _git(root, "checkout", "-q", "-b", side["branch"], side["from"])
        for c in side["commits"]:
            _commit(root, table, c)
        if side.get("checkout"):
            final = side["branch"]
        _git(root, "checkout", "-q", "main")
    if final != "main":
        _git(root, "checkout", "-q", final)
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
                tags = [tuple(t) for t in case["tags"]]  # [tag, day] or [tag, day, instant]
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
        files = [
            (rel.split("/", 1)[1], text) for rel, text in REPO_TABLE["files"].items() if rel.startswith("changelog.d/")
        ]
        files += [(".DS_Store", "x"), ("9.unknown.md", "- not a kind\n")]
        got = [n.model_dump() for n in R.fragment_notes(files)]
        self.assertEqual(got, REPO_TABLE["expected"][0]["notes"])

    def test_no_file_is_no_notes(self):
        self.assertEqual(R.fragment_notes([]), [])

    def test_the_fragments_at_a_ref_from_one_git_grep(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = build_repo(Path(tmp) / "r")
            calls: list[list[str]] = []
            real = R.git_read

            def spy(args, cwd):
                calls.append(list(args))
                return real(args, cwd)

            with mock.patch.object(R, "git_read", side_effect=spy):
                got = R.read_fragments(root, "refs/heads/main")
                none = R.read_fragments(root, "refs/tags/v0.1.0")
        self.assertEqual(
            sorted(n for n, _ in got), ["12-fix.Fixed.md", "13.added.md", "14.changed.md", "README.md", "notes.txt"]
        )
        self.assertEqual(dict(got)["README.md"], REPO_TABLE["files"]["changelog.d/README.md"])
        self.assertEqual(none, [])
        self.assertEqual(len(calls), 2)
        self.assertTrue(all("grep" in c for c in calls), calls)


class TheDefaultBranch(unittest.TestCase):
    """Which ref "the tip of the default branch" is: the CLI's base-branch order
    (Thread-CommitHash.ps1 Resolve-P20BaseBranch) for the name, then origin's ref,
    else the local branch, else HEAD."""

    LISTING = (
        "refs/heads/main\t\nrefs/heads/feature\t\n"
        "refs/remotes/origin/HEAD\trefs/remotes/origin/trunk\nrefs/remotes/origin/trunk\t\n"
    )

    def test_the_rows(self):
        rows = [
            ("configured, with origin's ref", "trunk", "trunk", "refs/remotes/origin/trunk", "origin/trunk"),
            ("configured, only a local branch", "main", "main", "refs/heads/main", "main"),
            ("configured, on neither", "develop", "develop", "HEAD", "HEAD"),
            ("unconfigured: origin's HEAD names it", "", "trunk", "refs/remotes/origin/trunk", "origin/trunk"),
        ]
        for name, configured, branch, full, short in rows:
            with self.subTest(name):
                self.assertEqual(R.pick_default_ref(self.LISTING, configured), (branch, full, short))

    def test_no_origin_head_falls_to_main_then_master(self):
        self.assertEqual(R.pick_default_ref("refs/heads/master\t\n", ""), ("master", "refs/heads/master", "master"))
        self.assertEqual(
            R.pick_default_ref("refs/heads/master\t\nrefs/heads/main\t\n", ""), ("main", "refs/heads/main", "main")
        )
        self.assertEqual(R.pick_default_ref("refs/heads/feature\t\n", ""), ("", "HEAD", "HEAD"))
        self.assertEqual(R.pick_default_ref("", ""), ("", "HEAD", "HEAD"))

    def test_a_projects_entry_names_it_by_repository(self):
        projects = [
            {"name": "Other", "repo": "gadgets", "defaultBranch": "dev"},
            {"name": "Widgets", "repo": "acme/Widgets", "defaultBranch": "trunk"},
        ]
        self.assertEqual(R.configured_branch(REPO, projects), "trunk")
        self.assertEqual(R.configured_branch(REPO, [{"name": "W", "repo": "widgets", "defaultBranch": "rel"}]), "rel")
        self.assertEqual(R.configured_branch(REPO, [{"name": "W", "repo": "widgets"}]), "")
        self.assertEqual(R.configured_branch(REPO, []), "")


class TheRoute(unittest.TestCase):
    features = {"solitaireAgile": True}

    def setUp(self):
        solitaire_tracker.forget()
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        hub = base / "hub"
        (hub / "widgets" / "current").mkdir(parents=True)
        self.clone = build_repo(base / "widgets-clone")
        default = self.default = base / "config.default.json"
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
        self.queries: list[str] = []

        def fake_run(argv, *args, **kw):
            if argv and argv[0] != "gh":
                return _REAL_RUN(argv, *args, **kw)  # git runs for real
            calls.append(list(argv))
            if gh_fails:
                raise subprocess.TimeoutExpired(argv, 30)
            if "graphql" in argv:
                # The titles read: the query travels in a file; answer each alias
                # GitHub could resolve (the table's titles), null for the rest.
                at = next(a for a in argv if a.startswith("query=@"))[len("query=@") :]
                query = Path(at).read_text(encoding="utf-8")
                self.queries.append(query)
                asked = re.findall(r"i(\d+): issueOrPullRequest\(number: (\d+)\)", query)
                titles = REPO_TABLE["issueTitles"]
                repo = {f"i{n}": ({"title": titles[n]} if n in titles else None) for _, n in asked}
                return subprocess.CompletedProcess(
                    argv, 0, stdout=json.dumps({"data": {"repository": repo}}), stderr=""
                )
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
        self.assertEqual(body["source"], REPO_TABLE["source"])
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
        # Closed on v0.2.0's day, three hours after the tag: the instants put it in v0.3.0.
        self.assertEqual(by_title["Empty state"]["reachedOn"], "2026-10-01")
        self.assertEqual(by_title["Empty state"]["closed_time"], "2026-10-01T15:00:00Z")
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
            Path(self.tmp.name) / "other",
            {**REPO_TABLE, "repo": "acme/gadgets", "commits": REPO_TABLE["commits"][:1], "side": []},
        )
        self._checkout(str(other))
        body = self._get("/api/ritual/releases")[0].json()
        self.assertFalse(body["source"]["ok"])
        self.assertIn("acme/gadgets", body["source"]["reason"])

    def test_no_tag_yet_is_one_release_in_progress(self):
        bare = build_repo(
            Path(self.tmp.name) / "bare",
            {**REPO_TABLE, "commits": [{**c, "tags": []} for c in REPO_TABLE["commits"]], "side": []},
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

    def test_a_tag_on_a_branch_never_merged_is_not_a_release(self):
        body = self._get("/api/ritual/releases")[0].json()
        self.assertNotIn("v0.2.1", [r["tag"] for r in body["releases"]])
        self.assertNotIn(15, [p["number"] for r in body["releases"] for p in r["pulls"]])

    def test_the_branch_checked_out_is_not_the_release_in_progress(self):
        # The clone has import-lists checked out, one commit past main with its
        # own changelog.d entry: neither is in the release in progress.
        self.assertEqual(
            _REAL_RUN(
                ["git", "branch", "--show-current"], cwd=self.clone, capture_output=True, text=True
            ).stdout.strip(),
            "import-lists",
        )
        now = self._get("/api/ritual/releases")[0].json()["releases"][0]
        self.assertNotIn(17, [p["number"] for p in now["pulls"]])
        self.assertNotIn("Import a list from a file.", [e for n in now["notes"] for e in n["entries"]])

    def test_the_variants(self):
        for v in REPO_TABLE["variants"]:
            with self.subTest(v["name"]):
                clone = build_repo(Path(self.tmp.name) / re.sub(r"\W+", "-", v["name"]), origin=v.get("origin", True))
                self._checkout(str(clone))
                cfg = json.loads(self.default.read_text(encoding="utf-8"))
                cfg["spaces"][0]["projects"] = (
                    [{"name": "Widgets", "repo": "widgets", "defaultBranch": v["defaultBranch"]}]
                    if v.get("defaultBranch")
                    else []
                )
                self.default.write_text(json.dumps(cfg), encoding="utf-8")
                body = self._get("/api/ritual/releases", tier=2)[0].json()
                self.assertEqual(body["source"], {"ok": True, "reason": "", "ref": v["ref"]})
                now = _summary(body["releases"][0])
                self.assertEqual({k: now[k] for k in v["inProgress"]}, v["inProgress"])
                self.assertEqual([r["tag"] for r in body["releases"][1:]], v["tags"])

    # -- the titles read ----------------------------------------------------

    def test_titles_one_batched_read_fields_as_fields(self):
        res, calls = self._get("/api/ritual/releases/titles?numbers=12,8,99")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["tracker"], {"ok": True, "reason": ""})
        self.assertEqual(
            (body["space"], body["repo"], body["asked"], body["limit"]), ("widgets", REPO, 3, R.TITLES_LIMIT)
        )
        # 99 is not an issue GitHub could resolve: absent, never an error.
        self.assertEqual(
            body["titles"],
            [{"number": 8, "title": "Find a widget by name"}, {"number": 12, "title": "Export the list"}],
        )
        self.assertEqual(len(calls), 1)
        argv = calls[0]
        self.assertEqual(argv[:3], ["gh", "api", "graphql"])
        self.assertIn("owner=acme", argv)
        self.assertIn("name=widgets", argv)
        self.assertFalse(any("&" in a for a in argv), argv)
        self.assertEqual(re.findall(r"i(\d+): issueOrPullRequest", self.queries[0]), ["8", "12", "99"])

    def test_titles_are_kept_a_minute(self):
        self._get("/api/ritual/releases/titles?numbers=8,12")
        _res, calls = self._get("/api/ritual/releases/titles?numbers=12,8")
        self.assertEqual(calls, [])
        _res, calls = self._get("/api/ritual/releases/titles?numbers=12,8&refresh=1")
        self.assertEqual(len(calls), 1)

    def test_titles_no_numbers_makes_no_call(self):
        res, calls = self._get("/api/ritual/releases/titles")
        self.assertEqual(res.status_code, 200)
        self.assertEqual((res.json()["titles"], res.json()["asked"]), ([], 0))
        self.assertEqual(calls, [])

    def test_titles_past_the_cap_reads_the_first_and_says_how_many_were_asked(self):
        numbers = list(range(1, R.TITLES_LIMIT + 11))
        res, calls = self._get("/api/ritual/releases/titles?numbers=" + ",".join(map(str, reversed(numbers))))
        body = res.json()
        self.assertEqual((body["asked"], body["limit"]), (R.TITLES_LIMIT + 10, R.TITLES_LIMIT))
        asked = [int(n) for n in re.findall(r"i(\d+): issueOrPullRequest", self.queries[0])]
        self.assertEqual(asked, numbers[: R.TITLES_LIMIT])
        self.assertEqual(len(calls), 1)

    def test_titles_no_tracker_is_a_reason_and_no_call(self):
        res, calls = self._get("/api/ritual/releases/titles?numbers=8", tier=2)
        self.assertEqual(res.status_code, 200)
        self.assertFalse(res.json()["tracker"]["ok"])
        self.assertTrue(res.json()["tracker"]["reason"])
        self.assertEqual(res.json()["titles"], [])
        self.assertEqual(calls, [])

    def test_titles_gh_not_answering_is_a_reason(self):
        body = self._get("/api/ritual/releases/titles?numbers=8", gh_fails=True)[0].json()
        self.assertFalse(body["tracker"]["ok"])
        self.assertTrue(body["tracker"]["reason"].startswith(f"{REPO}: "), body["tracker"]["reason"])
        self.assertEqual(body["titles"], [])

    def test_titles_a_number_that_is_not_one_is_422(self):
        res, calls = self._get("/api/ritual/releases/titles?numbers=8,abc")
        self.assertEqual(res.status_code, 422)
        self.assertIn("abc", res.json()["detail"])
        self.assertEqual(calls, [])

    def test_titles_an_unknown_space_is_404(self):
        res, calls = self._get("/api/ritual/releases/titles?space=nowhere&numbers=8")
        self.assertEqual(res.status_code, 404)
        self.assertEqual(calls, [])

    def test_the_titles_route_is_the_contracts(self):
        self.assertEqual(C.rituals_release_titles_route(), "/api/ritual/releases/titles")

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_releases_route(), "/api/ritual/releases")


class TheRouteWithTheFlagOff(TheRoute):
    features = {}

    def test_off_is_404_not_403(self):
        for path in ("/api/ritual/releases?space=widgets", "/api/ritual/releases/titles?space=widgets&numbers=8"):
            with self.subTest(path):
                res, calls = self._get(path)
                self.assertEqual(res.status_code, 404)
                self.assertIn("features.solitaireAgile", res.json()["detail"])
                self.assertEqual(calls, [])

    for _name in [
        n
        for n in dir(TheRoute)
        if n.startswith("test_")
        and n not in ("test_the_route_is_the_contracts", "test_the_titles_route_is_the_contracts")
    ]:
        locals()[_name] = None
    del _name


class TheRouteWhereTheSpaceWorksAlone(TheRoute):
    """The switch on, but the Space answered `alone`: Team Agile is off there too."""

    def setUp(self):
        super().setUp()
        cfg = json.loads(config.DEFAULT_CONFIG_PATH.read_text(encoding="utf-8"))
        cfg["spaces"][0]["howIWork"] = "alone"
        config.DEFAULT_CONFIG_PATH.write_text(json.dumps(cfg), encoding="utf-8")

    def test_off_in_this_space_is_404(self):
        for path in ("/api/ritual/releases", "/api/ritual/releases/titles?numbers=8"):
            with self.subTest(path):
                res, calls = self._get(path)
                self.assertEqual(res.status_code, 404)
                self.assertIn("howIWork", res.json()["detail"])
                self.assertEqual(calls, [])

    for _name in [
        n
        for n in dir(TheRoute)
        if n.startswith("test_")
        and n not in ("test_the_route_is_the_contracts", "test_the_titles_route_is_the_contracts")
    ]:
        locals()[_name] = None
    del _name


if __name__ == "__main__":
    unittest.main()
