<#
.SYNOPSIS
    Land a card: record the merge, close the issue behind it, archive it.
.DESCRIPTION
    The end of a card is three verbs and a hand edit -- a merge bullet typed
    into the card, CloseItem, Archive -- and it is the step most often left
    half done, because the card is the engineer's ledger and the tracker is the
    organisation's, and nothing reconciles the two (AGENTS.md, "Two ledgers").

    Land asks the tracker one question first: is the pull request MERGED?
    (`gh pr view --json state,mergeCommit,mergedAt` on GitHub,
    `az repos pr show` on Azure DevOps; the PR is the card's `PR URL:` line,
    or -Pr). Only then, in order:

      1. the bullet `- <short merge hash> #<n> squash-merged to <base> <yyyy-MM-dd>`
         goes into the card's Git section -- Add-CommitBullet.ps1, the rule
         ThreadHash writes by, and Write-CardText -- so the card carries the
         commit that landed it;
      2. the issue or work item behind the card is closed by CloseItem
         (Scripts/Close-WorkItem.ps1, run as it is), with a comment naming the
         commit and -Comment;
      3. the card is archived by Archive (Scripts/Move-PromptToArchive.ps1, run
         as it is).

    It is a composition: no second closer, no second archiver. Each step that
    has already happened is skipped -- the bullet already on the card, the
    issue already closed, the card already in archive/ -- so Land is safe to
    run again, and a run after a full Land changes nothing and says so.
.EXAMPLE
    {cliPrefix}Land 146
    {cliPrefix}Land K7M2 -Pr 175 -Comment "Thanks for the review."
    {cliPrefix}Land 146 -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [int]$Pr = 0,

    [string]$Comment = '',

    [switch]$WhatIf,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$p = Get-CliPrefix
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$c = Get-P20Consts
$prToken = [string]$c.tokens.prUrl

if ($Help) {
    Write-Host ""
    Write-Host "  ${p}Land <id|file> [-Pr <n>] [-Comment <text>] [-WhatIf]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Asks the tracker whether the card's pull request is merged, and only then:" -ForegroundColor Gray
    Write-Host "    1. records '- <hash> #<n> squash-merged to <base> <date>' in the card's Git section" -ForegroundColor Gray
    Write-Host "    2. closes the issue behind the card (${p}CloseItem), naming the commit" -ForegroundColor Gray
    Write-Host "    3. archives the card (${p}Archive)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -Pr <n>          The pull request, when the card has no $prToken line" -ForegroundColor Gray
    Write-Host "  -Comment <text>  More words for the closing comment" -ForegroundColor Gray
    Write-Host "  -WhatIf          Print the three writes and make none" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  A step already done is skipped, so running it again is safe. An open or" -ForegroundColor Gray
    Write-Host "  closed-unmerged pull request is refused and nothing is written." -ForegroundColor Gray
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

. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Add-CommitBullet.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Get-WorkItemRecord.ps1')
. (Join-Path $PSScriptRoot 'ConvertTo-LocalDay.ps1')

$types = Get-P20WorkItemTypes -Config $cfg

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename: '${p}Land <id>'. '${p}Status' lists the cards."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Which card ----------------------------------------------------------------
#
# The one rule (Resolve-P20CardArgument): an id is that id and never a partial
# name. current/ and backlog/ first -- the card in play -- then archive/, so a
# card a person archived by hand, or a Land that stopped after its last step,
# is found where it is and never archived a second time as a new round.
$folders = Get-PromptFolders
$backlogDir = Get-P20BacklogFolder -Folders $folders
$archiveDir = $folders.Archive
$inPlay = Resolve-P20CardArgument -Argument $Card -Folder @($folders.Current, $backlogDir) `
    -WorkItemTypes $types -AllowPath -PromptsRoot $promptsRoot
$found = @($inPlay.Match | Where-Object { $_.Name -like '*.prompt.md' })
$resolved = $inPlay
if ($found.Count -eq 0) {
    $resolved = Resolve-P20CardArgument -Argument $Card -Folder @($archiveDir) `
        -WorkItemTypes $types -AllowPath -PromptsRoot $promptsRoot
    $found = @($resolved.Match | Where-Object { $_.Name -like '*.prompt.md' })
}
if ($found.Count -eq 0) {
    if ($inPlay.IsId) {
        Write-CliError -Message "No card with id '$Card' in current/, backlog/ or archive/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. Run '${p}Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/, backlog/ or archive/." `
            -Hint "Pass the card's ID, its filename, or a path. Run '${p}Status' to see the cards."
    }
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($found.Count -gt 1) {
    Write-Host "Matches for '$Card':" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$Card' matches $($found.Count) cards." -Hint "Pass the full filename, or the path, of the one you mean."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($resolved.Fuzzy) {
    if ($env:TOOLKIT_QUIET_STARTUP) {
        Write-CliError -Message "'$Card' is not a card; it matches '$($found[0].Name)' only by partial name." `
            -Hint "Pass the card's ID or its full filename."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-Host "Matched '$Card' -> $($found[0].Name)" -ForegroundColor Cyan
}

$cardFile = $found[0].FullName
$leaf = $found[0].Name
$archived = ((Split-Path (Split-Path $cardFile -Parent) -Leaf) -eq [string]$c.folders.archive)
$original = [System.IO.File]::ReadAllText($cardFile)
$cardId = Get-P20CardId -Name ($leaf -replace '-r\d+(?=\.prompt\.md$)', '') -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)

# -- Which pull request --------------------------------------------------------
#
# The card's PR URL: line says which tracker holds it, and where; -Pr names the
# number when the card has none (a Code Review by a **Review:** line), and the
# active Space's tracker then says where to ask.
$prUrl = ''
$prLine = [regex]::Match($original, '(?m)^' + [regex]::Escape($prToken) + '\s*(https://\S+)')
if ($prLine.Success) { $prUrl = $prLine.Groups[1].Value.Trim() }

$prHost = ''
$ghRepo = ''
$adoOrg = ''
$prNumber = $Pr
$ghPr = [regex]::Match($prUrl, '(?i)github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)')
$adoPr = [regex]::Match($prUrl, '(?i)/pullrequest/(\d+)')
if ($ghPr.Success) {
    $prHost = 'github'
    $ghRepo = "$($ghPr.Groups[1].Value)/$($ghPr.Groups[2].Value)"
    if (-not $prNumber) { $prNumber = [int]$ghPr.Groups[3].Value }
}
elseif ($adoPr.Success) {
    $prHost = 'ado'
    $orgMatch = [regex]::Match($prUrl, '(?i)^(https://dev\.azure\.com/[^/]+|https://[^/]+\.visualstudio\.com)/')
    $adoOrg = if ($orgMatch.Success) { $orgMatch.Groups[1].Value } else { [string]$cfg.Org }
    if (-not $prNumber) { $prNumber = [int]$adoPr.Groups[1].Value }
}

if (-not $prNumber) {
    Write-CliError -Message "$leaf has no $prToken line, so there is no pull request to ask about." `
        -Hint "Name it: '${p}Land $Card -Pr <n>'."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$spaceTracker = Resolve-P20Tracker -OrgUrl $cfg.Org
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $cfg.Org
if (-not $prHost) {
    $prHost = $spaceTracker
    if ($prHost -eq 'github') {
        $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $cfg.Org -Projects $cfg.Projects -CliPrefix $p
        if (-not $repoAnswer.Repo) {
            Write-CliError -Message "$($repoAnswer.Reason) Pull request #$prNumber cannot be looked up." -Hint $repoAnswer.Hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $ghRepo = $repoAnswer.Repo
    }
    elseif ($prHost -eq 'ado') {
        $adoOrg = [string]$cfg.Org
    }
    else {
        Write-CliError -Message "This Space has no tracker, and $leaf has no $prToken line to say where pull request #$prNumber is." `
            -Hint "Write the card's $prToken line, or run ${p}Land from the Space whose tracker holds the pull request."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

function ConvertTo-P20LandDay {
    # The merge's local day. ConvertFrom-Json hands pwsh 7 a [DateTime] and
    # Windows PowerShell 5.1 the ISO string; both are an instant in UTC.
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return '' }
    $instant = $null
    if ($Value -is [DateTime]) {
        $dt = $Value
        if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
        $instant = [DateTimeOffset]$dt
    }
    else {
        $parsed = [DateTimeOffset]::MinValue
        $ok = [DateTimeOffset]::TryParse("$Value", [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)
        if (-not $ok) { return '' }
        $instant = $parsed
    }
    return (ConvertTo-P20LocalDay "$($instant.ToUnixTimeSeconds())")
}

# -- Is it merged? -------------------------------------------------------------
#
# The one question asked before anything is written. Its answer is read, never
# assumed: a PR that is open, closed without merging or abandoned is a stated
# refusal that names the state, and the card is left exactly as it was.
$mergeHash = ''
$mergeDay = ''
$baseBranch = ''
$prLabel = "#$prNumber"
if ($prHost -eq 'github') {
    $prLabel = "#$prNumber ($ghRepo)"
    $view = Invoke-P20TrackerRead 'gh' @('pr', 'view', "$prNumber", '--repo', $ghRepo, '--json', 'state,mergeCommit,mergedAt,baseRefName')
    if ($view.Code -ne 0 -or -not ($view.Out -join '').Trim()) {
        $said = @($view.Lines | Where-Object { "$_".Trim() })[0]
        Write-CliError -Message "Could not read pull request $prLabel from GitHub$(if ($said) { ": $said" } else { '.' })" `
            -Hint 'Check the number, and that gh is signed in (gh auth status). Nothing was written.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $prData = ($view.Out -join "`n") | ConvertFrom-Json
    $state = "$($prData.state)".ToUpperInvariant()
    if ($state -ne 'MERGED') {
        $word = if ($state -eq 'OPEN') { 'open' } elseif ($state -eq 'CLOSED') { 'closed without merging' } else { "'$($prData.state)'" }
        Write-CliError -Message "Pull request $prLabel is $word, not merged. Nothing was written." `
            -Hint "Land runs after the merge. Merge it, then '${p}Land $Card' again."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $mergeHash = "$($prData.mergeCommit.oid)"
    $mergeDay = ConvertTo-P20LandDay $prData.mergedAt
    $baseBranch = "$($prData.baseRefName)"
}
else {
    $show = Invoke-P20TrackerRead 'az' @('repos', 'pr', 'show', '--id', "$prNumber", '--org', $adoOrg, '--output', 'json')
    $out = @($show.Out | Where-Object { "$_" -notmatch '^WARNING:' })
    if ($show.Code -ne 0 -or -not ($out -join '').Trim()) {
        $said = @(@($show.Err) + @($out) | Where-Object { "$_".Trim() })[0]
        Write-CliError -Message "Could not read pull request $prLabel from Azure DevOps$(if ($said) { ": $said" } else { '.' })" `
            -Hint 'Check the number, and that az is signed in (az login). Nothing was written.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $prData = ($out -join "`n") | ConvertFrom-Json
    $status = "$($prData.status)".ToLowerInvariant()
    if ($status -ne 'completed') {
        $word = if ($status -eq 'active') { 'open' } elseif ($status -eq 'abandoned') { 'abandoned' } else { "'$($prData.status)'" }
        Write-CliError -Message "Pull request $prLabel is $word, not merged. Nothing was written." `
            -Hint "Land runs after the merge. Complete it, then '${p}Land $Card' again."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $mergeHash = "$($prData.lastMergeCommit.commitId)"
    $mergeDay = ConvertTo-P20LandDay $prData.closedDate
    $baseBranch = ("$($prData.targetRefName)" -replace '^refs/heads/', '')
}

if ($mergeHash -notmatch '^[0-9a-fA-F]{7,}$') {
    Write-CliError -Message "Pull request $prLabel reads as merged, but the tracker named no merge commit." `
        -Hint 'Nothing was written. Look at the pull request on the tracker, and record the commit by hand if it has one.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$shortHash = $mergeHash.Substring(0, 7).ToLowerInvariant()
if (-not $mergeDay) { $mergeDay = (Get-Date).ToString('yyyy-MM-dd') }
if (-not $baseBranch) { $baseBranch = 'main' }
$bullet = "- $shortHash #$prNumber squash-merged to $baseBranch $mergeDay"
Write-Host "[*] Pull request $prLabel is merged: $shortHash, $mergeDay." -ForegroundColor Cyan

# -- Step 1: the plan for the bullet ------------------------------------------
$hasBullet = Test-P20HashSeen -Hash $shortHash -Known (Get-P20CardBulletHashes -Content $original)
$wasCrlf = $original.Contains("`r`n")
$newContent = $null
if (-not $hasBullet) {
    $edit = Add-P20CommitBullets -Content ($original -replace "`r`n", "`n") -Bullets @($bullet)
    if (-not $edit.Ok) {
        Write-CliError -Message "No '## Git' section in $leaf, so the merge has nowhere to go. Nothing was written." `
            -Hint "Add a '## Git' heading with a 'Commits:' line, as the card templates have, then '${p}Land $Card' again."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $newContent = $edit.Content
    if ($wasCrlf) { $newContent = $newContent -replace "`n", "`r`n" }
}

# -- Step 2: the plan for the issue -------------------------------------------
#
# The issue behind the card, by the rule NewPR reads a work item id with: the
# card's **ADO Link:** URL when it has one (a -Title card published with
# NewItem -FromCard keeps its short id and gains a link), else the card's id
# when it is a number. A card with neither has no issue to close.
$issueId = 0
$link = [regex]::Match($original, '(?m)^\s*\*{0,2}ADO Link:\*{0,2}\s*(https://\S+)')
if ($link.Success) {
    $linkUrl = $link.Groups[1].Value
    $linkNum = [regex]::Match($linkUrl, '/edit/(\d+)')
    if (-not $linkNum.Success) { $linkNum = [regex]::Match($linkUrl, '/(\d+)/?$') }
    if ($linkNum.Success) { $issueId = [int]$linkNum.Groups[1].Value }
}
if (-not $issueId -and (Test-P20IsWorkItemId $cardId)) { $issueId = [int]$cardId }

$issueSkip = ''     # why the issue step does nothing; '' when it closes
$issueWord = if ($spaceTracker -eq 'github') { "issue #$issueId" } else { "work item $issueId" }
if ($spaceTracker -eq 'none') {
    $issueSkip = 'this Space has no tracker, so there is no issue to close'
}
elseif (-not $issueId) {
    $issueSkip = "$leaf has no issue behind it (a card made with -Title)"
}
else {
    # Already closed? Asked here, because CloseItem on a closed item still posts
    # its comment -- a second comment on every re-run. A read that fails is not
    # an answer: CloseItem runs, and states its own refusal if it cannot.
    if ($spaceTracker -eq 'github') {
        $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $cfg.Org -Projects $cfg.Projects -CliPrefix $p
        if ($repoAnswer.Repo) {
            $issueRead = Invoke-P20TrackerRead 'gh' @('issue', 'view', "$issueId", '--repo', $repoAnswer.Repo, '--json', 'state')
            if ($issueRead.Code -eq 0 -and ($issueRead.Out -join '').Trim()) {
                $issueState = "$((($issueRead.Out -join "`n") | ConvertFrom-Json).state)".ToUpperInvariant()
                if ($issueState -eq 'CLOSED') { $issueSkip = "$issueWord is already closed" }
            }
        }
    }
    else {
        $record = Get-P20WorkItemRecord -Id "$issueId" -Org ([string]$cfg.Org)
        if ($record.Ok -and (Test-P20BoardStateClosed $record.State)) { $issueSkip = "$issueWord is already $($record.State)" }
    }
}
# Markdown: GitHub renders it, and CloseItem turns the link into HTML on Azure
# DevOps. No '#<n>' -- CloseItem reads '#' and four digits there as a work item.
$prName = if ($prUrl) { "[pull request $prNumber]($prUrl)" } else { "pull request $prNumber" }
$closeComment = "Landed in $shortHash -- $prName, squash-merged to $baseBranch $mergeDay."
if ($Comment.Trim()) { $closeComment = "$closeComment $($Comment.Trim())" }

# -- -WhatIf: the three writes, and none of them -------------------------------
if ($WhatIf) {
    Write-Host ""
    Write-Host "  [WhatIf] No changes will be made." -ForegroundColor Yellow
    if ($hasBullet) { Write-Host "  [WhatIf] 1. Skipped: $leaf already carries $shortHash." -ForegroundColor Yellow }
    else { Write-Host "  [WhatIf] 1. Would add to $leaf`: $bullet" -ForegroundColor Yellow }
    if ($issueSkip) { Write-Host "  [WhatIf] 2. Skipped: $issueSkip." -ForegroundColor Yellow }
    else { Write-Host "  [WhatIf] 2. Would close $issueWord with the comment: $closeComment" -ForegroundColor Yellow }
    if ($archived) { Write-Host "  [WhatIf] 3. Skipped: $leaf is already in $($c.folders.archive)/." -ForegroundColor Yellow }
    else { Write-Host "  [WhatIf] 3. Would archive $leaf." -ForegroundColor Yellow }
    exit 0
}

$changed = 0

# -- Step 1: record the merge --------------------------------------------------
if ($hasBullet) {
    Write-Host "[1/3] Skipped: $leaf already carries $shortHash." -ForegroundColor DarkGray
}
else {
    # A planned card is pulled into play before its first commit is written, the
    # way ThreadHash does it (Scripts/Move-CardFolder.ps1).
    $pull = Invoke-P20PullIntoPlay -Path $cardFile
    if (-not $pull.Ok) {
        Write-CliError -Message "$($pull.Message) Nothing was written." `
            -Hint "Look in $($c.folders.current)/ -- a person moves or deletes the file there, on purpose."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $cardFile = $pull.Path
    Write-CardText -Path $cardFile -Content $newContent
    Write-Host "[1/3] Recorded in $leaf`: $bullet" -ForegroundColor Green
    $changed++
}

# -- Step 2: close the issue, through CloseItem --------------------------------
if ($issueSkip) {
    Write-Host "[2/3] Skipped: $issueSkip." -ForegroundColor DarkGray
}
else {
    Write-Host "[2/3] Closing $issueWord through ${p}CloseItem..." -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    $closeOut = & (Join-Path $PSScriptRoot 'Close-WorkItem.ps1') -Id $issueId -Comment $closeComment
    $closeCode = $LASTEXITCODE
    $closed = @($closeOut | Where-Object { "$_" -match '^\[RESULT\]' })
    if ($closeCode -ne 0 -or $closed.Count -eq 0) {
        # CloseItem has already said why, once (AGENTS.md, "The refusal contract").
        $where = if ($archived) { "in $($c.folders.archive)/" } else { "where it was, not archived" }
        Write-Host "    Land stopped at step 2: the merge is recorded on the card and the card is $where." -ForegroundColor Yellow
        Write-Host "    Run '${p}Land $Card' again once $issueWord can be closed; the recorded step is skipped." -ForegroundColor Yellow
        exit 2  # stated refusal -- CloseItem's
    }
    $changed++
}

# -- Step 3: archive, through Archive ------------------------------------------
if ($archived) {
    Write-Host "[3/3] Skipped: $leaf is already in $($c.folders.archive)/." -ForegroundColor DarkGray
}
else {
    Write-Host "[3/3] Archiving $leaf through ${p}Archive..." -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    # By its path, so Archive finds this card and no other.
    & (Join-Path $PSScriptRoot 'Move-PromptToArchive.ps1') -File $cardFile
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $changed++
}

Write-Host ""
if ($changed -eq 0) {
    Write-Host "[=] $leaf is already landed: the merge recorded, the issue step done, the card in $($c.folders.archive)/. Nothing changed." -ForegroundColor DarkGray
}
else {
    Write-Host "[+] Landed $leaf -- $shortHash, pull request $prNumber." -ForegroundColor Green
}
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "${p}Land" -Detail "$leaf $shortHash #$prNumber ($changed step(s) written)"
}
exit 0
