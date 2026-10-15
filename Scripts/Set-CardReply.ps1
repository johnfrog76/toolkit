<#
.SYNOPSIS
    Fills a thread's `Reply:` slot in a card. Dot-source it.

.DESCRIPTION
    Not a command. GetPRComments writes one block per comment under
    `### Comment N (Thread T)`, each with an empty `Reply:` slot and a
    `Status:` line. ReplyPR posted to ADO and stopped, so the slot stayed
    empty and the reply lived only in the tracker -- the card stopped being the
    record from the other end.

    Set-P20CardReply fills the FIRST empty `Reply:` slot in the thread's blocks
    (a thread can have several comments; the reply answers the latest unanswered
    one) and, when asked, rewrites the block's `Status:` line. Through
    Write-CardText: the file keeps its line endings, no BOM.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

function Set-P20CardReply {
    <#
        Returns $true when the card was written, $false when the thread has no
        block or no empty slot (the caller says so; it is not a failure).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$ThreadId,
        [Parameter(Mandatory = $true)][string]$Reply,
        [string]$Status = ''
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $lines = [System.Collections.Generic.List[string]]($text -split "`n")
    $heading = '^###\s+Comment\s+\d+\s+\(Thread\s+' + [regex]::Escape([string]$ThreadId) + '\)\s*$'
    $oneLine = ($Reply -replace "\r?\n", ' ').Trim()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch $heading) { continue }
        # The block runs to the next heading or rule.
        $end = $lines.Count
        for ($j = $i + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^(###\s|---\s*$|## )') { $end = $j; break } }
        $slot = -1
        for ($j = $i + 1; $j -lt $end; $j++) { if ($lines[$j] -match '^Reply:\s*$') { $slot = $j; break } }
        if ($slot -lt 0) { continue }   # answered already; try the thread's next block
        $lines[$slot] = "Reply: $oneLine"
        if ($Status) {
            for ($j = $i + 1; $j -lt $end; $j++) { if ($lines[$j] -match '^Status:\s') { $lines[$j] = "Status: $Status"; break } }
        }
        Write-CardText -Path $Path -Content (($lines -join "`n"))
        return $true
    }
    return $false
}
