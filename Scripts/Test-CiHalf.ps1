<#
.SYNOPSIS
    CI's verdict on one half's run, or the browser smoke's. Not a verb.

.DESCRIPTION
    .github/workflows/verify.yml runs each half's runner with its output teed to
    a transcript, then calls this with the transcript and the runner's exit code:

        python -m pytest Tests/ 2>&1 | tee agent.log
        pwsh -NoProfile -File Scripts/Test-CiHalf.ps1 -Half agent -Path agent.log -ExitCode <code>

    -Half smoke reads a browser smoke's transcript (npm run smoke -- --matrix,
    --a11y) by its closing `smoke:` line, the same way.

    The verdict is Get-P20CiHalfVerdict (Scripts/TestAll-Rules.ps1): the parser
    and the rule {cliPrefix}Test reads each half with, and one rule tighter -- a
    half with no summary line, a failure, a non-zero exit, or nothing passed
    (a 0/0, every test skipped) fails the step. A runner's exit code alone is
    not trusted: a run that stopped before it reported, or counted nothing, can
    still exit 0.

    It prints the half's summary line and the verdict. Under GitHub Actions
    (GITHUB_ACTIONS is true) a failure is also an ::error:: annotation, a
    self-skipped test or suite a ::warning::, and one line goes into the job's
    step summary.

    Exit 0 when the half passed; 2, after an Error: line, when it did not.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('cli', 'agent', 'web', 'smoke')][string]$Half,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][int]$ExitCode
)

. (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')

$onActions = ($env:GITHUB_ACTIONS -eq 'true')
$v = @{ Result = 'fail'; Detail = "no transcript at $Path"; Line = ''; Passed = 0; Failed = 0; Skipped = 0; Total = 0 }
if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    $v = Get-P20CiHalfVerdict -Half $Half -Text $text -ExitCode $ExitCode
}

$line = $v.Line
if (-not $line) { $line = '(no summary line)' }
$label = $v.Result.ToUpperInvariant()

Write-Host ''
Write-Host "  CI verdict, the $Half half: $label"
Write-Host "    summary line: $line"
Write-Host "    exit code:    $ExitCode"
Write-Host "    counted:      $($v.Passed) passed, $($v.Failed) failed, $($v.Skipped) skipped"
if ($v.Result -ne 'pass') { Write-Host "    why:          $($v.Detail)" }

if ($onActions) {
    if ($v.Result -ne 'pass') {
        Write-Host "::error title=The $Half half did not pass::$($v.Detail) -- $line"
    }
    elseif ($v.Skipped -gt 0) {
        $what = 'test(s)'
        if ($Half -eq 'cli') { $what = 'suite(s), Results: 0/0' }
        Write-Host "::warning title=The $Half half skipped some::$($v.Skipped) $what skipped themselves -- $line"
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $row = "- **$Half** $label -- ``$line`` (exit $ExitCode)"
        if ($v.Result -ne 'pass') { $row += " -- $($v.Detail)" }
        try {
            [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $row + "`n", (New-Object System.Text.UTF8Encoding($false)))
        }
        catch { Write-Warning "Could not write the step summary: $_" }
    }
}

if ($v.Result -ne 'pass') {
    Write-Host ''
    Write-Host "Error: the $Half half did not pass in CI: $($v.Detail)."
    Write-Host "Hint:  the runner's own output is above; a skip or a 0/0 is not a pass (docs/TESTING.md, `"In CI`")."
    exit 2
}
exit 0
