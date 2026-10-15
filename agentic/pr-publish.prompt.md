---
description: "Ship-it flow, stage 2: when the draft pull request is polished and its review comments look good, flip it to ready and post a one-line note about it to your team, unless you opt out."
argument-hint: "PR number (default: read from the prompt file's PR URL line); optional -NoComms to flip ready without posting"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# PR Publish -- stage 2 of 2 (ready + comms)

This is stage 2 of the two-stage ship flow. Stage 1 is [pr-ship](pr-ship.prompt.md) (draft PR). Run
this only after the user has polished the markdown and media on the draft PR and checked that
review comments look good -- deciding the PR is ready to be seen is the user's call, not
automatic.

`tkPublishPR` flips the draft to ready (step 3); this prompt adds the decision around it and the
note to the team.

## Why this is a separate step from pr-ship

Publishing is a different decision than shipping: shipping is "code is done, open for early eyes."
Publishing is "the team should see this now" -- and the note to the team goes out by default.
Bundling that into stage 1 would mean either always posting on every draft (noisy, premature) or
never posting at all. Splitting them means the user decides *when* to cross that line,
explicitly.

## Steps

1. **Resolve the PR** -- from the prompt file's `PR URL:` line (written by `tkNewPR`), or the passed-in
   PR number. If no `PR URL:` line exists, stop: stage 1 hasn't run yet.

2. **Preview the flip**: `tkPublishPR <id> -WhatIf`. It prints the exact `PATCH` and its body and
   sends nothing. Show it to the user.

3. **Flip draft → ready** -- once the user confirms the PR is ready to publish: `tkPublishPR <id>`.
   - The verb reads the card's `PR URL:` line, takes the token the way `tkNewPR` does (the active
     Space's `tenant` when it declares one), confirms on Azure DevOps that the pull request is an
     active draft, and sends `PATCH .../pullrequests/{id}?api-version=7.1` with `{"isDraft":false}`.
     On success it writes one line under the `PR URL:` line, `PR published: <url>`.
   - **Already ready** is a refusal (exit 2) that sends nothing: say so and stop -- don't re-publish
     or re-post. A card with no `PR URL:` line is refused the same way: stage 1 has not run.
   - **A GitHub pull request** is refused with its own answer in the hint: `gh pr ready <url>`. Run
     that instead, with the user's go-ahead.
   - Do not write the REST call by hand, and do not drop to bash `curl` or the `az` CLI for it.

4. **Comms -- the default is to post, not to ask:**
   - Comms is the **communication** add-on (`features.communication`). If it is off, `tkSendTeams`
     does not exist: report "comms skipped (communication is off)" and go to step 5.
   - The recipient is a **key**, not a URL or a channel name: one declared under
     `managerWorkflow.communication.recipients`, or under the active Space's
     `communication.recipients`. Use the key the user names; if there is none and only one is
     declared, confirm that one. Never invent a key -- an undeclared one is refused.
   - Compose one line: `PR {number}: [PR title](PR URL), thanks for review` -- a real markdown link,
     not a raw URL and not a dump of `## Described Changes`.
   - Preview it unsent first: `tkSendTeams <key> "<line>" -WhatIf`. Every gate runs and the payload
     comes back. Then, with the user's go-ahead, the same command without `-WhatIf`, once per
     recipient key.
   - `tkSendTeams` posts through the running agent (`tkAgent`, or `tkWeb -Dev`), on `web.agentPort`
     from config, and the agent reads the webhook variables from `.env` in the package root **when
     it starts**. A variable exported in the shell you are typing in is not seen, and a change to
     `.env` needs the agent restarted (`tkWeb -Stop`, then `tkWeb -Dev`). A connection error means
     the agent is not up; "Not sent -- no webhook configured" names the variable that is missing.
     Neither is a reason to hand-roll the POST.
   - **`-NoComms`**: skip the post entirely but still flip the PR to ready. Use when the user
     explicitly doesn't want this one announced (a WIP-adjacent PR, an internal-only change).
   - A `skipped` or `disabled` status is a configuration answer, not a failure: report it, don't block
     the ready-flip on it.
   - **If the post itself fails** (agent not running, webhook unreachable, non-2xx from Teams):
     report it plainly in step 5 and move on -- don't retry in a loop and don't stop to debug the
     webhook. The PR is ready whether or not the note landed.

5. **Report back**: PR ready-state confirmed, and one of "posted to `<key>`", "comms skipped
   (`-NoComms` / communication off / `skipped` / `disabled`)", or "comms failed to post to `<key>`
   (`<reason>`) -- PR is still ready".

## Safety contract

| Action | Agent | User |
|---|---|---|
| Check PR is currently draft | yes | -- |
| Flip draft → ready | yes | confirms |
| Compose the one-line note | yes | -- |
| Preview the note with `-WhatIf` | yes | -- |
| Post the note (default) | yes | confirms, or passes `-NoComms` up front |
| Decide whether this PR is ready to publish at all | never (out of scope) | yes -- run this only when ready |
