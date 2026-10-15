<#
.SYNOPSIS
    Validates all toolkit prerequisites and reports what's missing.
.DESCRIPTION
    Checks what the tool NEEDS -- git, a config, a hub that exists, the verbs in
    every new shell -- and states the TIER this machine runs at. What is optional
    is a note ([--]), never a warning and never a failure: az and its devops
    extension are checked only when Azure DevOps is in use (Test-AdoEnabled.ps1),
    and a machine working from its cards is told that nothing is missing.
.EXAMPLE
    {cliPrefix}Setup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}


function Show-Help {
    Write-Host @"

Test-P20Prerequisites - Validate toolkit prerequisites

USAGE:
    $(Get-CliPrefix)Setup          # Run all checks
    $(Get-CliPrefix)Setup -Help    # Show this help

CHECKS:
    git              Installed and on PATH
    az CLI           Only when Azure DevOps is in use: installed, signed in,
                     devops extension present. Missing is a note, not a failure
    posh-git         Optional -- a note when absent
    config.local     Exists; an identity, when Azure DevOps is in use
    Autoload         The verbs are in every new shell
    Key paths        PromptsRoot exists; hub.json if the hub has one

    The last line states the tier: what this machine can do as it stands.
"@
    return
}

if ($Help) { Show-Help; return }

$cfg = $global:P20Config
$toolkitFolder = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "  Prerequisite Check" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$pass = 0
$warn = 0
$fail = 0
$note = 0

function script:Write-ReportOk($msg) {
    Write-Host "  [ok] $msg" -ForegroundColor Green
    $script:pass++
}
function script:Write-ReportWarn($msg) {
    Write-Host "  [!!] $msg" -ForegroundColor Yellow
    $script:warn++
}
# Something this machine does not have and does not NEED. It is not a warning
# and never a failure: working from cards with no Azure DevOps is a supported
# way to run this tool, and the first command a new user is told to run must not
# tell them their install is broken.
function script:Write-ReportNote($msg) {
    Write-Host "  [--] $msg" -ForegroundColor DarkGray
    $script:note++
}
function script:Write-ReportFail($msg) {
    Write-Host "  [XX] $msg" -ForegroundColor Red
    $script:fail++
}

# ── Git ──────────────────────────────────────────────────────────────────────
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = (git --version) -replace 'git version ', ''
    Write-ReportOk "git $gitVersion"
}
else {
    Write-ReportFail "git not found - install from https://git-scm.com"
}

# ── Azure CLI ────────────────────────────────────────────────────────────────
# Whether Azure DevOps is part of what this machine shows at all -- one rule,
# Scripts/Test-AdoEnabled.ps1. Off, and `az` is not looked for: a machine working
# from its cards has nothing to be told about a tool it does not use.
. (Join-Path $PSScriptRoot 'Test-AdoEnabled.ps1')
# WHICH tracker the board's address names decides which tool is checked: gh on
# a GitHub board, az everywhere else --
# and the rule above reads it too, since a GitHub tracker is not Azure DevOps.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
$trackerKind = Resolve-P20Tracker -OrgUrl $cfg.Org
$adoFlag = $null
if (Get-Command Get-P20Features -ErrorAction SilentlyContinue) {
    $features = Get-P20Features
    if ($features -and $features.ContainsKey('ado')) { $adoFlag = $features['ado'] }
}
$adoEnabled = Test-P20AdoEnabled -OrgStatus $cfg.OrgStatus -Flag $adoFlag -Tracker $trackerKind
$hasAz = [bool](Get-Command az -ErrorAction SilentlyContinue)
$azLoggedIn = $false
$hasGh = $false
$ghSignedIn = $false

# A connected GitHub Space is asked about gh, whatever the Azure DevOps answer:
# the tracker is the Space's, the flag is the person's, and gh is not az.
if ($trackerKind -eq 'github' -and $cfg.OrgStatus -eq 'active') {
    $hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    if ($hasGh) {
        $ghVersion = ((gh --version 2>$null | Select-Object -First 1) -replace 'gh version ', '') -replace ' \(.*', ''
        Write-ReportOk "gh CLI $ghVersion"
        $null = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ghLogin = [string](gh api user -q .login 2>$null)
            if ($LASTEXITCODE -eq 0 -and $ghLogin) { Write-ReportOk "gh signed in as $ghLogin" }
            else { Write-ReportOk "gh signed in" }
            $ghSignedIn = $true
        }
        else {
            Write-ReportWarn "gh CLI not signed in - run: gh auth login"
        }
    }
    else {
        # Optional, like az: a note, never a failure.
        Write-ReportNote "gh CLI not found -- optional. Cards, the board, Daily and Sync all work without it; the GitHub verbs will say they are unavailable. To plug it in: https://cli.github.com"
    }
}
elseif (-not $adoEnabled) {
    Write-ReportNote "Azure DevOps: not in use here -- this Space works from its cards. Nothing to install."
}
elseif ($hasAz) {
    $azVersion = (az version --output json 2>$null | ConvertFrom-Json).'azure-cli'
    Write-ReportOk "az CLI $azVersion"

    $azAccount = az account show --output json 2>$null | ConvertFrom-Json
    if ($azAccount) {
        Write-ReportOk "az logged in as $($azAccount.user.name)"
        $azLoggedIn = $true
    }
    else {
        Write-ReportWarn "az CLI not logged in - run: az login"
    }

    $devopsExt = az extension show --name azure-devops --output json 2>$null | ConvertFrom-Json
    if ($devopsExt) {
        Write-ReportOk "az devops extension installed"
    }
    else {
        Write-ReportWarn "az devops extension missing - run: az extension add --name azure-devops"
    }
}
else {
    # Optional, so a note. It used to be Write-ReportFail, which made a correctly
    # installed Tier-2 machine read as broken.
    $azUrl = if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'https://aka.ms/installazurecliwindows' } else { 'https://docs.microsoft.com/cli/azure/install-azure-cli' }
    Write-ReportNote "az CLI not found -- optional. Cards, the board, Daily and Sync all work without it; the Azure DevOps verbs will say they are unavailable. To plug it in: $azUrl"
}

# ── posh-git ─────────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable -Name posh-git) {
    Write-ReportOk "posh-git available"
}
elseif ((($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) -and (Test-Path 'C:\tools\poshgit')) {  # portability-ok: chocolatey's fixed install location, not a personal path; export:example
    Write-ReportOk "posh-git (choco install)"
}
else {
    # Prompt decoration. Nice to have, never needed: a note, not a warning.
    Write-ReportNote "posh-git not found -- optional (branch name in the prompt): Install-Module posh-git -Scope CurrentUser"
}

# ── config.local.json ────────────────────────────────────────────────────────
$localConfigPath = Join-Path $toolkitFolder 'config.local.json'
if (Test-Path $localConfigPath) {
    Write-ReportOk "config.local.json exists"
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
    $localCfg = Read-P20LocalConfigJson -Path $localConfigPath
    if ($localCfg -and -not [string]::IsNullOrWhiteSpace($localCfg.email)) {
        Write-ReportOk "identity: $($localCfg.email) (config)"
    }
    else {
        # Resolving an identity means starting `az`. With Azure DevOps not in use
        # there is nobody to assign anything to, so az is not started at all.
        $derived = ''
        if ($adoEnabled) { $derived = Resolve-P20Identity }
        if ($derived) {
            Write-ReportOk "identity: $derived (from az; set 'email' in config.local.json to override)"
        }
        else {
            if ($adoEnabled) {
                Write-ReportWarn "no identity - new work items cannot be auto-assigned. Run az login, or set 'email' in config.local.json"
            }
            else {
                # Identity is who a WORK ITEM is assigned to. No Azure DevOps, no question.
                Write-ReportNote "identity: not set -- only Azure DevOps uses it"
            }
        }
    }
}
else {
    # It named a bootstrap.ps1 that this package has never had.
    Write-ReportWarn "config.local.json not found - run '$(Get-CliPrefix)Start' for a hub of sample cards, or '$(Get-CliPrefix)Config -Set promptsRoot=<path>' to point at your own"
}

# ── PromptsRoot ──────────────────────────────────────────────────────────────
if ($cfg.PromptsRoot -and (Test-Path $cfg.PromptsRoot)) {
    Write-ReportOk "PromptsRoot: $($cfg.PromptsRoot)"
}
elseif ($cfg.PromptsRoot) {
    Write-ReportFail "PromptsRoot path does not exist: $($cfg.PromptsRoot)"
}
else {
    Write-ReportWarn "PromptsRoot not configured"
}

# -- hub.json -----------------------------------------------------------------
# Whether the hub declared Spaces of its own. Never a failure: a hub with no
# manifest is the ordinary case and every Space then comes from config alone.
if ($cfg.HubManifest) {
    $hubSpaceWord = 'Spaces'
    if ($cfg.HubSpaceCount -eq 1) { $hubSpaceWord = 'Space' }
    Write-ReportOk "hub.json: read, $($cfg.HubSpaceCount) $hubSpaceWord declared ($($cfg.HubManifestPath))"
}
else {
    Write-ReportOk "hub.json: none -- Spaces come from config alone"
}

# -- The container's spelling (stage 3) ----------------------------------
# The files say `spaces` and `activeSpace`; a file that still says `orgs` or
# `activeOrg` is read exactly the same and is rewritten in the new spelling the
# next time Config or Sync writes it. Never a failure -- a note, so a machine can
# say which of its files has not been written since the rename.
foreach ($spelledFile in @($localConfigPath, $cfg.HubManifestPath)) {
    if (-not $spelledFile -or -not (Test-Path $spelledFile)) { continue }
    $spelledRaw = Get-Content $spelledFile -Raw -ErrorAction SilentlyContinue
    if ($spelledRaw -match '"(orgs|activeOrg)"\s*:') {
        Write-ReportNote "$(Split-Path -Leaf $spelledFile) still says orgs/activeOrg -- read the same; written as spaces/activeSpace the next time $(Get-CliPrefix)Config or $(Get-CliPrefix)Sync writes it"
    }
}

# -- Autoload ------------------------------------------------------------------
# The documented install is InstallAutoload: a shim module on PSModulePath, so
# every new shell has the verbs with no profile line at all. This check used to
# look for "utilities.psm1" in $PROFILE and tell a correctly installed machine to
# run a bootstrap.ps1 that does not exist. A profile import still counts -- it
# is how some machines were set up, and it works.
# WHICH toolkit, not whether "a" toolkit: two checkouts imported into one session
# and whichever registered last owns the names (AGENTS.md, "One toolkit per
# shell"). This check used to match the substring 'utilities.psm1' anywhere in the
# profile and any module called Prompt20Toolkit on the path, so a machine whose
# profile imported a different repo's toolkit read [ok].
$modulePath = Join-Path $toolkitFolder 'utilities.psm1'
function script:ConvertTo-ComparablePath([string]$Path) {
    if (-not $Path) { return '' }
    $full = $Path
    try { if (Test-Path -LiteralPath $Path) { $full = (Get-Item -LiteralPath $Path).FullName } } catch { $null = $_ }
    return ($full -replace '\\', '/').TrimEnd('/').ToLowerInvariant()
}
function script:Resolve-ShimTarget($Module) {
    # What Prompt20Toolkit.psm1 does: the sibling of the shim's folder, else
    # WS_ROOT/toolkit. A symlinked shim resolves through its link target.
    $base = $Module.ModuleBase
    try {
        $item = Get-Item -LiteralPath $base -ErrorAction Stop
        $target = $null
        if ($item.PSObject.Properties['LinkTarget'] -and $item.LinkTarget) { $target = [string]$item.LinkTarget }
        elseif ($item.PSObject.Properties['Target'] -and $item.Target) { $target = [string](@($item.Target)[0]) }
        if ($target) { $base = $target }
    }
    catch { $null = $_ }
    $sibling = Join-Path (Split-Path $base -Parent) 'utilities.psm1'
    if (Test-Path -LiteralPath $sibling) { return $sibling }
    $wsRoot = if ($env:WS_ROOT) { $env:WS_ROOT } elseif (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { 'C:\ws' } else { Join-Path $HOME 'Repos' }  # portability-ok: the shim's own fallback (Prompt20Toolkit.psm1), mirrored so Setup resolves a copied shim the way the shim does; export:example
    return (Join-Path (Join-Path $wsRoot 'toolkit') 'utilities.psm1')
}
$thisModule = ConvertTo-ComparablePath $modulePath
$shims = @(Get-Module -ListAvailable -Name 'Prompt20Toolkit' -ErrorAction SilentlyContinue)
$shimOurs = $null
$shimOther = $null
foreach ($shim in $shims) {
    $target = Resolve-ShimTarget $shim
    if ((ConvertTo-ComparablePath $target) -eq $thisModule) { if (-not $shimOurs) { $shimOurs = $shim } }
    elseif (-not $shimOther) { $shimOther = @{ Module = $shim; Target = $target } }
}
$profileImports = $false
$profileOther = ''
foreach ($profilePath in @($PROFILE)) {
    if ($profilePath -and (Test-Path $profilePath)) {
        $profileText = Get-Content $profilePath -Raw
        foreach ($hit in [regex]::Matches($profileText, '[^\s''"]*utilities\.psm1')) {
            if ((ConvertTo-ComparablePath $hit.Value) -eq $thisModule) { $profileImports = $true }
            elseif (-not $profileOther) { $profileOther = $hit.Value }
        }
    }
}
if ($shimOurs) {
    Write-ReportOk "autoload installed -- this checkout's verbs are in every new shell ($($shimOurs.ModuleBase))"
}
elseif ($profileImports) {
    Write-ReportOk "PS profile imports this toolkit ($modulePath)"
}
else {
    Write-ReportWarn "the verbs are in THIS shell only - run '$(Get-CliPrefix)InstallAutoload' to have them in every new one"
}
if ($shimOther) {
    Write-ReportWarn "a Prompt20Toolkit shim at $($shimOther.Module.ModuleBase) loads a DIFFERENT toolkit ($($shimOther.Target)) -- one toolkit per shell; '$(Get-CliPrefix)InstallAutoload -Force' points it here"
}
if ($profileOther) {
    Write-ReportWarn "the PS profile imports a DIFFERENT toolkit ($profileOther) -- whichever registers last owns the $(Get-CliPrefix)* names; remove the line or point it at $modulePath"
}

# The assistant's copy of AGENTS.md: generated per machine, outside the tree, so
# only the machine can say it is behind. Silent when no copy was ever generated.
$agentDocs = Join-Path $PSScriptRoot 'Update-AgentDocs.ps1'
if (Test-Path $agentDocs) {
    $agentDocsOut = & $agentDocs -Check 6>&1 | Out-String
    if ($LASTEXITCODE -eq 1) {
        Write-ReportWarn "the agent guidance on this machine is behind AGENTS.md - run 'pwsh ./Scripts/Update-AgentDocs.ps1'"
    }
    elseif ($agentDocsOut -match '\[ok\]') {
        Write-ReportOk "agent guidance matches AGENTS.md"
    }
    $global:LASTEXITCODE = 0
}

# -- The spec's own self-checks: C2, C4, C8 ------------------------------------
# Each failure is loud the first time the thing is used; Setup is where a new
# machine is told BEFORE that.

# C2: every registered verb resolves to a function that exists.
$unresolved = @()
$registered = 0
if (Get-Command Get-P20CommandMap -ErrorAction SilentlyContinue) {
    $map = Get-P20CommandMap | ConvertFrom-Json
    foreach ($prop in $map.PSObject.Properties) {
        # `_timeouts` is the map's one reserved key (Get-P20CommandMap), a table
        # rather than a function name: counting it inflated the total, and handing
        # it to Get-Command is not a question about a verb.
        if ($prop.Name -eq '_timeouts') { continue }
        $registered++
        # An empty target is a verb that resolves to nothing, and says so here --
        # Get-Command -Name refuses it with a raw error record, which printed red
        # above an [ok] line that had not checked it.
        if ([string]::IsNullOrWhiteSpace([string]$prop.Value) -or -not (Get-Command $prop.Value -ErrorAction SilentlyContinue)) { $unresolved += "$($prop.Name) -> $($prop.Value)" }
    }
    foreach ($alias in @(Get-Alias -Name "$(Get-CliPrefix)*" -ErrorAction SilentlyContinue)) {
        if ($map.PSObject.Properties[$alias.Name.Substring((Get-CliPrefix).Length)]) { continue }
        $registered++
        if ([string]::IsNullOrWhiteSpace($alias.Definition) -or -not (Get-Command $alias.Definition -ErrorAction SilentlyContinue)) { $unresolved += "$($alias.Name) -> $($alias.Definition)" }
    }
}
if ($unresolved.Count -gt 0) {
    Write-ReportFail "$($unresolved.Count) registered command(s) resolve to nothing -- a broken install: $($unresolved -join ', ')"
}
else {
    Write-ReportOk "every registered command resolves ($registered checked)"
}

# C4: the template every card type is scaffolded from is present.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
$templatesDir = Join-Path $toolkitFolder 'templates'
$missingTemplates = @()
$typeTable = Get-P20WorkItemTypes -Config $cfg
foreach ($typeName in $typeTable.Keys) {
    $tpl = $typeTable[$typeName].Template
    if ($tpl -and -not (Test-Path (Join-Path $templatesDir $tpl))) { $missingTemplates += "$typeName ($tpl)" }
}
if ($missingTemplates.Count -gt 0) {
    Write-ReportFail "card template(s) missing from $templatesDir -- $($missingTemplates -join ', '); '$(Get-CliPrefix)NewPrompt' cannot scaffold that type"
}
else {
    Write-ReportOk "card templates present for every type ($($typeTable.Count)) in $templatesDir"
}

# C8: the usage log can be written where the module will write it.
$logDirForCheck = ''
if (Get-Command Get-P20ToolkitLogDir -ErrorAction SilentlyContinue) { $logDirForCheck = Get-P20ToolkitLogDir }
if ($logDirForCheck) {
    $logProbe = Join-Path $logDirForCheck ".setup-write-probe-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $logWritable = $false
    try {
        [System.IO.File]::WriteAllText($logProbe, 'probe')
        $logWritable = $true
    }
    catch { $logWritable = $false }
    finally { Remove-Item $logProbe -Force -ErrorAction SilentlyContinue }
    if ($logWritable) { Write-ReportOk "log path writable: $logDirForCheck" }
    else { Write-ReportFail "log path is not writable: $logDirForCheck -- every verb records itself there ('$(Get-CliPrefix)Log'); P20_USAGE_LOG_DIR moves it" }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
$total = $pass + $warn + $fail
Write-Host "  Results: $pass passed, $warn warnings, $fail failed (of $total checks)" -ForegroundColor $(
    if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' }
)
if ($note -gt 0) {
    $noteWord = 'notes'; if ($note -eq 1) { $noteWord = 'note' }
    Write-Host "  $note $noteWord ([--]): things this machine does not have and does not need." -ForegroundColor DarkGray
}

# The tier, STATED. Setup never said the word, so a machine with no `az` was
# told what it lacked and never what it could do. No network call is made here:
# whether Azure DevOps actually answers is Env's live probe, and the line says so.
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
$p = Get-CliPrefix
if (-not $hasGit) {
    Write-Host "  Tier 3: git is missing -- ${p}Menu and the tests work. Install git for the rest." -ForegroundColor Yellow
}
elseif (-not $adoEnabled) {
    Write-Host "  Working from your cards (Tier 2): ${p}NewPrompt -Title, ${p}Archive, ${p}Billable, ${p}Status, ${p}Sync and the web UI. Nothing is missing." -ForegroundColor Green
}
else {
    # The words follow the board's tracker: gh and GitHub on a GitHub board,
    # az and Azure DevOps everywhere else.
    $sumTracker = if ($trackerKind -eq 'github') { 'GitHub' } else { 'Azure DevOps' }
    $sumTool = if ($trackerKind -eq 'github') { 'gh' } else { 'az' }
    $toolReady = if ($trackerKind -eq 'github') { $hasGh -and $ghSignedIn } else { $hasAz -and $azLoggedIn }
    if (-not $toolReady) {
        Write-Host "  Tier 2: the local workflow -- ${p}NewPrompt -Title, ${p}Archive, ${p}Billable, ${p}Status, ${p}Sync and the web UI. The $sumTracker verbs need $sumTool, signed in." -ForegroundColor Green
    }
    else {
        Write-Host "  Tier 1 if $sumTracker answers -- ${p}Env makes the live check." -ForegroundColor Green
    }
}
Write-Host ""
# The last test run on this machine, all three halves: what
# test-summary.<machine>.json says, read through the one rule {cliPrefix}Test
# writes it with. Information, not a check -- it moves no count above.
. (Join-Path $PSScriptRoot 'TestAll-Rules.ps1')
$testRecords = Get-P20TestHalfRecords -Summary (Read-P20TestSummary -Path (Get-P20TestSummaryPath -PackageRoot $toolkitFolder))
if ($testRecords.Count -eq 0) {
    Write-Host "  Tests: none recorded on this machine -- $(Get-CliPrefix)Test runs all three halves." -ForegroundColor DarkGray
}
else {
    $testParts = @()
    foreach ($h in (Get-P20TestHalves)) {
        if (-not $testRecords.Contains($h)) { $testParts += "$h not run"; continue }
        $r = $testRecords[$h]
        if ($r['result'] -eq 'skip') { $testParts += "$h skipped ($($r['reason']))" }
        else { $testParts += "$h $($r['result']) $($r['passed'])/$([int]$r['passed'] + [int]$r['failed'])" }
    }
    Write-Host "  Tests, last run on this machine: $($testParts -join '; ') -- $(Get-CliPrefix)Test runs all three." -ForegroundColor DarkGray
}
Write-Host ""
# This command checks what the tool NEEDS. What it optionally has -- the modules,
# the nav shortcuts, the two environment gates -- is the other report, and a
# fresh machine is exactly the reader who should be told it exists
# (AGENTS.md, "Opt in by configuration").
Write-Host "  Optional surfaces (modules, nav shortcuts, the environment gates): $(Get-CliPrefix)Env" -ForegroundColor DarkGray
Write-Host ""
