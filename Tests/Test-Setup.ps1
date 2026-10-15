<#
.SYNOPSIS
    Tests for the Setup verb and the one rule behind it, Test-P20AdoEnabled.
.DESCRIPTION
    Setup is the first command a careful new user runs, and for a time no
    suite ran it. It told a correctly installed machine with no `az` that it had
    FAILED, never said the word "tier", and pointed at a bootstrap.ps1 this
    package has never had.

    The rule is tested directly. The verb is tested AS A VERB: a scratch copy of
    the package, a fresh shell, and `az` taken off the PATH -- the machine the
    tier model exists for.

    Run:  pwsh -File Tests/Test-Setup.ps1
    Or:   {cliPrefix}TestToolkit -Setup
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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

# -- The rule -------------------------------------------------------------------
Write-Host "-- Test-P20AdoEnabled: it follows the org you are in ---" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Test-AdoEnabled.ps1')
# ONE table, two readers: Tests/test_ado_enabled.py runs the agent's copy of the
# rule over the same file. If the halves disagree about a row, one of them is wrong.
$table = (Get-Content (Join-Path $PSScriptRoot 'fixtures/ado-enabled/table.json') -Raw | ConvertFrom-Json).rows
foreach ($row in $table) {
    $got = Test-P20AdoEnabled -OrgStatus ([string]$row.spaceStatus) -Flag $row.flag -Tracker ([string]$row.tracker)
    Assert-True $row.why ($got -eq [bool]$row.enabled) "got [$got]"
}
Assert-True 'it returns a boolean, not a string' ((Test-P20AdoEnabled -OrgStatus 'active' -Flag $null -Tracker 'ado') -is [bool])
Assert-True 'the table has the row this rule exists for: active, nobody has said, tracker GitHub' `
    (@($table | Where-Object { $_.spaceStatus -eq 'active' -and $null -eq $_.flag -and $_.tracker -eq 'github' }).Count -eq 1)

# -- The tracker rule -----------------------------------------------------------
Write-Host "-- Resolve-P20Tracker: the address decides the tracker ---" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Resolve-Tracker.ps1')
# ONE table, two readers: Tests/test_tracker.py runs the agent's copy of the
# rule over the same file. If the halves disagree about a row, one of them is wrong.
$trackerTable = (Get-Content (Join-Path $PSScriptRoot 'fixtures/tracker/table.json') -Raw | ConvertFrom-Json).rows
foreach ($row in $trackerTable) {
    $got = Resolve-P20Tracker -OrgUrl ([string]$row.org)
    Assert-True $row.why ($got -eq $row.tracker) "got [$got]"
    if ($null -ne $row.PSObject.Properties['owner']) {
        $gotOwner = Get-P20TrackerOwner -OrgUrl ([string]$row.org)
        Assert-True "owner of $(if ($row.org) { $row.org } else { '(blank)' })" ($gotOwner -eq $row.owner) "got [$gotOwner]"
    }
}
Assert-True 'a null address is none, like a blank one' ((Resolve-P20Tracker -OrgUrl $null) -eq 'none')

# -- The header every tracker verb prints before it acts ------------------------:
#the fix for the
# cross-tenant near-miss where an id meant for one tracker fetched another's
# card of the same number with nothing on screen saying which space answered.
Write-Host "-- Write-P20TrackerHeader: names the space and the tracker ---" -ForegroundColor Cyan
$headerOut = (Write-P20TrackerHeader -Name 'DemoOrg' -OrgUrl 'https://dev.azure.com/demoorg' 6>&1 | Out-String)
Assert-True 'an ADO address prints the space and (ado)' ($headerOut -match '\[\*\] In DemoOrg \(ado\)') $headerOut
$headerOut = (Write-P20TrackerHeader -Name 'Toolkit' -OrgUrl 'https://github.com/johnfrog76/toolkit' 6>&1 | Out-String)
Assert-True 'a GitHub address prints (gh)' ($headerOut -match '\[\*\] In Toolkit \(gh\)') $headerOut
$headerOut = (Write-P20TrackerHeader -Name '' -OrgUrl '' 6>&1 | Out-String)
Assert-True 'a blank space name prints a placeholder rather than a blank line' ($headerOut -match '\[\*\] In \(no space\) \(local\)') $headerOut

# -- The verb, on four machines ---------------------------------------------------
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-setup-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
$pkg = Join-Path $base 'pkg'
New-Item -ItemType Directory -Path $pkg -Force | Out-Null
$files = @()
if (Get-Command git -ErrorAction SilentlyContinue) { $files = @(& git -C $pkgRoot ls-files --cached --others --exclude-standard 2>$null) }
if ($files.Count -eq 0) {
    $files = @(Get-ChildItem $pkgRoot -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|dist|__pycache__)[\\/]' } |
        ForEach-Object { $_.FullName.Substring($pkgRoot.Length + 1) })
}
foreach ($rel in $files) {
    if ($rel -match '^(web|agent|issues|docs|spec)/' -or $rel -eq 'config.local.json') { continue }
    $src = Join-Path $pkgRoot $rel
    if (-not (Test-Path $src -PathType Leaf)) { continue }
    $dst = Join-Path $pkg $rel
    New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
    Copy-Item $src $dst
}
$prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
$logDir = Join-Path $base 'log'
$hub = Join-Path $base 'hub'
New-Item -ItemType Directory -Path $logDir, (Join-Path $hub 'demo/current'), (Join-Path $hub 'test/current') -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'),
    '{ "orgs": [ { "slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo" } ] }', $utf8)
$localConfig = Join-Path $pkg 'config.local.json'
$hubJson = $hub -replace '\\', '/'

function Invoke-Setup {
    # A new shell per machine, with `az` taken off the PATH: every directory that
    # holds one is dropped. Reports whether az and git are still resolvable, so a
    # host where that cannot be arranged SKIPS out loud rather than passing.
    param([string]$LocalConfigJson, [string]$Verbs = '', [string]$ModulePath = '', [string]$UsageLogDir = '')
    if (-not $Verbs) { $Verbs = "${prefix}Setup; 'SETUP-EXIT=' + `$LASTEXITCODE" }
    if (-not $ModulePath) { $ModulePath = $pkg }
    if (-not $UsageLogDir) { $UsageLogDir = $logDir }
    [System.IO.File]::WriteAllText($localConfig, $LocalConfigJson, $utf8)
    $command = "`$sep = [System.IO.Path]::PathSeparator; " +
        "`$env:PATH = (@(`$env:PATH -split `$sep | Where-Object { `$_ -and -not (Test-Path (Join-Path `$_ 'az')) -and -not (Test-Path (Join-Path `$_ 'az.cmd')) }) -join `$sep); " +
        "`$env:PSModulePath = '$ModulePath'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$UsageLogDir'; " +
        "Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; " +
        "'AZ=' + [bool](Get-Command az -ErrorAction SilentlyContinue); 'GIT=' + [bool](Get-Command git -ErrorAction SilentlyContinue); " +
        $Verbs
    return (& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

try {
    Write-Host ""
    Write-Host "-- The machine Start leaves: a local org ---------------" -ForegroundColor Cyan
    $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`" }"
    if ($out -match 'AZ=True' -or $out -notmatch 'GIT=True') {
        Write-Host "  SKIP  az could not be taken off the PATH without losing git on this host -- the verb cases did not run" -ForegroundColor Yellow
    }
    else {
        Assert-True 'Setup exits 0' ($out -match 'SETUP-EXIT=0') $out
        Assert-True 'nothing failed' ($out -match ', 0 failed') $out
        Assert-True 'az is not mentioned as missing: Azure DevOps is not in use here' ($out -match 'Azure DevOps: not in use here' -and $out -notmatch 'az CLI not found') $out
        Assert-True 'the tier is STATED, in words a new user can act on' ($out -match 'Working from your cards \(Tier 2\)' -and $out -match 'Nothing is missing') $out
        Assert-True 'a note is explained as a note' ($out -match '\[--\]' -and $out -match 'does not have and does not need') $out
        Assert-True 'no bootstrap.ps1, which this package has never had' ($out -notmatch 'bootstrap') $out
        Assert-True 'no identity warning: only Azure DevOps uses one' ($out -notmatch 'no identity - new work items') $out
        Assert-True 'a config file still spelled activeOrg is named, as a note, with the verbs that rewrite it' ($out -match 'config.local.json still says orgs/activeOrg' -and $out -match 'Config or \w*Sync writes it') $out

        Write-Host ""
        # The shipped Space is local with no address; the old Example --
        # active, with the placeholder address -- is one local patch away, which is
        # what every "active org" case below stands on.
        $activePatch = "`"spaces`": { `"azure-demo`": { `"status`": `"active`", `"org`": `"https://dev.azure.com/YOUR-ADO-ORG`" } }"
        Write-Host "-- An active org and no az: Tier 2, and not a failure --" -ForegroundColor Cyan
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", $activePatch }"
        Assert-True 'Setup exits 0' ($out -match 'SETUP-EXIT=0') $out
        Assert-True 'a missing az is NOT a failure' ($out -match ', 0 failed' -and $out -notmatch '\[XX\] az') $out
        Assert-True 'it is a note that says az is optional, and what works without it' ($out -match '\[--\] az CLI not found -- optional' -and $out -match 'work without it') $out
        Assert-True 'the tier is stated: Tier 2, and what the Azure DevOps verbs need' ($out -match 'Tier 2: the local workflow' -and $out -match 'need az, signed in') $out

        Write-Host ""
        Write-Host "-- features.ado is the explicit answer, both ways ------" -ForegroundColor Cyan
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", $activePatch, `"features`": { `"ado`": false } }"
        Assert-True 'false on an active org: Azure DevOps is not in use, az is not looked for' ($out -match 'Azure DevOps: not in use here' -and $out -notmatch 'az CLI not found') $out
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`", `"features`": { `"ado`": true } }"
        Assert-True 'true on a local org: az is looked for again' ($out -match 'az CLI not found -- optional' -and $out -notmatch 'not in use here') $out

        # -- Menu: Azure DevOps is something you plug in ------------------------------
        # docs/modules/ado.md. The verbs stay registered; what changes is
        # what a person is SHOWN, and for someone in an active org nothing changes.
        Write-Host ""
        Write-Host "-- Menu on the machine Start leaves -------------------" -ForegroundColor Cyan
        $menuVerbs = "'MENU-BEGIN'; ${prefix}Menu; 'MENU-END'; 'ALL-BEGIN'; ${prefix}Menu -All; 'ALL-END'; 'TYPED=' + [bool](Get-Command ${prefix}MyWork -ErrorAction SilentlyContinue)"
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`" }" $menuVerbs
        $menu = [regex]::Match($out, '(?s)MENU-BEGIN(.*)MENU-END').Groups[1].Value
        $all = [regex]::Match($out, '(?s)ALL-BEGIN(.*)ALL-END').Groups[1].Value
        # Canonical names: Menu draws config's rows, and a deprecated alias has none.
        $adoVerbs = @('GetPRComments', 'ReplyPR', 'NewPR', 'PublishPR', 'AddPRReview', 'NewItem', 'MyPRs', 'MyWork', 'CloseItem', 'EditItem', 'Dashboard')
        $leaked = @($adoVerbs | Where-Object { $menu -match "${prefix}$_\b" -or $all -match "(?m)^\s+${prefix}$_\b" })
        Assert-True 'no Azure DevOps verb is shown, in Menu or in Menu -All' ($leaked.Count -eq 0) ($leaked -join ', ')
        Assert-True 'no "Pull Requests" or "Work Items" heading is left over a verb that is neither' ($menu -notmatch 'Pull Requests|Work Items' -and $all -notmatch '(?m)^\s+(Pull Requests|Work Items)\s*$') $menu
        Assert-True 'what is left is listed together, as Cards' ($menu -match '(?m)^\s+Cards\s*$' -and $menu -match "${prefix}NewPrompt" -and $menu -match "${prefix}ThreadHash" -and $menu -match "${prefix}Archive") $menu
        Assert-True 'NewPrompt describes making a card, not an ADO work item' ($menu -match "${prefix}NewPrompt\s+Make a card" -and $menu -notmatch 'ADO work item') $menu
        Assert-True 'nothing on screen is unavailable, so nothing apologises for it' ($menu -notmatch 'ADO commands unavailable' -and $all -notmatch '\(unavailable\)') $menu
        Assert-True 'the inventory NAMES it: Azure DevOps, off, why, and the line that changes it' ($all -match "Azure DevOps\s+off \(follows the org you are in: demo is 'local'\)" -and $all -match 'spaces\.demo\.status=active') $all
        Assert-True 'and the verbs are still registered -- this is the visible half' ($out -match 'TYPED=True') $out

        Write-Host ""
        Write-Host "-- Menu in an active org: as it always was ------------" -ForegroundColor Cyan
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", $activePatch }" $menuVerbs
        $menu = [regex]::Match($out, '(?s)MENU-BEGIN(.*)MENU-END').Groups[1].Value
        $all = [regex]::Match($out, '(?s)ALL-BEGIN(.*)ALL-END').Groups[1].Value
        $missing = @($adoVerbs | Where-Object { $all -notmatch "(?m)^\s+${prefix}$_\b" })
        Assert-True 'every Azure DevOps verb is listed' ($missing.Count -eq 0) ($missing -join ', ')
        Assert-True 'under its own headings, with Prompts still called Prompts' ($menu -match 'Pull Requests' -and $menu -match 'Work Items' -and $menu -match '(?m)^\s+Prompts\s*$' -and $menu -notmatch '(?m)^\s+Cards\s*$') $menu
        Assert-True 'NewPrompt keeps the description it had' ($menu -match 'Create a prompt file from an ADO work item') $menu
        Assert-True 'the inventory says on, and how to turn it off' ($all -match "Azure DevOps\s+on \(follows the org you are in: azure-demo is 'active'\)" -and $all -match 'features\.ado=false') $all

        # -- A connected GitHub Space: active, and its tracker is GitHub -----------------
        # The surface used to read on here, because the rule asked the status alone and
        # a GitHub Space is active once connected. The tracker verbs stay listed -- they
        # answer through gh -- and the Azure DevOps row says why it is off.
        Write-Host ""
        Write-Host "-- Menu on a connected GitHub Space: the tracker verbs, no Azure DevOps --" -ForegroundColor Cyan
        $githubPatch = "`"spaces`": { `"azure-demo`": { `"status`": `"active`", `"org`": `"https://github.com/acme/widgets`" } }"
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", $githubPatch }" $menuVerbs
        $all = [regex]::Match($out, '(?s)ALL-BEGIN(.*)ALL-END').Groups[1].Value
        $missing = @($adoVerbs | Where-Object { $all -notmatch "(?m)^\s+${prefix}$_\b" })
        Assert-True 'every tracker verb is listed: the Space has a tracker, and it answers through gh' ($missing.Count -eq 0) ($missing -join ', ')
        Assert-True 'the inventory says Azure DevOps is off, and names the tracker as the reason' ($all -match "Azure DevOps\s+off \(follows the org you are in: azure-demo's tracker is GitHub\)") $all
        Assert-True 'and the line that changes it is the flag alone: the status is already active' ($all -match 'features\.ado=true' -and $all -notmatch 'spaces\.azure-demo\.status=active') $all
        Assert-True 'GitHub issues reads on beside it' ($all -match 'GitHub issues\s+on') $all

        # -- A nav alias of your own, set by path alone, is registered ----------------
        # The module used to default a local-only alias to hidden and skip it at
        # registration, so a path written by Config registered nothing.
        #
        Write-Host ""
        Write-Host "-- A local alias with a path registers ----------------" -ForegroundColor Cyan
        $aliasDir = ($base -replace '\\', '/')
        $aliasVerbs = "'MINE=' + [bool](Get-Alias ${prefix}Mine -ErrorAction SilentlyContinue); 'HIDDEN=' + [bool](Get-Alias ${prefix}Hidden -ErrorAction SilentlyContinue)"
        $out = Invoke-Setup "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`", `"aliases`": { `"Mine`": { `"path`": `"$aliasDir`" }, `"Hidden`": { `"path`": `"$aliasDir`", `"display`": false } } }" $aliasVerbs
        Assert-True 'a path alone is enough: the alias is registered' ($out -match 'MINE=True') $out
        Assert-True 'display false still hides it' ($out -match 'HIDDEN=False') $out

        # -- Which toolkit, not whether "a" toolkit ------------------------------------
        #
        Write-Host ""
        Write-Host "-- Setup says WHICH toolkit the shim and the profile load --" -ForegroundColor Cyan
        $demoCfg = "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`" }"
        $out = Invoke-Setup $demoCfg
        Assert-True "this checkout's own shim reads as autoload installed, naming where" ($out -match "autoload installed -- this checkout's verbs") $out
        $other = Join-Path $base 'other'
        New-Item -ItemType Directory -Path (Join-Path $other 'Prompt20Toolkit') -Force | Out-Null
        Copy-Item (Join-Path $pkg 'Prompt20Toolkit/*') (Join-Path $other 'Prompt20Toolkit') -Recurse -Force
        [System.IO.File]::WriteAllText((Join-Path $other 'utilities.psm1'), "# not this toolkit`n", $utf8)
        $out = Invoke-Setup $demoCfg -ModulePath $other
        Assert-True 'a shim on the path that loads a DIFFERENT toolkit is a warning naming both' ($out -match 'loads a DIFFERENT toolkit' -and $out -match [regex]::Escape((Join-Path $other 'utilities.psm1'))) $out
        Assert-True 'and it is not reported as this checkout being installed' ($out -notmatch "autoload installed -- this checkout") $out
        $profileFile = Join-Path $base 'profile.ps1'
        [System.IO.File]::WriteAllText($profileFile, "Import-Module '$($other -replace '\\', '/')/utilities.psm1'`n", $utf8)
        $profileVerbs = "`$PROFILE = '$($profileFile -replace "'", "''")'; ${prefix}Setup; 'SETUP-EXIT=' + `$LASTEXITCODE"
        $out = Invoke-Setup $demoCfg $profileVerbs
        Assert-True 'a profile that imports a different toolkit is a warning, not [ok]' ($out -match 'PS profile imports a DIFFERENT toolkit' -and $out -notmatch 'PS profile imports this toolkit') $out

        # -- C2, C4, C8: the three self-checks the spec lists --------------------------
        #
        Write-Host ""
        Write-Host "-- C2, C4, C8: verbs resolve, templates present, log writable --" -ForegroundColor Cyan
        $out = Invoke-Setup $demoCfg
        Assert-True 'C2: every registered command resolves, and how many were checked' ($out -match 'every registered command resolves \(\d+ checked\)') $out
        Assert-True 'C4: the templates are present, one per type' ($out -match 'card templates present for every type') $out
        Assert-True 'C8: the log path is writable, and named' ($out -match "log path writable: " ) $out
        $bugTemplate = Join-Path $pkg 'templates/Bug.template.md'
        Move-Item $bugTemplate "$bugTemplate.away" -Force
        try {
            $out = Invoke-Setup $demoCfg
            Assert-True 'C4: a missing template is a FAILURE that names the type and the file' ($out -match '\[XX\] card template\(s\) missing' -and $out -match 'Bug\.template\.md' -and $out -notmatch ', 0 failed') $out
        }
        finally { Move-Item "$bugTemplate.away" $bugTemplate -Force }
        $readOnlyLog = Join-Path $base 'readonly-log'
        New-Item -ItemType Directory -Path $readOnlyLog -Force | Out-Null
        $probe = Join-Path $readOnlyLog 'probe'
        $canMakeReadOnly = $false
        if (-not (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows)) {
            & chmod 555 $readOnlyLog 2>$null
            try { [System.IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force } catch { $canMakeReadOnly = $true }
        }
        if ($canMakeReadOnly) {
            try {
                $out = Invoke-Setup $demoCfg -UsageLogDir $readOnlyLog
                Assert-True 'C8: an unwritable log directory is a FAILURE that names it and the override' ($out -match '\[XX\] log path is not writable' -and $out -match 'P20_USAGE_LOG_DIR') $out
            }
            finally { & chmod 755 $readOnlyLog 2>$null }
        }
        else {
            Write-Host "  SKIP  C8 failure case: this host cannot make a directory read-only for its own user" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "-- No config at all: told what to run, by its real name -" -ForegroundColor Cyan
        Remove-Item $localConfig -Force
        $command = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$logDir'; " +
            "Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; ${prefix}Setup"
        $out = (& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
        Assert-True 'a machine with no config is pointed at Start and Config' ($out -match "${prefix}Start" -and $out -match "${prefix}Config -Set promptsRoot" -and $out -notmatch 'bootstrap') $out
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }

# -- Summary ----------------------------------------------------------------------
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
