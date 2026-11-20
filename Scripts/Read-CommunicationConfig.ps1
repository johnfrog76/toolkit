#
# The Teams recipients registry, as the CLI reads it, and the agent port a send
# goes to.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Send-TeamsMessage.ps1
# (gate 2 of a send) and by Scripts/Get-OptionalSurfaces.ps1 (the Teams delivery
# row, which names the recipients). One reader, so the row Env prints and the
# gate a send meets cannot disagree about who is declared.
#
# Read straight from the files rather than through the module: SendTeams must
# work when the script is invoked directly, and the recipients registry is not
# part of the config object the module exports.
#
# Two places hold recipients. The managerWorkflow block's are the engineer's and
# hold steady across Spaces; the active Space's own communication block wins on
# a key collision. Within one recipient the files merge FIELD by field, in the
# order the agent merges them (agent/communication/comms.py): a machine that sets
# only a recipient's display keeps the shipped type and webhookEnv.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#

function Merge-P20RecipientInto {
    # Lay one recipients object over a hashtable of recipients, field by field.
    param([hashtable]$Into, $Recipients)
    if (-not $Recipients) { return }
    foreach ($prop in $Recipients.PSObject.Properties) {
        $entry = $prop.Value
        if ($null -eq $entry) { continue }
        $merged = [ordered]@{}
        $had = $Into[$prop.Name]
        if ($had) { foreach ($f in $had.PSObject.Properties) { $merged[$f.Name] = $f.Value } }
        if ($entry -is [System.Management.Automation.PSCustomObject]) {
            foreach ($f in $entry.PSObject.Properties) { $merged[$f.Name] = $f.Value }
        }
        $Into[$prop.Name] = [PSCustomObject]$merged
    }
}

function Read-P20CommunicationConfig {
    <#
      @{ Recipients = @{ <key> = <entry> }; AgentPort = <int> } for the package
      at -Root, as this machine resolves it: config.default.json, then
      config.local.json; the active Space's from the shipped Spaces, hub.json and
      this machine's spaces.<slug> patch, in that order.
    #>
    param([string]$Root)

    $defaults = $null
    $local = $null
    $defaultPath = Join-Path $Root 'config.default.json'
    $localPath = Join-Path $Root 'config.local.json'
    $scripts = Join-Path $Root 'Scripts'
    # The container's keys in both spellings (ConvertTo-P20SpaceKeys), and the
    # one reader of hub.json.
    if (-not (Get-Command ConvertTo-P20SpaceKeys -ErrorAction SilentlyContinue)) { . (Join-Path $scripts 'Resolve-HubConfig.ps1') }
    if (Test-Path -LiteralPath $defaultPath) { $defaults = ConvertTo-P20SpaceKeys (Get-Content -LiteralPath $defaultPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $scripts 'Write-ConfigParseWarning.ps1') }
    $local = ConvertTo-P20SpaceKeys (Read-P20LocalConfigJson -Path $localPath)

    $recipients = @{}
    foreach ($source in @($defaults, $local)) {
        if (-not $source) { continue }
        $mw = $source.managerWorkflow
        if ($mw -and $mw.communication -and $mw.communication.recipients) {
            Merge-P20RecipientInto -Into $recipients -Recipients $mw.communication.recipients
        }
    }

    $activeSlug = ''
    if ($defaults -and $defaults.activeSpace) { $activeSlug = $defaults.activeSpace }
    if ($local -and $local.activeSpace) { $activeSlug = $local.activeSpace }

    # The active Space's recipients, in the documented order: the shipped
    # Spaces, then the hub's own (hub.json), then this machine's spaces.<slug>
    # patch. A real Space is always hub-declared, so reading the shipped array
    # alone would leave gate 2 nothing to check.
    $spaceRecipients = @{}
    $takeRecipients = {
        param($Space)
        if ($Space -and $Space.communication -and $Space.communication.recipients) {
            Merge-P20RecipientInto -Into $spaceRecipients -Recipients $Space.communication.recipients
        }
    }
    if ($defaults -and $defaults.spaces) {
        foreach ($o in @($defaults.spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } }
    }
    $hubRoot = Get-P20PromptsRoot -PackageRoot $Root
    $manifest = Read-P20HubManifest -Root $hubRoot -WarningAction SilentlyContinue
    # A renamed Space's old slug -- a nameless hub.json patch, an activeSpace --
    # is the new one.
    $shippedSlugs = @(@($defaults.spaces) | Where-Object { $_ } | ForEach-Object { [string]$_.slug })
    $manifest.Spaces = @(Rename-P20LegacyHubSpaces -Spaces @($manifest.Spaces) -ShippedSlugs $shippedSlugs)
    $renamedTo = Resolve-P20RenamedSlug -Slug ([string]$activeSlug) -Slugs @(@($defaults.spaces) + @($manifest.Spaces) | Where-Object { $_ } | ForEach-Object { [string]$_.slug })
    if ($renamedTo -ne $activeSlug) {
        $activeSlug = $renamedTo
        if ($defaults -and $defaults.spaces) { foreach ($o in @($defaults.spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } } }
    }
    foreach ($o in @($manifest.Spaces)) { if ($o.slug -eq $activeSlug) { & $takeRecipients $o } }
    if ($local -and $local.spaces -and ($local.spaces -isnot [array]) -and $activeSlug) {
        $patch = $local.spaces.PSObject.Properties[$activeSlug]
        if ($patch) { & $takeRecipients $patch.Value }
    }
    foreach ($k in $spaceRecipients.Keys) { $recipients[$k] = $spaceRecipients[$k] }

    $port = 4100
    foreach ($source in @($defaults, $local)) {
        if ($source -and $source.web -and $source.web.agentPort) { $port = [int]$source.web.agentPort }
    }

    return @{ Recipients = $recipients; AgentPort = $port }
}
