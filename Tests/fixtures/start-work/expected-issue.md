# Start work: Issue #41 -- Triage shows who holds each item

## How we work in Widgets (hub.json: spaces[widgets].howIWork = agents)
You work with agents here: the repository's GitHub issues are the backlog, a worker label on an issue (its size) says which agent takes it, and the item below is the record -- write what you find, what you decide and each commit into it as you go.

## The work: Issue #41 (https://github.com/acme/widgets/issues/41)
# Issue #41: Triage shows who holds each item

Tags: sonnet; sev2
**Sprint:** Team Agile V2

## Problem

Triage does not say who has an item.

## The prompt (agentic/build.prompt.md)
---
description: "Build the card you were handed: read it, do the work, thread the commits."
argument-hint: "The card"
agent: "agent"
---

# Build

1. Read the card under "The work".
2. Make the change on the card's branch, and thread each commit with `tkThreadHash`.
