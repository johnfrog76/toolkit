<#
.SYNOPSIS
    The one warning for a config.local.json that will not parse. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    The module's loader reads config.local.json first and warns when it cannot
    parse it. Six other readers (Get-P20PromptsRoot, Test-P20HubConfigured,
    Resolve-P20ConfigPrefix, Get-P20AgenticExtensionPath, Get-P20HelpPorts, and
    the module's Get-P20CommandScores and Get-RecentErrors) read the same file
    and used to swallow the failure, so a typo turned the machine back into an
    unconfigured one with no hint why. They keep their fallback; they
    call this to say so. So does every other reader in the tree; the
    scan in Tests/Test-Config.ps1 fails naming the line of one that does not.
    Read-P20LocalConfigJson is the shorthand for a plain read, and
    ConvertTo-P20ConfigDate names the key of a date that is not one.

    It says it ONCE per process per file: the marker is an AppDomain data slot,
    which -- unlike a $script: or $global: variable -- is the same for the
    module, a script the module launched and a dot-sourced standalone script
    (AGENTS.md, "A function global: in utilities.psm1 cannot read module state
    through a $script: name"). The wording is the loader's own.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

function Write-P20ConfigParseWarning {
    <# Returns $true when it warned, $false when this file was already reported. #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    # The same file spelled with / or \ is one file.
    $norm = $Path
    try { $norm = [System.IO.Path]::GetFullPath($Path) } catch { $null = $_ }
    $slot = 'Toolkit.ConfigParseWarned:' + $norm.ToLowerInvariant()
    if ([AppDomain]::CurrentDomain.GetData($slot)) { return $false }
    [AppDomain]::CurrentDomain.SetData($slot, $true)
    Write-Warning ("Failed to parse " + (Split-Path -Leaf $Path) + " ($Message). Using defaults only.")
    return $true
}

function Read-P20LocalConfigJson {
    <#
      The reader for a script that only wants to LOOK at config.local.json.
      Returns the parsed object, or $null when the file is not there or will not
      parse -- and for a file that will not parse says so once, through
      Write-P20ConfigParseWarning. The caller keeps its own fallback (defaults
      only), which is what $null means to every one of them. A caller that goes
      on to WRITE the file must not use this: it has to tell "absent" from
      "malformed" and refuse the second, so it does its own try/catch.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { $null = Write-P20ConfigParseWarning -Path $Path -Message $_.Exception.Message; return $null }
}

function ConvertTo-P20ConfigDate {
    <#
      A date-valued key of a config.local.json that DID parse (menuResetTimestamp,
      errorsAckedAt). Returns the [datetime], or $null when the value is not one
      -- and then says which key and what it held, once per process per file and
      key, instead of calling a good file unparseable. Same slot idea as
      Write-P20ConfigParseWarning.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        $Value
    )
    try { return [datetime]$Value }
    catch {
        $norm = $Path
        try { $norm = [System.IO.Path]::GetFullPath($Path) } catch { $null = $_ }
        $slot = 'Toolkit.ConfigKeyWarned:' + $norm.ToLowerInvariant() + ':' + $Key
        if (-not [AppDomain]::CurrentDomain.GetData($slot)) {
            [AppDomain]::CurrentDomain.SetData($slot, $true)
            Write-Warning ((Split-Path -Leaf $Path) + "'s " + $Key + " is not a date (" + [string]$Value + "). Ignoring it.")
        }
        return $null
    }
}
