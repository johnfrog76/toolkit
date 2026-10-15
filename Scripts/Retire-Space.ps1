<#
.SYNOPSIS
    RetireSpace -- the engagement is over, keep the record.
.DESCRIPTION
    The Space stays declared with status `archive`: its cards stay readable,
    Daily and reviews still count them, its row on the Studio's Spaces card moves
    under Archive, and nothing asks its tracker again (an archived Space is never
    ADO-enabled, Scripts/Test-AdoEnabled.ps1). It is the value the web shell has
    always rendered as the retrospective view; this verb is the name for it.

    THE WRITE IS Config's (Scripts/Set-ToolkitConfig.ps1, the one writer), in
    process: `Config -Set spaces.<slug>.status=archive -Hub`, and -- when this
    machine's config.local.json overrides that Space's status -- `Config -Unset
    spaces.<slug>.status`, because a local override would otherwise keep it
    from being retired here. Nothing else is written and no folder is touched.

    To bring a retired Space back is the same key: the output names the line.
    Removing a Space -- un-declaring it -- is RemoveSpace.
.PARAMETER Slug
    The Space to retire.
.PARAMETER WhatIf
    Say every key it would write and the folder that stays; write nothing.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Slug,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

# Re-run after the write: Config re-imports the module (AGENTS.md, "Traps worth knowing").
$loadHelpers = {
    foreach ($helper in @('Resolve-CliPrefix.ps1', 'Resolve-HubConfig.ps1', 'Get-SpaceLifecycle.ps1')) {
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
    Write-Host "  ${prefix}RetireSpace -- the engagement is over, keep the record" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    ${prefix}RetireSpace <slug> [-WhatIf]"
    Write-Host ""
    Write-Host "  Sets the Space's status to archive, through Config. Its cards stay where they are and stay"
    Write-Host "  readable; nothing asks its tracker again. To un-declare a Space instead: ${prefix}RemoveSpace <slug>."
    Write-Host ""
    exit 0
}

$state = Get-P20SpaceLifecycleState -PackageRoot $packageRoot
$knownSlugs = @($state.Spaces | ForEach-Object { [string]$_.slug })

$typed = ([string]$Slug).Trim()
if (-not $typed) {
    Write-CliError -Message "Say which Space to retire: ${prefix}RetireSpace <slug>." -Hint "The Spaces are: $($knownSlugs -join ', ')."
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
$cards = Get-P20SpaceFolderCount -HubRoot $state.HubRoot -Space $space
$cardsLine = "$($cards.Folder) -- $($cards.Total) cards ($($cards.Current) current, $($cards.Archive) archive)"
if (-not $cards.Exists) { $cardsLine = "$($cards.Folder) -- not there on this machine" }

$oldStatus = [string]$space.status
if ($oldStatus -eq 'archive') {
    Write-Host ""
    Write-Host "  $label is already retired (status archive) -- nothing to change." -ForegroundColor DarkGray
    Write-Host "      cards: $cardsLine"
    Write-Host ""
    exit 0
}

# This machine's own override of the Space's status, which would outrank the hub's.
$localStatus = $false
if ($state.LocalPatches -and $state.LocalPatches.PSObject.Properties[$target]) {
    $patch = $state.LocalPatches.PSObject.Properties[$target].Value
    if ($patch -and $patch.PSObject.Properties['status']) { $localStatus = $true }
}

$setPair = "spaces.$target.status=archive"
if ($WhatIf) {
    Write-Host ""
    Write-Host "  [WhatIf] ${prefix}Config -Set $setPair -Hub" -ForegroundColor Yellow
    if ($localStatus) { Write-Host "  [WhatIf] ${prefix}Config -Unset spaces.$target.status" -ForegroundColor Yellow }
    Write-Host "  [WhatIf] its folder stays as it is: $cardsLine" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [-] Would retire the Space '$target' -- $label" -ForegroundColor Green
    exit 0
}

$configScript = Join-Path $scriptsDir 'Set-ToolkitConfig.ps1'
$global:LASTEXITCODE = 0
$out = & $configScript -Set $setPair -Hub *>&1 | Out-String
$code = $LASTEXITCODE
. $loadHelpers
Write-Host $out.TrimEnd()
if ($code -and $code -ne 0) { exit $code }
if ($localStatus) {
    $global:LASTEXITCODE = 0
    $out = & $configScript -Unset "spaces.$target.status" *>&1 | Out-String
    $code = $LASTEXITCODE
    . $loadHelpers
    Write-Host $out.TrimEnd()
    if ($code -and $code -ne 0) { exit $code }
}
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "${prefix}RetireSpace" -Detail "$target $oldStatus -> archive"
}

Write-Host ""
Write-Host "  [-] Retired the Space '$target' -- $label" -ForegroundColor Green
Write-Host "      cards: $cardsLine -- kept, and readable"
Write-Host "      Nothing asks its tracker now. To bring it back:"
Write-Host "    ${prefix}Config -Set spaces.$target.status=$(if ($oldStatus) { $oldStatus } else { 'local' }) -Hub"
exit 0
