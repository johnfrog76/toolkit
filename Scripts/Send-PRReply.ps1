<#
.SYNOPSIS
    Posts a reply to a specific PR thread in Azure DevOps.

.DESCRIPTION
    Posts a comment reply to an existing thread and optionally updates thread status (active/fixed/closed).
    Reads org/project/repo from toolkit config by default -- override with parameters.

.PARAMETER PullRequestId
    The PR number (positional).

.PARAMETER ThreadId
    The thread ID to reply to (positional).

.PARAMETER Reply
    The reply text (supports markdown).

.PARAMETER Status
    Optional. Set thread status after replying: active, fixed, closed, byDesign, pending, wontFix.

.PARAMETER Repository
    ADO repository name. Default: from toolkit config.

.PARAMETER Project
    ADO project name. Default: from toolkit config.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    Send-P20PRReply -PullRequestId 140123 -ThreadId 1342185 -Reply "Good catch -- fixed in abc1234." -Status fixed

.NOTES
    Depends on: az cli (for access token), ADO REST API v7.1
    Config: reads org/project/repo from $global:P20Config
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$PullRequestId,

    [Parameter(Position = 1)]
    [int]$ThreadId,

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


# ── Help ─────────────────────────────────────────────────────────────────────
function Show-Help {
    Write-Host @"

Send-P20PRReply - Post a reply to a PR thread in Azure DevOps

USAGE:
    $(Get-CliPrefix)ReplyPR <PullRequestId> <ThreadId> -Reply "text" [-Status fixed]

PARAMETERS:
    -PullRequestId <int>   PR number (positional, required).
    -ThreadId <int>        Thread ID to reply to (positional, required).
    -Reply <string>        Reply text -- supports markdown (required).
    -Status <string>       Set thread status: active, fixed, closed, byDesign, pending, wontFix.
    -Repository <string>   ADO repo name. Default: from toolkit config.
    -Project <string>      ADO project name. Default: from toolkit config.
    -Help                  Show this help message.

EXAMPLES:
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "Good catch -- fixed in abc1234." -Status fixed
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "By design -- this is intentional." -Status byDesign
    $(Get-CliPrefix)ReplyPR 140123 1342185 -Reply "Will address in follow-up." -Status pending

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

$userSpecifiedProject = $PSBoundParameters.ContainsKey('Project')
$userSpecifiedRepo = $PSBoundParameters.ContainsKey('Repository')
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

# -- The card is the record: fill the thread's Reply: slot ------------------------
# The reply is with ADO; now it goes into the card the way GetPRComments would
# bring it back on the next fetch. The card is the one in current/ whose
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
        $prNeedle = "pullrequest/$PullRequestId"
        $prLineRx = (Get-P20Consts).regex.prUrlLine + '\S*' + [regex]::Escape($prNeedle) + '\b'
        $hits = @(Get-ChildItem -Path $currentDir -Filter '*.prompt.md' -File | Where-Object {
            ([System.IO.File]::ReadAllText($_.FullName)) -match $prLineRx
        })
        if ($hits.Count -eq 1) { $card = $hits[0].FullName }
        elseif ($hits.Count -eq 0) {
            . (Join-Path $PSScriptRoot 'Resolve-CardForBranch.ps1')
            $branch = "$(git rev-parse --abbrev-ref HEAD 2>$null)".Trim()
            if ($branch) { $card = Resolve-P20CardForBranch -Branch $branch -CurrentDir $currentDir }
        }
    }
    if ($card) {
        if (Set-P20CardReply -Path $card -ThreadId $ThreadId -Reply $Reply -Status $Status) {
            Write-Host "Recorded in $(Split-Path $card -Leaf): the reply is in the thread's Reply: slot." -ForegroundColor Green
        }
        else {
            Write-Host "Not recorded: $(Split-Path $card -Leaf) has no open Reply: slot for thread $ThreadId -- run $(Get-CliPrefix)GetPRComments $PullRequestId to fetch the thread, and it will carry this reply." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Not recorded: no card in current/ names PR #$PullRequestId -- $(Get-CliPrefix)GetPRComments $PullRequestId brings the reply into the card on the next fetch." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Reply posted, but it could not be written into the card: $($_.Exception.Message)" -ForegroundColor Yellow
}
