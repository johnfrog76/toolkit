<#
.SYNOPSIS
    A folder inside someone else's repository is not a checkout of its own.
.DESCRIPTION
    `git rev-parse --is-inside-work-tree` searches UPWARD, so every verb that
    used it accepted a plain folder sitting anywhere under another repository
    and then ran git against THAT repository: `Update` would fast-forward it and
    `Sync` would `git add -A`, commit and push it.

    Two questions, because the verbs do not all ask the same one:

      Test-P20GitRoot        is this folder the top level?  -- what a WRITER asks
      Test-P20GitTracksPath  does the repo track anything here? -- what a READER asks

    Backfill is the reader. A hub that is a tracked SUBFOLDER of its own
    repository is deliberately supported there, so the root check would have
    regressed it; what disqualifies a folder is a repository that knows nothing
    about it.

    The end-to-end half builds a real enclosing repository in a temp folder,
    puts a Toolkit copy and a hub inside it, and asserts each verb refuses AND
    that the enclosing repository's HEAD and working tree are untouched
    afterwards. There is no remote anywhere in this file, and nothing here runs
    against the real hub or the real checkout: the defect IS a verb writing to
    a repository nobody pointed it at, so a careless test run would be the bug.

    GIT_CEILING_DIRECTORIES stops git searching above the sandbox, so a stray
    `git init` somewhere above %TEMP% -- which is exactly how this was found on
    Windows -- cannot turn a scratch folder into a checkout and quietly change
    what these assertions mean.

    Run:  pwsh -File Tests/Test-GitRoot.ps1
    Or:   tkTestToolkit -GitRoot
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = Split-Path $scriptDir -Parent
$helper    = Join-Path $pkgRoot 'Scripts/Test-GitRoot.ps1'
if (-not (Test-Path $helper)) { Write-Error "Test-GitRoot.ps1 not found at $helper"; return }
. $helper

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:passed++; Write-Host "  PASS  $TestName" -ForegroundColor Green }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  SKIP  git is not installed -- a skip is not a pass." -ForegroundColor Yellow
    return
}

# -- A disposable enclosing repository -----------------------------------------

$base     = Join-Path ([System.IO.Path]::GetTempPath()) "p20-gitroot-$([guid]::NewGuid())"
$outer    = Join-Path $base 'outer-repo'
$innerPkg = Join-Path $outer 'toolkit-copy'
$innerHub = Join-Path $outer 'hub-folder'
$ownRepo  = Join-Path $base 'own-repo'
$trackedSub = Join-Path $outer 'tracked-hub'

$savedCeiling = $env:GIT_CEILING_DIRECTORIES
$env:GIT_CEILING_DIRECTORIES = ([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')

try {
    foreach ($d in @($innerPkg, $innerHub, $ownRepo, $trackedSub)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    git -C $outer init -q 2>$null
    Set-Content -LiteralPath (Join-Path $outer 'readme.md') -Value 'outer' -Encoding utf8
    # A TRACKED subfolder, so the reader's question has a true case to answer.
    Set-Content -LiteralPath (Join-Path $trackedSub 'card.md') -Value '# card' -Encoding utf8
    git -C $outer add -A 2>$null | Out-Null
    git -C $outer -c user.email=t@t -c user.name=t commit -qm 'outer' 2>$null | Out-Null
    git -C $ownRepo init -q 2>$null

    $headBefore  = (git -C $outer rev-parse HEAD 2>$null)
    # TRACKED changes only. This test copies a Toolkit into the repository on
    # purpose, so untracked files are its own scaffolding; what must not move is
    # anything the repository is actually keeping.
    $dirtyBefore = (git -C $outer status --porcelain --untracked-files=no 2>$null | Out-String)

    Write-Host ""
    Write-Host "-- the two questions ------------------------------------" -ForegroundColor Cyan

    Assert-True 'a plain folder inside another repository is NOT its root' `
        (-not (Test-P20GitRoot -Path $innerHub))
    Assert-True 'a repository root IS its root' (Test-P20GitRoot -Path $ownRepo)
    Assert-True 'the enclosing repository is its own root' (Test-P20GitRoot -Path $outer)
    Assert-True 'a folder in no repository at all is not a root' `
        (-not (Test-P20GitRoot -Path $base))

    Assert-True 'an untracked folder under a repository has no history to read' `
        (-not (Test-P20GitTracksPath -Path $innerHub))
    Assert-True 'a TRACKED subfolder does have history -- the reader keeps working' `
        (Test-P20GitTracksPath -Path $trackedSub)

    $hint = Get-P20EnclosingRepoHint -Path $innerHub -Subject 'hub'
    Assert-True 'the hint names the repository that was found instead' `
        ($hint -like '*outer-repo*') $hint
    Assert-True 'and a real root gets no enclosing-repository hint' `
        ([string]::IsNullOrEmpty((Get-P20EnclosingRepoHint -Path $ownRepo -Subject 'hub')))

    Write-Host ""
    Write-Host "-- the same folder, spelled differently -----------------" -ForegroundColor Cyan
    # Windows hands the same folder back several ways and git always prints a
    # forward-slashed long path. Comparing raw strings refuses a real checkout
    # for how it was typed.
    Assert-True 'forward slashes'      (Test-P20GitRoot -Path ($ownRepo -replace '\\', '/'))
    Assert-True 'a trailing separator' (Test-P20GitRoot -Path ($ownRepo + [IO.Path]::DirectorySeparatorChar))
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        Assert-True 'a different case' (Test-P20GitRoot -Path $ownRepo.ToUpper())
        $sig = '[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern uint GetShortPathName(string l, System.Text.StringBuilder s, uint c);'
        $k = Add-Type -MemberDefinition $sig -Name K -Namespace P20GitRootTest -PassThru
        $sb = New-Object System.Text.StringBuilder 400
        [void]$k::GetShortPathName($ownRepo, $sb, 400)
        $short = $sb.ToString()
        Assert-True 'the 8.3 short form of the same root (Windows only)' `
            ($short -and (Test-P20GitRoot -Path $short)) $short
    }
    else {
        Write-Host "  SKIP  8.3 short paths and case-insensitivity are Windows-only" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "-- the verbs refuse, and change nothing -----------------" -ForegroundColor Cyan

    # Update, against a Toolkit COPY inside the enclosing repository. Run as a
    # child pwsh so the refusal and the exit code are the real ones.
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $innerPkg 'Scripts') -Recurse -Force
    $updateScript = Join-Path $innerPkg 'Scripts/Update-Toolkit.ps1'
    $r = & pwsh -NoProfile -Command "`$env:GIT_CEILING_DIRECTORIES='$($env:GIT_CEILING_DIRECTORIES -replace "'","''")'; & '$($updateScript -replace "'","''")' 2>&1 | Out-String; exit `$LASTEXITCODE" 2>&1
    $updateOut = ($r | Out-String)
    Assert-True 'Update refuses a Toolkit copy inside another repository' `
        ($updateOut -match 'not a git checkout') $updateOut
    Assert-True 'and its hint names the enclosing repository' `
        ($updateOut -match 'outer-repo') $updateOut
    Assert-True 'and git stderr never reaches the message as a branch name' `
        ($updateOut -notmatch 'ambiguous argument') $updateOut

    $headAfter  = (git -C $outer rev-parse HEAD 2>$null)
    $dirtyAfter = (git -C $outer status --porcelain --untracked-files=no 2>$null | Out-String)
    Assert-True "the enclosing repository's HEAD is unchanged" ($headBefore -eq $headAfter) "$headBefore -> $headAfter"
    Assert-True "no tracked file in the enclosing repository moved" ($dirtyBefore -eq $dirtyAfter) "[$dirtyBefore] -> [$dirtyAfter]"
    Assert-True 'and nothing was staged there' `
        (0 -eq @(git -C $outer diff --cached --name-only 2>$null | Where-Object { $_ }).Count)
    Assert-True 'and it grew no commits' `
        (1 -eq [int](git -C $outer rev-list --count HEAD 2>$null))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if ($null -eq $savedCeiling) { Remove-Item Env:GIT_CEILING_DIRECTORIES -ErrorAction SilentlyContinue }
    else { $env:GIT_CEILING_DIRECTORIES = $savedCeiling }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

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
