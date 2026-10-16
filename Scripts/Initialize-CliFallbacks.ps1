#
# The two helpers every script calls -- Get-CliPrefix and Write-CliError --
# for a script run STANDALONE. NOT a runnable verb: DOT-SOURCED, at the top of
# a script, the way Write-CardText.ps1 and Invoke-TrackerRead.ps1 are:
#
#     . (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
#
# Both normally come from the module (utilities.psm1). A script is also run
# directly -- by a test, by a user running the .ps1, by anything that wants
# -Help without importing first -- so a missing helper must not be fatal. Each
# fallback is guarded, so the module's own definition wins whenever it is
# loaded, and dot-sourcing this file then defines nothing.
#
# Write-CliError is the module's shape exactly: the Error: line, the Hint: line,
# and $global:P20StatedError, which is the stated reason a caller reads after
# the refusal (AGENTS.md, "The refusal contract"). This file is the ONE copy:
# a script that carried its own drifted, and a refusal from it lost its reason.
# Tests/Test-Portability.ps1 refuses an inline copy anywhere else in Scripts/.
#
# Dot-source it at the script's top level, before the first call -- some
# scripts refuse from their own parameter checks. PowerShell 5.1 clean; reads
# no module state.

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param(
            [Parameter(Mandatory)][string]$Message,
            [string]$Hint
        )
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) {
            Write-Host "Hint:  $Hint" -ForegroundColor Yellow
        }
    }
}
