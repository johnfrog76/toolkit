<#
.SYNOPSIS
    Whether a GitHub repository is public -- the CLI's half of a Space's visibility mark.
.DESCRIPTION
    A write to a public repository is read by strangers, and GitHub keeps an
    edited issue's first wording. So every verb that writes to a GitHub Space's
    tracker prints ONE line before it writes -- -WhatIf (and NewItem's
    -ReadOnly) included -- when the repository it writes to is public:

        [!] This repository is public

    The line only; no confirmation is asked (the issue's own recommendation: a
    prompt is refused for a non-interactive caller, so it would need a switch).

    The words are consts.json `visibility`, which the agent's GET
    /api/visibility serves and the web draws: public, private (gh's INTERNAL
    too -- an enterprise repository is not read by strangers) or unknown, which
    is what a gh that did not answer gives. Never a guess: unknown prints no
    line, and Env and SwitchSpace Status say `unknown`.

    Asked of gh once per call (`gh api repos/<owner>/<name>`); nothing is
    cached, because a verb asks once. An Azure DevOps Space, or one with no
    tracker, has no visibility at all ('' from Get-P20SpaceVisibility), and gh
    is never asked there.

    Dot-sourced by the writing verbs (NewItem, EditItem, CloseItem, NewPR,
    Route) and by Env and SwitchSpace; it reads no module state.
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
}

function ConvertTo-P20Visibility {
    # gh's word -- PUBLIC | PRIVATE | INTERNAL, any case -- as the contract's.
    # Anything else, or nothing, is unknown.
    param([AllowEmptyString()][AllowNull()][string]$Raw)
    $v = (Get-P20Consts).visibility
    $s = "$Raw".Trim().ToLowerInvariant()
    if ($s -eq 'public') { return [string]$v.public }
    if ($s -eq 'private' -or $s -eq 'internal') { return [string]$v.private }
    return [string]$v.unknown
}

function Merge-P20Visibility {
    # One Space from its repositories': public when ANY is (a write may land
    # there), private when ALL are, unknown otherwise -- and for none.
    param([AllowEmptyCollection()][string[]]$Words = @())
    $v = (Get-P20Consts).visibility
    $w = @($Words | Where-Object { $_ })
    if ($w -contains [string]$v.public) { return [string]$v.public }
    if ($w.Count -gt 0 -and @($w | Where-Object { $_ -ne [string]$v.private }).Count -eq 0) { return [string]$v.private }
    return [string]$v.unknown
}

function Get-P20RepoVisibility {
    # One repository, 'owner/name', asked of gh. unknown when gh is missing,
    # refuses, or answers with something that is not a repository.
    param([AllowEmptyString()][AllowNull()][string]$Repo)
    if (-not $Repo -or -not (Get-Command gh -ErrorAction SilentlyContinue)) { return ConvertTo-P20Visibility '' }
    try {
        $raw = & gh api "repos/$Repo" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return ConvertTo-P20Visibility '' }
        $obj = (@($raw) -join "`n") | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return ConvertTo-P20Visibility '' }
    if ($null -eq $obj -or $obj -is [array] -or -not $obj.PSObject.Properties['visibility']) { return ConvertTo-P20Visibility '' }
    return ConvertTo-P20Visibility ([string]$obj.visibility)
}

function Get-P20SpaceVisibility {
    # A Space's visibility: '' when its tracker is not GitHub (no visibility,
    # gh never asked); with -NoAsk, unknown without asking (a Space that is not
    # connected -- the agent's below-Tier-1 answer); else its repositories',
    # merged.
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        [switch]$NoAsk
    )
    if ((Resolve-P20Tracker -OrgUrl $OrgUrl) -ne 'github') { return '' }
    if ($NoAsk) { return Merge-P20Visibility }
    $repos = @(Get-P20TrackerRepos -OrgUrl $OrgUrl -Projects $Projects)
    return Merge-P20Visibility -Words @($repos | ForEach-Object { Get-P20RepoVisibility -Repo $_ })
}

function Write-P20PublicLine {
    # Before a write: the one line, when the repository written to is public.
    # Nothing for private or unknown.
    param([AllowEmptyString()][AllowNull()][string]$Repo)
    $v = (Get-P20Consts).visibility
    if ((Get-P20RepoVisibility -Repo $Repo) -ne [string]$v.public) { return }
    Write-Host "[!] $($v.publicLine)" -ForegroundColor Yellow
}
