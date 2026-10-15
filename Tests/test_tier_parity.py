#!/usr/bin/env python3
"""
PS<->Python tier parity check (docs/CLI.md, "Tiers: what works without ADO").

Enforces that the tier DECISION is identical in three places for every possible
input combination:

  1. the canonical spec formula (`expected_tier` below -- the source of truth),
  2. Python     -- agent.core.tier._tier_from,
  3. PowerShell -- Scripts/Resolve-TierDecision.ps1.

If any drifts (as Python once did, ignoring status:"local"), this fails and
names the offending combination. Run standalone (`python3 Tests/test_tier_parity.py`)
or under pytest.
"""

import itertools
import os
import subprocess
import sys

PKG_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PS_SCRIPT = os.path.join(PKG_ROOT, "Scripts", "Resolve-TierDecision.ps1")
sys.path.insert(0, PKG_ROOT)
from agent.core import tier as agent_tier  # noqa: E402

STATUSES = ("active", "local", "archive", "inactive", "")
BOOLS = (False, True)


def expected_tier(repo, git, az, ado, status):
    """Canonical tier decision — docs/CLI.md, "Tiers: what works without ADO". The source of truth."""
    if not repo or not git:
        return 3
    if status in ("local", "archive"):
        return 2
    if not az:
        return 2
    return 1 if ado else 2


def ps_tier(repo, git, az, ado, status):
    """Invoke the real PowerShell decision unit."""
    args = ["pwsh", "-NoProfile", "-File", PS_SCRIPT]
    if repo:
        args.append("-RepoFound")
    if git:
        args.append("-GitInstalled")
    if az:
        args.append("-AzAuthenticated")
    if ado:
        args.append("-AdoReachable")
    args += ["-Status", status]
    out = subprocess.run(args, capture_output=True, text=True, timeout=60, check=False)
    if out.returncode != 0:
        raise RuntimeError(f"pwsh failed: {out.stderr.strip()}")
    return int(out.stdout.strip())


def _check_all(include_powershell=True):
    failures = []
    for repo, git, az, ado in itertools.product(BOOLS, BOOLS, BOOLS, BOOLS):
        for status in STATUSES:
            exp = expected_tier(repo, git, az, ado, status)
            py = agent_tier._tier_from(repo, git, az, ado, status)
            row = {
                "repo": repo,
                "git": git,
                "az": az,
                "ado": ado,
                "status": status or "''",
                "expected": exp,
                "python": py,
            }
            if include_powershell:
                ps = ps_tier(repo, git, az, ado, status)
                row["powershell"] = ps
                if not (exp == py == ps):
                    failures.append(row)
            elif exp != py:
                failures.append(row)
    return failures


def test_tier_parity():
    failures = _check_all(include_powershell=True)
    assert not failures, "Tier parity mismatches:\n" + "\n".join(str(f) for f in failures)


def test_python_matches_spec():
    # Fast Python-only check (no pwsh) — always runnable.
    failures = _check_all(include_powershell=False)
    assert not failures, "Python tier drift:\n" + "\n".join(str(f) for f in failures)


if __name__ == "__main__":
    have_pwsh = subprocess.run(["which", "pwsh"], capture_output=True, check=False).returncode == 0
    combos = len(BOOLS) ** 4 * len(STATUSES)
    print(f"Checking {combos} input combinations ({'PS + Python' if have_pwsh else 'Python only — pwsh not found'})...")
    fails = _check_all(include_powershell=have_pwsh)
    if fails:
        print(f"FAIL — {len(fails)} mismatch(es):")
        for f in fails:
            print(" ", f)
        sys.exit(1)
    print(
        f"PASS — all {combos} combinations agree"
        + (" across PowerShell and Python." if have_pwsh else " (Python vs spec).")
    )
