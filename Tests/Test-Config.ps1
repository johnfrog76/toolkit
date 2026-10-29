<#
.SYNOPSIS
    The Config verb -- the one writer for configuration.
.DESCRIPTION
    Every case runs against a SCRATCH package and a SCRATCH hub: a throwaway
    directory holding a copy of config.default.json, consts.json and Scripts/,
    with its own hub beside it. Nothing here reads or writes the engineer's real
    config.local.json or their real hub, which is the whole reason the sandbox
    is a copy rather than a PROMPTS_ROOT pointed at the tree.

    What it holds:

      * -List names the FILE each value came from -- default, hub, local, env.
        That is the one thing the module's merged config has forgotten, and the
        reason this command reads the three files itself.
      * a machine key CREATES config.local.json as a sparse patch, and a second
        write preserves the keys the first one put there.
      * the scope rule: a machine key to config.local.json, an org to the hub's
        hub.json, a new slug appended with the two fields both loaders require,
        an archive that sets a value rather than deleting an entry.
      * the refusals, by exit code AND by sentence: a key that lives only in
        config.default.json, an unknown key, a value outside the allowed set, a
        hub declaration without -Hub, a required org field that -Unset must not
        remove.
      * idempotence: the same -Set twice leaves the same bytes.
      * the byte contract: UTF-8 with no BOM, LF, and the same two-space JSON on
        either host.

    The 5.1 floor is the Compat suite's business, not this one's -- every file
    here is scanned by it like any other script.

    Run:  pwsh -File Tests/Test-Config.ps1
    Or:   tkTestToolkit -Config
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

# PROMPTS_ROOT is the hub override, and the runner exports it pointing at THIS
# repo so the org-scoped suites have a hub to read. The verb honours it above
# config, so every child below would resolve the checkout as its hub and write
# a hub.json into the source tree. Cleared for the length of this suite and put
# back at the end; the one case that is ABOUT the override sets it on its own
# child.
$script:SavedPromptsRoot = $env:PROMPTS_ROOT
Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue

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

function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    Assert-True $TestName ($Haystack -like "*$Needle*") "'$Needle' not in: $Haystack"
}

# -- The sandbox ---------------------------------------------------------------

function Invoke-LockRetry {
    <# Run one read, write or copy of a scratch file, retrying while something else
       holds it. A file this suite has just copied or written is briefly open to a
       scanner or to the child shell that wound down, and Windows PowerShell fails
       there with "being used by another process" or "Stream was not readable".
       The same family occurs in Test-Start and Test-HubJson. 20 tries,
       half a second apart; a file held for ten seconds is a named FAIL here rather
       than a throw that ends the group. One loop, one place. #>
    param([string]$Name, [scriptblock]$Action)
    $last = ''
    for ($try = 1; $try -le 20; $try++) {
        try { $ErrorActionPreference = 'Stop'; return (& $Action) }
        catch { $last = $_.Exception.Message; Start-Sleep -Milliseconds 500 }
    }
    Assert-True "$Name (the file stayed held for 10 seconds)" $false $last
    return $null
}
function New-ConfigSandbox {
    <#
      A throwaway package plus a hub beside it. The package carries only what the
      verb reads: the shipped config, the contract file and Scripts/.
    #>
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $pkg = Join-Path $root 'pkg'
    $hub = Join-Path $root 'hub'
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    New-Item -ItemType Directory -Path $hub -Force | Out-Null
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'config.default.json') $pkg -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'consts.json') $pkg -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $pkg -Recurse -Force }
    return @{ Root = $root; Pkg = $pkg; Hub = $hub; Script = (Join-Path $pkg 'Scripts/Set-ToolkitConfig.ps1') }
}

function Invoke-Config {
    <#
      Run the verb in a fresh child pwsh, exactly as a user would, and hand back
      stdout and the exit code. A child process because the exit code IS the
      refusal contract: `exit 2` in-process would end this suite.
    #>
    param([hashtable]$Box, [string[]]$Arguments)
    # -File, not -Command: it hands every token through as argv and returns the
    # script's own exit code unchanged, which is the refusal contract this suite
    # is here to read. It is also exactly how agent/ado/bridge.ps1 is started,
    # so a case that passes here passes through the bridge.
    #
    # The arguments travel as ONE -EncodedCommand, not as argv: a Windows
    # PowerShell 5.1 host strips the embedded `"` from a native child's argument
    # (`{"email":"x"}` arrives as `{email:x}`) and pwsh 7.3+ escapes them, so the
    # JSON form the bridge carries only survives if it never goes through a
    # command line. A token that starts with `-` is a parameter name and goes
    # bare; every other is a single-quoted literal, which is what keeps it
    # byte for byte. `exit $LASTEXITCODE` hands back the script's own code.
    $quoted = ($Arguments | ForEach-Object {
            if ($_ -like '-*' -and $_ -notmatch '[=\s]') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
        }) -join ' '
    $command = "& '" + ($Box.Script -replace "'", "''") + "' $quoted; exit `$LASTEXITCODE"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $out = & pwsh -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String
    return @{ Output = $out; ExitCode = $LASTEXITCODE }
}

function Get-LocalConfigText {
    param([hashtable]$Box)
    $path = Join-Path $Box.Pkg 'config.local.json'
    if (-not (Test-Path $path)) { return '' }
    return ((Invoke-LockRetry 'read of a scratch file' { Get-Content $path -Raw }))
}

function Get-HubText {
    param([hashtable]$Box)
    $path = Join-Path $Box.Hub 'hub.json'
    if (-not (Test-Path $path)) { return '' }
    return ((Invoke-LockRetry 'read of a scratch file' { Get-Content $path -Raw }))
}

function Get-HubSpace {
    <# One org entry out of the sandbox hub, or $null. #>
    param([hashtable]$Box, [string]$Slug)
    $text = Get-HubText $Box
    if (-not $text) { return $null }
    # The file's spelling is `spaces` since the Space rename.
    $hit = @(($text | ConvertFrom-Json).spaces | Where-Object { $_.slug -eq $Slug })
    if ($hit.Count -eq 0) { return $null }
    return $hit[0]
}

function Set-HubRoot {
    <# Point the sandbox package at its own hub. #>
    param([hashtable]$Box)
    [void](Invoke-Config $Box @('-Set', "promptsRoot=$($Box.Hub)"))
}

Write-Host ''
Write-Host '  Config -- the one writer for configuration' -ForegroundColor Cyan
Write-Host '  -----------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

# -- The schema ----------------------------------------------------------------

Write-Host '-- The schema --------------------------------------------' -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Get-ConfigSchema.ps1')
$defaultCfg = Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json
$schemaRows = Get-P20ConfigSchema -DefaultConfig $defaultCfg -Spaces @($defaultCfg.spaces)

Assert-True 'the schema has rows' (@($schemaRows).Count -gt 10) "$(@($schemaRows).Count)"

# The parity the web spec's 8.6 wanted from a schema FILE, without the file:
# every top-level key of the shipped config is accounted for in some scope, so a
# key added there cannot be silently unsettable and undescribed.
$schemaTops = @($schemaRows | ForEach-Object { ($_.key -split '\.')[0] } | Select-Object -Unique)
$missing = @()
foreach ($prop in $defaultCfg.PSObject.Properties) {
    if ($prop.Name.StartsWith('_')) { continue }
    if ($prop.Name -eq 'spaces') { continue }
    if ($schemaTops -notcontains $prop.Name) { $missing += $prop.Name }
}
Assert-True "every shipped config key is in the schema$(if ($missing.Count) { ' -- missing: ' + ($missing -join ', ') })" ($missing.Count -eq 0)

# And the reverse: a machine row must not name a key the shipped file has as the
# team's table.
$machineKeys = @($schemaRows | Where-Object { $_.scope -eq 'machine' } | ForEach-Object { ($_.key -split '\.')[0] } | Select-Object -Unique)
Assert-True 'no machine row claims commands or workItemTypes' `
    (($machineKeys -notcontains 'commands') -and ($machineKeys -notcontains 'workItemTypes'))

Assert-Equal 'status offers the three org statuses' 'active, local, archive' `
    ((@($schemaRows | Where-Object { $_.key -like '*status' } | Select-Object -First 1).allowed) -join ', ')

$folderRows = @($schemaRows | Where-Object { $_.key -like 'folders.*' })
# Eight since the design lifecycle's `spec` folder joined the table (D-DL12).
Assert-Equal 'the hub-root folder set is eight names' 8 $folderRows.Count
Assert-True 'and spec is one of them' (@($folderRows | Where-Object { $_.key -eq 'folders.spec' }).Count -eq 1)
Assert-True 'a folder row is hub-scoped' (@($folderRows | Where-Object { $_.scope -ne 'hub' }).Count -eq 0)

# -- -List ---------------------------------------------------------------------

Write-Host ''
Write-Host '-- -List names the file each value came from --------------' -ForegroundColor Cyan

$box = New-ConfigSandbox
try {
    $listed = Invoke-Config $box @('-List', '-AsJson')
    Assert-Equal '-List -AsJson exits 0' 0 $listed.ExitCode
    $parsed = $null
    try { $parsed = $listed.Output | ConvertFrom-Json } catch { $null = $_ }
    Assert-True '-List -AsJson is one JSON object' ($null -ne $parsed) $listed.Output
    if ($parsed) {
        $emailRow = @($parsed.settings | Where-Object { $_.key -eq 'email' })
        Assert-Equal 'email is unset in a fresh package' 'unset' $emailRow[0].source
        $prefixRow = @($parsed.settings | Where-Object { $_.key -eq 'commandPrefix' })
        Assert-Equal 'commandPrefix comes from the shipped file' 'default' $prefixRow[0].source
    }

    # A machine key creates the file, and the source moves to 'local'.
    $setResult = Invoke-Config $box @('-Set', 'email=someone@example.com')
    Assert-Equal 'a first -Set exits 0' 0 $setResult.ExitCode
    Assert-True 'config.local.json is created' (Test-Path (Join-Path $box.Pkg 'config.local.json'))
    $afterText = Get-LocalConfigText $box
    Assert-Contains 'it holds the key that was set' $afterText 'someone@example.com'
    Assert-True 'and nothing else from the shipped file' ($afterText -notlike '*workItemTypes*') $afterText

    $listed2 = (Invoke-Config $box @('-List', '-AsJson')).Output | ConvertFrom-Json
    $emailRow2 = @($listed2.settings | Where-Object { $_.key -eq 'email' })
    Assert-Equal 'email now reads from local' 'local' $emailRow2[0].source
    Assert-Equal 'and carries the value that was written' 'someone@example.com' $emailRow2[0].value

    # The environment override is a source of its own.
    $envList = & pwsh -NoProfile -Command "`$env:PROMPTS_ROOT = '$($box.Hub)'; & '$($box.Script)' -List -AsJson" 2>&1 | Out-String
    $envParsed = $envList | ConvertFrom-Json
    $rootRow = @($envParsed.settings | Where-Object { $_.key -eq 'promptsRoot' })
    Assert-Equal 'PROMPTS_ROOT is reported as its own source' 'env' $rootRow[0].source
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# -- Machine keys --------------------------------------------------------------

Write-Host ''
Write-Host '-- Machine keys ------------------------------------------' -ForegroundColor Cyan

$box = New-ConfigSandbox
try {
    [void](Invoke-Config $box @('-Set', 'email=someone@example.com'))
    [void](Invoke-Config $box @('-Set', 'features.growth=true'))
    $text = Get-LocalConfigText $box
    Assert-Contains 'a feature flag is written top-level' $text '"growth": true'
    Assert-Contains 'and the earlier key is still there' $text 'someone@example.com'

    # A features.* write says an open shell keeps its menu; another key says nothing of the kind.
    $flagWrite = Invoke-Config $box @('-Set', 'features.communication=true')
    Assert-Equal 'a features.* write still exits 0' 0 $flagWrite.ExitCode
    Assert-Contains 'a features.* write notes that open shells keep their menu' $flagWrite.Output 'Open shells keep their current menu until they re-import'
    $plainWrite = Invoke-Config $box @('-Set', 'email=other@example.com')
    Assert-True 'a non-features key prints no shell note' ($plainWrite.Output -notlike '*Open shells keep*') $plainWrite.Output


    # Idempotence: the same write twice is the same bytes.
    $before = Get-LocalConfigText $box
    [void](Invoke-Config $box @('-Set', 'features.growth=true'))
    Assert-Equal 'a repeated -Set leaves the same bytes' $before (Get-LocalConfigText $box)

    # The byte contract.
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $box.Pkg 'config.local.json'))
    Assert-True 'no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
    Assert-True 'LF, never CRLF' (-not $raw.Contains("`r`n")) 'found a CR LF pair'
    Assert-True 'two-space indent, the same on either host' ($raw -match '(?m)^  "email"') $raw

    # -Unset removes the override and nothing else.
    [void](Invoke-Config $box @('-Unset', 'email'))
    $afterUnset = Get-LocalConfigText $box
    Assert-True 'the unset key is gone' ($afterUnset -notlike '*someone@example.com*') $afterUnset
    Assert-Contains 'its sibling stands' $afterUnset '"growth": true'

    # A second -Unset is not a failure: there is simply nothing to remove.
    $again = Invoke-Config $box @('-Unset', 'email')
    Assert-Equal 'unsetting what is not set exits 0' 0 $again.ExitCode
    Assert-Contains 'and says so' $again.Output 'nothing to remove'

    # A nav shortcut of your own, set by its path alone. It used to be stored
    # hidden and registered nowhere, with exit 0 and no word about either.
    #
    $mine = Invoke-Config $box @('-Set', 'aliases.Bowling.path=/somewhere/bowling')
    Assert-Equal 'a new alias is accepted' 0 $mine.ExitCode
    $aliasText = Get-LocalConfigText $box
    Assert-Contains 'the path is written' $aliasText '/somewhere/bowling'
    Assert-Contains 'and display is written true beside it, in the same write' $aliasText '"display": true'
    Assert-Contains 'the person is told the name answers after the module has loaded' $mine.Output 'not as the first command of a new shell'
    Assert-Contains 'and what does autoload' $mine.Output 'config.default.json is what autoloads'
    $shippedName = Invoke-Config $box @('-Set', 'aliases.Home.path=/somewhere/home')
    Assert-True 'a shipped name gets no such note: it autoloads' ($shippedName.Output -notlike '*not as the first command*') $shippedName.Output
    [void](Invoke-Config $box @('-Set', 'aliases.Bowling.display=false'))
    Assert-Contains 'display false is kept when set on purpose' (Get-LocalConfigText $box) '"display": false'

    # Several pairs in one call: -Set cannot be repeated, so this is the shape --
    # typed in a shell, where PowerShell splits the comma into an array. (Through
    # -File the same text arrives as ONE element; a batch there is the JSON form.)
    $typed = "& '$($box.Script)' -Set email=two@example.com,features.communication=true"
    $pairsOut = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    $pairs = @{ Output = $pairsOut; ExitCode = $LASTEXITCODE }
    Assert-Equal 'comma-separated pairs are one call' 0 $pairs.ExitCode
    $pairText = Get-LocalConfigText $box
    Assert-Contains 'the first pair landed' $pairText 'two@example.com'
    Assert-Contains 'and the second' $pairText '"communication": true'

    # A key -Set was not asked to touch keeps its exact bytes -- PowerShell 7's
    # ConvertFrom-Json otherwise reads an ISO-looking string as a [datetime] and
    # the writer re-serialises it in .NET's own culture-shaped format.
    #
    $localPath = Join-Path $box.Pkg 'config.local.json'
    $stamped = (Invoke-LockRetry 'read of a scratch file' { Get-Content $localPath -Raw }) | ConvertFrom-Json
    $stamped | Add-Member -NotePropertyName 'errorsAckedAt' -NotePropertyValue '2026-09-23T15:17:31' -Force
    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($localPath, (ConvertTo-Json $stamped -Depth 10)) }
    [void](Invoke-Config $box @('-Set', 'features.growth=true'))
    Assert-Contains 'an ISO date string it does not own is untouched by an unrelated -Set' `
        (Get-LocalConfigText $box) '"errorsAckedAt": "2026-09-23T15:17:31"'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# -- Org keys go to the hub ----------------------------------------------------

Write-Host ''
Write-Host '-- Org keys land in the hub ------------------------------' -ForegroundColor Cyan

$box = New-ConfigSandbox
try {
    Set-HubRoot $box

    # A slug nobody has declared is how a new org is added.
    $added = Invoke-Config $box @('-Set', 'spaces.acme.name=Acme Engineering')
    Assert-Equal 'adding an org exits 0' 0 $added.ExitCode
    Assert-True 'hub.json is created' (Test-Path (Join-Path $box.Hub 'hub.json'))
    $acme = Get-HubSpace $box 'acme'
    Assert-True 'the org is appended to the hub' ($null -ne $acme) (Get-HubText $box)
    Assert-Equal 'with the name that was set' 'Acme Engineering' $acme.name
    Assert-Equal 'and promptsFolder, which both loaders require' 'acme' $acme.promptsFolder
    Assert-Equal 'fail-closed: a new org starts local' 'local' $acme.status

    Assert-True 'nothing about the org reached config.local.json' `
        ((Get-LocalConfigText $box) -notlike '*Acme*') (Get-LocalConfigText $box)

    # Archiving is a value, never a deletion.
    [void](Invoke-Config $box @('-Set', 'spaces.acme.status=archive'))
    $acme2 = Get-HubSpace $box 'acme'
    Assert-Equal 'archiving sets the status' 'archive' $acme2.status
    Assert-Equal 'and the entry is still there' 'acme' $acme2.slug
    Assert-Equal 'the hub still declares exactly one org' 1 @((Get-HubText $box | ConvertFrom-Json).spaces).Count
    Assert-True 'and the file spells it spaces, never orgs' ($null -eq (Get-HubText $box | ConvertFrom-Json).PSObject.Properties['orgs'])

    # An org's lane names: four nested org fields the schema derives, written
    # into the hub entry like any other org field.
    [void](Invoke-Config $box @('-Set', 'spaces.acme.laneNames.codeReview=Waiting'))
    $acme3 = Get-HubSpace $box 'acme'
    Assert-Equal 'a lane name lands on the org, nested under laneNames' 'Waiting' $acme3.laneNames.codeReview
    $refusedLane = Invoke-Config $box @('-Set', 'spaces.acme.laneNames.planned=Someday')
    Assert-True 'a lane that is not one of the four is refused' ($refusedLane.ExitCode -ne 0) $refusedLane.Output

    # How do you want to work in this Space?: the Space's answer, written
    # into its hub entry like any other Space field -- what the Settings control
    # sends through PUT /api/config with -Hub. `team` is derived from an Azure
    # DevOps address and is never stored, so it is refused like any unknown value.
    $how = Invoke-Config $box @('-Set', 'spaces.acme.howIWork=agents', '-Hub')
    Assert-Equal '#424: spaces.<slug>.howIWork=agents -Hub exits 0' 0 $how.ExitCode
    Assert-Equal '#424: the answer lands on the Space''s hub entry' 'agents' (Get-HubSpace $box 'acme').howIWork
    Assert-True '#424: and nothing of it reached config.local.json' ((Get-LocalConfigText $box) -notlike '*howIWork*') (Get-LocalConfigText $box)
    foreach ($bad in @('team', 'crew')) {
        $refusedHow = Invoke-Config $box @('-Set', "spaces.acme.howIWork=$bad", '-Hub')
        Assert-Equal "#424: howIWork=$bad is a stated refusal (exit 2)" 2 $refusedHow.ExitCode
        Assert-True "#424: ...naming the answers a Space may store" ($refusedHow.Output -match 'alone' -and $refusedHow.Output -match 'agents') $refusedHow.Output
    }
    Assert-Equal '#424: a refusal leaves the answer as it was' 'agents' (Get-HubSpace $box 'acme').howIWork
    [void](Invoke-Config $box @('-Unset', 'spaces.acme.howIWork', '-Hub'))
    Assert-True '#424: -Unset takes the answer off the Space again' (-not (Get-HubSpace $box 'acme').PSObject.Properties['howIWork']) (Get-HubText $box)

    # The suggestion's switch: a Space-scoped feature flag (consts.json
    # features.spaceScoped), written onto the Space's hub entry as a boolean.
    $sugOff = Invoke-Config $box @('-Set', 'spaces.acme.features.suggestions=false', '-Hub')
    Assert-Equal 'spaces.<slug>.features.suggestions=false -Hub exits 0' 0 $sugOff.ExitCode
    $sugSpace = Get-HubSpace $box 'acme'
    Assert-True 'the switch lands on the Space''s features as a boolean false' ($sugSpace.features -and $sugSpace.features.suggestions -is [bool] -and -not $sugSpace.features.suggestions) (Get-HubText $box)
    Assert-True 'and nothing of it reached config.local.json' ((Get-LocalConfigText $box) -notlike '*suggestions*') (Get-LocalConfigText $box)
    [void](Invoke-Config $box @('-Unset', 'spaces.acme.features.suggestions', '-Hub'))

    # The first write of the Azure on-ramp. Setting a field on the
    # SHIPPED org must patch it -- not add an org called "test" (its slug then) with status
    # local, which merged over Example and switched ADO off.
    $onramp = New-ConfigSandbox
    try {
        Set-HubRoot $onramp
        $r = Invoke-Config $onramp @('-Set', 'spaces.azure-demo.org=https://dev.azure.com/SomeOrg')
        Assert-Equal '#6: setting a shipped org''s field exits 0' 0 $r.ExitCode
        Assert-True '#6: ...and does not announce a new local org' ($r.Output -notmatch 'new org') $r.Output
        $patch = Get-HubSpace $onramp 'azure-demo'
        Assert-Equal '#6: the hub entry carries the field that was set' 'https://dev.azure.com/SomeOrg' $patch.org
        Assert-Equal '#6: ...and the promptsFolder both loaders require, the shipped one' 'azure-demo' $patch.promptsFolder
        Assert-True '#6: ...and NO name or status of its own to merge over the shipped ones' `
            (-not $patch.PSObject.Properties['name'] -and -not $patch.PSObject.Properties['status']) (Get-HubText $onramp)
        $listed = (Invoke-Config $onramp @('-List', '-AsJson')).Output | ConvertFrom-Json
        $eff = @{}
        foreach ($row in @($listed.settings)) { $eff[$row.key] = $row.value }
        Assert-Equal '#6: the merged org keeps its shipped name' 'Azure demo' $eff['spaces.azure-demo.name']
        # The Azure demo ships LOCAL with no address, so a cold machine never
        # reads it as unreachable; the patch still says nothing of its own, so the
        # shipped status stands until Connect (an address implies active) says so.
        Assert-Equal '#6: ...and the shipped status, which the patch does not override' 'local' $eff['spaces.azure-demo.status']
        Assert-Equal '#6: ...with the new address' 'https://dev.azure.com/SomeOrg' $eff['spaces.azure-demo.org']
    }
    finally { Remove-Item $onramp.Root -Recurse -Force -ErrorAction SilentlyContinue }

    # A shipped org edited through the hub: appended by slug, not written into
    # the committed file.
    [void](Invoke-Config $box @('-Set', 'spaces.azure-demo.status=active'))
    Assert-Equal 'a second org joins the hub' 2 @((Get-HubText $box | ConvertFrom-Json).spaces).Count
    $shipped = (Invoke-LockRetry 'read of a scratch file' { Get-Content (Join-Path $box.Pkg 'config.default.json') -Raw }) | ConvertFrom-Json
    Assert-Equal 'config.default.json is untouched' 'local' (@($shipped.spaces | Where-Object { $_.slug -eq 'azure-demo' })[0].status)

    # The OLDER spelling is still typed (stage 3): it lands on the same
    # row, the file is written in the new spelling, and the new name is said.
    $aliased = Invoke-Config $box @('-Set', 'orgs.acme.orgType=engagement')
    Assert-Equal 'the old typed spelling still exits 0' 0 $aliased.ExitCode
    Assert-Contains 'and is told the new name once' $aliased.Output 'orgs.acme.orgType is spaces.acme.orgType now'
    Assert-Equal 'and the value landed on the Space' 'engagement' (Get-HubSpace $box 'acme').orgType

    # -Local sends the same edit to this machine's patch instead.
    [void](Invoke-Config $box @('-Set', 'spaces.azure-demo.status=archive', '-Local'))
    $local = Get-LocalConfigText $box | ConvertFrom-Json
    Assert-Equal 'with -Local the override is this machine''s' 'archive' $local.spaces.'azure-demo'.status
    Assert-True 'written as spaces, not orgs' ($null -eq $local.PSObject.Properties['orgs'])
    Assert-Equal 'and the hub keeps what it had' 'active' (Get-HubSpace $box 'azure-demo').status

    # A file that still carries the OLD spelling comes out in the new one after
    # any write, with its values intact -- and the typed key is still the old
    # vocabulary (activeOrg), which is stage 3's to rename.
    $oldSpelling = "{ `"promptsRoot`": `"$($box.Hub -replace '\\', '/')`", `"activeOrg`": `"test`", `"orgs`": { `"test`": { `"status`": `"archive`" } }, `"email`": `"old@example.com`" }"
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path (Join-Path $box.Pkg 'config.local.json') -Value $oldSpelling -Encoding UTF8 }
    [void](Invoke-Config $box @('-Set', 'email=new@example.com'))
    $migrated = Get-LocalConfigText $box | ConvertFrom-Json
    Assert-Equal 'the old activeOrg is now activeSpace' 'test' $migrated.activeSpace
    Assert-True 'and activeOrg is gone' ($null -eq $migrated.PSObject.Properties['activeOrg'])
    Assert-Equal 'the old orgs patch is now spaces' 'archive' $migrated.spaces.test.status
    Assert-True 'and orgs is gone' ($null -eq $migrated.PSObject.Properties['orgs'])
    Assert-Equal 'the value that was set landed' 'new@example.com' $migrated.email
    [void](Invoke-Config $box @('-Set', 'activeOrg=azure-demo'))
    $active = Get-LocalConfigText $box | ConvertFrom-Json
    Assert-Equal '-Set activeOrg=<slug> writes activeSpace' 'azure-demo' $active.activeSpace
    Assert-True 'and never activeOrg' ($null -eq $active.PSObject.Properties['activeOrg'])

    # The Azure demo's OLD slug is accepted, written as the new one, and
    # the new name is said once.
    $oldSlug = Invoke-Config $box @('-Set', 'activeSpace=test')
    Assert-Equal '#116: -Set activeSpace=test exits 0' 0 $oldSlug.ExitCode
    Assert-Equal '#116: ...and writes the new slug' 'azure-demo' (Get-LocalConfigText $box | ConvertFrom-Json).activeSpace
    Assert-Contains '#116: ...and says the new name' $oldSlug.Output "it is 'azure-demo' now"
    $oldField = Invoke-Config $box @('-Set', 'spaces.test.tenant=contoso')
    Assert-Equal '#116: -Set spaces.test.<field> exits 0' 0 $oldField.ExitCode
    Assert-Equal '#116: ...and lands on the azure-demo entry' 'contoso' (Get-HubSpace $box 'azure-demo').tenant
    Assert-True '#116: ...without a test entry beside it' ($null -eq (Get-HubSpace $box 'test')) (Get-HubText $box)

    # A hub written before the rename carries a nameless `test` patch: a write to the
    # new slug goes INTO that entry, so its promptsFolder -- where the cards are
    # -- stands, and no second entry appears.
    $legacy = New-ConfigSandbox
    try {
        Set-HubRoot $legacy
        Invoke-LockRetry 'write of a scratch file' { Set-Content -Path (Join-Path $legacy.Hub 'hub.json') -Value '{ "hub": 1, "spaces": [ { "slug": "test", "promptsFolder": "test", "org": "https://dev.azure.com/SomeOrg" } ] }' -Encoding UTF8 }
        $r = Invoke-Config $legacy @('-Set', 'spaces.azure-demo.status=active')
        Assert-Equal '#116: a write to azure-demo over a legacy test patch exits 0' 0 $r.ExitCode
        $entries = @((Get-HubText $legacy | ConvertFrom-Json).spaces)
        Assert-Equal '#116: ...the hub still has one entry' 1 $entries.Count
        Assert-Equal '#116: ...the legacy one, its promptsFolder intact' 'test' $entries[0].promptsFolder
        Assert-Equal '#116: ...carrying the new status' 'active' $entries[0].status
    }
    finally { Remove-Item $legacy.Root -Recurse -Force -ErrorAction SilentlyContinue }

    # The hub's own declarations need -Hub.
    $refusedHub = Invoke-Config $box @('-Set', 'folders.growth=learning')
    Assert-Equal 'a hub declaration without -Hub is refused' 2 $refusedHub.ExitCode
    Assert-Contains 'and says which switch it wants' $refusedHub.Output '-Hub'
    $withHub = Invoke-Config $box @('-Set', 'folders.growth=learning', '-Hub')
    Assert-Equal 'with -Hub it lands' 0 $withHub.ExitCode
    Assert-Equal 'in hub.json' 'learning' (Get-HubText $box | ConvertFrom-Json).folders.growth

    # A required org field cannot be removed, even with -Hub.
    $required = Invoke-Config $box @('-Unset', 'spaces.acme.promptsFolder', '-Hub')
    Assert-Equal 'unsetting a required org field is refused' 2 $required.ExitCode
    Assert-Contains 'and names the way to retire an org instead' $required.Output 'status=archive'

    # A non-required one may go.
    $optional = Invoke-Config $box @('-Unset', 'spaces.acme.name', '-Hub')
    Assert-Equal 'a non-required hub field unsets' 0 $optional.ExitCode
    Assert-True 'and is gone from the entry' `
        ($null -eq (Get-HubSpace $box 'acme').PSObject.Properties['name'])

    # A WHOLE Space: -Unset spaces.<slug> -Hub un-declares it, and without
    # -Hub this machine's patch for it goes. Neither touches the Space's folder.
    [void](Invoke-Config $box @('-Set', 'spaces.gone.name=Gone'))
    [void](Invoke-Config $box @('-Set', 'spaces.gone.status=archive', '-Local'))
    $goneCards = Join-Path $box.Hub 'gone/current'
    New-Item -ItemType Directory -Path $goneCards -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $goneCards '9-kept.prompt.md'), "# 9`n", (New-Object System.Text.UTF8Encoding($false)))
    $whole = Invoke-Config $box @('-Unset', 'spaces.gone', '-Hub')
    Assert-Equal '#167: -Unset spaces.<slug> -Hub exits 0' 0 $whole.ExitCode
    Assert-True '#167: ...the entry leaves hub.json' ($null -eq (Get-HubSpace $box 'gone')) (Get-HubText $box)
    Assert-True '#167: ...the other Spaces stand' ($null -ne (Get-HubSpace $box 'acme'))
    Assert-True '#167: ...and the folder and its card are not touched' (Test-Path (Join-Path $goneCards '9-kept.prompt.md'))
    Assert-Contains "#167: ...this machine's patch is a separate key" (Get-LocalConfigText $box) '"gone"'
    $patch = Invoke-Config $box @('-Unset', 'spaces.gone')
    Assert-Equal "#167: -Unset spaces.<slug> drops this machine's patch" 0 $patch.ExitCode
    Assert-True '#167: ...from config.local.json' ((Get-LocalConfigText $box) -notmatch '"gone"') (Get-LocalConfigText $box)
    $nobody = Invoke-Config $box @('-Unset', 'spaces.nobody', '-Hub')
    Assert-True '#167: a Space nobody declared is nothing to remove, not an error' ($nobody.ExitCode -eq 0 -and $nobody.Output -match 'nothing to remove') $nobody.Output
    # Out of the Azure demo first -- it is this sandbox's shipped active Space.
    [void](Invoke-Config $box @('-Set', 'activeSpace=acme'))
    $shippedOne = Invoke-Config $box @('-Unset', 'spaces.azure-demo', '-Hub')
    Assert-Equal '#167: a Space config.default.json ships is refused' 2 $shippedOne.ExitCode
    Assert-Contains '#167: ...with one sentence naming the file' $shippedOne.Output 'config.default.json ships'
    $here = Invoke-Config $box @('-Unset', 'spaces.acme', '-Hub')
    Assert-Equal '#167: the Space you are in is refused' 2 $here.ExitCode
    Assert-Contains '#167: ...switch first' $here.Output 'SwitchSpace'
    Assert-True '#167: ...and stays declared' ($null -ne (Get-HubSpace $box 'acme'))
    [void](Invoke-Config $box @('-Unset', 'activeSpace'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# -- Refusals ------------------------------------------------------------------

Write-Host ''
Write-Host '-- Refusals state the reason and exit 2 ------------------' -ForegroundColor Cyan

$box = New-ConfigSandbox
try {
    $teamKey = Invoke-Config $box @('-Set', 'commands=nope')
    Assert-Equal 'a key that lives only in config.default.json is refused' 2 $teamKey.ExitCode
    Assert-Contains 'and the sentence names that file' $teamKey.Output 'config.default.json, which this command never writes'

    $unknown = Invoke-Config $box @('-Set', 'nonsense=1')
    Assert-Equal 'an unknown key is refused' 2 $unknown.ExitCode
    Assert-Contains 'by name' $unknown.Output "Unknown setting 'nonsense'"

    $badBool = Invoke-Config $box @('-Set', 'features.growth=yes')
    Assert-Equal 'a value outside the type is refused' 2 $badBool.ExitCode
    Assert-Contains 'saying what the type is' $badBool.Output 'true or false'

    $badEnum = Invoke-Config $box @('-Set', 'storeSync=rsync')
    Assert-Equal 'a value outside an enum is refused' 2 $badEnum.ExitCode
    Assert-Contains 'listing the values it takes' $badEnum.Output 'git, none'

    $badOrg = Invoke-Config $box @('-Set', 'activeOrg=nowhere')
    Assert-Equal 'an unknown activeOrg is refused' 2 $badOrg.ExitCode
    Assert-Contains 'listing the Spaces this machine knows' $badOrg.Output 'activeSpace is one of: azure-demo'

    $badPair = Invoke-Config $box @('-Set', 'emailyou@example.com')
    Assert-Equal 'something that is not key=value is refused' 2 $badPair.ExitCode
    Assert-Contains 'showing the shape' $badPair.Output 'key=value'

    $noHub = Invoke-Config $box @('-Set', 'spaces.acme.status=archive')
    Assert-Equal 'an org edit with no hub is refused' 2 $noHub.ExitCode
    Assert-Contains 'and says to set promptsRoot first' $noHub.Output 'promptsRoot'

    Assert-True 'no file was written by any refusal' (-not (Test-Path (Join-Path $box.Pkg 'config.local.json')))

    # A refusal in the middle of a batch changes nothing, which is why every
    # pair is validated before the first write. The batch is the JSON form,
    # because that is the one a browser sends.
    $batch = Invoke-Config $box @('-Set', '{"email":"someone@example.com","features.growth":"maybe"}')
    Assert-Equal 'a batch with one bad pair is refused' 2 $batch.ExitCode
    Assert-True 'and the good pair was not written either' (-not (Test-Path (Join-Path $box.Pkg 'config.local.json')))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# -- The JSON object form, which is how the agent carries a batch ---------------

Write-Host ''
Write-Host '-- The JSON form the bridge carries ----------------------' -ForegroundColor Cyan

$box = New-ConfigSandbox
try {
    $json = '{"email":"someone@example.com","features.growth":true,"web.corsOrigins":["http://localhost:5174"]}'
    $result = Invoke-Config $box @('-Set', $json)
    Assert-Equal 'a JSON object of pairs is accepted' 0 $result.ExitCode
    $local = Get-LocalConfigText $box | ConvertFrom-Json
    Assert-Equal 'the string value lands' 'someone@example.com' $local.email
    Assert-Equal 'the boolean lands as a boolean' $true $local.features.growth
    Assert-Equal 'the array lands as an array' 'http://localhost:5174' (@($local.web.corsOrigins) -join ',')

    $unsetJson = Invoke-Config $box @('-Unset', '["email"]')
    Assert-Equal 'a JSON array of keys unsets' 0 $unsetJson.ExitCode
    Assert-True 'and the key is gone' ($null -eq (Get-LocalConfigText $box | ConvertFrom-Json).PSObject.Properties['email'])

    $schemaJson = Invoke-Config $box @('-Schema', '-AsJson')
    Assert-Equal '-Schema -AsJson exits 0' 0 $schemaJson.ExitCode
    $rows = $null
    try { $rows = $schemaJson.Output | ConvertFrom-Json } catch { $null = $_ }
    Assert-True '-Schema -AsJson parses' ($null -ne $rows) $schemaJson.Output
    if ($rows) {
        Assert-True 'and every row carries a help line' (@($rows | Where-Object { -not $_.help }).Count -eq 0)
        Assert-True 'and a scope' (@($rows | Where-Object { -not $_.scope }).Count -eq 0)
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# -- The orgs a person is offered: isDemoDismissed ------------------------------
# ONE table, two readers: Tests/test_offered_orgs.py runs the agent's copy of the
# rule over the same file.
Write-Host ''
Write-Host '-- Select-P20OfferedSpaces: a dismissed Example org is not offered --' -ForegroundColor Cyan
. (Join-Path $pkgRoot 'Scripts/Select-OfferedSpaces.ps1')
$offeredTable = (Get-Content (Join-Path $PSScriptRoot 'fixtures/offered-orgs/table.json') -Raw | ConvertFrom-Json).rows
foreach ($row in $offeredTable) {
    $org = [pscustomobject]@{ slug = 'test'; example = [bool]$row.example }
    $active = 'other'
    if ($row.active) { $active = 'test' }
    $got = Select-P20OfferedSpaces -Spaces @($org) -ActiveSpace $active -Dismissed ([bool]$row.dismissed)
    Assert-True $row.why ((@($got).Count -eq 1) -eq [bool]$row.offered) "got $(@($got).Count) org(s)"
}

# -- spaces.<slug>.projects: the field discovery writes (settings by workflow W2) --
Write-Host ''
Write-Host '-- spaces.<slug>.projects: two forms, one field --' -ForegroundColor Cyan
$box = New-ConfigSandbox
try {
    Set-HubRoot $box
    $r = Invoke-Config $box @('-Set', 'spaces.acme.projects=Alpha/alpha-repo; Beta', '-Hub')
    Assert-Equal 'the shorthand form is accepted' 0 $r.ExitCode $r.Output
    $acme = Get-HubSpace $box 'acme'
    Assert-Equal 'two projects landed' 2 @($acme.projects).Count
    Assert-Equal 'a name and its repo' 'alpha-repo' @($acme.projects)[0].repo
    Assert-Equal 'a name without a repo' 'Beta' @($acme.projects)[1].name
    Assert-True 'and no repo where none was given -- said as hasRepo false, which MyWork reads' ($null -eq @($acme.projects)[1].PSObject.Properties['repo'] -and @($acme.projects)[1].hasRepo -eq $false)
    $r2 = Invoke-Config $box @('-Set', 'spaces.acme.projects=[{"name":"Gamma","repo":"g","defaultBranch":"main","hasRepo":true,"colour":"teal"}]', '-Hub')
    Assert-Equal 'the JSON form is accepted' 0 $r2.ExitCode $r2.Output
    Assert-Equal 'and replaces the list' 'Gamma' @((Get-HubSpace $box 'acme').projects)[0].name
    Assert-Equal 'keeping every key the entry carried, known or not' 'teal' @((Get-HubSpace $box 'acme').projects)[0].colour
    $r3 = Invoke-Config $box @('-Set', 'spaces.acme.projects=/nameless', '-Hub')
    Assert-Equal 'a project with no name is refused' 2 $r3.ExitCode $r3.Output
    Assert-Contains 'and the refusal names the shape' $r3.Output 'Name/repo'
    $r4 = Invoke-Config $box @('-Set', 'spaces.acme.projects=', '-Hub')
    Assert-Equal 'an empty value clears the list' 0 $r4.ExitCode $r4.Output
    Assert-Equal 'to nothing' 0 @((Get-HubSpace $box 'acme').projects).Count
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# SwitchSpace Status offers what the rule says, and the switch is the Config verb's.
$box = New-ConfigSandbox
try {
    $switch = Join-Path $box.Pkg 'Scripts/Switch-Mode.ps1'
    # With no module loaded, SwitchSpace reads the Spaces from the package's own
    # config: give the sandbox's a second org, and make it the active one.
    $defaultPath = Join-Path $box.Pkg 'config.default.json'
    $shipped = (Invoke-LockRetry 'read of a scratch file' { Get-Content $defaultPath -Raw }) | ConvertFrom-Json
    $shipped.spaces = @($shipped.spaces) + @([pscustomobject]@{ slug = 'other'; name = 'Other'; status = 'local'; promptsFolder = 'other' })
    $shipped.activeSpace = 'other'
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $defaultPath -Value ($shipped | ConvertTo-Json -Depth 20) -Encoding utf8 }
    $before = & pwsh -NoProfile -File $switch 'Status' 2>&1 | Out-String
    Assert-True 'SwitchSpace Status offers the Azure demo until it is dismissed' ($before -match '(?m)^\s+azure-demo\s+Azure demo') $before
    $set = Invoke-Config $box @('-Set', 'isDemoDismissed=true')
    Assert-Equal 'Config -Set isDemoDismissed=true exits 0' 0 $set.ExitCode
    $after = & pwsh -NoProfile -File $switch 'Status' 2>&1 | Out-String
    Assert-True 'and then it is not offered' ($after -notmatch '(?m)^\s+azure-demo\s+Azure demo') $after
    Assert-True 'while the org you are in still is' ($after -match '->\s*other') $after
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $box.Root -Recurse -Force -ErrorAction SilentlyContinue }

# SwitchSpace <slug> typed as a verb lands in the file. From 40e3112 (stage 2)
# the switch set the OLD name, activeOrg, and ConvertTo-P20SpaceSpelling let the activeSpace
# the file already had win -- so on every machine whose file said activeSpace the verb printed
# "Switched" and wrote nothing. The one suite that drove Switch-Mode.ps1 ran it with Status and
# never read the file back. This one is a SCRATCH PACKAGE (the switch writes the package's own
# config.local.json, and the Spaces it knows are the loaded module's), imported in a fresh shell
# whose PSModulePath is that package alone, the verb typed, the file read back.
$switchPkg = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-switch-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$switchHub = Join-Path $switchPkg 'hub'
New-Item -ItemType Directory -Path $switchPkg, $switchHub -Force | Out-Null
try {
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Invoke-LockRetry "scratch copy of $file" { Copy-Item (Join-Path $pkgRoot $file) $switchPkg -Force } }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $switchPkg -Recurse -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Config')  $switchPkg -Recurse -Force }
    $defaultPath = Join-Path $switchPkg 'config.default.json'
    $shipped = (Invoke-LockRetry 'read of a scratch file' { Get-Content $defaultPath -Raw }) | ConvertFrom-Json
    $shipped.spaces = @($shipped.spaces) + @([pscustomobject]@{ slug = 'other'; name = 'Other'; status = 'local'; promptsFolder = 'other' })
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $defaultPath -Value ($shipped | ConvertTo-Json -Depth 20) -Encoding utf8 }
    $prefix = $shipped.commandPrefix
    $localPath = Join-Path $switchPkg 'config.local.json'
    $hubPath = $switchHub -replace '\\', '/'
    $module = (Join-Path $switchPkg 'utilities.psm1') -replace "'", "''"
    $typed = "`$env:PSModulePath = '$($switchPkg -replace "'", "''")'; `$env:PROMPTS_ROOT = '$hubPath'; " +
        "Import-Module '$module' -Force -DisableNameChecking 3>`$null 6>`$null; ${prefix}SwitchSpace other"

    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value "{ `"promptsRoot`": `"$hubPath`", `"quietStart`": true, `"activeSpace`": `"test`", `"email`": `"kept@example.com`" }" -Encoding UTF8 }
    $out = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    Assert-True "${prefix}SwitchSpace other, typed, says it switched" ($out -match 'Switched to Other') $out
    $written = (Invoke-LockRetry 'read of a scratch file' { Get-Content $localPath -Raw }) | ConvertFrom-Json
    Assert-Equal 'and the file now says activeSpace: other' 'other' $written.activeSpace
    Assert-True 'with no activeOrg beside it' (-not $written.PSObject.Properties['activeOrg'])
    Assert-Equal 'and the machine keys it carried are kept' 'kept@example.com' $written.email

    # A file still in the old spelling comes out in the new one, saying the new Space.
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value "{ `"promptsRoot`": `"$hubPath`", `"quietStart`": true, `"activeOrg`": `"test`" }" -Encoding UTF8 }
    $out2 = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    $written2 = (Invoke-LockRetry 'read of a scratch file' { Get-Content $localPath -Raw }) | ConvertFrom-Json
    Assert-Equal 'an activeOrg file is written as activeSpace, with the new Space' 'other' $written2.activeSpace
    Assert-True 'and activeOrg is gone' (-not $written2.PSObject.Properties['activeOrg'])
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $switchPkg -Recurse -Force -ErrorAction SilentlyContinue }

# A Space switched from ANOTHER shell reaches an open one. The module read config once at
# import, so `tkEnv`, `tkStatus` and `tkNewPrompt -Title` in a shell opened before a switch kept
# the Space it imported with -- and NewPrompt filed the card into the old Space's folder. The GUI's
# switch is exactly this shape: a child pwsh writes activeSpace, the user's shell is already open.
# One scratch package, one shell that imports, a SECOND shell that writes activeSpace through
# Config -Set (the one writer), and the first shell types the verbs again, in the same process.
$staleCfgPkg = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-stale-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$staleCfgHub = Join-Path $staleCfgPkg 'hub'
New-Item -ItemType Directory -Path $staleCfgPkg, $staleCfgHub -Force | Out-Null
try {
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Invoke-LockRetry "scratch copy of $file" { Copy-Item (Join-Path $pkgRoot $file) $staleCfgPkg -Force } }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $staleCfgPkg -Recurse -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Config')  $staleCfgPkg -Recurse -Force }
    $defaultPath = Join-Path $staleCfgPkg 'config.default.json'
    $shipped = (Invoke-LockRetry 'read of a scratch file' { Get-Content $defaultPath -Raw }) | ConvertFrom-Json
    $shipped.spaces = @($shipped.spaces) + @(
        [pscustomobject]@{ slug = 'alpha'; name = 'Alpha'; status = 'local'; promptsFolder = 'alpha' },
        [pscustomobject]@{ slug = 'beta'; name = 'Beta'; status = 'local'; promptsFolder = 'beta' })
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $defaultPath -Value ($shipped | ConvertTo-Json -Depth 20) -Encoding utf8 }
    $prefix = $shipped.commandPrefix
    $localPath = Join-Path $staleCfgPkg 'config.local.json'
    $hubPath = $staleCfgHub -replace '\\', '/'
    $pkgQ = $staleCfgPkg -replace "'", "''"
    $module = (Join-Path $staleCfgPkg 'utilities.psm1') -replace "'", "''"
    $alphaFile = "{ `"promptsRoot`": `"$hubPath`", `"quietStart`": true, `"activeSpace`": `"alpha`" }"
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value $alphaFile -Encoding UTF8 }
    $pre = "`$env:PSModulePath = '$pkgQ'; `$env:PROMPTS_ROOT = '$hubPath'; Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue; " +
        "Import-Module '$module' -Force -DisableNameChecking 3>`$null 6>`$null; "
    # The second shell is the verb typed in a child that imports the same package.
    $second = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pre + "${prefix}Config -Set activeSpace=beta | Out-Null"))
    $typed = $pre +
        "'A1=' + `$global:P20Config.ActiveSpace; ${prefix}NewPrompt -Title 'First card' -Type Task -Id K7M2 | Out-Null; " +
        "& pwsh -NoProfile -EncodedCommand $second; " +
        "'ENV-BEGIN'; ${prefix}Env; 'ENV-END'; " +
        "'A2=' + `$global:P20Config.ActiveSpace; " +
        "${prefix}NewPrompt -Title 'Second card' -Type Task -Id W3X7 | Out-Null; " +
        "'ST-BEGIN'; ${prefix}Status; 'ST-END'; " +
        "'A3=' + `$global:P20Config.ActiveSpace"
    $out = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    Assert-True 'the shell imports with the Space the file names' ($out -match 'A1=alpha') $out
    Assert-True 'a verb typed after another shell switched says the Space changed, once' ([regex]::Matches($out, 'Space changed to beta since this shell loaded \(it was alpha\)').Count -eq 1) $out
    Assert-True 'and the process now acts on beta' ($out -match 'A2=beta' -and $out -match 'A3=beta') $out
    $envBlock = [regex]::Match($out, '(?s)ENV-BEGIN(.*)ENV-END').Groups[1].Value
    Assert-True "${prefix}Env in the same process reports the new Space" ($envBlock -match 'Beta') $envBlock
    Assert-True 'the first card landed in the Space the shell had' (@(Get-ChildItem (Join-Path $staleCfgHub 'alpha') -Recurse -Filter '*K7M2*' -ErrorAction SilentlyContinue).Count -eq 1)
    Assert-True 'the second card landed in the NEW Space, not the old one' (@(Get-ChildItem (Join-Path $staleCfgHub 'beta') -Recurse -Filter '*W3X7*' -ErrorAction SilentlyContinue).Count -eq 1 -and @(Get-ChildItem (Join-Path $staleCfgHub 'alpha') -Recurse -Filter '*W3X7*' -ErrorAction SilentlyContinue).Count -eq 0)
    $stBlock = [regex]::Match($out, '(?s)ST-BEGIN(.*)ST-END').Groups[1].Value
    Assert-True "${prefix}Status lists the new Space's card and not the old one's" ($stBlock -match 'W3X7' -and $stBlock -notmatch 'K7M2') $stBlock

    # P20_ACTIVE_SPACE keeps its precedence: it names the Space for the process, and a file change does not move it.
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value $alphaFile -Encoding UTF8 }
    $pre2 = $pre.Replace('Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue;', "`$env:P20_ACTIVE_SPACE = 'alpha';")
    $second2 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pre + "${prefix}Config -Set activeSpace=beta | Out-Null"))
    $typed2 = $pre2 + "'B1=' + `$global:P20Config.ActiveSpace; & pwsh -NoProfile -EncodedCommand $second2; " +
        "${prefix}Status | Out-Null; 'B2=' + `$global:P20Config.ActiveSpace"
    $out2 = & pwsh -NoProfile -Command $typed2 2>&1 | Out-String
    Assert-True 'with P20_ACTIVE_SPACE set the override still wins after the file changed' ($out2 -match 'B1=alpha' -and $out2 -match 'B2=alpha') $out2

    # A flag flipped in another shell reaches the open one too: no stale verb list.
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value $alphaFile -Encoding UTF8 }
    $flagSecond = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pre + "${prefix}Config -Set features.organize=true | Out-Null"))
    $typed3 = $pre + "'C1=' + [bool](Get-Command ${prefix}NewReminder -ErrorAction SilentlyContinue); " +
        "& pwsh -NoProfile -EncodedCommand $flagSecond; ${prefix}Status | Out-Null; " +
        "'C2=' + [bool](Get-Command ${prefix}NewReminder -ErrorAction SilentlyContinue)"
    $out3 = & pwsh -NoProfile -Command $typed3 2>&1 | Out-String
    Assert-True 'a module flag flipped elsewhere is seen by the next verb' ($out3 -match 'C1=False' -and $out3 -match 'C2=True' -and $out3 -match 'Config changed since this shell loaded') $out3
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $staleCfgPkg -Recurse -Force -ErrorAction SilentlyContinue }

# An override exported AFTER the import reaches the open shell the same way (card H3QY). A profile
# that loads the toolkit before PROMPTS_ROOT is set, or a walk that points an open shell at a
# scratch hub, left every verb on the import-time hub while Env's "Your hub" row, which reads the
# environment fresh, named the other one -- two hubs in one report, and the card filed into the
# first. The two overrides are part of the stamp the re-import compares, so Env's Hub check and
# its surface row read one re-imported state, and the verb typed next acts on it. One shell: it
# imports against hub-a, exports PROMPTS_ROOT at hub-b, types Env and NewPrompt, then names a
# Space through the environment and types Status and NewPrompt again.
$envOvPkg = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-envov-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$envOvHubA = Join-Path $envOvPkg 'hub-a'
$envOvHubB = Join-Path $envOvPkg 'hub-b'
New-Item -ItemType Directory -Path $envOvPkg, $envOvHubA, $envOvHubB -Force | Out-Null
try {
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Invoke-LockRetry "scratch copy of $file" { Copy-Item (Join-Path $pkgRoot $file) $envOvPkg -Force } }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $envOvPkg -Recurse -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Config')  $envOvPkg -Recurse -Force }
    $defaultPath = Join-Path $envOvPkg 'config.default.json'
    $shipped = (Invoke-LockRetry 'read of a scratch file' { Get-Content $defaultPath -Raw }) | ConvertFrom-Json
    $shipped.spaces = @($shipped.spaces) + @(
        [pscustomobject]@{ slug = 'alpha'; name = 'Alpha'; status = 'local'; promptsFolder = 'alpha' },
        [pscustomobject]@{ slug = 'beta'; name = 'Beta'; status = 'local'; promptsFolder = 'beta' })
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $defaultPath -Value ($shipped | ConvertTo-Json -Depth 20) -Encoding utf8 }
    $prefix = $shipped.commandPrefix
    $localPath = Join-Path $envOvPkg 'config.local.json'
    $hubAPath = $envOvHubA -replace '\\', '/'
    $pkgQ = $envOvPkg -replace "'", "''"
    $hubBQ = $envOvHubB -replace "'", "''"
    $module = (Join-Path $envOvPkg 'utilities.psm1') -replace "'", "''"
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $localPath -Value "{ `"promptsRoot`": `"$hubAPath`", `"quietStart`": true, `"activeSpace`": `"alpha`" }" -Encoding UTF8 }
    $typed = "`$env:PSModulePath = '$pkgQ'; Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue; Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue; " +
        "Import-Module '$module' -Force -DisableNameChecking 3>`$null 6>`$null; " +
        "'H1=' + `$global:P20Config.PromptsRoot; " +
        "`$env:PROMPTS_ROOT = '$hubBQ'; " +
        "'ENV-BEGIN'; ${prefix}Env; 'ENV-END'; " +
        "'H2=' + `$global:P20Config.PromptsRoot; " +
        "${prefix}NewPrompt -Title 'Scratch card' -Type Task -Id K7M2 | Out-Null; " +
        "`$env:P20_ACTIVE_SPACE = 'beta'; ${prefix}Status | Out-Null; " +
        "'A3=' + `$global:P20Config.ActiveSpace; " +
        "${prefix}NewPrompt -Title 'Beta card' -Type Task -Id W3X7 | Out-Null"
    $out = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    Assert-True 'the shell imports with the hub the file names' ($out -match '(?m)^H1=.*hub-a\s*$') $out
    Assert-True 'a verb typed after PROMPTS_ROOT was exported says the hub changed, once' ([regex]::Matches($out, 'Hub changed to .*hub-b since this shell loaded \(it was .*hub-a\)').Count -eq 1) $out
    Assert-True 'and the process now acts on the hub the environment names' ($out -match '(?m)^H2=.*hub-b\s*$') $out
    $envBlock = [regex]::Match($out, '(?s)ENV-BEGIN(.*)ENV-END').Groups[1].Value
    Assert-True "${prefix}Env's Hub check names the hub the environment names" ($envBlock -match '(?m)^\s*\[ok\]\s+Hub\s+.*hub-b\s*$') $envBlock
    Assert-True 'and not the one the shell imported with' ($envBlock -notmatch '(?m)^\s*\[(ok|X|--)\]\s+Hub\s+.*hub-a') $envBlock
    Assert-True "${prefix}Env's Your hub row names the same hub -- one report, one hub" ($envBlock -match '(?m)^\s*Your hub\s+on -- .*hub-b\s*$') $envBlock
    Assert-True 'the card filed after the export landed in the hub the environment names' (@(Get-ChildItem (Join-Path $envOvHubB 'alpha') -Recurse -Filter '*K7M2*' -ErrorAction SilentlyContinue).Count -eq 1 -and @(Get-ChildItem $envOvHubA -Recurse -Filter '*K7M2*' -ErrorAction SilentlyContinue).Count -eq 0)
    Assert-True 'a Space named through the environment after the import is the next verb''s Space' ($out -match 'Space changed to beta since this shell loaded \(it was alpha\)' -and $out -match '(?m)^A3=beta\s*$') $out
    Assert-True 'and the card filed after that landed in it' (@(Get-ChildItem (Join-Path $envOvHubB 'beta') -Recurse -Filter '*W3X7*' -ErrorAction SilentlyContinue).Count -eq 1 -and @(Get-ChildItem (Join-Path $envOvHubB 'alpha') -Recurse -Filter '*W3X7*' -ErrorAction SilentlyContinue).Count -eq 0)
}
catch {
    Assert-True 'the override cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $envOvPkg -Recurse -Force -ErrorAction SilentlyContinue }


# A config.local.json that will not parse says so, once. The module's loader always did;
# six other readers (the prefix, the hub root, the agentic extension path, the help ports, the menu
# scores, the recent-errors count) swallowed the same failure, so a typo in a hand-edited file turned
# the machine back into an unconfigured one with no hint why. One helper, Write-P20ConfigParseWarning,
# says it once per process per file; the readers keep their fallback to the shipped defaults.
$badCfgPkg = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-malformed-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $badCfgPkg -Force | Out-Null
try {
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Invoke-LockRetry "scratch copy of $file" { Copy-Item (Join-Path $pkgRoot $file) $badCfgPkg -Force } }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $badCfgPkg -Recurse -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Config')  $badCfgPkg -Recurse -Force }
    $badLocal = Join-Path $badCfgPkg 'config.local.json'
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path $badLocal -Value '{ "commandPrefix": "zz", "quietStart": ' -Encoding UTF8 }
    $badQ = $badCfgPkg -replace "'", "''"
    $shippedPrefix = ((Get-Content (Join-Path $badCfgPkg 'config.default.json') -Raw) | ConvertFrom-Json).commandPrefix

    # Standalone: the scripts dot-sourced with no module, each reader called, one of them twice.
    $standalone = "`$env:PSModulePath = '$badQ'; Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue; " +
        ". '$badQ/Scripts/Resolve-CliPrefix.ps1'; . '$badQ/Scripts/Resolve-AgenticPrompt.ps1'; . '$badQ/Scripts/Show-ConfigHelp.ps1'; " +
        "`$seen = @(); " +
        "`$a = Resolve-P20ConfigPrefix -PackageRoot '$badQ' 3>&1; `$b = Resolve-P20ConfigPrefix -PackageRoot '$badQ' 3>&1; " +
        "`$c = Get-P20AgenticExtensionPath -PackageRoot '$badQ' 3>&1; `$d = Get-P20PromptsRoot -PackageRoot '$badQ' 3>&1; " +
        "`$e = Get-P20HelpPorts -RepoRoot '$badQ' 3>&1; " +
        "`$all = @(`$a) + @(`$b) + @(`$c) + @(`$d) + @(`$e); " +
        "`$warns = @(`$all | Where-Object { `$_ -is [System.Management.Automation.WarningRecord] }); " +
        "'WARN-COUNT=' + `$warns.Count; 'WARN-TEXT=' + `$warns[0].Message; " +
        "'PREFIX=' + (@(`$b | Where-Object { `$_ -is [string] }) | Select-Object -Last 1)"
    $outS = & pwsh -NoProfile -Command $standalone 2>&1 | Out-String
    Assert-True 'a malformed config.local.json read by five standalone readers warns once, not five times' ($outS -match 'WARN-COUNT=1\b') $outS
    Assert-True 'the warning names the file and carries the parse error' ($outS -match 'WARN-TEXT=Failed to parse config\.local\.json \(.+\)\. Using defaults only') $outS
    Assert-True 'and the prefix reader still falls back to the shipped default' ($outS -match ("PREFIX=" + [regex]::Escape($shippedPrefix) + "\b")) $outS

    # Through the module: the loader warns at import, a verb that reads the file again adds nothing.
    $module = (Join-Path $badCfgPkg 'utilities.psm1') -replace "'", "''"
    $typed = "`$env:PSModulePath = '$badQ'; `$w = Import-Module '$module' -Force -DisableNameChecking 3>&1; " +
        "'IMPORT-WARN=' + @(`$w | Where-Object { `$_ -is [System.Management.Automation.WarningRecord] -and `$_.Message -match 'Failed to parse config.local.json' }).Count; " +
        "`$l = & { ${shippedPrefix}Menu } 3>&1 6>&1; " +
        "'LATER-WARN=' + @(`$l | Where-Object { `$_ -is [System.Management.Automation.WarningRecord] -and `$_.Message -match 'Failed to parse' }).Count"
    $outM = & pwsh -NoProfile -Command $typed 2>&1 | Out-String
    Assert-True 'the module warns once at import' ($outM -match 'IMPORT-WARN=1\b') $outM
    Assert-True 'and a later verb that reads the file again says nothing more' ($outM -match 'LATER-WARN=0\b') $outM
}
catch {
    Assert-True 'the malformed-config cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $badCfgPkg -Recurse -Force -ErrorAction SilentlyContinue }

# Every reader of config.local.json, not only the first six. The first six it named got one
# warning; the tree has more, and a new one added quietly would swallow the failure again. So a SCAN:
# every ConvertFrom-Json whose operand comes from config.local.json (a string naming it, a variable
# assigned from one, a function parameter the file feeds it to) has to sit in a try whose catch says so
# -- through Write-P20ConfigParseWarning, or as a stated refusal (Write-CliError) the way Config does.
# The scan is an AST walk, so a comment or a string that mentions the file is not a reader.
function Get-ConfigLocalReaderScan {
    param([string]$Root)
    $result = @{ Readers = 0; Gaps = @(); Writers = @() }
    $files = @()
    foreach ($dir in @('Scripts', 'Config', 'Prompt20Toolkit', 'agent/ado')) {
        $d = Join-Path $Root $dir
        if (Test-Path $d) { $files += @(Get-ChildItem -Path $d -Filter '*.ps1' -File) }
    }
    foreach ($top in @('utilities.psm1')) { if (Test-Path (Join-Path $Root $top)) { $files += @(Get-Item (Join-Path $Root $top)) } }
    foreach ($f in $files) {
        if ($f.Name -eq 'Write-ConfigParseWarning.ps1') { continue }
        $text = [System.IO.File]::ReadAllText($f.FullName)
        if ($text -notmatch 'config\.local') { continue }
        $tokens = $null; $perr = $null
        $tree = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$perr)
        $scopeOf = { param($n) $f = $n.Parent; while ($f -and $f -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $f = $f.Parent }; if ($f) { return $f.Name } else { return '' } }
        $varsIn = { param($node) @($node.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath.ToLowerInvariant() }) }
        # Variables that carry config.local.json's path, to a fixed point.
        $tainted = @{}
        do {
            $before = $tainted.Count
            foreach ($as in @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
                $lhs = $as.Left
                if ($lhs -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                $rhsText = $as.Right.Extent.Text
                # A PATH carries the taint; what was read out of the file does not (a parsed object
                # is not a place to read from), so a read of any kind ends the chain.
                $isRead = @($as.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^(ConvertFrom-Json|Get-Content|Read-|ConvertTo-)' }, $true)).Count -gt 0
                if ($isRead) { continue }
                if ($lhs.VariablePath.UserPath -eq 'null') { continue }
                # The file's name closing a quoted string is a path; a sentence that mentions it is not.
                $hit = ($rhsText -match 'config\.local\.json[''"]')
                $scope = (& $scopeOf $as)
                if (-not $hit) { foreach ($v in (& $varsIn $as.Right)) { if ($tainted.ContainsKey($scope + '|' + $v) -or $tainted.ContainsKey('|' + $v)) { $hit = $true } } }
                if ($hit) { $tainted[$scope + '|' + $lhs.VariablePath.UserPath.ToLowerInvariant()] = $true }
            }
            foreach ($fe in @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true))) {
                $hit = ($fe.Condition.Extent.Text -match 'config\.local\.json[''"]')
                $scope = (& $scopeOf $fe)
                if (-not $hit) { foreach ($v in (& $varsIn $fe.Condition)) { if ($tainted.ContainsKey($scope + '|' + $v) -or $tainted.ContainsKey('|' + $v)) { $hit = $true } } }
                if ($hit) { $tainted[$scope + '|' + $fe.Variable.VariablePath.UserPath.ToLowerInvariant()] = $true }
            }
        } while ($tainted.Count -ne $before)
        # Taint is per function (a name reused in another function is another variable); script scope is seen by all.
        $isLocalText = {
            param($t, $scope)
            if ($t -match 'config\.local') { return $true }
            foreach ($k in $tainted.Keys) {
                $bar = $k.IndexOf('|')
                if ($bar -ne 0 -and $k.Substring(0, $bar) -ne $scope) { continue }
                if ($t -match ('\$' + [regex]::Escape($k.Substring($bar + 1)) + '\b')) { return $true }
            }
            return $false
        }
        foreach ($cmd in @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'ConvertFrom-Json' }, $true))) {
            # The statement the call belongs to: its pipeline's outermost statement.
            $stmt = $cmd
            while ($stmt.Parent -and -not ($stmt.Parent -is [System.Management.Automation.Language.StatementBlockAst] -or $stmt.Parent -is [System.Management.Automation.Language.NamedBlockAst])) { $stmt = $stmt.Parent }
            $local = (& $isLocalText $stmt.Extent.Text (& $scopeOf $cmd))
            if (-not $local) {
                # A function parameter, fed config.local.json's path by a call elsewhere in the file.
                $fn = $cmd.Parent
                while ($fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                $params = @()
                if ($fn -and $fn.Parameters) { $params = @($fn.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath.ToLowerInvariant() }) }
                elseif ($fn -and $fn.Body.ParamBlock) { $params = @($fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath.ToLowerInvariant() }) }
                $usesParam = $false
                foreach ($v in (& $varsIn $stmt)) { if ($params -contains $v) { $usesParam = $true } }
                if ($usesParam) {
                    foreach ($call in @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $fn.Name }, $true))) {
                        if (& $isLocalText $call.Extent.Text (& $scopeOf $call)) { $local = $true }
                    }
                }
            }
            if (-not $local) { continue }
            $result.Readers++
            $ok = $false
            $node = $cmd
            while ($node.Parent) {
                $parent = $node.Parent
                if ($parent -is [System.Management.Automation.Language.TryStatementAst] -and [object]::ReferenceEquals($parent.Body, $node)) {
                    # A CALL in the catch (a mention in a comment or in Get-Command is not one).
                    foreach ($cc in @($parent.CatchClauses)) {
                        $says = @($cc.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Write-P20ConfigParseWarning', 'Write-CliError') }, $true))
                        if ($says.Count -gt 0) { $ok = $true }
                    }
                }
                $node = $parent
            }
            if (-not $ok) {
                $rel = $f.FullName.Substring($Root.TrimEnd('\', '/').Length).TrimStart('\', '/') -replace '\\', '/'
                $result.Gaps += ($rel + ':' + $cmd.Extent.StartLineNumber)
            }
        }
        # WRITERS. config.local.json has one writer, Config's (Write-ConfigJson in
        # Scripts/Write-ConfigJson.ps1: no BOM, LF, atomic). Anything else that puts bytes
        # into the file -- Set-Content, Add-Content, Out-File, Tee-Object, a [System.IO.File]
        # write, a > redirection -- is a second writer, and is named by file and line.
        $writeNodes = @($tree.FindAll({ param($n)
                    ($n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Set-Content', 'Add-Content', 'Out-File', 'Tee-Object')) -or
                    ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -match '^(WriteAllText|WriteAllBytes|WriteAllLines|AppendAllText|AppendAllLines)$') -or
                    ($n -is [System.Management.Automation.Language.FileRedirectionAst])
                }, $true))
        foreach ($w in $writeNodes) {
            # The write's TARGET only -- what it writes is not where it writes: the path argument
            # (-Path / -LiteralPath / -FilePath, else the first positional), the call's first
            # argument, or the redirection's location.
            $target = ''
            if ($w -is [System.Management.Automation.Language.FileRedirectionAst]) { $target = $w.Location.Extent.Text }
            elseif ($w -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                if ($w.Arguments -and $w.Arguments.Count -gt 0) { $target = $w.Arguments[0].Extent.Text }
            }
            else {
                $els = @($w.CommandElements)
                for ($i = 1; $i -lt $els.Count; $i++) {
                    $el = $els[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if ($el.ParameterName -match '^(Path|LiteralPath|FilePath|PSPath)$') {
                            if ($el.Argument) { $target = $el.Argument.Extent.Text }
                            elseif ($i + 1 -lt $els.Count) { $target = $els[$i + 1].Extent.Text }
                            break
                        }
                        # A switch or a named value: step over the value it takes.
                        if (-not $el.Argument -and $i + 1 -lt $els.Count -and $els[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -notmatch '^(Force|NoNewline|Append|NoClobber|PassThru|WhatIf|Confirm)$') { $i++ }
                        continue
                    }
                    if (-not $target) { $target = $el.Extent.Text; break }
                }
            }
            if (-not $target) { continue }
            if (-not (& $isLocalText $target (& $scopeOf $w))) { continue }
            $rel = $f.FullName.Substring($Root.TrimEnd('\', '/').Length).TrimStart('\', '/') -replace '\\', '/'
            $result.Writers += ($rel + ':' + $w.Extent.StartLineNumber)
        }
    }
    return $result
}

$scan = Get-ConfigLocalReaderScan -Root $pkgRoot
Assert-True ('the tree scan finds the readers of config.local.json (' + $scan.Readers + ')') ($scan.Readers -ge 8) 'the scan went blind: it should see at least the loader, the prefix, hub root, agentic path, help ports, menu scores, recent errors and the agent port'
Assert-True 'every reader of config.local.json says so when the file will not parse' ($scan.Gaps.Count -eq 0) ('no Write-P20ConfigParseWarning (or stated refusal) in the catch at: ' + ($scan.Gaps -join ', '))
Assert-True 'nothing but Config''s writer (Write-ConfigJson) writes config.local.json -- utilities.psm1, Scripts/, Config/' ($scan.Writers.Count -eq 0) ('a second writer of config.local.json at: ' + ($scan.Writers -join ', '))

# The scan is only worth having if it can fail: a scratch tree with one unrouted reader and one routed.
$scanProbe = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-scan-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $scanProbe 'Scripts') -Force | Out-Null
try {
    $probeSrc = @'
$p = Join-Path $root 'config.local.json'
try { $a = Get-Content $p -Raw | ConvertFrom-Json } catch { $a = $null }
try { $b = Get-Content $p -Raw | ConvertFrom-Json } catch { $null = Write-P20ConfigParseWarning -Path $p -Message $_.Exception.Message }
$c = Get-Content (Join-Path $root 'config.default.json') -Raw | ConvertFrom-Json
$a | ConvertTo-Json | Set-Content $p -Encoding UTF8
[System.IO.File]::WriteAllText($p, '{}')
Write-ConfigJson -Path $p -Value $a
$c | ConvertTo-Json | Set-Content (Join-Path $root 'config.default.json')
'@
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path (Join-Path $scanProbe 'Scripts/Probe.ps1') -Value $probeSrc -Encoding ASCII }
    $probeScan = Get-ConfigLocalReaderScan -Root $scanProbe
    Assert-True 'the scan counts both readers of config.local.json in a probe, and not the default file' ($probeScan.Readers -eq 2) ('readers=' + $probeScan.Readers)
    Assert-True 'and names only the one that swallows the failure, with its line' ($probeScan.Gaps.Count -eq 1 -and $probeScan.Gaps[0] -eq 'Scripts/Probe.ps1:2') ($probeScan.Gaps -join ', ')
    Assert-True 'the scan names both second writers of config.local.json by line, not Config''s writer and not the default file' `
        (($probeScan.Writers -join ',') -eq 'Scripts/Probe.ps1:5,Scripts/Probe.ps1:6') ($probeScan.Writers -join ', ')
}
catch { Assert-True 'the scan probe ran to the end without a terminating error' $false $_.Exception.Message }
finally { Remove-Item $scanProbe -Recurse -Force -ErrorAction SilentlyContinue }

# The later readers, run for real against a scratch package. A malformed file: one warning for
# the whole process, a reader that falls back, and the two WRITERS (Menu -Reset, Log -Ack) leave the
# bytes alone and say why. A file that parses but holds a bad date: the warning names the key.
$p405 = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-config-405-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $p405 -Force | Out-Null
try {
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Invoke-LockRetry "scratch copy of $file" { Copy-Item (Join-Path $pkgRoot $file) $p405 -Force } }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Scripts') $p405 -Recurse -Force }
    Invoke-LockRetry 'scratch copy' { Copy-Item (Join-Path $pkgRoot 'Config')  $p405 -Recurse -Force }
    $p405Local = Join-Path $p405 'config.local.json'
    $p405Q = $p405 -replace "'", "''"
    $p405Prefix = ((Get-Content (Join-Path $p405 'config.default.json') -Raw) | ConvertFrom-Json).commandPrefix
    $p405Logs = Join-Path $p405 'logs'
    New-Item -ItemType Directory -Path $p405Logs -Force | Out-Null
    Invoke-LockRetry 'write of a scratch file' { Set-Content -Path (Join-Path $p405Logs 'usage.scratch.log') -Value ("2026-10-01T10:00:00`tERR`tscratch`tx`tboom") -Encoding UTF8 }
    $p405LogsQ = $p405Logs -replace "'", "''"
    $isWarn = '[System.Management.Automation.WarningRecord]'

    # (a) the standalone readers the scan found: the agent port and the lifecycle read, one process.
    $badBytes = '{ "web": { "agentPort": 9999 }, "x": '
    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, $badBytes) }
    $cmdA = "`$env:PSModulePath = '$p405Q'; Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue; " +
        ". '$p405Q/Scripts/Resolve-HubConfig.ps1'; . '$p405Q/Scripts/Get-AgentPort.ps1'; . '$p405Q/Scripts/Get-SpaceLifecycle.ps1'; " +
        "`$a = Get-P20AgentPort -RepoRoot '$p405Q' 3>&1; `$b = Get-P20AgentPort -RepoRoot '$p405Q' 3>&1; `$c = Get-P20SpaceLifecycleState -PackageRoot '$p405Q' 3>&1; " +
        "`$d = Read-P20LocalConfigJson -Path '$p405Q/config.local.json' 3>&1; " +
        "`$w = @(@(`$a) + @(`$b) + @(`$c) + @(`$d) | Where-Object { `$_ -is $isWarn }); " +
        "'A-WARN-COUNT=' + `$w.Count; 'A-WARN-TEXT=' + `$w[0].Message; 'A-PORT=' + @(`$b | Where-Object { `$_ -is [int] })[0]"
    $outA = & pwsh -NoProfile -Command $cmdA 2>&1 | Out-String
    Assert-True 'the agent port, the lifecycle read and the shared reader warn once between them' ($outA -match 'A-WARN-COUNT=1\b') $outA
    Assert-True 'and the warning is the loader''s sentence' ($outA -match 'A-WARN-TEXT=Failed to parse config\.local\.json \(.+\)\. Using defaults only') $outA
    Assert-True 'and the agent port still comes from the shipped file' ($outA -match 'A-PORT=\d+') $outA

    # (b) the writers refuse a file they cannot read, and leave it as it was.
    $cmdB = "`$env:PSModulePath = '$p405Q'; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>`$null; " +
        "`$r = & { ${p405Prefix}Menu -Reset } 3>&1 6>&1 2>&1 | Out-String; 'RESET-OUT=' + (`$r -replace '\s+', ' '); " +
        "`$l = & { ${p405Prefix}Log -Ack } 3>&1 6>&1 2>&1 | Out-String; 'ACK-OUT=' + (`$l -replace '\s+', ' ')"
    $outB = & pwsh -NoProfile -Command $cmdB 2>&1 | Out-String
    Assert-True 'Menu -Reset on a malformed file says it was not reset' ($outB -match 'RESET-OUT=.*will not parse, so the menu scores were not reset') $outB
    Assert-True 'and Log -Ack on a malformed file says it did not acknowledge' ($outB -match 'ACK-OUT=.*will not parse, so the errors were not acknowledged') $outB
    $afterBytes = [System.IO.File]::ReadAllText($p405Local)
    Assert-True 'and neither writer changed a byte of it' ($afterBytes -eq $badBytes) $afterBytes

    # (c) a file that parses, with a bad date: the warning names the key, never "Failed to parse".
    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, '{ "menuResetTimestamp": "when it feels right", "errorsAckedAt": "nope" }') }
    $cmdC = "`$env:PSModulePath = '$p405Q'; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; `$w = Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>&1; " +
        "`$l = & { ${p405Prefix}Menu } 3>&1 6>&1; `$l2 = & { ${p405Prefix}Menu } 3>&1 6>&1; " +
        "`$all = @(@(`$w) + @(`$l) + @(`$l2) | Where-Object { `$_ -is $isWarn } | ForEach-Object { `$_.Message }); " +
        "'C-KEY-RESET=' + @(`$all | Where-Object { `$_ -match 'menuResetTimestamp is not a date \(when it feels right\)' }).Count; " +
        "'C-KEY-ACK=' + @(`$all | Where-Object { `$_ -match 'errorsAckedAt is not a date \(nope\)' }).Count; " +
        "'C-FAILED=' + @(`$all | Where-Object { `$_ -match 'Failed to parse' }).Count"
    $outC = & pwsh -NoProfile -Command $cmdC 2>&1 | Out-String
    Assert-True 'a bad menuResetTimestamp is named, once, over two menus' ($outC -match 'C-KEY-RESET=1\b') $outC
    Assert-True 'a bad errorsAckedAt is named, once, over two menus' ($outC -match 'C-KEY-ACK=1\b') $outC
    Assert-True 'and a file that parses is never called unparseable' ($outC -match 'C-FAILED=0\b') $outC

    # (d) SwitchSpace is the third writer: with a malformed file it states a refusal (exit 2) and writes nothing.
    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, $badBytes) }
    $cmdD = "`$env:PSModulePath = '$p405Q'; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>`$null; " +
        "`$r = & { ${p405Prefix}SwitchSpace azure-demo } 3>&1 6>&1 2>&1 | Out-String; 'SWITCH-CODE=' + `$LASTEXITCODE; 'SWITCH-OUT=' + (`$r -replace '\s+', ' ')"
    $outD = & pwsh -NoProfile -Command $cmdD 2>&1 | Out-String
    Assert-True 'SwitchSpace on a malformed file exits 2' ($outD -match 'SWITCH-CODE=2\b') $outD
    Assert-True 'and states why, as an Error' ($outD -match 'SWITCH-OUT=.*Error:.*will not parse, so the Space was not switched') $outD
    Assert-True 'and leaves the file byte for byte as it was' ([System.IO.File]::ReadAllText($p405Local) -eq $badBytes) ([System.IO.File]::ReadAllText($p405Local))

    # (e) The two that write when the file DOES parse -- SwitchSpace and Log -Ack -- write it the way
    # Config does (Write-ConfigJson): no BOM, LF, every other key kept, and a date-looking string kept
    # as the string it was. Run on THIS host, which the suite runs under both: Set-Content -Encoding
    # UTF8 put a BOM on the file under Windows PowerShell 5.1 and not under 7.
    $hostExe = (Get-Process -Id $PID).Path
    $goodJson = '{ "quietStart": true, "menuResetTimestamp": "2026-10-01T09:00:00" }'
    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, $goodJson, (New-Object System.Text.UTF8Encoding($true))) }
    $cmdE = "`$env:PSModulePath = '$p405Q' + [System.IO.Path]::PathSeparator + `$env:PSModulePath; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; " +
        "Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>`$null; " +
        "`$null = & { ${p405Prefix}SwitchSpace azure-demo } *>&1; 'SWITCH-CODE=' + `$LASTEXITCODE"
    $outE = (& $hostExe -NoProfile -EncodedCommand ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmdE))) 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $eBytes = [System.IO.File]::ReadAllBytes($p405Local)
    $eText = [System.Text.Encoding]::UTF8.GetString($eBytes)
    Assert-True 'SwitchSpace over a parsing file exits 0' ($outE -match 'SWITCH-CODE=0\b') $outE
    Assert-True 'and writes config.local.json with no BOM on this host' (-not ($eBytes.Length -ge 3 -and $eBytes[0] -eq 0xEF -and $eBytes[1] -eq 0xBB -and $eBytes[2] -eq 0xBF)) (($eBytes | Select-Object -First 3) -join ',')
    Assert-True 'with LF line endings and the two-space indent Config writes' (($eText -notmatch "`r") -and ($eText -match '(?m)^  "activeSpace": "azure-demo"')) $eText
    Assert-True 'keeping the keys it did not change, a date-looking string as itself' (($eText -match '"quietStart": true') -and ($eText -match '"menuResetTimestamp": "2026-10-01T09:00:00"')) $eText

    Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, $goodJson, (New-Object System.Text.UTF8Encoding($true))) }
    $cmdF = "`$env:PSModulePath = '$p405Q' + [System.IO.Path]::PathSeparator + `$env:PSModulePath; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; " +
        "Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>`$null; " +
        "`$null = & { ${p405Prefix}Log -Ack } *>&1; 'ACK-CODE=' + `$LASTEXITCODE"
    $outF = (& $hostExe -NoProfile -EncodedCommand ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmdF))) 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $fBytes = [System.IO.File]::ReadAllBytes($p405Local)
    $fText = [System.Text.Encoding]::UTF8.GetString($fBytes)
    Assert-True 'Log -Ack over a parsing file exits 0' ($outF -match 'ACK-CODE=0\b') $outF
    Assert-True 'and writes config.local.json with no BOM on this host' (-not ($fBytes.Length -ge 3 -and $fBytes[0] -eq 0xEF -and $fBytes[1] -eq 0xBB -and $fBytes[2] -eq 0xBF)) (($fBytes | Select-Object -First 3) -join ',')
    Assert-True 'with LF line endings, and the stamp it writes' (($fText -notmatch "`r") -and ($fText -match '(?m)^  "errorsAckedAt": "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"')) $fText
    Assert-True 'keeping the keys it did not change, a date-looking string as itself' (($fText -match '"quietStart": true') -and ($fText -match '"menuResetTimestamp": "2026-10-01T09:00:00"')) $fText

    # (g) A zero-byte (or whitespace-only) config.local.json is an empty object, not a parse failure:
    # Log -Ack and SwitchSpace both write through it instead of dereferencing a null.
    foreach ($emptyCase in @(@{ Name = 'zero-byte'; Text = '' }, @{ Name = 'whitespace-only'; Text = "  `n" })) {
        foreach ($verbCase in @(@{ Verb = 'Log -Ack'; Call = "${p405Prefix}Log -Ack"; Key = 'errorsAckedAt' }, @{ Verb = 'SwitchSpace'; Call = "${p405Prefix}SwitchSpace azure-demo"; Key = 'activeSpace' })) {
            Invoke-LockRetry 'write of a scratch file' { [System.IO.File]::WriteAllText($p405Local, $emptyCase.Text) }
            $cmdG = "`$env:PSModulePath = '$p405Q' + [System.IO.Path]::PathSeparator + `$env:PSModulePath; `$env:P20_USAGE_LOG_DIR = '$p405LogsQ'; " +
                "Import-Module '$p405Q/utilities.psm1' -Force -DisableNameChecking 3>`$null; " +
                "`$null = & { $($verbCase.Call) } *>&1; 'EMPTY-CODE=' + `$LASTEXITCODE"
            $outG = (& $hostExe -NoProfile -EncodedCommand ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmdG))) 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
            $gText = [System.IO.File]::ReadAllText($p405Local)
            Assert-True "$($verbCase.Verb) over a $($emptyCase.Name) config.local.json exits 0" ($outG -match 'EMPTY-CODE=0\b') $outG
            Assert-True "and writes $($verbCase.Key) into it" ($gText -match ('"' + $verbCase.Key + '"')) $gText
        }
    }
}
catch { Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message }
finally { Remove-Item $p405 -Recurse -Force -ErrorAction SilentlyContinue }

# -- Summary -------------------------------------------------------------------

if ($script:SavedPromptsRoot) { $env:PROMPTS_ROOT = $script:SavedPromptsRoot }

Write-Host ''
Write-Host '=======================================================' -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ''
    Write-Host '  Failures:' -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host '=======================================================' -ForegroundColor Cyan
Write-Host ''

if ($script:failed -gt 0) { exit 1 }
exit 0
