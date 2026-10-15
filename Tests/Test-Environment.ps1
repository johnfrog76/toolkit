<#
.SYNOPSIS
    Env's optional-surface inventory, run THROUGH THE WRAPPER the way a user runs it.
.DESCRIPTION
    `{cliPrefix}Env` is `Get-P20Environment`, and that wrapper invokes
    `Scripts/Get-Environment.ps1` from INSIDE the module. The script then calls
    back into the module's global accessors -- `Get-P20NavAliases`,
    `Get-P20Features`, `Get-CliPrefix` -- and that is a different scope chain
    from the one every other suite exercised: function -> the running script's
    scope -> module scope. A `$script:` read inside a global function binds to
    the NEAREST script scope, which in that shape is the .ps1's and not the
    module's, so the nav table came back null and the org-scoped feature list
    came back empty. Env printed `not configured` for three configured
    shortcuts and `off` for an org whose hub.json says sprintAwareness is true,
    while `Menu -All` on the same data in the same session was right.

    The suites were green through all of it because they exercised the script or
    the function, never the wrapper. So this one runs the wrapper.

    Three clauses, narrowing:

      1. The user's call shape. `{prefix}Env` in a clean child shell, against a
         scratch package and a scratch hub: the Navigation shortcuts row reads
         `on -- 1 configured` and Sprint awareness reads `on`.
      2. The two call shapes agree. The whole "Optional surfaces" block printed
         by the in-module shape and by a direct run of the script are byte-equal
         -- by construction, not by two paths that happen to agree today
         (the issue's item 3: one resolver, one call shape).
      3. The accessors themselves, with the shadow case forced. A probe script
         deliberately assigns $NavAliases, $activeSpace, $SpaceScopedFeatures,
         $defaultConfig and $localConfig of its own, then asks the accessors.
         Direct and in-module answers must match. This is the cheap guard: it
         fails the moment an accessor goes back to reading module state through
         a name an intervening script can shadow.

    NOTHING here reads the real hub or the engineer's config.local.json. Every
    run builds its own package and its own hub under the temp directory, points
    PROMPTS_ROOT and P20_USAGE_LOG_DIR at them, and clears the Teams webhook
    variables so the inventory's last row is the same on every machine.

    `az` is never really called: the child shell defines an `az` of its own that
    returns nothing and a non-zero exit code before the module is imported, so
    the environment probe takes its "not logged in" path without a network call
    or a real credential being read.

    Run:  pwsh -File Tests/Test-Environment.ps1
#>
[CmdletBinding()]
param([switch]$Help)

if ($Help) {
    Write-Host ""
    Write-Host "  Test-Environment -- Env's optional surfaces, through the wrapper" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Wrapper      {prefix}Env reports configured surfaces as on"
    Write-Host "  Agreement    the in-module and direct call shapes print one identical block"
    Write-Host "  Accessors    the shadow case: a script's own variables cannot change the answer"
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

# -- The sandbox ---------------------------------------------------------------
# A scratch COPY of the package plus a scratch HUB beside it. The hub is what
# makes this test possible at all: sprintAwareness is the one ORG-scoped flag,
# so it can only be turned on by an org, and an org with a private flag belongs
# in hub.json rather than in the committed config.
$sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-env-" + [guid]::NewGuid().ToString('N').Substring(0, 12))
$pkgDir = Join-Path $sandboxRoot 'package'
$hubDir = Join-Path $sandboxRoot 'hub'
$logDir = Join-Path $sandboxRoot 'logs'

function New-EnvSandbox {
    New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
    New-Item -ItemType Directory -Path $hubDir -Force | Out-Null
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) {
        Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force
    }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $pkgDir -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')  $pkgDir -Recurse -Force

    # The hub declares one org, and that org declares the one org-scoped flag.
    # status 'local' keeps the tier decision away from ADO on top of the stub az.
    $hubJson = @'
{
  "hub": 1,
  "orgs": [
    {
      "slug": "envtest",
      "name": "Env Test",
      "status": "local",
      "promptsFolder": "envtest",
      "features": { "sprintAwareness": true }
    },
    { "slug": "envgh", "name": "Env GitHub", "status": "local", "promptsFolder": "envgh", "org": "https://github.com/acme/widgets", "howIWork": "agents" },
    { "slug": "envfresh", "name": "Env Fresh", "status": "local", "promptsFolder": "envfresh", "org": "https://github.com/acme/fresh" },
    { "slug": "envado", "name": "Env Azure", "status": "local", "promptsFolder": "envado", "org": "https://dev.azure.com/acme", "howIWork": "agents" }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson,
        (New-Object System.Text.UTF8Encoding($false)))
    New-Item -ItemType Directory -Path (Join-Path $hubDir 'envtest') -Force | Out-Null

    # The machine's half: the hub, the active Space, and ONE nav shortcut with a
    # path. The shipped aliases carry empty paths, so one configured path is
    # what turns the Navigation row from 'not configured' into 'on -- 1 configured'.
    $local = [ordered]@{
        quietStart  = $true
        promptsRoot = $hubDir
        activeOrg   = 'envtest'
        aliases     = [ordered]@{
            Home = [ordered]@{ path = $hubDir; display = $true; description = 'The scratch hub' }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'),
        ($local | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

# -- What the child shell does before it imports anything ----------------------
# Five things, and each one is a way this suite could otherwise read or write
# something that belongs to the engineer:
#
#   PSModulePath    limited to the scratch package, so a toolkit installed on
#                   the machine cannot answer for {prefix}Env (Test-ExitCodes
#                   makes the same point at length).
#   PROMPTS_ROOT    the scratch hub. The runner exports the real repo root for
#                   child suites and that override WINS over configured
#                   promptsRoot, so leaving it alone would point this run at a
#                   hub with no hub.json and the sprint row would read off for
#                   the wrong reason.
#   P20_USAGE_LOG   the scratch logs folder, so a run appends nothing to the
#                   engineer's usage log.
#   az              a stub that produces no output and a non-zero exit code.
#                   Get-Environment.ps1 probes `az account show`; a suite must
#                   not run a real one, and a machine that happens to be logged
#                   in must not print different rows from one that is not.
#   TEAMS_WEBHOOK_* cleared, so the Teams row is the same on every machine.
function New-ChildPreamble {
    $pkg = $pkgDir -replace "'", "''"
    $hub = $hubDir -replace "'", "''"
    $log = $logDir -replace "'", "''"
    return @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } |
    ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:az { `$global:LASTEXITCODE = 1 }
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking
"@
}

function Invoke-InChild {
    <# Run a snippet in a clean child shell against the sandbox; return all of it. #>
    param([Parameter(Mandatory)][string]$Snippet)
    $runner = Join-Path $sandboxRoot ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, ((New-ChildPreamble) + "`n" + $Snippet + "`n"),
        (New-Object System.Text.UTF8Encoding($false)))
    $out = & pwsh -NoProfile -File $runner 2>&1
    return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}

function Get-Marked {
    <# The text between two markers a child printed, trimmed line by line. #>
    param([string]$Text, [string]$Name)
    $lines = $Text -split "`r?`n"
    $collecting = $false
    $out = @()
    foreach ($line in $lines) {
        if ($line -match "^$Name-END$") { $collecting = $false; continue }
        if ($collecting) { $out += $line.TrimEnd() }
        if ($line -match "^$Name-BEGIN$") { $collecting = $true }
    }
    return ($out -join "`n")
}

Write-Host ""
Write-Host "  Env -- the optional-surface inventory through the wrapper" -ForegroundColor Cyan
Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {

New-EnvSandbox

# -- 1. The user's call shape --------------------------------------------------
Write-Host "  Through the wrapper" -ForegroundColor Magenta

$envOut = Invoke-InChild 'tkEnv'

Assert-True 'the report reaches the Optional surfaces block' `
    ($envOut -match 'Optional surfaces') $envOut

# Which build this is, in the first block: consts.json's version, read through
# the contract and never typed in the script.
$contractVersion = [string]((Get-Content (Join-Path $pkgRoot 'consts.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)
Assert-True "the first block names the version, consts.json's ($contractVersion)" `
    ($contractVersion -and ($envOut -match ('(?m)^\s*Version:\s+' + [regex]::Escape($contractVersion) + '\s*$'))) $envOut

# The row, whole: title, state and the count. `not configured` here is the bug
# this suite exists for, and `on` with no count would mean the nav table arrived
# but the paths did not.
Assert-True 'a configured nav shortcut reads on through the wrapper' `
    ($envOut -match 'Navigation shortcuts\s+on -- 1 configured') $envOut
Assert-True 'and the row does not claim the category is unconfigured' `
    ($envOut -notmatch 'Navigation shortcuts\s+not configured') $envOut

# sprintAwareness is org-scoped, so this row also proves Get-P20Features
# reached the ACTIVE ORG through the wrapper, not just the two config files.
Assert-True "an org's sprintAwareness reads on through the wrapper" `
    ($envOut -match "Sprint awareness\s+on -- this org's board") $envOut
Assert-True 'and the row is not reported off' `
    ($envOut -notmatch 'Sprint awareness\s+off') $envOut

# The prefix resolves through the wrapper too -- same hazard, same fix.
Assert-True 'the config line names the active Space, not a placeholder' `
    ($envOut -match 'spaces\.envtest\.features\.sprintAwareness=true') $envOut
Assert-True 'and no repair hint teaches the old orgs.<slug> key path' `
    ($envOut -notmatch 'Config -Set orgs\.') $envOut

# A row that is genuinely off must still read off: the fix must not have made
# everything look configured.
Assert-True 'a surface that really is off still reads off' `
    ($envOut -match 'Growth module\s+off') $envOut

# The tier line says WHY, and a local org is not a failure: it is never probed,
# so nothing about it is "unavailable" or "not logged in" in red.
#
Assert-True 'the tier line names the org and says it works from its cards' `
    ($envOut -match "Tier:\s+Working from your cards \(Tier 2\) -- 'envtest' works from its cards") $envOut
Assert-True 'a local org is never reported as unreachable or logged out' `
    ($envOut -notmatch 'ADO Add-on\s+unreachable' -and $envOut -notmatch '\[X\]\s+az login') $envOut
# The az rows print only where az is installed.
if (Get-Command az -ErrorAction SilentlyContinue) {
    Assert-True 'a local org reads the ADO Add-on as not configured, and expected' `
        ($envOut -match 'ADO Add-on\s+not configured \(expected\)') $envOut
}

# -- 1b. The hub row: configured, and not configured -------------------
# "The hub resolved" is not "a hub was configured": with no promptsRoot anywhere
# the module falls back to the folder above the package, which exists on every
# machine, and the row used to tick green on it while the Optional surfaces block
# below it said "not configured". Same test as Start's, so the two cannot differ.
Assert-True 'a configured hub is an [ok] row carrying its path' `
    ($envOut -match '\[ok\]  Hub {2,}\S') $envOut
Assert-True 'and it is not called unconfigured' `
    ($envOut -notmatch '\[--\]  Hub {2,}') $envOut

$localFile = Join-Path $pkgDir 'config.local.json'
$localKept = [System.IO.File]::ReadAllText($localFile)
$unset = Get-Content -LiteralPath $localFile -Raw | ConvertFrom-Json
$unset.PSObject.Properties.Remove('promptsRoot')
[System.IO.File]::WriteAllText($localFile, ($unset | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
try {
    $runner = Join-Path $sandboxRoot 'run-unset-hub.ps1'
    $pkgQ = $pkgDir -replace "'", "''"
    $logQ = $logDir -replace "'", "''"
    $unsetScript = @"
`$env:PSModulePath = '$pkgQ'
Remove-Item Env:\PROMPTS_ROOT -ErrorAction SilentlyContinue
`$env:P20_USAGE_LOG_DIR = '$logQ'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } |
    ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:az { `$global:LASTEXITCODE = 1 }
Import-Module '$pkgQ/utilities.psm1' -Force -DisableNameChecking
tkEnv
"@
    [System.IO.File]::WriteAllText($runner, $unsetScript, (New-Object System.Text.UTF8Encoding($false)))
    $unsetOut = (& pwsh -NoProfile -File $runner 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
}
finally {
    [System.IO.File]::WriteAllText($localFile, $localKept, (New-Object System.Text.UTF8Encoding($false)))
}
Assert-True 'with no hub configured the Hub row reads not configured, and says to run Start' `
    ($unsetOut -match '\[--\]  Hub {2,}not configured -- run tkStart') $unsetOut
Assert-True 'it is a note, not a green tick or a red cross' `
    ($unsetOut -notmatch '\[ok\]  Hub {2,}' -and $unsetOut -notmatch '\[X\]  Hub {2,}') $unsetOut
Assert-True 'and the Optional surfaces block on the same screen says the same thing' `
    ($unsetOut -match 'Your hub\s+not configured') $unsetOut
# -- 2. The two call shapes agree ---------------------------------------------
Write-Host ""
Write-Host "  One resolver, one call shape" -ForegroundColor Magenta

$compare = Invoke-InChild @'
function Get-SurfaceBlock([string]$text) {
    $lines = $text -split "`r?`n"
    $out = @()
    $started = $false
    foreach ($line in $lines) {
        if ($line -match 'Optional surfaces') { $started = $true }
        if (-not $started) { continue }
        if ($line -match 'commands unavailable') { break }
        $out += $line.TrimEnd()
    }
    return ($out -join "`n")
}
$envScript = Join-Path $PSScriptRoot 'package/Scripts/Get-Environment.ps1'
$direct = (& $envScript *>&1 | Out-String)
$m = Get-Module utilities
$inModule = (& $m ([scriptblock]::Create("& '$envScript' *>&1 | Out-String")))
"BLOCK-DIRECT-BEGIN"
Get-SurfaceBlock $direct
"BLOCK-DIRECT-END"
"BLOCK-MODULE-BEGIN"
Get-SurfaceBlock ($inModule | Out-String)
"BLOCK-MODULE-END"
'@

$directBlock = Get-Marked $compare 'BLOCK-DIRECT'
$moduleBlock = Get-Marked $compare 'BLOCK-MODULE'

Assert-True 'the direct call produces an Optional surfaces block' `
    ($directBlock -match 'Navigation shortcuts') $compare
Assert-True 'so does the in-module call' `
    ($moduleBlock -match 'Navigation shortcuts') $compare
Assert-True 'and the two blocks are identical' ($directBlock -eq $moduleBlock) `
    "direct:`n$directBlock`n---`nin-module:`n$moduleBlock"

# -- 3. The accessors, with the shadow forced ---------------------------------
# The cheap guard. Every name the accessors used to read through the scope chain
# is deliberately taken by the probe script, which is exactly what a module
# -launched script is free to do.
Write-Host ""
Write-Host "  The accessors, with the shadow case forced" -ForegroundColor Magenta

$probeBody = @'
$NavAliases = 'shadow'
$activeSpace = 'shadow'
$SpaceScopedFeatures = 'shadow'
$defaultConfig = 'shadow'
$localConfig = 'shadow'
$CommandPrefix = 'shadow'
$script:NavAliases = 'shadow'
$script:SpaceScopedFeatures = 'shadow'
$script:CommandPrefix = 'shadow'
$nav = Get-P20NavAliases
$features = Get-P20Features
$navType = 'null'
$navKeys = -1
$configured = -1
if ($null -ne $nav) {
    $navType = $nav.GetType().Name
    if ($nav -is [System.Collections.IDictionary]) {
        $navKeys = @($nav.Keys).Count
        $configured = @($nav.Keys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$nav[$_].path) }).Count
    }
}
$sprint = 'absent'
if ($features -and $features.ContainsKey('sprintAwareness')) { $sprint = [string]$features['sprintAwareness'] }
"NAVTYPE=$navType NAVKEYS=$navKeys CONFIGURED=$configured SPRINT=$sprint PREFIX=$(Get-CliPrefix)"
'@
[System.IO.File]::WriteAllText((Join-Path $sandboxRoot 'probe.ps1'), $probeBody,
    (New-Object System.Text.UTF8Encoding($false)))

$probeOut = Invoke-InChild @'
$probe = Join-Path $PSScriptRoot 'probe.ps1'
"PROBE-DIRECT-BEGIN"
& $probe
"PROBE-DIRECT-END"
"PROBE-MODULE-BEGIN"
& (Get-Module utilities) ([scriptblock]::Create("& '$probe'"))
"PROBE-MODULE-END"
'@

$probeDirect = (Get-Marked $probeOut 'PROBE-DIRECT').Trim()
$probeModule = (Get-Marked $probeOut 'PROBE-MODULE').Trim()

Assert-True 'the probe answered in the direct shape' ($probeDirect -match 'NAVKEYS=') $probeOut
Assert-True 'the probe answered in the in-module shape' ($probeModule -match 'NAVKEYS=') $probeOut
Assert-True 'a script cannot shadow the nav table away' `
    ($probeDirect -eq $probeModule) "direct: $probeDirect`nin-module: $probeModule"
Assert-True 'the nav table is the real table, not whatever the script named' `
    ($probeModule -match 'NAVTYPE=Hashtable' -and $probeModule -notmatch 'NAVKEYS=-1') $probeModule
Assert-True 'one shortcut is configured in both shapes' `
    ($probeModule -match 'CONFIGURED=1') $probeModule
Assert-True "the org's flag is merged in both shapes" `
    ($probeModule -match 'SPRINT=True') $probeModule
Assert-True 'the prefix resolves in both shapes' `
    ($probeModule -match 'PREFIX=tk') $probeModule

# -- 4. The five swept functions, with the shadow forced -----------------
# The audit moved every `$script:` read out of the global functions and into
# $script:ModuleState. This is the assertion the issue asked for: each of the
# five runs in BOTH call shapes -- direct, and through the module the way a
# launched script reaches it -- with a probe that shadows every name they used
# to read, and answers the same. The deprecation hint proves the SHARED state:
# printed once in the direct shape, silent for the same alias in the module
# shape (it remembered), printed for a fresh alias there.
Write-Host ""
Write-Host "  The swept functions, with the shadow case forced" -ForegroundColor Magenta

$sweepProbe = @'
$script:Config = 'shadow'; $script:Commands = 'shadow'; $script:AdoCommands = 'shadow'
$script:CommandMap = 'shadow'; $script:DeprecatedAliases = 'shadow'; $script:ShownDeprecationHints = 'shadow'
$script:SkipNavAliases = 'shadow'; $script:ModuleCommandsLoaded = 'shadow'; $script:ModuleState = 'shadow'
$Config = 'shadow'; $Commands = 'shadow'; $CommandMap = 'shadow'; $ModuleState = 'shadow'
$map = Get-P20CommandMap | ConvertFrom-Json
$mods = Get-P20ModuleCommands
$menu = (Get-P20Menu -Markdown *>&1 | Out-String)
Register-PromptAlias -Prefix 'zq' -Commands @('Status') -Force *>$null
$alias = if (Get-Command zqStatus -ErrorAction SilentlyContinue) { 'registered' } else { 'missing' }
$hintA = (Write-P20DeprecationHint 'tkSwitchOrg' *>&1 | Out-String).Trim()
$hintB = (Write-P20DeprecationHint 'tkNewAdoItem' *>&1 | Out-String).Trim()
"MAPKEYS=$(@($map.PSObject.Properties.Name).Count) TIMEOUTS=$([bool]$map._timeouts) MODS=$($mods.Length -gt 1) MENULINES=$(@($menu -split "`n" | Where-Object { $_ -match '\S' }).Count) ALIAS=$alias HINTA=$([bool]($hintA -match 'deprecated')) HINTB=$([bool]($hintB -match 'deprecated'))"
'@
[System.IO.File]::WriteAllText((Join-Path $sandboxRoot 'sweep-probe.ps1'), $sweepProbe,
    (New-Object System.Text.UTF8Encoding($false)))

$sweepOut = Invoke-InChild @'
$probe = Join-Path $PSScriptRoot 'sweep-probe.ps1'
"SWEEP-DIRECT-BEGIN"
& $probe
"SWEEP-DIRECT-END"
"SWEEP-MODULE-BEGIN"
& (Get-Module utilities) ([scriptblock]::Create("& '$probe'"))
"SWEEP-MODULE-END"
'@
$sweepDirect = (Get-Marked $sweepOut 'SWEEP-DIRECT').Trim()
$sweepModule = (Get-Marked $sweepOut 'SWEEP-MODULE').Trim()

Assert-True 'the swept probe answered in the direct shape, with a command map, module commands, a menu and an alias' `
    ($sweepDirect -match 'MAPKEYS=[1-9]\d* TIMEOUTS=True MODS=True MENULINES=[1-9]\d* ALIAS=registered') $sweepOut
Assert-True 'the direct shape printed the deprecation hint the first time, for both aliases' `
    ($sweepDirect -match 'HINTA=True HINTB=True') $sweepDirect
Assert-True 'the module shape answered the same for the map, the module commands, the menu and the alias' `
    (($sweepModule -replace ' HINT.*$', '') -eq ($sweepDirect -replace ' HINT.*$', '')) "direct: $sweepDirect`nin-module: $sweepModule"
Assert-True 'and it REMEMBERED: the hints already shown were not shown again -- the shared state is reachable from a launched script' `
    ($sweepModule -match 'HINTA=False HINTB=False') $sweepModule


Write-Host ""
# -- 5. The list and the inventory agree, both ways (settings by workflow, D-W1) --
# Every inventory key has a question; every entry names a key the inventory has;
# the JSON the agent reads carries both, with the same keys.
Write-Host ""
Write-Host "  The questions and the inventory, both ways" -ForegroundColor Magenta

$parityOut = Invoke-InChild @'
$json = Get-P20SurfaceInventory | ConvertFrom-Json
$keys = @($json.surfaces | ForEach-Object { $_.key })
$noQuestion = @($json.surfaces | Where-Object { -not $_.question } | ForEach-Object { $_.key })
$stale = @()
foreach ($e in $json.entries) { foreach ($k in @($e.surfaces)) { if ($keys -notcontains $k) { $stale += "$($e.id):$k" } } }
$doors = @($json.entries | Where-Object { $_.door -notin @('change','walk','sentence') } | ForEach-Object { $_.id })
$noAnchor = @($json.entries | Where-Object { $_.door -eq 'change' -and -not $_.anchor } | ForEach-Object { $_.id })
"KEYS=$($keys.Count) ENTRIES=$(@($json.entries).Count) NOQUESTION=$($noQuestion -join ',') STALE=$($stale -join ',') BADDOOR=$($doors -join ',') NOANCHOR=$($noAnchor -join ',') FIRST=$($keys[0]) ACTIVE=$($json.activeSpace)"
'@
$parityLine = ($parityOut -split "`n" | Where-Object { $_ -match '^KEYS=' } | Select-Object -Last 1)
Assert-True 'the inventory JSON answers with keys and entries' ($parityLine -match 'KEYS=1[0-9] ENTRIES=1[0-9]') $parityOut
Assert-True 'every inventory key has a question (a surface with no entry is the drift this guards)' ($parityLine -match 'NOQUESTION= ') $parityLine
Assert-True 'every entry names a key the inventory has (an entry with no surface is stale)' ($parityLine -match 'STALE= ') $parityLine
Assert-True 'every door is one of change / walk / sentence' ($parityLine -match 'BADDOOR= ') $parityLine
Assert-True 'every change door has an anchor (a walk may be a journey with no key, like Teams delivery)' ($parityLine -match 'NOANCHOR= ') $parityLine
Assert-True 'the hub is the first row (D-W7)' ($parityLine -match 'FIRST=promptsRoot') $parityLine
Assert-True 'Env prints the question before the row (D-W10)' ($envOut -match 'Where do my cards live[^\n]*\n\s*Your hub') $envOut

# -- 6. How do you want to work in this Space? --------------------------------
# The rule over the table the agent's suite reads too, then the gate through the
# module: Team Agile's switch on everywhere, and the row and the resolved flag
# follow the Space you are in -- the Space's answer, not the person's.
Write-Host ""
Write-Host "  How do you want to work in this Space?" -ForegroundColor Magenta

. (Join-Path $pkgRoot 'Scripts/Resolve-HowIWork.ps1')
$howTable = Get-Content -LiteralPath (Join-Path $testDir 'fixtures/how-i-work/table.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$howWrong = @()
foreach ($row in @($howTable.rows)) {
    $got = Resolve-P20HowIWork -OrgUrl ([string]$row.org) -Stored ([string]$row.stored)
    if ($got.answer -ne $row.answer -or $got.source -ne $row.source -or $got.tracker -ne $row.tracker -or [bool]$got.locked -ne [bool]$row.locked) {
        $howWrong += "$($row.org)|$($row.stored) -> $($got.answer)/$($got.source)/$($got.tracker)/$($got.locked)"
    }
}
Assert-True "every row of the shared table ($(@($howTable.rows).Count))" ($howWrong.Count -eq 0 -and @($howTable.rows).Count -ge 10) ($howWrong -join '; ')
$gateWrong = @()
foreach ($row in @($howTable.gate)) {
    $f = @{}
    if ($null -ne $row.switch) { $f['solitaireAgile'] = [bool]$row.switch }
    $out = Invoke-P20HowIWorkGate -Features $f -Answer ([string]$row.answer)
    $on = $null
    if ($out.ContainsKey('solitaireAgile')) { $on = $out['solitaireAgile'] }
    if ("$on" -ne "$($row.on)") { $gateWrong += "switch=$($row.switch) answer=$($row.answer) -> $on" }
}
Assert-True 'every gate row of the shared table' ($gateWrong.Count -eq 0) ($gateWrong -join '; ')

$howCases = @(
    @{ Space = 'envgh';    On = 'True';  Row = 'Team Agile module\s+on \(chosen: with agents in envgh\)'; Line = 'spaces\.envgh\.howIWork=alone -Hub' },
    @{ Space = 'envfresh'; On = 'False'; Row = 'Team Agile module\s+not configured \(nobody has answered for envfresh'; Line = 'spaces\.envfresh\.howIWork=agents -Hub' },
    @{ Space = 'envado';   On = 'False'; Row = 'Team Agile module\s+off \(derived: on a team in Azure'; Line = 'Connect envado -Address' },
    @{ Space = 'envtest';  On = 'False'; Row = 'Team Agile module\s+off \(derived: alone'; Line = 'Connect envtest -Address' }
)
foreach ($case in $howCases) {
    $howOut = Invoke-InChild @"
`$env:P20_ACTIVE_SPACE = '$($case.Space)'
`$env:P20_FEATURES = '{ "solitaireAgile": true, "growth": true }'
Import-Module "`$env:PSModulePath/utilities.psm1" -Force -DisableNameChecking
`$f = Get-P20Features
"FLAG=`$(`$f['solitaireAgile']) GROWTH=`$(`$f['growth']) VERB=`$([bool](Get-Command tkStandup -ErrorAction SilentlyContinue))"
tkMenu -All
"@
    Assert-True "$($case.Space): the resolved switch reads $($case.On), and no other flag moves" ($howOut -match "FLAG=$($case.On) GROWTH=True") $howOut
    Assert-True "$($case.Space): Standup is a verb only where Team Agile is on here" ($howOut -match "VERB=$($case.On)") $howOut
    Assert-True "$($case.Space): the inventory row says on, off or not configured and why" ($howOut -match $case.Row) $howOut
    Assert-True "$($case.Space): and its line is the one that changes it" ($howOut -match $case.Line) $howOut
}
# Switching Space re-evaluates it in a shell too: SwitchSpace re-imports the
# module, so Team Agile's verbs come with a Space that works with agents and go
# with one that does not. The sandbox's own config is switched and switched back.
$switchOut = Invoke-InChild @"
`$env:P20_FEATURES = '{ "solitaireAgile": true }'
Import-Module "`$env:PSModulePath/utilities.psm1" -Force -DisableNameChecking
"BEFORE=`$([bool](Get-Command tkStandup -ErrorAction SilentlyContinue))"
tkSwitchSpace envgh | Out-Null
"GH=`$([bool](Get-Command tkStandup -ErrorAction SilentlyContinue))"
tkSwitchSpace envtest | Out-Null
"AFTER=`$([bool](Get-Command tkStandup -ErrorAction SilentlyContinue))"
"@
Assert-True 'SwitchSpace re-evaluates: no Standup in envtest, Standup in envgh, none again back in envtest' `
    ($switchOut -match 'BEFORE=False' -and $switchOut -match 'GH=True' -and $switchOut -match 'AFTER=False') $switchOut

$questionOut = Invoke-InChild @'
$env:P20_ACTIVE_SPACE = 'envgh'
Import-Module "$env:PSModulePath/utilities.psm1" -Force -DisableNameChecking
tkMenu -All
'@
Assert-True 'the question names the Space you are in ({space})' ($questionOut -match 'How do you want to work in Env GitHub\?') $questionOut

$total = $script:passed + $script:failed

}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if (Test-Path $sandboxRoot) { Remove-Item -Recurse -Force $sandboxRoot -ErrorAction SilentlyContinue }
}
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'Environment' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) `
        -Passed $script:passed -Total $total
}

if ($script:failed -gt 0) { exit 1 }
exit 0
