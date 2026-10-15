<#
.SYNOPSIS
    Precondition, lifecycle-guard and logging tests for Start-Web.ps1.
.DESCRIPTION
    The command starts Vite, the agent, or a Docker container. These tests start
    none of them: every case below stops at a guard, and the two guards that
    could reach a Start-Process are made to fail first (no npm on PATH, no
    web/node_modules). What is covered:

      - -Status and -Stop are safe no-ops when nothing is running, exit 0, log
        Type CMD, and report BOTH halves -- the dev server and the agent -- so
        the delegation to Start-Agent.ps1 is asserted rather than assumed.
      - A missing prerequisite (npm, node_modules, web/) fails with a readable
        Write-CliError, logs Type ERR, and exits non-zero.
      - A machine with no Docker gets a sentence naming -Dev, not a stack trace.
        That is the single most likely difference on a fresh clone.
      - Messages carry the INVOKING prefix; the sandbox uses an unusual one so a
        hardcoded 'tk' fails.
      - The config entry advertises the surface the script implements.

    Each case runs against a sandbox that mirrors the repo's shape -- Scripts/
    with BOTH launchers, config.default.json, and a web/ directory -- so nothing
    touches the real repo's PID files or usage log.

    Run:  pwsh -File Tests/Test-Web.ps1
    Or:   {cliPrefix}TestToolkit -Web
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $testDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/Start-Web.ps1'
$agentScript = Join-Path $pkgRoot 'Scripts/Start-Agent.ps1'
$detachedScript = Join-Path $pkgRoot 'Scripts/Start-Detached.ps1'
$configPath = Join-Path $pkgRoot 'config.default.json'
if (-not (Test-Path $targetScript)) {
    Write-Error "Start-Web.ps1 not found at $targetScript"
    return
}

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

# Replaces a file the sandbox has just copied in, or one a child shell has just
# read. A virus scanner holds a fresh copy for a moment, and Windows PowerShell 5.1's Set-Content loses that race
# where pwsh 7's does not, so the write tries again before it gives up.
function Set-SandboxStub {
    param([string]$Path, [string]$Value)
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try { Set-Content -Path $Path -Value $Value -Encoding UTF8 -ErrorAction Stop; return }
        catch {
            if ($attempt -eq 20) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

# Runs Start-Web.ps1 in a child pwsh against a throwaway copy of the package's
# shape. Returns { Output, ExitCode, LogText }.
#
# -NoWebFolder omits web/ entirely; -NoModules leaves web/ without node_modules
# (the default, because a sandbox has no install and the guard must catch it);
# -WithModules fakes an install so a later guard can be reached.
# -ClearPath empties PATH after the shims are defined, so `Get-Command npm` and
# `Get-Command docker` both genuinely fail.
function Invoke-Web {
    param(
        [string[]]$ScriptArgs = @(),
        [switch]$ClearPath,
        [switch]$NoWebFolder,
        [switch]$WithModules,
        # PowerShell injected into the child BEFORE the script runs. The port
        # helpers are declared behind Get-Command guards precisely so the suite
        # can replace them: there is no real dev server here, and nothing in
        # these tests may kill a real process.
        [string]$Preamble = '',
        # Writes a web/vite.config.ts declaring this port, so the probe can be
        # shown reading the port rather than hardcoding 5174.
        [int]$VitePort = 0,
        # Replaces Start-Agent.ps1 with a stub that succeeds. The dev path will
        # not go past a failed agent start, and a sandbox has no Python -- so
        # without this the branch that reports an already-running dev server
        # (and opens the browser) is unreachable. The stub starts nothing.
        [switch]$StubAgent,
        # Seeds .web.pid with a live PID so Get-DevServerProcessId answers, and
        # web.log with a URL so Get-DevServerUrl does. The PID is the runner's
        # own: that branch exits before anything could stop a process.
        [int]$SeedDevPid = 0,
        [string]$WebLogUrl = '',
        # Replaces Start-Detached.ps1 with a stub whose launcher starts nothing
        # and prints what it was handed -- including the agent-port variable in
        # its environment. The stub returns the runner's own PID as the "server",
        # so the liveness check passes and nothing is ever stopped.
        [switch]$StubLaunch,
        # Writes a config.local.json patching web.agentPort, so the export can be
        # shown reading the merged config rather than the shipped default.
        [int]$LocalAgentPort = 0,
        # PowerShell run in the child AFTER the script returns, before it exits
        # -- where a case reads back what the script left in the caller's
        # environment (-Fixture must leave nothing behind).
        [string]$Postamble = ''
    )

    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "p20-web-test-$([guid]::NewGuid())"
    try {
        $sandboxScripts = Join-Path $sandbox 'Scripts'
        New-Item -ItemType Directory -Path $sandboxScripts -Force | Out-Null
        Copy-Item $targetScript (Join-Path $sandboxScripts 'Start-Web.ps1')
        # Both, because -Status, -Stop and every start path delegate to it.
        Copy-Item $agentScript (Join-Path $sandboxScripts 'Start-Agent.ps1')
        # -Dev dot-sources it before its first guard: it owns the npm resolver
        # as well as the launch, so a sandbox without it cannot reach either.
        Copy-Item $detachedScript (Join-Path $sandboxScripts 'Start-Detached.ps1')
        # Dot-sourced at load: the OS port probe both launchers share.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-PortListeners.ps1') (Join-Path $sandboxScripts 'Get-PortListeners.ps1')
        # Dot-sourced by -Help: the shared config-help renderer.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Show-ConfigHelp.ps1') (Join-Path $sandboxScripts 'Show-ConfigHelp.ps1')
        # Dot-sourced at load by Start-Agent.ps1: the one hub resolver.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1') (Join-Path $sandboxScripts 'Resolve-HubConfig.ps1')
        # ...and the one warning for a config.local.json that will not parse, which it dot-sources.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Write-ConfigParseWarning.ps1') (Join-Path $sandboxScripts 'Write-ConfigParseWarning.ps1')
        # Dot-sourced at load by both launchers: the one agent-port resolver, and
        # the contract reader it needs for the variable's name -- with consts.json
        # at the sandbox root, where Get-Consts.ps1 looks for it.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-AgentPort.ps1') (Join-Path $sandboxScripts 'Get-AgentPort.ps1')
        Copy-Item (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1') (Join-Path $sandboxScripts 'Get-Consts.ps1')
        # Dot-sourced at load by Start-Agent.ps1: the one interpreter resolver.
        Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-Python.ps1') (Join-Path $sandboxScripts 'Resolve-Python.ps1')
        Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $sandbox 'consts.json')
        Copy-Item $configPath (Join-Path $sandbox 'config.default.json')

        if (-not $NoWebFolder) {
            $webDir = Join-Path $sandbox 'web'
            New-Item -ItemType Directory -Path $webDir -Force | Out-Null
            if ($WithModules) {
                New-Item -ItemType Directory -Path (Join-Path $webDir 'node_modules') -Force | Out-Null
            }
            if ($VitePort -gt 0) {
                Set-Content -Path (Join-Path $webDir 'vite.config.ts') `
                    -Value "export default { server: { port: $VitePort } };" -Encoding UTF8
            }
        }

        if ($StubAgent) {
            $stub = @'
param([switch]$Reuse, [switch]$Stop, [switch]$Status, [switch]$Dev, [int]$Port, [switch]$Help)
Write-Host "  [test] agent stub ($($PSBoundParameters.Keys -join ','))"
# What the agent's LAUNCHER sees -- and so what its child would inherit.
if ($Reuse) { Write-Host "  [test] agent sees marker=[$env:P20_TEST_RUN] root=[$env:PROMPTS_ROOT] space=[$env:P20_ACTIVE_SPACE] features=[$env:P20_FEATURES] webhook=[$env:TEAMS_WEBHOOK_MANAGER]" }
exit 0
'@
            Set-SandboxStub (Join-Path $sandboxScripts 'Start-Agent.ps1') $stub
        }
        if ($StubLaunch) {
            $launchStub = @'
function Resolve-LaunchExecutable { param([string]$Name) return $Name }
function Start-DetachedProcess {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory, [string]$StdOutLog, [string]$StdErrLog)
    Write-Host "  [test] would launch $FilePath $($ArgumentList -join ' ') with P20_AGENT_PORT=$env:P20_AGENT_PORT"
    Write-Host "  [test] launch sees marker=[$env:P20_TEST_RUN] space=[$env:P20_ACTIVE_SPACE] webhook=[$env:TEAMS_WEBHOOK_MANAGER]"
    return [pscustomobject]@{ Id = $PID }
}
# The real pair, not a stand-in: what -Fixture does to the environment is the
# thing under test, and a stub here would assert the stub.
'@
            $launchStub += "`n" + [regex]::Match((Get-Content $detachedScript -Raw), '(?s)function Push-ProcessEnvironment \{.*?\n\}\s*\nfunction Pop-ProcessEnvironment \{.*?\n\}').Value + "`n"
            Set-SandboxStub (Join-Path $sandboxScripts 'Start-Detached.ps1') $launchStub
        }
        if ($LocalAgentPort -gt 0) {
            Set-Content -Path (Join-Path $sandbox 'config.local.json') `
                -Value "{ `"web`": { `"agentPort`": $LocalAgentPort } }" -Encoding UTF8
        }
        if ($SeedDevPid -gt 0) {
            Set-Content -Path (Join-Path $sandbox '.web.pid') -Value "$SeedDevPid" -Encoding UTF8
        }
        if ($WebLogUrl) {
            Set-Content -Path (Join-Path $sandbox 'web.log') -Value "  ->  Local:   $WebLogUrl/" -Encoding UTF8
        }

        $logPath = Join-Path $sandbox 'test-usage.log'

        $argLine = ($ScriptArgs | ForEach-Object { if ($_ -match '^-') { $_ } else { "'$_'" } }) -join ' '
        $clearPathLine = if ($ClearPath) { "`$env:PATH = ''" } else { '' }
        $invokePath = (Join-Path $sandboxScripts 'Start-Web.ps1') -replace "'", "''"
        $body = @"
`$env:P20_TEST_LOG = '$($logPath -replace "'", "''")'
# The agent half runs for real (Start-Agent.ps1), and its -Stop reads
# the port. A quiet agent port by default, and never a real kill: otherwise an
# agent the engineer has running on 4100 turns "-Stop (down)" red. A case about
# a listener defines its own stubs in -Preamble, which comes after these.
function global:Get-AgentPortListenerIds { param([int]`$Port) return @() }
function global:Get-AgentHealthReport { param([int]`$Port) return @{ Answered = `$false; PromptsRoot = ''; Status = ''; PackageRoot = '' } }
function global:Stop-AgentProcess { param([int]`$ProcessId) Write-Host "  [test] would stop agent `$ProcessId" }
function global:Get-CliPrefix { return '$script:Prefix' }
function global:Write-ToolkitLog {
    param([string]`$Type, [string]`$Source, [string]`$Detail)
    Add-Content -Path `$env:P20_TEST_LOG -Value "`$Type``t`$Source``t`$Detail"
}
$clearPathLine
$Preamble
& '$invokePath' $argLine
`$scriptExit = `$LASTEXITCODE
$Postamble
exit `$scriptExit
"@
        $runner = Join-Path $sandbox 'run.ps1'
        Set-Content -Path $runner -Value $body -Encoding UTF8

        # Under 5.1 a child's stderr line (the sandbox's dot-source of a script it
        # does not carry) is a terminating error while Stop is in force.
        $output = & {
            $ErrorActionPreference = 'Continue'
            (& pwsh -NoProfile -File $runner 2>&1 | ForEach-Object { "$_" }) -join "`n"
        }
        $output = "$output`n"
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
Write-Host "  Web Launcher Tests" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# -- -Status with nothing running ----------------------------------------------

Write-Host "-- -Status (nothing running) --------------------------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Status')
Assert-True '-Status (down) reports the dev server is not running' ($r.Output -match 'Dev server is not running') $r.Output
Assert-True '-Status (down) reports the agent too' ($r.Output -match 'Agent is not running') $r.Output
Assert-True '-Status (down) exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Status (down) logs CMD' ($r.LogText -match "^CMD`t") $r.LogText
Assert-True '-Status (down) logs the invoking prefix' ($r.LogText -match "$($script:Prefix)Web") $r.LogText
Assert-True '-Status (down) starts nothing' ($r.Output -notmatch 'Starting the Vite dev server') $r.Output

Write-Host ""

# -- -Stop with nothing running ------------------------------------------------

Write-Host "-- -Stop (nothing running) ----------------------------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Stop')
Assert-True '-Stop (down) reports nothing to stop' ($r.Output -match 'nothing to stop') $r.Output
Assert-True '-Stop (down) stops the agent half too' ($r.Output -match 'Agent is not running') $r.Output
Assert-True '-Stop (down) exits 0 (idempotent)' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Stop (down) logs CMD' ($r.LogText -match "^CMD`t") $r.LogText

Write-Host ""

# -- -Status probes the port, not only the PID file ----------------------------
# tkWeb -Stop killed the PID it recorded, which is the npm launcher; vite is its
# child and kept the socket. -Status then read the (now removed) PID file and
# reported "not running" while the orphan served on 5174 -- the port `npm run
# smoke` defaults to, so a later smoke run could pass against a stale tree.

Write-Host "-- -Status probes the port as well as the PID ---------" -ForegroundColor Cyan

# An orphaned Vite: on the port, not in the PID file, and running in node --
# which is what makes it something this command may stop.
$listenerShim = @'
function global:Get-WebPortListenerIds { param([int]$Port) if ($Port -eq 5174) { return @(424242) } return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
function global:Get-WebProcessName { param([int]$ProcessId) return 'node' }
function global:Stop-WebProcessTree { param([int]$ProcessId) Write-Host "  [test] would stop $ProcessId" }
'@

$r = Invoke-Web -ScriptArgs @('-Status') -Preamble $listenerShim
Assert-True '-Status reports a listener the PID file does not know about' ($r.Output -match '424242') $r.Output
Assert-True '-Status names the port the orphan holds' ($r.Output -match 'Port 5174') $r.Output
Assert-True '-Status still says the dev server is not running' ($r.Output -match 'Dev server is not running') $r.Output
Assert-True '-Status warns that a smoke run would hit it' ($r.Output -match 'stale server') $r.Output
Assert-True '-Status with an orphan still exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

# No listener, no noise: the orphan line must not appear on a quiet machine.
$quietShim = @'
function global:Get-WebPortListenerIds { param([int]$Port) return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
'@
$r = Invoke-Web -ScriptArgs @('-Status') -Preamble $quietShim
Assert-True '-Status says nothing about a port when nothing is listening' ($r.Output -notmatch 'still being served') $r.Output

# The probed port is read from web/vite.config.ts, not hardcoded.
$portShim = @'
function global:Get-WebPortListenerIds { param([int]$Port) return @($Port) }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
function global:Get-WebProcessName { param([int]$ProcessId) return 'node' }
function global:Stop-WebProcessTree { param([int]$ProcessId) Write-Host "  [test] would stop $ProcessId" }
'@
$r = Invoke-Web -ScriptArgs @('-Status') -Preamble $portShim -VitePort 5199
Assert-True '-Status probes the port vite.config.ts declares' ($r.Output -match 'Port 5199') $r.Output
Assert-True '-Status is not still probing a hardcoded 5174' ($r.Output -notmatch 'Port 5174') $r.Output

Write-Host ""

# -- -Stop ends the orphan rather than denying it -------------------------------

Write-Host "-- -Stop reaches a listener it did not record ---------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Stop') -Preamble $listenerShim
Assert-True '-Stop stops the orphaned listener' ($r.Output -match 'would stop 424242') $r.Output
Assert-True '-Stop names the port it found it on' ($r.Output -match 'listening on port 5174') $r.Output
# The agent half prints its own "nothing to stop"; this is about the dev half.
Assert-True '-Stop no longer claims the dev half had nothing to stop' ($r.Output -notmatch 'Dev server is not running -- nothing to stop') $r.Output
Assert-True '-Stop with an orphan exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Web -ScriptArgs @('-Stop') -Preamble $quietShim
Assert-True '-Stop with nothing listening still reports nothing to stop' ($r.Output -match 'Dev server is not running -- nothing to stop') $r.Output

Write-Host ""

# -- A listener that is not ours, and not a dev server --------------------------
# With the production UI up, the only listeners on 5174 are Docker Desktop's own
# port forwards. The sweep killed every listener it did not recognise, so
# `tkWeb -Stop` force-killed com.docker.backend.exe and the WSL relay -- which
# then made Test-DockerAvailable false, which SKIPPED the compose down it was
# about to run. The container was left defined, Docker had to be restarted by
# hand, and every other container went with it.
#The PIDs and names below are the
# ones from that report.

Write-Host "-- A foreign listener is reported, never killed -------" -ForegroundColor Cyan

$dockerShim = @'
function global:Get-WebPortListenerIds { param([int]$Port) if ($Port -eq 5174) { return @(19136, 31096) } return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
function global:Get-WebProcessName {
    param([int]$ProcessId)
    if ($ProcessId -eq 19136) { return 'vpnkit-bridge.exe' }
    if ($ProcessId -eq 31096) { return 'com.docker.backend.exe' }
    return ''
}
function global:Stop-WebProcessTree { param([int]$ProcessId) Write-Host "  [test] would stop $ProcessId" }
function global:Test-DockerAvailable { return $true }
function global:Invoke-WebComposeDown { Write-Host "  [test] compose down" }
'@

$r = Invoke-Web -ScriptArgs @('-Stop') -Preamble $dockerShim
Assert-True '-Stop does not kill a listener that is not a dev server' ($r.Output -notmatch 'would stop 31096') $r.Output
Assert-True '-Stop does not kill the other one either' ($r.Output -notmatch 'would stop 19136') $r.Output
Assert-True '-Stop names what is holding the port' ($r.Output -match 'com\.docker\.backend\.exe \(PID 31096\)') $r.Output
Assert-True '-Stop says it is not stopping it' ($r.Output -match 'not a dev server; not stopping it') $r.Output
Assert-True '-Stop still exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

# The order is the other half of the fix: the container's forward has to be gone
# before anything looks at the port.
$composeAt = $r.Output.IndexOf('[test] compose down')
$sweepAt = $r.Output.IndexOf('Port 5174 is held by')
Assert-True '-Stop runs compose down at all' ($composeAt -ge 0) $r.Output
Assert-True '-Stop runs compose down BEFORE the port sweep' ($composeAt -ge 0 -and $sweepAt -gt $composeAt) $r.Output

# A dev server on the same port, with Docker up, is still stopped: the guard is
# about what the process IS, not about whether Docker is running.
$mixedShim = @'
function global:Get-WebPortListenerIds { param([int]$Port) if ($Port -eq 5174) { return @(31096, 424242) } return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
function global:Get-WebProcessName {
    param([int]$ProcessId)
    if ($ProcessId -eq 424242) { return 'node' }
    return 'com.docker.backend.exe'
}
function global:Stop-WebProcessTree { param([int]$ProcessId) Write-Host "  [test] would stop $ProcessId" }
function global:Test-DockerAvailable { return $true }
function global:Invoke-WebComposeDown { Write-Host "  [test] compose down" }
'@

$r = Invoke-Web -ScriptArgs @('-Stop') -Preamble $mixedShim
Assert-True '-Stop still stops a node listener' ($r.Output -match 'would stop 424242') $r.Output
Assert-True '-Stop names node when it stops one' ($r.Output -match 'Also stopped PID 424242 \(node\)') $r.Output
Assert-True '-Stop leaves the Docker process alone' ($r.Output -notmatch 'would stop 31096') $r.Output

# -Restart has the same order and the same guard.
$r = Invoke-Web -ScriptArgs @('-Restart') -ClearPath -Preamble $dockerShim
Assert-True '-Restart does not kill a foreign listener either' ($r.Output -notmatch 'would stop 31096') $r.Output
$composeAt = $r.Output.IndexOf('[test] compose down')
$sweepAt = $r.Output.IndexOf('Port 5174 is held by')
Assert-True '-Restart runs compose down before the sweep' ($composeAt -ge 0 -and $sweepAt -gt $composeAt) $r.Output

Write-Host ""

# -Status must give advice that -Stop will actually follow. It used to say
# "tkWeb -Stop will end it" about a Docker port forward, and it did.

Write-Host "-- -Status says the same thing -Stop does -------------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Status') -Preamble $dockerShim
Assert-True '-Status names what is holding the port' ($r.Output -match 'com\.docker\.backend\.exe \(PID 31096\)') $r.Output
Assert-True '-Status says it is not a dev server' ($r.Output -match 'not a dev server; not stopping it') $r.Output
Assert-True '-Status does not offer to end it with -Stop' ($r.Output -notmatch 'will end it') $r.Output
Assert-True '-Status does not call it a stale server' ($r.Output -notmatch 'stale server') $r.Output
Assert-True '-Status with a foreign listener still exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

Write-Host ""

# -- Missing prerequisites -----------------------------------------------------

Write-Host "-- Missing prerequisites ------------------------------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Dev') -ClearPath -WithModules
Assert-True 'npm missing gives a readable error' ($r.Output -match 'Error: npm not found') $r.Output
Assert-True 'npm missing names Node' ($r.Output -match 'Node\.js') $r.Output
Assert-True 'npm missing shows no raw exception text' ($r.Output -notmatch 'System\.Management\.Automation') $r.Output
Assert-True 'npm missing logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'npm missing exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"

$r = Invoke-Web -ScriptArgs @('-Dev')
Assert-True 'no node_modules gives a readable error' ($r.Output -match 'node_modules is missing') $r.Output
Assert-True 'no node_modules points at npm ci' ($r.Output -match 'npm ci') $r.Output
Assert-True 'no node_modules logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'no node_modules exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"
Assert-True 'no node_modules starts no dev server' ($r.Output -notmatch 'Starting the Vite dev server') $r.Output

$r = Invoke-Web -ScriptArgs @('-Status') -NoWebFolder
Assert-True 'no web/ gives a readable error' ($r.Output -match 'No web/ directory') $r.Output
Assert-True 'no web/ logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'no web/ exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"

Write-Host ""

# -- Docker absent -------------------------------------------------------------

Write-Host "-- Docker absent (production path) --------------------" -ForegroundColor Cyan

# PATH cleared means `Get-Command docker` fails, which is what a machine with no
# Docker Desktop looks like. The production path must say so.
$r = Invoke-Web -ScriptArgs @() -ClearPath -WithModules
Assert-True 'no Docker says so in words' ($r.Output -match 'Docker is not available') $r.Output
Assert-True 'no Docker points at -Dev as the alternative' ($r.Output -match '-Dev') $r.Output
Assert-True 'no Docker shows no raw exception text' ($r.Output -notmatch 'System\.Management\.Automation') $r.Output
Assert-True 'no Docker logs ERR' ($r.LogText -match "^ERR`t") $r.LogText
Assert-True 'no Docker exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"
Assert-True 'no Docker builds nothing' ($r.Output -notmatch 'Building and starting') $r.Output

Write-Host ""

# -- -Help ---------------------------------------------------------------------

Write-Host "-- -Help comes from config ----------------------------" -ForegroundColor Cyan

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = $config.commands.Web

$r = Invoke-Web -ScriptArgs @('-Help')
Assert-True '-Help exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True '-Help prints the config description' ($r.Output -match [regex]::Escape($entry.description.Substring(0, [Math]::Min(40, $entry.description.Length)))) $r.Output
Assert-True '-Help renders the invoking prefix, not a literal placeholder' ($r.Output -match "$($script:Prefix)Web" -and $r.Output -notmatch '\{cliPrefix\}') $r.Output
Assert-True '-Help describes each switch' ($r.Output -match 'Switches:') $r.Output
Assert-True '-Help describes -Status in words' ($r.Output -match '(?m)^\s+-Status\s+\S') $r.Output
Assert-True '-Help carries the notes' ($r.Output -match 'Notes:') $r.Output
Assert-True '-Help names a URL to open' ($r.Output -match 'http://localhost:\d+') $r.Output
Assert-True '-Help leaves no port token unresolved' ($r.Output -notmatch '\{agentPort\}' -and $r.Output -notmatch '\{devPort\}') $r.Output
Assert-True '-Help starts nothing' ($r.Output -notmatch 'Starting the Vite dev server') $r.Output

Write-Host ""

# -- The config entry matches the script ---------------------------------------

Write-Host "-- Config entry ---------------------------------------" -ForegroundColor Cyan

Assert-True 'config: Web entry exists' ($null -ne $entry)
Assert-True 'config: category is org' ($entry.category -eq 'org')
Assert-True 'config: usage advertises -Dev' ($entry.usage -match '-Dev')
Assert-True 'config: usage advertises -Stop' ($entry.usage -match '-Stop')
Assert-True 'config: usage advertises -Status' ($entry.usage -match '-Status')
Assert-True 'config: usage advertises -Restart' ($entry.usage -match '-Restart')
Assert-True 'config: at least one example' ($entry.examples -and @($entry.examples).Count -gt 0)

$scriptParams = (Get-Command $targetScript).Parameters.Keys
foreach ($switch in @('Dev', 'Stop', 'Restart', 'Status', 'Help')) {
    Assert-True "script declares -$switch" ($scriptParams -contains $switch)
}

# Both start paths need an agent and do not care who started it, so they ask
# Start-Agent.ps1 to reuse one rather than print "Stop it first" mid-command.
$webSource = Get-Content $targetScript -Raw
$agentParams = (Get-Command $agentScript).Parameters.Keys
Assert-True 'the agent launcher declares -Reuse' ($agentParams -contains 'Reuse')
Assert-True 'no start path calls the agent without -Reuse' ($webSource -notmatch '(?m)^\s*&\s+\$agentScript\s*$') $webSource

Write-Host ""

# -- The agent's port reaches the dev proxy --------------------------------------
# web.agentPort moved the agent and not the two proxies that point at it.
#-Dev now exports the
# resolved port, under the contract's variable name, into the environment Vite
# inherits -- asserted by a launch stub that prints what it was handed, with a
# config.local.json patching the port so the shipped default cannot pass for it.

Write-Host "-- The agent port reaches the dev proxy ---------------" -ForegroundColor Cyan

$r = Invoke-Web -ScriptArgs @('-Dev', '-NoBrowser') -WithModules -StubAgent -StubLaunch -WebLogUrl 'http://localhost:5199' -LocalAgentPort 4321
Assert-True '-Dev exports the merged web.agentPort to the launch' ($r.Output -match 'would launch npm run dev with P20_AGENT_PORT=4321') $r.Output
Assert-True '-Dev names the port /api is proxied to' ($r.Output -match 'proxied to the agent on port 4321') $r.Output
Assert-True '-Dev does not export the shipped default when a local file patches it' ($r.Output -notmatch 'P20_AGENT_PORT=4100') $r.Output
Assert-True '-Dev with the stubbed launch exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Web -ScriptArgs @('-Dev', '-NoBrowser') -WithModules -StubAgent -StubLaunch -WebLogUrl 'http://localhost:5199'
Assert-True '-Dev exports the shipped default when nothing patches it' ($r.Output -match 'P20_AGENT_PORT=4100') $r.Output

Write-Host ""

# -- -Fixture: the smoke's servers, with nothing written ---------------
# The modules-on smoke failed on the machine whose .env holds a webhook: the
# module reads .env into the shell at import and the agent inherited it, so the
# send button was live. And every smoke run meant rewriting
# config.local.json twice and restoring it. -Fixture hands the servers the
# run marker, the fixture hub, its Space and the flags through the environment,
# with every TEAMS_WEBHOOK_* removed -- and gives the caller's shell its own
# environment back. A webhook is planted in the child's shell here to prove it.

Write-Host "-- -Dev -Fixture: the smoke's servers ----------------" -ForegroundColor Cyan

$plantHook = "`$env:TEAMS_WEBHOOK_MANAGER = 'https://example.invalid/hook'; `$env:P20_ACTIVE_SPACE = ''; `$env:P20_FEATURES = ''"
$readBack = "Write-Host `"  [test] after: marker=[`$env:P20_TEST_RUN] space=[`$env:P20_ACTIVE_SPACE] features=[`$env:P20_FEATURES] webhook=[`$env:TEAMS_WEBHOOK_MANAGER]`""

$r = Invoke-Web -ScriptArgs @('-Dev', '-Fixture', '-Modules', 'on', '-NoBrowser') -WithModules -StubAgent -StubLaunch -WebLogUrl 'http://localhost:5199' -Preamble $plantHook -Postamble $readBack
Assert-True '-Fixture exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)`n$($r.Output)"
Assert-True '-Fixture restarts the agent rather than reusing one' ($r.Output -match 'agent stub \(Stop\)') $r.Output
$stopAt = $r.Output.IndexOf('agent stub (Stop)')
$reuseAt = $r.Output.IndexOf('agent stub (Reuse)')
Assert-True '-Fixture stops the agent BEFORE it starts one' ($stopAt -ge 0 -and $reuseAt -gt $stopAt) $r.Output
Assert-True 'the agent launcher sees the run marker' ($r.Output -match 'agent sees marker=\[fixture\]') $r.Output
Assert-True 'the agent launcher sees the fixture hub' ($r.Output -match 'agent sees .*root=\[[^\]]*Tests[\\/]fixtures[\\/]hub\]') $r.Output
Assert-True 'the agent launcher sees the fixture Space' ($r.Output -match 'agent sees .*space=\[test\]') $r.Output
Assert-True '-Modules on hands the agent growth and communication' ($r.Output -match 'agent sees .*features=\[\{"growth":true,"communication":true\}\]') $r.Output
Assert-True 'the agent launcher sees NO webhook, though the shell holds one' ($r.Output -match 'agent sees .*webhook=\[\]') $r.Output
Assert-True 'the Vite launch sees the same environment' ($r.Output -match 'launch sees marker=\[fixture\] space=\[test\] webhook=\[\]') $r.Output
Assert-True '-Fixture says what it started, and that config.local.json is untouched' ($r.Output -match 'Fixture mode: .*config\.local\.json is not touched') $r.Output
Assert-True 'the shell gets its webhook back afterwards' ($r.Output -match 'after: .*webhook=\[https://example\.invalid/hook\]') $r.Output
Assert-True 'and none of the fixture environment stays behind' ($r.Output -match 'after: marker=\[(?!fixture)[^\]]*\] space=\[\] features=\[\]') $r.Output

$r = Invoke-Web -ScriptArgs @('-Dev', '-Fixture', '-NoBrowser') -WithModules -StubAgent -StubLaunch -WebLogUrl 'http://localhost:5199'
Assert-True '-Fixture without -Modules sets no flag at all' ($r.Output -match 'agent sees .*features=\[\{\}\]') $r.Output
Assert-True '-Fixture without -Modules exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Web -ScriptArgs @('-Dev', '-NoBrowser') -WithModules -StubAgent -StubLaunch -WebLogUrl 'http://localhost:5199' -Preamble $plantHook
Assert-True 'plain -Dev is unchanged: the agent is reused, not stopped first' ($r.Output -notmatch 'agent stub \(Stop\)') $r.Output
Assert-True 'plain -Dev sets no fixture Space' ($r.Output -match 'agent sees .*space=\[\]') $r.Output

$r = Invoke-Web -ScriptArgs @('-Dev', '-Modules', 'on') -WithModules -StubAgent -StubLaunch
Assert-True '-Modules without -Fixture refuses' ($r.Output -match 'Error: -Modules .*needs -Fixture') $r.Output
Assert-True '-Modules without -Fixture exits 2' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True '-Modules without -Fixture starts nothing' ($r.Output -notmatch '\[test\] (agent stub|would launch)') $r.Output

$r = Invoke-Web -ScriptArgs @('-Fixture') -WithModules -StubAgent -StubLaunch
Assert-True '-Fixture without -Dev refuses' ($r.Output -match 'Error: -Fixture .*goes with -Dev') $r.Output
Assert-True '-Fixture without -Dev exits 2' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True '-Fixture without -Dev starts nothing' ($r.Output -notmatch '\[test\] (agent stub|would launch)') $r.Output
Assert-True '-Fixture without -Dev logs ERR' ($r.LogText -match "^ERR`t") $r.LogText

Assert-True 'config: usage advertises -Fixture and -Modules' ($entry.usage -match '-Fixture' -and $entry.usage -match '-Modules <on\|off>') $entry.usage
Assert-True 'the fixture names its variables through the contract, not by hand' ($webSource -match 'env\.activeSpace' -and $webSource -match 'env\.features' -and $webSource -match 'env\.testRunMarker') 'Start-Web.ps1 does not read env.* from consts'

Write-Host ""

# The resolver on its own: dot-sourced against a scratch root, the way both
# launchers use it.
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agentport-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    . (Join-Path $pkgRoot 'Scripts/Get-AgentPort.ps1')
    Assert-True 'the resolver names the variable from the contract file' ((Get-P20AgentPortEnvName) -eq 'P20_AGENT_PORT') (Get-P20AgentPortEnvName)
    $threw = $false
    try { $null = Get-P20AgentPort -RepoRoot $scratch } catch { $threw = $true }
    Assert-True 'a root with no config throws rather than guessing a port' $threw
    Copy-Item $configPath (Join-Path $scratch 'config.default.json')
    Assert-True 'the shipped default resolves' ((Get-P20AgentPort -RepoRoot $scratch) -eq 4100) (Get-P20AgentPort -RepoRoot $scratch)
    Set-SandboxStub (Join-Path $scratch 'config.local.json') '{ "web": { "agentPort": 4321 } }'
    Assert-True 'config.local.json wins over the default' ((Get-P20AgentPort -RepoRoot $scratch) -eq 4321) (Get-P20AgentPort -RepoRoot $scratch)
    Set-SandboxStub (Join-Path $scratch 'config.local.json') '{ "email": "x" }'
    Assert-True 'a local file without the key leaves the default standing' ((Get-P20AgentPort -RepoRoot $scratch) -eq 4100) (Get-P20AgentPort -RepoRoot $scratch)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- Opening the UI ------------------------------------------------------------
# The command's purpose is to bring the UI up for the person who typed it, and
# it stopped short of that -- the predecessor's Web -Restart opened a browser and this did not.
#It opens the URL the server
# actually printed, and never in a test run: the real Test-BrowserAllowed says
# no to a redirected stdout, which is what every one of these cases has.

Write-Host "-- The browser, and who is allowed to open it ---------" -ForegroundColor Cyan

# Both halves stubbed: a test may assert that the right URL was chosen, never
# that a window appeared.
$browserShim = @'
function global:Test-BrowserAllowed { return $true }
function global:Open-WebBrowser { param([string]$Url) Write-Host "  [test] would open $Url" }
function global:Get-WebPortListenerIds { param([int]$Port) return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
'@

$mypid = $PID
$r = Invoke-Web -ScriptArgs @('-Dev') -WithModules -StubAgent -SeedDevPid $mypid -WebLogUrl 'http://localhost:5199' -Preamble $browserShim
Assert-True '-Dev opens the URL the server printed' ($r.Output -match 'would open http://localhost:5199') $r.Output
Assert-True '-Dev does not open a port it merely assumed' ($r.Output -notmatch 'would open http://localhost:5174') $r.Output
Assert-True '-Dev with a server already up still exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

$r = Invoke-Web -ScriptArgs @('-Dev', '-NoBrowser') -WithModules -StubAgent -SeedDevPid $mypid -WebLogUrl 'http://localhost:5199' -Preamble $browserShim
Assert-True '-NoBrowser opens nothing' ($r.Output -notmatch 'would open') $r.Output
Assert-True '-NoBrowser still prints the URL to open by hand' ($r.Output -match 'Open it at http://localhost:5199') $r.Output
Assert-True '-NoBrowser exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"

# The real gate, with only the opener stubbed. Every case in this suite runs
# with a redirected stdout, which is exactly what a CI step or an agent tool
# call looks like -- so the answer must be no.
$openerOnlyShim = @'
function global:Open-WebBrowser { param([string]$Url) Write-Host "  [test] would open $Url" }
function global:Get-WebPortListenerIds { param([int]$Port) return @() }
function global:Get-WebChildProcessIds { param([int]$ProcessId) return @() }
'@
$r = Invoke-Web -ScriptArgs @('-Dev') -WithModules -StubAgent -SeedDevPid $mypid -WebLogUrl 'http://localhost:5199' -Preamble $openerOnlyShim
Assert-True 'a non-interactive caller is never sent a browser' ($r.Output -notmatch 'would open') $r.Output
Assert-True 'and is told the URL instead' ($r.Output -match 'Open it at http://localhost:5199') $r.Output

# The production path opens the port the compose file publishes. Asserted from
# the source rather than by running it: reaching that line means `docker compose
# up --build`, which a test must never run.
Assert-True 'the production path opens the UI too' ($webSource -match 'Open-WebUi -Url "http://localhost:\$\(Get-ProductionPort\)"') 'no Open-WebUi on the production path'
Assert-True 'the production port is read from docker-compose.yml' ($webSource -match 'docker-compose\.yml') 'the production port is not read from the compose file'
Assert-True 'all three start paths go through one opener' ((([regex]::Matches($webSource, 'Open-WebUi -Url')).Count) -ge 3) $webSource.Length
Assert-True 'the script declares -NoBrowser' ((Get-Command $targetScript).Parameters.Keys -contains 'NoBrowser')
Assert-True 'config usage advertises -NoBrowser' ($entry.usage -match '-NoBrowser') $entry.usage

Write-Host ""

# -- What is handed to CreateProcess -------------------------------------------
# Windows ships npm as three files -- npm.ps1, npm.cmd and a bash npm -- and
# PowerShell ranks the .ps1 first. Start-Process with a redirect cannot use
# either a .ps1 or a .cmd as a process image, so `tkWeb -Dev` died with
# "%1 is not a valid Win32 application" on every current Node install.
#
#
# THIS SUITE CANNOT RUN THAT. There is no Windows here. What is asserted is the
# shape: the resolver is handed a simulated Windows path and the argv it
# produces is read back. A Windows run confirms the launch itself.

Write-Host "-- The Windows launch shape ---------------------------" -ForegroundColor Cyan

. $detachedScript

$plain = Resolve-DetachedCommand -FilePath '/usr/local/bin/npm' -ArgumentList @('run', 'dev')
Assert-True 'off Windows the command is passed through unchanged' ($plain.FilePath -eq '/usr/local/bin/npm') $plain.FilePath
Assert-True 'off Windows the arguments are passed through unchanged' ((@($plain.ArgumentList) -join ' ') -eq 'run dev') (@($plain.ArgumentList) -join ' ')

$exe = Resolve-DetachedCommand -FilePath 'C:\Python312\python.exe' -ArgumentList @('-m', 'uvicorn') -ForWindows  # export:example
Assert-True 'a real Windows executable is still launched directly' ($exe.FilePath -eq 'C:\Python312\python.exe') $exe.FilePath  # export:example
Assert-True 'a real Windows executable keeps its arguments' ((@($exe.ArgumentList) -join ' ') -eq '-m uvicorn') (@($exe.ArgumentList) -join ' ')

$shim = Resolve-DetachedCommand -FilePath 'C:\nvm4w\nodejs\npm.cmd' -ArgumentList @('run', 'dev') -ForWindows  # export:example
$shimArgs = @($shim.ArgumentList)
Assert-True 'a .cmd shim is launched through the command interpreter' ($shim.FilePath -match 'cmd(\.exe)?$') $shim.FilePath
Assert-True 'the interpreter gets /d /s /c' (($shimArgs[0] -eq '/d') -and ($shimArgs[1] -eq '/s') -and ($shimArgs[2] -eq '/c')) ($shimArgs -join ' ')
Assert-True 'the whole command line is one quoted argument' ($shimArgs.Count -eq 4 -and $shimArgs[3].StartsWith('"') -and $shimArgs[3].EndsWith('"')) ($shimArgs -join ' ')
Assert-True 'the shim path is quoted inside it' ($shimArgs[3] -eq '""C:\nvm4w\nodejs\npm.cmd" run dev"') $shimArgs[3]  # export:example
Assert-True 'the .cmd is never the FilePath itself' ($shim.FilePath -notmatch '\.cmd$') $shim.FilePath

$batShim = Resolve-DetachedCommand -FilePath 'C:\tools\npm.bat' -ArgumentList @('run', 'dev -- --host 0.0.0.0') -ForWindows  # export:example
Assert-True 'a .bat shim is wrapped the same way' ($batShim.FilePath -match 'cmd(\.exe)?$') $batShim.FilePath
Assert-True 'an argument with spaces is quoted on its own' (@($batShim.ArgumentList)[3] -eq '""C:\tools\npm.bat" run "dev -- --host 0.0.0.0""') (@($batShim.ArgumentList)[3])  # export:example

# -- The Unix launch shape: a session of its own, a quiet stdin ----------------
# .NET starts a child in the caller's process group with the caller's stdin, so
# Vite shared the user's terminal with the pwsh that started it -- bound its
# shortcuts on it, put it in raw mode, and the shell went quiet
#; and a server started from a
# tool call died with the tool call's shell.
# Off Windows the launcher now wraps the command in a
# session leader: a perl one-liner that setsids, opens /dev/null as stdin and
# execs the command in place. The shape is asserted with a leader handed in;
# Test-Agent.ps1 launches a real child through it and reads the facts back.

Write-Host "-- The Unix launch shape ------------------------------" -ForegroundColor Cyan

$fakeLeader = @{ FilePath = '/usr/bin/perl'; ArgumentList = @('-e', '"prog"', '--') }
$own = Resolve-DetachedCommand -FilePath '/usr/local/bin/npm' -ArgumentList @('run', 'dev') -SessionLeader $fakeLeader
Assert-True 'with a session leader, the leader is what is launched' ($own.FilePath -eq '/usr/bin/perl') $own.FilePath
Assert-True 'and the command follows the leader''s --' ((@($own.ArgumentList) -join ' ') -eq '-e "prog" -- /usr/local/bin/npm run dev') (@($own.ArgumentList) -join ' ')
$spaced = Resolve-DetachedCommand -FilePath '/bin/sh' -ArgumentList @('-c', 'echo "a" b') -SessionLeader $fakeLeader
Assert-True 'an argument with a space or a quote is quoted for the joined line, its quotes escaped' (@($spaced.ArgumentList)[-1] -eq '"echo \"a\" b"') (@($spaced.ArgumentList)[-1])
Assert-True 'a Windows-shaped call asks for no leader' ($null -eq (Resolve-SessionLeader -ForWindows))
$isWinHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
if (-not $isWinHost) {
    $realLeader = Resolve-SessionLeader
    Assert-True 'this host has a session leader, and it is perl' ($realLeader -and $realLeader.FilePath -match 'perl') "$($realLeader.FilePath)"
    $program = @($realLeader.ArgumentList)[1]
    Assert-True 'the leader starts a new session' ($program -match 'setsid') $program
    Assert-True 'the leader opens /dev/null as stdin' ($program -match 'open\(STDIN.*dev/null') $program
    Assert-True 'the leader execs the command in place' ($program -match 'exec \{') $program
    Assert-True 'the program is one double-quoted argument with no quote inside it' ($program.StartsWith('"') -and $program.EndsWith('"') -and ($program.Trim('"') -notmatch '["'']')) $program
}
Assert-True '-Dev gives Vite CI=true in its own environment' ($webSource -match "-Environment @\{ CI = 'true' \}") 'no -Environment @{ CI = ''true'' } on the Vite launch'
Assert-True '-Dev never exports CI to itself' ($webSource -notmatch '\$env:CI\s*=') 'Start-Web.ps1 assigns $env:CI'

# The other half of the bug: which npm was picked in the first place.
$detachedSource = Get-Content $detachedScript -Raw
Assert-True 'the resolver asks for an Application, never a .ps1' ($detachedSource -match "Get-Command \`$Name -CommandType Application") 'no -CommandType Application in Start-Detached.ps1'
Assert-True '-Dev resolves npm through the resolver' ($webSource -match "Resolve-LaunchExecutable -Name 'npm'") 'Start-Web.ps1 does not call Resolve-LaunchExecutable'
Assert-True '-Dev no longer assigns from a bare Get-Command npm' ($webSource -notmatch '=\s*Get-Command npm') 'Start-Web.ps1 still resolves npm itself'
Assert-True 'a failed dev start says the agent was left running' ($webSource -match 'The agent is still running') 'no such sentence in the catch'

Write-Host ""

# -- The VERB, not the script -------------------------------------------------
#
# Every -NoBrowser case above drives Start-Web.ps1 directly, which is why the
# suite was green while `tkWeb -Dev -NoBrowser` refused to bind: the wrapper's
# param() block did not declare it, the binder rejected the call before the
# script ran, nothing started, and a binding error sets no $LASTEXITCODE so the
# caller saw exit 0.
# Tests/Test-Menu.ps1 holds every verb to this now; this is the case for the one
# it happened to.

Write-Host "-- tkWeb the verb accepts what tkWeb the help says -----" -ForegroundColor Cyan

# A fresh child pwsh, one manifest by path: this suite otherwise runs with no
# module in the session, and importing one here would leave it imported for
# whatever the runner does next.
$wrapperModule = (Join-Path $pkgRoot 'utilities.psm1') -replace "'", "''"
$wrapperScript = "Import-Module '$wrapperModule' -Force -DisableNameChecking *>`$null; (Get-Command Start-P20Web).Parameters.Keys -join ','"
$wrapperEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapperScript))
$wrapperProbe = & {
    $ErrorActionPreference = 'Continue'
    ((& pwsh -NoProfile -OutputFormat Text -EncodedCommand $wrapperEncoded 2>&1 | ForEach-Object { "$_" }) -join "`n") + "`n"
}
$wrapperParams = @(($wrapperProbe -split "`n" | Where-Object { $_ -match 'Dev' } | Select-Object -Last 1) -split ',' | ForEach-Object { $_.Trim() })
Assert-True 'the Web wrapper is readable' ($wrapperParams.Count -gt 0) $wrapperProbe
foreach ($switch in @('Dev', 'Fixture', 'Modules', 'Stop', 'Restart', 'Status', 'NoBrowser', 'Help')) {
    Assert-True "the wrapper takes -$switch"($wrapperParams -contains $switch) ($wrapperParams -join ',')
}

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
