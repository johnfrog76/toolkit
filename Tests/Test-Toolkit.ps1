<#
.SYNOPSIS
    Unified test runner for the Toolkit Toolkit's PowerShell suites.
.DESCRIPTION
    Runs one or more test suites and reports combined results.
    By default runs all suites. Use switches to run specific suites.

    -Help renders USAGE from config.default.json's `commands.TestToolkit` entry
    through Show-ConfigHelp, the same renderer tkWeb and tkAgent use, so the
    command it names is the one THIS package registers. It used to be a
    hand-written here-string naming the LEGACY system's runner five times, and
    two suites this package does not have.
.PARAMETER All
    Run all test suites (default when no suite is specified).
.PARAMETER Review
    Run generate-review tests.
.PARAMETER Compat
    Run PowerShell 5.1 compatibility tests.
.PARAMETER List
    List available test suites without running them.
.PARAMETER Help
    Show usage information.
.EXAMPLE
    {cliPrefix}TestToolkit                # runs all suites
    {cliPrefix}TestToolkit -Review        # runs the review suite only
    {cliPrefix}TestToolkit -Compat -Menu  # runs two suites
    {cliPrefix}TestToolkit -List          # list available suites
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Each suite switch is read by name, through Get-Variable, in the selection loop.')]
[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Review,
    [switch]$Compat,
    [switch]$Menu,
    [switch]$Environment,
    [switch]$ConfigMerge,
    [switch]$Config,
    [switch]$Archive,
    [switch]$Parsers,
    [switch]$PRComments,
    [switch]$BackfillStamps,
    [switch]$Update,
    [switch]$Start,
    [switch]$PullRequest,
    [switch]$CloseWorkItem,
    [switch]$PromptStatus,
    [switch]$ThreadHash,
    [switch]$Billable,
    [switch]$Plan,
    [switch]$Cover,
    [switch]$Design,
    [switch]$Move,
    [switch]$Setup,
    [switch]$Consts,
    [switch]$ResolveBug,
    [switch]$ExitCodes,
    [switch]$StressCheckout,
    [switch]$StressDefaults,
    [switch]$CaptureScreens,
    [switch]$Wasteland,
    [switch]$BakeVoices,
    [switch]$DeckVoiceAudit,
    [switch]$Autoload,
    # Declared, not just registered below: the selection loop reads these by
    # name, so a suite in the registry with no switch runs in a full pass and
    # is listed by -List but cannot be selected alone -- the HubJson trap.
    [switch]$GitRoot,
    [switch]$Sync,
    # Declared because the suite registry below already advertises it.
    # Without the switch the suite ran in a full pass and was listed by
    # -List, but could not be selected alone -- the one suite that could
    # not, and the selection loop reads these by name.
    [switch]$HubJson,
    [switch]$Portability,
    [switch]$Web,
    [switch]$Agent,
    [switch]$TestAll,
    [switch]$ModuleCommands,
    [switch]$Reminders,
    [switch]$Rituals,
    [switch]$StandupRemind,
    [switch]$Triage,
    [switch]$StartWork,
    [switch]$SendTeams,
    [switch]$NewMeeting,
    [switch]$MeetingAgenda,
    [switch]$NewPrompt,
    [switch]$DocCounts,
    [switch]$Connect,
    [switch]$NewSpace,
    [switch]$HowWeWork,
    [switch]$EditItem,
    [switch]$PublishPR,
    # Named sets and a rerun, for a run that cannot afford 35 minutes on
    # Windows:
    #   -Fast    the suites that spawn no shell -- a few minutes; run after a pull
    #   -Slow    the rest, one host process per case
    #   -Failed  whatever failed in the last run on this machine (test-summary.<machine>.json)
    [switch]$Fast,
    [switch]$Slow,
    [switch]$Failed,
    [switch]$List,
    [switch]$Help
)

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path $testDir)) {
    $testDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests'
}

# Ensure PROMPTS_ROOT is set for child suites (standalone / -NoProfile runs)
$repoRoot = (git -C $testDir rev-parse --show-toplevel 2>$null)
if ($repoRoot -and -not $env:PROMPTS_ROOT) { $env:PROMPTS_ROOT = $repoRoot }

# ── The usage log this run writes to ─────────────────────────────────────────
# A test run is not an event. Every suite that loads utilities.psm1 -- and every
# script it drives -- calls Write-ToolkitLog, and 28 `Tier 2 (local mode)` lines
# from suites running without a config landed in the engineer's real
# usage.{machine}.log, beside the bridge refusal assertions pytest wrote on its
# side. That file is what `{prefix}Log -Errors`, the web UI's Log card and its
# error count read as this engineer's history.
#
#
# P20_USAGE_LOG_DIR is the one override both halves read; the child pwsh each
# suite runs in inherits it. Restored in the finally below, because
# `{prefix}TestToolkit` is often run in the shell the engineer keeps using --
# leaving it set would redirect their real log for the rest of the session.
#
# test-results.{machine}.log and test-summary.{machine}.json are NOT redirected:
# the Health card reading real test results is the point of those two.
$previousLogDir = $env:P20_USAGE_LOG_DIR
$scratchLogDir = Join-Path ([System.IO.Path]::GetTempPath()) "p20-test-logs-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratchLogDir -Force | Out-Null
$env:P20_USAGE_LOG_DIR = $scratchLogDir

# The webhook variables, by PATTERN, for the whole run and every child pwsh the
# suites start -- a name no list could contain is the one that would slip
# through -- and the run marker the two posting paths refuse on. Both restored
# in the finally: a person can still send from another shell meanwhile.
#
. (Join-Path $PSScriptRoot '../Scripts/Get-Consts.ps1')
$runnerConsts = Get-P20Consts
$webhookPrefix = $runnerConsts.env.teamsWebhookPrefix
$runMarker = $runnerConsts.env.testRunMarker
$savedWebhooks = @{}
foreach ($v in @(Get-ChildItem Env: | Where-Object { $_.Name.StartsWith($webhookPrefix) })) {
    $savedWebhooks[$v.Name] = $v.Value
    Remove-Item "Env:\$($v.Name)" -ErrorAction SilentlyContinue
}
$previousMarker = [System.Environment]::GetEnvironmentVariable($runMarker)
[System.Environment]::SetEnvironmentVariable($runMarker, '1')

# The agent's on-disk cache (agent/core/disk_cache.py: the Design tab's parsed
# rows and note bodies, by blob sha) lives in the user's cache folder. A suite
# that starts the agent must not fill it with a fixture's rows, so the run points
# consts.json env.agentCacheDir at a scratch folder, restored in the finally.
$agentCacheEnv = $runnerConsts.env.agentCacheDir
$previousAgentCache = [System.Environment]::GetEnvironmentVariable($agentCacheEnv)
$scratchAgentCache = Join-Path ([System.IO.Path]::GetTempPath()) "p20-test-cache-$([guid]::NewGuid())"
[System.Environment]::SetEnvironmentVariable($agentCacheEnv, $scratchAgentCache)

# The bridge's quiet marker. The web UI's Test Health card runs this verb through
# POST /api/cmd/Test, and the bridge sets TOOLKIT_QUIET_STARTUP=1 for that child
# to mark it non-interactive -- which this runner and every pwsh a suite starts
# then inherit. The refusal guard re-raises a stated refusal as a throw for a
# non-interactive caller, so each bare verb a suite types stopped its -Command
# string and exited 1 where it states 2: every refusal case failed. A suite types
# its verbs as a person at a terminal would, so the variable is removed for the
# run and put back in the finally, the way the webhooks are.
$previousQuiet = [System.Environment]::GetEnvironmentVariable('TOOLKIT_QUIET_STARTUP')
[System.Environment]::SetEnvironmentVariable('TOOLKIT_QUIET_STARTUP', $null)

try {

# Load utilities.psm1 for Write-P20TestResult
$utilitiesPath = Join-Path (Split-Path $testDir -Parent) 'utilities.psm1'
if (Test-Path $utilitiesPath) {
    Import-Module $utilitiesPath -DisableNameChecking -Force
}

# ── Suite registry ───────────────────────────────────────────────────────────

# Scope: 'org' suites resolve the active Space's promptsFolder and run against it,
# so their result varies per org — they are tagged with the active Space in the log.
# 'system' suites are org-independent toolkit health and carry no org tag.
#
# The table itself lives in Get-ToolkitSuiteRegistry.ps1, dot-sourced -- so
# Test-DocCounts.ps1 reads the SAME list this runner does, rather than a count
# retyped a second place.
. (Join-Path $testDir 'Get-ToolkitSuiteRegistry.ps1')
$suites = Get-P20ToolkitSuiteRegistry
# The summary file's name and its merge rule are {cliPrefix}Test's too:
# one file holds both, so this runner and the verb that runs all three halves
# write the same file the same way.
. (Join-Path (Join-Path (Split-Path $testDir -Parent) 'Scripts') 'TestAll-Rules.ps1')
$summaryFile = Get-P20TestSummaryPath -PackageRoot (Split-Path $testDir -Parent)

# ── Help ─────────────────────────────────────────────────────────────────────

if ($Help) {
    # USAGE comes from config, not from a here-string. A hand-written block is
    # how this help spent its life sending users of the {cliPrefix}* system to
    # the LEGACY runner, and naming two switches that match no row in the suite
    # table.
    . (Join-Path (Join-Path (Split-Path $testDir -Parent) 'Scripts') 'Show-ConfigHelp.ps1')
    $helpPrefix = ''
    if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $helpPrefix = Get-CliPrefix }
    if (-not $helpPrefix) {
        # No module in the session: read the prefix the same way every other
        # standalone script does, rather than typing one.
        foreach ($cfgName in @('config.default.json', 'config.local.json')) {
            $cfgPath = Join-Path (Split-Path $testDir -Parent) $cfgName
            if (-not (Test-Path $cfgPath)) { continue }
            try {
                $probe = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($probe.commandPrefix) { $helpPrefix = [string]$probe.commandPrefix }
            }
            catch { $null = $_ }
        }
    }
    Show-P20ConfigHelp -CommandName 'TestToolkit' -RepoRoot (Split-Path $testDir -Parent) -Prefix $helpPrefix `
        -Fallback 'config.default.json is missing its commands.TestToolkit entry.'

    # The SUITES list is generated from the table above -- the one thing config
    # cannot hold, because adding a suite is a code change here.
    Write-Host "  Suites:" -ForegroundColor Yellow
    foreach ($entry in $suites.GetEnumerator()) {
        Write-Host "    -$($entry.Key.PadRight(14)) $($entry.Value.Description)" -ForegroundColor Gray
    }
    Write-Host ""
    return
}

# ── List ─────────────────────────────────────────────────────────────────────

if ($List) {
    Write-Host ""
    Write-Host "  Available test suites:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($entry in $suites.GetEnumerator()) {
        $file = Join-Path $testDir $entry.Value.File
        $exists = if (Test-Path $file) { 'ok' } else { 'MISSING' }
        $color = if ($exists -eq 'ok') { 'Green' } else { 'Red' }
        Write-Host "    -$($entry.Key.PadRight(12)) [$exists]  $($entry.Value.Description)" -ForegroundColor $color
    }
    Write-Host ""
    return
}

# ── Determine which suites to run ────────────────────────────────────────────

$selectedSuites = @()
foreach ($entry in $suites.GetEnumerator()) {
    $switchVal = Get-Variable -Name $entry.Key -ValueOnly -ErrorAction SilentlyContinue
    if ($switchVal -eq $true) {
        $selectedSuites += $entry.Key
    }
}
# The suites that never start a host process of their own: seconds each, and
# together a few minutes. Everything else types a verb in a fresh pwsh per
# case, which is where the time goes on Windows.
$fastSuites = @('Consts', 'Compat', 'Menu', 'Environment', 'PRComments', 'PullRequest', 'CloseWorkItem',
    'PromptStatus', 'HubJson', 'Portability', 'Review', 'BackfillStamps', 'Sync', 'DocCounts')
if ($Fast) { $selectedSuites += @($suites.Keys | Where-Object { $fastSuites -contains $_ }) }
if ($Slow) { $selectedSuites += @($suites.Keys | Where-Object { $fastSuites -notcontains $_ }) }
if ($Failed) {
    if (-not (Test-Path $summaryFile)) {
        Write-Host "  -Failed: no $(Split-Path $summaryFile -Leaf) yet -- nothing has run on this machine." -ForegroundColor Yellow
        return
    }
    $last = Get-Content $summaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $last.suites.PSObject.Properties) {
        if ($prop.Value.result -ne 'pass' -and $suites.Contains($prop.Name)) { $selectedSuites += $prop.Name }
    }
    if ($selectedSuites.Count -eq 0) {
        Write-Host "  -Failed: the last run on this machine was green -- nothing to rerun." -ForegroundColor Green
        return
    }
}
$selectedSuites = @($selectedSuites | Select-Object -Unique)
if ($selectedSuites.Count -eq 0 -or $All) {
    $selectedSuites = @($suites.Keys)
}

# ── Run suites ───────────────────────────────────────────────────────────────

$totalPassed = 0
$totalFailed = 0
$suiteResults = @()
$overallStart = Get-Date

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║           Toolkit Test Runner                     ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Suites: $($selectedSuites -join ', ')" -ForegroundColor DarkGray
$activeSpace = $global:P20Config.ActiveSpace
if ($activeSpace) {
    Write-Host "  Org:    $activeSpace" -ForegroundColor DarkGray
}
Write-Host ""

foreach ($suiteName in $selectedSuites) {
    $suite = $suites[$suiteName]
    $file = Join-Path $testDir $suite.File

    if (-not (Test-Path $file)) {
        Write-Host "  ⊘ $suiteName — file not found: $($suite.File)" -ForegroundColor Red
        $suiteResults += [PSCustomObject]@{
            Suite  = $suiteName
            Passed = 0
            Failed = 1
            Seconds = 0
            Time   = '—'
            Status = 'MISSING'
            Detail = "file not found: $($suite.File)"
        }
        $totalFailed++
        # A missing suite is a failed one in the record: logged as `fail`, so the
        # streak breaks and the readers need no fourth word. Its detail says why.
        $missingOrg = if ($suite.Scope -eq 'org') { $activeSpace } else { '' }
        try {
            Write-P20TestResult -Suite $suiteName -Result 'fail' -Passed 0 -Total 1 -Detail "file not found: $($suite.File)" -Org $missingOrg
        }
        catch {
            Write-Warning "Failed to log test result for $suiteName`: $_"
        }
        continue
    }

    $suiteStart = Get-Date

    # Run in a subprocess to get isolated exit code
    $result = & pwsh -NoProfile -File $file 2>&1
    $exitCode = $LASTEXITCODE

    $suiteTime = ((Get-Date) - $suiteStart).TotalSeconds

    # What the suite counts for: Get-P20SuiteVerdict (Get-ToolkitSuiteRegistry.ps1)
    # -- a suite with no Results line, or a non-zero exit, is a FAILED suite
    # counted as at least one failure, never 0/0.
    $output = $result -join "`n"
    $verdict = Get-P20SuiteVerdict -Output $output -ExitCode $exitCode
    $suitePassed = $verdict.Passed
    $suiteFailed = $verdict.Failed

    # Display the suite output, and the time it took, as it finishes.
    Write-Host $output
    Write-Host ("  {0} finished in {1:N1}s" -f $suiteName, $suiteTime) -ForegroundColor DarkGray

    $totalPassed += $suitePassed
    $totalFailed += $suiteFailed

    $status = $verdict.Status
    $suiteResults += [PSCustomObject]@{
        Suite  = $suiteName
        Seconds = [math]::Round([double]$suiteTime, 1)
        Passed = $suitePassed
        Failed = $suiteFailed
        Time   = "{0:N1}s" -f $suiteTime
        Status = $status
        Detail = $verdict.Detail
    }

    # Log structured test result
    $logResult = $status.ToLowerInvariant()
    $logDetail = if ($status -eq 'PASS' -or $status -eq 'WARN') { 'ok' }
    elseif ($verdict.Detail -like 'no Results line*') { $verdict.Detail }
    else {
        # Grab first FAIL line from output as detail
        $failLine = ($output -split "`n" | Where-Object { $_ -match 'FAIL' } | Select-Object -First 1)
        if ($failLine) { $failLine.Trim().Substring(0, [Math]::Min($failLine.Trim().Length, 200)) } else { 'exit code non-zero' }
    }
    $suiteOrg = if ($suite.Scope -eq 'org') { $activeSpace } else { '' }
    try {
        Write-P20TestResult -Suite $suiteName -Result $logResult -Passed $suitePassed -Total ($suitePassed + $suiteFailed) -Detail $logDetail -Org $suiteOrg
    }
    catch {
        Write-Warning "Failed to log test result for $suiteName`: $_"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

$overallTime = ((Get-Date) - $overallStart).TotalSeconds
$grandTotal = $totalPassed + $totalFailed
$anyFail = @($suiteResults | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'MISSING' }).Count -gt 0
$anyWarn = @($suiteResults | Where-Object { $_.Status -eq 'WARN' }).Count -gt 0
# A WARN is a suite that exited 0 and produced no tests -- a deliberate skip,
# not a defect. A suite that actually broke exits non-zero and is a FAIL, so
# failing the run on WARN only turns correct packages red. Still shown as a
# warning so a skip stays visible.
$allGreen = -not $anyFail

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║           Summary                                 ║" -ForegroundColor Cyan
Write-Host "  ╠═══════════════════════════════════════════════════╣" -ForegroundColor Cyan

foreach ($r in $suiteResults) {
    $icon = if ($r.Status -eq 'PASS') { '✓' } elseif ($r.Status -eq 'WARN') { '⚠' } else { '✗' }
    $color = if ($r.Status -eq 'PASS') { 'Green' } elseif ($r.Status -eq 'WARN' -or $r.Status -eq 'MISSING') { 'DarkYellow' } else { 'Red' }
    $line = "  ║  $icon $($r.Suite.PadRight(12)) $($r.Passed)/$($r.Passed + $r.Failed) passed".PadRight(42) + "$($r.Time.PadLeft(8)) ║"
    Write-Host $line -ForegroundColor $color
}

Write-Host "  ╠═══════════════════════════════════════════════════╣" -ForegroundColor Cyan
$timeStr = "{0:N1}s" -f $overallTime
$totalLine = ("  ║  Total: $totalPassed/$grandTotal passed").PadRight(42) + "$($timeStr.PadLeft(8)) ║"
Write-Host $totalLine -ForegroundColor $(if ($anyFail) { 'Red' } elseif ($anyWarn) { 'DarkYellow' } else { 'Green' })
Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
# A suite that did not report is named, with why -- the box's n/n cannot say
# "this suite never reached its Results line".
foreach ($r in @($suiteResults | Where-Object { $_.Status -eq 'FAIL' -and $_.Detail -like 'no Results line*' })) {
    Write-Host "  ✗ $($r.Suite): $($r.Detail)" -ForegroundColor Red
}
Write-Host ""

# ── The counts, ready to paste ─────────────────────────────────────────
# docs/TESTING.md's combined row and the three printed totals (AGENTS.md,
# docs/TESTING.md, VERIFY.md) are built from THIS run's own verdicts, so the
# counts commit after a merge is a paste and never a hand-typed number. Only a
# FULL run prints it -- every suite in the registry, each passed: -Fast, -Slow,
# -Failed or a single suite cannot know the others, and a red suite's count is
# not the one to publish.
$ranEverySuite = $true
foreach ($key in $suites.Keys) {
    if ($selectedSuites -notcontains $key) { $ranEverySuite = $false }
}
if ($ranEverySuite) {
    $notPassed = @($suiteResults | Where-Object { $_.Status -ne 'PASS' })
    if ($notPassed.Count -gt 0) {
        Write-Host "  No counts line: $($notPassed.Count) suite(s) did not pass ($(($notPassed | ForEach-Object { $_.Suite }) -join ', '))." -ForegroundColor DarkYellow
    }
    else {
        $countParts = @()
        foreach ($key in $suites.Keys) {
            $r = $suiteResults | Where-Object { $_.Suite -eq $key } | Select-Object -First 1
            $countParts += "$key $($r.Passed)"
        }
        Write-Host "  Counts for docs/TESTING.md's combined row, from this run:" -ForegroundColor Cyan
        Write-Host "  $($countParts -join ', ')"
        Write-Host "  $($suites.Count) suites, $grandTotal assertions" -ForegroundColor Cyan
        # The paste block holds two more lines this runner cannot know; say so in
        # their place rather than leave a number to copy from an older paste.
        Write-Host "  pytest: not run by tkTestToolkit -- tkTest prints it" -ForegroundColor DarkGray
        Write-Host "  web: not run by tkTestToolkit -- tkTest prints it" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ── Write cross-machine summary JSON (committed via {cliPrefix}Sync) ────────────

$suitesHash = [ordered]@{}
foreach ($r in $suiteResults) {
    $suitesHash[$r.Suite] = [ordered]@{
        # Which of the three halves wrote it: the agent's and the web's
        # entries are {cliPrefix}Test's, and this run leaves them alone.
        half        = 'cli'
        result      = if ($r.Status -eq 'PASS') { 'pass' } elseif ($r.Status -eq 'WARN') { 'warn' } else { 'fail' }
        passed      = $r.Passed
        total       = $r.Passed + $r.Failed
        # Seconds, so a slow suite is visible and a regression in runtime is too.
        seconds     = $r.Seconds
        description = $suites[$r.Suite].Description
        org         = if ($suites[$r.Suite].Scope -eq 'org') { $activeSpace } else { '' }
    }
}
$cliResult = 'pass'
if ($anyFail) { $cliResult = 'fail' }
$cliHalf = [ordered]@{
    half      = 'cli'
    result    = $cliResult
    passed    = $totalPassed
    failed    = $totalFailed
    skipped   = @($suiteResults | Where-Object { $_.Status -eq 'WARN' }).Count
    total     = $grandTotal
    seconds   = [math]::Round([double]$overallTime, 1)
    reason    = ''
    detail    = if ($anyFail) { "$totalFailed failed" } else { 'ok' }
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
}
if ($selectedSuites.Count -lt $suites.Count) { $cliHalf['partial'] = $true }
$top = [ordered]@{
    activeOrg = $activeSpace
    # The grand totals, as DATA -- so a check can compare against a run's real
    # numbers without re-parsing the box-drawing summary above
    # (part 1). Only
    # meaningful for a run that selected every suite; a partial run (a single
    # -Config, -Fast, -Failed...) still writes them, so they describe THIS run,
    # not necessarily the whole product -- suiteCount says which.
    suiteCount  = $selectedSuites.Count
    totalPassed = $totalPassed
    totalFailed = $totalFailed
    grandTotal  = $grandTotal
}
try {
    Merge-P20TestSummary -Path $summaryFile -Halves @{ cli = $cliHalf } -Suites $suitesHash -Top $top
}
catch {
    Write-Warning "Failed to write $(Split-Path $summaryFile -Leaf): $_"
}

if (-not $allGreen) { exit 1 }

}
finally {
    # Put the shell back the way it was found, and take the scratch log with it.
    if ($null -eq $previousLogDir) {
        Remove-Item Env:\P20_USAGE_LOG_DIR -ErrorAction SilentlyContinue
    }
    else {
        $env:P20_USAGE_LOG_DIR = $previousLogDir
    }
    Remove-Item -Path $scratchLogDir -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($name in $savedWebhooks.Keys) { [System.Environment]::SetEnvironmentVariable($name, $savedWebhooks[$name]) }
    if ($null -eq $previousMarker) { [System.Environment]::SetEnvironmentVariable($runMarker, $null) }
    else { [System.Environment]::SetEnvironmentVariable($runMarker, $previousMarker) }
    [System.Environment]::SetEnvironmentVariable($agentCacheEnv, $previousAgentCache)
    Remove-Item -Path $scratchAgentCache -Recurse -Force -ErrorAction SilentlyContinue
    [System.Environment]::SetEnvironmentVariable('TOOLKIT_QUIET_STARTUP', $previousQuiet)
}
