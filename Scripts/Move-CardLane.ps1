<#
.SYNOPSIS
    Moves a card to a lane by hand: Backlog, Active, In Progress, Code Review, or Done.
.DESCRIPTION
    Two writers per lane. Git's tokens move a card by themselves -- a commit
    bullet is In Progress, a PR URL: line is Code Review -- and for the card that
    has nothing checked in and no pull request, a person writes the line instead:

        Move <card> -To InProgress    writes  **Started:** <today>
        Move <card> -To CodeReview    writes  **Review:**  <today>
        Move <card> -To Done          archives it (the Archive verb, exactly)

    Two lanes are FOLDERS, and moving to them moves the file (a rename; the
    card's bytes are not touched):

        Move <card> -To Backlog       current/ -> backlog/: planned, not in play
        Move <card> -To Active        backlog/ -> current/: pulled into play

    A card in backlog/ is pulled into current/ by -To InProgress and -To
    CodeReview too, BEFORE the line is written -- a backlog card never carries a
    commit bullet, a PR URL, **Started:** or **Review:** (Scripts/Move-CardFolder.ps1).

    The state rule reads a person's line exactly as it reads git's; it does not
    care who wrote it. The board's drag-and-drop and "Move to" menu run this verb
    through the bridge, so the browser has no second implementation.

    A card travels one way. Moving backwards is refused: to take a card back,
    remove the line by hand -- on purpose, and knowing why. The one way back is
    Active -> Backlog, and only for a card with nothing threaded: unfinished work
    is not backlog, it is in play.
.PARAMETER Card
    The card's ID, or its filename. An ID matches that id and no other. Cards in
    current/ and backlog/ can be moved; a card in archive/ is Done.
.PARAMETER To
    Backlog, Active, InProgress, CodeReview or Done. The contract's words, with
    or without the space, in any case; the org's own lane names are display only.
.EXAMPLE
    {cliPrefix}Move K7M2 -To Active
    {cliPrefix}Move K7M2 -To Backlog
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
    Write-Host "  ${p}Move <id|file> -To Active       Pull a card from backlog/ into play (current/)" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To Backlog      Park a card with nothing threaded: current/ -> backlog/" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To InProgress   Say you have started: writes **Started:** today" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To CodeReview   Say 'look at this': writes **Review:** today" -ForegroundColor Cyan
    Write-Host "  ${p}Move <id|file> -To Done         Archive it -- the same as ${p}Archive" -ForegroundColor Cyan
    Write-Host "  ${p}Move -Help                      Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  For a card with nothing checked in or no pull request. A commit or a PR" -ForegroundColor Gray
    Write-Host "  still moves a card by itself; this is the same move, written by you." -ForegroundColor Gray
    Write-Host "  A new card starts in backlog/; Active, a commit or a PR pulls it in." -ForegroundColor Gray
    Write-Host "  A card travels one way: moving it back is refused -- except Active to" -ForegroundColor Gray
    Write-Host "  Backlog, for a card with no commit, PR URL, Started or Review line." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')

$c = Get-P20Consts
$p = Get-CliPrefix

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a lane: '${p}Move <id> -To InProgress'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}

# The lane, from the contract's words -- typed with or without the space, in any case.
$lanes = @{
    ($c.status.backlog    -replace '\s', '').ToLowerInvariant() = $c.status.backlog
    ($c.status.active     -replace '\s', '').ToLowerInvariant() = $c.status.active
    ($c.status.inProgress -replace '\s', '').ToLowerInvariant() = $c.status.inProgress
    ($c.status.codeReview -replace '\s', '').ToLowerInvariant() = $c.status.codeReview
    ($c.status.done       -replace '\s', '').ToLowerInvariant() = $c.status.done
}
$key = ("$To" -replace '\s', '').ToLowerInvariant()
if (-not $To -or -not $lanes.ContainsKey($key)) {
    Write-CliError -Message "'$To' is not a lane a card can be moved to." `
        -Hint "-To Backlog, -To Active, -To InProgress, -To CodeReview, or -To Done. A new card is $($c.status.backlog) until it is pulled into play."
    exit 2  # stated refusal
}
$target = $lanes[$key]

$folders = Get-PromptFolders
$backlogDir = Get-P20BacklogFolder -Folders $folders
$types = Get-P20WorkItemTypes -Config $cfg
# current/ and backlog/: the two folders a card can be moved FROM, named on purpose.
# -AllowPath: a card's full path is that card, whichever Space is active -- the
# path names its Space, so the folders it moves between are that Space's (below).
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
if ($resolved.IsPath) {
    # The card's own Space's backlog/, beside the folder it is in -- not the
    # active Space's, which a path into another Space has nothing to do with.
    $backlogDir = Get-P20SiblingCardFolder -Folder $file.DirectoryName -Name (Split-Path ($backlogDir.TrimEnd('/', '\')) -Leaf)
}
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

# Done is Archive, exactly -- one implementation, and its refusals are its own.
if ($target -eq $c.status.done) {
    # A card named by its path is handed on by its path, so Archive finds it in its own Space.
    $handOn = if ($resolved.IsPath) { $file.FullName } else { $file.Name }
    & (Join-Path $PSScriptRoot 'Move-PromptToArchive.ps1') -File $handOn
    exit $LASTEXITCODE
}

$text = [System.IO.File]::ReadAllText($file.FullName)
$inBacklog = Test-P20CardInBacklog -Path $file.FullName
$now = Get-PromptFileStatus -Content $text -Folder (Split-Path $file.FullName -Parent)

# -- The two folder lanes: the move IS the transition --------------------------
if ($target -eq $c.status.backlog) {
    if ($inBacklog) {
        Write-Host "$label is already $target -- nothing moved." -ForegroundColor Gray
        exit 0
    }
    # Unfinished work is not backlog, it is in play: anything threaded refuses.
    $markers = Get-P20InPlayMarkers -Content $text
    if ($markers.Count -gt 0) {
        Write-CliError -Message "$label is $now and carries $($markers -join ', '); threaded work is in play, not backlog." `
            -Hint "Finish it, or archive it: '${p}Archive $label'. To park it anyway, remove those lines by hand first -- on purpose, and knowing why."
        exit 2  # stated refusal
    }
    $moved = Move-P20CardFile -Path $file.FullName -Destination $backlogDir
    if (-not $moved.Ok) {
        Write-CliError -Message $moved.Message -Hint "Look in $($c.folders.backlog)/ -- a person moves or deletes the file there, on purpose."
        exit 2  # stated refusal
    }
    Write-Host "[+] $label is $target -- moved $($file.Name) to $($c.folders.backlog)/" -ForegroundColor Green
    exit 0
}
if ($target -eq $c.status.active) {
    if (-not $inBacklog) {
        if ($now -eq $target) {
            Write-Host "$label is already $target -- nothing moved." -ForegroundColor Gray
            exit 0
        }
        Write-CliError -Message "$label is $now; a card travels one way and is not moved back to $target." `
            -Hint "To take it back on purpose, remove the line that put it there -- the commit bullet, the PR URL, or the $($c.stamps.started) / $($c.stamps.review) line -- by hand."
        exit 2  # stated refusal
    }
    $pull = Invoke-P20PullIntoPlay -Path $file.FullName -Quiet
    if (-not $pull.Ok) {
        Write-CliError -Message $pull.Message -Hint "Look in $($c.folders.current)/ -- a person moves or deletes the file there, on purpose."
        exit 2  # stated refusal
    }
    Write-Host "[+] $label is $target -- moved $($file.Name) to $($c.folders.current)/" -ForegroundColor Green
    exit 0
}

# -- The written lanes: a backlog card is pulled into play FIRST ---------------
# So the line lands on a card in current/, and a backlog card never carries one.
if ($inBacklog) {
    $pull = Invoke-P20PullIntoPlay -Path $file.FullName
    if (-not $pull.Ok) {
        Write-CliError -Message $pull.Message -Hint "Look in $($c.folders.current)/ -- a person moves or deletes the file there, on purpose."
        exit 2  # stated refusal
    }
    $file = Get-Item -LiteralPath $pull.Path
    $now = Get-PromptFileStatus -Content $text
}
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
