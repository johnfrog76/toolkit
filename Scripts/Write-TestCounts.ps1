<#
.SYNOPSIS
    The release step that writes docs/TEST-COUNTS.md from a full run's printed
    counts. Run beside Scripts/Fold-Changelog.ps1, in the release pull request.

.DESCRIPTION
    Not a verb -- no alias, no menu row, no bridge entry. A maintainer runs it
    once, by hand, in the release pull request, after consts.json's version is
    set.

    Why one machine-written file: the test counts used to be typed lines in
    AGENTS.md, VERIFY.md and docs/TESTING.md, and every pull request that added
    a test rewrote them, so any two such pull requests conflicted on the same
    lines and the second owed a fresh full run. Now no pull request states a
    count. docs/TEST-COUNTS.md is the one page that does, as of the version it
    names; it changes only with that version (CI refuses any other change to
    it, Scripts/Test-TestCountsChange.ps1), and the documents link to it.

    THE INPUT is what a full run prints: tkTest, every half and no -Fast, ends
    with

        Counts for docs/TEST-COUNTS.md, from this run:
        <the CLI per suite: Name N, Name N, ...>
        N suites, M assertions
        pytest: N passed, N skipped
        web: N suites, N tests

    Give it those four lines (the heading may come with them), or the whole
    transcript of the run: the block is read after the last heading. A pytest
    line's "(via <python>)" is information about the machine and is not kept.

    EVERYTHING IS CHECKED BEFORE ANYTHING IS WRITTEN (ConvertFrom-P20CountsBlock
    in Scripts/TestAll-Rules.ps1): four lines in their shapes, so a half that
    did not run or did not pass -- which prints a sentence in its line's place
    -- is refused; the total equal to the per-suite line's sum and its suite
    count to the suites it lists; the suites exactly the registry's
    (Tests/Get-ToolkitSuiteRegistry.ps1), in the runner's order, so a block from
    another tree is refused; and the version consts.json's. A refusal names
    every reason, writes nothing, and exits 2 (AGENTS.md, "The refusal
    contract").

    The page is written through Write-CardText -New: UTF-8 with no BOM, LF, the
    same bytes on every host. Its words are Format-P20TestCountsFile's, and
    {cliPrefix}TestToolkit -DocCounts holds the committed page to them and to
    consts.json's version.

.PARAMETER Path
    The file holding the block or the transcript. '-' reads standard input.
    Lines may also be piped in from PowerShell instead.

.PARAMETER Version
    The version the counts are as of. Defaults to consts.json's; any other is
    refused, because the release sets consts.json first.

.PARAMETER Root
    The folder that holds consts.json and docs/. Defaults to this package.
    Composition for the suite, which writes a scratch copy.

.PARAMETER WhatIf
    Print the page it would write. Writes nothing.

.EXAMPLE
    pwsh -NoProfile -File Scripts/Write-TestCounts.ps1 -Path run.log -WhatIf
.EXAMPLE
    pwsh -NoProfile -File Scripts/Write-TestCounts.ps1 -Path run.log
.EXAMPLE
    Get-Content block.txt | ./Scripts/Write-TestCounts.ps1

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path,
    [string]$Version,
    [string]$Root,
    [Parameter(ValueFromPipeline = $true)][AllowEmptyString()][string[]]$InputLine
)

begin {
    $ErrorActionPreference = 'Stop'
    $piped = New-Object System.Collections.ArrayList
}

process {
    foreach ($l in @($InputLine)) { if ($null -ne $l) { [void]$piped.Add([string]$l) } }
}

end {
    . (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
    . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
    . (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')
    . (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests') 'Get-ToolkitSuiteRegistry.ps1')

    if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
    $cf = Get-P20TestCountsFile
    $recipe = 'docs/TESTING.md, "The counts", has the step; AGENTS.md, "A release is a tag on main", has the release.'
    $refuse = {
        param([string]$Message, [string]$Hint)
        Write-CliError -Message $Message -Hint "$Hint Nothing was written. $recipe"
        exit 2  # a stated refusal (AGENTS.md, "The refusal contract")
    }

    # -- The block ---------------------------------------------------------------
    $text = ''
    if ($Path -eq '-') { $text = [Console]::In.ReadToEnd() }
    elseif ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            & $refuse "There is no file at $Path." 'Pass the file a full tkTest run''s output was saved to, or -Path - to read standard input.'
        }
        $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, (New-Object System.Text.UTF8Encoding($false)))
    }
    elseif ($piped.Count -gt 0) { $text = (@($piped) -join "`n") }
    else {
        & $refuse 'No counts were given.' 'Pass -Path <file> (or -Path - for standard input), or pipe the block in.'
    }

    # -- The version ---------------------------------------------------------------
    $constsPath = Join-Path $Root 'consts.json'
    $constsVersion = ''
    if (Test-Path -LiteralPath $constsPath -PathType Leaf) {
        try { $constsVersion = [string](([System.IO.File]::ReadAllText($constsPath) | ConvertFrom-Json).version) }
        catch { $constsVersion = '' }
    }
    if (-not $constsVersion) {
        & $refuse "consts.json in $Root has no version to write the counts as of." 'The release sets consts.json''s version first.'
    }
    if ($Version -and ($Version -cne $constsVersion)) {
        & $refuse "-Version is $Version and consts.json says $($constsVersion)." 'Set the version in consts.json (and the two other places that state it) first, then run this with no -Version.'
    }

    # -- Every reason the block is not a full run's of this tree ------------------
    $block = ConvertFrom-P20CountsBlock -Text $text
    $problems = @($block.Findings)
    if ($problems.Count -eq 0) {
        $names = @($block.Suites | ForEach-Object { $_[0] })
        $registry = @((Get-P20ToolkitSuiteRegistry).Keys)
        if (($names -join ', ') -cne ($registry -join ', ')) {
            $problems += "the per-suite line names $($names.Count) suite(s) and the registry has $($registry.Count): the suites must be the registry's, in the runner's order (a block from another tree, or from a run that did not run every suite)"
        }
    }
    if ($problems.Count -gt 0) {
        & $refuse "These are not a full run's counts: $($problems -join '; ')." 'Write from the block a full tkTest run printed on this tree -- every half, no -Fast, every suite passing.'
    }

    # -- The page --------------------------------------------------------------------
    $newText = Format-P20TestCountsFile -Lines @($block.Lines) -Version $constsVersion
    $target = Join-Path $Root ($cf.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $summary = "as of $constsVersion -- $($block.Lines[1]); $($block.Lines[2]); $($block.Lines[3])"

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $old = [System.IO.File]::ReadAllText($target, (New-Object System.Text.UTF8Encoding($false)))
        if ($old -ceq $newText) {
            Write-Host "$($cf.Path) already says this ($summary). Nothing was written."
            exit 0
        }
    }

    if (-not $PSCmdlet.ShouldProcess($cf.Path, "write the counts $summary")) {
        Write-Host ""
        Write-Host "The page $($cf.Path) would hold:"
        Write-Host ""
        foreach ($l in @($newText.TrimEnd("`n") -split "`n")) { Write-Host $l }
        exit 0
    }

    $folder = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    Write-CardText -Path $target -Content $newText -New
    Write-Host "Wrote $($cf.Path): $summary."
    exit 0
}
