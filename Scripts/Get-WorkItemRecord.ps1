<#
.SYNOPSIS
    One read of a work item from Azure DevOps, and the board states Status -Board
    judges by. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    `az boards work-item show --id --org --output json` was typed twice, in
    NewPrompt (to scaffold a card) and in EditItem (to merge tags), each with its
    own idea of what a failure looks like. `Status -Board` is the third reader,
    and it is the one that must not write a third copy: this is the one place the
    call is made. It is READ-ONLY by construction -- `show`, never `update`.

    Get-P20WorkItemRecord answers with an object and never throws or exits, so a
    caller decides what a failure means for it: EditItem and NewPrompt refuse,
    Status -Board shows `(unavailable)` for that one card and goes on.

      Ok     $true when az answered with JSON
      Item   the parsed work item (fields.'System.State', ...), or $null
      State  fields.'System.State', or '' when there is none
      Raw    what az printed on stdout (for a caller that shows it)
      Error  one line saying what went wrong, '' when Ok

    Test-P20BoardStateClosed and Get-P20BoardMismatch are the rule Status -Board
    flags by, and they flag only the two DEFINITE mismatches: an archived card
    whose item is still open, and a card in current/ whose item is closed. The
    lane mapping between a local Code Review and any ADO state is not defined by
    this product and is not invented here: every other pairing is shown, not
    judged.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

# The states of a work item that mean the work is over, across the process
# templates Agile, Scrum, Basic and CMMI use. Only this half reads them (the
# agent does not join against the board), so they live here and not in consts.json.
$script:P20BoardClosedStates = @('Closed', 'Done', 'Removed', 'Resolved')

function Get-P20WorkItemRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Org
    )
    $result = [pscustomobject]@{ Ok = $false; Item = $null; State = ''; Raw = ''; Error = '' }
    $read = Invoke-P20TrackerRead 'az' @('boards', 'work-item', 'show', '--id', $Id, '--org', $Org, '--output', 'json')
    $code = $read.Code
    # stdout and stderr are told apart: a WARNING on stderr must not reach the
    # JSON parser, and an error's text is what the caller's hint quotes.
    $errText = @($read.Err)
    $out = @($read.Out | Where-Object { "$_" -notmatch '^WARNING:' })
    $result.Raw = $out -join "`n"
    if ($code -ne 0 -or -not $result.Raw.Trim()) {
        $said = (@($errText) + @($out)) -join ' '
        $result.Error = if ($said.Trim()) { $said.Trim() } else { "az exited with code $code and printed nothing" }
        return $result
    }
    try { $result.Item = $result.Raw | ConvertFrom-Json }
    catch {
        $result.Error = 'az answered with something that is not JSON'
        return $result
    }
    $result.State = "$($result.Item.fields.'System.State')"
    $result.Ok = $true
    return $result
}

function Test-P20BoardStateClosed {
    param([AllowNull()][AllowEmptyString()][string]$State)
    if (-not $State) { return $false }
    return ($script:P20BoardClosedStates -contains $State.Trim())
}

function Get-P20BoardMismatch {
    <#
        $true only for the two definite mismatches. -Folder is the folder the card
        is in ('current' or 'archive', consts.json folders). An unknown state is
        never a mismatch.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [AllowNull()][AllowEmptyString()][string]$State
    )
    if (-not $State) { return $false }
    $closed = Test-P20BoardStateClosed $State
    if ($Folder -eq (Get-P20Consts).folders.archive) { return (-not $closed) }
    if ($Folder -eq (Get-P20Consts).folders.current) { return $closed }
    return $false
}
