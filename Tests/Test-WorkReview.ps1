<#
.SYNOPSIS
    WorkReview -- a work review put away, typed in a fresh shell against a
    scratch package and a scratch git hub.

.DESCRIPTION
    1. Off            with features.growth unset there is no verb at all.
    2. Help           -Help prints both moves, from the module's own Help entry.
    3. -WhatIf        names the folder and writes nothing, for either move.
    4. -Archive       the folder moves under reviews/archive/, review.md carries
                      **Closed:**, summary.md moves untouched, and storeSync: git
                      commits it -- that review's paths only.
    5. -Delete        the folder is gone and the removal is committed; an
                      archived review is named archive/<slug-set>/<range>.
    6. Refusals       stated, exit 2, one block, nothing written.

    Run:  pwsh -File Tests/Test-WorkReview.ps1
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
Write-Host "  WorkReview -- archive or delete a work review" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-workreview-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
New-Item -ItemType Directory -Path $pkg, $logDir, (Join-Path $hub 'first/current'), (Join-Path $hub 'second/current') -Force | Out-Null
foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'),
    '{ "orgs": [ { "slug": "first", "name": "First", "status": "local", "promptsFolder": "first" }, { "slug": "second", "name": "Second", "status": "local", "promptsFolder": "second" } ] }', $utf8)
$hubJson = $hub -replace '\\', '/'
$localConfig = Join-Path $pkg 'config.local.json'

function New-ScratchReview {
    # The shape NewWorkReview writes, plus the summary.md the prose pass adds.
    param([string]$SlugSet, [string]$Range, [switch]$Summary)
    $dir = Join-Path $hub "reviews/$SlugSet/$($Range.Substring(0, 4))/$Range"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $orgs = ($SlugSet -split '\+') -join ', '
    [System.IO.File]::WriteAllText((Join-Path $dir 'review.md'),
        "---`norgs: [$orgs]`nperiod: $Range`ngenerated: 2026-05-01`ngenerator: scaffold`n---`n`n# Review -- $Range`n`n**Period:** $Range`n", $utf8)
    if ($Summary) { [System.IO.File]::WriteAllText((Join-Path $dir 'summary.md'), "# Summary`n`nEverything.`n", $utf8) }
    return $dir
}

function Invoke-Git {
    param([string[]]$GitArgs)
    Push-Location $hub
    try { return ((& git @GitArgs 2>&1 | ForEach-Object { "$_" }) -join "`n") } finally { Pop-Location }
}

function Invoke-Verbs {
    # A fresh shell per call, the package's own module and nothing else, the way
    # a person types a verb (AGENTS.md, "One toolkit per shell").
    param([string]$Snippet, [bool]$On = $true)
    $features = if ($On) { '{ "growth": true }' } else { '{}' }
    [System.IO.File]::WriteAllText($localConfig,
        "{ `"promptsRoot`": `"$hubJson`", `"activeOrg`": `"first`", `"quietStart`": true, `"storeSync`": `"git`", `"features`": $features }", $utf8)
    $body = "`$env:PSModulePath = '$($pkg -replace "'", "''")'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$($logDir -replace "'", "''")'; " +
        "Import-Module '$($pkg -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; $Snippet"
    return ((& pwsh -NoProfile -NonInteractive -Command $body 2>&1 | ForEach-Object { "$_" }) -join "`n")
}

function Get-TreeSnapshot {
    # Every file under reviews/ with its bytes: "wrote nothing" is this, unchanged.
    $root = Join-Path $hub 'reviews'
    if (-not (Test-Path $root)) { return '' }
    return ((Get-ChildItem $root -Recurse -File | Sort-Object FullName | ForEach-Object {
                $_.FullName.Substring($root.Length) + '=' + [System.IO.File]::ReadAllText($_.FullName)
            }) -join '|')
}

try {
    $null = Invoke-Git @('init', '-q')
    $null = Invoke-Git @('config', 'user.email', 'test@example.invalid')
    $null = Invoke-Git @('config', 'user.name', 'Test')
    $null = Invoke-Git @('config', 'commit.gpgsign', 'false')
    $aprilDir = New-ScratchReview -SlugSet 'first' -Range '2026-04-01_2026-04-30' -Summary
    $comboDir = New-ScratchReview -SlugSet 'first+second' -Range '2026-01-01_2026-03-31'
    $null = Invoke-Git @('add', '-A')
    $null = Invoke-Git @('commit', '-q', '-m', 'seed')

    # -- 1. Off means absent ---------------------------------------------------------
    Write-Host "-- Off: no verb ----------------------------------------" -ForegroundColor Cyan
    $off = Invoke-Verbs "'CMD=' + [bool](Get-Command tkWorkReview -ErrorAction SilentlyContinue); 'MAP=' + (Get-P20CommandMap)" -On $false
    Assert-True 'with growth off WorkReview does not exist' ($off -match 'CMD=False') $off
    Assert-True 'and the bridge has nothing to call' ($off -notmatch '"WorkReview"') $off
    $on = Invoke-Verbs "'MAP=' + (Get-P20CommandMap)"
    Assert-True 'with growth on the bridge table carries it' ($on -match '"WorkReview"\s*:\s*"Set-P20WorkReview"') $on

    # -- 2. Help ---------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -Help: the two moves --------------------------------" -ForegroundColor Cyan
    $out = Invoke-Verbs "tkWorkReview -Help; 'H=' + `$LASTEXITCODE"
    Assert-True '-Help prints both moves' ($out -match '-Archive' -and $out -match '-Delete' -and $out -match '-WhatIf') $out
    Assert-True '-Help names the review the way the row does' ($out -match '<slug-set>/<start>_<end>') $out

    # -- 3. -WhatIf ------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -WhatIf: names the folder, writes nothing -----------" -ForegroundColor Cyan
    $before = Get-TreeSnapshot
    $head = Invoke-Git @('rev-parse', 'HEAD')
    $out = Invoke-Verbs "tkWorkReview first/2026-04-01_2026-04-30 -Archive -WhatIf; 'W=' + `$LASTEXITCODE; tkWorkReview first+second/2026-01-01_2026-03-31 -Delete -WhatIf; 'D=' + `$LASTEXITCODE"
    Assert-True '-Archive -WhatIf names the folder and its destination' ($out -match 'reviews/first/2026/2026-04-01_2026-04-30/' -and $out -match 'reviews/archive/first/2026/2026-04-01_2026-04-30/' -and $out -match 'W=0') $out
    Assert-True '-Delete -WhatIf names the folder and its files' ($out -match 'remove reviews/first\+second/2026/2026-01-01_2026-03-31/' -and $out -match 'review\.md' -and $out -match 'D=0') $out
    Assert-True 'and nothing was written' ((Get-TreeSnapshot) -ceq $before) 'the tree changed'
    Assert-True 'and nothing was committed' ((Invoke-Git @('rev-parse', 'HEAD')) -eq $head) 'HEAD moved'

    # -- 4. -Archive -----------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -Archive: moved, stamped, committed -----------------" -ForegroundColor Cyan
    # Something else staged: the commit must leave it staged and out of it.
    [System.IO.File]::WriteAllText((Join-Path $hub 'first/current/other.md'), "# Other`n", $utf8)
    $null = Invoke-Git @('add', 'first/current/other.md')
    $summaryBytes = [System.IO.File]::ReadAllText((Join-Path $aprilDir 'summary.md'))
    $out = Invoke-Verbs "tkWorkReview first/2026-04-01_2026-04-30 -Archive; 'A=' + `$LASTEXITCODE"
    $archived = Join-Path $hub 'reviews/archive/first/2026/2026-04-01_2026-04-30'
    Assert-True 'Archive says what it did and exits 0' ($out -match 'Archived: reviews/first/2026/2026-04-01_2026-04-30/ -> reviews/archive/first/2026/2026-04-01_2026-04-30/' -and $out -match 'A=0') $out
    Assert-True 'the folder is gone from reviews/first/' (-not (Test-Path $aprilDir)) $aprilDir
    Assert-True 'and is under reviews/archive/, both files with it' ((Test-Path (Join-Path $archived 'review.md')) -and (Test-Path (Join-Path $archived 'summary.md'))) $archived
    $reviewText = [System.IO.File]::ReadAllText((Join-Path $archived 'review.md'))
    Assert-True 'review.md carries **Closed:** with the date' ($reviewText -match "(?m)^\*\*Closed:\*\* $(Get-Date -Format 'yyyy-MM-dd')$") $reviewText
    Assert-True 'review.md keeps its frontmatter and body' ($reviewText.StartsWith("---`norgs: [first]") -and $reviewText -match '\*\*Period:\*\*') $reviewText
    Assert-True 'review.md stays LF with no BOM' (-not $reviewText.Contains("`r`n") -and [System.IO.File]::ReadAllBytes((Join-Path $archived 'review.md'))[0] -ne 0xEF)
    Assert-True 'summary.md is moved untouched' ([System.IO.File]::ReadAllText((Join-Path $archived 'summary.md')) -ceq $summaryBytes)
    $log = Invoke-Git @('log', '-1', '--name-status', '--format=%s')
    Assert-True 'storeSync: git commits it, named' ($log -match '(?m)^review: archive first/2026-04-01_2026-04-30$') $log
    Assert-True 'the commit is the move' ($log -match 'reviews/archive/first/2026/2026-04-01_2026-04-30/review\.md' -and $log -match 'reviews/first/2026/2026-04-01_2026-04-30/review\.md') $log
    Assert-True 'and nothing else: what a person had staged stays staged, out of it' ($log -notmatch 'other\.md' -and (Invoke-Git @('diff', '--cached', '--name-only')) -match 'first/current/other\.md') $log
    $null = Invoke-Git @('reset', '-q', '--', 'first/current/other.md')

    $out = Invoke-Verbs "tkWorkReview first/2026-04-01_2026-04-30 -Archive; 'A2=' + `$LASTEXITCODE"
    Assert-True 'a second Archive is a report, not an error' ($out -match 'Already archived' -and $out -match 'A2=0') $out
    Assert-True 'and the stamp is not written twice' (@([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $archived 'review.md')), '\*\*Closed:\*\*')).Count -eq 1)

    # -- 5. -Delete ------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -Delete: removed, committed -------------------------" -ForegroundColor Cyan
    # The slug-set is a set: second+first names the same review.
    $out = Invoke-Verbs "tkWorkReview second+first/2026-01-01_2026-03-31 -Delete; 'D=' + `$LASTEXITCODE"
    Assert-True 'Delete says what it did and exits 0' ($out -match 'Deleted: reviews/first\+second/2026/2026-01-01_2026-03-31/' -and $out -match 'D=0') $out
    Assert-True 'the folder is gone' (-not (Test-Path $comboDir)) $comboDir
    $log = Invoke-Git @('log', '-1', '--name-status', '--format=%s')
    Assert-True 'storeSync: git commits the removal' ($log -match '(?m)^review: delete first\+second/2026-01-01_2026-03-31$' -and $log -match '(?m)^D\s+reviews/first\+second/2026/2026-01-01_2026-03-31/review\.md') $log

    $out = Invoke-Verbs "tkWorkReview archive/first/2026-04-01_2026-04-30 -Delete; 'DA=' + `$LASTEXITCODE"
    Assert-True 'an archived review is deleted by archive/<slug-set>/<range>' ($out -match 'DA=0' -and -not (Test-Path $archived)) $out
    $log = Invoke-Git @('log', '-1', '--format=%s')
    Assert-True 'and that removal is committed too' ($log -match '^review: delete archive/first/2026-04-01_2026-04-30$') $log
    Assert-True 'the working tree is clean afterwards' ([string]::IsNullOrWhiteSpace((Invoke-Git @('status', '--porcelain', '--', 'reviews')))) (Invoke-Git @('status', '--porcelain'))

    $fresh = New-ScratchReview -SlugSet 'second' -Range '2026-05-01_2026-05-31'
    $out = Invoke-Verbs "tkWorkReview second/2026-05-01_2026-05-31 -Delete; 'U=' + `$LASTEXITCODE"
    Assert-True 'a review never committed is deleted, with nothing to commit' ($out -match 'never committed' -and $out -match 'U=0' -and -not (Test-Path $fresh)) $out

    # -- 6. Refusals -----------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Refusals: stated, exit 2, one block -----------------" -ForegroundColor Cyan
    $null = New-ScratchReview -SlugSet 'first' -Range '2026-06-01_2026-06-30'
    $null = New-ScratchReview -SlugSet 'archive/first' -Range '2026-06-01_2026-06-30'
    $refusals = @(
        @{ Name = 'no move'; Snippet = 'tkWorkReview first/2026-06-01_2026-06-30'; Want = '-Archive or -Delete' }
        @{ Name = 'both moves'; Snippet = 'tkWorkReview first/2026-06-01_2026-06-30 -Archive -Delete'; Want = 'not both' }
        @{ Name = 'no review named'; Snippet = 'tkWorkReview -Archive'; Want = 'does not name a review' }
        @{ Name = 'a range that is not one'; Snippet = 'tkWorkReview first/2026-06 -Archive'; Want = 'does not name a review' }
        @{ Name = 'a path out of reviews/'; Snippet = 'tkWorkReview ../2026-06-01_2026-06-30 -Delete'; Want = 'does not name a review' }
        @{ Name = 'a review that is not there'; Snippet = 'tkWorkReview second/2026-06-01_2026-06-30 -Delete'; Want = 'no review second/2026-06-01_2026-06-30' }
        @{ Name = 'an archive that would overwrite one'; Snippet = 'tkWorkReview first/2026-06-01_2026-06-30 -Archive'; Want = 'nothing in the archive is overwritten' }
    )
    $before = Get-TreeSnapshot
    foreach ($r in $refusals) {
        $out = Invoke-Verbs "$($r.Snippet); 'X=' + `$LASTEXITCODE"
        Assert-True "refused: $($r.Name)" ($out -match [regex]::Escape($r.Want) -and $out -match 'X=2' -and (@([regex]::Matches($out, '(?m)^Error: ')).Count -eq 1) -and $out -notmatch 'exit code') $out
    }
    Assert-True 'a refusal wrote nothing' ((Get-TreeSnapshot) -ceq $before) 'the tree changed'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host ""
if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'WorkReview' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
