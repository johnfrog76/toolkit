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
                       each half in a job of its own with its own installs
                       and lints, the filter, the contract job, the one
                       check that sums them up, and no action past the three named;
                       and pages.yml, the landing page's deploy, on the
                       button alone, with no secret, the Pages permissions
                       and a read, and its actions pinned to a major version.
      1c. CI's scope   which jobs a change runs, one row per path class
                       (Tests/fixtures/ci-scope/table.json), count lines alone
                       reaching no half (count-lines.json) and the classifier
                       under it, the script as the changes job runs it, and
                       the carried paste lines:
                       identical, typed, and a half that ran not compared.
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

# A worker jest force-exited (#238): every test passed and a test still left a timer or a handle
# open. The same transcript with and without the sentence, through Test's reader and CI's.
$jestClean = "Test Suites: 159 passed, 159 total`nTests:       1891 passed, 1891 total`nSnapshots:   0 total"
$jestLeak = "Test Suites: 159 passed, 159 total`nTests:       1891 passed, 1891 total`nSnapshots:   0 total`nTime:        49.9 s`nA worker process has failed to exit gracefully and has been force exited. This is likely caused by tests leaking due to improper teardown. Try running with --detectOpenHandles to find leaks. Active timers can also cause this, ensure that .unref() was called on them."
$leakTable = @(
    # transcript, exit, result
    @($jestClean, 0, 'pass'),
    @($jestLeak, 0, 'fail')
)
foreach ($row in $leakTable) {
    $c = ConvertFrom-P20JestOutput -Text $row[0]
    $label = if ($row[2] -eq 'fail') { 'with the force-exit sentence' } else { 'without it' }
    $test = Get-P20HalfVerdict -Counts $c -ExitCode $row[1]
    Assert-True "jest $label`: Test's verdict is $($row[2])" ($c.Found -and $c.Passed -eq 1891 -and $test.Result -eq $row[2]) "got $($test.Result) '$($test.Detail)'"
    $ci = Get-P20CiHalfVerdict -Half 'web' -Text $row[0] -ExitCode $row[1]
    Assert-True "jest $label`: CI's verdict is $($row[2]), the same as Test's" ($ci.Result -eq $row[2] -and $ci.Detail -eq $test.Detail) "got $($ci.Result) '$($ci.Detail)'"
    if ($row[2] -eq 'fail') {
        Assert-True 'and the failure names --detectOpenHandles as the next step' ($test.Detail -like '*--detectOpenHandles*') $test.Detail
    }
}

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

# Each job's own text, from its two-space key under jobs: to the next one.
$wfJobs = [ordered]@{}
$jobsAt = $workflow.IndexOf("`njobs:")
if ($jobsAt -ge 0) {
    $jobsText = $workflow.Substring($jobsAt)
    $keys = @([regex]::Matches($jobsText, '(?m)^  ([a-z][a-z0-9-]*):\s*$'))
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $from = $keys[$i].Index
        $to = $jobsText.Length
        if ($i + 1 -lt $keys.Count) { $to = $keys[$i + 1].Index }
        $wfJobs[$keys[$i].Groups[1].Value] = $jobsText.Substring($from, $to - $from)
    }
}
function Get-WfJob { param([string]$Name) if ($wfJobs.Contains($Name)) { return [string]$wfJobs[$Name] } return '' }
Assert-True 'verify.yml has the jobs changes, cli, agent, web, contract, verify, windows and ps51, in that order' `
    ((@($wfJobs.Keys) -join ',') -eq 'changes,cli,agent,web,contract,verify,windows,ps51') (@($wfJobs.Keys) -join ',')
$jCli = Get-WfJob 'cli'; $jAgent = Get-WfJob 'agent'; $jWeb = Get-WfJob 'web'
$jChanges = Get-WfJob 'changes'; $jContract = Get-WfJob 'contract'; $jVerify = Get-WfJob 'verify'

# Each half in a job of its own, with only the installs it needs, waiting on the filter.
Assert-True 'the cli job runs tkTest -Half cli in a shell with the module path set inside it, read through the gate' `
    ($jCli -match "pwsh -NoProfile -Command '\`$env:PSModulePath = \(Resolve-Path \.\); Import-Module \./Prompt20Toolkit/Prompt20Toolkit\.psd1 -Force; tkTest -Half cli; exit \`$LASTEXITCODE' 2>&1 \| tee [^\r\n]+\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half cli\b")
Assert-True 'the agent job runs python -m pytest Tests/, read through the gate' `
    ($jAgent -match 'python -m pytest Tests/ 2>&1 \| tee [^\r\n]+\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half agent\b')
Assert-True 'the web job runs npm test, read through the gate' `
    ($jWeb -match 'npm test 2>&1 \| tee [^\r\n]+\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half web\b')
Assert-True 'the cli job installs neither Node nor Python' (($jCli -ne '') -and ($jCli -notmatch 'setup-node|setup-python|npm ci|pip install'))
Assert-True 'the agent job installs Python and not Node' (($jAgent -match 'actions/setup-python@') -and ($jAgent -match 'pip install -r agent/requirements-dev\.txt') -and ($jAgent -notmatch 'setup-node|npm ci'))
Assert-True 'the web job installs Node and not Python' (($jWeb -match 'actions/setup-node@') -and ($jWeb -match 'npm ci') -and ($jWeb -notmatch 'setup-python|pip install'))
Assert-True 'the agent job carries its lints and its audit: ruff check, ruff format --check, pip-audit' `
    (($jAgent -match '(?m)^\s+ruff check\s*$') -and ($jAgent -match '(?m)^\s+ruff format --check\s*$') -and ($jAgent -match 'pip_audit -r agent/requirements-dev\.txt'))
Assert-True 'the web job carries its lints and its audit: npm run lint, npm run lint:md, npm audit --omit=dev at high' `
    (($jWeb -match '(?m)^\s+run: npm run lint\s*$') -and ($jWeb -match '(?m)^\s+run: npm run lint:md\s*$') -and ($jWeb -match 'npm audit --omit=dev --audit-level=high'))
foreach ($j in @('cli', 'agent', 'web', 'contract')) {
    $jt = Get-WfJob $j
    Assert-True "the $j job waits on the filter and runs only when it says so" `
        (($jt -match '(?m)^\s+needs: changes\s*$') -and ($jt -match ("(?m)^\s+if: \`$\{\{ needs\.changes\.outputs\." + $j + " == 'true' \}\}\s*$")))
}

# The filter: one step that diffs against the pull request's base and hands the list
# to the rule, with no action of its own beyond the checkout.
Assert-True 'the changes job is not on the schedule, and checks out the whole history' `
    (($jChanges -match "(?m)^\s+if: \`$\{\{ github\.event_name != 'schedule' \}\}\s*$") -and ($jChanges -match '(?m)^\s+fetch-depth: 0\s*$'))
Assert-True 'the changes job sets cli, agent, web and contract from one step' `
    (@('cli', 'agent', 'web', 'contract' | Where-Object { $jChanges -notmatch ("(?m)^\s+" + $_ + ": \`$\{\{ steps\.scope\.outputs\." + $_ + " \}\}\s*$") }).Count -eq 0)
$scopeSteps = @([regex]::Matches($jChanges, '(?m)^\s+- name: '))
Assert-True 'that one step diffs against the base sha and runs Get-CiScope.ps1 over the list' `
    (($scopeSteps.Count -eq 1) -and ($jChanges -match 'github\.event\.pull_request\.base\.sha') -and ($jChanges -match 'git diff --name-only --no-renames "\$BASE\.\.\.HEAD" > "\$RUNNER_TEMP/changed\.txt"') -and ($jChanges -match 'Scripts/Get-CiScope\.ps1 -Event "\$EVENT" -PathsFile "\$RUNNER_TEMP/changed\.txt" -CountDiffFile "\$RUNNER_TEMP/counts\.diff" -BaseRoot "\$RUNNER_TEMP/base"')) "$($scopeSteps.Count) named step(s)"
Assert-True 'that step hands the rule the -U0 diff of the three count-line documents and their text at the base' `
    (($jChanges -match 'git diff -U0 --no-renames "\$BASE\.\.\.HEAD" -- docs/TESTING\.md AGENTS\.md VERIFY\.md > "\$RUNNER_TEMP/counts\.diff"') -and ($jChanges -match 'git show "\$from:\$f" > "\$RUNNER_TEMP/base/\$f"'))

# The contract set: the CLI's five suites with the module path set inside pwsh, the
# agent's three files, the markdown lint, the carried paste lines -- each gated on
# its half not running.
Assert-True 'the contract job runs Consts, Portability, Menu, DocCounts and Changelog with the module path set inside pwsh, read through the gate, when the cli job did not run' `
    (($jContract -match "pwsh -NoProfile -Command '\`$env:PSModulePath = \(Resolve-Path \.\); & \./Tests/Test-Toolkit\.ps1 -Consts -Portability -Menu -DocCounts -Changelog; exit \`$LASTEXITCODE' 2>&1 \| tee [^\r\n]+\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half cli\b") -and ($jContract -match "needs\.changes\.outputs\.cli != 'true'"))
Assert-True 'the contract job runs the agent''s three contract files, read through the gate, when the agent job did not run' `
    (($jContract -match 'python -m pytest Tests/test_consts\.py Tests/test_pr_comments\.py Tests/test_third_party_notices\.py 2>&1 \| tee [^\r\n]+\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half agent\b') -and ($jContract -match "needs\.changes\.outputs\.agent != 'true'"))
Assert-True 'the contract job runs the markdown lint, after its own npm ci, when the web job did not run' `
    (($jContract -match "(?m)^\s+run: npm run lint:md\s*$") -and ($jContract -match "(?m)^\s+run: npm ci\s*$") -and ($jContract -match "needs\.changes\.outputs\.web != 'true' && steps\.npm\.outcome == 'success'"))
Assert-True 'the contract job holds the carried paste lines to main''s, from the base sha' `
    (($jContract -match 'git show "\$BASE:docs/TESTING\.md"') -and ($jContract -match 'Scripts/Test-CarriedCounts\.ps1 -BasePath [^\r\n]+ -HeadPath docs/TESTING\.md -Ran ') -and ($jContract -match 'fetch-depth: 0'))

# The one check that sums the run up: every job behind it, always run, each needed job held to success.
Assert-True 'the verify job is named Verify, needs every Ubuntu job and ps51, and runs always, but not on the schedule' `
    (($jVerify -match '(?m)^\s+name: Verify\s*$') -and ($jVerify -match '(?m)^\s+needs: \[changes, cli, agent, web, contract, ps51\]\s*$') -and ($jVerify -match "(?m)^\s+if: \`$\{\{ always\(\) && github\.event_name != 'schedule' \}\}\s*$"))
Assert-True 'the verify job reads the filter''s answer and every job''s result' `
    (($jVerify -match 'needs\.changes\.result') -and (@('cli', 'agent', 'web', 'contract' | Where-Object { ($jVerify -notmatch ("needs\.changes\.outputs\." + $_ + " \}\}")) -or ($jVerify -notmatch ("needs\." + $_ + "\.result")) }).Count -eq 0))
Assert-True 'the verify job reads ps51''s result and holds it in the same loop as the Ubuntu jobs' `
    (($jVerify -match '(?m)^\s+GOT_PS51: \$\{\{ needs\.ps51\.result \}\}\s*$') -and ($jVerify -match '(?m)^\s+for job in cli agent web contract ps51; do\s*$'))
Assert-True 'the verify job does not wait for the windows job' ($jVerify -notmatch 'needs\.windows\.|, windows')

$wfUses = @([regex]::Matches($workflow, '(?m)^\s+(?:- )?uses: (\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'verify.yml uses no action but actions/checkout, actions/setup-node and actions/setup-python, each pinned to a major version' `
    (($wfUses.Count -gt 0) -and (@($wfUses | Where-Object { $_ -notmatch '^actions/(checkout|setup-node|setup-python)@v\d+$' }).Count -eq 0)) ($wfUses -join ', ')
Assert-True 'verify.yml asks for no secret and reads with contents: read' (($workflow -notmatch 'secrets\.') -and ($workflow -match '(?m)^permissions:\s*\r?\n\s+contents: read'))
foreach ($mode in @('matrix', 'a11y')) {
    Assert-True "verify.yml reads the browser smoke's $mode mode through Test-CiHalf.ps1" ($workflow -match ('npm run smoke:' + $mode + ' 2>&1 \| Tee-Object[^\r\n]*\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half smoke\b'))
}
Assert-True 'verify.yml has a Windows job' ($workflow -match '(?m)^\s+runs-on: windows-latest\s*$')
Assert-True 'the Windows job runs the CLI from Windows PowerShell 5.1, the module path set inside that shell' `
    ($workflow -match "powershell\.exe -NoProfile -Command '\`$env:PSModulePath = \(Resolve-Path \.\); Import-Module \./Prompt20Toolkit/Prompt20Toolkit\.psd1 -Force; tkTest -Half cli; exit \`$LASTEXITCODE'")
# tkTest starts the runner in pwsh, so the step above runs every suite on 7, and
# its name says so. The ps51 job starts the runner in powershell.exe with no suite
# switch, which starts every suite in 5.1, so every suite's own code runs there.
# A suite that starts its children through Invoke-P20TestHost
# (Tests/Get-TestHost.ps1) runs its verbs in 5.1 too; the rest still start pwsh
# by name, and Test-Portability's Clause 22 lists them. The job is read through
# the same gate.
Assert-True 'the smoke job''s CLI step says it runs the suites in PowerShell 7' `
    ($workflow -match "(?m)^\s+- name: The CLI in PowerShell 7 on Windows -- tkTest -Half cli\s*$")
$ps51Job = Get-WfJob 'ps51'
Assert-True 'verify.yml has a ps51 job on Windows with a timeout of its own' `
    (($ps51Job -match '(?m)^\s+runs-on: windows-latest\s*$') -and ($ps51Job -match '(?m)^\s+timeout-minutes: \d+\s*$'))
Assert-True 'the ps51 job runs every CLI suite with the runner itself in Windows PowerShell 5.1, no suite switch, read by the CLI gate' `
    ($ps51Job -match "powershell\.exe -NoProfile -Command '\`$env:PSModulePath = \(Resolve-Path \.\); & \./Tests/Test-Toolkit\.ps1; exit \`$LASTEXITCODE' 2>&1 \| Tee-Object -FilePath \`$log\r?\n[^\r\n]*\r?\n[^\r\n]*Test-CiHalf\.ps1 -Half cli\b")
Assert-True 'the ps51 job says which ANSI code page 5.1 reads a script without a BOM in' `
    ($ps51Job -match "powershell\.exe -NoProfile -Command '[^'\r\n]*\[System\.Text\.Encoding\]::Default\.CodePage'")
Assert-True 'no step runs a hand-picked list of suites on 5.1: the ps51 job runs them all' `
    (($workflow -notmatch 'on Windows PowerShell 5\.1 itself') -and ($ps51Job -notmatch "Test-Toolkit\.ps1 -[A-Z]") -and ($workflow -notmatch "powershell\.exe [^\r\n]*Test-Toolkit\.ps1 -[A-Z]"))
$jobCount = [regex]::Matches($workflow, '(?m)^\s+runs-on:').Count
Assert-True 'verify.yml runs on pull requests (default types: labeled is NOT a trigger), pushes to main, the button, and a weekday schedule' `
    (($workflow -match '(?m)^\s+workflow_dispatch:') -and ($workflow -notmatch '(?m)^\s+types:') -and ($workflow -notmatch '(?m)^\s+if: .*labeled') -and ($workflow -match '(?ms)^\s+push:\s*\r?\n\s+branches: \[main\]') -and ($workflow -match '(?m)^\s+- cron: "[^"]+"'))
$windowsJob = Get-WfJob 'windows'
Assert-True 'the Windows job runs on the schedule, the button and the ci label, and not on a push to main' `
    (($windowsJob -match "(?m)^\s+if: .*github\.event_name == 'schedule'") -and ($windowsJob -match "(?m)^\s+if: .*github\.event_name == 'workflow_dispatch'") -and ($windowsJob -match "(?m)^\s+if: .*labels\.\*\.name, 'ci'") -and ($windowsJob -notmatch "(?m)^\s+if: .*'push'"))
Assert-True 'the Windows job waits on no other job, so the filter cannot skip it' (($windowsJob -ne '') -and ($windowsJob -notmatch '(?m)^\s+needs:'))
# ps51: the Windows triggers, and on a pull request the CLI scope too. It needs the
# filter, which does not run on the schedule, so it asks !cancelled() and not the
# filter's success. Verify's WANT_PS51 is the same expression, so the job and the
# aggregate cannot disagree about whether a run needed it.
$ps51Rule = [regex]::Match($ps51Job, "(?m)^\s+if: \`$\{\{ !cancelled\(\) && \((.+)\) \}\}\s*$").Groups[1].Value
$verifyRule = [regex]::Match($jVerify, "(?m)^\s+WANT_PS51: \`$\{\{ (.+) \}\}\s*$").Groups[1].Value
Assert-True 'the ps51 job runs on the Windows triggers: the schedule, the button and the ci label, not a push' `
    (($ps51Rule -match "github\.event_name == 'schedule'") -and ($ps51Rule -match "github\.event_name == 'workflow_dispatch'") -and ($ps51Rule -match "github\.event_name == 'pull_request' && contains\(github\.event\.pull_request\.labels\.\*\.name, 'ci'\)") -and ($ps51Rule -notmatch "'push'")) $ps51Rule
Assert-True 'on a pull request the ps51 job is gated on the CLI scope: needs changes, and the ci clause asks for outputs.cli' `
    (($ps51Job -match '(?m)^\s+needs: changes\s*$') -and ($ps51Rule -match "contains\(github\.event\.pull_request\.labels\.\*\.name, 'ci'\) && needs\.changes\.outputs\.cli == 'true'\)"))
Assert-True 'Verify reads ps51 as needed by the very expression that starts it' (($ps51Rule -ne '') -and ($verifyRule -eq $ps51Rule)) "if: $ps51Rule / WANT_PS51: $verifyRule"
# The rule, evaluated: the expression rewritten into PowerShell and run over one row
# per case, the CLI scope taken from Get-P20CiScope where the row names paths. The
# scope table has no label column, so the label is the row's here.
$ps51Ps = $ps51Rule -replace "contains\(github\.event\.pull_request\.labels\.\*\.name, 'ci'\)", '($labels -contains ''ci'')' `
    -replace 'github\.event_name', '$ev' -replace "needs\.changes\.outputs\.cli", '$cliOut' -replace '==', '-eq' -replace '&&', '-and' -replace '\|\|', '-or'
$ps51Cases = @(
    @{ ev = 'schedule'; labels = @(); paths = $null; cli = ''; want = $true; why = 'the schedule runs ps51, though the filter does not run' }
    @{ ev = 'workflow_dispatch'; labels = @(); paths = $null; cli = 'true'; want = $true; why = 'the button runs ps51' }
    @{ ev = 'push'; labels = @(); paths = $null; cli = 'true'; want = $false; why = 'a push to main does not' }
    @{ ev = 'pull_request'; labels = @('ci'); paths = @('Scripts/Get-Status.ps1'); cli = $null; want = $true; why = 'a ci-labelled pull request that reaches the CLI runs ps51' }
    @{ ev = 'pull_request'; labels = @('ci'); paths = @('web/src/App.tsx'); cli = $null; want = $false; why = 'a ci-labelled pull request that is web-only starts no ps51, and Verify reads it as not needed' }
    @{ ev = 'pull_request'; labels = @(); paths = @('Scripts/Get-Status.ps1'); cli = $null; want = $false; why = 'a pull request with no ci label does not' }
)
try {
    $ps51Eval = [scriptblock]::Create("param(`$ev, `$labels, `$cliOut) [bool]($ps51Ps)")
    foreach ($c in $ps51Cases) {
        $cliOut = $c.cli
        if ($null -ne $c.paths) {
            $sc = Get-P20CiScope -Event $c.ev -Paths $c.paths
            $cliOut = ([string]([bool]$sc.cli)).ToLowerInvariant()
        }
        $got = & $ps51Eval $c.ev $c.labels $cliOut
        Assert-True "ps51's rule: $($c.why)" ($got -eq $c.want) "got $got, cli=$cliOut"
    }
}
catch {
    Assert-True 'ps51''s rule evaluates as PowerShell' $false "$($_.Exception.Message) / $ps51Ps"
}
Assert-True 'a scheduled run has a concurrency group of its own and cancel-in-progress is only for pull requests' `
    (($workflow -match "group: verify-\$\{\{ github\.event_name == 'schedule'") -and ($workflow -match "cancel-in-progress: \$\{\{ github\.event_name == 'pull_request' \}\}"))
Assert-True 'every job in verify.yml has a timeout' (($jobCount -eq $wfJobs.Count) -and ([regex]::Matches($workflow, '(?m)^\s+timeout-minutes: \d+').Count -eq $jobCount)) "$jobCount runs-on, $($wfJobs.Count) jobs"

# -- 1c. CI's scope and the carried paste lines ---------------------------------
# Get-P20CiScope over one row per path class (Tests/fixtures/ci-scope/table.json),
# the script as the changes job calls it, and the carried-lines check.
Write-Host ""
Write-Host "-- CI's scope: which jobs a change runs --" -ForegroundColor Cyan
$scopeFixture = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/ci-scope/table.json')) | ConvertFrom-Json
Assert-True 'the scope table has rows' (@($scopeFixture.rows).Count -gt 0)
foreach ($row in @($scopeFixture.rows)) {
    $sc = Get-P20CiScope -Event $row.event -Paths @($row.paths)
    $want = "cli=$($row.cli) agent=$($row.agent) web=$($row.web) contract=$($row.contract)"
    $got = "cli=$($sc.cli) agent=$($sc.agent) web=$($sc.web) contract=$($sc.contract)"
    Assert-True "scope: $($row.why)" ($want -eq $got) "want $want, got $got"
}
Assert-True 'scope: each path is reported with its class' `
    (((@((Get-P20CiScope -Event 'pull_request' -Paths @('web/a.ts', 'CHANGELOG.md', 'consts.json', 'x.txt')).Paths) | ForEach-Object { $_[1] }) -join ',') -eq 'web,changelog,shared,unclassified')
Assert-True 'scope: a module document, the scenario grid and the known gaps are prose, a changelog fragment is changelog' `
    (((@((Get-P20CiScope -Event 'pull_request' -Paths @('docs/modules/studio.md', 'docs/SCENARIOS.md', 'docs/KNOWN-GAPS.md', 'changelog.d/1.fixed.md', 'docs/CLI.md')).Paths) | ForEach-Object { $_[1] }) -join ',') -eq 'prose,prose,prose,changelog,shared')

# Count lines alone reach no half. The classifier first: the line numbers it reads
# as count lines, a -U0 diff's changed lines, and a removed line that starts `--`.
Write-Host ""
Write-Host "-- CI's scope: count lines alone --" -ForegroundColor Cyan
$countFixture = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/ci-scope/count-lines.json')) | ConvertFrom-Json
$countBase = @{}
foreach ($pr in $countFixture.base.PSObject.Properties) { $countBase[$pr.Name] = (@($pr.Value) -join "`n") + "`n" }
$nums = Get-P20CountLineNumbers -Path 'docs/TESTING.md' -Text $countBase['docs/TESTING.md']
Assert-True 'count lines in docs/TESTING.md: the command block''s three, the paste block''s five, the table row' `
    ((@($nums.Keys | Sort-Object) -join ',') -eq '4,8,9,17,18,19,20,21,26') (@($nums.Keys | Sort-Object) -join ',')
Assert-True 'count lines in AGENTS.md and VERIFY.md: the one line each that DocCounts reads' `
    (((@((Get-P20CountLineNumbers -Path 'AGENTS.md' -Text $countBase['AGENTS.md']).Keys) -join ',') -eq '4') -and ((@((Get-P20CountLineNumbers -Path 'VERIFY.md' -Text $countBase['VERIFY.md']).Keys) -join ',') -eq '3'))
Assert-True 'a file with no rule has no count lines' ((Get-P20CountLineNumbers -Path 'README.md' -Text "tkTestToolkit # 3 suites, 60 assertions`n").Count -eq 0)
$handDiff = "diff --git a/VERIFY.md b/VERIFY.md`nindex 1..2 100644`n--- a/VERIFY.md`n+++ b/VERIFY.md`n@@ -3 +3 @@ ## Gate 4`n-old three`n+new three`n@@ -5,2 +4,0 @@`n--- a dash line`n-five`n@@ -9,0 +8,2 @@`n+++ a plus line`n+eight`n\ No newline at end of file`n"
$changed = @(Get-P20DiffChangedLines -Diff $handDiff)
$changedSaid = @($changed | ForEach-Object { "$($_.Path):$($_.Side)$($_.Line)=$($_.Text)" }) -join ' | '
Assert-True 'a -U0 diff''s changed lines, each with its side and number, a `--` or `++` line read as a line' `
    ($changedSaid -eq 'VERIFY.md:old3=old three | VERIFY.md:new3=new three | VERIFY.md:old5=-- a dash line | VERIFY.md:old6=five | VERIFY.md:new8=++ a plus line | VERIFY.md:new9=eight') $changedSaid

# A -U0 diff of a case's edits, in git's shape: one hunk per edited line.
function New-CountCase {
    param($Case, [hashtable]$Base)
    $head = @{}
    foreach ($k in $Base.Keys) { $head[$k] = [System.Collections.Generic.List[string]]@(($Base[$k].TrimEnd("`n")) -split "`n") }
    $hunks = @{}
    foreach ($e in @($Case.edits)) {
        $lines = $head[$e.path]
        if (-not $hunks.ContainsKey($e.path)) { $hunks[$e.path] = @() }
        if ($e.PSObject.Properties.Name -contains 'find') {
            $n = $lines.IndexOf([string]$e.find) + 1
            $lines[$n - 1] = [string]$e.replace
            $hunks[$e.path] += , @($n, "@@ -$n +$n @@`n-$($e.find)`n+$($e.replace)")
        }
        else {
            $n = $lines.IndexOf([string]$e.after) + 1
            $lines.Insert($n, [string]$e.insert)
            $hunks[$e.path] += , @($n, "@@ -$n,0 +$($n + 1) @@`n+$($e.insert)")
        }
    }
    $diff = ''
    foreach ($k in @($hunks.Keys | Sort-Object)) {
        $diff += "diff --git a/$k b/$k`n--- a/$k`n+++ b/$k`n"
        foreach ($h in @($hunks[$k] | Sort-Object { $_[0] })) { $diff += $h[1] + "`n" }
    }
    $headText = @{}
    foreach ($k in $head.Keys) { $headText[$k] = ($head[$k] -join "`n") + "`n" }
    return @{ Diff = $diff; Head = $headText; Edited = @($hunks.Keys) }
}
foreach ($case in @($countFixture.cases)) {
    $built = New-CountCase -Case $case -Base $countBase
    $only = Get-P20CountOnlyPaths -Diff $built.Diff -BaseTexts $countBase -HeadTexts $built.Head
    $onlyPaths = @($only.Keys | Where-Object { $only[$_].CountOnly } | Sort-Object)
    $sc = Get-P20CiScope -Event 'pull_request' -Paths (@($case.paths) + @($built.Edited)) -CountOnly $onlyPaths
    $want = "countOnly=$(@($case.countOnly | Sort-Object) -join ',') cli=$($case.cli) agent=$($case.agent) web=$($case.web) contract=$($case.contract)"
    $got = "countOnly=$($onlyPaths -join ',') cli=$($sc.cli) agent=$($sc.agent) web=$($sc.web) contract=$($sc.contract)"
    Assert-True "count lines: $($case.why)" ($want -eq $got) "want $want, got $got"
}

. (Join-Path $scriptDir 'Get-TestHost.ps1')
$scopeScript = Join-Path $pkgRoot 'Scripts/Get-CiScope.ps1'
$scopeScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-ci-scope-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$heldActions = $env:GITHUB_ACTIONS; $heldOutput = $env:GITHUB_OUTPUT; $heldSummary = $env:GITHUB_STEP_SUMMARY
try {
    New-Item -ItemType Directory -Path $scopeScratch -Force | Out-Null
    $listFile = Join-Path $scopeScratch 'changed.txt'
    $outFile = Join-Path $scopeScratch 'output.txt'
    [System.IO.File]::WriteAllText($listFile, "web/src/App.tsx`nweb/README.md`n")
    [System.IO.File]::WriteAllText($outFile, '')
    $env:GITHUB_ACTIONS = 'true'; $env:GITHUB_OUTPUT = $outFile; $env:GITHUB_STEP_SUMMARY = ''
    $said = (Invoke-P20TestHost -File $scopeScript -Arguments @('-Event', 'pull_request', '-PathsFile', $listFile) | ForEach-Object { [string]$_ }) -join "`n"
    $code = $LASTEXITCODE
    $written = [System.IO.File]::ReadAllText($outFile) -replace "`r", ''
    Assert-True 'Get-CiScope.ps1, run as the changes job runs it: exit 0 and the four outputs for a web-only list' `
        (($code -eq 0) -and ($written -eq "cli=false`nagent=false`nweb=true`ncontract=true`n")) "exit $code, wrote '$written' -- $said"
    # The same call with the count-line files: a web change that pastes its web line.
    $built = New-CountCase -Case @($countFixture.cases)[0] -Base $countBase
    $baseDir = Join-Path $scopeScratch 'base'
    $headDir = Join-Path $scopeScratch 'head'
    foreach ($pair in @(@($baseDir, $countBase), @($headDir, $built.Head))) {
        foreach ($k in $pair[1].Keys) {
            $dest = Join-Path $pair[0] $k
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            [System.IO.File]::WriteAllText($dest, $pair[1][$k])
        }
    }
    $diffFile = Join-Path $scopeScratch 'counts.diff'
    [System.IO.File]::WriteAllText($diffFile, $built.Diff)
    [System.IO.File]::WriteAllText($listFile, "web/src/App.tsx`ndocs/TESTING.md`n")
    [System.IO.File]::WriteAllText($outFile, '')
    $said = (Invoke-P20TestHost -File $scopeScript -Arguments @('-Event', 'pull_request', '-PathsFile', $listFile, '-CountDiffFile', $diffFile, '-BaseRoot', $baseDir, '-HeadRoot', $headDir) | ForEach-Object { [string]$_ }) -join "`n"
    $code = $LASTEXITCODE
    $written = [System.IO.File]::ReadAllText($outFile) -replace "`r", ''
    Assert-True 'Get-CiScope.ps1 with the count-line diff: a pasted web line beside a web change is web plus contract' `
        (($code -eq 0) -and ($written -eq "cli=false`nagent=false`nweb=true`ncontract=true`n") -and ($said -match 'count lines: docs/TESTING\.md')) "exit $code, wrote '$written' -- $said"
    $env:GITHUB_ACTIONS = ''; $env:GITHUB_OUTPUT = ''
    $null = Invoke-P20TestHost -File $scopeScript -Arguments @('-Event', 'pull_request', '-PathsFile', $listFile, '-CountDiffFile', (Join-Path $scopeScratch 'absent.diff'))
    Assert-True 'Get-CiScope.ps1 with no diff at the path it was given exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
    $null = Invoke-P20TestHost -File $scopeScript -Arguments @('-Event', 'pull_request', '-PathsFile', (Join-Path $scopeScratch 'absent.txt'))
    Assert-True 'Get-CiScope.ps1 with no list at the path it was given exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
}
catch {
    Assert-True 'the scope script cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    $env:GITHUB_ACTIONS = $heldActions; $env:GITHUB_OUTPUT = $heldOutput; $env:GITHUB_STEP_SUMMARY = $heldSummary
    Remove-Item -LiteralPath $scopeScratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "-- CI's carried paste lines --" -ForegroundColor Cyan
function New-PasteDoc {
    param([string]$Cli = 'Consts 10, Compat 20', [string]$Total = '2 suites, 30 assertions', [string]$Pytest = 'pytest: 12 passed, 1 skipped', [string]$Web = 'web: 7 suites, 55 tests')
    return "# Testing`n`n**The counts, after a merge.** The block:`n`n``````text`n  Counts for docs/TESTING.md's paste block, from this run:`n  $Cli`n  $Total`n  $Pytest`n  $Web`n```````n"
}
$carriedBase = New-PasteDoc
$carriedTable = @(
    # why, head, ran, finding count, a fragment the finding must contain
    @('identical, a web-only change', (New-PasteDoc), @('web'), 0, ''),
    @('a typed pytest count on a web-only change', (New-PasteDoc -Pytest 'pytest: 13 passed, 1 skipped'), @('web'), 1, "the agent half's paste line 'pytest: 13 passed, 1 skipped' is not main's 'pytest: 12 passed, 1 skipped'"),
    @('a typed CLI total on a web-only change', (New-PasteDoc -Total '2 suites, 31 assertions'), @('web'), 1, "the cli half's paste line '2 suites, 31 assertions' is not main's '2 suites, 30 assertions'"),
    @('a new web count on a web-only change: the web half ran, so it is not compared', (New-PasteDoc -Web 'web: 7 suites, 56 tests'), @('web'), 0, ''),
    @('a new CLI count where the CLI ran', (New-PasteDoc -Cli 'Consts 10, Compat 21' -Total '2 suites, 31 assertions'), @('cli'), 0, ''),
    @('every half ran: nothing is compared', (New-PasteDoc -Pytest 'pytest: 99 passed' -Web 'web: 1 suites, 1 tests'), @('cli', 'agent', 'web'), 0, ''),
    @('two typed lines, two halves named', (New-PasteDoc -Pytest 'pytest: 13 passed, 1 skipped' -Cli 'Consts 11, Compat 20'), @('web'), 2, "the cli half's paste line 'Consts 11, Compat 20'"),
    @('a change with no paste block', "# Testing`n", @('web'), 1, "this change's docs/TESTING.md has no paste block")
)
foreach ($row in $carriedTable) {
    $got = @(Get-P20CarriedCountFindings -BaseText $carriedBase -HeadText $row[1] -Ran $row[2])
    $okRow = ($got.Count -eq $row[3]) -and (($row[3] -eq 0) -or (@($got | Where-Object { $_ -like "*$($row[4])*" }).Count -gt 0))
    Assert-True "carried lines: $($row[0])" $okRow ($got -join ' | ')
}
$realTesting = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'docs/TESTING.md'))
$realBlock = Get-P20PasteBlock -Text $realTesting
Assert-True 'the real docs/TESTING.md''s paste block gives every half its lines: two for the CLI, one each for the agent and the web' `
    (($null -ne $realBlock) -and (@($realBlock.cli).Count -eq 2) -and (@($realBlock.agent).Count -eq 1) -and (@($realBlock.web).Count -eq 1))
Assert-True 'the real docs/TESTING.md carries its own lines: no finding against itself' (@(Get-P20CarriedCountFindings -BaseText $realTesting -HeadText $realTesting -Ran @('web')).Count -eq 0)

$carriedScript = Join-Path $pkgRoot 'Scripts/Test-CarriedCounts.ps1'
$carriedScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-ci-carried-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $carriedScratch -Force | Out-Null
    $baseFile = Join-Path $carriedScratch 'base.md'
    $sameFile = Join-Path $carriedScratch 'same.md'
    $typedFile = Join-Path $carriedScratch 'typed.md'
    [System.IO.File]::WriteAllText($baseFile, $carriedBase)
    [System.IO.File]::WriteAllText($sameFile, (New-PasteDoc))
    [System.IO.File]::WriteAllText($typedFile, (New-PasteDoc -Pytest 'pytest: 13 passed, 1 skipped'))
    $null = Invoke-P20TestHost -File $carriedScript -Arguments @('-BasePath', $baseFile, '-HeadPath', $sameFile, '-Ran', 'web')
    Assert-True 'Test-CarriedCounts.ps1, run as the contract job runs it: carried lines that are main''s exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
    $said = (Invoke-P20TestHost -File $carriedScript -Arguments @('-BasePath', $baseFile, '-HeadPath', $typedFile, '-Ran', 'cli,web') | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True 'a typed pytest line exits 2 and names the line' (($LASTEXITCODE -eq 2) -and ($said -match [regex]::Escape("'pytest: 13 passed, 1 skipped'")) -and ($said -match '(?m)^Error: ')) "exit $LASTEXITCODE -- $said"
    $null = Invoke-P20TestHost -File $carriedScript -Arguments @('-BasePath', $baseFile, '-HeadPath', $sameFile, '-Ran', 'docs')
    Assert-True 'a -Ran that names no half exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
}
catch {
    Assert-True 'the carried-lines script cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $carriedScratch -Recurse -Force -ErrorAction SilentlyContinue
}

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
    # The verb and its fake runner write the machine's test history; here it is
    # this case's own folder, named by the override both read.
    $stubHistory = Join-Path $base 'history'
    $savedHistoryDir = [System.Environment]::GetEnvironmentVariable($consts.env.testHistoryDir)
    [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $stubHistory)
    $summaryFile = Join-Path $stubHistory (Get-P20TestHistoryFileName -Kind summary)
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
    # Where each record came from: the scratch package is in no git repository,
    # so both fields are there and empty.
    Assert-True 'every half the verb wrote carries its checkout and commit' ($s['halves']['agent'].Contains('checkout') -and $s['halves']['agent'].Contains('commit') -and $s['halves']['web'].Contains('checkout')) "$(@($s['halves']['agent'].Keys) -join ',')"
    Assert-True 'and so does the file' ($s.Contains('checkout') -and $s.Contains('commit') -and $s['checkout'] -eq '' -and $s['commit'] -eq '')

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
    if ($null -ne (Get-Variable savedHistoryDir -ErrorAction SilentlyContinue)) {
        [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $savedHistoryDir)
    }
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
    $warnHistory = Join-Path $warnBase 'history'
    $warnCmd = "`$ErrorActionPreference = 'Continue'; " +
        "`$env:$($consts.env.testHistoryDir) = '$($warnHistory -replace '\\', '/')'; " +
        "Import-Module '$warnModule/utilities.psm1' -Force 3>`$null 6>`$null; " +
        "Write-P20TestResult -Suite 'Zero' -Result 'warn' -Passed 0 -Total 0 -Detail 'ok'; " +
        "Write-P20TestResult -Suite 'Green' -Result 'pass' -Passed 3 -Total 3; " +
        "try { Write-P20TestResult -Suite 'Bad' -Result 'maybe' -Passed 0 -Total 0 } catch { Write-Output 'REFUSED-BAD-WORD' }"
    $savedQuiet = $env:TOOLKIT_QUIET_STARTUP
    $env:TOOLKIT_QUIET_STARTUP = '1'
    try { $warnOut = (& $warnHost -NoProfile -ExecutionPolicy Bypass -Command $warnCmd 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally { $env:TOOLKIT_QUIET_STARTUP = $savedQuiet }
    $warnLogs = @(Get-ChildItem -LiteralPath $warnHistory -Filter 'test-results.*.log' -ErrorAction SilentlyContinue)
    Assert-True 'the writer wrote a log in the history folder it was given' ($warnLogs.Count -eq 1) $warnOut
    Assert-True 'and none beside the module' (@(Get-ChildItem -LiteralPath $warnBase -Filter 'test-results.*.log').Count -eq 0)
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
    $savedLineHistory = [System.Environment]::GetEnvironmentVariable($consts.env.testHistoryDir)
    [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $lineBase)
    try { $lineOut = (& $lineHost -NoProfile -ExecutionPolicy Bypass -File $probe 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally {
        $env:TOOLKIT_QUIET_STARTUP = $savedQuiet
        $env:P20_USAGE_LOG_DIR = $savedLogDir
        [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $savedLineHistory)
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
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1'), (Join-Path $scriptDir 'Get-TestHost.ps1') (Join-Path $missBase 'Tests')
    $missHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $missHistory = Join-Path $missBase 'history'
    $savedMissHistory = [System.Environment]::GetEnvironmentVariable($consts.env.testHistoryDir)
    [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $missHistory)
    try { $missOut = (& $missHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $missBase 'Tests/Test-Toolkit.ps1') -Consts 2>&1 | ForEach-Object { [string]$_ }) -join "`n" }
    finally { [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $savedMissHistory) }
    $missExit = $LASTEXITCODE
    Assert-True 'the console says the file was not found' ($missOut -match 'file not found: Test-Consts\.ps1') $missOut
    Assert-True 'the runner exits non-zero: a missing suite fails the run' ($missExit -ne 0) "exit $missExit"
    $missLogs = @(Get-ChildItem -LiteralPath $missHistory -Filter 'test-results.*.log' -ErrorAction SilentlyContinue)
    $missLines = @()
    if ($missLogs.Count -eq 1) { $missLines = @([System.IO.File]::ReadAllLines($missLogs[0].FullName)) }
    $missLine = @($missLines | Where-Object { $_ -match "`tConsts`t" }) | Select-Object -First 1
    $missCols = @()
    if ($missLine) { $missCols = @($missLine -split "`t") }
    Assert-True 'the missing suite is a line in the log: fail, 0 of 1, the same seven columns, with why' ($missCols.Count -eq 7 -and $missCols[2] -eq 'fail' -and $missCols[3] -eq '0' -and $missCols[4] -eq '1' -and $missCols[5] -match 'file not found') "$missLine"
    $missSummaries = @(Get-ChildItem -LiteralPath $missHistory -Filter 'test-summary.*.json' -ErrorAction SilentlyContinue)
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

# -- 3c2. Where the machine's test history lives ----------------------------
Write-Host ""
Write-Host "-- One folder per machine: the rule, a marked run, the old record, the checkout --" -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Get-TestHistoryDir.ps1')
$historyTable = [System.IO.File]::ReadAllText((Join-Path $scriptDir 'fixtures/test-history/paths.json')) | ConvertFrom-Json
Assert-True 'the shared table has its rows' (@($historyTable.rows).Count -ge 10)
foreach ($row in @($historyTable.rows)) {
    $vars = @{}
    foreach ($p in $row.env.PSObject.Properties) { $vars[$p.Name] = [string]$p.Value }
    $got = Resolve-P20TestHistorySegments -Platform $row.platform -HomeDir $row.home -Variables $vars
    if ($null -eq $row.expected) {
        Assert-True "history: $($row.name)" ($null -eq $got) "got $(@($got) -join ' | ')"
    }
    else {
        Assert-True "history: $($row.name)" ($null -ne $got -and ((@($got) -join '|') -eq (@($row.expected) -join '|'))) "got $(@($got) -join ' | ')"
    }
}

$histBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-testall-history-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $histBase -Force | Out-Null
$histNames = @($consts.env.testHistoryDir, $consts.env.testRunMarker, 'HOME', 'USERPROFILE', 'LOCALAPPDATA', 'XDG_STATE_HOME')
$histSaved = @{}
foreach ($n in $histNames) { $histSaved[$n] = [System.Environment]::GetEnvironmentVariable($n) }
try {
    # Every place the rule could reach is under one scratch home, so a mistake
    # lands there and the assertion below sees it.
    $fakeHistHome = Join-Path $histBase 'home'
    New-Item -ItemType Directory -Path $fakeHistHome -Force | Out-Null
    $homeVars = @{ HOME = $fakeHistHome; USERPROFILE = $fakeHistHome; LOCALAPPDATA = (Join-Path $fakeHistHome 'local'); XDG_STATE_HOME = (Join-Path $fakeHistHome 'state') }

    # A marked run with no override: the real CLI runner in a scratch package,
    # as a suite that drives it would start it -- marker set, no override.
    $markPkg = Join-Path $histBase 'pkg'
    New-Item -ItemType Directory -Path (Join-Path $markPkg 'Tests') -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1'), (Join-Path $pkgRoot 'consts.json'), (Join-Path $pkgRoot 'config.default.json') $markPkg
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $markPkg 'Scripts') -Recurse
    if (Test-Path (Join-Path $pkgRoot 'Config')) { Copy-Item (Join-Path $pkgRoot 'Config') (Join-Path $markPkg 'Config') -Recurse }
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1'), (Join-Path $scriptDir 'Get-TestHost.ps1') (Join-Path $markPkg 'Tests')
    # An old record at the scratch package's root: a marked run must not copy it anywhere either.
    [System.IO.File]::WriteAllText((Join-Path $markPkg (Get-P20TestHistoryFileName -Kind summary)), '{ "machine": "OLD", "suites": {} }')
    foreach ($k in $homeVars.Keys) { [System.Environment]::SetEnvironmentVariable($k, $homeVars[$k]) }
    [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, $null)
    [System.Environment]::SetEnvironmentVariable($consts.env.testRunMarker, '1')
    $markDir = Get-P20TestHistoryDir -PackageRoot $markPkg
    Assert-True 'under the marker with no override, the folder is none' ($markDir -eq '') "got '$markDir'"
    $markSummary = Get-P20TestSummaryPath -PackageRoot $markPkg
    Assert-True 'and so is the summary path' ($markSummary -eq '') "got '$markSummary'"
    Merge-P20TestSummary -Path (Get-P20TestSummaryPath -PackageRoot $markPkg) -Halves @{ cli = [ordered]@{ half = 'cli'; result = 'pass' } }
    $markHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $markOut = (& $markHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $markPkg 'Tests/Test-Toolkit.ps1') -Consts 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $markWrite = "`$ErrorActionPreference = 'Continue'; Import-Module '$(($markPkg -replace '\\', '/'))/utilities.psm1' -Force 3>`$null 6>`$null; Write-P20TestResult -Suite 'Marked' -Result 'pass' -Passed 1 -Total 1"
    $markOut += (& $markHost -NoProfile -ExecutionPolicy Bypass -Command $markWrite 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    Assert-True 'the runner ran (its missing suite is named)' ($markOut -match 'file not found: Test-Consts\.ps1') $markOut
    # The host itself may keep its own caches under a home folder; what must not
    # be there is a test record, or the folder the rule would have used.
    $leaked = @(Get-ChildItem -LiteralPath $fakeHistHome -Recurse -Force | Where-Object { $_.Name -match '^test-(summary|results)\.' -or $_.Name -eq 'TestHistory' -or $_.Name -eq 'test-history' } | ForEach-Object { $_.FullName })
    Assert-True 'a marked run with no override writes no record under the home folder' ($leaked.Count -eq 0) ($leaked -join ', ')
    $atRoot = @(Get-ChildItem -LiteralPath $markPkg -Filter 'test-results.*' | ForEach-Object { $_.Name })
    Assert-True 'and nothing beside the package either' ($atRoot.Count -eq 0) ($atRoot -join ', ')

    # The old record, copied in once: no marker, no override, the scratch home.
    [System.Environment]::SetEnvironmentVariable($consts.env.testRunMarker, $null)
    $realDir = Get-P20TestHistoryDir -PackageRoot $markPkg
    Assert-True 'with neither, the folder is under the home folder' ($realDir -and $realDir.StartsWith($fakeHistHome)) $realDir
    $migrated = Join-Path $realDir (Get-P20TestHistoryFileName -Kind summary)
    Assert-True 'and the checkout''s old record was copied in, so the first read is not "not run"' ((Test-Path -LiteralPath $migrated) -and (Read-P20TestSummary -Path $migrated)['machine'] -eq 'OLD')
    Merge-P20TestSummary -Path $migrated -Halves @{ cli = [ordered]@{ half = 'cli'; result = 'pass'; passed = 1; failed = 0; total = 1 } }
    $null = Get-P20TestHistoryDir -PackageRoot $markPkg
    Assert-True 'a second read copies nothing over the newer record' ((Read-P20TestSummary -Path $migrated)['machine'] -eq [System.Environment]::MachineName)
    Assert-True 'the old file is left where it was' (Test-Path -LiteralPath (Join-Path $markPkg (Get-P20TestHistoryFileName -Kind summary)))
    [System.Environment]::SetEnvironmentVariable($consts.env.testHistoryDir, (Join-Path $histBase 'over'))
    $overDir = Get-P20TestHistoryDir -PackageRoot $markPkg
    Assert-True 'an override is the folder, and copies nothing in' ($overDir -eq (Join-Path $histBase 'over') -and -not (Test-Path -LiteralPath $overDir)) $overDir
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    foreach ($n in $histNames) { [System.Environment]::SetEnvironmentVariable($n, $histSaved[$n]) }
}

# Where a run came from: main for a repository's own tree, the folder name of
# a linked worktree, '' outside git.
try {
    $repo = Join-Path $histBase 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $null = Invoke-P20TestGit -C $repo init --quiet
    [System.IO.File]::WriteAllText((Join-Path $repo 'a.txt'), 'a')
    $null = Invoke-P20TestGit -C $repo add a.txt
    $null = Invoke-P20TestGit -C $repo -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit --quiet -m one
    $head = ((Invoke-P20TestGit -C $repo rev-parse --short HEAD).Out | Select-Object -First 1)
    $wt = Join-Path $histBase 'wt-311'
    $null = Invoke-P20TestGit -C $repo worktree add --quiet --detach $wt
    $mainSource = Get-P20TestCheckout -PackageRoot $repo
    $wtSource = Get-P20TestCheckout -PackageRoot $wt
    $noSource = Get-P20TestCheckout -PackageRoot (Join-Path $histBase 'home')
    Assert-True 'a repository''s own tree is main, at its commit' ($mainSource.checkout -eq 'main' -and $mainSource.commit -eq $head -and $head) "$($mainSource.checkout) $($mainSource.commit) $head"
    Assert-True 'a linked worktree is its folder name, at its commit' ($wtSource.checkout -eq 'wt-311' -and $wtSource.commit -eq $head) "$($wtSource.checkout) $($wtSource.commit)"
    Assert-True 'outside git, both are empty' ($noSource.checkout -eq '' -and $noSource.commit -eq '') "$($noSource.checkout) $($noSource.commit)"
}
catch {
    Assert-True 'the checkout cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $histBase -Recurse -Force -ErrorAction SilentlyContinue
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
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1'), (Join-Path $scriptDir 'Get-TestHost.ps1') (Join-Path $quietBase 'Tests')
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
    Copy-Item (Join-Path $scriptDir 'Test-Toolkit.ps1'), (Join-Path $scriptDir 'Get-ToolkitSuiteRegistry.ps1'), (Join-Path $scriptDir 'Get-TestHost.ps1') (Join-Path $ovBase 'Tests')
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
Assert-True 'and the summary path comes from the one rule' ($runnerSource -match 'Get-P20TestHistoryFile -Kind summary -Dir \$historyDir' -and $runnerSource -notmatch '"test-summary\.\$')
Assert-True 'the runner resolves the real folder before it sets the run marker' ($runnerSource -match '(?s)\$historyDir = Get-P20TestHistoryDir.*SetEnvironmentVariable\(\$runMarker, ''1''\)')
Assert-True 'and hands its children a scratch one, put back in the finally' ($runnerSource -match 'SetEnvironmentVariable\(\$historyEnv, \$scratchHistoryDir\)' -and $runnerSource -match 'SetEnvironmentVariable\(\$historyEnv, \$previousHistoryDir\)')
Assert-True 'its own records go to the folder it resolved, by name' (([regex]::Matches($runnerSource, 'Write-P20TestResult [^\r\n]*-Dir \$historyDir')).Count -eq 2)
$verbSource = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Scripts/Invoke-TestAll.ps1'))
Assert-True 'Test resolves the folder once, before the web half sets the marker' ($verbSource -match '(?s)\$historyDir = Get-P20TestHistoryDir.*\$runWeb = ')
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
