<#
.SYNOPSIS
    Tests for Get-MeetingAgenda.ps1 -- the stage lifecycle, what each stage
    writes, the status report, and the wrapper's positional guard.
.DESCRIPTION
    Same sandbox arrangement as Test-NewMeeting: a copy of the script and the
    shipped template in a temp package, a temp hub behind PROMPTS_ROOT. Stage is
    read back out of the file rather than out of the command's own output,
    because the file IS the state -- nothing stores it anywhere else.

    Run:  pwsh -File Tests/Test-MeetingAgenda.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$agendaScript = Join-Path $pkgRoot 'Scripts/Get-MeetingAgenda.ps1'
$templateFile = Join-Path $pkgRoot 'templates/ManagerSession.template.md'
$agentPrompt = Join-Path $pkgRoot 'agentic/manager1on1.prompt.md'
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
# class to -like, and a usage line is full of both.
function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName ($Haystack.Contains($Needle)) "'$Needle' not in output"
}

function Assert-NotContains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName (-not $Haystack.Contains($Needle)) "'$Needle' was in output"
}

# -- Sandbox --------------------------------------------------------------------

function New-AgendaSandbox {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-agenda-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path (Join-Path $root 'pkg/Scripts') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $root 'pkg/templates') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $root 'hub') -ItemType Directory -Force | Out-Null
    Copy-Item $agendaScript (Join-Path $root 'pkg/Scripts/Get-MeetingAgenda.ps1')
    # The hub-root folder resolver the script dot-sources: manager/ is named by
    # the hub (hub.json "folders"), and this sandbox's hub declares nothing, so
    # the default name is what it must come back with.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1') (Join-Path $root 'pkg/Scripts/Resolve-HubConfig.ps1')
    # Resolve-HubConfig dot-sources the config-parse warning writer beside it.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Write-ConfigParseWarning.ps1') (Join-Path $root 'pkg/Scripts/Write-ConfigParseWarning.ps1')
    # The script resolves the agentic prompt it names through this sibling.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-AgenticPrompt.ps1') (Join-Path $root 'pkg/Scripts/Resolve-AgenticPrompt.ps1')
    # -Close dot-sources this sibling for the "**Closed:**" stamp, so the sandbox
    # needs it beside the script the way the real Scripts/ folder has it.
    $stampScript = Join-Path $pkgRoot 'Scripts/Add-ClosedStamp.ps1'
    if (Test-Path $stampScript) { Copy-Item $stampScript (Join-Path $root 'pkg/Scripts/Add-ClosedStamp.ps1') }
    # The byte contract underneath the stamp, dot-sourced by both the stamp and
    # this script's own writers.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1') (Join-Path $root 'pkg/Scripts/Write-CardText.ps1')
    # consts.json and its reader: the stamp's literal is a cross-half contract
    # and is read from the file, not typed. A sandbox without it is a package
    # without its contract, and the stamp cannot be written at all.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1') (Join-Path $root 'pkg/Scripts/Get-Consts.ps1')
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $root 'pkg/consts.json')
    # The "## Carried from" check the status, the quick menu and -Plan report.
    Copy-Item (Join-Path $pkgRoot 'Scripts/Resolve-CarriedFrom.ps1') (Join-Path $root 'pkg/Scripts/Resolve-CarriedFrom.ps1')
    Copy-Item $templateFile (Join-Path $root 'pkg/templates/ManagerSession.template.md')
    return $root
}

function Remove-AgendaSandbox {
    param([string]$Root)
    if ($Root -and (Test-Path $Root)) { Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-Agenda {
    param([string]$Root, [string[]]$Arguments)

    $script = Join-Path $Root 'pkg/Scripts/Get-MeetingAgenda.ps1'
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

function Get-SessionPath {
    param([string]$Root, [string]$Date)
    return (Join-Path (Join-Path (Join-Path $Root 'hub') 'manager/current') "$Date.md")
}

# Same rule as Test-NewMeeting: a session read from disk is normalised before
# anything is asserted about its text. A session this suite CREATES is LF on
# every host (Write-CardText -New), but a session EDITED on
# Windows is CRLF whatever this repo checks out, and the cases below hand-write
# CRLF sessions on purpose. A needle spanning a line break would otherwise be
# asserting a fact about the host rather than about the file.
function Test-HasBom {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function ConvertTo-Lf {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n")
}

function Get-SessionText {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    return (ConvertTo-Lf (Get-Content $Path -Raw))
}

# Stage is read from the file, because the file is where it lives.
function Get-Stage {
    param([string]$Root, [string]$Date)
    $path = Get-SessionPath $Root $Date
    if (-not (Test-Path $path)) { return '' }
    $inStage = $false
    foreach ($line in (Get-Content $path)) {
        if ($inStage) { return $line.Trim() }
        if ($line.Trim() -eq '## Stage') { $inStage = $true }
    }
    return ''
}

Write-Host ""
Write-Host "  MeetingAgenda -- the session lifecycle" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- Help -----------------------------------------------------------------------

Write-Host "-- Help --------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Help')
    Assert-Contains "-Help names the command" $result.Output 'MeetingAgenda'
    foreach ($stage in @('Plan', 'Prep', 'Retro')) {
        Assert-Contains "-Help documents -$stage" $result.Output "-$stage"
    }
    Assert-Contains "-Help names the agent prompt that ships with the package" $result.Output 'agentic/manager1on1.prompt.md'
    Assert-True "-Help exits 0" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
    Assert-True "-Help writes nothing" (-not (Test-Path (Join-Path $sandbox 'hub/manager')))
    # The three per-stage prompt files this used to read out of the hub are
    # retired. Naming one again would send a reader looking for a file that is
    # not there.
    foreach ($retired in @('pre-1on1.md', 'reset-check.md', 'post-1on1.md')) {
        Assert-NotContains "-Help does not name the retired $retired" $result.Output $retired
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- Status ---------------------------------------------------------------------

Write-Host ""
Write-Host "-- Status ------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12')
    Assert-Contains "no session says so" $result.Output 'No session for 2026-06-12'
    Assert-Contains "no session points at the stage that creates one" $result.Output '-Plan'
    Assert-True "reporting on nothing is not an error" ($result.ExitCode -eq 0) "exit $($result.ExitCode)"
    Assert-True "reporting on nothing writes nothing" (-not (Test-Path (Get-SessionPath $sandbox '2026-06-12')))

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12')
    Assert-Contains "status shows the stage" $result.Output '[draft]'
    Assert-Contains "status shows the file" $result.Output 'manager/current/2026-06-12.md'
    Assert-Contains "status names the next stage" $result.Output 'Next:'
    Assert-Contains "after Plan the next stage is Prep" $result.Output 'Prep'

    # -Type IS the series (docs/hub/manager.md, "Where it lives"): a second
    # recurring meeting with its own records and its own carry-forward. The 1:1's
    # records keep their bare date names; a series carries its name in front.
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'skip-level')
    Assert-Contains "a series with no record on that date says so -- the 1:1's record is not it" $result.Output 'No session for 2026-06-12'
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'skip-level', '-Plan')
    Assert-True "the series' record is named for it, beside the 1:1's for the same day" (Test-Path (Join-Path $sandbox 'hub/manager/current/skip-level-2026-06-12.md')) 'skip-level-2026-06-12.md missing'
    Assert-True "and the 1:1's record is untouched" (Test-Path (Get-SessionPath $sandbox '2026-06-12'))
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'skip-level')
    Assert-Contains "the series is reported" $result.Output 'Agenda (skip-level)'
    Assert-Contains "and its file" $result.Output 'manager/current/skip-level-2026-06-12.md'
    $text = Get-Content (Join-Path $sandbox 'hub/manager/current/skip-level-2026-06-12.md') -Raw
    Assert-Contains "the heading names the series" $text '# skip-level 2026-06-12'
    Assert-Contains "a first record in a series carries from none, not from the 1:1" $text '## Carried from (none)'

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Type', 'skip-level', '-Plan')
    $text2 = Get-Content (Join-Path $sandbox 'hub/manager/current/skip-level-2026-06-26.md') -Raw
    Assert-Contains "the second record in a series carries from the first IN THAT SERIES" $text2 '## Carried from 2026-06-12'
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Plan')
    $text3 = Get-Content (Get-SessionPath $sandbox '2026-06-26') -Raw
    Assert-Contains "and the 1:1 on the same day carries from the last 1:1, never from the series" $text3 '## Carried from 2026-06-12'

    # The quick menu: no date, no series -- every open record with its next command.
    $result = Invoke-Agenda -Root $sandbox -Arguments @()
    Assert-Contains "the quick menu lists the 1:1" $result.Output '1:1 - 2026-06-12'
    Assert-Contains "and the series, by name" $result.Output 'skip-level - 2026-06-12'
    Assert-Contains "each with the exact next command, series named" $result.Output 'MeetingAgenda -Type skip-level -Date 2026-06-12 -Prep'
    Assert-Contains "and the 1:1's without a -Type" $result.Output 'MeetingAgenda -Date 2026-06-12 -Prep'
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'Skip Level')
    Assert-Contains "a series name that is not a slug is refused" $result.Output 'is not a series name'
    Assert-True "and refuses with exit 2" ($result.ExitCode -eq 2) "exit $($result.ExitCode)"
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- The three stages -------------------------------------------------------------

Write-Host ""
Write-Host "-- Plan --------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    Assert-Contains "-Plan creates the session" $result.Output 'Created session: manager/current/2026-06-12.md'
    Assert-True "the file is on disk" (Test-Path (Get-SessionPath $sandbox '2026-06-12'))
    Assert-True "-Plan stamps the draft stage" ((Get-Stage $sandbox '2026-06-12') -eq 'draft')
    Assert-Contains "-Plan says what you provide" $result.Output 'WHAT YOU PROVIDE'
    Assert-Contains "-Plan names the prompt to run" $result.Output 'agentic/manager1on1.prompt.md'

    # Running it twice must not scaffold over a session that already has notes.
    Add-FixtureText (Get-SessionPath $sandbox '2026-06-12') "`nHAND WRITTEN"
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    Assert-Contains "-Plan on an existing session keeps its content" `
        (Get-SessionText (Get-SessionPath $sandbox '2026-06-12')) 'HAND WRITTEN'

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-10', '-Plan', '-DryRun')
    Assert-Contains "-DryRun prints the path" $result.Output '2026-07-10.md'
    Assert-True "-DryRun writes nothing" (-not (Test-Path (Get-SessionPath $sandbox '2026-07-10')))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- Plan carries forward within its own series ------------------------------------
# The prior record is found by the session's own series and the prior date, so a
# named series' plan reads its own last record (docs/hub/manager.md, "Which
# session a record carries from") and never the 1:1's.

$sandbox = New-AgendaSandbox
try {
    $cur = Join-Path $sandbox 'hub/manager/current'
    $arc = Join-Path $sandbox 'hub/manager/archive'
    New-Item -Path $cur, $arc -ItemType Directory -Force | Out-Null
    function Write-Record {
        param([string]$Dir, [string]$Name, [string]$Retro)
        $body = "# $Name`n`n## Stage`nretro`n`n## Retro`n$Retro`n"
        [System.IO.File]::WriteAllText((Join-Path $Dir $Name), $body, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Record $arc 'client-weekly-2026-06-12.md' 'SERIES-CARRY-MARKER'
    Write-Record $cur '2026-06-19.md' 'ONE-ON-ONE-MARKER'
    Write-Record $cur '2026-06-12.md' 'ONE-ON-ONE-OLD-MARKER'

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Type', 'client-weekly', '-Plan')
    Assert-Contains "a series' -Plan prints its own prior record's carry-forward (archive/)" $result.Output 'Carry-forward from 2026-06-12:'
    Assert-Contains "and that record's retro" $result.Output 'SERIES-CARRY-MARKER'
    Assert-NotContains "a series' plan never carries from the 1:1" $result.Output 'ONE-ON-ONE'

    Write-Record $cur 'client-weekly-2026-06-19.md' 'SERIES-CURRENT-MARKER'
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Type', 'client-weekly', '-Plan')
    Assert-Contains "the latest earlier record in the series wins (current/)" $result.Output 'SERIES-CURRENT-MARKER'
    Assert-NotContains "over an older one" $result.Output 'SERIES-CARRY-MARKER'

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Plan')
    Assert-Contains "the default series still carries from the last 1:1" $result.Output 'Carry-forward from 2026-06-19:'
    Assert-Contains "that 1:1's retro" $result.Output 'ONE-ON-ONE-MARKER'
    Assert-NotContains "and never from a series" $result.Output 'SERIES-'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

Write-Host ""
Write-Host "-- Prep and Retro ----------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Prep')
    Assert-Contains "-Prep on nothing says to run -Plan first" $result.Output 'Run '
    Assert-True "-Prep on nothing writes nothing" (-not (Test-Path (Get-SessionPath $sandbox '2026-06-12')))

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Prep')
    Assert-True "-Prep stamps the prep stage" ((Get-Stage $sandbox '2026-06-12') -eq 'prep')
    Assert-Contains "-Prep asks its three questions" $result.Output 'how you intend to show up'
    # Prep is a state check, not a writing pass -- there is nothing for an
    # assistant to do with the answers.
    Assert-NotContains "-Prep does not send you to the agent" $result.Output 'manager1on1.prompt.md'
    Assert-Contains "-Prep says nothing needs writing back" $result.Output 'Nothing needs writing back'

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Retro')
    Assert-True "-Retro stamps the retro stage" ((Get-Stage $sandbox '2026-06-12') -eq 'retro')
    Assert-Contains "-Retro names the prompt to run" $result.Output 'agentic/manager1on1.prompt.md'
    Assert-Contains "-Retro says where the notes go" $result.Output "'## Retro'"
    # Archive is org-scoped: it moves a card out of the ACTIVE ORG's current/,
    # and manager/ is a sibling of the org folders. Suggesting it would send the
    # user to a command that cannot find this file.
    Assert-NotContains "-Retro does not suggest the org-scoped archive verb" $result.Output 'Archive 2026-06-12.md'
    # ...it names -Close instead, which is the verb that can actually find the
    # file. This line used to be "move it to manager/archive/" and
    # the move was a manual mv that never wrote the closed stamp.
    Assert-Contains "-Retro names the close verb" $result.Output 'MeetingAgenda -Date 2026-06-12 -Close'
    Assert-Contains "-Retro says what closing does" $result.Output 'stamps the date it closed'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- Close ----------------------------------------------------------------------

Write-Host ""
Write-Host "-- Close -------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Retro')

    $currentPath = Get-SessionPath $sandbox '2026-06-12'
    $archivePath = Join-Path (Join-Path (Join-Path $sandbox 'hub') 'manager/archive') '2026-06-12.md'

    # The destination folder is created by -Close if it is not there. New-SessionFile
    # makes it too, so remove it first -- otherwise this asserts nothing.
    $archiveDirPath = Split-Path $archivePath -Parent
    if (Test-Path $archiveDirPath) { Remove-Item $archiveDirPath -Recurse -Force }

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Close')

    Assert-True "-Close creates manager/archive/ when it is absent" (Test-Path $archiveDirPath)
    Assert-True "-Close moves the session out of current/" (-not (Test-Path $currentPath))
    Assert-True "-Close puts it in archive/ under the same name" (Test-Path $archivePath)
    Assert-Contains "-Close says where the file went" $result.Output 'manager/archive/2026-06-12.md'

    $closedText = Get-SessionText $archivePath
    $today = (Get-Date -Format 'yyyy-MM-dd')
    # The same stamp Move-PromptToArchive writes, from the same implementation --
    # agent/ado/reporting.py reads this literal out of archived files.
    Assert-True "-Close stamps a closed date on its own line" ($closedText -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}')
    Assert-Contains "-Close stamps today" $closedText "**Closed:** $today"

    # Idempotent: a second -Close is a report, not an error and not a second stamp.
    $again = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Close')
    Assert-Contains "a second -Close reports it is already closed" $again.Output 'Already closed'
    Assert-True "a second -Close leaves the archived file where it is" (Test-Path $archivePath)
    $stampCount = ([regex]::Matches((Get-SessionText $archivePath), '(?m)^\*\*Closed:\*\*')).Count
    Assert-True "a second -Close does not stamp twice" ($stampCount -eq 1)

    # A DUPLICATE is not the idempotent case: a session in current/ AND a closed
    # one in archive/ for the same date. -Close protects the archived copy
    # correctly and cannot remove the duplicate, so it must at least be a failure
    # the caller can see -- it reported in yellow and exited 0.
    #
    $duplicate = Get-SessionPath -Root $sandbox -Date '2026-06-12'
    Write-FixtureText $duplicate "# 1:1 -- 2026-06-12`n`n## Stage`ndraft`nDUPLICATE"
    $clash = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Close')
    Assert-Contains "-Close refuses to overwrite the archived session" $clash.Output 'already in manager/archive/'
    Assert-Contains "and says which copy is the record" $clash.Output 'the record'
    Assert-True "and exits 2 rather than reporting success" ($clash.ExitCode -eq 2) "exit $($clash.ExitCode)"
    Assert-Contains "the archived session is untouched" (Get-SessionText $archivePath) '**Closed:**'
    Assert-Contains "and the duplicate is left for a person to resolve" (Get-SessionText $duplicate) 'DUPLICATE'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

$sandbox = New-AgendaSandbox
try {
    # -Close on a date with no session says what to run, rather than failing.
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-01', '-Close')
    Assert-Contains "-Close on a missing session points at -Plan" $result.Output 'No session for 2026-07-01'

    # -DryRun writes nothing, and says both halves of what it would do.
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-02', '-Plan')
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-02', '-Close', '-DryRun')
    Assert-Contains "-Close -DryRun names the move" $result.Output 'Would move manager/current/2026-07-02.md'
    Assert-Contains "-Close -DryRun names the stamp" $result.Output "Would stamp '**Closed:**"
    Assert-True "-Close -DryRun leaves the session in current/" (Test-Path (Get-SessionPath $sandbox '2026-07-02'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- Carry-forward ------------------------------------------------------------------

Write-Host ""
Write-Host "-- A CRLF session ----------------------------------------" -ForegroundColor Cyan

# The tool has to read a session whose line endings are CRLF -- a hub edited on
# Windows is CRLF whatever this repo checks out. The parser matches \r?\n and
# always has; this is the case that says so out loud.
#
# It starts from a CRLF template, so it pins the create half too: the scaffold
# normalises, and the session it writes is LF even here. That assertion is new
# with the fix -- the template's checkout used to
# decide the session's bytes, which made Windows and macOS write different
# files for the same verb.

$sandbox = New-AgendaSandbox
try {
    $tpl = Join-Path $sandbox 'pkg/templates/ManagerSession.template.md'
    $tplText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($tpl))
    $crlf = ($tplText -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllBytes($tpl, [System.Text.Encoding]::UTF8.GetBytes($crlf))

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    Assert-True "the stage is read out of a CRLF session" ((Get-Stage $sandbox '2026-06-12') -eq 'draft')

    # CREATED from a CRLF template, so: LF. The stage change that -Plan just
    # made is an EDIT of a file that was already LF, which leaves it LF.
    $scaffoldPath = Get-SessionPath $sandbox '2026-06-12'
    $scaffoldRaw = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($scaffoldPath))
    Assert-True "a CRLF template still scaffolds an LF session" (-not $scaffoldRaw.Contains("`r`n")) `
        'the scaffold copied the template byte for byte -- a CREATED file is LF'
    Assert-True "and the scaffold wrote no BOM" (-not (Test-HasBom $scaffoldPath))

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Close')
    $archived = Get-SessionText (Join-Path (Join-Path (Join-Path $sandbox 'hub') 'manager/archive') '2026-06-12.md')
    Assert-True "-Close stamps a CRLF session on its own line" `
        ($archived -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

Write-Host ""
Write-Host "-- Carry-forward -----------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $prior = Get-SessionPath $sandbox '2026-06-12'
    $text = (Get-SessionText $prior) -replace '(?ms)## Retro.*?(?=## Sent)', "## Retro`nThe reporting decision is still open.`n`n"
    Write-FixtureText $prior $text

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Plan')
    Assert-Contains "-Plan surfaces the prior session's retro" $result.Output 'The reporting decision is still open.'
    Assert-Contains "-Plan says which session it came from" $result.Output 'Carry-forward from 2026-06-12'
    Assert-Contains "the new session names its prior in the heading" (Get-SessionText (Get-SessionPath $sandbox '2026-06-26')) '## Carried from 2026-06-12'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- Which session a record carries from ----------------------------------------------
# docs/hub/manager.md, "Which session a record carries from". The rule over the
# shared table first -- the same rows Tests/test_manager.py asserts against the
# agent's reader, so the two halves cannot read one heading two ways -- and then
# the verb end to end: a session added out of order is SAID, and nothing is
# rewritten.

Write-Host ""
Write-Host "-- Which session a record carries from -------------------" -ForegroundColor Cyan

try {
    . (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
    . (Join-Path $pkgRoot 'Scripts/Resolve-CarriedFrom.ps1')
    $tablePath = Join-Path $pkgRoot 'Tests/fixtures/carried-from/table.json'
    $table = Get-Content $tablePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $verdicts = @{}
    foreach ($row in $table.rows) {
        $names = @(@($row.current) + @($row.archive) | Where-Object { $_ })
        $check = Resolve-P20CarriedFrom -SessionName $row.session -Heading $row.heading -Names $names
        $verdicts[$row.verdict] = $true
        Assert-True "table: $($row.case) -- $($row.verdict)" `
            ($check.Verdict -eq $row.verdict -and $check.Expected -eq $row.expected) `
            "read $($check.Verdict) / $($check.Expected), the table says $($row.verdict) / $($row.expected)"
    }
    Assert-True "the table covers every verdict" (($verdicts.Keys | Sort-Object) -join ',' -eq 'absent,missing,ok,stale') (($verdicts.Keys | Sort-Object) -join ',')

    $okNote = Format-P20CarriedFromNote (Resolve-P20CarriedFrom -SessionName '2026-06-26.md' -Heading '2026-06-12' -Names @('2026-06-12.md', '2026-06-26.md'))
    Assert-True "a heading that is right says nothing" ($okNote -eq '') $okNote
    Assert-True "the heading is read from a CRLF line" ((Get-P20CarriedFromHeading @("# 2026-06-26`r", "## Carried from 2026-06-12`r")) -eq '2026-06-12')
    Assert-True "no heading reads as null, not as empty" ($null -eq (Get-P20CarriedFromHeading @('# 2026-06-26', '## Stage', 'draft')))
    Assert-True "the one builder names the default series by date alone" ((New-P20SessionFileName -Series '1on1' -Date '2026-06-26') -eq '2026-06-26.md')
    Assert-True "the one builder puts a series in front of the date" ((New-P20SessionFileName -Series 'client-weekly' -Date '2026-06-26') -eq 'client-weekly-2026-06-26.md')
    foreach ($row in $table.rows) {
        $parts = Get-P20SessionNameParts $row.session
        if ($parts) {
            Assert-True "builder and parser round-trip: $($row.session)" ((New-P20SessionFileName -Series $parts.Series -Date $parts.Date) -eq $row.session)
        }
    }
}
catch {
    Assert-True 'the table ran to the end without a terminating error' $false $_.Exception.Message
}

$sandbox = New-AgendaSandbox
try {
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Plan')
    $laterPath = Get-SessionPath $sandbox '2026-06-26'
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26')
    Assert-NotContains "a session in order says nothing about its heading" $result.Output 'Check:'

    # Out of order: a session for a date between the two, created after the later one.
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-19', '-Plan')
    Assert-Contains "-Plan creating a session out of order names the later one it sits in front of" $result.Output '2026-06-26.md -- Carried from 2026-06-12, but the latest earlier session in this series is 2026-06-19'
    $before = [System.IO.File]::ReadAllBytes($laterPath)

    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26')
    Assert-Contains "the status says the heading names another session" $result.Output 'Check:   Carried from 2026-06-12, but the latest earlier session in this series is 2026-06-19'
    Assert-Contains "and says it is not rewritten" $result.Output 'The heading is not rewritten'
    $result = Invoke-Agenda -Root $sandbox -Arguments @()
    Assert-Contains "the quick menu says it too" $result.Output 'Check:   Carried from 2026-06-12'
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26', '-Plan')
    Assert-Contains "-Plan on the stale session says so beside the carry-forward" $result.Output 'Check: Carried from 2026-06-12'

    $after = Get-SessionText $laterPath
    Assert-Contains "no reader rewrote the heading" $after '## Carried from 2026-06-12'
    $bodyBefore = ([System.Text.Encoding]::UTF8.GetString($before)) -replace '(?m)^draft$', ''
    $bodyAfter = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($laterPath))) -replace '(?m)^draft$', ''
    Assert-True "the status and the quick menu changed nothing in the file" ($bodyBefore -eq $bodyAfter)

    # A heading edited by hand to a session that is not there.
    $edited = (Get-SessionText $laterPath) -replace '## Carried from 2026-06-12', '## Carried from 2026-05-01'
    [System.IO.File]::WriteAllText($laterPath, $edited)
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-26')
    Assert-Contains "a heading naming no earlier session says so" $result.Output 'Carried from 2026-05-01, which is not an earlier session in this series'

    # A series reads only its own records.
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'skip-level', '-Plan')
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Type', 'skip-level')
    Assert-NotContains "a series' first record is not stale because the 1:1 has earlier ones" $result.Output 'Check:'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# -- The bytes a session is written with ---------------------------------------------
# Every write this script makes goes through the one card writer, so a session
# gets the contract a card gets: UTF-8 with NO BOM, and the terminator the file
# already has when it is edited. Set-SessionStage rewrites the WHOLE file on
# every stage change and used to put a BOM back that -Close would strip again.
#

Write-Host ""
Write-Host "-- The bytes a session is written with -------------------" -ForegroundColor Cyan


$sandbox = New-AgendaSandbox
try {
    # Created by this script (not by NewMeeting): -Plan is what scaffolds one.
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Plan')
    $path = Get-SessionPath $sandbox '2026-06-12'
    Assert-True "a session this script created has no BOM" (-not (Test-HasBom $path)) 'BOM on a new session'

    # Edited: each stage change rewrites the whole file.
    foreach ($stage in @('-Prep', '-Retro')) {
        $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', $stage)
        Assert-True "no BOM after $stage" (-not (Test-HasBom $path)) "BOM after $stage"
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    Assert-True "the first byte is still the '#' of the title" ($bytes[0] -eq 0x23) ("0x{0:X2}" -f $bytes[0])

    # Closed: the stamp writes through the same writer, so the move is one added
    # line rather than a whole-file diff.
    $beforeClose = [System.Text.Encoding]::UTF8.GetString($bytes)
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-06-12', '-Close')
    $closedPath = Join-Path $sandbox 'hub/manager/archive/2026-06-12.md'
    Assert-True "the closed session is in archive/" (Test-Path $closedPath)
    Assert-True "no BOM after -Close" (-not (Test-HasBom $closedPath)) 'BOM on a closed session'

    $afterClose = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($closedPath))
    # One added line, and nothing else moved: the whole point of one writer.
    $before = @($beforeClose -split "`n")
    $after = @($afterClose -split "`n")
    $added = @($after | Where-Object { $_ -notin $before })
    Assert-True "-Close changes exactly one line" ($added.Count -eq 1) ($added -join ' | ')
    Assert-True "and that line is the stamp" ($added.Count -eq 1 -and $added[0] -match '^\*\*Closed:\*\*') ($added -join ' | ')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# A CRLF session keeps its endings through a stage change -- editing keeps what
# it finds, and the stamp already had a case for this.
$sandbox = New-AgendaSandbox
try {
    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-02', '-Plan')
    $path = Get-SessionPath $sandbox '2026-07-02'
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))
    $crlf = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($path, $crlf, (New-Object System.Text.UTF8Encoding($false)))

    $null = Invoke-Agenda -Root $sandbox -Arguments @('-Date', '2026-07-02', '-Prep')
    $after = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))
    Assert-True "a CRLF session is still CRLF after a stage change" ($after.Contains("`r`n")) 'the stage change normalised the file'
    Assert-True "and gained no bare LF" (($after -replace "`r`n", '') -notmatch "`n") 'a bare LF was introduced'
    Assert-True "and gained no BOM" (-not (Test-HasBom $path)) 'BOM after editing a CRLF session'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-AgendaSandbox $sandbox }

# The writer is shared, not copied.
$agendaSource = Get-Content (Join-Path $pkgRoot 'Scripts/Get-MeetingAgenda.ps1') -Raw
Assert-True "Get-MeetingAgenda writes through Write-CardText" ($agendaSource -match 'Write-CardText -Path')
Assert-True "it has no encoding of its own" ($agendaSource -notmatch 'UTF8Encoding\(\$true\)') 'a second BOM writer is still in Get-MeetingAgenda.ps1'
Assert-True "the writer is its own file, dot-sourced" ($agendaSource -match "Write-CardText\.ps1")

# -- What it refuses -----------------------------------------------------------------

Write-Host ""
Write-Host "-- What it refuses ---------------------------------------" -ForegroundColor Cyan

$sandbox = New-AgendaSandbox
try {
    $result = Invoke-Agenda -Root $sandbox -Arguments @('-Date', 'yesterday', '-Plan')
    Assert-Contains "a date that is not a date is refused" $result.Output 'Invalid date'

    $script = Join-Path $sandbox 'pkg/Scripts/Get-MeetingAgenda.ps1'
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
finally { Remove-AgendaSandbox $sandbox }

# -- The agent prompt it points at ---------------------------------------------------
# The command tells you to run a file. If that file is not in the package, the
# instruction is a dead end -- which is exactly the class of break the
# Portability suite's link clause exists for, one layer up.

Write-Host ""
Write-Host "-- The prompt it points at -------------------------------" -ForegroundColor Cyan

Assert-True "the agent prompt ships with the package" (Test-Path $agentPrompt)

# -- The wrapper ----------------------------------------------------------------------

Write-Host ""
Write-Host "-- The wrapper -------------------------------------------" -ForegroundColor Cyan

$stubs = @"
function global:Show-CommandHelp { param([string]`$CommandName) Write-Host "HELP:`$CommandName" }
function global:Write-ToolkitLog { param(`$Type, `$Source, `$Detail) Write-Host "LOG:`$Type/`$Source/`$Detail" }
function global:Write-CliError { param(`$Message, `$Hint) Write-Host "ERR:`$Message" }
function global:Get-CliPrefix { return 'tk' }
# The refusal contract's guard, the real one -- the loader dot-sources it too.
. '$guardFile'
. '$commandFile'
"@

$result = pwsh -NoProfile -Command "$stubs; if (Get-Command Get-P20MeetingAgenda -ErrorAction SilentlyContinue) { 'DEFINED' }" 2>&1 | Out-String
Assert-Contains "dot-sourcing the command file defines Get-P20MeetingAgenda" $result 'DEFINED'

$result = pwsh -NoProfile -Command "$stubs; Get-P20MeetingAgenda -Help" 2>&1 | Out-String
Assert-Contains "-Help renders from the shared help table" $result 'HELP:MeetingAgenda'

# The guard that exists because someone spliced a markdown file onto the command
# line and got a string-to-switch conversion error instead of an explanation.
$result = pwsh -NoProfile -Command "$stubs; Get-P20MeetingAgenda '## Agenda' 'some pasted file content'" 2>&1 | Out-String
Assert-Contains "a positional argument is refused with an explanation" $result 'takes only named flags'
Assert-Contains "the refusal shows what was passed" $result '## Agenda'
Assert-Contains "the refusal is logged" $result 'LOG:ERR'

$result = pwsh -NoProfile -Command "$stubs; (Get-Command Get-P20MeetingAgenda).Parameters.Keys -join ','" 2>&1 | Out-String
foreach ($flag in @('Date', 'Type', 'Plan', 'Prep', 'Retro', 'Close', 'DryRun')) {
    Assert-Contains "the wrapper takes -$flag" $result $flag
}

# -- Summary -------------------------------------------------------------------------

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
