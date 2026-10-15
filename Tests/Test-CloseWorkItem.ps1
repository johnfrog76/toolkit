<#
.SYNOPSIS
    Regression tests for Close-WorkItem.ps1's transition rule and error surfacing.
.DESCRIPTION
    Two defects, found together while closing US-144 for real:

    1. Get-CloseTransition. The reason for a non-Bug close was hardcoded to
       "Completed" and -Reason was silently ignored for every type except Bug.
       That "Completed" is not a valid System.Reason value on this project's
       process for a Closed User Story, so a legitimate WillNotFix close failed
       with a 400 and no way to say what actually happened. -Reason now applies
       to every type; "Completed" stays the non-Bug default because it is
       correct for the common case (the work shipped).

    2. Get-AdoErrorMessage. The old catch block printed only
       $_.Exception.Message, which for a failed Invoke-RestMethod is the useless
       "400 (Bad Request)". ADO's real explanation is in the response body, on
       $_.ErrorDetails.Message, which this function parses.

    Both are extracted as functions from the script's source text and evaluated
    directly, so this suite needs no ADO, no auth, no network.

    Run:  pwsh -File Tests/Test-CloseWorkItem.ps1
    Or:   tkTestToolkit -CloseWorkItem
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Loads a function, or a block, out of the script under test by its source text, so it can be called alone.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = Split-Path $scriptDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/Close-WorkItem.ps1'
if (-not (Test-Path $targetScript)) {
    Write-Error "Close-WorkItem.ps1 not found at $targetScript"
    return
}

$sourceText = Get-Content -Path $targetScript -Raw

# A regex matching "the next line that is just N spaces + }" breaks the moment a
# function's body contains a nested block closed at that same indent -- which
# Get-CloseTransition does (its if/elseif/else), and it silently grabbed the
# if-block's closer instead of the function's own. Count braces instead: exact
# regardless of nesting or indentation, and correct for either function here
# even though the two are defined at different indent levels in the script.
function Get-FunctionSource {
    param([string]$Source, [string]$Name)

    $start = $Source.IndexOf("function $Name")
    if ($start -lt 0) { return $null }

    $openBrace = $Source.IndexOf('{', $start)
    if ($openBrace -lt 0) { return $null }

    $depth = 0
    for ($i = $openBrace; $i -lt $Source.Length; $i++) {
        if ($Source[$i] -eq '{') { $depth++ }
        elseif ($Source[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Source.Substring($start, $i - $start + 1) }
        }
    }
    return $null
}

$transitionSource = Get-FunctionSource -Source $sourceText -Name 'Get-CloseTransition'
if (-not $transitionSource) {
    Write-Error "Could not find function Get-CloseTransition in $targetScript"
    return
}
Invoke-Expression $transitionSource

$errorSource = Get-FunctionSource -Source $sourceText -Name 'Get-AdoErrorMessage'
if (-not $errorSource) {
    Write-Error "Could not find function Get-AdoErrorMessage in $targetScript"
    return
}
Invoke-Expression $errorSource

if (-not (Get-Command Get-CloseTransition -ErrorAction SilentlyContinue)) {
    Write-Error "Get-CloseTransition did not load correctly"
    return
}
if (-not (Get-Command Get-AdoErrorMessage -ErrorAction SilentlyContinue)) {
    Write-Error "Get-AdoErrorMessage did not load correctly"
    return
}

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  CloseWorkItem Transition + Error-Message Tests" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$reasonMap = @{
    "Fixed"           = "Fixed"
    "AsDesigned"      = "As Designed"
    "CannotReproduce" = "Cannot Reproduce"
    "Duplicate"       = "Duplicate"
    "WontFix"         = "Won't Fix"
    "WillNotFix"      = "Won't Fix"
    "Obsolete"        = "Obsolete"
    "CopiedToBacklog" = "Copied to Backlog"
    "Deferred"        = "Deferred"
    "Rejected"        = "Rejected"
}

# -- Bugs: unchanged behaviour -------------------------------------------------

$r = Get-CloseTransition -WorkItemType 'Bug' -Reason 'Fixed' -ReasonWasSpecified $false -ReasonMap $reasonMap
Assert-True "Bug, no -Reason -> Resolved / Fixed" `
    ($r.TargetState -eq 'Resolved' -and $r.AdoReason -eq 'Fixed')

$r = Get-CloseTransition -WorkItemType 'Bug' -Reason 'AsDesigned' -ReasonWasSpecified $true -ReasonMap $reasonMap
Assert-True "Bug, -Reason AsDesigned -> Resolved / As Designed (mapped)" `
    ($r.TargetState -eq 'Resolved' -and $r.AdoReason -eq 'As Designed')

$r = Get-CloseTransition -WorkItemType 'Bug' -Reason 'SomethingCustom' -ReasonWasSpecified $true -ReasonMap $reasonMap
Assert-True "Bug, unknown -Reason passes through verbatim" `
    ($r.AdoReason -eq 'SomethingCustom')

# -- The actual defect: non-Bug types ------------------------------------------

$r = Get-CloseTransition -WorkItemType 'User Story' -Reason 'Fixed' -ReasonWasSpecified $false -ReasonMap $reasonMap
Assert-True "Story, no -Reason -> Closed / Completed (default preserved)" `
    ($r.TargetState -eq 'Closed' -and $r.AdoReason -eq 'Completed')

$r = Get-CloseTransition -WorkItemType 'User Story' -Reason 'WillNotFix' -ReasonWasSpecified $true -ReasonMap $reasonMap
Assert-True "Story, -Reason WillNotFix -> Closed / Won't Fix (was silently 'Completed')" `
    ($r.TargetState -eq 'Closed' -and $r.AdoReason -eq "Won't Fix") `
    "got AdoReason='$($r.AdoReason)' -- this is the US-144 case, -Reason must not be ignored"

$r = Get-CloseTransition -WorkItemType 'Task' -Reason 'Rejected' -ReasonWasSpecified $true -ReasonMap $reasonMap
Assert-True "Task, -Reason Rejected -> Closed / Rejected" `
    ($r.TargetState -eq 'Closed' -and $r.AdoReason -eq 'Rejected')

$r = Get-CloseTransition -WorkItemType 'Feature' -Reason 'Fixed' -ReasonWasSpecified $false -ReasonMap $reasonMap
Assert-True "Feature, no -Reason -> Closed / Completed" `
    ($r.TargetState -eq 'Closed' -and $r.AdoReason -eq 'Completed')

# The trap this whole function exists to avoid: the param default is "Fixed",
# so a naive $Reason -eq default check cannot distinguish an explicit
# "-Reason Fixed" from no -Reason at all.
$r = Get-CloseTransition -WorkItemType 'Task' -Reason 'Fixed' -ReasonWasSpecified $true -ReasonMap $reasonMap
Assert-True "Task, EXPLICIT -Reason Fixed is honoured, not overridden to Completed" `
    ($r.AdoReason -eq 'Fixed') `
    "got '$($r.AdoReason)' -- ReasonWasSpecified must be checked, not the value against its default"

Write-Host ""

# -- Get-AdoErrorMessage --------------------------------------------------------

$realBody = '{"$id":"1","innerException":null,"message":"The field ''Reason'' contains the value ''Completed'' that is not in the list of supported values","typeName":"Microsoft.TeamFoundation.WorkItemTracking.Server.RuleValidationException, Microsoft.TeamFoundation.WorkItemTracking.Server","typeKey":"RuleValidationException","errorCode":0,"eventId":3200}'

Assert-True "parses the real ADO rule-validation body captured from US-144" `
    ((Get-AdoErrorMessage $realBody) -eq "The field 'Reason' contains the value 'Completed' that is not in the list of supported values")

Assert-True "empty input returns null rather than throwing" `
    ($null -eq (Get-AdoErrorMessage ''))

Assert-True "null input returns null rather than throwing" `
    ($null -eq (Get-AdoErrorMessage $null))

Assert-True "malformed JSON returns null rather than throwing" `
    ($null -eq (Get-AdoErrorMessage 'not json at all'))

Assert-True "valid JSON with no message field returns null" `
    ($null -eq (Get-AdoErrorMessage '{"foo":"bar"}'))

Write-Host ""

# -- The token helper, Scripts/Get-AdoToken.ps1 --------------------------------
# One helper gets the Azure DevOps token for every ADO script, and one failure
# contract holds for all of them: az exiting non-zero OR printing no token is a
# failure. Before it, CloseItem and NewItem merged az's stderr into the output
# with 2>&1 and checked only for an empty string, so "ERROR: ..." from a failed
# az read as a token and the refusal was skipped. The helper is dot-sourced in a
# child shell on each host with $ErrorActionPreference = 'Stop', where a stand-in
# az writes down its arguments and answers by mode. No tracker is contacted.

Write-Host "-- The token helper ------------------------------------" -ForegroundColor Cyan

$tokenHelperPath = (Join-Path $pkgRoot 'Scripts/Get-AdoToken.ps1') -replace "'", "''"
$tokenCases = @'
. '__HELPER__'
$ErrorActionPreference = 'Stop'
function global:az {
    $global:LASTEXITCODE = 0
    $global:AzArgs = ($args -join ' ')
    if ($env:P20_TEST_AZ_MODE -eq 'fail') { $global:LASTEXITCODE = 1; Write-Error 'ERROR: AADSTS70043: The refresh token has expired.'; return }
    if ($env:P20_TEST_AZ_MODE -eq 'empty') { return }
    if ($env:P20_TEST_AZ_MODE -eq 'warnonly') { return 'WARNING: a newer az is available', '   ' }
    return 'WARNING: a newer az is available', ' a-token '
}
foreach ($mode in @('ok', 'fail', 'empty', 'warnonly')) {
    $env:P20_TEST_AZ_MODE = $mode
    $r = Get-P20AdoToken -Tenant 'tenant-1'
    "$mode ok=$($r.Ok) token=[$($r.Token)] message=$($r.Message) hint=$($r.Hint)"
}
"ARGS=$global:AzArgs"
$env:P20_TEST_AZ_MODE = 'ok'
$null = Get-P20AdoToken
"NOTENANT=$global:AzArgs"
$h = Get-P20AdoHeaders -Token 'a-token'
$p = Get-P20AdoHeaders -Token 'a-token' -ContentType 'application/json-patch+json'
"HEADERS=$($h.Authorization)|$($h['Content-Type'])|$($p['Content-Type'])"
foreach ($code in @(401, 403, 404)) {
    $ex = New-Object System.Exception 'stubbed REST failure'
    $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = $code })
    $rec = New-Object System.Management.Automation.ErrorRecord($ex, 'stub', 'NotSpecified', $null)
    $handled = Show-P20AdoForbiddenHint $rec -Org 'https://dev.azure.com/acme-org'
    "HINT$code=$handled"
}
"PREF=$ErrorActionPreference"
'@.Replace('__HELPER__', $tokenHelperPath)
$tokenRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-adotoken-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $tokenRoot -Force | Out-Null
    $tokenScript = Join-Path $tokenRoot 'token-cases.ps1'
    [System.IO.File]::WriteAllText($tokenScript, $tokenCases, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($exe in @('pwsh', 'powershell.exe')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $savedPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $to = (& $exe -NoProfile -File $tokenScript 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        $ErrorActionPreference = $savedPref
        Assert-True "token helper, ${exe}: a token is read from stdout, WARNING lines and spaces dropped" ($to -match 'ok ok=True token=\[a-token\]') $to
        Assert-True "token helper, ${exe}: az exiting non-zero with error text is a failure, not a token" ($to -match 'fail ok=False token=\[\] message=Failed to get ADO access token\. hint=Run ''az login'' first\. az said: ERROR: AADSTS70043') $to
        Assert-True "token helper, ${exe}: az printing nothing and exiting 0 is a failure, and the hint still names az login" ($to -match 'empty ok=False token=\[\] message=Failed to get ADO access token\. hint=Run ''az login'' first\.(\n|$)') $to
        Assert-True "token helper, ${exe}: only WARNING lines and blanks is a failure" ($to -match 'warnonly ok=False token=\[\]') $to
        Assert-True "token helper, ${exe}: asks for the Azure DevOps resource with the tenant given" ($to -match 'ARGS=account get-access-token --tenant tenant-1 --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv') $to
        Assert-True "token helper, ${exe}: no tenant, no --tenant" ($to -match 'NOTENANT=account get-access-token --resource ') $to
        Assert-True "token helper, ${exe}: the headers carry the bearer token and the content type asked for" ($to -match 'HEADERS=Bearer a-token\|application/json\|application/json-patch\+json') $to
        Assert-True "token helper, ${exe}: 401 and 403 get the access advice naming az login and the org" ($to -match 'HINT401=True' -and $to -match 'HINT403=True' -and $to -match 'Access denied \(HTTP 401\)' -and $to -match 'Access denied \(HTTP 403\)' -and $to -match "run 'az login'" -and $to -match 'az devops login --organization https://dev\.azure\.com/acme-org') $to
        Assert-True "token helper, ${exe}: any other status is left to the caller" ($to -match 'HINT404=False' -and $to -notmatch 'HTTP 404') $to
        Assert-True "token helper, ${exe}: the caller's ErrorActionPreference is still Stop after the calls" ($to -match 'PREF=Stop') $to
    }
}
catch {
    Assert-True "the token helper cases ran to the end without a terminating error" $false $_.Exception.Message
}
finally {
    if (Test-Path $tokenRoot) { Remove-Item $tokenRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""

# -- The verb, typed in a fresh shell ------------------------------------------
# Everything above drives pieces of the script. This section types the verb the
# way a person does (AGENTS.md: a suite that runs a script directly does not test
# the verb), in a child shell with the scratch package alone on PSModulePath, no
# webhook in reach, and az and Invoke-RestMethod replaced by functions that write
# down each call and change nothing. No tracker is contacted.

. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$cfgPrefix = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot

$typedRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-closeitem-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$typedPkg  = Join-Path $typedRoot 'pkg'
$typedHub  = Join-Path $typedRoot 'hub'
$typedLog  = Join-Path $typedRoot 'log'
$typedCalls = Join-Path $typedRoot 'calls.log'

function Invoke-TypedClose {
    param([string]$Snippet, [string]$WorkItemType = 'Task', [string]$State = 'Active')
    if (Test-Path $typedCalls) { Remove-Item $typedCalls -Force }
    $pkg = $typedPkg -replace "'", "''"; $hub = $typedHub -replace "'", "''"; $log = $typedLog -replace "'", "''"; $calls = $typedCalls -replace "'", "''"
    $pre = @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
`$env:P20_TEST_WI_TYPE = '$WorkItemType'
`$env:P20_TEST_WI_STATE = '$State'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:az {
    Add-Content -Path '$calls' -Value ("az " + (`$args -join ' '))
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'account' -and `$args[1] -eq 'get-access-token' -and `$env:P20_TEST_AZ_FAIL) { `$global:LASTEXITCODE = 1; Write-Error 'ERROR: AADSTS70043: The refresh token has expired.'; return }
    if (`$args[0] -eq 'account' -and `$args[1] -eq 'get-access-token') { return 'stub-token' }
}
function global:Invoke-RestMethod {
    param(`$Uri, `$Headers, `$Method, `$Body)
    `$line = "REST `$Method `$Uri"
    if (`$Body) { `$line += " " + (`$Body -replace '\s+', ' ') }
    Add-Content -Path '$calls' -Value `$line
    if ("`$Method" -eq 'Get') {
        return [pscustomobject]@{ fields = [pscustomobject]@{ 'System.State' = `$env:P20_TEST_WI_STATE; 'System.Title' = 'A scratch item'; 'System.WorkItemType' = `$env:P20_TEST_WI_TYPE; 'System.TeamProject' = 'Acme Project' } }
    }
    return [pscustomobject]@{ id = 4242 }
}
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
`$global:P20Env = [pscustomobject]@{ Tier = 1 }
"@
    $runner = Join-Path $typedRoot ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, ($pre + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n"), (New-Object System.Text.UTF8Encoding($false)))
    $out = & pwsh -NoProfile -File $runner 2>&1
    $text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $callLines = if (Test-Path $typedCalls) { @(Get-Content $typedCalls) } else { @() }
    return [pscustomobject]@{ Text = $text; Calls = $callLines }
}

try {
    New-Item -ItemType Directory -Path $typedPkg, $typedHub, $typedLog -Force | Out-Null
    foreach ($f in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $f) $typedPkg -Force }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $typedPkg -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')  $typedPkg -Recurse -Force
    $hubJson = '{ "hub": 1, "spaces": [ { "slug": "board", "name": "Board", "status": "active", "promptsFolder": "board", "org": "https://dev.azure.com/acme-org" } ] }'
    [System.IO.File]::WriteAllText((Join-Path $typedHub 'hub.json'), $hubJson, (New-Object System.Text.UTF8Encoding($false)))
    New-Item -ItemType Directory -Path (Join-Path $typedHub 'board/current') -Force | Out-Null
    $localCfg = [ordered]@{ quietStart = $true; promptsRoot = $typedHub; activeSpace = 'board' }
    [System.IO.File]::WriteAllText((Join-Path $typedPkg 'config.local.json'), ($localCfg | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

    $itemUri = 'https://dev.azure.com/acme-org/_apis/wit/workitems/4242?api-version=7.1'
    $commentUri = 'https://dev.azure.com/acme-org/Acme%20Project/_apis/wit/workItems/4242/comments?api-version=7.1-preview'

    # -WhatIf: reads the item, prints the transition, writes nothing.
    $r = Invoke-TypedClose "${cfgPrefix}CloseItem 4242 -Comment 'Shipped' -WhatIf"
    $writes = @($r.Calls | Where-Object { $_ -match '^REST (Patch|Post) ' })
    Assert-True "typed CloseItem -WhatIf exits 0" ($r.Text -match 'EXIT=0') $r.Text
    Assert-True "typed CloseItem -WhatIf says what it would set" ($r.Text -match 'Would set Task #4242 : Active -> Closed \(Completed\)') $r.Text
    Assert-True "typed CloseItem -WhatIf makes no PATCH and no comment POST" ($writes.Count -eq 0) ($r.Calls -join ' | ')

    # The real close of a Task: one PATCH with the state and the reason, one comment.
    $r = Invoke-TypedClose "${cfgPrefix}CloseItem 4242 -Comment 'Shipped in the scratch branch'"
    $patches = @($r.Calls | Where-Object { $_ -match '^REST Patch ' })
    $posts = @($r.Calls | Where-Object { $_ -match '^REST Post ' })
    $restCalls = @($r.Calls | Where-Object { $_ -match '^REST ' })
    Assert-True "typed CloseItem exits 0" ($r.Text -match 'EXIT=0') $r.Text
    Assert-True "typed CloseItem reads the item, then PATCHes it once at its address" ($patches.Count -eq 1 -and $patches[0].StartsWith("REST Patch $itemUri ") -and $restCalls[0] -eq "REST Get $itemUri") ($r.Calls -join ' | ')
    # JSON key order differs between hosts, so the body is read back, not matched as text.
    $ops = @(); if ($patches.Count -eq 1) { $ops = @(($patches[0] -replace '^REST Patch \S+ ', '') | ConvertFrom-Json) }
    Assert-True "the PATCH sets System.State to Closed" (@($ops | Where-Object { $_.path -eq '/fields/System.State' -and $_.value -eq 'Closed' -and $_.op -eq 'add' }).Count -eq 1) ($patches -join ' | ')
    Assert-True "the PATCH sets System.Reason to Completed" (@($ops | Where-Object { $_.path -eq '/fields/System.Reason' -and $_.value -eq 'Completed' }).Count -eq 1) ($patches -join ' | ')
    Assert-True "the comment is POSTed once, with the text given" ($posts.Count -eq 1 -and $posts[0].StartsWith("REST Post $commentUri ") -and $posts[0].Contains('Shipped in the scratch branch')) ($posts -join ' | ')
    Assert-True "typed CloseItem reports the result line" ($r.Text -match '\[RESULT\] workItemType=Task targetState=Closed reason=Completed') $r.Text

    # A Bug goes to Resolved / Fixed, and an item already closed is left alone.
    $r = Invoke-TypedClose "${cfgPrefix}CloseItem 4242 -Comment 'Fixed'" -WorkItemType 'Bug'
    $patches = @($r.Calls | Where-Object { $_ -match '^REST Patch ' })
    $ops = @(); if ($patches.Count -eq 1) { $ops = @(($patches[0] -replace '^REST Patch \S+ ', '') | ConvertFrom-Json) }
    Assert-True "typed CloseItem on a Bug sets Resolved / Fixed" (@($ops | Where-Object { $_.path -eq '/fields/System.State' -and $_.value -eq 'Resolved' }).Count -eq 1 -and @($ops | Where-Object { $_.path -eq '/fields/System.Reason' -and $_.value -eq 'Fixed' }).Count -eq 1) ($patches -join ' | ')
    $r = Invoke-TypedClose "${cfgPrefix}CloseItem 4242 -Comment 'Again'" -State 'Closed'
    Assert-True "typed CloseItem on a closed item sends no PATCH, still comments, exits 0" (@($r.Calls | Where-Object { $_ -match '^REST Patch ' }).Count -eq 0 -and @($r.Calls | Where-Object { $_ -match '^REST Post ' }).Count -eq 1 -and $r.Text -match 'EXIT=0') $r.Text

    # az failing with error text: a stated refusal before any REST call. The
    # error text came back through 2>&1 as a non-empty string and was sent as
    # the bearer token.
    $r = Invoke-TypedClose "`$env:P20_TEST_AZ_FAIL = '1'`n${cfgPrefix}CloseItem 4242 -Comment 'Shipped'"
    Assert-True "typed CloseItem with az failing states the token refusal and exits 2" ($r.Text -match 'Error: Failed to get ADO access token\.' -and $r.Text -match "Run 'az login' first\." -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True "typed CloseItem with az failing says it once and calls no REST" ((@([regex]::Matches($r.Text, '(?m)^Error: ')).Count) -eq 1 -and @($r.Calls | Where-Object { $_ -match '^REST ' }).Count -eq 0) (($r.Calls -join ' | ') + ' // ' + $r.Text)
}
catch {
    Assert-True "the typed cases ran to the end without a terminating error" $false $_.Exception.Message
}
finally {
    if (Test-Path $typedRoot) { Remove-Item $typedRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""

# -- Summary -----------------------------------------------------------------

Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
