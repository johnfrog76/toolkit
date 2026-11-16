<#
.SYNOPSIS
    The standup room's size: a Space's features.teamSize, read the one way.

.DESCRIPTION
    Dot-sourced by Scripts/Standup-Rules.ps1 (the fill) and by
    Scripts/Get-OptionalSurfaces.ps1 (the inventory row), so the rule is typed once
    in this half. team_size in agent/solitaire/standup.py is the agent's copy;
    Tests/fixtures/rituals/standup-team.json's `sizes` rows hold the two to one table.

      Get-P20TeamSize -Stored <value>
        @{ Size = <int>; Set = <bool> }. Size is the stored value when it is a
        whole number in consts.json rituals.teamSizes (a JSON number: a string, a
        boolean or a fraction is not one), else rituals.teamSizeDefault. Set says
        whether the stored value was one of the sizes -- unset and a value that is
        not a size both read as the default, and Set is false for both.

      Get-P20SpaceTeamSize -Space <entry>
        The same, off a Space's entry (its features.teamSize).

    5.1-safe: no ternary, no null-coalescing.
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-P20TeamSize {
    param($Stored)
    $rituals = (Get-P20Consts).rituals
    $sizes = @($rituals.teamSizes | ForEach-Object { [int]$_ })
    $result = @{ Size = [int]$rituals.teamSizeDefault; Set = $false }
    if ($null -eq $Stored) { return $result }
    # A JSON number only: 5.1 reads one as [int], 7 as [long]; a whole [double]
    # is a fraction's type and is not a size, whatever its value.
    if (-not ($Stored -is [int] -or $Stored -is [long])) { return $result }
    if ($sizes -contains [int]$Stored) {
        $result.Size = [int]$Stored
        $result.Set = $true
    }
    return $result
}

function Get-P20SpaceTeamSize {
    param($Space)
    $stored = $null
    $features = $null
    if ($Space -is [System.Collections.IDictionary]) { if ($Space.Contains('features')) { $features = $Space['features'] } }
    elseif ($Space -and $Space.PSObject.Properties['features']) { $features = $Space.features }
    if ($features -is [System.Collections.IDictionary]) { if ($features.Contains('teamSize')) { $stored = $features['teamSize'] } }
    elseif ($features -and $features.PSObject.Properties['teamSize']) { $stored = $features.teamSize }
    return (Get-P20TeamSize -Stored $stored)
}
