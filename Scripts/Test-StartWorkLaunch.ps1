# Whether `StartWork <id> -Launch` has a session to start: `claude` found on the
# PATH as an application (D-AR13). The one rule behind the inventory's StartWork
# launch row (Scripts/Get-OptionalSurfaces.ps1) and the standup's delegate
# suggestion (Scripts/Get-Standup.ps1); the agent's start_work_launch
# (agent/core/config.py) is the same rule, and /env carries it.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.

function Test-P20StartWorkLaunch {
    return [bool](Get-Command claude -CommandType Application -ErrorAction SilentlyContinue)
}
