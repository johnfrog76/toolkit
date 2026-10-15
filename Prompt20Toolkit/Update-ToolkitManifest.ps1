#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regenerate Prompt20Toolkit.psd1 from whatever utilities.psm1 actually exposes.

.DESCRIPTION
Module auto-loading only finds a command that the MANIFEST advertises. So the
manifest has to list all 55 prefixed aliases -- and a hand-maintained list of 55
names is a drift machine: add a command, forget the manifest, and it works
interactively while silently 404ing in agent shells. That's the failure this
whole shim exists to prevent, so the list is generated instead of typed.

The generator imports utilities.psm1 into a throwaway shell and asks the session
what appeared, rather than regexing the source for `Set-Alias`. Reflection sees
what actually loads; a regex sees what someone remembered to write in the
expected shape.

Navigation aliases are the exception: their names come from config.default.json,
because the ones that actually register on import depend on the gitignored,
per-machine config.local.json. See Get-ToolkitAliases.ps1, which both this
generator and Tests/Test-Autoload.ps1 use so they cannot drift apart on what
counts as canonical.

Run this after adding or renaming any `{cliPrefix}*` command.

.EXAMPLE
./Update-ToolkitManifest.ps1
.EXAMPLE
./Update-ToolkitManifest.ps1 -WhatIf     # show the diff, write nothing
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

# This lives at toolkit/Prompt20Toolkit/, so utilities.psm1 is one level up.
# Derived from $PSScriptRoot rather than a hardcoded root, so a clone at any
# path works.
$here       = $PSScriptRoot
$toolkitDir = Split-Path $here -Parent
$utilities  = Join-Path $toolkitDir 'utilities.psm1'
$configPath = Join-Path $toolkitDir 'config.default.json'

if (-not (Test-Path $utilities)) {
    throw "Cannot find utilities.psm1 (expected at $utilities)"
}

# Get-ToolkitAliases.ps1 owns the definition of "which aliases count" -- shared
# with Tests/Test-Autoload.ps1 so the generator and the drift check cannot
# disagree about it. It excludes personal nav shortcuts from config.local.json,
# which are per-machine and cannot live in a shared committed manifest.
. (Join-Path $here 'Get-ToolkitAliases.ps1')

# The version is consts.json's, the one place the product's version is typed
# (AGENTS.md, "One place for magic strings"). The manifest still carries it as a
# literal -- a data file cannot read another file -- but this generator writes
# that literal from the contract, so the generator holds no copy of its own and
# Tests/Test-Autoload.ps1's byte comparison goes red when the two disagree.
. (Join-Path (Join-Path $toolkitDir 'Scripts') 'Get-Consts.ps1')
$version = [string](Get-P20Consts -Path (Join-Path $toolkitDir 'consts.json')).version
if (-not $version) { throw "consts.json has no version -- refusing to write a manifest without one" }

$aliases = @(Get-ToolkitAliases -UtilitiesPath $utilities -DefaultConfigPath $configPath)
if (-not $aliases) { throw "Discovered no aliases from $utilities -- refusing to write an empty manifest" }

Write-Host "Discovered $($aliases.Count) aliases from utilities.psm1 + config.default.json" -ForegroundColor Cyan

$aliasBlock = ($aliases | ForEach-Object { "        '$_'" }) -join ",`n"
$manifestPath = Join-Path $here 'Prompt20Toolkit.psd1'

$content = @"
#
# Prompt20Toolkit -- GENERATED FILE, do not hand-edit.
# Regenerate with: ./Update-ToolkitManifest.ps1
#
# AliasesToExport is what makes the prefixed aliases auto-load in shells that never ran the
# profile (agent tool calls, pwsh -c, CI). PowerShell only consults the manifest
# when resolving an unknown command, so an alias missing from this list works
# interactively and fails everywhere else.
#
@{
    RootModule        = 'Prompt20Toolkit.psm1'
    ModuleVersion     = '$version'
    GUID              = '4c1d7e2a-3b6f-4a9e-9d21-7f0c5e8b2a61'
    Author            = 'Toolkit'
    Description       = 'Auto-loading shim for the Toolkit Toolkit (utilities.psm1 at the package root).'
    PowerShellVersion = '5.1'

    # The shim imports utilities.psm1 -Global, which defines these itself.
    # Declaring '*' would force a load just to enumerate; naming them is what
    # lets PowerShell resolve `{cliPrefix}Status` WITHOUT importing anything first.
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    AliasesToExport = @(
$aliasBlock
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('toolkit', 'toolkit', 'cards')
            ProjectUri = 'https://github.com/johnfrog76/toolkit'
        }
    }
}
"@

# .gitattributes pins this manifest to LF on every platform (the line was
# missing once -- on a Windows clone with core.autocrlf=true the
# file checked out CRLF, this script rewrote it LF, and the first install
# dirtied the tree.
# The here-string above may still carry CRLF on Windows while the
# alias block's join contributes LF, so normalise to LF before writing, and
# write the bytes directly rather than via Set-Content, which re-appends a
# platform-native terminator and, under PS 5.1, a BOM.
$content = $content -replace "`r`n", "`n"
if (-not $content.EndsWith("`n")) { $content += "`n" }

# A refresh that changes nothing must touch nothing: compare the bytes on disk
# first, so a no-op install leaves the tree exactly as clean as it found it.
# ShouldProcess runs first so -WhatIf still reports the operation it would perform.
$existing = if (Test-Path $manifestPath) { [System.IO.File]::ReadAllText($manifestPath) } else { $null }
if ($PSCmdlet.ShouldProcess($manifestPath, 'write manifest')) {
    if ($existing -eq $content) {
        Write-Host "[OK] Manifest already current: $manifestPath" -ForegroundColor Green
    }
    else {
        [System.IO.File]::WriteAllText($manifestPath, $content, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "[OK] Wrote $manifestPath" -ForegroundColor Green
    }
}
else {
    Write-Host "-WhatIf: would write $($aliases.Count) aliases to $manifestPath" -ForegroundColor Yellow
    $aliases | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}
