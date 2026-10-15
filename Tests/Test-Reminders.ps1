<#
.SYNOPSIS
    The Organize add-on's reminders -- the time rules over the shared table, and
    both verbs typed in a fresh shell against a scratch package and hub.

.DESCRIPTION
    1. The rules      Tests/fixtures/reminders/buckets.json, every row: the bucket
                      rule the agent implements too, and the snooze arithmetic.
    2. Off            with features.organize unset there is no verb at all.
    3. The verbs      NewReminder and Reminders through the module, as a person
                      types them: create, the ledger, snooze, edit (each switch
                      its own line, an unchanged value writing nothing), archive,
                      and the stated refusals -- exit 2, one block, nothing written.
    4. The bytes      a created reminder is UTF-8 with no BOM and LF; a snooze of
                      a CRLF file keeps CRLF and changes only the Due line.

    Run:  pwsh -File Tests/Test-Reminders.ps1
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
Write-Host "  Reminders -- the Organize add-on" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- 1. The rules, over the table the agent reads too ---------------------------
Write-Host "-- The bucket rule and the snooze, from the shared table --" -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Resolve-CardName.ps1')
. (Join-Path $pkgRoot 'Scripts/Reminder-Rules.ps1')
$table = Get-Content (Join-Path $scriptDir 'fixtures/reminders/buckets.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fmt = 'yyyy-MM-ddTHH:mm'
foreach ($row in $table.buckets) {
    $now = [datetime]::ParseExact($row.now, $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
    $got = Get-P20ReminderBucket -Due $row.due -Now $now
    Assert-True "bucket: $($row.why)" ($got -eq $row.bucket) "due $($row.due) at $($row.now): got $got, want $($row.bucket)"
}
foreach ($row in $table.snooze) {
    $now = [datetime]::ParseExact($row.now, $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
    $got = Get-P20SnoozeDue -Word $row.word -Now $now
    Assert-True "snooze $($row.word): $($row.why)" ($got -eq $row.due) "got $got, want $($row.due)"
}
Assert-True 'a word the contract does not list is no snooze' ($null -eq (Get-P20SnoozeDue -Word 'later' -Now (Get-Date)))
$at = [datetime]::ParseExact('2026-09-23T10:15', $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
Assert-True '-Due takes a date' ((ConvertTo-P20DueValue -Text '2026-10-01' -Now $at) -eq '2026-10-01')
Assert-True '-Due takes a date and time, with a T or a space' ((ConvertTo-P20DueValue -Text '2026-10-01 14:30' -Now $at) -eq '2026-10-01T14:30')
Assert-True '-Due takes a snooze word' ((ConvertTo-P20DueValue -Text 'tomorrow' -Now $at) -eq '2026-09-24T09:00')
Assert-True '-Due refuses a date that is not one' ($null -eq (ConvertTo-P20DueValue -Text '2026-02-30' -Now $at))
Assert-True '-Due refuses words it does not know' ($null -eq (ConvertTo-P20DueValue -Text 'yesterday' -Now $at))

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-reminders-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
New-Item -ItemType Directory -Path $pkg, $logDir, (Join-Path $hub 'demo/current') -Force | Out-Null
foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'),
    '{ "orgs": [ { "slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo" } ] }', $utf8)
$hubJson = $hub -replace '\\', '/'
$localConfig = Join-Path $pkg 'config.local.json'

function Invoke-Verbs {
    # A fresh shell per call, the package's own module and nothing else, the way
    # a person types a verb (AGENTS.md, "One toolkit per shell").
    param([string]$Snippet, [bool]$On = $true)
    $features = if ($On) { '{ "organize": true }' } else { '{}' }
    [System.IO.File]::WriteAllText($localConfig,
        "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"demo`", `"quietStart`": true, `"features`": $features }", $utf8)
    $body = "`$env:PSModulePath = '$($pkg -replace "'", "''")'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$($logDir -replace "'", "''")'; " +
        "Import-Module '$($pkg -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; $Snippet"
    return ((& pwsh -NoProfile -NonInteractive -Command $body 2>&1 | ForEach-Object { "$_" }) -join "`n")
}

try {
    # -- 2. Off means absent ---------------------------------------------------------
    Write-Host ""
    Write-Host "-- Off: no verb ----------------------------------------" -ForegroundColor Cyan
    $off = Invoke-Verbs "'NEW=' + [bool](Get-Command tkNewReminder -ErrorAction SilentlyContinue); 'LIST=' + [bool](Get-Command tkReminders -ErrorAction SilentlyContinue); 'MAP=' + (Get-P20CommandMap)" -On $false
    Assert-True 'with the flag off NewReminder does not exist' ($off -match 'NEW=False') $off
    Assert-True 'nor does Reminders' ($off -match 'LIST=False') $off
    Assert-True 'and the bridge has nothing to call' ($off -notmatch '"Reminders"') $off

    # -- 3. The verbs, as typed ----------------------------------------------------
    Write-Host ""
    Write-Host "-- On: the verbs, as typed ------------------------------" -ForegroundColor Cyan
    $out = Invoke-Verbs "tkNewReminder -Title 'Review sprint goals' -Due 2020-01-01; 'A=' + `$LASTEXITCODE; tkNewReminder -Title 'Book the training' -Due tomorrow -Source goal -Ref 'Clean Architecture'; tkNewReminder -Title 'Someday'; tkReminders; 'L=' + `$LASTEXITCODE"
    Assert-True 'NewReminder creates, and says the id and bucket' ($out -match 'Created reminder [A-Z0-9]{4} \(overdue, due 2020-01-01\)' -and $out -match 'A=0') $out
    $current = Join-Path $hub 'reminders/current'
    $files = @(Get-ChildItem $current -Filter '*.md' -File -ErrorAction SilentlyContinue)
    Assert-True 'three files, in reminders/current/, named <ID>-<slug>.md' ($files.Count -eq 3 -and @($files | Where-Object { $_.Name -cmatch '^[A-Z0-9]{4}-[a-z0-9-]+\.md$' }).Count -eq 3) (($files | ForEach-Object Name) -join ', ')
    Assert-True 'the ledger groups by bucket, overdue first' ($out -match '(?s)OVERDUE \(1\).*Review sprint goals.*UPCOMING \(2\)') $out
    Assert-True 'the source and ref are the row tag' ($out -match '\[goal Clean Architecture\]' -and $out -match '\[manual\]') $out
    Assert-True 'the ledger exits 0' ($out -match 'L=0') $out

    $review = @($files | Where-Object { $_.Name -like '*review-sprint-goals*' })[0]
    $text = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True 'the file is an H1 and the house footer, and stores nothing derived' ($text -match '(?m)^# Review sprint goals$' -and $text -match '(?m)^\*\*Due:\*\* 2020-01-01$' -and $text -match '(?m)^\*\*Source:\*\* manual$' -and $text -match '(?m)^\*\*Created:\*\* \d{4}-\d{2}-\d{2}$' -and $text -notmatch '(?i)overdue') $text
    # -- 4. The bytes ---------------------------------------------------------------
    $bytes = [System.IO.File]::ReadAllBytes($review.FullName)
    Assert-True 'created with no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    Assert-True 'created LF' (-not $text.Contains("`r`n"))

    $id = $review.Name.Substring(0, 4)
    [System.IO.File]::WriteAllText($review.FullName, ($text -replace "`n", "`r`n"), $utf8)
    $before = [System.IO.File]::ReadAllText($review.FullName)
    $out = Invoke-Verbs "tkReminders $id -Snooze tomorrow; 'S=' + `$LASTEXITCODE"
    $after = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True 'Snooze says what it did and exits 0' ($out -match "Snoozed $id-" -and $out -match 'S=0') $out
    Assert-True 'Snooze rewrote the Due line to tomorrow at 09:00' ($after -match ('\*\*Due:\*\* ' + (Get-Date).AddDays(1).ToString('yyyy-MM-dd') + 'T09:00')) $after
    $beforeRest = ($before -split "`r`n" | Where-Object { $_ -notmatch '^\*\*Due:\*\*' }) -join '|'
    $afterRest = ($after -split "`r`n" | Where-Object { $_ -notmatch '^\*\*Due:\*\*' }) -join '|'
    Assert-True 'and nothing else: same file, same lines' ($beforeRest -eq $afterRest -and (Test-Path $review.FullName)) $after
    Assert-True 'a CRLF reminder stays CRLF' (-not ($after -replace "`r`n", '').Contains("`n"))

    # -- 5. Edit: correct the entry, one line per switch --------------------------
    Write-Host ""
    Write-Host "-- Edit: each switch rewrites its own line --------------" -ForegroundColor Cyan
    $before = [System.IO.File]::ReadAllText($review.FullName)
    $out = Invoke-Verbs "tkReminders $id -Due '2026-10-01 14:00'; 'E=' + `$LASTEXITCODE"
    $after = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True '-Due says what it changed and exits 0' ($out -match "Updated $id-.*due 2026-10-01T14:00" -and $out -match 'E=0') $out
    Assert-True '-Due rewrote the Due line, a space read as the T' ($after -match '(?m)^\*\*Due:\*\* 2026-10-01T14:00\r?$') $after
    $beforeRest = ($before -split "`r`n" | Where-Object { $_ -notmatch '^\*\*Due:\*\*' }) -join '|'
    $afterRest = ($after -split "`r`n" | Where-Object { $_ -notmatch '^\*\*Due:\*\*' }) -join '|'
    Assert-True 'and nothing else: the title, source and Created kept' ($beforeRest -eq $afterRest) $after
    Assert-True 'an edited CRLF reminder stays CRLF' (-not ($after -replace "`r`n", '').Contains("`n"))

    $before = $after
    $out = Invoke-Verbs "tkReminders $id -Title 'Review the sprint goals'; 'T=' + `$LASTEXITCODE"
    $after = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True '-Title rewrites the heading and exits 0' ($after -match '(?m)^# Review the sprint goals\r?$' -and $out -match 'T=0') $out
    Assert-True 'and keeps the filename -- the id is the identity' (Test-Path $review.FullName) (($files | ForEach-Object Name) -join ', ')
    $beforeRest = ($before -split "`r`n" | Where-Object { $_ -notmatch '^# ' }) -join '|'
    $afterRest = ($after -split "`r`n" | Where-Object { $_ -notmatch '^# ' }) -join '|'
    Assert-True 'and changes no other line' ($beforeRest -eq $afterRest) $after

    $stamp = (Get-Item $review.FullName).LastWriteTimeUtc
    Start-Sleep -Milliseconds 1100
    $out = Invoke-Verbs "tkReminders $id -Title 'Review the sprint goals' -Due 2026-10-01T14:00; 'U=' + `$LASTEXITCODE"
    Assert-True 'the same values again is a report, exit 0' ($out -match '\[=\] Unchanged' -and $out -match 'U=0') $out
    Assert-True 'and writes nothing' ((Get-Item $review.FullName).LastWriteTimeUtc -eq $stamp) 'the file was rewritten'

    $out = Invoke-Verbs "tkReminders $id -NoDue; 'N=' + `$LASTEXITCODE"
    $after = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True '-NoDue removes the Due line' ($after -notmatch '\*\*Due:\*\*' -and $out -match 'no due date' -and $out -match 'N=0') $out
    $out = Invoke-Verbs "tkReminders $id -Due 2020-01-01; 'D=' + `$LASTEXITCODE"
    $after = [System.IO.File]::ReadAllText($review.FullName)
    Assert-True '-Due puts a Due line back, above Created' ($after -match '(?s)\*\*Due:\*\* 2020-01-01.*\*\*Created:\*\*' -and $out -match '\(overdue\)' -and $out -match 'D=0') $after

    $training = @(Get-ChildItem $current -Filter '*book-the-training*' -File)[0]
    $tid = $training.Name.Substring(0, 4)
    $out = Invoke-Verbs "tkReminders $tid -Source ado -Ref 'Task 139'; 'S2=' + `$LASTEXITCODE"
    $t = [System.IO.File]::ReadAllText($training.FullName)
    Assert-True '-Source and -Ref together rewrite both lines' ($t -match '(?m)^\*\*Source:\*\* ado$' -and $t -match '(?m)^\*\*Ref:\*\* Task 139$' -and $out -match 'S2=0') $t
    $out = Invoke-Verbs "tkReminders $tid -Ref ''; 'R0=' + `$LASTEXITCODE"
    $t = [System.IO.File]::ReadAllText($training.FullName)
    Assert-True 'an empty -Ref removes the ref line' ($t -notmatch '\*\*Ref:\*\*' -and $t -match '(?m)^\*\*Source:\*\* ado$' -and $out -match 'no ref' -and $out -match 'R0=0') $t

    $out = Invoke-Verbs "tkReminders $id -Archive; 'R=' + `$LASTEXITCODE; tkReminders $id -Archive; 'R2=' + `$LASTEXITCODE"
    $archived = Join-Path $hub "reminders/archive/$($review.Name)"
    Assert-True 'Archive moves it to reminders/archive/' ((Test-Path $archived) -and -not (Test-Path $review.FullName) -and $out -match 'R=0') $out
    Assert-True 'and stamps Closed' ((Test-Path $archived) -and ([System.IO.File]::ReadAllText($archived)) -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}') 'no stamp'
    Assert-True 'a second Archive is a report, not an error' ($out -match 'Already archived' -and $out -match 'R2=0') $out

    Write-Host ""
    Write-Host "-- Refusals: stated, exit 2, one block -----------------" -ForegroundColor Cyan
    $refusals = @(
        @{ Name = 'no title'; Snippet = "tkNewReminder -Due tomorrow"; Want = 'needs a title' }
        @{ Name = 'a due that is not one'; Snippet = "tkNewReminder -Title x -Due yesterday"; Want = "'yesterday' is not a due date" }
        @{ Name = 'a snooze word it does not know'; Snooze = $true; Snippet = "tkReminders ID -Snooze later"; Want = "'later' is not a snooze" }
        @{ Name = 'an id nothing carries'; Snippet = "tkReminders ZZ99 -Archive"; Want = "No open reminder with id 'ZZ99'" }
        @{ Name = 'an id is not a substring'; Snippet = "tkReminders 9 -Archive"; Want = "No open reminder with id '9'" }
        @{ Name = 'a switch with no id'; Snippet = "tkReminders -Snooze 1h"; Want = 'need its id' }
        @{ Name = 'an id with no switch'; Snippet = "tkReminders ID"; Want = 'Nothing to do to' }
        @{ Name = 'a partial name'; Snippet = "tkReminders training -Archive"; Want = 'is not a reminder id' }
        @{ Name = 'an edit with no id'; Snippet = "tkReminders -Title x"; Want = 'need its id' }
        @{ Name = 'an edit due that is not one'; Snippet = "tkReminders ID -Due yesterday"; Want = "'yesterday' is not a due date" }
        @{ Name = 'an empty title'; Snippet = "tkReminders ID -Title ''"; Want = 'needs a title' }
        @{ Name = 'an empty source'; Snippet = "tkReminders ID -Source ''"; Want = 'needs a source' }
        @{ Name = 'edit and archive'; Snippet = "tkReminders ID -Title x -Archive"; Want = 'Edit or archive, not both' }
        @{ Name = 'snooze and due'; Snippet = "tkReminders ID -Snooze 1h -Due tomorrow"; Want = 'both set the due time' }
        @{ Name = 'due and no due'; Snippet = "tkReminders ID -Due tomorrow -NoDue"; Want = '-Due and -NoDue, not both' }
    )
    $openId = (@(Get-ChildItem $current -Filter '*.md' -File)[0]).Name.Substring(0, 4)
    $openFile = @(Get-ChildItem $current -Filter "$openId-*.md" -File)[0].FullName
    $openBytes = [System.IO.File]::ReadAllText($openFile)
    foreach ($r in $refusals) {
        $snip = $r.Snippet -replace '\bID\b', $openId
        $out = Invoke-Verbs "$snip; 'X=' + `$LASTEXITCODE"
        Assert-True "refused: $($r.Name)" ($out -match [regex]::Escape($r.Want) -and $out -match 'X=2' -and (@([regex]::Matches($out, '(?m)^Error: ')).Count -eq 1) -and $out -notmatch 'exit code') $out
    }
    Assert-True 'a refused edit wrote nothing' ([System.IO.File]::ReadAllText($openFile) -ceq $openBytes) 'the file changed'

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
    Write-P20TestResult -Suite 'Reminders' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
