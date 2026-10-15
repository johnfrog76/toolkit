<#
.SYNOPSIS
    The hub declares its own orgs -- <promptsRoot>/hub.json.
.DESCRIPTION
    config.default.json is committed and shared, so a private ADO org cannot go
    in it; the hub is where that engineer's cards already live, so the hub is
    where the engineer's orgs are declared ("data separate
    from software").

    A hub declares its orgs, its hub-root folder names and its storeSync -- the
    last because whether the store is a git repository is a fact about the hub,
    not about the machine reading it.

    Two halves, because the file has two callers:

      Unit -- Scripts/Resolve-HubConfig.ps1 dot-sourced directly, one throwaway
      hub per case, every warning collected with -WarningVariable.

      End to end -- a sandbox holding a copy of utilities.psm1, its Scripts/ and
      a pair of config files, imported in a fresh child pwsh, so what is asserted
      is the resolution order the module actually performs.

    The last end-to-end case is PARITY. Tests/fixtures/hub-parity holds one
    config.default.json, one hub/hub.json, one config.local.json and the resolved
    org list both halves of the Toolkit must produce. Tests/test_hub_json.py
    asserts the agent against the same expectation file (and, where pwsh is on
    the machine, runs this module and compares the two answers directly), so a
    drift in either loader turns one of the two suites red. The CLI does not
    shell out to Python to find that out -- Python is the agent's requirement,
    not the CLI's.

    Run:  pwsh -File Tests/Test-HubJson.ps1
    Or:   tkTestToolkit -HubJson
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = Split-Path $scriptDir -Parent
$resolver  = Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1'
$fixture   = Join-Path $scriptDir 'fixtures/hub-parity'

if (-not (Test-Path $resolver)) {
    Write-Error "Resolve-HubConfig.ps1 not found at $resolver"
    return
}

. $resolver

# -- Harness -------------------------------------------------------------------

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg = "$msg -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    Assert-True $TestName ("$Expected" -eq "$Actual") "expected '$Expected', got '$Actual'"
}

function Assert-AnyWarning {
    param([string]$TestName, [string[]]$Warnings, [string]$Needle)
    $hit = @($Warnings | Where-Object { $_ -like "*$Needle*" })
    Assert-True $TestName ($hit.Count -gt 0) "no warning contained '$Needle'; got: $($Warnings -join ' | ')"
}

# -- Unit sandbox --------------------------------------------------------------

function Write-FixtureFile {
    <# Write a fixture file, retrying while something else holds it. A file this
       suite has just written or imported is briefly open to a scanner or an
       exiting child process, and Windows PowerShell's Set-Content fails there
       with "Stream was not readable" or "being used by another process" at
       whichever write comes next. One retry loop, one place; the bytes
       are UTF-8 with no BOM on both shells. #>
    param([string]$Path, [string]$Value)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    for ($try = 1; $true; $try++) {
        try { [System.IO.File]::WriteAllText($Path, $Value, $encoding); return }
        catch { if ($try -ge 20) { throw }; Start-Sleep -Milliseconds 250 }
    }
}

function New-HubSandbox {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-hub-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    return $root
}

function Set-HubManifest {
    param([string]$Root, [string]$Json)
    Write-FixtureFile (Join-Path $Root 'hub.json') $Json
}

function Read-Manifest {
    <# Read a hub and hand back both the result and everything it warned about. #>
    param([string]$Root)
    $collected = @()
    $result = Read-P20HubManifest -Root $Root -WarningVariable collected -WarningAction SilentlyContinue
    return @{ Result = $result; Warnings = @($collected | ForEach-Object { $_.Message }) }
}

Write-Host ""
Write-Host "  hub.json -- the hub declares its own orgs" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# -- The declared folder set ---------------------------------------------------

Write-Host "-- The folder set ----------------------------------------" -ForegroundColor Cyan

$defaults = Get-P20DefaultHubFolders
Assert-Equal "the folder set has eight names" 8 $defaults.Count
foreach ($name in @('growth', 'manager', 'reviews', 'resume', 'agentic', 'reminders', 'design', 'spec')) {
    Assert-Equal "'$name' defaults to itself" $name $defaults[$name]
}

# The two tables say they MUST mirror each other, and for a time nothing
# held them to it: read the agent's DEFAULT_HUB_FOLDERS out of its source and
# compare it, key and value, with this half's.
$agentConfig = Get-Content (Join-Path $pkgRoot 'agent/core/config.py') -Raw
$block = [regex]::Match($agentConfig, '(?s)DEFAULT_HUB_FOLDERS = \{(.*?)\}').Groups[1].Value
$agentPairs = @{}
foreach ($m in [regex]::Matches($block, '"([a-z]+)":\s*"([^"]+)"')) { $agentPairs[$m.Groups[1].Value] = $m.Groups[2].Value }
Assert-Equal "the agent's folder table has as many names" $defaults.Count $agentPairs.Count
foreach ($name in $defaults.Keys) {
    Assert-Equal "the agent agrees '$name' defaults to '$($defaults[$name])'" $defaults[$name] $agentPairs[$name]
}

# -- Absent --------------------------------------------------------------------

Write-Host ""
Write-Host "-- Absent ------------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    $r = Read-Manifest $sandbox
    Assert-True "a hub with no hub.json reports no manifest" (-not $r.Result.Manifest)
    Assert-Equal "and declares no orgs" 0 @($r.Result.Spaces).Count
    Assert-Equal "and warns about nothing" 0 $r.Warnings.Count
    Assert-True "the path it looked at is still reported" ($r.Result.Path -like '*hub.json')

    $none = Read-Manifest ''
    Assert-True "no hub root at all is not an error" (-not $none.Result.Manifest)
    Assert-Equal "and names no path" '' $none.Result.Path

    # -- A hub that is NOT THERE ------------------------------------------------
    # On Windows this is a promptsRoot on an unmapped drive -- an unplugged disk,
    # a `subst` that has not run, a typo. Join-Path THROWS on one of those
    # ("Cannot find drive"), the Test-Path under it then bound a null and threw
    # again, and the catch reported it as "hub.json: not valid JSON ... fix the
    # file or delete it" -- a warning about a file problem that did not exist,
    # with an empty path.
    #
    # A missing DRIVE cannot be reproduced on macOS; a path under a directory
    # that does not exist reaches the same guard, which is the whole point of
    # checking Test-Path before any Join-Path rather than catching a throw.
    $ghost = Join-Path $sandbox 'no-such-folder/hub'
    $gone = Read-Manifest $ghost
    Assert-True "a hub that is not there reports no manifest" (-not $gone.Result.Manifest)
    Assert-Equal "and declares no orgs" 0 @($gone.Result.Spaces).Count
    Assert-Equal "and says NOTHING about hub.json" 0 $gone.Warnings.Count
    Assert-Equal "and names no path it never looked at" '' $gone.Result.Path
    Assert-True "Test-P20HubRoot answers false rather than throwing" (-not (Test-P20HubRoot $ghost))
    Assert-True "the missing-hub sentence names the root" ((Get-P20HubMissingMessage $ghost) -like "*$ghost*")
    Assert-True "and names where the path came from" ((Get-P20HubMissingMessage $ghost) -like '*config.local.json*')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- Malformed -----------------------------------------------------------------

Write-Host ""
Write-Host "-- Malformed ---------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    Set-HubManifest $sandbox '{ this is not json'
    $r = Read-Manifest $sandbox
    Assert-True "broken JSON does not throw" (-not $r.Result.Manifest)
    Assert-AnyWarning "the warning names the path" $r.Warnings 'hub.json'
    Assert-AnyWarning "and says what to do about it" $r.Warnings 'Fix the file or delete it'

    Set-HubManifest $sandbox '[]'
    $r = Read-Manifest $sandbox
    Assert-True "a JSON array at the top level is refused" (-not $r.Result.Manifest)
    Assert-AnyWarning "and says an object was wanted" $r.Warnings 'JSON object'

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": { "acme": { "promptsFolder": "acme" } } }'
    $r = Read-Manifest $sandbox
    Assert-Equal "'orgs' as an object declares nothing" 0 @($r.Result.Spaces).Count
    Assert-AnyWarning "and names the shape it wanted" $r.Warnings 'must be an array'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- Org entries ---------------------------------------------------------------

Write-Host ""
Write-Host "-- Org entries -------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme", "name": "Acme", "status": "local", "promptsFolder": "acme" } ] }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a usable org is collected" 1 @($r.Result.Spaces).Count
    Assert-Equal "with its slug" 'acme' @($r.Result.Spaces)[0].slug
    Assert-Equal "and its folder" 'acme' @($r.Result.Spaces)[0].promptsFolder
    Assert-Equal "and no warnings" 0 $r.Warnings.Count

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "name": "Nameless", "promptsFolder": "x" } ] }'
    $r = Read-Manifest $sandbox
    Assert-Equal "an org with no slug is skipped" 0 @($r.Result.Spaces).Count
    Assert-AnyWarning "and says so" $r.Warnings "no 'slug'"

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme", "name": "Acme" } ] }'
    $r = Read-Manifest $sandbox
    Assert-Equal "an org with no promptsFolder is skipped" 0 @($r.Result.Spaces).Count
    Assert-AnyWarning "and the warning names it" $r.Warnings "org 'acme'"

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme" }, { "slug": "beta", "promptsFolder": "beta" } ] }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a usable sibling still lands" 1 @($r.Result.Spaces).Count
    Assert-Equal "and it is the usable one" 'beta' @($r.Result.Spaces)[0].slug
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- Keys that are the machine's, not the hub's --------------------------------

Write-Host ""
Write-Host "-- Machine keys ------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    $machineKeys = @{
        activeOrg   = '"acme"'
        promptsRoot = '"/somewhere/else"'
        email       = '"someone@example.com"'
        branchUser  = '"someone"'
        wsRoot      = '"/ws"'
        web         = '{ "agentPort": 9999 }'
        commands    = '{ "Status": { "category": "prompt" } }'
        features    = '{ "growth": true }'
    }
    foreach ($key in @($machineKeys.Keys | Sort-Object)) {
        Set-HubManifest $sandbox "{ `"hub`": 1, `"$key`": $($machineKeys[$key]), `"orgs`": [] }"
        $r = Read-Manifest $sandbox
        Assert-AnyWarning "'$key' in hub.json is ignored with a warning" $r.Warnings "'$key'"
    }

    Set-HubManifest $sandbox '{ "hub": 1, "_comment": "mine, not the tool''s", "orgs": [], "folders": {} }'
    $r = Read-Manifest $sandbox
    Assert-Equal "an underscore comment key is not a warning" 0 $r.Warnings.Count
    Assert-True "and the manifest still reads" $r.Result.Manifest
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- Feature flags on a hub org ------------------------------------------------

Write-Host ""
Write-Host "-- Feature flags -----------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme", "promptsFolder": "acme", "features": { "sprintAwareness": true } } ] }'
    $r = Read-Manifest $sandbox
    Assert-True "an org-scoped flag on a hub org survives" ([bool]@($r.Result.Spaces)[0].features.sprintAwareness)
    Assert-Equal "and warns about nothing" 0 $r.Warnings.Count

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme", "promptsFolder": "acme", "features": { "growth": true } } ] }'
    $r = Read-Manifest $sandbox
    Assert-True "an engineer flag on a hub org is dropped" ($null -eq @($r.Result.Spaces)[0].PSObject.Properties['features'])
    Assert-AnyWarning "and the warning names the flag" $r.Warnings 'features.growth'
    Assert-AnyWarning "and says where it belongs" $r.Warnings 'config.local.json'

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [ { "slug": "acme", "promptsFolder": "acme", "features": { "sprintAwareness": true, "growth": true } } ] }'
    $r = Read-Manifest $sandbox
    Assert-True "the org-scoped sibling survives the filter" ([bool]@($r.Result.Spaces)[0].features.sprintAwareness)
    Assert-True "while the engineer flag does not" ($null -eq @($r.Result.Spaces)[0].features.PSObject.Properties['growth'])
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- Folders -------------------------------------------------------------------

Write-Host ""
Write-Host "-- Folders -----------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    Set-HubManifest $sandbox '{ "hub": 1, "folders": { "growth": "development", "manager": "1on1s" } }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a declared name is collected" 'development' $r.Result.Folders['growth']
    Assert-Equal "so is a second" '1on1s' $r.Result.Folders['manager']
    Assert-Equal "and nothing is warned about" 0 $r.Warnings.Count

    $names = Get-P20HubFolderNames -PromptsRoot $sandbox
    Assert-Equal "the declared name is what the resolver returns" 'development' $names['growth']
    Assert-Equal "an undeclared one keeps its default" 'reviews' $names['reviews']
    Assert-Equal "and the path is joined onto the hub" (Join-Path $sandbox 'development') (Get-P20HubFolder -Name 'growth' -PromptsRoot $sandbox)
    Assert-Equal "an undeclared folder resolves to its default path" (Join-Path $sandbox 'resume') (Get-P20HubFolder -Name 'resume' -PromptsRoot $sandbox)

    Set-HubManifest $sandbox '{ "hub": 1, "folders": { "growht": "development" } }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a folder key nothing reads is ignored" 0 $r.Result.Folders.Count
    Assert-AnyWarning "and warns with the key" $r.Warnings 'folders.growht'

    Set-HubManifest $sandbox '{ "hub": 1, "folders": { "growth": "" } }'
    $r = Read-Manifest $sandbox
    Assert-Equal "an empty folder name is ignored" 0 $r.Result.Folders.Count
    Assert-AnyWarning "and says which default it kept" $r.Warnings "keeping 'growth'"

    Remove-Item (Join-Path $sandbox 'hub.json') -Force
    $names = Get-P20HubFolderNames -PromptsRoot $sandbox
    Assert-Equal "with no manifest the defaults stand" 'growth' $names['growth']
    Assert-Equal "all eight of them" 8 $names.Count
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- storeSync -----------------------------------------------------------------

Write-Host ""
Write-Host "-- storeSync ---------------------------------------------" -ForegroundColor Cyan

$sandbox = New-HubSandbox
try {
    Set-HubManifest $sandbox '{ "hub": 1, "storeSync": "git" }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a hub may declare storeSync" 'git' $r.Result.StoreSync
    Assert-Equal "and it is not a machine key any more" 0 $r.Warnings.Count

    Set-HubManifest $sandbox '{ "hub": 1, "storeSync": "none" }'
    $r = Read-Manifest $sandbox
    Assert-Equal "'none' is the other value it may take" 'none' $r.Result.StoreSync

    Set-HubManifest $sandbox '{ "hub": 1, "storeSync": "yes" }'
    $r = Read-Manifest $sandbox
    Assert-Equal "anything else declares nothing" '' $r.Result.StoreSync
    Assert-AnyWarning "and warns with the key" $r.Warnings 'storeSync'
    Assert-AnyWarning "and says the configured value stands" $r.Warnings 'keeping the configured value'

    Set-HubManifest $sandbox '{ "hub": 1, "storeSync": true }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a value that is not a string declares nothing" '' $r.Result.StoreSync
    Assert-AnyWarning "and warns too" $r.Warnings 'storeSync'

    Set-HubManifest $sandbox '{ "hub": 1, "orgs": [] }'
    $r = Read-Manifest $sandbox
    Assert-Equal "a hub that says nothing declares nothing" '' $r.Result.StoreSync

    $values = Get-P20StoreSyncValues
    Assert-Equal "there are two values" 2 $values.Count
    Assert-True "and they are the ones the agent knows" (($values -contains 'git') -and ($values -contains 'none'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- End to end: the module's own resolution order -----------------------------

Write-Host ""
Write-Host "-- End to end --------------------------------------------" -ForegroundColor Cyan

function New-ModuleSandbox {
    <# A copy of the package big enough to import, plus the parity fixture's
       committed half. The local config is written per case. #>
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-hubmod-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1') (Join-Path $root 'utilities.psm1')
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $root 'Scripts') -Recurse
    Copy-Item (Join-Path $fixture 'config.default.json') (Join-Path $root 'config.default.json')
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $root 'consts.json')
    # The shipped templates: the communication verbs scaffold from them, and the
    # override cases below run those verbs for real.
    Copy-Item (Join-Path $pkgRoot 'templates') (Join-Path $root 'templates') -Recurse
    return $root
}

function Invoke-ModuleConfig {
    <# Import the sandboxed module in a fresh child pwsh with PROMPTS_ROOT
       pointing at the fixture hub, and hand back $global:P20Config as JSON. #>
    param([string]$Root, [string]$LocalJson, [string]$HubRoot)
    Write-FixtureFile (Join-Path $Root 'config.local.json') $LocalJson
    $modulePath = Join-Path $Root 'utilities.psm1'
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$env:PROMPTS_ROOT = '$HubRoot'
Import-Module '$modulePath' -Force -DisableNameChecking *>`$null
`$spaces = @(`$global:P20Config.Spaces | ForEach-Object {
    [ordered]@{
        slug            = [string]`$_.slug
        status          = [string]`$_.status
        org             = [string]`$_.org
        promptsFolder   = [string]`$_.promptsFolder
        sprintAwareness = [bool](`$_.features -and `$_.features.sprintAwareness)
    }
})
`$payload = [ordered]@{
    spaces          = `$spaces
    activeSpace     = [string]`$global:P20Config.ActiveSpace
    promptsFolder   = [string]`$global:P20Config.PromptsFolder
    hubManifest     = [bool]`$global:P20Config.HubManifest
    hubSpaceCount     = [int]`$global:P20Config.HubSpaceCount
    growthFolder    = [string]`$global:P20Config.HubFolders['growth']
    reviewsFolder   = [string]`$global:P20Config.HubFolders['reviews']
    storeSync       = [string]`$global:P20Config.StoreSync
}
ConvertTo-Json -InputObject `$payload -Depth 6 -Compress
"@
    $out = pwsh -NoProfile -Command $command 2>&1
    $lines = @("$out" -split "`n" | Where-Object { $_.Trim().StartsWith('{') })
    if ($lines.Count -eq 0) { return $null }
    return ($lines[-1] | ConvertFrom-Json)
}

$hubRoot  = Join-Path $fixture 'hub'
$expected = Get-Content (Join-Path $fixture 'expected-orgs.json') -Raw | ConvertFrom-Json
# The hub-wide half of the expectation. Separate file on purpose: storeSync is
# the hub's, not any one org's, and widening the org list to carry it would say
# something untrue about the shape.
$expectedScalars = Get-Content (Join-Path $fixture 'expected-scalars.json') -Raw | ConvertFrom-Json
$modSandbox = New-ModuleSandbox
try {
    $localJson = Get-Content (Join-Path $fixture 'config.local.json') -Raw
    $cfg = Invoke-ModuleConfig -Root $modSandbox -LocalJson $localJson -HubRoot $hubRoot

    Assert-True "the sandboxed module resolves a config" ($null -ne $cfg)
    if ($null -ne $cfg) {
        $got = @($cfg.spaces)
        Assert-Equal "PARITY: the resolved org list is the expected length" @($expected).Count $got.Count
        for ($i = 0; $i -lt @($expected).Count; $i++) {
            $e = @($expected)[$i]
            $g = $got[$i]
            $label = "PARITY: org $($i + 1) resolves as expected"
            if ($null -eq $g) {
                Assert-True $label $false "nothing at position $i"
            }
            else {
                $same = ($e.slug -eq $g.slug) -and ($e.status -eq $g.status) -and ($e.org -eq $g.org) `
                    -and ($e.promptsFolder -eq $g.promptsFolder) -and ([bool]$e.sprintAwareness -eq [bool]$g.sprintAwareness)
                Assert-True $label $same "expected $($e | ConvertTo-Json -Compress), got $($g | ConvertTo-Json -Compress)"
            }
        }
        Assert-True "a shipped slug is merged, not duplicated" (@($got | Where-Object { $_.slug -eq 'test' }).Count -eq 1)
        Assert-Equal "the hub's org URL wins over the shipped one" 'https://dev.azure.com/EXAMPLE-HUB-ORG' ($got | Where-Object { $_.slug -eq 'test' }).org
        Assert-Equal "a shipped org the hub said nothing about is untouched" 'archive' ($got | Where-Object { $_.slug -eq 'shipped-only' }).status
        Assert-Equal "the machine's patch wins over the hub" 'local' ($got | Where-Object { $_.slug -eq 'acme' }).status
        Assert-True "the manifest is reported as read" ([bool]$cfg.hubManifest)
        Assert-Equal "with the count it declared" 2 $cfg.hubSpaceCount
        Assert-Equal "PARITY: the hub's storeSync is what resolves" $expectedScalars.storeSync $cfg.storeSync
        Assert-Equal "a declared folder name reaches the config" $expectedScalars.growthFolder $cfg.growthFolder
        Assert-Equal "an undeclared one keeps its default" 'reviews' $cfg.reviewsFolder
        Assert-Equal "the shipped activeOrg still decides the active Space" 'test' $cfg.activeSpace
    }

    # PARITY, SPELLED THE NEW WAY (stage 2): the same three files with
    # `spaces` and `activeSpace` for `orgs` and `activeOrg` resolve to exactly
    # the same list. The fixture is Tests/fixtures/hub-parity-spaces, which
    # Tests/test_hub_json.py resolves too.
    $spacesFixture = Join-Path $scriptDir 'fixtures/hub-parity-spaces'
    $spacesSandbox = New-ModuleSandbox
    try {
        Copy-Item (Join-Path $spacesFixture 'config.default.json') (Join-Path $spacesSandbox 'config.default.json') -Force
        $spacesLocal = Get-Content (Join-Path $spacesFixture 'config.local.json') -Raw
        $cfg2 = Invoke-ModuleConfig -Root $spacesSandbox -LocalJson $spacesLocal -HubRoot (Join-Path $spacesFixture 'hub')
        Assert-True "PARITY (spaces spelling): the sandboxed module resolves a config" ($null -ne $cfg2)
        if ($null -ne $cfg2 -and $null -ne $cfg) {
            $a = @($cfg.spaces) | ConvertTo-Json -Compress -Depth 4
            $b = @($cfg2.spaces) | ConvertTo-Json -Compress -Depth 4
            Assert-Equal "PARITY (spaces spelling): the SAME org list as the older spelling" $a $b
            Assert-Equal "PARITY (spaces spelling): activeSpace decides the active Space" 'test' $cfg2.activeSpace
            Assert-Equal "PARITY (spaces spelling): the hub's storeSync still resolves" $expectedScalars.storeSync $cfg2.storeSync
            Assert-Equal "PARITY (spaces spelling): the hub's count is the same" $cfg.hubSpaceCount $cfg2.hubSpaceCount
        }
    }
    finally { Remove-Item $spacesSandbox -Recurse -Force -ErrorAction SilentlyContinue }

    # The canonicaliser itself, at the unit: the new spelling wins when a file
    # carries both, an empty activeSpace is no answer, and a non-object passes.
    $both = '{ "activeOrg": "old", "activeSpace": "new", "orgs": [1], "spaces": [1, 2] }' | ConvertFrom-Json
    $both = ConvertTo-P20SpaceKeys $both
    Assert-Equal "both spellings present: activeSpace wins" 'new' $both.activeSpace
    Assert-Equal "both spellings present: spaces wins" 2 @($both.spaces).Count
    Assert-True "and the old keys are dropped, so nothing downstream sees them" ($null -eq $both.PSObject.Properties['orgs'] -and $null -eq $both.PSObject.Properties['activeOrg'])
    $oldOnly = '{ "activeOrg": "old", "orgs": [1] }' | ConvertFrom-Json
    $oldOnly = ConvertTo-P20SpaceKeys $oldOnly
    Assert-Equal "an older file's activeOrg lands on activeSpace" 'old' $oldOnly.activeSpace
    Assert-Equal "and its orgs on spaces" 1 @($oldOnly.spaces).Count
    Assert-True "with the old names gone" ($null -eq $oldOnly.PSObject.Properties['orgs'])
    $blank = '{ "activeOrg": "old", "activeSpace": "" }' | ConvertFrom-Json
    Assert-Equal "an empty activeSpace is no answer" 'old' (ConvertTo-P20SpaceKeys $blank).activeSpace
    Assert-True "a null passes through" ($null -eq (ConvertTo-P20SpaceKeys $null))

    # The write side: the file's spelling is `spaces` / `activeSpace`, the
    # canonical value wins, the order is kept, and a file already spelled the
    # new way is left alone by the migration.
    $written = ConvertTo-P20SpaceSpelling ('{ "hub": 1, "activeOrg": "x", "orgs": [ { "slug": "a" } ], "folders": {} }' | ConvertFrom-Json)
    Assert-Equal "orgs is written as spaces" 'a' (@($written.spaces)[0].slug)
    Assert-True "and orgs is not written" ($null -eq $written.PSObject.Properties['orgs'])
    Assert-Equal "activeOrg is written as activeSpace" 'x' $written.activeSpace
    Assert-Equal "and the order is kept: spaces stands where orgs stood" 'spaces' @($written.PSObject.Properties | ForEach-Object { $_.Name })[2]
    $mutated = '{ "orgs": [ { "slug": "old" } ] }' | ConvertFrom-Json
    $mutated | Add-Member -NotePropertyName 'spaces' -NotePropertyValue @([pscustomobject]@{ slug = 'new' })
    Assert-Equal "the canonical value the code mutated wins over the orgs a raw file still had" 'new' (@((ConvertTo-P20SpaceSpelling $mutated).spaces)[0].slug)
    Assert-True "and orgs is not written beside it" ($null -eq (ConvertTo-P20SpaceSpelling $mutated).PSObject.Properties['orgs'])
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-spell-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    try {
        Write-FixtureFile $tmpFile '{ "hub": 1, "orgs": [] }'
        Assert-True "a file spelled orgs is migrated" (Update-P20SpaceKeysInFile -Path $tmpFile)
        Assert-True "and now says spaces" ((Get-Content $tmpFile -Raw) -match '"spaces"')
        Assert-True "a file already spelled spaces is left alone" (-not (Update-P20SpaceKeysInFile -Path $tmpFile))
        Assert-True "a missing file is left alone" (-not (Update-P20SpaceKeysInFile -Path ($tmpFile + '.missing')))
    }
    finally { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }

    # An org that exists only because the hub declared it is a first-class org:
    # selectable, and its promptsFolder is where its cards are read from.
    $cfg = Invoke-ModuleConfig -Root $modSandbox -HubRoot $hubRoot -LocalJson '{ "activeOrg": "acme", "orgs": { "acme": { "status": "local" } } }'
    Assert-True "a hub-only org can be made active" ($null -ne $cfg -and $cfg.activeSpace -eq 'acme')
    Assert-Equal "and its promptsFolder is the hub's" 'acme' $cfg.promptsFolder

    # storeSync, end to end: the hub turns it on for every machine that reads
    # the hub, and a machine that must never push says so in its own config.
    $syncHub = New-HubSandbox
    try {
        Set-HubManifest $syncHub '{ "hub": 1, "storeSync": "git" }'
        $cfg = Invoke-ModuleConfig -Root $modSandbox -HubRoot $syncHub -LocalJson '{}'
        Assert-Equal "a hub-declared storeSync reaches the config" 'git' $cfg.storeSync

        $cfg = Invoke-ModuleConfig -Root $modSandbox -HubRoot $syncHub -LocalJson '{ "storeSync": "none" }'
        Assert-Equal "and this machine still has the last word" 'none' $cfg.storeSync

        Set-HubManifest $syncHub '{ "hub": 1 }'
        $cfg = Invoke-ModuleConfig -Root $modSandbox -HubRoot $syncHub -LocalJson '{}'
        Assert-Equal "a hub that declares none of it keeps the shipped value" 'none' $cfg.storeSync
    }
    finally { Remove-Item $syncHub -Recurse -Force -ErrorAction SilentlyContinue }

    # A hub that is NOT THERE gets ONE sentence at import, and no hub.json
    # warning at all. The import used to print a Join-Path stack trace, a null
    # Test-Path under it, and a warning blaming a file that did not exist.
    $ghostRoot = Join-Path $modSandbox 'no-such-folder/hub'
    Write-FixtureFile (Join-Path $modSandbox 'config.local.json') '{}'
    $modulePath = Join-Path $modSandbox 'utilities.psm1'
    $importOut = pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$ghostRoot'; Import-Module '$modulePath' -Force -DisableNameChecking" 2>&1 | Out-String
    Assert-True "a missing hub is one stated warning at import" ($importOut -like '*Hub not found*') $importOut
    Assert-True "which names the root" ($importOut -like "*$ghostRoot*") $importOut
    Assert-True "and no hub.json warning at all" ($importOut -notlike '*not valid JSON*') $importOut
    Assert-True "and no Join-Path stack trace" ($importOut -notmatch 'Cannot find drive|Cannot bind argument') $importOut
    Assert-Equal "and it is said exactly once" 1 (@([regex]::Matches($importOut, 'Hub not found')).Count)

    # A hub with no manifest changes nothing at all.
    $emptyHub = New-HubSandbox
    try {
        $cfg = Invoke-ModuleConfig -Root $modSandbox -HubRoot $emptyHub -LocalJson '{}'
        Assert-True "no hub.json means no manifest" ($null -ne $cfg -and -not $cfg.hubManifest)
        Assert-Equal "and only the shipped orgs" 2 @($cfg.spaces).Count
        Assert-Equal "and the default folder names" 'growth' $cfg.growthFolder
    }
    finally { Remove-Item $emptyHub -Recurse -Force -ErrorAction SilentlyContinue }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $modSandbox -Recurse -Force -ErrorAction SilentlyContinue }

# -- A shipped Space's old slug (test -> azure-demo) ----------------------
#
# The rule is one table, Tests/fixtures/space-renamed/table.json, which
# Tests/test_hub_json.py asserts against the agent's half.

Write-Host ""
Write-Host "-- A renamed shipped Space --------------------------" -ForegroundColor Cyan

$renamedTable = Get-Content (Join-Path $scriptDir 'fixtures/space-renamed/table.json') -Raw | ConvertFrom-Json
Assert-Equal "the contract names the rename" 'azure-demo' (Get-P20RenamedSpaceSlugs)['test']
foreach ($row in @($renamedTable.slugs)) {
    Assert-Equal "RENAMED (slug): $($row.why)" ([string]$row.expect) (Resolve-P20RenamedSlug -Slug ([string]$row.slug) -Slugs @($row.slugs))
}
foreach ($row in @($renamedTable.entries)) {
    $entry = $row.entry | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    $out = @(Rename-P20LegacyHubSpaces -Spaces @($entry) -ShippedSlugs @($row.shipped))
    Assert-Equal "RENAMED (entry): $($row.why)" ([string]$row.expect) ([string]$out[0].slug)
    Assert-Equal "RENAMED (entry): $($row.why) -- and its promptsFolder stands" ([string]$row.entry.promptsFolder) ([string]$out[0].promptsFolder)
}

# End to end, against the SHIPPED config: a machine that connected the old
# Example before the rename -- a nameless hub.json patch under `test` and an
# activeSpace that still says test -- keeps its Space, under the new slug, with
# its cards where they were.
$renamedSandbox = New-ModuleSandbox
$renamedHub = New-HubSandbox
try {
    Copy-Item (Join-Path $pkgRoot 'config.default.json') (Join-Path $renamedSandbox 'config.default.json') -Force
    Set-HubManifest $renamedHub '{ "hub": 1, "spaces": [ { "slug": "test", "promptsFolder": "test", "org": "https://dev.azure.com/SomeOrg", "status": "active" } ] }'
    $cfg = Invoke-ModuleConfig -Root $renamedSandbox -HubRoot $renamedHub -LocalJson '{ "activeSpace": "test", "spaces": { "test": { "tenant": "contoso" } } }'
    Assert-True "the module resolves a config over the old slug" ($null -ne $cfg)
    if ($null -ne $cfg) {
        Assert-True "no Space answers to the old slug" (@($cfg.spaces | Where-Object { $_.slug -eq 'test' }).Count -eq 0)
        Assert-Equal "the old activeSpace is the new Space" 'azure-demo' $cfg.activeSpace
        Assert-Equal "with the hub patch's promptsFolder, where its cards are" 'test' $cfg.promptsFolder
        $azure = @($cfg.spaces | Where-Object { $_.slug -eq 'azure-demo' })[0]
        Assert-Equal "and the hub patch's address" 'https://dev.azure.com/SomeOrg' $azure.org
        Assert-Equal "and its status" 'active' $azure.status
    }
    # A Space that names itself `test` is its own (Tests/fixtures/hub's shape).
    Set-HubManifest $renamedHub '{ "hub": 1, "spaces": [ { "slug": "test", "name": "Mine", "status": "local", "promptsFolder": "test" } ] }'
    $cfg = Invoke-ModuleConfig -Root $renamedSandbox -HubRoot $renamedHub -LocalJson '{ "activeSpace": "test" }'
    Assert-Equal "a Space that names itself test stays test, beside azure-demo" 'azure-demo,test' ((@($cfg.spaces) | ForEach-Object { $_.slug }) -join ',')
    Assert-Equal "and is the active one" 'test' $cfg.activeSpace
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $renamedSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $renamedHub -Recurse -Force -ErrorAction SilentlyContinue
}

# -- PROMPTS_ROOT is an override, in EVERY half --------------------------------
#
# The docs say it in four places: PROMPTS_ROOT in the environment is an explicit
# override that WINS over the configured promptsRoot. The code said three
# different things once -- the agent and five scripts let it win,
# $global:P20Config.PromptsRoot ignored it, and New-Meeting and MeetingAgenda
# used it only as a fallback for an EMPTY config. With both set, the web half
# read one hub and the 1:1 verbs WROTE INTO another, which on an engineer's
# machine is their real store.
#
# So this asserts the module and two module verbs -- one growth, one
# communication -- against the same environment, and it asserts where the files
# LANDED rather than only what a variable says.

Write-Host ""
Write-Host "-- One hub root, env first -------------------------------" -ForegroundColor Cyan

function New-OverrideHub {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-hubroot-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    return $root
}

$envHub    = New-OverrideHub   # what PROMPTS_ROOT names -- must win
$configHub = New-OverrideHub   # what config.local.json names -- must not
$rootSandbox = New-ModuleSandbox
try {
    Write-FixtureFile (Join-Path $rootSandbox 'config.local.json') `
        ("{ `"promptsRoot`": `"" + ($configHub -replace '\\', '/') + "`", `"activeOrg`": `"test`" }")

    # 1. The module.
    $modCmd = @"
`$env:PROMPTS_ROOT = '$envHub'
Import-Module '$(Join-Path $rootSandbox 'utilities.psm1')' -Force -DisableNameChecking *>`$null
Write-Output `$global:P20Config.PromptsRoot
"@
    $modRoot = ((pwsh -NoProfile -Command $modCmd 2>&1 | Out-String) -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
    Assert-Equal "the module's PromptsRoot is the env override" $envHub $modRoot

    # 2. A growth verb, run as the bridge and the suites run it: a child pwsh
    #    with no module in the session.
    $growthOut = & pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$envHub'; & '$(Join-Path $rootSandbox 'Scripts/New-GrowthItem.ps1')' -Title 'Env override' -Type goal" 2>&1 | Out-String
    $growthLanded = @(Get-ChildItem -Path (Join-Path $envHub 'growth/current') -Filter '*.prompt.md' -ErrorAction SilentlyContinue).Count
    Assert-Equal "a growth verb writes into the env override" 1 $growthLanded
    Assert-True "and nothing was written into the configured hub" `
        (-not (Test-Path (Join-Path $configHub 'growth'))) $growthOut

    # 3. A communication verb. This is the pair that was actually wrong: it read
    #    the env var only when config was EMPTY, so it wrote 1:1 sessions into
    #    the configured store while the agent served the overridden one.
    $meetOut = & pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$envHub'; & '$(Join-Path $rootSandbox 'Scripts/New-Meeting.ps1')' -Date 2026-07-01" 2>&1 | Out-String
    Assert-True "a communication verb writes into the env override" `
        (Test-Path (Join-Path $envHub 'manager/current/2026-07-01.md')) $meetOut
    Assert-True "and nothing was written into the configured hub" `
        (-not (Test-Path (Join-Path $configHub 'manager'))) $meetOut

    # 4. And MeetingAgenda reads the same one -- it had the fallback twice, once
    #    for the folder NAME and once for the root.
    $agendaOut = & pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$envHub'; & '$(Join-Path $rootSandbox 'Scripts/Get-MeetingAgenda.ps1')' -Date 2026-07-01 -Close" 2>&1 | Out-String
    Assert-True "the session closes in the env override" `
        (Test-Path (Join-Path $envHub 'manager/archive/2026-07-01.md')) $agendaOut
    Assert-True "and the configured hub is still untouched" `
        (-not (Test-Path (Join-Path $configHub 'manager'))) $agendaOut

    # 5. With no override, config is the answer -- the rule is env FIRST, not
    #    env ONLY.
    $noEnvCmd = @"
Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue
Import-Module '$(Join-Path $rootSandbox 'utilities.psm1')' -Force -DisableNameChecking *>`$null
Write-Output `$global:P20Config.PromptsRoot
"@
    $noEnvRoot = ((pwsh -NoProfile -Command $noEnvCmd 2>&1 | Out-String) -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
    Assert-Equal "with no override the configured hub is the answer" ($configHub -replace '\\', '/') ($noEnvRoot -replace '\\', '/')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $rootSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $envHub -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $configHub -Recurse -Force -ErrorAction SilentlyContinue
}

# -- The Space and the flags from the environment -------------------------
#
# PROMPTS_ROOT's two siblings, for `Web -Dev -Fixture`: consts.json env.activeSpace
# stands in for config.local.json's activeSpace and env.features for its features
# block, per PROCESS, so a smoke run never rewrites the machine's file. The agent
# reads them in load_config (Tests/test_config.py, EnvironmentStandInTests); this
# is the module's half, imported in a fresh shell the way a bridge child is.

Write-Host ""
Write-Host "-- The Space and the flags from the environment --------" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
$spaceVar = [string](Get-P20Consts).env.activeSpace
$featuresVar = [string](Get-P20Consts).env.features
$standInSandbox = New-ModuleSandbox
try {
    Write-FixtureFile (Join-Path $standInSandbox 'config.local.json') `
        '{ "activeSpace": "test", "features": { "growth": true, "communication": true, "organize": true }, "email": "someone@example.invalid" }'
    $probe = {
        param([string]$Space, [string]$Features)
        $cmd = @"
`$env:$spaceVar = '$Space'
`$env:$featuresVar = '$Features'
Import-Module '$(Join-Path $standInSandbox 'utilities.psm1')' -Force -DisableNameChecking *>`$null
`$f = Get-P20Features
ConvertTo-Json -Compress -InputObject ([ordered]@{ space = [string]`$global:P20Config.ActiveSpace; email = [string]`$global:P20Config.Email; growth = [bool]`$f['growth']; communication = [bool]`$f['communication']; organize = `$f.ContainsKey('organize') })
"@
        $out = pwsh -NoProfile -Command $cmd 2>&1 | Out-String
        $line = @($out -split "`n" | Where-Object { $_.Trim().StartsWith('{') }) | Select-Object -Last 1
        if (-not $line) { return $null }
        return ($line | ConvertFrom-Json)
    }

    $unset = & $probe '' ''
    Assert-True 'unset, the files decide the Space' ($unset -and $unset.space -eq 'test') "$($unset | ConvertTo-Json -Compress)"
    Assert-True 'unset, the files decide the flags' ($unset -and $unset.organize) "$($unset | ConvertTo-Json -Compress)"

    $moved = & $probe 'shipped-only' ''
    Assert-Equal 'the Space override wins over config.local.json' 'shipped-only' $moved.space

    $none = & $probe '' '{}'
    Assert-True '{} is no flag set: the file''s growth does not survive it' ($none -and -not $none.growth -and -not $none.communication) "$($none | ConvertTo-Json -Compress)"
    Assert-True 'and the override REPLACES the block: organize is not merely false, it is absent' ($none -and -not $none.organize) "$($none | ConvertTo-Json -Compress)"

    $on = & $probe '' '{"growth":true,"communication":true}'
    Assert-True 'the smoke''s modules-on block turns growth and communication on' ($on -and $on.growth -and $on.communication) "$($on | ConvertTo-Json -Compress)"
    Assert-True 'and nothing from the file leaks through it' ($on -and -not $on.organize) "$($on | ConvertTo-Json -Compress)"

    $bad = & $probe '' 'not json'
    Assert-True 'a malformed features value is ignored, and the file''s flags stand' ($bad -and $bad.growth -and $bad.organize) "$($bad | ConvertTo-Json -Compress)"

    Assert-Equal 'the rest of config.local.json still applies' 'someone@example.invalid' $on.email
    $localAfter = Get-Content (Join-Path $standInSandbox 'config.local.json') -Raw
    Assert-True 'and nothing was written to it' ($localAfter -match '"organize": true' -and $localAfter -match '"activeSpace": "test"') $localAfter
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $standInSandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# -- Summary -------------------------------------------------------------------

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
