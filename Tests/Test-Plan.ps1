<#
.SYNOPSIS
    Tests for the Plan verb -- the write side of a card's two planning lines.
.DESCRIPTION
    The line writer itself (where the line goes, that an unchanged card is not written, that
    the card keeps its own bytes) is already held by Test-Billable.ps1 against the one shared
    writer, Set-P20CardLine -- this suite does not repeat that. What is specific to Plan is
    tested AS A VERB -- the real module imported in a fresh shell, typed the way a person
    types it -- because a suite that runs a script directly does not test the verb:

      - -Milestone writes **Milestone:** and -Sprint writes **Sprint:**, each its own line,
        whole and never truncated; a card can hold both, and each write leaves the other
        reading as it was (docs/hub/cards.md, "Milestone and sprint: two lines")
      - an OLD card -- one **Sprint:** line naming its milestone, no **Milestone:** line --
        keeps that milestone through -Sprint and through -Remove -Only Sprint
      - -Remove deletes both lines, as it always deleted the one; -Remove -Only Milestone
        or -Only Sprint takes the card out of one
      - -Milestone / -Sprint and -Remove refuse together; none given refuses; -Only
        without -Remove, or naming no line, refuses
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
$sprint = [string]$consts.stamps.sprint
$milestone = [string]$consts.stamps.milestone
. (Join-Path $pkgRoot 'Scripts/Get-PromptFileStatus.ps1')
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
        "${prefix}Plan K7M2 -Sprint 'S1' -Remove; 'SPRINTREMOVE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan K7M2 -Sprint 'S1' -Only Sprint; 'ONLYALONE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan K7M2 -Remove -Only Tags; 'ONLYBAD-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan W3X7 -Milestone 'M1'; 'UNKNOWN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Plan bench -Milestone 'M1'; 'AMBIGUOUS-EXIT=' + `$LASTEXITCODE")
    $help = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the verb with the registered prefix' ($help -match [regex]::Escape("${prefix}Plan <id|file> -Milestone")) $help
    Assert-True '-Help names -Sprint beside it' ($help -match [regex]::Escape("${prefix}Plan <id|file> -Sprint")) $help
    Assert-True '-Help names -Remove and -Remove -Only too' ($help -match [regex]::Escape("${prefix}Plan <id|file> -Remove ") -and $help -match [regex]::Escape("${prefix}Plan <id|file> -Remove -Only")) $help
    Assert-True 'a bare call states the reason, exit 2' ($out -match 'no card given\.' -and $out -match 'BARE-EXIT=2') $out
    Assert-True 'a card with no switch is refused, exit 2' ($out -match 'no milestone or sprint given\.' -and $out -match 'NEITHER-EXIT=2') $out
    Assert-True '-Milestone and -Remove together are refused, exit 2' ($out -match "do not go together" -and $out -match 'BOTH-EXIT=2') $out
    Assert-True '-Sprint and -Remove together are refused, exit 2' ($out -match 'SPRINTREMOVE-EXIT=2') $out
    Assert-True '-Only without -Remove is refused, exit 2' ($out -match "'-Only' goes with '-Remove'" -and $out -match 'ONLYALONE-EXIT=2') $out
    Assert-True '-Only naming no line Plan writes is refused, exit 2' ($out -match "'-Only Tags' is not a line Plan writes" -and $out -match 'ONLYBAD-EXIT=2') $out
    Assert-True 'an id nobody has is refused, not guessed at' ($out -match "No card with id 'W3X7'" -and $out -match 'UNKNOWN-EXIT=2') $out
    Assert-True 'a name that matches two cards is refused, and both are named' ($out -match "'bench' matches 2 cards" -and $out -match 'AMBIGUOUS-EXIT=2' -and $out -match 'Spike-K7M2-' -and $out -match 'TaskQ4R9-') $out
    $spike = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'the card exists to be planned' 1 $spike.Count
    $original = [System.IO.File]::ReadAllText($spike[0].FullName)
    # NewPrompt -Title's offline form already writes a placeholder Sprint line
    # ("(not linked)", docs/hub/cards.md) -- so "untouched" means byte for byte
    # unchanged, not "carries no Sprint line at all".
    Assert-True 'the card already carries the offline placeholder line' ($original -match [regex]::Escape("$sprint (not linked)"))
    Assert-True 'and no milestone line -- a card is born with none' ($original -notmatch [regex]::Escape($milestone))
    $afterRefusals = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-Equal 'and no refusal changed it' $original $afterRefusals
    $backlogCard = Find-Card 'TaskQ4R9-*.prompt.md' $consts.folders.backlog
    Assert-Equal 'the second card is still in backlog/' 1 $backlogCard.Count

    function Get-Lines {
        param([string]$Text, [string]$Stamp)
        return @(($Text -replace "`r`n", "`n").Split("`n") | Where-Object { $_.StartsWith($Stamp) })
    }

    Write-Host ""
    Write-Host "-- -Milestone writes its own line, whole, never truncated" -ForegroundColor Cyan

    $long = 'M2 -- 1.2.0, the standup sees the work, and a title this long is never cut down for the write side'
    $out = Invoke-Verbs ("${prefix}Plan k7m2 -Milestone '$long'; 'SET-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan k7m2 -Milestone' exits 0, the id typed in any case" ($out -match 'SET-EXIT=0') $out
    Assert-True 'and says what it planned' ($out -match [regex]::Escape("K7M2 is planned into $long")) $out
    $marked = [System.IO.File]::ReadAllText($spike[0].FullName)
    $mLines = @(Get-Lines $marked $milestone)
    Assert-True 'the card carries the WHOLE title on a Milestone line of its own' ($mLines.Count -eq 1 -and $mLines[0] -ceq "$milestone $long") $marked
    Assert-True 'the Sprint line is untouched -- -Milestone never writes it' (@(Get-Lines $marked $sprint).Count -eq 1 -and @(Get-Lines $marked $sprint)[0] -ceq "$sprint (not linked)") $marked
    Assert-True 'Created is still the LAST footer line -- the new line went above it' ($marked.IndexOf($milestone) -lt $marked.IndexOf($created))
    Assert-True 'the card it CREATED is still LF' (-not $marked.Contains("`r"))
    Assert-Equal 'the one reader reads the milestone' $long (Get-P20CardMilestone $marked)

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone '$long'; 'AGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'repeating the same milestone exits 0 and writes nothing' ($out -match 'AGAIN-EXIT=0' -and $out -match 'already planned into') $out
    Assert-Equal 'the card is byte for byte what it was' $marked ([System.IO.File]::ReadAllText($spike[0].FullName))

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone 'M3'; 'REPLACE-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan K7M2 -Milestone M3' exits 0" ($out -match 'REPLACE-EXIT=0') $out
    $replaced = [System.IO.File]::ReadAllText($spike[0].FullName)
    $mLines = @(Get-Lines $replaced $milestone)
    Assert-True 'still exactly one Milestone line, replaced in place' ($mLines.Count -eq 1 -and $mLines[0] -ceq "$milestone M3") $replaced

    Write-Host ""
    Write-Host "-- -Sprint writes its own line; a card holds both -----" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Sprint 'Sprint 9'; 'SPRINT-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan K7M2 -Sprint' exits 0 and says so" ($out -match 'SPRINT-EXIT=0' -and $out -match [regex]::Escape('K7M2 is in sprint Sprint 9')) $out
    $both = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'the Sprint line is replaced in place, and still one' (@(Get-Lines $both $sprint).Count -eq 1 -and @(Get-Lines $both $sprint)[0] -ceq "$sprint Sprint 9") $both
    Assert-True 'the Milestone line is untouched' (@(Get-Lines $both $milestone).Count -eq 1 -and @(Get-Lines $both $milestone)[0] -ceq "$milestone M3") $both
    Assert-True 'the card reads both: milestone M3, sprint Sprint 9' ((Get-P20CardMilestone $both) -ceq 'M3' -and (Get-P20CardSprint $both) -ceq 'Sprint 9')
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Sprint 'Sprint 9'; 'SPRINTAGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'the same sprint again writes nothing' ($out -match 'SPRINTAGAIN-EXIT=0' -and $out -match 'already in sprint Sprint 9') $out
    Assert-Equal 'byte for byte' $both ([System.IO.File]::ReadAllText($spike[0].FullName))
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone 'M4' -Sprint 'Sprint 10'; 'PAIR-EXIT=' + `$LASTEXITCODE")
    $pair = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'both in one call: each line its own value' ($out -match 'PAIR-EXIT=0' -and (Get-P20CardMilestone $pair) -ceq 'M4' -and (Get-P20CardSprint $pair) -ceq 'Sprint 10' -and @(Get-Lines $pair $milestone).Count -eq 1 -and @(Get-Lines $pair $sprint).Count -eq 1) $pair

    Write-Host ""
    Write-Host "-- -Remove -Only takes the card out of one ------------" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only sprint; 'ONLYS-EXIT=' + `$LASTEXITCODE")
    $noSprint = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True "'-Remove -Only sprint' (any case) deletes the Sprint line and keeps the milestone" ($out -match 'ONLYS-EXIT=0' -and $out -match 'K7M2 is out of its sprint' -and @(Get-Lines $noSprint $sprint).Count -eq 0 -and (Get-P20CardMilestone $noSprint) -ceq 'M4') $noSprint
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only Sprint; 'ONLYSAGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'again: no sprint, nothing written' ($out -match 'ONLYSAGAIN-EXIT=0' -and $out -match 'carries no sprint -- nothing written') $out
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only Milestone; 'ONLYM-EXIT=' + `$LASTEXITCODE")
    $noMilestone = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True "'-Remove -Only Milestone' with no sprint left deletes the line" ($out -match 'ONLYM-EXIT=0' -and $out -match 'K7M2 is out of its milestone' -and @(Get-Lines $noMilestone $milestone).Count -eq 0 -and -not (Get-P20CardMilestone $noMilestone)) $noMilestone

    Write-Host ""
    Write-Host "-- A sprint on a card with no milestone is not one ----" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Sprint 'Sprint 11'; 'FRESH-EXIT=' + `$LASTEXITCODE")
    $fresh = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'the sprint is written and the card is still in no milestone' ($out -match 'FRESH-EXIT=0' -and (Get-P20CardSprint $fresh) -ceq 'Sprint 11' -and -not (Get-P20CardMilestone $fresh)) $fresh
    Assert-True 'because a placeholder Milestone line says none' (@(Get-Lines $fresh $milestone).Count -eq 1 -and @(Get-Lines $fresh $milestone)[0] -ceq "$milestone (none)") $fresh
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only Sprint | Out-Null; 'X'")
    $clean = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'and with the sprint gone the placeholder goes too' (@(Get-Lines $clean $milestone).Count -eq 0 -and @(Get-Lines $clean $sprint).Count -eq 0) $clean

    Write-Host ""
    Write-Host "-- An OLD card: its one Sprint line names its milestone" -ForegroundColor Cyan

    # Before the two lines were separate, Plan -Milestone wrote **Sprint:**. A card
    # like that reads its milestone from it -- and keeps it through every write.
    $oldText = ($clean -replace [regex]::Escape($created), ("$sprint M2 -- the old line`n" + $created))
    [System.IO.File]::WriteAllText($spike[0].FullName, $oldText)
    Assert-True 'the old card reads its Sprint line as its milestone, as it always did' ((Get-P20CardMilestone $oldText) -ceq 'M2 -- the old line' -and @(Get-Lines $oldText $milestone).Count -eq 0)
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Milestone 'M2 -- the old line'; 'OLDSAME-EXIT=' + `$LASTEXITCODE")
    Assert-True 'planning it into the milestone it already reads writes nothing' ($out -match 'OLDSAME-EXIT=0' -and $out -match 'already planned into') $out
    Assert-Equal 'byte for byte' $oldText ([System.IO.File]::ReadAllText($spike[0].FullName))
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Sprint 'Sprint 12'; 'OLDSPRINT-EXIT=' + `$LASTEXITCODE")
    $oldSprint = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True '-Sprint keeps the milestone it read on a line of its own' ($out -match 'OLDSPRINT-EXIT=0' -and (Get-P20CardMilestone $oldSprint) -ceq 'M2 -- the old line' -and (Get-P20CardSprint $oldSprint) -ceq 'Sprint 12' -and @(Get-Lines $oldSprint $milestone)[0] -ceq "$milestone M2 -- the old line") $oldSprint
    [System.IO.File]::WriteAllText($spike[0].FullName, $oldText)
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only Sprint; 'OLDONLYS-EXIT=' + `$LASTEXITCODE")
    $oldNoSprint = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True '-Remove -Only Sprint keeps the milestone it read' ($out -match 'OLDONLYS-EXIT=0' -and (Get-P20CardMilestone $oldNoSprint) -ceq 'M2 -- the old line' -and -not (Get-P20CardSprint $oldNoSprint)) $oldNoSprint
    [System.IO.File]::WriteAllText($spike[0].FullName, $oldText)
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove -Only Milestone; 'OLDONLYM-EXIT=' + `$LASTEXITCODE")
    $oldNoMilestone = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True '-Remove -Only Milestone keeps the line as a sprint, and the card in no milestone' ($out -match 'OLDONLYM-EXIT=0' -and -not (Get-P20CardMilestone $oldNoMilestone) -and (Get-P20CardSprint $oldNoMilestone) -ceq 'M2 -- the old line') $oldNoMilestone

    Write-Host ""
    Write-Host "-- -Remove deletes both lines; a card with none says so" -ForegroundColor Cyan

    # -Remove deletes the lines outright, as it always deleted the one -- the old
    # card goes back to the card it was before its Sprint line was written.
    [System.IO.File]::WriteAllText($spike[0].FullName, $oldText)
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove; 'REMOVE-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan K7M2 -Remove' exits 0" ($out -match 'REMOVE-EXIT=0' -and $out -match 'K7M2 is out of its milestone and sprint') $out
    $afterRemove = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-Equal 'the line is gone and nothing else moved' $clean $afterRemove
    [System.IO.File]::WriteAllText($spike[0].FullName, $pair)
    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove | Out-Null; 'X'")
    $afterRemoveBoth = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'on a card with both, both lines go' (@(Get-Lines $afterRemoveBoth $milestone).Count -eq 0 -and @(Get-Lines $afterRemoveBoth $sprint).Count -eq 0) $afterRemoveBoth

    $out = Invoke-Verbs ("${prefix}Plan K7M2 -Remove; 'REMOVEAGAIN-EXIT=' + `$LASTEXITCODE")
    Assert-True 'removing again exits 0 and writes nothing' ($out -match 'REMOVEAGAIN-EXIT=0' -and $out -match 'carries no milestone or sprint') $out
    Assert-Equal 'still exactly as it was' $afterRemoveBoth ([System.IO.File]::ReadAllText($spike[0].FullName))

    Write-Host ""
    Write-Host "-- A backlog card is planned WHERE it sits, never pulled -" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Plan Q4R9 -Milestone 'M2'; 'BACKLOG-EXIT=' + `$LASTEXITCODE")
    Assert-True "'Plan Q4R9 -Milestone M2' exits 0" ($out -match 'BACKLOG-EXIT=0' -and $out -match 'Q4R9 is planned into M2') $out
    Assert-Equal 'the card stayed in backlog/ -- Plan never pulls a card into play' 1 (Find-Card 'TaskQ4R9-*.prompt.md' $consts.folders.backlog).Count
    Assert-Equal 'and never landed in current/' 0 (Find-Card 'TaskQ4R9-*.prompt.md' 'current').Count
    $plannedBacklog = [System.IO.File]::ReadAllText($backlogCard[0].FullName)
    Assert-True 'the backlog card carries the Milestone line' ($plannedBacklog -match [regex]::Escape("$milestone M2"))

    Write-Host ""
    Write-Host "-- An archived card is not found -- planning is forward --" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Archive Q4R9 | Out-Null; ${prefix}Plan Q4R9 -Milestone 'M9'; 'ARCHIVED-EXIT=' + `$LASTEXITCODE")
    $archived = Find-Card 'TaskQ4R9-*.prompt.md' 'archive'
    Assert-Equal 'the card is in archive/' 1 $archived.Count
    Assert-True "'Plan Q4R9' does not find it there, exit 2" ($out -match "No card with id 'Q4R9' in current/ or backlog/" -and $out -match 'ARCHIVED-EXIT=2') $out
    $closedText = [System.IO.File]::ReadAllText($archived[0].FullName)
    Assert-True 'the archived card keeps its planned Milestone line untouched' ($closedText -match [regex]::Escape("$milestone M2"))
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
exit 0
