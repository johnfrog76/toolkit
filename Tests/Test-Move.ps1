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
    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'A script never checked in' -Type Task -Id K7M2 | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Move -Help; 'HELP-END'; " +
        "${prefix}Move; 'BARE=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2; 'NOLANE=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2 -To Planned; 'BADLANE=' + `$LASTEXITCODE; " +
        "${prefix}Move W3X7 -To InProgress; 'NOCARD=' + `$LASTEXITCODE; " +
        "${prefix}Move K7M2 -To Active; 'TOACTIVE=' + `$LASTEXITCODE")
    $help = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the three lanes with the registered prefix' ($help -match [regex]::Escape("${prefix}Move <id|file> -To InProgress") -and $help -match 'CodeReview' -and $help -match 'Done') $help
    Assert-True 'a bare call is a stated refusal' ($out -match 'no card given' -and $out -match 'BARE=2') $out
    Assert-True 'a card with no lane is refused, naming the three' ($out -match "'' is not a lane" -and $out -match 'NOLANE=2') $out
    Assert-True 'a lane that does not exist is refused' ($out -match "'Planned' is not a lane" -and $out -match 'BADLANE=2') $out
    Assert-True 'an id nobody has is refused, and says archive/ is Done' ($out -match "No card with id 'W3X7'" -and $out -match 'already Done' -and $out -match 'NOCARD=2') $out
    Assert-True 'Active is not a lane to move TO' ($out -match "'Active' is not a lane" -and $out -match 'TOACTIVE=2') $out
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
    Assert-True 'Active -> Code Review in one move, exit 0, and Status agrees' ($out -match 'SPIKE=0' -and $status -match "Status:\s+$($consts.status.codeReview)") $out
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
