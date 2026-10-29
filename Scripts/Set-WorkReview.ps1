<#
.SYNOPSIS
    Put a work review away: -Archive moves its folder under reviews/archive/,
    -Delete removes it.
.DESCRIPTION
    A review is a FOLDER, reviews/<slug-set>/<year>/<start>_<end>/, written by
    NewWorkReview (review.md) and, after the prose pass, holding summary.md too.
    It is named here the way a person reads it: <slug-set>/<start>_<end> -- the
    Spaces joined with '+', then the range. The year folder is found, not typed.

    -Archive moves the whole folder to reviews/archive/<slug-set>/<year>/<range>/
    and stamps **Closed:** into review.md, the file consts.json's
    reviews.fileName names: the one every review has from the moment it is
    generated, and the one every reader identifies a review by. summary.md is
    optional and is moved untouched. The stamp comes from the one shared writer,
    Scripts/Add-ClosedStamp.ps1 (whose bytes are Write-CardText's). The module
    closes its own data -- Archive is org-scoped and cannot see reviews/.

    -Delete removes the folder and everything in it. An archived review is named
    with archive/ in front: archive/<slug-set>/<range>.

    With storeSync: git the change is staged and committed, scoped to the
    review's own paths, the way Archive commits a card; Sync pushes it. -WhatIf
    names the folder and writes nothing.

    NewWorkReview and PublishWorkReview are untouched by this: it neither
    generates nor edits a review.
.EXAMPLE
    {cliPrefix}WorkReview first/<yyyy-mm-dd>_<yyyy-mm-dd> -Archive
.EXAMPLE
    {cliPrefix}WorkReview first+second/<yyyy-mm-dd>_<yyyy-mm-dd> -Delete -WhatIf
.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Review,
    [switch]$Archive,
    [switch]$Delete,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)WorkReview - archive or delete a work review" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)WorkReview <slug-set>/<start>_<end> -Archive   move it to reviews/archive/, stamped closed"
    Write-Host "    $($p)WorkReview <slug-set>/<start>_<end> -Delete    remove the folder"
    Write-Host "    ... -WhatIf                                       name the folder, write nothing"
    Write-Host ""
    exit 0
}

$p = Get-CliPrefix
$usageHint = "$($p)WorkReview <slug-set>/<start>_<end> -Archive | -Delete [-WhatIf]"

if ($Archive -and $Delete) {
    Write-CliError -Message 'choose one move: -Archive or -Delete, not both.' -Hint $usageHint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not $Archive -and -not $Delete) {
    Write-CliError -Message 'say what to do with the review: -Archive or -Delete.' -Hint $usageHint
    exit 2
}

# -- The review's name: [archive/]<slug-set>/<start>_<end> ----------------------
$consts = Get-P20Consts
$archiveName = [string]$consts.folders.archive
$reviewFile = [string]$consts.reviews.fileName
$closedStamp = [string]$consts.stamps.closed

$name = ([string]$Review).Trim() -replace '\\', '/'
$inArchive = $false
if ($name.StartsWith("$archiveName/")) {
    $inArchive = $true
    $name = $name.Substring($archiveName.Length + 1)
}
$parts = @($name.Trim('/') -split '/')
$rangeOk = ($parts.Count -eq 2) -and ($parts[1] -match '^\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}$')
$slugs = @()
if ($parts.Count -ge 1) { $slugs = @($parts[0] -split '\+' | Where-Object { $_ }) }
$slugsOk = ($slugs.Count -gt 0) -and (@($slugs | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' }).Count -eq 0)
if (-not $rangeOk -or -not $slugsOk) {
    $shown = if ($Review) { "'$Review'" } else { 'nothing' }
    Write-CliError -Message "$shown does not name a review -- a review is <slug-set>/<start>_<end>, the Spaces joined with '+'." -Hint "$($p)WorkReview first+second/2026-01-01_2026-03-31 -Archive"
    exit 2
}
# The slug-set is a SET: sorted, the way NewWorkReview writes the folder.
$slugSet = (@($slugs | Sort-Object) -join '+')
$range = $parts[1]
$label = "$slugSet/$range"

# -- Resolve the hub and the folder --------------------------------------------
$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not $promptsRoot -or -not (Test-Path -LiteralPath $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2
}
$reviewsRoot = Get-P20HubFolder -Name 'reviews' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
$reviewsName = Split-Path -Leaf $reviewsRoot
$activeBase = Join-Path $reviewsRoot $slugSet
$archiveBase = Join-Path (Join-Path $reviewsRoot $archiveName) $slugSet

function Find-P20ReviewFolder {
    # <base>/<year>/<range>, any year: the year is the generator's to choose,
    # and a person names the review by what it covers.
    param([string]$Base)
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Base -Directory | Where-Object { $_.Name -match '^\d{4}$' } | ForEach-Object {
            $candidate = Join-Path $_.FullName $range
            if (Test-Path -LiteralPath (Join-Path $candidate $reviewFile) -PathType Leaf) { $candidate }
        })
}

$where = if ($inArchive) { $archiveBase } else { $activeBase }
$hits = @(Find-P20ReviewFolder -Base $where)
if ($hits.Count -eq 0) {
    if ($Archive -and -not $inArchive -and @(Find-P20ReviewFolder -Base $archiveBase).Count -gt 0) {
        Write-Host "Already archived: $reviewsName/$archiveName/$label" -ForegroundColor Yellow
        exit 0
    }
    $hint = "The review's row in the web UI names it, or list $reviewsName/$slugSet/ in the hub."
    if (-not $inArchive -and @(Find-P20ReviewFolder -Base $archiveBase).Count -gt 0) {
        $hint = "It is archived -- name it $archiveName/$label."
    }
    $shownWhere = if ($inArchive) { "$reviewsName/$archiveName/" } else { "$reviewsName/" }
    Write-CliError -Message "no review $label under $shownWhere" -Hint $hint
    exit 2
}
if ($hits.Count -gt 1) {
    Write-CliError -Message "$label is in more than one year folder: $(($hits | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) }) -join ', ')." -Hint 'Move or remove one of them by hand, then run this again.'
    exit 2
}
if ($Archive -and $inArchive) {
    Write-Host "Already archived: $reviewsName/$archiveName/$label" -ForegroundColor Yellow
    exit 0
}

$source = $hits[0]
$year = Split-Path -Leaf (Split-Path -Parent $source)
$rootNorm = $promptsRoot.TrimEnd('\', '/')
function ConvertTo-P20HubRel {
    param([string]$Path)
    return ($Path.Substring($rootNorm.Length).TrimStart('\', '/') -replace '\\', '/')
}
$sourceRel = ConvertTo-P20HubRel $source
$dest = Join-Path (Join-Path $archiveBase $year) $range
$destRel = ConvertTo-P20HubRel $dest

if ($Archive -and (Test-Path -LiteralPath $dest)) {
    Write-CliError -Message "an archived review of $label is already at $destRel -- nothing in the archive is overwritten." -Hint "Delete one of the two first: $($p)WorkReview $archiveName/$label -Delete, or $($p)WorkReview $label -Delete."
    exit 2
}

# -- -WhatIf: name the folder, write nothing ----------------------------------
if ($WhatIf) {
    if ($Archive) {
        Write-Host "What if: move $sourceRel/ to $destRel/ and stamp $closedStamp into $destRel/$reviewFile. Nothing written." -ForegroundColor Cyan
    }
    else {
        $files = @(Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object { $_.Name })
        Write-Host "What if: remove $sourceRel/ and the $($files.Count) file(s) in it ($($files -join ', ')). Nothing written." -ForegroundColor Cyan
    }
    exit 0
}

# -- Was any of it ever committed? Asked before the move, while the path exists.
$storeSync = 'none'
if ($global:P20Config -and $global:P20Config.StoreSync) { $storeSync = [string]$global:P20Config.StoreSync }
$sourceTracked = $false
if ($storeSync -eq 'git') {
    Push-Location $promptsRoot
    try {
        $listed = Invoke-P20TrackerRead 'git' @('ls-files', '--', $sourceRel)
        $sourceTracked = ($listed.Code -eq 0) -and (@($listed.Lines | Where-Object { $_ }).Count -gt 0)
    }
    finally { Pop-Location }
}

# -- The move ------------------------------------------------------------------
if ($Archive) {
    $destParent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
    Move-Item -LiteralPath $source -Destination $dest -ErrorAction Stop
    # review.md carries the stamp: the file every review has and every reader keys on.
    Add-ClosedDate -Path (Join-Path $dest $reviewFile)
    Write-Host "Archived: $sourceRel/ -> $destRel/ ($closedStamp in $reviewFile)" -ForegroundColor Green
    $paths = @($destRel)
    if ($sourceTracked) { $paths += $sourceRel }
    $commitMsg = "review: archive $label"
}
else {
    Remove-Item -LiteralPath $source -Recurse -Force -ErrorAction Stop
    Write-Host "Deleted: $sourceRel/" -ForegroundColor Green
    $paths = @()
    if ($sourceTracked) { $paths += $sourceRel }
    $commitMsg = "review: delete $(if ($inArchive) { "$archiveName/" })$label"
}

# -- storeSync: stage and commit the review's own paths, nothing else ----------
if ($storeSync -ne 'git') {
    Write-Host "Store is not git (storeSync='$storeSync') -- nothing committed." -ForegroundColor DarkGray
    exit 0
}
if ($paths.Count -eq 0) {
    Write-Host 'It was never committed -- nothing to commit.' -ForegroundColor DarkGray
    exit 0
}
$gitFailure = $null
Push-Location $promptsRoot
try {
    $add = Invoke-P20TrackerRead 'git' (@('add', '-A', '--') + $paths)
    if ($add.Code -ne 0) {
        $gitFailure = "git add failed: $(@($add.Lines | Where-Object { $_ })[0])"
    }
    else {
        $staged = Invoke-P20TrackerRead 'git' (@('diff', '--cached', '--quiet', '--') + $paths)
        if ($staged.Code -eq 0) {
            Write-Host 'Nothing to commit.' -ForegroundColor DarkGray
        }
        else {
            # The pathspec keeps the commit to this review: anything else a person
            # had staged stays staged, and out of it.
            $commit = Invoke-P20TrackerRead 'git' (@('commit', '-m', $commitMsg, '--') + $paths)
            foreach ($line in $commit.Lines) { Write-Host $line }
            if ($commit.Code -ne 0) {
                $gitFailure = "git commit failed: $(@($commit.Lines | Where-Object { $_ })[0])"
            }
            else {
                Write-Host "Committed: $commitMsg. $($p)Sync pushes it." -ForegroundColor Green
            }
        }
    }
}
finally { Pop-Location }

if ($gitFailure) {
    $done = if ($Archive) { "moved to $destRel/" } else { 'removed' }
    Write-CliError -Message "the review was $done, but it is not committed -- $gitFailure" `
        -Hint "Commit it yourself (git add -A; git commit) or run '$($p)Sync'."
    exit 2
}
exit 0
