[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$Id,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [string]$Sprint,

    [Parameter(Mandatory = $false)]
    [string]$AssignTo,

    [Parameter(Mandatory = $false)]
    [string]$AddTag,

    [Parameter(Mandatory = $false)]
    [string]$RemoveTag,

    [Parameter(Mandatory = $false)]
    [switch]$Pin,

    [Parameter(Mandatory = $false)]
    [switch]$Unpin,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# The edit flow: change what a work item SAYS (title,
# description) or WEARS (tags, sprint, assignee) -- one verb, dispatched by
# the space's tracker like every seam (D-G4). On GitHub the words translate:
# tags are labels, the sprint is the milestone, the description is the body.
#
# -Pin / -Unpin: the TRACKER'S own pin -- `gh issue pin` / `gh issue
# unpin` -- so "stays pinned" is true on every machine and on github.com at
# once, with no second store. GitHub pins three issues per repository and
# refuses a fourth; that refusal is said in the product's own sentence. A work
# item on Azure DevOps has no pin, so there the switches are a stated refusal.

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

function Show-Help {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)EditItem -- Change what a work item says or wears" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    $(Get-CliPrefix)EditItem <id> [-Title <text>] [-Description <text>] [-Sprint <name>]" -ForegroundColor Gray
    Write-Host "                        [-AssignTo <who>] [-AddTag <a;b>] [-RemoveTag <a;b>] [-Pin | -Unpin] [-WhatIf]" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  On a GitHub space the words translate: tags are labels (sev1..3 live" -ForegroundColor Gray
    Write-Host "  here), -Sprint is the milestone, -Description is the body, -AssignTo" -ForegroundColor Gray
    Write-Host "  is a login (or @me). On ADO, tags merge read-modify-write." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -Pin / -Unpin use GitHub's own pin (three per repository), so the issue" -ForegroundColor Gray
    Write-Host "  sorts first on the Issues tab everywhere. A work item on ADO has no pin." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -WhatIf prints the exact edit and changes nothing." -ForegroundColor Gray
    Write-Host ""
}

if ($Help) { Show-Help; return }

if ($Id -le 0) {
    Write-CliError -Message "Which work item? An id is required." -Hint "Use '$(Get-CliPrefix)EditItem -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# At least one change, or there is nothing to do -- and silence would read as
# an edit that happened.
$changeKeys = @('Title', 'Description', 'Sprint', 'AssignTo', 'AddTag', 'RemoveTag', 'Pin', 'Unpin')
$asked = @($changeKeys | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($asked.Count -eq 0) {
    Write-CliError -Message "Nothing to change: no edit switch was given." `
        -Hint "Pass at least one of -Title, -Description, -Sprint, -AssignTo, -AddTag, -RemoveTag, -Pin, -Unpin."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Pin -and $Unpin) {
    Write-CliError -Message "-Pin and -Unpin ask for opposite things; $Id was not changed." `
        -Hint "Pass one of them."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
# The edit proper (gh issue edit / az boards work-item update) runs only when
# something other than the pin was asked for.
$editAsked = @($asked | Where-Object { $_ -ne 'Pin' -and $_ -ne 'Unpin' })

$splitTags = { param($raw) @("$raw" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$cfg = $global:P20Config
$org = $cfg.Org

# -- The tracker seam ----------------------------------------------------------
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $org -Projects $cfg.Projects -CliPrefix (Get-CliPrefix)
    if (-not $repoAnswer.Repo) {
        Write-CliError -Message "$($repoAnswer.Reason) Issue $Id cannot be edited." -Hint $repoAnswer.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $repoFull = $repoAnswer.Repo

    # Name the target before touching it -- the near-miss rule.
    $viewRead = Invoke-P20TrackerRead 'gh' @('issue', 'view', "$Id", '--repo', $repoFull, '--json', 'title,state,url')
    $raw = $viewRead.Out
    if ($viewRead.Code -ne 0 -or -not ($raw -join '').Trim()) {
        Write-CliError -Message "Could not fetch issue $Id from $repoFull." `
            -Hint 'Check the number and that gh is signed in (gh auth status).'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $issue = ($raw -join "`n") | ConvertFrom-Json
    Write-Host "[+] Found: $($issue.title)" -ForegroundColor Green

    $planned = @()
    $ghArgs = @('issue', 'edit', "$Id", '--repo', $repoFull)
    if ($PSBoundParameters.ContainsKey('Title'))       { $ghArgs += @('--title', $Title);        $planned += "title    -> $Title" }
    if ($PSBoundParameters.ContainsKey('Description')) { $ghArgs += @('--body', $Description);   $planned += "body     -> (rewritten, $($Description.Length) chars)" }
    if ($PSBoundParameters.ContainsKey('Sprint'))      { $ghArgs += @('--milestone', $Sprint);   $planned += "milestone-> $Sprint" }
    if ($PSBoundParameters.ContainsKey('AssignTo'))    { $ghArgs += @('--add-assignee', $AssignTo); $planned += "assignee += $AssignTo" }
    foreach ($t in (& $splitTags $AddTag))    { $ghArgs += @('--add-label', $t);    $planned += "label    += $t" }
    foreach ($t in (& $splitTags $RemoveTag)) { $ghArgs += @('--remove-label', $t); $planned += "label    -= $t" }
    if ($Pin)   { $planned += "pin      -> pinned on GitHub" }
    if ($Unpin) { $planned += "pin      -> unpinned" }
    # On stage: one line before a write to a public repository, and in -WhatIf.
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    Write-P20PublicLine -Repo $repoFull

    if ($WhatIf) {
        Write-Host ""
        Write-Host "  [WHATIF] Would edit issue #$Id in ${repoFull}:" -ForegroundColor Yellow
        $planned | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        Write-Host ""
        return
    }

    if ($editAsked.Count -gt 0) {
        $editRead = Invoke-P20TrackerRead 'gh' $ghArgs
        $out = $editRead.Lines
        if ($editRead.Code -ne 0) {
            Write-CliError -Message "Failed to edit issue ${Id}: $(@($out) -join ' ')" `
                -Hint "A label or milestone must already exist on $repoFull."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    if ($Pin -or $Unpin) {
        $pinVerb = if ($Pin) { 'pin' } else { 'unpin' }
        $pinRead = Invoke-P20TrackerRead 'gh' @('issue', $pinVerb, "$Id", '--repo', $repoFull)
        $out = $pinRead.Lines
        if ($pinRead.Code -ne 0) {
            $said = @($out) -join ' '
            # GitHub pins three issues per repository and refuses a fourth; the
            # tracker's refusal is said in the product's own sentence.
            if ($Pin -and $said -match '(?i)limit|maximum|at most|too many|three|\b3\b') {
                Write-CliError -Message "GitHub pins three issues per repository; unpin one first. Issue $Id was not pinned." `
                    -Hint "'$(Get-CliPrefix)EditItem <id> -Unpin' on one of the three, then pin this one. GitHub said: $said"
            }
            else {
                Write-CliError -Message "Failed to $pinVerb issue ${Id}: $said" `
                    -Hint 'Check the number and that gh is signed in (gh auth status).'
            }
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    Write-Host "[+] Edited issue #$Id" -ForegroundColor Green
    $planned | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host "    $($issue.url)" -ForegroundColor Cyan
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)EditItem" -Detail "issue #$Id ($repoFull): $($asked -join ', ')"
    }
    return
}

# -- The ADO half ----------------------------------------------------------------
# A work item has no pin: the switches are GitHub's, and here they are refused
# before az is asked anything.
if ($Pin -or $Unpin) {
    $pinSwitch = if ($Pin) { '-Pin' } else { '-Unpin' }
    Write-CliError -Message "A work item on Azure DevOps has no pin; $pinSwitch is for a GitHub Space. Work item $Id was not changed." `
        -Hint "Pin an issue on a GitHub Space ('$(Get-CliPrefix)EditItem <n> -Pin' there)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
# az boards work-item update; tags MERGE read-modify-write, because ADO's
# System.Tags is replace-only and dropping the tags someone else set is not
# an edit, it is a loss.
$needShow = $PSBoundParameters.ContainsKey('AddTag') -or $PSBoundParameters.ContainsKey('RemoveTag') -or $PSBoundParameters.ContainsKey('Sprint')
$current = $null
if ($needShow) {
    # The one reader of a work item (Scripts/Get-WorkItemRecord.ps1), shared with
    # NewPrompt and Status -Board.
    . (Join-Path $PSScriptRoot 'Get-WorkItemRecord.ps1')
    $record = Get-P20WorkItemRecord -Id $Id -Org $org
    if (-not $record.Ok) {
        Write-CliError -Message "Could not fetch work item $Id." -Hint "az said: $($record.Error)"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $current = $record.Item
}

$updateArgs = @('boards', 'work-item', 'update', '--id', "$Id", '--org', $org, '--output', 'json')
$fields = @()
$planned = @()
if ($PSBoundParameters.ContainsKey('Title'))       { $updateArgs += @('--title', $Title);            $planned += "title      -> $Title" }
if ($PSBoundParameters.ContainsKey('Description')) { $updateArgs += @('--description', $Description); $planned += "description-> (rewritten)" }
if ($PSBoundParameters.ContainsKey('AssignTo'))    { $updateArgs += @('--assigned-to', $AssignTo);    $planned += "assignee   -> $AssignTo" }
if ($PSBoundParameters.ContainsKey('Sprint')) {
    $iterationPath = if ($Sprint -match '\\') { $Sprint } else {
        $projName = "$($current.fields.'System.TeamProject')"
        "$projName\$Sprint"
    }
    $updateArgs += @('--iteration', $iterationPath)
    $planned += "sprint     -> $iterationPath"
}
if ($PSBoundParameters.ContainsKey('AddTag') -or $PSBoundParameters.ContainsKey('RemoveTag')) {
    $have = @("$($current.fields.'System.Tags')" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $have = @($have) + (& $splitTags $AddTag) | Select-Object -Unique
    $drop = & $splitTags $RemoveTag
    $have = @($have | Where-Object { $_ -notin $drop })
    $fields += "System.Tags=$($have -join '; ')"
    $planned += "tags       -> $($have -join '; ')"
}
if ($fields.Count -gt 0) { $updateArgs += @('--fields') + $fields }

if ($WhatIf) {
    Write-Host ""
    Write-Host "  [WHATIF] Would edit work item #${Id}:" -ForegroundColor Yellow
    $planned | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host ""
    return
}

Write-Host "[*] Editing work item $Id..." -ForegroundColor Cyan
$updateRead = Invoke-P20TrackerRead 'az' $updateArgs
$out = $updateRead.Lines
if ($updateRead.Code -ne 0) {
    Write-CliError -Message "Failed to edit work item ${Id}." -Hint "az said: $(@($out) -join ' ' | Select-Object -First 1)"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
Write-Host "[+] Edited work item #$Id" -ForegroundColor Green
$planned | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)EditItem" -Detail "work item #${Id}: $($asked -join ', ')"
}
