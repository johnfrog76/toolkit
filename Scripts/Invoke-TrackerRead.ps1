#
# The one way a script calls gh or az. NOT a runnable verb: DOT-SOURCED, by
# the scripts that read the tracker (New-Space.ps1, Connect-Space.ps1,
# Test-TrackerSignIn.ps1) and by a test, the way Get-Consts.ps1 is.
#
#     . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
#     $r = Invoke-P20TrackerRead 'gh' @('repo', 'view', $repo, '--json', 'visibility')
#     if ($r.Code -ne 0) { ... $r.Lines[0] ... }
#
# Why it exists: under Windows PowerShell 5.1 a native command whose stderr is
# redirected (2>&1 or 2>$null) while $ErrorActionPreference is 'Stop' makes each
# stderr line an error record and the first one THROWS, before the exit code can
# be read. pwsh 7 reads the same call as text. So the preference is 'Continue'
# for the one native call (it is function-local and ends with the function), and
# stderr is kept as text on both hosts.
#
# Returns @{ Code; Lines; Out; Err }: Lines is stdout and stderr in the order they
# came, as strings; Out is stdout alone (what to parse as JSON, so a warning on
# stderr cannot corrupt it); Err is stderr alone. $LASTEXITCODE is left at Code.
# A tool that is not found is Code 127, one that cannot be started (a command line
# past what Windows takes, say) Code 126, each with its sentence in Lines and Err.
# PowerShell 5.1 clean; reads no module state.
#
# On Windows a tool can be a .cmd (az is), and then cmd.exe parses the command
# line. PowerShell quotes an argument holding a space and nothing else, so an
# argument with no space reaches cmd.exe bare. Test-P20CmdArgument is the rule, and
# a read it refuses never starts: Code 2, with the sentence in Lines and Err. Quoting
# stops & and | but not %, so a variable's shape is refused with or without a space.
# cmd.exe's own names start with = (%=ExitCode%). Past that, a % that starts a
# percent-encoded byte (%2F) passes, because a URL path carries them: gh's branch
# path does, and gh can be a .cmd shim. Two such bytes with a letter first (%C3%A9) have a variable's shape and are refused, on a rare path.
#
function Test-P20CmdArgument {
    param([AllowEmptyString()][string]$Argument)
    if ($Argument -match '["\r\n]') { return $false }
    if ($Argument -match '%[A-Za-z_=][^%]*%') { return $false }
    if ($Argument -match '\s') { return $true }
    return ($Argument -notmatch '[&|<>^]|%(?![0-9A-Fa-f]{2})')
}

function Invoke-P20TrackerRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Tool,
        [Parameter(Position = 1)][string[]]$Arguments = @()
    )
    $ErrorActionPreference = 'Continue'
    $resolved = Get-Command $Tool -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved -and "$($resolved.Source)" -match '\.(cmd|bat)$') {
        foreach ($argument in $Arguments) {
            if (Test-P20CmdArgument $argument) { continue }
            $said = "$Tool was not run: the argument '$argument' holds a character cmd.exe would read."
            $global:LASTEXITCODE = 2
            return [PSCustomObject]@{ Code = 2; Lines = @($said); Out = @(); Err = @($said) }
        }
    }
    # A tool that is not there, or that will not start, is a failure with its own
    # code, never the 0 set just below: a write that never ran must not read as
    # done. 127 and 126 are the shell's own numbers for the two.
    if (-not $resolved) {
        $said = "$Tool is not installed, or not on the PATH, so it was not run."
        $global:LASTEXITCODE = 127
        return [PSCustomObject]@{ Code = 127; Lines = @($said); Out = @(); Err = @($said) }
    }
    # gh and git write UTF-8 to a pipe, and PowerShell decodes a native
    # command's output with [Console]::OutputEncoding -- on Windows the console's
    # OEM code page unless something changed it, so a comment's em dash came back
    # as three other characters, in a terminal and not from the web, whose bridge
    # sets it. UTF-8 for this one call, put back after. az is Python, which
    # encodes a pipe in the locale's code page unless PYTHONIOENCODING says
    # otherwise, so it is told too. Setting the console's encoding can throw where
    # there is no console; then nothing was changed and nothing is put back.
    $savedOutput = $null
    try { $savedOutput = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { $savedOutput = $null }
    $isAz = ([System.IO.Path]::GetFileNameWithoutExtension($Tool) -eq 'az')
    $savedPython = [System.Environment]::GetEnvironmentVariable('PYTHONIOENCODING')
    if ($isAz) { [System.Environment]::SetEnvironmentVariable('PYTHONIOENCODING', 'utf-8') }
    $global:LASTEXITCODE = 0
    try {
        $raw = @(& $Tool @Arguments 2>&1)
    }
    catch {
        $said = "$Tool could not be started: $($_.Exception.Message)"
        $global:LASTEXITCODE = 126
        return [PSCustomObject]@{ Code = 126; Lines = @($said); Out = @(); Err = @($said) }
    }
    finally {
        if ($null -ne $savedOutput) { try { [Console]::OutputEncoding = $savedOutput } catch { $null = $_ } }
        if ($isAz) { [System.Environment]::SetEnvironmentVariable('PYTHONIOENCODING', $savedPython) }
    }
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

#
# A gh api WRITE whose body is JSON: the body travels in a file (--input), never
# in argv. Windows PowerShell 5.1 drops a bare double quote from a native
# command's arguments, so a reply or a review comment that quotes code would
# reach GitHub altered if it went as -f body=<text>; a file carries any text
# byte for byte, on both hosts. The path is still a plain repos/... path with
# no query in it. Returns Invoke-P20TrackerRead's @{ Code; Lines; Out; Err }.
#
function Invoke-P20GhApiWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Path,
        [Parameter(Mandatory = $true, Position = 1)]$Body,
        [string]$Method = 'POST'
    )
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ('p20-gh-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $json = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
        [System.IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding($false)))
        return (Invoke-P20TrackerRead 'gh' @('api', '--method', $Method, $Path, '--input', $file))
    }
    finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}
