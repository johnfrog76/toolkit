<#
.SYNOPSIS
    The orgs a person is OFFERED to pick from -- not the orgs that exist.
.DESCRIPTION
    The owner's rule: once dismissed, the shipped template org (`azure-demo`,
    "Azure demo", once `test` and "Example") is filtered out of the collections of orgs a person picks from,
    and lives on only as a checked checkbox in Settings. So:

        an org marked `example: true` is left out  WHEN  isDemoDismissed is true
                                                   AND   it is not the active Space

    Never hide where you are: the active Space is always offered. And nothing is
    removed from config -- switching to `azure-demo` by name still works, and every
    suite that uses it still does.

    The template org is marked by a PROPERTY, not by its slug (AGENTS.md, "One
    place for magic strings"). A pure function in a file of its own, like
    Test-AdoEnabled.ps1: it reads no state, the caller hands it everything.
    agent/core/config.py's offered_orgs is the other half, and
    Tests/fixtures/offered-orgs/table.json holds the two to one table.
#>

function Select-P20OfferedSpaces {
    param(
        [AllowNull()][object[]]$Spaces,
        [AllowEmptyString()][AllowNull()][string]$ActiveSpace,
        [bool]$Dismissed
    )
    $offered = @()
    foreach ($o in @($Spaces)) {
        if ($null -eq $o) { continue }
        $isExample = ($o.PSObject.Properties.Name -contains 'example') -and ($o.example -eq $true)
        if ($Dismissed -and $isExample -and [string]$o.slug -ne $ActiveSpace) { continue }
        $offered += $o
    }
    return , $offered
}
