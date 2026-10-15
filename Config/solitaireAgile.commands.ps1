# The Solitaire Agile add-on's wrappers: Standup (M0), Triage and Route (V1).
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
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Standup'; return }
    $detail = 'ok'
    if ($PSBoundParameters.ContainsKey('Remind')) { $detail = "remind $Remind" }
    Invoke-ToolkitScript -Path (Join-Path $global:P20SolitaireAgileRoot 'Scripts/Get-Standup.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)Standup" -Prefix (Get-CliPrefix) -Detail $detail
}

# V1: triage, the first ceremony with a write. Triage reads; Route writes
# -- one gh write per switch, never the hub (D-TA2).

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
    <# Route -- one issue's triage answers, each one gh write: size, milestone, severity, deep-water. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Number,
        [string]$Size,
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
