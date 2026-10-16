#!/usr/bin/env pwsh
<#
.SYNOPSIS
Install the Prompt20Toolkit shim so `{cliPrefix}*` commands auto-load in any shell.

.DESCRIPTION
`utilities.psm1` publishes its `{cliPrefix}*` commands by writing into the caller's
session (`function global:` + `Set-Alias -Scope Global`) as an import side
effect. That works for a shell that already imported it -- in practice, an
interactive shell that loaded the profile.

Shells that never load the profile therefore had no `{cliPrefix}*` at all: agent tool
calls, `pwsh -c`, CI, git hooks, VS Code tasks. Every command in those failed
with "The term '{cliPrefix}X' is not recognized" until someone remembered the manual
Import-Module line. The agentic prompts even carry a standing workaround
("if a verb fails with not recognized, run the import and retry"), which is the
tell that the surface was broken rather than merely awkward.

This installs a small module DIRECTORY on $env:PSModulePath whose manifest
advertises the `{cliPrefix}*` aliases, so PowerShell's module auto-loading resolves them
on first use, in any shell, with no import line.

The shim does not duplicate the alias list -- utilities.psm1 stays the single
source of truth (clause 11: one obvious place to add a command). The manifest's
alias list is GENERATED from a live import, so adding a `{cliPrefix}*` command needs no
edit here; just re-run this.

Prefers a symlink (needs Developer Mode or elevation) so the install tracks the
repo. Falls back to a copy, which works everywhere but goes stale -- so
RE-RUNNING THIS IS THE UPDATE STEP. A copy is compared with the repo's shim
every time and refreshed when it differs; an identical copy, and a symlink, are
left alone. The script always reports which of the three it did, for every
destination it writes.

.EXAMPLE
{cliPrefix}InstallAutoload
.EXAMPLE
{cliPrefix}InstallAutoload -Force      # replace an existing install regardless
.EXAMPLE
{cliPrefix}InstallAutoload -WhatIf     # report what would happen, change nothing
.EXAMPLE
{cliPrefix}InstallAutoload -Remove     # take the shim out of every module root
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Replace an existing install even when it already matches the repo.
    [switch]$Force,

    # Take the shim back out of every module root the install writes to, then verify
    # it is gone in a cold shell. Never touches the checkout a link points at.
    [switch]$Remove,

    # Install under (or, with -Remove, take out of) this module directory instead of
    # the host's own; -Remove takes several, separated as PSModulePath is. For TESTS:
    # the suite must be able to exercise a first install, a no-op re-install and
    # a refresh without writing into the developer's real module path, where it
    # would overwrite the shim the machine actually uses. A caller that passes it
    # gets no 5.1 mirror and no cold-shell probe -- both are statements about
    # this machine's hosts, and a scratch directory is on neither host's
    # PSModulePath.
    [string]$ModuleRoot,

    # Skip the symlink attempt and install a copy. What Windows without
    # Developer Mode gets anyway, and the only mode in which the install can go
    # stale -- so it is also how the suite reaches the refresh path from a host
    # where symlinks succeed.
    [switch]$CopyOnly,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Run '$(Get-CliPrefix)InstallAutoload -Help' (help is generated from config.default.json)."
    return
}

# The prefix this package registers, and the shipped default behind it, read
# from one place rather than typed here.
. (Join-Path $PSScriptRoot 'Resolve-CliPrefix.ps1')

# -Remove is the way back out: it undoes what the install wrote, and nothing else.
# It never reads the shim's source and never touches the checkout a link points at.
if ($Remove) {
    if ($Force) {
        Write-CliError -Message "-Remove and -Force cannot be combined" `
                       -Hint "-Force replaces an install and -Remove deletes it; run one or the other."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    $isWinRm = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    if (-not [string]::IsNullOrWhiteSpace($ModuleRoot)) {
        # A scratch run names its own roots, separated like PSModulePath is.
        $removeRoots = @($ModuleRoot -split [System.IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $removeScratch = $true
    }
    else {
        $removeScratch = $false
        if ($isWinRm) {
            $docs = [Environment]::GetFolderPath('MyDocuments')
            $removeRoots = @((Join-Path $docs 'PowerShell\Modules'), (Join-Path $docs 'WindowsPowerShell\Modules'))
        }
        else {
            $removeRoots = @(Join-Path $HOME '.local/share/powershell/Modules')
        }
    }

    $removed = 0
    foreach ($root in $removeRoots) {
        $target = Join-Path $root 'Prompt20Toolkit'
        $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }

        $isLink = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if (-not $isLink -and -not (Test-Path -LiteralPath (Join-Path $target 'Prompt20Toolkit.psm1'))) {
            Write-Host "[--] Left $target alone: it is not a Prompt20Toolkit shim." -ForegroundColor Yellow
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($target, 'remove Prompt20Toolkit shim')) {
            Write-Host "Would remove $target" -ForegroundColor Gray
            $removed++
            continue
        }

        # A link is unlinked, never recursed into: on Windows PowerShell 5.1,
        # Remove-Item -Recurse on a directory link deletes the target's contents.
        if ($isLink) { [System.IO.Directory]::Delete($target, $false) }
        else { Remove-Item -LiteralPath $target -Recurse -Force }
        Write-Host "[OK] Removed $target" -ForegroundColor Green
        $removed++
    }

    if ($removed -eq 0) {
        Write-Host "nothing to remove" -ForegroundColor Gray
        return
    }
    if ($WhatIfPreference) { return }

    if ($removeScratch) {
        Write-Host "  -ModuleRoot given: skipping the cold-shell probe." -ForegroundColor Gray
        return
    }

    # Verify the way the install does: cold, no profile, no import, in each host.
    $removeProbe = (Resolve-P20ConfigPrefix -PackageRoot (Split-Path $PSScriptRoot -Parent)) + 'Status'
    Write-Host "  verifying in cold -NoProfile shells..." -ForegroundColor Gray
    $removeHosts = @(@{ Name = 'pwsh 7'; Exe = 'pwsh' })
    if ($isWinRm) { $removeHosts += @{ Name = 'Windows PowerShell 5.1'; Exe = 'powershell.exe' } }
    $stillThere = @()
    foreach ($h in $removeHosts) {
        if (-not (Get-Command $h.Exe -ErrorAction SilentlyContinue)) { continue }
        $probe = & $h.Exe -NoProfile -Command "[bool](Get-Command $removeProbe -ErrorAction SilentlyContinue)"
        $seen = (& $h.Exe -NoProfile -Command '$env:PSModulePath')
        if ($probe -eq 'True') {
            Write-Host "[!!] $removeProbe still resolves in $($h.Name) (PSModulePath: $seen)." -ForegroundColor Red
            $stillThere += $h.Name
        }
        else {
            Write-Host "[OK] $removeProbe no longer resolves in $($h.Name)." -ForegroundColor Green
        }
    }
    if ($stillThere.Count -gt 0) {
        Write-CliError -Message "$removeProbe still resolves in $($stillThere -join ', ') after the shim was removed" `
                       -Hint "Another copy of the module is on that host's `$env:PSModulePath, or the shell was started with the checkout on it."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)InstallAutoload" -Detail "removed shim ($removed location(s))"
    }
    return
}

$toolkitRoot = Split-Path $PSScriptRoot -Parent
$shimSource  = Join-Path $toolkitRoot 'Prompt20Toolkit'

if (-not (Test-Path (Join-Path $shimSource 'Prompt20Toolkit.psm1'))) {
    Write-CliError -Message "Shim source missing at $shimSource" `
                   -Hint "Expected toolkit/Prompt20Toolkit/Prompt20Toolkit.psm1 -- is the repo complete?"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Regenerate before installing. Installing a manifest whose alias list predates a
# new `{cliPrefix}*` command silently reintroduces the exact bug this fixes.
$generator = Join-Path $shimSource 'Update-ToolkitManifest.ps1'
if (Test-Path $generator) {
    Write-Host "  refreshing manifest from utilities.psm1..." -ForegroundColor Gray
    & $generator
    if ($LASTEXITCODE -ne 0) {
        Write-CliError -Message "Could not generate the module manifest" `
                       -Hint "Run toolkit/Prompt20Toolkit/Update-ToolkitManifest.ps1 directly to see why."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

# A COPY of the shim is stale the moment the repo's copy changes, and nothing on
# disk says so -- the alias list lives inside the manifest. Fingerprint the whole
# shim folder so a re-install can tell "already installed" from "installed, and
# behind".
#
# Line endings are normalised before hashing: .gitattributes pins the manifest to
# eol=lf, but the shim's *.ps1 files check out CRLF on Windows, and a fingerprint
# that moved with the checkout would call every Windows install stale forever.
# After that normalisation the comparison is byte-for-byte.
function Get-ShimFingerprint {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $parts = @()
        $files = @(Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($f in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $text = $text -replace "`r`n", "`n"
            $norm = [System.Text.Encoding]::UTF8.GetBytes($text)
            $hash = [System.BitConverter]::ToString($sha.ComputeHash($norm)).Replace('-', '')
            $parts += "$($f.Name):$hash"
        }
        return ($parts -join '|')
    }
    finally { $sha.Dispose() }
}

# One destination, one decision. Returns the word for what it did: 'symlink',
# 'installed', 'refreshed' or 'current'. The 5.1 mirror goes through here too --
# it was the second stale copy nobody mentioned.
function Install-ShimAt {
    param([string]$Destination, [string]$Source, [switch]$Replace, [switch]$CopyOnly)

    $wasLink = $false
    if (Test-Path $Destination) {
        $existing = Get-Item $Destination -Force
        $wasLink = ($existing.LinkType -eq 'SymbolicLink')
        # A symlink cannot go stale -- it IS the repo folder.
        if ($wasLink -and -not $Replace) { return 'symlink' }
        if ($Replace) { $verb = 'replaced' }
        elseif ((Get-ShimFingerprint $Destination) -eq (Get-ShimFingerprint $Source)) { return 'current' }
        else { $verb = 'refreshed' }
    }
    else { $verb = 'installed' }

    if (Test-Path $Destination) {
        # Remove-Item -Recurse on a DIRECTORY SYMLINK deletes the target's
        # contents on Windows PowerShell 5.1 -- which here is this repo's own
        # Prompt20Toolkit folder. Unlink instead; the link, not the target.
        if ($wasLink) { [System.IO.Directory]::Delete($Destination, $false) }
        else { Remove-Item $Destination -Recurse -Force }
    }
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    if (-not $CopyOnly) {
        try {
            $null = New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop
            return 'symlink'
        }
        catch {
            # No symlink privilege -- fall through to the copy.
            $null = $_
        }
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item (Join-Path $Source '*') $Destination -Recurse -Force
    return $verb
}

function Write-InstallResult {
    param([string]$Result, [string]$Destination, [string]$Label)

    $suffix = if ($Label) { " ($Label)" } else { '' }
    switch ($Result) {
        'symlink' {
            Write-Host "[OK] Symlinked $Destination$suffix" -ForegroundColor Green
            Write-Host "     Tracks the repo -- no reinstall after edits." -ForegroundColor Gray
        }
        'current' {
            Write-Host "[OK] Already up to date at $Destination$suffix (copy)" -ForegroundColor Green
            Write-Host "     Matches this repo's shim -- nothing to do." -ForegroundColor Gray
        }
        'refreshed' {
            Write-Host "[OK] Refreshed the copy at $Destination$suffix" -ForegroundColor Green
            Write-Host "     The installed shim differed from this repo and was replaced." -ForegroundColor Gray
        }
        'replaced' {
            Write-Host "[OK] Replaced the install at $Destination$suffix (-Force)" -ForegroundColor Green
            Write-Host "     Overwritten regardless of whether it differed." -ForegroundColor Gray
        }
        default {
            Write-Host "[OK] Copied to $Destination$suffix" -ForegroundColor Green
            Write-Host "     This is a COPY (no symlink privilege). Re-run $(Get-CliPrefix)InstallAutoload" -ForegroundColor Yellow
            Write-Host "     after adding a $(Get-CliPrefix)* command, or it won't resolve in agent shells." -ForegroundColor Yellow
            Write-Host "     Enable Developer Mode to get symlinks without elevation." -ForegroundColor Gray
        }
    }
}

$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$scratchRoot = -not [string]::IsNullOrWhiteSpace($ModuleRoot)
if ($scratchRoot) {
    $moduleRoot = $ModuleRoot
}
elseif ($isWin) {
    $moduleRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
}
else {
    $moduleRoot = Join-Path $HOME '.local/share/powershell/Modules'
}
$dest = Join-Path $moduleRoot 'Prompt20Toolkit'

if (-not $PSCmdlet.ShouldProcess($dest, 'install Prompt20Toolkit shim')) { return }

$result = Install-ShimAt -Destination $dest -Source $shimSource -Replace:$Force -CopyOnly:$CopyOnly
$linked = ($result -eq 'symlink')

Write-Host ""
Write-InstallResult -Result $result -Destination $dest

# Windows PowerShell 5.1 reads a DIFFERENT module directory than PowerShell 7
# -- Documents\WindowsPowerShell\Modules rather than Documents\PowerShell\Modules.
# Installing only to one leaves the commands unresolvable in the other host,
# which looks exactly like a broken install from whichever shell you happen to
# open. Mirror to both so either host autoloads -- and compare the mirror
# separately, because it is a copy on every machine and so goes stale on its own.
if ($isWin -and -not $scratchRoot) {
    $ps51Root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    $ps51Dest = Join-Path $ps51Root 'Prompt20Toolkit'
    $ps51Result = Install-ShimAt -Destination $ps51Dest -Source $shimSource -Replace:$Force -CopyOnly
    Write-InstallResult -Result $ps51Result -Destination $ps51Dest -Label 'Windows PowerShell 5.1'
}

# A scratch -ModuleRoot is not on any host's PSModulePath and is nobody's
# assistant directory, so the two machine-scoped steps below are skipped and
# said to be skipped. Everything above this line ran for real.
if ($scratchRoot) {
    Write-Host ""
    Write-Host "  -ModuleRoot given: skipping the 5.1 mirror, the agent adapters and the cold-shell probe." -ForegroundColor Gray
    return
}

# Verify in the shells this exists to fix: cold, no profile, no import.
$probeCmd = (Resolve-P20ConfigPrefix -PackageRoot (Split-Path $PSScriptRoot -Parent)) + 'Status'

Write-Host ""
# Teach the assistant too, not just the shell. The shim above makes commands
# resolve in any PowerShell; this makes whichever assistant is in use know how to
# drive them. Adapters are generated per machine rather than committed -- the
# client picks the assistant, so the repo must not favour one.
$agentDocs = Join-Path $PSScriptRoot 'Update-AgentDocs.ps1'
if (Test-Path $agentDocs) {
    Write-Host ""
    Write-Host "  agent adapters..." -ForegroundColor Gray
    try {
        & $agentDocs | Out-Null
        Write-Host "  [OK] agent guidance generated from AGENTS.md" -ForegroundColor Green
    }
    catch {
        # Never fail an install over this: the commands work regardless, and an
        # assistant that has not been told simply has to be told.
        Write-Host "  [!] could not generate agent adapters: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Host "  verifying in cold -NoProfile shells..." -ForegroundColor Gray
$hosts = @(@{ Name = 'pwsh 7'; Exe = 'pwsh' })
if ($isWin) { $hosts += @{ Name = 'Windows PowerShell 5.1'; Exe = 'powershell.exe' } }

$allOk = $true
foreach ($h in $hosts) {
    $probe = & $h.Exe -NoProfile -Command "[bool](Get-Command $probeCmd -ErrorAction SilentlyContinue)"
    if ($probe -eq 'True') {
        Write-Host "[OK] $probeCmd auto-loads in $($h.Name)." -ForegroundColor Green
    }
    else {
        Write-Host "[!!] $probeCmd does NOT resolve in $($h.Name)." -ForegroundColor Red
        $allOk = $false
    }
}
if (-not $allOk) {
    Write-CliError -Message "$probeCmd does not resolve without the profile in every host" `
                   -Hint "Check that the module directory is on that host's `$env:PSModulePath."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)InstallAutoload" -Detail "installed shim ($(if ($linked) { 'symlink' } else { 'copy' }))"
}
