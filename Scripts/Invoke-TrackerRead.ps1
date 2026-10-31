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
# PowerShell 5.1 clean; reads no module state.
#
function Invoke-P20TrackerRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Tool,
        [Parameter(Position = 1)][string[]]$Arguments = @()
    )
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    $raw = @(& $Tool @Arguments 2>&1)
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
