<#
.SYNOPSIS
    {cliPrefix}Test -- run the three halves' suites and report them together.

.DESCRIPTION
    The agent (pytest), the CLI (Tests/Test-Toolkit.ps1) and the web UI (npm test),
    in that order, each in its own child process; then one summary -- per half its
    counts and elapsed time -- and one verdict.

    The runners own their environment (docs/TESTING.md, "The runners own their
    environment"): Test-Toolkit.ps1 and Tests/conftest.py each strip every
    TEAMS_WEBHOOK_*, point P20_USAGE_LOG_DIR at a scratch folder and set the run
    marker for themselves, so this sets none of that for them. The one half that
    sets nothing is npm test, so for that child alone the webhooks are removed and
    the marker set, and both are put back after. pytest's child is told to write
    UTF-8 (PYTHONIOENCODING), so a test name it cannot encode in the console's
    code page cannot kill the run that reports it.

    A half that cannot run is a STATED skip with its reason -- no Python, no
    pytest, no httpx, no pwsh, no npm, no web/node_modules -- and the verdict names
    it as skipped. A skip is not a pass.

    Exit codes (AGENTS.md, "The refusal contract"): 0 when every half that ran
    passed and at least one ran; 2, after the summary and one Error line, when a
    half failed or nothing ran at all.

    test-summary.<machine>.json gains each half this run touched (Merge-P20TestSummary
    in TestAll-Rules.ps1); the halves it did not run keep what they had.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Fast', Justification = 'Read inside the CLI half''s runner, a function defined in this script, which the rule does not follow.')]
[CmdletBinding()]
param(
    [ValidateSet('cli', 'agent', 'web')]
    [string]$Half,
    [switch]$Fast,
    [switch]$Help
)

$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

. (Join-Path $scriptsDir 'TestAll-Rules.ps1')
. (Join-Path $scriptsDir 'Resolve-Python.ps1')
. (Join-Path $scriptsDir 'Get-Consts.ps1')
. (Join-Path $scriptsDir 'Resolve-CliPrefix.ps1')
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
$prefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
if (-not $prefix) { $prefix = Resolve-P20ConfigPrefix -PackageRoot $packageRoot }

if ($Help) {
    . (Join-Path $scriptsDir 'Show-ConfigHelp.ps1')
    Show-P20ConfigHelp -CommandName 'Test' -RepoRoot $packageRoot -Prefix $prefix `
        -Fallback 'config.default.json is missing its commands.Test entry.'
    exit 0
}

$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$halves = @(Get-P20TestHalves)
if ($Half) { $halves = @($Half) }
$consts = Get-P20Consts
$webhookPrefix = $consts.env.teamsWebhookPrefix
$runMarker = $consts.env.testRunMarker

# -- Running one child ---------------------------------------------------------
# Every line is shown as it arrives and kept for the parse. stderr is merged
# because jest writes its totals there. A native command's stderr is an error
# record under 5.1, so the preference is Continue for the call.
function Invoke-P20HalfProcess {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir)
    $lines = New-Object System.Collections.Generic.List[string]
    $code = 0
    $savedEap = $ErrorActionPreference
    $savedEncoding = $null
    try { $savedEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { $savedEncoding = $null }
    Push-Location -LiteralPath $WorkDir
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        & $Exe @Arguments 2>&1 | ForEach-Object {
            $s = [string]$_
            Write-Host $s
            $lines.Add($s)
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
    }
    catch {
        $lines.Add([string]$_.Exception.Message)
        if (-not $code) { $code = 1 }
    }
    finally {
        $ErrorActionPreference = $savedEap
        Pop-Location
        if ($null -ne $savedEncoding) { try { [Console]::OutputEncoding = $savedEncoding } catch { $null = $_ } }
    }
    return @{ Text = ($lines -join "`n"); ExitCode = [int]$code }
}

function New-P20HalfRecord {
    param([string]$Name)
    return [ordered]@{ half = $Name; result = 'skip'; passed = 0; failed = 0; skipped = 0; total = 0; seconds = 0; reason = ''; detail = '' }
}

# -- The three halves ----------------------------------------------------------
$runAgent = {
    $rec = New-P20HalfRecord 'agent'
    # The test venv first, then the PATH's Python: the first that imports pytest
    # and httpx (Scripts/Resolve-Python.ps1; docs/TESTING.md, "Which Python runs pytest").
    $pick = Resolve-P20TestPython -PackageRoot $packageRoot
    $python = $pick.Python
    if ($null -eq $python) {
        $tried = 'python3, python'
        if ($onWindows) { $tried = 'python, py -3, python3' }
        $rec.reason = "no Python 3 on the PATH (tried $tried)"
        return $rec
    }
    if ($pick.Missing) {
        $rec.reason = "$($pick.Missing) is not installed for $($python.Display) -- $($python.Display) -m pip install -r agent/requirements-dev.txt"
        return $rec
    }
    $rec.python = $pick.Via
    $savedIo = $env:PYTHONIOENCODING
    $env:PYTHONIOENCODING = 'utf-8'
    $start = Get-Date
    try {
        $run = Invoke-P20HalfProcess -Exe $python.Exe -Arguments (@($python.Prefix) + @('-m', 'pytest', 'Tests/')) -WorkDir $packageRoot
    }
    finally {
        if ($null -eq $savedIo) { Remove-Item Env:\PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $savedIo }
    }
    $rec.seconds = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    $c = ConvertFrom-P20PytestOutput -Text $run.Text
    $v = Get-P20HalfVerdict -Counts $c -ExitCode $run.ExitCode
    $rec.result = $v.Result; $rec.detail = $v.Detail
    $rec.passed = $c.Passed; $rec.failed = $c.Failed; $rec.skipped = $c.Skipped; $rec.total = $c.Total
    if ($c.Found) { $rec.line = $c.Line }
    return $rec
}

$runCli = {
    $rec = New-P20HalfRecord 'cli'
    $runner = Join-Path (Join-Path $packageRoot 'Tests') 'Test-Toolkit.ps1'
    if (-not (Test-Path -LiteralPath $runner)) {
        $rec.reason = 'Tests/Test-Toolkit.ps1 is not in this package'
        return $rec
    }
    # The runner starts every suite in pwsh, so the CLI half needs it. The host
    # this verb runs in is the answer when it is pwsh already.
    $pwshExe = ''
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try { $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $pwshExe = '' }
        if ($pwshExe -and ([System.IO.Path]::GetFileNameWithoutExtension($pwshExe) -ne 'pwsh')) { $pwshExe = '' }
    }
    if (-not $pwshExe) {
        $found = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $pwshExe = $found.Source }
    }
    if (-not $pwshExe) {
        $rec.reason = 'no pwsh on the PATH -- the CLI runner starts every suite in PowerShell 7'
        return $rec
    }
    $runnerArgs = @('-NoProfile', '-File', $runner)
    if ($Fast) { $runnerArgs += '-Fast'; $rec.fast = $true }
    # The bridge marks the child that runs this verb non-interactive with
    # TOOLKIT_QUIET_STARTUP, and the runner would hand it to every suite's shell,
    # where a stated refusal then throws instead of exiting 2. Removed for this
    # child alone and put back after, like the webhooks for npm test below.
    $savedQuiet = [System.Environment]::GetEnvironmentVariable('TOOLKIT_QUIET_STARTUP')
    [System.Environment]::SetEnvironmentVariable('TOOLKIT_QUIET_STARTUP', $null)
    $start = Get-Date
    try {
        $run = Invoke-P20HalfProcess -Exe $pwshExe -Arguments $runnerArgs -WorkDir $packageRoot
    }
    finally {
        [System.Environment]::SetEnvironmentVariable('TOOLKIT_QUIET_STARTUP', $savedQuiet)
    }
    $rec.seconds = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    $c = ConvertFrom-P20ToolkitOutput -Text $run.Text
    # The CLI runner's own paste lines (a full, green run prints them): kept for
    # the paste block at the foot of this run's summary.
    $script:cliPasteLines = @()
    $pm = [regex]::Match($run.Text, '(?m)^\s*Counts for docs/TESTING\.md''s combined row, from this run:\s*\r?\n\s*(\S[^\r\n]*?)\s*\r?\n\s*(\d+ suites, \d+ assertions)\s*$')
    if ($pm.Success) { $script:cliPasteLines = @($pm.Groups[1].Value, $pm.Groups[2].Value) }
    $v = Get-P20HalfVerdict -Counts $c -ExitCode $run.ExitCode
    $rec.result = $v.Result; $rec.detail = $v.Detail
    $rec.passed = $c.Passed; $rec.failed = $c.Failed; $rec.total = $c.Total
    # A suite that skipped itself is a WARN in the runner's own summary file;
    # it is the CLI half's skip count.
    $written = Read-P20TestSummary -Path (Get-P20TestSummaryPath -PackageRoot $packageRoot)
    if ($null -ne $written -and $written.Contains('suites')) {
        $warns = 0
        foreach ($name in $written['suites'].Keys) {
            $e = $written['suites'][$name]
            if ((Get-P20SuiteHalf $e) -eq 'cli' -and $e['result'] -eq 'warn') { $warns++ }
        }
        $rec.skipped = $warns
    }
    if ($c.Found) { $rec.line = $c.Line }
    return $rec
}

$runWeb = {
    $rec = New-P20HalfRecord 'web'
    $webDir = Join-Path $packageRoot 'web'
    if (-not (Test-Path -LiteralPath (Join-Path $webDir 'package.json'))) {
        $rec.reason = 'web/package.json is not in this package'
        return $rec
    }
    $npm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $npm) {
        $rec.reason = 'npm is not on the PATH -- install Node.js (docs/QUICKSTART.md, "Requirements")'
        return $rec
    }
    if (-not (Test-Path -LiteralPath (Join-Path $webDir 'node_modules'))) {
        $rec.reason = 'web/node_modules is missing -- run npm ci in web/'
        return $rec
    }
    # npm test owns none of the run's environment, so this child gets it here:
    # no webhook variable, and the run marker set. Both put back after.
    $savedHooks = @{}
    foreach ($v in @(Get-ChildItem Env: | Where-Object { $_.Name.StartsWith($webhookPrefix) })) {
        $savedHooks[$v.Name] = $v.Value
        [System.Environment]::SetEnvironmentVariable($v.Name, $null)
    }
    $savedMarker = [System.Environment]::GetEnvironmentVariable($runMarker)
    [System.Environment]::SetEnvironmentVariable($runMarker, '1')
    $start = Get-Date
    try {
        $run = Invoke-P20HalfProcess -Exe $npm.Source -Arguments @('test') -WorkDir $webDir
    }
    finally {
        foreach ($name in $savedHooks.Keys) { [System.Environment]::SetEnvironmentVariable($name, $savedHooks[$name]) }
        [System.Environment]::SetEnvironmentVariable($runMarker, $savedMarker)
    }
    $rec.seconds = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    $c = ConvertFrom-P20JestOutput -Text $run.Text
    $v = Get-P20HalfVerdict -Counts $c -ExitCode $run.ExitCode
    $rec.result = $v.Result; $rec.detail = $v.Detail
    $rec.passed = $c.Passed; $rec.failed = $c.Failed; $rec.skipped = $c.Skipped; $rec.total = $c.Total
    if ($c.Suites -gt 0) { $rec.suites = $c.Suites }
    if ($c.Found) { $rec.line = $c.Line }
    return $rec
}

$runners = @{ agent = $runAgent; cli = $runCli; web = $runWeb }
$descriptions = @{
    agent = 'The agent: python -m pytest Tests/ (pytest''s closing line)'
    web   = 'The web UI: npm test in web/ (jest''s Tests: and Test Suites: lines)'
}
$suiteKeys = @{ agent = 'pytest'; web = 'jest' }

# -- Run -------------------------------------------------------------------------
$script:cliPasteLines = @()
$records = [ordered]@{}
$overallStart = Get-Date
foreach ($h in $halves) {
    Write-Host ""
    Write-Host "  == ${prefix}Test: the $h half ==" -ForegroundColor Cyan
    $rec = & $runners[$h]
    $rec.timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    if ($rec.result -eq 'skip') {
        Write-Host "  SKIP  $h -- $($rec.reason)" -ForegroundColor DarkYellow
    }
    $records[$h] = $rec
}
$overallSeconds = [math]::Round(((Get-Date) - $overallStart).TotalSeconds, 1)

# -- The summary file ------------------------------------------------------------
# The CLI runner has written its own suites (with half = cli) already; this adds
# the run's record of every half it touched, and the agent's and web's one suite
# entry each, so the Health card and Setup read the whole machine.
$suiteEntries = [ordered]@{}
foreach ($h in @($records.Keys)) {
    if (-not $suiteKeys.ContainsKey($h)) { continue }
    $r = $records[$h]
    $entryResult = $r.result
    if ($entryResult -eq 'skip') { $entryResult = 'warn' }
    $suiteEntries[$suiteKeys[$h]] = [ordered]@{
        half        = $h
        result      = $entryResult
        passed      = $r.passed
        total       = ($r.passed + $r.failed)
        skipped     = $r.skipped
        seconds     = $r.seconds
        description = $descriptions[$h]
        detail      = $(if ($r.result -eq 'skip') { $r.reason } else { $r.detail })
        org         = ''
    }
}
$summaryPath = Get-P20TestSummaryPath -PackageRoot $packageRoot
try {
    # Every half this run touched goes in the halves block, a skip with its
    # reason; the agent's and web's suite entries are replaced, and the CLI's
    # are left as the runner wrote them -- or, when the CLI half was skipped,
    # as the last run did.
    $replace = @($records.Keys | Where-Object { $suiteKeys.ContainsKey($_) })
    Merge-P20TestSummary -Path $summaryPath -Halves $records -Suites $suiteEntries -ReplaceSuitesOf $replace
}
catch {
    Write-Warning "Could not write $([System.IO.Path]::GetFileName($summaryPath)): $_"
}

# The daily history the Health card charts (test-results.<machine>.log): one
# line per half that ran, beside the CLI runner's per-suite lines. Only when the
# module is loaded -- the writer is its.
if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    foreach ($h in @($suiteKeys.Keys)) {
        if (-not $records.Contains($h)) { continue }
        $r = $records[$h]
        if ($r.result -eq 'skip') { continue }
        try {
            Write-P20TestResult -Suite $suiteKeys[$h] -Result $r.result -Passed $r.passed -Total ($r.passed + $r.failed) -Detail $r.detail
        }
        catch { Write-Warning "Could not log the $h half: $_" }
    }
}

# -- One summary -----------------------------------------------------------------
$expected = Read-P20ExpectedCounts -Path (Join-Path (Join-Path $packageRoot 'docs') 'TESTING.md')
$rule = '  ' + ('-' * 66)
Write-Host ""
Write-Host "  ${prefix}Test -- the three halves" -ForegroundColor Cyan
Write-Host $rule -ForegroundColor Cyan
foreach ($h in @($records.Keys)) {
    $r = $records[$h]
    $label = $r.result.ToUpperInvariant()
    $color = 'Green'
    if ($r.result -eq 'fail') { $color = 'Red' }
    elseif ($r.result -eq 'skip') { $color = 'DarkYellow' }
    if ($r.result -eq 'skip') {
        $what = "skipped: $($r.reason)"
        $time = ''
    }
    else {
        $what = "$($r.passed) passed, $($r.failed) failed, $($r.skipped) skipped"
        if ($r.Contains('suites')) { $what += " ($($r.suites) suites)" }
        if ($r.result -eq 'fail' -and $r.detail -like 'no summary line*') { $what += " -- $($r.detail)" }
        if ($r.Contains('fast') -and $r.fast) { $what += ' [-Fast]' }
        if ($r.Contains('python') -and $r.python) { $what += " [via $($r.python)]" }
        $time = ('{0:N1}s' -f [double]$r.seconds)
    }
    $rowText = ('  {0,-6} {1,-5} {2}' -f $h, $label, $what).PadRight(60)
    Write-Host $rowText -NoNewline -ForegroundColor $color
    Write-Host ($time.PadLeft(10)) -ForegroundColor DarkGray
}
Write-Host $rule -ForegroundColor Cyan
Write-Host ('  {0,-12} {1}' -f 'Elapsed', ('{0:N1}s' -f $overallSeconds)) -ForegroundColor DarkGray

# Expected vs actual: information, never the verdict. The counts in
# docs/TESTING.md are pasted from a macOS run after a merge, so
# a branch, a partial run or another platform reads differently on purpose.
Write-Host ""
Write-Host "  Expected (docs/TESTING.md) vs actual:" -ForegroundColor Cyan
$differs = @()
foreach ($h in @($records.Keys)) {
    $r = $records[$h]
    $exp = $expected[$h]
    $expText = 'not stated'
    $actText = ''
    $same = $true
    $comparable = ($r.result -ne 'skip')
    if ($h -eq 'cli') {
        if ($exp) { $expText = "$($exp.Total) assertions" }
        $actText = "$($r.total) assertions"
        if ($r.Contains('fast') -and $r.fast) { $comparable = $false; $actText += ' (-Fast: a partial run, not compared)' }
        if ($exp -and $comparable) { $same = ($exp.Total -eq $r.total) }
    }
    elseif ($h -eq 'agent') {
        if ($exp) { $expText = "$($exp.Passed) passed, $($exp.Skipped) skipped" }
        $actText = "$($r.passed) passed, $($r.skipped) skipped"
        if ($exp -and $comparable) { $same = ($exp.Passed -eq $r.passed -and $exp.Skipped -eq $r.skipped) }
    }
    else {
        if ($exp) { $expText = "$($exp.Suites) suites, $($exp.Total) tests" }
        $suitesRan = 0
        if ($r.Contains('suites')) { $suitesRan = $r.suites }
        $actText = "$suitesRan suites, $($r.total) tests"
        if ($exp -and $comparable) { $same = ($exp.Suites -eq $suitesRan -and $exp.Total -eq $r.total) }
    }
    if (-not $comparable -and $r.result -eq 'skip') { $actText = 'not run' }
    $mark = ''
    if (-not $same) { $mark = '  (differs)'; $differs += $h }
    Write-Host ('    {0,-6} expected {1}; actual {2}{3}' -f $h, $expText, $actText, $mark) -ForegroundColor Gray
}
if ($differs.Count -gt 0) {
    Write-Host "  Note: $($differs -join ', ') differs from docs/TESTING.md. Information, not a failure: the merger pastes those counts from the Mac's run after a merge, and a branch or another platform reads differently." -ForegroundColor DarkGray
}

# -- The paste block ----------------------------------------------------------
# docs/TESTING.md's "The counts, after a merge" holds three figures: the CLI's
# per-suite line and total, the pytest totals and the web totals. This is the
# runner that has all three. A half that did not run says so in its line's place.
Write-Host ""
if ($halves.Count -eq 3 -and -not $Fast) {
    Write-Host "  Counts for docs/TESTING.md's paste block, from this run:" -ForegroundColor Cyan
    foreach ($pl in @(Get-P20PasteLines -Records $records -CliLines $script:cliPasteLines)) { Write-Host "  $pl" }
}
else {
    Write-Host "  No paste block: it needs all three halves and no -Fast." -ForegroundColor DarkGray
}

# -- One verdict -----------------------------------------------------------------
$failed = @($records.Keys | Where-Object { $records[$_].result -eq 'fail' })
$passed = @($records.Keys | Where-Object { $records[$_].result -eq 'pass' })
$skipped = @($records.Keys | Where-Object { $records[$_].result -eq 'skip' })
$skipText = ''
if ($skipped.Count -gt 0) {
    $skipText = ' SKIPPED (not passed): ' + (($skipped | ForEach-Object { "$_ -- $($records[$_].reason)" }) -join '; ') + '.'
}
Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "  Verdict: FAILED -- $($failed -join ', ').$skipText" -ForegroundColor Red
    Write-Host ""
    $failHint = "Each half's own output is above; '$($prefix)Test -Half <half>' reruns one."
    if ($failed -contains 'cli') { $failHint += " '$($prefix)TestToolkit -Failed' reruns the CLI suites that failed." }
    Write-CliError -Message "$($failed.Count) of $($records.Count) half/halves failed: $($failed -join ', ')." -Hint $failHint
    exit 2  # a stated refusal: the summary and the reason are printed (AGENTS.md, "The refusal contract")
}
if ($passed.Count -eq 0) {
    Write-Host "  Verdict: NOTHING RAN.$skipText" -ForegroundColor DarkYellow
    Write-Host ""
    Write-CliError -Message "No half ran on this machine: $($skipped -join ', ') skipped." `
        -Hint "Each skip names what is missing; '$($prefix)Setup' checks the rest of the machine."
    exit 2  # nothing was verified, which is not a pass
}
if ($skipped.Count -gt 0) {
    Write-Host "  Verdict: PASSED -- $($passed -join ', ').$skipText" -ForegroundColor DarkYellow
}
else {
    Write-Host "  Verdict: PASSED -- $($passed -join ', ')." -ForegroundColor Green
}
Write-Host ""
exit 0
