<#
.SYNOPSIS
    Is Azure DevOps part of what this machine SHOWS, right now?
.DESCRIPTION
    docs/modules/ado.md, "The switch, and its scope". Cards have no flag and never
    will; Azure DevOps gets one, and it is DERIVED rather than defaulted so that
    a person with a real ADO org changes nothing and sees nothing change:

        ON   when  features.ado is true
             or    features.ado is absent AND the active Space's status is 'active'
                   AND its tracker is Azure DevOps ('ado', Resolve-Tracker.ps1)
        OFF  otherwise

    It follows the org you are in. A machine made by Start is in Demo, which is
    'local': OFF. Someone in their client's org is in an 'active' one: ON. A
    connected GitHub Space is 'active' too, and its tracker is GitHub: OFF --
    the GitHub row of the inventory is the one that says it is connected.
    An explicit features.ado always wins, either way.

    A pure function over three values, in a file of its own, so that a module
    wrapper, a module-launched script and a test can all reach the SAME rule --
    the shape Resolve-TierDecision.ps1 already has. It reads no state: the
    caller hands it the org status, the tracker the address names and the flag
    (AGENTS.md, the $script: trap).

    This is about what is SHOWN -- Menu's rows, Setup's checks, the inventory.
    It unregisters nothing: an ADO verb typed by name still exists and still
    refuses with its tier sentence. That is the invisible half, roadmap phase 8.
#>

function Test-P20AdoEnabled {
    param(
        # The active org's status: 'active', 'local', 'archive', or '' when unknown.
        [AllowEmptyString()][AllowNull()][string]$OrgStatus,
        # features.ado as configured: $true, $false, or $null when nobody has said.
        $Flag,
        # WHICH tracker the active Space's address names (Resolve-P20Tracker):
        # 'ado', 'github', 'none', or '' when unknown. Only 'ado' is Azure DevOps.
        [AllowEmptyString()][AllowNull()][string]$Tracker
    )
    if ($null -ne $Flag -and "$Flag" -ne '') { return [bool]$Flag }
    return (($OrgStatus -eq 'active') -and ($Tracker -eq 'ado'))
}
