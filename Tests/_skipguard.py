"""One import guard, shared by every agent test file.

A test file whose dependency is missing must skip **itself** and let the rest of
the session run. A module-level ``sys.exit()`` does not do that: pytest imports
the module during collection, ``SystemExit`` escapes into the collector, and the
whole run ends with an ``INTERNALERROR`` and **zero tests** -- one file taking
the other eight down with it, which is the opposite of what a skip is for. The
same is true of letting the ``ImportError`` fly: pytest reports it as a
collection error and interrupts the run.

Usage, at the top of a test file, around the imports that may not resolve::

    try:
        from fastapi.testclient import TestClient
    except Exception as e:
        from _skipguard import skip_module
        skip_module(f"cannot import the app ({type(e).__name__}: {e})")
"""

import sys


def skip_module(reason):
    """Skip the calling module, whichever runner is driving it.

    Under pytest this is a real module-level skip and the reason shows in the
    short summary. Run directly (``python3 Tests/test_bridge.py``) it prints the
    same ``SKIP:`` line and exits 0, which is what these files have always done.
    """
    if "pytest" in sys.modules:
        import pytest

        pytest.skip(reason, allow_module_level=True)
    print(f"SKIP: {reason}")
    raise SystemExit(0)
