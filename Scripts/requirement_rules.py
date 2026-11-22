"""One reading of a requirement line, a package name and a version, for the two Python checks.

``Scripts/requirements_floors.py`` (installed packages against the agent's requirements files)
and ``Scripts/third_party_notices.py`` (the notices page's agent section against
``agent/requirements.txt``) both read requirement lines and compare versions. They read them
here, so the two can never disagree about whether a package is below its floor. What is each
script's own stays there: following ``-r`` includes and reading what is installed in one,
walking dependencies, markers and licenses in the other.

Stdlib only, Python 3.8 or later, and no import of either script, so both checks keep running
with no packages installed. ``Tests/fixtures/requirements/table.json`` is the one table these
three answers are held to (``Tests/test_requirement_rules.py``).

* ``normalise_name`` -- PEP 503: case, and any run of ``-``, ``_`` and ``.``, do not tell two
  names apart.
* ``parse_requirement`` -- one PEP 508 line (a requirements file's, or a ``Requires-Dist``
  header's) as (name, extras, specifiers, marker).
* ``version_key`` -- a sortable key for a PEP 440 version: an epoch, a release of any length
  (``2.7`` equals ``2.7.0``), an optional pre-, post- or dev-release; a local label (``+cpu``)
  is ignored. None for text that is not a version, which a caller reports rather than guesses at.
  ``release`` is the release numbers as written, for a prefix match (``==2.7.*``, ``~=2.7.1``).
"""

import re

_REQ = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\s*"
    r"(?:\[(?P<extras>[^\]]*)\])?\s*"
    r"(?:\((?P<pspec>[^)]*)\)|(?P<spec>[^;]*))?"
    r"(?:;(?P<marker>.*))?$"
)
_CLAUSE = re.compile(r"\s*(===|==|!=|<=|>=|~=|<|>)\s*(\S+)\s*$")

_VERSION = re.compile(
    r"^\s*v?(?:(?P<epoch>\d+)!)?(?P<release>\d+(?:\.\d+)*)"
    r"(?:[-_.]?(?P<pre>a|b|c|rc|alpha|beta|pre|preview)[-_.]?(?P<pren>\d*))?"
    r"(?:-(?P<postn1>\d+)|[-_.]?(?P<post>post|rev|r)[-_.]?(?P<postn2>\d*))?"
    r"(?:[-_.]?(?P<dev>dev)[-_.]?(?P<devn>\d*))?"
    r"(?:\+[a-z0-9.]*)?\s*$",
    re.IGNORECASE,
)
_PRE = {"a": 0, "alpha": 0, "b": 1, "beta": 1, "c": 2, "rc": 2, "pre": 2, "preview": 2}


def normalise_name(name):
    """PEP 503: case, and any run of ``-``, ``_`` and ``.``, do not tell two names apart."""
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_requirement(line):
    """(name, extras, [(op, version)], marker) for one requirement line, or None for a line that
    names nothing: a blank, a comment, or a pip option such as ``-r other.txt``.

    The extras are a set of normalised names; the marker is its text, or "" when there is none;
    a trailing comment is taken off. A specifier may be bare (``x>=1.2``) or in parentheses
    (``x (>=1.2)``, as older ``Requires-Dist`` headers write it). A direct reference
    (``name @ url``) is a name with no specifier."""
    line = re.split(r"(?:^|\s)#", line, maxsplit=1)[0].strip()
    if not line or line.startswith("-"):
        return None
    m = _REQ.match(line)
    if not m:
        return None
    extras = {normalise_name(e.strip()) for e in (m.group("extras") or "").split(",") if e.strip()}
    spec = m.group("pspec") if m.group("pspec") is not None else (m.group("spec") or "")
    specs = []
    for clause in spec.split(","):
        c = _CLAUSE.match(clause)
        if c:
            specs.append((c.group(1), c.group(2)))
    return m.group("name"), extras, specs, (m.group("marker") or "").strip()


def version_key(text):
    """A sortable key for a PEP 440 version, or None when the text is not one. Orders
    X.devN < X.aN < X.bN < X.rcN < X < X.postN, and 2.0 equals 2.0.0.

    The key is (epoch, release, pre, post, dev), the release with its trailing zeros taken off."""
    m = _VERSION.match(text or "")
    if not m:
        return None
    rel = [int(p) for p in m.group("release").split(".")]
    while len(rel) > 1 and rel[-1] == 0:
        rel.pop()
    post = m.group("postn1") or (m.group("postn2") or "0" if m.group("post") else None)
    dev = m.group("devn") or "0" if m.group("dev") else None
    if m.group("pre"):
        pre = (0, _PRE[m.group("pre").lower()], int(m.group("pren") or 0))
    elif dev is not None and post is None:
        pre = (-1,)  # 1.0.dev1 sorts before 1.0a1
    else:
        pre = (1,)
    return (
        int(m.group("epoch") or 0),
        tuple(rel),
        pre,
        (-1,) if post is None else (int(post),),
        (1, 0) if dev is None else (0, int(dev)),
    )


def release(text):
    """The release numbers as written (trailing zeros kept), without epoch or suffixes; [] when
    the text is not a version."""
    m = _VERSION.match(text or "")
    return [int(p) for p in m.group("release").split(".")] if m else []
