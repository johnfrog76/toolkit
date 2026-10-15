<#
.SYNOPSIS
    The canonical tier DECISION (docs/CLI.md, "Tiers: what works without ADO").
.DESCRIPTION
    Pure function of its inputs - no I/O - so it can be parity-tested against the
    the tier contract. Get-Environment.ps1 calls this for the real decision; the
    parity test calls it with controlled inputs. Switch params are used because
    PowerShell's string→[bool] conversion is a footgun ([bool]'false' is $true).
    Outputs the tier (1, 2, or 3) to the pipeline.
.NOTES
    this is the sole implementation -- the package it was carved from had a second
    one in a service that is NOT part of Toolkit, so there is nothing to keep in sync here.
#>
param(
    [switch]$RepoFound,
    [switch]$GitInstalled,
    [switch]$AzAuthenticated,
    [switch]$AdoReachable,
    [string]$Status = ''
)

$tier = if (-not $RepoFound -or -not $GitInstalled) { 3 }
        elseif ($Status -eq 'local' -or $Status -eq 'archive') { 2 }   # config wins - declared offline / rolled off
        elseif (-not $AzAuthenticated) { 2 }
        elseif ($AdoReachable) { 1 }
        else { 2 }

$tier
