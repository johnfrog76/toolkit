# agentic/

These are prompts for an AI coding assistant, written to be handed to it as they are. The ToolKit's
commands move a work item's card between states; these decide **what to do** at each one -- triage a
round of review comments, ship a pull request, file a bug -- and they call the commands to do the
writing. They are plain Markdown with no runtime of their own: open one in your assistant (or point
your editor's prompt-file feature at this folder), give it the argument its front matter asks for,
and it works against your hub through the same `tk*` verbs you type. Two of them, `pr-review` and
`pr-suggest`, are not run by hand at all: they are the instructions the CLI and the agent send to a
model.

## Why these, and why they read the way they do

They were kept on evidence, not on taste: each one has been used for real work, and a prompt is
added here only after it has. That is also why they look over-specified. A
restatement, a Safety Contract (an explicit table of what the assistant may do and what waits for
you) or a "stop and ask" is there because the step goes wrong without it. Where a tool still has a
gap a prompt has to work around, the prompt says what to do in one line and links to
[Known gaps](../docs/KNOWN-GAPS.md); a gap that is fixed leaves the prompt.

**The card workflow** -- moving one card from created to merged:

| Prompt | What it carries |
|---|---|
| `ado-comments` | Safety Contract. Two-pass PR comment triage. |
| `pr-ship` | Safety Contract. Stage 1: context check, commit, draft PR. |
| `pr-publish` | Safety Contract. Stage 2: draft → ready, comms. |
| `new-bug` | Creating a Bug: the item with `tkNewItem`, the card with `tkNewPrompt`, the repro filled in. |
| `new-user-story` | Creating a User Story the same way, with scope, implementation details and acceptance criteria. |

`new-bug` and `new-user-story` are the front door of the workflow the other three continue, and
they drive the two commands that create an item and its card rather than writing a card by hand.

**The prompts the tools send** -- frontmatter and prose for a person above a `---` line, the
instruction below it; only the instruction is sent:

| Prompt | What it carries |
|---|---|
| `pr-review` | The review prompt behind `tkAddPRReview`. Not a workflow; the thing the command sends. |
| `pr-suggest` | The prompt behind the agent's `POST /api/pr-comments/{filename}/suggest`, which the PR Comments page's **Suggest a reply** calls. The model is `ai.model` in config. |

**The tracker** -- `new-issue`, the front end of a GitHub issue list: the triage rule (an issue
before a fix) is only real if filing one is a single command. An issue filed into a PUBLIC
repository is written for a stranger, in a different shape ("On stage: a public repository").

**Module content** -- they come with their add-on, the way a script or a template does, and are
listed only while it is on:

| Prompt | Add-on | What it drives |
|---|---|---|
| `generate-review` | growth | Turn a `tkNewWorkReview` scaffold into a shareable work review |
| `growth-create-training` | growth | Create a training with `tkNewGrowth` and fill it in |
| `growth-create-presentation` | growth | The same for a talk, demo, brown bag or workshop |
| `manager1on1` | communication | Work a 1:1 session file end to end. `tkMeetingAgenda -Plan` and `-Retro` point at it |

## The shape of a prompt

Every prompt here opens the same way, and `Tests/test_agentic_index.py` holds all of them to it:

1. **Frontmatter** on the first line, with three keys: `description` -- one sentence, written to
   you, which the Studio's Prompts card shows as the prompt's purpose; `argument-hint` -- what to
   give it; and `agent` -- `agent` for a prompt that runs commands, `ask` for the two the tools
   send. `tools` is optional, for a prompt that names the tools it needs.
2. The **prefix note**, when the prompt types a `tk` command.
3. One **`# ` title**, which the card shows as the prompt's title.

**One record for every prompt.** The Studio's Prompts card draws every row the same way, whether the
prompt is ToolKit's, your hub's or the Space's -- four fields and nothing else:

| Field | Where it comes from |
|---|---|
| **title** | the frontmatter's `title`, else the one `# ` heading, else the file name |
| **purpose** | the frontmatter's `description` -- one sentence |
| **owner** | where the file lives: ToolKit (this folder), yours (your hub's or `agenticExtensionPath`), or the Space (its repository's `agentic/`). Worked out by the agent, never written in a file |
| **category** | a shipped prompt's is its entry in `prompts.json`; any other prompt's is its frontmatter `category` line. A prompt with none reads `uncategorized` |

The way of working, who sends it, the add-on and what it drives are detail: the reading room shows them,
the row does not.

**The categories** are a small fixed vocabulary, `categories` in `prompts.json`, and every shipped entry
carries one of them. A prompt of yours may name any category; one of these keeps it beside the shipped
ones it belongs with:

| Category | A prompt that... |
|---|---|
| `ship` | takes work from committed code to a pull request and out |
| `review` | reads, answers or writes a code review |
| `tracker` | files or shapes a work item or an issue |
| `growth` | puts something you learned or delivered on the record |
| `meetings` | prepares or closes a meeting |
| `rituals` | runs a team's ritual -- a standup, a triage |
| `design` | works a design note or a spec |

The shipped ones carry theirs in the index, not in their frontmatter: `pr-ship` and `pr-publish`
are `ship`; `ado-comments`, `pr-review` and `pr-suggest` are `review`; `new-bug`, `new-user-story`
and `new-issue` are `tracker`; `generate-review`, `growth-create-training` and
`growth-create-presentation` are `growth`; `manager1on1` is `meetings`.

Below the title, a prompt you open by hand speaks to the assistant as "you" and to you as "the
user". The two the tools send speak about the tool in the third person above the line, and the
instruction below it is the model's. None of them carries its own history: why a rule exists is
said as the rule, and the story of how it came about is the commit's.

## Which way of working each prompt belongs to

`prompts.json` beside the prompts is the index: for each one, the **workflows** it belongs to --
`alone` (by myself), `team` (on a team in Azure), `agents` (with agents), the three answers to
the question Settings asks of each Space, "How do you want to work in `<Space>`?" -- who **sends** it (`by hand` for a prompt you open in your assistant,
else the verb or route that sends it to a model), its **module**, what it **drives** and its
**category** (above). The
Studio's Prompts card reads it to show a Space the prompts for the way you work there, and
`Tests/test_agentic_index.py` holds it to the folder: every prompt has an entry, every entry a
prompt, every workflow one of the three, every category one of the vocabulary's.

A prompt in your own folder (`agenticExtensionPath`, below), or in your hub's `agentic/`, is yours and
needs no entry -- the card lists it under **Your hub** for every way of working, and a `category: <name>`
line in its frontmatter is its category; the index describes the shipped set. Each prompt opens in a reading room at `/studio/prompts/<name>`. The card's **Copy
reference** puts an `@` reference to the file on the clipboard for an assistant that can read your files;
**Copy prompt**, in the row's menu, puts the whole file there for a chat that cannot.

## Conventions

Commands appear with the default `tk` prefix; substitute yours if you changed it. Every backticked
`tk` command in these files is a real one, and the CLI's own tests check that. Nothing here may link
outside this package -- the Portability suite fails the build if it does, because a link that
points outside it arrives broken.

## Tuning a prompt for one machine

The shipped prompts stay generic. To run a tuned copy here, name a folder in `config.local.json` --
`tkConfig -Set agenticExtensionPath=<folder>` (absolute, or relative to the hub) -- and put your copy
in it under the same file name. `Scripts/Resolve-AgenticPrompt.ps1` is the one lookup: the folder's
copy when it has the file, the package's otherwise, and each verb prints which copy it chose.
