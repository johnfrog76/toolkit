<#
.SYNOPSIS
    Team Agile's reminder to attend (D-TA15) -- the cadence rule over the
    shared table, and Standup -Remind and attending typed in a fresh shell.

.DESCRIPTION
    1. The table      Tests/fixtures/rituals/remind.json, every row: the days
                      -Days takes, the times -Remind takes, the first due, and
                      what attending does -- the same table
                      Tests/test_standup_remind.py asserts against the agent.
    2. -Remind        typed in a fresh shell with the package's own manifest and
                      features.organize on: ONE reminder, source standup, the
                      cadence on its Ref line, due the first time ahead; a second
                      -Remind rewrites it rather than adding one; a bad time, bad
                      days and -Days alone are stated refusals.
    3. Attending      with a fixed clock (Invoke-P20StandupAttend -Now, the same
                      code the verb runs): Friday's archived through Reminders
                      -Archive and Monday's written through NewReminder; a second
                      attendance the same day writes nothing. Then the verb itself,
                      on the real clock: Standup archives an overdue one and writes
                      the next, silently, and running it again changes nothing.
    4. Organize off   -Remind refuses naming features.organize (exit 2, one Error
                      block) and writes nothing; Standup leaves a reminder alone.
    5. Three places   -Remind and -Days are in the script's param(), the
                      wrapper's and the usage line.

    Run:  pwsh -File Tests/Test-StandupRemind.ps1
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

Write-Host ""
Write-Host "  StandupRemind -- Team Agile's reminder to attend" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
. (Join-Path $pkgRoot 'Scripts/Standup-Remind.ps1')
$consts = Get-P20Consts
$fmt = 'yyyy-MM-ddTHH:mm'
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function ConvertTo-TestTime { param([string]$Text) return [datetime]::ParseExact($Text, $fmt, $inv) }

# -- 1. The table ------------------------------------------------------------------
$table = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/rituals/remind.json')) | ConvertFrom-Json
Write-Host "-- The shared table -------------------------------------" -ForegroundColor Cyan
foreach ($row in @($table.days)) {
    $d = ConvertTo-P20StandupDays -Text ([string]$row.input)
    $got = $null
    if ($null -ne $d) { $got = Format-P20StandupDays -Days $d }
    $want = $row.days
    Assert-True "days '$($row.input)' -> $(if ($null -eq $want) { 'refused' } else { $want })" ([string]$got -ceq [string]$want -and (($null -eq $got) -eq ($null -eq $want))) "got '$got'"
}
foreach ($row in @($table.times)) {
    $got = ConvertTo-P20StandupTime -Text ([string]$row.input)
    $want = $row.time
    Assert-True "time '$($row.input)' -> $(if ($null -eq $want) { 'refused' } else { $want })" ([string]$got -ceq [string]$want -and (($null -eq $got) -eq ($null -eq $want))) "got '$got'"
}
foreach ($row in @($table.first)) {
    $got = Get-P20StandupFirstDue -Now (ConvertTo-TestTime $row.now) -Time ([string]$row.time) -Days (ConvertTo-P20StandupDays -Text ([string]$row.days))
    Assert-True "first due: $($row.name)" ($got -ceq [string]$row.due) "got '$got', want '$($row.due)'"
}
foreach ($row in @($table.attend)) {
    $plan = Get-P20StandupAttendPlan -Now (ConvertTo-TestTime $row.now) -Open @(@{ Id = 'K7M2'; Due = [string]$row.due; Ref = [string]$row.ref })
    Assert-True "attend: $($row.name)" ($plan.Action -ceq [string]$row.action -and [string]$plan.Next -ceq [string]$row.next) "got $($plan.Action) '$($plan.Next)', want $($row.action) '$($row.next)'"
    if ($row.action -eq 'rearm') {
        Assert-True "attend: $($row.name) -- archives the one it found" ((@($plan.Archive) -join ',') -eq 'K7M2')
    }
}
$two = Get-P20StandupAttendPlan -Now (ConvertTo-TestTime '2026-10-02T10:00') -Open @(
    @{ Id = 'A1B2'; Due = '2026-09-30T09:00'; Ref = '09:00 Mon-Fri' },
    @{ Id = 'C3D4'; Due = '2026-10-01T09:00'; Ref = '09:00 Mon-Fri' })
Assert-True 'two open and both behind: both archived, ONE next written' ($two.Action -eq 'rearm' -and (@($two.Archive) -join ',') -eq 'A1B2,C3D4' -and $two.Next -eq '2026-10-05T09:00') "$($two.Action) $(@($two.Archive) -join ',') $($two.Next)"
Assert-True 'the cadence is written the way the Ref line reads it back' ((ConvertFrom-P20StandupCadence -Ref '9:00 mon,wed,fri').Time -eq '09:00' -and (Format-P20StandupDays -Days (ConvertFrom-P20StandupCadence -Ref '09:00 Mon,Wed,Fri').Days) -eq 'Mon,Wed,Fri')

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-standup-remind-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$current = Join-Path $hub 'reminders/current'
$archive = Join-Path $hub 'reminders/archive'

function Invoke-Verbs {
    # A fresh shell per call, the package's own module and nothing else, the way
    # a person types a verb (AGENTS.md, "One toolkit per shell").
    param([string]$Snippet, [bool]$Organize = $true)
    $features = '{ "solitaireAgile": true }'
    if ($Organize) { $features = '{ "solitaireAgile": true, "organize": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"local1`", `"quietStart`": true, `"features`": $features }", $utf8)
    $q = { param($p) $p -replace "'", "''" }
    $body = @"
`$env:PSModulePath = '$(& $q $pkg)'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$(& $q $logDir)'
Remove-Item Env:\TOOLKIT_QUIET_STARTUP -ErrorAction SilentlyContinue
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
Import-Module '$(& $q $pkg)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
'<<<'
$Snippet
'>>>'
'EXIT=' + `$LASTEXITCODE
"@
    $runner = Join-Path $scratch ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    [System.IO.File]::WriteAllText($runner, $body, $utf8)
    $out = (& pwsh -NoProfile -NonInteractive -File $runner 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $inner = ''
    $m = [regex]::Match($out, '(?s)<<<\n(.*?)\n?>>>')
    if ($m.Success) { $inner = $m.Groups[1].Value }
    $code = ''
    $mc = [regex]::Match($out, 'EXIT=(\d*)')
    if ($mc.Success) { $code = $mc.Groups[1].Value }
    return [pscustomobject]@{ All = $out; Inner = $inner; Exit = $code }
}

function Get-Reminders {
    # Every file in a reminders folder: @{ Name; Title; Due; Source; Ref; Closed }.
    param([string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -Filter '*.md' -File | Sort-Object Name | ForEach-Object {
            $t = [System.IO.File]::ReadAllText($_.FullName)
            $line = { param($label) $mm = [regex]::Match($t, '(?m)^\*\*' + $label + ':\*\*[ \t]*(.*)$'); if ($mm.Success) { $mm.Groups[1].Value.Trim() } else { '' } }
            $h1 = [regex]::Match($t, '(?m)^#\s+(.+)$')
            [pscustomobject]@{
                Name = $_.Name; Title = $(if ($h1.Success) { $h1.Groups[1].Value.Trim() } else { '' })
                Due = (& $line 'Due'); Source = (& $line 'Source'); Ref = (& $line 'Ref'); Closed = (& $line 'Closed')
            }
        })
}

function Get-HubSnapshot {
    return ((@(Get-ChildItem -LiteralPath $hub -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })) -join "`n")
}

function Write-StandupReminder {
    # Test setup only: a reminder as NewReminder writes one.
    param([string]$Id, [string]$Due, [string]$Ref)
    New-Item -ItemType Directory -Path $current -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $current "$Id-standup.md"),
        "# Standup`n`n---`n`n**Due:** $Due`n**Source:** $($consts.rituals.remindSource)`n**Ref:** $Ref`n**Created:** 2026-09-28`n", $utf8)
}

function Clear-Reminders { Remove-Item (Join-Path $hub 'reminders') -Recurse -Force -ErrorAction SilentlyContinue }

try {
    New-Item -ItemType Directory -Path $pkg, $logDir, (Join-Path $hub 'local1/current') -Force | Out-Null
    foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
    # A local Space: Standup still happens from its cards, and asks no gh. Its
    # address is GitHub's and it is answered with agents -- the one kind of
    # Space Team Agile is on in; local, so the tracker is never contacted.
    [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'),
        '{ "hub": 1, "spaces": [ { "slug": "local1", "name": "Local", "status": "local", "promptsFolder": "local1", "org": "https://github.com/acme/local1", "howIWork": "agents" } ] }', $utf8)

    # -- 5. Three places -----------------------------------------------------------
    Write-Host ""
    Write-Host "-- The switch, in three places --------------------------" -ForegroundColor Cyan
    $scriptParams = @((Get-Command (Join-Path $pkgRoot 'Scripts/Get-Standup.ps1')).Parameters.Keys)
    Assert-True 'the script''s param() has -Remind and -Days' ($scriptParams -contains 'Remind' -and $scriptParams -contains 'Days') ($scriptParams -join ',')
    $data = Import-PowerShellDataFile (Join-Path $pkgRoot 'Config/solitaireAgile.commands.psd1')
    $usage = [string]$data.Help.Standup.usage
    Assert-True 'the usage line names -Remind <HH:mm> and -Days' ($usage -match '\[-Remind <HH:mm>\]' -and $usage -match '\[-Days <') $usage
    $w = Invoke-Verbs "(Get-Command Get-P20Standup).Parameters.Keys -join ','"
    Assert-True 'the wrapper''s param() has -Remind and -Days' ($w.Inner -match '\bRemind\b' -and $w.Inner -match '\bDays\b') $w.All

    # -- 2. -Remind ------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Standup -Remind, as typed ----------------------------" -ForegroundColor Cyan
    $before = Get-P20StandupFirstDue -Now (Get-Date) -Time '09:00' -Days @(0, 1, 2, 3, 4)
    $r = Invoke-Verbs 'tkStandup -Remind 09:00'
    $after = Get-P20StandupFirstDue -Now (Get-Date) -Time '09:00' -Days @(0, 1, 2, 3, 4)
    $open = @(Get-Reminders $current)
    Assert-True '-Remind 09:00 exits 0' ($r.Exit -eq '0') $r.All
    Assert-True 'and writes ONE reminder' ($open.Count -eq 1) (($open | ForEach-Object Name) -join ', ')
    if ($open.Count -eq 1) {
        Assert-True 'titled Standup, source standup' ($open[0].Title -ceq $consts.rituals.remindTitle -and $open[0].Source -ceq $consts.rituals.remindSource) "$($open[0].Title) / $($open[0].Source)"
        Assert-True 'its cadence on the Ref line: 09:00 Mon-Fri' ($open[0].Ref -ceq '09:00 Mon-Fri') $open[0].Ref
        Assert-True 'due the next 09:00 on a working day' ($open[0].Due -eq $before -or $open[0].Due -eq $after) "got $($open[0].Due), want $before"
    }
    Assert-True 'and says so in one line, not the standup' ($r.Inner -match 'reminds you at 09:00 Mon-Fri' -and $r.Inner -notmatch '(?m)^Standup -- ') $r.Inner

    $r = Invoke-Verbs 'tkStandup -Remind 17:30 -Days Mon,Wed,Fri'
    $open2 = @(Get-Reminders $current)
    $want = Get-P20StandupFirstDue -Now (Get-Date) -Time '17:30' -Days @(0, 2, 4)
    Assert-True 'a second -Remind exits 0' ($r.Exit -eq '0') $r.All
    Assert-True 'and REWRITES the one there, not a second' ($open2.Count -eq 1 -and $open.Count -eq 1 -and $open2[0].Name -eq $open[0].Name) (($open2 | ForEach-Object Name) -join ', ')
    if ($open2.Count -eq 1) {
        Assert-True 'its Ref is the new cadence, its Due the new first time' ($open2[0].Ref -ceq '17:30 Mon,Wed,Fri' -and $open2[0].Due -eq $want) "$($open2[0].Ref) / $($open2[0].Due)"
    }
    Assert-True 'nothing was archived by it' (@(Get-Reminders $archive).Count -eq 0)

    $snap = Get-HubSnapshot
    $bad = Invoke-Verbs 'tkStandup -Remind 25:00'
    Assert-True 'a time that is not one: exit 2, one Error block' ($bad.Exit -eq '2' -and $bad.All -match "'25:00' is not a time of day" -and @([regex]::Matches($bad.All, '(?m)^Error: ')).Count -eq 1) $bad.All
    $bad = Invoke-Verbs 'tkStandup -Remind 09:00 -Days Mon,Funday'
    Assert-True 'days that are not days: exit 2, naming the day names' ($bad.Exit -eq '2' -and $bad.All -match 'is not a list of days' -and $bad.All -match 'Mon,Tue,Wed') $bad.All
    $bad = Invoke-Verbs 'tkStandup -Days Mon'
    Assert-True '-Days without -Remind: exit 2' ($bad.Exit -eq '2' -and $bad.All -match '-Days goes with -Remind') $bad.All
    Assert-True 'and none of the three wrote anything' ((Get-HubSnapshot) -ceq $snap)

    # -- 3. Attending --------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Attending: a fixed clock, then the verb ---------------" -ForegroundColor Cyan
    Clear-Reminders
    Write-StandupReminder -Id 'K7M2' -Due '2026-10-02T09:00' -Ref '09:00 Mon-Fri'
    $attend = ". '$($pkg -replace "'", "''")/Scripts/Standup-Remind.ps1'; `$why = Invoke-P20StandupAttend -PackageRoot '$($pkg -replace "'", "''")' -Now ([datetime]::ParseExact('2026-10-02T10:00', 'yyyy-MM-ddTHH:mm', `$null)); 'WHY=[' + `$why + ']'"
    $a = Invoke-Verbs $attend
    $open = @(Get-Reminders $current)
    $done = @(Get-Reminders $archive)
    Assert-True 'Friday 10:00: attending says nothing went wrong' ($a.Inner -match 'WHY=\[\]') $a.All
    Assert-True 'Friday''s is archived, through Reminders -Archive (stamped Closed)' ($done.Count -eq 1 -and $done[0].Name -eq 'K7M2-standup.md' -and $done[0].Closed) (($done | ForEach-Object Name) -join ', ')
    Assert-True 'and Monday''s written, through NewReminder: one open, due Monday 09:00' ($open.Count -eq 1 -and $open[0].Due -eq '2026-10-05T09:00') (($open | ForEach-Object { "$($_.Name) $($_.Due)" }) -join ', ')
    if ($open.Count -eq 1) {
        Assert-True 'the new one carries the title, the source and the same cadence' ($open[0].Title -ceq 'Standup' -and $open[0].Source -ceq 'standup' -and $open[0].Ref -ceq '09:00 Mon-Fri') "$($open[0].Title) / $($open[0].Source) / $($open[0].Ref)"
        Assert-True 'with a fresh id of its own' ($open[0].Name -cmatch '^[A-Z0-9]{4}-standup\.md$' -and $open[0].Name -ne 'K7M2-standup.md') $open[0].Name
    }
    Assert-True 'attending prints nothing of the Organize verbs' ($a.Inner -notmatch 'Created reminder|Archived:') $a.Inner
    $snap = Get-HubSnapshot
    $a = Invoke-Verbs $attend
    Assert-True 'attending twice the same day writes nothing more' ($a.Inner -match 'WHY=\[\]' -and (Get-HubSnapshot) -ceq $snap) $a.All

    Clear-Reminders
    Write-StandupReminder -Id 'K7M2' -Due '2020-01-01T09:00' -Ref '09:00 Mon-Sun'
    $s = Invoke-Verbs 'tkStandup'
    $open = @(Get-Reminders $current)
    $want = Get-P20StandupNextDue -Now (Get-Date) -Time '09:00' -Days @(0, 1, 2, 3, 4, 5, 6)
    Assert-True 'Standup, typed: the standup still prints, exit 0' ($s.Exit -eq '0' -and $s.Inner -match '(?m)^Standup -- ') $s.All
    Assert-True 'and the overdue reminder is archived' (@(Get-Reminders $archive).Count -eq 1)
    Assert-True 'and the next is written, due tomorrow at 09:00' ($open.Count -eq 1 -and $open[0].Due -eq $want) (($open | ForEach-Object { "$($_.Name) $($_.Due)" }) -join ', ')
    Assert-True 'silently' ($s.Inner -notmatch 'not re-armed|Created reminder|Archived:') $s.Inner
    $snap = Get-HubSnapshot
    $s = Invoke-Verbs 'tkStandup'
    Assert-True 'Standup again the same day: nothing more' ($s.Exit -eq '0' -and (Get-HubSnapshot) -ceq $snap) $s.All

    Clear-Reminders
    Write-StandupReminder -Id 'K7M2' -Due '2020-01-01T09:00' -Ref 'whenever'
    $snap = Get-HubSnapshot
    $s = Invoke-Verbs 'tkStandup'
    Assert-True 'a Ref that is not a cadence: one line, exit 0, nothing written' ($s.Exit -eq '0' -and $s.Inner -match "not re-armed: its ref 'whenever'" -and (Get-HubSnapshot) -ceq $snap) $s.All

    # -- 4. Organize off -------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Organize off ------------------------------------------" -ForegroundColor Cyan
    Clear-Reminders
    $off = Invoke-Verbs 'tkStandup -Remind 09:00' -Organize $false
    Assert-True '-Remind with organize off: exit 2' ($off.Exit -eq '2') $off.All
    Assert-True 'naming the key and the file' ($off.All -match 'features\.organize' -and $off.All -match 'config\.local\.json') $off.All
    Assert-True 'one Error block, no generic exit-code block' (@([regex]::Matches($off.All, '(?m)^Error: ')).Count -eq 1 -and $off.All -notmatch 'exit code') $off.All
    Assert-True 'and nothing written' (-not (Test-Path (Join-Path $hub 'reminders')))
    Write-StandupReminder -Id 'K7M2' -Due '2020-01-01T09:00' -Ref '09:00 Mon-Fri'
    $snap = Get-HubSnapshot
    $off = Invoke-Verbs 'tkStandup' -Organize $false
    Assert-True 'Standup with organize off leaves a standup reminder alone' ($off.Exit -eq '0' -and (Get-HubSnapshot) -ceq $snap -and $off.Inner -notmatch 'not re-armed') $off.All

    $usage = Invoke-Verbs 'tkStandup -Help'
    Assert-True '-Help renders -Remind and -Days' ($usage.Inner -match '\[-Remind <HH:mm>\] \[-Days <') $usage.Inner
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
    Write-P20TestResult -Suite 'StandupRemind' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
