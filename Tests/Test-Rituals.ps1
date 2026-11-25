<#
.SYNOPSIS
    Solitaire Agile's Ritual Engine -- the standup's slot rule over the shared
    table, the golden texts byte for byte, and the verb typed in a fresh shell.

.DESCRIPTION
    1. The table     Tests/fixtures/rituals/standup.json, every case: since, the
                     day of the year, the chair's two lines, the queue, each
                     worker's slots by issue number, empty and its two made-up
                     items (status, and excuse its first) -- the
                     same table Tests/test_rituals.py asserts against the agent.
    2. The goldens   the rendered text against standup-<name>.txt, byte for byte
                     (LF), wherever a case names one; every case rendered again
                     from its own JSON round trip.
    2a. Both         Tests/fixtures/rituals/standup-joined.json: an active
                     GitHub Space's issues and cards joined on the id -- every
                     shape's walk, each worker's slots by ref, the Check lines
                     and the links, and the together case's detail, work and
                     brief against standup-joined-together*.txt, byte for byte,
                     again after a JSON round trip; typed, a GitHub Space with
                     cards in its folder prints the joined standup. What moved
                    : each item's motion and commits, the counts per
                     worker and in total, the counts and window cases' goldens;
                     typed, Standup -Since and its refusals.
    2b. The work grain  Tests/fixtures/rituals/standup-work.json: every
                     group of the queue and of each worker's slots, the small
                     tables, the work text against standup-work-<name>.txt --
                     the same rows Tests/test_rituals.py asserts; and typed,
                     Standup -Grain work|detail|brief and its two refusals.
    2c. The prose    Tests/fixtures/rituals/standup-prose.json: every
                     sentence row (one group as one sentence), every fold row
                     (today's also-ons as one sentence, D-SA9), every unsaid row
                     (a slot's fixed line, or the refs worked in the window) and
                     itemWorked row, and every case's
                     queue sentences, each worker's sentences and the work text
                     against standup-prose-<name>.txt, byte for byte, again
                     after a JSON round trip -- the same rows the agent asserts.
    2c''. The model  Tests/fixtures/rituals/standup-sessions.json: every
                     lookup row of the model object -- an id and a session id
                     in, {id, sessionId, name, family, known} or none out, a
                     known row's name and family the shipped map's own row --
                     the rows the agent asserts.
    2c'''. Sessions  the same file's inside, porcelain, sessions and privacy
                     rows: the path rule, the worktree list's parse, and the
                     session reader over a scratch projects folder per row --
                     {id, sessionId} pairs and nothing else, the folder left
                     as it was; one git worktree list per read in a scratch
                     repository; nothing calls the reader yet.
    2c''''. Seats    the same file's seats rows: an org.json through the org
                     chart's own reader, a Space slug and Team Agile in, the
                     Space's seats as model objects out, in the chart's order;
                     no machine or person in the output; no caller yet.
    2c'. The team    Tests/fixtures/rituals/standup-team.json: every size
                     row (a stored teamSize read as the room), every seat row
                     (who is present: the ones with work first, then the idle),
                     and every case's team.size, present flags and detail, work
                     and brief against standup-team-<name>*.txt -- the rows the
                     agent asserts; typed, teamSize=3 in the hub keeps every
                     worker and speaks the present only. The room's rules over
                     every room row and every case: the size seen is the size
                     picked, everyone speaks (an idle member its made-up pair),
                     the desks are past the size, the engineer sits; and a day
                     with no work is a case at every size.
    2d. The dress    Tests/fixtures/rituals/standup-dress.json: every
                     row of the dress guard (a dressed sentence and its group's
                     facts in, kept or the guard it fails out), every group's
                     prose sentence passing its own guard, every guard of
                     rituals.dressGuards with a row, and a reply naming a number that is not in the read
                     keeping the prose for that group -- the rows the agent
                     asserts. Only the agent calls a model.
    3. No fake work  the real register never reads the vocabulary's fakeWork
                     family (D-SA5): every case's text is grepped for it. And no
                     nothing line claims tracker work: none holds a word of
                     standup-nothing-banned.json, the list the agent's suite reads;
                     the family has more than one line and none twice.
    4. Off           with features.solitaireAgile unset there is no verb, no menu
                     line and nothing for the bridge to call.
    5. The verb      Standup typed in a fresh shell -- the package's own manifest
                     imported by path, the flag on in a scratch config.local.json
                     -- with gh stubbed as a function answering the friday case:
                     the text the rule renders for now, -AsJson round-tripping to
                     the same text, the Tracker line when gh does not answer or
                     the Space is not GitHub (exit 0 -- the ritual happens anyway),
                     an undeclared -Space a stated refusal, and the hub untouched.

    Run:  pwsh -File Tests/Test-Rituals.ps1
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path -Parent $scriptDir

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $Name"
        if ($Detail) { $msg += " -- $Detail" }
        Write-Host $msg -ForegroundColor Red
        $script:errors += $msg
    }
}

function Get-Numbers {
    # A slot's issue numbers, in order, as one comparable string.
    param($Items)
    return ((@($Items | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_.number })) -join ',')
}

Write-Host ""
Write-Host "  Rituals -- Team Agile's standup" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
. (Join-Path $pkgRoot 'Scripts/Standup-Rules.ps1')
$consts = Get-P20Consts
$data = Get-P20RitualData -PackageRoot $pkgRoot
$phrases = @($data.Vocabulary.phrasebook)
$nothing = @($data.Vocabulary.nothing)
$nothingToday = @($data.Vocabulary.nothingToday)
$excuses = @($data.Vocabulary.excuses)
$fakeWork = @($data.Vocabulary.fakeWork)

# An idle worker's two made-up items from a fixture row's two indexes, as one
# comparable string: 'excuse | yesterday | today', or ' | ' parts empty for a
# worker with something to say. The same string is built from what the fill wrote.
$idleWant = {
    param($Row)
    # A row with no first index has no second either; one that does fails here.
    if ($null -eq $Row.nothingIndex) { return ' || ' + "$($Row.nothingTodayIndex)" }
    $y = [string]$nothing[[int]$Row.nothingIndex]
    $t = [string]$nothingToday[[int]$Row.nothingTodayIndex]
    return "$y | $y | $t"
}
$idleGot = {
    param($W)
    $pair = @($W.status | Where-Object { $null -ne $_ })
    if ($pair.Count -eq 0) { return ([string]$W.excuse) + ' || ' }
    return ([string]$W.excuse) + ' | ' + ((@($pair | ForEach-Object { [string]$_ })) -join ' | ')
}
$idleSays = {
    param($Row)
    if ($null -eq $Row.nothingIndex) { return 'says no made-up item (excuse empty, status empty)' }
    return "says nothing[$($Row.nothingIndex)] and nothingToday[$($Row.nothingTodayIndex)], excuse the first"
}
# A filled worker's two indexes, as a fixture row of standup-joined.json states them.
$idleIndexes = {
    param($W)
    $pair = @($W.status | Where-Object { $null -ne $_ })
    if ($pair.Count -eq 0) { return 'null/null' }
    return "$([array]::IndexOf($nothing, [string]$pair[0]))/$([array]::IndexOf($nothingToday, [string]$pair[1]))"
}

$fixtureDir = Join-Path $scriptDir 'fixtures/rituals'
$fixturePath = Join-Path $fixtureDir 'standup.json'
$fixtureRaw = [System.IO.File]::ReadAllText($fixturePath)
$fixture = $fixtureRaw | ConvertFrom-Json
$cases = @($fixture.cases)

# PowerShell 7's ConvertFrom-Json turns an ISO string into a [datetime] in the
# MACHINE's zone, which keeps the instant and loses the offset -- and asOf's
# offset is what decides the local midnight and the date line. So the two
# offset-bearing strings the table states are read from the raw text, in case
# order: one asOf per case, one expected since per case.
$asOfTexts = @([regex]::Matches($fixtureRaw, '"asOf"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$sinceTexts = @([regex]::Matches($fixtureRaw, '"since"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'the table is read: five cases, an asOf and a since each' ($cases.Count -eq 5 -and $asOfTexts.Count -eq $cases.Count -and $sinceTexts.Count -eq $cases.Count) "$($cases.Count) cases, $($asOfTexts.Count) asOf, $($sinceTexts.Count) since"

# -- 1. The table, 2. the goldens, 3. no fake work ------------------------------
$rendered = @{}
for ($n = 0; $n -lt $cases.Count; $n++) {
    $case = $cases[$n]
    $name = [string]$case.name
    $exp = $case.expected
    Write-Host ""
    Write-Host "-- $name --" -ForegroundColor Cyan

    $labels = $case.labels
    if ($labels -is [string]) { $labels = $fixture.($labels) }
    $s = Invoke-P20StandupFill -AsOf $asOfTexts[$n] -Labels @($labels) -Issues @($case.issues) -Tracker $case.tracker -PackageRoot $pkgRoot

    Assert-True "${name}: since is the previous working day's local midnight" ($s.since -eq $sinceTexts[$n]) "got $($s.since), want $($sinceTexts[$n])"
    $doy = (ConvertTo-P20RitualTime $asOfTexts[$n]).DayOfYear
    Assert-True "${name}: day of the year" ($doy -eq [int]$exp.dayOfYear) "got $doy, want $($exp.dayOfYear)"
    Assert-True "${name}: the chair opens on phrasebook[$($exp.chair.openIndex)]" ($s.chair.open -ceq $phrases[[int]$exp.chair.openIndex]) "got '$($s.chair.open)'"
    Assert-True "${name}: and closes on phrasebook[$($exp.chair.closeIndex)]" ($s.chair.close -ceq $phrases[[int]$exp.chair.closeIndex]) "got '$($s.chair.close)'"
    foreach ($kind in @('walk', 'decide', 'look')) {
        $want = (@($exp.queue.$kind | ForEach-Object { [int]$_ })) -join ','
        $got = Get-Numbers $s.queue.$kind
        Assert-True "${name}: queue.$kind is [$want]" ($got -eq $want) "got [$got]"
    }
    Assert-True "${name}: the tracker is passed through" ([bool]$s.tracker.ok -eq [bool]$case.tracker.ok -and $s.tracker.reason -ceq [string]$case.tracker.reason) "$($s.tracker.ok) '$($s.tracker.reason)'"

    $wantWorkers = @($exp.workers)
    $gotWorkers = @($s.workers)
    Assert-True "${name}: $($wantWorkers.Count) workers, in label order" ($gotWorkers.Count -eq $wantWorkers.Count -and ((@($gotWorkers | ForEach-Object { $_.label })) -join ',') -eq ((@($wantWorkers | ForEach-Object { $_.label })) -join ',')) ((@($gotWorkers | ForEach-Object { $_.label })) -join ',')
    for ($i = 0; $i -lt [Math]::Min($gotWorkers.Count, $wantWorkers.Count); $i++) {
        $g = $gotWorkers[$i]
        $w = $wantWorkers[$i]
        Assert-True "${name}: $($w.label) is named $($w.name), from the label's description" ($g.name -ceq [string]$w.name) "got '$($g.name)'"
        foreach ($slot in @('yesterday', 'today', 'blockers')) {
            $want = (@($w.$slot | ForEach-Object { [int]$_ })) -join ','
            $got = Get-Numbers $g.$slot
            Assert-True "${name}: $($w.label).$slot is [$want]" ($got -eq $want) "got [$got]"
        }
        Assert-True "${name}: $($w.label).empty is $($w.empty)" ([bool]$g.empty -eq [bool]$w.empty)
        $want = & $idleWant $w
        $got = & $idleGot $g
        Assert-True "${name}: $($w.label) $(& $idleSays $w)" ($got -ceq $want) "got '$got', want '$want'"
    }

    $text = Format-P20StandupText -Standup $s -PackageRoot $pkgRoot
    $rendered[$name] = $text
    $brief = Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot
    Assert-True "${name}: the brief is LF only and ends in one LF" (-not $brief.Contains("`r") -and $brief.EndsWith("`n") -and -not $brief.EndsWith("`n`n"))
    $goldenBrief = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.brief)))
    Assert-True "${name}: the brief is $($exp.brief), byte for byte" ($brief -ceq $goldenBrief) ("`n--- got ---`n$brief--- want ---`n$goldenBrief")
    Assert-True "${name}: the text is LF only and ends in one LF" (-not $text.Contains("`r") -and $text.EndsWith("`n") -and -not $text.EndsWith("`n`n"))
    if ($exp.text) {
        $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
        Assert-True "${name}: the text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    }

    # The same object read back from JSON renders the same text: what -AsJson
    # prints is enough for a reader to draw it. asOf is put back as the string
    # it was (see the note above on 7's ConvertFrom-Json).
    $back = ($s | ConvertTo-Json -Depth 8) | ConvertFrom-Json
    $back.asOf = $s.asOf
    $again = Format-P20StandupText -Standup $back -PackageRoot $pkgRoot
    Assert-True "${name}: the JSON round trip renders the same text" ($again -ceq $text) $again

    foreach ($fake in $fakeWork) {
        if ($text.Contains([string]$fake)) {
            Assert-True "${name}: no fakeWork line in the real register" $false "found '$fake'"
        }
    }
    Assert-True "${name}: no fakeWork line in the real register ($($fakeWork.Count) checked)" (@($fakeWork | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
    Assert-True "${name}: no excuses line in the real register ($($excuses.Count) checked)" (@($excuses | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
}
Assert-True 'the vocabulary has an excuses family (the nonsense register''s) and nothing and nothingToday families (the empty worker''s)' ($excuses.Count -gt 0 -and $nothing.Count -gt 0 -and $nothingToday.Count -gt 0)
Assert-True 'the vocabulary has a fakeWork family to grep for' ($fakeWork.Count -gt 0)

# A nothing line is the day around the work and claims NO TRACKER WORK -- no word of
# standup-nothing-banned.json, whole word, any case; the same list Tests/test_rituals.py reads.
# fix/fixed is not on it on purpose ("Fixed my standing desk"); a fix to code is a bug, a
# commit or a pull request, which are.
$bannedRaw = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-nothing-banned.json'), [System.Text.Encoding]::UTF8)
$banned = @(($bannedRaw | ConvertFrom-Json).words | ForEach-Object { [string]$_ })
$trackerWord = {
    param([string]$Line)
    foreach ($word in $banned) {
        $pattern = '\b' + ((@($word -split '\s+') | ForEach-Object { [regex]::Escape($_) }) -join '\s+') + '\b'
        if ([regex]::IsMatch($Line, $pattern, [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant')) { return $word }
    }
    return ''
}
Assert-True "the tracker-word list has words ($($banned.Count))" ($banned.Count -gt 0)
foreach ($family in @('nothing', 'nothingToday')) {
    $lines = @($data.Vocabulary.$family)
    Assert-True "the $family family has more than one line ($($lines.Count)), so two idle workers say different lines" ($lines.Count -gt 1)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $twice = @($lines | Where-Object { -not $seen.Add([string]$_) })
    Assert-True "no $family line appears twice" ($twice.Count -eq 0) ($twice -join ' | ')
    foreach ($line in $lines) {
        $hit = & $trackerWord ([string]$line)
        Assert-True "no tracker work in the $family line '$line'" ($hit -eq '') "says '$hit'"
    }
}
# A worker's yesterday and today are two different items: no sentence is in both
# families, and their lengths share no factor, so the pair does not repeat in step.
$yesterdaySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($line in $nothing) { [void]$yesterdaySet.Add([string]$line) }
$inBoth = @($nothingToday | Where-Object { $yesterdaySet.Contains([string]$_) })
Assert-True 'no sentence is in both the nothing and the nothingToday family' ($inBoth.Count -eq 0) ($inBoth -join ' | ')
$ga = $nothing.Count
$gb = $nothingToday.Count
while ($gb -ne 0) { $gr = $ga % $gb; $ga = $gb; $gb = $gr }
Assert-True "the two families' lengths ($($nothing.Count), $($nothingToday.Count)) share no factor, so they never run in step" ($ga -eq 1) "their greatest common divisor is $ga"
foreach ($line in @('Opened a PR.', 'Went over the  Pull  Request.', 'Two cards moved.', 'Ran the tests.')) {
    Assert-True "the tracker-word guard catches '$line'" ((& $trackerWord $line) -ne '')
}
foreach ($line in @('Fixed my standing desk.', 'Fixed my PATH.', 'Read the protest notes.', 'Carded nothing.')) {
    Assert-True "the tracker-word guard passes '$line'" ((& $trackerWord $line) -eq '')
}

# A few rows the table implies, said in words.
Write-Host ""
Write-Host "-- The rule, said in words --" -ForegroundColor Cyan
Assert-True 'Friday''s since is Thursday' ((Get-P20StandupSince -AsOf ([DateTimeOffset]::Parse('2026-10-02T09:00:00-04:00', [System.Globalization.CultureInfo]::InvariantCulture))).DayOfWeek -eq [DayOfWeek]::Thursday)
Assert-True 'Sunday''s since is Friday' ((Get-P20StandupSince -AsOf ([DateTimeOffset]::Parse('2026-10-04T23:00:00-04:00', [System.Globalization.CultureInfo]::InvariantCulture))).DayOfWeek -eq [DayOfWeek]::Friday)
Assert-True 'the window keeps asOf''s own offset' ((Get-P20StandupSince -AsOf ([DateTimeOffset]::Parse('2026-10-06T09:00:00+09:00', [System.Globalization.CultureInfo]::InvariantCulture))).Offset.TotalHours -eq 9)
$w = @(Get-P20StandupWorkers -Labels @(
        [pscustomobject]@{ name = 'zeta'; description = "$($consts.rituals.workerLabelPrefix) Zed" },
        [pscustomobject]@{ name = 'Alpha'; description = "$($consts.rituals.workerLabelPrefix)   Al   -- the first" },
        [pscustomobject]@{ name = 'other'; description = "Not $($consts.rituals.workerLabelPrefix) anyone" }
    ) -Prefix $consts.rituals.workerLabelPrefix)
Assert-True 'a worker is a label whose description STARTS with the prefix, ordered by label name' (((@($w | ForEach-Object { $_.label })) -join ',') -ceq 'Alpha,zeta') ((@($w | ForEach-Object { $_.label })) -join ',')
Assert-True 'its name is the text after the prefix, up to the separator, trimmed' (((@($w | ForEach-Object { $_.name })) -join ',') -ceq 'Al,Zed') ((@($w | ForEach-Object { $_.name })) -join ',')
$mixed = Invoke-P20StandupFill -AsOf '2026-10-02T09:00:00-04:00' -Tracker @{ ok = $true; reason = '' } -PackageRoot $pkgRoot `
    -Labels @([pscustomobject]@{ name = 'opus'; description = "$($consts.rituals.workerLabelPrefix) Opus" }, [pscustomobject]@{ name = 'fable'; description = "$($consts.rituals.workerLabelPrefix) Fable" }) `
    -Issues @([pscustomobject]@{ number = 9; title = 't'; state = 'OPEN'; labels = @([pscustomobject]@{ name = 'opus' }, [pscustomobject]@{ name = 'fable' }); closedAt = $null; url = 'u' })
Assert-True 'an issue''s worker is its FIRST worker label, and gh''s label objects read like the fixture''s strings' ((Get-Numbers @($mixed.workers | Where-Object { $_.label -eq 'opus' })[0].today) -eq '9' -and (Get-Numbers @($mixed.workers | Where-Object { $_.label -eq 'fable' })[0].today) -eq '')

# -- 1b. The second source: cards ----------------------------------------
# Tests/fixtures/rituals/standup-cards.json, every case, against the SAME table
# Tests/test_rituals.py asserts: the card rows in, the one worker's slots and the
# walk queue out BY CARD ID, and standup-cards-<name>.txt byte for byte.
function Get-Ids {
    # A slot's card ids, in order, as one comparable string.
    param($Items)
    return ((@($Items | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })) -join ',')
}

$cardsPath = Join-Path $fixtureDir 'standup-cards.json'
$cardsRaw = [System.IO.File]::ReadAllText($cardsPath)
$cardsTable = $cardsRaw | ConvertFrom-Json
$cardCases = @($cardsTable.cases)
$cardAsOf = @([regex]::Matches($cardsRaw, '"asOf"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$cardSince = @([regex]::Matches($cardsRaw, '"since"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'the cards table is read: four cases, an asOf and a since each' ($cardCases.Count -eq 4 -and $cardAsOf.Count -eq 4 -and $cardSince.Count -eq 4) "$($cardCases.Count) cases, $($cardAsOf.Count) asOf, $($cardSince.Count) since"

for ($n = 0; $n -lt $cardCases.Count; $n++) {
    $case = $cardCases[$n]
    $name = 'cards-' + [string]$case.name
    $exp = $case.expected
    Write-Host ""
    Write-Host "-- $name --" -ForegroundColor Cyan

    $s = Invoke-P20StandupCardsFill -AsOf $cardAsOf[$n] -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot
    Assert-True "${name}: since is the previous working day's local midnight" ($s.since -eq $cardSince[$n]) "got $($s.since), want $($cardSince[$n])"
    $doy = (ConvertTo-P20RitualTime $cardAsOf[$n]).DayOfYear
    Assert-True "${name}: day of the year" ($doy -eq [int]$exp.dayOfYear) "got $doy, want $($exp.dayOfYear)"
    Assert-True "${name}: the chair opens on phrasebook[$($exp.chair.openIndex)] and closes on phrasebook[$($exp.chair.closeIndex)]" ($s.chair.open -ceq $phrases[[int]$exp.chair.openIndex] -and $s.chair.close -ceq $phrases[[int]$exp.chair.closeIndex]) "got '$($s.chair.open)' / '$($s.chair.close)'"
    Assert-True "${name}: source is cards, and the hub answered" ($s.source -ceq 'cards' -and [bool]$s.tracker.ok -and $s.tracker.reason -ceq '') "$($s.source) $($s.tracker.ok) '$($s.tracker.reason)'"
    foreach ($kind in @('walk', 'decide', 'look')) {
        $want = (@($exp.queue.$kind | ForEach-Object { [string]$_ })) -join ','
        $got = Get-Ids $s.queue.$kind
        Assert-True "${name}: queue.$kind is [$want]" ($got -ceq $want) "got [$got]"
    }
    $walkOk = $true
    foreach ($item in @($s.queue.walk)) { if ($null -ne $item.number -or $item.worker -cne [string]$exp.worker.name) { $walkOk = $false } }
    Assert-True "${name}: a walk item has no number and names the Space's one worker" $walkOk

    $ws = @($s.workers)
    $w = $exp.worker
    Assert-True "${name}: ONE worker, $($w.label) named '$($w.name)'" ($ws.Count -eq 1 -and $ws[0].label -ceq [string]$w.label -and $ws[0].name -ceq [string]$w.name) ((@($ws | ForEach-Object { "$($_.label)/$($_.name)" })) -join ',')
    if ($ws.Count -eq 1) {
        foreach ($slot in @('yesterday', 'today', 'blockers')) {
            $want = (@($w.$slot | ForEach-Object { [string]$_ })) -join ','
            $got = Get-Ids $ws[0].$slot
            Assert-True "${name}: $slot is [$want]" ($got -ceq $want) "got [$got]"
        }
        Assert-True "${name}: empty is $($w.empty)" ([bool]$ws[0].empty -eq [bool]$w.empty)
        $want = & $idleWant $w
        $got = & $idleGot $ws[0]
        Assert-True "${name}: the worker $(& $idleSays $w)" ($got -ceq $want) "got '$got', want '$want'"
    }

    $brief = Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot
    $goldenBrief = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.brief)))
    Assert-True "${name}: the brief is $($exp.brief), byte for byte" ($brief -ceq $goldenBrief) ("`n--- got ---`n$brief--- want ---`n$goldenBrief")
    $text = Format-P20StandupText -Standup $s -PackageRoot $pkgRoot
    Assert-True "${name}: the text is LF only and ends in one LF" (-not $text.Contains("`r") -and $text.EndsWith("`n") -and -not $text.EndsWith("`n`n"))
    if ($exp.text) {
        $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
        Assert-True "${name}: the text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    }
    $back = ($s | ConvertTo-Json -Depth 8) | ConvertFrom-Json
    $back.asOf = $s.asOf
    $back.since = $s.since
    $again = Format-P20StandupText -Standup $back -PackageRoot $pkgRoot
    Assert-True "${name}: the JSON round trip renders the same text" ($again -ceq $text) $again
    Assert-True "${name}: no fakeWork line in the real register ($($fakeWork.Count) checked)" (@($fakeWork | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
}

$friday = Invoke-P20StandupCardsFill -AsOf $cardAsOf[0] -Cards @($cardCases[0].cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
$first = @($friday.workers)[0].yesterday[0]
Assert-True 'a card item has an id and a path, and no number and no url' ($null -eq $first.number -and $first.id -ceq '198' -and $first.url -ceq '' -and $first.path -ceq 'archive/198-fix-the-export.prompt.md') "$($first.number) $($first.id) '$($first.url)' $($first.path)"
Assert-True 'its keys are the seven every item has' (((@($first.Keys)) -join ',') -ceq 'number,id,title,url,path,motion,commits') ((@($first.Keys)) -join ',')

Write-Host ""
Write-Host "-- Which source a Space chooses --" -ForegroundColor Cyan
foreach ($row in @($cardsTable.sources)) {
    $got = Get-P20StandupSource -Address ([string]$row.address) -Status ([string]$row.status)
    $wantReason = ''
    if ($row.reason) { $wantReason = [string]$consts.rituals.text.([string]$row.reason) }
    Assert-True "'$($row.address)' $($row.status) -> $($row.source)" ($got.source -ceq [string]$row.source -and $got.reason -ceq $wantReason) "got $($got.source) '$($got.reason)'"
}

Write-Host ""
Write-Host "-- Why the tracker was not read --" -ForegroundColor Cyan
# Tests/fixtures/rituals/tracker-reasons.json, the SAME rows Tests/test_rituals.py
# asserts: every reason's Tracker line from its rituals.text key, and the readers
# that word it -- Invoke-P20RitualGh over a stubbed gh, Get-P20TrackerRepoReason
# over Resolve-P20TrackerRepo's refusal. The stub lives in this block's scope only.
$reasonsTable = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'tracker-reasons.json')) | ConvertFrom-Json
& {
    . (Join-Path $pkgRoot 'Scripts/Ritual-Common.ps1')
    $ghAnswer = @{ row = $null }
    function Invoke-P20TrackerRead {
        param([string]$Tool, [string[]]$Arguments)
        $g = $ghAnswer.row.gh
        if ($g.PSObject.Properties['raises']) { throw ([string]$g.raises) }
        $err = @(([string]$g.stderr) -split "`n" | Where-Object { $_ })
        return [PSCustomObject]@{ Code = [int]$g.exit; Lines = @(); Out = @([string]$g.stdout); Err = $err }
    }
    $textKeys = @($consts.rituals.text.PSObject.Properties | Where-Object { $_.Name -cmatch '^tracker[A-Z]' -or $_.Name -ceq 'adoTracker' } | ForEach-Object { $_.Name } | Sort-Object)
    $rowKeys = @($reasonsTable.rows | ForEach-Object { [string]$_.key } | Sort-Object -Unique)
    Assert-True 'reasons: every tracker key of rituals.text has a row, and every row a key' (($textKeys -join ',') -ceq ($rowKeys -join ',')) "keys [$($textKeys -join ',')] rows [$($rowKeys -join ',')]"
    foreach ($row in @($reasonsTable.rows)) {
        $values = @{}
        foreach ($v in @($row.values.PSObject.Properties)) { $values[$v.Name] = $v.Value }
        $said = Format-P20TrackerReason -Key ([string]$row.key) -Values $values
        Assert-True "reasons $($row.reason): $($row.key) says the line" ($said -ceq [string]$row.line) "got '$said'"
        if ($row.PSObject.Properties['gh'] -and @($row.halves) -contains 'cli') {
            $ghAnswer.row = $row
            $got = Invoke-P20RitualGh -Repo ([string]$reasonsTable.repo) -Arguments @('label', 'list')
            Assert-True "reasons $($row.reason): the gh read says it" (-not $got.ok -and [string]$got.reason -ceq [string]$row.line) "got '$($got.reason)'"
        }
        if ($row.PSObject.Properties['target'] -and @($row.halves) -contains 'cli') {
            $projects = @($row.target.repos | ForEach-Object { [pscustomobject]@{ repo = [string]$_ } })
            $target = Resolve-P20TrackerRepo -OrgUrl ([string]$row.target.org) -Projects $projects
            $got = Get-P20TrackerRepoReason -Target $target
            Assert-True "reasons $($row.reason): the repository rule says it" ($got -ceq [string]$row.line) "got '$got'"
        }
    }
    $ado = @($reasonsTable.rows | Where-Object { $_.reason -ceq 'ado' })[0]
    $src = Get-P20StandupSource -Address 'https://dev.azure.com/acme-org' -Status 'active'
    Assert-True 'reasons ado: the source rule says it' ($src.reason -ceq [string]$ado.line) "got '$($src.reason)'"
    $repoTarget = Resolve-P20TrackerRepo -OrgUrl 'https://github.com/acme/widgets' -Projects @()
    Assert-True 'reasons: a Space that names its repository has no reason' ((Get-P20TrackerRepoReason -Target $repoTarget) -ceq '') "got '$(Get-P20TrackerRepoReason -Target $repoTarget)'"
}

Write-Host ""
Write-Host "-- A card's title from its heading --" -ForegroundColor Cyan
foreach ($row in @($cardsTable.titles)) {
    $got = Get-P20StandupCardTitle -Content ([string]$row.content) -File ([string]$row.file) -Id ([string]$row.id)
    Assert-True "$($row.file) -> '$($row.title)'" ($got -ceq [string]$row.title) "got '$got'"
}

Write-Host ""
Write-Host "-- The card reader, over real folders --" -ForegroundColor Cyan
$readerDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-standup-cards-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $utf8r = New-Object System.Text.UTF8Encoding($false)
    New-Item -ItemType Directory -Path (Join-Path $readerDir 'current'), (Join-Path $readerDir 'archive'), (Join-Path $readerDir 'backlog') -Force | Out-Null
    $readerFiles = [ordered]@{
        # A planned card: backlog/ is beside current/, and the standup never reads it.
        'backlog/Task9QHT-a-planned-card.prompt.md'  = "# Task 9QHT: A planned card`n`n**Created:** 2026-10-01`n"
        'current/K7M2-wire-the-board.prompt.md'      = "# Task K7M2: Wire the board`n`n- [x] a`n"
        'current/Task139-write-the-docs.prompt.md'   = "# Task 139: Write the docs`n`n- a41c2e9 first`n"
        'current/US-144-read-the-board.prompt.md'    = "# User Story 144: Read the board`r`n`r`nPR URL: https://example.com/pr/1`r`n"
        'current/notes.md'                           = "# Just a note`n"
        'current/.hidden.prompt.md'                  = "# Hidden`n"
        'archive/198-fix-the-export.prompt.md'       = "# Bug 198: Fix the export`n`n**Closed:** 2026-10-01`n"
        'archive/151-never-stamped.prompt.md'        = "# Bug 151: Never stamped`n"
        'archive/2026-05-14-PR141415.prompt.md'      = "# PR comments`n`n**Closed:** 2026-10-01`n"
        'archive/160-off-the-clock.prompt.md'        = "# Bug 160: Off the clock`n`n**Billable:** no`n**Closed:** 2026-10-01`n"
    }
    foreach ($k in $readerFiles.Keys) { [System.IO.File]::WriteAllText((Join-Path $readerDir $k), $readerFiles[$k], $utf8r) }
    $pattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $null)
    $rows = @(Get-P20StandupCards -CurrentDir (Join-Path $readerDir 'current') -ArchiveDir (Join-Path $readerDir 'archive') -Pattern $pattern)
    $offClock = (@($rows | Where-Object { -not $_.billable } | ForEach-Object { $_.file })) -join ','
    Assert-True 'Get-P20StandupCards: a card that says **Billable:** no reads billable false, and only that one' ($offClock -ceq '160-off-the-clock.prompt.md') "got [$offClock]"
    $rows = @($rows | Where-Object { $_.file -ne '160-off-the-clock.prompt.md' })
    $seen = (@($rows | Sort-Object { $_.file } | ForEach-Object { "$($_.file)|$($_.folder)|$($_.status)|$($_.closed)|$($_.title)|$($_.id)" })) -join "`n"
    $want = (@(
            '151-never-stamped.prompt.md|archive|Done||Never stamped|151',
            '198-fix-the-export.prompt.md|archive|Done|2026-10-01|Fix the export|198',
            'K7M2-wire-the-board.prompt.md|current|Active||Wire the board|K7M2',
            'Task139-write-the-docs.prompt.md|current|In Progress||Write the docs|139',
            'US-144-read-the-board.prompt.md|current|Code Review||Read the board|144'
        ) | Sort-Object) -join "`n"
    Assert-True 'Get-P20StandupCards: state by the status rule, the Closed day, the title, the id; a file with no id is not a card' ($seen -ceq $want) ("`n--- got ---`n$seen`n--- want ---`n$want")
    Assert-True 'a card in backlog/ beside them is not read: planned is not in play (agent: read_cards, the same)' (@($rows | Where-Object { $_.id -eq '9QHT' -or $_.folder -eq 'backlog' }).Count -eq 0) $seen
    $none = @(Get-P20StandupCards -CurrentDir (Join-Path $readerDir 'nope') -ArchiveDir (Join-Path $readerDir 'nada') -Pattern $pattern)
    Assert-True 'a Space with no folders is no cards' ($none.Count -eq 0)

    # What moved: begun is the **Started:** day, else **Created:**; commits every `- <hash>` bullet's hash.
    $movedDir = Join-Path $readerDir 'moved'
    New-Item -ItemType Directory -Path (Join-Path $movedDir 'current') -Force | Out-Null
    $movedFiles = [ordered]@{
        'current/Task139-write-the-docs.prompt.md'  = "# Task 139: Write the docs`n`nCommits:`n- a41c2e9 first`n  - ``b52d3f0aa`` second`n- not a hash`n`n---`n`n**Created:** 2026-09-20`n**Started:** 2026-10-01`n"
        'current/TaskK7M2-wire-the-board.prompt.md' = "# Task K7M2: Wire the board`n`nCommits:`n- (pending)`n`n---`n`n**Created:** 2026-09-30`n"
        'current/140-no-footer.prompt.md'           = "# Bug 140: No footer`n"
    }
    foreach ($k in $movedFiles.Keys) { [System.IO.File]::WriteAllText((Join-Path $movedDir $k), $movedFiles[$k], $utf8r) }
    $moved = @(Get-P20StandupCards -CurrentDir (Join-Path $movedDir 'current') -ArchiveDir (Join-Path $movedDir 'archive') -Pattern $pattern)
    $seenMoved = (@($moved | Sort-Object { $_.id } | ForEach-Object { "$($_.id)|$($_.begun)|$((@($_.commits)) -join ',')" })) -join "`n"
    $wantMoved = "139|2026-10-01|a41c2e9,b52d3f0aa`n140||`nK7M2|2026-09-30|"
    Assert-True 'Get-P20StandupCards: begun is the Started day, else the Created day; commits every bullet''s hash' ($seenMoved -ceq $wantMoved) ("`n--- got ---`n$seenMoved`n--- want ---`n$wantMoved")

    # What the suggestion reads: the **Sprint:** line whole, the Created day, the Tags, who takes it.
    $sugDir = Join-Path $readerDir 'suggest'
    New-Item -ItemType Directory -Path (Join-Path $sugDir 'current') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $sugDir 'current/Task23A3-route-the-git-calls.prompt.md'),
        "# Task 23A3: Route the git calls`r`nTags: spec, sev2, sonnet`r`n`r`n---`r`n`r`n**Sprint:** M2 -- 1.2.0, the standup sees the work`r`n**Assigned:** me`r`n**Created:** 2026-09-20`r`n", $utf8r)
    [System.IO.File]::WriteAllText((Join-Path $sugDir 'current/TaskK7M2-bare.prompt.md'), "# Task K7M2: Bare`n", $utf8r)
    $sugRows = @(Get-P20StandupCards -CurrentDir (Join-Path $sugDir 'current') -ArchiveDir (Join-Path $sugDir 'archive') -Pattern $pattern)
    $seenSug = (@($sugRows | Sort-Object { $_.id } | ForEach-Object { "$($_.id)|$($_.sprint)|$($_.created)|$((@($_.tags)) -join ',')|$($_.assigned)" })) -join "`n"
    $wantSug = "23A3|M2 -- 1.2.0, the standup sees the work|2026-09-20|spec,sev2,sonnet|me`nK7M2||||"
    Assert-True 'Get-P20StandupCards: the milestone a card names (whole), its Created day, its Tags, who takes it (agent: the same)' ($seenSug -ceq $wantSug) ("`n--- got ---`n$seenSug`n--- want ---`n$wantSug")

    # A card routed with Route -Assign sonnet carries the Agent line alone: the
    # standup's row and the suggestion see it as sonnet (agent: the same).
    $routedDir = Join-Path $readerDir 'routed'
    New-Item -ItemType Directory -Path (Join-Path $routedDir 'current') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $routedDir 'current/TaskR2DW-routed-to-sonnet.prompt.md'),
        "# Task R2DW: Routed to sonnet`n`n---`n`n**Agent:** claude-sonnet-5-5`n**Created:** 2026-09-20`n", $utf8r)
    $routedRows = @(Get-P20StandupCards -CurrentDir (Join-Path $routedDir 'current') -ArchiveDir (Join-Path $routedDir 'archive') -Pattern $pattern)
    Assert-True 'Get-P20StandupCards: a card routed to sonnet (its Agent line alone) is taken by sonnet' ($routedRows.Count -eq 1 -and [string]$routedRows[0].assigned -ceq 'sonnet') (($routedRows | ForEach-Object { "$($_.id)|$($_.assigned)" }) -join ' / ')
    if (-not (Get-Command Get-P20SuggestionItems -ErrorAction SilentlyContinue)) { . (Join-Path $pkgRoot 'Scripts/Suggest-Rules.ps1') }
    $routedLabels = @([pscustomobject]@{ name = 'sonnet'; description = 'Routed to sonnet -- the crew' })
    $routedItems = @(Get-P20SuggestionItems -Labels $routedLabels -Issues @() -Cards $routedRows -PackageRoot $pkgRoot)
    Assert-True 'and the suggestion sizes it as sonnet: who is sonnet' ($routedItems.Count -eq 1 -and [string]$routedItems[0].who -ceq 'sonnet') (($routedItems | ForEach-Object { "$($_.ref)|$($_.who)" }) -join ' / ')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $readerDir -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 1b'. Both: issues and cards, joined on the id ----------------------------
# Tests/fixtures/rituals/standup-joined.json, every case, the SAME rows
# Tests/test_rituals.py asserts against fill_joined_standup.
function Get-Refs {
    # A slot's refs -- #<n> for an issue, the id for a card -- as one comparable string.
    param($Items)
    return ((@($Items | Where-Object { $null -ne $_ } | ForEach-Object { Get-P20StandupItemRef $_ })) -join ',')
}

$joinedRaw = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-joined.json'))
$joinedTable = $joinedRaw | ConvertFrom-Json
$joinedCases = @($joinedTable.cases)
$joinedAsOf = ([regex]::Match($joinedRaw, '"asOf"\s*:\s*"([^"]+)"')).Groups[1].Value
$joinedSince = ([regex]::Match($joinedRaw, '"since"\s*:\s*"([^"]+)"')).Groups[1].Value
$joinedNames = (@($joinedCases | ForEach-Object { [string]$_.name })) -join ','
Assert-True 'the joined table is read: the six shapes, all of them together, then what moved' ($joinedNames -ceq 'linked-card-open-issue,linked-card-archived-issue-open,issue-closed-card-current,linked-card-issue-unrouted,custom-card-alone,issue-alone,not-billable,together,counts,not-billable-counts,window-three-days,commits-window,issue-labelled-in-window,issue-assigned-before-window,dates-not-read') $joinedNames

foreach ($case in $joinedCases) {
    $name = 'joined-' + [string]$case.name
    $exp = $case.expected
    Write-Host ""
    Write-Host "-- $name --" -ForegroundColor Cyan
    $window = ConvertTo-P20StandupDay $case.window
    # The dates read, when the case has one: absent is not read, and today's rule stands.
    $s = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($case.issues) -Tracker @{ ok = $true; reason = '' } `
        -Cards @($case.cards) -Space ([string]$joinedTable.space) -SpaceName ([string]$joinedTable.spaceName) -Window $window -PackageRoot $pkgRoot `
        -CommitDates (ConvertTo-P20StandupMap $case.commitDates) -IssueStarts (ConvertTo-P20StandupMap $case.issueStarts)
    if ($window) {
        # A window's since is that day's midnight in asOf's own offset (7's ConvertFrom-Json may hand back a [datetime]: the instant is compared).
        $wantSince = ConvertTo-P20RitualTime $exp.since
        Assert-True "${name}: source is both, since is the window's first day" ($s.source -ceq 'both' -and (ConvertTo-P20RitualTime $s.since) -eq $wantSince -and $s.since.EndsWith($joinedAsOf.Substring($joinedAsOf.Length - 6))) "$($s.source) $($s.since)"
    }
    else {
        Assert-True "${name}: source is both, since is the previous working day's" ($s.source -ceq 'both' -and $s.since -ceq $joinedSince) "$($s.source) $($s.since)"
    }
    $want = (@($exp.walk | ForEach-Object { [string]$_ })) -join ','
    $got = Get-Refs $s.queue.walk
    Assert-True "${name}: the walk is [$want]" ($got -ceq $want) "got [$got]"
    $wantWorkers = (@($exp.workers | ForEach-Object { "$($_.label)/$($_.name) y[$((@($_.yesterday)) -join ',')] t[$((@($_.today)) -join ',')] b[$((@($_.blockers)) -join ',')] $([bool]$_.empty) $(if ($null -eq $_.nothingIndex) { 'null' } else { $_.nothingIndex })/$(if ($null -eq $_.nothingTodayIndex) { 'null' } else { $_.nothingTodayIndex })" })) -join ' | '
    $gotWorkers = (@($s.workers | ForEach-Object { "$($_.label)/$($_.name) y[$(Get-Refs $_.yesterday)] t[$(Get-Refs $_.today)] b[$(Get-Refs $_.blockers)] $([bool]$_.empty) $(& $idleIndexes $_)" })) -join ' | '
    Assert-True "${name}: every worker's slots by ref, and an idle one's two made-up items by index" ($gotWorkers -ceq $wantWorkers) ("`n got: $gotWorkers`nwant: $wantWorkers")
    $wantChecks = (@($exp.checks | ForEach-Object { ([string]$consts.rituals.text.([string]$_.key)).Replace('{item}', [string]$_.item) })) -join "`n"
    $gotChecks = (@($s.checks | ForEach-Object { [string]$_ })) -join "`n"
    Assert-True "${name}: the Check lines ($(@($exp.checks).Count))" ($gotChecks -ceq $wantChecks) ("`n got: $gotChecks`nwant: $wantChecks")
    $wantLinks = (@($exp.links | ForEach-Object { "$($_.number)/$($_.id)/$($_.lane)" })) -join ','
    $gotLinks = (@($s.links | ForEach-Object { "$($_.number)/$($_.id)/$($_.lane)" })) -join ','
    Assert-True "${name}: the links are [$wantLinks]" ($gotLinks -ceq $wantLinks) "got [$gotLinks]"
    if ($null -ne $exp.motions) {
        $wantMotions = (@($exp.motions.PSObject.Properties | ForEach-Object { "$($_.Name)=$(@($_.Value)[0])/$(@($_.Value)[1])" }) | Sort-Object) -join ','
        $gotMotions = (@(foreach ($w in @($s.workers)) { foreach ($slot in @('yesterday', 'today', 'blockers')) { foreach ($it in @($w.$slot | Where-Object { $null -ne $_ })) { "$(Get-P20StandupItemRef $it)=$($it.motion)/$($it.commits)" } } }) | Sort-Object) -join ','
        Assert-True "${name}: each item's motion and commits" ($gotMotions -ceq $wantMotions) ("`n got: $gotMotions`nwant: $wantMotions")
    }
    if ($null -ne $exp.counts) {
        # Absent undated is none undated.
        $countLine = { param($c) $u = 0; if ($null -ne $c.undated) { $u = [int]$c.undated }; "$($c.closed)/$($c.started)/$($c.inProgress)/$($c.commits)/$u" }
        $wantCounts = (@($exp.counts.workers | ForEach-Object { "$($_.label) " + (& $countLine $_) }) + @('total ' + (& $countLine $exp.counts.total))) -join ' | '
        $gotCounts = (@($s.counts.workers | ForEach-Object { "$($_.label) " + (& $countLine $_) }) + @('total ' + (& $countLine $s.counts.total))) -join ' | '
        Assert-True "${name}: the counts per worker and in total (closed/started/in progress/commits/undated)" ($gotCounts -ceq $wantCounts) ("`n got: $gotCounts`nwant: $wantCounts")
    }

    $text = Format-P20StandupText -Standup $s -PackageRoot $pkgRoot
    $s.work.text = Format-P20StandupWork -Standup $s -PackageRoot $pkgRoot
    $brief = Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot
    if ($exp.text) {
        foreach ($pair in @(@($text, [string]$exp.text), @([string]$s.work.text, [string]$exp.work), @($brief, [string]$exp.brief))) {
            $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir $pair[1]))
            Assert-True "${name}: $($pair[1]), byte for byte" ($pair[0] -ceq $golden) ("`n--- got ---`n$($pair[0])--- want ---`n$golden")
        }
    }
    $back = ($s | ConvertTo-Json -Depth 10) | ConvertFrom-Json
    $back.asOf = $s.asOf
    $back.since = $s.since
    $again = (Format-P20StandupText -Standup $back -PackageRoot $pkgRoot) + (Format-P20StandupWork -Standup $back -PackageRoot $pkgRoot) + (Format-P20StandupBrief -Standup $back -PackageRoot $pkgRoot)
    Assert-True "${name}: the JSON round trip renders the same three texts" ($again -ceq ($text + $s.work.text + $brief)) $again
    Assert-True "${name}: no fakeWork line in the real register" (@($fakeWork | Where-Object { ($text + $s.work.text + $brief).Contains([string]$_) }).Count -eq 0)
}

Write-Host ""
Write-Host "-- Both, said in words --" -ForegroundColor Cyan
$fridayCase = @($cases | Where-Object { $_.name -eq 'friday' })[0]
$fridayAsOf = $asOfTexts[[array]::IndexOf(@($cases | ForEach-Object { $_.name }), 'friday')]
$aloneFill = Invoke-P20StandupFill -AsOf $fridayAsOf -Labels @($fixture.workerLabels) -Issues @($fridayCase.issues) -Tracker @{ ok = $true; reason = '' } -Space 'toolkit' -PackageRoot $pkgRoot
$joinedFill = Invoke-P20StandupJoinedFill -AsOf $fridayAsOf -Labels @($fixture.workerLabels) -Issues @($fridayCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'toolkit' -SpaceName 'Toolkit' -PackageRoot $pkgRoot
# A rendering with the engineer's rows set aside: the detail's block under Name
# (the name line and its indented rows) and the brief's 'Name: ...' line. What
# is left is the labelled workers' own, which the issues fill's goldens hold.
function Remove-EngineerRows {
    param([string]$Text, [string]$Name)
    $out = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    foreach ($line in $Text.Split([char]10)) {
        if ($line -ceq $Name) { $skipping = $true; continue }
        if ($skipping -and $line.StartsWith('  ')) { continue }
        $skipping = $false
        if ($line.StartsWith($Name + ': ')) { continue }
        $out.Add($line)
    }
    return ($out -join "`n")
}
$joinedText = Format-P20StandupText -Standup $joinedFill -PackageRoot $pkgRoot
$joinedBrief = Format-P20StandupBrief -Standup $joinedFill -PackageRoot $pkgRoot
$aloneText = Format-P20StandupText -Standup $aloneFill -PackageRoot $pkgRoot
$aloneBrief = Format-P20StandupBrief -Standup $aloneFill -PackageRoot $pkgRoot
$joinedEngineer = @($joinedFill.workers)[-1]
Assert-True 'no card in play: the issues'' own rows, then the engineer''s -- idle, present, named for the Space -- and the source says both' ($joinedFill.source -ceq 'both' -and @($joinedFill.workers).Count -eq (@($aloneFill.workers).Count + 1) -and [string]$joinedEngineer.label -ceq 'toolkit' -and [string]$joinedEngineer.name -ceq 'Toolkit' -and $joinedEngineer.empty -and $joinedEngineer.present -and @($joinedEngineer.status).Count -eq 2) ((@($joinedFill.workers | ForEach-Object { $_.label })) -join ',')
Assert-True 'no card in play: the text and the brief are the issues'' own once the engineer''s rows are set aside, and differ by them' ($joinedText -cne $aloneText -and (Remove-EngineerRows $joinedText 'Toolkit') -ceq $aloneText -and $joinedBrief -cne $aloneBrief -and (Remove-EngineerRows $joinedBrief 'Toolkit') -ceq $aloneBrief) ("`n" + $joinedText + $joinedBrief)
Assert-True 'no card in play: the engineer takes the round''s first turn' ([string]@($joinedFill.work.workers)[0].label -ceq 'toolkit' -and -not @($joinedFill.work.workers)[0].cast)
$together = @($joinedCases | Where-Object { $_.name -eq 'together' })[0]
$downFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($together.issues) -Tracker @{ ok = $false; reason = 'gh did not answer' } -Cards @($together.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
Assert-True 'the tracker not answering: the Tracker line, no worker, no Check line, no link' ($downFill.source -ceq 'none' -and @($downFill.workers).Count -eq 0 -and @($downFill.checks).Count -eq 0 -and @($downFill.links).Count -eq 0)
$slugged = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @([pscustomobject]@{ name = 'opus'; description = 'Routed to Opus' }) -Issues @() -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'opus' -SpaceName 'Opus' -PackageRoot $pkgRoot
$sluggedBrief = Format-P20StandupBrief -Standup $slugged
Assert-True 'a Space slugged as its only worker label still has a worker label: the in-flight line, not noWorkers' ($sluggedBrief.Contains([string]$consts.rituals.text.briefInFlightUnknown) -and -not $sluggedBrief.Contains([string]$consts.rituals.text.noWorkers))
$rounds = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Tracker @{ ok = $true; reason = '' } -Space 'widgets' -PackageRoot $pkgRoot `
    -Issues @([pscustomobject]@{ number = 141; title = 'Build'; state = 'OPEN'; labels = @('opus'); closedAt = $null }) `
    -Cards @([pscustomobject]@{ file = '141-build-r1.prompt.md'; folder = 'archive'; status = 'Done'; closed = '2026-09-01'; id = '141' },
    [pscustomobject]@{ file = '141-build.prompt.md'; folder = 'current'; status = 'In Progress'; closed = $null; id = '141' })
$readAsOf = [DateTimeOffset]::Parse('2026-10-02T09:00:00-04:00', [System.Globalization.CultureInfo]::InvariantCulture)
Assert-True 'a window is a yyyy-MM-dd day on or before today; empty is the default' ((Test-P20StandupSince -AsOf $readAsOf -Since '') -ceq '' -and (Test-P20StandupSince -AsOf $readAsOf -Since '2026-10-02') -ceq '' -and (Test-P20StandupSince -AsOf $readAsOf -Since '2026-09-29') -ceq '')
$badSince = @(@('2026-10-03', 'yesterday', '2026-9-29', '2026-02-30', '29/09/2026') | Where-Object { -not (Test-P20StandupSince -AsOf $readAsOf -Since $_) })
Assert-True 'a day after today, or one that is not a day, says why' ($badSince.Count -eq 0) "no reason for: $($badSince -join ', ')"
Assert-True 'a window starts at that day''s midnight in asOf''s own offset' ((Format-P20RitualTime (Get-P20StandupSince -AsOf $readAsOf -Window '2026-09-29')) -ceq '2026-09-29T00:00:00-04:00')
Assert-True 'a card''s hashes are distinct by their first seven characters, lowercase' (((Get-P20StandupCardHashes ([pscustomobject]@{ commits = @('A1B2C3D', 'a1b2c3d4e5f6', 'b2c3d4e', '') })) -join ',') -ceq 'a1b2c3d,b2c3d4e' -and (Get-P20StandupCardHashes ([pscustomobject]@{ file = 'x' })).Count -eq 0)
$countsCase = @($joinedCases | Where-Object { $_.name -eq 'counts' })[0]
$countsFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($countsCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards @($countsCase.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
$countsFirst = @((Format-P20StandupBrief -Standup $countsFill -PackageRoot $pkgRoot) -split "`n")[0]
Assert-True 'the counts line opens the brief' ($countsFirst -ceq 'Since Thursday 1 October 2026: 2 closed, 2 started, 2 in progress, 5 commits.') $countsFirst
$windowCase = @($joinedCases | Where-Object { $_.name -eq 'commits-window' })[0]
$windowFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($windowCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards @($windowCase.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot `
    -CommitDates (ConvertTo-P20StandupMap $windowCase.commitDates) -IssueStarts (ConvertTo-P20StandupMap $windowCase.issueStarts)
$windowFirst = @((Format-P20StandupBrief -Standup $windowFill -PackageRoot $pkgRoot) -split "`n")[0]
Assert-True 'an undated commit is said after the commits, not counted' ($windowFirst -ceq 'Since Thursday 1 October 2026: 1 started, 1 in progress, 3 commits (2 undated).') $windowFirst
Assert-True 'with only undated commits the count says so: 0 commits (2 undated)' ((Get-P20StandupCountsText ([ordered]@{ closed = 0; started = 0; inProgress = 0; commits = 0; undated = 2 })) -ceq '0 commits (2 undated)')
$readSince = Get-P20StandupSince -AsOf $readAsOf
$wh = Select-P20StandupWindowHashes -Hashes @('a0a1111', 'b0b2222', 'c0c3333', 'd0d4444') -CommitDates @{ 'A0A1111FFFF' = '2026-10-01T04:00:00Z'; 'b0b2222' = '2026-09-30T23:59:59-04:00'; 'c0c3333' = $null } -Since $readSince -AsOf $readAsOf
Assert-True 'the window hashes rule: in the window counts, before it drops, no date is undated (agent: the same)' ((($wh.inside) -join ',') -ceq 'a0a1111' -and (($wh.undated) -join ',') -ceq 'c0c3333,d0d4444') "$($wh.inside -join ',') | $($wh.undated -join ',')"
$notRead = Select-P20StandupWindowHashes -Hashes @('a0a1111') -CommitDates $null -Since $readSince -AsOf $readAsOf
Assert-True 'no dates read: every hash counts' ((($notRead.inside) -join ',') -ceq 'a0a1111' -and @($notRead.undated).Count -eq 0)
$plainCase = @($joinedCases | Where-Object { $_.name -eq 'dates-not-read' })[0]
$plainFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($plainCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards @($plainCase.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
$plainAsks = Get-P20StandupDateAsks -Standup $plainFill -Cards @($plainCase.cards) -Slots @('yesterday', 'today', 'blockers')
Assert-True 'the asks are the counted cards'' hashes (agent: the same)' ((($plainAsks.hashes) -join ',') -ceq 'a0a1111,b0b2222,c0c3333,d0d4444,a0a9999,e0e5555,f0f6666' -and @($plainAsks.numbers).Count -eq 0) "$($plainAsks.hashes -join ',') | $($plainAsks.numbers -join ',')"
$loneCase = @($joinedCases | Where-Object { $_.name -eq 'issue-assigned-before-window' })[0]
$loneFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($loneCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards @($loneCase.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
$loneAsks = Get-P20StandupDateAsks -Standup $loneFill -Cards @($loneCase.cards) -Slots @('yesterday', 'today', 'blockers')
Assert-True 'and the open issues with no card, by number (agent: the same)' (@($loneAsks.hashes).Count -eq 0 -and (($loneAsks.numbers) -join ',') -ceq '172') "$($loneAsks.numbers -join ',')"
# The trailer asks: the commits of every card the fill places with no Agent line.
$slotsT = @('yesterday', 'today', 'blockers')
$plainTrailers = Get-P20StandupTrailerAsks -Standup $plainFill -Cards @($plainCase.cards) -Slots $slotsT
Assert-True 'the trailer asks: the slots'' own cards, then the joined ones (agent: the same)' (($plainTrailers -join ',') -ceq 'e0e5555,f0f6666,a0a1111,b0b2222,c0c3333,d0d4444,a0a9999') ($plainTrailers -join ',')
$linedCards = @($plainCase.cards | ForEach-Object { $_ | Select-Object * })
$linedCards[0] | Add-Member -NotePropertyName body -NotePropertyValue "# Task 170: Date the commits`n`n**Agent:** claude-opus-5-5`n" -Force
$linedTrailers = Get-P20StandupTrailerAsks -Standup $plainFill -Cards $linedCards -Slots $slotsT
Assert-True 'the trailer asks: never a card whose Agent line answers (agent: the same)' (($linedTrailers -join ',') -ceq 'e0e5555,f0f6666') ($linedTrailers -join ',')
$oldCard = [pscustomobject]@{ file = 'Task120-long-ago.prompt.md'; folder = 'archive'; status = 'Done'; closed = '2026-01-05'; title = 'Long ago'; id = '120'; path = 'archive/Task120-long-ago.prompt.md'; commits = @('9a9a9a9') }
$withOld = @(@($plainCase.cards) + $oldCard)
$oldFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($plainCase.issues) -Tracker @{ ok = $true; reason = '' } -Cards $withOld -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
# One array back, as Get-P20StandupCardHashes gives one: not wrapped again in @().
$oldTrailers = Get-P20StandupTrailerAsks -Standup $oldFill -Cards $withOld -Slots $slotsT
Assert-True 'the trailer asks: never the whole archive (agent: the same)' ($oldTrailers.Count -gt 0 -and -not ($oldTrailers -contains '9a9a9a9')) ($oldTrailers -join ',')
$loneTrailers = Get-P20StandupTrailerAsks -Standup $loneFill -Cards @($loneCase.cards) -Slots $slotsT
Assert-True 'the trailer asks: an issue alone asks none (agent: the same)' ($loneTrailers.Count -eq 0) ($loneTrailers -join ',')

# -- The dates read: its query and its parse ----------------------------------
# Tests/fixtures/rituals/standup-dates.json, the SAME rows Tests/test_rituals.py
# asserts against dates_query and dates_from_answer.
Write-Host ""
Write-Host "-- The dates read --" -ForegroundColor Cyan
$datesTable = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-dates.json')) | ConvertFrom-Json
$dq = $datesTable.query
$wantQuery = ((@($dq.lines | ForEach-Object { [string]$_ })) -join "`n") + "`n"
$gotQuery = Get-P20StandupDatesQuery -Hashes ([string[]]@($dq.hashes)) -Numbers ([int[]]@($dq.numbers))
Assert-True 'dates: the query, line for line' ($gotQuery -ceq $wantQuery) ("`n--- got ---`n$gotQuery--- want ---`n$wantQuery")
Assert-True 'dates: a hash that is not hex is never written into the query' (-not (Get-P20StandupDatesQuery -Hashes @('a0a1111") { x } evil: object(expression: "') -Numbers @()).Contains('evil'))
$tq = $datesTable.trailerQuery
$wantTQuery = ((@($tq.lines | ForEach-Object { [string]$_ })) -join "`n") + "`n"
$gotTQuery = Get-P20StandupDatesQuery -Hashes ([string[]]@($tq.hashes)) -Numbers ([int[]]@($tq.numbers)) -Trailers ([string[]]@($tq.trailers))
Assert-True 'dates: the trailer aliases ride after the others, line for line' ($gotTQuery -ceq $wantTQuery) ("`n--- got ---`n$gotTQuery--- want ---`n$wantTQuery")
Assert-True 'dates: no trailer hashes is the query unchanged' ((Get-P20StandupDatesQuery -Hashes ([string[]]@($dq.hashes)) -Numbers ([int[]]@($dq.numbers)) -Trailers @()) -ceq $wantQuery)
Assert-True 'dates: a trailer hash that is not hex is never written into the query' (-not (Get-P20StandupDatesQuery -Hashes @() -Numbers @() -Trailers @('a0a1111") { x } evil: object(expression: "')).Contains('evil'))
foreach ($dc in @($datesTable.cases)) {
    $trailersOf = [string[]]@()
    if ($dc.PSObject.Properties['trailers']) { $trailersOf = [string[]]@($dc.trailers) }
    $got = ConvertFrom-P20StandupDates -Repository $dc.answer -Hashes ([string[]]@($dc.hashes)) -Numbers ([int[]]@($dc.numbers)) -WorkerLabels ([string[]]@($datesTable.workerLabels)) -Trailers $trailersOf
    $wantM = ''
    if ($dc.expected.PSObject.Properties['messages']) { $wantM = (@($dc.expected.messages.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) | Sort-Object) -join '|' }
    $gotM = (@($got.messages.Keys | ForEach-Object { "$_=$($got.messages[$_])" }) | Sort-Object) -join '|'
    Assert-True "dates $($dc.name): the messages" ($gotM -ceq $wantM) "got [$gotM] want [$wantM]"
    $instant = { param($v) $t = ConvertTo-P20RitualTime $v; if ($null -eq $t) { 'null' } else { $t.UtcTicks } }
    $wantC = (@($dc.expected.commitDates.PSObject.Properties | ForEach-Object { "$($_.Name)=$(& $instant $_.Value)" }) | Sort-Object) -join ','
    $gotC = (@($got.commitDates.Keys | ForEach-Object { "$_=$(& $instant $got.commitDates[$_])" }) | Sort-Object) -join ','
    $wantS = (@($dc.expected.issueStarts.PSObject.Properties | ForEach-Object { "$($_.Name)=$(& $instant $_.Value)" }) | Sort-Object) -join ','
    $gotS = (@($got.issueStarts.Keys | ForEach-Object { "$_=$(& $instant $got.issueStarts[$_])" }) | Sort-Object) -join ','
    Assert-True "dates $($dc.name): the commit dates" ($gotC -ceq $wantC) "got [$gotC] want [$wantC]"
    Assert-True "dates $($dc.name): the issue starts" ($gotS -ceq $wantS) "got [$gotS] want [$wantS]"
}
Assert-True 'rounds share an id: the one in current/ is the card, so an earlier archived round is no Check line' (@($rounds.checks).Count -eq 0 -and (@($rounds.links | ForEach-Object { "$($_.lane)|$($_.path)" }) -join ',') -ceq 'In Progress|current/141-build.prompt.md') ((@($rounds.links | ForEach-Object { "$($_.lane)|$($_.path)" })) -join ',')

# -- 1c. The work grain (D-TA20) -------------------------------------------
# Tests/fixtures/rituals/standup-work.json, every case and every small table, the
# SAME rows Tests/test_rituals.py asserts: the groups of the queue's kinds and of
# each worker's slots -- name, how it was found, count, refs, phrase -- and the
# work text against standup-work-<name>.txt, byte for byte.
function Get-GroupLine {
    # One group as one comparable string.
    param($G)
    return "$($G.name)|$($G.by)|$($G.count)|$((@($G.refs) | ForEach-Object { [string]$_ }) -join ',')|$($G.phrase)"
}
function Get-GroupLines {
    param($Groups)
    return ((@($Groups | Where-Object { $null -ne $_ } | ForEach-Object { Get-GroupLine $_ })) -join ' / ')
}

Write-Host ""
Write-Host "-- The work grain --" -ForegroundColor Cyan
$workRaw = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-work.json'))
$workTable = $workRaw | ConvertFrom-Json
$workCases = @($workTable.cases)
$workAsOf = @([regex]::Matches($workRaw, '"asOf"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'the work table is read: three cases, an asOf each' ($workCases.Count -eq 3 -and $workAsOf.Count -eq 3) "$($workCases.Count) cases, $($workAsOf.Count) asOf"

for ($n = 0; $n -lt $workCases.Count; $n++) {
    $case = $workCases[$n]
    $name = 'work-' + [string]$case.name
    $exp = $case.expected
    if ([string]$case.source -eq 'cards') {
        $s = Invoke-P20StandupCardsFill -AsOf $workAsOf[$n] -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot
    }
    else {
        $s = Invoke-P20StandupFill -AsOf $workAsOf[$n] -Labels @($workTable.workerLabels) -Issues @($case.issues) -Tracker $case.tracker -PackageRoot $pkgRoot
    }
    foreach ($kind in @('walk', 'decide', 'look')) {
        $want = Get-GroupLines $exp.queue.$kind
        $got = Get-GroupLines $s.work.queue.$kind
        Assert-True "${name}: queue.$kind groups" ($got -ceq $want) "`n  got  $got`n  want $want"
    }
    # The table's rows are the members'; the invented cast members that fill the
    # room follow them, with no group: the golden text holds their lines.
    $gotWorkers = @($s.work.workers | Where-Object { -not $_.cast })
    $gotCast = @($s.work.workers | Where-Object { $_.cast })
    $wantWorkers = @($exp.workers)
    Assert-True "${name}: one work row per member, in seat order" (((@($gotWorkers | ForEach-Object { $_.label })) -join ',') -ceq ((@($wantWorkers | ForEach-Object { $_.label })) -join ',')) ((@($gotWorkers | ForEach-Object { $_.label })) -join ',')
    Assert-True "${name}: the invented cast members come after the members, with no group" (((@($s.work.workers | Select-Object -Skip $gotWorkers.Count | ForEach-Object { [string]$_.cast })) -join ',') -ceq ((@($gotCast | ForEach-Object { 'True' })) -join ',') -and @($gotCast | Where-Object { @($_.yesterday).Count + @($_.today).Count + @($_.blockers).Count -gt 0 }).Count -eq 0)
    foreach ($w in $wantWorkers) {
        $g = @($gotWorkers | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
        foreach ($slot in @('yesterday', 'today', 'blockers')) {
            $want = Get-GroupLines $w.$slot
            $got = ''
            if ($g) { $got = Get-GroupLines $g.$slot }
            Assert-True "${name}: $($w.label).$slot groups" ($got -ceq $want) "`n  got  $got`n  want $want"
        }
    }
    $text = Format-P20StandupWork -Standup $s -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
    Assert-True "${name}: the work text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    $back = ($s | ConvertTo-Json -Depth 12) | ConvertFrom-Json
    $back.asOf = $s.asOf
    Assert-True "${name}: the JSON round trip renders the same work text" ((Format-P20StandupWork -Standup $back -PackageRoot $pkgRoot) -ceq $text)
    Assert-True "${name}: no fakeWork line in the work grain" (@($fakeWork | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
}

foreach ($row in @($workTable.heads)) {
    $got = Get-P20StandupHead ([string]$row.title)
    Assert-True "the head of '$($row.title)' is '$($row.head)'" ($got -ceq [string]$row.head) "got '$got'"
}
foreach ($row in @($workTable.keys)) {
    $threads = @{}
    if ($row.threads) { foreach ($p in $row.threads.PSObject.Properties) { $threads[[string]$p.Name] = [string]$p.Value } }
    $keyBody = [string]$row.body
    if ($row.digits) { $keyBody += ('9' * [int]$row.digits) }
    $got = Get-P20StandupWorkKey -Milestone $row.milestone -Body $keyBody -Type ([string]$row.type) -Threads $threads
    Assert-True "work key: milestone '$($row.milestone)', body '$(([string]$row.body).Trim())', type '$($row.type)' -> '$($row.name)' by '$($row.by)'" ($got.name -ceq [string]$row.name -and $got.by -ceq [string]$row.by) "got '$($got.name)' by '$($got.by)'"
}
foreach ($row in @($workTable.types)) {
    $got = Get-P20StandupCardType -Content ([string]$row.content) -Id ([string]$row.id)
    Assert-True "a card's type: '$(([string]$row.content).Trim())' -> '$($row.type)'" ($got -ceq [string]$row.type) "got '$got'"
}
foreach ($row in @($workTable.counts)) {
    $got = Get-P20StandupCountWord ([int]$row.n)
    Assert-True "the count $($row.n) is said '$($row.word)'" ($got -ceq [string]$row.word) "got '$got'"
}
Assert-True 'the grains are detail, work and brief, in that order' (((@($consts.rituals.grains)) -join ',') -ceq 'detail,work,brief')
$grainCase = Invoke-P20StandupFill -AsOf $workAsOf[0] -Labels @($workTable.workerLabels) -Issues @($workCases[0].issues) -Tracker $workCases[0].tracker -PackageRoot $pkgRoot
$grainCase.text = Format-P20StandupText -Standup $grainCase -PackageRoot $pkgRoot
$grainCase.work.text = Format-P20StandupWork -Standup $grainCase -PackageRoot $pkgRoot
$grainCase['brief'] = Format-P20StandupBrief -Standup $grainCase -PackageRoot $pkgRoot
Assert-True 'Get-P20StandupGrainText: detail is the text, work the work text, brief the brief, anything else nothing' ((Get-P20StandupGrainText -Standup $grainCase -Grain 'detail') -ceq $grainCase.text -and (Get-P20StandupGrainText -Standup $grainCase -Grain 'work') -ceq $grainCase.work.text -and (Get-P20StandupGrainText -Standup $grainCase -Grain 'brief') -ceq $grainCase.brief -and $null -eq (Get-P20StandupGrainText -Standup $grainCase -Grain 'Work'))
$standupJson = Invoke-P20StandupFill -AsOf $asOfTexts[0] -Labels @($fixture.workerLabels) -Issues @($cases[0].issues) -Tracker $cases[0].tracker -PackageRoot $pkgRoot
Assert-True 'the response carries work beside text: queue, workers, the queue''s prose, the chair''s turn and its own text' ($standupJson.Contains('work') -and (((@($standupJson.work.Keys)) -join ',') -ceq 'queue,workers,queueProse,chairProse,text')) ((@($standupJson.work.Keys)) -join ',')
Assert-True 'a work row carries its prose after its three slots, then whether it is an invented cast member' ((((@($standupJson.work.workers[0].Keys)) -join ',') -ceq 'label,name,yesterday,today,blockers,prose,cast')) ((@($standupJson.work.workers[0].Keys)) -join ',')

# -- 1d. The prose ---------------------------------------------------------
# Tests/fixtures/rituals/standup-prose.json, every row and every case, the SAME
# rows Tests/test_rituals.py asserts: one group as one standup sentence (lead and
# body, every fixed word from rituals.text), then each case's queue sentences,
# each worker's sentences in order, and the work text against
# standup-prose-<name>.txt, byte for byte.
Write-Host ""
Write-Host "-- The prose --" -ForegroundColor Cyan
$proseRaw = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-prose.json'))
$proseTable = $proseRaw | ConvertFrom-Json
$proseCases = @($proseTable.cases)
$proseAsOf = @([regex]::Matches($proseRaw, '"asOf"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'the prose table is read: nine cases, an asOf each' ($proseCases.Count -eq 9 -and $proseAsOf.Count -eq 9) "$($proseCases.Count) cases, $($proseAsOf.Count) asOf"

foreach ($row in @($proseTable.sentences)) {
    $titles = @{}
    if ($row.titles) { foreach ($p in $row.titles.PSObject.Properties) { $titles[[string]$p.Name] = [string]$p.Value } }
    $got = Get-P20StandupProseSentence -Slot ([string]$row.slot) -First ([bool]$row.first) -Group $row.group -Titles $titles
    Assert-True "prose: $($row.sentence)" ($got -ceq [string]$row.sentence) "got '$got'"
}

# The also-ons fold (D-SA9): the groups after today's first as ONE sentence --
# their names up to proseFoldNames, the count alone past it; other slots never fold.
$foldRows = @($proseTable.folds)
Assert-True 'the fold table is read: nine rows' ($foldRows.Count -eq 9) "$($foldRows.Count) rows"
foreach ($row in $foldRows) {
    $rows = @()
    if ($row.titles) { foreach ($p in $row.titles.PSObject.Properties) { $rows += @{ ref = [string]$p.Name; title = [string]$p.Value } } }
    $want = (@($row.sentences | ForEach-Object { [string]$_ })) -join ' | '
    $got = (@(Get-P20StandupProse -Slot ([string]$row.slot) -Groups @($row.groups) -Rows $rows)) -join ' | '
    Assert-True "fold: $($row.slot), $(@($row.groups).Count) groups" ($got -ceq $want) "`n  got  $got`n  want $want"
}

# A slot a member with something to say has nothing in: the fixed honest line,
# or for yesterday the refs of its open items worked inside the window -- never a
# made-up item. The `unsaid` rows, the same ones the agent asserts against prose_unsaid.
$unsaidRows = @($proseTable.unsaid)
$workedSizes = @($unsaidRows | Where-Object { [string]$_.slot -ceq 'yesterday' } | ForEach-Object { @($_.worked).Count })
$unsaidCap = [int]$consts.rituals.proseFoldNames
Assert-True 'the unsaid table has a yesterday row each side of every edge' ((@(0, 1, 2, $unsaidCap, ($unsaidCap + 1)) | Where-Object { $workedSizes -notcontains $_ }).Count -eq 0) ($workedSizes -join ',')
foreach ($row in $unsaidRows) {
    $want = (@($row.lines | ForEach-Object { [string]$_ })) -join ' | '
    $got = (@(Get-P20StandupProseUnsaid -Slot ([string]$row.slot) -Worked @($row.worked | ForEach-Object { [string]$_ }))) -join ' | '
    Assert-True "unsaid: $($row.slot), $(@($row.worked).Count) worked" ($got -ceq $want) "`n  got  $got`n  want $want"
    $made = @($row.lines | Where-Object { ($nothing + @($data.Vocabulary.nothingToday)) -ccontains [string]$_ })
    Assert-True "unsaid: $($row.slot) says no made-up item" ($made.Count -eq 0) ($made -join ' | ')
}

# The real yesterday: an open item whose work began in the window, or whose card
# threads a commit authored in it -- known only where the dates were read.
foreach ($row in @($proseTable.itemWorked)) {
    $item = [ordered]@{ number = 1; id = $null; title = ''; url = ''; path = ''; motion = [string]$row.motion; commits = [int]$row.commits }
    $got = Test-P20StandupItemWorked -Item $item -Dated ([bool]$row.dated)
    Assert-True "item worked: $($row.motion), $($row.commits) commits, dated $($row.dated)" ($got -eq [bool]$row.worked) "got $got"
}
$workedMotions = (@($proseTable.itemWorked | ForEach-Object { [string]$_.motion } | Sort-Object -Unique)) -join ','
Assert-True 'the item-worked table has a row for every motion' ($workedMotions -ceq ((@($consts.rituals.motions | ForEach-Object { [string]$_ } | Sort-Object -Unique)) -join ',')) $workedMotions

# The chair's own voice: its yesterday (what you walked, else the made-up line at
# the place after the last worker) and its today (what waits, kind by kind).
$queueKinds = @($data.Ceremony.queue | ForEach-Object { [string]$_ })
$chairYesterdays = @($proseTable.chairYesterday)
$foldCap = [int]$consts.rituals.proseFoldNames
$walkedSizes = @($chairYesterdays | ForEach-Object { @($_.walked).Count })
Assert-True 'the chair''s yesterday table has a row each side of every edge' ((@(0, 1, 2, $foldCap, ($foldCap + 1)) | Where-Object { $walkedSizes -notcontains $_ }).Count -eq 0) ($walkedSizes -join ',')
foreach ($row in $chairYesterdays) {
    $got = Get-P20StandupChairYesterday -Walked @($row.walked | ForEach-Object { [string]$_ }) -Day ([int]$row.day) -Workers ([int]$row.workers) -Nothing $nothing
    Assert-True "chair yesterday: $($row.sentence)" ($got -ceq [string]$row.sentence) "got '$got'"
    if (@($row.walked).Count -eq 0) {
        Assert-True "chair yesterday: day $($row.day), $($row.workers) workers is nothing[(d + n) mod len]" ([string]$row.sentence -ceq [string]$nothing[([int]$row.day + [int]$row.workers) % $nothing.Count])
    }
    Assert-True "chair yesterday never says you: $($row.sentence)" ([string]$row.sentence -notmatch '(?i)\byou\b')
}
foreach ($row in @($proseTable.chairToday)) {
    $q = [ordered]@{}
    foreach ($p in $row.queue.PSObject.Properties) {
        $q[[string]$p.Name] = [object[]]@($p.Value | ForEach-Object { , ([object[]]@($_ | ForEach-Object { [string]$_ })) })
    }
    $got = Get-P20StandupChairToday -Queue $q -QueueKinds $queueKinds
    Assert-True "chair today: $($row.sentence)" ($got -ceq [string]$row.sentence) "got '$got'"
    Assert-True "chair today never says you: $($row.sentence)" ([string]$row.sentence -notmatch '(?i)\byou\b')
}

for ($n = 0; $n -lt $proseCases.Count; $n++) {
    $case = $proseCases[$n]
    $name = 'prose-' + [string]$case.name
    $exp = $case.expected
    if ([string]$case.source -eq 'cards') {
        $s = Invoke-P20StandupCardsFill -AsOf $proseAsOf[$n] -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot
    }
    elseif ([string]$case.source -eq 'both') {
        # The joined fill, with the case's dates read when it has one (absent is not read).
        $s = Invoke-P20StandupJoinedFill -AsOf $proseAsOf[$n] -Labels @($proseTable.workerLabels) -Issues @($case.issues) -Tracker $case.tracker `
            -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot `
            -CommitDates (ConvertTo-P20StandupMap $case.commitDates) -IssueStarts (ConvertTo-P20StandupMap $case.issueStarts)
    }
    else {
        $s = Invoke-P20StandupFill -AsOf $proseAsOf[$n] -Labels @($proseTable.workerLabels) -Issues @($case.issues) -Tracker $case.tracker -PackageRoot $pkgRoot
    }
    $want = (@($exp.queue | ForEach-Object { [string]$_ })) -join ' | '
    $got = (@($s.work.queueProse | ForEach-Object { [string]$_ })) -join ' | '
    Assert-True "${name}: the queue's sentences" ($got -ceq $want) "`n  got  $got`n  want $want"
    # The table's rows are the members'; an invented cast member says two made-up
    # items in the same frame, and the golden text holds its line.
    $gotWorkers = @($s.work.workers | Where-Object { -not $_.cast })
    Assert-True "${name}: one prose row per member, in seat order" (((@($gotWorkers | ForEach-Object { $_.label })) -join ',') -ceq ((@($exp.workers | ForEach-Object { $_.label })) -join ',')) ((@($gotWorkers | ForEach-Object { $_.label })) -join ',')
    $offCast = @($s.work.workers | Where-Object { $_.cast } | Where-Object { $p = @($_.prose); $p.Count -ne 5 -or [string]$p[0] -cne [string]$consts.rituals.text.turnOpen -or @($data.Vocabulary.nothing) -cnotcontains [string]$p[1] -or @($data.Vocabulary.nothingToday) -cnotcontains [string]$p[2] -or [string]$p[3] -cne [string]$consts.rituals.text.proseBlockersNone -or [string]$p[4] -cne [string]$consts.rituals.text.turnClose })
    Assert-True "${name}: an invented cast member's turn is two made-up items in the frame" ($offCast.Count -eq 0) ((@($offCast | ForEach-Object { $_.label })) -join ',')
    foreach ($w in @($exp.workers)) {
        $g = @($gotWorkers | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
        $want = (@($w.prose | ForEach-Object { [string]$_ })) -join ' | '
        $got = ''
        if ($g) { $got = (@($g.prose | ForEach-Object { [string]$_ })) -join ' | ' }
        Assert-True "${name}: $($w.label)'s sentences" ($got -ceq $want) "`n  got  $got`n  want $want"
    }
    # The chair's own turn, last, in the workers' frame and its own voice.
    $want = (@($exp.chair | ForEach-Object { [string]$_ })) -join ' | '
    $got = (@($s.work.chairProse | ForEach-Object { [string]$_ })) -join ' | '
    Assert-True "${name}: the chair's own turn" ($got -ceq $want) "`n  got  $got`n  want $want"
    $board = @($s.work.queueProse | ForEach-Object { [string]$_ })
    $echo = @($s.work.chairProse | Where-Object { $board -ccontains [string]$_ -or [string]$_ -match '(?i)\byou\b' })
    Assert-True "${name}: the chair speaks in its own voice: no board sentence again, never you" ($echo.Count -eq 0) ($echo -join ' | ')
    $wantWalked = ''
    if ([string]$case.name -ceq 'walked') { $wantWalked = '530,531' }
    $gotWalked = (@($s.chair.walked | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.number })) -join ','
    Assert-True "${name}: chair.walked is the walk items closed in the window" ($gotWalked -ceq $wantWalked) "got [$gotWalked] want [$wantWalked]"
    # A member with something to say has a yesterday and a today: its sentences, else
    # the slot's fixed line (Get-P20StandupProseUnsaid); never a made-up item.
    $tt = $consts.rituals.text
    $madeUp = @($nothing) + @($data.Vocabulary.nothingToday)
    foreach ($w in @($s.workers | Where-Object { $null -ne $_ -and -not $_.empty -and $false -ne $_.present })) {
        $g = @($gotWorkers | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
        $said = @($g.prose | ForEach-Object { [string]$_ })
        $ok = $said[1].StartsWith('Yesterday I ') -and @($said | Where-Object { $madeUp -ccontains $_ }).Count -eq 0
        if (@($w.today | Where-Object { $null -ne $_ }).Count -eq 0) { $ok = $ok -and ($said -ccontains [string]$tt.proseTodayNone) }
        else { $ok = $ok -and -not ($said -ccontains [string]$tt.proseTodayNone) }
        Assert-True "${name}: $($w.label) says a yesterday and a today, no made-up item" $ok ($said -join ' | ')
    }
    # An idle worker says its two made-up items, then no blockers, in the frame.
    foreach ($w in @($s.workers | Where-Object { $null -ne $_ -and $_.empty })) {
        $g = @($gotWorkers | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
        $tt = $consts.rituals.text
        $want = (@([string]$tt.turnOpen) + @($w.status | ForEach-Object { [string]$_ }) + @([string]$tt.proseBlockersNone, [string]$tt.turnClose)) -join ' | '
        $got = (@($g.prose | ForEach-Object { [string]$_ })) -join ' | '
        Assert-True "${name}: idle $($w.label) says its status in the frame" ($got -ceq $want) "`n  got  $got`n  want $want"
    }
    $text = Format-P20StandupWork -Standup $s -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
    Assert-True "${name}: the work text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    $back = ($s | ConvertTo-Json -Depth 12) | ConvertFrom-Json
    $back.asOf = $s.asOf
    Assert-True "${name}: the JSON round trip renders the same prose" ((Format-P20StandupWork -Standup $back -PackageRoot $pkgRoot) -ceq $text)
    Assert-True "${name}: no fakeWork line in the prose" (@($fakeWork | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
}

# -- 1c''. The model object ----------------------------------------------
# Tests/fixtures/rituals/standup-sessions.json's lookup rows, the SAME rows
# Tests/test_rituals.py asserts from model_object: an id and a session id in,
# the model object or $null out. A known row's name and family are the shipped
# map's own row for the id, so the table does not move when a row is added.
Write-Host ""
Write-Host "-- The model object --" -ForegroundColor Cyan
$sessionsTable = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-sessions.json')) | ConvertFrom-Json
$lookupRows = @($sessionsTable.lookup)
Assert-True 'the sessions table has its lookup rows, each named' ($lookupRows.Count -ge 8 -and @($lookupRows | Where-Object { -not [string]$_.name }).Count -eq 0) "$($lookupRows.Count) rows"
$shippedMap = Get-P20ModelMap
$shippedCurrent = Get-P20ModelCurrent
foreach ($lrow in $lookupRows) {
    $hasId = $null -ne $lrow.PSObject.Properties['id']
    $lid = $null
    if ($hasId) { $lid = [string]$lrow.id }
    $got = Get-P20ModelObject -Id $lid -SessionId ([string]$lrow.sessionId)
    $want = $lrow.expected
    if ($null -eq $want) {
        Assert-True "model object: $($lrow.name)" ($null -eq $got) "got $($got | ConvertTo-Json -Compress)"
        continue
    }
    $wantName = $null
    $wantFamily = $null
    if ([bool]$want.known) {
        $mapRow = $null
        if ($shippedMap.Contains($lid)) { $mapRow = $shippedMap[$lid] }
        Assert-True "model object: $($lrow.name) -- the id has a row in the shipped map" ($null -ne $mapRow) $lid
        if ($null -eq $mapRow) { continue }
        $wantName = [string]$mapRow.name
        $wantFamily = [string]$mapRow.family
        if ($lrow.retired) {
            $cur = [string]$shippedCurrent[$wantFamily]
            Assert-True "model object: $($lrow.name) -- current names another id for its family" ($cur -and $cur -cne $lid) "current.$wantFamily is '$cur'"
        }
    }
    else {
        Assert-True "model object: $($lrow.name) -- the id has no row in the shipped map" (-not $shippedMap.Contains($lid)) $lid
        $wantName = [string]$want.name
        if ($null -ne $want.family) { $wantFamily = [string]$want.family }
    }
    $wantSession = $null
    if ([string]$lrow.sessionId) { $wantSession = [string]$lrow.sessionId }
    $keys = (@($got.PSObject.Properties | ForEach-Object { $_.Name })) -join ','
    $same = ($null -ne $got) -and ($keys -ceq 'id,sessionId,name,family,known') -and ($got.id -ceq $lid) -and ($got.name -ceq $wantName) -and ($got.known -eq [bool]$want.known)
    if ($null -eq $wantSession) { $same = $same -and ($null -eq $got.sessionId) } else { $same = $same -and ($got.sessionId -ceq $wantSession) }
    if ($null -eq $wantFamily) { $same = $same -and ($null -eq $got.family) } else { $same = $same -and ($got.family -ceq $wantFamily) }
    Assert-True "model object: $($lrow.name)" $same "got $($got | ConvertTo-Json -Compress)"
}
foreach ($nm in @($consts.models.notModels)) {
    Assert-True "model object: '$nm' from models.notModels is no object" ($null -eq (Get-P20ModelObject -Id ([string]$nm) -SessionId 'a-session'))
}

# -- 1c'''. The session reader ---------------------------------------------
# standup-sessions.json's inside, porcelain, sessions and privacy sections, the
# SAME rows Tests/test_rituals.py asserts from agent/solitaire/sessions.py. Every
# read is over a scratch projects folder built here; this machine's own Claude
# Code folder is never opened (every call names -ProjectsRoot, or points
# CLAUDE_CONFIG_DIR at a scratch folder and puts it back).
Write-Host ""
Write-Host "-- The session reader --" -ForegroundColor Cyan
. (Join-Path $scriptDir 'Get-TestHost.ps1')
# Timestamps stay text: PowerShell 7 would read an ISO string as a date.
$sessJsonArgs = @{}
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $sessJsonArgs['DateKind'] = 'String' }
$sessTable = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-sessions.json')) | ConvertFrom-Json @sessJsonArgs
$sessText = {
    param($Value)
    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [System.Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}
foreach ($sec in @(@('inside', 12), @('porcelain', 3), @('sessions', 14), @('privacy', 2))) {
    $secRows = @($sessTable.($sec[0]))
    Assert-True "the sessions table has its $($sec[0]) rows, each named" ($secRows.Count -ge $sec[1] -and @($secRows | Where-Object { -not [string]$_.name }).Count -eq 0) "$($secRows.Count) rows"
}
foreach ($irow in @($sessTable.inside)) {
    $got = Test-P20SessionPathInside -Path ([string]$irow.path) -Roots ([string[]]@($irow.roots))
    Assert-True "inside: $($irow.name)" ($got -eq [bool]$irow.expected) "got $got"
}
foreach ($prow in @($sessTable.porcelain)) {
    $got = @(ConvertFrom-P20WorktreePorcelain -Text ([string]$prow.text))
    $want = @($prow.expected | ForEach-Object { [string]$_ })
    Assert-True "porcelain: $($prow.name)" (($got -join '|') -ceq ($want -join '|') -and $got.Count -eq $want.Count) ("got " + ($got -join ' | '))
}

$sessContent = [string]$sessTable.content
$newSessionLine = {
    # One line spec rendered as Claude Code writes a line -- the agent's suite renders the same.
    param($Spec)
    if ($Spec.PSObject.Properties['raw']) { return [string]$Spec.raw }
    $kind = 'assistant'
    if ($Spec.PSObject.Properties['type']) { $kind = [string]$Spec.type }
    $role = 'user'
    if ($kind -eq 'assistant') { $role = 'assistant' }
    $message = [ordered]@{ model = [string]$Spec.model; type = 'message'; role = $role; content = @([ordered]@{ type = 'text'; text = $sessContent }) }
    $line = [ordered]@{ parentUuid = $null; isSidechain = [bool]($Spec.PSObject.Properties['side'] -and $Spec.side); message = $message; type = $kind }
    $line['uuid'] = '00000000-0000-4000-8000-000000000000'
    $line['timestamp'] = & $sessText $Spec.t
    if ($Spec.PSObject.Properties['cwd']) { $line['cwd'] = [string]$Spec.cwd }
    if ($Spec.PSObject.Properties['sid']) { $line['sessionId'] = [string]$Spec.sid }
    return ($line | ConvertTo-Json -Compress -Depth 10)
}
$newSessionTree = {
    # A scratch projects folder from a sessions row. A file's last write is its
    # mtime ([System.IO.File]::SetLastWriteTimeUtc), else the row's asOf.
    param($Row, [string]$Projects, [switch]$NoMtime)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $asOfUtc = (ConvertTo-P20RitualTime $Row.window.asOf).UtcDateTime
    foreach ($p in @($Row.files.PSObject.Properties)) {
        $lines = $p.Value
        $mtime = $asOfUtc
        if ($lines -isnot [System.Array] -and $lines.PSObject.Properties['lines']) {
            if ($lines.PSObject.Properties['mtime'] -and -not $NoMtime) { $mtime = (ConvertTo-P20RitualTime (& $sessText $lines.mtime)).UtcDateTime }
            $lines = $lines.lines
        }
        $path = Join-Path $Projects $p.Name
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $text = ((@($lines) | ForEach-Object { & $newSessionLine $_ }) -join "`n") + "`n"
        [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
        [System.IO.File]::SetLastWriteTimeUtc($path, $mtime)
    }
}
$sessSnapshot = {
    param([string]$Dir)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ((@(Get-ChildItem -LiteralPath $Dir -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
                        "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|" + [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($_.FullName)))
                    })) -join "`n")
    }
    finally { $sha.Dispose() }
}
$sessScratch = Join-Path ([System.IO.Path]::GetTempPath()) ('p20-sessions-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sessScratch -Force | Out-Null
$sessRead = {
    # The reader over one row's scratch folder; the folder must read the same after.
    param($Row, [switch]$NoMtime)
    $projects = Join-Path $sessScratch ('projects-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $projects -Force | Out-Null
    & $newSessionTree $Row $projects -NoMtime:$NoMtime
    $roots = @([string]$Row.checkout)
    if ($Row.PSObject.Properties['worktrees']) { $roots += @($Row.worktrees | ForEach-Object { [string]$_ }) }
    if ($Row.PSObject.Properties['porcelain']) { $roots += @(ConvertFrom-P20WorktreePorcelain -Text ([string]$Row.porcelain)) }
    $before = & $sessSnapshot $projects
    $pairs = @(Get-P20StandupSessionPairs -ProjectsRoot $projects -Since (& $sessText $Row.window.since) -AsOf (& $sessText $Row.window.asOf) -Roots ([string[]]$roots))
    $after = & $sessSnapshot $projects
    return [pscustomobject]@{ Pairs = $pairs; Untouched = ($before -ceq $after) }
}
$pairsText = { param($Pairs) ((@($Pairs) | ForEach-Object { "$($_.id)=$($_.sessionId)" }) -join ', ') }

$privacyRules = @{}
foreach ($pr in @($sessTable.privacy)) { $privacyRules[[string]$pr.rule] = $pr }
Assert-True 'privacy: the two rules, keys and strings' ((@($sessTable.privacy | ForEach-Object { [string]$_.rule } | Sort-Object) -join ',') -ceq 'keys,strings')
$stamped = 0
try {
    foreach ($srow in @($sessTable.sessions)) {
        $read = & $sessRead $srow
        $want = @($srow.expected | Where-Object { $null -ne $_ })
        Assert-True "sessions: $($srow.name)" ((& $pairsText $read.Pairs) -ceq (& $pairsText $want) -and $read.Pairs.Count -eq $want.Count) ("got " + (& $pairsText $read.Pairs))
        Assert-True "sessions: $($srow.name) -- the folder is read-only to the reader" $read.Untouched
        $hasMtime = @($srow.files.PSObject.Properties | Where-Object { $_.Value -isnot [System.Array] -and $_.Value.PSObject.Properties['mtime'] }).Count -gt 0
        if ($hasMtime) {
            # The file's last write is what keeps it out: written at asOf, it counts.
            $stamped++
            $fresh = & $sessRead $srow -NoMtime
            Assert-True "sessions: $($srow.name) -- written at asOf, the same file counts" ($fresh.Pairs.Count -gt 0) 'the stamped line is not in the window'
        }

        # privacy: no key but id and sessionId; no needle and no path segment of the row.
        $allowed = (@($privacyRules['keys'].allowed | ForEach-Object { [string]$_ } | Sort-Object) -join ',')
        $badKeys = @($read.Pairs | Where-Object { (@($_.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join ',') -cne $allowed })
        Assert-True "privacy: $($srow.name) -- a pair carries id and sessionId and nothing else" ($badKeys.Count -eq 0)
        $paths = @([string]$srow.checkout)
        if ($srow.PSObject.Properties['worktrees']) { $paths += @($srow.worktrees | ForEach-Object { [string]$_ }) }
        if ($srow.PSObject.Properties['porcelain']) { $paths += @(ConvertFrom-P20WorktreePorcelain -Text ([string]$srow.porcelain)) }
        foreach ($p in @($srow.files.PSObject.Properties)) {
            $ls = $p.Value
            if ($ls -isnot [System.Array] -and $ls.PSObject.Properties['lines']) { $ls = $ls.lines }
            foreach ($spec in @($ls)) { if ($spec.PSObject.Properties['cwd']) { $paths += [string]$spec.cwd } }
            $paths += ($p.Name -replace '\\', '/').Split('/')[0]
        }
        $needles = @($privacyRules['strings'].needles | ForEach-Object { [string]$_ })
        foreach ($t in $paths) {
            foreach ($seg in @($t -split '[\\/]')) {
                foreach ($piece in @(@($seg) + @($seg.Split('-')))) { if ($piece.Length -ge 4) { $needles += $piece } }
            }
        }
        $wantJson = (ConvertTo-Json -InputObject @($want | ForEach-Object { [string]$_.id; [string]$_.sessionId }) -Compress)
        $gotJson = (ConvertTo-Json -InputObject @($read.Pairs) -Compress -Depth 5)
        $proves = @($needles | Where-Object { $wantJson.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        Assert-True "privacy: $($srow.name) -- no needle is part of an expected pair, so the check has teeth" ($proves.Count -eq 0) ($proves -join ', ')
        $leaks = @($needles | Where-Object { $gotJson.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } | Sort-Object -Unique)
        Assert-True "privacy: $($srow.name) -- no path, folder name or prompt text in the output" ($leaks.Count -eq 0) ($leaks -join ', ')
    }
    Assert-True 'sessions: at least one row is kept out by its file''s last write alone' ($stamped -ge 1)

    # The thin reads: ONE git worktree list in the checkout, a sibling worktree
    # counted, the checkout alone when git fails, and nothing read with no folder.
    $sessRepo = Join-Path $sessScratch 'repo'
    $sessSibling = Join-Path $sessScratch 'repo-wt'
    New-Item -ItemType Directory -Path $sessRepo -Force | Out-Null
    $null = Invoke-P20TestGit -C $sessRepo init --quiet
    $null = Invoke-P20TestGit -C $sessRepo -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit --allow-empty --quiet -m start
    $null = Invoke-P20TestGit -C $sessRepo worktree add --quiet --detach $sessSibling
    $siblingTop = ((Invoke-P20TestGit -C $sessSibling rev-parse --show-toplevel).Out -join '').Trim()
    Assert-True 'the scratch repository has its sibling worktree' ([bool]$siblingTop) $siblingTop

    $realGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    $global:P20SessGitCalls = @()
    $global:P20SessRealGit = $realGit
    function global:git { $global:P20SessGitCalls += , (@($args) -join ' '); & $global:P20SessRealGit @args }
    try {
        $roots = @(Get-P20StandupWorktreeRoots -Checkout $sessRepo)
        $calls = @($global:P20SessGitCalls)
        $global:P20SessGitCalls = @()
        $failRoots = @(Get-P20StandupWorktreeRoots -Checkout $sessScratch)
        $failCalls = @($global:P20SessGitCalls)

        $configDir = Join-Path $sessScratch 'claude'
        $e2e = [pscustomobject]@{
            window = [pscustomobject]@{ since = '2026-11-20T00:00:00-08:00'; asOf = '2026-11-23T09:30:00-08:00' }
            files  = [pscustomobject]@{ '-scratch-repo-wt/cccccccc-0000-4000-8000-000000000001.jsonl' = @([pscustomobject]@{ t = '2026-11-21T10:00:00.000Z'; sid = 'cccccccc-0000-4000-8000-000000000001'; cwd = $siblingTop; model = 'claude-opus-5-5' }) }
        }
        New-Item -ItemType Directory -Path (Join-Path $configDir 'projects') -Force | Out-Null
        & $newSessionTree $e2e (Join-Path $configDir 'projects')
        $savedConfigDir = [System.Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR')
        try {
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $configDir)
            $global:P20SessGitCalls = @()
            $e2ePairs = @(Read-P20StandupSessions -Checkout $sessRepo -Since $e2e.window.since -AsOf $e2e.window.asOf)
            $e2eCalls = @($global:P20SessGitCalls)
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', (Join-Path $sessScratch 'absent'))
            $global:P20SessGitCalls = @()
            $nonePairs = @(Read-P20StandupSessions -Checkout $sessRepo -Since $e2e.window.since -AsOf $e2e.window.asOf)
            $noneCalls = @($global:P20SessGitCalls)
        }
        finally { [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $savedConfigDir) }
    }
    finally {
        Remove-Item Function:\git -ErrorAction SilentlyContinue
        Remove-Variable -Name P20SessGitCalls, P20SessRealGit -Scope Global -ErrorAction SilentlyContinue
    }
    Assert-True 'worktrees: one git worktree list --porcelain in the checkout' ($calls.Count -eq 1 -and $calls[0].StartsWith('-C ') -and $calls[0].EndsWith(' worktree list --porcelain')) ($calls -join ' ; ')
    Assert-True 'worktrees: the checkout first, the sibling worktree a root' ($roots[0] -ceq $sessRepo -and (Test-P20SessionPathInside -Path ($siblingTop + '/web') -Roots $roots) -and -not (Test-P20SessionPathInside -Path (Join-Path $sessScratch 'repo-two') -Roots $roots)) ($roots -join ' | ')
    Assert-True 'worktrees: where git cannot answer, the checkout alone, and nothing thrown' ($failCalls.Count -eq 1 -and $failRoots.Count -eq 1 -and $failRoots[0] -ceq $sessScratch) ($failRoots -join ' | ')
    Assert-True 'sessions read: CLAUDE_CONFIG_DIR''s folder, a session in the sibling worktree counted, one git call' ((& $pairsText $e2ePairs) -ceq 'claude-opus-5-5=cccccccc-0000-4000-8000-000000000001' -and $e2eCalls.Count -eq 1) ((& $pairsText $e2ePairs) + ' / ' + $e2eCalls.Count)
    Assert-True 'sessions read: no projects folder, no pairs and no git call' ($nonePairs.Count -eq 0 -and $noneCalls.Count -eq 0) "$($nonePairs.Count) / $($noneCalls.Count)"
}
catch { Assert-True 'the session reader cases ran to the end without a terminating error' $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $sessScratch -Recurse -Force -ErrorAction SilentlyContinue }

# Nothing calls it yet: no verb, no wrapper, no bridge entry, no other script
# names the reader -- only Scripts/Standup-Rules.ps1, which defines it, and its
# twin agent/solitaire/sessions.py, which names it.
$sessNames = @('Read-P20StandupSessions', 'Get-P20StandupSessionPairs', 'Get-P20StandupWorktreeRoots', 'ConvertFrom-P20WorktreePorcelain', 'Test-P20SessionPathInside')
$sessCallers = @()
foreach ($dir in @('Scripts', 'Prompt20Toolkit', 'Config', 'agent')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $pkgRoot $dir) -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.json', '*.py' -ErrorAction SilentlyContinue)) {
        if ($f.Name -eq 'Standup-Rules.ps1' -or ($f.Name -eq 'sessions.py' -and $f.Directory.Name -eq 'solitaire')) { continue }
        $body = [System.IO.File]::ReadAllText($f.FullName)
        foreach ($n in $sessNames) { if ($body.Contains($n)) { $sessCallers += "$($f.Name): $n" } }
    }
}
$defaultCommands = ([System.IO.File]::ReadAllText((Join-Path $pkgRoot 'config.default.json')) | ConvertFrom-Json).commands
$sessVerb = @($defaultCommands.PSObject.Properties | Where-Object { $_.Name -match 'Session' })
Assert-True 'the session reader has no caller yet: no verb, no wrapper, no route' ($sessCallers.Count -eq 0 -and $sessVerb.Count -eq 0) (($sessCallers + @($sessVerb | ForEach-Object { $_.Name })) -join '; ')

# -- 1c''''. The seats reader ----------------------------------------------
# standup-sessions.json's seats section, the SAME rows Tests/test_rituals.py
# asserts from agent/solitaire/org_seats.py: each row's org.json written to a
# scratch hub and read by the org chart's own reader (Read-P20OrgChart), the
# reader's result handed to Get-P20StandupOrgSeats. A known model is named and
# grouped by the shipped map's own row, so a row added there moves nothing.
Write-Host ""
Write-Host "-- The seats reader --" -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Read-OrgChart.ps1')
$seatRows = @($sessionsTable.seats)
Assert-True 'the sessions table has its seats rows, each named' ($seatRows.Count -ge 13 -and @($seatRows | Where-Object { -not [string]$_.name }).Count -eq 0) "$($seatRows.Count) rows"
$seatText = {
    # One seat as one comparable line; a list of them joined.
    param($Seats)
    return ((@($Seats) | ForEach-Object {
                $m = $_.model
                $keys = (@($m.PSObject.Properties | ForEach-Object { $_.Name })) -join ','
                if ($m -is [System.Collections.IDictionary]) { $keys = (@($m.Keys) -join ',') }
                "$($_.seat)|$($_.position)|$keys|$($m.id)|$(if ($null -eq $m.sessionId) { '<null>' } else { $m.sessionId })|$($m.name)|$(if ($null -eq $m.family) { '<null>' } else { $m.family })|$($m.known)"
            }) -join "`n")
}
$seatScratch = Join-Path ([System.IO.Path]::GetTempPath()) ('p20-seats-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $seatScratch -Force | Out-Null
$utf8Seats = New-Object System.Text.UTF8Encoding($false)
try {
    $seatHeld = 0
    foreach ($trow in $seatRows) {
        $hub = Join-Path $seatScratch ('hub-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $hub -Force | Out-Null
        if ($trow.PSObject.Properties['org']) {
            [System.IO.File]::WriteAllText((Join-Path $hub (Get-P20OrgFileName)), ($trow.org | ConvertTo-Json -Depth 20), $utf8Seats)
        }
        $teamAgile = $true
        if ($trow.PSObject.Properties['teamAgile']) { $teamAgile = [bool]$trow.teamAgile }
        $orgRead = Read-P20OrgChart -PromptsRoot $hub -PackageRoot $pkgRoot
        if ($trow.PSObject.Properties['invalid']) {
            Assert-True "seats: $($trow.name) -- the org reader's verdict" ($orgRead.Status -ceq 'invalid' -and $orgRead.Kind -ceq [string]$trow.invalid) "$($orgRead.Status) $($orgRead.Kind)"
        }
        $got = @(Get-P20StandupOrgSeats -OrgRead $orgRead -Space ([string]$trow.space) -TeamAgile $teamAgile -PackageRoot $pkgRoot)

        $want = @()
        $specOk = $true
        foreach ($w in @($trow.expected | Where-Object { $null -ne $_ })) {
            $spec = $w.model
            $known = $true
            if ($spec.PSObject.Properties['current']) { $mid = [string]$shippedCurrent[[string]$spec.current] }
            else {
                $mid = [string]$spec.id
                if ($spec.PSObject.Properties['known']) { $known = [bool]$spec.known }
            }
            if ($known) {
                if (-not $mid -or -not $shippedMap.Contains($mid)) { $specOk = $false; continue }
                $wm = [ordered]@{ id = $mid; sessionId = $null; name = [string]$shippedMap[$mid].name; family = [string]$shippedMap[$mid].family; known = $true }
            }
            else {
                if ($shippedMap.Contains($mid) -or @($shippedCurrent.Keys | Where-Object { [string]$_ -ieq $mid }).Count -gt 0) { $specOk = $false; continue }
                $wm = [ordered]@{ id = $mid; sessionId = $null; name = $mid; family = $null; known = $false }
            }
            $want += [ordered]@{ seat = [string]$w.seat; position = [string]$w.position; model = $wm }
        }
        Assert-True "seats: $($trow.name) -- a known model has a row in the shipped map, an unknown one none and no current key" $specOk
        Assert-True "seats: $($trow.name)" ((& $seatText $got) -ceq (& $seatText $want) -and $got.Count -eq $want.Count) ("got " + ((& $seatText $got) -replace "`n", ' ; '))

        # The pure rule reads the chart after a JSON round trip the same.
        if ($orgRead.Status -ceq 'ok' -and $teamAgile) {
            $round = ConvertTo-Json -InputObject $orgRead.Chart -Depth 20 | ConvertFrom-Json
            $again = @(ConvertTo-P20StandupOrgSeats -Chart $round -Space ([string]$trow.space) -PackageRoot $pkgRoot)
            Assert-True "seats: $($trow.name) -- the same after a JSON round trip" ((& $seatText $again) -ceq (& $seatText $got))
        }

        # privacy: a seat carries seat, position and model; no machine or person value leaves.
        $badSeat = @($got | Where-Object { (@($_.Keys) -join ',') -cne 'seat,position,model' })
        Assert-True "seats privacy: $($trow.name) -- a seat carries seat, position and model and nothing else" ($badSeat.Count -eq 0)
        $needles = @()
        if ($trow.PSObject.Properties['org']) {
            foreach ($tree in @($trow.org.trees)) {
                if ($tree.PSObject.Properties['machines']) { $needles += @($tree.machines | ForEach-Object { [string]$_ }) }
                foreach ($position in @($tree.positions)) {
                    if (-not $position.PSObject.Properties['seats']) { continue }
                    foreach ($seat in @($position.seats)) {
                        foreach ($k in @('machine', 'person')) { if ($seat.PSObject.Properties[$k] -and ([string]$seat.$k).Trim()) { $needles += ([string]$seat.$k).Trim() } }
                    }
                }
            }
        }
        $seatHeld += $needles.Count
        $wantJson = ConvertTo-Json -InputObject @($want) -Depth 6 -Compress
        $gotJson = ConvertTo-Json -InputObject @($got) -Depth 6 -Compress
        $proves = @($needles | Where-Object { $wantJson.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        Assert-True "seats privacy: $($trow.name) -- no needle is part of the expected seats, so the check has teeth" ($proves.Count -eq 0) ($proves -join ', ')
        $leaks = @($needles | Where-Object { $gotJson.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } | Sort-Object -Unique)
        Assert-True "seats privacy: $($trow.name) -- no machine or person in the output" ($leaks.Count -eq 0) ($leaks -join ', ')
    }
    Assert-True 'seats privacy: the rows hold machines and people to look for' ($seatHeld -gt 0)
    Assert-True 'seats: no result is no seats' (@(Get-P20StandupOrgSeats -OrgRead $null -Space 'alpha').Count -eq 0)
    Assert-True 'seats: no Space is no seats' (@(ConvertTo-P20StandupOrgSeats -Chart ([pscustomobject]@{ tree = [pscustomobject]@{ positions = @() } }) -Space '').Count -eq 0)
}
catch { Assert-True 'the seats reader cases ran to the end without a terminating error' $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $seatScratch -Recurse -Force -ErrorAction SilentlyContinue }

# Nothing calls it yet: no verb, no wrapper, no bridge entry, no other script
# names the seats reader -- only Scripts/Standup-Rules.ps1, which defines it,
# and its twin agent/solitaire/org_seats.py, which names it.
$seatNames = @('Get-P20StandupOrgSeats', 'ConvertTo-P20StandupOrgSeats', 'Resolve-P20SeatModelId')
$seatCallers = @()
foreach ($dir in @('Scripts', 'Prompt20Toolkit', 'Config', 'agent')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $pkgRoot $dir) -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.json', '*.py' -ErrorAction SilentlyContinue)) {
        if ($f.Name -eq 'Standup-Rules.ps1' -or ($f.Name -eq 'org_seats.py' -and $f.Directory.Name -eq 'solitaire')) { continue }
        $body = [System.IO.File]::ReadAllText($f.FullName)
        foreach ($n in $seatNames) { if ($body.Contains($n)) { $seatCallers += "$($f.Name): $n" } }
    }
}
$seatVerb = @($defaultCommands.PSObject.Properties | Where-Object { $_.Name -match 'Seat' })
Assert-True 'the seats reader has no caller yet: no verb, no wrapper, no route' ($seatCallers.Count -eq 0 -and $seatVerb.Count -eq 0) (($seatCallers + @($seatVerb | ForEach-Object { $_.Name })) -join '; ')

# -- 1d'. The team size ----------------------------------------------------
# Tests/fixtures/rituals/standup-team.json, every row and every case, the SAME
# rows Tests/test_rituals.py asserts: a Space's stored teamSize read as the
# room's size; who sits in a room of that size, in which window, and the
# invented cast members that fill the seats left (the size is the team); and a
# fill end to end -- team.size, every worker of the record kept with its
# present, the round, and the detail, the work and the brief against their goldens.
Write-Host ""
Write-Host "-- The team size --" -ForegroundColor Cyan
$teamRaw = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-team.json'))
$teamTable = $teamRaw | ConvertFrom-Json
$teamCases = @($teamTable.cases)
$teamAsOf = @([regex]::Matches($teamRaw, '"asOf"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$teamNames = (@($teamCases | ForEach-Object { [string]$_.name })) -join ','
Assert-True 'the team table is read: its sizes, its seats, its room rows and twenty-three cases, an asOf each' (@($teamTable.sizes).Count -ge 8 -and @($teamTable.seats).Count -ge 6 -and @($teamTable.room).Count -ge 16 -and $teamNames -ceq 'absent,idle-sits,unset,work-unsaid,walk-size-3,walk-size-6,walk-size-9,idle-room,idle-room-3,idle-room-6,agent-line,trailer-only,neither,label-differs,labelled-no-card,no-kept-window,unknown-id,one-family,legacy-size,legacy-backend,slug-is-label-counts,agent-family-is-slug-counts,no-worker-labels-card-seats-member' -and $teamAsOf.Count -eq $teamCases.Count) "$(@($teamTable.sizes).Count) sizes, $(@($teamTable.seats).Count) seats, $(@($teamTable.room).Count) room rows, cases $teamNames"

foreach ($row in @($teamTable.sizes)) {
    $got = Get-P20TeamSize -Stored $row.stored
    Assert-True "size: stored $(ConvertTo-Json -InputObject $row.stored -Compress) reads $($row.size), set $($row.set)" ($got.Size -eq [int]$row.size -and [bool]$got.Set -eq [bool]$row.set) "got $($got.Size), set $($got.Set)"
}
$sizesNow = @($consts.rituals.teamSizes | ForEach-Object { [int]$_ })
Assert-True 'the sizes and the default are the contract''s' ((Get-P20TeamSize -Stored $null).Size -eq [int]$consts.rituals.teamSizeDefault -and @($sizesNow | Where-Object { (Get-P20TeamSize -Stored ([int]$_)).Size -ne $_ }).Count -eq 0) ($sizesNow -join ',')

# Labels only: who sits, said in the workers' own order.
foreach ($row in @($teamTable.seats)) {
    $labels = @(@($row.workers) | ForEach-Object { @{ label = [string]$_.label; empty = [bool]$_.empty } })
    $seated = @((Get-P20StandupRoomSeats -Size ([int]$row.size) -Engineer $null -Labels $labels).present)
    $want = (@($row.present | ForEach-Object { [string]$_ })) -join ','
    $got = (@($row.workers | Where-Object { $seated -ccontains [string]$_.label } | ForEach-Object { [string]$_.label })) -join ','
    Assert-True "seats: $($row.name)" ($got -ceq $want) "got [$got] want [$want]"
}

# The room's rules (docs/modules/solitaire-agile.md, "The room's rules"), each
# stated once, so a failure names the rule it broke; Tests/test_rituals.py states
# the same four over the same rows. Held as scriptblocks, called with &.
$ruleSizeSeen = {
    param([string]$Where, [int]$Size, [int]$Speakers)
    Assert-True "the size seen is the size picked: $Where -- the round and the chair make $Size" (($Speakers + 1) -eq $Size) "got $($Speakers + 1)"
}
$ruleDesks = {
    param([string]$Where, [int]$Size, [int]$Desks)
    $windowCount = @($consts.rituals.room.windows).Count
    Assert-True "the empty desks are only the windows past the size: $Where -- $($windowCount - $Size) desks" ($Desks -eq ($windowCount - $Size)) "got $Desks"
}
$ruleEngineer = {
    param([string]$Where, $Speakers, $Engineer)
    # $Engineer is $null for a fill with none, else @{ label; name } (name optional).
    if ($null -eq $Engineer) { return }
    $first = @($Speakers)[0]
    $ok = ($null -ne $first) -and ([string]$first.label -ceq [string]$Engineer.label) -and (-not [bool]$first.cast)
    if ($ok -and $Engineer.Contains('name')) { $ok = ([string]$first.name -ceq [string]$Engineer.name) }
    Assert-True "the engineer's seat is the owner's: $Where -- first in the round, never invented, under the Space's name" $ok
}
$idlePairs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($y in $nothing) { foreach ($t in $nothingToday) { [void]$idlePairs.Add("$y $t $([string]$consts.rituals.text.proseBlockersNone)") } }
$ruleEveryoneSpeaks = {
    param([string]$Where, $Speakers, [string]$WorkText)
    $open = [string]$consts.rituals.text.turnOpen
    $close = [string]$consts.rituals.text.turnClose
    $lines = @($WorkText -split "`n")
    $at = -1
    $bad = @()
    $place = 0
    $everyone = @($Speakers)
    foreach ($sp in $everyone) {
        $head = [string]$sp.name + ': '
        $found = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith($head, [System.StringComparison]::Ordinal)) { $i } })
        # Members of one name each have a turn: this one is the nth of them, in round order.
        $same = @($everyone | Where-Object { [string]$_.name -ceq [string]$sp.name }).Count
        $nth = @($everyone | Select-Object -First $place | Where-Object { [string]$_.name -ceq [string]$sp.name }).Count
        $place++
        if ($found.Count -ne $same -or $found[$nth] -le $at) { $bad += "$($sp.name): no turn of its own, in round order"; continue }
        $at = $found[$nth]
        $line = $lines[$at].Substring($head.Length)
        if (-not $line.StartsWith("$open ", [System.StringComparison]::Ordinal) -or -not $line.EndsWith(" $close", [System.StringComparison]::Ordinal)) { $bad += "$($sp.name): the turn is not framed"; continue }
        $body = $line.Substring($open.Length + 1, $line.Length - $open.Length - $close.Length - 2)
        if (-not $body.Trim()) { $bad += "$($sp.name): the turn says nothing" }
        elseif ($sp.idle -and -not $idlePairs.Contains($body)) { $bad += "$($sp.name): idle, and the turn is not a made-up pair: $body" }
    }
    Assert-True "everyone speaks: $Where -- every member of the round has a turn in the work grain, an idle one its made-up pair" ($bad.Count -eq 0) ($bad -join '; ')
}

# The size is the team: who sits, each speaker's window, and the desks left.
$roomMembers =@($consts.rituals.room.windows | Where-Object { [string]$_.id -cne [string]$consts.rituals.room.chair } | ForEach-Object { [string]$_.id })
$seatLine = { param($Round) (@($Round | ForEach-Object { "$($_.label)/$([bool]$_.cast)/$($_.window)" })) -join ',' }
foreach ($row in @($teamTable.room)) {
    $labels = @(@($row.labels) | Where-Object { $null -ne $_ } | ForEach-Object { @{ label = [string]$_.label; empty = [bool]$_.empty } })
    $engineer = $null
    if ($null -ne $row.engineer) { $engineer = @{ label = [string]$row.engineer.label; empty = [bool]$row.engineer.empty } }
    $got = Get-P20StandupRoomSeats -Size ([int]$row.size) -Engineer $engineer -Labels $labels
    $wantRound = & $seatLine @($row.round)
    $gotRound = & $seatLine @($got.round)
    $wantRest = ((@($row.present | ForEach-Object { [string]$_ })) -join ',') + ' | ' + ((@($row.desks | ForEach-Object { [string]$_ })) -join ',')
    $gotRest = ((@($got.present | ForEach-Object { [string]$_ })) -join ',') + ' | ' + ((@($got.desks | ForEach-Object { [string]$_ })) -join ',')
    Assert-True "room: $($row.name)" ($gotRound -ceq $wantRound -and $gotRest -ceq $wantRest) "`n  got  $gotRound -- $gotRest`n  want $wantRound -- $wantRest"
    # Every seat the size counts is filled, so the desks are the windows past it;
    # nobody shares a window (a Space's slug may be a worker label: two members, one label).
    $seats = [int]$row.size - 1
    $everyone = $labels.Count
    if ($null -ne $engineer) { $everyone++ }
    $wantCast = $seats - $everyone
    if ($wantCast -lt 0) { $wantCast = 0 }
    $windows = @(@($got.round) | ForEach-Object { [string]$_.window }) + @($got.desks)
    & $ruleSizeSeen "room: $($row.name)" ([int]$row.size) @($got.round).Count
    & $ruleDesks "room: $($row.name)" ([int]$row.size) @($got.desks).Count
    & $ruleEngineer "room: $($row.name)" @($got.round) $engineer
    Assert-True "room: $($row.name) -- $seats seats filled, $($roomMembers.Count - $seats) desks, $wantCast invented" (@($got.round).Count -eq $seats -and @($got.desks).Count -eq ($roomMembers.Count - $seats) -and ((@($windows | Sort-Object)) -join ',') -ceq ((@($roomMembers | Sort-Object)) -join ',') -and @(@($got.round) | ForEach-Object { [string]$_.window } | Sort-Object -Unique).Count -eq $seats -and @(@($got.round) | Where-Object { $_.cast }).Count -eq $wantCast -and @(@($got.round) | Where-Object { $_.cast -and [string]$_.window -cne [string]$_.label }).Count -eq 0) $gotRound
}
$walkRooms = @($teamTable.room | Where-Object { ([string]$_.name).StartsWith('walk-size-') })
Assert-True 'the walk rows are the three rooms: no labels, the engineer with work in its own window, and 1, 4 and 7 invented with 6, 3 and 0 desks' ($walkRooms.Count -eq 3 -and ((@($walkRooms | ForEach-Object { "$($_.size):$(@($_.round | Where-Object { $_.cast }).Count):$(@($_.desks).Count)" })) -join ',') -ceq '3:1:6,6:4:3,9:7:0' -and @($walkRooms | Where-Object { @($_.labels).Count -ne 0 -or [string]$_.round[0].label -cne 'widgets' -or [string]$_.round[0].window -cne [string]$consts.rituals.room.engineer }).Count -eq 0)

for ($n = 0; $n -lt $teamCases.Count; $n++) {
    $case = $teamCases[$n]
    $name = 'team-' + [string]$case.name
    $caseMessages = $null
    $exp = $case.expected
    if ($case.PSObject.Properties['cards']) {
        # A case that states its cards is the joined fill over its own labels, issues and cards,
        # with the trailer read's messages when it states them.
        $caseMessages = $null
        if ($case.PSObject.Properties['messages'] -and $null -ne $case.messages) {
            $caseMessages = @{}
            foreach ($p in @($case.messages.PSObject.Properties)) { $caseMessages[$p.Name] = [string]$p.Value }
        }
        $s = Invoke-P20StandupJoinedFill -AsOf $teamAsOf[$n] -Labels @($case.labels) -Issues @($case.issues) -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) `
            -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot -TeamSize $case.teamSize -Messages $caseMessages
    }
    else {
        $s = Invoke-P20StandupFill -AsOf $teamAsOf[$n] -Labels @($teamTable.workerLabels) -Issues @($case.issues) -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) -Space 'widgets' -PackageRoot $pkgRoot -TeamSize $case.teamSize
    }
    Assert-True "${name}: team.size is $($exp.team.size)" ([int]$s.team.size -eq [int]$exp.team.size) "got $($s.team.size)"
    $want = (@($exp.workers | ForEach-Object { "$($_.label)/$($_.name)/$([bool]$_.empty)/$([bool]$_.present)" })) -join ','
    $got = (@($s.workers | ForEach-Object { "$($_.label)/$($_.name)/$([bool]$_.empty)/$([bool]$_.present)" })) -join ','
    Assert-True "${name}: every worker kept, in label order, each marked present or absent" ($got -ceq $want) "`n  got  $got`n  want $want"
    # A row that states a plate holds it; one that does not wears none.
    $wantPlates = (@($exp.workers | ForEach-Object { $pl = ''; if ($_.PSObject.Properties['plate']) { $pl = [string]$_.plate }; "$($_.label)=$pl" })) -join ','
    $gotPlates = (@($s.workers | ForEach-Object { "$($_.label)=$([string]$_.plate)" })) -join ','
    Assert-True "${name}: each worker's plate" ($gotPlates -ceq $wantPlates) "`n  got  $gotPlates`n  want $wantPlates"
    # Who each card names, and where it came from: the one reader, shipped order.
    if ($exp.PSObject.Properties['agents']) {
        foreach ($ap in @($exp.agents.PSObject.Properties)) {
            $acard = @($case.cards | Where-Object { [string]$_.id -ceq $ap.Name })[0]
            $ans = Resolve-P20CardAgent -Content ([string]$acard.body) -Messages $caseMessages
            $wantA = "$($ap.Value.id)|$($ap.Value.family)|$($ap.Value.source)"
            $gotA = "$($ans.id)|$($ans.family)|$($ans.source)"
            Assert-True "${name}: card $($ap.Name) is $($ap.Value.source)" ($gotA -ceq $wantA) "got $gotA want $wantA"
        }
    }
    # Each member's window, by the room's own rule over the fill's record.
    if ($exp.PSObject.Properties['windows']) {
        $rec = @($s.workers)
        $eng = $rec[$rec.Count - 1]
        $roomNow = Get-P20StandupRoomSeats -Size ([int]$s.team.size) -Engineer @{ label = [string]$eng.label; empty = [bool]$eng.empty } -Labels @($rec[0..($rec.Count - 2)] | ForEach-Object { @{ label = [string]$_.label; empty = [bool]$_.empty } })
        $gotW = (@($roomNow.round | Where-Object { -not $_.cast } | ForEach-Object { "$($_.label)=$($_.window)" } | Sort-Object)) -join ','
        $wantW = (@($exp.windows.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" } | Sort-Object)) -join ','
        Assert-True "${name}: each member's window" ($gotW -ceq $wantW) "got $gotW want $wantW"
    }
    $wantRound = (@($exp.round | ForEach-Object { "$($_.label)/$($_.name)/$([bool]$_.cast)" })) -join ','
    $gotRound = (@($s.work.workers | ForEach-Object { "$($_.label)/$($_.name)/$([bool]$_.cast)" })) -join ','
    Assert-True "${name}: the round is the seated in seat order, then the invented cast members" ($gotRound -ceq $wantRound) "`n  got  $gotRound`n  want $wantRound"
    $seatedNow = (@($s.work.workers | Where-Object { -not $_.cast } | ForEach-Object { [string]$_.label } | Sort-Object)) -join ','
    Assert-True "${name}: the members who speak are the workers marked present" ($seatedNow -ceq ((@($exp.workers | Where-Object { $_.present } | ForEach-Object { [string]$_.label } | Sort-Object)) -join ','))
    $gotCounts = (@($s.counts.workers | ForEach-Object { [string]$_.label })) -join ','
    Assert-True "${name}: the counts keep every worker" ($gotCounts -ceq ((@($exp.workers | ForEach-Object { [string]$_.label })) -join ',')) "got [$gotCounts]"
    $renders = @{
        text  = (Format-P20StandupText -Standup $s -PackageRoot $pkgRoot)
        work  = (Format-P20StandupWork -Standup $s -PackageRoot $pkgRoot)
        brief = (Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot)
    }
    foreach ($grain in @('text', 'work', 'brief')) {
        $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.$grain)))
        Assert-True "${name}: the $grain is $($exp.$grain), byte for byte" ($renders[$grain] -ceq $golden) ("`n--- got ---`n$($renders[$grain])--- want ---`n$golden")
    }
    # The room's rules, over the round as the work grain renders it. An invented
    # member is idle always; a member of the record by its own empty.
    $recordEmpty = @{}
    foreach ($w in @($s.workers)) { $recordEmpty[[string]$w.label] = [bool]$w.empty }
    $speakers = @(@($s.work.workers) | ForEach-Object {
        $idle = [bool]$_.cast
        if (-not $idle) { $idle = (-not $recordEmpty.ContainsKey([string]$_.label)) -or $recordEmpty[[string]$_.label] }
        [pscustomobject]@{ label = [string]$_.label; name = [string]$_.name; cast = [bool]$_.cast; idle = $idle }
    })
    & $ruleSizeSeen $name ([int]$s.team.size) $speakers.Count
    & $ruleDesks $name ([int]$s.team.size) (@($consts.rituals.room.windows).Count - 1 - $speakers.Count)
    & $ruleEveryoneSpeaks $name $speakers $renders.work
    $caseEngineer = $null
    if ($case.PSObject.Properties['cards']) { $caseEngineer = @{ label = [string]$case.space; name = [string]$case.spaceName } }
    & $ruleEngineer $name $speakers $caseEngineer
    # An invented cast member is in the round only: not in the detail, not in the brief.
    $leaked =@($s.work.workers | Where-Object { $_.cast } | Where-Object { -not $renders.work.Contains([string]$_.name + ': ') -or $renders.text.Contains([string]$_.name) -or $renders.brief.Contains([string]$_.name) })
    Assert-True "${name}: an invented cast member has a line in the round and none in the detail or the brief" ($leaked.Count -eq 0) ((@($leaked | ForEach-Object { $_.name })) -join ',')
    # What -AsJson prints is enough to speak the same round.
    $back = ($s | ConvertTo-Json -Depth 12) | ConvertFrom-Json
    $back.asOf = $s.asOf
    Assert-True "${name}: the JSON round trip speaks the same round" ((Format-P20StandupWork -Standup $back -PackageRoot $pkgRoot) -ceq $renders.work)
}
# The idle pick's position is the worker's place in the label order, whoever is
# absent: its made-up items do not move when the room's size does.
$absentCase = @($teamCases | Where-Object { [string]$_.name -eq 'absent' })[0]
$absentAt = $teamAsOf[[array]::IndexOf(@($teamCases | ForEach-Object { [string]$_.name }), 'absent')]
$small = Invoke-P20StandupFill -AsOf $absentAt -Labels @($teamTable.workerLabels) -Issues @($absentCase.issues) -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) -PackageRoot $pkgRoot -TeamSize 3
$whole = Invoke-P20StandupFill -AsOf $absentAt -Labels @($teamTable.workerLabels) -Issues @($absentCase.issues) -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) -PackageRoot $pkgRoot
$smallSaid = (@($small.workers | ForEach-Object { (@($_.status) -join '/') })) -join ' | '
$wholeSaid = (@($whole.workers | ForEach-Object { (@($_.status) -join '/') })) -join ' | '
Assert-True 'an absent worker keeps its made-up items by its label position' ($smallSaid -ceq $wholeSaid) "`n  small $smallSaid`n  whole $wholeSaid"
$cardsRoom = Invoke-P20StandupCardsFill -AsOf $absentAt -Cards @() -Space 's' -PackageRoot $pkgRoot -TeamSize 3
Assert-True 'the cards fill seats the engineer and fills the room: its one tile present, and one invented cast member beside it' ([int]$cardsRoom.team.size -eq 3 -and @($cardsRoom.workers | Where-Object { $_.present }).Count -eq 1 -and ((@($cardsRoom.work.workers | ForEach-Object { "$($_.label)/$([bool]$_.cast)" })) -join ',') -ceq 's/False,ops-dev/True')
# A Space named for one of its worker labels, both with work: two members, both
# present, both in the round.
$sameSlug = Invoke-P20StandupJoinedFill -AsOf $absentAt -Labels @(@{ name = 'opus'; description = 'Routed to Opus -- the crash-through volume' }) -Issues @(@{ number = 801; title = 'Trim the export header'; state = 'OPEN'; labels = @('opus'); closedAt = $null; url = 'https://github.com/acme/widgets/issues/801'; body = ''; milestone = @{ title = 'Phase 6' } }) -Tracker @{ ok = $true; reason = '' } -Cards @($teamCases[4].cards) -Space 'opus' -SpaceName 'Opus' -PackageRoot $pkgRoot -TeamSize 3
Assert-True 'a Space whose slug is a worker label seats the engineer and the worker: two members, both present, both in the round' (@($sameSlug.workers).Count -eq 2 -and @($sameSlug.workers | Where-Object { $_.present }).Count -eq 2 -and ((@($sameSlug.work.workers | ForEach-Object { "$($_.label)/$([bool]$_.cast)" })) -join ',') -ceq 'opus/False,opus/False') ((@($sameSlug.work.workers | ForEach-Object { "$($_.label)/$([bool]$_.cast)" })) -join ',')
# Its brief: the worker gets the in-flight treatment, the engineer (the record's last) its own.
$sameBrief = @((Format-P20StandupBrief -Standup $sameSlug -PackageRoot $pkgRoot) -split "`n" | Where-Object { $_.StartsWith('Opus: ') })
$inFlightSaid = [string]$consts.rituals.text.briefInFlight
Assert-True 'a Space whose slug is a worker label: the brief gives the worker the in-flight line and the engineer its own' ($sameBrief.Count -eq 2 -and $sameBrief[0].Contains($inFlightSaid) -and -not $sameBrief[1].Contains($inFlightSaid)) ($sameBrief -join ' | ')
# A full idle room never repeats a made-up line: eight idle members -- the
# engineer and seven invented -- say two different items each, none repeated on
# one day, and the chair's own made-up yesterday is none of them. Every day of
# a year, leap day included, through the one picker and the chair's.
$repeats = New-Object System.Collections.Generic.List[string]
for ($day = 1; $day -le 366; $day++) {
    $idleRoom = @(1..8 | ForEach-Object { [ordered]@{ label = "m$_"; empty = $true } })
    Set-P20StandupIdle -Workers @($idleRoom[0]) -Day $day -Vocabulary $data.Vocabulary
    Set-P20StandupIdle -Workers @($idleRoom | Select-Object -Skip 1) -Day $day -Vocabulary $data.Vocabulary -Start 1
    $said = @($idleRoom | ForEach-Object { @($_.status) })
    $chairSays = Get-P20StandupChairYesterday -Walked @() -Day $day -Workers 8 -Nothing @($data.Vocabulary.nothing)
    if ($said.Count -ne 16 -or @($said | Sort-Object -Unique).Count -ne 16 -or $said -ccontains [string]$chairSays -or -not $chairSays) { $repeats.Add([string]$day) }
}
Assert-True 'a full idle room never repeats a made-up line, any day of a year: 8 members, 16 lines, and the chair''s is none of them' ($repeats.Count -eq 0) ("days " + ($repeats -join ','))
$idleRoomCase = @($teamCases | Where-Object { [string]$_.name -eq 'idle-room' })[0]
$idleRoomFill = Invoke-P20StandupJoinedFill -AsOf $teamAsOf[[array]::IndexOf(@($teamCases | ForEach-Object { [string]$_.name }), 'idle-room')] -Labels @() -Issues @() -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) -Cards @() -Space ([string]$idleRoomCase.space) -SpaceName ([string]$idleRoomCase.spaceName) -PackageRoot $pkgRoot -TeamSize 9
$idleLines = @($idleRoomFill.work.workers | ForEach-Object { @($_.prose)[1]; @($_.prose)[2] })
Assert-True 'the idle-room case end to end: eight speakers, sixteen different made-up lines, and the chair''s yesterday is none of them' (@($idleRoomFill.work.workers).Count -eq 8 -and @($idleLines | Sort-Object -Unique).Count -eq 16 -and $idleLines -cnotcontains [string]@($idleRoomFill.work.chairProse)[1]) ($idleLines -join ' | ')
# The standup always runs: a day with no work at all -- no labels, no issues, no
# card -- is a case at every size, and the chair still speaks last.
$idleSizes = @()
for ($n = 0; $n -lt $teamCases.Count; $n++) {
    $case = $teamCases[$n]
    if (-not ([string]$case.name).StartsWith('idle-room')) { continue }
    $idleSizes += [int]$case.teamSize
    $quiet = Invoke-P20StandupJoinedFill -AsOf $teamAsOf[$n] -Labels @() -Issues @() -Tracker ([pscustomobject]@{ ok = $true; reason = '' }) -Cards @() -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot -TeamSize $case.teamSize
    $quietWork = Format-P20StandupWork -Standup $quiet -PackageRoot $pkgRoot
    $chairLine = (@($quiet.work.chairProse) | ForEach-Object { [string]$_ }) -join ' '
    Assert-True "the standup always runs: $($case.name) -- no work at all, a room of $($case.teamSize), every speaker idle, and the chair's turn last" (@($case.labels).Count -eq 0 -and @($case.issues).Count -eq 0 -and @($case.cards).Count -eq 0 -and [int]$quiet.team.size -eq [int]$case.teamSize -and @($quiet.workers | Where-Object { -not $_.empty }).Count -eq 0 -and $quietWork.Contains("`n$chairLine`n")) $quietWork
}
Assert-True 'the standup always runs: a day with no work is a case at every size' (((@($idleSizes | Sort-Object)) -join ',') -ceq ((@($consts.rituals.teamSizes | ForEach-Object { [int]$_ } | Sort-Object)) -join ',')) ($idleSizes -join ',')

# -- 1e. The dress guard -----------------------------------------------------
# Tests/fixtures/rituals/standup-dress.json, every row, the SAME rows
# Tests/test_rituals.py asserts against dress_guard: a dressed sentence and its
# group's facts in, '' or the first of rituals.dressGuards it fails out. Only the
# agent calls a model; the guard is the contract, so both halves hold it.

Write-Host "-- The dress guard --" -ForegroundColor Cyan
$dressTable = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'standup-dress.json')) | ConvertFrom-Json
$dressGroups = @($dressTable.groups)
$dressRows = @($dressTable.rows)
$guards = @($consts.rituals.dressGuards | ForEach-Object { [string]$_ })
Assert-True 'the dress table is read: three groups and its rows' ($dressGroups.Count -eq 3 -and $dressRows.Count -gt 0) "$($dressGroups.Count) groups, $($dressRows.Count) rows"
Assert-True 'the vocabulary has its fourth family, verbs, the register''s words' (@($data.Vocabulary.verbs).Count -gt 0 -and @($data.Vocabulary.verbs) -contains 'smashed')
Assert-True 'the standup declares its kinds: bug and enhancement, each with one and many nouns' (((@($data.Ceremony.kinds | ForEach-Object { [string]$_.label })) -join ',') -ceq 'bug,enhancement' -and @($data.Ceremony.kinds | Where-Object { -not $_.one -or -not $_.many }).Count -eq 0)
foreach ($g in $dressGroups) {
    $got = Test-P20StandupDress -Facts $g -Sentence ([string]$g.floor) -PackageRoot $pkgRoot
    Assert-True "dress: $($g.id)'s prose sentence passes its own guard" ($got -ceq '') "got '$got'"
}
foreach ($row in $dressRows) {
    $got = Test-P20StandupDress -Facts $dressGroups[[int]$row.group] -Sentence ([string]$row.sentence) -PackageRoot $pkgRoot
    $want = [string]$row.reason
    $shown = ([string]$row.sentence) -replace "`n", '\n'
    Assert-True "dress: '$shown' is $(if ($want) { $want } else { 'kept' })" ($got -ceq $want) "got '$got'"
}
$reasons = @($dressRows | ForEach-Object { [string]$_.reason } | Where-Object { $_ } | Sort-Object -Unique)
Assert-True 'every reason in the table is a guard of the contract, and every guard has a row' ((@($reasons | Where-Object { $guards -cnotcontains $_ }).Count -eq 0) -and (@($guards | Where-Object { $reasons -cnotcontains $_ }).Count -eq 0)) (($reasons -join ',') + ' vs ' + ($guards -join ','))
$answer = Get-P20DressMap $dressTable.reply.answer
$said = New-Object System.Collections.ArrayList
$dressed = 0
$refused = 0
foreach ($g in $dressGroups) {
    $line = ''
    if ($answer.Contains([string]$g.id)) { $line = ([string]$answer[[string]$g.id]).Trim() }
    if ($line -and -not (Test-P20StandupDress -Facts $g -Sentence $line -PackageRoot $pkgRoot)) { [void]$said.Add($line); $dressed++ }
    else { [void]$said.Add([string]$g.floor); $refused++ }
}
Assert-True 'dress: a reply that names an issue the facts do not hold keeps the prose sentence for that group and the model''s words for the rest' ((($said.ToArray()) -join ' | ') -ceq ((@($dressTable.reply.said | ForEach-Object { [string]$_ })) -join ' | ') -and $dressed -eq [int]$dressTable.reply.dressed -and $refused -eq [int]$dressTable.reply.refused) (($said.ToArray()) -join ' | ')

# -- 1f. The suggestion (AR-3) -------------------------------------------------
# Tests/fixtures/suggestion/table.json, every section, the SAME rows
# Tests/test_rituals.py asserts against agent/solitaire/suggest.py: the nearest
# milestone, the rule (order, pick, shape, sentence, command, exclusions), the
# switch, and the chair's reading end to end against its generated golden.
Write-Host ""
Write-Host "-- The suggestion --" -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Suggest-Rules.ps1')
$suggestDir = Join-Path $scriptDir 'fixtures/suggestion'
$suggestTable = [System.IO.File]::ReadAllText((Join-Path $suggestDir 'table.json')) | ConvertFrom-Json
$suggestRows = @($suggestTable.rows)
$suggestNames = @($suggestRows | ForEach-Object { [string]$_.name })
$wantShapes = @('sev1-beats-a-nearer-milestone', 'two-in-one-milestone-pick-the-older', 'one-left-beats-three-left', 'no-milestone-sorts-last',
    'crew-sized-on-agents-is-a-delegation', 'unrouted-on-agents-is-a-route', 'in-flight-is-excluded', 'not-billable-is-excluded-first',
    'waiting-on-you-is-excluded-before-in-flight', 'the-empty-space', 'a-dismissed-item-yields-the-next')
Assert-True 'the suggestion table has every shape the rule distinguishes' (@($wantShapes | Where-Object { $suggestNames -cnotcontains $_ }).Count -eq 0) ($suggestNames -join ',')
$rowShapes = @($suggestRows | ForEach-Object { [string]$_.expected.shape } | Where-Object { $_ } | Sort-Object -Unique)
$met = @($suggestRows | ForEach-Object { @($_.expected.excluded.PSObject.Properties | ForEach-Object { [string]$_.Value }) } | Sort-Object -Unique)
Assert-True 'every shape and every exclusion of the contract has a row that reaches it' ((($rowShapes) -join ',') -ceq ((@($consts.rituals.suggestShapes | ForEach-Object { [string]$_ } | Sort-Object)) -join ',') -and (($met) -join ',') -ceq ((@($consts.rituals.suggestExclusions | ForEach-Object { [string]$_ } | Sort-Object)) -join ',')) "shapes [$($rowShapes -join ',')] exclusions [$($met -join ',')]"
foreach ($row in @($suggestTable.nearest)) {
    $order = @(Get-P20NearestMilestones -Milestones @($row.milestones))
    $want = (@($row.order | ForEach-Object { [string]$_ })) -join ' | '
    $first = ''
    if ($order.Count -gt 0) { $first = $order[0] }
    Assert-True "nearest: $($row.name)" ((($order) -join ' | ') -ceq $want -and $first -ceq [string]$row.nearest) "got [$($order -join ' | ')]"
}
foreach ($row in $suggestRows) {
    $dismissed = [string[]]@($row.dismissed | ForEach-Object { [string]$_ })
    $chosen = Select-P20Suggestion -Items @($row.items) -HowIWork ([string]$row.howIWork) -Dismissed $dismissed -PackageRoot $pkgRoot -Launch ([bool]$row.launch)
    $exp = $row.expected
    $gotOrder = (@($chosen.picked | ForEach-Object { $_.ref })) -join ','
    $wantOrder = (@($exp.order | ForEach-Object { [string]$_ })) -join ','
    $gotEx = (@($chosen.excluded.Keys | ForEach-Object { "$_=$($chosen.excluded[$_])" } | Sort-Object)) -join ','
    $wantEx = (@($exp.excluded.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" } | Sort-Object)) -join ','
    $ok = ($gotOrder -ceq $wantOrder -and $gotEx -ceq $wantEx)
    $detail = "order [$gotOrder] excluded [$gotEx]"
    if ($null -eq $exp.pick) { $ok = $ok -and @($chosen.picked).Count -eq 0 }
    else {
        $p = @($chosen.picked)[0]
        $ok = $ok -and $p.ref -ceq [string]$exp.pick -and $p.shape -ceq [string]$exp.shape -and $p.sentence -ceq [string]$exp.sentence -and $p.command -ceq [string]$exp.command
        $detail += " pick $($p.ref)/$($p.shape) '$($p.sentence)' '$($p.command)'"
    }
    Assert-True "suggest: $($row.name)" $ok $detail
}
foreach ($row in @($suggestTable.switch)) {
    $got = Test-P20SuggestionsOn -TeamAgile $row.solitaireAgile -Stored $row.suggestions
    Assert-True "switch: Team Agile $($row.solitaireAgile), suggestions $($row.suggestions) -> $($row.on)" ($got -eq [bool]$row.on) "got $got"
}
$sb = $suggestTable.briefs
$sbAsOf = ([regex]::Match([System.IO.File]::ReadAllText((Join-Path $suggestDir 'table.json')), '"briefs"\s*:\s*\{\s*"asOf"\s*:\s*"([^"]+)"')).Groups[1].Value
foreach ($case in @($sb.cases)) {
    $s = Invoke-P20StandupJoinedFill -AsOf $sbAsOf -Labels @($sb.workerLabels) -Issues @($case.issues) -Tracker @{ ok = $true; reason = '' } `
        -Cards @($case.cards) -Space ([string]$sb.space) -SpaceName ([string]$sb.spaceName) -PackageRoot $pkgRoot
    $on = Test-P20SuggestionsOn -TeamAgile $true -Stored $case.suggestions
    $null = Add-P20StandupSuggestion -Standup $s -Labels @($sb.workerLabels) -Issues @($case.issues) -Cards @($case.cards) -HowIWork ([string]$case.howIWork) -On $on -Prefix ([string]$sb.prefix) -PackageRoot $pkgRoot
    $gotOrder = (@($s.suggestions | ForEach-Object { $_.ref })) -join ','
    $wantOrder = (@($case.expected.order | ForEach-Object { [string]$_ })) -join ','
    $pick = $null
    if ($null -ne $s.suggestion) { $pick = $s.suggestion.ref }
    Assert-True "brief $($case.name): the candidates [$wantOrder] and the pick" ($gotOrder -ceq $wantOrder -and "$pick" -ceq "$($case.expected.pick)") "got [$gotOrder] pick $pick"
    $brief = Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $suggestDir ([string]$case.expected.brief)))
    Assert-True "brief $($case.name): $($case.expected.brief), byte for byte" ($brief -ceq $golden) ("`n--- got ---`n$brief--- want ---`n$golden")
    $back = ($s | ConvertTo-Json -Depth 10) | ConvertFrom-Json
    $back.asOf = $s.asOf
    $back.since = $s.since
    Assert-True "brief $($case.name): the JSON round trip renders the same brief" ((Format-P20StandupBrief -Standup $back -PackageRoot $pkgRoot) -ceq $brief)
}
# Who "me" is: an assignee who is the signed-in gh user reads me (triage's rule) and
# is a candidate; another is @<login>, excluded theirs; no viewer, every assignee theirs.
$viewIssues = @(
    [pscustomobject]@{ number = 7; title = 'Mine'; state = 'OPEN'; labels = @(); assignees = @([pscustomobject]@{ login = 'Me-Dev' }) },
    [pscustomobject]@{ number = 8; title = 'Theirs'; state = 'OPEN'; labels = @(); assignees = @('octocat') }
)
$viewItems = @(Get-P20SuggestionItems -Labels @($sb.workerLabels) -Issues $viewIssues -Cards @() -Viewer 'me-dev' -PackageRoot $pkgRoot)
$viewPick = Select-P20Suggestion -Items $viewItems -HowIWork 'agents' -PackageRoot $pkgRoot
$blindPick = Select-P20Suggestion -Items @(Get-P20SuggestionItems -Labels @($sb.workerLabels) -Issues $viewIssues -Cards @() -PackageRoot $pkgRoot) -HowIWork 'agents' -PackageRoot $pkgRoot
$viewWho = (@($viewItems | ForEach-Object { $_.who })) -join ','
Assert-True 'who "me" is: the viewer''s issue reads me and is the pick; another''s is excluded theirs; no viewer, both theirs' ($viewWho -ceq "$([string]$consts.rituals.assignMe),@octocat" -and (@($viewPick.picked | ForEach-Object { $_.ref }) -join ',') -ceq '#7' -and $viewPick.excluded['#8'] -ceq 'theirs' -and @($blindPick.picked).Count -eq 0 -and $blindPick.excluded['#7'] -ceq 'theirs') "who [$viewWho]"
$cardTable = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/parsers/card-milestone.json')) | ConvertFrom-Json
foreach ($row in @($cardTable.rows)) {
    $eol = "`n"
    if ($row.crlf) { $eol = "`r`n" }
    $text = ((@($row.lines | ForEach-Object { [string]$_ })) -join $eol) + $eol
    $gotM = Get-P20CardMilestone $text
    $gotG = Test-P20CardMilestoneFromGitHub $text
    $gotS = Get-P20CardSprint $text
    $gotT = (@(Get-P20CardTags $text)) -join '|'
    Assert-True "a card's milestone, its source, sprint and tags: $($row.name)" ($gotM -ceq [string]$row.milestone -and $gotG -eq [bool]$row.github -and $gotS -ceq [string]$row.sprint -and $gotT -ceq ((@($row.tags | ForEach-Object { [string]$_ })) -join '|')) "got '$gotM' $gotG '$gotS' [$gotT]"
}
Assert-True "the card-milestone table has both sources: a GitHub issue's milestone on a card's Sprint line, and a GitHub card's own Milestone line, a release" (
    @($cardTable.rows | Where-Object { $_.github -eq $true }).Count -gt 0 -and
    @($cardTable.rows | Where-Object { $_.github -eq $false -and [string]$_.milestone -and (@($_.lines) -like '*github.com*') }).Count -gt 0) ''
Assert-True 'the card-milestone table has every shape: an old card read through its sprint line, both lines, a placeholder milestone' (
    @($cardTable.rows | Where-Object { -not (@($_.lines) -like '[*][*]Milestone:[*][*]*') -and [string]$_.milestone }).Count -gt 0 -and
    @($cardTable.rows | Where-Object { [string]$_.milestone -and [string]$_.sprint -and ([string]$_.milestone -cne [string]$_.sprint) }).Count -gt 0 -and
    @($cardTable.rows | Where-Object { -not [string]$_.milestone -and [string]$_.sprint }).Count -gt 0) ''


# -- 1g. The PM Corner (AR-4) ----------------------------------------------------
# Tests/fixtures/rituals/corner.json, both sections, the SAME rows
# Tests/test_rituals.py asserts against agent/solitaire/corner.py: the line from
# the raw read (each card given as its file's lines, read through the one card
# reader -- its **Sprint:** line WHOLE), and the chair's reading end to end
# against its generated golden.
Write-Host ""
Write-Host "-- The PM Corner --" -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Corner-Rules.ps1')
$cornerText = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'corner.json'))
$cornerTable = $cornerText | ConvertFrom-Json
# The table's two instants, as their text: 7's ConvertFrom-Json may hand back a [datetime].
$cornerAsOf = ([regex]::Match($cornerText, '"asOf"\s*:\s*"([^"]+)"')).Groups[1].Value
$cornerSince = ([regex]::Match($cornerText, '"since"\s*:\s*"([^"]+)"')).Groups[1].Value
function ConvertTo-CornerCardRows {
    # corner.json's cards, each given as its file's lines, as the card rows
    # Get-P20StandupCards makes -- through the one card reader each field has.
    param($Cards)
    $rows = New-Object System.Collections.ArrayList
    foreach ($card in @($Cards)) {
        if ($null -eq $card) { continue }
        $text = ((@($card.lines | ForEach-Object { [string]$_ })) -join "`n") + "`n"
        [void]$rows.Add([ordered]@{
                file = [string]$card.file; folder = [string]$card.folder; status = [string]$card.status
                closed = $card.closed; id = [string]$card.id; title = [string]$card.title; created = $card.created
                sprint = (Get-P20CardMilestone $text); milestoneFromGitHub = (Test-P20CardMilestoneFromGitHub $text); tags = [object[]]@(Get-P20CardTags $text)
                assigned = (Get-P20CardAssigned $text); billable = (Test-P20CardBillable $text)
            })
    }
    return $rows.ToArray()
}
$cornerRows = @($cornerTable.rows)
$cornerNames = @($cornerRows | ForEach-Object { [string]$_.name })
$wantCorner = @('one-left', 'several-left', 'reached', 'nothing-in-reach', 'a-card-and-its-issue-counted-once',
    'a-card-and-an-issue-are-items-and-a-long-title-is-read-whole')
Assert-True 'the Corner table has every shape the card names' (@($wantCorner | Where-Object { $cornerNames -cnotcontains $_ }).Count -eq 0) ($cornerNames -join ',')
$cornerShapesMet = @($cornerRows | ForEach-Object { [string]$_.expected.shape } | Sort-Object -Unique)
Assert-True 'every Corner shape of the contract has a row that reaches it' ((($cornerShapesMet) -join ',') -ceq ((@($consts.rituals.cornerShapes | ForEach-Object { [string]$_ } | Sort-Object)) -join ',')) ($cornerShapesMet -join ',')
foreach ($row in $cornerRows) {
    $cards = @(ConvertTo-CornerCardRows $row.cards)
    $items = @(Get-P20SuggestionItems -Labels @($cornerTable.workerLabels) -Issues @($row.issues) -Cards $cards -PackageRoot $pkgRoot)
    $closed = @(Get-P20CornerClosed -Issues @($row.issues) -Cards $cards -Since $cornerSince -AsOf $cornerAsOf)
    # howIWork and launch are the row's when it names them: alone and off otherwise.
    $rowHow = 'alone'
    if ($row.PSObject.Properties['howIWork']) { $rowHow = [string]$row.howIWork }
    $got = Get-P20CornerLine -Items $items -Closed $closed -PackageRoot $pkgRoot -HowIWork $rowHow -Launch ([bool]$row.launch)
    $exp = $row.expected
    $ok = ($got.shape -ceq [string]$exp.shape -and $got.milestone -ceq [string]$exp.milestone -and [int]$got.remaining -eq [int]$exp.remaining -and
        $got.ref -ceq [string]$exp.ref -and $got.kind -ceq [string]$exp.kind -and $got.noun -ceq [string]$exp.noun -and
        $got.line -ceq [string]$exp.line -and $got.command -ceq [string]$exp.command)
    Assert-True "corner: $($row.name)" $ok "got $($got.shape) '$($got.milestone)' $($got.remaining) $($got.ref)/$($got.kind) '$($got.noun)' '$($got.line)' '$($got.command)'"
}
$longRow = @($cornerRows | Where-Object { ([string]$_.name).EndsWith('long-title-is-read-whole') })[0]
Assert-True 'corner: the long milestone is longer than twenty characters and its card counts toward it -- the Sprint line is read whole' (([string]$longRow.expected.milestone).Length -gt 20 -and [int]$longRow.expected.remaining -eq 2)
$cb = $cornerTable.briefs
foreach ($case in @($cb.cases)) {
    $cards = @(ConvertTo-CornerCardRows $case.cards)
    $s = Invoke-P20StandupJoinedFill -AsOf $cornerAsOf -Labels @($cornerTable.workerLabels) -Issues @($case.issues) -Tracker @{ ok = $true; reason = '' } `
        -Cards $cards -Space ([string]$cb.space) -SpaceName ([string]$cb.spaceName) -PackageRoot $pkgRoot
    $on = Test-P20SuggestionsOn -TeamAgile $true -Stored $case.suggestions
    $null = Add-P20StandupSuggestion -Standup $s -Labels @($cornerTable.workerLabels) -Issues @($case.issues) -Cards $cards -HowIWork ([string]$case.howIWork) -On $on -Prefix ([string]$cb.prefix) -PackageRoot $pkgRoot -Launch ([bool]$case.launch)
    $null = Add-P20StandupCorner -Standup $s -Labels @($cornerTable.workerLabels) -Issues @($case.issues) -Cards $cards -On $on -Prefix ([string]$cb.prefix) -PackageRoot $pkgRoot -HowIWork ([string]$case.howIWork) -Launch ([bool]$case.launch)
    $gotShape = $null
    if ($null -ne $s.corner) { $gotShape = $s.corner.shape }
    Assert-True "corner brief $($case.name): the shape" ("$gotShape" -ceq "$($case.expected.shape)") "got $gotShape"
    if ($null -ne $s.corner -and $s.corner.command -and $null -ne $s.suggestion -and [string]$s.suggestion.ref -ceq [string]$s.corner.ref -and [string]$s.suggestion.shape -ceq [string]@($consts.rituals.suggestShapes)[1]) {
        Assert-True "corner brief $($case.name): the Corner and the suggestion name one command for the pick they share" ([string]$s.corner.command -ceq [string]$s.suggestion.command) "corner '$($s.corner.command)', suggestion '$($s.suggestion.command)'"
    }
    $brief = Format-P20StandupBrief -Standup $s -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$case.expected.brief)))
    Assert-True "corner brief $($case.name): $($case.expected.brief), byte for byte" ($brief -ceq $golden) ("`n--- got ---`n$brief--- want ---`n$golden")
    $back = ($s | ConvertTo-Json -Depth 10) | ConvertFrom-Json
    $back.asOf = $s.asOf
    $back.since = $s.since
    Assert-True "corner brief $($case.name): the JSON round trip renders the same brief" ((Format-P20StandupBrief -Standup $back -PackageRoot $pkgRoot) -ceq $brief)
}

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-rituals-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# One instant for the whole typed section. The verb runs in a child process, so
# an expectation built from this process's clock is a second reading of now, and
# the two disagree when a run crosses midnight. The suite reads the clock once,
# to the second, hands that text to every child (Invoke-Standup) and builds every
# expectation from it. The name is the contract's (consts.json env.standupAsOf).
# Set in the environment of a suite run on its own, it names the instant instead,
# which is how a run is put a second before midnight; a runner removes it first.
$pinName = [string]$consts.env.standupAsOf
$pin = ConvertTo-P20RitualTime ([string][System.Environment]::GetEnvironmentVariable($pinName))
if ($null -eq $pin) { $pin = [DateTimeOffset]::Now }
$pinText = Format-P20RitualTime $pin
$pin = ConvertTo-P20RitualTime $pinText

function Invoke-Standup {
    # A fresh shell per call: gh replaced by a function that answers from the
    # scratch files (and fails when P20_TEST_GH_DOWN is set), then the package's
    # own manifest and nothing else, the way a person types a verb (AGENTS.md,
    # "One toolkit per shell").
    param([string]$Snippet, [bool]$On = $true, [switch]$GhDown, [string]$AsOf = $pinText, [bool]$Marker = $true)
    $features = '{}'
    if ($On) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"widgets`", `"quietStart`": true, `"features`": $features }", $utf8)
    $q = { param($p) $p -replace "'", "''" }
    # One instant for the verb and the expectation: the child reads the suite's
    # pin and not its own clock, which the verb honours only in a test run.
    $clock = "`$env:$([string]$consts.env.testRunMarker) = '1'`n`$env:$pinName = '$AsOf'`n"
    if (-not $Marker) { $clock = "Remove-Item Env:\$([string]$consts.env.testRunMarker) -ErrorAction SilentlyContinue`n`$env:$pinName = '$AsOf'`n" }
    # The stub's commit dates are counted from the same instant, never from the
    # child's clock, so a commit a minute old cannot land after the pin.
    $stubAt = ConvertTo-P20RitualTime $AsOf
    if ($null -eq $stubAt) { $stubAt = $pin }
    $stubAt = $stubAt.ToUniversalTime()
    $stubWhen = $stubAt.AddMinutes(-1).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    $stubOld = $stubAt.AddDays(-30).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    $down = ''
    if ($GhDown) { $down = "`$env:P20_TEST_GH_DOWN = '1'`n" }
    $body = $down + $clock + @"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { `$null = `$_ }
`$env:PSModulePath = '$(& $q $pkg)'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$(& $q $logDir)'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:gh {
    if (`$env:P20_TEST_GH_DOWN) { `$global:LASTEXITCODE = 1; Write-Error 'HTTP 502: the tracker is down'; return }
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'label' -and `$args[1] -eq 'list') { return (Get-Content -Raw -LiteralPath '$(& $q (Join-Path $scratch 'labels.json'))') }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'list') { return (Get-Content -Raw -LiteralPath '$(& $q (Join-Path $scratch 'issues.json'))') }
    if (`$args[0] -eq 'api' -and `$args[1] -eq 'graphql') {
        # The dates read: every hash asked for authored a minute before the pinned instant -- one starting d7, thirty days before it -- and every issue a timeline with no event.
        `$query = Get-Content -Raw -Encoding UTF8 -LiteralPath ((@(`$args) | Where-Object { "`$_" -like 'query=@*' } | Select-Object -First 1).Substring(7))
        `$when = '$stubWhen'
        `$old = '$stubOld'
        `$repo = [ordered]@{}
        foreach (`$m in [regex]::Matches(`$query, '\b([ct]\d+): object\(expression: "([0-9a-f]+)"\)')) {
            `$at = `$when
            if (`$m.Groups[2].Value.StartsWith('d7')) { `$at = `$old }
            `$repo[`$m.Groups[1].Value] = [ordered]@{ oid = `$m.Groups[2].Value.PadRight(40, '0'); authoredDate = `$at }
            # A t alias is a trailer read: its commit's message, with no trailer.
            if (`$m.Groups[1].Value.StartsWith('t')) { `$repo[`$m.Groups[1].Value]['message'] = 'A commit' }
        }
        foreach (`$m in [regex]::Matches(`$query, '\b(i\d+): issue\(')) { `$repo[`$m.Groups[1].Value] = [ordered]@{ timelineItems = [ordered]@{ nodes = @() } } }
        return (ConvertTo-Json -InputObject ([ordered]@{ data = [ordered]@{ repository = `$repo } }) -Depth 6 -Compress)
    }
    return ''
}
Import-Module '$(& $q $pkg)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
'<<<'
$Snippet
'>>>'
'EXIT=' + `$LASTEXITCODE
"@
    $runner = Join-Path $scratch ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    [System.IO.File]::WriteAllText($runner, $body, $utf8)
    # The child's stdout is decoded with the console's code page, so a launch
    # from a non-UTF-8 console (Git bash on Windows) turned the title's em dash
    # into '-'. Both ends are UTF-8 for the call, whatever launched the suite.
    $priorEncoding = $null
    try { $priorEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $priorEncoding = $null }
    try {
        $out = (& pwsh -NoProfile -NonInteractive -File $runner 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    finally {
        if ($null -ne $priorEncoding) { try { [Console]::OutputEncoding = $priorEncoding } catch { $null = $_ } }
    }
    $inner = ''
    $m = [regex]::Match($out, '(?s)<<<\n(.*?)\n?>>>')
    if ($m.Success) { $inner = $m.Groups[1].Value }
    $code = ''
    $mc = [regex]::Match($out, 'EXIT=(\d*)')
    if ($mc.Success) { $code = $mc.Groups[1].Value }
    return [pscustomobject]@{ All = $out; Inner = $inner; Exit = $code }
}

function Get-HubSnapshot {
    return ((@(Get-ChildItem -LiteralPath $hub -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })) -join "`n")
}

try {
    New-Item -ItemType Directory -Path $pkg, $logDir, (Join-Path $hub 'widgets/current') -Force | Out-Null
    foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
    [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'), @'
{
  "hub": 1,
  "spaces": [
    { "slug": "widgets", "name": "Widgets", "status": "active", "promptsFolder": "widgets", "org": "https://github.com/acme/widgets", "howIWork": "agents" },
    { "slug": "board",   "name": "Board",   "status": "active", "promptsFolder": "board",   "org": "https://dev.azure.com/acme-org" },
    { "slug": "solo",    "name": "Solo Work", "status": "local", "promptsFolder": "solo",   "org": "" }
  ]
}
'@, $utf8)

    # What the stub answers: the friday case's labels and issues, in gh's own
    # shape (labels as objects), with each closedAt moved to now -- one minute
    # ago for the issues the table puts in yesterday, thirty days ago for the
    # rest -- so the verb, reading the pinned clock, fills the same slots.
    $friday = @($cases | Where-Object { $_.name -eq 'friday' })[0]
    $yesterdayNumbers = @($friday.expected.workers | ForEach-Object { @($_.yesterday) } | ForEach-Object { [int]$_ })
    $now = $pin.ToUniversalTime()
    $ghIssues = @(foreach ($iss in @($friday.issues)) {
            $closedAt = $null
            if ([string]$iss.state -eq 'CLOSED') {
                $when = $now.AddDays(-30)
                if ($yesterdayNumbers -contains [int]$iss.number) { $when = $now.AddMinutes(-1) }
                $closedAt = $when.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            [ordered]@{
                number   = [int]$iss.number
                title    = [string]$iss.title
                state    = [string]$iss.state
                labels   = [object[]]@(@($iss.labels) | ForEach-Object { [ordered]@{ name = [string]$_ } })
                closedAt = $closedAt
                url      = [string]$iss.url
            }
        })
    $ghLabels = @($fixture.workerLabels | ForEach-Object { [ordered]@{ name = [string]$_.name; description = [string]$_.description } })
    [System.IO.File]::WriteAllText((Join-Path $scratch 'labels.json'), (ConvertTo-Json -InputObject ([object[]]$ghLabels) -Depth 4), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issues.json'), (ConvertTo-Json -InputObject ([object[]]$ghIssues) -Depth 5), $utf8)

    # -- 4. Off means absent -----------------------------------------------------
    Write-Host ""
    Write-Host "-- Off: no verb ----------------------------------------" -ForegroundColor Cyan
    $off = Invoke-Standup "'VERB=' + [bool](Get-Command tkStandup -ErrorAction SilentlyContinue); 'FN=' + [bool](Get-Command Get-P20Standup -ErrorAction SilentlyContinue); 'MAP=' + (Get-P20CommandMap); tkMenu -All" -On $false
    Assert-True 'with the flag off Standup does not exist' ($off.Inner -match 'VERB=False') $off.All
    Assert-True 'nor does its function' ($off.Inner -match 'FN=False') $off.All
    Assert-True 'the bridge has nothing to call' ($off.Inner -notmatch '"Standup"') $off.Inner
    Assert-True 'and Menu -All has no Standup line' ($off.Inner -notmatch '(?m)^\s+tkStandup\b') $off.Inner

    # -- 5. The verb, as typed ----------------------------------------------------
    Write-Host ""
    Write-Host "-- On: the verb, as typed -------------------------------" -ForegroundColor Cyan
    $on = Invoke-Standup "'MAP=' + (Get-P20CommandMap); tkMenu -All"
    Assert-True 'with the flag on the bridge can call Standup' ($on.Inner -match '"Standup"') $on.Inner
    Assert-True 'and Menu -All lists it, under its own heading' ($on.Inner -match '(?m)^\s+tkStandup\s' -and $on.Inner -match ('(?m)^\s+' + [regex]::Escape('Team Agile') + '\s*$')) $on.Inner

    $before = Get-HubSnapshot
    $r = Invoke-Standup 'tkStandup'
    $after = Get-HubSnapshot
    # An active GitHub Space reads both; its folder has no card yet, so the text is the issues' alone.
    $expectNow = Invoke-P20StandupJoinedFill -AsOf $pin -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
    $expectText = (Format-P20StandupText -Standup $expectNow -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True 'Standup exits 0' ($r.Exit -eq '0') $r.All
    # A launch from a non-UTF-8 console (Git bash on Windows, code page 437)
    # must not cost the title its em dash.
    $emDash = [string][char]0x2014
    Assert-True 'the rendered title carries an em dash (the premise of the next case)' $expectText.Contains($emDash)
    $launchEncoding = $null
    try { $launchEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437) } catch { $launchEncoding = $null }
    $oem = Invoke-Standup 'tkStandup'
    if ($null -ne $launchEncoding) { try { [Console]::OutputEncoding = $launchEncoding } catch { $null = $_ } }
    Assert-True 'under a code page 437 console the em dash survives the child''s output' ($oem.Inner.Contains($emDash)) $oem.Inner
    Assert-True 'and prints the text the rule renders for now, line for line' ($r.Inner -ceq $expectText) ("`n--- got ---`n$($r.Inner)`n--- want ---`n$expectText")
    Assert-True 'the queue first: both open verify-close issues, worker or none' ($r.Inner -match '(?m)^  Walk {7}#104 ' -and $r.Inner -match '(?m)^  Walk {7}#105 ') $r.Inner
    Assert-True 'one block per worker label found in the labels'' own descriptions' ($r.Inner -match '(?s)\nFable\n.*\nOpus\n.*\nSonnet\n') $r.Inner
    Assert-True 'a closed issue a minute ago is yesterday, the slot saying closed; a month ago is nowhere' ($r.Inner -match '(?m)^  Yesterday  #102 Rename the slug$' -and $r.Inner -notmatch '#103') $r.Inner
    Assert-True 'a blocker carries the walk label''s suffix, and no in-progress word the slot already says' ($r.Inner -match ('#104 Verify the Studio tab draws on the PC' + [regex]::Escape([string]$consts.rituals.text.blockerSuffix))) $r.Inner
    Assert-True 'an open issue with no worker and no walk label appears nowhere' ($r.Inner -notmatch '#106') $r.Inner
    Assert-True 'no fakeWork line reaches the terminal' (@($fakeWork | Where-Object { $r.Inner.Contains([string]$_) }).Count -eq 0)
    Assert-True 'nothing is written to the hub' ($before -ceq $after)

    # The pin itself: a second before midnight on a day long gone, the verb's title
    # is that day's and not the next; and outside a test run it is not read at all.
    $lateText = '2001-03-09T23:59:59+00:00'
    $lateTitle = ([string]$consts.rituals.text.title).Replace('{date}', (ConvertTo-P20RitualTime $lateText).ToString([string]$consts.rituals.text.dateFormat, [System.Globalization.CultureInfo]::InvariantCulture))
    $late = Invoke-Standup 'tkStandup' -AsOf $lateText
    Assert-True 'pinned a second before midnight, the standup is that day''s' ($late.Exit -eq '0' -and (@($late.Inner -split "`n")[0]) -ceq $lateTitle) ("`n--- got ---`n$($late.Inner)`n--- want ---`n$lateTitle")
    $unpinned = Invoke-Standup 'tkStandup' -AsOf $lateText -Marker $false
    Assert-True 'outside a test run the pin is not read: the standup is not that day''s' ($unpinned.Exit -eq '0' -and $unpinned.Inner -match '^Standup ' -and -not $unpinned.Inner.Contains('2001')) $unpinned.Inner

    $j = Invoke-Standup 'tkStandup -AsJson'
    $parsed = $null
    try { $parsed = $j.Inner | ConvertFrom-Json } catch { $parsed = $null }
    Assert-True '-AsJson prints JSON' ($null -ne $parsed -and $j.Exit -eq '0') $j.All
    if ($parsed) {
        Assert-True '-AsJson carries the response''s fields' ($parsed.ceremony -eq 'standup' -and $parsed.register -eq 'real' -and $parsed.space -eq 'widgets' -and [bool]$parsed.tracker.ok -and $parsed.source -eq 'both') $j.Inner
        Assert-True '-AsJson''s text is the text the verb prints' (([string]$parsed.text).TrimEnd([char]10) -ceq $r.Inner) $parsed.text
        Assert-True '-AsJson''s queue.walk is [104,105], each naming its worker' ((Get-Numbers $parsed.queue.walk) -eq '104,105' -and @($parsed.queue.walk)[0].worker -eq 'Fable' -and @($parsed.queue.walk)[1].worker -eq '') $j.Inner
        Assert-True '-AsJson keeps empty slots as arrays' ($j.Inner -match '"decide"\s*:\s*\[\s*\]') $j.Inner
        $sonnet = @($parsed.workers | Where-Object { $_.label -eq 'sonnet' })[0]
        Assert-True '-AsJson: an empty worker carries one status sentence from the nothing family' ($sonnet -and [bool]$sonnet.empty -and $nothing -contains [string]$sonnet.excuse) $j.Inner
        $sonnetPair = @($sonnet.status)
        Assert-True '-AsJson: and its status is two items, nothing''s then nothingToday''s, the first its excuse' ($sonnetPair.Count -eq 2 -and [string]$sonnetPair[0] -ceq [string]$sonnet.excuse -and $nothingToday -contains [string]$sonnetPair[1]) $j.Inner
        $busy = @($parsed.workers | Where-Object { -not [bool]$_.empty })
        Assert-True '-AsJson: a worker with something to say carries an empty status list' ($busy.Count -gt 0 -and @($busy | Where-Object { @($_.status).Count -ne 0 -or [string]$_.excuse -ne '' }).Count -eq 0 -and $j.Inner -match '"status"\s*:\s*\[\s*\]') $j.Inner
    }

    # The typed verb asks whether a launch would work on this host (claude on the
    # PATH), and a delegation's command follows the answer on both lines; so do the
    # expectations below, or they would hold only on a host without it.
    . (Join-Path $pkgRoot 'Scripts/Test-StartWorkLaunch.ps1')
    $launchNow = Test-P20StartWorkLaunch
    # -Brief: the chair's reading alone -- the rule's own bytes, and nothing of the long form.
    $br = Invoke-Standup 'tkStandup -Brief'
    # The verb attaches the suggestion and the PM Corner (its last line); so does the expectation.
    $briefNow = Invoke-P20StandupJoinedFill -AsOf $pin -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
    $null = Add-P20StandupSuggestion -Standup $briefNow -Labels $ghLabels -Issues $ghIssues -Cards @() -HowIWork 'agents' -On $true -Prefix 'tk' -PackageRoot $pkgRoot -Launch $launchNow
    $null = Add-P20StandupCorner -Standup $briefNow -Labels $ghLabels -Issues $ghIssues -Cards @() -On $true -Prefix 'tk' -PackageRoot $pkgRoot -HowIWork 'agents' -Launch $launchNow
    $expectBrief = (Format-P20StandupBrief -Standup $briefNow -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True '-Brief: the PM Corner is its last line' ($null -ne $briefNow.corner -and $br.Inner.EndsWith([string]$briefNow.corner.brief)) $br.Inner
    Assert-True '-Brief exits 0 and prints the brief the rule renders for now, and only that' ($br.Exit -eq '0' -and $br.Inner -ceq $expectBrief) ("`n--- got ---`n$($br.Inner)`n--- want ---`n$expectBrief")
    Assert-True '-Brief has no title, no chair and no slot labels' ($br.Inner -notmatch '^Standup -- ' -and $br.Inner -notmatch '(?m)^  (Walk|Yesterday|Blockers)\b') $br.Inner
    if ($parsed) {
        Assert-True '-AsJson always carries the brief, the one -Brief prints' ((([string]$parsed.brief).TrimEnd([char]10)) -ceq $br.Inner) $parsed.brief
    }

    # -Grain: the work grain is the rule's own bytes; brief is -Brief's; a
    # word that is not a grain, or -Brief with another grain, is a stated refusal.
    $gw = Invoke-Standup 'tkStandup -Grain work'
    $expectNow.work.text = Format-P20StandupWork -Standup $expectNow -PackageRoot $pkgRoot
    $expectWork = ([string]$expectNow.work.text).TrimEnd([char]10)
    Assert-True '-Grain work exits 0 and prints the work grain the rule renders for now' ($gw.Exit -eq '0' -and $gw.Inner -ceq $expectWork) ("`n--- got ---`n$($gw.Inner)`n--- want ---`n$expectWork")
    $openTurn = [regex]::Escape([string]$consts.rituals.text.turnOpen)
    Assert-True '-Grain work: one turn a worker, spoken as prose, no slot labels padded to the column' ($gw.Inner -match ('(?m)^Opus: ' + $openTurn + ' Yesterday I closed ') -and $gw.Inner -notmatch '(?m)^  (Walk|Yesterday|Today|Blockers) ') $gw.Inner
    if ($parsed) {
        Assert-True '-AsJson carries the work grain: its groups, a full room -- every member, then the invented cast members -- and the text -Grain work prints' (([string]$parsed.work.text).TrimEnd([char]10) -ceq $gw.Inner -and @($parsed.work.workers).Count -eq ([int]$consts.rituals.teamSizeDefault - 1) -and @($parsed.work.workers | Where-Object { -not $_.cast }).Count -eq @($parsed.workers).Count -and $null -ne $parsed.work.queue) $j.Inner
    }
    $gd = Invoke-Standup 'tkStandup -Grain detail'
    Assert-True '-Grain detail is the standup as it always printed' ($gd.Exit -eq '0' -and $gd.Inner -ceq $r.Inner) $gd.All
    $gb = Invoke-Standup 'tkStandup -Grain brief'
    Assert-True '-Grain brief is -Brief' ($gb.Exit -eq '0' -and $gb.Inner -ceq $br.Inner) $gb.All
    $gx = Invoke-Standup 'tkStandup -Grain ticket'
    Assert-True 'a -Grain that is not a grain is a stated refusal: exit 2, one Error block naming the three' ($gx.Exit -eq '2' -and (@([regex]::Matches($gx.All, '(?m)^Error: ')).Count -eq 1) -and $gx.All -match 'detail, work, brief' -and $gx.All -notmatch 'exit code') $gx.All
    $gc = Invoke-Standup 'tkStandup -Brief -Grain work'
    Assert-True '-Brief with another grain is a stated refusal: exit 2, one Error block' ($gc.Exit -eq '2' -and (@([regex]::Matches($gc.All, '(?m)^Error: ')).Count -eq 1) -and $gc.All -notmatch 'exit code') $gc.All

    # -Since: yesterday widened back to a day -- the issue closed a month ago is said,
    # and the brief's counts line names the day. Today and the blockers do not move.
    $sinceDay = $pin.AddDays(-40).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $sw = Invoke-Standup "tkStandup -Since $sinceDay"
    $expectSince = Invoke-P20StandupJoinedFill -AsOf $pin -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'widgets' -SpaceName 'Widgets' -Window $sinceDay -PackageRoot $pkgRoot
    $expectSinceText = (Format-P20StandupText -Standup $expectSince -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True '-Since widens yesterday: exit 0, the text the rule renders for that window, line for line' ($sw.Exit -eq '0' -and $sw.Inner -ceq $expectSinceText) ("`n--- got ---`n$($sw.Inner)`n--- want ---`n$expectSinceText")
    Assert-True '-Since: the issue closed a month ago is said, under yesterday' ($sw.Inner -match '(?m)^  Yesterday  #103 ' -and $r.Inner -notmatch '#103') $sw.Inner
    $sb = Invoke-Standup "tkStandup -Since $sinceDay -Brief"
    $null = Add-P20StandupSuggestion -Standup $expectSince -Labels $ghLabels -Issues $ghIssues -Cards @() -HowIWork 'agents' -On $true -Prefix 'tk' -PackageRoot $pkgRoot -Launch $launchNow
    $null = Add-P20StandupCorner -Standup $expectSince -Labels $ghLabels -Issues $ghIssues -Cards @() -On $true -Prefix 'tk' -PackageRoot $pkgRoot -HowIWork 'agents' -Launch $launchNow
    $expectSinceBrief = (Format-P20StandupBrief -Standup $expectSince -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True '-Since -Brief: the counts line names the window''s first day' ($sb.Exit -eq '0' -and $sb.Inner -ceq $expectSinceBrief -and $sb.Inner -match '^Since \w+ ') ("`n--- got ---`n$($sb.Inner)`n--- want ---`n$expectSinceBrief")
    $tomorrow = $pin.AddDays(2).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    foreach ($badArg in @($tomorrow, 'yesterday')) {
        $sx = Invoke-Standup "tkStandup -Since $badArg"
        Assert-True "-Since $badArg is a stated refusal: exit 2, one Error block naming it" ($sx.Exit -eq '2' -and (@([regex]::Matches($sx.All, '(?m)^Error: ')).Count -eq 1) -and $sx.All.Contains($badArg) -and $sx.All -notmatch 'exit code') $sx.All
    }
    $sr = Invoke-Standup "tkStandup -Since $sinceDay -Remind 09:00"
    Assert-True '-Since -Remind is a stated refusal: one thing at a time' ($sr.Exit -eq '2' -and $sr.All -match 'one thing at a time' -and (@([regex]::Matches($sr.All, '(?m)^Error: ')).Count -eq 1)) $sr.All

    $down = Invoke-Standup 'tkStandup' -GhDown
    Assert-True 'gh not answering: the standup still happens, exit 0' ($down.Exit -eq '0' -and $down.Inner -match '^Standup -- ') $down.All
    Assert-True 'with the reason on its Tracker line' ($down.Inner -match '(?m)^  Tracker {4}gh did not answer') $down.Inner
    Assert-True 'and no queue, no workers' ($down.Inner -notmatch [regex]::Escape([string]$consts.rituals.text.queueHeading) -and $down.Inner -notmatch '(?m)^Fable$') $down.Inner

    $ado = Invoke-Standup 'tkStandup -Space board'
    Assert-True 'an Azure DevOps Space: the human team''s board (D-TA19), said on the Tracker line, exit 0' ($ado.Exit -eq '0' -and $ado.Inner -match ('(?m)^  Tracker {4}' + [regex]::Escape([string]$consts.rituals.text.adoTracker) + '$')) $ado.All
    Assert-True 'and no card is read for it: no queue, no worker' ($ado.Inner -notmatch [regex]::Escape([string]$consts.rituals.text.queueHeading)) $ado.Inner

    # A GitHub Space with cards: both, joined on the id. widgets/ gets a card of its
    # own in flight, a card linked to the closed issue 102 still in current/, and a
    # not-billable card -- and they are taken away again after.
    $widgetsCurrent = Join-Path $hub 'widgets/current'
    $joinedFiles = [ordered]@{
        'TaskK7M2-wire-the-board.prompt.md'  = "# Task K7M2: Wire the board`n`n- d74f5b2 before the window`n- a41c2e9 first`n"
        'Task102-rename-the-slug.prompt.md'  = "# Task 102: Rename the slug`n`n- b52d3f0 first`n"
        'TaskC4D7-bench.prompt.md'           = "# Task C4D7: Bench`n`n- c63e4a1 first`n`n**Billable:** no`n"
    }
    foreach ($k in $joinedFiles.Keys) { [System.IO.File]::WriteAllText((Join-Path $widgetsCurrent $k), $joinedFiles[$k], $utf8) }
    $beforeJoined = Get-HubSnapshot
    $jv = Invoke-Standup 'tkStandup'
    $afterJoined = Get-HubSnapshot
    $widgetCards = @(Get-P20StandupCards -CurrentDir $widgetsCurrent -ArchiveDir (Join-Path $hub 'widgets/archive') `
            -Pattern (Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $null)))
    # The stub dates d74f5b2 thirty days before the pinned instant and the others a minute before it: the verb's dates read drops the one before the window.
    $stubDates = @{ 'd74f5b2' = $pin.ToUniversalTime().AddDays(-30); 'a41c2e9' = $pin.ToUniversalTime().AddMinutes(-1); 'b52d3f0' = $pin.ToUniversalTime().AddMinutes(-1) }
    $joinedNow = Invoke-P20StandupJoinedFill -AsOf $pin -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } `
        -Cards $widgetCards -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot -CommitDates $stubDates -IssueStarts @{}
    $joinedText = (Format-P20StandupText -Standup $joinedNow -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True 'a GitHub Space with cards: the joined standup, exit 0, line for line' ($jv.Exit -eq '0' -and $jv.Inner -ceq $joinedText) ("`n--- got ---`n$($jv.Inner)`n--- want ---`n$joinedText")
    Assert-True 'a card of its own is a row under you, on the Space''s tile, with its commit -- the one authored before the window not counted, by the typed verb''s dates read' ($jv.Inner -match '(?m)^Widgets$' -and $jv.Inner -match '(?m)^  Today {6}K7M2 \(1 commit\) Wire the board$') $jv.Inner
    $check102 = ([string]$consts.rituals.text.checkIssueClosed).Replace('{item}', '#102 Rename the slug')
    Assert-True 'a card linked to a closed issue, still in current/: one Check line' ($jv.Inner -match ('(?m)^  Check {6}' + [regex]::Escape($check102) + '$')) $jv.Inner
    Assert-True 'a not-billable card is not a row' ($jv.Inner -notmatch 'C4D7') $jv.Inner
    Assert-True 'and reading both wrote nothing' ($beforeJoined -ceq $afterJoined)

    # The suggestion, typed: the same read, the rule's candidates in order on
    # -AsJson, each line naming the command with the registered prefix.
    $sj = Invoke-Standup 'tkStandup -AsJson'
    $sjParsed = $null
    try { $sjParsed = $sj.Inner | ConvertFrom-Json } catch { $sjParsed = $null }
    $null = Add-P20StandupSuggestion -Standup $joinedNow -Labels $ghLabels -Issues $ghIssues -Cards $widgetCards -HowIWork 'agents' -On $true -Prefix 'tk' -PackageRoot $pkgRoot -Launch $launchNow
    $wantRefs = (@($joinedNow.suggestions | ForEach-Object { $_.ref })) -join ','
    $gotRefs = ''
    if ($sjParsed) { $gotRefs = (@($sjParsed.suggestions | ForEach-Object { [string]$_.ref })) -join ',' }
    Assert-True 'typed: -AsJson carries the suggestion -- the rule''s candidates in order, the first as suggestion' ($sjParsed -and $wantRefs -and $gotRefs -ceq $wantRefs -and [string]$sjParsed.suggestion.ref -ceq @($joinedNow.suggestions)[0].ref) "got [$gotRefs] want [$wantRefs]"
    Assert-True 'typed: each line is Next:, the sentence, and the command with the CLI prefix' ($sjParsed -and @($sjParsed.suggestions | Where-Object { -not ([string]$_.line).StartsWith('Next: ' + [string]$_.sentence + ' (tk') }).Count -eq 0) $sj.Inner
    Assert-True 'typed: with walks waiting, the brief''s Next line is the queue''s, not the suggestion (D-AR7)' ($sjParsed -and -not ([string]$sjParsed.brief).Contains([string]$sjParsed.suggestion.line)) $sj.Inner
    # The switch: spaces.widgets.features.suggestions=false in the hub -- no suggestion.
    $hubJsonPath = Join-Path $hub 'hub.json'
    $savedHub = [System.IO.File]::ReadAllText($hubJsonPath)
    [System.IO.File]::WriteAllText($hubJsonPath, $savedHub.Replace('"howIWork": "agents" }', '"howIWork": "agents", "features": { "suggestions": false } }'), $utf8)
    $soff = Invoke-Standup 'tkStandup -AsJson'
    [System.IO.File]::WriteAllText($hubJsonPath, $savedHub, $utf8)
    $soffParsed = $null
    try { $soffParsed = $soff.Inner | ConvertFrom-Json } catch { $soffParsed = $null }
    Assert-True 'typed: spaces.<slug>.features.suggestions=false -- no candidate, no suggestion, the standup unchanged' ($soffParsed -and @($soffParsed.suggestions).Count -eq 0 -and $null -eq $soffParsed.suggestion -and ([string]$soffParsed.text) -ceq ([string]$sjParsed.text)) $soff.All
    # The room: spaces.widgets.features.teamSize=3 in the hub -- two seats. Every
    # worker stays on the response; the engineer takes the first seat and the
    # first worker with work the second, and nobody is invented.
    [System.IO.File]::WriteAllText($hubJsonPath, $savedHub.Replace('"howIWork": "agents" }', '"howIWork": "agents", "features": { "teamSize": 3 } }'), $utf8)
    $room = Invoke-Standup 'tkStandup -AsJson'
    [System.IO.File]::WriteAllText($hubJsonPath, $savedHub, $utf8)
    $roomParsed = $null
    try { $roomParsed = $room.Inner | ConvertFrom-Json } catch { $roomParsed = $null }
    $roomPresent = @()
    if ($roomParsed) { $roomPresent = @($roomParsed.workers | Where-Object { $_.present } | ForEach-Object { [string]$_.label }) }
    $roomSaid = ''
    $roomEngineer = ''
    if ($roomParsed) {
        $roomSaid = (@($roomParsed.work.workers | ForEach-Object { "$($_.label)/$([bool]$_.cast)" })) -join ','
        $roomEngineer = [string]@($roomParsed.workers)[-1].label
    }
    $roomOther = @($roomPresent | Where-Object { $_ -cne $roomEngineer })
    Assert-True 'typed: spaces.<slug>.features.teamSize=3 -- team.size 3, every worker kept, two present, and the round is those two: the engineer, then the first worker with work' ($roomParsed -and [int]$roomParsed.team.size -eq 3 -and @($roomParsed.workers).Count -eq @($sjParsed.workers).Count -and $roomPresent.Count -eq 2 -and $roomOther.Count -eq 1 -and $roomSaid -ceq "$roomEngineer/False,$($roomOther[0])/False" -and ([string]$roomParsed.text) -ceq ([string]$sjParsed.text)) $room.All
    Assert-True 'typed: with no teamSize the room is nine, everyone of the friday read is present, and the invented cast members fill the seats left' ($sjParsed -and [int]$sjParsed.team.size -eq [int]$consts.rituals.teamSizeDefault -and @($sjParsed.workers | Where-Object { -not $_.present }).Count -eq 0 -and @($sjParsed.work.workers).Count -eq ([int]$consts.rituals.teamSizeDefault - 1) -and @($sjParsed.work.workers | Where-Object { $_.cast }).Count -eq ([int]$consts.rituals.teamSizeDefault - 1 - @($sjParsed.workers).Count)) $sj.Inner
    foreach ($k in $joinedFiles.Keys) { Remove-Item -LiteralPath (Join-Path $widgetsCurrent $k) -Force }

    # A local Space: its cards, not gh. The scratch hub's solo/ has a card
    # in review, one in flight, one not started, and one archived today.
    $soloDir = Join-Path $hub 'solo'
    New-Item -ItemType Directory -Path (Join-Path $soloDir 'current'), (Join-Path $soloDir 'archive') -Force | Out-Null
    $today = $pin.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/K7M2-wire-the-board.prompt.md'), "# Task K7M2: Wire the board`n`n---`n`n**Review:** $today`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/Task139-write-the-docs.prompt.md'), "# Task 139: Write the docs`n`n- a41c2e9 first`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/214-not-started.prompt.md'), "# Bug 214: Not started`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'archive/198-fix-the-export.prompt.md'), "# Bug 198: Fix the export`n`n**Closed:** $today`n", $utf8)
    $beforeSolo = Get-HubSnapshot
    $solo = Invoke-Standup 'tkStandup -Space solo'
    $afterSolo = Get-HubSnapshot
    $soloCards = @(Get-P20StandupCards -CurrentDir (Join-Path $soloDir 'current') -ArchiveDir (Join-Path $soloDir 'archive') `
            -Pattern (Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $null)))
    $soloExpect = Invoke-P20StandupCardsFill -AsOf $pin -Cards $soloCards -Space 'solo' -SpaceName 'Solo Work' -PackageRoot $pkgRoot
    $soloText = (Format-P20StandupText -Standup $soloExpect -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True 'a local Space: the standup fills from its cards, exit 0, line for line' ($solo.Exit -eq '0' -and $solo.Inner -ceq $soloText) ("`n--- got ---`n$($solo.Inner)`n--- want ---`n$soloText")
    Assert-True 'one tile, named for the Space' ($solo.Inner -match '(?m)^Solo Work$') $solo.Inner
    Assert-True 'Code Review waits on you, by the card''s id' ($solo.Inner -match '(?m)^  Walk {7}K7M2 Wire the board$') $solo.Inner
    Assert-True 'In Progress and Code Review are today; archived today is yesterday; Active is nowhere' ($solo.Inner -match '(?m)^  Today {6}139 \(1 commit\) Write the docs$' -and $solo.Inner -match '(?m)^  Yesterday  198 Fix the export$' -and $solo.Inner -notmatch '214') $solo.Inner
    Assert-True 'and reading the cards wrote nothing' ($beforeSolo -ceq $afterSolo)
    $soloJson = Invoke-Standup 'tkStandup -Space solo -AsJson'
    $soloParsed = $null
    try { $soloParsed = $soloJson.Inner | ConvertFrom-Json } catch { $soloParsed = $null }
    Assert-True '-AsJson for a local Space: source cards, items carry id and path, number null' ($soloParsed -and $soloParsed.source -eq 'cards' -and @($soloParsed.queue.walk)[0].id -eq 'K7M2' -and $null -eq @($soloParsed.queue.walk)[0].number -and ([string]@($soloParsed.queue.walk)[0].path).EndsWith('K7M2-wire-the-board.prompt.md')) $soloJson.All

    $bad = Invoke-Standup 'tkStandup -Space nowhere'
    Assert-True 'an undeclared -Space is a stated refusal: exit 2, one Error block' ($bad.Exit -eq '2' -and $bad.All -match "No Space 'nowhere' is declared" -and (@([regex]::Matches($bad.All, '(?m)^Error: ')).Count -eq 1) -and $bad.All -notmatch 'exit code') $bad.All

    # -- 6. The walk list ---------------------------------------------------
    # A scratch VERIFY.md in the scratch package root (the root the module resolves
    # Scripts/ from): a row naming issue 104 -- wrapped, as the file wraps -- and a row
    # naming issue 1040 only, which must not be read as 104's or 105's.
    Write-Host ""
    Write-Host "-- Standup -Walk -----------------------------------------" -ForegroundColor Cyan
    $verifyText = @'
## Gate 12 -- Windows install and test

- [ ] **Other row** (#1040, 2026-10-01). Not the one.
      It names a longer number.

### Rows added by a fix

- [ ] **The Studio tab draws on the PC** (#104, 2026-10-02). Open the Studio tab on a real
      repo: the foyer shows one row per Space.
      **Expect:** a row per Space, no blank card.
- [x] **Unrelated** (#7, 2026-09-01). Done.
'@
    [System.IO.File]::WriteAllText((Join-Path $pkg 'VERIFY.md'), ($verifyText -replace "`r`n", "`n"), $utf8)
    $beforeWalk = Get-HubSnapshot
    $wk = Invoke-Standup 'tkStandup -Walk'
    $afterWalk = Get-HubSnapshot
    $wkLines = @($wk.Inner -split "`n")
    Assert-True '-Walk exits 0 and starts with the standup''s title line' ($wk.Exit -eq '0' -and $wkLines[0] -match '^Standup -- ') $wk.All
    Assert-True '-Walk prints only the walk list: no chair, no workers, no queue heading' ($wk.Inner -notmatch [regex]::Escape([string]$consts.rituals.text.queueHeading) -and $wk.Inner -notmatch '(?m)^Fable$' -and $wk.Inner -notmatch '(?m)^"') $wk.Inner
    Assert-True '-Walk: the issue line is the standup''s own, by number ascending' ($wk.Inner -match '(?m)^  Walk {7}#104 Verify the Studio tab draws on the PC$' -and $wk.Inner.IndexOf('#104 ') -lt $wk.Inner.IndexOf('#105 ')) $wk.Inner
    Assert-True '-Walk: the issue''s Gate 12 row verbatim and wrapped, indented under its line' ($wk.Inner.Contains("    - [ ] **The Studio tab draws on the PC** (#104, 2026-10-02). Open the Studio tab on a real`n          repo: the foyer shows one row per Space.`n          **Expect:** a row per Space, no blank card.")) $wk.Inner
    Assert-True '-Walk: an issue with no row (a longer number is not its row), and says so' ($wk.Inner -match "(?m)^  Walk {7}#105 .*\n  no VERIFY row -- close on the issue's own words$") $wk.Inner
    Assert-True '-Walk: another issue''s row is nowhere' ($wk.Inner -notmatch '#1040' -and $wk.Inner -notmatch 'Unrelated') $wk.Inner
    Assert-True '-Walk writes nothing, and never writes a reminder' ($beforeWalk -ceq $afterWalk -and -not (Test-Path -LiteralPath (Join-Path $hub 'reminders'))) $wk.All

    $wj = Invoke-Standup 'tkStandup -Walk -AsJson'
    $wjParsed = $null
    try { $wjParsed = $wj.Inner | ConvertFrom-Json } catch { $wjParsed = $null }
    Assert-True '-Walk -AsJson prints JSON with walk[] and nothing else of the standup' ($wjParsed -and $wj.Exit -eq '0' -and (@($wjParsed.PSObject.Properties.Name) -join ',') -eq 'walk') $wj.All
    if ($wjParsed) {
        $w104 = @($wjParsed.walk)[0]
        $w105 = @($wjParsed.walk)[1]
        Assert-True '-Walk -AsJson: [104,105] with number, title, url, verifyRow' ((Get-Numbers $wjParsed.walk) -eq '104,105' -and (@($w104.PSObject.Properties.Name) -join ',') -eq 'number,title,url,verifyRow' -and [string]$w104.url -ne '') $wj.Inner
        Assert-True '-Walk -AsJson: verifyRow is the row''s text, null when none names the issue' ([string]$w104.verifyRow -match '^- \[ \] \*\*The Studio tab draws on the PC\*\* \(#104' -and $null -eq $w105.verifyRow) $wj.Inner
    }

    # The empty list: every issue closed, so nothing carries an open walk label.
    $savedIssues = [System.IO.File]::ReadAllText((Join-Path $scratch 'issues.json'))
    $noWalk = @($ghIssues | Where-Object { @($_.labels | ForEach-Object { $_.name }) -notcontains [string]$consts.rituals.walkLabel })
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issues.json'), (ConvertTo-Json -InputObject ([object[]]$noWalk) -Depth 5), $utf8)
    $empty = Invoke-Standup 'tkStandup -Walk'
    $emptyJson = Invoke-Standup 'tkStandup -Walk -AsJson'
    Assert-True '-Walk with nothing waiting: the title and the queueEmpty sentence, exit 0' ($empty.Exit -eq '0' -and $empty.Inner -match ('(?s)^Standup -- [^\n]+\n  ' + [regex]::Escape([string]$consts.rituals.text.queueEmpty) + '$')) $empty.All
    Assert-True '-Walk -AsJson with nothing waiting: walk is an empty array' ($emptyJson.Inner -match '"walk"\s*:\s*\[\s*\]') $emptyJson.Inner
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issues.json'), $savedIssues, $utf8)

    $wd = Invoke-Standup 'tkStandup -Walk' -GhDown
    Assert-True '-Walk with gh not answering: the Tracker line, exit 0' ($wd.Exit -eq '0' -and $wd.Inner -match '(?m)^  Tracker {4}gh did not answer' -and $wd.Inner -notmatch 'Walk ') $wd.All

    $wr = Invoke-Standup 'tkStandup -Walk -Remind 09:00'
    Assert-True '-Walk -Remind is a stated refusal: exit 2, one Error block, one thing at a time' ($wr.Exit -eq '2' -and $wr.All -match 'one thing at a time' -and (@([regex]::Matches($wr.All, '(?m)^Error: ')).Count -eq 1) -and $wr.All -notmatch 'exit code') $wr.All

    # Walking is not attending: the walk branch exits before the attend block.
    $standupSource = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Scripts/Get-Standup.ps1'))
    $walkAt = $standupSource.IndexOf('if ($Walk) {')
    $attendAt = $standupSource.IndexOf('Invoke-P20StandupAttend -PackageRoot')
    Assert-True '-Walk leaves before the attend block, so it never re-arms the reminder' ($walkAt -gt 0 -and $attendAt -gt $walkAt -and $standupSource.IndexOf('exit 0', $walkAt) -lt $attendAt)

    $usage = Invoke-Standup 'tkStandup -Help'
    Assert-True '-Help renders the usage' ($usage.Inner -match 'Standup \[-Space <slug>\] \[-AsJson\]' -and $usage.Inner -match '\[-Since <yyyy-MM-dd>\]') $usage.Inner
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host ""
if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'Rituals' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
