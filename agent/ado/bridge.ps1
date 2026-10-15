#!/usr/bin/env pwsh
<#
.SYNOPSIS
    The PowerShell half of POST /api/cmd/{name}: import this repo's toolkit and
    run exactly one function from it.

.DESCRIPTION
    Called by agent/ado/bridge.py as:

        <host> -NoProfile -File bridge.ps1 <Function-Name> [param] [param] ...

    <host> is whichever PowerShell the machine has -- pwsh where it exists,
    powershell.exe on a Windows machine with only the 5.1 floor. The resolver
    is agent/core/hosts.py, and the argv above is identical under both: 5.1 and
    7 alike hand every token after the script path to the script positionally,
    as strings. So nothing in this file may be 7-only; the shebang below is a
    convenience for a human running it directly on macOS, not the contract.

    Three decisions are load-bearing here:

    1. **This repo's own manifest, by path.** The import is resolved relative to
       THIS file, not from $env:PSModulePath and not from a configured root. A
       machine may have a second toolkit installed under a different prefix, or
       an autoload shim pointing somewhere else; the agent must run the tree it
       was started from or the web UI and the terminal are quietly two tools.

    2. **A function, never a prefixed alias.** The caller passes
       'Move-P20PromptToArchive', not '{cliPrefix}Archive'. The prefix is data
       (docs/CLI.md, "The prefix") and can be anything or several things at once, so
       an alias is not a stable name for a machine to call.

    3. **Parameters arrive as process argv, read positionally out of $args.**
       No param() block, on purpose. PowerShell's binder claims any argv token
       that starts with '-' as a parameter NAME before a declared array
       parameter can receive it, so a `param([string[]]$Params)` shape cannot
       carry '-Comment' or '-Reason' -- which is most of what the CLI's verbs
       take. Reading $args verbatim is the only shape where a parameter that
       begins with a dash, or contains spaces, quotes or punctuation, survives
       intact. Nothing here builds or parses a command STRING, so there is no
       quoting to get wrong and nothing to inject into.

    Exit code is the contract. 0 is success; anything else is the failure the
    caller reports. A terminating error becomes exit 1 with its message on
    stderr, because an unhandled exception's stack trace is not an error
    message.

.EXAMPLE
    pwsh -NoProfile -File bridge.ps1 Get-P20CommandMap
.EXAMPLE
    powershell -NoProfile -File bridge.ps1 Move-P20PromptToArchive Task401-add-retry.prompt.md
#>

# Not $args[0] + a param block: see decision 3 above.
if ($args.Count -lt 1) {
    [Console]::Error.WriteLine('bridge.ps1: no function name given')
    exit 2
}

$fn = [string]$args[0]
$fnArgs = @()
if ($args.Count -gt 1) { $fnArgs = @($args[1..($args.Count - 1)]) }

# Output is parsed by a caller that is not a terminal. UTF-8 so a card title
# with an em dash or an accent survives the pipe -- and constructed with
# emitUTF8Identifier = $false rather than [System.Text.Encoding]::UTF8, whose
# preamble flag is $true. Same rule as Write-CardText's: this repo never emits
# a BOM, and a BOM in front of Get-P20CommandMap's JSON is a line the caller's
# parser would not recognise as an object. New-Object, not ::new(), because
# this file is scanned by the 5.1 compatibility suite and read by 5.1.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { $null = $_ }

# The startup banner would otherwise be the first thing on stdout, ahead of
# whatever the command returns -- which breaks Get-P20CommandMap's JSON.
$env:TOOLKIT_QUIET_STARTUP = '1'

# agent/ado -> agent -> repo root. Nested Join-Path, not the 3-argument form:
# this file is inside the toolkit tree and the PS 5.1 compatibility suite scans
# it (CLI.md clause 10).
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$manifest = Join-Path (Join-Path $repoRoot 'Prompt20Toolkit') 'Prompt20Toolkit.psd1'

if (-not (Test-Path $manifest)) {
    [Console]::Error.WriteLine("bridge.ps1: no toolkit manifest at $manifest")
    exit 2
}

# Under -File, PowerShell folds the warning stream into stdout, and importing
# the toolkit on a machine with no config.local.json emits one. Stdout is
# parsed by the caller, so the import runs silent and the preference is put
# back before the command itself runs -- a warning the COMMAND raises is the
# caller's business.
$prevWarning = $WarningPreference
$WarningPreference = 'SilentlyContinue'
try {
    Import-Module $manifest -Force -DisableNameChecking -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine("bridge.ps1: could not import $manifest -- $($_.Exception.Message)")
    exit 2
}
finally {
    $WarningPreference = $prevWarning
}

# The allowlist lives in the caller, not here -- it is derived from
# Get-P20CommandMap. This check is the second half of that: a name the caller
# allowed must still resolve to something callable in THIS tree, and saying so
# is better than $fn being treated as a native command and reported as a shell
# failure.
$resolved = Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue
if (-not $resolved) {
    [Console]::Error.WriteLine("bridge.ps1: '$fn' is not a function in this toolkit")
    exit 127
}

# A clean return is 0; a terminating error is 1. Deliberately NOT
# `exit $LASTEXITCODE`: that variable holds the exit code of the last NATIVE
# command anywhere inside the verb, so a tier probe whose `az` call failed made
# a perfectly successful {cliPrefix}Env report as a failure. Exiting 0 on a
# clean return is also exactly the contract Tests/Test-ExitCodes.ps1 asserts for
# the CLI itself, so the bridge and the terminal agree about what failed.
#
# The consequence, and it is the CLI's rather than the bridge's: a verb that
# CATCHES its own failure, prints `Error: ...` via Write-CliError and returns
# normally exits 0 here too. The text is in the reply's `output` either way.
try {
    & $fn @fnArgs
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

exit 0
