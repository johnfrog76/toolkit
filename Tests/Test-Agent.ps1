<#
.SYNOPSIS
    Precondition, lifecycle-guard and logging tests for Start-Agent.ps1.
.DESCRIPTION
    The command starts a uvicorn process. These tests never do -- every case
    below stops at a guard, so nothing binds a socket and nothing is left
    running. What they cover is the part that regresses silently:

      - -Status and -Stop are safe no-ops when nothing is running: they say so,
        exit 0 and log Type CMD. Those two branches are most of the command.
      - -Status names the port it WOULD use, and reads it from config
        web.agentPort -- asserted by patching that key in the sandbox, because
        a port read from a file is the one claim this script makes that a
        hardcoded 4100 would satisfy just as well until the day it does not.
      - A missing prerequisite fails with a readable Write-CliError, not a raw
        exception, logs Type ERR and exits non-zero.
      - Messages carry the INVOKING prefix, not a hardcoded one. The sandbox
        runs with a deliberately unusual prefix so a hardcoded 'tk' would fail.
      - The config entry advertises the surface the script implements.

    Each case runs the script in an isolated child pwsh against a sandbox that
    mirrors the repo's shape (Scripts/ + config.default.json), with its own
    scratch log, so nothing touches the real repo's PID file or usage log.

    -ClearPath empties PATH inside the child after the shims are defined, so
    `Get-Command python3` genuinely fails without uninstalling anything.

    Run:  pwsh -File Tests/Test-Agent.ps1
    Or:   {cliPrefix}TestToolkit -Agent
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Justification = 'The ps here is /bin/ps, in the block that runs only off Windows, where ps is not an alias.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $testDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/Start-Agent.ps1'
$configPath = Join-Path $pkgRoot 'config.default.json'
if (-not (Test-Path $targetScript)) {
    Write-Error "Start-Agent.ps1 not found at $targetScript"
    return
}

# Deliberately not 'tk'. Every message the script prints about itself has to
# come back with this prefix or it is hardcoding one.
$script:Prefix = 'zz'

# -- Harness -------------------------------------------------------------------

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail)
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

# Runs Start-Agent.ps1 in a child pwsh against a throwaway copy of the package's
# shape. Returns { Output, ExitCode, LogText }.
#
# The module is NOT imported: the script is written to work standalone (it
# defines its own Get-CliPrefix and Write-CliError fallbacks) and that is the
# path a child shell actually takes. Only the two things the test needs to
# observe are shimmed -- the prefix, and the log.
function Invoke-Agent {
    param(
        [string[]]$ScriptArgs = @(),
        [switch]$ClearPath,
        [int]$AgentPort = 0,
        # Seeds .agent.pid so the script's "already running" branch is reached
        # without starting anything. Pass a PID that is genuinely alive -- the
        # test runner's own is the safe one, and that branch exits before any
        # code that could stop a process.
        [int]$SeedPid = 0,
        # PowerShell injected into the child BEFORE the script runs. The port
        # and health probes are declared behind Get-Command guards precisely so
        # the suite can replace them: there is no second agent here, and nothing
        # in these tests may touch a real socket.
        [string]$Preamble = ''
    )

    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agent-test-$([guid]::NewGuid())"
    try {
        $sandboxScripts = Join-Path $sandbox 'Scripts'
        New-Item -ItemType Directory -Path $sandboxScripts -Force | Out-Null
        Copy-Item $targetScript (Join-Path $sandboxScripts 'Start-Agent.ps1')
        # Dot-sourced by the script at load; a sandbox without it is a sandbox
        # that fails for the wrong reason.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-Python.ps1') (Join-Path $sandboxScripts 'Resolve-Python.ps1')
        # Dot-sourced at load: Get-CliPrefix and Write-CliError for a run with no module.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Initialize-CliFallbacks.ps1') (Join-Path $sandboxScripts 'Initialize-CliFallbacks.ps1')
        # Dot-sourced at load: the OS port probe both launchers share.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-PortListeners.ps1') (Join-Path $sandboxScripts 'Get-PortListeners.ps1')
        # Dot-sourced by -Help: the shared config-help renderer.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Show-ConfigHelp.ps1') (Join-Path $sandboxScripts 'Show-ConfigHelp.ps1')
        # Dot-sourced at load: the one hub resolver, which answers "which hub is
        # this checkout configured for" for -Status's is-it-ours comparison.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1') (Join-Path $sandboxScripts 'Resolve-HubConfig.ps1')
        # ...and the one warning for a config.local.json that will not parse, which it dot-sources.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Write-ConfigParseWarning.ps1') (Join-Path $sandboxScripts 'Write-ConfigParseWarning.ps1')
        # Dot-sourced at load by both launchers: the one agent-port resolver, and
        # the contract reader it needs for the variable's name -- with consts.json
        # at the sandbox root, where Get-Consts.ps1 looks for it.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-AgentPort.ps1') (Join-Path $sandboxScripts 'Get-AgentPort.ps1')
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1') (Join-Path $sandboxScripts 'Get-Consts.ps1')
        Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $sandbox 'consts.json')

        # The real config, optionally with agentPort patched, so -Help and the
        # port both read what the shipped file actually says.
        $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($AgentPort -gt 0) { $cfg.web.agentPort = $AgentPort }
        $cfg | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $sandbox 'config.default.json') -Encoding UTF8

        $logPath = Join-Path $sandbox 'test-usage.log'

        if ($SeedPid -gt 0) {
            Set-Content -Path (Join-Path $sandbox '.agent.pid') -Value "$SeedPid" -Encoding UTF8
        }

        $argLine = ($ScriptArgs | ForEach-Object { if ($_ -match '^-') { $_ } else { "'$_'" } }) -join ' '
        $clearPathLine = if ($ClearPath) { "`$env:PATH = ''" } else { '' }
        $invokePath = (Join-Path $sandboxScripts 'Start-Agent.ps1') -replace "'", "''"
        $body = @"
`$env:P20_TEST_LOG = '$($logPath -replace "'", "''")'
# A quiet port, by default, in every case. Otherwise the suite reads the REAL
# machine: an agent running on 4100 while the tests run would make -Status
# report a listener and turn assertions about a quiet machine red. A case that
# is about a listener defines its own stubs in -Preamble, which is injected
# after these and wins.
function global:Get-AgentPortListenerIds { param([int]`$Port) return @() }
function global:Get-AgentProcessName { param([int]`$ProcessId) return '' }
function global:Get-AgentHealthReport { param([int]`$Port) return @{ Answered = `$false; PromptsRoot = ''; Status = '' } }
# NEVER a real kill: .agent.pid is seeded with the test runner's own PID, and
# a hub mismatch restarts the recorded agent. The stub prints what it
# would have stopped and marks it gone, so a listener stub can stop answering.
`$global:StubStopped = @()
function global:Stop-AgentProcess { param([int]`$ProcessId) `$global:StubStopped += `$ProcessId; Write-Host "STUB-STOPPED `$ProcessId" }
function global:Get-CliPrefix { return '$script:Prefix' }
function global:Write-ToolkitLog {
    param([string]`$Type, [string]`$Source, [string]`$Detail)
    Add-Content -Path `$env:P20_TEST_LOG -Value "`$Type``t`$Source``t`$Detail"
}
$clearPathLine
$Preamble
& '$invokePath' $argLine
exit `$LASTEXITCODE
"@
        $runner = Join-Path $sandbox 'run.ps1'
        Set-Content -Path $runner -Value $body -Encoding UTF8

        $output = & pwsh -NoProfile -File $runner 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $logText = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }

        return [pscustomobject]@{ Output = $output; ExitCode = $exitCode; LogText = $logText }
    }
    finally {
        Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Agent Launcher Tests" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# -- -Status with nothing running ----------------------------------------------

Write-Host "-- -Status (nothing running) --------------------------" -ForegroundColor Cyan

$r = Invoke-Agent -ScriptArgs @('-Status')
Assert-True '-Status (down) reports not running' ($r.Output -match 'is not running') $r.Output
Assert-True '-Status (down) exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Status (down) logs CMD' ($r.LogText -match "^CMD`t") $r.LogText
Assert-True '-Status (down) logs the invoking prefix' ($r.LogText -match "$($script:Prefix)Agent") $r.LogText
Assert-True '-Status (down) starts no process' ($r.Output -notmatch 'PID \d') $r.Output

Write-Host ""

# -- The port comes from config ------------------------------------------------

Write-Host "-- web.agentPort is read, not hardcoded ---------------" -ForegroundColor Cyan

$r = Invoke-Agent -ScriptArgs @('-Status')
Assert-True '-Status names the shipped default port (4100)' ($r.Output -match '4100') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Status') -AgentPort 4321
Assert-True 'a patched web.agentPort is what -Status reports' ($r.Output -match '4321') $r.Output
Assert-True 'the old port is not still being printed' ($r.Output -notmatch '4100') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Status', '-Port', '4999') -AgentPort 4321
Assert-True '-Port overrides config for one run' ($r.Output -match '4999') $r.Output

Write-Host ""

# -- -Stop with nothing running ------------------------------------------------

Write-Host "-- -Stop (nothing running) ----------------------------" -ForegroundColor Cyan

$r = Invoke-Agent -ScriptArgs @('-Stop')
Assert-True '-Stop (down) reports nothing to stop' ($r.Output -match 'nothing to stop') $r.Output
Assert-True '-Stop (down) exits 0 (idempotent)' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Stop (down) logs CMD' ($r.LogText -match "^CMD`t") $r.LogText

Write-Host ""

# -- An already-running agent: instruction vs. reuse ---------------------------
# Web -Dev calls this script, so "Stop it first with tkAgent -Stop" was printed
# in the middle of a command that goes on to need the agent it just told you to
# kill. -Reuse is the composition switch Start-Web.ps1 passes.

Write-Host "-- Already running (direct vs. -Reuse) ----------------" -ForegroundColor Cyan

$r = Invoke-Agent -ScriptArgs @() -SeedPid $PID
Assert-True 'a direct start on a running agent says so' ($r.Output -match 'already running') $r.Output
Assert-True 'a direct start still gives the stop instruction' ($r.Output -match 'Stop it first') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Reuse') -SeedPid $PID
Assert-True '-Reuse reports the agent as reused' ($r.Output -match 'reusing it') $r.Output
Assert-True '-Reuse does not tell you to stop the agent it needs' ($r.Output -notmatch 'Stop it first') $r.Output
Assert-True '-Reuse exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Reuse starts nothing' ($r.Output -notmatch 'Starting the agent') $r.Output

Write-Host ""

# -- Missing prerequisite ------------------------------------------------------

Write-Host "-- Missing prerequisite (no python on PATH) -----------" -ForegroundColor Cyan

$r = Invoke-Agent -ScriptArgs @() -ClearPath
Assert-True 'python missing gives a readable error' ($r.Output -match 'Error: Python 3 not found') $r.Output
Assert-True 'python missing names what it tried' ($r.Output -match 'tried python') $r.Output
Assert-True 'python missing points at agent/requirements.txt' ($r.Output -match 'agent/requirements\.txt') $r.Output
Assert-True 'python missing shows no raw exception text' ($r.Output -notmatch 'System\.Management\.Automation') $r.Output
Assert-True 'python missing logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'python missing exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"

Write-Host ""

# -- Which Python, and is it real ----------------------------------------------
# `python3` on Windows is normally the Microsoft Store App Execution Alias: it
# is on PATH, Get-Command finds it, and it runs nothing. A cold start on Windows
# followed the docs, typed `python3`, and got the Store's advertisement.
#
# So presence is not evidence -- Resolve-P20Python RUNS each candidate and takes
# the first that reports major version 3.
#
# The interpreters are stubbed, which is the only way to assert the Windows
# ordering from a Mac and the only way to assert "the stub is skipped" without a
# machine that has one.

Write-Host "-- Resolve-Python (stubbed interpreters) --------------" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Resolve-Python.ps1')

# Each entry is name -> the version it reports, or '' for a stub that prints the
# Store's message on stderr and runs nothing.
function New-PythonStubDir {
    param([hashtable]$Interpreters)

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "p20-py-stub-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($name in $Interpreters.Keys) {
        $version = $Interpreters[$name]
        if ($version) {
            $sh = "#!/bin/sh`necho `"$version`"`n"
            $cmd = "@echo off`r`necho $version`r`n"
        }
        else {
            $sh = "#!/bin/sh`necho 'Python was not found; run without arguments to install from the Microsoft Store' 1>&2`nexit 9009`n"
            $cmd = "@echo off`r`necho Python was not found; run without arguments to install from the Microsoft Store 1>&2`r`nexit /b 9009`r`n"
        }
        # Both forms, so the same test runs on either host: Windows resolves the
        # .cmd through PATHEXT, everything else runs the extensionless script.
        $shPath = Join-Path $dir $name
        [System.IO.File]::WriteAllText($shPath, $sh)
        [System.IO.File]::WriteAllText((Join-Path $dir "$name.cmd"), $cmd)
        if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod '+x' $shPath }
    }
    return $dir
}

# The probe runs in a child shell whose PATH is ONLY the stub directory, so the
# machine's real interpreters cannot answer for it.
function Invoke-PythonProbe {
    param([string]$StubDir, [bool]$Windows)

    $resolver = (Join-Path $pkgRoot 'Scripts/Resolve-Python.ps1') -replace "'", "''"
    $body = @"
`$env:PATH = '$($StubDir -replace "'", "''")'
. '$resolver'
`$r = Resolve-P20Python -Windows `$$($Windows.ToString().ToLower())
if (`$null -eq `$r) { 'NONE' } else { "`$(`$r.Display)|`$(`$r.Version)" }
"@
    # A file of its own per call: the case asserts on the probe twice, and the
    # second write used to hit the first run's script while Windows PowerShell 5.1
    # (or the antivirus scanning it) still held it open.
    $runner = Join-Path $StubDir "probe-$([guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
    Set-Content -Path $runner -Value $body -Encoding UTF8
    return (& pwsh -NoProfile -File $runner 2>&1 | Out-String).Trim()
}

$stub = New-PythonStubDir @{ python = '3.12.10'; python3 = ''; py = '3.12.10' }
try {
    Assert-True 'on Windows, a working python beats the python3 stub' `
        ((Invoke-PythonProbe -StubDir $stub -Windows $true) -eq 'python|3.12.10') `
        (Invoke-PythonProbe -StubDir $stub -Windows $true)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $stub -Recurse -Force -ErrorAction SilentlyContinue }

$stub = New-PythonStubDir @{ python3 = ''; py = '3.12.10' }
try {
    Assert-True 'on Windows with no python, the launcher answers as "py -3"' `
        ((Invoke-PythonProbe -StubDir $stub -Windows $true) -eq 'py -3|3.12.10') `
        (Invoke-PythonProbe -StubDir $stub -Windows $true)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $stub -Recurse -Force -ErrorAction SilentlyContinue }

$stub = New-PythonStubDir @{ python3 = '' }
try {
    Assert-True 'the Store stub alone resolves to nothing, not to itself' `
        ((Invoke-PythonProbe -StubDir $stub -Windows $true) -eq 'NONE') `
        (Invoke-PythonProbe -StubDir $stub -Windows $true)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $stub -Recurse -Force -ErrorAction SilentlyContinue }

$stub = New-PythonStubDir @{ python = '2.7.18'; python3 = '3.12.10' }
try {
    Assert-True 'a python that is Python 2 is skipped, not named' `
        ((Invoke-PythonProbe -StubDir $stub -Windows $true) -eq 'python3|3.12.10') `
        (Invoke-PythonProbe -StubDir $stub -Windows $true)
    Assert-True 'off Windows, python3 is tried first' `
        ((Invoke-PythonProbe -StubDir $stub -Windows $false) -eq 'python3|3.12.10') `
        (Invoke-PythonProbe -StubDir $stub -Windows $false)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $stub -Recurse -Force -ErrorAction SilentlyContinue }

Assert-True 'the candidate order is Windows-specific' `
    (((Get-P20PythonCandidates -Windows $true)[0].Exe -eq 'python') -and
     ((Get-P20PythonCandidates -Windows $false)[0].Exe -eq 'python3'))

Write-Host ""

# -- -Help ---------------------------------------------------------------------

Write-Host "-- -Help comes from config ----------------------------" -ForegroundColor Cyan

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = $config.commands.Agent

$r = Invoke-Agent -ScriptArgs @('-Help')
Assert-True '-Help exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Help prints the config description' ($r.Output -match [regex]::Escape($entry.description.Substring(0, [Math]::Min(40, $entry.description.Length)))) $r.Output
Assert-True '-Help renders the invoking prefix, not a literal placeholder' ($r.Output -match "$($script:Prefix)Agent" -and $r.Output -notmatch '\{cliPrefix\}') $r.Output
Assert-True '-Help describes each switch' ($r.Output -match 'Switches:') $r.Output
Assert-True '-Help describes -Status in words' ($r.Output -match '(?m)^\s+-Status\s+\S') $r.Output
Assert-True '-Help carries the notes' ($r.Output -match 'Notes:') $r.Output
Assert-True '-Help names a URL to open' ($r.Output -match 'http://localhost:\d+') $r.Output
Assert-True '-Help leaves no port token unresolved' ($r.Output -notmatch '\{agentPort\}' -and $r.Output -notmatch '\{devPort\}') $r.Output
Assert-True '-Help starts nothing' ($r.Output -notmatch 'Starting the agent') $r.Output

Write-Host ""

# -- The config entry matches the script ---------------------------------------

Write-Host "-- Config entry ---------------------------------------" -ForegroundColor Cyan

Assert-True 'config: Agent entry exists' ($null -ne $entry)
Assert-True 'config: category is org' ($entry.category -eq 'org')
Assert-True 'config: usage advertises -Stop' ($entry.usage -match '-Stop')
Assert-True 'config: usage advertises -Status' ($entry.usage -match '-Status')
Assert-True 'config: usage advertises -Port' ($entry.usage -match '-Port')
Assert-True 'config: usage advertises -Dev' ($entry.usage -match '-Dev')
Assert-True 'config: at least one example' ($entry.examples -and @($entry.examples).Count -gt 0)

# Every switch the config advertises has to exist on the script, or -Help is a
# promise the binder will refuse.
$scriptParams = (Get-Command $targetScript).Parameters.Keys
foreach ($switch in @('Stop', 'Status', 'Dev', 'Port', 'Reuse', 'Help')) {
    Assert-True "script declares -$switch" ($scriptParams -contains $switch)
}

Write-Host ""

# -- A listener this command did not start -------------------------------------
# On a machine migrating from the predecessor package, its agent is already on
# 0.0.0.0:4100 serving a different hub. Windows allows this script's 127.0.0.1
# bind beside that wildcard one, so `tkAgent` said "Agent started" and localhost
# resolved to the more specific socket -- and after `tkAgent -Stop`, -Status
# denied a listener that curl could still reach, from the other package's hub.
#
# The probes are stubbed: there is no second agent here, and no socket is
# touched. What is asserted is what the launcher does with each answer.

Write-Host "-- A foreign listener is named, not stepped over ------" -ForegroundColor Cyan

# The hub these shims pretend this checkout is configured for. Absolute ON THIS
# HOST, because the one hub resolver (Get-P20PromptsRoot) reads a RELATIVE
# promptsRoot against the package root -- and a Windows drive letter is not an
# absolute path on macOS, so a hard-coded `C:\ws\...` would be joined onto the
# sandbox and then never match what the stubbed listener reports. The agent's
# _resolve_root has exactly this rule, which is why it is not worked around.
$fixtureHub = '/ws/toolkit-hub'
if ([System.IO.Path]::IsPathRooted('C:\ws\toolkit-hub')) { $fixtureHub = 'C:\ws\toolkit-hub' }  # export:example
# The same hub as the listener would report it: forward slashes, trailing one.
# Test-SameHub has to see through both, and that is what the reuse case pins.
$fixtureHubReported = ($fixtureHub -replace '\\', '/').TrimEnd('/') + '/'

# The report's own shape: another agent, another hub.
$foreignShim = @'
$env:PROMPTS_ROOT = '__HUB__'
function global:Get-AgentPortListenerIds { param([int]$Port) if ($Port -eq 4100) { return @(15976) } return @() }
function global:Get-AgentProcessName { param([int]$ProcessId) return 'python.exe' }
function global:Get-AgentHealthReport {
    param([int]$Port)
    return @{ Answered = $true; PromptsRoot = 'C:\ws\prompts'; Status = 'ok' }  # export:example
}
'@
$foreignShim = $foreignShim.Replace('__HUB__', $fixtureHub)

$r = Invoke-Agent -ScriptArgs @('-Status') -Preamble $foreignShim
Assert-True '-Status names the foreign listener''s PID' ($r.Output -match '15976') $r.Output
Assert-True '-Status names the process' ($r.Output -match 'python\.exe') $r.Output
Assert-True '-Status names the hub it serves' ($r.Output -match 'C:\\ws\\prompts') $r.Output  # export:example
Assert-True '-Status says it is not this package''s agent' ($r.Output -match 'not this package') $r.Output
Assert-True '-Status suggests another port' ($r.Output -match '-Port') $r.Output
Assert-True '-Status still reports our own agent as not running' ($r.Output -match 'Agent is not running') $r.Output
Assert-True '-Status with a foreign listener exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Agent -ScriptArgs @() -Preamble $foreignShim
Assert-True 'start refuses to run beside it' ($r.Output -match 'Error:') $r.Output
Assert-True 'the refusal names the port and the PID' ($r.Output -match 'Port 4100' -and $r.Output -match '15976') $r.Output
Assert-True 'the refusal names the hub the other one serves' ($r.Output -match 'C:\\ws\\prompts') $r.Output  # export:example
Assert-True 'the refusal offers -Port' ($r.Output -match '-Port <n>') $r.Output
Assert-True 'the refusal is a stated one (exit 2)' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'the refusal logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'nothing was started' ($r.Output -notmatch 'Starting the agent') $r.Output

# A listener that answers nothing at all is still a listener.
$silentShim = @'
$env:PROMPTS_ROOT = '__HUB__'
function global:Get-AgentPortListenerIds { param([int]$Port) if ($Port -eq 4100) { return @(4242) } return @() }
function global:Get-AgentProcessName { param([int]$ProcessId) return 'node' }
function global:Get-AgentHealthReport { param([int]$Port) return @{ Answered = $false; PromptsRoot = ''; Status = '' } }
'@
$silentShim = $silentShim.Replace('__HUB__', $fixtureHub)

$r = Invoke-Agent -ScriptArgs @('-Status') -Preamble $silentShim
Assert-True '-Status reports a listener that does not answer /api/health' ($r.Output -match 'does not answer /api/health') $r.Output
Assert-True '-Status names that one too' ($r.Output -match '4242') $r.Output

$r = Invoke-Agent -ScriptArgs @() -Preamble $silentShim
Assert-True 'start refuses beside a silent listener' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'the refusal says it is not an agent' ($r.Output -match 'not an agent') $r.Output

# An agent on OUR hub that this command did not record: reused and named, not
# refused. This is the case a lost PID file produces, and refusing it would
# break `{prefix}Web -Dev` on a machine where one is already up.
$sameHubShim = @'
$env:PROMPTS_ROOT = '__HUB__'
function global:Get-AgentPortListenerIds { param([int]$Port) if ($Port -eq 4100) { return @(5150) } return @() }
function global:Get-AgentProcessName { param([int]$ProcessId) return 'python3' }
function global:Get-AgentHealthReport {
    param([int]$Port)
    return @{ Answered = $true; PromptsRoot = '__HUB_REPORTED__'; Status = 'ok' }
}
'@
$sameHubShim = $sameHubShim.Replace('__HUB__', $fixtureHub).Replace('__HUB_REPORTED__', $fixtureHubReported)

$r = Invoke-Agent -ScriptArgs @() -Preamble $sameHubShim
Assert-True 'an agent on this hub is reused, not refused' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True 'reuse names the PID it found' ($r.Output -match '5150') $r.Output
Assert-True 'reuse says -Stop will not stop it' ($r.Output -match 'will not stop it') $r.Output
Assert-True 'reuse starts nothing' ($r.Output -notmatch 'Starting the agent') $r.Output

# -- The port is the truth, the PID file a cache of it ---------------
# /api/health reports package_root, so the launcher can tell THIS checkout's
# agent (stop it, restart it) from another package's (name it, leave it). The
# sandbox is the checkout here: run.ps1 sits at its root, so $PSScriptRoot in
# the preamble is exactly the path Start-Agent.ps1 computes for itself.
$ownShim = @'
$env:PROMPTS_ROOT = '__HUB__'
$global:Sandbox = $PSScriptRoot
function global:Get-AgentPortListenerIds { param([int]$Port) if ($Port -eq 4100 -and $global:StubStopped -notcontains 7373) { return @(7373) } return @() }
function global:Get-AgentProcessName { param([int]$ProcessId) return 'python3' }
function global:Get-AgentHealthReport {
    param([int]$Port)
    if ($global:StubStopped -contains 7373) { return @{ Answered = $false; PromptsRoot = ''; Status = ''; PackageRoot = '' } }
    return @{ Answered = $true; PromptsRoot = '__SERVED__'; Status = 'ok'; PackageRoot = $global:Sandbox }
}
'@
$ownSameHub = $ownShim.Replace('__HUB__', $fixtureHub).Replace('__SERVED__', $fixtureHubReported)
$ownOtherHub = $ownShim.Replace('__HUB__', $fixtureHub).Replace('__SERVED__', '/somewhere/the-real-hub')

$r = Invoke-Agent -ScriptArgs @('-Stop') -Preamble $ownSameHub
Assert-True '#73: -Stop stops this checkout''s agent that another shell started' ($r.Output -match 'STUB-STOPPED 7373') $r.Output
Assert-True '#73: -Stop says whose it was' ($r.Output -match 'started from another shell') $r.Output
Assert-True '#73: -Stop does not say "nothing to stop" about a live listener' ($r.Output -notmatch 'nothing to stop') $r.Output
Assert-True '#73: -Stop exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Agent -ScriptArgs @('-Stop') -Preamble $foreignShim
Assert-True '#73: -Stop names another package''s agent' ($r.Output -match '15976' -and $r.Output -match 'not this checkout') $r.Output
Assert-True '#73: -Stop leaves another package''s agent alone' ($r.Output -notmatch 'STUB-STOPPED') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Status') -Preamble $ownSameHub
Assert-True '#73: -Status says -Stop will stop this checkout''s agent' ($r.Output -match 'this checkout' -and $r.Output -match 'will stop it') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Reuse') -Preamble $ownSameHub
Assert-True '#73: this checkout''s agent on the asked-for hub is reused' ($r.ExitCode -eq 0 -and $r.Output -notmatch 'STUB-STOPPED') $r.Output
Assert-True '#73: and the reuse no longer claims -Stop cannot stop it' ($r.Output -match 'will stop it' -and $r.Output -notmatch 'will not stop it') $r.Output

$r = Invoke-Agent -ScriptArgs @('-Reuse') -Preamble $ownOtherHub -ClearPath
Assert-True '#73: an unrecorded agent of ours on another hub is restarted, not reused' ($r.Output -match 'restarting it' -and $r.Output -match 'STUB-STOPPED 7373') $r.Output
Assert-True '#73: the restart names the hub it was serving' ($r.Output -match 'the-real-hub') $r.Output
Assert-True '#73: and then goes on to start one (here: no Python, a stated refusal)' ($r.Output -match 'Python 3 not found' -and $r.ExitCode -eq 2) $r.Output

# The recorded agent: the case the issue hit -- "Agent already running (PID
# 11592) -- reusing it" while PROMPTS_ROOT named a fixture hub.
$recordedShim = @'
$env:PROMPTS_ROOT = '__HUB__'
function global:Get-AgentHealthReport {
    param([int]$Port)
    return @{ Answered = $true; PromptsRoot = '__SERVED__'; Status = 'ok'; PackageRoot = '' }
}
'@
$recordedOther = $recordedShim.Replace('__HUB__', $fixtureHub).Replace('__SERVED__', '/somewhere/the-real-hub')
$recordedSame = $recordedShim.Replace('__HUB__', $fixtureHub).Replace('__SERVED__', $fixtureHubReported)

$r = Invoke-Agent -ScriptArgs @('-Reuse') -SeedPid $PID -Preamble $recordedOther -ClearPath
Assert-True '#73: the recorded agent on another hub is restarted, not reused' ($r.Output -match 'restarting it' -and $r.Output -match "STUB-STOPPED $PID" -and $r.Output -notmatch 'reusing it') $r.Output
Assert-True '#73: the restart names both hubs' ($r.Output -match 'the-real-hub' -and $r.Output -match [regex]::Escape($fixtureHub)) $r.Output

$r = Invoke-Agent -ScriptArgs @('-Reuse') -SeedPid $PID -Preamble $recordedSame
Assert-True '#73: the recorded agent on the asked-for hub is reused' ($r.Output -match 'reusing it' -and $r.Output -notmatch 'STUB-STOPPED') $r.Output
Assert-True '#73: every reuse names the hub it serves' ($r.Output -match 'Serving hub:') $r.Output

# -- The Windows probe answers in a narrowed shell ------------------
# Get-NetTCPConnection is a module cmdlet and does not autoload once PSModulePath
# is limited to one package; netstat is an executable and does. The parser is
# pure, so a Windows transcript is asserted on every host.
. (Join-Path $pkgRoot 'Scripts/Get-PortListeners.ps1')
$netstat = @(
    'Active Connections',
    '',
    '  Proto  Local Address          Foreign Address        State           PID',
    '  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1180',
    '  TCP    127.0.0.1:4100         0.0.0.0:0              LISTENING       11592',
    '  TCP    127.0.0.1:4100         127.0.0.1:52344        ESTABLISHED     11592',
    '  TCP    127.0.0.1:52344        127.0.0.1:4100         ESTABLISHED     20400',
    '  TCP    127.0.0.1:41000        0.0.0.0:0              LISTENING       999',
    "  TCP    [::1]:5174             [::]:0                 ABH$([char]0x00D6)REN          30012",
    '  UDP    0.0.0.0:5353           *:*                                    2222'
)
$ids = @(ConvertFrom-P20Netstat -Lines $netstat -Port 4100)
Assert-True '#73: netstat -- the listener on 4100, once' (($ids -join ',') -eq '11592') ($ids -join ',')
$ids = @(ConvertFrom-P20Netstat -Lines $netstat -Port 5174)
Assert-True '#73: netstat -- an IPv6 listener, under a translated state word' (($ids -join ',') -eq '30012') ($ids -join ',')
$ids = @(ConvertFrom-P20Netstat -Lines $netstat -Port 52344)
Assert-True '#73: netstat -- a client-side port is not a listener' ($ids.Count -eq 0) ($ids -join ',')
$ids = @(ConvertFrom-P20Netstat -Lines $netstat -Port 410)
Assert-True '#73: netstat -- a port is matched whole, not as a prefix' ($ids.Count -eq 0) ($ids -join ',')

# A quiet machine says nothing about the port.
$quietShim = @'
function global:Get-AgentPortListenerIds { param([int]$Port) return @() }
function global:Get-AgentHealthReport { param([int]$Port) return @{ Answered = $false; PromptsRoot = ''; Status = '' } }
'@
$r = Invoke-Agent -ScriptArgs @('-Status') -Preamble $quietShim
Assert-True '-Status says nothing about the port when nothing is on it' ($r.Output -notmatch 'is held by') $r.Output
Assert-True '-Status on a quiet machine still exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

# Web -Status reuses this answer rather than reimplementing it.
$webSourceText = Get-Content (Join-Path $pkgRoot 'Scripts/Start-Web.ps1') -Raw
Assert-True 'Web -Status asks the agent launcher for the agent''s half' ($webSourceText -match '&\s+\$agentScript\s+-Status') 'Start-Web.ps1 does not delegate -Status'

Write-Host ""

# -- The agent's Python test files skip, they do not exit ----------------------
#
# A module-level sys.exit() in a test file escapes into pytest's collector as
# SystemExit and ends the WHOLE session with zero tests -- one missing optional
# dependency taking every other file down with it. The guard is static and so
# runs on a machine with no Python at all; the live proof is `pytest Tests/`
# with a dependency removed.

Write-Host "-- Python test files skip rather than exit ------------" -ForegroundColor Cyan

$pyTestDir = Join-Path $pkgRoot 'Tests'
$pyTestFiles = @(Get-ChildItem -Path $pyTestDir -Filter 'test_*.py' -File | Sort-Object Name)

Assert-True 'the shared import guard ships' (Test-Path (Join-Path $pyTestDir '_skipguard.py')) `
    'Tests/_skipguard.py'

Assert-True 'there are Python test files to check' ($pyTestFiles.Count -gt 0) "found $($pyTestFiles.Count)"

# sys.exit() is legitimate under `if __name__ == "__main__":` -- that is the
# direct-run path. Anything above that line runs at import.
$exitOffenders = @()
foreach ($f in $pyTestFiles) {
    $lines = Get-Content $f.FullName
    $mainAt = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^if\s+__name__\s*==') { $mainAt = $i; break }
    }
    for ($i = 0; $i -lt $mainAt; $i++) {
        if ($lines[$i] -match '^\s*sys\.exit\(') {
            $exitOffenders += "$($f.Name):$($i + 1)"
        }
    }
}
Assert-True 'no test file calls sys.exit() at import scope' ($exitOffenders.Count -eq 0) `
    ($exitOffenders -join '; ')

# Anything that reaches fastapi.testclient depends on httpx, which is a
# requirements-dev line rather than a runtime one -- so it has to be guarded.
$unguarded = @()
foreach ($f in $pyTestFiles) {
    $text = Get-Content $f.FullName -Raw
    if ($text -match 'fastapi\.testclient' -and $text -notmatch 'skip_module') {
        $unguarded += $f.Name
    }
}
Assert-True 'every file importing fastapi.testclient guards the import' ($unguarded.Count -eq 0) `
    ($unguarded -join '; ')

Write-Host ""

# -- The launcher returns to a caller reading it through a PIPE ----------------
#
# `tkAgent` backgrounds the agent and returns -- when its output goes to a
# console or a file. Through a PIPE it used to return only when the agent was
# stopped, because Start-Process with -RedirectStandardOutput goes down
# PowerShell's native CreateProcess path with bInheritHandles = TRUE on Windows:
# the child inherits every inheritable handle the caller holds, including the
# write end of the caller's own stdout pipe, and holds it for its whole life.
# pwsh exits, the launcher has done its job, and the reader never sees EOF.
#
#
# The stand-in interpreter is pwsh, not python: a stub has to be a real
# executable that CreateProcess can start and that lives long enough to hold a
# handle, and the shell running this suite is the only one of those every host
# is guaranteed to have. What is under test is Start-DetachedProcess, which is
# the whole of what changed and what both launchers now call.
#
# The read is the assertion. The test process holds the READ end and waits for
# EOF with a timeout; before the fix that wait ran out.

Write-Host "-- The launch path returns through a pipe -------------" -ForegroundColor Cyan

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agent-pipe-$([guid]::NewGuid())"
$childPid = 0
try {
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'Scripts/Start-Detached.ps1') (Join-Path $sandbox 'Start-Detached.ps1')

    $shell = (Get-Process -Id $PID).Path
    $outLog = Join-Path $sandbox 'agent.log'
    $errLog = Join-Path $sandbox 'agent.err.log'
    $pidFile = Join-Path $sandbox '.agent.pid'

    # The launcher, as Start-Agent.ps1 runs it: dot-source the sibling, start a
    # long-lived child redirected to the two log files, write the PID, print,
    # exit. Nothing here waits for the child.
    $runnerBody = @"
. '$(($sandbox -replace "'", "''"))/Start-Detached.ps1'
`$proc = Start-DetachedProcess -FilePath '$($shell -replace "'", "''")' ``
    -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') ``
    -WorkingDirectory '$(($sandbox -replace "'", "''"))' ``
    -StdOutLog '$(($outLog -replace "'", "''"))' -StdErrLog '$(($errLog -replace "'", "''"))'
`$proc.Id | Set-Content '$(($pidFile -replace "'", "''"))'
Write-Host "  Agent started (PID `$(`$proc.Id))."
"@
    $runner = Join-Path $sandbox 'run.ps1'
    Set-Content -Path $runner -Value $runnerBody -Encoding UTF8

    # A pipe, explicitly: this process keeps the read end and waits for EOF.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $shell
    $psi.Arguments = "-NoProfile -File `"$runner`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $piped = [System.Diagnostics.Process]::Start($psi)
    $readOut = $piped.StandardOutput.ReadToEndAsync()
    $readErr = $piped.StandardError.ReadToEndAsync()

    # 30 seconds is well inside the stand-in child's 30-second life on a slow
    # host and far outside a healthy launch, which is a couple of seconds.
    $returned = [System.Threading.Tasks.Task]::WaitAll(@($readOut, $readErr), 30000)
    $exited = $piped.WaitForExit(5000)

    Assert-True 'the launcher''s output reaches EOF while the child is still running' $returned `
        'the read end never closed -- the child is holding the caller''s pipe'

    $pipedText = ''
    if ($returned) { $pipedText = "$($readOut.Result)$($readErr.Result)" }
    Assert-True 'the launcher exited' $exited
    Assert-True 'and it reported the child it started' ($pipedText -match 'Agent started \(PID \d+\)') $pipedText

    if (Test-Path $pidFile) { $childPid = [int]((Get-Content $pidFile -Raw).Trim()) }
    Assert-True 'the child was still alive when the pipe closed' `
        ($childPid -gt 0 -and $null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) "pid $childPid"
    Assert-True 'the child got its own log files, not the caller''s handles' `
        ((Test-Path $outLog) -and (Test-Path $errLog))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if ($childPid -gt 0) { Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue }
    Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- The child gets a session of its own and a quiet stdin (macOS, Linux) -----
# The same launch path, read back from inside the child: its PID is the one
# the launcher returned (the leader exec'd in place), it is its own group
# leader in a session that is not the launcher's, its stdin is not a terminal,
# the variable handed in with -Environment is set for it and not for us, and an
# argument with a space arrived whole. Windows is the one host this does not
# apply to; CI=true alone covers Vite's shortcuts there, and VERIFY.md carries
# the row.

Write-Host "-- A session of its own, a quiet stdin ----------------" -ForegroundColor Cyan

$isWinHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
if ($isWinHost) {
    Write-Host "  (Windows: no session leader here -- see VERIFY.md, Rows added by a fix)" -ForegroundColor DarkGray
}
else {
    $sandbox2 = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agent-session-$([guid]::NewGuid())"
    $childPid2 = 0
    $hadCI = if (Test-Path Env:CI) { $env:CI } else { $null }
    try {
        New-Item -ItemType Directory -Path $sandbox2 -Force | Out-Null
        Remove-Item -Path Env:CI -ErrorAction SilentlyContinue
        . (Join-Path $pkgRoot 'Scripts/Start-Detached.ps1')
        $out2 = Join-Path $sandbox2 'child.log'
        $err2 = Join-Path $sandbox2 'child.err.log'
        $facts = 'echo pid=$$ pgid=$(ps -o pgid= -p $$ | tr -d " ") ci=$CI; if [ -t 0 ]; then echo stdin=tty; else echo stdin=notty; fi; printf "[%s]" "$@"; echo; sleep 30'
        $proc2 = Start-DetachedProcess -FilePath '/bin/sh' -ArgumentList @('-c', $facts, 'x', 'a b') `
            -WorkingDirectory $sandbox2 -StdOutLog $out2 -StdErrLog $err2 -Environment @{ CI = 'true' }
        $childPid2 = $proc2.Id
        $said = ''
        foreach ($i in 1..50) {
            if (Test-Path $out2) { $said = Get-Content $out2 -Raw }
            if ($said -match 'stdin=' -and $said -match '\]') { break }
            Start-Sleep -Milliseconds 200
        }
        $launcherPgid = ((& ps -o pgid= -p $PID) -join '') -replace '\s', ''
        $childPidSaid = if ($said -match 'pid=(\d+)') { [int]$Matches[1] } else { -1 }
        $childPgid = if ($said -match 'pgid=(\d+)') { [int]$Matches[1] } else { -2 }
        Assert-True 'the PID the launcher returned is the child''s own -- the leader exec''d in place' ($childPidSaid -eq $childPid2) "returned $childPid2, child said $childPidSaid"
        Assert-True 'the child leads its own process group' ($childPgid -eq $childPidSaid) "pid $childPidSaid pgid $childPgid"
        Assert-True 'and that group is not the launcher''s' ("$childPgid" -ne $launcherPgid) "both $launcherPgid"
        Assert-True 'the child''s stdin is not a terminal' ($said -match 'stdin=notty') $said
        Assert-True 'the variable handed in is set for the child' ($said -match 'ci=true') $said
        Assert-True 'and not for the launcher' (-not (Test-Path Env:CI)) "CI=$env:CI"
        Assert-True 'an argument with a space arrives whole' ($said -match '\[a b\]') $said
    }
    finally {
        if ($null -eq $hadCI) { Remove-Item -Path Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $hadCI }
        if ($childPid2 -gt 0) { Stop-Process -Id $childPid2 -Force -ErrorAction SilentlyContinue }
        Remove-Item -Path $sandbox2 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# -- Both launchers go through the one launch path -----------------------------
# The fix is only a fix where it is called from. Start-Web.ps1 starts Vite the
# same way and had the same shape, so the wiring is asserted rather than assumed.

Write-Host "-- One launch path, both launchers --------------------" -ForegroundColor Cyan

$detachedPath = Join-Path $pkgRoot 'Scripts/Start-Detached.ps1'
Assert-True 'the shared launcher ships' (Test-Path $detachedPath)

foreach ($name in @('Start-Agent.ps1', 'Start-Web.ps1')) {
    $text = Get-Content (Join-Path $pkgRoot "Scripts/$name") -Raw
    $codeLines = @($text -split "`r?`n" | Where-Object { $_.TrimStart() -notmatch '^#' })
    # One exception, and only one: opening a URL in the default browser. That
    # starts a DOCUMENT -- no redirection, nothing to wait for, no handles to
    # leak -- which is a different thing from starting a server, and the reason
    # Start-Detached.ps1 exists does not apply to it.
    $bare = @($codeLines | Where-Object { $_ -match '\bStart-Process\b' -and $_ -notmatch '\$Url' })
    $browserOpen = @($codeLines | Where-Object { $_ -match '\bStart-Process\b' -and $_ -match '\$Url' })
    Assert-True "$name calls Start-DetachedProcess" ($text -match 'Start-DetachedProcess')
    Assert-True "$name dot-sources Start-Detached.ps1" ($text -match "Start-Detached\.ps1")
    Assert-True "$name starts no SERVER outside the shared launcher" ($bare.Count -eq 0) ($bare -join ' | ')
    Assert-True "$name starts at most one URL" ($browserOpen.Count -le 1) ($browserOpen -join ' | ')
}

Write-Host ""

# -- A batch shim is not a process image ---------------------------------------
# Windows ships npm as npm.ps1 + npm.cmd + a bash npm, and Start-Process with a
# redirect cannot use either of the first two as a process image. The launcher
# both launchers share is where that is handled, so the agent's side of it is
# asserted here too: the interpreter it resolves is an .exe and must keep going
# through CreateProcess directly, and a .bat interpreter must not.
#
# No Windows here. The shape is what is asserted; a Windows run confirms the launch.

Write-Host "-- The Windows launch shape (shared launcher) ---------" -ForegroundColor Cyan

. $detachedPath

$py = Resolve-DetachedCommand -FilePath 'C:\Python312\python.exe' -ArgumentList @('-m', 'uvicorn', 'agent.app:app', '--port', '4100') -ForWindows  # export:example
Assert-True 'python.exe is launched directly' ($py.FilePath -eq 'C:\Python312\python.exe') $py.FilePath  # export:example
Assert-True 'python.exe keeps every argument, in order' ((@($py.ArgumentList) -join ' ') -eq '-m uvicorn agent.app:app --port 4100') (@($py.ArgumentList) -join ' ')

$shim = Resolve-DetachedCommand -FilePath 'C:\Users\runneradmin\AppData\Roaming\npm\python.bat' -ArgumentList @('-m', 'uvicorn') -ForWindows  # export:example
Assert-True 'a .bat interpreter goes through the command interpreter' ($shim.FilePath -match 'cmd(\.exe)?$') $shim.FilePath
Assert-True 'the shim is quoted inside one /c argument' (@($shim.ArgumentList)[3] -eq '""C:\Users\runneradmin\AppData\Roaming\npm\python.bat" -m uvicorn"') (@($shim.ArgumentList)[3])  # export:example

$posix = Resolve-DetachedCommand -FilePath '/usr/bin/python3' -ArgumentList @('-m', 'uvicorn')
Assert-True 'nothing is wrapped off Windows' ($posix.FilePath -eq '/usr/bin/python3') $posix.FilePath

# The resolver behind it: an Application, never an ExternalScript.
$detachedText = Get-Content $detachedPath -Raw
Assert-True 'Resolve-LaunchExecutable ships beside it' ($detachedText -match 'function Resolve-LaunchExecutable')
Assert-True 'it asks for an Application only' ($detachedText -match '-CommandType Application')

Write-Host ""

# -- Summary -------------------------------------------------------------------

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
exit 0
