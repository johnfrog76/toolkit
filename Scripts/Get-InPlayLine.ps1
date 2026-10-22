#
# The WIP line: how many cards are in play, and whether that is past the number
# this machine said it wants to stay under.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Get-PromptStatus.ps1
# and by the suite that holds the table (Tests/Test-Status.ps1). One function so
# the words exist once on the CLI side; the web board draws the same facts from
# the same /env field (agent/core/env.py, `inPlayLimit`).
#
# THE LIMIT IS A LINE THE PRODUCT SAYS, NEVER A GATE ("limit doesn't mean slow it
# down, it means more focus"). Nothing here refuses, blocks a pull or hides a
# card; the line is information and the card is still created, moved and shown.
#
#   limit unset (null, zero or not a number)   -> no line at all (opt in)
#   count at or under the limit                -> "in play: 4"
#   count past the limit                       -> "in play: 7 of 5"
#
# "of N" is said only past the limit: under it the number is a count, and the
# limit has nothing to warn about.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

function Get-P20InPlayLimit {
    <#
      The limit as a positive whole number, or $null when there is none. Zero and
      a negative are no limit: a limit of nothing would warn on every card.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    $parsed = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) { return $null }
    if ($parsed -lt 1) { return $null }
    return $parsed
}

function Get-P20InPlayLine {
    <#
      Returns @{ Line = <string or ''>; Past = <bool> }. Line is empty when no
      limit is set.
    #>
    param(
        [int]$Count,
        $Limit = $null
    )
    $n = Get-P20InPlayLimit -Value $Limit
    if ($null -eq $n) { return @{ Line = ''; Past = $false } }
    if ($Count -gt $n) { return @{ Line = "in play: $Count of $n"; Past = $true } }
    return @{ Line = "in play: $Count"; Past = $false }
}
