"""The growth module's routes, its gate, and the file-shape contract.

Three claims:

  (a) the routes read and write ``<promptsRoot>/growth``, ``reviews`` and
      ``resume`` -- hub-root folders, resolved from config, never from where
      this package sits;
  (b) ``features.growth`` false means the routes are ABSENT: 404, not 403. Off
      means absent is the rule the whole shell is built on, and a 403 would be
      saying something else;
  (c) the reader takes what the writer writes. There is one writer of a growth
      item, ``NewGrowth`` (the browser runs it through the bridge), so there is
      no second writer to compare bytes with; what is held here is that a file
      in the documented shape -- and one made by hand from the template -- reads
      the way docs/hub/growth.md says.

Run directly:  python3 Tests/test_growth.py
Under pytest:  python3 -m pytest Tests/
"""

import json
import os
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

    # What ``NewGrowth -Type training -Title "No Provider Yet"`` with a start day and a
    # later due day writes (Scripts/New-GrowthItem.ps1): the provider's
    # heading is followed by an empty line and then the writer's ``---``.
    NO_PROVIDER = (
        "# Training Artifact\n\n---\n\n## Title\n\nNo Provider Yet\n\n## Type\n\nVoluntary\n\n"
        "## Date(s)\n\n2026-03-02 to 2026-04-30\n\n## Hours\n\nTBD\n\n## Provider\n\n\n\n---\n\n"
        "## Description\n\n\n\n---\n\n## Status\n\nNot Started\n\n## Key Takeaways\n\n-\n-\n-\n\n---\n\n"
        "## Outcome\n\n- **Completed**: No\n- **Certificate / badge**:\n- **Applied to work**:\n"
    )

    def test_an_empty_provider_is_none_not_the_separator(self):
        folder = self.hub / "growth" / "current"
        folder.mkdir(parents=True, exist_ok=True)
        name = "training-2026-03-02-no-provider-yet.prompt.md"
        (folder / name).write_bytes(self.NO_PROVIDER.encode("utf-8"))
        item = self._items()[name]
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

    def test_a_manager_session_stage_skips_a_comment_under_its_heading(self):
        from agent.communication.manager import _heading_value as manager_reader
        from agent.growth.growth import _heading_value as growth_reader

        lines = ["## Stage", "<!-- draft, sent or closed -->", "draft", "", "## Agenda"]
        self.assertEqual(manager_reader(lines, "stage"), "draft")
        self.assertIs(manager_reader, growth_reader)


class DocumentedShapeTests(unittest.TestCase):
    """docs/hub/growth.md is the contract for a growth file's shape."""

    def test_the_fixture_files_use_only_documented_headings(self):
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
