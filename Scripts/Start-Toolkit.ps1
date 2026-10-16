<#
.SYNOPSIS
    The first run: give this machine a hub with something in it, and open the UI.

.DESCRIPTION
    A new machine has the Toolkit and nothing to show in it: no hub, no org, no
    cards. Getting from there to a working page used to be a page of
    docs/CONFIGURATION.md -- write a sparse config.local.json by hand, point it
    at a folder you made, declare an org, know what a slug is.

    This verb does that once:

      1. COPIES the sample hub that ships in samples/hub to a folder YOU own
         (-Path, default ~/toolkit-hub). Copied OUT, never used in place: a hub
         inside the package would make the Toolkit's own git tree dirty the
         first time a box was ticked, and Update refuses a dirty tree.
      2. Points this machine at it -- promptsRoot and activeSpace -- and switches
         the four opt-in modules on (growth, communication, deck and organize), so there is a whole product to look at.
         All through the Config verb, the one writer for configuration.
      3. Opens the web UI (skip with -NoWeb).

    The sample hub's 'demo' Space is where this lands: status 'local', it works
    from the files alone and never contacts a tracker, so a first run needs no
    login, no `az` and no network. The hub also declares 'github-demo',
    the same product tracked on a public GitHub repo -- local too until you
    connect it -- and its cards come along in the copy, as do the cards of the
    Azure demo (slug 'azure-demo', declared by config.default.json, local and with no
    address until you give it your organisation's). Your real Space is added
    later, from Settings in the web UI.

    It refuses rather than guesses, and it never overwrites:
      - a machine that already has a hub keeps it -- this only opens the UI;
      - a target folder with anything in it is a stated refusal (exit 2).

.PARAMETER Path
    Where your hub goes. Default: ~/toolkit-hub.

.PARAMETER NoWeb
    Set up the hub and stop; do not start the web UI.

.PARAMETER WhatIf
    Say what would be copied and written. Change nothing.

.EXAMPLE
    {cliPrefix}Start
.EXAMPLE
    {cliPrefix}Start -Path ~/work/hub -NoWeb

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoWeb', Justification = 'Read inside the $openWeb scriptblock, which the rule does not follow.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path,
    [switch]$NoWeb,
    [switch]$Help
)

# The prefix is config, never a literal. Run without the module there may be no
# config at all, and then the bare verb name is still right.
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

function Write-StartRefusal {
    param([string]$Message, [string]$Hint)
    Write-Host ""
    Write-Host "Error: $Message" -ForegroundColor Red
    if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    Write-Host ""
}

$prefix = Get-CliPrefix

if ($Help) {
    Write-Host @"

${prefix}Start - the first run: a hub with something in it, and the UI open

USAGE:
    ${prefix}Start                    Copy the sample hub to ~/toolkit-hub, point this machine at it, open the UI
    ${prefix}Start -Path <folder>     ...somewhere else
    ${prefix}Start -NoWeb             Set up the hub; do not start the UI
    ${prefix}Start -WhatIf            Say what would happen; change nothing

The sample org, Demo, works from its own files: no account, no login, no network.
A machine that already has a hub keeps it, and a folder with anything in it is never written to.

"@
    return
}

$pkgRoot = Split-Path -Parent $PSScriptRoot
$samples = Join-Path (Join-Path $pkgRoot 'samples') 'hub'
$sampleOrg = 'demo'

# A scriptblock in a VARIABLE, not a function. This script runs under the module,
# and the re-import below resets the module's function table -- a function
# defined here is 'not recognized' afterwards, while a local variable survives.
# (AGENTS.md, the $script: scope trap; found by the first end-to-end run.)
$openWeb = {
    if ($NoWeb) { return }
    if ($WhatIfPreference) { Write-Host "  (-WhatIf: the web UI was not started)" -ForegroundColor Yellow; return }
    $webCommand = $null
    if ($prefix) { $webCommand = Get-Command "${prefix}Web" -ErrorAction SilentlyContinue }
    if (-not $webCommand) {
        Write-Host "  The hub is ready. Start the UI with ${prefix}Web in a new shell." -ForegroundColor Yellow
        return
    }
    Write-Host "Web UI:" -ForegroundColor Cyan
    # Through the verb's ALIAS, the way a person types it -- see Update-Toolkit.ps1
    # for what happens to a wrapper called by its function name.
    & "${prefix}Web"
}

# ---- a machine that already has a hub keeps it --------------------------------
# "Has a hub" means someone SAID where it is -- PROMPTS_ROOT, or promptsRoot in
# either config file. Not "the module resolved a folder": with nothing set it
# falls back to the package's parent folder (the layout the Toolkit grew up in),
# which exists on every machine, so the first real run of this verb looked at a
# fresh clone and announced that it already had a hub.
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
$configured = Get-P20ConfiguredHub -PackageRoot $pkgRoot
if ($configured) {
    $resolved = ''
    if ($global:P20Config -and $global:P20Config.PromptsRoot) { $resolved = [string]$global:P20Config.PromptsRoot }
    if (-not $resolved) { $resolved = $configured }
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        Write-Host ""
        Write-Host "This machine already has a hub: $resolved" -ForegroundColor Green
        Write-Host "  Nothing was copied and nothing was changed." -ForegroundColor Gray
        Write-Host ""
        & $openWeb
        exit 0
    }
    Write-StartRefusal -Message "This machine is pointed at a hub that is not there: $resolved" `
        -Hint "Fix the path (${prefix}Config -Set promptsRoot=<folder>), or clear it and run ${prefix}Start again. Nothing was copied."
    exit 2  # stated refusal -- a configured hub that has gone missing is not a first run
}

if (-not (Test-Path -LiteralPath (Join-Path $samples 'hub.json') -PathType Leaf)) {
    Write-StartRefusal -Message "The sample hub is missing from this copy of the Toolkit ($samples)." `
        -Hint 'Make a folder for your hub and set it by hand: see docs/CONFIGURATION.md.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# ---- where it goes ------------------------------------------------------------
if (-not $Path) { $Path = Join-Path $HOME 'toolkit-hub' }
if ($Path.StartsWith('~')) { $Path = Join-Path $HOME $Path.Substring(1).TrimStart('/', '\') }
$target = [System.IO.Path]::GetFullPath($Path)

# A bare StartsWith on the raw string treats a SIBLING whose name happens to
# begin with the package folder's name as "inside" it -- the house layout hits
# this exactly: the Toolkit at ~/Repos/toolkit and the hub at
# ~/Repos/toolkit-hub, where the hub's path does start with the Toolkit's, one
# character short of a directory separator.
#
# Compare whole path segments instead: refuse only when the target IS the
# package root, or sits under it with a separator between the two.
$pkgRootFull = [System.IO.Path]::GetFullPath($pkgRoot).TrimEnd('\', '/')
$pkgRootWithSep = $pkgRootFull + [System.IO.Path]::DirectorySeparatorChar
$insidePackage = $target.Equals($pkgRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
    $target.StartsWith($pkgRootWithSep, [System.StringComparison]::OrdinalIgnoreCase)
if ($insidePackage) {
    Write-StartRefusal -Message "A hub cannot live inside the Toolkit's own folder ($pkgRoot)." `
        -Hint "It would make the Toolkit's git tree dirty, and ${prefix}Update refuses a dirty tree. Choose a folder outside it."
    exit 2  # stated refusal
}

if (Test-Path -LiteralPath $target) {
    $existing = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-StartRefusal -Message "'$target' already has $($existing.Count) item(s) in it; nothing was copied." `
            -Hint "If it is a hub you want to use: ${prefix}Config -Set promptsRoot=$target   Otherwise choose another folder with -Path."
        exit 2  # stated refusal -- this verb never overwrites
    }
}

$files = @(Get-ChildItem -LiteralPath $samples -Recurse -File -Force)
Write-Host ""
Write-Host "First run" -ForegroundColor Cyan
Write-Host "  Your hub:   $target" -ForegroundColor White
# What the reader HAS, not what they lack: a person who has never heard of a work
# item is not told which tracker this is not talking to (docs/modules/ado.md).
Write-Host "  Sample Space: Demo -- works from its own files. No account, no login, no network." -ForegroundColor White
# The other demo Spaces are invitations, not steps: named once, never required.
Write-Host "  Also there:   the GitHub demo and the Azure demo -- connect either when you like (${prefix}Connect github-demo, ${prefix}Connect azure-demo)." -ForegroundColor Gray
Write-Host "  Copying:    $($files.Count) sample files" -ForegroundColor Gray

if (-not $PSCmdlet.ShouldProcess($target, "copy the sample hub and point this machine at it")) {
    Write-Host "  (-WhatIf: nothing was copied and no configuration was written)" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
    # Children, not the folder: -Recurse onto an existing folder nests it a level down.
    foreach ($child in (Get-ChildItem -LiteralPath $samples -Force)) {
        Copy-Item -LiteralPath $child.FullName -Destination $target -Recurse -Force -ErrorAction Stop
    }
}
catch {
    Write-StartRefusal -Message "Could not copy the sample hub to '$target'." -Hint $_.Exception.Message
    exit 2  # stated refusal
}
Write-Host "  Copied." -ForegroundColor Green

# ---- the day-1 reminder: due TODAY, on the copy -----------------------------------
# The one post-copy edit. The sample ships with no Due line, because any date
# written into the package is in the past by the time someone runs this; stamped
# here, on the COPY, it lands in Organize's Today bucket on day one. A day, not a
# moment, so it is not overdue by the afternoon. The package's file is never touched.
$dayOne = Join-Path (Join-Path (Join-Path $target 'reminders') 'current') 'D1WK-welcome-to-your-first-day.md'
if (Test-Path -LiteralPath $dayOne) {
    . (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
    [void](Set-P20CardLine -Path $dayOne -Stamp (Get-P20Consts).stamps.due -Value (Get-Date).ToString('yyyy-MM-dd'))
}

# ---- point this machine at it: through Config, the one writer -------------------
$configCommand = $null
if ($prefix) { $configCommand = Get-Command "${prefix}Config" -ErrorAction SilentlyContinue }
if (-not $configCommand) {
    Write-StartRefusal -Message 'The hub is copied, but the Config verb is not loaded in this shell, so nothing points at it yet.' `
        -Hint "In a new shell: ${prefix}Config -Set promptsRoot=$target,activeSpace=$sampleOrg"
    exit 2  # stated refusal
}
# TWO writes, in this order. The sample org is declared by the hub's own hub.json,
# so until promptsRoot points there 'demo' is not an org this machine knows, and
# Config -- rightly -- refuses an activeSpace it cannot find. Written together, the
# first real run copied the hub and then failed to point at it.
# Then the four opt-in modules, ON. They are off by default because a module is
# a choice -- but a first run is the one moment someone is asking "what does
# this do?", and an empty Growth tab they never see answers nothing. Each is one
# switch in Settings to turn off again.
# And the Home banner that offers the tour deck, which its own Dismiss turns off.
# The flags below and the closing line are built from ONE table, so a fourth
# (or fifth) module turned on here cannot say otherwise in the sentence a new
# user reads last -- the exact slip this fixes:
#the flags already
# wrote all four, the sentence still named three.
$moduleFlags = [ordered]@{
    'features.growth'        = 'Growth'
    'features.communication' = 'Meetings'
    'features.deck'          = 'Decks'
    'features.organize'      = 'Organize'
}
$settings = @("promptsRoot=$target", "activeSpace=$sampleOrg")
foreach ($flag in $moduleFlags.Keys) { $settings += "$flag=true" }
$settings += 'firstRun.welcome=true'
foreach ($setting in $settings) {
    & "${prefix}Config" -Set $setting | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-StartRefusal -Message "The hub is copied, but '$setting' could not be written." `
            -Hint "By hand, in this order: ${prefix}Config -Set promptsRoot=$target   then   ${prefix}Config -Set activeSpace=$sampleOrg"
        exit 2  # stated refusal
    }
}
$moduleNames = @($moduleFlags.Values)
$moduleList = $moduleNames[0]
if ($moduleNames.Count -eq 2) { $moduleList = "$($moduleNames[0]) and $($moduleNames[1])" }
elseif ($moduleNames.Count -gt 2) {
    $moduleList = ($moduleNames[0..($moduleNames.Count - 2)] -join ', ') + ' and ' + $moduleNames[-1]
}
Write-Host "  This machine now points at it, with Demo as the active Space and the $moduleList modules on." -ForegroundColor Green

# The running shell still holds the config it was imported with -- no hub, the
# shipped org. Re-import so THIS shell, and the UI it is about to start, see the
# hub that was just written.
$manifest = Join-Path (Join-Path $pkgRoot 'Prompt20Toolkit') 'Prompt20Toolkit.psd1'
if ((Get-Module | Where-Object { $_.Path -like "$pkgRoot*" }) -and (Test-Path $manifest)) {
    try { Import-Module $manifest -Force -Global -WarningAction SilentlyContinue -ErrorAction Stop 3>$null 6>$null }
    catch { Write-Host "  Open a new shell before using the other verbs ($($_.Exception.Message))." -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "  Ready. What is in the hub is in its README: $(Join-Path $target 'README.md')" -ForegroundColor Green
Write-Host "  Your real Space is added from Settings in the web UI (your avatar, top right)." -ForegroundColor Gray
Write-Host ""

$global:LASTEXITCODE = 0
& $openWeb
exit $LASTEXITCODE
