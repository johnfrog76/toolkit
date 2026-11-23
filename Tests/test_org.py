"""The org chart's agent half -- GET /api/ritual/org and the reader behind it.

Two readers implement docs/hub/org.md, this one (agent/solitaire/org.py) and the
CLI's (Scripts/Read-OrgChart.ps1), and ONE table holds them to each other:
Tests/fixtures/org/table.json, which ``tkTestToolkit -OrgChart`` asserts from the
other side. A case builds a scratch hub (the table's own header says how); here
each case is read twice -- by the reader on the hub it resolves, and through the
route -- and the chart compares as JSON to the response the table states, key
order aside. A failure's ``kind`` is the contract; its sentence is the CLI's.

Beyond the table: the route's gate (off is 404, not 403), what a failed read
answers, the two fields each position carries for the web (``promptTitle`` and
``promptRef``, through the Studio's one prompt record), and that nothing in the
hub is written.

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
                    for position in body["tree"]["positions"]:
                        # the two fields the web needs; the table's response is the shared part
                        self.assertEqual(
                            set(position) & {"promptTitle", "promptRef"}, {"promptTitle", "promptRef"}, position
                        )
                        del position["promptTitle"], position["promptRef"]
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
        self.assertEqual(got.chart["tree"]["name"], "t")
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
        self.assertEqual((body["activeTree"], body["tree"]["id"], body["tree"]["name"]), ("a", "b", "Branch"))
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
        self.assertEqual((body["activeTree"], body["tree"]["name"]), ("mine", "My team"))
        positions = body["tree"]["positions"]
        self.assertEqual(
            [(p["id"], p["level"]) for p in positions],
            [
                ("owner", 0),
                ("vp-product", 1),
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
