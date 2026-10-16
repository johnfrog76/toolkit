<#
.SYNOPSIS
    StampDesign -- give every design note and spec an id (the Studio, core).

.DESCRIPTION
    The design lifecycle's identity (L1; docs/hub/design.md, "The file"). A design is identified by a UUID in its file's frontmatter,
    `id: <uuid>`; a spec carries the SAME id as the note it graduated from.
    This verb is how a product that already has design/ and spec/ joins: it
    walks design/, design/archive/, spec/ and spec/archive/ (those that exist)
    and, for every markdown file with no `id:` in its frontmatter, adds one --
    creating a frontmatter block when the file has none.

    PAIRING. A spec and a note that share a stem are one design:
    design/<stem>.md <-> spec/<stem>.spec.md. They get one id.
    If either already carries one, the other takes it; if both do and they
    differ, both are left alone and the disagreement is printed.

    It never changes an id that is present, never writes a file it did not
    change, and is idempotent: a second run writes nothing. Files are written
    through Write-CardText without -New, so each keeps its own line endings.
    README.md in those folders is not a design and is skipped.

    WHERE. By default the git root of the CURRENT directory (stated on the
    first line of output), which must hold design/. -Hub works on the hub's
    design/ and spec/ instead -- at the hub's root, and inside any Space folder
    that has them. Never both, never guessed. -WhatIf names every file it would
    write and writes none.

.PARAMETER Hub
    Stamp the hub's design/ and spec/ folders instead of the current repository.

.PARAMETER WhatIf
    Print every file that would be stamped; write nothing.

.EXAMPLE
    {cliPrefix}StampDesign -WhatIf
.EXAMPLE
    {cliPrefix}StampDesign
.EXAMPLE
    {cliPrefix}StampDesign -Hub

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Hub,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}StampDesign -- give every design note and spec an id" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}StampDesign [-Hub] [-WhatIf]"
    Write-Host ""
    Write-Host "  Adds id: <uuid> to the frontmatter of every markdown file in design/, design/archive/,"
    Write-Host "  spec/ and spec/archive/ that has none. A spec shares its note's id (same file stem)."
    Write-Host "  Never changes an id that is there; a second run writes nothing."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
$consts = Get-P20Consts
$idKey = $consts.design.idKey
$archiveName = $consts.folders.archive

# -- Where: the repository we stand in, or the hub -----------------------------------
# A tree is one place that holds a design/ and a spec/ side by side: a repo's
# root, the hub's root, or a Space's folder inside the hub.
$trees = @()
if ($Hub) {
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
    if (-not (Test-P20HubRoot $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    # Get-P20PromptsRoot has already expanded a Windows 8.3 short name; the git
    # root below has not, so both go through the one expansion.
    $promptsRoot = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $promptsRoot).Path
    Write-Host "Hub: $promptsRoot"
    $trees += @{
        Label  = 'the hub'
        Base   = $promptsRoot
        Design = Get-P20HubFolder -Name 'design' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
        Spec   = Get-P20HubFolder -Name 'spec' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
    }
    # A Space's own design/ and spec/ (D-DL17): one level down, same names.
    # Only a DECLARED Space's folder: growth/, manager/ and the other hub-root
    # siblings are module data, not products.
    $seenFolders = @{}
    $declared = @()
    if ($global:P20Config -and $global:P20Config.Spaces) { $declared = @($global:P20Config.Spaces) }
    foreach ($space in $declared) {
        $folder = [string]$space.promptsFolder
        if (-not $folder) { $folder = [string]$space.slug }
        if (-not $folder -or $seenFolders.ContainsKey($folder)) { continue }
        $seenFolders[$folder] = $true
        $spaceDir = Join-Path $promptsRoot $folder
        $d = Join-Path $spaceDir 'design'
        $s = Join-Path $spaceDir 'spec'
        if ((Test-Path -LiteralPath $d -PathType Container) -or (Test-Path -LiteralPath $s -PathType Container)) {
            $trees += @{ Label = $folder; Base = $promptsRoot; Design = $d; Spec = $s }
        }
    }
    $any = @($trees | Where-Object { (Test-Path -LiteralPath $_.Design -PathType Container) -or (Test-Path -LiteralPath $_.Spec -PathType Container) })
    if ($any.Count -eq 0) {
        Write-CliError -Message "The hub has no design/ or spec/ folder to stamp: $promptsRoot" `
            -Hint "$(Get-CliPrefix)NewDesign -Title ""..."" creates the first note; a Space's own design/ and spec/ are read too."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
else {
    $top = ''
    try { $top = "$(git rev-parse --show-toplevel 2>$null)".Trim() } catch { $top = '' }
    if (-not $top) {
        Write-CliError -Message "$((Get-Location).Path) is not inside a git repository." `
            -Hint "Run it from the repository whose design/ you mean to stamp, or use -Hub for the hub's."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $top = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $top).Path
    Write-Host "Git root: $top"
    if (-not (Test-Path -LiteralPath (Join-Path $top 'design') -PathType Container)) {
        Write-CliError -Message "$top has no design/ folder." `
            -Hint "Stamp a repository that keeps its designs in design/ (spec/ beside it), or use -Hub for the hub's."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $trees += @{ Label = 'this repository'; Base = $top; Design = (Join-Path $top 'design'); Spec = (Join-Path $top 'spec') }
}

# -- Reading a file's identity -------------------------------------------------------
# Get-P20FrontEnd and Get-P20FileId are the tree reader's (Read-DesignTree.ps1):
# one reader of a file's frontmatter for the stamp, the surfaces row, the state
# rule and, when it is built, MoveDesign.
. (Join-Path $PSScriptRoot 'Read-DesignTree.ps1')

function Add-P20Id {
    # The text with `id: <uuid>` as the first frontmatter line -- a block is
    # created when there is none. Written with LF; Write-CardText gives the
    # file back its own endings.
    param([string]$Text, [string]$Id)
    $normal = $Text -replace "`r`n", "`n"
    if ($normal.Length -gt 0 -and $normal[0] -eq [char]0xFEFF) { $normal = $normal.Substring(1) }
    $lines = $normal -split "`n"
    $end = Get-P20FrontEnd -Lines $lines
    if ($end -ge 0) {
        $out = @($lines[0], "${idKey}: $Id") + @($lines[1..($lines.Count - 1)])
        return ($out -join "`n")
    }
    return "---`n${idKey}: $Id`n---`n`n$normal"
}

function Get-P20RelPath {
    param([string]$Base, [string]$Path)
    $b = $Base.TrimEnd('\', '/')
    $rel = $Path.Substring($b.Length).TrimStart('\', '/')
    return ($rel -replace '\\', '/')
}

# -- Walk each tree, group by stem, stamp ----------------------------------------------
$stamped = 0
$alreadyHad = 0
$conflicts = 0
$verb = if ($WhatIf) { 'would stamp' } else { 'stamped' }

foreach ($tree in $trees) {
    $files = @()
    foreach ($spot in @(
            @{ Dir = $tree.Design; Kind = 'note' },
            @{ Dir = (Join-Path $tree.Design $archiveName); Kind = 'note' },
            @{ Dir = $tree.Spec; Kind = 'spec' },
            @{ Dir = (Join-Path $tree.Spec $archiveName); Kind = 'spec' })) {
        if (-not (Test-Path -LiteralPath $spot.Dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $spot.Dir -Filter '*.md' -File | Sort-Object Name)) {
            if ($f.Name -ieq 'README.md') { continue }
            $stem = $f.Name.Substring(0, $f.Name.Length - 3)
            if ($spot.Kind -eq 'spec' -and $stem.EndsWith('.spec')) { $stem = $stem.Substring(0, $stem.Length - 5) }
            $text = [System.IO.File]::ReadAllText($f.FullName)
            $files += [pscustomobject]@{ Path = $f.FullName; Stem = $stem; Text = $text; Id = (Get-P20FileId -Text $text) }
        }
    }

    foreach ($group in @($files | Group-Object Stem)) {
        $members = @($group.Group)
        $present = @($members | Where-Object { $null -ne $_.Id } | ForEach-Object { $_.Id } | Select-Object -Unique)
        if ($present.Count -gt 1) {
            $conflicts++
            Write-Host "  conflict: '$($group.Name)' carries $($present.Count) different ids; left alone" -ForegroundColor Yellow
        }
        $pairId = $null
        if ($present.Count -ge 1) { $pairId = $present[0] }
        foreach ($m in $members) {
            if ($null -ne $m.Id) { $alreadyHad++; continue }
            if (-not $pairId) { $pairId = [guid]::NewGuid().ToString() }
            $rel = Get-P20RelPath -Base $tree.Base -Path $m.Path
            Write-Host ("  {0} {1}  {2}" -f $verb, $rel, $pairId.Substring(0, [Math]::Min(8, $pairId.Length)))
            if (-not $WhatIf) {
                Write-CardText -Path $m.Path -Content (Add-P20Id -Text $m.Text -Id $pairId)
            }
            $stamped++
        }
    }
}

$summary = "$($verb.Substring(0,1).ToUpper())$($verb.Substring(1)) $stamped file$(if ($stamped -ne 1) { 's' }); $alreadyHad already had an id."
if ($conflicts -gt 0) { $summary += " $conflicts pair$(if ($conflicts -ne 1) { 's' }) disagree." }
Write-Host $summary -ForegroundColor Green
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)StampDesign" -Detail "$verb $stamped"
}
exit 0
