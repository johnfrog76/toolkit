<#
.SYNOPSIS
    Sets, changes or removes ONE `**Label:** value` line in a card's footer.
.DESCRIPTION
    A card's footer is a short run of bold-label lines -- Sprint, Story Points,
    ADO Link, Created, and after Archive, Closed. A verb that adds one to a card
    that already exists goes through here, so that there is one answer to where
    the line goes, and one to what bytes the card is written with:

      - the line already exists  -> its value is replaced, in place
      - it does not, and -InsertAfter names a line the card has
                                 -> it is inserted directly BELOW the first such
                                    line (Tag puts `Tags:` under `Priority:`, in
                                    `## Work Item Info`, where every template has it)
      - it does not              -> it is inserted directly ABOVE `**Created:**`,
                                    so Created / Closed stay the last two lines
                                    every reader of the footer expects
      - there is no Created line -> it is appended, after one blank line
      - -Remove                  -> the line is deleted, and nothing else moves

    The card keeps the line terminator it already has and is written through
    Write-CardText: UTF-8, no BOM (AGENTS.md, "One byte contract for a card").
    An unchanged card is NOT written -- the function returns $false and the
    file's modified time, which Home sorts by, does not move.
#>

if (-not (Get-Command Write-CardText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
}
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Set-P20CardLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        # The label exactly as the card carries it, e.g. '**Billable:**'.
        [Parameter(Mandatory = $true)][string]$Stamp,
        [string]$Value,
        [switch]$Remove,
        # Where a NEW line goes when the card has none: below the first line matching
        # one of these patterns, tried in order; else the footer rule above.
        [string[]]$InsertAfter = @()
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    $eol = "`n"
    if ($raw.Contains("`r`n")) { $eol = "`r`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($raw -replace "`r`n", "`n").Split("`n")) { [void]$lines.Add($l) }

    $lineRx = '^' + [regex]::Escape($Stamp)
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $lineRx) { $at = $i; break }
    }

    if ($Remove) {
        if ($at -lt 0) { return $false }
        $lines.RemoveAt($at)
    }
    else {
        $wanted = "$Stamp $Value".TrimEnd()
        if ($at -ge 0) {
            if ($lines[$at] -ceq $wanted) { return $false }
            $lines[$at] = $wanted
        }
        else {
            $afterAt = -1
            foreach ($rx in @($InsertAfter)) {
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match $rx) { $afterAt = $i; break }
                }
                if ($afterAt -ge 0) { break }
            }
            $createdRx = '^' + [regex]::Escape((Get-P20Consts).stamps.created)
            $createdAt = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $createdRx) { $createdAt = $i; break }
            }
            if ($afterAt -ge 0) {
                $lines.Insert($afterAt + 1, $wanted)
            }
            elseif ($createdAt -ge 0) {
                $lines.Insert($createdAt, $wanted)
            }
            else {
                # No footer to join: end of file, after one blank line, keeping
                # the file's single trailing newline.
                while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
                [void]$lines.Add('')
                [void]$lines.Add($wanted)
                [void]$lines.Add('')
            }
        }
    }

    Write-CardText -Path $Path -Content ($lines -join $eol)
    return $true
}
