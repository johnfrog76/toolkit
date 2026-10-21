<#
.SYNOPSIS
    Triage -- the open issues by milestone, the ones nobody placed first (the Team Agile add-on).

.DESCRIPTION
    Team Agile V1's first ceremony with a write (D-TA5; docs/modules/solitaire-agile.md,
    "The verbs"). This verb is the READ: the open issues grouped by
    milestone, the group with no milestone first, then the milestones by open
    count; each issue one line -- number, title, who has it (me, @<login>, its
    worker -- the size, D-TA3 -- or nobody; D-AR10), severity or --, and
    deep-water marked; each milestone a context line, "N open, M routed,
    K unrouted". The answers are Route's.

    The rule is Scripts/Triage-Rules.ps1's, shared with the suite; this script
    is the thin layer: which Space, which repo, the gh reads, the printing.

        gh label list --repo <repo> --limit 500 --json name,description
        gh issue list --repo <repo> --state open --limit 500 --json number,title,state,labels,assignees,milestone,url
        gh api user -q .login     (best effort: who "me" is)

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
    Write-Host "  Who has each issue (me, @<login>, a size, or nobody), its severity and deep-water mark. Writes nothing; ${p}Route answers."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Triage-Rules.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Ritual-Common.ps1')

# -- Which Space ---------------------------------------------------------------
# No -Space: the one you are in. A slug: that Space's own entry, read without
# switching into it -- the same three things the agent's space_scope() takes.
# Scripts/Ritual-Common.ps1 holds the rule, shared with Standup and Route.
$cfg = $global:P20Config
# A name that is not $space: PowerShell variables are case-insensitive, so
# $space would be the same variable as the -Space PARAMETER above (the
# $help/[switch]$Help trap in AGENTS.md, same shape) and the assignment would
# coerce the resolved object into that parameter's [string] type.
$resolvedSpace = Resolve-P20RitualSpace -Space $Space -Config $cfg
$slug = $resolvedSpace.slug
$org = $resolvedSpace.org
$status = $resolvedSpace.status
$projects = $resolvedSpace.projects

$tracker = @{ ok = $false; reason = '' }
$viewer = ''
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
        # -- The thin layer: two gh reads (Scripts/Ritual-Common.ps1) --------
        $repo = $target.Repo
        $got = Invoke-P20RitualGh -Repo $repo -Arguments @('label', 'list', '--repo', $repo, '--limit', '500', '--json', 'name,description')
        if ($got.ok) {
            $labels = $got.value
            $got = Invoke-P20RitualGh -Repo $repo -Arguments @('issue', 'list', '--repo', $repo, '--state', 'open', '--limit', '500',
                '--json', 'number,title,state,labels,assignees,milestone,url')
        }
        if ($got.ok) {
            $issues = $got.value
            $tracker.ok = $true
            # Who you are on GitHub, so an issue assigned to you reads "me"
            # (D-AR10). Best effort: a viewer gh cannot name leaves every
            # assignee as @<login>, and the triage still answers.
            try {
                $me = Invoke-P20TrackerRead 'gh' @('api', 'user', '-q', '.login')
                $login = ((@($me.Out) -join "`n").Trim())
                if ($me.Code -eq 0 -and $login -match '^[A-Za-z0-9-]+$') { $viewer = $login }
            }
            catch { $viewer = '' }
        }
        else {
            $tracker.reason = $got.reason
            $labels = @()
        }
    }
}

# -- The fill, the rendering, the printing --------------------------------------
$triage = Invoke-P20TriageFill -Labels $labels -Issues $issues -Tracker $tracker -Space $slug -Viewer $viewer -PackageRoot $repoRoot
$triage.text = Format-P20TriageText -Triage $triage -PackageRoot $repoRoot

if ($AsJson) {
    Write-Output ($triage | ConvertTo-Json -Depth 8)
}
else {
    Write-Output ($triage.text.TrimEnd([char]10))
}
exit 0
