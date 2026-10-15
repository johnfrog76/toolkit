# The communication module's three wrappers.
#
# Dot-sourced by the module-command loader, and only when the top-level
# features.communication is true -- so a switched-off module defines no
# function, which is what makes "off means absent" true of the CLI half as
# well as the web half.
#
# Same pattern as the core wrappers in utilities.psm1: -Help renders from the
# shared help table, the body invokes the script in Scripts/ with the caller's
# own bound parameters, and a failure is logged and surfaced through
# Write-CliError rather than thrown at the terminal.
#
# Nothing here decides anything. The behaviour lives in the scripts, which are
# also runnable directly (by the tests, by a person, by anything that wants
# -Help without importing first).

# The package root, derived from this file's own location: Config/ ->  <repo>.
# It is a global because these are global functions -- they resolve the path
# when they are CALLED, in whatever scope the caller happens to be in, and a
# script- or module-scoped variable is not visible from there.
$global:P20CommunicationRoot = Split-Path -Parent $PSScriptRoot

function global:Send-P20TeamsMessage {
    <#
        SendTeams -- the communication engine's manual escape hatch.
        Both gates are the script's: the module flag decided whether this
        function exists at all, and the recipient's webhook env var is checked
        at call time, where it is reported rather than thrown.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Thin wrapper: -WhatIf is forwarded to Send-TeamsMessage.ps1, which performs the ShouldProcess check and translates it to the engine dryRun.')]
    param(
        [Parameter(Position = 0)][string]$Recipient,
        [Parameter(Position = 1)][string]$Message,
        [switch]$AsJson,
        [string]$Session,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'SendTeams'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20CommunicationRoot 'Scripts/Send-TeamsMessage.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)SendTeams" -Prefix (Get-CliPrefix)
}

function global:New-P20Meeting {
    <#
        NewMeeting -- scaffold one session file in the hub from the shipped
        ManagerSession template.
    #>
    [CmdletBinding()]
    param(
        [string]$Date,
        [string]$Type = '1on1',
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'NewMeeting'; return }
    Invoke-ToolkitScript -Path (Join-Path $global:P20CommunicationRoot 'Scripts/New-Meeting.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)NewMeeting" -Prefix (Get-CliPrefix)
}

function global:Get-P20MeetingAgenda {
    <#
        MeetingAgenda -- the stage driver. Takes only named flags: it reads the
        session file itself, and a caller that splices file text onto the
        command line lands on the guard below instead of on a cryptic
        string-to-switch conversion error.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Delegated to inner script via @PSBoundParameters')]
    param(
        [string]$Date,
        [string]$Type = '1on1',
        [switch]$Plan,
        [switch]$Prep,
        [switch]$Retro,
        [switch]$Close,
        [switch]$DryRun,
        [switch]$Help,
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Extra
    )
    if ($Help) { Show-CommandHelp 'MeetingAgenda'; return }
    if ($Extra) {
        $preview = ($Extra -join ' ')
        if ($preview.Length -gt 60) { $preview = $preview.Substring(0, 60) + '...' }
        $msg = "Unexpected positional argument(s): '$preview'. $(Get-CliPrefix)MeetingAgenda takes only named flags; it reads the session file itself. Do not pass file content."
        Write-WrapperRefusal -Name "$(Get-CliPrefix)MeetingAgenda" -Message $msg `
            -Hint "Run '$(Get-CliPrefix)MeetingAgenda -Help' for usage."
        return
    }
    $stage = 'status'
    if ($Plan) { $stage = 'plan' }
    elseif ($Prep) { $stage = 'prep' }
    elseif ($Retro) { $stage = 'retro' }
    elseif ($Close) { $stage = 'close' }
    $null = $PSBoundParameters.Remove('Extra')
    Invoke-ToolkitScript -Path (Join-Path $global:P20CommunicationRoot 'Scripts/Get-MeetingAgenda.ps1') `
        -Parameters $PSBoundParameters -Name "$(Get-CliPrefix)MeetingAgenda" -Prefix (Get-CliPrefix) -Detail $stage
}
