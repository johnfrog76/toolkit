[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [int]$Id = 0,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Comment = "",

    [Parameter(Mandatory = $false)]
    # Deliberately NOT a ValidateSet. Valid reasons come from the project's process
    # template, not from this script -- an Agile Bug accepts Obsolete and Copied to
    # Backlog, other templates differ, and a local allow-list that omits one makes
    # the command useless for the triage it exists to serve. Known shorthands are
    # mapped below; anything else is passed through and ADO decides, returning its
    # own error naming what it will accept.
    [string]$Reason = "Fixed",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Write-CliError normally comes from the module; it is what makes a refusal ONE
# block. See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}


# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}


# Configuration
$cfg = $global:P20Config
$org = $cfg.Org

# Map friendly enum names to ADO resolution reason strings
$reasonMap = @{
    "Fixed"           = "Fixed"
    "AsDesigned"      = "As Designed"
    "CannotReproduce" = "Cannot Reproduce"
    "Duplicate"       = "Duplicate"
    "WontFix"         = "Won't Fix"
    "WillNotFix"      = "Won't Fix"
    "Obsolete"        = "Obsolete"
    "CopiedToBacklog" = "Copied to Backlog"
    "Deferred"        = "Deferred"
    "Rejected"        = "Rejected"
}

function Show-Help {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)CloseItem -- Close/resolve any ADO work item" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Transitions the work item to its correct terminal state based on type:" -ForegroundColor White
    Write-Host "    Bug                          -> Resolved (default reason: Fixed)" -ForegroundColor Gray
    Write-Host "    User Story / Task / Feature -> Closed   (default reason: Completed)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    $(Get-CliPrefix)CloseItem <Id> -Comment <text> [-Reason <reason>] [-WhatIf]" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Parameters:" -ForegroundColor White
    Write-Host "    Id            Work item ID (or auto-detect from current/ prompt filename)" -ForegroundColor Gray
    Write-Host "    -Comment      Comment to post in ADO discussion (required)" -ForegroundColor Gray
    Write-Host "                  Supports [text](url) markdown links and #workItemId references" -ForegroundColor DarkGray
    Write-Host "    -Reason       Resolution reason. Applies to EVERY work item type -- default is" -ForegroundColor Gray
    Write-Host "                  Fixed for a Bug, Completed for everything else." -ForegroundColor Gray
    Write-Host "                  Known: Fixed, AsDesigned, CannotReproduce, Duplicate, WontFix,
                         WillNotFix, Obsolete, CopiedToBacklog, Deferred, Rejected
                  Anything else is passed to ADO verbatim -- the project's process
                  template decides what it accepts, not this script." -ForegroundColor DarkGray
    Write-Host "                  Each project's process defines its own Reason picklist per state," -ForegroundColor DarkGray
    Write-Host "                  and the default that works on a stock template can be rejected by" -ForegroundColor DarkGray
    Write-Host "                  a customised one. If ADO rejects it, it says so and names the field" -ForegroundColor DarkGray
    Write-Host "                  -- pass a different -Reason rather than assume the default is safe." -ForegroundColor DarkGray
    Write-Host "    -WhatIf       Print the planned transition without calling ADO" -ForegroundColor Gray
    Write-Host "    -Help         Show this help" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    $(Get-CliPrefix)CloseItem 232161 -Comment `"Fixed in [PR 140387](https://...) as part of #178497`"  # Bug -> Resolved" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)CloseItem 232271 -Comment `"Teams host sets role=application`" -Reason AsDesigned    # Bug -> Resolved" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)CloseItem 449 -Comment `"Delivered in US-448 scope`"           # User Story -> Closed" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)CloseItem 450 -Comment `"Done -- merged to main`"              # Task       -> Closed" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)CloseItem 144 -Comment `"No image feature to build against`" -Reason WillNotFix  # Story, won't fix" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)CloseItem -Comment `"Already fixed`"   # auto-detect ID from current/" -ForegroundColor DarkGray
    Write-Host ""
}

if ($Help) { Show-Help; return }

# --- Auto-detect bug ID from current/ prompt filename if not provided ---
if ($Id -eq 0) {
    $folders = Get-PromptFolders
    $currentDir = $folders.Current
    if (Test-Path $currentDir) {
        # The one id rule (Scripts/Resolve-CardName.ps1), not a private regex: this
        # used to know about "US-" and "Task" and nothing a team had configured.
        # Only a NUMBER is a work item -- a card with no work item (K7M2) has
        # nothing on a board to close, so it is not a candidate here.
        . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
        $idPattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $global:P20Config)
        $candidates = @(Get-ChildItem -Path $currentDir -Filter "*.prompt.md" |
            ForEach-Object { Get-P20CardId -Name $_.Name -Pattern $idPattern } |
            Where-Object { Test-P20IsWorkItemId $_ } |
            ForEach-Object { [int]$_ })
        if ($candidates.Count -eq 1) {
            $Id = $candidates[0]
            Write-Host "[*] Auto-detected work item ID $Id from current/" -ForegroundColor DarkGray
        }
        elseif ($candidates.Count -gt 1) {
            Write-CliError -Message "More than one card in current/ has a work item: $($candidates -join ', ')." -Hint "Name the one to close: $(Get-CliPrefix)CloseItem <id> -Comment `"...`""
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        else {
            Write-CliError -Message "No card in current/ has a work item to close." -Hint "Name it: $(Get-CliPrefix)CloseItem <id> -Comment `"...`""
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Comment)) {
    Write-CliError -Message "-Comment is required." -Hint "Example: $(Get-CliPrefix)CloseItem 232161 -Comment `"Fixed in PR 140387`""
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- A GitHub board: the same verb, gh issue close as the transition ---------
# GitHub closes an issue one of two
# ways -- completed, or not planned -- where an ADO process template accepts
# whatever it defines. The known shorthands map onto the two; a word that maps
# to neither is refused with both named, because "pass it verbatim and let the
# tracker decide" has nothing to pass it to here. The comment stays MARKDOWN:
# GitHub renders links and #n references natively, so the ADO HTML conversion
# below never runs on this path.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
# Which space, which tracker, before the id is sent anywhere.
#
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $org -Projects $cfg.Projects -CliPrefix (Get-CliPrefix)
    if (-not $repoAnswer.Repo) {
        Write-CliError -Message "$($repoAnswer.Reason) Issue $Id cannot be closed." -Hint $repoAnswer.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $repoFull = $repoAnswer.Repo

    $notPlannedWords = @('AsDesigned', 'CannotReproduce', 'Duplicate', 'WontFix', 'WillNotFix',
        'Obsolete', 'CopiedToBacklog', 'Deferred', 'Rejected', 'NotPlanned', 'Not planned')
    $ghReason = if (-not $PSBoundParameters.ContainsKey('Reason') -or $Reason -in @('Fixed', 'Completed')) { 'completed' }
    elseif ($Reason -in $notPlannedWords) { 'not planned' }
    else { $null }
    if (-not $ghReason) {
        Write-CliError -Message "GitHub closes an issue as 'completed' or 'not planned'; '$Reason' maps to neither." `
            -Hint "Use -Reason Completed (the default), or one of: $($notPlannedWords[0..8] -join ', ') -- all of which close as not planned."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    Write-Host "[*] Closing issue $Id..." -ForegroundColor Cyan
    $viewRead = Invoke-P20TrackerRead 'gh' @('issue', 'view', "$Id", '--repo', $repoFull, '--json', 'title,state,url')
    $raw = $viewRead.Out
    if ($viewRead.Code -ne 0 -or -not ($raw -join '').Trim()) {
        Write-CliError -Message "Could not fetch issue $Id from $repoFull." `
            -Hint 'Check the number and that gh is signed in (gh auth status).'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $issue = ($raw -join "`n") | ConvertFrom-Json
    $issueState = "$($issue.state)".ToUpperInvariant()
    Write-Host "[+] Found: $($issue.title)" -ForegroundColor Green
    Write-Host "    Type: Issue  |  Current state: $($issueState.ToLowerInvariant())" -ForegroundColor Gray
    # On stage: a public repository's comment is read by strangers. One
    # line before the write, and in -WhatIf; nothing is asked.
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    Write-P20PublicLine -Repo $repoFull

    if ($WhatIf) {
        Write-Host ""
        Write-Host "  [WhatIf] No changes will be made." -ForegroundColor Yellow
        if ($issueState -eq 'CLOSED') {
            Write-Host "  [WhatIf] Already closed -- state change would be skipped; comment would still post." -ForegroundColor Yellow
        }
        else {
            Write-Host "  [WhatIf] Would close issue #$Id as $ghReason" -ForegroundColor Yellow
        }
        Write-Host "  [WhatIf] Would post comment: $Comment" -ForegroundColor Yellow
        Write-Output "[RESULT] workItemType=Issue targetState=closed reason=$ghReason whatIf=true"
        return
    }

    if ($issueState -eq 'CLOSED') {
        Write-Host "[!] Issue is already closed. Skipping state change." -ForegroundColor Yellow
        $commentRead = Invoke-P20TrackerRead 'gh' @('issue', 'comment', "$Id", '--repo', $repoFull, '--body', $Comment)
        if ($commentRead.Code -eq 0) { Write-Host "[+] Posted comment" -ForegroundColor Green }
        else {
            # A notice, exit 0: the state asked for is already true.
            Write-Host "[!] Failed to post comment. The issue stays closed; add it on GitHub." -ForegroundColor Yellow
        }
    }
    else {
        # One call closes and comments together.
        $closeRead = Invoke-P20TrackerRead 'gh' @('issue', 'close', "$Id", '--repo', $repoFull, '--reason', $ghReason, '--comment', $Comment)
        if ($closeRead.Code -ne 0) {
            Write-CliError -Message "Failed to close issue $Id." `
                -Hint "Nothing was changed. Check gh auth status, or $(Get-CliPrefix)Log -Errors."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        Write-Host "[+] Closed issue #$Id as $ghReason, with the comment" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[+] Done. Issue: $($issue.url)" -ForegroundColor Cyan
    Write-Output "[RESULT] workItemType=Issue targetState=closed reason=$ghReason"
    return
}

# Convert markdown links [text](url) to HTML <a href="url">text</a>
$Comment = [regex]::Replace($Comment, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')

# Convert #workItemId references to ADO work item links
$Comment = [regex]::Replace($Comment, '#(\d{4,})', '<a href="' + $org + '/_workitems/edit/$1">#$1</a>')

# --- Get bearer token ---
Write-Host "[*] Closing work item $Id..." -ForegroundColor Cyan

. (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
$tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
if (-not $tokenRead.Ok) {
    # A stated refusal, not a bare return: exit 0 here reported success to the
    # bridge and to any script checking $LASTEXITCODE. az exiting non-zero is a
    # failure even when it printed something: its "ERROR: ..." is not a token.
    Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$adoToken = $tokenRead.Token

$headers = Get-P20AdoHeaders -Token $adoToken -ContentType 'application/json-patch+json'

# --- Fetch current work item state ---
try {
    $wiUri = "$org/_apis/wit/workitems/$($Id)?api-version=7.1"
    $wi = Invoke-RestMethod -Uri $wiUri -Headers @{ Authorization = "Bearer $adoToken" } -Method Get
    $currentState = $wi.fields.'System.State'
    $title = $wi.fields.'System.Title'
    $workItemType = $wi.fields.'System.WorkItemType'
    Write-Host "[+] Found: $title" -ForegroundColor Green
    Write-Host "    Type: $workItemType  |  Current state: $currentState" -ForegroundColor Gray
}
catch {
    Write-CliError -Message "Could not fetch work item $Id." -Hint "Check the id and the active Space ($(Get-CliPrefix)SwitchSpace Status). ADO said: $($_.Exception.Message)"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# --- Determine correct terminal state + reason for this work item type ---
# A function, not inline, so the transition rule can be tested without ADO.
#
# Bugs use Resolved; everything else uses Closed. -Reason now applies to BOTH --
# it used to be silently ignored for non-Bug types in favor of a hardcoded
# "Completed", which this project's process rejects outright: "Completed" is not
# a defined System.Reason value for a Closed User Story here, and the PATCH
# failed with a 400 whose real message the old catch block did not surface.
# "Completed" is still the default for non-Bugs -- it is correct on a stock
# process and correct for the common case (the work shipped) -- but a caller who
# passes -Reason now gets exactly what they asked for, on any type, the same way
# a Bug always has.
function Get-CloseTransition {
    param(
        [string]$WorkItemType,
        [string]$Reason,
        # NOT "was $Reason different from its default" -- the param default IS
        # "Fixed", so comparing the value cannot tell "the caller typed
        # -Reason Fixed" apart from "the caller did not pass -Reason at all",
        # and only the second case should fall through to the non-Bug default.
        # The caller passes $PSBoundParameters.ContainsKey('Reason') for this.
        [bool]$ReasonWasSpecified,
        [hashtable]$ReasonMap
    )

    $targetState = if ($WorkItemType -eq "Bug") { "Resolved" } else { "Closed" }

    if ($ReasonWasSpecified) {
        $requestedReason = $Reason
    }
    elseif ($WorkItemType -eq "Bug") {
        $requestedReason = "Fixed"
    }
    else {
        $requestedReason = "Completed"
    }

    # Shorthand if we know it, verbatim if we do not -- see the note on $Reason.
    $adoReason = if ($ReasonMap.ContainsKey($requestedReason)) { $ReasonMap[$requestedReason] } else { $requestedReason }

    return @{ TargetState = $targetState; AdoReason = $adoReason }
}

$transition  = Get-CloseTransition -WorkItemType $workItemType -Reason $Reason `
    -ReasonWasSpecified $PSBoundParameters.ContainsKey('Reason') -ReasonMap $reasonMap
$targetState = $transition.TargetState
$adoReason   = $transition.AdoReason

# --- Dry-run: print the planned transition and stop before any write ---
if ($WhatIf) {
    Write-Host ""
    Write-Host "  [WhatIf] No changes will be made." -ForegroundColor Yellow
    if ($currentState -eq "Resolved" -or $currentState -eq "Closed") {
        Write-Host "  [WhatIf] Already $currentState -- state change would be skipped; comment would still post." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [WhatIf] Would set $workItemType #$Id : $currentState -> $targetState ($adoReason)" -ForegroundColor Yellow
    }
    Write-Host "  [WhatIf] Would post comment: $Comment" -ForegroundColor Yellow
    Write-Output "[RESULT] workItemType=$workItemType targetState=$targetState reason=$adoReason whatIf=true"
    return
}

if ($currentState -eq "Resolved" -or $currentState -eq "Closed") {
    Write-Host "[!] Work item is already $currentState. Skipping state change." -ForegroundColor Yellow
}
else {
    # --- Update state to the type-appropriate terminal state with reason ---
    # ADO requires System.Reason (not Microsoft.VSTS.Common.ResolvedReason)
    # in the same PATCH as System.State for the transition to succeed.
    $patchBody = @(
        @{ op = "add"; path = "/fields/System.State"; value = $targetState }
        @{ op = "add"; path = "/fields/System.Reason"; value = $adoReason }
    ) | ConvertTo-Json -Depth 3

    # $_.Exception.Message on a failed Invoke-RestMethod is just "400 (Bad
    # Request)" -- ADO puts the actual reason in the response body, on
    # $_.ErrorDetails.Message as a JSON blob. A function, not inline, so the
    # parsing can be tested against a captured body without a live failure.
    # Without this, a rejected Reason value looked identical to auth failing, a
    # bad work item id, or the API being down.
    function Get-AdoErrorMessage {
        param([string]$RawErrorDetails)
        if (-not $RawErrorDetails) { return $null }
        try { return ($RawErrorDetails | ConvertFrom-Json).message }
        catch { return $null }
    }

    try {
        $patchUri = "$org/_apis/wit/workitems/$($Id)?api-version=7.1"
        Invoke-RestMethod -Uri $patchUri -Headers $headers -Method Patch -Body $patchBody | Out-Null
        Write-Host "[+] Set state to $targetState ($adoReason)" -ForegroundColor Green
    }
    catch {
        $adoMessage = if ($_.ErrorDetails) { Get-AdoErrorMessage $_.ErrorDetails.Message } else { $null }
        $displayMessage = if ($adoMessage) { $adoMessage } else { $_.Exception.Message }
        # A failure, not a notice: nothing changed on the board, and a caller
        # checking the exit code -- the bridge, a batch -- must see that.
        $hint = if ($adoMessage -and $adoMessage -match "not in the list of supported values") {
            "This project's process does not accept reason '$adoReason' for $workItemType -> $targetState. Pass a -Reason it accepts (check an existing $targetState $workItemType in this project)."
        } else { "Nothing was changed. Check $(Get-CliPrefix)Log -Errors, or retry." }
        Write-CliError -Message "Failed to update work item state: $displayMessage" -Hint $hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

# --- Post comment ---
$commentHeaders = @{
    Authorization  = "Bearer $adoToken"
    "Content-Type" = "application/json"
}

try {
    $project = $wi.fields.'System.TeamProject'
    $commentUri = "$org/$([Uri]::EscapeDataString($project))/_apis/wit/workItems/$Id/comments?api-version=7.1-preview"
    $commentBody = @{ text = $Comment } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Uri $commentUri -Headers $commentHeaders -Method Post -Body $commentBody | Out-Null
    Write-Host "[+] Posted comment to discussion" -ForegroundColor Green
}
catch {
    # A notice, and exit 0, on purpose: the transition -- the thing asked for --
    # has already happened, and a non-zero exit would tell a batch to retry a
    # close that succeeded. It says plainly what is missing instead.
    Write-Host "[!] Failed to post comment: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    The work item was closed; the comment was not posted. Add it on the board." -ForegroundColor Gray
}

Write-Host ""
Write-Host "[+] Done. ADO: $org/$([Uri]::EscapeDataString($project))/_workitems/edit/$Id" -ForegroundColor Cyan

# Structured result line for callers (wrapper / agent) to parse and log.
# Emitted on the success stream so the in-process wrapper can capture it via
# variable assignment; Write-Host messages above still render to the console.
Write-Output "[RESULT] workItemType=$workItemType targetState=$targetState reason=$adoReason"
