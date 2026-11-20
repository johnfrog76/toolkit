<#
.SYNOPSIS
    Tests for the Backlog verb -- the Space's waiting cards as one ranked table.
.DESCRIPTION
    The rule first, then the verb:

      - the one reader, Get-P20BacklogRows (Scripts/Read-Backlog.ps1), over the shared
        table Tests/fixtures/parsers/backlog-order.json, which Tests/test_backlog.py
        asserts from the agent's half too: rows milestone by milestone, ranked by the
        milestone's file, then the cards with no milestone; rank, age, the heading's type
        and title, the filters
      - as a VERB -- the real module imported in a fresh shell, typed the way a person
        types it, because a suite that runs a script directly does not test the verb:
        the order on disk, a card in play counting toward the rank and never a row, the
        rank agreeing with Plan -Rank after a move, -Milestone / -Tag / -Type, a non-ASCII
        title read as UTF-8, an empty backlog/ and a filter that matches nothing said in
        words, -Help, and nothing written by any of it
      - on an Azure DevOps Space it refuses, exit 2, naming MyWork

    Run:  pwsh -File Tests/Test-Backlog.ps1
    Or:   {cliPrefix}TestToolkit -Backlog
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
. (Join-Path $scriptDir 'Get-TestHost.ps1')

# -- Test harness ---------------------------------------------------------------

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
    if ($Expected -ceq $Actual) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName -- expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

. (Join-Path $pkgRoot 'Scripts/Read-Backlog.ps1')

# -- The one reader, over the shared table ---------------------------------------
Write-Host "-- The Backlog's rows: the shared table ----------------" -ForegroundColor Cyan
$table = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/parsers/backlog-order.json'), (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
$types = @{}
for ($i = 0; $i -lt @($table.typeNames).Count; $i++) { $types[[string]$table.typeNames[$i]] = @{ FilePrefix = [string]$table.prefixes[$i] } }
$pattern = Get-P20CardIdPattern -WorkItemTypes $types
$typeNames = @($table.typeNames | ForEach-Object { [string]$_ })
$show = { param($r) "$($r.rank)|$($r.id)|$($r.title)|$($r.type)|$($r.milestone)|$(@($r.tags) -join ',')|$($r.age)|$([bool]$r.in_play)" }
foreach ($case in $table.cases) {
    $eol = "`n"
    if ($case.crlf) { $eol = "`r`n" }
    $cards = @()
    foreach ($k in @($case.cards)) {
        $card = ConvertTo-P20BacklogCard -Name ([string]$k.file) -Folder ([string]$k.folder) -Content ((@($k.lines) | ForEach-Object { [string]$_ }) -join $eol) -TypeNames $typeNames -Pattern $pattern
        if ($card) { $cards += $card }
    }
    $files = @{}
    foreach ($m in @($case.milestones)) { $files[[string]$m.file] = (@($m.lines) | ForEach-Object { [string]$_ }) -join $eol }
    $rows = Get-P20BacklogRows -Cards $cards -MilestoneFiles $files -Today ([string]$case.today) `
        -Milestone ([string]$case.filter.milestone) -Tag ([string]$case.filter.tag) -Type ([string]$case.filter.type)
    $got = (@($rows) | ForEach-Object { "$($_.Rank)|$($_.Id)|$($_.Title)|$($_.Type)|$($_.Milestone)|$(@($_.Tags) -join ',')|$($_.Age)|$([bool]$_.InPlay)" }) -join ' ; '
    $want = (@($case.rows) | ForEach-Object { & $show $_ }) -join ' ; '
    Assert-True "rows: $($case.name)" ($got -ceq $want) "got [$got] want [$want]"
}
$names = (@($table.cases | ForEach-Object { [string]$_.name })) -join ' | '
foreach ($shape in @('with a file first', 'a card in play is a row in its ranked place', 'a card in play the order does not list', 'stale id', "not at the title's slug", 'no Created',
        'no milestone', 'impossible date', 'emoji', 'BMP symbol', 'accented letter', 'Sprint line', 'filter by milestone', 'filter by tag', 'filter by type',
        'filters AND', 'CRLF', 'cards are all in play is no group', 'an empty Space')) {
    Assert-True "the table has a case for: $shape" ($names.Contains($shape))
}
Write-Host ""

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-backlog-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

try {
    # -- Through the VERB ---------------------------------------------------------
    Write-Host "-- Backlog, typed as a verb ----------------------------" -ForegroundColor Cyan

    $hub = Join-Path $base 'hub'
    $log = Join-Path $base 'log'
    New-Item -ItemType Directory -Path $hub, $log -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'),
        '{ "hub": 1, "spaces": [ { "slug": "home", "name": "Home", "status": "local", "org": "", "promptsFolder": "home" } ] }',
        (New-Object System.Text.UTF8Encoding($false)))
    $prefix = ([System.IO.File]::ReadAllText((Join-Path $pkgRoot 'config.default.json')) | ConvertFrom-Json).commandPrefix
    $preamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$hub'; `$env:P20_ACTIVE_SPACE = 'home'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "

    function Invoke-Verbs {
        param([string]$Commands)
        return (@(Invoke-P20TestHost -NonInteractive -Command ($preamble + $Commands)) | ForEach-Object { "$_" }) -join "`n"
    }
    function Get-HubBytes {
        $map = @{}
        foreach ($f in @(Get-ChildItem $hub -Recurse -File)) { $map[$f.FullName] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName)) }
        return $map
    }

    $out = Invoke-Verbs ("${prefix}Backlog; 'EMPTY-EXIT=' + `$LASTEXITCODE")
    Assert-True 'an empty backlog/ says so, exit 0' ($out -match 'EMPTY-EXIT=0' -and $out -match 'backlog/ is empty') $out

    # Three waiting cards and one in play; two of them in M2, whose order the
    # in-play card leads.
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Bench reading' -Type Task -Id K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Write the guide' -Type Bug -Id Q4R9 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Caf$([char]0x00E9) menu' -Type Task -Id P7NX | Out-Null; " +
        "${prefix}NewPrompt -Now -Title 'In play' -Type Task -Id H3RE | Out-Null; " +
        "${prefix}Plan H3RE -Milestone 'M2' | Out-Null; ${prefix}Plan Q4R9 -Milestone 'M2' | Out-Null; ${prefix}Plan K7M2 -Milestone 'M2' | Out-Null; " +
        "${prefix}Tag K7M2 docs | Out-Null; 'SETUP-DONE'")
    Assert-True 'the scratch Space is set up through the verbs' ($out -match 'SETUP-DONE') $out

    $before = Get-HubBytes
    $out = Invoke-Verbs ("${prefix}Backlog; 'ALL-EXIT=' + `$LASTEXITCODE")
    Assert-True 'Backlog exits 0' ($out -match 'ALL-EXIT=0') $out
    Assert-True 'it counts the waiting cards and the one in play apart' ($out -match 'Backlog -- 3 cards waiting, 1 in play') $out
    $lines = @($out -split "`n" | Where-Object { $_ -match '^\s+(\d+\s+)?(in play\s+)?(H3RE|K7M2|Q4R9|P7NX)\s' })
    $order = (@($lines | ForEach-Object { [regex]::Match($_, '(H3RE|K7M2|Q4R9|P7NX)').Value })) -join ','
    Assert-Equal 'the rows: M2 in its order, its card in play in its place, then the card with no milestone' 'H3RE,Q4R9,K7M2,P7NX' $order
    Assert-True 'the ranks read 1, 2, 3, the card in play marked' ($lines[0] -match '^\s+1\s+in play\s+H3RE' -and $lines[1] -match '^\s+2\s+Q4R9' -and $lines[2] -match '^\s+3\s+K7M2') ($lines -join ' / ')
    Assert-True 'a card with no milestone has no rank' ($lines[3] -match '^\s+P7NX\s') ($lines -join ' / ')
    Assert-True 'type, milestone, tags and age are columns' ($lines[2] -match 'Task\s+M2\s+docs\s+0d\s+Bench reading') $lines[2]
    Assert-True 'a non-ASCII title reads as UTF-8' ($out.Contains("Caf$([char]0x00E9) menu")) $out
    $after = Get-HubBytes
    $same = ($before.Count -eq $after.Count) -and (@($before.Keys | Where-Object { $after[$_] -cne $before[$_] }).Count -eq 0)
    Assert-True 'reading writes nothing' $same

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Rank top | Out-Null; ${prefix}Backlog -Milestone m2")
    $lines = @($out -split "`n" | Where-Object { $_ -match '^\s+\d+\s+(in play\s+)?(H3RE|K7M2|Q4R9)\s' })
    Assert-True "after 'Plan K7M2 -Rank top', K7M2 is 1, H3RE 2 and Q4R9 3" ($lines.Count -eq 3 -and $lines[0] -match '^\s+1\s+K7M2' -and $lines[1] -match '^\s+2\s+in play\s+H3RE' -and $lines[2] -match '^\s+3\s+Q4R9') ($lines -join ' / ')
    Assert-True '-Milestone, ignoring case, keeps the milestone and says the filter' ($out -match "Backlog -- 2 cards waiting, 1 in play -- milestone 'm2'" -and $out -notmatch 'P7NX') $out

    $out = Invoke-Verbs ("${prefix}Backlog -Tag DOCS; ${prefix}Backlog -Type bug -Milestone M2")
    Assert-True '-Tag matches one of the tags, ignoring case' ($out -match "Backlog -- 1 card waiting -- tag 'DOCS'" -and $out -match 'K7M2') $out
    Assert-True '-Type and -Milestone go together' ($out -match "1 card waiting -- milestone 'M2', type 'bug'") $out
    $out = Invoke-Verbs ("${prefix}Backlog -Type 'user story'; 'NONE-EXIT=' + `$LASTEXITCODE")
    Assert-True 'a filter nothing matches says so, exit 0' ($out -match "No card in backlog/ matches -- type 'user story'" -and $out -match 'NONE-EXIT=0') $out

    $out = Invoke-Verbs ("${prefix}Backlog -Help; 'HELP-EXIT=' + `$LASTEXITCODE")
    Assert-True '-Help shows the switches and names Plan -Rank' ($out -match "${prefix}Backlog -Milestone" -and $out -match "${prefix}Plan <id> -Rank" -and $out -match 'HELP-EXIT=0') $out

    # -- On an Azure DevOps Space ---------------------------------------------------
    Write-Host "-- On an Azure DevOps Space it refuses ----------------" -ForegroundColor Cyan
    $aHub = Join-Path $base 'ado-hub'
    New-Item -ItemType Directory -Path $aHub -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $aHub 'hub.json'),
        '{ "hub": 1, "spaces": [ { "slug": "acme", "name": "Acme", "status": "local", "org": "https://dev.azure.com/acme", "promptsFolder": "acme" } ] }',
        (New-Object System.Text.UTF8Encoding($false)))
    $aPre = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$aHub'; `$env:P20_ACTIVE_SPACE = 'acme'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
    $out = (@(Invoke-P20TestHost -NonInteractive -Command ($aPre + "${prefix}Backlog; 'ADO-EXIT=' + `$LASTEXITCODE")) | ForEach-Object { "$_" }) -join "`n"
    Assert-True "'Backlog' refuses on an Azure DevOps Space, exit 2, naming MyWork" ($out -match 'ADO-EXIT=2' -and $out -match "backlog is in Azure DevOps" -and $out -match [regex]::Escape("${prefix}MyWork")) $out
    Assert-True 'and says it once' (([regex]::Matches($out, 'Error:')).Count -eq 1) $out
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

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
exit 0
