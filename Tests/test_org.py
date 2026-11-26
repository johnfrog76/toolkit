"""The org chart's agent half -- GET /api/ritual/org and the reader behind it.

Two readers implement docs/hub/org.md, this one (agent/solitaire/org.py) and the
CLI's (Scripts/Read-OrgChart.ps1), and ONE table holds them to each other:
Tests/fixtures/org/table.json, which ``tkTestToolkit -OrgChart`` asserts from the
other side. A case builds a scratch hub (the table's own header says how); here
each case is read twice -- by the reader on the hub it resolves, and through the
route -- and the chart compares as JSON to the response the table states, key
order aside. A failure's ``kind`` is the contract; its sentence is the CLI's.

Beyond the table: the route's gate (off is 404, not 403), what a failed read
answers, the fields only the route adds for the web (``promptTitle`` and
``promptRef`` on each position, through the Studio's one prompt record, and
``modelName`` on each seat, through the model map), that nothing in the hub is
written, and the schema (Config/org.schema.json) validating the sample hub's file
and the presets with ``jsonschema``.

No network: the route reads one file and calls nothing.

Run:  python3 -m pytest Tests/test_org.py
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "org"
try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.core import consts as C
    from agent.solitaire import api as solitaire_api
    from agent.solitaire import org
    from agent.studio import prompts
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

TABLE = json.loads((FIXTURES / "table.json").read_text(encoding="utf-8"))
CASES = TABLE["cases"]
ROUTE = "/api/ritual/org"


def same_json(a, b) -> bool:
    """Equal as JSON, key order aside (and True is not 1)."""
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def build_hub(hub: Path, case: dict) -> None:
    """The scratch hub a table row describes (the table's header says how)."""
    hub.mkdir(parents=True, exist_ok=True)
    if "hubJson" in case:
        (hub / "hub.json").write_text(json.dumps(case["hubJson"]), encoding="utf-8")
    if "org" in case:
        (hub / "org.json").write_text(json.dumps(case["org"]), encoding="utf-8")
    if "orgText" in case:
        (hub / "org.json").write_text(case["orgText"], encoding="utf-8")
    if "orgFile" in case:
        (hub / "org.json").write_bytes((FIXTURES / case["orgFile"]).read_bytes().replace(b"\r\n", b"\n"))
    folder = hub / case.get("promptsFolder", "agentic")
    folder.mkdir(parents=True, exist_ok=True)
    for name in case.get("prompts", TABLE["prompts"]):
        (folder / name).write_text("", encoding="utf-8")
    for name in case.get("promptFolders", []):
        (folder / name).mkdir(parents=True, exist_ok=True)
    if "hubOrgPrompts" in case:
        roles = folder / C.org_roles_folder()
        roles.mkdir(parents=True, exist_ok=True)
        for name in case["hubOrgPrompts"]:
            (roles / name).write_text("", encoding="utf-8")


def build_package(pkg: Path, case: dict) -> Path:
    """The scratch package a table row reads against: exactly its ``shippedPrompts``
    in agentic/<roles>/ and its ``shippedFlatPrompts`` in agentic/, so the real
    shipped roles never decide a row. Returns its agentic folder."""
    agentic = pkg / "agentic"
    roles = agentic / C.org_roles_folder()
    roles.mkdir(parents=True, exist_ok=True)
    for name in case.get("shippedPrompts", []):
        (roles / name).write_text("", encoding="utf-8")
    for name in case.get("shippedFlatPrompts", []):
        (agentic / name).write_text("", encoding="utf-8")
    return agentic


class OrgBase(unittest.TestCase):
    features = {"solitaireAgile": True}
    how_i_work = "agents"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.hub = self.base / "hub"
        default = self.base / "config.default.json"
        local = self.base / "config.local.json"
        default.write_text(
            json.dumps(
                {
                    "activeSpace": "widgets",
                    "features": self.features,
                    "promptsRoot": str(self.hub),
                    "spaces": [
                        {
                            "slug": "widgets",
                            "status": "active",
                            "promptsFolder": "widgets",
                            "org": "https://github.com/acme/widgets",
                            "howIWork": self.how_i_work,
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        local.write_text("{}", encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", default),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", local),
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

    def put(self, doc=None, prompts=None, text=None):
        self.hub.mkdir(parents=True, exist_ok=True)
        (self.hub / "agentic").mkdir(exist_ok=True)
        if text is not None:
            (self.hub / "org.json").write_text(text, encoding="utf-8")
        elif doc is not None:
            (self.hub / "org.json").write_text(json.dumps(doc), encoding="utf-8")
        for name, body in (prompts or {}).items():
            (self.hub / "agentic" / name).write_text(body, encoding="utf-8")

    def doc(self, **position):
        return {
            "trees": [
                {
                    "id": "t",
                    "positions": [
                        {"id": "owner", "seats": [{"id": "o", "person": "Sam"}]},
                        {"id": "lead", "reportsTo": "owner", **position},
                    ],
                }
            ]
        }

    def tree_of_files(self) -> dict:
        return {p.relative_to(self.hub).as_posix(): p.read_bytes() for p in self.hub.rglob("*") if p.is_file()}


class TheSharedTable(OrgBase):
    """Every case of Tests/fixtures/org/table.json, by the reader and by the route."""

    def test_the_table_has_the_cases_this_suite_knows_how_to_build(self):
        self.assertGreaterEqual(len(CASES), 33)
        for case in CASES:
            optional = {"promptFolders", "hubOrgPrompts", "shippedPrompts", "shippedFlatPrompts"}
            self.assertEqual(
                set(case) - {"name", "why", "org", "orgText", "orgFile", "hubJson", "tree", "prompts", "promptsFolder"},
                {"expect"} | (optional & set(case)),
                case["name"],
            )

    def test_every_case_through_the_reader(self):
        for case in CASES:
            with self.subTest(case=case["name"]):
                hub = self.base / "reader" / case["name"]
                build_hub(hub, case)
                agentic = build_package(self.base / "reader-pkg" / case["name"], case)
                with (
                    mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(hub)}),
                    mock.patch.object(prompts, "AGENTIC_DIR", agentic),
                ):
                    got = org.find_org_chart(case.get("tree", ""))
                want = case["expect"]
                self.assertEqual(got.status, want["status"])
                if want["status"] == "ok":
                    chart = json.loads((FIXTURES / want["chart"]).read_text(encoding="utf-8"))
                    self.assertTrue(same_json(got.chart, chart), json.dumps(got.chart, indent=1))
                    self.assertEqual(got.active_tree, want["activeTree"])
                    self.assertEqual(got.seat_count, want["seatCount"])
                    self.assertEqual(got.warnings, want["warnings"])
                else:
                    self.assertEqual(got.kind, want["kind"])
                    if "message" in want:
                        self.assertEqual(got.message, want["message"])
                    else:
                        self.assertTrue(got.message.startswith(want["messageStartsWith"]), got.message)

    def test_every_case_through_the_route(self):
        for case in CASES:
            with self.subTest(case=case["name"]):
                hub = self.base / "route" / case["name"]
                build_hub(hub, case)
                agentic = build_package(self.base / "route-pkg" / case["name"], case)
                query = f"?tree={case['tree']}" if "tree" in case else ""
                with (
                    mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(hub)}),
                    mock.patch.object(prompts, "AGENTIC_DIR", agentic),
                ):
                    res = self.client.get(ROUTE + query)
                want = case["expect"]
                if want["status"] == "ok":
                    self.assertEqual(res.status_code, 200, res.text)
                    body = res.json()
                    # Which copy the lookup chose: the hub's reads yours/<name>, the toolkit's <name>.
                    refs = {p["id"]: p["promptRef"] for p in body["tree"]["positions"]}
                    for pid, ref in want.get("promptRefs", {}).items():
                        self.assertEqual(refs.get(pid), ref, pid)
                    # What each seat's model is called, where the table states it ("position.seat").
                    names = {
                        f"{p['id']}.{s['id']}": s.get("modelName", "absent")
                        for p in body["tree"]["positions"]
                        for s in p["seats"]
                    }
                    for where, name in want.get("modelNames", {}).items():
                        self.assertEqual(names.get(where, "no such seat"), name, where)
                    # The file's trees, listed: the tree shown among them, exactly one in use.
                    trees = body.pop("trees")
                    self.assertIn(body["tree"]["id"], [t["id"] for t in trees])
                    self.assertEqual([t["id"] for t in trees if t["active"]], [want["activeTree"]])
                    for position in body["tree"]["positions"]:
                        # the fields only the route adds; the table's response is the shared part
                        added = {"promptTitle", "promptRef", "defaultModelName"}
                        self.assertEqual(set(position) & added, added, position)
                        self.assertEqual(
                            position["defaultModelName"], org.model_name(position["defaultModel"]), position
                        )
                        del position["promptTitle"], position["promptRef"], position["defaultModelName"]
                        for seat in position["seats"]:
                            self.assertIn("modelName", seat, seat)
                            del seat["modelName"]
                    chart = json.loads((FIXTURES / want["chart"]).read_text(encoding="utf-8"))
                    self.assertTrue(same_json(body, chart), json.dumps(body, indent=1))
                else:
                    detail = res.json()["detail"]
                    self.assertEqual(res.status_code, {"missing": 404, "unknown-tree": 422}.get(want["kind"], 409))
                    self.assertEqual(detail["kind"], want["kind"])
                    if "message" in want:
                        self.assertEqual(detail["message"], want["message"])
                    else:
                        self.assertTrue(detail["message"].startswith(want["messageStartsWith"]), detail["message"])


class TheStateTable(unittest.TestCase):
    """An org's state, derived from Tests/fixtures/org/state.json -- the table
    tkTestToolkit -OrgChart asserts for the CLI's reader too."""

    def test_every_case(self):
        table = json.loads((FIXTURES / "state.json").read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["cases"]), 5)
        for case in table["cases"]:
            with self.subTest(case=case["name"]):
                got = org.read_org_chart(json.dumps(case["org"]), lambda _n: True)
                self.assertEqual(got.status, "ok", got.message)
                self.assertEqual({t["id"]: t["state"] for t in got.trees}, case["expect"]["states"])
                # active stays the one pointer: true on the active tree alone.
                self.assertEqual(
                    [t["id"] for t in got.trees if t["active"]],
                    [i for i, st in case["expect"]["states"].items() if st == "active"],
                )

    def test_activated_at_is_a_key_the_tool_reads(self):
        doc = {"trees": [{"id": "t", "activatedAt": "2026-11-26", "positions": [{"id": "r"}]}]}
        got = org.read_org_chart(json.dumps(doc), lambda _n: True)
        self.assertEqual(got.warnings, [])
        self.assertEqual(got.trees[0]["activatedAt"], "2026-11-26")


class TheReaderAlone(unittest.TestCase):
    """The pure layer: text and a prompt test in, a result out -- and it never raises."""

    def read(self, text, names=(), **kw):
        return org.read_org_chart(text, lambda n: n in names, **kw)

    def test_a_byte_order_mark_is_read_past(self):
        doc = json.dumps({"trees": [{"id": "t", "positions": [{"id": "r"}]}]})
        self.assertEqual(self.read("﻿" + doc).status, "ok")

    def test_nan_is_not_json(self):
        got = self.read('{"trees": NaN}')
        self.assertEqual((got.status, got.kind), ("invalid", "unreadable"))

    def test_an_id_given_as_a_number_is_its_text(self):
        doc = {"trees": [{"id": 7, "positions": [{"id": 1.0, "seats": [{"id": 2, "model": 3}]}]}]}
        got = self.read(json.dumps(doc))
        self.assertEqual(got.status, "ok")
        self.assertEqual(got.chart["tree"]["id"], "7")
        self.assertEqual(got.chart["tree"]["positions"][0]["id"], "1")
        self.assertEqual(got.chart["tree"]["positions"][0]["seats"][0]["model"], "3")

    def test_a_boolean_is_not_an_id(self):
        got = self.read(json.dumps({"trees": [{"id": True, "positions": []}]}))
        self.assertEqual((got.kind, got.message), ("missing-id", "Tree 1 has no id."))

    def test_key_names_are_matched_exactly(self):
        got = self.read(json.dumps({"Trees": [], "trees": [{"id": "t", "Name": "x", "positions": [{"id": "r"}]}]}))
        self.assertEqual(got.status, "ok")
        self.assertEqual(got.chart["tree"]["title"], "t")
        self.assertEqual(
            got.warnings,
            [
                "org.json: 'Trees' is not a key this tool reads -- ignored.",
                "org.json: 'Name' is not a key this tool reads in tree 't' -- ignored.",
            ],
        )

    def test_a_seat_that_names_both_carries_both_and_is_staffed(self):
        doc = {"trees": [{"id": "t", "positions": [{"id": "r", "seats": [{"id": "s", "model": "m", "person": "p"}]}]}]}
        seat = self.read(json.dumps(doc)).chart["tree"]["positions"][0]["seats"][0]
        self.assertEqual((seat["model"], seat["person"], seat["state"]), ("m", "p", "staffed"))

    def test_a_deep_tree_does_not_recurse(self):
        positions = [{"id": "p0"}] + [{"id": f"p{i}", "reportsTo": f"p{i - 1}"} for i in range(1, 3000)]
        got = self.read(json.dumps({"trees": [{"id": "t", "positions": positions}]}))
        self.assertEqual(got.status, "ok")
        self.assertEqual(got.chart["tree"]["positions"][-1]["level"], 2999)

    def test_siblings_are_drawn_in_file_order_under_their_parent(self):
        positions = [
            {"id": "root"},
            {"id": "a", "reportsTo": "root"},
            {"id": "b", "reportsTo": "root"},
            {"id": "a1", "reportsTo": "a"},
        ]
        got = self.read(json.dumps({"trees": [{"id": "t", "positions": positions}]}))
        walked = [(p["id"], p["level"]) for p in got.chart["tree"]["positions"]]
        self.assertEqual(walked, [("root", 0), ("a", 1), ("a1", 2), ("b", 1)])


class TheRoute(OrgBase):
    def positions(self, res):
        self.assertEqual(res.status_code, 200, res.text)
        return {p["id"]: p for p in res.json()["tree"]["positions"]}

    def test_the_route_is_the_contracts(self):
        self.assertEqual(C.rituals_org_route(), ROUTE)

    def test_the_title_is_the_front_matters_and_the_ref_is_the_reading_rooms(self):
        self.put(
            self.doc(prompt="lead.prompt.md"),
            {"lead.prompt.md": "---\ntitle: The team lead\n---\n# Opus the team lead\n\nText.\n"},
        )
        lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), ("The team lead", "yours/lead"))
        self.assertEqual(lead["prompt"], "lead.prompt.md")

    def test_with_no_front_matter_the_heading_is_the_title(self):
        self.put(self.doc(prompt="lead.prompt.md"), {"lead.prompt.md": "# Opus the team lead\n\nText.\n"})
        self.assertEqual(self.positions(self.client.get(ROUTE))["lead"]["promptTitle"], "Opus the team lead")

    def test_with_neither_the_file_name_is_the_title(self):
        self.put(self.doc(prompt="lead.prompt.md"), {"lead.prompt.md": "Just text, no heading.\n"})
        lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), ("lead", "yours/lead"))

    def test_it_is_the_studios_title_for_the_same_file(self):
        """Not a second parser: the list's row for the same prompt says the same title."""
        body = "---\ntitle: The PM\ndescription: Checks the table.\n---\n# Opus the PM\n"
        self.put(self.doc(prompt="pm.prompt.md"), {"pm.prompt.md": body})
        lead = self.positions(self.client.get(ROUTE))["lead"]
        row = next(r for r in prompts.yours_rows(set()) if r.name == "pm")
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), (row.title, row.ref))

    def test_a_position_with_no_prompt_carries_nulls(self):
        self.put(self.doc())
        lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["prompt"], lead["promptTitle"], lead["promptRef"]), (None, None, None))

    def test_a_file_the_room_does_not_list_has_a_title_and_no_ref(self):
        self.put(self.doc(prompt="notes.md"), {"notes.md": "# Notes\n"})
        lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), ("Notes", None))

    def test_the_extension_folders_copy_is_the_one_the_room_opens(self):
        ext = self.base / "ext"
        ext.mkdir()
        (ext / "lead.prompt.md").write_text("# Tuned lead\n", encoding="utf-8")
        self.put(self.doc(prompt="lead.prompt.md"), {"lead.prompt.md": "# Hub lead\n"})
        with mock.patch.object(prompts, "agentic_extension_path", return_value=ext.resolve()):
            lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), ("Tuned lead", "yours/lead"))

    def test_the_folder_comes_from_the_hubs_manifest(self):
        self.put(self.doc(prompt="lead.prompt.md"))
        (self.hub / "hub.json").write_text(json.dumps({"folders": {"agentic": "roles"}}), encoding="utf-8")
        (self.hub / "roles").mkdir()
        (self.hub / "roles" / "lead.prompt.md").write_text("# From roles\n", encoding="utf-8")
        lead = self.positions(self.client.get(ROUTE))["lead"]
        self.assertEqual((lead["promptTitle"], lead["promptRef"]), ("From roles", "yours/lead"))

    def test_the_route_lists_every_tree_of_the_file_in_its_order(self):
        doc = json.loads((FIXTURES / "docs" / "valid.json").read_text(encoding="utf-8"))
        self.put(doc, {n: "" for n in TABLE["prompts"]})
        for query in ("", "?tree=branch"):
            with self.subTest(query=query):
                body = self.client.get(ROUTE + query).json()
                self.assertEqual(
                    body["trees"],
                    [
                        {
                            "id": "main",
                            "title": "Laptop and mini",
                            "size": None,
                            "preset": None,
                            "active": True,
                            "state": "active",
                            "activatedAt": None,
                        },
                        {
                            "id": "branch",
                            "title": "One machine",
                            "size": None,
                            "preset": None,
                            "active": False,
                            "state": "draft",
                            "activatedAt": None,
                        },
                    ],
                )

    def test_a_tree_from_a_preset_lists_its_size_and_preset(self):
        doc = json.loads((FIXTURES / "docs" / "shape.json").read_text(encoding="utf-8"))
        self.put(doc, {n: "" for n in TABLE["prompts"]})
        trees = self.client.get(ROUTE).json()["trees"]
        self.assertEqual(
            trees,
            [
                {
                    "id": "branch-office",
                    "title": "The Branch Office",
                    "size": "M",
                    "preset": "branch-office",
                    "active": True,
                    "state": "active",
                    "activatedAt": None,
                }
            ],
        )

    def test_tree_asks_for_another_tree_and_active_tree_still_says_which_is_in_use(self):
        doc = {
            "activeTree": "a",
            "trees": [
                {"id": "a", "positions": [{"id": "x"}]},
                {"id": "b", "name": "Branch", "positions": [{"id": "y"}]},
            ],
        }
        self.put(doc)
        body = self.client.get(ROUTE + "?tree=b").json()
        self.assertEqual((body["activeTree"], body["tree"]["id"], body["tree"]["title"]), ("a", "b", "Branch"))
        self.assertEqual(self.client.get(ROUTE).json()["tree"]["id"], "a")
        # the CLI trims -Tree, so the agent does
        self.assertEqual(self.client.get(ROUTE + "?tree=%20b%20").json()["tree"]["id"], "b")

    def test_an_unknown_tree_is_422_naming_it_and_the_trees(self):
        self.put(self.doc())
        res = self.client.get(ROUTE + "?tree=nope")
        self.assertEqual(res.status_code, 422)
        self.assertEqual(res.json()["detail"]["kind"], "unknown-tree")
        self.assertIn("nope", res.json()["detail"]["message"])
        self.assertIn("Trees: t.", res.json()["detail"]["message"])

    def test_no_file_is_404_missing(self):
        self.hub.mkdir()
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.json()["detail"], {"kind": "missing", "message": "There is no org.json in the hub."})

    def test_a_hub_that_is_not_there_is_404_missing(self):
        res = self.client.get(ROUTE)
        self.assertEqual((res.status_code, res.json()["detail"]["kind"]), (404, "missing"))

    def test_no_hub_configured_is_404_no_hub(self):
        default = config.DEFAULT_CONFIG_PATH
        data = json.loads(default.read_text(encoding="utf-8"))
        data["promptsRoot"] = ""
        default.write_text(json.dumps(data), encoding="utf-8")
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.json()["detail"]["kind"], "no-hub")
        self.assertIn("No hub is configured", res.json()["detail"]["message"])

    def test_an_invalid_file_is_409_with_its_kind_and_sentence(self):
        self.put(text='{"trees": []}')
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 409)
        self.assertEqual(
            res.json()["detail"],
            {"kind": "no-trees", "message": "org.json has no trees: 'trees' must be an array with at least one tree."},
        )

    def test_a_file_that_is_not_utf8_is_read_the_way_the_cli_reads_it(self):
        self.hub.mkdir()
        (self.hub / "org.json").write_bytes(b'{"trees": [{"id": "t\xff", "positions": [{"id": "r"}]}]}')
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["tree"]["id"], "t�")

    def test_nothing_is_written_to_the_hub(self):
        self.put(self.doc(prompt="lead.prompt.md"), {"lead.prompt.md": "# Lead\n"})
        before = self.tree_of_files()
        self.client.get(ROUTE)
        self.client.get(ROUTE + "?tree=nope")
        self.assertEqual(self.tree_of_files(), before)

    def test_the_sample_hub_reads(self):
        sample = REPO_ROOT / "samples" / "hub"
        with mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(sample)}):
            res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 200, res.text)
        body = res.json()
        self.assertEqual((body["activeTree"], body["tree"]["title"]), ("mine", "My team"))
        positions = body["tree"]["positions"]
        self.assertEqual(
            [(p["id"], p["level"]) for p in positions],
            [
                ("owner", 0),
                ("vp-product", 1),
                ("butler", 2),
                ("vp-engineering", 1),
                ("pm", 1),
                ("team-lead", 2),
                ("builder", 3),
                ("intern", 2),
            ],
        )
        by_id = {p["id"]: p for p in positions}
        self.assertEqual([s["state"] for s in by_id["team-lead"]["seats"]], ["staffed", "vacant"])
        # Every office names a role the toolkit ships: the sample hub has no copy,
        # so the lookup finds the toolkit's agentic/org/ and the ref is a shipped one.
        roles = {
            "vp-product": ("vp-of-product", "owner", "VP of product"),
            "butler": ("butler", "vp-product", "Butler"),
            "vp-engineering": ("vp-of-engineering", "owner", "VP of engineering"),
            "pm": ("pm", "owner", "PM"),
            "team-lead": ("team-lead", "pm", "Team lead"),
            "intern": ("intern", "pm", "Intern"),
        }
        for pid, (role, reports_to, title) in roles.items():
            got = by_id[pid]
            self.assertEqual(
                (got["prompt"], got["reportsTo"], got["promptRef"], got["promptTitle"]),
                (f"{role}.prompt.md", reports_to, role, title),
                pid,
            )
            self.assertFalse((sample / "agentic" / "org" / f"{role}.prompt.md").exists(), pid)
        for pid in ("owner", "builder"):
            self.assertEqual((by_id[pid]["promptTitle"], by_id[pid]["promptRef"]), (None, None), pid)


class TheFlagOff(OrgBase):
    """Off means absent: 404 whatever the file says, and the detail names which is off."""

    features = {}

    def test_off_is_404_not_403_and_the_file_is_not_read(self):
        self.put(self.doc())
        with mock.patch.object(org, "find_org_chart") as read:
            res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 404)
        self.assertIn("features.solitaireAgile", res.json()["detail"])
        read.assert_not_called()

    def test_off_is_404_with_a_tree_and_with_no_file_alike(self):
        self.assertEqual(self.client.get(ROUTE + "?tree=x").status_code, 404)


class TheSpaceWorkedAlone(OrgBase):
    """The Space is answered otherwise: the module is off for it, so the route is
    absent and the detail says which Space and which answer."""

    how_i_work = "alone"

    def test_it_is_404_and_names_the_space_and_its_answer(self):
        self.put(self.doc())
        res = self.client.get(ROUTE)
        self.assertEqual(res.status_code, 404)
        self.assertIn("widgets", res.json()["detail"])
        self.assertIn("alone", res.json()["detail"])


class TheAppMountsIt(unittest.TestCase):
    def test_the_app_serves_the_route(self):
        from agent.app import app

        self.assertIn(C.rituals_org_route(), set(app.openapi()["paths"]))

    def test_the_app_serves_the_presets_route(self):
        from agent.app import app

        self.assertIn(C.rituals_org_presets_route(), set(app.openapi()["paths"]))


# -- The presets (docs/hub/org.md, "Org presets") -------------------------------

PRESETS_ROUTE = "/api/ritual/org/presets"
PRESET_IDS = ["executive-suite", "branch-office", "corporate-headquarters"]


def shipped_prompt(name: str) -> bool:
    return (prompts.shipped_roles_dir() / name).is_file()


class ThePresets(unittest.TestCase):
    """The three presets the toolkit ships, read from the package."""

    def setUp(self):
        self.presets = org.org_presets()

    def test_there_are_three_smallest_first(self):
        self.assertEqual([p["id"] for p in self.presets], PRESET_IDS)
        self.assertEqual([p["size"] for p in self.presets], ["S", "M", "L"])
        self.assertEqual([p["teamSize"] for p in self.presets], [3, 6, 9])

    def test_every_file_in_the_folder_reads_as_a_preset(self):
        files = sorted(config.ORG_PRESETS_DIR.glob("*.json"))
        self.assertEqual(len(files), len(self.presets), [f.name for f in files])
        self.assertEqual(sorted(f.stem for f in files), sorted(PRESET_IDS))

    def test_each_carries_its_words(self):
        for p in self.presets:
            with self.subTest(p["id"]):
                for key in ("title", "shortDescription", "description"):
                    self.assertTrue(p[key], key)
                self.assertEqual(p["chart"]["tree"]["id"], p["id"])
                self.assertEqual(p["chart"]["tree"]["title"], p["title"])

    def test_each_names_only_roles_the_toolkit_ships(self):
        for p in self.presets:
            for position in p["chart"]["tree"]["positions"]:
                if position["prompt"]:
                    with self.subTest(p["id"], position=position["id"]):
                        self.assertTrue(shipped_prompt(position["prompt"]), position["prompt"])

    def test_the_owner_is_the_root_and_a_person(self):
        for p in self.presets:
            with self.subTest(p["id"]):
                root = p["chart"]["tree"]["positions"][0]
                self.assertEqual((root["id"], root["level"], root["prompt"]), ("owner", 0, None))
                self.assertEqual(root["seats"][0]["state"], "staffed")

    def test_every_other_seat_is_open_for_the_owner_to_fill(self):
        for p in self.presets:
            for position in p["chart"]["tree"]["positions"][1:]:
                for seat in position["seats"]:
                    with self.subTest(p["id"], seat=seat["id"]):
                        self.assertEqual(seat["state"], "vacant")

    def test_the_seats_and_the_room(self):
        # S fills its room of three. M has five seats for a room of six, and L ten for a room of
        # nine: the room seats who has work first.
        seats = [sum(len(x["seats"]) for x in p["chart"]["tree"]["positions"]) for p in self.presets]
        self.assertEqual(seats, [3, 5, 10])
        self.assertEqual(seats[0], self.presets[0]["teamSize"])

    def test_a_team_is_one_lead_and_its_own_builders(self):
        # One lead seat to an office, and each lead's own pool reporting to it alone: M has one
        # team, L one under the PM for each project.
        want = {"executive-suite": 0, "branch-office": 1, "corporate-headquarters": 2}
        for p in self.presets:
            positions = p["chart"]["tree"]["positions"]
            leads = [x for x in positions if x["prompt"] == "team-lead.prompt.md"]
            with self.subTest(p["id"]):
                self.assertEqual(len(leads), want[p["id"]])
                for lead in leads:
                    self.assertEqual([s["id"] for s in lead["seats"]], ["lead"])
                    pools = [x for x in positions if x["reportsTo"] == lead["id"]]
                    self.assertEqual(len(pools), 1, lead["id"])
                    self.assertEqual((pools[0]["seats"], pools[0]["title"]), ([], "Builder"))
                    boss = "pm" if p["id"] == "corporate-headquarters" else "vp-engineering"
                    self.assertEqual(lead["reportsTo"], boss)

    def test_no_seat_names_a_machine_and_no_text_names_one(self):
        # Sessions talk across machines, so a machine is not a boundary in an org.
        words = ("machine", "laptop", "mini", " pc")
        for p in self.presets:
            with self.subTest(p["id"]):
                # machines and machine are retired: no preset file carries one at any level.
                raw = json.loads((org.ORG_PRESETS_DIR / f"{p['id']}.json").read_text(encoding="utf-8"))
                self.assertNotIn("machines", raw)
                for position in raw["positions"]:
                    self.assertFalse([s for s in position.get("seats", []) if "machine" in s], position["id"])
                for position in p["chart"]["tree"]["positions"]:
                    self.assertFalse(any(w in (position["defaultModel"] or "").lower() for w in words))
                text = f"{p['shortDescription']} {p['description']}".lower()
                self.assertFalse([w for w in words if w in text])

    def test_each_names_who_holds_the_merge(self):
        for p in self.presets:
            with self.subTest(p["id"]):
                self.assertIn("VP of product", p["description"])
                self.assertIn("merge", p["description"])


class APresetFile(unittest.TestCase):
    """What the reader makes of one preset's text."""

    BASE = {
        "id": "x",
        "size": "S",
        "title": "The X",
        "shortDescription": "short",
        "description": "long",
        "teamSize": 3,
        "positions": [
            {"id": "owner", "title": "Owner", "seats": [{"id": "owner", "person": "You"}]},
            {"id": "pm", "title": "PM", "prompt": "pm.prompt.md", "reportsTo": "owner", "seats": [{"id": "pm"}]},
        ],
    }

    def read(self, doc):
        return org.read_preset(json.dumps(doc), shipped_prompt)

    def test_a_field_it_does_not_know_reads_fine(self):
        extra = json.loads(json.dumps(self.BASE))
        extra["swag"] = {"mug": "blue"}
        extra["waysOfWorking"] = ["readies straight to the merge seat"]
        extra["positions"][1]["swag"] = "badge"
        extra["positions"][1]["seats"][0]["desk"] = "by the window"
        self.assertTrue(same_json(self.read(extra), self.read(self.BASE)))
        self.assertIsNotNone(self.read(extra))

    def test_its_fields_and_its_chart(self):
        got = self.read(self.BASE)
        self.assertEqual(
            {k: got[k] for k in org.PRESET_FIELDS},
            {k: self.BASE[k] for k in org.PRESET_FIELDS},
        )
        self.assertEqual([x["id"] for x in got["chart"]["tree"]["positions"]], ["owner", "pm"])

    def test_a_tree_that_fails_a_check_is_no_preset(self):
        broken = json.loads(json.dumps(self.BASE))
        broken["positions"][1]["reportsTo"] = "nobody"
        self.assertIsNone(self.read(broken))

    def test_a_role_the_toolkit_does_not_ship_is_no_preset(self):
        broken = json.loads(json.dumps(self.BASE))
        broken["positions"][1]["prompt"] = "mine.prompt.md"
        self.assertIsNone(self.read(broken))

    def test_no_id_or_not_json_is_no_preset(self):
        no_id = dict(self.BASE)
        del no_id["id"]
        self.assertIsNone(self.read(no_id))
        self.assertIsNone(org.read_preset("{nope", shipped_prompt))
        self.assertIsNone(org.read_preset("[]", shipped_prompt))

    def test_a_file_that_is_no_preset_is_left_out_of_the_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "good.json").write_text(json.dumps(self.BASE), encoding="utf-8")
            (folder / "bad.json").write_text("{nope", encoding="utf-8")
            self.assertEqual([p["id"] for p in org.org_presets(folder)], ["x"])


class ThePresetsRoute(OrgBase):
    def test_it_serves_the_three_with_their_charts_and_prompts(self):
        res = self.client.get(PRESETS_ROUTE)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual([p["id"] for p in body["presets"]], PRESET_IDS)
        for p in body["presets"]:
            for position in p["chart"]["tree"]["positions"]:
                with self.subTest(p["id"], position=position["id"]):
                    self.assertIn("promptTitle", position)
                    self.assertEqual(bool(position["promptTitle"]), bool(position["prompt"]))

    def test_it_needs_no_org_file_and_writes_nothing(self):
        self.assertFalse((self.hub / "org.json").exists())
        self.assertEqual(self.client.get(PRESETS_ROUTE).status_code, 200)
        self.assertFalse(self.hub.exists() and any(self.hub.rglob("*")))


class ThePresetsFlagOff(OrgBase):
    features = {}

    def test_off_is_404(self):
        with mock.patch.object(org, "org_presets") as read:
            res = self.client.get(PRESETS_ROUTE)
        self.assertEqual(res.status_code, 404)
        read.assert_not_called()


# -- The schema: Config/org.schema.json, validated for real --------------------------
#
# docs/hub/org.md, "The schema". The sample hub's org.json is a file; each preset is
# one tree, validated against the schema's tree. jsonschema is a dev-only dependency
# (agent/requirements-dev.txt); without it these cases skip, by name.

SCHEMA_PATH = REPO_ROOT / "Config" / "org.schema.json"
try:
    import jsonschema
except ImportError:  # pragma: no cover - a venv without the dev requirements
    jsonschema = None
_NO_JSONSCHEMA = "jsonschema is not installed (agent/requirements-dev.txt)"


@unittest.skipUnless(jsonschema, _NO_JSONSCHEMA)
class TheSchema(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))

    def validator(self, part: str | None = None):
        """The schema's validator; ``part`` ('file' or 'tree') validates against that $def alone."""
        schema = self.schema
        if part:
            schema = {"$schema": self.schema["$schema"], "$defs": self.schema["$defs"], "$ref": f"#/$defs/{part}"}
        return jsonschema.Draft202012Validator(schema)

    def errors(self, doc, part: str | None = None) -> list[str]:
        return [e.message for e in self.validator(part).iter_errors(doc)]

    def test_it_is_a_valid_draft_2020_12_schema(self):
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        jsonschema.Draft202012Validator.check_schema(self.schema)

    def test_every_level_lets_an_unknown_key_through(self):
        for name, part in self.schema["$defs"].items():
            self.assertIs(part.get("additionalProperties"), True, name)

    def test_it_says_what_it_cannot_express(self):
        for words in ("loop", "one root", "role file"):
            self.assertIn(words, self.schema["description"])

    def test_the_sample_hubs_org_file_is_valid(self):
        doc = json.loads((REPO_ROOT / "samples" / "hub" / "org.json").read_text(encoding="utf-8"))
        self.assertEqual(self.errors(doc, "file"), [])
        self.assertEqual(self.errors(doc), [])

    def test_every_preset_is_a_valid_tree(self):
        files = sorted(config.ORG_PRESETS_DIR.glob("*.json"))
        self.assertEqual(len(files), 3)
        for path in files:
            with self.subTest(path.name):
                doc = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(self.errors(doc, "tree"), [])
                self.assertEqual(self.errors(doc), [])

    def test_the_tables_whole_shape_is_valid(self):
        doc = json.loads((FIXTURES / "docs" / "shape.json").read_text(encoding="utf-8"))
        self.assertEqual(self.errors(doc, "file"), [])

    def test_what_it_refuses(self):
        seat = {"id": "s"}
        tree = {"id": "t", "positions": [{"id": "p", "seats": [seat]}]}
        rows = [
            ({}, "file", "'trees' is a required property"),
            ({"trees": []}, "file", "should be non-empty"),
            ({"trees": [{"positions": []}]}, "file", "'id' is a required property"),
            ({"trees": [{"id": "t"}]}, "file", "'positions' is a required property"),
            ({"trees": [tree, {**tree, "id": "u"}]}, "file", "'activeTree' is a required property"),
            ({**tree, "size": "XL"}, "tree", "'XL' is not one of"),
            ({**tree, "teamSize": 4}, "tree", "4 is not one of"),
            ({**tree, "activatedAt": "26 November"}, "tree", "does not match"),
            ({**tree, "positions": [{"title": "x"}]}, "tree", "'id' is a required property"),
            ({**tree, "positions": [{"id": "p", "recommend": "opus"}]}, "tree", "is not of type 'array'"),
            ({**tree, "positions": [{"id": "p", "seats": [{"model": "m"}]}]}, "tree", "'id' is a required property"),
            (
                {**tree, "positions": [{"id": "p", "seats": [{"id": "s", "merges": "yes"}]}]},
                "tree",
                "is not of type 'boolean'",
            ),
        ]
        for doc, part, words in rows:
            with self.subTest(doc=doc):
                found = self.errors(doc, part)
                self.assertTrue(any(words in e for e in found), found)
        # And what it lets through: an unknown key and a note at every level, the retired keys.
        loose = {
            "_note": "",
            "colour": "x",
            "trees": [
                {
                    **tree,
                    "region": "x",
                    "machines": ["a"],
                    "positions": [
                        {"id": "p", "budget": 1, "seats": [{"id": "s", "badge": 1, "machine": "a", "active": True}]}
                    ],
                }
            ],
        }
        self.assertEqual(self.errors(loose, "file"), [])


class TheModelName(unittest.TestCase):
    """A seat's ``modelName``: the model map's name, looked up and never parsed."""

    def test_an_id_with_a_row_is_its_name(self):
        self.assertEqual(org.model_name("claude-opus-5-5"), "Opus 5.5")

    def test_a_family_is_the_name_of_the_id_it_is_today(self):
        from agent.core import models

        for family in ("opus", "fable", "sonnet", "haiku"):
            with self.subTest(family):
                today = models.current_model(family)
                self.assertTrue(today)
                self.assertEqual(org.model_name(family), models.model_info(today)["name"])

    def test_a_pool_line_written_as_an_id_reads_as_its_name(self):
        # Staff -Preset writes the builder pool's defaultModel as an id; the page shows its name.
        chart = {"tree": {"positions": [{"prompt": None, "defaultModel": "claude-sonnet-5-5", "seats": []}]}}
        org.with_prompts(chart)
        self.assertEqual(chart["tree"]["positions"][0]["defaultModelName"], "Sonnet 5.5")

    def test_anything_else_is_as_written_and_no_model_is_none(self):
        self.assertEqual(org.model_name("sonnet for crew cards"), "sonnet for crew cards")
        self.assertEqual(org.model_name("claude-opus-9-9"), "claude-opus-9-9")
        self.assertIsNone(org.model_name(None))
        self.assertIsNone(org.model_name(""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
