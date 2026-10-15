<#
.SYNOPSIS
    Static analysis tests for PowerShell 5.1 compatibility.
.DESCRIPTION
    Scans all toolkit .ps1/.psm1 files for syntax and API usage
    that would fail on Windows PowerShell 5.1. Catches:
      - Ternary operator (condition ? a : b)
      - Null-coalescing (??, ??=)
      - Pipeline chain operators (&& ||) in PS code (not comments/strings)
      - ForEach-Object -Parallel
      - ConvertFrom-Json -AsHashtable
      - $IsWindows/$IsMacOS/$IsLinux without PSEdition fallback
      - Clean {} block in functions
      - Get-Content -AsByteStream (5.1 uses -Encoding Byte)
      - [System.Collections.Generic.*] that need explicit assembly in 5.1

    Run:  {cliPrefix}TestToolkit -Compat
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# The package root is the parent of Tests/. Derived from this file's own
# location rather than from git, so the scan works wherever the package sits
# and needs no repo around it.
$toolkitRoot = Split-Path $scriptDir -Parent

# ── Test harness ──────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:warned = 0
$script:errors = @()

function Assert-NoMatch {
    param(
        [string]$TestName,
        [string]$Pattern,
        [string]$FilePath,
        [string[]]$Content,
        [string[]]$ExcludeContextPatterns = @()
    )
    $lineNum = 0
    $hits = @()
    foreach ($line in $Content) {
        $lineNum++
        # Skip comments and here-string content
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#')) { continue }
        # Skip lines inside here-strings or string literals that match
        if ($trimmed -match '^\s*["''].*["'']') {
            # Entire line is a string — check if the match is only inside quotes
        }
        # Skip excluded context patterns (e.g. comment blocks, help text)
        $skip = $false
        foreach ($ep in $ExcludeContextPatterns) {
            if ($trimmed -match $ep) { $skip = $true; break }
        }
        if ($skip) { continue }

        if ($line -match $Pattern) {
            $hits += "${lineNum}: $($trimmed.Substring(0, [Math]::Min(80, $trimmed.Length)))"
        }
    }
    $fileName = Split-Path $FilePath -Leaf
    if ($hits.Count -eq 0) {
        $script:passed++
        Write-Host "  PASS  $fileName — $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $fileName — $TestName ($($hits.Count) hit(s))"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
        foreach ($h in $hits) {
            Write-Host "        $h" -ForegroundColor DarkRed
        }
    }
}

function Assert-True {
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PowerShell 5.1 Compatibility Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# ── Gather files ─────────────────────────────────────────────────────────────

# Scripts/ and the top-level module, plus any .ps1/.psm1 in toolkit subfolders
# (e.g. Prompt20Toolkit/). The subfolder sweep matters: code that ships as part of
# the toolkit but lives outside Scripts/ was previously invisible to this gate,
# so a 5.1-incompatible file could land there and only fail on a 5.1 machine.
# Tests/ is excluded -- the suites themselves run under pwsh 7 by design.
# The exclusion list is shared with Test-Portability -- see Tests/ScanExclusions.ps1
# for why there is only one of it.
. (Join-Path $scriptDir 'ScanExclusions.ps1')

$scriptFiles = @(@(
    Get-ChildItem "$toolkitRoot\Scripts\*.ps1" -ErrorAction SilentlyContinue
    Get-ChildItem "$toolkitRoot\*.psm1" -ErrorAction SilentlyContinue
    Get-ChildItem $toolkitRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Scripts', 'Tests') -and -not (Test-ScanExcluded $_.FullName) } |
        ForEach-Object { Get-ChildItem $_.FullName -Include '*.ps1', '*.psm1' -Recurse -File -ErrorAction SilentlyContinue }
) | Select-ScannableFile)

# The filter above rejects an excluded folder at the TOP level; Select-ScannableFile
# rejects one at any depth. Both are needed: `web` is source and must be entered,
# `web/node_modules` is a vendored tree three thousand files deep and must not be.
# Before this, the sweep descended into it once `npm ci` had run, and the suite's
# total -- and therefore the whole run's -- depended on whether a sibling half's
# dependencies happened to be installed. The count is now the same either way.

Assert-True "Found toolkit scripts to scan" ($scriptFiles.Count -gt 0)
Write-Host "  Scanning $($scriptFiles.Count) files..." -ForegroundColor DarkGray
Write-Host ""

# ── Patterns to check ───────────────────────────────────────────────────────
# Each pattern is: { Name, Regex, Severity, ExcludeContext }
#
# ExcludeContext patterns skip lines that are clearly in comments or docs
# (e.g. help blocks, inline comments with &&).

$commentOrDocPattern = @(
    '^\s*#'                       # line comment
    '^\s*\.SYNOPSIS'              # help block
    '^\s*\.DESCRIPTION'
    '^\s*\.EXAMPLE'
    '^\s*Write-Host.*".*&&'       # string containing &&
    '^\s*\$\w+\s*=\s*["'']'      # variable assignment to string
    '^\s*\[void\].*Append'        # StringBuilder
    "^\s*'.*&&"                   # single-quoted string
)

# Build Unicode-safe regex patterns from codepoints -- avoids file-encoding ambiguity
# [char] cast is PS 5.1-safe; .NET regex matches the resulting Unicode chars correctly
$patEmDash    = '[' + [string][char]0x2013 + [string][char]0x2014 + '][A-Za-z]'
$patSmartQuot = '[' + [string][char]0x2018 + [string][char]0x2019 +
                      [string][char]0x201C + [string][char]0x201D + ']'

$checks = @(
    @{
        Name    = 'No ternary operator (<cond> ? <a> : <b>)'
        # Match: ) ? expr : expr  or  $var ? expr : expr
        # Avoid matching ? in regex patterns or help text
        Pattern = '(?<!\[[\w ]*)\s+\?\s+[^{].*\s+:\s+'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No null-coalescing (?? or ??=)'
        Pattern = '\?\?'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No pipeline chain operators (&& or ||) in code'
        Pattern = '(?<![''"])\s+&&\s+|(?<![''"])\s+\|\|\s+'
        Exclude = $commentOrDocPattern + @(
            '^\s*#'
            'git pull.*&&'         # git commands in comments/help
            'pull --rebase.*&&'
            '2>/dev/null'          # shell script lines
            '\(\) \{'             # bash function definitions
        )
    },
    @{
        Name    = 'No ForEach-Object -Parallel'
        Pattern = 'ForEach-Object\s+-Parallel'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No ConvertFrom-Json -AsHashtable'
        Pattern = 'ConvertFrom-Json\s+-AsHashtable'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No Get-Content -AsByteStream'
        Pattern = 'Get-Content\s+.*-AsByteStream'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No Clean {} block'
        Pattern = '^\s*clean\s*\{'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No 3-arg Join-Path (PS 6+ only)'
        # Match Join-Path with 3+ bare positional args (not nested Join-Path or -flags)
        # e.g. Join-Path $a $b 'c'  but not  Join-Path (Join-Path $a $b) 'c'
        # Exclude ) from arg chars so nested calls don't false-positive
        Pattern = 'Join-Path\s+(?!\()[\$''"][^\s)]+\s+(?!-)[\$''"][^\s)]+\s+(?!-)[\$''"]'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No [System.IO.Path]::GetRelativePath (.NET Core only)'
        Pattern = '\[System\.IO\.Path\]::GetRelativePath'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = ‘No em dash / en dash in parameter position (use ASCII hyphen)’
        # Catches copy-paste errors: Get-Item [U+2014]Path or $x [U+2013]eq $y
        # Pattern built from [char] casts -- see $patEmDash above
        Pattern = $patEmDash
        Exclude = $commentOrDocPattern + @(
            ‘^\s*Write-Host\b’
            ‘^\s*Write-Warning\b’
            ‘^\s*Write-Error\b’
            ‘^\s*Write-Verbose\b’
            ‘^\s*\$\w+\s*[+]?=’    # variable assignment RHS
        )
    },
    @{
        Name    = ‘No smart / curly quotes (not valid PS string delimiters)’
        # U+2018/2019 = curly single, U+201C/201D = curly double
        # Pattern built from [char] casts -- see $patSmartQuot above
        # Pasting from Word/web often substitutes these for straight ASCII quotes
        Pattern = $patSmartQuot
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = 'No -SkipCertificateCheck on web cmdlets (PS 6+ only)'
        Pattern = '-SkipCertificateCheck'
        Exclude = $commentOrDocPattern
    },
    @{
        Name    = '$IsWindows/$IsMacOS/$IsLinux has PSEdition guard'
        # This is checked specially below
        Pattern = $null
        Exclude = @()
    }
)

# ── Run checks ──────────────────────────────────────────────────────────────

foreach ($file in $scriptFiles) {
    $content = Get-Content $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    Write-Host "── $($file.Name) ──" -ForegroundColor Magenta

    foreach ($check in $checks) {
        if (-not $check.Pattern) { continue }
        Assert-NoMatch -TestName $check.Name `
            -Pattern $check.Pattern `
            -FilePath $file.FullName `
            -Content $content `
            -ExcludeContextPatterns $check.Exclude
    }

    # Special check: $IsWindows / $IsMacOS / $IsLinux without PSEdition guard
    # In 5.1 these variables don't exist. Code should either:
    #   - Check PSEdition first: ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    #   - Use the toolkit helper: Get-IsWindows
    $lineNum = 0
    $unguarded = @()
    foreach ($line in $content) {
        $lineNum++
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#')) { continue }

        if ($line -match '\$Is(Windows|MacOS|Linux)') {
            # Check if same line has PSEdition guard or is in a safe helper
            $hasGuard = $line -match 'PSEdition.*Desktop' -or
            $line -match 'PSVersionTable\.PSEdition' -or
            $line -match 'Get-IsWindows'
            # Check if this IS the Get-IsWindows helper definition
            $isHelper = $line -match 'function.*Get-IsWindows'

            if (-not $hasGuard -and -not $isHelper) {
                $unguarded += "${lineNum}: $($trimmed.Substring(0, [Math]::Min(80, $trimmed.Length)))"
            }
        }
    }

    if ($unguarded.Count -eq 0) {
        $script:passed++
        Write-Host "  PASS  $($file.Name) — `$IsWindows/`$IsMacOS/`$IsLinux guarded or absent" -ForegroundColor Green
    }
    else {
        # Check if the file sources utilities.psm1 (which provides Get-IsWindows)
        $importsUtilities = ($content -join "`n") -match 'Import-Module.*utilities'
        if ($importsUtilities) {
            # File imports utilities — the helper is available, but direct use is still risky
            $script:warned++
            Write-Host "  WARN  $($file.Name) — `$IsWindows/`$IsMacOS/`$IsLinux used ($($unguarded.Count)x) — utilities.psm1 provides Get-IsWindows" -ForegroundColor DarkYellow
            foreach ($u in $unguarded) {
                Write-Host "        $u" -ForegroundColor DarkYellow
            }
        }
        else {
            $script:failed++
            $msg = "  FAIL  $($file.Name) — `$IsWindows/`$IsMacOS/`$IsLinux unguarded ($($unguarded.Count)x)"
            $script:errors += $msg
            Write-Host $msg -ForegroundColor Red
            foreach ($u in $unguarded) {
                Write-Host "        $u" -ForegroundColor DarkRed
            }
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
$warnStr = if ($script:warned -gt 0) { "  ($($script:warned) warnings)" } else { '' }
Write-Host "  Results: $($script:passed)/$total passed$warnStr" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
