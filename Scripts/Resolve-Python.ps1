#
# Which Python is the real one on this machine.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Start-Agent.ps1 and
# by Tests/Test-Agent.ps1. It is a file rather than a function inside the module
# for the same reason Resolve-HubConfig.ps1 is: the script that needs it also
# runs standalone, with no module in the session, and the answer must have
# exactly one implementation.
#
# The problem it solves, verified on the Windows floor (Windows 11
# Pro, Python 3.12.10 from python.org):
#
#   PS> (Get-Command python3).Source
#   C:\Users\...\AppData\Local\Microsoft\WindowsApps\python3.exe   # export:example
#   PS> python3 --version
#   Python was not found; run without arguments to install from the Microsoft
#   Store, or disable this shortcut from Settings > Apps > Advanced app settings
#   > App execution aliases.
#
# `python3` on Windows is normally that App Execution Alias -- a stub that
# resolves, reports a version of nothing, and runs nothing. Get-Command finds
# it. So a name on PATH is not evidence: every candidate is RUN, and only an
# interpreter that reports major version 3 is accepted.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

function Get-P20PythonCandidates {
    <#
      The interpreters to try, in order, for a platform.

      Windows: `python` first (python.org's installer puts the real one there,
      and it is the one verified on Windows), then `py -3` (the launcher, present with
      any python.org install and unaffected by the Store alias), then `python3`,
      which is usually the stub but is the right answer on a machine that only
      has one.

      Everywhere else: `python3` first, because `python` on macOS and most
      distributions is either absent or Python 2.

      Each candidate is @{ Exe = <command name>; Prefix = @(<leading args>) }.
    #>
    param([bool]$Windows)

    if ($Windows) {
        return @(
            @{ Exe = 'python'; Prefix = @() },
            @{ Exe = 'py'; Prefix = @('-3') },
            @{ Exe = 'python3'; Prefix = @() }
        )
    }
    return @(
        @{ Exe = 'python3'; Prefix = @() },
        @{ Exe = 'python'; Prefix = @() }
    )
}

function Resolve-P20Python {
    <#
      The first candidate that is present AND actually runs Python 3.

      Returns $null when there is none, or:
        @{ Exe = <resolved path>; Prefix = @(...); Display = 'py -3'; Version = '3.12.10' }

      Display is what a message should name -- the command a reader can retype,
      not the resolved path, and not `python3` when `python3` is the thing that
      does not work here.

      -Windows overrides the platform, which is what lets a macOS machine test the
      Windows ordering. -Candidates replaces the list entirely, for a test that
      wants one.
    #>
    param(
        [bool]$Windows = (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows),
        $Candidates = $null
    )

    if ($null -eq $Candidates) { $Candidates = Get-P20PythonCandidates -Windows $Windows }

    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }

        # Run it. The Store stub is on PATH and answers Get-Command; what it
        # does not do is execute this.
        $probeArgs = @($candidate.Prefix) + @('-c', 'import sys; print(sys.version.split()[0])')
        $out = ''
        try { $out = (& $cmd.Source @probeArgs 2>&1 | Out-String).Trim() }
        catch { $out = '' }
        if ($out -notmatch '^3\.\d') { continue }

        $display = $candidate.Exe
        if (@($candidate.Prefix).Count -gt 0) { $display = "$($candidate.Exe) $($candidate.Prefix -join ' ')" }
        return @{
            Exe     = $cmd.Source
            Prefix  = @($candidate.Prefix)
            Display = $display
            Version = $out
        }
    }
    return $null
}

function Get-P20TestVenvPythons {
    <#
      The test environments to try before the PATH, in order: a `.venv` inside the
      package, then `.venv-toolkit` in the home folder -- where docs/TESTING.md says
      to put the agent's dev requirements when the system Python is not the one
      that should hold them. Each is
      @{ Exe = <the venv's python>; Prefix = @(); Display = '~/.venv-toolkit/bin/python' };
      one that is not on disk is left out.

      Display is written with a leading `~` or the package-relative path, never the
      machine's own path, so it can be pasted.
    #>
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [bool]$Windows = (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows)
    )
    $rel = 'bin/python'
    if ($Windows) { $rel = 'Scripts/python.exe' }
    $homeDir = [System.Environment]::GetFolderPath('UserProfile')
    $roots = @(@{ Path = (Join-Path $PackageRoot '.venv'); Label = '.venv' })
    if ($homeDir) { $roots += @{ Path = (Join-Path $homeDir '.venv-toolkit'); Label = '~/.venv-toolkit' } }
    $found = @()
    foreach ($r in $roots) {
        $exe = Join-Path $r.Path $rel
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            $found += @{ Exe = $exe; Prefix = @(); Display = "$($r.Label)/$rel" }
        }
    }
    return $found
}

function Resolve-P20TestPython {
    <#
      The interpreter `tkTest` runs the agent half with: the first of the test
      venvs (Get-P20TestVenvPythons), then the PATH's (Resolve-P20Python's order),
      that imports BOTH pytest and httpx.

      Returns @{ Python = <candidate or $null>; Missing = <'' | 'pytest' | 'httpx'>;
                 Via = <what to call it: '~/.venv-toolkit/bin/python', 'python3 (PATH)'> }.
      With none that has both, Python is the PATH interpreter (or $null when there
      is none) and Missing names the module it lacked, so the caller's stated reason
      is the one it always was.
    #>
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [bool]$Windows = (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows)
    )
    $pathPython = Resolve-P20Python -Windows $Windows
    $candidates = @(Get-P20TestVenvPythons -PackageRoot $PackageRoot -Windows $Windows)
    if ($null -ne $pathPython) { $candidates += $pathPython }
    $result = @{ Python = $pathPython; Missing = ''; Via = '' }
    foreach ($c in $candidates) {
        $lacks = ''
        foreach ($mod in @('pytest', 'httpx')) {
            $probeArgs = @($c.Prefix) + @('-c', "import $mod")
            $global:LASTEXITCODE = 0
            $null = & $c.Exe @probeArgs 2>&1
            if ($LASTEXITCODE -ne 0) { $lacks = $mod; break }
        }
        $isPath = ($null -ne $pathPython -and $c.Exe -eq $pathPython.Exe)
        if (-not $lacks) {
            $result.Python = $c; $result.Missing = ''
            $result.Via = $c.Display
            if ($isPath) { $result.Via = "$($c.Display) (PATH)" }
            return $result
        }
        if ($isPath) { $result.Missing = $lacks }
    }
    return $result
}
