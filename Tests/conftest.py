"""Session setup for the agent's tests. Two jobs, both about not touching the
engineer's own machine state.

1. **The usage log.** Every write through ``agent/core/log_writer.py`` -- the
   bridge's refusals, a fixture hub's config warnings, the manager module's
   "created" lines, the rewrite route's declined key -- used to land in the real
   ``usage.{machine}.log`` at the repo root. That file is what ``tkLog -Errors``
   and the web UI's Log card read as this engineer's history, so a test run
   showed up there as errors: nine of the ten the Log card displayed after a
   Windows verification run were assertions, not events.
   ``P20_USAGE_LOG_DIR`` is the one override both halves read; here it points at
   a temp directory for the whole session.

2. **The webhook variables.** ``SendTeams`` and ``POST /api/comms/send`` take
   whatever is in the environment at face value, and a machine that has ever
   sent a real message may still have one exported. Every ``TEAMS_WEBHOOK_*``
   is removed here by pattern for the run and put back afterwards, and the
   run sets the test-run marker (``consts.json`` ``env.testRunMarker``) that the
   engine's one POST refuses on. ``Tests/Test-Toolkit.ps1`` does the same for
   the CLI suites.

**The log redirect happens at IMPORT time, not in a fixture.** conftest is
imported before test modules are collected, and collection runs module-level
code: ``test_bridge.py`` calls ``bridge.command_map()`` there, which starts a
child PowerShell that logs on its way up. A session fixture is set up after
collection, so the first thing the run did was write to the real log. An
``atexit`` hook removes the directory afterwards.

The webhook guard is autouse and session-scoped, so a file that forgets is
covered anyway.
"""

import atexit
import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _rmtree
from _rmtree import remove_tree

# The two names the runners and the engine share, read from the contract file
# rather than retyped: conftest is imported before the agent package is, so it
# reads the JSON itself.
_CONSTS = json.loads((Path(__file__).resolve().parent.parent / "consts.json").read_text(encoding="utf-8-sig"))
WEBHOOK_PREFIX = _CONSTS["env"]["teamsWebhookPrefix"]
TEST_RUN_MARKER = _CONSTS["env"]["testRunMarker"]

# See the module docstring: at import, because collection logs.
USAGE_LOG_DIR = tempfile.mkdtemp(prefix="p20-test-logs-")
os.environ["P20_USAGE_LOG_DIR"] = USAGE_LOG_DIR
atexit.register(remove_tree, USAGE_LOG_DIR)


def scrub_webhooks(environ) -> dict:
    """Remove every ``TEAMS_WEBHOOK_*`` variable from ``environ`` and hand back
    what was removed, so the caller can put it back. By PATTERN, not by a list
    of names: a name no list could contain is exactly the one that would slip
    through."""
    saved = {name: environ.pop(name) for name in list(environ) if name.startswith(WEBHOOK_PREFIX)}
    return saved


# The marker is an environment variable and nothing else: inherited by this
# runner's own children, seen by nobody else, gone when the process is. A
# person can still send a Teams message from another shell while this runs.
os.environ[TEST_RUN_MARKER] = "1"
_SAVED_WEBHOOKS = scrub_webhooks(os.environ)


@pytest.fixture(scope="session", autouse=True)
def _no_live_webhooks():
    try:
        yield
    finally:
        os.environ.update(_SAVED_WEBHOOKS)
        os.environ.pop(TEST_RUN_MARKER, None)
