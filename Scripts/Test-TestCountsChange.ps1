<#
.SYNOPSIS
    CI's check that docs/TEST-COUNTS.md changes only with the version. Not a verb.

.DESCRIPTION
    The counts file is written in the release pull request, by
    Scripts/Write-TestCounts.ps1 from a full run's block, and that pull request
    sets consts.json's version beside it. Any other pull request leaves it as it
    is: a count typed in between releases is the conflict the file exists to
    end. .github/workflows/verify.yml's changes job lists the files a pull
    request changed, writes consts.json as it stood at the base, and calls this:

        git diff --name-only --no-renames "$BASE...HEAD" > changed.txt
        git show "$from:consts.json" > base-consts.json
        pwsh -NoProfile -File Scripts/Test-TestCountsChange.ps1 -PathsFile changed.txt -BaseConstsPath base-consts.json

    The rule is Get-P20TestCountsChangeFindings (Scripts/TestAll-Rules.ps1): a
    change that touches docs/TEST-COUNTS.md -- edits or deletes it -- and leaves
    consts.json's `version` as the base had it is refused, unless the page did
    not exist at the base (-BaseHadPage false: it is being introduced; the step
    asks git cat-file -e). -HeadConstsPath is the change's consts.json (this
    package's, by default).

    Exit 0 when the counts file is untouched or the version moved with it; 2,
    after an Error: line naming the release step, when it changed alone, or
    when a file it needs is missing.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PathsFile,
    [Parameter(Mandatory)][string]$BaseConstsPath,
    [string]$HeadConstsPath,
    [ValidateSet('true', 'false')][string]$BaseHadPage = 'true'
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
. (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')

$cf = Get-P20TestCountsFile
if (-not $HeadConstsPath) { $HeadConstsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'consts.json' }

if (-not (Test-Path -LiteralPath $PathsFile -PathType Leaf)) {
    Write-CliError -Message "There is no list of changed files at $PathsFile." -Hint 'The step writes it with git diff --name-only before calling this (docs/TESTING.md, "In CI").'
    exit 2
}
$paths = @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $PathsFile).Path))
$touched = (@($paths | ForEach-Object { ([string]$_).Trim() -replace '\\', '/' }) -ccontains $cf.Path)

Write-Host ''
if (-not $touched) {
    Write-Host "  The counts file: $($cf.Path) is not changed"
    exit 0
}
if ($BaseHadPage -eq 'false') {
    Write-Host "  The counts file: $($cf.Path) is introduced by this change (the base has none)"
    exit 0
}

$readVersion = {
    param([string]$File)
    if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return '' }
    try { return [string](([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path) | ConvertFrom-Json).version) }
    catch { return '' }
}
$baseVersion = & $readVersion $BaseConstsPath
$headVersion = & $readVersion $HeadConstsPath
if (-not $baseVersion -or -not $headVersion) {
    Write-CliError -Message "$($cf.Path) changed and consts.json's version could not be read at the base ('$baseVersion') or the head ('$headVersion')." -Hint 'The step writes the base''s consts.json with git show before calling this (docs/TESTING.md, "In CI").'
    exit 2
}

$findings = @(Get-P20TestCountsChangeFindings -Paths $paths -BaseVersion $baseVersion -HeadVersion $headVersion)
if ($findings.Count -eq 0) {
    Write-Host "  The counts file: $($cf.Path) changed with the version, $baseVersion to $headVersion"
    exit 0
}
foreach ($f in $findings) {
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error title=The counts file changed without a release::$f" }
}
Write-CliError -Message "$($findings -join '; ')." -Hint "Put $($cf.Path) back as the base has it. A count is never typed: the next release writes it from a full run (docs/TESTING.md, ""The counts"")."
exit 2
