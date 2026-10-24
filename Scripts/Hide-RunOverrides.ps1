# The per-shell environment overrides a test run must not inherit.
#
# P20_ACTIVE_SPACE (consts.json env.activeSpace) names the Space a shell works
# in, and PROMPTS_ROOT (env.promptsRoot) names its hub. Both beat the config
# files, so a shell that holds them points every suite that copies samples/hub
# at a Space or a folder that hub does not have. A runner takes them out of its
# own process tree for the run and puts them back after, the way it takes out
# every TEAMS_WEBHOOK_*; a suite that means to test an override sets it itself.
#
# Dot-source Scripts/Get-Consts.ps1 first: the names are read from it.

function Hide-P20RunOverrides {
    <#
    .SYNOPSIS
        Remove the overrides from this process and return what they held.
    #>
    $names = @((Get-P20Consts).env.activeSpace, (Get-P20Consts).env.promptsRoot)
    $saved = [ordered]@{}
    foreach ($name in $names) {
        $saved[$name] = [System.Environment]::GetEnvironmentVariable($name)
        Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
    }
    return $saved
}

function Restore-P20RunOverrides {
    <#
    .SYNOPSIS
        Put back what Hide-P20RunOverrides returned; a name that held nothing
        is left unset.
    #>
    param($Saved)
    if ($null -eq $Saved) { return }
    foreach ($name in @($Saved.Keys)) {
        # A $null handed to a string parameter becomes '' in PowerShell, which would
        # leave the variable set and empty; a name that held nothing is removed.
        if ($null -eq $Saved[$name]) { Remove-Item "Env:\$name" -ErrorAction SilentlyContinue }
        else { [System.Environment]::SetEnvironmentVariable($name, [string]$Saved[$name]) }
    }
}
