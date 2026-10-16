<#
.SYNOPSIS
    Regression tests for the Get-PRComments.ps1 actionable-thread filter.
.DESCRIPTION
    Get-PRComments.ps1 used to filter PR threads using comment.commentType,
    but the ADO REST API (v7.1, this org) never returns that property --
    so file-less human comments (e.g. a reviewer's "Overall PR Review"
    summary with no threadContext.filePath) were silently dropped.

    This suite extracts the Test-IsActionableThread function straight out of
    the script's source text (via regex) and evaluates it against small
    synthetic thread fixtures -- so it exercises the real filter logic
    without invoking the rest of the script (auth, network calls, etc.).

    Run:  pwsh -File toolkit/Tests/Test-PRComments.ps1
    Or:   {cliPrefix}TestToolkit -PRComments
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'OutputFile', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'newCount', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Repository', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'prUrl', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'prTitle', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'PullRequestId', Justification = 'Read by the -OutputFile block the suite loads out of Get-PRComments.ps1 and runs in this scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Loads a function, or a block, out of the script under test by its source text, so it can be called alone.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location:
# works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/Get-PRComments.ps1'
if (-not (Test-Path $targetScript)) {
    Write-Error "Get-PRComments.ps1 not found at $targetScript"
    return
}

# ── Extract Test-IsActionableThread from the script source ──────────────────
# Pull just the function definition out of the file text and load it into
# this scope, so the test calls the exact same logic the script runs,
# without triggering auth/network/config side effects further down the file.
# Read as LF whatever the checkout: on Windows the script is CRLF on disk (* text=auto with
# core.autocrlf=true), and the regexes below that lift a function out of it expect "\n}\n".
$sourceText = (Get-Content -Path $targetScript -Raw) -replace "`r`n", "`n"
$funcMatch = [regex]::Match($sourceText, '(?s)function Test-IsActionableThread \{.*?\n\}')
if (-not $funcMatch.Success) {
    Write-Error "Could not find function Test-IsActionableThread in $targetScript"
    return
}
Invoke-Expression $funcMatch.Value

if (-not (Get-Command Test-IsActionableThread -ErrorAction SilentlyContinue)) {
    Write-Error "Test-IsActionableThread did not load correctly"
    return
}

# ── Test harness ──────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

# Byte-level writes for a card or session the verb under test reads or has just
# written. A host cmdlet (Set-Content / Add-Content -Encoding UTF8) opens the file
# with its own encoding detection and, on Windows PowerShell 5.1, throws "Stream was
# not readable" when something still holds it; the tool itself writes cards as
# BOM-less UTF-8 (AGENTS.md, "One byte contract for a card").
function Write-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
}
function Add-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::AppendAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Assert-True {
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# A skip is reported and counted, never scored as a pass.
$script:skipped = 0
function Skip-Case {
    param([string]$TestName, [string]$Reason)
    $script:skipped++
    Write-Host "  SKIP  $TestName -- $Reason" -ForegroundColor Yellow
}

# Whether the scratch hubs this suite builds sit on the package's own drive. They
# are made under the temp folder, so on a machine whose temp folder is on another
# drive no relative link between a card and the package exists, and a case whose
# premise is "the link resolves" has nothing to resolve.
$script:sameDrive = [string]::Equals(
    [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())),
    [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($pkgRoot)),
    [System.StringComparison]::OrdinalIgnoreCase)

function Assert-Relative {
    param([string]$TestName, [bool]$Condition)
    if ($script:sameDrive) { Assert-True $TestName $Condition; return }
    Skip-Case $TestName 'the scratch hub and the package are on different drives, so there is no relative link to resolve (the cross-drive cases below assert what a card carries instead)'
}

# ── Synthetic fixtures ───────────────────────────────────────────────────────
# Hand-built thread objects shaped like real ADO PR-thread API responses.
# Comment objects deliberately have NO commentType property, matching what
# the live API actually returns (this was the root cause of the bug).

function New-Comment {
    param([string]$DisplayName, [string]$Content)
    return [PSCustomObject]@{
        author        = [PSCustomObject]@{ displayName = $DisplayName }
        content       = $Content
        publishedDate = '2026-06-16T00:00:00Z'
    }
}

# (a) File-anchored human thread -- e.g. PR 81 thread 869.
$fileAnchoredThread = [PSCustomObject]@{
    id            = 869
    status        = 'active'
    threadContext = [PSCustomObject]@{ filePath = '/src/Foo.cs'; rightFileStart = [PSCustomObject]@{ line = 42 } }
    properties    = $null
    comments      = @(New-Comment -DisplayName 'A Reviewer' -Content 'This null check looks wrong.')
}

# (b) File-less human thread -- e.g. PR 81 thread 874, "Overall PR Review" summary.
$fileLessHumanThread = [PSCustomObject]@{
    id            = 874
    status        = 'active'
    threadContext = $null
    properties    = $null
    comments      = @(New-Comment -DisplayName 'A Reviewer' -Content 'Overall PR Review: looks good, a few nits inline.')
}

# (c) System/policy thread -- carries CodeReviewThreadType, no human content.
$systemThread = [PSCustomObject]@{
    id            = 900
    status        = 'fixed'
    threadContext = $null
    properties    = [PSCustomObject]@{ CodeReviewThreadType = [PSCustomObject]@{ '$type' = 'System.String'; value = 'VoteResultReset' } }
    comments      = @(New-Comment -DisplayName 'Microsoft.VisualStudio.Services.TFS' -Content '')
}

# (d) Build Service thread -- automated, should be dropped even though it
#     technically has "content".
$buildServiceThread = [PSCustomObject]@{
    id            = 901
    status        = 'closed'
    threadContext = $null
    properties    = $null
    comments      = @(New-Comment -DisplayName 'Project Collection Build Service (Org)' -Content 'Build succeeded.')
}

# (e) Bot review thread -- PR Assistant / AI Code Review, file-less, should be kept.
$botReviewThread = [PSCustomObject]@{
    id            = 902
    status        = 'active'
    threadContext = $null
    properties    = $null
    comments      = @(New-Comment -DisplayName 'PR Assistant' -Content '<small>PR Assistant / AI Code Review</small> found an issue.')
}

# (f)-(h) Activity-event threads -- vote / policy-status / PR-status updates. These carry a
#         CodeReviewThreadType BUT ADO stamps them with the triggering user's real display name
#         and synthetic content, so they look human. They must be dropped (regression: PR 84
#         threads 921/922/923 leaked into triage as fake "comments").
$voteThread = [PSCustomObject]@{
    id            = 921
    status        = ''
    threadContext = $null
    properties    = [PSCustomObject]@{ CodeReviewThreadType = [PSCustomObject]@{ '$type' = 'System.String'; '$value' = 'VoteUpdate' } }
    comments      = @(New-Comment -DisplayName 'A Reviewer' -Content 'A Reviewer voted 5')
}
$policyThread = [PSCustomObject]@{
    id            = 922
    status        = ''
    threadContext = $null
    properties    = [PSCustomObject]@{ CodeReviewThreadType = [PSCustomObject]@{ '$type' = 'System.String'; '$value' = 'PolicyStatusUpdate' } }
    comments      = @(New-Comment -DisplayName 'A Person' -Content 'Policy status has been updated')
}
$statusThread = [PSCustomObject]@{
    id            = 923
    status        = ''
    threadContext = $null
    properties    = [PSCustomObject]@{ CodeReviewThreadType = [PSCustomObject]@{ '$type' = 'System.String'; '$value' = 'StatusUpdate' } }
    comments      = @(New-Comment -DisplayName 'A Person' -Content 'A Person updated the pull request status to Completed')
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  PR Comments Filter Tests" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

Assert-True "File-anchored human thread (869) is kept" (Test-IsActionableThread $fileAnchoredThread)
Assert-True "File-less human thread (874, regression case) is kept" (Test-IsActionableThread $fileLessHumanThread)
Assert-True "System/policy thread is dropped" (-not (Test-IsActionableThread $systemThread))
Assert-True "Build Service thread is dropped" (-not (Test-IsActionableThread $buildServiceThread))
Assert-True "Bot review thread (file-less) is kept" (Test-IsActionableThread $botReviewThread)
Assert-True "Vote-event thread (921, human name) is dropped" (-not (Test-IsActionableThread $voteThread))
Assert-True "Policy-status thread (922, human name) is dropped" (-not (Test-IsActionableThread $policyThread))
Assert-True "PR-status thread (923, human name) is dropped" (-not (Test-IsActionableThread $statusThread))

$allThreads = @($fileAnchoredThread, $fileLessHumanThread, $systemThread, $buildServiceThread, $botReviewThread, $voteThread, $policyThread, $statusThread)
$actionable = @($allThreads | Where-Object { Test-IsActionableThread $_ })
Assert-True "End-to-end filter keeps exactly 3 of 8 threads" ($actionable.Count -eq 3)
Assert-True "End-to-end filter keeps thread 874" (874 -in @($actionable | ForEach-Object { $_.id }))
Assert-True "End-to-end filter drops all 3 activity events" (@(921, 922, 923 | Where-Object { $_ -in @($actionable | ForEach-Object { $_.id }) }).Count -eq 0)

Write-Host ""

# ── No-comments early-exit: PR URL always written ────────────────────────────
# Design: clicking fetch after creating a PR is the intentional trigger for the
# In Progress → Code Review transition. The PR URL is written regardless of
# whether there are review comments — the URL itself is the state gate.

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  No-Comments Early-Exit Tests" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

function Invoke-NoCommentsUrlDecision {
    param([string]$TempFile)
    # Mirror the logic from Get-PRComments.ps1 no-comments branch, including the
    # `-notmatch 'PR URL:'` guard that makes re-running idempotent.
    $fileContent = Get-Content -Path $TempFile -Raw
    if ($fileContent -notmatch 'PR URL:') {
        Add-FixtureText $TempFile "`nPR URL: https://dev.azure.com/fake/project/_git/repo/pullrequest/99"
        return $true
    }
    return $false
}

$tmpFile = [System.IO.Path]::GetTempFileName()
Write-FixtureText $tmpFile "# Prompt file"

# First run on a file with no PR URL: writes the line and flips the card.
$wroteFirst   = Invoke-NoCommentsUrlDecision -TempFile $tmpFile
$firstContent = Get-Content -Path $tmpFile -Raw

# Second run on the SAME file must skip the write (guard sees existing PR URL:).
$wroteSecond   = Invoke-NoCommentsUrlDecision -TempFile $tmpFile
$repeatContent = Get-Content -Path $tmpFile -Raw

Assert-True "No-comments → PR URL written (card flips to Code Review)" $wroteFirst
Assert-True "PR URL: line present in prompt file after write"           ($firstContent -match 'PR URL:')
Assert-True "Re-run skips the write (guard returns false)"             (-not $wroteSecond)
Assert-True "Re-running does not duplicate PR URL: line (idempotent)"   (($repeatContent -split 'PR URL:').Count -eq 2)

Remove-Item $tmpFile -ErrorAction SilentlyContinue

# The side record a fetch leaves in pr-comments/ is a hub file the tool creates, so it
# carries the card byte contract: UTF-8 with no byte-order mark, LF. Run the real
# Write-P20PRCommentsRecord against a scratch hub and read the bytes back.
. (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1')
$recFunc = [regex]::Match($sourceText, '(?s)function Write-P20PRCommentsRecord \{.*?\n\}\n')
Assert-True "Write-P20PRCommentsRecord is found in the script source" $recFunc.Success
Invoke-Expression $recFunc.Value
$recHub = Join-Path ([System.IO.Path]::GetTempPath()) ("prrec-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $recHub -Force | Out-Null
$savedRecCfg = $global:P20Config
$savedRecConsts = $script:Consts
try {
    $global:P20Config = [pscustomobject]@{ PromptsRoot = $recHub; PromptsFolder = 'org' }
    $script:Consts = [pscustomobject]@{ tokens = [pscustomobject]@{ prUrl = 'PR URL:' } }
    Write-P20PRCommentsRecord -PullRequestId 42 -Title 'A title' -Url 'https://example.test/pr/42' -Repository 'repo' -Count 3 | Out-Null
    $recFiles = @(Get-ChildItem -Path (Join-Path $recHub 'org/pr-comments') -Filter '*-PR42.md' -ErrorAction SilentlyContinue)
    Assert-True "the fetch writes one pr-comments record" ($recFiles.Count -eq 1)
    if ($recFiles.Count -eq 1) {
        $recBytes = [System.IO.File]::ReadAllBytes($recFiles[0].FullName)
        Assert-True "the record has no byte-order mark" (-not ($recBytes.Length -ge 3 -and $recBytes[0] -eq 0xEF -and $recBytes[1] -eq 0xBB -and $recBytes[2] -eq 0xBF))
        Assert-True "the record has no carriage return" (-not ($recBytes -contains 13))
        Assert-True "the record carries the fetched count" ([System.Text.Encoding]::UTF8.GetString($recBytes) -match 'Comments: 3')
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    $global:P20Config = $savedRecCfg
    $script:Consts = $savedRecConsts
    Remove-Item -Path $recHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# ── The agentic workflow link ────────────────────────────────────────────────
# The card lives in the hub -- a separate repo at an arbitrary depth -- while
# ado-comments.prompt.md ships with this package. The link used to be the
# hardcoded string "../../agentic/ado-comments.prompt.md", which was correct only
# while both sat in one repo and has pointed at nothing in every hub card since.
#
# Nothing caught it because a wrong relative link is still a valid line of
# markdown. These tests check the thing that actually matters: does the emitted
# path resolve to the file, from a directory at a depth nobody chose in advance.

# One file builds these lines and refreshes them, and Get-PRComments reads it
# rather than carrying its own copy of Resolve-P20PackageLink -- the second copy
# was in New-PromptFromWorkItem.ps1 and the two could drift.
#
Assert-True "Get-PRComments reads the shared link builder" `
    ($sourceText -match "Repair-CardLinks\.ps1")
Assert-True "Get-PRComments carries no second copy of Resolve-P20PackageLink" `
    (-not ($sourceText -match '(?s)function Resolve-P20PackageLink \{'))

. (Join-Path $pkgRoot 'Scripts/Repair-CardLinks.ps1')
Assert-True "the shared file supplies Resolve-P20PackageLink with no module loaded" `
    ([bool](Get-Command Resolve-P20PackageLink -ErrorAction SilentlyContinue))

$workflowPath = Join-Path $pkgRoot 'agentic/ado-comments.prompt.md'
Assert-True "the ado-comments workflow ships with the package" (Test-Path $workflowPath)

# A hub at a depth deliberately unlike the package's own layout.
$fakeHub = Join-Path ([System.IO.Path]::GetTempPath()) ("pkglink-" + [guid]::NewGuid().ToString('N'))
$fakeCardDir = Join-Path $fakeHub 'someone/someorg/current'
New-Item -ItemType Directory -Path $fakeCardDir -Force | Out-Null

$computed = Resolve-P20PackageLink -TargetPath $workflowPath -FromDirectory $fakeCardDir `
    -Fallback '../../agentic/ado-comments.prompt.md'

Assert-Relative "computed workflow link resolves to the real file" `
    (Test-Path (Join-Path $fakeCardDir $computed))
Assert-Relative "computed workflow link is not the old hardcoded depth" `
    ($computed -ne '../../agentic/ado-comments.prompt.md')
Assert-True "computed workflow link uses forward slashes" `
    (-not $computed.Contains([char]92))

# The console path passes no directory at all. A Mandatory parameter rejected
# null before the fallback could run, so the handled case threw instead.
$noDir = $null
try {
    $noDir = Resolve-P20PackageLink -TargetPath $workflowPath -FromDirectory $null -Fallback 'FALLBACK'
}
catch { $noDir = "THREW: $($_.Exception.Message)" }
Assert-True "a missing directory returns the fallback rather than throwing" ($noDir -eq 'FALLBACK')

$gone = Resolve-P20PackageLink -TargetPath (Join-Path $pkgRoot 'agentic/not-a-file.md') `
    -FromDirectory $fakeCardDir -Fallback 'FALLBACK'
Assert-True "a missing target returns the fallback" ($gone -eq 'FALLBACK')

Remove-Item $fakeHub -Recurse -Force -ErrorAction SilentlyContinue

# And the string itself must not come back. Get-PRComments emits no link text of
# its own at all now -- it asks the builder for the line.
Assert-True "Get-PRComments emits no literal workflow link" `
    (-not ($sourceText -match 'Triage these with the \['))
Assert-True "Get-PRComments asks the builder for the line" `
    ($sourceText -match 'New-P20WorkflowLine')

# -- A work item finds its own card, never one whose name merely contains it --
. (Join-Path $pkgRoot 'Scripts/Resolve-CardName.ps1')
$fm = [regex]::Match($sourceText, "(?s)function Find-P20CardForWorkItem \{.*?\n\}")
Assert-True "Find-P20CardForWorkItem is in the script" $fm.Success
Assert-True "Get-PRComments reads the one card-filename rule" ($sourceText -match 'Resolve-CardName\.ps1')
if ($fm.Success) {
    Invoke-Expression $fm.Value
    $cardDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cardmatch-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cardDir -Force | Out-Null
    foreach ($n in @('Task140-fix-39-bugs.prompt.md', '39-real.prompt.md', 'Feat-402-x.prompt.md')) {
        [System.IO.File]::WriteAllText((Join-Path $cardDir $n), 'x')
    }
    $files = @(Get-ChildItem -LiteralPath $cardDir -Filter '*.prompt.md' -File)
    $hit39 = @(Find-P20CardForWorkItem -PromptFiles $files -WorkItemId '39' -Config $null)
    Assert-True "work item 39 picks 39-real, not Task140-fix-39-bugs" ($hit39.Count -eq 1 -and $hit39[0].Name -eq '39-real.prompt.md')
    $hit402 = @(Find-P20CardForWorkItem -PromptFiles $files -WorkItemId '402' -Config $null)
    Assert-True "work item 402 matches Feat-402-x" ($hit402.Count -eq 1 -and $hit402[0].Name -eq 'Feat-402-x.prompt.md')
    Remove-Item -LiteralPath $cardDir -Recurse -Force -ErrorAction SilentlyContinue
}

# -- The link follows the card, not the machine that wrote it -----------------
# Every hub card written before a hub reorganisation had one `../` too many,
# and the only fix was counting them by hand. A card is now REFRESHED from
# wherever it currently sits.

# -- A thread is a conversation, not its opening remark -------------------------
# The script used to keep comments[0] and deduplicated on THREAD id, so a
# reviewer's follow-up inside a thread the card already had was skipped as a
# duplicate on every later run.
# The three functions that decide what a thread adds to a card are pure, so they
# are loaded out of the script the same way Test-IsActionableThread is.

Write-Host "-- Follow-up comments reach the card ------------------" -ForegroundColor Cyan

foreach ($fn in @('Get-P20ThreadTextComments', 'Get-P20RecordedComments', 'Get-P20ThreadDelta')) {
    $m = [regex]::Match($sourceText, "(?s)function $fn \{.*?\n\}")
    Assert-True "$fn is in the script" $m.Success
    if ($m.Success) { Invoke-Expression $m.Value }
}

function New-ThreadComment {
    param([int]$Id, [string]$DisplayName, [string]$Content, [string]$Type = 'text', [bool]$Deleted = $false)
    return [PSCustomObject]@{
        id            = $Id
        author        = [PSCustomObject]@{ displayName = $DisplayName }
        content       = $Content
        commentType   = $Type
        isDeleted     = $Deleted
        publishedDate = '2026-06-16T00:00:00Z'
    }
}

$conversation = [PSCustomObject]@{
    id            = 874
    status        = 'active'
    threadContext = [PSCustomObject]@{ filePath = '/src/Foo.cs'; rightFileStart = [PSCustomObject]@{ line = 42 } }
    properties    = $null
    comments      = @(
        (New-ThreadComment 1 'A Reviewer' 'This null check looks wrong.'),
        (New-ThreadComment 2 'The Engineer' 'Fixed in abc1234.'),
        (New-ThreadComment 3 'A Reviewer' 'That fix is not enough, see line 40.'),
        (New-ThreadComment 4 'Azure DevOps' 'The Engineer updated the status to fixed' 'system'),
        (New-ThreadComment 5 'A Reviewer' 'withdrawn' 'text' $true),
        (New-ThreadComment 6 'A Reviewer' '   ')
    )
}

$text = @(Get-P20ThreadTextComments $conversation)
Assert-True 'system, deleted and empty comments are not conversation' ($text.Count -eq 3) "got $($text.Count)"

# (1) A thread the card has never seen: the opener, and every later comment.
$d = Get-P20ThreadDelta -Thread $conversation -Recorded @{}
Assert-True 'an unseen thread is new' ($d.Kind -eq 'new') $d.Kind
Assert-True 'its opener is comment 1' ($d.Opener.Id -eq 1)
Assert-True 'and its two replies come with it' (@($d.FollowUps).Count -eq 2 -and @($d.FollowUps)[1].Comment.content -match 'not enough')

# (2) THE BUG. A card written by the old version holds the thread and nothing
# else -- and the old version only ever wrote the opener. The replies it dropped
# are recovered, once.
$legacyCard = "## PR Review Comments (PR 81)`n### Comment 1 (Thread 874)`nComment: This null check looks wrong.`nReply: `n"
$rec = Get-P20RecordedComments -FileContent $legacyCard
Assert-True 'a legacy card knows the thread' ($rec.ContainsKey(874))
$d = Get-P20ThreadDelta -Thread $conversation -Recorded $rec
Assert-True 'a known thread with unseen replies is a follow-up, not a duplicate' ($d.Kind -eq 'follow-up') $d.Kind
Assert-True 'the opener is NOT written again' ($null -eq $d.Opener)
Assert-True 'both dropped replies are recovered' ((@($d.FollowUps) | ForEach-Object { $_.Id }) -join ',' -eq '2,3')

# (3) Partly caught up: reply 2 is in the card, reply 3 is not.
$partCard = $legacyCard + "### Comment 2 (Thread 874)`nFollow-up: (Thread 874 / Comment 2) -- a later comment in this thread`nComment: Fixed in abc1234.`n"
$d = Get-P20ThreadDelta -Thread $conversation -Recorded (Get-P20RecordedComments -FileContent $partCard)
Assert-True 'only the reply the card lacks is added' ((@($d.FollowUps) | ForEach-Object { $_.Id }) -join ',' -eq '3')

# (4) Idempotent: everything recorded, nothing to add -- run it a hundred times.
$fullCard = $partCard + "### Comment 3 (Thread 874)`nFollow-up: (Thread 874 / Comment 3) -- a later comment in this thread`n"
$d = Get-P20ThreadDelta -Thread $conversation -Recorded (Get-P20RecordedComments -FileContent $fullCard)
Assert-True 'a fully recorded thread adds nothing' ($d.Kind -eq 'known' -and @($d.FollowUps).Count -eq 0) $d.Kind

# (5) A thread that reached the file as PROSE first is still known: its opener
# must not come back as a fake new comment (the rule the old dedup existed for).
$proseCard = "Reviewer summary: see thread **874** -- resolved by hand.`n"
$d = Get-P20ThreadDelta -Thread $conversation -Recorded (Get-P20RecordedComments -FileContent $proseCard)
Assert-True 'a prose mention makes the thread known' ($d.Kind -eq 'follow-up' -and $null -eq $d.Opener) $d.Kind

# (6) An id is not a substring: thread 87 is not thread 874.
$rec87 = Get-P20RecordedComments -FileContent "### Comment 1 (Thread 87)`n"
Assert-True 'thread 87 in the card does not make thread 874 known' (-not $rec87.ContainsKey(874))

# (7) A follow-up token belongs to ITS thread: (Thread 900 / Comment 2) says
# nothing about thread 874's comment 2.
$otherCard = $legacyCard + "Follow-up: (Thread 900 / Comment 2) -- a later comment in this thread`n"
$d = Get-P20ThreadDelta -Thread $conversation -Recorded (Get-P20RecordedComments -FileContent $otherCard)
Assert-True "another thread's token does not hide this thread's reply" ((@($d.FollowUps) | ForEach-Object { $_.Id }) -join ',' -eq '2,3')

# (8) A payload with no comment ids falls back to position.
$noIds = [PSCustomObject]@{
    id = 5; status = 'active'; threadContext = $null; properties = $null
    comments = @(
        [PSCustomObject]@{ author = [PSCustomObject]@{ displayName = 'A' }; content = 'one' },
        [PSCustomObject]@{ author = [PSCustomObject]@{ displayName = 'B' }; content = 'two' }
    )
}
$d = Get-P20ThreadDelta -Thread $noIds -Recorded @{ 5 = @() }
Assert-True 'comments without ids are numbered by position' ((@($d.FollowUps) | ForEach-Object { $_.Id }) -join ',' -eq '2')

# (9) The WRITER and the READER agree on the token. The reader's regex is the
# only thing that makes a follow-up idempotent, so the line the script writes
# is pulled out of the source and read back with the script's own reader.
$writerLine = [regex]::Match($sourceText, '\$md \+= "(Follow-up: \(Thread \$threadId / Comment \$\(\$w\.Item\.Id\)\)[^"]*)"')
Assert-True 'the script writes a Follow-up token line' $writerLine.Success
if ($writerLine.Success) {
    $rendered = $writerLine.Groups[1].Value.Replace('$threadId', '874').Replace('$($w.Item.Id)', '3')
    $back = Get-P20RecordedComments -FileContent "### Comment 9 (Thread 874)`n$rendered`n"
    Assert-True 'and the reader finds exactly that comment in it' (@($back[874]) -contains 3) $rendered
}

# (10) Every block keeps the heading the agent and the web UI split on.
Assert-True 'a follow-up uses the same "### Comment N (Thread T)" heading as an opener' `
    (([regex]::Matches($sourceText, '\$md \+= "### Comment \$commentNum \(Thread \$threadId\)"')).Count -eq 1)

Write-Host ""
Write-Host "-- ReplyPR writes the reply into the card -------------" -ForegroundColor Cyan

# One writer for a thread's Reply: slot (Scripts/Set-CardReply.ps1). ReplyPR
# posted to ADO and stopped; the slot GetPRComments wrote stayed empty.
#
. (Join-Path $pkgRoot 'Scripts/Set-CardReply.ps1')
$replyCard = Join-Path ([System.IO.Path]::GetTempPath()) ("reply-" + [guid]::NewGuid().ToString('N') + '.prompt.md')
try {
    $replyBody = "# Bug 140: a card`r`n`r`n## PR Review Comments`r`n`r`n### Comment 1 (Thread 77)`r`nReviewer/Bot: Sam`r`nStatus: active`r`nComment: rename this`r`nDecision: take / reject / modify`r`nReply: `r`n`r`n---`r`n`r`n### Comment 2 (Thread 78)`r`nStatus: active`r`nComment: and this`r`nDecision: take / reject / modify`r`nReply: `r`n`r`n---`r`n"
    [System.IO.File]::WriteAllText($replyCard, $replyBody, (New-Object System.Text.UTF8Encoding($false)))
    Assert-True "the thread's empty slot is filled, and its status set" (Set-P20CardReply -Path $replyCard -ThreadId 77 -Reply "Done in abc1234." -Status fixed)
    $filled = [System.IO.File]::ReadAllText($replyCard)
    Assert-True "the reply is in thread 77's block" ($filled -match "\(Thread 77\)\r\nReviewer/Bot: Sam\r\nStatus: fixed\r\nComment: rename this\r\nDecision: take / reject / modify\r\nReply: Done in abc1234\.") $filled
    Assert-True "thread 78 is untouched" ($filled -match "(?s)\(Thread 78\)\r\nStatus: active\r\n.*?Reply: \r\n") $filled
    Assert-True "the card kept its CRLF endings" (-not ($filled -replace "`r`n", '').Contains("`n")) $filled
    Assert-True "a second reply to an answered thread finds no slot and writes nothing" (-not (Set-P20CardReply -Path $replyCard -ThreadId 77 -Reply "again"))
    Assert-True "an unknown thread writes nothing" (-not (Set-P20CardReply -Path $replyCard -ThreadId 999 -Reply "nobody"))
    Assert-True "and the file is byte-for-byte what the one write left" ([System.IO.File]::ReadAllText($replyCard) -eq $filled)
    # The script itself resolves the card by the PR URL line, through the one
    # helper, when run under the module; that path needs ADO and is Gate 6's.
    Assert-True "Send-PRReply.ps1 dot-sources the one writer" ((Get-Content (Join-Path $pkgRoot 'Scripts/Send-PRReply.ps1') -Raw) -match "Set-CardReply\.ps1")
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $replyCard -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "-- The extension folder: a tuned prompt wins here, the package stays generic --" -ForegroundColor Cyan

# One resolver (Scripts/Resolve-AgenticPrompt.ps1): the configured folder's copy
# when it has the file, the package's otherwise, and nothing at all changes when
# no folder is set.
$extRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-ext-" + [guid]::NewGuid().ToString('N'))
try {
    $extPkg = Join-Path $extRoot 'pkg'
    $extHub = Join-Path $extRoot 'hub'
    New-Item -ItemType Directory -Path (Join-Path $extPkg 'Scripts'), (Join-Path $extPkg 'agentic'), (Join-Path $extHub 'mine') -Force | Out-Null
    foreach ($h in @('Resolve-AgenticPrompt.ps1', 'Resolve-HubConfig.ps1', 'Get-Consts.ps1', 'Write-ConfigParseWarning.ps1')) { Copy-Item (Join-Path $pkgRoot "Scripts/$h") (Join-Path $extPkg "Scripts/$h") }
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $extPkg 'consts.json')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $extPkg 'agentic/pr-review.prompt.md'), "# shipped review`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $extPkg 'agentic/ado-comments.prompt.md'), "# shipped comments`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $extHub 'mine/pr-review.prompt.md'), "# my tuned review`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $extPkg 'config.default.json'), '{ "promptsRoot": "", "agenticExtensionPath": "" }', $utf8)
    $savedCfg = $global:P20Config
    $savedRoot = $env:PROMPTS_ROOT
    $global:P20Config = $null
    $env:PROMPTS_ROOT = $extHub
    . (Join-Path $extPkg 'Scripts/Resolve-AgenticPrompt.ps1')

    $unset = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md' -PackageRoot $extPkg
    Assert-True "no folder set: the package copy, as it always was" ($unset.Source -eq 'package' -and $unset.Path -eq (Join-Path (Join-Path $extPkg 'agentic') 'pr-review.prompt.md')) ($unset | ConvertTo-Json -Compress)

    [System.IO.File]::WriteAllText((Join-Path $extPkg 'config.local.json'), '{ "agenticExtensionPath": "mine" }', $utf8)
    $tuned = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md' -PackageRoot $extPkg
    Assert-True "a hub-relative folder that carries the file wins" ($tuned.Source -eq 'extension' -and ([System.IO.File]::ReadAllText($tuned.Path)) -match 'my tuned review') ($tuned | ConvertTo-Json -Compress)
    $sibling = Resolve-P20AgenticPrompt -Name 'ado-comments.prompt.md' -PackageRoot $extPkg
    Assert-True "a name the folder does not carry falls back to the package" ($sibling.Source -eq 'package' -and $sibling.Path -like '*agentic*ado-comments.prompt.md') ($sibling | ConvertTo-Json -Compress)

    [System.IO.File]::WriteAllText((Join-Path $extPkg 'config.local.json'), ('{ "agenticExtensionPath": "' + (($extHub -replace '\\', '/') + '/mine') + '" }'), $utf8)
    $absolute = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md' -PackageRoot $extPkg
    Assert-True "an absolute folder works the same way" ($absolute.Source -eq 'extension') ($absolute | ConvertTo-Json -Compress)

    [System.IO.File]::WriteAllText((Join-Path $extPkg 'config.local.json'), '{ "agenticExtensionPath": "not-there" }', $utf8)
    $missingDir = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md' -PackageRoot $extPkg
    Assert-True "a folder that does not exist changes nothing" ($missingDir.Source -eq 'package') ($missingDir | ConvertTo-Json -Compress)
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    $global:P20Config = $savedCfg
    if ($null -eq $savedRoot) { Remove-Item Env:\PROMPTS_ROOT -ErrorAction SilentlyContinue } else { $env:PROMPTS_ROOT = $savedRoot }
    Remove-Item $extRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "-- A tool-sent prompt: the instruction below the fence, nothing above it --" -ForegroundColor Cyan

# The shipped prompts open with frontmatter, so the fence is the first '---'
# line AFTER it. Read the real files, in both line endings: a Windows checkout
# is CRLF, and a split that only knew LF sent the person's prose to the model.
# The agent's suite asserts the same files through prompt_instruction().
. (Join-Path $pkgRoot 'Scripts/Resolve-AgenticPrompt.ps1')
foreach ($case in @(
        @{ Name = 'pr-review.prompt.md'; First = 'You are a code reviewer.'; Placeholder = '{diff}' }
        @{ Name = 'pr-suggest.prompt.md'; First = 'Analyze this PR code review comment'; Placeholder = '{comment_text}' }
    )) {
    $raw = [System.IO.File]::ReadAllText((Join-Path $pkgRoot "agentic/$($case.Name)")).Replace("`r`n", "`n")
    foreach ($ending in @("`n", "`r`n")) {
        $label = if ($ending -eq "`n") { 'LF' } else { 'CRLF' }
        $instruction = (Get-P20PromptInstruction -Text $raw.Replace("`n", $ending)).Trim()
        Assert-True "$($case.Name) ($label): the instruction starts at the fence" ($instruction.StartsWith($case.First)) $instruction.Substring(0, [Math]::Min(80, $instruction.Length))
        Assert-True "$($case.Name) ($label): its placeholder is in the instruction" ($instruction.Contains($case.Placeholder))
        Assert-True "$($case.Name) ($label): no frontmatter and no prose reach the model" (-not $instruction.Contains('description:') -and -not $instruction.Contains('is sent verbatim'))
    }
}
Assert-True "a file with no frontmatter fences on its first --- line" ((Get-P20PromptInstruction -Text "prose`n---`nsent") -eq 'sent')
Assert-True "a file with no fence is sent whole" ((Get-P20PromptInstruction -Text "just this") -eq 'just this')

Write-Host ""
Write-Host "-- Package links are refreshed, not frozen -----------" -ForegroundColor Cyan

$relinkHub = Join-Path ([System.IO.Path]::GetTempPath()) ("relink-" + [guid]::NewGuid().ToString('N'))
try {
    $deepDir = Join-Path $relinkHub 'someone/test/current'
    $shallowDir = Join-Path $relinkHub 'demo/current'
    New-Item -ItemType Directory -Path $deepDir -Force | Out-Null
    New-Item -ItemType Directory -Path $shallowDir -Force | Out-Null

    $card = Join-Path $deepDir '114-a-card.prompt.md'
    $body = (New-P20TemplateLine -TemplateName 'Bug.template.md' -CardDirectory $deepDir) + "`n`n" +
            "## Comments`n`n" + (New-P20WorkflowLine -CardDirectory $deepDir) + "`n"
    Write-CardText -Path $card -Content $body -New

    $written = Get-Content $card -Raw -Encoding UTF8
    $tplRel = [regex]::Match($written, '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
    Assert-Relative "a freshly written template link resolves to the real file" `
        ((Test-Path (Join-Path $deepDir $tplRel)) -and $tplRel)

    Assert-True "refreshing an unchanged card writes nothing" `
        (-not (Repair-P20CardLinks -Path $card))

    # Now move the card one level shallower -- the hub reorganisation that broke
    # all six demo cards.
    $moved = Join-Path $shallowDir '114-a-card.prompt.md'
    Move-Item $card $moved
    # The frozen link now carries one `../` too many -- the exact shape all six
    # demo cards had after the hub reorganisation. (Whether an over-deep path
    # still happens to resolve depends on where the two trees sit relative to
    # the filesystem root, which is why the assertion is about the TEXT.)
    $staleTpl = [regex]::Match((Get-Content $moved -Raw -Encoding UTF8), '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
    $staleHops = ([regex]::Matches($staleTpl, '\.\./')).Count

    Assert-Relative "the refresh reports that it changed the card" `
        (Repair-P20CardLinks -Path $moved)

    $after = Get-Content $moved -Raw -Encoding UTF8
    $newTpl = [regex]::Match($after, '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
    $newWf = [regex]::Match($after, '\[ado-comments workflow\]\(([^)]*)\)').Groups[1].Value
    Assert-Relative "the refreshed template link resolves from the new folder" `
        ((Test-Path (Join-Path $shallowDir $newTpl)) -and $newTpl)
    Assert-Relative "the refreshed workflow link resolves from the new folder" `
        ((Test-Path (Join-Path $shallowDir $newWf)) -and $newWf)
    $newHops = ([regex]::Matches($newTpl, '\.\./')).Count
    Assert-Relative "the refreshed link climbs one level less than the frozen one" `
        ($newHops -eq ($staleHops - 1))
    Assert-True "a second refresh is a no-op" `
        (-not (Repair-P20CardLinks -Path $moved))

    # ...and back again: the rule is "wherever it is now", not "one level up".
    Move-Item $moved $card
    $null = Repair-P20CardLinks -Path $card
    $backTpl = [regex]::Match((Get-Content $card -Raw -Encoding UTF8), '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
    Assert-Relative "moving the card back restores a link that resolves" `
        ((Test-Path (Join-Path $deepDir $backTpl)) -and $backTpl)

    # -- A CRLF card: the platform where hub moves happen -------------------
    # On Windows most cards are CRLF on disk. The template pattern could not
    # match one (its `$` could not step over the \r), and the workflow pattern
    # swallowed the \r and wrote the line back with a bare LF: links stayed
    # broken and every Sync left the card mixed.
    #
    Move-Item $card $moved
    $crlfText = (Get-Content $moved -Raw -Encoding UTF8) -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($moved, $crlfText, (New-Object System.Text.UTF8Encoding($false)))
    Assert-Relative "a CRLF card with a stale link is repaired (reported changed)" (Repair-P20CardLinks -Path $moved)
    $crlfAfter = [System.IO.File]::ReadAllText($moved)
    Assert-True "the repaired card is CRLF on every line -- no bare LF anywhere" (-not ($crlfAfter -replace "`r`n", '').Contains("`n"))
    $crlfTpl = [regex]::Match($crlfAfter, '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
    Assert-Relative "the CRLF card's template link now resolves" ((Test-Path (Join-Path $shallowDir $crlfTpl)) -and $crlfTpl)
    Assert-True "a second refresh of the CRLF card is a no-op" (-not (Repair-P20CardLinks -Path $moved))
    Move-Item $moved $card
    $null = Repair-P20CardLinks -Path $card

    # The writer itself: an edit keeps the file's endings whatever the caller
    # passed in, and a create is LF whatever the caller passed in.
    $endings = Join-Path $relinkHub 'endings.md'
    [System.IO.File]::WriteAllText($endings, "one`r`ntwo`r`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-CardText -Path $endings -Content "one`ntwo`nthree`n"
    Assert-True "an edit with LF content keeps a CRLF file CRLF" ([System.IO.File]::ReadAllText($endings) -eq "one`r`ntwo`r`nthree`r`n")
    [System.IO.File]::WriteAllText($endings, "one`ntwo`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-CardText -Path $endings -Content "one`r`ntwo`r`nthree`r`n"
    Assert-True "an edit with CRLF content keeps an LF file LF" ([System.IO.File]::ReadAllText($endings) -eq "one`ntwo`nthree`n")
    [System.IO.File]::WriteAllText($endings, "one`r`ntwo`nthree`r`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-CardText -Path $endings -Content "x`ny`n"
    Assert-True "a mixed file is made consistent, as CRLF (it contained one)" ([System.IO.File]::ReadAllText($endings) -eq "x`r`ny`r`n")
    Write-CardText -Path $endings -Content "a`r`nb`r`n" -New
    Assert-True "a create is LF whatever the content carried" ([System.IO.File]::ReadAllText($endings) -eq "a`nb`n")

    # No guessed fallback: a package that cannot be found leaves the NAME, not
    # a legacy ../../templates/ path that is wrong for every toolkit hub.
    $orphan = New-P20TemplateLine -TemplateName 'NotAThing.template.md' -CardDirectory $deepDir
    Assert-True "an unfindable template is named, not guessed at" `
        ($orphan -eq '> Template: NotAThing.template.md')
    Assert-True "and carries no ../../templates/ fallback" `
        (-not ($orphan -match '\.\./'))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    Remove-Item $relinkHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "-- Across drives a card names the file and keeps no machine path --" -ForegroundColor Cyan
# Resolve-Path -Relative has no answer between two drives (or onto a share) and
# returns the ABSOLUTE path, which a card would then keep and sync to a machine
# where it means nothing. The one builder falls back to the file's name instead,
# and the repair pass rebuilds a line that already holds a machine path.
#
# These cases need a hub on a different drive from the package. A machine whose
# temp folder is already on another drive has one. Otherwise, on Windows, `subst`
# makes one from a free letter and takes it away again. Where neither can be had
# the cases are skipped, and say so.

$xHub = $null
$xLetter = $null
$xBacking = $null
$xHow = ''
$xWhy = ''
if (-not $script:sameDrive) {
    $xHub = Join-Path ([System.IO.Path]::GetTempPath()) ("xdrive-" + [guid]::NewGuid().ToString('N'))
    $xHow = 'the temp folder is already on another drive'
}
elseif ([System.IO.Path]::DirectorySeparatorChar -ne [char]92) {
    $xWhy = 'this platform has one filesystem root, so a hub cannot be put on another drive'
}
elseif (-not (Get-Command subst.exe -ErrorAction SilentlyContinue)) {
    $xWhy = 'subst.exe is not available to make a second drive'
}
else {
    $xBacking = Join-Path ([System.IO.Path]::GetTempPath()) ("xdrive-backing-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $xBacking -Force | Out-Null
    $xTried = ''
    foreach ($l in [char[]]'ZYXWVUTSRQPONMLKJIHGFED') {
        if (Test-Path -LiteralPath "${l}:\") { continue }
        # A native command's stderr under Stop is a throw in Windows PowerShell 5.1.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $substOut = (& subst.exe "${l}:" $xBacking 2>&1 | Out-String); $substCode = $LASTEXITCODE }
        finally { $ErrorActionPreference = $prevEap }
        if ($substCode -eq 0 -and (Test-Path -LiteralPath "${l}:\")) { $xLetter = [string]$l; break }
        $xTried = "subst ${l}: failed ($($substOut.Trim()))"
        if ($substCode -eq 0) {
            $ErrorActionPreference = 'Continue'
            try { & subst.exe "${l}:" /D 2>&1 | Out-Null } finally { $ErrorActionPreference = $prevEap }
        }
    }
    if ($xLetter) {
        $xHub = "${xLetter}:\hub"
        $xHow = "subst ${xLetter}: onto a scratch folder"
    }
    else {
        $xWhy = "no free drive letter could be made with subst ($xTried)"
        Remove-Item $xBacking -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $xHub) {
    Skip-Case 'the cross-drive cases' $xWhy
}
else {
    Write-Host "  (hub on another drive: $xHow)" -ForegroundColor DarkGray
    $machinePath = '(?<![A-Za-z])[A-Za-z]:[\\/]|\]\((?:/|\\\\)|\(//'
    $wantTpl = '> Template: Bug.template.md'
    $wantWf = 'Triage these with the ado-comments workflow -- agentic/ado-comments.prompt.md in the Toolkit package'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        $xCardDir = Join-Path $xHub 'someone/test/current'
        New-Item -ItemType Directory -Path $xCardDir -Force | Out-Null
        Assert-True 'the scratch hub really is on another drive from the package' `
            (-not [string]::Equals(
                [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($xCardDir)),
                [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($pkgRoot)),
                [System.StringComparison]::OrdinalIgnoreCase))

        # -- A card written here --------------------------------------------------
        $tplLine = New-P20TemplateLine -TemplateName 'Bug.template.md' -CardDirectory $xCardDir
        $wfLine = New-P20WorkflowLine -CardDirectory $xCardDir
        Assert-True "the template line is the file's name, not a link ($tplLine)" ($tplLine -eq $wantTpl)
        Assert-True "the workflow line is the file's name, not a link ($wfLine)" ($wfLine -eq $wantWf)
        $xCard = Join-Path $xCardDir '114-a-card.prompt.md'
        Write-CardText -Path $xCard -Content ($tplLine + "`n`n## Comments`n`n" + $wfLine + "`n") -New
        $written = [System.IO.File]::ReadAllText($xCard)
        Assert-True 'a card written there carries no drive letter and no absolute path in either line' `
            (-not [regex]::IsMatch($written, $machinePath)) $written
        Assert-True 'refreshing it writes nothing (idempotent)' (-not (Repair-P20CardLinks -Path $xCard))
        Assert-True 'and the bytes are untouched' ([System.IO.File]::ReadAllText($xCard) -eq $written)

        # -- A card that already carries a machine path -----------------------------
        $pkgFwd = $pkgRoot -replace '\\', '/'
        $variants = @(
            @{ Name = 'a drive letter, forward slashes'
               Tpl = '[Bug.template.md](Q:/work/toolkit/templates/Bug.template.md)'  # export:example
               Wf = '[ado-comments workflow](Q:/work/toolkit/agentic/ado-comments.prompt.md)' },  # export:example
            @{ Name = 'a drive letter, backslashes'
               Tpl = '[Bug.template.md](Q:\work\toolkit\templates\Bug.template.md)'  # export:example
               Wf = '[ado-comments workflow](Q:\work\toolkit\agentic\ado-comments.prompt.md)' },  # export:example
            @{ Name = 'a network share'
               Tpl = '[Bug.template.md](//fileserver/share/toolkit/templates/Bug.template.md)'
               Wf = '[ado-comments workflow](//fileserver/share/toolkit/agentic/ado-comments.prompt.md)' },
            @{ Name = 'a leading slash'
               Tpl = '[Bug.template.md](/srv/checkout/toolkit/templates/Bug.template.md)'
               Wf = '[ado-comments workflow](/srv/checkout/toolkit/agentic/ado-comments.prompt.md)' },
            @{ Name = 'this package, spelled absolutely (what an unfixed run wrote)'
               Tpl = "[Bug.template.md]($pkgFwd/templates/Bug.template.md)"
               Wf = "[ado-comments workflow]($pkgFwd/agentic/ado-comments.prompt.md)" },
            @{ Name = 'a bare path where the name goes'
               Tpl = 'Q:\work\toolkit\templates\Bug.template.md'  # export:example
               Wf = 'Q:\work\toolkit\agentic\ado-comments.prompt.md' }  # export:example
        )
        $n = 0
        foreach ($v in $variants) {
            $n++
            $vCard = Join-Path $xCardDir "$n-variant.prompt.md"
            $before = "# Bug ${n}: variant`n`n> Template: $($v.Tpl)`n`n## Comments`n`nTriage these with the $($v.Wf)`n"
            [System.IO.File]::WriteAllText($vCard, $before, $utf8)
            Assert-True "[$($v.Name)] the card starts with a machine path (the case is not vacuous)" `
                ([regex]::IsMatch($before, $machinePath))
            Assert-True "[$($v.Name)] the repair reports that it changed the card" (Repair-P20CardLinks -Path $vCard)
            $after = [System.IO.File]::ReadAllText($vCard)
            $tplAfter = [regex]::Match($after, '(?m)^> Template: [^\r\n]*').Value
            $wfAfter = [regex]::Match($after, '(?m)^Triage these with the [^\r\n]*').Value
            Assert-True "[$($v.Name)] the template line is now the file's name ($tplAfter)" ($tplAfter -eq $wantTpl)
            Assert-True "[$($v.Name)] the workflow line is now the file's name ($wfAfter)" ($wfAfter -eq $wantWf)
            Assert-True "[$($v.Name)] no drive letter and no absolute path is left" (-not [regex]::IsMatch($after, $machinePath)) $after
            Assert-True "[$($v.Name)] the rest of the card is untouched" `
                ($after -eq ($before -replace '(?m)^> Template: [^\r\n]*', $wantTpl -replace '(?m)^Triage these with the [^\r\n]*', $wantWf))
            Assert-True "[$($v.Name)] a second repair changes nothing" (-not (Repair-P20CardLinks -Path $vCard))
            Assert-True "[$($v.Name)] and the bytes are the same" ([System.IO.File]::ReadAllText($vCard) -eq $after)
        }

        # A CRLF card keeps its endings through the same repair.
        $crlfCard = Join-Path $xCardDir '200-crlf.prompt.md'
        $crlfBefore = "# Bug 200: crlf`r`n`r`n> Template: [Bug.template.md](Q:/work/toolkit/templates/Bug.template.md)`r`n`r`nTriage these with the [ado-comments workflow](Q:/work/toolkit/agentic/ado-comments.prompt.md)`r`n"  # export:example
        [System.IO.File]::WriteAllText($crlfCard, $crlfBefore, $utf8)
        Assert-True 'a CRLF card with machine paths is repaired (reported changed)' (Repair-P20CardLinks -Path $crlfCard)
        $crlfAfter = [System.IO.File]::ReadAllText($crlfCard)
        Assert-True 'and stays CRLF on every line' (-not ($crlfAfter -replace "`r`n", '').Contains("`n"))
        Assert-True 'with no machine path left' (-not [regex]::IsMatch($crlfAfter, $machinePath)) $crlfAfter
        Assert-True 'and a second repair changes nothing' (-not (Repair-P20CardLinks -Path $crlfCard))

        # -- Both copies of the builder, lifted out of their sources ---------------
        # The module carries one Resolve-P20PackageLink and Repair-CardLinks.ps1 carries
        # another for a caller with no module loaded. Neither may hand back an absolute path.
        $modSrc = (Get-Content -Path (Join-Path $pkgRoot 'utilities.psm1') -Raw) -replace "`r`n", "`n"
        $scrSrc = (Get-Content -Path (Join-Path $pkgRoot 'Scripts/Repair-CardLinks.ps1') -Raw) -replace "`r`n", "`n"
        $copies = @(
            @{ Name = 'module';
               Match = [regex]::Match($modSrc, '(?s)function global:Resolve-P20PackageLink \{.*?\n\}\n');
               From = 'function global:Resolve-P20PackageLink'; To = 'function script:Resolve-LinkModuleCopy'; Fn = 'Resolve-LinkModuleCopy' },
            @{ Name = 'no-module';
               Match = [regex]::Match($scrSrc, '(?s)    function Resolve-P20PackageLink \{.*?\n    \}\n');
               From = 'function Resolve-P20PackageLink'; To = 'function script:Resolve-LinkScriptCopy'; Fn = 'Resolve-LinkScriptCopy' }
        )
        foreach ($c in $copies) {
            Assert-True "the $($c.Name) copy of Resolve-P20PackageLink is found in its source" $c.Match.Success
            if (-not $c.Match.Success) { continue }
            Invoke-Expression ($c.Match.Value.Replace($c.From, $c.To))
            $got = & $c.Fn -TargetPath $workflowPath -FromDirectory $xCardDir -Fallback 'FALLBACK'
            Assert-True "the $($c.Name) copy returns the -Fallback across drives, not an absolute path ($got)" ($got -eq 'FALLBACK')
            $gotNone = & $c.Fn -TargetPath $workflowPath -FromDirectory $xCardDir
            Assert-True "the $($c.Name) copy returns an empty string across drives when no -Fallback is given" ([string]$gotNone -eq '')
            if ($script:sameDrive) {
                $nearDir = Join-Path ([System.IO.Path]::GetTempPath()) ("near-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $nearDir -Force | Out-Null
                try {
                    $near = & $c.Fn -TargetPath $workflowPath -FromDirectory $nearDir -Fallback 'FALLBACK'
                    Assert-True "the $($c.Name) copy still resolves a relative link on one drive ($near)" `
                        ($near -ne 'FALLBACK' -and -not [System.IO.Path]::IsPathRooted($near) -and (Test-Path (Join-Path $nearDir $near)))
                }
                finally { Remove-Item $nearDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
            else {
                Skip-Case "the $($c.Name) copy still resolves a relative link on one drive" 'the temp folder and the package are on different drives here; the single-drive cases run where they share one'
            }
        }

        # -- Through the verb: Archive -Relink in a fresh shell, on this hub --------
        $verbHub = Join-Path $xHub 'verb'
        New-Item -ItemType Directory -Path (Join-Path $verbHub 'alpha/archive') -Force | Out-Null
        $hubJson = @{ orgs = @(@{ slug = 'alpha'; promptsFolder = 'alpha'; status = 'active' }) } | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText((Join-Path $verbHub 'hub.json'), $hubJson)
        $absCard = Join-Path $verbHub 'alpha/archive/1-absolute.prompt.md'
        [System.IO.File]::WriteAllText($absCard, "# Bug 1: absolute`n`n> Template: [Bug.template.md]($pkgFwd/templates/Bug.template.md)`n")
        $pkg = Split-Path -Parent $PSScriptRoot
        $prefix = (Get-Content (Join-Path $pkg 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
        $cmd = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = '$verbHub'; " +
            "Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; " +
            "${prefix}Archive -Relink; 'EXIT=' + `$LASTEXITCODE"
        $verbOut = (& pwsh -NoProfile -NonInteractive -Command $cmd 2>&1 | ForEach-Object { "$_" }) -join "`n"
        Assert-True 'Archive -Relink as a verb exits 0 on the other drive' ($verbOut -match 'EXIT=0') $verbOut
        $verbTpl = [regex]::Match([System.IO.File]::ReadAllText($absCard), '(?m)^> Template: [^\r\n]*').Value
        Assert-True "and the card's absolute template link became the file's name ($verbTpl)" ($verbTpl -eq $wantTpl)
    }
    catch {
        Assert-True "the cross-drive cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
    }
    finally {
        if ($xLetter) {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { & subst.exe "${xLetter}:" /D 2>&1 | Out-Null } finally { $ErrorActionPreference = $prevEap }
            Assert-True "the subst drive ${xLetter}: is removed again" (-not (Test-Path -LiteralPath "${xLetter}:\"))
        }
        if ($xBacking) { Remove-Item $xBacking -Recurse -Force -ErrorAction SilentlyContinue }
        elseif ($xHub) { Remove-Item $xHub -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ""
Write-Host "-- Every org's cards are repaired, not only the active Space's --" -ForegroundColor Cyan
# Sync and Archive -Relink walked the ACTIVE org's two folders, so an org nobody
# switches to kept its links forever: every card of an archived Space.
#
$allOrgHub = Join-Path ([System.IO.Path]::GetTempPath()) ("allorgs-" + [guid]::NewGuid().ToString('N'))
try {
    foreach ($d in @('alpha/current', 'alpha/archive', 'beta/archive')) {
        New-Item -ItemType Directory -Path (Join-Path $allOrgHub $d) -Force | Out-Null
    }
    $spaces = @(
        [pscustomobject]@{ slug = 'alpha'; promptsFolder = 'alpha' },
        [pscustomobject]@{ slug = 'beta' },                    # no promptsFolder: the slug is the folder
        [pscustomobject]@{ slug = 'gone'; promptsFolder = 'gone' }  # declared, never created
    )
    $found = Get-P20CardFolders -Root $allOrgHub -Spaces $spaces -Also @((Join-Path $allOrgHub 'alpha/current'))
    $names = @($found | ForEach-Object { ($_.Substring($allOrgHub.Length + 1)) -replace '\\', '/' })
    Assert-True "every declared org's existing folders are found, each once ($($names -join ', '))" `
        ((@($names | Sort-Object) -join '|') -eq 'alpha/archive|alpha/current|beta/archive')

    # Through the VERB, in a fresh shell: a hub.json declaring two orgs, neither of
    # them the active one, each holding a card with the June-era legacy link.
    $hubJson = @{ orgs = @(@{ slug = 'alpha'; promptsFolder = 'alpha'; status = 'active' }, @{ slug = 'beta'; promptsFolder = 'beta'; status = 'archive' }) } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText((Join-Path $allOrgHub 'hub.json'), $hubJson)
    $legacy = "# Bug 1: legacy`n`n> Template: [Bug.template.md](../../templates/Bug.template.md)`n"
    [System.IO.File]::WriteAllText((Join-Path $allOrgHub 'alpha/archive/1-legacy.prompt.md'), $legacy)
    [System.IO.File]::WriteAllText((Join-Path $allOrgHub 'beta/archive/2-legacy.prompt.md'), ($legacy -replace 'Bug 1', 'Bug 2'))
    $pkg = Split-Path -Parent $PSScriptRoot
    $prefix = (Get-Content (Join-Path $pkg 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $cmd = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = '$allOrgHub'; " +
        "Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; " +
        "${prefix}Archive -Relink; 'EXIT=' + `$LASTEXITCODE"
    $out = (& pwsh -NoProfile -NonInteractive -Command $cmd 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True "Archive -Relink as a verb exits 0" ($out -match 'EXIT=0') $out
    foreach ($c in @('alpha/archive/1-legacy.prompt.md', 'beta/archive/2-legacy.prompt.md')) {
        $cardDir = Split-Path (Join-Path $allOrgHub $c) -Parent
        $link = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $allOrgHub $c)), '(?m)^> Template: \[[^\]]+\]\(([^)]*)\)').Groups[1].Value
        if ($script:sameDrive) {
            Assert-True "$c -- in an org that is not active -- now links to a template that exists ($link)" `
                ($link -and (Test-Path (Join-Path $cardDir $link)))
        }
        else {
            $tplLine = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $allOrgHub $c)), '(?m)^> Template: [^\r\n]*').Value
            Assert-True "$c -- in an org that is not active -- now names the template, with no stale link, across drives ($tplLine)" `
                ($tplLine -eq '> Template: Bug.template.md')
        }
    }
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    Remove-Item $allOrgHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "-- The pr-comments/ side record, and -OutputFile --" -ForegroundColor Cyan
# Get-PRComments.ps1 needs az and the network, so the suite lifts the two pieces that decide
# the side record out of the source -- the writer function, and the block that gates it on
# -OutputFile -- and runs them against a scratch hub.
$recFunc = [regex]::Match($sourceText, '(?s)function Write-P20PRCommentsRecord \{.*?\n\}\n')
$recBlock = [regex]::Match($sourceText, '(?s)    # --- Write canonical pr-comments record ---.*?\n    \}\n(?=\s*\n\}\ncatch)')
Assert-True "the side-record writer and its -OutputFile gate are both found in the script" ($recFunc.Success -and $recBlock.Success)
if ($recFunc.Success -and $recBlock.Success) {
    Invoke-Expression $recFunc.Value
    $recHub = Join-Path ([System.IO.Path]::GetTempPath()) ("prrec-" + [guid]::NewGuid().ToString('N'))
    $savedCfg = $global:P20Config
    $savedConsts = $script:Consts
    try {
        New-Item -ItemType Directory -Path (Join-Path $recHub 'demo') -Force | Out-Null
        $global:P20Config = [pscustomobject]@{ PromptsRoot = $recHub; PromptsFolder = 'demo' }
        $script:Consts = [pscustomobject]@{ tokens = [pscustomobject]@{ prUrl = 'PR URL:' } }
        $PullRequestId = 34; $prTitle = 'A title'; $prUrl = 'https://example/pr/34'; $Repository = 'repo'; $newCount = 2
        $recDir = Join-Path $recHub 'demo/pr-comments'

        $OutputFile = Join-Path $recHub 'scratch.md'
        $skipOut = (Invoke-Expression $recBlock.Value 6>&1 | ForEach-Object { "$_" }) -join "`\n"
        Assert-True "with -OutputFile no pr-comments/ directory or record appears in the hub" `
            (-not (Test-Path $recDir))
        Assert-True "with -OutputFile the verb says the side record was skipped" ($skipOut -match 'Side record skipped: -OutputFile')

        $OutputFile = $null
        $null = (Invoke-Expression $recBlock.Value 6>&1 | ForEach-Object { "$_" })
        $recFiles = @(Get-ChildItem $recDir -Filter '*-PR34.md' -ErrorAction SilentlyContinue)
        Assert-True "without -OutputFile the record is written, one file named for the PR" ($recFiles.Count -eq 1)
        if ($recFiles.Count -eq 1) {
            $recText = [System.IO.File]::ReadAllText($recFiles[0].FullName)
            Assert-True "the record carries the PR URL, repository and comment count" `
                (($recText -match 'PR URL: https://example/pr/34') -and ($recText -match 'Repository: repo') -and ($recText -match 'Comments: 2'))
        }
    }
    finally {
        $global:P20Config = $savedCfg
        $script:Consts = $savedConsts
        Remove-Item $recHub -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:skipped -gt 0) {
    Write-Host "  Skipped: $($script:skipped) (a skip is not a pass)" -ForegroundColor Yellow
}
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
