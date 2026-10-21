<#
.SYNOPSIS
    Tests for the Plan verb -- the write side of the Sprint token.
.DESCRIPTION
    The line writer itself (where the line goes, that an unchanged card is not written, that
    the card keeps its own bytes) is already held by Test-Billable.ps1 against the one shared
    writer, Set-P20CardLine -- this suite does not repeat that. What is specific to Plan is
    tested AS A VERB -- the real module imported in a fresh shell, typed the way a person
    types it -- because a suite that runs a script directly does not test the verb:

      - -Milestone writes **Sprint:** whole, never truncated; -Remove deletes the line
      - -Milestone and -Remove refuse together; neither given refuses too
      - found in current/ AND backlog/, and a backlog card is never pulled into play by it
        (planning a card before it is pulled into play is the whole point)
      - an archived card is not found -- Plan is not Billable's "still worth adjusting after
        the fact", it is planning forward
      - every refusal exits 2 and writes nothing; a repeat of the same milestone writes nothing

    Run:  pwsh -File Tests/Test-Plan.ps1
    Or:   {cliPrefix}TestToolkit -Plan
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

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
    if ($Expected -eq $Actual) {
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

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
$consts = Get-P20Consts
$sprint = '**Sprint:**'
$created = $consts.stamps.created

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-plan-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

try {
    # -- Through the VERB ---------------------------------------------------------
    Write-Host "-- Plan, typed as a verb -------------------------------" -ForegroundColor Cyan

    $hub = Join-Path $base 'hub'
    $log = Join-Path $base 'log'
    New-Item -ItemType Directory -Path $hub, $log -Force | Out-Null
    $prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $preamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$hub'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "

    function Invoke-Verbs {
        param([string]$Commands)
        return (& pwsh -NoProfile -NonInteractive -Command ($preamble + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    function Find-Card {
        param([string]$Filter, [string]$FolderName)
        return @(Get-ChildItem $hub -Recurse -Filter $Filter | Where-Object { $_.DirectoryName -match "[\\/]$FolderName`$" })
    }

    # A card in current/ (-Now), a card in backlog/ (no -Now), and a second current/
    # card to prove ambiguity and "untouched by a refusal".
    $out = Invoke-Verbs ("${prefix}NewPrompt -Now -Title 'Bench reading' -Type Spike -Id K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Bench writing' -Type Task -Id Q4R9 | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Plan -Help; 'HELP-END'; " +
        "${prefix}Plan; 'BARE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan K7M2; 'NEITHER-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan K7M2 -Milestone 'M1' -Remove; 'BOTH-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan W3X7 -Milestone 'M1'; 'UNKNOWN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan bench -Milestone 'M1'; 'AMBIGUOUS-EXIT=' + `$LASTEXITCODE")
    $help = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the verb with the registered prefix' ($help -match [regex]::Escape("${prefix}Plan <id|file> -Milestone")) $help
    Assert-True '-Help names -Remove too' ($help -match [regex]::Escape("${prefix}Plan <id|file> -Remove")) $help
    Assert-True 'a bare call states the reason, exit 2' ($out -match 'no card given\.' -and $out -match 'BARE-EXIT=2') $out
    Assert-True 'a card with neither switch is refused, exit 2' ($out -match 'no milestone given\.' -and $out -match 'NEITHER-EXIT=2') $out
    Assert-True '-Milestone and -Remove together are refused, exit 2' ($out -match "do not go together" -and $out -match 'BOTH-EXIT=2') $out
    Assert-True 'an id nobody has is refused, not guessed at' ($out -match "No card with id 'W3X7'" -and $out -match 'UNKNOWN-EXIT=2') $out
    Assert-True 'a name that matches two cards is refused, and both are named' ($out -match "'bench' matches 2 cards" -and $out -match 'AMBIGUOUS-EXIT=2' -and $out -match 'Spike-K7M2-' -and $out -match 'TaskQ4R9-') $out
    $spike = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'the card exists to be planned' 1 $spike.Count
    $original = [System.IO.File]::ReadAllText($spike[0].FullName)
    # NewPrompt -Title's offline form already writes a placeholder Sprint line
    # ("(not linked)", docs/hub/cards.md) -- so "untouched" means byte for byte
    # unchanged, not "carries no Sprint line at all".
    Assert-True 'the card already carries the offline placeholder line' ($original -match [regex]::Escape("$sprint (not linked)"))
    $afterRefusals = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-Equal 'and no refusal changed it' $original $afterRefusals
    $backlogCard = Find-Card 'TaskQ4R9-*.prompt.md' $consts.folders.backlog
    Assert-Equal 'the second card is still in backlog/' 1 $backlogCard.Count

    Write-Host ""
    Write-Host "-- -Milestone writes the whole title, never truncated -" -ForegroundColor Cyan

    $long = 'M2 -- 1.2.0, the standup sees the work, and a title this long is never cut down for the write side'
    $out = Invoke-Verbs ("${prefix}Plan k7m2 -Milestone '$long'; 'SET-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan k7m2 -Milestone' exits 0, the id typed in any case" ($out -match 'SET-EXIT=0') $out
    Assert-True 'and says what it planned' ($out -match [regex]::Escape("K7M2 is planned into $long")) $out
    $marked = [System.IO.File]::ReadAllText($spike[0].FullName)
    $markedLines = @(($marked -replace "`r`n", "`n").Split("`n") | Where-Object { $_ -like "$sprint*" })
    Assert-True 'the card carries the WHOLE title on the Sprint line, in place -- the line already existed' ($markedLines.Count -eq 1 -and $markedLines[0] -ceq "$sprint $long") $marked
    Assert-True 'Created is still the LAST footer line -- replacing in place moved nothing' ($marked -match [regex]::Escape($created) -and ($marked.IndexOf($sprint) -lt $marked.IndexOf($created)))
    Assert-True 'the card it CREATED is still LF' (-not $marked.Contains("`r"))

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone '$long'; 'AGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'repeating the same milestone exits 0 and writes nothing' ($out -match 'AGAIN-EXIT=0' -and $out -match 'already planned into') $out
    Assert-Equal 'the card is byte for byte what it was' $marked ([System.IO.File]::ReadAllText($spike[0].FullName))

    Write-Host ""
    Write-Host "-- A different milestone replaces the line in place -----" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone 'M3'; 'REPLACE-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan K7M2 -Milestone M3' exits 0" ($out -match 'REPLACE-EXIT=0') $out
    $replaced = [System.IO.File]::ReadAllText($spike[0].FullName)
    $sprintLines = @(($replaced -replace "`r`n", "`n").Split("`n") | Where-Object { $_ -like "$sprint*" })
    Assert-True 'still exactly one Sprint line' ($sprintLines.Count -eq 1 -and $sprintLines[0] -ceq "$sprint M3") $replaced

    Write-Host ""
    Write-Host "-- -Remove deletes the line; a card with none says so --" -ForegroundColor Cyan

    # -Remove deletes the line outright -- the card goes back to what it would
    # have been had it never carried a Sprint line at all, which is the ORIGINAL
    # minus its one Sprint line (the offline placeholder), not byte for byte the
    # original (which still had that line, as "(not linked)").
    $expectedAfterRemove = $original -replace [regex]::Escape("$sprint (not linked)`n"), ''
    Assert-True 'the baseline really had exactly one Sprint line to subtract' ($expectedAfterRemove.Length -lt $original.Length)

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove; 'REMOVE-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan K7M2 -Remove' exits 0" ($out -match 'REMOVE-EXIT=0' -and $out -match 'K7M2 is out of its sprint') $out
    $afterRemove = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-Equal 'the line is gone and nothing else moved' $expectedAfterRemove $afterRemove
    Assert-True 'no Sprint line survives' ($afterRemove -notmatch [regex]::Escape($sprint))

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove; 'REMOVEAGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'removing again exits 0 and writes nothing' ($out -match 'REMOVEAGAIN-EXIT=0' -and $out -match 'carries no sprint') $out
    Assert-Equal 'still exactly as it was' $expectedAfterRemove ([System.IO.File]::ReadAllText($spike[0].FullName))

    Write-Host ""
    Write-Host "-- A backlog card is planned WHERE it sits, never pulled -" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan Q4R9 -Milestone 'M2'; 'BACKLOG-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan Q4R9 -Milestone M2' exits 0" ($out -match 'BACKLOG-EXIT=0' -and $out -match 'Q4R9 is planned into M2') $out
    Assert-Equal 'the card stayed in backlog/ -- Plan never pulls a card into play' 1 (Find-Card 'TaskQ4R9-*.prompt.md' $consts.folders.backlog).Count
    Assert-Equal 'and never landed in current/' 0 (Find-Card 'TaskQ4R9-*.prompt.md' 'current').Count
    $plannedBacklog = [System.IO.File]::ReadAllText($backlogCard[0].FullName)
    Assert-True 'the backlog card carries the Sprint line' ($plannedBacklog -match [regex]::Escape("$sprint M2"))

    Write-Host ""
    Write-Host "-- An archived card is not found -- planning is forward --" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Archive Q4R9 | Out-Null; ${prefix}Plan Q4R9 -Milestone 'M9'; 'ARCHIVED-EXIT=' + `$LASTEXITCODE")
    $archived = Find-Card 'TaskQ4R9-*.prompt.md' 'archive'
    Assert-Equal 'the card is in archive/' 1 $archived.Count
    Assert-True "'Plan Q4R9' does not find it there, exit 2" ($out -match "No card with id 'Q4R9' in current/ or backlog/" -and $out -match 'ARCHIVED-EXIT=2') $out
    $closedText = [System.IO.File]::ReadAllText($archived[0].FullName)
    Assert-True 'the archived card keeps its planned Sprint line untouched' ($closedText -match [regex]::Escape("$sprint M2"))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }

# -- Summary ----------------------------------------------------------------------

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
