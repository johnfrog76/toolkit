<#
.SYNOPSIS
    The one way this package starts a long-running child process. Dot-source it.

.DESCRIPTION
    Not a command -- there is no alias, no menu row and no help entry for this
    file. It exists so that "start a server, write its output to a log, and
    RETURN" has exactly one implementation, shared by Start-Agent.ps1,
    Start-Web.ps1 and Start-Work.ps1 (StartWork -Launch, which starts an agent
    session in a worktree and returns its PID).

    The promise is the return. `{prefix}Agent` and `{prefix}Web -Dev` are launchers: they
    hand back a PID and a URL and the caller carries on. docs/QUICKSTART.md names
    "agent tool calls, `pwsh -c`, and CI" as the shells this package is for, and
    every one of those reads a command's output through a PIPE.

    A pipe is where the promise used to break, on Windows only. Start-Process
    with -RedirectStandardOutput goes down PowerShell's native CreateProcess
    path with bInheritHandles = TRUE, and that inherits every INHERITABLE handle
    the caller holds -- not only the two log files it meant to hand over. When
    the caller's own stdout is a pipe (`pwsh -c '{prefix}Agent' | cat`), the child
    gets the write end of that pipe too and holds it for its whole life. pwsh
    exits, the launcher has done its job, and the reader still never sees EOF:
    the call returns only when the agent it started is stopped. On a Mac and on
    Linux the same code is fine, because .NET closes every descriptor above the
    standard three across the exec -- which is why this was found on Windows.

    The fix is one Win32 flag. The caller's std handles, and every other
    inheritable pipe it holds except stdin, are marked non-inheritable for the
    length of the CreateProcess call and restored immediately afterwards, so the
    only handles that cross are the two log files Start-Process opens for the
    redirection (and stdin). Every pipe, not only the std two: Windows
    PowerShell 5.1 holds a second inheritable copy of its stdout, and a launcher
    can itself have inherited its caller's pipes -- Disable-CallerHandleInheritance
    has both. Restoring matters: PowerShell hands its std handles to ordinary
    native commands as well, and a shell left with non-inheritable ones would
    stop showing their output.

    Not solved by "redirect on every platform" -- the redirection was already
    there on every platform. The leak is beside it, not instead of it.

    THE THIRD THING THIS FILE OWNS, ON macOS AND LINUX: the child's session
    and its stdin. .NET starts a child in the caller's process group with the
    caller's stdin, so a server started from a terminal shared that terminal
    with the shell that started it: Vite, seeing a TTY on stdin, bound its
    keyboard shortcuts and put the terminal into raw mode, and the shell's
    readline went quiet;
    a Ctrl+C in that terminal reached the servers too; and a server started
    from a tool call died when the tool call's shell was reaped, because it was
    still in that shell's session.
    Resolve-SessionLeader
    answers with a perl one-liner -- perl ships with macOS and every Linux this
    package has met -- that starts a NEW SESSION, opens /dev/null as stdin and
    execs the real command in place, so the PID the launcher records is the
    server's. Vite's own stdin-end handler is answered by the caller with
    CI=true in the child's environment (-Environment), which is Vite's
    documented switch for exactly that. Windows is unchanged here: its children
    get their own console handles from CreateProcess, and CI=true does the
    shortcut half there too.

    Dot-sourced rather than reached through utilities.psm1 because both callers
    have to work as a plain script with no module imported: that is how both of
    their test suites drive them, and how Start-Web.ps1 drives Start-Agent.ps1.

        . (Join-Path $PSScriptRoot 'Start-Detached.ps1')

    THE SECOND WINDOWS-ONLY THING THIS FILE OWNS: what may be handed to
    CreateProcess. Start-Process with -RedirectStandardOutput is
    UseShellExecute = false, so the file it is given has to be a real process
    image. `npm` on Windows is not: a Node install ships npm.ps1, npm.cmd and a
    bash `npm` side by side, PowerShell ranks the .ps1 first, and neither a
    .ps1 nor a .cmd is a Win32 application. Both fail with

        %1 is not a valid Win32 application.

    which is exactly what `{prefix}Web -Dev` did on Windows. So there are two steps,
    and both live here: Resolve-LaunchExecutable picks an APPLICATION (never
    the .ps1), and Resolve-DetachedCommand wraps a batch shim in
    `cmd.exe /d /s /c "..."`. Everything that is already a process image goes
    through untouched, on every platform.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

function Resolve-LaunchExecutable {
    <#
        The path this machine would actually RUN for a command name -- never a
        PowerShell script.

        `Get-Command npm` on Windows answers npm.ps1, because PowerShell ranks
        an ExternalScript above an Application, and Start-Process cannot use a
        .ps1 as a process image. -CommandType Application is the whole fix for
        that half; the preference for .cmd/.bat/.exe below picks the shim
        Windows can be made to run over the extension-less bash script that
        sits beside it. On macOS and Linux there is one candidate and it is
        returned unchanged.

        Returns $null when the command is not on PATH -- the caller states its
        own refusal, because "npm not found" and "python not found" are
        different sentences.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $all = @(Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { return $null }
    $preferred = $all | Where-Object { $_.Source -match '\.(cmd|bat|exe)$' } | Select-Object -First 1
    if ($preferred) { return $preferred.Source }
    return $all[0].Source
}

function Resolve-SessionLeader {
    <#
        The wrapper that gives a child its OWN session and a quiet stdin on
        macOS and Linux, as @{ FilePath = <perl>; ArgumentList = @('-e', <program>, '--') },
        ready to have the real command appended. $null on Windows, and on a
        host with no perl -- then the child is launched as it always was, in
        the caller's group, and nothing refuses.

        The program is written with no quote character in it on purpose:
        Start-Process joins -ArgumentList into one line that .NET re-splits,
        so the whole program travels as one double-quoted argument and a quote
        inside it would end it early.
    #>
    param([switch]$ForWindows)

    if ($ForWindows) { return $null }
    $perl = Get-Command perl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $perl) { return $null }
    # setsid: a new session, no controlling terminal -- a SIGHUP or a Ctrl+C in
    # the terminal that started us does not reach the child. /dev/null on
    # STDIN: a child that asks whether stdin is a terminal hears no. exec in
    # place: the PID stays the launcher's answer. exit 127 is only reached if
    # exec itself failed.
    # STDIN is /dev/null unless the launch named a file for it: then
    # P20_DETACHED_STDIN carries the path (Start-DetachedProcess -StdInFile).
    # STDOUT and STDERR are the two LOG FILES, opened here and appended to:
    # Start-Process's redirection on macOS and Linux is a pipe that pwsh copies
    # into the file while pwsh lives, so everything a child wrote after the
    # launcher returned was lost -- the agent's log stopped at its startup
    # lines, and a session would have had no transcript at all. Opened in the
    # child, the files are the child's own. Start-DetachedProcess sets all three
    # variables for every launch, or removes them, so a child never inherits a
    # stale one into a launch of its own.
    $program = 'use POSIX; POSIX::setsid(); open(STDIN, q{<}, $ENV{P20_DETACHED_STDIN} // q{/dev/null}); open(STDOUT, q{>>}, $ENV{P20_DETACHED_STDOUT}) if defined $ENV{P20_DETACHED_STDOUT}; open(STDERR, q{>>}, $ENV{P20_DETACHED_STDERR}) if defined $ENV{P20_DETACHED_STDERR}; exec { $ARGV[0] } @ARGV; exit 127'
    return @{ FilePath = $perl.Source; ArgumentList = @('-e', ('"' + $program + '"'), '--') }
}

function Resolve-DetachedCommand {
    <#
        Turns (FilePath, ArgumentList) into the pair CreateProcess will accept,
        and returns it as @{ FilePath = ...; ArgumentList = ... }.

        On Windows a .cmd or .bat is not a process image -- it is input to a
        command interpreter -- so it is launched as

            cmd.exe /d /s /c ""<path to npm.cmd>" run dev"

        /d skips AutoRun, /s plus the outer quotes is the documented way to
        hand cmd one command line it will not re-parse, and every argument that
        contains a space or a quote is quoted individually. Anything else --
        python.exe, node, a Unix npm -- is returned exactly as it came in,
        so this is a Windows-only widening and not a change of launch method.

        Chosen over resolving `node` plus npm's own CLI script: the cmd wrapper
        works for ANY batch shim (npm, npx, a corepack or Volta shim, whatever
        a future caller launches) and does not depend on npm's internal layout,
        which differs between an MSI install, nvm4w, Scoop and Volta. The cost
        is one extra process between the launcher and vite, and the callers
        already stop a tree rather than a PID.

        Off Windows, with a -SessionLeader (Resolve-SessionLeader's answer),
        the command is appended to the leader's own argv: the leader runs
        first and execs the command in its place. Every argument that carries
        a space or a quote is double-quoted, and a quote inside it escaped, for
        the same joined-then-split reason as the cmd.exe line below. Without a
        leader the command is passed through exactly as it came in.

        Pure and parameterised on the platform so the suites can assert the
        argv shape for Windows from a Mac -- there is no other way to test it
        here -- and the session-leader shape with a leader handed in.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$ForWindows,
        [hashtable]$SessionLeader
    )

    if (-not $ForWindows) {
        if (-not $SessionLeader) {
            return @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
        }
        $wrapped = @($SessionLeader.ArgumentList) + @($FilePath)
        foreach ($a in $ArgumentList) {
            if ($null -eq $a) { continue }
            if ($a -match '[\s"]') { $wrapped += '"' + ($a -replace '"', '\"') + '"' }
            else { $wrapped += $a }
        }
        return @{ FilePath = $SessionLeader.FilePath; ArgumentList = $wrapped }
    }

    $ext = [System.IO.Path]::GetExtension($FilePath)
    if ($ext -ne '.cmd' -and $ext -ne '.bat') {
        return @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
    }

    $inner = '"' + $FilePath + '"'
    foreach ($a in $ArgumentList) {
        if ($null -eq $a) { continue }
        if ($a -match '[\s"]') { $inner += ' "' + ($a -replace '"', '\"') + '"' }
        else { $inner += ' ' + $a }
    }

    $shell = $env:ComSpec
    if (-not $shell) { $shell = 'cmd.exe' }
    # The parentheses are load-bearing: `,` binds tighter than `+` in
    # PowerShell, so @('/c', '"' + $x + '"') is (@('/c','"') + $x + '"') --
    # four elements, none of them the one that was meant.
    return @{ FilePath = $shell; ArgumentList = @('/d', '/s', '/c', ('"' + $inner + '"')) }
}

function Disable-CallerHandleInheritance {
    <#
        Marks this process's stdout and stderr, and every other inheritable PIPE
        handle it holds except stdin, non-inheritable, and returns what it
        changed so Restore-CallerHandleInheritance can put it back.

        Why every pipe and not only the two std handles: a pipe's reader
        sees EOF only when the LAST write end closes, and the std handles are
        not the only write ends a launcher can hold. Two were found on Windows:

          - Windows PowerShell 5.1 holds a second, inheritable handle to its own
            stdout pipe, at a different value from GetStdHandle's. It is there
            before any script runs -- a bare .NET Framework 4.8 console program
            that never touches Console has it too -- so it comes from the .NET
            Framework runtime's startup, not from PowerShell, and pwsh 7 (.NET
            Core) has none. Clearing the std handle left this copy to cross, and
            the reader of `powershell -c {prefix}Agent | ...` waited for the agent.
          - Whatever the launcher itself inherited. `cmd /c "pwsh -c {prefix}Agent |
            findstr x"` run by something that captures cmd's output: cmd's own
            stdout is an inheritable pipe, the launcher inherits it, and the
            agent would carry it on and hold the outer reader -- on both hosts.

        So the rule is the mechanism's, not a list of known culprits: no pipe
        the caller holds crosses. The handles come from one snapshot of this
        process's handle table (NtQueryInformationProcess,
        ProcessHandleInformation, Windows 8 and later); where that is not
        available the std handles are still cleared, as they always were.
        stdin is left alone: .NET hands GetStdHandle(STD_INPUT) to the child
        as its stdin, so clearing it would give the child an invalid one, and
        a held READ end keeps no reader waiting. Off Windows the session
        leader gives the child its own stdin (see the header).

        Chosen over an explicit inherit list (PROC_THREAD_ATTRIBUTE_HANDLE_LIST)
        because that list only exists on a CreateProcess this file would have to
        call itself, replacing Start-Process -- the log files, the working
        directory, the hidden window and the Process object the callers read --
        to fix a leak that one more loop around the existing flag closes.

        Windows only -- returns $null everywhere else, and on any failure. This
        is a hardening step around a launch that already works; it must never be
        the reason a launch does not happen.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Process-local handle flag, restored by the caller in a finally.')]
    param()

    $isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    if (-not $isWin) { return $null }

    try {
        # A type name of its own (not the old HandleFlags): a shell
        # that loaded the old type keeps it for its life, and -as [type] would
        # then find a class without the members below.
        if (-not ('Toolkit.PipeInheritance' -as [type])) {
            Add-Type -Namespace 'Toolkit' -Name 'PipeInheritance' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool GetHandleInformation(System.IntPtr hObject, out uint lpdwFlags);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool SetHandleInformation(System.IntPtr hObject, uint dwMask, uint dwFlags);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern uint GetFileType(System.IntPtr hFile);

[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetCurrentProcess();

[System.Runtime.InteropServices.DllImport("ntdll.dll")]
public static extern int NtQueryInformationProcess(System.IntPtr hProcess, int infoClass, System.IntPtr info, int length, out int returnLength);

// Every handle value in this process, from one ProcessHandleInformation (51)
// snapshot; null when the call is not available. The snapshot is two
// ULONG_PTRs, then one entry per handle: HandleValue, HandleCount and
// PointerCount (pointer-sized), then four ULONGs.
public static long[] HandleValues() {
    int size = 0x10000;
    for (int attempt = 0; attempt < 8; attempt++) {
        System.IntPtr buf = System.Runtime.InteropServices.Marshal.AllocHGlobal(size);
        try {
            int ret;
            int status = NtQueryInformationProcess(GetCurrentProcess(), 51, buf, size, out ret);
            // INFO_LENGTH_MISMATCH, BUFFER_OVERFLOW, BUFFER_TOO_SMALL: grow, ask again.
            bool tooSmall = (status == unchecked((int)0xC0000004));
            if (status == unchecked((int)0x80000005)) { tooSmall = true; }
            if (status == unchecked((int)0xC0000023)) { tooSmall = true; }
            if (tooSmall) {
                size = System.Math.Max(size * 2, ret + 0x1000);
                continue;
            }
            if (status != 0) { return null; }
            int ptr = System.IntPtr.Size;
            long count = System.Runtime.InteropServices.Marshal.ReadIntPtr(buf).ToInt64();
            int entry = ptr * 3 + 16;
            long[] values = new long[count];
            for (long i = 0; i < count; i++) {
                System.IntPtr at = new System.IntPtr(buf.ToInt64() + ptr * 2 + i * entry);
                values[i] = System.Runtime.InteropServices.Marshal.ReadIntPtr(at).ToInt64();
            }
            return values;
        }
        finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(buf); }
    }
    return null;
}
'@ -ErrorAction Stop
        }

        $type = [Toolkit.PipeInheritance]
        $invalid = New-Object System.IntPtr(-1)
        $stdin = $type::GetStdHandle(-10)

        # STD_OUTPUT_HANDLE and STD_ERROR_HANDLE whatever they are (a pipe, a
        # file, the console), then every other pipe the snapshot names. The
        # second element says whether the handle must be a pipe to be cleared.
        $candidates = @()
        foreach ($id in @(-11, -12)) {
            $handle = $type::GetStdHandle($id)
            if ($handle -eq [System.IntPtr]::Zero -or $handle -eq $invalid) { continue }
            $candidates += , @($handle, $false)
        }
        $values = $null
        try { $values = $type::HandleValues() } catch { $values = $null }
        foreach ($v in @($values)) {
            if ($null -eq $v) { continue }
            $candidates += , @((New-Object System.IntPtr([long]$v)), $true)
        }

        $saved = @()
        $seen = @{}
        foreach ($c in $candidates) {
            $handle = $c[0]
            $key = $handle.ToInt64()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            if ($handle -eq $stdin) { continue }
            $flags = 0
            if (-not $type::GetHandleInformation($handle, [ref]$flags)) { continue }
            # HANDLE_FLAG_INHERIT = 0x1. A handle that would not cross is left
            # alone and asked nothing more. FILE_TYPE_PIPE = 3.
            if (($flags -band 1) -eq 0) { continue }
            if ($c[1] -and $type::GetFileType($handle) -ne 3) { continue }
            [void]$type::SetHandleInformation($handle, 1, 0)
            $saved += , @($handle, $flags)
        }
        return $saved
    }
    catch {
        Write-Verbose "Could not clear handle inheritance: $($_.Exception.Message)"
        return $null
    }
}

function Restore-CallerHandleInheritance {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Undoes Disable-CallerHandleInheritance; the caller owns the pairing.')]
    param($Saved)

    if (-not $Saved) { return }
    try {
        foreach ($entry in $Saved) {
            [void][Toolkit.PipeInheritance]::SetHandleInformation($entry[0], 1, ($entry[1] -band 1))
        }
    }
    catch {
        Write-Verbose "Could not restore handle inheritance: $($_.Exception.Message)"
    }
}

function Push-ProcessEnvironment {
    <#
        Applies a map of environment variables to THIS process and returns what
        they were, for Pop-ProcessEnvironment to put back. A $null value REMOVES
        the variable -- how a caller keeps a live TEAMS_WEBHOOK_* the module's
        .env loader put in this shell out of a server it starts.

        Through the Env: drive, not [Environment]::SetEnvironmentVariable: a
        $null handed to that .NET string parameter arrives as "", which on this
        runtime leaves the variable set and empty rather than removing it.

        Start-DetachedProcess uses it for the length of one launch. Start-Web.ps1
        uses it around a whole start, because the agent's LAUNCHER has to see the
        same environment its child will -- it compares the hub it asks for with
        the hub a running agent reports.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Process-local, and undone by Pop-ProcessEnvironment in the caller''s finally.')]
    param([hashtable]$Environment)

    $saved = @{}
    if (-not $Environment) { return $saved }
    foreach ($k in $Environment.Keys) {
        $saved[$k] = if (Test-Path "Env:$k") { (Get-Item "Env:$k").Value } else { $null }
        if ($null -eq $Environment[$k]) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
        else { Set-Item -Path "Env:$k" -Value ([string]$Environment[$k]) }
    }
    return $saved
}

function Pop-ProcessEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Undoes Push-ProcessEnvironment; the caller owns the pairing.')]
    param([hashtable]$Saved)

    if (-not $Saved) { return }
    foreach ($k in $Saved.Keys) {
        if ($null -eq $Saved[$k]) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
        else { Set-Item -Path "Env:$k" -Value $Saved[$k] }
    }
}

function Start-DetachedProcess {
    <#
        Starts a background process whose stdout and stderr go to the two log
        files given, which holds nothing of the caller's open, and which -- on
        macOS and Linux -- runs in its own session with /dev/null as stdin.

        -Environment sets variables in the CHILD's environment only: they are
        set in this process for the length of the launch and put back after,
        which works on 5.1 as well as 7 (Start-Process -Environment is 7.4+).
        A $null value keeps the variable OUT of the child (Push-ProcessEnvironment).

        -StdInFile gives the child a FILE as its stdin instead of nothing --
        how StartWork -Launch hands a session its prompt, which is many lines
        and cannot cross a joined command line whole. On Windows it is
        Start-Process's own -RedirectStandardInput (a file handle, not a pipe,
        so nothing of the caller's is held); on macOS and Linux the session
        leader opens it in place of /dev/null, through P20_DETACHED_STDIN.

        Returns the process object, so the caller still writes its own PID file
        and does its own liveness check -- this owns the launch and nothing else.
        Throws what Start-Process throws; both callers already catch it and turn
        it into a Write-CliError.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A launcher; -WhatIf belongs to the verb that calls it.')]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StdOutLog,
        [Parameter(Mandatory = $true)][string]$StdErrLog,
        [hashtable]$Environment,
        [string]$StdInFile = ''
    )

    $isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

    # The one place a batch shim becomes something CreateProcess can run, and
    # the one place a Unix child gets its own session.
    $leader = Resolve-SessionLeader -ForWindows:$isWin
    $launch = Resolve-DetachedCommand -FilePath $FilePath -ArgumentList $ArgumentList -ForWindows:$isWin -SessionLeader $leader

    $startArgs = @{
        FilePath               = $launch.FilePath
        WorkingDirectory       = $WorkingDirectory
        RedirectStandardOutput = $StdOutLog
        RedirectStandardError  = $StdErrLog
        PassThru               = $true
    }
    if ($launch.ArgumentList -and @($launch.ArgumentList).Count -gt 0) { $startArgs['ArgumentList'] = $launch.ArgumentList }
    if ($isWin) { $startArgs['WindowStyle'] = 'Hidden' }

    # The child's stdin: a file when one was named, else the leader's /dev/null.
    $childEnv = @{}
    if ($Environment) { foreach ($k in $Environment.Keys) { $childEnv[$k] = $Environment[$k] } }
    if ($leader) {
        $childEnv['P20_DETACHED_STDIN'] = $null
        if ($StdInFile) { $childEnv['P20_DETACHED_STDIN'] = $StdInFile }
        # The leader opens the logs itself (see Resolve-SessionLeader); the
        # redirection below still truncates them first and is never written to.
        $childEnv['P20_DETACHED_STDOUT'] = $StdOutLog
        $childEnv['P20_DETACHED_STDERR'] = $StdErrLog
    }
    elseif ($StdInFile) { $startArgs['RedirectStandardInput'] = $StdInFile }

    # The child's environment is this process's at the moment of the launch.
    $savedEnv = Push-ProcessEnvironment -Environment $childEnv
    $saved = Disable-CallerHandleInheritance
    try {
        return Start-Process @startArgs
    }
    finally {
        Restore-CallerHandleInheritance $saved
        Pop-ProcessEnvironment -Saved $savedEnv
    }
}
