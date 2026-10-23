<#
.SYNOPSIS
    The documented CLI suite count agrees with the real one, and with itself.
.DESCRIPTION
    AGENTS.md, docs/TESTING.md and VERIFY.md each record "N suites, M
    assertions on this commit". Nothing checked them, so a commit that added a
    suite (or removed one) left the three sentences saying a number the runner
    no longer produces -- found only by a cold start.

    This suite closes the SUITE-COUNT half of that gap: it reads the three
    sentences back with a regex anchored to each file's own wording, and
    checks all three agree with each other and with
    Get-ToolkitSuiteRegistry.ps1's real count -- the same table
    Test-Toolkit.ps1 runs. Deliberately NOT the ASSERTION count: that number
    moves with a machine's config.local.json (an extra nav alias adds rows to
    Menu's own coverage; a local org adds Autoload's), which is legitimate
    variance this suite would otherwise have to model exactly to avoid being
    wrong on someone else's machine. The suite count has no such variance --
    it is exactly the registry's size, on any host. The assertion counts are
    printed instead: a full run of Test-Toolkit.ps1 ends with the combined
    per-suite line and the total, ready to paste, and this suite holds
    the SHAPE they are pasted into -- docs/TESTING.md's combined row names every
    registry suite once in the runner's order, and no single-suite row carries
    a count of its own to go stale beside it.

    It also holds the root README to its job as the front door: at most
    120 lines, no build-history phrases, every relative link resolving, and the
    known gaps one link down in docs/KNOWN-GAPS.md.

    Run:  pwsh -File Tests/Test-DocCounts.ps1
    Or:   {cliPrefix}TestToolkit -DocCounts
#>
[CmdletBinding()]
param()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    Assert-True $TestName ("$Expected" -eq "$Actual") "expected '$Expected', got '$Actual'"
}

Write-Host ""
Write-Host "  DocCounts -- the documented suite count agrees with the real one" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- The real count --------------------------------------------------------------
. (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1')
$realCount = (Get-P20ToolkitSuiteRegistry).Count
Write-Host "  Registry:  $realCount suites (Get-ToolkitSuiteRegistry.ps1)" -ForegroundColor DarkGray

# -- Each document's own sentence, read back with an anchor unique to it --------
# A file whose wording changes has to change the anchor here too -- that is the
# point: a silent rewording is a silent way to stop being checked.
function Get-DocSuiteCount {
    param([string]$Path, [string]$Pattern, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Assert-True "$Label exists" $false "not found: $Path"
        return $null
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $m = [regex]::Match($text, $Pattern)
    Assert-True "$Label states its CLI suite count in the expected shape" $m.Success `
        "pattern not found in $Path -- has the sentence been reworded?"
    if (-not $m.Success) { return $null }
    return [int]$m.Groups[1].Value
}

$agentsPath = Join-Path $pkgRoot 'AGENTS.md'
$testingPath = Join-Path $pkgRoot 'docs/TESTING.md'
$verifyPath = Join-Path $pkgRoot 'VERIFY.md'

$agentsCount = Get-DocSuiteCount -Path $agentsPath -Label 'AGENTS.md' `
    -Pattern 'tkTestToolkit\s+#\s*the CLI -- (\d+) suites,'
$testingCount = Get-DocSuiteCount -Path $testingPath -Label 'docs/TESTING.md' `
    -Pattern 'tkTestToolkit\s+#\s*(\d+) suites,'
$verifyCount = Get-DocSuiteCount -Path $verifyPath -Label 'VERIFY.md' `
    -Pattern 'is \*\*(\d+) suites,'

if ($null -ne $agentsCount) { Write-Host "  AGENTS.md:       $agentsCount suites" -ForegroundColor DarkGray }
if ($null -ne $testingCount) { Write-Host "  docs/TESTING.md: $testingCount suites" -ForegroundColor DarkGray }
if ($null -ne $verifyCount) { Write-Host "  VERIFY.md:       $verifyCount suites" -ForegroundColor DarkGray }
Write-Host ""

# -- Agreement --------------------------------------------------------------------
if ($null -ne $agentsCount) {
    Assert-Equal 'AGENTS.md matches the real suite count' $realCount $agentsCount
}
if ($null -ne $testingCount) {
    Assert-Equal 'docs/TESTING.md matches the real suite count' $realCount $testingCount
}
if ($null -ne $verifyCount) {
    Assert-Equal 'VERIFY.md matches the real suite count' $realCount $verifyCount
}

# -- Per-suite counts live in ONE row -----------------------------------------
# docs/TESTING.md prints the CLI's per-suite counts once, in the `tkTestToolkit`
# row, and a full run of the runner prints that row ready to paste. A count typed
# into a single suite's own row is a half-measure: nothing reads it
# back, so it goes stale while the combined row beside it is refreshed.
Write-Host ""
Write-Host "  Per-suite counts live in one row" -ForegroundColor Cyan
$testingText = ''
if (Test-Path -LiteralPath $testingPath) { $testingText = Get-Content -LiteralPath $testingPath -Raw -Encoding UTF8 }
$testingRows = @($testingText -split "\r?\n")

$combinedRow = @($testingRows | Where-Object { $_ -match '^\|\s*`tkTestToolkit`\s*\|' })
Assert-True 'docs/TESTING.md has one combined `tkTestToolkit` row' ($combinedRow.Count -eq 1) "$($combinedRow.Count) rows"
if ($combinedRow.Count -eq 1) {
    # The names in the row, in order, are the registry's -- the same line the
    # runner prints, so a paste lands in the shape this reads.
    $named = @([regex]::Matches($combinedRow[0], '(?<=[\s,.])([A-Z][A-Za-z]+) \d+(?=[,.])') | ForEach-Object { $_.Groups[1].Value })
    $registryNames = @((Get-P20ToolkitSuiteRegistry).Keys)
    Assert-Equal 'the combined row names every registry suite once, in the runner''s order' ($registryNames -join ', ') ($named -join ', ')
}


# The paste block under "The counts, after a merge" is what a full run prints:
# the per-suite line and the total line. It went stale once -- a deleted suite
# still listed, a total that was no one's sum -- because nothing read it. Read it
# back against the registry: the same suite count, the same names in the same
# order, and a total that is the sum of its own lines. Deliberately not against a
# live run: assertion counts move with a machine's config.local.json (see above).
$pasteHead = [regex]::Match($testingText, '(?s)\*\*The counts, after a merge\.\*\*.*?```text\r?\n(.*?)\r?\n```')
Assert-True 'docs/TESTING.md has the paste block under "The counts, after a merge"' $pasteHead.Success 'fenced block not found -- has the heading been reworded?'
if ($pasteHead.Success) {
    $pasteLines = @($pasteHead.Groups[1].Value -split "\r?\n" | Where-Object { $_.Trim() })
    $pasteNames = @()
    $pasteSum = 0
    $pasteTotal = $null
    foreach ($pl in $pasteLines) {
        $tm = [regex]::Match($pl, '^\s*(\d+) suites, (\d+) assertions\s*$')
        if ($tm.Success) { $pasteTotal = $tm; continue }
        $parts = @([regex]::Matches($pl, '(?<=^\s*|,\s)([A-Z][A-Za-z]+) (\d+)(?=,|\s*$)'))
        if ($parts.Count -gt 0) {
            foreach ($pm in $parts) { $pasteNames += $pm.Groups[1].Value; $pasteSum += [int]$pm.Groups[2].Value }
        }
    }
    Assert-Equal 'the paste block lists as many suites as the registry has' $realCount $pasteNames.Count
    Assert-Equal 'the paste block names every registry suite once, in the runner''s order' ($registryNames -join ', ') ($pasteNames -join ', ')
    Assert-True 'the paste block ends with its "N suites, M assertions" line' ($null -ne $pasteTotal) 'line not found'
    if ($null -ne $pasteTotal) {
        Assert-Equal 'the paste block''s suite count is the registry''s' $realCount $pasteTotal.Groups[1].Value
        Assert-Equal 'the paste block''s total is the sum of its own per-suite lines' $pasteSum $pasteTotal.Groups[2].Value
    }
}

$suiteRows = @($testingRows | Where-Object { $_ -match '^\|\s*`tkTestToolkit -[A-Za-z]+`\s*\|' })
Assert-True 'docs/TESTING.md has single-suite rows to check' ($suiteRows.Count -gt 0)
foreach ($row in $suiteRows) {
    $suiteName = [regex]::Match($row, '`tkTestToolkit -([A-Za-z]+)`').Groups[1].Value
    # A bare count is a cell holding only a number, or a bolded number in prose.
    $bare = ($row -match '\|\s*\d+\s*\|') -or ($row -match '\*\*\d+\*\*')
    Assert-True "docs/TESTING.md's -$suiteName row carries no count of its own" (-not $bare) $row.Substring(0, [Math]::Min(120, $row.Length))
}

# -- The paste owns every count in docs/TESTING.md ----------------------------
# The paste block is the one record: the CLI's per-suite line and total, a pytest
# line and a web line (tkTest prints all three). The table row's list and the
# command block's three totals are held to it, from the text alone -- no run and
# no machine-local file is read, so it holds in CI as it does anywhere.
Write-Host ""
Write-Host "  The paste block owns the table row and the command block's totals" -ForegroundColor Cyan
. (Join-Path $scriptDir 'Get-TestingDocDrift.ps1')
$driftFindings = @(Get-P20TestingDocDrift -Text $testingText)
Assert-True 'docs/TESTING.md: the table row and the command block agree with the paste block' ($driftFindings.Count -eq 0) ($driftFindings -join ' | ')

# One fixture per drift shape: the clause must name the stale line, and for a
# stale row the first suite whose number differs.
$driftDir = Join-Path $scriptDir 'fixtures/doc-counts'
$driftTable = @(
    # file, expected finding count, a fragment the finding must contain
    @('agree.md', 0, ''),
    @('stale-row.md', 1, "first difference is suite 2, row says 'Compat 19', paste says 'Compat 20'"),
    @('stale-pytest.md', 1, "the command block's pytest line is stale: it says '11 passed"),
    @('stale-web.md', 1, "the command block's web line is stale: it says '7 suites, 54 tests'"),
    @('stale-cli-line.md', 1, "the command block's tkTestToolkit line is stale: it says '3 suites, 59 assertions'"),
    @('pytest-not-run.md', 1, "the paste block's pytest line is not a count"),
    @('pytest-not-available.md', 1, "the paste block's pytest line is not a count"),
    @('agree-via.md', 0, '')
)
foreach ($case in $driftTable) {
    $fx = Get-Content -LiteralPath (Join-Path $driftDir $case[0]) -Raw -Encoding UTF8
    $got = @(Get-P20TestingDocDrift -Text $fx)
    $okCase = ($got.Count -eq $case[1]) -and (($case[1] -eq 0) -or ($got[0] -like "*$($case[2])*"))
    Assert-True "drift fixture $($case[0]): $($case[1]) finding(s)" $okCase ($got -join ' | ')
}

# What tkTest prints for the paste: a half that did not run says so in its line's place.
. (Join-Path $pkgRoot 'Scripts/TestAll-Rules.ps1')
$recAgent = [ordered]@{ result = 'pass'; line = '12 passed, 1 skipped, 40 subtests passed in 3.0s' }
$recWeb = [ordered]@{ result = 'pass'; suites = 7; total = 55 }
$cliTwo = @('Consts 10, Compat 20, Menu 30', '3 suites, 60 assertions')
$pasteTable = @(
    @('all three ran', [ordered]@{ agent = $recAgent; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests|web: 7 suites, 55 tests'),
    @('agent skipped', [ordered]@{ agent = [ordered]@{ result = 'skip'; reason = 'no Python 3 on the PATH' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: NOT AVAILABLE -- no python with pytest was found: no Python 3 on the PATH|web: 7 suites, 55 tests'),
    @('agent ran through a venv', [ordered]@{ agent = [ordered]@{ result = 'pass'; line = $recAgent.line; python = '~/.venv-toolkit/bin/python' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests (via ~/.venv-toolkit/bin/python)|web: 7 suites, 55 tests'),
    @('web failed, CLI partial', [ordered]@{ agent = $recAgent; web = [ordered]@{ result = 'fail' } }, @(), 'CLI: not printed -- the CLI half did not run every suite and pass|pytest: 12 passed, 1 skipped, 40 subtests|web: not printed -- the web half did not pass')
)
foreach ($pc in $pasteTable) {
    $pasted = @(Get-P20PasteLines -Records $pc[1] -CliLines $pc[2])
    Assert-Equal "tkTest's paste block, $($pc[0])" $pc[3] ($pasted -join '|')
}

# -- The front door stays the commercial ------------------------------------
# The root README is what every cold reader, and every cold model, reads first:
# what the product is, the three halves, the five verbs, the quick start and the
# Documentation table, in about a hundred lines. It prints no counts (those live in
# AGENTS.md, docs/TESTING.md and VERIFY.md, checked above), no build history, and
# the known gaps are one link down in docs/KNOWN-GAPS.md. A commercial that grows
# back, or starts dating itself, is the regression this block names.
Write-Host ""
Write-Host "  The README is the front door" -ForegroundColor Cyan
$readmePath = Join-Path $pkgRoot 'README.md'
$readmeLines = @()
$readmeText = ''
if (Test-Path -LiteralPath $readmePath) {
    $readmeLines = @(Get-Content -LiteralPath $readmePath -Encoding UTF8)
    $readmeText = $readmeLines -join "`n"
}
$readmeMax = 120
Assert-True "README.md exists and is at most $readmeMax lines" `
    ((Test-Path -LiteralPath $readmePath) -and ($readmeLines.Count -le $readmeMax)) "$($readmeLines.Count) lines"

# Case-sensitive on purpose: "Since 20" and "since 20" are listed separately.
foreach ($phrase in @('Since 20', 'since 20', 'as of step', 'built 20')) {
    Assert-True "README.md carries no build history: no '$phrase'" (-not $readmeText.Contains($phrase))
}

# Every relative link resolves: a front door that points at a moved drawer is
# broken. External links and bare anchors are not files.
$readmeLinks = @([regex]::Matches($readmeText, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
$relativeLinks = @($readmeLinks | Where-Object { $_ -notmatch '^(https?|mailto):' -and $_ -notmatch '^#' })
Assert-True 'README.md has relative links to check' ($relativeLinks.Count -gt 0) "$($readmeLinks.Count) links in all"
$danglingLinks = @()
foreach ($link in $relativeLinks) {
    $target = $link.Split('#')[0]
    if (-not $target) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $pkgRoot $target))) { $danglingLinks += $link }
}
Assert-True 'every relative link in README.md resolves' ($danglingLinks.Count -eq 0) ($danglingLinks -join ', ')

$gapsPath = Join-Path $pkgRoot 'docs/KNOWN-GAPS.md'
Assert-True 'docs/KNOWN-GAPS.md exists (the known gaps live in the manual)' (Test-Path -LiteralPath $gapsPath)
$gapsText = ''
if (Test-Path -LiteralPath $gapsPath) { $gapsText = Get-Content -LiteralPath $gapsPath -Raw -Encoding UTF8 }
Assert-True 'docs/KNOWN-GAPS.md carries the heading "Known gaps"' `
    ($gapsText -match '(?m)^#+\s+Known gaps\s*$')

# -- The runner counts a suite that did not report as a failure -------------
# Test-Toolkit.ps1 reads each child's score through Get-P20SuiteVerdict. A suite
# that threw before its Results line used to count 0/0 and leave the Total green.
Write-Host ""
Write-Host "  The runner's verdict on a suite's output" -ForegroundColor Cyan
$verdictTable = @(
    # output, exit, status, passed, failed, detail-like
    @('  Results: 12/12 passed', 0, 'PASS', 12, 0, ''),
    @('  Results: 10/12 passed', 1, 'FAIL', 10, 2, 'exit code 1'),
    @('  Results: 12/12 passed', 1, 'FAIL', 12, 1, 'exit code 1'),
    # A Results line QUOTED inside another line is not the score; the last real line is.
    @("  PASS  verdict: 'Results: 3/3 passed' exit 0`n  Results: 19/19 passed", 0, 'PASS', 19, 0, ''),
    @("  PASS  it quotes 'Results: 3/3 passed' and never reports", 0, 'FAIL', 0, 1, 'no Results line -- the suite threw?'),
    @('  Results: 10/12 passed', 0, 'FAIL', 10, 2, ''),
    @("  SKIP  git is not installed`n  Results: 0/0 passed", 0, 'WARN', 0, 0, '*skip*'),
    @('  PASS  one', 0, 'FAIL', 0, 1, 'no Results line*'),
    @("Exception: boom`n  finished", 1, 'FAIL', 0, 1, 'no Results line*exit 1*'),
    @('', 0, 'FAIL', 0, 1, 'no Results line*')
)
foreach ($row in $verdictTable) {
    $v = Get-P20SuiteVerdict -Output $row[0] -ExitCode $row[1]
    $label = "verdict: '$(($row[0] -split "`n")[-1].Trim())' exit $($row[1]) -> $($row[2]) $($row[3])/$($row[3] + $row[4])"
    $ok = ($v.Status -eq $row[2]) -and ($v.Passed -eq $row[3]) -and ($v.Failed -eq $row[4]) -and
        (($row[5] -eq '' -and $v.Detail -notlike 'no Results*') -or ($row[5] -ne '' -and $v.Detail -like $row[5]))
    Assert-True $label $ok "got $($v.Status) $($v.Passed)/$($v.Passed + $v.Failed) '$($v.Detail)'"
}

# The shape that hid the bug, for real: a scratch suite run the way the runner
# runs one (a child pwsh -File), throwing before it prints its Results line.
$scratchSuiteDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-throwing-suite-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $scratchSuiteDir -Force | Out-Null
    $throwing = Join-Path $scratchSuiteDir 'Test-Throws.ps1'
    # Stop, so the write's .NET exception ends the script on every host the way
    # an unhandled throw does -- the shape is "threw before Results", not how.
    Set-Content -LiteralPath $throwing -Encoding UTF8 -Value @'
$ErrorActionPreference = 'Stop'
Write-Host "  PASS  the first assertion"
$missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
try { [System.IO.File]::WriteAllText((Join-Path $missing 'x.txt'), 'x') } finally { }
Write-Host "  Results: 1/1 passed"
'@
    $childOut = (& pwsh -NoProfile -File $throwing 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $childExit = $LASTEXITCODE
    Assert-True 'a scratch suite that throws never reaches its Results line' `
        ($childOut -notmatch 'Results:') $childOut
    $v = Get-P20SuiteVerdict -Output $childOut -ExitCode $childExit
    Assert-True 'the runner counts it as ONE failed suite, not 0/0' `
        (($v.Status -eq 'FAIL') -and ($v.Failed -eq 1) -and ($v.Passed -eq 0)) "got $($v.Status) $($v.Passed)/$($v.Passed + $v.Failed)"
    Assert-True 'and says why: no Results line -- the suite threw?' `
        ($v.Detail -like 'no Results line -- the suite threw?*') $v.Detail
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $scratchSuiteDir -Recurse -Force -ErrorAction SilentlyContinue
}

$runnerSource = Get-Content -LiteralPath (Join-Path $scriptDir 'Test-Toolkit.ps1') -Raw
Assert-True 'the runner reads every suite through Get-P20SuiteVerdict' `
    ($runnerSource -match 'Get-P20SuiteVerdict\s+-Output\s+\$output\s+-ExitCode\s+\$exitCode')
Assert-True 'the runner keeps no Results regex of its own' `
    ($runnerSource -notmatch "-match\s+'Results:")

# -- VERIFY.md's coverage table names every verb -----------------------------
# "Why this file exists" carries one row per verb: the suite that types it, the gate that
# walks it, or "neither". It went stale once -- 26 commands, eight reached -- because
# nothing read it back. Every `commands.<Name>` in config.default.json, and every key of
# a module's Config/*.commands.psd1, must have a row; and a row must name a real verb.
Write-Host ""
Write-Host "  VERIFY.md's coverage table names every verb" -ForegroundColor Cyan
$verifyText = ''
if (Test-Path -LiteralPath $verifyPath) { $verifyText = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 }
$whyStart = $verifyText.IndexOf('## Why this file exists')
$whyEnd = $verifyText.IndexOf('## Gate 1 ')
Assert-True 'VERIFY.md has a "Why this file exists" section ahead of Gate 1' ($whyStart -ge 0 -and $whyEnd -gt $whyStart)
if ($whyStart -ge 0 -and $whyEnd -gt $whyStart) {
    $whyText = $verifyText.Substring($whyStart, $whyEnd - $whyStart)
    $tableVerbs = @([regex]::Matches($whyText, '(?m)^\|\s*`([A-Za-z]+)`\s*\|') | ForEach-Object { $_.Groups[1].Value })
    $defaultCfg = Get-Content -LiteralPath (Join-Path $pkgRoot 'config.default.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $coreVerbs = @($defaultCfg.commands.PSObject.Properties.Name)
    $moduleVerbs = @()
    foreach ($psd in @(Get-ChildItem -Path (Join-Path $pkgRoot 'Config') -Filter '*.commands.psd1' -ErrorAction SilentlyContinue)) {
        $moduleVerbs += @((Import-PowerShellDataFile -LiteralPath $psd.FullName).Commands.Keys)
    }
    $allVerbs = @($coreVerbs) + @($moduleVerbs)
    Assert-True "the table is read (config.default.json has $($coreVerbs.Count) verbs, the modules $($moduleVerbs.Count))" `
        ($coreVerbs.Count -gt 0 -and $tableVerbs.Count -gt 0)
    $missing = @($allVerbs | Where-Object { $tableVerbs -notcontains $_ })
    Assert-True 'every verb in config.default.json and the module data files has a row' ($missing.Count -eq 0) ($missing -join ', ')
    $stale = @($tableVerbs | Where-Object { $allVerbs -notcontains $_ })
    Assert-True 'no row names a verb that is not defined' ($stale.Count -eq 0) ($stale -join ', ')
    $dupes = @($tableVerbs | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-True 'no verb has two rows' ($dupes.Count -eq 0) ($dupes -join ', ')

    # The sentence above the table states the counts: "41 always-on, and the 13 the
    # modules contribute ... (54 in all". It went stale when Team Agile added three verbs.
    $cm = [regex]::Match($whyText, '(\d+) always-on, and the (\d+) the modules[\s\S]*?\((\d+) in all')
    Assert-True 'VERIFY.md states its verb counts in the expected shape' $cm.Success 'pattern not found -- has the sentence been reworded?'
    if ($cm.Success) {
        Assert-Equal "VERIFY.md's always-on verb count is config.default.json's" $coreVerbs.Count $cm.Groups[1].Value
        Assert-Equal "VERIFY.md's module verb count is the data files'" $moduleVerbs.Count $cm.Groups[2].Value
        Assert-Equal "VERIFY.md's total verb count is the sum" $allVerbs.Count $cm.Groups[3].Value
    }

    # docs/CLI.md's command reference opens with the same counts: "42 always on, 55 with
    # every opt-in module switched on." Read it back against the same two sources.
    $cliPath = Join-Path $pkgRoot 'docs/CLI.md'
    $cliText = ''
    if (Test-Path -LiteralPath $cliPath) { $cliText = Get-Content -LiteralPath $cliPath -Raw -Encoding UTF8 }
    $km = [regex]::Match($cliText, '\*\*(\d+) always on, (\d+) with every opt-in module')
    Assert-True 'docs/CLI.md states its verb counts in the expected shape' $km.Success 'pattern not found -- has the sentence been reworded?'
    if ($km.Success) {
        Assert-Equal "docs/CLI.md's always-on verb count is config.default.json's" $coreVerbs.Count $km.Groups[1].Value
        Assert-Equal "docs/CLI.md's with-every-module verb count is the sum" $allVerbs.Count $km.Groups[2].Value
    }
}

# -- docs/TESTING.md's agent row counts its test files ------------------------------
# The inventory row for `pytest Tests/` says "in N files" and gives each file a plain
# "(N)" that is the file's `def test_` count. Nothing read them back, so each new test
# file or test left them stale. N is a digit on purpose, so the regex stays simple.
# Only a plain "(N)" or "(N," is held: an entry written another way, such as
# "(3 tables, 20 cases)", or one with no count, is left to its prose.
Write-Host ""
Write-Host "  docs/TESTING.md's agent row counts the test files" -ForegroundColor Cyan
$testingPath = Join-Path $pkgRoot 'docs/TESTING.md'
$testingText = ''
if (Test-Path -LiteralPath $testingPath) { $testingText = Get-Content -LiteralPath $testingPath -Raw -Encoding UTF8 }
$agentRow = @($testingText -split "`n" | Where-Object { $_.StartsWith('| `python3 -m pytest Tests/` |') })
Assert-True 'docs/TESTING.md has the agent inventory row' ($agentRow.Count -eq 1)
if ($agentRow.Count -eq 1) {
    $realFiles = @(Get-ChildItem -LiteralPath $scriptDir -Filter 'test_*.py' -File)
    $fm = [regex]::Match($agentRow[0], 'in (\d+) files')
    Assert-True 'the agent row states its file count as "in N files"' $fm.Success 'pattern not found -- has the sentence been reworded?'
    if ($fm.Success) {
        Assert-Equal "the agent row's file count is the number of Tests/test_*.py files" $realFiles.Count $fm.Groups[1].Value
    }
    $perFile = @([regex]::Matches($agentRow[0], '`(test_\w+\.py)` \((\d+)[,)]'))
    Assert-True 'the agent row carries per-file counts' ($perFile.Count -gt 0)
    foreach ($pf in $perFile) {
        $name = $pf.Groups[1].Value
        $file = Join-Path $scriptDir $name
        if (-not (Test-Path -LiteralPath $file)) {
            Assert-True "$name (named in the agent row) exists" $false 'no such file in Tests/'
            continue
        }
        $defs = @([regex]::Matches((Get-Content -LiteralPath $file -Raw -Encoding UTF8), 'def test_')).Count
        Assert-Equal "$name's count in the agent row is its def test_ count" $defs $pf.Groups[2].Value
    }
}

Write-Host ""
Write-Host "  Results: $($script:passed)/$($script:passed + $script:failed) passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
    Write-Host ""
    Write-Host "  A suite was added or removed without updating the three counts, or one of" -ForegroundColor Yellow
    Write-Host "  them was reworded so its anchor no longer matches. Update AGENTS.md," -ForegroundColor Yellow
    Write-Host "  docs/TESTING.md and VERIFY.md's suite-count sentences in the same commit;" -ForegroundColor Yellow
    Write-Host "  a full tkTestToolkit run prints the combined row and the total to paste." -ForegroundColor Yellow
}
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
