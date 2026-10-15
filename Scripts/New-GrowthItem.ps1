<#
.SYNOPSIS
    Create a training, presentation or goal artifact under growth/current/.
.DESCRIPTION
    Writes <promptsRoot>/growth/current/{type}-{date}-{slug}.prompt.md in the
    hub, in the shape docs/hub/growth.md documents. The folder is named by the
    hub -- hub.json's folders.growth, defaulting to 'growth'. That document --
    not this script and not the agent -- is the contract: POST /api/growth writes the same bytes for the
    same inputs, and Tests/test_growth.py compares the two.

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

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# The package root: the parent of Scripts/. Never the hub -- the two are
# separate trees and only config says where the second one is.
$repoRoot = Split-Path -Parent $PSScriptRoot

# Normally supplied by the module. The script is also run directly -- by tests,
# by a user running the .ps1, by anything wanting -Help without importing -- so
# a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)NewGrowth - create a growth artifact" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)NewGrowth -Title <string> [-Type training|presentation|goal] [-Date YYYY-MM-DD]"
    Write-Host "              [-DueDate YYYY-MM-DD (required for a training)] [-Provider <string>]"
    Write-Host "              [-Hours <string>] [-Notes <string>]"
    Write-Host ""
    Write-Host "  PARAMETERS:" -ForegroundColor Yellow
    Write-Host "    -Type       training (default), presentation or goal"
    Write-Host "    -Title      course, talk or goal title (required)"
    Write-Host "    -Date       start date for a training, event date for a presentation (default: today)"
    Write-Host "    -DueDate    completion deadline -- required for a training"
    Write-Host "    -Provider   who delivers the training (training only)"
    Write-Host "    -Hours      total hours (training only)"
    Write-Host "    -Notes      one line of context, written into Description / Context / Why This Matters"
    Write-Host "    -Close      retire a growth item: move growth/current/<file> to growth/archive/ and stamp the date"
    Write-Host ""
    Write-Host "  EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    $($p)NewGrowth -Title 'Clean Architecture' -DueDate 2026-10-01 -Hours 8"
    Write-Host "    $($p)NewGrowth -Type presentation -Title 'Designing for Non-Determinism' -Date 2026-09-15"
    Write-Host "    $($p)NewGrowth -Type goal -Title 'Improve test coverage patterns'"
    Write-Host "    $($p)NewGrowth -Close training-2026-09-01-clean-architecture"
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

# -- Close ----------------------------------------------------------------------
if ($Close) {
    if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $growthRoot = Get-P20HubFolder -Name 'growth' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
    $growthCurrent = Join-Path $growthRoot 'current'
    $growthArchive = Join-Path $growthRoot 'archive'
    $wanted = [System.IO.Path]::GetFileName($Close)
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
        # Idempotent: already retired is a report, not an error -- the state is
        # where the file is, exactly as a card's and a session's are.
        if ((Test-Path $growthArchive) -and (Test-Path (Join-Path $growthArchive $wanted))) {
            Write-Host "Already closed: growth/archive/$wanted" -ForegroundColor DarkGray
            exit 0
        }
        Write-CliError -Message "No growth item matches '$Close' in growth/current/." `
            -Hint "Pass the file name as it appears under growth/current/."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($hits.Count -gt 1) {
        Write-CliError -Message "'$Close' matches $($hits.Count) growth items: $(($hits | ForEach-Object { $_.Name }) -join ', ')" `
            -Hint "Be more specific, or pass the full file name."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $source = $hits[0].FullName
    $dest = Join-Path $growthArchive $hits[0].Name
    if (Test-Path $dest) {
        Write-CliError -Message "growth/archive/$($hits[0].Name) already exists. Not overwriting it." `
            -Hint "The archived copy is the record. Compare the two and delete whichever is the duplicate."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
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

$currentDir = Join-Path (Get-P20HubFolder -Name 'growth' -PromptsRoot $promptsRoot -PackageRoot $repoRoot) 'current'
if (-not (Test-Path $currentDir)) {
    New-Item -Path $currentDir -ItemType Directory -Force | Out-Null
}
$filePath = Join-Path $currentDir $fileName

if (Test-Path $filePath) {
    Write-Host "Already there: $filePath" -ForegroundColor Yellow
    Write-Host "    FILE: $filePath"
    exit 0
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
# documented shape, because the parity test in Tests/test_growth.py compares
# these bytes with what POST /api/growth writes for the same inputs -- and a
# CRLF here would make the two disagree on a Windows machine only. The LF is
# -New's job now, not a -replace of this script's own: one writer, one rule.
#
Write-CardText -Path $filePath -Content ($content + "`n") -New

Write-Host "Created $fileName" -ForegroundColor Green
Write-Host "    FILE: $filePath"
exit 0
