---
description: "Ship-it flow, stage 1: when the code is ready for review, check that the card's Summary, Described Changes and Implementation Details are written, then commit, push and open a draft pull request with tkNewPR."
argument-hint: "Optional: path to the prompt file (default: auto-detect from current branch)"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# PR Ship -- stage 1 of 2 (draft PR)

This is stage 1 of the two-stage ship flow. Stage 2 is [pr-publish](pr-publish.prompt.md) (draft → ready, comms). This stage only gets code from "done" to "draft PR open" -- it never flips the PR to ready and never sends comms.

## Why this exists

The prompt file's context section (`## Summary`, `## Described Changes`, `## Implementation Details`) is manually maintained. `tkNewPR` reads `## Described Changes` directly into the PR description -- if that section is still the template placeholder, the PR ships with an empty or useless description and nobody notices until a reviewer asks "what does this actually do." This command's whole job is to make skipping that step harder than doing it.

## Steps

1. **Locate the prompt file** for the current branch (in `current/` -- same auto-detection `tkNewPR` uses: match branch suffix, fall back to work-item-ID prefix). Use the arg if one was passed.

2. **Verify context is filled in** -- read the file and check these sections are not still template placeholders:
   - `## Summary` -- must not be only the HTML comment (`<!-- Your plain-English explanation... -->`) with no text below it.
   - `## Described Changes` -- must have at least one real bullet (not just the `<!-- Up to 5 high-level bullets... -->` comment).
   - `## Implementation Details` -- table should list at least one changed file, matching what `git diff --stat` against the target branch actually shows. Flag (don't silently fix) any file in the diff that's missing from the table -- that's a sign the table was written early and code moved on since.

   If any of these are empty or stale: **stop and tell the user what's missing**, with the actual diff summary alongside so filling it in is fast (paste-ready, not "go write documentation"). Do not write the content yourself unless asked -- the user's voice belongs in the PR description.

3. **Commit** -- once context is filled and the user explicitly confirms they're ready to commit, the agent runs the commit (message drawn from `## Described Changes`). After commit, run `tkThreadHash` from the code repository: it writes each commit on the branch as its own `- <hash> <message>` bullet under `## Git` / `Commits:`, which is what flips `tkStatus` from "Active" to "In Progress" (`docs/hub/cards.md`, "State is derived, never stored"). A hash written inline or comma-separated is not detected. Never amend an existing commit to backfill this.

4. **Push** -- immediately after commit, the agent pushes the branch (`git push -u origin <branch>` on first push for the branch, plain `git push` after). No separate confirmation needed beyond the commit confirmation in step 3 -- this is a normal part of shipping, not a distinct risky action.

5. **Verify the Space before running `tkNewPR`** -- `tkNewPR`'s prompt-file auto-detection walks the active Space's `current/` folder (e.g. `<space-a>/current`) and can miss a file that lives under a different Space (e.g. `<space-b>/current`) even when the actual git repo/remote was identified correctly. It can find no file (a safe, loud failure) or -- worse -- match a different work item if two Spaces happen to have similarly-named prompt files. Before running `tkNewPR`, confirm:
   - Run `tkSwitchSpace Status` to see which Space the toolkit is currently scoped to, and compare it against the organisation in the prompt file's `**ADO Link:**` line. If they don't match, run `tkSwitchSpace <correct-slug>` before doing anything else -- do not proceed with a mismatched scope.
   - The prompt file path you're passing (explicit `-File`, or what auto-detection would resolve to) lives under the Space folder that actually corresponds to the git remote for this repo (check `git remote -v` / the ADO organisation in the URL against the prompt file's `**ADO Link:**` line).
   - If auto-detection fails to find the prompt file or looks in the wrong Space's `current/` folder, do not paper over it with `-Project` / `-Repository` overrides on faith -- those flags change *where the PR/work-item update is sent*, so a wrong guess there is a wrong-org write, not a cosmetic mismatch. Stop and confirm the org/project/repo with the user before passing them.
   - Prefer passing `-File <explicit path>` (as already resolved in step 1) over relying on auto-detection once you know the layout is multi-project -- it sidesteps the lookup entirely rather than trying to out-guess it.

6. **Run `tkNewPR -Draft`** (add `-SkipWorkItem` only if asked; otherwise let it move the ADO card to Code Review and post the comment as usual). If the `[*] Repo:` line in the output doesn't match the actual repo, stop and confirm with the user rather than retrying with different `-Repository` / `-Project` guesses.

   - `-File` does **not** change the working directory: the source branch (and, if the prompt file has no `**ADO Link:**` line, the project/repo) are still read from the shell's cwd. Always `cd` into the target repo in the same pwsh invocation before calling `tkNewPR` -- in agent environments the shell cwd often resets to the hub (or wherever the session started) after every tool call.

   - If the state-change step fails (a 400, a state/lane that doesn't exist for this work item type, or something else): the PR itself is still created, so the run has not failed. **Tell the user it failed and move on** -- don't dig into fixing it mid-flow unless asked. On a 400 the work item can be moved by hand with `az boards work-item update --id <id> --state "Code Review" --org <org>` (the `az` CLI fills in a default reason). Board lanes and state names vary per team/project, so a state-change failure here isn't necessarily a bug worth chasing every time.

7. **Stop here.** Do not flip the PR to ready and do not send comms -- that's [pr-publish](pr-publish.prompt.md), run separately once the user has manually polished markdown/media and checked review comments look good.

## Safety contract

| Action | Agent | User |
|---|---|---|
| Check context sections for placeholders | yes | -- |
| Write Summary / Described Changes / Implementation Details content | only if asked | yes (default) |
| Commit | yes (after the user confirms ready) | confirms |
| Record commit hash in prompt file's Git section (`tkThreadHash`) | yes | -- |
| Push | yes (immediately after commit) | -- |
| Verify Space/project scoping matches prompt file before `tkNewPR` | yes | -- |
| Guess `-Project` / `-Repository` on auto-detection failure | never -- stop and confirm | yes |
| Run `tkNewPR -Draft` | yes (after the user confirms context is ready) | confirms |
| Flip PR to ready / send comms | never (out of scope) | via `pr-publish` |
