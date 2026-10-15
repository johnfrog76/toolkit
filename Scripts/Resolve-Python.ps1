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
