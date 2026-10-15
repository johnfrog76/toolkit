#
# The settings-by-workflow entries -- the questions a person asks, in their
# words, each tied to an optional surface by key (D-W1, D-W8; docs/CONFIGURATION.md,
# "Settings by workflow: the questions, and the one list behind them"). NOT a runnable verb: dot-sourced by Scripts/Get-OptionalSurfaces.ps1,
# which puts the question on every inventory row, and by utilities.psm1 for the
# agent's GET /api/surfaces. The file is Config/settings-workflows.json; the web
# imports the same file at build time. Held to the inventory both ways by
# tkTestToolkit -Environment.
#
# PowerShell 5.1 clean: ConvertFrom-Json without -AsHashtable, no ternary.
#
$script:P20SettingsWorkflowsCache = $null

function Get-P20SettingsWorkflowsPath {
    param([string]$PackageRoot = '')
    if (-not $PackageRoot) { $PackageRoot = (Split-Path $PSScriptRoot -Parent) }
    return (Join-Path (Join-Path $PackageRoot 'Config') 'settings-workflows.json')
}

function Get-P20SettingsWorkflows {
    <#
      Every entry, as objects: id, question, sentence, surfaces (string[]),
      door ('change' | 'walk' | 'sentence'), anchor (optional), tip (optional).
      An unreadable file answers an empty list and a warning naming the path --
      the inventory still renders, every row simply carries no question.
    #>
    [CmdletBinding()]
    param([string]$PackageRoot = '', [switch]$Refresh)
    if ($script:P20SettingsWorkflowsCache -and -not $Refresh -and -not $PackageRoot) { return $script:P20SettingsWorkflowsCache }
    $path = Get-P20SettingsWorkflowsPath -PackageRoot $PackageRoot
    $entries = @()
    if (Test-Path -LiteralPath $path) {
        try {
            $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data -and $data.entries) { $entries = @($data.entries) }
        }
        catch { Write-Warning "$path`: not readable as JSON ($($_.Exception.Message)) -- the inventory carries no questions." }
    }
    else { Write-Warning "$path`: missing -- the inventory carries no questions." }
    if (-not $PackageRoot) { $script:P20SettingsWorkflowsCache = $entries }
    return $entries
}

function Get-P20SurfaceQuestion {
    <# The question for one inventory key, or '' when no entry names it. #>
    param([string]$Key, [string]$PackageRoot = '')
    foreach ($entry in (Get-P20SettingsWorkflows -PackageRoot $PackageRoot)) {
        if (@($entry.surfaces) -contains $Key) { return [string]$entry.question }
    }
    return ''
}
