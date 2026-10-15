# Prompt20Toolkit -- auto-loading shim for toolkit/utilities.psm1
#
# Why this exists
# ---------------
# `utilities.psm1` publishes its commands by writing straight into the
# caller's session (`function global:` + `Set-Alias -Scope Global`) as a side
# effect of import. That works, but only for a shell that has already imported
# it -- which in practice means an interactive shell that loaded the profile.
#
# Non-interactive shells don't load the profile: agent tool calls, `pwsh -c`,
# CI, hooks, VS Code tasks. In those, every prefixed call failed with
# "The term '{cliPrefix}X' is not recognized" until someone remembered the manual
# Import-Module line. That's the bug this fixes.
#
# The fix is module auto-loading: PowerShell searches $env:PSModulePath when it
# meets an unknown command, so a module DIRECTORY on that path whose manifest
# advertises the aliases makes them resolve on first use, in any shell.
#
# This file is deliberately a shim rather than a copy. `utilities.psm1` stays
# the single source of truth -- the alias list is NOT duplicated here, because a
# second hand-maintained list is how the two drift apart and a new command
# silently stops working in exactly the non-interactive shells this was meant to
# fix. The manifest's AliasesToExport is generated, not typed; see
# Update-ToolkitManifest.ps1.

# Locate the real toolkit.
#
# When installed as a SYMLINK, $PSScriptRoot resolves inside the repo, so
# utilities.psm1 sits one level up and no guessing is needed -- this is the
# path that survives the repo being cloned anywhere.
#
# When installed as a COPY (no symlink privilege), $PSScriptRoot is under the
# user's module folder and the sibling lookup misses, so fall back to
# $env:WS_ROOT (exported by the toolkit itself) and then the per-platform
# default.
$utilities = Join-Path (Split-Path $PSScriptRoot -Parent) 'utilities.psm1'

if (-not (Test-Path $utilities)) {
    $wsRoot = if ($env:WS_ROOT) {
        $env:WS_ROOT
    }
    elseif (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) {
        'C:\ws'  # export:example
    }
    else {
        Join-Path $HOME 'Repos'
    }
    # Nested rather than the 3-arg form: multi-argument Join-Path is PS 6+ only,
    # and this module must parse on the 5.1 floor (CLI.md clause 10).
    $utilities = Join-Path (Join-Path $wsRoot 'toolkit') 'utilities.psm1'
}

if (-not (Test-Path $utilities)) {
    # A warning, not a throw: auto-loading fires on ANY unrecognized prefixed
    # command, so throwing here would turn a typo into a stack trace that looks
    # like the toolkit is broken.
    Write-Warning "Prompt20Toolkit: no utilities.psm1 at $utilities. Set `$env:WS_ROOT to your checkout's parent, or import the module directly."
    return
}

# -Global is what makes this work. Without it the functions and aliases land in
# THIS shim's module scope and vanish the moment the auto-load completes -- the
# command that triggered the load would still come back "not recognized".
# -DisableNameChecking suppresses the unapproved-verb noise for these helpers.
Import-Module $utilities -Force -Global -DisableNameChecking
