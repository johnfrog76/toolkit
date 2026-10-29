<#
.SYNOPSIS
    Where a Space's own repository is checked out on this machine, if anywhere.
.DESCRIPTION
    A Space's address names its repository (Resolve-P20TrackerRepo,
    Resolve-Tracker.ps1); this asks whether a clone of it is here. The
    candidates are the caller's -- MoveDesign passes the folder you stand in
    first, then the nav shortcuts' paths (aliases.<Name>.path, the toolkit's
    existing record of where things live on this machine, which the agent's
    stress-repos read uses for the same question). A candidate counts only when
    it is inside a git repository whose origin IS the Space's repository
    (Get-P20GitHubOriginRepo, the rule StartWork -Launch holds a clone to), so
    a folder that merely shares a name never answers.

    Returns a hashtable:
        Root    the clone's top level, or '' when none was found
        Repo    'owner/name' when the address names one, else ''
        Reason  why there is no Root, in words a refusal or a note can print

    A Space whose tracker is not GitHub, or whose address names no single
    repository, has no Root and says so; the caller decides what that means.
    Every git call goes through Invoke-P20TrackerRead (AGENTS.md, "Traps worth
    knowing"), which the caller dot-sources, with Resolve-Tracker.ps1.

    PowerShell 5.1 compatible (ASCII only); reads no module state.
#>

function Resolve-P20SpaceCheckout {
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        [string[]]$Candidates = @()
    )
    $result = @{ Root = ''; Repo = ''; Reason = '' }
    if ((Resolve-P20Tracker -OrgUrl $OrgUrl) -ne 'github') {
        $result.Reason = 'its address is not a GitHub repository, so there is no clone to look for'
        return $result
    }
    $target = Resolve-P20TrackerRepo -OrgUrl $OrgUrl -Projects $Projects
    if (-not $target.Repo) {
        $result.Reason = "its address names no single repository ($($target.Reason))"
        return $result
    }
    $result.Repo = [string]$target.Repo
    $seen = @{}
    foreach ($candidate in @($Candidates)) {
        $c = "$candidate".Trim()
        if (-not $c) { continue }
        if (-not (Test-Path -LiteralPath $c -PathType Container)) { continue }
        $topRead = Invoke-P20TrackerRead 'git' @('-C', $c, 'rev-parse', '--show-toplevel')
        if ($topRead.Code -ne 0) { continue }
        $top = ([string](@($topRead.Out | Where-Object { "$_".Trim() }) | Select-Object -First 1)).Trim()
        if (-not $top) { continue }
        $top = [System.IO.Path]::GetFullPath($top)
        if ($seen.ContainsKey($top)) { continue }
        $seen[$top] = $true
        $originRead = Invoke-P20TrackerRead 'git' @('-C', $top, 'remote', 'get-url', 'origin')
        if ($originRead.Code -ne 0) { continue }
        $originUrl = ([string](@($originRead.Out) | Select-Object -First 1)).Trim()
        if ((Get-P20GitHubOriginRepo -Url $originUrl) -ieq $result.Repo) {
            $result.Root = $top
            return $result
        }
    }
    $result.Reason = "no clone of $($result.Repo) was found on this machine (looked in the folder you stand in and the nav shortcuts' paths)"
    return $result
}
