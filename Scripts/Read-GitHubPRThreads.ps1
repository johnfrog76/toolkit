#
# A GitHub pull request's review conversation, in the thread shape
# Get-PRComments.ps1 already writes into a card.
#
# NOT a runnable verb: this file is DOT-SOURCED by the three pull-request verbs
# -- Get-PRComments.ps1, Send-PRReply.ps1 and Invoke-PRReview.ps1 -- and by
# Tests/Test-PRComments.ps1, which runs the pure functions below against
# fixture payloads. Nothing here calls gh -- the scripts do that, through
# Invoke-P20TrackerRead -- so every rule in this file can be held by a table.
# One function, Resolve-P20GitHubPRRepo, asks git (through the same helper)
# for a code checkout's remote; it is the one answer to "which repository does
# this pull request number mean" that all three verbs share.
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

function Resolve-P20GitHubPRRepo {
    <#
        Which repository a GitHub pull request number means, asked in the one
        order every pull-request verb uses:

          1. the card in current/ whose PR URL: line names this pull request
             (NewPR wrote it, and it names the repository -- no checkout needed);
          2. -Repository, as typed: owner/name, or a name under the owner
             (-Project when given, else the board's);
          3. this checkout's GitHub remote -- only when the cwd is a code
             checkout, never the Toolkit's own;
          4. the board's one repository.

        Returns @{ Repo; Card; Error; Hint }. Card is the one card that named
        the pull request, when exactly one did. Error set means refused: the
        caller prints Error and Hint and exits 2. A board of several
        repositories and none of the above is refused, never guessed -- the
        same number on the wrong repository is somebody else's pull request.

        Needs Invoke-TrackerRead.ps1, Resolve-Tracker.ps1 and the CLI fallbacks
        dot-sourced by the caller.
    #>
    param(
        [long]$PullRequestId = 0,
        [string]$Repository = '',
        [string]$Project = '',
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        [AllowEmptyString()][AllowNull()][string]$CurrentDir,
        # consts.json tokens.prUrl, passed in -- never retyped here.
        [Parameter(Mandatory = $true)][string]$Token,
        # The Toolkit's own checkout, whose remote is never a card's repository.
        [Parameter(Mandatory = $true)][string]$ToolkitRoot,
        # The verb, for the hint's usage line.
        [string]$Verb = 'GetPRComments'
    )
    $prefix = Get-CliPrefix
    $owner = Get-P20TrackerOwner -OrgUrl $OrgUrl
    $askedRepo = ''
    if ($Repository) {
        if ($Repository -match '/') { $askedRepo = $Repository }
        else {
            $askedOwner = $owner
            if ($Project) { $askedOwner = $Project }
            $askedRepo = "$askedOwner/$Repository"
        }
    }

    $repo = ''
    $card = $null
    # 1. The card that already names this pull request names its repository too.
    if ($PullRequestId) {
        $named = @(Find-P20CardsForGitHubPR -Folder @($CurrentDir) -Number $PullRequestId -Repo $askedRepo -Token $Token)
        $namedRepos = @($named | ForEach-Object { $_.Repo } | Sort-Object -Unique)
        if ($namedRepos.Count -gt 1) {
            return @{
                Repo = ''; Card = $null
                Error = "PR #$PullRequestId is named by cards in more than one repository: $($namedRepos -join ', ')."
                Hint = "Say which: $prefix$Verb $PullRequestId -Repository <owner>/<name>."
            }
        }
        if ($namedRepos.Count -eq 1) {
            $repo = $namedRepos[0]
            if ($named.Count -eq 1) { $card = $named[0].Path }
            Write-Host "[*] The card names it: $(Split-Path $named[0].Path -Leaf) -> $($named[0].Url)" -ForegroundColor DarkGray
        }
    }
    # 2. -Repository.
    if (-not $repo -and $askedRepo) { $repo = $askedRepo }
    # 3. This checkout's GitHub remote, when the cwd is a code checkout.
    if (-not $repo) {
        $cwdRead = Invoke-P20TrackerRead 'git' @('rev-parse', '--absolute-git-dir')
        $cwdDir = "$(@($cwdRead.Out)[0])".Trim()
        $tkRead = Invoke-P20TrackerRead 'git' @('-C', $ToolkitRoot, 'rev-parse', '--absolute-git-dir')
        $tkDir = "$(@($tkRead.Out)[0])".Trim()
        if ($cwdRead.Code -eq 0 -and $cwdDir -and $cwdDir -ne $tkDir) {
            $remoteRead = Invoke-P20TrackerRead 'git' @('remote', 'get-url', 'origin')
            $remote = "$(@($remoteRead.Out)[0])".Trim()
            if ($remoteRead.Code -eq 0 -and $remote -match 'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$') {
                $repo = "$($Matches[1])/$($Matches[2])"
            }
        }
    }
    # 4. The board's one repository.
    if (-not $repo) {
        $answer = Resolve-P20TrackerRepo -OrgUrl $OrgUrl -Projects $Projects -CliPrefix $prefix
        if (-not $answer.Repo) {
            return @{
                Repo = ''; Card = $null
                Error = "$($answer.Reason) No card in current/ names this pull request, so its repository cannot be told."
                Hint = "Pass it: $prefix$Verb <PrId> -Repository <owner>/<name>. $($answer.Hint)"
            }
        }
        $repo = $answer.Repo
    }
    return @{ Repo = $repo; Card = $card; Error = ''; Hint = '' }
}

# -- The write side: ReplyPR and AddPRReview ---------------------------------------

function Get-P20GitHubReplyStatus {
    <#
        What ReplyPR's -Status (Azure DevOps' thread vocabulary) means on GitHub,
        where a review thread is only resolved or unresolved:

          fixed, closed   resolve the thread  (resolveReviewThread)
          active          reopen it           (unresolveReviewThread) -- ADO's
                          "active" is the open state a thread returns to, which
                          is exactly GitHub's unresolved
          (none)          the reply alone

        byDesign, pending and wontFix carry a REASON GitHub has nowhere to keep;
        each is refused by name, before anything is posted, rather than quietly
        becoming "resolved" or nothing. Returns @{ Action; Word; Error; Hint }:
        Action is the mutation's name or '', Word what the card's Status: line
        reads afterwards.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Status)
    switch ("$Status") {
        '' { return @{ Action = ''; Word = ''; Error = ''; Hint = '' } }
        { $_ -in @('fixed', 'closed') } { return @{ Action = 'resolveReviewThread'; Word = 'resolved'; Error = ''; Hint = '' } }
        'active' { return @{ Action = 'unresolveReviewThread'; Word = 'unresolved'; Error = ''; Hint = '' } }
    }
    return @{
        Action = ''; Word = ''
        Error = "-Status $Status has no equivalent on GitHub: a review thread is only resolved or unresolved, and keeps no reason."
        Hint = "Nothing was posted. Use -Status fixed or closed to resolve the thread, active to reopen it, or leave -Status off -- and say '$Status' in the reply itself."
    }
}

function Get-P20GitHubCommentKind {
    <#
        What a ReplyPR -ThreadId is, from the three lookups the script made
        (each the parsed REST object, or $null when GitHub had none). The id
        is GetPRComments' thread id, so it is one of its three kinds:

          review        an inline review comment on THIS pull request. Root is
                        the thread's first comment -- GitHub's replies endpoint
                        answers a top-level comment only, and a thread's every
                        reply points at it -- and the thread can be resolved.
          conversation  a conversation-tab comment: no thread on GitHub, so a
                        reply is a new comment on the pull request.
          summary       a review's own summary text: the same.

        A comment that belongs to another pull request is not this one's.
        Returns @{ Kind; Root; Url } or $null.
    #>
    param([long]$Number, $ReviewComment, $IssueComment, $Review)
    if ($ReviewComment -and "$($ReviewComment.pull_request_url)" -match "/pulls/$Number$") {
        $root = [long]$ReviewComment.id
        if ($ReviewComment.PSObject.Properties['in_reply_to_id'] -and $ReviewComment.in_reply_to_id) { $root = [long]$ReviewComment.in_reply_to_id }
        return [PSCustomObject]@{ Kind = 'review'; Root = $root; Url = [string]$ReviewComment.html_url }
    }
    if ($IssueComment -and "$($IssueComment.issue_url)" -match "/issues/$Number$") {
        return [PSCustomObject]@{ Kind = 'conversation'; Root = [long]$IssueComment.id; Url = [string]$IssueComment.html_url }
    }
    if ($Review -and $Review.id) {
        return [PSCustomObject]@{ Kind = 'summary'; Root = [long]$Review.id; Url = [string]$Review.html_url }
    }
    return $null
}

function Find-P20GitHubReviewThreadNode {
    <#
        The GraphQL review thread whose FIRST comment is REST comment $RootId,
        from one page of reviewThreads nodes. The two ids are different things:
        REST knows a comment's number (databaseId), GraphQL resolves a thread
        by its node id, so the one is found by the other. $null when absent.
    #>
    param($Nodes, [long]$RootId)
    foreach ($n in @($Nodes | Where-Object { $_ })) {
        $first = @($n.comments.nodes)[0]
        if ($first -and [long]$first.databaseId -eq $RootId) { return $n }
    }
    return $null
}

function Get-P20DiffRightLines {
    <#
        The lines GitHub will take an inline comment on: for each file, the
        new-side line numbers inside the diff's hunks (added and context lines).
        A review comment is positioned by path and line on the RIGHT side --
        the new version's own numbering, which is what the review prompt asks
        the model for -- so no translation is needed; but a line outside every
        hunk makes GitHub refuse the WHOLE review, so it is checked first.
        Returns @{ '<path>' = @{ <line> = $true } }.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Diff)
    $map = @{}
    $path = ''
    $next = 0
    foreach ($raw in ("$Diff" -split "`n")) {
        $line = $raw.TrimEnd("`r")
        if ($line -match '^diff --git ') { $path = ''; $next = 0; continue }
        if ($line -match '^\+\+\+ (?:b/)?(.+)$') {
            $path = $Matches[1]
            if ($path -eq '/dev/null') { $path = '' }
            elseif (-not $map.ContainsKey($path)) { $map[$path] = @{} }
            continue
        }
        if ($line -match '^--- ') { continue }
        if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') { $next = [int]$Matches[1]; continue }
        if (-not $path -or $next -le 0) { continue }
        if ($line.StartsWith('-') -or $line.StartsWith('\')) { continue }
        if ($line.StartsWith('+') -or $line.StartsWith(' ') -or $line -eq '') {
            $map[$path][$next] = $true
            $next++
        }
    }
    return $map
}

function New-P20GitHubReviewPayload {
    <#
        AddPRReview's findings as ONE GitHub review: event COMMENT, each finding
        an inline comment ({path, line, side: RIGHT, body}) when its line is in
        the diff, and named in the review's body otherwise -- the way the Azure
        DevOps path falls back to a general comment. Every body starts
        "[AI Code Review]", the marker GetPRComments reads as the bot's.
        Returns @{ Payload = <ordered hashtable>; Inline = n; Moved = n }.
    #>
    param([object[]]$Findings, [hashtable]$RightLines, [string]$Marker = '[AI Code Review]')
    $comments = @()
    $moved = @()
    foreach ($f in @($Findings | Where-Object { $_ })) {
        $file = ([string]$f.file) -replace '^b/', ''
        $file = $file.TrimStart('/')
        $lineNo = 0
        [void][int]::TryParse("$($f.line)", [ref]$lineNo)
        $text = "$Marker $($f.comment)"
        if ($file -and $lineNo -gt 0 -and $RightLines -and $RightLines.ContainsKey($file) -and $RightLines[$file].ContainsKey($lineNo)) {
            $comments += [ordered]@{ path = $file; line = $lineNo; side = 'RIGHT'; body = $text }
        }
        else {
            $where = '(no file)'
            if ($file) { $where = "``$file``"; if ($lineNo -gt 0) { $where += " L$lineNo" } }
            $moved += "- $where -- $($f.comment)"
        }
    }
    $body = "$Marker $(@($Findings | Where-Object { $_ }).Count) finding(s)."
    if ($moved.Count -gt 0) {
        $body += "`n`nNot on a line this pull request changes, so not inline:`n" + ($moved -join "`n")
    }
    $payload = [ordered]@{ event = 'COMMENT'; body = $body; comments = @($comments) }
    return [PSCustomObject]@{ Payload = $payload; Inline = $comments.Count; Moved = $moved.Count }
}
