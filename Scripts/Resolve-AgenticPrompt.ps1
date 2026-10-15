<#
.SYNOPSIS
    Which copy of a shipped agentic prompt runs here. Dot-source it.

.DESCRIPTION
    Not a command. The agentic prompts ship GENERIC -- no org, no client, no
    engagement -- and the other half of that arrangement is a folder of the
    engineer's own whose tuned copy wins on their machine while the package
    stays generic for everyone else (docs/CLI.md, "The agentic workflows").
    This is the ONE lookup:
    the extension folder first, when config names one and the file is there,
    then the package's agentic/. One resolver, so the search order cannot
    differ per caller -- "one place for magic strings" applied to a lookup.

    The folder is config.local.json's agenticExtensionPath (or the module's
    merged copy), absolute or relative to the hub. Each caller prints the path
    it chose AND which copy won, or a tuned prompt silently taking over is its
    own confusing afternoon.

        . (Join-Path $PSScriptRoot 'Resolve-AgenticPrompt.ps1')
        $prompt = Resolve-P20AgenticPrompt -Name 'pr-review.prompt.md'
        $prompt.Path      # the file to read
        $prompt.Source    # 'extension' or 'package'

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20PromptsRoot -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1') }
if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }

function Get-P20AgenticExtensionPath {
    <# The configured folder, resolved, or '' when none is set or it does not exist. #>
    param([string]$PackageRoot = '')
    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
    $raw = ''
    if ($global:P20Config -and $global:P20Config.PSObject.Properties['AgenticExtensionPath']) {
        $raw = [string]$global:P20Config.AgenticExtensionPath
    }
    else {
        foreach ($name in @('config.default.json', 'config.local.json')) {
            $path = Join-Path $PackageRoot $name
            if (-not (Test-Path $path)) { continue }
            try {
                $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cfg -and $cfg.PSObject.Properties['agenticExtensionPath'] -and $null -ne $cfg.agenticExtensionPath) {
                    $raw = [string]$cfg.agenticExtensionPath
                }
            }
            catch { if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message } }
        }
    }
    $raw = $raw.Trim()
    if (-not $raw) { return '' }
    if ($raw.StartsWith('~')) {
        $rest = $raw.Substring(1).TrimStart('/', '\')
        $raw = if ($rest) { Join-Path $HOME $rest } else { $HOME }
    }
    if (-not [System.IO.Path]::IsPathRooted($raw)) {
        $hub = Get-P20PromptsRoot -PackageRoot $PackageRoot
        if (-not $hub) { return '' }
        $raw = Join-Path $hub $raw
    }
    if (-not (Test-Path -LiteralPath $raw -PathType Container)) { return '' }
    return (Get-Item -LiteralPath $raw).FullName
}

function Resolve-P20AgenticPrompt {
    <#
        @{ Path = <file>; Source = 'extension' | 'package'; Extension = <folder or ''> }
        The package copy is returned whether or not it exists; the caller says
        so if it is missing, as it always did.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$PackageRoot = ''
    )
    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
    $extension = Get-P20AgenticExtensionPath -PackageRoot $PackageRoot
    if ($extension) {
        $candidate = Join-Path $extension $Name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return @{ Path = (Get-Item -LiteralPath $candidate).FullName; Source = 'extension'; Extension = $extension }
        }
    }
    return @{ Path = (Join-Path (Join-Path $PackageRoot 'agentic') $Name); Source = 'package'; Extension = $extension }
}

function Get-P20PromptInstruction {
    <#
        The part of a tool-sent prompt file that goes to the model: everything
        below the first '---' line that follows the frontmatter. A file with no
        frontmatter fences on its first '---' line; a file with no fence is
        sent whole. CRLF reads as LF, so a Windows checkout sends what a Mac
        does. The agent's twin is prompt_instruction() in
        agent/ado/pr_comments.py; both suites read the shipped files with it.
    #>
    param([AllowEmptyString()][string]$Text)
    $fenceLine = "`n---`n"
    $t = ([string]$Text).Replace("`r`n", "`n")
    $start = 0
    if ($t.StartsWith("---`n")) {
        $close = $t.IndexOf($fenceLine, 3)
        if ($close -ge 0) { $start = $close + $fenceLine.Length }
    }
    $fence = $t.IndexOf($fenceLine, [Math]::Max($start - 1, 0))
    if ($fence -ge 0) { return $t.Substring($fence + $fenceLine.Length) }
    return $t.Substring($start)
}
