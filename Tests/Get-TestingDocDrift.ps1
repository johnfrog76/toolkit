<#
.SYNOPSIS
    Holds the per-file pytest counts docs/TESTING.md states to the files they count.
.DESCRIPTION
    docs/TESTING.md's agent row gives each test file a plain "(N)", and a standalone
    `pytest Tests/test_x.py` row may state "N" or "N (+ subtests)". Each is held to the
    file's `def test_` count, one counting rule for both places, from the text and the
    tree alone -- no run, no machine-local file -- so it holds on every machine and in CI.
    A run's totals are not here: they live in docs/TEST-COUNTS.md alone
    (Get-P20TestCountsFile in Scripts/TestAll-Rules.ps1).

    Returns an array of findings (empty when everything agrees); each names the file,
    where the document states it, and the two numbers.
#>
# The one rule for a pytest file's real count: its `def test_` occurrences.
function Get-P20PytestDefCount {
    param([string]$Path)
    return @([regex]::Matches((Get-Content -LiteralPath $Path -Raw -Encoding UTF8), 'def test_')).Count
}

# Every per-file pytest count docs/TESTING.md states, as { File, Stated, Where }:
#   - the agent row's plain "`test_x.py` (N)" / "(N," entries, and
#   - a standalone row "| `pytest Tests/test_x.py` | N |" or "| N (+ subtests) |"
#     (also "python3 -m pytest"). A cell that is "--" or "in the pytest row" states
#     no count and is not read. Jest per-file counts are not read: there is no
#     static source of truth for them short of running jest.
function Get-P20StatedPytestCounts {
    param([string]$Text)
    $claims = @()
    foreach ($line in @($Text -split "\r?\n")) {
        if ($line.StartsWith('| `python3 -m pytest Tests/` |')) {
            foreach ($m in [regex]::Matches($line, '`(test_\w+\.py)` \((\d+)[,)]')) {
                $claims += [pscustomobject]@{ File = $m.Groups[1].Value; Stated = [int]$m.Groups[2].Value; Where = 'the agent row' }
            }
            continue
        }
        $r = [regex]::Match($line, '^\|\s*`(?:python3? -m )?pytest Tests/(test_\w+\.py)`\s*\|\s*(\d+)(?:\s*\(\+ subtests\))?\s*\|')
        if ($r.Success) {
            $claims += [pscustomobject]@{ File = $r.Groups[1].Value; Stated = [int]$r.Groups[2].Value; Where = 'its own row' }
        }
    }
    return $claims
}

# Findings for every stated count that is not the file's real one. $Counts maps a file
# name to its real def test_ count; a name absent from it is a file that does not exist.
function Get-P20PytestCountDrift {
    param([string]$Text, [hashtable]$Counts)
    $findings = @()
    foreach ($c in @(Get-P20StatedPytestCounts -Text $Text)) {
        if (-not $Counts.ContainsKey($c.File)) { $findings += "$($c.File) ($($c.Where)) is not a file in Tests/"; continue }
        if ($Counts[$c.File] -ne $c.Stated) { $findings += "$($c.File) ($($c.Where)): the document says $($c.Stated), the file has $($Counts[$c.File]) def test_" }
    }
    return $findings
}
