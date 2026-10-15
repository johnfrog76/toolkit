<#
.SYNOPSIS
    The one implementation of the "**Closed:**" stamp. Dot-source it.

.DESCRIPTION
    Not a command -- there is no alias, no menu row and no help entry for this
    file. It exists so that the stamp has exactly one writer.

    The byte contract it writes with -- UTF-8, no BOM, the line ending the file
    already uses -- lives in Write-CardText, which moved to its own file when
    the manager module's session writers became callers of it too. This file
    dot-sources it; see Scripts/Write-CardText.ps1.

    The stamp is load-bearing: `agent/ado/reporting.py` derives a billing
    timeline by reading "**Closed:** yyyy-mm-dd" out of archived cards, and the
    web's session cards look for it too -- so the literal is a contract between
    THREE halves and lives in `consts.json` (`stamps.closed`), not in this file.
    The date format and the rule that an existing stamp is never rewritten are
    part of the same contract, not a formatting choice. It was
    written in one place (Move-PromptToArchive.ps1) until
    MeetingAgenda -Close became the second thing that retires a file -- and a
    second copy of a contract is how the two drift.

    Dot-sourced rather than reached through utilities.psm1 because both callers
    have to work as a plain script with no module imported: that is how both of
    their test suites drive them.

        . (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')

function Add-ClosedDate {
    <#
        Writes "**Closed:** yyyy-MM-dd" into a retired file (docs/CLI.md, "The two dates a card carries, and the cards that never got them").

        Idempotent by design: if the line is already there, the ORIGINAL date
        stands. Re-archiving a card must not rewrite when it actually closed.

        Never throws. The contract of the verb that calls this is "the file is
        no longer in current/" -- the stamp is valuable but it is not the
        promise, so a failure here is reported and the move still succeeds.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        # -Encoding UTF8 on the way in as well as the way out: without it,
        # Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page and
        # a card with an emoji or a curly quote in it comes back mangled -- and
        # this function writes back everything it read.
        $stamp = (Get-P20Consts).stamps.closed

        $content = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ($content -match ('(?m)^' + [regex]::Escape($stamp))) { return }

        # Append in the terminator the file already uses. The stamp used to be
        # appended with a bare "`n" whatever it was joining, so every archived
        # card on a Windows hub ended with one LF line after its CRLF ones, and
        # the next editor to touch the file normalised the lot -- an archive
        # commit full of churn that is not the stamp.
        $eol = "`n"
        if ($content -match "`r`n") { $eol = "`r`n" }

        if ($content -and -not $content.EndsWith("`n")) { $content += $eol }
        $content += $stamp + ' ' + (Get-Date -Format 'yyyy-MM-dd') + $eol
        Write-CardText -Path $Path -Content $content
    }
    catch {
        $name = Split-Path $Path -Leaf
        Write-Warning "Could not stamp closed date into ${name}: $($_.Exception.Message)"
    }
}
