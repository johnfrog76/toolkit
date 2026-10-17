<#
.SYNOPSIS
    Record that you reviewed someone else's pull request.
.DESCRIPTION
    Writes one small file into the active Space's pr-comments/ folder. This is the
    half of review work that leaves no trace anywhere else: the PR carries your
    comments, but nothing in your own record says you spent the afternoon on it.
    The year-end review reads these.

    Org-scoped on purpose -- unlike growth/, reviewing a colleague's PR happens
    inside one engagement -- so it lands under <promptsRoot>/<promptsFolder>/.
.EXAMPLE
    {cliPrefix}LogPeerReview 6789
.EXAMPLE
    {cliPrefix}LogPeerReview 6789 -Title "Auth refactor" -Notes "Approved with nits"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [int]$PullRequestId,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Notes,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)LogPeerReview - log a completed peer review" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)LogPeerReview <PullRequestId> [-Title <string>] [-Notes <string>]"
    Write-Host ""
    Write-Host "  EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    $($p)LogPeerReview 6789"
    Write-Host "    $($p)LogPeerReview 6789 -Title 'Auth refactor' -Notes 'Approved with nits'"
    Write-Host ""
    exit 0
}

if (-not $PullRequestId) {
    Write-CliError -Message 'a pull request id is required.' -Hint "run '$(Get-CliPrefix)LogPeerReview -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Resolve the hub ----------------------------------------------------------
# One resolver, one rule: PROMPTS_ROOT in the environment is an explicit override
# and WINS, then the configured promptsRoot. Get-P20PromptsRoot in
# Resolve-HubConfig.ps1 is the only implementation of that -- every script read
# the two config files for itself, and the copies had drifted
# into three different precedences.
# Dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, pwsh -File).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
$cfg = $global:P20Config
$promptsFolder = ''
if ($cfg -and $cfg.PromptsFolder) { $promptsFolder = $cfg.PromptsFolder }

if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
    Write-CliError -Message "the prompt store is not configured or does not exist: '$promptsRoot'" -Hint 'set promptsRoot in config.local.json.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$prCommentsDir = if ($promptsFolder) {
    Join-Path (Join-Path $promptsRoot $promptsFolder) 'pr-comments'
}
else {
    Join-Path $promptsRoot 'pr-comments'
}
New-Item -ItemType Directory -Force -Path $prCommentsDir | Out-Null

$date = (Get-Date).ToString('yyyy-MM-dd')
$recordFile = Join-Path $prCommentsDir "reviewed-$date-PR$PullRequestId.md"

$heading = "# Reviewed PR $PullRequestId"
if ($Title) { $heading = "$heading - $Title" }
$lines = @($heading, "", "Date: $date")
if ($Notes) { $lines += "Notes: $Notes" }
$body = ($lines -join "`n") + "`n"

# The one writer, and -New because this CREATES the record: UTF-8 no BOM, LF.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
Write-CardText -Path $recordFile -Content $body -New

Write-Host "Logged peer review: pr-comments/reviewed-$date-PR$PullRequestId.md" -ForegroundColor Green
exit 0
