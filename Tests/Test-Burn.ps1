<#
.SYNOPSIS
    Burn -- the current burn (today and this week), and Burn -Log's day record, typed.
.DESCRIPTION
    Typed as the VERB in a fresh child shell against a scratch copy of the
    package and of samples/hub (AGENTS.md: a suite that runs a script directly
    does not test the verb; samples/hub is never used in place), with
    CLAUDE_CONFIG_DIR pointing the reader at scratch projects folders built from
    Tests/fixtures/usage/. Every line time is built from the logged day's LOCAL
    midnight when the suite runs, so the suite reads the same in any timezone.
    Holds:

    1. Registration  the command table the bridge reads, -Help from config,
                     the autoload manifest, the inventory row.
    2. Refusals      no -Log, a -Date that is not a day, a day not yet come:
                     exit 2, one Error block, nothing written.
    3. No folder     a machine without Claude Code's projects folder writes
                     nothing and says so, exit 0.
    4. The table     Tests/fixtures/usage/cases.json, one row per input the
                     rule distinguishes: an empty day, two models, a session
                     across midnight, the lines of one response counted once,
                     a subagent's transcript, an unpriced model, a dated
                     snapshot, a malformed line, no cache breakdown, a file
                     untouched since before the day, the project names.
    5. One record    Tests/fixtures/usage/day.json writes exactly
                     Tests/fixtures/usage/record.json: UTF-8, no BOM, LF.
    6. Re-run        the same day again replaces the record: one file, the
                     same bytes.
    7. Privacy       no record carries a path, the home folder or a user name.
    8. Read-only     every file under the projects folders keeps its bytes and
                     its last write time.
    9. The gate      Tests/fixtures/usage/projects-root.json, the rule the
                     inventory row and the agent's /env flag share
                     (Tests/test_usage_burn.py asserts the same rows).
   10. The week      Tests/fixtures/usage/week.json: burn.weekStarts' values,
                     the windows at a given now under Friday 05:00 (the
                     default), Monday 09:00 and Sunday 00:00, another machine's
                     record counting toward the week it starts in (a record
                     dated the week's first day is the week before's), and
                     both halves at one now.
   11. The burn      Burn and Burn -AsJson typed at a fixed -At: this machine's
                     session files plus another machine's records, this
                     machine's own record not read twice, a file that is not
                     a record skipped; -At's refusals; burn.weekStarts set
                     through Config (a bad value refused) and read by Burn,
                     and one Burn cannot read refused naming the key.
   12. The burndown  Tests/fixtures/usage/burndown.json, the rule from typed
                     readings to each bucket's percent, pace and gap and the
                     cache line (no reading, one bucket, ahead, behind, on pace,
                     rounding, latest wins, stale, past reset, after now);
                     burn.cacheHours' range; what -Reading accepts.
   13. -Reading      Burn -Reading typed: the week's record started and
                     appended (UTF-8, no BOM, LF), another machine's readings
                     merged, last week's not counted, the refusals writing
                     nothing, Burn and -AsJson carrying the burndown, a new week
                     empty, burn.cacheHours set through Config and read by Burn.

    Run:  pwsh -File Tests/Test-Burn.ps1
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

$ErrorActionPreference = 'Stop'
$pkgRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}
function Assert-Equal($label, $expected, $actual, $detail = '') {
    if ("$expected" -eq "$actual") { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label -- expected '$expected', got '$actual'$(if ($detail) { "`n        $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-burn-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$outDir = Join-Path $root 'out'
$claudeRoot = Join-Path $root 'claude'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$fixtures = Join-Path $PSScriptRoot 'fixtures/usage'
# The child runs on the host running this suite, so Windows PowerShell 5.1 is exercised where it runs it.
$hostExe = (Get-Process -Id $PID).Path

function Get-DayStart([string]$Day) {
    $d = [DateTime]::ParseExact($Day, 'yyyy-MM-dd', $inv)
    return [DateTime]::SpecifyKind($d, [DateTimeKind]::Local)
}
function Get-SpecInstant([DateTime]$DayStart, [string]$Offset) {
    # "+09:30" or "-00:30" from the day's local midnight, as the UTC text a session file carries.
    $m = [regex]::Match($Offset, '^([+-])(\d{1,2}):(\d{2})$')
    $minutes = [int]$m.Groups[2].Value * 60 + [int]$m.Groups[3].Value
    if ($m.Groups[1].Value -eq '-') { $minutes = -$minutes }
    return $DayStart.AddMinutes($minutes).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv)
}
function ConvertTo-SessionLine($Spec, [DateTime]$DayStart) {
    # One line spec rendered as Claude Code writes an assistant line.
    if ($Spec.PSObject.Properties['raw']) { return [string]$Spec.raw }
    $n = { param($name) if ($Spec.PSObject.Properties[$name]) { [long]$Spec.$name } else { [long]0 } }
    $usage = [ordered]@{
        input_tokens                = (& $n 'in')
        cache_creation_input_tokens = ((& $n 'w5') + (& $n 'w1'))
        cache_read_input_tokens     = (& $n 'read')
        output_tokens               = (& $n 'out')
        output_tokens_details       = [ordered]@{ thinking_tokens = (& $n 'think') }
        service_tier                = 'standard'
    }
    if (-not $Spec.PSObject.Properties['noBreakdown']) {
        $usage['cache_creation'] = [ordered]@{ ephemeral_1h_input_tokens = (& $n 'w1'); ephemeral_5m_input_tokens = (& $n 'w5') }
    }
    $message = [ordered]@{ model = [string]$Spec.model }
    if ($Spec.PSObject.Properties['id']) { $message['id'] = [string]$Spec.id }
    $message['type'] = 'message'
    $message['role'] = 'assistant'
    $message['content'] = @([ordered]@{ type = 'text'; text = 'ok' })
    $message['usage'] = $usage
    $line = [ordered]@{ parentUuid = $null; isSidechain = [bool]($Spec.PSObject.Properties['side'] -and $Spec.side); message = $message }
    if ($Spec.PSObject.Properties['req']) { $line['requestId'] = [string]$Spec.req }
    $line['type'] = 'assistant'
    $line['uuid'] = [guid]::NewGuid().ToString()
    $line['timestamp'] = Get-SpecInstant $DayStart ([string]$Spec.t)
    if ($Spec.PSObject.Properties['cwd']) { $line['cwd'] = [string]$Spec.cwd }
    $line['sessionId'] = [string]$Spec.sid
    return ($line | ConvertTo-Json -Compress -Depth 10)
}
function New-ProjectsTree($Files, [string]$ConfigDir, [DateTime]$DayStart) {
    # A scratch Claude Code configuration folder with projects/<files> in it.
    $projects = Join-Path $ConfigDir 'projects'
    New-Item -ItemType Directory -Path $projects -Force | Out-Null
    foreach ($p in @($Files.PSObject.Properties)) {
        $lines = $p.Value
        $mtime = $DayStart.AddDays(1).AddHours(12)
        if ($lines -isnot [System.Array] -and $lines.PSObject.Properties['lines']) {
            if ($lines.PSObject.Properties['mtimeDays']) { $mtime = $DayStart.AddDays([double]$lines.mtimeDays) }
            $lines = $lines.lines
        }
        $path = Join-Path $projects $p.Name
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $text = ((@($lines) | ForEach-Object { ConvertTo-SessionLine $_ $DayStart }) -join "`n") + "`n"
        [System.IO.File]::WriteAllText($path, $text, $utf8)
        [System.IO.File]::SetLastWriteTime($path, $mtime)
    }
}
function Invoke-Burn([string]$Snippet) {
    $pkg = $pkgDir -replace "'", "''"; $log = $logDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"
    $text = @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
$Snippet
"EXIT=`$LASTEXITCODE"
"@
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, $text, $utf8)
    $out = & $hostExe -NoProfile -NonInteractive -File $runner 2>&1
    Remove-Item $runner -Force -ErrorAction SilentlyContinue
    $all = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $code = ''
    $m = [regex]::Matches($all, 'EXIT=(\d*)')
    if ($m.Count) { $code = $m[$m.Count - 1].Groups[1].Value }
    return [pscustomobject]@{ All = $all; Exit = $code }
}
function Get-Section([string]$All, [string]$Name) {
    # The output between BEGIN:<name> and END:<name>=<exit>, with the exit.
    $m = [regex]::Match($All, "(?s)BEGIN:$([regex]::Escape($Name))\r?\n(.*?)END:$([regex]::Escape($Name))=(\d*)")
    return [pscustomobject]@{ Text = $m.Groups[1].Value; Exit = $m.Groups[2].Value; Found = $m.Success }
}
function Get-TreeSnapshot([string]$Dir) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ((@(Get-ChildItem -LiteralPath $Dir -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
                        $hash = [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($_.FullName)))
                        "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$hash"
                    })) -join "`n")
    }
    finally { $sha.Dispose() }
}
function Format-Cost($Value) {
    if ($null -eq $Value) { return 'null' }
    return ([decimal]$Value).ToString($inv)
}
function Test-NoPrivateText([string]$Label, [string]$Text) {
    # The machine line is the record's one name for where it was written, so it is set aside.
    $body = ($Text -split "`n" | Where-Object { $_ -notmatch '^\s*"machine":' }) -join "`n"
    $userHome = [System.Environment]::GetFolderPath('UserProfile')
    $userName = [System.Environment]::UserName
    $found = @()
    foreach ($needle in @('/Users/', '/home/', 'C:\', 'C:\\', '\Users\', '\\Users\\', 'alex')) { if ($body.Contains($needle)) { $found += $needle } }
    if ($userHome -and $body.Contains($userHome)) { $found += 'the home folder' }
    if ($userName -and $userName.Length -ge 3 -and $body.IndexOf($userName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $found += 'the user name' }
    Assert-True "$Label carries no path, home folder or user name" ($found.Count -eq 0) ("found: " + ($found -join ', '))
}

Write-Host ""
Write-Host "  Burn -- the current burn, and Burn -Log's day record, typed" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-Item -ItemType Directory -Path $pkgDir, $logDir, $outDir, $claudeRoot -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates', 'agentic')) { Copy-Item (Join-Path $pkgRoot $folder) $pkgDir -Recurse -Force }
    Copy-Item (Join-Path $pkgRoot 'samples/hub') $hubDir -Recurse -Force
    $local = [ordered]@{ quietStart = $true; promptsRoot = ($hubDir -replace '\\', '/') }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), $utf8)

    . (Join-Path $pkgRoot 'Scripts/Read-ClaudeUsage.ps1')
    $machine = Get-P20UsageMachineName
    $cases = [System.IO.File]::ReadAllText((Join-Path $fixtures 'cases.json')) | ConvertFrom-Json
    $dayKey = [string]$cases.day
    $dayStart = Get-DayStart $dayKey
    $usageDir = Join-Path $hubDir 'usage'
    $recordPath = Join-Path $usageDir "$dayKey-$machine.json"
    $noFolder = Join-Path $claudeRoot 'none'
    New-Item -ItemType Directory -Path $noFolder -Force | Out-Null

    # -- 1. Registration ------------------------------------------------------------------
    Write-Host "-- Registration ----------------------------------------" -ForegroundColor Cyan
    $reg = Invoke-Burn "'MAP=' + (Get-P20CommandMap); tkBurn -Help"
    Assert-True 'Burn is in the command table the bridge reads' ($reg.All -match '"Burn":\s*"Invoke-P20Burn"') $reg.All
    Assert-True '-Help prints the usage from config' ($reg.All.Contains('tkBurn [-AsJson] [-At <yyyy-mm-dd HH:mm>] [-Reading <bucket=percent,...>] [-Log] [-Date <yyyy-mm-dd>]')) $reg.All
    $manifest = Get-Content (Join-Path $pkgRoot 'Prompt20Toolkit/Prompt20Toolkit.psd1') -Raw
    Assert-True 'the autoload manifest names tkBurn (core, no flag)' ($manifest -match "'tkBurn',")

    . (Join-Path $pkgRoot 'Scripts/Get-OptionalSurfaces.ps1')
    $savedConfigDir = [System.Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR')
    try {
        [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $noFolder)
        $rowOff = @(Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot) | Where-Object { $_.key -eq 'claudeUsage' }
        New-Item -ItemType Directory -Path (Join-Path $claudeRoot 'surface/projects') -Force | Out-Null
        [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', (Join-Path $claudeRoot 'surface'))
        $rowOn = @(Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot) | Where-Object { $_.key -eq 'claudeUsage' }
    }
    finally { [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $savedConfigDir) }
    Assert-Equal 'the inventory names Claude Code usage: not configured with no projects folder' 'not configured' $rowOff.state
    Assert-Equal 'and on where the folder is' 'on' $rowOn.state
    Assert-True 'the row carries its question' (-not [string]::IsNullOrWhiteSpace($rowOn.question)) $rowOn.question
    Assert-True 'and names the verb' ($rowOn.note -match 'tkBurn -Log') $rowOn.note

    # -- 2. Refusals and 3. no folder --------------------------------------------------------
    Write-Host ""
    Write-Host "-- Refusals, and a machine with no session files ------" -ForegroundColor Cyan
    New-ProjectsTree $cases.cases[1].files (Join-Path $claudeRoot 'refusals') $dayStart
    $refusalDir = (Join-Path $claudeRoot 'refusals') -replace "'", "''"
    $calls = @(
        @{ Name = 'datealone'; Call = 'tkBurn -Date 2026-07-15' }
        @{ Name = 'logjson'; Call = 'tkBurn -Log -AsJson' }
        @{ Name = 'notaday'; Call = 'tkBurn -Log -Date 2026-7-15' }
        @{ Name = 'impossible'; Call = 'tkBurn -Log -Date 2026-02-30' }
        @{ Name = 'future'; Call = "tkBurn -Log -Date $((Get-Date).AddDays(2).ToString('yyyy-MM-dd', $inv))" }
    )
    $snippet = "`$env:CLAUDE_CONFIG_DIR = '$refusalDir'`n"
    foreach ($c in $calls) { $snippet += "'BEGIN:$($c.Name)'`n$($c.Call)`n'END:$($c.Name)=' + `$LASTEXITCODE`n" }
    $snippet += "`$env:CLAUDE_CONFIG_DIR = '$($noFolder -replace "'", "''")'`n'BEGIN:none'`ntkBurn -Log -Date $dayKey`n'END:none=' + `$LASTEXITCODE`n"
    $r = Invoke-Burn $snippet
    $s = Get-Section $r.All 'datealone'
    Assert-True '-Date without -Log: exit 2, the refusal names -Log' ($s.Exit -eq '2' -and $s.Text.Contains('-Date names the day -Log writes')) $s.Text
    Assert-True 'one Error block, no generic exit-code block' ((@([regex]::Matches($s.Text, '(?m)^Error: ')).Count -eq 1) -and $s.Text -notmatch 'exit code') $s.Text
    $s = Get-Section $r.All 'logjson'
    Assert-True '-Log with -AsJson: exit 2, the refusal says -AsJson is the current burn''s' ($s.Exit -eq '2' -and $s.Text.Contains('-AsJson is the current burn')) $s.Text
    $s = Get-Section $r.All 'notaday'
    Assert-True 'a -Date that is not yyyy-mm-dd: exit 2' ($s.Exit -eq '2' -and $s.Text.Contains('is not a day')) $s.Text
    $s = Get-Section $r.All 'impossible'
    Assert-True 'a -Date that is no day of the calendar: exit 2' ($s.Exit -eq '2' -and $s.Text.Contains('is not a day')) $s.Text
    $s = Get-Section $r.All 'future'
    Assert-True 'a day that has not come: exit 2' ($s.Exit -eq '2' -and $s.Text.Contains('has not happened yet')) $s.Text
    Assert-True 'the refusals wrote nothing into the hub' (-not (Test-Path -LiteralPath $usageDir)) $usageDir
    $s = Get-Section $r.All 'none'
    Assert-True 'no projects folder: exit 0, and it says so' ($s.Exit -eq '0' -and $s.Text.Contains('No Claude Code session files on this machine') -and $s.Text.Contains('Nothing written')) $s.Text
    Assert-True 'and writes nothing' (-not (Test-Path -LiteralPath $usageDir)) $usageDir

    # -- 4. The table, 5. the documented record, 6. a re-run ----------------------------------
    Write-Host ""
    Write-Host "-- The table: Tests/fixtures/usage/cases.json ---------" -ForegroundColor Cyan
    $rows = @($cases.cases)
    $snippet = ''
    $rec = $recordPath -replace "'", "''"
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $dir = Join-Path $claudeRoot "case$i"
        New-ProjectsTree $rows[$i].files $dir $dayStart
        $snippet += "`$env:CLAUDE_CONFIG_DIR = '$($dir -replace "'", "''")'`nRemove-Item -LiteralPath '$rec' -ErrorAction SilentlyContinue`n"
        $snippet += "'BEGIN:case$i'`ntkBurn -Log -Date $dayKey`n'END:case$i=' + `$LASTEXITCODE`n"
        $snippet += "if (Test-Path -LiteralPath '$rec') { Copy-Item -LiteralPath '$rec' -Destination '$((Join-Path $outDir "case$i.json") -replace "'", "''")' }`n"
    }
    $day = [System.IO.File]::ReadAllText((Join-Path $fixtures 'day.json')) | ConvertFrom-Json
    $dayDir = Join-Path $claudeRoot 'day'
    New-ProjectsTree $day.files $dayDir $dayStart
    $snippet += "`$env:CLAUDE_CONFIG_DIR = '$($dayDir -replace "'", "''")'`nRemove-Item -LiteralPath '$rec' -ErrorAction SilentlyContinue`n"
    foreach ($round in @('first', 'second')) {
        $snippet += "'BEGIN:$round'`ntkBurn -Log -Date $dayKey`n'END:$round=' + `$LASTEXITCODE`n"
        $snippet += "Copy-Item -LiteralPath '$rec' -Destination '$((Join-Path $outDir "$round.json") -replace "'", "''")'`n"
    }
    $before = Get-TreeSnapshot $claudeRoot
    $r = Invoke-Burn $snippet
    $after = Get-TreeSnapshot $claudeRoot

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $s = Get-Section $r.All "case$i"
        $out = Join-Path $outDir "case$i.json"
        if (-not ($s.Exit -eq '0' -and (Test-Path -LiteralPath $out))) {
            Assert-True "$($row.name): exit 0 and a record" $false $s.Text
            continue
        }
        $text = [System.IO.File]::ReadAllText($out)
        $got = $text | ConvertFrom-Json
        $wrong = @()
        foreach ($p in @($row.expect.totals.PSObject.Properties)) {
            if ($p.Name -eq 'costUsdDerived') { $actual = Format-Cost $got.totals.costUsdDerived }
            else { $actual = [string]$got.totals.($p.Name) }
            if ([string]$p.Value -ne $actual) { $wrong += "totals.$($p.Name) $actual, not $($p.Value)" }
        }
        $models = (@($got.byModel | ForEach-Object { "$($_.model)=$(Format-Cost $_.costUsdDerived)" }) -join ', ')
        if ($models -ne (@($row.expect.models) -join ', ')) { $wrong += "models [$models], not [$(@($row.expect.models) -join ', ')]" }
        if (@($got.bySession).Count -ne [int]$row.expect.sessions) { $wrong += "$(@($got.bySession).Count) sessions, not $($row.expect.sessions)" }
        if ((@($got.unpriced) -join ', ') -ne (@($row.expect.unpriced) -join ', ')) { $wrong += "unpriced [$(@($got.unpriced) -join ', ')]" }
        if ($row.expect.PSObject.Properties['projects']) {
            $projects = (@($got.bySession | ForEach-Object { $_.project }) -join ', ')
            if ($projects -ne (@($row.expect.projects) -join ', ')) { $wrong += "projects [$projects], not [$(@($row.expect.projects) -join ', ')]" }
        }
        if ($row.expect.PSObject.Properties['skipped'] -and -not $s.Text.Contains("$($row.expect.skipped) line(s) could not be read")) { $wrong += 'the skipped line is not said' }
        Assert-True $row.name ($wrong.Count -eq 0) (($wrong -join '; ') + "`n" + $s.Text)
        Test-NoPrivateText "  the record for '$($row.name)'" $text
    }

    Write-Host ""
    Write-Host "-- One record: Tests/fixtures/usage/record.json --------" -ForegroundColor Cyan
    $s = Get-Section $r.All 'first'
    Assert-True 'the documented day: exit 0, written, with the path said' ($s.Exit -eq '0' -and $s.Text.Contains('Wrote the Claude Code usage for ' + $dayKey) -and $s.Text.Contains($recordPath)) $s.Text
    $expected = [System.IO.File]::ReadAllText((Join-Path $fixtures 'record.json')).Replace("`r`n", "`n")
    $offset = [TimeZoneInfo]::Local.GetUtcOffset($dayStart)
    $sign = '+'
    if ($offset -lt [TimeSpan]::Zero) { $sign = '-' }
    $expected = $expected.Replace('{machine}', $machine).Replace('{timezone}', [TimeZoneInfo]::Local.Id).Replace('{utcOffset}', ($sign + [Math]::Abs($offset.Hours).ToString('00') + ':' + [Math]::Abs($offset.Minutes).ToString('00')))
    foreach ($t in @('+09:00', '+09:05', '+14:00', '+14:10')) { $expected = $expected.Replace("{$t}", (Get-SpecInstant $dayStart $t)) }
    $firstBytes = [System.IO.File]::ReadAllBytes((Join-Path $outDir 'first.json'))
    $firstText = $utf8.GetString($firstBytes)
    Assert-Equal 'the record is the documented one, byte for byte' $expected $firstText
    Assert-True 'UTF-8 with no BOM' (-not ($firstBytes.Length -ge 3 -and $firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF))
    Assert-True 'LF, no CR, one newline at the end' ((-not $firstText.Contains("`r")) -and $firstText.EndsWith("}`n") -and -not $firstText.EndsWith("`n`n"))
    Assert-True 'the console names the derived cost and the price table' ($s.Text.Contains('$0.17 derived') -and $s.Text.Contains('as of 2026-10-06') -and $s.Text.Contains('claude-mystery-9')) $s.Text
    Test-NoPrivateText 'the documented record' $firstText

    Write-Host ""
    Write-Host "-- A second run that day ------------------------------" -ForegroundColor Cyan
    $s = Get-Section $r.All 'second'
    Assert-True 'exit 0, and it says the record was replaced' ($s.Exit -eq '0' -and $s.Text.Contains('Replaced the Claude Code usage for ' + $dayKey)) $s.Text
    Assert-Equal 'the same bytes' ([BitConverter]::ToString($firstBytes)) ([BitConverter]::ToString([System.IO.File]::ReadAllBytes((Join-Path $outDir 'second.json'))))
    $records = @(Get-ChildItem -LiteralPath $usageDir -File)
    Assert-Equal 'one file in usage/, named <day>-<machine>.json' "$dayKey-$machine.json" (($records | ForEach-Object { $_.Name }) -join ', ')

    Write-Host ""
    Write-Host "-- Read-only over the projects folders ----------------" -ForegroundColor Cyan
    Assert-True 'every file under the projects folders kept its bytes and its last write time' ($before -eq $after)
    Assert-True 'and nothing was added there' ((@($before -split "`n").Count) -eq (@($after -split "`n").Count))
    Assert-True 'the usage log names the verb' ((@(Get-ChildItem -LiteralPath $logDir -Filter 'usage.*.log' -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n") -match 'tkBurn')

    # -- 9. The gate: Tests/fixtures/usage/projects-root.json --------------------------------
    Write-Host ""
    Write-Host "-- The gate: Tests/fixtures/usage/projects-root.json --" -ForegroundColor Cyan
    $gate = [System.IO.File]::ReadAllText((Join-Path $fixtures 'projects-root.json')) | ConvertFrom-Json
    $gateRoot = Join-Path $claudeRoot 'gate'
    $savedConfigDir = [System.Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR')
    try {
        foreach ($row in @($gate.rows)) {
            $folder = Join-Path $gateRoot ([string]$row.dir)
            if ([string]$row.projects -ne 'absent') { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            if ([string]$row.projects -eq 'folder') { New-Item -ItemType Directory -Path (Join-Path $folder 'projects') -Force | Out-Null }
            if ([string]$row.projects -eq 'file') { [System.IO.File]::WriteAllText((Join-Path $folder 'projects'), 'not a folder', $utf8) }
            $value = $folder
            if ($row.pad) { $value = "  $folder  " }
            [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $value)
            $state = (@(Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot) | Where-Object { $_.key -eq (Get-P20Consts).usage.envFlag }).state
            $want = 'not configured'
            if ($row.on) { $want = 'on' }
            Assert-Equal "the row: $($row.name)" $want $state
        }
    }
    finally { [System.Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $savedConfigDir) }

    # -- 10. The week: Tests/fixtures/usage/week.json ---------------------------------------------
    Write-Host ""
    Write-Host "-- The week: Tests/fixtures/usage/week.json -----------" -ForegroundColor Cyan
    $week = [System.IO.File]::ReadAllText((Join-Path $fixtures 'week.json')) | ConvertFrom-Json
    $local = { param([string]$Text) [DateTime]::SpecifyKind([DateTime]::ParseExact($Text, 'yyyy-MM-dd HH:mm', $inv), [DateTimeKind]::Local) }
    $fmt = { param([DateTime]$D) $D.ToString('yyyy-MM-dd HH:mm', $inv) }
    $parseWeek = { param([string]$Text) $p = ConvertFrom-P20WeekStart -Text $Text; if (-not $p.Ok) { throw "week.json names a weekStarts the parser refuses: $Text" }; $p }
    foreach ($v in @($week.weekStartsValues.accepted)) {
        $p = ConvertFrom-P20WeekStart -Text ([string]$v.typed)
        Assert-Equal "burn.weekStarts '$($v.typed)' reads as '$($v.reads)'" ([string]$v.reads) $(if ($p.Ok) { $p.Text } else { "refused: $($p.Reason)" })
    }
    foreach ($v in @($week.weekStartsValues.refused)) {
        $p = ConvertFrom-P20WeekStart -Text ([string]$v)
        Assert-True "burn.weekStarts '$v' is refused, naming the key" ((-not $p.Ok) -and $p.Reason.Contains('burn.weekStarts')) $p.Reason
    }
    foreach ($row in @($week.windows)) {
        $w = Get-P20BurnWindows -Now (& $local $row.now) -WeekStart (& $parseWeek $row.weekStarts)
        Assert-Equal "the windows ($($row.weekStarts)): $($row.name)" "$($row.weekStart) / $($row.nextBoundary)" ("$(& $fmt $w.WeekStart) / $(& $fmt $w.NextBoundary)")
    }
    foreach ($group in @($week.records)) {
        $ws = & $local $group.weekStart
        foreach ($row in @($group.rows)) {
            Assert-Equal "a record dated $($row.date) ($($group.weekStarts)): $($row.why)" ([string][bool]$row.inWeek) ([string](Test-P20RecordInWeek -DayKey $row.date -WeekStart $ws))
        }
    }

    $machinesOf = { param($W) (@($W.machines | ForEach-Object { $t = "$($_.machine)=$($_.messages)"; if (@($_.days).Count) { $t += " [$(@($_.days) -join ', ')]" }; $t }) -join ', ') }
    $writeRecord = {
        param([string]$Dir, [string]$Who, [string]$Date, [string]$Model, [long]$Messages, [long]$Out)
        $body = [ordered]@{ usage = 1; date = $Date; machine = $Who
            byModel = @([ordered]@{ model = $Model; input = 0; output = $Out; thinking = 0; cacheWrite5m = 0; cacheWrite1h = 0; cacheRead = 0; messages = $Messages })
        }
        [System.IO.File]::WriteAllText((Join-Path $Dir "$Date-$Who.json"), ($body | ConvertTo-Json -Depth 6), $utf8)
    }
    $si = 0
    foreach ($sumSpec in @($week.summaries)) {
        $si++
        $sumNow = & $local $sumSpec.now
        $sumDir = Join-Path $claudeRoot "summary$si"
        $sumLines = @($sumSpec.lines | ForEach-Object {
                [pscustomobject]@{ t = $_.t; id = $_.id; model = $_.model; out = $_.out; sid = '33333333-cccc-4ccc-8ccc-000000000003'; cwd = '/Users/alex/Repos/demo' }
            })
        New-ProjectsTree ([pscustomobject]@{ 'demo/33333333-cccc-4ccc-8ccc-000000000003.jsonl' = $sumLines }) $sumDir $sumNow.Date
        $sumUsage = Join-Path $root "summary-usage$si"
        New-Item -ItemType Directory -Path $sumUsage -Force | Out-Null
        foreach ($rec in @($sumSpec.records)) {
            & $writeRecord $sumUsage (([string]$rec.machine).Replace('{this}', $machine)) ([string]$rec.date) ([string]$rec.model) ([long]$rec.messages) ([long]$rec.out)
        }
        $sum = (Read-P20BurnSummary -ProjectsRoot (Join-Path $sumDir 'projects') -UsageDir $sumUsage -Now $sumNow -WeekStart (& $parseWeek $sumSpec.weekStarts) `
                -PriceTable (Get-P20ClaudePriceTable -PackageRoot $pkgRoot) -Machine $machine).Summary
        foreach ($name in @('today', 'week')) {
            $want = $sumSpec.expect.$name
            $got = $sum.$name
            Assert-Equal "$($sumSpec.name), $($name): messages and output" "$($want.messages) / $($want.output)" "$($got.totals.messages) / $($got.totals.output)"
            Assert-Equal "  and which machine said what (this machine's own record never read)" (([string]$want.machines).Replace('{this}', $machine)) (& $machinesOf $got)
        }
        Assert-Equal "  the answer is right until $($sumSpec.expect.nextBoundary)" ([string]$sumSpec.expect.nextBoundary) (& $fmt ([DateTime]::Parse($sum.nextBoundaryAt, $inv)))
        Assert-Equal '  and names its week start' "$($sumSpec.weekStarts) local" ([string]$sum.weekStarts)
        Assert-True '  Haiku is priced at its lower rate card, and says so' ((@($sum.cost.priceNotes | Where-Object { $_.model -eq 'claude-haiku-5-5' -and $_.note -match 'lower rate card' })).Count -eq 1) ($sum.cost.priceNotes | ConvertTo-Json -Depth 4)
        Assert-True '  the cost is marked derived' ($sum.cost.derived -eq $true -and $sum.cost.note -match "not the plan's allocation")
    }

    # -- 11. The burn, typed: Burn and Burn -AsJson, at a fixed -At --------------------------------
    # The clock is fixed, so no run straddles a midnight or a week's start:
    # 14:00 on cases.json's day, a Wednesday. One line of this machine's at 09:00
    # that day; laptop's records for the Monday before and the day itself; this
    # machine's own record for the day, which must never be read.
    Write-Host ""
    Write-Host "-- The current burn, typed: Burn and Burn -AsJson -----" -ForegroundColor Cyan
    $liveDir = Join-Path $claudeRoot 'live'
    $liveLines = @([pscustomobject]@{ t = '+09:00'; id = 'msg-live'; model = 'claude-opus-5-5'; out = 400; sid = '44444444-dddd-4ddd-8ddd-000000000004'; cwd = '/Users/alex/Repos/demo' })
    New-ProjectsTree ([pscustomobject]@{ 'demo/44444444-dddd-4ddd-8ddd-000000000004.jsonl' = $liveLines }) $liveDir $dayStart
    & $writeRecord $usageDir 'laptop' '2026-07-13' 'claude-haiku-5-5' 2 20
    & $writeRecord $usageDir 'laptop' $dayKey 'claude-haiku-5-5' 3 30
    & $writeRecord $usageDir $machine $dayKey 'claude-opus-5-5' 100 1000
    [System.IO.File]::WriteAllText((Join-Path $usageDir 'notes.json'), '{ not a record', $utf8)
    $at = "$dayKey 14:00"
    $localCfg = (Join-Path $pkgDir 'config.local.json') -replace "'", "''"
    $before = Get-TreeSnapshot $claudeRoot
    $snippet = "`$env:CLAUDE_CONFIG_DIR = '$($liveDir -replace "'", "''")'`n"
    $snippet += "'BEGIN:json'`ntkBurn -AsJson -At '$at'`n'END:json=' + `$LASTEXITCODE`n'BEGIN:console'`ntkBurn -At '$at'`n'END:console=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:atbad'`ntkBurn -At 2026-7-15`n'END:atbad=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:atfuture'`ntkBurn -At '$((Get-Date).AddDays(2).ToString('yyyy-MM-dd HH:mm', $inv))'`n'END:atfuture=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:atlog'`ntkBurn -Log -At '$at'`n'END:atlog=' + `$LASTEXITCODE`n"
    # burn.weekStarts through the one writer: a bad value refused, a good one written as it reads back.
    $snippet += "'BEGIN:setbad'`ntkConfig -Set 'burn.weekStarts=Funday 05:00'`n'END:setbad=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:set'`ntkConfig -Set 'burn.weekStarts=monday 9:00'`n'END:set=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:written'`n(Get-Content -Raw '$localCfg' | ConvertFrom-Json).burn.weekStarts`n'END:written=0'`n"
    $snippet += "'BEGIN:monday'`ntkBurn -AsJson -At '$at'`n'END:monday=' + `$LASTEXITCODE`n"
    # A value written by hand that Burn cannot read: refused, naming the key and the file.
    $snippet += "`$c = Get-Content -Raw '$localCfg' | ConvertFrom-Json; `$c.burn.weekStarts = 'Fri 5am'; [System.IO.File]::WriteAllText('$localCfg', (`$c | ConvertTo-Json -Depth 8))`n"
    $snippet += "Import-Module '$($pkgDir -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null`n"
    $snippet += "'BEGIN:handbad'`ntkBurn -At '$at'`n'END:handbad=' + `$LASTEXITCODE`n"
    $snippet += "`$c.burn = `$null; `$c.PSObject.Properties.Remove('burn'); [System.IO.File]::WriteAllText('$localCfg', (`$c | ConvertTo-Json -Depth 8))`n"
    $r = Invoke-Burn $snippet
    $after = Get-TreeSnapshot $claudeRoot

    # Instants stay text: PowerShell 7 would read an ISO string as a date.
    $jsonArgs = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonArgs['DateKind'] = 'String' }
    $parseJson = { param($Text) try { $Text | ConvertFrom-Json @jsonArgs } catch { $null } }
    $s = Get-Section $r.All 'json'
    $j = & $parseJson $s.Text
    Assert-True 'Burn -AsJson -At: exit 0 and nothing but one JSON object' ($s.Exit -eq '0' -and $null -ne $j -and $j.burn -eq 1) $s.Text
    if ($null -ne $j) {
        Assert-Equal "today: this machine's session files plus laptop's record, this machine's own record not read" "$machine=1, laptop=3 [$dayKey]" (& $machinesOf $j.today)
        Assert-Equal '  and the totals are the two, once' '4 / 430' "$($j.today.totals.messages) / $($j.today.totals.output)"
        Assert-Equal 'this week from Friday 05:00 (the default): laptop''s Monday and today' "$machine=1, laptop=5 [2026-07-13, $dayKey]" (& $machinesOf $j.week)
        Assert-Equal '  and the week is the default''s' 'Friday 05:00 local' ([string]$j.weekStarts)
        Assert-Equal 'a file in usage/ that is not a record is skipped and counted' '1' ([string]$j.skipped.records)
        Assert-Equal 'the answer is right until the next midnight after -At' "$((& $local "$dayKey 00:00").AddDays(1).ToString('yyyy-MM-dd HH:mm', $inv))" (& $fmt ([DateTime]::Parse([string]$j.nextBoundaryAt, $inv)))
        Test-NoPrivateText 'the -AsJson answer' $s.Text
    }
    $s = Get-Section $r.All 'console'
    # The burn's own blocks carry no percentage: the plan's share is the burndown's, and typed.
    $burnPart = $s.Text
    $burnAt = $burnPart.IndexOf('Claude Code burn on')
    if ($burnAt -ge 0) { $burnPart = $burnPart.Substring($burnAt) }
    Assert-True 'Burn -At: exit 0, today and this week, the cost derived, never a share of the plan' ($s.Exit -eq '0' -and $burnAt -ge 0 -and $s.Text.Contains("as of $at") -and $s.Text.Contains('Today, ') -and $s.Text.Contains('This week, from ') -and $s.Text.Contains('the week starts Friday 05:00, burn.weekStarts') -and $s.Text.Contains("not the plan's allocation") -and $burnPart -notmatch '\d%') $s.Text
    Assert-True '  and opens with the burndown, no reading yet, saying how to record one' ($burnAt -gt $s.Text.IndexOf('Weekly burndown') -and $s.Text.IndexOf('Weekly burndown') -ge 0 -and $s.Text.Contains('no reading this week') -and $s.Text.Contains('tkBurn -Reading general=<n>,premium=<n>')) $s.Text
    Assert-True '  and says Haiku is priced at its lower rate card' ($s.Text.Contains('claude-haiku-5-5 is priced at its lower rate card')) $s.Text
    $s = Get-Section $r.All 'atbad'
    Assert-True '-At that is not a time: exit 2, one Error block' ($s.Exit -eq '2' -and $s.Text.Contains('is not a time') -and (@([regex]::Matches($s.Text, '(?m)^Error: ')).Count -eq 1)) $s.Text
    $s = Get-Section $r.All 'atfuture'
    Assert-True '-At that has not come: exit 2' ($s.Exit -eq '2' -and $s.Text.Contains('has not happened yet')) $s.Text
    $s = Get-Section $r.All 'atlog'
    Assert-True '-At with -Log: exit 2, naming -Date' ($s.Exit -eq '2' -and $s.Text.Contains("-Log's day is -Date")) $s.Text
    $s = Get-Section $r.All 'setbad'
    Assert-True 'Config -Set burn.weekStarts=Funday 05:00: refused, exit 2, naming the key' ($s.Exit -eq '2' -and $s.Text.Contains('burn.weekStarts is a day and a 24-hour time')) $s.Text
    $s = Get-Section $r.All 'set'
    Assert-True 'Config -Set burn.weekStarts=monday 9:00: written, exit 0' ($s.Exit -eq '0') $s.Text
    Assert-Equal '  as it reads back, in config.local.json' 'Monday 09:00' ((Get-Section $r.All 'written').Text.Trim())
    $s = Get-Section $r.All 'monday'
    $j = & $parseJson $s.Text
    Assert-True 'Burn -AsJson -At under Monday 09:00: exit 0' ($s.Exit -eq '0' -and $null -ne $j) $s.Text
    if ($null -ne $j) {
        Assert-Equal '  the week starts Monday 09:00, the 13th' "Monday 09:00 local / $((& $local '2026-07-13 09:00').ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv))" "$($j.weekStarts) / $($j.week.from)"
        Assert-Equal "  laptop's Monday record starts before 09:00, so it is the week before's" "$machine=1, laptop=3 [$dayKey]" (& $machinesOf $j.week)
        Assert-Equal '  today is the same either way' "$machine=1, laptop=3 [$dayKey]" (& $machinesOf $j.today)
    }
    $s = Get-Section $r.All 'handbad'
    Assert-True 'a burn.weekStarts Burn cannot read: exit 2, naming the key and the file' ($s.Exit -eq '2' -and $s.Text.Contains("burn.weekStarts is a day and a 24-hour time") -and $s.Text.Contains('config.local.json') -and (@([regex]::Matches($s.Text, '(?m)^Error: ')).Count -eq 1)) $s.Text
    Assert-True 'Burn reads the projects folder and changes nothing in it' ($before -eq $after)

    # -- 12. The burndown's rule: Tests/fixtures/usage/burndown.json ------------------------------
    Write-Host ""
    Write-Host "-- The burndown's rule: Tests/fixtures/usage/burndown.json --" -ForegroundColor Cyan
    . (Join-Path $pkgRoot 'Scripts/Read-BurnReadings.ps1')
    $bd = [System.IO.File]::ReadAllText((Join-Path $fixtures 'burndown.json')) | ConvertFrom-Json @jsonArgs
    $bdBuckets = @(Get-P20BurnBuckets -Value @($bd.buckets))
    $nullText = { param($v) if ($null -eq $v) { 'null' } else { [string]$v } }
    foreach ($case in @($bd.cases)) {
        $entries = @()
        foreach ($e in @($case.entries)) {
            $b = [ordered]@{}
            foreach ($p in $e.buckets.PSObject.Properties) { $b[$p.Name] = [int]$p.Value }
            $entries += @{ At = (ConvertTo-P20UtcInstant $e.at); Machine = [string]$e.machine; Buckets = $b }
        }
        $got = Get-P20Burndown -WeekStart (ConvertTo-P20UtcInstant $bd.weekStart) -WeekEnd (ConvertTo-P20UtcInstant $bd.weekEnd) `
            -Now (ConvertTo-P20UtcInstant $case.now) -CacheHours ([int]$case.cacheHours) -Buckets $bdBuckets -Entries $entries -Product 'claude'
        $wantText = @(); $gotText = @()
        foreach ($b in $bdBuckets) {
            $w = $case.expect.buckets.($b.key)
            if ($null -eq $w) { $wantText += "$($b.key)=none" } else { $wantText += "$($b.key)=$($w.percent)/$($w.pace)/$($w.gap)@$($w.readingAt) by $($w.machine)" }
            $g = @($got.buckets | Where-Object { $_.key -eq $b.key })[0]
            if ($null -eq $g.percent) { $gotText += "$($b.key)=none" } else { $gotText += "$($b.key)=$($g.percent)/$($g.pace)/$($g.gap)@$($g.readingAt) by $($g.machine)" }
        }
        Assert-Equal "burndown: $($case.name)" ($wantText -join '; ') ($gotText -join '; ')
        Assert-Equal "  cached, renews, due" "$(& $nullText $case.expect.cachedAt) / $(& $nullText $case.expect.renewsAt) / $($case.expect.due)" "$(& $nullText $got.cachedAt) / $(& $nullText $got.renewsAt) / $($got.due)"
    }
    foreach ($v in @(@{ t = ''; ok = '4' }, @{ t = '1'; ok = '1' }, @{ t = '168'; ok = '168' }, @{ t = ' 6 '; ok = '6' }, @{ t = '0'; ok = '' }, @{ t = '169'; ok = '' }, @{ t = '2.5'; ok = '' }, @{ t = '-3'; ok = '' }, @{ t = 'four'; ok = '' })) {
        $h = Get-P20BurnCacheHours -Value $v.t
        $read = ''
        if ($h.Ok) { $read = [string]$h.Hours }
        Assert-Equal "burn.cacheHours '$($v.t)' reads as '$(if ($v.ok) { $v.ok } else { 'refused' })'" $v.ok $read
    }
    foreach ($v in @(
            @{ t = @('general=43', 'premium=54'); want = 'general=43,premium=54' },
            @{ t = @('General = 7'); want = 'general=7' },
            @{ t = @('premium=54%'); want = 'premium=54' },
            @{ t = @('premium=0,general=100'); want = 'premium=0,general=100' },
            @{ t = @('general=101'); want = 'refused' },
            @{ t = @('general=4.5'); want = 'refused' },
            @{ t = @('gold=5'); want = 'refused' },
            @{ t = @('general=4,general=5'); want = 'refused' },
            @{ t = @('general'); want = 'refused' },
            @{ t = @(''); want = 'refused' })) {
        $r2 = ConvertFrom-P20BurnReading -Text $v.t -Buckets $bdBuckets
        $read = 'refused'
        if ($r2.Ok) { $read = (@($r2.Values.Keys | ForEach-Object { "$_=$($r2.Values[$_])" }) -join ',') }
        Assert-Equal "-Reading '$($v.t -join ',')' reads as $($v.want)" $v.want $read
    }

    # -- 13. Burn -Reading, typed -----------------------------------------------------------------
    # The week of cases.json's day (a Wednesday) starts Friday 05:00 the 10th
    # under the default. Two readings from this machine, one from laptop's file,
    # last week's file not counted, a refusal writing nothing.
    Write-Host ""
    Write-Host "-- Burn -Reading, typed ------------------------------" -ForegroundColor Cyan
    $readingsDir = Join-Path $usageDir 'readings'
    $weekKey = '2026-07-10'
    $mine = Join-Path $readingsDir "$weekKey-$machine.json"
    New-Item -ItemType Directory -Path $readingsDir -Force | Out-Null
    $stampOf = { param([string]$Text) (& $local $Text).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv) }
    $laptopBody = [ordered]@{ readings = 1; product = 'claude'; source = 'typed'; machine = 'laptop'; weekStart = (& $stampOf '2026-07-10 05:00'); weekStarts = 'Friday 05:00 local'
        entries = @([ordered]@{ at = (& $stampOf '2026-07-15 10:00'); buckets = [ordered]@{ general = 50 } }) }
    [System.IO.File]::WriteAllText((Join-Path $readingsDir "$weekKey-laptop.json"), ($laptopBody | ConvertTo-Json -Depth 6), $utf8)
    $lastBody = [ordered]@{ readings = 1; machine = $machine; entries = @([ordered]@{ at = (& $stampOf '2026-07-08 12:00'); buckets = [ordered]@{ general = 99; premium = 99 } }) }
    [System.IO.File]::WriteAllText((Join-Path $readingsDir "2026-07-03-$machine.json"), ($lastBody | ConvertTo-Json -Depth 6), $utf8)
    $snippet = "'BEGIN:first'`ntkBurn -Reading general=43,premium=54 -At '2026-07-14 09:10'`n'END:first=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:second'`ntkBurn -Reading premium=60 -At '2026-07-15 08:00'`n'END:second=' + `$LASTEXITCODE`n"
    foreach ($bad in @(@('big', 'general=101'), @('gold', 'gold=5'), @('twice', "'general=4,general=5'"))) {
        $snippet += "'BEGIN:$($bad[0])'`ntkBurn -Reading $($bad[1]) -At '2026-07-15 09:00'`n'END:$($bad[0])=' + `$LASTEXITCODE`n"
    }
    $snippet += "'BEGIN:withlog'`ntkBurn -Reading general=40 -Log`n'END:withlog=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:withjson'`ntkBurn -Reading general=40 -AsJson`n'END:withjson=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:rjson'`ntkBurn -AsJson -At '2026-07-15 14:00'`n'END:rjson=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:rconsole'`ntkBurn -At '2026-07-15 14:00'`n'END:rconsole=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:empty'`ntkBurn -AsJson -At '2026-07-10 06:00'`n'END:empty=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:cachebad'`ntkConfig -Set burn.cacheHours=0`n'END:cachebad=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:cacheset'`ntkConfig -Set burn.cacheHours=6`n'END:cacheset=' + `$LASTEXITCODE`n"
    $snippet += "'BEGIN:rjson6'`ntkBurn -AsJson -At '2026-07-15 14:00'`n'END:rjson6=' + `$LASTEXITCODE`n"
    $snippet += "`$c = Get-Content -Raw '$localCfg' | ConvertFrom-Json; `$c.burn.cacheHours = 'lots'; [System.IO.File]::WriteAllText('$localCfg', (`$c | ConvertTo-Json -Depth 8))`n"
    $snippet += "Import-Module '$($pkgDir -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null`n"
    $snippet += "'BEGIN:cachehand'`ntkBurn -At '2026-07-15 14:00'`n'END:cachehand=' + `$LASTEXITCODE`n"
    $snippet += "`$c.PSObject.Properties.Remove('burn'); [System.IO.File]::WriteAllText('$localCfg', (`$c | ConvertTo-Json -Depth 8))`n"
    $r = Invoke-Burn $snippet

    $s = Get-Section $r.All 'first'
    Assert-True 'Burn -Reading general=43,premium=54 (the unquoted comma form): exit 0, recorded, the week''s record started' ($s.Exit -eq '0' -and $s.Text.Contains('Recorded general=43,premium=54') -and $s.Text.Contains('Started the week') -and (Test-Path -LiteralPath $mine)) $s.Text
    Assert-True '  and prints the burndown' ($s.Text.Contains('Weekly burndown') -and $s.Text.Contains('*cached as of')) $s.Text
    $s = Get-Section $r.All 'second'
    Assert-True 'a second reading the same week is appended to the same file' ($s.Exit -eq '0' -and $s.Text.Contains('Added a reading to the week') -and $s.Text.Contains('2 reading(s)')) $s.Text
    $bytes = [System.IO.File]::ReadAllBytes($mine)
    $text = $utf8.GetString($bytes)
    Assert-True 'the record is UTF-8 with no BOM and LF only' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) -and -not $text.Contains("`r") -and $text.EndsWith("`n")) $text
    $rec = $text | ConvertFrom-Json @jsonArgs
    Assert-Equal '  its shape: version, product, source, machine, week, two entries in time order' "1 / claude / typed / $machine / $(& $stampOf '2026-07-10 05:00') / Friday 05:00 local / $(& $stampOf '2026-07-14 09:10'),$(& $stampOf '2026-07-15 08:00')" `
        "$($rec.readings) / $($rec.product) / $($rec.source) / $($rec.machine) / $($rec.weekStart) / $($rec.weekStarts) / $(@($rec.entries | ForEach-Object { $_.at }) -join ',')"
    Assert-Equal '  and each entry names only the buckets typed' 'general=43,premium=54 | premium=60' ((@($rec.entries | ForEach-Object { @($_.buckets.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ',' })) -join ' | ')
    Test-NoPrivateText 'the readings record' $text
    foreach ($bad in @(@('big', 'not a reading'), @('gold', "not one of the plan's buckets"), @('twice', 'typed twice'), @('withlog', 'One at a time'), @('withjson', "not -Reading's"))) {
        $s = Get-Section $r.All $bad[0]
        Assert-True "-Reading refused ($($bad[0])): exit 2, one Error block" ($s.Exit -eq '2' -and $s.Text.Contains($bad[1]) -and (@([regex]::Matches($s.Text, '(?m)^Error: ')).Count -eq 1)) $s.Text
    }
    Assert-Equal '  and a refusal writes nothing' '2' ([string]@(($utf8.GetString([System.IO.File]::ReadAllBytes($mine)) | ConvertFrom-Json @jsonArgs).entries).Count)
    $s = Get-Section $r.All 'rjson'
    $j = & $parseJson $s.Text
    Assert-True 'Burn -AsJson carries the burndown' ($s.Exit -eq '0' -and $null -ne $j -and $null -ne $j.burndown) $s.Text
    if ($null -ne $j -and $null -ne $j.burndown) {
        $bdj = $j.burndown
        $row = { param($k) $x = @($bdj.buckets | Where-Object { $_.key -eq $k })[0]; "$($x.label): $($x.percent)/$($x.pace)/$($x.gap) by $($x.machine)" }
        Assert-Equal "  General is laptop's later reading (Wed 10:00, 125 of 168 hours: pace 74)" 'General: 50/74/-24 by laptop' (& $row 'general')
        Assert-Equal "  Premium is this machine's latest (Wed 08:00, 123 hours: pace 73); last week's 99 not counted" ("Premium (Fable): 60/73/-13 by $machine") (& $row 'premium')
        Assert-Equal '  the week, the reset, the cache line: due at 14:00, four hours after 10:00' "$(& $stampOf '2026-07-10 05:00') / $(& $stampOf '2026-07-17 05:00') / 4 / $(& $stampOf '2026-07-15 10:00') / $(& $stampOf '2026-07-15 14:00') / True / claude" `
            "$($bdj.weekFrom) / $($bdj.resetsAt) / $($bdj.cacheHours) / $($bdj.cachedAt) / $($bdj.renewsAt) / $($bdj.due) / $($bdj.product)"
        Assert-Equal '  and the week''s readings, in time order, for the line' '3' ([string]@($bdj.readings).Count)
    }
    $s = Get-Section $r.All 'rconsole'
    Assert-True 'Burn opens with the burndown: bars, the gap, the reset, the cache line, no colour word' ($s.Exit -eq '0' -and $s.Text.IndexOf('Weekly burndown') -ge 0 -and $s.Text.IndexOf('Weekly burndown') -lt $s.Text.IndexOf('Claude Code burn on') -and $s.Text.Contains('behind pace by 24') -and $s.Text.Contains('behind pace by 13') -and $s.Text.Contains('resets Fri 17 Jul 05:00 (1d 15h left)') -and $s.Text.Contains('*cached as of Wed 15 Jul 10:00 - renewal due since Wed 15 Jul 14:00')) $s.Text
    $s = Get-Section $r.All 'empty'
    $j = & $parseJson $s.Text
    Assert-True 'a new week starts empty: last week''s readings are not this week''s, and none is yet' ($s.Exit -eq '0' -and $null -ne $j -and @($j.burndown.buckets | Where-Object { $null -ne $_.percent }).Count -eq 0 -and $null -eq $j.burndown.cachedAt -and $j.burndown.due -eq $false) $s.Text
    $s = Get-Section $r.All 'cachebad'
    Assert-True 'Config -Set burn.cacheHours=0: refused, exit 2, naming the key' ($s.Exit -eq '2' -and $s.Text.Contains('burn.cacheHours is a whole number of hours from 1 to 168')) $s.Text
    $s = Get-Section $r.All 'cacheset'
    Assert-True 'Config -Set burn.cacheHours=6: written, exit 0' ($s.Exit -eq '0') $s.Text
    $s = Get-Section $r.All 'rjson6'
    $j = & $parseJson $s.Text
    Assert-True '  and Burn reads it: renews six hours after the reading, not yet due' ($s.Exit -eq '0' -and $null -ne $j -and $j.burndown.cacheHours -eq 6 -and $j.burndown.renewsAt -eq (& $stampOf '2026-07-15 16:00') -and $j.burndown.due -eq $false) $s.Text
    $s = Get-Section $r.All 'cachehand'
    Assert-True 'a burn.cacheHours Burn cannot read: exit 2, naming the key and the file' ($s.Exit -eq '2' -and $s.Text.Contains('burn.cacheHours is a whole number') -and $s.Text.Contains('config.local.json') -and (@([regex]::Matches($s.Text, '(?m)^Error: ')).Count -eq 1)) $s.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

$total = $script:passed + $script:failed
Write-Host ""
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) { exit 1 }
exit 0
