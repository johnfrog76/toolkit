<#
.SYNOPSIS
    The host a suite runs in, for the shells it starts. Dot-source it.

.DESCRIPTION
    Not a suite and not a command.

    A suite that typed `pwsh` for every child ran its verbs in PowerShell 7
    even when the suite itself ran under Windows PowerShell 5.1, so the 5.1
    job proved the suite's own code on 5.1 and every verb it drove on 7. A
    read that only 5.1 gets wrong passed there. A suite that starts its
    children through Invoke-P20TestHost runs them in the host it is running
    in: pwsh under pwsh, powershell.exe under powershell.exe.

        . (Join-Path $PSScriptRoot 'Get-TestHost.ps1')
        $out = Invoke-P20TestHost -Command $cmd -NonInteractive
        $out = Invoke-P20TestHost -File $script -Arguments @('-Sandbox', $box)

    -Command goes as -EncodedCommand: Windows PowerShell 5.1 drops a bare
    double quote from a native command's arguments, and a command holding one
    would reach the child altered. UTF-16 base64 also carries any character,
    so a non-ASCII test value arrives as itself. Output is stdout and stderr
    together, as `2>&1` gave it, and $LASTEXITCODE is the child's.

.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>

function Get-P20TestHost {
    <# The running host's own executable: pwsh, or powershell.exe on 5.1. #>
    $exe = ''
    try { $exe = [string](Get-Process -Id $PID).Path } catch { $exe = '' }
    if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return (Join-Path $PSHOME 'powershell.exe') }
    $found = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    return 'pwsh'
}

function Invoke-P20TestHost {
    param(
        [string]$Command,
        [string]$File,
        [string[]]$Arguments = @(),
        [switch]$NonInteractive
    )
    # Continue for the one native call: under 5.1, a redirected stderr line with
    # 'Stop' in force throws before the exit code can be read.
    $ErrorActionPreference = 'Continue'
    $exe = Get-P20TestHost
    $hostArgs = @('-NoProfile')
    if ($NonInteractive) { $hostArgs += '-NonInteractive' }
    if ($File) {
        $hostArgs += @('-File', $File) + @($Arguments)
    }
    else {
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
        # Windows takes a command line of 32767 characters; past that the child
        # never starts, so say so rather than fail somewhere stranger.
        if ($encoded.Length -gt 30000) { throw "Invoke-P20TestHost: the command is $($Command.Length) characters, too long for -EncodedCommand; pass a -File." }
        $hostArgs += @('-EncodedCommand', $encoded)
    }
    & $exe @hostArgs 2>&1
}
