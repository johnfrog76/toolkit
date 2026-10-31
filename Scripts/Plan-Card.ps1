<#
.SYNOPSIS
    Plans a card into a milestone, a sprint, or both -- the write side of a card's two
    planning lines.
.DESCRIPTION
    A card carries its milestone and its sprint on two footer lines, each its own
    (docs/hub/cards.md, "Milestone and sprint: two lines"): `**Milestone:**` and
    `**Sprint:**`. -Milestone writes the first, -Sprint the second, through
    `Set-P20CardLine`: a line is replaced in place if the card already carries one, or
    inserted directly above `**Created:**` if not. A card can be in both at once.

    Before the two were separate, ONE `**Sprint:**` line held a sprint OR a milestone, and
    a card with no `**Milestone:**` line still reads its milestone from that line
    (Get-P20CardMilestone) -- files outlive their templates. So each write keeps the OTHER
    reading as it was:

      - -Milestone never touches the sprint line;
      - -Sprint on a card with no milestone line first writes one carrying the milestone
        the card read before -- its old sprint line's value, or `(none)` -- so setting a
        sprint never moves a card out of (or into) a milestone;
      - a write that leaves both readings as they were writes nothing.

    -Remove takes the card out of both, deleting both lines -- what -Remove always did
    to the one line. -Remove -Only Milestone or -Remove -Only Sprint takes it out of one
    and keeps the other reading as it was, by the same rule.

    Sprints and milestones are opt-in at every grain (AGENTS.md): no card is forced into
    one. The title is written WHOLE, verbatim -- never truncated. (The agent's card model
    shortens the sprint to ~20 characters for board display; that is a display-time
    shortening of what it reads, not something this verb does.)

    This is purely a LOCAL, card-side write. It never touches the tracker: the existing
    `-Sprint` switch on `NewItem` / `EditItem` is a different thing entirely -- it sets a
    milestone on the work item itself, through `gh` / `az`. This verb writes lines in one
    file and calls nothing else.

    A card is looked for in current/ and backlog/, and never pulled into play: a backlog
    card's whole value is being planned into a milestone BEFORE it is pulled into play, so
    this verb writes the lines exactly where the card already sits.
.PARAMETER Card
    The card's ID, or its filename. An ID matches that id and no other.
.PARAMETER Milestone
    The milestone title, written whole into `**Milestone:**`. Goes with -Sprint; not with
    -Remove.
.PARAMETER Sprint
    The sprint title, written whole into `**Sprint:**`. Goes with -Milestone; not with
    -Remove.
.PARAMETER Remove
    Take the card out of its milestone and its sprint -- both lines are deleted. With
    -Only, out of one of them.
.PARAMETER Only
    With -Remove: `Milestone` or `Sprint`, the one line to take the card out of.
.EXAMPLE
    {cliPrefix}Plan K7M2 -Milestone "M2 -- 1.2.0"
    {cliPrefix}Plan K7M2 -Sprint "Sprint 9"
    {cliPrefix}Plan K7M2 -Remove -Only Sprint
    {cliPrefix}Plan K7M2 -Remove
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [string]$Milestone,

    [string]$Sprint,

    [switch]$Remove,

    [string]$Only,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Plan <id|file> -Milestone ""<title>""   Plan the card into a milestone" -ForegroundColor Cyan
    Write-Host "  ${p}Plan <id|file> -Sprint ""<title>""      Put the card in a sprint (with -Milestone, both at once)" -ForegroundColor Cyan
    Write-Host "  ${p}Plan <id|file> -Remove                 Take it out of its milestone and its sprint" -ForegroundColor Cyan
    Write-Host "  ${p}Plan <id|file> -Remove -Only Sprint    Take it out of one (Milestone or Sprint), keep the other" -ForegroundColor Cyan
    Write-Host "  ${p}Plan -Help                             Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Writes the card's Milestone and Sprint footer lines, each its own, through" -ForegroundColor Gray
    Write-Host "  Set-P20CardLine. A card with no Milestone line reads its milestone from its" -ForegroundColor Gray
    Write-Host "  Sprint line, as it always did; -Sprint keeps that milestone on its own line." -ForegroundColor Gray
    Write-Host "  Titles are written whole, never truncated. This never touches the tracker --" -ForegroundColor Gray
    Write-Host "  NewItem / EditItem have their own -Sprint, which sets a milestone through gh / az." -ForegroundColor Gray
    Write-Host "  Found in current/ or backlog/, and never pulled into play: a backlog card is" -ForegroundColor Gray
    Write-Host "  planned into a milestone before it is ever pulled into play." -ForegroundColor Gray
    Write-Host ""
    return
}

$cfg = $global:P20Config
$promptsRoot = $cfg.PromptsRoot
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')

$p = Get-CliPrefix

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a milestone: '${p}Plan <id> -Milestone ""M2""'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}

$which = ''
if ($PSBoundParameters.ContainsKey('Only')) {
    if (-not $Remove) {
        Write-CliError -Message "'-Only' goes with '-Remove'." `
            -Hint "'${p}Plan <id> -Remove -Only Milestone' or '-Only Sprint' takes the card out of one of the two."
        exit 2  # stated refusal
    }
    $which = @('Milestone', 'Sprint') | Where-Object { $_ -ieq $Only } | Select-Object -First 1
    if (-not $which) {
        Write-CliError -Message "'-Only $Only' is not a line Plan writes." `
            -Hint "Pass '-Only Milestone' or '-Only Sprint'; '-Remove' alone takes the card out of both."
        exit 2  # stated refusal
    }
}

if (-not $Milestone -and -not $Sprint -and -not $Remove) {
    Write-CliError -Message "no milestone or sprint given." `
        -Hint "Pass '-Milestone ""<title>""' or '-Sprint ""<title>""' (or both) to plan the card, or '-Remove' to take it out of them."
    exit 2  # stated refusal
}
if (($Milestone -or $Sprint) -and $Remove) {
    Write-CliError -Message "'-Remove' and '-Milestone' / '-Sprint' do not go together." `
        -Hint "Plan the card into a milestone or a sprint, or take it out of one -- not both in the same call."
    exit 2  # stated refusal
}
$folders = Get-PromptFolders
$backlogDir = Get-P20BacklogFolder -Folders $folders
$types = Get-P20WorkItemTypes -Config $cfg

# current/ and backlog/: a card is planned into a milestone wherever it already sits -- a
# backlog card is never pulled into play by this verb, because being planned before being
# pulled into play is the whole point (AGENTS.md: a backlog card's value is being planned).
# -AllowPath: a card's full path is that card, whichever Space is active.
$resolved = Resolve-P20CardArgument -Argument $Card -Folder @($folders.Current, $backlogDir) -WorkItemTypes $types -AllowPath -PromptsRoot $promptsRoot
$found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
if ($found.Count -eq 0) {
    if ($resolved.IsId) {
        Write-CliError -Message "No card with id '$Card' in current/ or backlog/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. A card in archive/ is already Done. Run '${p}Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/ or backlog/." -Hint "Run '${p}Status' to see the cards."
    }
    exit 2  # stated refusal
}
if ($found.Count -gt 1) {
    Write-Host "Matches for '$Card':" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$Card' matches $($found.Count) cards." -Hint "Pass the full filename of the one you mean."
    exit 2  # stated refusal
}

$file = $found[0]
$c = Get-P20Consts
$milestoneStamp = [string]$c.stamps.milestone
$sprintStamp = [string]$c.stamps.sprint
# What a milestone line says when the card is in no milestone and its sprint line must
# not be read as one -- a placeholder, which every reader reads as none.
$noMilestone = '(none)'
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

function Read-PlanState {
    # The card's two readings now, and whether it carries its own milestone line.
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    return @{
        Milestone    = (Get-P20CardMilestone $text)
        Sprint       = (Get-P20CardSprint $text)
        HasMilestone = (Get-P20CardLineValue -Content $text -Stamp $milestoneStamp).Present
        HasSprint    = (Get-P20CardLineValue -Content $text -Stamp $sprintStamp).Present
    }
}

$changed = $false
$state = Read-PlanState $file.FullName

if ($Remove) {
    if (-not $which) {
        # Out of both: the two lines go, as the one line always went.
        if (Set-P20CardLine -Path $file.FullName -Stamp $sprintStamp -Remove) { $changed = $true }
        if (Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Remove) { $changed = $true }
        if ($changed) { Write-Host "[+] $label is out of its milestone and sprint. ($($file.Name))" -ForegroundColor Green }
        else { Write-Host "$label carries no milestone or sprint -- nothing written." -ForegroundColor Gray }
    }
    elseif ($which -eq 'Milestone') {
        if ($state.Milestone) {
            # A sprint line stays, and must not be read as the milestone: a placeholder
            # line says none. With no sprint either, the line simply goes.
            if ($state.Sprint) { $changed = Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Value $noMilestone }
            else { $changed = Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Remove }
        }
        if ($changed) { Write-Host "[+] $label is out of its milestone. ($($file.Name))" -ForegroundColor Green }
        else { Write-Host "$label carries no milestone -- nothing written." -ForegroundColor Gray }
    }
    else {
        if ($state.HasSprint) {
            # The milestone an old card read from this line stays, on its own line.
            if (-not $state.HasMilestone -and $state.Milestone) {
                [void](Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Value $state.Milestone)
            }
            $changed = Set-P20CardLine -Path $file.FullName -Stamp $sprintStamp -Remove
            # A placeholder milestone line was only there to keep the sprint line from
            # reading as a milestone; with the sprint gone, it goes too.
            $after = Read-PlanState $file.FullName
            if ($after.HasMilestone -and -not $after.Milestone) {
                [void](Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Remove)
            }
        }
        if ($changed) { Write-Host "[+] $label is out of its sprint. ($($file.Name))" -ForegroundColor Green }
        else { Write-Host "$label carries no sprint -- nothing written." -ForegroundColor Gray }
    }
    exit 0
}

if ($Milestone) {
    if ($state.Milestone -ceq $Milestone) {
        Write-Host "$label is already planned into $Milestone -- nothing written." -ForegroundColor Gray
    }
    else {
        [void](Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Value $Milestone)
        Write-Host "[+] $label is planned into $Milestone. ($($file.Name))" -ForegroundColor Green
    }
    $state = Read-PlanState $file.FullName
}
if ($Sprint) {
    if ($state.Sprint -ceq $Sprint) {
        Write-Host "$label is already in sprint $Sprint -- nothing written." -ForegroundColor Gray
    }
    else {
        # A card with no milestone line reads its milestone from the sprint line: keep
        # what it read on a line of its own before the sprint line changes under it.
        if (-not $state.HasMilestone -and $state.Milestone -cne $Sprint) {
            $keep = $state.Milestone
            if (-not $keep) { $keep = $noMilestone }
            [void](Set-P20CardLine -Path $file.FullName -Stamp $milestoneStamp -Value $keep)
        }
        [void](Set-P20CardLine -Path $file.FullName -Stamp $sprintStamp -Value $Sprint)
        Write-Host "[+] $label is in sprint $Sprint. ($($file.Name))" -ForegroundColor Green
    }
}
exit 0
