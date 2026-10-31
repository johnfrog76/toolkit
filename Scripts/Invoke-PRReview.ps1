<#
.SYNOPSIS
    Posts an AI code review to a pull request (up to 3 inline comments) -- Azure DevOps, or GitHub through gh.

.DESCRIPTION
    Gets the diff for a PR, sends it to Claude for review, and posts up to 3 findings as
    individual PR comment threads. Comments are formatted so $(Get-CliPrefix)GetPRComments picks them up
    as bot reviews and feeds them into the ado-comments triage flow.

    On a GitHub Space the diff comes from GitHub, not a checkout (gh api, the
    pull request as application/vnd.github.diff), the same model call reviews
    it, and the findings are posted as ONE review (event COMMENT) whose inline
    comments are positioned by path and new-side line -- the numbering the
    review prompt already asks for. A finding whose line is not in the diff
    is named in the review's body instead, as Azure DevOps falls back to a
    general comment. The repository: the card whose PR URL: line names the
    pull request, -Repository, this checkout's GitHub remote, the board's one
    repo -- the one answer GetPRComments uses.

    Requires ANTHROPIC_API_KEY environment variable.

.PARAMETER PullRequestId
    The PR number (positional). Omit to auto-detect from current branch.

.PARAMETER Repository
    ADO repository name. Default: from toolkit config. On GitHub: <owner>/<name>, or <name>
    under the Space's owner.

.PARAMETER Project
    ADO project name. Default: from toolkit config.

.PARAMETER Model
    Model id to send. Default: ai.model in config (config.default.json ships one;
    config.local.json overrides it) -- the same key the agent's suggest and rewrite
    routes read, so one setting names the model for every half.

.PARAMETER DryRun
    Print the review to console without posting to ADO.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    $(Get-CliPrefix)AddPRReview 1042
    $(Get-CliPrefix)AddPRReview           # auto-detect from current branch
    $(Get-CliPrefix)AddPRReview 1042 -DryRun

.NOTES
    Requires: az cli (ADO auth), git (for diff), ANTHROPIC_API_KEY env var -- or, on a GitHub
    Space, gh in place of az and git
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$PullRequestId,

    [Parameter()]
    [string]$Repository,

    [Parameter()]
    [string]$Project,

    [Parameter()]
    [string]$Model,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

function Get-P20ModelId {
    <#
      ai.model: the one provider profile. The module resolved it into
      $global:P20Config.AiModel; run bare, this script reads the shipped file
      beside the package, and only then falls back to the literal the agent's
      core/model.py also carries as its last resort.
    #>
    if ($global:P20Config -and $global:P20Config.AiModel) { return [string]$global:P20Config.AiModel }
    $shipped = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.default.json'
    if (Test-Path -LiteralPath $shipped) {
        try {
            $cfgJson = Get-Content -LiteralPath $shipped -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfgJson.ai -and $cfgJson.ai.model) { return [string]$cfgJson.ai.model }
        } catch { $null = $_ }
    }
    return 'claude-opus-5-5'
}


# -- Help ---------------------------------------------------------------------
function Show-Help {
    Write-Host @"

$(Get-CliPrefix)AddPRReview - Post an AI code review to a pull request (Azure DevOps, or GitHub through gh)

USAGE:
    $(Get-CliPrefix)AddPRReview <PullRequestId> [options]
    $(Get-CliPrefix)AddPRReview                              # auto-detect PR from current branch

PARAMETERS:
    -PullRequestId <int>   PR number (positional). Omit to detect from branch.
    -Repository <string>   ADO repo name. Default: from toolkit config.
                           On GitHub: <owner>/<name>, or <name> under the Space's owner.
    -Project <string>      ADO project name. Default: from toolkit config.
    -Model <string>        Model id. Default: ai.model in config ($(Get-P20ModelId)).
    -DryRun                Print review to console, do not post it.
    -Help                  Show this help.

REQUIRES:
    - ANTHROPIC_API_KEY in a .env beside this package (loaded on import), or in
      the environment. Copy .env.example to .env -- it lists every variable.
      Get your key at console.anthropic.com -- API Keys
    - az cli authenticated (same as every other ADO command)
    - Run from within the git repo (used to get the diff)
    - On a GitHub Space: gh signed in instead; no checkout is needed, the diff
      comes from GitHub

BEHAVIOR:
    Sends the PR diff to Claude, posts up to 3 inline comment threads.
    Comments appear as AI Code Review bot entries that $(Get-CliPrefix)GetPRComments picks up.
    On GitHub: one review with the findings as inline comments; a finding on
    a line the diff does not show is named in the review's body.

EXAMPLES:
    $(Get-CliPrefix)AddPRReview 1042
    $(Get-CliPrefix)AddPRReview 1042 -Model claude-sonnet-5-5
    $(Get-CliPrefix)AddPRReview 1042 -DryRun
    $(Get-CliPrefix)AddPRReview            # auto-detects from current branch

"@ -ForegroundColor Cyan
    exit 0
}

if ($Help) { Show-Help }

# -- Prereqs -------------------------------------------------------------------
# The model is config's, not this script's: ai.model, the one provider profile
# the CLI and the agent share. -Model still overrides it for one run.
if (-not $Model) { $Model = Get-P20ModelId }
$apiKey = $env:ANTHROPIC_API_KEY
if (-not $apiKey) { $apiKey = $env:CLAUDE_API_KEY }
if (-not $apiKey) {
    Write-CliError -Message "ANTHROPIC_API_KEY is not set." -Hint "Copy .env.example to .env beside the package, set ANTHROPIC_API_KEY=sk-ant-..., then reload the toolkit (re-import utilities.psm1)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

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

if ($trackerKind -ne 'github' -and (-not $Project -or -not $Repository)) {
    $projects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo } })
    if ($projects.Count -eq 0) {
        Write-CliError -Message "No projects configured for the active Space." -Hint "Pass -Project and -Repository, or add projects to the Space in hub.json."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not $Project)    { $Project    = $projects[0].Name }
    if (-not $Repository) {
        $match = $projects | Where-Object { $_.Name -eq $Project }
        $Repository = if ($match) { $match[0].Repo } else { $projects[0].Repo }
    }
}

$ErrorActionPreference = 'Stop'

# -- Auth ----------------------------------------------------------------------
# The token, the headers, the HTTP status and the 401/403 advice: one helper for
# every ADO script. The branch search and the PR fetch read the status the same way.
. (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

# -- Main ----------------------------------------------------------------------
try {
    # What the shared middle reads, whichever tracker answered: the diff, and
    # what it is a diff of.
    $diff = ''
    $diffOf = ''
    $ghRepoFull = ''

    # -- A GitHub Space: the diff from GitHub; the model call and the parse are
    # shared; the post is GitHub's own, below. The ADO body sits in the else,
    # unindented on purpose, as GetPRComments' does.
    if ($trackerKind -eq 'github') {
        . (Join-Path $PSScriptRoot 'Read-GitHubPRThreads.ps1')
        . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
        Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
        $currentDir = $null
        if (Get-Command Get-PromptFolders -ErrorAction SilentlyContinue) { $currentDir = (Get-PromptFolders).Current }
        $branchName = ''
        if (-not $PullRequestId) {
            $branchName = "$((Invoke-P20TrackerRead 'git' @('rev-parse', '--abbrev-ref', 'HEAD')).Out)".Trim()
            if (-not $branchName -or $branchName -eq 'HEAD') {
                Write-CliError -Message "Could not detect current branch." -Hint "Pass -PullRequestId explicitly."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
        }
        $where = Resolve-P20GitHubPRRepo -PullRequestId $PullRequestId -Repository $Repository -Project $Project `
            -OrgUrl $org -Projects $cfg.Projects -CurrentDir $currentDir -Token (Get-P20Consts).tokens.prUrl `
            -ToolkitRoot (Split-Path -Parent $PSScriptRoot) -Verb 'AddPRReview'
        if ($where.Error) {
            # A write: the same number on the wrong repository is somebody
            # else's pull request. Nothing is guessed.
            Write-CliError -Message $where.Error -Hint $where.Hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $ghRepoFull = $where.Repo

        # By branch: the open pull request whose head it is, as -f fields.
        if (-not $PullRequestId) {
            Write-Host "Auto-detecting PR for branch: $branchName ..." -ForegroundColor DarkGray
            $listRead = Invoke-P20TrackerRead 'gh' @('api', '--method', 'GET', "repos/$ghRepoFull/pulls",
                '-f', "head=$($ghRepoFull.Split('/')[0]):$branchName", '-f', 'state=open', '-F', 'per_page=10')
            if ($listRead.Code -ne 0) {
                Write-CliError -Message "Could not list pull requests on $ghRepoFull -- $((@($listRead.Lines) -join ' ').Trim())" -Hint "Check gh auth status, or $(Get-CliPrefix)Log -Errors."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
            $listed = @(@((@($listRead.Out) -join "`n") | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_ })
            if ($listed.Count -eq 0) {
                Write-CliError -Message "No open PR found for branch '$branchName' on $ghRepoFull." -Hint "Push your branch, open a PR, then retry."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
            $PullRequestId = [int]$listed[0].number
        }

        Write-Host "Fetching PR #$PullRequestId details ..." -ForegroundColor DarkGray
        $prRead = Invoke-P20TrackerRead 'gh' @('api', "repos/$ghRepoFull/pulls/$PullRequestId")
        if ($prRead.Code -ne 0) {
            $said = (@($prRead.Lines) -join ' ').Trim()
            if ($said -match '404|Not Found') {
                Write-CliError -Message "PR #$PullRequestId not found on $ghRepoFull." -Hint "Check the PR number, or name the repository: -Repository <owner>/<name>."
            }
            else {
                Write-CliError -Message "Could not read PR #$PullRequestId on $ghRepoFull -- $said" -Hint "Check gh auth status, or $(Get-CliPrefix)Log -Errors."
            }
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $pr = (@($prRead.Out) -join "`n") | ConvertFrom-Json
        Write-Host "  PR #$($PullRequestId): $($pr.title) ($ghRepoFull)" -ForegroundColor DarkGray
        if ($pr.head -and $pr.base) { Write-Host "  $($pr.head.ref) -> $($pr.base.ref)" -ForegroundColor DarkGray }

        # The unified diff, from GitHub: the same text git diff gives the ADO
        # path, and no checkout needed. The media type travels as a header.
        Write-Host "Fetching the diff from GitHub ..." -ForegroundColor DarkGray
        $diffRead = Invoke-P20TrackerRead 'gh' @('api', "repos/$ghRepoFull/pulls/$PullRequestId", '-H', 'Accept: application/vnd.github.diff')
        if ($diffRead.Code -ne 0) {
            Write-CliError -Message "Could not read the diff of PR #$PullRequestId on $ghRepoFull -- $((@($diffRead.Lines) -join ' ').Trim())" -Hint "GitHub refuses a diff past its size limit; nothing was sent to the model."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $diff = @($diffRead.Out) -join "`n"
        $diffOf = "PR #$PullRequestId on $ghRepoFull"
    }
    else {

    $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
    if (-not $tokenRead.Ok) {
        Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $headers = Get-P20AdoHeaders -Token $tokenRead.Token
    $encodedProject = [Uri]::EscapeDataString($Project)

    # --- Resolve PR ID from branch if not supplied ---
    if (-not $PullRequestId) {
        $branchName = (Invoke-P20TrackerRead 'git' @('rev-parse', '--abbrev-ref', 'HEAD')).Out
        if (-not $branchName -or $branchName -eq 'HEAD') {
            Write-CliError -Message "Could not detect current branch." -Hint "Pass -PullRequestId explicitly."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        Write-Host "Auto-detecting PR for branch: $branchName ..." -ForegroundColor DarkGray

        $allProjects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo } })
        $foundPR = $false
        foreach ($proj in $allProjects) {
            $enc = [Uri]::EscapeDataString($proj.Name)
            $uri = "$org/$enc/_apis/git/repositories/$($proj.Repo)/pullRequests?searchCriteria.sourceRefName=refs/heads/$branchName&api-version=7.1"
            try {
                $list = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                if ($list.count -gt 0) {
                    $PullRequestId = $list.value[0].pullRequestId
                    $Project       = $proj.Name
                    $Repository    = $proj.Repo
                    $encodedProject = $enc
                    $foundPR = $true
                    Write-Host "Found PR #${PullRequestId}: $($list.value[0].title) ($Project / $Repository)" -ForegroundColor Green
                    break
                }
            } catch {
                # 404 (no such repo here) is "not in this project": the search goes on.
                # 401/403 is the token or the permission, and reading it as "no PR" sends
                # the user to look for a PR that exists -- stop and say so.
                $httpStatus = Get-P20AdoHttpStatus $_
                if ($httpStatus -eq 401 -or $httpStatus -eq 403) {
                    Write-CliError -Message "Azure DevOps refused the PR search in '$($proj.Name)' (HTTP $httpStatus)." -Hint "Run 'az login' (and open $org in a browser once), then retry; or pass -PullRequestId."
                    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
                }
            }
        }
        if (-not $foundPR) {
            Write-CliError -Message "No open PR found for branch '$branchName'." -Hint "Push your branch, open a PR, then retry."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }

    # --- Fetch PR details (source / target branches) ---
    Write-Host "Fetching PR #$PullRequestId details ..." -ForegroundColor DarkGray
    try {
        $prUri  = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$($PullRequestId)?api-version=7.1"
        $pr     = Invoke-RestMethod -Uri $prUri -Headers $headers -Method Get
    } catch {
        $handled = Show-P20AdoForbiddenHint $_ -Org $org
        if (-not $handled) {
            Write-CliError -Message "Could not fetch PR #$PullRequestId. $($_.Exception.Message)"
        }
        else { $global:P20StatedError = "Could not fetch PR #$PullRequestId -- access denied." }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    $sourceBranch = $pr.sourceRefName -replace '^refs/heads/', ''
    $targetBranch = $pr.targetRefName -replace '^refs/heads/', ''
    Write-Host "  $sourceBranch -> $targetBranch" -ForegroundColor DarkGray

    # --- Get diff via git ---
    $inGitRepo = $false
    try {
        $inGitRepo = ((Invoke-P20TrackerRead 'git' @('rev-parse', '--git-dir')).Code -eq 0)
    } catch { $null = $_ }

    if (-not $inGitRepo) {
        Write-CliError -Message "Not in a git repository." -Hint "Run $(Get-CliPrefix)AddPRReview from within the repo directory."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    Write-Host "Fetching branches and computing diff ..." -ForegroundColor DarkGray
    $null = Invoke-P20TrackerRead 'git' @('fetch', 'origin', $targetBranch, $sourceBranch, '--quiet')

    $diffRead   = Invoke-P20TrackerRead 'git' @('diff', "origin/$targetBranch...origin/$sourceBranch", '--unified=3')
    $diffLines  = $diffRead.Lines
    $gitExit    = $diffRead.Code
    $diff       = $diffLines -join "`n"
    $diffOf     = "origin/$targetBranch and origin/$sourceBranch"

    # 2>&1 folds stderr into $diffLines, so a git failure arrives looking like
    # content and passes an emptiness check. It then reaches the model as though
    # it were a diff, which costs an API call and returns nothing useful. Check
    # the exit code, and that what came back actually looks like a diff.
    if ($gitExit -ne 0) {
        Write-CliError -Message "git diff failed between origin/$targetBranch and origin/$sourceBranch." -Hint "Run this from the repository the PR belongs to. git said: $diff"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    }
    # -- end of the ADO else; both trackers land here with $diff and $diffOf --

    if ($diff -and ($diff -notmatch '(?m)^diff --git ') -and ($diff -notmatch '(?m)^@@ ')) {
        Write-CliError -Message "Output from git does not look like a diff -- refusing to send it to the model." -Hint $diff.Substring(0, [Math]::Min(200, $diff.Length))
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    if ([string]::IsNullOrWhiteSpace($diff)) {
        Write-Host "No diff found for $diffOf." -ForegroundColor Yellow
        exit 0
    }

    # The whole diff, for GitHub's positioning check: a finding is placed on a
    # line the diff shows, and the model may cite one past a truncation.
    $fullDiff = $diff

    # Truncate if very large (haiku has plenty of context; keep it snappy)
    $maxChars = 120000
    if ($diff.Length -gt $maxChars) {
        $diff = $diff.Substring(0, $maxChars) + "`n[... diff truncated at $maxChars chars ...]"
        Write-Host "  Diff truncated to $maxChars chars." -ForegroundColor DarkGray
    } else {
        Write-Host "  Diff: $($diff.Length) chars" -ForegroundColor DarkGray
    }

    # --- Build Claude prompt ---
    # The reviewing is done by agentic/pr-review.prompt.md, not by this script.
    # Loading it from disk is the point: the prompt is the portable half and must
    # be editable, versionable and forkable without touching PowerShell.
    # ...and which copy: the engineer's extension folder wins when it carries
    # the file, the package's otherwise (Scripts/Resolve-AgenticPrompt.ps1).
    . (Join-Path $PSScriptRoot 'Resolve-AgenticPrompt.ps1')
    $resolvedPrompt = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md'
    $promptPath = $resolvedPrompt.Path
    Write-Host "  Prompt: $promptPath ($($resolvedPrompt.Source) copy)" -ForegroundColor DarkGray
    if (-not (Test-Path $promptPath)) {
        Write-CliError -Message "Review prompt not found at $promptPath"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $promptTemplate = Get-Content $promptPath -Raw
    # The frontmatter and everything above the --- fence are for a person, not
    # instruction (Get-P20PromptInstruction, beside the resolver).
    $promptTemplate = Get-P20PromptInstruction -Text $promptTemplate
    $prompt = $promptTemplate.Replace('{diff}', $diff).Trim()

    # --- Call Claude API ---
    Write-Host "Calling Claude ($Model) ..." -ForegroundColor DarkGray

    $requestBody = [ordered]@{
        model      = $Model
        max_tokens = 1024
        messages   = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 5 -Compress

    try {
        $claudeResp = Invoke-RestMethod `
            -Uri "https://api.anthropic.com/v1/messages" `
            -Method Post `
            -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
                "content-type"      = "application/json"
            } `
            -Body $requestBody
    } catch {
        Write-CliError -Message "Claude API call failed. $($_.Exception.Message)"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    $reviewText = $claudeResp.content[0].text.Trim()

    # Strip markdown fences if Claude added them
    $reviewText = $reviewText -replace '(?s)^```(?:json)?\s*', ''
    $reviewText = $reviewText -replace '\s*```$', ''

    # Parse JSON findings
    try {
        $findings = $reviewText | ConvertFrom-Json
    } catch {
        Write-CliError -Message "Could not parse the model's response as JSON." -Hint "Raw output follows."
        Write-Host $reviewText
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    if ($findings.Count -eq 0) {
        Write-Host "Claude found no issues. PR looks clean." -ForegroundColor Green
        if ($DryRun) { Write-Host "(dry run - nothing to post)" -ForegroundColor DarkGray }
        exit 0
    }

    Write-Host "Claude returned $($findings.Count) finding(s)." -ForegroundColor Cyan

    # --- On GitHub: ONE review, the findings its inline comments ---
    if ($trackerKind -eq 'github') {
        $plan = New-P20GitHubReviewPayload -Findings @($findings) -RightLines (Get-P20DiffRightLines -Diff $fullDiff)
        $review = $plan.Payload
        # On stage: a public repository's review is read by strangers. One
        # line before the write, and in -DryRun; nothing is asked.
        . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
        Write-P20PublicLine -Repo $ghRepoFull
        if ($DryRun) {
            Write-Host ""
            Write-Host "--- [DryRun] Would post one review on $ghRepoFull PR #$PullRequestId ($($plan.Inline) inline, $($plan.Moved) in the body) ---" -ForegroundColor DarkGray
            foreach ($c in @($review.comments)) { Write-Host "  File: $($c.path)  L$($c.line)" -ForegroundColor DarkGray; Write-Host "  $($c.body)" -ForegroundColor White }
            Write-Host "  Body: $($review.body)" -ForegroundColor White
            exit 0
        }
        $reviewsPath = "repos/$ghRepoFull/pulls/$PullRequestId/reviews"
        $post = Invoke-P20GhApiWrite $reviewsPath $review
        if ($post.Code -ne 0 -and @($review.comments).Count -gt 0) {
            # GitHub refuses the whole review when one inline position does not
            # resolve. Once more with every finding in the body, as the ADO
            # path retries a thread as a general comment.
            Write-Host "  Warning: GitHub refused the inline review -- $((@($post.Lines) -join ' ').Trim())" -ForegroundColor Yellow
            Write-Host "    Retrying with every finding in the review's body ..." -ForegroundColor DarkGray
            $plan = New-P20GitHubReviewPayload -Findings @($findings) -RightLines @{}
            $review = $plan.Payload
            $post = Invoke-P20GhApiWrite $reviewsPath $review
        }
        if ($post.Code -ne 0) {
            Write-CliError -Message "Could not post the review to PR #$PullRequestId on $ghRepoFull -- $((@($post.Lines) -join ' ').Trim())" -Hint "Check gh auth status, or $(Get-CliPrefix)Log -Errors. -DryRun prints the findings without posting."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $posted = (@($post.Out) -join "`n") | ConvertFrom-Json
        Write-Host "  Posted review $($posted.id): $($plan.Inline) inline comment(s), $($plan.Moved) in the body." -ForegroundColor Green
        Write-Host ""
        Write-Host "Done. $(@($findings).Count) finding(s) posted to PR #$PullRequestId." -ForegroundColor Green
        Write-Host "  https://github.com/$ghRepoFull/pull/$PullRequestId" -ForegroundColor DarkGray
        Write-Host "  Run $(Get-CliPrefix)GetPRComments $PullRequestId to pull them into a prompt file." -ForegroundColor Cyan
        exit 0
    }

    # --- Post findings as PR threads ---
    $threadsUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullRequests/$PullRequestId/threads?api-version=7.1"

    $posted = 0
    foreach ($finding in $findings) {
        $file    = $finding.file -replace '^b/', ''   # strip b/ prefix from diff paths
        $line    = [int]$finding.line
        $comment = $finding.comment

        # Prefix so $(Get-CliPrefix)GetPRComments recognises it as a bot review
        $content = "[AI Code Review] $comment"

        $thread = [ordered]@{
            comments = @(@{
                parentCommentId = 0
                content         = $content
                commentType     = 1
            })
            status = 1
        }

        # Add inline file context if we have a valid file + line
        if ($file -and $line -gt 0) {
            $thread.threadContext = [ordered]@{
                filePath       = "/$($file.TrimStart('/'))"
                rightFileStart = @{ line = $line; offset = 1 }
                rightFileEnd   = @{ line = $line; offset = 200 }
            }
        }

        $body = $thread | ConvertTo-Json -Depth 6 -Compress

        if ($DryRun) {
            Write-Host ""
            Write-Host "--- [DryRun] Would post thread ---" -ForegroundColor DarkGray
            Write-Host "  File: $file  L$line" -ForegroundColor DarkGray
            Write-Host "  $comment" -ForegroundColor White
        } else {
            try {
                $result = Invoke-RestMethod -Uri $threadsUri -Method Post -Headers $headers -Body $body
                $threadId = $result.id
                Write-Host "  Posted thread $threadId - $file L$line" -ForegroundColor Green
                $posted++
            } catch {
                $status = $_.Exception.Response.StatusCode
                Write-Host "  Warning: Failed to post thread for $file L$line (HTTP $status)." -ForegroundColor Yellow
                # If inline fails (line number out of range), retry without threadContext
                if ($thread.threadContext) {
                    Write-Host "    Retrying as general PR comment ..." -ForegroundColor DarkGray
                    $thread.Remove('threadContext')
                    $body = $thread | ConvertTo-Json -Depth 6 -Compress
                    try {
                        $result = Invoke-RestMethod -Uri $threadsUri -Method Post -Headers $headers -Body $body
                        Write-Host "    Posted as general comment (thread $($result.id))." -ForegroundColor Green
                        $posted++
                    } catch {
                        Write-Host "    Could not post even as general comment: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }

    if (-not $DryRun) {
        $prUrl = "$org/$encodedProject/_git/$Repository/pullrequest/$PullRequestId"
        Write-Host ""
        Write-Host "Done. $posted comment(s) posted to PR #$PullRequestId." -ForegroundColor Green
        Write-Host "  $prUrl" -ForegroundColor DarkGray
        Write-Host "  Run $(Get-CliPrefix)GetPRComments $PullRequestId to pull them into a prompt file." -ForegroundColor Cyan
    }

} catch {
    Write-CliError -Message $_.Exception.Message -Hint "Use '$(Get-CliPrefix)AddPRReview -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
