[CmdletBinding()]
param(
    # -Id is the same parameter: an offline card still needs a number, and
    # "-Id 7" reads better beside -Title than "-WorkItemId 7".
    [Parameter(Mandatory = $false, Position = 0)]
    [Alias('Id')]
    # A STRING: a work item number, or the four-character id of a
    # card with no work item (K7M2). Validated below, against the one id rule.
    [string]$WorkItemId = '',

    # OFFLINE MODE. Supplying -Title means "scaffold a card from nothing", with
    # no az call anywhere -- the Tier-2 half of "a machine without the tracker
    # still produces and maintains prompt files". The file is identical in shape
    # to an ADO-sourced one; the fields that would have come from the board say
    # so in words instead of being silently blank.
    [Parameter(Mandatory = $false)]
    [string]$Title = "",

    # Any key in workItemTypes (config) -- Task, Bug, User Story, Feature by
    # default. 'UserStory' and 'userstory' are accepted for the one that has a
    # space in it, because a shell argument with a space is a nuisance.
    [Parameter(Mandatory = $false)]
    [string]$Type = "Task",

    [Parameter(Mandatory = $false)]
    [string]$AssignTo = "",

    # -Date YYYY-MM-DD: the day the work WAS, when a card is written after the
    # fact -- a meeting attended yesterday, a call last week. It becomes the
    # **Created:** stamp, so Daily lands the card on that day rather than on the
    # day the card was typed.
    [Parameter(Mandatory = $false)]
    [string]$Date = "",

    [Parameter(Mandatory = $false)]
    [switch]$ReadOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder,

    # A card born with its picture (docs/hub/cards.md, "A card's pictures"): for a
    # GUI issue the snap IS the report. Attached after the card is written, by the
    # same code the Cover verb runs (Scripts/Add-CardImage.ps1); checked before
    # anything is written, so a refused picture leaves no card behind.
    [Parameter(Mandatory = $false)]
    [string]$Cover = "",

    [Parameter(Mandatory = $false)]
    [string]$Before = "",

    # The design this card is worked against (docs/hub/cards.md, "2. The sections
    # -- by type, from the template"): a design's file name, its stem, or its id (any unique prefix of four
    # or more). Resolved before anything is written; the card gets one header
    # line, `> Design: [<title>](<link>) <id>`, under its Template line.
    [Parameter(Mandatory = $false)]
    [string]$Design = "",

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

# The two links a card carries back into the package, and the standalone
# Resolve-P20PackageLink fallback they need when this script runs with no module.
# One file builds those lines and one file refreshes them, so a card written
# today and a card refreshed after the hub moved come out identical.
#
. (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')


# Configuration - read from toolkit config
$cfg = $global:P20Config

# Not a parameter default: an address hardcoded in source is wrong in a tool
# meant to be forked. Config first, then whoever az is signed in as.
$org = $cfg.Org
$promptsRoot = $cfg.PromptsRoot

# -- Where the card goes -------------------------------------------------------
# -OutputFolder is normally a name relative to the prompt store ("current",
# "archive"), but an absolute path must be honoured as given -- joining that onto
# promptsRoot produced a doubled path and failed at write time. Both callers go
# through here, so the hub is checked once and only when the hub is what is being
# read: a rooted -OutputFolder needs no hub at all.
#
# The check itself matters on Windows: Join-Path on a root whose DRIVE does not
# exist THROWS ("Cannot find drive"), and the Test-Path under it then binds a
# null and throws again -- two stack traces where one sentence belongs.
#Test-P20HubRoot is the
# safe question and Get-P20HubMissingMessage is the one sentence every verb says.
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')

# The one byte contract for a file this tool writes into the user's hub.
# Scripts/Write-CardText.ps1 owns it; a card CREATE passes -New and comes out
# LF on every host. This script used to call WriteAllText itself, twice, which
# was a second copy of the BOM rule and no copy at all of the LF one.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
# The cross-half literals this file writes into a card: the **Created:** stamp,
# whose **Closed:** twin the billing timeline reads. See consts.json.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
# The one id rule. Loaded HERE, before the argument guard, because the guard asks
# it whether -Id is an id at all (it is dot-sourced again further down, harmlessly,
# beside the type table that has always lived next to it).
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')

function Resolve-TargetFolder {
    param([string]$Folder)
    if ([System.IO.Path]::IsPathRooted($Folder)) { return $Folder }
    if (-not (Test-P20HubRoot $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    return (Join-Path $promptsRoot $Folder)
}

# Default OutputFolder to <promptsFolder>/current based on active org
if (-not $OutputFolder) {
    $pf = $cfg.PromptsFolder
    if (-not $pf) {
        Write-CliError -Message 'No promptsFolder configured for the active Space.' `
            -Hint 'Set activeSpace in config.local.json, or pass -OutputFolder.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $OutputFolder = "$pf/current"
}

# Terminal escape sequences for clickable links (OSC 8)
$esc = [char]27
$bel = [char]7

function Show-Help {
    Write-Host @"

New-PromptFromWorkItem - Create a prompt file from an ADO work item

USAGE:
    $(Get-CliPrefix)NewPrompt <WorkItemId> [options]

PARAMETERS:
    -WorkItemId <int>      ADO work item ID (or -Id). Required unless -Title is given
    -Title <text>          OFFLINE: scaffold a card with no ADO call at all
    -Type <name>           With -Title: Task (default), Bug, User Story / UserStory,
                           Feature, or any key in config's workItemTypes
    -AssignTo <email>      Assign to specific user (default: config email, else the az identity)
    -ReadOnly              Skip assignment and state changes
    -Force                 Allow reassigning work items from other users
    -OutputFolder <name>   Target folder (default: <activeOrg>/current)
    -Cover <image>         Attach a cover picture as the card is made (as Cover does)
    -Before <image>        Attach the 'before' picture of a before/after proof
    -Design <name|id>      Bind the card to the design it is worked against: a
                           Design line under its Template line. The hub's
                           designs, and the repo you stand in when it is this
                           Space's; a file name, its stem, or an id prefix
    -Help                  Show this help message

EXAMPLES:
    $(Get-CliPrefix)NewPrompt 123456                                  # Assign to you if unassigned
    $(Get-CliPrefix)NewPrompt 123456 -ReadOnly                        # Don't modify ADO
    $(Get-CliPrefix)NewPrompt 123456 -Force                           # Reassign from someone else
    $(Get-CliPrefix)NewPrompt 123456 -AssignTo "other@contoso.com"    # Assign to specific user
    $(Get-CliPrefix)NewPrompt 123456 -OutputFolder "archive"          # Output to archive folder

  OFFLINE (no az, no ADO -- works at Tier 2):
    $(Get-CliPrefix)NewPrompt -Title "Spike the cache layer"          # Task, next free local id
    $(Get-CliPrefix)NewPrompt -Title "Timeout on large files" -Type Bug
    $(Get-CliPrefix)NewPrompt -Title "Import flow" -Type UserStory -Id 144
    $(Get-CliPrefix)NewPrompt -Title "Lanes, part one" -Design board-ideas   # bound to its design

  An offline card is an ordinary prompt file: {cliPrefix}Status reads it as
  Active, {cliPrefix}ThreadHash and {cliPrefix}Archive work on it unchanged.
  The board fields read "(not linked)" until someone fills them in.

"@ -ForegroundColor Cyan
    exit 0
}

if ($Help) {
    Show-Help
}

$script:LocalMode = -not [string]::IsNullOrWhiteSpace($Title)

# -- The id, if one was given ---------------------------------------------------
# One rule decides what an id is (Scripts/Resolve-CardName.ps1). "0" and "" both
# mean "none given", which is what the old [int] default meant.
$WorkItemId = "$WorkItemId".Trim()
if ($WorkItemId -match '^0+$') { $WorkItemId = '' }
if ($WorkItemId) {
    if (-not (Test-P20IsCardId $WorkItemId)) {
        Write-CliError -Message "'$WorkItemId' is not a card id." `
            -Hint "An id is a work item number (141), or four characters with at least one letter and one digit (K7M2). For a card with no work item, use -Title and let the id be chosen: $(Get-CliPrefix)NewPrompt -Title <words>"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (Test-P20IsWorkItemId $WorkItemId) { $WorkItemId = [string]([long]$WorkItemId) }
    else { $WorkItemId = $WorkItemId.ToUpperInvariant() }
}

if ($Date) {
    $parsedDate = [datetime]::MinValue
    if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
        Write-CliError -Message "'$Date' is not a date." -Hint "-Date takes YYYY-MM-DD: the day the work was."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

# The pictures, checked BEFORE anything is written or fetched: a card whose
# picture is refused is not made at all, rather than made without it.
. (Join-Path $PSScriptRoot 'Add-CardImage.ps1')
$script:BirthPictures = @()
foreach ($pic in @(@{ Kind = 'before'; Path = $Before; Switch = '-Before' }, @{ Kind = 'cover'; Path = $Cover; Switch = '-Cover' })) {
    if (-not $pic.Path) { continue }
    $check = Test-P20CoverSource -Path $pic.Path
    if (-not $check.Ok) {
        Write-CliError -Message "$($pic.Switch): $($check.Message)" -Hint "$($check.Hint) No card was written."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $script:BirthPictures += @{ Kind = $pic.Kind; Path = $check.Path; Switch = $pic.Switch }
}

function Add-BirthPictures {
    # After the card is written: the same attach the Cover verb runs.
    param([string]$CardPath)
    if ($script:BirthPictures.Count -eq 0) { return }
    $cardFile = Get-Item -LiteralPath $CardPath
    $cardDir = Split-Path -Parent $CardPath
    $spaceDir = Split-Path -Parent $cardDir
    $consts = Get-P20Consts
    $roundFolders = @((Join-Path $spaceDir $consts.folders.current), (Join-Path $spaceDir $consts.folders.archive))
    foreach ($pic in $script:BirthPictures) {
        $outcome = Add-P20CardImage -CardFile $cardFile -Source $pic.Path -Kind $pic.Kind -Folders $roundFolders -WorkItemTypes $script:WorkItemTypes
        if ($outcome.Ok) {
            Write-Host "    $($pic.Kind): $($consts.folders.assets)/$($outcome.Key)/$($outcome.File)" -ForegroundColor Gray
        }
        else {
            Write-Host "[!] The card is made, but its $($pic.Kind) was not attached: $($outcome.Message)" -ForegroundColor Yellow
        }
    }
}

# -- The design, resolved BEFORE anything is written or fetched ----------------
# Against the active Space's designs:
# the hub's four folders always, and the repository you stand in when it is
# this Space's own (its origin is one of the Space's GitHub repos) and has
# design/ -- a design that has a product lives in that product's repo (D-S10).
# One id in both is one design, and the repo's copy is the one named. What a
# person typed is read by the lifecycle's one rule (Select-P20Design, which
# MoveDesign asks too). Nothing, or more than one, is a stated refusal and no
# card is written.
$script:DesignBinding = $null
if (-not [string]::IsNullOrWhiteSpace($Design)) {
    . (Join-Path $PSScriptRoot 'Read-DesignTree.ps1')
    . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
    if (-not (Test-P20HubRoot $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $pkgForDesign = Split-Path -Parent $PSScriptRoot
    # One spelling of the hub's path (8.3 short names and relative roots expanded),
    # so a file's path reads as relative to it.
    $hubBase = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $promptsRoot).Path
    $hubDesignDir = Get-P20HubFolder -Name 'design' -PromptsRoot $hubBase -PackageRoot $pkgForDesign
    $hubSpecDir = Get-P20HubFolder -Name 'spec' -PromptsRoot $hubBase -PackageRoot $pkgForDesign
    $candidates = @()
    $repoIds = @{}
    # The repository you stand in -- only when it is this Space's.
    $spaceRepos = @(Get-P20TrackerRepos -OrgUrl $cfg.Org -Projects $cfg.Projects | ForEach-Object { "$_".ToLowerInvariant() })
    if ($spaceRepos.Count -gt 0) {
        $top = ''
        try {
            $probe = Invoke-P20TrackerRead 'git' @('rev-parse', '--show-toplevel')
            if ($probe.Code -eq 0 -and @($probe.Out).Count -gt 0) { $top = "$(@($probe.Out)[0])".Trim() }
        }
        catch { $top = '' }
        if ($top -and (Test-Path -LiteralPath $top -PathType Container)) {
            $top = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $top).Path
        }
        if ($top -and (Test-Path -LiteralPath (Join-Path $top 'design') -PathType Container)) {
            $originName = ''
            try {
                $o = Invoke-P20TrackerRead 'git' @('-C', $top, 'remote', 'get-url', 'origin')
                if ($o.Code -eq 0 -and @($o.Out).Count -gt 0) {
                    $om = [regex]::Match("$(@($o.Out)[0])".Trim(), 'github\.com[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$')
                    if ($om.Success) { $originName = "$($om.Groups[1].Value)/$($om.Groups[2].Value)" }
                }
            }
            catch { $originName = '' }
            if ($originName -and ($spaceRepos -contains $originName.ToLowerInvariant())) {
                $repoTree = Read-P20DesignTree -DesignDir (Join-Path $top 'design') -SpecDir (Join-Path $top 'spec') -Base $top
                foreach ($d in @($repoTree.Designs)) {
                    $repoIds[$d.Id] = $true
                    $candidates += [PSCustomObject]@{ Design = $d; Where = 'repo'; Base = $top; Repo = $originName }
                }
            }
        }
    }
    $hubTree = Read-P20DesignTree -DesignDir $hubDesignDir -SpecDir $hubSpecDir -Base $hubBase
    foreach ($d in @($hubTree.Designs)) {
        if ($repoIds.ContainsKey($d.Id)) { continue }
        $candidates += [PSCustomObject]@{ Design = $d; Where = 'hub'; Base = $hubBase; Repo = '' }
    }
    $picked = @(Select-P20Design -Designs @($candidates | ForEach-Object { $_.Design }) -Name $Design)
    if ($picked.Count -eq 0) {
        $whereSaid = "the hub's design/ and spec/"
        if ($repoIds.Count -gt 0) { $whereSaid = "this repository's design/ and spec/, or the hub's" }
        Write-CliError -Message "No design named '$Design' in $whereSaid. No card was written." `
            -Hint 'Name a design''s file, its stem, or its id (four characters or more); the Studio''s Hub Designs and the Design tab list them.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($picked.Count -gt 1) {
        $list = (@($picked | ForEach-Object { "$($_.Short) $($_.Title)" })) -join '; '
        Write-CliError -Message "'$Design' names $($picked.Count) designs: $list. No card was written." `
            -Hint 'Give more of the id, or the file name.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $chosen = @($candidates | Where-Object { [object]::ReferenceEquals($_.Design, $picked[0]) })[0]
    $doc = $chosen.Design.Spec
    if (-not $doc) { $doc = $chosen.Design.Note }
    $script:DesignBinding = [PSCustomObject]@{
        Id    = $chosen.Design.Id
        Short = $chosen.Design.Short
        Title = $chosen.Design.Title
        State = $chosen.Design.State
        Where = $chosen.Where
        Path  = $doc.Path                                   # relative to its tree, forward slashes
        Full  = (Join-Path $chosen.Base ($doc.Path -replace '/', [IO.Path]::DirectorySeparatorChar))
        Repo  = $chosen.Repo
    }
}

function Get-DesignLine {
    # The `> Design:` line for a card written into $CardDir: a hub design's link
    # is relative to the card's folder; a repo design's is its page on GitHub.
    param([string]$CardDir)
    $b = $script:DesignBinding
    if (-not $b) { return $null }
    if ($b.Where -eq 'repo') {
        $link = "https://github.com/$($b.Repo)/blob/HEAD/$($b.Path)"
    }
    else {
        $link = Resolve-P20PackageLink -TargetPath $b.Full -FromDirectory $CardDir -Fallback $b.Path
    }
    return (New-P20DesignLine -Title $b.Title -Link $link -Id $b.Id)
}

if (-not $WorkItemId -and -not $script:LocalMode) {
    Write-CliError -Message 'WorkItemId is required, or -Title to scaffold a card offline.' `
        -Hint "Run '$(Get-CliPrefix)NewPrompt -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# Resolved AFTER the argument guard, and only for the ADO path:
# Resolve-P20Identity can reach for `az`, and neither a usage error nor a card
# that touches no board needs an identity.
if (-not $script:LocalMode -and [string]::IsNullOrWhiteSpace($AssignTo)) {
    $AssignTo = Resolve-P20Identity
}

if ($script:LocalMode -and ($ReadOnly -or $Force -or $PSBoundParameters.ContainsKey('AssignTo'))) {
    # Not fatal, but not silent either: these three are about the board, and an
    # offline card never touches it.
    Write-Host "[*] -Title is offline: -AssignTo, -ReadOnly and -Force do not apply and are ignored." -ForegroundColor DarkGray
}

function Remove-Html {
    param([string]$html)
    if ([string]::IsNullOrWhiteSpace($html)) { return "" }
    # Convert block/line-break tags to newlines before stripping
    $text = $html -replace '<br\s*/?>', "`n"
    $text = $text -replace '</?(div|p|tr|li|ul|ol|h[1-6])\b[^>]*>', "`n"
    $text = $text -replace '<[^>]+>', ''
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace '(?m)^\s+', '' -replace '(?m)\s+$', '' -replace '(\r?\n){3,}', "`n`n"
    return $text.Trim()
}

function ConvertTo-KebabCase {
    param([string]$text)
    $kebab = $text.ToLower()
    $kebab = $kebab -replace '[^a-z0-9]+', '-'
    $kebab = $kebab -replace '-+', '-'
    $kebab = $kebab.Trim('-')
    if ($kebab.Length -gt 60) {
        $kebab = $kebab.Substring(0, 60).TrimEnd('-')
    }
    return $kebab
}

function Get-BranchName {
    param([string]$workItemType, [string]$id, [string]$title)
    # Branch prefix is config, not the OS account name. Deriving it from the
    # machine means the same card yields a different branch on each laptop --
    # exactly the cross-machine drift this package exists to remove.
    $username = $cfg.BranchUser
    if (-not $username) { $username = [System.Environment]::UserName }
    $slug = ConvertTo-KebabCase $title
    $shape = Get-WorkItemShape $workItemType
    return "$username/$id$($shape.BranchSeparator)$slug"
}

# One table per work-item type. Filename prefix, template and branch shape were
# three separate switches keyed on the same string, in three functions, kept in
# sync by hand -- add a type and you had to remember all three. Adding a row to
# the table is now the whole change, and the table itself moved out to
# Scripts/Resolve-CardName.ps1 when Archive became the second verb that has to
# read an id out of a card's name.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
$script:WorkItemTypes = Get-P20WorkItemTypes -Config $cfg

$script:DefaultWorkItemType = @{ FilePrefix = ''; Template = 'Bug.template.md'; BranchSeparator = '-' }

function Get-WorkItemShape {
    param([string]$workItemType)
    if ($workItemType -and $script:WorkItemTypes.ContainsKey($workItemType)) {
        return $script:WorkItemTypes[$workItemType]
    }
    return $script:DefaultWorkItemType
}

function Get-FileName {
    param([string]$workItemType, [string]$id, [string]$title)
    $kebab = ConvertTo-KebabCase $title
    $shape = Get-WorkItemShape $workItemType
    return "$($shape.FilePrefix)$id-$kebab.prompt.md"
}

# A card that comes back after archive links to its earlier round and says which
# round this is. Archive numbers the rounds (-r1, -r2) at ARCHIVE time, matched by
# the card's id, so there is nothing here to number: this only finds the files
# Archive would count, by the same rule (Get-P20PriorRounds), and writes the link.
# Nothing is quoted from the old card -- the link is the whole feature.
$script:PreviousRound = $null
function Get-PreviousRoundInfo {
    param([string]$CardDir, [string]$Id)
    $archiveDir = Get-P20ArchiveFolderFor -CardDirectory $CardDir
    $prior = @(Get-P20PriorRounds -ArchiveDirectory $archiveDir -CardId ([string]$Id) -WorkItemTypes $script:WorkItemTypes)
    if ($prior.Count -eq 0) { return $null }
    return [pscustomobject]@{ Count = $prior.Count; Latest = $prior[-1]; Round = $prior.Count + 1 }
}

function Write-RoundNotice {
    # The header lines a new card carries beyond its Template line, said once.
    if ($script:DesignBinding) {
        $b = $script:DesignBinding
        $whose = "the hub's $($b.Path)"
        if ($b.Where -eq 'repo') { $whose = "$($b.Repo)'s $($b.Path)" }
        Write-Host "[*] Worked against the design $($b.Short) $($b.Title) ($($b.State), $whose)" -ForegroundColor Cyan
    }
    if (-not $script:PreviousRound) { return }
    $archiveName = (Get-P20Consts).folders.archive
    Write-Host "[*] Round $($script:PreviousRound.Round) of this card; previous round: $archiveName/$($script:PreviousRound.Latest.Name)" -ForegroundColor Cyan
}

function Build-PromptContent {
    param([hashtable]$workItem, [string]$cardDir)

    $type = $workItem.Type
    $id = $workItem.Id
    $title = $workItem.Title
    $description = $workItem.Description
    $reproSteps = $workItem.ReproSteps
    $acceptanceCriteria = $workItem.AcceptanceCriteria
    $sprint = $workItem.Sprint
    $storyPoints = $workItem.StoryPoints
    $adoUrl = $workItem.AdoUrl
    $branchName = $workItem.BranchName
    $priority = $workItem.Priority
    $severity = $workItem.Severity
    $tags = $workItem.Tags
    $triage = $workItem.Triage
    $adoComments = $workItem.AdoComments

    $isLargeStory = ($type -eq "User Story" -and $storyPoints -ge 5)
    if ($isLargeStory) { $pfx = [char]::ConvertFromUtf32(0x1F966) + " " } else { $pfx = "" }

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("# $pfx$type ${id}: $title")
    [void]$sb.AppendLine("")
    # Templates ship with the package, the card lives in the hub. The hop is
    # built by the one thing that knows these lines, and refreshed by the same
    # file whenever the card or the package moves -- a depth frozen at write
    # time was wrong on the next machine and stayed wrong.
    $tpl = (Get-WorkItemShape $type).Template
    [void]$sb.AppendLine((New-P20TemplateLine -TemplateName $tpl -CardDirectory $cardDir))
    $script:PreviousRound = Get-PreviousRoundInfo -CardDir $cardDir -Id $id
    if ($script:PreviousRound) {
        [void]$sb.AppendLine((New-P20PreviousRoundLine -PreviousPath $script:PreviousRound.Latest.FullName -CardDirectory $cardDir))
    }
    # The design it is worked against (-Design): in the header,
    # beside the Template line -- after the Previous round line, which sits
    # directly under Template.
    $designLine = Get-DesignLine -CardDir $cardDir
    if ($designLine) { [void]$sb.AppendLine($designLine) }
    [void]$sb.AppendLine("")
    # No hardcoded module path here. An absolute path baked into every card is
    # wrong on the next machine, points at whichever package generated the
    # file, and is unnecessary now that the commands autoload.
    #
    # {cliPrefix}, not the prefix this machine happens to have registered: the
    # prefix is config, and a card that names `jw*` because that was the setting
    # the morning it was written tells the next reader to run commands that do
    # not exist. It is the same token templates and -Help use (docs/CONTRIBUTING.md, "Never hardcode a prefix").
    [void]$sb.AppendLine("<!-- {cliPrefix}* commands autoload in any shell -- no Import-Module needed. If one is not recognized, run {cliPrefix}InstallAutoload -Force. -->")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Branch")
    [void]$sb.AppendLine("$branchName")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Git")
    [void]$sb.AppendLine("<!-- One commit PER LINE as a bullet: ""- {short-hash} {message}"". {cliPrefix}Status marks the card ""In Progress"" only on a ""- {7+ hex hash}"" bullet line; an inline/comma list is NOT detected. -->")
    [void]$sb.AppendLine("Commits:")
    [void]$sb.AppendLine("- (pending)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Work Item Info")
    [void]$sb.AppendLine("Priority: $priority | Severity: $severity | Triage: $triage")
    [void]$sb.AppendLine("Tags: $tags")
    [void]$sb.AppendLine("")
    if ($type -eq "Bug" -and $reproSteps) {
        [void]$sb.AppendLine("## Repro")
        [void]$sb.AppendLine("$reproSteps")
        [void]$sb.AppendLine("")
    }
    elseif ($type -eq "Task") {
        if ($workItem.ParentId) {
            [void]$sb.AppendLine("> Parent: [#$($workItem.ParentId)]($($workItem.ParentUrl))")
            [void]$sb.AppendLine("")
        }
        [void]$sb.AppendLine("## Context")
        [void]$sb.AppendLine("$description")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Summary")
        [void]$sb.AppendLine("<!-- Your plain-English explanation of what was done and why. -->")
        [void]$sb.AppendLine("")
    }

    if ($type -ne "Task" -and $type -ne "Meeting") {
        [void]$sb.AppendLine("## Summary")
        [void]$sb.AppendLine("$description")
        [void]$sb.AppendLine("")
    }

    # A Meeting is one you ATTENDED, written after the fact: when, where, who, why,
    # what was said, what was decided, what you now owe. No Described Changes and
    # no Implementation Details -- a meeting writes no code. (A meeting you RUN
    # is the Meeting Agenda Planner's, under manager/.)
    if ($type -eq "Meeting") {
        [void]$sb.AppendLine("## When")
        [void]$sb.AppendLine("<!-- Date, time and duration. The date is the card's Created: -- pass -Date when the card is written after the day. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Where")
        [void]$sb.AppendLine("<!-- A room, a call, a link. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Who")
        [void]$sb.AppendLine("<!-- Who was there, and who ran it. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Purpose")
        if ($description) { [void]$sb.AppendLine("$description") } else { [void]$sb.AppendLine("<!-- Why it was held, in a sentence. -->") }
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Notes")
        [void]$sb.AppendLine("<!-- What was said that matters. Written during or straight after, not from memory a week on. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Outcomes")
        [void]$sb.AppendLine("<!-- What was decided. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("- (TBD)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Follow-ups")
        [void]$sb.AppendLine("<!-- What you now owe, and what you are owed. Each one that is real work becomes a card. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("- [ ] (TBD)")
        [void]$sb.AppendLine("")
    }

    # A Spike ends in a FINDING, not in code: a question, what was found, what to do
    # about it. No Described Changes and no Implementation Details -- there may be
    # no pull request at all -- and "done" is that the question has an answer.
    if ($type -eq "Spike") {
        [void]$sb.AppendLine("## Question")
        [void]$sb.AppendLine("<!-- The one thing this spike exists to find out. If it cannot be said in a sentence, it is two spikes. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Findings")
        [void]$sb.AppendLine("<!-- What was tried, what happened, what was learned -- written as it is learned, not at the end. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("- (TBD)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Recommendation")
        [void]$sb.AppendLine("<!-- What to do now that this is known, and the cards it turns into. -->")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Done when")
        [void]$sb.AppendLine("- [ ] The question has an answer, written above")
        [void]$sb.AppendLine("- [ ] The recommendation names what happens next")
        [void]$sb.AppendLine("")
    }

    if ($type -eq "User Story") {
        [void]$sb.AppendLine("## Scope")
        [void]$sb.AppendLine("**In scope:** (TBD)")
        [void]$sb.AppendLine("**Out of scope:** (TBD)")
        [void]$sb.AppendLine("")
    }

    if ($type -ne "Spike" -and $type -ne "Meeting") {
    [void]$sb.AppendLine("## Described Changes")
    [void]$sb.AppendLine("<!-- Up to 5 high-level bullets summarizing the PR. Used directly in PR description. -->")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- (TBD)")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## Implementation Details")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| File | Change |")
    [void]$sb.AppendLine("|------|--------|")
    [void]$sb.AppendLine("| (TBD) | (TBD) |")
    [void]$sb.AppendLine("")
    }

    if ($acceptanceCriteria -and $type -ne "Spike" -and $type -ne "Meeting") {
        [void]$sb.AppendLine("## Acceptance Criteria")
        [void]$sb.AppendLine("$acceptanceCriteria")
        [void]$sb.AppendLine("")
    }

    if ($type -eq "User Story") {
        [void]$sb.AppendLine("## Verification")
        [void]$sb.AppendLine("- [ ] Build passes")
        [void]$sb.AppendLine("- [ ] Tests pass")
        [void]$sb.AppendLine("- [ ] Manual verification complete")
        [void]$sb.AppendLine("- [ ] Peer review complete")
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("## Questions / Blockers")
    [void]$sb.AppendLine("(Add any open questions or blockers here)")
    [void]$sb.AppendLine("")
    if ($adoComments -and $adoComments.Count -gt 0) {
        [void]$sb.AppendLine("## ADO Discussion")
        foreach ($comment in $adoComments) {
            [void]$sb.AppendLine("**$($comment.Author)** ($($comment.Date)):")
            [void]$sb.AppendLine("$($comment.Text)")
            [void]$sb.AppendLine("")
        }
    }
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Sprint:** $sprint")
    [void]$sb.AppendLine("**Story Points:** $storyPoints")
    [void]$sb.AppendLine("**ADO Link:** $adoUrl")
    # When this card was opened. Move-PromptToArchive adds a matching
    # **Closed:** line, and the pair is what lets an archived corpus be reported
    # over -- billing included -- without reading git. See docs/hub/cards.md, "3. The footer -- one fact per line".
    $createdDate = Get-Date -Format 'yyyy-MM-dd'
    if ($Date) { $createdDate = $Date }
    [void]$sb.AppendLine("$((Get-P20Consts).stamps.created) $createdDate")

    # LF, on every host. StringBuilder.AppendLine follows Environment.NewLine,
    # so the same card came out CRLF on Windows and LF on macOS -- and then
    # the "**Closed:**" stamp appended a bare LF to the CRLF one. A card the
    # tool CREATES is LF; a card it EDITS keeps what it finds. See
    # Scripts/Add-ClosedStamp.ps1's Write-CardText for the other half.
    return ($sb.ToString() -replace "`r`n", "`n")
}

# -- Offline: a card from nothing ----------------------------------------------
# docs/CLI.md's Tiers section says in bold that a Tier-2 machine still produces
# and maintains prompt files, and every documented way to
# produce one once went through ADO. This is the other half of that sentence.
#
# It deliberately shares Build-PromptContent with the ADO path rather than
# rendering templates/*.template.md. Those files are REFERENCE documents that a
# generated card LINKS to; the body has always been built here, and forking it
# would give the two paths two shapes within a release.

function Resolve-LocalType {
    param([string]$Requested)
    if ([string]::IsNullOrWhiteSpace($Requested)) { return 'Task' }
    # Exact key first, so a team's own workItemTypes entry always wins.
    foreach ($key in $script:WorkItemTypes.Keys) {
        if ($key -eq $Requested) { return $key }
    }
    # Then case- and space-insensitively, so "userstory" finds "User Story".
    $squashed = ($Requested -replace '[\s_-]', '').ToLower()
    foreach ($key in $script:WorkItemTypes.Keys) {
        if (($key -replace '[\s_-]', '').ToLower() -eq $squashed) { return $key }
    }
    return $null
}

function Get-NextLocalId {
    # The next number above every id already filed for this org, current/ and
    # archive/ together, so an offline card sorts with the rest and cannot
    # collide with one that is already there. It is a LOCAL number: it means
    # nothing on a board.
    #
    # It counts CARDS and nothing else. The first run of digits in any
    # *.prompt.md name used to do, and both folders hold digit-bearing files
    # that are not cards: the PR-comment and review flows write dated
    # "<date>-PR141415.prompt.md" into archive/, and a slug can carry a year
    # of its own. On the real hub that read 2026 as the highest id and numbered
    # the next offline card Task2027 -- the opposite of "sorts with the rest".
    #
    param([string]$Folder)
    $max = 0
    $pattern = Get-P20CardIdPattern -WorkItemTypes $script:WorkItemTypes
    $roots = @($Folder)
    $parent = Split-Path $Folder -Parent
    if ($parent) { $roots += (Join-Path $parent 'archive'), (Join-Path $parent 'current') }
    foreach ($r in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path $r)) { continue }
        foreach ($f in (Get-ChildItem -Path $r -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue)) {
            # Get-P20CardId returns a STRING. Only a number takes
            # part in highest-plus-one: "99" -gt "100" is true for strings.
            $n = Get-P20CardId -Name $f.Name -Pattern $pattern
            if (-not (Test-P20IsWorkItemId $n)) { continue }
            $n = [long]$n
            if ($null -ne $n -and $n -gt $max) { $max = $n }
        }
    }
    return $max + 1
}

# -- The card is already here ---------------------------------------------------
# Asked BEFORE anything else happens -- ADO included, and the OFFLINE path included.
# It used to sit after the -Title branch, so `-Title x -Id K7M2` run twice wrote a
# second card carrying the same id; current/ was protected from the board and not
# from the keyboard (found the first time an offline id was typed twice). Re-running NewPrompt <id> for
# a card that was already in current/ used to write a fresh scaffold over it --
# the notes, the threaded commits, the PR URL and every review round gone, exit
# 0, no warning -- and on the way it could reassign the board card and move it
# back to Active.
#
# The owner's rule: it "should return the user card that already exists
# in current and not overwrite". So this is not a refusal. The verb was asked for
# card <id> and here it is: print it, exit 0, write nothing, call nothing. There
# is deliberately NO switch that overwrites -- -Force on this path already means
# "reassign from another user" and cannot carry a second meaning. To start a card
# over, move or delete the file, which is a thing a person does on purpose.
#
# By ID, through the one card-name rule (Resolve-CardName.ps1), not by the name
# this run would have generated: the title on the board may have changed since,
# and "Task140-old-title" is still card 140. Only the TARGET folder is searched.
# A card with this id in archive/ is one that came back, and scaffolding it into
# current/ again is the reopen flow, not an overwrite.
$existingFolder = Resolve-TargetFolder $OutputFolder
if ($WorkItemId -and (Test-Path $existingFolder)) {
    $idPattern = Get-P20CardIdPattern -WorkItemTypes $script:WorkItemTypes
    $existingCards = @(Get-ChildItem -Path $existingFolder -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue |
        Where-Object { (Get-P20CardId -Name $_.Name -Pattern $idPattern) -eq [string]$WorkItemId } |
        Sort-Object Name)
    if ($existingCards.Count -gt 0) {
        Write-Host ""
        Write-Host "[=] Card $WorkItemId is already in $OutputFolder/ -- nothing was written, and ADO was not contacted." -ForegroundColor Green
        foreach ($card in $existingCards) {
            # "file://" + an absolute POSIX path already gives three slashes;
            # a drive-letter path needs the third added.
            $existingPath = $card.FullName -replace '\\', '/'
            $existingUrl = if ($existingPath.StartsWith('/')) { "file://$existingPath" } else { "file:///$existingPath" }
            Write-Host "    Prompt: $existingUrl" -ForegroundColor Blue
        }
        Write-Host "    To start it over, move or delete that file first." -ForegroundColor DarkGray
        if ($script:BirthPictures.Count -gt 0) {
            Write-Host "    No picture was attached either: '$(Get-CliPrefix)Cover $WorkItemId <image>' gives an existing card one." -ForegroundColor DarkGray
        }
        if ($script:DesignBinding) {
            Write-Host "    No design line was written either: an existing card names its design by hand, under its Template line." -ForegroundColor DarkGray
        }
        Write-Host ""
        exit 0
    }
}

# Main execution
Write-Host ""
if ($script:LocalMode) {
    $resolvedType = Resolve-LocalType $Type
    if (-not $resolvedType) {
        Write-CliError -Message "unknown work item type '$Type'." `
            -Hint "Known types: $(($script:WorkItemTypes.Keys | Sort-Object) -join ', ')"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    $targetFolder = Resolve-TargetFolder $OutputFolder
    if (-not (Test-Path $targetFolder)) {
        New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }

    # A card with no work item gets a short RANDOM id, not "highest plus one":
    # an integer collides with a real work item number sooner or later, and two
    # machines that each make a card before a sync make the same one.
    $localId = $WorkItemId
    if (-not $localId) {
        $idFolders = @($targetFolder)
        $idParent = Split-Path $targetFolder -Parent
        if ($idParent) { $idFolders += (Join-Path $idParent 'archive'), (Join-Path $idParent 'current') }
        $localId = New-P20CardId -Folders $idFolders -WorkItemTypes $script:WorkItemTypes
        if (-not $localId) {
            Write-CliError -Message 'Could not find a free card id after 50 tries.' `
                -Hint "Give one yourself with -Id: four characters, at least one letter and one digit."
            exit 2  # stated refusal
        }
    }

    $fileName = Get-FileName -workItemType $resolvedType -id $localId -title $Title
    $branchName = Get-BranchName -workItemType $resolvedType -id $localId -title $Title

    # "(not linked)", not "" and not a fake URL: the card says which fields a
    # board would have filled, so whoever links it later knows what to replace.
    $notLinked = '(not linked)'
    $workItemData = @{
        Type               = $resolvedType
        Id                 = $localId
        Title              = $Title
        Description        = '(TBD)'
        ReproSteps         = if ($resolvedType -eq 'Bug') { '(TBD)' } else { '' }
        AcceptanceCriteria = '- [ ] (TBD)'
        Sprint             = $notLinked
        StoryPoints        = '(Not estimated)'
        Project            = ''
        AdoUrl             = '(not linked -- created offline with -Title)'
        BranchName         = $branchName
        Priority           = '(Not set)'
        Severity           = '(Not set)'
        Tags               = '(None)'
        Triage             = '(Not triaged)'
        AdoComments        = @()
        ParentId           = $null
        ParentUrl          = $null
    }

    $content = Build-PromptContent -workItem $workItemData -cardDir $targetFolder
    $filePath = Join-Path $targetFolder $fileName
    if ((Test-Path $filePath) -and -not $Force) {
        Write-CliError -Message "$fileName already exists in $OutputFolder/." `
            -Hint 'Pick another title, pass -Id, or delete the file.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    # The one writer, and -New because this CREATES: UTF-8 with no BOM (5.1's
    # Set-Content -Encoding UTF8 writes one and 7's does not, so the stamp
    # Archive adds later used to rewrite the whole file on one host only) and
    # LF, whatever the line endings of the here-strings that built the body.
    Write-CardText -Path $filePath -Content $content -New
    Add-BirthPictures -CardPath $filePath

    $fileUrl = "file:///" + ($filePath -replace '\\', '/')
    Write-Host ""
    Write-Host "[+] Created $fileName in $OutputFolder/ -- $resolvedType $localId, offline." -ForegroundColor Green
    Write-Host "    Prompt: $fileUrl" -ForegroundColor Blue
    Write-Host "    Branch: $branchName" -ForegroundColor Gray
    Write-Host "    No ADO call was made; Sprint and ADO Link read '(not linked)'." -ForegroundColor DarkGray
    Write-RoundNotice
    Write-Host ""
    exit 0
}

# Only a NUMBER is a work item. A lettered id names a card that was made here,
# with no board behind it: if it is not in current/ (checked above) there is
# nothing to fetch, and asking ADO for "K7M2" would only produce its error.
if (-not (Test-P20IsWorkItemId $WorkItemId)) {
    Write-CliError -Message "No card with id '$WorkItemId' in $OutputFolder/, and '$WorkItemId' is not a work item number." `
        -Hint "For a card with no work item: $(Get-CliPrefix)NewPrompt -Title <words> [-Type Spike|Task|Bug|UserStory|Feature]"
    exit 2  # stated refusal
}

# -- A GitHub board: the same verb, an issue as the source -------------------
# (D-G4.) The card that comes out is the
# SAME card -- Build-PromptContent, Get-FileName, Get-BranchName and
# Write-CardText are all shared -- and `**ADO Link:**` stays the card's
# tracker-link TOKEN, because both halves parse that line (D-G5: a tracker
# writes the contract's tokens, never redefines them). Here it carries the
# issue's URL.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
# Which space, which tracker -- said before the id is even sent, so a number
# meant for one tracker cannot fetch the other tracker's card of the same
# number without a person seeing where it stood.
#
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    # WHICH repo holds issue <n>? One rule for every GitHub verb --
    # Resolve-P20TrackerRepo: the repo-grained address, else the board's ONE
    # projects[] entry, else a stated refusal (issue numbers are per-repo, and
    # a guess that fetched the wrong repo's issue of that number would write a WRONG CARD).
    $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $org -Projects $cfg.Projects -CliPrefix (Get-CliPrefix)
    if (-not $repoAnswer.Repo) {
        Write-CliError -Message "$($repoAnswer.Reason) Issue $WorkItemId cannot be found." -Hint $repoAnswer.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $repoFull = $repoAnswer.Repo
    $repoName = $repoFull.Split('/')[1]

    Write-Host "[*] Fetching issue #$WorkItemId from $repoFull..." -ForegroundColor Cyan
    $raw = gh issue view $WorkItemId --repo $repoFull --json 'number,title,body,state,labels,assignees,milestone,url,comments' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        Write-CliError -Message "Could not fetch issue $WorkItemId from $repoFull." `
            -Hint 'Check the number and that gh is signed in (gh auth status).'
        exit 2  # stated refusal
    }
    $issue = ($raw -join "`n") | ConvertFrom-Json

    $title = $issue.title
    $issueState = "$($issue.state)".ToUpperInvariant()
    $assigneeLogins = @($issue.assignees | ForEach-Object { $_.login })
    $myLogin = [string](gh api user -q .login 2>$null)
    if ($LASTEXITCODE -ne 0) { $myLogin = '' }

    # The card's TYPE is the card's own (cards spec, phase 1): a label that
    # names one of workItemTypes' keys wins ("bug" -> Bug), else Task. GitHub
    # has no native type, and the corpus's filename conventions hold either way.
    $resolvedType = 'Task'
    foreach ($labelName in @($issue.labels | ForEach-Object { $_.name })) {
        $t = Resolve-LocalType $labelName
        if ($t -and $t -ne 'Task') { $resolvedType = $t; break }
    }

    Write-Host "[+] Found: issue #$WorkItemId - $title" -ForegroundColor Green
    $assignedWord = if ($assigneeLogins.Count -gt 0) { $assigneeLogins -join ', ' } else { 'Unassigned' }
    Write-Host "    State: $($issueState.ToLowerInvariant()) | Assigned: $assignedWord | Card type: $resolvedType" -ForegroundColor Gray

    if (-not $ReadOnly) {
        if ($assigneeLogins.Count -eq 0) {
            Write-Host ""
            Write-Host "[>] Assigning unassigned issue to you..." -ForegroundColor Yellow
            gh issue edit $WorkItemId --repo $repoFull --add-assignee '@me' *> $null
            if ($LASTEXITCODE -eq 0) { Write-Host "[+] Assigned issue #$WorkItemId to you" -ForegroundColor Green }
            else { Write-Host "[!] Warning: Could not assign the issue" -ForegroundColor Yellow }
        }
        elseif ($myLogin -and ($assigneeLogins -contains $myLogin)) {
            # Already yours -- nothing to do.
        }
        elseif (-not $Force) {
            Write-Host ""
            Write-CliError -Message "Issue $WorkItemId is already assigned to $($assigneeLogins -join ', ')." `
                -Hint 'Use -Force to be added beside them (GitHub allows several assignees), or -ReadOnly to skip assignment.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        else {
            Write-Host ""
            Write-Host "[>] Adding you beside $($assigneeLogins -join ', ')..." -ForegroundColor Yellow
            gh issue edit $WorkItemId --repo $repoFull --add-assignee '@me' *> $null
            if ($LASTEXITCODE -eq 0) { Write-Host "[+] Added you as an assignee of issue #$WorkItemId" -ForegroundColor Green }
            else { Write-Host "[!] Warning: Could not add you as an assignee" -ForegroundColor Yellow }
        }

        if ($issueState -eq 'CLOSED') {
            # The New -> Active dance has no GitHub shape; open or closed is
            # the whole state model, so a closed issue is the one to ask about.
            Write-Host ""
            Write-Host "[!] Issue $WorkItemId is closed." -ForegroundColor Yellow
            $answer = Read-Host "    Reopen it? [Y/N]"
            if ($answer -match '^[Yy]') {
                gh issue reopen $WorkItemId --repo $repoFull *> $null
                if ($LASTEXITCODE -eq 0) { Write-Host "[+] Reopened issue #$WorkItemId" -ForegroundColor Green }
                else { Write-Host "[!] Warning: Could not reopen the issue" -ForegroundColor Yellow }
            }
            else { Write-Host "[*] Skipped -- the issue stays closed" -ForegroundColor DarkGray }
        }
    }

    $description = "$($issue.body)"
    if ([string]::IsNullOrWhiteSpace($description)) { $description = "(No description provided)" }
    $sprint = if ($issue.milestone -and $issue.milestone.title) { $issue.milestone.title } else { "(Not assigned to sprint)" }
    $labelWords = @($issue.labels | ForEach-Object { $_.name })
    $tags = if ($labelWords.Count -gt 0) { $labelWords -join '; ' } else { "(None)" }
    $ghComments = @($issue.comments | ForEach-Object {
            @{
                Author = $_.author.login
                Date   = ([datetime]$_.createdAt).ToString('yyyy-MM-dd')
                Text   = "$($_.body)"
            }
        })

    $fileName = Get-FileName -workItemType $resolvedType -id $WorkItemId -title $title
    $branchName = Get-BranchName -workItemType $resolvedType -id $WorkItemId -title $title

    $workItemData = @{
        Type               = $resolvedType
        Id                 = $WorkItemId
        Title              = $title
        Description        = $description
        ReproSteps         = ''
        AcceptanceCriteria = "- [ ] (No acceptance criteria provided)"
        Sprint             = $sprint
        StoryPoints        = "(Not estimated)"
        Project            = $repoName
        AdoUrl             = $issue.url
        BranchName         = $branchName
        Priority           = "(Not set)"
        Severity           = "(Not set)"
        Tags               = $tags
        Triage             = "(Not triaged)"
        AdoComments        = $ghComments
        ParentId           = $null
        ParentUrl          = $null
    }

    $targetFolder = Resolve-TargetFolder $OutputFolder
    if (-not (Test-Path $targetFolder)) {
        New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }

    $content = Build-PromptContent -workItem $workItemData -cardDir $targetFolder
    $filePath = Join-Path $targetFolder $fileName
    # Created, so no BOM and LF -- the one byte contract for a card.
    Write-CardText -Path $filePath -Content $content -New
    Add-BirthPictures -CardPath $filePath

    $fileUrl = "file:///" + ($filePath -replace '\\', '/')
    $fileLink = $esc + ']8;;' + $fileUrl + $bel + $fileName + $esc + ']8;;' + $bel
    $issueLink = $esc + ']8;;' + $issue.url + $bel + "issue #${WorkItemId}: $title" + $esc + ']8;;' + $bel

    Write-Host ""
    Write-Host "[+] Created prompt file $fileLink in $OutputFolder/ for $issueLink" -ForegroundColor Green
    Write-Host "    Prompt: $fileUrl" -ForegroundColor Blue
    Write-Host "    Issue:  $($issue.url)" -ForegroundColor Blue
    Write-RoundNotice
    Write-Host ""
    exit 0
}

Write-Host "[*] Fetching work item $WorkItemId from ADO..." -ForegroundColor Cyan

try {
    # The one reader of a work item (Scripts/Get-WorkItemRecord.ps1), shared with
    # EditItem and Status -Board; it drops az's WARNING lines itself.
    . (Join-Path $PSScriptRoot 'Get-WorkItemRecord.ps1')
    $record = Get-P20WorkItemRecord -Id $WorkItemId -Org $org

    if (-not $record.Ok) {
        Write-CliError -Message "Could not fetch work item $WorkItemId." `
            -Hint 'Check the id and that az is signed in to this org.'
        if ($record.Raw) { Write-Host $record.Raw -ForegroundColor DarkGray }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $wi = $record.Item

    $workItemType = $wi.fields.'System.WorkItemType'
    $title = $wi.fields.'System.Title'
    $state = $wi.fields.'System.State'
    $assignedTo = $wi.fields.'System.AssignedTo'.uniqueName
    $description = Remove-Html $wi.fields.'System.Description'
    $reproSteps = Remove-Html $wi.fields.'Microsoft.VSTS.TCM.ReproSteps'
    $acceptanceCriteria = Remove-Html $wi.fields.'Microsoft.VSTS.Common.AcceptanceCriteria'
    $sprint = $wi.fields.'System.IterationPath'
    $storyPoints = $wi.fields.'Microsoft.VSTS.Scheduling.StoryPoints'
    $project = $wi.fields.'System.TeamProject'
    $priority = $wi.fields.'Microsoft.VSTS.Common.Priority'
    $severity = $wi.fields.'Microsoft.VSTS.Common.Severity'
    $tags = $wi.fields.'System.Tags'
    $triage = $wi.fields.'Microsoft.VSTS.Common.Triage'

    # Extract parent work item ID from relations
    $parentId = $null
    $parentUrl = $null
    if ($wi.relations) {
        $parentRel = $wi.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Reverse' } | Select-Object -First 1
        if ($parentRel) {
            $parentId = [int]($parentRel.url -split '/' | Select-Object -Last 1)
            $parentUrl = "$org/$([Uri]::EscapeDataString($project))/_workitems/edit/$parentId"
        }
    }

    # Fetch work item comments (discussion) via REST API. The token is asked for
    # BEFORE anything is written or changed: no token is a stated refusal, so no
    # card is left without the discussion it was meant to carry and the work
    # item is not assigned or moved for a card that was never made.
    $adoComments = @()
    . (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
    $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
    if (-not $tokenRead.Ok) {
        Write-CliError -Message "Could not read work item $WorkItemId's comments: no ADO token was available, and the card is not made without them." `
            -Hint $tokenRead.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    try {
        $commentsUri = "$org/$([Uri]::EscapeDataString($project))/_apis/wit/workItems/$WorkItemId/comments?api-version=7.1-preview"
        $commentsHeaders = Get-P20AdoHeaders -Token $tokenRead.Token
        $commentsResponse = Invoke-RestMethod -Uri $commentsUri -Headers $commentsHeaders -Method Get
        if ($commentsResponse.comments) {
            $adoComments = $commentsResponse.comments | ForEach-Object {
                $author = $_.createdBy.displayName
                $date = ([datetime]$_.createdDate).ToString('yyyy-MM-dd')
                $text = Remove-Html $_.text
                @{ Author = $author; Date = $date; Text = $text }
            }
        }
    }
    catch {
        Write-Host "[!] Warning: Could not fetch work item comments" -ForegroundColor Yellow
        Write-Host "    URI: $commentsUri" -ForegroundColor DarkGray
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }

    if ([string]::IsNullOrWhiteSpace($description)) { $description = "(No description provided)" }
    if ([string]::IsNullOrWhiteSpace($acceptanceCriteria)) { $acceptanceCriteria = "- [ ] (No acceptance criteria provided)" }
    if ([string]::IsNullOrWhiteSpace($sprint)) { $sprint = "(Not assigned to sprint)" }
    if ([string]::IsNullOrWhiteSpace($storyPoints)) { $storyPoints = "(Not estimated)" }
    if ([string]::IsNullOrWhiteSpace($priority)) { $priority = "(Not set)" }
    if ([string]::IsNullOrWhiteSpace($severity)) { $severity = "(Not set)" }
    if ([string]::IsNullOrWhiteSpace($tags)) { $tags = "(None)" }
    if ([string]::IsNullOrWhiteSpace($triage)) { $triage = "(Not triaged)" }

    $assignedLabel = if ($assignedTo) { $assignedTo } else { "Unassigned" }
    Write-Host "[+] Found: $workItemType $WorkItemId - $title" -ForegroundColor Green
    Write-Host "    State: $state | Assigned: $assignedLabel" -ForegroundColor Gray

    # Handle assignment and state changes unless ReadOnly
    if (-not $ReadOnly) {
        if ([string]::IsNullOrWhiteSpace($assignedTo)) {
            Write-Host ""
            Write-Host "[>] Assigning unassigned work item to $AssignTo..." -ForegroundColor Yellow
            az boards work-item update --id $WorkItemId --assigned-to $AssignTo --org $org --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Assigned work item $WorkItemId to $AssignTo" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Warning: Could not assign work item" -ForegroundColor Yellow
            }
        }
        elseif ($assignedTo -ne $AssignTo) {
            if (-not $Force) {
                Write-Host ""
                Write-CliError -Message "Work item $WorkItemId is already assigned to $assignedTo." `
                    -Hint 'Use -Force to reassign from another user, or -ReadOnly to skip assignment.'
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
            Write-Host ""
            Write-Host "[>] Reassigning work item from $assignedTo to $AssignTo..." -ForegroundColor Yellow
            az boards work-item update --id $WorkItemId --assigned-to $AssignTo --org $org --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Reassigned work item $WorkItemId to $AssignTo" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Warning: Could not reassign work item" -ForegroundColor Yellow
            }
        }

        if ($state -eq "Active") {
            # Already active -- nothing to do
        }
        elseif ($state -eq "New") {
            Write-Host ""
            Write-Host "[>] Setting work item state to Active..." -ForegroundColor Yellow
            az boards work-item update --id $WorkItemId --state "Active" --org $org --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Set work item $WorkItemId state to Active" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Warning: Could not update work item state" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host ""
            Write-Host "[!] Work item $WorkItemId is currently '$state'." -ForegroundColor Yellow
            $answer = Read-Host "    Set to Active? [Y/N]"
            if ($answer -match '^[Yy]') {
                az boards work-item update --id $WorkItemId --state "Active" --org $org --output none
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[+] Set work item $WorkItemId state to Active" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] Warning: Could not update work item state" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[*] Skipped state change -- work item remains '$state'" -ForegroundColor DarkGray
            }
        }
    }

    $fileName = Get-FileName -workItemType $workItemType -id $WorkItemId -title $title
    $branchName = Get-BranchName -workItemType $workItemType -id $WorkItemId -title $title
    $adoUrl = "$org/$([Uri]::EscapeDataString($project))/_workitems/edit/$WorkItemId"

    $workItemData = @{
        Type               = $workItemType
        Id                 = $WorkItemId
        Title              = $title
        Description        = $description
        ReproSteps         = $reproSteps
        AcceptanceCriteria = $acceptanceCriteria
        Sprint             = $sprint
        StoryPoints        = $storyPoints
        Project            = $project
        AdoUrl             = $adoUrl
        BranchName         = $branchName
        Priority           = $priority
        Severity           = $severity
        Tags               = $tags
        Triage             = $triage
        AdoComments        = $adoComments
        ParentId           = $parentId
        ParentUrl          = $parentUrl
    }

    # Resolve (and create) the target folder before building content: the
    # template link is computed relative to where the card will actually sit,
    # so the directory has to exist first.
    $targetFolder = Resolve-TargetFolder $OutputFolder
    if (-not (Test-Path $targetFolder)) {
        New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }

    $content = Build-PromptContent -workItem $workItemData -cardDir $targetFolder

    $filePath = Join-Path $targetFolder $fileName
    # Same contract as the offline path above: created, so no BOM and LF.
    Write-CardText -Path $filePath -Content $content -New
    Add-BirthPictures -CardPath $filePath

    $fileUrl = "file:///" + ($filePath -replace '\\', '/')
    $fileLink = $esc + ']8;;' + $fileUrl + $bel + $fileName + $esc + ']8;;' + $bel
    $adoLink = $esc + ']8;;' + $adoUrl + $bel + $workItemType + ' ' + $WorkItemId + ': ' + $title + $esc + ']8;;' + $bel

    Write-Host ""
    Write-Host "[+] Created prompt file $fileLink in $OutputFolder/ for $adoLink" -ForegroundColor Green
    Write-Host "    Prompt: $fileUrl" -ForegroundColor Blue
    Write-Host "    ADO: $adoUrl" -ForegroundColor Blue
    Write-RoundNotice
    Write-Host ""

}
catch {
    Write-CliError -Message "$_" -Hint "Run '$(Get-CliPrefix)Log -Errors' for details."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}