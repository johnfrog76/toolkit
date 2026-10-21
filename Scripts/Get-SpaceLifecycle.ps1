<#
.SYNOPSIS
    What RetireSpace and RemoveSpace both read about a Space before they
    write anything: the Spaces this machine knows, the one you are in, which ones
    config.default.json ships, this machine's patches, and a Space's folder with
    its cards counted.
.DESCRIPTION
    Dot-sourced. Reads only; every write is Config's (Scripts/Set-ToolkitConfig.ps1).
    The list is the module's resolved one when a verb ran us, and the shipped
    config plus the hub's declarations when run alone -- the read NewSpace and
    Connect make. Re-dot-source after a Config call: Config re-imports the module,
    which resets every function a script defined (AGENTS.md, "Traps worth knowing").
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>

function Read-P20SpaceLifecycleJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (ConvertTo-P20SpaceKeys (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)) }
    catch {
        # config.local.json is said once; the shipped file and the hub's are not this warning's.
        if ((Split-Path -Leaf $Path) -eq 'config.local.json') {
            if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
            $null = Write-P20ConfigParseWarning -Path $Path -Message $_.Exception.Message
        }
        return $null
    }
}

function Get-P20SpaceLifecycleState {
    <#
      @{ Spaces; HubRoot; Active; ShippedSlugs; HubSlugs; LocalPatches } --
      LocalPatches is config.local.json's spaces.<slug> object (or $null).
    #>
    param([Parameter(Mandatory = $true)][string]$PackageRoot)
    $defaultCfg = Read-P20SpaceLifecycleJson (Join-Path $PackageRoot 'config.default.json')
    $localCfg = Read-P20SpaceLifecycleJson (Join-Path $PackageRoot 'config.local.json')
    $shipped = @()
    if ($defaultCfg -and $defaultCfg.spaces) { $shipped = @($defaultCfg.spaces | ForEach-Object { [string]$_.slug }) }

    $spaces = @()
    $hubRoot = ''
    $active = ''
    if ($global:P20Config -and $global:P20Config.Spaces) {
        $spaces = @($global:P20Config.Spaces)
        $hubRoot = [string]$global:P20Config.PromptsRoot
        $active = [string]$global:P20Config.ActiveSpace
    }
    else {
        if ($defaultCfg -and $defaultCfg.spaces) { $spaces = @($defaultCfg.spaces) }
        $hubRoot = Get-P20PromptsRoot -PackageRoot $PackageRoot
        if ($hubRoot -and (Test-P20HubRoot $hubRoot)) {
            $manifest = Read-P20HubManifest -Root $hubRoot
            foreach ($hs in @(Rename-P20LegacyHubSpaces -Spaces @($manifest.Spaces) -ShippedSlugs $shipped)) {
                if (-not (@($spaces | Where-Object { $_.slug -eq $hs.slug }).Count)) { $spaces += $hs }
            }
        }
        if ($defaultCfg -and $defaultCfg.activeSpace) { $active = [string]$defaultCfg.activeSpace }
        if ($localCfg -and $localCfg.activeSpace) { $active = [string]$localCfg.activeSpace }
        $override = Get-P20ActiveSpaceOverride
        if ($override) { $active = $override }
    }
    if ($env:PROMPTS_ROOT) { $hubRoot = Get-P20PromptsRoot -PackageRoot $PackageRoot }

    $hubSlugs = @()
    if ($hubRoot -and (Test-P20HubRoot $hubRoot)) {
        $hubCfg = Read-P20SpaceLifecycleJson (Join-Path $hubRoot (Get-P20HubManifestName))
        if ($hubCfg -and $hubCfg.spaces) {
            foreach ($h in @(Rename-P20LegacyHubSpaces -Spaces @($hubCfg.spaces | Where-Object { $_ -and $_.slug }) -ShippedSlugs $shipped)) {
                $hubSlugs += [string]$h.slug
            }
        }
    }
    $patches = $null
    if ($localCfg -and $localCfg.PSObject.Properties['spaces'] -and ($localCfg.spaces -is [System.Management.Automation.PSCustomObject])) {
        $patches = $localCfg.spaces
    }
    return @{
        Spaces       = $spaces
        HubRoot      = $hubRoot
        Active       = $active
        ShippedSlugs = $shipped
        HubSlugs     = $hubSlugs
        LocalPatches = $patches
    }
}

function Get-P20SpaceFolderCount {
    <# @{ Folder; Exists; Current; Archive; Backlog; Total; Breakdown } for one Space's cards folder. #>
    param([string]$HubRoot, $Space)
    $folderName = [string]$Space.promptsFolder
    if (-not $folderName) { $folderName = [string]$Space.slug }
    $folder = Join-Path $HubRoot $folderName
    $current = 0
    $archive = 0
    $backlog = 0
    $exists = Test-Path -LiteralPath $folder -PathType Container
    if ($exists) {
        $cur = Join-Path $folder 'current'
        $arc = Join-Path $folder 'archive'
        if (Test-Path -LiteralPath $cur) { $current = @(Get-ChildItem -LiteralPath $cur -File -Filter '*.md' -ErrorAction SilentlyContinue).Count }
        if (Test-Path -LiteralPath $arc) { $archive = @(Get-ChildItem -LiteralPath $arc -File -Filter '*.md' -ErrorAction SilentlyContinue).Count }
        $blg = Join-Path $folder 'backlog'
        if (Test-Path -LiteralPath $blg) { $backlog = @(Get-ChildItem -LiteralPath $blg -File -Filter '*.md' -ErrorAction SilentlyContinue).Count }
    }
    # backlog/ is said only when it holds a card, so a Space without one reads as it always did.
    $breakdown = "$current current, $archive archive"
    if ($backlog -gt 0) { $breakdown += ", $backlog backlog" }
    return @{ Folder = $folder; FolderName = $folderName; Exists = $exists; Current = $current; Archive = $archive; Backlog = $backlog; Total = ($current + $archive + $backlog); Breakdown = $breakdown }
}

function Get-P20SpaceLabel {
    param($Space)
    $n = [string]$Space.name
    if (-not $n) { $n = [string]$Space.slug }
    return "$n ($($Space.slug))"
}
