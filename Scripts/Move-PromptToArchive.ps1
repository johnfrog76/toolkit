<#
.SYNOPSIS
    Moves a prompt file from current/ to archive/ and commits the change.
.DESCRIPTION
    Tab-completes against files in the current/ folder. Moves the file,
    stages both the delete and the add, and commits with a standard message.
    Use -WhatIf to preview without making changes.
.EXAMPLE
    {cliPrefix}Archive US-316615-plg-one-more-end-to-end-testing.prompt.md
.EXAMPLE
    {cliPrefix}Archive 316615        # by ID -- matches id 316615 and nothing else
.EXAMPLE
    {cliPrefix}Archive -List         # show files available to archive
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$File,

    [Parameter(Mandatory = $false)]
    [switch]$List,

    [Parameter(Mandatory = $false)]
    [switch]$Relink,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$cfg = $global:P20Config
$promptsRoot = $cfg.PromptsRoot

# The contract is exactly "no longer in current/". Committing is a
# convenience for stores that happen to be git, and nothing is ever read back from
# git -- so a synced folder, a share, or no backup at all loses none of the
# contract. Set at script scope: the round-rename path and the plain move path
# both need it, and only one of them runs.
$storeIsGit = ($cfg.StoreSync -eq 'git')
# Test-P20HubRoot and the one "hub not found" sentence live here, and this file
# is dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, `pwsh -File`).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$folders = Get-PromptFolders
$currentDir = $folders.Current
# The stamp has one writer, and it is not this file any more: MeetingAgenda -Close
# retires a 1:1 session the same way, and agent/ado/reporting.py reads the result.
. (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')

$archiveDir = $folders.Archive

# The one card-filename rule -- what counts as an id, and which prefixes may sit
# in front of it. Shared with NewPrompt's next-id scan so the two cannot
# disagree about which card "139" is.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')

# The links a card carries back into the package. Archive already rewrites the
# file on the way past (the Closed stamp), and it is the one verb that CHANGES a
# card's folder -- so it is where a frozen relative path gets recomputed.
#
. (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')

# git runs through the one helper that keeps stderr as text on both hosts: a
# raw `git ... 2>&1` under $ErrorActionPreference = 'Stop' throws on Windows
# PowerShell 5.1 before the exit code can be read.
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

function Show-Help {
    Write-Host @"

Move-P20PromptToArchive - Move a prompt from current/ to archive/ and commit

USAGE:
    $(Get-CliPrefix)Archive <ID>
    $(Get-CliPrefix)Archive <filename>
    $(Get-CliPrefix)Archive -List
    $(Get-CliPrefix)Archive -Relink
    $(Get-CliPrefix)Archive -WhatIf <ID>

PARAMETERS:
    -File <string>    The card's ID (all digits -- matches that id and no
                      other), or a filename. A name that is not an exact
                      filename may still match one card by partial name;
                      the match is named before anything moves.
    -List             Show files in current/ that can be archived
    -Relink           Rewrite every card's package links in current/ and
                      archive/ from where the hub and the package are now,
                      and archive nothing
    -WhatIf           Preview what would happen without making changes
    -Help             Show this help message

EXAMPLES:
    $(Get-CliPrefix)Archive 316615
    $(Get-CliPrefix)Archive US-316615-plg-one-more-end-to-end-testing.prompt.md
    $(Get-CliPrefix)Archive -List
    $(Get-CliPrefix)Archive -WhatIf 316615

IDS ARE NOT SUBSTRINGS:
    An all-digit argument is an ID and matches only the card whose id is
    exactly that number -- the same rule NewPrompt uses to find the next free
    id. "$(Get-CliPrefix)Archive 39" on a hub holding Task139 archives nothing
    and says so, where it used to move and commit Task139
    (issues: bug-archive-matches-an-id-as-a-substring).

ROUND HISTORY:
    When a prompt is archived more than once, prior rounds are preserved
    via -rN suffixes instead of being overwritten:

      First archive:  file moves to archive/ with its original name.
      Second archive: the existing archived file is renamed to
                      <name>-r1 in a separate "round history" commit,
                      and the incoming file is archived as <name>-r2.
      Third+:         the incoming file gets the next -rN
                      (e.g. -r3, -r4, ...).
"@
    return
}

if ($Help) { Show-Help; return }

# List mode
if ($List) {
    $files = Get-ChildItem -Path $currentDir -File | Select-Object -ExpandProperty Name
    if ($files.Count -eq 0) {
        Write-Host "No files in current/." -ForegroundColor Yellow
    }
    else {
        Write-Host "Files in current/ ($($files.Count)):" -ForegroundColor Cyan
        $files | ForEach-Object { Write-Host "  $_" }
    }
    return
}

# A bare call moved nothing, so it may not report success. It used to warn and
# return with the exit code untouched, which through the bridge reads exactly
# like an archive that worked.
# Relink mode. A card's `> Template:` and `ado-comments workflow` links are
# relative paths from the card to the package, so moving either one breaks every
# card written before the move. Archive fixes the card it moves; this fixes a
# whole hub at once, which is what a reorganisation needs.
if ($Relink) {
    $total = 0
    # Every org the hub declares, not only the active one (Get-P20CardFolders).
    $cardFolders = Get-P20CardFolders -Root $promptsRoot -Spaces $cfg.Spaces `
        -CurrentName (Split-Path $currentDir -Leaf) -ArchiveName (Split-Path $archiveDir -Leaf) `
        -Also @($currentDir, $archiveDir)
    foreach ($folder in $cardFolders) {
        $total += Repair-P20FolderLinks -Folder $folder
    }
    if ($total -eq 0) {
        Write-Host "Package links are already correct -- nothing rewritten." -ForegroundColor Gray
    }
    else {
        Write-Host "Refreshed package links in $total card(s)." -ForegroundColor Green
    }
    return
}

if (-not $File) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID, or run '$(Get-CliPrefix)Archive -List' to see the candidates."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Find matching file(s).
#
# An all-digit argument is an ID and is matched as one: only the card whose id
# is exactly that number, read with the shared card-name rule (an optional type
# prefix, the id, then the dash that starts the slug). There is no substring
# fallback for digits -- that fallback is what made `Archive 39` move and commit
# Task139 on a hub with short ids, and the only sign was a "Moved:" line naming
# a card nobody typed.
#
# Anything else is a FILENAME: exact first, then a partial match, and a partial
# match is named out loud before anything moves.
#
# -ErrorAction SilentlyContinue: a hub whose current/ has not been created yet is
# "nothing matched", which the refusal below states properly -- not a raw
# Get-ChildItem error record in front of it.
# One rule for "what did they mean?", shared with every verb that takes a card:
# Resolve-P20CardArgument. An id -- a work item number, or the four-character id
# of a card with no work item, typed in any case -- matches that id and NEVER
# falls to a partial name. It used to be '^\d+$' here.
$resolved = Resolve-P20CardArgument -Argument $File -Folder $currentDir `
    -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
$isId = $resolved.IsId
$fuzzy = $resolved.Fuzzy
$match = $resolved.Match

# Already in archive/? Then the job is done: say where, and exit 0. Archive may
# be idempotent because it touches no tracker -- moving a file that has already
# moved changes nothing anywhere -- so the board's drop onto Done from a stale
# view reports success and the refetch confirms it.
#
# THE BOUNDARY: this is for verbs whose whole effect is local. CloseItem and
# NewPR act on Azure DevOps, where "it already happened" is not something this
# tool can know from a file -- do not extend this to them by analogy.
# An id, or an exact filename, counts; a partial name never does.
if (-not $match) {
    $archivedHit = Resolve-P20CardArgument -Argument $File -Folder $archiveDir `
        -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
    $archived = @($archivedHit.Match | Where-Object { $_.Name -like '*.prompt.md' })
    if ($archived.Count -gt 0 -and -not $archivedHit.Fuzzy) {
        $rootForRel = ($promptsRoot -replace '\\', '/').TrimEnd('/')
        foreach ($a in $archived) {
            $rel = $a.FullName -replace '\\', '/'
            if ($rel.StartsWith($rootForRel + '/', [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($rootForRel.Length + 1) }
            Write-Host "[=] Already archived: $rel" -ForegroundColor DarkGray
        }
        exit 0
    }
}

if ($isId -and -not $match) {
    Write-CliError -Message "No card with id '$File' in current/." `
        -Hint "'$File' has the shape of an ID, and an ID is not a partial name. Run '$(Get-CliPrefix)Archive -List' to see the candidates."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Neither of these moved anything, so neither may report success. They used to
# write a raw error record (or a warning) and return with the exit code
# untouched, so `$LASTEXITCODE` stayed 0 and the bridge told the browser the card
# had been archived.
if (-not $match) {
    Write-CliError -Message "No file matching '$File' found in current/." `
        -Hint "Run '$(Get-CliPrefix)Archive -List' to see the candidates."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (@($match).Count -gt 1) {
    Write-Host "Matches for '$File':" -ForegroundColor Yellow
    @($match) | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$File' matches $(@($match).Count) files in current/." `
        -Hint "Be more specific, or run '$(Get-CliPrefix)Archive -List' to see the candidates."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# One card matched something the caller did not type in full. In a terminal that
# is a convenience and the target is named first, so the "Moved:" line is never
# the first time the user learns which card this was. Through the bridge there
# is nobody to read it -- TOOLKIT_QUIET_STARTUP is how a non-interactive caller
# says so (AGENTS.md, "The refusal contract") -- so an inexact match refuses
# rather than guessing on the browser's behalf.
if ($fuzzy) {
    if ($env:TOOLKIT_QUIET_STARTUP) {
        Write-CliError -Message "'$File' is not a card in current/; it matches '$(@($match)[0].Name)' only by partial name." `
            -Hint "Pass the card's ID or its full filename."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-Host "Matched '$File' -> $(@($match)[0].Name)" -ForegroundColor Cyan
}

$sourcePath = $match.FullName
$fileName = $match.Name

if ($fileName -notmatch '\.prompt\.md$') {
    Write-Error "Move-P20PromptToArchive only handles *.prompt.md files; got '$fileName'. Round history relies on the .prompt.md convention."
    return
}

$destPath = Join-Path $archiveDir $fileName
$currentRel = $sourcePath.Replace('\', '/')
$archiveRel = $destPath.Replace('\', '/')
$rootNorm = $promptsRoot.Replace('\', '/').TrimEnd('/')
# The two folders a move touches, relative to the hub root. git is staged with
# these (directory pathspecs), never with the card's own paths: a card that was
# never committed has no tracked path in current/, and an exact pathspec that
# matches nothing makes the whole `git add` abort.
$currentDirRel = $currentDir.Replace('\', '/')
$archiveDirRel = $archiveDir.Replace('\', '/')
if ($currentDirRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $currentDirRel = $currentDirRel.Substring($rootNorm.Length).TrimStart('/')
}
if ($archiveDirRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $archiveDirRel = $archiveDirRel.Substring($rootNorm.Length).TrimStart('/')
}
if ($currentRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $currentRel = $currentRel.Substring($rootNorm.Length + 1)
}
if ($archiveRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $archiveRel = $archiveRel.Substring($rootNorm.Length + 1)
}

# --- Round-aware archive: preserve prior rounds instead of overwriting ---
# Guarded above: $fileName is known to end in .prompt.md.
$null = $fileName -match '^(.+?)(\.prompt\.md)$'
$baseName = $Matches[1]
$ext = $Matches[2]

# A hub whose org folder has never archived anything has no archive/ yet --
# which is every hub, the first time. Create it HERE, before the round scan
# reads it: the scan used to run first and wrote a red Get-ChildItem error to
# the console on a first archive, then succeeded anyway. Under -WhatIf nothing
# is created and the scan below finds no prior rounds, which is the truth.
if (-not $WhatIfPreference -and -not (Test-Path $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

# Find existing rounds in archive for this card: the same stem (strip any -rN
# suffix), OR the same card id under a different slug. A card whose title was
# edited on the board between rounds has a different file name, and by name
# alone it archived plainly beside its earlier round -- two unrelated files to
# anything that counts rounds.
# The id rule is the one every verb reads ids with.
$stem = if ($baseName -match '^(.+)-r\d+$') { $Matches[1] } else { $baseName }
$roundIdPattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
$thisCardId = Get-P20CardId -Name $fileName -Pattern $roundIdPattern
$existingRounds = @()
if (Test-Path $archiveDir) {
    $existingRounds = @(Get-ChildItem -Path $archiveDir -File | Where-Object {
        ($_.Name -match "^$([regex]::Escape($stem))(-r\d+)?$([regex]::Escape($ext))$") -or
        ($thisCardId -and $_.Name -match "$([regex]::Escape($ext))$" -and
            (Get-P20CardId -Name ($_.Name -replace '-r\d+(?=\.prompt\.md$)', '') -Pattern $roundIdPattern) -eq $thisCardId)
    })
}

if ($existingRounds -and $existingRounds.Count -gt 0) {
    # Determine the highest existing round number
    $maxRound = 0
    foreach ($f in $existingRounds) {
        if ($f.Name -match '-r(\d+)') {
            $round = [int]$Matches[1]
            if ($round -gt $maxRound) { $maxRound = $round }
        }
    }

    # If an existing round has no round suffix, rename it to -r1 -- under ITS
    # OWN stem, so an earlier round keeps the title it was archived with.
    # On the NAME: BaseName only strips '.md', so '-r1.prompt' would read as plain.
    $plainRounds = @($existingRounds | Where-Object { $_.Name -notmatch '-r\d+\.prompt\.md$' })
    $plainArchive = $null
    $plainStem = $stem
    if ($plainRounds.Count -gt 0) {
        $plainArchive = $plainRounds[0].FullName
        $null = $plainRounds[0].Name -match '^(.+?)(\.prompt\.md)$'
        $plainStem = $Matches[1]
    }
    $renameFailure = $null
    if ($plainArchive -and (Test-Path $plainArchive)) {
        $r1Name = "$plainStem-r1$ext"
        $r1Path = Join-Path $archiveDir $r1Name
        $r1Rel = $r1Path.Replace('\', '/')
        if ($r1Rel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $r1Rel = $r1Rel.Substring($rootNorm.Length + 1)
        }
        Write-Host "Renaming prior archive to $r1Name (preserving round 1)" -ForegroundColor Yellow
        $plainRel = $plainArchive.Replace('\', '/')
        if ($plainRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $plainRel = $plainRel.Substring($rootNorm.Length + 1)
        }
        Push-Location $promptsRoot
        try {
            Rename-Item -Path $plainArchive -NewName $r1Name
            if ($storeIsGit) {
                # archive/ as a directory: the prior round may never have been committed.
                $null = Invoke-P20TrackerRead 'git' @('add', '-A', '--', $archiveDirRel)
                # Same failure path as the main archive commit below: a hook or a lock that
                # refuses it is a stated refusal, not a staged rename nobody hears about.
                $renameCommit = Invoke-P20TrackerRead 'git' @('commit', '-m', "archive: rename $($plainRounds[0].Name) to $r1Name (round history)")
                foreach ($line in $renameCommit.Lines) { Write-Host $line }
                if ($renameCommit.Code -ne 0) {
                    $renameFailure = "git commit failed: $(@($renameCommit.Lines | Where-Object { $_ })[0])"
                }
            }
        }
        finally { Pop-Location }
        if ($renameFailure) {
            Write-CliError -Message "The earlier archive was renamed to $r1Name (round history), but the rename is not committed -- $renameFailure. $fileName was not archived." `
                -Hint "The rename is already done and staged, and the card is still in current/. Fix what git refused (a hook, a lock), then run '$(Get-CliPrefix)Archive' again."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($maxRound -lt 1) { $maxRound = 1 }
    }

    # New file gets the next round number
    $nextRound = $maxRound + 1
    $fileName = "$stem-r$nextRound$ext"
    $destPath = Join-Path $archiveDir $fileName
    $archiveRel = $destPath.Replace('\', '/')
    if ($archiveRel.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
        $archiveRel = $archiveRel.Substring($rootNorm.Length + 1)
    }
    Write-Host "Archiving as round $nextRound -> $fileName" -ForegroundColor Cyan
}

if ($PSCmdlet.ShouldProcess("$fileName", "Move to archive and commit")) {
    # archive/ was created above the round scan, which reads it; this is the
    # belt to that braces. Without either, Move-Item fails non-terminating, the
    # "Moved:" line below still prints, and the card silently stays in
    # current/ -- found through the web bridge against the fixture hub.
    if (-not (Test-Path $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }
    Move-Item -Path $sourcePath -Destination $destPath -ErrorAction Stop
    Write-Host "Moved: $currentRel -> $archiveRel" -ForegroundColor Green

    # Stamp the closed date into the file. The commit below records "when"
    # too, but that is an external dependency of exactly the kind that docs/hub/cards.md, "State is derived, never stored",
    # exists to avoid -- an archived corpus should stay readable, and billable,
    # with no git at all. Stamped before staging so it lands in the same commit.
    Add-ClosedDate -Path $destPath

    # The card just changed folder, so its links to the package may have changed
    # depth with it. Today current/ and archive/ sit at the same depth and
    # nothing moves -- which is exactly why this has to be computed rather than
    # assumed, on a hub whose shape is a convention and not a guarantee.
    $null = Repair-P20CardLinks -Path $destPath

    # Stage and commit
    Push-Location $promptsRoot
    try {
        if (-not $storeIsGit) {
            Write-Host "Archived. Store is not git (storeSync='$($cfg.StoreSync)') -- nothing committed." -ForegroundColor DarkGray
        }
        else {
            $gitFailure = $null
            $add = Invoke-P20TrackerRead 'git' @('add', '-A', '--', $currentDirRel, $archiveDirRel)
            if ($add.Code -ne 0) {
                $gitFailure = "git add failed: $(@($add.Lines | Where-Object { $_ })[0])"
            }
            else {
                # Nothing staged (the move left no difference git can see) is not a failure.
                $staged = Invoke-P20TrackerRead 'git' @('diff', '--cached', '--quiet', '--', $currentDirRel, $archiveDirRel)
                if ($staged.Code -eq 0) {
                    Write-Host "Nothing to commit." -ForegroundColor DarkGray
                }
                else {
                    $commit = Invoke-P20TrackerRead 'git' @('commit', '-m', "archive: move $fileName to archive")
                    foreach ($line in $commit.Lines) { Write-Host $line }
                    if ($commit.Code -ne 0) {
                        $gitFailure = "git commit failed: $(@($commit.Lines | Where-Object { $_ })[0])"
                    }
                    else {
                        Write-Host "Committed." -ForegroundColor Green
                    }
                }
            }
        }
    }
    finally {
        Pop-Location
    }
    if ($gitFailure) {
        Write-CliError -Message "$fileName was moved to archive/, but it is not committed -- $gitFailure" `
            -Hint "The file is already in archive/. Commit it yourself (git add -A; git commit) or run '$(Get-CliPrefix)Sync'."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
