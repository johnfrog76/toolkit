#
# The refusal contract's guard -- AGENTS.md, "The refusal contract".
#
# NOT a runnable verb: this file is DOT-SOURCED, by utilities.psm1 at import and
# by the suites that exercise a module wrapper in a bare pwsh. Same reasoning as
# Scripts/Resolve-HubConfig.ps1: there must be exactly one implementation of
# "what does a non-zero exit mean", and every caller has to be able to reach it.
#
# It depends on two things the module defines and the suites stub: Write-CliError
# and Write-ToolkitLog.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

# The one exit code that means "I have already said why". A script that has
# written its own Write-CliError block exits with this; anything else non-zero
# is a failure that said nothing.
$script:StatedRefusalExitCode = 2

# -- One guard for every wrapper -----------------------------------------------
# Runs a command's script and reads the exit code it left behind:
#
#   0   success -- one CMD line, nothing printed.
#   2   a stated refusal -- the script has already printed its own Error/Hint
#       block, so NOTHING is printed here. The reason is logged (not "exit code
#       2"), and $LASTEXITCODE is left at 2 so a caller that checks it sees the
#       failure the user was just told about.
#   n   a failure that said nothing -- the generic block, with the hint that
#       points at the log.
#
# A non-interactive caller cannot read $LASTEXITCODE across a process boundary:
# agent/ado/bridge.ps1 exits on whether the FUNCTION threw, deliberately, so a
# verb that catches its own failure and returns cleanly reports `success` to the
# web UI. For one of those -- TOOLKIT_QUIET_STARTUP, which the agent sets -- the
# stated refusal is re-raised AFTER the guard, unreported, so the bridge exits
# non-zero with the stated sentence on stderr and the browser is told `error`.
# It is never re-raised in a terminal: there the exit code is readable and a
# raw error record is exactly what this contract exists to remove.
function Invoke-ToolkitScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prefix,
        [System.Collections.IDictionary]$Parameters,
        [object[]]$Arguments,
        [string]$Detail = 'ok',
        [switch]$NoSuccessLog
    )
    # A config written since this shell loaded is re-read first. Absent in a bare shell that only dot-sourced this guard.
    if (Get-Command Update-P20StaleConfig -ErrorAction SilentlyContinue) { Update-P20StaleConfig }
    if ($null -eq $Parameters) { $Parameters = @{} }
    if ($null -eq $Arguments) { $Arguments = @() }

    $refusal = ''
    $code = 0
    try {
        # The guard below must read this script's outcome, not a stale one.
        $global:LASTEXITCODE = 0
        $global:P20StatedError = $null

        & $Path @Parameters @Arguments

        $code = $LASTEXITCODE
        if ($code -eq $script:StatedRefusalExitCode) {
            $refusal = [string]$global:P20StatedError
            if (-not $refusal) { $refusal = "$Name refused the request." }
            Write-ToolkitLog -Type ERR -Source $Name -Detail $refusal
        }
        elseif ($code) {
            throw "exit code $code"
        }
        elseif (-not $NoSuccessLog) {
            Write-ToolkitLog -Type CMD -Source $Name -Detail $Detail
        }
    }
    catch {
        $failure = $_.Exception.Message
        Write-ToolkitLog -Type ERR -Source $Name -Detail $failure
        Write-CliError -Message $failure -Hint "Run '$($Prefix)Log -Errors' for details, or '$Name -Help' for usage."
        # A failure is never exit 0. A silent non-zero exit keeps its own code; a
        # script that THREW (a terminating error under ErrorActionPreference Stop)
        # left no code at all -- the reset above made it 0 -- so NewSpace printed
        # "Error: An object at the specified path ... does not exist." and reported
        # success. The guard has just stated it, so it is exit 2, and a
        # non-interactive caller is told the same way a stated refusal tells it.
        if ($code) { $global:LASTEXITCODE = $code }
        else { $global:LASTEXITCODE = $script:StatedRefusalExitCode }
        if ($env:TOOLKIT_QUIET_STARTUP) { throw $failure }
        return
    }

    if ($refusal) {
        $global:LASTEXITCODE = $script:StatedRefusalExitCode
        if ($env:TOOLKIT_QUIET_STARTUP) { throw $refusal }
    }
}

# A refusal the WRAPPER itself states, before any script runs -- same contract,
# same two consequences: one block, and a caller that can see it failed.
function Write-WrapperRefusal {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message,
        [string]$Hint
    )
    Write-ToolkitLog -Type ERR -Source $Name -Detail $Message
    Write-CliError -Message $Message -Hint $Hint
    $global:LASTEXITCODE = $script:StatedRefusalExitCode
    if ($env:TOOLKIT_QUIET_STARTUP) { throw $Message }
}
