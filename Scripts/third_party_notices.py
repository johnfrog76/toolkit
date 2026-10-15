"""Keep THIRD-PARTY-NOTICES.md true to what the repository holds.

Two jobs, one file:

* The web bundle's dependency list is GENERATED from ``web/package-lock.json`` (every
  package the lockfile does not mark ``dev``, which is what ``license-checker --production``
  reports; the two agree package for package) and written between the ``npm`` markers.
  ``--write`` rewrites that block; ``--check`` fails when the file has drifted from the
  lockfile, and prints the one command that fixes it.
* The fonts, images, audio and other artwork the repository ships are listed BY HAND in the
  page's "Fonts, artwork and audio" section, one backticked path (a file, a folder ending in
  ``/``, or a glob) per entry. ``--check`` walks the tracked files, and fails naming every
  font, image, audio or video file, and every file under ``web/public/``, that no entry covers;
  and every entry that covers nothing.

Stdlib only, Python 3.8 or later, so the check runs wherever the suite does.

    python Scripts/third_party_notices.py --check
    python Scripts/third_party_notices.py --write
"""

import argparse
import fnmatch
import json
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


def split_block(text):
    """(before, inside, after) around the npm markers, or None when they are not both there."""
    if text.count(BEGIN) != 1 or text.count(END) != 1 or text.index(BEGIN) > text.index(END):
        return None
    head, rest = text.split(BEGIN, 1)
    inside, tail = rest.split(END, 1)
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


def requirement_names(text):
    names = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if m and not line.startswith("-"):
            names.append(m.group(1))
    return names


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


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

    pip = section(text, PIP_HEADING)
    if pip is None:
        found.append(f"{NOTICES}: no '{PIP_HEADING}' section")
    else:
        listed = {norm(t) for t in re.findall(r"`([^`\n]+)`", pip)}
        for name in requirement_names(_read(REQUIREMENTS)):
            if norm(name) not in listed:
                found.append(f"{NOTICES}: {REQUIREMENTS} requires {name}, which the agent section does not list")

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


def write():
    path = ROOT / NOTICES
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    parts = split_block(text)
    if parts is None:
        sys.exit(f"{NOTICES}: add the {BEGIN} and {END} markers first")
    block = render_npm_block(production_packages(json.loads(_read(LOCKFILE))))
    text = parts[0] + BEGIN + "\n\n" + block + "\n" + END + parts[2]
    path.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--write", action="store_true", help="regenerate the web dependency list")
    ap.add_argument("--check", action="store_true", help="fail when the notices disagree with the repository")
    args = ap.parse_args(argv)
    if args.write:
        write()
        return 0
    found = problems()
    for line in found:
        print(line)
    if not found:
        print(f"{NOTICES}: true to the lockfile, the requirements and the tracked artwork")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
