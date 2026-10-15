<#
.SYNOPSIS
    Fetches PR review comments from Azure DevOps and appends them to a prompt file.

.DESCRIPTION
    Pulls all threads from a given PR, filters to actionable comments (skips system/build noise),
    formats as markdown matching the ADO-Comments.template.md structure, and appends to the
    matching prompt file in current/ (auto-detected from linked work items).

    Workflow:
    1. Resolve PR ID from branch name (or accept PR ID directly)
    2. Fetch threads via ADO REST API (Bearer token from az cli)
    3. Filter: skip system threads (policy, auto-complete, publish), keep file-specific + human comments
    4. Parse each thread: extract file, line, author, category, severity, content, code suggestion
    5. Query linked work items and find matching prompt file in current/
    6. Append formatted comments to prompt file (or print to console)

.PARAMETER PullRequestId
    The PR number (positional). If not provided, auto-detects from current branch.

.PARAMETER BranchName
    Source branch name to look up the PR. Ignored if PullRequestId is provided.

.PARAMETER Repository
    ADO repository name. Default: from toolkit config.

.PARAMETER Project
    ADO project name. Default: from toolkit config.

.PARAMETER OutputFile
    Write to a specific file instead of auto-detecting from linked work items.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    Get-P20PRComments -PullRequestId 140123
    Get-P20PRComments
    Get-P20PRComments 140123 -OutputFile .\my-bug.prompt.md

.NOTES
    Depends on: az cli (for access token), ADO REST API v7.1
    Config: reads org/project/repo from $global:P20Config
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$PullRequestId,

    [Parameter()]
    [string]$BranchName,

    [Parameter()]
    [string]$Repository,

    [Parameter()]
    [string]$Project,

    [Parameter()]
    [string]$OutputFile,

    [Parameter()]
    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# The workflow line this script appends to a card, and the standalone
# Resolve-P20PackageLink fallback it needs when this script runs with no module.
# The line is BUILT here and REFRESHED by the same file after a move, so it
# cannot be written one way and repaired another.
#
. (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')

# The two card literals this script WRITES and Get-PromptStatus/agent read back:
# the "PR URL:" line that gates Code Review, and the PR-comments heading. Both
# live in consts.json -- see AGENTS.md, "One place for magic strings".
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$script:Consts = Get-P20Consts


# ── Help ─────────────────────────────────────────────────────────────────────
function Show-Help {
    Write-Host @"

Get-P20PRComments - Fetch PR review comments and append to prompt file

USAGE:
    $(Get-CliPrefix)GetPRComments <PullRequestId> [options]
    $(Get-CliPrefix)GetPRComments                             # auto-detect from current branch

PARAMETERS:
    -PullRequestId <int>   PR number (positional). Omit to detect from branch.
    -BranchName <string>   Source branch to look up PR. Ignored if PullRequestId given.
    -Repository <string>   ADO repo name. Default: from toolkit config.
    -Project <string>      ADO project name. Default: from toolkit config.
    -OutputFile <path>     Write to specific file instead of auto-detecting prompt (no pr-comments/ side record).
    -Help                  Show this help message.

BEHAVIOR:
    1. Fetches all PR threads from ADO
    2. Filters out system noise (policy, auto-complete, build publish)
    3. Formats actionable comments as markdown (ADO-Comments template)
    4. Queries PR for linked work items
    5. Finds matching prompt file in current/ by work item ID
    6. Appends formatted comments to that prompt file

    If no matching prompt file is found, prints to console with a warning.

EXAMPLES:
    $(Get-CliPrefix)GetPRComments 140123                        # Fetch + append to matching prompt
    $(Get-CliPrefix)GetPRComments                               # Auto-detect PR from current branch
    $(Get-CliPrefix)GetPRComments 140123 -OutputFile .\x.md     # Write to specific file
    $(Get-CliPrefix)GetPRComments 140123 -Project "Learning Coaches Everywhere" -Repository CoachWebApp

"@ -ForegroundColor Cyan
    exit 0
}

# ── Thread filter ────────────────────────────────────────────────────────────
# Decide whether a PR thread is "actionable" (worth surfacing for triage).
#
# Note: the ADO REST API (v7.1, this org) does NOT return a `commentType`
# property on comment objects at all -- so detection of human vs. system
# comments must rely on author + content instead. System/policy threads are
# identified via the `properties.CodeReviewThreadType` marker ADO attaches
# to them, since they have no human-authored content.
#
# Defined before the -Help early-exit so test suites can dot-source this
# script with -Help (no network/config access) and call this function
# directly against synthetic fixtures.
function Test-IsActionableThread {
    param($Thread)

    $hasFileContext = [bool]($Thread.threadContext -and $Thread.threadContext.filePath)

    $humanComments = @($Thread.comments | Where-Object {
            $_.author.displayName -and
            $_.author.displayName -notmatch 'Build Service|Microsoft\.VisualStudio\.Services|Project Collection Build' -and
            -not [string]::IsNullOrWhiteSpace($_.content)
        })
    $hasHumanComment = $humanComments.Count -gt 0
    $hasBotReview = ($Thread.comments | Where-Object { $_.content -match 'PR Assistant|AI Code Review' }).Count -gt 0

    # System/activity threads carry a CodeReviewThreadType property: policy threads
    # (no human content), but ALSO vote / policy-status / PR-status events. ADO stamps the
    # latter with the *triggering* user's display name and a synthetic content line
    # ("X voted 5", "Policy status has been updated", "X updated the pull request status to
    # Completed"), so they look like human comments -- but they are activity-feed events, not
    # review feedback. Drop anything carrying CodeReviewThreadType regardless of author.
    # Verified against live PR payloads: real review comments never carry this property
    # (vote=VoteUpdate, policy=PolicyStatusUpdate, status=StatusUpdate; real comments=none).
    $isSystemThread = [bool]($Thread.properties -and $Thread.properties.CodeReviewThreadType) -and -not $hasBotReview
    $isBuildService = ($Thread.comments | Where-Object { $_.author.displayName -match 'Build Service' }).Count -gt 0

    return ($hasFileContext -or $hasHumanComment -or $hasBotReview) -and -not $isSystemThread -and -not $isBuildService
}

if ($Help) { Show-Help }

# The one byte contract for a card this script writes into.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

# ── Config ───────────────────────────────────────────────────────────────────
$cfg = $global:P20Config
if (-not $cfg) {
    Write-CliError -Message "Toolkit config not loaded. Is utilities.psm1 imported?"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$org = $cfg.Org

# Resolve project/repo from config if not provided
if (-not $Project -or -not $Repository) {
    $projects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo } })
    if ($projects.Count -eq 0) {
        Write-CliError -Message "No projects configured for the active Space." -Hint "Pass -Project and -Repository, or add projects to the Space in hub.json."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not $Project) { $Project = $projects[0].Name }
    if (-not $Repository) {
        $match = $projects | Where-Object { $_.Name -eq $Project }
        if ($match) {
            $Repository = $match.Repo
        }
        else {
            $Repository = $projects[0].Repo
        }
    }
}


$ErrorActionPreference = 'Stop'

# ── Auth ─────────────────────────────────────────────────────────────────────
# -- A thread is a conversation, not its opening remark -------------------------
# This script used to keep comments[0] of a thread and nothing else, and
# deduplicated on THREAD id -- so a reviewer's follow-up inside a thread the card
# already had ("that fix is not enough, see line 40") was skipped as a duplicate
# on every later run, for ever. The card is meant to be the whole record of the
# review, and it silently stopped matching the PR
# (docs/CLI.md, GetPRComments).
#
# The three functions below are pure -- no ADO, no file system -- so the suite
# loads them out of this file and runs them against fixture threads.

function Get-P20ThreadTextComments {
    <#
        The comments of a thread that are CONVERSATION, in thread order: written
        text, not deleted, not one of ADO's system entries.
    #>
    param($Thread)
    return @($Thread.comments | Where-Object {
            -not $_.isDeleted -and
            ("$($_.commentType)" -ne 'system') -and
            -not [string]::IsNullOrWhiteSpace($_.content)
        })
}

function Get-P20RecordedComments {
    <#
        What the card already holds: thread id -> the ids of the FOLLOW-UP
        comments recorded for it. A thread that is present at all has its opening
        comment recorded -- that is what every version of this script has written
        -- so the opener needs no token, and a card written before follow-ups
        existed reads correctly with no migration: present, no follow-ups.

        Threads are recognised in ANY form, prose included ("thread 874",
        "thread **874**"): a thread can reach the file as a hand-written summary
        first, and it must not come back as a fake new comment.
    #>
    param([string]$FileContent)
    $recorded = @{}
    if (-not $FileContent) { return $recorded }
    foreach ($m in [regex]::Matches($FileContent, '(?i)threads?\s*\**\s*(\d+)')) {
        $threadId = [int]$m.Groups[1].Value
        if (-not $recorded.ContainsKey($threadId)) { $recorded[$threadId] = @() }
    }
    foreach ($m in [regex]::Matches($FileContent, '\(Thread (\d+) / Comment (\d+)\)')) {
        $threadId = [int]$m.Groups[1].Value
        $recorded[$threadId] = @($recorded[$threadId]) + [int]$m.Groups[2].Value
    }
    return $recorded
}

function Get-P20ThreadDelta {
    <#
        What this thread adds to the card. Returns @{ Kind; Opener; FollowUps }:
          new        the card has never seen the thread: its opener, and every
                     later comment as a follow-up
          follow-up  the card has the thread, and the thread has comments the
                     card does not
          known      nothing to add
        A comment's id is ADO's, which counts WITHIN the thread (1, 2, 3...); a
        payload without ids falls back to position.
    #>
    param($Thread, [hashtable]$Recorded)
    $comments = @(Get-P20ThreadTextComments $Thread)
    $threadId = [int]$Thread.id
    $numbered = @()
    for ($i = 0; $i -lt $comments.Count; $i++) {
        $commentId = $i + 1
        if ($comments[$i].PSObject.Properties['id'] -and $comments[$i].id) { $commentId = [int]$comments[$i].id }
        $numbered += [PSCustomObject]@{ Id = $commentId; Comment = $comments[$i] }
    }
    $later = @($numbered | Select-Object -Skip 1)
    if (-not $Recorded.ContainsKey($threadId)) {
        $opener = $null
        if ($numbered.Count -gt 0) { $opener = $numbered[0] }
        return @{ Kind = 'new'; Opener = $opener; FollowUps = $later }
    }
    $known = @($Recorded[$threadId])
    $unseen = @($later | Where-Object { $_.Id -notin $known })
    if ($unseen.Count -eq 0) { return @{ Kind = 'known'; Opener = $null; FollowUps = @() } }
    return @{ Kind = 'follow-up'; Opener = $null; FollowUps = $unseen }
}

function Write-P20PRCommentsRecord {
    # The side record: one small file per PR fetch under <promptsFolder>/pr-comments/, read at
    # archive time to count prsReviewed. Best effort -- a failure warns and never stops the run.
    param($PullRequestId, [string]$Title, [string]$Url, [string]$Repository, $Count)
    try {
        $cfg = $global:P20Config
        if ($cfg -and $cfg.PromptsRoot) {
            $prRoot = $cfg.PromptsRoot
            $prFolder = if ($cfg.PromptsFolder) { $cfg.PromptsFolder } else { '' }
            $prCommentsDir = if ($prFolder) { Join-Path $prRoot "$prFolder/pr-comments" } else { Join-Path $prRoot 'pr-comments' }
            New-Item -ItemType Directory -Force -Path $prCommentsDir | Out-Null
            $fetchDate = (Get-Date).ToString('yyyy-MM-dd')
            $recordFile = Join-Path $prCommentsDir "$fetchDate-PR$PullRequestId.md"
            $recordLines = @(
                "# PR $PullRequestId$(if ($Title) { " - $Title" })"
                ""
                "$($script:Consts.tokens.prUrl) $Url"
                "Fetched: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                "Repository: $Repository"
                "Comments: $Count"
            )
            $recordLines -join "`n" | Out-File -FilePath $recordFile -Encoding UTF8 -NoNewline
            Write-Host "Record written to pr-comments/$($fetchDate)-PR$PullRequestId.md" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "Warning: Could not write pr-comments record: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# The token, the headers and the 401/403 advice: one helper for every ADO script.
. (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')

# ── Main ─────────────────────────────────────────────────────────────────────
try {
    # --- Resolve PR ID ---
    if (-not $PullRequestId -and -not $BranchName) {
        # The cwd's branch is the card's only when the cwd is the card's code
        # checkout. The Toolkit's own checkout never is -- the bridge runs every
        # verb there -- and its branch looked up in the card's project can write
        # a wrong PR URL: into a card, which is the Code Review token.
        #
        # Asked of git, not by comparing paths.
        $cwdGitDir = "$(git rev-parse --absolute-git-dir 2>$null)".Trim()
        $toolkitGitDir = "$(git -C (Split-Path -Parent $PSScriptRoot) rev-parse --absolute-git-dir 2>$null)".Trim()
        if ($cwdGitDir -and $toolkitGitDir -and $cwdGitDir -eq $toolkitGitDir) {
            Write-CliError -Message "No PullRequestId or BranchName provided, and this is the Toolkit's own checkout, not a card's code repository." -Hint "Pass the pull request: $(Get-CliPrefix)GetPRComments <PullRequestId>, or -BranchName <branch>."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $BranchName = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $BranchName -or $BranchName -eq 'HEAD') {
            Write-CliError -Message "No PullRequestId or BranchName provided, and could not detect current branch." -Hint "Usage: $(Get-CliPrefix)GetPRComments <PullRequestId>  or  $(Get-CliPrefix)GetPRComments -Help"
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        Write-Host "Detected branch: $BranchName" -ForegroundColor DarkGray
    }

    $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
    if (-not $tokenRead.Ok) {
        Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $headers = Get-P20AdoHeaders -Token $tokenRead.Token
    $encodedProject = [Uri]::EscapeDataString($Project)
    $userSpecifiedProject = $PSBoundParameters.ContainsKey('Project')

    $prTitle = ""

    if (-not $PullRequestId) {
        Write-Host "Looking up PR for branch: $BranchName..." -ForegroundColor DarkGray

        if ($userSpecifiedProject) {
            # User specified project -- search only that one
            $prListUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests?searchCriteria.sourceRefName=refs/heads/$BranchName&api-version=7.1"
            try {
                $prList = Invoke-RestMethod -Uri $prListUri -Headers $headers -Method Get
            }
            catch {
                Write-CliError -Message "Failed to query PRs for branch '$BranchName' in $Project/$Repository." -Hint $_.Exception.Message
                [void](Show-P20AdoForbiddenHint $_ -Org $org)
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
            if ($prList.count -eq 0) {
                Write-CliError -Message "No PR found for branch '$BranchName' in $Project/$Repository." -Hint "Push your branch and create a PR first, or pass -PullRequestId directly."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
            $PullRequestId = $prList.value[0].pullRequestId
            $prTitle = $prList.value[0].title
        }
        else {
            # Search all configured projects for this branch
            $allProjects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo } })
            $foundPR = $false
            $lastForbidden = $null
            foreach ($proj in $allProjects) {
                $tryEncoded = [Uri]::EscapeDataString($proj.Name)
                $tryUri = "$org/$tryEncoded/_apis/git/repositories/$($proj.Repo)/pullRequests?searchCriteria.sourceRefName=refs/heads/$BranchName&api-version=7.1"
                try {
                    $prList = Invoke-RestMethod -Uri $tryUri -Headers $headers -Method Get
                    if ($prList.count -gt 0) {
                        $PullRequestId = $prList.value[0].pullRequestId
                        $prTitle = $prList.value[0].title
                        $Project = $proj.Name
                        $Repository = $proj.Repo
                        $encodedProject = $tryEncoded
                        $foundPR = $true
                        break
                    }
                }
                catch {
                    # Remember a 401 or 403 so we can distinguish "no access" from "no PR".
                    $status = Get-P20AdoHttpStatus $_
                    if ($status -eq 401 -or $status -eq 403) { $lastForbidden = $_ }
                    # Skip this project, try next
                }
            }
            if (-not $foundPR) {
                if ($lastForbidden) {
                    Write-CliError -Message "Could not query PRs - access denied for branch '$BranchName'."
                    [void](Show-P20AdoForbiddenHint $lastForbidden -Org $org)
                    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
                }
                $projNames = ($allProjects | ForEach-Object { $_.Name }) -join ', '
                Write-CliError -Message "No PR found for branch '$BranchName' in any configured project ($projNames)." -Hint "Push your branch and create a PR first, or pass -PullRequestId directly."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
        }
        Write-Host "Found PR #$($PullRequestId): $prTitle ($Project / $Repository)" -ForegroundColor Green
    }

    # --- Resolve PR project/repo via org-level endpoint ---
    if (-not $PSBoundParameters.ContainsKey('Project')) {
        try {
            $prLookupUri = "$org/_apis/git/pullrequests/$($PullRequestId)?api-version=7.1"
            $prInfo = Invoke-RestMethod -Uri $prLookupUri -Headers $headers -Method Get
            $Repository = $prInfo.repository.name
            $prRepoProjectName = $prInfo.repository.project.name
            if ($prRepoProjectName) { $Project = $prRepoProjectName }
            $encodedProject = [Uri]::EscapeDataString($Project)
            if (-not $prTitle) { $prTitle = $prInfo.title }
            if (-not $BranchName -and $prInfo.sourceRefName) {
                $BranchName = $prInfo.sourceRefName -replace '^refs/heads/', ''
            }
            Write-Host "PR #$($PullRequestId): $prTitle ($Project / $Repository)" -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 404) {
                Write-Host "Error: PR #$($PullRequestId) not found. Check the PR ID." -ForegroundColor Red
            }
            else {
                Write-CliError -Message "Failed to look up PR #$($PullRequestId)." -Hint $_.Exception.Message
                [void](Show-P20AdoForbiddenHint $_ -Org $org)
            }
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }

    # --- Fetch Threads ---
    Write-Host "Fetching threads for PR #$($PullRequestId)..." -ForegroundColor DarkGray
    $threadsUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$PullRequestId/threads?api-version=7.1"
    try {
        $response = Invoke-RestMethod -Uri $threadsUri -Headers $headers -Method Get
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Error: PR #$($PullRequestId) not found in project '$Project/$Repository'." -ForegroundColor Red
        }
        else {
            Write-CliError -Message "Failed to fetch threads for PR #$($PullRequestId)." -Hint $_.Exception.Message
            [void](Show-P20AdoForbiddenHint $_ -Org $org)
        }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $allThreads = $response.value

    # --- Filter & Parse ---
    $actionableThreads = @($allThreads | Where-Object { Test-IsActionableThread $_ })

    # Non-actionable activity threads (votes / policy-status / PR-status events) carry a
    # CodeReviewThreadType. They never enter the triage list, but we record their IDs in the
    # file so re-running {cliPrefix}GetPRComments dedups them instead of re-surfacing them every time.
    $systemThreadIds = @($allThreads |
            Where-Object { $_.properties -and $_.properties.CodeReviewThreadType } |
            ForEach-Object { [int]$_.id } | Sort-Object -Unique)

    Write-Host "Found $($actionableThreads.Count) actionable thread(s) out of $($allThreads.Count) total." -ForegroundColor Cyan

    # --- Resolve output target (before early exit, so we can write PR URL) ---
    $targetFile = $null

    if ($OutputFile) {
        $targetFile = $OutputFile
    }
    else {
        $folders = Get-PromptFolders
        $currentDir = $folders.Current

        if ($currentDir -and (Test-Path $currentDir)) {
            $workItemIds = @()
            try {
                $wiUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$PullRequestId/workitems?api-version=7.1"
                $wiResponse = Invoke-RestMethod -Uri $wiUri -Headers $headers -Method Get
                $workItemIds = @($wiResponse.value | ForEach-Object { $_.id })
            }
            catch {
                Write-Host "Warning: Could not fetch linked work items. $($_.Exception.Message)" -ForegroundColor Yellow
            }

            if ($BranchName -match '/(\d{4,})[-/]') {
                $branchWiId = $Matches[1]
                if ($branchWiId -notin $workItemIds) { $workItemIds += $branchWiId }
            }

            if ($workItemIds.Count -gt 0) {
                Write-Host "Linked work item(s): $($workItemIds -join ', ')" -ForegroundColor DarkGray
                $promptFiles = Get-ChildItem -Path $currentDir -Filter "*.prompt.md" -File
                foreach ($wiId in $workItemIds) {
                    $match = $promptFiles | Where-Object { $_.Name -match "(^|[-.])(US-)?$wiId-" -or $_.Name -match "^Task$wiId-" }
                    if ($match) {
                        $targetFile = $match[0].FullName
                        Write-Host "Matched prompt file: $($match[0].Name)" -ForegroundColor Green
                        break
                    }
                }
            }
        }
    }

    if ($actionableThreads.Count -eq 0) {
        # Design: writing "PR URL:" to the prompt file is what causes {cliPrefix}Status to flip the card
        # from In Progress → Code Review. Clicking fetch after creating a PR is the intentional
        # trigger for that transition — even with no comments yet. The PR URL is the state gate.
        if ($targetFile -and (Test-Path $targetFile)) {
            $fileContent = Get-Content -Path $targetFile -Raw
            $prUrl = "$org/$encodedProject/_git/$Repository/pullrequest/$PullRequestId"
            if ($fileContent -notmatch [regex]::Escape($script:Consts.tokens.prUrl)) {
                # Through the one card writer: it keeps the file's line endings.
                Write-CardText -Path $targetFile -Content ($fileContent.TrimEnd("`r", "`n") + "`n`n$($script:Consts.tokens.prUrl) $prUrl`n")
                Write-Host "Wrote PR URL to $($targetFile | Split-Path -Leaf)" -ForegroundColor Green
            }
        }
        Write-Host "No actionable comments to process." -ForegroundColor Yellow
        exit 0
    }

    # --- Dedup: by COMMENT, not by thread ---
    # Re-running {cliPrefix}GetPRComments must be idempotent -- a comment the card already holds is
    # never written again -- and it must also be COMPLETE: a comment the card does not hold is
    # written, even when its thread is an old one. Get-P20RecordedComments reads what the card
    # has; Get-P20ThreadDelta says what each thread adds.
    $fileContent = ""
    if ($targetFile -and (Test-Path $targetFile)) {
        $fileContent = Get-Content -Path $targetFile -Raw
    }
    $recordedComments = Get-P20RecordedComments -FileContent $fileContent
    $existingThreadIds = @($recordedComments.Keys | ForEach-Object { [int]$_ } | Sort-Object -Unique)
    if ($existingThreadIds.Count -gt 0) {
        Write-Host "Found $($existingThreadIds.Count) existing thread(s) in file." -ForegroundColor DarkGray
    }

    # One entry per thread that has something to add. $newThreads keeps its name and its
    # meaning for the summary lines below: threads with at least one comment to write.
    $deltas = @()
    foreach ($thread in $actionableThreads) {
        $delta = Get-P20ThreadDelta -Thread $thread -Recorded $recordedComments
        if ($delta.Kind -eq 'known') { continue }
        $deltas += [PSCustomObject]@{ Thread = $thread; Delta = $delta }
    }
    $newThreads = @($deltas | Where-Object { $_.Delta.Kind -eq 'new' })
    $followUpThreads = @($deltas | Where-Object { $_.Delta.Kind -eq 'follow-up' })
    $skippedCount = $actionableThreads.Count - $deltas.Count

    if ($deltas.Count -eq 0) {
        Write-Host "No new comments -- all $($actionableThreads.Count) thread(s), and every reply in them, already in file." -ForegroundColor Yellow
        exit 0
    }

    if ($skippedCount -gt 0 -or $followUpThreads.Count -gt 0) {
        Write-Host "New threads: $($newThreads.Count); threads with new replies: $($followUpThreads.Count) (skipped $skippedCount with nothing new)" -ForegroundColor Cyan
    }

    # --- Determine round number and starting comment number from existing file ---
    $isFirstRun = $existingThreadIds.Count -eq 0
    $roundNum = 1
    $commentNum = 0
    if (-not $isFirstRun -and $fileContent) {
        # Find highest round number and increment
        $roundMatches = [regex]::Matches($fileContent, 'Round:\s*(\d+)')
        if ($roundMatches.Count -gt 0) {
            $roundNum = [int]$roundMatches[$roundMatches.Count - 1].Groups[1].Value + 1
        }
        # Find highest comment number and continue from there
        $commentMatches = [regex]::Matches($fileContent, '### Comment (\d+)')
        if ($commentMatches.Count -gt 0) {
            $commentNum = [int]$commentMatches[$commentMatches.Count - 1].Groups[1].Value
        }
    }

    # --- Format Markdown ---
    $md = @()
    $md += ""
    $prUrl = "$org/$encodedProject/_git/$Repository/pullrequest/$PullRequestId"

    $heading = $script:Consts.tokens.prReviewHeading
    if ($isFirstRun) {
        $md += "$heading (PR $PullRequestId)"
    }
    else {
        $md += "$heading -- Round $roundNum (PR $PullRequestId)"
    }
    if ($prTitle) { $md += "PR: $prTitle" }
    $md += "$($script:Consts.tokens.prUrl) $prUrl"
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $md += "Fetched: $timestamp"
    if ($isFirstRun) {
        $md += "Context: (fill in one-liner)"
    }
    $md += "Round: $roundNum"
    if (-not $isFirstRun) {
        $md += "New threads: $($newThreads.Count); threads with new replies: $($followUpThreads.Count) (skipped $skippedCount with nothing new)"
    }
    # Record non-actionable activity-thread IDs not already in the file, in (Thread N) form so
    # the dedup regex catches them next run. Keeps votes/policy/status out of triage for good.
    $newSystemIds = @($systemThreadIds | Where-Object { $_ -notin $existingThreadIds })
    if ($newSystemIds.Count -gt 0) {
        $md += "Non-actionable threads (votes / policy / status -- recorded for dedup, not for triage): " +
            (($newSystemIds | ForEach-Object { "(Thread $_)" }) -join ' ')
    }
    $md += ""
    # Inject workflow reference if not already present -- the agent loads it as context
    # when the prompt runs. The hop is computed, not hardcoded: the card lives in the
    # hub and the workflow ships with the package, so "../../agentic/..." was only ever
    # right while both sat in one repo -- and computing it ONCE, at write time, was
    # only ever right until the hub or the package moved.
    if ($fileContent -notmatch 'ado-comments') {
        $cardDir = if ($targetFile) { Split-Path $targetFile -Parent } else { $null }
        $md += (New-P20WorkflowLine -CardDirectory $cardDir)
        $md += ""
    }

    # One block per COMMENT, in the heading shape every reader already parses
    # ("### Comment N (Thread T)" -- the agent splits on it, the web UI lists by it). A
    # follow-up is a triage item in its own right: it gets its own Decision and its own
    # Reply slot, because "that fix is not enough" needs an answer of its own.
    $blocksWritten = 0
    foreach ($entry in $deltas) {
        $thread = $entry.Thread
        $file = if ($thread.threadContext -and $thread.threadContext.filePath) { $thread.threadContext.filePath } else { "(no file)" }
        $line = if ($thread.threadContext -and $thread.threadContext.rightFileStart) { $thread.threadContext.rightFileStart.line } else { "-" }
        $status = $thread.status
        $threadId = $thread.id

        $toWrite = @()
        if ($entry.Delta.Opener) { $toWrite += [PSCustomObject]@{ Item = $entry.Delta.Opener; FollowUp = $false } }
        foreach ($f in @($entry.Delta.FollowUps)) { $toWrite += [PSCustomObject]@{ Item = $f; FollowUp = $true } }

        foreach ($w in $toWrite) {
            $commentNum++
            $blocksWritten++
            $thisComment = $w.Item.Comment
            $author = $thisComment.author.displayName
            $content = $thisComment.content
            $publishedDate = if ($thisComment.publishedDate) { $thisComment.publishedDate } else { "" }

            # Detect PR Assistant bot
            $isBot = $content -match 'PR Assistant|AI Code Review'

            # Extract category and severity from PR Assistant HTML badges
            $category = ""
            $severity = ""
            if ($isBot) {
                $author = "PR Assistant (AI Code Review)"
                if ($content -match 'Reliability:\s*([^<]+)<') { $category = $Matches[1].Trim() }
                if ($content -match 'Severity</span><[^>]+>([^<]+)<') { $severity = $Matches[1].Trim() }
            }

            # Extract the actual comment text (strip HTML for bot comments)
            $commentText = $content
            if ($isBot) {
                if ($content -match '(?s)</small>\s*\n\s*\n(.+?)(?:\nHere is the suggested code:|<small class="secondary-text">)') {
                    $commentText = $Matches[1].Trim()
                }
            }
            # Collapse to single line for display
            $commentText = ($commentText -replace "`r`n|`n", " ").Trim()

            # Extract code suggestion
            $codeSuggestion = ""
            if ($content -match '(?s)```\s*\n(.+?)\n```') {
                $codeSuggestion = $Matches[1].Trim()
            }

            $md += "### Comment $commentNum (Thread $threadId)"
            if ($w.FollowUp) {
                # The token is what Get-P20RecordedComments reads next run. It is the
                # ONLY thing that makes a follow-up idempotent, so it is written in one
                # exact shape and nowhere else.
                $md += "Follow-up: (Thread $threadId / Comment $($w.Item.Id)) -- a later comment in this thread"
            }
            $reviewerLine = $author
            if ($severity) { $reviewerLine += " -- Severity: $severity" }
            if ($category) { $reviewerLine += " -- Category: $category" }
            $md += "Line: ``$file`` L$line"
            $md += "Reviewer/Bot: $reviewerLine"
            if ($publishedDate) { $md += "Published: $publishedDate" }
            $md += "Status: $status"
            $md += "Comment: $commentText"
            if ($codeSuggestion) {
                $md += "Code suggestion:"
                $md += '```'
                $md += $codeSuggestion
                $md += '```'
            }
            else {
                $md += "Code suggestion: (none)"
            }
            $md += "Decision: take / reject / modify"
            $md += "Reply: "
            $md += ""
            $md += "---"
            $md += ""
        }
    }

    if ($isFirstRun) {
        $md += "## Carry forward"
        $md += "- [ ] (pending review decisions)"
    }

    $output = $md -join "`n"
    $newCount = $blocksWritten

    # --- Write or print ---
    if ($targetFile) {
        # Appended through the one card writer -- Add-Content wrote a bare-LF
        # tail onto a CRLF card.
        $existingText = ''
        if (Test-Path $targetFile) { $existingText = [System.IO.File]::ReadAllText($targetFile) }
        if ($existingText -and -not $existingText.EndsWith("`n")) { $existingText += "`n" }
        Write-CardText -Path $targetFile -Content ($existingText + $output + "`n")
        Write-Host ""
        Write-Host "Appended $newCount new comment(s) to $targetFile" -ForegroundColor Green
    }
    else {
        if (-not $OutputFile) {
            Write-Host ""
            Write-Host "Warning: No matching prompt file found in current/. Printing to console." -ForegroundColor Yellow
            Write-Host "  Use -OutputFile <path> to write to a specific file." -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host $output
        Write-Host ""
    }

    # --- Write canonical pr-comments record ---
    # One file per PR fetch in <org>/pr-comments/ so prsReviewed stat is countable at archive time.
    # -OutputFile names the only file a redirected run writes, so it writes no side record.
    if ($OutputFile) {
        Write-Host "Side record skipped: -OutputFile names the only file this run writes." -ForegroundColor DarkGray
    }
    else {
        Write-P20PRCommentsRecord -PullRequestId $PullRequestId -Title $prTitle -Url $prUrl -Repository $Repository -Count $newCount
    }

}
catch {
    Write-CliError -Message $_.Exception.Message -Hint "Use '$(Get-CliPrefix)GetPRComments -Help' for usage information."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
