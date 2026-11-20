<#
.SYNOPSIS
    The command prefix, read from config, with the shipped default in one
    place. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    The prefix is data: `commandPrefix` in `config.default.json`, overridable
    per machine in `config.local.json`. Five places needed the answer while the
    module was not loaded -- the autoload alias generator, the installer's cold
    shell probe, the card writer, and two suites -- and each carried its own
    bare fallback literal, and that literal was the LEGACY system's
    namespace -- so every one of those fallbacks was a wrong answer waiting for
    a config it could not read, and one of them wrote the wrong prefix into a
    user's card.

    So the fallback is a named constant, here, and the readers call the
    function. A repeated literal is a drift bug waiting for its second copy to
    be edited alone (AGENTS.md, "One place for magic strings").

    Dot-sourced rather than reached through utilities.psm1 because every caller
    has to work with no module imported -- that is the whole reason they need
    to resolve it themselves.

        . (Join-Path $PSScriptRoot 'Resolve-CliPrefix.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

# The shipped default, in ONE place. It matches config.default.json's
# `commandPrefix`, and it is what a reader gets when that file cannot be read
# at all -- a broken checkout, not a reason to answer with another product's
# namespace.
$script:P20DefaultCommandPrefix = 'tk'

function Get-P20DefaultPrefix {
    return $script:P20DefaultCommandPrefix
}

function Test-P20CommandName {
    <#
        Whether a nav alias key may become a command's name: a letter, then
        letters, digits, '-' or '_'. The schema refuses anything else as it is
        set, and every reader checks again, because a file can already hold one.
        A commandPrefix has its own, narrower rule: Test-P20CommandPrefix.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Name)
    return ($Name -cmatch '^[A-Za-z][A-Za-z0-9_-]*\z')
}

function Test-P20CommandPrefix {
    <#
        Whether a value may be the commandPrefix: a letter, then letters or
        digits. Narrower than an alias key on purpose: the prefix starts every
        verb, and 'my-tkStatus' is a name nobody wants to type. The one rule for
        the schema, the readers and Register-PromptAlias, so what Config accepts
        always registers.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Name)
    return ($Name -cmatch '^[A-Za-z][A-Za-z0-9]*\z')
}

function ConvertTo-P20BareAliasKey {
    <#
        The bare spelling of a navigation alias key.

        A nav alias key is stored BARE -- 'Home', never 'tkHome' -- exactly as a
        command key is, and the prefix is applied when the alias is registered
        and when the menu renders it. A key that still carries the prefix is
        read as the bare name rather than prefixed a second time, which is what
        printed 'tktkHub'.

        Only a prefixed VERB spelling is stripped: the remainder has to start
        with a capital, so a bare key that merely begins with the prefix's
        letters is left exactly as it was written.

        It lives here, beside the prefix itself, because three readers need the
        same answer with no module loaded -- the module's own merge, the config
        schema that validates `aliases.<name>.path`, and the suites.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prefix
    )
    if (-not $Prefix) { return $Key }
    if ($Key.Length -le $Prefix.Length) { return $Key }
    if (-not $Key.StartsWith($Prefix, [System.StringComparison]::Ordinal)) { return $Key }
    $rest = $Key.Substring($Prefix.Length)
    if ($rest -cmatch '^[A-Z]') { return $rest }
    return $Key
}

if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }

function Select-P20CommandPrefix {
    <#
        A configured prefix, if it may be one; otherwise the fallback, with a
        warning that names the file and the rule.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Fallback,
        [string]$Path = 'config'
    )
    if (Test-P20CommandPrefix $Value) { return $Value }
    Write-Warning "commandPrefix in $Path is not a command prefix (a letter, then letters or digits); using '$Fallback'."
    return $Fallback
}

function Resolve-P20ConfigPrefix {
    <#
        The prefix this package registers: config.default.json, then
        config.local.json's override, then the shipped default.
    #>
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $prefix = $script:P20DefaultCommandPrefix
    foreach ($name in @('config.default.json', 'config.local.json')) {
        $path = Join-Path $PackageRoot $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $cfg = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.commandPrefix) { $prefix = Select-P20CommandPrefix -Value ([string]$cfg.commandPrefix) -Fallback $prefix -Path $path }
        }
        catch { if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message } }
    }
    return $prefix
}
