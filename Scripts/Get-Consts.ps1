#
# The CLI's reader for consts.json -- the package's contract file.
#
# NOT a runnable verb: this file is DOT-SOURCED, by utilities.psm1 at import and
# by any standalone script that needs a cross-half literal while running with no
# module in the session (a test sandbox, `pwsh -File`). That is why it is one
# file rather than a function inside the module: there must be exactly one
# implementation of "what does the contract say", and both kinds of caller have
# to be able to reach it.
#
#     . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
#     $C = Get-P20Consts
#     $C.stamps.closed
#
# PowerShell 5.1 floor: ConvertFrom-Json WITHOUT -AsHashtable, which 5.1 does
# not have. What comes back is a PSCustomObject tree, addressed with dots.
#
# Read ONCE per session and cached. The file is small, but a script that asks
# for one literal should not pay for a disk read, and every caller holding the
# same object is what makes "one place" true at runtime as well as in the tree.
#
# A missing or malformed consts.json is FATAL by design -- it is not
# configuration with a sensible default, it is the contract the three halves
# agree on, and guessing at it is how two halves quietly stop agreeing.
#

$script:P20ConstsCache = $null

function Get-P20ConstsPath {
    # Scripts/ -> package root. Callers may override for a test fixture.
    return (Join-Path (Split-Path $PSScriptRoot -Parent) 'consts.json')
}

function Get-P20Consts {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Refresh
    )
    if ($script:P20ConstsCache -and -not $Refresh -and -not $Path) {
        return $script:P20ConstsCache
    }
    if (-not $Path) { $Path = Get-P20ConstsPath }
    if (-not (Test-Path $Path)) {
        throw "consts.json not found at $Path. It is the package's contract file and has no default."
    }
    $parsed = (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    if (-not $Path -or $Path -eq (Get-P20ConstsPath)) { $script:P20ConstsCache = $parsed }
    return $parsed
}
