---
description: "Build the card you were handed: take its branch from current main, do what the card says, thread each commit into it and keep its Summary, Described Changes and Implementation Details current, then ship with pr-ship."
argument-hint: "The hand-off block tkStartWork printed -- or a card's id"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# Build

You have been handed one piece of work. Everything you need is in the block above this prompt: how
work is done in this Space, then the work itself under **The work** -- a card (a file in the hub) or an
issue -- and its path or address in that heading. The card is the record: what it asks for, what was
decided, and what changed all end up written in it, not only in this chat.

## Steps

1. **Read the work.** Under **The work**, read the card or the issue in full -- the summary, the
   acceptance criteria or definition of done, and any questions already written down. If it names a
   spec, a design note or a document, read that too before you change anything. Start the work from
   what is written; ask only about something the card does not answer and you cannot find out.
2. **Take the branch from current main.** The card's `## Branch` section names it. In the code
   repository: `git fetch origin`, then `git switch -c <branch> origin/main` -- or, if the branch already
   exists, `git switch <branch>` and bring it up to date with main. An issue with no card: name the
   branch for the issue's number and title.
3. **Do what the card says**, in small commits that each say what changed and why. Run the
   repository's own tests for what you touch, and change its documentation in the same commit as the
   behaviour it describes.
4. **Thread each commit into the card**: run `tkThreadHash` from the code repository after
   committing. It writes every commit on the branch into the card as its own `- <hash> <message>` bullet,
   which is what moves the card to In Progress; never type a hash in by hand, and never amend a commit
   to backfill one.
5. **Write the card as you go.** Fill `## Summary` (what was done and why, in plain words),
   `## Described Changes` (up to five bullets -- the pull request's description is built from them) and
   `## Implementation Details` (one row per file you changed, matching `git diff --stat` against main).
   Write the diagnosis and every decision -- and the alternative you rejected, and why -- into the card,
   not only into this conversation.
6. **When the code is ready**, run [pr-ship](pr-ship.prompt.md): it checks those three sections against
   the diff, then commits, pushes and opens the draft pull request with `tkNewPR`. Stop there.

## Safety contract

| Action | Agent | User |
|---|---|---|
| Read the card, the issue and the documents it names | yes | -- |
| Create or update the branch from current main | yes | -- |
| Change code, tests and documentation the card asks for | yes | -- |
| Thread commits into the card (`tkThreadHash`) | yes | -- |
| Write Summary, Described Changes and Implementation Details | yes, as the work goes | reviews |
| Push to or merge into main | never | yes |
| Ship the pull request | via `pr-ship`, which asks before it commits | confirms |
