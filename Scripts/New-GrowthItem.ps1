<#
.SYNOPSIS
    Create a training, presentation or goal artifact under growth/current/.
.DESCRIPTION
    Writes <promptsRoot>/growth/current/{type}-{date}-{slug}.prompt.md in the
    hub, in the shape docs/hub/growth.md documents. The folder is named by the
    hub -- hub.json's folders.growth, defaulting to 'growth'. That document --
    not this script and not the agent -- is the contract. This script is the
    one writer: the web UI's create runs it through the bridge
    (POST /api/cmd/NewGrowth), and the agent only reads what it writes.

    growth/ is a HUB-ROOT folder. It sits beside the per-org folders, not inside
    one, because a training you took does not stop having happened when you
    switch org. It is resolved from promptsRoot and never from where this script
    happens to live.
.EXAMPLE
    {cliPrefix}NewGrowth -Title "Clean Architecture" -DueDate <yyyy-mm-dd> -Hours 8
.EXAMPLE
    {cliPrefix}NewGrowth -Type presentation -Title "Designing for Non-Determinism" -Date <yyyy-mm-dd>
.EXAMPLE
    {cliPrefix}NewGrowth -Type goal -Title "Improve test coverage patterns"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("training", "presentation", "goal")]
    [string]$Type = "training",

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Date,

    [Parameter(Mandatory = $false)]
    [string]$DueDate,

    [Parameter(Mandatory = $false)]
    [string]$Provider,

    [Parameter(Mandatory = $false)]
    [string]$Hours,

    [Parameter(Mandatory = $false)]
    [string]$Notes,

    # -Close <file>: retire a growth item. The module closes its own data --
    # Archive is org-scoped and cannot see growth/ -- the way MeetingAgenda -Close
    # does for a session: move to growth/archive/ and stamp **Closed:** from the
    # one shared writer.
    [Parameter(Mandatory = $false)]
    [string]$Close,

    # -Complete <file>: mark a GOAL complete. Writes the `**Status**` line under
    # the goal's `## Outcome` heading as `Achieved`, through Set-P20CardLine (the
    # one in-place line writer), and nothing else in the file moves. The file
    # stays in growth/current/ -- putting it away is -Close.
    [Parameter(Mandatory = $false)]
    [string]$Complete,

    # Names what would be written or moved, and writes nothing.
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# The package root: the parent of Scripts/. Never the hub -- the two are
# separate trees and only config says where the second one is.
$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)NewGrowth - create a growth artifact" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)NewGrowth -Title <string> [-Type training|presentation|goal] [-Date YYYY-MM-DD]"
    Write-Host "              [-DueDate YYYY-MM-DD (required for a training)] [-Provider <string>]"
    Write-Host "              [-Hours <string>] [-Notes <string>] [-WhatIf]"
    Write-Host "    $($p)NewGrowth -Close <file> [-WhatIf]"
    Write-Host "    $($p)NewGrowth -Complete <file> [-WhatIf]"
    Write-Host ""
    Write-Host "  PARAMETERS:" -ForegroundColor Yellow
    Write-Host "    -Type       training (default), presentation or goal"
    Write-Host "    -Title      course, talk or goal title (required)"
    Write-Host "    -Date       start date for a training, event date for a presentation (default: today)"
    Write-Host "    -DueDate    completion deadline -- required for a training"
    Write-Host "    -Provider   who delivers the training (training only)"
    Write-Host "    -Hours      total hours (training only)"
    Write-Host "    -Notes      one line of context, written into Description / Context / Why This Matters"
    Write-Host "    -Close      archive a growth item: move growth/current/<file> to growth/archive/ and stamp the date"
    Write-Host "    -Complete   mark a goal complete: write its Outcome Status line as Achieved; nothing else changes"
    Write-Host "    -WhatIf     name the file that would be written or moved, and write nothing"
    Write-Host ""
    Write-Host "  EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    $($p)NewGrowth -Title 'Clean Architecture' -DueDate 2026-10-01 -Hours 8"
    Write-Host "    $($p)NewGrowth -Type presentation -Title 'Designing for Non-Determinism' -Date 2026-09-15"
    Write-Host "    $($p)NewGrowth -Type goal -Title 'Improve test coverage patterns'"
    Write-Host "    $($p)NewGrowth -Close training-2026-09-01-clean-architecture"
    Write-Host "    $($p)NewGrowth -Complete goal-2026-improve-test-coverage-patterns -WhatIf"
    Write-Host ""
    exit 0
}

# -- Resolve the hub ----------------------------------------------------------
# One resolver, one rule: PROMPTS_ROOT in the environment is an explicit override
# and WINS, then the configured promptsRoot. Get-P20PromptsRoot in
# Resolve-HubConfig.ps1 is the only implementation of that -- every script read
# the two config files for itself, and the copies had drifted
# into three different precedences.
# Dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, pwsh -File).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot

# The display name is the engineer's, not the hub's, so it keeps its own read of
# the two files for a run with no module.
$cfg = $global:P20Config
$displayName = ''
if ($cfg -and $cfg.BranchUser) { $displayName = $cfg.BranchUser }
if (-not $displayName) {
    $cfgDefaultPath = Join-Path $repoRoot 'config.default.json'
    $cfgLocalPath   = Join-Path $repoRoot 'config.local.json'
    $defaults = $null
    $local = $null
    if (Test-Path $cfgDefaultPath) { $defaults = Get-Content $cfgDefaultPath -Raw | ConvertFrom-Json }
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
    $local = Read-P20LocalConfigJson -Path $cfgLocalPath
    if ($local -and $local.branchUser)        { $displayName = $local.branchUser }
    elseif ($defaults -and $defaults.branchUser) { $displayName = $defaults.branchUser }
}
# The one byte contract for a hub file -- see Scripts/Write-CardText.ps1.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-Consts.ps1') }

# -- Close / Complete: one lookup, two moves ----------------------------------------
# Both name an item already in growth/current/, and both find it the same way: the
# exact file name first, then a unique partial match.
if ($Close -and $Complete) {
    Write-CliError -Message '-Close and -Complete are two moves; pass one.' `
        -Hint "Complete the goal first, then archive it with -Close."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$target = if ($Close) { $Close } else { $Complete }
if ($target) {
    if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $growthRoot = Get-P20HubFolder -Name 'growth' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
    $growthCurrent = Join-Path $growthRoot ([string](Get-P20Consts).folders.current)
    $growthArchive = Join-Path $growthRoot ([string](Get-P20Consts).folders.archive)
    $wanted = [System.IO.Path]::GetFileName($target)
    if ($wanted -notmatch '\.prompt\.md$') { $wanted = "$wanted.prompt.md" }
    $hits = @()
    if (Test-Path $growthCurrent) {
        $hits = @(Get-ChildItem -LiteralPath $growthCurrent -Filter '*.prompt.md' -File | Where-Object { $_.Name -eq $wanted })
        if ($hits.Count -eq 0) {
            $stem = $wanted -replace '\.prompt\.md$', ''
            $hits = @(Get-ChildItem -LiteralPath $growthCurrent -Filter '*.prompt.md' -File | Where-Object { $_.Name -like "*$stem*" })
        }
    }
    if ($hits.Count -eq 0) {
        $archived = (Test-Path $growthArchive) -and (Test-Path (Join-Path $growthArchive $wanted))
        # Idempotent: already archived is a report, not an error -- the state is
        # where the file is, exactly as a card's and a session's are.
        if ($Close -and $archived) {
            Write-Host "Already closed: growth/archive/$wanted" -ForegroundColor DarkGray
            exit 0
        }
        if ($archived) {
            Write-CliError -Message "growth/archive/$wanted is archived; an archived goal is not edited from here." `
                -Hint "The archive is the record. Edit the file by hand if its Status line is wrong."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        Write-CliError -Message "No growth item matches '$target' in growth/current/." `
            -Hint "Pass the file name as it appears under growth/current/."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($hits.Count -gt 1) {
        Write-CliError -Message "'$target' matches $($hits.Count) growth items: $(($hits | ForEach-Object { $_.Name }) -join ', ')" `
            -Hint "Be more specific, or pass the full file name."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    if ($Complete) {
        $goalName = $hits[0].Name
        if ($goalName -notlike 'goal-*') {
            Write-CliError -Message "$goalName is not a goal. -Complete writes a goal's Outcome Status line." `
                -Hint "A training reads complete from its ## Status line and a presentation from **Delivered**; edit those in the file."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        # Where the Status line is: the first `**Status**...:` line under the first
        # heading that STARTS WITH `## Outcome`, up to the next `##` heading. That is
        # the reader's own rule (agent/growth/growth.py, parse_growth_file; the table
        # in docs/hub/growth.md), so the line written is the line read.
        $goalPath = $hits[0].FullName
        $goalLines = ([System.IO.File]::ReadAllText($goalPath) -replace "`r`n", "`n").Split("`n")
        $inOutcome = $false
        $statusAt = -1
        for ($i = 0; $i -lt $goalLines.Count; $i++) {
            $trimmed = $goalLines[$i].Trim()
            if ($inOutcome) {
                if ($goalLines[$i].StartsWith('##')) { break }
                if ($goalLines[$i] -match '\*\*Status\*\*[^:]*:') { $statusAt = $i; break }
            }
            elseif ($trimmed -match '^##\s+outcome') { $inOutcome = $true }
        }
        if ($statusAt -lt 0) {
            Write-CliError -Message "$goalName has no **Status** line under its ## Outcome heading. Nothing was written." `
                -Hint "Add '- **Status**: Not Started' under ## Outcome, as the goal template has it, and run it again."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $statusLine = $goalLines[$statusAt]
        # The label as this file writes it -- `- **Status**:` in the template, any
        # older shape the reader accepts otherwise -- so the line keeps its own form.
        $stamp = ([regex]::Match($statusLine, '^.*?\*\*Status\*\*[^:]*:')).Value
        $current = $statusLine.Substring($stamp.Length).Trim()
        # Already complete is a report, not an error. The words are the reader's:
        # a value starting Complet or Achiev reads as complete (docs/hub/growth.md).
        if ($current.ToLower().StartsWith('complet') -or $current.ToLower().StartsWith('achiev')) {
            Write-Host "Already complete: growth/current/$goalName ($current)" -ForegroundColor DarkGray
            exit 0
        }
        # Set-P20CardLine replaces the FIRST line starting with the label, so the
        # label must not start an earlier line too -- a hand-written goal with a
        # second Status line above its outcome would otherwise be edited in the wrong place.
        $firstAt = -1
        for ($i = 0; $i -lt $goalLines.Count; $i++) {
            if ($goalLines[$i] -match ('^' + [regex]::Escape($stamp))) { $firstAt = $i; break }
        }
        if ($firstAt -ne $statusAt) {
            Write-CliError -Message "$goalName has a '$stamp' line above its ## Outcome heading, so the Status line is not the only one. Nothing was written." `
                -Hint "Edit the Outcome Status line by hand."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $completeValue = 'Achieved'
        if ($WhatIf) {
            Write-Host "  [WhatIf] growth/current/$($goalName): $stamp $completeValue"
            Write-Host "    FILE: $goalPath"
            Write-Host "  [WhatIf] No changes were made."
            exit 0
        }
        . (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
        [void](Set-P20CardLine -Path $goalPath -Stamp $stamp -Value $completeValue)
        Write-Host "Completed: growth/current/$goalName -- Status: $completeValue" -ForegroundColor Green
        Write-Host "    FILE: $goalPath"
        exit 0
    }

    $source = $hits[0].FullName
    $dest = Join-Path $growthArchive $hits[0].Name
    if (Test-Path $dest) {
        Write-CliError -Message "growth/archive/$($hits[0].Name) already exists. Not overwriting it." `
            -Hint "The archived copy is the record. Compare the two and delete whichever is the duplicate."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($WhatIf) {
        Write-Host "  [WhatIf] growth/current/$($hits[0].Name) -> growth/archive/$($hits[0].Name), stamped with the date it closed"
        Write-Host "    FILE: $source"
        Write-Host "  [WhatIf] No changes were made."
        exit 0
    }
    if (-not (Test-Path $growthArchive)) { New-Item -ItemType Directory -Path $growthArchive -Force | Out-Null }
    Move-Item -LiteralPath $source -Destination $dest -ErrorAction Stop
    # Stamped AFTER the move, on the archived copy: the move is the promise and
    # the stamp is the record, so a stamp that fails must not leave the file in current/.
    . (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')
    Add-ClosedDate -Path $dest
    Write-Host "Closed: growth/archive/$($hits[0].Name)" -ForegroundColor Green
    exit 0
}
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- The hub-root folder's NAME is the hub's, not this script's ----------------
# hub.json's "folders" block can rename it. Resolve-HubConfig.ps1 is the single
# reader of that, dot-sourced above rather than called through the module because
# this script also runs with no module in the session (a test sandbox, pwsh -File).

if (-not $Title) {
    Write-CliError -Message '-Title is required.' -Hint "run '$(Get-CliPrefix)NewGrowth -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM-dd') }

if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-CliError -Message "invalid date '$Date' -- expected YYYY-MM-DD."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($DueDate -and $DueDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-CliError -Message "invalid due date '$DueDate' -- expected YYYY-MM-DD."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Type -eq "training" -and -not $DueDate) {
    Write-CliError -Message '-DueDate is required for a training item.' `
        -Hint "run '$(Get-CliPrefix)NewGrowth -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Slug: lowercase alphanumerics, hyphen separated, 40 characters at most.
$slug = ($Title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }

# A goal is dated by YEAR, not by day: it belongs to a review period, not to an
# afternoon. That is growth/README.md's convention, promoted to docs/hub/growth.md.
if ($Type -eq "goal") {
    $fileName = "goal-" + $Date.Substring(0, 4) + "-$slug.prompt.md"
}
else {
    $fileName = "$Type-$Date-$slug.prompt.md"
}

$currentDir = Join-Path (Get-P20HubFolder -Name 'growth' -PromptsRoot $promptsRoot -PackageRoot $repoRoot) ([string](Get-P20Consts).folders.current)
$filePath = Join-Path $currentDir $fileName

if (Test-Path $filePath) {
    Write-Host "Already there: $filePath" -ForegroundColor Yellow
    Write-Host "    FILE: $filePath"
    exit 0
}
if ($WhatIf) {
    Write-Host "  [WhatIf] would create $fileName"
    Write-Host "    FILE: $filePath"
    Write-Host "  [WhatIf] No changes were made."
    exit 0
}
if (-not (Test-Path $currentDir)) {
    New-Item -Path $currentDir -ItemType Directory -Force | Out-Null
}

# ASCII 'to' rather than a dash: this string is parsed back by both readers and
# a PS 5.1 shell on a Windows-1252 code page misreads an en dash inside a
# double-quoted string.
$dateField   = if ($DueDate) { "$Date to $DueDate" } else { $Date }
$hoursVal    = if ($Hours) { $Hours } else { "TBD" }
$providerVal = if ($Provider) { $Provider } else { "" }
$notesVal    = if ($Notes) { $Notes } else { "" }

if ($Type -eq "training") {
    $content = @"
# Training Artifact

---

## Title

$Title

## Type

Voluntary

## Date(s)

$dateField

## Hours

$hoursVal

## Provider

$providerVal

---

## Description

$notesVal

---

## Status

Not Started

## Key Takeaways

-
-
-

---

## Outcome

- **Completed**: No
- **Certificate / badge**:
- **Applied to work**:
"@
}
elseif ($Type -eq "goal") {
    $content = @"
# Goal Artifact

---

## Goal

$Title

## Category

## Time Frame

$dateField

---

## Why This Matters

$notesVal

---

## Milestones

- [ ]
- [ ]
- [ ]

---

## Progress Log

| Date | Update |
|------|--------|
|      |        |

---

## Outcome

- **Status**: Not Started
- **Evidence**:
- **Impact**:
"@
}
else {
    $content = @"
# Presentation Artifact

---

## Title

$Title

## Presenter

$displayName

## Date & Time

$dateField

## Format

## Prep Estimate

## Audience

---

## Context & Intent

$notesVal

---

## Outline / Slide Summary

### Section 1 -
### Section 2 -
### Section 3 -

---

## Key Themes

---

## Outcome & Follow-Up

- **Delivered**: No
- **Audience size**:
- **Feedback received**:
- **Follow-up actions**:
- **Recording / materials link**:
"@
}

# LF, no BOM, one trailing newline. Every one of those three is part of the
# documented shape, so the file comes out the same from a terminal and from the
# browser on every host. The LF is -New's job, not a -replace of this script's
# own: one writer, one rule.
#
Write-CardText -Path $filePath -Content ($content + "`n") -New

Write-Host "Created $fileName" -ForegroundColor Green
Write-Host "    FILE: $filePath"
exit 0
