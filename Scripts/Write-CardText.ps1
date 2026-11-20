<#
.SYNOPSIS
    The one byte contract for a file this tool writes into the user's hub.
    Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry.

    It lived inside Scripts/Add-ClosedStamp.ps1 while the stamp was the only
    thing that wrote a hub file byte-for-byte. It is not any more: the
    communication module's session writers create and rewrite
    `manager/current/<date>.md`, and they were writing a BOM, so a session's
    first three bytes depended on which verb touched it last -- `New-Meeting`
    and `MeetingAgenda` put one on, `MeetingAgenda -Close` took it off on the
    way past. That is the exact shape `Archive` had before the card contract
    landed.

    So the writer moved out to its own file, named after itself, and
    Add-ClosedStamp.ps1 dot-sources it like everyone else. The callers now:
    Move-PromptToArchive.ps1 and Get-MeetingAgenda.ps1 through the stamp (both
    EDITS); New-Meeting.ps1, Get-MeetingAgenda.ps1, New-PromptFromWorkItem.ps1,
    New-GrowthItem.ps1, Write-PeerReviewLog.ps1 and Generate-Review.ps1 directly.
    Every one of those last six CREATES, and passes -New.

    THE CONTRACT, in one place:

      - UTF-8, NO BOM, always.
      - A file the tool CREATES is LF        -- Write-CardText -New.
      - A file the tool EDITS keeps the terminator it already has -- no -New.
        The WRITER reads the file's own bytes to decide, so no caller has to.

    The switch is the whole contract, because the writer used to take
    the string it was given byte for byte and let "the content decide", which
    made the two halves impossible to hold at once on Windows: `* text=auto`
    plus core.autocrlf=true checks templates/*.template.md out CRLF, and the
    here-strings in the card and growth builders are CRLF in the same clone, so
    every CREATE came out CRLF there and LF on macOS. One hub written from
    both machines then churned line endings by machine -- the exact thing the
    contract exists to stop.

    -New normalises CRLF to LF once, here, so it fixes the template readers and
    the here-string builders together and needs no checkout rule. Pinning
    templates/*.md eol=lf in .gitattributes would have fixed only the first
    kind. An EDIT is normalised to LF and then converted to whatever the file
    on disk uses, which is what keeps the second half true whatever the caller
    passed in: a hub file that was CRLF before the edit is CRLF after it, on
    every line. docs/CLI.md, "The bytes a card is written with", is the
    reader-facing half.

    Dot-sourced rather than reached through utilities.psm1 because every caller
    has to work as a plain script with no module imported: that is how their
    test suites drive them.

        . (Join-Path $PSScriptRoot 'Write-CardText.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

function Write-CardText {
    <#
        The one way this package writes a file into the user's hub.

        UTF8Encoding($false) -- no BOM -- through [System.IO.File]::WriteAllText,
        because Set-Content -Encoding UTF8 means two different things: Windows
        PowerShell 5.1 emits a BOM and PowerShell 7 does not. The same verb on
        the same card produced different bytes depending on which shell ran it,
        and on a hub with storeSync: git that is a whole-file diff on every
        archive from 5.1. Prompt20Toolkit/Update-ToolkitManifest.ps1 uses this
        pattern for exactly the same reason.

        -New says this call CREATES the file, and a created file is LF: the
        content is normalised here and nowhere else, so no caller has to
        remember to do it and none of them can disagree about how. Without
        -New this is an EDIT and the content goes out byte for byte, which is
        how a file keeps the terminator it already has.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the caller owns the ShouldProcess decision.')]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [switch]$New
    )
    $text = $Content
    if ($New) { $text = $text -replace "`r`n", "`n" }
    elseif (Test-Path -LiteralPath $Path) {
        $text = $text -replace "`r`n", "`n"
        # An EDIT keeps the terminator the file already has -- decided HERE, from
        # the bytes on disk, not by whichever caller remembered to.
        # An edit used to go out byte for byte, so four callers carried their
        # own copy of this rule and four did not, and a CRLF card came back with
        # one bare-LF line after every Sync, GetPRComments and NewPR.
        #A file
        # that contains any CRLF is CRLF; a mixed file is made consistent.
        $existing = [System.IO.File]::ReadAllText($Path)
        if ($existing.Contains("`r`n")) { $text = $text -replace "`n", "`r`n" }
    }
    # No -New and no file: nothing on disk to follow, so the content decides,
    # byte for byte -- the shape the Archive suite pins for this edge.
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-CardText {
    <#
        The read half of the same contract: a hub file is UTF-8, so it is read
        as UTF-8, on every host.

        Get-Content with no -Encoding reads a file with no BOM in the system's
        ANSI code page under Windows PowerShell 5.1 and as UTF-8 under 7. A
        caller that read a card that way and wrote it back through
        Write-CardText turned every non-ASCII character into two or three,
        permanently, and only on the floor. A BOM, where a file has one, still
        wins and is not part of the text.

        -Lines returns the lines, split on LF or CRLF and nothing else -- a bare
        CR inside a line stays in it, where Get-Content made it a line break --
        with no empty last element for the file's final newline. Always an
        array, so a one-line file indexes as a line and not as its characters.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Lines
    )
    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
    if (-not $Lines) { return $text }
    $parts = [string[]]($text -split "`r?`n")
    if ($parts.Length -gt 0 -and $parts[$parts.Length - 1] -eq '') {
        if ($parts.Length -eq 1) { $parts = [string[]]@() } else { $parts = [string[]]$parts[0..($parts.Length - 2)] }
    }
    return , $parts
}
