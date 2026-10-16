<#
.SYNOPSIS
    Commit the hub's reviews/ folder and sync it.
.DESCRIPTION
    Stages everything under <promptsRoot>/reviews/, commits with a dated
    message, and then runs the same sync the rest of the CLI uses.

    -Preview emits the pending diff as JSON instead, which is what the web UI's
    review page renders before you press commit. Nothing about the review is
    read back out of git: the file is the record, committing is how the store
    happens to be backed up.
.EXAMPLE
    {cliPrefix}PublishWorkReview
.EXAMPLE
    {cliPrefix}PublishWorkReview -NoPush
#>
[CmdletBinding()]
param(
    [switch]$NoPush,
    [switch]$Preview,
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)PublishWorkReview - commit the reviews/ folder and sync" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)PublishWorkReview            stage, commit and sync reviews/"
    Write-Host "    $($p)PublishWorkReview -NoPush    commit only -- read the diff first"
    Write-Host "    $($p)PublishWorkReview -Preview   emit the pending diff as JSON"
    Write-Host ""
    Write-Host "  WORKFLOW:" -ForegroundColor Yellow
    Write-Host "    1. $($p)NewWorkReview -StartDate ... -EndDate ...   writes the scaffold"
    Write-Host "    2. hand agentic/generate-review.prompt.md to your assistant to turn"
    Write-Host "       the scaffold into prose, or edit it yourself"
    Write-Host "    3. read the diff, then $($p)PublishWorkReview"
    Write-Host ""
    exit 0
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

# -- The hub-root folder's NAME is the hub's, not this script's ----------------
# hub.json's "folders" block can rename it. Resolve-HubConfig.ps1 is the single
# reader of that too, and is dot-sourced above.
$reviewsFolder = (Get-P20HubFolderNames -PromptsRoot $promptsRoot -PackageRoot $repoRoot)['reviews']
$reviewsPathspec = "${reviewsFolder}/"
# -- Preview: the web UI's read, so it answers in JSON and never in prose -----
if ($Preview) {
    if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
        @{ error = "the prompt store is not configured" } | ConvertTo-Json -Compress
        exit 0
    }
    Push-Location $promptsRoot
    try {
        # --untracked-files=all, not the default: the default reports a brand
        # new folder as one entry ending in '/', and a folder is not a file --
        # reading it produced an entry whose content was null and a 500 from the
        # route that renders this. A first review lands in a brand new folder,
        # so that is the normal case, not the edge one.
        $status = git status --porcelain --untracked-files=all -- $reviewsPathspec 2>&1
        $files = @()
        if (-not [string]::IsNullOrWhiteSpace($status)) {
            $changedPaths = $status -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                $rel = ($_ -split '\s+', 2)[1].Trim()
                # A rename reads 'old -> new'; the file that exists is the new one.
                if ($rel -match '\s->\s') { $rel = ($rel -split '\s->\s', 2)[1].Trim() }
                $rel.Trim('"')
            }
            foreach ($rel in $changedPaths) {
                $full = Join-Path $promptsRoot $rel
                if (Test-Path $full -PathType Leaf) {
                    $content = Get-Content $full -Raw
                    if ($null -eq $content) { $content = '' }
                    $files += @{ file = $rel; content = $content }
                }
            }
        }
        @{ files = $files } | ConvertTo-Json -Depth 5
    }
    finally {
        Pop-Location
    }
    exit 0
}

if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
    Write-Host "Error: the prompt store is not configured or does not exist: '$promptsRoot'" -ForegroundColor Red
    Write-Host "Hint:  set promptsRoot in config.local.json." -ForegroundColor Yellow
    exit 1
}

$reviewsDir = Join-Path $promptsRoot $reviewsFolder
if (-not (Test-Path $reviewsDir)) {
    Write-Host "Error: there is no $reviewsPathspec folder at '$reviewsDir'." -ForegroundColor Red
    Write-Host "Hint:  run '$(Get-CliPrefix)NewWorkReview -StartDate <d> -EndDate <d>' to write the first one." -ForegroundColor Yellow
    exit 1
}

Push-Location $promptsRoot
try {
    $status = git status --porcelain -- $reviewsPathspec 2>&1
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "Nothing to commit -- $reviewsPathspec is unchanged." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Write a scaffold first:" -ForegroundColor Cyan
        Write-Host "    $(Get-CliPrefix)NewWorkReview -StartDate 2026-01-01 -EndDate 2026-04-18"
        Write-Host ""
        exit 0
    }

    Write-Host "Changes in ${reviewsPathspec}:" -ForegroundColor Cyan
    Write-Host $status

    git add $reviewsPathspec 2>&1 | ForEach-Object { Write-Host $_ }
    $timestamp = Get-Date -Format 'yyyy-MM-dd'
    $commitMsg = "chore: update review ($timestamp)"
    git commit -m $commitMsg 2>&1 | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: the commit failed." -ForegroundColor Red
        exit 1
    }

    Write-Host "Committed: $commitMsg" -ForegroundColor Green

    if (-not $NoPush) {
        Write-Host ""
        & "$PSScriptRoot/Sync-Prompts.ps1"
    }
}
finally {
    Pop-Location
}
exit 0
