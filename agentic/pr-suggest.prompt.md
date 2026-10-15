---
description: "The instruction the PR Comments page's Suggest a reply sends to a model with one review thread, asking for a recommendation and a draft reply as JSON."
argument-hint: "Not run by hand: the agent's suggest route fills {file_path}, {line}, {reviewer}, {comment_text} and {code_suggestion} from the thread"
agent: "ask"
---

# PR comment suggest

Used by the agent's `POST /api/pr-comments/{filename}/suggest`. The route is transport -- take one
review thread off a card, call the model, hand back a recommendation. **This file is the part that
decides**, so it can be edited, versioned and forked without touching code, and it travels to
whichever model you point at it.

The frontmatter and everything above the `---` line below are for a person and are not sent.
`{file_path}`, `{line}`, `{reviewer}`, `{comment_text}` and `{code_suggestion}` are replaced with
the thread's fields at call time (`unknown` and `none` when a field is empty). Everything below the
line is sent verbatim.

Keep the output contract exactly as stated -- the caller parses it as JSON and answers 502 rather
than guess.

---

Analyze this PR code review comment and respond with ONLY a JSON object -- no markdown fences, no explanation.

PR comment:
- File: {file_path}
- Line: {line}
- Reviewer: {reviewer}
- Comment: {comment_text}
- Code suggestion: {code_suggestion}

Rules:
- "recommendation": one of "take", "reject", or "modify"
- "confidence": one of "high", "medium", or "low"
- "draft_reply": short professional first-person reply, under 40 words

Respond with exactly: {"recommendation":"...", "confidence":"...", "draft_reply":"..."}
