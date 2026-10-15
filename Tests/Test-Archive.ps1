<#
.SYNOPSIS
    Tests for Move-PromptToArchive.ps1 — round-history logic, partial matching,
    help output, and ambiguous-match handling.
.DESCRIPTION
    Each test creates an isolated temp directory containing current/ and
    archive/ subfolders plus a fresh git repo, stubs $global:P20Config
    and Get-PromptFolders to point at it, and exercises the script end-to-end.

    Run:  pwsh -File toolkit/Tests/Test-Archive.ps1
    Or:   {cliPrefix}TestToolkit -Archive
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location:
# works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent

$archiveScript = Join-Path $pkgRoot 'Scripts/Move-PromptToArchive.ps1'
if (-not (Test-Path $archiveScript)) {
    Write-Error "Move-PromptToArchive.ps1 not found at $archiveScript"
    return
}

# ── Test harness ──────────────────────────────────────────────────────────────

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
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    # Literal, not -like: a needle with [ ] in it is a wildcard class to -like,
    # so '[=] Already archived' could never match itself.
    if ($Haystack.Contains($Needle)) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName — '$Needle' not found in output"
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
        $msg = "  FAIL  $TestName — expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# ── Sandbox setup ─────────────────────────────────────────────────────────────
#
# A sandbox is a temp dir with current/ and archive/ subdirs and a fresh
# git repo. $global:P20Config and Get-PromptFolders are stubbed to
# point at it, mirroring how utilities.psm1 wires real runs.

function New-ArchiveSandbox {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("test-archive-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'current') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'archive') -Force | Out-Null

    Push-Location $base
    try {
        git init --quiet 2>&1 | Out-Null
        git checkout -B main --quiet 2>&1 | Out-Null
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name 'Archive Test' 2>&1 | Out-Null
        git config commit.gpgsign false 2>&1 | Out-Null
        git config core.autocrlf false 2>&1 | Out-Null
        Set-Content -Path (Join-Path $base '.gitkeep') -Value '' -Encoding UTF8
        git add .gitkeep 2>&1 | Out-Null
        git commit -m 'init' --quiet 2>&1 | Out-Null
    }
    finally {
        Pop-Location
    }

    $global:P20Config = @{ PromptsRoot = $base; StoreSync = 'git' }
    return $base
}

function Remove-ArchiveSandbox {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Add-CurrentFile {
    param([string]$Sandbox, [string]$Name, [string]$Content = '')
    $path = Join-Path (Join-Path $Sandbox 'current') $Name
    if (-not $Content) { $Content = "# $Name`n" }
    Write-FixtureText $path $Content
}

function Add-ArchiveFile {
    param([string]$Sandbox, [string]$Name, [string]$Content = '')
    $path = Join-Path (Join-Path $Sandbox 'archive') $Name
    if (-not $Content) { $Content = "# $Name`n" }
    Write-FixtureText $path $Content
}

function Save-SandboxState {
    param([string]$Sandbox, [string]$Message = 'seed')
    Push-Location $Sandbox
    try {
        git add . 2>&1 | Out-Null
        git commit -m $Message --quiet 2>&1 | Out-Null
    }
    finally { Pop-Location }
}

function Get-CommitSubjects {
    param([string]$Sandbox)
    Push-Location $Sandbox
    try {
        return @(git log --format='%s')
    }
    finally { Pop-Location }
}

function Invoke-Archive {
    # Runs the script and captures all streams as a single string.
    # Returns the captured output; callers inspect it for warnings/errors.
    # The exit code the script left behind is parked in $script:LastArchiveExit,
    # because "did it refuse?" is now a question about the code as well as the
    # text -- see the refusal contract in AGENTS.md.
    param([hashtable]$BoundArgs)
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = 0
        $out = & $archiveScript @BoundArgs *>&1 | Out-String
        $script:LastArchiveExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevErr
    }
    return $out
}

function Invoke-ArchiveCapture {
    # Like Invoke-Archive, but keeps the stream OBJECTS so a caller can tell an
    # ErrorRecord from an ordinary line. Needed for the first-archive case: the
    # command used to write a red Get-ChildItem error and then succeed, which
    # every string-matching assertion in this file passed straight over.
    param([hashtable]$BoundArgs)
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $records = @(& $archiveScript @BoundArgs *>&1)
    }
    finally {
        $ErrorActionPreference = $prevErr
    }
    return [pscustomobject]@{
        Text   = ($records | Out-String)
        Errors = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
}

# Stub Get-PromptFolders to read from the current $global:P20Config.
# Mirrors utilities.psm1 behavior when PromptsFolder is unset.
function global:Get-PromptFolders {
    $root = $global:P20Config.PromptsRoot
    @{
        Current = Join-Path $root 'current'
        Archive = Join-Path $root 'archive'
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Archive Script Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Test 1: -Help output ─────────────────────────────────────────────────────

Write-Host "── -Help output ───────────────────────────────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    $output = Invoke-Archive @{ Help = $true }
    Assert-Contains "-Help mentions ROUND HISTORY" $output 'ROUND HISTORY'
    Assert-Contains "-Help mentions -rN" $output '-rN'
    Assert-Contains "-Help mentions -WhatIf" $output '-WhatIf'
    Assert-Contains "-Help mentions USAGE" $output 'USAGE'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 2: First archive — plain move, no suffix ────────────────────────────

Write-Host "── First archive (no round suffix) ────────────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-100-feature.prompt.md'
    Save-SandboxState $sandbox

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $null = Invoke-Archive @{ File = 'US-100-feature.prompt.md' }
    $afterCommits = Get-CommitSubjects $sandbox

    Assert-True "Source file removed from current/" (-not (Test-Path (Join-Path $sandbox 'current/US-100-feature.prompt.md')))
    Assert-True "Destination file in archive/ with original name" (Test-Path (Join-Path $sandbox 'archive/US-100-feature.prompt.md'))
    Assert-True "Archived file has no -rN suffix" (-not (Test-Path (Join-Path $sandbox 'archive/US-100-feature-r1.prompt.md')))
    Assert-Equal "One new commit created" 1 ($afterCommits.Count - $beforeCommits)
    Assert-Contains "Commit subject mentions archive move" $afterCommits[0] 'archive: move'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 3: Second archive — rename prior to -r1, archive incoming as -r2 ────

Write-Host "── Second archive (round history kicks in) ────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-ArchiveFile $sandbox 'US-200-feature.prompt.md' '# first round'
    Add-CurrentFile $sandbox 'US-200-feature.prompt.md' '# second round'
    Save-SandboxState $sandbox

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $null = Invoke-Archive @{ File = 'US-200-feature.prompt.md' }
    $afterSubjects = Get-CommitSubjects $sandbox

    Assert-True "Prior archive renamed to -r1" (Test-Path (Join-Path $sandbox 'archive/US-200-feature-r1.prompt.md'))
    Assert-True "Incoming archived as -r2" (Test-Path (Join-Path $sandbox 'archive/US-200-feature-r2.prompt.md'))
    Assert-True "Original plain archive no longer present" (-not (Test-Path (Join-Path $sandbox 'archive/US-200-feature.prompt.md')))
    Assert-True "Source removed from current/" (-not (Test-Path (Join-Path $sandbox 'current/US-200-feature.prompt.md')))
    Assert-Equal "Two new commits created (rename + move)" 2 ($afterSubjects.Count - $beforeCommits)
    Assert-Contains "Rename commit subject mentions round history" ($afterSubjects -join "`n") 'round history'

    # Verify content was preserved across the rename
    $r1Content = Get-Content (Join-Path $sandbox 'archive/US-200-feature-r1.prompt.md') -Raw
    $r2Content = Get-Content (Join-Path $sandbox 'archive/US-200-feature-r2.prompt.md') -Raw
    Assert-Contains "r1 retains original first-round content" $r1Content 'first round'
    Assert-Contains "r2 contains the incoming second-round content" $r2Content 'second round'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 4: Third archive — highest existing round detected, next is -r3 ─────

Write-Host "── Third archive (next round = -r3) ───────────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-ArchiveFile $sandbox 'US-300-feature-r1.prompt.md'
    Add-ArchiveFile $sandbox 'US-300-feature-r2.prompt.md'
    Add-CurrentFile $sandbox 'US-300-feature.prompt.md' '# round three'
    Save-SandboxState $sandbox

    $null = Invoke-Archive @{ File = 'US-300-feature.prompt.md' }

    Assert-True "Existing -r1 preserved" (Test-Path (Join-Path $sandbox 'archive/US-300-feature-r1.prompt.md'))
    Assert-True "Existing -r2 preserved" (Test-Path (Join-Path $sandbox 'archive/US-300-feature-r2.prompt.md'))
    Assert-True "Incoming archived as -r3" (Test-Path (Join-Path $sandbox 'archive/US-300-feature-r3.prompt.md'))
    Assert-True "No plain (no-suffix) archive created" (-not (Test-Path (Join-Path $sandbox 'archive/US-300-feature.prompt.md')))
    Assert-True "Source removed from current/" (-not (Test-Path (Join-Path $sandbox 'current/US-300-feature.prompt.md')))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 4b: A reopened card whose title changed is still the same card ─────
# Rounds follow the card ID, not the file name: the earlier round keeps its own
# slug as -r1, the new one is -r2 under its slug.
#

Write-Host "── A changed title is still the same card (rounds by id) ─" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-ArchiveFile $sandbox 'Task400-the-old-title.prompt.md' '# first round'
    Add-CurrentFile $sandbox 'Task400-a-better-title.prompt.md' '# second round'
    Add-ArchiveFile $sandbox '4001-not-this-card.prompt.md' '# a different card'
    Save-SandboxState $sandbox

    $null = Invoke-Archive @{ File = 'Task400-a-better-title.prompt.md' }

    Assert-True "The earlier round keeps its own title, as -r1" (Test-Path (Join-Path $sandbox 'archive/Task400-the-old-title-r1.prompt.md'))
    Assert-True "The new round is -r2 under its own title" (Test-Path (Join-Path $sandbox 'archive/Task400-a-better-title-r2.prompt.md'))
    Assert-True "No plain archive of the new title" (-not (Test-Path (Join-Path $sandbox 'archive/Task400-a-better-title.prompt.md')))
    Assert-True "A different card with a longer id is untouched (an id is not a substring)" (Test-Path (Join-Path $sandbox 'archive/4001-not-this-card.prompt.md'))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 5: Partial match resolves uniquely ──────────────────────────────────

Write-Host "── Partial match resolution ───────────────────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-316615-plg-end-to-end.prompt.md'
    Add-CurrentFile $sandbox 'US-999999-unrelated.prompt.md'
    Save-SandboxState $sandbox

    $null = Invoke-Archive @{ File = '316615' }

    Assert-True "Matched file moved to archive/" (Test-Path (Join-Path $sandbox 'archive/US-316615-plg-end-to-end.prompt.md'))
    Assert-True "Matched file removed from current/" (-not (Test-Path (Join-Path $sandbox 'current/US-316615-plg-end-to-end.prompt.md')))
    Assert-True "Unrelated file left in current/" (Test-Path (Join-Path $sandbox 'current/US-999999-unrelated.prompt.md'))
    Assert-True "Unrelated file NOT moved to archive/" (-not (Test-Path (Join-Path $sandbox 'archive/US-999999-unrelated.prompt.md')))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# ── Test 6: Multiple matches — warn and abort ────────────────────────────────

Write-Host "── Ambiguous partial match (warn + abort) ─────────────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-500000-alpha.prompt.md'
    Add-CurrentFile $sandbox 'US-500000-beta.prompt.md'
    Save-SandboxState $sandbox

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $output = Invoke-Archive @{ File = '500000' }
    $afterCommits = (Get-CommitSubjects $sandbox).Count

    Assert-Contains "Output names both candidates" $output 'US-500000-alpha.prompt.md'
    Assert-Contains "Output says how many matched" $output "matches 2 files in current/"
    Assert-Contains "Output hints at -List" $output '-List'
    Assert-True "Alpha file still in current/" (Test-Path (Join-Path $sandbox 'current/US-500000-alpha.prompt.md'))
    Assert-True "Beta file still in current/" (Test-Path (Join-Path $sandbox 'current/US-500000-beta.prompt.md'))
    Assert-True "Nothing moved to archive/" ((Get-ChildItem (Join-Path $sandbox 'archive') -File).Count -eq 0)
    Assert-Equal "No new commits created" 0 ($afterCommits - $beforeCommits)
    # A write that did not happen must not read as one: the bridge types the
    # reply off this exit code.
    Assert-Equal "Several matches exits 2 (a stated refusal)" 2 $script:LastArchiveExit
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- No match at all -----------------------------------------------------------
# This used to print a raw `Write-Error:` record -- no hint, no exit code -- and
# then exit 0, so POST /api/cmd/Archive reported success for a card that was
# never moved and usage.<MACHINE>.log recorded `Archive ok`.

Write-Host "-- No matching card (stated refusal) ------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-600-present.prompt.md'
    Save-SandboxState $sandbox

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $output = Invoke-Archive @{ File = 'does-not-exist-card' }
    $afterCommits = (Get-CommitSubjects $sandbox).Count

    Assert-Contains "No match states the reason" $output "No file matching 'does-not-exist-card' found in current/."
    Assert-Contains "No match gives a hint" $output '-List'
    Assert-True "No match writes no raw error record" ($output -notmatch 'Write-Error')
    Assert-Equal "No match exits 2 (a stated refusal)" 2 $script:LastArchiveExit
    Assert-True "The card that IS there was not touched" (Test-Path (Join-Path $sandbox 'current/US-600-present.prompt.md'))
    Assert-True "Nothing moved to archive/" ((Get-ChildItem (Join-Path $sandbox 'archive') -File).Count -eq 0)
    Assert-Equal "No new commits created" 0 ($afterCommits - $beforeCommits)
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- An ID is an ID, not a substring -------------------------------------------
# `Archive 39` used to fall through to `*39*` over current/, match exactly one
# card -- Task139 -- and move AND COMMIT it with no prompt. The only sign was a
# "Moved:" line naming a card nobody typed.
#An all-digit argument is
# now read with the shared card-name rule: the card whose id IS that number.

Write-Host "-- An all-digit argument is an ID --------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'Task139-extract-scoring-rules.prompt.md'
    Add-CurrentFile $sandbox 'US-142-story.prompt.md'
    Add-CurrentFile $sandbox '114-bug.prompt.md'
    Save-SandboxState $sandbox

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $output = Invoke-Archive @{ File = '39' }
    $afterCommits = (Get-CommitSubjects $sandbox).Count

    Assert-Contains "'39' states that no card carries that id" $output "No card with id '39' in current/."
    Assert-Contains "'39' says an all-digit argument is an ID" $output 'not a partial name'
    Assert-Equal "'39' exits 2 (a stated refusal)" 2 $script:LastArchiveExit
    Assert-True "'39' leaves Task139 in current/" (Test-Path (Join-Path $sandbox 'current/Task139-extract-scoring-rules.prompt.md'))
    Assert-True "'39' moves nothing to archive/" ((Get-ChildItem (Join-Path $sandbox 'archive') -File).Count -eq 0)
    Assert-Equal "'39' creates no commit" 0 ($afterCommits - $beforeCommits)

    # The id it really is still archives, prefix and all.
    $null = Invoke-Archive @{ File = '139' }
    Assert-True "'139' archives Task139" (Test-Path (Join-Path $sandbox 'archive/Task139-extract-scoring-rules.prompt.md'))
    Assert-True "'139' removes it from current/" (-not (Test-Path (Join-Path $sandbox 'current/Task139-extract-scoring-rules.prompt.md')))

    # A type prefix in front of the id is part of the rule, not an obstacle.
    $null = Invoke-Archive @{ File = '142' }
    Assert-True "'142' archives US-142" (Test-Path (Join-Path $sandbox 'archive/US-142-story.prompt.md'))

    # A bare id with no prefix is the Bug shape and matches itself.
    $null = Invoke-Archive @{ File = '114' }
    Assert-True "'114' archives the bare-id card" (Test-Path (Join-Path $sandbox 'archive/114-bug.prompt.md'))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- An id need not be a number ----------------------------------------------------
# A card with no work item carries a four-character id (docs/hub/cards.md, "The
# filename"). The rule that decides "is this argument an id?" used to be '^\d+$', so
# `Archive k7m2` would have fallen to partial-name matching -- the fallback the
# section above exists to keep ids away from.

Write-Host "-- A lettered id is an ID too ------------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'TaskK7M2-wallet-ticket.prompt.md'
    Add-CurrentFile $sandbox 'Q4TN-qr-code-bug.prompt.md'
    Add-CurrentFile $sandbox 'Task150-mentions-K7M2-in-its-name.prompt.md'
    Save-SandboxState $sandbox

    # Typed the way a person types it: lowercase.
    $null = Invoke-Archive @{ File = 'k7m2' }
    Assert-True "'k7m2' archives TaskK7M2, prefix and all" (Test-Path (Join-Path $sandbox 'archive/TaskK7M2-wallet-ticket.prompt.md'))
    Assert-True "'k7m2' does NOT touch a card that only mentions K7M2 in its name" (Test-Path (Join-Path $sandbox 'current/Task150-mentions-K7M2-in-its-name.prompt.md'))

    $null = Invoke-Archive @{ File = 'Q4TN' }
    Assert-True "'Q4TN' archives the bare-id card" (Test-Path (Join-Path $sandbox 'archive/Q4TN-qr-code-bug.prompt.md'))

    # An id nobody has is a refusal -- never a guess by partial name.
    $output = Invoke-Archive @{ File = 'M2T7' }
    Assert-Contains "'M2T7' states that no card carries that id" $output "No card with id 'M2T7' in current/."
    Assert-Equal "'M2T7' exits 2 (a stated refusal)" 2 $script:LastArchiveExit
    Assert-True "'M2T7' leaves everything where it was" (Test-Path (Join-Path $sandbox 'current/Task150-mentions-K7M2-in-its-name.prompt.md'))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- Through the VERB, not the script -------------------------------------------
# Everything above runs Move-PromptToArchive.ps1 directly, with a stubbed
# Get-PromptFolders. That is how this was missed for three days: run as a verb,
# Archive asked the MODULE's Get-PromptFolders, which read the folder names
# through a `$script:` name that is $null from a launched script -- so it looked
# in `<hub>/<org>/` and saw no cards at all, while Status listed them.
#This section imports the
# real module in a fresh shell and types the verbs the way a person does.

Write-Host "-- Archive, typed as a verb, finds the card -----------" -ForegroundColor Cyan

$verbBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-archive-verb-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
$verbHub = Join-Path $verbBase 'hub'
$verbLog = Join-Path $verbBase 'log'
New-Item -ItemType Directory -Path $verbHub, $verbLog -Force | Out-Null
try {
    $verbPrefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $verbScript = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$verbHub'; `$env:P20_USAGE_LOG_DIR = '$verbLog'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; " +
        "${verbPrefix}NewPrompt -Title 'Made to be archived' -Type Task -Id K7M2 | Out-Null; " +
        "'LIST-BEGIN'; ${verbPrefix}Archive -List; 'LIST-END'; " +
        "${verbPrefix}Archive k7m2; 'ARCHIVE-EXIT=' + `$LASTEXITCODE; " +
        "${verbPrefix}Archive k7m2; 'AGAIN-EXIT=' + `$LASTEXITCODE"
    $verbOut = (& pwsh -NoProfile -NonInteractive -Command $verbScript 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $listed = [regex]::Match($verbOut, '(?s)LIST-BEGIN(.*)LIST-END').Groups[1].Value
    Assert-True "'Archive -List' as a verb lists the card Status would" ($listed -match 'TaskK7M2-made-to-be-archived\.prompt\.md') $listed
    Assert-True "'Archive -List' does not claim current/ is empty" ($listed -notmatch 'No files in current') $listed
    Assert-True "'Archive k7m2' as a verb exits 0" ($verbOut -match 'ARCHIVE-EXIT=0') $verbOut
    $archived = @(Get-ChildItem $verbHub -Recurse -Filter 'TaskK7M2-made-to-be-archived.prompt.md' | Where-Object { $_.DirectoryName -match '[\\/]archive$' })
    Assert-Equal 'and the card is in archive/' 1 $archived.Count
    $stillCurrent = @(Get-ChildItem $verbHub -Recurse -Filter 'TaskK7M2-*.prompt.md' | Where-Object { $_.DirectoryName -match '[\\/]current$' })
    Assert-Equal 'and no longer in current/' 0 $stillCurrent.Count
    # Twice is fine: the second says where the card already is, and succeeds.
    Assert-True "'Archive k7m2' a second time exits 0" ($verbOut -match 'AGAIN-EXIT=0') $verbOut
    Assert-True "and says the card is already archived, naming where" ($verbOut -match '\[=\] Already archived: .*archive/TaskK7M2-made-to-be-archived\.prompt\.md') $verbOut
    Assert-True "and states no refusal" ($verbOut -notmatch '(?m)^Error: ') $verbOut
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $verbBase -Recurse -Force -ErrorAction SilentlyContinue }

# -- Already archived is done, not an error -------------------------------------
# Archive touches no tracker, so archiving a card that has already moved changes
# nothing anywhere -- and the board's drop onto Done from a stale view should
# report success.
# An id or an exact filename counts. A partial name never does, and a card in
# neither folder is still a refusal.

Write-Host "-- Already archived is success ------------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-ArchiveFile $sandbox 'US-119-import-flow.prompt.md'
    Add-ArchiveFile $sandbox 'Task140-rounds-r1.prompt.md'
    Add-ArchiveFile $sandbox 'Task140-rounds-r2.prompt.md'
    Add-CurrentFile $sandbox 'Task141-still-here.prompt.md'
    Save-SandboxState $sandbox
    $beforeCommits = (Get-CommitSubjects $sandbox).Count

    $output = Invoke-Archive @{ File = '119' }
    Assert-Equal "an archived id exits 0" 0 $script:LastArchiveExit
    Assert-Contains "and names where it is" $output '[=] Already archived: archive/US-119-import-flow.prompt.md'
    Assert-True "and states no refusal" ($output -notmatch '(?m)^Error: ')

    $output = Invoke-Archive @{ File = 'US-119-import-flow.prompt.md' }
    Assert-Equal "an archived exact filename exits 0" 0 $script:LastArchiveExit

    $output = Invoke-Archive @{ File = '140' }
    Assert-Equal "an id archived in rounds exits 0" 0 $script:LastArchiveExit
    Assert-True "and names every round" ($output -match 'Task140-rounds-r1' -and $output -match 'Task140-rounds-r2') $output

    $output = Invoke-Archive @{ File = 'import-flow' }
    Assert-Equal "a PARTIAL name of an archived card is still a refusal" 2 $script:LastArchiveExit

    $output = Invoke-Archive @{ File = '404' }
    Assert-Equal "an id in neither folder is still a refusal" 2 $script:LastArchiveExit
    Assert-Contains "with the same sentence" $output "No card with id '404' in current/."

    Assert-Equal "none of it created a commit" 0 ((Get-CommitSubjects $sandbox).Count - $beforeCommits)
    Assert-True "and the card in current/ was not touched" (Test-Path (Join-Path $sandbox 'current/Task141-still-here.prompt.md'))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- One table, two readers --------------------------------------------------------
# Tests/fixtures/parsers/card-ids.json is read here AND by Tests/test_parsers.py.
# If PowerShell and Python ever disagree about a row, one of them is wrong.

Write-Host "-- The id rule agrees with the shared table -----------" -ForegroundColor Cyan

. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CardName.ps1')
$idTable = Get-Content (Join-Path $PSScriptRoot 'fixtures/parsers/card-ids.json') -Raw | ConvertFrom-Json
$tableTypes = @{}
foreach ($prefix in $idTable.prefixes) { $tableTypes["type$prefix"] = @{ FilePrefix = [string]$prefix } }
$tablePattern = Get-P20CardIdPattern -WorkItemTypes $tableTypes
foreach ($row in $idTable.names) {
    $got = Get-P20CardId -Name ([string]$row[0]) -Pattern $tablePattern
    $want = $row[1]
    $shown = if ($null -eq $want) { '(no id)' } else { [string]$want }
    Assert-True "'$($row[0])' -> $shown" (($null -eq $want -and $null -eq $got) -or ($null -ne $want -and [string]$got -ceq [string]$want)) "got [$got]"
}
foreach ($row in $idTable.arguments) {
    Assert-Equal "the argument '$($row[0])' is $(if ($row[1]) { 'an id' } else { 'a name' })" ([bool]$row[1]) (Test-P20IsCardId ([string]$row[0]))
}
Assert-True 'Get-P20CardId returns a string, not a number' ((Get-P20CardId -Name '141-x.prompt.md' -Pattern $tablePattern) -is [string])

Write-Host ""

# -- The `> Previous round:` token: one fixture, two readers -------------------------
# Tests/fixtures/parsers/previous-round.md is read here AND by Tests/test_parsers.py
# (previous_round). The line is written by NewPrompt, re-aimed by Archive's link
# refresh, and read by the agent.

Write-Host "-- The previous-round line agrees with the shared fixture" -ForegroundColor Cyan

. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Repair-CardLinks.ps1')
$prevFixture = Get-Content (Join-Path $PSScriptRoot 'fixtures/parsers/previous-round.md') -Raw
Assert-Equal 'the fixture names its previous round' '../archive/59-redirect-uri-mismatch-on-localhost-with-trailing-slash-r2.prompt.md' (Get-P20PreviousRoundPath $prevFixture)
Assert-Equal 'the same with CRLF line endings' '../archive/59-redirect-uri-mismatch-on-localhost-with-trailing-slash-r2.prompt.md' (Get-P20PreviousRoundPath ($prevFixture -replace "`n", "`r`n"))
Assert-True 'a card with no such line has none' ($null -eq (Get-P20PreviousRoundPath (Get-Content (Join-Path $PSScriptRoot 'fixtures/parsers/active.md') -Raw)))

# Archive renames a plain earlier round to -r1 when the next one lands, so the name
# the line carries can go stale; the link refresh re-aims it at the latest round.
$sandbox = New-ArchiveSandbox
try {
    $arch = Join-Path $sandbox 'archive'
    $cur = Join-Path $sandbox 'current'
    foreach ($d in @($arch, $cur)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    Write-FixtureText (Join-Path $arch 'Task77-widget-r1.prompt.md') '# one'
    Write-FixtureText (Join-Path $arch 'Task77-widget-r2.prompt.md') '# two'
    $cardPath = Join-Path $cur 'Task77-widget.prompt.md'
    [System.IO.File]::WriteAllText($cardPath, "# Task 77: widget`n`n> Previous round: ../archive/Task77-widget.prompt.md`n`n## Branch`nx`n")
    $changed = Repair-P20CardLinks -Path $cardPath
    Assert-True 'a stale previous-round line is rewritten' $changed
    Assert-Equal 'and re-aimed at the latest earlier round' '../archive/Task77-widget-r2.prompt.md' (Get-P20PreviousRoundPath (Get-Content $cardPath -Raw))
    Assert-True 'and a second pass writes nothing' (-not (Repair-P20CardLinks -Path $cardPath))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- A bare call refuses -------------------------------------------------------
# It used to Write-Warning and return, leaving $LASTEXITCODE untouched -- which
# through the bridge reads exactly like an archive that worked.

Write-Host "-- A bare call refuses -------------------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-610-present.prompt.md'
    Save-SandboxState $sandbox

    $output = Invoke-Archive @{}

    Assert-Contains "A bare call states the reason" $output 'no card given.'
    Assert-Contains "A bare call hints at -List" $output '-List'
    Assert-Equal "A bare call exits 2 (a stated refusal)" 2 $script:LastArchiveExit
    Assert-True "A bare call moves nothing" ((Get-ChildItem (Join-Path $sandbox 'archive') -File).Count -eq 0)
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- A partial name names its target before it moves ---------------------------
# The convenience survives for NON-digit arguments, but it stops being silent:
# the "Moved:" line is no longer the first time the user learns which card this
# was. Through the bridge there is nobody to read that line, so an inexact match
# refuses instead -- TOOLKIT_QUIET_STARTUP is how a non-interactive caller says
# so (AGENTS.md, "The refusal contract").

Write-Host "-- A partial name names its target -------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-700-widget-sprocket.prompt.md'
    Save-SandboxState $sandbox

    $output = Invoke-Archive @{ File = 'widget' }

    Assert-Contains "The partial match names the card it chose" $output "Matched 'widget' -> US-700-widget-sprocket.prompt.md"
    Assert-True "The named card is the one that moved" (Test-Path (Join-Path $sandbox 'archive/US-700-widget-sprocket.prompt.md'))
    Assert-Equal "A named partial match still exits 0" 0 $script:LastArchiveExit
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-701-widget-sprocket.prompt.md'
    Save-SandboxState $sandbox

    $prevQuiet = $env:TOOLKIT_QUIET_STARTUP
    $env:TOOLKIT_QUIET_STARTUP = '1'
    try {
        $output = Invoke-Archive @{ File = 'widget' }
        Assert-Contains "A non-interactive caller is told the match was partial" $output 'only by partial name'
        Assert-Equal "A non-interactive partial match exits 2" 2 $script:LastArchiveExit
        Assert-True "and moves nothing" ((Get-ChildItem (Join-Path $sandbox 'archive') -File).Count -eq 0)

        # The exact filename is not a guess, so it still goes through.
        $null = Invoke-Archive @{ File = 'US-701-widget-sprocket.prompt.md' }
        Assert-True "An exact filename still archives for a non-interactive caller" (Test-Path (Join-Path $sandbox 'archive/US-701-widget-sprocket.prompt.md'))
    }
    finally {
        if ($null -eq $prevQuiet) { Remove-Item Env:\TOOLKIT_QUIET_STARTUP -ErrorAction SilentlyContinue }
        else { $env:TOOLKIT_QUIET_STARTUP = $prevQuiet }
    }
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- A hub that is not there ---------------------------------------------------
# On Windows: promptsRoot on an unmapped drive. It used to be a raw
# `Write-Error:` record and exit 0, so a card the tool could not even look for
# read as archived. A
# missing drive is not reproducible on macOS; a path under a folder that does
# not exist reaches the identical guard.

Write-Host "-- A hub that is not there ---------------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    $realRoot = $global:P20Config.PromptsRoot
    $global:P20Config = @{ PromptsRoot = (Join-Path $realRoot 'no-such-folder/hub'); StoreSync = 'none' }
    $output = Invoke-Archive @{ File = 'anything' }
    Assert-Contains "a missing hub is stated in words" $output 'Hub not found'
    Assert-Contains "and names where the path came from" $output 'config.local.json'
    Assert-True "and writes no raw error record" ($output -notmatch 'Write-Error') $output
    Assert-True "and no Join-Path stack trace" ($output -notmatch 'Cannot find drive|Cannot bind argument') $output
    Assert-Equal "and exits 2 rather than reporting success" 2 $script:LastArchiveExit
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# A successful archive is still exit 0 -- the contract has two halves and this
# is the one a regression would quietly break.
$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-601-happy.prompt.md'
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-601-happy.prompt.md' }
    Assert-Equal "A successful archive exits 0" 0 $script:LastArchiveExit
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- Closed-date stamp --------------------------------------------------------

Write-Host "-- Closed date stamp ---------------------------------" -ForegroundColor Cyan

$today = Get-Date -Format 'yyyy-MM-dd'

# Stamped on a normal archive.
$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-900-dates.prompt.md' "# US-900`n`n**ADO Link:** http://x/900`n**Created:** 2026-01-02`n"
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-900-dates.prompt.md' }

    $archived = Get-Content (Join-Path $sandbox 'archive/US-900-dates.prompt.md') -Raw
    Assert-True "Closed date stamped on archive" ($archived -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}')
    Assert-Contains "Closed date is today" $archived "**Closed:** $today"
    Assert-Contains "Created date preserved" $archived '**Created:** 2026-01-02'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# A file that already carries a Closed date keeps its ORIGINAL one. Re-archiving
# must not rewrite when the work actually finished -- that is the whole value of
# the stamp for reporting.
$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'US-901-dates.prompt.md' "# US-901`n`n**Created:** 2026-01-02`n**Closed:** 2020-05-05`n"
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-901-dates.prompt.md' }

    $archived = Get-Content (Join-Path $sandbox 'archive/US-901-dates.prompt.md') -Raw
    Assert-Contains "Existing closed date is not rewritten" $archived '**Closed:** 2020-05-05'
    $count = ([regex]::Matches($archived, '(?m)^\*\*Closed:\*\*')).Count
    Assert-Equal "Exactly one closed-date line" 1 $count
    Assert-True "Today's date not added" ($archived -notmatch [regex]::Escape("**Closed:** $today"))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# A file with no trailing newline must not have the stamp glued onto its last line.
$sandbox = New-ArchiveSandbox
try {
    $path = Join-Path (Join-Path $sandbox 'current') 'US-902-dates.prompt.md'
    [System.IO.File]::WriteAllText($path, "# US-902`n**ADO Link:** http://x/902")
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-902-dates.prompt.md' }

    $archived = Get-Content (Join-Path $sandbox 'archive/US-902-dates.prompt.md') -Raw
    Assert-True "Stamp starts on its own line" ($archived -match '(?m)^\*\*Closed:\*\*')
    Assert-True "Previous last line intact" ($archived -match '(?m)^\*\*ADO Link:\*\* http://x/902\s*$')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- The bytes the stamp writes (host independence) ---------------------------
#
# The stamp used to be appended with a bare "`n" and written with
# Set-Content -Encoding UTF8. Both of those are host-dependent: 5.1 emits a BOM
# where 7 does not, and a bare LF into a CRLF file leaves one odd line at the
# end. On a hub with storeSync: git that is a whole-file diff per archive on one
# host and a one-line diff on the other, for the same verb on the same card.
# The contract now: no BOM, ever, and the line ending the FILE already uses.
#

Write-Host "-- Stamp bytes are the same on every host -------------" -ForegroundColor Cyan

function Get-CardBytes {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.IO.File]::ReadAllText($Path)
    return [pscustomobject]@{
        HasBom  = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        Crlf    = ([regex]::Matches($text, "`r`n")).Count
        BareLf  = ([regex]::Matches($text, "(?<!`r)`n")).Count
        Text    = $text
    }
}

# A CRLF card, written with a BOM, exactly as NewPrompt used to leave one on a
# Windows hub.
$sandbox = New-ArchiveSandbox
try {
    $path = Join-Path (Join-Path $sandbox 'current') 'US-903-crlf.prompt.md'
    $body = "# US-903`r`n`r`n**ADO Link:** http://x/903`r`n**Created:** 2026-01-02`r`n"
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding($true)))
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-903-crlf.prompt.md' }

    $b = Get-CardBytes (Join-Path $sandbox 'archive/US-903-crlf.prompt.md')
    Assert-True "A CRLF card comes back with no BOM" (-not $b.HasBom)
    Assert-Equal "A CRLF card gains no bare LF" 0 $b.BareLf
    Assert-Equal "A CRLF card is still all CRLF, stamp included" 5 $b.Crlf
    Assert-True "The stamp is there" ($b.Text -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# The same card with LF endings and no BOM -- what the tool writes now.
$sandbox = New-ArchiveSandbox
try {
    $path = Join-Path (Join-Path $sandbox 'current') 'US-904-lf.prompt.md'
    $body = "# US-904`n`n**ADO Link:** http://x/904`n**Created:** 2026-01-02`n"
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding($false)))
    Save-SandboxState $sandbox
    $null = Invoke-Archive @{ File = 'US-904-lf.prompt.md' }

    $b = Get-CardBytes (Join-Path $sandbox 'archive/US-904-lf.prompt.md')
    Assert-True "An LF card comes back with no BOM" (-not $b.HasBom)
    Assert-Equal "An LF card gains no CR" 0 $b.Crlf
    Assert-Equal "An LF card ends up with one more line" 5 $b.BareLf
    Assert-True "The stamp is there" ($b.Text -match '(?m)^\*\*Closed:\*\* \d{4}-\d{2}-\d{2}')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# Both endings parse the same. The stamp is a contract with agent/ado/
# reporting.py, so the PowerShell side asserts what the Python side asserts in
# Tests/test_parsers.py: a CRLF card and an LF card yield the same date.
$sandbox = New-ArchiveSandbox
try {
    $crlfPath = Join-Path (Join-Path $sandbox 'current') 'US-905-crlf.prompt.md'
    $lfPath = Join-Path (Join-Path $sandbox 'current') 'US-906-lf.prompt.md'
    [System.IO.File]::WriteAllText($crlfPath, "# US-905`r`n`r`n**Closed:** 2026-03-04`r`n", (New-Object System.Text.UTF8Encoding($true)))
    [System.IO.File]::WriteAllText($lfPath, "# US-906`n`n**Closed:** 2026-03-04`n", (New-Object System.Text.UTF8Encoding($false)))

    $crlfText = Get-Content $crlfPath -Raw -Encoding UTF8
    $lfText = Get-Content $lfPath -Raw -Encoding UTF8
    $crlfDate = [regex]::Match($crlfText, '(?m)^\*\*Closed:\*\*\s*(\d{4}-\d{2}-\d{2})').Groups[1].Value
    $lfDate = [regex]::Match($lfText, '(?m)^\*\*Closed:\*\*\s*(\d{4}-\d{2}-\d{2})').Groups[1].Value
    Assert-Equal "A CRLF stamp parses to the same date as an LF one" $lfDate $crlfDate
    Assert-Equal "and that date is the one in the file" '2026-03-04' $crlfDate
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- The writer itself: create normalises, edit does not ----------------------
#
# The two halves of the byte contract, asserted on Write-CardText directly
# rather than through a verb, because the verbs are only correct if this is.
# The writer used to take the string it was given byte for byte and
# the create half was therefore untrue on Windows: `* text=auto` plus
# core.autocrlf=true checks the templates AND the scripts out CRLF, so every
# created card was CRLF there and LF on macOS, for the same verb into the
# same hub. -New is the fix,
# and it is on the ONE writer so no create path can implement it differently.

Write-Host "-- Write-CardText: -New creates LF, no -New edits -----" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1')

$writerDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-writer-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $writerDir -Force | Out-Null
try {
    $crlfBody = "# Card`r`n`r`n**Created:** 2026-01-02`r`n"

    $createPath = Join-Path $writerDir 'created.md'
    Write-CardText -Path $createPath -Content $crlfBody -New
    $c = Get-CardBytes $createPath
    Assert-Equal "-New turns a CRLF body into an LF file" 0 $c.Crlf
    Assert-Equal "-New keeps every line break it was given" 3 $c.BareLf
    Assert-True "-New writes no BOM" (-not $c.HasBom)

    $editPath = Join-Path $writerDir 'edited.md'
    Write-CardText -Path $editPath -Content $crlfBody
    $e = Get-CardBytes $editPath
    Assert-Equal "without -New a CRLF body stays CRLF" 3 $e.Crlf
    Assert-Equal "and gains no bare LF" 0 $e.BareLf
    Assert-True "and still writes no BOM" (-not $e.HasBom)

    # An LF body is LF either way -- -New must not be a second chance to get
    # the endings wrong.
    $lfPath = Join-Path $writerDir 'lf.md'
    Write-CardText -Path $lfPath -Content "# Card`n`n**Created:** 2026-01-02`n" -New
    $l = Get-CardBytes $lfPath
    Assert-Equal "-New leaves an LF body alone" 0 $l.Crlf
    Assert-Equal "and keeps its three line breaks" 3 $l.BareLf
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { if (Test-Path $writerDir) { Remove-Item $writerDir -Recurse -Force -ErrorAction SilentlyContinue } }

# Every create path in the package goes through it, with -New. A grep, because
# the alternative is one suite per verb for a rule that belongs to all of them.

Write-Host "-- Every create path passes -New ----------------------" -ForegroundColor Cyan

$createPaths = @(
    @{ Script = 'New-Meeting.ps1';             What = 'a manager session' }
    @{ Script = 'Get-MeetingAgenda.ps1';       What = 'a session scaffolded by MeetingAgenda' }
    @{ Script = 'New-PromptFromWorkItem.ps1';  What = 'a card' }
    @{ Script = 'New-GrowthItem.ps1';          What = 'a growth item' }
    @{ Script = 'Write-PeerReviewLog.ps1';     What = 'a peer-review record' }
)
foreach ($cp in $createPaths) {
    $srcPath = Join-Path $pkgRoot ('Scripts/' + $cp.Script)
    $src = Get-Content $srcPath -Raw
    Assert-True "$($cp.Script) creates $($cp.What) through Write-CardText -New" `
        ($src -match 'Write-CardText[^\r\n]*-New') 'no -New create call found'
    Assert-True "$($cp.Script) has no writer of its own" `
        ($src -notmatch '\[System\.IO\.File\]::WriteAllText') 'a second WriteAllText is still in this script'
}

Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

# ── Test: archive/ absent -- created, not silently skipped ─────────────────
# Found through the web bridge against the fixture hub: an org
# folder that has never archived anything has no archive/, Move-Item failed
# non-terminating, "Moved:" still printed, and the card stayed in current/.

Write-Host "── First archive into an org with no archive/ yet ──────" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Remove-Item -Path (Join-Path $sandbox 'archive') -Recurse -Force
    Add-CurrentFile $sandbox 'US-300-first-ever.prompt.md'
    Save-SandboxState $sandbox

    $r = Invoke-ArchiveCapture @{ File = 'US-300-first-ever.prompt.md' }

    Assert-True "archive/ was created" (Test-Path (Join-Path $sandbox 'archive'))
    Assert-True "Source file removed from current/" (-not (Test-Path (Join-Path $sandbox 'current/US-300-first-ever.prompt.md')))
    Assert-True "Destination file in archive/" (Test-Path (Join-Path $sandbox 'archive/US-300-first-ever.prompt.md'))

    # The round scan used to read archive/ before anything created it, so a
    # first archive printed a full red Get-ChildItem record and then reported
    # success -- exactly what docs/CLI.md's Errors section says this tool does
    # not do.
    $errText = ($r.Errors | ForEach-Object { $_.ToString() }) -join '; '
    Assert-True "Nothing was written to the error stream" ($r.Errors.Count -eq 0) $errText
    Assert-True "No 'cannot find path' in the output" ($r.Text -notmatch 'Cannot find path') $r.Text
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

# -- -WhatIf on a hub with no archive/ creates nothing --------------------------
# The create moved above the round scan; it must still stay behind -WhatIf, or a
# preview would leave a folder behind.

Write-Host "-- -WhatIf does not create archive/ --------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Remove-Item -Path (Join-Path $sandbox 'archive') -Recurse -Force
    Add-CurrentFile $sandbox 'US-301-preview.prompt.md'
    Save-SandboxState $sandbox

    $r = Invoke-ArchiveCapture @{ File = 'US-301-preview.prompt.md'; WhatIf = $true }

    Assert-True "-WhatIf left archive/ absent" (-not (Test-Path (Join-Path $sandbox 'archive')))
    Assert-True "-WhatIf left the card in current/" (Test-Path (Join-Path $sandbox 'current/US-301-preview.prompt.md'))
    Assert-True "-WhatIf wrote nothing to the error stream" ($r.Errors.Count -eq 0) (($r.Errors | ForEach-Object { $_.ToString() }) -join '; ')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

# -- A card archived before its first commit; a failed commit is a refusal ------
# A card created and archived with no commit in between has no tracked path in
# current/. The move used to stage exact file paths, so git aborted the whole
# add and the archive was left uncommitted behind a warning. It stages the two
# folders now, and a commit that fails is a stated refusal (exit 2) that says
# the file has already moved.

Write-Host "-- archive before the first commit ---------------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'Task701-never-committed.prompt.md'
    $out = Invoke-Archive @{ File = '701' }
    Assert-Equal "an untracked card archives with exit 0" 0 $script:LastArchiveExit
    Assert-True "the card is in archive/" (Test-Path (Join-Path $sandbox 'archive/Task701-never-committed.prompt.md'))
    Assert-True "the archive commit is in the log" ((Get-CommitSubjects $sandbox) -contains 'archive: move Task701-never-committed.prompt.md to archive') ((Get-CommitSubjects $sandbox) -join '; ')
    Push-Location $sandbox
    try { $dirty = @(git status --short) } finally { Pop-Location }
    Assert-True "the working tree is clean afterwards" ($dirty.Count -eq 0) ($dirty -join '; ')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host "-- a tracked card still commits as a rename ------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    Add-CurrentFile $sandbox 'Task702-tracked.prompt.md'
    Save-SandboxState $sandbox
    $out = Invoke-Archive @{ File = '702' }
    Assert-Equal "a tracked card archives with exit 0" 0 $script:LastArchiveExit
    Push-Location $sandbox
    try {
        $show = @(git show --name-status --format='%s' HEAD)
        $dirty = @(git status --short)
    }
    finally { Pop-Location }
    Assert-True "the last commit is the archive commit" ($show[0] -eq 'archive: move Task702-tracked.prompt.md to archive') ($show -join '; ')
    Assert-True "git records a rename" (($show -join ' ') -match 'R\d*\s+current/Task702-tracked\.prompt\.md\s+archive/Task702-tracked\.prompt\.md') ($show -join '; ')
    Assert-True "the working tree is clean afterwards" ($dirty.Count -eq 0) ($dirty -join '; ')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host "-- a failed commit is a stated refusal -----------------" -ForegroundColor Cyan

$sandbox = New-ArchiveSandbox
try {
    $hook = Join-Path $sandbox '.git/hooks/pre-commit'
    [System.IO.File]::WriteAllText($hook, "#!/bin/sh`necho 'hook says no'`nexit 1`n")
    # git runs a hook only when the file is executable; Windows has no execute bit, Unix does.
    if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod '+x' $hook }
    Add-CurrentFile $sandbox 'Task703-hook-refuses.prompt.md'
    $out = Invoke-Archive @{ File = '703' }
    Assert-Equal "a failed commit exits 2" 2 $script:LastArchiveExit
    Assert-Contains "the refusal says the file was moved" $out 'was moved to archive/'
    Assert-Contains "the refusal carries git's own sentence" $out 'hook says no'
    Assert-Contains "the refusal names the way out" $out 'Hint:'
    Assert-True "the card is in archive/" (Test-Path (Join-Path $sandbox 'archive/Task703-hook-refuses.prompt.md'))
    Assert-True "the card is gone from current/" (-not (Test-Path (Join-Path $sandbox 'current/Task703-hook-refuses.prompt.md')))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-ArchiveSandbox $sandbox }

Write-Host ""

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
