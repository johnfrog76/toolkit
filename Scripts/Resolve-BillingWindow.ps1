#
# Daily's window -- the one rule for what -Since and -Until may say. Dot-source it.
#
# NOT a runnable verb. Two callers dot-source this file: the billing script the
# agent runs (agent/ado/Get-WeeklyBilling.ps1) and the CLI's Daily
# (Scripts/Get-Daily.ps1), which checks the window before it runs that script so
# a refusal is stated once, in the CLI's own shape. The agent checks the shape
# before it starts the script, with the same sentences (consts.json billing.text).
#
#     . (Join-Path $PSScriptRoot 'Resolve-BillingWindow.ps1')
#     $w = Resolve-P20BillingWindow -Since $Since -Until $Until
#     if ($w.Error) { ... refuse with $w.Error ... }
#     if ($w.HasWindow) { $w.Since; $w.Until }     # [datetime], midnight
#
# A window is both ends or neither. Each end is a day written yyyy-MM-dd, read
# with the invariant culture -- [datetime]::Parse read '10/5/2026' by the machine's
# culture and threw on anything else. A window that ends before it starts is
# refused; one day (-Since and -Until the same) is a window.
#
# PowerShell 5.1 compatible (ASCII only).
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Get-Consts.ps1') }

function Resolve-P20BillingWindow {
    param(
        [string]$Since,
        [string]$Until
    )
    $text = (Get-P20Consts).billing.text
    $answer = @{ Error = ''; HasWindow = $false; Since = $null; Until = $null }
    if (-not $Since -and -not $Until) { return $answer }
    if (-not $Since -or -not $Until) {
        $answer.Error = [string]$text.halfWindow
        return $answer
    }
    $days = @{}
    foreach ($end in @(@('-Since', $Since), @('-Until', $Until))) {
        $parsed = [datetime]::MinValue
        $ok = [datetime]::TryParseExact($end[1], 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
        if (-not $ok) {
            $answer.Error = ([string]$text.notADay).Replace('{name}', $end[0]).Replace('{value}', $end[1])
            return $answer
        }
        $days[$end[0]] = $parsed
    }
    if ($days['-Since'] -gt $days['-Until']) {
        $answer.Error = ([string]$text.backwards).Replace('{since}', $Since).Replace('{until}', $Until)
        return $answer
    }
    $answer.HasWindow = $true
    $answer.Since = $days['-Since']
    $answer.Until = $days['-Until']
    return $answer
}
