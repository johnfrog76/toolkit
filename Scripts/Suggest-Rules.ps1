<#
.SYNOPSIS
    The suggestion: one next move, derived from the joined list (Team Agile, AR-3). Dot-source it.

.DESCRIPTION
    Not a command. The rule the chair's Next line reads (docs/modules/solitaire-agile.md,
    "The suggestion: one next move, derived"; spec prompt20-agent-in-the-room,
    section 6). agent/solitaire/suggest.py implements the same rule, and ONE table,
    Tests/fixtures/suggestion/table.json, holds the two together -- tkTestToolkit
    -Rituals here, Tests/test_rituals.py there.

      Get-P20NearestMilestones  milestones -> titles, the nearest first: the fewest
                                open items, a tie by the earlier due date (none
                                after every one with one), then the title, ordinal.
      Select-P20Suggestion      items already joined, howIWork, the refs dismissed
                                -> every candidate in order with its shape, sentence
                                and command, and each excluded ref with the FIRST
                                exclusion it met (rituals.suggestExclusions).
      Get-P20SuggestionItems    the joined list (labels, issues, card rows, the
                                refs on the queue) -> the rule's items.
      Test-P20SuggestionsOn     Team Agile's resolved switch and the Space's
                                features.suggestions: unset is on.
      Add-P20StandupSuggestion  the step Standup runs after the fill: the
                                candidates and the first, on the standup object.

    Every word is consts.json's rituals.text.suggest*; Format-P20StandupBrief
    prints the suggestion's line in place of briefNextNone only, and only when
    nothing waits (D-AR7).

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
# The standup's own readers: an issue's label names, and how an item is named (#<n> or its id).
if (-not (Get-Command Get-P20IssueLabelNames -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Standup-Rules.ps1')
}
# Who has an issue: triage's one rule (me, @<login>, the size, or nobody).
if (-not (Get-Command Get-P20TriageWho -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Triage-Rules.ps1')
}

function Get-P20SuggestField {
    <# One field of an item, a card row or an issue: a hashtable's key or an object's property; $null when absent. #>
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function ConvertTo-P20SuggestDay {
    <#
      A date-ish value -> 'yyyy-MM-dd', or ''. A string gives its first ten
      characters when they are a day; 7's ConvertFrom-Json may hand back a
      [datetime] for gh's createdAt (a UTC instant), which is read in UTC so the
      day agrees with the agent's first ten characters of the same string.
    #>
    param($Value)
    if ($null -eq $Value) { return '' }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime.ToString('yyyy-MM-dd', $inv) }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return $Value.ToString('yyyy-MM-dd', $inv) }
        return $Value.ToUniversalTime().ToString('yyyy-MM-dd', $inv)
    }
    $text = ([string]$Value).Trim()
    if ($text -match '^\d{4}-\d{2}-\d{2}') { return $text.Substring(0, 10) }
    return ''
}

function Format-P20SuggestTemplate {
    <# One pass over a suggestion template's placeholders: a value is never read as a placeholder. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Values', Justification = 'Read inside the MatchEvaluator scriptblock, which the rule does not follow.')]
    param([string]$Template, [hashtable]$Values)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $k = $m.Groups[1].Value
        if ($Values.ContainsKey($k)) { return [string]$Values[$k] }
        return $m.Value
    }
    return [regex]::Replace([string]$Template, '\{(ref|why|size|nobody|noun|milestone|kind|sentence|command|arg)\}', $evaluator)
}

function Get-P20SuggestSeverities {
    <# The triage ceremony's severities, most severe first (Config/ceremonies.json). #>
    param([string]$PackageRoot)
    if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
    $file = Join-Path $PackageRoot ([string](Get-P20Consts).rituals.ceremoniesFile)
    $ceremonies = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($ceremonies.triage.severities | ForEach-Object { [string]$_ })
}

# -- The nearest milestone -----------------------------------------------------

function Get-P20NearestMilestones {
    <#
      Milestone titles, the nearest first: fewest open items, then the earlier
      due date (a milestone with none after every one with one), then the title,
      ordinal. One entry per title, the first seen. nearest_milestones in the agent.
    #>
    param($Milestones)
    $seen = [ordered]@{}
    foreach ($m in @($Milestones)) {
        if ($null -eq $m) { continue }
        $title = [string](Get-P20SuggestField $m 'title')
        if (-not $title -or $seen.Contains($title)) { continue }
        $due = ConvertTo-P20SuggestDay (Get-P20SuggestField $m 'due')
        if (-not $due) { $due = '9999-99-99' }
        $seen[$title] = @{ open = [int](Get-P20SuggestField $m 'open'); due = $due; title = $title }
    }
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($k in $seen.Keys) { $list.Add($seen[$k]) }
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            if ($a.open -ne $b.open) { return $a.open.CompareTo($b.open) }
            $byDue = [string]::CompareOrdinal($a.due, $b.due)
            if ($byDue -ne 0) { return $byDue }
            return [string]::CompareOrdinal($a.title, $b.title)
        })
    return @($list | ForEach-Object { [string]$_.title })
}

# -- The rule ------------------------------------------------------------------

function Get-P20SuggestionExcludedBy {
    <# The first exclusion an item meets, in rituals.suggestExclusions' order; '' for none. #>
    param($Item, [string[]]$Dismissed)
    $c = Get-P20Consts
    $why = @($c.rituals.suggestExclusions | ForEach-Object { [string]$_ })
    $billable = Get-P20SuggestField $Item 'billable'
    if ($billable -is [bool] -and -not $billable) { return $why[0] }
    if ([bool](Get-P20SuggestField $Item 'waiting')) { return $why[1] }
    $lane = [string](Get-P20SuggestField $Item 'lane')
    if ($lane -ceq [string]$c.status.inProgress -or $lane -ceq [string]$c.status.codeReview) { return $why[2] }
    # Someone else's: an assignee who is not you (@<login>).
    if (([string](Get-P20SuggestField $Item 'who')).StartsWith('@')) { return $why[3] }
    if (@($Dismissed) -ccontains [string](Get-P20SuggestField $Item 'ref')) { return $why[4] }
    return ''
}

function Get-P20SuggestionSentence {
    <# (shape, sentence, command) for one candidate, as @{ shape; sentence; command }. _sentence in the agent. #>
    param($Item, [string]$HowIWork)
    $c = Get-P20Consts
    $t = $c.rituals.text
    $shapes = @($c.rituals.suggestShapes | ForEach-Object { [string]$_ })
    $ref = [string](Get-P20SuggestField $Item 'ref')
    $arg = $ref.TrimStart('#')
    $noun = [string]$t.suggestNounIssue
    if ([string](Get-P20SuggestField $Item 'kind') -ceq 'card') { $noun = [string]$t.suggestNounCard }
    $kind = [string](Get-P20SuggestField $Item 'severity')
    if (-not $kind) { $kind = $noun }
    $milestone = Get-P20SuggestField $Item 'milestone'
    $title = ''
    $open = 0
    if ($null -ne $milestone) {
        $title = [string](Get-P20SuggestField $milestone 'title')
        $open = [int](Get-P20SuggestField $milestone 'open')
    }
    if ($title -and $open -eq 1) { $why = Format-P20SuggestTemplate ([string]$t.suggestWhyLast) @{ noun = $noun; milestone = $title } }
    elseif ($title) { $why = Format-P20SuggestTemplate ([string]$t.suggestWhyMilestone) @{ kind = $kind; milestone = $title } }
    else { $why = Format-P20SuggestTemplate ([string]$t.suggestWhyOldest) @{ kind = $kind } }
    $who = [string](Get-P20SuggestField $Item 'who')
    # Yours to start: you, or the owner's own seat (D-AR10) -- never the crew.
    $isYours = ($who -ceq [string]$c.rituals.assignMe -or $who -ceq [string]$c.rituals.suggestOwnerSeat)
    $startCommand = Format-P20SuggestTemplate ([string]$t.suggestCommandStart) @{ arg = $arg }
    if ($HowIWork -cne 'agents' -or $isYours) {
        return @{ shape = $shapes[0]; sentence = (Format-P20SuggestTemplate ([string]$t.suggestStart) @{ ref = $ref; why = $why }); command = $startCommand }
    }
    if ($who) {
        $size = [string](Get-P20SuggestField $Item 'size')
        if (-not $size) { $size = $who }
        if ($title) {
            # Well defined is not a judgement: a size label and a milestone.
            return @{ shape = $shapes[1]; sentence = (Format-P20SuggestTemplate ([string]$t.suggestDelegate) @{ ref = $ref; size = $size }); command = $startCommand }
        }
        # Sized, but no destination: route it to a milestone -- Route's write on an
        # issue, Plan's **Sprint:** line on a card (Route takes only -Assign there).
        $placeTemplate = [string]$t.suggestCommandPlace
        if ([string](Get-P20SuggestField $Item 'kind') -ceq 'card') { $placeTemplate = [string]$t.suggestCommandPlaceCard }
        return @{
            shape    = $shapes[3]
            sentence = (Format-P20SuggestTemplate ([string]$t.suggestPlace) @{ ref = $ref; size = $size })
            command  = (Format-P20SuggestTemplate $placeTemplate @{ arg = $arg })
        }
    }
    return @{
        shape    = $shapes[2]
        sentence = (Format-P20SuggestTemplate ([string]$t.suggestRoute) @{ ref = $ref; why = $why; nobody = [string]$t.suggestNobody })
        command  = (Format-P20SuggestTemplate ([string]$t.suggestCommandRoute) @{ arg = $arg })
    }
}

function Select-P20Suggestion {
    <#
      The candidates in order and the excluded refs, as
      @{ picked = <array of @{ item; ref; shape; sentence; command }>; excluded = <ordered ref -> exclusion> }.
      Order: severity (the triage ceremony's, in order, then none), the nearest
      milestone (Get-P20NearestMilestones; none after every milestone), age (the
      oldest created day first; none last), then the ref without its '#', ordinal.
      suggest() in the agent.
    #>
    param($Items, [string]$HowIWork, [string[]]$Dismissed = @(), [string]$PackageRoot)
    $excluded = [ordered]@{}
    $kept = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $why = Get-P20SuggestionExcludedBy -Item $item -Dismissed $Dismissed
        if ($why) { $excluded[[string](Get-P20SuggestField $item 'ref')] = $why }
        else { $kept.Add($item) }
    }
    $sev = @(Get-P20SuggestSeverities -PackageRoot $PackageRoot)
    $milestones = @($kept | ForEach-Object { Get-P20SuggestField $_ 'milestone' } | Where-Object { $null -ne $_ })
    $nearest = @(Get-P20NearestMilestones -Milestones $milestones)
    $keyed = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $kept) {
        $s = [string](Get-P20SuggestField $item 'severity')
        $sevRank = [array]::IndexOf($sev, $s)
        if (-not $s -or $sevRank -lt 0) { $sevRank = $sev.Count }
        $m = Get-P20SuggestField $item 'milestone'
        $mRank = $nearest.Count
        if ($null -ne $m) {
            $at = [array]::IndexOf($nearest, [string](Get-P20SuggestField $m 'title'))
            if ($at -ge 0) { $mRank = $at }
        }
        $day = ConvertTo-P20SuggestDay (Get-P20SuggestField $item 'created')
        if (-not $day) { $day = '9999-99-99' }
        $keyed.Add(@{ item = $item; sev = [int]$sevRank; mile = [int]$mRank; day = $day; id = ([string](Get-P20SuggestField $item 'ref')).TrimStart('#') })
    }
    $keyed.Sort([System.Comparison[object]] {
            param($a, $b)
            if ($a.sev -ne $b.sev) { return $a.sev.CompareTo($b.sev) }
            if ($a.mile -ne $b.mile) { return $a.mile.CompareTo($b.mile) }
            $byDay = [string]::CompareOrdinal($a.day, $b.day)
            if ($byDay -ne 0) { return $byDay }
            return [string]::CompareOrdinal($a.id, $b.id)
        })
    $picked = New-Object System.Collections.ArrayList
    foreach ($k in $keyed) {
        $said = Get-P20SuggestionSentence -Item $k.item -HowIWork $HowIWork
        [void]$picked.Add(@{ item = $k.item; ref = [string](Get-P20SuggestField $k.item 'ref'); shape = $said.shape; sentence = $said.sentence; command = $said.command })
    }
    return @{ picked = [object[]]$picked.ToArray(); excluded = $excluded }
}

# -- The switch ----------------------------------------------------------------

function Test-P20SuggestionsOn {
    <#
      Whether the suggestion shows: Team Agile on (its resolved switch) AND the
      Space's features.suggestions not false -- unset is on. suggestions_on in the agent.
    #>
    param($TeamAgile, $Stored)
    if (-not ($TeamAgile -is [bool] -and $TeamAgile)) { return $false }
    if ($Stored -is [bool] -and -not $Stored) { return $false }
    return $true
}

# -- The joined list, as items ---------------------------------------------------

function Get-P20SuggestionItems {
    <#
      The joined list as the rule's items. suggest_items in the agent, the same
      rule: an OPEN issue is one item -- severity and size from its labels, who
      by the triage rule (Get-P20TriageWho: its first assignee -- me when it is
      -Viewer, the signed-in gh user, else @<login> -- else its size), its
      milestone and due date, its createdAt, its lane from the card in current/
      whose id is its number (Active without one). A card in current/ whose id is
      no issue in the read is its own item -- severity and size from its Tags,
      who from its **Assigned:** line (else its size), its milestone from its
      **Sprint:** line, its **Created:** day, its lane. A not-billable card is an
      item with billable false and adds nothing to an issue. -Waiting is every ref
      on the queue. A milestone's open counts its billable items, once per id.
    #>
    param($Labels, $Issues, $Cards, [string[]]$Waiting = @(), [string]$Viewer = '', [string]$PackageRoot)
    $c = Get-P20Consts
    $prefix = [string]$c.rituals.workerLabelPrefix
    $sizes = @{}
    foreach ($lab in @($Labels)) {
        if ($null -eq $lab) { continue }
        $desc = [string](Get-P20SuggestField $lab 'description')
        if ($desc.StartsWith($prefix) -and $desc.Substring($prefix.Length).Trim()) { $sizes[[string](Get-P20SuggestField $lab 'name')] = $true }
    }
    $sev = @(Get-P20SuggestSeverities -PackageRoot $PackageRoot)
    $numbers = @{}
    foreach ($i in @($Issues)) { if ($null -ne $i) { $numbers[[string][int](Get-P20SuggestField $i 'number')] = $true } }
    $currentName = [string]$c.folders.current
    $current = @($Cards | Where-Object { $null -ne $_ -and [string](Get-P20SuggestField $_ 'folder') -eq $currentName })
    $laneOf = @{}
    foreach ($card in $current) {
        $cid = [string](Get-P20SuggestField $card 'id')
        $billable = Get-P20SuggestField $card 'billable'
        if ($numbers.ContainsKey($cid) -and -not ($billable -is [bool] -and -not $billable)) { $laneOf[$cid] = [string](Get-P20SuggestField $card 'status') }
    }
    $items = New-Object System.Collections.ArrayList
    $sortedIssues = @($Issues | Where-Object { $null -ne $_ } | Sort-Object { [int](Get-P20SuggestField $_ 'number') })
    foreach ($issue in $sortedIssues) {
        if (([string](Get-P20SuggestField $issue 'state')).ToUpperInvariant() -ne 'OPEN') { continue }
        $n = [string][int](Get-P20SuggestField $issue 'number')
        $tags = @(Get-P20IssueLabelNames $issue)
        $size = ''
        foreach ($tg in $tags) { if ($sizes.ContainsKey([string]$tg)) { $size = [string]$tg; break } }
        $severity = ''
        foreach ($tg in $tags) { if ($sev -ccontains [string]$tg) { $severity = [string]$tg; break } }
        $assignee = ''
        foreach ($a in @(Get-P20SuggestField $issue 'assignees')) {
            if ($null -eq $a) { continue }
            $login = $a
            if (-not ($a -is [string])) { $login = Get-P20SuggestField $a 'login' }
            if ($login) { $assignee = [string]$login; break }
        }
        $who = Get-P20TriageWho -Assignee $assignee -Size $size -Viewer $Viewer
        $m = Get-P20SuggestField $issue 'milestone'
        $milestone = $null
        if ($null -ne $m) {
            $mTitle = ''
            $mDue = ''
            if ($m -is [string]) { $mTitle = $m }
            else { $mTitle = [string](Get-P20SuggestField $m 'title'); $mDue = ConvertTo-P20SuggestDay (Get-P20SuggestField $m 'dueOn') }
            if ($mTitle) {
                $dueValue = $null
                if ($mDue) { $dueValue = $mDue }
                $milestone = [ordered]@{ title = $mTitle; open = 0; due = $dueValue }
            }
        }
        $created = ConvertTo-P20SuggestDay (Get-P20SuggestField $issue 'createdAt')
        if (-not $created) { $created = $null }
        $lane = [string]$c.status.active
        if ($laneOf.ContainsKey($n)) { $lane = $laneOf[$n] }
        [void]$items.Add([ordered]@{
                ref = '#' + $n; number = [int]$n; id = $null; kind = 'issue'; title = [string](Get-P20SuggestField $issue 'title')
                severity = $severity; milestone = $milestone; created = $created; size = $size; who = $who
                lane = $lane; billable = $true; waiting = (@($Waiting) -ccontains ('#' + $n))
            })
    }
    $sortedCards = New-Object 'System.Collections.Generic.List[object]'
    foreach ($card in $current) { $sortedCards.Add($card) }
    $sortedCards.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string](Get-P20SuggestField $a 'file'), [string](Get-P20SuggestField $b 'file')) })
    foreach ($card in $sortedCards) {
        $cid = [string](Get-P20SuggestField $card 'id')
        if (-not $cid -or $numbers.ContainsKey($cid)) { continue }
        $tags = @(Get-P20SuggestField $card 'tags' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        $size = ''
        foreach ($tg in $tags) { if ($sizes.ContainsKey($tg)) { $size = $tg; break } }
        $severity = ''
        foreach ($tg in $tags) { if ($sev -ccontains $tg) { $severity = $tg; break } }
        $mTitle = [string](Get-P20SuggestField $card 'sprint')
        $milestone = $null
        if ($mTitle) { $milestone = [ordered]@{ title = $mTitle; open = 0; due = $null } }
        $created = ConvertTo-P20SuggestDay (Get-P20SuggestField $card 'created')
        if (-not $created) { $created = $null }
        $who = [string](Get-P20SuggestField $card 'assigned')
        if (-not $who) { $who = $size }
        $billable = Get-P20SuggestField $card 'billable'
        [void]$items.Add([ordered]@{
                ref = $cid; number = $null; id = $cid; kind = 'card'; title = [string](Get-P20SuggestField $card 'title')
                severity = $severity; milestone = $milestone; created = $created; size = $size; who = $who
                lane = [string](Get-P20SuggestField $card 'status'); billable = (-not ($billable -is [bool] -and -not $billable))
                waiting = (@($Waiting) -ccontains $cid)
            })
    }
    $opens = @{}
    foreach ($item in $items) {
        if ($item.billable -and $null -ne $item.milestone) {
            $k = [string]$item.milestone.title
            if ($opens.ContainsKey($k)) { $opens[$k] = $opens[$k] + 1 } else { $opens[$k] = 1 }
        }
    }
    foreach ($item in $items) {
        if ($null -ne $item.milestone) { $item.milestone['open'] = [int]$opens[[string]$item.milestone.title] }
    }
    return $items.ToArray()
}

function Add-P20StandupSuggestion {
    <#
      The suggestion attached to a filled standup, in place: suggestions (every
      candidate in order) and suggestion (the first, or $null). Nothing with the
      switch off, or with the tracker not answering. -Prefix is the CLI's, for
      the command the chair's line names; -Viewer the signed-in gh user's login
      (Get-P20RitualViewer, triage's one read), '' when gh cannot say -- then every
      assignee is someone else's. attach_suggestions in the agent.
    #>
    param([Parameter(Mandatory)]$Standup, $Labels, $Issues, $Cards, [string]$HowIWork, [bool]$On, [string]$Prefix, [string]$Viewer = '', [string]$PackageRoot)
    $Standup['suggestions'] = [object[]]@()
    $Standup['suggestion'] = $null
    if (-not $On -or -not $Standup.tracker.ok) { return $Standup }
    $waiting = New-Object System.Collections.ArrayList
    foreach ($kind in @('walk', 'decide', 'look')) {
        if (-not $Standup.queue.Contains($kind)) { continue }
        foreach ($it in @($Standup.queue[$kind] | Where-Object { $null -ne $_ })) { [void]$waiting.Add((Get-P20StandupItemRef $it)) }
    }
    $useIssues = @()
    if ([string]$Standup.source -ceq 'issues' -or [string]$Standup.source -ceq 'both') { $useIssues = @($Issues) }
    $items = @(Get-P20SuggestionItems -Labels $Labels -Issues $useIssues -Cards $Cards -Waiting ([string[]]$waiting.ToArray()) -Viewer $Viewer -PackageRoot $PackageRoot)
    $chosen = Select-P20Suggestion -Items $items -HowIWork $HowIWork -PackageRoot $PackageRoot
    $t = (Get-P20Consts).rituals.text
    $out = New-Object System.Collections.ArrayList
    foreach ($p in @($chosen.picked)) {
        [void]$out.Add([ordered]@{
                ref      = $p.ref
                number   = $p.item.number
                id       = $p.item.id
                kind     = [string]$p.item.kind
                shape    = $p.shape
                sentence = $p.sentence
                command  = $p.command
                line     = (Format-P20SuggestTemplate ([string]$t.suggestNext) @{ sentence = $p.sentence; command = ($Prefix + $p.command) })
            })
    }
    $Standup['suggestions'] = [object[]]$out.ToArray()
    if ($out.Count -gt 0) { $Standup['suggestion'] = $out[0] }
    return $Standup
}
