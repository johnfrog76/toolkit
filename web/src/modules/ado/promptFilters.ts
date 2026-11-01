import type { PromptInfo } from "./api.ado";

// Which cards are SHOWN, decided once. The list (PromptStatus) and the board
// (Board) are two pictures of the same cards under the same filters; if each
// kept its own predicates, the day they disagreed the board would be showing a
// different set of cards than the list beside it and nobody could say which was
// right. They were inline in PromptStatus.tsx until the board needed them too.

export interface PromptFilter {
  /** A repo tag from the filter drawer, or null. Matched against the ADO link; a card with no ADO link is never hidden by it. */
  activeRepo: string | null;
  /** A state name, or "All". */
  status: string;
  /** Free text: file, title, the ADO link -- or an exact card id. Several
   *  words match in any order. */
  text: string;
  /** A sprint name, or "All". The board's own filter. */
  sprint?: string;
  /** A milestone, WHOLE (the card model's `milestone`), or "All". The board's own filter. */
  milestone?: string;
  /** One tag (the card model's `tags`, compared ignoring case), or "All". The board's own filter. */
  tag?: string;
  /** A card type as the heading names it ("Bug", "User Story"), UNTYPED for a
   *  card whose heading names no configured type, or "All". */
  type?: string;
  /** Linked, Custom, or "All" -- the filter drawer's linkedness row. */
  link?: string;
}

/** Does this card have a tracker's ledger behind it? The question a MIXED
 *  Space raises. The words are the drawer's; the fact is the card model's
 *  `linked`, which the agent derives from the one tracker-link rule -- an
 *  `https://` `**ADO Link:**`, while a `(not linked ...)` placeholder is custom
 *  (agent/core/parsers.py). Nothing here reads the link itself, and the filter
 *  never cares WHICH tracker: that is the badge's question. */
export type LinkFilter = "All" | "Linked" | "Custom";

/** The bucket for a card whose heading names no configured type. It is a
 *  badge of its own on the type row, and it is inside "All": a type filter
 *  shows and hides, and only an active badge ever hides a card. */
export const UNTYPED = "Untyped";

/** A card that names no Azure DevOps repository -- no link at all, or a link to
 *  another tracker -- belongs to none of the repo row's projects, and choosing
 *  a project is no reason to hide it. It stays in view under every
 *  repo; only a card whose ADO link names a DIFFERENT project is filtered out.
 *  (A `Repo:` line to place such a card would be a card-contract change,
 *  docs/hub/cards.md, and is not built.) */
function matchesRepo(p: PromptInfo, repo: string): boolean {
  if (!p.ado_url || p.tracker === "github") return true;
  return p.ado_url.includes(repo) || p.ado_url.includes(encodeURIComponent(repo));
}

// The one box is dual entry (the owner: "the card id filter is absolutely needed
// for list because it functions as dual entry"): an exact id first, then a
// substring of the file, the title or the link -- and the
// words typed in any order, so `angular signals` finds "Signals in Angular".
// No typo tolerance: on a 250-file corpus a loose match mostly produces false
// hits, and a filter that shows the wrong card is worse than one that shows
// none.
function matchesText(p: PromptInfo, text: string): boolean {
  const typed = text.trim();
  const needle = typed.toLowerCase();
  if (!needle) return true;
  if ((p.id ?? "").toLowerCase() === needle) return true;
  const haystack = `${p.file} ${p.title}`.toLowerCase();
  if (haystack.includes(needle)) return true;
  if (p.ado_url && p.ado_url.includes(typed)) return true;
  const words = needle.split(/\s+/).filter(Boolean);
  return words.length > 1 && words.every((w) => haystack.includes(w));
}

function matchesType(p: PromptInfo, type: string): boolean {
  return type === UNTYPED ? p.type === null : p.type === type;
}

export function filterPrompts(prompts: PromptInfo[], f: PromptFilter): PromptInfo[] {
  const byRepo = f.activeRepo ? prompts.filter((p) => matchesRepo(p, f.activeRepo!)) : prompts;
  const byStatus = f.status === "All" ? byRepo : byRepo.filter((p) => p.status === f.status);
  const bySprint =
    !f.sprint || f.sprint === "All" ? byStatus : byStatus.filter((p) => p.sprint === f.sprint);
  const byMilestone =
    !f.milestone || f.milestone === "All"
      ? bySprint
      : bySprint.filter((p) => (p.milestone ?? "") === f.milestone);
  const byTag =
    !f.tag || f.tag === "All"
      ? byMilestone
      : byMilestone.filter((p) =>
          (p.tags ?? []).some((t) => t.toLowerCase() === f.tag!.toLowerCase()),
        );
  const byType = !f.type || f.type === "All" ? byTag : byTag.filter((p) => matchesType(p, f.type!));
  const byLink =
    !f.link || f.link === "All"
      ? byType
      : byType.filter((p) => (f.link === "Linked" ? p.linked : !p.linked));
  return f.text ? byLink.filter((p) => matchesText(p, f.text)) : byLink;
}

/** One badge per type on the filter row, COUNTED FROM THE CARDS -- never from
 *  config, which is what the repo row's counts do and why they never move. The
 *  configured types come first in config's order, then any type a card names
 *  that config does not (a team's old vocabulary), then UNTYPED when a card has
 *  no type. A configured type with no card is listed at 0, so the row is the
 *  same shape from one week to the next. */
export function typeRowOf(
  prompts: PromptInfo[],
  configured: string[],
): Array<{ label: string; count: number }> {
  const counts = new Map<string, number>();
  let untyped = 0;
  for (const p of prompts) {
    if (p.type === null) untyped++;
    else counts.set(p.type, (counts.get(p.type) ?? 0) + 1);
  }
  const row = configured.map((label) => ({ label, count: counts.get(label) ?? 0 }));
  const extra = [...counts.keys()].filter((t) => !configured.includes(t)).sort();
  for (const label of extra) row.push({ label, count: counts.get(label)! });
  if (untyped > 0) row.push({ label: UNTYPED, count: untyped });
  return row;
}

/** The linkedness row's counts, COUNTED FROM THE CARDS like the type row. */
export function linkRowOf(prompts: PromptInfo[]): { linked: number; custom: number } {
  const linked = prompts.filter((p) => p.linked).length;
  return { linked, custom: prompts.length - linked };
}

/** Whether the drawer draws the linkedness row. Only a MIXED Space asks the
 *  question. Where every card is custom (a local Space, or a tracker Space
 *  nobody has picked work up in yet) or every card is linked, the row would be
 *  one badge equal to All and one at 0 -- a control whose only power is to
 *  hide everything. One exception keeps the way out: while a linkedness
 *  filter is ACTIVE the row stays, so a Space that stopped being mixed under
 *  it (its last custom card archived) can still be set back to All. */
export function showLinkRow(prompts: PromptInfo[], active: string): boolean {
  if (active !== "All") return true;
  const { linked, custom } = linkRowOf(prompts);
  return linked > 0 && custom > 0;
}

/** The sprints these cards name, for a filter's options. "--" and "(not linked)"
 *  are what a card with no sprint reads as, and are not sprints. */
export function sprintsOf(prompts: PromptInfo[]): string[] {
  const names = new Set<string>();
  for (const p of prompts) {
    if (p.sprint && p.sprint !== "--" && !p.sprint.startsWith("(")) names.add(p.sprint);
  }
  return [...names].sort();
}

/** The milestones these cards name, whole, for the board's filter -- the card
 *  model's `milestone`: its own line, else an old card's sprint line (one rule,
 *  agent/core/parsers.py card_milestone). "" is no milestone, and not an option. */
export function milestonesOf(prompts: PromptInfo[]): string[] {
  const names = new Set<string>();
  for (const p of prompts) if (p.milestone) names.add(p.milestone);
  return [...names].sort();
}

/** The tags these cards carry, for the board's filter: one option per tag, the
 *  first spelling met kept when two cards spell it in different cases. */
export function tagsOf(prompts: PromptInfo[]): string[] {
  const seen = new Map<string, string>();
  for (const p of prompts)
    for (const t of p.tags ?? []) if (!seen.has(t.toLowerCase())) seen.set(t.toLowerCase(), t);
  return [...seen.values()].sort((a, b) => a.localeCompare(b));
}
