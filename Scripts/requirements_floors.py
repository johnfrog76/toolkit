"""Say which installed Python packages are below the agent's requirements files.

``agent/requirements.txt`` and ``agent/requirements-dev.txt`` state floors (``>=``) and one
exact pin (``==``): the versions the agent's suite passes on. CI installs them fresh on every
run; a machine that set its environment up once does not, and falls below them as the floors
move. This reads the two files -- there is no second list of packages -- and compares each
requirement with what is installed for the interpreter running it, which is why it must be run
by the same Python the test runner hands pytest to.

It is a WARNING and never a refusal: it exits 0 whatever it finds, makes no network call, and
installs nothing. Stdlib only (``importlib.metadata``; no ``packaging``, which may be absent),
so it runs wherever the suite would.

    python Scripts/requirements_floors.py            # one line per finding, nothing when all is well
    python Scripts/requirements_floors.py --json     # the same, for a caller (Scripts/Resolve-Python.ps1)
    python Scripts/requirements_floors.py --json path/to/requirements.txt ...

What a version may look like is PEP 440's public form: an epoch, a release number of any
length (``2.7`` equals ``2.7.0``), and an optional pre-, post- or dev-release; a local label
(``+cpu``) is ignored. An installed version that does not parse is reported, not guessed at.
"""

import argparse
import importlib.metadata
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIREMENTS = ("agent/requirements.txt", "agent/requirements-dev.txt")
# The one line that brings an environment up to both files: the dev file includes the runtime one.
FIX_ARGS = "-m pip install -r agent/requirements-dev.txt"

_VERSION = re.compile(
    r"""^\s*v?
    (?:(?P<epoch>\d+)!)?
    (?P<release>\d+(?:\.\d+)*)
    (?:[-_.]?(?P<pre>a|b|c|rc|alpha|beta|pre|preview)[-_.]?(?P<pre_n>\d*))?
    (?:-(?P<post_implicit>\d+)|[-_.]?(?:post|rev|r)[-_.]?(?P<post_n>\d*))?
    (?:[-_.]?dev[-_.]?(?P<dev_n>\d*))?
    (?:\+[a-z0-9.]*)?
    \s*$""",
    re.IGNORECASE | re.VERBOSE,
)
_PRE_RANK = {"a": 0, "alpha": 0, "b": 1, "beta": 1, "c": 2, "rc": 2, "pre": 2, "preview": 2}
_NAME = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(.*)$")
_SPEC = re.compile(r"^\s*(===|~=|==|!=|<=|>=|<|>)\s*(\S+?)\s*$")


def normalise_name(name):
    """PEP 503: case, and any run of ``-``, ``_`` and ``.``, do not tell two names apart."""
    return re.sub(r"[-_.]+", "-", name).lower()


def version_key(text):
    """A sortable key for a PEP 440 version, or None when it does not parse."""
    m = _VERSION.match(text or "")
    if not m:
        return None
    release = [int(p) for p in m.group("release").split(".")]
    while len(release) > 1 and release[-1] == 0:
        release.pop()
    has_pre = m.group("pre") is not None
    has_post = m.group("post_implicit") is not None or m.group("post_n") is not None
    has_dev = m.group("dev_n") is not None
    if has_pre:
        pre = (0, _PRE_RANK[m.group("pre").lower()], int(m.group("pre_n") or 0))
    elif has_dev and not has_post:
        pre = (-1, 0, 0)  # 1.0.dev1 sorts before 1.0a1
    else:
        pre = (1, 0, 0)
    post = (-1,)
    if has_post:
        post = (int(m.group("post_implicit") or m.group("post_n") or 0),)
    dev = (1, 0) if not has_dev else (0, int(m.group("dev_n") or 0))
    return (int(m.group("epoch") or 0), tuple(release), pre, post, dev)


def satisfies(installed, op, wanted):
    """Whether an installed version meets one specifier. None when either side does not parse."""
    if op == "===":
        return installed.strip() == wanted.strip()
    if op in ("==", "!=") and wanted.endswith(".*"):
        have, prefix = version_key(installed), version_key(wanted[:-2])
        if have is None or prefix is None:
            return None
        same = have[0] == prefix[0] and _prefix_matches(have, _release(wanted[:-2]))
        return same if op == "==" else not same
    have, want = version_key(installed), version_key(wanted)
    if have is None or want is None:
        return None
    if op == ">=":
        return have >= want
    if op == ">":
        return have > want
    if op == "<=":
        return have <= want
    if op == "<":
        return have < want
    if op == "==":
        return have == want
    if op == "!=":
        return have != want
    if op == "~=":
        # ~=2.7.1 is >=2.7.1 and ==2.7.*: the release with its last part dropped is a prefix.
        stem = _release(wanted)[:-1] or _release(wanted)
        return have >= want and _prefix_matches(have, stem)
    return None


def _release(text):
    """The release numbers as written (trailing zeros kept), without epoch or suffixes."""
    m = _VERSION.match(text or "")
    return [int(p) for p in m.group("release").split(".")] if m else []


def _prefix_matches(key, stem):
    rel = list(key[1]) + [0] * len(stem)
    return rel[: len(stem)] == stem


def parse_requirement(line):
    """One requirement line as (name, [(op, version), ...]), or None for a line that names none.

    A comment, a blank line and a pip option (``-r``, ``-c``, ``--index-url``) name none. Extras
    (``uvicorn[standard]``), an environment marker (``; python_version < "3.13"``) and a trailing
    comment are taken off; a direct reference (``name @ url``) is a name with no version to check.
    """
    text = line.split(" #", 1)[0].split("\t#", 1)[0]
    if text.lstrip().startswith("#"):
        return None
    text = text.split(";", 1)[0].strip()
    if not text or text.startswith("-"):
        return None
    m = _NAME.match(text)
    if not m:
        return None
    name, rest = m.group(1), m.group(2).strip()
    if rest.startswith("@"):
        return (name, [])
    specs = []
    for part in [p for p in rest.split(",") if p.strip()]:
        s = _SPEC.match(part)
        if s:
            specs.append((s.group(1), s.group(2)))
    return (name, specs)


def read_requirements(paths, root=ROOT):
    """Every requirement in the files, following ``-r``, each file read once.

    Returns [(name, specs, file_label), ...] in file order; file_label is the path as a reader
    would type it (relative to the repository root where it can be).
    """
    out, seen = [], set()

    def label(p):
        try:
            return p.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            return p.name

    def walk(path):
        key = path.resolve()
        if key in seen or not path.is_file():
            return
        seen.add(key)
        for raw in path.read_text(encoding="utf-8").splitlines():
            stripped = raw.strip()
            inc = re.match(r"^(?:-r|--requirement)(?:\s+|=)(\S+)", stripped)
            if inc:
                walk(path.parent / inc.group(1))
                continue
            req = parse_requirement(raw)
            if req:
                out.append((req[0], req[1], label(path)))

    for p in paths:
        walk(Path(p))
    return out


def installed_versions():
    """{normalised name: version} for every distribution this interpreter can import.

    The first one on sys.path wins, as it would for an import.
    """
    found = {}
    for dist in importlib.metadata.distributions():
        name = dist.metadata["Name"] if dist.metadata else None
        if not name:
            continue
        found.setdefault(normalise_name(name), dist.version)
    return found


def _required_text(specs):
    return ",".join(f"{op}{v}" for op, v in specs)


def check(requirements, installed):
    """The findings: one dict per requirement the installed set does not meet.

    Each is {name, installed, required, file, kind, text}; kind is ``missing``, ``below`` (a
    floor not met), ``differs`` (an exact pin not met), ``outside`` (any other specifier not
    met) or ``unreadable`` (an installed version that does not parse). A package named twice is
    reported once, at its first line.
    """
    findings, done = [], set()
    for name, specs, file_label in requirements:
        key = normalise_name(name)
        if key in done:
            continue
        done.add(key)
        required = _required_text(specs)
        have = installed.get(key)
        kind = ""
        if have is None:
            kind = "missing"
        else:
            for op, v in specs:
                ok = satisfies(have, op, v)
                if ok is None:
                    kind = "unreadable"
                    break
                if not ok:
                    kind = {">=": "below", ">": "below", "~=": "below", "==": "differs", "===": "differs"}.get(
                        op, "outside"
                    )
                    break
        if not kind:
            continue
        if kind == "missing":
            text = f"{name} is not installed; {file_label} wants {required or 'it'}"
        elif kind == "unreadable":
            text = f"{name} {have} is a version this check cannot read; {file_label} wants {required}"
        elif kind == "differs":
            text = f"{name} {have} is not the pinned {required} in {file_label}"
        elif kind == "below":
            text = f"{name} {have} is below {required} in {file_label}"
        else:
            text = f"{name} {have} does not meet {required} in {file_label}"
        findings.append(
            {"name": name, "installed": have, "required": required, "file": file_label, "kind": kind, "text": text}
        )
    return findings


def main(argv=None):
    ap = argparse.ArgumentParser(description="Compare installed packages with the agent's requirements files.")
    ap.add_argument("--json", action="store_true", help="print one JSON object for a caller")
    ap.add_argument("files", nargs="*", help="requirements files (default: the agent's two)")
    args = ap.parse_args(argv)
    paths = [Path(f) for f in args.files] or [ROOT / f for f in REQUIREMENTS]
    findings = check(read_requirements(paths), installed_versions())
    if args.json:
        print(json.dumps({"findings": findings, "fix": FIX_ARGS}))
        return 0
    for f in findings:
        print(f["text"])
    if findings:
        print(f"Fix: {Path(sys.executable).name} {FIX_ARGS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
