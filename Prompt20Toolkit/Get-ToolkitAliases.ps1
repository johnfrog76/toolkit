#!/usr/bin/env pwsh
<#
.SYNOPSIS
The single definition of which aliases the autoload manifest must advertise.

.DESCRIPTION
Dot-source this from both Update-ToolkitManifest.ps1 and Tests/Test-Autoload.ps1.
The generator writes what this returns; the test asserts the committed manifest
equals what this returns. One definition, so the two cannot drift apart on what
counts as canonical -- which is the failure mode this file exists to prevent.

The canonical set is:

  1. Every alias utilities.psm1 defines on import, discovered by reflection in a
     clean child shell -- these are the hand-written COMMANDS, the thing
     autoload actually has to resolve.
  2. Every navigation alias declared in config.default.json, whatever its
     `display` flag or path, spelled as the prefix plus its bare key -- which is
     the name it registers under.

Nav aliases are deliberately taken from the committed config rather than from
the import. utilities.psm1 registers them by merging config.default.json with
the gitignored, per-machine config.local.json, so the imported set is
"canonical commands + whichever repos this developer happens to have cloned."
Baking that into a shared committed manifest meant `{cliPrefix}TestToolkit -Autoload`
flipped red/green purely on which machine ran it, with no code change involved.
Discovery therefore runs with PROMPTS_TOOLKIT_NO_NAV_ALIASES=1, which makes the
module skip the nav loop entirely, and the names are added back from the
committed config instead.

Advertising a nav name the current machine has not enabled costs nothing: the
alias resolves, the module loads, and the name simply is not there -- the same
"command not found" any typo gets. Advertising one machine's PERSONAL shortcut
is what could not be made to hold on the next machine. A shortcut that should
survive a profile-less shell therefore needs a name in config.default.json
(path "", display false is enough); one that only exists in config.local.json
is, by construction, local.
#>

# The shipped default prefix lives in ONE place and this reads it. Only two
# things dot-source this file -- Update-ToolkitManifest.ps1 and
# Tests/Test-Autoload.ps1 -- and both run from inside the package, where
# Scripts/ is a sibling. (The installed shim carries a copy of this file that
# nothing loads; if that ever changes, this line failing is the right way to
# find out, rather than a second copy of the default quietly answering.)
. (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Scripts') 'Resolve-CliPrefix.ps1')

function Get-ToolkitAliases {
    [CmdletBinding()]
    param(
        # toolkit/utilities.psm1
        [Parameter(Mandatory)][string]$UtilitiesPath,
        # toolkit/config.default.json
        [Parameter(Mandatory)][string]$DefaultConfigPath
    )

    if (-not (Test-Path $UtilitiesPath)) {
        throw "Cannot find utilities.psm1 (expected at $UtilitiesPath)"
    }

    # A clean child shell: the calling process may already carry aliases from
    # an earlier import, which would pollute the "what did THIS module add"
    # answer. Reflection rather than regexing the source for Set-Alias -- it sees
    # what really loads, not what someone remembered to write in the expected
    # shape. Run from a temp FILE rather than -Command so the module path needs
    # no second round of quoting.
    $escaped = $UtilitiesPath -replace "'", "''"
    $body = @"
`$env:PROMPTS_TOOLKIT_NO_NAV_ALIASES = '1'
`$before = (Get-Alias).Name
Import-Module '$escaped' -Force -DisableNameChecking -WarningAction SilentlyContinue *> `$null
(Get-Alias | Where-Object { `$_.Name -notin `$before }).Name | Sort-Object
"@

    # WriteAllText rather than Set-Content: the manifest generator declares
    # SupportsShouldProcess, so under -WhatIf a Set-Content here would be skipped,
    # the probe script would never exist, and pwsh's usage banner would come back
    # looking like a list of aliases.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "toolkit-alias-discovery-$([guid]::NewGuid()).ps1"
    try {
        [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
        $out = & pwsh -NoProfile -File $tmp
        $probeExit = $LASTEXITCODE
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    if ($probeExit -ne 0) {
        throw "Alias discovery shell exited $probeExit -- cannot tell which aliases utilities.psm1 defines"
    }

    # Keep only the toolkit's own prefixed namespace. Two things also land in a
    # before/after alias diff and neither belongs in this manifest:
    #   - Anything not shaped like an alias name at all (a banner, an error line)
    #     -- a symptom, and junk in a file that IS the autoload contract.
    #   - PowerShell's OWN aliases. utilities.psm1 calls Set-Clipboard,
    #     Get-ComputerInfo and friends at import time, which autoloads the
    #     modules that own them and drops gcb/scb/gin/gtz/stz into the session.
    #     Which of those appear depends on the platform, so they made the drift
    #     check differ between Windows and macOS as well as between configs.
    # Every toolkit command carries the configured prefix; Test-Autoload
    # cross-checks the Set-Alias lines in utilities.psm1 against the manifest, so
    # a command that ever breaks that convention fails loudly rather than being
    # silently dropped here.
    # The command namespace is whatever prefix the config declares, never a
    # literal. Registering under a different prefix must not silently produce
    # an empty manifest, and the shipped default lives in one place --
    # Scripts/Resolve-CliPrefix.ps1.
    $config = $null
    $prefix = Get-P20DefaultPrefix
    if (Test-Path $DefaultConfigPath) {
        $config = Get-Content $DefaultConfigPath -Raw | ConvertFrom-Json
        if ($config.commandPrefix) { $prefix = $config.commandPrefix }
    }
    $prefixPattern = '^' + [regex]::Escape($prefix) + '[A-Za-z0-9_-]*$'

    $commands = @($out |
        Where-Object { $_ -and $_.ToString().Trim() } |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ -match $prefixPattern })

    # Nav alias keys are stored BARE in config.default.json, exactly as command
    # keys are, and the prefix is applied when the alias is registered. So the
    # manifest -- which advertises the names a cold shell has to resolve -- emits
    # prefix + key, and a changed `commandPrefix` moves the shortcuts with the
    # verbs instead of leaving them behind.
    #
    $nav = @()
    if ($config -and $config.aliases) {
        $nav = @($config.aliases.PSObject.Properties.Name | ForEach-Object { $prefix + $_ })
    }

    return @(@($commands + $nav) | Sort-Object -Unique)
}
