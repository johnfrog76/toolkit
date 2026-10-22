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
      ConvertFrom-P20JestOutput    jest's `Tests:` and `Test Suites:` lines -> counts.
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
    return @{ Found = $false; Passed = 0; Failed = 0; Skipped = 0; Total = 0; Suites = 0; SuitesFailed = 0; Subtests = 0; Line = '' }
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
    #>
    param([string]$Text)
    $c = New-P20Counts
    if (-not $Text) { return $c }
    $testsLine = ''
    $suitesLine = ''
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
      CLI runner's own rule for a suite (Get-P20SuiteVerdict).
    #>
    param($Counts, [int]$ExitCode)
    if (-not $Counts.Found) { return @{ Result = 'fail'; Detail = "no summary line (exit $ExitCode)" } }
    if ($Counts.Failed -gt 0) { return @{ Result = 'fail'; Detail = "$($Counts.Failed) failed" } }
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
    elseif ($a.result -eq 'skip') { $out += "pytest: not run -- skipped: $($a.reason)" }
    elseif ($a.result -ne 'pass') { $out += 'pytest: not printed -- the agent half did not pass' }
    else {
        $pc = ConvertFrom-P20PytestOutput -Text ([string]$a.line)
        $s = "$($pc.Passed) passed"
        if ($pc.Skipped -gt 0) { $s += ", $($pc.Skipped) skipped" }
        if ($pc.Subtests -gt 0) { $s += ", $($pc.Subtests) subtests" }
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
