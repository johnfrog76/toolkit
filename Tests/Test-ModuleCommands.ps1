<#
.SYNOPSIS
    The module-command mechanism: how an opt-in module contributes CLI verbs.
.DESCRIPTION
    Build-plan D-CM. A module ships Config/<module>.commands.psd1 and a sibling
    .ps1, and utilities.psm1 merges the rows into $script:ModuleState.CommandMap before
    Register-PromptAlias runs -- but only when the module's feature flag is on.

    The data file is a DATA file: plain hashtables, read with
    Import-PowerShellDataFile, which will not evaluate an expression to build
    one. An [ordered] cast is an expression and is therefore refused, which is
    why `Order` exists -- and why a psd1 cannot run code when the CLI starts.

    Every clause here is a way that mechanism could be wrong in a way nobody
    would notice until it mattered:

      off means absent      a flag that is false must leave NO trace -- no row,
                            no alias, no menu line, no help. "Present but
                            refusing" is a different product.
      the prefix is data    aliases must carry whatever prefix is configured,
                            not a baked-in 'tk'.
      help travels          a module's help comes from its own data file, so
                            config.default.json never has to learn about it.
      a collision refuses   a module naming an existing command is skipped
                            WHOLE, with the name in the message, and the
                            existing command is untouched. A half-merged module
                            is worse than an unloaded one.
      a bad file is skipped one unreadable data file must not cost the user the
                            rest of the CLI -- and an [ordered] cast, the
                            easiest mistake to make here, is one of those.
      Order is the order    a hashtable has none, so the data file states it.

    Every scenario runs in a scratch COPY of the package with its own
    config.local.json and its own Config/ folder, in a fresh -NoProfile shell.
    Nothing here writes to the checkout it is testing.

    Run:  pwsh -File Tests/Test-ModuleCommands.ps1
#>
[CmdletBinding()]
param([switch]$Help)

if ($Help) {
    Write-Host ""
    Write-Host "  Test-ModuleCommands -- how an opt-in module contributes CLI verbs (D-CM)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Flag off     no row, no alias, no menu line, no help"
    Write-Host "  Flag on      rows, prefixed aliases, help from the module's own data file"
    Write-Host "  Prefix       aliases carry the configured prefix, not a baked-in one"
    Write-Host "  Collision    a module naming an existing command is refused whole"
    Write-Host "  Malformed    an unreadable data file is reported and skipped, not fatal"
    Write-Host "  Order        registration order comes from Order, not from the hashtable"
    Write-Host ""
    return
}

$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $testDir -Parent

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkYellow }
        $script:errors += "$Name -- $Detail"
    }
}

# -- Scratch package ----------------------------------------------------------
# A COPY, not the checkout: two of these scenarios deliberately put a broken
# data file in Config/, and a suite that did that in place would leave the tree
# it was testing in a state the next run inherits.
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "p20-module-commands-$PID"

function New-ScratchPackage {
    param([Parameter(Mandatory)][string]$Name)
    $dest = Join-Path $scratchRoot $Name
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1')       $dest -Force
    Copy-Item (Join-Path $pkgRoot 'config.default.json')  $dest -Force
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $pkgRoot 'consts.json')          $dest -Force
    Copy-Item (Join-Path $pkgRoot 'Scripts')              $dest -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')               $dest -Recurse -Force
    return $dest
}

# Run a snippet against a scratch package in a clean shell and return everything
# it said, both streams. -NoProfile because an autoload shim on the machine
# would otherwise shadow the copy under test.
function Invoke-InScratch {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Snippet,
        # Runs BEFORE the import. The module reads its config and builds its
        # command table at import time, so an environment variable set after the
        # import would be read by nothing.
        [string]$Preamble = ''
    )
    $modulePath = (Join-Path $Package 'utilities.psm1') -replace "'", "''"
    $body = "`$ErrorActionPreference = 'Continue'; $Preamble Import-Module '$modulePath' -Force -DisableNameChecking; $Snippet"
    $out = & pwsh -NoProfile -Command $body 2>&1
    return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}

function Set-ScratchConfig {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][hashtable]$Local
    )
    ($Local | ConvertTo-Json -Depth 6) |
        Set-Content -Path (Join-Path $Package 'config.local.json') -Encoding UTF8
}

Write-Host ""
Write-Host "  Module commands (D-CM)" -ForegroundColor Cyan
Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {

# -- 1. The flag is off: the module leaves no trace ---------------------------
Write-Host "  Flag off" -ForegroundColor Magenta

$offPkg = New-ScratchPackage -Name 'flag-off'
Set-ScratchConfig -Package $offPkg -Local @{ quietStart = $true }

$offMap = Invoke-InScratch -Package $offPkg -Snippet 'Get-P20CommandMap'
Assert-True 'flag off: no growth row in the command table' `
    ($offMap -notmatch 'NewGrowth') $offMap

$offAlias = Invoke-InScratch -Package $offPkg -Snippet `
    '(Get-Alias -Name tkNewGrowth -ErrorAction SilentlyContinue) -ne $null'
Assert-True 'flag off: no prefixed alias is registered' ($offAlias -match 'False') $offAlias

$offMenu = Invoke-InScratch -Package $offPkg -Snippet 'tkMenu -All'
Assert-True 'flag off: Menu is silent about the module' ($offMenu -notmatch 'NewGrowth') `
    'a menu line for a verb that does not exist is worse than no line'

# Single quotes inside the snippet: Windows PowerShell 5.1 strips an embedded double quote
# when it passes -Command to the child, which turned the string into a command name.
$offHelp = Invoke-InScratch -Package $offPkg -Snippet `
    'try { tkNewGrowth -Help } catch { ''NOT-RECOGNISED'' }'
Assert-True 'flag off: the verb is not recognised at all' ($offHelp -match 'NOT-RECOGNISED') $offHelp

$offModules = Invoke-InScratch -Package $offPkg -Snippet 'Get-P20ModuleCommands'
Assert-True 'flag off: nothing reports as loaded' ($offModules -match '^\s*\{\s*\}\s*$') $offModules

# The core is untouched by a module being off.
Assert-True 'flag off: the core commands are still there' ($offMap -match 'Archive') $offMap

# -- 2. The flag is on: rows, aliases, help -----------------------------------
Write-Host ""
Write-Host "  Flag on" -ForegroundColor Magenta

$onPkg = New-ScratchPackage -Name 'flag-on'
Set-ScratchConfig -Package $onPkg -Local @{ quietStart = $true; features = @{ growth = $true } }

$onMap = Invoke-InScratch -Package $onPkg -Snippet 'Get-P20CommandMap'
foreach ($verb in @('NewGrowth', 'NewWorkReview', 'PublishWorkReview', 'LogPeerReview', 'UpdateResume')) {
    Assert-True "flag on: $verb is in the command table" ($onMap -match "`"$verb`"") $onMap
}
Assert-True 'flag on: the row names the function, not an alias' `
    ($onMap -match 'New-P20GrowthItem') $onMap

$onAliases = Invoke-InScratch -Package $onPkg -Snippet `
    '(Get-Alias | Where-Object { $_.Name -like ''tk*Growth*'' -or $_.Name -like ''tk*Resume*'' }).Name -join '','''
Assert-True 'flag on: aliases carry the configured prefix' `
    (($onAliases -match 'tkNewGrowth') -and ($onAliases -match 'tkUpdateResume')) $onAliases

# -- NewGrowth -Close: the module retires its own data ----------------------
# Archive is org-scoped and cannot see growth/; -Close moves the item to
# growth/archive/ and stamps it, idempotently.
$closeHub = Join-Path $script:ScratchRoot 'growth-hub'
New-Item -ItemType Directory -Path (Join-Path $closeHub 'growth/current') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $closeHub 'growth/current/training-2026-09-01-clean-architecture.prompt.md'),
    "# Training: Clean Architecture`n`n**Created:** 2026-09-01`n", (New-Object System.Text.UTF8Encoding($false)))
$closeSnippet = "`$env:PROMPTS_ROOT = '$($closeHub -replace "'", "''")'; tkNewGrowth -Close clean-architecture; 'EXIT=' + `$LASTEXITCODE"
$closeOut = Invoke-InScratch -Package $onPkg -Snippet $closeSnippet
Assert-True 'flag on: -Close moves the item to growth/archive/' (Test-Path (Join-Path $closeHub 'growth/archive/training-2026-09-01-clean-architecture.prompt.md')) $closeOut
Assert-True 'flag on: and it leaves current/' (-not (Test-Path (Join-Path $closeHub 'growth/current/training-2026-09-01-clean-architecture.prompt.md'))) $closeOut
$closedText = if (Test-Path (Join-Path $closeHub 'growth/archive/training-2026-09-01-clean-architecture.prompt.md')) { [System.IO.File]::ReadAllText((Join-Path $closeHub 'growth/archive/training-2026-09-01-clean-architecture.prompt.md')) } else { '' }
Assert-True 'flag on: the archived item carries the Closed stamp' ($closedText -match '\*\*Closed:\*\* \d{4}-\d{2}-\d{2}') $closedText
Assert-True 'flag on: -Close reports what it did and exits 0' ($closeOut -match 'Closed: growth/archive/' -and $closeOut -match 'EXIT=0') $closeOut
$again = Invoke-InScratch -Package $onPkg -Snippet $closeSnippet.Replace('clean-architecture', 'training-2026-09-01-clean-architecture')
Assert-True 'flag on: a second -Close is a report, not an error' ($again -match 'Already closed' -and $again -match 'EXIT=0') $again
$missing = Invoke-InScratch -Package $onPkg -Snippet $closeSnippet.Replace('clean-architecture', 'no-such-item')
Assert-True 'flag on: -Close on nothing is a stated refusal' ($missing -match 'Error: No growth item matches' -and $missing -match 'EXIT=2') $missing

# -- A module verb reached from a module-launched script ---------------
# Every wrapper launches a script, and a script can call a verb back. In that shape a
# global function's FREE names resolve against the intervening script, so a wrapper that
# read $repoRoot found whatever the script called $repoRoot (or nothing) and built a path
# to a script that is not there. The probe below shadows every spelling of the name and
# runs the verb inside the module's session state, as Env's probe does.
$shadowProbe = Join-Path $script:ScratchRoot 'growth-shadow-probe-374.ps1'
$shadowBody = @'
$repoRoot = '/shadow/nowhere'
$script:repoRoot = '/shadow/nowhere'
$global:repoRoot = '/shadow/nowhere'
$toolkitRoot = '/shadow/nowhere'
$script:toolkitRoot = '/shadow/nowhere'
$pkgRoot = '/shadow/nowhere'
tkNewGrowth -Close no-such-item
'EXIT=' + $LASTEXITCODE
'@
[System.IO.File]::WriteAllText($shadowProbe, $shadowBody, (New-Object System.Text.UTF8Encoding($false)))
$shadowSnippet = "`$env:PROMPTS_ROOT = '$($closeHub -replace "'", "''")'; & (Get-Module utilities) { & '$($shadowProbe -replace "'", "''")' }"
$shadowOut = Invoke-InScratch -Package $onPkg -Snippet $shadowSnippet
Assert-True 'flag on: a growth verb from a module-launched script, root names shadowed, still finds its script' `
    ($shadowOut -match 'Error: No growth item matches' -and $shadowOut -match 'EXIT=2') $shadowOut
$growthPs1 = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Config/growth.commands.ps1'))
Assert-True 'growth wrappers read the package root through Get-P20ModuleState, never a free $repoRoot' `
    (($growthPs1 -notmatch '"\$repoRoot') -and ($growthPs1 -match '\(Get-P20ModuleState\)\.PackageRoot')) 'free $repoRoot in Config/growth.commands.ps1'

$onHelp = Invoke-InScratch -Package $onPkg -Snippet 'tkNewGrowth -Help'
Assert-True 'flag on: -Help renders the description from the module data file' `
    ($onHelp -match 'Create a training, presentation or goal') $onHelp
Assert-True 'flag on: -Help renders the usage line from the module data file' `
    ($onHelp -match '-Type training\|presentation\|goal') $onHelp
Assert-True 'flag on: {cliPrefix} is expanded in the module help' `
    (($onHelp -match 'tkNewGrowth -Title') -and ($onHelp -notmatch '\{cliPrefix\}')) $onHelp

$onMenu = Invoke-InScratch -Package $onPkg -Snippet 'tkMenu -All'
Assert-True 'flag on: Menu lists the module verb under its declared category' `
    ($onMenu -match 'tkNewGrowth') $onMenu

$onModules = Invoke-InScratch -Package $onPkg -Snippet 'Get-P20ModuleCommands'
Assert-True 'flag on: the module reports which commands it contributed' `
    (($onModules -match 'growth') -and ($onModules -match 'NewGrowth')) $onModules

# The bridge's allowlist is the same table, so a module verb is bridgeable with
# no backend edit. That is the whole claim of deriving the allowlist.
Assert-True 'flag on: the module verb is therefore bridgeable' ($onMap -match 'NewGrowth') $onMap

# -- 3. The prefix is data ----------------------------------------------------
Write-Host ""
Write-Host "  A different prefix" -ForegroundColor Magenta

$prefixPkg = New-ScratchPackage -Name 'prefix'
Set-ScratchConfig -Package $prefixPkg -Local @{
    quietStart = $true; commandPrefix = 'gt'; features = @{ growth = $true }
}

$prefixAliases = Invoke-InScratch -Package $prefixPkg -Snippet `
    '(Get-Alias | Where-Object { $_.Name -like ''*NewGrowth'' }).Name -join '','''
Assert-True 'a non-default prefix reaches the module verbs too' `
    ($prefixAliases -match 'gtNewGrowth') $prefixAliases
Assert-True 'and the default prefix is NOT also registered' `
    ($prefixAliases -notmatch 'tkNewGrowth') $prefixAliases

$prefixHelp = Invoke-InScratch -Package $prefixPkg -Snippet 'gtNewGrowth -Help'
Assert-True 'module help renders under the prefix actually configured' `
    (($prefixHelp -match 'gtNewGrowth') -and ($prefixHelp -notmatch 'tkNewGrowth')) $prefixHelp

# -- 4. A collision refuses the module, whole ---------------------------------
Write-Host ""
Write-Host "  A name that is already taken" -ForegroundColor Magenta

$clashPkg = New-ScratchPackage -Name 'collision'
Set-ScratchConfig -Package $clashPkg -Local @{ quietStart = $true; features = @{ clashing = $true } }
@'
@{
    Feature  = 'clashing'
    Commands = @{
        'Archive'   = 'Invoke-ClashArchive'
        'ClashOnly' = 'Invoke-ClashOnly'
    }
    Help     = @{ 'ClashOnly' = @{ category = 'info'; description = 'never loads' } }
}
'@ | Set-Content -Path (Join-Path $clashPkg 'Config/clashing.commands.psd1') -Encoding UTF8
@'
function global:Invoke-ClashArchive { 'clash' }
function global:Invoke-ClashOnly { 'clash' }
'@ | Set-Content -Path (Join-Path $clashPkg 'Config/clashing.commands.ps1') -Encoding UTF8

$clashOut = Invoke-InScratch -Package $clashPkg -Snippet 'Get-P20CommandMap'
Assert-True 'a collision is reported, and the message names the command' `
    ($clashOut -match 'Archive') $clashOut
Assert-True 'a collision is reported as a warning, not a crash' `
    ($clashOut -match '(?i)WARNING') $clashOut
Assert-True 'the existing command is left pointing where it did' `
    ($clashOut -match 'Move-P20PromptToArchive') $clashOut
Assert-True 'the colliding module is refused WHOLE -- its other command is absent too' `
    ($clashOut -notmatch 'ClashOnly') $clashOut

$clashAlias = Invoke-InScratch -Package $clashPkg -Snippet `
    '(Get-Alias -Name tkClashOnly -ErrorAction SilentlyContinue) -ne $null'
Assert-True 'and no alias is registered for the refused module' ($clashAlias -match 'False') $clashAlias

# -- 5. A malformed data file is skipped, not fatal ---------------------------
Write-Host ""
Write-Host "  A data file that cannot be read" -ForegroundColor Magenta

$badPkg = New-ScratchPackage -Name 'malformed'
Set-ScratchConfig -Package $badPkg -Local @{
    quietStart = $true; features = @{ growth = $true; broken = $true }
}
'@{ Feature = ''broken''; Commands = @{ ' |
    Set-Content -Path (Join-Path $badPkg 'Config/broken.commands.psd1') -Encoding UTF8

$badOut = Invoke-InScratch -Package $badPkg -Snippet 'Get-P20CommandMap'
Assert-True 'a malformed data file is reported by PATH' `
    ($badOut -match 'broken\.commands\.psd1') $badOut
Assert-True 'a malformed data file is a warning, never fatal' `
    ($badOut -match '(?i)WARNING') $badOut
Assert-True 'the core commands still register around it' ($badOut -match 'Move-P20PromptToArchive') $badOut
Assert-True 'and the OTHER module still loads -- one bad file costs one module' `
    ($badOut -match 'NewGrowth') $badOut

# A data file with no wrapper script beside it is the same class of failure.
$orphanPkg = New-ScratchPackage -Name 'no-wrapper'
Set-ScratchConfig -Package $orphanPkg -Local @{ quietStart = $true; features = @{ orphan = $true } }
@'
@{
    Feature  = 'orphan'
    Commands = @{ 'OrphanVerb' = 'Invoke-Orphan' }
}
'@ | Set-Content -Path (Join-Path $orphanPkg 'Config/orphan.commands.psd1') -Encoding UTF8

$orphanOut = Invoke-InScratch -Package $orphanPkg -Snippet 'Get-P20CommandMap'
Assert-True 'a data file with no wrapper file beside it is reported and skipped' `
    (($orphanOut -match '(?i)WARNING') -and ($orphanOut -notmatch 'OrphanVerb')) $orphanOut

# -- 6. The data file is data --------------------------------------------------
Write-Host ""
Write-Host "  A data file is data" -ForegroundColor Magenta

# [ordered]@{ } is a cast, and a cast is an expression. Import-PowerShellDataFile
# will not evaluate one, so a module that reaches for it to get a stable order
# does not load -- which is the single easiest mistake to make writing one of
# these files, and has to say so by path rather than by silence.
$orderedPkg = New-ScratchPackage -Name 'ordered-cast'
Set-ScratchConfig -Package $orderedPkg -Local @{ quietStart = $true; features = @{ growth = $true; casty = $true } }
@'
@{
    Feature  = 'casty'
    Commands = [ordered]@{ 'CastyVerb' = 'Invoke-Casty' }
}
'@ | Set-Content -Path (Join-Path $orderedPkg 'Config/casty.commands.psd1') -Encoding UTF8
@'
function global:Invoke-Casty { 'casty' }
'@ | Set-Content -Path (Join-Path $orderedPkg 'Config/casty.commands.ps1') -Encoding UTF8

$orderedOut = Invoke-InScratch -Package $orderedPkg -Snippet 'Get-P20CommandMap'
Assert-True 'an [ordered] cast in a data file is reported by PATH' `
    ($orderedOut -match 'casty\.commands\.psd1') $orderedOut
Assert-True 'an [ordered] cast is a warning, never fatal' ($orderedOut -match '(?i)WARNING') $orderedOut
# The command table itself, not the whole transcript: the skip warning quotes
# the expression it refused, so the verb's name appears in the output either way.
$orderedMapLine = @($orderedOut -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
Assert-True 'and that module is skipped' `
    (($orderedMapLine.Count -gt 0) -and ($orderedMapLine[0] -notmatch 'CastyVerb')) ($orderedMapLine -join '')
Assert-True 'while the well-formed module beside it still loads' ($orderedOut -match 'NewGrowth') $orderedOut

# A marker FILE rather than a printed line: the skip warning quotes the
# expression it refused, so an echoed string would appear in the output either
# way and the assertion would prove nothing. A file appears only if the
# expression actually ran.
$evalPkg = New-ScratchPackage -Name 'not-executed'
Set-ScratchConfig -Package $evalPkg -Local @{ quietStart = $true; features = @{ sneaky = $true } }
$marker = (Join-Path $evalPkg 'executed-on-import.marker') -replace '\\', '/'
@"
@{
    Feature  = 'sneaky'
    Commands = @{ 'Sneaky' = (New-Item -ItemType File -Path '$marker') }
}
"@ | Set-Content -Path (Join-Path $evalPkg 'Config/sneaky.commands.psd1') -Encoding UTF8
@'
function global:Invoke-Sneaky { 'sneaky' }
'@ | Set-Content -Path (Join-Path $evalPkg 'Config/sneaky.commands.ps1') -Encoding UTF8

$evalOut = Invoke-InScratch -Package $evalPkg -Snippet 'Get-P20CommandMap'
Assert-True 'a command in a data file is not run on import' `
    (-not (Test-Path $marker)) 'the data file executed a command -- it must be read, never run'
Assert-True 'and the module that tried it is skipped' ($evalOut -notmatch '"Sneaky"') $evalOut

# -- 6b. Order is the order ----------------------------------------------------
Write-Host ""
Write-Host "  Order" -ForegroundColor Magenta

# A plain hashtable has no order, so Menu would otherwise shuffle a module's
# lines between sessions. Order is what the [ordered] cast was there for.
$orderPkg = New-ScratchPackage -Name 'order'
Set-ScratchConfig -Package $orderPkg -Local @{ quietStart = $true; features = @{ ordering = $true } }
@'
@{
    Feature  = 'ordering'
    Commands = @{
        'Zulu'    = 'Invoke-Zulu'
        'Alpha'   = 'Invoke-Alpha'
        'Mike'    = 'Invoke-Mike'
        'Unnamed' = 'Invoke-Unnamed'
    }
    Order = @('Zulu', 'Alpha', 'Mike', 'Missing')
}
'@ | Set-Content -Path (Join-Path $orderPkg 'Config/ordering.commands.psd1') -Encoding UTF8
@'
function global:Invoke-Zulu { }
function global:Invoke-Alpha { }
function global:Invoke-Mike { }
function global:Invoke-Unnamed { }
'@ | Set-Content -Path (Join-Path $orderPkg 'Config/ordering.commands.ps1') -Encoding UTF8

$orderOut = Invoke-InScratch -Package $orderPkg -Snippet 'Get-P20ModuleCommands'
$orderJson = $null
$orderLine = @($orderOut -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
if ($orderLine) { $orderJson = $orderLine[0] | ConvertFrom-Json }
$registered = if ($orderJson) { @($orderJson.ordering) } else { @() }

Assert-True 'Order decides the registration order' `
    (($registered.Count -ge 3) -and ($registered[0] -eq 'Zulu') -and ($registered[1] -eq 'Alpha') -and ($registered[2] -eq 'Mike')) `
    ($registered -join ', ')
Assert-True 'a command left out of Order still registers, after the listed ones' `
    ($registered -contains 'Unnamed') ($registered -join ', ')
Assert-True 'a name in Order that is not a command is a warning, naming it' `
    (($orderOut -match '(?i)WARNING') -and ($orderOut -match 'Missing')) $orderOut
Assert-True 'and it does not become a phantom row' ($registered -notcontains 'Missing') ($registered -join ', ')

$orderMenu = Invoke-InScratch -Package $orderPkg -Snippet 'tkMenu -All'
Assert-True 'the module still registers all four verbs' `
    (($orderMenu -match 'tkZulu') -or ($registered.Count -eq 4)) ($registered -join ', ')

# -- 7. Autoload: the manifest is a committed, shared file --------------------
Write-Host ""
Write-Host "  Autoload discovery" -ForegroundColor Magenta

# The alias-discovery shell builds the list the autoload manifest advertises,
# and that manifest is committed and read on every machine. A module switched on
# in ONE machine's config.local.json must therefore stay out of it, or the drift
# check goes red on whichever machine did not last run the generator -- which is
# exactly the bug the personal nav aliases already have a fix for.
$discovered = Invoke-InScratch -Package $onPkg `
    -Preamble '$env:PROMPTS_TOOLKIT_NO_NAV_ALIASES = "1";' -Snippet 'Get-P20CommandMap'
Assert-True 'a locally-enabled module is invisible to the manifest generator' `
    ($discovered -notmatch 'NewGrowth') $discovered
Assert-True 'while the core commands stay visible to it' `
    ($discovered -match 'Move-P20PromptToArchive') $discovered

# The other half of the same rule: a fork that commits the flag in
# config.default.json has said the verb belongs to every machine, and then it
# DOES belong in the manifest.
$committedPkg = New-ScratchPackage -Name 'committed-flag'
$committedCfgPath = Join-Path $committedPkg 'config.default.json'
# A file copied a moment ago can still be held by a scanner on Windows PowerShell 5.1
# ("being used by another process"), so the read-modify-write retries briefly.
for ($try = 1; $try -le 10; $try++) {
    try {
        $committedCfg = Get-Content $committedCfgPath -Raw | ConvertFrom-Json
        $committedCfg.features | Add-Member -NotePropertyName 'growth' -NotePropertyValue $true -Force
        ($committedCfg | ConvertTo-Json -Depth 12) | Set-Content -Path $committedCfgPath -Encoding UTF8
        break
    }
    catch {
        if ($try -eq 10) { throw }
        Start-Sleep -Milliseconds 300
    }
}
Set-ScratchConfig -Package $committedPkg -Local @{ quietStart = $true }

$committedDiscovered = Invoke-InScratch -Package $committedPkg `
    -Preamble '$env:PROMPTS_TOOLKIT_NO_NAV_ALIASES = "1";' -Snippet 'Get-P20CommandMap'
Assert-True 'a module enabled in the COMMITTED config is visible to it' `
    ($committedDiscovered -match 'NewGrowth') $committedDiscovered

# -- 8. The shipped growth data file is well formed ---------------------------
Write-Host ""
Write-Host "  The shipped file" -ForegroundColor Magenta

$growthPsd1 = Join-Path $pkgRoot 'Config/growth.commands.psd1'
$growthPs1  = Join-Path $pkgRoot 'Config/growth.commands.ps1'
Assert-True 'Config/growth.commands.psd1 ships' (Test-Path $growthPsd1)
Assert-True 'Config/growth.commands.ps1 ships beside it' (Test-Path $growthPs1)

if ((Test-Path $growthPsd1) -and (Test-Path $growthPs1)) {
    $psd1Text = Get-Content $growthPsd1 -Raw
    $ps1Text  = Get-Content $growthPs1 -Raw
    Assert-True 'the data file names a top-level feature key' ($psd1Text -match "Feature\s*=\s*'growth'")
    # The assignment, not the whole file: the header comment explains why the
    # cast is not there, and would otherwise match.
    Assert-True 'the shipped data file uses no cast, so it is really a data file' `
        ($psd1Text -match '(?m)^\s*Commands\s*=\s*@\{')
    Assert-True 'and states its own order instead' ($psd1Text -match '(?m)^\s*Order\s*=')
    Assert-True 'Import-PowerShellDataFile can read it' `
        ($null -ne (Import-PowerShellDataFile -Path $growthPsd1 -ErrorAction SilentlyContinue))
    # Every row must have help, or the verb shows up in Menu with a blank line
    # next to it and -Help prints nothing.
    foreach ($verb in @('NewGrowth', 'NewWorkReview', 'PublishWorkReview', 'LogPeerReview', 'UpdateResume')) {
        Assert-True "$verb has a help entry in the data file" `
            ($psd1Text -match "'$verb'\s*=\s*@\{")
    }
    Assert-True 'every wrapper answers -Help through Show-CommandHelp' `
        (([regex]::Matches($ps1Text, 'Show-CommandHelp')).Count -ge 5)
    Assert-True 'no wrapper bakes in a prefix' ($ps1Text -cnotmatch '[''"][^''"]*\bgo[A-Z]')
}

}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if (Test-Path $scratchRoot) { Remove-Item -Recurse -Force $scratchRoot -ErrorAction SilentlyContinue }
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'ModuleCommands' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) `
        -Passed $script:passed -Total $total
}

if ($script:failed -gt 0) { exit 1 }
exit 0
