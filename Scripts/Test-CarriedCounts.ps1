<#
.SYNOPSIS
    CI's check that a pull request carried, and did not type, the paste lines of
    the halves it did not run. Not a verb.

.DESCRIPTION
    A pull request that runs one half pastes that half's line from its own run
    and carries the other halves' lines from main, which it could not have
    moved. .github/workflows/verify.yml's contract job writes main's
    docs/TESTING.md to a file and calls this with it, the change's copy and the
    halves that ran:

        git show "$BASE:docs/TESTING.md" > base-TESTING.md
        pwsh -NoProfile -File Scripts/Test-CarriedCounts.ps1 -BasePath base-TESTING.md -HeadPath docs/TESTING.md -Ran web

    The rule is Get-P20CarriedCountFindings (Scripts/TestAll-Rules.ps1): the
    paste-block lines of each half NOT in -Ran must be main's, line for line,
    and the block is read by Get-P20PasteBlock, the rule
    {cliPrefix}TestToolkit -DocCounts reads it with. -Ran takes the halves as
    separate values or one comma-separated string (cli,agent,web).

    Exit 0 when every carried line is main's; 2, after an Error: line naming
    each line that is not, when one differs or a file is missing.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string]$HeadPath,
    [string[]]$Ran = @()
)

. (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')

$halves = @(Get-P20TestHalves)
$ranList = @()
foreach ($r in @($Ran)) {
    foreach ($part in ([string]$r -split ',')) {
        $p = $part.Trim()
        if (-not $p) { continue }
        if ($halves -notcontains $p) {
            Write-Host "Error: '$p' is not a half."
            Write-Host "Hint:  -Ran takes $($halves -join ', ')."
            exit 2
        }
        $ranList += $p
    }
}

$texts = @{}
foreach ($pair in @(@('base', $BasePath), @('head', $HeadPath))) {
    if (-not (Test-Path -LiteralPath $pair[1] -PathType Leaf)) {
        Write-Host "Error: no docs/TESTING.md at $($pair[1])."
        Write-Host "Hint:  -BasePath is main's copy (git show), -HeadPath the change's."
        exit 2
    }
    $texts[$pair[0]] = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $pair[1]).Path)
}

$carried = @($halves | Where-Object { $ranList -notcontains $_ })
$findings = @(Get-P20CarriedCountFindings -BaseText $texts.base -HeadText $texts.head -Ran $ranList)

Write-Host ''
$ranWord = '(none)'
if ($ranList.Count -gt 0) { $ranWord = $ranList -join ', ' }
$carriedWord = '(none)'
if ($carried.Count -gt 0) { $carriedWord = $carried -join ', ' }
Write-Host "  Carried paste lines: ran $ranWord; carried from main $carriedWord"
if ($findings.Count -eq 0) {
    Write-Host '    every carried line is main''s'
    exit 0
}
foreach ($f in $findings) {
    Write-Host "    $f"
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error title=A carried paste line is not main's::$f" }
}
Write-Host ''
Write-Host "Error: docs/TESTING.md's paste block changes a line for a half this pull request did not run."
Write-Host "Hint:  put main's line back; a count is pasted from a run of its own half, never typed (docs/TESTING.md, `"In CI`")."
exit 2
