#
# The one way a script turns a request body into what goes on the wire: the
# UTF-8 bytes of the text, with no BOM. NOT a runnable verb: DOT-SOURCED, by
# Get-AdoToken.ps1 (so every Azure DevOps caller has it) and by every other
# script that sends a body.
#
#     . (Join-Path $PSScriptRoot 'ConvertTo-Utf8Body.ps1')
#     Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body (ConvertTo-P20Utf8Body $json)
#
# Why bytes and not a string: Windows PowerShell 5.1 does not send a string
# -Body as UTF-8 -- not with no charset in the content type, and not with
# charset=utf-8 in the -Headers either (the CloseWorkItem suite reads it off a
# loopback listener) -- so an accented letter reached the server as a byte that
# is not UTF-8, and anything past U+00FF as '?'. ConvertTo-Json on 5.1
# leaves such characters unescaped, so the text of a title or a comment was
# altered on its way out. A byte array is sent as it is, on every host. The
# headers still say charset=utf-8, so the server reads the bytes as what they are.
#
# Test-Portability's Clause 18 holds every -Body in Scripts/ to this function.
#
# PowerShell 5.1 clean; reads no module state.
#
function ConvertTo-P20Utf8Body {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Text)
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
    # The comma keeps the array whole: without it the pipeline hands the caller
    # one byte at a time, and -Body would receive an object array.
    return , $bytes
}
