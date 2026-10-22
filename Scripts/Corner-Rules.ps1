<#
.SYNOPSIS
    The PM Corner: one derived line at the head of the Team Agile page (AR-4). Dot-source it.

.DESCRIPTION
    Not a command. The line the Team Agile page draws at its head and Standup
    -Brief prints last (docs/modules/solitaire-agile.md, "The PM Corner: the
    line, the chevron, the confetti"; spec prompt20-agent-in-the-room, section 7;
    D-AR11, D-AR14). agent/solitaire/corner.py implements the same rule, and ONE
    table, Tests/fixtures/rituals/corner.json, holds the two together --
    tkTestToolkit -Rituals here, Tests/test_rituals.py there.

    Nothing here is a second rule. The milestone is the suggestion's nearest
    (Get-P20NearestMilestones) over the suggestion's own candidates in the
    suggestion's own order (Select-P20Suggestion), the id is the suggestion's
    pick inside it, and the remaining count is the joined list's own open count
    (Get-P20SuggestionItems): open issues that name the milestone plus open
    cards whose **Sprint:** line names it, WHOLE, once per id.

      Get-P20CornerLine    the joined list's items and what closed in the
                           window -> the line: shape (rituals.cornerShapes),
                           milestone, remaining, the pick, noun, line, command.
      Get-P20CornerClosed  the read's issues and card rows and the standup's
                           window -> what named a milestone and closed in it,
                           once per id.
      Add-P20StandupCorner the step Standup runs after the suggestion: the line
                           on the standup object, and the brief's last line.

    Every word is consts.json's rituals.text.corner*.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Select-P20Suggestion -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Suggest-Rules.ps1')
}

function Get-P20CornerLine {
    <#
      The Corner's line, as an ordered hashtable. corner() in the agent.

      1. REACHED: a milestone some billable closed item names and no open
         billable item names. The latest close first, then the title, ordinal.
      2. The nearest milestone among the suggestion's candidates; the pick is the
         first candidate in it and the remaining count its open. One left names
         the pick's noun (card, issue); more names the remaining rows' -- cards,
         issues, or items for a mix.
      3. Else nothing in reach.
    #>
    param($Items, $Closed, [string]$PackageRoot)
    $c = Get-P20Consts
    $t = $c.rituals.text
    $shapes = @($c.rituals.cornerShapes | ForEach-Object { [string]$_ })
    # Open milestones: title -> the kinds of the open billable items that name it.
    $openTitles = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $billable = Get-P20SuggestField $item 'billable'
        if ($billable -is [bool] -and -not $billable) { continue }
        $m = Get-P20SuggestField $item 'milestone'
        if ($null -eq $m) { continue }
        $title = [string](Get-P20SuggestField $m 'title')
        if (-not $title) { continue }
        if (-not $openTitles.ContainsKey($title)) { $openTitles[$title] = @{} }
        $openTitles[$title][[string](Get-P20SuggestField $item 'kind')] = $true
    }
    $done = @{}
    foreach ($cl in @($Closed)) {
        if ($null -eq $cl) { continue }
        $title = [string](Get-P20SuggestField $cl 'milestone')
        $billable = Get-P20SuggestField $cl 'billable'
        if (-not $title -or ($billable -is [bool] -and -not $billable) -or $openTitles.ContainsKey($title)) { continue }
        $day = ConvertTo-P20SuggestDay (Get-P20SuggestField $cl 'day')
        if (-not $done.ContainsKey($title) -or [string]::CompareOrdinal($day, $done[$title]) -gt 0) { $done[$title] = $day }
    }
    $out = [ordered]@{
        shape = $shapes[3]; milestone = ''; remaining = 0; ref = ''; number = $null; id = $null
        kind = ''; noun = ''; line = [string]$t.cornerNothingInReach; command = ''
    }
    if ($done.Count -gt 0) {
        $titles = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in $done.Keys) { $titles.Add([string]$k) }
        # The latest close first; a tie by title, ordinal.
        $titles.Sort([System.Comparison[string]] {
                param($a, $b)
                $byDay = [string]::CompareOrdinal($done[$b], $done[$a])
                if ($byDay -ne 0) { return $byDay }
                return [string]::CompareOrdinal($a, $b)
            })
        $title = $titles[0]
        $out.shape = $shapes[2]
        $out.milestone = $title
        $out.line = Format-P20SuggestTemplate ([string]$t.cornerReached) @{ milestone = $title }
        return $out
    }
    $chosen = Select-P20Suggestion -Items @($Items) -HowIWork 'alone' -PackageRoot $PackageRoot
    $inReach = @($chosen.picked | Where-Object {
            $m = Get-P20SuggestField $_.item 'milestone'
            $null -ne $m -and [string](Get-P20SuggestField $m 'title')
        })
    if ($inReach.Count -eq 0) { return $out }
    $title = @(Get-P20NearestMilestones -Milestones @($inReach | ForEach-Object { Get-P20SuggestField $_.item 'milestone' }))[0]
    $pick = @($inReach | Where-Object { [string](Get-P20SuggestField (Get-P20SuggestField $_.item 'milestone') 'title') -ceq $title })[0]
    $remaining = [int](Get-P20SuggestField (Get-P20SuggestField $pick.item 'milestone') 'open')
    $ref = [string]$pick.ref
    $kind = [string](Get-P20SuggestField $pick.item 'kind')
    if ($remaining -le 1) {
        $noun = [string]$t.suggestNounIssue
        if ($kind -ceq 'card') { $noun = [string]$t.suggestNounCard }
        $line = Format-P20SuggestTemplate ([string]$t.cornerOneLeft) @{ noun = $noun; ref = $ref; milestone = $title }
        $shape = $shapes[0]
    }
    else {
        $kinds = @{ $kind = $true }
        if ($openTitles.ContainsKey($title)) { $kinds = $openTitles[$title] }
        $noun = [string]$t.cornerNounItems
        if ($kinds.Count -eq 1 -and $kinds.ContainsKey('card')) { $noun = [string]$t.cornerNounCards }
        elseif ($kinds.Count -eq 1 -and $kinds.ContainsKey('issue')) { $noun = [string]$t.cornerNounIssues }
        $line = Format-P20SuggestTemplate ([string]$t.cornerManyLeft) @{ n = [string]$remaining; noun = $noun; ref = $ref; milestone = $title }
        $shape = $shapes[1]
    }
    $out.shape = $shape
    $out.milestone = $title
    $out.remaining = $remaining
    $out.ref = $ref
    $out.number = Get-P20SuggestField $pick.item 'number'
    $out.id = Get-P20SuggestField $pick.item 'id'
    $out.kind = $kind
    $out.noun = $noun
    $out.line = $line
    $out.command = Format-P20SuggestTemplate ([string]$t.suggestCommandStart) @{ arg = $ref.TrimStart('#') }
    return $out
}

function Get-P20CornerClosed {
    <#
      What named a milestone and closed in the window, once per id, each as
      @{ ref; kind; milestone; day; billable }. corner_closed() in the agent.
      An issue: CLOSED, a milestone, its closedAt in [-Since, -AsOf] -- the
      standup's own test for yesterday's closes. A card: in archive/, its Closed
      day in [-Since's day, -AsOf's day] (the cards fill's test), its **Sprint:**
      line naming the milestone, and its id no issue in the read -- a card that
      tracks an issue is that issue's row, as on the joined list.
    #>
    param($Issues, $Cards, $Since, $AsOf)
    $c = Get-P20Consts
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $from = ConvertTo-P20RitualTime $Since
    $to = ConvertTo-P20RitualTime $AsOf
    $first = $from.ToString('yyyy-MM-dd', $inv)
    $last = $to.ToString('yyyy-MM-dd', $inv)
    $numbers = @{}
    foreach ($i in @($Issues)) { if ($null -ne $i) { $numbers[[string][int](Get-P20SuggestField $i 'number')] = $true } }
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($issue in @($Issues | Where-Object { $null -ne $_ } | Sort-Object { [int](Get-P20SuggestField $_ 'number') })) {
        if (([string](Get-P20SuggestField $issue 'state')).ToUpperInvariant() -ne 'CLOSED') { continue }
        $m = Get-P20SuggestField $issue 'milestone'
        $title = ''
        if ($m -is [string]) { $title = $m } elseif ($null -ne $m) { $title = [string](Get-P20SuggestField $m 'title') }
        $closedAt = Get-P20SuggestField $issue 'closedAt'
        $when = ConvertTo-P20RitualTime $closedAt
        $ref = '#' + [string][int](Get-P20SuggestField $issue 'number')
        if (-not $title -or $null -eq $when -or $when -lt $from -or $when -gt $to -or $seen.ContainsKey($ref)) { continue }
        $seen[$ref] = $true
        [void]$out.Add([ordered]@{ ref = $ref; kind = 'issue'; milestone = $title; day = (ConvertTo-P20SuggestDay $closedAt); billable = $true })
    }
    $sorted = New-Object 'System.Collections.Generic.List[object]'
    foreach ($card in @($Cards)) { if ($null -ne $card) { $sorted.Add($card) } }
    $sorted.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string](Get-P20SuggestField $a 'file'), [string](Get-P20SuggestField $b 'file')) })
    foreach ($card in $sorted) {
        $cid = [string](Get-P20SuggestField $card 'id')
        $title = [string](Get-P20SuggestField $card 'sprint')
        $day = ConvertTo-P20SuggestDay (Get-P20SuggestField $card 'closed')
        if ([string](Get-P20SuggestField $card 'folder') -ne [string]$c.folders.archive) { continue }
        if (-not $cid -or $numbers.ContainsKey($cid) -or $seen.ContainsKey($cid) -or -not $title) { continue }
        if (-not $day -or [string]::CompareOrdinal($day, $first) -lt 0 -or [string]::CompareOrdinal($day, $last) -gt 0) { continue }
        $seen[$cid] = $true
        $billable = Get-P20SuggestField $card 'billable'
        [void]$out.Add([ordered]@{ ref = $cid; kind = 'card'; milestone = $title; day = $day; billable = (-not ($billable -is [bool] -and -not $billable)) })
    }
    return $out.ToArray()
}

function Add-P20StandupCorner {
    <#
      The Corner attached to a filled standup, in place: corner, or $null with
      the switch off (the suggestion's -- the Corner is its second surface,
      D-AR8) or the tracker not answering. -Prefix is the CLI's, for the brief's
      command; -Viewer the signed-in gh user's login, as the suggestion takes it
      -- the pick is the suggestion's, so the exclusions are. attach_corner in
      the agent.
    #>
    param([Parameter(Mandatory)]$Standup, $Labels, $Issues, $Cards, [bool]$On, [string]$Prefix, [string]$Viewer = '', [string]$PackageRoot)
    $Standup['corner'] = $null
    if (-not $On -or -not $Standup.tracker.ok) { return $Standup }
    $waiting = New-Object System.Collections.ArrayList
    foreach ($kind in @('walk', 'decide', 'look')) {
        if (-not $Standup.queue.Contains($kind)) { continue }
        foreach ($it in @($Standup.queue[$kind] | Where-Object { $null -ne $_ })) { [void]$waiting.Add((Get-P20StandupItemRef $it)) }
    }
    $useIssues = @()
    if ([string]$Standup.source -ceq 'issues' -or [string]$Standup.source -ceq 'both') { $useIssues = @($Issues) }
    $items = @(Get-P20SuggestionItems -Labels $Labels -Issues $useIssues -Cards $Cards -Waiting ([string[]]$waiting.ToArray()) -Viewer $Viewer -PackageRoot $PackageRoot)
    $closed = @(Get-P20CornerClosed -Issues $useIssues -Cards $Cards -Since $Standup.since -AsOf $Standup.asOf)
    $got = Get-P20CornerLine -Items $items -Closed $closed -PackageRoot $PackageRoot
    $t = (Get-P20Consts).rituals.text
    if ($got.command) {
        $got['brief'] = Format-P20SuggestTemplate ([string]$t.cornerBriefCommand) @{ line = $got.line; chevron = [string]$t.cornerChevron; command = ($Prefix + $got.command) }
    }
    else {
        $got['brief'] = Format-P20SuggestTemplate ([string]$t.cornerBrief) @{ line = $got.line }
    }
    $Standup['corner'] = $got
    return $Standup
}
