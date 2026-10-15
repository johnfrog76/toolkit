#
# Which port the agent is on -- ONE resolver, dot-sourced by both launchers.
#
#     . (Join-Path $PSScriptRoot 'Get-AgentPort.ps1')
#     $port = Get-P20AgentPort -RepoRoot $repoRoot
#     Set-Item -Path "env:$(Get-P20AgentPortEnvName)" -Value $port
#
# The port is DATA: web.agentPort in config.default.json, patched by
# config.local.json, last read wins (Start-Agent.ps1 owns the -Port override for
# a single run). Start-Agent.ps1 used to resolve it alone, and the two
# proxies that point at the agent -- Vite's dev proxy and nginx's -- carried 4100
# in source, so `tkAgent -Port <n>` produced a web UI that could not reach its
# agent.
#
# Now Start-Web.ps1 asks this for the port and exports it under the name the
# contract file gives it (consts.json, env.agentPort): web/vite.config.ts reads
# that variable for the dev proxy, and docker-compose.yml passes it into the
# nginx image, whose entrypoint substitutes it into the template. Neither proxy
# can read config; both can read an environment variable, and this is the one
# place that decides its name and its value.
#
# Not a runnable verb. PowerShell 5.1 floor.
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-P20AgentPort {
    [CmdletBinding()]
    param(
        # The package root: where config.default.json and config.local.json are.
        [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
    )
    $resolved = 0
    foreach ($name in @('config.default.json', 'config.local.json')) {
        $path = Join-Path $RepoRoot $name
        if (-not (Test-Path $path)) { continue }
        try {
            $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.web -and $cfg.web.agentPort) { $resolved = [int]$cfg.web.agentPort }
        }
        catch {
            if ($name -eq 'config.local.json') {
                if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
                $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message
            }
            else { Write-Warning "Could not read $name for web.agentPort -- ignoring it" }
        }
    }
    if ($resolved -le 0) {
        # No number typed here as a fallback: the shipped default is
        # config.default.json's, and a package without that file has no agent.
        throw "web.agentPort is not set in config.default.json or config.local.json under $RepoRoot."
    }
    return $resolved
}

function Get-P20AgentPortEnvName {
    # The variable's NAME comes from the contract file, because two halves that
    # cannot read config have to agree on it to the character.
    return [string](Get-P20Consts).env.agentPort
}
