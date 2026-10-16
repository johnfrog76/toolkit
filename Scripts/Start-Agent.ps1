#Requires -Version 5.1
<#
.SYNOPSIS
    Start, stop or check the FastAPI agent -- the read layer the web UI talks to
    and the bridge back into this CLI.
.DESCRIPTION
    The agent runs on the host, not in Docker, because the bridge forks this
    repo's own PowerShell: a container would be a second, different toolkit.

    The port comes from config (web.agentPort), not from a number in source.
    This script and Start-Web.ps1 are the only readers of that key, and the
    reason it exists.

    The PID and the two log files live at the repository root, where the
    existing .gitignore patterns (*.log, **/*.pid) already cover them.
.EXAMPLE
    {cliPrefix}Agent              Start the agent
    {cliPrefix}Agent -Dev         Start with auto-reload
    {cliPrefix}Agent -Stop        Stop it
    {cliPrefix}Agent -Status      Is it running, and is it healthy
    {cliPrefix}Agent -Port 4200   Override the configured port for one run

    -Reuse is for callers, not for typing: Start-Web.ps1 passes it so an agent
    that is already up is reported as reused instead of as something to stop.
#>
[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Status,
    [switch]$Dev,
    [int]$Port,
    # Composition, not a user-facing verb: Start-Web.ps1 passes it because
    # -Dev's job is "have an agent", not "start one". An already-running agent
    # is then reported as reused rather than as something to stop first.
    [switch]$Reuse,
    [switch]$Help
)

# Scripts/ -> repo root. From this file's own location, so a clone at any path
# works and nothing is derived from the prompt store.
$repoRoot = Split-Path $PSScriptRoot -Parent

# These normally come from the module. The script is also run directly -- by
# the suite, by a person running the .ps1, by Start-Web.ps1 -- so a missing
# helper must not be fatal. Same pattern as Get-Environment.ps1.
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$script:IsWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

$pidFile = Join-Path $repoRoot '.agent.pid'
$logFile = Join-Path $repoRoot 'agent.log'
$errFile = Join-Path $repoRoot 'agent.err.log'

function Write-AgentLog {
    param([string]$Type, [string]$Detail)
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type $Type -Source "$(Get-CliPrefix)Agent" -Detail $Detail
    }
}

# The port is data. config.local.json patches config.default.json, last read
# wins, and -Port beats both for a single run. The resolver is shared with
# Start-Web.ps1, which exports the same answer to the two proxies -- see
# Scripts/Get-AgentPort.ps1.
. (Join-Path $PSScriptRoot 'Get-AgentPort.ps1')
function Get-ConfiguredPort { return (Get-P20AgentPort -RepoRoot $repoRoot) }

function Show-ConfigHelp {
    # One renderer, shared with the other launcher: the same config entry, the
    # same switches, examples and notes, whether this script runs as a tk* verb
    # or as a plain .ps1. See Scripts/Show-ConfigHelp.ps1.
    . (Join-Path $PSScriptRoot 'Show-ConfigHelp.ps1')
    Show-P20ConfigHelp -CommandName 'Agent' -RepoRoot $repoRoot -Prefix (Get-CliPrefix) `
        -Fallback 'Start, stop or check the FastAPI agent.'
}

function Get-AgentProcessId {
    if (-not (Test-Path $pidFile)) { return 0 }
    $raw = (Get-Content $pidFile -Raw).Trim()
    if (-not $raw) { return 0 }
    try {
        $proc = Get-Process -Id $raw -ErrorAction Stop
        if ($proc -and -not $proc.HasExited) { return [int]$raw }
        return 0
    }
    catch {
        # The PID is gone -- the file is stale, not evidence of anything.
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return 0
    }
}

# -- The port, and who else is on it -------------------------------------------
# A machine migrating to this package may already be running the PREDECESSOR's
# agent -- `python -m uvicorn agent:app --host 0.0.0.0 --port 4100`, serving a
# different hub. Windows lets this script bind 127.0.0.1 beside that wildcard
# listener, so `tkAgent` printed "Agent started", `localhost` resolved to the
# more specific socket, and everything looked right; then `tkAgent -Stop` left
# the OTHER agent answering /api/health from the OTHER hub while `-Status` said
# nothing was running. A browser, the Vite proxy or `npm run smoke` pointed at
# localhost:4100 then read a different package's data.
#
#
# The three helpers are behind Get-Command guards because that is how the suite
# replaces them: there is no second agent here, and nothing in these tests may
# touch a real socket.
. (Join-Path $PSScriptRoot 'Get-PortListeners.ps1')

if (-not (Get-Command Get-AgentPortListenerIds -ErrorAction SilentlyContinue)) {
    function Get-AgentPortListenerIds {
        param([int]$Port)
        return @(Get-P20PortListenerIds -Port $Port)
    }
}

if (-not (Get-Command Get-AgentProcessName -ErrorAction SilentlyContinue)) {
    function Get-AgentProcessName {
        param([int]$ProcessId)
        return (Get-P20ProcessNameById -ProcessId $ProcessId)
    }
}

# What the thing on the port SAYS it is. /api/health is this package's own
# route and the predecessor's alike, and its prompts_root is the identity that
# matters: which hub the answers would come from.
if (-not (Get-Command Get-AgentHealthReport -ErrorAction SilentlyContinue)) {
    function Get-AgentHealthReport {
        param([int]$Port)
        try {
            $resp = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 3 -ErrorAction Stop
            return @{ Answered = $true; PromptsRoot = [string]$resp.prompts_root; Status = [string]$resp.status; PackageRoot = [string]$resp.package_root }
        }
        catch {
            return @{ Answered = $false; PromptsRoot = ''; Status = ''; PackageRoot = '' }
        }
    }
}

# The hub THIS checkout is configured for. Compared against what the listener
# reports, because "is it ours" is a question about the store being served, not
# about the port. An unreadable or unset value compares equal to nothing, which
# makes the listener foreign -- the safe direction.
#
# One resolver: Get-P20PromptsRoot in Scripts/Resolve-HubConfig.ps1, env first
# then config. This function used to read the two config files itself, which was
# a fourth copy of a rule the module and five other scripts each had their own
# version of. Dot-sourced
# because this launcher runs with no module in the session, by design.
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
function Get-ConfiguredHubRoot {
    return (Get-P20PromptsRoot -PackageRoot $repoRoot)
}

function Test-SameHub {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    $normalise = {
        param($v)
        $x = ([string]$v).Trim().Replace('\', '/').TrimEnd('/')
        if ($script:IsWin) { return $x.ToLowerInvariant() }
        return $x
    }
    return ((& $normalise $A) -eq (& $normalise $B))
}

# Is the listener THIS checkout's agent? /api/health reports package_root
# -- which checkout the process runs from, as opposed to whose
# hub it serves. An agent from an older build reports none, and is treated as
# foreign: the safe direction, since the answer decides whether -Stop may kill
# it. The agent resolves symlinks (REPO_ROOT is Path.resolve()), so this side
# compares against both spellings of the checkout.
function Test-OurPackage {
    param([string]$Reported)
    if (-not $Reported) { return $false }
    if (Test-SameHub $Reported $repoRoot) { return $true }
    if (-not $script:IsWin -and (Get-Command realpath -ErrorAction SilentlyContinue)) {
        $real = & realpath $repoRoot 2>$null
        if ($real -and (Test-SameHub $Reported ([string]$real))) { return $true }
    }
    return $false
}

# Behind a guard for the same reason as the probes: the suite must never kill a
# real process, and asserts which PID would have been stopped instead.
if (-not (Get-Command Stop-AgentProcess -ErrorAction SilentlyContinue)) {
    function Stop-AgentProcess {
        param([int]$ProcessId)
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    }
}

# Wait for the port to let go after a stop, so the start that follows does not
# find the dying process and read it as an occupant. A few seconds at most.
function Wait-PortReleased {
    param([int]$Port, [int[]]$Ids)
    for ($i = 0; $i -lt 15; $i++) {
        $left = @(Get-AgentPortListenerIds -Port $Port | Where-Object { $Ids -contains $_ })
        if ($left.Count -eq 0) { return }
        Start-Sleep -Milliseconds 200
    }
}

# The hub the CALLER's environment asks for, compared with the hub a running
# agent reports -- the question -Reuse never asked, which is how
# `$env:PROMPTS_ROOT = <fixture>; tkWeb -Dev` reused an agent still serving the
# real hub and a smoke run measured the wrong data. An agent that
# reports no hub is compared only when the caller named one explicitly, since
# the resolver's fallback for "nothing configured" is a path the agent never
# reports.
function Test-HubMismatch {
    param($Health)
    if (-not $Health.Answered) { return $false }
    $wanted = Get-ConfiguredHubRoot
    if (-not $Health.PromptsRoot) { return [bool]$env:PROMPTS_ROOT }
    return -not (Test-SameHub $Health.PromptsRoot $wanted)
}

# One description of what is on the port, used by -Status and by the start
# path so they cannot disagree. Returns $null when the port is free or holds
# only the PID this script recorded.
function Get-PortOccupant {
    param([int]$Port, [int]$OurPid = 0)

    $ids = @(Get-AgentPortListenerIds -Port $Port | Where-Object { $_ -ne $OurPid })
    if ($ids.Count -eq 0) { return $null }

    $listener = $ids[0]
    $name = Get-AgentProcessName -ProcessId $listener
    if (-not $name) { $name = 'an unknown process' }
    $health = Get-AgentHealthReport -Port $Port
    $ours = Get-ConfiguredHubRoot
    $sameHub = $false
    if ($health.Answered) { $sameHub = Test-SameHub $health.PromptsRoot $ours }
    $ourPackage = $false
    if ($health.Answered) { $ourPackage = Test-OurPackage $health.PackageRoot }

    $detail = "Port $Port is held by $name (PID $listener)"
    if ($health.Answered) {
        $reported = $health.PromptsRoot
        if (-not $reported) { $reported = '(no hub reported)' }
        $detail += " -- it answers /api/health from hub $reported"
    }
    else {
        $detail += ' -- it does not answer /api/health'
    }

    return @{
        ProcessId = $listener
        Name      = $name
        Answered  = $health.Answered
        HubRoot   = $health.PromptsRoot
        SameHub   = $sameHub
        OurPackage = $ourPackage
        Health    = $health
        Detail    = $detail
    }
}

# Which interpreter this machine actually has, and what to CALL it in a
# message. Scripts/Resolve-Python.ps1 is the one implementation -- dot-sourced
# because this script also runs standalone, and because the suite tests the
# probe against stubbed interpreters.
. (Join-Path $PSScriptRoot 'Resolve-Python.ps1')

if ($Help) { Show-ConfigHelp; exit 0 }

if (-not $Port -or $Port -le 0) { $Port = Get-ConfiguredPort }

# -- Status --------------------------------------------------------------------

if ($Status) {
    $running = Get-AgentProcessId
    if ($running -gt 0) {
        Write-Host "  Agent is running (PID $running) on http://localhost:$Port" -ForegroundColor Green
        try {
            $resp = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 3
            Write-Host "  Health: $($resp.status) -- hub: $($resp.prompts_root)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  Health probe failed -- it may still be starting up." -ForegroundColor Yellow
        }
    }
    else {
        # The port is named even when nothing is running: it is the answer to
        # "which port would it use", which is the question config.web.agentPort
        # exists to settle.
        Write-Host "  Agent is not running (configured port $Port)." -ForegroundColor Yellow
    }

    # The PID file is not the whole truth. Something this script did not start
    # can be serving the port that every browser, the Vite proxy and the smoke
    # run resolve to, and "not running" about a live listener is the answer
    # that sent a migrating machine reading another package's hub.
    $occupant = Get-PortOccupant -Port $Port -OurPid $running
    if ($occupant) {
        if ($occupant.OurPackage) {
            Write-Host "  $($occupant.Detail) -- this checkout's agent, started from another shell. $(Get-CliPrefix)Agent -Stop will stop it." -ForegroundColor Yellow
        }
        elseif ($occupant.SameHub) {
            Write-Host "  $($occupant.Detail) -- this hub, but not started by this command." -ForegroundColor Yellow
        }
        else {
            Write-Host "  $($occupant.Detail)." -ForegroundColor Yellow
            Write-Host "  That is not this package's agent. Anything pointed at localhost:$Port reads its hub, not yours." -ForegroundColor Gray
            Write-Host "  Stop it, or run this one elsewhere: $(Get-CliPrefix)Agent -Port <n>." -ForegroundColor Gray
        }
    }

    Write-AgentLog 'CMD' 'status'
    exit 0
}

# -- Stop ----------------------------------------------------------------------

if ($Stop) {
    $running = Get-AgentProcessId
    $stopped = @()
    if ($running -gt 0) {
        try {
            Stop-AgentProcess -ProcessId $running
            Write-Host "  Agent stopped (PID $running)." -ForegroundColor Green
        }
        catch {
            Write-Host "  Agent process $running had already gone." -ForegroundColor Yellow
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        $stopped += $running
        Wait-PortReleased -Port $Port -Ids @($running)
    }

    # The PID file is a cache of what is on the port, not the truth of it. An
    # agent this checkout started from ANOTHER shell is invisible to it, and
    # "nothing to stop" about a live listener left orphans that the next
    # `Web -Dev` then reused. This checkout's agent is stopped
    # wherever it was started; anything else is named and left alone, because
    # stopping another package's server is still not a launcher's decision.
    $occupant = Get-PortOccupant -Port $Port -OurPid $running
    $named = $false
    while ($occupant -and $occupant.OurPackage -and ($stopped -notcontains $occupant.ProcessId)) {
        try {
            Stop-AgentProcess -ProcessId $occupant.ProcessId
            Write-Host "  Stopped PID $($occupant.ProcessId) ($($occupant.Name)) -- this checkout's agent, started from another shell." -ForegroundColor Green
        }
        catch {
            Write-Host "  PID $($occupant.ProcessId) had already gone." -ForegroundColor Yellow
        }
        $stopped += $occupant.ProcessId
        Wait-PortReleased -Port $Port -Ids @($occupant.ProcessId)
        $occupant = Get-PortOccupant -Port $Port -OurPid $running
    }
    if ($occupant -and ($stopped -notcontains $occupant.ProcessId)) {
        Write-Host "  $($occupant.Detail) -- not this checkout's agent; not stopping it." -ForegroundColor Yellow
        $named = $true
    }

    if ($stopped.Count -eq 0 -and -not $named) {
        Write-Host "  Agent is not running -- nothing to stop." -ForegroundColor Yellow
        Write-AgentLog 'CMD' 'stop (not running)'
        exit 0
    }
    Write-AgentLog 'CMD' "stop ($($stopped -join ', '))"
    exit 0
}

# -- Start ---------------------------------------------------------------------

$already = Get-AgentProcessId
if ($already -gt 0) {
    # Recorded, so it is ours -- but is it serving the hub THIS caller asks for?
    # PROMPTS_ROOT "is an explicit override and wins" (agent/core/config.py),
    # and it can only win in a process started with it. So an agent of ours on
    # another hub is restarted, not reused.
    $health = Get-AgentHealthReport -Port $Port
    if (Test-HubMismatch $health) {
        $was = $health.PromptsRoot
        if (-not $was) { $was = '(no hub)' }
        Write-Host "  Agent (PID $already) is serving $was; this shell asks for $(Get-ConfiguredHubRoot) -- restarting it." -ForegroundColor Yellow
        try { Stop-AgentProcess -ProcessId $already } catch { $null = $_ }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Wait-PortReleased -Port $Port -Ids @($already)
        Write-AgentLog 'CMD' "restart (PID $already served $was)"
        $already = 0
    }
}
if ($already -gt 0) {
    # Every reuse names the hub, so a stale agent is one line away from obvious.
    $servingLine = ''
    if ($health.Answered) {
        $h = $health.PromptsRoot
        if (-not $h) { $h = '(no hub configured)' }
        $servingLine = "  Serving hub: $h"
    }
    if ($Reuse) {
        # Called from Web -Dev, which needs an agent and does not care who
        # started it. "Stop it first" is an instruction, and printing one in a
        # message that is not a refusal made a working command read as half
        # failed.
        Write-Host "  Agent already running (PID $already) on http://localhost:$Port -- reusing it." -ForegroundColor Green
    }
    else {
        Write-Host "  Agent is already running (PID $already) on http://localhost:$Port." -ForegroundColor Yellow
        Write-Host "  Stop it first with $(Get-CliPrefix)Agent -Stop." -ForegroundColor Gray
    }
    if ($servingLine) { Write-Host $servingLine -ForegroundColor Gray }
    Write-AgentLog 'CMD' 'start (already running)'
    exit 0
}

# Nothing of ours is recorded -- so what is on the port?
$occupant = Get-PortOccupant -Port $Port -OurPid $already
if ($occupant -and $occupant.OurPackage -and (Test-HubMismatch $occupant.Health)) {
    # This checkout's agent, from another shell, on a hub this caller does not
    # ask for: the orphan that kept feeding every later -Dev. Ours to end.
    $was = $occupant.HubRoot
    if (-not $was) { $was = '(no hub)' }
    Write-Host "  $($occupant.Detail) -- this checkout's agent, from another shell; this shell asks for $(Get-ConfiguredHubRoot) -- restarting it." -ForegroundColor Yellow
    try { Stop-AgentProcess -ProcessId $occupant.ProcessId } catch { $null = $_ }
    Wait-PortReleased -Port $Port -Ids @($occupant.ProcessId)
    Write-AgentLog 'CMD' "restart (PID $($occupant.ProcessId) served $was)"
    $occupant = Get-PortOccupant -Port $Port -OurPid 0
}
if ($occupant) {
    if ($occupant.SameHub) {
        # An agent on THIS hub that this script did not record: another shell's,
        # or one whose PID file was removed. Starting a second one would either
        # fail to bind or, on Windows, bind beside it -- so it is reused and
        # named, rather than refused or duplicated.
        Write-Host "  $($occupant.Detail) -- this hub." -ForegroundColor Yellow
        if ($occupant.OurPackage) {
            Write-Host "  Reusing it. It is this checkout's agent, so $(Get-CliPrefix)Agent -Stop will stop it." -ForegroundColor Gray
        }
        else {
            Write-Host "  Reusing it. This command did not start it, so $(Get-CliPrefix)Agent -Stop will not stop it." -ForegroundColor Gray
        }
        Write-AgentLog 'CMD' "start (reusing PID $($occupant.ProcessId) on $Port)"
        exit 0
    }

    $hub = $occupant.HubRoot
    if (-not $hub) { $hub = 'an unknown hub' }
    $what = if ($occupant.Answered) { "another agent, serving $hub" } else { 'something that is not an agent' }
    Write-CliError -Message "Port $Port is already held by $($occupant.Name) (PID $($occupant.ProcessId)) -- $what." `
        -Hint "Stop it first, or run this agent on another port: $(Get-CliPrefix)Agent -Port <n>. Windows will let both bind, and localhost then resolves to the other one."
    Write-AgentLog 'ERR' "port $Port held by PID $($occupant.ProcessId) ($($occupant.Name))"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$python = Resolve-P20Python -Windows $script:IsWin
if (-not $python) {
    # Name the commands that were tried, in order. On Windows the reader's next
    # move is `python` or `py -3`, and telling them to run `python3` -- which is
    # the Store alias there -- is what sent the cold start looking.
    $tried = (@(Get-P20PythonCandidates -Windows $script:IsWin | ForEach-Object {
                if (@($_.Prefix).Count -gt 0) { "$($_.Exe) $($_.Prefix -join ' ')" } else { $_.Exe }
            }) -join ', ')
    Write-CliError -Message "Python 3 not found -- tried $tried." `
        -Hint "Install Python 3, then run its own pip: <python> -m pip install -r agent/requirements.txt"
    Write-AgentLog 'ERR' "python not found (tried $tried)"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
Write-Host "  Python: $($python.Display) ($($python.Version))" -ForegroundColor Gray

# Both, in one probe: uvicorn is what runs the app and fastapi is what the app
# is written in, and a half-installed environment is the common case after a
# fresh clone.
$probeArgs = @($python.Prefix) + @('-c', "import uvicorn, fastapi; print('ok')")
$probe = & $python.Exe @probeArgs 2>&1
if ("$probe" -notlike '*ok*') {
    Write-CliError -Message 'The agent''s Python dependencies are not installed (uvicorn, fastapi).' `
        -Hint "Run: $($python.Display) -m pip install -r $(Join-Path $repoRoot 'agent/requirements.txt')"
    Write-AgentLog 'ERR' 'uvicorn/fastapi not importable'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# The interface is the contract's (consts.json, agent.bindHost): the loopback.
# The agent has no authentication of its own, so this one argument is the
# boundary (docs/ARCHITECTURE.md, "Trust model"); Tests/test_consts.py
# holds it to the constant.
$bindHost = (Get-P20Consts).agent.bindHost
$uvArgs = @($python.Prefix) + @('-m', 'uvicorn', 'agent.app:app', '--host', $bindHost, '--port', "$Port")
if ($Dev) { $uvArgs += '--reload' }

Write-Host "  Starting the agent on http://localhost:$Port ..." -ForegroundColor Cyan

# Started from the REPO ROOT: `agent` is imported as a package (agent.app:app),
# so the working directory has to be its parent.
# Through Start-DetachedProcess, not Start-Process, so that a caller reading
# this command's output through a PIPE gets EOF when the launcher returns
# instead of when the agent stops -- see Scripts/Start-Detached.ps1 for the
# Windows handle-inheritance reason. Dot-sourced here rather than at the top of
# the file: this is the only thing in the script that starts anything.
# $uvArgs already carries the interpreter's own leading arguments (py -3).
. (Join-Path $PSScriptRoot 'Start-Detached.ps1')

try {
    $proc = Start-DetachedProcess -FilePath $python.Exe -ArgumentList $uvArgs `
        -WorkingDirectory $repoRoot -StdOutLog $logFile -StdErrLog $errFile
}
catch {
    Write-CliError -Message "Could not start the agent: $($_.Exception.Message)" `
        -Hint "Try it by hand: cd $repoRoot; $($python.Display) -m uvicorn agent.app:app --port $Port"
    Write-AgentLog 'ERR' $_.Exception.Message
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$proc.Id | Set-Content $pidFile -Encoding UTF8

Start-Sleep -Seconds 2
if ((Get-AgentProcessId) -gt 0) {
    Write-Host "  Agent started (PID $($proc.Id))." -ForegroundColor Green
    Write-AgentLog 'CMD' "start on $Port"
    exit 0
}

Write-CliError -Message 'The agent exited immediately after starting.' `
    -Hint "Read agent.err.log at the repository root, or run it by hand: cd $repoRoot; $($python.Display) -m uvicorn agent.app:app --port $Port"
Write-AgentLog 'ERR' 'exited immediately'
Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
