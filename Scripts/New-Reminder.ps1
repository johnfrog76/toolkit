<#
.SYNOPSIS
    NewReminder -- create one reminder in the hub (the Organize add-on).

.DESCRIPTION
    Writes <promptsRoot>/reminders/current/<ID>-<slug>.md: an H1 title and the
    house footer -- **Due:**, **Source:**, **Ref:**, **Created:**. The id is a
    fresh short id (K7M2), the one a card with no work item gets, unique across
    reminders/current/ and reminders/archive/. The folder is the hub's to name
    (hub.json folders.reminders, default 'reminders').

    Never overwrites: an existing file is a stated refusal, as every creator here.
    Nothing derived is written -- overdue and the bucket are worked out at read time.

.EXAMPLE
    {cliPrefix}NewReminder -Title "Review sprint goals" -Due <yyyy-mm-ddThh:mm>
.EXAMPLE
    {cliPrefix}NewReminder -Title "Book the training" -Due tomorrow -Source goal

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Title,
    [Parameter(Mandatory = $false)]
    [string]$Due,
    [Parameter(Mandatory = $false)]
    [string]$Source,
    [Parameter(Mandatory = $false)]
    [string]$Ref,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}NewReminder -- create a reminder" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}NewReminder -Title <text> [-Due <when>] [-Source <where>] [-Ref <ref>]"
    Write-Host ""
    Write-Host "  -Due takes YYYY-MM-DD, YYYY-MM-DDTHH:MM, or 1h / tomorrow / nextweek."
    Write-Host "  -Source is where it came from (a tag; default manual); -Ref a pointer in it."
    Write-Host "  Writes reminders/current/<ID>-<slug>.md in the hub. Never overwrites."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Reminder-Rules.ps1')
$consts = Get-P20Consts

if (-not $Title -or -not $Title.Trim()) {
    Write-CliError -Message 'A reminder needs a title.' -Hint "$(Get-CliPrefix)NewReminder -Title ""Review sprint goals"" -Due tomorrow"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$Title = ($Title -replace "\r?\n", ' ').Trim()

$now = Get-Date
$dueValue = ''
if ($Due) {
    $dueValue = ConvertTo-P20DueValue -Text $Due -Now $now
    if (-not $dueValue) {
        Write-CliError -Message "'$Due' is not a due date." `
            -Hint "-Due takes YYYY-MM-DD, YYYY-MM-DDTHH:MM, or one of: $(@($consts.reminders.snooze) -join ', ')."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
if (-not $Source) { $Source = 'manual' }
$Source = ($Source -replace "\r?\n", ' ').Trim()

$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$remindersDir = Get-P20HubFolder -Name 'reminders' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
$currentDir = Join-Path $remindersDir $consts.folders.current
$archiveDir = Join-Path $remindersDir $consts.folders.archive
if (-not (Test-Path $currentDir)) { New-Item -ItemType Directory -Path $currentDir -Force | Out-Null }

$id = New-P20CardId -Folders @($currentDir, $archiveDir) -WorkItemTypes @{}
if (-not $id) {
    Write-CliError -Message 'Could not find a free reminder id after 50 tries.' -Hint 'Archive some reminders, or try again.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$fileName = "$id-$(ConvertTo-P20ReminderSlug $Title).md"
$filePath = Join-Path $currentDir $fileName
if (Test-Path $filePath) {
    Write-CliError -Message "reminders/current/$fileName already exists. Not overwriting it." -Hint 'Run it again: the id is drawn fresh each time.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$lines = @("# $Title", '', '---', '')
if ($dueValue) { $lines += "$($consts.stamps.due) $dueValue" }
$lines += "$($consts.stamps.source) $Source"
if ($Ref) { $lines += "$($consts.stamps.ref) $(($Ref -replace "\r?\n", ' ').Trim())" }
$lines += "$($consts.stamps.created) $($now.ToString('yyyy-MM-dd'))"
Write-CardText -Path $filePath -Content (($lines -join "`n") + "`n") -New

$bucket = Get-P20ReminderBucket -Due $dueValue -Now $now
$when = 'no due date'
if ($dueValue) { $when = "due $dueValue" }
Write-Host "Created reminder $id ($bucket, $when): $([System.IO.Path]::GetFileName($remindersDir))/$($consts.folders.current)/$fileName" -ForegroundColor Green
exit 0
