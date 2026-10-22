#
# Prompt20Toolkit -- GENERATED FILE, do not hand-edit.
# Regenerate with: ./Update-ToolkitManifest.ps1
#
# AliasesToExport is what makes the prefixed aliases auto-load in shells that never ran the
# profile (agent tool calls, pwsh -c, CI). PowerShell only consults the manifest
# when resolving an unknown command, so an alias missing from this list works
# interactively and fails everywhere else.
#
@{
    RootModule        = 'Prompt20Toolkit.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = '4c1d7e2a-3b6f-4a9e-9d21-7f0c5e8b2a61'
    Author            = 'Toolkit'
    Description       = 'Auto-loading shim for the Toolkit Toolkit (utilities.psm1 at the package root).'
    PowerShellVersion = '5.1'

    # The shim imports utilities.psm1 -Global, which defines these itself.
    # Declaring '*' would force a load just to enumerate; naming them is what
    # lets PowerShell resolve {cliPrefix}Status WITHOUT importing anything first.
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    AliasesToExport = @(
        'tkAddPRReview',
        'tkAgent',
        'tkArchive',
        'tkBillable',
        'tkCloseItem',
        'tkCloseWorkItem',
        'tkConfig',
        'tkConnect',
        'tkCover',
        'tkDashboard',
        'tkEditItem',
        'tkEditWorkItem',
        'tkEnv',
        'tkGetPRComments',
        'tkHome',
        'tkHub',
        'tkInstallAutoload',
        'tkLog',
        'tkMenu',
        'tkMove',
        'tkMoveDesign',
        'tkMyPRs',
        'tkMyWork',
        'tkNewAdoItem',
        'tkNewDesign',
        'tkNewItem',
        'tkNewPR',
        'tkNewPrompt',
        'tkNewSpace',
        'tkPlan',
        'tkPrompt',
        'tkPublishPR',
        'tkRemoveSpace',
        'tkReplyPR',
        'tkRepos',
        'tkRetireSpace',
        'tkSetup',
        'tkStampDesign',
        'tkStart',
        'tkStatus',
        'tkSwitchOrg',
        'tkSwitchSpace',
        'tkSync',
        'tkTest',
        'tkTestCompat',
        'tkTestMenu',
        'tkTestSync',
        'tkTestToolkit',
        'tkThreadHash',
        'tkUpdate',
        'tkWeb'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('toolkit', 'toolkit', 'cards')
            ProjectUri = 'https://github.com/johnfrog76/toolkit'
        }
    }
}
