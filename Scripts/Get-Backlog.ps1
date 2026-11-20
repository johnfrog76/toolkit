<#
.SYNOPSIS
    The Backlog: the Space's waiting cards as one ranked table.
.DESCRIPTION
    Prints the cards in the active Space's backlog/ -- rank, id, type, milestone,
    tags, age and title -- in the Backlog's order, with each milestone's cards in
    play in their ranked place, marked 'in play', so the ranks read 1, 2, 3 (Scripts/Read-Backlog.ps1;
    docs/hub/milestones.md, "The Backlog: the order as a table"): milestone by
    milestone, ranked by the milestone's file, then the cards with no milestone.
    -Milestone, -Tag and -Type filter (AND, ignoring case); a filtered row keeps its
    rank, because the rank is the milestone's, not the table's.

    Read-only, and a folder read: it works offline and with no tracker. Plan -Rank
    moves a card in its milestone's order; Move <id> -To Active puts it in play.

    On an Azure DevOps Space there is no backlog in ToolKit -- the company's is in
    Azure DevOps, and a card there is work assigned to you -- so it refuses (exit 2)
    and names MyWork.
.PARAMETER Milestone
    Only the cards in this milestone, matched ignoring case.
.PARAMETER Tag
    Only the cards carrying this tag, matched ignoring case.
.PARAMETER Type
    Only the cards of this type -- Task, Bug, "User Story" (or UserStory) --
    matched ignoring case and spaces.
.PARAMETER Help
    Show usage.
.EXAMPLE
    {cliPrefix}Backlog
.EXAMPLE
    {cliPrefix}Backlog -Milestone "M2 -- 1.2.0" -Tag docs
.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [string]$Milestone,

    [string]$Tag,

    [string]$Type,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Backlog                          The Space's waiting cards, ranked" -ForegroundColor Cyan
    Write-Host "  ${p}Backlog -Milestone ""<title>""     Only the cards in one milestone" -ForegroundColor Cyan
    Write-Host "  ${p}Backlog -Tag <tag>               Only the cards carrying a tag" -ForegroundColor Cyan
    Write-Host "  ${p}Backlog -Type <type>             Only one type: Task, Bug, UserStory, ..." -ForegroundColor Cyan
    Write-Host "  ${p}Backlog -Help                    Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The cards in backlog/, milestone by milestone: milestones with an order file" -ForegroundColor Gray
    Write-Host "  first, by the day it was made, then the rest by title; inside one, its order." -ForegroundColor Gray
    Write-Host "  A milestone's cards in play sit in their place, marked 'in play'. Cards with" -ForegroundColor Gray
    Write-Host "  no milestone come last, oldest first. Rank is the place in the milestone's" -ForegroundColor Gray
    Write-Host "  order, the count '${p}Plan <id> -Rank' uses; a card the order does not list" -ForegroundColor Gray
    Write-Host "  yet has none. The filters go together and never change a rank." -ForegroundColor Gray
    Write-Host "  Read-only, and it works offline. On an Azure DevOps Space it refuses: the" -ForegroundColor Gray
    Write-Host "  backlog is the board's there, and '${p}MyWork' lists what is assigned to you." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')
. (Join-Path $PSScriptRoot 'Read-Backlog.ps1')

$p = Get-CliPrefix

if ((Resolve-P20Tracker -OrgUrl ([string]$cfg.Org)) -eq 'ado') {
    Write-CliError -Message "this Space's backlog is in Azure DevOps; ${p}MyWork lists what is assigned to you." `
        -Hint "A card on an Azure DevOps Space is work assigned to you, and lives in current/ until it is archived. '${p}Status' lists those cards."
    exit 2  # stated refusal
}

$folders = Get-PromptFolders
$spaceDir = Split-Path $folders.Current -Parent
$today = (Get-Date).ToString('yyyy-MM-dd')
# Not wrapped in @(): the reader returns its array whole, an empty one included.
$rows = Read-P20SpaceBacklog -SpaceDir $spaceDir -Today $today -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg) -Milestone $Milestone -Tag $Tag -Type $Type

$filters = @()
if ($Milestone) { $filters += "milestone '$Milestone'" }
if ($Tag) { $filters += "tag '$Tag'" }
if ($Type) { $filters += "type '$Type'" }
$scope = ''
if ($filters.Count -gt 0) { $scope = " -- " + ($filters -join ', ') }

Write-Host ""
if ($rows.Count -eq 0) {
    if ($filters.Count -gt 0) {
        Write-Host "  No card in backlog/ matches$scope." -ForegroundColor Gray
    }
    else {
        Write-Host "  backlog/ is empty: every card is in play or done." -ForegroundColor Gray
        Write-Host "  '${p}NewPrompt -Title ""...""' with no -Now puts a card there." -ForegroundColor Gray
    }
    Write-Host ""
    exit 0
}

function Format-Cell {
    # A cell at most $Width wide, cut with an ASCII '...' (5.1 consoles).
    param([string]$Text, [int]$Width)
    if ($Text.Length -le $Width) { return $Text }
    return $Text.Substring(0, $Width - 3) + '...'
}

$playing = @($rows | Where-Object { $_.InPlay }).Count
$waiting = $rows.Count - $playing
$noun = 'cards'
if ($waiting -eq 1) { $noun = 'card' }
$also = ''
if ($playing -gt 0) { $also = ", $playing in play" }
Write-Host "  Backlog -- $waiting $noun waiting$also$scope" -ForegroundColor Cyan
Write-Host ""
$cells = @($rows | ForEach-Object {
        $rank = ''
        if ($null -ne $_.Rank) { $rank = [string]$_.Rank }
        $age = ''
        if ($null -ne $_.Age) { $age = "$($_.Age)d" }
        $state = ''
        if ($_.InPlay) { $state = 'in play' }
        @{
            Rank      = $rank
            State     = $state
            Id        = [string]$_.Id
            Type      = Format-Cell ([string]$_.Type) 12
            Milestone = Format-Cell ([string]$_.Milestone) 24
            Tags      = Format-Cell (@($_.Tags) -join ', ') 20
            Age       = $age
            Title     = [string]$_.Title
        }
    })
$columns = @('Rank', 'State', 'Id', 'Type', 'Milestone', 'Tags', 'Age', 'Title')
$width = @{}
foreach ($col in $columns) {
    $width[$col] = $col.Length
    foreach ($c in $cells) { if ($c[$col].Length -gt $width[$col]) { $width[$col] = $c[$col].Length } }
}
$line = { param($c) '  ' + (($columns | ForEach-Object { if ($_ -eq 'Title') { $c[$_] } else { $c[$_].PadRight($width[$_]) } }) -join '  ') }
$header = @{}
foreach ($col in $columns) { $header[$col] = $col }
Write-Host (& $line $header) -ForegroundColor DarkGray
foreach ($c in $cells) { Write-Host (& $line $c) }
Write-Host ""
exit 0
