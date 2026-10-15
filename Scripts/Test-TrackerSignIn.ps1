#
# Is the tracker's CLI here, and is it signed in? ONE rule for the connect
# wizard's second step (D-W13), in a
# file of its own like Test-AdoEnabled.ps1: the step is SAID and CHECKED, never
# performed -- this asks `az` or `gh`, and tells the person the exact command.
# Dot-sourced; PowerShell 5.1 clean. Every gh/az call goes through
# Invoke-P20TrackerRead, which this file loads itself.
#
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
function Test-P20TrackerSignIn {
    <#
      Returns @{ Tracker; Tool; Installed; SignedIn; Identity; Command } for
      'ado' or 'github'. 'none' answers Installed=$true, SignedIn=$true: a local
      board needs nothing.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Tracker)
    $r = @{ Tracker = $Tracker; Tool = ''; Installed = $false; SignedIn = $false; Identity = ''; Command = '' }
    if ($Tracker -eq 'none') { $r.Installed = $true; $r.SignedIn = $true; return $r }
    if ($Tracker -eq 'github') {
        $r.Tool = 'gh'; $r.Command = 'gh auth login'
        $r.Installed = [bool](Get-Command gh -ErrorAction SilentlyContinue)
        if (-not $r.Installed) { return $r }
        $status = Invoke-P20TrackerRead 'gh' @('auth', 'status')
        $r.SignedIn = ($status.Code -eq 0)
        if ($r.SignedIn) {
            $who = Invoke-P20TrackerRead 'gh' @('api', 'user', '-q', '.login')
            if ($who.Code -eq 0) { $r.Identity = ([string]($who.Out -join '')).Trim() }
        }
        return $r
    }
    $r.Tool = 'az'; $r.Command = 'az login'
    $r.Installed = [bool](Get-Command az -ErrorAction SilentlyContinue)
    if (-not $r.Installed) { return $r }
    $shown = Invoke-P20TrackerRead 'az' @('account', 'show', '--output', 'json')
    $acct = $shown.Out
    $r.SignedIn = ($shown.Code -eq 0 -and [bool]$acct)
    if ($r.SignedIn) {
        try { $parsed = ($acct | Out-String) | ConvertFrom-Json; if ($parsed.user -and $parsed.user.name) { $r.Identity = [string]$parsed.user.name } } catch { $null = $_ }
    }
    return $r
}
