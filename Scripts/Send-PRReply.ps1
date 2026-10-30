<#
.SYNOPSIS
    Posts a reply to a specific PR thread -- Azure DevOps, or GitHub through gh.

.DESCRIPTION
    Posts a comment reply to an existing thread and optionally updates thread status (active/fixed/closed).
    Reads org/project/repo from toolkit config by default -- override with parameters.

    On a GitHub Space (every call through Invoke-P20TrackerRead; every body as
    a JSON file, never in argv or the URL):
    1. -Status is checked FIRST. GitHub keeps only resolved / unresolved:
       fixed and closed resolve the thread, active reopens it; byDesign,
       pending and wontFix have no equivalent and are refused, nothing posted.
    2. The repository: the card whose PR URL: line names the pull request,
       -Repository, this checkout's GitHub remote, the board's one repo
       (Resolve-P20GitHubPRRepo, the one GetPRComments uses).
    3. What -ThreadId is -- GetPRComments' thread id is an inline review
       comment, a conversation-tab comment or a review's summary.
    4. The reply. Inline: REST, pulls/<n>/comments/<root>/replies, into the
       thread. Conversation or summary: GitHub has no reply to those, so a
       new comment on the pull request, opening with a link to the one it
       answers.
    5. The status, inline threads only: GraphQL, because REST has no thread
       status. The thread's node id is looked up from the root comment's REST
       id (reviewThreads, paginated), then resolveReviewThread or
       unresolveReviewThread.
    6. The card's Reply: slot, as on Azure DevOps.

.PARAMETER PullRequestId
    The PR number (positional).

.PARAMETER ThreadId
    The thread ID to reply to (positional). A [long]: GitHub's ids are past 32 bits.

.PARAMETER Reply
    The reply text (supports markdown).

.PARAMETER Status
    Optional. Set thread status after replying: active, fixed, closed, byDesign, pending, wontFix.
    On GitHub: fixed and closed resolve, active reopens; the other three are refused.

.PARAMETER Repository
    ADO repository name. Default: from toolkit config. On GitHub: <owner>/<name>, or <name>
    under the Space's owner.

.PARAMETER Project
    ADO project name. Default: from toolkit config. On GitHub: the owner, when -Repository
    is a bare name.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    Send-P20PRReply -PullRequestId 140123 -ThreadId 1342185 -Reply "Good catch -- fixed in abc1234." -Status fixed

.NOTES
    Depends on: az cli (for access token), ADO REST API v7.1 -- or, on a GitHub Space, gh
    Config: reads org/project/repo from $global:P20Config
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$PullRequestId,

    [Parameter(Position = 1)]
    [long]$ThreadId,

    [Parameter()]
    [string]$Reply,

    [Parameter()]
    [ValidateSet('active', 'fixed', 'closed', 'byDesign', 'pending', 'wontFix')]
    [string]$Status,

    [Parameter()]
    [string]$Repository,

    [Parameter()]
    [string]$Project,

    [Parameter()]
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')


# ── Help ─────────────────────────────────────────────────────────────────────
function Show-Help {
    Write-Host @"

Send-P20PRReply - Post a reply to a PR thread (Azure DevOps, or GitHub through gh)

USAGE:
    $(Get-CliPrefix)ReplyPR <PullRequestId> <ThreadId> -Reply "text" [-Status fixed]

PARAMETERS:
    -PullRequestId <int>   PR number (positional, required).
    -ThreadId <long>       Thread ID to reply to (positional, required) -- the
                           (Thread N) GetPRComments wrote on the card.
    -Reply <string>        Reply text -- supports markdown (required).
    -Status <string>       Set thread status: active, fixed, closed, byDesign, pending, wontFix.
    -Repository <string>   ADO repo name. Default: from toolkit config.
                           On GitHub: <owner>/<name>, or <name> under the Space's owner.
    -Project <string>      ADO project name. Default: from toolkit config.
    -Help                  Show this help message.

ON GITHUB:
    A thread is only resolved or unresolved. -Status fixed or closed resolves
    it, active reopens it; byDesign, pending and wontFix have no equivalent and
    are refused before anything is posted. A conversation comment or a review
    summary has no thread: the reply is a new comment on the pull request, and
    -Status is not applied.

EXAMPLES:
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "Good catch -- fixed in abc1234." -Status fixed
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "By design -- this is intentional." -Status byDesign
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "Will address in follow-up." -Status pending
    $(Get-CliPrefix)ReplyPR 12 2412345678 -Reply "Fixed in abc1234." -Status fixed   # GitHub: reply, then resolve

"@ -ForegroundColor Cyan
    exit 0
}

if ($Help) { Show-Help }

# ── Config ───────────────────────────────────────────────────────────────────
$cfg = $global:P20Config
if (-not $cfg) {
    Write-CliError -Message "Toolkit config not loaded. Is utilities.psm1 imported?"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$org = $cfg.Org

# WHICH tracker answers follows the board's address (D-G4), as in GetPRComments.
# The GitHub path resolves its own repository below; the ADO defaults are ADO's.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
$trackerKind = Resolve-P20Tracker -OrgUrl $org

$userSpecifiedProject = $PSBoundParameters.ContainsKey('Project')
$userSpecifiedRepo = $PSBoundParameters.ContainsKey('Repository')
if ($trackerKind -ne 'github' -and (-not $Project -or -not $Repository)) {
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
        } else {
            $Repository = $projects[0].Repo
        }
    }
}

# ── Validate required params ─────────────────────────────────────────────────
if (-not $PullRequestId) {
    Write-CliError -Message "-PullRequestId is required." -Hint "Usage: $(Get-CliPrefix)ReplyPR <PullRequestId> <ThreadId> -Reply ""text""  or  $(Get-CliPrefix)ReplyPR -Help"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not $ThreadId) {
    Write-CliError -Message "-ThreadId is required." -Hint "Usage: $(Get-CliPrefix)ReplyPR <PullRequestId> <ThreadId> -Reply ""text""  or  $(Get-CliPrefix)ReplyPR -Help"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not $Reply) {
    Write-CliError -Message "-Reply is required." -Hint "Usage: $(Get-CliPrefix)ReplyPR <PullRequestId> <ThreadId> -Reply ""text""  or  $(Get-CliPrefix)ReplyPR -Help"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$ErrorActionPreference = 'Stop'

# What the card's Reply: slot is filled under, whichever tracker answered: the
# thread the card knows (on GitHub, an inline thread's ROOT comment) and the
# word its Status: line takes ('' leaves the line as it is).
$cardThreadId = $ThreadId
$cardStatus = $Status
$ghRepoFull = ''

# -- A GitHub Space: gh answers, then the SHARED tail (the card's Reply: slot).
if ($trackerKind -eq 'github') {
    . (Join-Path $PSScriptRoot 'Read-GitHubPRThreads.ps1')
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
    Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org

    # 1. The status, before anything is posted: a refused status posts nothing.
    $statusPlan = Get-P20GitHubReplyStatus -Status $Status
    if ($statusPlan.Error) {
        Write-CliError -Message $statusPlan.Error -Hint $statusPlan.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    try {
        # 2. The repository -- the one answer GetPRComments uses.
        $currentDir = $null
        if (Get-Command Get-PromptFolders -ErrorAction SilentlyContinue) { $currentDir = (Get-PromptFolders).Current }
        $where = Resolve-P20GitHubPRRepo -PullRequestId $PullRequestId -Repository $Repository -Project $Project `
            -OrgUrl $org -Projects $cfg.Projects -CurrentDir $currentDir -Token (Get-P20Consts).tokens.prUrl `
            -ToolkitRoot (Split-Path -Parent $PSScriptRoot) -Verb 'ReplyPR'
        if ($where.Error) {
            # A write: the same number on the wrong repository is somebody
            # else's pull request. Nothing is guessed.
            Write-CliError -Message $where.Error -Hint $where.Hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $ghRepoFull = $where.Repo

        # 3. What the id is. GetPRComments' thread ids are GitHub's own, of one
        #    of three kinds, and each kind is answered differently.
        $lookups = @{}
        foreach ($part in @(
                @{ Key = 'review'; Path = "repos/$ghRepoFull/pulls/comments/$ThreadId" },
                @{ Key = 'issue'; Path = "repos/$ghRepoFull/issues/comments/$ThreadId" },
                @{ Key = 'summary'; Path = "repos/$ghRepoFull/pulls/$PullRequestId/reviews/$ThreadId" })) {
            $read = Invoke-P20TrackerRead 'gh' @('api', $part.Path)
            $lookups[$part.Key] = $null
            if ($read.Code -eq 0) {
                $lookups[$part.Key] = (@($read.Out) -join "`n") | ConvertFrom-Json
                $kind = Get-P20GitHubCommentKind -Number $PullRequestId -ReviewComment $lookups['review'] -IssueComment $lookups['issue'] -Review $lookups['summary']
                if ($kind) { break }
            }
            elseif ((@($read.Lines) -join ' ') -notmatch '404|Not Found') {
                Write-CliError -Message "Could not read comment $ThreadId on $ghRepoFull -- $((@($read.Lines) -join ' ').Trim())" -Hint "Nothing was posted. Check gh auth status, or $(Get-CliPrefix)Log -Errors."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
        }
        $kind = Get-P20GitHubCommentKind -Number $PullRequestId -ReviewComment $lookups['review'] -IssueComment $lookups['issue'] -Review $lookups['summary']
        if (-not $kind) {
            Write-CliError -Message "PR #$PullRequestId on $ghRepoFull has no review comment, conversation comment or review $ThreadId." `
                -Hint "Nothing was posted. The id is the (Thread N) $(Get-CliPrefix)GetPRComments $PullRequestId wrote on the card."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }

        # On stage: a public repository's reply is read by strangers. One line
        # after the reads and before the write; nothing is asked.
        . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
        Write-P20PublicLine -Repo $ghRepoFull

        # 4. The reply.
        if ($kind.Kind -eq 'review') {
            $post = Invoke-P20GhApiWrite "repos/$ghRepoFull/pulls/$PullRequestId/comments/$($kind.Root)/replies" ([ordered]@{ body = $Reply })
        }
        else {
            # The conversation tab has no "reply to": a new comment that says
            # which one it answers.
            $lead = "In reply to $($kind.Url):"
            if (-not $kind.Url) { $lead = "In reply to comment $($kind.Root):" }
            $post = Invoke-P20GhApiWrite "repos/$ghRepoFull/issues/$PullRequestId/comments" ([ordered]@{ body = "$lead`n`n$Reply" })
        }
        if ($post.Code -ne 0) {
            Write-CliError -Message "Could not post the reply to $ThreadId on $ghRepoFull PR #$PullRequestId -- $((@($post.Lines) -join ' ').Trim())" -Hint "Check gh auth status, or $(Get-CliPrefix)Log -Errors."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $posted = (@($post.Out) -join "`n") | ConvertFrom-Json
        if ($kind.Kind -eq 'review') {
            Write-Host "Reply posted to thread $($kind.Root) (comment ID: $($posted.id))" -ForegroundColor Green
        }
        else {
            Write-Host "Reply posted on PR #$PullRequestId's conversation, answering $($kind.Kind) $($kind.Root) (comment ID: $($posted.id))" -ForegroundColor Green
        }
        $cardThreadId = $kind.Root
        $cardStatus = ''

        # 5. The status: inline threads only, through GraphQL.
        if ($statusPlan.Action -and $kind.Kind -ne 'review') {
            Write-Host "-Status $Status not applied: on GitHub a $(if ($kind.Kind -eq 'summary') { 'review summary' } else { 'conversation comment' }) has no thread to resolve. The reply is posted." -ForegroundColor Yellow
        }
        elseif ($statusPlan.Action) {
            # GraphQL resolves a thread by its node id, which REST never shows:
            # find the thread whose first comment is the root, a page at a time.
            # Every value is a variable (-f / -F), so the query has no quote in it.
            $ghOwner, $ghName = $ghRepoFull.Split('/', 2)
            $findQuery = 'query($owner: String!, $name: String!, $number: Int!, $cursor: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
            $node = $null
            $cursor = ''
            $failed = ''
            for ($page = 0; $page -lt 50 -and -not $node; $page++) {
                $gqlArgs = @('api', 'graphql', '-f', "query=$findQuery", '-f', "owner=$ghOwner", '-f', "name=$ghName", '-F', "number=$PullRequestId")
                if ($cursor) { $gqlArgs += @('-f', "cursor=$cursor") }
                $gql = Invoke-P20TrackerRead 'gh' $gqlArgs
                if ($gql.Code -ne 0) { $failed = (@($gql.Lines) -join ' ').Trim(); break }
                $threads = ((@($gql.Out) -join "`n") | ConvertFrom-Json).data.repository.pullRequest.reviewThreads
                $node = Find-P20GitHubReviewThreadNode -Nodes $threads.nodes -RootId $kind.Root
                if ($node -or -not $threads.pageInfo.hasNextPage) { break }
                $cursor = [string]$threads.pageInfo.endCursor
            }
            $wantResolved = ($statusPlan.Action -eq 'resolveReviewThread')
            if ($failed) {
                Write-Host "Warning: Reply posted, but the thread could not be looked up to set '$Status': $failed" -ForegroundColor Yellow
            }
            elseif (-not $node) {
                Write-Host "Warning: Reply posted, but no review thread on PR #$PullRequestId starts with comment $($kind.Root); '$Status' not applied." -ForegroundColor Yellow
            }
            elseif ([bool]$node.isResolved -eq $wantResolved) {
                Write-Host "Thread $($kind.Root) is already $($statusPlan.Word)." -ForegroundColor DarkGray
                $cardStatus = $statusPlan.Word
            }
            else {
                $mutation = 'mutation($threadId: ID!) { ' + $statusPlan.Action + '(input: {threadId: $threadId}) { thread { isResolved } } }'
                $set = Invoke-P20TrackerRead 'gh' @('api', 'graphql', '-f', "query=$mutation", '-f', "threadId=$($node.id)")
                if ($set.Code -ne 0) {
                    Write-Host "Warning: Reply posted, but failed to set thread $($kind.Root) to $($statusPlan.Word): $((@($set.Lines) -join ' ').Trim())" -ForegroundColor Yellow
                }
                else {
                    Write-Host "Thread $($kind.Root) $($statusPlan.Word) ('$Status')" -ForegroundColor Green
                    $cardStatus = $statusPlan.Word
                }
            }
        }
    }
    catch {
        Write-CliError -Message $_.Exception.Message -Hint "Use '$(Get-CliPrefix)ReplyPR -Help' for usage information."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
else {

# ── Main ─────────────────────────────────────────────────────────────────────
try {
    # Auth
    . (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
    $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
    if (-not $tokenRead.Ok) {
        Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $headers = Get-P20AdoHeaders -Token $tokenRead.Token

    # Auto-resolve project/repo from PR ID if user didn't specify
    if (-not $userSpecifiedProject -and -not $userSpecifiedRepo) {
        $orgLevelUri = "$org/_apis/git/pullrequests/$($PullRequestId)?api-version=7.1"
        try {
            $prInfo = Invoke-RestMethod -Uri $orgLevelUri -Headers $headers -Method Get
            $resolvedRepo = $prInfo.repository.name
            $resolvedProject = $prInfo.repository.project.name
            if ($resolvedProject -and $resolvedRepo) {
                $Project = $resolvedProject
                $Repository = $resolvedRepo
                Write-Host "Resolved PR #$PullRequestId to $Project/$Repository" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "Warning: Could not auto-resolve project from PR ID, using default: $Project/$Repository" -ForegroundColor Yellow
        }
    }

    $encodedProject = [Uri]::EscapeDataString($Project)

    # Post reply
    $commentBody = @{ content = $Reply; parentCommentId = 1 } | ConvertTo-Json
    $commentUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$PullRequestId/threads/$ThreadId/comments?api-version=7.1"
    try {
        $result = Invoke-RestMethod -Uri $commentUri -Headers $headers -Method Post -Body $commentBody
        Write-Host "Reply posted to thread $ThreadId (comment ID: $($result.id))" -ForegroundColor Green
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-CliError -Message "Thread $ThreadId not found on PR #$($PullRequestId) in project '$Project'." -Hint "Check the PR ID and thread ID (shown in $(Get-CliPrefix)GetPRComments output)."
        } else {
            Write-CliError -Message "Failed to post reply to thread $ThreadId." -Hint $_.Exception.Message
        }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    # Update status if requested
    if ($Status) {
        $statusMap = @{
            active   = 1
            fixed    = 2
            wontFix  = 3
            closed   = 4
            byDesign = 5
            pending  = 6
        }
        $numericStatus = $statusMap[$Status]
        if (-not $numericStatus) {
            Write-Host "Warning: Unknown status '$Status'. Valid values: $($statusMap.Keys -join ', ')" -ForegroundColor Yellow
        } else {
            $statusBody = @{ status = $numericStatus } | ConvertTo-Json
            $threadUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$PullRequestId/threads/$($ThreadId)?api-version=7.1"
            try {
                Invoke-RestMethod -Uri $threadUri -Headers $headers -Method Patch -Body $statusBody | Out-Null
                Write-Host "Thread $ThreadId status set to '$Status'" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Reply posted, but failed to update thread status to '$Status'." -ForegroundColor Yellow
                Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
    }
} catch {
    Write-CliError -Message $_.Exception.Message -Hint "Use '$(Get-CliPrefix)ReplyPR -Help' for usage information."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

}
# -- end of the ADO else; both trackers land here with $cardThreadId and
# $cardStatus set --

# -- The card is the record: fill the thread's Reply: slot ------------------------
# The reply is with the tracker; now it goes into the card the way GetPRComments
# would bring it back on the next fetch. The card is the one in current/ whose
# `PR URL:` names this pull request (or, failing that, the one the current
# branch names). Not finding one is said, not failed: the reply IS posted.
try {
    . (Join-Path $PSScriptRoot 'Set-CardReply.ps1')
    $card = $null
    $currentDir = $null
    if (Get-Command Get-PromptFolders -ErrorAction SilentlyContinue) { $currentDir = (Get-PromptFolders).Current }
    if ($currentDir -and (Test-Path $currentDir)) {
        # The PR URL line's shape is the contract's (consts.json regex.prUrlLine), not retyped here.
        . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
        if ($trackerKind -eq 'github') {
            # A GitHub URL names its repository: only a card naming THIS one.
            $hits = @(Find-P20CardsForGitHubPR -Folder @($currentDir) -Number $PullRequestId -Repo $ghRepoFull -Token (Get-P20Consts).tokens.prUrl |
                ForEach-Object { Get-Item -LiteralPath $_.Path })
        }
        else {
            $prNeedle = "pullrequest/$PullRequestId"
            $prLineRx = (Get-P20Consts).regex.prUrlLine + '\S*' + [regex]::Escape($prNeedle) + '\b'
            $hits = @(Get-ChildItem -Path $currentDir -Filter '*.prompt.md' -File | Where-Object {
                ([System.IO.File]::ReadAllText($_.FullName)) -match $prLineRx
            })
        }
        if ($hits.Count -eq 1) { $card = $hits[0].FullName }
        elseif ($hits.Count -eq 0) {
            . (Join-Path $PSScriptRoot 'Resolve-CardForBranch.ps1')
            $branch = "$((Invoke-P20TrackerRead 'git' @('rev-parse', '--abbrev-ref', 'HEAD')).Out)".Trim()
            if ($branch) { $card = Resolve-P20CardForBranch -Branch $branch -CurrentDir $currentDir }
        }
    }
    if ($card) {
        if (Set-P20CardReply -Path $card -ThreadId $cardThreadId -Reply $Reply -Status $cardStatus) {
            Write-Host "Recorded in $(Split-Path $card -Leaf): the reply is in the thread's Reply: slot." -ForegroundColor Green
        }
        else {
            Write-Host "Not recorded: $(Split-Path $card -Leaf) has no open Reply: slot for thread $cardThreadId -- run $(Get-CliPrefix)GetPRComments $PullRequestId to fetch the thread, and it will carry this reply." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Not recorded: no card in current/ names PR #$PullRequestId -- $(Get-CliPrefix)GetPRComments $PullRequestId brings the reply into the card on the next fetch." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Reply posted, but it could not be written into the card: $($_.Exception.Message)" -ForegroundColor Yellow
}
