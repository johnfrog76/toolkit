<#
.SYNOPSIS
    Render a command's -Help from config.default.json. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    Two launchers, Start-Web.ps1 and Start-Agent.ps1, run both WITH the module
    (as a tk* verb) and WITHOUT it (as a plain .ps1, which is how both suites
    drive them and how Start-Web.ps1 drives Start-Agent.ps1). The module has
    Show-CommandHelp for the first case; this is the second, and it renders the
    SAME entry -- description, usage, switches, examples, notes -- so the two
    cannot drift into describing the command differently.

    Help lives in config.default.json's `commands.<Name>` for exactly that
    reason: -Help, Menu and the README-parity check all read one source. The
    per-switch detail used to live in these scripts' comment-based help, where
    -Help never looked, so `tkWeb -Help` told a reader less than the
    predecessor's Web help did.

        . (Join-Path $PSScriptRoot 'Show-ConfigHelp.ps1')
        Show-P20ConfigHelp -CommandName 'Web' -RepoRoot $repoRoot -Prefix (Get-CliPrefix)

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }

function Get-P20HelpPorts {
    <#
        The ports a help entry may name, read rather than typed: web.agentPort
        is the key that decides the agent's, and web/vite.config.ts asks for the
        dev one. A help line with 4100 in it is wrong on the machine that
        changed the key.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $agentPort = 4100
    foreach ($name in @('config.default.json', 'config.local.json')) {
        $path = Join-Path $RepoRoot $name
        if (-not (Test-Path $path)) { continue }
        try {
            $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.web -and $cfg.web.agentPort) { $agentPort = [int]$cfg.web.agentPort }
        }
        catch { if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message } }
    }

    $devPort = 5174
    $viteConfig = Join-Path $RepoRoot 'web/vite.config.ts'
    if (Test-Path $viteConfig) {
        $m = [regex]::Match((Get-Content $viteConfig -Raw -ErrorAction SilentlyContinue), 'port:\s*(\d+)')
        if ($m.Success) { $devPort = [int]$m.Groups[1].Value }
    }

    return @{ AgentPort = $agentPort; DevPort = $devPort }
}

function Expand-P20HelpTokens {
    param([string]$Text, [string]$Prefix, $Ports)
    if (-not $Text) { return $Text }
    $out = $Text -replace '\{cliPrefix\}', $Prefix -replace '\{p\}', $Prefix
    if ($Ports) {
        $out = $out -replace '\{agentPort\}', $Ports.AgentPort -replace '\{devPort\}', $Ports.DevPort
    }
    return $out
}

function Show-P20ConfigHelp {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$Prefix = '',
        # Printed when the config cannot be read at all -- a checkout missing
        # its own config is a broken checkout, not a reason to say nothing.
        [string]$Fallback = ''
    )

    $meta = $null
    $path = Join-Path $RepoRoot 'config.default.json'
    if (Test-Path $path) {
        try { $meta = (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json).commands.$CommandName } catch { $meta = $null }
    }
    $ports = Get-P20HelpPorts -RepoRoot $RepoRoot

    Write-Host ""
    Write-Host "  $Prefix$CommandName" -ForegroundColor Cyan
    if (-not $meta) {
        if ($Fallback) { Write-Host "  $Fallback" -ForegroundColor Gray }
        Write-Host ""
        return
    }

    Write-Host "  $(Expand-P20HelpTokens $meta.description $Prefix $ports)" -ForegroundColor Gray
    if ($meta.usage) {
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    $(Expand-P20HelpTokens $meta.usage $Prefix $ports)" -ForegroundColor Gray
    }
    if ($meta.switches) {
        Write-Host ""
        Write-Host "  Switches:" -ForegroundColor Yellow
        foreach ($sw in $meta.switches.PSObject.Properties) {
            $label = "$($sw.Name)".PadRight(12)
            Write-Host "    $label $(Expand-P20HelpTokens $sw.Value $Prefix $ports)" -ForegroundColor Gray
        }
    }
    if ($meta.examples) {
        Write-Host ""
        Write-Host "  Examples:" -ForegroundColor Yellow
        foreach ($ex in $meta.examples) {
            Write-Host "    $(Expand-P20HelpTokens $ex $Prefix $ports)" -ForegroundColor Gray
        }
    }
    if ($meta.notes) {
        Write-Host ""
        Write-Host "  Notes:" -ForegroundColor Yellow
        foreach ($note in $meta.notes) {
            Write-Host "    $(Expand-P20HelpTokens $note $Prefix $ports)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}
