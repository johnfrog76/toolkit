<#
.SYNOPSIS
    Plans a card into a sprint or milestone -- the write side of the Sprint token.
.DESCRIPTION
    A card's `**Sprint:**` footer line has always been read -- the board's sprint filter and
    the card's own tag -- but the only writer was a hand editing the file, or `NewPrompt` at
    birth from a work item's iteration path. This verb writes it on a card that already
    exists, through `Set-P20CardLine`: the line is replaced in place if the card already
    carries one, or inserted directly above `**Created:**` if not.

    Sprints are opt-in at every grain (AGENTS.md): no card is forced into one, and no verb
    here ever requires a card to carry one to proceed. The title is written WHOLE, verbatim --
    never truncated. (The agent's card model shortens it to ~20 characters for board display;
    that is a display-time shortening of what it reads, not something this verb does.)

    This is purely a LOCAL, card-side write. It never touches the tracker: the existing
    `-Sprint` switch on `NewItem` / `EditItem` is a different thing entirely -- it sets a
    milestone on the work item itself, through `gh` / `az`. This verb writes one line in one
    file and calls nothing else.

    A card is looked for in current/ and backlog/, and never pulled into play: a backlog
    card's whole value is being planned into a milestone BEFORE it is pulled into play, so
    this verb writes the line exactly where the card already sits.
.PARAMETER Card
    The card's ID, or its filename. An ID matches that id and no other.
.PARAMETER Milestone
    The sprint or milestone title, written whole into `**Sprint:**`. Mutually exclusive with
    -Remove.
.PARAMETER Remove
    Take the card out of whatever sprint it carries -- the line is deleted. Mutually
    exclusive with -Milestone.
.EXAMPLE
    {cliPrefix}Plan K7M2 -Milestone "M2 -- 1.2.0"
    {cliPrefix}Plan K7M2 -Remove
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [string]$Milestone,

    [switch]$Remove,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Plan <id|file> -Milestone ""<title>""   Plan the card into a sprint or milestone" -ForegroundColor Cyan
    Write-Host "  ${p}Plan <id|file> -Remove                 Take it out of whatever sprint it carries" -ForegroundColor Cyan
    Write-Host "  ${p}Plan -Help                             Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Writes the card's **Sprint:** footer line, through Set-P20CardLine. The title is" -ForegroundColor Gray
    Write-Host "  written whole, never truncated. This never touches the tracker -- NewItem / EditItem" -ForegroundColor Gray
    Write-Host "  have their own -Sprint, which sets a milestone through gh / az." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')

$p = Get-CliPrefix

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a milestone: '${p}Plan <id> -Milestone ""M2""'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}

if (-not $Milestone -and -not $Remove) {
    Write-CliError -Message "no milestone given." `
        -Hint "Pass '-Milestone ""<title>""' to plan the card into it, or '-Remove' to take it out of whatever sprint it carries."
    exit 2  # stated refusal
}
if ($Milestone -and $Remove) {
    Write-CliError -Message "'-Milestone' and '-Remove' do not go together." `
        -Hint "Plan the card into a milestone, or take it out of one -- not both in the same call."
    exit 2  # stated refusal
}

$folders = Get-PromptFolders
$backlogDir = Get-P20BacklogFolder -Folders $folders
$types = Get-P20WorkItemTypes -Config $cfg

# current/ and backlog/: a card is planned into a milestone wherever it already sits -- a
# backlog card is never pulled into play by this verb, because being planned before being
# pulled into play is the whole point (AGENTS.md: a backlog card's value is being planned).
# -AllowPath: a card's full path is that card, whichever Space is active.
$resolved = Resolve-P20CardArgument -Argument $Card -Folder @($folders.Current, $backlogDir) -WorkItemTypes $types -AllowPath
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
$stamp = '**Sprint:**'
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

if ($Remove) {
    $changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Remove
    if ($changed) {
        Write-Host "[+] $label is out of its sprint. ($($file.Name))" -ForegroundColor Green
    }
    else {
        Write-Host "$label carries no sprint -- nothing written." -ForegroundColor Gray
    }
}
else {
    $changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Value $Milestone
    if ($changed) {
        Write-Host "[+] $label is planned into $Milestone. ($($file.Name))" -ForegroundColor Green
    }
    else {
        Write-Host "$label is already planned into $Milestone -- nothing written." -ForegroundColor Gray
    }
}
exit 0
