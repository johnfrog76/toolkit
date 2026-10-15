"""agent/README.md's route tables name every route the app registers.

The tables are the reader's map of the API, so a route added without its row
is a document that describes less than the code does. This reads the rows
(``| `METHOD /path` | ...``) and compares them, as a set, with the app's own
route list: a missing row and a row for a route that is gone both fail, each
naming the route.

Run:  python -m pytest Tests/test_readme_routes.py
"""

import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # Tests/, for _skipguard

from _skipguard import skip_module  # noqa: E402

try:
    from agent import app as app_module
    from agent.core.config import API_PREFIX
except Exception as e:  # pragma: no cover - environment without the deps
    skip_module(f"cannot import the app ({type(e).__name__}: {e})")

README = REPO_ROOT / "agent" / "README.md"
ROW = re.compile(r"^\| `(GET|POST|PUT|PATCH|DELETE) (/[^`]*)` \|")
CONVERTER = re.compile(r"\{(\w+):\w+\}")


def readme_routes() -> set[tuple[str, str]]:
    rows = set()
    text = README.read_text(encoding="utf-8")
    # "Deliberately absent" lists routes the app does not have; stop before it.
    for line in text.split("### Deliberately absent")[0].splitlines():
        m = ROW.match(line)
        if m:
            rows.add((m.group(1), CONVERTER.sub(r"{\1}", m.group(2))))
    return rows


def app_routes() -> set[tuple[str, str]]:
    # fastapi >=0.142 includes routers lazily, so app.routes does not list them;
    # the OpenAPI paths do.
    paths = app_module.create_app(None).openapi()["paths"]
    found = set()
    for path, operations in paths.items():
        for method in operations:
            if method.upper() in ("HEAD", "OPTIONS"):
                continue
            found.add((method.upper(), CONVERTER.sub(r"{\1}", path.removeprefix(API_PREFIX))))
    return found


class ReadmeRouteTables(unittest.TestCase):
    def test_every_route_has_a_row(self):
        have = app_routes()
        self.assertTrue(have, "no routes found in the OpenAPI paths; the check would pass on nothing")
        missing = sorted(have - readme_routes())
        self.assertEqual(missing, [], f"routes with no row in agent/README.md: {missing}")

    def test_every_row_is_a_route(self):
        extra = sorted(readme_routes() - app_routes())
        self.assertEqual(extra, [], f"rows in agent/README.md for routes the app does not register: {extra}")


if __name__ == "__main__":
    unittest.main()
