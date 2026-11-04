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
   10. The week      Tests/fixtures/usage/week.json: the windows at a given
                     now, another machine's record counting toward the week it
                     starts in (a Friday-dated record is the week before's),
                     and both halves at one now.
   11. The burn      Burn and Burn -AsJson typed: this machine's session files
                     plus another machine's record, this machine's own record
                     not read twice, a file that is not a record skipped.

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
    Assert-True '-Help prints the usage from config' ($reg.All.Contains('tkBurn [-AsJson] [-Log] [-Date <yyyy-mm-dd>] [-Help]')) $reg.All
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
    foreach ($row in @($week.windows)) {
        $w = Get-P20BurnWindows -Now (& $local $row.now)
        Assert-Equal "the windows: $($row.name)" "$($row.weekStart) / $($row.nextBoundary)" ("$(& $fmt $w.WeekStart) / $(& $fmt $w.NextBoundary)")
    }
    $ws = & $local $week.records.weekStart
    foreach ($row in @($week.records.rows)) {
        Assert-Equal "a record dated $($row.date): $($row.why)" ([string][bool]$row.inWeek) ([string](Test-P20RecordInWeek -DayKey $row.date -WeekStart $ws))
    }

    $sumSpec = $week.summary
    $sumNow = & $local $sumSpec.now
    $sumDir = Join-Path $claudeRoot 'summary'
    $sumLines = @($sumSpec.lines | ForEach-Object {
            [pscustomobject]@{ t = $_.t; id = $_.id; model = $_.model; out = $_.out; sid = '33333333-cccc-4ccc-8ccc-000000000003'; cwd = '/Users/alex/Repos/demo' }
        })
    New-ProjectsTree ([pscustomobject]@{ 'demo/33333333-cccc-4ccc-8ccc-000000000003.jsonl' = $sumLines }) $sumDir $sumNow.Date
    $sumUsage = Join-Path $root 'summary-usage'
    New-Item -ItemType Directory -Path $sumUsage -Force | Out-Null
    foreach ($rec in @($sumSpec.records)) {
        $who = ([string]$rec.machine).Replace('{this}', $machine)
        $body = [ordered]@{ usage = 1; date = [string]$rec.date; machine = $who
            byModel = @([ordered]@{ model = [string]$rec.model; input = 0; output = [long]$rec.out; thinking = 0; cacheWrite5m = 0; cacheWrite1h = 0; cacheRead = 0; messages = [long]$rec.messages })
        }
        [System.IO.File]::WriteAllText((Join-Path $sumUsage "$($rec.date)-$who.json"), ($body | ConvertTo-Json -Depth 6), $utf8)
    }
    $sum = (Read-P20BurnSummary -ProjectsRoot (Join-Path $sumDir 'projects') -UsageDir $sumUsage -Now $sumNow `
            -PriceTable (Get-P20ClaudePriceTable -PackageRoot $pkgRoot) -Machine $machine).Summary
    $machinesOf = { param($W) (@($W.machines | ForEach-Object { $t = "$($_.machine)=$($_.messages)"; if (@($_.days).Count) { $t += " [$(@($_.days) -join ', ')]" }; $t }) -join ', ') }
    foreach ($name in @('today', 'week')) {
        $want = $sumSpec.expect.$name
        $got = $sum.$name
        Assert-Equal "both halves at $($sumSpec.now), $($name): messages and output" "$($want.messages) / $($want.output)" "$($got.totals.messages) / $($got.totals.output)"
        Assert-Equal "  and which machine said what (this machine's own record never read)" (([string]$want.machines).Replace('{this}', $machine)) (& $machinesOf $got)
    }
    Assert-Equal 'the answer is right until the next midnight' '2026-11-07 00:00' (& $fmt ([DateTime]::Parse($sum.nextBoundaryAt, $inv)))
    Assert-True 'Haiku is priced at its lower rate card, and says so' ((@($sum.cost.priceNotes | Where-Object { $_.model -eq 'claude-haiku-5-5' -and $_.note -match 'lower rate card' })).Count -eq 1) ($sum.cost.priceNotes | ConvertTo-Json -Depth 4)
    Assert-True 'the cost is marked derived' ($sum.cost.derived -eq $true -and $sum.cost.note -match "not the plan's allocation")

    # -- 11. The burn, typed: Burn and Burn -AsJson --------------------------------------------
    Write-Host ""
    Write-Host "-- The current burn, typed: Burn and Burn -AsJson -----" -ForegroundColor Cyan
    $liveDir = Join-Path $claudeRoot 'live'
    $liveAt = (Get-Date).AddMinutes(-1)
    $liveLines = @([pscustomobject]@{ t = '+00:00'; id = 'msg-live'; model = 'claude-opus-5-5'; out = 400; sid = '44444444-dddd-4ddd-8ddd-000000000004'; cwd = '/Users/alex/Repos/demo' })
    New-ProjectsTree ([pscustomobject]@{ 'demo/44444444-dddd-4ddd-8ddd-000000000004.jsonl' = $liveLines }) $liveDir $liveAt
    $todayKey = (Get-Date).ToString('yyyy-MM-dd', $inv)
    foreach ($rec in @(@{ Who = 'laptop'; Messages = 3; Out = 30 }, @{ Who = $machine; Messages = 100; Out = 1000 })) {
        $body = [ordered]@{ usage = 1; date = $todayKey; machine = $rec.Who
            byModel = @([ordered]@{ model = 'claude-haiku-5-5'; input = 0; output = [long]$rec.Out; thinking = 0; cacheWrite5m = 0; cacheWrite1h = 0; cacheRead = 0; messages = [long]$rec.Messages })
        }
        [System.IO.File]::WriteAllText((Join-Path $usageDir "$todayKey-$($rec.Who).json"), ($body | ConvertTo-Json -Depth 6), $utf8)
    }
    [System.IO.File]::WriteAllText((Join-Path $usageDir 'notes.json'), '{ not a record', $utf8)
    $before = Get-TreeSnapshot $claudeRoot
    $snippet = "`$env:CLAUDE_CONFIG_DIR = '$($liveDir -replace "'", "''")'`n"
    $snippet += "'BEGIN:json'`ntkBurn -AsJson`n'END:json=' + `$LASTEXITCODE`n'BEGIN:console'`ntkBurn`n'END:console=' + `$LASTEXITCODE`n"
    $r = Invoke-Burn $snippet
    $after = Get-TreeSnapshot $claudeRoot
    $s = Get-Section $r.All 'json'
    $j = $null
    try { $j = $s.Text | ConvertFrom-Json } catch { $j = $null }
    Assert-True 'Burn -AsJson: exit 0 and nothing but one JSON object' ($s.Exit -eq '0' -and $null -ne $j -and $j.burn -eq 1) $s.Text
    if ($null -ne $j) {
        $weekStart = (Get-P20BurnWindows -Now (Get-Date)).WeekStart
        $laptopInWeek = Test-P20RecordInWeek -DayKey $todayKey -WeekStart $weekStart
        Assert-Equal "today: this machine's session files plus laptop's record, this machine's own record not read" "$machine=1, laptop=3 [$todayKey]" (& $machinesOf $j.today)
        Assert-Equal '  and the totals are the two, once' '4 / 430' "$($j.today.totals.messages) / $($j.today.totals.output)"
        $wantWeek = "$machine=1"
        if ($laptopInWeek) { $wantWeek += ", laptop=3 [$todayKey]" }
        Assert-Equal "this week: by the rule (today's record is in this week: $laptopInWeek)" $wantWeek (& $machinesOf $j.week)
        Assert-Equal 'a file in usage/ that is not a record is skipped and counted' '1' ([string]$j.skipped.records)
        Assert-True 'the answer says when it stops being right' ([DateTime]::Parse([string]$j.nextBoundaryAt, $inv) -gt (Get-Date)) ([string]$j.nextBoundaryAt)
        Test-NoPrivateText 'the -AsJson answer' $s.Text
    }
    $s = Get-Section $r.All 'console'
    Assert-True 'Burn: exit 0, today and this week, the cost derived, never a share of the plan' ($s.Exit -eq '0' -and $s.Text.Contains('Today, ') -and $s.Text.Contains('This week, from ') -and $s.Text.Contains('derived') -and $s.Text.Contains("not the plan's allocation") -and $s.Text -notmatch '\d%') $s.Text
    Assert-True '  and says Haiku is priced at its lower rate card' ($s.Text.Contains('claude-haiku-5-5 is priced at its lower rate card')) $s.Text
    Assert-True 'Burn reads the projects folder and changes nothing in it' ($before -eq $after)
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
