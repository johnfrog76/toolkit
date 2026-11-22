"""The sign-in strip's state: which Space it is for, and what /env says about it.

``agent/core/signin.py`` decides ``needed`` -- true on an ACTIVE Azure DevOps Space
where ``az`` is installed and not signed in, and nowhere else -- and /env carries it
as ``azSignIn`` beside the command, which is consts.json's. The agent only ASKS
``az`` (``account show``); the table below also holds that nothing here ever starts
a sign-in.

Run directly:  python3 Tests/test_signin.py
Under pytest:  python3 -m pytest Tests/
"""

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
    from agent.core import consts, signin, tier
    from agent.core import env as env_route
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

ADO = "https://dev.azure.com/acme"
GITHUB = "https://github.com/acme/widgets"
COMMAND = "az login --allow-no-subscriptions"

# (what the row is, org address, Space status, az installed, az signed in, needed)
ROWS = [
    ("Azure DevOps, active, az signed out: shown", ADO, "active", True, False, True),
    ("Azure DevOps, active, az signed in: not shown", ADO, "active", True, True, False),
    ("Azure DevOps, active, az missing: not shown", ADO, "active", False, False, False),
    ("Azure DevOps, local Space: not shown", ADO, "local", True, False, False),
    ("Azure DevOps, archived Space: not shown", ADO, "archive", True, False, False),
    ("GitHub Space, active, az signed out: not shown", GITHUB, "active", True, False, False),
    ("GitHub Space, local: not shown", GITHUB, "local", True, False, False),
    ("no tracker: not shown", "", "local", True, False, False),
]


class _Az:
    """A stand-in for ``az``: installed or not, signed in or not, and a record of every call."""

    def __init__(self, installed: bool, signed_in: bool):
        self.installed = installed
        self.signed_in = signed_in
        self.calls: list[list[str]] = []

    def which(self, name):
        return "/usr/bin/az" if (name == "az" and self.installed) else None

    def run(self, cmd, **_kwargs):
        self.calls.append(list(cmd))
        if self.signed_in:
            return mock.Mock(returncode=0, stdout='{"user": {"name": "me@acme.test"}}', stderr="")
        return mock.Mock(returncode=1, stdout="", stderr="Please run 'az login' to setup account.")

    def __enter__(self):
        self._patches = [
            mock.patch.object(signin.shutil, "which", self.which),
            mock.patch.object(signin.subprocess, "run", self.run),
        ]
        for p in self._patches:
            p.start()
        return self

    def __exit__(self, *exc):
        for p in self._patches:
            p.stop()


class TheStripIsForOneState(unittest.TestCase):
    def test_every_row(self):
        for name, org, status, installed, signed_in, needed in ROWS:
            with self.subTest(name), _Az(installed, signed_in):
                signin.signin_cache_clear()
                block = signin.sign_in_block(org, status)
                self.assertEqual(block["needed"], needed)
                self.assertEqual(block["command"], COMMAND)

    def test_az_is_asked_only_where_the_answer_can_matter(self):
        for name, org, status, installed, signed_in, _needed in ROWS:
            asked = org == ADO and status == "active" and installed
            with self.subTest(name), _Az(installed, signed_in) as az:
                signin.signin_cache_clear()
                signin.sign_in_block(org, status)
                self.assertEqual(len(az.calls), 1 if asked else 0)

    def test_the_agent_never_signs_in(self):
        with _Az(True, False) as az:
            signin.sign_in_block(ADO, "active", refresh=True)
        self.assertEqual(az.calls, [["az", "account", "show", "--output", "json"]])
        for call in az.calls:
            self.assertNotIn("login", call)

    def test_the_command_is_the_contracts(self):
        self.assertEqual(consts.az_login_command(), COMMAND)
        self.assertEqual(consts.sign_in_env_field(), "azSignIn")

    def test_an_answer_is_kept_until_a_refresh_asks_again(self):
        with _Az(True, False) as az:
            signin.signin_cache_clear()
            self.assertTrue(signin.sign_in_block(ADO, "active")["needed"])
            self.assertTrue(signin.sign_in_block(ADO, "active")["needed"])
            self.assertEqual(len(az.calls), 1)
            az.signed_in = True  # az login in another terminal
            self.assertTrue(signin.sign_in_block(ADO, "active")["needed"])  # still the kept answer
            self.assertFalse(signin.sign_in_block(ADO, "active", refresh=True)["needed"])
            self.assertEqual(len(az.calls), 2)

    def test_az_that_raises_is_az_that_is_not_signed_in(self):
        def boom(*_a, **_k):
            raise OSError("no such file")

        with (
            mock.patch.object(signin.shutil, "which", lambda _n: "/usr/bin/az"),
            mock.patch.object(signin.subprocess, "run", boom),
        ):
            signin.signin_cache_clear()
            self.assertTrue(signin.sign_in_block(ADO, "active")["needed"])


class EnvCarriesIt(unittest.TestCase):
    def _env(self, org, status, installed, signed_in, refresh=""):
        cfg = {
            "org": org,
            "status": status,
            "activeSpace": "demo",
            "features": {},
            "spaces": [{"slug": "demo", "name": "Demo", "status": status}],
        }
        patches = [
            mock.patch.object(env_route, "load_config", lambda: cfg),
            mock.patch.object(tier, "_probe_tracker_cached", lambda *_a, **_k: signed_in),
            mock.patch.object(env_route, "identity_block", lambda *_a, **_k: {"email": "", "source": ""}),
        ]
        for p in patches:
            p.start()
        try:
            with _Az(installed, signed_in):
                return TestClient(app).get(f"/api/env{refresh}").json()
        finally:
            for p in patches:
                p.stop()

    def test_a_signed_out_azure_devops_space_says_so(self):
        body = self._env(ADO, "active", True, False)
        self.assertEqual(
            body["azSignIn"],
            {"needed": True, "installed": True, "signedIn": False, "command": COMMAND},
        )

    def test_a_local_space_says_not_needed_and_asks_nothing(self):
        body = self._env(ADO, "local", True, False)
        self.assertEqual(
            body["azSignIn"],
            {"needed": False, "installed": None, "signedIn": None, "command": COMMAND},
        )

    def test_the_field_is_the_contracts_name(self):
        self.assertIn(consts.sign_in_env_field(), self._env(GITHUB, "active", True, True))


if __name__ == "__main__":
    unittest.main()
