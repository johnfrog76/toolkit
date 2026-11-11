<#
.SYNOPSIS
    Which of CI's Ubuntu jobs a run needs, from the files it changed. Not a verb.

.DESCRIPTION
    .github/workflows/verify.yml's `changes` job lists the files a pull request
    changed and calls this with the list:

        git diff --name-only --no-renames "$BASE...HEAD" > changed.txt
        git diff -U0 --no-renames "$BASE...HEAD" -- docs/TESTING.md AGENTS.md VERIFY.md > counts.diff
        # and each of those three files as it stood at the base, under base/
        pwsh -NoProfile -File Scripts/Get-CiScope.ps1 -Event pull_request -PathsFile changed.txt `
            -CountDiffFile counts.diff -BaseRoot base

    The rule is Get-P20CiScope (Scripts/TestAll-Rules.ps1): every event but a
    pull request runs the three halves; a pull request runs the half each path
    can affect -- web/ the web job; changelog.d/, CHANGELOG.md,
    docs/modules/*.md, docs/SCENARIOS.md and docs/KNOWN-GAPS.md no half, only
    the contract job; a shared path or one the rule does not know all three --
    and the contract job wherever a half is left out.

    -CountDiffFile is the -U0 diff of docs/TESTING.md, AGENTS.md and VERIFY.md,
    -BaseRoot a folder holding those files as they stood at the base, and
    -HeadRoot the tree after (the checkout, by default). A file whose changed
    lines are all count lines -- the lines {cliPrefix}TestToolkit -DocCounts
    checks (Get-P20CountOnlyPaths) -- reaches no half by itself.

    It prints one line per job and one per path with its class. Under GitHub
    Actions it writes `cli`, `agent`, `web` and `contract` (true or false) to
    GITHUB_OUTPUT, and the same lines to the job's step summary.

    Exit 0 with the answer; 2, after an Error: line, when -PathsFile or
    -CountDiffFile names no file.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Event,
    [string]$PathsFile,
    [string[]]$Paths = @(),
    [string]$CountDiffFile,
    [string]$BaseRoot,
    [string]$HeadRoot = '.'
)

. (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')

$all = @($Paths)
if ($PathsFile) {
    if (-not (Test-Path -LiteralPath $PathsFile -PathType Leaf)) {
        Write-Host "Error: no list of changed files at $PathsFile."
        Write-Host "Hint:  the step writes it with git diff --name-only before calling this (docs/TESTING.md, `"In CI`")."
        exit 2
    }
    $all += @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $PathsFile).Path))
}

$countOnly = @()
if ($CountDiffFile) {
    if (-not (Test-Path -LiteralPath $CountDiffFile -PathType Leaf)) {
        Write-Host "Error: no diff of the count-line files at $CountDiffFile."
        Write-Host "Hint:  the step writes it with git diff -U0 before calling this (docs/TESTING.md, `"In CI`")."
        exit 2
    }
    $diff = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $CountDiffFile).Path)
    $baseTexts = @{}
    $headTexts = @{}
    foreach ($f in @((Get-P20CountLineRules).Keys)) {
        foreach ($pair in @(@($baseTexts, $BaseRoot), @($headTexts, $HeadRoot))) {
            $pair[0][$f] = ''
            if (-not $pair[1]) { continue }
            $full = Join-Path $pair[1] $f
            if (Test-Path -LiteralPath $full -PathType Leaf) { $pair[0][$f] = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $full).Path) }
        }
    }
    $changes = Get-P20CountOnlyPaths -Diff $diff -BaseTexts $baseTexts -HeadTexts $headTexts
    foreach ($k in $changes.Keys) {
        if ($changes[$k].CountOnly) { $countOnly += $k }
        else { Write-Host "  $k changes more than its count lines -- $($changes[$k].Other)" }
    }
}

$scope = Get-P20CiScope -Event $Event -Paths $all -CountOnly $countOnly
$jobs = @('cli', 'agent', 'web', 'contract')

$report = @()
foreach ($j in $jobs) {
    $word = 'skip'
    if ($scope[$j]) { $word = 'run' }
    $report += "$j`: $word"
}
$pathRows = @($scope.Paths)
if ($Event -ne 'pull_request') { $report += "a $Event runs every half" }
elseif ($pathRows.Count -eq 0) { $report += 'no changed file was listed, so every half runs' }
else {
    $shown = 0
    foreach ($r in $pathRows) {
        if ($shown -ge 200) { $report += "... and $($pathRows.Count - $shown) more"; break }
        $report += "  $($r[1]): $($r[0])"
        $shown++
    }
}

Write-Host ''
Write-Host "  CI scope, a $Event"
foreach ($l in $report) { Write-Host "    $l" }

if ($env:GITHUB_ACTIONS -eq 'true') {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    if ($env:GITHUB_OUTPUT) {
        $lines = @()
        foreach ($j in $jobs) { $lines += "$j=$(([string]$scope[$j]).ToLowerInvariant())" }
        [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, (($lines -join "`n") + "`n"), $utf8)
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $md = @('**Which jobs this run needs**', '')
        foreach ($l in $report) { $md += "- ``$($l.Trim())``" }
        try { [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (($md -join "`n") + "`n"), $utf8) }
        catch { Write-Warning "Could not write the step summary: $_" }
    }
}
exit 0
