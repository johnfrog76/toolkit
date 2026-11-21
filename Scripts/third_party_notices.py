"""Keep THIRD-PARTY-NOTICES.md true to what the repository holds.

Two jobs, one file:

* The web bundle's dependency list is GENERATED from ``web/package-lock.json`` (every
  package the lockfile does not mark ``dev``, which is what ``license-checker --production``
  reports; the two agree package for package) and written between the ``npm`` markers.
  ``--write`` rewrites that block; ``--check`` fails when the file has drifted from the
  lockfile, and prints the one command that fixes it.
* The agent's runtime dependency list is GENERATED from the packages installed for
  ``agent/requirements.txt``: ``--write-agent`` walks each requirement's ``Requires-Dist``
  (honouring environment markers and the extras asked for) through ``importlib.metadata``, and
  writes every package it reaches, with its version and license, between the ``pip`` markers,
  stating the Python version, the platform and the date it resolved on. ``--check`` needs no
  packages: it fails when a package the requirements name is missing from that list, or is listed
  at a version below the requirement's floor.
* The fonts, images, audio and other artwork the repository ships are listed BY HAND in the
  page's "Fonts, artwork and audio" section, one backticked path (a file, a folder ending in
  ``/``, or a glob) per entry. ``--check`` walks the tracked files, and fails naming every
  font, image, audio or video file, and every file under ``web/public/``, that no entry covers;
  and every entry that covers nothing.

Stdlib only, Python 3.8 or later, so the check runs wherever the suite does, with no network
call. Only ``--write-agent`` needs anything installed: the agent's requirements, in the
environment of the interpreter that runs it.

    python Scripts/third_party_notices.py --check
    python Scripts/third_party_notices.py --write
    python Scripts/third_party_notices.py --write-agent
"""

import argparse
import datetime
import fnmatch
import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTICES = "THIRD-PARTY-NOTICES.md"
LOCKFILE = "web/package-lock.json"
REQUIREMENTS = "agent/requirements.txt"

BEGIN = "<!-- notices:npm begin -->"
END = "<!-- notices:npm end -->"
PIP_BEGIN = "<!-- notices:pip begin -->"
PIP_END = "<!-- notices:pip end -->"
WRITE_AGENT = "pip install -r agent/requirements.txt, then python Scripts/third_party_notices.py --write-agent"
ASSETS_HEADING = "## Fonts, artwork and audio"
PIP_HEADING = "## Agent (`agent/`), runtime dependencies"

# What counts as a font, a picture or a sound. A file with one of these extensions that
# is tracked by git must be covered by an entry in the assets section; so must anything
# under web/public/, which is served as-is whatever it is called.
FONT_EXT = {".woff", ".woff2", ".ttf", ".otf", ".eot", ".ttc"}
ART_EXT = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".avif", ".bmp", ".icns",
    ".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac", ".mp4", ".webm", ".mov",
}  # fmt: skip
SERVED_DIRS = ("web/public/",)


def _read(rel):
    # A checkout with core.autocrlf hands the page over with CRLF; the comparison is on LF.
    return (ROOT / rel).read_bytes().decode("utf-8").replace("\r\n", "\n")


def production_packages(lock):
    """[(name, version, license)] for every non-dev package, sorted by name then version."""
    rows = []
    for key, entry in lock["packages"].items():
        if not key or entry.get("dev"):
            continue
        name = key.rsplit("node_modules/", 1)[-1]
        rows.append((name, entry["version"], entry.get("license") or "UNKNOWN"))
    return sorted(rows)


def render_npm_block(rows):
    """The text between the markers, LF-terminated, ending without a blank line."""
    groups = {}
    for name, version, lic in rows:
        groups.setdefault(lic, []).append((name, version))
    order = sorted(groups, key=lambda lic: (-len(groups[lic]), lic))
    out = [
        (
            f"What ships in the browser bundle: {len(rows)} packages, besides the web package itself "
            "(`toolkit-web`, MIT). Every one is under a permissive license."
        ),
        "",
        "| License | Packages |",
        "| --- | --- |",
    ]
    out += [f"| {lic} | {len(groups[lic])} |" for lic in order]
    for lic in order:
        out += ["", f"#### {lic} ({len(groups[lic])})", "", "| Package | Version |", "| --- | --- |"]
        out += [f"| `{name}` | {version} |" for name, version in groups[lic]]
    return "\n".join(out) + "\n"


def split_block(text, begin=BEGIN, end=END):
    """(before, inside, after) around a pair of markers, or None when they are not both there."""
    if text.count(begin) != 1 or text.count(end) != 1 or text.index(begin) > text.index(end):
        return None
    head, rest = text.split(begin, 1)
    inside, tail = rest.split(end, 1)
    return head, inside, tail


def section(text, heading):
    """The body under a '## ' heading, up to the next one."""
    m = re.search(r"^" + re.escape(heading) + r"\s*$", text, re.MULTILINE)
    if not m:
        return None
    nxt = re.search(r"^## ", text[m.end() :], re.MULTILINE)
    return text[m.end() : m.end() + nxt.start()] if nxt else text[m.end() :]


def tracked_files():
    """Tracked paths, forward-slashed. Falls back to a walk when git is not there."""
    try:
        out = subprocess.run(
            ["git", "ls-files"], cwd=str(ROOT), capture_output=True, check=True, timeout=60
        ).stdout.decode("utf-8", "replace")
        files = [p for p in out.splitlines() if p]
        if files:
            return files
    except (OSError, subprocess.SubprocessError):
        pass
    skip = {"node_modules", ".git", ".venv", "dist", "__pycache__"}
    return [
        p.relative_to(ROOT).as_posix()
        for p in ROOT.rglob("*")
        if p.is_file() and not (skip & set(p.relative_to(ROOT).parts))
    ]


def artwork_files(files):
    """The tracked files the assets section has to account for."""
    keep = []
    for rel in files:
        ext = Path(rel).suffix.lower()
        if ext in FONT_EXT or ext in ART_EXT or rel.startswith(SERVED_DIRS):
            keep.append(rel)
    return sorted(keep)


def entries(assets_body):
    """The path-like tokens in the FIRST column of the assets section's tables: a '/' or '*' in them."""
    seen = []
    for line in assets_body.splitlines():
        if not line.startswith("|"):
            continue
        first = line.split("|")[1] if line.count("|") > 1 else ""
        for tok in re.findall(r"`([^`]+)`", first):
            if "/" in tok or "*" in tok:
                seen.append(tok)
    return seen


def covers(entry, rel):
    if entry.endswith("/"):
        return rel.startswith(entry)
    if "*" in entry or "?" in entry:
        return fnmatch.fnmatchcase(rel, entry)
    return rel == entry


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


# -- Requirements, versions and markers, without the packaging library -------------------------

_REQ = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\s*"
    r"(?:\[(?P<extras>[^\]]*)\])?\s*"
    r"(?:\((?P<pspec>[^)]*)\)|(?P<spec>[^;]*))?"
    r"(?:;(?P<marker>.*))?$"
)


def parse_requirement(line):
    """(name, extras, [(op, version)], marker) for one requirement line, or None for a line that
    names nothing: a blank, a comment, or an option such as ``-r other.txt``. The extras are a set
    of normalised names; the marker is its text, or "" when there is none."""
    line = re.split(r"(?:^|\s)#", line, maxsplit=1)[0].strip()
    if not line or line.startswith("-"):
        return None
    m = _REQ.match(line)
    if not m:
        return None
    extras = {norm(e.strip()) for e in (m.group("extras") or "").split(",") if e.strip()}
    spec = m.group("pspec") if m.group("pspec") is not None else (m.group("spec") or "")
    specs = []
    for clause in spec.split(","):
        c = re.match(r"\s*(===|==|!=|<=|>=|~=|<|>)\s*(\S+)\s*$", clause)
        if c:
            specs.append((c.group(1), c.group(2)))
    return m.group("name"), extras, specs, (m.group("marker") or "").strip()


def requirements(text):
    """Every requirement the text names, parsed, in file order."""
    return [r for r in (parse_requirement(line) for line in text.splitlines()) if r]


def requirement_names(text):
    return [r[0] for r in requirements(text)]


def floor(specs):
    """The lowest version a requirement allows, from its >=, ==, === or ~= clause, or None."""
    for op, version in specs:
        if op in (">=", "==", "===", "~="):
            return version.rstrip(".*")
    return None


_VERSION = re.compile(
    r"^\s*v?(?:(?P<epoch>\d+)!)?(?P<release>\d+(?:\.\d+)*)"
    r"(?:[-_.]?(?P<pre>a|b|c|rc|alpha|beta|pre|preview)[-_.]?(?P<pren>\d*))?"
    r"(?:-(?P<postn1>\d+)|[-_.]?(?P<post>post|rev|r)[-_.]?(?P<postn2>\d*))?"
    r"(?:[-_.]?(?P<dev>dev)[-_.]?(?P<devn>\d*))?"
    r"(?:\+[a-z0-9.]*)?\s*$",
    re.IGNORECASE,
)
_PRE = {"a": 0, "alpha": 0, "b": 1, "beta": 1, "c": 2, "rc": 2, "pre": 2, "preview": 2}


def version_key(text):
    """A sortable key for a PEP 440 version, or None when the text is not one. Orders
    X.devN < X.aN < X.bN < X.rcN < X < X.postN, and 2.0 equals 2.0.0."""
    m = _VERSION.match(text or "")
    if not m:
        return None
    release = [int(p) for p in m.group("release").split(".")]
    while len(release) > 1 and release[-1] == 0:
        release.pop()
    post = m.group("postn1") or (m.group("postn2") or "0" if m.group("post") else None)
    dev = m.group("devn") or "0" if m.group("dev") else None
    if m.group("pre"):
        pre = (0, _PRE[m.group("pre").lower()], int(m.group("pren") or 0))
    elif dev is not None and post is None:
        pre = (-1,)
    else:
        pre = (1,)
    return (
        int(m.group("epoch") or 0),
        tuple(release),
        pre,
        (-1,) if post is None else (int(post),),
        (1, 0) if dev is None else (0, int(dev)),
    )


def marker_environment(extra=""):
    """The PEP 508 marker variables for the interpreter running this script."""
    impl = sys.implementation
    iv = impl.version
    impl_version = f"{iv.major}.{iv.minor}.{iv.micro}"
    if iv.releaselevel != "final":
        impl_version += iv.releaselevel[0] + str(iv.serial)
    return {
        "os_name": os.name,
        "sys_platform": sys.platform,
        "platform_machine": platform.machine(),
        "platform_python_implementation": platform.python_implementation(),
        "platform_release": platform.release(),
        "platform_system": platform.system(),
        "platform_version": platform.version(),
        "python_version": ".".join(platform.python_version_tuple()[:2]),
        "python_full_version": platform.python_version(),
        "implementation_name": impl.name,
        "implementation_version": impl_version,
        "extra": extra,
    }


_MARKER_TOKEN = re.compile(
    r"\s*(?:(?P<str>'[^']*'|\"[^\"]*\")|(?P<op>===|==|!=|<=|>=|~=|<|>)|(?P<paren>[()])"
    r"|(?P<word>[A-Za-z_][A-Za-z0-9_.]*))"
)
_VERSION_VARS = {"python_version", "python_full_version", "implementation_version"}


def _compare(lhs, op, rhs, versioned):
    if op == "in":
        return lhs in rhs
    if op == "not in":
        return lhs not in rhs
    a, b = (version_key(lhs), version_key(rhs)) if versioned else (None, None)
    if a is None or b is None:
        if op in ("==", "==="):
            return lhs == rhs
        if op == "!=":
            return lhs != rhs
        raise ValueError(f"cannot compare {lhs!r} {op} {rhs!r}")
    if op == "~=":
        prefix = [int(p) for p in re.match(r"\d+(?:\.\d+)*", rhs).group(0).split(".")][:-1]
        here = [int(p) for p in re.match(r"\d+(?:\.\d+)*", lhs).group(0).split(".")]
        return a >= b and here[: len(prefix)] == prefix
    return {"==": a == b, "===": lhs == rhs, "!=": a != b, "<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b}[op]


def marker_holds(marker, env):
    """Whether a PEP 508 environment marker is true in ``env``. An empty marker holds."""
    if not marker.strip():
        return True
    tokens, pos = [], 0
    while pos < len(marker):
        if marker[pos:].strip() == "":
            break
        m = _MARKER_TOKEN.match(marker, pos)
        if not m:
            raise ValueError(f"cannot read the marker {marker!r}")
        pos = m.end()
        kind = m.lastgroup
        tokens.append((kind, m.group(kind)))
    at = [0]

    def peek():
        return tokens[at[0]] if at[0] < len(tokens) else (None, None)

    def take():
        tok = peek()
        at[0] += 1
        return tok

    def value():
        kind, text = take()
        if kind == "str":
            return text[1:-1], False
        if kind == "word" and text in env:
            return env[text], text
        raise ValueError(f"cannot read the marker {marker!r}")

    def atom():
        if peek() == ("paren", "("):
            take()
            out = either()
            if take() != ("paren", ")"):
                raise ValueError(f"cannot read the marker {marker!r}")
            return out
        lhs, lvar = value()
        kind, op = take()
        if kind == "word" and op == "not" and peek() == ("word", "in"):
            take()
            op = "not in"
        elif not (kind == "op" or (kind == "word" and op == "in")):
            raise ValueError(f"cannot read the marker {marker!r}")
        rhs, rvar = value()
        if "extra" in (lvar, rvar):
            lhs, rhs = norm(lhs), norm(rhs)
        return _compare(lhs, op, rhs, bool({lvar, rvar} & _VERSION_VARS))

    def both():
        out = atom()
        while peek() == ("word", "and"):
            take()
            out = atom() and out
        return out

    def either():
        out = both()
        while peek() == ("word", "or"):
            take()
            out = both() or out
        return out

    result = either()
    if at[0] != len(tokens):
        raise ValueError(f"cannot read the marker {marker!r}")
    return result


# -- The agent section ---------------------------------------------------------------------------

_PIP_ROW = re.compile(r"^\|\s*(?P<lic>[^|]+?)\s*\|\s*`(?P<name>[^`]+)`\s*\|\s*(?P<version>[^|\s]+)\s*\|\s*$")


def listed_agent_packages(block):
    """{normalised name: (name, version)} for every row of the agent section's table."""
    rows = {}
    for line in block.splitlines():
        m = _PIP_ROW.match(line.strip())
        if m:
            rows[norm(m.group("name"))] = (m.group("name"), m.group("version"))
    return rows


def agent_problems(block, requirements_text):
    """Every way the agent section disagrees with the requirements, as sentences."""
    found = []
    listed = listed_agent_packages(block)
    for name, _extras, specs, _marker in requirements(requirements_text):
        row = listed.get(norm(name))
        if row is None:
            found.append(
                f"{NOTICES}: {REQUIREMENTS} requires {name}, which the agent section does not list ({WRITE_AGENT})"
            )
            continue
        low = floor(specs)
        if low is None:
            continue
        have, want = version_key(row[1]), version_key(low)
        if have is None or want is None:
            found.append(
                f"{NOTICES}: the agent section lists {row[0]} {row[1]}, which cannot be compared "
                f"with the floor {low} in {REQUIREMENTS} ({WRITE_AGENT})"
            )
        elif have < want:
            found.append(
                f"{NOTICES}: the agent section lists {row[0]} {row[1]}, below the floor {name}>={low} "
                f"in {REQUIREMENTS} ({WRITE_AGENT})"
            )
    return found


# The few license classifiers the agent's packages use, as SPDX identifiers. A classifier outside
# this table stops --write-agent by name rather than being guessed at.
CLASSIFIERS = {
    "License :: OSI Approved :: MIT License": "MIT",
    "License :: OSI Approved :: Apache Software License": "Apache-2.0",
    "License :: OSI Approved :: ISC License (ISCL)": "ISC",
    "License :: OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0",
    "License :: OSI Approved :: Python Software Foundation License": "PSF-2.0",
}
_SPDX_ID = re.compile(r"^(?:[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*\+?|AND|OR|WITH|\(|\))$")
_SPDX_WORDS = {"MIT", "ISC", "0BSD", "Unlicense", "Zlib", "BSD", "PSF", "MPL", "Apache"}


def _spdx_shaped(text):
    """Whether a License field reads as an SPDX expression ("MIT", "MIT OR Apache-2.0") rather
    than prose ("MIT License") or a whole license text."""
    words = text.replace("(", " ( ").replace(")", " ) ").split()
    if not words or len(text) > 100:
        return False
    for w in words:
        if not _SPDX_ID.match(w):
            return False
        if w not in ("AND", "OR", "WITH", "(", ")") and not (re.search(r"\d", w) or w in _SPDX_WORDS):
            return False
    return True


def package_license(meta):
    """The license one installed distribution declares: its License-Expression, else a License
    field that is an SPDX expression, else its license classifiers (joined with OR when there are
    several). Raises when none of the three can be read."""
    expr = (meta.get("License-Expression") or "").strip()
    if expr:
        return expr
    field = (meta.get("License") or "").strip()
    if _spdx_shaped(field):
        return field
    classifiers = [c for c in (meta.get_all("Classifier") or []) if c.startswith("License ::")]
    unknown = [c for c in classifiers if c not in CLASSIFIERS]
    if classifiers and not unknown:
        return " OR ".join(sorted({CLASSIFIERS[c] for c in classifiers}, key=lambda lic: (lic != "MIT", lic)))
    raise LookupError(
        f"{meta.get('Name')}: no License-Expression, no SPDX License field and "
        + (f"an unknown classifier {unknown[0]!r}" if unknown else "no license classifier")
        + "; read its license by hand and add the classifier to CLASSIFIERS"
    )


def resolve_agent_packages(requirements_text, distribution, env=None):
    """[(name, version, license)] for every package the requirements reach, sorted.

    ``distribution`` is ``importlib.metadata.distribution`` (or a stand-in): it is asked for each
    package by name, and the walk follows its ``Requires-Dist`` lines whose markers hold here, with
    the extras each requirement asks for. Raises LookupError naming a package that is not
    installed, or is installed below its floor."""
    env = env or marker_environment()
    seen, found, queue = set(), {}, []
    for req in requirements(requirements_text):
        if marker_holds(req[3], env):
            queue.append((req, REQUIREMENTS))
    while queue:
        (name, extras, specs, _marker), wanted_by = queue.pop(0)
        try:
            dist = distribution(name)
        except Exception as exc:  # importlib.metadata.PackageNotFoundError, or a stand-in's
            raise LookupError(f"{name} (required by {wanted_by}) is not installed: {WRITE_AGENT}") from exc
        meta = dist.metadata
        low = floor(specs)
        if wanted_by == REQUIREMENTS and low and version_key(dist.version) < version_key(low):
            raise LookupError(f"{name} {dist.version} is installed, below the floor {low}: {WRITE_AGENT}")
        key = norm(meta["Name"])
        if key not in found:
            found[key] = (meta["Name"], dist.version, package_license(meta))
        # The package's own dependencies (no extra), then each extra the requirement asked for.
        for extra in [""] + sorted(extras):
            if (key, extra) in seen:
                continue
            seen.add((key, extra))
            for line in meta.get_all("Requires-Dist") or []:
                dep = parse_requirement(line)
                if dep and marker_holds(dep[3], dict(env, extra=extra)):
                    queue.append((dep, meta["Name"]))
    return sorted(found.values(), key=lambda r: (norm(r[0]), r[1]))


def render_pip_block(rows, python, system, date):
    """The text between the pip markers, LF-terminated, ending without a blank line."""
    groups = {}
    for name, version, lic in rows:
        groups.setdefault(lic, []).append((name, version))
    order = sorted(groups, key=lambda lic: (-len(groups[lic]), lic))
    out = [
        (
            f"From `{REQUIREMENTS}`, with the packages they pull in: {len(rows)} packages, as resolved from "
            f"the installed packages on Python {python} ({system}) on {date}. The requirements are lower "
            "bounds, so a later install may resolve newer versions, and a package behind a platform marker "
            "is listed as it resolved on that platform."
        ),
        "",
        "| License | Package | Version |",
        "| --- | --- | --- |",
    ]
    for lic in order:
        out += [f"| {lic} | `{name}` | {version} |" for name, version in groups[lic]]
    return "\n".join(out) + "\n"


def problems():
    """Every way the notices disagree with the repository, as sentences. Empty means true."""
    text = _read(NOTICES)
    found = []

    parts = split_block(text)
    if parts is None:
        found.append(f"{NOTICES}: the {BEGIN} ... {END} markers are missing or out of order")
    else:
        want = render_npm_block(production_packages(json.loads(_read(LOCKFILE))))
        if parts[1].strip("\n") != want.strip("\n"):
            found.append(
                f"{NOTICES}: the web dependency list has drifted from {LOCKFILE} "
                "(python Scripts/third_party_notices.py --write)"
            )

    pip = split_block(text, PIP_BEGIN, PIP_END)
    if section(text, PIP_HEADING) is None:
        found.append(f"{NOTICES}: no '{PIP_HEADING}' section")
    elif pip is None:
        found.append(f"{NOTICES}: the {PIP_BEGIN} ... {PIP_END} markers are missing or out of order")
    else:
        found += agent_problems(pip[1], _read(REQUIREMENTS))

    body = section(text, ASSETS_HEADING)
    if body is None:
        found.append(f"{NOTICES}: no '{ASSETS_HEADING}' section")
        return found
    files = tracked_files()
    listed = entries(body)
    for rel in artwork_files(files):
        if not any(covers(e, rel) for e in listed):
            found.append(f"{NOTICES}: {rel} is a font, picture or sound the page does not account for")
    for entry in listed:
        if not any(covers(entry, rel) for rel in files):
            found.append(f"{NOTICES}: '{entry}' names nothing in the repository")
    return found


def _write_block(begin, end, block):
    path = ROOT / NOTICES
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    parts = split_block(text, begin, end)
    if parts is None:
        sys.exit(f"{NOTICES}: add the {begin} and {end} markers first")
    text = parts[0] + begin + "\n\n" + block + "\n" + end + parts[2]
    path.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))


def write():
    _write_block(BEGIN, END, render_npm_block(production_packages(json.loads(_read(LOCKFILE)))))


def write_agent():
    from importlib.metadata import distribution

    try:
        rows = resolve_agent_packages(_read(REQUIREMENTS), distribution)
    except (LookupError, ValueError) as exc:
        sys.exit(f"{NOTICES}: {exc}")
    system = {"Darwin": "macOS"}.get(platform.system(), platform.system())
    block = render_pip_block(rows, platform.python_version(), system, datetime.date.today().isoformat())
    _write_block(PIP_BEGIN, PIP_END, block)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--write", action="store_true", help="regenerate the web dependency list")
    ap.add_argument(
        "--write-agent",
        action="store_true",
        help="regenerate the agent's dependency list from the packages installed for agent/requirements.txt",
    )
    ap.add_argument("--check", action="store_true", help="fail when the notices disagree with the repository")
    args = ap.parse_args(argv)
    if args.write or args.write_agent:
        if args.write:
            write()
        if args.write_agent:
            write_agent()
        return 0
    found = problems()
    for line in found:
        print(line)
    if not found:
        print(f"{NOTICES}: true to the lockfile, the requirements and the tracked artwork")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
