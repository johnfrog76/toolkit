<#
.SYNOPSIS
    Triage -- the open issues by milestone, the ones nobody placed first (the Team Agile add-on).

.DESCRIPTION
    Team Agile V1's first ceremony with a write (D-TA5; docs/modules/solitaire-agile.md,
    "The verbs"). This verb is the READ: the open issues grouped by
    milestone, the group with no milestone first, then the milestones by open
    count; each issue one line -- number, title, worker (the size, D-TA3) or
    --, severity or --, and deep-water marked; each milestone a context line,
    "N open, M routed, K unrouted". The answers are Route's.

    The rule is Scripts/Triage-Rules.ps1's, shared with the suite; this script
    is the thin layer: which Space, which repo, the two gh reads, the printing.

        gh label list --repo <repo> --limit 500 --json name,description
        gh issue list --repo <repo> --state open --limit 500 --json number,title,state,labels,milestone,url

    A GitHub Space only. An Azure DevOps or local Space, a Space whose repo is
    ambiguous, gh missing or not answering -- each prints the ceremony's title
    and a Tracker line saying why, and exits 0, the way Standup does. The one
    refusal is a -Space nobody declared (exit 2).

    Writes nothing: not the hub, not the tracker (D-TA2).

.PARAMETER Space
    A declared Space's slug, to read instead of the one you are in.
.PARAMETER AsJson
    Print the response GET /api/ritual/triage serves -- text included -- as JSON.

.EXAMPLE
    {cliPrefix}Triage
.EXAMPLE
    {cliPrefix}Triage -Space toolkit -AsJson

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Space,
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Triage -- the open issues by milestone, the ones nobody placed first" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}Triage [-Space <slug>] [-AsJson]"
    Write-Host ""
    Write-Host "  Each issue's worker (its size), severity and deep-water mark. Writes nothing; ${p}Route answers."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Triage-Rules.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')

# -- Which Space ---------------------------------------------------------------
# No -Space: the one you are in. A slug: that Space's own entry, read without
# switching into it -- the same three things the agent's space_scope() takes.
$cfg = $global:P20Config
$slug = ''
$org = ''
$status = ''
$projects = @()
if ($Space) {
    $spaceValue = $Space.Trim()
    $declared = @()
    if ($cfg -and $cfg.Spaces) { $declared = @($cfg.Spaces | Where-Object { $_ } | ForEach-Object { [string]$_.slug }) }
    $entry = $null
    if ($cfg -and $cfg.Spaces) { $entry = @($cfg.Spaces | Where-Object { $_ -and [string]$_.slug -eq $spaceValue }) | Select-Object -First 1 }
    if (-not $entry) {
        $hint = 'Leave -Space out for the Space you are in.'
        if ($declared.Count -gt 0) { $hint = "Declared: $($declared -join ', '). Or leave -Space out for the Space you are in." }
        Write-CliError -Message "No Space '$spaceValue' is declared." -Hint $hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $slug = $spaceValue
    $org = [string]$entry.org
    $status = [string]$entry.status
    if ($entry.projects) { $projects = @($entry.projects) }
}
elseif ($cfg) {
    $slug = [string]$cfg.ActiveSpace
    $org = [string]$cfg.Org
    $status = [string]$cfg.OrgStatus
    if ($cfg.Projects) { $projects = @($cfg.Projects) }
}

# -- The thin layer: two gh reads ----------------------------------------------
function Invoke-P20TriageGh {
    # One gh call -> @{ ok; value } or @{ ok = $false; reason }. stderr's first
    # line is the reason; the value is the parsed JSON array, enumerated so 5.1's
    # unrolled-array quirk cannot hand back an array of one array.
    param([string[]]$Arguments, [string]$Repo)
    $global:LASTEXITCODE = 0
    try { $out = & gh @Arguments 2>&1 }
    catch { return @{ ok = $false; reason = "gh did not answer ($($_.Exception.Message))" } }
    $code = $LASTEXITCODE
    $stdout = @($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ }) -join "`n"
    $stderr = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($code -ne 0) {
        $why = "gh did not answer for $Repo"
        if ($stderr.Count -gt 0) { $why += ": $($stderr[0])" }
        return @{ ok = $false; reason = $why }
    }
    try { $parsed = ConvertFrom-Json -InputObject $stdout }
    catch { return @{ ok = $false; reason = "gh answered for $Repo with something that is not JSON" } }
    $list = New-Object System.Collections.ArrayList
    foreach ($x in $parsed) { if ($null -ne $x) { [void]$list.Add($x) } }
    return @{ ok = $true; value = $list.ToArray() }
}

$tracker = @{ ok = $false; reason = '' }
$labels = @()
$issues = @()
$kind = Resolve-P20Tracker -OrgUrl $org
if ($kind -ne 'github') {
    # The worker labels, severities and milestones are GitHub's; ADO's door is a later spike.
    $tracker.reason = "This Space's tracker is not GitHub -- triage reads a GitHub Space's issues."
}
elseif ($status -eq 'local' -or $status -eq 'archive') {
    $tracker.reason = "This Space is $status, so its tracker is not asked."
}
else {
    $target = Resolve-P20TrackerRepo -OrgUrl $org -Projects $projects -CliPrefix (Get-CliPrefix)
    if ($target.Reason) {
        $tracker.reason = $target.Reason
    }
    elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $tracker.reason = 'gh is not installed, so the tracker was not asked.'
    }
    else {
        $repo = $target.Repo
        $got = Invoke-P20TriageGh -Repo $repo -Arguments @('label', 'list', '--repo', $repo, '--limit', '500', '--json', 'name,description')
        if ($got.ok) {
            $labels = $got.value
            $got = Invoke-P20TriageGh -Repo $repo -Arguments @('issue', 'list', '--repo', $repo, '--state', 'open', '--limit', '500',
                '--json', 'number,title,state,labels,milestone,url')
        }
        if ($got.ok) {
            $issues = $got.value
            $tracker.ok = $true
        }
        else {
            $tracker.reason = $got.reason
            $labels = @()
        }
    }
}

# -- The fill, the rendering, the printing --------------------------------------
$triage = Invoke-P20TriageFill -Labels $labels -Issues $issues -Tracker $tracker -Space $slug -PackageRoot $repoRoot
$triage.text = Format-P20TriageText -Triage $triage -PackageRoot $repoRoot

if ($AsJson) {
    Write-Output ($triage | ConvertTo-Json -Depth 8)
}
else {
    Write-Output ($triage.text.TrimEnd([char]10))
}
exit 0
