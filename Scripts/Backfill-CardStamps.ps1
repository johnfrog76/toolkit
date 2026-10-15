<#
.SYNOPSIS
    One-time repair: write the **Created:** / **Closed:** stamps that cards
    written before the stamps existed never got, from the hub's git history.

.DESCRIPTION
    Not a verb -- no alias, no menu row. It is run once per hub, by hand.

    A card is stamped "**Created:** yyyy-MM-dd" when it is scaffolded
    and "**Closed:** yyyy-MM-dd" when it is archived, so that an archived corpus
    can be reported over -- billing included -- WITHOUT reading git. Cards older
    than that carry neither, and their dates exist in exactly one place: the
    hub's commit history. That history is not permanent. A repo gets squashed,
    re-homed or archived, and a date that lived only there is gone. On the real
    hub at the time: 241 archived cards, 2 with Created, 4 with Closed.
    (docs/CLI.md, "The two dates a card carries").

    What it derives, per card, by following the FILE through its renames:

      Created   the date of the oldest commit that is still THIS card.
      Closed    the date the file most recently ENTERED an archive/ folder --
                moved in from somewhere else, or added there directly.
                archive/ cards only.

    Three rules, each learned from the real hub:

      * A folder reorganisation is not an event. A card that went
        current/ -> archive/ in May and whose whole org folder was renamed in
        September closed in May. Only a move INTO archive/ counts, not a move
        of archive/ itself.
      * Git's copy detection must not rewrite a card's origin. --follow decides
        that a card scaffolded from the same template was "copied from" another
        card, and would hand it that card's history. Following stops at the
        first commit where the file's name becomes a DIFFERENT card (names are
        compared without the -rN round suffix, so a round rename is the same
        card).
      * An existing stamp is never rewritten. It is the record; history is only
        the fallback. So this is idempotent, and safe to run again after a sync.

    Dated PR records ("<date>-PR141415.prompt.md") are not cards and are
    skipped by name.

    It writes through Write-CardText (UTF-8, no BOM, the file's own line ending)
    and it does NOT commit: review the diff, then commit it in the hub with a
    subject that starts "backfill:" -- billing skips commits the tool itself
    makes for mechanical reasons, and that prefix is how it knows one.

.PARAMETER PromptsRoot
    The hub. Defaults to the configured promptsRoot.

.PARAMETER Org
    One org folder (promptsFolder), e.g. "globex". Default: every org the shipped
    config and the hub's hub.json declare. Never growth/ or manager/ -- their
    files are not cards.

.PARAMETER WhatIf
    Report what would be written; write nothing.

.EXAMPLE
    pwsh -NoProfile -File Scripts/Backfill-CardStamps.ps1 -WhatIf
.EXAMPLE
    pwsh -NoProfile -File Scripts/Backfill-CardStamps.ps1 -Org globex

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PromptsRoot,
    [string]$Org
)

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'ConvertTo-LocalDay.ps1')
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')

function Write-BackfillError {
    param([string]$Message, [string]$Hint)
    Write-Host ""
    Write-Host "Error: $Message" -ForegroundColor Red
    if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    Write-Host ""
}

# -- The card a path names, without its folder or its round -------------------
function Get-P20CardStem {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileName(($Path -replace '\\', '/'))
    $name = $name -replace '(\.prompt)?\.md$', ''
    return ($name -replace '-r\d+$', '')
}

function Test-P20ArchivePath {
    param([string]$Path)
    return (('/' + ($Path -replace '\\', '/')) -match '/archive/')
}

# -- What git knows about one card ---------------------------------------------
function Get-P20CardHistoryDates {
    <#
        Returns @{ Created = 'yyyy-MM-dd' or $null; Closed = ... ; Commits = n }.
        Pure over its input when -LogLines is given, which is how the suite
        drives the three rules without a repository.
    #>
    param(
        [string]$RepoRoot,
        [string]$RelPath,
        [string[]]$LogLines
    )

    if (-not $LogLines) {
        # --follow + --name-status: one "COMMIT <epoch>" line, then the status
        # line for THIS file in that commit ("A<tab>path", "M<tab>path",
        # "R100<tab>old<tab>new", "C054<tab>source<tab>new"). Newest first.
        # %at, not `%ad --date=short`: that was the AUTHOR's day in the author's
        # zone, written into a card for good. The day is read on this machine's
        # clock (ConvertTo-P20LocalDay).
        $LogLines = @(& git -C $RepoRoot log --follow --format='COMMIT %at' --name-status -- $RelPath 2>$null)
    }

    $stem = Get-P20CardStem $RelPath
    $created = $null
    $closed = $null
    $commits = 0
    $date = $null
    $stop = $false

    foreach ($raw in $LogLines) {
        if ($stop) { break }
        $line = "$raw"
        if (-not $line.Trim()) { continue }
        # An epoch from git, or a day already (how the suite's -LogLines write it).
        if ($line -match '^COMMIT (\d{4}-\d{2}-\d{2})') { $date = $Matches[1]; continue }
        if ($line -match '^COMMIT (\d+)\s*$') { $date = ConvertTo-P20LocalDay $Matches[1]; continue }
        if (-not $date) { continue }

        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $status = $parts[0]
        $newPath = $parts[$parts.Count - 1]
        $oldPath = $null
        if ($parts.Count -ge 3) { $oldPath = $parts[1] }

        # Still this card? A rename or copy FROM a different card is where this
        # card begins: count the commit, then stop following.
        if ((Get-P20CardStem $newPath) -ne $stem) { break }
        $commits++
        $created = $date

        # A rename or copy whose SOURCE is a different card is this card being
        # born, whatever git calls it: it has no earlier path of its own.
        $bornHere = ($status -like 'A*') -or ($oldPath -and ((Get-P20CardStem $oldPath) -ne $stem))
        $entersArchive = $false
        if (Test-P20ArchivePath $newPath) {
            if ($bornHere) { $entersArchive = $true }
            elseif ($oldPath -and -not (Test-P20ArchivePath $oldPath)) { $entersArchive = $true }
        }
        # Newest first, so the FIRST entry seen is the most recent one -- keep it.
        if ($entersArchive -and -not $closed) { $closed = $date }

        if ($oldPath -and ((Get-P20CardStem $oldPath) -ne $stem)) { $stop = $true }
    }

    return @{ Created = $created; Closed = $closed; Commits = $commits }
}

# -- Resolve the hub -------------------------------------------------------------
if (-not $PromptsRoot) {
    $pkgRoot = Split-Path -Parent $PSScriptRoot
    $PromptsRoot = Get-P20PromptsRoot -PackageRoot $pkgRoot
}
if (-not $PromptsRoot -or -not (Test-Path $PromptsRoot)) {
    Write-BackfillError -Message "Hub not found: '$PromptsRoot'." -Hint 'Pass -PromptsRoot, or set promptsRoot with the Config verb.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$PromptsRoot = (Resolve-Path $PromptsRoot).Path

. (Join-Path $PSScriptRoot 'Test-GitRoot.ps1')

# NOT the root check the writers use. This verb reads commit dates, and a hub
# that is a tracked SUBFOLDER of its own repository is deliberately supported
# (see the note below). What disqualifies a folder is the repository knowing
# nothing about it: a stray `git init` above the hub leaves every card
# untracked, so --is-inside-work-tree said yes and there were no dates to read.
#
if (-not (Test-P20GitTracksPath -Path $PromptsRoot)) {
    $enclosing = Get-P20EnclosingRepoHint -Path $PromptsRoot -Subject 'hub'
    Write-BackfillError -Message "'$PromptsRoot' is not a git repository, so there is no history to read dates from." `
        -Hint $(if ($enclosing) { "$enclosing Nothing was changed." } else { 'Nothing was changed. Stamps on a non-git hub can only be written by hand.' })
    exit 2  # stated refusal
}
# git is always run FROM the hub, with paths relative to the hub. Slicing a
# card's path by the length of `rev-parse --show-toplevel` was wrong wherever the
# hub path goes through a symlink (macOS /tmp and /var do): the two strings name
# the same folder with different lengths, every relative path came out mangled,
# and every card read as "no history". It also means a hub that is a SUBFOLDER
# of a repository needs no special case.
$global:LASTEXITCODE = 0

$consts = Get-P20Consts
$createdStamp = $consts.stamps.created
$closedStamp = $consts.stamps.closed

$orgFolders = @()
if ($Org) {
    $orgFolders = @($Org)
}
else {
    # The ORGS, and only the orgs: the folders the shipped config and the hub's
    # own hub.json declare. Not "every folder with a current/" -- growth/ has one
    # too, its items are *.prompt.md, and they are not cards: a different module
    # owns their shape and their dates.
    $declared = @()
    $defaultConfig = Join-Path (Split-Path -Parent $PSScriptRoot) 'config.default.json'
    if (Test-Path $defaultConfig) {
        $shipped = ConvertTo-P20SpaceKeys (Get-Content $defaultConfig -Raw | ConvertFrom-Json)
        foreach ($o in @($shipped.spaces)) { if ($o.promptsFolder) { $declared += [string]$o.promptsFolder } }
    }
    $manifest = Read-P20HubManifest -Root $PromptsRoot -WarningAction SilentlyContinue
    foreach ($o in @($manifest.Spaces)) { if ($o.promptsFolder) { $declared += [string]$o.promptsFolder } }
    $orgFolders = @($declared | Sort-Object -Unique | Where-Object { Test-Path (Join-Path $PromptsRoot $_) })
}
if ($orgFolders.Count -eq 0) {
    Write-BackfillError -Message "No declared org has a folder under '$PromptsRoot'." -Hint 'Pass -Org <folder>, or declare the org in hub.json.'
    exit 2  # stated refusal
}

$totals = @{ Cards = 0; Files = 0; CreatedAdded = 0; ClosedAdded = 0; AlreadyStamped = 0; NoHistory = 0; Written = 0 }
$noHistory = @()

Write-Host ""
Write-Host "Backfill card stamps from git history -- $PromptsRoot" -ForegroundColor Cyan
if ($WhatIfPreference) { Write-Host "  (-WhatIf: nothing will be written)" -ForegroundColor Yellow }

foreach ($orgFolder in $orgFolders) {
    $orgCreated = 0
    $orgClosed = 0
    $orgCards = 0
    foreach ($kind in @('current', 'archive')) {
        $dir = Join-Path (Join-Path $PromptsRoot $orgFolder) $kind
        if (-not (Test-Path $dir)) { continue }
        # Every work item the review generator lists, not only *.prompt.md: an
        # org's archive/ also holds plans and explorations saved as plain .md,
        # and a review dates them the same way it dates a card. Not README.md,
        # not a dated PR record, and not a dotfile (Get-ChildItem skips hidden
        # files on its own; the name test makes that explicit on Windows too).
        $files = @(Get-ChildItem -Path $dir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'README.md' -and $_.Name -notmatch '^\d{4}-\d{2}-\d{2}-' -and $_.Name -notmatch '^\.' } | Sort-Object Name)
        foreach ($file in $files) {
            $orgCards++
            $totals.Cards++
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            if ($null -eq $content) { $content = '' }
            $hasCreated = $content -match ('(?m)^' + [regex]::Escape($createdStamp))
            $hasClosed = $content -match ('(?m)^' + [regex]::Escape($closedStamp))
            $needCreated = -not $hasCreated
            $needClosed = ($kind -eq 'archive') -and (-not $hasClosed)
            if (-not $needCreated -and -not $needClosed) { $totals.AlreadyStamped++; continue }

            $rel = "$orgFolder/$kind/$($file.Name)"
            $dates = Get-P20CardHistoryDates -RepoRoot $PromptsRoot -RelPath $rel
            if ($dates.Commits -eq 0) {
                $totals.NoHistory++
                $noHistory += "$orgFolder/$kind/$($file.Name)"
                continue
            }

            $eol = "`n"
            if ($content -match "`r`n") { $eol = "`r`n" }
            $add = ''
            if ($needCreated -and $dates.Created) { $add += $createdStamp + ' ' + $dates.Created + $eol }
            # A card sitting in archive/ whose history never shows it ENTERING
            # (the repo was seeded with it already there) closed no later than
            # the day it first appears, which is its Created date.
            $closedDate = $dates.Closed
            if ($needClosed -and -not $closedDate) { $closedDate = $dates.Created }
            if ($needClosed -and $closedDate) { $add += $closedStamp + ' ' + $closedDate + $eol }
            if (-not $add) { continue }

            if ($needCreated -and $dates.Created) { $orgCreated++; $totals.CreatedAdded++ }
            if ($needClosed -and $closedDate) { $orgClosed++; $totals.ClosedAdded++ }
            $totals.Files++

            if ($PSCmdlet.ShouldProcess("$orgFolder/$kind/$($file.Name)", "add $(($add -replace '\r?\n', ' ').Trim())")) {
                if ($content -and -not $content.EndsWith("`n")) { $content += $eol }
                Write-CardText -Path $file.FullName -Content ($content + $add)
                $totals.Written++
            }
        }
    }
    Write-Host ("  {0,-14} {1,4} cards   +{2,3} Created   +{3,3} Closed" -f $orgFolder, $orgCards, $orgCreated, $orgClosed)
}

Write-Host ""
$verb = 'Wrote'
if ($WhatIfPreference) { $verb = 'Would write' }
Write-Host ("{0} {1} file(s): +{2} Created, +{3} Closed. {4} card(s) already fully stamped." -f `
        $verb, $totals.Files, $totals.CreatedAdded, $totals.ClosedAdded, $totals.AlreadyStamped) -ForegroundColor Green
if ($totals.NoHistory -gt 0) {
    Write-Host "$($totals.NoHistory) card(s) have no commit history (untracked or never committed) and were left alone:" -ForegroundColor Yellow
    foreach ($n in ($noHistory | Select-Object -First 10)) { Write-Host "    $n" -ForegroundColor DarkGray }
}
if (-not $WhatIfPreference -and $totals.Written -gt 0) {
    Write-Host "Nothing was committed. Review the diff, then commit in the hub with a subject starting 'backfill:'." -ForegroundColor Gray
}
Write-Host ""
exit 0
