<#
.SYNOPSIS
    Tests for New-PromptFromWorkItem.ps1's OFFLINE form -- NewPrompt -Title.
.DESCRIPTION
    The ADO form of the verb needs a board. The -Title form needs nothing, which
    makes it the half of the command a suite can actually drive end to end, and
    it is the one a Tier-2 machine runs. Two contracts are pinned here:

      - The next free LOCAL id is the next number above the CARDS already filed
        in current/ and archive/, and nothing else. Both folders hold
        digit-bearing files that are not cards -- the PR-comment and review
        flows write dated "<date>-PR141415.prompt.md" into archive/, and a
        slug can carry a year of its own -- and the unanchored scan that used to
        run read the year as the highest id and numbered the next card Task2027.
       

      - The bytes. A card the tool writes is UTF-8 with NO BOM and LF line
        endings on every host. StringBuilder.AppendLine follows
        Environment.NewLine, so the same card used to come out CRLF on Windows
        and LF on macOS, and the BOM made a 5.1 archive rewrite every byte of
        the file. See Scripts/Add-ClosedStamp.ps1's Write-CardText for the other
        half of the contract.
       

    Each case runs the script in a child pwsh against a throwaway folder, which
    is the path a real offline run takes: the script defines its own fallbacks
    and needs no module imported.

    Run:  pwsh -File Tests/Test-NewPrompt.ps1
    Or:   {cliPrefix}TestToolkit -NewPrompt
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $testDir -Parent
$targetScript = Join-Path $pkgRoot 'Scripts/New-PromptFromWorkItem.ps1'
if (-not (Test-Path $targetScript)) {
    Write-Error "New-PromptFromWorkItem.ps1 not found at $targetScript"
    return
}

# -- Harness -------------------------------------------------------------------

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
    param([string]$TestName, [bool]$Condition, [string]$Detail)
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
    Assert-True $TestName ($Expected -eq $Actual) "expected [$Expected] got [$Actual]"
}

function New-PromptSandbox {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-newprompt-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $base 'current') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'archive') -Force | Out-Null
    return $base
}

function Remove-PromptSandbox {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) { Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue }
}

function Add-Card {
    # Seeds a file by NAME. The content is irrelevant to the id scan, which is
    # the point: the scan reads names, so the names are the fixture.
    param([string]$Sandbox, [string]$Folder, [string]$Name)
    Write-FixtureText (Join-Path (Join-Path $Sandbox $Folder) $Name) "# $Name"
}

function Invoke-NewPrompt {
    # Returns { Output, ExitCode, Created } -- Created is the file NAME the
    # command reports, which is where the resolved id shows up.
    param([string]$Sandbox, [string[]]$ScriptArgs)
    # 5.1 reads a native stderr line as a terminating error under 'Stop';
    # the child's stderr is text here. Local to this function.
    $ErrorActionPreference = 'Continue'
    $target = Join-Path $Sandbox 'current'
    $all = @('-OutputFolder', $target) + $ScriptArgs
    $output = (& pwsh -NoProfile -File $targetScript @all 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $exitCode = $LASTEXITCODE
    $created = ''
    $m = [regex]::Match($output, 'Created (\S+\.prompt\.md)')
    if ($m.Success) { $created = $m.Groups[1].Value }
    return [pscustomobject]@{ Output = $output; ExitCode = $exitCode; Created = $created }
}

# -- A card made after the fact: -Date is the day the work was ----------------
# A meeting attended yesterday, a call last week: **Created:** is that day, so
# Daily lands the card where it belongs.

Write-Host "-- -Date: the day the work was ------------------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Sprint review with the client', '-Type', 'Meeting', '-Date', '2026-09-18')
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    Assert-True 'a Meeting card is scaffolded from the shipped type' ($r.Created -and (Test-Path $path -PathType Leaf) -and $r.Created -like 'Meeting-*') $r.Output
    $text = if ($r.Created -and (Test-Path $path -PathType Leaf)) { [System.IO.File]::ReadAllText($path) } else { '' }
    Assert-True 'its Created stamp is the day given, not today' ($text -match '(?m)^\*\*Created:\*\* 2026-09-18$') $text
    Assert-True 'and the template is the meeting one' ($text -match '(?m)^## Who$' -and $text -match '(?m)^## Outcomes$') $text
    $bad = Invoke-NewPrompt $sandbox @('-Title', 'Nope', '-Date', 'yesterday')
    Assert-True 'a date that is not YYYY-MM-DD is a stated refusal' ($bad.ExitCode -eq 2 -and $bad.Output -match "Error: 'yesterday' is not a date") $bad.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""

# -- The bytes a card is written with ------------------------------------------

Write-Host "-- Host-independent bytes -----------------------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Byte contract', '-Type', 'Task')
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    Assert-True 'the card was written' (Test-Path $path) $r.Output

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True 'a scaffolded card has no BOM' (-not $hasBom) "first bytes $($bytes[0]),$($bytes[1]),$($bytes[2])"

    $text = [System.IO.File]::ReadAllText($path)
    $crlf = ([regex]::Matches($text, "`r`n")).Count
    Assert-Equal 'a scaffolded card is LF on every host' 0 $crlf
    Assert-True 'a scaffolded card still has lines' (([regex]::Matches($text, "`n")).Count -gt 5) $text
    Assert-True 'the card carries a Created stamp' ($text -match '(?m)^\*\*Created:\*\* \d{4}-\d{2}-\d{2}') $text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  NewPrompt (offline -Title) Tests" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# -- The id of a card with no work item -----------------------------------------
# It used to be "highest id in the org, plus one": an integer, which in
# an org that also has linked cards collides with a real work item number sooner
# or later, and which two machines generate identically before a sync. It is a
# short RANDOM id now (docs/hub/cards.md, "The filename"): four characters, at
# least one letter and one digit, no look-alike characters, never all digits.

Write-Host "-- A card with no work item gets a lettered id --------" -ForegroundColor Cyan

$idShape = '(?-i)[ACDEFGHJKMNPQRTUVWXY234679]{4}'
function Get-CreatedId {
    param([string]$Created, [string]$Prefix)
    $m = [regex]::Match($Created, '^' + [regex]::Escape($Prefix) + '([A-Z0-9]{4})-')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'First card here', '-Type', 'Task')
    Assert-Equal 'an offline scaffold exits 0' 0 $r.ExitCode
    Assert-True 'the file is Task{id}-{slug}, house style' ($r.Created -cmatch "^Task$idShape-first-card-here\.prompt\.md$") $r.Created
    $id = Get-CreatedId $r.Created 'Task'
    Assert-True 'the id has a letter AND a digit' (($id -cmatch '[A-Z]') -and ($id -match '[0-9]')) $id
    Assert-True 'the id is never all digits -- it cannot be mistaken for a work item' ($id -notmatch '^\d+$') $id
    Assert-True 'the output names the id' ($r.Output -match [regex]::Escape($id)) $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    # Linked cards with high numbers beside it: the OLD rule would have made 403.
    Add-Card $sandbox 'current' '402-timeout-on-large-files.prompt.md'
    Add-Card $sandbox 'current' 'Task401-add-retry-to-upload.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Not the next number', '-Type', 'Task')
    Assert-True 'it is NOT highest-plus-one' ($r.Created -notmatch '^Task403-') $r.Created
    Assert-True 'it is a lettered id' ($r.Created -cmatch "^Task$idShape-") $r.Created
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    $seen = @{}
    foreach ($n in 1..12) {
        $r = Invoke-NewPrompt $sandbox @('-Title', "Card number $n", '-Type', 'Bug')
        $seen[(Get-CreatedId $r.Created '')] = $true
    }
    Assert-Equal 'twelve cards, twelve different ids' 12 $seen.Count
    Assert-True 'a Bug is bare: {id}-{slug}' ($r.Created -cmatch "^$idShape-card-number-12\.prompt\.md$") $r.Created
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""
Write-Host "-- Every type keeps its house style --------------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Show the ticket', '-Type', 'UserStory')
    Assert-True 'a story is US-{id}-' ($r.Created -cmatch "^US-$idShape-show-the-ticket\.prompt\.md$") $r.Created
    Assert-True 'and its branch keeps the third segment' ($r.Output -cmatch "/$idShape/show-the-ticket") $r.Output
    $r = Invoke-NewPrompt $sandbox @('-Title', 'A whole feature', '-Type', 'Feature')
    Assert-True 'a feature is Feat-{id}-' ($r.Created -cmatch "^Feat-$idShape-") $r.Created

    # The Spike type (types are ADO's, plus Spike).
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Wallet ticket from a QR code', '-Type', 'Spike')
    Assert-Equal 'a Spike scaffolds' 0 $r.ExitCode
    Assert-True 'a spike is Spike-{id}-' ($r.Created -cmatch "^Spike-$idShape-wallet-ticket-from-a-qr-code\.prompt\.md$") $r.Created
    $spike = Get-Content (Join-Path (Join-Path $sandbox 'current') $r.Created) -Raw
    Assert-True 'its heading says Spike and its id' ($spike -cmatch "(?m)^# Spike ${idShape}: Wallet ticket from a QR code") ($spike.Substring(0, [Math]::Min(80, $spike.Length)))
    Assert-True 'it asks a Question, records Findings, ends in a Recommendation' (($spike -match '(?m)^## Question') -and ($spike -match '(?m)^## Findings') -and ($spike -match '(?m)^## Recommendation'))
    Assert-True 'it has NO Described Changes and NO Implementation Details -- a spike may have no PR' (($spike -notmatch '(?m)^## Described Changes') -and ($spike -notmatch '(?m)^## Implementation Details'))
    Assert-True 'it links the Spike template' ($spike -match 'Spike\.template\.md')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""
Write-Host "-- -Id: given, validated, never duplicated -------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    Add-Card $sandbox 'current' '140-a-bug.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Explicit id wins', '-Type', 'Task', '-Id', '77')
    Assert-Equal 'a NUMBER given with -Id is still honoured' 'Task77-explicit-id-wins.prompt.md' $r.Created

    $r = Invoke-NewPrompt $sandbox @('-Title', 'Chosen id', '-Type', 'Task', '-Id', 'k7m2')
    Assert-Equal 'a lettered id typed lowercase is written uppercase' 'TaskK7M2-chosen-id.prompt.md' $r.Created

    # current/ is protected from the keyboard too. This used to write a SECOND card
    # with the same id: the existing-card check sat after the offline branch.
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Chosen id again', '-Type', 'Task', '-Id', 'K7M2')
    Assert-Equal 'the same id again exits 0' 0 $r.ExitCode
    Assert-True 'and RETURNS the existing card' ($r.Output -match 'already in' -and $r.Output -match 'TaskK7M2-chosen-id\.prompt\.md') $r.Output
    Assert-Equal 'and writes no second card' 1 @(Get-ChildItem (Join-Path $sandbox 'current') -Filter 'TaskK7M2-*').Count

    foreach ($bad in @('TASK', 'KKKK', 'K7M0', 'K7M22', 'seven')) {
        $r = Invoke-NewPrompt $sandbox @('-Title', 'Bad id', '-Id', $bad)
        Assert-Equal "-Id $bad is refused (exit 2)" 2 $r.ExitCode
    }
    Assert-True 'the refusal says what an id is' ($r.Output -match 'at least one letter and one digit') $r.Output
    Assert-Equal 'a refused id writes nothing' 0 @(Get-ChildItem (Join-Path $sandbox 'current') -Filter '*bad-id*').Count

    # A lettered id with no -Title: there is no work item to fetch. It is the card
    # if it is here, and a stated refusal if it is not -- never a call to ADO.
    $r = Invoke-NewPrompt $sandbox @('K7M2')
    Assert-True 'NewPrompt K7M2 returns the card that is here' ($r.ExitCode -eq 0 -and $r.Output -match 'already in') $r.Output
    $r = Invoke-NewPrompt $sandbox @('Q4TN')
    Assert-Equal 'NewPrompt Q4TN, which is nowhere, is refused (exit 2)' 2 $r.ExitCode
    Assert-True 'and says it is not a work item number' ($r.Output -match 'not a work item number') $r.Output
    Assert-True 'and never tried ADO' ($r.Output -notmatch 'Fetching work item') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""

# -- What is NOT a card id -----------------------------------------------------
# Both of these sat in a real hub and both were once read as ids. They no longer
# feed a counter -- there is none -- but they must not be read as TAKEN ids either,
# nor stop a card being made.

Write-Host "-- A date and a year in a slug are not ids ------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    Add-Card $sandbox 'archive' '2026-05-14-PR141415.prompt.md'
    Add-Card $sandbox 'current' 'goal-2027-improve-test-coverage.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Nothing but noise', '-Type', 'Task')
    Assert-Equal 'a hub holding only non-cards still scaffolds' 0 $r.ExitCode
    Assert-True 'the year is not in the file name' ($r.Created -notmatch '202[0-9]') $r.Created
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""

# -- The card is already here ----------------------------------------------------
# NewPrompt <id> for a card that is already in the folder returns THAT card and
# writes nothing. The check
# runs before any ADO call, which is also what lets this suite cover the ID form
# at all: nothing here stubs `az`, and nothing has to.

Write-Host "-- An existing card is returned, not overwritten ------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'Timeout on large files', '-Type', 'Bug', '-Id', '140')
    $cardPath = Join-Path (Join-Path $sandbox 'current') $r.Created
    # What a day of work adds: notes, a commit bullet, the PR URL.
    Add-FixtureText $cardPath "`nDiagnosis: the reader never closes the stream.`n- 80e2168 close the stream`nPR URL: https://example.invalid/pr/35`n"
    $before = [System.IO.File]::ReadAllBytes($cardPath)

    $again = Invoke-NewPrompt $sandbox @('140')
    $after = [System.IO.File]::ReadAllBytes($cardPath)

    Assert-Equal 'a re-run exits 0 -- it is the card you asked for, not a refusal' 0 $again.ExitCode
    Assert-True 'and says the card is already there' ($again.Output -match 'Card 140 is already in') $again.Output
    Assert-True 'and names the file' ($again.Output -match [regex]::Escape($r.Created)) $again.Output
    Assert-True 'and says ADO was not contacted' ($again.Output -match 'ADO was not contacted') $again.Output
    Assert-True 'and never reaches the ADO fetch' ($again.Output -notmatch 'Fetching work item') $again.Output
    Assert-True 'the card is byte for byte what it was' ([System.Linq.Enumerable]::SequenceEqual($before, $after))
    Assert-Equal 'and it is still the only card' 1 @(Get-ChildItem (Join-Path $sandbox 'current') -Filter '*.prompt.md').Count

    # -Force means "reassign from another user" on this path. It must not become
    # a way to overwrite.
    $forced = Invoke-NewPrompt $sandbox @('140', '-Force')
    Assert-True '-Force does not overwrite either' ([System.Linq.Enumerable]::SequenceEqual($before, [System.IO.File]::ReadAllBytes($cardPath)))
    Assert-Equal '-Force also exits 0' 0 $forced.ExitCode
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    # By ID through the one card-name rule, not by the name this run would have
    # generated: a typed prefix and an old title are still card 140...
    Add-Card $sandbox 'current' 'Task140-the-title-it-had-last-week.prompt.md'
    $again = Invoke-NewPrompt $sandbox @('140')
    Assert-True 'a typed card with an old title is found by id' ($again.Output -match 'Task140-the-title-it-had-last-week') $again.Output

    # ...and an id is not a substring: 14 is not 140, and a dated record is no card.
    Add-Card $sandbox 'current' '2026-05-14-PR141415.prompt.md'
    $other = Invoke-NewPrompt $sandbox @('14')
    Assert-True 'card 140 does not answer for id 14' ($other.Output -notmatch 'is already in') $other.Output
    $dated = Invoke-NewPrompt $sandbox @('2026')
    Assert-True 'a dated PR record does not answer for id 2026' ($dated.Output -notmatch 'is already in') $dated.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    # A card with this id in archive/ is one that came back. Scaffolding it into
    # current/ again is the reopen flow, so archive/ must not block it.
    Add-Card $sandbox 'archive' '140-shipped-last-month.prompt.md'
    $reopen = Invoke-NewPrompt $sandbox @('140')
    Assert-True 'a card that is only in archive/ does not count as already here' ($reopen.Output -notmatch 'is already in') $reopen.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

# -- A card that comes back links to its earlier round --------------------
# Archive numbers the rounds (-r1, -r2) by the card's id at archive time, so NewPrompt
# numbers nothing: it writes the link under `> Template:` and says which round this is.

Write-Host "-- A card that came back names its previous round -----" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    Add-Card $sandbox 'archive' 'Task140-shipped-last-month-r1.prompt.md'
    Add-Card $sandbox 'archive' 'Task140-shipped-last-month-r2.prompt.md'
    Add-Card $sandbox 'archive' 'Task141-someone-else.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Id', '140', '-Title', 'Shipped last month, again', '-Type', 'Task')
    Assert-Equal 'the offline scaffold exits 0' 0 $r.ExitCode
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    $text = if ($r.Created -and (Test-Path $path -PathType Leaf)) { [System.IO.File]::ReadAllText($path) } else { '' }
    Assert-True 'the card carries the line, naming the LATEST round, relative to its folder' ($text -match '(?m)^> Previous round: \.\./archive/Task140-shipped-last-month-r2\.prompt\.md$') $text
    Assert-True 'directly under the Template line' ($text -match '(?m)^> Template: [^\n]*\n> Previous round: ') $text
    Assert-True 'the message says round 3 and names the file' ($r.Output -match '\[\*\] Round 3 of this card; previous round: archive/Task140-shipped-last-month-r2\.prompt\.md') $r.Output
    Assert-True 'nothing was quoted from the old card' ($text -notmatch '## Outcome') $text
    $again = Invoke-NewPrompt $sandbox @('-Id', '140', '-Title', 'Shipped last month, again', '-Type', 'Task')
    Assert-True 'current/ stays protected: the card already there is returned untouched' ($again.Output -match 'is already in' -and $again.Output -notmatch 'Round \d') $again.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    # A plain earlier archive (never numbered) is round 1.
    Add-Card $sandbox 'archive' '140-shipped-last-month.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Id', '140', '-Title', 'Back again', '-Type', 'Bug')
    Assert-True 'a plain archived card is round 1, so this is round 2' ($r.Output -match '\[\*\] Round 2 of this card; previous round: archive/140-shipped-last-month\.prompt\.md') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

$sandbox = New-PromptSandbox
try {
    Add-Card $sandbox 'archive' 'Task140-unrelated-r1.prompt.md'
    $r = Invoke-NewPrompt $sandbox @('-Title', 'A brand new card', '-Type', 'Task')
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    $text = if ($r.Created -and (Test-Path $path -PathType Leaf)) { [System.IO.File]::ReadAllText($path) } else { '' }
    Assert-True 'a card with no earlier round has no Previous round line' ($text -notmatch 'Previous round') $text
    Assert-True 'and no round message' ($r.Output -notmatch 'Round \d of this card') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

# -- -Design: a card bound to the design it is worked against ------------------
# TYPED as the verb, in a fresh shell that
# imports this package's manifest and nothing else, against a scratch hub with a
# design/ and a spec/ of its own -- and, for the repo half, a scratch git repository
# whose origin is the Space's. The line it writes is read back by the one CLI
# reader, Get-P20CardDesign, which the agent's card_design matches row for row.

Write-Host ""
Write-Host "-- -Design, typed as the verb -------------------------" -ForegroundColor Cyan

$dBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-np-design-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
try {
    . (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
    . (Join-Path $pkgRoot 'Scripts/Read-DesignTree.ps1')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $dHub = Join-Path $dBase 'hub'
    $dLog = Join-Path $dBase 'log'
    $dRepo = Join-Path $dBase 'widgets-repo'
    $elsewhere = Join-Path $dBase 'elsewhere'
    foreach ($d in @($dHub, $dLog, $dRepo, $elsewhere, (Join-Path $dHub 'design'), (Join-Path $dHub 'design/archive'), (Join-Path $dHub 'spec'), (Join-Path $dRepo 'design'))) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path $dHub 'hub.json'), (@'
{
  "hub": 1,
  "spaces": [
    { "slug": "solo",    "name": "Solo",    "status": "local", "promptsFolder": "solo",    "org": "" },
    { "slug": "widgets", "name": "Widgets", "status": "local", "promptsFolder": "widgets", "org": "https://github.com/acme/widgets" }
  ]
}
'@), $utf8)
    $boardId = 'ee925272-9564-4816-8944-e6b39c86339c'
    $lanesId = '53913fc8-08cc-4b3f-9da7-40050b690010'
    $twinA = 'ab12cd34-0000-4000-8000-000000000001'
    $twinB = 'ab12ef56-0000-4000-8000-000000000002'
    $repoOnly = '6c1f0a2e-5b7d-4c8e-9f10-112233445566'
    function Write-Doc([string]$Path, [string]$Id, [string]$Title) {
        [System.IO.File]::WriteAllText($Path, "---`nid: $Id`ndescription: `"x`"`n---`n`n# $Title`n`n## Problem`n`n**Created:** 2026-10-01`n", $utf8)
    }
    Write-Doc (Join-Path $dHub 'design/board-ideas.md') $boardId 'Board ideas: the [next] lane'
    Write-Doc (Join-Path $dHub 'design/lanes.md') $lanesId 'Lanes'
    Write-Doc (Join-Path $dHub 'spec/lanes.spec.md') $lanesId 'Lanes (spec)'
    Write-Doc (Join-Path $dHub 'design/twin-a.md') $twinA 'Twin A'
    Write-Doc (Join-Path $dHub 'design/archive/twin-b.md') $twinB 'Twin B'
    # The repo: one design of its own, and the board-ideas id promoted into it.
    Write-Doc (Join-Path $dRepo 'design/repo-note.md') $repoOnly 'Repo note'
    Write-Doc (Join-Path $dRepo 'design/board-ideas.md') $boardId 'Board ideas, in the product'
    $gitQuiet = { param([string[]]$GitArgs) & git @GitArgs 2>&1 | Out-Null }
    & $gitQuiet @('-C', $dRepo, 'init', '-q')
    & $gitQuiet @('-C', $dRepo, 'remote', 'add', 'origin', 'https://github.com/acme/widgets.git')
    & $gitQuiet @('-C', $elsewhere, 'init', '-q')
    & $gitQuiet @('-C', $elsewhere, 'remote', 'add', 'origin', 'https://github.com/someone/else.git')
    New-Item -ItemType Directory -Path (Join-Path $elsewhere 'design') -Force | Out-Null
    Write-Doc (Join-Path $elsewhere 'design/stranger.md') '7d2e4f60-1a2b-4c3d-8e9f-aabbccddeeff' 'Stranger'

    $prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    function Invoke-DesignVerb {
        param([string]$Space, [string]$Where, [string]$Commands)
        $ErrorActionPreference = 'Continue'
        $q = { param([string]$s) $s -replace "'", "''" }
        $pre = "`$env:PSModulePath = '$(& $q $pkgRoot)'; `$env:PROMPTS_ROOT = '$(& $q $dHub)'; `$env:P20_ACTIVE_SPACE = '$Space'; " +
            "`$env:P20_USAGE_LOG_DIR = '$(& $q $dLog)'; Set-Location '$(& $q $Where)'; " +
            "Import-Module '$(& $q $pkgRoot)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
        $out = (& pwsh -NoProfile -NonInteractive -Command ($pre + $Commands + "; 'EXIT=' + `$LASTEXITCODE") 2>&1 | ForEach-Object { "$_" }) -join "`n"
        return $out
    }
    function Get-NewCard([string]$Space, [string]$Filter) {
        return @(Get-ChildItem (Join-Path $dHub "$Space/current") -Filter $Filter -File -ErrorAction SilentlyContinue)
    }

    # A hub design, by its file's stem, from a folder that is no repository.
    $out = Invoke-DesignVerb 'solo' $dBase "${prefix}NewPrompt -Now -Title 'Lanes, part one' -Type Task -Design board-ideas"
    $card = Get-NewCard 'solo' 'Task*-lanes-part-one.prompt.md'
    Assert-True '-Design writes the card (exit 0)' ($card.Count -eq 1 -and $out -match 'EXIT=0') $out
    $text = ''
    $head = @()
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName); $head = @([System.IO.File]::ReadAllBytes($card[0].FullName))[0..2] }
    Assert-True 'the line names the design by its own title (a bracket made round), a link relative to the card, and its whole id' `
        ($text -match ('(?m)^> Design: \[Board ideas: the \(next\) lane\]\(\.\./\.\./design/board-ideas\.md\) ' + $boardId + '$')) $text
    Assert-True 'directly under the Template line' ($text -match '(?m)^> Template: [^\n]*\n> Design: ') $text
    Assert-True 'the card is still LF with no BOM' ($text -notmatch "`r" -and -not ($head.Count -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)) ($head -join ',')
    $read = Get-P20CardDesign -Text $text
    Assert-True 'the one reader reads it back: kind, title, link and id' ($read -and $read.Kind -eq 'design' -and $read.Id -eq $boardId -and $read.Link -eq '../../design/board-ideas.md' -and $read.Title -eq 'Board ideas: the (next) lane') ($read | Out-String)
    Assert-True 'the verb says which design, its state and where' ($out -match ('Worked against the design ' + $boardId.Substring(0, 8) + ' Board ideas: the \[next\] lane \(Design, the hub''s design/board-ideas\.md\)')) $out

    # By an id prefix; a design with a spec links its spec.
    $out = Invoke-DesignVerb 'solo' $dBase "${prefix}NewPrompt -Now -Title 'Lanes, part two' -Design 53913fc8"
    $card = Get-NewCard 'solo' 'Task*-lanes-part-two.prompt.md'
    $text = ''
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName) }
    Assert-True 'an id prefix of four or more names the design; one in Spec links its spec' ($text -match ('(?m)^> Design: \[Lanes\]\(\.\./\.\./spec/lanes\.spec\.md\) ' + $lanesId + '$')) $text

    # Two, and none: stated refusals, and no card.
    $before = @(Get-ChildItem (Join-Path $dHub 'solo/current') -File).Count
    $out = Invoke-DesignVerb 'solo' $dBase "${prefix}NewPrompt -Now -Title 'Which twin' -Design ab12"
    Assert-True 'a prefix that names two designs is refused, naming both (exit 2)' ($out -match "'ab12' names 2 designs" -and $out -match 'Twin A' -and $out -match 'Twin B' -and $out -match 'EXIT=2') $out
    $out2 = Invoke-DesignVerb 'solo' $dBase "${prefix}NewPrompt -Now -Title 'Nowhere' -Design no-such-design"
    Assert-True 'a name that resolves to nothing is refused (exit 2)' ($out2 -match "No design named 'no-such-design'" -and $out2 -match 'EXIT=2') $out2
    Assert-True 'and neither refusal writes a card' ((@(Get-ChildItem (Join-Path $dHub 'solo/current') -File).Count) -eq $before)
    Assert-True 'and each says it once, not wrapped in a generic error' (-not ($out -match 'exit code 2') -and -not ($out2 -match 'exit code 2')) ($out + $out2)

    # The repository you stand in, when it is the Space's: its design's GitHub page,
    # and one id in both trees is the repo's.
    $out = Invoke-DesignVerb 'widgets' $dRepo "${prefix}NewPrompt -Now -Title 'From the repo' -Design repo-note"
    $card = Get-NewCard 'widgets' 'Task*-from-the-repo.prompt.md'
    $text = ''
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName) }
    Assert-True 'a repo design is linked by its page on the Space''s GitHub repo' ($text -match ('(?m)^> Design: \[Repo note\]\(https://github\.com/acme/widgets/blob/HEAD/design/repo-note\.md\) ' + $repoOnly + '$')) ($out + "`n" + $text)
    $out = Invoke-DesignVerb 'widgets' $dRepo "${prefix}NewPrompt -Now -Title 'Promoted one' -Design $($boardId.Substring(0, 6))"
    $card = Get-NewCard 'widgets' 'Task*-promoted-one.prompt.md'
    $text = ''
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName) }
    Assert-True 'an id in the hub and in the repo is one design, and the repo''s copy is named' ($text -match '(?m)^> Design: \[Board ideas, in the product\]\(https://github\.com/acme/widgets/blob/HEAD/design/board-ideas\.md\) ') ($out + "`n" + $text)

    # A repository that is not the Space's is not read.
    $out = Invoke-DesignVerb 'widgets' $elsewhere "${prefix}NewPrompt -Now -Title 'Not ours' -Design stranger"
    Assert-True 'a repository whose origin is not the Space''s is not read for designs' ($out -match "No design named 'stranger'" -and $out -match 'EXIT=2') $out

    $out = Invoke-DesignVerb 'solo' $dBase "${prefix}NewPrompt -Help"
    Assert-True '-Help names -Design' ($out -match '-Design <name\|id>') $out
}
catch {
    Assert-True 'the -Design cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { if (Test-Path $dBase) { Remove-Item -Path $dBase -Recurse -Force -ErrorAction SilentlyContinue } }

# -- -From: an agenda line becomes a card -------------------------------------
# TYPED as the verb, in a fresh shell that imports this package's manifest and
# nothing else, against a scratch hub whose hub.json renames the meeting folder --
# so a record is found by the hub's folder name, never a literal. The line the verb
# writes is the shape Tests/fixtures/parsers/from-lines.json's rows read, which the
# agent's card_from_record is held to.

Write-Host ""
Write-Host "-- -From, typed as the verb ---------------------------" -ForegroundColor Cyan

$fBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-np-from-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
try {
    . (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $fHub = Join-Path $fBase 'hub'
    $fLog = Join-Path $fBase 'log'
    foreach ($d in @($fHub, $fLog, (Join-Path $fHub 'meetings/current'), (Join-Path $fHub 'meetings/archive'), (Join-Path $fHub 'solo/current'), (Join-Path $fHub 'solo/backlog'))) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path $fHub 'hub.json'), (@'
{
  "hub": 1,
  "spaces": [
    { "slug": "solo", "name": "Solo", "status": "local", "promptsFolder": "solo", "org": "" }
  ],
  "folders": { "manager": "meetings" }
}
'@), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $fHub 'meetings/current/2026-10-28.md'), "# 1:1 -- 2026-10-28`n`n## Agenda`n`n- Chase the cert renewal`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $fHub 'meetings/archive/client-weekly-2026-10-21.md'), "# client-weekly -- 2026-10-21`n`n## Agenda`n`n- Export the audit log`n", $utf8)

    $fPrefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $featuresVar = [string](Get-P20Consts).env.features
    function Invoke-FromVerb {
        # -Features is the module flags for the child, through the env override;
        # '{}' (every module off) unless a case says otherwise, so a shell that
        # holds a flag cannot change what a case sees.
        param([string]$Commands, [string]$Features = '{}')
        $ErrorActionPreference = 'Continue'
        $q = { param([string]$s) $s -replace "'", "''" }
        $pre = "`$env:$featuresVar = '$(& $q $Features)'; " +
            "`$env:PSModulePath = '$(& $q $pkgRoot)'; `$env:PROMPTS_ROOT = '$(& $q $fHub)'; `$env:P20_ACTIVE_SPACE = 'solo'; " +
            "`$env:P20_USAGE_LOG_DIR = '$(& $q $fLog)'; Set-Location '$(& $q $fBase)'; " +
            "Import-Module '$(& $q $pkgRoot)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
        return ((& pwsh -NoProfile -NonInteractive -Command ($pre + $Commands + "; 'EXIT=' + `$LASTEXITCODE") 2>&1 | ForEach-Object { "$_" }) -join "`n")
    }
    function Get-FromCard([string]$Folder, [string]$Filter) {
        return @(Get-ChildItem (Join-Path $fHub "solo/$Folder") -Filter $Filter -File -ErrorAction SilentlyContinue)
    }
    $fromStamp = [string](Get-P20Consts).stamps.from

    # The 1:1's record, by its stem, in the meeting folder's current/.
    $out = Invoke-FromVerb "${fPrefix}NewPrompt -Title 'Chase the cert renewal' -From 2026-10-28"
    $card = Get-FromCard 'backlog' 'Task*-chase-the-cert-renewal.prompt.md'
    Assert-True '-From writes the card (exit 0)' ($card.Count -eq 1 -and $out -match 'EXIT=0') $out
    $text = ''
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName) }
    Assert-True 'the card carries one From line naming the record''s stem' (([regex]::Matches($text, '(?m)^' + [regex]::Escape($fromStamp) + ' 2026-10-28$')).Count -eq 1) $text
    Assert-True 'in the footer, directly above Created, the way every footer line lands' ($text -match ('(?m)^\*\*ADO Link:\*\* [^\n]*\n' + [regex]::Escape($fromStamp) + ' 2026-10-28\n\*\*Created:\*\* ')) $text
    Assert-True 'and the card is still LF' ($text -notmatch "`r") $text
    Assert-True 'the verb says which record, in the hub''s own folder name' ($out -match 'From: the meeting record meetings/current/2026-10-28\.md') $out

    # A series' record, archived, named with .md: written without it.
    $out = Invoke-FromVerb "${fPrefix}NewPrompt -Now -Title 'Export the audit log' -Type Bug -From client-weekly-2026-10-21.md"
    $card = Get-FromCard 'current' '*export-the-audit-log.prompt.md'
    $text = ''
    if ($card.Count -eq 1) { $text = [System.IO.File]::ReadAllText($card[0].FullName) }
    Assert-True 'a series'' record in archive/, given with .md, is written without it' ($out -match 'EXIT=0' -and $text -match ('(?m)^' + [regex]::Escape($fromStamp) + ' client-weekly-2026-10-21$')) ($out + "`n" + $text)

    # A record that is not there, and a name that is not a record's: refused, nothing written.
    $before = @(Get-ChildItem (Join-Path $fHub 'solo') -Recurse -File).Count
    $out = Invoke-FromVerb "${fPrefix}NewPrompt -Title 'Nowhere' -From 2026-01-01"
    Assert-True 'a record that does not exist is a stated refusal naming the stem and the folders (exit 2)' ($out -match "No meeting record '2026-01-01' in meetings/current/ or meetings/archive/" -and $out -match 'EXIT=2') $out
    # Off means absent: with communication off (this case), MeetingAgenda is not a
    # verb, so the hint names the meeting folder; with it on, the hint names the verb.
    Assert-True 'with communication off, the hint names the meeting folder and not MeetingAgenda' ($out -match 'Hint:.*meetings/current/ or meetings/archive/' -and $out -notmatch 'MeetingAgenda') $out
    $outOn = Invoke-FromVerb "${fPrefix}NewPrompt -Title 'Nowhere' -From 2026-01-01" -Features '{"communication":true}'
    Assert-True 'with communication on, the same refusal''s hint names MeetingAgenda (exit 2)' ($outOn -match 'Hint:.*MeetingAgenda' -and $outOn -match 'EXIT=2') $outOn
    $out2 = Invoke-FromVerb "${fPrefix}NewPrompt -Title 'Not a record' -From ../solo/backlog/x"
    Assert-True 'a name that is not a record''s shape is refused the same way' ($out2 -match "No meeting record '\.\./solo/backlog/x'" -and $out2 -match 'EXIT=2') $out2
    Assert-True 'and neither refusal writes a card' ((@(Get-ChildItem (Join-Path $fHub 'solo') -Recurse -File).Count) -eq $before)
    Assert-True 'and each says it once, not wrapped in a generic error' (-not ($out -match 'exit code 2') -and -not ($out2 -match 'exit code 2')) ($out + $out2)

    # An existing card: returned as it is, no footer added.
    $existing = Get-FromCard 'current' '*export-the-audit-log.prompt.md'
    $existingId = ''
    if ($existing.Count -eq 1) { $existingId = [regex]::Match($existing[0].Name, '^[A-Za-z]*-?([A-Z0-9]{4})-').Groups[1].Value }
    $bytesBefore = if ($existing.Count -eq 1) { [System.IO.File]::ReadAllText($existing[0].FullName) } else { '' }
    $out = Invoke-FromVerb "${fPrefix}NewPrompt $existingId -Title 'Export the audit log' -From 2026-10-28"
    $bytesAfter = if ($existing.Count -eq 1) { [System.IO.File]::ReadAllText($existing[0].FullName) } else { '' }
    Assert-True 'an existing card is returned, exit 0, and says no From line was written' ($existingId -and $out -match 'EXIT=0' -and $out -match "Card $existingId is already in" -and $out -match 'No From line was written either') $out
    Assert-True 'and its file is untouched' ($bytesBefore -and $bytesBefore -ceq $bytesAfter) $bytesAfter

    $out = Invoke-FromVerb "${fPrefix}NewPrompt -Help"
    Assert-True '-Help names -From' ($out -match '-From <record>') $out
}
catch {
    Assert-True 'the -From cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { if (Test-Path $fBase) { Remove-Item -Path $fBase -Recurse -Force -ErrorAction SilentlyContinue } }

# -- A new card on an Azure DevOps Space starts in play -----------------------
# The team's backlog lives in Azure DevOps and that Space's board draws no Backlog
# lane (issue #178), so NewPrompt writes current/. TYPED as the verb, in a fresh
# shell, against a scratch hub with one Space per tracker; -Title is the offline
# form of the creating verb (no az), and the folder rule is the same code the <id>
# form runs. Only the address differs between the three Spaces.

Write-Host ""
Write-Host "-- A new card on an Azure DevOps Space is in play, typed as the verb ---" -ForegroundColor Cyan

$tBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-np-tracker-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
try {
    . (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $tHub = Join-Path $tBase 'hub'
    $tLog = Join-Path $tBase 'log'
    New-Item -ItemType Directory -Path $tHub, $tLog -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tHub 'hub.json'), (@'
{
  "hub": 1,
  "spaces": [
    { "slug": "azdo", "name": "Azure", "status": "active", "promptsFolder": "azdo", "org": "https://dev.azure.com/example" },
    { "slug": "gh", "name": "GitHub", "status": "active", "promptsFolder": "gh", "org": "https://github.com/example/repo" },
    { "slug": "solo", "name": "Solo", "status": "local", "promptsFolder": "solo", "org": "" }
  ]
}
'@), $utf8)
    $tPrefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $tFolders = (Get-P20Consts).folders
    function Invoke-TrackerVerb {
        param([string]$Space, [string]$Commands)
        $ErrorActionPreference = 'Continue'
        $q = { param([string]$s) $s -replace "'", "''" }
        $pre = "`$env:PSModulePath = '$(& $q $pkgRoot)'; `$env:PROMPTS_ROOT = '$(& $q $tHub)'; `$env:P20_ACTIVE_SPACE = '$Space'; " +
            "`$env:P20_USAGE_LOG_DIR = '$(& $q $tLog)'; Set-Location '$(& $q $tBase)'; " +
            "Import-Module '$(& $q $pkgRoot)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
        return ((& pwsh -NoProfile -NonInteractive -Command ($pre + $Commands + "; 'EXIT=' + `$LASTEXITCODE") 2>&1 | ForEach-Object { "$_" }) -join "`n")
    }
    function Get-TrackerCard([string]$Space, [string]$Folder, [string]$Filter) {
        return @(Get-ChildItem (Join-Path $tHub "$Space/$Folder") -Filter $Filter -File -ErrorAction SilentlyContinue)
    }

    $out = Invoke-TrackerVerb 'azdo' "${tPrefix}NewPrompt -Title 'Azure card' -Type Task -Id A7ED"
    Assert-True 'on an Azure DevOps Space NewPrompt writes the card under current/, with no -Now' ((Get-TrackerCard 'azdo' $tFolders.current 'TaskA7ED-*.prompt.md').Count -eq 1 -and (Get-TrackerCard 'azdo' $tFolders.backlog 'TaskA7ED-*.prompt.md').Count -eq 0 -and $out -match 'EXIT=0') $out
    Assert-True 'and the verb reports a path under current/' ($out -match ("Prompt: file://\S*/azdo/" + [regex]::Escape($tFolders.current) + "/TaskA7ED-")) $out

    $out = Invoke-TrackerVerb 'gh' "${tPrefix}NewPrompt -Title 'Hub card' -Type Task -Id G7HC"
    Assert-True 'on a GitHub Space the card is still planned, in backlog/' ((Get-TrackerCard 'gh' $tFolders.backlog 'TaskG7HC-*.prompt.md').Count -eq 1 -and (Get-TrackerCard 'gh' $tFolders.current 'TaskG7HC-*.prompt.md').Count -eq 0 -and $out -match 'EXIT=0') $out

    $out = Invoke-TrackerVerb 'solo' "${tPrefix}NewPrompt -Title 'Local card' -Type Task -Id K7CM"
    Assert-True 'on a local Space the card is still planned, in backlog/' ((Get-TrackerCard 'solo' $tFolders.backlog 'TaskK7CM-*.prompt.md').Count -eq 1 -and (Get-TrackerCard 'solo' $tFolders.current 'TaskK7CM-*.prompt.md').Count -eq 0 -and $out -match 'EXIT=0') $out
}
catch {
    Assert-True 'the tracker cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { if (Test-Path $tBase) { Remove-Item -Path $tBase -Recurse -Force -ErrorAction SilentlyContinue } }

# -- The work item's comments cannot be read: no token ------------------------
# The comments are fetched with a bearer token from `az account get-access-token`.
# An empty token used to skip the fetch with no message and write a card without
# the discussion; it is a stated refusal now (exit 2, one Error and one Hint), and
# nothing is written -- the work item is not assigned or moved either. A child
# shell carries a stand-in `az` function, which shadows any real one on the PATH.

Write-Host "-- No ADO token: a stated refusal, no card ------------" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $azLog = Join-Path $sandbox 'az-calls.txt'
    $driver = Join-Path $sandbox 'driver.ps1'
    $driverText = @'
param([string]$Sandbox, [string]$Script, [string]$Mode)
$global:P20Config = [pscustomobject]@{
    Org = 'https://dev.azure.com/example'; PromptsRoot = $Sandbox; PromptsFolder = 'current'
    Tenant = ''; ActiveOrgName = 'example'; Projects = @(); BranchUser = 'someone'; CommandPrefix = 'tk'
}
function global:az {
    Add-Content -Path (Join-Path $Sandbox 'az-calls.txt') -Value ($args -join ' ')
    $global:LASTEXITCODE = 0
    if ($args -contains 'get-access-token') {
        if ($Mode -eq 'EmptyToken') { return }
        if ($Mode -eq 'NoToken') { $global:LASTEXITCODE = 1; return 'ERROR: Please run az login to setup account.' }
        return 'a-token'
    }
    if ($args -contains 'show') {
        return '{"fields":{"System.WorkItemType":"Bug","System.Title":"Timeout on large files","System.State":"Active","System.AssignedTo":{"uniqueName":"someone@example.com"}}}'
    }
}
& $Script -OutputFolder (Join-Path $Sandbox 'current') -AssignTo 'someone@example.com' 77
exit $LASTEXITCODE
'@
    [System.IO.File]::WriteAllText($driver, $driverText, (New-Object System.Text.UTF8Encoding $false))

    $ErrorActionPreference = 'Continue'
    $out = (& pwsh -NoProfile -File $driver -Sandbox $sandbox -Script $targetScript -Mode NoToken 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    Assert-Equal 'an empty token exits 2, a stated refusal' 2 $code
    Assert-True 'it says the comments could not be read because no ADO token was available' ($out -match "Error: Could not read work item 77's comments: no ADO token was available") $out
    Assert-True 'and the hint names az login' ($out -match "Hint:\s+Run 'az login'") $out
    Assert-Equal 'and no card was written' 0 @(Get-ChildItem (Join-Path $sandbox 'current') -Filter '*.prompt.md').Count
    $azCalls = if (Test-Path $azLog) { [System.IO.File]::ReadAllText($azLog) } else { '' }
    Assert-True 'and the work item was never assigned or moved' ($azCalls -notmatch 'work-item update') $azCalls

    $empty = (& pwsh -NoProfile -File $driver -Sandbox $sandbox -Script $targetScript -Mode EmptyToken 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True 'az printing nothing and exiting 0 is refused the same way' ($LASTEXITCODE -eq 2 -and $empty -match 'no ADO token was available') $empty
    Assert-Equal 'and that wrote no card either' 0 @(Get-ChildItem (Join-Path $sandbox 'current') -Filter '*.prompt.md').Count

    # The same stand-in with a token gets past the check: the refusal is the token, not the harness.
    $ok = (& pwsh -NoProfile -File $driver -Sandbox $sandbox -Script $targetScript -Mode Token 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True 'with a token the same run does not refuse for it' ($ok -notmatch 'no ADO token was available') $ok
}
catch {
    Assert-True 'the no-token cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

Write-Host ""

# -- -Description: fills Context/Summary in place of (TBD) --------------------
# Offline only, beside -Title. Omitted, the card reads (TBD) exactly as before
# (CAE7); given, the text lands where the ADO-linked path puts a work item's own
# description -- ## Context for a Task, ## Summary for everything else.

Write-Host "-- -Description: fills Context/Summary, (TBD) when omitted ---" -ForegroundColor Cyan

$sandbox = New-PromptSandbox
try {
    $r = Invoke-NewPrompt $sandbox @('-Title', 'No description given', '-Type', 'Task')
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    $text = [System.IO.File]::ReadAllText($path)
    Assert-True 'omitted, a Task card still reads (TBD) under Context' ($text -match "(?m)^## Context`n\(TBD\)$") $text

    $r = Invoke-NewPrompt $sandbox @('-Title', 'Timeout on large files', '-Type', 'Bug', '-Description', 'Uploads over 2GB hang past the 60s gateway timeout.')
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    $text = [System.IO.File]::ReadAllText($path)
    Assert-True 'given, a non-Task card carries it under Summary' ($text -match "(?m)^## Summary`nUploads over 2GB hang past the 60s gateway timeout\.$") $text
    Assert-True 'and Summary itself is not (TBD)' ($text -notmatch "(?m)^## Summary`n\(TBD\)$") $text

    $multiLine = 'Second line of the diagnosis.' + [Environment]::NewLine + 'Third line.'
    $r = Invoke-NewPrompt $sandbox @('-Title', 'A task with real context', '-Type', 'Task', '-Description', $multiLine)
    Assert-Equal 'a multi-line -Description still exits 0' 0 $r.ExitCode
    $path = Join-Path (Join-Path $sandbox 'current') $r.Created
    $text = [System.IO.File]::ReadAllText($path)
    Assert-True 'under Context for a Task' ($text -match '(?m)^## Context$') $text
    Assert-True 'and every line is kept' ($text -match 'Second line of the diagnosis\.' -and $text -match 'Third line\.') $text
    Assert-True 'written LF, like the rest of the card' ($text -notmatch "`r`n") $text
}
catch {
    Assert-True 'the -Description cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-PromptSandbox $sandbox }

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
