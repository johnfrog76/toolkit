# The Organize add-on's two wrappers.
#
# Dot-sourced by the module-command loader, and only when the top-level
# features.organize is true -- so a switched-off module defines no function,
# which is what makes "off means absent" true of the CLI half as well as the web.
#
# Same pattern as communication's: -Help renders from the shared help table, the
# body runs the script in Scripts/ with the caller's own bound parameters through
# the one guard, and nothing here decides anything.

# The package root, derived from this file's own location: Config/ -> <repo>.
$global:P20OrganizeRoot = Split-Path -Parent $PSScriptRoot

function global:New-P20Reminder {
    <# NewReminder -- one reminder file in the hub's reminders/current/. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Title,
        [string]$Due,
        [string]$Source,
        [string]$Ref,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'NewReminder'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20OrganizeRoot 'Scripts/New-Reminder.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)NewReminder" -Prefix (Get-CliPrefix)
}

function global:Get-P20Reminders {
    <# Reminders -- the ledger; with an id, -Snooze, edit or -Archive one. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [string]$Snooze,
        [switch]$Archive,
        [string]$Due,
        [switch]$NoDue,
        [string]$Title,
        [string]$Source,
        [string]$Ref,
        [switch]$All,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Reminders'; return }
    $detail = 'list'
    if ($Snooze) { $detail = "snooze $Snooze" } elseif ($Archive) { $detail = 'archive' }
    elseif (@('Due', 'NoDue', 'Title', 'Source', 'Ref' | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count) { $detail = 'edit' }
    Invoke-ToolkitScript -Path (Join-Path $global:P20OrganizeRoot 'Scripts/Get-Reminders.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)Reminders" -Prefix (Get-CliPrefix) -Detail $detail
}
