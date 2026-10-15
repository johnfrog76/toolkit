<#
.SYNOPSIS
    RemoveSpace -- it should never have been a Space, or it is truly gone.
.DESCRIPTION
    The Space is UN-DECLARED: its entry leaves the hub's hub.json, and this
    machine's config.local.json patch for its slug goes with it.

    REMOVING NEVER DELETES A CARD. The Space's folder stays in the hub exactly as
    it is; the output says where it is, how many cards are in it, and the line
    that brings them back -- adding a Space with the same folder adopts it
    untouched (NewSpace). Deleting the folder is a person's act, in their own file
    manager, on purpose: the same rule as current/ being protected.

    THE WRITE IS Config's (Scripts/Set-ToolkitConfig.ps1, the one writer), in
    process: `Config -Unset spaces.<slug> -Hub`, and `Config -Unset spaces.<slug>`
    when this machine has a patch for it.

    Refused, exit 2, one sentence each: no slug; a slug that is not declared; the
    Space you are in (switch first); a Space config.default.json ships (the
    team's -- it can be hidden or retired, not removed). A Space with cards in
    current/ asks first, naming the count; a caller that cannot answer (the
    bridge, a script) is refused without -Force.
.PARAMETER Slug
    The Space to remove.
.PARAMETER Force
    Remove a Space with cards in current/ without asking. The folder stays either way.
.PARAMETER WhatIf
    Say every key that would go and the folder that would stay; write nothing.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Slug,
    [switch]$Force,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

# Re-run after each write: Config re-imports the module (AGENTS.md, "Traps worth knowing").
$loadHelpers = {
    foreach ($helper in @('Resolve-CliPrefix.ps1', 'Resolve-Tracker.ps1', 'Resolve-HubConfig.ps1', 'Get-SpaceLifecycle.ps1')) {
        . (Join-Path $scriptsDir $helper)
    }
}
. $loadHelpers
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}
$prefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
if (-not $prefix) { $prefix = Resolve-P20ConfigPrefix -PackageRoot $packageRoot }

if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}RemoveSpace -- un-declare a Space; its cards stay" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    ${prefix}RemoveSpace <slug> [-Force] [-WhatIf]"
    Write-Host ""
    Write-Host "  Its entry leaves hub.json, and this machine's patch for it leaves config.local.json, through"
    Write-Host "  Config. Its folder stays in the hub exactly as it is, and adding a Space with that folder brings"
    Write-Host "  the cards back. To keep it declared and archived instead: ${prefix}RetireSpace <slug>."
    Write-Host ""
    exit 0
}

$state = Get-P20SpaceLifecycleState -PackageRoot $packageRoot
$knownSlugs = @($state.Spaces | ForEach-Object { [string]$_.slug })

$typed = ([string]$Slug).Trim()
if (-not $typed) {
    Write-CliError -Message "Say which Space to remove: ${prefix}RemoveSpace <slug>." -Hint "The Spaces are: $($knownSlugs -join ', ')."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$target = Resolve-P20RenamedSlug -Slug $typed -Slugs $knownSlugs
if ($target -ne $typed) { Write-Host "  $(Get-P20RenamedSlugNote -From $typed -To $target)" -ForegroundColor Yellow }
$space = $state.Spaces | Where-Object { [string]$_.slug -eq $target } | Select-Object -First 1
if (-not $space) {
    Write-CliError -Message "'$typed' is not a Space this machine knows." -Hint "The Spaces are: $($knownSlugs -join ', ')."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$label = Get-P20SpaceLabel $space
if ($target -eq $state.Active) {
    Write-CliError -Message "$label is the Space you are in; switch to another before removing it." -Hint "${prefix}SwitchSpace <slug>, then ${prefix}RemoveSpace $target."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($state.ShippedSlugs -contains $target) {
    Write-CliError -Message "$label ships in config.default.json, so it is the team's and cannot be removed -- only hidden or retired." `
        -Hint "Hide the demo Spaces: ${prefix}Config -Set isDemoDismissed=true. Or keep it declared and archived: ${prefix}RetireSpace $target."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$inHub = $state.HubSlugs -contains $target
$inLocal = [bool]($state.LocalPatches -and $state.LocalPatches.PSObject.Properties[$target])
$cards = Get-P20SpaceFolderCount -HubRoot $state.HubRoot -Space $space
$cardsLine = "$($cards.Folder) -- $($cards.Total) cards ($($cards.Current) current, $($cards.Archive) archive)"
if (-not $cards.Exists) { $cardsLine = "$($cards.Folder) -- not there on this machine" }

# The line that brings the cards back: NewSpace with the folder as its slug adopts
# the folder untouched -- with the Space's own address, so it comes back as it was.
$back = ''
if ($cards.FolderName -cmatch '^[a-z][a-z0-9-]*$') {
    $back = "${prefix}NewSpace $($cards.FolderName)"
    $addr = [string]$space.org
    if ($addr) {
        if ((Resolve-P20Tracker -OrgUrl $addr) -eq 'github') {
            $parts = @(($addr -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '').Split('/') | Where-Object { $_ })
            if ($parts.Count -ge 3) { $back += " -Repo $($parts[1])/$($parts[2])" }
        }
        else { $back += " -Address $addr" }
    }
    if ($space.name) { $back += " -Name `"$($space.name)`"" }
}
else {
    $back = "${prefix}Config -Set spaces.$target.promptsFolder=$($cards.FolderName) -Hub"
}

$lines = @()
if ($inHub) { $lines += "${prefix}Config -Unset spaces.$target -Hub" }
if ($inLocal) { $lines += "${prefix}Config -Unset spaces.$target" }

if ($WhatIf) {
    Write-Host ""
    foreach ($l in $lines) { Write-Host "  [WhatIf] $l" -ForegroundColor Yellow }
    Write-Host "  [WhatIf] its folder stays as it is: $cardsLine" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [-] Would remove the Space '$target' -- $label" -ForegroundColor Green
    if ($cards.Current -gt 0) { Write-Host "      $($cards.Current) cards in current/ -- removing it asks first (-Force does not)." }
    exit 0
}

# Cards in play: asked, naming the count -- or refused for a caller that cannot answer.
if ($cards.Current -gt 0 -and -not $Force) {
    $canAsk = $true
    if ($env:TOOLKIT_QUIET_STARTUP -or $env:CI) { $canAsk = $false }
    try { if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { $canAsk = $false } } catch { $canAsk = $false }
    if (-not $canAsk) {
        Write-CliError -Message "$label has $($cards.Current) cards in current/, and removing it needs a yes this caller cannot give." `
            -Hint "${prefix}RemoveSpace $target -Force -- the folder and its cards stay either way."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $answer = Read-Host "  Remove $label? Its $($cards.Current) cards in current/ stay in $($cards.Folder). [y/N]"
    if (([string]$answer).Trim() -notmatch '^(?i)y(es)?$') {
        Write-Host "  Nothing changed." -ForegroundColor DarkGray
        exit 0
    }
}

$configScript = Join-Path $scriptsDir 'Set-ToolkitConfig.ps1'
if ($inHub) {
    $global:LASTEXITCODE = 0
    $out = & $configScript -Unset "spaces.$target" -Hub *>&1 | Out-String
    $code = $LASTEXITCODE
    . $loadHelpers
    Write-Host $out.TrimEnd()
    if ($code -and $code -ne 0) { exit $code }
}
if ($inLocal) {
    $global:LASTEXITCODE = 0
    $out = & $configScript -Unset "spaces.$target" *>&1 | Out-String
    $code = $LASTEXITCODE
    . $loadHelpers
    Write-Host $out.TrimEnd()
    if ($code -and $code -ne 0) { exit $code }
}
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "${prefix}RemoveSpace" -Detail "$target folder kept $($cards.FolderName) $($cards.Total)"
}

Write-Host ""
Write-Host "  [-] Removed the Space '$target' -- $label" -ForegroundColor Green
Write-Host "      Its folder stays, untouched: $cardsLine"
Write-Host "      Deleting it is yours to do, in your own file manager. To bring the cards back:"
Write-Host "    $back"
exit 0
