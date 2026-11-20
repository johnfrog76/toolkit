#
# How an argument has to be handed to a host that builds a native command's
# command line itself, and a folder path with its trailing separator off. NOT a
# runnable verb: DOT-SOURCED, by Invoke-TrackerRead.ps1 (the one way a script
# calls gh, az or git), by Tests/Get-TestHost.ps1 (the one way a suite calls
# git) and by the scripts that read a folder path from configuration.
#
#     . (Join-Path $PSScriptRoot 'ConvertTo-NativeArgument.ps1')
#     if (Test-P20LegacyNativeArguments) {
#         $arguments = @($arguments | ForEach-Object { ConvertTo-P20NativeArgument $_ })
#     }
#     & git @arguments
#
# Why it exists: Windows PowerShell 5.1, PowerShell 7.0 to 7.2, and a later one
# whose $PSNativeCommandArgumentPassing is Legacy, join the arguments into one
# line and the tool's C runtime splits it again. The host wraps an argument
# holding whitespace in double quotes and does nothing else, so three values do
# not arrive as written:
#
#   ''              vanishes, and the argument after it takes its place
#   say "hi"        loses its double quotes
#   C:\My Repos\r\  on 5.1 goes out as "C:\My Repos\r\" -- the C runtime reads
#                   \" as a quote, and the value swallows every argument after
#                   it. `git -C <that> rev-parse --show-toplevel` then asks
#                   about a folder named  C:\My Repos\r" rev-parse --show-toplevel
#
# ConvertTo-P20NativeArgument is the ONE rule for all three, and nothing else
# escapes an argument: Invoke-P20TrackerRead and Invoke-P20TestGit both call it,
# behind Test-P20LegacyNativeArguments, and Test-Portability holds each to the
# same table of shapes. A host that passes arguments as an array (PowerShell 7.3
# and later, by default) needs none of it and is handed every value untouched.
#
# Remove-P20TrailingSeparator is the other half: a folder path read from
# configuration (spaceCheckouts.<slug>.path, the hub root) has its trailing
# separator taken off where it is read, so the value is clean before any call.
# The escaping is the fix; this is the second fastening, because a path reaches
# a native call from more places than configuration.
#
# PowerShell 5.1 clean (ASCII only); reads no module state.
#

function Test-P20LegacyNativeArguments {
    <# True where the host joins a native command's arguments into one line
       itself: Windows PowerShell 5.1, PowerShell 7.0 to 7.2, and a later one
       whose $PSNativeCommandArgumentPassing is Legacy. #>
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
    $mode = Get-Variable -Name PSNativeCommandArgumentPassing -ValueOnly -ErrorAction SilentlyContinue
    return ((-not $mode) -or ([string]$mode -eq 'Legacy'))
}

function ConvertTo-P20NativeArgument {
    <# One argument, as a legacy host has to be handed it for the tool to read
       the value back. The host wraps an argument holding whitespace in double
       quotes; it does nothing for an empty argument or for a double quote
       inside one. So an empty one goes as "" and each double quote as \",
       with the backslashes before it doubled, which is how the C runtime
       reads a command line.

       The trailing backslashes of a value it wraps are where the hosts part.
       PowerShell 7's Legacy mode doubles them itself; Windows PowerShell 5.1
       does not, so `my dir\` goes out as "my dir\" and the C runtime reads
       \" as a quote, swallowing the next argument. On 5.1 this doubles them;
       on 7 it leaves them, or they would be doubled twice. A value with no
       whitespace is not wrapped, so its trailing backslash is left alone on
       both. -Desktop is for a test, which states the edition it is asking
       about; a caller never passes it. #>
    param(
        [AllowEmptyString()][string]$Value,
        [bool]$Desktop = ($PSVersionTable.PSEdition -eq 'Desktop')
    )
    if ($Value.Length -eq 0) { return '""' }
    if ($Value.IndexOf('"') -ge 0) {
        $Value = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    }
    if ($Desktop -and $Value -match '\s') {
        $Value = [regex]::Replace($Value, '(\\+)$', '$1$1')
    }
    return $Value
}

function Remove-P20TrailingSeparator {
    <# A folder path without the directory separators at its end. A root is
       left as it is: a path that is nothing but separators (/, \, \\), and a
       drive root, which keeps one separator (C:\ stays C:\, because C: alone
       is the drive's CURRENT folder, a different place). Anything else loses
       them all: C:\My Repos\r\ is C:\My Repos\r.

       The separators are the running platform's: \ and / on Windows, / alone
       elsewhere, where a backslash is a character a folder's name may hold.
       -Separators is for a test, which names the platform it is asking about. #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [char[]]$Separators = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    )
    $p = "$Path"
    $trimmed = $p.TrimEnd($Separators)
    if ($trimmed.Length -eq $p.Length) { return $p }
    if ($trimmed.Length -eq 0) { return $p }
    if ($trimmed -match '^[A-Za-z]:$') { return $trimmed + $p.Substring(2, 1) }
    return $trimmed
}
