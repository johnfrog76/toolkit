<#
.SYNOPSIS
    The rules behind {cliPrefix}Test, in one file. Dot-source it.

.DESCRIPTION
    Not a command. Everything the verb works OUT about a test run lives here, so
    the verb (Scripts/Invoke-TestAll.ps1), the CLI runner (Tests/Test-Toolkit.ps1),
    Setup (Scripts/Test-Prerequisites.ps1), CI's gate (Scripts/Test-CiHalf.ps1)
    and the suite (Tests/Test-TestAll.ps1) read one answer:

      Get-P20TestHalves            the three halves, in the order Test runs them.
      Get-P20TestSummaryPath       test-summary.<machine>.json in the machine's
                                   test-history folder (Get-TestHistoryDir.ps1),
                                   '' when a marked run has none.
      Get-P20TestResultsPath       test-results.<machine>.log, the same way.
      Get-P20TestCheckout          the checkout a run came from (main, or the
                                   worktree's folder name) and its commit.
      ConvertFrom-P20PytestOutput  pytest's closing summary line -> counts.
      ConvertFrom-P20JestOutput    jest's `Tests:` and `Test Suites:` lines -> counts,
                                   and whether jest force-exited a worker (Leaked).
      ConvertFrom-P20ToolkitOutput the CLI runner's `Total: n/m passed` line -> counts.
      Get-P20HalfVerdict           counts + exit code -> pass / fail.
      ConvertFrom-P20SmokeOutput   the browser smoke's closing `smoke:` line and
                                   its PASS / FAIL lines -> counts.
      Get-P20CiHalfVerdict         one half's transcript + exit code -> CI's
                                   pass / fail: the verdict above, and a half
                                   with nothing passed is not a pass.
                                   The smoke is read by it too, though it is
                                   not one of Test's halves.
      Get-P20TestCountsFile        where the counts live (docs/TEST-COUNTS.md),
                                   its writer, and the headings the runners
                                   print above a run's counts.
      Get-P20CountLinePatterns     the shapes of a run's four count lines: as a
                                   block's lines, and as typed into a document.
      ConvertFrom-P20CountsBlock   a full run's printed block (or a transcript
                                   holding one) -> its four lines, and every way
                                   it is not a full run's.
      Format-P20TestCountsFile     docs/TEST-COUNTS.md's text from a block and a
                                   version: what Scripts/Write-TestCounts.ps1
                                   writes.
      Read-P20TestCountsFile       docs/TEST-COUNTS.md read back and held to that.
      Read-P20ExpectedCounts       the three totals docs/TEST-COUNTS.md states.
      Get-P20TypedCountLines       every count line typed into a document other
                                   than docs/TEST-COUNTS.md.
      Get-P20TestCountsChangeFindings  a change to docs/TEST-COUNTS.md that does
                                   not change consts.json's version.
      Get-P20CiScope               which of CI's jobs a change runs, from the
                                   event and the files it changed.
      Read-P20TestSummary          the summary file, as nested hashtables.
      Merge-P20TestSummary         write some halves into the summary file and
                                   keep the others' entries as they were.
      Get-P20TestHalfRecords       one record per half from a summary, for a
                                   reader (Setup), with a file that predates
                                   the halves read as the CLI's alone.

    The runners' internals are not forked: each half is read from what it
    PRINTS, the line a person reads at the end of a run.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing, and
    JSON read into hashtables by hand (5.1's ConvertFrom-Json has no switch for it).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Get-P20TestHistoryDir -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-TestHistoryDir.ps1')
}
if (-not (Get-Command Invoke-P20TrackerRead -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
}

function Get-P20TestHalves {
    <# The order Test runs them in -- consts.json tests.halves: the agent, the CLI, the web UI. #>
    return @((Get-P20Consts).tests.halves)
}

function Get-P20LegacyTestHalf {
    <# What a suite entry with no `half` is read as -- consts.json tests.legacyHalf. #>
    return [string](Get-P20Consts).tests.legacyHalf
}

function Get-P20TestSummaryPath {
    <#
      test-summary.<machine>.json in this machine's test-history folder, one for
      every checkout (Scripts/Get-TestHistoryDir.ps1). The CLI runner, Test and
      Setup all ask here; agent/core/log.py reads the same folder by the same
      rule. -PackageRoot is the checkout asking: a record it kept at its own root
      before the folder existed is copied in, once. '' under the run marker with
      no override -- nothing is written and nothing is read.
    #>
    param([string]$PackageRoot)
    return (Get-P20TestHistoryFile -Kind summary -PackageRoot $PackageRoot)
}

function Get-P20TestResultsPath {
    <# test-results.<machine>.log beside the summary, by the same rule. #>
    param([string]$PackageRoot)
    return (Get-P20TestHistoryFile -Kind results -PackageRoot $PackageRoot)
}

function Get-P20TestCheckout {
    <#
      Where a run came from: `checkout` is `main` for a repository's own working
      tree, the folder name of a linked git worktree, '' outside git; `commit`
      is HEAD's short hash, '' when git cannot say. Both go on every record a run
      writes, so a reader can say which tree a result is about.
    #>
    param([Parameter(Mandatory)][string]$PackageRoot)
    $out = [ordered]@{ checkout = ''; commit = '' }
    try {
        $r = Invoke-P20TrackerRead 'git' @('-C', $PackageRoot, 'rev-parse', '--show-toplevel', '--git-dir', '--git-common-dir', '--short', 'HEAD')
    }
    catch { return $out }
    $lines = @($r.Out | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($r.Code -ne 0 -or $lines.Count -lt 4) { return $out }
    $full = {
        param([string]$P)
        if (-not [System.IO.Path]::IsPathRooted($P)) { $P = Join-Path $PackageRoot $P }
        return ([System.IO.Path]::GetFullPath($P)).TrimEnd('\', '/')
    }
    $gitDir = & $full $lines[1]
    $commonDir = & $full $lines[2]
    if ($gitDir -eq $commonDir) { $out.checkout = 'main' }
    else { $out.checkout = Split-Path -Leaf (& $full $lines[0]) }
    $out.commit = $lines[3]
    return $out
}

function New-P20Counts {
    return @{ Found = $false; Passed = 0; Failed = 0; Skipped = 0; Total = 0; Suites = 0; SuitesFailed = 0; Subtests = 0; Line = ''; Leaked = $false }
}

function ConvertFrom-P20PytestOutput {
    <#
      pytest's closing line, with or without its rule of '=':
        ======= 2 failed, 898 passed, 3 skipped, 882 subtests passed in 312.40s (0:05:12) =======
        900 passed, 3 skipped in 12.3s
      Failed counts `failed`, `error(s)` and `subtests failed`. `N subtests passed`
      is not a test and is not counted as one. No such line: Found is false.
    #>
    param([string]$Text)
    $c = New-P20Counts
    if (-not $Text) { return $c }
    $lines = @($Text -split "`r?`n")
    $line = ''
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if ($l -match '^=*\s*((\d+ [a-z]+.*?)|(no tests ran.*?)) in [0-9.]+s\b') { $line = $l; break }
    }
    if (-not $line) { return $c }
    $c.Found = $true
    $c.Line = ($line -replace '^=+\s*', '' -replace '\s*=+$', '')
    foreach ($m in [regex]::Matches($line, '(\d+) (subtests passed|subtests failed|passed|failed|errors|error|skipped)\b')) {
        $n = [int]$m.Groups[1].Value
        switch ($m.Groups[2].Value) {
            'subtests passed' { $c.Subtests += $n }
            'passed' { $c.Passed += $n }
            'failed' { $c.Failed += $n }
            'error' { $c.Failed += $n }
            'errors' { $c.Failed += $n }
            'subtests failed' { $c.Failed += $n }
            'skipped' { $c.Skipped += $n }
        }
    }
    $c.Total = $c.Passed + $c.Failed + $c.Skipped
    return $c
}

function ConvertFrom-P20JestOutput {
    <#
      jest's totals:
        Test Suites: 1 failed, 102 passed, 103 total
        Tests:       2 failed, 1 skipped, 1229 passed, 1232 total
      The LAST of each, so a watch-mode rerun or a nested print cannot win.
      No `Tests:` line: Found is false -- npm test stopped before jest reported.
      Leaked: jest printed that it force-exited a worker ("A worker process has
      failed to exit gracefully and has been force exited"), which it does when a
      test left a timer or a handle open. Every test can pass and the run still
      leaked, so the verdict reads it on its own (Get-P20HalfVerdict).
    #>
    param([string]$Text)
    $c = New-P20Counts
    if (-not $Text) { return $c }
    $testsLine = ''
    $suitesLine = ''
    $c.Leaked = ($Text -match 'worker process has failed to exit gracefully')
    foreach ($l in @($Text -split "`r?`n")) {
        $t = $l.Trim()
        if ($t -match '^Tests:\s+\d') { $testsLine = $t }
        elseif ($t -match '^Test Suites:\s+\d') { $suitesLine = $t }
    }
    if (-not $testsLine) { return $c }
    $c.Found = $true
    $c.Line = $testsLine
    foreach ($m in [regex]::Matches($testsLine, '(\d+) (passed|failed|skipped|todo|total)\b')) {
        $n = [int]$m.Groups[1].Value
        switch ($m.Groups[2].Value) {
            'passed' { $c.Passed = $n }
            'failed' { $c.Failed = $n }
            'skipped' { $c.Skipped += $n }
            'todo' { $c.Skipped += $n }
            'total' { $c.Total = $n }
        }
    }
    if ($suitesLine) {
        foreach ($m in [regex]::Matches($suitesLine, '(\d+) (failed|total)\b')) {
            if ($m.Groups[2].Value -eq 'total') { $c.Suites = [int]$m.Groups[1].Value }
            else { $c.SuitesFailed = [int]$m.Groups[1].Value }
        }
    }
    return $c
}

function ConvertFrom-P20ToolkitOutput {
    <#
      The CLI runner's summary box: `Total: 6153/6153 passed`. The last one,
      read off the line whatever box characters frame it.
    #>
    param([string]$Text)
    $c = New-P20Counts
    if (-not $Text) { return $c }
    $all = [regex]::Matches($Text, 'Total: (\d+)/(\d+) passed')
    if ($all.Count -eq 0) { return $c }
    $m = $all[$all.Count - 1]
    $c.Found = $true
    $c.Passed = [int]$m.Groups[1].Value
    $c.Total = [int]$m.Groups[2].Value
    $c.Failed = $c.Total - $c.Passed
    $c.Line = $m.Value
    return $c
}

function ConvertFrom-P20SmokeOutput {
    <#
      The browser smoke's closing line (web/tests/smoke.mjs and the modes it
      runs), the LAST one in the transcript:
        smoke: clean (matrix, 212 checks)
        smoke: 2 failure(s) (matrix, 212 checks)
        smoke: clean (modules=off, viewport=desktop)
        smoke: a11y -- 0 critical, 0 serious, 3 moderate, 1 minor over 48 pages
      A check mode counts its `PASS  ` and `FAIL  ` lines; Failed is never fewer
      than the failures the closing line states. The a11y mode counts the pages
      it audited as passed and its serious and critical findings as failed --
      the mode's own rule; moderate and minor are listed and do not fail it.
      No closing line: Found is false -- the run stopped before it reported
      (no chromium, a stack that never came up).
    #>
    param([string]$Text)
    $c = New-P20Counts
    if (-not $Text) { return $c }
    $lines = @($Text -split "`r?`n")
    $line = ''
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = ($lines[$i] -replace '\x1b\[[0-9;]*m', '').Trim()
        if ($l -match '^smoke: (clean \(.+\)|\d+ failure\(s\) \(.+\)|a11y -- \d+ critical, .+ over \d+ pages?)$') { $line = $l; break }
    }
    if (-not $line) { return $c }
    $c.Found = $true
    $c.Line = $line
    $a = [regex]::Match($line, '^smoke: a11y -- (\d+) critical, (\d+) serious, \d+ moderate, \d+ minor over (\d+) pages?$')
    if ($a.Success) {
        $c.Failed = [int]$a.Groups[1].Value + [int]$a.Groups[2].Value
        $c.Passed = [int]$a.Groups[3].Value
        $c.Total = $c.Passed + $c.Failed
        return $c
    }
    $c.Passed = [regex]::Matches($Text, '(?m)^(?:\x1b\[[0-9;]*m)*PASS  ').Count
    $c.Failed = [regex]::Matches($Text, '(?m)^(?:\x1b\[[0-9;]*m)*FAIL  ').Count
    $stated = [regex]::Match($line, '^smoke: (\d+) failure\(s\)')
    if ($stated.Success -and [int]$stated.Groups[1].Value -gt $c.Failed) { $c.Failed = [int]$stated.Groups[1].Value }
    $c.Total = $c.Passed + $c.Failed
    return $c
}

function Get-P20HalfVerdict {
    <#
      A half passed when it printed its summary, exited 0 and counted no
      failure. No summary line is a failure -- the runner stopped before it
      reported -- and so is a non-zero exit after a clean-looking line: the
      CLI runner's own rule for a suite (Get-P20SuiteVerdict). A web run in
      which jest force-exited a worker fails too, with every test passed: a test
      left a timer or a handle open, and a leak that passes quietly stops being
      noticed. The detail names the run that finds it.
    #>
    param($Counts, [int]$ExitCode)
    if (-not $Counts.Found) { return @{ Result = 'fail'; Detail = "no summary line (exit $ExitCode)" } }
    if ($Counts.Failed -gt 0) { return @{ Result = 'fail'; Detail = "$($Counts.Failed) failed" } }
    if ($Counts.Leaked) {
        return @{ Result = 'fail'; Detail = 'jest force-exited a worker: a test left a timer or a handle open -- run npx jest --runInBand --detectOpenHandles in web/ to name it' }
    }
    if ($ExitCode -ne 0) { return @{ Result = 'fail'; Detail = "exit $ExitCode" } }
    return @{ Result = 'pass'; Detail = 'ok' }
}

function Get-P20CiHalfVerdict {
    <#
      What CI makes of one half's step: the step's transcript and the
      exit code of the command that printed it. The half is read by the parser
      Test reads it with and judged by Get-P20HalfVerdict, and CI holds it one
      rule tighter, because a check nobody watches cannot read a short run:
        no summary line             -> fail. A half Test skipped prints none;
                                       its stated reason is the detail.
        a failure counted, exit <>0 -> fail (Get-P20HalfVerdict).
        a line with nothing passed  -> fail: `Total: 0/0`, `no tests ran`, or
                                       every test skipped proved nothing.
        otherwise                   -> pass. Skipped is how many tests
                                       (pytest, jest) or suites (the CLI's
                                       `Results: 0/0 passed`, a WARN) skipped
                                       themselves -- reported, not failed, the
                                       runners' own rule (docs/TESTING.md).
      -Half smoke reads the browser smoke the same way: its closing `smoke:`
      line (ConvertFrom-P20SmokeOutput), so a run that never launched a
      browser, or audited no page, fails too.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('cli', 'agent', 'web', 'smoke')][string]$Half,
        [string]$Text,
        [int]$ExitCode
    )
    if ($Half -eq 'agent') { $c = ConvertFrom-P20PytestOutput -Text $Text }
    elseif ($Half -eq 'web') { $c = ConvertFrom-P20JestOutput -Text $Text }
    elseif ($Half -eq 'smoke') { $c = ConvertFrom-P20SmokeOutput -Text $Text }
    else {
        $c = ConvertFrom-P20ToolkitOutput -Text $Text
        # A suite's own score line, the pattern Get-P20SuiteVerdict reads; 0/0 is its WARN.
        $c.Skipped = [regex]::Matches([string]$Text, '(?m)^(?:\x1b\[[0-9;]*m|\s)*Results:\s*0/0\s+passed').Count
    }
    $out = @{ Result = 'fail'; Detail = ''; Line = $c.Line; Passed = $c.Passed; Failed = $c.Failed; Skipped = $c.Skipped; Total = $c.Total }
    $v = Get-P20HalfVerdict -Counts $c -ExitCode $ExitCode
    if (-not $c.Found) {
        $skip = [regex]::Match([string]$Text, '(?m)^\s*SKIP\s+' + $Half + '\s+--\s+(.+?)\s*$')
        if ($skip.Success) { $out.Detail = "skipped: $($skip.Groups[1].Value)" }
        else { $out.Detail = $v.Detail }
        return $out
    }
    if ($v.Result -ne 'pass') { $out.Detail = $v.Detail; return $out }
    if ($c.Passed -eq 0) {
        $out.Detail = 'nothing passed -- a run that counted no passing test proved nothing'
        return $out
    }
    $out.Result = 'pass'
    $out.Detail = 'ok'
    return $out
}

function Get-P20TestCountsFile {
    <#
      Where the test counts live, and the line each runner prints above them.
      Path is the one document that may state a run's figures. Heading is
      tkTest's, above the four lines Scripts/Write-TestCounts.ps1 takes;
      CliHeading is tkTestToolkit's, above the CLI's two (tkTest reads them
      from its child's output by it).
    #>
    return [ordered]@{
        Path       = 'docs/TEST-COUNTS.md'
        Heading    = 'Counts for docs/TEST-COUNTS.md, from this run:'
        CliHeading = 'CLI counts for docs/TEST-COUNTS.md, from this run:'
        Writer     = 'Scripts/Write-TestCounts.ps1'
    }
}

function Get-P20CountLinePatterns {
    <#
      The shapes of the four lines a full run prints, in one place. The
      anchored four read one trimmed line of a block (the writer's check and
      the counts file's): SuiteLine the CLI per suite, CliTotal
      `N suites, M assertions`, Pytest `pytest: N passed[, N skipped][, N subtests]`
      and Web `web: N suites, N tests`. The Typed four find the same figures
      typed anywhere in a line of a document, which
      {cliPrefix}TestToolkit -DocCounts refuses outside docs/TEST-COUNTS.md:
      a run of five or more `Name N` pairs, `N suites, M assertions`, a pytest
      total, `N passed, N skipped`, and `N suites, N tests`.
    #>
    return [ordered]@{
        SuiteLine      = '^[A-Z][A-Za-z]+ \d+(?:, [A-Z][A-Za-z]+ \d+)*$'
        CliTotal       = '^(\d+) suites, (\d+) assertions$'
        Pytest         = '^pytest: (\d+) passed(?:, (\d+) skipped)?(?:, (\d+) subtests)?$'
        Web            = '^web: (\d+) suites, (\d+) tests$'
        TypedSuiteList = '(?:[A-Z][A-Za-z]+ \d+, ){4,}[A-Z][A-Za-z]+ \d+'
        TypedCliTotal  = '\b\d+ suites, \d+ assertions\b'
        TypedPytest    = '(?:\bpytest:|pytest Tests/\s+#)\s*\d+ passed\b|\b\d+ passed, \d+ skipped\b'
        TypedWeb       = '\b\d+ suites, \d+ tests\b'
    }
}

function ConvertFrom-P20CountsBlock {
    <#
      A full run's printed block -> its four lines, read. -Text is the block,
      or a whole transcript: when a line ends `from this run:` (the heading
      tkTest prints), the block is the lines after the LAST such heading, up to
      the first blank line after them; otherwise it is every non-blank line.
      Each line is trimmed and colour codes dropped, and a pytest line's
      `(via <python>)` -- which interpreter ran it, information for the
      person reading -- is not kept.
      Returns Lines (the four, as they are written), Suites (one @(name, n)
      each, in order), SuiteCount, Assertions, Pytest (Passed, Skipped,
      Subtests), Web (Suites, Total) and Findings: one sentence per way the
      block is not a full run's -- not four lines, a line not in its shape
      (a half that did not run prints a sentence in its place), a suite named
      twice, a suite count that is not the number of suites listed, a total
      that is not their sum. A block with no finding is one the writer takes.
    #>
    param([AllowEmptyString()][string]$Text)
    $p = Get-P20CountLinePatterns
    $out = [ordered]@{ Lines = @(); Suites = @(); SuiteCount = 0; Assertions = 0; Pytest = $null; Web = $null; Findings = @() }
    $raw = @(([string]$Text) -split "\r?\n" | ForEach-Object { ($_ -replace '\x1b\[[0-9;]*m', '') })
    $start = 0
    $fromHeading = $false
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match 'from this run:\s*$') { $start = $i + 1; $fromHeading = $true }
    }
    $lines = @()
    for ($i = $start; $i -lt $raw.Count; $i++) {
        $t = $raw[$i].Trim()
        if (-not $t) {
            if ($fromHeading -and $lines.Count -gt 0) { break }
            continue
        }
        $lines += ($t -replace '^(pytest: .*?)\s+\(via .*\)$', '$1')
    }
    $out.Lines = $lines
    $shape = 'a full run prints four: the per-suite line, "N suites, M assertions", "pytest: ..." and "web: ..."'
    if ($lines.Count -ne 4) {
        $out.Findings = @("the block has $($lines.Count) line(s); $shape")
        return $out
    }
    $f = @()
    if ($lines[0] -cnotmatch $p.SuiteLine) { $f += "the first line is not the per-suite line ('Name N, Name N, ...'): '$($lines[0])'" }
    else {
        $seen = @{}
        foreach ($m in [regex]::Matches($lines[0], '([A-Z][A-Za-z]+) (\d+)')) {
            $name = $m.Groups[1].Value
            if ($seen.ContainsKey($name)) { $f += "the per-suite line names $name twice" }
            $seen[$name] = $true
            $out.Suites += , @($name, [int]$m.Groups[2].Value)
        }
    }
    $tm = [regex]::Match($lines[1], $p.CliTotal)
    if (-not $tm.Success) { $f += "the second line is not ""N suites, M assertions"": '$($lines[1])'" }
    else {
        $out.SuiteCount = [int]$tm.Groups[1].Value
        $out.Assertions = [int]$tm.Groups[2].Value
        if ($out.Suites.Count -gt 0) {
            $sum = 0
            foreach ($s in $out.Suites) { $sum += $s[1] }
            if ($out.SuiteCount -ne $out.Suites.Count) { $f += "the total says $($out.SuiteCount) suites and the per-suite line lists $($out.Suites.Count)" }
            if ($out.Assertions -ne $sum) { $f += "the total says $($out.Assertions) assertions and the per-suite line sums to $sum" }
        }
    }
    $pm = [regex]::Match($lines[2], $p.Pytest)
    if (-not $pm.Success) { $f += "the third line is not a pytest count: '$($lines[2])' -- write from a tkTest run that ran the agent half and passed" }
    else {
        $out.Pytest = [ordered]@{ Passed = [int]$pm.Groups[1].Value; Skipped = 0; Subtests = 0 }
        if ($pm.Groups[2].Success) { $out.Pytest.Skipped = [int]$pm.Groups[2].Value }
        if ($pm.Groups[3].Success) { $out.Pytest.Subtests = [int]$pm.Groups[3].Value }
    }
    $wm = [regex]::Match($lines[3], $p.Web)
    if (-not $wm.Success) { $f += "the fourth line is not a web count: '$($lines[3])' -- write from a tkTest run that ran the web half and passed" }
    else { $out.Web = [ordered]@{ Suites = [int]$wm.Groups[1].Value; Total = [int]$wm.Groups[2].Value } }
    $out.Findings = $f
    return $out
}

function Format-P20TestCountsFile {
    <#
      docs/TEST-COUNTS.md's whole text, LF, from a block's four lines and the
      version they are as of. The one place the page's words are: the writer
      writes this, and -DocCounts holds the committed file to it.
    #>
    param([Parameter(Mandatory)][string[]]$Lines, [Parameter(Mandatory)][string]$Version)
    $doc = @(
        '# Test counts',
        '',
        "The counts a full run printed, as of version **$Version**: the CLI per suite and in total, the",
        'agent''s `pytest` and the web UI''s `npm test`. `Scripts/Write-TestCounts.ps1` writes this page in the',
        'release pull request, from a full `tkTest` run, and it changes only with the version: between',
        'releases `main` moves on and these figures stay where the last release left them. No other document',
        'states them. [Testing](TESTING.md), "The counts", says how they are written.',
        '',
        '```text'
    ) + @($Lines) + @('```')
    return ($doc -join "`n") + "`n"
}

function Read-P20TestCountsFile {
    <#
      docs/TEST-COUNTS.md read back: Version (the one it is as of, '' when it
      states none), Block (ConvertFrom-P20CountsBlock over its text fence, or
      $null) and Findings -- no version, no fence, a block that is not a full
      run's, or a text that is not exactly what the writer writes from them
      (Format-P20TestCountsFile; line endings aside, so a CRLF checkout reads
      the same). -ExpectedVersion, when given, is consts.json's version, and a
      file as of another is a finding too.
    #>
    param([AllowEmptyString()][string]$Text, [string]$ExpectedVersion)
    $out = [ordered]@{ Version = ''; Block = $null; Findings = @() }
    $f = @()
    $norm = ([string]$Text) -replace "`r`n", "`n"
    $vm = [regex]::Match($norm, 'as of version \*\*([0-9A-Za-z.+-]+)\*\*')
    if ($vm.Success) { $out.Version = $vm.Groups[1].Value }
    else { $f += 'it states no version ("as of version **x.y.z**")' }
    $fm = [regex]::Match($norm, '(?s)```text\n(.*?)\n```')
    if (-not $fm.Success) { $f += 'it has no ```text block' }
    else {
        $out.Block = ConvertFrom-P20CountsBlock -Text $fm.Groups[1].Value
        foreach ($b in @($out.Block.Findings)) { $f += "its block: $b" }
    }
    if ($f.Count -eq 0) {
        $want = Format-P20TestCountsFile -Lines @($out.Block.Lines) -Version $out.Version
        if ($norm -cne $want) { $f += 'its text is not what the writer writes: it was edited by hand' }
    }
    if ($PSBoundParameters.ContainsKey('ExpectedVersion') -and $out.Version -and ($out.Version -cne $ExpectedVersion)) {
        $f += "it is as of version $($out.Version) and consts.json says $($ExpectedVersion): the release pull request sets the version and writes this page together"
    }
    $out.Findings = $f
    return $out
}

function Read-P20ExpectedCounts {
    <#
      The totals docs/TEST-COUNTS.md states, for Test's `expected vs actual`
      lines: information, never a verdict -- the page is written at a release
      and main moves on between them. -Path is the page. A line that is not
      there, or not a count, is $null in its slot.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $out = @{ cli = $null; agent = $null; web = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $fm = [regex]::Match($text, '(?s)```text\n(.*?)\n```')
    if (-not $fm.Success) { return $out }
    $p = Get-P20CountLinePatterns
    foreach ($l in @($fm.Groups[1].Value -split "`n" | ForEach-Object { $_.Trim() })) {
        $m = [regex]::Match($l, $p.CliTotal)
        if ($m.Success) { $out.cli = @{ Suites = [int]$m.Groups[1].Value; Total = [int]$m.Groups[2].Value }; continue }
        $m = [regex]::Match($l, $p.Pytest)
        if ($m.Success) {
            $skipped = 0
            if ($m.Groups[2].Success) { $skipped = [int]$m.Groups[2].Value }
            $out.agent = @{ Passed = [int]$m.Groups[1].Value; Skipped = $skipped }
            continue
        }
        $m = [regex]::Match($l, $p.Web)
        if ($m.Success) { $out.web = @{ Suites = [int]$m.Groups[1].Value; Total = [int]$m.Groups[2].Value } }
    }
    return $out
}

function Get-P20TypedCountLines {
    <#
      Every line of a document that types a test count. -Docs maps a
      package-relative path to its text; docs/TEST-COUNTS.md is the one page
      allowed them and is not read. A line is a count line when a Typed
      pattern of Get-P20CountLinePatterns matches it, inside a code fence or
      out. One sentence per line, naming the file and its line number, in path
      order.
    #>
    param([System.Collections.IDictionary]$Docs = @{})
    $p = Get-P20CountLinePatterns
    $cf = Get-P20TestCountsFile
    $typed = @($p.TypedSuiteList, $p.TypedCliTotal, $p.TypedPytest, $p.TypedWeb)
    $paths = [string[]]@($Docs.Keys)
    [array]::Sort($paths, [System.StringComparer]::Ordinal)
    $found = @()
    foreach ($path in $paths) {
        if ($path -ceq $cf.Path) { continue }
        $lines = @(([string]$Docs[$path]) -split "\r?\n")
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($pat in $typed) {
                $m = [regex]::Match($lines[$i], $pat)
                if (-not $m.Success) { continue }
                $said = $m.Value
                if ($said.Length -gt 60) { $said = $said.Substring(0, 60) + '...' }
                $found += "$path, line $($i + 1): '$said' is a test count, and the counts live in $($cf.Path) alone -- link to it ($($cf.Writer) writes it at a release)"
                break
            }
        }
    }
    return $found
}

function Get-P20TestCountsChangeFindings {
    <#
      The counts file changes only with the version. -Paths is a pull
      request's changed files; -BaseVersion and -HeadVersion are consts.json's
      `version` at its base and at its head; -BaseHadPage says whether
      docs/TEST-COUNTS.md existed at the base. A change that touches the page
      -- edits or deletes it -- and leaves the version as it was is one
      finding, naming the release step. The one exemption is the page being
      introduced: it did not exist at the base. Any other change, none.
    #>
    param(
        [string[]]$Paths = @(),
        [AllowEmptyString()][string]$BaseVersion = '',
        [AllowEmptyString()][string]$HeadVersion = '',
        [bool]$BaseHadPage = $true
    )
    $cf = Get-P20TestCountsFile
    $clean = @($Paths | ForEach-Object { ([string]$_).Trim() -replace '\\', '/' } | Where-Object { $_ })
    if ($clean -cnotcontains $cf.Path) { return @() }
    if (-not $BaseHadPage) { return @() }
    if ($BaseVersion -and ($BaseVersion -cne $HeadVersion)) { return @() }
    $was = $BaseVersion
    if (-not $was) { $was = '(none)' }
    return @("this change edits $($cf.Path) and leaves consts.json's version at $($was): the counts are written only in a release pull request, which sets the new version and runs $($cf.Writer) from a full run's block (AGENTS.md, ""A release is a tag on main"")")
}

function Get-P20CiPathClass {
    <#
      What one changed path can affect, for CI's filter (Get-P20CiScope). The
      path is git's: relative to the root, forward slashes, case as committed.
        changelog   changelog.d/ and CHANGELOG.md: no half. The contract job's
                    CLI set (Changelog, DocCounts, Portability) and its markdown
                    lint read them.
        prose       docs/modules/*.md, docs/SCENARIOS.md and docs/KNOWN-GAPS.md:
                    no half. Documents no full suite asserts beyond what the
                    contract job runs: Menu's parity and Python spelling,
                    DocCounts' gap links, Portability's links and sweeps, and the
                    markdown lint.
        web         anything under web/, its README included: the web job, and
                    the contract set beside it.
        shared      a path more than one half reads: consts.json,
                    config.default.json, agent/, Scripts/, Prompt20Toolkit/,
                    Config/, Tests/, .github/, samples/hub/, agentic/,
                    templates/, every other document under docs/ and every
                    other root document.
        unclassified anything else, read as shared: a path the rule has never
                    heard of runs every job rather than none.
      Returns @{ Class; Halves }. Halves is empty for a path that reaches the
      contract job alone.
    #>
    param([string]$Path)
    $all = @(Get-P20TestHalves)
    if ($Path -cmatch '^changelog\.d/' -or $Path -ceq 'CHANGELOG.md') { return @{ Class = 'changelog'; Halves = @() } }
    if ($Path -cmatch '^docs/modules/[^/]+\.md$' -or @('docs/SCENARIOS.md', 'docs/KNOWN-GAPS.md') -ccontains $Path) { return @{ Class = 'prose'; Halves = @() } }
    if ($Path -cmatch '^web/') { return @{ Class = 'web'; Halves = @('web') } }
    $sharedFiles = @('consts.json', 'config.default.json')
    $sharedDirs = @('agent/', 'Scripts/', 'Prompt20Toolkit/', 'Config/', 'Tests/', '.github/', 'samples/hub/', 'agentic/', 'templates/', 'docs/')
    if ($sharedFiles -ccontains $Path) { return @{ Class = 'shared'; Halves = $all } }
    foreach ($d in $sharedDirs) {
        if ($Path.StartsWith($d, [System.StringComparison]::Ordinal)) { return @{ Class = 'shared'; Halves = $all } }
    }
    if ($Path -cmatch '^[^/]+\.md$') { return @{ Class = 'shared'; Halves = $all } }
    return @{ Class = 'unclassified'; Halves = $all }
}

function Get-P20CiScope {
    <#
      Which of verify.yml's Ubuntu jobs a run needs. Every event but a pull
      request runs the three halves. A pull request runs the half each changed
      path can affect (Get-P20CiPathClass), the union over its paths; a pull
      request that lists no path runs everything. A changelog or prose path
      reaches the contract job alone. The contract job runs on a pull request
      where a half is left out: the cross-half suites of the halves that did
      not run, and the markdown lint when the web job did not.
      Returns cli, agent, web and contract as booleans, and Paths: each path
      with its class, in the order given.
    #>
    param([string]$Event, [string[]]$Paths = @())
    $out = [ordered]@{ cli = $false; agent = $false; web = $false; contract = $false; Paths = @() }
    $all = @(Get-P20TestHalves)
    $clean = @($Paths | ForEach-Object { ([string]$_).Trim() -replace '\\', '/' } | Where-Object { $_ })
    if ($Event -ne 'pull_request' -or $clean.Count -eq 0) {
        foreach ($h in $all) { $out[$h] = $true }
        return $out
    }
    $rows = @()
    foreach ($p in $clean) {
        $c = Get-P20CiPathClass -Path $p
        foreach ($h in $c.Halves) { $out[$h] = $true }
        $rows += , @($p, $c.Class)
    }
    $out.Paths = $rows
    $out.contract = (@($all | Where-Object { -not $out[$_] }).Count -gt 0)
    return $out
}

function Get-P20PasteLines {
    <#
      The four lines tkTest prints for docs/TEST-COUNTS.md, built from one run: the
      CLI's per-suite line and total (as the CLI runner printed them, passed in
      -CliLines), then `pytest: ...` and `web: ...`. A half that did not run, or
      did not pass, prints a line that SAYS so in that line's place -- never a
      number to copy -- and ConvertFrom-P20CountsBlock refuses it.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Records,
        [string[]]$CliLines = @()
    )
    $out = @()
    if (@($CliLines).Count -eq 2) { $out += @($CliLines) }
    else { $out += 'CLI: not printed -- the CLI half did not run every suite and pass' }

    $a = $null
    if ($Records.Contains('agent')) { $a = $Records['agent'] }
    if ($null -eq $a) { $out += 'pytest: not run -- this run did not include the agent half' }
    elseif ($a.result -eq 'skip') { $out += "pytest: NOT AVAILABLE -- no python with pytest was found: $($a.reason)" }
    elseif ($a.result -ne 'pass') { $out += 'pytest: not printed -- the agent half did not pass' }
    else {
        $pc = ConvertFrom-P20PytestOutput -Text ([string]$a.line)
        $s = "$($pc.Passed) passed"
        if ($pc.Skipped -gt 0) { $s += ", $($pc.Skipped) skipped" }
        if ($pc.Subtests -gt 0) { $s += ", $($pc.Subtests) subtests" }
        if ($a.Contains('python') -and $a.python) { $s += " (via $($a.python))" }
        $out += "pytest: $s"
    }

    $w = $null
    if ($Records.Contains('web')) { $w = $Records['web'] }
    if ($null -eq $w) { $out += 'web: not run -- this run did not include the web half' }
    elseif ($w.result -eq 'skip') { $out += "web: not run -- skipped: $($w.reason)" }
    elseif ($w.result -ne 'pass') { $out += 'web: not printed -- the web half did not pass' }
    else {
        $suitesRan = 0
        if ($w.Contains('suites')) { $suitesRan = $w.suites }
        $out += "web: $suitesRan suites, $($w.total) tests"
    }
    return $out
}

function ConvertTo-P20PlainTable {
    <# A ConvertFrom-Json object as ordered hashtables, all the way down (5.1 has no hashtable switch on ConvertFrom-Json). #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-P20PlainTable $p.Value }
        return $h
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in $Value.Keys) { $h[$k] = ConvertTo-P20PlainTable $Value[$k] }
        return $h
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return , @($Value | ForEach-Object { ConvertTo-P20PlainTable $_ })
    }
    return $Value
}

function Read-P20TestSummary {
    <# The summary file as ordered hashtables, or $null when there is none or it does not parse. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($Path)
        if (-not $raw.Trim()) { return $null }
        return (ConvertTo-P20PlainTable ($raw | ConvertFrom-Json))
    }
    catch { return $null }
}

function Get-P20SuiteHalf {
    <# A suite entry's half; an entry written before halves existed is the CLI's. #>
    param($Entry)
    if ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('half') -and $Entry['half']) { return [string]$Entry['half'] }
    return (Get-P20LegacyTestHalf)
}

function Merge-P20TestSummary {
    <#
      Write the records in -Halves (half -> record) into the `halves` block
      and the entries in -Suites (name -> entry, each carrying `half`) into
      `suites`, keeping every other half's as the file had them. The suites of
      each half in -ReplaceSuitesOf are dropped first -- by default the halves
      written: a CLI run drops the CLI suites it did not run, exactly as the
      runner always did, and leaves the agent's and the web's alone. Test
      passes the agent and web only, because the CLI's suites are the
      runner's own and it has just written them. -Top sets top-level keys
      (the CLI runner's totals). Written UTF-8 without a BOM; every reader
      takes either. An empty -Path -- a marked run with no history folder --
      writes nothing.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [System.Collections.IDictionary]$Halves = @{},
        [System.Collections.IDictionary]$Suites = @{},
        [System.Collections.IDictionary]$Top = @{},
        [string[]]$ReplaceSuitesOf
    )
    if (-not $Path) { return }
    $existing = Read-P20TestSummary -Path $Path
    if ($null -eq $existing) { $existing = [ordered]@{} }

    $written = @($Halves.Keys)
    if ($PSBoundParameters.ContainsKey('ReplaceSuitesOf')) { $written = @($ReplaceSuitesOf) }
    $out = [ordered]@{}
    $out['machine'] = [System.Environment]::MachineName
    $out['timestamp'] = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    foreach ($k in $existing.Keys) {
        if (@('machine', 'timestamp', 'suites', 'halves') -contains $k) { continue }
        $out[$k] = $existing[$k]
    }
    foreach ($k in $Top.Keys) { $out[$k] = $Top[$k] }

    $suitesOut = [ordered]@{}
    if ($existing.Contains('suites') -and $existing['suites'] -is [System.Collections.IDictionary]) {
        foreach ($name in $existing['suites'].Keys) {
            $entry = $existing['suites'][$name]
            if ($written -contains (Get-P20SuiteHalf $entry)) { continue }
            $suitesOut[$name] = $entry
        }
    }
    foreach ($name in $Suites.Keys) { $suitesOut[$name] = $Suites[$name] }
    $out['suites'] = $suitesOut

    $halvesOut = [ordered]@{}
    $oldHalves = $null
    if ($existing.Contains('halves') -and $existing['halves'] -is [System.Collections.IDictionary]) { $oldHalves = $existing['halves'] }
    foreach ($h in (Get-P20TestHalves)) {
        if ($Halves.Contains($h)) { $halvesOut[$h] = $Halves[$h] }
        elseif ($null -ne $oldHalves -and $oldHalves.Contains($h)) { $halvesOut[$h] = $oldHalves[$h] }
    }
    $out['halves'] = $halvesOut

    $json = $out | ConvertTo-Json -Depth 6
    $folder = Split-Path -Parent $Path
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Get-P20TestHalfRecords {
    <#
      What a reader shows for each half: the summary's `halves` block where it
      has one, and for a file that predates it, the CLI half summed from its
      suite entries. A half with no record is absent from the answer.
    #>
    param($Summary)
    $out = [ordered]@{}
    if ($null -eq $Summary) { return $out }
    $halves = $null
    if ($Summary.Contains('halves') -and $Summary['halves'] -is [System.Collections.IDictionary]) { $halves = $Summary['halves'] }
    foreach ($h in (Get-P20TestHalves)) {
        if ($null -ne $halves -and $halves.Contains($h)) { $out[$h] = $halves[$h] }
    }
    $legacy = Get-P20LegacyTestHalf
    if (-not $out.Contains($legacy) -and $Summary.Contains('suites') -and $Summary['suites'] -is [System.Collections.IDictionary]) {
        $passed = 0; $total = 0; $anyFail = $false; $seen = 0; $warned = 0
        foreach ($name in $Summary['suites'].Keys) {
            $e = $Summary['suites'][$name]
            if ((Get-P20SuiteHalf $e) -ne $legacy) { continue }
            $seen++
            $passed += [int]$e['passed']; $total += [int]$e['total']
            if ($e['result'] -eq 'fail') { $anyFail = $true }
            if ($e['result'] -eq 'warn') { $warned++ }
        }
        if ($seen -gt 0) {
            $result = 'pass'
            if ($anyFail) { $result = 'fail' }
            $out[$legacy] = [ordered]@{ result = $result; passed = $passed; failed = ($total - $passed); skipped = $warned; total = $total; timestamp = [string]$Summary['timestamp'] }
        }
    }
    return $out
}
