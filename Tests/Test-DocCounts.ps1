<#
.SYNOPSIS
    The documented CLI suite count agrees with the real one, and with itself.
.DESCRIPTION
    AGENTS.md, docs/TESTING.md and VERIFY.md each record "N suites, M
    assertions on this commit". Nothing checked them, so a commit that added a
    suite (or removed one) left the three sentences saying a number the runner
    no longer produces -- found only by a cold start.

    This suite closes the SUITE-COUNT half of that gap: it reads the three
    sentences back with a regex anchored to each file's own wording, and
    checks all three agree with each other and with
    Get-ToolkitSuiteRegistry.ps1's real count -- the same table
    Test-Toolkit.ps1 runs. Deliberately NOT the ASSERTION count: that number
    moves with a machine's config.local.json (an extra nav alias adds rows to
    Menu's own coverage; a local org adds Autoload's), which is legitimate
    variance this suite would otherwise have to model exactly to avoid being
    wrong on someone else's machine. The suite count has no such variance --
    it is exactly the registry's size, on any host. The assertion counts are
    printed instead: a full run of Test-Toolkit.ps1 ends with the combined
    per-suite line and the total, ready to paste, and this suite holds
    the SHAPE they are pasted into -- docs/TESTING.md's combined row names every
    registry suite once in the runner's order, and no single-suite row carries
    a count of its own to go stale beside it.

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
Write-Host "  DocCounts -- the documented suite count agrees with the real one" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- The real count --------------------------------------------------------------
. (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1')
$realCount = (Get-P20ToolkitSuiteRegistry).Count
Write-Host "  Registry:  $realCount suites (Get-ToolkitSuiteRegistry.ps1)" -ForegroundColor DarkGray

# -- Each document's own sentence, read back with an anchor unique to it --------
# A file whose wording changes has to change the anchor here too -- that is the
# point: a silent rewording is a silent way to stop being checked.
function Get-DocSuiteCount {
    param([string]$Path, [string]$Pattern, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Assert-True "$Label exists" $false "not found: $Path"
        return $null
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $m = [regex]::Match($text, $Pattern)
    Assert-True "$Label states its CLI suite count in the expected shape" $m.Success `
        "pattern not found in $Path -- has the sentence been reworded?"
    if (-not $m.Success) { return $null }
    return [int]$m.Groups[1].Value
}

$agentsPath = Join-Path $pkgRoot 'AGENTS.md'
$testingPath = Join-Path $pkgRoot 'docs/TESTING.md'
$verifyPath = Join-Path $pkgRoot 'VERIFY.md'

$agentsCount = Get-DocSuiteCount -Path $agentsPath -Label 'AGENTS.md' `
    -Pattern 'tkTestToolkit\s+#\s*the CLI -- (\d+) suites,'
$testingCount = Get-DocSuiteCount -Path $testingPath -Label 'docs/TESTING.md' `
    -Pattern 'tkTestToolkit\s+#\s*(\d+) suites,'
$verifyCount = Get-DocSuiteCount -Path $verifyPath -Label 'VERIFY.md' `
    -Pattern 'is \*\*(\d+) suites,'

if ($null -ne $agentsCount) { Write-Host "  AGENTS.md:       $agentsCount suites" -ForegroundColor DarkGray }
if ($null -ne $testingCount) { Write-Host "  docs/TESTING.md: $testingCount suites" -ForegroundColor DarkGray }
if ($null -ne $verifyCount) { Write-Host "  VERIFY.md:       $verifyCount suites" -ForegroundColor DarkGray }
Write-Host ""

# -- Agreement --------------------------------------------------------------------
if ($null -ne $agentsCount) {
    Assert-Equal 'AGENTS.md matches the real suite count' $realCount $agentsCount
}
if ($null -ne $testingCount) {
    Assert-Equal 'docs/TESTING.md matches the real suite count' $realCount $testingCount
}
if ($null -ne $verifyCount) {
    Assert-Equal 'VERIFY.md matches the real suite count' $realCount $verifyCount
}

# -- Per-suite counts live in ONE row -----------------------------------------
# docs/TESTING.md prints the CLI's per-suite counts once, in the `tkTestToolkit`
# row, and a full run of the runner prints that row ready to paste. A count typed
# into a single suite's own row is a half-measure: nothing reads it
# back, so it goes stale while the combined row beside it is refreshed.
Write-Host ""
Write-Host "  Per-suite counts live in one row" -ForegroundColor Cyan
$testingText = ''
if (Test-Path -LiteralPath $testingPath) { $testingText = Get-Content -LiteralPath $testingPath -Raw -Encoding UTF8 }
$testingRows = @($testingText -split "\r?\n")

$combinedRow = @($testingRows | Where-Object { $_ -match '^\|\s*`tkTestToolkit`\s*\|' })
Assert-True 'docs/TESTING.md has one combined `tkTestToolkit` row' ($combinedRow.Count -eq 1) "$($combinedRow.Count) rows"
if ($combinedRow.Count -eq 1) {
    # The names in the row, in order, are the registry's -- the same line the
    # runner prints, so a paste lands in the shape this reads.
    $named = @([regex]::Matches($combinedRow[0], '(?<=[\s,.])([A-Z][A-Za-z]+) \d+(?=[,.])') | ForEach-Object { $_.Groups[1].Value })
    $registryNames = @((Get-P20ToolkitSuiteRegistry).Keys)
    Assert-Equal 'the combined row names every registry suite once, in the runner''s order' ($registryNames -join ', ') ($named -join ', ')
}


# The paste block under "The counts, after a merge" is what a full run prints:
# the per-suite line and the total line. It went stale once -- a deleted suite
# still listed, a total that was no one's sum -- because nothing read it. Read it
# back against the registry: the same suite count, the same names in the same
# order, and a total that is the sum of its own lines. Deliberately not against a
# live run: assertion counts move with a machine's config.local.json (see above).
$pasteHead = [regex]::Match($testingText, '(?s)\*\*The counts, after a merge\.\*\*.*?```text\r?\n(.*?)\r?\n```')
Assert-True 'docs/TESTING.md has the paste block under "The counts, after a merge"' $pasteHead.Success 'fenced block not found -- has the heading been reworded?'
if ($pasteHead.Success) {
    $pasteLines = @($pasteHead.Groups[1].Value -split "\r?\n" | Where-Object { $_.Trim() })
    $pasteNames = @()
    $pasteSum = 0
    $pasteTotal = $null
    foreach ($pl in $pasteLines) {
        $tm = [regex]::Match($pl, '^\s*(\d+) suites, (\d+) assertions\s*$')
        if ($tm.Success) { $pasteTotal = $tm; continue }
        $parts = @([regex]::Matches($pl, '(?<=^\s*|,\s)([A-Z][A-Za-z]+) (\d+)(?=,|\s*$)'))
        if ($parts.Count -gt 0) {
            foreach ($pm in $parts) { $pasteNames += $pm.Groups[1].Value; $pasteSum += [int]$pm.Groups[2].Value }
        }
    }
    Assert-Equal 'the paste block lists as many suites as the registry has' $realCount $pasteNames.Count
    Assert-Equal 'the paste block names every registry suite once, in the runner''s order' ($registryNames -join ', ') ($pasteNames -join ', ')
    Assert-True 'the paste block ends with its "N suites, M assertions" line' ($null -ne $pasteTotal) 'line not found'
    if ($null -ne $pasteTotal) {
        Assert-Equal 'the paste block''s suite count is the registry''s' $realCount $pasteTotal.Groups[1].Value
        Assert-Equal 'the paste block''s total is the sum of its own per-suite lines' $pasteSum $pasteTotal.Groups[2].Value
    }
}

$suiteRows = @($testingRows | Where-Object { $_ -match '^\|\s*`tkTestToolkit -[A-Za-z]+`\s*\|' })
Assert-True 'docs/TESTING.md has single-suite rows to check' ($suiteRows.Count -gt 0)
foreach ($row in $suiteRows) {
    $suiteName = [regex]::Match($row, '`tkTestToolkit -([A-Za-z]+)`').Groups[1].Value
    # A bare count is a cell holding only a number, or a bolded number in prose.
    $bare = ($row -match '\|\s*\d+\s*\|') -or ($row -match '\*\*\d+\*\*')
    Assert-True "docs/TESTING.md's -$suiteName row carries no count of its own" (-not $bare) $row.Substring(0, [Math]::Min(120, $row.Length))
}

# -- The paste owns every count in docs/TESTING.md ----------------------------
# The paste block is the one record: the CLI's per-suite line and total, a pytest
# line and a web line (tkTest prints all three). The table row's list and the
# command block's three totals are held to it, from the text alone -- no run and
# no machine-local file is read, so it holds in CI as it does anywhere.
Write-Host ""
Write-Host "  The paste block owns the table row and the command block's totals" -ForegroundColor Cyan
. (Join-Path $scriptDir 'Get-TestingDocDrift.ps1')
$driftFindings = @(Get-P20TestingDocDrift -Text $testingText)
Assert-True 'docs/TESTING.md: the table row and the command block agree with the paste block' ($driftFindings.Count -eq 0) ($driftFindings -join ' | ')

# One fixture per drift shape: the clause must name the stale line, and for a
# stale row the first suite whose number differs.
$driftDir = Join-Path $scriptDir 'fixtures/doc-counts'
$driftTable = @(
    # file, expected finding count, a fragment the finding must contain
    @('agree.md', 0, ''),
    @('stale-row.md', 1, "first difference is suite 2, row says 'Compat 19', paste says 'Compat 20'"),
    @('stale-pytest.md', 1, "the command block's pytest line is stale: it says '11 passed"),
    @('stale-web.md', 1, "the command block's web line is stale: it says '7 suites, 54 tests'"),
    @('stale-cli-line.md', 1, "the command block's tkTestToolkit line is stale: it says '3 suites, 59 assertions'"),
    @('pytest-not-run.md', 1, "the paste block's pytest line is not a count"),
    @('pytest-not-available.md', 1, "the paste block's pytest line is not a count"),
    @('agree-via.md', 0, '')
)
foreach ($case in $driftTable) {
    $fx = Get-Content -LiteralPath (Join-Path $driftDir $case[0]) -Raw -Encoding UTF8
    $got = @(Get-P20TestingDocDrift -Text $fx)
    $okCase = ($got.Count -eq $case[1]) -and (($case[1] -eq 0) -or ($got[0] -like "*$($case[2])*"))
    Assert-True "drift fixture $($case[0]): $($case[1]) finding(s)" $okCase ($got -join ' | ')
}

# What tkTest prints for the paste: a half that did not run says so in its line's place.
. (Join-Path $pkgRoot 'Scripts/TestAll-Rules.ps1')
$recAgent = [ordered]@{ result = 'pass'; line = '12 passed, 1 skipped, 40 subtests passed in 3.0s' }
$recWeb = [ordered]@{ result = 'pass'; suites = 7; total = 55 }
$cliTwo = @('Consts 10, Compat 20, Menu 30', '3 suites, 60 assertions')
$pasteTable = @(
    @('all three ran', [ordered]@{ agent = $recAgent; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests|web: 7 suites, 55 tests'),
    @('agent skipped', [ordered]@{ agent = [ordered]@{ result = 'skip'; reason = 'no Python 3 on the PATH' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: NOT AVAILABLE -- no python with pytest was found: no Python 3 on the PATH|web: 7 suites, 55 tests'),
    @('agent ran through a venv', [ordered]@{ agent = [ordered]@{ result = 'pass'; line = $recAgent.line; python = '~/.venv-toolkit/bin/python' }; web = $recWeb }, $cliTwo, 'Consts 10, Compat 20, Menu 30|3 suites, 60 assertions|pytest: 12 passed, 1 skipped, 40 subtests (via ~/.venv-toolkit/bin/python)|web: 7 suites, 55 tests'),
    @('web failed, CLI partial', [ordered]@{ agent = $recAgent; web = [ordered]@{ result = 'fail' } }, @(), 'CLI: not printed -- the CLI half did not run every suite and pass|pytest: 12 passed, 1 skipped, 40 subtests|web: not printed -- the web half did not pass')
)
foreach ($pc in $pasteTable) {
    $pasted = @(Get-P20PasteLines -Records $pc[1] -CliLines $pc[2])
    Assert-Equal "tkTest's paste block, $($pc[0])" $pc[3] ($pasted -join '|')
}

# -- The front door stays the commercial ------------------------------------
# The root README is what every cold reader, and every cold model, reads first:
# what the product is, the three halves, the five verbs, the quick start and the
# Documentation table, in about a hundred lines. It prints no counts (those live in
# AGENTS.md, docs/TESTING.md and VERIFY.md, checked above), no build history, and
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
    @('outbound', 'every relative link in docs/KNOWN-GAPS.md resolves, file and heading')
)
foreach ($gc in $gapChecks) {
    $hits = @($gapFindings | Where-Object { $_.Kind -eq $gc[0] } | ForEach-Object { $_.Text })
    Assert-True "known gaps: $($gc[1])" (($hits.Count -eq 0) -and ($gc[0] -ne 'gaps' -or $gapCount -gt 0)) ($hits -join ' | ')
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
    Write-Host "  A suite was added or removed without updating the three counts, or one of" -ForegroundColor Yellow
    Write-Host "  them was reworded so its anchor no longer matches. Update AGENTS.md," -ForegroundColor Yellow
    Write-Host "  docs/TESTING.md and VERIFY.md's suite-count sentences in the same commit;" -ForegroundColor Yellow
    Write-Host "  a full tkTestToolkit run prints the combined row and the total to paste." -ForegroundColor Yellow
}
Write-Host ""

# An explicit verdict either way: without the exit 0, a caller inherits the
# last child process's code (the pwsh a case above spawned), not this suite's.
if ($script:failed -gt 0) { exit 1 }
exit 0
