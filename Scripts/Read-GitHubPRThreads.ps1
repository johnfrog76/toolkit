#
# A GitHub pull request's review conversation, in the thread shape
# Get-PRComments.ps1 already writes into a card.
#
# NOT a runnable verb: this file is DOT-SOURCED by Get-PRComments.ps1, and by
# Tests/Test-PRComments.ps1, which runs the pure functions below against
# fixture payloads. Nothing here calls gh -- the script does that, through
# Invoke-P20TrackerRead -- so every rule in this file can be held by a table.
#
# GitHub keeps a pull request's conversation in THREE places, and the card is
# meant to be the whole review, so all three are read:
#
#   pulls/<n>/comments   inline review comments. A reply carries in_reply_to_id,
#                        which GitHub always points at the thread's FIRST
#                        comment, so a thread is "the root and every comment
#                        that names it".
#   issues/<n>/comments  the conversation tab. A pull request is also an issue;
#                        these comments have no threads, so each is its own.
#   pulls/<n>/reviews    a review's own summary text ("Request changes: ...").
#                        Each submitted review with text is its own thread.
#
# Thread ids are GitHub's own ids -- the root comment's, the comment's, the
# review's -- because those are what a later reply is posted against. They
# are past the 32-bit range, so every id here is a [long].
#
# What is NOT actionable, and why (Get-PRComments.ps1's ADO filter, read for
# its spirit: keep anything anchored to code and anything a person wrote; drop
# automation that reports on the build):
#
#   - a comment with no text (a review that only approves, or only carries
#     inline comments, is a vote, not a remark);
#   - a conversation-tab comment whose author is a Bot account (CI status,
#     coverage, deploy previews -- the build-service noise of GitHub).
#     These are NOT dropped silently: their ids come back in NonActionable,
#     and the card names them on its "Non-actionable" line.
#
# Everything on the review side is kept whoever wrote it: an inline comment is
# anchored to code (ADO keeps any file-anchored thread), and a review is review
# feedback by definition -- an automated reviewer that reviews is a reviewer,
# the way ADO keeps "AI Code Review" threads.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#

function ConvertTo-P20GitHubDate {
    # created_at / submitted_at as one ISO string on both hosts. pwsh 7's
    # ConvertFrom-Json turns the string into a [datetime]; 5.1 leaves it.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

function Test-P20GitHubBot {
    # A Bot ACCOUNT, by GitHub's own account type -- never by a name pattern.
    param($User)
    if (-not $User) { return $false }
    return ([string]$User.type -eq 'Bot')
}

function New-P20GitHubComment {
    param($Id, $User, $Body, $Date)
    $login = ''
    if ($User -and $User.login) { $login = [string]$User.login }
    return [PSCustomObject]@{
        id            = [long]$Id
        author        = [PSCustomObject]@{ displayName = $login }
        content       = [string]$Body
        publishedDate = (ConvertTo-P20GitHubDate $Date)
        commentType   = 'text'
        isDeleted     = $false
    }
}

function ConvertTo-P20GitHubThreads {
    <#
        The three payloads (arrays of the REST objects, any of them empty) as
        @{ Threads = <actionable threads, in the card's thread shape>;
           NonActionable = <[long] ids named on the card's Non-actionable line>;
           Total = <threads considered> }.

        A thread is { id; status; threadContext; properties; comments } -- the
        shape Get-P20ThreadDelta and the card writer already read. `status`
        says WHAT the thread is: GitHub's REST API does not carry whether an
        inline thread is resolved, so no active/fixed word is invented for it.
    #>
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$ReviewComments = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$IssueComments = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$Reviews = @()
    )
    $threads = @()
    $nonActionable = @()
    $total = 0

    # -- Inline review comments, grouped into their threads ----------------------
    $byRoot = [ordered]@{}
    foreach ($c in @($ReviewComments | Where-Object { $_ })) {
        $root = [long]$c.id
        if ($c.PSObject.Properties['in_reply_to_id'] -and $c.in_reply_to_id) { $root = [long]$c.in_reply_to_id }
        $key = [string]$root
        if (-not $byRoot.Contains($key)) { $byRoot[$key] = @() }
        $byRoot[$key] = @($byRoot[$key]) + $c
    }
    foreach ($key in @($byRoot.Keys)) {
        $total++
        $members = @($byRoot[$key] | Sort-Object -Property @{ Expression = { ConvertTo-P20GitHubDate $_.created_at } }, @{ Expression = { [long]$_.id } })
        $anchor = $members[0]
        $lineNo = $null
        if ($anchor.PSObject.Properties['line'] -and $null -ne $anchor.line) { $lineNo = $anchor.line }
        elseif ($anchor.PSObject.Properties['original_line'] -and $null -ne $anchor.original_line) { $lineNo = $anchor.original_line }
        $context = [PSCustomObject]@{ filePath = [string]$anchor.path; rightFileStart = $null }
        if ($null -ne $lineNo) { $context.rightFileStart = [PSCustomObject]@{ line = $lineNo } }
        $status = 'review comment'
        # GitHub nulls `line` when the code under the comment has since changed.
        if ($anchor.PSObject.Properties['line'] -and $null -eq $anchor.line) { $status = 'review comment, outdated' }
        $comments = @($members | ForEach-Object { New-P20GitHubComment $_.id $_.user $_.body $_.created_at })
        $thread = [PSCustomObject]@{ id = [long]$key; status = $status; threadContext = $context; properties = $null; comments = $comments }
        if (@($comments | Where-Object { -not [string]::IsNullOrWhiteSpace($_.content) }).Count -gt 0) { $threads += $thread }
    }

    # -- Review summaries: each submitted review with text ------------------------
    foreach ($r in @($Reviews | Where-Object { $_ })) {
        $state = [string]$r.state
        if ($state -eq 'PENDING') { continue }   # an unsent draft, visible to its author only
        if ([string]::IsNullOrWhiteSpace([string]$r.body)) { continue }   # a vote, not a remark
        $total++
        $threads += [PSCustomObject]@{
            id            = [long]$r.id
            status        = ('review, ' + ($state.ToLowerInvariant() -replace '_', ' '))
            threadContext = $null
            properties    = $null
            comments      = @(New-P20GitHubComment $r.id $r.user $r.body $r.submitted_at)
        }
    }

    # -- The conversation tab: each comment its own thread ------------------------
    foreach ($c in @($IssueComments | Where-Object { $_ })) {
        if ([string]::IsNullOrWhiteSpace([string]$c.body)) { continue }
        $total++
        if (Test-P20GitHubBot $c.user) { $nonActionable += [long]$c.id; continue }
        $threads += [PSCustomObject]@{
            id            = [long]$c.id
            status        = 'conversation'
            threadContext = $null
            properties    = $null
            comments      = @(New-P20GitHubComment $c.id $c.user $c.body $c.created_at)
        }
    }

    # In the order they were written, whichever channel they came through.
    $threads = @($threads | Sort-Object -Property @{ Expression = { $_.comments[0].publishedDate } }, @{ Expression = { $_.id } })
    return [PSCustomObject]@{ Threads = $threads; NonActionable = @($nonActionable | Sort-Object -Unique); Total = $total }
}

function ConvertFrom-P20GitHubPRUrl {
    # https://github.com/<owner>/<repo>/pull/<n> -> @{ Repo = 'owner/repo'; Number = n }, or $null.
    param([AllowEmptyString()][AllowNull()][string]$Url)
    $m = [regex]::Match("$Url", '^https://(?:www\.)?github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)(?:[/#?]\S*)?$')
    if (-not $m.Success) { return $null }
    return [PSCustomObject]@{ Repo = "$($m.Groups[1].Value)/$($m.Groups[2].Value)"; Number = [long]$m.Groups[3].Value }
}

function Find-P20CardsForGitHubPR {
    <#
        The cards in $Folder whose PR URL: line names GitHub pull request
        $Number -- in any repository, or in $Repo alone when it is given. Each
        hit: @{ Path; Repo; Url }. This is what lets the verb run with no
        checkout at all: NewPR wrote the line, and the line names the repo.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string[]]$Folder,
        [long]$Number,
        [string]$Repo = '',
        # consts.json tokens.prUrl, passed in -- never retyped here.
        [Parameter(Mandatory = $true)][string]$Token
    )
    $hits = @()
    foreach ($dir in @($Folder | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            foreach ($m in [regex]::Matches($text, '(?m)^' + [regex]::Escape($Token) + '[ \t]*(https://\S+)')) {
                $ref = ConvertFrom-P20GitHubPRUrl $m.Groups[1].Value.TrimEnd("`r")
                if (-not $ref -or $ref.Number -ne $Number) { continue }
                if ($Repo -and $ref.Repo -ne $Repo) { continue }
                $hits += [PSCustomObject]@{ Path = $f.FullName; Repo = $ref.Repo; Url = $m.Groups[1].Value.TrimEnd("`r") }
                break
            }
        }
    }
    return $hits
}

function Get-P20GitHubLinkedIssues {
    # The issue numbers a pull request's body names: NewPR's own plain
    # "Issue: #n" line, and GitHub's closing keywords ("Fixes #n"). A bare
    # "#n" anywhere in prose is not a link to a card and is not read.
    param([AllowEmptyString()][AllowNull()][string]$Body)
    $ids = @()
    foreach ($m in [regex]::Matches("$Body", '(?im)^\s*Issue:\s*#(\d+)\b')) { $ids += $m.Groups[1].Value }
    foreach ($m in [regex]::Matches("$Body", '(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b')) { $ids += $m.Groups[1].Value }
    return @($ids | Select-Object -Unique)
}
