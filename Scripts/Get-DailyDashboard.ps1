<#
.SYNOPSIS
    Morning dashboard -- PRs, work items, and recent pipeline runs.
.DESCRIPTION
    Combines Get-MyPRs, Get-MyWorkItems, and pipeline status into a single summary.
    On Tier 2 (local mode), shows active prompts and repo status instead of ADO data.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = $global:P20Config
$tier = if ($global:ToolkitEnv) { $global:ToolkitEnv.Tier } else { 1 }

$modeTag = if ($tier -ge 2) { '  [Local Mode]  [*]' } else { '' }

Write-Host ""
Write-Host "  ======================================$modeTag" -ForegroundColor Cyan
Write-Host "    Daily Dashboard  -  $(Get-Date -Format 'dddd, MMMM dd yyyy')" -ForegroundColor Cyan
Write-Host "  ======================================" -ForegroundColor Cyan

if ($tier -ge 2) {
    # -- Local view: no ADO, show what we can --
    Write-Host ""
    Write-Host "  [*] ADO unavailable -- PR and work item data not shown" -ForegroundColor Yellow
    Write-Host "      Run on work laptop for full dashboard, or $(Get-CliPrefix)Env for details" -ForegroundColor DarkGray

    # Active prompts
    Write-Host ""
    Write-Host "  == Active Prompts =="  -ForegroundColor Magenta
    $folders = Get-PromptFolders
    $currentDir = $folders.Current
    if (Test-Path $currentDir) {
        $prompts = Get-ChildItem -Path $currentDir -File | Sort-Object LastWriteTime -Descending
        if ($prompts.Count -eq 0) {
            Write-Host "  (none)" -ForegroundColor DarkGray
        } else {
            foreach ($p in $prompts) {
                $age = (Get-Date) - $p.LastWriteTime
                $ageStr = if ($age.TotalHours -lt 1) { "{0:N0}m ago" -f $age.TotalMinutes }
                          elseif ($age.TotalDays -lt 1) { "{0:N0}h ago" -f $age.TotalHours }
                          else { "{0:N0}d ago" -f $age.TotalDays }
                $name = $p.Name
                if ($name.Length -gt 55) { $name = $name.Substring(0, 52) + '...' }
                Write-Host "  $($name.PadRight(58)) modified $ageStr" -ForegroundColor Gray
            }
        }
    }

    # Repo status
    Write-Host ""
    Write-Host "  == Repo Status ==" -ForegroundColor Magenta
    Push-Location $cfg.PromptsRoot
    try {
        # %at on this machine's clock, not %ai in the author's zone
        $lastLog = git log -1 --format="%at%x09%an" 2>$null
        if ($lastLog) {
            $lastAt, $lastWho = "$lastLog" -split "`t", 2
            . (Join-Path $PSScriptRoot 'ConvertTo-LocalDay.ps1')
            Write-Host "  Last commit:   $(ConvertTo-P20LocalStamp $lastAt) ($lastWho)" -ForegroundColor Gray
        }
        $unpushed = (git log --oneline '@{u}..HEAD' 2>$null | Measure-Object).Count
        Write-Host "  Unpushed:      $unpushed commits" -ForegroundColor Gray
        $uncommitted = (git status --porcelain 2>$null | Measure-Object).Count
        Write-Host "  Uncommitted:   $uncommitted files" -ForegroundColor Gray
    } finally {
        Pop-Location
    }

    # Recent errors from log
    $logPath = Join-Path (Split-Path $scriptDir -Parent) 'usage.log'
    if (Test-Path $logPath) {
        $cutoff = (Get-Date).AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ss')
        $recentErrors = @(Get-Content $logPath -Encoding UTF8 | Where-Object {
            $parts = $_ -split "`t"
            $parts.Count -ge 2 -and $parts[1] -eq 'ERR' -and $parts[0] -gt $cutoff
        })
        if ($recentErrors.Count -gt 0) {
            Write-Host ""
            Write-Host "  == Recent Errors ==" -ForegroundColor Magenta
            Write-Host "  [!] $($recentErrors.Count) error$(if($recentErrors.Count -ne 1){'s'}) in last 24h -- $(Get-CliPrefix)Log -Errors to review" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Dashboard complete." -ForegroundColor Green
    Write-Host ""
    # `git log @{u}..HEAD` exits 128 on a hub with no upstream -- or no git at
    # all -- and that code is not the dashboard's verdict.
    exit 0
}

# -- Full view (Tier 1) -------------------------------------------------------

# --- PRs ---
Write-Host "`n  [Pull Requests]" -ForegroundColor Magenta
& "$scriptDir\Get-MyPRs.ps1"

# --- Work Items ---
Write-Host "`n  [Work Items]" -ForegroundColor Magenta
& "$scriptDir\Get-MyWorkItems.ps1"

# --- Recent Pipeline Runs ---
Write-Host "`n  [Recent Pipeline Runs]" -ForegroundColor Magenta
Write-Host "  $('=' * 60)" -ForegroundColor DarkGray

$org = $cfg.Org
$esc = [char]27
$bel = [char]7

# On a GitHub board the pipelines are Actions runs, per repo, through gh --
# the same five-row table.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
# Which space, which tracker.
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    foreach ($repoFull in (Get-P20TrackerRepos -OrgUrl $org -Projects $cfg.Projects)) {
        $runs = gh run list --repo $repoFull --limit 5 `
            --json 'workflowName,conclusion,status,headBranch,updatedAt,url' 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n  $repoFull -- GitHub did not answer for its runs." -ForegroundColor Yellow
            continue
        }
        if (-not $runs) { continue }
        Write-Host "`n  $repoFull" -ForegroundColor Yellow
        $runs | Format-Table @(
            @{ Label = "Pipeline"; Expression = { $_.workflowName.Substring(0, [Math]::Min(25, $_.workflowName.Length)) }; Width = 27 }
            @{ Label = "Result"; Expression = {
                    switch ($_.conclusion) {
                        "success" { "[+] Pass" }
                        "failure" { "[x] Fail" }
                        "cancelled" { "[-] Cancel" }
                        "" { if ($_.status -eq 'in_progress' -or $_.status -eq 'queued') { "Running..." } else { $_.status } }
                        default { $_.conclusion }
                    }
                }; Width = 12
            }
            @{ Label = "Branch"; Expression = { $_.headBranch }; Width = 25 }
            @{ Label = "Finished"; Expression = { ([datetime]$_.updatedAt).ToString("MM-dd HH:mm") }; Width = 14 }
        ) -AutoSize
        Write-Host "    Links:" -ForegroundColor DarkGray
        foreach ($run in $runs) {
            $link = $esc + "]8;;" + $run.url + $bel + $run.url + $esc + "]8;;" + $bel
            $name = $run.workflowName.Substring(0, [Math]::Min(25, $run.workflowName.Length))
            Write-Host "    ${name}: " -NoNewline -ForegroundColor Yellow
            Write-Host $link -ForegroundColor Blue
        }
    }
    Write-Host "`n  Dashboard complete.`n" -ForegroundColor Green
    # Each section has said its own trouble; the last native call's code is not
    # the dashboard's verdict.
    exit 0
}

$projects = @($cfg.Projects | ForEach-Object { $_.name } | Select-Object -Unique)

foreach ($proj in $projects) {
    $runs = az pipelines runs list `
        --org $org `
        --project $proj `
        --top 5 `
        --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n  $proj -- did not answer in $org; its pipeline runs are not shown." -ForegroundColor Yellow
        continue
    }

    if ($runs) {
        Write-Host "`n  $proj" -ForegroundColor Yellow
        $runs | Format-Table @(
            @{ Label = "Pipeline";  Expression = { $_.definition.name.Substring(0, [Math]::Min(25, $_.definition.name.Length)) }; Width = 27 }
            @{ Label = "Result";    Expression = {
                switch ($_.result) {
                    "succeeded"           { "[+] Pass" }
                    "failed"              { "[x] Fail" }
                    "canceled"            { "[-] Cancel" }
                    "partiallySucceeded"  { "~ Partial" }
                    default               { $_.status }
                }
            }; Width = 12 }
            @{ Label = "Branch";    Expression = { $_.sourceBranch -replace 'refs/heads/', '' }; Width = 25 }
            @{ Label = "Finished";  Expression = {
                if ($_.finishTime) { ([datetime]$_.finishTime).ToString("MM-dd HH:mm") } else { "Running..." }
            }; Width = 14 }
        ) -AutoSize

        $projEncoded = [Uri]::EscapeDataString($proj)
        Write-Host "    Links:" -ForegroundColor DarkGray
        foreach ($run in $runs) {
            $url = "$org/$projEncoded/_build/results?buildId=$($run.id)"
            $link = $esc + "]8;;" + $url + $bel + $url + $esc + "]8;;" + $bel
            $name = $run.definition.name.Substring(0, [Math]::Min(25, $run.definition.name.Length))
            Write-Host "    ${name}: " -NoNewline -ForegroundColor Yellow
            Write-Host $link -ForegroundColor Blue
        }
    }
}

Write-Host "`n  Dashboard complete.`n" -ForegroundColor Green
# The dashboard listed what it could, and each section named what it could not.
exit 0
