<#
.SYNOPSIS
    Tests for the Move verb -- a person's move to a lane, written as a line.
.DESCRIPTION
    Typed as a verb, in a fresh shell, on a scratch hub Start made: Move to In
    Progress writes **Started:**, to Code Review writes **Review:**, to Done
    archives; a card travels one way; every refusal exits 2 and writes nothing;
    and the state the verb reports is the state Status derives, because both
    dot-source Scripts/Get-PromptFileStatus.ps1.

    Run:  pwsh -File Tests/Test-Move.ps1
    Or:   {cliPrefix}TestToolkit -Move
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

$script:passed = 0; $script:failed = 0; $script:errors = @()
function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:passed++; Write-Host "  PASS  $TestName" -ForegroundColor Green }
    else {
        $script:failed++; $msg = "  FAIL  $TestName"; if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg; Write-Host $msg -ForegroundColor Red
    }
}

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
$consts = Get-P20Consts

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-move-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
$hub = Join-Path $base 'hub'; $log = Join-Path $base 'log'
New-Item -ItemType Directory -Path $hub, $log -Force | Out-Null
$prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
$preamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$hub'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
    "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
function Invoke-Verbs {
    param([string]$Commands)
    return (& pwsh -NoProfile -NonInteractive -Command ($preamble + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
}
function Find-Card { param([string]$Filter, [string]$FolderName)
    return @(Get-ChildItem $hub -Recurse -Filter $Filter | Where-Object { $_.DirectoryName -match "[\\/]$FolderName`$" }) }
function Read-Card { param([string]$Filter) $f = Find-Card $Filter 'current'; if ($f.Count -eq 1) { [System.IO.File]::ReadAllText($f[0].FullName) } else { '' } }

try {
    Write-Host "-- Refusals write nothing ---------------------------------" -ForegroundColor Cyan
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'A script never checked in' -Type Task -Id K7M2 -Now | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Move -Help; 'HELP-END'; " +
        "${prefix}Move; 'BARE=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2; 'NOLANE=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2 -To Planned; 'BADLANE=' + `$LASTEXITCODE; " +
        "${prefix}Move W3X7 -To InProgress; 'NOCARD=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2 -To Active; 'TOACTIVE=' + `$LASTEXITCODE")
    $help = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the lanes with the registered prefix' ($help -match [regex]::Escape("${prefix}Move <id|file> -To InProgress") -and $help -match 'CodeReview' -and $help -match 'Done' -and $help -match '-To Active' -and $help -match '-To Backlog') $help
    Assert-True 'a bare call is a stated refusal' ($out -match 'no card given' -and $out -match 'BARE=2') $out
    Assert-True 'a card with no lane is refused, naming the lanes' ($out -match "'' is not a lane" -and $out -match '-To Backlog, -To Active' -and $out -match 'NOLANE=2') $out
    Assert-True 'a lane that does not exist is refused: Planned is the folder Backlog, not a word' ($out -match "'Planned' is not a lane" -and $out -match 'BADLANE=2') $out
    Assert-True 'an id nobody has is refused, and says archive/ is Done' ($out -match "No card with id 'W3X7' in current/ or backlog/" -and $out -match 'already Done' -and $out -match 'NOCARD=2') $out
    Assert-True 'an Active card moved to Active: already there, nothing moved, exit 0' ($out -match 'K7M2 is already Active' -and $out -match 'TOACTIVE=0') $out
    $original = Read-Card 'TaskK7M2-*.prompt.md'
    Assert-True 'and none of them wrote a line' ($original -and $original -notmatch [regex]::Escape($consts.stamps.started) -and $original -notmatch [regex]::Escape($consts.stamps.review))

    Write-Host ""
    Write-Host "-- Forward: Started, then Review, then Done ------------------" -ForegroundColor Cyan
    $out = Invoke-Verbs ("${prefix}Move k7m2 -To inprogress; 'IP=' + `$LASTEXITCODE; " +
        "'STATUS-BEGIN'; ${prefix}Status; 'STATUS-END'; " +
        "${prefix}Move K7M2 -To InProgress; 'AGAIN=' + `$LASTEXITCODE")
    Assert-True "'Move k7m2 -To inprogress' -- any case, no space -- exits 0" ($out -match 'IP=0' -and $out -match "K7M2 is $($consts.status.inProgress)") $out
    $card = Read-Card 'TaskK7M2-*.prompt.md'
    Assert-True 'the card carries **Started:** today, above Created' ($card -match ('(?m)^' + [regex]::Escape($consts.stamps.started) + ' \d{4}-\d{2}-\d{2}\n' + [regex]::Escape($consts.stamps.created))) $card
    Assert-True 'and the card is still LF' (-not $card.Contains("`r"))
    $status = [regex]::Match($out, '(?s)STATUS-BEGIN(.*)STATUS-END').Groups[1].Value
    Assert-True 'Status reads it as In Progress -- same rule, same file' ($status -match "Status:\s+$($consts.status.inProgress)") $status
    Assert-True 'moving to where it already is writes nothing, exit 0' ($out -match 'AGAIN=0' -and $out -match 'already') $out

    $out = Invoke-Verbs ("${prefix}Move K7M2 -To 'Code Review'; 'CR=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2 -To InProgress; 'BACK=' + `$LASTEXITCODE; " +
        "'STATUS-BEGIN'; ${prefix}Status; 'STATUS-END'")
    Assert-True 'Move -To "Code Review" -- the contract''s word with its space -- exits 0' ($out -match 'CR=0') $out
    $card = Read-Card 'TaskK7M2-*.prompt.md'
    Assert-True 'the card carries **Review:** as well, and keeps **Started:**' ($card -match [regex]::Escape($consts.stamps.review) -and $card -match [regex]::Escape($consts.stamps.started))
    $status = [regex]::Match($out, '(?s)STATUS-BEGIN(.*)STATUS-END').Groups[1].Value
    Assert-True 'Status reads it as Code Review: the Review line outranks Started' ($status -match "Status:\s+$($consts.status.codeReview)") $status
    Assert-True 'moving BACK to In Progress is refused: a card travels one way' ($out -match 'BACK=2' -and $out -match 'travels one way' -and $out -match 'by hand') $out

    $out = Invoke-Verbs "${prefix}Move K7M2 -To Done; 'DONE=' + `$LASTEXITCODE"
    Assert-True "'Move -To Done' exits 0" ($out -match 'DONE=0') $out
    Assert-True 'and the card is in archive/, stamped Closed -- it was Archive, exactly' ((Find-Card 'TaskK7M2-*.prompt.md' 'archive').Count -eq 1 -and ([System.IO.File]::ReadAllText((Find-Card 'TaskK7M2-*.prompt.md' 'archive')[0].FullName) -match [regex]::Escape($consts.stamps.closed)))
    Assert-True 'and gone from current/' ((Find-Card 'TaskK7M2-*.prompt.md' 'current').Count -eq 0)
    $out = Invoke-Verbs "${prefix}Move K7M2 -To CodeReview; 'ARCHIVED=' + `$LASTEXITCODE"
    Assert-True 'a card in archive/ cannot be moved: it is Done' ($out -match 'ARCHIVED=2') $out

    Write-Host ""
    Write-Host "-- A spike goes straight to review, with nothing committed ----" -ForegroundColor Cyan
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Can it be done in one pass' -Type Spike -Id Q4R9 | Out-Null; " +
        "${prefix}Move Q4R9 -To CodeReview; 'SPIKE=' + `$LASTEXITCODE; 'STATUS-BEGIN'; ${prefix}Status; 'STATUS-END'")
    $status = [regex]::Match($out, '(?s)STATUS-BEGIN(.*)STATUS-END').Groups[1].Value
    Assert-True 'Backlog -> Code Review in one move, exit 0, and Status agrees' ($out -match 'SPIKE=0' -and $status -match "Status:\s+$($consts.status.codeReview)") $out
    Assert-True 'the planned spike was pulled into current/ BEFORE its Review line was written' ((Find-Card 'Spike-Q4R9-*.prompt.md' 'current').Count -eq 1 -and (Find-Card 'Spike-Q4R9-*.prompt.md' $consts.folders.backlog).Count -eq 0 -and $out -match 'pulled from backlog/ into current/') $out

    Write-Host ""
    Write-Host "-- The backlog: planned by default, pulled into play ---------" -ForegroundColor Cyan
    # Row: a new card -> backlog/ by default.
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Cache the thumbnails' -Type Task -Id R9PX; 'NEW=' + `$LASTEXITCODE; " +
        "'STATUS-BEGIN'; ${prefix}Status; 'STATUS-END'")
    Assert-True 'NewPrompt with no -Now writes the card to backlog/, exit 0' ($out -match 'NEW=0' -and (Find-Card 'TaskR9PX-*.prompt.md' $consts.folders.backlog).Count -eq 1 -and (Find-Card 'TaskR9PX-*.prompt.md' 'current').Count -eq 0) $out
    $status = [regex]::Match($out, '(?s)STATUS-BEGIN(.*)STATUS-END').Groups[1].Value
    Assert-True 'Status folds the backlog AFTER the cards in play: a count and the names, not a numbered row' ($status -match "(?s)Active prompts.*$($consts.status.backlog) \(1\), planned -- not in play:\s+TaskR9PX-cache-the-thumbnails\.prompt\.md" -and $status -notmatch '\d+\. Task 403|\d+\. Task R9PX') $status
    $planned = Find-Card 'TaskR9PX-*.prompt.md' $consts.folders.backlog
    $plannedBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($planned[0].FullName))
    Assert-True 'a planned card carries none of the in-play markers' (([System.IO.File]::ReadAllText($planned[0].FullName)) -notmatch $consts.regex.commitBullet -and ([System.IO.File]::ReadAllText($planned[0].FullName)) -notmatch $consts.regex.startedLine)

    # Row: an id already in backlog/ is returned, not rewritten -- with or without -Now.
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Cache the thumbnails' -Type Task -Id R9PX -Now; 'AGAIN=' + `$LASTEXITCODE")
    Assert-True 'NewPrompt for a card already in backlog/ returns it, exit 0, and -Now names the pull' ($out -match 'AGAIN=0' -and $out -match 'already in .*backlog/' -and $out -match [regex]::Escape("${prefix}Move R9PX -To Active")) $out
    Assert-True 'and wrote nothing: no second card, the bytes unchanged' ((Find-Card 'TaskR9PX-*.prompt.md' 'current').Count -eq 0 -and [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($planned[0].FullName)) -ceq $plannedBytes)

    # Row: Move -To Active -- the explicit pull. A rename: the bytes do not change.
    $out = Invoke-Verbs "${prefix}Move R9PX -To Active; 'PULL=' + `$LASTEXITCODE"
    $inPlay = Find-Card 'TaskR9PX-*.prompt.md' 'current'
    Assert-True 'Move -To Active moves the card from backlog/ to current/, exit 0' ($out -match 'PULL=0' -and $inPlay.Count -eq 1 -and (Find-Card 'TaskR9PX-*.prompt.md' $consts.folders.backlog).Count -eq 0) $out
    Assert-True 'and the move did not touch a byte of the card' ($inPlay.Count -eq 1 -and [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($inPlay[0].FullName)) -ceq $plannedBytes)

    # Row: Move -To Backlog -- an Active card with nothing threaded goes back.
    $out = Invoke-Verbs "${prefix}Move R9PX -To Backlog; 'PARK=' + `$LASTEXITCODE; ${prefix}Move R9PX -To Backlog; 'PARKAGAIN=' + `$LASTEXITCODE"
    $parked = Find-Card 'TaskR9PX-*.prompt.md' $consts.folders.backlog
    Assert-True 'Move -To Backlog parks an Active card, exit 0, the bytes unchanged' ($out -match 'PARK=0' -and $parked.Count -eq 1 -and [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($parked[0].FullName)) -ceq $plannedBytes) $out
    Assert-True 'a card already in backlog/ moved to Backlog: nothing moved, exit 0' ($out -match 'PARKAGAIN=0' -and $out -match 'already Backlog') $out

    # Row: the implicit pull on Move -To InProgress, then Move -To Backlog refused.
    $out = Invoke-Verbs ("${prefix}Move R9PX -To InProgress; 'IP=' + `$LASTEXITCODE; " +
        "${prefix}Move R9PX -To Backlog; 'REFUSED=' + `$LASTEXITCODE")
    $started = Find-Card 'TaskR9PX-*.prompt.md' 'current'
    Assert-True 'Move -To InProgress on a planned card pulls it into current/ first, then writes Started' ($out -match 'IP=0' -and $started.Count -eq 1 -and ([System.IO.File]::ReadAllText($started[0].FullName)) -match [regex]::Escape($consts.stamps.started)) $out
    Assert-True 'Move -To Backlog refuses a card with something threaded, exit 2, naming it' ($out -match 'REFUSED=2' -and $out -match 'in play, not backlog' -and $out -match [regex]::Escape($consts.stamps.started)) $out
    Assert-True 'and the refused card stayed in current/' ((Find-Card 'TaskR9PX-*.prompt.md' 'current').Count -eq 1 -and (Find-Card 'TaskR9PX-*.prompt.md' $consts.folders.backlog).Count -eq 0)

    # Row: -Now writes current/ at once; Archive works from either folder.
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Right now' -Type Task -Id T3MX -Now | Out-Null; " +
        "${prefix}NewPrompt -Title 'Never mind' -Type Task -Id W4CY | Out-Null; " +
        "${prefix}Archive W4CY; 'ARCH=' + `$LASTEXITCODE")
    Assert-True 'NewPrompt -Now writes the card to current/, not backlog/' ((Find-Card 'TaskT3MX-*.prompt.md' 'current').Count -eq 1 -and (Find-Card 'TaskT3MX-*.prompt.md' $consts.folders.backlog).Count -eq 0)
    $retired = Find-Card 'TaskW4CY-*.prompt.md' 'archive'
    Assert-True 'Archive retires a planned card straight from backlog/, with the Closed stamp' ($out -match 'ARCH=0' -and $retired.Count -eq 1 -and ([System.IO.File]::ReadAllText($retired[0].FullName)) -match [regex]::Escape($consts.stamps.closed) -and (Find-Card 'TaskW4CY-*.prompt.md' $consts.folders.backlog).Count -eq 0) $out

    Write-Host ""
    Write-Host "-- A card's full path works whichever Space is active -------" -ForegroundColor Cyan
    # Two Spaces in one hub. Every card below belongs to beta; every verb that acts
    # on one runs with P20_ACTIVE_SPACE=alpha and names the card by its full path.
    $sHub = Join-Path $base 'spaces-hub'
    New-Item -ItemType Directory -Path $sHub -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $sHub 'hub.json'),
        '{ "hub": 1, "spaces": [ { "slug": "alpha", "name": "Alpha", "status": "local", "promptsFolder": "alpha" }, { "slug": "beta", "name": "Beta", "status": "local", "promptsFolder": "beta" } ] }',
        (New-Object System.Text.UTF8Encoding($false)))
    function Invoke-InSpace {
        param([string]$Space, [string]$Commands)
        $pre = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$sHub'; `$env:P20_ACTIVE_SPACE = '$Space'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
            "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
        return (& pwsh -NoProfile -NonInteractive -Command ($pre + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    function Get-SpaceCard { param([string]$Space, [string]$Folder, [string]$Filter)
        $dir = Join-Path (Join-Path $sHub $Space) $Folder
        if (-not (Test-Path -LiteralPath $dir)) { return @() }
        return @(Get-ChildItem -LiteralPath $dir -File -Filter $Filter) }

    $out = Invoke-InSpace 'beta' ("${prefix}NewPrompt -Title 'Belongs to beta' -Type Task -Id H6PN | Out-Null; " +
        "${prefix}NewPrompt -Title 'Also beta' -Type Task -Id J7RT | Out-Null; 'MADE=' + `$LASTEXITCODE")
    $planned = Get-SpaceCard 'beta' $consts.folders.backlog 'TaskH6PN-*.prompt.md'
    Assert-True 'the beta cards were made in beta/backlog/' ($planned.Count -eq 1 -and (Get-SpaceCard 'beta' $consts.folders.backlog 'TaskJ7RT-*.prompt.md').Count -eq 1) $out
    $plannedPath = $planned[0].FullName

    # The finding, exactly: a full path into another Space refused with "No card matching".
    $out = Invoke-InSpace 'alpha' "${prefix}Move '$plannedPath' -To Active; 'PULL=' + `$LASTEXITCODE"
    $pulled = Get-SpaceCard 'beta' $consts.folders.current 'TaskH6PN-*.prompt.md'
    Assert-True "Move <beta's backlog path> -To Active, with alpha active: exit 0, into beta/current/" ($out -match 'PULL=0' -and $pulled.Count -eq 1 -and (Get-SpaceCard 'beta' $consts.folders.backlog 'TaskH6PN-*.prompt.md').Count -eq 0) $out
    Assert-True 'and nothing landed in alpha' ((Get-SpaceCard 'alpha' $consts.folders.current '*.prompt.md').Count -eq 0 -and (Get-SpaceCard 'alpha' $consts.folders.backlog '*.prompt.md').Count -eq 0)
    $inPlayPath = if ($pulled.Count -eq 1) { $pulled[0].FullName } else { Join-Path (Join-Path (Join-Path $sHub 'beta') $consts.folders.current) $planned[0].Name }

    $out = Invoke-InSpace 'alpha' "${prefix}Move '$inPlayPath' -To Backlog; 'PARK=' + `$LASTEXITCODE"
    Assert-True "Move <beta's current path> -To Backlog parks it in BETA's backlog/, not alpha's" ($out -match 'PARK=0' -and (Get-SpaceCard 'beta' $consts.folders.backlog 'TaskH6PN-*.prompt.md').Count -eq 1 -and (Get-SpaceCard 'alpha' $consts.folders.backlog '*.prompt.md').Count -eq 0) $out
    $out = Invoke-InSpace 'alpha' "${prefix}Move '$plannedPath' -To InProgress; 'IP=' + `$LASTEXITCODE"
    $started = Get-SpaceCard 'beta' $consts.folders.current 'TaskH6PN-*.prompt.md'
    Assert-True "Move <beta's backlog path> -To InProgress pulls it into beta/current/ and writes Started" ($out -match 'IP=0' -and $started.Count -eq 1 -and ([System.IO.File]::ReadAllText($started[0].FullName)) -match [regex]::Escape($consts.stamps.started)) $out
    $startedPath = $inPlayPath

    $out = Invoke-InSpace 'alpha' "${prefix}Plan '$startedPath' -Milestone 'Sprint 9'; 'PLAN=' + `$LASTEXITCODE"
    Assert-True "Plan <beta's current path> -Milestone writes the Sprint line on that card" ($out -match 'PLAN=0' -and (Test-Path -LiteralPath $startedPath) -and ([System.IO.File]::ReadAllText($startedPath)) -match '\*\*Sprint:\*\* Sprint 9') $out

    $out = Invoke-InSpace 'alpha' "${prefix}Move '$startedPath' -To Done; 'DONE=' + `$LASTEXITCODE"
    $done = Get-SpaceCard 'beta' $consts.folders.archive 'TaskH6PN-*.prompt.md'
    Assert-True "Move <beta's current path> -To Done archives it into BETA's archive/, stamped Closed" ($out -match 'DONE=0' -and $done.Count -eq 1 -and ([System.IO.File]::ReadAllText($done[0].FullName)) -match [regex]::Escape($consts.stamps.closed) -and (Get-SpaceCard 'alpha' $consts.folders.archive '*.prompt.md').Count -eq 0) $out
    $donePath = Join-Path (Join-Path (Join-Path $sHub 'beta') $consts.folders.archive) $planned[0].Name

    $out = Invoke-InSpace 'alpha' ("${prefix}Archive '$donePath'; 'AGAIN=' + `$LASTEXITCODE; " +
        "${prefix}Move '$donePath' -To CodeReview; 'FROMARCH=' + `$LASTEXITCODE")
    Assert-True 'Archive <an archived path> says it is already archived, exit 0' ($out -match 'AGAIN=0' -and $out -match 'Already archived') $out
    Assert-True 'Move <an archived path> is refused, exit 2: a path into archive/ is not a card in play' ($out -match 'FROMARCH=2' -and $out -match 'No card matching') $out

    $otherPath = Join-Path (Join-Path (Join-Path $sHub 'beta') $consts.folders.backlog) 'TaskJ7RT-also-beta.prompt.md'
    $out = Invoke-InSpace 'alpha' "${prefix}Archive '$otherPath'; 'ARCHPATH=' + `$LASTEXITCODE"
    Assert-True "Archive <beta's backlog path>, with alpha active: into beta/archive/" ($out -match 'ARCHPATH=0' -and (Get-SpaceCard 'beta' $consts.folders.archive 'TaskJ7RT-*.prompt.md').Count -eq 1) $out

    # What must not move: an id and a partial name still read the ACTIVE Space only,
    # and a partial name still refuses a non-interactive caller.
    $out = Invoke-InSpace 'beta' "${prefix}NewPrompt -Title 'Gamma ray burst' -Type Task -Id M3XC -Now | Out-Null; 'MADE=' + `$LASTEXITCODE"
    $out = Invoke-InSpace 'alpha' ("${prefix}Move M3XC -To InProgress; 'BYID=' + `$LASTEXITCODE; " +
        "${prefix}Move 'gamma-ray' -To InProgress; 'BYNAME=' + `$LASTEXITCODE")
    Assert-True "with alpha active, beta's card by ID is not found: an id reads the active Space" ($out -match 'BYID=2' -and $out -match "No card with id 'M3XC'") $out
    Assert-True "and by partial name is not found either" ($out -match 'BYNAME=2' -and $out -match "No card matching 'gamma-ray'") $out
    $out = Invoke-InSpace 'beta' "`$env:TOOLKIT_QUIET_STARTUP = '1'; try { ${prefix}Archive 'gamma-ray' } catch { 'RAISED: ' + `$_.Exception.Message }; 'QUIET=' + `$LASTEXITCODE"
    Assert-True 'a partial name still refuses a non-interactive caller, exit 2, and moves nothing' ($out -match 'QUIET=2' -and $out -match 'only by partial name' -and (Get-SpaceCard 'beta' $consts.folders.current 'TaskM3XC-*.prompt.md').Count -eq 1) $out
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) { Write-Host ""; Write-Host "  Failures:" -ForegroundColor Red; foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red } }
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
if ($script:failed -gt 0) { exit 1 }
exit 0
