<#
.SYNOPSIS
    Solitaire Agile's Ritual Engine, the standup's half of it, in one file. Dot-source it.

.DESCRIPTION
    Not a command. Everything the CLI works OUT about a standup lives here, so
    the verb (Standup) and the suite (Tests/Test-Rituals.ps1) read one answer,
    and neither touches the tracker -- the gh calls are the verb's thin layer
    around these:

      Get-P20RitualData        the two data files consts.json names (the
                               ceremonies' slots and queue kinds, and the
                               vocabulary), read relative to the package.
      Get-P20StandupSince      the window's start: local midnight at the start
                               of the previous WORKING day (Mon-Fri) relative to
                               asOf, in asOf's own offset. Monday's, Saturday's
                               and Sunday's is Friday's.
      Get-P20StandupWorkers    the worker rule: a label whose description starts
                               with rituals.workerLabelPrefix; the name is the
                               text after it up to the " -- " separator.
                               Ordered by label name (ordinal).
      Invoke-P20StandupFill    (asOf, labels, issues, tracker) -> the response
                               object of the standup's shape, text left empty.
      Get-P20StandupSource     (address, status) -> which source fills it:
                               both (a GitHub Space that is not local: its
                               issues and its cards, joined on the id), cards
                               (no tracker address, or a local or archive
                               Space), none (Azure DevOps -- D-TA19).
      Get-P20StandupCardTitle  a card's heading -> the title a slot shows.
      Get-P20StandupCards      the impure half of the second source: a Space's
                               current/ and archive/ read into card rows.
      Invoke-P20StandupCardsFill (asOf, cards, space, spaceName) -> the same
                               response, filled from cards.
      Invoke-P20StandupJoinedFill (asOf, labels, issues, tracker, cards, space,
                               spaceName) -> the issues fill joined with the
                               cards on the id: the Check lines and the links.
      Test-P20StandupSince     Standup -Since's day: '' or why it is not a window.
      Get-P20StandupCounts     what moved: each item by its motion and
                               the distinct commits its cards thread, per
                               worker and in total.
      Format-P20StandupText    the filled object -> the text, LF-joined, every
                               fixed word from consts.json rituals.text; a slot
                               line says what moved after its ref.
      Group-P20StandupWork     the work grain: one slot's items grouped
                               by milestone, design card, card type or the
                               titles' common stem, one phrase per group.
      Get-P20StandupProseSentence  the prose: one group as one standup
                               sentence -- a grammar over the groups, no model.
      Format-P20StandupWork    the filled object -> the work grain's text, its
                               prose: one line for the queue, one per worker.
      Test-P20StandupDress     the dress guard: a model's sentence and its
                               group's facts -> '' or the guard it fails. The
                               CLI calls no model; the guard is the contract.

    The agent's agent/solitaire/standup.py implements the same rule over the
    same files; Tests/fixtures/rituals/standup.json (issues),
    standup-cards.json (cards) and standup-joined.json (both), with the golden
    texts beside them, hold the two to one table, byte for byte.

    The real register never reads the vocabulary's fakeWork family (D-SA5) --
    nor excuses (the nonsense register's) -- only phrasebook (the chair)
    and nothing (the empty worker's status) -- and the suite greps every
    rendered case for fakeWork.

    Times are DateTimeOffset throughout and compared with their offsets. A value
    may arrive as a string (5.1's ConvertFrom-Json, a fixture) or a [datetime]
    (7's ConvertFrom-Json turns ISO strings into one); ConvertTo-P20RitualTime
    takes either, and the instant is kept.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
# The second source reads cards the way every verb does: the tracker rule,
# the one id rule and the status verb's state rule, each from its own file.
if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1') }
if (-not (Get-Command Get-P20CardId -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1') }
# Get-PromptFileStatus.ps1 also holds Test-P20CardBillable, the one reader of **Billable:**.
if (-not (Get-Command Test-P20CardBillable -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1') }

function Get-P20RitualData {
    <# The rituals contract plus the two data files it names, read from the package. #>
    param([string]$PackageRoot)
    if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
    # The ceremony this file fills. Its slots and queue kinds are the data
    # file's, never typed here (D-SA2).
    $name = 'standup'
    $rituals = (Get-P20Consts).rituals
    $ceremonies = Get-Content -LiteralPath (Join-Path $PackageRoot $rituals.ceremoniesFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    $vocabulary = Get-Content -LiteralPath (Join-Path $PackageRoot $rituals.vocabularyFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
        Rituals    = $rituals
        Name       = $name
        Ceremony   = $ceremonies.$name
        Vocabulary = $vocabulary
    }
}

function ConvertTo-P20RitualTime {
    <# A string, [datetime] or [DateTimeOffset] -> [DateTimeOffset], or $null. #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [datetime]) { return [DateTimeOffset]$Value }
    $text = ([string]$Value).Trim()
    if (-not $text) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Format-P20RitualTime {
    <# The one wire shape for a time: yyyy-MM-ddTHH:mm:ss+hh:mm. #>
    param([DateTimeOffset]$Value)
    return $Value.ToString("yyyy-MM-dd'T'HH:mm:sszzz", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-P20StandupSince {
    <#
      Yesterday's lower bound. With no Window: local midnight at the start of the
      previous working day (Mon-Fri), in AsOf's offset. With a Window -- a
      yyyy-MM-dd day (Standup -Since), already held by Test-P20StandupSince --
      local midnight of that day in AsOf's offset. window_start in the agent.
    #>
    param([Parameter(Mandatory)][DateTimeOffset]$AsOf, [string]$Window)
    if ($Window) {
        $day = [datetime]::ParseExact($Window.Trim(), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        return (New-Object DateTimeOffset -ArgumentList $day.Year, $day.Month, $day.Day, 0, 0, 0, $AsOf.Offset)
    }
    $day = $AsOf.Date.AddDays(-1)
    while ($day.DayOfWeek -eq [DayOfWeek]::Saturday -or $day.DayOfWeek -eq [DayOfWeek]::Sunday) {
        $day = $day.AddDays(-1)
    }
    return (New-Object DateTimeOffset -ArgumentList $day.Year, $day.Month, $day.Day, 0, 0, 0, $AsOf.Offset)
}

function Test-P20StandupSince {
    <#
      '' when Since is a window the standup can read: empty (the default, the
      previous working day) or a yyyy-MM-dd day no later than AsOf's. Else the
      reason -- Standup -Since states it and exits 2. since_refusal in the agent.
    #>
    param([Parameter(Mandatory)][DateTimeOffset]$AsOf, [AllowEmptyString()][AllowNull()][string]$Since)
    $text = ([string]$Since).Trim()
    if (-not $text) { return '' }
    $day = [datetime]::MinValue
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact($text, 'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$day)) {
        return "-Since '$Since' is not a day: yyyy-MM-dd."
    }
    if ($day.Date -gt $AsOf.Date) {
        return "-Since '$Since' is after $($AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)): a window looks back."
    }
    return ''
}

function Get-P20StandupCardHashes {
    <#
      A card row's commits: its commits hashes, distinct by their first seven
      characters (lowercase, so a short and a full hash of one commit are one),
      in first-seen order. card_hashes in the agent.
    #>
    param($Card)
    $seen = New-Object 'System.Collections.Generic.List[string]'
    $list = $null
    if ($Card -is [System.Collections.IDictionary]) { if ($Card.Contains('commits')) { $list = $Card['commits'] } }
    elseif ($null -ne $Card -and $Card.PSObject.Properties['commits']) { $list = $Card.commits }
    foreach ($h in @($list)) {
        if ($null -eq $h) { continue }
        $key = ([string]$h).Trim().ToLowerInvariant()
        if ($key.Length -gt 7) { $key = $key.Substring(0, 7) }
        if ($key -and -not $seen.Contains($key)) { $seen.Add($key) }
    }
    return , ([string[]]$seen.ToArray())
}

function Test-P20StandupCardBegun {
    <# Whether a card row's begun day (its **Started:** day, else **Created:**) is in [From, To], as days. card_begun_in in the agent. #>
    param($Card, [string]$From, [string]$To)
    $day = ConvertTo-P20StandupDay $Card.begun
    return ([bool]$day -and [string]::CompareOrdinal($day, $From) -ge 0 -and [string]::CompareOrdinal($day, $To) -le 0)
}

function Get-P20StandupWorkers {
    <#
      The worker labels, from `gh label list --json name,description`: each one
      whose description starts with the prefix, as @{ label; name }, ordered by
      label name (ordinal, so every host and the agent sort alike).
    #>
    param($Labels, [Parameter(Mandatory)][string]$Prefix)
    $rows = @{}
    foreach ($l in @($Labels)) {
        if ($null -eq $l) { continue }
        $name = [string]$l.name
        $desc = [string]$l.description
        if (-not $name -or -not $desc.StartsWith($Prefix, [System.StringComparison]::Ordinal)) { continue }
        $rest = $desc.Substring($Prefix.Length)
        $cut = $rest.IndexOf(' -- ', [System.StringComparison]::Ordinal)
        if ($cut -ge 0) { $rest = $rest.Substring(0, $cut) }
        $worker = $rest.Trim()
        if (-not $worker) { $worker = $name }
        if (-not $rows.ContainsKey($name)) { $rows[$name] = [ordered]@{ label = $name; name = $worker } }
    }
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $rows.Keys) { $names.Add([string]$k) }
    $names.Sort([System.StringComparer]::Ordinal)
    $result = New-Object System.Collections.ArrayList
    foreach ($n in $names) { [void]$result.Add($rows[$n]) }
    return $result.ToArray()
}

function Get-P20IssueLabelNames {
    <# An issue's label names: gh gives objects with .name, the fixture gives strings. #>
    param($Issue)
    $names = New-Object System.Collections.ArrayList
    foreach ($l in @($Issue.labels)) {
        if ($null -eq $l) { continue }
        if ($l -is [string]) { [void]$names.Add($l); continue }
        if ($l.PSObject.Properties['name']) { [void]$names.Add([string]$l.name); continue }
        if ($l -is [System.Collections.IDictionary] -and $l.Contains('name')) { [void]$names.Add([string]$l['name']) }
    }
    return $names.ToArray()
}

function Get-P20StandupIssueKeys {
    <#
      Every issue's work-grain key, '#<n>|' -> Get-P20StandupWorkKey's answer. A
      `> GitHub:` thread is named by its issue's head: every issue in the read.
      agent/solitaire/standup.py's issue_keys is the same rule.
    #>
    param($Issues)
    $threads = @{}
    foreach ($issue in @($Issues)) { if ($null -ne $issue) { $threads[[string][int]$issue.number] = [string]$issue.title } }
    $keys = @{}
    foreach ($issue in @($Issues)) {
        if ($null -eq $issue) { continue }
        $keys['#' + [int]$issue.number + '|'] = Get-P20StandupWorkKey -Milestone $issue.milestone -Body ([string]$issue.body) -Threads $threads
    }
    return $keys
}

function Invoke-P20StandupFill {
    <#
      The fill. Pure over its inputs: no gh, no clock, no file but the two data
      files. Returns the standup's response (docs/modules/solitaire-agile.md, "The file shape, and how a standup is read") as an ordered dictionary,
      with text '' -- Format-P20StandupText renders it.

        yesterday  closed, with the worker label, closedAt in [since, asOf]
        blockers   open, with the worker label AND the walk label
        today      open, with the worker label and NOT the walk label
        queue.walk every open issue with the walk label, worker or none, by number
        decide, look  empty in M0

      An issue's worker is its first worker label. An open issue with neither a
      worker label nor the walk label appears nowhere. A worker whose slots are
      all empty is empty and carries one status sentence (the wire field is still named excuse): nothing[(d + i) mod len], d the
      day of the year of asOf (1-based), i its position (0-based). The chair
      opens on phrasebook[d mod len] and closes on phrasebook[(d + 1) mod len].
      With tracker.ok false the queue and the workers are empty -- the ritual
      happens anyway.
    #>
    param(
        [Parameter(Mandatory)]$AsOf,
        $Labels,
        $Issues,
        $Tracker,
        [string]$Space = '',
        [string]$Window = '',
        [string]$PackageRoot
    )
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $rituals = $data.Rituals
    $motions = @($rituals.motions | ForEach-Object { [string]$_ })
    $at = ConvertTo-P20RitualTime $AsOf
    if ($null -eq $at) { throw "asOf '$AsOf' is not a time." }
    $since = Get-P20StandupSince -AsOf $at -Window $Window
    $d = $at.DayOfYear

    $phrases = @($data.Vocabulary.phrasebook)
    $nothing = @($data.Vocabulary.nothing)

    $ok = $true
    $reason = ''
    if ($null -ne $Tracker) {
        $ok = [bool]$Tracker.ok
        $reason = [string]$Tracker.reason
    }

    $queueLists = [ordered]@{}
    foreach ($kind in @($data.Ceremony.queue)) { $queueLists[[string]$kind] = New-Object System.Collections.ArrayList }
    $slots = @($data.Ceremony.slots | ForEach-Object { [string]$_ })
    $kinds = @($data.Ceremony.queue | ForEach-Object { [string]$_ })
    $workers = New-Object System.Collections.ArrayList
    # The work grain's key for every item: '<ref>|<path>' -> @{ name; by }.
    $keyOf = @{}
    if ($ok) { $keyOf = Get-P20StandupIssueKeys -Issues $Issues }

    if ($ok) {
        $defs = @(Get-P20StandupWorkers -Labels $Labels -Prefix ([string]$rituals.workerLabelPrefix))
        $byLabel = @{}
        $fills = [ordered]@{}
        foreach ($def in $defs) {
            $byLabel[$def.label] = $def
            $lists = @{}
            foreach ($slot in $slots) { $lists[$slot] = New-Object System.Collections.ArrayList }
            $fills[$def.label] = $lists
        }
        $walkLabel = [string]$rituals.walkLabel

        foreach ($issue in @($Issues)) {
            if ($null -eq $issue) { continue }
            $names = @(Get-P20IssueLabelNames $issue)
            $state = ([string]$issue.state).ToUpperInvariant()
            $isOpen = ($state -eq 'OPEN')
            $isWalk = ($names -contains $walkLabel)
            $worker = $null
            foreach ($n in $names) {
                if ($byLabel.ContainsKey($n)) { $worker = $byLabel[$n]; break }
            }
            # Every item has the same seven keys whichever source filled it: an
            # issue's id is null and its path ''; a card's number is null and
            # its url ''. An issue alone says closed or in progress: the read
            # has no fact that marks when its work began.
            $motion = $motions[2]
            if (-not $isOpen) { $motion = $motions[0] }
            $item = [ordered]@{ number = [int]$issue.number; id = $null; title = [string]$issue.title; url = [string]$issue.url; path = ''; motion = $motion; commits = 0 }

            if ($isOpen -and $isWalk -and $queueLists.Contains('walk')) {
                $workerName = ''
                if ($worker) { $workerName = [string]$worker.name }
                [void]$queueLists['walk'].Add([ordered]@{ number = $item.number; id = $null; title = $item.title; url = $item.url; path = ''; motion = $motion; commits = 0; worker = $workerName })
            }
            if (-not $worker) { continue }
            $lists = $fills[$worker.label]
            if ($isOpen) {
                if ($isWalk) { [void]$lists['blockers'].Add($item) } else { [void]$lists['today'].Add($item) }
            }
            elseif ($state -eq 'CLOSED') {
                $closed = ConvertTo-P20RitualTime $issue.closedAt
                if ($null -ne $closed -and $closed -ge $since -and $closed -le $at) { [void]$lists['yesterday'].Add($item) }
            }
        }

        $i = 0
        foreach ($def in $defs) {
            $w = [ordered]@{ label = $def.label; name = $def.name }
            $empty = $true
            foreach ($slot in $slots) {
                $sorted = [object[]]@($fills[$def.label][$slot] | Sort-Object { [int]$_.number })
                if ($sorted.Count -gt 0) { $empty = $false }
                $w[$slot] = $sorted
            }
            $w['empty'] = $empty
            $w['excuse'] = ''
            if ($empty -and $nothing.Count -gt 0) { $w['excuse'] = [string]$nothing[($d + $i) % $nothing.Count] }
            [void]$workers.Add($w)
            $i++
        }
    }

    $queue = [ordered]@{}
    foreach ($kind in $queueLists.Keys) { $queue[$kind] = [object[]]@($queueLists[$kind] | Sort-Object { [int]$_.number }) }
    $work = New-P20StandupWorkEmpty -QueueKinds $kinds
    if ($ok) { $work = New-P20StandupWork -Standup @{ queue = $queue; workers = $workers.ToArray() } -KeyOf $keyOf -QueueKinds $kinds -Slots $slots }
    $counts = Get-P20StandupCounts -Standup @{ workers = $workers.ToArray() } -Hashes @{} -Slots $slots

    $open = ''
    $close = ''
    if ($phrases.Count -gt 0) {
        $open = [string]$phrases[$d % $phrases.Count]
        $close = [string]$phrases[($d + 1) % $phrases.Count]
    }

    return [ordered]@{
        ceremony = $data.Name
        register = 'real'
        asOf     = (Format-P20RitualTime $at)
        since    = (Format-P20RitualTime $since)
        space    = $Space
        source   = $(if ($ok) { 'issues' } else { 'none' })
        tracker  = [ordered]@{ ok = $ok; reason = $reason }
        chair    = [ordered]@{ open = $open; close = $close }
        queue    = $queue
        workers  = [object[]]$workers.ToArray()
        work     = $work
        text     = ''
        checks   = [object[]]@()
        links    = [object[]]@()
        counts   = $counts
    }
}

function Get-P20StandupCounts {
    <#
      What moved in the window, per worker (in the workers' order) and in total,
      as [ordered]@{ workers; total }, each count [ordered]@{ label; name; closed;
      started; inProgress; commits } (the total's label and name ''). Each slot
      item by its motion, and the distinct hashes its card threads -- Hashes
      maps an item's '<ref>|<path>' to them. A hash is counted once per worker
      and once in the total, however many cards thread it; an issue with no
      card, and a card with no bullets, count none. standup_counts in the agent.
    #>
    param($Standup, [hashtable]$Hashes, [string[]]$Slots)
    $m = @((Get-P20Consts).rituals.motions | ForEach-Object { [string]$_ })
    $rows = New-Object System.Collections.ArrayList
    $every = New-Object 'System.Collections.Generic.List[string]'
    $total = [ordered]@{ label = ''; name = ''; closed = 0; started = 0; inProgress = 0; commits = 0 }
    foreach ($w in @($Standup.workers | Where-Object { $null -ne $_ })) {
        $c = [ordered]@{ label = [string]$w.label; name = [string]$w.name; closed = 0; started = 0; inProgress = 0; commits = 0 }
        $mine = New-Object 'System.Collections.Generic.List[string]'
        foreach ($slot in $Slots) {
            foreach ($it in @($w.$slot | Where-Object { $null -ne $_ })) {
                $mo = [string]$it.motion
                if ($mo -ceq $m[0]) { $c['closed'] = $c['closed'] + 1 }
                elseif ($mo -ceq $m[1]) { $c['started'] = $c['started'] + 1 }
                elseif ($mo -ceq $m[2]) { $c['inProgress'] = $c['inProgress'] + 1 }
                $key = (Get-P20StandupItemRef $it) + '|' + [string]$it.path
                if ($Hashes -and $Hashes.ContainsKey($key)) {
                    foreach ($h in @($Hashes[$key])) { if ($h -and -not $mine.Contains([string]$h)) { $mine.Add([string]$h) } }
                }
            }
        }
        $c['commits'] = $mine.Count
        foreach ($h in $mine) { if (-not $every.Contains($h)) { $every.Add($h) } }
        foreach ($k in @('closed', 'started', 'inProgress')) { $total[$k] = $total[$k] + $c[$k] }
        [void]$rows.Add($c)
    }
    $total['commits'] = $every.Count
    return [ordered]@{ workers = [object[]]$rows.ToArray(); total = $total }
}

# -- The second source: cards -------------------------------------------
# A Space with no tracker, or one whose tracker is not asked, still has a board:
# its cards. The mapping (Tests/fixtures/rituals/standup-cards.json is the law):
#
#   yesterday   a card in archive/ whose **Closed:** day is in [since, asOf]
#   today       a card in current/ that is In Progress or Code Review
#   queue.walk  a card in current/ that is Code Review -- what waits on you
#   nowhere     an Active card; an archived card with no **Closed:** line
#
# A local Space has ONE worker, the engineer, so there is one tile, named for
# the Space (its display name, else its slug). Blockers stay empty: a card has
# no walk label. An item names the card by its id (Get-P20CardId) and its path.

function Get-P20StandupSource {
    <#
      Which source fills a Space's standup, from its address and status, as
      @{ source; reason }. Pure. both: a GitHub Space that is not local or
      archive -- its issues AND its cards, joined on the id
      (Invoke-P20StandupJoinedFill). cards: no tracker address, or a local or
      archive Space. none: an Azure DevOps Space -- the human team's board, whose
      standup the team holds in its own room (D-TA19); the reason is
      rituals.text.adoTracker. Invoke-P20StandupFill alone still says issues; no
      Space chooses it.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Address, [AllowEmptyString()][AllowNull()][string]$Status)
    $kind = Resolve-P20Tracker -OrgUrl $Address
    if ($kind -eq 'ado') {
        return @{ source = 'none'; reason = [string](Get-P20Consts).rituals.text.adoTracker }
    }
    if ($kind -eq 'none' -or $Status -eq 'local' -or $Status -eq 'archive') {
        return @{ source = 'cards'; reason = '' }
    }
    return @{ source = 'both'; reason = '' }
}

function Get-P20StandupCardTitle {
    <#
      A card's text -> the title its slot line shows. The first H1; when the part
      before its first colon ends with the card's id ("Task 139: Write the docs"),
      only the part after it. No heading: the filename without .prompt.md / .md.
      agent/solitaire/standup.py's card_title is the same rule, and the fixture's
      titles table holds the two.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content, [string]$File, [string]$Id)
    $m = [regex]::Match("$Content", '(?m)^#[ \t]+([^\r\n]+)')
    if (-not $m.Success) {
        $name = [string]$File
        foreach ($ext in @('.prompt.md', '.md')) {
            if ($name.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) { $name = $name.Substring(0, $name.Length - $ext.Length); break }
        }
        return $name
    }
    $heading = $m.Groups[1].Value.Trim()
    $colon = $heading.IndexOf(':')
    if ($colon -gt 0 -and $Id) {
        $before = $heading.Substring(0, $colon).TrimEnd()
        $after = $heading.Substring($colon + 1).Trim()
        if ($after -and [regex]::IsMatch($before, '(^|\s)' + [regex]::Escape($Id) + '$')) { return $after }
    }
    return $heading
}

function Get-P20StandupCards {
    <#
      The impure half: a Space's current/ and archive/ read into the rows the
      cards fill takes -- @{ file; folder; status; closed; title; id; path; type;
      body; billable; begun; commits }. billable is Test-P20CardBillable's
      answer; begun the day its **Started:** stamp, else its **Created:** stamp,
      carries; commits the hash of every `- <hash>` bullet (commitHashRegex).
      A file the one id rule finds no id in is not a card and is skipped (a
      dated PR-comment record in archive/, a person's note). State is the
      status verb's own rule (Get-PromptFileStatus); a card in archive/ is Done.
    #>
    param([string]$CurrentDir, [string]$ArchiveDir, [Parameter(Mandatory)][string]$Pattern)
    $c = Get-P20Consts
    $closedRx = '(?m)^' + [regex]::Escape([string]$c.stamps.closed) + '\s*(\d{4}-\d{2}-\d{2})'
    # What moved: the day its work began -- **Started:**, else **Created:** -- and its bullets.
    $startedRx = '(?m)^' + [regex]::Escape([string]$c.stamps.started) + '\s*(\d{4}-\d{2}-\d{2})'
    $createdRx = '(?m)^' + [regex]::Escape([string]$c.stamps.created) + '\s*(\d{4}-\d{2}-\d{2})'
    $hashRx = [string]$c.rituals.commitHashRegex
    $rows = New-Object System.Collections.ArrayList
    foreach ($pair in @(@([string]$c.folders.current, $CurrentDir), @([string]$c.folders.archive, $ArchiveDir))) {
        $folder = $pair[0]
        $dir = $pair[1]
        if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -notlike '.*' })) {
            $id = Get-P20CardId -Name $f.Name -Pattern $Pattern
            if (-not $id) { continue }
            $content = [System.IO.File]::ReadAllText($f.FullName)
            $closed = $null
            $begun = $null
            $bm = [regex]::Match($content, $startedRx)
            if (-not $bm.Success) { $bm = [regex]::Match($content, $createdRx) }
            if ($bm.Success) { $begun = $bm.Groups[1].Value }
            $hashes = @([regex]::Matches($content, $hashRx) | ForEach-Object { $_.Groups[1].Value })
            $status = [string]$c.status.done
            if ($folder -eq [string]$c.folders.current) { $status = Get-PromptFileStatus $content }
            else {
                $cm = [regex]::Match($content, $closedRx)
                if ($cm.Success) { $closed = $cm.Groups[1].Value }
            }
            [void]$rows.Add([ordered]@{
                    file   = $f.Name
                    folder = $folder
                    status = $status
                    closed = $closed
                    title  = (Get-P20StandupCardTitle -Content $content -File $f.Name -Id $id)
                    id     = $id
                    path   = $f.FullName
                    type     = (Get-P20StandupCardType -Content $content -Id $id)
                    body     = $content
                    # A card that says **Billable:** no is not a standup row.
                    billable = (Test-P20CardBillable $content)
                    begun    = $begun
                    commits  = [object[]]$hashes
                })
        }
    }
    return $rows.ToArray()
}

function ConvertTo-P20StandupDay {
    <# A Closed stamp -> 'yyyy-MM-dd', or ''. 7's ConvertFrom-Json may hand back a [datetime]. #>
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }
    $text = ([string]$Value).Trim()
    if ($text -match '^\d{4}-\d{2}-\d{2}') { return $text.Substring(0, 10) }
    return ''
}

function Get-P20StandupCardsInPlay {
    <#
      The cards a standup may mention: one per file, in file-name order (ordinal),
      and none that says **Billable:** no (a row with no billable key is billable
      -- no line means billable, the rule Daily reads). cards_in_play in the agent.
    #>
    param($Cards)
    $byFile = @{}
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($card in @($Cards)) {
        if ($null -eq $card) { continue }
        $file = [string]$card.file
        if ($byFile.ContainsKey($file)) { continue }
        $byFile[$file] = $card
        $names.Add($file)
    }
    $names.Sort([System.StringComparer]::Ordinal)
    $rows = New-Object System.Collections.ArrayList
    foreach ($file in $names) {
        $card = $byFile[$file]
        $billable = $true
        if ($card -is [System.Collections.IDictionary]) { if ($card.Contains('billable')) { $billable = $card['billable'] } }
        elseif ($card.PSObject.Properties['billable']) { $billable = $card.billable }
        if ($billable -is [bool] -and -not $billable) { continue }
        [void]$rows.Add($card)
    }
    # Unrolled: every caller wraps the answer in @().
    return $rows.ToArray()
}

function Get-P20StandupCardTile {
    <#
      Cards already in play -> one worker's slots, its walk items and the work
      keys, as @{ worker; walk; keyOf }. yesterday: in archive/, its Closed day in
      [since, asOf] (as days). today: in current/, In Progress or Code Review.
      walk: in current/, Code Review. An Active card is nowhere; so is an archived
      card with no Closed day. A yesterday item is closed; a today item started
      when its begun day is in the window, else in progress. worker.empty is
      set; its status sentence is the caller's. Also returns hashes, each item's
      '<ref>|<path>' -> its card's hashes. _cards_tile in the agent.
    #>
    param([Parameter(Mandatory)][DateTimeOffset]$AsOf, $Cards, [string]$Label, [string]$Name, [string[]]$Slots, $From)
    $c = Get-P20Consts
    $st = $c.status
    $motions = @($c.rituals.motions | ForEach-Object { [string]$_ })
    $archiveName = [string]$c.folders.archive
    $start = $From
    if ($null -eq $start) { $start = Get-P20StandupSince -AsOf $AsOf }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fromDay = ([DateTimeOffset]$start).ToString('yyyy-MM-dd', $inv)
    $toDay = $AsOf.ToString('yyyy-MM-dd', $inv)
    $hashesOf = @{}
    $keyOf = @{}
    $lists = @{}
    foreach ($slot in $Slots) { $lists[$slot] = New-Object System.Collections.ArrayList }
    $walk = New-Object System.Collections.ArrayList
    foreach ($card in @($Cards)) {
        if ($null -eq $card) { continue }
        $file = [string]$card.file
        $path = [string]$card.path
        if (-not $path) { $path = ([string]$card.folder) + '/' + $file }
        $hashes = Get-P20StandupCardHashes $card
        $item = [ordered]@{ number = $null; id = [string]$card.id; title = [string]$card.title; url = ''; path = $path; motion = $motions[2]; commits = $hashes.Count }
        if (Test-P20StandupCardBegun -Card $card -From $fromDay -To $toDay) { $item['motion'] = $motions[1] }
        # A card groups by the design card it names, else its type.
        $keyOf[$item.id + '|' + $path] = Get-P20StandupWorkKey -Milestone $null -Body ([string]$card.body) -Type ([string]$card.type) -Threads @{}
        $hashesOf[$item.id + '|' + $path] = $hashes
        $status = [string]$card.status
        if ([string]$card.folder -eq $archiveName) {
            $item['motion'] = $motions[0]
            $day = ConvertTo-P20StandupDay $card.closed
            if ($day -and [string]::CompareOrdinal($day, $fromDay) -ge 0 -and [string]::CompareOrdinal($day, $toDay) -le 0) {
                [void]$lists['yesterday'].Add($item)
            }
            continue
        }
        if ($status -ceq [string]$st.inProgress -or $status -ceq [string]$st.codeReview) { [void]$lists['today'].Add($item) }
        if ($status -ceq [string]$st.codeReview) {
            [void]$walk.Add([ordered]@{ number = $null; id = $item.id; title = $item.title; url = ''; path = $path; motion = $item.motion; commits = $item.commits; worker = $Name })
        }
    }
    $w = [ordered]@{ label = $Label; name = $Name }
    $empty = $true
    foreach ($slot in $Slots) {
        $arr = [object[]]$lists[$slot].ToArray()
        if ($arr.Count -gt 0) { $empty = $false }
        $w[$slot] = $arr
    }
    $w['empty'] = $empty
    $w['excuse'] = ''
    return @{ worker = $w; walk = [object[]]$walk.ToArray(); keyOf = $keyOf; hashes = $hashesOf }
}

function Invoke-P20StandupCardsFill {
    <#
      The second fill. Pure over its inputs, like the first: card rows in (the
      shape Get-P20StandupCards returns and the fixture states), the response of
      the standup's response out, with source 'cards', text ''. The cards in play
      (Get-P20StandupCardsInPlay: a not-billable card is left out) on ONE worker,
      the engineer, named for the Space, by Get-P20StandupCardTile's mapping. Days
      compare as yyyy-MM-dd strings: a Closed stamp is a day, and since and asOf
      are read as the days they fall on in asOf's own offset. Within a slot, cards
      are in file-name order (ordinal) -- the ledger's tie-break.
    #>
    param(
        [Parameter(Mandatory)]$AsOf,
        $Cards,
        [string]$Space = '',
        [string]$SpaceName = '',
        [string]$Window = '',
        [string]$PackageRoot
    )
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $at = ConvertTo-P20RitualTime $AsOf
    if ($null -eq $at) { throw "asOf '$AsOf' is not a time." }
    $since = Get-P20StandupSince -AsOf $at -Window $Window
    $d = $at.DayOfYear
    $phrases = @($data.Vocabulary.phrasebook)
    $nothing = @($data.Vocabulary.nothing)

    $name = $SpaceName
    if (-not $name) { $name = $Space }
    $slots = @($data.Ceremony.slots | ForEach-Object { [string]$_ })
    $kinds = @($data.Ceremony.queue | ForEach-Object { [string]$_ })
    $tile = Get-P20StandupCardTile -AsOf $at -Cards @(Get-P20StandupCardsInPlay -Cards $Cards) -Label $Space -Name $name -Slots $slots -From $since
    $w = $tile.worker
    if ($w.empty -and $nothing.Count -gt 0) { $w['excuse'] = [string]$nothing[$d % $nothing.Count] }

    $queue = [ordered]@{}
    foreach ($kind in @($data.Ceremony.queue)) { $queue[[string]$kind] = [object[]]@() }
    if ($queue.Contains('walk')) { $queue['walk'] = [object[]]$tile.walk }
    $work = New-P20StandupWork -Standup @{ queue = $queue; workers = @($w) } -KeyOf $tile.keyOf -QueueKinds $kinds -Slots $slots
    $counts = Get-P20StandupCounts -Standup @{ workers = @($w) } -Hashes $tile.hashes -Slots $slots

    $open = ''
    $close = ''
    if ($phrases.Count -gt 0) {
        $open = [string]$phrases[$d % $phrases.Count]
        $close = [string]$phrases[($d + 1) % $phrases.Count]
    }
    return [ordered]@{
        ceremony = $data.Name
        register = 'real'
        asOf     = (Format-P20RitualTime $at)
        since    = (Format-P20RitualTime $since)
        space    = $Space
        source   = 'cards'
        tracker  = [ordered]@{ ok = $true; reason = '' }
        chair    = [ordered]@{ open = $open; close = $close }
        queue    = $queue
        workers  = [object[]]@($w)
        work     = $work
        text     = ''
        checks   = [object[]]@()
        links    = [object[]]@()
        counts   = $counts
    }
}

# -- Both: issues and cards, joined on the id ---------------------------------
# The card is the job record, the tracker the product record; an active GitHub
# Space reads both (Tests/fixtures/rituals/standup-joined.json is the law):
#
#   a card whose id is an issue's number in the read IS that issue's job record:
#     ONE row, the issue's, placed by the issue as Invoke-P20StandupFill places
#     it. The card adds its lane (links) and, where the two disagree, one Check
#     line: archived while the issue is open, or not archived while the issue is
#     closed. Rounds share an id: the one in current/ is the card, else the
#     archived one closed last.
#   any other card -- an id of its own, or a number the read has no issue for --
#     is its own row, under you: one tile labelled with the Space's slug and
#     named for it, by the cards fill's mapping, after the worker tiles, and only
#     when it has something to say. Its Code Review cards follow the issues on
#     the walk.
#   a not-billable card is not a row and adds nothing to one.

function Invoke-P20StandupJoinedFill {
    <#
      The issues fill, joined with the cards on the id. Pure over its inputs.
      With the tracker not answering it is the issues fill as it stands: the
      chair's lines and the reason. fill_joined_standup in the agent.
    #>
    param(
        [Parameter(Mandatory)]$AsOf,
        $Labels,
        $Issues,
        $Tracker,
        $Cards,
        [string]$Space = '',
        [string]$SpaceName = '',
        [string]$Window = '',
        [string]$PackageRoot
    )
    $out = Invoke-P20StandupFill -AsOf $AsOf -Labels $Labels -Issues $Issues -Tracker $Tracker -Space $Space -Window $Window -PackageRoot $PackageRoot
    if (-not $out.tracker.ok) { return $out }
    $out.source = 'both'
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $c = Get-P20Consts
    $t = $c.rituals.text
    $currentName = [string]$c.folders.current
    $at = ConvertTo-P20RitualTime $AsOf
    $slots = @($data.Ceremony.slots | ForEach-Object { [string]$_ })
    $kinds = @($data.Ceremony.queue | ForEach-Object { [string]$_ })
    $motions = @($c.rituals.motions | ForEach-Object { [string]$_ })
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $since = Get-P20StandupSince -AsOf $at -Window $Window
    $fromDay = $since.ToString('yyyy-MM-dd', $inv)
    $toDay = $at.ToString('yyyy-MM-dd', $inv)
    # Every issue row, the slots' and the walk's: a joined card gives its row its commits.
    $issueItems = New-Object System.Collections.ArrayList
    foreach ($w in @($out.workers | Where-Object { $null -ne $_ })) {
        foreach ($slot in $slots) { foreach ($it in @($w.$slot | Where-Object { $null -ne $_ })) { [void]$issueItems.Add($it) } }
    }
    foreach ($it in @($out.queue.walk | Where-Object { $null -ne $_ })) { [void]$issueItems.Add($it) }
    $hashesOf = @{}

    $byNumber = @{}
    foreach ($issue in @($Issues)) { if ($null -ne $issue) { $byNumber[[int]$issue.number] = $issue } }
    $joined = @{}
    $alone = New-Object System.Collections.ArrayList
    foreach ($card in @(Get-P20StandupCardsInPlay -Cards $Cards)) {
        if ($null -eq $card) { continue }
        $cid = [string]$card.id
        $n = 0
        if ($cid -match '^\d+$' -and [int]::TryParse($cid, [ref]$n) -and $byNumber.ContainsKey($n)) {
            if (-not $joined.ContainsKey($n)) { $joined[$n] = New-Object System.Collections.ArrayList }
            [void]$joined[$n].Add($card)
        }
        else { [void]$alone.Add($card) }
    }

    $checks = New-Object System.Collections.ArrayList
    $links = New-Object System.Collections.ArrayList
    foreach ($n in @($joined.Keys | Sort-Object)) {
        $rounds = @($joined[$n])
        $current = @($rounds | Where-Object { [string]$_.folder -eq $currentName })
        if ($current.Count -gt 0) { $card = $current[0] }
        else {
            # The archived round closed last; the later file breaks a tie.
            $card = $rounds[0]
            foreach ($r in $rounds) {
                $byDay = [string]::CompareOrdinal((ConvertTo-P20StandupDay $r.closed), (ConvertTo-P20StandupDay $card.closed))
                if ($byDay -gt 0 -or ($byDay -eq 0 -and [string]::CompareOrdinal([string]$r.file, [string]$card.file) -gt 0)) { $card = $r }
            }
        }
        $path = [string]$card.path
        if (-not $path) { $path = ([string]$card.folder) + '/' + [string]$card.file }
        [void]$links.Add([ordered]@{ number = [int]$n; id = [string]$card.id; lane = [string]$card.status; path = $path })
        $hashes = Get-P20StandupCardHashes $card
        $hashesOf['#' + $n + '|'] = $hashes
        $begun = Test-P20StandupCardBegun -Card $card -From $fromDay -To $toDay
        foreach ($it in $issueItems) {
            if ($null -ne $it.number -and [int]$it.number -eq [int]$n) {
                $it['commits'] = $hashes.Count
                if ($begun -and [string]$it.motion -ceq $motions[2]) { $it['motion'] = $motions[1] }
            }
        }
        $issue = $byNumber[$n]
        $isOpen = (([string]$issue.state).ToUpperInvariant() -eq 'OPEN')
        $item = '#' + $n + ' ' + [string]$issue.title
        if ($current.Count -gt 0 -and -not $isOpen) { [void]$checks.Add(([string]$t.checkIssueClosed).Replace('{item}', $item)) }
        elseif ($current.Count -eq 0 -and $isOpen) { [void]$checks.Add(([string]$t.checkCardArchived).Replace('{item}', $item)) }
    }

    $name = $SpaceName
    if (-not $name) { $name = $Space }
    $tile = Get-P20StandupCardTile -AsOf $at -Cards $alone.ToArray() -Label $Space -Name $name -Slots $slots -From $since
    foreach ($k in @($tile.hashes.Keys)) { $hashesOf[$k] = $tile.hashes[$k] }
    $workers = New-Object System.Collections.ArrayList
    foreach ($w in @($out.workers | Where-Object { $null -ne $_ })) { [void]$workers.Add($w) }
    if (-not $tile.worker.empty) { [void]$workers.Add($tile.worker) }
    $out.workers = [object[]]$workers.ToArray()
    if ($out.queue.Contains('walk')) {
        $walk = New-Object System.Collections.ArrayList
        foreach ($i in @($out.queue.walk | Where-Object { $null -ne $_ })) { [void]$walk.Add($i) }
        foreach ($i in @($tile.walk | Where-Object { $null -ne $_ })) { [void]$walk.Add($i) }
        $out.queue['walk'] = [object[]]$walk.ToArray()
    }
    $keyOf = Get-P20StandupIssueKeys -Issues $Issues
    foreach ($k in @($tile.keyOf.Keys)) { $keyOf[$k] = $tile.keyOf[$k] }
    $out.work = New-P20StandupWork -Standup @{ queue = $out.queue; workers = $out.workers } -KeyOf $keyOf -QueueKinds $kinds -Slots $slots
    $out.checks = [object[]]$checks.ToArray()
    $out.links = [object[]]$links.ToArray()
    $out.counts = Get-P20StandupCounts -Standup @{ workers = $out.workers } -Hashes $hashesOf -Slots $slots
    return $out
}

function Get-P20StandupItemRef {
    <# How a slot line names its item: '#<number>' for an issue, the card's id for a card. #>
    param($Item)
    if ($null -ne $Item.number -and "$($Item.number)" -ne '') { return '#' + $Item.number }
    return [string]$Item.id
}

# -- The work grain (D-TA20) ----------------------------------------------
# The ritual speaks at the grain of the WORK, not the ticket: each worker's slot
# items grouped by what they belong to, one phrase per group with the count behind
# it ("Team Agile, three closed; the Studio, one"). No model groups anything: every
# noun is a milestone's, a design card's, a card type's or the titles' own words,
# and every count is derived. agent/solitaire/standup.py implements the same rule;
# Tests/fixtures/rituals/standup-work.json holds the two to one table.
#
#   1. milestone   the issue's milestone title                         by milestone
#   2. design      the design card the body names: a `> GitHub:` thread
#                  (named by that issue's head when the read has it, else
#                  #<n>), else a design/<note>.md (its stem, title-cased)  by design
#   3. type        a card's type, from its heading                      by type
#   4. stem        what is left in the slot, by the titles' common stem: the
#                  head (a one-word type tag dropped, cut at ' -- ' or ': ');
#                  heads sharing their first two words or more (a trailing
#                  small word like 'the' not counted) group under the words
#                  they all share; a head alone names itself            by stem
#
# Groups with the same name (ignoring case) are one group, named as first seen.
# Most items first; a tie keeps the order the slot has them in.

function Get-P20StandupHead {
    <# A title's head, by rituals.workHeadRegex; the trimmed title when that leaves nothing. #>
    param([AllowEmptyString()][AllowNull()][string]$Title)
    $text = ([string]$Title).Trim()
    $m = [regex]::Match($text, [string](Get-P20Consts).rituals.workHeadRegex)
    if ($m.Success) {
        $head = $m.Groups[1].Value.Trim()
        if ($head) { return $head }
    }
    return $text
}

function Get-P20StandupDesignName {
    <# A design note's stem, title-cased: 'team-agile' -> 'Team Agile'. #>
    param([string]$Stem)
    $words = @(([string]$Stem) -split '[-_]+' | Where-Object { $_ })
    return ((@($words | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })) -join ' ')
}

function Get-P20StandupCardType {
    <#
      A card's type, from its heading: the words before its id, when the part
      before the first colon ends with the id ("Task 139: Write the docs" is
      Task). '' when the heading says none. card_type in the agent is the same.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content, [string]$Id)
    $m = [regex]::Match("$Content", '(?m)^#[ \t]+([^\r\n]+)')
    if (-not $m.Success -or -not $Id) { return '' }
    $heading = $m.Groups[1].Value.Trim()
    $colon = $heading.IndexOf(':')
    if ($colon -le 0) { return '' }
    $tm = [regex]::Match($heading.Substring(0, $colon).TrimEnd(), '^(.*\S)\s+' + [regex]::Escape($Id) + '$')
    if ($tm.Success) { return $tm.Groups[1].Value.Trim() }
    return ''
}

function Get-P20StandupWorkKey {
    <#
      What one item belongs to, as @{ name; by }: rules 1 to 3 above, in order.
      name '' means none of them named it, and the slot's common stem will.
      Milestone is gh's object ({ title }) or the fixture's string. Threads maps
      an issue number (as a string) to its title -- every issue in the read.
      Pure.
    #>
    param(
        $Milestone,
        [AllowEmptyString()][AllowNull()][string]$Body,
        [AllowEmptyString()][AllowNull()][string]$Type,
        [hashtable]$Threads
    )
    $rituals = (Get-P20Consts).rituals
    $title = ''
    if ($null -ne $Milestone) {
        if ($Milestone -is [string]) { $title = $Milestone }
        elseif ($Milestone -is [System.Collections.IDictionary]) { if ($Milestone.Contains('title')) { $title = [string]$Milestone['title'] } }
        elseif ($Milestone.PSObject.Properties['title']) { $title = [string]$Milestone.title }
    }
    $title = $title.Trim()
    if ($title) { return @{ name = $title; by = 'milestone' } }

    $text = [string]$Body
    $tm = [regex]::Match($text, [string]$rituals.workThreadRegex)
    if ($tm.Success) {
        $n = [string][int]$tm.Groups[1].Value
        $name = '#' + $n
        if ($Threads -and $Threads.ContainsKey($n)) { $name = Get-P20StandupHead $Threads[$n] }
        return @{ name = $name; by = 'design' }
    }
    $dm = [regex]::Match($text, [string]$rituals.workDesignRegex)
    if ($dm.Success) { return @{ name = (Get-P20StandupDesignName $dm.Groups[1].Value); by = 'design' } }

    $kind = ([string]$Type).Trim()
    if ($kind) { return @{ name = $kind; by = 'type' } }
    return @{ name = ''; by = '' }
}

function Get-P20StandupCountWord {
    <# A count as the voice says it: rituals.numberWords[n], digits past its end. #>
    param([int]$N)
    $words = @((Get-P20Consts).rituals.numberWords)
    if ($N -ge 0 -and $N -lt $words.Count) { return [string]$words[$N] }
    return [string]$N
}

function Get-P20StandupCommonWords {
    <#
      How many leading words two word lists share, ignoring case -- not counting
      a trailing small word (rituals.workSmallWordRegex: 'the', 'of', 'a'), so
      "Verify the Studio" and "Verify the clock" share one word, not two.
    #>
    param([string[]]$A, [string[]]$B)
    $small = [string](Get-P20Consts).rituals.workSmallWordRegex
    $k = 0
    while ($k -lt $A.Count -and $k -lt $B.Count -and $A[$k].ToLowerInvariant() -ceq $B[$k].ToLowerInvariant()) { $k++ }
    while ($k -gt 0 -and [regex]::IsMatch($A[$k - 1], $small)) { $k-- }
    return $k
}

function Group-P20StandupWork {
    <#
      One slot's entries -- @{ ref; title; name; by }, in the slot's order -> its
      groups, each [ordered]@{ name; by; count; refs; phrase }. First is the
      phrase template of the slot's first group (text.work<Slot>), Rest the
      others' (text.workGroup). Pure.
    #>
    param($Entries, [string]$First, [string]$Rest)
    $list = @($Entries | Where-Object { $null -ne $_ })
    $names = New-Object 'string[]' $list.Count
    $bys = New-Object 'string[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { $names[$i] = [string]$list[$i].name; $bys[$i] = [string]$list[$i].by }

    # Rule 4: what nothing named groups by the common stem of its titles' heads.
    $left = @(for ($i = 0; $i -lt $list.Count; $i++) { if (-not $names[$i]) { $i } })
    $heads = @{}
    $words = @{}
    foreach ($i in $left) {
        $heads[$i] = Get-P20StandupHead ([string]$list[$i].title)
        $words[$i] = [string[]]@(([string]$heads[$i]) -split '\s+' | Where-Object { $_ })
    }
    foreach ($i in $left) {
        if ($names[$i]) { continue }
        $members = @($i)
        $shared = [int]::MaxValue
        foreach ($j in $left) {
            if ($j -le $i -or $names[$j]) { continue }
            $k = Get-P20StandupCommonWords $words[$i] $words[$j]
            if ($k -ge 2) { $members += $j; if ($k -lt $shared) { $shared = $k } }
        }
        $name = [string]$heads[$i]
        if ($members.Count -gt 1) { $name = ($words[$i][0..($shared - 1)]) -join ' ' }
        foreach ($m in $members) { $names[$m] = $name; $bys[$m] = 'stem' }
    }

    # One group per name, ignoring case, named as first seen.
    $groups = New-Object System.Collections.ArrayList
    $at = @{}
    for ($i = 0; $i -lt $list.Count; $i++) {
        $key = $names[$i].ToLowerInvariant()
        if (-not $at.ContainsKey($key)) {
            $at[$key] = $groups.Count
            [void]$groups.Add([ordered]@{ name = $names[$i]; by = $bys[$i]; count = 0; refs = (New-Object System.Collections.ArrayList); index = $groups.Count })
        }
        $g = $groups[$at[$key]]
        $g.count++
        [void]$g.refs.Add([string]$list[$i].ref)
    }
    # Most first; a tie keeps first appearance.
    $sorted = @($groups | Sort-Object -Property @{ Expression = { - [int]$_.count } }, @{ Expression = { [int]$_.index } })
    $out = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($g in $sorted) {
        $template = $Rest
        if ($n -eq 0) { $template = $First }
        $phrase = $template.Replace('{name}', [string]$g.name).Replace('{n}', (Get-P20StandupCountWord ([int]$g.count)))
        [void]$out.Add([ordered]@{ name = $g.name; by = $g.by; count = [int]$g.count; refs = [object[]]$g.refs.ToArray(); phrase = $phrase })
        $n++
    }
    return , ([object[]]$out.ToArray())
}

function Get-P20StandupWorkTemplate {
    <# The phrase template for a slot's or a queue kind's first group: text.work<Slot>, else text.workGroup. #>
    param([string]$Slot)
    $t = (Get-P20Consts).rituals.text
    $key = 'work' + $Slot.Substring(0, 1).ToUpperInvariant() + $Slot.Substring(1)
    $value = $null
    if ($t.PSObject.Properties[$key]) { $value = [string]$t.$key }
    if (-not $value) { $value = [string]$t.workGroup }
    return $value
}

function New-P20StandupWork {
    <#
      The filled standup's work grain: [ordered]@{ queue; workers; text = '' }.
      KeyOf maps an item's '<ref>|<path>' to its Get-P20StandupWorkKey answer.
      queue: each kind's groups; workers: each worker's label, name and three
      slots' groups. Pure.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'KeyOf', Justification = 'Read inside the $entriesOf scriptblock, which the rule does not follow.')]
    param($Standup, [hashtable]$KeyOf, [string[]]$QueueKinds, [string[]]$Slots)
    $t = (Get-P20Consts).rituals.text
    $entriesOf = {
        param($Items)
        $rows = New-Object System.Collections.ArrayList
        foreach ($item in @($Items | Where-Object { $null -ne $_ })) {
            $ref = Get-P20StandupItemRef $item
            $key = $KeyOf[$ref + '|' + [string]$item.path]
            $name = ''
            $by = ''
            if ($key) { $name = [string]$key.name; $by = [string]$key.by }
            [void]$rows.Add(@{ ref = $ref; title = [string]$item.title; name = $name; by = $by })
        }
        return , ($rows.ToArray())
    }
    $queue = [ordered]@{}
    $queueProse = New-Object System.Collections.ArrayList
    foreach ($kind in $QueueKinds) {
        $rows = & $entriesOf $Standup.queue.$kind
        $queue[$kind] = Group-P20StandupWork -Entries $rows -First (Get-P20StandupWorkTemplate $kind) -Rest ([string]$t.workGroup)
        foreach ($said in @(Get-P20StandupProse -Slot $kind -Groups $queue[$kind] -Rows $rows)) { [void]$queueProse.Add($said) }
    }
    $workers = New-Object System.Collections.ArrayList
    foreach ($w in @($Standup.workers | Where-Object { $null -ne $_ })) {
        $row = [ordered]@{ label = $w.label; name = $w.name }
        $prose = New-Object System.Collections.ArrayList
        foreach ($slot in $Slots) {
            $rows = & $entriesOf $w.$slot
            $row[$slot] = Group-P20StandupWork -Entries $rows -First (Get-P20StandupWorkTemplate $slot) -Rest ([string]$t.workGroup)
            foreach ($said in @(Get-P20StandupProse -Slot $slot -Groups $row[$slot] -Rows $rows)) { [void]$prose.Add($said) }
        }
        # Something said and no blockers: the worker closes on "Nothing blocked.".
        if ($prose.Count -gt 0 -and @($row['blockers'] | Where-Object { $null -ne $_ }).Count -eq 0) {
            [void]$prose.Add([string]$t.proseBlockersNone)
        }
        $row['prose'] = [object[]]$prose.ToArray()
        [void]$workers.Add($row)
    }
    return [ordered]@{ queue = $queue; workers = [object[]]$workers.ToArray(); queueProse = [object[]]$queueProse.ToArray(); text = '' }
}

# -- The prose -------------------------------------------------------------
# The work grain spoken as standup language: a grammar over the groups, no model.
# One sentence a group -- text.proseSentence joins a LEAD and a BODY:
#
#   lead  text.prose<Slot> for the slot's (or queue kind's) first group,
#         text.prose<Slot>Also for the rest     "Yesterday I closed" / "I also closed"
#   body  a group of one whose name IS its item's clause: text.proseBare
#                                               "#413, Rename the slug"
#         a group of one: text.prose<Slot>One, else text.proseOne
#                                               "one in the Studio: #<n>, Count the foyer rows"
#         a group of more: text.prose<Slot>Many, else text.proseMany
#                                               "two in Team Agile"
#
# {item} is text.proseItem -- the ref, then the title trimmed to its clause (its
# head, by workHeadRegex); {refs} the group's refs joined by proseRefSeparator.
# A slot with a text.prose<Slot>Fold template (today's) FOLDS when two or more
# groups follow its first (D-SA9: a group and a count, never a list): the
# first group is its own sentence, as above, and the rest are ONE sentence --
#
#   lead  text.prose<Slot>Also                  "I'm also on"
#   body  up to proseFoldNames groups: text.prose<Slot>Fold, {n} the number of
#         groups, {names} their names (proseNameSeparator, the last proseNameLast)
#                                               "three more: the Studio, Phase 6 and Docs"
#         past it: text.prose<Slot>FoldCount    "seven more designs"
#
# No ref in a folded sentence: the thought bubble keeps every number.
# A worker with something to say and no blockers ends on text.proseBlockersNone.
# agent/solitaire/standup.py's prose_sentence and prose_sentences are the same
# rule; Tests/fixtures/rituals/standup-prose.json holds the two to one table.

function Format-P20ProseTemplate {
    <# One pass over a template's placeholders: a value is never read as a placeholder. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Values', Justification = 'Read inside the MatchEvaluator scriptblock, which the rule does not follow.')]
    param([string]$Template, [hashtable]$Values)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $k = $m.Groups[1].Value
        if ($Values.ContainsKey($k)) { return [string]$Values[$k] }
        return $m.Value
    }
    return [regex]::Replace([string]$Template, '\{(n|names|name|item|refs|ref|clause|lead|body|motion|title|date|counts)\}', $evaluator)
}

function Get-P20StandupProseText {
    <# A prose template by key; $null when rituals.text has none. #>
    param([string]$Key)
    $t = (Get-P20Consts).rituals.text
    if ($t.PSObject.Properties[$Key]) { return [string]$t.$Key }
    return $null
}

function Get-P20StandupProseSentence {
    <#
      One group of a slot (or queue kind) as one standup sentence -- the rule
      above. First is whether it is the slot's first group; Titles maps a ref
      to its item's title. Pure.
    #>
    param([string]$Slot, [bool]$First, $Group, [hashtable]$Titles)
    $cap = $Slot.Substring(0, 1).ToUpperInvariant() + $Slot.Substring(1)
    $leadKey = 'prose' + $cap
    if (-not $First) { $leadKey = $leadKey + 'Also' }
    $lead = Get-P20StandupProseText $leadKey
    $count = [int]$Group.count
    $n = Get-P20StandupCountWord $count
    $name = [string]$Group.name
    $refs = @($Group.refs | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    if ($count -eq 1 -and $refs.Count -gt 0) {
        $ref = $refs[0]
        $title = ''
        if ($Titles -and $Titles.ContainsKey($ref)) { $title = [string]$Titles[$ref] }
        $clause = Get-P20StandupHead $title
        $item = Format-P20ProseTemplate (Get-P20StandupProseText 'proseItem') @{ ref = $ref; clause = $clause }
        if ($name.ToLowerInvariant() -ceq $clause.ToLowerInvariant()) {
            $body = Format-P20ProseTemplate (Get-P20StandupProseText 'proseBare') @{ item = $item }
        }
        else {
            $template = Get-P20StandupProseText ('prose' + $cap + 'One')
            if (-not $template) { $template = Get-P20StandupProseText 'proseOne' }
            $body = Format-P20ProseTemplate $template @{ n = $n; name = $name; item = $item }
        }
    }
    else {
        $joined = $refs -join (Get-P20StandupProseText 'proseRefSeparator')
        $template = Get-P20StandupProseText ('prose' + $cap + 'Many')
        if (-not $template) { $template = Get-P20StandupProseText 'proseMany' }
        $body = Format-P20ProseTemplate $template @{ n = $n; name = $name; refs = $joined }
    }
    return (Format-P20ProseTemplate (Get-P20StandupProseText 'proseSentence') @{ lead = $lead; body = $body })
}

function Test-P20StandupProseFolds {
    <#
      Whether a slot's groups after its first are said as one sentence: the slot
      has a text.prose<Slot>Fold template and two or more groups follow the first.
    #>
    param([string]$Slot, $Groups)
    $cap = $Slot.Substring(0, 1).ToUpperInvariant() + $Slot.Substring(1)
    if (-not (Get-P20StandupProseText ('prose' + $cap + 'Fold'))) { return $false }
    return (@($Groups | Where-Object { $null -ne $_ }).Count -gt 2)
}

function Join-P20StandupFoldNames {
    <# The groups' names as a sentence says them: 'a, b and c'. #>
    param($Groups)
    $names = @($Groups | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.name })
    if ($names.Count -lt 2) { return ($names -join '') }
    $head = $names[0..($names.Count - 2)] -join (Get-P20StandupProseText 'proseNameSeparator')
    return $head + (Get-P20StandupProseText 'proseNameLast') + $names[$names.Count - 1]
}

function Get-P20StandupProseFoldSentence {
    <#
      The groups after a slot's first as ONE sentence: their count and, up to
      proseFoldNames of them, their names; no refs. Pure.
    #>
    param([string]$Slot, $Groups)
    $cap = $Slot.Substring(0, 1).ToUpperInvariant() + $Slot.Substring(1)
    $groups = @($Groups | Where-Object { $null -ne $_ })
    $n = Get-P20StandupCountWord $groups.Count
    if ($groups.Count -gt [int](Get-P20Consts).rituals.proseFoldNames) {
        $body = Format-P20ProseTemplate (Get-P20StandupProseText ('prose' + $cap + 'FoldCount')) @{ n = $n }
    }
    else {
        $body = Format-P20ProseTemplate (Get-P20StandupProseText ('prose' + $cap + 'Fold')) @{ n = $n; names = (Join-P20StandupFoldNames $groups) }
    }
    $lead = Get-P20StandupProseText ('prose' + $cap + 'Also')
    return (Format-P20ProseTemplate (Get-P20StandupProseText 'proseSentence') @{ lead = $lead; body = $body })
}

function Get-P20StandupProse {
    <#
      A slot's groups as its sentences, in the groups' order -- one a group, or the
      first and one fold sentence for the rest (Test-P20StandupProseFolds). Rows are
      the slot's entries (ref, title). Pure.
    #>
    param($Slot, $Groups, $Rows)
    $titles = @{}
    foreach ($r in @($Rows | Where-Object { $null -ne $_ })) { $titles[[string]$r.ref] = [string]$r.title }
    $groups = @($Groups | Where-Object { $null -ne $_ })
    $out = New-Object System.Collections.ArrayList
    if (Test-P20StandupProseFolds -Slot ([string]$Slot) -Groups $groups) {
        [void]$out.Add((Get-P20StandupProseSentence -Slot ([string]$Slot) -First $true -Group $groups[0] -Titles $titles))
        [void]$out.Add((Get-P20StandupProseFoldSentence -Slot ([string]$Slot) -Groups $groups[1..($groups.Count - 1)]))
        return [string[]]$out.ToArray()
    }
    $i = 0
    foreach ($g in $groups) {
        [void]$out.Add((Get-P20StandupProseSentence -Slot ([string]$Slot) -First ($i -eq 0) -Group $g -Titles $titles))
        $i++
    }
    return [string[]]$out.ToArray()  # unrolled: a slot with no groups says nothing
}

# -- The dress (D-SA11) -----------------------------------------------------
# A model may DRESS a worker's prose sentence in the standup register and never ADD
# a fact. Only the agent calls a model (agent/solitaire/standup.py, dress_standup);
# the CLI's Standup prints the prose, which is the floor and the fallback. The
# GUARD is the contract, so both halves implement it over one table,
# Tests/fixtures/rituals/standup-dress.json: a dressed sentence and its group's
# facts in, '' (it stands) or the first of rituals.dressGuards it fails out --
#
#   empty          blank, or more than one line
#   ref-added      a ref (dressRefRegex: #n, or a card-id-shaped word) not the group's
#   ref-dropped    a ref of the group the sentence does not say
#   number         a number (dressNumberRegex, or a numberWords word) that is not the
#                  count, a kind count, or a number in the facts' own words
#   count-dropped  a group of two or more whose count is not said
#   kind           a kind noun (ceremonies' standup.kinds) for a kind the group has
#                  none of, or after a number that is not that kind's count
#   name-dropped   the group's name not said (a group of one named by its own
#                  clause may re-say the clause)
#   name           a capitalised word (dressNameRegex) that is not sentence-initial,
#                  not the first person's I (dressPronounRegex), and not a word of
#                  the facts -- the worker's name, the group's, the titles, the prose
#
# A number glued to a unit ("20g of protein") is no number and a lowercase word is
# no name: the persona's colour is not checked, the work is. dress_guard in the
# agent is the same rule.

function Get-P20DressNumberValue {
    <# A word as a number: digits, or a numberWords word (ignoring case); else $null. #>
    param([string]$Token)
    if ([regex]::IsMatch($Token, '^\d+$')) {
        if ($Token.Length -gt 15) { return [long]-1 }  # past any count: never allowed
        return [long]$Token
    }
    $words = @((Get-P20Consts).rituals.numberWords)
    for ($i = 0; $i -lt $words.Count; $i++) {
        if ([string]::Equals([string]$words[$i], $Token, [System.StringComparison]::OrdinalIgnoreCase)) { return [long]$i }
    }
    return $null
}

function Get-P20DressNumbers {
    <# Every number a text says: standalone digits (dressNumberRegex) and numberWords words. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $rituals = (Get-P20Consts).rituals
    $out = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches([string]$Text, [string]$rituals.dressNumberRegex)) {
        $v = Get-P20DressNumberValue $m.Value
        if ($null -ne $v) { [void]$out.Add($v) }
    }
    $alts = (@(@($rituals.numberWords) | ForEach-Object { [regex]::Escape([string]$_) })) -join '|'
    $wordsRx = '(?<![\w''-])(?:' + $alts + ')(?![\w''-])'
    foreach ($m in [regex]::Matches([string]$Text, $wordsRx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $v = Get-P20DressNumberValue $m.Value
        if ($null -ne $v) { [void]$out.Add($v) }
    }
    return , ([long[]]$out.ToArray())
}

function Get-P20DressMap {
    <# A facts field that is a JSON object (titles, kinds) as an ordered name -> value map. #>
    param($Value)
    $map = [ordered]@{}
    if ($null -eq $Value) { return $map }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) { $map[[string]$k] = $Value[$k] }
        return $map
    }
    foreach ($p in $Value.PSObject.Properties) { $map[[string]$p.Name] = $p.Value }
    return $map
}

function Remove-P20DressPossessive {
    param([string]$Word)
    if ($Word.EndsWith("'s", [System.StringComparison]::Ordinal)) { return $Word.Substring(0, $Word.Length - 2) }
    return $Word
}

function Test-P20StandupDress {
    <#
      '' when a dressed sentence keeps every fact of its group and adds none;
      else the first of rituals.dressGuards it fails. Facts is one group:
      name, count, refs, titles (ref -> title), kinds (a kind's many noun ->
      count), worker, floor. Pure.
    #>
    param($Facts, [AllowEmptyString()][AllowNull()][string]$Sentence, [string]$PackageRoot)
    $rituals = (Get-P20Consts).rituals
    $s = [string]$Sentence
    if (-not $s.Trim() -or $s.Contains("`n") -or $s.Contains("`r")) { return 'empty' }

    $refs = @(@($Facts.refs) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    foreach ($m in [regex]::Matches($s, [string]$rituals.dressRefRegex)) {
        if ($refs -cnotcontains $m.Value) { return 'ref-added' }
    }
    foreach ($r in $refs) {
        if ($r.StartsWith('#')) { $pattern = [regex]::Escape($r) + '(?!\d)' }
        else { $pattern = '(?<![\w#])' + [regex]::Escape($r) + '(?!\w)' }
        if (-not [regex]::IsMatch($s, $pattern)) { return 'ref-dropped' }
    }

    $name = [string]$Facts.name
    $worker = [string]$Facts.worker
    $titles = Get-P20DressMap $Facts.titles
    $kinds = Get-P20DressMap $Facts.kinds
    $count = [long]$Facts.count
    $allowed = @{}
    $allowed[$count] = $true
    foreach ($k in $kinds.Keys) { $allowed[[long]$kinds[$k]] = $true }
    foreach ($r in $refs) {
        $digits = $r.TrimStart('#')
        if ([regex]::IsMatch($digits, '^\d+$')) { $allowed[(Get-P20DressNumberValue $digits)] = $true }
    }
    $known = @($name, $worker) + @($titles.Values | ForEach-Object { [string]$_ })
    foreach ($text in $known) {
        foreach ($n in (Get-P20DressNumbers $text)) { $allowed[$n] = $true }
    }
    $said = Get-P20DressNumbers $s
    foreach ($n in $said) { if (-not $allowed.ContainsKey($n)) { return 'number' } }
    if ($count -ge 2 -and ($said -notcontains $count)) { return 'count-dropped' }

    $data = Get-P20RitualData -PackageRoot $PackageRoot
    foreach ($kind in @($data.Ceremony.kinds)) {
        $nouns = '(?<![\w''-])(?:' + [regex]::Escape([string]$kind.many) + '|' + [regex]::Escape([string]$kind.one) + ')(?![\w''-])'
        $have = [long]0
        if ($kinds.Contains([string]$kind.many)) { $have = [long]$kinds[[string]$kind.many] }
        foreach ($m in [regex]::Matches($s, $nouns, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            if ($have -le 0) { return 'kind' }
            $tokens = @([regex]::Matches($s.Substring(0, $m.Index), "[A-Za-z0-9#'-]+") | ForEach-Object { $_.Value })
            $from = [Math]::Max(0, $tokens.Count - 3)
            for ($i = $tokens.Count - 1; $i -ge $from; $i--) {
                $v = Get-P20DressNumberValue $tokens[$i]
                if ($null -ne $v) {
                    if ($v -ne $have) { return 'kind' }
                    break
                }
            }
        }
    }

    $clause = ''
    if ($refs.Count -gt 0 -and $titles.Contains($refs[0])) { $clause = Get-P20StandupHead ([string]$titles[$refs[0]]) }
    elseif ($refs.Count -gt 0) { $clause = Get-P20StandupHead '' }
    $bare = ($count -eq 1 -and $refs.Count -eq 1 -and $name.ToLowerInvariant() -ceq $clause.ToLowerInvariant())
    if (-not $bare -and -not $s.ToLowerInvariant().Contains($name.ToLowerInvariant())) { return 'name-dropped' }

    $knownText = (@($name, $worker, [string]$Facts.floor) + @($titles.Values | ForEach-Object { [string]$_ })) -join ' '
    $words = @{}
    foreach ($w in [regex]::Matches($knownText, "[A-Za-z0-9'-]+")) { $words[(Remove-P20DressPossessive $w.Value).ToLowerInvariant()] = $true }
    foreach ($m in [regex]::Matches($s, [string]$rituals.dressNameRegex)) {
        $word = Remove-P20DressPossessive $m.Value
        if ([regex]::IsMatch($word, [string]$rituals.dressPronounRegex)) { continue }
        $before = [regex]::Replace($s.Substring(0, $m.Index), '[\s"''(]+$', '')
        if (-not $before -or '.!?:'.Contains($before.Substring($before.Length - 1))) { continue }
        if (-not $words.ContainsKey($word.ToLowerInvariant())) { return 'name' }
    }
    return ''
}

function New-P20StandupWorkEmpty {
    <# The work grain of a standup nothing filled: every queue kind empty, no workers. #>
    param([string[]]$QueueKinds)
    $queue = [ordered]@{}
    foreach ($kind in $QueueKinds) { $queue[$kind] = [object[]]@() }
    return [ordered]@{ queue = $queue; workers = [object[]]@(); queueProse = [object[]]@(); text = '' }
}

function Format-P20StandupWork {
    <#
      The filled object -> the work grain's text, spoken as prose:
      the same frame as the long form -- the title, the chair's lines, the
      Tracker line when nothing answered -- with ONE line for the queue (its
      sentences, or "Nothing is waiting on you.") and one per worker (its name,
      then its sentences):

        Waiting on you to walk two in Phase 6.
        <worker>: Yesterday I closed two in Team Agile. Nothing blocked.
        <worker>: "Nothing on the board for me. All green, no blockers."

      An empty slot says nothing; an empty worker is its status sentence. LF-joined,
      ending in one LF; every fixed word from rituals.text. Takes the fill's
      dictionary or the same shape read back from JSON. render_work in the
      agent is the same rule; the goldens standup-prose-<case>.txt are the law.
    #>
    param([Parameter(Mandatory)]$Standup, [string]$PackageRoot)
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $t = $data.Rituals.text
    $width = [int]$data.Rituals.labelWidth
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $at = ConvertTo-P20RitualTime $Standup.asOf
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add(([string]$t.title).Replace('{date}', $at.ToString([string]$t.dateFormat, $inv)))
    $lines.Add('"' + [string]$Standup.chair.open + '"')
    $lines.Add('')
    if (-not $Standup.tracker.ok) {
        $lines.Add('  ' + ([string]$t.tracker).PadRight($width) + '  ' + [string]$Standup.tracker.reason)
    }
    else {
        $said = @($Standup.work.queueProse | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        if ($said.Count -eq 0) { $lines.Add([string]$t.queueEmpty) }
        else { $lines.Add($said -join ' ') }
        $lines.Add('')

        $workers = @($Standup.workers | Where-Object { $null -ne $_ })
        if ($workers.Count -eq 0) { $lines.Add([string]$t.noWorkers) }
        $grained = @($Standup.work.workers | Where-Object { $null -ne $_ })
        foreach ($w in $workers) {
            if ($w.empty) { $lines.Add([string]$w.name + ': "' + [string]$w.excuse + '"'); continue }
            $ww = @($grained | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
            $said = @()
            if ($ww) { $said = @($ww.prose | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) }
            $lines.Add([string]$w.name + ': ' + ($said -join ' '))
        }
        $checks = @($Standup.checks | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        if ($checks.Count -gt 0) {
            $lines.Add('')
            foreach ($check in $checks) { $lines.Add([string]$t.check + ': ' + $check) }
        }
    }
    $lines.Add('')
    $lines.Add('"' + [string]$Standup.chair.close + '"')
    return (($lines -join "`n") + "`n")
}

function Get-P20StandupGrainText {
    <#
      The text a grain reads (rituals.grains): detail is the long form, work the
      work grain's, brief the chair's reading. $null for a grain that is not one.
    #>
    param([Parameter(Mandatory)]$Standup, [string]$Grain)
    $grains = @((Get-P20Consts).rituals.grains)
    if ($Grain -ceq [string]$grains[0]) { return [string]$Standup.text }
    if ($Grain -ceq [string]$grains[1]) { return [string]$Standup.work.text }
    if ($Grain -ceq [string]$grains[2]) { return [string]$Standup.brief }
    return $null
}

function Format-P20StandupText {
    <#
      The filled object -> the standup's text: LF-joined, ending in one LF, every
      fixed word from consts.json rituals.text, slot labels padded to labelWidth
      then two spaces. Takes the fill's dictionary or the same shape read back
      from JSON. The golden files in Tests/fixtures/rituals/ are the law.
    #>
    param([Parameter(Mandatory)]$Standup, [string]$PackageRoot)
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $t = $data.Rituals.text
    $width = [int]$data.Rituals.labelWidth
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $at = ConvertTo-P20RitualTime $Standup.asOf
    $lines = New-Object System.Collections.Generic.List[string]
    $row = { param($Label, $Value) '  ' + ([string]$Label).PadRight($width) + '  ' + $Value }

    $lines.Add(([string]$t.title).Replace('{date}', $at.ToString([string]$t.dateFormat, $inv)))
    $lines.Add('"' + [string]$Standup.chair.open + '"')
    $lines.Add('')

    if (-not $Standup.tracker.ok) {
        $lines.Add((& $row $t.tracker ([string]$Standup.tracker.reason)))
    }
    else {
        $lines.Add([string]$t.queueHeading)
        $any = $false
        foreach ($kind in @($data.Ceremony.queue)) {
            $label = [string]$t.$kind
            if (-not $label) { $label = [string]$kind }
            foreach ($item in @($Standup.queue.$kind)) {
                if ($null -eq $item) { continue }
                $any = $true
                $lines.Add((& $row $label ((Get-P20StandupItemRef $item) + ' ' + $item.title)))
            }
        }
        if (-not $any) { $lines.Add('  ' + [string]$t.queueEmpty) }
        $lines.Add('')

        $workers = @($Standup.workers | Where-Object { $null -ne $_ })
        if ($workers.Count -eq 0) { $lines.Add([string]$t.noWorkers) }
        foreach ($w in $workers) {
            $lines.Add([string]$w.name)
            if ($w.empty) {
                $lines.Add((& $row $t.mug ('"' + [string]$w.excuse + '"')))
                continue
            }
            foreach ($slot in @($data.Ceremony.slots)) {
                $label = [string]$t.$slot
                $items = @($w.$slot | Where-Object { $null -ne $_ })
                if ($items.Count -eq 0) {
                    $emptyKey = $slot + 'Empty'
                    $lines.Add((& $row $label ([string]$t.$emptyKey)))
                    continue
                }
                # The walk label's suffix, on a blocker -- which is exactly an
                # open item carrying the walk label.
                $suffix = ''
                if ($slot -eq 'blockers') { $suffix = [string]$t.blockerSuffix }
                foreach ($item in $items) {
                    # What moved, after the ref: "#143 (closed, 2 commits) Rename the slug".
                    $said = Get-P20StandupMotionText $item
                    if ($said) {
                        $body = Format-P20ProseTemplate ([string]$t.itemMotion) @{ ref = (Get-P20StandupItemRef $item); motion = $said; title = [string]$item.title }
                    }
                    else { $body = (Get-P20StandupItemRef $item) + ' ' + $item.title }
                    $lines.Add((& $row $label ($body + $suffix)))
                }
            }
        }
        # Where a card and its issue disagree: said, one line each, never fixed.
        $checks = @($Standup.checks | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        if ($checks.Count -gt 0) {
            $lines.Add('')
            foreach ($check in $checks) { $lines.Add((& $row $t.check $check)) }
        }
    }

    $lines.Add('')
    $lines.Add('"' + [string]$Standup.chair.close + '"')
    return (($lines -join "`n") + "`n")
}


# -- What moved ------------------------------------------------
# Every slot item carries its motion (rituals.motions: closed, started,
# inProgress) and its card's commits; a detail line says them after the ref
# (text.itemMotion), and the brief opens on the counts line (text.countsTotal):
# the window's first day and what moved in it, in total -- a hash once however
# many cards thread it. agent/solitaire/standup.py's motion_said, counts_said and
# render_counts are the same rule; the goldens hold the two to the byte.

function Get-P20StandupCommitsText {
    <# A commit count as the standup says it: text.commitOne or commitMany, in digits. #>
    param([int]$N)
    $t = (Get-P20Consts).rituals.text
    $template = [string]$t.commitMany
    if ($N -eq 1) { $template = [string]$t.commitOne }
    return $template.Replace('{n}', [string]$N)
}

function Get-P20StandupMotionText {
    <#
      An item's motion word, then its commits when it has any ("in progress, 3
      commits"); '' for an item that carries no motion (the queue's, or an older
      response's). motion_said in the agent.
    #>
    param($Item)
    $c = Get-P20Consts
    $t = $c.rituals.text
    $m = @($c.rituals.motions | ForEach-Object { [string]$_ })
    $mo = [string]$Item.motion
    $word = ''
    if ($mo -ceq $m[0]) { $word = [string]$t.motionClosed }
    elseif ($mo -ceq $m[1]) { $word = [string]$t.motionStarted }
    elseif ($mo -ceq $m[2]) { $word = [string]$t.motionInProgress }
    if (-not $word) { return '' }
    $n = 0
    if ($null -ne $Item.commits -and "$($Item.commits)" -ne '') { $n = [int]$Item.commits }
    if ($n -gt 0) { $word += [string]$t.countsSeparator + (Get-P20StandupCommitsText $n) }
    return $word
}

function Get-P20StandupCountsText {
    <# One count as its non-zero parts -- closed, started, in progress, commits -- joined, or text.countsNone. counts_said in the agent. #>
    param($Count)
    $t = (Get-P20Consts).rituals.text
    $bits = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(@('countsClosed', 'closed'), @('countsStarted', 'started'), @('countsInProgress', 'inProgress'))) {
        $n = 0
        if ($null -ne $Count) { $n = [int]$Count.($pair[1]) }
        if ($n -gt 0) { $bits.Add(([string]$t.($pair[0])).Replace('{n}', [string]$n)) }
    }
    $commits = 0
    if ($null -ne $Count) { $commits = [int]$Count.commits }
    if ($commits -gt 0) { $bits.Add((Get-P20StandupCommitsText $commits)) }
    if ($bits.Count -eq 0) { return [string]$t.countsNone }
    return ($bits -join [string]$t.countsSeparator)
}

function Format-P20StandupCounts {
    <#
      The counts line: the window's first day (since, in asOf's offset) and what
      moved in it, in total. The brief's first line. render_counts in the agent.
    #>
    param([Parameter(Mandatory)]$Standup)
    $t = (Get-P20Consts).rituals.text
    $at = ConvertTo-P20RitualTime $Standup.asOf
    $since = (ConvertTo-P20RitualTime $Standup.since).ToOffset($at.Offset)
    $total = $null
    if ($null -ne $Standup.counts) { $total = $Standup.counts.total }
    $date = $since.ToString([string]$t.dateFormat, [System.Globalization.CultureInfo]::InvariantCulture)
    return (Format-P20ProseTemplate ([string]$t.countsTotal) @{ date = $date; counts = (Get-P20StandupCountsText $total) })
}

function Format-P20StandupBrief {
    <#
      The chair's reading: the filled object -> a few lines, every one a count
      or a derived fact, no model. LF-joined, ending in one LF, every fixed word from
      consts.json rituals.text (the brief* keys, plus the queue heading and the
      blockersEmpty of the long form). Takes the fill's dictionary or the same shape
      read back from JSON; agent/solitaire/standup.py's render_brief is the same
      rule, and the goldens standup-<case>.brief.txt hold the two to the byte.

        Since Thursday 1 October 2026: 4 closed, 1 started, 6 in progress, 9 commits.
                                                   the counts line, first
        Waiting on you: 7 walks, all on <who>.     one line per queue kind with items
        <worker>: 4 closed yesterday, 6 open, none in flight, 1 blocker.
        In flight is not yet known: ...            one sentence, while it is unbuilt
        Next: the walks -- 7 on <who>.             the kind with the most items

      An issues Space says its walks are all on one machine (every walk there is a verify-close) and
      "none in flight"; a cards Space says neither, and its walks wait on "you". A
      both Space reads as an issues Space, except that a card on its walk puts the
      walks on "you", and its card tile (labelled with the Space's slug) does not
      say "none in flight"; its Check lines follow the workers.
      With tracker.ok false the brief is the Tracker line and nothing else.
    #>
    param([Parameter(Mandatory)]$Standup, [string]$PackageRoot)
    $data = Get-P20RitualData -PackageRoot $PackageRoot
    $t = $data.Rituals.text
    $lines = New-Object System.Collections.Generic.List[string]
    $fill = { param($Template, $N) ([string]$Template).Replace('{n}', [string]$N) }

    if (-not $Standup.tracker.ok) {
        return (([string]$t.tracker + ': ' + [string]$Standup.tracker.reason) + "`n")
    }
    $both = ([string]$Standup.source -ceq 'both')
    $issues = ([string]$Standup.source -ceq 'issues' -or $both)
    # The walks wait on the verifying machine only while every one is an issue (a verify-close).
    $onPc = $issues
    foreach ($i in @($Standup.queue.walk | Where-Object { $null -ne $_ })) {
        if ($null -eq $i.number -or "$($i.number)" -eq '') { $onPc = $false }
    }
    $who = [string]$t.briefWhoYou
    if ($onPc) { $who = [string]$t.briefWhoPc }
    # A window wider than yesterday (-Since) says a worker's closes without "yesterday".
    $at = ConvertTo-P20RitualTime $Standup.asOf
    $widened = ((ConvertTo-P20RitualTime $Standup.since) -ne (Get-P20StandupSince -AsOf $at))
    $counted = @{}
    if ($null -ne $Standup.counts) {
        foreach ($cw in @($Standup.counts.workers | Where-Object { $null -ne $_ })) { $counted[[string]$cw.label] = $cw }
    }
    # The counts line opens the reading: what moved in the window, in total.
    $lines.Add((Format-P20StandupCounts -Standup $Standup))

    # The queue: a line per kind that has items; the biggest kind is "next".
    $bestKind = ''
    $bestCount = 0
    foreach ($kind in @($data.Ceremony.queue)) {
        $count = @($Standup.queue.$kind | Where-Object { $null -ne $_ }).Count
        if ($count -eq 0) { continue }
        $cap = ([string]$kind).Substring(0, 1).ToUpperInvariant() + ([string]$kind).Substring(1)
        $manyKey = 'brief' + $cap + 'Many'
        $oneKey = 'brief' + $cap + 'One'
        $noun = [string]$t.$manyKey
        if ($count -eq 1) { $noun = [string]$t.$oneKey }
        $line = [string]$t.queueHeading + ': ' + $count + ' ' + $noun
        if ($onPc -and $kind -eq 'walk') { $line += ', ' + [string]$t.briefAllPc }
        $lines.Add($line + '.')
        if ($count -gt $bestCount) { $bestCount = $count; $bestKind = $noun }
    }
    if ($bestCount -eq 0) { $lines.Add([string]$t.queueEmpty) }

    $workers = @($Standup.workers | Where-Object { $null -ne $_ })
    foreach ($w in $workers) {
        if ($w.empty) { $lines.Add([string]$w.name + ': ' + [string]$t.briefWorkerNone + '.'); continue }
        $closed = @($w.yesterday | Where-Object { $null -ne $_ }).Count
        $blockers = @($w.blockers | Where-Object { $null -ne $_ }).Count
        $open = @($w.today | Where-Object { $null -ne $_ }).Count + $blockers
        $bits = @()
        $closedKey = 'briefClosed'
        $noneKey = 'briefClosedNone'
        if ($widened) { $closedKey = 'countsClosed'; $noneKey = 'yesterdayEmpty' }
        if ($closed -gt 0) { $bits += (& $fill $t.$closedKey $closed) } else { $bits += [string]$t.$noneKey }
        if ($open -gt 0) { $bits += (& $fill $t.briefOpen $open) } else { $bits += [string]$t.briefOpenNone }
        # What moved, the worker's own: how many of the open began in the window, and the commits.
        $mine = $counted[[string]$w.label]
        if ($null -ne $mine -and [int]$mine.started -gt 0) { $bits += (& $fill $t.countsStarted ([int]$mine.started)) }
        if ($null -ne $mine -and [int]$mine.commits -gt 0) { $bits += (Get-P20StandupCommitsText ([int]$mine.commits)) }
        if ($issues -and -not ($both -and [string]$w.label -ceq [string]$Standup.space)) { $bits += [string]$t.briefInFlight }
        if ($blockers -gt 1) { $bits += (& $fill $t.briefBlockers $blockers) }
        elseif ($blockers -eq 1) { $bits += (& $fill $t.briefBlocker $blockers) }
        else { $bits += [string]$t.blockersEmpty }
        $lines.Add([string]$w.name + ': ' + ($bits -join ', ') + '.')
    }
    if ($workers.Count -eq 0) { $lines.Add([string]$t.noWorkers) }
    elseif ($issues) { $lines.Add([string]$t.briefInFlightUnknown) }
    foreach ($check in @($Standup.checks | Where-Object { $null -ne $_ })) { $lines.Add([string]$t.check + ': ' + [string]$check) }

    if ($bestCount -eq 0) { $lines.Add([string]$t.briefNextNone) }
    else { $lines.Add(([string]$t.briefNext).Replace('{kind}', $bestKind).Replace('{n}', [string]$bestCount).Replace('{who}', $who)) }
    return (($lines -join "`n") + "`n")
}
