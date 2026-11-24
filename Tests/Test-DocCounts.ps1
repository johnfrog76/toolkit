<#
.SYNOPSIS
    The test counts live in one machine-written file, and the documents keep
    to their shapes.
.DESCRIPTION
    The counts a full run prints -- the CLI per suite and in total, the pytest
    totals, the web totals -- used to be typed into AGENTS.md, VERIFY.md and
    docs/TESTING.md, and every pull request that added a test rewrote them, so
    two such pull requests always conflicted on the same lines. Now they live
    in docs/TEST-COUNTS.md alone, written at a release by
    Scripts/Write-TestCounts.ps1 from a full run's block, and this suite holds
    both sides of that:

      - no document it reads (the root's, docs/'s, web/'s, agent/'s and
        agentic/'s Markdown) types a count line outside docs/TEST-COUNTS.md --
        a per-suite list, `N suites, M assertions`, a pytest total or a web
        total -- and a finding names the file and the line;
      - docs/TEST-COUNTS.md is exactly the writer's text for its own block, the
        block is a full run's (four lines in their shapes, a total that is the
        sum of its suites), and it is as of consts.json's version;
      - the writer itself: a block round-trips, a malformed one or one from
        another tree is refused with exit 2 and a stated reason, -WhatIf
        writes nothing.

    It does NOT compare the counts with a run, or with the registry: between
    releases main moves on and the page does not, on purpose. The writer holds
    a block to the registry when it is written. The rule that the page changes
    only with the version is CI's (Scripts/Test-TestCountsChange.ps1, held by
    {cliPrefix}TestToolkit -TestAll).

    It also holds the root README to its job as the front door: at most
    120 lines, no build-history phrases, every relative link resolving, and the
    known gaps one link down in docs/KNOWN-GAPS.md -- each gap a block tied to
    the heading where a reader meets it, which links back, and to its issue.

    Run:  pwsh -File Tests/Test-DocCounts.ps1
    Or:   {cliPrefix}TestToolkit -DocCounts
#>
[CmdletBinding()]
param()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

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
    Assert-True $TestName ("$Expected" -eq "$Actual") "expected '$Expected', got '$Actual'"
}

Write-Host ""
Write-Host "  DocCounts -- the test counts live in one file, and the documents keep their shapes" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

. (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1')
. (Join-Path $pkgRoot 'Scripts/TestAll-Rules.ps1')
. (Join-Path $scriptDir 'Get-TestHost.ps1')
. (Join-Path $scriptDir 'Get-TestingDocDrift.ps1')
$driftDir = Join-Path $scriptDir 'fixtures/doc-counts'

$agentsPath = Join-Path $pkgRoot 'AGENTS.md'
$testingPath = Join-Path $pkgRoot 'docs/TESTING.md'
$verifyPath = Join-Path $pkgRoot 'VERIFY.md'
$testingText = ''
if (Test-Path -LiteralPath $testingPath) { $testingText = Get-Content -LiteralPath $testingPath -Raw -Encoding UTF8 }
$testingRows = @($testingText -split "\r?\n")

$cf = Get-P20TestCountsFile
$countsPath = Join-Path $pkgRoot $cf.Path
$constsVersion = [string]((Get-Content -LiteralPath (Join-Path $pkgRoot 'consts.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)

# -- The counts file ---------------------------------------------------------------
# The page the writer wrote, read back: its own block in its shapes, the writer's
# words exactly, and consts.json's version. The release pull request sets the
# version and runs the writer together, so a version bump alone fails here.
Write-Host "  The counts file" -ForegroundColor Cyan
Assert-True "$($cf.Path) exists" (Test-Path -LiteralPath $countsPath -PathType Leaf)
$countsText = ''
if (Test-Path -LiteralPath $countsPath -PathType Leaf) { $countsText = Get-Content -LiteralPath $countsPath -Raw -Encoding UTF8 }
$countsRead = Read-P20TestCountsFile -Text $countsText -ExpectedVersion $constsVersion
Assert-True "$($cf.Path) is the writer's page for a full run's block, as of consts.json's version ($constsVersion)" `
    (@($countsRead.Findings).Count -eq 0) (@($countsRead.Findings) -join ' | ')
if ($null -ne $countsRead.Block -and @($countsRead.Block.Findings).Count -eq 0) {
    Write-Host "  As of $($countsRead.Version): $($countsRead.Block.Lines[1]); $($countsRead.Block.Lines[2]); $($countsRead.Block.Lines[3])" -ForegroundColor DarkGray
}

# One row per shape the page can be wrong in, against a page the writer's own
# formatter made. No run and no registry: the page is held to itself.
$goodLines = @('Consts 10, Compat 20, Menu 30, Archive 5, Setup 5', '5 suites, 70 assertions', 'pytest: 12 passed, 1 skipped', 'web: 7 suites, 55 tests')
$goodPage = Format-P20TestCountsFile -Lines $goodLines -Version '1.2.3'
$pageTable = @(
    # why, text, consts.json's version, finding count, a fragment the finding must contain
    @('the writer''s page, as of consts.json''s version', $goodPage, '1.2.3', 0, ''),
    @('the same page checked out CRLF', $goodPage.Replace("`n", "`r`n"), '1.2.3', 0, ''),
    @('a page as of another version than consts.json''s', $goodPage, '1.2.4', 1, 'is as of version 1.2.3 and consts.json says 1.2.4'),
    @('a page that states no version', $goodPage.Replace('**1.2.3**', '1.2.3'), '1.2.3', 1, 'states no version'),
    @('a page with no block', $goodPage.Replace('```text', '```'), '1.2.3', 1, 'text block'),
    @('a total that is not the sum', $goodPage.Replace('70 assertions', '71 assertions'), '1.2.3', 1, 'the per-suite line sums to 70'),
    @('a suite count that is not the suites listed', $goodPage.Replace('5 suites, 70', '6 suites, 70'), '1.2.3', 1, 'the per-suite line lists 5'),
    @('a half that did not run', $goodPage.Replace('pytest: 12 passed, 1 skipped', 'pytest: not run -- this run did not include the agent half'), '1.2.3', 1, 'is not a pytest count'),
    @('a block of three lines', $goodPage.Replace("web: 7 suites, 55 tests`n", ''), '1.2.3', 1, 'has 3 line(s)'),
    @('words edited by hand', $goodPage.Replace('# Test counts', '# Test counts, by hand'), '1.2.3', 1, 'edited by hand')
)
foreach ($pc in $pageTable) {
    $got = @((Read-P20TestCountsFile -Text $pc[1] -ExpectedVersion $pc[2]).Findings)
    $okCase = ($got.Count -eq $pc[3]) -and (($pc[3] -eq 0) -or ($got[0] -like "*$($pc[4])*"))
    Assert-True "counts page fixture, $($pc[0]): $($pc[3]) finding(s)" $okCase ($got -join ' | ')
}

# -- The writer ----------------------------------------------------------------------
# Scripts/Write-TestCounts.ps1 run as the release runs it, on a scratch root that
# holds a consts.json: a block made of the registry's own suites round-trips, and
# everything else is refused before anything is written.
Write-Host ""
Write-Host "  The writer, Scripts/Write-TestCounts.ps1" -ForegroundColor Cyan
$writer = Join-Path $pkgRoot 'Scripts/Write-TestCounts.ps1'
$registryNames = @((Get-P20ToolkitSuiteRegistry).Keys)
$parts = @(); $sum = 0; $n = 0
foreach ($name in $registryNames) { $n++; $parts += "$name $n"; $sum += $n }
$blockLines = @(($parts -join ', '), "$($registryNames.Count) suites, $sum assertions", 'pytest: 12 passed, 1 skipped, 40 subtests', 'web: 7 suites, 55 tests')
$writeScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-test-counts-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $root = Join-Path $writeScratch 'root'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $root 'consts.json'), '{ "version": "1.2.3" }', $utf8)
    $page = Join-Path $root 'docs/TEST-COUNTS.md'
    $blockFile = Join-Path $writeScratch 'block.txt'
    [System.IO.File]::WriteAllText($blockFile, (($blockLines | ForEach-Object { "  $_" }) -join "`n") + "`n", $utf8)
    $want = Format-P20TestCountsFile -Lines $blockLines -Version '1.2.3'

    $said = (Invoke-P20TestHost -File $writer -Arguments @('-Root', $root, '-Path', $blockFile, '-WhatIf') | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True '-WhatIf prints the page and writes nothing, exit 0' (($LASTEXITCODE -eq 0) -and -not (Test-Path -LiteralPath $page) -and ($said -match [regex]::Escape($blockLines[1]))) "exit $LASTEXITCODE -- $said"

    $said = (Invoke-P20TestHost -File $writer -Arguments @('-Root', $root, '-Path', $blockFile) | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True 'a full run''s block is written, exit 0' (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $page)) "exit $LASTEXITCODE -- $said"
    $bytes = @()
    if (Test-Path -LiteralPath $page) { $bytes = [System.IO.File]::ReadAllBytes($page) }
    Assert-True 'the page is UTF-8 with no BOM and LF only' (($bytes.Count -gt 3) -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) -and (@($bytes | Where-Object { $_ -eq 13 }).Count -eq 0))
    $written = ''
    if (Test-Path -LiteralPath $page) { $written = [System.IO.File]::ReadAllText($page, $utf8) }
    Assert-True 'the page is the formatter''s text for the block and the version' ($written -ceq $want)
    $back = Read-P20TestCountsFile -Text $written -ExpectedVersion '1.2.3'
    Assert-True 'and it reads back: no finding, the same four lines' ((@($back.Findings).Count -eq 0) -and ((@($back.Block.Lines) -join '|') -ceq ($blockLines -join '|'))) (@($back.Findings) -join ' | ')

    # The whole transcript of a tkTest run, CRLF, the pytest line with its python:
    # the block is read after the heading and the page comes out the same.
    $transcript = Join-Path $writeScratch 'run.log'
    $runText = "  tkTest -- the three halves`r`n  cli    PASS  ...`r`n`r`n  $($cf.Heading)`r`n  $($blockLines[0])`r`n  $($blockLines[1])`r`n  pytest: 12 passed, 1 skipped, 40 subtests (via ~/.venv-toolkit/bin/python)`r`n  $($blockLines[3])`r`n`r`n  All three halves passed.`r`n"
    [System.IO.File]::WriteAllText($transcript, $runText, $utf8)
    $said = (Invoke-P20TestHost -File $writer -Arguments @('-Root', $root, '-Path', $transcript) | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True 'a CRLF transcript of the run gives the same page, so nothing is written' (($LASTEXITCODE -eq 0) -and ($said -match 'Nothing was written') -and ([System.IO.File]::ReadAllText($page, $utf8) -ceq $want)) "exit $LASTEXITCODE -- $said"

    # Piped in from PowerShell, as the help's third example.
    $root2 = Join-Path $writeScratch 'root2'
    New-Item -ItemType Directory -Path $root2 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $root2 'consts.json'), '{ "version": "1.2.3" }', $utf8)
    $null = Invoke-P20TestHost -Command "Get-Content -LiteralPath '$blockFile' -Encoding UTF8 | & '$writer' -Root '$root2'"
    $page2 = Join-Path $root2 'docs/TEST-COUNTS.md'
    Assert-True 'lines piped in are written the same' ((Test-Path -LiteralPath $page2) -and ([System.IO.File]::ReadAllText($page2, $utf8) -ceq $want))

    # Every refusal: exit 2, an Error: line with the reason, and the page as it was.
    $refusals = @(
        # why, block text, extra arguments, a fragment of the reason
        @('a half that did not run', ($blockLines[0..1] + @('pytest: NOT AVAILABLE -- no python with pytest was found: x', $blockLines[3])), @(), 'not a pytest count'),
        @('a block of two lines (tkTestToolkit alone)', $blockLines[0..1], @(), 'has 2 line(s)'),
        @('a total that is not the sum', ($blockLines[0], "$($registryNames.Count) suites, $($sum + 1) assertions", $blockLines[2], $blockLines[3]), @(), "sums to $sum"),
        @('a block from another tree', ((($parts | Select-Object -Skip 1) -join ', '), "$($registryNames.Count - 1) suites, $($sum - 1) assertions", $blockLines[2], $blockLines[3]), @(), 'registry'),
        @('a -Version that is not consts.json''s', $blockLines, @('-Version', '9.9.9'), 'consts.json says 1.2.3')
    )
    foreach ($rf in $refusals) {
        $bad = Join-Path $writeScratch 'bad.txt'
        [System.IO.File]::WriteAllText($bad, (@($rf[1]) -join "`n") + "`n", $utf8)
        $said = (Invoke-P20TestHost -File $writer -Arguments (@('-Root', $root, '-Path', $bad) + @($rf[2])) | ForEach-Object { [string]$_ }) -join "`n"
        $code = $LASTEXITCODE
        $same = ([System.IO.File]::ReadAllText($page, $utf8) -ceq $want)
        Assert-True "the writer refuses $($rf[0]): exit 2, the reason stated, nothing written" `
            (($code -eq 2) -and ($said -match '(?m)^Error: ') -and ($said -like "*$($rf[3])*") -and $same) "exit $code -- $said"
    }
    $said = (Invoke-P20TestHost -File $writer -Arguments @('-Root', $root, '-Path', (Join-Path $writeScratch 'absent.txt')) | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True 'the writer refuses a path with no file: exit 2, stated' (($LASTEXITCODE -eq 2) -and ($said -match '(?m)^Error: There is no file')) "exit $LASTEXITCODE -- $said"
}
catch {
    Assert-True 'the writer cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $writeScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# -- A single suite's row carries no count ------------------------------------------
# docs/TESTING.md says what each suite guards; how many assertions it has is the
# counts file's. A count typed into a single suite's own row goes stale.
Write-Host ""
Write-Host "  A single suite's row carries no count" -ForegroundColor Cyan
$suiteRows = @($testingRows | Where-Object { $_ -match '^\|\s*`tkTestToolkit -[A-Za-z]+`\s*\|' })
Assert-True 'docs/TESTING.md has single-suite rows to check' ($suiteRows.Count -gt 0)
foreach ($row in $suiteRows) {
    $suiteName = [regex]::Match($row, '`tkTestToolkit -([A-Za-z]+)`').Groups[1].Value
    # A bare count is a cell holding only a number, or a bolded number in prose.
    $bare = ($row -match '\|\s*\d+\s*\|') -or ($row -match '\*\*\d+\*\*')
    Assert-True "docs/TESTING.md's -$suiteName row carries no count of its own" (-not $bare) $row.Substring(0, [Math]::Min(120, $row.Length))
}

# -- What tkTest prints for the counts file -----------------------------------------
# The four lines under tkTest's heading: a half that did not run says so in its
# line's place, and the writer's block rule takes the first shape and refuses that.
Write-Host ""
Write-Host "  What tkTest prints for the counts file" -ForegroundColor Cyan
$recAgent = [ordered]@{ result = 'pass'; line = '12 passed, 1 skipped, 40 subtests passed in 3.0s' }
$recWeb = [ordered]@{ result = 'pass'; suites = 7; total = 55 }
$cliTwo = @('Consts 10, Compat 20, Menu 30', '3 suites, 60 assertions')
$pasteTable = @(
    @('all three ran', [ordered]@{ agent = $recAgent; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests|web: 7 suites, 55 tests'),
    @('agent skipped', [ordered]@{ agent = [ordered]@{ result = 'skip'; reason = 'no Python 3 on the PATH' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: NOT AVAILABLE -- no python with pytest was found: no Python 3 on the PATH|web: 7 suites, 55 tests'),
    @('agent ran through a venv', [ordered]@{ agent = [ordered]@{ result = 'pass'; line = $recAgent.line; python = '~/.venv-toolkit/bin/python' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests (via ~/.venv-toolkit/bin/python)|web: 7 suites, 55 tests'),
    @('agent ran through the PATH python', [ordered]@{ agent = [ordered]@{ result = 'pass'; line = $recAgent.line; python = 'python3 (PATH)' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests (via python3 (PATH))|web: 7 suites, 55 tests'),
    @('web failed, CLI partial', [ordered]@{ agent = $recAgent; web = [ordered]@{ result = 'fail' } }, @(), 'CLI: not printed -- the CLI half did not run every suite and pass|pytest: 12 passed, 1 skipped, 40 subtests|web: not printed -- the web half did not pass')
)
foreach ($pc in $pasteTable) {
    $pasted = @(Get-P20PasteLines -Records $pc[1] -CliLines $pc[2])
    Assert-Equal "tkTest's counts block, $($pc[0])" $pc[3] ($pasted -join '|')
    $blockTaken = (@((ConvertFrom-P20CountsBlock -Text ($pasted -join "`n")).Findings).Count -eq 0)
    $shouldTake = ($pc[0] -eq 'all three ran' -or $pc[0] -eq 'agent ran through a venv' -or $pc[0] -eq 'agent ran through the PATH python')
    Assert-True "and the writer's block rule $(if ($shouldTake) { 'takes' } else { 'refuses' }) it" ($blockTaken -eq $shouldTake)
}

# -- The front door stays the commercial ------------------------------------
# The root README is what every cold reader, and every cold model, reads first:
# what the product is, the three halves, the five verbs, the quick start and the
# Documentation table, in about a hundred lines. It prints no counts (those live in
# docs/TEST-COUNTS.md, checked below), no build history, and
# the known gaps are one link down in docs/KNOWN-GAPS.md. A commercial that grows
# back, or starts dating itself, is the regression this block names.
Write-Host ""
Write-Host "  The README is the front door" -ForegroundColor Cyan
$readmePath = Join-Path $pkgRoot 'README.md'
$readmeLines = @()
$readmeText = ''
if (Test-Path -LiteralPath $readmePath) {
    $readmeLines = @(Get-Content -LiteralPath $readmePath -Encoding UTF8)
    $readmeText = $readmeLines -join "`n"
}
$readmeMax = 120
Assert-True "README.md exists and is at most $readmeMax lines" `
    ((Test-Path -LiteralPath $readmePath) -and ($readmeLines.Count -le $readmeMax)) "$($readmeLines.Count) lines"

# Case-sensitive on purpose: "Since 20" and "since 20" are listed separately.
foreach ($phrase in @('Since 20', 'since 20', 'as of step', 'built 20')) {
    Assert-True "README.md carries no build history: no '$phrase'" (-not $readmeText.Contains($phrase))
}

# Every relative link resolves: a front door that points at a moved drawer is
# broken. External links and bare anchors are not files.
$readmeLinks = @([regex]::Matches($readmeText, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
$relativeLinks = @($readmeLinks | Where-Object { $_ -notmatch '^(https?|mailto):' -and $_ -notmatch '^#' })
Assert-True 'README.md has relative links to check' ($relativeLinks.Count -gt 0) "$($readmeLinks.Count) links in all"
$danglingLinks = @()
foreach ($link in $relativeLinks) {
    $target = $link.Split('#')[0]
    if (-not $target) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $pkgRoot $target))) { $danglingLinks += $link }
}
Assert-True 'every relative link in README.md resolves' ($danglingLinks.Count -eq 0) ($danglingLinks -join ', ')

$gapsPath = Join-Path $pkgRoot 'docs/KNOWN-GAPS.md'
Assert-True 'docs/KNOWN-GAPS.md exists (the known gaps live in the manual)' (Test-Path -LiteralPath $gapsPath)
$gapsText = ''
if (Test-Path -LiteralPath $gapsPath) { $gapsText = Get-Content -LiteralPath $gapsPath -Raw -Encoding UTF8 }
Assert-True 'docs/KNOWN-GAPS.md carries the heading "Known gaps"' `
    ($gapsText -match '(?m)^#+\s+Known gaps\s*$')

# -- Each known gap is tied to where a reader meets it, and to its issue ------
# docs/KNOWN-GAPS.md is one '### <title>' block per gap under '## Known gaps', each with
# a '**Where you meet it:**' link to a document and heading, and an '**Issue:**' line.
# The heading the Where line names links back to the gap, and every link into the
# page's anchors lands on a gap. A table row has no anchor, which is how the list
# drifted from the documents before; the anchor is the GitHub slug of the heading.
Write-Host ""
Write-Host "  Each known gap names where you meet it and its issue, and is linked back" -ForegroundColor Cyan

function ConvertTo-P20HeadingSlug {
    # GitHub's rule: lowercase; a link keeps its text; drop everything but letters,
    # digits, underscores, hyphens and spaces; each space becomes a hyphen.
    param([string]$Heading)
    $s = [regex]::Replace($Heading.Trim(), '\[([^\]]*)\]\([^)]*\)', '$1').ToLowerInvariant()
    $s = [regex]::Replace($s, '[^\p{L}\p{M}\p{N}\p{Pc} \-]', '')
    return $s.Replace(' ', '-')
}

function Get-P20DocLines {
    # The document's lines with every fenced line blanked, so a '#' in a code block
    # is not a heading and a link in one is not a link. Line numbers are kept.
    param([string]$Text)
    $lines = @(([string]$Text) -split "`r?`n")
    $fence = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^\s{0,3}(`{3,}|~{3,})')
        if ($fence) {
            if ($m.Success -and $m.Groups[1].Value.StartsWith($fence)) { $fence = '' }
            $lines[$i] = ''
        }
        elseif ($m.Success) {
            $fence = $m.Groups[1].Value
            $lines[$i] = ''
        }
    }
    return $lines
}

function Get-P20DocSections {
    # One row per heading: its level, title, slug (a repeat gets -1, -2 the way
    # GitHub numbers them), and its body -- up to the next heading at its level or above.
    param([string]$Text)
    $lines = @(Get-P20DocLines -Text $Text)
    $heads = @()
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^(#{1,6})\s+(.+?)\s*#*\s*$')
        if (-not $m.Success) { continue }
        $base = ConvertTo-P20HeadingSlug $m.Groups[2].Value
        $slug = $base
        if ($seen.ContainsKey($base)) { $seen[$base] = $seen[$base] + 1; $slug = "$base-$($seen[$base])" }
        else { $seen[$base] = 0 }
        $heads += [pscustomobject]@{ Level = $m.Groups[1].Value.Length; Title = $m.Groups[2].Value; Slug = $slug; Line = $i; End = $lines.Count; Body = '' }
    }
    for ($h = 0; $h -lt $heads.Count; $h++) {
        for ($k = $h + 1; $k -lt $heads.Count; $k++) {
            if ($heads[$k].Level -le $heads[$h].Level) { $heads[$h].End = $heads[$k].Line; break }
        }
        $first = $heads[$h].Line + 1
        $last = $heads[$h].End - 1
        if ($last -ge $first) { $heads[$h].Body = ($lines[$first..$last] -join "`n") }
    }
    return $heads
}

function Get-P20DocLinks {
    # Every markdown link target outside a fence; a code span is no link.
    param([string]$Text)
    $out = @()
    foreach ($line in @(Get-P20DocLines -Text $Text)) {
        $bare = [regex]::Replace($line, '`[^`]*`', '')
        foreach ($m in [regex]::Matches($bare, '\]\(([^)\s]+)\)')) { $out += $m.Groups[1].Value }
    }
    return $out
}

function Resolve-P20DocLink {
    # A relative link from one document to a package path and an anchor; $null for
    # an external link. Paths are package-relative, with forward slashes.
    param([string]$From, [string]$Link)
    if ($Link -match '^[A-Za-z][A-Za-z0-9+.-]*:') { return $null }
    $anchor = ''
    $path = $Link
    $hash = $Link.IndexOf('#')
    if ($hash -ge 0) { $anchor = $Link.Substring($hash + 1); $path = $Link.Substring(0, $hash) }
    if (-not $path) { return [pscustomobject]@{ Path = $From; Anchor = $anchor } }
    $parts = New-Object System.Collections.ArrayList
    if (-not $path.StartsWith('/')) {
        $dir = @($From -split '/')
        if ($dir.Count -gt 1) { foreach ($d in $dir[0..($dir.Count - 2)]) { [void]$parts.Add($d) } }
    }
    foreach ($seg in ($path -split '/')) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') { if ($parts.Count -gt 0) { $parts.RemoveAt($parts.Count - 1) }; continue }
        [void]$parts.Add($seg)
    }
    return [pscustomobject]@{ Path = ($parts -join '/'); Anchor = $anchor }
}

function Get-P20GapLinkFindings {
    # $Docs maps a package-relative path to its text. Returns one row per finding:
    # Kind (gaps, where, issue, backlink, inbound, outbound) and the sentence.
    param([hashtable]$Docs, [string]$GapsPath = 'docs/KNOWN-GAPS.md')
    $found = @()
    $sectionCache = @{}
    $getSections = {
        param($p)
        if (-not $sectionCache.ContainsKey($p)) { $sectionCache[$p] = @(Get-P20DocSections -Text $Docs[$p]) }
        return $sectionCache[$p]
    }
    if (-not $Docs.ContainsKey($GapsPath)) {
        return @([pscustomobject]@{ Kind = 'gaps'; Text = "$GapsPath is not read" })
    }
    $sections = @(& $getSections $GapsPath)
    $parent = @($sections | Where-Object { $_.Level -eq 2 -and $_.Title -eq 'Known gaps' }) | Select-Object -First 1
    if (-not $parent) {
        return @([pscustomobject]@{ Kind = 'gaps'; Text = "$GapsPath has no '## Known gaps' section" })
    }
    $gaps = @($sections | Where-Object { $_.Level -eq 3 -and $_.Line -gt $parent.Line -and $_.Line -lt $parent.End })
    if ($gaps.Count -eq 0) { $found += [pscustomobject]@{ Kind = 'gaps'; Text = "'## Known gaps' holds no '### ' gap" } }
    $gapSlugs = @($gaps | ForEach-Object { $_.Slug })

    foreach ($g in $gaps) {
        $where = [regex]::Match($g.Body, '(?m)^\*\*Where you meet it:\*\*\s*(.*)$')
        if (-not $where.Success) {
            $found += [pscustomobject]@{ Kind = 'where'; Text = "'$($g.Title)' has no **Where you meet it:** line" }
        }
        else {
            $wl = [regex]::Match($where.Groups[1].Value, '\]\(([^)\s]+)\)')
            $target = $null
            if ($wl.Success) { $target = Resolve-P20DocLink -From $GapsPath -Link $wl.Groups[1].Value }
            if (-not $target) {
                $found += [pscustomobject]@{ Kind = 'where'; Text = "'$($g.Title)': its Where line has no relative link" }
            }
            elseif (-not $Docs.ContainsKey($target.Path)) {
                $found += [pscustomobject]@{ Kind = 'where'; Text = "'$($g.Title)': $($target.Path) is not a document that is read" }
            }
            elseif (-not $target.Anchor) {
                $found += [pscustomobject]@{ Kind = 'where'; Text = "'$($g.Title)': its Where link names no heading" }
            }
            else {
                $section = @(& $getSections $target.Path | Where-Object { $_.Slug -eq $target.Anchor }) | Select-Object -First 1
                if (-not $section) {
                    $found += [pscustomobject]@{ Kind = 'where'; Text = "'$($g.Title)': $($target.Path)#$($target.Anchor) does not resolve" }
                }
                else {
                    $back = @(@(Get-P20DocLinks -Text $section.Body) | Where-Object {
                            $r = Resolve-P20DocLink -From $target.Path -Link $_
                            $r -and $r.Path -eq $GapsPath -and $r.Anchor -eq $g.Slug })
                    if ($back.Count -eq 0) {
                        $found += [pscustomobject]@{ Kind = 'backlink'; Text = "$($target.Path), ""$($section.Title)"", does not link back to #$($g.Slug)" }
                    }
                }
            }
        }
        $issue = [regex]::Match($g.Body, '(?m)^\*\*Issue:\*\*\s*(.*)$')
        if (-not $issue.Success) {
            $found += [pscustomobject]@{ Kind = 'issue'; Text = "'$($g.Title)' has no **Issue:** line" }
        }
        elseif (-not [regex]::IsMatch($issue.Groups[1].Value, '\[#\d+\]\(https://github\.com/[^/\s)]+/[^/\s)]+/issues/\d+\)')) {
            $found += [pscustomobject]@{ Kind = 'issue'; Text = "'$($g.Title)': its Issue line has no issue link" }
        }
    }

    foreach ($p in @($Docs.Keys)) {
        foreach ($link in @(Get-P20DocLinks -Text $Docs[$p])) {
            $r = Resolve-P20DocLink -From $p -Link $link
            if (-not $r) { continue }
            if ($r.Path -eq $GapsPath -and $r.Anchor -and ($gapSlugs -notcontains $r.Anchor)) {
                $found += [pscustomobject]@{ Kind = 'inbound'; Text = "$p links $link, which is not a gap heading" }
            }
        }
    }

    # Every other document's relative links: a link to a heading must land on one.
    foreach ($p in @($Docs.Keys)) {
        if ($p -eq $GapsPath) { continue }
        foreach ($link in @(Get-P20DocLinks -Text $Docs[$p])) {
            $r = Resolve-P20DocLink -From $p -Link $link
            if (-not $r -or -not $r.Anchor -or $r.Path -eq $GapsPath -or $r.Path -notlike '*.md' -or -not $Docs.ContainsKey($r.Path)) { continue }
            if (-not (@(& $getSections $r.Path | Where-Object { $_.Slug -eq $r.Anchor }).Count)) {
                $found += [pscustomobject]@{ Kind = 'link'; Text = "$p links $link, which does not resolve to a heading" }
            }
        }
    }

    # The page's other links -- a Where line's is the 'where' check's, above.
    $rest = [regex]::Replace([string]$Docs[$GapsPath], '(?m)^\*\*Where you meet it:\*\*.*$', '')
    foreach ($link in @(Get-P20DocLinks -Text $rest)) {
        $r = Resolve-P20DocLink -From $GapsPath -Link $link
        if (-not $r -or $r.Path -eq $GapsPath) { continue }
        if (-not $Docs.ContainsKey($r.Path)) {
            $found += [pscustomobject]@{ Kind = 'outbound'; Text = "$GapsPath links $link, which is not a document that is read" }
        }
        elseif ($r.Anchor -and -not (@(& $getSections $r.Path | Where-Object { $_.Slug -eq $r.Anchor }).Count)) {
            $found += [pscustomobject]@{ Kind = 'outbound'; Text = "$GapsPath links $link, which does not resolve" }
        }
    }
    return $found
}

# The check's own cases.
$slugCases = @(
    @('`Config -Set` cannot declare a Teams recipient', 'config--set-cannot-declare-a-teams-recipient'),
    @("``/env``'s ``communication`` block", 'envs-communication-block'),
    @("``spaceCheckouts.<slug>.path`` -- a Space's checkout on this machine", 'spacecheckoutsslugpath----a-spaces-checkout-on-this-machine'),
    @('Tiers: what happens when ADO does not answer', 'tiers-what-happens-when-ado-does-not-answer'),
    @('Most CLI suites run their verbs on PowerShell 7 under 5.1', 'most-cli-suites-run-their-verbs-on-powershell-7-under-51')
)
foreach ($c in $slugCases) {
    Assert-Equal "known gaps: the slug of '$($c[0])'" $c[1] (ConvertTo-P20HeadingSlug $c[0])
}
$dupSlugs = @(Get-P20DocSections -Text "## Known gaps`n`n## Known gaps`n" | ForEach-Object { $_.Slug })
Assert-Equal 'known gaps: a repeated heading is numbered the way GitHub numbers it' 'known-gaps|known-gaps-1' ($dupSlugs -join '|')
$crossDir = Resolve-P20DocLink -From 'web/README.md' -Link '../docs/KNOWN-GAPS.md#x'
Assert-Equal 'known gaps: a link from web/ resolves into docs/' 'docs/KNOWN-GAPS.md#x' "$($crossDir.Path)#$($crossDir.Anchor)"

$caseGap = "# Gaps`n`n## Known gaps`n`n### A thing is missing`n`n**What you see:** it is.`n`n" +
    "**Where you meet it:** [A](a.md#the-place), ""The place""`n`n**ISSUE**`n`n## True by design`n`nProse.`n"
$caseIssue = '**Issue:** [#1](https://github.com/o/r/issues/1)'
$caseA = "# A`n`n## The place`n`nText. Known gap: [A thing is missing](KNOWN-GAPS.md#a-thing-is-missing).`n`n## Elsewhere`n`nMore.`n"
$caseWeb = "# Web`n`nSee [the gap](../docs/KNOWN-GAPS.md#a-thing-is-missing).`n"
$gapCases = @(
    @{ Why = 'a gap with its Where, its Issue and a link back'; Kind = ''; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue); A = $caseA; Web = $caseWeb }
    @{ Why = 'a gap with no Issue line'; Kind = 'issue'; Gaps = $caseGap.Replace('**ISSUE**', ''); A = $caseA; Web = $caseWeb }
    @{ Why = 'an Issue line with no issue link'; Kind = 'issue'; Gaps = $caseGap.Replace('**ISSUE**', '**Issue:** to be filed'); A = $caseA; Web = $caseWeb }
    @{ Why = 'a Where anchor no heading has'; Kind = 'where'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue).Replace('#the-place', '#the-plaice'); A = $caseA; Web = $caseWeb }
    @{ Why = 'a heading inside a code fence'; Kind = 'where'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue); A = $caseA.Replace('## The place', "``````text`n## The place`n``````"); Web = $caseWeb }
    @{ Why = 'a section that does not link back'; Kind = 'backlink'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue); A = "# A`n`n## The place`n`nText.`n`n## Elsewhere`n`n[x](KNOWN-GAPS.md#a-thing-is-missing)`n"; Web = $caseWeb }
    @{ Why = 'a link on the page to a heading that is not there'; Kind = 'outbound'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue).Replace('it is.', 'it is ([A](a.md#nowhere)).'); A = $caseA; Web = $caseWeb }
    @{ Why = 'a link from another document to a heading that is not there'; Kind = 'link'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue); A = $caseA; Web = $caseWeb + "`n[x](../docs/a.md#nope)`n" }
    @{ Why = 'a document linking an anchor that is no gap'; Kind = 'inbound'; Gaps = $caseGap.Replace('**ISSUE**', $caseIssue); A = $caseA; Web = $caseWeb.Replace('#a-thing-is-missing', '#a-thing-was-missing') }
)
try {
    foreach ($case in $gapCases) {
        $caseDocs = @{ 'docs/KNOWN-GAPS.md' = $case.Gaps; 'docs/a.md' = $case.A; 'web/README.md' = $case.Web }
        $got = @(Get-P20GapLinkFindings -Docs $caseDocs)
        if ($case.Kind) {
            $ok = ($got.Count -eq 1) -and ($got[0].Kind -eq $case.Kind)
            Assert-True "known gaps: the check finds $($case.Why)" $ok (($got | ForEach-Object { "$($_.Kind): $($_.Text)" }) -join ' | ')
        }
        else {
            Assert-True "known gaps: the check passes $($case.Why)" ($got.Count -eq 0) (($got | ForEach-Object { "$($_.Kind): $($_.Text)" }) -join ' | ')
        }
    }
}
catch {
    Assert-True 'known gaps: the check cases ran to the end without a terminating error' $false $_.Exception.Message
}

# The real documents: every Markdown file a reader can follow a link from.
$gapDocs = @{}
$gapDocFiles = @(Get-ChildItem -LiteralPath $pkgRoot -Filter '*.md' -File)
$gapDocFiles += @(Get-ChildItem -LiteralPath (Join-Path $pkgRoot 'docs') -Filter '*.md' -File -Recurse)
foreach ($sub in @('web', 'agent', 'agentic')) {
    $subDir = Join-Path $pkgRoot $sub
    if (Test-Path -LiteralPath $subDir) { $gapDocFiles += @(Get-ChildItem -LiteralPath $subDir -Filter '*.md' -File) }
}
foreach ($f in $gapDocFiles) {
    $rel = $f.FullName.Substring($pkgRoot.Length).TrimStart('\', '/').Replace('\', '/')
    $gapDocs[$rel] = [string](Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8)
}
$gapFindings = @(Get-P20GapLinkFindings -Docs $gapDocs)
$gapCount = @(Get-P20DocSections -Text $gapDocs['docs/KNOWN-GAPS.md'] | Where-Object { $_.Level -eq 3 }).Count
$gapChecks = @(
    @('gaps', "docs/KNOWN-GAPS.md holds its gaps as '### ' blocks under '## Known gaps' ($gapCount read)"),
    @('where', 'every gap has a **Where you meet it:** link that resolves, file and heading'),
    @('issue', 'every gap has an **Issue:** line with an issue link'),
    @('backlink', "the heading each gap's Where names links back to that gap"),
    @('inbound', 'every link into docs/KNOWN-GAPS.md#... from a document lands on a gap heading'),
    @('outbound', 'every relative link in docs/KNOWN-GAPS.md resolves, file and heading'),
    @('link', 'every relative link from any other document to a heading in a document lands on one')
)
foreach ($gc in $gapChecks) {
    $hits = @($gapFindings | Where-Object { $_.Kind -eq $gc[0] } | ForEach-Object { $_.Text })
    Assert-True "known gaps: $($gc[1])" (($hits.Count -eq 0) -and ($gc[0] -ne 'gaps' -or $gapCount -gt 0)) ($hits -join ' | ')
}

# -- No document types a count ------------------------------------------------------
# The same documents: a count line typed anywhere in one -- prose, a table row, a
# code fence -- is a finding naming the file and the line, except in
# docs/TEST-COUNTS.md, the one page that states them. The shapes are
# Get-P20CountLinePatterns' Typed four (Scripts/TestAll-Rules.ps1).
Write-Host ""
Write-Host "  No document but $($cf.Path) types a test count" -ForegroundColor Cyan
$readDocs = @('AGENTS.md', 'VERIFY.md', 'docs/TESTING.md', $cf.Path)
$unread = @($readDocs | Where-Object { -not $gapDocs.ContainsKey($_) })
Assert-True "the documents read include $($readDocs -join ', ')" ($unread.Count -eq 0) ($unread -join ', ')
$typedFindings = @(Get-P20TypedCountLines -Docs $gapDocs)
Assert-True "no document types a count line outside $($cf.Path) ($($gapDocs.Count) documents read)" ($typedFindings.Count -eq 0) ($typedFindings -join ' | ')

# One row per shape and per document the counts used to be typed in. Each must be
# named by its file and line; a placeholder, a link and the counts page itself pass.
$typedTable = @(
    # why, path, text, finding count, the finding's start
    @('AGENTS.md''s runner line with a CLI total', 'AGENTS.md', "# A`n`n``````powershell`ntkTestToolkit   # the CLI -- 53 suites, 11177 assertions on this commit`n```````n", 1, "AGENTS.md, line 4: '53 suites, 11177 assertions'"),
    @('VERIFY.md''s Gate 4 sentence', 'VERIFY.md', "# V`n`nfindings. On this commit that is **53 suites, 11177 assertions** with a config`n", 1, "VERIFY.md, line 3: '53 suites, 11177 assertions'"),
    @('docs/TESTING.md''s per-suite row', 'docs/TESTING.md', "# T`n`n| ``tkTestToolkit`` | The CLI, per suite: Consts 244, Compat 1912, Menu 2205, Environment 86, Archive 217. |`n", 1, "docs/TESTING.md, line 3: 'Consts 244, Compat 1912"),
    @('docs/TESTING.md''s pytest command line', 'docs/TESTING.md', "# T`n`n``````bash`npython3 -m pytest Tests/     # 1585 passed, 6 skipped -- the agent`n```````n", 1, 'docs/TESTING.md, line 4:'),
    @('docs/TESTING.md''s web command line', 'docs/TESTING.md', "# T`n`ncd web && npm test           # 5 build-contract checks, then 185 suites, 2307 tests`n", 1, "docs/TESTING.md, line 3: '185 suites, 2307 tests'"),
    @('a pasted block in another document', 'docs/CONTRIBUTING.md', "# C`n`n  pytest: 1585 passed`n", 1, "docs/CONTRIBUTING.md, line 3: 'pytest: 1585 passed'"),
    @('two typed lines, two findings', 'VERIFY.md', "a 3 suites, 4 assertions`nb`nc web: 7 suites, 55 tests`n", 2, 'VERIFY.md, line 1:'),
    @('placeholders and a link to the counts page', 'AGENTS.md', "The total, ``N suites, M assertions``, is in [the counts](docs/TEST-COUNTS.md).`n", 0, ''),
    @('the counts page itself', $cf.Path, $goodPage, 0, '')
)
foreach ($tc in $typedTable) {
    $got = @(Get-P20TypedCountLines -Docs @{ $tc[1] = $tc[2] })
    $okCase = ($got.Count -eq $tc[3]) -and (($tc[3] -eq 0) -or ($got[0].StartsWith($tc[4])))
    Assert-True "typed count fixture, $($tc[0]): $($tc[3]) finding(s)" $okCase ($got -join ' | ')
}

# -- The runner counts a suite that did not report as a failure -------------
# Test-Toolkit.ps1 reads each child's score through Get-P20SuiteVerdict. A suite
# that threw before its Results line used to count 0/0 and leave the Total green.
Write-Host ""
Write-Host "  The runner's verdict on a suite's output" -ForegroundColor Cyan
$verdictTable = @(
    # output, exit, status, passed, failed, detail-like
    @('  Results: 12/12 passed', 0, 'PASS', 12, 0, ''),
    @('  Results: 10/12 passed', 1, 'FAIL', 10, 2, 'exit code 1'),
    @('  Results: 12/12 passed', 1, 'FAIL', 12, 1, 'exit code 1'),
    # A Results line QUOTED inside another line is not the score; the last real line is.
    @("  PASS  verdict: 'Results: 3/3 passed' exit 0`n  Results: 19/19 passed", 0, 'PASS', 19, 0, ''),
    @("  PASS  it quotes 'Results: 3/3 passed' and never reports", 0, 'FAIL', 0, 1, 'no Results line -- the suite threw?'),
    @('  Results: 10/12 passed', 0, 'FAIL', 10, 2, ''),
    @("  SKIP  git is not installed`n  Results: 0/0 passed", 0, 'WARN', 0, 0, '*skip*'),
    @('  PASS  one', 0, 'FAIL', 0, 1, 'no Results line*'),
    @("Exception: boom`n  finished", 1, 'FAIL', 0, 1, 'no Results line*exit 1*'),
    @('', 0, 'FAIL', 0, 1, 'no Results line*')
)
foreach ($row in $verdictTable) {
    $v = Get-P20SuiteVerdict -Output $row[0] -ExitCode $row[1]
    $label = "verdict: '$(($row[0] -split "`n")[-1].Trim())' exit $($row[1]) -> $($row[2]) $($row[3])/$($row[3] + $row[4])"
    $ok = ($v.Status -eq $row[2]) -and ($v.Passed -eq $row[3]) -and ($v.Failed -eq $row[4]) -and
        (($row[5] -eq '' -and $v.Detail -notlike 'no Results*') -or ($row[5] -ne '' -and $v.Detail -like $row[5]))
    Assert-True $label $ok "got $($v.Status) $($v.Passed)/$($v.Passed + $v.Failed) '$($v.Detail)'"
}

# The shape that hid the bug, for real: a scratch suite run the way the runner
# runs one (a child pwsh -File), throwing before it prints its Results line.
$scratchSuiteDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-throwing-suite-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $scratchSuiteDir -Force | Out-Null
    $throwing = Join-Path $scratchSuiteDir 'Test-Throws.ps1'
    # Stop, so the write's .NET exception ends the script on every host the way
    # an unhandled throw does -- the shape is "threw before Results", not how.
    Set-Content -LiteralPath $throwing -Encoding UTF8 -Value @'
$ErrorActionPreference = 'Stop'
Write-Host "  PASS  the first assertion"
$missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
try { [System.IO.File]::WriteAllText((Join-Path $missing 'x.txt'), 'x') } finally { }
Write-Host "  Results: 1/1 passed"
'@
    $childOut = (& pwsh -NoProfile -File $throwing 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $childExit = $LASTEXITCODE
    Assert-True 'a scratch suite that throws never reaches its Results line' `
        ($childOut -notmatch 'Results:') $childOut
    $v = Get-P20SuiteVerdict -Output $childOut -ExitCode $childExit
    Assert-True 'the runner counts it as ONE failed suite, not 0/0' `
        (($v.Status -eq 'FAIL') -and ($v.Failed -eq 1) -and ($v.Passed -eq 0)) "got $($v.Status) $($v.Passed)/$($v.Passed + $v.Failed)"
    Assert-True 'and says why: no Results line -- the suite threw?' `
        ($v.Detail -like 'no Results line -- the suite threw?*') $v.Detail
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $scratchSuiteDir -Recurse -Force -ErrorAction SilentlyContinue
}

$runnerSource = Get-Content -LiteralPath (Join-Path $scriptDir 'Test-Toolkit.ps1') -Raw
Assert-True 'the runner reads every suite through Get-P20SuiteVerdict' `
    ($runnerSource -match 'Get-P20SuiteVerdict\s+-Output\s+\$output\s+-ExitCode\s+\$exitCode')
Assert-True 'the runner keeps no Results regex of its own' `
    ($runnerSource -notmatch "-match\s+'Results:")

# -- VERIFY.md's coverage table names every verb -----------------------------
# "Why this file exists" carries one row per verb: the suite that types it, the gate that
# walks it, or "neither". It went stale once -- 26 commands, eight reached -- because
# nothing read it back. Every `commands.<Name>` in config.default.json, and every key of
# a module's Config/*.commands.psd1, must have a row; and a row must name a real verb.
Write-Host ""
Write-Host "  VERIFY.md's coverage table names every verb" -ForegroundColor Cyan
$verifyText = ''
if (Test-Path -LiteralPath $verifyPath) { $verifyText = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 }
$whyStart = $verifyText.IndexOf('## Why this file exists')
$whyEnd = $verifyText.IndexOf('## Gate 1 ')
Assert-True 'VERIFY.md has a "Why this file exists" section ahead of Gate 1' ($whyStart -ge 0 -and $whyEnd -gt $whyStart)
if ($whyStart -ge 0 -and $whyEnd -gt $whyStart) {
    $whyText = $verifyText.Substring($whyStart, $whyEnd - $whyStart)
    $tableVerbs = @([regex]::Matches($whyText, '(?m)^\|\s*`([A-Za-z]+)`\s*\|') | ForEach-Object { $_.Groups[1].Value })
    $defaultCfg = Get-Content -LiteralPath (Join-Path $pkgRoot 'config.default.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $coreVerbs = @($defaultCfg.commands.PSObject.Properties.Name)
    $moduleVerbs = @()
    foreach ($psd in @(Get-ChildItem -Path (Join-Path $pkgRoot 'Config') -Filter '*.commands.psd1' -ErrorAction SilentlyContinue)) {
        $moduleVerbs += @((Import-PowerShellDataFile -LiteralPath $psd.FullName).Commands.Keys)
    }
    $allVerbs = @($coreVerbs) + @($moduleVerbs)
    Assert-True "the table is read (config.default.json has $($coreVerbs.Count) verbs, the modules $($moduleVerbs.Count))" `
        ($coreVerbs.Count -gt 0 -and $tableVerbs.Count -gt 0)
    $missing = @($allVerbs | Where-Object { $tableVerbs -notcontains $_ })
    Assert-True 'every verb in config.default.json and the module data files has a row' ($missing.Count -eq 0) ($missing -join ', ')
    $stale = @($tableVerbs | Where-Object { $allVerbs -notcontains $_ })
    Assert-True 'no row names a verb that is not defined' ($stale.Count -eq 0) ($stale -join ', ')
    $dupes = @($tableVerbs | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-True 'no verb has two rows' ($dupes.Count -eq 0) ($dupes -join ', ')

    # The sentence above the table states the counts: "41 always-on, and the 13 the
    # modules contribute ... (54 in all". It went stale when Team Agile added three verbs.
    $cm = [regex]::Match($whyText, '(\d+) always-on, and the (\d+) the modules[\s\S]*?\((\d+) in all')
    Assert-True 'VERIFY.md states its verb counts in the expected shape' $cm.Success 'pattern not found -- has the sentence been reworded?'
    if ($cm.Success) {
        Assert-Equal "VERIFY.md's always-on verb count is config.default.json's" $coreVerbs.Count $cm.Groups[1].Value
        Assert-Equal "VERIFY.md's module verb count is the data files'" $moduleVerbs.Count $cm.Groups[2].Value
        Assert-Equal "VERIFY.md's total verb count is the sum" $allVerbs.Count $cm.Groups[3].Value
    }

    # docs/CLI.md's command reference opens with the same counts: "42 always on, 55 with
    # every opt-in module switched on." Read it back against the same two sources.
    $cliPath = Join-Path $pkgRoot 'docs/CLI.md'
    $cliText = ''
    if (Test-Path -LiteralPath $cliPath) { $cliText = Get-Content -LiteralPath $cliPath -Raw -Encoding UTF8 }
    $km = [regex]::Match($cliText, '\*\*(\d+) always on, (\d+) with every opt-in module')
    Assert-True 'docs/CLI.md states its verb counts in the expected shape' $km.Success 'pattern not found -- has the sentence been reworded?'
    if ($km.Success) {
        Assert-Equal "docs/CLI.md's always-on verb count is config.default.json's" $coreVerbs.Count $km.Groups[1].Value
        Assert-Equal "docs/CLI.md's with-every-module verb count is the sum" $allVerbs.Count $km.Groups[2].Value
    }
}

# -- docs/TESTING.md's agent row counts its test files ------------------------------
# The inventory row for `pytest Tests/` says "in N files" and gives each file a plain
# "(N)" that is the file's `def test_` count. Nothing read them back, so each new test
# file or test left them stale. N is a digit on purpose, so the regex stays simple.
# Only a plain "(N)" or "(N," is held: an entry written another way, such as
# "(3 tables, 20 cases)", or one with no count, is left to its prose.
Write-Host ""
Write-Host "  docs/TESTING.md's agent row counts the test files" -ForegroundColor Cyan
$testingPath = Join-Path $pkgRoot 'docs/TESTING.md'
$testingText = ''
if (Test-Path -LiteralPath $testingPath) { $testingText = Get-Content -LiteralPath $testingPath -Raw -Encoding UTF8 }
$agentRow = @($testingText -split "`n" | Where-Object { $_.StartsWith('| `python3 -m pytest Tests/` |') })
Assert-True 'docs/TESTING.md has the agent inventory row' ($agentRow.Count -eq 1)
if ($agentRow.Count -eq 1) {
    $realFiles = @(Get-ChildItem -LiteralPath $scriptDir -Filter 'test_*.py' -File)
    $fm = [regex]::Match($agentRow[0], 'in (\d+) files')
    Assert-True 'the agent row states its file count as "in N files"' $fm.Success 'pattern not found -- has the sentence been reworded?'
    if ($fm.Success) {
        Assert-Equal "the agent row's file count is the number of Tests/test_*.py files" $realFiles.Count $fm.Groups[1].Value
    }
    Assert-True 'the agent row carries per-file counts' (@(Get-P20StatedPytestCounts -Text $agentRow[0]).Count -gt 0)
}

# Every per-file count the document states -- the agent row's and each standalone
# `pytest Tests/test_x.py` row's -- against the one counting rule.
Write-Host ""
Write-Host "  Every per-file pytest count in docs/TESTING.md is the file's def test_ count" -ForegroundColor Cyan
$realCounts = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $scriptDir -Filter 'test_*.py' -File)) { $realCounts[$f.Name] = Get-P20PytestDefCount -Path $f.FullName }
$stated = @(Get-P20StatedPytestCounts -Text $testingText)
Assert-True 'standalone pytest rows with a count are read' (@($stated | Where-Object { $_.Where -eq 'its own row' }).Count -gt 0)
foreach ($c in $stated) {
    $pfFinding = @(Get-P20PytestCountDrift -Text $testingText -Counts $realCounts | Where-Object { $_ -like "$($c.File) ($($c.Where))*" })
    Assert-True "$($c.File)'s count in $($c.Where) is its def test_ count" ($pfFinding.Count -eq 0) ($pfFinding -join ' | ')
}

# One fixture per shape, against a fixed table of real counts.
$fixtureCounts = @{ 'test_alpha.py' = 5; 'test_beta.py' = 7; 'test_gamma.py' = 9 }
$pytestDriftTable = @(
    @('agree-pytest-counts.md', 0, ''),
    @('stale-standalone-pytest-row.md', 1, 'test_beta.py (its own row): the document says 4, the file has 7 def test_'),
    @('stale-standalone-subtests-row.md', 1, 'test_gamma.py (its own row): the document says 3, the file has 9 def test_'),
    @('stale-agent-row-pytest-count.md', 1, 'test_alpha.py (the agent row): the document says 6, the file has 5 def test_'),
    @('missing-pytest-file.md', 1, 'test_gone.py (its own row) is not a file in Tests/')
)
foreach ($case in $pytestDriftTable) {
    $fx = Get-Content -LiteralPath (Join-Path $driftDir $case[0]) -Raw -Encoding UTF8
    $got = @(Get-P20PytestCountDrift -Text $fx -Counts $fixtureCounts)
    $okCase = ($got.Count -eq $case[1]) -and (($case[1] -eq 0) -or ($got[0] -like "*$($case[2])*"))
    Assert-True "pytest count fixture $($case[0]): $($case[1]) finding(s)" $okCase ($got -join ' | ')
}

Write-Host ""
Write-Host "  Results: $($script:passed)/$($script:passed + $script:failed) passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
    Write-Host ""
    Write-Host "  A count typed into a document belongs in docs/TEST-COUNTS.md alone: link to it." -ForegroundColor Yellow
    Write-Host "  That page is written at a release, from a full tkTest run's block, by" -ForegroundColor Yellow
    Write-Host "  Scripts/Write-TestCounts.ps1 -Path <the run's output> (docs/TESTING.md, ""The counts"")." -ForegroundColor Yellow
}
Write-Host ""

# An explicit verdict either way: without the exit 0, a caller inherits the
# last child process's code (the pwsh a case above spawned), not this suite's.
if ($script:failed -gt 0) { exit 1 }
exit 0
