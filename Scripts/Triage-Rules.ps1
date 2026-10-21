<#
.SYNOPSIS
    Team Agile's triage rule, in one file. Dot-source it.

.DESCRIPTION
    Not a command. Everything the CLI works OUT about a triage lives here, so the
    verb (Triage) and the suite (Tests/Test-Triage.ps1) read one answer, and
    neither touches the tracker -- the gh calls are the verb's thin layer:

      Get-P20TriageRow       Config/ceremonies.json's triage row: the three
                             question slots, the severity labels, the deep-water
                             label and the words of the text.
      Invoke-P20TriageFill   (labels, open issues, tracker) -> the response
                             GET /api/ritual/triage serves, text left empty.
      Format-P20TriageText   the filled object -> the text, LF-joined.

    The rule: the open issues grouped by milestone; the group with NO milestone
    first, because nobody has placed them; then the milestones by open count,
    most first, a tie by title (ordinal). Inside a group, by number. An issue's
    worker is its first worker label (the standup's rule, Get-P20StandupWorkers:
    a label whose description starts "Routed to"), and that label IS its size
    (D-TA3). Its severity is the first of its labels that ceremonies.json names a
    severity; deep-water is the label ceremonies.json names. Who has it (D-AR10)
    is its GitHub assignee -- consts.json rituals.assignMe ("me") when that is the
    signed-in gh user (the viewer), else "@<login>" -- else its size (the worker
    label), else "" (nobody). Each group's context line is "N open, M routed,
    K unrouted", routed meaning it has a who: a worker label or an assignee.

    The agent's agent/solitaire/triage.py implements the same rule over the same
    file; Tests/fixtures/rituals/triage.json and the golden triage-<name>.txt
    beside it hold the two to one table, byte for byte.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20StandupWorkers -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Standup-Rules.ps1')
}

function Get-P20TriageRow {
    <# The rituals contract and ceremonies.json's triage row, read from the package. #>
    param([string]$PackageRoot)
    if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
    $rituals = (Get-P20Consts).rituals
    $ceremonies = Get-Content -LiteralPath (Join-Path $PackageRoot $rituals.ceremoniesFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
        Rituals = $rituals
        Row     = $ceremonies.triage
    }
}

function Get-P20TriageMilestone {
    <# An issue's milestone title: gh gives an object with .title or null. #>
    param($Issue)
    $m = $Issue.milestone
    if ($null -eq $m) { return '' }
    if ($m -is [string]) { return $m }
    if ($m.PSObject.Properties['title']) { return [string]$m.title }
    if ($m -is [System.Collections.IDictionary] -and $m.Contains('title')) { return [string]$m['title'] }
    return ''
}

function Get-P20IssueAssignees {
    <# An issue's assignee logins: gh gives objects with .login, the fixture gives strings. #>
    param($Issue)
    $logins = New-Object System.Collections.ArrayList
    if ($null -eq $Issue) { return $logins.ToArray() }
    $raw = $null
    if ($Issue -is [System.Collections.IDictionary]) { if ($Issue.Contains('assignees')) { $raw = $Issue['assignees'] } }
    elseif ($Issue.PSObject.Properties['assignees']) { $raw = $Issue.assignees }
    foreach ($a in @($raw)) {
        if ($null -eq $a) { continue }
        if ($a -is [string]) { if ($a) { [void]$logins.Add($a) }; continue }
        if ($a -is [System.Collections.IDictionary]) { if ($a.Contains('login') -and $a['login']) { [void]$logins.Add([string]$a['login']) }; continue }
        if ($a.PSObject.Properties['login'] -and $a.login) { [void]$logins.Add([string]$a.login) }
    }
    return $logins.ToArray()
}

function Get-P20TriageWho {
    <#
      Who has an item (D-AR10), one rule: the first assignee -- "me" when it is
      the viewer (compared ignoring case, as GitHub's logins are), "@<login>"
      otherwise -- else the size, else "" (nobody). agent/solitaire/triage.py's
      who() is the same rule over the same table.
    #>
    param([string]$Assignee, [string]$Size, [string]$Viewer)
    if ($Assignee) {
        if ($Viewer -and $Assignee -ieq $Viewer) { return [string](Get-P20Consts).rituals.assignMe }
        return '@' + $Assignee
    }
    return [string]$Size
}

function Invoke-P20TriageFill {
    <#
      The fill. Pure over its inputs: no gh, no clock, no file but ceremonies.json.
      Returns the response of GET /api/ritual/triage as an ordered dictionary,
      with text '' -- Format-P20TriageText renders it. With tracker.ok false the
      labels and issues are not read: the ceremony is its title and the reason.
    #>
    param(
        $Labels,
        $Issues,
        $Tracker,
        [string]$Space = '',
        # The signed-in gh user's login, '' when unknown: an assignee who is the
        # viewer reads as "me".
        [string]$Viewer = '',
        [string]$PackageRoot
    )
    $data = Get-P20TriageRow -PackageRoot $PackageRoot
    $row = $data.Row
    $severities = @($row.severities | ForEach-Object { [string]$_ })
    $deep = [string]$row.deepWaterLabel

    $ok = $true
    $reason = ''
    if ($null -ne $Tracker) {
        $ok = [bool]$Tracker.ok
        $reason = [string]$Tracker.reason
    }

    $sizes = New-Object System.Collections.ArrayList
    $groupsOut = New-Object System.Collections.ArrayList

    if ($ok) {
        $defs = @(Get-P20StandupWorkers -Labels $Labels -Prefix ([string]$data.Rituals.workerLabelPrefix))
        $byLabel = @{}
        foreach ($def in $defs) {
            $byLabel[[string]$def.label] = $def
            [void]$sizes.Add([ordered]@{ label = [string]$def.label; name = [string]$def.name })
        }

        $groups = @{}
        $sorted = @(@($Issues) | Where-Object { $null -ne $_ } | Sort-Object { [int]$_.number })
        foreach ($issue in $sorted) {
            $state = 'OPEN'
            if ($issue.PSObject.Properties['state'] -and $issue.state) { $state = ([string]$issue.state).ToUpperInvariant() }
            if ($state -ne 'OPEN') { continue }
            $names = @(Get-P20IssueLabelNames $issue)
            $size = ''
            foreach ($n in $names) { if ($byLabel.ContainsKey($n)) { $size = $n; break } }
            $severity = ''
            foreach ($n in $names) { if ($severities -contains $n) { $severity = $n; break } }
            $worker = ''
            if ($size) { $worker = [string]$byLabel[$size].name }
            $assignee = [string](@(Get-P20IssueAssignees $issue) | Select-Object -First 1)
            $item = [ordered]@{
                number    = [int]$issue.number
                title     = [string]$issue.title
                url       = [string]$issue.url
                worker    = $worker
                size      = $size
                assignee  = $assignee
                who       = (Get-P20TriageWho -Assignee $assignee -Size $size -Viewer $Viewer)
                severity  = $severity
                deepWater = [bool]($names -contains $deep)
            }
            $title = Get-P20TriageMilestone $issue
            if (-not $groups.ContainsKey($title)) { $groups[$title] = New-Object System.Collections.ArrayList }
            [void]$groups[$title].Add($item)
        }

        # No milestone first; then most open first; a tie by title, ordinal --
        # Sort-Object compares strings by culture, which is not what the agent does.
        $titles = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in $groups.Keys) { if ($k -ne '') { $titles.Add([string]$k) } }
        $counts = @{}
        foreach ($k in $groups.Keys) { $counts[[string]$k] = $groups[$k].Count }
        $titles.Sort([System.Comparison[string]] {
                param($a, $b)
                $c = $counts[$b].CompareTo($counts[$a])
                if ($c -ne 0) { return $c }
                return [string]::CompareOrdinal($a, $b)
            })
        $order = New-Object System.Collections.ArrayList
        if ($groups.ContainsKey('')) { [void]$order.Add('') }
        foreach ($t in $titles) { [void]$order.Add($t) }

        foreach ($t in $order) {
            $members = [object[]]$groups[$t].ToArray()
            # Routed: someone has it -- a worker label or an assignee (D-AR10).
            $routed = @($members | Where-Object { $_.who }).Count
            $open = $members.Count
            $context = ([string]$row.text.context).Replace('{open}', [string]$open).Replace('{routed}', [string]$routed).Replace('{unrouted}', [string]($open - $routed))
            [void]$groupsOut.Add([ordered]@{
                    milestone = [string]$t
                    open      = $open
                    routed    = $routed
                    unrouted  = $open - $routed
                    context   = $context
                    issues    = $members
                })
        }
    }

    return [ordered]@{
        ceremony       = 'triage'
        space          = $Space
        tracker        = [ordered]@{ ok = $ok; reason = $reason }
        slots          = [object[]]@($row.slots | ForEach-Object { [string]$_ })
        severities     = [object[]]$severities
        deepWaterLabel = $deep
        sizes          = [object[]]$sizes.ToArray()
        groups         = [object[]]$groupsOut.ToArray()
        text           = ''
    }
}

function Format-P20TriageText {
    <#
      The filled object -> the triage's text: LF-joined, ending in one LF, every
      fixed word from ceremonies.json's triage.text (the Tracker label and its
      width are the standup's, consts.json rituals). Takes the fill's dictionary
      or the same shape read back from JSON.
    #>
    param([Parameter(Mandatory)]$Triage, [string]$PackageRoot)
    $data = Get-P20TriageRow -PackageRoot $PackageRoot
    $t = $data.Row.text
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(([string]$t.title).Replace('{space}', [string]$Triage.space))
    [void]$lines.Add('')
    $groups = @($Triage.groups | Where-Object { $null -ne $_ })
    if (-not [bool]$Triage.tracker.ok) {
        $label = ([string]$data.Rituals.text.tracker).PadRight([int]$data.Rituals.labelWidth)
        [void]$lines.Add("  $label  $([string]$Triage.tracker.reason)")
    }
    elseif ($groups.Count -eq 0) {
        [void]$lines.Add([string]$t.nothingOpen)
    }
    else {
        $first = $true
        foreach ($g in $groups) {
            if (-not $first) { [void]$lines.Add('') }
            $first = $false
            $heading = [string]$g.milestone
            if (-not $heading) { $heading = [string]$t.noMilestone }
            [void]$lines.Add(([string]$t.group).Replace('{milestone}', $heading).Replace('{context}', [string]$g.context))
            foreach ($i in @($g.issues | Where-Object { $null -ne $_ })) {
                # Who: "me", "@<login>", the size's worker name, or nobody.
                $who = [string]$i.who
                if ($i.size -and $who -ceq [string]$i.size) { $who = [string]$i.worker }
                if (-not $who) { $who = [string]$t.nobody }
                $sev = [string]$i.severity
                if (-not $sev) { $sev = [string]$t.none }
                $tags = @($who, $sev)
                if ([bool]$i.deepWater) { $tags += [string]$Triage.deepWaterLabel }
                [void]$lines.Add(([string]$t.issue).Replace('{number}', [string]$i.number).Replace('{title}', [string]$i.title).Replace('{tags}', ($tags -join ', ')))
            }
        }
    }
    return (($lines.ToArray()) -join "`n") + "`n"
}
