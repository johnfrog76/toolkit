<#
.SYNOPSIS
    Post a one-line message to a Teams recipient through the communication engine.
.DESCRIPTION
    The manual escape hatch for the engine: builds the smallest valid message
    object -- the <Message> string as the subject, tone "broadcast" -- and POSTs
    it to the running agent's /api/comms/send. No template, no dedup; running it
    IS the opt-in.

    Two gates, and this script owns the second one. The first is the module flag
    (features.communication), which decided whether this command exists at all.
    The second is the recipient's webhook environment variable, which can only be
    checked when the command runs -- and an unset variable is a configuration
    fact, not a failure, so it is PRINTED with the variable's name rather than
    raised. The engine resolves recipients the same way; checking here means the
    answer arrives without a round trip and names the fix.
.PARAMETER Recipient
    A logical recipient key from the communication recipients registry, e.g.
    "manager". Not a raw URL and not a channel name.
.PARAMETER Message
    The line to post.
.PARAMETER WhatIf
    Preview only: the engine runs every gate and formats the markdown but does
    not POST, returning the resolved target and the would-be payload.
.PARAMETER AsJson
    Emit the engine's raw {status, detail} as JSON.
.EXAMPLE
    {cliPrefix}SendTeams manager 'Retro summary posted'
.EXAMPLE
    {cliPrefix}SendTeams manager 'Heads up' -WhatIf
.NOTES
    PowerShell 5.1 compatible (ASCII dashes only). The webhook URL itself is
    never in config -- config names the variable, the environment holds the URL.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Recipient,

    [Parameter(Position = 1)]
    [string]$Message,

    [Parameter()]
    [switch]$AsJson,

    # -Session <file>: the meeting record (manager/current/<file>) that this
    # send is for. After an `ok`, one line goes under its ## Sent -- the same line
    # the web button writes -- so a send from a terminal is on the record too.
    #
    [Parameter()]
    [string]$Session,

    [Parameter()]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot
# The contract file: the webhook prefix, the run marker, the Sent line.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$script:SendConsts = Get-P20Consts

# Get-CliPrefix normally comes from the module. This script is also invoked
# directly -- by the tests, by a user running the .ps1 -- so a missing helper
# must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}SendTeams -- post one line to a Teams recipient" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}SendTeams <recipient> <message> [-WhatIf] [-AsJson] [-Help]"
    Write-Host ""
    Write-Host "  The recipient is a key from the communication registry, not a URL."
    Write-Host "  Its webhook lives in an environment variable; this command names"
    Write-Host "  the variable when it is not set instead of failing."
    Write-Host ""
    return
}

# -- Config ---------------------------------------------------------------------
# Read straight from the two JSON files rather than through the module: this
# script must work when it is invoked directly, and the recipients registry is
# not part of the config object the module exports.
function Read-CommunicationConfig {
    param([string]$Root)

    $defaults = $null
    $local = $null
    $defaultPath = Join-Path $Root 'config.default.json'
    $localPath = Join-Path $Root 'config.local.json'
    # The container's keys in both spellings (ConvertTo-P20SpaceKeys, stage 2).
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    if (Test-Path $defaultPath) { $defaults = ConvertTo-P20SpaceKeys (Get-Content $defaultPath -Raw | ConvertFrom-Json) }
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
    $local = ConvertTo-P20SpaceKeys (Read-P20LocalConfigJson -Path $localPath)

    # The manager recipient is NOT an org concern -- it does not change when the
    # active org changes -- so it lives in a top-level managerWorkflow block.
    # Every other recipient is the org's. Both are merged here, org last.
    $recipients = @{}
    foreach ($source in @($defaults, $local)) {
        if (-not $source) { continue }
        $mw = $source.managerWorkflow
        if ($mw -and $mw.communication -and $mw.communication.recipients) {
            foreach ($prop in $mw.communication.recipients.PSObject.Properties) {
                $recipients[$prop.Name] = $prop.Value
            }
        }
    }

    $activeSlug = ''
    if ($defaults -and $defaults.activeSpace) { $activeSlug = $defaults.activeSpace }
    if ($local -and $local.activeSpace) { $activeSlug = $local.activeSpace }

    # The active org's recipients, in the documented order: the shipped orgs,
    # then the hub's own (hub.json), then this machine's spaces.<slug> patch. This
    # read the shipped array alone, and a real org is always
    # hub-declared, so gate 2 found nothing to check and the engine's `skipped`
    # came back as a throw.
    # Resolve-HubConfig.ps1 is the one reader of
    # hub.json; nothing here parses it.
    $orgRecipients = @{}
    $takeRecipients = {
        param($Org)
        if ($Org -and $Org.communication -and $Org.communication.recipients) {
            foreach ($prop in $Org.communication.recipients.PSObject.Properties) {
                $orgRecipients[$prop.Name] = $prop.Value
            }
        }
    }
    if ($defaults -and $defaults.spaces) {
        foreach ($o in @($defaults.spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } }
    }
    $hubResolver = Join-Path (Join-Path $Root 'Scripts') 'Resolve-HubConfig.ps1'
    if (Test-Path $hubResolver) {
        . $hubResolver
        $hubRoot = Get-P20PromptsRoot -PackageRoot $Root
        $manifest = Read-P20HubManifest -Root $hubRoot -WarningAction SilentlyContinue
        # A renamed Space's old slug -- a nameless hub.json patch, an activeSpace --
        # is the new one.
        $manifest.Spaces = @(Rename-P20LegacyHubSpaces -Spaces @($manifest.Spaces) -ShippedSlugs @(@($defaults.spaces) | Where-Object { $_ } | ForEach-Object { [string]$_.slug }))
        $renamedTo = Resolve-P20RenamedSlug -Slug ([string]$activeSlug) -Slugs @(@($defaults.spaces) + @($manifest.Spaces) | Where-Object { $_ } | ForEach-Object { [string]$_.slug })
        if ($renamedTo -ne $activeSlug) {
            $activeSlug = $renamedTo
            if ($defaults -and $defaults.spaces) { foreach ($o in @($defaults.spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } } }
        }
        foreach ($o in @($manifest.Spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } }
    }
    if ($local -and $local.spaces -and ($local.spaces -isnot [array]) -and $activeSlug) {
        $patch = $local.spaces.PSObject.Properties[$activeSlug]
        if ($patch) { & $takeRecipients $patch.Value }
    }
    foreach ($k in $orgRecipients.Keys) { $recipients[$k] = $orgRecipients[$k] }

    $port = 4100
    foreach ($source in @($defaults, $local)) {
        if ($source -and $source.web -and $source.web.agentPort) { $port = [int]$source.web.agentPort }
    }

    return @{ Recipients = $recipients; AgentPort = $port }
}

# recipient key -> TEAMS_WEBHOOK_{KEY}, the convention the engine uses when a
# recipient entry does not name its variable explicitly.
function Get-WebhookEnvName {
    param([string]$Key)
    $upper = ''
    foreach ($c in $Key.ToUpper().ToCharArray()) {
        if ([char]::IsLetterOrDigit($c)) { $upper += $c } else { $upper += '_' }
    }
    return "$($script:SendConsts.env.teamsWebhookPrefix)$upper"
}

# -- Validate required args ------------------------------------------------------
# A throw here is the script-to-wrapper signal, not the user-facing surface: the
# wrapper catches it, logs ERR, and renders it through Write-CliError.
if ([string]::IsNullOrWhiteSpace($Recipient) -or [string]::IsNullOrWhiteSpace($Message)) {
    throw "Recipient and Message are both required (usage: $(Get-CliPrefix)SendTeams <recipient> <message>)."
}

$commsConfig = Read-CommunicationConfig -Root $repoRoot

# -- Gate 2: the recipient's webhook environment variable ------------------------
# Checked before the POST so the answer is immediate and names the fix. A
# recipient this config does not know is left to the engine, which has the whole
# registry and a better message for it.
$entry = $commsConfig.Recipients[$Recipient]
if ($entry -and $entry.type -eq 'channel') {
    $envName = $entry.webhookEnv
    if (-not $envName) { $envName = Get-WebhookEnvName -Key $Recipient }
    $url = [Environment]::GetEnvironmentVariable($envName)
    if (-not $url) { $url = [Environment]::GetEnvironmentVariable('TEAMS_WEBHOOK_URL') }
    if (-not $url) {
        Write-Host ""
        Write-Host "  Not sent -- no webhook configured for '$Recipient'." -ForegroundColor Yellow
        Write-Host "  Put $envName=<the recipient's webhook URL> in .env in the package root (copy .env.example)." -ForegroundColor DarkGray
        Write-Host "  The agent reads .env when it starts: restart it ($(Get-CliPrefix)Web -Stop, $(Get-CliPrefix)Web -Dev) after a change." -ForegroundColor DarkGray
        Write-Host "  The URL is a secret: it belongs in .env, never in config." -ForegroundColor DarkGray
        Write-Host ""
        return
    }
}

# -- Build the minimal message object --------------------------------------------
# ShouldProcess returns false under -WhatIf (and prints the standard "What if:"
# line); that is translated into the engine's dryRun rather than gating the POST
# locally, so the engine still resolves and formats and returns the would-be
# payload. The false return is deliberately NOT short-circuited on.
$isDryRun = -not $PSCmdlet.ShouldProcess($Recipient, "Post Teams message")

# While a test run is in progress nothing leaves the machine: the runners set
# the marker for their own process tree, so a suite that reached a real agent
# still cannot send. A dry run carries no message and may go.
if (-not $isDryRun -and [System.Environment]::GetEnvironmentVariable($script:SendConsts.env.testRunMarker)) {
    Write-Host ""
    Write-Host "  Not sent -- a test run is in progress ($($script:SendConsts.env.testRunMarker) is set); nothing posts until it ends." -ForegroundColor Yellow
    Write-Host ""
    return
}

$uri = "http://localhost:$($commsConfig.AgentPort)/api/comms/send"
$body = @{
    caller    = "ad-hoc"
    recipient = $Recipient
    subject   = $Message
    sections  = @()
    tone      = "broadcast"
    dryRun    = $isDryRun
} | ConvertTo-Json -Depth 5

# -- POST to the engine; degrade with a readable message if the agent is down ----
try {
    $result = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -TimeoutSec 15
}
catch {
    throw "Could not reach the agent at $uri -- start it with '$(Get-CliPrefix)Agent', then retry ($($_.Exception.Message))."
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}

# -- Map engine status to output -------------------------------------------------
# disabled / rejected / skipped / error all mean nothing was sent. The manual
# primitive says so out loud, unlike an embedded caller for which a no-op is
# normal.
switch ($result.status) {
    "ok" {
        if (-not $AsJson) { Write-Host "Sent to '$Recipient'." -ForegroundColor Green }
        if ($Session) {
            . (Join-Path $PSScriptRoot 'Add-SentLine.ps1')
            . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
            $sessionPath = $Session
            if (-not (Test-Path -LiteralPath $sessionPath)) {
                $managerDir = Get-P20HubFolder -Name 'manager' -PromptsRoot (Get-P20PromptsRoot -PackageRoot $repoRoot) -PackageRoot $repoRoot
                $sessionPath = Join-Path (Join-Path $managerDir 'current') ([System.IO.Path]::GetFileName($Session))
            }
            if (Test-Path -LiteralPath $sessionPath) {
                Add-P20SentLine -Path $sessionPath -Recipient $Recipient -Date (Get-Date -Format 'yyyy-MM-dd')
                if (-not $AsJson) { Write-Host "  Recorded under ## Sent in $([System.IO.Path]::GetFileName($sessionPath))." -ForegroundColor DarkGray }
            }
            else {
                Write-Warning "Sent, but '$Session' is not a session in manager/current/ -- add the Sent line by hand."
            }
        }
    }
    "dry-run" {
        if (-not $AsJson) {
            Write-Host "Dry run -- would post to '$Recipient':" -ForegroundColor Cyan
            Write-Host $result.payload -ForegroundColor Gray
        }
    }
    "skipped" {
        # The engine's own "nothing to send to": a recipient it does not know,
        # or a webhook it could not resolve. A printed result, not a throw --
        # nothing was sent, and the sentence says why.
        if (-not $AsJson) {
            Write-Host ""
            Write-Host "  Not sent -- skipped: $($result.detail)" -ForegroundColor Yellow
            Write-Host ""
        }
    }
    default {
        throw "Not sent ($($result.status)): $($result.detail)"
    }
}
