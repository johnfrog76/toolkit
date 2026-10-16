<#
.SYNOPSIS
    Route -- answer triage's three questions for one issue, as real labels and a milestone (the Team Agile add-on).

.DESCRIPTION
    Team Agile's first WRITE (D-TA2, D-TA3, D-TA4; docs/modules/solitaire-agile.md,
    "The verbs"). Each switch given is ONE gh write on the Space's repo, in this
    order, and nothing else is written -- not the hub, not a store (D-TA2):

      -Size <label>        gh issue edit <n> --repo <repo> --add-label <size> --remove-label <the other sizes>
      -Milestone <title>   gh issue edit <n> --repo <repo> --milestone <title>
      -Severity <sevN>     gh issue edit <n> --repo <repo> --add-label <sevN> --remove-label <the other severities>
      -DeepWater           gh issue edit <n> --repo <repo> --add-label deep-water

    A size IS a worker label (D-TA3): a label on the repo whose description
    starts "Routed to" -- read with gh label list, so the sizes are whatever the
    repo carries. The severities and the deep-water label are
    Config/ceremonies.json's triage row. A milestone is one of the repo's OPEN
    milestones, by title (gh api repos/<repo>/milestones), matched ignoring case
    and written with the tracker's own spelling.

    -DeepWater only adds the label. Deep water gets two moves (D-TA4) -- assign
    a worker or split -- and the verb prints them as its hint; it makes neither for
    you.

    -WhatIf runs the reads (so every refusal still happens) and prints every gh
    write it would make, and makes none.

    Stated refusals (exit 2): no issue number; no switch; a severity that is not
    one of the ceremony's; an undeclared -Space; a Space whose tracker is not
    GitHub, or is local or archived; a repo that is ambiguous; gh missing; a
    size that is not a worker label on the repo; a milestone that is not one of
    its open milestones (the hint lists them); a gh write that fails.

.PARAMETER Number
    The issue's number on the Space's repo (a leading # is allowed).
.PARAMETER Size
    A worker label on the repo -- sonnet, opus or fable in this house.
.PARAMETER Milestone
    An open milestone's title.
.PARAMETER Severity
    sev1, sev2 or sev3 -- one at a time; the others are removed.
.PARAMETER DeepWater
    Add the deep-water label.
.PARAMETER Space
    A declared Space's slug, to write to instead of the one you are in.
.PARAMETER WhatIf
    Print the gh writes and make none.

.EXAMPLE
    {cliPrefix}Route 132 -Size opus -Milestone "Team Agile V1" -Severity sev3
.EXAMPLE
    {cliPrefix}Route 140 -DeepWater -WhatIf

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Number,
    [Parameter(Mandatory = $false)]
    [string]$Size,
    [Parameter(Mandatory = $false)]
    [string]$Milestone,
    [Parameter(Mandatory = $false)]
    [string]$Severity,
    [Parameter(Mandatory = $false)]
    [switch]$DeepWater,
    [Parameter(Mandatory = $false)]
    [string]$Space,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

$p = Get-CliPrefix
$usage = "${p}Route <n> [-Size <label>] [-Milestone <title>] [-Severity sev1|sev2|sev3] [-DeepWater] [-Space <slug>] [-WhatIf]"

if ($Help) {
    Write-Host ""
    Write-Host "  ${p}Route -- answer triage's three questions for one issue" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    $usage"
    Write-Host ""
    Write-Host "  One gh write per switch: a size (a worker label), a milestone, a severity, deep-water."
    Write-Host "  -WhatIf prints the writes and makes none. Nothing is written to the hub."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Triage-Rules.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

$row = (Get-P20TriageRow -PackageRoot $repoRoot).Row
$severities = @($row.severities | ForEach-Object { [string]$_ })
$deepLabel = [string]$row.deepWaterLabel

# -- What was asked, before anything is read ------------------------------------
$n = ([string]$Number).Trim().TrimStart('#')
if ($n -notmatch '^\d+$') {
    $what = 'Route needs an issue number.'
    if ($Number) { $what = "'$Number' is not an issue number." }
    Write-CliError -Message $what -Hint "Usage: $usage"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$n = [string]([int64]$n)
if (-not $Size -and -not $Milestone -and -not $Severity -and -not $DeepWater) {
    Write-CliError -Message "Nothing to route: give -Size, -Milestone, -Severity or -DeepWater." `
        -Hint "${p}Triage shows each open issue's answers so far. Usage: $usage"
    exit 2
}
$sev = ''
if ($Severity) {
    $sev = @($severities | Where-Object { $_ -ieq $Severity.Trim() }) | Select-Object -First 1
    if (-not $sev) {
        Write-CliError -Message "'$Severity' is not a severity." -Hint "One of: $($severities -join ', ')."
        exit 2
    }
}

# -- Which Space ----------------------------------------------------------------
$cfg = $global:P20Config
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
        exit 2
    }
    $org = [string]$entry.org
    $status = [string]$entry.status
    if ($entry.projects) { $projects = @($entry.projects) }
}
elseif ($cfg) {
    $org = [string]$cfg.Org
    $status = [string]$cfg.OrgStatus
    if ($cfg.Projects) { $projects = @($cfg.Projects) }
}

if ((Resolve-P20Tracker -OrgUrl $org) -ne 'github') {
    Write-CliError -Message "Route writes a GitHub issue's labels and milestone, and this Space's tracker is not GitHub." `
        -Hint "Triage and Route are GitHub-only for now; on Azure DevOps, ${p}EditItem changes a work item."
    exit 2
}
if ($status -eq 'local' -or $status -eq 'archive') {
    Write-CliError -Message "This Space is $status, so its tracker is not written." `
        -Hint "Connect it first: ${p}Connect <slug>."
    exit 2
}
$target = Resolve-P20TrackerRepo -OrgUrl $org -Projects $projects -CliPrefix $p
if ($target.Reason) {
    Write-CliError -Message $target.Reason -Hint $target.Hint
    exit 2
}
$repo = $target.Repo
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-CliError -Message 'gh is not installed, so nothing was written.' -Hint 'Install the GitHub CLI and run gh auth login.'
    exit 2
}

# -- The reads that make the answers checkable ----------------------------------
function Invoke-P20RouteGh {
    # One gh call -> @{ ok; out; reason }. stderr's first line is the reason.
    # The call itself is Invoke-P20TrackerRead's; this only shapes its answer.
    param([string[]]$Arguments)
    try { $read = Invoke-P20TrackerRead 'gh' $Arguments }
    catch { return @{ ok = $false; out = ''; reason = "gh did not answer ($($_.Exception.Message))" } }
    $code = $read.Code
    $stdout = @($read.Out) -join "`n"
    $stderr = @($read.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($code -ne 0) {
        $why = 'gh returned an error'
        if ($stderr.Count -gt 0) { $why = $stderr[0] }
        return @{ ok = $false; out = $stdout; reason = $why }
    }
    return @{ ok = $true; out = $stdout; reason = '' }
}

function Read-P20RouteJson {
    param([string[]]$Arguments, [string]$What)
    $got = Invoke-P20RouteGh -Arguments $Arguments
    if (-not $got.ok) {
        Write-CliError -Message "gh could not read $What for ${repo}: $($got.reason)" -Hint 'Nothing was written. gh auth status says whether gh is signed in.'
        exit 2
    }
    try { $parsed = ConvertFrom-Json -InputObject $got.out }
    catch {
        Write-CliError -Message "gh answered with something that is not JSON when asked for $What." -Hint 'Nothing was written.'
        exit 2
    }
    $list = New-Object System.Collections.ArrayList
    foreach ($x in $parsed) { if ($null -ne $x) { [void]$list.Add($x) } }
    return , $list.ToArray()
}

$sizeLabel = ''
$otherSizes = @()
if ($Size) {
    $labels = Read-P20RouteJson -What 'its labels' -Arguments @('label', 'list', '--repo', $repo, '--limit', '500', '--json', 'name,description')
    $workers = @(Get-P20StandupWorkers -Labels $labels -Prefix ([string](Get-P20Consts).rituals.workerLabelPrefix))
    $match = @($workers | Where-Object { [string]$_.label -ieq $Size.Trim() }) | Select-Object -First 1
    if (-not $match) {
        $known = @($workers | ForEach-Object { [string]$_.label })
        $hint = "A size is a worker label: one whose description starts '$((Get-P20Consts).rituals.workerLabelPrefix)'. $repo has none."
        if ($known.Count -gt 0) { $hint = "Sizes on ${repo}: $($known -join ', ')." }
        Write-CliError -Message "'$Size' is not a worker label on $repo." -Hint $hint
        exit 2
    }
    $sizeLabel = [string]$match.label
    $otherSizes = @($workers | ForEach-Object { [string]$_.label } | Where-Object { $_ -cne $sizeLabel })
}

$milestoneTitle = ''
if ($Milestone) {
    $rows = Read-P20RouteJson -What 'its milestones' -Arguments @('api', '--method', 'GET', "repos/$repo/milestones", '-f', 'state=open', '-F', 'per_page=100')
    $titles = @($rows | ForEach-Object { [string]$_.title } | Where-Object { $_ })
    $milestoneTitle = @($titles | Where-Object { $_ -ieq $Milestone.Trim() }) | Select-Object -First 1
    if (-not $milestoneTitle) {
        $hint = "$repo has no open milestone. Make one on GitHub first."
        if ($titles.Count -gt 0) { $hint = "Open milestones on ${repo}: $($titles -join '; ')." }
        Write-CliError -Message "No open milestone '$Milestone' on $repo." -Hint $hint
        exit 2
    }
}

# -- The writes: one per switch -------------------------------------------------
$writes = New-Object System.Collections.ArrayList
$base = @('issue', 'edit', $n, '--repo', $repo)
if ($sizeLabel) {
    $w = $base + @('--add-label', $sizeLabel)
    if ($otherSizes.Count -gt 0) { $w += @('--remove-label', ($otherSizes -join ',')) }
    [void]$writes.Add(@{ What = "size $sizeLabel"; Args = [string[]]$w })
}
if ($milestoneTitle) {
    [void]$writes.Add(@{ What = "milestone '$milestoneTitle'"; Args = [string[]]($base + @('--milestone', $milestoneTitle)) })
}
if ($sev) {
    $w = $base + @('--add-label', $sev)
    $others = @($severities | Where-Object { $_ -cne $sev })
    if ($others.Count -gt 0) { $w += @('--remove-label', ($others -join ',')) }
    [void]$writes.Add(@{ What = "severity $sev"; Args = [string[]]$w })
}
if ($DeepWater) {
    [void]$writes.Add(@{ What = $deepLabel; Args = [string[]]($base + @('--add-label', $deepLabel)) })
}

function Format-P20GhLine {
    param([string[]]$Arguments)
    $parts = @('gh') + @($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    return ($parts -join ' ')
}

$twoMoves = ''
if ($DeepWater -and $sizeLabel -cne 'fable') {
    $twoMoves = "Deep water gets two moves: assign Fable (${p}Route $n -Size fable) or split it into sized issues, each a sub-issue of #$n (${p}NewItem -Parent $n -Title <text>)."
}

# On stage: after the reads, before the writes and in -WhatIf -- one line
# when the repository is public. The reads above are unchanged and come first.
. (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
Write-P20PublicLine -Repo $repo

if ($WhatIf) {
    foreach ($w in $writes) { Write-Output "  [WhatIf] $(Format-P20GhLine $w.Args)" }
    Write-Output "  [WhatIf] No changes were made."
    if ($twoMoves) { Write-Output $twoMoves }
    exit 0
}

$done = New-Object System.Collections.ArrayList
foreach ($w in $writes) {
    $got = Invoke-P20RouteGh -Arguments $w.Args
    if (-not $got.ok) {
        $hint = 'Nothing was written.'
        if ($done.Count -gt 0) { $hint = "Written before it: $($done -join ', '). The rest was not tried." }
        Write-CliError -Message "gh did not write the $($w.What) on #${n}: $($got.reason)" -Hint $hint
        exit 2
    }
    [void]$done.Add($w.What)
}

Write-Output "Routed #$n on ${repo}: $($done -join ', ')."
if ($twoMoves) { Write-Output $twoMoves }
exit 0
