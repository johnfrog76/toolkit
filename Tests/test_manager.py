"""The 1:1 surface: list, read, create, save -- and the two gates.

Every test here runs against a real hub on disk (a copy of the committed
fixture, so a write test cannot dirty the repo) with config pointed at it. The
routes are exercised through the app, not called as functions, because half of
what is under test is the gate -- and a gate that is a router dependency only
exists when something routes through it.

Two gates, and they are not the same thing:

  1. features.communication decides whether the module answers at all. Off is a
     404, the same answer a module that was never written would give.
  2. The recipient's webhook environment variable decides whether a send can
     happen. /env reports it BEFORE the click, with the variable's name, so the
     UI can offer a disabled button instead of discovering the problem after.

The dummy webhook value below is a string, never a URL. Nothing in this file
reaches the network.
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.ado import bridge
    from agent.communication import manager
    from agent.core import config, consts, env
    from agent.core.hosts import resolve_host
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

FIXTURE_HUB = REPO_ROOT / "Tests" / "fixtures" / "hub"

# The environment variable that replaces config.local.json's features block for
# one process, in the child pwsh the bridge starts as well as in this one.
FEATURES_ENV = consts.env_features()

HAVE_HOST = resolve_host() is not None

# A value, not an address. The point is only that the variable is set.
DUMMY_WEBHOOK = "set-for-this-test"


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


class ManagerRouteTestCase(unittest.TestCase):
    """A hub of its own, config pointed at it, and the flag on."""

    features = {"communication": True}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.hub = base / "hub"
        shutil.copytree(FIXTURE_HUB, self.hub)

        self.default_path = base / "config.default.json"
        self.local_path = base / "config.local.json"
        _write(
            self.default_path,
            {
                "activeSpace": "test",
                "features": self.features,
                "promptsRoot": str(self.hub),
                "managerWorkflow": {
                    "retroChannel": "manager",
                    "postRetroSummary": True,
                    "communication": {
                        "recipients": {
                            "manager": {
                                "type": "channel",
                                "display": "My Manager",
                                "webhookEnv": "TEAMS_WEBHOOK_MANAGER",
                            }
                        }
                    },
                },
                "spaces": [{"slug": "test", "status": "local", "promptsFolder": "test"}],
            },
        )
        _write(self.local_path, {})

        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", self.local_path),
            mock.patch.object(manager.comms, "DEFAULT_CONFIG_PATH", self.default_path),
            mock.patch.object(manager.comms, "LOCAL_CONFIG_PATH", self.local_path),
            # PROMPTS_ROOT is an override and would win over the config under test.
            mock.patch.dict(os.environ, {}, clear=False),
            # The bridge keeps the CLI's command table, keyed on file mtimes and
            # not on the environment, so a table another suite cached with the
            # communication verbs off would answer this one.
            mock.patch.object(bridge, "_map_cache", {}),
            mock.patch.object(bridge, "_map_key", None),
        ]
        for p in self.patches:
            p.start()
        os.environ.pop("PROMPTS_ROOT", None)
        os.environ.pop("TEAMS_WEBHOOK_MANAGER", None)
        os.environ.pop("TEAMS_WEBHOOK_URL", None)
        # The create goes through the bridge, whose child pwsh reads this
        # checkout's config, not the scratch one above -- and a checkout with no
        # config.local.json has every module off, so the child has no NewMeeting.
        #P20_FEATURES is the per-process stand-in both halves
        # read for config.local.json's features block (consts.json env.features).
        os.environ[FEATURES_ENV] = json.dumps(self.features)

        app = FastAPI()
        app.include_router(manager.api, prefix="/api")
        app.include_router(env.api, prefix="/api")
        self.client = TestClient(app)

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def session(self, name: str) -> Path:
        return self.hub / "manager" / "current" / name


class ListAndRead(ManagerRouteTestCase):
    def test_lists_every_fixture_session_newest_first(self):
        items = self.client.get("/api/manager").json()["items"]
        self.assertEqual(
            [i["filename"] for i in items],
            ["2026-02-05.md", "2026-01-22.md", "2026-01-08.md"],
        )

    def test_each_stage_is_read_from_the_file(self):
        items = {i["filename"]: i for i in self.client.get("/api/manager").json()["items"]}
        self.assertEqual(items["2026-01-08.md"]["stage"], "draft")
        self.assertEqual(items["2026-01-22.md"]["stage"], "prep")
        self.assertEqual(items["2026-02-05.md"]["stage"], "retro")

    def test_a_placeholder_is_not_a_summary(self):
        # The draft session's Agenda says "(populated by the Plan pass)". That
        # is the file describing its own template, and listing it as a summary
        # is how a fresh session looked like it had content.
        items = {i["filename"]: i for i in self.client.get("/api/manager").json()["items"]}
        self.assertEqual(items["2026-01-08.md"]["summary"], "")
        self.assertTrue(items["2026-02-05.md"]["summary"])

    def test_detail_splits_the_sections_the_form_owns(self):
        data = self.client.get("/api/manager/2026-01-22.md").json()
        self.assertEqual(data["session_stage"], "prep")
        self.assertIn("Queue timeouts are fixed", data["since"])
        self.assertIn("becomes a project by accident", data["forward"])
        self.assertIn("## Agenda", data["content"])
        self.assertEqual(data["sent"], "")

    def test_detail_serves_the_files_absolute_path(self):
        """The address a person hands to an assistant."""
        path = Path(self.client.get("/api/manager/2026-01-22.md").json()["path"])
        self.assertTrue(path.is_absolute())
        self.assertEqual(path, (self.hub / "manager" / "current" / "2026-01-22.md").resolve())
        self.assertTrue(path.is_file())

    def test_detail_says_which_folder_the_session_is_in(self):
        # GET serves a closed session and PUT refuses one, so the folder has to
        # be on the detail: a client that sends the retro and then records it
        # must know BEFORE the send that it cannot record.
        self.assertEqual(self.client.get("/api/manager/2026-01-08.md").json()["folder"], "current")
        archive = self.hub / "manager" / "archive"
        archive.mkdir(parents=True, exist_ok=True)
        (archive / "2025-12-11.md").write_text(
            "# 2025-12-11\n\n## Stage\nretro\n\n## Agenda\n- done\n\n**Closed:** 2025-12-12\n",
            encoding="utf-8",
        )
        res = self.client.get("/api/manager/2025-12-11.md")
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(res.json()["folder"], "archive")

    def test_a_missing_session_is_404_not_a_crash(self):
        self.assertEqual(self.client.get("/api/manager/2099-01-01.md").status_code, 404)

    def test_a_traversing_filename_is_refused(self):
        # Two layers, and the test names both. The router never matches a path
        # with a separator in it, so the request that a client can actually
        # send does not reach the handler; the handler refuses one anyway,
        # because the hub is a directory this process can write to and that
        # guard must not depend on a routing accident.
        self.assertNotEqual(self.client.get("/api/manager/..%2Fconfig.local.json").status_code, 200)
        for bad in ("../config.local.json", "..\\config.local.json", "sub/2026-01-08.md"):
            with self.assertRaises(manager.HTTPException):
                manager._safe_name(bad)


CARRIED_FROM_TABLE = REPO_ROOT / "Tests" / "fixtures" / "carried-from" / "table.json"


class CarriedFromRule(unittest.TestCase):
    """docs/hub/manager.md, "Which session a record carries from": the shared
    table, one row per shape the rule distinguishes. Tests/Test-MeetingAgenda.ps1
    asserts the same rows against the CLI's reader."""

    def test_every_row_of_the_shared_table(self):
        rows = json.loads(CARRIED_FROM_TABLE.read_text(encoding="utf-8"))["rows"]
        self.assertGreaterEqual(len(rows), 6)
        for row in rows:
            with self.subTest(case=row["case"]):
                check = manager.carried_from_check(row["session"], row["heading"], row["current"] + row["archive"])
                self.assertEqual(check["verdict"], row["verdict"])
                self.assertEqual(check["expected"], row["expected"])
                if row["heading"] is not None:
                    self.assertEqual(check["named"], row["heading"].strip())

    def test_the_table_covers_every_verdict(self):
        rows = json.loads(CARRIED_FROM_TABLE.read_text(encoding="utf-8"))["rows"]
        self.assertEqual(
            {r["verdict"] for r in rows},
            {manager.CARRIED_OK, manager.CARRIED_STALE, manager.CARRIED_MISSING, manager.CARRIED_ABSENT},
        )

    def test_a_note_is_said_only_when_the_heading_is_wrong(self):
        ok = manager.carried_from_check("2026-06-26.md", "2026-06-12", ["2026-06-12.md", "2026-06-26.md"])
        self.assertEqual(manager.carried_from_note(ok), "")
        stale = manager.carried_from_check(
            "2026-06-26.md", "2026-06-12", ["2026-06-12.md", "2026-06-19.md", "2026-06-26.md"]
        )
        note = manager.carried_from_note(stale)
        self.assertIn("2026-06-12", note)
        self.assertIn("2026-06-19", note)
        self.assertIn("not rewritten", note)

    def test_the_heading_is_read_from_a_crlf_line(self):
        self.assertEqual(manager._carried_heading(["# 2026-06-26\r", "## Carried from 2026-06-12\r"]), "2026-06-12")
        self.assertIsNone(manager._carried_heading(["# 2026-06-26", "## Stage", "draft"]))


class CarriedFromOnTheDetail(ManagerRouteTestCase):
    """The agent's model says so; nothing rewrites the file."""

    def test_the_fixture_sessions_carry_from_the_right_one(self):
        for name in ("2026-01-08.md", "2026-01-22.md", "2026-02-05.md"):
            with self.subTest(session=name):
                data = self.client.get(f"/api/manager/{name}").json()
                self.assertEqual(data["carried_from_verdict"], "ok")
                self.assertEqual(data["carried_from_note"], "")
        data = self.client.get("/api/manager/2026-01-22.md").json()
        self.assertEqual(data["carried_from"], "2026-01-08")
        self.assertEqual(data["carried_from_expected"], "2026-01-08")

    def test_a_session_added_out_of_order_is_reported_and_left_alone(self):
        later = self.session("2026-01-22.md")
        before = later.read_bytes()
        # A session for an earlier date, added after the later one was created.
        archive = self.hub / "manager" / "archive"
        archive.mkdir(parents=True, exist_ok=True)
        (archive / "2026-01-15.md").write_text(
            "# 2026-01-15\n\n## Stage\nretro\n\n## Carried from 2026-01-08\n\n**Closed:** 2026-01-16\n",
            encoding="utf-8",
        )
        data = self.client.get("/api/manager/2026-01-22.md").json()
        self.assertEqual(data["carried_from"], "2026-01-08")
        self.assertEqual(data["carried_from_expected"], "2026-01-15")
        self.assertEqual(data["carried_from_verdict"], "stale")
        self.assertIn("2026-01-15", data["carried_from_note"])
        self.assertEqual(later.read_bytes(), before, "a reader rewrote the heading")

    def test_a_save_reports_the_check_and_keeps_the_heading(self):
        path = self.session("2026-01-22.md")
        text = path.read_text(encoding="utf-8").replace("## Carried from 2026-01-08", "## Carried from 2025-12-01")
        path.write_text(text, encoding="utf-8")
        data = self.client.put("/api/manager/2026-01-22.md", json={"since": "notes"}).json()
        self.assertEqual(data["carried_from_verdict"], "missing")
        self.assertIn("## Carried from 2025-12-01", path.read_text(encoding="utf-8"))


@unittest.skipIf(shutil.which("pwsh") is None, "pwsh is not on this machine")
class Create(ManagerRouteTestCase):
    """``POST /manager`` runs the real ``NewMeeting`` through the bridge, in a
    SCRATCH package: the bridge imports the manifest beside itself, the verb is
    in the command table only while the checkout's own config turns the module
    on, and a test that wrote this checkout's ``config.local.json`` would be
    editing the engineer's machine. So the package is copied, its
    ``config.local.json`` turns the module on and names the test's hub, and the
    bridge is pointed at the copy
   ."""

    def setUp(self):
        super().setUp()
        self.pkg = Path(self.tmp.name) / "pkg"
        self.pkg.mkdir()
        for name in ("utilities.psm1", "config.default.json", "consts.json"):
            shutil.copy(REPO_ROOT / name, self.pkg / name)
        for folder in ("Scripts", "Config", "Prompt20Toolkit", "templates"):
            shutil.copytree(REPO_ROOT / folder, self.pkg / folder)
        (self.pkg / "agent" / "ado").mkdir(parents=True)
        shutil.copy(REPO_ROOT / "agent" / "ado" / "bridge.ps1", self.pkg / "agent" / "ado" / "bridge.ps1")
        _write(
            self.pkg / "config.local.json",
            {
                "features": {"communication": True},
                "promptsRoot": str(self.hub),
            },
        )
        self._saved = (bridge._map_cache, bridge._map_key)
        self._bridge_patches = [
            mock.patch.object(bridge, "REPO_ROOT", self.pkg),
            mock.patch.object(bridge, "UTILITIES", self.pkg / "utilities.psm1"),
            mock.patch.object(bridge, "BRIDGE_PS1", self.pkg / "agent" / "ado" / "bridge.ps1"),
            mock.patch.object(bridge, "MODULE_COMMANDS_DIR", self.pkg / "Config"),
            mock.patch.object(bridge, "_map_cache", {}),
            mock.patch.object(bridge, "_map_key", None),
        ]
        for p in self._bridge_patches:
            p.start()

    def tearDown(self):
        for p in reversed(self._bridge_patches):
            p.stop()
        bridge._map_cache, bridge._map_key = self._saved
        super().tearDown()

    def test_creates_a_session_in_the_documented_shape(self):
        res = self.client.post("/api/manager", json={"date": "2026-03-05"})
        self.assertEqual(res.status_code, 200, res.text)
        text = self.session("2026-03-05.md").read_text(encoding="utf-8")
        for heading in (
            "## Stage",
            "## Carried from",
            "## Since Last Session",
            "## Unresolved / Forward",
            "## Agenda",
            "## Prep",
            "## Retro",
            "## Sent",
        ):
            self.assertIn(heading, text)
        body = res.json()
        self.assertEqual(
            (body["filename"], body["series"], body["date"], body["session_stage"]),
            ("2026-03-05.md", "", "2026-03-05", "draft"),
        )
        self.assertEqual(body["content"], text)
        self.assertEqual(body["since"], "", "the template's hint read as content")
        self.assertTrue(Path(body["path"]).is_absolute())

    def test_the_file_is_the_verbs_not_a_second_scaffold(self):
        """Byte parity with the CLI, the way growth has it: the file the route
        made is the file `NewMeeting` makes -- the template's own words."""
        self.client.post("/api/manager", json={"date": "2026-03-05"})
        text = self.session("2026-03-05.md").read_bytes()
        template = (REPO_ROOT / "templates" / "ManagerSession.template.md").read_text(encoding="utf-8")
        expected = template.replace("{{DATE}}", "2026-03-05").replace("{{PRIOR_DATE}}", "2026-02-05")
        self.assertEqual(text.decode("utf-8"), expected)
        self.assertFalse(text.startswith(b"\xef\xbb\xbf"), "a BOM")
        self.assertNotIn(b"\r\n", text, "a created file is LF")

    def test_notes_are_an_edit_not_part_of_the_create(self):
        r = self.client.post("/api/manager", json={"date": "2026-03-05", "since": "shipped the thing"})
        self.assertEqual(r.status_code, 422, "a create takes a date and a series; notes go through PUT")
        self.assertFalse(self.session("2026-03-05.md").exists())
        self.assertEqual(self.client.post("/api/manager", json={"date": "2026-03-05"}).status_code, 200)
        r = self.client.put("/api/manager/2026-03-05.md", json={"since": "shipped the thing"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("shipped the thing", self.session("2026-03-05.md").read_text(encoding="utf-8"))

    def test_the_verb_not_in_the_table_is_a_503_that_says_so(self):
        with mock.patch.object(bridge, "command_map", lambda force=False: {"Menu": "Get-P20Menu"}):
            r = self.client.post("/api/manager", json={"date": "2026-03-05"})
        self.assertEqual(r.status_code, 503)
        self.assertIn("NewMeeting", r.json()["detail"])
        self.assertFalse(self.session("2026-03-05.md").exists())

    def test_the_verb_is_run_with_the_hub_this_process_resolved(self):
        seen = {}
        real_run = bridge._run

        def spy(function, params, timeout, extra_env=None):
            seen.update(function=function, params=params, env=extra_env or {})
            return real_run(function, params, timeout, extra_env)

        with mock.patch.object(bridge, "_run", spy):
            self.client.post("/api/manager", json={"date": "2026-03-05", "series": "client-weekly"})
        self.assertEqual(seen["function"], "New-P20Meeting")
        self.assertEqual(seen["params"], ["-Date", "2026-03-05", "-Type", "client-weekly"])
        self.assertEqual(seen["env"].get("PROMPTS_ROOT"), str(self.hub))

    def test_carried_from_names_the_prior_session(self):
        self.client.post("/api/manager", json={"date": "2026-03-05"})
        text = self.session("2026-03-05.md").read_text(encoding="utf-8")
        self.assertIn("## Carried from 2026-02-05", text)

    def test_a_second_series_has_its_own_records_and_its_own_carry_forward(self):
        """docs/modules/communication.md. A series' record
        carries its name in front of the date; a first record carries from none,
        not from the 1:1; the second carries from the first in that series; and
        the 1:1 on the same day still carries from the last 1:1."""
        r = self.client.post("/api/manager", json={"date": "2026-03-05", "series": "client-weekly"})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(
            (body["filename"], body["series"], body["date"], body["title"]),
            ("client-weekly-2026-03-05.md", "client-weekly", "2026-03-05", "client-weekly -- 2026-03-05"),
        )
        text = (self.hub / "manager" / "current" / "client-weekly-2026-03-05.md").read_text()
        self.assertIn("# client-weekly 2026-03-05", text)
        self.assertIn("## Carried from (none)", text)

        r2 = self.client.post("/api/manager", json={"date": "2026-03-12", "series": "client-weekly"}).json()
        text2 = (self.hub / "manager" / "current" / r2["filename"]).read_text()
        self.assertIn("## Carried from 2026-03-05", text2)

        one = self.client.post("/api/manager", json={"date": "2026-03-12"}).json()
        self.assertEqual((one["filename"], one["series"], one["title"]), ("2026-03-12.md", "", "1:1 -- 2026-03-12"))
        text3 = (self.hub / "manager" / "current" / "2026-03-12.md").read_text()
        self.assertIn("## Carried from 2026-02-05", text3)  # the last 1:1 in the fixture, not the weekly

        items = {i["filename"]: i for i in self.client.get("/api/manager").json()["items"]}
        self.assertEqual(items["client-weekly-2026-03-12.md"]["series"], "client-weekly")
        self.assertEqual(items["2026-03-12.md"]["series"], "")
        detail = self.client.get("/api/manager/client-weekly-2026-03-12.md").json()
        self.assertEqual((detail["series"], detail["date"]), ("client-weekly", "2026-03-12"))

    def test_a_series_name_that_is_not_a_slug_is_refused(self):
        r = self.client.post("/api/manager", json={"date": "2026-03-05", "series": "Client Weekly"})
        self.assertEqual(r.status_code, 400)
        self.assertFalse(list((self.hub / "manager" / "current").glob("*Client*")))

    def test_a_bad_date_is_rejected_before_anything_is_written(self):
        res = self.client.post("/api/manager", json={"date": "the fifth"})
        self.assertEqual(res.status_code, 400)
        self.assertFalse((self.hub / "manager" / "current" / "the fifth.md").exists())

    def test_an_existing_session_is_never_overwritten(self):
        res = self.client.post("/api/manager", json={"date": "2026-01-08"})
        self.assertEqual(res.status_code, 409)

    def test_a_session_already_closed_into_archive_is_not_recreated(self):
        """The date is the file's identity, so "exists" means EITHER folder.

        Checking only current/ scaffolded a blank session beside a real, closed
        one in archive/: the 1:1s page listed an open meeting that had already
        been held, and nothing but a hand delete resolved the duplicate.
        """
        archive = self.hub / "manager" / "archive"
        archive.mkdir(parents=True, exist_ok=True)
        closed = archive / "2026-03-05.md"
        closed.write_text("# 1:1 -- 2026-03-05\n\n**Closed:** 2026-03-06\n", encoding="utf-8")

        res = self.client.post("/api/manager", json={"date": "2026-03-05"})
        self.assertEqual(res.status_code, 409, res.text)
        self.assertIn("archive", res.json()["detail"])
        self.assertFalse(self.session("2026-03-05.md").exists(), "a draft was scaffolded beside the closed session")
        self.assertIn("**Closed:**", closed.read_text(encoding="utf-8"))


class Update(ManagerRouteTestCase):
    def test_saves_the_form_fields(self):
        res = self.client.put(
            "/api/manager/2026-01-08.md",
            json={
                "since": "rewrote the importer",
                "forward": "still unresolved",
                "retro": "",
            },
        )
        self.assertEqual(res.status_code, 200)
        text = self.session("2026-01-08.md").read_text(encoding="utf-8")
        self.assertIn("rewrote the importer", text)
        self.assertIn("still unresolved", text)

    def test_a_save_never_deletes_what_the_agent_wrote(self):
        # The notes form does not own the Agenda, the Prep or the carry-forward.
        self.client.put("/api/manager/2026-01-22.md", json={"since": "new note"})
        text = self.session("2026-01-22.md").read_text(encoding="utf-8")
        self.assertIn("two approaches prototyped", text)  # Agenda
        self.assertIn("## Carried from 2026-01-08", text)  # carry-forward heading
        self.assertIn("agreed to raise it again", text)  # carry-forward body

    def test_a_save_does_not_move_the_stage(self):
        self.client.put("/api/manager/2026-02-05.md", json={"retro": "notes"})
        self.assertEqual(self.client.get("/api/manager/2026-02-05.md").json()["session_stage"], "retro")

    def test_append_sent_records_the_send_in_the_file(self):
        self.client.put(
            "/api/manager/2026-02-05.md",
            json={
                "retro": "notes",
                "append_sent": "Sent to manager: 2026-02-05",
            },
        )
        text = self.session("2026-02-05.md").read_text(encoding="utf-8")
        self.assertIn("## Sent\nSent to manager: 2026-02-05", text)

    def test_a_later_save_keeps_the_sent_line(self):
        self.client.put(
            "/api/manager/2026-02-05.md",
            json={
                "retro": "notes",
                "append_sent": "Sent to manager: 2026-02-05",
            },
        )
        self.client.put("/api/manager/2026-02-05.md", json={"retro": "notes again"})
        self.assertIn(
            "Sent to manager: 2026-02-05",
            self.session("2026-02-05.md").read_text(encoding="utf-8"),
        )

    def test_a_second_send_appends_rather_than_replaces(self):
        for day in ("2026-02-05", "2026-02-06"):
            self.client.put(
                "/api/manager/2026-02-05.md",
                json={
                    "retro": "notes",
                    "append_sent": f"Sent to manager: {day}",
                },
            )
        text = self.session("2026-02-05.md").read_text(encoding="utf-8")
        self.assertIn("Sent to manager: 2026-02-05", text)
        self.assertIn("Sent to manager: 2026-02-06", text)

    @unittest.skipUnless(
        HAVE_HOST, "the series half creates through the bridge and needs pwsh (or powershell.exe) to run NewMeeting"
    )
    def test_a_save_keeps_the_heading_and_the_series(self):
        # The name rule's groups are (series, date). The save read group 1 as
        # the date, so a 1:1's heading came back "# None" and a series record's
        # lost its date and its series.
        self.client.put("/api/manager/2026-01-08.md", json={"since": "x"})
        text = self.session("2026-01-08.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("# 2026-01-08\n"), text.splitlines()[0])

        # The real create, through the bridge. Asserted, so a table without the
        # verb fails here by name rather than as a 404 on the PUT below.
        created = self.client.post("/api/manager", json={"date": "2026-03-12", "series": "client-weekly"})
        self.assertEqual(created.status_code, 200, created.text)
        res = self.client.put("/api/manager/client-weekly-2026-03-12.md", json={"since": "y"})
        self.assertEqual(res.status_code, 200, res.text)
        body = res.json()
        self.assertEqual(body["series"], "client-weekly")
        self.assertEqual(body["date"], "2026-03-12")
        self.assertEqual(body["title"], "client-weekly -- 2026-03-12")
        self.assertEqual(body["folder"], "current")
        text = self.session("client-weekly-2026-03-12.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("# client-weekly 2026-03-12\n"), text.splitlines()[0])

    def test_a_closed_session_cannot_be_saved(self):
        # A closed session is the record. The web's send hides itself on one,
        # because a send it cannot record is the case this pins.
        archive = self.hub / "manager" / "archive"
        archive.mkdir(parents=True, exist_ok=True)
        (archive / "2025-12-11.md").write_text("# 2025-12-11\n\n## Stage\nretro\n", encoding="utf-8")
        res = self.client.put("/api/manager/2025-12-11.md", json={"append_sent": "Sent to manager: 2026-09-22"})
        self.assertEqual(res.status_code, 404)

    def test_saving_a_session_that_is_not_there_is_404(self):
        self.assertEqual(self.client.put("/api/manager/2099-01-01.md", json={}).status_code, 404)


class FlagOff(ManagerRouteTestCase):
    features: dict = {}

    def test_every_route_is_absent(self):
        self.assertEqual(self.client.get("/api/manager").status_code, 404)
        self.assertEqual(self.client.get("/api/manager/2026-01-08.md").status_code, 404)
        self.assertEqual(self.client.post("/api/manager", json={"date": "2026-03-05"}).status_code, 404)
        self.assertEqual(self.client.put("/api/manager/2026-01-08.md", json={}).status_code, 404)
        self.assertEqual(self.client.post("/api/comms/send", json={}).status_code, 404)
        self.assertEqual(self.client.post("/api/rewrite", json={"text": "hi"}).status_code, 404)

    def test_off_writes_nothing(self):
        self.client.post("/api/manager", json={"date": "2026-03-05"})
        self.assertFalse(self.session("2026-03-05.md").exists())

    def test_env_carries_no_communication_block(self):
        self.assertNotIn("communication", self.client.get("/api/env").json())


class EnvReportsGateTwo(ManagerRouteTestCase):
    def _block(self) -> dict:
        return self.client.get("/api/env").json()["communication"]

    def test_the_manager_recipient_is_unconfigured_when_the_variable_is_unset(self):
        entry = next(r for r in self._block()["recipients"] if r["key"] == "manager")
        self.assertFalse(entry["configured"])
        self.assertEqual(entry["webhookEnv"], "TEAMS_WEBHOOK_MANAGER")

    def test_the_manager_recipient_is_configured_when_the_variable_is_set(self):
        with mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_MANAGER": DUMMY_WEBHOOK}):
            entry = next(r for r in self._block()["recipients"] if r["key"] == "manager")
        self.assertTrue(entry["configured"])

    def test_the_block_says_where_the_recipient_came_from(self):
        # C7: two places hold recipients. The UI renders that honestly rather
        # than pretending there is one list.
        entry = next(r for r in self._block()["recipients"] if r["key"] == "manager")
        self.assertEqual(entry["scope"], "managerWorkflow")

    def test_post_retro_summary_is_reported(self):
        self.assertTrue(self._block()["postRetroSummary"])


class CommsSendRoute(ManagerRouteTestCase):
    """The route is a wrapper. What it must not do is reach the network when a
    gate says no -- so the engine's transport is asserted untouched."""

    def test_an_unset_webhook_is_skipped_and_never_posts(self):
        with mock.patch.object(manager.comms, "_post_to_webhook") as post:
            res = self.client.post(
                "/api/comms/send",
                json={
                    "caller": "ManagerSessionPage",
                    "recipient": "manager",
                    "subject": "1:1 -- 2026-02-05",
                    "sections": [{"heading": "Agenda", "body": "x"}],
                    "tone": "personal",
                },
            )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "skipped")
        self.assertIn("TEAMS_WEBHOOK_MANAGER", res.json()["detail"])
        post.assert_not_called()

    def test_a_dry_run_formats_without_posting(self):
        with (
            mock.patch.dict(os.environ, {"TEAMS_WEBHOOK_MANAGER": DUMMY_WEBHOOK}),
            mock.patch.object(manager.comms, "_post_to_webhook") as post,
        ):
            res = self.client.post(
                "/api/comms/send",
                json={
                    "caller": "ManagerSessionPage",
                    "recipient": "manager",
                    "subject": "1:1 -- 2026-02-05",
                    "sections": [{"heading": "Agenda", "body": "the agenda"}],
                    "tone": "personal",
                    "dryRun": True,
                },
            )
        body = res.json()
        self.assertEqual(body["status"], "dry-run")
        self.assertIn("the agenda", body["payload"])
        post.assert_not_called()


class RewriteRoute(ManagerRouteTestCase):
    def test_no_model_key_declines_with_a_reason(self):
        # clear=True takes P20_USAGE_LOG_DIR with it, and the decline is
        # logged -- which put this assertion in the engineer's own usage log.
        # The variable is not what this case is about, so it is kept.
        kept = {"P20_USAGE_LOG_DIR": os.environ.get("P20_USAGE_LOG_DIR", "")}
        with mock.patch.dict(os.environ, kept, clear=True):
            res = self.client.post("/api/rewrite", json={"text": "some raw notes"})
        # 412, the profile's sentence (core/model.py): a precondition on
        # this machine, not the model failing.
        self.assertEqual(res.status_code, 412)
        self.assertIn("ANTHROPIC_API_KEY", res.json()["detail"])

    def test_empty_text_is_rejected_by_the_model(self):
        self.assertEqual(self.client.post("/api/rewrite", json={"text": ""}).status_code, 422)


if __name__ == "__main__":
    unittest.main(verbosity=2)
