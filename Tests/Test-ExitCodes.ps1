<#
.SYNOPSIS
    Exit-code smoke tests for the toolkit CLI surface (docs/CLI.md, "Errors").
.DESCRIPTION
    Asserts the exit-code contract on representative commands:
      - A successful invocation exits 0.
      - A failing invocation exits non-zero (no command exits 0 after an error).

    Each command is run in an isolated child pwsh so we observe a real process
    exit code, not the in-proc $LASTEXITCODE.

    SAFETY: the success path only invokes commands that provably short-circuit on
    -Help (so no real, side-effecting logic runs). Today that is the daily and
    test categories. As -Help reaches every function, add the
    remaining categories to $safeHelpByCategory below — the assertion is free.

    Run:  pwsh -File toolkit/Tests/Test-ExitCodes.ps1
    Or:   {cliPrefix}TestToolkit -ExitCodes
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location:
# works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent
$modPath = Join-Path ($pkgRoot) 'utilities.psm1'

# The command namespace under test, read from config rather than typed -- the
# same shape Test-Menu and Test-Autoload use. Typing it is how this suite came
# to run the LEGACY toolkit's MyPRs, TestToolkit and Log: names this package
# does not
# define, which resolved out of the LEGACY toolkit installed on the machine. The
# suite reported 15/15 by asserting the exit-code contract of a different
# product, and on a clean machine the success cases would have failed and the
# failure case passed vacuously, because command-not-found also exits non-zero.
#
. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$cfgPrefix = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot

# ── Test harness ──────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# What makes the child shell honest.
#
# Every assertion below is about THIS package's commands, and a command resolves
# from whatever is on $env:PSModulePath before it resolves from nothing. A
# toolkit installed on the machine -- this package's own autoload shim, or an
# unrelated one advertising the same names -- therefore answers first, and the
# suite passes without the checkout under test ever being asked.
#
# -NoProfile does NOT prevent that: module auto-loading reads PSModulePath, not
# the profile. Nor does setting the variable in the PARENT shell, because pwsh
# prepends the user and system module paths at startup, so a child inherits them
# back. It has to be set INSIDE the child, before the first command resolves --
# which is exactly what this line does. The package's own directory stays on the
# path so its shim is still reachable; nothing else is.
function Get-IsolationLine {
    $escaped = $pkgRoot -replace "'", "''"
    return "`$env:PSModulePath = '$escaped'"
}

# Run a snippet in an isolated child pwsh after importing the module; return the
# process exit code. -Strict sets ErrorActionPreference=Stop so non-terminating
# errors propagate to a non-zero exit (models the failure half of the contract).
function Invoke-ChildExitCode {
    param([string]$Snippet, [switch]$Strict)

    # Windows PowerShell 5.1 turns a native command's stderr line into a terminating
    # error record under 'Stop'. The child's stderr is text here and its code is
    # what is asserted, so the call runs under 'Continue'; the assignment is local to
    # this function and ends with it.
    $ErrorActionPreference = 'Continue'
    $pref = if ($Strict) { "`$ErrorActionPreference = 'Stop'" } else { '' }
    $body = @"
$pref
$(Get-IsolationLine)
Import-Module '$modPath' -DisableNameChecking -Force *> `$null
$Snippet
"@
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "exitcode-$([guid]::NewGuid()).ps1")
    Set-Content -Path $tmp -Value $body -Encoding UTF8
    try {
        & pwsh -NoProfile -File $tmp *> $null
        return $LASTEXITCODE
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Same child, but the OUTPUT matters as well as the code -- the refusal contract
# is as much about what is NOT printed as about what the process exits with.
function Invoke-ChildRun {
    param([string]$Snippet, [hashtable]$Environment = @{}, [string]$Shell = 'pwsh')

    # 5.1 reads a native stderr line as a terminating error under 'Stop';
    # local to this function, see Invoke-ChildExitCode.
    $ErrorActionPreference = 'Continue'

    # The shipped Space answers, whatever the machine's config.local.json makes
    # active: the variable consts.json names under env.activeSpace replaces
    # activeSpace for this child only. A caller's own -Environment may override it.
    $spaceVar = (Get-Content (Join-Path $pkgRoot 'consts.json') -Raw | ConvertFrom-Json).env.activeSpace
    $envMap = @{ $spaceVar = 'azure-demo' }
    foreach ($k in $Environment.Keys) { $envMap[$k] = $Environment[$k] }
    $envLines = ''
    foreach ($k in $envMap.Keys) { $envLines += "`$env:$k = '$($envMap[$k])'`n" }
    $body = @"
$envLines
$(Get-IsolationLine)
Import-Module '$modPath' -DisableNameChecking -Force *> `$null
$Snippet
"@
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "exitcode-$([guid]::NewGuid()).ps1")
    Set-Content -Path $tmp -Value $body -Encoding UTF8
    try {
        # -Shell names the child's executable: 'powershell' is Windows PowerShell 5.1.
        $out = (& $Shell -NoProfile -File $tmp 2>&1 | ForEach-Object { "$_" }) -join "`n"
        return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Two probe scripts, one per half of the contract: one that states its refusal
# and exits 2, and one that fails silently. They are driven through the real
# guard (Invoke-ToolkitScript, module-scoped, reached with & $module { ... })
# rather than through a verb, so the assertion is about the contract and not
# about whichever command happens to implement it today.
$script:probeDir = Join-Path ([System.IO.Path]::GetTempPath()) "exitcode-probe-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $script:probeDir -Force | Out-Null
$script:statedProbe = Join-Path $script:probeDir 'stated.ps1'
$script:silentProbe = Join-Path $script:probeDir 'silent.ps1'
Set-Content -Path $script:statedProbe -Encoding UTF8 -Value @'
Write-CliError -Message 'the card is not in current/.' -Hint 'zzArchive -List shows the candidates.'
exit 2
'@
Set-Content -Path $script:silentProbe -Encoding UTF8 -Value @'
exit 3
'@
# A third: a script that THROWS -- a terminating error under Stop, the shape of
# NewSpace's Move-Item on a Windows 8.3 short path. It leaves no exit code.
$script:throwsProbe = Join-Path $script:probeDir 'throws.ps1'
Set-Content -Path $script:throwsProbe -Encoding UTF8 -Value @'
$ErrorActionPreference = 'Stop'
throw 'An object at the specified path C:\Folder\ZZ~1 does not exist.'  # export:example
'@

function Invoke-Guard {
    param([string]$ProbePath, [hashtable]$Environment = @{})
    $snippet = @"
`$m = Get-Module | Where-Object { `$_.Path -eq '$modPath' } | Select-Object -First 1
& `$m { param(`$p) Invoke-ToolkitScript -Path `$p -Name 'zzProbe' -Prefix 'zz' } '$ProbePath'
Write-Host "LASTEXITCODE=`$LASTEXITCODE"
exit `$LASTEXITCODE
"@
    return Invoke-ChildRun $snippet -Environment $Environment
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Exit-Code Smoke Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# -- The child shell is isolated -----------------------------------------------
# The positive control for Get-IsolationLine. Without it every assertion below
# is worth nothing: the names would resolve from whichever toolkit the machine
# has installed, and a suite that tests the wrong product looks exactly like a
# suite that passes.

Write-Host "-- The child shell can load nothing but this package -" -ForegroundColor Cyan

$isolation = Invoke-ChildRun "Write-Host `"MODULEPATH=`$env:PSModulePath`"; Write-Host `"FOREIGN=`$((Get-Module -ListAvailable | Where-Object { `$_.Path -notlike '$pkgRoot*' }).Count)`""
Assert-True "the child's module path is this package and nothing else" `
    ($isolation.Output -match ("(?m)^MODULEPATH=" + [regex]::Escape($pkgRoot) + "\s*$")) $isolation.Output
Assert-True "no module outside the package is loadable in the child" `
    ($isolation.Output -match 'FOREIGN=0') $isolation.Output

Write-Host ""

# ── Success: -Help exits 0 (one safe command per covered category) ────────────

Write-Host "── Success paths (-Help exits 0) ──────────────────────" -ForegroundColor Cyan

# Only commands that provably short-circuit on -Help — see SAFETY note above.
$safeHelpByCategory = [ordered]@{
    daily = "${cfgPrefix}MyPRs"
    test  = "${cfgPrefix}TestToolkit"
}

foreach ($entry in $safeHelpByCategory.GetEnumerator()) {
    $cmd = $entry.Value
    $code = Invoke-ChildExitCode "$cmd -Help"
    Assert-True "[$($entry.Key)] $cmd -Help exits 0 (got $code)" ($code -eq 0)
}

Write-Host ""

# ── Failure: a bad invocation exits non-zero ──────────────────────────────────

Write-Host "── Failure path (bad invocation exits non-zero) ───────" -ForegroundColor Cyan

$failCode = Invoke-ChildExitCode "${cfgPrefix}MyPRs -NoSuchParam_ZZ" -Strict
Assert-True "Unknown parameter exits non-zero (got $failCode)" ($failCode -ne 0)

Write-Host ""

# ── A stale native exit code is not this verb's failure ──────────────────────
# Import runs the environment probe, whose az call fails against the committed
# template org and leaves $LASTEXITCODE = 1 in the session. Every wrapper guard
# reads that variable after its script returns, so before the reset every
# first verb after Import-Module reported "exit code 1" for a failure it never
# had. Log -Days runs no native command,
# so with a stale code planted the only way it can exit non-zero is the guard.

Write-Host "── Stale `$LASTEXITCODE does not fail a native-free verb ─" -ForegroundColor Cyan

$staleCode = Invoke-ChildExitCode "`$global:LASTEXITCODE = 1; ${cfgPrefix}Log -Days 1" -Strict
Assert-True "${cfgPrefix}Log after a planted exit code 1 exits 0 (got $staleCode)" ($staleCode -eq 0)

Write-Host ""

# ── The refusal contract: exit 2 is "I already said why" ─────────────────────
# AGENTS.md, "The refusal contract". Before it, a script that refused with a good
# sentence got a second, generic block under it -- "Error: exit code 1" -- which
# said less than the line above and pointed at tkLog for details the user
# already had.

Write-Host "── A stated refusal (exit 2) prints ONE block ─────────" -ForegroundColor Cyan

$stated = Invoke-Guard $script:statedProbe
Assert-True "stated refusal keeps the script's own message" ($stated.Output -match 'Error: the card is not in current/\.')
Assert-True "stated refusal keeps the script's own hint" ($stated.Output -match 'zzArchive -List')
Assert-True "stated refusal adds no second 'exit code' block" ($stated.Output -notmatch 'exit code')
Assert-True "stated refusal prints exactly one Error: line" ((@([regex]::Matches($stated.Output, '(?m)^Error: ')).Count) -eq 1)
Assert-True "stated refusal leaves `$LASTEXITCODE = 2" ($stated.Output -match 'LASTEXITCODE=2')
Assert-True "stated refusal exits 2 (got $($stated.ExitCode))" ($stated.ExitCode -eq 2)

Write-Host ""

Write-Host "── A silent failure still gets the generic block ──────" -ForegroundColor Cyan

$silent = Invoke-Guard $script:silentProbe
Assert-True "a non-zero exit with nothing stated is explained" ($silent.Output -match 'Error: exit code 3')
Assert-True "the generic block still points at the log" ($silent.Output -match 'zzLog -Errors')
Assert-True "the silent failure exits non-zero (got $($silent.ExitCode))" ($silent.ExitCode -ne 0)
Assert-True "the silent failure keeps its own code (got $($silent.ExitCode))" ($silent.Output -match 'LASTEXITCODE=3')

Write-Host ""

Write-Host "── A script that throws is a failure, never exit 0 ────" -ForegroundColor Cyan

# The guard printed the error and left $LASTEXITCODE at the 0 it had reset
# it to, so NewSpace said "Error: ..." and reported success.
$threw = Invoke-Guard $script:throwsProbe
Assert-True "a throw is stated with its own message" ($threw.Output -match 'Error: An object at the specified path') $threw.Output
Assert-True "a throw prints exactly one Error: line" ((@([regex]::Matches($threw.Output, '(?m)^Error: ')).Count) -eq 1) $threw.Output
Assert-True "a throw leaves `$LASTEXITCODE = 2" ($threw.Output -match 'LASTEXITCODE=2') $threw.Output
Assert-True "a throw exits 2 (got $($threw.ExitCode))" ($threw.ExitCode -eq 2)
$threwBridged = Invoke-Guard $script:throwsProbe -Environment @{ TOOLKIT_QUIET_STARTUP = '1' }
Assert-True "a throw is re-raised for a non-interactive caller" ($threwBridged.ExitCode -ne 0)
Assert-True "the re-raise carries the throw's message" ($threwBridged.Output -match 'An object at the specified path')

Write-Host ""

# A non-interactive caller (the agent sets TOOLKIT_QUIET_STARTUP) cannot read
# $LASTEXITCODE across the process boundary -- bridge.ps1 exits on whether the
# FUNCTION threw. The guard re-raises a stated refusal for one of those, so
# POST /api/cmd/{name} answers `error` rather than `success`.

Write-Host "── A stated refusal reaches a non-interactive caller ──" -ForegroundColor Cyan

$bridged = Invoke-Guard $script:statedProbe -Environment @{ TOOLKIT_QUIET_STARTUP = '1' }
Assert-True "the refusal is re-raised for a non-interactive caller" ($bridged.ExitCode -ne 0)
Assert-True "the re-raise carries the stated sentence" ($bridged.Output -match 'the card is not in current/')


# ── The Tier-1 gate is a stated refusal, and -Help is never behind it ────────
# Every ADO verb asks Test-AdoAvailable first. It used to print a page of one
# person's setup ("available on your work laptop"), return with exit 0 -- so the
# bridge reported success -- and stand in front of -Help on four verbs.
#The tier is
# forced through $global:P20Env, which Get-CurrentTier reads before probing.

Write-Host "── A Tier-2 refusal is stated, exits 2, and names the cause ──" -ForegroundColor Cyan

$tier2Env = "`$global:P20Env = @{ Tier = 2; OrgStatus = 'local'; ActiveSpace = 'demo'; GitInstalled = `$true; RepoFound = `$true; AzCliInstalled = `$false; AzAuthenticated = `$false; AdoReachable = `$false }"
$refused = Invoke-ChildRun "$tier2Env`n${cfgPrefix}NewPR`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "the documented sentence: <command> needs ADO (Tier 1); currently Tier <n>." ($refused.Output -match "Error: ${cfgPrefix}NewPR needs ADO \(Tier 1\); currently Tier 2\.")
Assert-True "the cause is the hint" ($refused.Output -match "Hint:.*'demo' is local, so Azure DevOps is not contacted")
Assert-True "nobody's laptop is named" ($refused.Output -notmatch 'work laptop')
Assert-True "one Error: line, no generic block" ((@([regex]::Matches($refused.Output, '(?m)^Error: ')).Count) -eq 1 -and $refused.Output -notmatch 'exit code')
Assert-True "it leaves `$LASTEXITCODE = 2" ($refused.Output -match 'LASTEXITCODE=2')
Assert-True "and exits 2 (got $($refused.ExitCode))" ($refused.ExitCode -eq 2)

$bridgedTier = Invoke-ChildRun "$tier2Env`n${cfgPrefix}MyWork`nexit 0" -Environment @{ TOOLKIT_QUIET_STARTUP = '1' }
Assert-True "a non-interactive caller sees the refusal as a failure" ($bridgedTier.ExitCode -ne 0)
Assert-True "and is handed the sentence" ($bridgedTier.Output -match "${cfgPrefix}MyWork needs ADO \(Tier 1\)")

# A GitHub board's refusal names GitHub and gh, never ADO and az -- telling its
# user they need ADO would name a product this board never contacts
# (the sentence above stays pinned for ADO).
$tier2Gh = "`$global:P20Env = @{ Tier = 2; OrgStatus = 'active'; ActiveSpace = 'gh'; GitInstalled = `$true; RepoFound = `$true; Tracker = 'github'; GhCliInstalled = `$false; GhAuthenticated = `$false; TrackerReachable = `$false; AzCliInstalled = `$false; AzAuthenticated = `$false; AdoReachable = `$false }"
$refusedGh = Invoke-ChildRun "$tier2Gh`n${cfgPrefix}MyWork`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "a GitHub board's sentence: needs GitHub (Tier 1)" ($refusedGh.Output -match "Error: ${cfgPrefix}MyWork needs GitHub \(Tier 1\); currently Tier 2\.")
Assert-True "its cause names the gh CLI" ($refusedGh.Output -match 'Hint:.*the gh CLI is not installed')
Assert-True "and ADO is not mentioned" ($refusedGh.Output -notmatch 'needs ADO|az login')
Assert-True "it still exits 2 (got $($refusedGh.ExitCode))" ($refusedGh.ExitCode -eq 2)

Write-Host ""
Write-Host "── -Help answers on a Tier-2 machine ──────────────────" -ForegroundColor Cyan

foreach ($verb in @('NewPR', 'PublishPR', 'GetPRComments', 'ReplyPR', 'NewAdoItem', 'MyPRs')) {
    $help = Invoke-ChildRun "$tier2Env`n${cfgPrefix}$verb -Help`nexit `$LASTEXITCODE"
    Assert-True "${cfgPrefix}$verb -Help prints help, not the refusal (exit $($help.ExitCode))" ($help.ExitCode -eq 0 -and $help.Output -notmatch 'needs ADO' -and $help.Output -match "${cfgPrefix}$verb")
}

Write-Host ""

# ── The PR scripts state their refusals with exit 2 ──────────────────────────
# The sweep that converted fifteen sites missed the PR family; each printed its
# sentence and then got the wrapper's "Error: exit code 1" under it.
#Tier forced to
# 1 so the wrapper reaches the script; the script refuses before any ADO call.

Write-Host "── The PR scripts refuse with ONE block and exit 2 ────" -ForegroundColor Cyan

$tier1Env = "`$global:P20Env = @{ Tier = 1; OrgStatus = 'active'; ActiveSpace = 'azure-demo'; GitInstalled = `$true; RepoFound = `$true; AzCliInstalled = `$true; AzAuthenticated = `$true; AdoReachable = `$true }"
$outside = [System.IO.Path]::GetTempPath() -replace "'", "''"

$reply = Invoke-ChildRun "$tier1Env`n${cfgPrefix}ReplyPR`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "ReplyPR with no id states the refusal" ($reply.Output -match 'Error: -PullRequestId is required\.')
Assert-True "ReplyPR's hint is the usage line" ($reply.Output -match "Hint:\s+Usage: ${cfgPrefix}ReplyPR")
Assert-True "ReplyPR prints one block and exits 2 (got $($reply.ExitCode))" ($reply.Output -notmatch 'exit code' -and (@([regex]::Matches($reply.Output, '(?m)^Error: ')).Count) -eq 1 -and $reply.ExitCode -eq 2)

$newPr = Invoke-ChildRun "$tier1Env`nSet-Location '$outside'`n${cfgPrefix}NewPR`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "NewPR outside a repository states the refusal" ($newPr.Output -match 'Error: Not in a git repository, and no card was named\.')
Assert-True "NewPR prints one block and exits 2 (got $($newPr.ExitCode))" ($newPr.Output -notmatch 'exit code' -and (@([regex]::Matches($newPr.Output, '(?m)^Error: ')).Count) -eq 1 -and $newPr.ExitCode -eq 2)

$review = Invoke-ChildRun "$tier1Env`nRemove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue`nRemove-Item Env:CLAUDE_API_KEY -ErrorAction SilentlyContinue`n${cfgPrefix}AddPRReview 1`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "AddPRReview with no key states the refusal" ($review.Output -match "Error: ${cfgPrefix}AddPRReview needs ANTHROPIC_API_KEY; it is not set\.")
Assert-True "AddPRReview's missing key is exit 2, not a bare return (got $($review.ExitCode))" ($review.Output -match 'LASTEXITCODE=2' -and $review.ExitCode -eq 2)

# The branch's PR search asks each project in turn. A 404 is "not in this project"
# and the search goes on; a 401 or 403 is the token or the permission, and reading
# it as "no PR" sent the user to look for a PR that exists. az, git and the
# REST call are stubbed in the child, so no org is called.
$prSearchStub = @'
$env:ANTHROPIC_API_KEY = 'sk-ant-stub'
function global:az { $global:LASTEXITCODE = 0; 'stub-token' }
function global:git { $global:LASTEXITCODE = 0; 'user/371-stub' }
function global:Invoke-RestMethod {
    param($Uri, $Headers, $Method)
    $ex = New-Object System.Exception 'stubbed REST failure'
    $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = __STATUS__ })
    throw $ex
}
'@
foreach ($code in @(401, 403)) {
    $stub = $prSearchStub.Replace('__STATUS__', "$code")
    $auth = Invoke-ChildRun "$tier1Env`n$stub`n${cfgPrefix}AddPRReview`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
    Assert-True "AddPRReview search: HTTP $code states the refusal with the status and az login" ($auth.Output -match "Error: Azure DevOps refused the PR search in '[^']+' \(HTTP $code\)\." -and $auth.Output -match 'az login')
    Assert-True "AddPRReview search: HTTP $code is not read as 'No open PR found'" ($auth.Output -notmatch 'No open PR found')
    Assert-True "AddPRReview search: HTTP $code prints one block and exits 2 (got $($auth.ExitCode))" ($auth.Output -notmatch 'exit code' -and (@([regex]::Matches($auth.Output, '(?m)^Error: ')).Count) -eq 1 -and $auth.ExitCode -eq 2)
}
if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
    # Windows PowerShell 5.1 reads the status as an enum off a different response type.
    $auth51 = Invoke-ChildRun "$tier1Env`n$($prSearchStub.Replace('__STATUS__', '401'))`n${cfgPrefix}AddPRReview`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Shell 'powershell'
    Assert-True "AddPRReview search: HTTP 401 under Windows PowerShell 5.1 states the refusal and exits 2 (got $($auth51.ExitCode))" ($auth51.Output -match "refused the PR search in '[^']+' \(HTTP 401\)" -and $auth51.Output -notmatch 'No open PR found' -and $auth51.ExitCode -eq 2)
}
$stub404 = $prSearchStub.Replace('__STATUS__', '404')
$notHere = Invoke-ChildRun "$tier1Env`n$stub404`n${cfgPrefix}AddPRReview`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "AddPRReview search: HTTP 404 still means not in this project, so the search ends at 'No open PR found'" ($notHere.Output -match "Error: No open PR found for branch 'user/371-stub'\." -and $notHere.Output -notmatch 'refused the PR search')
Assert-True "AddPRReview search: HTTP 404 is one block and exit 2 (got $($notHere.ExitCode))" ((@([regex]::Matches($notHere.Output, '(?m)^Error: ')).Count) -eq 1 -and $notHere.ExitCode -eq 2)

# The PR-details fetch is the second call in the same script. It knew only 403, so a
# 401 fell through to "Could not fetch PR" with the raw exception instead of the az
# login advice. It reads the status through Get-P20AdoHttpStatus (Scripts/Get-AdoToken.ps1).
foreach ($code in @(401, 403)) {
    $stub = $prSearchStub.Replace('__STATUS__', "$code")
    $det = Invoke-ChildRun "$tier1Env`n$stub`n${cfgPrefix}AddPRReview -PullRequestId 4242`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
    Assert-True "AddPRReview details: HTTP $code gives the access advice naming the status and az login" ($det.Output -match "Access denied \(HTTP $code\)" -and $det.Output -match 'az login')
    Assert-True "AddPRReview details: HTTP $code is not the raw 'Could not fetch PR' sentence" ($det.Output -notmatch 'stubbed REST failure')
    Assert-True "AddPRReview details: HTTP $code is one stated block and exit 2 (got $($det.ExitCode))" ($det.Output -notmatch 'exit code' -and $det.ExitCode -eq 2)
}
if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
    $det51 = Invoke-ChildRun "$tier1Env`n$($prSearchStub.Replace('__STATUS__', '401'))`n${cfgPrefix}AddPRReview -PullRequestId 4242`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Shell 'powershell'
    Assert-True "AddPRReview details: HTTP 401 under Windows PowerShell 5.1 gives the access advice and exits 2 (got $($det51.ExitCode))" ($det51.Output -match 'Access denied \(HTTP 401\)' -and $det51.ExitCode -eq 2)
}
$det404 = Invoke-ChildRun "$tier1Env`n$stub404`n${cfgPrefix}AddPRReview -PullRequestId 4242`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "AddPRReview details: HTTP 404 is unchanged -- Could not fetch PR with the exception text" ($det404.Output -match 'Could not fetch PR #4242\. stubbed REST failure' -and $det404.Output -notmatch 'Access denied' -and $det404.ExitCode -eq 2)

Write-Host ""

# -- NewPR from the Toolkit's own folder: the card answers, nothing is guessed --
# The bridge runs every verb with its cwd at the package root. NewPR used to take
# the Toolkit's branch and remote from there, fall back to the FIRST configured
# project with a warning, and was stopped only because the browser's work item id
# failed Test-Path as -File.
#
# A scratch hub under the shipped 'azure-demo' Space, whose one project is YourProject.

Write-Host "── NewPR from the Toolkit's folder reads the card ─────" -ForegroundColor Cyan

$prHub = Join-Path ([System.IO.Path]::GetTempPath()) "exitcode-prhub-$([guid]::NewGuid())"
$prCurrent = Join-Path $prHub 'azure-demo/current'
New-Item -ItemType Directory -Path $prCurrent -Force | Out-Null
$linked = @(
    '# US-119: Import flow', '',
    '**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/119', '',
    '## Branch', 'you/119/import-flow', '',
    '## Described Changes', '- The import flow.', ''
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $prCurrent 'US-119-import-flow.prompt.md'), $linked)
$unlinked = @(
    '# Spike-K7M2: A finding', '',
    '**ADO Link:** (not linked)', '',
    '## Branch', 'you/K7M2-a-finding', ''
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $prCurrent 'Spike-K7M2-a-finding.prompt.md'), $unlinked)
$prEnv = @{ PROMPTS_ROOT = $prHub }
$atToolkit = "Set-Location '$($pkgRoot -replace "'", "''")'"
try {
    $byId = Invoke-ChildRun "$tier1Env`n$atToolkit`n${cfgPrefix}NewPR 119 -WhatIf`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment $prEnv
    Assert-True "NewPR 119 -WhatIf from the Toolkit's folder exits 0 (got $($byId.ExitCode))" ($byId.ExitCode -eq 0)
    Assert-True "the id resolved to the card" ($byId.Output -match 'US-119-import-flow\.prompt\.md')
    Assert-True "the project and repo are the card's ADO Link's" ($byId.Output -match 'Repo: YourProject / your-repo')
    Assert-True "the source branch is the card's ## Branch, not the Toolkit's" ($byId.Output -match 'Branch: you/119/import-flow -> main')
    Assert-True "nothing was guessed" ($byId.Output -notmatch 'first configured project')
    Assert-True "-WhatIf says nothing was done" ($byId.Output -match 'no pull request was opened')

    $noLink = Invoke-ChildRun "$tier1Env`n$atToolkit`n${cfgPrefix}NewPR K7M2 -WhatIf`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment $prEnv
    Assert-True "a card with no ADO Link refuses rather than guessing a project" ($noLink.Output -match 'Error: Could not tell which Azure DevOps project')
    Assert-True "the hint names -Project and -Repository" ($noLink.Output -match 'Hint:.*-Project and -Repository')
    Assert-True "one block, exit 2 (got $($noLink.ExitCode))" ((@([regex]::Matches($noLink.Output, '(?m)^Error: ')).Count) -eq 1 -and $noLink.ExitCode -eq 2)

    $missing = Invoke-ChildRun "$tier1Env`n$atToolkit`n${cfgPrefix}NewPR 404 -WhatIf`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment $prEnv
    Assert-True "an id with no card is a stated refusal, exit 2 (got $($missing.ExitCode))" ($missing.Output -match "Error: No card with id '404' in current/" -and $missing.ExitCode -eq 2)

    $bare = Invoke-ChildRun "$tier1Env`n$atToolkit`n${cfgPrefix}NewPR -WhatIf`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment $prEnv
    Assert-True "no card named, in the Toolkit's folder: refused, exit 2 (got $($bare.ExitCode))" ($bare.ExitCode -eq 2 -and $bare.Output -match '(?m)^Error: ')
    Assert-True "and the Toolkit's branch is never offered as the source" ($bare.Output -notmatch 'Branch: ')

    # GetPRComments' fallback is the same shape: with no id and no branch it took
    # the cwd's branch, and in the Toolkit's folder that is toolkit's.
    $comments = Invoke-ChildRun "$tier1Env`n$atToolkit`n${cfgPrefix}GetPRComments`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment $prEnv
    Assert-True "GetPRComments with nothing, in the Toolkit's folder: refused before any lookup (exit $($comments.ExitCode))" ($comments.ExitCode -eq 2 -and $comments.Output -match "Error: .*the Toolkit's own checkout")
    Assert-True "and it never says it detected the Toolkit's branch" ($comments.Output -notmatch 'Detected branch:')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $prHub -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""

# -- ReplyPR typed on its success path: the reply lands in the card -----------
# The refusal above reaches the script's first lines. The success path is the
# wrapper's call into Send-PRReply.ps1 and that script's call into
# Set-P20CardReply, and a suite that dot-sources either one directly stays green
# when the wiring between them breaks. az and the REST calls are stubbed in the
# child (global functions, as in the PR search cases), so no org is called; the
# card sits in a scratch hub and names the pull request on its PR URL line.

Write-Host "── ReplyPR typed: the reply is posted and recorded ────" -ForegroundColor Cyan

$replyHub = Join-Path ([System.IO.Path]::GetTempPath()) "exitcode-replyhub-$([guid]::NewGuid())"
$replyCurrent = Join-Path $replyHub 'azure-demo/current'
New-Item -ItemType Directory -Path $replyCurrent -Force | Out-Null
$replyCardPath = Join-Path $replyCurrent 'US-119-import-flow.prompt.md'
$replyCardText = @(
    '# US-119: Import flow', '',
    'PR URL: https://dev.azure.com/YOUR-ADO-ORG/YourProject/_git/your-repo/pullrequest/4242', '',
    '## PR Review Comments (PR 4242)', '',
    '### Comment 1 (Thread 777)',
    'Comment: This null check looks wrong.',
    'Reply: ',
    'Status: active', ''
) -join "`n"
[System.IO.File]::WriteAllText($replyCardPath, $replyCardText)
$replyStub = @'
$global:StubCalls = @()
function global:az { $global:LASTEXITCODE = 0; 'stub-token' }
function global:Invoke-RestMethod {
    param($Uri, $Headers, $Method, $Body)
    $global:StubCalls += "$Method $Uri"
    if ($Method -eq 'Get') { return [pscustomobject]@{ repository = [pscustomobject]@{ name = 'your-repo'; project = [pscustomobject]@{ name = 'YourProject' } } } }
    if ($Method -eq 'Post') { return [pscustomobject]@{ id = 2 } }
    return $null
}
'@
$replyTail = "`n'LASTEXITCODE=' + `$LASTEXITCODE`n`$global:StubCalls | ForEach-Object { 'STUB ' + `$_ }`nexit `$LASTEXITCODE"
try {
    $replyCmd = "${cfgPrefix}ReplyPR 4242 777 -Reply 'Done in abc1234.' -Status fixed"
    $shells = @('pwsh')
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { $shells += 'powershell' }
    foreach ($sh in $shells) {
        [System.IO.File]::WriteAllText($replyCardPath, $replyCardText)
        $ok = Invoke-ChildRun "$tier1Env`n$replyStub`n$replyCmd$replyTail" -Environment @{ PROMPTS_ROOT = $replyHub } -Shell $sh
        $after = [System.IO.File]::ReadAllText($replyCardPath)
        Assert-True "[$sh] ReplyPR typed with a stubbed tracker exits 0 (got $($ok.ExitCode))" ($ok.ExitCode -eq 0 -and $ok.Output -match 'LASTEXITCODE=0')
        Assert-True "[$sh] the reply was posted through the stubbed tracker, then the status patched" ($ok.Output -match 'STUB Post \S+/threads/777/comments' -and $ok.Output -match 'STUB Patch \S+/threads/777\?')
        Assert-True "[$sh] the card's Reply: slot carries the reply" ($after -match '(?m)^Reply: Done in abc1234\.$')
        Assert-True "[$sh] the card's Status: line carries the status" ($after -match '(?m)^Status: fixed$' -and $after -notmatch '(?m)^Status: active$')
        Assert-True "[$sh] the card says it recorded the reply" ($ok.Output -match 'Recorded in US-119-import-flow\.prompt\.md')
    }
}
catch {
    Assert-True "the ReplyPR cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $replyHub -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""

# -- Every script: a red [!] is a refusal written the old way ----------------
# The cases above SAMPLE the contract, and a sample is how CloseWorkItem kept four
# refusals that printed a red [!] line and returned 0 -- the bridge said success
# and the log said ok.
# This SWEEPS: a red "[!]" line in any script under Scripts/ or Config/ is a
# refusal that is not Write-CliError. A yellow [!] is a notice and is allowed.

Write-Host "── No script refuses with a red [!] ───────────────────" -ForegroundColor Cyan

$oldRefusals = @()
foreach ($dir in @('Scripts', 'Config')) {
    foreach ($ps1 in @(Get-ChildItem (Join-Path $pkgRoot $dir) -Filter '*.ps1' -File)) {
        $n = 0
        foreach ($line in [System.IO.File]::ReadAllLines($ps1.FullName)) {
            $n++
            if ($line -match 'Write-Host\s+"\[!\].*-ForegroundColor\s+Red') { $oldRefusals += "$dir/$($ps1.Name):$n" }
        }
    }
}
Assert-True "no red [!] refusal in any script ($($oldRefusals.Count): $($oldRefusals -join ', '))" ($oldRefusals.Count -eq 0)

# And the converted ones, run: each is ONE block and exit 2.
$close = Invoke-ChildRun "$tier1Env`n${cfgPrefix}CloseWorkItem 12345`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "CloseWorkItem with no -Comment: stated, one block, exit 2 (got $($close.ExitCode))" ($close.Output -match 'Error: -Comment is required\.' -and (@([regex]::Matches($close.Output, '(?m)^Error: ')).Count) -eq 1 -and $close.Output -notmatch 'exit code' -and $close.ExitCode -eq 2)
$adoItem = Invoke-ChildRun "$tier1Env`n${cfgPrefix}NewAdoItem -Points -1 -Title x`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "NewAdoItem with bad -Points: stated, one block, exit 2 (got $($adoItem.ExitCode))" ($adoItem.Output -match 'Error: -Points must be a positive number\.' -and (@([regex]::Matches($adoItem.Output, '(?m)^Error: ')).Count) -eq 1 -and $adoItem.ExitCode -eq 2)

Write-Host ""
Write-Host "── A project az rejects is named, never 'exit code 1' ─" -ForegroundColor Cyan
# On the Example org's placeholder project, MyPRs printed "No active
# PRs found." and then the wrapper's reasonless "Error: exit code 1" -- the
# failed `az` call's code leaking out of a script that returned. az is a
# function here: it rejects YourProject the way ADO does and answers [] for
# anything else, so nothing leaves this machine.
$azStub = @'
function global:az {
    if ($args -contains 'YourProject') {
        Write-Error "TF200016: The following project does not exist: YourProject."
        $global:LASTEXITCODE = 1
        return
    }
    $global:LASTEXITCODE = 0
    '[]'
}
function global:Resolve-P20Identity { return 'me@example.com' }
$global:P20Config.Org = 'https://dev.azure.com/SomeOrg'
'@
$onlyPlaceholder = "$azStub`n`$global:P20Config.Projects = @(@{ name = 'YourProject'; repo = 'your-repo' })"
$mixed = "$azStub`n`$global:P20Config.Projects = @(@{ name = 'YourProject'; repo = 'your-repo' }, @{ name = 'RealProject'; repo = 'real-repo' })"

$r = Invoke-ChildRun "$tier1Env`n$onlyPlaceholder`n${cfgPrefix}MyPRs`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "#9: no project answered -- stated, naming the project, exit 2 (got $($r.ExitCode))" ($r.Output -match 'Error: No configured project answered in https://dev.azure.com/SomeOrg \(YourProject\)' -and $r.ExitCode -eq 2)
Assert-True "#9: ...with az's own reason on the project's line" ($r.Output -match "Project 'YourProject' \(repo 'your-repo'\) did not answer.*TF200016")
Assert-True "#9: ...one Error block, no generic 'exit code', no 'No active PRs found.'" ((@([regex]::Matches($r.Output, '(?m)^Error: ')).Count) -eq 1 -and $r.Output -notmatch 'exit code' -and $r.Output -notmatch 'No active PRs found')

$r = Invoke-ChildRun "$tier1Env`n$mixed`n${cfgPrefix}MyPRs`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "#9: one project wrong, one right -- the wrong one is named" ($r.Output -match "Project 'YourProject'.*did not answer")
Assert-True "#9: ...the listing goes on, and it is success: exit 0, no Error (got $($r.ExitCode))" ($r.Output -match 'No active PRs found' -and $r.Output -notmatch '(?m)^Error: ' -and $r.ExitCode -eq 0)

# -- az's JSON list is read through a variable, so 5.1 does not see one object --
# Windows PowerShell 5.1 writes a JSON array as ONE object; @($json | ConvertFrom-Json)
# made the whole list one pull request -- which the table hides, but the sort order and the reviewer de-duplication do not. The child is run in pwsh 7 AND, where the machine
# has it, in Windows PowerShell 5.1 -- whichever shell this suite itself runs in.
$prStub = @'
function global:az {
    $global:LASTEXITCODE = 0
    if ($args -contains '--reviewer') {
        if ($env:P20_TEST_ONE_PR) { return '[]' }
        return '[{"pullRequestId":101,"title":"first","creationDate":"2026-10-01T10:00:00Z"},{"pullRequestId":103,"title":"third","creationDate":"2026-10-03T10:00:00Z"}]'
    }
    if ($env:P20_TEST_ONE_PR) { return '[{"pullRequestId":101,"title":"first","creationDate":"2026-10-01T10:00:00Z"}]' }
    return '[{"pullRequestId":101,"title":"first","creationDate":"2026-10-01T10:00:00Z"},{"pullRequestId":102,"title":"second","creationDate":"2026-10-02T10:00:00Z"}]'
}
function global:Resolve-P20Identity { return 'me@example.com' }
$global:P20Config.Org = 'https://dev.azure.com/SomeOrg'
$global:P20Config.Projects = @(@{ name = 'RealProject'; repo = 'real-repo' })
'@
foreach ($shell in @('pwsh', 'powershell')) {
    if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { continue }
    $r = Invoke-ChildRun "$tier1Env`n$prStub`n${cfgPrefix}MyPRs" -Shell $shell
    $ix = @(101, 102, 103 | ForEach-Object { $r.Output.IndexOf("PR #${_}: ") })
    Assert-True "#186 [$shell]: two lists from az are three links -- 101 once (it is the author's), 102, 103" ((@([regex]::Matches($r.Output, 'PR #\d+: ')).Count) -eq 3 -and ($ix -notcontains -1))
    Assert-True "#186 [$shell]: ...sorted by role then newest first: 102, 101 (author), then 103 (reviewer) -- not one array sorted as one item" ($ix[1] -lt $ix[0] -and $ix[0] -lt $ix[2])
    $r = Invoke-ChildRun "`$env:P20_TEST_ONE_PR = '1'`n$tier1Env`n$prStub`n${cfgPrefix}MyPRs" -Shell $shell
    Assert-True "#186 [$shell]: a one-PR list is still one link" ((@([regex]::Matches($r.Output, 'PR #\d+: ')).Count) -eq 1 -and $r.Output -match 'PR #101: ')
}

$r = Invoke-ChildRun "$tier1Env`n$onlyPlaceholder`n${cfgPrefix}Dashboard`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE"
Assert-True "#9: Dashboard completes and exits 0 when a project does not answer (got $($r.ExitCode))" ($r.Output -match 'Dashboard complete' -and $r.ExitCode -eq 0)
Assert-True "#9: ...with no generic 'exit code' block after it" ($r.Output -notmatch 'exit code \d')
Assert-True "#9: ...and the pipeline section names the project it could not read" ($r.Output -match 'YourProject -- did not answer')

Write-Host ""

# -- Scripts that refuse are reached through the guard ------------------------
# ThreadHash and SwitchSpace used to run their script bare: the refusal printed,
# nothing was logged, a terminal run could still read exit 2 but the bridge
# (which exits on whether the FUNCTION threw) reported success, and SwitchSpace
# of a Space that does not exist printed a notice and returned 0. Each case runs
# a terminal call (exit 2, one Error block, one ERR line in the usage log) and a
# bridge-style call (TOOLKIT_QUIET_STARTUP: a throw carrying the sentence).

Write-Host "-- ThreadHash and SwitchSpace refuse through the guard --" -ForegroundColor Cyan

$guardCases = @(
    @{ Verb = 'ThreadHash'; Call = "${cfgPrefix}ThreadHash -File __no-such-card__.prompt.md -Hash deadbee"; Sentence = 'File not found' },
    @{ Verb = 'SwitchSpace'; Call = "${cfgPrefix}SwitchSpace nope"; Sentence = 'Unknown Space: nope' }
)
foreach ($case in $guardCases) {
    foreach ($shell in @('pwsh', 'powershell')) {
        if ($shell -eq 'powershell' -and -not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { continue }
        $logDir = Join-Path ([System.IO.Path]::GetTempPath()) "guard-log-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        try {
            $term = Invoke-ChildRun "$($case.Call)`n'LASTEXITCODE=' + `$LASTEXITCODE`nexit `$LASTEXITCODE" -Environment @{ P20_USAGE_LOG_DIR = $logDir } -Shell $shell
            $logText = ''
            foreach ($f in @(Get-ChildItem -Path $logDir -Filter 'usage.*.log' -ErrorAction SilentlyContinue)) { $logText += [System.IO.File]::ReadAllText($f.FullName) }
            $errLines = @($logText -split "`n" | Where-Object { $_ -match "`tERR`t" })
            $cmdLines = @($logText -split "`n" | Where-Object { $_ -match "`tCMD`t" })
            Assert-True "$($case.Verb) [$shell]: a terminal run exits 2 (got $($term.ExitCode))" ($term.ExitCode -eq 2 -and $term.Output -match 'LASTEXITCODE=2')
            Assert-True "$($case.Verb) [$shell]: one Error block, no generic 'exit code'" ((@([regex]::Matches($term.Output, '(?m)^Error: ')).Count) -eq 1 -and $term.Output -match $case.Sentence -and $term.Output -notmatch 'exit code')
            Assert-True "$($case.Verb) [$shell]: exactly one ERR line in the usage log, naming the verb, and no CMD line" ($errLines.Count -eq 1 -and $errLines[0] -match "$($case.Verb)" -and $cmdLines.Count -eq 0) $logText
        }
        finally { Remove-Item $logDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $bridged = Invoke-ChildRun "$($case.Call)`nexit 0" -Environment @{ TOOLKIT_QUIET_STARTUP = '1' }
    Assert-True "$($case.Verb): a non-interactive caller sees a failure (got $($bridged.ExitCode))" ($bridged.ExitCode -ne 0)
    Assert-True "$($case.Verb): and is handed the sentence" ($bridged.Output -match $case.Sentence)
}

Write-Host ""

Remove-Item $script:probeDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
