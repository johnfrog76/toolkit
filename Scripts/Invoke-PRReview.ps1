<#
.SYNOPSIS
    Posts an AI code review to an Azure DevOps pull request (up to 3 inline comment threads).

.DESCRIPTION
    Gets the diff for a PR, sends it to Claude for review, and posts up to 3 findings as
    individual PR comment threads. Comments are formatted so $(Get-CliPrefix)GetPRComments picks them up
    as bot reviews and feeds them into the ado-comments triage flow.

    Requires ANTHROPIC_API_KEY environment variable.

.PARAMETER PullRequestId
    The PR number (positional). Omit to auto-detect from current branch.

.PARAMETER Repository
    ADO repository name. Default: from toolkit config.

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
    Requires: az cli (ADO auth), git (for diff), ANTHROPIC_API_KEY env var
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

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

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

$(Get-CliPrefix)AddPRReview - Post an AI code review to an Azure DevOps pull request

USAGE:
    $(Get-CliPrefix)AddPRReview <PullRequestId> [options]
    $(Get-CliPrefix)AddPRReview                              # auto-detect PR from current branch

PARAMETERS:
    -PullRequestId <int>   PR number (positional). Omit to detect from branch.
    -Repository <string>   ADO repo name. Default: from toolkit config.
    -Project <string>      ADO project name. Default: from toolkit config.
    -Model <string>        Model id. Default: ai.model in config ($(Get-P20ModelId)).
    -DryRun                Print review to console, do not post to ADO.
    -Help                  Show this help.

REQUIRES:
    - ANTHROPIC_API_KEY in a .env beside this package (loaded on import), or in
      the environment. Copy .env.example to .env -- it lists every variable.
      Get your key at console.anthropic.com -- API Keys
    - az cli authenticated (same as every other ADO command)
    - Run from within the git repo (used to get the diff)

BEHAVIOR:
    Sends the PR diff to Claude, posts up to 3 inline comment threads.
    Comments appear as AI Code Review bot entries that $(Get-CliPrefix)GetPRComments picks up.

EXAMPLES:
    $(Get-CliPrefix)AddPRReview 1042
    $(Get-CliPrefix)AddPRReview 1042 -Model claude-sonnet-5-5
    $(Get-CliPrefix)AddPRReview 1042 -DryRun
    $(Get-CliPrefix)AddPRReview            # auto-detects from current branch

"@ -ForegroundColor Cyan
    exit 0
}

if ($Help) { Show-Help }

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

if (-not $Project -or -not $Repository) {
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
function Get-AdoToken {
    $tenantArg = if ($global:P20Config.Tenant) { @('--tenant', $global:P20Config.Tenant) } else { @() }
    $tokenOutput = az account get-access-token @tenantArg --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-CliError -Message "Failed to get ADO access token. Run 'az login' first."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    return ($tokenOutput | Where-Object { $_ -notmatch '^WARNING:' })
}

function Get-AdoHeaders { param([string]$Token)
    return @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
}

function Get-AdoHttpStatus { param($ErrorRecord)
    # The status as a number: Windows PowerShell 5.1 hands back an HttpStatusCode enum,
    # pwsh 7 a System.Net.HttpStatusCode too -- [int] reads both. 0 when there is no response.
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and $null -ne $resp.StatusCode) { return [int]$resp.StatusCode }
    } catch { $null = $_ }
    return 0
}

function Show-AdoForbiddenHint { param($ErrorRecord)
    # 401 (an expired or unprovisioned token) is the same advice as 403; the status
    # is read by Get-AdoHttpStatus, the rule the branch search uses too.
    $status = Get-AdoHttpStatus $ErrorRecord
    if ($status -ne 401 -and $status -ne 403) { return $false }
    Write-Host "  Access denied (HTTP $status) -- your az identity may not be provisioned in this org." -ForegroundColor Yellow
    Write-Host "  Fix: run 'az login', open $org in a browser, sign in, then retry." -ForegroundColor Yellow
    return $true
}

# -- Main ----------------------------------------------------------------------
try {
    $token   = Get-AdoToken
    $headers = Get-AdoHeaders -Token $token
    $encodedProject = [Uri]::EscapeDataString($Project)

    # --- Resolve PR ID from branch if not supplied ---
    if (-not $PullRequestId) {
        $branchName = git rev-parse --abbrev-ref HEAD 2>$null
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
                $httpStatus = Get-AdoHttpStatus $_
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
        $handled = Show-AdoForbiddenHint $_
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
        git rev-parse --git-dir 2>&1 | Out-Null
        $inGitRepo = ($LASTEXITCODE -eq 0)
    } catch { $null = $_ }

    if (-not $inGitRepo) {
        Write-CliError -Message "Not in a git repository." -Hint "Run $(Get-CliPrefix)AddPRReview from within the repo directory."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    Write-Host "Fetching branches and computing diff ..." -ForegroundColor DarkGray
    git fetch origin $targetBranch $sourceBranch --quiet 2>&1 | Out-Null

    $diffLines  = git diff "origin/$targetBranch...origin/$sourceBranch" --unified=3 2>&1
    $gitExit    = $LASTEXITCODE
    $diff       = $diffLines -join "`n"

    # 2>&1 folds stderr into $diffLines, so a git failure arrives looking like
    # content and passes an emptiness check. It then reaches the model as though
    # it were a diff, which costs an API call and returns nothing useful. Check
    # the exit code, and that what came back actually looks like a diff.
    if ($gitExit -ne 0) {
        Write-CliError -Message "git diff failed between origin/$targetBranch and origin/$sourceBranch." -Hint "Run this from the repository the PR belongs to. git said: $diff"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($diff -and ($diff -notmatch '(?m)^diff --git ') -and ($diff -notmatch '(?m)^@@ ')) {
        Write-CliError -Message "Output from git does not look like a diff -- refusing to send it to the model." -Hint $diff.Substring(0, [Math]::Min(200, $diff.Length))
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    if ([string]::IsNullOrWhiteSpace($diff)) {
        Write-Host "No diff found between origin/$targetBranch and origin/$sourceBranch." -ForegroundColor Yellow
        exit 0
    }

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
