<#
.SYNOPSIS
    NewDesign -- scaffold one design note in the hub's design/ (the Studio, core).

.DESCRIPTION
    Writes <promptsRoot>/design/<slug>.md from templates/DesignNote.template.md:
    YAML frontmatter with the design's id (a UUID v4, consts.json design.idKey), the one-line description (and the Space it is for,
    when -Space names one), the title as the H1, the template's headings, and
    the house footer's **Created:** stamp. The folder is the hub's to name
    (hub.json folders.design, default 'design').

    The hub's design/ is the Studio's SEED DRAWER (D-S3, D-S10): a note that belongs to no product yet. Once it has one, it
    moves into that product's repo by a commit, which is not this verb's job.

    Never overwrites: an existing file is a stated refusal, as every creator here
    (AGENTS.md, "current/ is protected"). The file name is the title's slug and
    always matches the contract's studio.noteName.

.EXAMPLE
    {cliPrefix}NewDesign -Title "Board ideas" -Description "What the board could show next"
.EXAMPLE
    {cliPrefix}NewDesign -Title "Spike: offline specs" -Space toolkit

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Title,
    [Parameter(Mandatory = $false)]
    [string]$Description,
    [Parameter(Mandatory = $false)]
    [string]$Space,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}
# Write-CliError normally comes from the module; it is what makes a refusal ONE
# block. See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}NewDesign -- scaffold a design note in the hub" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}NewDesign -Title <text> [-Description <text>] [-Space <slug>]"
    Write-Host ""
    Write-Host "  Writes design/<slug>.md in the hub from the DesignNote template. Never overwrites."
    Write-Host "  -Space names the Space the note is for; Promote then files its thread there."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
$consts = Get-P20Consts

function ConvertTo-P20DesignSlug {
    # The title lowercased, every run of anything but a-z and 0-9 one hyphen,
    # trimmed, at most 60 characters -- so the name always matches noteName.
    param([string]$Text)
    $slug = ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    return $slug
}

if (-not $Title -or -not $Title.Trim()) {
    Write-CliError -Message 'A design note needs a title.' -Hint "$(Get-CliPrefix)NewDesign -Title ""Board ideas"" -Description ""What the board could show next"""
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$Title = ($Title -replace "\r?\n", ' ').Trim()
$slug = ConvertTo-P20DesignSlug $Title
if (-not $slug) {
    Write-CliError -Message "'$Title' has no letter or digit to name the file with." -Hint 'Give the note a title with a word in it.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$fileName = "$slug.md"
if ($fileName -notmatch $consts.studio.noteName) {
    Write-CliError -Message "'$fileName' is not a name a design note can have." -Hint 'Give the note a title that starts with a letter or digit.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# The description is one frontmatter line inside double quotes: one line, and
# a double quote becomes a single one rather than ending the value early.
$descriptionValue = ''
if ($Description) { $descriptionValue = (($Description -replace "\r?\n", ' ') -replace '"', "'").Trim() }

$spaceValue = ''
if ($Space) {
    $spaceValue = $Space.Trim()
    $declared = @()
    if ($global:P20Config -and $global:P20Config.Spaces) { $declared = @($global:P20Config.Spaces | ForEach-Object { [string]$_.slug }) }
    if ($declared.Count -gt 0 -and $declared -notcontains $spaceValue) {
        Write-CliError -Message "No Space '$spaceValue' is declared." -Hint "Declared: $($declared -join ', '). Or leave -Space out: a note may belong to no product yet."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$designDir = Get-P20HubFolder -Name 'design' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
$folderName = [System.IO.Path]::GetFileName($designDir)
$filePath = Join-Path $designDir $fileName
if (Test-Path -LiteralPath $filePath) {
    Write-CliError -Message "$folderName/$fileName already exists. Not overwriting it." `
        -Hint 'Open it and keep writing, or give the new note a different title.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$templatePath = Join-Path (Join-Path $repoRoot 'templates') 'DesignNote.template.md'
if (-not (Test-Path -LiteralPath $templatePath)) {
    Write-CliError -Message "The design note template is missing: $templatePath" -Hint 'The package is incomplete; update or re-clone it.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$text = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$text = $text -replace "`r`n", "`n"
if ($spaceValue) { $text = $text.Replace('{SPACE}', $spaceValue) }
else { $text = ($text -split "`n" | Where-Object { $_ -ne 'space: {SPACE}' }) -join "`n" }
$text = $text.Replace('{ID}', [guid]::NewGuid().ToString()).Replace('{DESCRIPTION}', $descriptionValue).Replace('{TITLE}', $Title)
$text = $text.TrimEnd("`n") + "`n`n$($consts.stamps.created) $((Get-Date).ToString('yyyy-MM-dd'))`n"

if (-not (Test-Path -LiteralPath $designDir)) { New-Item -ItemType Directory -Path $designDir -Force | Out-Null }
Write-CardText -Path $filePath -Content $text -New

Write-Host "Created design note: $folderName/$fileName" -ForegroundColor Green
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)NewDesign" -Detail "$folderName/$fileName"
}
exit 0
