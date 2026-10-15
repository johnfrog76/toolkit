#
# The growth module's wrapper functions (build-plan D-CM).
#
# Dot-sourced by utilities.psm1's module-command loader, and ONLY when
# features.growth is true -- so on an install with growth switched off these
# functions do not exist at all. That is the same "off means absent" the web
# shell applies to a module's routes.
#
# Same pattern as the core wrappers in utilities.psm1, and for the same reasons:
# the wrapper declares the parameters so PowerShell can bind and complete them,
# answers -Help from the command table via Show-CommandHelp, forwards with
# @PSBoundParameters so only what the caller actually typed reaches the script,
# and logs one CMD or ERR line. The package root is read per call from
# (Get-P20ModuleState).PackageRoot, never a free $repoRoot: a global function reached from a
# module-launched script resolves a free name against that script (AGENTS.md, Traps).
#
# Nothing here names the prefix: Resolve-InvokedCommand reads it back off the
# alias the user actually typed, so the same function reads correctly under any
# prefix, and under two at once.
#

function global:New-P20GrowthItem {
    [CmdletBinding()]
    param(
        [ValidateSet('training', 'presentation', 'goal')]
        [string]$Type = 'training',
        [string]$Title,
        [string]$Date,
        [string]$DueDate,
        [string]$Provider,
        [string]$Hours,
        [string]$Notes,
        [string]$Close,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewGrowth'
    if ($Help) { Show-CommandHelp 'NewGrowth'; return }
    $pkgRoot = (Get-P20ModuleState).PackageRoot
    Invoke-ToolkitScript -Path "$($pkgRoot)/Scripts/New-GrowthItem.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -Detail $Type
}

function global:New-P20WorkReview {
    [CmdletBinding()]
    param(
        [string]$StartDate,
        [string]$EndDate,
        [string]$Slugs,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewWorkReview'
    if ($Help) { Show-CommandHelp 'NewWorkReview'; return }
    $pkgRoot = (Get-P20ModuleState).PackageRoot
    # Forwarded without a try/catch that re-reports: this one writes JSON to
    # stdout for the agent to parse, and a second error line on top of the
    # script's own {"error": "..."} would break every caller that parses it.
    & "$($pkgRoot)/Scripts/Generate-Review.ps1" @PSBoundParameters
    Write-ToolkitLog -Type CMD -Source $inv.Name -Detail 'ok'
}

function global:Publish-P20WorkReview {
    [CmdletBinding()]
    param(
        [switch]$NoPush,
        [switch]$Preview,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'PublishWorkReview'
    if ($Help) { Show-CommandHelp 'PublishWorkReview'; return }
    $pkgRoot = (Get-P20ModuleState).PackageRoot
    # -Preview emits JSON for the agent; same reason as above, no re-report.
    & "$($pkgRoot)/Scripts/Update-Review.ps1" @PSBoundParameters
    if (-not $Preview) { Write-ToolkitLog -Type CMD -Source $inv.Name -Detail 'ok' }
}

function global:Write-P20PeerReviewLog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][int]$PullRequestId,
        [string]$Title,
        [string]$Notes,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'LogPeerReview'
    if ($Help) { Show-CommandHelp 'LogPeerReview'; return }
    $pkgRoot = (Get-P20ModuleState).PackageRoot
    Invoke-ToolkitScript -Path "$($pkgRoot)/Scripts/Write-PeerReviewLog.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -Detail "PR$PullRequestId"
}

function global:Update-P20Resume {
    [CmdletBinding()]
    param(
        [switch]$NoPush,
        [switch]$Preview,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'UpdateResume'
    if ($Help) { Show-CommandHelp 'UpdateResume'; return }
    $pkgRoot = (Get-P20ModuleState).PackageRoot
    & "$($pkgRoot)/Scripts/Update-Resume.ps1" @PSBoundParameters
    if (-not $Preview) { Write-ToolkitLog -Type CMD -Source $inv.Name -Detail 'ok' }
}
