<#
.SYNOPSIS
    The rules behind {cliPrefix}Test, in one file. Dot-source it.

.DESCRIPTION
    Not a command. Everything the verb works OUT about a test run lives here, so
    the verb (Scripts/Invoke-TestAll.ps1), the CLI runner (Tests/Test-Toolkit.ps1),
    Setup (Scripts/Test-Prerequisites.ps1), CI's gate (Scripts/Test-CiHalf.ps1)
    and the suite (Tests/Test-TestAll.ps1) read one answer:

      Get-P20TestHalves            the three halves, in the order Test runs them.
      Get-P20TestSummaryPath       test-summary.<machine>.json -- the one place
                                   the file's name and the machine rule live.
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
      Read-P20ExpectedCounts       the three totals docs/TESTING.md prints.
      Get-P20PasteBlock            docs/TESTING.md's paste block, each line given
                                   to the half it belongs to -- the one rule the
                                   drift check and CI's carried-lines check read.
      Get-P20CountLinePatterns     the count lines {cliPrefix}TestToolkit -DocCounts
                                   reads in docs/TESTING.md, AGENTS.md and VERIFY.md.
      Get-P20CountOnlyPaths        which of those files a diff changes in its
                                   count lines and nowhere else.
      Get-P20CiScope               which of CI's jobs a change runs, from the
                                   event and the files it changed.
      Get-P20CarriedCountFindings  a pull request's paste lines for the halves
                                   that did not run, against main's.
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
      test-summary.<machine>.json at the package root. The CLI runner, Test and
      Setup all ask here; agent/core/log.py globs test-summary.*.json from the
      same root. The machine is [System.Environment]::MachineName -- the rule
      Write-P20TestResult and the usage log use.
    #>
    param([Parameter(Mandatory)][string]$PackageRoot)
    return (Join-Path $PackageRoot ("test-summary.{0}.json" -f [System.Environment]::MachineName))
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

function Read-P20ExpectedCounts {
    <#
      The totals docs/TESTING.md prints at its head, which are pasted
      from a macOS run after a merge: the tkTestToolkit line, the pytest line
      and the npm test line of its opening code blocks. Information for Test's
      `expected vs actual` lines, never a verdict. A line that is not there is
      $null in its slot.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $out = @{ cli = $null; agent = $null; web = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    $text = [System.IO.File]::ReadAllText($Path)
    $m = [regex]::Match($text, '(?m)^\s*\w*TestToolkit\s+#\s*(\d+) suites, (\d+) assertions')
    if ($m.Success) { $out.cli = @{ Suites = [int]$m.Groups[1].Value; Total = [int]$m.Groups[2].Value } }
    $m = [regex]::Match($text, '(?m)-m pytest Tests/\s+#\s*(\d+) passed(?:, (\d+) skipped)?')
    if ($m.Success) {
        $skipped = 0
        if ($m.Groups[2].Success) { $skipped = [int]$m.Groups[2].Value }
        $out.agent = @{ Passed = [int]$m.Groups[1].Value; Skipped = $skipped }
    }
    $m = [regex]::Match($text, '(?m)npm test\s+#[^\r\n]*?(\d+) suites, (\d+) tests')
    if ($m.Success) { $out.web = @{ Suites = [int]$m.Groups[1].Value; Total = [int]$m.Groups[2].Value } }
    return $out
}

function Get-P20PasteBlockMatch {
    <#
      Where docs/TESTING.md's paste block is: the regex match whose first group
      is the block's text, between its ```text fence and the closing one. $null
      when there is none. Get-P20PasteBlock reads its lines from it, and
      Get-P20CountLineNumbers its line numbers.
    #>
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text, '(?s)\*\*The counts, after a merge\.\*\*.*?```text\r?\n(.*?)\r?\n```')
    if (-not $m.Success) { return $null }
    return $m
}

function Get-P20CountLinePatterns {
    <#
      The count lines the documents state, one regex each -- the patterns
      Tests/Test-DocCounts.ps1 and Tests/Get-TestingDocDrift.ps1 read them
      with, so CI's count-line exemption (Get-P20CountOnlyPaths) cannot cover a
      line they do not check:
        TestingRow       docs/TESTING.md's `tkTestToolkit` table row
        TestingCliTotal  its command block's `tkTestToolkit # N suites, M assertions`
                         (group 1 the figure, group 2 the suite count)
        TestingPytest    its command block's pytest totals (group 1)
        TestingWeb       its command block's npm test totals (group 1)
        AgentsCli        AGENTS.md's `tkTestToolkit # the CLI -- N suites, ...`
        VerifyCli        VERIFY.md's Gate 4 `On this commit that is **N suites, ...`
      docs/TESTING.md's paste block is the seventh, found by Get-P20PasteBlockMatch.
    #>
    return [ordered]@{
        TestingRow      = '^\|\s*`tkTestToolkit`\s*\|'
        TestingCliTotal = 'tkTestToolkit\s+#\s*((\d+) suites, \d+ assertions)'
        TestingPytest   = 'pytest Tests/\s+#\s*(.+?)\s+--'
        TestingWeb      = 'npm test\s+#\s*(?:.*?then\s+)?(\d+ suites, \d+ tests)'
        AgentsCli       = 'tkTestToolkit\s+#\s*the CLI -- (\d+) suites,'
        VerifyCli       = 'is \*\*(\d+) suites,'
    }
}

function Get-P20CountLineRules {
    <# The files that carry count lines, each with its patterns and whether it holds the paste block. #>
    $p = Get-P20CountLinePatterns
    return [ordered]@{
        'docs/TESTING.md' = @{ Patterns = @($p.TestingRow, $p.TestingCliTotal, $p.TestingPytest, $p.TestingWeb); PasteBlock = $true }
        'AGENTS.md'       = @{ Patterns = @($p.AgentsCli); PasteBlock = $false }
        'VERIFY.md'       = @{ Patterns = @($p.VerifyCli); PasteBlock = $false }
    }
}

function Get-P20CountLineNumbers {
    <#
      The 1-based numbers of the count lines in one file's text: every line a
      pattern of its rule matches, and for docs/TESTING.md every line inside the
      paste block's fence. A file with no rule has none.
    #>
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $nums = @{}
    $rules = Get-P20CountLineRules
    if (-not $rules.Contains($Path) -or -not $Text) { return $nums }
    $rule = $rules[$Path]
    $lines = @($Text -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($pat in $rule.Patterns) {
            if ($lines[$i] -match $pat) { $nums[$i + 1] = $true; break }
        }
    }
    if ($rule.PasteBlock) {
        $m = Get-P20PasteBlockMatch -Text $Text
        if ($null -ne $m) {
            $g = $m.Groups[1]
            $first = ([regex]::Matches($Text.Substring(0, $g.Index), "\n")).Count + 1
            $count = ([regex]::Matches($g.Value, "\n")).Count + 1
            for ($n = $first; $n -lt $first + $count; $n++) { $nums[$n] = $true }
        }
    }
    return $nums
}

function Get-P20DiffChangedLines {
    <#
      The changed lines of a `git diff -U0`: one @{ Path; Side; Line; Text } per
      removed line (Side old, its number in the old file) and per added line
      (Side new, its number in the new file). Each hunk is read by the counts
      its header states, so a removed line that itself starts with `--` is
      still a line.
    #>
    param([AllowEmptyString()][string]$Diff)
    $out = @()
    if (-not $Diff) { return $out }
    $lines = @($Diff -split "\r?\n")
    $path = ''; $oldPath = ''
    $i = 0
    while ($i -lt $lines.Count) {
        $l = $lines[$i]
        if ($l.StartsWith('diff --git ')) { $path = ''; $oldPath = ''; $i++; continue }
        if ($l.StartsWith('--- ')) { $oldPath = $l.Substring(4) -replace '^a/', ''; $i++; continue }
        if ($l.StartsWith('+++ ')) {
            $path = $l.Substring(4) -replace '^b/', ''
            if ($path -eq '/dev/null') { $path = $oldPath }
            $i++; continue
        }
        $h = [regex]::Match($l, '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
        if (-not $h.Success) { $i++; continue }
        $oldAt = [int]$h.Groups[1].Value; $oldLeft = 1; if ($h.Groups[2].Success) { $oldLeft = [int]$h.Groups[2].Value }
        $newAt = [int]$h.Groups[3].Value; $newLeft = 1; if ($h.Groups[4].Success) { $newLeft = [int]$h.Groups[4].Value }
        $i++
        while (($oldLeft + $newLeft) -gt 0 -and $i -lt $lines.Count) {
            $c = $lines[$i]
            if ($c.StartsWith('-') -and $oldLeft -gt 0) {
                $out += @{ Path = $path; Side = 'old'; Line = $oldAt; Text = $c.Substring(1) }
                $oldAt++; $oldLeft--
            }
            elseif ($c.StartsWith('+') -and $newLeft -gt 0) {
                $out += @{ Path = $path; Side = 'new'; Line = $newAt; Text = $c.Substring(1) }
                $newAt++; $newLeft--
            }
            elseif (-not $c.StartsWith('\')) { break }
            $i++
        }
    }
    return $out
}

function Get-P20CountOnlyPaths {
    <#
      Which files a diff changes in their count lines alone. -Diff is
      `git diff -U0` over docs/TESTING.md, AGENTS.md and VERIFY.md; -BaseTexts
      and -HeadTexts map each path to its text before and after. A removed line
      is a count line when its number is one in the base text, an added line
      when its number is one in the head text (Get-P20CountLineNumbers).
      Returns path -> @{ CountOnly; Other }, Other the first changed line that
      is not a count line. A path with no rule is never count-only.
    #>
    param(
        [AllowEmptyString()][string]$Diff,
        [hashtable]$BaseTexts = @{},
        [hashtable]$HeadTexts = @{}
    )
    $out = [ordered]@{}
    $nums = @{}
    foreach ($c in @(Get-P20DiffChangedLines -Diff $Diff)) {
        $key = $c.Side + '|' + $c.Path
        if (-not $nums.ContainsKey($key)) {
            $t = ''
            if ($c.Side -eq 'old' -and $BaseTexts.ContainsKey($c.Path)) { $t = [string]$BaseTexts[$c.Path] }
            if ($c.Side -eq 'new' -and $HeadTexts.ContainsKey($c.Path)) { $t = [string]$HeadTexts[$c.Path] }
            $nums[$key] = Get-P20CountLineNumbers -Path $c.Path -Text $t
        }
        if (-not $out.Contains($c.Path)) { $out[$c.Path] = @{ CountOnly = $true; Other = '' } }
        if ($out[$c.Path].CountOnly -and -not $nums[$key].ContainsKey($c.Line)) {
            $out[$c.Path].CountOnly = $false
            $said = $c.Text.Trim()
            if ($said.Length -gt 100) { $said = $said.Substring(0, 100) + '...' }
            $out[$c.Path].Other = "$($c.Side) line $($c.Line): $said"
        }
    }
    return $out
}

function Get-P20PasteLineHalf {
    <#
      The half one trimmed paste-block line belongs to: `N suites, M assertions`
      and the per-suite line (`Consts 208, Compat 1756, ...`) are the CLI's,
      `pytest: ...` the agent's, `web: ...` the web UI's. Any other line -- the
      block's own heading -- is no half's, and the answer is ''.
    #>
    param([string]$Line)
    if ($Line -match '^\d+ suites, \d+ assertions$') { return 'cli' }
    if ($Line -match '^pytest: ') { return 'agent' }
    if ($Line -match '^web: ') { return 'web' }
    if ($Line -match '(?<=^|,\s)[A-Z][A-Za-z]+ \d+(?=,|$)') { return 'cli' }
    return ''
}

function Get-P20PasteBlock {
    <#
      docs/TESTING.md's paste block: the first ```text fence after
      "**The counts, after a merge.**", each line trimmed and blank lines
      dropped. Lines holds them all in order; cli, agent and web hold each
      half's own lines (Get-P20PasteLineHalf). $null when there is no block.
      Tests/Get-TestingDocDrift.ps1 and CI's carried-lines check read the
      block through this, so the two cannot find different lines.
    #>
    param([AllowEmptyString()][string]$Text)
    $m = Get-P20PasteBlockMatch -Text $Text
    if ($null -eq $m) { return $null }
    $lines = @($m.Groups[1].Value -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $out = [ordered]@{ Lines = $lines; cli = @(); agent = @(); web = @() }
    foreach ($l in $lines) {
        $h = Get-P20PasteLineHalf -Line $l
        if ($h) { $out[$h] = @($out[$h]) + @($l) }
    }
    return $out
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
      reaches the contract job alone. A path in -CountOnly
      (Get-P20CountOnlyPaths: docs/TESTING.md, AGENTS.md or VERIFY.md changed
      in its count lines alone) reaches nothing by itself; a pull request whose
      every path is one runs everything. The contract job runs on a
      pull request where a half is left out: the cross-half suites of the halves
      that did not run, the markdown lint when the web job did not, and the
      carried-lines check.
      Returns cli, agent, web and contract as booleans, and Paths: each path
      with its class, in the order given.
    #>
    param([string]$Event, [string[]]$Paths = @(), [string[]]$CountOnly = @())
    $out = [ordered]@{ cli = $false; agent = $false; web = $false; contract = $false; Paths = @() }
    $all = @(Get-P20TestHalves)
    $clean = @($Paths | ForEach-Object { ([string]$_).Trim() -replace '\\', '/' } | Where-Object { $_ })
    if ($Event -ne 'pull_request' -or $clean.Count -eq 0) {
        foreach ($h in $all) { $out[$h] = $true }
        return $out
    }
    $rows = @()
    $contractOnly = $false
    foreach ($p in $clean) {
        if (@($CountOnly) -ccontains $p) { $rows += , @($p, 'count lines'); continue }
        $c = Get-P20CiPathClass -Path $p
        foreach ($h in $c.Halves) { $out[$h] = $true }
        if (@($c.Halves).Count -eq 0) { $contractOnly = $true }
        $rows += , @($p, $c.Class)
    }
    $out.Paths = $rows
    # Count lines alone reach no half; a change of nothing else runs every half,
    # so a paste of all three lines is held by the runs it pastes from. A
    # changelog or prose path beside them is the contract job's alone.
    if (@($all | Where-Object { $out[$_] }).Count -eq 0 -and -not $contractOnly) {
        foreach ($h in $all) { $out[$h] = $true }
        return $out
    }
    $out.contract = (@($all | Where-Object { -not $out[$_] }).Count -gt 0)
    return $out
}

function Get-P20CarriedCountFindings {
    <#
      A pull request that did not run a half carries that half's paste lines
      from main: it cannot have a new count for a half it never ran. So the
      paste-block lines of each half not in -Ran must be main's, line for line
      and case for case; a difference is a count somebody typed. -BaseText is
      main's docs/TESTING.md, -HeadText the change's. Returns one finding per
      half that differs, naming the line; empty when they agree, and empty when
      every half ran.
    #>
    param(
        [AllowEmptyString()][string]$BaseText,
        [AllowEmptyString()][string]$HeadText,
        [string[]]$Ran = @()
    )
    $carried = @(Get-P20TestHalves | Where-Object { @($Ran) -notcontains $_ })
    if ($carried.Count -eq 0) { return @() }
    $base = Get-P20PasteBlock -Text $BaseText
    $head = Get-P20PasteBlock -Text $HeadText
    if ($null -eq $base) { return @("main's docs/TESTING.md has no paste block under `"The counts, after a merge`"") }
    if ($null -eq $head) { return @("this change's docs/TESTING.md has no paste block under `"The counts, after a merge`"") }
    $findings = @()
    foreach ($h in $carried) {
        $b = @($base[$h])
        $t = @($head[$h])
        $n = [Math]::Max($b.Count, $t.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $bl = '(none)'; if ($i -lt $b.Count) { $bl = $b[$i] }
            $tl = '(none)'; if ($i -lt $t.Count) { $tl = $t[$i] }
            if ($bl -cne $tl) {
                $findings += "the $h half's paste line '$tl' is not main's '$bl': the $h job did not run on this pull request, so the line is carried from main as it stands"
                break
            }
        }
    }
    return $findings
}

function Get-P20PasteLines {
    <#
      The lines docs/TESTING.md's paste block holds, built from one tkTest run: the
      CLI's per-suite line and total (as the CLI runner printed them, passed in
      -CliLines), then `pytest: ...` and `web: ...`. A half that did not run, or
      did not pass, prints a line that SAYS so in that line's place -- never a
      number to copy. Tests/Get-TestingDocDrift.ps1 holds the same shapes.
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
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
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
      takes either.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IDictionary]$Halves = @{},
        [System.Collections.IDictionary]$Suites = @{},
        [System.Collections.IDictionary]$Top = @{},
        [string[]]$ReplaceSuitesOf
    )
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
