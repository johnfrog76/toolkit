<#
.SYNOPSIS
    Tests for Send-TeamsMessage.ps1 -- gate 2, argument validation, help, and
    the wrapper that fronts it.
.DESCRIPTION
    Every test runs the script inside a sandbox: a temp directory holding a copy
    of the script under Scripts/ and its own config.default.json. The script
    resolves its root from its own location, so that sandbox IS its repo -- the
    recipients registry under test is the one written here, and nothing reads
    the real config.

    Nothing in this suite reaches a network. The agent port in the sandbox
    config is one nothing listens on, and the only value ever written to a
    webhook variable is a plain string.

    Run:  pwsh -File Tests/Test-SendTeams.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$sendScript = Join-Path $pkgRoot 'Scripts/Send-TeamsMessage.ps1'
$commandFile = Join-Path $pkgRoot 'Config/communication.commands.ps1'
$guardFile  = Join-Path $pkgRoot 'Scripts/Invoke-CommandScript.ps1'
. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
$consts = Get-P20Consts

# -- Harness --------------------------------------------------------------------

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
        if ($Detail) { $msg = "$msg -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# Plain substring, not -like: a needle containing [ or ] is a wildcard character
# class to -like, and "[-Date YYYY-MM-DD]" is a perfectly ordinary thing to look
# for in a usage line.
function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName ($Haystack.Contains($Needle)) "'$Needle' not in output"
}

function Assert-NotContains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName (-not $Haystack.Contains($Needle)) "'$Needle' was in output"
}

# -- Sandbox --------------------------------------------------------------------
# A port nothing listens on: a test that reaches gate 2 must fail on the
# connection, deterministically, rather than finding a real agent.
$DeadPort = 49781

function New-SendSandbox {
    param([hashtable]$Recipients, [string]$HubJson, [hashtable]$LocalConfig)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-send-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path (Join-Path $root 'Scripts') -ItemType Directory -Force | Out-Null
    Copy-Item $sendScript (Join-Path $root 'Scripts/Send-TeamsMessage.ps1')
    # The one reader of hub.json, which gate 2 goes through for a hub-declared org.
    Copy-Item (Join-Path (Split-Path $sendScript -Parent) 'Resolve-HubConfig.ps1') (Join-Path $root 'Scripts/Resolve-HubConfig.ps1')
    # The contract file and its reader: the webhook prefix, the run marker, the Sent line.
    foreach ($helper in @('Get-Consts.ps1', 'Add-SentLine.ps1', 'Write-CardText.ps1', 'Write-ConfigParseWarning.ps1')) {
        Copy-Item (Join-Path (Split-Path $sendScript -Parent) $helper) (Join-Path $root "Scripts/$helper")
    }
    Copy-Item (Join-Path (Split-Path (Split-Path $sendScript -Parent) -Parent) 'consts.json') (Join-Path $root 'consts.json')
    if ($HubJson) {
        New-Item -Path (Join-Path $root 'hub') -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root 'hub/hub.json'), $HubJson, (New-Object System.Text.UTF8Encoding($false)))
        if (-not $LocalConfig) { $LocalConfig = @{} }
        $LocalConfig['promptsRoot'] = (Join-Path $root 'hub')
    }
    if ($LocalConfig) {
        $LocalConfig | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'config.local.json') -Encoding UTF8
    }

    if (-not $Recipients) {
        $Recipients = @{
            manager = @{ type = 'channel'; display = 'My Manager'; webhookEnv = 'TEAMS_WEBHOOK_MANAGER' }
        }
    }
    $cfg = @{
        activeOrg       = 'test'
        web             = @{ agentPort = $DeadPort }
        managerWorkflow = @{
            retroChannel = 'manager'
            communication = @{ recipients = $Recipients }
        }
        orgs            = @(@{ slug = 'test'; status = 'local' })
    }
    $cfg | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'config.default.json') -Encoding UTF8
    return $root
}

function Remove-SendSandbox {
    param([string]$Root)
    if ($Root -and (Test-Path $Root)) { Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue }
}

# Run one command in a child pwsh and return everything it printed as text.
# Windows PowerShell 5.1 turns a native command's stderr line into a terminating
# error record under 'Stop'; here stderr is just output and the caller
# asserts on it, so the call runs under 'Continue' (local to this function) and
# $LASTEXITCODE is left as the child set it. The command travels as
# -EncodedCommand: 5.1 does not escape a double quote inside a native argument, so
# a command carrying one (the Env:\ line in Invoke-Send) reached the child mangled
# and parsed as nothing.
function Invoke-PwshText {
    param([string]$Command)
    $ErrorActionPreference = 'Continue'
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
    return ((pwsh -NoProfile -OutputFormat Text -EncodedCommand $encoded 2>&1 | ForEach-Object { "$_" }) -join "`n")
}

# Run the sandboxed copy in a child pwsh so an exit or a throw cannot take this
# suite with it, and so the environment each case sets is its own.
function Invoke-Send {
    param([string]$Root, [string[]]$Arguments, [hashtable]$Environment)

    $script = Join-Path $Root 'Scripts/Send-TeamsMessage.ps1'
    $envPrefix = ''
    # EVERY webhook variable, by pattern, cleared in the child before a case's
    # own are set: this helper takes the run marker away on purpose, so it must
    # not leave a real webhook standing beside it. A list of three names missed
    # TEAMS_WEBHOOK_DEMO_CHANNEL.
    $envPrefix += "Get-ChildItem Env: | Where-Object { `$_.Name.StartsWith('$($consts.env.teamsWebhookPrefix)') } | ForEach-Object { Remove-Item (""Env:\"" + `$_.Name) }; "
    # PROMPTS_ROOT: the runner points every suite at a scratch hub; a sandbox
    # here names its own hub in config.local.json, and the override would win.
    foreach ($key in @('TEAMS_WEBHOOK_MANAGER', 'TEAMS_WEBHOOK_URL', 'TEAMS_WEBHOOK_TEAM_CHANNEL', 'P20_TEST_RUN', 'PROMPTS_ROOT')) {
        # P20_TEST_RUN: the runner sets it for this process; the child must not
        # inherit it unless a case asks, or every gate-2 case would stop at the
        # marker instead of reaching the (dead) agent it asserts on.
        $value = ''
        if ($Environment -and $Environment.ContainsKey($key)) { $value = $Environment[$key] }
        $envPrefix += "`$env:$key = '$value'; "
    }
    # A token that starts with a dash is a parameter NAME and must not be
    # quoted -- quoting it makes PowerShell bind it positionally, and -Help
    # arrives as the recipient.
    $quoted = ($Arguments | ForEach-Object {
            if ($_ -like '-*') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
        }) -join ' '
    $command = "$envPrefix & '$script' $quoted"
    $output = Invoke-PwshText -Command $command
    return @{ Output = $output; ExitCode = $LASTEXITCODE }
}

Write-Host ""
Write-Host "  SendTeams -- the engine primitive and its two gates" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- Help -----------------------------------------------------------------------

Write-Host "-- Help --------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox
try {
    $result = Invoke-Send -Root $sandbox -Arguments @('-Help')
    Assert-Contains "-Help names the command" $result.Output 'SendTeams'
    Assert-Contains "-Help shows usage" $result.Output '<recipient> <message>'
    Assert-Contains "-Help explains the recipient is a key, not a URL" $result.Output 'not a URL'
    Assert-True "-Help exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
    # The prefix is data. A help line that spells one out is wrong on any
    # install that changed it.
    Assert-NotContains "-Help hardcodes no prefix" $result.Output 'zzSendTeams'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# -- Gate 2 sees the org's recipients wherever the org is declared ------------
# A real org lives in the hub's hub.json or in config.local.json's spaces.<slug>
# patch, never in the committed file. Gate 2 read the committed array alone, so
# for a real channel it found nothing, the engine answered `skipped`, and the
# script threw on it.

Write-Host ""
Write-Host "-- Gate 2 and a hub-declared org --------------------------" -ForegroundColor Cyan

$hubJson = '{ "orgs": [ { "slug": "client", "name": "Client", "status": "local", "promptsFolder": "client", ' +
    '"communication": { "recipients": { "team": { "type": "channel", "display": "Team", "webhookEnv": "TEAMS_WEBHOOK_TEAM_CHANNEL" } } } } ] }'
$sandbox = New-SendSandbox -HubJson $hubJson -LocalConfig @{ activeOrg = 'client' }
try {
    $result = Invoke-Send -Root $sandbox -Arguments @('team', 'hello') -Environment @{}
    Assert-Contains "a recipient declared only in hub.json is found by gate 2" $result.Output 'TEAMS_WEBHOOK_TEAM_CHANNEL'
    Assert-Contains "and the answer is the gate's own sentence, not a throw" $result.Output 'Not sent -- no webhook configured'
    Assert-NotContains "nothing was posted" $result.Output 'Could not reach the agent'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

Write-Host ""
Write-Host "-- Gate 2 and a locally patched org -----------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox -LocalConfig @{ activeOrg = 'test'; orgs = @{ test = @{ communication = @{ recipients = @{ ops = @{ type = 'channel'; display = 'Ops'; webhookEnv = 'TEAMS_WEBHOOK_TEAM_CHANNEL' } } } } } }
try {
    $result = Invoke-Send -Root $sandbox -Arguments @('ops', 'hello') -Environment @{}
    Assert-Contains "a recipient patched in config.local.json is found by gate 2" $result.Output 'TEAMS_WEBHOOK_TEAM_CHANNEL'
    Assert-NotContains "and it is not left to the engine" $result.Output 'Could not reach the agent'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# -- A test run does not post ---------------------------------------------------
# The runner sets the marker for its process tree; with it set, the script stops
# before the engine is reached, dry run excepted.
#

Write-Host ""
Write-Host "-- The run marker ----------------------------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox
try {
    $result = Invoke-Send -Root $sandbox -Arguments @('manager', 'hello') -Environment @{ TEAMS_WEBHOOK_MANAGER = 'https://example.invalid/hook'; P20_TEST_RUN = '1' }
    Assert-Contains "with the marker set, nothing posts and the reason is said" $result.Output 'a test run is in progress'
    Assert-NotContains "and the agent is never reached" $result.Output 'Could not reach the agent'
    $dry = Invoke-Send -Root $sandbox -Arguments @('manager', 'hello', '-WhatIf') -Environment @{ TEAMS_WEBHOOK_MANAGER = 'https://example.invalid/hook'; P20_TEST_RUN = '1' }
    Assert-NotContains "a dry run is not stopped by the marker" $dry.Output 'a test run is in progress'
    Assert-True "the runner itself clears every webhook variable for its process (this suite sees none)" `
        ((-not $env:P20_TEST_RUN) -or (@(Get-ChildItem Env: | Where-Object { $_.Name.StartsWith('TEAMS_WEBHOOK_') }).Count -eq 0)) 'a TEAMS_WEBHOOK_* variable reached a suite'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# The import is what put them back: the module read the package's .env into the
# process on every import, so the runner's strip lasted until a suite's first
# Import-Module. A machine with webhooks in .env is the only one that could see
# it -- so this builds one: a scratch package whose .env holds a fake webhook,
# imported in a fresh shell with and without the marker. Nothing is sent: the
# child only reports what its environment holds.
#
Write-Host ""
Write-Host "-- .env during a test run -------------------------------" -ForegroundColor Cyan
$envPkg = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-dotenv-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $envPkg -Force | Out-Null
    foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $envPkg -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $envPkg -Recurse -Force }
    $fakeHook = "$($consts.env.teamsWebhookPrefix)DOTENV_PROBE"
    [System.IO.File]::WriteAllText((Join-Path $envPkg '.env'), "$fakeHook=https://example.invalid/hook`nP20_DOTENV_PLAIN=seen`n", (New-Object System.Text.UTF8Encoding($false)))
    $probe = {
        param([bool]$Marker)
        $markerSet = if ($Marker) { "`$env:$($consts.env.testRunMarker) = '1'" } else { "Remove-Item Env:\$($consts.env.testRunMarker) -ErrorAction SilentlyContinue" }
        $body = "$markerSet; `$env:PSModulePath = '$($envPkg -replace "'", "''")'; " +
            "Import-Module '$($envPkg -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; " +
            "'HOOK=' + [bool][System.Environment]::GetEnvironmentVariable('$fakeHook'); 'PLAIN=' + `$env:P20_DOTENV_PLAIN"
        return ((& pwsh -NoProfile -NonInteractive -Command $body 2>&1 | ForEach-Object { "$_" }) -join "`n")
    }
    $during = & $probe $true
    Assert-True "with the run marker set, importing the module does not read .env -- no webhook comes back" `
        ($during -match 'HOOK=False' -and $during -match 'PLAIN=(\r?\n|$)') $during
    $outside = & $probe $false
    Assert-True "outside a test run the module still reads .env, as a person's shell expects" `
        ($outside -match 'HOOK=True' -and $outside -match 'PLAIN=seen') $outside
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $envPkg -Recurse -Force -ErrorAction SilentlyContinue }

# -- The Sent line -----------------------------------------------------------------
# One writer for "Sent to <recipient>: <date>", shared by -Session and the web
# button through consts.json.

Write-Host ""
Write-Host "-- The Sent line -----------------------------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox
try {
    . (Join-Path $sandbox 'Scripts/Add-SentLine.ps1')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $rec = Join-Path $sandbox 'record.md'
    [System.IO.File]::WriteAllText($rec, "# 2026-09-22`n`n## Agenda`n`n- one`n`n## Sent`n`n## Notes`n`nx`n", $utf8NoBom)
    $written = Add-P20SentLine -Path $rec -Recipient 'manager' -Date '2026-09-22'
    $after = [System.IO.File]::ReadAllText($rec)
    Assert-True "the line is the contract's shape" ($written -eq 'Sent to manager: 2026-09-22') $written
    Assert-True "it lands under ## Sent, before the next heading" ($after -match "## Sent`n`nSent to manager: 2026-09-22`n`n## Notes") $after
    $null = Add-P20SentLine -Path $rec -Recipient 'manager' -Date '2026-09-23'
    $after = [System.IO.File]::ReadAllText($rec)
    Assert-True "a second send is a second line under the first" ($after -match "Sent to manager: 2026-09-22`nSent to manager: 2026-09-23`n`n## Notes") $after
    $bare = Join-Path $sandbox 'bare.md'
    [System.IO.File]::WriteAllText($bare, "# 2026-09-22`r`n`r`n## Agenda`r`n`r`n- one`r`n", $utf8NoBom)
    $null = Add-P20SentLine -Path $bare -Recipient 'team' -Date '2026-09-22'
    $bareAfter = [System.IO.File]::ReadAllText($bare)
    Assert-True "a record with no ## Sent gets the section at the end" ($bareAfter -match "## Sent`r`n`r`nSent to team: 2026-09-22`r`n$") $bareAfter
    Assert-True "and keeps its CRLF endings" (-not ($bareAfter -replace "`r`n", '').Contains("`n")) $bareAfter
    $none = Invoke-Send -Root $sandbox -Arguments @('manager', 'hello', '-Session', 'no-such.md') -Environment @{ TEAMS_WEBHOOK_MANAGER = 'https://example.invalid/hook' }
    Assert-Contains "-Session is accepted, and a failed send writes nothing" $none.Output 'Could not reach the agent'
    Assert-True "no record was touched by a send that did not happen" (-not (Test-Path (Join-Path $sandbox 'no-such.md')))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# -- Arguments ------------------------------------------------------------------

Write-Host ""
Write-Host "-- Arguments ---------------------------------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox
try {
    $result = Invoke-Send -Root $sandbox -Arguments @()
    Assert-Contains "no arguments reports both are required" $result.Output 'are both required'
    Assert-True "no arguments exits non-zero" ($result.ExitCode -ne 0) "exit $($result.ExitCode)"

    $result = Invoke-Send -Root $sandbox -Arguments @('manager')
    Assert-Contains "a recipient with no message is refused" $result.Output 'are both required'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# -- Gate 2: the webhook environment variable ------------------------------------

Write-Host ""
Write-Host "-- Gate 2: the webhook variable ---------------------------" -ForegroundColor Cyan

$sandbox = New-SendSandbox
try {
    $result = Invoke-Send -Root $sandbox -Arguments @('manager', 'a line') -Environment @{}
    Assert-Contains "an unset webhook says nothing was sent" $result.Output 'Not sent'
    Assert-Contains "an unset webhook NAMES the variable" $result.Output 'TEAMS_WEBHOOK_MANAGER'
    Assert-Contains "an unset webhook says where the URL belongs: .env in the package root" $result.Output '.env in the package root (copy .env.example)'
    Assert-Contains "an unset webhook says the agent must be restarted" $result.Output 'Web -Stop, '
    # The whole point of gate 2: a missing webhook is a configuration fact, so
    # it is reported and the command succeeds. Erroring would make an unset
    # variable look like a broken toolkit.
    Assert-True "an unset webhook exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
    Assert-NotContains "an unset webhook never reaches the agent" $result.Output 'Could not reach the agent'

    # A recipient whose entry names no variable falls back to the convention.
    $sandbox2 = New-SendSandbox -Recipients @{
        'team-channel' = @{ type = 'channel'; display = 'Team' }
    }
    try {
        $result = Invoke-Send -Root $sandbox2 -Arguments @('team-channel', 'a line') -Environment @{}
        Assert-Contains "a recipient with no webhookEnv uses the TEAMS_WEBHOOK_<KEY> convention" `
            $result.Output 'TEAMS_WEBHOOK_TEAM_CHANNEL'
    }
    finally { Remove-SendSandbox $sandbox2 }

    # Gate 2 met: the command gets past the variable check and on to the agent,
    # which is not there. That failure is the proof the gate opened.
    $result = Invoke-Send -Root $sandbox -Arguments @('manager', 'a line') `
        -Environment @{ TEAMS_WEBHOOK_MANAGER = 'set-for-this-test' }
    Assert-NotContains "a set webhook passes gate 2" $result.Output 'Not sent -- no webhook configured'
    Assert-Contains "past gate 2 it talks to the agent" $result.Output 'Could not reach the agent'
    Assert-Contains "an absent agent names the command that starts one" $result.Output 'Agent'

    # TEAMS_WEBHOOK_URL is the engine's catch-all, and gate 2 must agree with it
    # or the CLI would refuse a send the engine would have made.
    $result = Invoke-Send -Root $sandbox -Arguments @('manager', 'a line') `
        -Environment @{ TEAMS_WEBHOOK_URL = 'set-for-this-test' }
    Assert-NotContains "the catch-all variable also satisfies gate 2" $result.Output 'Not sent -- no webhook configured'

    # A recipient this config does not know is the engine's to explain -- it has
    # the whole registry and a better message than a guess from here.
    $result = Invoke-Send -Root $sandbox -Arguments @('nobody', 'a line') -Environment @{}
    Assert-NotContains "an unknown recipient is not answered with a webhook name" $result.Output 'TEAMS_WEBHOOK_NOBODY'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-SendSandbox $sandbox }

# -- The wrapper ------------------------------------------------------------------
# The loader is not on this branch yet, so the command file is dot-sourced by
# hand with the module helpers stubbed -- which is also the smallest statement
# of what the wrapper actually needs from the module.

Write-Host ""
Write-Host "-- The wrapper -------------------------------------------" -ForegroundColor Cyan

$stubs = @"
function global:Show-CommandHelp { param([string]`$CommandName) Write-Host "HELP:`$CommandName" }
function global:Write-ToolkitLog { param(`$Type, `$Source, `$Detail) Write-Host "LOG:`$Type/`$Source" }
function global:Write-CliError { param(`$Message, `$Hint) Write-Host "ERR:`$Message" }
function global:Get-CliPrefix { return 'tk' }
# The refusal contract's guard, the real one -- the loader dot-sources it too.
. '$guardFile'
. '$commandFile'
"@

$result = Invoke-PwshText "$stubs; if (Get-Command Send-P20TeamsMessage -ErrorAction SilentlyContinue) { 'DEFINED' }"
Assert-Contains "dot-sourcing the command file defines Send-P20TeamsMessage" $result 'DEFINED'

$result = Invoke-PwshText "$stubs; Send-P20TeamsMessage -Help"
Assert-Contains "-Help renders from the shared help table" $result 'HELP:SendTeams'

$result = Invoke-PwshText "$stubs; `$global:P20CommunicationRoot"
# The root is the package, wherever the package is checked out -- the assertion
# must not depend on the checkout's path containing the word "communication".
$expectedRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Assert-Contains "the command file derives the package root from its own location" $result $expectedRoot

$result = Invoke-PwshText "$stubs; Send-P20TeamsMessage"
Assert-Contains "a script failure is surfaced through Write-CliError" $result 'ERR:'
Assert-Contains "a script failure is logged" $result 'LOG:ERR'

# -- Summary -----------------------------------------------------------------------

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
