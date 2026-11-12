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

    Invoke-P20TestGit is the one way a suite calls git, to build a fixture
    repository or read one back. Under Windows PowerShell 5.1 a native
    command's redirected stderr, with 'Stop' in force, throws on its first
    line, and on Windows git warns on stderr about line endings. So a suite
    that wrote `git add -A 2>&1 | Out-Null` stopped there on 5.1 and passed
    on 7. The helper runs git with 'Continue' for the one call and returns
    what it said as text:

        $r = Invoke-P20TestGit -C $repo status --porcelain
        if ($r.Code -ne 0) { ... $r.Lines ... }
        $null = Invoke-P20TestGit -C $repo add -A

    It returns @{ Code; Lines; Out; Err }, the shape Invoke-P20TrackerRead
    gives a script: Lines is stdout and stderr in the order they came, Out
    stdout alone (what `2>$null` kept), Err stderr alone. $LASTEXITCODE is
    left at Code. There is no gate on the arguments: a fixture is not a
    user's input.

    Each argument reaches git as one value, with two things to know.

    PowerShell reads a function's arguments before the function sees them,
    so a bare word is not always one argument. Quote these, and each arrives
    as written:

        '--'            bare, the first one ends the parameters and is dropped
        '-c:x'          bare, it arrives as  -c:  and  x
        '-a.b'          bare, it arrives as  -a   and  .b
        '--format=%h,%s'  bare, the comma splits it in two
        'stash@{0}'     bare, it arrives as  stash@  and  0

        $null = Invoke-P20TestGit -C $repo checkout -q '--' $path

    Clause 23 of Test-Portability.ps1 reads every call under Tests/ and
    fails on one of these written bare.

    Windows PowerShell 5.1, and PowerShell 7 with
    $PSNativeCommandArgumentPassing set to Legacy, build a native command
    line by joining the arguments: an empty one vanishes and a double quote
    inside one is not escaped. The helper escapes for that host
    (ConvertTo-P20TestGitArgument), so '' and 'say "hi"' arrive as
    themselves there too.

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

function Test-P20TestLegacyNativeArguments {
    <# True where the host joins a native command's arguments into one line
       itself: Windows PowerShell 5.1, PowerShell 7.0 to 7.2, and a later one
       whose $PSNativeCommandArgumentPassing is Legacy. #>
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
    $mode = Get-Variable -Name PSNativeCommandArgumentPassing -ValueOnly -ErrorAction SilentlyContinue
    return ((-not $mode) -or ([string]$mode -eq 'Legacy'))
}

function ConvertTo-P20TestGitArgument {
    <# One argument, as a legacy host has to be handed it for git to read the
       value back. The host wraps an argument holding whitespace in double
       quotes; it does nothing for an empty argument or for a double quote
       inside one. So an empty one goes as "" and each double quote as \",
       with the backslashes before it doubled, which is how the C runtime
       reads a command line.

       The trailing backslashes of a value it wraps are where the hosts part.
       PowerShell 7's Legacy mode doubles them itself; Windows PowerShell 5.1
       does not, so `my dir\` goes out as "my dir\" and the C runtime reads
       \" as a quote, swallowing the next argument. On 5.1 the helper doubles
       them; on 7 it leaves them, or they would be doubled twice. #>
    param([AllowEmptyString()][string]$Value)
    if ($Value.Length -eq 0) { return '""' }
    if ($Value.IndexOf('"') -ge 0) {
        $Value = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    }
    if ($PSVersionTable.PSEdition -eq 'Desktop' -and $Value -match '\s') {
        $Value = [regex]::Replace($Value, '(\\+)$', '$1$1')
    }
    return $Value
}

function Invoke-P20TestGit {
    # No param block: a dash-led argument (-C, -c, --quiet) reaches git rather
    # than binding here. The header says which bare words PowerShell splits
    # before this function sees them.
    $ErrorActionPreference = 'Continue'
    $gitArgs = @($args | ForEach-Object { $_ } | ForEach-Object { [string]$_ })
    if (Test-P20TestLegacyNativeArguments) {
        $gitArgs = @($gitArgs | ForEach-Object { ConvertTo-P20TestGitArgument $_ })
    }
    $global:LASTEXITCODE = 0
    $raw = @(& git @gitArgs 2>&1)
    $code = $LASTEXITCODE
    $out = @()
    $err = @()
    $lines = @()
    foreach ($item in $raw) {
        $text = [string]$item
        $lines += $text
        if ($item -is [System.Management.Automation.ErrorRecord]) { $err += $text } else { $out += $text }
    }
    $global:LASTEXITCODE = $code
    return [PSCustomObject]@{ Code = $code; Lines = $lines; Out = $out; Err = $err }
}
