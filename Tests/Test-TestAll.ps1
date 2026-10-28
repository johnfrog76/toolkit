<#
.SYNOPSIS
    {cliPrefix}Test -- the three halves in one run, with all three STUBBED.

.DESCRIPTION
    Never runs a real suite: it would recurse, and it would take the length of
    the three runs. A scratch package holds the verb's scripts, a fake
    Tests/Test-Toolkit.ps1 that prints a known `Total:` line and writes CLI suite
    entries the way the runner does, and a docs/TESTING.md with known counts. A
    scratch PATH holds a fake python and a fake npm, each printing a known
    summary. Then:

      1. The parsers   pytest's closing line (with and without its rule, errors,
                       subtests), jest's Tests: and Test Suites: lines, the CLI
                       runner's Total line, the verdict rule -- and the expected
                       counts read from the REAL docs/TESTING.md, so a doc edit
                       that moves those lines fails here.
      1b. CI's gate    Get-P20CiHalfVerdict over every shape of a half's
                       transcript: a pass, a failure, an exit, no
                       summary line, a skipped half, nothing passed, and the
                       browser smoke's closing line; the gate script run as
                       .github/workflows/verify.yml runs it; and the workflow
                       reading each half and the smoke through it, its
                       Windows job importing under Windows PowerShell 5.1,
                       and every job behind the one switch with a timeout;
                       and pages.yml, the landing page's deploy, on the
                       button alone, with no secret, the Pages permissions
                       and a read, and its actions pinned to a major version.
      2. The merge     a half written replaces only that half's entries; a file
                       from before the halves reads as the CLI's alone.
      3. The verb      all three green; one failed (exit 2, stated); a half with
                       no summary line; each stated skip -- no Python, no httpx,
                       no npm, no node_modules, no pwsh (Windows PowerShell only);
                       nothing ran (exit 2); -Half; -Fast reaching the runner;
                       expected vs actual, equal and differing (never the
                       verdict); the web child with no webhook and the marker;
                       the summary file's three halves, and the CLI entries
                       exactly as the runner wrote them.
      4. The wiring    the runner writes half = cli through the shared merge.

    Run:  pwsh -File Tests/Test-TestAll.ps1
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path -Parent $scriptDir

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $Name"
        if ($Detail) { $msg += " -- $Detail" }
        Write-Host $msg -ForegroundColor Red
        $script:errors += $msg
    }
}

Write-Host ""
Write-Host "  Test -- the three halves in one run" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray

. (Join-Path $pkgRoot 'Scripts/TestAll-Rules.ps1')
. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
$consts = Get-P20Consts
$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

# -- 1. The parsers ---------------------------------------------------------------
Write-Host ""
Write-Host "-- The parsers --" -ForegroundColor Cyan

$c = ConvertFrom-P20PytestOutput -Text "collected 905 items`n`n========== 2 failed, 898 passed, 3 skipped, 882 subtests passed in 312.40s (0:05:12) =========="
Assert-True 'pytest: the closing line with its rule' ($c.Found -and $c.Passed -eq 898 -and $c.Failed -eq 2 -and $c.Skipped -eq 3) "$($c.Passed)/$($c.Failed)/$($c.Skipped)"
Assert-True 'pytest: `N subtests passed` is not a test' ($c.Passed -eq 898)
$c = ConvertFrom-P20PytestOutput -Text "900 passed, 3 skipped in 12.3s"
Assert-True 'pytest: the -q line, no rule' ($c.Found -and $c.Passed -eq 900 -and $c.Skipped -eq 3 -and $c.Failed -eq 0)
$c = ConvertFrom-P20PytestOutput -Text "=== 1 failed, 5 passed, 2 errors, 1 subtests failed in 3.1s ==="
Assert-True 'pytest: errors and failed subtests count as failures' ($c.Failed -eq 4 -and $c.Passed -eq 5) "$($c.Failed)"
$c = ConvertFrom-P20PytestOutput -Text "=== no tests ran in 0.01s ==="
Assert-True 'pytest: no tests ran is a line, with nothing passed' ($c.Found -and $c.Passed -eq 0)
$c = ConvertFrom-P20PytestOutput -Text "Traceback (most recent call last):`nImportError: boom"
Assert-True 'pytest: no closing line is not found' (-not $c.Found)

$c = ConvertFrom-P20JestOutput -Text "PASS src/a.test.ts`nTest Suites: 1 failed, 102 passed, 103 total`nTests:       2 failed, 1 skipped, 1229 passed, 1232 total`nSnapshots:   0 total"
Assert-True 'jest: Tests: and Test Suites:' ($c.Found -and $c.Passed -eq 1229 -and $c.Failed -eq 2 -and $c.Skipped -eq 1 -and $c.Total -eq 1232 -and $c.Suites -eq 103 -and $c.SuitesFailed -eq 1)
$c = ConvertFrom-P20JestOutput -Text "> node tests/viteconfig.mjs`nviteconfig: 1 failed"
Assert-True 'jest: npm test stopped before jest reported -- not found' (-not $c.Found)

$c = ConvertFrom-P20ToolkitOutput -Text "  |  Total: 6150/6153 passed           2100.0s |"
Assert-True 'CLI: the Total line, whatever frames it' ($c.Found -and $c.Passed -eq 6150 -and $c.Total -eq 6153 -and $c.Failed -eq 3)

$ok = @{ Found = $true; Failed = 0 }
Assert-True 'verdict: a line, no failure, exit 0 is a pass' ((Get-P20HalfVerdict -Counts $ok -ExitCode 0).Result -eq 'pass')
Assert-True 'verdict: a clean line and a non-zero exit is a failure' ((Get-P20HalfVerdict -Counts $ok -ExitCode 1).Result -eq 'fail')
$v = Get-P20HalfVerdict -Counts @{ Found = $false; Failed = 0 } -ExitCode 0
Assert-True 'verdict: no summary line is a failure, and says so' ($v.Result -eq 'fail' -and $v.Detail -like 'no summary line*') $v.Detail

# -- 1b. CI's verdict --------------------------------------------------------
# The rule .github/workflows/verify.yml reads each half by: Test's own verdict, one
# rule tighter. One row per shape the gate tells apart.
Write-Host ""
Write-Host "-- CI's verdict on a half's transcript --" -ForegroundColor Cyan
$ciTable = @(
    # half, transcript, exit, result, detail-like
    @('agent', "collected 931 items`n==== 928 passed, 3 skipped, 960 subtests passed in 301.2s ====", 0, 'pass', 'ok'),
    @('agent', "==== 1 failed, 927 passed, 3 skipped in 301.2s ====", 1, 'fail', '1 failed'),
    @('agent', "==== no tests ran in 0.02s ====", 5, 'fail', 'exit 5'),
    @('agent', "==== no tests ran in 0.02s ====", 0, 'fail', 'nothing passed*'),
    @('agent', "==== 12 skipped in 0.40s ====", 0, 'fail', 'nothing passed*'),
    @('agent', "ImportError: no module named fastapi", 2, 'fail', 'no summary line (exit 2)'),
    @('web', "Test Suites: 117 passed, 117 total`nTests:       1301 passed, 1301 total", 0, 'pass', 'ok'),
    @('web', "Test Suites: 1 failed, 116 passed, 117 total`nTests:       2 failed, 1299 passed, 1301 total", 1, 'fail', '2 failed'),
    @('web', "Test Suites: 0 total`nTests:       0 total", 0, 'fail', 'nothing passed*'),
    @('web', "> node tests/viteconfig.mjs`nviteconfig: 1 failed", 1, 'fail', 'no summary line (exit 1)'),
    @('cli', "  Results: 12/12 passed`n  |  Total: 6546/6546 passed     2100.0s |", 0, 'pass', 'ok'),
    @('cli', "  |  Total: 6540/6546 passed     2100.0s |", 1, 'fail', '6 failed'),
    @('cli', "  |  Total: 6546/6546 passed     2100.0s |", 2, 'fail', 'exit 2'),
    @('cli', "  |  Total: 0/0 passed     0.1s |", 0, 'fail', 'nothing passed*'),
    @('cli', "  SKIP  cli -- no pwsh on the PATH`n  Verdict: NOTHING RAN.", 2, 'fail', 'skipped: no pwsh on the PATH'),
    @('cli', "Import-Module: the module could not be loaded", 1, 'fail', 'no summary line (exit 1)'),
    @('smoke', "PASS  growth alone: its nav entry`nPASS  flip: the agent is the same process throughout`nsmoke: clean (matrix, 2 checks)", 0, 'pass', 'ok'),
    @('smoke', "PASS  growth alone: its nav entry`nFAIL  flip: the nav entry appears -- Home`nsmoke: 1 failure(s) (matrix, 2 checks)", 1, 'fail', '1 failed'),
    @('smoke', "smoke: clean (matrix, 0 checks)", 0, 'fail', 'nothing passed*'),
    @('smoke', "FAIL  chromium is not installed for Playwright.", 2, 'fail', 'no summary line (exit 2)'),
    @('smoke', "smoke: a11y -- 0 critical, 0 serious, 3 moderate, 1 minor over 48 pages", 0, 'pass', 'ok'),
    @('smoke', "smoke: a11y -- 1 critical, 2 serious, 0 moderate, 0 minor over 48 pages`nFAIL  a11y: 3 serious or critical finding(s) -- listed above", 1, 'fail', '3 failed'),
    @('smoke', "smoke: a11y -- 0 critical, 0 serious, 0 moderate, 0 minor over 0 pages", 0, 'fail', 'nothing passed*')
)
foreach ($row in $ciTable) {
    $v = Get-P20CiHalfVerdict -Half $row[0] -Text $row[1] -ExitCode $row[2]
    $last = (($row[1] -split "`n")[-1]).Trim()
    Assert-True "CI: $($row[0]) '$last' exit $($row[2]) -> $($row[3])" ($v.Result -eq $row[3] -and $v.Detail -like $row[4]) "got $($v.Result) '$($v.Detail)'"
}
$v = Get-P20CiHalfVerdict -Half 'cli' -Text "  Results: 0/0 passed`n  Results: 5/5 passed`n  PASS  quotes 'Results: 0/0 passed'`n  |  Total: 5/5 passed  1.0s |" -ExitCode 0
Assert-True 'CI: a CLI suite''s own 0/0 is a skip counted, not a failure' ($v.Result -eq 'pass' -and $v.Skipped -eq 1) "got $($v.Result), skipped $($v.Skipped)"
$v = Get-P20CiHalfVerdict -Half 'agent' -Text "==== 928 passed, 3 skipped in 301.2s ====" -ExitCode 0
Assert-True 'CI: pytest''s skipped tests are counted, not failed' ($v.Result -eq 'pass' -and $v.Skipped -eq 3)

# The gate as the workflow calls it: a child shell, a transcript file, exit 0 or 2.
$ciGate = Join-Path $pkgRoot 'Scripts/Test-CiHalf.ps1'
$ciScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-ci-243-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $ciScratch -Force | Out-Null
    $ciCases = @(
        @('green', "==== 928 passed, 3 skipped in 301.2s ====", 0, 0),
        @('red', "==== 1 failed, 927 passed in 301.2s ====", 1, 2),
        @('empty', "==== no tests ran in 0.02s ====", 0, 2)
    )
    foreach ($case in $ciCases) {
        $log = Join-Path $ciScratch "$($case[0]).log"
        [System.IO.File]::WriteAllText($log, $case[1] + "`n")
        $savedEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $said = (& pwsh -NoProfile -File $ciGate -Half agent -Path $log -ExitCode $case[2] 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
        finally { $ErrorActionPreference = $savedEap }
        Assert-True "CI gate: the $($case[0]) transcript exits $($case[3])" ($LASTEXITCODE -eq $case[3]) "exit $LASTEXITCODE -- $said"
    }
    $ErrorActionPreference = 'Continue'
    try { $null = & pwsh -NoProfile -File $ciGate -Half web -Path (Join-Path $ciScratch 'absent.log') -ExitCode 0 2>&1 }
    finally { $ErrorActionPreference = 'Stop' }
    Assert-True 'CI gate: no transcript at all exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
}
catch {
    Assert-True 'the CI gate cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $ciScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# The workflow calls the gate once per half, and reads no summary line of its own.
$workflowPath = Join-Path $pkgRoot '.github/workflows/verify.yml'
$workflow = ''
if (Test-Path -LiteralPath $workflowPath) { $workflow = [System.IO.File]::ReadAllText($workflowPath) }
foreach ($h in (Get-P20TestHalves)) {
    Assert-True "verify.yml reads the $h half through Test-CiHalf.ps1" ($workflow -match ("Test-CiHalf\.ps1 -Half " + $h + "\b"))
}
Assert-True 'verify.yml audits what ships: npm audit --omit=dev at high, and pip-audit over the agent requirements' (($workflow -match 'npm audit --omit=dev --audit-level=high') -and ($workflow -match 'pip_audit -r agent/requirements-dev\.txt'))
Assert-True 'verify.yml asks for no secret and reads with contents: read' (($workflow -notmatch 'secrets\.') -and ($workflow -match '(?m)^permissions:\s*\r?\n\s+contents: read'))
foreach ($mode in @('matrix', 'a11y')) {
    Assert-True "verify.yml reads the browser smoke's $mode mode through Test-CiHalf.ps1" ($workflow -match ('npm run smoke:' + $mode + ' 2>&1 \| Tee-Object[^\r\n]*\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half smoke\b'))
}
Assert-True 'verify.yml has a Windows job' ($workflow -match '(?m)^\s+runs-on: windows-latest\s*$')
Assert-True 'the Windows job runs the CLI from Windows PowerShell 5.1, the module path set inside that shell' `
    ($workflow -match "powershell\.exe -NoProfile -Command '\`$env:PSModulePath = \(Resolve-Path \.\); Import-Module \./Prompt20Toolkit/Prompt20Toolkit\.psd1 -Force; tkTest -Half cli; exit \`$LASTEXITCODE'")
$jobCount = [regex]::Matches($workflow, '(?m)^\s+runs-on:').Count
Assert-True 'verify.yml runs on pull requests (default types: labeled is NOT a trigger), pushes to main, the button, and a weekday schedule' `
    (($workflow -match '(?m)^\s+workflow_dispatch:') -and ($workflow -notmatch '(?m)^\s+types:') -and ($workflow -notmatch '(?m)^\s+if: .*labeled') -and ($workflow -match '(?ms)^\s+push:\s*\r?\n\s+branches: \[main\]') -and ($workflow -match '(?m)^\s+- cron: "[^"]+"'))
$windowsJob = $workflow.Substring($workflow.IndexOf('  windows:'))
Assert-True 'the Windows job runs on the schedule, the button and the ci label, and not on a push to main' `
    (($windowsJob -match "(?m)^\s+if: .*github\.event_name == 'schedule'") -and ($windowsJob -match "(?m)^\s+if: .*github\.event_name == 'workflow_dispatch'") -and ($windowsJob -match "(?m)^\s+if: .*labels\.\*\.name, 'ci'") -and ($windowsJob -notmatch "(?m)^\s+if: .*'push'"))
Assert-True 'a scheduled run has a concurrency group of its own and cancel-in-progress is only for pull requests' `
    (($workflow -match "group: verify-\$\{\{ github\.event_name == 'schedule'") -and ($workflow -match "cancel-in-progress: \$\{\{ github\.event_name == 'pull_request' \}\}"))
Assert-True 'every job in verify.yml has a timeout' ([regex]::Matches($workflow, '(?m)^\s+timeout-minutes: \d+').Count -eq $jobCount)

# The landing page's workflow: every push to main and the button, no secret, the
# deploy's two Pages permissions and a read, nothing more.
$pagesPath = Join-Path $pkgRoot '.github/workflows/pages.yml'
$pages = ''
if (Test-Path -LiteralPath $pagesPath) { $pages = [System.IO.File]::ReadAllText($pagesPath) }
Assert-True 'pages.yml runs on every push to main and from the button, and nothing else' `
    (($pages -match '(?ms)^on:\s*\r?\n\s+workflow_dispatch:\s*\r?\n\s+push:\s*\r?\n\s+branches: \[main\]\s*$') -and ($pages -notmatch '(?m)^\s+(pull_request|pull_request_target|schedule|workflow_run):'))
Assert-True 'pages.yml asks for no secret' (($pages -ne '') -and ($pages -notmatch 'secrets\.'))
$pagesGrants = @([regex]::Matches($pages, '(?m)^\s+([a-z-]+): (read|write)\s*$') | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value } | Sort-Object)
Assert-True 'pages.yml grants contents: read, pages: write and id-token: write, and nothing else' `
    (($pages -match '(?m)^permissions: \{\}\s*$') -and (($pagesGrants -join ',') -eq 'contents:read,id-token:write,pages:write')) ($pagesGrants -join ',')
$pagesUses = @([regex]::Matches($pages, '(?m)^\s+(?:- )?uses: (\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'every action pages.yml uses is pinned to a major version' `
    (($pagesUses.Count -gt 0) -and (@($pagesUses | Where-Object { $_ -notmatch '^actions/[a-z-]+@v\d+$' }).Count -eq 0)) ($pagesUses -join ', ')

# The release workflow runs on a tag push and nothing else, asks for no secret
# beyond the default token, and may write contents, nothing more.
$releasePath = Join-Path $pkgRoot '.github/workflows/release.yml'
$release = ''
if (Test-Path -LiteralPath $releasePath) { $release = [System.IO.File]::ReadAllText($releasePath) }
Assert-True 'release.yml runs on a tag push and nothing else' `
    (($release -match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+tags:') -and ($release -notmatch '(?m)^\s+(pull_request|pull_request_target|schedule|workflow_run|workflow_dispatch):'))
Assert-True 'release.yml asks for no secret beyond the default token' (($release -ne '') -and ($release -notmatch 'secrets\.'))
$releaseGrants = @([regex]::Matches($release, '(?m)^\s+([a-z-]+): (read|write)\s*$') | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value } | Sort-Object)
Assert-True 'release.yml grants contents: write and nothing else' `
    (($release -match '(?m)^permissions: \{\}\s*$') -and (($releaseGrants -join ',') -eq 'contents:write')) ($releaseGrants -join ',')
$releaseUses = @([regex]::Matches($release, '(?m)^\s+(?:- )?uses: (\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'every action release.yml uses is pinned to a major version' `
    (($releaseUses.Count -gt 0) -and (@($releaseUses | Where-Object { $_ -notmatch '^actions/[a-z-]+@v\d+$' }).Count -eq 0)) ($releaseUses -join ', ')
Assert-True 'release.yml reads its notes out of CHANGELOG.md and refuses an empty section' (($release -match 'CHANGELOG\.md') -and ($release -match 'no section for'))

# The code-scanning workflow: every push to main, every pull request and a weekly
# schedule, the web's and the agent's languages, a read and the one write a scan
# uploads with, no secret, and every action held to a major version.
$codeqlPath = Join-Path $pkgRoot '.github/workflows/codeql.yml'
$codeql = ''
if (Test-Path -LiteralPath $codeqlPath) { $codeql = [System.IO.File]::ReadAllText($codeqlPath) }
Assert-True 'codeql.yml runs on every push to main, every pull request and a weekly schedule' `
    (($codeql -match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+branches: \[main\]\s*\r?\n\s+pull_request:\s*\r?\n\s+schedule:\s*\r?\n\s+- cron: "[^"\r\n]+"\s*\r?\n') -and ($codeql -notmatch '(?m)^\s+(pull_request_target|workflow_run):'))
Assert-True 'codeql.yml scans the web and the agent: javascript-typescript and python' `
    (($codeql -match '(?m)^\s+- language: javascript-typescript\s*$') -and ($codeql -match '(?m)^\s+- language: python\s*$'))
Assert-True 'codeql.yml asks for no secret' (($codeql -ne '') -and ($codeql -notmatch 'secrets\.'))
$codeqlGrants = @([regex]::Matches($codeql, '(?m)^\s+([a-z-]+): (read|write)\s*$') | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value } | Sort-Object -Unique)
Assert-True 'codeql.yml grants contents: read and security-events: write, and nothing else' `
    (($codeql -match '(?m)^permissions:\s*\r?\n\s+contents: read\s*$') -and (($codeqlGrants -join ',') -eq 'contents:read,security-events:write')) ($codeqlGrants -join ',')
$codeqlUses = @([regex]::Matches($codeql, '(?m)^\s+(?:- )?uses: (\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'every action codeql.yml uses is pinned to a major version' `
    (($codeqlUses.Count -gt 0) -and (@($codeqlUses | Where-Object { $_ -notmatch '^(actions/[a-z-]+|github/codeql-action/[a-z-]+)@v\d+$' }).Count -eq 0)) ($codeqlUses -join ', ')
Assert-True 'codeql.yml runs the default queries: init names no queries or config file' (($codeql -ne '') -and ($codeql -notmatch '(?m)^\s+(queries|config-file|config):'))
Assert-True 'every job in codeql.yml has a timeout' (($codeql -ne '') -and ([regex]::Matches($codeql, '(?m)^\s+runs-on:').Count -eq [regex]::Matches($codeql, '(?m)^\s+timeout-minutes: \d+').Count))

$real = Read-P20ExpectedCounts -Path (Join-Path $pkgRoot 'docs/TESTING.md')
Assert-True 'docs/TESTING.md: the tkTestToolkit line is read' ($null -ne $real.cli -and $real.cli.Total -gt 0)
Assert-True 'docs/TESTING.md: the pytest line is read' ($null -ne $real.agent -and $real.agent.Passed -gt 0)
Assert-True 'docs/TESTING.md: the npm test line is read' ($null -ne $real.web -and $real.web.Total -gt 0 -and $real.web.Suites -gt 0)

# -- 2. The merge -----------------------------------------------------------------
Write-Host ""
Write-Host "-- The merge --" -ForegroundColor Cyan
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-43-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null
$savedPath = $env:PATH
$savedHook = [System.Environment]::GetEnvironmentVariable('TEAMS_WEBHOOK_TESTALL43')
try {
    $legacy = Join-Path $base 'legacy.json'
    [System.IO.File]::WriteAllText($legacy, '{ "machine": "M", "timestamp": "2026-10-01T09:00:00", "grandTotal": 7, "suites": { "Menu": { "result": "pass", "passed": 5, "total": 5, "seconds": 1.5, "description": "menu", "org": "" }, "Web": { "result": "fail", "passed": 1, "total": 2, "seconds": 2.0, "description": "web launcher", "org": "" } } }')
    $records = Get-P20TestHalfRecords -Summary (Read-P20TestSummary -Path $legacy)
    Assert-True 'a file from before the halves reads as the CLI half alone' (@($records.Keys).Count -eq 1 -and $records.Contains('cli'))
    Assert-True 'its CLI half is summed from the suites: 6/7, failed' ($records['cli']['passed'] -eq 6 -and $records['cli']['total'] -eq 7 -and $records['cli']['result'] -eq 'fail')

    Merge-P20TestSummary -Path $legacy -Halves @{ agent = [ordered]@{ half = 'agent'; result = 'pass'; passed = 3; failed = 0; skipped = 0; total = 3 } } `
        -Suites @{ pytest = [ordered]@{ half = 'agent'; result = 'pass'; passed = 3; total = 3 } }
    $after = Read-P20TestSummary -Path $legacy
    Assert-True 'writing the agent keeps the CLI''s entries as they were' ($after['suites'].Contains('Menu') -and $after['suites'].Contains('Web') -and $after['suites']['Web']['result'] -eq 'fail')
    Assert-True 'and the top-level totals' ($after['grandTotal'] -eq 7)
    Assert-True 'and adds the agent''s entry and half' ($after['suites']['pytest']['half'] -eq 'agent' -and $after['halves']['agent']['passed'] -eq 3)
    Merge-P20TestSummary -Path $legacy -Halves @{ cli = [ordered]@{ half = 'cli'; result = 'pass'; passed = 1; failed = 0; total = 1 } } `
        -Suites @{ Consts = [ordered]@{ half = 'cli'; result = 'pass'; passed = 1; total = 1 } }
    $after = Read-P20TestSummary -Path $legacy
    Assert-True 'a CLI write replaces the CLI suites, legacy ones included' ($after['suites'].Contains('Consts') -and -not $after['suites'].Contains('Menu') -and -not $after['suites'].Contains('Web'))
    Assert-True 'and leaves the agent''s' ($after['suites'].Contains('pytest') -and $after['halves'].Contains('agent'))
    $bytes = [System.IO.File]::ReadAllBytes($legacy)
    Assert-True 'written without a BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))

    # -- 3. The verb, stubbed -----------------------------------------------------
    Write-Host ""
    Write-Host "-- The verb, every half stubbed --" -ForegroundColor Cyan
    $pkg = Join-Path $base 'pkg'
    New-Item -ItemType Directory -Path (Join-Path $pkg 'Scripts'), (Join-Path $pkg 'Tests'), (Join-Path $pkg 'docs'), (Join-Path $pkg 'web') -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'Scripts/*.ps1') (Join-Path $pkg 'Scripts')
    Copy-Item (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $pkg
    [System.IO.File]::WriteAllText((Join-Path $pkg 'web/package.json'), '{ "name": "fake" }')
    $docsPath = Join-Path $pkg 'docs/TESTING.md'
    $docsSame = "# Testing`n`n``````powershell`ntkTestToolkit            # 9 suites, 10 assertions`n```````n`n``````bash`npython3 -m pytest Tests/     # 12 passed, 2 skipped, 5 subtests -- the agent`ncd web && npm test           # 5 build-contract checks, then 3 suites, 40 tests -- the shell`n```````n"
    [System.IO.File]::WriteAllText($docsPath, $docsSame)

    # The fake CLI runner: prints the runner's Total line, writes CLI suites the
    # way the runner does (through the shared merge), and says what it was given.
    $fakeRunner = @'
param([switch]$Fast)
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'Scripts/TestAll-Rules.ps1')
$scenario = ([System.IO.File]::ReadAllText((Join-Path $root 'Tests/cli-scenario.txt'))).Trim()
Write-Host "RUNNER-ARGS: Fast=$Fast"
$p = 10
$betaResult = 'pass'
if ($scenario -eq 'fail') { $p = 9; $betaResult = 'fail' }
$suites = [ordered]@{
    Alpha = [ordered]@{ half = 'cli'; result = 'pass'; passed = 6; total = 6; seconds = 1.5; description = 'alpha suite'; org = '' }
    Beta  = [ordered]@{ half = 'cli'; result = $betaResult; passed = ($p - 6); total = 4; seconds = 2.5; description = 'beta suite'; org = '' }
    Gamma = [ordered]@{ half = 'cli'; result = 'warn'; passed = 0; total = 0; seconds = 0.1; description = 'gamma suite'; org = '' }
}
Merge-P20TestSummary -Path (Get-P20TestSummaryPath -PackageRoot $root) -Halves @{ cli = [ordered]@{ half = 'cli'; result = $betaResult; passed = $p; failed = (10 - $p); skipped = 1; total = 10 } } -Suites $suites -Top @{ grandTotal = 10 }
Write-Host "  Total: $p/10 passed"
if ($p -ne 10) { exit 1 }
exit 0
'@
    [System.IO.File]::WriteAllText((Join-Path $pkg 'Tests/Test-Toolkit.ps1'), $fakeRunner)
    [System.IO.File]::WriteAllText((Join-Path $pkg 'Tests/cli-scenario.txt'), 'pass')

    $bin = Join-Path $base 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $enc = New-Object System.Text.UTF8Encoding($false)
    function Set-Stub {
        # A fake python or npm in $bin: it prints <name>-out.txt and exits with
        # <name>-exit.txt. python also answers the interpreter probe and the
        # import probes (httpx fails while bin/nohttpx exists); npm prints what
        # its environment says about the webhook and the run marker.
        param([string]$Name, [string]$Out, [int]$Exit = 0)
        [System.IO.File]::WriteAllText((Join-Path $bin "$Name-out.txt"), $Out.Replace("`r`n", "`n"), $enc)
        [System.IO.File]::WriteAllText((Join-Path $bin "$Name-exit.txt"), "$Exit", $enc)
        if ($isWin) {
            if ($Name -eq 'python') {
                $body = "@echo off`r`nif `"%1`"==`"-m`" goto run`r`necho %2 | findstr /c:`"import sys`" >nul && (echo 3.12.0& exit /b 0)`r`necho %2 | findstr /c:`"import httpx`" >nul && if exist `"%~dp0nohttpx`" exit /b 1`r`nexit /b 0`r`n:run`r`ntype `"%~dp0python-out.txt`"`r`nset /p CODE=<`"%~dp0python-exit.txt`"`r`nexit /b %CODE%`r`n"
            }
            else {
                $body = "@echo off`r`necho NPM-ARGS: %*`r`necho HOOK=[%TEAMS_WEBHOOK_TESTALL43%] MARKER=[%P20_TEST_RUN%]`r`necho OVERRIDES=[%P20_ACTIVE_SPACE%][%PROMPTS_ROOT%]`r`ntype `"%~dp0npm-out.txt`"`r`nset /p CODE=<`"%~dp0npm-exit.txt`"`r`nexit /b %CODE%`r`n"
            }
            [System.IO.File]::WriteAllText((Join-Path $bin "$Name.cmd"), $body, $enc)
        }
        else {
            if ($Name -eq 'python') {
                $body = "#!/bin/sh`nd=`"`${0%/*}`"`nif [ `"`$1`" = `"-m`" ]; then`n  while IFS= read -r l || [ -n `"`$l`" ]; do printf '%s\n' `"`$l`"; done < `"`$d/python-out.txt`"`n  read code < `"`$d/python-exit.txt`"; exit `$code`nfi`ncase `"`$2`" in`n  *'import sys'*) echo 3.12.0; exit 0;;`n  *'import httpx'*) if [ -f `"`$d/nohttpx`" ]; then exit 1; fi; exit 0;;`nesac`nexit 0`n"
            }
            else {
                $body = "#!/bin/sh`nd=`"`${0%/*}`"`necho `"NPM-ARGS: `$*`"`necho `"HOOK=[`$TEAMS_WEBHOOK_TESTALL43] MARKER=[`$P20_TEST_RUN]`"`necho `"OVERRIDES=[`$P20_ACTIVE_SPACE][`$PROMPTS_ROOT]`"`nwhile IFS= read -r l || [ -n `"`$l`" ]; do printf '%s\n' `"`$l`"; done < `"`$d/npm-out.txt`"`nread code < `"`$d/npm-exit.txt`"; exit `$code`n"
            }
            $stubPath = Join-Path $bin $Name
            [System.IO.File]::WriteAllText($stubPath, $body, $enc)
            & chmod +x $stubPath
        }
    }
    function Remove-Stub {
        param([string]$Name)
        Remove-Item (Join-Path $bin "$Name.cmd"), (Join-Path $bin $Name) -Force -ErrorAction SilentlyContinue
    }

    $pytestGreen = "collected 14 items`n`n====== 12 passed, 2 skipped, 5 subtests passed in 1.23s ======"
    $jestGreen = "PASS src/a.test.ts`nTest Suites: 3 passed, 3 total`nTests:       40 passed, 40 total`nTime:        2.1 s"
    Set-Stub 'python' $pytestGreen 0
    Set-Stub 'npm' $jestGreen 0
    New-Item -ItemType Directory -Path (Join-Path $pkg 'web/node_modules') -Force | Out-Null

    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $pathParts = @($bin)
    if ($isWin) {
        $pathParts += [System.Environment]::GetFolderPath('System')
        $pw = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pw) { $pathParts += (Split-Path $pw.Source -Parent) }
    }
    $stubPath = $pathParts -join [System.IO.Path]::PathSeparator
    $fakeHome = Join-Path $base 'home'
    New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
    $verb =Join-Path $pkg 'Scripts/Invoke-TestAll.ps1'
    $summaryFile = Get-P20TestSummaryPath -PackageRoot $pkg
    [System.Environment]::SetEnvironmentVariable('TEAMS_WEBHOOK_TESTALL43', 'not-a-url')

    function Invoke-TestVerb {
        param([string[]]$Arguments = @(), [string]$PathValue = $stubPath, [string]$HostExe = $hostExe)
        $env:PATH = $PathValue
        # The home folder is the scratch one: a real ~/.venv-toolkit on the machine
        # running this suite must not answer for the stub PATH.
        $savedHome = $env:HOME; $savedProfile = $env:USERPROFILE
        $env:HOME = $fakeHome; $env:USERPROFILE = $fakeHome
        try {
            $global:LASTEXITCODE = 0
            $out = & $HostExe -NoProfile -ExecutionPolicy Bypass -File $verb @Arguments 2>&1
            $code = $LASTEXITCODE
        }
        finally {
            $env:PATH = $savedPath
            $env:HOME = $savedHome; $env:USERPROFILE = $savedProfile
        }
        return @{ Text = (@($out | ForEach-Object { [string]$_ }) -join "`n"); Exit = $code }
    }
    function Get-Line {
        param([string]$Text, [string]$Half)
        return (@($Text -split "`n" | Where-Object { $_ -match ('^\s+' + $Half + '\s+(PASS|FAIL|SKIP)\b') }) | Select-Object -First 1)
    }

    # All three green -- from a shell that holds both per-shell overrides (the
    # names come from the contract, which the verb reads too).
    $overrideNames = @($consts.env.activeSpace, $consts.env.promptsRoot)
    $heldOverrides = @{}
    foreach ($n in $overrideNames) { $heldOverrides[$n] = [System.Environment]::GetEnvironmentVariable($n) }
    [System.Environment]::SetEnvironmentVariable($overrideNames[0], 'nonexistent-space')
    [System.Environment]::SetEnvironmentVariable($overrideNames[1], '/nonexistent')
    try { $r = Invoke-TestVerb }
    finally {
        foreach ($n in $overrideNames) {
            if ($null -eq $heldOverrides[$n]) { Remove-Item "Env:\$n" -ErrorAction SilentlyContinue }
            else { [System.Environment]::SetEnvironmentVariable($n, [string]$heldOverrides[$n]) }
        }
    }
    Assert-True 'the web child saw neither the active-Space nor the prompts-root override a shell held' ($r.Text -match 'OVERRIDES=\[\]\[\]') (@($r.Text -split "`n" | Where-Object { $_ -match 'OVERRIDES=' }) -join ' ')
    $testAllRunSource = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Scripts/Invoke-TestAll.ps1'))
    Assert-True 'Invoke-TestAll hides the overrides around every half and restores them in a finally' ($testAllRunSource -match '(?s)Hide-P20RunOverrides.*foreach \(\$h in \$halves\).*finally \{ Restore-P20RunOverrides')
    Assert-True 'all green: exit 0' ($r.Exit -eq 0) "exit $($r.Exit)`n$($r.Text)"
    $ia = $r.Text.IndexOf('the agent half'); $ic = $r.Text.IndexOf('the cli half'); $iw = $r.Text.IndexOf('the web half')
    Assert-True 'the halves run in order: agent, cli, web' ($ia -ge 0 -and $ia -lt $ic -and $ic -lt $iw) "$ia $ic $iw"
    Assert-True 'the agent line: 12 passed, 2 skipped' ((Get-Line $r.Text 'agent') -match 'PASS\s+12 passed, 0 failed, 2 skipped') (Get-Line $r.Text 'agent')
    Assert-True 'the cli line: 10 passed, the warned suite its skip' ((Get-Line $r.Text 'cli') -match 'PASS\s+10 passed, 0 failed, 1 skipped') (Get-Line $r.Text 'cli')
    Assert-True 'the web line: 40 passed in 3 suites' ((Get-Line $r.Text 'web') -match 'PASS\s+40 passed, 0 failed, 0 skipped \(3 suites\)') (Get-Line $r.Text 'web')
    Assert-True 'each half carries its elapsed time' ((Get-Line $r.Text 'agent') -match '\d+\.\ds\s*$')
    Assert-True 'one verdict: PASSED' ($r.Text -match 'Verdict: PASSED -- agent, cli, web\.')
    Assert-True 'expected vs actual is printed per half' ($r.Text -match 'expected 12 passed, 2 skipped; actual 12 passed, 2 skipped' -and $r.Text -match 'expected 10 assertions; actual 10 assertions' -and $r.Text -match 'expected 3 suites, 40 tests; actual 3 suites, 40 tests')
    Assert-True 'and no note when they agree' ($r.Text -notmatch '\(differs\)' -and $r.Text -notmatch 'Note: ')
    Assert-True 'npm test ran as npm test' ($r.Text -match 'NPM-ARGS: test')
    Assert-True 'the web child had no webhook variable and the run marker set' ($r.Text -match 'HOOK=\[\] MARKER=\[1\]') (@($r.Text -split "`n" | Where-Object { $_ -match 'HOOK=' }) -join ' ')
    Assert-True 'the CLI runner was not given -Fast' ($r.Text -match 'RUNNER-ARGS: Fast=False')
    $s = Read-P20TestSummary -Path $summaryFile
    Assert-True 'the summary file has the three halves' ($null -ne $s -and (@($s['halves'].Keys) -join ',') -eq 'agent,cli,web') "$(@($s['halves'].Keys) -join ',')"
    Assert-True 'each half its counts' ($s['halves']['agent']['passed'] -eq 12 -and $s['halves']['cli']['total'] -eq 10 -and $s['halves']['web']['passed'] -eq 40 -and $s['halves']['web']['suites'] -eq 3)
    Assert-True 'the agent and the web each a suite entry with its half' ($s['suites']['pytest']['half'] -eq 'agent' -and $s['suites']['jest']['half'] -eq 'web' -and $s['suites']['jest']['total'] -eq 40)
    $alpha = $s['suites']['Alpha']
    Assert-True 'the CLI entries are exactly as the runner wrote them' ((@($alpha.Keys) -join ',') -eq 'half,result,passed,total,seconds,description,org' -and $alpha['seconds'] -eq 1.5 -and $alpha['description'] -eq 'alpha suite') "$(@($alpha.Keys) -join ',')"
    Assert-True 'and the runner''s top-level totals stay' ($s['grandTotal'] -eq 10)

    # Expected vs actual that differ: information, not the verdict.
    [System.IO.File]::WriteAllText($docsPath, $docsSame.Replace('12 passed, 2 skipped', '13 passed, 2 skipped'))
    $r = Invoke-TestVerb @('-Half', 'agent')
    Assert-True 'a count that differs from the doc is still exit 0' ($r.Exit -eq 0) "exit $($r.Exit)"
    Assert-True 'and is marked, with the one-line note' ($r.Text -match 'expected 13 passed, 2 skipped; actual 12 passed, 2 skipped\s+\(differs\)' -and $r.Text -match 'Note: agent differs from docs/TESTING\.md')
    [System.IO.File]::WriteAllText($docsPath, $docsSame)

    # -Half: one half, and the other halves' record kept.
    Set-Stub 'python' "===== 20 passed in 2.0s =====" 0
    $r = Invoke-TestVerb @('-Half', 'agent')
    Assert-True '-Half agent runs the agent alone' ($r.Exit -eq 0 -and $r.Text -match 'the agent half' -and $r.Text -notmatch 'the cli half' -and $r.Text -notmatch 'the web half')
    $s = Read-P20TestSummary -Path $summaryFile
    Assert-True '-Half agent rewrites the agent''s record only' ($s['halves']['agent']['passed'] -eq 20 -and $s['suites']['pytest']['passed'] -eq 20)
    Assert-True 'the cli and web records are kept' ($s['halves']['cli']['total'] -eq 10 -and $s['halves']['web']['passed'] -eq 40 -and $s['suites'].Contains('jest') -and $s['suites'].Contains('Alpha'))
    Set-Stub 'python' $pytestGreen 0

    # -Fast reaches the CLI runner, and its total is not compared.
    $r = Invoke-TestVerb @('-Half', 'cli', '-Fast')
    Assert-True '-Fast is passed to the CLI runner' ($r.Text -match 'RUNNER-ARGS: Fast=True') (@($r.Text -split "`n" | Where-Object { $_ -match 'RUNNER-ARGS' }) -join ' ')
    Assert-True 'and the comparison says a partial run is not compared' ($r.Text -match '-Fast: a partial run, not compared')

    # A half that fails: exit 2, after the summary, stated once.
    Set-Stub 'python' "===== 1 failed, 11 passed in 1.0s =====" 1
    $r = Invoke-TestVerb
    Assert-True 'a failed half: exit 2' ($r.Exit -eq 2) "exit $($r.Exit)"
    Assert-True 'its line says FAIL with the counts' ((Get-Line $r.Text 'agent') -match 'FAIL\s+11 passed, 1 failed') (Get-Line $r.Text 'agent')
    Assert-True 'the other halves still ran' ((Get-Line $r.Text 'cli') -match 'PASS' -and (Get-Line $r.Text 'web') -match 'PASS')
    Assert-True 'the verdict names it' ($r.Text -match 'Verdict: FAILED -- agent\.')
    Assert-True 'and one Error line states it, after the summary' (@($r.Text -split "`n" | Where-Object { $_ -match '^Error: ' }).Count -eq 1 -and $r.Text.IndexOf('Error: ') -gt $r.Text.IndexOf('Verdict:'))
    $s = Read-P20TestSummary -Path $summaryFile
    Assert-True 'the summary file records the failure' ($s['halves']['agent']['result'] -eq 'fail' -and $s['suites']['pytest']['result'] -eq 'fail')
    Set-Stub 'python' $pytestGreen 0

    # The CLI runner red.
    [System.IO.File]::WriteAllText((Join-Path $pkg 'Tests/cli-scenario.txt'), 'fail')
    $r = Invoke-TestVerb @('-Half', 'cli')
    Assert-True 'a red CLI runner: exit 2, 9 passed, 1 failed' ($r.Exit -eq 2 -and (Get-Line $r.Text 'cli') -match 'FAIL\s+9 passed, 1 failed') (Get-Line $r.Text 'cli')
    [System.IO.File]::WriteAllText((Join-Path $pkg 'Tests/cli-scenario.txt'), 'pass')

    # npm test that stops before jest reports.
    Set-Stub 'npm' "> node tests/viteconfig.mjs`nviteconfig: 1 failed" 1
    $r = Invoke-TestVerb @('-Half', 'web')
    Assert-True 'no jest totals: the web half fails, saying there was no summary line' ($r.Exit -eq 2 -and (Get-Line $r.Text 'web') -match 'FAIL.*no summary line') (Get-Line $r.Text 'web')
    Set-Stub 'npm' $jestGreen 0

    # Stated skips.
    New-Item -ItemType File -Path (Join-Path $bin 'nohttpx') -Force | Out-Null
    $r = Invoke-TestVerb
    Remove-Item (Join-Path $bin 'nohttpx') -Force
    Assert-True 'no httpx: the agent half is skipped, saying so' ((Get-Line $r.Text 'agent') -match 'SKIP\s+skipped: httpx is not installed') (Get-Line $r.Text 'agent')
    Assert-True 'and the hint is the requirements file' ($r.Text -match 'pip install -r agent/requirements-dev\.txt')
    Assert-True 'the run still passes on what ran: exit 0' ($r.Exit -eq 0) "exit $($r.Exit)"
    Assert-True 'but the verdict names the skip, not a pass' ($r.Text -match 'Verdict: PASSED -- cli, web\. SKIPPED \(not passed\): agent -- httpx')
    $s = Read-P20TestSummary -Path $summaryFile
    Assert-True 'the summary file records the skip and its reason' ($s['halves']['agent']['result'] -eq 'skip' -and $s['halves']['agent']['reason'] -match 'httpx' -and $s['suites']['pytest']['result'] -eq 'warn')

    Remove-Stub 'python'
    $r = Invoke-TestVerb @('-Half', 'agent')
    Assert-True 'no Python: a stated skip naming what was tried' ((Get-Line $r.Text 'agent') -match 'SKIP\s+skipped: no Python 3 on the PATH \(tried ') (Get-Line $r.Text 'agent')
    Assert-True 'nothing ran: exit 2' ($r.Exit -eq 2) "exit $($r.Exit)"
    Assert-True 'and the verdict says NOTHING RAN, stated once' ($r.Text -match 'Verdict: NOTHING RAN' -and @($r.Text -split "`n" | Where-Object { $_ -match '^Error: No half ran' }).Count -eq 1)
    Set-Stub 'python' $pytestGreen 0

    # The test venv answers before the PATH. The PATH's python lacks httpx; the home
    # folder's .venv-toolkit has everything and prints its own count.
    $r = Invoke-TestVerb @('-Half', 'agent')
    Assert-True 'no venv: the PATH python runs, and the line names it' ((Get-Line $r.Text 'agent') -match 'PASS.*\[via python \(PATH\)\]') (Get-Line $r.Text 'agent')
    if ($isWin) {
        Write-Host "  SKIP  the venv cases stub a POSIX python; the Windows layout (Scripts/python.exe) needs a real one" -ForegroundColor DarkYellow
    }
    else {
        $venvBin = Join-Path $fakeHome '.venv-toolkit/bin'
        New-Item -ItemType Directory -Path $venvBin -Force | Out-Null
        $venvBody = "#!/bin/sh`nif [ `"`$1`" = `"-m`" ]; then echo '===== 7 passed in 1.0s ====='; exit 0; fi`nexit 0`n"
        [System.IO.File]::WriteAllText((Join-Path $venvBin 'python'), $venvBody, $enc)
        & chmod +x (Join-Path $venvBin 'python')
        New-Item -ItemType File -Path (Join-Path $bin 'nohttpx') -Force | Out-Null
        $r = Invoke-TestVerb @('-Half', 'agent')
        Remove-Item (Join-Path $bin 'nohttpx') -Force
        Assert-True 'a venv with pytest is used though the PATH python lacks httpx' ((Get-Line $r.Text 'agent') -match 'PASS\s+7 passed') (Get-Line $r.Text 'agent')
        Assert-True 'and the line names the venv, not the machine path' ((Get-Line $r.Text 'agent') -match [regex]::Escape('[via ~/.venv-toolkit/bin/python]') -and $r.Text -notmatch [regex]::Escape($fakeHome)) (Get-Line $r.Text 'agent')
        $s = Read-P20TestSummary -Path $summaryFile
        Assert-True 'and the summary file records the python' ($s['halves']['agent']['python'] -eq '~/.venv-toolkit/bin/python') "$($s['halves']['agent']['python'])"
        Remove-Item (Join-Path $fakeHome '.venv-toolkit') -Recurse -Force
    }

    Remove-Stub 'npm'
    $r = Invoke-TestVerb @('-Half', 'web')
    Assert-True 'no npm: a stated skip' ((Get-Line $r.Text 'web') -match 'SKIP\s+skipped: npm is not on the PATH') (Get-Line $r.Text 'web')
    Set-Stub 'npm' $jestGreen 0

    Remove-Item (Join-Path $pkg 'web/node_modules') -Recurse -Force
    $r = Invoke-TestVerb @('-Half', 'web')
    Assert-True 'no node_modules: a stated skip naming npm ci' ((Get-Line $r.Text 'web') -match 'SKIP\s+skipped: web/node_modules is missing -- run npm ci in web/') (Get-Line $r.Text 'web')
    New-Item -ItemType Directory -Path (Join-Path $pkg 'web/node_modules') -Force | Out-Null

    # No pwsh: only Windows PowerShell can be the host that lacks it.
    $winPs = $null
    if ($isWin) { $winPs = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($winPs) {
        $noPwshPath = (@($bin, [System.Environment]::GetFolderPath('System')) -join [System.IO.Path]::PathSeparator)
        $r = Invoke-TestVerb @('-Half', 'cli') -PathValue $noPwshPath -HostExe $winPs.Source
        Assert-True 'no pwsh (Windows PowerShell host): the CLI half is a stated skip' ((Get-Line $r.Text 'cli') -match 'SKIP\s+skipped: no pwsh on the PATH') "$(Get-Line $r.Text 'cli')"
        $s = Read-P20TestSummary -Path $summaryFile
        Assert-True 'and the CLI suites the last run wrote are kept' ($s['suites'].Contains('Alpha') -and $s['halves']['cli']['result'] -eq 'skip')
    }
    else {
        Write-Host "  SKIP  no pwsh -- needs Windows PowerShell as the host; not on this machine" -ForegroundColor DarkYellow
    }

    # -Help.
    $r = Invoke-TestVerb @('-Help')
    Assert-True '-Help renders the usage from config' ($r.Exit -eq 0 -and $r.Text -match [regex]::Escape('Test [-Half cli|agent|web] [-Fast] [-Help]')) $r.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    $env:PATH = $savedPath
    [System.Environment]::SetEnvironmentVariable('TEAMS_WEBHOOK_TESTALL43', $savedHook)
    Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 3b. A WARN suite is logged ---------------------------------------------
Write-Host ""
Write-Host "-- A suite that ends WARN reaches the log and the summary --" -ForegroundColor Cyan
$warnBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-241-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $warnBase -Force | Out-Null
try {
    # A scratch copy of the module, so the log the writer appends to is the copy's
    # (it sits beside utilities.psm1) and never this checkout's.
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $warnBase
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $warnBase 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $warnBase 'Config') -Recurse }
    $warnHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $warnModule = $warnBase -replace '\\', '/'
    $warnCmd = "`$ErrorActionPreference = 'Continue'; " +
        "Import-Module '$warnModule/utilities.psm1' -Force 3>`$null 6>`$null; " +
        "Write-P20TestResult -Suite 'Zero' -Result 'warn' -Passed 0 -Total 0 -Detail 'ok'; " +
        "Write-P20TestResult -Suite 'Green' -Result 'pass' -Passed 3 -Total 3; " +
        "try { Write-P20TestResult -Suite 'Bad' -Result 'maybe' -Passed 0 -Total 0 } catch { Write-Output 'REFUSED-BAD-WORD' }"
    $savedQuiet = $env:TOOLKIT_QUIET_STARTUP
    $env:TOOLKIT_QUIET_STARTUP = '1'
    try { $warnOut = (& $warnHost -NoProfile -ExecutionPolicy Bypass -Command $warnCmd 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally { $env:TOOLKIT_QUIET_STARTUP = $savedQuiet }
    $warnLogs = @(Get-ChildItem -Path $warnBase -Filter 'test-results.*.log')
    Assert-True 'the writer wrote a log beside the scratch module' ($warnLogs.Count -eq 1) $warnOut
    $warnLines = @()
    if ($warnLogs.Count -eq 1) { $warnLines = @([System.IO.File]::ReadAllLines($warnLogs[0].FullName)) }
    $zeroLine = @($warnLines | Where-Object { $_ -match "`tZero`t" }) | Select-Object -First 1
    $zeroCols = @()
    if ($zeroLine) { $zeroCols = @($zeroLine -split "`t") }
    Assert-True 'a warn suite is a line in the log, as the word warn, in the same seven columns' ($zeroCols.Count -eq 7 -and $zeroCols[2] -eq 'warn' -and $zeroCols[3] -eq '0' -and $zeroCols[4] -eq '0') "$zeroLine"
    Assert-True 'the writer did not throw on warn, and nothing said Failed to log' ($warnOut -notmatch 'Cannot validate argument' -and $warnOut -notmatch 'Failed to log' -and $warnOut -notmatch 'Failed to write') $warnOut
    Assert-True 'a pass line is unchanged' (@($warnLines | Where-Object { $_ -match "`tGreen`tpass`t3`t3`t" }).Count -eq 1)
    Assert-True 'a word that is none of the three is still refused, and not logged' ($warnOut -match 'REFUSED-BAD-WORD' -and @($warnLines | Where-Object { $_ -match "`tBad`t" }).Count -eq 0)

    # The summary entry the runner writes for a WARN suite survives the merge as
    # its own word, and the CLI half counts it as neither passed nor failed.
    $warnSummary = Join-Path $warnBase 'summary.json'
    $warnSuites = [ordered]@{
        Zero  = [ordered]@{ half = 'cli'; result = 'warn'; passed = 0; total = 0; seconds = 0.1; description = 'zero'; org = '' }
        Green = [ordered]@{ half = 'cli'; result = 'pass'; passed = 3; total = 3; seconds = 0.1; description = 'green'; org = '' }
    }
    Merge-P20TestSummary -Path $warnSummary -Halves @{ cli = [ordered]@{ half = 'cli'; result = 'pass'; passed = 3; failed = 0; skipped = 1; total = 3 } } -Suites $warnSuites -Top @{ grandTotal = 3 }
    $ws = Read-P20TestSummary -Path $warnSummary
    Assert-True 'the summary entry says warn' ($ws['suites']['Zero']['result'] -eq 'warn' -and $ws['suites']['Green']['result'] -eq 'pass')
    Assert-True 'and the CLI half counts it as skipped, not failed' ($ws['halves']['cli']['failed'] -eq 0 -and $ws['halves']['cli']['skipped'] -eq 1)
    $lw = Get-P20TestHalfRecords -Summary ([ordered]@{ suites = $warnSuites; timestamp = '2026-10-06T09:00:00' })
    Assert-True 'a file with no halves block reads the warn as a skip, not a pass or a fail' ($lw['cli']['result'] -eq 'pass' -and $lw['cli']['skipped'] -eq 1 -and $lw['cli']['failed'] -eq 0) "$($lw['cli']['result']) $($lw['cli']['skipped'])"

}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $warnBase -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 3b2. One log entry is one line -------------------------------------------
Write-Host ""
Write-Host "-- A tab or a line break in a logged value cannot forge an entry or shift a column --" -ForegroundColor Cyan
$lineBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-lines-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $lineBase -Force | Out-Null
try {
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $lineBase
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $lineBase 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $lineBase 'Config') -Recurse }
    $lineHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $lineModule = $lineBase -replace '\\', '/'
    # A script file, not -Command: Windows PowerShell 5.1 drops the double quotes
    # from a native argument, and the values here are the point of the test.
    $probe = Join-Path $lineBase 'probe-write.ps1'
    $probeText = @(
        "`$ErrorActionPreference = 'Continue'",
        "Import-Module '$lineModule/utilities.psm1' -Force 3>`$null 6>`$null",
        "`$tab = [string][char]9; `$lf = [string][char]10; `$cr = [string][char]13",
        "`$forged = 'failed' + `$lf + '2030-01-01T00:00:00' + `$tab + 'ERR' + `$tab + 'HOST' + `$tab + 'forged' + `$tab + 'not a real entry'",
        "Write-ToolkitLog -Type WARN -Source ('a' + `$tab + 'b') -Detail `$forged",
        "Write-ToolkitLog -Type INFO -Source plain -Detail ('one' + `$cr + `$lf + 'two')",
        "Write-P20TestResult -Suite 'Lines' -Result 'fail' -Passed 1 -Total 2 -Detail ('first' + `$lf + 'second' + `$tab + 'third') -Org 'acme'"
    )
    [System.IO.File]::WriteAllText($probe, ($probeText -join "`r`n"))
    $savedQuiet = $env:TOOLKIT_QUIET_STARTUP
    $savedLogDir = $env:P20_USAGE_LOG_DIR
    $env:TOOLKIT_QUIET_STARTUP = '1'
    $env:P20_USAGE_LOG_DIR = $lineBase
    try { $lineOut = (& $lineHost -NoProfile -ExecutionPolicy Bypass -File $probe 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally {
        $env:TOOLKIT_QUIET_STARTUP = $savedQuiet
        $env:P20_USAGE_LOG_DIR = $savedLogDir
    }
    $usageLogs = @(Get-ChildItem -Path $lineBase -Filter 'usage.*.log')
    $usageLines = @()
    if ($usageLogs.Count -eq 1) { $usageLines = @([System.IO.File]::ReadAllLines($usageLogs[0].FullName) | Where-Object { $_ -notmatch "`ttkEnv`t" }) }
    Assert-True 'two Write-ToolkitLog calls are two lines, however many line breaks the values carried' ($usageLines.Count -eq 2) "$($usageLines.Count) lines: $lineOut"
    $warnCols = @()
    if ($usageLines.Count -ge 1) { $warnCols = @($usageLines[0] -split "`t") }
    Assert-True 'a value with a forged line and tabs is still five columns' ($warnCols.Count -eq 5) ($usageLines -join ' | ')
    Assert-True 'a tab in the source is a space, not a new column' ($warnCols.Count -eq 5 -and $warnCols[3] -eq 'a b')
    Assert-True 'the whole detail is kept, each tab and line break as one space' ($warnCols.Count -eq 5 -and $warnCols[4] -eq 'failed 2030-01-01T00:00:00 ERR HOST forged not a real entry') ($usageLines -join ' | ')
    $crCols = @()
    if ($usageLines.Count -ge 2) { $crCols = @($usageLines[1] -split "`t") }
    Assert-True 'CR and LF are one space each' ($crCols.Count -eq 5 -and $crCols[4] -eq 'one  two') ($usageLines -join ' | ')

    # The reader the CLI ships: the Log verb shows the entry whole, once.
    $logReadCmd = "`$ErrorActionPreference = 'Continue'; " +
        "Import-Module '$lineModule/utilities.psm1' -Force 3>`$null 6>`$null; " +
        "Get-P20ToolkitLog -Count 50 6>&1"
    $env:TOOLKIT_QUIET_STARTUP = '1'
    $env:P20_USAGE_LOG_DIR = $lineBase
    try { $logReadOut = (& $lineHost -NoProfile -ExecutionPolicy Bypass -Command $logReadCmd 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally {
        $env:TOOLKIT_QUIET_STARTUP = $savedQuiet
        $env:P20_USAGE_LOG_DIR = $savedLogDir
    }
    Assert-True 'the Log verb shows the forged-looking detail as part of one entry' ($logReadOut -match 'failed 2030-01-01T00:00:00 ERR HOST forged not a real entry') $logReadOut
    Assert-True 'and shows no entry of its own with the forged source' (@($logReadOut -split "`n" | Where-Object { $_ -match '\sforged\s+not a real entry' -and $_ -notmatch 'failed' }).Count -eq 0) $logReadOut

    $resultLogs = @(Get-ChildItem -Path $lineBase -Filter 'test-results.*.log')
    $resultLines = @()
    if ($resultLogs.Count -eq 1) { $resultLines = @([System.IO.File]::ReadAllLines($resultLogs[0].FullName)) }
    $resultCols = @()
    if ($resultLines.Count -ge 1) { $resultCols = @($resultLines[0] -split "`t") }
    Assert-True 'Write-P20TestResult strips line breaks as well as tabs: one line, seven columns' ($resultLines.Count -eq 1 -and $resultCols.Count -eq 7) "$($resultLines.Count) lines: $($resultLines -join ' | ')"
    Assert-True 'its detail is kept whole and the org is still the last column' ($resultCols.Count -eq 7 -and $resultCols[5] -eq 'first second third' -and $resultCols[6] -eq 'acme') ($resultLines -join ' | ')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $lineBase -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 3c. A MISSING suite is logged and fails the run -----------------------
Write-Host ""
Write-Host "-- A suite whose file is not found reaches the log and fails the run --" -ForegroundColor Cyan
$missBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-247-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $missBase 'Tests') -Force | Out-Null
try {
    # A scratch package with the real runner and registry and NO Test-Consts.ps1: the
    # registry names a suite whose file is not there. Log and summary are the copy's.
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $missBase
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $missBase 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $missBase 'Config') -Recurse }
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1') (Join-Path $missBase 'Tests')
    $missHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $missOut = (& $missHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $missBase 'Tests/Test-Toolkit.ps1') -Consts 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $missExit = $LASTEXITCODE
    Assert-True 'the console says the file was not found' ($missOut -match 'file not found: Test-Consts\.ps1') $missOut
    Assert-True 'the runner exits non-zero: a missing suite fails the run' ($missExit -ne 0) "exit $missExit"
    $missLogs = @(Get-ChildItem -Path $missBase -Filter 'test-results.*.log')
    $missLines = @()
    if ($missLogs.Count -eq 1) { $missLines = @([System.IO.File]::ReadAllLines($missLogs[0].FullName)) }
    $missLine = @($missLines | Where-Object { $_ -match "`tConsts`t" }) | Select-Object -First 1
    $missCols = @()
    if ($missLine) { $missCols = @($missLine -split "`t") }
    Assert-True 'the missing suite is a line in the log: fail, 0 of 1, the same seven columns, with why' ($missCols.Count -eq 7 -and $missCols[2] -eq 'fail' -and $missCols[3] -eq '0' -and $missCols[4] -eq '1' -and $missCols[5] -match 'file not found') "$missLine"
    $missSummaries = @(Get-ChildItem -Path $missBase -Filter 'test-summary.*.json')
    $ms = $null
    if ($missSummaries.Count -eq 1) { $ms = Read-P20TestSummary -Path $missSummaries[0].FullName }
    Assert-True 'the summary entry says fail, with a real seconds value and the suite counted' ($null -ne $ms -and $ms['suites']['Consts']['result'] -eq 'fail' -and $null -ne $ms['suites']['Consts']['seconds'] -and $ms['suites']['Consts']['total'] -eq 1)
    Assert-True 'and the CLI half is a fail with one failed, not a pass' ($null -ne $ms -and $ms['halves']['cli']['result'] -eq 'fail' -and $ms['halves']['cli']['failed'] -eq 1)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $missBase -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 3d. The bridge's quiet marker does not reach the suites ----------------
Write-Host ""
Write-Host "-- A run started with TOOLKIT_QUIET_STARTUP set: a suite's bare refusal exits 2, and the variable comes back --" -ForegroundColor Cyan
$quietBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-edk6-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $quietBase 'Tests') -Force | Out-Null
try {
    # The web UI's Test Health card runs Test through the bridge, which sets the marker for
    # that child; the runner and every pwsh a suite starts inherited it, and the refusal
    # guard then threw instead of exiting 2. A scratch package with the REAL runner and
    # registry and a one-file suite (registered as Consts) that types a bare refusing verb
    # from the real module in a fresh shell, the way the suites do.
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $quietBase
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $quietBase 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $quietBase 'Config') -Recurse }
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1') (Join-Path $quietBase 'Tests')
    $quietProbe = Join-Path $quietBase 'probe.txt'
    $quietPkg = $pkgRoot -replace "'", "''"
    $quietProbeQ = $quietProbe -replace "'", "''"
    $suiteText = @"
`$sawQuiet = [string]`$env:TOOLKIT_QUIET_STARTUP
`$child = 'Import-Module ''$quietPkg/Prompt20Toolkit/Prompt20Toolkit.psd1'' -Force 3>`$null 6>`$null; tkBillable *>`$null; exit `$LASTEXITCODE'
`$env:PSModulePath = '$quietPkg'
`$h = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& `$h -NoProfile -NonInteractive -Command `$child *>`$null
[System.IO.File]::WriteAllText('$quietProbeQ', "QUIET=[`$sawQuiet] EXIT=`$LASTEXITCODE")
exit 0
"@
    [System.IO.File]::WriteAllText((Join-Path $quietBase 'Tests/Test-Consts.ps1'), $suiteText)
    $quietHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $savedQuiet = $env:TOOLKIT_QUIET_STARTUP
    $env:TOOLKIT_QUIET_STARTUP = '1'
    try {
        $null = & $quietHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $quietBase 'Tests/Test-Toolkit.ps1') -Consts 2>&1
        $quietAfter = $env:TOOLKIT_QUIET_STARTUP
    }
    finally { $env:TOOLKIT_QUIET_STARTUP = $savedQuiet }
    $probeText = ''
    if (Test-Path $quietProbe) { $probeText = [System.IO.File]::ReadAllText($quietProbe) }
    Assert-True 'the suite ran and wrote its probe' ($probeText -ne '') 'no probe file'
    Assert-True 'the suite''s environment does not carry the bridge''s marker' ($probeText -match 'QUIET=\[\]') $probeText
    Assert-True 'a bare refusing verb typed in a fresh shell under that run exits 2, not 1' ($probeText -match 'EXIT=2$') $probeText
    Assert-True 'the marker is still set in the shell that started the run' ($quietAfter -eq '1') "[$quietAfter]"
    $testAllSource = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Scripts/Invoke-TestAll.ps1'))
    Assert-True 'Invoke-TestAll removes the marker around the CLI half and puts it back' ($testAllSource -match '(?s)savedQuiet.*Invoke-P20HalfProcess -Exe \$pwshExe.*finally.*SetEnvironmentVariable\(.TOOLKIT_QUIET_STARTUP., \$savedQuiet\)')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $quietBase -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 3e. The per-shell overrides do not reach a suite, and come back ---------
Write-Host ""
Write-Host "-- A run started with P20_ACTIVE_SPACE and PROMPTS_ROOT set: no suite sees them, and the shell has them after --" -ForegroundColor Cyan
$ovBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-ovr-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $ovBase 'Tests') -Force | Out-Null
try {
    # The REAL CLI runner and registry in a scratch package, with a one-file suite
    # (registered as Consts) that reports what its environment holds. The runner is
    # called in-process from a child shell that set both overrides, so the line the
    # child prints last is the caller's own shell after the run.
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $ovBase
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $ovBase 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $ovBase 'Config') -Recurse }
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1') (Join-Path $ovBase 'Tests')
    $ovProbe = Join-Path $ovBase 'probe.txt'
    $ovSpaceName = $consts.env.activeSpace
    $ovRootName = $consts.env.promptsRoot
    $ovSuite = "[System.IO.File]::WriteAllText('$($ovProbe -replace "'", "''")', ""SPACE=[`$env:$ovSpaceName] ROOT=[`$env:$ovRootName]"")`nexit 0`n"
    [System.IO.File]::WriteAllText((Join-Path $ovBase 'Tests/Test-Consts.ps1'), $ovSuite)
    $ovHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $ovRunner = (Join-Path $ovBase 'Tests/Test-Toolkit.ps1') -replace "'", "''"
    $ovCommand = "`$env:$ovSpaceName = 'nonexistent-space'; `$env:$ovRootName = '/nonexistent'; & '$ovRunner' -Consts *>`$null; 'AFTER=[' + `$env:$ovSpaceName + '][' + `$env:$ovRootName + ']'"
    $ovOut = (& $ovHost -NoProfile -ExecutionPolicy Bypass -Command $ovCommand 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $ovSeen = ''
    if (Test-Path $ovProbe) { $ovSeen = [System.IO.File]::ReadAllText($ovProbe) }
    Assert-True 'the suite ran and wrote its probe' ($ovSeen -ne '') 'no probe file'
    Assert-True 'the suite saw no active-Space override' ($ovSeen -match 'SPACE=\[\]') $ovSeen
    Assert-True 'the suite saw no prompts-root override from the shell' ($ovSeen -notmatch [regex]::Escape('/nonexistent')) $ovSeen
    Assert-True 'the shell that started the run has both back afterwards' ($ovOut -match [regex]::Escape('AFTER=[nonexistent-space][/nonexistent]')) $ovOut
    # The helper on its own: hide, then restore; a name that held nothing stays unset.
    . (Join-Path $pkgRoot 'Scripts/Hide-RunOverrides.ps1')
    $ovHeld = @{}
    foreach ($n in @($ovSpaceName, $ovRootName)) { $ovHeld[$n] = [System.Environment]::GetEnvironmentVariable($n) }
    # (read before the cases below set anything, so Restore puts the suite's own back)
    try {
        [System.Environment]::SetEnvironmentVariable($ovSpaceName, 'x')
        Remove-Item "Env:\$ovRootName" -ErrorAction SilentlyContinue
        $ovSaved = Hide-P20RunOverrides
        Assert-True 'Hide-P20RunOverrides leaves neither variable set' (-not [System.Environment]::GetEnvironmentVariable($ovSpaceName) -and -not [System.Environment]::GetEnvironmentVariable($ovRootName))
        Restore-P20RunOverrides $ovSaved
        Assert-True 'Restore-P20RunOverrides puts back the one that was set and leaves the other unset' (([System.Environment]::GetEnvironmentVariable($ovSpaceName) -eq 'x') -and ($null -eq [System.Environment]::GetEnvironmentVariable($ovRootName)))
    }
    finally { Restore-P20RunOverrides $ovHeld }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $ovBase -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 4. The wiring -----------------------------------------------------------------
Write-Host ""
Write-Host "-- The wiring --" -ForegroundColor Cyan
$runnerSource = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'Test-Toolkit.ps1'))
Assert-True 'the CLI runner writes through the shared merge' ($runnerSource -match 'Merge-P20TestSummary\s+-Path\s+\$summaryFile')
Assert-True 'its suite entries carry half = cli' ($runnerSource -match "half\s+=\s+'cli'")
Assert-True 'and the summary path comes from the one rule' ($runnerSource -match 'Get-P20TestSummaryPath' -and $runnerSource -notmatch '"test-summary\.\$')
$cfg = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'config.default.json')) | ConvertFrom-Json
Assert-True 'config: Test outlasts the bridge''s default timeout' ([int]$cfg.commands.Test.bridgeTimeoutSeconds -ge 1800)

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host ""
if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'TestAll' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
