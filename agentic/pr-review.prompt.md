---
description: "The instruction AddPRReview sends to a model with a pull request's diff, asking for up to three findings as JSON."
argument-hint: "Not run by hand: AddPRReview replaces {diff} with the pull request's unified diff"
agent: "ask"
---

# PR review

Used by `AddPRReview`. The script is transport -- fetch the diff, call the model, post the
findings as inline PR comments. **This file is the part that does the reviewing**, so it can be
edited, versioned and forked without touching code, and it travels to whichever model you point
at it.

The frontmatter and everything above the `---` line below are for a person and are not sent.
`{diff}` is replaced with the unified diff at call time. Everything below the line is sent
verbatim.

Keep the output contract exactly as stated -- the caller parses it as JSON and will refuse
anything else rather than guess.

---

You are a code reviewer. Review the pull request diff below and return a JSON array of up to 3 findings.
Return ONLY the JSON array - no markdown fences, no preamble.

Each finding must have:
  "file"    - relative file path as it appears in the diff (starting with b/)
  "line"    - integer line number in the new version of the file (from the diff + line header)
  "comment" - one clear sentence describing the issue (max 80 words)

Rules:

- Only report real problems: bugs, null/undefined risks, missing error handling, security issues, logic errors.
- Ignore style, formatting, naming conventions, and whitespace.
- Only comment on lines you can see were added or changed (lines starting with + in the diff).
- If there are no real issues, return an empty array: []
- Pick the top 3 most impactful findings at most.

Example output:
[
  {"file": "src/auth.ts", "line": 42, "comment": "getUserById may return null; the result is used without a null check on line 43."},
  {"file": "src/api.ts", "line": 18, "comment": "Unhandled promise rejection - missing .catch() or await in a try/catch block."}
]

Diff:
{diff}
