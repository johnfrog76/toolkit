"""A card's pictures: the reader of its ``**Cover:**`` / ``**Before:**`` lines, the
model's ``cover`` and ``before``, and ``GET /api/assets/{space}/{key}/{file}``.

docs/hub/cards.md, "A card's pictures". The reader is held to the
CLI's by ONE table, ``Tests/fixtures/parsers/covers.json`` -- read here against
``agent/core/assets.py`` ``card_image`` and by ``tkTestToolkit -Cover`` against
``Resolve-P20CardImage``. If the two ever disagree about a row, one is wrong.

Run:  python3 -m pytest Tests/test_assets.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _skipguard import skip_module

try:
    from fastapi.testclient import TestClient

    from agent.core import config
    from agent.core.assets import card_image
    from agent.core.consts import stamp_before, stamp_cover
except Exception as exc:  # pragma: no cover - a machine without the agent's deps
    skip_module(f"the agent's dependencies are not installed: {exc}")

FIXTURE = Path(__file__).parent / "fixtures" / "parsers" / "covers.json"

# Eight bytes that open every PNG: enough for a file to be one on disk.
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24


def _card_text(footer: list[str]) -> str:
    lines = [
        "# Spike K7M2: Can we import a recipe from a photo?",
        "",
        "## Summary",
        "Paper recipes.",
        "",
        "---",
        "",
        "**Sprint:** RecipeBox\\Sprint 9",
        *footer,
        "**Created:** 2026-09-18",
        "",
    ]
    return "\n".join(lines)


class TheSharedTable(unittest.TestCase):
    """Every row of covers.json, built as a scratch Space and read by card_image."""

    @classmethod
    def setUpClass(cls):
        cls.table = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_every_row(self):
        for row in self.table["rows"]:
            with self.subTest(row=row["name"]):
                scratch = tempfile.mkdtemp()
                try:
                    space = Path(scratch) / "space"
                    card_dir = space / row["folder"]
                    card_dir.mkdir(parents=True)
                    for rel in row["files"]:
                        target = space / rel
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(PNG)
                    text = _card_text(row["footer"])
                    if row["crlf"]:
                        text = text.replace("\n", "\r\n")
                    card = card_dir / self.table["cardName"]
                    card.write_bytes(text.encode("utf-8"))
                    content = card.read_bytes().decode("utf-8")
                    self.assertEqual(card_image(content, card, stamp_cover()), row["cover"])
                    self.assertEqual(card_image(content, card, stamp_before()), row["before"])
                finally:
                    shutil.rmtree(scratch, ignore_errors=True)

    def test_the_table_has_the_rows_the_spec_asks_for(self):
        """Spec 8: a line whose file is missing, a path that climbs out, a CRLF card."""
        names = " | ".join(r["name"] for r in self.table["rows"])
        for words in ("file is missing", "climbs out", "CRLF", "no line"):
            self.assertIn(words, names)


class TheRouteAndTheModel(unittest.TestCase):
    def setUp(self):
        self.hub = tempfile.TemporaryDirectory()
        root = Path(self.hub.name)
        self.space = root / "demo"
        (self.space / "current").mkdir(parents=True)
        (self.space / "archive").mkdir(parents=True)
        (self.space / "assets" / "214").mkdir(parents=True)
        (self.space / "assets" / "214" / "before.png").write_bytes(PNG)
        (self.space / "assets" / "214" / "cover.jpg").write_bytes(b"\xff\xd8\xff\xe0jpeg")
        (self.space / "assets" / "214" / "add_prize_drawer.html").write_text("<p>a mock</p>", encoding="utf-8")
        (self.space / "assets" / "US-209").mkdir(parents=True)
        (self.space / "current" / "secret.png").write_bytes(PNG)
        (root / "outside.png").write_bytes(PNG)
        (self.space / "current" / "214-search-returns-duplicates.prompt.md").write_text(
            _card_text(
                [
                    f"{stamp_before()} ../assets/214/before.png",
                    f"{stamp_cover()} ../assets/214/cover.jpg",
                ]
            ).replace("Spike K7M2", "Bug 214"),
            encoding="utf-8",
        )
        (self.space / "current" / "US-209-paginate.prompt.md").write_text(
            _card_text(
                [
                    f"{stamp_cover()} ../assets/US-209/cover.png",  # the file is missing
                ]
            ).replace("Spike K7M2", "User Story 209"),
            encoding="utf-8",
        )
        (self.space / "current" / "Task211-extract.prompt.md").write_text(
            _card_text([]).replace("Spike K7M2", "Task 211"), encoding="utf-8"
        )

        self.cfg = tempfile.TemporaryDirectory()
        base = Path(self.cfg.name)
        (base / "config.default.json").write_text(
            json.dumps(
                {
                    "activeSpace": "demo",
                    "commandPrefix": "tk",
                    "features": {},
                    "spaces": [
                        {"slug": "demo", "status": "local", "promptsFolder": "demo"},
                        {"slug": "other", "status": "local", "promptsFolder": "other"},
                    ],
                    "commands": {},
                    "workItemTypes": {
                        "User Story": {"filePrefix": "US-"},
                        "Task": {"filePrefix": "Task"},
                        "Bug": {"filePrefix": ""},
                        "Spike": {"filePrefix": "Spike-"},
                    },
                }
            ),
            encoding="utf-8",
        )
        (base / "config.local.json").write_text(json.dumps({"promptsRoot": self.hub.name}), encoding="utf-8")
        self.patches = [
            mock.patch.object(config, "DEFAULT_CONFIG_PATH", base / "config.default.json"),
            mock.patch.object(config, "LOCAL_CONFIG_PATH", base / "config.local.json"),
            mock.patch.dict(os.environ, {"PROMPTS_ROOT": ""}, clear=False),
        ]
        for p in self.patches:
            p.start()
        from agent.app import app

        self.client = TestClient(app)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.cfg.cleanup()
        self.hub.cleanup()

    def _by_file(self):
        return {p["file"]: p for p in self.client.get("/api/status").json()["prompts"]}

    def test_the_model_serves_urls_of_the_route(self):
        card = self._by_file()["214-search-returns-duplicates.prompt.md"]
        self.assertEqual(card["cover"], "/api/assets/demo/214/cover.jpg")
        self.assertEqual(card["before"], "/api/assets/demo/214/before.png")

    def test_a_missing_file_and_no_line_are_both_null(self):
        cards = self._by_file()
        self.assertIsNone(cards["US-209-paginate.prompt.md"]["cover"])
        self.assertIsNone(cards["Task211-extract.prompt.md"]["cover"])
        self.assertIsNone(cards["Task211-extract.prompt.md"]["before"])

    def test_the_card_page_serves_them_too(self):
        detail = self.client.get("/api/status/214-search-returns-duplicates.prompt.md").json()
        self.assertEqual(
            (detail["cover"], detail["before"]), ("/api/assets/demo/214/cover.jpg", "/api/assets/demo/214/before.png")
        )

    def test_the_route_serves_the_picture_with_its_type(self):
        r = self.client.get("/api/assets/demo/214/cover.jpg")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers["content-type"], "image/jpeg")
        self.assertEqual(r.content, b"\xff\xd8\xff\xe0jpeg")
        r = self.client.get("/api/assets/demo/214/before.png")
        self.assertEqual((r.status_code, r.headers["content-type"]), (200, "image/png"))

    def test_the_url_the_model_serves_is_one_the_route_answers(self):
        url = self._by_file()["214-search-returns-duplicates.prompt.md"]["cover"]
        self.assertEqual(self.client.get(url).status_code, 200)

    def test_only_images_are_served(self):
        self.assertEqual(self.client.get("/api/assets/demo/214/add_prize_drawer.html").status_code, 404)

    def test_a_missing_picture_and_an_unknown_space_are_404(self):
        self.assertEqual(self.client.get("/api/assets/demo/214/nope.png").status_code, 404)
        self.assertEqual(self.client.get("/api/assets/nowhere/214/before.png").status_code, 404)

    def test_nothing_outside_the_spaces_assets_is_reachable(self):
        """Resolved, then checked: no spelling of .. gets out."""
        for path in (
            "/api/assets/demo/..%2Fcurrent/secret.png",
            "/api/assets/demo/214/..%2F..%2Fcurrent%2Fsecret.png",
            "/api/assets/demo/..%2F..%2F/outside.png",
            "/api/assets/demo/%2E%2E/outside.png",
            "/api/assets/demo/214/%2Fetc%2Fpasswd",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.client.get(path).status_code, 404)

    def test_the_route_writes_nothing(self):
        before = sorted(str(p) for p in Path(self.hub.name).rglob("*"))
        self.client.get("/api/assets/demo/214/cover.jpg")
        self.client.get("/api/assets/demo/214/nope.png")
        self.assertEqual(sorted(str(p) for p in Path(self.hub.name).rglob("*")), before)

    def test_it_is_core_no_flag(self):
        """Every features flag off: the route and the fields are still there."""
        with mock.patch.dict(os.environ, {"P20_FEATURES": "{}"}, clear=False):
            self.assertEqual(self.client.get("/api/assets/demo/214/cover.jpg").status_code, 200)


class TheUploadRoute(unittest.TestCase):
    """``POST /api/assets/upload`` (C2): the bytes land in a temp
    file and the path comes back; the hub is never written -- the verb is the one
    writer. The browser hears a refusal the verb would give before a shell starts."""

    def setUp(self):
        from agent.app import app

        self._tmp = tempfile.TemporaryDirectory()
        self.hub = Path(self._tmp.name) / "hub"
        (self.hub / "demo" / "current").mkdir(parents=True)
        (self.hub / "demo" / "current" / "K7M2-a-card.prompt.md").write_text("# K7M2: a card\n", encoding="utf-8")
        self.client = TestClient(app)
        self._patch = mock.patch.object(config, "hub_root", return_value=self.hub)
        self._patch.start()

    def tearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def snapshot(self) -> dict:
        return {str(p): p.read_bytes() for p in self.hub.rglob("*") if p.is_file()}

    def test_the_bytes_land_in_a_temp_file_and_nothing_lands_in_the_hub(self):
        before = self.snapshot()
        res = self.client.post("/api/assets/upload?name=shot.png", content=PNG, headers={"Content-Type": "image/png"})
        self.assertEqual(res.status_code, 200, res.text)
        body = res.json()
        path = Path(body["path"])
        self.assertTrue(path.is_file())
        self.assertEqual(path.read_bytes(), PNG)
        self.assertEqual((body["name"], body["bytes"]), ("shot.png", len(PNG)))
        self.assertIn("p20-upload-", path.parent.name)
        self.assertFalse(str(path).startswith(str(self.hub)), "the upload must never land in the hub")
        self.assertEqual(self.snapshot(), before, "the route wrote into the hub")
        shutil.rmtree(path.parent, ignore_errors=True)

    def test_the_name_is_its_basename_and_safe(self):
        res = self.client.post("/api/assets/upload?name=../../evil dir/sh ot.PNG", content=PNG)
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(res.json()["name"], "sh-ot.PNG")
        path = Path(res.json()["path"])
        self.assertEqual(path.name, "sh-ot.PNG")
        shutil.rmtree(path.parent, ignore_errors=True)

    def test_refusals_say_the_verbs_sentence_and_write_nothing(self):
        before = self.snapshot()
        res = self.client.post("/api/assets/upload?name=notes.txt", content=PNG)
        self.assertEqual(res.status_code, 400)
        self.assertIn("not an image type Cover accepts (png, jpg, jpeg, webp, gif)", res.json()["detail"])
        res = self.client.post("/api/assets/upload?name=shot.png", content=b"")
        self.assertEqual(res.status_code, 400)
        self.assertIn("No bytes", res.json()["detail"])
        with mock.patch("agent.core.assets.cover_max_bytes", return_value=16):
            res = self.client.post("/api/assets/upload?name=shot.png", content=PNG)
        self.assertEqual(res.status_code, 413)
        self.assertIn("Cover copies at most 16", res.json()["detail"])
        res = self.client.post("/api/assets/upload", content=PNG)
        self.assertEqual(res.status_code, 400)
        self.assertEqual(self.snapshot(), before)


class TheUploadFolderIsFinished(unittest.TestCase):
    """The folder an upload made is removed when the verb handed its path is done
    (success or failure), only ever for a real ``p20-upload-`` folder directly in
    the system temp, and a sweep at agent start drops the stale ones."""

    def setUp(self):
        from agent.app import app

        self.client = TestClient(app)
        self._made = []

    def tearDown(self):
        for d in self._made:
            shutil.rmtree(d, ignore_errors=True)

    def upload(self) -> Path:
        res = self.client.post("/api/assets/upload?name=shot.png", content=PNG)
        self.assertEqual(res.status_code, 200, res.text)
        path = Path(res.json()["path"])
        self._made.append(path.parent)
        return path

    def run_verb(self, returncode: int, params: list):
        from agent.ado import bridge

        done = subprocess.CompletedProcess([], returncode, stdout="", stderr="" if returncode == 0 else "no")
        with (
            mock.patch.object(bridge, "resolve_host", return_value="pwsh"),
            mock.patch.object(bridge, "command_map", return_value={"Cover": "Set-CardCover"}),
            mock.patch.object(bridge, "_run", return_value=done),
        ):
            return self.client.post("/api/cmd/Cover", json={"params": params}).json()

    def test_the_folder_is_gone_after_an_attach(self):
        path = self.upload()
        self.assertEqual(self.run_verb(0, ["K7M2-a-card.prompt.md", str(path)])["status"], "success")
        self.assertFalse(path.parent.exists())

    def test_the_folder_is_gone_after_a_failed_attach(self):
        path = self.upload()
        self.assertEqual(self.run_verb(1, ["K7M2-a-card.prompt.md", str(path)])["status"], "error")
        self.assertFalse(path.parent.exists())

    def test_a_path_that_is_not_an_upload_is_never_deleted(self):
        with tempfile.TemporaryDirectory() as t:
            elsewhere = Path(t) / "shot.png"
            elsewhere.write_bytes(PNG)
            prefixed_deeper = Path(t) / "p20-upload-x" / "shot.png"
            prefixed_deeper.parent.mkdir()
            prefixed_deeper.write_bytes(PNG)
            plain = Path(tempfile.mkdtemp(prefix="other-"))
            self._made.append(plain)
            (plain / "shot.png").write_bytes(PNG)
            self.run_verb(
                0, [str(elsewhere), str(prefixed_deeper), str(plain / "shot.png"), "-Before", t, tempfile.gettempdir()]
            )
            self.assertTrue(elsewhere.exists())
            self.assertTrue(prefixed_deeper.exists(), "only a folder directly in the system temp counts")
            self.assertTrue((plain / "shot.png").exists())
            self.assertTrue(Path(tempfile.gettempdir()).is_dir())

    def test_the_sweep_removes_only_old_prefixed_folders(self):
        from agent.core.assets import UPLOAD_PREFIX, sweep_stale_uploads

        old = Path(tempfile.mkdtemp(prefix=UPLOAD_PREFIX))
        fresh = Path(tempfile.mkdtemp(prefix=UPLOAD_PREFIX))
        other_old = Path(tempfile.mkdtemp(prefix="not-an-upload-"))
        self._made += [old, fresh, other_old]
        for d in (old, other_old):
            (d / "f.png").write_bytes(PNG)
            long_ago = time.time() - 3 * 24 * 60 * 60
            os.utime(d, (long_ago, long_ago))
        sweep_stale_uploads()
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())
        self.assertTrue(other_old.exists())

    def test_the_agent_sweeps_on_start(self):
        from agent.app import app

        with mock.patch("agent.core.assets.sweep_stale_uploads") as sweep, TestClient(app):
            pass
        sweep.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
