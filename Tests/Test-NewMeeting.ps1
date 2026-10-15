<#
.SYNOPSIS
    Tests for New-Meeting.ps1 -- scaffolding a session file, the shape it
    writes, what it refuses, and the wrapper that fronts it.
.DESCRIPTION
    Each case runs the script in a sandbox: a temp directory holding a copy of
    the script under Scripts/ and a copy of the shipped template under
    templates/, with PROMPTS_ROOT pointing at a second temp directory that
    stands in for the hub. The script derives its own root from its location, so
    the sandbox IS its package -- and the hub it writes into is not this repo.

    The point of the shape assertions: the template, the agent's POST /manager
    and docs/hub/manager.md all describe one file. A change to any of them that
    is not a change to all of them fails here.

    Run:  pwsh -File Tests/Test-NewMeeting.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$newScript = Join-Path $pkgRoot 'Scripts/New-Meeting.ps1'
$templateFile = Join-Path $pkgRoot 'templates/ManagerSession.template.md'
$commandFile = Join-Path $pkgRoot 'Config/communication.commands.ps1'
$guardFile  = Join-Path $pkgRoot 'Scripts/Invoke-CommandScript.ps1'

# -- Harness --------------------------------------------------------------------

$script:passed = 0
$script:failed = 0
$script:errors = @()

# Byte-level writes for a card or session the verb under test reads or has just
# written. A host cmdlet (Set-Content / Add-Content -Encoding UTF8) opens the file
# with its own encoding detection and, on Windows PowerShell 5.1, throws "Stream was
# not readable" when something still holds it; the tool itself writes cards as
# BOM-less UTF-8 (AGENTS.md, "One byte contract for a card").
function Write-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
}
function Add-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::AppendAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg = "$msg -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# Plain substring, not -like: a needle containing [ or ] is a wildcard character
# class to -like, and "[-Date YYYY-MM-DD]" is a perfectly ordinary thing to look
# for in a usage line.
function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName ($Haystack.Contains($Needle)) "'$Needle' not in output"
}

# -- Sandbox --------------------------------------------------------------------

function New-MeetingSandbox {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-meet-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path (Join-Path $root 'pkg/Scripts') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $root 'pkg/templates') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $root 'hub') -ItemType Directory -Force | Out-Null
    Copy-Item $newScript (Join-Path $root 'pkg/Scripts/New-Meeting.ps1')
    # The hub-root folder resolver the script dot-sources: manager/ is named by
    # the hub (hub.json "folders"), and this sandbox's hub declares nothing, so
    # the default name is what it must come back with.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1') (Join-Path $root 'pkg/Scripts/Resolve-HubConfig.ps1')
    # Resolve-HubConfig dot-sources the config-parse warning writer beside it.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Write-ConfigParseWarning.ps1') (Join-Path $root 'pkg/Scripts/Write-ConfigParseWarning.ps1')
    # The one writer: a scaffolded session gets the same bytes a card does.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1') (Join-Path $root 'pkg/Scripts/Write-CardText.ps1')
    Copy-Item $templateFile (Join-Path $root 'pkg/templates/ManagerSession.template.md')
    # The record's name rule is the contract's: the script reads it.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1') (Join-Path $root 'pkg/Scripts/Get-Consts.ps1')
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $root 'pkg/consts.json')
    # The "## Carried from" check it runs on the session after the one it creates.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-CarriedFrom.ps1') (Join-Path $root 'pkg/Scripts/Resolve-CarriedFrom.ps1')
    return $root
}

function Remove-MeetingSandbox {
    param([string]$Root)
    if ($Root -and (Test-Path $Root)) { Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-NewMeeting {
    param([string]$Root, [string[]]$Arguments)

    $script = Join-Path $Root 'pkg/Scripts/New-Meeting.ps1'
    $hub = Join-Path $Root 'hub'
    $quoted = ($Arguments | ForEach-Object {
            if ($_ -like '-*') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
        }) -join ' '
    # `exit $LASTEXITCODE` on the end: under -Command, PowerShell reports its own
    # 0/1 for the block rather than the code the invoked SCRIPT left behind, so a
    # stated refusal (exit 2, AGENTS.md) arrived here as 1 and could not be told
    # from any other failure.
    $command = "`$env:PROMPTS_ROOT = '$hub'; & '$script' $quoted; exit `$LASTEXITCODE"
    # Windows PowerShell 5.1 turns a redirected native stderr into a throw under
    # 'Stop' before $LASTEXITCODE can be read; a refusal's text is the subject here.
    $ErrorActionPreference = 'Continue'
    $output = pwsh -NoProfile -Command $command 2>&1 | Out-String
    return @{ Output = $output; ExitCode = $LASTEXITCODE }
}

# Every read of a written session goes through here, and every read normalises
# line endings, because a multi-line needle otherwise asserts a fact about the
# CHECKOUT rather than about the file.
#
# It stays even though a CREATED session is now LF on every host: the reads
# below also run over sessions this suite hand-writes, and a session EDITED on
# Windows is CRLF whatever this repo checks out. The parser matches \r?\n and
# must keep doing so; the needles must not depend on it.
#
# What changed: `templates/ManagerSession.template.md` is
# `text=auto`, so a Windows clone with core.autocrlf=true has it CRLF, and
# New-Meeting used to read it -Raw and write it back byte for byte -- a CRLF
# session on Windows, an LF one on macOS, for the same verb into the same hub.
# The writer now normalises on CREATE (Write-CardText -New), so the template's
# checkout no longer decides the session's bytes.
#
function ConvertTo-Lf {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n")
}

function Test-HasBomAt {
    param([string]$Path)
    $b = [System.IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

function Get-SessionText {
    param([string]$Root, [string]$Name)
    $path = Join-Path (Join-Path (Join-Path $Root 'hub') 'manager/current') $Name
    if (-not (Test-Path $path)) { return '' }
    return (ConvertTo-Lf (Get-Content $path -Raw))
}

Write-Host ""
Write-Host "  NewMeeting -- scaffolding one session" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- Help -----------------------------------------------------------------------

Write-Host "-- Help --------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Help')
    Assert-Contains "-Help names the command" $result.Output 'NewMeeting'
    Assert-Contains "-Help shows usage" $result.Output '[-Date YYYY-MM-DD]'
    Assert-Contains "-Help says it never overwrites" $result.Output 'Never overwrites'
    Assert-True "-Help exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
    Assert-True "-Help writes nothing" (-not (Test-Path (Join-Path $sandbox 'hub/manager')))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- The file it writes -----------------------------------------------------------

Write-Host ""
Write-Host "-- The file it writes ------------------------------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    Assert-Contains "reports the path it wrote" $result.Output 'manager/current/2026-06-12.md'
    Assert-True "exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"

    $text = Get-SessionText $sandbox '2026-06-12.md'
    Assert-True "the file exists" ($text -ne '')
    Assert-Contains "titled with the date" $text '# 2026-06-12'
    # One shape, and this is the list of what is in it. The agent's writer and
    # docs/hub/manager.md carry the same eight headings.
    foreach ($heading in @('## Stage', '## Carried from', '## Since Last Session',
            '## Unresolved / Forward', '## Agenda', '## Prep', '## Retro', '## Sent')) {
        Assert-Contains "the documented shape carries '$heading'" $text $heading
    }
    Assert-Contains "a new session starts at the draft stage" $text "## Stage`ndraft"
    Assert-Contains "no prior session reads as (none)" $text '## Carried from (none)'
    Assert-True "the template's placeholders are substituted" (-not ($text -like '*{{DATE}}*'))

    # manager/ is a sibling of the org folders. A session written inside one
    # would vanish from view the next time the active Space changed.
    Assert-True "manager/ sits at the hub root, not inside an org folder" `
        (Test-Path (Join-Path $sandbox 'hub/manager/current'))
    Assert-True "archive/ is created alongside it" `
        (Test-Path (Join-Path $sandbox 'hub/manager/archive'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- The bytes a session is written with ---------------------------------------
# A session is a file in the user's own store, so it gets the card contract:
# UTF-8 with NO BOM, through the one writer. It used to be scaffolded with
# UTF8Encoding($true) -- BOM on -- which MeetingAgenda -Close then stripped on
# its way past, so a session's first three bytes depended on which verb touched
# it last and a close read as a whole-file diff on a hub with storeSync: git.
#

Write-Host ""
Write-Host "-- The bytes a scaffolded session is written with ---------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $null = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    $sessionPath = Join-Path $sandbox 'hub/manager/current/2026-06-12.md'
    Assert-True "the session exists" (Test-Path $sessionPath)

    $bytes = [System.IO.File]::ReadAllBytes($sessionPath)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True "no BOM on a scaffolded session" (-not $hasBom) `
        "first bytes: $([string]::Join(' ', ($bytes[0..2] | ForEach-Object { '0x{0:X2}' -f $_ })))"
    Assert-True "the first byte is the '#' of the title" ($bytes[0] -eq 0x23) ("0x{0:X2}" -f $bytes[0])

    # An LF template makes an LF session, which is the contract's other half.
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    Assert-True "an LF template gives an LF session" (-not $text.Contains("`r`n")) 'the session came out CRLF from an LF template'

    # The writer is shared, not copied: one implementation of the contract.
    $newMeetingSource = Get-Content (Join-Path $pkgRoot 'Scripts/New-Meeting.ps1') -Raw
    Assert-True "New-Meeting writes through Write-CardText" ($newMeetingSource -match 'Write-CardText -Path')
    Assert-True "New-Meeting has no encoding of its own" ($newMeetingSource -notmatch 'UTF8Encoding\(\$true\)') 'a second BOM writer is still in New-Meeting.ps1'
    # -New is the create half of the contract, and it is a switch on the shared
    # writer rather than a -replace here, so no create path can forget it and
    # no two of them can normalise differently.
    Assert-True "New-Meeting creates with -New" ($newMeetingSource -match 'Write-CardText -Path \$filePath -Content \$content -New')
    Assert-True "and does not normalise line endings itself" ($newMeetingSource -notmatch '\$content = \$content -replace "`r`n"') 'a second normaliser is in New-Meeting.ps1'
    Assert-True "the writer ships as its own file" (Test-Path (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- A CRLF checkout ----------------------------------------------------------------

# The Windows default clone, reproduced on any host: `* text=auto` plus
# core.autocrlf=true gives the template CRLF. This is the case the suite was
# blind to until Windows ran it -- and what it pins is the CONTRACT, not the
# copy: a file the tool CREATES is LF, so a CRLF template must still give an LF
# session. It once pinned "the session keeps the template's line endings"
# which was pinning the bug.

Write-Host ""
Write-Host "-- A CRLF template ---------------------------------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    # Bytes in, bytes out: the template carries a BOM, and a round trip through
    # ReadAllText/WriteAllText would drop it and make this about the BOM.
    $tpl = Join-Path $sandbox 'pkg/templates/ManagerSession.template.md'
    $tplText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($tpl))
    $crlf = ($tplText -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllBytes($tpl, [System.Text.Encoding]::UTF8.GetBytes($crlf))

    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    Assert-True "a CRLF template still writes a session" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"

    $rawPath = Join-Path $sandbox 'hub/manager/current/2026-06-12.md'
    $raw = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($rawPath))
    Assert-True "a CRLF template still gives an LF session" (-not $raw.Contains("`r`n")) `
        'the session came out CRLF -- a CREATED file is LF, whatever the template checked out as'
    Assert-True "and the session still has its lines" (([regex]::Matches($raw, "`n")).Count -gt 5) $raw
    Assert-True "and no BOM came back with the normalisation" `
        (-not (Test-HasBomAt $rawPath)) 'a BOM was written by the create path'

    $text = Get-SessionText $sandbox '2026-06-12.md'
    Assert-Contains "the draft stage reads the same from a CRLF session" $text "## Stage`ndraft"
    Assert-Contains "carry-forward reads the same from a CRLF session" $text '## Carried from (none)'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- The prior session ------------------------------------------------------------

Write-Host ""
Write-Host "-- Carry-forward -----------------------------------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $null = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    $null = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-26')
    $text = Get-SessionText $sandbox '2026-06-26.md'
    Assert-Contains "the prior session is named in the heading" $text '## Carried from 2026-06-12'

    # A later date already on disk is not the prior one, and a session created
    # out of order must not claim it.
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-19')
    $text = Get-SessionText $sandbox '2026-06-19.md'
    Assert-Contains "out-of-order creation still finds the session before it" $text '## Carried from 2026-06-12'
    # ... and the later session's heading now names the wrong one. That is SAID,
    # and the later session is left as it was (docs/hub/manager.md, "Which
    # session a record carries from").
    Assert-Contains "out-of-order creation names the later session it sits in front of" $result.Output '2026-06-26.md -- Carried from 2026-06-12, but the latest earlier session in this series is 2026-06-19'
    Assert-Contains "and the later session's heading is not rewritten" (Get-SessionText $sandbox '2026-06-26.md') '## Carried from 2026-06-12'

    # A stray file in the folder is not a session and must not be carried from.
    Write-FixtureText (Join-Path $sandbox 'hub/manager/current/notes.md') 'not a session'
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-07-10')
    Assert-True "a session created after the last one says nothing about a heading" (-not $result.Output.Contains('Check:')) $result.Output
    $text = Get-SessionText $sandbox '2026-07-10.md'
    Assert-Contains "a non-dated file is not a session" $text '## Carried from 2026-06-26'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- What it refuses ---------------------------------------------------------------

Write-Host ""
Write-Host "-- What it refuses ---------------------------------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', 'the twelfth')
    Assert-Contains "a date that is not a date is refused" $result.Output 'Invalid date'
    Assert-True "nothing is written for a bad date" (-not (Test-Path (Join-Path $sandbox 'hub/manager/current/the twelfth.md')))

    # The session file accumulates a whole meeting's record. Re-scaffolding it
    # would throw that away, so this path reports and stops.
    $null = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    $path = Join-Path $sandbox 'hub/manager/current/2026-06-12.md'
    Add-FixtureText $path "`nHAND WRITTEN"
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-06-12')
    Assert-Contains "an existing session reports rather than overwriting" $result.Output 'already exists'
    Assert-Contains "the existing content survives" (ConvertTo-Lf (Get-Content $path -Raw)) 'HAND WRITTEN'
    Assert-True "an existing session is not an error" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- A session that has already been CLOSED ----------------------------------------
# The session date is the file's identity (docs/hub/manager.md), so "already
# exists" means either folder. Checking only current/ scaffolded a blank session
# beside a real, closed one in archive/: the 1:1s page then listed an open meeting
# that had already been held, MeetingAgenda -Close could protect the archived copy
# but not remove the duplicate, and nothing but a hand delete resolved it.
#

Write-Host ""
Write-Host "-- A session already closed into archive/ ----------------" -ForegroundColor Cyan

$sandbox = New-MeetingSandbox
try {
    $archiveDir = Join-Path $sandbox 'hub/manager/archive'
    New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
    $closed = Join-Path $archiveDir '2026-09-01.md'
    Write-FixtureText $closed "# 1:1 -- 2026-09-01`n`n**Closed:** 2026-09-02`nREAL RECORD"

    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-09-01')
    Assert-Contains "an archived session is refused, not recreated" $result.Output 'already closed'
    Assert-Contains "the refusal names the archived path" $result.Output 'archive/2026-09-01.md'
    Assert-True "and it is an error, not a report" ($result.ExitCode -eq 2) "exit $($result.ExitCode)"
    Assert-True "no duplicate is scaffolded in current/" `
        (-not (Test-Path (Join-Path $sandbox 'hub/manager/current/2026-09-01.md')))
    Assert-Contains "the closed session is untouched" (ConvertTo-Lf (Get-Content $closed -Raw)) 'REAL RECORD'

    # A date the hub has never seen still works, from the same sandbox.
    $result = Invoke-NewMeeting -Root $sandbox -Arguments @('-Date', '2026-09-08')
    Assert-True "a date with no session anywhere is still created" `
        (Test-Path (Join-Path $sandbox 'hub/manager/current/2026-09-08.md')) $result.Output
    Assert-True "and exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# An unconfigured hub is reported, not guessed at.
$sandbox = New-MeetingSandbox
try {
    $script = Join-Path $sandbox 'pkg/Scripts/New-Meeting.ps1'
    $output = pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = ''; & '$script'" 2>&1 | Out-String
    Assert-Contains "an unconfigured hub is reported in words" $output 'Hub not found'
    Assert-Contains "and names the file the path came from" $output 'config.local.json'
    Assert-True "and does not write a raw error record" ($output -notmatch 'Write-Error') $output

    # A hub on a drive that is not mapped is the Windows version of the same
    # thing, and the one that used to print stack traces. A path under a
    # directory that does not exist reaches the identical guard on any host.
    #
    $ghost = Join-Path $sandbox 'no-such-folder/hub'
    $output = pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$ghost'; & '$script'" 2>&1 | Out-String
    Assert-Contains "a hub that is not there says so" $output 'Hub not found'
    Assert-True "and shows no Join-Path stack trace" ($output -notmatch 'Cannot find drive|Cannot bind argument') $output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-MeetingSandbox $sandbox }

# -- The wrapper --------------------------------------------------------------------

Write-Host ""
Write-Host "-- The wrapper -------------------------------------------" -ForegroundColor Cyan

$stubs = @"
function global:Show-CommandHelp { param([string]`$CommandName) Write-Host "HELP:`$CommandName" }
function global:Write-ToolkitLog { param(`$Type, `$Source, `$Detail) Write-Host "LOG:`$Type/`$Source" }
function global:Write-CliError { param(`$Message, `$Hint) Write-Host "ERR:`$Message" }
function global:Get-CliPrefix { return 'tk' }
# The refusal contract's guard, the real one -- the loader dot-sources it too.
. '$guardFile'
. '$commandFile'
"@

$result = pwsh -NoProfile -Command "$stubs; if (Get-Command New-P20Meeting -ErrorAction SilentlyContinue) { 'DEFINED' }" 2>&1 | Out-String
Assert-Contains "dot-sourcing the command file defines New-P20Meeting" $result 'DEFINED'

$result = pwsh -NoProfile -Command "$stubs; New-P20Meeting -Help" 2>&1 | Out-String
Assert-Contains "-Help renders from the shared help table" $result 'HELP:NewMeeting'

$result = pwsh -NoProfile -Command "$stubs; (Get-Command New-P20Meeting).Parameters.Keys -join ','" 2>&1 | Out-String
Assert-Contains "the wrapper takes -Date" $result 'Date'

# -- Summary -----------------------------------------------------------------------

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
