/**
 * The Prompts card's rule: which prompts a Space shows, by how you work on it.
 * Someone working on a team's board does not need the orchestration prompts in
 * front of them, and someone orchestrating agents wants to see every one the
 * product offers. Each shipped prompt names the ways of working it belongs to
 * (agentic/prompts.json, `workflows`); the card's ToolKit filter shows the
 * Space's set and its info tip says how many others exist. One of yours has no
 * index entry, so it belongs to every way of working; the Space's own, read
 * from its repository, are every one too.
 *
 * The ways of working are the answers to "How do you want to work?" -- their
 * values and words are Config/settings-workflows.json's, the Space's answer is
 * /env's `howIWork`, worked out by the agent. Nothing here re-derives either.
 */
import type { EnvStatus } from "../../shell/api";
import { WORKFLOW_ENTRIES } from "../../shell/settingsWorkflows";
import type { PromptListRow, PromptWorkflow } from "./api.studio";

/** The question's answers, in the drawer's order: each value and its words. */
const ANSWERS = WORKFLOW_ENTRIES.find((e) => e.answerKey?.endsWith(".howIWork"))?.answers ?? [];

/** The ways of working, in the drawer's order. */
export const WORKFLOWS = ANSWERS.map((a) => a.value as PromptWorkflow);

/** One way of working's words, as they read inside a sentence ("with agents"). */
export function workflowLabel(workflow: PromptWorkflow): string {
  const label = ANSWERS.find((a) => a.value === workflow)?.label ?? workflow;
  return label.charAt(0).toLowerCase() + label.slice(1);
}

/**
 * The active Space's answer to How do you want to work?, as /env says it. An
 * agent that does not send one is read as the answer nobody has given: alone.
 */
export function spaceWorkflow(env: EnvStatus | undefined): PromptWorkflow {
  return env?.howIWork?.answer ?? "alone";
}

/** Whether a prompt belongs to a way of working: one of yours (no index entry) always does. */
export function belongsTo(
  row: Pick<PromptListRow, "workflows">,
  workflow: PromptWorkflow,
): boolean {
  return row.workflows.length === 0 || row.workflows.includes(workflow);
}

export interface PromptSets {
  /** ToolKit's prompts for this way of working, in the agent's order. */
  toolkit: PromptListRow[];
  /** Yours, every one. */
  yours: PromptListRow[];
  /** The active Space's own, every one -- its repository's agentic/, as the agent read it. */
  space: PromptListRow[];
  /** How many of ToolKit's are left out. */
  others: number;
  /** For each other way of working, how many of the left-out ones belong to it. */
  elsewhere: { workflow: PromptWorkflow; count: number }[];
}

export function promptSets(rows: PromptListRow[], workflow: PromptWorkflow): PromptSets {
  const toolkit = rows.filter((r) => r.group === "toolkit");
  const shown = toolkit.filter((r) => belongsTo(r, workflow));
  const hidden = toolkit.filter((r) => !belongsTo(r, workflow));
  return {
    toolkit: shown,
    yours: rows.filter((r) => r.group === "yours"),
    space: rows.filter((r) => r.group === "space"),
    others: hidden.length,
    elsewhere: WORKFLOWS.filter((w) => w !== workflow)
      .map((w) => ({ workflow: w, count: hidden.filter((r) => r.workflows.includes(w)).length }))
      .filter((e) => e.count > 0),
  };
}

/** The sentence that says ToolKit's others exist -- in the card's info tip and
 *  under the ToolKit filter's empty state -- or null when none are left out. */
export function othersLine(sets: PromptSets): string | null {
  if (sets.others === 0) return null;
  const where = sets.elsewhere.map((e) => `${workflowLabel(e.workflow)} (${e.count})`).join(", ");
  const n =
    sets.others === 1
      ? "1 more of ToolKit's prompts is"
      : `${sets.others} more of ToolKit's prompts are`;
  return `${n} for another way of working: ${where}.`;
}

/** Who sends a prompt, in a few words: by hand, or the verb or route that sends it. */
export function senderLabel(row: Pick<PromptListRow, "group" | "by_hand" | "sender">): string {
  if (row.group !== "toolkit") return "by hand";
  return row.by_hand ? "by hand" : `sent by ToolKit: ${row.sender}`;
}

/** Whose a prompt is, in the filter row's own words: ToolKit, Your hub, or the
 *  Space's name (the agent's `space` block; the row's owner, its slug, without one). */
export function ownerLabel(
  row: Pick<PromptListRow, "group" | "owner">,
  space: { name: string } | undefined,
): string {
  if (row.group === "toolkit") return "ToolKit";
  if (row.group === "yours") return "Your hub";
  return space?.name || row.owner;
}

/** Whose a prompt is, as the reading room's badge says it. */
export function groupLabel(group: PromptListRow["group"]): string {
  return group === "toolkit" ? "ToolKit's" : group === "space" ? "the Space's" : "yours";
}

/**
 * The category row's threshold: up to this many categories are filter tabs (the
 * house's FilterBadge row); past it the row is meant to become a dropdown, the
 * pattern a long single choice takes. The dropdown is not built -- the
 * vocabulary is seven -- and PromptsCard.test.tsx fails when agentic/prompts.json
 * grows past this, which is the moment to build it.
 */
export const CATEGORY_TABS_MAX = 8;

export interface CategoryTab {
  category: string;
  count: number;
}

/**
 * The category row for one source's rows: each category that has at least one
 * of them, with its count -- the vocabulary's in its order first, then any
 * outside it (a hub or Space prompt may name its own, and `uncategorized` is
 * the agent's word for none) in alphabetical order. A category with no row is
 * not a tab.
 */
export function categoryTabs(
  rows: Pick<PromptListRow, "category">[],
  vocabulary: string[],
): CategoryTab[] {
  const counts = new Map<string, number>();
  for (const r of rows) counts.set(r.category, (counts.get(r.category) ?? 0) + 1);
  const known = vocabulary.filter((c) => counts.has(c));
  const outside = [...counts.keys()].filter((c) => !vocabulary.includes(c)).sort();
  return [...known, ...outside].map((category) => ({ category, count: counts.get(category) ?? 0 }));
}
