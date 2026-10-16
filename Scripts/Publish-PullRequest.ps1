<#
.SYNOPSIS
    Workflow command: flips a card's draft pull request on Azure DevOps to ready.

.DESCRIPTION
    The second stage of the ship flow. `NewPR -Draft` opens a draft; this publishes
    it, through the same token and REST path NewPR uses:

      1. The card -- named by id or filename, or the card current/ holds for this
         branch when run from the code repository.
      2. Its PR URL: line -- the pull request NewPR (or GetPRComments) wrote. It
         names the organisation, project, repository and pull request id, so
         nothing else is asked for.
      3. A token from `az account get-access-token` (with the Space's tenant when it
         declares one), a GET to confirm the pull request is an active draft, then
         PATCH .../pullrequests/{id}?api-version=7.1 with {"isDraft":false}.
      4. One line under the card's PR URL: line -- `PR published: <url>` -- through
         Write-CardText. Not a dated stamp: the line says THAT it was published.
         A card that already carries it is not written again.

    Refused, with exit 2 and one sentence: a card with no PR URL: line, a GitHub
    pull request (its draft is flipped with `gh pr ready <url>`), a URL that is not
    an Azure DevOps pull request, a pull request that is not active, and one that
    is already ready.

.PARAMETER Card
    The card: a path, a filename, or its ID (119, K7M2). Default: the card current/
    holds for this branch, from the code repository.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    {cliPrefix}PublishPR 119 -WhatIf
    {cliPrefix}PublishPR 119
    {cliPrefix}PublishPR

.NOTES
    Depends on: az cli (for the access token), Azure DevOps REST API v7.1.
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [Parameter()]
    [switch]$Help
)

# The PR URL: line is read through consts.json, never retyped.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$c = Get-P20Consts

# Get-CliPrefix, Write-CliError and Write-ToolkitLog normally come from the module.
# This script is also run directly -- by -Help without an import, by a test -- so a
# missing helper must not be fatal (the same shape as New-PullRequest.ps1).
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
if (-not (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue)) {
    function Write-ToolkitLog { param([string]$Type, [string]$Source, [string]$Detail) $null = $Type, $Source, $Detail }
}

$p = Get-CliPrefix

# -- Help ---------------------------------------------------------------------
if ($Help) {
    Write-Host @"

Publish-P20PullRequest - Ship-it flow, stage 2: flip the card's draft PR to ready

USAGE:
    ${p}PublishPR [[-Card] <card|id>] [-WhatIf] [-Help]

WHAT IT DOES:
    1. Reads the card's PR URL line (written by ${p}NewPR)
    2. Confirms on Azure DevOps that the pull request is an active draft
    3. PATCHes it with {"isDraft":false} -- the token is az's, as ${p}NewPR's is
    4. Writes one line under the PR URL line: PR published: <url>

PARAMETERS:
    -Card <card|id>   The card: a path, a filename, or its ID (119, K7M2). Default:
                      the card current/ holds for this branch.
    -WhatIf           Print the exact call; send nothing, write nothing.
    -Help             Show this help message.

EXAMPLES:
    ${p}PublishPR 119 -WhatIf
    ${p}PublishPR 119
    ${p}PublishPR                  # from the code repository, on the work branch

NOTES:
    - Azure DevOps only. A GitHub pull request is published with: gh pr ready <url>
    - A card with no PR URL line, a pull request that is not active, and one that
      is already ready are refused, and nothing is written.

"@ -ForegroundColor Cyan
    exit 0
}

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')

# The line this verb writes. CLI-only: nothing in the agent or the web reads it, and
# it is not state -- the PR URL: line above it is the gate into Code Review.
$publishedLabel = 'PR published:'

# -- Config -------------------------------------------------------------------
$cfg = $global:P20Config
if (-not $cfg) {
    Write-CliError -Message "Toolkit config not loaded. Is utilities.psm1 imported?"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$folders = Get-PromptFolders
$types = Get-P20WorkItemTypes -Config $cfg

# -- Which card ----------------------------------------------------------------
# Named: a path on disk, else the one rule every verb uses (Resolve-P20CardArgument).
# Not named: the card for the cwd's branch -- only when the cwd is a code checkout
# and not the Toolkit's own, which is where the bridge runs every verb.
$cardPath = $null
if ($Card) {
    if (Test-Path -LiteralPath $Card -PathType Leaf) {
        $cardPath = (Resolve-Path -LiteralPath $Card).Path
    }
    else {
        $hit = Resolve-P20CardArgument -Argument $Card -Folder $folders.Current -WorkItemTypes $types
        $found = @($hit.Match | Where-Object { $_.Name -like '*.prompt.md' })
        if ($found.Count -eq 0) {
            if ($hit.IsId) {
                Write-CliError -Message "No card with id '$Card' in current/." `
                    -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. '${p}Status' lists the cards."
            }
            else {
                Write-CliError -Message "No card matching '$Card' in current/." -Hint "'${p}Status' lists the cards."
            }
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($found.Count -gt 1) {
            Write-CliError -Message "'$Card' matches $($found.Count) cards in current/: $(($found | ForEach-Object { $_.Name }) -join ', ')" `
                -Hint 'Name the card by its id or its full filename.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($hit.Fuzzy -and $env:TOOLKIT_QUIET_STARTUP) {
            # A partial name is acted on only where a person can read which card it hit.
            Write-CliError -Message "'$Card' is a partial name; it matched $($found[0].Name)." `
                -Hint 'Name the card by its id or its full filename.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $cardPath = $found[0].FullName
    }
}
else {
    $toolkitRoot = Split-Path -Parent $PSScriptRoot
    $cwdGitDir = "$(git rev-parse --absolute-git-dir 2>$null)".Trim()
    $cwdIsRepo = ($LASTEXITCODE -eq 0 -and $cwdGitDir)
    $toolkitGitDir = "$(git -C $toolkitRoot rev-parse --absolute-git-dir 2>$null)".Trim()
    $cwdIsCode = ($cwdIsRepo -and -not ($toolkitGitDir -and ($cwdGitDir -eq $toolkitGitDir)))
    $branch = ''
    if ($cwdIsCode) { $branch = "$(git rev-parse --abbrev-ref HEAD 2>$null)".Trim() }
    if (-not $branch) {
        Write-CliError -Message 'No card was named, and this is not a code repository on a work branch.' `
            -Hint "Name the card: ${p}PublishPR <id>."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    . (Join-Path $PSScriptRoot 'Resolve-CardForBranch.ps1')
    $byBranch = Resolve-P20CardForBranch -Branch $branch -CurrentDir $folders.Current -Detailed
    if (-not $byBranch.Path) {
        $why = "No card in current/ matches branch '$branch'."
        if ($byBranch.Candidates.Count -gt 1) { $why = "Branch '$branch' matches $($byBranch.Candidates.Count) cards: $($byBranch.Candidates -join ', ')." }
        Write-CliError -Message $why -Hint "Name the card: ${p}PublishPR <id>."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $cardPath = $byBranch.Path
}

$cardName = Split-Path $cardPath -Leaf
Write-Host "[*] Card: $cardName" -ForegroundColor DarkGray

# -- The pull request, from the card's PR URL: line -----------------------------
$text = [System.IO.File]::ReadAllText($cardPath) -replace "`r`n", "`n"
$prLine = [regex]::Match($text, '(?m)^' + [regex]::Escape($c.tokens.prUrl) + '\s*(https://\S+)[ \t]*$')
if (-not $prLine.Success) {
    Write-CliError -Message "$cardName has no $($c.tokens.prUrl) line, so there is no pull request to publish." `
        -Hint "Open it first: ${p}NewPR <id> -Draft writes the line."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$prUrl = $prLine.Groups[1].Value

# A GitHub pull request is GitHub's to publish, and gh already does it in one word.
if ($prUrl -match '^https://github\.com/[^/]+/[^/]+/pull/\d+') {
    Write-CliError -Message "$prUrl is a GitHub pull request; ${p}PublishPR publishes an Azure DevOps draft." `
        -Hint "On GitHub the draft is published with: gh pr ready $prUrl"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# The address New-PullRequest.ps1 builds: <org>/<project, escaped>/_git/<repo>/pullrequest/<id>.
# The project arrives escaped and is used as it is.
$ado = [regex]::Match($prUrl, '^(?<org>https://.+?)/(?<project>[^/]+)/_git/(?<repo>[^/]+)/pullrequest/(?<id>\d+)/?$')
if (-not $ado.Success) {
    Write-CliError -Message "$prUrl is not an Azure DevOps pull request address." `
        -Hint "${p}PublishPR reads <organisation>/<project>/_git/<repository>/pullrequest/<id>, the address ${p}NewPR writes."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$org = $ado.Groups['org'].Value
$project = $ado.Groups['project'].Value
$repo = $ado.Groups['repo'].Value
$prId = $ado.Groups['id'].Value

$apiUri = "$org/$project/_apis/git/repositories/$repo/pullrequests/$($prId)?api-version=7.1"
$body = @{ isDraft = $false } | ConvertTo-Json -Compress

Write-Host "[*] Pull request: $prUrl" -ForegroundColor DarkGray
Write-Host "[*] Call: PATCH $apiUri" -ForegroundColor DarkGray
Write-Host "[*] Body: $body" -ForegroundColor DarkGray

# -WhatIf: the exact call is printed above; nothing below runs -- no token, no
# read, no write to the pull request, no write to the card.
if (-not $PSCmdlet.ShouldProcess($prUrl, "Publish pull request $prId (draft -> ready)")) {
    Write-Host "[=] -WhatIf: the pull request was not published, nothing written." -ForegroundColor Cyan
    exit 0
}

# -- Auth: the token NewPR takes -----------------------------------------------
$tokenRead = Get-P20AdoToken -Tenant ([string]$cfg.Tenant)
if (-not $tokenRead.Ok) {
    Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$headers = Get-P20AdoHeaders -Token $tokenRead.Token

# Azure DevOps puts the reason in the response body; the exception only says the status.
$adoSentence = {
    param($err)
    $said = $err.Exception.Message
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        try { $m = ($err.ErrorDetails.Message | ConvertFrom-Json).message; if ($m) { $said = $m } } catch { $null = $_ }
    }
    return $said
}

# -- Is it an active draft? ------------------------------------------------------
try {
    $pr = Invoke-RestMethod -Uri $apiUri -Headers $headers -Method Get
}
catch {
    Write-CliError -Message "Could not read pull request $prId -- $(& $adoSentence $_)" `
        -Hint "Check ${p}Log -Errors, and that 'az login' is the account that can see $project/$repo."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($pr.status -and [string]$pr.status -ne 'active') {
    Write-CliError -Message "Pull request $prId is $($pr.status); only an active draft is published." `
        -Hint $prUrl
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not [bool]$pr.isDraft) {
    Write-CliError -Message "Pull request $prId is already ready -- it is not a draft, so there is nothing to publish." `
        -Hint "Nothing was sent and the card was not written. $prUrl"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Publish -----------------------------------------------------------------------
try {
    Invoke-RestMethod -Uri $apiUri -Headers $headers -Method Patch -Body $body | Out-Null
}
catch {
    Write-CliError -Message "Publishing pull request $prId failed -- $(& $adoSentence $_)" -Hint "Check ${p}Log -Errors."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
Write-Host "[+] Published: $prUrl" -ForegroundColor Green
Write-ToolkitLog -Type INFO -Source "${p}PublishPR" -Detail "published $prUrl ($cardName)"

# -- The card: one line under its PR URL: line, once ------------------------------
$lineText = "$publishedLabel $prUrl"
if ($text -match ('(?m)^' + [regex]::Escape($lineText) + '[ \t]*$')) {
    Write-Host "[=] $cardName already says '$lineText' -- not written again." -ForegroundColor DarkGray
}
else {
    $at = $prLine.Index + $prLine.Length
    $newText = $text.Substring(0, $at) + "`n" + $lineText + $text.Substring($at)
    Write-CardText -Path $cardPath -Content $newText
    Write-Host "[+] Wrote '$lineText' into $cardName" -ForegroundColor Green
}
exit 0
