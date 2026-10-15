<#
.SYNOPSIS
    Regenerate provider-specific agent adapters from AGENTS.md.

.DESCRIPTION
    AGENTS.md is the source of truth and is deliberately provider-neutral -- plain
    Markdown, no vendor frontmatter, readable by any assistant or by a person.

    Assistants each want the same knowledge in their own wrapper, and none of them
    support including another file, so the wrappers have to be generated. Writing
    them by hand would mean the portable asset lives in a vendor-shaped box and
    drifts the moment one copy is edited -- which is the failure this whole
    arrangement exists to avoid.

    Adapters are NOT committed -- see .gitignore. They are generated per machine,
    for whichever assistant is in use, the same way InstallAutoload writes the
    PowerShell shim into the module path rather than tracking a copy. Committing
    one would ship this tool's knowledge in a vendor-shaped box and pick a winner
    among assistants the client chooses, not us.

    Run this after editing AGENTS.md. InstallAutoload runs it for you.

.EXAMPLE
    ./Scripts/Update-AgentDocs.ps1
    ./Scripts/Update-AgentDocs.ps1 -Check    # report drift, write nothing

    Every COPY is compared on its own: the one in the checkout and the one in
    the user's home folder. Comparing only the checkout's, and writing the home
    copy only when that one drifted, would leave the checkout reading "[ok]"
    while the skill an assistant actually loads is weeks behind.
    A copy that does not exist is not drift: a machine that never generated
    one is not behind. Update and Setup both ask -Check.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Summary', Justification = 'Every adapter''s Render block takes the same ($Summary, $Body); the Copilot file has no front matter to put the summary in.')]
[CmdletBinding()]
param(
    [switch]$Check,
    # Where the user-level copies go. Composition for the tests, which must
    # never write into a real home folder.
    [string]$UserHome = $HOME,
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "  Update-AgentDocs -- regenerate agent adapters from AGENTS.md" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    -Check   Report drift and exit 1; write nothing" -ForegroundColor Gray
    Write-Host "    -Help    This message" -ForegroundColor Gray
    Write-Host ""
    return
}

# Write-CliError normally comes from the module; it is what makes a refusal ONE
# block. See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

$pkgRoot   = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $pkgRoot 'AGENTS.md'

if (-not (Test-Path $sourcePath)) {
    Write-CliError -Message "AGENTS.md not found at $sourcePath" -Hint "The adapters are generated from it; restore it from git."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Read the source as UTF-8 on every host. Get-Content -Raw with no -Encoding decodes a
# BOM-less file as the ANSI code page under Windows PowerShell 5.1 (an em dash comes out
# as a-circumflex-euro-quote) and as UTF-8 under 7, so the two hosts rendered different
# adapters and each called the other's drift -- the target read below is UTF-8 already.
$raw = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8)

# The summary line lives in the HTML comment so the neutral file carries no
# vendor syntax, and adapters that need a one-line trigger can still find it.
$summary = ''
if ($raw -match '(?s)ONE LINE SUMMARY[^\n]*\n\s*(.+?)\n\s*-->') {
    $summary = $Matches[1].Trim()
}
if (-not $summary) {
    Write-CliError -Message "No ONE LINE SUMMARY found in AGENTS.md -- adapters need a trigger description." -Hint "Put one in the HTML comment at the top of AGENTS.md."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Strip the generator's own note; everything after it is the shared content.
$body = $raw
$endComment = $body.IndexOf('-->')
if ($endComment -ge 0) { $body = $body.Substring($endComment + 3) }
$body = $body.Trim()

# -- Adapters -----------------------------------------------------------------
# Each assistant looks in its own place for the same knowledge. None of these is
# committed -- see .gitignore. Committing one would ship this tool's knowledge in
# a vendor-shaped box and pick a winner among tools the CLIENT chooses, not us.
#
# Adding a provider is an entry here. The conventions below are young and move;
# that is an argument for generating them from one source, not for tracking them
# by hand in several files.
$adapters = @(
    @{
        Name     = 'Claude Code skill'
        Path     = Join-Path $pkgRoot '.claude/skills/toolkit-ado/SKILL.md'
        UserPath = Join-Path $UserHome '.claude/skills/toolkit-ado/SKILL.md'
        Render   = {
            param($Summary, $Body)
            $l = @('---', 'name: toolkit-ado', "description: $Summary", '---', '')
            $l += '<!-- GENERATED from AGENTS.md by Scripts/Update-AgentDocs.ps1 -- do not edit. -->'
            $l += ''
            $l += $Body
            return ($l -join "`n") + "`n"
        }
    }
    @{
        Name   = 'GitHub Copilot instructions'
        Path   = Join-Path $pkgRoot '.github/copilot-instructions.md'
        Render = {
            param($Summary, $Body)
            $l = @('<!-- GENERATED from AGENTS.md by Scripts/Update-AgentDocs.ps1 -- do not edit. -->', '')
            $l += $Body
            return ($l -join "`n") + "`n"
        }
    }
    @{
        Name   = 'Cursor rule'
        Path   = Join-Path $pkgRoot '.cursor/rules/toolkit-ado.mdc'
        Render = {
            param($Summary, $Body)
            $l = @('---', "description: $Summary", 'alwaysApply: false', '---', '')
            $l += '<!-- GENERATED from AGENTS.md by Scripts/Update-AgentDocs.ps1 -- do not edit. -->'
            $l += ''
            $l += $Body
            return ($l -join "`n") + "`n"
        }
    }
)

$drift = @()
# One byte contract for everything this tool writes: UTF-8, no BOM, LF for a created file
# (Write-CardText -New), so a copy written under 5.1 and one written under 7 are identical.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

foreach ($a in $adapters) {
    $rendered = & $a.Render $summary $body
    # Compare on normalised line endings: the repo checks out CRLF on Windows and
    # LF elsewhere, and a line-ending difference is not drift.
    $normNew = $rendered -replace "`r`n", "`n"

    $targets = @(@{ Where = 'checkout'; Path = $a.Path })
    # A project-scoped adapter only helps while you are standing in this repo.
    # Where the assistant also reads a user-level location, that copy is kept
    # too -- and checked on its own, because it is the one loaded elsewhere.
    if ($a.UserPath) { $targets += @{ Where = 'home'; Path = $a.UserPath } }

    foreach ($t in $targets) {
        $exists = Test-Path -LiteralPath $t.Path
        $current = $exists -and ((([System.IO.File]::ReadAllText($t.Path)) -replace "`r`n", "`n").TrimStart([char]0xFEFF) -eq $normNew)
        if ($current) {
            Write-Host "  [ok]   $($a.Name) ($($t.Where)) is current" -ForegroundColor DarkGray
            continue
        }
        if ($Check) {
            if ($exists) {
                $drift += "$($a.Name) ($($t.Where))"
                Write-Host "  [!]    $($a.Name) ($($t.Where)) has drifted from AGENTS.md: $($t.Path)" -ForegroundColor Yellow
            }
            continue
        }
        $drift += "$($a.Name) ($($t.Where))"
        $dir = Split-Path $t.Path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-CardText -Path $t.Path -Content $rendered -New
        Write-Host "  [OK]   wrote $($a.Name) ($($t.Where))" -ForegroundColor Green
    }
}

Write-Host ""
if ($Check -and $drift.Count -gt 0) {
    Write-Host "  $($drift.Count) adapter cop$(if ($drift.Count -eq 1) { 'y' } else { 'ies' }) out of date. Run Scripts/Update-AgentDocs.ps1." -ForegroundColor Yellow
    exit 1
}
if ($drift.Count -eq 0) {
    Write-Host "  All adapters current." -ForegroundColor Green
}
exit 0
