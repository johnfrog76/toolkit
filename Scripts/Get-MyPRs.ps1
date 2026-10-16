<#
.SYNOPSIS
    Lists your open Azure DevOps PRs across the active Space's projects.
.DESCRIPTION
    Queries every configured project for active PRs where you are the creator or a reviewer.
.PARAMETER CreatorOnly
    If set, only shows PRs you created (excludes reviewer PRs).
#>
[CmdletBinding()]
param(
    [switch]$CreatorOnly
)

$cfg = $global:P20Config
$org = $cfg.Org
# Config first, then the az identity. Reading $cfg.Email directly meant an unset
# email queried --creator '' and silently returned "No active PRs found" -- a
# wrong answer that looks like a correct one.
$email = Resolve-P20Identity
$esc = [char]27
$bel = [char]7
$p = if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { Get-CliPrefix } else { '' }

# The refusal contract (AGENTS.md): exit 0 is success, exit 2 a stated refusal.
# A failed `az`/`gh` call used to leave its exit code behind a script that then
# `return`ed -- "No active PRs found." followed by the wrapper's reasonless
# "Error: exit code 1". Every way out of this script now says which.
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

# One PR query, and whether the tracker answered it. stderr is kept so a
# rejection can be NAMED rather than swallowed; `2>$null` is what hid it.
function Invoke-AdoPrList {
    param([string[]]$Arguments)
    $read = Invoke-P20TrackerRead 'az' (@('repos', 'pr', 'list') + @($Arguments) + @('--output', 'json'))
    $code = $read.Code
    $errText = (@($read.Err) -join ' ').Trim()
    $json = (@($read.Out) -join "`n")
    # Through a variable, then @(): Windows PowerShell 5.1 writes a JSON array as ONE
    # object, so @($json | ConvertFrom-Json) is a one-item list holding every PR.
    $items = @()
    if ($code -eq 0 -and $json) { try { $list = $json | ConvertFrom-Json; $items = @($list) } catch { $code = 1; $errText = 'az returned output that is not JSON' } }
    return @{ Ok = ($code -eq 0); Items = $items; Error = $errText }
}

# -- The dispatch: the board's address names the tracker that answers --------
# (D-G4.) A GitHub board asks gh: PRs you
# authored, and PRs awaiting your review, across the board's repos -- the
# owner-wide search is the WIQL org-wide shape. Same table, same links block.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
# Which space, which tracker.
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    $owner = Get-P20TrackerOwner -OrgUrl $org
    $ghPRs = @()
    $roleQueries = @(@{ Role = 'Author'; Flag = '--author' })
    if (-not $CreatorOnly) { $roleQueries += @{ Role = 'Reviewer'; Flag = '--review-requested' } }
    foreach ($q in $roleQueries) {
        $found = gh search prs $q.Flag '@me' --state open --owner $owner `
            --json 'number,title,repository,createdAt,url' --limit 50 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-CliError -Message "GitHub did not answer the PR search for $owner." -Hint "${p}Env shows the tier and whether gh is signed in."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        foreach ($pr in @($found)) {
            if ($ghPRs | Where-Object { $_.url -eq $pr.url }) { continue }
            $pr | Add-Member -NotePropertyName 'Role' -NotePropertyValue $q.Role -Force
            $ghPRs += $pr
        }
    }
    if ($ghPRs.Count -eq 0) {
        Write-Host "No active PRs found." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`n  My Active Pull Requests" -ForegroundColor Cyan
    Write-Host "  $('=' * 60)" -ForegroundColor DarkGray
    $sorted = $ghPRs | Sort-Object -Property @{Expression = 'Role'; Ascending = $true }, @{Expression = 'createdAt'; Descending = $true }
    $sorted | Format-Table @(
        @{ Label = "ID"; Expression = { $_.number }; Width = 8 }
        @{ Label = "Role"; Expression = { $_.Role }; Width = 10 }
        @{ Label = "Repo"; Expression = { $_.repository.nameWithOwner }; Width = 30 }
        @{ Label = "Title"; Expression = { $_.title.Substring(0, [Math]::Min(50, $_.title.Length)) }; Width = 52 }
        @{ Label = "Created"; Expression = { ([datetime]$_.createdAt).ToString("yyyy-MM-dd") }; Width = 12 }
    ) -AutoSize -Wrap
    Write-Host "  Links (Ctrl+Click to open):" -ForegroundColor DarkGray
    foreach ($pr in $sorted) {
        $link = $esc + "]8;;" + $pr.url + $bel + $pr.url + $esc + "]8;;" + $bel
        Write-Host "  PR #$($pr.number): " -NoNewline -ForegroundColor Cyan
        Write-Host $link -ForegroundColor Blue
    }
    Write-Host ""
    exit 0
}

$projects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo } })

$allPRs = @()
$failed = @()

foreach ($proj in $projects) {
    # PRs I created
    $q = Invoke-AdoPrList @('--org', $org, '--project', $proj.Name, '--repository', $proj.Repo, '--status', 'active', '--creator', $email)
    if (-not $q.Ok) {
        # Named, and the loop carries on: one wrong project name (the Example
        # org's placeholder YourProject is the common one) must not hide the
        # PRs of the projects that do exist.
        $why = if ($q.Error) { " -- az: $($q.Error)" } else { '' }
        Write-Host "  Project '$($proj.Name)' (repo '$($proj.Repo)') did not answer in $org$why" -ForegroundColor Yellow
        $failed += $proj.Name
        continue
    }
    $created = $q.Items

    if ($created) {
        $created | ForEach-Object {
            $_ | Add-Member -NotePropertyName "Role" -NotePropertyValue "Author" -Force
            $_ | Add-Member -NotePropertyName "Project" -NotePropertyValue $proj.Name -Force
            $_ | Add-Member -NotePropertyName "RepoName" -NotePropertyValue $proj.Repo -Force
        }
        $allPRs += $created
    }

    if (-not $CreatorOnly) {
        # PRs where I'm a reviewer
        $reviewing = (Invoke-AdoPrList @('--org', $org, '--project', $proj.Name, '--repository', $proj.Repo, '--status', 'active', '--reviewer', $email)).Items

        if ($reviewing) {
            # Exclude PRs already listed as author
            $authorIds = $allPRs | Where-Object { $_.Role -eq "Author" } | ForEach-Object { $_.pullRequestId }
            $reviewing = $reviewing | Where-Object { $_.pullRequestId -notin $authorIds }
            $reviewing | ForEach-Object {
                $_ | Add-Member -NotePropertyName "Role" -NotePropertyValue "Reviewer" -Force
                $_ | Add-Member -NotePropertyName "Project" -NotePropertyValue $proj.Name -Force
                $_ | Add-Member -NotePropertyName "RepoName" -NotePropertyValue $proj.Repo -Force
            }
            $allPRs += $reviewing
        }
    }
}

if ($projects.Count -gt 0 -and $failed.Count -eq $projects.Count) {
    Write-CliError -Message "No configured project answered in $org ($($failed -join ', '))." `
        -Hint "Check the active Space's project and repo names -- ${p}Env shows them; a placeholder like YourProject is not a real project."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if ($allPRs.Count -eq 0) {
    Write-Host "No active PRs found." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n  My Active Pull Requests" -ForegroundColor Cyan
Write-Host "  $('=' * 60)" -ForegroundColor DarkGray

$sorted = $allPRs | Sort-Object -Property @{Expression="Role"; Ascending=$true}, @{Expression="creationDate"; Descending=$true}

$sorted | Format-Table @(
    @{ Label = "ID";      Expression = { $_.pullRequestId }; Width = 8 }
    @{ Label = "Role";    Expression = { $_.Role }; Width = 10 }
    @{ Label = "Project"; Expression = { $_.Project }; Width = 30 }
    @{ Label = "Title";   Expression = { $_.title.Substring(0, [Math]::Min(50, $_.title.Length)) }; Width = 52 }
    @{ Label = "Created"; Expression = { ([datetime]$_.creationDate).ToString("yyyy-MM-dd") }; Width = 12 }
) -AutoSize -Wrap

Write-Host "  Links (Ctrl+Click to open):" -ForegroundColor DarkGray
foreach ($pr in $sorted) {
    $projEncoded = [Uri]::EscapeDataString($pr.Project)
    $url = "$org/$projEncoded/_git/$($pr.RepoName)/pullrequest/$($pr.pullRequestId)"
    $link = $esc + "]8;;" + $url + $bel + $url + $esc + "]8;;" + $bel
    Write-Host "  PR #$($pr.pullRequestId): " -NoNewline -ForegroundColor Cyan
    Write-Host $link -ForegroundColor Blue
}
Write-Host ""
exit 0
