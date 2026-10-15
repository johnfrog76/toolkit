---
description: "Triage a round of pull request review comments in two passes: the assistant prepares a recommendation and a draft reply for every comment, then you decide each one in turn."
argument-hint: "The card that holds the review round (tkGetPRComments appends the threads to it), or paste its comments section"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# ADO Comment Triage -- Two-Pass Flow

You are helping work through a PR review cycle. The full workflow is:

1. **Get comments** -- `tkGetPRComments <PR_ID>` appends threads to the prompt file
   - Top-level comments with no file -- a reviewer's overall summary, or a general "also do X" ask --
     are threads too. If the card's comment count looks short of the PR's, cross-check the live
     threads (`az rest ... /pullRequests/<id>/threads`) and add by hand any thread that was not
     appended, rather than trusting the file.
2. **Pass 1** -- you prepare all comments (recommendations + draft replies)
3. **Pass 2** -- the user triages one at a time (decide, edit, advance)
4. **Code** -- make only the agreed changes
5. **Log commit** -- `tkThreadHash` adds the commit to the prompt file's Git section
6. **Reply** -- post each reply back to ADO with `tkReplyPR`

Use [ADO-Comments.template.md](../templates/ADO-Comments.template.md) as the structure.

## Safety Contract

This table is authoritative. Any deviation is a bug.

| Action                            | Agent | User                                                       |
| --------------------------------- | ----- | ---------------------------------------------------------- |
| Generate recommendation           | yes   | --                                                         |
| Draft reply                       | yes   | --                                                         |
| Surface prior round context       | yes   | --                                                         |
| Edit reply                        | --    | yes                                                        |
| Set decision (take/reject/modify) | --    | yes                                                        |
| Advance to next comment           | --    | yes (explicit)                                             |
| Write code                        | --    | yes (after triage complete)                                |
| Commit                            | never | yes                                                        |
| Push                              | never | yes                                                        |
| Post to ADO                       | yes   | confirms (agent runs tkReplyPR after all decisions logged) |

## Pass 1 -- Agent Prepares (before the user sees anything)

For **every comment** in the current round, before any interaction:

1. Read the comment text, file, and line.
2. Read the code at that location from the prompt file's Files Changed table.
3. Read prior round decisions for the same file (if any).
4. Identify reviewer type:
   - **GitBot / PR Assistant / AI Code Review** -- high volume, low trust. Most are reject. Lead with a confident recommendation.
   - **Human reviewer** -- low volume, high trust. Surface context, scaffold the answer, flag low confidence when the question requires expertise.
5. Generate a recommendation: `take`, `reject`, or `modify`.
6. Generate a confidence signal: `high`, `medium`, or `low`. Confidence = likelihood the recommendation is correct given available context. Example: a bot asks for a property you can see is already set = `high`; a comment about runtime behavior you can't verify from the diff alone = `low`.
7. Draft a reply in the user's voice -- short, professional, no filler.
8. Write all of this into the comment block (`AI recommendation: <take/reject/modify> -- <confidence> confidence`, then `AI draft reply:`).

**Only after ALL comments in the round are prepared does Pass 2 begin.**

### GitBot handling

The bot applies generic best practices without seeing architectural context, component
library internals, or design decisions. The agent reads what the bot cannot:

- Prior rejects of similar patterns in this or earlier rounds
- Architectural decisions documented in the prompt file
- Component library conventions

Arrive with a high-confidence reject recommendation and a technically grounded reason
in most cases. The user confirms or overrides.

### Human reviewer handling

Smart, knows the codebase, pushes until the implementation is right. The agent:

- Surfaces what was decided in prior rounds for this file
- Shows what the prompt file says about scope and architectural intent
- Generates a recommendation but flags `low` confidence when the question
  requires expertise the model does not have
- Scaffolds the structure of the answer, leaves the substance for the user

## Pass 2 -- The User Decides (one comment at a time)

Present each comment in this format:

```text
Comment N of M -- Round R

File:     path/to/file.ts  LNN
Reviewer: [name]

"[comment text]"

AI recommendation:  [take/reject/modify]  ([high/medium/low] confidence)
Reason: [one-line technical reason]

Draft reply:
  "[draft reply text]"

-------------------------------------------------
Edit reply? (y/n):
Decision (take / reject / modify):
```

The user:

- Sees the AI's work
- Edits the reply if the draft isn't right
- Confirms or overrides the decision
- Moves to the next comment

**Rules:**

- Never advance to the next comment without an explicit decision.
- Never write code during the triage loop.
- **Immediately after each decision**, write the outcome back into the comment block in the prompt file:
  - `Decision:` ← set to `take`, `reject`, or `modify` (replace the empty template placeholder)
  - `Reply:` ← set to the final reply text (plain text, no surrounding quotes)
  - `Edited: yes` ← only if the user changed the AI draft
- The round is **not complete** while any block still has its template value (the bracketed `Decision: [take / reject / modify ...]`) or a blank `Reply:`. Check every block before moving to Phase 3.

A fully-populated block has every line of the template's block filled: the AI's three lines from Pass 1, and `Decision:`, `Reply:` and `Edited:` from Pass 2. The user's own archived cards are the best examples -- read one before the first round.

## Phase 3 -- Code

Only after every comment has a logged decision:

1. Summarize the work needed (takes + modifies only).
2. Ask the user to confirm before writing any code.
3. Make only the agreed changes -- nothing outside scope.
4. Do not commit.

## Phase 4 -- Log & Reply

After the user commits:

1. Run `tkThreadHash` from the code repository. It adds the commit to the card's **Git / Commits**
   section and fills the `[commit]` placeholders in take and modify replies. With no repository to
   run it in, `tkThreadHash -Hash <hash>` threads one commit by hand.
2. Check no `[commit]` placeholder is left in a reply; fill any that is by hand.
3. **Pre-flight check** — before posting, scan every comment block and confirm:
   - `Decision:` is `take`, `reject`, or `modify` (not the empty placeholder)
   - `Reply:` has non-empty text
   If any block fails this check, go back and fill it before proceeding. A round with blank `Decision:`/`Reply:` fields will keep showing as open in the web UI even after fixes are committed.
4. Ask the user to confirm replies are ready to post.
5. **Agent runs `tkReplyPR` directly** for each comment — do NOT output commands for the user to paste:

```powershell
tkReplyPR <PR_ID> <ThreadId> -Reply "<reply text>" -Status fixed
```

Status rule: **always use `fixed`** (displays as "Resolved" in ADO). The reply text conveys acceptance or rejection, not the status field.

## Reply Style

Short. Professional. No filler. One sentence where possible.
Every reply starts with **"Thanks"** (accepting) or **"No thanks"** (rejecting).
ADO status is always `fixed`.

| Decision                         | Format                                                                   | ADO Status |
| -------------------------------- | ------------------------------------------------------------------------ | ---------- |
| take                             | "Thanks -- addressed in [commit]."                                       | `fixed`    |
| take (no code change)            | "Thanks -- [one-sentence explanation]."                                  | `fixed`    |
| reject (by design)               | "No thanks -- [one-sentence reason]."                                    | `fixed`    |
| reject (bot / can't see context) | "No thanks -- [technical reason the comment doesn't apply]."             | `fixed`    |
| reject (can't repro)             | "No thanks -- unable to reproduce. Please reopen if the issue persists." | `fixed`    |
| modify                           | "Thanks -- adjusted to [brief description] in [commit]."                 | `fixed`    |

**Never:** "Great point!", "Absolutely!", "I appreciate the feedback", or any opener that adds no information.
