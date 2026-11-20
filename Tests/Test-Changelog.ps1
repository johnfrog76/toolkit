<#
.SYNOPSIS
    Tests for Scripts/Fold-Changelog.ps1 -- the release step that folds the
    entries waiting in changelog.d/ into CHANGELOG.md's ## [Unreleased].

.DESCRIPTION
    Every case folds a scratch copy built from Tests/fixtures/changelog/, never
    the package's own CHANGELOG.md: the fixture changelog with entries written by
    hand under two headings, the same with an empty ## [Unreleased] (the shape
    right after a release), and one fragment of each kind beside the folder's
    README. The result is compared byte for byte with expected.md and
    expected-empty.md.

    What it holds: mixed kinds land under their headings in Keep a Changelog
    order, a missing heading is added in its place, entries already there stay
    first, files fold in name order; the result is UTF-8 with no BOM and LF
    whatever the input was; the folded files are deleted and README.md is never
    an entry; an empty folder, or none, folds nothing and writes nothing; a
    second fold changes nothing; every malformed fragment -- an unknown kind, a
    name not <id>.<kind>.md, an empty file, a heading, a first line that is not
    an entry -- refuses the whole fold with exit 2 naming the file, writing and
    deleting nothing, and a child pwsh sees the same exit code; -WhatIf and
    -Check write nothing; a changelog with no ## [Unreleased] is refused.

    Then the two ends it has to keep working with: release.yml's own awk reader,
    lifted out of the workflow and run over the folded result after the release
    rename, finds the version's section; and release.yml's guard against an
    unfolded entry, run in a scratch folder, passes on a folder holding only its
    README and fails on one with an entry. Each is skipped by name where the host
    has no awk or no bash. Last, -Check over the committed tree, so a fragment in
    the wrong shape fails the pull request that adds it.

    Run:  pwsh -File Tests/Test-Changelog.ps1
    Or:   {cliPrefix}TestToolkit -Changelog

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
param()

$pkgRoot = Split-Path -Parent $PSScriptRoot
$foldScript = Join-Path (Join-Path $pkgRoot 'Scripts') 'Fold-Changelog.ps1'
$fixtureDir = Join-Path (Join-Path $PSScriptRoot 'fixtures') 'changelog'
$utf8 = New-Object System.Text.UTF8Encoding($false)

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

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    Assert-True $TestName ("$Expected" -ceq "$Actual") "expected [$Expected] got [$Actual]"
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Changelog -- the fold of changelog.d/ into CHANGELOG.md" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# A scratch root: CHANGELOG.md from the named fixture, and changelog.d/ holding
# the named fragments (by fixture name) plus any extra files given as name -> text.
function New-FoldScratch {
    param([string]$Changelog = 'CHANGELOG.md', [string[]]$Fragments = @(), [hashtable]$Extra = @{}, [switch]$NoFolder)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('p20-changelog-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    if ($Changelog) { Copy-Item -LiteralPath (Join-Path $fixtureDir $Changelog) -Destination (Join-Path $root 'CHANGELOG.md') }
    if (-not $NoFolder) {
        $dir = Join-Path $root 'changelog.d'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($f in $Fragments) { Copy-Item -LiteralPath (Join-Path (Join-Path $fixtureDir 'fragments') $f) -Destination (Join-Path $dir $f) }
        foreach ($k in $Extra.Keys) { [System.IO.File]::WriteAllText((Join-Path $dir $k), $Extra[$k], $utf8) }
    }
    $script:scratch += $root
    return $root
}

function Invoke-Fold {
    param([string]$Root, [hashtable]$With = @{})
    $global:LASTEXITCODE = 0
    $out = (& $foldScript -Root $Root @With *>&1 | Out-String)
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $out }
}

function Get-Bytes { param([string]$Path) return [System.IO.File]::ReadAllBytes($Path) }
function Get-Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path, $utf8) }
function Get-FolderNames {
    param([string]$Root)
    $d = Join-Path $Root 'changelog.d'
    if (-not (Test-Path -LiteralPath $d)) { return '' }
    $n = [string[]]@(Get-ChildItem -LiteralPath $d -File -Force | ForEach-Object { $_.Name })
    [array]::Sort($n, [System.StringComparer]::Ordinal)
    return ($n -join ',')
}
function Test-NoBomLf {
    param([byte[]]$Bytes)
    $bom = ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    return ((-not $bom) -and ($Bytes -notcontains 13))
}

$allFragments = @('README.md', 'A1.added.md', 'B0.added.md', 'B2.fixed.md', 'C3.changed.md', 'D4.removed.md')
$script:scratch = @()

try {
    Assert-True 'Scripts/Fold-Changelog.ps1 exists' (Test-Path -LiteralPath $foldScript)

    # -- Mixed kinds, into a section that already has entries ----------------------
    Write-Host ""
    Write-Host "-- Mixed kinds ----------------------------------------" -ForegroundColor Cyan
    $r = New-FoldScratch -Fragments $allFragments
    $run = Invoke-Fold -Root $r
    Assert-Equal 'mixed kinds: exit 0' 0 $run.Exit
    $expected = Get-Text (Join-Path $fixtureDir 'expected.md')
    $got = Get-Text (Join-Path $r 'CHANGELOG.md')
    Assert-True 'mixed kinds: CHANGELOG.md is expected.md byte for byte (hand entries first, a missing heading in its place, name order)' ($got -ceq $expected) $got
    Assert-True 'mixed kinds: UTF-8 with no BOM, LF only' (Test-NoBomLf (Get-Bytes (Join-Path $r 'CHANGELOG.md')))
    Assert-Equal 'mixed kinds: every folded file is deleted and README.md stays' 'README.md' (Get-FolderNames $r)
    Assert-True 'mixed kinds: README.md is never an entry' ($got -notmatch 'never an entry')
    Assert-True 'mixed kinds: the report counts each heading' ($run.Output -match 'Added 2, Changed 2, Removed 1, Fixed 1') $run.Output

    $before = Get-Bytes (Join-Path $r 'CHANGELOG.md')
    $again = Invoke-Fold -Root $r
    Assert-Equal 'a second fold: exit 0' 0 $again.Exit
    Assert-True 'a second fold: nothing to fold, and says so' ($again.Output -match 'Nothing to fold') $again.Output
    Assert-True 'a second fold: CHANGELOG.md keeps its bytes' ([System.Convert]::ToBase64String($before) -eq [System.Convert]::ToBase64String((Get-Bytes (Join-Path $r 'CHANGELOG.md'))))

    # -- An empty ## [Unreleased], the shape right after a release ----------------
    $r = New-FoldScratch -Changelog 'CHANGELOG-empty.md' -Fragments $allFragments
    $run = Invoke-Fold -Root $r
    Assert-Equal 'an empty [Unreleased]: exit 0' 0 $run.Exit
    $got = Get-Text (Join-Path $r 'CHANGELOG.md')
    Assert-True 'an empty [Unreleased]: every heading added in Keep a Changelog order (expected-empty.md byte for byte)' ($got -ceq (Get-Text (Join-Path $fixtureDir 'expected-empty.md'))) $got

    # -- The bytes, whatever the input was ------------------------------------------
    $r = New-FoldScratch -Changelog '' -Extra @{ 'E5.fixed.md' = ([char]0xFEFF + "- Fixed by E5, with a BOM and CRLF.`r`n") }
    $crlf = ((Get-Text (Join-Path $fixtureDir 'CHANGELOG.md')) -replace "`n", "`r`n")
    [System.IO.File]::WriteAllText((Join-Path $r 'CHANGELOG.md'), $crlf, (New-Object System.Text.UTF8Encoding($true)))
    $run = Invoke-Fold -Root $r
    Assert-Equal 'a CRLF changelog with a BOM, and a BOM CRLF fragment: exit 0' 0 $run.Exit
    $bytes = Get-Bytes (Join-Path $r 'CHANGELOG.md')
    Assert-True 'the result is UTF-8 with no BOM, LF only' (Test-NoBomLf $bytes)
    Assert-True 'the BOM fragment folds as its text' ((Get-Text (Join-Path $r 'CHANGELOG.md')) -match '(?m)^- A fix written by hand\.\n- Fixed by E5, with a BOM and CRLF\.\n\n## \[1\.0\.0\]')

    # -- Nothing to fold ----------------------------------------------------------
    Write-Host ""
    Write-Host "-- Nothing to fold ------------------------------------" -ForegroundColor Cyan
    foreach ($case in @(
            @{ Label = 'a folder holding only README.md'; Args = @{ Fragments = @('README.md') } },
            @{ Label = 'an empty folder'; Args = @{} },
            @{ Label = 'no changelog.d/ at all'; Args = @{ NoFolder = $true } },
            @{ Label = 'a folder holding only a file the system made'; Args = @{ Fragments = @('README.md'); Extra = @{ '.DS_Store' = 'x' } } })) {
        $a = $case.Args
        $r = New-FoldScratch @a
        $before = Get-Bytes (Join-Path $r 'CHANGELOG.md')
        $names = Get-FolderNames $r
        $run = Invoke-Fold -Root $r
        Assert-Equal "$($case.Label): exit 0" 0 $run.Exit
        Assert-True "$($case.Label): says there is nothing to fold" ($run.Output -match 'Nothing to fold') $run.Output
        Assert-True "$($case.Label): CHANGELOG.md keeps its bytes" ([System.Convert]::ToBase64String($before) -eq [System.Convert]::ToBase64String((Get-Bytes (Join-Path $r 'CHANGELOG.md'))))
        Assert-Equal "$($case.Label): the folder is as it was" $names (Get-FolderNames $r)
    }

    # -- Refusals: the whole fold, named, nothing written -------------------------
    Write-Host ""
    Write-Host "-- Refusals -------------------------------------------" -ForegroundColor Cyan
    $refusals = @(
        @{ Label = 'an unknown kind'; File = 'E5.security.md'; Text = "- Not a kind this project uses.`n"; Says = "kind 'security'" },
        @{ Label = 'a name that is not <id>.<kind>.md'; File = 'notes.md'; Text = "- A note.`n"; Says = 'is not named <id>.<kind>.md' },
        @{ Label = 'a kind with no id'; File = '.added.md'; Text = "- Hidden.`n"; Says = '' },
        @{ Label = 'an empty fragment'; File = 'E6.fixed.md'; Text = "`n"; Says = 'is empty' },
        @{ Label = 'a fragment with a heading'; File = 'E7.added.md'; Text = "- An entry.`n## [9.9.9]`n"; Says = 'heading' },
        @{ Label = 'a first line that is not an entry'; File = 'E8.added.md'; Text = "An entry with no dash.`n"; Says = 'first line is not an entry' },
        @{ Label = 'a blank line inside'; File = 'E9.added.md'; Text = "- One.`n`n- Two.`n"; Says = 'blank line inside' }
    )
    foreach ($c in $refusals) {
        $r = New-FoldScratch -Fragments $allFragments -Extra @{ $c.File = $c.Text }
        $before = Get-Bytes (Join-Path $r 'CHANGELOG.md')
        $names = Get-FolderNames $r
        $run = Invoke-Fold -Root $r
        if ($c.File.StartsWith('.')) {
            # A dot-file is the system's, not a fragment: it is skipped, and the fold goes through.
            Assert-Equal "$($c.Label) ($($c.File)): a dot-file is skipped, exit 0" 0 $run.Exit
            Assert-True "$($c.Label): and is left where it is" ((Get-FolderNames $r) -eq "$($c.File),README.md") (Get-FolderNames $r)
            continue
        }
        Assert-Equal "$($c.Label) ($($c.File)): exit 2" 2 $run.Exit
        Assert-True "$($c.Label): one Error: block naming changelog.d/$($c.File)" (($run.Output -match [regex]::Escape("changelog.d/$($c.File)")) -and (@([regex]::Matches($run.Output, '(?m)^Error: ')).Count -eq 1) -and ($run.Output -match '(?m)^Hint: ')) $run.Output
        Assert-True "$($c.Label): says why ($($c.Says))" ($run.Output -match [regex]::Escape($c.Says)) $run.Output
        Assert-True "$($c.Label): CHANGELOG.md keeps its bytes" ([System.Convert]::ToBase64String($before) -eq [System.Convert]::ToBase64String((Get-Bytes (Join-Path $r 'CHANGELOG.md'))))
        Assert-Equal "$($c.Label): no fragment is deleted, the good ones included" $names (Get-FolderNames $r)
    }

    $r = New-FoldScratch -Fragments @('A1.added.md') -Extra @{ 'E5.security.md' = "- x`n"; 'notes.md' = "- y`n" }
    $run = Invoke-Fold -Root $r
    Assert-True 'two bad files: one refusal naming both' (($run.Exit -eq 2) -and ($run.Output -match 'E5\.security\.md') -and ($run.Output -match 'notes\.md')) $run.Output

    $r = New-FoldScratch -Fragments @('A1.added.md') -Extra @{ 'E5.security.md' = "- x`n" }
    $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $childOut = (& $exe -NoProfile -File $foldScript -Root $r 2>&1 | Out-String)
    Assert-Equal 'run as its own process, a refusal still exits 2' 2 $LASTEXITCODE
    Assert-True 'and still names the file' ($childOut -match 'E5\.security\.md') $childOut

    $r = New-FoldScratch -Fragments @('A1.added.md')
    [System.IO.File]::WriteAllText((Join-Path $r 'CHANGELOG.md'), "# Changelog`n`n## [1.0.0] - 2026-01-01`n", $utf8)
    $run = Invoke-Fold -Root $r
    Assert-True 'a changelog with no ## [Unreleased]: exit 2, saying so' (($run.Exit -eq 2) -and ($run.Output -match "0 '## \[Unreleased\]' headings")) $run.Output
    Assert-Equal 'a changelog with no ## [Unreleased]: the fragment stays' 'A1.added.md' (Get-FolderNames $r)

    $r = New-FoldScratch -Changelog '' -Fragments @('A1.added.md')
    $run = Invoke-Fold -Root $r
    Assert-True 'no CHANGELOG.md: exit 2, saying so' (($run.Exit -eq 2) -and ($run.Output -match 'CHANGELOG\.md is not in')) $run.Output

    # -- -WhatIf and -Check write nothing -------------------------------------------
    Write-Host ""
    Write-Host "-- -WhatIf and -Check ---------------------------------" -ForegroundColor Cyan
    $r = New-FoldScratch -Fragments $allFragments
    $before = Get-Bytes (Join-Path $r 'CHANGELOG.md')
    $names = Get-FolderNames $r
    $run = Invoke-Fold -Root $r -With @{ WhatIf = $true }
    Assert-Equal '-WhatIf: exit 0' 0 $run.Exit
    Assert-True '-WhatIf: prints the section it would write and the files it would delete' (($run.Output -match '- Removed by D4\.') -and ($run.Output -match 'would delete: changelog\.d/A1\.added\.md')) $run.Output
    Assert-True '-WhatIf: CHANGELOG.md keeps its bytes' ([System.Convert]::ToBase64String($before) -eq [System.Convert]::ToBase64String((Get-Bytes (Join-Path $r 'CHANGELOG.md'))))
    Assert-Equal '-WhatIf: nothing is deleted' $names (Get-FolderNames $r)

    $run = Invoke-Fold -Root $r -With @{ Check = $true }
    Assert-Equal '-Check on good fragments: exit 0' 0 $run.Exit
    Assert-True '-Check: says what would fold' ($run.Output -match '5 file\(s\) ready to fold: Added 2, Changed 2, Removed 1, Fixed 1') $run.Output
    Assert-True '-Check: CHANGELOG.md keeps its bytes' ([System.Convert]::ToBase64String($before) -eq [System.Convert]::ToBase64String((Get-Bytes (Join-Path $r 'CHANGELOG.md'))))
    Assert-Equal '-Check: nothing is deleted' $names (Get-FolderNames $r)

    $r = New-FoldScratch -Fragments @('A1.added.md') -Extra @{ 'E5.security.md' = "- x`n" }
    $run = Invoke-Fold -Root $r -With @{ Check = $true }
    Assert-True '-Check on a bad fragment: exit 2 naming it' (($run.Exit -eq 2) -and ($run.Output -match 'would not fold') -and ($run.Output -match 'E5\.security\.md')) $run.Output

    # -- release.yml still finds the section ----------------------------------------
    Write-Host ""
    Write-Host "-- release.yml ----------------------------------------" -ForegroundColor Cyan
    $releaseText = Get-Text (Join-Path $pkgRoot '.github/workflows/release.yml')
    $awkMatch = [regex]::Match($releaseText, "(?s)awk -v v=""\`$version"" '(.*?)'\s+CHANGELOG\.md")
    Assert-True 'release.yml reads the notes with an awk program over CHANGELOG.md' $awkMatch.Success
    $awk = Get-Command awk -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($awkMatch.Success -and $awk) {
        $r = New-FoldScratch -Fragments $allFragments
        $null = Invoke-Fold -Root $r
        # The release rename, as AGENTS.md writes it: the folded section takes the
        # version, and a fresh empty ## [Unreleased] opens above it.
        $cl = Join-Path $r 'CHANGELOG.md'
        $renamed = (Get-Text $cl) -replace '(?m)^## \[Unreleased\]$', "## [Unreleased]`n`n## [9.9.9] - 2026-11-04"
        [System.IO.File]::WriteAllText($cl, $renamed, $utf8)
        $prog = Join-Path $r 'notes.awk'
        [System.IO.File]::WriteAllText($prog, $awkMatch.Groups[1].Value, $utf8)
        $notes = (& $awk.Source -v 'v=9.9.9' -f $prog $cl | Out-String) -replace "`r", ''
        $want = [regex]::Match((Get-Text (Join-Path $fixtureDir 'expected.md')), '(?s)## \[Unreleased\]\n(.*?)## \[1\.0\.0\]').Groups[1].Value
        Assert-True "release.yml's own awk finds the folded section under its version" ($notes.Trim() -ceq $want.Trim()) $notes
        $none = (& $awk.Source -v 'v=9.9.8' -f $prog $cl | Out-String)
        Assert-True "and finds nothing for a version with no section, so the workflow refuses it" (-not $none.Trim()) $none
    }
    else { Write-Host "  SKIP  release.yml's awk over the folded result: no awk on this host" -ForegroundColor Yellow }

    $guardMatch = [regex]::Match($releaseText, '(?s)- name: Every changelog entry is folded\s*\r?\n\s+run: \|\r?\n(.*?)\r?\n\s*\r?\n')
    Assert-True 'release.yml refuses a tag while changelog.d/ still holds an entry' ($guardMatch.Success -and ($releaseText.IndexOf('Every changelog entry is folded') -lt $releaseText.IndexOf('The notes, from CHANGELOG.md')))
    $bash = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($guardMatch.Success -and $bash -and -not ($env:OS -eq 'Windows_NT')) {
        $guard = (@($guardMatch.Groups[1].Value -split "\r?\n" | ForEach-Object { $_ -replace '^ {10}', '' }) -join "`n") + "`n"
        $r = New-FoldScratch -Fragments @('README.md') -Extra @{ '.DS_Store' = 'x' }
        $gs = Join-Path $r 'guard.sh'
        [System.IO.File]::WriteAllText($gs, $guard, $utf8)
        Push-Location $r
        try {
            $null = (& $bash.Source $gs 2>&1 | Out-String)
            Assert-Equal "release.yml's guard passes a folder holding only its README" 0 $LASTEXITCODE
            [System.IO.File]::WriteAllText((Join-Path $r 'changelog.d/A1.added.md'), "- x`n", $utf8)
            $gOut = (& $bash.Source $gs 2>&1 | Out-String)
            Assert-True "release.yml's guard fails on an entry left unfolded, naming it" (($LASTEXITCODE -ne 0) -and ($gOut -match 'A1\.added\.md')) $gOut
        }
        finally { Pop-Location }
    }
    else { Write-Host "  SKIP  release.yml's guard, run: no bash on this host (or Windows, where bash may be WSL's)" -ForegroundColor Yellow }

    # -- The committed tree ---------------------------------------------------------
    Write-Host ""
    Write-Host "-- The committed tree ---------------------------------" -ForegroundColor Cyan
    Assert-True 'changelog.d/README.md ships' (Test-Path -LiteralPath (Join-Path $pkgRoot 'changelog.d/README.md'))
    # A fragment reaches the contract job alone, and that job's markdown lint is
    # what CI's path rule says reads it: the lint's globs have to name the folder.
    $lintMd = [string](([System.IO.File]::ReadAllText((Join-Path $pkgRoot 'web/package.json')) | ConvertFrom-Json).scripts.'lint:md')
    Assert-True 'the markdown lint reads the waiting entries: lint:md names changelog.d/*.md' ($lintMd -match '"changelog\.d/\*\.md"') $lintMd
    $lintCfg = Join-Path $pkgRoot 'changelog.d/.markdownlint-cli2.jsonc'
    Assert-True '...and the folder turns off only the first-line-heading rule, which an entry cannot meet' `
        ((Test-Path -LiteralPath $lintCfg) -and (@([regex]::Matches([System.IO.File]::ReadAllText($lintCfg), '"MD\d+"')).Count -eq 1) -and ([System.IO.File]::ReadAllText($lintCfg) -match '"MD041":\s*false'))
    $run = Invoke-Fold -Root $pkgRoot -With @{ Check = $true }
    Assert-Equal 'every committed fragment is in the shape a fold takes (-Check over the package)' 0 $run.Exit
    if ($run.Exit -ne 0) { Write-Host $run.Output }
    $agentsText = Get-Text (Join-Path $pkgRoot 'AGENTS.md')
    Assert-True 'AGENTS.md tells a change to add a file under changelog.d/, and a release to fold it' (($agentsText -match 'changelog\.d/') -and ($agentsText -match 'Fold-Changelog\.ps1'))
    $contribText = Get-Text (Join-Path $pkgRoot 'docs/CONTRIBUTING.md')
    Assert-True 'docs/CONTRIBUTING.md points a contributor at changelog.d/' ($contribText -match 'changelog\.d/')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    foreach ($d in $script:scratch) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
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
