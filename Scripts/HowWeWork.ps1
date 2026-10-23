<#
.SYNOPSIS
    HowWeWork -- write a Space's how-we-work note, once, from the shipped template.
.DESCRIPTION
    The orchestrating answer to "How do you want to work in <Space>?" (agents)
    is the one with a file: the seats, the loop, the hand-off, relay and
    stand-in rules, named as roles and loops and never as models or machines.
    This verb writes it to the Space's folder in the hub, at
    consts.json startWork.howWeWorkNote (agentic/how-we-work.md), from the
    package's agentic/how-we-work.template.md with the Space's name and tracker
    filled in, through Write-CardText -New (UTF-8, no BOM, LF). StartWork quotes
    it as section one of the hand-off block; the Studio's Prompts card lists it.

    It never writes over the note: a file that is already there is a person's,
    and the verb refuses naming its path (exit 2). For a Space whose answer is
    alone or team -- worked out by Scripts/Resolve-HowIWork.ps1, the one table --
    it says so and writes nothing. It prints the one line to paste into the
    repository's AGENTS.md; ToolKit never writes into a product's repository.
.PARAMETER Slug
    The Space whose note to write.
.PARAMETER WhatIf
    Print the path and the text it would write; write nothing.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Slug,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

foreach ($helper in @('Resolve-CliPrefix.ps1', 'Resolve-HubConfig.ps1', 'Get-SpaceLifecycle.ps1', 'Get-Consts.ps1', 'Resolve-Tracker.ps1', 'Resolve-HowIWork.ps1', 'Write-CardText.ps1')) {
    . (Join-Path $scriptsDir $helper)
}
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
$prefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
if (-not $prefix) { $prefix = Resolve-P20ConfigPrefix -PackageRoot $packageRoot }

if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}HowWeWork -- write a Space's how-we-work note, once" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    ${prefix}HowWeWork <slug> [-WhatIf]"
    Write-Host ""
    Write-Host "  For a Space worked with agents: the seats, the loop and the rules, from the shipped template,"
    Write-Host "  into the Space's folder in the hub. Never over a file that is there. ${prefix}StartWork quotes it."
    Write-Host ""
    exit 0
}

$c = Get-P20Consts
$noteRel = [string]$c.startWork.howWeWorkNote
$templatePath = Join-Path $packageRoot 'agentic/how-we-work.template.md'

$state = Get-P20SpaceLifecycleState -PackageRoot $packageRoot
$knownSlugs = @($state.Spaces | ForEach-Object { [string]$_.slug })

$typed = ([string]$Slug).Trim()
if (-not $typed) {
    Write-CliError -Message "Say which Space: ${prefix}HowWeWork <slug>." -Hint "The Spaces are: $($knownSlugs -join ', ')."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$target = Resolve-P20RenamedSlug -Slug $typed -Slugs $knownSlugs
if ($target -ne $typed) { Write-Host "  $(Get-P20RenamedSlugNote -From $typed -To $target)" -ForegroundColor Yellow }
$space = $state.Spaces | Where-Object { [string]$_.slug -eq $target } | Select-Object -First 1
if (-not $space) {
    Write-CliError -Message "'$typed' is not a Space this machine knows." -Hint "The Spaces are: $($knownSlugs -join ', ')."
    exit 2  # stated refusal
}
if (-not (Test-P20HubRoot $state.HubRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $state.HubRoot)
    exit 2  # stated refusal
}

$label = Get-P20SpaceLabel $space
$spaceName = [string]$space.name
if (-not $spaceName) { $spaceName = $target }
$org = [string]$space.org
$stored = ''
if ($space.PSObject.Properties['howIWork']) { $stored = [string]$space.howIWork }
$how = Resolve-P20HowIWork -OrgUrl $org -Stored $stored

# Only the orchestrating answer has a file to write.
if ($how.answer -ne 'agents') {
    $words = 'alone'
    if ($how.answer -eq 'team') { $words = 'on a team' }
    Write-Host ""
    Write-Host "  $label is worked $words ($($how.source)): only the orchestrating answer, agents, has a how-we-work note. Nothing written." -ForegroundColor DarkGray
    if (-not $how.locked) {
        Write-Host "  To work it with agents: ${prefix}Config -Set spaces.$target.howIWork=agents -Hub, then ${prefix}HowWeWork $target"
    }
    Write-Host ""
    exit 0
}

$folder = (Get-P20SpaceFolderCount -HubRoot $state.HubRoot -Space $space).Folder
$notePath = Join-Path $folder $noteRel
if (Test-Path -LiteralPath $notePath) {
    Write-CliError -Message "$notePath is already there; ${prefix}HowWeWork never writes over it." `
        -Hint 'It is the team''s to edit. To start it over from the template, move or delete the file first, on purpose.'
    exit 2  # stated refusal
}
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    Write-CliError -Message "The template is not in this package: $templatePath." -Hint "Restore it from the package's repository (agentic/how-we-work.template.md)."
    exit 2  # stated refusal
}

# The tracker in words: a GitHub Space's address names its repository (or its owner).
$tracker = 'GitHub'
$m = [regex]::Match($org, '^https?://github\.com/([^/\s]+)(?:/([^/\s]+?))?(?:\.git)?/?$', 'IgnoreCase')
if ($m.Success -and $m.Groups[2].Success) { $tracker = "GitHub, ``$($m.Groups[1].Value)/$($m.Groups[2].Value)``" }
elseif ($m.Success) { $tracker = "GitHub, ``$($m.Groups[1].Value)``" }

$text = [System.IO.File]::ReadAllText($templatePath).Replace('{space}', $spaceName).Replace('{tracker}', $tracker)
$pasteLine = ([string]$c.startWork.howWeWorkLine).Replace('{path}', $notePath)

if ($WhatIf) {
    Write-Host ""
    Write-Host "  [WhatIf] would write $notePath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host $text.Replace("`r`n", "`n").TrimEnd()
    Write-Host ""
    Write-Host "  [WhatIf] and print the line to paste into the repository's AGENTS.md:" -ForegroundColor Yellow
    Write-Host "    $pasteLine"
    Write-Host ""
    exit 0
}

$dir = Split-Path -Parent $notePath
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Write-CardText -Path $notePath -Content $text -New
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "${prefix}HowWeWork" -Detail "$target -> $notePath"
}

Write-Host ""
Write-Host "  [+] Wrote how we work in $label" -ForegroundColor Green
Write-Host "      $notePath"
Write-Host "      It is the team's now: edit it to fit. ${prefix}StartWork <id> quotes it."
Write-Host ""
Write-Host "  Paste this line into the repository's AGENTS.md (ToolKit never writes there):"
Write-Host "    $pasteLine"
Write-Host ""
exit 0
