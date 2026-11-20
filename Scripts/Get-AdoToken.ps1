#
# The one way a script gets an Azure DevOps token, builds its headers and
# explains a 401 or 403. NOT a runnable verb: DOT-SOURCED, by every script that
# calls the Azure DevOps REST API, and by a test, the way Invoke-TrackerRead.ps1 is.
#
#     . (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
#     $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
#     if (-not $tokenRead.Ok) {
#         Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
#         exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
#     }
#     $headers = Get-P20AdoHeaders -Token $tokenRead.Token -OrgUrl $cfg.Org
#
# The failure contract, one for every caller: az exiting non-zero, OR az printing
# no token (nothing, or only blank lines and WARNING: lines), is a failure. The
# token is read from az's stdout alone, through Invoke-P20TrackerRead, so an
# "ERROR: ..." on stderr can never be taken for a token, and Windows PowerShell
# 5.1 with $ErrorActionPreference = 'Stop' cannot throw on az's stderr before the
# exit code is read. The helper does not refuse for the caller: it returns the
# sentence and the hint, and the caller states them and exits 2, so the exit
# stays visible in the script that owns the verb.
#
# PowerShell 5.1 clean; reads no module state.
#
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'ConvertTo-Utf8Body.ps1')

# Returns @{ Ok; Token; Said; Message; Hint }. Token is the trimmed bearer token,
# or $null when Ok is $false. Said is what az printed (stdout and stderr, joined),
# for a caller that words its own refusal. Message and Hint are the standard
# refusal for a caller that does not.
function Get-P20AdoToken {
    [CmdletBinding()]
    param([string]$Tenant)
    $azArgs = @('account', 'get-access-token')
    if (-not [string]::IsNullOrWhiteSpace($Tenant)) { $azArgs += @('--tenant', $Tenant) }
    # The resource is Azure DevOps' own id: the audience of the token.
    $azArgs += @('--resource', '499b84ac-1321-427f-aa17-267ca6975798', '--query', 'accessToken', '-o', 'tsv')
    $read = Invoke-P20TrackerRead 'az' $azArgs
    $token = @($read.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^WARNING:' }) | Select-Object -Last 1
    $said = (@($read.Lines) -join ' ').Trim()
    $ok = ($read.Code -eq 0 -and -not [string]::IsNullOrWhiteSpace($token))
    $hint = "Run 'az login' first."
    if ($said) { $hint = "$hint az said: $said" }
    $value = $null
    if ($ok) { $value = ([string]$token).Trim() }
    return [PSCustomObject]@{
        Ok      = $ok
        Token   = $value
        Said    = $said
        Message = 'Failed to get ADO access token.'
        Hint    = $hint
    }
}

# Whether an address may be sent an Azure DevOps token: the Space's own address
# (spaces[].org), which the tracker rule reads as Azure DevOps, over https, with a
# host and no user name in it. On any other scheme the token would cross the
# network readable, so it is never put in a header for one. The host is not
# listed: Azure DevOps Server answers on a company's own name, and the tracker
# rule already sends github.com elsewhere.
function Test-P20AdoTokenUrl {
    param([AllowEmptyString()][AllowNull()][string]$Url)
    if ((Resolve-P20Tracker -OrgUrl $Url) -ne 'ado') { return $false }
    $uri = $null
    if (-not [Uri]::TryCreate("$Url".Trim(), [UriKind]::Absolute, [ref]$uri)) { return $false }
    return ($uri.Scheme -eq 'https' -and -not [string]::IsNullOrEmpty($uri.Host) -and -not $uri.UserInfo)
}

# The REST headers for a token, for the one address it goes to. -ContentType is
# application/json unless the call is a work item PATCH, which takes
# application/json-patch+json; either way it names charset=utf-8, because the body
# goes as UTF-8 bytes (ConvertTo-P20Utf8Body). Every Azure DevOps request a script
# makes takes its headers here, so the address rule above has no second copy to
# miss: an address outside it throws, and nothing is sent. The refusal names the
# address without any user name or password written into it.
function Get-P20AdoHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$OrgUrl,
        [string]$ContentType = 'application/json'
    )
    if (-not (Test-P20AdoTokenUrl $OrgUrl)) {
        $shown = "$OrgUrl" -replace '^([A-Za-z][A-Za-z0-9+.-]*://)[^/@?#]*@', '$1'
        if ((Resolve-P20Tracker -OrgUrl $OrgUrl) -ne 'ado') {
            throw "The Space's address ('$shown') is not an Azure DevOps organisation, so your Azure DevOps token is not sent to it."
        }
        throw "The Space's Azure DevOps address ('$shown') is not an https address, so your token is not sent to it. Set the Space's org to its https:// address."
    }
    return @{ Authorization = "Bearer $Token"; 'Content-Type' = "$ContentType; charset=utf-8" }
}

# The HTTP status of a failed Invoke-RestMethod, as a number. Windows PowerShell
# 5.1 hands back an HttpStatusCode enum off a WebResponse, pwsh 7 one off an
# HttpResponseMessage; [int] reads both. 0 when there is no response.
function Get-P20AdoHttpStatus {
    param($ErrorRecord)
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and $null -ne $resp.StatusCode) { return [int]$resp.StatusCode }
    } catch { $null = $_ }
    return 0
}

# Surfaces the actionable advice when Azure DevOps rejects the token: 401 (expired
# or not signed in) and 403 (most often an identity the org has never seen -- the
# az account has not signed in to the org in a browser, so it has no user record
# there yet). Returns $true when it handled a 401 or 403, so a caller can skip its
# generic message; $false for any other status, having printed nothing.
function Show-P20AdoForbiddenHint {
    param($ErrorRecord, [string]$Org)
    $status = Get-P20AdoHttpStatus $ErrorRecord
    if ($status -ne 401 -and $status -ne 403) { return $false }
    Write-Host "  Access denied (HTTP $status) by Azure DevOps -- the az sign-in may have expired, or your identity is not provisioned in this org yet." -ForegroundColor Yellow
    Write-Host "  Fix: run 'az login'. If that is not enough, open the org in a browser and sign in once, then retry:" -ForegroundColor Yellow
    Write-Host "    $Org" -ForegroundColor Yellow
    Write-Host "  Or run: az devops login --organization $Org" -ForegroundColor Yellow
    return $true
}
