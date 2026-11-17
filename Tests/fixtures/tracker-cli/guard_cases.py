"""The cases ``Tests/test_tracker_cli_guard.py`` runs in a child pytest.

Not collected by a normal run (the name is not ``test_*.py``): two of these are
meant to fail, and the suite asserts on how.
"""

import shutil
import subprocess
import sys
from unittest import mock

from _tracker_cli import unreachable


def _ask_gh_as_the_agent_does() -> str:
    """A read that catches everything and answers "unreachable", the shape of
    the agent's own probes: the refusal never reaches the test by itself."""
    try:
        subprocess.run(["gh", "api", "user", "-q", ".login"], capture_output=True, check=False)
    except Exception:
        return "unreachable"
    return "answered"


def test_an_unasked_call_in_this_process():
    assert _ask_gh_as_the_agent_does() == "unreachable"


def test_an_unasked_call_from_a_child():
    # Through the shell, as a child PowerShell would find it: by the PATH.
    child = "import subprocess, sys; sys.exit(subprocess.run('az account show', shell=True).returncode)"
    done = subprocess.run([sys.executable, "-c", child], capture_output=True, check=False)
    assert done.returncode != 0


def test_an_unasked_gh_from_a_child_through_the_shell():
    # On Windows the real gh is a .exe further along the PATH and the stand-in a
    # .cmd: the shell reads the PATH folder by folder, so the stand-in answers.
    child = "import subprocess, sys; sys.exit(subprocess.run('gh auth status', shell=True).returncode)"
    done = subprocess.run([sys.executable, "-c", child], capture_output=True, check=False)
    assert done.returncode != 0


def test_an_unasked_call_from_a_child_powershell():
    # What a verb run through the bridge does: PowerShell finds gh by the PATH.
    shell = shutil.which("pwsh") or shutil.which("powershell")
    done = subprocess.run(
        [shell, "-NoProfile", "-Command", "gh repo list; exit $LASTEXITCODE"], capture_output=True, check=False
    )
    assert done.returncode != 0


@unreachable("gh")
def test_a_marked_call():
    assert _ask_gh_as_the_agent_does() == "unreachable"


@unreachable("az")
def test_a_mark_covers_only_the_tools_it_names():
    assert _ask_gh_as_the_agent_does() == "unreachable"


def test_a_stubbed_call():
    answer = subprocess.CompletedProcess(["gh"], 0, stdout="someone\n", stderr="")
    with mock.patch.object(subprocess, "run", return_value=answer):
        assert _ask_gh_as_the_agent_does() == "answered"
