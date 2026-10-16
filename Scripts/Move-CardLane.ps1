<#
.SYNOPSIS
    Moves a card to a lane by hand: In Progress, Code Review, or Done.
.DESCRIPTION
    Two writers per lane. Git's tokens move a card by themselves -- a commit
    bullet is In Progress, a PR URL: line is Code Review -- and for the card that
    has nothing checked in and no pull request, a person writes the line instead:

        Move <card> -To InProgress    writes  **Started:** <today>
        Move <card> -To CodeReview    writes  **Review:**  <today>
        Move <card> -To Done          archives it (the Archive verb, exactly)

    The state rule reads a person's line exactly as it reads git's; it does not
    care who wrote it. The board's drag-and-drop and "Move to" menu run this verb
    through the bridge, so the browser has no second implementation.

    A card travels one way. Moving backwards is refused: to take a card back,
    remove the line by hand -- on purpose, and knowing why.
.PARAMETER Card
    The card's ID, or its filename. An ID matches that id and no other. Only
    cards in current/ can be moved; a card in archive/ is Done.
.PARAMETER To
    InProgress, CodeReview or Done. The contract's words, with or without the
    space, in any case; the org's own lane names are display only.
.EXAMPLE
    {cliPrefix}Move K7M2 -To InProgress
    {cliPrefix}Move K7M2 -To CodeReview
    {cliPrefix}Move K7M2 -To Done
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [Parameter(Position = 1)]
    [string]$To,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Move <id|file> -To InProgress   Say you have started: writes **Started:** today" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To CodeReview   Say 'look at this': writes **Review:** today" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To Done         Archive it -- the same as ${p}Archive" -ForegroundColor Cyan
    Write-Host "  ${p}Move -Help                      Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  For a card with nothing checked in or no pull request. A commit or a PR" -ForegroundColor Gray
    Write-Host "  still moves a card by itself; this is the same move, written by you." -ForegroundColor Gray
    Write-Host "  A card travels one way: moving it back is refused." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')

$c = Get-P20Consts
$p = Get-CliPrefix

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a lane: '${p}Move <id> -To InProgress'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}

# The lane, from the contract's words -- typed with or without the space, in any case.
$lanes = @{
    ($c.status.inProgress -replace '\s', '').ToLowerInvariant() = $c.status.inProgress
    ($c.status.codeReview -replace '\s', '').ToLowerInvariant() = $c.status.codeReview
    ($c.status.done       -replace '\s', '').ToLowerInvariant() = $c.status.done
}
$key = ("$To" -replace '\s', '').ToLowerInvariant()
if (-not $To -or -not $lanes.ContainsKey($key)) {
    Write-CliError -Message "'$To' is not a lane a card can be moved to." `
        -Hint "-To InProgress, -To CodeReview, or -To Done. A card is $($c.status.active) from the moment it is made."
    exit 2  # stated refusal
}
$target = $lanes[$key]

$folders = Get-PromptFolders
$types = Get-P20WorkItemTypes -Config $cfg
$resolved = Resolve-P20CardArgument -Argument $Card -Folder $folders.Current -WorkItemTypes $types
$found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
if ($found.Count -eq 0) {
    if ($resolved.IsId) {
        Write-CliError -Message "No card with id '$Card' in current/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. A card in archive/ is already Done. Run '${p}Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/." -Hint "Run '${p}Status' to see the cards."
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
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

# Done is Archive, exactly -- one implementation, and its refusals are its own.
if ($target -eq $c.status.done) {
    & (Join-Path $PSScriptRoot 'Move-PromptToArchive.ps1') -File $file.Name
    exit $LASTEXITCODE
}

$text = [System.IO.File]::ReadAllText($file.FullName)
$now = Get-PromptFileStatus -Content $text
$order = @{ ($c.status.active) = 0; ($c.status.inProgress) = 1; ($c.status.codeReview) = 2 }
if ($now -eq $target) {
    Write-Host "$label is already $target -- nothing written." -ForegroundColor Gray
    exit 0
}
if ($order[$now] -gt $order[$target]) {
    Write-CliError -Message "$label is $now; a card travels one way and is not moved back to $target." `
        -Hint "To take it back on purpose, remove the line that put it there -- the commit bullet, the PR URL, or the $($c.stamps.started) / $($c.stamps.review) line -- by hand."
    exit 2  # stated refusal
}

$today = Get-Date -Format 'yyyy-MM-dd'
$stamp = if ($target -eq $c.status.inProgress) { $c.stamps.started } else { $c.stamps.review }
$changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Value $today
if ($changed) {
    Write-Host "[+] $label is $target -- wrote '$stamp $today' into $($file.Name)" -ForegroundColor Green
}
else {
    Write-Host "$label already carries '$stamp' -- nothing written." -ForegroundColor Gray
}
exit 0
