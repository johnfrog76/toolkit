<#
.SYNOPSIS
    The one writer of a session's "Sent to <recipient>: <date>" line. Dot-source it.

.DESCRIPTION
    Not a command. The ## Sent section of a meeting record is the record that
    a message went out. The web button wrote it (through PUT /api/manager) and
    a send from the terminal did not, so an assistant following
    agentic/manager1on1.prompt.md had to add the line itself.
    The literal is the contract's -- consts.json stamps.sent -- read by the web
    button and by this file, so the two never disagree about the line.

    Through Write-CardText: the file keeps its line endings, no BOM.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-Consts.ps1') }

function Add-P20SentLine {
    <#
        Appends "Sent to <Recipient>: <Date>" under ## Sent, creating the section
        at the end of the file when the record has none. Returns the line written.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Recipient,
        [Parameter(Mandatory = $true)][string]$Date
    )
    $line = "$((Get-P20Consts).stamps.sent) ${Recipient}: $Date"
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $lines = [System.Collections.Generic.List[string]]($text -split "`n")
    # A trailing terminator splits into one empty last element; drop it and
    # put one back on the way out.
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $sentAt = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s+Sent\s*$') { $sentAt = $i; break } }
    if ($sentAt -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add('## Sent')
        $lines.Add('')
        $lines.Add($line)
    }
    else {
        # The end of the section: the next heading, or the end of the file.
        $end = $lines.Count
        for ($i = $sentAt + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,6}\s') { $end = $i; break } }
        # Insert after the last non-empty line of the section.
        $insertAt = $sentAt + 1
        for ($i = $sentAt + 1; $i -lt $end; $i++) { if ($lines[$i].Trim() -ne '') { $insertAt = $i + 1 } }
        if ($insertAt -eq $sentAt + 1 -and $insertAt -lt $lines.Count -and $lines[$insertAt] -eq '') { $insertAt++ }
        $lines.Insert($insertAt, $line)
        # A blank line before the next heading, so the section stays a section.
        if ($insertAt + 1 -lt $lines.Count -and $lines[$insertAt + 1] -match '^#{1,6}\s') { $lines.Insert($insertAt + 1, '') }
    }
    Write-CardText -Path $Path -Content (($lines -join "`n") + "`n")
    return $line
}
