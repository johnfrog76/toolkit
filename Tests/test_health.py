"""GET /api/health says which checkout the agent runs from.

prompts_root says whose DATA an agent serves; package_root says whose PROCESS
it is. Scripts/Start-Agent.ps1 reads both: it stops or restarts an agent from
its own checkout that another shell started, and leaves another package's
alone. That decision is only as good as this field, so it is pinned here.
"""

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

PKG_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PKG_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from fastapi.testclient import TestClient

    from agent.app import app
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")


class HealthNamesItsCheckout(unittest.TestCase):
    def test_package_root_is_this_checkout(self):
        body = TestClient(app).get("/api/health").json()
        self.assertEqual(Path(body["package_root"]).resolve(), PKG_ROOT)

    def test_package_root_does_not_follow_the_hub_override(self):
        # The override moves the data, never the process's identity -- the
        # launcher tells the two apart by exactly this.
        with mock.patch.dict(os.environ, {"PROMPTS_ROOT": str(PKG_ROOT / "Tests" / "fixtures" / "hub")}):
            body = TestClient(app).get("/api/health").json()
        self.assertEqual(Path(body["package_root"]).resolve(), PKG_ROOT)
        self.assertEqual(Path(body["prompts_root"]).resolve(), (PKG_ROOT / "Tests" / "fixtures" / "hub").resolve())


if __name__ == "__main__":
    unittest.main(verbosity=2)
