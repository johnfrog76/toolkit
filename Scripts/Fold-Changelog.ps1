<#
.SYNOPSIS
    The release step that folds every entry waiting in changelog.d/ into
    CHANGELOG.md's ## [Unreleased] section, and deletes the folded files.

.DESCRIPTION
    Not a verb -- no alias, no menu row, no bridge entry. A maintainer runs it
    once, by hand, at the start of a release pull request.

    Why the entries are files: every pull request that a user would notice used
    to add its line to the same list under ## [Unreleased], so two pull requests
    built side by side always conflicted on it, whatever their code did. One
    file per entry, named by the card or issue it belongs to, means two pull
    requests never touch the same file. changelog.d/README.md is the writer's
    half; AGENTS.md, "A release is a tag on main", is the release recipe this
    step opens.

    THE FRAGMENT, in one place:

      changelog.d/<id>.<kind>.md
        <id>    the card or issue: letters, digits, '-' and '_', starting with a
                letter or digit (MY6C, 214, TaskMY6C, 214-docs)
        <kind>  added | changed | removed | fixed -- the Keep a Changelog
                heading the entry goes under, in any case
        body    one or more entries exactly as they will read in the changelog:
                each line starts "- ", or is an indented continuation of the
                entry above it. No blank line inside, no heading.

      README.md is the folder's own page and is never an entry; a name that
      starts with '.' is a file the system made (.DS_Store) and is skipped.

    WHERE IT FOLDS: into ## [Unreleased], not into a version. The release recipe
    stays exactly as it was -- rename ## [Unreleased] to ## [x.y.z] - date, open
    a fresh one, bump the three version fields -- so .github/workflows/release.yml
    reads the version's section the way it always has, and the version number is
    chosen where it always was, after the fold, with every entry in view. An
    entry already written by hand under ## [Unreleased] stays where it is; a
    folded entry goes at the end of its heading's list, and a heading the section
    does not have yet is added in Keep a Changelog order (Added, Changed,
    Removed, Fixed). Within one heading the files fold in name order.

    EVERY FILE IS READ BEFORE ANYTHING IS WRITTEN. One fragment that is not the
    shape above refuses the whole fold, naming every such file, with nothing
    written and nothing deleted (exit 2, AGENTS.md "The refusal contract").

    The result is written through Write-CardText -New: UTF-8 with no BOM, LF.
    -New because the whole file is rewritten and it must come out the same bytes
    on every host, whatever line ending the checkout gave it.

.PARAMETER Root
    The folder that holds CHANGELOG.md and changelog.d/. Defaults to this
    package. Composition for the suite, which folds a scratch copy.

.PARAMETER Check
    Read every fragment and the changelog and say whether a fold would go
    through. Writes nothing. The suite runs it over the committed tree, so a
    fragment in the wrong shape fails the pull request that adds it, not the
    release.

.PARAMETER WhatIf
    Print the ## [Unreleased] section the fold would write, and the files it
    would delete. Writes and deletes nothing.

.EXAMPLE
    pwsh -NoProfile -File Scripts/Fold-Changelog.ps1 -Check
.EXAMPLE
    pwsh -NoProfile -File Scripts/Fold-Changelog.ps1 -WhatIf
.EXAMPLE
    pwsh -NoProfile -File Scripts/Fold-Changelog.ps1

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

$changelogPath = Join-Path $Root 'CHANGELOG.md'
$fragmentDir = Join-Path $Root 'changelog.d'
$recipe = 'changelog.d/README.md has the shape; AGENTS.md, "A release is a tag on main", has the release.'

# Keep a Changelog's order, restricted to the four headings this project uses.
$kindTitles = [ordered]@{ added = 'Added'; changed = 'Changed'; removed = 'Removed'; fixed = 'Fixed' }
$kindNames = @($kindTitles.Keys)

# -- Read every fragment, and every reason one cannot fold ----------------------
$fragments = @()
$problems = @()
if (Test-Path -LiteralPath $fragmentDir -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $fragmentDir -File -Force)
    $byName = @{}
    foreach ($f in $files) { $byName[$f.Name] = $f }
    # Name order, ordinal, so the fold is the same on every host and culture.
    $names = [string[]]@($files | ForEach-Object { $_.Name })
    [array]::Sort($names, [System.StringComparer]::Ordinal)

    foreach ($name in $names) {
        $f = $byName[$name]
        if ($name -ieq 'README.md') { continue }
        if ($name.StartsWith('.')) { continue }
        $shown = "changelog.d/$name"

        $m = [regex]::Match($name, '^([A-Za-z0-9][A-Za-z0-9_-]*)\.([A-Za-z]+)\.md$')
        if (-not $m.Success) {
            $problems += "$shown is not named <id>.<kind>.md"
            continue
        }
        $kind = $m.Groups[2].Value.ToLowerInvariant()
        if ($kindNames -notcontains $kind) {
            $problems += "$shown has the kind '$($m.Groups[2].Value)', which is not one of $($kindNames -join ', ')"
            continue
        }

        # ReadAllText takes a BOM off if an editor wrote one.
        $text = [System.IO.File]::ReadAllText($f.FullName, (New-Object System.Text.UTF8Encoding($false)))
        $text = ($text -replace "`r`n", "`n").Trim()
        if (-not $text) {
            $problems += "$shown is empty"
            continue
        }
        $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd() })
        $bad = $null
        if (-not $lines[0].StartsWith('- ')) { $bad = 'its first line is not an entry starting "- "' }
        else {
            foreach ($l in $lines) {
                if (-not $l) { $bad = 'it has a blank line inside'; break }
                if ($l -match '^#') { $bad = 'it has a heading in it'; break }
                if (-not ($l.StartsWith('- ') -or $l -match '^\s+\S')) { $bad = "a line is neither an entry starting ""- "" nor an indented continuation: '$l'"; break }
            }
        }
        if ($bad) {
            $problems += "$shown cannot fold: $bad"
            continue
        }
        $fragments += [pscustomobject]@{ Name = $name; Path = $f.FullName; Kind = $kind; Lines = $lines }
    }
}

# -- The changelog's ## [Unreleased] section -------------------------------------
$clLines = @()
$start = -1
$end = -1
if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) {
    $problems += "CHANGELOG.md is not in $Root"
}
else {
    $clText = [System.IO.File]::ReadAllText($changelogPath, (New-Object System.Text.UTF8Encoding($false)))
    $clText = $clText -replace "`r`n", "`n"
    $clLines = @($clText.TrimEnd("`n") -split "`n")
    $heads = @()
    for ($i = 0; $i -lt $clLines.Count; $i++) {
        if ($clLines[$i] -match '^## \[Unreleased\]\s*$') { $heads += $i }
    }
    if ($heads.Count -ne 1) {
        $problems += "CHANGELOG.md has $($heads.Count) '## [Unreleased]' headings; a fold needs exactly one"
    }
    else {
        $start = $heads[0]
        $end = $clLines.Count
        for ($i = $start + 1; $i -lt $clLines.Count; $i++) {
            if ($clLines[$i] -match '^## \[') { $end = $i; break }
        }
    }
}

if ($problems.Count -gt 0) {
    $what = 'The changelog cannot be folded'
    if ($Check) { $what = 'The changelog would not fold' }
    Write-CliError -Message "${what}: $($problems -join '; ')." -Hint "Fix what it names, then run this again; nothing was written or deleted. $recipe"
    exit 2  # a stated refusal (AGENTS.md, "The refusal contract")
}

$counts = [ordered]@{}
foreach ($k in $kindNames) {
    $n = 0
    foreach ($fr in $fragments) { if ($fr.Kind -eq $k) { $n += @($fr.Lines | Where-Object { $_.StartsWith('- ') }).Count } }
    if ($n -gt 0) { $counts[$kindTitles[$k]] = $n }
}
$countLine = (@($counts.Keys | ForEach-Object { "$_ $($counts[$_])" }) -join ', ')

if ($fragments.Count -eq 0) {
    Write-Host "Nothing to fold: changelog.d/ holds no entries. CHANGELOG.md is unchanged."
    exit 0
}

if ($Check) {
    Write-Host "changelog.d/ holds $($fragments.Count) file(s) ready to fold: $countLine."
    exit 0
}

# -- The section, rebuilt -----------------------------------------------------
function Get-TrimmedLines {
    param([string[]]$Lines)
    $out = @($Lines)
    while ($out.Count -gt 0 -and -not $out[0].Trim()) { $out = @($out | Select-Object -Skip 1) }
    while ($out.Count -gt 0 -and -not $out[$out.Count - 1].Trim()) { $out = @($out | Select-Object -First ($out.Count - 1)) }
    return , $out
}

$body = @()
if ($end -gt $start + 1) { $body = @($clLines[($start + 1)..($end - 1)]) }

$preamble = @()
$blocks = New-Object System.Collections.ArrayList
$current = $null
foreach ($l in $body) {
    if ($l -match '^###\s+(.+?)\s*$') {
        $current = [pscustomobject]@{ Title = $Matches[1]; Lines = New-Object System.Collections.ArrayList }
        [void]$blocks.Add($current)
        continue
    }
    if ($null -eq $current) { $preamble += $l } else { [void]$current.Lines.Add($l) }
}

function Get-KindRank {
    param([string]$Title)
    $i = 0
    foreach ($t in $kindTitles.Values) {
        if ($t -ieq $Title) { return $i }
        $i++
    }
    return -1
}

foreach ($k in $kindNames) {
    $title = $kindTitles[$k]
    $entries = @()
    foreach ($fr in $fragments) { if ($fr.Kind -eq $k) { $entries += $fr.Lines } }
    if ($entries.Count -eq 0) { continue }

    $block = $null
    foreach ($b in $blocks) { if ($b.Title -ieq $title) { $block = $b; break } }
    if ($null -eq $block) {
        $block = [pscustomobject]@{ Title = $title; Lines = New-Object System.Collections.ArrayList }
        $rank = Get-KindRank $title
        $at = $blocks.Count
        for ($j = 0; $j -lt $blocks.Count; $j++) {
            if ((Get-KindRank $blocks[$j].Title) -gt $rank) { $at = $j; break }
        }
        $blocks.Insert($at, $block)
    }
    $kept = Get-TrimmedLines -Lines @($block.Lines)
    $block.Lines.Clear()
    foreach ($l in $kept) { [void]$block.Lines.Add($l) }
    foreach ($l in $entries) { [void]$block.Lines.Add($l) }
}

$section = New-Object System.Collections.ArrayList
[void]$section.Add($clLines[$start])
[void]$section.Add('')
$pre = Get-TrimmedLines -Lines $preamble
if ($pre.Count -gt 0) {
    foreach ($l in $pre) { [void]$section.Add($l) }
    [void]$section.Add('')
}
foreach ($b in $blocks) {
    [void]$section.Add("### $($b.Title)")
    [void]$section.Add('')
    $bl = Get-TrimmedLines -Lines @($b.Lines)
    foreach ($l in $bl) { [void]$section.Add($l) }
    if ($bl.Count -gt 0) { [void]$section.Add('') }
}

$out = New-Object System.Collections.ArrayList
if ($start -gt 0) { foreach ($l in $clLines[0..($start - 1)]) { [void]$out.Add($l) } }
foreach ($l in $section) { [void]$out.Add($l) }
if ($end -lt $clLines.Count) {
    foreach ($l in $clLines[$end..($clLines.Count - 1)]) { [void]$out.Add($l) }
}
else {
    while ($out.Count -gt 0 -and -not $out[$out.Count - 1]) { $out.RemoveAt($out.Count - 1) }
}
$newText = (@($out) -join "`n") + "`n"

$fragmentNames = @($fragments | ForEach-Object { "changelog.d/$($_.Name)" })
if (-not $PSCmdlet.ShouldProcess('CHANGELOG.md', "fold $($fragments.Count) file(s) from changelog.d/ into ## [Unreleased]")) {
    Write-Host ""
    Write-Host "The ## [Unreleased] section the fold would write ($countLine):"
    Write-Host ""
    foreach ($l in $section) { Write-Host $l }
    Write-Host "And it would delete: $($fragmentNames -join ', ')"
    exit 0
}

Write-CardText -Path $changelogPath -Content $newText -New
foreach ($fr in $fragments) { Remove-Item -LiteralPath $fr.Path -Force }

Write-Host "Folded $($fragments.Count) file(s) from changelog.d/ into CHANGELOG.md's ## [Unreleased]: $countLine."
Write-Host "Deleted: $($fragmentNames -join ', ')"
Write-Host "Next: rename ## [Unreleased] to ## [x.y.z] - YYYY-MM-DD and open a fresh one above it (AGENTS.md, ""A release is a tag on main"")."
exit 0
