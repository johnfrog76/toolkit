<#
    A probe module for the bridge's results table (Tests/fixtures/bridge/results.json).

    NOT shipped and never in Config/: the two suites that read the table copy
    this file, its sibling .ps1 and the bridge-probe/ folder into the Config/
    of a SCRATCH package and switch features.bridgeProbe on there. Each verb is
    one row's case, driven through the real guard (Invoke-ToolkitScript) or the
    real wrapper refusal (Write-WrapperRefusal), so the table is about the
    refusal contract and not about whichever shipped verb implements it today.

    Commands is a PLAIN hashtable: Import-PowerShellDataFile, the only reader
    the loader uses, refuses a type cast such as [ordered].
#>
@{
    Feature  = 'bridgeProbe'

    Commands = @{
        'ProbeOk'      = 'Invoke-P20BridgeProbeOk'
        'ProbeStated'  = 'Invoke-P20BridgeProbeStated'
        'ProbeWrapper' = 'Invoke-P20BridgeProbeWrapper'
        'ProbeThrows'  = 'Invoke-P20BridgeProbeThrows'
        'ProbeSilent'  = 'Invoke-P20BridgeProbeSilent'
        'ProbeStale'   = 'Invoke-P20BridgeProbeStale'
        'ProbeSlow'    = 'Invoke-P20BridgeProbeSlow'
    }

    Help     = @{
        'ProbeOk'      = @{ category = 'test'; description = 'Probe: succeeds'; usage = '{cliPrefix}ProbeOk [-Help]' }
        'ProbeStated'  = @{ category = 'test'; description = 'Probe: a script states its refusal and exits 2'; usage = '{cliPrefix}ProbeStated [-Help]' }
        'ProbeWrapper' = @{ category = 'test'; description = 'Probe: the wrapper states the refusal'; usage = '{cliPrefix}ProbeWrapper [-Help]' }
        'ProbeThrows'  = @{ category = 'test'; description = 'Probe: a script throws'; usage = '{cliPrefix}ProbeThrows [-Help]' }
        'ProbeSilent'  = @{ category = 'test'; description = 'Probe: a script exits 3 and says nothing'; usage = '{cliPrefix}ProbeSilent [-Help]' }
        'ProbeStale'   = @{ category = 'test'; description = 'Probe: a refusal caught inside the verb, then a throw'; usage = '{cliPrefix}ProbeStale [-Help]' }
        'ProbeSlow'    = @{ category = 'test'; description = 'Probe: outlives its timeout'; usage = '{cliPrefix}ProbeSlow [-Help]'; bridgeTimeoutSeconds = 3 }
    }
}
