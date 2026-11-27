<#
.SYNOPSIS
    OrgChart -- the org's tree, one line per seat (the Team Agile add-on).

.DESCRIPTION
    Prints the tree in use from the hub's org file (consts.json org.file, at the
    hub root beside hub.json; docs/hub/org.md): the positions the org has, who
    each reports to, and which model or person sits in each seat. One line per
    seat, "Position . model [space] (session)", indented by level, with
    ". merges" after the seat that holds the merge; a seat's own roleTitle
    stands in for the position's title, a vacant seat says vacant, the owner's
    line shows the person, and a position with no seats is a pool, one line with
    its default-model text. No machine is printed: a machine is not a boundary
    in an org.

    -AsJson prints the response the agent serves, as one JSON document:
    docs/hub/org.md, "The response".

    Reads one file and writes nothing: not the hub, not the tracker. The file is
    checked first (a duplicate id, a reportsTo that names no position, a loop,
    not exactly one root, a prompt that is not in the hub's agentic folder), and
    a file that fails is a stated refusal naming what is wrong.

.PARAMETER Tree
    A tree of the file other than the one it names as active, by id.
.PARAMETER AsJson
    Print the response the agent serves instead of the text.

.EXAMPLE
    {cliPrefix}OrgChart
.EXAMPLE
    {cliPrefix}OrgChart -AsJson
.EXAMPLE
    {cliPrefix}OrgChart -Tree branch

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Tree,
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}OrgChart -- the org's tree, one line per seat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}OrgChart [-Tree <id>] [-AsJson]"
    Write-Host ""
    Write-Host "  The positions the org has and who sits in each seat, from the hub's org file. Writes nothing."
    Write-Host "  -Tree prints another tree of the file by id; -AsJson prints what the agent serves."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Read-OrgChart.ps1')

$p = Get-CliPrefix
$fileName = Get-P20OrgFileName
$cfg = $global:P20Config

# "The hub resolved" is not "a hub was configured": with nothing said anywhere the
# module falls back to the folder above the package, and an org file is not read
# from a folder nobody named.
$hubRoot = ''
if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
if (-not (Get-P20ConfiguredHub -PackageRoot $repoRoot)) {
    Write-CliError -Message "No hub is configured, so there is no $fileName to read." `
        -Hint "Point the toolkit at your hub with '${p}Config -Set promptsRoot=<folder>'; the chart is $fileName at its root (docs/hub/org.md)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not (Test-P20HubRoot $hubRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $hubRoot)
    exit 2  # stated refusal
}

$read = Read-P20OrgChart -PromptsRoot $hubRoot -PackageRoot $repoRoot -TreeId ([string]$Tree).Trim()

foreach ($warning in @($read.Warnings)) {
    Write-Warning $warning
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type WARN -Source $fileName -Detail $warning
    }
}

if ($read.Status -eq 'missing') {
    Write-CliError -Message "There is no $fileName in the hub: $($read.Path) would hold the org chart." `
        -Hint "Start one with '${p}Staff -Preset S|M|L', or create it at the hub root, beside hub.json. docs/hub/org.md has the shape and an example; samples/hub/$fileName is a small one to copy."
    exit 2  # stated refusal
}
if ($read.Status -ne 'ok') {
    Write-CliError -Message "$($read.Path): $($read.Message)" `
        -Hint "Fix the file and run ${p}OrgChart again; docs/hub/org.md lists what is checked."
    exit 2  # stated refusal
}

if ($AsJson) {
    Write-Output ($read.Chart | ConvertTo-Json -Depth 10)
    return
}

$chart = $read.Chart
$header = "Org chart: $($chart.tree.title) ($($chart.tree.id))"
if ($chart.tree.id -ne $chart.activeTree) { $header += " -- not the tree in use ($($chart.activeTree))" }
Write-Output $header
# A file of several trees lists them, each with its state: active, draft (saved,
# never in use) or inactive (in use before) -- docs/hub/org.md, "An org's state".
if (@($read.Trees).Count -gt 1) {
    Write-Output ("Trees: " + ((@($read.Trees) | ForEach-Object { "$($_.id) ($($_.state))" }) -join ', '))
}
Write-Output ''
foreach ($line in (Format-P20OrgChartLines -Chart $chart)) { Write-Output $line }
