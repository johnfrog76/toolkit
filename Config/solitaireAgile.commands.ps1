# The Solitaire Agile add-on's wrappers: Standup (M0), Triage and Route (V1),
# StartWork (AR-1).
#
# Dot-sourced by the module-command loader, and only when the top-level
# features.solitaireAgile is true -- so a switched-off module defines no
# function, which is what makes "off means absent" true of the CLI half as well
# as the web.
#
# Same pattern as organize's: -Help renders from the shared help table, the
# body runs the script in Scripts/ with the caller's own bound parameters through
# the one guard, and nothing here decides anything.

# The package root, derived from this file's own location: Config/ -> <repo>.
$global:P20SolitaireAgileRoot = Split-Path -Parent $PSScriptRoot

function global:Get-P20Standup {
    <# Standup -- today's standup, derived from the tracker; -Remind sets the reminder to attend. #>
    [CmdletBinding()]
    param(
        [string]$Space,
        [switch]$AsJson,
        [switch]$Brief,
        [string]$Grain,
        [string]$Remind,
        [string[]]$Days,
        [switch]$Walk,
        [string]$Since,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Standup'; return }
    $detail = 'ok'
    if ($PSBoundParameters.ContainsKey('Remind')) { $detail = "remind $Remind" }
    Invoke-ToolkitScript -Path (Join-Path $global:P20SolitaireAgileRoot 'Scripts/Get-Standup.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)Standup" -Prefix (Get-CliPrefix) -Detail $detail
}

# V1: triage, the first ceremony with a write. Triage reads; Route writes
# -- one gh write per switch, never the hub (D-TA2); the one exception is
# -Assign on a card with no issue behind it, one **Assigned:** line (D-AR10).

function global:Get-P20Triage {
    <# Triage -- the open issues by milestone, the ones nobody placed first. Writes nothing. #>
    [CmdletBinding()]
    param(
        [string]$Space,
        [switch]$AsJson,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Triage'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20SolitaireAgileRoot 'Scripts/Get-Triage.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)Triage" -Prefix (Get-CliPrefix)
}

function global:Set-P20Route {
    <# Route -- one issue's triage answers, each one gh write: size, assignee, milestone, severity, deep-water; or who takes a card. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Number,
        [string]$Size,
        [string]$Assign,
        [string]$Milestone,
        [string]$Severity,
        [switch]$DeepWater,
        [string]$Space,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Route'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20SolitaireAgileRoot 'Scripts/Set-Route.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)Route" -Prefix (Get-CliPrefix)
}

# AR-1 of the agent in the room: StartWork, the hand-off. A read like Triage --
# three files in, one block out, nothing written anywhere.

function global:Get-P20StartWork {
    <# StartWork -- how we work here, the card (or issue) and its prompt, as one block. Writes nothing. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Id,
        [switch]$Clip,
        [string]$Prompt,
        [string]$Space,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'StartWork'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20SolitaireAgileRoot 'Scripts/Start-Work.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)StartWork" -Prefix (Get-CliPrefix)
}
