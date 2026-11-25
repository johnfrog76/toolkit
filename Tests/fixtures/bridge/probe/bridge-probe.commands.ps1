# The probe module's wrappers -- see bridge-probe.commands.psd1. Test-only.
#
# The same shape as a shipped module's wrappers: -Help from the shared table,
# the body through the one guard. The package root is read inside each
# function from the module state, never from a variable this file set at load
# (AGENTS.md, "A function global: in utilities.psm1 cannot read module state
# through a $script: name").
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.

function global:Get-P20BridgeProbeScript {
    param([string]$Leaf)
    return (Join-Path (Join-Path (Join-Path (Get-P20ModuleState).PackageRoot 'Config') 'bridge-probe') $Leaf)
}

function global:Invoke-P20BridgeProbeOk {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeOk'; return }
    Invoke-ToolkitScript -Path (Get-P20BridgeProbeScript 'ok.ps1') -Parameters $PSBoundParameters `
        -Name "$(Get-CliPrefix)ProbeOk" -Prefix (Get-CliPrefix)
}

function global:Invoke-P20BridgeProbeStated {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeStated'; return }
    Invoke-ToolkitScript -Path (Get-P20BridgeProbeScript 'stated.ps1') -Parameters $PSBoundParameters `
        -Name "$(Get-CliPrefix)ProbeStated" -Prefix (Get-CliPrefix)
}

function global:Invoke-P20BridgeProbeWrapper {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeWrapper'; return }
    Write-WrapperRefusal -Name "$(Get-CliPrefix)ProbeWrapper" -Message 'ProbeWrapper needs PROBE_KEY; it is not set.' `
        -Hint 'Set PROBE_KEY in the environment.'
    return
}

function global:Invoke-P20BridgeProbeThrows {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeThrows'; return }
    Invoke-ToolkitScript -Path (Get-P20BridgeProbeScript 'throws.ps1') -Parameters $PSBoundParameters `
        -Name "$(Get-CliPrefix)ProbeThrows" -Prefix (Get-CliPrefix)
}

function global:Invoke-P20BridgeProbeSilent {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeSilent'; return }
    Invoke-ToolkitScript -Path (Get-P20BridgeProbeScript 'silent.ps1') -Parameters $PSBoundParameters `
        -Name "$(Get-CliPrefix)ProbeSilent" -Prefix (Get-CliPrefix)
}

# A refusal recorded and caught INSIDE the verb, then a different failure: the
# record is not this failure's, so the bridge must not read it as a refusal.
function global:Invoke-P20BridgeProbeStale {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeStale'; return }
    try { Invoke-P20BridgeProbeStated } catch { $null = $_ }
    throw 'The probe failed after a refusal it caught.'
}

function global:Invoke-P20BridgeProbeSlow {
    [CmdletBinding()]
    param([switch]$Help)
    if ($Help) { Show-CommandHelp 'ProbeSlow'; return }
    Invoke-ToolkitScript -Path (Get-P20BridgeProbeScript 'slow.ps1') -Parameters $PSBoundParameters `
        -Name "$(Get-CliPrefix)ProbeSlow" -Prefix (Get-CliPrefix)
}
