<#
.SYNOPSIS
    Tests for the autoload shim (InstallAutoload / Prompt20Toolkit).
.DESCRIPTION
    The shim exists so `{cliPrefix}*` resolves in shells that never load a profile --
    agent tool calls, `pwsh -c`, CI, git hooks. Before it, those shells had no
    `{cliPrefix}*` at all, because utilities.psm1 publishes its commands as an import
    side effect (`function global:` + `Set-Alias -Scope Global`).

    What these tests assert, and why each one is the thing that regresses:

      - The MANIFEST is what makes auto-loading work. PowerShell only consults
        AliasesToExport when resolving an unknown command, so an alias missing
        from that list works interactively and fails in exactly the shells the
        shim was built for. The generated manifest must therefore cover every
        {cliPrefix}* alias utilities.psm1 actually defines -- a drift check, and the
        highest-value test here.
      - The generator must discover a plausible number of aliases and must
        refuse to write an empty manifest (an empty AliasesToExport would
        silently disable autoload everywhere).
      - The shim must locate utilities.psm1 both when installed as a SYMLINK
        (sibling lookup) and as a COPY (falls back to $env:WS_ROOT) -- the copy
        path is what most Windows machines get, since symlinks need elevation.
      - A missing toolkit must WARN rather than throw: auto-loading fires on any
        unrecognized {cliPrefix}* command, so throwing would turn a typo into a stack
        trace that looks like the toolkit is broken.
      - InstallAutoload answers -Help and carries a config entry (CLI.md
        clauses 7 and 11).

    Real end-to-end auto-loading (resolving a command in a cold shell) is
    deliberately NOT tested here -- the developer's own module path is where the
    shim would have to land, and overwriting the shim this machine actually uses
    is not a test's business. That last step is verified by the installer
    itself, which probes a cold -NoProfile shell and exits non-zero if the
    prefixed commands fail
    to resolve.

    The install's OWN decisions -- writes, no-ops and refreshes -- are tested,
    against a scratch module directory passed with -ModuleRoot. That is what
    -ModuleRoot exists for: a re-install that leaves a stale copy in place and
    calls it installed was a real defect on the Windows floor,
   and
    it was invisible because nothing could run the installer without hitting the
    real module path.

    Run:  pwsh -File toolkit/Tests/Test-Autoload.ps1
    Or:   {cliPrefix}TestToolkit -Autoload
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# The package root is the parent of Tests/, derived from this file's own
# location. Works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent

$shimDir    = Join-Path $pkgRoot 'Prompt20Toolkit'
$shimModule = Join-Path $shimDir 'Prompt20Toolkit.psm1'
$generator  = Join-Path $shimDir 'Update-ToolkitManifest.ps1'
$manifest   = Join-Path $shimDir 'Prompt20Toolkit.psd1'
$aliasHelper = Join-Path $shimDir 'Get-ToolkitAliases.ps1'
$installer  = Join-Path $pkgRoot 'Scripts/Install-ToolkitAutoload.ps1'
$modPath    = Join-Path $pkgRoot 'utilities.psm1'
$configPath = Join-Path $pkgRoot 'config.default.json'

# Command namespace under test -- read from config so a renamed prefix does not
# silently make these assertions vacuous.
. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$cfgPrefix = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot

foreach ($required in @($shimModule, $generator, $aliasHelper, $installer, $modPath)) {
    if (-not (Test-Path $required)) {
        Write-Error "Required file not found: $required"
        return
    }
}

# -- Test harness --------------------------------------------------------------

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
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# The canonical alias set the manifest must advertise. Deliberately the SAME
# helper the generator uses -- if the test defined "which aliases count" on its
# own, the two could disagree and the drift check would chase a manifest the
# generator never produces. It excludes personal nav shortcuts from the
# gitignored config.local.json, which used to make these assertions flip between
# machines with no code change at all.
. $aliasHelper

function Get-DefinedAliases {
    return @(Get-ToolkitAliases -UtilitiesPath $modPath -DefaultConfigPath $configPath)
}

# -- Tests ---------------------------------------------------------------------

Write-Host ""
Write-Host "  Autoload shim" -ForegroundColor Cyan
Write-Host ""

# --- The manifest is the contract that makes autoload work --------------------

Assert-True 'manifest exists (generated)' (Test-Path $manifest) `
    'run toolkit/Prompt20Toolkit/Update-ToolkitManifest.ps1'

$manifestData = $null
if (Test-Path $manifest) {
    try { $manifestData = Import-PowerShellDataFile -Path $manifest }
    catch { $manifestData = $null }
}

Assert-True 'manifest parses as a data file' ($null -ne $manifestData)

if ($manifestData) {
    Assert-True 'manifest RootModule points at the shim' `
        ($manifestData.RootModule -eq 'Prompt20Toolkit.psm1') "got '$($manifestData.RootModule)'"

    $exported = @($manifestData.AliasesToExport)
    Assert-True 'manifest exports a non-empty alias list' ($exported.Count -gt 0) `
        'an empty AliasesToExport silently disables autoload everywhere'

    # The drift check. This is the test that catches "added a command,
    # forgot to re-run the generator" -- which fails ONLY in profile-less shells
    # and is therefore invisible during normal interactive use.
    $defined = Get-DefinedAliases
    Assert-True 'discovery found the toolkit aliases' ($defined.Count -gt 20) `
        "only found $($defined.Count)"

    if ($defined.Count -gt 20) {
        $missing = @($defined | Where-Object { $_ -notin $exported })
        Assert-True 'every defined alias is in the manifest' ($missing.Count -eq 0) `
            "missing: $($missing -join ', ') -- re-run Update-ToolkitManifest.ps1"

        # A stale manifest naming aliases that no longer exist isn't fatal (the
        # import just defines whatever it defines), but it means the generator
        # hasn't been re-run since a rename, so flag it.
        $stale = @($exported | Where-Object { $_ -notin $defined })
        Assert-True 'manifest has no aliases the toolkit no longer defines' ($stale.Count -eq 0) `
            "stale: $($stale -join ', ')"

        # The two assertions above compare a COMMITTED file against a set built
        # on this machine, so they only mean something if that set is the same
        # on every machine. config.local.json is gitignored and per-developer:
        # any nav shortcut declared only there must stay out, or the drift check
        # goes red on whichever machine did not last run the generator. Trivially
        # true on a machine with no local nav shortcuts of its own -- it is the
        # machine that HAS them where this earns its place.
        $localCfgPath = Join-Path $pkgRoot 'config.local.json'
        if (Test-Path $localCfgPath) {
            $localCfg = $null
            try { $localCfg = Get-Content $localCfgPath -Raw | ConvertFrom-Json } catch { $localCfg = $null }
            # Both sides bare, then compared under the prefix: the manifest
            # carries the REGISTERED name (prefix + key) and a config file
            # carries the key, which may still be spelled with the prefix on a
            # machine that has not renamed it.
            $navPrefix = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot
            $sharedNames = @((Get-Content $configPath -Raw | ConvertFrom-Json).aliases.PSObject.Properties.Name |
                ForEach-Object { ConvertTo-P20BareAliasKey -Key $_ -Prefix $navPrefix })
            $localOnly = @()
            if ($localCfg -and $localCfg.aliases) {
                $localOnly = @($localCfg.aliases.PSObject.Properties.Name |
                    ForEach-Object { ConvertTo-P20BareAliasKey -Key $_ -Prefix $navPrefix } |
                    Where-Object { $_ -notin $sharedNames })
            }
            $leaked = @($localOnly | Where-Object { ($navPrefix + $_) -in $defined -or $_ -in $defined })
            Assert-True 'personal nav aliases (config.local.json only) stay out of the manifest' `
                ($leaked.Count -eq 0) `
                "leaked: $($leaked -join ', ') -- these would flip this suite red on any other machine"
        }
    }

    # --- Nav aliases are advertised under the prefix, not as stored ----------
    # The keys in config.default.json are BARE ('Home'), because the prefix is
    # applied when the alias is registered. The manifest advertises names a cold
    # shell has to resolve, so it carries prefix + key -- and a changed
    # commandPrefix moves the shortcuts with the verbs instead of leaving a
    # frozen 'tk' behind.
    #
    $navPrefixNow = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot
    $navKeys = @((Get-Content $configPath -Raw | ConvertFrom-Json).aliases.PSObject.Properties.Name)
    Assert-True 'the shipped config declares nav aliases' ($navKeys.Count -gt 0)
    foreach ($navKey in $navKeys) {
        Assert-True "config stores '$navKey' bare" `
            ($navKey -eq (ConvertTo-P20BareAliasKey -Key $navKey -Prefix $navPrefixNow)) $navKey
        Assert-True "the manifest advertises $navPrefixNow$navKey" `
            ($exported -contains ($navPrefixNow + $navKey)) "not in AliasesToExport"
        Assert-True "and not the bare key on its own" ($exported -notcontains $navKey) $navKey
    }

    # A package whose commandPrefix is something else: the generator follows it,
    # for the nav aliases as well as for the verbs. This is the assertion the
    # issue asked for -- change the prefix and everything updates, with no edit
    # to any alias key.
    $prefixScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-autoload-prefix-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $prefixScratch -Force | Out-Null
        foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) {
            Copy-Item (Join-Path $pkgRoot $file) $prefixScratch -Force
        }
        Copy-Item (Join-Path $pkgRoot 'Scripts')          $prefixScratch -Recurse -Force
        Copy-Item (Join-Path $pkgRoot 'Config')           $prefixScratch -Recurse -Force
        Copy-Item (Join-Path $pkgRoot 'Prompt20Toolkit')  $prefixScratch -Recurse -Force
        $scratchConfigPath = Join-Path $prefixScratch 'config.default.json'
        $scratchConfig = Get-Content $scratchConfigPath -Raw | ConvertFrom-Json
        $scratchConfig.commandPrefix = 'zz'
        [System.IO.File]::WriteAllText($scratchConfigPath, ($scratchConfig | ConvertTo-Json -Depth 20),
            (New-Object System.Text.UTF8Encoding($false)))

        $scratchAliases = @(Get-ToolkitAliases -UtilitiesPath (Join-Path $prefixScratch 'utilities.psm1') `
            -DefaultConfigPath $scratchConfigPath)
        foreach ($navKey in $navKeys) {
            Assert-True "a changed prefix moves $navKey to zz$navKey" `
                ($scratchAliases -contains ("zz" + $navKey)) ($scratchAliases -join ', ')
            Assert-True "and leaves no $navPrefixNow$navKey behind" `
                ($scratchAliases -notcontains ($navPrefixNow + $navKey)) ($scratchAliases -join ', ')
        }
        Assert-True 'and the verbs followed the prefix too' `
            (@($scratchAliases | Where-Object { $_ -like 'zz*' }).Count -gt 20) `
            "$(@($scratchAliases | Where-Object { $_ -like 'zz*' }).Count) zz aliases"
    }
    finally { Remove-Item $prefixScratch -Recurse -Force -ErrorAction SilentlyContinue }

    # Discovery keeps only the configured namespace, because a before/after alias diff
    # also catches PowerShell's own aliases (gcb, gtz, stz...) autoloaded by the
    # cmdlets utilities.psm1 calls at import, and which of those appear varies by
    # platform. That filter is safe only while every command really carries the
    # prefix, so
    # read the Set-Alias lines out of the source and hold them to the manifest
    # directly -- a command named outside the convention fails here instead of
    # being silently dropped from the autoload contract.
    $declared = @(
        [regex]::Matches((Get-Content $modPath -Raw), '(?m)^\s*Set-Alias\s+-Name\s+([A-Za-z][A-Za-z0-9_-]*)') |
            ForEach-Object { $_.Groups[1].Value }
    )
    $undeclared = @($declared | Where-Object { $_ -notin $exported })
    Assert-True 'every Set-Alias in utilities.psm1 is in the manifest' ($undeclared.Count -eq 0) `
        "not exported: $($undeclared -join ', ') -- re-run Update-ToolkitManifest.ps1"

    # InstallAutoload must be in its own manifest, or the command that repairs
    # autoload is itself unreachable in the shells that need repairing.
    Assert-True 'manifest includes {cliPrefix}InstallAutoload' ($exported -contains ($cfgPrefix + 'InstallAutoload'))

    Assert-True 'manifest declares no functions (aliases resolve the import)' `
        (@($manifestData.FunctionsToExport).Count -eq 0)
}

# --- The generator ------------------------------------------------------------

# The assertions below run the generator for real, and it writes a TRACKED file.
# Capture the bytes up front and put them back afterwards, or every test
# run leaves the working tree dirty. Bytes rather than text, so the restore
# itself cannot introduce the EOL drift these tests are here to catch.
$manifestBytes = if (Test-Path $manifest) { [System.IO.File]::ReadAllBytes($manifest) } else { $null }

try {
    # -WhatIf must not write. Capture the manifest's current bytes and confirm.
    $before = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { $null }
    $whatIfOut = & pwsh -NoProfile -File $generator -WhatIf 2>&1 | Out-String
    $after = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { $null }

    Assert-True 'generator -WhatIf changes nothing on disk' ($before -eq $after)
    Assert-True 'generator -WhatIf reports what it would write' `
        ($whatIfOut -match 'would write')

    # Regenerating must be deterministic -- otherwise every run dirties the repo and
    # the drift check above becomes noise people learn to ignore. Compare two
    # CONSECUTIVE regenerations rather than against the pre-existing file, so a
    # manifest that was merely stale on disk doesn't read as non-determinism.
    $regen = & pwsh -NoProfile -File $generator 2>&1 | Out-String
    $firstRegen = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { $null }
    & pwsh -NoProfile -File $generator *> $null
    $secondRegen = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { $null }

    Assert-True 'regenerating produces identical output (deterministic)' `
        ($firstRegen -eq $secondRegen) 'generator output is not stable across runs'
    Assert-True 'generator reports the alias count it discovered' `
        ($regen -match 'Discovered \d+ aliases')

    # .gitattributes checks this manifest out as LF on every platform while *.ps1
    # -- including the generator, and so its here-string -- is CRLF. A generator
    # that emits anything but LF produces a file that can never equal its own
    # checked-out copy, and the drift assertion below then fails forever on a
    # clean tree while telling you to regenerate and commit, which cannot clear
    # it. Assert the EOLs directly so that returns as its own cause.
    Assert-True 'generated manifest is LF-only (matches .gitattributes eol=lf)' `
        (-not $firstRegen.Contains("`r")) `
        'generator wrote CR bytes; .gitattributes pins this file to eol=lf'

    # The committed manifest must already match what the generator produces -- if it
    # doesn't, someone added a command without re-running the generator, which
    # is precisely the drift that breaks autoload in profile-less shells. Compared
    # byte-for-byte deliberately: the LF assertion above makes that achievable on
    # every platform, so normalizing here would only hide a real regression.
    Assert-True 'committed manifest is up to date with utilities.psm1' `
        ($before -eq $firstRegen) 'manifest is stale -- run Update-ToolkitManifest.ps1 and commit'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if ($null -ne $manifestBytes) { [System.IO.File]::WriteAllBytes($manifest, $manifestBytes) }
}

# --- The install decides: write, no-op, or refresh ----------------------------

# The bug this section exists for: a machine that installed once got
# "already installed ... Re-run with -Force to replace it" and exit 0 forever,
# so a COPY install (the normal Windows case, symlinks needing Developer Mode)
# silently kept whatever manifest it was given months earlier -- missing every
# alias added since, in exactly the profile-less shells the shim is for.
#
# Everything here runs against a scratch -ModuleRoot and -CopyOnly. -CopyOnly
# because a symlink cannot be stale and macOS creates symlinks without
# privilege, so without it this host would never reach the branch under test.
$installScratch = Join-Path ([System.IO.Path]::GetTempPath()) "autoload-install-$([guid]::NewGuid())"
# The installer regenerates the TRACKED manifest before every install, same as
# the generator section above. Put the bytes back or the suite dirties the tree.
$preInstallManifest = if (Test-Path $manifest) { [System.IO.File]::ReadAllBytes($manifest) } else { $null }

function Invoke-Installer {
    param([string]$Root, [string[]]$Extra = @())
    $psArgs = @('-NoProfile', '-File', $installer, '-ModuleRoot', $Root, '-CopyOnly') + $Extra
    return (& pwsh @psArgs 2>&1 | Out-String)
}

try {
    $modRoot = Join-Path $installScratch 'Modules'
    $installedDir = Join-Path $modRoot 'Prompt20Toolkit'
    $installedManifest = Join-Path $installedDir 'Prompt20Toolkit.psd1'

    # -WhatIf must not create the destination.
    $whatIf = Invoke-Installer -Root $modRoot -Extra @('-WhatIf')
    Assert-True 'install -WhatIf writes nothing to the module root' (-not (Test-Path $installedDir)) $whatIf

    $first = Invoke-Installer -Root $modRoot
    Assert-True 'first install writes the shim' (Test-Path $installedManifest) $first
    Assert-True 'first install says it copied' ($first -match 'Copied to') $first
    Assert-True 'a scratch -ModuleRoot skips the machine-scoped steps' `
        ($first -match 'skipping the 5\.1 mirror') $first

    # The no-op. Compare the file itself, not just the message: "up to date"
    # over a rewritten file would be the same defect wearing a better word.
    $stampBefore = (Get-Item $installedManifest).LastWriteTimeUtc
    $second = Invoke-Installer -Root $modRoot
    Assert-True 'a second install is a no-op' ($second -match 'Already up to date') $second
    Assert-True 'the no-op did not rewrite the installed manifest' `
        ((Get-Item $installedManifest).LastWriteTimeUtc -eq $stampBefore)

    # CRLF is what the shim's *.ps1 files check out as on Windows, so the
    # comparison normalises line endings before it compares bytes. Without that
    # every Windows install would read as stale and be rewritten every run.
    # Bytes in, bytes out -- the shim files carry a UTF-8 BOM, and a round trip
    # through ReadAllText/WriteAllText would drop it and make this case about
    # the BOM rather than about line endings.
    $psm1 = Join-Path $installedDir 'Prompt20Toolkit.psm1'
    $psm1Text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($psm1))
    $crlf = ($psm1Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllBytes($psm1, [System.Text.Encoding]::UTF8.GetBytes($crlf))
    $eol = Invoke-Installer -Root $modRoot
    Assert-True 'a CRLF checkout of the same shim is not called stale' `
        ($eol -match 'Already up to date') $eol

    # The defect itself: an installed copy that differs must be refreshed
    # WITHOUT -Force, and must say that it was.
    # A byte-level append: Add-Content -Encoding UTF8 throws "Stream was not readable" under
    # Windows PowerShell 5.1 when something still holds the file just installed.
    [System.IO.File]::AppendAllText($installedManifest, "# stale marker" + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    $third = Invoke-Installer -Root $modRoot
    Assert-True 'a changed shim is refreshed without -Force' ($third -match 'Refreshed the copy') $third
    Assert-True 'the refresh names the path it refreshed' ($third -match [regex]::Escape($installedDir)) $third
    Assert-True 'the refreshed copy no longer carries the stale content' `
        (-not ((Get-Content $installedManifest -Raw) -match 'stale marker'))

    # -Force keeps meaning "overwrite regardless", including over a copy that
    # already matches.
    $forced = Invoke-Installer -Root $modRoot -Extra @('-Force')
    Assert-True '-Force replaces an install that already matches' ($forced -match 'Replaced the install') $forced
    Assert-True 'the forced install is still a working shim' (Test-Path $installedManifest)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $installScratch -Recurse -Force -ErrorAction SilentlyContinue
    if ($null -ne $preInstallManifest) { [System.IO.File]::WriteAllBytes($manifest, $preInstallManifest) }
}

# --- InstallAutoload -Remove --------------------------------------------------
#
# The way back out: it removes the shim from each module root it is in, link or
# copy, and leaves the checkout a link points at alone. Every case runs against
# scratch module roots; the machine's own Modules folders are never named.
$removeScratch = Join-Path ([System.IO.Path]::GetTempPath()) "autoload-remove-$([guid]::NewGuid())"

function Invoke-Remover {
    param([string[]]$Roots, [string[]]$Extra = @())
    $joined = $Roots -join [System.IO.Path]::PathSeparator
    $psArgs = @('-NoProfile', '-File', $installer, '-Remove', '-ModuleRoot', $joined) + $Extra
    $out = (& pwsh @psArgs 2>&1 | Out-String)
    return [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
}

function New-LinkedShim {
    param([string]$Root, [string]$Target)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $link = Join-Path $Root 'Prompt20Toolkit'
    try { $null = New-Item -ItemType SymbolicLink -Path $link -Target $Target -ErrorAction Stop; return 'symlink' }
    catch {
        try { $null = New-Item -ItemType Junction -Path $link -Target $Target -ErrorAction Stop; return 'junction' }
        catch { return '' }
    }
}

function New-CopiedShim {
    param([string]$Root, [string]$Source)
    $dest = Join-Path $Root 'Prompt20Toolkit'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $Source '*') $dest -Recurse -Force
}

function Get-TreeFingerprint {
    param([string]$Path)
    $len = $Path.Length
    return (@(Get-ChildItem $Path -Recurse -File | ForEach-Object { $_.FullName.Substring($len) + ':' + (Get-FileHash $_.FullName).Hash } | Sort-Object) -join '|')
}

try {
    # A stand-in for the checkout: a copy of the shim folder plus a marker file,
    # so "untouched" can be asserted on files and not on a hope.
    $fakeCheckout = Join-Path $removeScratch 'checkout/Prompt20Toolkit'
    New-Item -ItemType Directory -Path $fakeCheckout -Force | Out-Null
    Copy-Item (Join-Path $shimDir '*') $fakeCheckout -Recurse -Force
    Set-Content -Path (Join-Path $fakeCheckout 'marker.txt') -Value 'keep me'
    $checkoutBefore = Get-TreeFingerprint $fakeCheckout

    # Nothing installed anywhere.
    $emptyRoot = Join-Path $removeScratch 'empty/Modules'
    $none = Invoke-Remover -Roots @($emptyRoot)
    Assert-True '-Remove with no shim says nothing to remove' ($none.Output -match 'nothing to remove') $none.Output
    Assert-True '-Remove with no shim exits 0' ($none.Code -eq 0) "exit $($none.Code)"

    # A linked shim (symlink, or a junction where symlinks need privilege).
    $linkRoot = Join-Path $removeScratch 'link/Modules'
    $linkKind = New-LinkedShim -Root $linkRoot -Target $fakeCheckout
    if ($linkKind) {
        $linkPath = Join-Path $linkRoot 'Prompt20Toolkit'
        $r = Invoke-Remover -Roots @($linkRoot) -Extra @('-WhatIf')
        Assert-True '-Remove -WhatIf names the path it would remove' ($r.Output -match [regex]::Escape($linkPath)) $r.Output
        Assert-True '-Remove -WhatIf leaves a linked shim in place' (Test-Path $linkPath) $r.Output
        $r = Invoke-Remover -Roots @($linkRoot)
        Assert-True "-Remove deletes a linked shim ($linkKind)" (-not (Test-Path $linkPath)) $r.Output
        Assert-True '-Remove prints the path it removed' ($r.Output -match [regex]::Escape($linkPath)) $r.Output
        Assert-True '-Remove keeps the module root itself' (Test-Path $linkRoot)
        Assert-True '-Remove through a link leaves the checkout it pointed at' (Test-Path (Join-Path $fakeCheckout 'marker.txt')) $r.Output
    }
    else {
        Assert-True 'a link could be made here (neither symlink nor junction was allowed)' $false 'the linked-shim cases did not run'
    }

    # A copied shim.
    $copyRoot = Join-Path $removeScratch 'copy/Modules'
    New-CopiedShim -Root $copyRoot -Source $fakeCheckout
    $copyPath = Join-Path $copyRoot 'Prompt20Toolkit'
    $r = Invoke-Remover -Roots @($copyRoot) -Extra @('-WhatIf')
    Assert-True '-Remove -WhatIf leaves a copied shim in place' (Test-Path (Join-Path $copyPath 'Prompt20Toolkit.psm1')) $r.Output
    Assert-True '-Remove -WhatIf says it would remove, and not that it did' (($r.Output -match 'Would remove|What if') -and ($r.Output -notmatch '\[OK\] Removed')) $r.Output
    $r = Invoke-Remover -Roots @($copyRoot)
    Assert-True '-Remove deletes a copied shim' (-not (Test-Path $copyPath)) $r.Output
    Assert-True '-Remove of a copy prints the path' ($r.Output -match [regex]::Escape($copyPath)) $r.Output

    # Both hosts' roots at once: one linked where a link can be made, one copied.
    $rootA = Join-Path $removeScratch 'both/PowerShell/Modules'
    $rootB = Join-Path $removeScratch 'both/WindowsPowerShell/Modules'
    New-CopiedShim -Root $rootB -Source $fakeCheckout
    $kindA = New-LinkedShim -Root $rootA -Target $fakeCheckout
    if (-not $kindA) { New-CopiedShim -Root $rootA -Source $fakeCheckout }
    $r = Invoke-Remover -Roots @($rootA, $rootB)
    Assert-True '-Remove clears both roots in one run' `
        ((-not (Test-Path (Join-Path $rootA 'Prompt20Toolkit'))) -and (-not (Test-Path (Join-Path $rootB 'Prompt20Toolkit')))) $r.Output
    Assert-True '-Remove names both paths' `
        (($r.Output -match [regex]::Escape((Join-Path $rootA 'Prompt20Toolkit'))) -and ($r.Output -match [regex]::Escape((Join-Path $rootB 'Prompt20Toolkit')))) $r.Output

    # A folder of that name which is not a shim is left alone.
    $strangerRoot = Join-Path $removeScratch 'stranger/Modules'
    New-Item -ItemType Directory -Path (Join-Path $strangerRoot 'Prompt20Toolkit') -Force | Out-Null
    Set-Content -Path (Join-Path $strangerRoot 'Prompt20Toolkit/notes.txt') -Value 'mine'
    $r = Invoke-Remover -Roots @($strangerRoot)
    Assert-True '-Remove leaves a same-named folder that is not the shim' (Test-Path (Join-Path $strangerRoot 'Prompt20Toolkit/notes.txt')) $r.Output

    # Two intentions: refused once, exit 2, nothing removed.
    $forceRoot = Join-Path $removeScratch 'force/Modules'
    New-CopiedShim -Root $forceRoot -Source $fakeCheckout
    $r = Invoke-Remover -Roots @($forceRoot) -Extra @('-Force')
    Assert-True '-Remove -Force is refused with exit 2' ($r.Code -eq 2) "exit $($r.Code): $($r.Output)"
    Assert-True '-Remove -Force states the refusal once' (([regex]::Matches($r.Output, 'Error:')).Count -eq 1) $r.Output
    Assert-True '-Remove -Force removes nothing' (Test-Path (Join-Path $forceRoot 'Prompt20Toolkit/Prompt20Toolkit.psm1')) $r.Output

    # The checkout after all of the above.
    Assert-True 'the checkout is byte-for-byte untouched after every remove' ($checkoutBefore -eq (Get-TreeFingerprint $fakeCheckout))
}
catch {
    Assert-True 'the remove cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    # Unlink before the recursive delete so a surviving link cannot be followed.
    foreach ($leftover in @(Get-ChildItem $removeScratch -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })) {
        try { [System.IO.Directory]::Delete($leftover.FullName, $false) } catch { $null = $_ }
    }
    Remove-Item -Path $removeScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# --- The shim's path resolution ----------------------------------------------

# Copy-install case: shim sits somewhere with no sibling utilities.psm1, so it
# must fall back to $env:WS_ROOT. This is what most Windows machines get, since
# symlinks need Developer Mode or elevation.
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "autoload-test-$([guid]::NewGuid())"
try {
    # Build a fake WS_ROOT layout: <scratch>/ws/toolkit/utilities.psm1
    $fakeToolkit = Join-Path $scratch 'ws/toolkit'
    New-Item -ItemType Directory -Path $fakeToolkit -Force | Out-Null
    Copy-Item $modPath (Join-Path $fakeToolkit 'utilities.psm1')
    Copy-Item $configPath (Join-Path $fakeToolkit 'config.default.json')
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $fakeToolkit 'consts.json')
    Copy-Item (Join-Path $pkgRoot 'Scripts') (Join-Path $fakeToolkit 'Scripts') -Recurse -Force

    # Place the shim where it has NO sibling utilities.psm1 (mimics a copy install)
    $fakeModuleDir = Join-Path $scratch 'Modules/Prompt20Toolkit'
    New-Item -ItemType Directory -Path $fakeModuleDir -Force | Out-Null
    Copy-Item $shimModule (Join-Path $fakeModuleDir 'Prompt20Toolkit.psm1')
    if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $fakeModuleDir 'Prompt20Toolkit.psd1') }

    $wsRoot = (Join-Path $scratch 'ws') -replace "'", "''"
    $shimCopy = (Join-Path $fakeModuleDir 'Prompt20Toolkit.psm1') -replace "'", "''"
    $body = @"
`$env:WS_ROOT = '$wsRoot'
Import-Module '$shimCopy' -Force -DisableNameChecking *> `$null
[bool](Get-Command '$($cfgPrefix)Status' -ErrorAction SilentlyContinue)
"@
    $tmp = Join-Path $scratch 'run-copy.ps1'
    Set-Content -Path $tmp -Value $body -Encoding UTF8
    $copyResult = (& pwsh -NoProfile -File $tmp 2>&1 | Out-String).Trim()

    Assert-True 'copy-install shim resolves toolkit via $env:WS_ROOT' `
        ($copyResult -match 'True') "got: $copyResult"

    # Missing toolkit: must warn, not throw. Autoload fires on any unrecognized
    # prefixed command, so a throw would make a typo look like a broken toolkit.
    #
    # This uses the COPY of the shim (no sibling utilities.psm1), which is the
    # only way to reach the fallback branch -- importing the in-repo shim finds
    # its sibling and never consults $env:WS_ROOT at all. `3>&1` redirects the
    # warning stream into output so the message itself can be asserted.
    $emptyRoot = (Join-Path $scratch 'nonexistent') -replace "'", "''"
    $body2 = @"
`$env:WS_ROOT = '$emptyRoot'
`$ErrorActionPreference = 'Stop'
try {
    Import-Module '$shimCopy' -Force -DisableNameChecking 3>&1 | ForEach-Object { 'WARN: ' + `$_ }
    'NO-THROW'
} catch {
    'THREW: ' + `$_.Exception.Message
}
"@
    $tmp2 = Join-Path $scratch 'run-missing.ps1'
    Set-Content -Path $tmp2 -Value $body2 -Encoding UTF8
    $missingResult = (& pwsh -NoProfile -File $tmp2 2>&1 | Out-String)

    Assert-True 'missing toolkit warns instead of throwing' `
        ($missingResult -notmatch 'THREW:') "got: $($missingResult.Trim())"
    Assert-True 'missing toolkit explains how to fix it' `
        ($missingResult -match 'WS_ROOT|utilities\.psm1')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# --- CLI contract (CLI.md clauses 7 and 11) -----------------------------------

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$entry = $config.commands.'InstallAutoload'

Assert-True 'InstallAutoload has a config entry' ($null -ne $entry)
if ($entry) {
    Assert-True 'config entry has usage (clause 7: help is generated)' `
        (-not [string]::IsNullOrWhiteSpace($entry.usage))
    Assert-True 'config entry has a description' `
        (-not [string]::IsNullOrWhiteSpace($entry.description))
    Assert-True 'config entry has examples' (@($entry.examples).Count -gt 0)
    Assert-True 'config entry is categorized as setup' ($entry.category -eq 'setup')
}

$modText = Get-Content $modPath -Raw
Assert-True 'utilities.psm1 exposes InstallAutoload in the command table' `
    ($modText -match "'InstallAutoload'\s*=")
Assert-True 'wrapper uses an approved Verb-Noun name (clause 2)' `
    ($modText -match 'function global:Install-P20ToolkitAutoload')

# Installer must be PS 5.1-parseable and ASCII-only (clause 10). The repo-wide
# compat suite covers Scripts/, but the shim folder is new -- assert directly.
foreach ($f in @($shimModule, $generator, $aliasHelper)) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    Assert-True "$(Split-Path $f -Leaf) parses cleanly" (-not $errs) `
        "$(@($errs).Count) parse error(s)"

    $nonAscii = Select-String -Path $f -Pattern '[^\x00-\x7F]' -AllMatches
    Assert-True "$(Split-Path $f -Leaf) is ASCII-only (clause 10)" ($null -eq $nonAscii) `
        "non-ASCII on line(s): $(($nonAscii.LineNumber) -join ', ')"
}

# -- Summary -------------------------------------------------------------------

Write-Host ""
$total = $script:passed + $script:failed
if ($script:failed -gt 0) {
    Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor Red
    Write-Host ""
    $script:errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
else {
    Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor Green
}
Write-Host ""

if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'Autoload' `
        -Result $(if ($script:failed -gt 0) { 'fail' } else { 'pass' }) `
        -Passed $script:passed -Total $total
}

if ($script:failed -gt 0) { exit 1 }
