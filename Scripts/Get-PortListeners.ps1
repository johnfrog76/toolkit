<#
.SYNOPSIS
    Who is listening on a TCP port, and what is that process called. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry. It exists because
    both launchers ask the same two questions of the same operating system, and
    a second copy of `Get-NetTCPConnection` / `lsof` is a drift bug waiting for
    one of them to be edited alone.

    They ask it for different reasons, and that difference stays with the
    caller: Start-Web.ps1 asks so the sweep can decide whether it may STOP a
    listener, and Start-Agent.ps1 asks so it can NAME one it must not start
    beside. Neither policy lives here.

    Windows answers through Get-NetTCPConnection and Win32_Process, falling back
    to netstat and Get-Process; everything else through lsof and ps. A machine with neither answers "nothing", which
    is the honest reading -- a probe that cannot see is not evidence of an
    empty port, and both callers treat it that way.

        . (Join-Path $PSScriptRoot 'Get-PortListeners.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

function Get-P20IsWindowsHost {
    return ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
}

function ConvertFrom-P20Netstat {
    <#
        The listener PIDs for one port out of `netstat -ano` text. Pure, so the
        suite can feed it a Windows transcript on any host.

        A listening socket is the row whose FOREIGN address ends in :0
        (0.0.0.0:0, [::]:0, *:*) -- matched on that rather than on the word
        LISTENING, which Windows translates.
    #>
    param([string[]]$Lines, [Parameter(Mandatory = $true)][int]$Port)
    $ids = @()
    foreach ($line in $Lines) {
        $m = [regex]::Match([string]$line, '^\s*TCP\s+\S*:(\d+)\s+\S*:(0|\*)\s+\S+\s+(\d+)\s*$')
        if ($m.Success -and [int]$m.Groups[1].Value -eq $Port) { $ids += [int]$m.Groups[3].Value }
    }
    return @($ids | Where-Object { $_ } | Select-Object -Unique)
}

function Get-P20PortListenerIds {
    <#
        The process ids listening on a port. Empty when nothing is, when the
        probe is unavailable, and when it fails -- never an exception.
    #>
    param([Parameter(Mandatory = $true)][int]$Port)

    $ids = @()
    try {
        if (Get-P20IsWindowsHost) {
            if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
                $ids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty OwningProcess)
            }
            # Get-NetTCPConnection lives in the NetTCPIP module, which does not
            # autoload in a shell whose PSModulePath was narrowed to one package --
            # the isolation AGENTS.md prescribes. There the probe saw nothing,
            # `Web -Stop` said "not running" while netstat showed node on 5174 and
            # python on 4100, and the orphans were reused. netstat is
            # an executable, not a module, so it answers in any shell.
            if ($ids.Count -eq 0 -and (Get-Command netstat -ErrorAction SilentlyContinue)) {
                $ids = @(ConvertFrom-P20Netstat -Lines @(& netstat -ano -p TCP 2>$null) -Port $Port)
                if ($ids.Count -eq 0) { $ids = @(ConvertFrom-P20Netstat -Lines @(& netstat -ano -p TCPv6 2>$null) -Port $Port) }
            }
        }
        elseif (Get-Command lsof -ErrorAction SilentlyContinue) {
            $ids = @(& lsof -nP "-iTCP:$Port" -sTCP:LISTEN -t 2>$null)
        }
    }
    catch { $ids = @() }
    return @($ids | Where-Object { $_ } | ForEach-Object { [int]$_ } | Select-Object -Unique)
}

function Get-P20ProcessNameById {
    <#
        The image name of a process, or '' when it cannot be read. '' is a
        real answer: a process may be gone, or owned by another user.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Justification = 'The ps here is /bin/ps: the Windows branch returns above it, and off Windows ps is not an alias.')]
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    if ($ProcessId -le 0) { return '' }
    try {
        if (Get-P20IsWindowsHost) {
            # CimCmdlets can be missing for the same reason NetTCPIP can (a narrowed
            # PSModulePath); Get-Process is in the core and answers 'node' rather
            # than 'node.exe', which Test-IsDevServerProcess accepts.
            if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
                if ($proc) { return [string]$proc.Name }
            }
            $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($p) { return [string]$p.ProcessName }
            return ''
        }
        $name = & ps -o comm= -p $ProcessId 2>$null
        if ($name) { return [string](Split-Path ([string]$name).Trim() -Leaf) }
        return ''
    }
    catch { return '' }
}
