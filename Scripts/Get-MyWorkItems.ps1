<#
.SYNOPSIS
    Lists the work items assigned to you, from the board's own tracker.
.DESCRIPTION
    The verb is the same on every board; WHICH tracker answers follows the
    board's address (D-G4): an Azure DevOps
    board runs a WIQL query through az, a GitHub board searches your assigned
    issues through gh. One table shape either way.
.PARAMETER State
    Filter by state. On an ADO board: a WIQL state ("Active", "New"), default
    all non-closed. On a GitHub board: open, closed or all, default open.
#>
[CmdletBinding()]
param(
    [string]$State
)

$cfg = $global:P20Config
$org = $cfg.Org
$esc = [char]27
$bel = [char]7

# -- The dispatch: the board's address names the tracker that answers --------
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
# Which space, which tracker.
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    $owner = Get-P20TrackerOwner -OrgUrl $org
    # An owner/repo-grained address scopes the search to that one repo; an
    # owner-grained one spans everything of theirs, the WIQL org-wide shape.
    $rest = ("$org".Trim() -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '').Split('/')
    $repoGrain = if ($rest.Count -ge 3 -and $rest[2]) { "$owner/$($rest[2])" } else { $null }

    $ghState = switch -Regex ("$State") {
        '^(?i)closed$' { 'closed'; break }
        '^(?i)all$' { 'all'; break }
        default { 'open' }
    }
    $ghArgs = @('search', 'issues', '--assignee', '@me', '--state', $ghState,
        '--json', 'number,title,state,repository,updatedAt,url', '--limit', '50')
    if ($repoGrain) { $ghArgs += @('--repo', $repoGrain) } else { $ghArgs += @('--owner', $owner) }

    $issues = gh @ghArgs 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        $p = if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { Get-CliPrefix } else { '' }
        Write-Host "GitHub did not answer for $owner -- ${p}Env shows the tier." -ForegroundColor Yellow
        return
    }
    if (-not $issues -or @($issues).Count -eq 0) {
        Write-Host "No assigned issues found." -ForegroundColor Yellow
        return
    }

    Write-Host "`n  My Assigned Issues" -ForegroundColor Cyan
    Write-Host "  $('=' * 60)" -ForegroundColor DarkGray
    $sorted = @($issues) | Sort-Object -Property updatedAt -Descending
    $sorted | Format-Table @(
        @{ Label = "ID"; Expression = { $_.number }; Width = 8 }
        @{ Label = "State"; Expression = { $_.state.ToLowerInvariant() }; Width = 10 }
        @{ Label = "Repo"; Expression = { $_.repository.nameWithOwner }; Width = 30 }
        @{ Label = "Title"; Expression = {
                $t = $_.title
                if ($t.Length -gt 45) { $t.Substring(0, 42) + "..." } else { $t }
            }; Width = 47
        }
        @{ Label = "Updated"; Expression = { ([datetime]$_.updatedAt).ToString("yyyy-MM-dd") }; Width = 12 }
    ) -AutoSize -Wrap

    Write-Host "  Links (Ctrl+Click to open):" -ForegroundColor DarkGray
    foreach ($issue in $sorted) {
        $link = $esc + "]8;;" + $issue.url + $bel + $issue.url + $esc + "]8;;" + $bel
        Write-Host "  #$($issue.number): " -NoNewline -ForegroundColor Cyan
        Write-Host $link -ForegroundColor Blue
    }
    Write-Host ""
    return
}

$projects = @($cfg.Projects | ForEach-Object { $_.name })

$stateFilter = if ($State) {
    "AND [System.State] = '$State'"
}
else {
    "AND [System.State] NOT IN ('Closed', 'Done', 'Removed', 'Resolved')"
}

$allItems = @()
$seenIds = @{}

# WIQL with no [System.TeamProject] clause is ORG-WIDE, so this only needs one
# query -- looping the configured projects returned the same set every time and
# the dedupe below hid it. More importantly the project label was taken from the
# loop variable, so every item was stamped with whichever project happened to be
# first in config. On a cross-repo view that is the one field that has to be
# right, so it now comes from the item itself.
$wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.TeamProject], [System.IterationPath], [System.ChangedDate] FROM WorkItems WHERE [System.AssignedTo] = @Me $stateFilter ORDER BY [System.ChangedDate] DESC"

# az boards query needs *a* project for the call even though the WIQL spans the
# org. Prefer one that actually has a repo: config carries placeholder projects
# with hasRepo=false, and the first of those was being used, which is both
# fragile and misleading in any error message the call produces.
$realProjects = @($cfg.Projects | Where-Object { $_.hasRepo -ne $false } | ForEach-Object { $_.name })
$queryProject = if ($realProjects.Count -gt 0) { $realProjects[0] }
                elseif ($projects.Count -gt 0) { $projects[0] }
                else { $null }
$result = az boards query `
    --org $org `
    --project $queryProject `
    --wiql $wiql `
    --output json 2>$null | ConvertFrom-Json

if ($result) {
    $result | ForEach-Object {
        if (-not $seenIds.ContainsKey($_.id)) {
            $seenIds[$_.id] = $true
            $itemProject = $_.fields.'System.TeamProject'
            if (-not $itemProject) { $itemProject = '(unknown)' }
            $_ | Add-Member -NotePropertyName "Project" -NotePropertyValue $itemProject -Force
            $allItems += $_
        }
    }
}

if ($allItems.Count -eq 0) {
    Write-Host "No assigned work items found." -ForegroundColor Yellow
    return
}

Write-Host "`n  My Assigned Work Items" -ForegroundColor Cyan
Write-Host "  $('=' * 60)" -ForegroundColor DarkGray

$sorted = $allItems | Sort-Object -Property { $_.fields.'System.ChangedDate' } -Descending

$sorted | Format-Table @(
    @{ Label = "ID"; Expression = { $_.id }; Width = 8 }
    @{ Label = "Type"; Expression = { $_.fields.'System.WorkItemType' }; Width = 14 }
    @{ Label = "State"; Expression = { $_.fields.'System.State' }; Width = 10 }
    @{ Label = "Project"; Expression = { $_.Project }; Width = 30 }
    @{ Label = "Title"; Expression = {
            $t = $_.fields.'System.Title'
            if ($t.Length -gt 45) { $t.Substring(0, 42) + "..." } else { $t }
        }; Width = 47
    }
    @{ Label = "Updated"; Expression = { ([datetime]$_.fields.'System.ChangedDate').ToString("yyyy-MM-dd") }; Width = 12 }
) -AutoSize -Wrap

Write-Host "  Links (Ctrl+Click to open):" -ForegroundColor DarkGray
foreach ($wi in $sorted) {
    $projEncoded = [Uri]::EscapeDataString($wi.Project)
    $url = "$org/$projEncoded/_workitems/edit/$($wi.id)"
    $link = $esc + "]8;;" + $url + $bel + $url + $esc + "]8;;" + $bel
    Write-Host "  #$($wi.id): " -NoNewline -ForegroundColor Cyan
    Write-Host $link -ForegroundColor Blue
}
Write-Host ""
