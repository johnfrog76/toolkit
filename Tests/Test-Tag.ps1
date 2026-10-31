<#
.SYNOPSIS
    Tests for the Tag verb -- the write side of a card's Tags: line.
.DESCRIPTION
    Set-P20CardLine itself is held by Test-Billable.ps1; what is specific to Tag is tested
    AS A VERB -- the real module imported in a fresh shell, typed the way a person types it:

      - tags are added after the ones already there, joined by a comma and a space, in the
        line's own place (under Priority:, in ## Work Item Info); one already there, in any
        case, is not added twice; several arguments or one with commas
      - -Remove takes tags off, in any case; the last one off leaves the template's
        `Tags: (None)`
      - a call that changes no tag exits 0, says "nothing written", and writes nothing
      - a card with no Tags: line gets one under Priority:, else under ## Work Item Info;
        a CRLF card stays CRLF
      - found in current/ AND backlog/, never pulled into play; an archived card not found
      - every refusal exits 2 and writes nothing
      - the one reader (Get-P20CardTags) reads back what was written

    Run:  pwsh -File Tests/Test-Tag.ps1
    Or:   {cliPrefix}TestToolkit -Tag
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

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
. (Join-Path $pkgRoot 'Scripts/Get-PromptFileStatus.ps1')
$consts = Get-P20Consts
$tagsToken = [string]$consts.tokens.tags

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-tag-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

try {
    Write-Host "-- Tag, typed as a verb --------------------------------" -ForegroundColor Cyan

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
    function Get-TagLines {
        param([string]$Text)
        return @(($Text -replace "`r`n", "`n").Split("`n") | Where-Object { $_.StartsWith($tagsToken) })
    }

    $out = Invoke-Verbs ("${prefix}NewPrompt -Now -Title 'Bench reading' -Type Spike -Id K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Bench writing' -Type Task -Id Q4R9 | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Tag -Help; 'HELP-END'; " +
        "${prefix}Tag; 'BARE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Tag K7M2; 'NOTAG-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Tag K7M2 ' , '; 'EMPTY-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Tag K7M2 '(None)'; 'PLACEHOLDER-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Tag W3X7 docs; 'UNKNOWN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Tag bench docs; 'AMBIGUOUS-EXIT=' + `$LASTEXITCODE")
    $usage = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the verb with the registered prefix' ($usage -match [regex]::Escape("${prefix}Tag <id|file> <tag>[,<tag>]")) $usage
    Assert-True '-Help names -Remove too' ($usage -match [regex]::Escape("${prefix}Tag <id|file> <tag>[,<tag>] -Remove")) $usage
    Assert-True 'a bare call states the reason, exit 2' ($out -match 'no card given\.' -and $out -match 'BARE-EXIT=2') $out
    Assert-True 'a card with no tag is refused, exit 2' ($out -match 'no tag given\.' -and $out -match 'NOTAG-EXIT=2') $out
    Assert-True 'commas and spaces alone are no tag, exit 2' ($out -match 'EMPTY-EXIT=2') $out
    Assert-True 'a placeholder is not a tag, exit 2' ($out -match "'\(None\)' is not a tag" -and $out -match 'PLACEHOLDER-EXIT=2') $out
    Assert-True 'an id nobody has is refused, not guessed at' ($out -match "No card with id 'W3X7'" -and $out -match 'UNKNOWN-EXIT=2') $out
    Assert-True 'a name that matches two cards is refused, and both are named' ($out -match "'bench' matches 2 cards" -and $out -match 'AMBIGUOUS-EXIT=2') $out

    $spike = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'the card exists to be tagged' 1 $spike.Count
    $original = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'it carries the template''s Tags: (None)' (@(Get-TagLines $original).Count -eq 1 -and @(Get-TagLines $original)[0] -ceq "$tagsToken (None)") $original
    Assert-Equal 'and no refusal changed it' $original ([System.IO.File]::ReadAllText($spike[0].FullName))

    Write-Host ""
    Write-Host "-- Tags are added in place, once each -----------------" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Tag k7m2 docs,sev3; 'ADD-EXIT=' + `$LASTEXITCODE")
    $tagged = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True "'Tag k7m2 docs,sev3' exits 0 and says what it tagged" ($out -match 'ADD-EXIT=0' -and $out -match [regex]::Escape('K7M2 is tagged docs, sev3')) $out
    Assert-True 'the line reads docs, sev3 -- replaced in place, still one line' (@(Get-TagLines $tagged).Count -eq 1 -and @(Get-TagLines $tagged)[0] -ceq "$tagsToken docs, sev3") $tagged
    Assert-Equal 'nothing but that line moved' ($original -replace [regex]::Escape("$tagsToken (None)"), "$tagsToken docs, sev3") $tagged
    Assert-Equal 'the one reader reads them back' 'docs|sev3' ((@(Get-P20CardTags $tagged)) -join '|')
    Assert-True 'the card it CREATED is still LF' (-not $tagged.Contains("`r"))

    $out = Invoke-Verbs ("${prefix}Tag K7M2 Docs; 'SAME-EXIT=' + `$LASTEXITCODE")
    Assert-True 'a tag it already carries, in another case, exits 0 and writes nothing' ($out -match 'SAME-EXIT=0' -and $out -match 'already carries Docs -- nothing written') $out
    Assert-Equal 'byte for byte' $tagged ([System.IO.File]::ReadAllText($spike[0].FullName))

    $out = Invoke-Verbs ("${prefix}Tag K7M2 ui docs; 'MANY-EXIT=' + `$LASTEXITCODE")
    $more = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'several arguments: the new one is appended, the old one not twice' ($out -match 'MANY-EXIT=0' -and @(Get-TagLines $more)[0] -ceq "$tagsToken docs, sev3, ui") $more

    Write-Host ""
    Write-Host "-- -Remove takes tags off; the last leaves (None) -----" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Tag K7M2 'SEV3,ui' -Remove; 'REMOVE-EXIT=' + `$LASTEXITCODE")
    $less = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True "'-Remove' in any case takes them off and says so" ($out -match 'REMOVE-EXIT=0' -and $out -match 'K7M2 is no longer tagged sev3, ui' -and @(Get-TagLines $less)[0] -ceq "$tagsToken docs") $less
    $out = Invoke-Verbs ("${prefix}Tag K7M2 nope -Remove; 'NOPE-EXIT=' + `$LASTEXITCODE")
    Assert-True 'removing a tag it does not carry exits 0 and writes nothing' ($out -match 'NOPE-EXIT=0' -and $out -match 'carries none of nope -- nothing written') $out
    Assert-Equal 'byte for byte' $less ([System.IO.File]::ReadAllText($spike[0].FullName))
    $out = Invoke-Verbs ("${prefix}Tag K7M2 docs -Remove; 'LAST-EXIT=' + `$LASTEXITCODE")
    $none = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'the last one off leaves the template''s placeholder' ($out -match 'LAST-EXIT=0' -and @(Get-TagLines $none)[0] -ceq "$tagsToken (None)" -and @(Get-P20CardTags $none).Count -eq 0) $none
    Assert-Equal 'which is the card it was born as' $original $none

    Write-Host ""
    Write-Host "-- A card with no Tags: line gets one where it belongs " -ForegroundColor Cyan

    # A CRLF card with no Tags: line: the line goes under Priority:, and the card
    # keeps its own terminator (Set-P20CardLine, through Write-CardText).
    $noLine = ((($original -replace "(?m)^Tags:[^\n]*\n", '') -replace "`r`n", "`n") -replace "`n", "`r`n")
    [System.IO.File]::WriteAllText($spike[0].FullName, $noLine)
    Assert-True 'the scratch card really has no Tags: line, and is CRLF' (@(Get-TagLines $noLine).Count -eq 0 -and $noLine.Contains("`r`n"))
    $out = Invoke-Verbs ("${prefix}Tag K7M2 spec; 'INSERT-EXIT=' + `$LASTEXITCODE")
    $inserted = [System.IO.File]::ReadAllText($spike[0].FullName)
    $lines = $inserted -split "`r`n"
    $pri = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l.StartsWith('Priority:') })
    Assert-True 'the new line sits directly under Priority:' ($out -match 'INSERT-EXIT=0' -and $pri -ge 0 -and $lines[$pri + 1] -ceq "$tagsToken spec") $inserted
    Assert-True 'and the card is still CRLF, with no bare LF' (($inserted -replace "`r`n", '') -notmatch "`n") ''
    $noPriority = (($noLine -replace "(?m)^Priority:[^\r\n]*\r\n", ''))
    [System.IO.File]::WriteAllText($spike[0].FullName, $noPriority)
    $out = Invoke-Verbs ("${prefix}Tag K7M2 spec | Out-Null; 'X'")
    $lines = ([System.IO.File]::ReadAllText($spike[0].FullName)) -split "`r`n"
    $wii = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^##\s+Work Item Info' })
    Assert-True 'with no Priority: line it sits under ## Work Item Info' ($wii -ge 0 -and $lines[$wii + 1] -ceq "$tagsToken spec") ($lines -join '|')

    Write-Host ""
    Write-Host "-- A backlog card is tagged WHERE it sits -------------" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Tag Q4R9 sonnet; 'BACKLOG-EXIT=' + `$LASTEXITCODE")
    $backlogCard = Find-Card 'TaskQ4R9-*.prompt.md' $consts.folders.backlog
    Assert-True "'Tag Q4R9 sonnet' exits 0 and the card stays in backlog/" ($out -match 'BACKLOG-EXIT=0' -and $backlogCard.Count -eq 1 -and (Find-Card 'TaskQ4R9-*.prompt.md' 'current').Count -eq 0) $out
    Assert-True 'the backlog card carries the tag' ((@(Get-P20CardTags ([System.IO.File]::ReadAllText($backlogCard[0].FullName)))) -join '|' -ceq 'sonnet')

    $out = Invoke-Verbs ("${prefix}Archive Q4R9 | Out-Null; ${prefix}Tag Q4R9 opus; 'ARCHIVED-EXIT=' + `$LASTEXITCODE")
    Assert-True "an archived card is not found, exit 2" ($out -match "No card with id 'Q4R9' in current/ or backlog/" -and $out -match 'ARCHIVED-EXIT=2') $out
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
