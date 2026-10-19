<#
.SYNOPSIS
    Solitaire Agile's Ritual Engine -- the standup's slot rule over the shared
    table, the golden texts byte for byte, and the verb typed in a fresh shell.

.DESCRIPTION
    1. The table     Tests/fixtures/rituals/standup.json, every case: since, the
                     day of the year, the chair's two lines, the queue, each
                     worker's slots by issue number, empty and its status sentence -- the
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
                     (today's also-ons as one sentence, D-SA9), and every case's
                     queue sentences, each worker's sentences and the work text
                     against standup-prose-<name>.txt, byte for byte, again
                     after a JSON round trip -- the same rows the agent asserts.
    2d. The dress    Tests/fixtures/rituals/standup-dress.json: every
                     row of the dress guard (a dressed sentence and its group's
                     facts in, kept or the guard it fails out), every group's
                     prose sentence passing its own guard, every guard of
                     rituals.dressGuards with a row, and a reply naming a number that is not in the read
                     keeping the prose for that group -- the rows the agent
                     asserts. Only the agent calls a model.
    3. No fake work  the real register never reads the vocabulary's fakeWork
                     family (D-SA5): every case's text is grepped for it.
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
$excuses = @($data.Vocabulary.excuses)
$fakeWork = @($data.Vocabulary.fakeWork)

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
        $wantExcuse = ''
        if ($null -ne $w.nothingIndex) { $wantExcuse = $nothing[[int]$w.nothingIndex] }
        Assert-True "${name}: $($w.label)'s status sentence is nothing[$($w.nothingIndex)]" ($g.excuse -ceq $wantExcuse) "got '$($g.excuse)', want '$wantExcuse'"
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
Assert-True 'the vocabulary has an excuses family (the nonsense register''s) and a nothing family (the empty worker''s)' ($excuses.Count -gt 0 -and $nothing.Count -gt 0)
Assert-True 'the vocabulary has a fakeWork family to grep for' ($fakeWork.Count -gt 0)

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
        $wantExcuse = ''
        if ($null -ne $w.nothingIndex) { $wantExcuse = $nothing[[int]$w.nothingIndex] }
        Assert-True "${name}: the status sentence is nothing[$($w.nothingIndex)]" ($ws[0].excuse -ceq $wantExcuse) "got '$($ws[0].excuse)', want '$wantExcuse'"
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
    New-Item -ItemType Directory -Path (Join-Path $readerDir 'current'), (Join-Path $readerDir 'archive') -Force | Out-Null
    $readerFiles = [ordered]@{
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
Assert-True 'the joined table is read: the six shapes, all of them together, then what moved' ($joinedNames -ceq 'linked-card-open-issue,linked-card-archived-issue-open,issue-closed-card-current,custom-card-alone,issue-alone,not-billable,together,counts,not-billable-counts,window-three-days') $joinedNames

foreach ($case in $joinedCases) {
    $name = 'joined-' + [string]$case.name
    $exp = $case.expected
    Write-Host ""
    Write-Host "-- $name --" -ForegroundColor Cyan
    $window = ConvertTo-P20StandupDay $case.window
    $s = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($case.issues) -Tracker @{ ok = $true; reason = '' } `
        -Cards @($case.cards) -Space ([string]$joinedTable.space) -SpaceName ([string]$joinedTable.spaceName) -Window $window -PackageRoot $pkgRoot
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
    $wantWorkers = (@($exp.workers | ForEach-Object { "$($_.label)/$($_.name) y[$((@($_.yesterday)) -join ',')] t[$((@($_.today)) -join ',')] b[$((@($_.blockers)) -join ',')] $([bool]$_.empty)" })) -join ' | '
    $gotWorkers = (@($s.workers | ForEach-Object { "$($_.label)/$($_.name) y[$(Get-Refs $_.yesterday)] t[$(Get-Refs $_.today)] b[$(Get-Refs $_.blockers)] $([bool]$_.empty)" })) -join ' | '
    Assert-True "${name}: every worker's slots by ref" ($gotWorkers -ceq $wantWorkers) ("`n got: $gotWorkers`nwant: $wantWorkers")
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
        $countLine = { param($c) "$($c.closed)/$($c.started)/$($c.inProgress)/$($c.commits)" }
        $wantCounts = (@($exp.counts.workers | ForEach-Object { "$($_.label) " + (& $countLine $_) }) + @('total ' + (& $countLine $exp.counts.total))) -join ' | '
        $gotCounts = (@($s.counts.workers | ForEach-Object { "$($_.label) " + (& $countLine $_) }) + @('total ' + (& $countLine $s.counts.total))) -join ' | '
        Assert-True "${name}: the counts per worker and in total (closed/started/in progress/commits)" ($gotCounts -ceq $wantCounts) ("`n got: $gotCounts`nwant: $wantCounts")
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
Assert-True 'no card in play: the issues'' own text and brief, only the source says both' ($joinedFill.source -ceq 'both' -and (Format-P20StandupText -Standup $joinedFill -PackageRoot $pkgRoot) -ceq (Format-P20StandupText -Standup $aloneFill -PackageRoot $pkgRoot) -and (Format-P20StandupBrief -Standup $joinedFill -PackageRoot $pkgRoot) -ceq (Format-P20StandupBrief -Standup $aloneFill -PackageRoot $pkgRoot))
$together = @($joinedCases | Where-Object { $_.name -eq 'together' })[0]
$downFill = Invoke-P20StandupJoinedFill -AsOf $joinedAsOf -Labels @($joinedTable.workerLabels) -Issues @($together.issues) -Tracker @{ ok = $false; reason = 'gh did not answer' } -Cards @($together.cards) -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
Assert-True 'the tracker not answering: the Tracker line, no worker, no Check line, no link' ($downFill.source -ceq 'none' -and @($downFill.workers).Count -eq 0 -and @($downFill.checks).Count -eq 0 -and @($downFill.links).Count -eq 0)
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
    $gotWorkers = @($s.work.workers)
    $wantWorkers = @($exp.workers)
    Assert-True "${name}: one work row per worker, in label order" (((@($gotWorkers | ForEach-Object { $_.label })) -join ',') -ceq ((@($wantWorkers | ForEach-Object { $_.label })) -join ',')) ((@($gotWorkers | ForEach-Object { $_.label })) -join ',')
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
    $got = Get-P20StandupWorkKey -Milestone $row.milestone -Body ([string]$row.body) -Type ([string]$row.type) -Threads $threads
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
Assert-True 'the response carries work beside text: queue, workers, the queue''s prose and its own text' ($standupJson.Contains('work') -and (((@($standupJson.work.Keys)) -join ',') -ceq 'queue,workers,queueProse,text')) ((@($standupJson.work.Keys)) -join ',')
Assert-True 'a work row carries its prose after its three slots' ((((@($standupJson.work.workers[0].Keys)) -join ',') -ceq 'label,name,yesterday,today,blockers,prose')) ((@($standupJson.work.workers[0].Keys)) -join ',')

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
Assert-True 'the prose table is read: five cases, an asOf each' ($proseCases.Count -eq 5 -and $proseAsOf.Count -eq 5) "$($proseCases.Count) cases, $($proseAsOf.Count) asOf"

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

for ($n = 0; $n -lt $proseCases.Count; $n++) {
    $case = $proseCases[$n]
    $name = 'prose-' + [string]$case.name
    $exp = $case.expected
    if ([string]$case.source -eq 'cards') {
        $s = Invoke-P20StandupCardsFill -AsOf $proseAsOf[$n] -Cards @($case.cards) -Space ([string]$case.space) -SpaceName ([string]$case.spaceName) -PackageRoot $pkgRoot
    }
    else {
        $s = Invoke-P20StandupFill -AsOf $proseAsOf[$n] -Labels @($proseTable.workerLabels) -Issues @($case.issues) -Tracker $case.tracker -PackageRoot $pkgRoot
    }
    $want = (@($exp.queue | ForEach-Object { [string]$_ })) -join ' | '
    $got = (@($s.work.queueProse | ForEach-Object { [string]$_ })) -join ' | '
    Assert-True "${name}: the queue's sentences" ($got -ceq $want) "`n  got  $got`n  want $want"
    $gotWorkers = @($s.work.workers)
    Assert-True "${name}: one prose row per worker, in label order" (((@($gotWorkers | ForEach-Object { $_.label })) -join ',') -ceq ((@($exp.workers | ForEach-Object { $_.label })) -join ','))
    foreach ($w in @($exp.workers)) {
        $g = @($gotWorkers | Where-Object { [string]$_.label -ceq [string]$w.label }) | Select-Object -First 1
        $want = (@($w.prose | ForEach-Object { [string]$_ })) -join ' | '
        $got = ''
        if ($g) { $got = (@($g.prose | ForEach-Object { [string]$_ })) -join ' | ' }
        Assert-True "${name}: $($w.label)'s sentences" ($got -ceq $want) "`n  got  $got`n  want $want"
    }
    $text = Format-P20StandupWork -Standup $s -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
    Assert-True "${name}: the work text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    $back = ($s | ConvertTo-Json -Depth 12) | ConvertFrom-Json
    $back.asOf = $s.asOf
    Assert-True "${name}: the JSON round trip renders the same prose" ((Format-P20StandupWork -Standup $back -PackageRoot $pkgRoot) -ceq $text)
    Assert-True "${name}: no fakeWork line in the prose" (@($fakeWork | Where-Object { $text.Contains([string]$_) }).Count -eq 0)
}

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

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-rituals-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-Standup {
    # A fresh shell per call: gh replaced by a function that answers from the
    # scratch files (and fails when P20_TEST_GH_DOWN is set), then the package's
    # own manifest and nothing else, the way a person types a verb (AGENTS.md,
    # "One toolkit per shell").
    param([string]$Snippet, [bool]$On = $true, [switch]$GhDown)
    $features = '{}'
    if ($On) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"widgets`", `"quietStart`": true, `"features`": $features }", $utf8)
    $q = { param($p) $p -replace "'", "''" }
    $down = ''
    if ($GhDown) { $down = "`$env:P20_TEST_GH_DOWN = '1'`n" }
    $body = $down + @"
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
    # rest -- so the verb, reading the real clock, fills the same slots.
    $friday = @($cases | Where-Object { $_.name -eq 'friday' })[0]
    $yesterdayNumbers = @($friday.expected.workers | ForEach-Object { @($_.yesterday) } | ForEach-Object { [int]$_ })
    $now = [DateTimeOffset]::UtcNow
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
    $expectNow = Invoke-P20StandupJoinedFill -AsOf ([DateTimeOffset]::Now) -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
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
    }

    # -Brief: the chair's reading alone -- the rule's own bytes, and nothing of the long form.
    $br = Invoke-Standup 'tkStandup -Brief'
    $expectBrief = (Format-P20StandupBrief -Standup $expectNow -PackageRoot $pkgRoot).TrimEnd([char]10)
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
    Assert-True '-Grain work: one line a worker, spoken as prose, no slot labels padded to the column' ($gw.Inner -match '(?m)^Opus: Yesterday I closed ' -and $gw.Inner -notmatch '(?m)^  (Walk|Yesterday|Today|Blockers) ') $gw.Inner
    if ($parsed) {
        Assert-True '-AsJson carries the work grain: its groups and the text -Grain work prints' (([string]$parsed.work.text).TrimEnd([char]10) -ceq $gw.Inner -and @($parsed.work.workers).Count -eq 3 -and $null -ne $parsed.work.queue) $j.Inner
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
    $sinceDay = [DateTimeOffset]::Now.AddDays(-40).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $sw = Invoke-Standup "tkStandup -Since $sinceDay"
    $expectSince = Invoke-P20StandupJoinedFill -AsOf ([DateTimeOffset]::Now) -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } -Cards @() -Space 'widgets' -SpaceName 'Widgets' -Window $sinceDay -PackageRoot $pkgRoot
    $expectSinceText = (Format-P20StandupText -Standup $expectSince -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True '-Since widens yesterday: exit 0, the text the rule renders for that window, line for line' ($sw.Exit -eq '0' -and $sw.Inner -ceq $expectSinceText) ("`n--- got ---`n$($sw.Inner)`n--- want ---`n$expectSinceText")
    Assert-True '-Since: the issue closed a month ago is said, under yesterday' ($sw.Inner -match '(?m)^  Yesterday  #103 ' -and $r.Inner -notmatch '#103') $sw.Inner
    $sb = Invoke-Standup "tkStandup -Since $sinceDay -Brief"
    $expectSinceBrief = (Format-P20StandupBrief -Standup $expectSince -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True '-Since -Brief: the counts line names the window''s first day' ($sb.Exit -eq '0' -and $sb.Inner -ceq $expectSinceBrief -and $sb.Inner -match '^Since \w+ ') ("`n--- got ---`n$($sb.Inner)`n--- want ---`n$expectSinceBrief")
    $tomorrow = [DateTimeOffset]::Now.AddDays(2).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
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
        'TaskK7M2-wire-the-board.prompt.md'  = "# Task K7M2: Wire the board`n`n- a41c2e9 first`n"
        'Task102-rename-the-slug.prompt.md'  = "# Task 102: Rename the slug`n`n- b52d3f0 first`n"
        'TaskC4D7-bench.prompt.md'           = "# Task C4D7: Bench`n`n- c63e4a1 first`n`n**Billable:** no`n"
    }
    foreach ($k in $joinedFiles.Keys) { [System.IO.File]::WriteAllText((Join-Path $widgetsCurrent $k), $joinedFiles[$k], $utf8) }
    $beforeJoined = Get-HubSnapshot
    $jv = Invoke-Standup 'tkStandup'
    $afterJoined = Get-HubSnapshot
    $widgetCards = @(Get-P20StandupCards -CurrentDir $widgetsCurrent -ArchiveDir (Join-Path $hub 'widgets/archive') `
            -Pattern (Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $null)))
    $joinedNow = Invoke-P20StandupJoinedFill -AsOf ([DateTimeOffset]::Now) -Labels $ghLabels -Issues $ghIssues -Tracker @{ ok = $true; reason = '' } `
        -Cards $widgetCards -Space 'widgets' -SpaceName 'Widgets' -PackageRoot $pkgRoot
    $joinedText = (Format-P20StandupText -Standup $joinedNow -PackageRoot $pkgRoot).TrimEnd([char]10)
    Assert-True 'a GitHub Space with cards: the joined standup, exit 0, line for line' ($jv.Exit -eq '0' -and $jv.Inner -ceq $joinedText) ("`n--- got ---`n$($jv.Inner)`n--- want ---`n$joinedText")
    Assert-True 'a card of its own is a row under you, on the Space''s tile, with its commit' ($jv.Inner -match '(?m)^Widgets$' -and $jv.Inner -match '(?m)^  Today {6}K7M2 \(1 commit\) Wire the board$') $jv.Inner
    $check102 = ([string]$consts.rituals.text.checkIssueClosed).Replace('{item}', '#102 Rename the slug')
    Assert-True 'a card linked to a closed issue, still in current/: one Check line' ($jv.Inner -match ('(?m)^  Check {6}' + [regex]::Escape($check102) + '$')) $jv.Inner
    Assert-True 'a not-billable card is not a row' ($jv.Inner -notmatch 'C4D7') $jv.Inner
    Assert-True 'and reading both wrote nothing' ($beforeJoined -ceq $afterJoined)
    foreach ($k in $joinedFiles.Keys) { Remove-Item -LiteralPath (Join-Path $widgetsCurrent $k) -Force }

    # A local Space: its cards, not gh. The scratch hub's solo/ has a card
    # in review, one in flight, one not started, and one archived today.
    $soloDir = Join-Path $hub 'solo'
    New-Item -ItemType Directory -Path (Join-Path $soloDir 'current'), (Join-Path $soloDir 'archive') -Force | Out-Null
    $today = [DateTimeOffset]::Now.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/K7M2-wire-the-board.prompt.md'), "# Task K7M2: Wire the board`n`n---`n`n**Review:** $today`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/Task139-write-the-docs.prompt.md'), "# Task 139: Write the docs`n`n- a41c2e9 first`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'current/214-not-started.prompt.md'), "# Bug 214: Not started`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $soloDir 'archive/198-fix-the-export.prompt.md'), "# Bug 198: Fix the export`n`n**Closed:** $today`n", $utf8)
    $beforeSolo = Get-HubSnapshot
    $solo = Invoke-Standup 'tkStandup -Space solo'
    $afterSolo = Get-HubSnapshot
    $soloCards = @(Get-P20StandupCards -CurrentDir (Join-Path $soloDir 'current') -ArchiveDir (Join-Path $soloDir 'archive') `
            -Pattern (Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $null)))
    $soloExpect = Invoke-P20StandupCardsFill -AsOf ([DateTimeOffset]::Now) -Cards $soloCards -Space 'solo' -SpaceName 'Solo Work' -PackageRoot $pkgRoot
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
