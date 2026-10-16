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
        gh issue list --repo <repo> --state all --limit 500 --json number,title,state,labels,closedAt,url,milestone,body

    milestone and body are the work grain's: an item groups by its
    milestone, else by the design card its body names.

    A Space with no tracker address, or a local or archive one, fills from its
    CARDS instead: the hub's current/ and archive/ for that Space, read by
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
    Write-Host "    ${p}Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail|work|brief>]"
    Write-Host "    ${p}Standup -Walk [-Space <slug>] [-AsJson]"
    Write-Host "    ${p}Standup -Remind <HH:mm> [-Days <Mon,Tue,...>]"
    Write-Host ""
    Write-Host "  The queue waiting on you, then one block per worker label. Writes nothing"
    Write-Host "  to the tracker. -Brief prints only the chair's reading, in a few lines. -Grain work speaks"
    Write-Host "  at the grain of the work: items grouped by milestone or feature, one sentence a group."
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

# -- Which Space ---------------------------------------------------------------
# No -Space: the one you are in. A slug: that Space's own entry, read without
# switching into it -- the same three things the agent's space_scope() takes.
$cfg = $global:P20Config
$slug = ''
$org = ''
$status = ''
$projects = @()
$spaceName = ''
$promptsFolder = ''
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
    $spaceName = [string]$entry.name
    $promptsFolder = [string]$entry.promptsFolder
}
elseif ($cfg) {
    $slug = [string]$cfg.ActiveSpace
    $org = [string]$cfg.Org
    $status = [string]$cfg.OrgStatus
    if ($cfg.Projects) { $projects = @($cfg.Projects) }
    $spaceName = [string]$cfg.ActiveOrgName
    $promptsFolder = [string]$cfg.PromptsFolder
}

# -- Which source ---------------------------------------------------------
# GitHub -> its issues; no tracker address, or a local/archive Space -> its cards;
# Azure DevOps -> the Tracker line (D-TA19). One pure rule, Get-P20StandupSource,
# held to the agent's by Tests/fixtures/rituals/standup-cards.json.
$choice = Get-P20StandupSource -Address $org -Status $status

# -- The thin layer: two gh reads ----------------------------------------------
function Invoke-P20StandupGh {
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
if ($choice.source -eq 'none') {
    # D-TA19: Azure DevOps is the human team's board; the sentence is consts.json's.
    $tracker.reason = $choice.reason
}
elseif ($choice.source -eq 'issues') {
    $target = Resolve-P20TrackerRepo -OrgUrl $org -Projects $projects -CliPrefix (Get-CliPrefix)
    if ($target.Reason) {
        $tracker.reason = $target.Reason
    }
    elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $tracker.reason = 'gh is not installed, so the tracker was not asked.'
    }
    else {
        $repo = $target.Repo
        $got = Invoke-P20StandupGh -Repo $repo -Arguments @('label', 'list', '--repo', $repo, '--limit', '500', '--json', 'name,description')
        if ($got.ok) {
            $labels = $got.value
            $got = Invoke-P20StandupGh -Repo $repo -Arguments @('issue', 'list', '--repo', $repo, '--state', 'all', '--limit', '500',
                '--json', 'number,title,state,labels,closedAt,url,milestone,body')
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
if ($choice.source -eq 'cards') {
    # The Space's own current/ and archive/, read by the rules every card verb uses.
    $hubRoot = ''
    if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
    $spaceDir = $hubRoot
    if ($hubRoot -and $promptsFolder) { $spaceDir = Join-Path $hubRoot $promptsFolder }
    $folderNames = (Get-P20Consts).folders
    $cards = @()
    if ($spaceDir) {
        $pattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
        $cards = @(Get-P20StandupCards -CurrentDir (Join-Path $spaceDir $folderNames.current) `
                -ArchiveDir (Join-Path $spaceDir $folderNames.archive) -Pattern $pattern)
    }
    $standup = Invoke-P20StandupCardsFill -AsOf ([DateTimeOffset]::Now) -Cards $cards -Space $slug -SpaceName $spaceName `
        -PackageRoot $repoRoot
}
else {
    $standup = Invoke-P20StandupFill -AsOf ([DateTimeOffset]::Now) -Labels $labels -Issues $issues -Tracker $tracker `
        -Space $slug -PackageRoot $repoRoot
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
