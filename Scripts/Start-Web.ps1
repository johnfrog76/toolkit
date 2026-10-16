#Requires -Version 5.1
<#
.SYNOPSIS
    Start, stop or check the web UI -- Vite plus the agent in dev, Docker in
    production.
.DESCRIPTION
    Two paths, and they are genuinely different things:

      -Dev        Vite on the host (npm run dev in web/) plus the agent, both
                  backgrounded so -Status can report them and -Stop can end
                  them. Vite proxies /api to the agent, so nothing is exposed
                  but one port. No Docker involved.

      (default)   The production image: docker compose up --build in web/,
                  with the agent alongside it. Docker being absent is a
                  sentence, not a stack trace -- this is the one machine
                  difference most likely to be true of a fresh clone.

    The agent half is never reimplemented here: every start, stop and status
    goes through Start-Agent.ps1, so there is one definition of what running
    the agent means.
.EXAMPLE
    {cliPrefix}Web              Start the production build (Docker)
    {cliPrefix}Web -Dev         Start Vite and the agent, with hot reload
    {cliPrefix}Web -Status      What is up, and on which port
    {cliPrefix}Web -Stop        Stop both halves
    {cliPrefix}Web -Restart     Stop, then start again
    {cliPrefix}Web -Dev -Fixture -Modules on
                                The smoke's servers: the fixture hub, as a test run
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoBrowser', Justification = 'Read inside Open-WebUi, a function defined in this script, which the rule does not follow.')]
[CmdletBinding()]
param(
    [switch]$Dev,
    # -Dev against Tests/fixtures/hub, as a TEST RUN, without writing a byte of
    # config.local.json. The agent -- and every bridge child it
    # forks -- gets the run marker, PROMPTS_ROOT, the fixture's Space and the
    # flags through the environment, and no TEAMS_WEBHOOK_* at all. See
    # Get-FixtureEnvironment below.
    [switch]$Fixture,
    # Which flags the fixture's agent starts with: 'off' (the default) sets
    # none, 'on' sets growth and communication -- the two configurations
    # `npm run smoke` asserts with --modules=off and --modules=on.
    [ValidateSet('on', 'off')]
    [string]$Modules,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Status,
    # The command's whole purpose is to bring the UI up for the person who typed
    # it, so it opens the URL once the server answers -- the predecessor did,
    # and copying the URL back out by hand is a step it never asked for. This
    # switch is the way to say no, and a non-interactive caller (CI, an agent
    # tool call, anything with a redirected stdout) is never asked.
    [switch]$NoBrowser,
    [switch]$Help
)

# Scripts/ -> repo root, from this file's own location.
$repoRoot = Split-Path $PSScriptRoot -Parent
$webPath = Join-Path $repoRoot 'web'
$agentScript = Join-Path $PSScriptRoot 'Start-Agent.ps1'

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$script:IsWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

$pidFile = Join-Path $repoRoot '.web.pid'
$logFile = Join-Path $repoRoot 'web.log'
$errFile = Join-Path $repoRoot 'web.err.log'

function Write-WebLog {
    param([string]$Type, [string]$Detail)
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type $Type -Source "$(Get-CliPrefix)Web" -Detail $Detail
    }
}

function Show-ConfigHelp {
    # One renderer, shared with the other launcher: the same config entry, the
    # same switches, examples and notes, whether this script runs as a tk* verb
    # or as a plain .ps1. See Scripts/Show-ConfigHelp.ps1.
    . (Join-Path $PSScriptRoot 'Show-ConfigHelp.ps1')
    Show-P20ConfigHelp -CommandName 'Web' -RepoRoot $repoRoot -Prefix (Get-CliPrefix) `
        -Fallback 'Start, stop or check the web UI.'
}

function Get-DevServerProcessId {
    if (-not (Test-Path $pidFile)) { return 0 }
    $raw = (Get-Content $pidFile -Raw).Trim()
    if (-not $raw) { return 0 }
    try {
        $proc = Get-Process -Id $raw -ErrorAction Stop
        if ($proc -and -not $proc.HasExited) { return [int]$raw }
        return 0
    }
    catch {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return 0
    }
}

# Vite asks for 5174 and takes the next free port if it is busy, so the URL is
# read back out of its own output rather than assumed.
function Get-DevServerUrl {
    if (-not (Test-Path $logFile)) { return '' }
    $line = Get-Content $logFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'https?://localhost:\d+' } |
        Select-Object -Last 1
    if (-not $line) { return '' }
    $found = [regex]::Match($line, 'https?://localhost:\d+')
    if ($found.Success) { return $found.Value }
    return ''
}

# -- The dev port, and who is on it --------------------------------------------
# The PID file holds the `npm` launcher, and `vite` -- its child -- is what holds
# the socket. Killing the launcher alone left a live server on a fixed port that
# -Status then denied existed, and `npm run smoke` defaults to that port, so the
# orphan could quietly serve a stale tree to a passing test run. Everything below
# is about reaching the child and about trusting the port as well as the file.
#
# The three helpers are declared behind Get-Command guards because that is the
# shim point Tests/Test-Web.ps1 replaces: the suite has no real server to point
# at and must never kill a real process.

$script:DefaultDevPort = 5174

# -- Opening the UI ------------------------------------------------------------
# The predecessor's Web verb opened a browser on all three start paths,
# unconditionally. This one
# opens it too, but only when a PERSON is there: the owner's standing rule for the UI
# side is "no popup ever, unless I act on it", and typing this command is that
# act while a script running it is not.
#
#
# Both halves are behind Get-Command guards so the suite can replace them:
# nothing in a test run may open a window, and the assertion is that the right
# URL was passed rather than that a browser appeared.
if (-not (Get-Command Test-BrowserAllowed -ErrorAction SilentlyContinue)) {
    function Test-BrowserAllowed {
        # Is a PERSON there -- nothing about what they asked for. -NoBrowser is
        # the caller's business, checked in Open-WebUi, so that a suite which
        # stubs this answer still honours the switch.
        if ($env:CI) { return $false }
        try {
            if (-not [Environment]::UserInteractive) { return $false }
            if ([Console]::IsOutputRedirected) { return $false }
        }
        catch { return $false }
        return $true
    }
}

if (-not (Get-Command Open-WebBrowser -ErrorAction SilentlyContinue)) {
    function Open-WebBrowser {
        param([string]$Url)
        if (-not $Url) { return }
        try {
            if ($script:IsWin) {
                # The one Start-Process left in this file, and it starts a
                # DOCUMENT rather than a server: no redirection, nothing to
                # wait for, nothing to return. Scripts/Start-Detached.ps1 owns
                # the other kind.
                Start-Process $Url | Out-Null
            }
            elseif (($PSVersionTable.PSEdition -ne 'Desktop') -and $IsMacOS) { & open $Url }
            else { & xdg-open $Url 2>$null }
        }
        catch {
            # A machine with no browser, or none registered, is not a failed
            # start. The URL is on screen either way.
            Write-Verbose "Could not open $Url : $($_.Exception.Message)"
        }
    }
}

# One place decides whether and what to open, so the three start paths cannot
# disagree about it.
function Open-WebUi {
    param([string]$Url)
    if (-not $Url) { return }
    if ($NoBrowser -or -not (Test-BrowserAllowed)) {
        Write-Host "  Open it at $Url" -ForegroundColor Gray
        return
    }
    Write-Host "  Opening $Url ..." -ForegroundColor Gray
    Open-WebBrowser -Url $Url
}

# The port the production container publishes, read from docker-compose.yml's
# `ports:` mapping ("127.0.0.1:5174:5173" -- host interface, host port, container
# port; the interface is optional here). Same rule as the dev path: the
# file that decides is the file that is read.
function Get-ProductionPort {
    $compose = Join-Path $webPath 'docker-compose.yml'
    if (Test-Path $compose) {
        $m = [regex]::Match((Get-Content $compose -Raw -ErrorAction SilentlyContinue), '"(?:[\d.]+:)?(\d+):\d+"')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return $script:DefaultDevPort
}

# Both the port Vite is CONFIGURED to ask for and the one it actually took, which
# differ exactly when an orphan already holds the configured one -- the case this
# whole block exists for.
function Get-DevServerPorts {
    $ports = @()
    $viteConfig = Join-Path $webPath 'vite.config.ts'
    if (Test-Path $viteConfig) {
        $m = [regex]::Match((Get-Content $viteConfig -Raw -ErrorAction SilentlyContinue), 'port:\s*(\d+)')
        if ($m.Success) { $ports += [int]$m.Groups[1].Value }
    }
    if ($ports.Count -eq 0) { $ports += $script:DefaultDevPort }
    $url = Get-DevServerUrl
    if ($url -and $url -match ':(\d+)') { $ports += [int]$Matches[1] }
    return @($ports | Select-Object -Unique)
}

# The OS probe itself is shared with Start-Agent.ps1 -- both launchers ask the
# same two questions of the same operating system, and only the POLICY differs.
# See Scripts/Get-PortListeners.ps1.
. (Join-Path $PSScriptRoot 'Get-PortListeners.ps1')

# -- The agent's port, handed to the two proxies -------------------------------
# web.agentPort decides where Start-Agent.ps1 listens. Vite's dev proxy and
# nginx's both point at that port and neither can read config, so, before the port had one reader,
# each carried 4100 in source and `tkAgent -Port <n>` produced a web
# UI that could not reach its agent. Both start paths now export the resolved
# port under the contract's variable name (consts.json env.agentPort) before
# they launch anything: Vite reads it in vite.config.ts, docker compose passes it
# to the nginx image's envsubst template. One resolver, shared with the agent's
# launcher: Scripts/Get-AgentPort.ps1.
. (Join-Path $PSScriptRoot 'Get-AgentPort.ps1')
function Export-AgentPortForProxies {
    $port = Get-P20AgentPort -RepoRoot $repoRoot
    Set-Item -Path "env:$(Get-P20AgentPortEnvName)" -Value ([string]$port)
    return $port
}

# -- Fixture mode: the smoke's servers, with nothing written --------------------
# Running `npm run smoke` used to mean rewriting the machine's own
# config.local.json twice -- promptsRoot at the fixture hub, activeSpace 'test',
# a features block for --modules=on and none for off -- and restoring it after;
# forgetting the restore left the real hub unplugged. And on the machine
# whose .env holds a webhook, the agent `-Dev` started inherited it: the module
# reads .env into THIS process at import, Start-DetachedProcess hands the
# process's environment to the child, and the modules-on smoke failed on an
# enabled send button with no documented way out.
#
# -Fixture answers both through the environment, for the servers only:
#
#   the run marker (consts.json env.testRunMarker)   the Teams engine refuses a
#                    POST, and every bridge child skips .env at import
#   PROMPTS_ROOT     Tests/fixtures/hub
#   env.activeSpace  the fixture's Space, standing in for config.local.json's
#   env.features     {} or growth+communication, standing in for its features
#   TEAMS_WEBHOOK_*  REMOVED -- the marker stops .env being read again in a
#                    child, but not a value this shell already holds
#
# The Space is the one Tests/fixtures/hub/hub.json declares; the flags are what
# web/tests/smoke.mjs asserts in each mode ("organize" is left unset on purpose:
# the smoke reads it back from /api/env and asserts either shape).
$script:FixtureHub = 'Tests/fixtures/hub'
$script:FixtureSpace = 'test'
$script:FixtureFlagsOn = '{"growth":true,"communication":true}'

function Get-FixtureEnvironment {
    param([string]$ModuleFlags)
    $consts = Get-P20Consts
    $map = @{}
    $map[[string]$consts.env.testRunMarker] = 'fixture'
    $map['PROMPTS_ROOT'] = (Join-Path $repoRoot $script:FixtureHub)
    $map[[string]$consts.env.activeSpace] = $script:FixtureSpace
    $flags = '{}'
    if ($ModuleFlags -eq 'on') { $flags = $script:FixtureFlagsOn }
    $map[[string]$consts.env.features] = $flags
    # By pattern, the way the test runners clear them: whatever recipient a
    # machine has configured, none of them reaches a fixture server.
    $prefix = [string]$consts.env.teamsWebhookPrefix
    foreach ($v in @(Get-ChildItem Env: | Where-Object { $_.Name -like "$prefix*" })) {
        $map[$v.Name] = $null
    }
    return $map
}

if (-not (Get-Command Get-WebPortListenerIds -ErrorAction SilentlyContinue)) {
    function Get-WebPortListenerIds {
        param([int]$Port)
        return @(Get-P20PortListenerIds -Port $Port)
    }
}

if (-not (Get-Command Get-WebChildProcessIds -ErrorAction SilentlyContinue)) {
    function Get-WebChildProcessIds {
        param([int]$ProcessId)
        $kids = @()
        try {
            if ($script:IsWin) {
                if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty ProcessId)
                }
                else {
                    # No CimCmdlets (a narrowed PSModulePath): pwsh 7's
                    # Process carries .Parent; 5.1's does not, and answers none.
                    $kids = @(Get-Process -ErrorAction SilentlyContinue |
                        Where-Object { $_.PSObject.Properties['Parent'] -and $_.Parent -and $_.Parent.Id -eq $ProcessId } |
                        Select-Object -ExpandProperty Id)
                }
            }
            elseif (Get-Command pgrep -ErrorAction SilentlyContinue) {
                $kids = @(& pgrep -P $ProcessId 2>$null)
            }
        }
        catch { $kids = @() }
        return @($kids | Where-Object { $_ } | ForEach-Object { [int]$_ })
    }
}

function Get-WebDescendantIds {
    param([int]$ProcessId)
    $all = @()
    if ($ProcessId -le 0) { return $all }
    foreach ($child in (Get-WebChildProcessIds -ProcessId $ProcessId)) {
        $all += $child
        $all += Get-WebDescendantIds -ProcessId $child
    }
    return @($all)
}

# What a listener actually IS. The sweep below may only stop a dev server, and
# "is it ours?" cannot be answered from the PID file alone -- a Vite orphaned by
# a dead npm has no entry there. The image name is the second question, and the
# only one that distinguishes a stray `node` from a system service that happens
# to publish the same port.
if (-not (Get-Command Get-WebProcessName -ErrorAction SilentlyContinue)) {
    function Get-WebProcessName {
        param([int]$ProcessId)
        return (Get-P20ProcessNameById -ProcessId $ProcessId)
    }
}

# Vite runs inside node, and nothing else this command starts does. The match is
# on the image name only -- `node`, or `node.exe` on Windows.
function Test-IsDevServerProcess {
    param([string]$Name)
    if (-not $Name) { return $false }
    return (($Name -eq 'node') -or ($Name -eq 'node.exe'))
}

if (-not (Get-Command Stop-WebProcessTree -ErrorAction SilentlyContinue)) {
    function Stop-WebProcessTree {
        param([int]$ProcessId)
        # Children first: killing the parent on its own is what orphaned vite.
        foreach ($child in (Get-WebChildProcessIds -ProcessId $ProcessId)) {
            Stop-WebProcessTree -ProcessId $child
        }
        try { Stop-Process -Id $ProcessId -Force -ErrorAction Stop }
        catch { $null = $_ }
    }
}

# Behind Get-Command guards for the same reason the port helpers are: the suite
# has no Docker to ask and must never run compose against a real one.
if (-not (Get-Command Test-DockerAvailable -ErrorAction SilentlyContinue)) {
    function Test-DockerAvailable {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
        try {
            $null = docker info 2>$null
            return ($LASTEXITCODE -eq 0)
        }
        catch {
            return $false
        }
    }
}

# One definition of "take the container down", called by -Stop and -Restart.
if (-not (Get-Command Invoke-WebComposeDown -ErrorAction SilentlyContinue)) {
    function Invoke-WebComposeDown {
        Push-Location $webPath
        try { docker compose down 2>$null | Out-Null }
        finally { Pop-Location }
    }
}

# -- Order matters here ---------------------------------------------------------
# `docker compose down` FIRST, then the port sweep. In production the only
# listeners on the dev port are Docker's own forwards -- on Windows a WSL relay
# and com.docker.backend.exe -- so a sweep that ran first force-killed Docker
# Desktop's backend, which then made Test-DockerAvailable false, which skipped
# the compose down it was about to do. The container was left defined, Docker had
# to be restarted by hand, and everything else the user had running in it went
# with it.
function Stop-WebContainer {
    if (-not (Test-DockerAvailable)) { return }
    Invoke-WebComposeDown
}

function Stop-DevServer {
    $running = Get-DevServerProcessId
    $stopped = $false
    $ours = @()

    if ($running -gt 0) {
        # Captured BEFORE the kill: afterwards there is nothing left to walk,
        # and these are the ids the port sweep below must not re-report.
        $ours = @($running) + (Get-WebDescendantIds -ProcessId $running)
        Stop-WebProcessTree -ProcessId $running
        Write-Host "  Dev server stopped (PID $running and its children)." -ForegroundColor Green
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        $stopped = $true
        Start-Sleep -Milliseconds 200
    }

    # An orphan from a run whose PID file is gone is still a live server on the
    # port `npm run smoke` defaults to. Stop it and name it; do not deny it.
    #
    # But only if it is a dev server. This sweep used to kill EVERY listener it
    # did not recognise, which in production mode meant Docker Desktop's port
    # forward for the container -- a third-party system service the user never
    # asked to stop. Anything that is not node is reported and left alone; being
    # unrecognised is not evidence of being an orphan.
    foreach ($port in (Get-DevServerPorts)) {
        foreach ($listener in (Get-WebPortListenerIds -Port $port)) {
            if ($ours -contains $listener) { continue }
            $name = Get-WebProcessName -ProcessId $listener
            if (-not (Test-IsDevServerProcess $name)) {
                $label = $name
                if (-not $label) { $label = 'an unknown process' }
                Write-Host "  Port $port is held by $label (PID $listener) -- not a dev server; not stopping it." -ForegroundColor Yellow
                continue
            }
            Stop-WebProcessTree -ProcessId $listener
            Write-Host "  Also stopped PID $listener ($name), which was still listening on port $port." -ForegroundColor Yellow
            $stopped = $true
        }
    }

    return $stopped
}

if ($Help) { Show-ConfigHelp; exit 0 }

if (-not (Test-Path $webPath)) {
    Write-CliError -Message "No web/ directory at $webPath." `
        -Hint 'The web UI ships in this repo; a checkout missing it is incomplete.'
    Write-WebLog 'ERR' 'web/ not found'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -Modules picks the fixture's flags, so it means nothing on the machine's own
# config -- where the flags are config.local.json's -- and -Fixture starts the
# dev servers, never the Docker image. Said before anything starts or stops.
if ($Modules -and -not $Fixture) {
    Write-CliError -Message '-Modules sets the fixture''s feature flags, and needs -Fixture.' `
        -Hint "Run: $(Get-CliPrefix)Web -Dev -Fixture -Modules $Modules   (your own flags are config.local.json's: $(Get-CliPrefix)Config -Set features.growth=true)"
    Write-WebLog 'ERR' '-Modules without -Fixture'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Fixture -and (-not $Dev -or $Stop -or $Status)) {
    Write-CliError -Message '-Fixture starts the dev servers against the fixture hub, so it goes with -Dev and nothing else.' `
        -Hint "Run: $(Get-CliPrefix)Web -Dev -Fixture [-Modules on|off]. To go back to your own hub afterwards: $(Get-CliPrefix)Web -Dev"
    Write-WebLog 'ERR' '-Fixture without -Dev'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Status --------------------------------------------------------------------

if ($Status) {
    $devPid = Get-DevServerProcessId
    if ($devPid -gt 0) {
        $url = Get-DevServerUrl
        if (-not $url) { $url = '(port not yet printed)' }
        Write-Host "  Dev server is running (PID $devPid) on $url" -ForegroundColor Green
    }
    else {
        Write-Host "  Dev server is not running." -ForegroundColor Yellow
    }

    # The PID file is not the whole truth. It records the launcher, so a child
    # that outlived a -Stop keeps serving on a port this command used to say was
    # free -- and the smoke test's default port is that port. Probe it.
    $ours = @()
    if ($devPid -gt 0) { $ours = @($devPid) + (Get-WebDescendantIds -ProcessId $devPid) }
    # The same two questions -Stop asks, answered out loud. Saying "-Stop will
    # end it" about a process -Stop must not touch is how a user came to kill
    # Docker Desktop by following this command's advice.
    $orphans = @()
    foreach ($port in (Get-DevServerPorts)) {
        foreach ($listener in (Get-WebPortListenerIds -Port $port)) {
            if ($ours -contains $listener) { continue }
            $name = Get-WebProcessName -ProcessId $listener
            if (Test-IsDevServerProcess $name) {
                $orphans += $listener
                Write-Host "  Port $port is still being served by PID $listener ($name), which this command did not start." -ForegroundColor Yellow
            }
            else {
                $label = $name
                if (-not $label) { $label = 'an unknown process' }
                Write-Host "  Port $port is held by $label (PID $listener) -- not a dev server; not stopping it." -ForegroundColor Yellow
            }
        }
    }
    if ($orphans.Count -gt 0) {
        Write-Host "  $(Get-CliPrefix)Web -Stop will end it; until then a smoke run on that port drives a stale server." -ForegroundColor Gray
    }

    if (Test-DockerAvailable) {
        Push-Location $webPath
        try {
            # -q prints ids and nothing else, so there is no header row to
            # mistake for a running container.
            $containers = @(docker compose ps --status running -q 2>$null | Where-Object { $_ })
            if ($containers.Count -gt 0) {
                Write-Host "  Docker: $($containers.Count) container(s) running." -ForegroundColor Green
            }
            else {
                Write-Host "  No Docker containers running." -ForegroundColor Yellow
            }
        }
        finally { Pop-Location }
    }
    else {
        Write-Host "  Docker is not available -- production mode is unavailable on this machine." -ForegroundColor DarkGray
    }

    & $agentScript -Status
    Write-WebLog 'CMD' 'status'
    exit 0
}

# -- Stop ----------------------------------------------------------------------

if ($Stop) {
    # The container FIRST: its port forward is what would otherwise still be on
    # the dev port when the sweep looks.
    Stop-WebContainer
    $stoppedAnything = Stop-DevServer
    if (-not $stoppedAnything) {
        Write-Host "  Dev server is not running -- nothing to stop." -ForegroundColor Yellow
    }
    & $agentScript -Stop
    Write-WebLog 'CMD' 'stop'
    exit 0
}

# -Restart stops everything and then falls through to whichever mode the other
# switches name -- `-Restart` is production, `-Dev -Restart` is dev. It does not
# pick a mode of its own, because guessing which one you meant is how you end up
# with two servers on one port.
if ($Restart) {
    # Same order as -Stop, and for the same reason.
    Stop-WebContainer
    $null = Stop-DevServer
    & $agentScript -Stop
}

# -- Dev -----------------------------------------------------------------------

if ($Dev) {
    # Dot-sourced HERE, before the first guard, because the npm resolver lives
    # beside the launcher: one file owns both "what may be handed to
    # CreateProcess" and "how it is handed over". See Scripts/Start-Detached.ps1.
    . (Join-Path $PSScriptRoot 'Start-Detached.ps1')

    # Not `Get-Command npm`: on Windows that answers npm.ps1, which cannot be a
    # process image, and `tkWeb -Dev` died with "%1 is not a valid Win32
    # application" on every PC with a current Node install.
    $npm = Resolve-LaunchExecutable -Name 'npm'
    if (-not $npm) {
        Write-CliError -Message 'npm not found.' `
            -Hint 'Install Node.js (22 or later), then run npm ci in web/.'
        Write-WebLog 'ERR' 'npm not found'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not (Test-Path (Join-Path $webPath 'node_modules'))) {
        Write-CliError -Message 'web/node_modules is missing -- the dev server has nothing to run.' `
            -Hint "Run: cd $webPath; npm ci"
        Write-WebLog 'ERR' 'node_modules missing'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    # -Fixture: this checkout's agent is RESTARTED, never reused. A running
    # agent's environment can be neither read nor changed from here, and a
    # fixture agent started with the other -Modules is indistinguishable from
    # outside -- same hub, same package. Start-Agent.ps1 -Stop ends only this
    # checkout's agent; another package's is named and left alone.
    #
    # Then the fixture's environment is applied to THIS process for the rest of
    # the start and put back in the finally below -- not only handed to the two
    # launches -- because the agent's launcher asks the same questions its child
    # will: Test-HubMismatch compares the hub a running agent reports with the
    # PROMPTS_ROOT this shell asks for, and it has to be asking for the fixture.
    $fixtureSaved = $null
    if ($Fixture) {
        if (-not $Restart) { & $agentScript -Stop }
        $fixtureSaved = Push-ProcessEnvironment -Environment (Get-FixtureEnvironment -ModuleFlags $Modules)
        $flagsSaid = 'no feature flags'
        if ($Modules -eq 'on') { $flagsSaid = 'growth and communication on' }
        Write-Host "  Fixture mode: $($script:FixtureHub), Space '$($script:FixtureSpace)', $flagsSaid, as a test run (no webhook, no .env) -- config.local.json is not touched." -ForegroundColor Cyan
    }
    try {
        & $agentScript -Reuse
        if ($LASTEXITCODE -ne 0) {
            Write-CliError -Message 'The agent did not start, so the dev server would have nothing to proxy to.' `
                -Hint "Fix the agent first: $(Get-CliPrefix)Agent"
            Write-WebLog 'ERR' 'agent failed to start'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }

        $existing = Get-DevServerProcessId
        if ($existing -gt 0) {
            Write-Host "  Dev server is already running (PID $existing)." -ForegroundColor Yellow
            # Asked for the UI, so the UI opens -- the server being up already is
            # not a reason to make someone find the tab themselves.
            Open-WebUi -Url (Get-DevServerUrl)
            Write-WebLog 'CMD' 'dev (already running)'
            exit 0
        }

        Write-Host "  Starting the Vite dev server ..." -ForegroundColor Cyan
        # The child inherits this process's environment, so the export happens
        # here, before the launch, and Vite's config reads it as it starts.
        $agentPort = Export-AgentPortForProxies
        # Same launch as the agent's, and for the same reason: Vite runs for hours,
        # and a caller reading `tkWeb -Dev` through a pipe must not sit on the
        # handles the child would otherwise inherit. Start-DetachedProcess also
        # turns a .cmd shim into a cmd.exe launch, and off Windows gives the child
        # its own session and /dev/null as stdin -- see Scripts/Start-Detached.ps1.
        # CI=true, in Vite's environment only: it is Vite's documented switch for
        # the two things a detached server must not do -- exit when stdin ends,
        # and bind keyboard shortcuts on a terminal it shares with the shell that
        # started it. Not exported here:
        # Test-BrowserAllowed reads $env:CI to mean "no person is there".

        try {
            $proc = Start-DetachedProcess -FilePath $npm -ArgumentList @('run', 'dev') `
                -WorkingDirectory $webPath -StdOutLog $logFile -StdErrLog $errFile `
                -Environment @{ CI = 'true' }
        }
        catch {
            # This path has already started the agent. Say so rather than leave the
            # reader to find it with -Status: a failed -Dev that silently left a
            # server up is how a Windows verification run ended.
            Write-CliError -Message "Could not start the dev server: $($_.Exception.Message)" `
                -Hint "The agent is still running -- stop it with $(Get-CliPrefix)Web -Stop. Try the server by hand: cd $webPath; npm run dev"
            Write-WebLog 'ERR' $_.Exception.Message
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }

        $proc.Id | Set-Content $pidFile -Encoding UTF8

        # Wait for Vite to print its port rather than guessing 5174: it takes the
        # next free one, and a URL that is merely probable is worse than none.
        $url = ''
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 400
            $url = Get-DevServerUrl
            if ($url) { break }
            if ((Get-DevServerProcessId) -le 0) { break }
        }

        if ((Get-DevServerProcessId) -le 0) {
            Write-CliError -Message 'The dev server exited immediately after starting.' `
                -Hint 'Read web.err.log at the repository root.'
            Write-WebLog 'ERR' 'dev server exited immediately'
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }

        if ($url) {
            Write-Host "  Dev server running on $url (PID $($proc.Id))." -ForegroundColor Green
        }
        else {
            Write-Host "  Dev server running (PID $($proc.Id)) -- port not printed yet; see web.log." -ForegroundColor Yellow
        }
        Write-Host "  /api is proxied to the agent on port $agentPort. Stop both with $(Get-CliPrefix)Web -Stop." -ForegroundColor Gray
        # The URL Vite PRINTED, not the one it was asked for: it takes the next free
        # port silently, and opening a port that is merely likely is how a browser
        # ends up on someone else's server.
        Open-WebUi -Url $url
        Write-WebLog 'CMD' 'dev'
        exit 0
    }
    finally {
        # The caller's shell gets its own environment back -- webhooks included,
        # since they are its business; only the servers were started without them.
        Pop-ProcessEnvironment -Saved $fixtureSaved
    }
}

# -- Production (Docker) -------------------------------------------------------

if (-not (Test-DockerAvailable)) {
    Write-CliError -Message 'Docker is not available, so the production build cannot run.' `
        -Hint "Start Docker Desktop, or use $(Get-CliPrefix)Web -Dev, which needs only Node."
    Write-WebLog 'ERR' 'docker unavailable'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

& $agentScript -Reuse
if ($LASTEXITCODE -ne 0) {
    Write-CliError -Message 'The agent did not start, so the web UI would have no backend.' `
        -Hint "Fix the agent first: $(Get-CliPrefix)Agent"
    Write-WebLog 'ERR' 'agent failed to start'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

Write-Host "  Building and starting the web container ..." -ForegroundColor Cyan
# docker compose reads the variable from THIS shell's environment and hands it
# to the container, where nginx's entrypoint writes it into the proxy_pass.
$agentPort = Export-AgentPortForProxies
Write-Host "  The container proxies /api to the agent on port $agentPort." -ForegroundColor Gray
Push-Location $webPath
try {
    docker compose up --build -d
    if ($LASTEXITCODE -ne 0) {
        Write-CliError -Message 'docker compose up failed.' `
            -Hint 'Read the output above; the compose file lives in web/.'
        Write-WebLog 'ERR' 'docker compose up failed'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
finally { Pop-Location }

Write-Host "  Web UI running. Check it with $(Get-CliPrefix)Web -Status." -ForegroundColor Green
# The published port from docker-compose.yml's `ports:` mapping, not a number
# typed here -- the same rule the dev path follows by reading Vite's own output.
Open-WebUi -Url "http://localhost:$(Get-ProductionPort)"
Write-WebLog 'CMD' 'start'
exit 0
