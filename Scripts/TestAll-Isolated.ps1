<#
.SYNOPSIS
    {cliPrefix}Test -Isolated: a run with a home, a temp folder and a test history
    of its own. Dot-source it.

.DESCRIPTION
    Not a command. Two full runs started at the same moment on one Mac can crash
    each other at PowerShell's startup: both read and write the same caches under
    the home folder. -Isolated gives a run a folder of its own and starts the
    usual run (this same verb, without the switch) in a child whose environment
    points every home-derived place into that folder. The launcher's own
    environment is never changed.

      Get-P20IsolatedRunName      the folder's name: prefix, process id and a
                                  random part, so two runs started in the same
                                  second by the same user cannot share one.
      Test-P20IsolatedRunDir      whether a path is one of those folders -- the
                                  check that guards the removal.
      Get-P20IsolatedRunPlan      THE PLAN, pure: the run folder and the current
                                  environment in; the variables to set, the
                                  folders to make and what to carry from the
                                  real home out.
      Initialize-P20IsolatedRun   makes the folders and carries what exists.
      Invoke-P20IsolatedChild     starts the child, its output straight to this
                                  console, and waits for it to exit.
      Remove-P20IsolatedRunDir    removes the folder, links and all, without
                                  following a link.
      Set-P20IsolatedRunKept      marks a folder -Keep left, so no sweep takes it.
      Remove-P20StaleIsolatedRunDirs
                                  removes the folders a killed run left: run
                                  folders older than a day, not kept, and not
                                  of a live process. Returns the paths removed.

    What a run carries from the real home, and why:
      the test venv (Get-P20TestVenvHomeName), as a LINK: the agent half picks
          the test venv first, and a home without it would fall to the PATH's
          Python and may skip the half;
      git's global configuration (~/.gitconfig, and git/config, git/ignore and
          git/attributes under the XDG config folder), as COPIES: a suite that
          builds a fixture repository reads the same settings it reads in a
          plain run, and a suite that wrote one would write the copy.
    Nothing else: gh's and az's sign-ins stay in the real home, because no suite
    may reach a real tracker.

    The folder sits in /tmp, not in the per-user temp folder: .NET puts a
    diagnostics socket for every process in TMPDIR, a socket path on macOS holds
    at most 104 bytes, and the per-user temp folder plus a run folder is long
    enough to cut that name short -- two processes would then aim at one socket.

    Ports: none. No half binds a fixed port -- the suites that serve HTTP ask
    the system for a free one (port 0) -- so there is nothing to offset.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
    -Isolated itself runs on macOS only; the pure functions run on every host.
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Get-P20TestVenvHomeName -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-Python.ps1')
}

function Get-P20IsolatedRunPrefix {
    <# The front of every run folder's name, and the base it sits in. #>
    # MaxAgeDays: how old a folder is before the next run may sweep it.
    # KeptMarker: the file -Keep leaves inside a folder; a sweep never takes
    # a folder that holds it. SweptLine: what a run says of each folder it swept.
    # SweepBase: where the sweep looks. It is Base, unless P20_ISOLATED_SWEEP_BASE
    # names another folder -- the test suite's seam, so a stubbed run never
    # sweeps the real /tmp. Nothing else reads the variable.
    $sweepBase = '/tmp'
    $seam = [Environment]::GetEnvironmentVariable('P20_ISOLATED_SWEEP_BASE')
    if ($seam -and $seam.Trim()) { $sweepBase = $seam.Trim() }
    return @{
        Prefix     = 'p20-isolated'
        Base       = '/tmp'
        SweepBase  = $sweepBase
        MaxAgeDays = 1
        KeptMarker = '.p20-kept'
        SweptLine  = 'Removed {0}, left by an earlier isolated run that was stopped.'
    }
}

function Get-P20IsolatedRunName {
    <#
      p20-isolated-<process id>-<random>. -Random is the random part, given by
      the caller; without it, eight lowercase letters and digits from a GUID.
    #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$Random
    )
    if (-not $Random) { $Random = ([guid]::NewGuid().ToString('N')).Substring(0, 8) }
    return ('{0}-{1}-{2}' -f (Get-P20IsolatedRunPrefix).Prefix, $ProcessId, $Random)
}

function Test-P20IsolatedRunDir {
    <# True when the path's leaf has the run folder's shape -- and only then is it removed. #>
    param([AllowEmptyString()][string]$Path)
    if (-not $Path) { return $false }
    $leaf = Split-Path -Leaf ($Path.TrimEnd('/', '\'))
    return ($leaf -cmatch ('^' + [regex]::Escape((Get-P20IsolatedRunPrefix).Prefix) + '-\d+-[a-z0-9]+$'))
}

function Get-P20IsolatedRunPlan {
    <#
      The plan, pure. -RunDir is the run's folder; -Environment the current
      environment, name -> value (an absent or blank name is unset). Returns
        Variables  ordered name -> value: what the child's environment sets
        Folders    the folders to make, the run folder first
        Carry      @{ Kind = 'link' | 'copy'; From; To } -- the real home's
                   test venv and git configuration; Initialize carries the
                   ones that exist. None without a home to carry from.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [System.Collections.IDictionary]$Environment = @{}
    )
    $read = {
        param([string]$Name)
        if (-not $Environment.Contains($Name)) { return '' }
        $v = $Environment[$Name]
        if ($null -eq $v) { return '' }
        return ([string]$v).Trim()
    }
    $c = Get-P20Consts
    $runHome = Join-Path $RunDir 'home'
    $runTmp = Join-Path $RunDir 'tmp'
    $runCache = Join-Path $RunDir 'cache'
    $runData = Join-Path $RunDir 'data'
    $runConfig = Join-Path $RunDir 'config'
    $runHistory = Join-Path $RunDir 'history'

    $vars = [ordered]@{}
    $vars['HOME'] = $runHome
    $vars['TMPDIR'] = $runTmp
    $vars['TMP'] = $runTmp
    $vars['TEMP'] = $runTmp
    # PowerShell's caches (StartupProfileData-*, ModuleAnalysisCache-*) follow
    # XDG_CACHE_HOME; the other two are set so nothing reaches the real ones.
    $vars['XDG_CACHE_HOME'] = $runCache
    $vars['XDG_DATA_HOME'] = $runData
    $vars['XDG_CONFIG_HOME'] = $runConfig
    # The run's test history: the verb and the CLI runner both read it.
    $vars[[string]$c.env.testHistoryDir] = $runHistory

    $folders = @($RunDir, $runHome, $runTmp, $runCache, $runData, $runConfig, $runHistory)

    $carry = @()
    $realHome = & $read 'HOME'
    if ($realHome) {
        $venv = Get-P20TestVenvHomeName
        $carry += @{ Kind = 'link'; From = (Join-Path $realHome $venv); To = (Join-Path $runHome $venv) }
        $carry += @{ Kind = 'copy'; From = (Join-Path $realHome '.gitconfig'); To = (Join-Path $runHome '.gitconfig') }
        $realConfig = & $read 'XDG_CONFIG_HOME'
        if (-not $realConfig) { $realConfig = Join-Path $realHome '.config' }
        foreach ($name in @('config', 'ignore', 'attributes')) {
            $carry += @{ Kind = 'copy'; From = (Join-Path (Join-Path $realConfig 'git') $name); To = (Join-Path (Join-Path $runConfig 'git') $name) }
        }
    }
    return [ordered]@{ Variables = $vars; Folders = $folders; Carry = $carry }
}

function Initialize-P20IsolatedRun {
    <#
      Makes the plan's folders (the run folder must not exist yet, and is made
      readable by this user alone) and carries each Carry entry whose source
      exists. Returns the entries it carried.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan)
    $runDir = [string]$Plan.Folders[0]
    if (Test-Path -LiteralPath $runDir) { throw "the run folder $runDir exists already" }
    foreach ($f in $Plan.Folders) { $null = New-Item -ItemType Directory -Path $f -Force }
    $null = & /bin/chmod 700 $runDir
    $carried = @()
    foreach ($e in $Plan.Carry) {
        if (-not (Test-Path -LiteralPath $e.From)) { continue }
        $parent = Split-Path -Parent $e.To
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        if ($e.Kind -eq 'link') { $null = New-Item -ItemType SymbolicLink -Path $e.To -Target $e.From }
        else { Copy-Item -LiteralPath $e.From -Destination $e.To }
        $carried += $e
    }
    return $carried
}

function Invoke-P20IsolatedChild {
    <#
      Starts -Exe with -Arguments in -WorkDir, the environment this process has
      with -Variables over it, and waits for it to exit; returns its exit code.
      Nothing is redirected: the child writes to this console itself, and this
      waits on the PROCESS, not on a pipe, so a grandchild that keeps the console
      open cannot hold the launcher. The wait is in short steps, so Ctrl+C
      (which reaches the child as well) can stop it.
    #>
    param(
        [Parameter(Mandatory)][string]$Exe,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkDir,
        [System.Collections.IDictionary]$Variables = @{}
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    foreach ($k in $Variables.Keys) { $psi.Environment[[string]$k] = [string]$Variables[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $done = $false
        while (-not $done) { $done = $p.WaitForExit(500) }
        $p.WaitForExit()
        return [int]$p.ExitCode
    }
    finally {
        # Wait for the exit after the kill, so the folder is not removed under a
        # child that is still writing into it.
        if (-not $p.HasExited) { try { $p.Kill(); $null = $p.WaitForExit(5000) } catch { $null = $_ } }
        $p.Dispose()
    }
}

function Remove-P20IsolatedRunDir {
    <#
      Removes a run folder with rm -rf, which never follows a symbolic link, so
      the linked test venv is unlinked and the real one untouched. Refuses any
      path that is not a run folder. Returns $true when the folder is gone.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-P20IsolatedRunDir $Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $null = & /bin/rm -rf -- $Path
    return (-not (Test-Path -LiteralPath $Path))
}

function Set-P20IsolatedRunKept {
    <# Marks a run folder as kept by -Keep, so a later run's sweep leaves it. #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-P20IsolatedRunDir $Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    try {
        [System.IO.File]::WriteAllText((Join-Path $Path (Get-P20IsolatedRunPrefix).KeptMarker), '')
        return $true
    }
    catch { return $false }
}

function Remove-P20StaleIsolatedRunDirs {
    <#
      Removes the run folders a killed run left behind, which no finally
      survives. Only a direct child of -Base whose name is a run folder's
      (Test-P20IsolatedRunDir) is ever looked at; nothing else in -Base is
      touched. A folder stays when
        - it is not older than -MaxAgeDays (default: a day) by its last write,
        - it holds the -Keep marker (Set-P20IsolatedRunKept), or
        - the process id in its name is alive: a run that is still going is
          never removed, whatever its age. A reused id keeps a dead run's
          folder a while longer, and that is the safe way to be wrong.
      -Now and -Base are the caller's to give (a suite gives a scratch base).
      Returns the paths it removed, in name order.
    #>
    param(
        [string]$Base = (Get-P20IsolatedRunPrefix).SweepBase,
        [double]$MaxAgeDays = (Get-P20IsolatedRunPrefix).MaxAgeDays,
        [datetime]$Now = (Get-Date)
    )
    $removed = @()
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) { return $removed }
    $marker = (Get-P20IsolatedRunPrefix).KeptMarker
    $cutoff = $Now.AddDays(-$MaxAgeDays)
    foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if (-not (Test-P20IsolatedRunDir $d.Name)) { continue }
        if ($d.LinkType) { continue }
        if ($d.LastWriteTime -ge $cutoff) { continue }
        if (Test-Path -LiteralPath (Join-Path $d.FullName $marker)) { continue }
        $m = [regex]::Match($d.Name, '^' + [regex]::Escape((Get-P20IsolatedRunPrefix).Prefix) + '-(\d+)-')
        $procId = 0
        if ($m.Success -and [int]::TryParse($m.Groups[1].Value, [ref]$procId) -and $procId -gt 0) {
            if (Get-Process -Id $procId -ErrorAction SilentlyContinue) { continue }
        }
        if (Remove-P20IsolatedRunDir -Path $d.FullName) { $removed += $d.FullName }
    }
    return $removed
}
