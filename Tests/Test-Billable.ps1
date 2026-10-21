<#
.SYNOPSIS
    Tests for the Billable verb and the one card-line writer behind it.
.DESCRIPTION
    Two halves. Set-P20CardLine is tested directly: where the line goes, that an
    unchanged card is not written, and that the card keeps its own bytes. The
    verb is tested AS A VERB -- the real module imported in a fresh shell, typed
    the way a person types it -- because a suite that runs a script directly
    does not test the verb.

    Run:  pwsh -File Tests/Test-Billable.ps1
    Or:   {cliPrefix}TestToolkit -Billable
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$lineScript = Join-Path $pkgRoot 'Scripts/Set-CardLine.ps1'
if (-not (Test-Path $lineScript)) {
    Write-Error "Set-CardLine.ps1 not found at $lineScript"
    return
}

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

. $lineScript
$consts = Get-P20Consts
$billable = $consts.stamps.billable
$created = $consts.stamps.created

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-billable-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

function New-ScratchCard {
    param([string]$Name, [string]$Text)
    $path = Join-Path $base $Name
    [System.IO.File]::WriteAllText($path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

try {
    # -- The line writer ----------------------------------------------------------
    Write-Host "-- Set-P20CardLine: where the line goes ---------------" -ForegroundColor Cyan

    $footer = "# Spike K7M2: A question`n`nBody.`n`n---`n`n**Sprint:** --`n$created 2026-09-14`n"
    $card = New-ScratchCard 'a.prompt.md' $footer
    $changed = Set-P20CardLine -Path $card -Stamp $billable -Value 'no'
    $lines = [System.IO.File]::ReadAllText($card).Split("`n")
    Assert-True 'a new line reports a change' ([bool]$changed)
    $at = [array]::IndexOf($lines, "$billable no")
    Assert-True 'the line is written once' (@($lines | Where-Object { $_ -like "$billable*" }).Count -eq 1)
    Assert-Equal 'directly above the Created line' "$created 2026-09-14" $lines[$at + 1]
    Assert-Equal 'and below what was already there' '**Sprint:** --' $lines[$at - 1]

    $before = [System.IO.File]::ReadAllBytes($card)
    $stampBefore = (Get-Item $card).LastWriteTimeUtc
    $changed = Set-P20CardLine -Path $card -Stamp $billable -Value 'no'
    Assert-True 'saying the same thing again reports no change' (-not $changed)
    Assert-True 'and does not write the card' ((Get-Item $card).LastWriteTimeUtc -eq $stampBefore)
    Assert-True 'and leaves the card byte for byte as it was' ([System.Convert]::ToBase64String($before) -ceq [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($card)))

    $changed = Set-P20CardLine -Path $card -Stamp $billable -Value 'yes'
    $lines = [System.IO.File]::ReadAllText($card).Split("`n")
    Assert-True 'a different value replaces the line in place' ($changed -and $lines[$at] -ceq "$billable yes")
    Assert-True 'still once' (@($lines | Where-Object { $_ -like "$billable*" }).Count -eq 1)

    $changed = Set-P20CardLine -Path $card -Stamp $billable -Remove
    Assert-True '-Remove reports a change' ([bool]$changed)
    Assert-Equal '-Remove gives back the card byte for byte' $footer ([System.IO.File]::ReadAllText($card))
    Assert-True '-Remove on a card with no line reports no change' (-not (Set-P20CardLine -Path $card -Stamp $billable -Remove))

    $bare = New-ScratchCard 'b.prompt.md' "# Task 12: No footer`n`nBody.`n"
    [void](Set-P20CardLine -Path $bare -Stamp $billable -Value 'no')
    Assert-Equal 'with no Created line it is appended after one blank line' "# Task 12: No footer`n`nBody.`n`n$billable no`n" ([System.IO.File]::ReadAllText($bare))

    Write-Host ""
    Write-Host "-- Set-P20CardLine: the card keeps its own bytes ------" -ForegroundColor Cyan

    $crlf = New-ScratchCard 'c.prompt.md' ($footer -replace "`n", "`r`n")
    [void](Set-P20CardLine -Path $crlf -Stamp $billable -Value 'no')
    $text = [System.IO.File]::ReadAllText($crlf)
    Assert-True 'a CRLF card gets a CRLF line' ($text.Contains("$billable no`r`n"))
    Assert-True 'and no bare LF anywhere' (($text -replace "`r`n", '') -notmatch "`n")
    $bytes = [System.IO.File]::ReadAllBytes($crlf)
    Assert-True 'no BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $lf = [System.IO.File]::ReadAllText($card)
    Assert-True 'an LF card stays LF' (-not $lf.Contains("`r"))

    Write-Host ""

    # -- Through the VERB ---------------------------------------------------------
    Write-Host "-- Billable, typed as a verb --------------------------" -ForegroundColor Cyan

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

    $out = Invoke-Verbs ("${prefix}NewPrompt -Now -Title 'Bench reading' -Type Spike -Id K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Now -Title 'Bench writing' -Type Task -Id Q4R9 | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Billable -Help; 'HELP-END'; " +
        "${prefix}Billable; 'BARE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Billable W3X7 -No; 'UNKNOWN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Billable bench -No; 'AMBIGUOUS-EXIT=' + `$LASTEXITCODE")
    $help = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the verb with the registered prefix' ($help -match [regex]::Escape("${prefix}Billable <id|file> -No")) $help
    Assert-True 'a bare call states the reason' ($out -match 'no card given\.') $out
    Assert-True 'a bare call exits 2 (a stated refusal)' ($out -match 'BARE-EXIT=2') $out
    Assert-True 'an id nobody has is refused, not guessed at' ($out -match "No card with id 'W3X7'" -and $out -match 'UNKNOWN-EXIT=2') $out
    Assert-True 'a name that matches two cards is refused, and both are named' ($out -match "'bench' matches 2 cards" -and $out -match 'AMBIGUOUS-EXIT=2' -and $out -match 'Spike-K7M2-' -and $out -match 'TaskQ4R9-') $out
    $spike = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'the card exists to be marked' 1 $spike.Count
    $original = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'and no refusal wrote anything' ($original -notmatch [regex]::Escape($billable))

    $out = Invoke-Verbs "${prefix}Billable k7m2 -No; 'NO-EXIT=' + `$LASTEXITCODE; ${prefix}Billable K7M2 -No; 'AGAIN-EXIT=' + `$LASTEXITCODE"
    Assert-True "'Billable k7m2 -No' exits 0, the id typed in any case" ($out -match 'NO-EXIT=0') $out
    Assert-True 'and says what it means for Daily' ($out -match 'K7M2 is not billable -- it stays off Daily') $out
    $marked = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'the card carries the line, above Created' ($marked -match ('(?m)^' + [regex]::Escape($billable) + ' no\n' + [regex]::Escape($created)))
    Assert-True 'the card it CREATED is still LF' (-not $marked.Contains("`r"))
    Assert-True 'a second -No exits 0 and writes nothing' ($out -match 'AGAIN-EXIT=0' -and $out -match 'already says it is not billable') $out
    $other = Find-Card 'TaskQ4R9-*.prompt.md' 'current'
    Assert-True 'the other card was not touched' ([System.IO.File]::ReadAllText($other[0].FullName) -notmatch [regex]::Escape($billable))

    $out = Invoke-Verbs "${prefix}Billable K7M2; 'YES-EXIT=' + `$LASTEXITCODE; ${prefix}Billable K7M2; 'YES2-EXIT=' + `$LASTEXITCODE"
    Assert-True "'Billable K7M2' exits 0" ($out -match 'YES-EXIT=0' -and $out -match 'K7M2 is billable again') $out
    Assert-Equal 'and the card is byte for byte what it was' $original ([System.IO.File]::ReadAllText($spike[0].FullName))
    Assert-True 'a card that is already billable is told so, exit 0' ($out -match 'YES2-EXIT=0' -and $out -match 'already billable') $out

    Write-Host ""
    Write-Host "-- A closed card can still be taken off the week ------" -ForegroundColor Cyan

    $out = Invoke-Verbs "${prefix}Archive Q4R9 | Out-Null; ${prefix}Billable Q4R9 -No; 'ARCHIVED-EXIT=' + `$LASTEXITCODE"
    $archived = Find-Card 'TaskQ4R9-*.prompt.md' 'archive'
    Assert-Equal 'the card is in archive/' 1 $archived.Count
    Assert-True "'Billable Q4R9 -No' finds it there and exits 0" ($out -match 'ARCHIVED-EXIT=0') $out
    $closedText = [System.IO.File]::ReadAllText($archived[0].FullName)
    Assert-True 'the line sits above Created, and Closed is still last' ($closedText -match ('(?s)' + [regex]::Escape($billable) + ' no\n' + [regex]::Escape($created) + '[^\n]*\n' + [regex]::Escape($consts.stamps.closed) + '[^\n]*\n?$')) $closedText.Substring([Math]::Max(0, $closedText.Length - 160))
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
