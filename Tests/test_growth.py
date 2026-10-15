"""The growth module's routes, its gate, and the file-shape contract.

Three claims, and the third is the one that needed a test rather than an
agreement:

  (a) the routes read and write ``<promptsRoot>/growth``, ``reviews`` and
      ``resume`` -- hub-root folders, resolved from config, never from where
      this package sits;
  (b) ``features.growth`` false means the routes are ABSENT: 404, not 403. Off
      means absent is the rule the whole shell is built on, and a 403 would be
      saying something else;
  (c) the CLI and the agent write the SAME BYTES for the same inputs. Two
      consumers of one documented file shape do not stay honest by agreeing to;
      this runs ``New-GrowthItem.ps1`` in a scratch hub, posts the same fields,
      and compares the files.

Run directly:  python3 Tests/test_growth.py
Under pytest:  python3 -m pytest Tests/
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

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.core import config
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURE_HUB = PKG_ROOT / "Tests" / "fixtures" / "hub"
NEW_GROWTH = PKG_ROOT / "Scripts" / "New-GrowthItem.ps1"


def _client(hub: Path, *, growth: bool = True, extra_default: dict | None = None):
    """A TestClient over a hub of our choosing, with the flag where we want it.

    Everything is a context manager the caller closes: the config module reads
    its two paths on every call, so pointing them at throwaway files is all it
    takes to run against a config that is not the machine's.
    """
    tmp = tempfile.TemporaryDirectory()
    base = Path(tmp.name)
    default_path = base / "config.default.json"
    local_path = base / "config.local.json"

    defaults = {
        "activeSpace": "test",
        "commandPrefix": "tk",
        "features": {"growth": growth},
        "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
        "commands": {},
    }
    defaults.update(extra_default or {})
    default_path.write_text(json.dumps(defaults), encoding="utf-8")
    local_path.write_text(json.dumps({"promptsRoot": str(hub)}), encoding="utf-8")

    patches = [
        mock.patch.object(config, "DEFAULT_CONFIG_PATH", default_path),
        mock.patch.object(config, "LOCAL_CONFIG_PATH", local_path),
        # The hub is named in the config above; PROMPTS_ROOT must not shadow it
        # from whatever shell the suite happens to be running in.
        mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
    ]
    for p in patches:
        p.start()

    from agent.app import app

    return TestClient(app), patches, tmp


class _RoutesCase(unittest.TestCase):
    """Base: a client over the committed fixture hub with growth switched on."""

    hub = FIXTURE_HUB
    growth = True

    def setUp(self):
        self.client, self._patches, self._tmp = _client(self.hub, growth=self.growth)

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        self._tmp.cleanup()


# ---------------------------------------------------------------------------
# (a) Reading the hub
# ---------------------------------------------------------------------------


class GrowthListTests(_RoutesCase):
    def test_lists_one_item_per_type_from_the_fixture_hub(self):
        body = self.client.get("/api/growth").json()
        self.assertEqual(len(body["items"]), 3, body)
        self.assertEqual(
            sorted(i["type"] for i in body["items"]),
            ["goal", "presentation", "training"],
        )

    def test_reads_the_title_out_of_the_file_not_the_filename(self):
        items = {i["type"]: i for i in self.client.get("/api/growth").json()["items"]}
        self.assertEqual(items["training"]["title"], "Distributed Systems Fundamentals")
        self.assertEqual(items["presentation"]["title"], "Designing for Non-Determinism")
        self.assertEqual(items["goal"]["title"], "Improve test coverage patterns")

    def test_the_detail_route_serves_the_files_absolute_path(self):
        """The address a person hands to an assistant."""
        name = "training-2026-03-02-distributed-systems-fundamentals.prompt.md"
        body = self.client.get(f"/api/growth/{name}").json()
        path = Path(body["path"])
        self.assertTrue(path.is_absolute(), body["path"])
        self.assertEqual(path, (self.hub / "growth" / "current" / name).resolve())
        self.assertTrue(path.is_file())

    def test_training_carries_provider_and_hours(self):
        items = {i["type"]: i for i in self.client.get("/api/growth").json()["items"]}
        self.assertEqual(items["training"]["provider"], "Internal Academy")
        self.assertEqual(items["training"]["hours"], "12")

    def test_the_end_of_a_range_is_the_deadline(self):
        items = {i["type"]: i for i in self.client.get("/api/growth").json()["items"]}
        self.assertEqual(items["training"]["due_date"], "2026-04-30")
        self.assertEqual(items["goal"]["due_date"], "2026-12-31")

    def test_a_fresh_file_reads_as_new_not_active(self):
        # Every fixture says "Not Started", and the page's ordering depends on
        # the three status words meaning what they say.
        for item in self.client.get("/api/growth").json()["items"]:
            if item["type"] != "presentation":
                self.assertEqual(item["status"], "new", item)

    def test_a_folder_that_is_not_there_is_empty_rather_than_an_error(self):
        with tempfile.TemporaryDirectory() as empty:
            client, patches, tmp = _client(Path(empty))
            try:
                r = client.get("/api/growth")
                self.assertEqual(r.status_code, 200)
                self.assertEqual(r.json()["items"], [])
            finally:
                for p in reversed(patches):
                    p.stop()
                tmp.cleanup()


class GrowthDetailTests(_RoutesCase):
    FILENAME = "training-2026-03-02-distributed-systems-fundamentals.prompt.md"

    def test_returns_the_whole_file(self):
        body = self.client.get(f"/api/growth/{self.FILENAME}").json()
        self.assertEqual(body["type"], "training")
        self.assertIn("## Key Takeaways", body["content"])

    def test_an_unknown_file_is_404(self):
        self.assertEqual(self.client.get("/api/growth/training-2026-01-01-nope.prompt.md").status_code, 404)

    def test_a_path_is_not_a_filename(self):
        # A backslash over the wire, because %2F is a path separator the client
        # and the server both normalise away before any route sees it -- so the
        # tempting `..%2F..%2Fconfig.local.json` never reaches this guard and
        # proves nothing about it.
        r = self.client.get("/api/growth/..%5C..%5Cconfig.local.json")
        self.assertIn(r.status_code, (400, 404), r.text)

    def test_the_guard_itself_refuses_every_shape_of_path(self):
        # Called directly, so URL normalisation cannot stand in for the check.
        import asyncio

        from fastapi import HTTPException

        from agent.growth.growth import get_growth_detail

        for name in ("../config.local.json", "..\\config.local.json", "sub/dir.prompt.md", "..", "a/../b.prompt.md"):
            with self.subTest(filename=name):
                with self.assertRaises(HTTPException) as caught:
                    asyncio.run(get_growth_detail(name))
                self.assertIn(caught.exception.status_code, (400, 404), name)


class ResumeTests(_RoutesCase):
    def test_serves_the_hubs_resume(self):
        body = self.client.get("/api/resume").json()
        self.assertIn("# Resume", body["content"])
        self.assertIsNotNone(body["last_modified"])

    def test_names_the_file_by_its_absolute_path(self):
        body = self.client.get("/api/resume").json()
        self.assertTrue(Path(body["path"]).is_absolute(), body["path"])
        self.assertEqual(Path(body["path"]), (self.hub / "resume" / "resume.md").resolve())

    def test_a_hub_with_no_resume_is_404_not_an_empty_string(self):
        with tempfile.TemporaryDirectory() as empty:
            client, patches, tmp = _client(Path(empty))
            try:
                self.assertEqual(client.get("/api/resume").status_code, 404)
            finally:
                for p in reversed(patches):
                    p.stop()
                tmp.cleanup()


class ReviewsTests(_RoutesCase):
    FOLDER = "2026-04-01_2026-04-30"

    def test_lists_the_fixture_review_for_the_active_space(self):
        body = self.client.get("/api/reviews").json()
        self.assertEqual(body["count"], 1, body)
        self.assertEqual(body["reviews"][0]["folder"], self.FOLDER)
        self.assertEqual(body["reviews"][0]["start_date"], "2026-04-01")

    def test_the_engagement_review_list_names_its_spaces(self):
        """The archive card maps over ``item.spaces`` (web api.growth.ts). The
        route built the key and its response model still said ``orgs``, so
        Pydantic dropped it and the card threw on undefined -- found by the
        smoke's modules-on run, a miss no test held."""
        body = self.client.get("/api/engagement/test/reviews").json()
        self.assertEqual(len(body), 1, body)
        self.assertEqual(body[0]["spaces"], ["test"])
        self.assertNotIn("orgs", body[0])
        self.assertEqual(body[0]["link"], f"/reviews/{self.FOLDER}")

    def test_returns_one_reviews_content(self):
        body = self.client.get(f"/api/reviews/{self.FOLDER}").json()
        self.assertIn("By the Numbers", body["content"])
        self.assertIn(self.FOLDER, body["folder"])

    def test_names_the_review_file_by_its_absolute_path(self):
        body = self.client.get(f"/api/reviews/{self.FOLDER}").json()
        self.assertTrue(Path(body["path"]).is_absolute(), body["path"])
        self.assertEqual(Path(body["path"]).name, "review.md")
        self.assertIn(self.FOLDER, body["path"])

    def test_a_folder_that_is_not_a_date_range_is_refused(self):
        self.assertEqual(self.client.get("/api/reviews/not-a-range").status_code, 400)

    def test_an_unknown_range_is_404(self):
        self.assertEqual(self.client.get("/api/reviews/2019-01-01_2019-01-31").status_code, 404)

    def test_generate_refuses_an_empty_slug_list(self):
        r = self.client.post(
            "/api/review/generate",
            json={
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
                "slugs": [],
            },
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("slugs", r.json()["detail"])

    def test_generate_refuses_an_org_this_install_does_not_have(self):
        r = self.client.post(
            "/api/review/generate",
            json={
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
                "slugs": ["nosuchorg"],
            },
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("nosuchorg", r.json()["detail"])

    def test_generate_refuses_a_date_that_is_not_a_date(self):
        r = self.client.post(
            "/api/review/generate",
            json={
                "start_date": "April 1",
                "end_date": "2026-04-30",
                "slugs": ["test"],
            },
        )
        self.assertEqual(r.status_code, 400)


# ---------------------------------------------------------------------------
# (b) The gate
# ---------------------------------------------------------------------------


class FlagOffTests(_RoutesCase):
    """Off means ABSENT. Every route answers 404, and none of them 403."""

    growth = False

    ROUTES = [
        ("get", "/api/growth"),
        ("get", "/api/growth/training-2026-03-02-distributed-systems-fundamentals.prompt.md"),
        ("get", "/api/resume"),
        ("get", "/api/resume-preview"),
        ("get", "/api/reviews"),
        ("get", "/api/reviews/2026-04-01_2026-04-30"),
        ("get", "/api/review-preview"),
    ]

    def test_every_read_route_is_404(self):
        for method, path in self.ROUTES:
            with self.subTest(path=path):
                self.assertEqual(getattr(self.client, method)(path).status_code, 404)

    def test_the_write_routes_are_404_too(self):
        self.assertEqual(
            self.client.post(
                "/api/growth",
                json={
                    "type": "goal",
                    "title": "x",
                    "date": "2026-01-01",
                },
            ).status_code,
            404,
        )
        self.assertEqual(
            self.client.post(
                "/api/review/generate",
                json={
                    "start_date": "2026-04-01",
                    "end_date": "2026-04-30",
                    "slugs": ["test"],
                },
            ).status_code,
            404,
        )

    def test_never_403(self):
        # A 403 would say the route exists and you may not have it. It does not
        # exist: this install does not have the module.
        for method, path in self.ROUTES:
            with self.subTest(path=path):
                self.assertNotEqual(getattr(self.client, method)(path).status_code, 403)

    def test_the_gate_is_re_read_per_request_not_frozen_at_mount(self):
        # Same process, same app: flipping the flag takes effect on the next
        # request, exactly as a switch-org from another shell already does.
        self.assertEqual(self.client.get("/api/growth").status_code, 404)
        on, patches, tmp = _client(self.hub, growth=True)
        try:
            self.assertEqual(on.get("/api/growth").status_code, 200)
        finally:
            for p in reversed(patches):
                p.stop()
            tmp.cleanup()

    def test_the_ado_core_is_untouched_by_the_module_being_off(self):
        self.assertEqual(self.client.get("/api/health").status_code, 200)
        self.assertEqual(self.client.get("/api/status").status_code, 200)


# ---------------------------------------------------------------------------
# (c) Writing, and the shape contract
# ---------------------------------------------------------------------------


class GrowthCreateTests(unittest.TestCase):
    def setUp(self):
        self._hub = tempfile.TemporaryDirectory()
        self.hub = Path(self._hub.name)
        self.client, self._patches, self._tmp = _client(self.hub)

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        self._tmp.cleanup()
        self._hub.cleanup()

    def test_creates_a_training_and_names_it_by_type_date_and_slug(self):
        r = self.client.post(
            "/api/growth",
            json={
                "type": "training",
                "title": "Clean Architecture",
                "date": "2026-03-02",
                "due_date": "2026-04-30",
            },
        )
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["filename"], "training-2026-03-02-clean-architecture.prompt.md")
        self.assertTrue((self.hub / "growth/current" / r.json()["filename"]).exists())

    def test_a_goal_is_dated_by_year(self):
        r = self.client.post(
            "/api/growth",
            json={
                "type": "goal",
                "title": "Improve test coverage patterns",
                "date": "2026-01-01",
            },
        )
        self.assertEqual(r.json()["filename"], "goal-2026-improve-test-coverage-patterns.prompt.md")

    def test_the_new_file_is_immediately_listed(self):
        self.client.post(
            "/api/growth",
            json={
                "type": "goal",
                "title": "Read more code",
                "date": "2026-02-01",
            },
        )
        titles = [i["title"] for i in self.client.get("/api/growth").json()["items"]]
        self.assertIn("Read more code", titles)

    def test_writing_over_an_existing_file_is_refused(self):
        body = {"type": "goal", "title": "Read more code", "date": "2026-02-01"}
        self.assertEqual(self.client.post("/api/growth", json=body).status_code, 200)
        self.assertEqual(self.client.post("/api/growth", json=body).status_code, 409)

    def test_a_training_must_say_when_it_is_due(self):
        r = self.client.post(
            "/api/growth",
            json={
                "type": "training",
                "title": "Something",
                "date": "2026-03-02",
            },
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("due_date", r.json()["detail"])

    def test_a_type_this_module_does_not_have_is_refused(self):
        r = self.client.post(
            "/api/growth",
            json={
                "type": "podcast",
                "title": "Something",
                "date": "2026-03-02",
            },
        )
        self.assertEqual(r.status_code, 400)

    def test_a_date_that_is_not_a_date_is_refused(self):
        r = self.client.post("/api/growth", json={"type": "goal", "title": "Something", "date": "March"})
        self.assertEqual(r.status_code, 400)


class HeadingReaderTests(unittest.TestCase):
    """A heading's value is the first VALUE line under it, not the first
    non-empty one. Two fixtures the reader used to misread:
    a training with no provider, whose next non-empty line is the writer's
    ``---``; and a file made by hand from the template, whose next non-empty
    line is the template's own ``<!-- hint -->``."""

    TEMPLATE = PKG_ROOT / "templates" / "Training.template.md"

    def setUp(self):
        self._hub = tempfile.TemporaryDirectory()
        self.hub = Path(self._hub.name)
        self.client, self._patches, self._tmp = _client(self.hub)

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()
        self._tmp.cleanup()
        self._hub.cleanup()

    def _items(self) -> dict:
        return {i["filename"]: i for i in self.client.get("/api/growth").json()["items"]}

    def test_an_empty_provider_is_none_not_the_separator(self):
        r = self.client.post(
            "/api/growth",
            json={
                "type": "training",
                "title": "No Provider Yet",
                "date": "2026-03-02",
                "due_date": "2026-04-30",
            },
        )
        self.assertEqual(r.status_code, 200, r.text)
        item = self._items()[r.json()["filename"]]
        self.assertIsNone(item["provider"], item)
        # The rest of the file is still read: the separator was skipped, not
        # the section boundary.
        self.assertEqual(item["title"], "No Provider Yet")
        self.assertEqual(item["hours"], "TBD")
        self.assertEqual(item["status"], "new")

    def test_a_template_made_file_reads_like_a_generated_one(self):
        folder = self.hub / "growth" / "current"
        folder.mkdir(parents=True, exist_ok=True)
        name = "training-2026-05-01-made-from-the-template.prompt.md"
        (folder / name).write_bytes(self.TEMPLATE.read_bytes())
        item = self._items()[name]
        # Every heading in the template is followed by a comment and nothing else.
        self.assertEqual(item["title"], Path(name).stem, item)  # the stem, as for a generated file with no title
        self.assertEqual(item["date"], "", item)
        self.assertIsNone(item["due_date"], item)
        self.assertIsNone(item["provider"], item)
        self.assertIsNone(item["hours"], item)
        for value in (item["title"], item["date"], item["provider"] or "", item["hours"] or ""):
            self.assertNotIn("<!--", value)
            self.assertNotIn("-->", value)

    def test_a_multi_line_comment_is_skipped_whole(self):
        from agent.growth.growth import _heading_value

        lines = [
            "## Date(s)",
            "<!-- A completion date, or a range written 'YYYY-MM-DD to YYYY-MM-DD'.",
            "     ASCII 'to', never a dash: both readers parse this line. -->",
            "2026-03-02 to 2026-04-30",
            "",
            "## Hours",
        ]
        self.assertEqual(_heading_value(lines, "date(s)"), "2026-03-02 to 2026-04-30")
        self.assertIsNone(_heading_value(lines, "hours"))

    def test_the_section_ends_at_the_next_heading(self):
        from agent.growth.growth import _heading_value

        lines = ["## Provider", "", "---", "", "## Description", "", "Not the provider."]
        self.assertIsNone(_heading_value(lines, "provider"))
        self.assertEqual(_heading_value(lines, "description"), "Not the provider.")


@unittest.skipIf(shutil.which("pwsh") is None, "pwsh is not on this machine")
class CliParityTests(unittest.TestCase):
    """The CLI and the agent write the same bytes for the same inputs.

    Not "the same headings" or "the same fields": the same bytes, because the
    file IS the record and a person reads it in an editor. Line endings, the
    trailing newline and the absence of a BOM are all part of the shape.
    """

    CASES = [
        (
            "training",
            {
                "type": "training",
                "title": "Clean Architecture",
                "date": "2026-03-02",
                "due_date": "2026-04-30",
                "provider": "Internal Academy",
                "hours": "8",
                "notes": "Boundaries, and which ones are worth the indirection.",
            },
            [
                "-Type",
                "training",
                "-Title",
                "Clean Architecture",
                "-Date",
                "2026-03-02",
                "-DueDate",
                "2026-04-30",
                "-Provider",
                "Internal Academy",
                "-Hours",
                "8",
                "-Notes",
                "Boundaries, and which ones are worth the indirection.",
            ],
        ),
        (
            "presentation",
            {
                "type": "presentation",
                "title": "Designing for Non-Determinism",
                "date": "2026-05-14",
                "notes": "Testing systems whose answers are allowed to differ.",
            },
            [
                "-Type",
                "presentation",
                "-Title",
                "Designing for Non-Determinism",
                "-Date",
                "2026-05-14",
                "-Notes",
                "Testing systems whose answers are allowed to differ.",
            ],
        ),
        (
            "goal",
            {
                "type": "goal",
                "title": "Improve test coverage patterns",
                "date": "2026-01-01",
                "due_date": "2026-12-31",
                "notes": "Make the suites say something about behaviour.",
            },
            [
                "-Type",
                "goal",
                "-Title",
                "Improve test coverage patterns",
                "-Date",
                "2026-01-01",
                "-DueDate",
                "2026-12-31",
                "-Notes",
                "Make the suites say something about behaviour.",
            ],
        ),
    ]

    def test_the_two_consumers_write_identical_files(self):
        # Whose name goes on a presentation comes from config, and the two
        # halves must be reading the SAME config for that -- so the agent is
        # told what the CLI will resolve rather than a value invented here.
        branch_user = (config.load_config().get("branchUser") or "").strip()

        for label, payload, cli_args in self.CASES:
            with (
                self.subTest(type=label),
                tempfile.TemporaryDirectory() as cli_hub,
                tempfile.TemporaryDirectory() as api_hub,
            ):
                env = {**os.environ, "PROMPTS_ROOT": cli_hub, "TOOLKIT_QUIET_STARTUP": "1"}
                run = subprocess.run(
                    ["pwsh", "-NoProfile", "-File", str(NEW_GROWTH), *cli_args],
                    capture_output=True,
                    text=True,
                    timeout=120,
                    env=env,
                    check=False,
                )
                self.assertEqual(run.returncode, 0, run.stderr or run.stdout)

                client, patches, tmp = _client(Path(api_hub), extra_default={"branchUser": branch_user})
                try:
                    r = client.post("/api/growth", json=payload)
                    self.assertEqual(r.status_code, 200, r.text)
                    api_name = r.json()["filename"]
                finally:
                    for p in reversed(patches):
                        p.stop()
                    tmp.cleanup()

                cli_files = sorted((Path(cli_hub) / "growth/current").iterdir())
                self.assertEqual(len(cli_files), 1, cli_files)
                self.assertEqual(cli_files[0].name, api_name)

                cli_bytes = cli_files[0].read_bytes()
                api_bytes = (Path(api_hub) / "growth/current" / api_name).read_bytes()
                self.assertEqual(
                    cli_bytes.decode("utf-8"),
                    api_bytes.decode("utf-8"),
                    f"{label}: the CLI and the agent disagree about the file shape",
                )
                self.assertEqual(cli_bytes, api_bytes, f"{label}: same text, different bytes")
                self.assertFalse(cli_bytes.startswith(b"\xef\xbb\xbf"), "a BOM crept in")
                self.assertNotIn(b"\r\n", cli_bytes, "CRLF crept in")
                self.assertTrue(cli_bytes.endswith(b"\n"), "no trailing newline")

    def test_the_documented_shape_is_what_both_of_them_write(self):
        # docs/hub/growth.md is the contract, and a reader has to be able to
        # find the headings it names in a real file.
        doc = (PKG_ROOT / "docs" / "hub" / "growth.md").read_text(encoding="utf-8")
        for path in sorted((FIXTURE_HUB / "growth" / "current").iterdir()):
            with self.subTest(file=path.name):
                for line in path.read_text(encoding="utf-8").splitlines():
                    if line.startswith("## "):
                        self.assertIn(
                            line.strip(), doc, f"{path.name} has a heading docs/hub/growth.md does not document"
                        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
