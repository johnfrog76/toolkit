<#
.SYNOPSIS
    Regression tests for New-PullRequest.ps1's Described Changes parser.
.DESCRIPTION
    Get-DescribedChanges reads the "## Described Changes" section out of a prompt
    file. Its output goes to TWO places other people read -- the pull request
    description and the ADO work item comment -- so a defect here is invisible
    locally and visible to everyone else.

    It had one. The parser kept only lines beginning with "-", so a bullet that
    soft-wrapped in the editor lost everything after its first line. On card 113
    that shipped "...asserting all eleven buttons" with "end disabled." dropped:
    a sentence that stops mid-clause, in the PR and on the card, with nothing
    failing anywhere. Found by reading the posted comment, not by any test.

    This suite extracts the function from the script's source text and evaluates
    it against synthetic sections, so it exercises the real parser without auth,
    network or git.

    Run:  pwsh -File Tests/Test-PullRequest.ps1
    Or:   tkTestToolkit -PullRequest
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Loads a function, or a block, out of the script under test by its source text, so it can be called alone.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = Split-Path $scriptDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/New-PullRequest.ps1'
if (-not (Test-Path $targetScript)) {
    Write-Error "New-PullRequest.ps1 not found at $targetScript"
    return
}

$sourceText = Get-Content -Path $targetScript -Raw
$funcMatch  = [regex]::Match($sourceText, '(?s)function Get-DescribedChanges \{.*?\n\}')
if (-not $funcMatch.Success) {
    Write-Error "Could not find function Get-DescribedChanges in $targetScript"
    return
}
Invoke-Expression $funcMatch.Value

if (-not (Get-Command Get-DescribedChanges -ErrorAction SilentlyContinue)) {
    Write-Error "Get-DescribedChanges did not load correctly"
    return
}

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Described Changes Parser Tests" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# -- The card 113 case: a bullet that wraps ----------------------------------

$wrapped = @'
## Described Changes
<!-- Up to 5 high-level bullets summarizing the PR. -->

- Pass `gameOver` into `ButtonList` so it knows when no further rolls are permitted.
- Add a regression test playing nine open frames plus an open 10th, asserting all eleven buttons
  end disabled.

## Diagnosis
This paragraph belongs to the next section and must not appear.
'@

$got = Get-DescribedChanges $wrapped
$lines = @($got -split "`n")

Assert-True "a wrapped bullet stays one bullet" ($lines.Count -eq 2) `
    "got $($lines.Count) lines"
Assert-True "the wrapped tail is kept, not dropped" ($got -match 'eleven buttons end disabled\.') `
    'the continuation line was discarded -- this is the card 113 truncation'
Assert-True "the next section is not swallowed" (-not ($got -match 'must not appear')) `
    'the parser ran past the ## boundary'
Assert-True "every line is still a bullet" (@($lines | Where-Object { $_ -notmatch '^- ' }).Count -eq 0) `
    'a continuation line leaked through as its own line'

# -- A lead-in paragraph before the bullets is not carried -------------------

$leadIn = @'
## Described Changes
This sentence introduces the list and is not a bullet.

- First real bullet.

## Next
'@

$got2 = Get-DescribedChanges $leadIn
Assert-True "a lead-in paragraph is not carried" (-not ($got2 -match 'introduces the list')) `
    'text before the first bullet was folded into it'
Assert-True "the bullet after a lead-in survives" ($got2 -match 'First real bullet\.')

# -- Heading suffix ----------------------------------------------------------

$suffix = @'
## Described Changes (as built)
- Only bullet.

## Next
'@
Assert-True "a heading suffix still matches" ((Get-DescribedChanges $suffix) -match 'Only bullet\.')

# -- Nothing to return -------------------------------------------------------

Assert-True "no section returns null" ($null -eq (Get-DescribedChanges "## Summary`nno such section"))
Assert-True "a section with no bullets returns null" `
    ($null -eq (Get-DescribedChanges "## Described Changes`njust prose, no bullets`n`n## Next"))

# -- Single-line bullets are untouched ---------------------------------------

$plain = @'
## Described Changes
- One.
- Two.
- Three.

## Next
'@
Assert-True "single-line bullets are unchanged" (@((Get-DescribedChanges $plain) -split "`n").Count -eq 3)

Write-Host ""

# -- Summary -----------------------------------------------------------------

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
