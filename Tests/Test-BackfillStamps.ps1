<#
.SYNOPSIS
    Tests for Scripts/Backfill-CardStamps.ps1 -- the one-time repair that writes
    the **Created:** / **Closed:** stamps older cards never got, from git history.

.DESCRIPTION
    Two layers.

    The RULES are a pure function over `git log --follow --name-status` lines
    (Get-P20CardHistoryDates -LogLines), loaded out of the script the way the
    PRComments suite loads its functions. Each of the three rules in the
    script's header is here as the log shape it was learned from on the real hub:
    a folder reorganisation that is not an event, a "copy" from a different card
    that must not lend this card its history, and a round rename that is still
    the same card.

    The TOOL is then run for real against a scratch git repository whose commit
    dates are fixed, because the properties that matter most cannot be shown on a
    fixture: it writes the right bytes, it never rewrites a stamp that is already
    there, -WhatIf writes nothing, a second run changes nothing, growth/ is left
    alone, and a hub that is not a repository is a stated refusal.

    Run:  pwsh -File Tests/Test-BackfillStamps.ps1
    Or:   {cliPrefix}TestToolkit -BackfillStamps

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Loads the rules'' functions out of the script under test by their source text, so they can be called alone.')]
param()

$pkgRoot = Split-Path -Parent $PSScriptRoot
$targetScript = Join-Path (Join-Path $pkgRoot 'Scripts') 'Backfill-CardStamps.ps1'
$sourceText = Get-Content $targetScript -Raw

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    Assert-True $TestName ($Expected -eq $Actual) "expected [$Expected] got [$Actual]"
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Backfill card stamps" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($fn in @('Get-P20CardStem', 'Test-P20ArchivePath', 'Get-P20CardHistoryDates')) {
    $m = [regex]::Match($sourceText, "(?s)function $fn \{.*?\n\}")
    Assert-True "$fn is in the script" $m.Success
    if ($m.Success) { Invoke-Expression $m.Value }
}

$T = "`t"
. (Join-Path (Join-Path $pkgRoot 'Scripts') 'ConvertTo-LocalDay.ps1')

# -- The rules, on the log shapes they were learned from -------------------------

Write-Host ""
Write-Host "-- The ordinary card ----------------------------------" -ForegroundColor Cyan
$log = @(
    'COMMIT 2026-05-06', "R100${T}globex/current/178484-next-page.prompt.md${T}globex/archive/178484-next-page.prompt.md",
    'COMMIT 2026-05-04', "M${T}globex/current/178484-next-page.prompt.md",
    'COMMIT 2026-05-01', "A${T}globex/current/178484-next-page.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'globex/archive/178484-next-page.prompt.md' -LogLines $log
Assert-Equal 'Created is the oldest commit' '2026-05-01' $d.Created
Assert-Equal 'Closed is the day it moved into archive/' '2026-05-06' $d.Closed

Write-Host ""
Write-Host "-- A folder reorganisation is not an event ------------" -ForegroundColor Cyan
# A hub archived under one org folder, the whole tree renamed to another
# later, and a link-refresh commit touching it after that. It closed on the first day.
$log = @(
    'COMMIT 2026-09-17', "M${T}demo/archive/113-pin-buttons.prompt.md",
    'COMMIT 2026-09-16', "R100${T}someone/test/archive/113-pin-buttons.prompt.md${T}demo/archive/113-pin-buttons.prompt.md",
    'COMMIT 2026-09-11', "R065${T}someone/test/current/113-pin-buttons.prompt.md${T}someone/test/archive/113-pin-buttons.prompt.md",
    'COMMIT 2026-09-10', "A${T}someone/test/current/113-pin-buttons.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'demo/archive/113-pin-buttons.prompt.md' -LogLines $log
Assert-Equal 'a move OF archive/ is not a move INTO it' '2026-09-11' $d.Closed
Assert-Equal 'a later mechanical edit does not move Closed either' '2026-09-11' $d.Closed
Assert-Equal 'and Created reaches back across the rename' '2026-09-10' $d.Created

Write-Host ""
Write-Host "-- A copy from another card lends no history ----------" -ForegroundColor Cyan
# The real hub: git decided 477 was "copied from" 482 (same template, C054), and
# --follow then walks into 482's past. 477 begins where its own name begins.
$log = @(
    'COMMIT 2026-06-30', "R100${T}ms/current/477-card-truncated.prompt.md${T}ms/archive/477-card-truncated.prompt.md",
    'COMMIT 2026-06-29', "C054${T}ms/current/482-ui-campaign-card.prompt.md${T}ms/current/477-card-truncated.prompt.md",
    'COMMIT 2026-06-01', "A${T}ms/current/482-ui-campaign-card.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'ms/archive/477-card-truncated.prompt.md' -LogLines $log
Assert-Equal 'Created is where THIS card begins, not where its template-twin did' '2026-06-29' $d.Created
Assert-Equal 'and it counts only its own commits' 2 $d.Commits

# A card born INSIDE archive/ as a copy of another never "moved in": being born
# there is the entry.
$log = @(
    'COMMIT 2026-05-24', "M${T}demo/archive/Feature-37-skip-link.prompt.md",
    'COMMIT 2026-05-24', "C089${T}demo/archive/Feature-1021-skip-link.prompt.md${T}demo/archive/Feature-37-skip-link.prompt.md",
    'COMMIT 2026-05-20', "A${T}demo/archive/Feature-1021-skip-link.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'demo/archive/Feature-37-skip-link.prompt.md' -LogLines $log
Assert-Equal 'a card copied into being inside archive/ closed the day it appeared' '2026-05-24' $d.Closed

Write-Host ""
Write-Host "-- A round rename is the same card --------------------" -ForegroundColor Cyan
$log = @(
    'COMMIT 2026-07-02', "R100${T}globex/archive/200-focus.prompt.md${T}globex/archive/200-focus-r1.prompt.md",
    'COMMIT 2026-06-10', "R100${T}globex/current/200-focus.prompt.md${T}globex/archive/200-focus.prompt.md",
    'COMMIT 2026-06-02', "A${T}globex/current/200-focus.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'globex/archive/200-focus-r1.prompt.md' -LogLines $log
Assert-Equal 'round 1 closed when it was archived, not when it was renamed -r1' '2026-06-10' $d.Closed
Assert-Equal 'and its history is followed through the rename' '2026-06-02' $d.Created
Assert-Equal 'a stem drops the round suffix' '200-focus' (Get-P20CardStem 'globex/archive/200-focus-r2.prompt.md')

Write-Host ""
Write-Host "-- Reopened and archived again ------------------------" -ForegroundColor Cyan
$log = @(
    'COMMIT 2026-08-20', "R100${T}globex/current/300-x.prompt.md${T}globex/archive/300-x.prompt.md",
    'COMMIT 2026-08-10', "R100${T}globex/archive/300-x.prompt.md${T}globex/current/300-x.prompt.md",
    'COMMIT 2026-07-01', "R100${T}globex/current/300-x.prompt.md${T}globex/archive/300-x.prompt.md",
    'COMMIT 2026-06-20', "A${T}globex/current/300-x.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'globex/archive/300-x.prompt.md' -LogLines $log
Assert-Equal 'Closed is the MOST RECENT entry into archive/' '2026-08-20' $d.Closed

Write-Host ""
Write-Host "-- No history at all ----------------------------------" -ForegroundColor Cyan
$d = Get-P20CardHistoryDates -RelPath 'globex/archive/never-committed.prompt.md' -LogLines @('')
Assert-Equal 'an untracked card has no commits' 0 $d.Commits
Assert-True 'and no dates are invented for it' ($null -eq $d.Created -and $null -eq $d.Closed)

# -- The tool, against a real scratch repository ---------------------------------

Write-Host ""
Write-Host "-- The tool against a scratch hub ---------------------" -ForegroundColor Cyan

$gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (-not $gitOk) {
    Write-Host "  SKIP  git is not installed -- the end-to-end cases need a repository" -ForegroundColor DarkYellow
}
else {
    $hub = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-backfill-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path $hub -Force | Out-Null

    function Invoke-HubGit {
        param([string]$Date, [string[]]$GitArgs)
        $env:GIT_AUTHOR_DATE = "${Date}T12:00:00"
        $env:GIT_COMMITTER_DATE = "${Date}T12:00:00"
        & git -C $hub -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false -c core.autocrlf=false @GitArgs 2>&1 | Out-Null
        Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    }
    function Write-HubFile {
        param([string]$Rel, [string]$Text)
        $full = Join-Path $hub $Rel
        New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }
    function Invoke-Backfill {
        param([string[]]$ScriptArgs)
        $all = @('-PromptsRoot', $hub) + $ScriptArgs
        $out = & pwsh -NoProfile -File $targetScript @all 2>&1 | Out-String
        return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
    }

    try {
        Invoke-HubGit '2026-01-01' @('init', '-q', '-b', 'main')
        Write-HubFile 'hub.json' '{ "hub": 1, "orgs": [ { "slug": "acme", "promptsFolder": "acme" } ] }'
        # Distinct bodies, so git has no reason to call one a copy of another.
        Write-HubFile 'acme/current/140-timeout.prompt.md' "# Bug 140: timeout on large files`n`nThe reader never closes the stream.`n"
        Write-HubFile 'acme/current/141-open.prompt.md' "# Bug 141: still being worked`n`nNothing like the other one at all, on purpose.`n"
        Write-HubFile 'acme/archive/2026-01-02-PR77.prompt.md' "# PR 77 review record`n"
        Write-HubFile 'acme/archive/Migration-Plan.md' "# A migration plan, saved as plain markdown, that a review lists as work`n"
        Write-HubFile 'growth/current/training-2026-01-02-rust.prompt.md' "# Training: Rust`n"
        Invoke-HubGit '2026-01-05' @('add', '-A')
        Invoke-HubGit '2026-01-05' @('commit', '-q', '-m', 'new cards')

        New-Item -ItemType Directory -Path (Join-Path $hub 'acme/archive') -Force | Out-Null
        Invoke-HubGit '2026-01-09' @('mv', 'acme/current/140-timeout.prompt.md', 'acme/archive/140-timeout.prompt.md')
        Invoke-HubGit '2026-01-09' @('commit', '-q', '-m', 'archive: move 140')

        # A card that was stamped properly, with a Closed date history would NOT
        # give it: the stamp is the record and must survive.
        Write-HubFile 'acme/archive/150-stamped.prompt.md' "# Bug 150`n`n**Created:** 2025-12-01`n**Closed:** 2025-12-24`n"
        Invoke-HubGit '2026-01-12' @('add', '-A')
        Invoke-HubGit '2026-01-12' @('commit', '-q', '-m', 'a stamped card arrives')

        # The whole org folder is renamed later. Not an event.
        Invoke-HubGit '2026-02-01' @('mv', 'acme', 'acme-corp')
        Write-HubFile 'hub.json' '{ "hub": 1, "orgs": [ { "slug": "acme", "promptsFolder": "acme-corp" } ] }'
        Invoke-HubGit '2026-02-01' @('add', '-A')
        Invoke-HubGit '2026-02-01' @('commit', '-q', '-m', 'rename the org folder')

        $archived = Join-Path $hub 'acme-corp/archive/140-timeout.prompt.md'
        $open = Join-Path $hub 'acme-corp/current/141-open.prompt.md'
        $stamped = Join-Path $hub 'acme-corp/archive/150-stamped.prompt.md'
        $record = Join-Path $hub 'acme-corp/archive/2026-01-02-PR77.prompt.md'
        $growth = Join-Path $hub 'growth/current/training-2026-01-02-rust.prompt.md'
        $stampedBefore = [System.IO.File]::ReadAllBytes($stamped)

        # -WhatIf writes nothing.
        $preview = Invoke-Backfill @('-WhatIf')
        Assert-Equal '-WhatIf exits 0' 0 $preview.ExitCode
        Assert-True '-WhatIf reports what it would do' ($preview.Output -match 'Would write 3 file') $preview.Output
        Assert-True '-WhatIf leaves the working tree clean' (-not (& git -C $hub status --porcelain))

        $run = Invoke-Backfill @()
        Assert-Equal 'the run exits 0' 0 $run.ExitCode
        $a = Get-Content $archived -Raw
        Assert-True 'the archived card gets Created from its first commit' ($a -match '(?m)^\*\*Created:\*\* 2026-01-05\r?$') $a
        Assert-True 'and Closed from the day it moved into archive/ -- not the folder rename' ($a -match '(?m)^\*\*Closed:\*\* 2026-01-09\r?$') $a
        Assert-True 'its own text is still there, above the stamps' ($a.StartsWith('# Bug 140: timeout on large files'))
        $o = Get-Content $open -Raw
        Assert-True 'an open card gets Created' ($o -match '(?m)^\*\*Created:\*\* 2026-01-05\r?$') $o
        Assert-True 'and no Closed -- it is not closed' ($o -notmatch '\*\*Closed:\*\*')
        Assert-True 'a stamped card is byte for byte what it was' ([System.Linq.Enumerable]::SequenceEqual($stampedBefore, [System.IO.File]::ReadAllBytes($stamped)))
        $plan = Get-Content (Join-Path $hub 'acme-corp/archive/Migration-Plan.md') -Raw
        Assert-True 'a plain .md work document is dated too -- a review lists it as work' ($plan -match '(?m)^\*\*Created:\*\* 2026-01-05\r?$' -and $plan -match '(?m)^\*\*Closed:\*\* 2026-01-05\r?$') $plan
        Assert-True 'a dated PR record is not a card and is not stamped' ((Get-Content $record -Raw) -notmatch '\*\*Created:\*\*')
        Assert-True 'growth/ is not an org and is left alone' ((Get-Content $growth -Raw) -notmatch '\*\*Created:\*\*')
        $bytes = [System.IO.File]::ReadAllBytes($archived)
        Assert-True 'written with no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
        Assert-True 'and with the line ending the file already had (LF)' ($a -notmatch "`r")
        Assert-True 'nothing was committed -- the operator reviews the diff' ((@(& git -C $hub log --oneline)).Count -eq 4)

        # Idempotent.
        $again = Invoke-Backfill @()
        Assert-True 'a second run writes nothing' ($again.Output -match 'Wrote 0 file') $again.Output
        Assert-Equal 'and leaves the card as the first run left it' $a (Get-Content $archived -Raw)

        # -Org narrows it.
        $none = Invoke-Backfill @('-Org', 'no-such-org')
        Assert-True '-Org on a folder with no cards writes nothing' ($none.Output -match 'Wrote 0 file') $none.Output
    }
    finally {
        Remove-Item -Path $hub -Recurse -Force -ErrorAction SilentlyContinue
    }

    # A hub that is not a repository has no history to read: a stated refusal.
    $plain = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-backfill-plain-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $plain 'acme/archive') -Force | Out-Null
    try {
        $out = & pwsh -NoProfile -File $targetScript -PromptsRoot $plain 2>&1 | Out-String
        Assert-Equal 'a non-git hub is a stated refusal (exit 2)' 2 $LASTEXITCODE
        Assert-True 'and says why' ($out -match 'not a git repository') $out
    }
    finally {
        Remove-Item -Path $plain -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# -- A day from git is the LOCAL day ----------------------------------------------
# git's %ad/%ai carry the AUTHOR's zone; a card committed from another zone got
# that person's day as its **Created:**/**Closed:** for good. Every git reader
# now asks for %at and converts with ConvertTo-P20LocalDay.
#The table is
# shared with Tests/test_clock.py: both halves must give every row one answer.

Write-Host ""
Write-Host "-- A day from git is the local day -------------------" -ForegroundColor Cyan
$clock = Get-Content (Join-Path $PSScriptRoot 'fixtures/clock/local-days.json') -Raw | ConvertFrom-Json
foreach ($row in $clock.rows) {
    $offset = [TimeSpan]::FromMinutes([int]$row[1])
    $zone = [System.TimeZoneInfo]::CreateCustomTimeZone("p20-test-$($row[1])", $offset, "UTC$($row[1])", "UTC$($row[1])")
    Assert-Equal "$($row[3]) -> $($row[2])" ([string]$row[2]) (ConvertTo-P20LocalDay ([string]$row[0]) -TimeZone $zone)
}
Assert-True 'not a number is no day, not an error' ($null -eq (ConvertTo-P20LocalDay 'soon'))
$pacific = [System.TimeZoneInfo]::CreateCustomTimeZone('p20-test-420', [TimeSpan]::FromMinutes(-420), 'UTC-420', 'UTC-420')
Assert-Equal 'the stamp form reads the same clock' '2026-09-23 23:30' (ConvertTo-P20LocalStamp ([string]$clock.rows[0][0]) -TimeZone $pacific)
$epoch = [string][DateTimeOffset]::new(2026, 9, 23, 23, 30, 0, [TimeSpan]::FromHours(-7)).ToUnixTimeSeconds()
Assert-Equal 'with no zone given it is the machine''s own clock' ([DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).ToLocalTime().ToString('yyyy-MM-dd')) (ConvertTo-P20LocalDay $epoch)

# Backfill reads the epoch shape git now prints, as well as the day shape above.
$log = @(
    "COMMIT $epoch", "A${T}demo/current/200-late-night.prompt.md"
)
$d = Get-P20CardHistoryDates -RelPath 'demo/current/200-late-night.prompt.md' -LogLines $log
Assert-Equal 'Backfill reads %at as the local day' (ConvertTo-P20LocalDay $epoch) $d.Created

# The guard: no reader asks git for a zoned DAY again. %ad, %ai, %cd, %ci and
# --date=short all print a day in someone's zone; %at/%ct do not.
$readers = @(Get-ChildItem (Join-Path $pkgRoot 'Scripts') -Filter '*.ps1' -File) +
           @(Get-ChildItem (Join-Path $pkgRoot 'agent') -Filter '*.ps1' -File -Recurse)
$zoned = @()
foreach ($f in $readers) {
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $n++
        if ($line.TrimStart().StartsWith('#')) { continue }
        if ($line -match 'git\b.*(--format|--pretty)[^\n]*%(ad|ai|aI|cd|ci|cI)\b' -or $line -match 'git\b.*--date=short') {
            $zoned += "$($f.Name):$n"
        }
    }
}
Assert-True "no script asks git for a zoned date ($($zoned -join ', '))" ($zoned.Count -eq 0)

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
