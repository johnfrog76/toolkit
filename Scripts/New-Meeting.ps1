<#
.SYNOPSIS
    Create a 1:1 session file in the hub from the ManagerSession template.
.DESCRIPTION
    Scaffolds <promptsRoot>/manager/current/YYYY-MM-DD.md. Defaults to today.
    The folder is named by the hub -- hub.json's folders.manager, default
    'manager'.
    Existing file for that date: reports it and stops, never overwrites -- a
    session file accumulates a meeting's whole record and re-scaffolding it
    would throw that away.

    The template ships with the toolkit (templates/ManagerSession.template.md),
    not with the hub. The hub holds sessions; the tool holds the shape of one.
.EXAMPLE
    {cliPrefix}NewMeeting
.EXAMPLE
    {cliPrefix}NewMeeting -Date <yyyy-mm-dd>
.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Date,

    # The series -- which recurring meeting. The 1:1 is the default and needs none;
    # any other name goes in front of the date in the filename (docs/hub/manager.md, "Where it lives").
    [Parameter(Mandatory = $false)]
    [string]$Type = '1on1',

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}NewMeeting -- create a 1:1 session file" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}NewMeeting [-Date YYYY-MM-DD] [-Type <series>] [-Help]"
    Write-Host ""
    Write-Host "  Writes manager/current/<date>.md in the hub from the shipped"
    Write-Host "  ManagerSession template. Defaults to today. Never overwrites."
    Write-Host ""
    return
}

# -- The hub ---------------------------------------------------------------------
# manager/ is a sibling of the per-org folders, not nested in any one of them:
# a 1:1 history spans engagements and does not reset when the active Space does.
# Test-P20HubRoot, the one "hub not found" sentence and the one hub resolver all
# live here, and this file is dot-sourced rather than reached through the module
# because this script also runs with no module in the session (a test sandbox,
# `pwsh -File`).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
# Get-P20PromptsRoot, not a re-derivation: PROMPTS_ROOT wins over config. This
# script treated the env var as a FALLBACK, so with both set it
# wrote sessions into the configured store while the agent read the overridden
# one.
$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM-dd') }
if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-Error "Invalid date '$Date' -- expected YYYY-MM-DD."
    return
}

# The hub-root folder's NAME is the hub's, not this script's: hub.json's
# "folders" block can rename manager/. Resolve-HubConfig.ps1 is the single reader
# of that, dot-sourced above.
$managerFolder = (Get-P20HubFolderNames -PromptsRoot $promptsRoot)['manager']
$managerRoot = Join-Path $promptsRoot $managerFolder
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-Consts.ps1') }
$currentDir = Join-Path $managerRoot ([string](Get-P20Consts).folders.current)
$archiveDir = Join-Path $managerRoot ([string](Get-P20Consts).folders.archive)
foreach ($dir in @($currentDir, $archiveDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

$defaultSeries = '1on1'
if ($Type -ne $defaultSeries -and $Type -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Write-CliError -Message "'$Type' is not a series name." `
        -Hint "Lower-case letters, digits and dashes: client-weekly, team-sync. The 1:1 needs no -Type."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$isDefaultSeries = ($Type -eq $defaultSeries)
# The record's name comes from the one builder beside the contract's parser, so
# the name written here and the name -Plan reads back are one rule.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CarriedFrom.ps1')
$fileName = New-P20SessionFileName -Series $Type -Date $Date
$filePath = Join-Path $currentDir $fileName

if (Test-Path $filePath) {
    Write-Host "Session for $Date already exists: $managerFolder/current/$fileName" -ForegroundColor Yellow
    Write-Host "    FILE: $filePath"
    return
}

# The session DATE is the file's identity (docs/hub/manager.md), so "already
# exists" means either folder. Checking only current/ scaffolded a blank session
# beside a real, closed one in archive/: the 1:1s page then listed an open
# meeting that had already been held, MeetingAgenda -Close could protect the
# archived copy but not remove the duplicate, and nothing but a hand delete
# resolved it.
$archivedPath = Join-Path $archiveDir $fileName
if (Test-Path $archivedPath) {
    Write-CliError -Message "A session for $Date is already closed: $managerFolder/archive/$fileName" `
        -Hint "Read it at $archivedPath, or pick another date. A closed session is the record; it is not reopened."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# One writer for every file this package puts in the user's hub -- see
# Scripts/Write-CardText.ps1 for the contract and why it is a dot-source.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

# -- Prior session ---------------------------------------------------------------
# The template carries a "Carried from" heading; filling in which session it
# carries from is what lets the next stage find the thread without being told.
# ... in THIS series: a client weekly never carries from the 1:1. The name rule
# is the contract's (consts.json regex.sessionName).
$nameRx = (Get-P20Consts).regex.sessionName
$allSessions = @()
foreach ($dir in @($currentDir, $archiveDir)) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem -Path $dir -Filter '*.md' -File)) {
        $m = [regex]::Match($f.Name, $nameRx)
        if (-not $m.Success) { continue }
        $series = if ($m.Groups[1].Success -and $m.Groups[1].Value) { $m.Groups[1].Value } else { $defaultSeries }
        if ($series -eq $Type -and $m.Groups[2].Value -lt $Date) { $allSessions += $m.Groups[2].Value }
    }
}
$priorDate = ($allSessions | Sort-Object -Descending | Select-Object -First 1)
if (-not $priorDate) { $priorDate = '(none)' }

$templatePath = Join-Path (Join-Path $repoRoot 'templates') 'ManagerSession.template.md'
if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $templatePath"
    return
}

$content = Get-Content -Path $templatePath -Raw -Encoding UTF8
$content = $content -replace '^# \{\{DATE\}\}', ('# ' + $(if ($isDefaultSeries) { $Date } else { "$Type $Date" }))
$content = $content -replace '\{\{DATE\}\}', $Date
$content = $content -replace '\{\{PRIOR_DATE\}\}', $priorDate

# -- The session after it --------------------------------------------------------
# A session created for an earlier date sits in front of a later one, whose
# "## Carried from" heading still names what came before. Say so, and change
# nothing: the heading is that session's record (docs/hub/manager.md, "Which
# session a record carries from"). Asked before the write, with this session
# named as the one about to exist.
$nextNote = ''
$nextPath = Get-P20NextSessionPath -Series $Type -Date $Date -Folders @($currentDir, $archiveDir)
if ($nextPath) {
    $nextNote = Format-P20CarriedFromNote (Get-P20CarriedFromCheck -Path $nextPath -Folders @($currentDir, $archiveDir) -Also @($fileName))
}

# The one writer, and the BOM half of the card contract: UTF-8 with NO BOM. It
# used to write one, which MeetingAgenda -Close then stripped on its
# way past -- a session whose first three bytes depended on which verb touched
# it last, and a whole-file diff on a hub with storeSync: git.
#
# -New is the LINE-ENDING half: this CREATES the session, and a created file is
# LF on every host. It used to copy the template byte for byte, which made the
# session CRLF on a Windows clone (`* text=auto` plus core.autocrlf checks the
# template out CRLF) and LF on macOS -- one hub, two byte shapes, by machine.
# The writer normalises; nothing here does. See Scripts/Write-CardText.ps1.
Write-CardText -Path $filePath -Content $content -New

Write-Host "Created $managerFolder/current/$fileName" -ForegroundColor Green
Write-Host "    FILE: $filePath"
if ($nextNote) { Write-Host "    Check: $(Split-Path $nextPath -Leaf) -- $nextNote" -ForegroundColor Yellow }
Write-Host "    Next: $(Get-CliPrefix)MeetingAgenda -Plan" -ForegroundColor DarkGray
