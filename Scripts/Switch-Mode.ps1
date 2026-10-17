<#
.SYNOPSIS
    Switch between named org profiles (Globex, Demo, etc.) or show status.
.DESCRIPTION
    Writes activeSpace into config.local.json.
    Org data (ADO URL, projects, promptsFolder) lives in the orgs array
    of config.default.json. Machine-specific settings (paths, aliases)
    stay untouched in config.local.json.
.EXAMPLE
    {cliPrefix}SwitchSpace Demo      # Switch to the sample Space
    {cliPrefix}SwitchSpace Globex    # Switch to the Globex Space
    {cliPrefix}SwitchSpace Status    # Show which Space is active, and every Space you can switch to
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Mode = "Status"
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$toolkitDir = Split-Path -Parent $PSScriptRoot
$localPath = Join-Path $toolkitDir "config.local.json"
# The container's keys in both spellings (ConvertTo-P20SpaceKeys, stage 2).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
# The byte contract for a config file -- Config's own writer (no BOM, LF, atomic).
. (Join-Path $PSScriptRoot 'Write-ConfigJson.ps1')

# Load orgs array from default config
$defaultCfgPath = Join-Path $toolkitDir "config.default.json"
$defaultCfg = $null
$spaces = @()
if (Test-Path $defaultCfgPath) {
    $defaultCfg = ConvertTo-P20SpaceKeys (Get-Content $defaultCfgPath -Raw | ConvertFrom-Json)
    if ($defaultCfg.spaces) { $spaces = @($defaultCfg.spaces) }
}

# config.local.json may patch org/tenant/projects per slug, so the raw default
# file describes a machine this may not be. The module has already merged them;
# prefer that and fall back to the file only if the module is not loaded.
if ($global:P20Config -and $global:P20Config.Spaces) {
    $spaces = @($global:P20Config.Spaces)
}

# Load current local config
$localCfg = $null
$localUnreadable = $false
# Read so it can be written back as it was: PowerShell 7 would otherwise turn an
# ISO-8601-looking string (errorsAckedAt, menuResetTimestamp) into a [datetime],
# and the writer below would put it back in another format. 5.1 never does.
$localJsonArgs = @{}
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $localJsonArgs['DateKind'] = 'String' }
if (Test-Path $localPath) {
    try {
        $localRaw = Get-Content $localPath -Raw -Encoding UTF8
        # A zero-byte or whitespace-only file is an empty object, not a parse failure.
        if ([string]::IsNullOrWhiteSpace($localRaw)) { $localRaw = '{}' }
        $localCfg = ConvertTo-P20SpaceKeys ($localRaw | ConvertFrom-Json @localJsonArgs)
    }
    catch {
        # Said once; Status reads on with defaults, but a switch refuses below
        # rather than write one key over a file it could not read.
        if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
        $null = Write-P20ConfigParseWarning -Path $localPath -Message $_.Exception.Message
        $localUnreadable = $true
        $localCfg = $null
    }
}

if ($Mode -eq "Status") {
    Write-Host ""
    $activeSlug = if ($localCfg.activeSpace) { $localCfg.activeSpace } elseif ($defaultCfg.activeSpace) { $defaultCfg.activeSpace } else { '' }
    $activeSlug = Resolve-P20RenamedSlug -Slug ([string]$activeSlug) -Slugs @($spaces | ForEach-Object { [string]$_.slug })
    $activeSpaceEntry = $spaces | Where-Object { $_.slug -eq $activeSlug }
    $displayName = if ($activeSpaceEntry) { $activeSpaceEntry.name } else { $activeSlug }
    $adoOrg = if ($activeSpaceEntry) { $activeSpaceEntry.org } else { '(none)' }
    $projCount = if ($activeSpaceEntry -and $activeSpaceEntry.projects) { @($activeSpaceEntry.projects).Count } else { 0 }
    $spaceStatus = if ($activeSpaceEntry) { $activeSpaceEntry.status } else { 'unknown' }
    Write-Host "  Active Space  : $displayName" -ForegroundColor Cyan
    Write-Host "  Address       : $adoOrg"      -ForegroundColor Gray
    $activeFolder = if ($activeSpaceEntry -and $activeSpaceEntry.promptsFolder) { [string]$activeSpaceEntry.promptsFolder } else { $activeSlug }
    Write-Host "  Folder        : $($activeFolder)/"  -ForegroundColor Gray
    Write-Host "  Projects      : $projCount configured" -ForegroundColor Gray
    $statusColor = switch ($spaceStatus) { 'archive' { 'DarkGray' } 'local' { 'Yellow' } default { 'Gray' } }
    $statusBadge = switch ($spaceStatus) { 'archive' { ' [Local - rolled off]' } 'local' { ' [Local]' } default { '' } }
    Write-Host "  Status        : $spaceStatus$statusBadge" -ForegroundColor $statusColor
    # On stage: a GitHub Space's repository visibility -- public, private
    # or unknown (consts.json `visibility`). gh is asked only for a Space that is
    # `active` (connected); any other is unknown, said rather than guessed. An
    # Azure DevOps Space, or one with no tracker, has none and gets no word.
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    $visibilityOf = @{}
    $readVisibility = {
        param($Entry)
        $key = [string]$Entry.slug
        if (-not $visibilityOf.ContainsKey($key)) {
            $visibilityOf[$key] = Get-P20SpaceVisibility -OrgUrl ([string]$Entry.org) -Projects $Entry.projects -NoAsk:([string]$Entry.status -ne 'active')
        }
        return $visibilityOf[$key]
    }
    if ($activeSpaceEntry) {
        $activeVisibility = & $readVisibility $activeSpaceEntry
        if ($activeVisibility) {
            $visibilityColor = 'Gray'
            if ($activeVisibility -eq [string](Get-P20Consts).visibility.public) { $visibilityColor = 'Yellow' }
            Write-Host "  Visibility    : $activeVisibility" -ForegroundColor $visibilityColor
        }
    }
    # What is OFFERED, not what exists: a dismissed Example org is left out
    # unless you are in it. `SwitchSpace azure-demo` still works by name.
    . (Join-Path $PSScriptRoot 'Select-OfferedSpaces.ps1')
    $dismissed = $false
    if ($localCfg -and ($localCfg.PSObject.Properties.Name -contains 'isDemoDismissed')) { $dismissed = [bool]$localCfg.isDemoDismissed }
    elseif ($defaultCfg -and $defaultCfg.isDemoDismissed) { $dismissed = [bool]$defaultCfg.isDemoDismissed }
    $offered = Select-P20OfferedSpaces -Spaces $spaces -ActiveSpace $activeSlug -Dismissed $dismissed
    if ($offered.Count -gt 0) {
        Write-Host ""
        Write-Host "  Available Spaces:" -ForegroundColor DarkGray
        foreach ($o in $offered) {
            $marker = if ($o.slug -eq $activeSlug) { '-> ' } else { '   ' }
            $badge = switch ($o.status) { 'archive' { ' [Local]' } 'local' { ' [Local]' } default { '' } }
            $color = if ($o.slug -eq $activeSlug) { 'Cyan' } elseif ($o.status -eq 'archive') { 'DarkGray' } else { 'Gray' }
            $word = & $readVisibility $o
            $visible = ''
            if ($word) { $visible = " ($word)" }
            Write-Host "  $marker$($o.slug.PadRight(10)) $($o.name)$badge$visible" -ForegroundColor $color
        }
    }
    Write-Host ""
    return
}

# Resolve slug (case-insensitive match against orgs array)
$slug = $Mode.ToLower()
# A renamed shipped Space's old slug (`test`, the Azure demo's before the rename) is
# accepted and switches to the new one, saying so once.
$renamedTo = Resolve-P20RenamedSlug -Slug $slug -Slugs @($spaces | ForEach-Object { [string]$_.slug })
if ($renamedTo -ne $slug) {
    Write-Host "  $(Get-P20RenamedSlugNote -From $slug -To $renamedTo)" -ForegroundColor Yellow
    $slug = $renamedTo
}
$spaceEntry = $spaces | Where-Object { $_.slug -eq $slug }
if (-not $spaceEntry) {
    # Try matching by name (case-insensitive)
    $spaceEntry = $spaces | Where-Object { $_.name -like $Mode }
    if ($spaceEntry) { $slug = $spaceEntry.slug }
}

if (-not $spaceEntry) {
    $known = if ($spaces.Count -gt 0) { "Available: $(($spaces | ForEach-Object { $_.slug }) -join ', ')." } else { 'No Spaces are configured.' }
    $why = "Unknown Space: $Mode"
    if (Get-Command Write-CliError -ErrorAction SilentlyContinue) { Write-CliError -Message $why -Hint $known }
    else { Write-Host "Error: $why" -ForegroundColor Red; Write-Host "Hint:  $known" -ForegroundColor Yellow }
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Update the active Space in config.local.json (preserves machine-specific
# settings). Written as `activeSpace` -- the file's spelling since the Space rename --
# and a stale `activeOrg` is dropped first: ConvertTo-P20SpaceSpelling lets the
# new name win when a file carries both, so setting the OLD name here was a
# no-op on every file already written as `activeSpace`.
if ($localUnreadable) {
    $why = 'config.local.json will not parse, so the Space was not switched.'
    $fix = 'Fix the file by hand (or delete it); it was not changed.'
    if (Get-Command Write-CliError -ErrorAction SilentlyContinue) { Write-CliError -Message $why -Hint $fix }
    else { Write-Host "Error: $why" -ForegroundColor Red; Write-Host "Hint:  $fix" -ForegroundColor Yellow }
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($localCfg) {
    if ($localCfg.PSObject.Properties['activeOrg']) { $localCfg.PSObject.Properties.Remove('activeOrg') }
    $localCfg | Add-Member -NotePropertyName 'activeSpace' -NotePropertyValue $slug -Force
    Write-ConfigJson -Path $localPath -Value (ConvertTo-P20SpaceSpelling $localCfg)
}
else {
    Write-ConfigJson -Path $localPath -Value ([PSCustomObject]@{ activeSpace = $slug })
}

# Reload the module so in-memory config picks up the new org
$modulePath = Join-Path $toolkitDir "utilities.psm1"
Import-Module $modulePath -Global -Force -DisableNameChecking 2>$null
# Clear cached env so {cliPrefix}Env re-detects tier
$global:P20Env = $null

# Display resolved config
$displayName = $spaceEntry.name
$mergedOrg = $global:P20Config.Org
$mergedProj = $global:P20Config.Projects.Count

Write-Host ""
Write-Host "  [+] Switched to $displayName"          -ForegroundColor Green
Write-Host "  Org      : $mergedOrg"                  -ForegroundColor Gray
Write-Host "  Projects : $mergedProj configured"      -ForegroundColor Gray
Write-Host ""

Write-Host "  Config reloaded. Run $(Get-CliPrefix)Env to verify tier detection." -ForegroundColor DarkGray
Write-Host ""
