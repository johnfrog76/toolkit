<#
.SYNOPSIS
    Tests for the Menu system — config coverage, alias wiring, scoring, and output.
.DESCRIPTION
    Validates that:
      - Every command in config.default.json has a registered alias
      - Menu -All output includes every command from config
      - Menu -Help prints without error
      - Get-P20CommandScores returns scores for synthetic log entries
      - No alias points to a missing function

    Run:  pwsh -File toolkit/Tests/Test-Menu.ps1
    Or:   {cliPrefix}TestToolkit -Menu
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location:
# works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent
$repoRoot = $pkgRoot

$toolkitRoot = $pkgRoot

# ── Test harness ──────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Contains {
    param(
        [string]$TestName,
        [string]$Haystack,
        [string]$Needle
    )
    if ($Haystack -like "*$Needle*") {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName — '$Needle' not found in output"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Equal {
    param(
        [string]$TestName,
        $Expected,
        $Actual
    )
    if ($Expected -eq $Actual) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName — expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Menu System Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Load config ──────────────────────────────────────────────────────────────

$configPath = Join-Path $toolkitRoot 'config.default.json'
Assert-True "config.default.json exists" (Test-Path $configPath)

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$commandNames = @($config.commands.PSObject.Properties.Name)

# The prefix, and the one rule for a bare nav alias key -- the module's own, so
# this suite cannot disagree with it about what a key means.
. (Join-Path (Join-Path $toolkitRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$mergePrefix = Resolve-P20ConfigPrefix -PackageRoot $toolkitRoot

# Merge local config to get resolved paths (nav aliases with empty paths are skipped).
# Keys are normalised to the BARE form exactly as utilities.psm1 does, so a local
# config that still spells one with the prefix resolves to the same entry rather
# than to a second one.
$localConfigPath = Join-Path $toolkitRoot 'config.local.json'
$mergedAliases = @{}
foreach ($prop in $config.aliases.PSObject.Properties) {
    $key = ConvertTo-P20BareAliasKey -Key $prop.Name -Prefix $mergePrefix
    $mergedAliases[$key] = @{
        path    = $prop.Value.path
        display = $prop.Value.display
    }
}
if (Test-Path $localConfigPath) {
    $localConfig = Get-Content $localConfigPath -Raw | ConvertFrom-Json
    if ($localConfig.aliases) {
        foreach ($prop in $localConfig.aliases.PSObject.Properties) {
            $key = ConvertTo-P20BareAliasKey -Key $prop.Name -Prefix $mergePrefix
            if (-not $mergedAliases.ContainsKey($key)) {
                $mergedAliases[$key] = @{ path = ''; display = $false }
            }
            if ($null -ne $prop.Value.path) { $mergedAliases[$key].path = $prop.Value.path }
            if ($null -ne $prop.Value.display) { $mergedAliases[$key].display = $prop.Value.display }
        }
    }
}
# BARE keys ('Home'); the alias a bare key registers is $mergePrefix + the key.
$aliasNames = @($mergedAliases.GetEnumerator() |
    Where-Object { $_.Value.display -eq $true -and -not [string]::IsNullOrWhiteSpace($_.Value.path) } |
    ForEach-Object { $_.Key })

Assert-True "Config has commands defined" ($commandNames.Count -gt 0)
if ($aliasNames.Count -gt 0) {
    Assert-True "Config has displayable aliases defined" $true
}
else {
    Write-Host "  SKIP  Config has displayable aliases defined — no displayable aliases in config.local.json; nav alias coverage not tested on this machine." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "  Config: $($commandNames.Count) commands, $($aliasNames.Count) nav aliases" -ForegroundColor DarkGray
Write-Host ""

# ── Import the module ────────────────────────────────────────────────────────

$modulePath = Join-Path $toolkitRoot 'utilities.psm1'
Assert-True "utilities.psm1 exists" (Test-Path $modulePath)

try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Assert-True "Module imports without error" $true
}
catch {
    Assert-True "Module imports without error ($($_.Exception.Message))" $false
    # Can't continue without the module
    Write-Host ""
    Write-Host "  Cannot continue — module failed to import." -ForegroundColor Red
    Write-Host ""
    if ($script:failed -gt 0) { exit 1 }
}

# ── Test 1: Every config command has a registered alias ──────────────────────

Write-Host "── Alias Registration ─────────────────────────────────" -ForegroundColor Cyan

# Aliases carry whatever prefix config declares, never a literal.
. (Join-Path (Join-Path $toolkitRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$cfgPrefix = Resolve-P20ConfigPrefix -PackageRoot $toolkitRoot
$registeredAliases = @(Get-Alias -Name "$cfgPrefix*" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

foreach ($cmd in $commandNames) {
    Assert-True "Alias exists: $cfgPrefix$cmd" ($registeredAliases -contains ($cfgPrefix + $cmd))
}

Write-Host ""

# ── Test 2: Every alias resolves to an existing function ─────────────────────

Write-Host "── Alias Targets ──────────────────────────────────────" -ForegroundColor Cyan

foreach ($cmd in $commandNames) {
    $alias = Get-Alias -Name ($cfgPrefix + $cmd) -ErrorAction SilentlyContinue
    if ($alias) {
        $target = $alias.ResolvedCommand
        Assert-True "Alias $cmd resolves to a function" ($null -ne $target)
    }
    # (missing alias already caught in Test 1)
}

Write-Host ""

# ── Test 3: Menu -All output includes every command ────────────────────────

Write-Host "── Menu -All Coverage ───────────────────────────────" -ForegroundColor Cyan

$allOutput = (Get-P20Menu -All 6>&1 | Out-String)

# Every command row's first token, and the prefix they all share. The prefix
# comes from whichever token ends in "Menu" -- the Menu command is always listed
# -- so these assertions hold whether the menu was reached by alias or by
# function name.
$menuRowTokens = @([regex]::Matches($allOutput, '(?m)^[ 	]{2,}(\S+)') | ForEach-Object { $_.Groups[1].Value })
$menuRowPrefix = ''
$menuToken = $menuRowTokens | Where-Object { $_ -match 'Menu$' } | Select-Object -First 1
if ($menuToken) { $menuRowPrefix = $menuToken -replace 'Menu$', '' }

# legacy-category aliases never appear in the menu.
# The tracker verbs are gated on whether a tracker is SHOWN for the Space this
# session is in -- Azure DevOps (Scripts/Test-AdoEnabled.ps1, which asks the
# tracker as well as the status), or a connected GitHub Space, where the same
# verbs answer through gh. The shipped Space is local, so on the shipped config
# they are absent here BY DESIGN, and their rows are asserted below in a scratch
# shell whose Space is active.
$activeSpace = $global:P20Config.ActiveSpace
. (Join-Path (Join-Path $toolkitRoot 'Scripts') 'Test-AdoEnabled.ps1')
. (Join-Path (Join-Path $toolkitRoot 'Scripts') 'Resolve-Tracker.ps1')
$adoVerbsInMenu = @((Get-P20ModuleState).AdoCommands)
$adoFlagHere = $null
$featuresHere = Get-P20Features
if ($featuresHere -and $featuresHere.ContainsKey('ado')) { $adoFlagHere = $featuresHere['ado'] }
$trackerHere = Resolve-P20Tracker -OrgUrl ([string]$global:P20Config.Org)
$adoShownHere = Test-P20AdoEnabled -OrgStatus $global:P20Config.OrgStatus -Flag $adoFlagHere -Tracker $trackerHere
if ($trackerHere -eq 'github' -and $global:P20Config.OrgStatus -eq 'active') { $adoShownHere = $true }
foreach ($cmd in $commandNames) {
    $cat = $config.commands.$cmd.category
    if ($cat -eq 'legacy') {
        Write-Host "  SKIP  -All output includes $cmd — legacy alias, hidden from menu" -ForegroundColor DarkYellow
        continue
    }
    if ($cmd -in $adoVerbsInMenu -and -not $adoShownHere) {
        Assert-True "-All output has NO row for ${cmd}: Azure DevOps is not shown for '$activeSpace'" (-not ($menuRowTokens -contains ($menuRowPrefix + $cmd))) `
            "a row reads '$menuRowPrefix$cmd' while Azure DevOps is off"
        continue
    }
    # As a ROW, not as a substring. `Assert-Contains` matches anywhere, so
    # `Sync` was satisfied by `tkTestSync` and `Update` by `tkUpdateResume`
    # while neither command appeared in the menu at all -- the check that exists
    # to catch exactly that reported success.
    #A command name
    # that is a substring of another command's name is invisible to a substring
    # match, which is what Archive matching an id as a substring taught about
    # ids.
    #
    # The prefix is DERIVED from the output, not assumed: the renderer takes it
    # from the invocation name, so calling Get-P20Menu directly (as this suite
    # does) prints `Get-P20Sync`, while the alias prints `tkSync`. Hardcoding
    # either one fails on the other path.
    Assert-True "-All output includes $cmd as its own row" ($menuRowTokens -contains ($menuRowPrefix + $cmd)) `
        "no row in the menu reads '$menuRowPrefix$cmd'"
}

Write-Host ""

# ── Test 4: Menu -All output includes nav aliases ─────────────────────────

Write-Host "── Menu -All Nav Aliases ────────────────────────────" -ForegroundColor Cyan

foreach ($nav in $aliasNames) {
    Assert-Contains "-All output includes nav alias $nav" $allOutput $nav
}

Write-Host ""

# ── Test 4c: the prefix is applied ONCE, and nav keys are bare ──────────────
# A nav alias key is stored bare and the prefix is applied at registration and
# at render, exactly as a command's is. Storing 'tkHome' in config and rendering
# $prefix + key printed 'tktkHome' -- and under a second registered prefix it
# would have printed a name that is nobody's command.
#
#
# Every case runs in a SCRATCH package with its own config.local.json: the
# machine running the suite may have nav shortcuts of its own, or none, and
# neither may decide whether these assertions run.

Write-Host "── Nav aliases: one prefix, applied once ────────────" -ForegroundColor Cyan

function New-MenuScratch {
    <# A throwaway copy of the package, with the given config.local.json. #>
    param([string]$LocalConfigJson)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-menu-nav-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) {
        Copy-Item (Join-Path $toolkitRoot $file) $dir -Force
    }
    Copy-Item (Join-Path $toolkitRoot 'Scripts') $dir -Recurse -Force
    Copy-Item (Join-Path $toolkitRoot 'Config')  $dir -Recurse -Force
    if ($LocalConfigJson) {
        [System.IO.File]::WriteAllText((Join-Path $dir 'config.local.json'), $LocalConfigJson,
            (New-Object System.Text.UTF8Encoding($false)))
    }
    return $dir
}

function Invoke-MenuScratch {
    <# Import the scratch module in a clean shell and run one command. #>
    param([string]$Dir, [string]$Command)
    # 5.1 reads a native stderr line as a terminating error under 'Stop';
    # the child's stderr is text here. Local to this function.
    $ErrorActionPreference = 'Continue'
    $module = (Join-Path $Dir 'utilities.psm1') -replace "'", "''"
    # -EncodedCommand: 5.1 does not escape a double quote inside a native argument.
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("Import-Module '$module' -Force -DisableNameChecking; $Command"))
    return ((& pwsh -NoProfile -OutputFormat Text -EncodedCommand $encoded 2>&1 |
        ForEach-Object { $_.ToString() }) -join "`n")
}

# -- Bare keys, under the shipped prefix --------------------------------------
$navScratch = New-MenuScratch @'
{
  "quietStart": true,
  "aliases": {
    "Home": { "path": "/", "display": true, "description": "Home directory" },
    "Bowling": { "path": "/", "display": true, "description": "Bowling app" }
  }
}
'@
try {
    $navOut = Invoke-MenuScratch $navScratch 'tkMenu -All'
    Assert-Contains 'a bare key renders under the prefix' $navOut 'tkHome'
    Assert-Contains 'a bare key added locally renders too' $navOut 'tkBowling'
    Assert-True 'no row carries the prefix twice' ($navOut -notmatch 'tktk') $navOut
    Assert-True 'the alias really registered under the prefix' `
        ((Invoke-MenuScratch $navScratch '(Get-Alias tkHome).Name') -match 'tkHome')
    # Configured, the empty-state line is gone.
    Assert-True 'a configured category drops the not-configured line' `
        (-not ($navOut -match '(?ms)Navigation\s*\r?\n\s*not configured')) $navOut
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $navScratch -Recurse -Force -ErrorAction SilentlyContinue }

# -- The same data under a DIFFERENT prefix ------------------------------------
# The case that matters: change commandPrefix and every nav alias follows, with
# no edit to any key. "So if I change prefix everything just updates."
$navScratchZz = New-MenuScratch @'
{
  "quietStart": true,
  "commandPrefix": "zz",
  "aliases": {
    "Home": { "path": "/", "display": true, "description": "Home directory" }
  }
}
'@
try {
    $zzOut = Invoke-MenuScratch $navScratchZz 'zzMenu -All'
    Assert-Contains 'the nav alias follows a changed prefix' $zzOut 'zzHome'
    Assert-True 'and the old prefix is nowhere in the row' ($zzOut -notmatch 'zztk' -and $zzOut -notmatch 'tkHome') $zzOut
    Assert-True 'the alias registers under the new prefix' `
        ((Invoke-MenuScratch $navScratchZz '(Get-Alias zzHome).Name') -match 'zzHome')
    # A SECOND prefix registered over the top gets the shortcuts too.
    Assert-True 'a second registered prefix gets the nav aliases' `
        ((Invoke-MenuScratch $navScratchZz 'Register-PromptAlias -Prefix gt; (Get-Alias gtHome).Name') -match 'gtHome')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $navScratchZz -Recurse -Force -ErrorAction SilentlyContinue }

# -- A local config that still spells the key WITH the prefix ------------------
# Read as the bare name, rendered once, and said once. A machine-local file is
# not rewritten by the package, so someone's shortcuts keep working.
$navScratchLegacy = New-MenuScratch @'
{
  "quietStart": true,
  "aliases": {
    "tkHub": { "path": "/", "display": true, "description": "Prompt hub" }
  }
}
'@
try {
    $legacyOut = Invoke-MenuScratch $navScratchLegacy 'tkMenu -All'
    Assert-Contains 'a prefixed local key still renders' $legacyOut 'tkHub'
    Assert-True 'and it renders ONCE, not doubled' ($legacyOut -notmatch 'tktkHub') $legacyOut
    Assert-Contains 'the deprecation names the bare form' $legacyOut 'tkHub -> Hub'
    $legacyAlias = Invoke-MenuScratch $navScratchLegacy '(Get-Alias tkHub).Name'
    Assert-True 'the alias registered under one prefix' `
        (($legacyAlias -match '(?m)^tkHub$') -and ($legacyAlias -notmatch 'tktkHub')) $legacyAlias
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $navScratchLegacy -Recurse -Force -ErrorAction SilentlyContinue }

# -- Two prefixes, one implementation ------------------------------------
# The multiton's contract, automated: every alias a second prefix registers
# points at the SAME function the shipped prefix does; -Commands registers
# exactly the names it lists; a name that is nobody's command warns and the
# rest still register; an alias that already points elsewhere is skipped with
# a warning unless -Force; and registering a prefix twice is silent. There is
# no per-prefix data file and no registry of prefixes -- a prefix is a
# registration in the shell that made it, and this is the whole of it.
Write-Host "── Two prefixes, one implementation ──────────────────" -ForegroundColor Cyan
$multiScratch = New-MenuScratch @'
{
  "quietStart": true,
  "aliases": {
    "Home": { "path": "/", "display": true, "description": "Home directory" }
  }
}
'@
try {
    $cmd = @'
Register-PromptAlias -Prefix gt 3>&1 | ForEach-Object { "WARN " + $_ }
# The COMMAND aliases. A nav shortcut is a small function named per prefix
# (Navigate-tkHub, Navigate-gtHub) by design, so it is the same shortcut and
# a different definition; the contract here is about the verbs.
$tk = @(Get-Alias -Name 'tk*' | Where-Object { $_.Definition -notmatch '^Navigate-' })
"TK=" + $tk.Count
foreach ($a in $tk) {
    $g = Get-Alias -Name ('gt' + $a.Name.Substring(2)) -ErrorAction SilentlyContinue
    if (-not $g) { "MISSING " + $a.Name }
    elseif ($g.Definition -ne $a.Definition) { "DIFFERS " + $a.Name }
}
Register-PromptAlias -Prefix gt 3>&1 | ForEach-Object { "AGAIN " + $_ }
"GT=" + @(Get-Alias -Name 'gt*' | Where-Object { $_.Definition -notmatch '^Navigate-' }).Count
"NAV=" + @(Get-Alias -Name 'gtHome' -ErrorAction SilentlyContinue).Count
'@
    $out = Invoke-MenuScratch $multiScratch $cmd
    $tkCount = [int](($out -split "`n" | Where-Object { $_ -match '^TK=(\d+)' } | ForEach-Object { $Matches[1] }) | Select-Object -First 1)
    $gtCount = [int](($out -split "`n" | Where-Object { $_ -match '^GT=(\d+)' } | ForEach-Object { $Matches[1] }) | Select-Object -First 1)
    Assert-True 'the shipped prefix registered a surface to compare against' ($tkCount -gt 20) "tk aliases: $tkCount"
    Assert-True 'every tk alias has a gt twin' ($out -notmatch '(?m)^MISSING ') $out
    Assert-True 'every gt twin resolves to the same function as its tk alias' ($out -notmatch '(?m)^DIFFERS ') $out
    # Not an exact count: the shipped prefix also answers to deprecated names,
    # which are its alone. MISSING above is the direction that matters.
    Assert-True 'the second prefix registers at least every command alias the first has' ($gtCount -ge $tkCount - 10 -and $gtCount -gt 20) "tk=$tkCount gt=$gtCount"
    Assert-Contains 'and the nav shortcut too, under its own name' $out 'NAV=1'
    Assert-True 'registering a prefix is silent' ($out -notmatch '(?m)^WARN ') $out
    Assert-True 'registering the same prefix twice is silent (idempotent)' ($out -notmatch '(?m)^AGAIN ') $out

    $cmd = @'
Register-PromptAlias -Prefix ab -Commands Status,Archive,Nope 3>&1 | ForEach-Object { "WARN " + $_ }
"AB=" + ((@(Get-Alias -Name 'ab*') | ForEach-Object { $_.Name } | Sort-Object) -join ',')
Set-Alias -Name xyStatus -Value Get-Date -Scope Global
Register-PromptAlias -Prefix xy -Commands Status 3>&1 | ForEach-Object { "COLLIDE " + $_ }
"XY1=" + (Get-Alias xyStatus).Definition
Register-PromptAlias -Prefix xy -Commands Status -Force 3>&1 | ForEach-Object { "FORCED " + $_ }
"XY2=" + (Get-Alias xyStatus).Definition
"TKS=" + (Get-Alias tkStatus).Definition
'@
    $out = Invoke-MenuScratch $multiScratch $cmd
    Assert-Contains '-Commands registers exactly the names it lists, and no nav alias' $out 'AB=abArchive,abStatus'
    Assert-True 'a name that is nobody''s command warns by name and the rest still register' ($out -match "(?m)^WARN .*unknown command 'Nope'") $out
    Assert-True 'an alias that points elsewhere is skipped with a warning' ($out -match '(?m)^COLLIDE .*points elsewhere') $out
    Assert-Contains 'and still points where it did' $out 'XY1=Get-Date'
    Assert-True '-Force takes the name over' ($out -notmatch '(?m)^FORCED ') $out
    $xy2 = (($out -split "`n" | Where-Object { $_ -match '^XY2=' }) | Select-Object -First 1) -replace '^XY2=', ''
    $tks = (($out -split "`n" | Where-Object { $_ -match '^TKS=' }) | Select-Object -First 1) -replace '^TKS=', ''
    Assert-True 'and the forced alias is the same function tkStatus is' ($xy2 -and $xy2 -eq $tks) "xy=$xy2 tk=$tks"
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $multiScratch -Recurse -Force -ErrorAction SilentlyContinue }

# -- The tracker verbs, in a Space where Azure DevOps is shown --------------------
# The shipped Space ships local, so the coverage loop above cannot see the
# tracker verbs on the shipped config. Here the same Space is made active with an
# address by a local patch, which is what the old Example was, and every tracker
# verb has its own row in -All.
Write-Host "── Tracker verbs, in an active Space ─────────────────" -ForegroundColor Cyan
$adoScratch = New-MenuScratch @'
{
  "quietStart": true,
  "spaces": { "azure-demo": { "status": "active", "org": "https://dev.azure.com/YOUR-ADO-ORG" } }
}
'@
try {
    $adoAll = Invoke-MenuScratch $adoScratch 'tkMenu -All'
    $adoRows = @([regex]::Matches($adoAll, '(?m)^[ 	]{2,}(\S+)') | ForEach-Object { $_.Groups[1].Value })
    foreach ($cmd in $adoVerbsInMenu) {
        if (-not $commandNames.Contains($cmd)) { continue }   # a module verb, off in the shipped config
        Assert-True "-All in an active Space includes $cmd as its own row" ($adoRows -contains ('tk' + $cmd)) "no row reads 'tk$cmd'"
    }
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $adoScratch -Recurse -Force -ErrorAction SilentlyContinue }


Write-Host ""

# ── Test 4d: Navigation is named before it is configured ────────────────────
# The category's members come from aliases with a path, a path is personal, and
# the three shipped ones are empty -- so the category used to vanish and a
# shipped feature looked absent.
#

Write-Host "── Navigation before it is configured ───────────────" -ForegroundColor Cyan

$navEmpty = New-MenuScratch '{ "quietStart": true }'
try {
    $emptyOut = Invoke-MenuScratch $navEmpty 'tkMenu -All'
    Assert-Contains 'the category title shows with nothing configured' $emptyOut 'Navigation'
    Assert-True 'and carries the not-configured line' `
        ($emptyOut -match '(?ms)Navigation\s*\r?\n\s*not configured') $emptyOut
    Assert-Contains 'the line says which setting fills it' $emptyOut 'tkConfig -Set aliases.Home.path='
    # Naming it is not registering it: an alias with no path has nowhere to go.
    Assert-True 'no shipped alias is registered without a path' `
        ((Invoke-MenuScratch $navEmpty '[bool](Get-Alias tkHome -ErrorAction SilentlyContinue)') -match 'False')
    # ASCII only -- Windows-1252 misreads an en dash in a double-quoted string.
    $emptyNavLine = @($emptyOut -split "`r?`n" | Where-Object { $_ -match 'not configured' })
    Assert-True 'the empty-state lines are ASCII' `
        (@($emptyNavLine | Where-Object { $_ -match '[^\x00-\x7F]' }).Count -eq 0) ($emptyNavLine -join ' | ')
    # -Markdown emits the real table and never a placeholder row.
    $emptyMd = Invoke-MenuScratch $navEmpty 'tkMenu -Markdown'
    Assert-True '-Markdown emits no not-configured row' ($emptyMd -notmatch 'not configured') $emptyMd
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $navEmpty -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""

# ── Test 4e: every opt-in surface is named, with its state ──────────────────
# "Core workflow always shows; add-ons only by configuration; the nav category
# shows its title with `not configured` under it when empty" -- and a machine
# has to be able to say what it is NOT doing.
#
#
# The distinction this must not blur: the inventory NAMES an off module; the
# command surface still does not have it. Both are asserted below.

Write-Host "── Opt-in surfaces, named with their state ──────────" -ForegroundColor Cyan

. (Join-Path (Join-Path $toolkitRoot 'Scripts') 'Get-OptionalSurfaces.ps1')
$surfaceStates = Get-P20SurfaceStates
Assert-Equal 'the three states are on/off/not configured' 'on|off|not configured' `
    (@($surfaceStates.On, $surfaceStates.Off, $surfaceStates.Unset) -join '|')

$surfaceRows = @(Get-P20OptionalSurfaces -Prefix $cfgPrefix -PackageRoot $toolkitRoot)
$surfaceKeys = @($surfaceRows | ForEach-Object { $_.key })
foreach ($expected in @('aliases', 'features.growth', 'features.communication', 'features.deck', 'tracker.github',
        'sprintAwareness', 'storeSync', 'email', 'web', 'design', 'ANTHROPIC_API_KEY', 'TEAMS_WEBHOOK_*')) {
    Assert-True "the inventory names $expected" ($surfaceKeys -contains $expected) ($surfaceKeys -join ', ')
}
foreach ($row in $surfaceRows) {
    Assert-True "$($row.key) has one of the three states" `
        (@($surfaceStates.On, $surfaceStates.Off, $surfaceStates.Unset) -contains $row.state) $row.state
    Assert-True "$($row.key) names the config that changes it" (-not [string]::IsNullOrWhiteSpace($row.config))
    Assert-True "$($row.key) has a title" (-not [string]::IsNullOrWhiteSpace($row.title))
}
# Every module that ships a Config/<module>.commands.psd1 is in the inventory,
# enumerated from the files rather than listed here.
foreach ($psd1 in (Get-ChildItem (Join-Path $toolkitRoot 'Config') -Filter '*.commands.psd1' -File)) {
    $moduleData = Import-PowerShellDataFile -Path $psd1.FullName
    Assert-True "the inventory names the $($moduleData.Feature) module" `
        ($surfaceKeys -contains "features.$($moduleData.Feature)") ($surfaceKeys -join ', ')
}

# -- Both flags OFF: named in the inventory, absent from the command surface ---
$surfaceOff = New-MenuScratch '{ "quietStart": true }'
try {
    $offOut = Invoke-MenuScratch $surfaceOff 'tkMenu -All'
    Assert-Contains '-All ends with the opt-in inventory' $offOut 'Opt in by configuration'
    Assert-Contains 'an off module is NAMED' $offOut 'Growth module'
    Assert-True 'and its state reads off' ($offOut -match '(?m)Growth module\s+off') $offOut
    Assert-Contains 'with the line that switches it on' $offOut 'tkConfig -Set features.growth=true'
    Assert-Contains 'the communication module is named too' $offOut 'Communication module'
    # "Off means absent" is NOT weakened: no module VERB renders.
    foreach ($verb in @('NewGrowth', 'PublishWorkReview', 'SendTeams', 'MeetingAgenda')) {
        Assert-True "flags off: no $verb row in the menu" ($offOut -notmatch $verb) $verb
    }
    Assert-Contains 'the nav surface is named' $offOut 'Navigation shortcuts'
    Assert-Contains 'the environment gates are named' $offOut 'ANTHROPIC_API_KEY'
    Assert-Contains 'and the webhook gate' $offOut 'TEAMS_WEBHOOK_'
    Assert-True 'no doubled prefix anywhere in -All' ($offOut -notmatch 'tktk') $offOut
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $surfaceOff -Recurse -Force -ErrorAction SilentlyContinue }

# -- Both flags ON: the state flips, and the verbs arrive ----------------------
$surfaceOn = New-MenuScratch '{ "quietStart": true, "features": { "growth": true, "communication": true } }'
try {
    $onSurfaces = Invoke-MenuScratch $surfaceOn 'tkMenu -All'
    Assert-True 'flags on: the growth module reads on' ($onSurfaces -match '(?m)Growth module\s+on') $onSurfaces
    Assert-True 'flags on: the communication module reads on' ($onSurfaces -match '(?m)Communication module\s+on') $onSurfaces
    Assert-Contains 'flags on: the verbs are there too' $onSurfaces 'NewGrowth'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-Item $surfaceOn -Recurse -Force -ErrorAction SilentlyContinue }

# -- Env prints the same inventory --------------------------------------------
# One list, two renderers: the menu is what you can use now, Env is what exists.
$envText = Get-Content (Join-Path $toolkitRoot 'Scripts/Get-Environment.ps1') -Raw
Assert-True 'Env renders the shared inventory' ($envText -match 'Get-P20OptionalSurfaces')
Assert-True 'Env heads the block' ($envText -match 'Optional surfaces')
$setupText = Get-Content (Join-Path $toolkitRoot 'Scripts/Test-Prerequisites.ps1') -Raw
Assert-True 'Setup points at that report' ($setupText -match 'Optional surfaces')
$utilitiesNav = Get-Content (Join-Path $toolkitRoot 'utilities.psm1') -Raw
Assert-True 'the menu reads the shared inventory rather than its own list' `
    ($utilitiesNav -match 'Get-P20OptionalSurfaces')

Write-Host ""

# ── Test 4b: no placeholder token survives any menu row ─────────────────────
# The list render used to substitute a dead {p} token instead of calling
# Expand-CliPrefix, so three descriptions printed a literal {cliPrefix} while
# -Help on the same commands was correct. One resolver, every render path -- and
# this is the assertion that keeps the NEXT token from doing the same.

Write-Host "── Menu -All expands every placeholder ──────────────" -ForegroundColor Cyan

$placeholder = '\{\w+\}'
$leaky = @($allOutput -split "`r?`n" | Where-Object { $_ -match $placeholder })
Assert-True "-All leaves no {token} in any row" ($leaky.Count -eq 0) ($leaky -join ' | ')

$markdownOutput = (Get-P20Menu -Markdown 6>&1 | Out-String)
$leakyMd = @($markdownOutput -split "`r?`n" | Where-Object { $_ -match $placeholder })
Assert-True "-Markdown leaves no {token} in any row" ($leakyMd.Count -eq 0) ($leakyMd -join ' | ')

# A module verb renders through the same path, and its help text comes from the
# module's own data file rather than config.default.json -- so "no token" has to
# hold with the flags on too, which the in-process run above cannot show.
$menuScratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-menu-token-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $menuScratch -Force | Out-Null
    Copy-Item (Join-Path $toolkitRoot 'utilities.psm1')      $menuScratch -Force
    Copy-Item (Join-Path $toolkitRoot 'config.default.json') $menuScratch -Force
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $toolkitRoot 'consts.json')         $menuScratch -Force
    Copy-Item (Join-Path $toolkitRoot 'Scripts')             $menuScratch -Recurse -Force
    Copy-Item (Join-Path $toolkitRoot 'Config')              $menuScratch -Recurse -Force
    # A byte-level write, as the scoring fixture's: Set-Content -Encoding UTF8 into a
    # folder a scanner may still hold throws "Stream was not readable" under 5.1.
    $menuLocalJson = @{ quietStart = $true; features = @{ growth = $true; communication = $true } } | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText((Join-Path $menuScratch 'config.local.json'), $menuLocalJson, (New-Object System.Text.UTF8Encoding $false))

    $scratchModule = (Join-Path $menuScratch 'utilities.psm1') -replace "'", "''"
    $onMenu = (& pwsh -NoProfile -Command "Import-Module '$scratchModule' -Force -DisableNameChecking; tkMenu -All" 2>&1 |
        ForEach-Object { $_.ToString() }) -join "`n"

    Assert-True "flags on: the module verbs really did render" ($onMenu -match 'NewGrowth' -and $onMenu -match 'SendTeams') $onMenu
    $leakyOn = @($onMenu -split "`r?`n" | Where-Object { $_ -match $placeholder })
    Assert-True "flags on: -All leaves no {token} in any row" ($leakyOn.Count -eq 0) ($leakyOn -join ' | ')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    Remove-Item -Path $menuScratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# ── Test 5: Menu -Help runs without error ──────────────────────────────────

Write-Host "── Menu -Help ───────────────────────────────────────" -ForegroundColor Cyan

try {
    $helpOutput = (Get-P20Menu -Help 6>&1 | Out-String)
    Assert-True "-Help runs without error" $true
    Assert-Contains "-Help mentions -All" $helpOutput "-All"
    Assert-Contains "-Help mentions -Help" $helpOutput "-Help"
    Assert-Contains "-Help mentions -Reset" $helpOutput "-Reset"
}
catch {
    Assert-True "-Help runs without error ($($_.Exception.Message))" $false
}

Write-Host ""

# ── Test 6: Get-P20CommandScores parses synthetic log entries ───────────────────

Write-Host "── Scoring Engine ─────────────────────────────────────" -ForegroundColor Cyan

# Where the scoring engine reads from: the package root, or what
# P20_USAGE_LOG_DIR names. This section states its own precondition: it points
# the variable at a scratch directory of its own, so every score and the menu's
# Most used list below come from the log written here and not from what this
# machine has typed (a real log whose top six verbs are not these
# ones made 'lists the verb under its prefix' red on a clean main). The
# variable's prior value is put back in the finally.
$savedScoreLogDir = $env:P20_USAGE_LOG_DIR
$scoreLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) "p20-menu-scores-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scoreLogRoot -Force | Out-Null
$env:P20_USAGE_LOG_DIR = $scoreLogRoot
$tempLog = Join-Path $scoreLogRoot "usage.TESTMENU.log"
$cleanupLog = $false
try {
    # Capture baseline scores (from any pre-existing usage logs)
    $baseScores = Get-P20CommandScores
    $baseDashboard = if ($baseScores.ContainsKey("${cfgPrefix}Dashboard")) { $baseScores["${cfgPrefix}Dashboard"] } else { 0 }
    $baseSync = if ($baseScores.ContainsKey("${cfgPrefix}Sync")) { $baseScores["${cfgPrefix}Sync"] }      else { 0 }
    $baseArchive = if ($baseScores.ContainsKey("${cfgPrefix}Archive")) { $baseScores["${cfgPrefix}Archive"] }   else { 0 }
    $baseMyPRs = if ($baseScores.ContainsKey("${cfgPrefix}MyPRs")) { $baseScores["${cfgPrefix}MyPRs"] }     else { 0 }

    $now = Get-Date
    # Write synthetic CMD entries for three commands at different ages
    $lines = @(
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`t${cfgPrefix}Dashboard`tok"
        "$($now.AddDays(-2).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`t${cfgPrefix}Dashboard`tok"
        "$($now.AddDays(-20).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`t${cfgPrefix}Sync`tok"
        "$($now.AddDays(-100).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`t${cfgPrefix}Archive`tok"
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tERR`tTESTMENU`t${cfgPrefix}MyPRs`ttest error"
    )
    # Byte-level writes, here and below: under Windows PowerShell 5.1,
    # Set-Content -Encoding UTF8 on a file something still holds for a moment
    # (a scanner, the read just before the rewrite) throws "Stream was not
    # readable". The log's own writer appends BOM-less UTF-8 the same way.
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tempLog, (($lines -join "`n") + "`n"), $utf8NoBom)
    $cleanupLog = $true

    $scores = Get-P20CommandScores

    $newDashboard = if ($scores.ContainsKey("${cfgPrefix}Dashboard")) { $scores["${cfgPrefix}Dashboard"] } else { 0 }
    $newSync = if ($scores.ContainsKey("${cfgPrefix}Sync")) { $scores["${cfgPrefix}Sync"] }      else { 0 }
    $newArchive = if ($scores.ContainsKey("${cfgPrefix}Archive")) { $scores["${cfgPrefix}Archive"] }   else { 0 }
    $newMyPRs = if ($scores.ContainsKey("${cfgPrefix}MyPRs")) { $scores["${cfgPrefix}MyPRs"] }     else { 0 }

    # Dashboard: 2 uses in last 14 days × 3 = +6 over baseline
    Assert-True "Dashboard gained +6 from 2 recent uses" (($newDashboard - $baseDashboard) -eq 6)

    # Sync: 1 use at 20 days × 2 = +2 over baseline
    Assert-True "Sync gained +2 from 1 use at 20 days" (($newSync - $baseSync) -eq 2)

    # Archive: 100 days old, weight = 0 — no score increase
    Assert-True "Archive unchanged (>90 days old entry ignored)" (($newArchive - $baseArchive) -eq 0)

    # ERR entries should not count toward score
    Assert-True "ERR entries do not boost score" (($newMyPRs - $baseMyPRs) -eq 0)

    # -- The names meet. The log writes the user-facing name (tkSync), another
    # prefix's (gtSync) and the agent's routes (agent/prs); the command table is
    # bare. Asked with the table, the scores come back bare, and a route is not
    # a verb.
    $names = @('Dashboard', 'Sync', 'Archive', 'MyPRs', 'Status')
    $baseBare = Get-P20CommandScores -CommandNames $names -Prefix $cfgPrefix
    $baseBareStatus = if ($baseBare.ContainsKey('Status')) { $baseBare['Status'] } else { 0 }
    $baseBareDash = if ($baseBare.ContainsKey('Dashboard')) { $baseBare['Dashboard'] } else { 0 }
    $more = @(
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`tgtStatus`tok"
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`tStatus`tok"
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`tagent/prs`t0 PRs"
        "$($now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss'))`tCMD`tTESTMENU`tagent/work-items`t3 items"
    )
    [System.IO.File]::WriteAllText($tempLog, ((($lines + $more) -join "`n") + "`n"), $utf8NoBom)
    $bare = Get-P20CommandScores -CommandNames $names -Prefix $cfgPrefix
    # The two Dashboard rows are prefixed: the bare key carries their score, and
    # at least everything the raw (un-normalised) read saw under the prefixed name.
    Assert-True "a prefixed log name scores under the bare key ($cfgPrefix)" ($bare['Dashboard'] -ge 6 -and $bare['Dashboard'] -ge $newDashboard)
    Assert-True "a bare name and another prefix's name score under the same bare key" ((($bare['Status']) - $baseBareStatus) -eq 6)
    Assert-True "rows for other verbs leave Dashboard's bare score where it was" (($bare['Dashboard']) -eq $baseBareDash)
    Assert-True "no prefixed key survives normalisation" (-not $bare.ContainsKey("${cfgPrefix}Dashboard"))
    Assert-True "an agent route is not a verb and is not scored" (-not ($bare.Keys | Where-Object { $_ -match '/' }))
    Assert-True "a name the table does not know is dropped" (-not $bare.ContainsKey('gtStatus'))

    # The menu itself: the section appears, and with the prefix on the names.
    # Through the ALIAS: the wrapper reads its prefix from the name it was invoked by.
    $menuText = (& (Get-Command "${cfgPrefix}Menu") 6>&1 | Out-String)
    Assert-True "the most-used section appears at all" ($menuText -match 'Most used commands')
    Assert-True "and lists the verb under its prefix" ($menuText -match "${cfgPrefix}Dashboard|${cfgPrefix}Status") $menuText
    Assert-True "and no longer claims there is no usage data" ($menuText -notmatch 'No usage data yet')
}
catch {
    Assert-True "Scoring test threw: $($_.Exception.Message)" $false
}
finally {
    if ($cleanupLog -and (Test-Path $tempLog)) {
        Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
    }
    $env:P20_USAGE_LOG_DIR = $savedScoreLogDir
    if (Test-Path $scoreLogRoot) { Remove-Item $scoreLogRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""

# ── Test 6b: the log a test run writes to is not the engineer's ──────────────
# Write-ToolkitLog and the two readers beside it (Get-P20CommandScores,
# Get-RecentErrors) resolve their directory through one helper, and
# P20_USAGE_LOG_DIR moves it. Unset it means the package root, exactly as
# before. This is the CLI half of the pair; Tests/test_log_override.py is the
# agent's.

Write-Host "── The usage log a test run writes to ─────────────────" -ForegroundColor Cyan

$machineName = [System.Environment]::MachineName
$realLog = Join-Path $toolkitRoot "usage.$machineName.log"
$realBefore = if (Test-Path $realLog) { (Get-FileHash $realLog -Algorithm SHA256).Hash } else { 'absent' }

$overrideDir = Join-Path ([System.IO.Path]::GetTempPath()) "p20-menu-log-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $overrideDir -Force | Out-Null
$savedLogDir = $env:P20_USAGE_LOG_DIR
try {
    $env:P20_USAGE_LOG_DIR = $overrideDir
    Write-ToolkitLog -Type ERR -Source 'TestMenu/log-override' -Detail 'this is an assertion, not an event'
    $scratchLog = Join-Path $overrideDir "usage.$machineName.log"
    Assert-True 'a write lands in the directory the override names' (Test-Path $scratchLog)
    if (Test-Path $scratchLog) {
        Assert-Contains 'the entry is the one that was written' (Get-Content $scratchLog -Raw) 'this is an assertion, not an event'
        $logHead = [System.IO.File]::ReadAllBytes($scratchLog) | Select-Object -First 3
        Assert-True 'a fresh usage log does not start with a byte-order mark' (-not ($logHead.Count -eq 3 -and $logHead[0] -eq 0xEF -and $logHead[1] -eq 0xBB -and $logHead[2] -eq 0xBF))
    }
    else {
        Assert-True 'the entry is the one that was written' $false
    }
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    if ($null -eq $savedLogDir) { Remove-Item Env:\P20_USAGE_LOG_DIR -ErrorAction SilentlyContinue }
    else { $env:P20_USAGE_LOG_DIR = $savedLogDir }
    Remove-Item -Path $overrideDir -Recurse -Force -ErrorAction SilentlyContinue
}

$realAfter = if (Test-Path $realLog) { (Get-FileHash $realLog -Algorithm SHA256).Hash } else { 'absent' }
Assert-True "the real usage.$machineName.log was not touched" ($realBefore -eq $realAfter) "$realBefore -> $realAfter"

# Unset is the default, and the default is where it always was.
$savedLogDir = $env:P20_USAGE_LOG_DIR
try {
    Remove-Item Env:\P20_USAGE_LOG_DIR -ErrorAction SilentlyContinue
    $utilitiesText = Get-Content (Join-Path $toolkitRoot 'utilities.psm1') -Raw
    Assert-True 'the writer resolves its directory through one helper' ($utilitiesText -match 'function global:Get-P20ToolkitLogDir')
    Assert-True 'unset falls back to the package root' ($utilitiesText -match 'return \$PSScriptRoot')
    Assert-True 'both readers use the same helper' ((([regex]::Matches($utilitiesText, 'Get-P20ToolkitLogDir')).Count) -ge 4)
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    if ($null -ne $savedLogDir) { $env:P20_USAGE_LOG_DIR = $savedLogDir }
}

# The same variable name on the agent's side -- one override, not two.
$logWriterText = Get-Content (Join-Path $toolkitRoot 'agent/core/log_writer.py') -Raw
Assert-True 'the agent reads the same variable name' ($logWriterText -match 'P20_USAGE_LOG_DIR')

# And Log -Clear exists, because a log that can only grow is not a diagnostic.
$logScript = Get-Content (Join-Path $toolkitRoot 'Scripts/Get-ToolkitLog.ps1') -Raw
Assert-True 'Log declares -Clear' ((Get-Command (Join-Path $toolkitRoot 'Scripts/Get-ToolkitLog.ps1')).Parameters.Keys -contains 'Clear')
Assert-True 'Log -Clear archives rather than deletes' ($logScript -match '\.bak')
Assert-True 'Log reads the override too' ($logScript -match 'P20_USAGE_LOG_DIR')
Assert-True 'config advertises -Clear' ($config.commands.Log.usage -match '-Clear')

Write-Host ""

# ── Test 7: Config categories are valid ──────────────────────────────────────

Write-Host "── Config Validation ──────────────────────────────────" -ForegroundColor Cyan

$validCategories = @('nav', 'pr', 'work', 'prompt', 'sync', 'sprint', 'review', 'growth', 'organize', 'studio', 'rituals', 'org', 'setup', 'info', 'test', 'legacy')
foreach ($cmd in $commandNames) {
    $cat = $config.commands.$cmd.category
    Assert-True "$cmd has valid category '$cat'" ($validCategories -contains $cat)
}

foreach ($cmd in $commandNames) {
    $desc = $config.commands.$cmd.description
    Assert-True "$cmd has a non-empty description" (-not [string]::IsNullOrWhiteSpace($desc))
}

# A description is one dense line: it starts at column 27 of the menu, so 53
# characters is what fits an 80-column window. Flags, keys, examples and reasons
# go in usage, switches, examples and notes, which -Help renders
# (docs/CONTRIBUTING.md).
$descriptionLimit = 53
$descriptionsToHold = @()
foreach ($cmd in $commandNames) {
    $descriptionsToHold += @{ Name = $cmd; Text = [string]$config.commands.$cmd.description }
    if ($config.commands.$cmd.descriptionWithoutAdo) {
        $descriptionsToHold += @{ Name = "$cmd (without ADO)"; Text = [string]$config.commands.$cmd.descriptionWithoutAdo }
    }
}
foreach ($psd1 in @(Get-ChildItem (Join-Path $repoRoot 'Config') -Filter '*.commands.psd1' -File)) {
    try { $moduleData = Import-PowerShellDataFile $psd1.FullName } catch { continue }
    if (-not $moduleData.Help) { continue }
    foreach ($verb in $moduleData.Help.Keys) {
        $descriptionsToHold += @{ Name = "$verb ($($psd1.Name))"; Text = [string]$moduleData.Help[$verb].description }
    }
}
foreach ($d in $descriptionsToHold) {
    $expanded = $d.Text -replace '\{cliPrefix\}', $cfgPrefix
    Assert-True "$($d.Name): description is at most $descriptionLimit characters ($($expanded.Length))" ($expanded.Length -le $descriptionLimit)
    Assert-True "$($d.Name): description carries no flag list, markdown or e.g." ($expanded -notmatch '\(-|\*\*|e\.g\.')
    Assert-True "$($d.Name): description has no trailing period" (-not $expanded.TrimEnd().EndsWith('.'))
}
Assert-True 'Update and Sync sit in one group, on the default menu' ($config.commands.Update.category -eq 'sync' -and $config.commands.Sync.category -eq 'sync')
# The config saying so is not the menu doing so. Both lines above passed while
# the renderers' $catOrder omitted 'sync' entirely, so the group existed in the
# data and in no output.
Assert-True 'and that group is actually RENDERED, with both commands under it' `
    (($allOutput -match "(?m)^\s+Sync\s*$") -and
     ($menuRowTokens -contains ($menuRowPrefix + 'Sync')) -and
     ($menuRowTokens -contains ($menuRowPrefix + 'Update'))) $allOutput

# Every command must carry usage + at least one example so -Help (via
# Show-CommandHelp) always has something to print.
foreach ($cmd in $commandNames) {
    $usage = $config.commands.$cmd.usage
    Assert-True "$cmd has non-empty usage" (-not [string]::IsNullOrWhiteSpace($usage))
    $examples = $config.commands.$cmd.examples
    Assert-True "$cmd has at least one example" ($examples -and @($examples).Count -gt 0)
}

Write-Host ""

# ── Test 7b: Error-path contract ─────────────────────────────────

Write-Host "── Error-Path Contract ────────────────────────────────" -ForegroundColor Cyan

$moduleText = Get-Content (Join-Path $toolkitRoot 'utilities.psm1') -Raw

# No bare Write-Error in the module — errors surface via Write-CliError.
Assert-True "No bare Write-Error in utilities.psm1" (-not ($moduleText -match '(?m)^\s*Write-Error\b'))

# "Every ERR log is paired with a Write-CliError" used to be checked by counting
# two substrings across fifteen copies of the same catch block. There is one copy
# now -- Scripts/Invoke-CommandScript.ps1's guard, which every wrapper calls --
# so the pairing is asserted where it lives, and the wrappers are asserted to go
# through it rather than to re-type it. See AGENTS.md, "The refusal contract".
$guardPath = Join-Path $toolkitRoot 'Scripts/Invoke-CommandScript.ps1'
Assert-True "The wrapper guard ships with the package" (Test-Path $guardPath)
$guardText = Get-Content $guardPath -Raw
Assert-True "The guard logs ERR on a failure" ($guardText -match 'Write-ToolkitLog -Type ERR')
Assert-True "The guard states that failure through Write-CliError" ($guardText -match 'Write-CliError -Message')
Assert-True "The guard declares the stated-refusal exit code" ($guardText -match '\$script:StatedRefusalExitCode = 2')
Assert-True "The guard prints nothing extra for a stated refusal" ($guardText -match 'StatedRefusalExitCode')

$oldShape = @($moduleText -split "`n" | Where-Object { $_ -like '*Write-ToolkitLog -Type ERR -Source $inv.Name*' })
Assert-True "No registered wrapper re-types the guard's catch" ($oldShape.Count -eq 0)
$guarded = @($moduleText -split "`n" | Where-Object { $_ -like '*Invoke-ToolkitScript -Path*' })
Assert-True "The registered wrappers run their scripts through the guard" ($guarded.Count -ge 10)

Write-Host ""

# ── Test 7c: Deprecation / legacy aliases ────────────────────────────

Write-Host "── Legacy / Deprecation ───────────────────────────────" -ForegroundColor Cyan

# Phase 4 sunset: the legacy aliases were removed (cliVersion 2). Assert the
# clean end state — no legacy-category commands, removed aliases no longer
# resolve, canonical names do, and the deprecation map is empty.
#
# The removed names are written under an obviously fake prefix. They are a
# NEGATIVE fixture -- "this is not our namespace" -- and spelling them with the
# predecessor's real prefix put that product's namespace back in this package
# for no test value.
$legacyCmds = @($commandNames | Where-Object { $config.commands.$_.category -eq 'legacy' })
Assert-True "No legacy-category commands remain" ($legacyCmds.Count -eq 0)

$removedAliases = @('zzCreatePR', 'zzCreatePrompt', 'zzCreateAdoItem', 'zzScaffoldDemo',
    'zzGenerateReview', 'zzUpdateReview', 'zzReviewPR', 'zzLogPRReview',
    'zzNew1on1', 'zzSwitchMode', 'zzResolveBug', 'zz1on1')
foreach ($old in $removedAliases) {
    Assert-True "Removed legacy alias $old no longer resolves" ($null -eq (Get-Alias -Name $old -ErrorAction SilentlyContinue))
}

# The canonical names from the cliVersion 2 rename. Scoped to those still
# declared, since a package that dropped a command should not assert its alias
# resolves -- and prefixed, because the namespace is config-driven now.
$canonicalNames = @('NewPR', 'NewPrompt', 'NewItem', 'NewDemo', 'NewWorkReview',
    'PublishWorkReview', 'AddPRReview', 'LogPeerReview', 'NewMeeting',
    'SwitchSpace', 'CloseItem', 'EditItem', 'MeetingAgenda')
foreach ($new in $canonicalNames) {
    if ($commandNames -notcontains $new) { continue }
    Assert-True "Canonical alias $cfgPrefix$new resolves" ($registeredAliases -contains ($cfgPrefix + $new))
}

# The Item family opened a new deprecation window: the map is no
# longer empty, so the assertion moves from "empty" to "well-formed" -- every
# deprecated name maps to a command config declares, is itself dual-mapped in
# the command table, and is NOT in config (the menu shows canonical rows only).
$depMatch = [regex]::Match($moduleText, '\$script:ModuleState\.DeprecatedAliases\s*=\s*@\{(.*?)\n\}', 'Singleline')
Assert-True "DeprecatedAliases block found" $depMatch.Success
$depPairs = @{}
foreach ($m in [regex]::Matches($depMatch.Groups[1].Value, "'(\w+)'\s*=\s*'(\w+)'")) {
    $depPairs[$m.Groups[1].Value] = $m.Groups[2].Value
}
foreach ($oldName in $depPairs.Keys) {
    $canon = $depPairs[$oldName]
    Assert-True "deprecated $oldName -> $canon : canonical is in config" ($commandNames -contains $canon)
    Assert-True "deprecated $oldName -> $canon : old name is NOT in config (menu shows canonical only)" ($commandNames -notcontains $oldName)
    Assert-True "deprecated $oldName -> $canon : old alias still answers" ($registeredAliases -contains ($cfgPrefix + $oldName))
}
Assert-True "cliVersion bumped to 2" ($config.cliVersion -eq 2)

Write-Host ""

# ── Test 7d: Markdown emitter ───────────────────────────────────────────

Write-Host "── Markdown Emitter ───────────────────────────────────" -ForegroundColor Cyan

$md = (Get-P20Menu -Markdown | Out-String)
foreach ($cmd in $commandNames) {
    $cat = $config.commands.$cmd.category
    if ($cat -in @('legacy', 'nav')) {
        Assert-True "-Markdown excludes $cat command $cmd" (-not ($md -match "\b$([regex]::Escape($cmd))\b"))
        continue
    }
    if ($cmd -in $adoVerbsInMenu -and -not $adoShownHere) { continue }
    Assert-Contains "-Markdown includes $cmd" $md $cmd
}

Write-Host ""

# ── Test 7e: Parameter-name standard ─────────────────────────────

Write-Host "── Parameter-Name Standard ────────────────────────────" -ForegroundColor Cyan

# Scan the module + all command scripts for off-standard parameter *declarations*
# of the four standardized concepts. Aliases (e.g. [Alias('OutputJson')]) are
# allowed for back-compat — only the declared parameter name must be canonical.
$paramFiles = @((Join-Path $toolkitRoot 'utilities.psm1')) +
    @(Get-ChildItem (Join-Path $toolkitRoot 'Scripts') -Filter '*.ps1' | ForEach-Object { $_.FullName })

# off-standard declared name -> canonical name
$offStandard = @{
    'OutputJson'   = '-AsJson'
    'Json'         = '-AsJson'
    'Organization' = '-Org'
    'OrgSlug'      = '-Org'
    'OrgName'      = '-Org'
    'Silent'       = '-Quiet'
}
foreach ($file in $paramFiles) {
    $text = Get-Content $file -Raw
    $name = Split-Path $file -Leaf
    foreach ($bad in $offStandard.Keys) {
        # match a parameter declaration like "]$OutputJson" or "[switch]$OutputJson"
        $declared = $text -match "\]\s*\`$$bad\b"
        Assert-True "$name declares no off-standard `$$bad (use $($offStandard[$bad]))" (-not $declared)
    }
}

Write-Host ""

# ── Test 8: Every command supports -Help ─────────────────────────────────────

Write-Host "── Command -Help Support ──────────────────────────────" -ForegroundColor Cyan

foreach ($cmd in $commandNames) {
    $alias = Get-Alias -Name ($cfgPrefix + $cmd) -ErrorAction SilentlyContinue
    if (-not $alias) { continue }  # missing alias already caught above

    $target = $alias.ResolvedCommand
    if (-not $target) { continue }

    $hasHelp = $target.Parameters -and $target.Parameters.ContainsKey('Help')
    Assert-True "$cmd supports -Help" $hasHelp
}

Write-Host ""

# ── Test 9: No orphan aliases (registered but missing from config) ───────────

Write-Host "── Orphan Alias Check ─────────────────────────────────" -ForegroundColor Cyan

# Every test-runner command now carries a config entry, so nothing is exempt.
# The list stays as the seam for a future internal-only command.
$internalAliases = @()

# Must be the CONFIGURED prefix. Globbing a literal namespace here matched
# nothing after the carve, so this test passed vacuously while proving nothing.
$allRegisteredAliases = $registeredAliases

# An opt-in module contributes its verbs at import time from its own
# Config/<module>.commands.psd1, not from config.default.json (build-plan D-CM),
# so on a machine that has one switched on those aliases are registered and are
# legitimately absent from the config this test reads. Ask the module which
# names those are rather than listing them here: a list here would go stale the
# first time a module changed, which is the failure mode this whole check
# exists to catch.
$moduleCommandNames = @()
if (Get-Command Get-P20ModuleCommands -ErrorAction SilentlyContinue) {
    try {
        $loadedModules = Get-P20ModuleCommands | ConvertFrom-Json
        foreach ($prop in $loadedModules.PSObject.Properties) { $moduleCommandNames += @($prop.Value) }
    }
    catch { $null = $_ }
}

$allConfigNames = @($commandNames) + @($aliasNames) + @($moduleCommandNames)

$orphans = @()
foreach ($alias in $allRegisteredAliases) {
    if ($alias -in $internalAliases) { continue }
    # A deprecated name in its window is dual-mapped ON PURPOSE and absent
    # from config on purpose -- the block above asserts both halves of that.
    $bareDep = $alias
    if ($bareDep.StartsWith($cfgPrefix)) { $bareDep = $bareDep.Substring($cfgPrefix.Length) }
    if ($depPairs.ContainsKey($bareDep)) { continue }
    # Config command keys are prefix-LESS ('Archive'); registered aliases carry the
    # prefix ('tkArchive'). Compare on the bare name, or nothing ever matches.
    $bare = $alias
    if ($bare.StartsWith($cfgPrefix)) { $bare = $bare.Substring($cfgPrefix.Length) }
    if ($bare -notin $allConfigNames -and $alias -notin $allConfigNames) {
        $orphans += $alias
    }
}

Assert-True "No orphan aliases (registered but not in config)" ($orphans.Count -eq 0)
if ($orphans.Count -gt 0) {
    foreach ($o in $orphans) {
        Write-Host "        orphan: $o (alias exists, missing from config.default.json)" -ForegroundColor DarkYellow
    }
}

Write-Host ""

# ── Test 9c: a document that says `python3` names the Windows spelling too ───
# `python3` on Windows is the Microsoft Store alias, not an interpreter. The
# fix was made once, line by line, and came back with the docs split;
#docs/CONTRIBUTING.md,
# "Naming the Python interpreter", is the rule this holds.

Write-Host "── The Python spelling ────────────────────────────────" -ForegroundColor Cyan

$pythonDocs = @(Get-ChildItem (Join-Path $repoRoot 'docs') -Filter '*.md' -Recurse -File | ForEach-Object { $_.FullName })
foreach ($rel in @('README.md', 'AGENTS.md', 'VERIFY.md', 'agent/README.md', 'web/README.md')) {
    $candidate = Join-Path $repoRoot $rel
    if (Test-Path $candidate) { $pythonDocs += $candidate }
}
$pythonDocsChecked = 0
foreach ($docPath in $pythonDocs) {
    $docText = Get-Content $docPath -Raw
    if ($docText -notmatch 'python3') { continue }
    $pythonDocsChecked++
    $docLeaf = $docPath.Substring($repoRoot.Length).TrimStart('\', '/')
    $namesWindows = ($docText -match '(?i)windows[^\n]{0,120}\bpy(thon| -3)\b') -or ($docText -match '(?i)\bpy(thon| -3)\b[^\n]{0,120}windows')
    Assert-True "$docLeaf says python3 and names the Windows spelling beside it" $namesWindows
}
Assert-True "the Python-spelling check read at least one document" ($pythonDocsChecked -gt 0)

Write-Host ""

# ── Test 10: README command table parity ─────────────────────────────────────

Write-Host "── README Parity ──────────────────────────────────────" -ForegroundColor Cyan

$readmePath = Join-Path $repoRoot 'README.md'
if (-not (Test-Path $readmePath)) {
    Write-Host "  SKIP  README parity — README.md not found" -ForegroundColor DarkYellow
}
else {
    # Include all alias keys from config (not just displayable ones) so nav aliases
    # that are defined but have no local path don't flag as stale on this machine.
    # Bare keys AND the prefixed names they register under: README documents
    # `tkHome`, which is what a configured `Home` becomes.
    $allConfigAliasKeys = @($config.aliases.PSObject.Properties.Name) +
        @($config.aliases.PSObject.Properties.Name | ForEach-Object { $cfgPrefix + $_ })

    # Module verbs are known names whether or not their flag is on.
    #
    # A module contributes its rows through Config/<module>.commands.psd1, and the
    # loader only reads that file when the module's top-level feature flag is true
    # -- which the committed config never is, and which is therefore the state
    # every test run is in. So before this, `{cliPrefix}NewGrowth` in README prose
    # turned this suite red while the unprefixed `NewGrowth` passed, and the
    # failure detail ("no alias or config entry") pointed the reader at
    # registering the command, which is the wrong fix. The rule lived only in the
    # test and was discovered by breaking the build.
    #
    # Import-PowerShellDataFile and nothing else -- the same reader the loader
    # uses, for the same reason: a data file in Config/ must not be able to run
    # code, least of all inside a test run.
    #
    # The check keeps its teeth. A name in no psd1, no alias and no config entry
    # is still stale.
    $moduleCommandNames = @()
    $configDir = Join-Path $pkgRoot 'Config'
    if (Test-Path $configDir) {
        foreach ($psd1 in (Get-ChildItem $configDir -Filter '*.commands.psd1' -File -ErrorAction SilentlyContinue)) {
            try {
                $data = Import-PowerShellDataFile -Path $psd1.FullName -ErrorAction Stop
            }
            catch {
                # A malformed module file is ModuleCommands' problem, not this
                # test's -- it is skipped by path there and skipped here too.
                Write-Host "  INFO  README parity: could not read $($psd1.Name) -- module verbs from it are not known names" -ForegroundColor DarkGray
                continue
            }
            if ($data -and $data.Commands) {
                foreach ($k in @($data.Commands.Keys)) { $moduleCommandNames += "$cfgPrefix$k" }
            }
        }
    }

    $allKnownNames = @($commandNames) + @($aliasNames) + @($allRegisteredAliases) +
        @($allConfigAliasKeys) + @($moduleCommandNames)

    # Stale-check the documentation. No document may reference a prefixed command
    # that isn't defined. Tokens inside Markdown blockquotes (`>`) are exempt -- the
    # docs keep a cliVersion deprecation note that intentionally names removed verbs
    # so readers aren't sent to dead names; those are asides, not live references.
    #
    # The README was once one 2,100-line file and is now the front door
    # over docs/*.md, so the check reads every document a command can be written
    # in rather than the one that used to hold them all. docs/CLI.md is the
    # authoritative command catalogue -- it carries the command reference.
    # docs/KNOWN-GAPS.md holds the gap rows that left the README, verbs
    # and all, so it is read too rather than dropping out of the check.
    $catalogName = 'docs/CLI.md'
    $cliDocs = @(
        @{ Name = 'README.md'; Path = $readmePath }
    )
    foreach ($docRel in @('docs/QUICKSTART.md', 'docs/CONFIGURATION.md', 'docs/CLI.md', 'docs/TESTING.md',
            'docs/ARCHITECTURE.md', 'docs/CONTRIBUTING.md', 'docs/modules/README.md',
            'docs/KNOWN-GAPS.md')) {
        $cliDocs += @{ Name = $docRel; Path = (Join-Path $repoRoot $docRel) }
    }
    # agentic/ ships prompts a stranger's assistant follows to the letter, so a
    # dead verb there is an error on someone else's machine. Every file,
    # read the same way: a module verb passes through its data file.
    $agenticDir = Join-Path $repoRoot 'agentic'
    if (Test-Path $agenticDir) {
        foreach ($agenticDoc in @(Get-ChildItem $agenticDir -Filter '*.md' -Recurse -File | Sort-Object FullName)) {
            $agenticRel = 'agentic/' + $agenticDoc.FullName.Substring($agenticDir.Length).TrimStart('\', '/').Replace('\', '/')
            $cliDocs += @{ Name = $agenticRel; Path = $agenticDoc.FullName }
        }
    }

    # docs/CLI.md is the catalogue that should list every command; remember its
    # full token set for the completeness advisory below.
    $catalogTokensAll = @()

    foreach ($doc in $cliDocs) {
        if (-not (Test-Path $doc.Path)) {
            Write-Host "  SKIP  $($doc.Name) parity -- file not found" -ForegroundColor DarkYellow
            continue
        }
        $docContent = Get-Content $doc.Path -Raw
        $docLines = $docContent -split "\r?\n"
        $liveContent = ($docLines | Where-Object { $_ -notmatch '^\s*>' }) -join "`n"
        # Capture the command even when args share the backticks, e.g.
        # `tkSwitchSpace <slug>` -- match the prefixed word, then anything up to
        # the closing tick.
        $tokenPattern = '`(' + [regex]::Escape($cfgPrefix) + '[A-Za-z0-9]+)[^`]*`'
        $liveTokens = @([regex]::Matches($liveContent, $tokenPattern) |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique)

        $stale = @($liveTokens | Where-Object { $_ -notin $allKnownNames })
        Assert-True "No stale commands in $($doc.Name) (documented but not defined)" ($stale.Count -eq 0)
        foreach ($s in $stale) {
            Write-Host "        stale: $s (in $($doc.Name) body but no alias, config entry or Config/*.commands.psd1 row)" -ForegroundColor DarkYellow
        }

        if ($doc.Name -eq $catalogName) {
            $catalogTokensAll = @([regex]::Matches($docContent, $tokenPattern) |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique)
        }
    }

    # Advisory (not a failure): config commands missing from the docs/CLI.md catalogue.
    if ($catalogTokensAll.Count -gt 0) {
        # $commandNames are BARE keys (Archive) and the tokens are PREFIXED
        # (tkArchive), so comparing them directly listed every command as
        # undocumented on every run. A command is documented when the catalogue
        # names it prefixed in prose or gives it a command-reference row.
        $catalogText = Get-Content (Join-Path $repoRoot $catalogName) -Raw
        $undocumented = @($commandNames | Where-Object {
            ("$cfgPrefix$_" -notin $catalogTokensAll) -and
            ($catalogText -notmatch ('(?m)^\|\s*`' + [regex]::Escape($_) + '[` ]'))
        })
        if ($undocumented.Count -gt 0) {
            Write-Host "  INFO  $($undocumented.Count) config command(s) not in $($catalogName):" -ForegroundColor DarkGray
            foreach ($u in ($undocumented | Sort-Object)) {
                Write-Host "        undocumented: $u" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "  INFO  All config commands appear in $catalogName" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""

# ── Test 10b: help that describes each switch, and README rows that agree ────
# The help table gained two optional keys, `switches` (name -> one line) and
# `notes`, because -Help rendered only the one-line description and so told a
# reader less than the predecessor's hand-written help did.
#Keeping them in
# config is what keeps -Help, Menu and this README check reading one source.

Write-Host "── Per-switch help ────────────────────────────────────" -ForegroundColor Cyan

# The command reference moved out of the README into docs/CLI.md;
# the rows this block reads went with it.
$cliDocPath = Join-Path $repoRoot 'docs/CLI.md'
$readmeText = if (Test-Path $cliDocPath) { Get-Content $cliDocPath -Raw } else { '' }

foreach ($verb in @('Web', 'Agent')) {
    $entry = $config.commands.$verb
    Assert-True "$verb has a switches block" ($null -ne $entry.switches)
    Assert-True "$verb has notes" ($null -ne $entry.notes -and @($entry.notes).Count -gt 0)

    $switchNames = @($entry.switches.PSObject.Properties.Name)
    # Every switch the script declares is described, and nothing is described
    # that the script does not declare. -Reuse is excluded on purpose: it is
    # composition for Start-Web.ps1, not a switch anyone types.
    $scriptFile = if ($verb -eq 'Web') { 'Scripts/Start-Web.ps1' } else { 'Scripts/Start-Agent.ps1' }
    $declared = @((Get-Command (Join-Path $repoRoot $scriptFile)).Parameters.Keys |
        Where-Object { $_ -notin @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction',
                'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'Reuse') })
    foreach ($d in $declared) {
        $described = @($switchNames | Where-Object { $_ -match "^-$d(\s|$)" })
        Assert-True "$verb -Help describes -$d" ($described.Count -eq 1) ($switchNames -join ', ')
    }
    foreach ($n in $switchNames) {
        if ($n -eq '(none)') { continue }
        $bare = ($n -replace '^-', '') -replace '\s.*$', ''
        Assert-True "$verb's $n is a switch the script declares" ($declared -contains $bare) ($declared -join ', ')
    }

    # The URLs are read, not typed: the notes carry tokens, and the renderer
    # resolves them from web.agentPort and vite.config.ts.
    $noteText = ($entry.notes -join ' ')
    Assert-True "$verb's notes name a URL" ($noteText -match 'http://localhost:\{(agentPort|devPort)\}') $noteText
    Assert-True "$verb's notes hardcode no port" ($noteText -notmatch 'localhost:\d') $noteText

    # docs/CLI.md's command-reference row for the verb names every switch the help does, so
    # the two catalogues cannot describe different commands.
    if ($readmeText) {
        $row = @($readmeText -split "`r?`n" | Where-Object { $_ -match "^\|\s*``$verb``\s*\|" })
        Assert-True "docs/CLI.md has a row for $verb" ($row.Count -eq 1) "$($row.Count) rows"
        if ($row.Count -eq 1) {
            foreach ($n in $switchNames) {
                # -Help is on every command in the package and is not part of
                # what a row is for; (none) is the bare form, not a switch.
                if ($n -eq '(none)' -or $n -eq '-Help') { continue }
                $bare = ($n -replace '\s.*$', '')
                Assert-True "docs/CLI.md's $verb row names $bare" ($row[0] -match [regex]::Escape($bare)) $row[0]
            }
        }
    }
}

# -- The test runner's own help ------------------------------------------------
# It was the one -Help in the package written by hand instead of read from
# config, and it named the LEGACY system's runner five times -- plus two
# switches matching no row in its suite table.
#Run under a fake
# prefix, the way the -ModuleCommands suite does, so a hardcoded `tk` fails here
# too.

Write-Host ""
Write-Host "-- The runner's -Help comes from config ---------------" -ForegroundColor Cyan

$runnerScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("runner-help-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $runnerScratch 'Tests') -Force | Out-Null
    Copy-Item (Join-Path $toolkitRoot 'utilities.psm1')      $runnerScratch -Force
    Copy-Item (Join-Path $toolkitRoot 'config.default.json') $runnerScratch -Force
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $toolkitRoot 'consts.json')         $runnerScratch -Force
    Copy-Item (Join-Path $toolkitRoot 'Scripts')             $runnerScratch -Recurse -Force
    Copy-Item (Join-Path $toolkitRoot 'Config')              $runnerScratch -Recurse -Force
    Copy-Item (Join-Path $toolkitRoot 'Tests/Test-Toolkit.ps1') (Join-Path $runnerScratch 'Tests') -Force
    # The suite table lives beside the runner now; a copy of
    # the runner without it dies before -Help prints a line.
    Copy-Item (Join-Path $toolkitRoot 'Tests/Get-ToolkitSuiteRegistry.ps1') (Join-Path $runnerScratch 'Tests') -Force
    $runnerLocalJson = @{ quietStart = $true; commandPrefix = 'zz' } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $runnerScratch 'config.local.json'), $runnerLocalJson, (New-Object System.Text.UTF8Encoding $false))

    $runnerHelp = (& pwsh -NoProfile -File (Join-Path $runnerScratch 'Tests/Test-Toolkit.ps1') -Help 2>&1 |
        ForEach-Object { $_.ToString() }) -join "`n"

    Assert-True "the runner's -Help names the prefix actually configured" `
        ($runnerHelp -match 'zzTestToolkit') $runnerHelp
    Assert-True "the runner's -Help hardcodes no prefix of its own" `
        ($runnerHelp -notmatch 'tkTestToolkit') $runnerHelp
    Assert-True "the runner's -Help names no legacy command" `
        ($runnerHelp -cnotmatch '\bgo[A-Z]') $runnerHelp
    Assert-True "the runner's -Help lists suites from the suite table" `
        (($runnerHelp -match '-Portability') -and ($runnerHelp -match '-MeetingAgenda')) $runnerHelp
    Assert-True "the runner's -Help offers no suite the table does not have" `
        (($runnerHelp -notmatch '-Billing') -and ($runnerHelp -notmatch '-Snapshot')) $runnerHelp

    # Every suite in the table is a switch the runner DECLARES. The selection loop reads each
    # suite's switch by name, so a suite registered with no switch runs in a full pass and is
    # listed by -List but cannot be selected alone: "-EditItem" is then a binding error, which
    # sets no exit code. HubJson fell in first, then Connect and EditItem.
    . (Join-Path $toolkitRoot 'Tests/Get-ToolkitSuiteRegistry.ps1')
    $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $toolkitRoot 'Tests/Test-Toolkit.ps1'), [ref]$null, [ref]$null)
    $runnerSwitches = @($runnerAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $undeclared = @((Get-P20ToolkitSuiteRegistry).Keys | Where-Object { $runnerSwitches -notcontains $_ })
    Assert-True "every suite in the table is a switch the runner declares" `
        ($undeclared.Count -eq 0) ("registered with no switch: " + ($undeclared -join ', '))
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally {
    Remove-Item $runnerScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# Phantom switches are gone from the param() block too, or -List and the
# selection loop would still advertise something that runs nothing.
$runnerText = Get-Content (Join-Path $toolkitRoot 'Tests/Test-Toolkit.ps1') -Raw
foreach ($phantomSwitch in @('Billing', 'Snapshot')) {
    Assert-True "the runner declares no -$phantomSwitch switch" `
        ($runnerText -notmatch "\[switch\]\`$$phantomSwitch\b") $phantomSwitch
}

Write-Host ""

# The renderer itself: one implementation for the module path and the
# standalone one, and no token left unexpanded.
$sharedHelp = Join-Path $repoRoot 'Scripts/Show-ConfigHelp.ps1'
Assert-True 'the shared config-help renderer ships' (Test-Path $sharedHelp)
foreach ($launcher in @('Scripts/Start-Web.ps1', 'Scripts/Start-Agent.ps1')) {
    $text = Get-Content (Join-Path $repoRoot $launcher) -Raw
    Assert-True "$launcher renders help through the shared one" ($text -match 'Show-P20ConfigHelp')
}
$utilitiesHelp = Get-Content (Join-Path $repoRoot 'utilities.psm1') -Raw
Assert-True 'the module renderer prints switches' ($utilitiesHelp -match '"  Switches:"')
Assert-True 'the module renderer prints notes' ($utilitiesHelp -match '"  Notes:"')
Assert-True 'the module resolves the port tokens' ($utilitiesHelp -match 'agentPort')

Write-Host ""

# ── Wrapper / script parameter parity ────────────────────────────────────────
#
# A verb is TWO param() blocks: the wrapper in utilities.psm1 that owns the
# alias, and the script in Scripts/ that does the work. The wrapper forwards
# $PSBoundParameters, so a switch the wrapper does not declare is rejected by
# the BINDER -- before the script runs, and a binding error sets no
# $LASTEXITCODE, so the failed call reports success. That is exactly what
# `tkWeb -Dev -NoBrowser` did: documented in the help since the browser-open
# landed, refused by the wrapper, nothing started, exit 0.
#
#
# The suite missed it because Test-Web.ps1 exercises -NoBrowser by invoking the
# SCRIPT. So this is the general guard, and it runs both ways:
#
#   forward  every parameter the help `usage` names that the SCRIPT really has
#            must be a parameter of the WRAPPER -- a documented switch can never
#            be silently refused again;
#   reverse  every parameter the WRAPPER declares must exist on the script --
#            a wrapper cannot advertise something the script will ignore.
#
# Aliases count on both sides ([Alias('Id')] on NewPrompt's -WorkItemId is how
# the documented `-Id <n>` binds), and common parameters are excluded: -WhatIf
# and -Confirm come from CmdletBinding, not from either param() block.

Write-Host "── Wrapper / script parameter parity ──────────────────" -ForegroundColor Cyan

$parityCommon = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
                @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)

function Get-ParameterNames {
    # Declared names AND their aliases, minus the common parameters.
    param($Command)
    $names = @()
    foreach ($key in $Command.Parameters.Keys) {
        if ($parityCommon -contains $key) { continue }
        $names += $key
        foreach ($a in @($Command.Parameters[$key].Aliases)) { if ($a) { $names += $a } }
    }
    return @($names | Select-Object -Unique)
}

$parityMap = Get-P20CommandMap | ConvertFrom-Json
# The rows the loop holds: every core verb's, from config.default.json, and every
# MODULE verb's, from its Config/<module>.commands.psd1 -- whether or not its flag
# is on here, because the committed config has every module off and a module verb
# has the same three places (script, wrapper, usage) as a core one. A module's
# wrappers are defined by dot-sourcing its own .ps1, exactly as the loader does.
$parityFns = @{}
$parityEntries = @{}
foreach ($cmdName in $commandNames) {
    $parityFns[$cmdName] = [string]$parityMap.$cmdName
    $parityEntries[$cmdName] = $config.commands.$cmdName
}
$parityNames = @($commandNames)
foreach ($psd1 in @(Get-ChildItem (Join-Path $toolkitRoot 'Config') -Filter '*.commands.psd1' -File)) {
    try { $moduleData = Import-PowerShellDataFile -Path $psd1.FullName } catch { continue }
    $modulePs1 = [System.IO.Path]::ChangeExtension($psd1.FullName, '.ps1')
    if (-not (Test-Path -LiteralPath $modulePs1)) { continue }
    $needsDefine = @($moduleData.Commands.Values | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }).Count -gt 0
    if ($needsDefine) { . $modulePs1 }
    foreach ($verb in @($moduleData.Commands.Keys)) {
        if ($parityFns.ContainsKey($verb)) { continue }
        $parityFns[$verb] = [string]$moduleData.Commands[$verb]
        $parityEntries[$verb] = $moduleData.Help[$verb]
        $parityNames += $verb
    }
}
$parityChecked = 0
foreach ($cmdName in $parityNames) {
    $fnName = $parityFns[$cmdName]
    if (-not $fnName) { continue }
    $wrapper = Get-Command $fnName -ErrorAction SilentlyContinue
    if (-not $wrapper) { continue }

    # Which script it forwards to, read out of the wrapper itself rather than
    # from a second table -- a second table is how two tables drift.
    $hit = [regex]::Match($wrapper.Definition, 'Scripts[\\/]([A-Za-z0-9\-]+\.ps1)')
    if (-not $hit.Success) { continue }   # Menu and the Test* verbs run in-process
    $scriptPath = Join-Path (Join-Path $toolkitRoot 'Scripts') $hit.Groups[1].Value
    $scriptCmd = Get-Command $scriptPath -ErrorAction SilentlyContinue
    Assert-True "$cmdName : its script is readable" ($null -ne $scriptCmd)
    if (-not $scriptCmd) { continue }
    $parityChecked++

    # A script that states a refusal (exit 2) is reached through the guard,
    # Invoke-ToolkitScript, or the refusal is never logged and a non-interactive
    # caller is told it succeeded (AGENTS.md, "The refusal contract"). The two
    # launchers below are the only exceptions, and each is listed with its reason.
    $bareByDesign = @{
        Web   = 'Start-Web.ps1 logs, prints and exits its own refusals; a second report from the wrapper would print a generic block under the readable one.'
        Agent = 'Start-Agent.ps1 logs, prints and exits its own refusals (ERR included); the guard would add a second ERR line and a generic block.'
    }
    $scriptRaw = [System.IO.File]::ReadAllText($scriptPath)
    if ($scriptRaw -match '(?m)^\s*exit 2' -and -not $bareByDesign.ContainsKey($cmdName)) {
        Assert-True "$cmdName : its script states refusals (exit 2), so the wrapper reaches it through Invoke-ToolkitScript" ($wrapper.Definition -match 'Invoke-ToolkitScript')
    }

    $scriptNames  = Get-ParameterNames $scriptCmd
    $wrapperNames = Get-ParameterNames $wrapper

    $usage = [string]$parityEntries[$cmdName].usage
    # A switch starts after a space or a bracket: the -MM and -dd inside a
    # `<yyyy-MM-dd>` placeholder are not switches.
    $usageNames = @([regex]::Matches($usage, '(?<![\w-])-([A-Za-z][A-Za-z0-9]*)') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $parityCommon -notcontains $_ } |
        Select-Object -Unique)

    # Forward: documented AND real on the script => must be on the wrapper.
    $documented = @($usageNames | Where-Object { $scriptNames -contains $_ })
    $refused = @($documented | Where-Object { $wrapperNames -notcontains $_ })
    Assert-True "$cmdName : the wrapper accepts every documented switch$(if ($refused.Count) { ' -- refuses: ' + ($refused -join ', ') })" ($refused.Count -eq 0)

    # The usage line must not name something neither block has.
    $phantom = @($usageNames | Where-Object { $scriptNames -notcontains $_ -and $wrapperNames -notcontains $_ })
    Assert-True "$cmdName : the usage line names nothing that does not exist$(if ($phantom.Count) { ' -- ' + ($phantom -join ', ') })" ($phantom.Count -eq 0)

    # Reverse: the wrapper must not take what the script cannot. -Help is the
    # one exception by design -- the wrapper renders help from the shared table
    # and returns, so the script is never reached. A wrapper-side guard is the
    # other: MeetingAgenda's -Extra catches stray positional text and refuses
    # it in the wrapper, so it never reaches the script either.
    $wrapperGuards = @{ MeetingAgenda = @('Extra') }
    $orphan = @($wrapperNames | Where-Object { $scriptNames -notcontains $_ -and $_ -ne 'Help' -and @($wrapperGuards[$cmdName]) -notcontains $_ })
    Assert-True "$cmdName : the wrapper declares nothing the script lacks$(if ($orphan.Count) { ' -- ' + ($orphan -join ', ') })" ($orphan.Count -eq 0)

    # Third direction: every parameter the SCRIPT has is named by the usage line
    # (itself or one of its aliases). The two above hold usage -> script and
    # wrapper -> script; nothing held script -> usage, so NewPR advertised
    # `[-Help]` while taking eight parameters, -Project and -Repository among them.
    #
    # `usage` is the authoritative list -- every verb has one and a reader reads
    # it; `switches`, where a verb has one, describes the same set (below).
    # Composition, not switches anyone types, and so not in any usage line:
    # Web's and Agent's -Reuse (Start-Web.ps1 reusing a running agent), Env's -Quiet (the
    # module's startup probe), InstallAutoload's -ModuleRoot and -CopyOnly
    # (Test-Autoload's scratch installs).
    $compositionByVerb = @{ Web = @('Reuse'); Agent = @('Reuse'); Env = @('Quiet'); InstallAutoload = @('ModuleRoot', 'CopyOnly') }
    $composition = @($compositionByVerb[$cmdName])
    # A positional parameter is documented by a bare placeholder -- `Archive <id>`
    # -- so the free placeholders (a <...> not right after a -Switch) pay for
    # positional parameters the usage does not spell out by name.
    $freePlaceholders = [regex]::Matches(($usage -replace '-[A-Za-z][A-Za-z0-9]*\s+<[^>]*>', ''), '<[^>]+>').Count
    $undocumented = @()
    foreach ($key in $scriptCmd.Parameters.Keys) {
        if ($parityCommon -contains $key -or $composition -contains $key) { continue }
        $spellings = @($key) + @($scriptCmd.Parameters[$key].Aliases)
        if (@($spellings | Where-Object { $usageNames -contains $_ }).Count -gt 0) { continue }
        $isPositional = @($scriptCmd.Parameters[$key].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Position -ge 0 }).Count -gt 0
        if ($isPositional -and $freePlaceholders -gt 0) { $freePlaceholders--; continue }
        $undocumented += $key
    }
    Assert-True "$cmdName : the usage line names every parameter the script has$(if ($undocumented.Count) { ' -- missing: ' + ($undocumented -join ', ') })" ($undocumented.Count -eq 0)

    # And every script parameter reaches the script: one the wrapper does not
    # declare is refused by the binder before the script runs.
    $unreachable = @($scriptCmd.Parameters.Keys | Where-Object { $parityCommon -notcontains $_ -and $composition -notcontains $_ -and $wrapperNames -notcontains $_ })
    Assert-True "$cmdName : the wrapper passes every parameter the script has$(if ($unreachable.Count) { ' -- missing: ' + ($unreachable -join ', ') })" ($unreachable.Count -eq 0)

    # A wrapper that takes -Help for a script that has none must answer it itself.
    # MyPRs forwarded it: a binding error, exit 0, and a hint pointing at -Help.
    if ($wrapperNames -contains 'Help' -and $scriptNames -notcontains 'Help') {
        Assert-True "$cmdName : the wrapper answers -Help itself, since the script has none" ($wrapper.Definition -match 'if\s*\(\s*\$Help\s*\)')
    }

    # Where a verb has a `switches` block, it describes exactly the usage set.
    $entry = $parityEntries[$cmdName]
    if ($null -ne $entry.switches) {
        $switchBare = @($entry.switches.PSObject.Properties.Name | Where-Object { $_ -ne '(none)' -and $_ -match '^-' } |
            ForEach-Object { ($_ -replace '^-', '') -replace '\s.*$', '' } |
            Where-Object { $parityCommon -notcontains $_ })
        $notDescribed = @($usageNames | Where-Object { $switchBare -notcontains $_ })
        $notInUsage = @($switchBare | Where-Object { $usageNames -notcontains $_ })
        Assert-True "$cmdName : switches describes every usage switch$(if ($notDescribed.Count) { ' -- missing: ' + ($notDescribed -join ', ') })" ($notDescribed.Count -eq 0)
        Assert-True "$cmdName : switches describes nothing the usage lacks$(if ($notInUsage.Count) { ' -- extra: ' + ($notInUsage -join ', ') })" ($notInUsage.Count -eq 0)
    }
}
Assert-True "parity ran over the script-backed verbs" ($parityChecked -ge 18)

Write-Host ""

# -- Menu -Reset writes through Config -----------------------------------------
# config.local.json has one writer, Config (Scripts/Set-ToolkitConfig.ps1). The
# reset used to write the file itself with Set-Content -Encoding UTF8, which puts
# a byte-order mark on it under Windows PowerShell 5.1 and not under 7. Run on
# THIS host -- the suite runs under both -- in a scratch package, twice: with no
# config.local.json, and with one that already carries a BOM (as an earlier
# reset left it). Either way the file comes out BOM-less, with the stamp, and
# with the keys it already had.

Write-Host "-- Menu -Reset: Config is the writer ----------------------" -ForegroundColor Cyan

$resetHost = (Get-Process -Id $PID).Path
$resetLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-menu-reset-logs-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resetLogs -Force | Out-Null
foreach ($resetCase in @(
        @{ Label = 'with no config.local.json'; Bom = $false; Json = '' },
        @{ Label = 'over a config.local.json that has a BOM'; Bom = $true; Json = '{ "quietStart": true }' })) {
    $resetScratch = New-MenuScratch ''
    try {
        $resetLocal = Join-Path $resetScratch 'config.local.json'
        if ($resetCase.Json) {
            [System.IO.File]::WriteAllText($resetLocal, $resetCase.Json, (New-Object System.Text.UTF8Encoding($resetCase.Bom)))
        }
        # The scratch has no config.local.json of this machine's, so its prefix is the shipped one.
        $resetPrefix = ((Get-Content (Join-Path $resetScratch 'config.default.json') -Raw) | ConvertFrom-Json).commandPrefix
        $resetModule = (Join-Path $resetScratch 'utilities.psm1') -replace "'", "''"
        $resetLogsQ = $resetLogs -replace "'", "''"
        $resetCmd = "`$env:PSModulePath = '$($resetScratch -replace "'", "''")' + [System.IO.Path]::PathSeparator + `$env:PSModulePath; `$env:P20_USAGE_LOG_DIR = '$resetLogsQ'; " +
            "Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item ('Env:' + `$_.Name) }; " +
            "Import-Module '$resetModule' -Force -DisableNameChecking 3>`$null; " +
            "`$r = & { ${resetPrefix}Menu -Reset } *>&1 | Out-String; 'RESET-CODE=' + `$LASTEXITCODE; 'RESET-OUT=' + (`$r -replace '\s+', ' ')"
        $resetEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($resetCmd))
        $savedEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $resetOut = (& $resetHost -NoProfile -EncodedCommand $resetEncoded 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        $ErrorActionPreference = $savedEap

        Assert-True "Menu -Reset $($resetCase.Label): says the scores were reset" ($resetOut -match 'RESET-OUT=.*Menu scores reset') $resetOut
        Assert-True "Menu -Reset $($resetCase.Label): exit 0" ($resetOut -match 'RESET-CODE=0\b') $resetOut
        Assert-True "Menu -Reset $($resetCase.Label): Config's own lines are not printed on success" ($resetOut -notmatch '\[\+\] menuResetTimestamp') $resetOut
        Assert-True "Menu -Reset $($resetCase.Label): config.local.json exists" (Test-Path $resetLocal)
        if (Test-Path $resetLocal) {
            $resetBytes = [System.IO.File]::ReadAllBytes($resetLocal)
            $hasBom = ($resetBytes.Length -ge 3 -and $resetBytes[0] -eq 0xEF -and $resetBytes[1] -eq 0xBB -and $resetBytes[2] -eq 0xBF)
            Assert-True "Menu -Reset $($resetCase.Label): config.local.json has no BOM on this host" (-not $hasBom) (($resetBytes | Select-Object -First 3) -join ',')
            $resetText = [System.Text.Encoding]::UTF8.GetString($resetBytes)
            Assert-True "Menu -Reset $($resetCase.Label): the stamp is written" ($resetText -match '"menuResetTimestamp":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"') $resetText
            Assert-True "Menu -Reset $($resetCase.Label): with Config's line endings (LF)" ($resetText -notmatch "`r") $resetText
            if ($resetCase.Json) {
                Assert-True "Menu -Reset $($resetCase.Label): the keys already there are kept" ($resetText -match '"quietStart":\s*true') $resetText
            }
        }
    }
    catch {
        Assert-True "Menu -Reset $($resetCase.Label): ran to the end without a terminating error -- $($_.Exception.Message)" $false
    }
    finally { Remove-Item $resetScratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Remove-Item $resetLogs -Recurse -Force -ErrorAction SilentlyContinue

# Config is the only writer: no Set-Content into config.local.json in the module,
# and the reset reaches the file through the Config script.
$resetModuleText = Get-Content (Join-Path $toolkitRoot 'utilities.psm1') -Raw
Assert-True 'utilities.psm1 has no Set-Content into config.local.json' ($resetModuleText -notmatch 'Set-Content.*config\.local')
$resetFn = Get-Command Reset-P20MenuScoring -ErrorAction SilentlyContinue
Assert-True 'the scores reset is a function of its own' ($null -ne $resetFn)
if ($resetFn) {
    Assert-True 'and it writes through the Config script' ($resetFn.Definition -match 'Set-ToolkitConfig\.ps1')
}
foreach ($menuJob in @('Show-P20MenuHelp', 'Get-P20MenuMarkdown')) {
    Assert-True "$menuJob is a function of its own" ($null -ne (Get-Command $menuJob -ErrorAction SilentlyContinue))
}
$menuFn = Get-Command Get-P20Menu -ErrorAction SilentlyContinue
if ($menuFn) {
    Assert-True 'Get-P20Menu writes no file itself' ($menuFn.Definition -notmatch 'Set-Content|WriteAllText|ConvertTo-Json')
}

Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Exit with failure code if any tests failed
if ($script:failed -gt 0) { exit 1 }
