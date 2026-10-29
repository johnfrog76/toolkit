#
# How far the hub is from its remote: commits ahead, commits behind. The read
# behind the System page's store-sync row and the foot line on the cards that
# write into the hub (docs/CONFIGURATION.md, "Syncing the hub from the web app").
#
# NOT a runnable verb: the agent starts it (agent/core/hub_sync.py), with
#
#     <pwsh|powershell> -NoProfile -File Get-HubSyncState.ps1 -HubRoot <path> [-Fetch]
#
# and reads the one JSON line it prints. It imports no module and reads no
# config: the agent has already resolved the hub and whether storeSync is git.
#
# Two reads, and only one of them touches the network:
#
#   ahead   LOCAL. `git rev-list --left-right --count HEAD...@{upstream}` counts
#           what this clone has that its remote-tracking branch does not. No
#           network, so it is cheap enough to answer every /env.
#   behind  needs `git fetch` first -- without one, the remote-tracking branch is
#           whatever the LAST fetch left, and a count read from it is a guess.
#           So -Fetch fetches, and only then is `behind` reported; without
#           -Fetch the field is null rather than stale.
#
# Every git call goes through Invoke-P20TrackerRead (AGENTS.md, "Traps worth
# knowing": a raw git call with a redirected stderr throws under Windows
# PowerShell 5.1 before its exit code can be read). Test-Portability's Clause 15
# holds this file to that.
#
# Prints: {"ahead":n|null,"behind":n|null,"fetched":bool,"fetchError":s|null,"error":s|null}
#   error       the local read failed: not a git root, no upstream branch. ahead
#               and behind are null.
#   fetchError  -Fetch was asked and the fetch failed (the remote is unreachable,
#               the credentials were refused): git's own first line. ahead is
#               still read; behind is null, because the last known count is the
#               agent's to keep, not this script's to guess.
# Always exits 0 with that line: the agent reads the fields, not the code.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HubRoot,
    [switch]$Fetch
)

$ErrorActionPreference = 'Stop'

# Test-GitRoot.ps1 dot-sources Invoke-TrackerRead.ps1 itself; it is named here
# too so the one way this file calls git is visible where it is used.
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Test-GitRoot.ps1')

$result = [ordered]@{
    ahead      = $null
    behind     = $null
    fetched    = $false
    fetchError = $null
    error      = $null
}

function Get-FirstLine {
    # git's own first line, else a sentence naming the step and the code.
    param($Read, [string]$Step)
    $line = @($Read.Err + $Read.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -First 1)
    if ($line.Count -gt 0) { return ("$($line[0])").Trim() }
    return "git $Step failed (exit code $($Read.Code))"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $result.error = 'git is not on the PATH, so the hub cannot be compared with its remote.'
}
elseif (-not (Test-P20GitRoot -Path $HubRoot)) {
    # The same question Sync asks before it writes: the hub must BE the root.
    $result.error = "The hub at '$HubRoot' is not the root of a git repository."
}
else {
    if ($Fetch) {
        $fetchRead = Invoke-P20TrackerRead 'git' @('-C', $HubRoot, 'fetch', '--quiet')
        if ($fetchRead.Code -eq 0) {
            $result.fetched = $true
        }
        else {
            $result.fetchError = Get-FirstLine $fetchRead 'fetch'
        }
    }

    $count = Invoke-P20TrackerRead 'git' @('-C', $HubRoot, 'rev-list', '--left-right', '--count', 'HEAD...@{upstream}')
    if ($count.Code -ne 0) {
        # No upstream branch is the common case: a hub that was `git init`-ed
        # and never pushed. git says so in its own words.
        $result.error = Get-FirstLine $count 'rev-list'
    }
    else {
        $parts = @((("$(@($count.Out)[0])").Trim()) -split '\s+')
        if ($parts.Count -eq 2) {
            $result.ahead = [int]$parts[0]
            if ($result.fetched) { $result.behind = [int]$parts[1] }
        }
        else {
            $result.error = "git rev-list answered '$(@($count.Out) -join ' ')', not two counts."
        }
    }
}

[Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
exit 0
