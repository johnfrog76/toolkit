<#
.SYNOPSIS
    The one way a commit bullet goes into a card's Git section. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    `- <hash> <subject>` under `Commits:` is the git token: the line
    Get-PromptStatus.ps1 and agent/core/parsers.py both read to call a card In
    Progress, through one pattern (consts.json `regex.commitBullet`). Two verbs
    write it -- ThreadHash, a branch's commits, and Land, the merge commit's
    `- <hash> #<n> squash-merged to <base> <yyyy-MM-dd>` -- and both put it in
    the same place by this one rule, so the two cannot disagree about where a
    commit goes or what counts as one already there.

    Works on TEXT, not on a file: the caller reads the card, decides what else
    it changes, and writes it through Write-CardText (AGENTS.md, "One byte
    contract for a card"). Content goes in and comes out LF; the caller puts the
    file's own terminator back.

    PowerShell 5.1 compatible (ASCII dashes only). Reads no module state.
#>

. (Join-Path $PSScriptRoot 'Get-Consts.ps1')

function Get-P20BulletHash {
    <#
        The hash out of a bullet the CONTRACT pattern matched, lowercased, '' for
        a line that is not one. Matching and extracting are one step so no second
        copy of the shape can exist.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Line)
    $m = [regex]::Match("$Line", (Get-P20Consts).regex.commitBullet)
    if (-not $m.Success) { return '' }
    return (($m.Value -replace '^\s*-\s+', '') -replace '`', '').Trim().ToLower()
}

function Test-P20HashSeen {
    <#
        Whether $Hash is one of $Known, either way round by prefix: a card that
        carries `c84c6e3` already carries `c84c6e3f00d`, and the reverse.
    #>
    param([string]$Hash, [string[]]$Known)
    if (-not $Hash) { return $false }
    foreach ($k in @($Known)) {
        if (-not $k) { continue }
        if ($k.StartsWith($Hash) -or $Hash.StartsWith($k)) { return $true }
    }
    return $false
}

function Get-P20CardBulletHashes {
    <#
        Every commit-bullet hash anywhere in a card -- the whole file, as the state
        rule reads it, not only the Git section. A hand-written landed bullet sits
        at the card's foot as often as under Commits:, and both count.
    #>
    param([AllowEmptyString()][string]$Content)
    $found = @()
    foreach ($line in ("$Content" -replace "`r`n", "`n") -split "`n") {
        $h = Get-P20BulletHash $line
        if ($h) { $found += $h }
    }
    return $found
}

function Add-P20CommitBullets {
    <#
        Insert $Bullets into the Git section of $Content (LF): after the last
        commit bullet under `Commits:`, else straight after `Commits:`, else at
        the end of the section. A bullet whose hash the section already carries
        is skipped, and the `- (pending)` placeholder goes once a real commit is
        written.

        Returns @{ Ok; Content; Added; Reason }: Ok is $false only when the card
        has no `## Git` section, and then Content is unchanged. Added is the
        bullets actually inserted, in order.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Bullets
    )
    $lines = [System.Collections.Generic.List[string]]($Content -split "`n")

    # The Git section: `## Git` to the next `## ` heading, or end of file.
    $gitStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+Git\s*$') { $gitStart = $i; break }
    }
    if ($gitStart -lt 0) {
        return @{ Ok = $false; Content = $Content; Added = @(); Reason = 'no-git-section' }
    }
    $gitEnd = $lines.Count
    for ($i = $gitStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+') { $gitEnd = $i; break }
    }

    # Hashes the section already carries -- the whole point of re-running being safe.
    $existing = @()
    for ($i = $gitStart; $i -lt $gitEnd; $i++) {
        $h = Get-P20BulletHash $lines[$i]
        if ($h) { $existing += $h }
    }

    $toAdd = @()
    foreach ($line in @($Bullets)) {
        $h = Get-P20BulletHash $line
        if (-not (Test-P20HashSeen -Hash $h -Known $existing)) {
            $toAdd += $line
            if ($h) { $existing += $h }
        }
    }

    if ($toAdd.Count -gt 0) {
        $insertAt = -1
        for ($i = $gitStart; $i -lt $gitEnd; $i++) {
            if ($lines[$i] -match '^Commits:') { $insertAt = $i + 1; break }
        }
        if ($insertAt -lt 0) { $insertAt = $gitEnd }
        for ($i = $insertAt; $i -lt $gitEnd; $i++) {
            if (Get-P20BulletHash $lines[$i]) { $insertAt = $i + 1 }
            elseif ($lines[$i].Trim() -ne '') { break }
        }
        $lines.InsertRange($insertAt, [string[]]$toAdd)
        $gitEnd += $toAdd.Count

        # The placeholder has done its job the moment a real commit is recorded.
        for ($i = $gitEnd - 1; $i -ge $gitStart; $i--) {
            if ($lines[$i] -match '^\s*-\s+\(pending\)\s*$') { $lines.RemoveAt($i) }
        }
    }

    return @{ Ok = $true; Content = ($lines -join "`n"); Added = @($toAdd); Reason = '' }
}
