<#
.SYNOPSIS
    Reminders -- the ledger of what you owe yourself, and the things you do to one.

.DESCRIPTION
    The Organize add-on's second verb, MeetingAgenda's shape: one verb, switches.

      Reminders                       every open reminder, grouped by its derived
                                      bucket -- overdue, today, upcoming -- the way
                                      Status reads cards. -All adds the archived.
      Reminders <id> -Snooze <word>   rewrites **Due:** and nothing else: the id, the
                                      file and the origin stay. 1h | tomorrow | nextweek.
      Reminders <id> -Archive         moves the file to reminders/archive/ and stamps
                                      **Closed:** through the one shared writer.
      Reminders <id> -Due <when> | -NoDue | -Title <t> | -Source <tag> | -Ref <ref>
                                      corrects the entry: each rewrites its own line
                                      and nothing else, and any may go together. -Due
                                      takes what NewReminder -Due takes, so -Snooze
                                      <word> is a shortcut for -Due <word>. The
                                      filename keeps its slug: the id is the identity.

    <id> is read by the ONE id rule (Resolve-P20CardArgument): an argument shaped
    like an id matches that id and nothing else, never as a substring. A partial
    name is refused rather than guessed at. Archive is not taught this folder --
    it is org-scoped, and a module closes its own data.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Id,
    [Parameter(Mandatory = $false)]
    [string]$Snooze,
    [Parameter(Mandatory = $false)]
    [switch]$Archive,
    [Parameter(Mandatory = $false)]
    [string]$Due,
    [Parameter(Mandatory = $false)]
    [switch]$NoDue,
    [Parameter(Mandatory = $false)]
    [string]$Title,
    [Parameter(Mandatory = $false)]
    [string]$Source,
    [Parameter(Mandatory = $false)]
    [string]$Ref,
    [Parameter(Mandatory = $false)]
    [switch]$All,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}
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
    Write-Host "  ${p}Reminders -- what you owe yourself" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}Reminders [-All]"
    Write-Host "    ${p}Reminders <id> -Snooze 1h|tomorrow|nextweek"
    Write-Host "    ${p}Reminders <id> -Archive"
    Write-Host "    ${p}Reminders <id> [-Due <when> | -NoDue] [-Title <text>] [-Source <tag>] [-Ref <ref>]"
    Write-Host ""
    Write-Host "  The list is grouped overdue / today / upcoming, worked out against the"
    Write-Host "  local clock each time. A snooze rewrites the due time and nothing else;"
    Write-Host "  an edit rewrites the lines it names and nothing else."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
. (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')
. (Join-Path $PSScriptRoot 'Reminder-Rules.ps1')
$consts = Get-P20Consts
$p = Get-CliPrefix

$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$remindersDir = Get-P20HubFolder -Name 'reminders' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
$folderName = [System.IO.Path]::GetFileName($remindersDir)
$currentDir = Join-Path $remindersDir $consts.folders.current
$archiveDir = Join-Path $remindersDir $consts.folders.archive
$now = Get-Date

# An edit is any of the five correcting switches, and it is BOUND that counts:
# `-Title ""` is a question (refused below), not an absent switch.
$editKeys = @('Due', 'NoDue', 'Title', 'Source', 'Ref')
$editing = @($editKeys | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0

# -- A switch with no id, or an id with no switch, is a question we cannot answer --
if (($Snooze -or $Archive -or $editing) -and -not $Id) {
    Write-CliError -Message 'Which reminder? -Snooze, -Archive and an edit need its id.' -Hint "${p}Reminders lists them with their ids."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Id -and -not $Snooze -and -not $Archive -and -not $editing) {
    Write-CliError -Message "Nothing to do to '$Id'." -Hint "${p}Reminders $Id -Snooze tomorrow, ${p}Reminders $Id -Due 2026-10-01T14:00, or ${p}Reminders $Id -Archive."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Snooze -and $Archive) {
    Write-CliError -Message 'Snooze or archive, not both.' -Hint 'A snoozed reminder is still open; an archived one is done.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($editing -and $Archive) {
    Write-CliError -Message 'Edit or archive, not both.' -Hint "Correct it first, then ${p}Reminders $Id -Archive -- an archived reminder is done."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Snooze -and ($PSBoundParameters.ContainsKey('Due') -or $NoDue)) {
    Write-CliError -Message '-Snooze and -Due both set the due time.' -Hint "-Snooze $Snooze is -Due $Snooze; pass one."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($PSBoundParameters.ContainsKey('Due') -and $NoDue) {
    Write-CliError -Message '-Due and -NoDue, not both.' -Hint '-NoDue removes the due time; -Due sets one.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Every value an edit carries is checked BEFORE anything is written ----------
$newDueValue = $null
if ($PSBoundParameters.ContainsKey('Due')) {
    $newDueValue = ConvertTo-P20DueValue -Text $Due -Now $now
    if (-not $newDueValue) {
        Write-CliError -Message "'$Due' is not a due date." `
            -Hint "-Due takes YYYY-MM-DD, YYYY-MM-DDTHH:MM, or one of: $(@($consts.reminders.snooze) -join ', '). -NoDue removes it."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
if ($PSBoundParameters.ContainsKey('Title')) {
    $Title = ($Title -replace "\r?\n", ' ').Trim()
    if (-not $Title) {
        Write-CliError -Message 'A reminder needs a title.' -Hint "${p}Reminders $Id -Title 'Review sprint goals'"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
if ($PSBoundParameters.ContainsKey('Source')) {
    $Source = ($Source -replace "\r?\n", ' ').Trim()
    if (-not $Source) {
        Write-CliError -Message 'A reminder needs a source.' -Hint '-Source manual is what NewReminder writes when none is given.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
if ($PSBoundParameters.ContainsKey('Ref')) { $Ref = ($Ref -replace "\r?\n", ' ').Trim() }

# -- One reminder: snooze or archive --------------------------------------------
if ($Id) {
    $resolved = Resolve-P20CardArgument -Argument $Id -Folder $currentDir -WorkItemTypes @{}
    $hits = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
    if ($resolved.Fuzzy) {
        Write-CliError -Message "'$Id' is not a reminder id; it matches $($hits.Count) by partial name." `
            -Hint "Pass the id ${p}Reminders shows (four characters, like K7M2)."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($hits.Count -eq 0) {
        $archivedAlready = @()
        if (Test-Path $archiveDir) {
            $archivedAlready = @((Resolve-P20CardArgument -Argument $Id -Folder $archiveDir -WorkItemTypes @{}).Match)
        }
        if ($archivedAlready.Count -gt 0 -and $Archive) {
            # Idempotent: already done is a report, not an error.
            Write-Host "Already archived: $folderName/$($consts.folders.archive)/$($archivedAlready[0].Name)" -ForegroundColor DarkGray
            exit 0
        }
        $hint = "${p}Reminders lists the open ones."
        if ($archivedAlready.Count -gt 0) { $hint = "It is archived ($($archivedAlready[0].Name)); an archived reminder is done." }
        Write-CliError -Message "No open reminder with id '$Id'." -Hint $hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($hits.Count -gt 1) {
        Write-CliError -Message "'$Id' matches $($hits.Count) reminders: $(($hits | ForEach-Object { $_.Name }) -join ', ')" `
            -Hint 'Two files carry one id -- rename or archive one by hand.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $file = $hits[0]

    if ($Snooze) {
        $newDue = Get-P20SnoozeDue -Word $Snooze -Now $now
        if (-not $newDue) {
            Write-CliError -Message "'$Snooze' is not a snooze." -Hint "-Snooze takes one of: $(@($consts.reminders.snooze) -join ', ')."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        # **Due:** and nothing else: same id, same file, same origin.
        $null = Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.due -Value $newDue
        $bucket = Get-P20ReminderBucket -Due $newDue -Now $now
        Write-Host "Snoozed $($file.Name): due $newDue ($bucket)." -ForegroundColor Green
        exit 0
    }

    if ($editing) {
        # Each switch rewrites its own line and nothing else; an unchanged value
        # writes nothing, so the file's modified time only moves for a change.
        $changed = @()
        if ($null -ne $newDueValue) {
            if (Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.due -Value $newDueValue) { $changed += "due $newDueValue" }
        }
        if ($NoDue) {
            if (Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.due -Remove) { $changed += 'no due date' }
        }
        if ($PSBoundParameters.ContainsKey('Title')) {
            if (Set-P20ReminderTitle -Path $file.FullName -Title $Title) { $changed += "title '$Title'" }
        }
        if ($PSBoundParameters.ContainsKey('Source')) {
            if (Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.source -Value $Source) { $changed += "source $Source" }
        }
        if ($PSBoundParameters.ContainsKey('Ref')) {
            # An empty -Ref removes the line: a ref is optional, a source is not.
            if ($Ref) {
                if (Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.ref -Value $Ref) { $changed += "ref $Ref" }
            }
            elseif (Set-P20CardLine -Path $file.FullName -Stamp $consts.stamps.ref -Remove) { $changed += 'no ref' }
        }
        if ($changed.Count -eq 0) {
            Write-Host "[=] Unchanged: $($file.Name) already says that." -ForegroundColor DarkGray
            exit 0
        }
        $after = Read-P20Reminder -File (Get-Item -LiteralPath $file.FullName)
        $bucket = Get-P20ReminderBucket -Due $after.Due -Now $now
        Write-Host "Updated $($file.Name): $($changed -join '; ') ($bucket)." -ForegroundColor Green
        exit 0
    }

    # -Archive
    if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }
    $dest = Join-Path $archiveDir $file.Name
    if (Test-Path $dest) {
        Write-CliError -Message "$folderName/$($consts.folders.archive)/$($file.Name) already exists. Not overwriting it." `
            -Hint 'The archived copy is the record. Compare the two and delete whichever is the duplicate.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Move-Item -LiteralPath $file.FullName -Destination $dest -ErrorAction Stop
    # Stamped AFTER the move: the move is the promise, the stamp the record.
    Add-ClosedDate -Path $dest
    Write-Host "Archived: $folderName/$($consts.folders.archive)/$($file.Name)" -ForegroundColor Green
    exit 0
}

# -- The ledger ------------------------------------------------------------------
$open = @()
if (Test-Path $currentDir) {
    $open = @(Get-ChildItem -LiteralPath $currentDir -Filter '*.md' -File | ForEach-Object { Read-P20Reminder -File $_ })
}
$order = @($consts.reminders.buckets)
foreach ($r in $open) { $r.Bucket = Get-P20ReminderBucket -Due $r.Due -Now $now }

Write-Host ""
if ($open.Count -eq 0) {
    Write-Host "  No open reminders." -ForegroundColor DarkGray
    Write-Host "  ${p}NewReminder -Title ""..."" -Due tomorrow adds one." -ForegroundColor DarkGray
}
foreach ($bucket in $order) {
    $rows = @($open | Where-Object { $_.Bucket -eq $bucket } | Sort-Object @{ Expression = { if ($_.Due) { $_.Due } else { '9999' } } }, @{ Expression = { $_.Title } })
    if ($rows.Count -eq 0) { continue }
    $colour = 'Gray'
    if ($bucket -eq $order[0]) { $colour = 'Red' } elseif ($bucket -eq $order[1]) { $colour = 'Yellow' }
    Write-Host ("  {0} ({1})" -f $bucket.ToUpperInvariant(), $rows.Count) -ForegroundColor $colour
    foreach ($r in $rows) {
        $when = '-'
        if ($r.Due) { $when = $r.Due -replace 'T', ' ' }
        $tag = $r.Source
        if ($r.Ref) { $tag = "$tag $($r.Ref)" }
        Write-Host ("    {0,-5} {1,-16} {2}  [{3}]" -f $r.Id, $when, $r.Title, $tag)
    }
    Write-Host ""
}
if ($All) {
    $done = @()
    if (Test-Path $archiveDir) {
        $done = @(Get-ChildItem -LiteralPath $archiveDir -Filter '*.md' -File | ForEach-Object { Read-P20Reminder -File $_ })
    }
    Write-Host ("  ARCHIVED ({0})" -f $done.Count) -ForegroundColor DarkGray
    foreach ($r in ($done | Sort-Object @{ Expression = { $_.Closed }; Descending = $true })) {
        Write-Host ("    {0,-5} closed {1,-10} {2}" -f $r.Id, $r.Closed, $r.Title) -ForegroundColor DarkGray
    }
    Write-Host ""
}
exit 0
