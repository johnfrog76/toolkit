<#
.SYNOPSIS
    Standup -- today's standup, filled from the tracker (the Solitaire Agile add-on).

.DESCRIPTION
    The Ritual Engine's first ceremony, as text (docs/modules/solitaire-agile.md, "The file shape, and how a standup is read"). The human's queue first, then one block per worker label --
    yesterday, today and blockers, each line a real issue with its number, or the
    mug and one status sentence ("Nothing on the board for me...") when a worker has nothing.

    The rule is Scripts/Standup-Rules.ps1's, shared with the suite; this script is
    the thin layer around it: which Space, which repo, the two gh reads, and the
    printing. Two reads, both on the Space's ONE repo (Resolve-P20TrackerRepo, the
    rule every GitHub verb uses):

        gh label list --repo <repo> --limit 500 --json name,description
        gh issue list --repo <repo> --state all --limit 500 --json number,title,state,labels,closedAt,url,milestone,body,createdAt,assignees

    milestone and body are the work grain's: an item groups by its
    milestone, else by the design card its body names. createdAt and
    assignees are the suggestion's (Scripts/Suggest-Rules.ps1): its age, and who
    has it.

    The suggestion: over the same read, one derived next move (the joined list,
    Select-P20Suggestion). With nothing waiting on you, the brief's last line is
    its sentence and the command that acts on it, in place of "Next: nothing is
    waiting on you." -- never above the queue's own line (D-AR7). Off where the
    Space says spaces.<slug>.features.suggestions=false. -AsJson carries every
    candidate as suggestions[] and the first as suggestion.

    The same Space's CARDS are read too (Get-P20StandupCards) and joined to the
    issues on the id by Invoke-P20StandupJoinedFill: a card whose id is an
    issue's number adds its lane, and a Check line where the two disagree; a card
    of its own is a row under you; a not-billable card is not a row.

    A Space with no tracker address, or a local or archive one, fills from its
    CARDS alone: the hub's current/ and archive/ for that Space, read by
    Get-P20StandupCards and filled by Invoke-P20StandupCardsFill -- no gh call.

    The ritual happens anyway (principle 3): an Azure DevOps Space (D-TA19), a
    Space whose repo is ambiguous, gh missing or not answering -- each still
    prints the standup, with tracker.ok false and the reason on its Tracker line,
    and exits 0. That is not a refusal. The one refusal is a -Space nobody
    declared (exit 2), which the agent's route answers with a 404.

    Writes nothing: not the hub, not the tracker, no timestamp of the last run
    (D-SA3: "since the last standup" is since the previous working day began).

.PARAMETER Space
    A declared Space's slug, to read instead of the one you are in.
.PARAMETER Json
    Print the response GET /api/ritual/standup serves -- text included -- as JSON.
.PARAMETER Brief
    Print only the chair's reading: a few lines, each a count or a derived
    fact -- what waits on you by kind, each worker as closed / open / in flight /
    blockers, and the one thing next. No model. -AsJson carries it as `brief`
    whether or not this is given. Reading is not attending: -Brief does not
    re-arm the reminder.
.PARAMETER Grain
    detail, work or brief (consts.json rituals.grains, D-TA20) -- the
    register of detail the standup is printed in. detail (the default) is every
    item with its number; work is the ritual's grain: each worker's items grouped
    by milestone, else the design card the issue names, else the titles' common
    stem, and spoken as standup prose -- one sentence a group, a grammar over
    the groups and no model; brief is -Brief's reading, and like -Brief it is
    a read, not attending. Anything else is a stated refusal. -AsJson carries all
    three whatever this says.
.PARAMETER Remind
    HH:mm. Write the reminder to attend (D-TA15): ONE Organize reminder,
    source standup, through NewReminder -- or, when one is open, rewrite its due
    and cadence through Reminders -- and print nothing of the standup. Needs
    features.organize. Scripts/Standup-Remind.ps1 holds the rule.
.PARAMETER Days
    With -Remind: the days, comma-separated or as a range (default Mon-Fri).

    Attending re-arms it: a run without -Remind archives the open standup
    reminder and writes the next day's, through the same two Organize verbs,
    once a day -- silent when it works, one line when it does not, never a
    refusal. With features.organize off it does nothing.

.PARAMETER Since
    yyyy-MM-dd. Widen yesterday's window back to that day: every issue closed
    and every card archived since it is said, and the counts line -- the first
    line of the brief -- sums the window: closed, started, in progress and
    commits, per worker and in total. Today and the blockers do not move: they
    are what is open now. The default is the previous working day (D-SA3). Not
    -Days, which is the reminder's cadence. A day that is not one, or is after
    today, is a stated refusal.

.PARAMETER Walk
    Print ONLY the walk list: each open verify-close issue by number, and
    under it the VERIFY.md Gate 12 row that names it (or "no VERIFY row"). A walker's
    morning as one printout. With -AsJson: walk[] of { number, title, url, verifyRow }.
    A read, not attending: it does not re-arm the reminder. Not with -Remind.

.EXAMPLE
    {cliPrefix}Standup
.EXAMPLE
    {cliPrefix}Standup -Brief
.EXAMPLE
    {cliPrefix}Standup -Grain work
.EXAMPLE
    {cliPrefix}Standup -Space toolkit -AsJson
.EXAMPLE
    {cliPrefix}Standup -Since <yyyy-MM-dd> -Brief
.EXAMPLE
    {cliPrefix}Standup -Remind 09:00 -Days Mon,Wed,Fri

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
    [switch]$Brief,
    [Parameter(Mandatory = $false)]
    [string]$Grain,
    [Parameter(Mandatory = $false)]
    [string]$Remind,
    [Parameter(Mandatory = $false)]
    [string[]]$Days,
    [Parameter(Mandatory = $false)]
    [switch]$Walk,
    [Parameter(Mandatory = $false)]
    [string]$Since,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Standup -- today's standup, filled from the tracker" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail|work|brief>] [-Since <yyyy-MM-dd>]"
    Write-Host "    ${p}Standup -Walk [-Space <slug>] [-AsJson]"
    Write-Host "    ${p}Standup -Remind <HH:mm> [-Days <Mon,Tue,...>]"
    Write-Host ""
    Write-Host "  The queue waiting on you, then one block per worker label. Writes nothing"
    Write-Host "  to the tracker. -Brief prints only the chair's reading, in a few lines. -Grain work speaks"
    Write-Host "  at the grain of the work: items grouped by milestone or feature, one sentence a group."
    Write-Host "  Each item says what moved -- closed, started or in progress, and its card's commits -- and the"
    Write-Host "  brief opens on the counts. -Since <yyyy-MM-dd> widens yesterday back to that day."
    Write-Host "  -Remind sets an Organize reminder to attend (features.organize);"
    Write-Host "  attending -- running Standup -- re-arms it for the next day in the cadence."
    Write-Host ""
    return
}

# -- The reminder to attend (D-TA15) ------------------------------------
# -Remind writes it and prints nothing else; the rule and the two Organize verb
# calls are Scripts/Standup-Remind.ps1's. Attending is the block at the bottom.
. (Join-Path $PSScriptRoot 'Standup-Remind.ps1')
if ($Walk -and $PSBoundParameters.ContainsKey('Remind')) {
    Write-CliError -Message '-Walk and -Remind are one thing at a time.' -Hint "$(Get-CliPrefix)Standup -Walk (reads the walk list), or $(Get-CliPrefix)Standup -Remind 09:00 (sets the reminder)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($PSBoundParameters.ContainsKey('Since') -and $PSBoundParameters.ContainsKey('Remind')) {
    Write-CliError -Message '-Since and -Remind are one thing at a time.' -Hint "$(Get-CliPrefix)Standup -Since 2026-10-12 (reads the window), or $(Get-CliPrefix)Standup -Remind 09:00 (sets the reminder)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($PSBoundParameters.ContainsKey('Days') -and -not $PSBoundParameters.ContainsKey('Remind')) {
    Write-CliError -Message '-Days goes with -Remind.' -Hint "$(Get-CliPrefix)Standup -Remind 09:00 -Days Mon,Wed,Fri"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
# -- The grain (D-TA20) ---------------------------------------------------
# detail | work | brief, consts.json rituals.grains. -Brief is the brief grain.
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-Consts.ps1') }
$grains = @((Get-P20Consts).rituals.grains | ForEach-Object { [string]$_ })
$grainName = $grains[0]
if ($Brief) { $grainName = $grains[2] }
if ($PSBoundParameters.ContainsKey('Grain')) {
    $asked = ([string]$Grain).Trim().ToLowerInvariant()
    if ($grains -cnotcontains $asked) {
        Write-CliError -Message "-Grain '$Grain' is not a grain." -Hint "One of: $($grains -join ', '). $(Get-CliPrefix)Standup -Grain $($grains[1])"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($Brief -and $asked -cne $grains[2]) {
        Write-CliError -Message "-Brief is the $($grains[2]) grain; -Grain $asked is another." -Hint "$(Get-CliPrefix)Standup -Brief, or $(Get-CliPrefix)Standup -Grain $asked"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $grainName = $asked
}

if ($PSBoundParameters.ContainsKey('Remind')) {
    $reminded = Invoke-P20StandupRemind -Time $Remind -Days $Days -PackageRoot $repoRoot -CliPrefix (Get-CliPrefix)
    if ($reminded.Code -ne 0) {
        # A refusal the Organize verb stated has been printed already: say it once.
        if ($reminded.Stated) { $global:P20StatedError = $reminded.Message }
        else { Write-CliError -Message $reminded.Message -Hint $reminded.Hint }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-Host $reminded.Line -ForegroundColor Green
    exit 0
}

. (Join-Path $PSScriptRoot 'Standup-Rules.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Ritual-Common.ps1')

# -- The window -------------------------------------------------------
# -Since moves yesterday's lower bound back; today and the blockers stay what is
# open now. One clock for the check and the fill. Test-P20StandupSince holds the
# rule, the agent's since_refusal the same one.
$asOf = [DateTimeOffset]::Now
$window = ''
if ($PSBoundParameters.ContainsKey('Since')) {
    $why = Test-P20StandupSince -AsOf $asOf -Since $Since
    if (-not $why -and -not ([string]$Since).Trim()) { $why = "-Since '' is not a day: yyyy-MM-dd." }
    if ($why) {
        Write-CliError -Message $why -Hint "$(Get-CliPrefix)Standup -Since $($asOf.AddDays(-3).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture))"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $window = ([string]$Since).Trim()
}

# -- Which Space ---------------------------------------------------------------
# No -Space: the one you are in. A slug: that Space's own entry, read without
# switching into it -- the same three things the agent's space_scope() takes.
# Scripts/Ritual-Common.ps1 holds the rule, shared with Triage and Route.
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
$spaceName = $resolvedSpace.spaceName
$promptsFolder = $resolvedSpace.promptsFolder

# -- Which source ---------------------------------------------------------
# GitHub -> its issues AND its cards, joined on the id; no tracker address, or a
# local/archive Space -> its cards; Azure DevOps -> the Tracker line (D-TA19). One
# pure rule, Get-P20StandupSource, held to the agent's by
# Tests/fixtures/rituals/standup-cards.json.
$choice = Get-P20StandupSource -Address $org -Status $status

$tracker = @{ ok = $false; reason = '' }
$labels = @()
$issues = @()
if ($choice.source -eq 'none') {
    # D-TA19: Azure DevOps is the human team's board; the sentence is consts.json's.
    $tracker.reason = $choice.reason
}
elseif ($choice.source -eq 'both') {
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
            $got = Invoke-P20RitualGh -Repo $repo -Arguments @('issue', 'list', '--repo', $repo, '--state', 'all', '--limit', '500',
                '--json', 'number,title,state,labels,closedAt,url,milestone,body,createdAt,assignees')
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
$cards = @()
if ($choice.source -eq 'cards' -or $choice.source -eq 'both') {
    # The Space's own current/ and archive/, read by the rules every card verb uses.
    $hubRoot = ''
    if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
    $spaceDir = $hubRoot
    if ($hubRoot -and $promptsFolder) { $spaceDir = Join-Path $hubRoot $promptsFolder }
    $folderNames = (Get-P20Consts).folders
    if ($spaceDir) {
        $pattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
        $cards = @(Get-P20StandupCards -CurrentDir (Join-Path $spaceDir $folderNames.current) `
                -ArchiveDir (Join-Path $spaceDir $folderNames.archive) -Pattern $pattern)
    }
}
if ($choice.source -eq 'cards') {
    $standup = Invoke-P20StandupCardsFill -AsOf $asOf -Cards $cards -Space $slug -SpaceName $spaceName `
        -Window $window -PackageRoot $repoRoot
}
elseif ($choice.source -eq 'both') {
    $standup = Invoke-P20StandupJoinedFill -AsOf $asOf -Labels $labels -Issues $issues -Tracker $tracker `
        -Cards $cards -Space $slug -SpaceName $spaceName -Window $window -PackageRoot $repoRoot
}
else {
    $standup = Invoke-P20StandupFill -AsOf $asOf -Labels $labels -Issues $issues -Tracker $tracker `
        -Space $slug -Window $window -PackageRoot $repoRoot
}
# -- The suggestion ---------------------------------------------------------
# One derived next move over the same read (Scripts/Suggest-Rules.ps1), before
# the brief renders it. On where Team Agile is on -- it is, or this verb would
# not be registered -- and the Space has not said features.suggestions=false.
if ($choice.source -eq 'cards' -or $choice.source -eq 'both') {
    . (Join-Path $PSScriptRoot 'Suggest-Rules.ps1')
    $spaceEntry = $null
    if ($cfg -and $cfg.Spaces) { $spaceEntry = @($cfg.Spaces | Where-Object { $_ -and [string]$_.slug -eq $slug }) | Select-Object -First 1 }
    $storedSwitch = $null
    if ($spaceEntry -and $spaceEntry.features -and $spaceEntry.features.PSObject.Properties['suggestions']) { $storedSwitch = $spaceEntry.features.suggestions }
    $teamAgile = $true
    if (Get-Command Get-P20Features -ErrorAction SilentlyContinue) { $teamAgile = [bool]((Get-P20Features)['solitaireAgile']) }
    $howStored = ''
    if ($spaceEntry -and $spaceEntry.PSObject.Properties['howIWork']) { $howStored = [string]$spaceEntry.howIWork }
    if (-not (Get-Command Resolve-P20HowIWork -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Resolve-HowIWork.ps1') }
    $how = Resolve-P20HowIWork -OrgUrl $org -Stored $howStored
    $suggestOn = Test-P20SuggestionsOn -TeamAgile $teamAgile -Stored $storedSwitch
    # Who "me" is: triage's one read (Ritual-Common.ps1), once per standup, and only
    # where an issue read happened -- a cards Space has no assignee to compare.
    $viewer = ''
    if ($suggestOn -and $choice.source -eq 'both' -and $tracker.ok) { $viewer = Get-P20RitualViewer }
    $null = Add-P20StandupSuggestion -Standup $standup -Labels $labels -Issues $issues -Cards $cards -HowIWork ([string]$how.answer) `
        -On $suggestOn -Prefix (Get-CliPrefix) -Viewer $viewer -PackageRoot $repoRoot
    # The PM Corner (Scripts/Corner-Rules.ps1): the suggestion's second surface --
    # the same switch, the same read, the same pick -- and the brief's last line.
    . (Join-Path $PSScriptRoot 'Corner-Rules.ps1')
    $null = Add-P20StandupCorner -Standup $standup -Labels $labels -Issues $issues -Cards $cards `
        -On $suggestOn -Prefix (Get-CliPrefix) -Viewer $viewer -PackageRoot $repoRoot
}
$standup.text = Format-P20StandupText -Standup $standup -PackageRoot $repoRoot
$standup.work.text = Format-P20StandupWork -Standup $standup -PackageRoot $repoRoot
$standup['brief'] = Format-P20StandupBrief -Standup $standup -PackageRoot $repoRoot

# -- The walk list -----------------------------------------------------------
# Only the queue's walk kind, each issue with the VERIFY.md Gate 12 row that names
# it. A read for whoever walks, not the standup: it does not attend, so it does not re-arm.
if ($Walk) {
    $walkItems = @($standup.queue.walk | Where-Object { $null -ne $_ } |
            Sort-Object { if ($null -ne $_.number) { [int]$_.number } else { [int]::MaxValue } })
    $verifyLines = @()
    $verifyPath = Join-Path $repoRoot 'VERIFY.md'
    if (Test-Path -LiteralPath $verifyPath) {
        $verifyLines = @([System.IO.File]::ReadAllText($verifyPath) -split "`r?`n")
    }
    # A row is a "- [ ]" / "- [x]" bullet and its indented continuation lines.
    $rows = New-Object System.Collections.ArrayList
    $rowLines = $null
    foreach ($ln in $verifyLines) {
        if ($ln -match '^- \[[ xX]\] ') {
            if ($rowLines) { [void]$rows.Add(($rowLines -join "`n")) }
            $rowLines = New-Object System.Collections.Generic.List[string]
            $rowLines.Add($ln)
        }
        elseif ($rowLines -and $ln -match '^\s+\S') { $rowLines.Add($ln) }
        else {
            if ($rowLines) { [void]$rows.Add(($rowLines -join "`n")) }
            $rowLines = $null
        }
    }
    if ($rowLines) { [void]$rows.Add(($rowLines -join "`n")) }
    $walkOut = New-Object System.Collections.ArrayList
    foreach ($w in $walkItems) {
        $found = @()
        if ($null -ne $w.number) {
            $pat = '#' + [int]$w.number + '(?!\d)'
            $found = @($rows | Where-Object { $_ -match $pat })
        }
        $verifyRow = $null
        if ($found.Count -gt 0) { $verifyRow = $found -join "`n" }
        [void]$walkOut.Add([ordered]@{ number = $w.number; id = $w.id; title = [string]$w.title; url = [string]$w.url; verifyRow = $verifyRow })
    }
    if ($AsJson) {
        $jsonWalk = @($walkOut | ForEach-Object { [ordered]@{ number = $_.number; title = $_.title; url = $_.url; verifyRow = $_.verifyRow } })
        Write-Output ([ordered]@{ walk = [object[]]$jsonWalk } | ConvertTo-Json -Depth 5)
        exit 0
    }
    $ritual = Get-P20RitualData -PackageRoot $repoRoot
    $t = $ritual.Rituals.text
    $width = [int]$ritual.Rituals.labelWidth
    $at = ConvertTo-P20RitualTime $standup.asOf
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add(([string]$t.title).Replace('{date}', $at.ToString([string]$t.dateFormat, [System.Globalization.CultureInfo]::InvariantCulture)))
    if (-not $standup.tracker.ok) {
        $out.Add('  ' + ([string]$t.tracker).PadRight($width) + '  ' + [string]$standup.tracker.reason)
    }
    elseif ($walkOut.Count -eq 0) {
        $out.Add('  ' + [string]$t.queueEmpty)
    }
    else {
        foreach ($w in $walkOut) {
            $out.Add('  ' + ([string]$t.walk).PadRight($width) + '  ' + (Get-P20StandupItemRef ([pscustomobject]$w)) + ' ' + $w.title)
            if ($w.verifyRow) {
                foreach ($rl in ($w.verifyRow -split "`n")) { $out.Add('    ' + $rl) }
            }
            else { $out.Add("  no VERIFY row -- close on the issue's own words") }
        }
    }
    Write-Output ($out -join "`n")
    exit 0
}

if ($AsJson) {
    Write-Output ($standup | ConvertTo-Json -Depth 10)
}
elseif ($grainName -ceq $grains[2]) {
    # The chair's reading alone. Reading is not attending: no reminder is re-armed.
    Write-Output ($standup.brief.TrimEnd([char]10))
    exit 0
}
else {
    # detail, or the work grain: the ritual as it is spoken.
    Write-Output ((Get-P20StandupGrainText -Standup $standup -Grain $grainName).TrimEnd([char]10))
}

# -- Attending re-arms the reminder --------------------------------------
# Silent when it works or there is nothing to do; one line when it could not.
$attendWhy = Invoke-P20StandupAttend -PackageRoot $repoRoot
if ($attendWhy) { Write-Host "The standup reminder was not re-armed: $attendWhy" -ForegroundColor Yellow }
exit 0
