<#
.SYNOPSIS
    Route -- answer triage's three questions for one issue, as real labels and a milestone (the Team Agile add-on).

.DESCRIPTION
    Team Agile's first WRITE (D-TA2, D-TA3, D-TA4; docs/modules/solitaire-agile.md,
    "The verbs"). Each switch given is ONE gh write on the Space's repo, in this
    order, and nothing else is written -- not the hub, not a store (D-TA2;
    -Assign on a card, below, is the one hub write):

      -Size <label>        gh issue edit <n> --repo <repo> --add-label <size> --remove-label <the other sizes>
      -Assign me           gh issue edit <n> --repo <repo> --add-assignee @me
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

    -Assign says WHO takes it (D-AR10), on the tracker's own field where it has
    one. On a GitHub issue, -Assign me makes you the assignee and -Assign <size>
    IS the -Size write -- one worker label, the others removed. On a CARD -- an
    id of its own (K7M2), or any card in a Space with no tracker or a local one
    -- it writes one footer line through Set-P20CardLine (Write-CardText's
    bytes): `**Assigned:** me` or `**Assigned:** <size>` (consts.json
    stamps.assigned), and nothing else. A card's sizes are the repo's worker
    labels on a connected GitHub Space; a Space with no connected GitHub
    repository has none to read, so there -Assign <size> is refused and a card
    takes -Assign me alone. fable is the owner's own seat, a size like the others.

    -WhatIf runs the reads (so every refusal still happens) and prints every gh
    write it would make -- or the card line -- and makes none.

    Stated refusals (exit 2): no issue number or card id; no switch; a severity
    that is not one of the ceremony's; an undeclared -Space; a Space whose
    tracker is not GitHub (an Azure DevOps Space refuses -Assign too), or is
    local or archived for an issue; a repo that is ambiguous; gh missing; a size
    that is not a worker label on the repo; -Assign and -Size that disagree; a
    milestone that is not one of its open milestones (the hint lists them); a gh
    write that fails; on a card, any switch but -Assign, a value that is neither
    me nor a size, a size in a Space with no connected GitHub repository (no
    worker labels to read), or an id no card in current/ carries.

.PARAMETER Number
    The issue's number on the Space's repo (a leading # is allowed), or with
    -Assign a card's id or filename.
.PARAMETER Size
    A worker label on the repo -- sonnet, opus or fable in this house.
.PARAMETER Assign
    Who takes it: me, or a size (a worker label).
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
.EXAMPLE
    {cliPrefix}Route 4 -Assign me
.EXAMPLE
    {cliPrefix}Route K7M2 -Assign sonnet

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
    [string]$Assign,
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

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$p = Get-CliPrefix
$usage = "${p}Route <n|id> [-Size <label>] [-Assign me|<size>] [-Milestone <title>] [-Severity sev1|sev2|sev3] [-DeepWater] [-Space <slug>] [-WhatIf]"

if ($Help) {
    Write-Host ""
    Write-Host "  ${p}Route -- answer triage's three questions for one issue" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    $usage"
    Write-Host ""
    Write-Host "  One gh write per switch: a size (a worker label), an assignee, a milestone, a severity, deep-water."
    Write-Host "  -Assign me takes the issue yourself; -Assign <size> is -Size. On a card with no issue behind it,"
    Write-Host "  -Assign writes one **Assigned:** line and nothing else. -WhatIf prints the writes and makes none."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Triage-Rules.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Ritual-Common.ps1')

$row = (Get-P20TriageRow -PackageRoot $repoRoot).Row
$severities = @($row.severities | ForEach-Object { [string]$_ })
$deepLabel = [string]$row.deepWaterLabel

# -- What was asked, before anything is read ------------------------------------
$n = ([string]$Number).Trim().TrimStart('#')
$isNumber = ($n -match '^\d+$')
# -Assign is the one answer a card takes, so with it the argument may be a
# card's id or filename; without it, Route writes an issue and wants a number.
if (-not $isNumber -and -not ($Assign -and $Number)) {
    $what = 'Route needs an issue number.'
    if ($Number) { $what = "'$Number' is not an issue number." }
    Write-CliError -Message $what -Hint "Usage: $usage"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($isNumber) { $n = [string]([int64]$n) }
if (-not $Size -and -not $Assign -and -not $Milestone -and -not $Severity -and -not $DeepWater) {
    Write-CliError -Message "Nothing to route: give -Size, -Assign, -Milestone, -Severity or -DeepWater." `
        -Hint "${p}Triage shows each open issue's answers so far. Usage: $usage"
    exit 2
}
# Who (D-AR10): "me" is its own answer; anything else is a size, checked below
# against the sizes there are.
$meWord = [string](Get-P20Consts).rituals.assignMe
$assignMe = $false
$assignValue = ''
if ($Assign) {
    $assignValue = $Assign.Trim()
    if ($assignValue -ieq $meWord) { $assignMe = $true; $assignValue = $meWord }
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
# Scripts/Ritual-Common.ps1 holds the rule, shared with Standup and Triage.
$cfg = $global:P20Config
# A name that is not $space: PowerShell variables are case-insensitive, so
# $space would be the same variable as the -Space PARAMETER above (the
# $help/[switch]$Help trap in AGENTS.md, same shape) and the assignment would
# coerce the resolved object into that parameter's [string] type.
$resolvedSpace = Resolve-P20RitualSpace -Space $Space -Config $cfg
$org = $resolvedSpace.org
$status = $resolvedSpace.status
$projects = $resolvedSpace.projects
$trackerKind = Resolve-P20Tracker -OrgUrl $org

# A CARD is the target when -Assign names one: an id of its own (not a number),
# or any card in a Space whose tracker is not written -- none, or local. An
# Azure DevOps Space is never a target (the board holds the rituals there).
$cardMode = [bool]$Assign -and $trackerKind -ne 'ado' -and (-not $isNumber -or $trackerKind -eq 'none' -or $status -eq 'local')

if (-not $cardMode -and $trackerKind -ne 'github') {
    Write-CliError -Message "Route writes a GitHub issue's labels and milestone, and this Space's tracker is not GitHub." `
        -Hint "Triage and Route are GitHub-only for now; on Azure DevOps, ${p}EditItem changes a work item."
    exit 2
}

# -- A card: one **Assigned:** line, and nothing else ---------------------------
if ($cardMode) {
    if ($Size -or $Milestone -or $Severity -or $DeepWater) {
        Write-CliError -Message 'A card takes only -Assign: -Size, -Milestone, -Severity and -DeepWater write a GitHub issue.' `
            -Hint "Route the card's issue by its number on a connected GitHub Space, or give -Assign alone."
        exit 2
    }
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
    . (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
    $hubRoot = ''
    if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
    if (-not (Test-P20HubRoot $hubRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $hubRoot)
        exit 2
    }
    $spaceRoot = $hubRoot
    if ($resolvedSpace.promptsFolder) { $spaceRoot = Join-Path $hubRoot ([string]$resolvedSpace.promptsFolder) }
    $currentDir = Join-Path $spaceRoot ([string](Get-P20Consts).folders.current)
    $types = Get-P20WorkItemTypes -Config $cfg
    $resolved = Resolve-P20CardArgument -Argument ([string]$Number).Trim() -Folder $currentDir -WorkItemTypes $types
    $found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
    if ($found.Count -eq 0) {
        if ($resolved.IsId) {
            Write-CliError -Message "No card with id '$Number' in current/." `
                -Hint "'$Number' has the shape of an ID, and an ID is not a partial name. Run '${p}Status' to see the cards."
        }
        else {
            Write-CliError -Message "No card matching '$Number' in current/." -Hint "Run '${p}Status' to see the cards."
        }
        exit 2
    }
    if ($found.Count -gt 1) {
        Write-Host "Matches for '$Number':" -ForegroundColor Yellow
        $found | ForEach-Object { Write-Host "  $($_.Name)" }
        Write-CliError -Message "'$Number' matches $($found.Count) cards in current/." -Hint 'Pass the full filename of the one you mean.'
        exit 2
    }
    if ($resolved.Fuzzy) {
        # A partial name is a convenience in a terminal, said before the write;
        # a caller that cannot read that line (the bridge) is refused.
        if ($env:TOOLKIT_QUIET_STARTUP) {
            Write-CliError -Message "'$Number' is not a card in current/; it matches '$($found[0].Name)' only by partial name." `
                -Hint "Pass the card's id or its full filename."
            exit 2
        }
        Write-Host "Matched '$Number' -> $($found[0].Name)" -ForegroundColor Cyan
    }
    $file = $found[0]

    # The sizes are the repo's worker labels -- the list -Size reads -- and
    # nothing else (D-AR10: no second list). A Space with no connected GitHub
    # repository has no labels to read, so there a card takes -Assign me alone.
    $sizes = @()
    $sizeSource = ''
    if (-not $assignMe) {
        if ($trackerKind -ne 'github' -or $status -eq 'local' -or $status -eq 'archive') {
            Write-CliError -Message "'$Assign' cannot be checked as a size: this Space has no connected GitHub repository, so there are no worker labels to read." `
                -Hint "On a card here -Assign takes $meWord alone. A size is a worker label on a connected GitHub Space's repository."
            exit 2
        }
        $target = Resolve-P20TrackerRepo -OrgUrl $org -Projects $projects -CliPrefix $p
        if ($target.Reason) {
            Write-CliError -Message $target.Reason -Hint $target.Hint
            exit 2
        }
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-CliError -Message 'gh is not installed, so the sizes could not be read and nothing was written.' -Hint 'Install the GitHub CLI and run gh auth login.'
            exit 2
        }
        $got = Invoke-P20TrackerRead 'gh' @('label', 'list', '--repo', $target.Repo, '--limit', '500', '--json', 'name,description')
        $labels = @()
        if ($got.Code -eq 0) { try { $labels = @((@($got.Out) -join "`n") | ConvertFrom-Json) } catch { $labels = @() } }
        else {
            $why = @($got.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) | Select-Object -First 1
            if (-not $why) { $why = 'gh returned an error' }
            Write-CliError -Message "gh could not read its labels for $($target.Repo): $why" -Hint 'Nothing was written. gh auth status says whether gh is signed in.'
            exit 2
        }
        $sizes = @(Get-P20StandupWorkers -Labels $labels -Prefix ([string](Get-P20Consts).rituals.workerLabelPrefix) | ForEach-Object { [string]$_.label })
        $sizeSource = "the worker labels on $($target.Repo)"
    }
    $value = $meWord
    if (-not $assignMe) {
        $value = @($sizes | Where-Object { $_ -ieq $assignValue }) | Select-Object -First 1
        if (-not $value) {
            $known = @($meWord) + @($sizes)
            Write-CliError -Message "'$Assign' is neither $meWord nor a size." -Hint "-Assign takes one of: $($known -join ', ') ($sizeSource)."
            exit 2
        }
    }
    $stamp = [string](Get-P20Consts).stamps.assigned
    $label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
    if (-not $label) { $label = $file.Name }
    if ($WhatIf) {
        Write-Output "  [WhatIf] $($file.Name): $stamp $value"
        Write-Output "  [WhatIf] No changes were made."
        exit 0
    }
    $changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Value $value
    if ($changed) { Write-Output "Assigned $label to ${value}: $stamp $value ($($file.Name))." }
    else { Write-Output "$label already says $stamp $value -- nothing written." }
    exit 0
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

# -Assign <size> on an issue IS the -Size write (D-AR10, D-TA3: the label is the size).
if ($Assign -and -not $assignMe) {
    if ($Size -and $Size.Trim() -ine $assignValue) {
        Write-CliError -Message "-Assign $assignValue and -Size $Size disagree." -Hint "On an issue -Assign <size> is the -Size write: give one of them."
        exit 2
    }
    $Size = $assignValue
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
if ($assignMe) {
    # You take it: the assignee is gh's own @me, the signed-in user.
    [void]$writes.Add(@{ What = 'assignee @me'; Args = [string[]]($base + @('--add-assignee', '@me')) })
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
