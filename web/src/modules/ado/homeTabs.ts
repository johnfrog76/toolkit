/**
 * Which of Home's tabs each ADO card is on, for a given org status, tier and
 * set of flags -- as data, so the rule can be read, and pinned by a table
 * (homeTabs.test.ts), without rendering a card.
 *
 * The cards a tier and an org status produce are settled behaviour with a year
 * of use behind them; what is new is that each also names a
 * TAB, instead of inheriting one from where it fell in a slice of four:
 *
 *   cards    FOCUS ("local cards and prompts") -- the
 *            dual-entry list: what Azure DevOps holds and what is on this
 *            machine. The four cards the filter drawer filters.
 *   board    the swim lanes. Its one "card" is the board itself, which Home
 *            draws in place of a grid. A tab now; a toggle before.
 *   sprint   the reporting read of the sprint. Part of ADO, so it follows ADO:
 *            a `local` org has none.
 *   actions  commands that belong to no card. Provisional ("these might go
 *            away eventually").
 *
 * An archived org has one group, its retrospective, so it is all Focus -- and
 * one tab is no strip. A `local` org has the Board alone: the list is the ADO
 * worklist, and without ADO it is the same cards drawn worse (the owner's call)
 * so no Focus tab there, and connecting is what brings it.
 */
import type { HomeTabId } from "../../shell/registry";

export type HomeCardId =
  | "board"
  | "comments"
  | "prs"
  | "status"
  | "work"
  | "connect-ado"
  | "engagement-summary"
  | "work-breakdown"
  | "sprint-velocity"
  | "issue-report"
  | "milestones"
  | "deploys"
  | "dashboard"
  | "actions"
  | "review-archive"
  | "skills-snapshot"
  | "design"
  | "docs";

export interface HomePlanInput {
  spaceStatus?: "active" | "local" | "archive";
  tier?: number;
  features?: { growth?: boolean; sprintAwareness?: boolean };
  tracker?: string;
}

export function homeTabPlan(env: HomePlanInput | undefined): Record<HomeTabId, HomeCardId[]> {
  const plan: Record<HomeTabId, HomeCardId[]> = {
    cards: [],
    board: [],
    backlog: [],
    sprint: [],
    actions: [],
    design: [],
    docs: [],
  };
  const tier = env?.tier;

  if (env?.spaceStatus === "archive") {
    // The retrospective: two ADO cards, and growth's two when growth is on.
    plan.cards.push("engagement-summary", "work-breakdown");
    if (env.features?.growth) plan.cards.push("review-archive", "skills-snapshot");
    return plan;
  }

  if (env?.spaceStatus === "local") {
    // The board alone. No Focus: the list is the ADO worklist, and without ADO
    // it is the same cards drawn worse. No Sprint: Sprint follows Azure DevOps,
    // and a local org has none.
    plan.board.push("board");
    return plan;
  }

  // A GitHub space plans NO ADO furniture -- "not a bunch of ADO filters or
  // dual entry, because this is not that". Its Cards tab is the files;
  // its Issues tab is the repo's issues; its Sprint tab is the reporting read
  // in GitHub's own words, the Issue Report.
  if (env?.tracker === "github") {
    // Three tabs: Issues (the many), Board (the files), Stats (the ledger
    // counted) -- in that order; the strip's order is the
    // registry's `homeTabOrder`, this plan only says which tab holds what.
    // No Focus (the list felt inferior to the board on gh)
    // and no Actions tab on gh soil.
    plan.board.push("board");
    if (tier === 1) {
      plan.backlog.push("work");
      // Milestones beside the report: where the work is going, read
      // through the tracker like the report -- so GitHub only, Tier 1 only.
      plan.sprint.push("issue-report", "milestones", "deploys");
      // Design (Studio S2, D-S11): the repo's design/ and spec/, read through
      // the tracker like every read above -- so Tier 1, and GitHub only. No
      // flag: it is this core's tab on a GitHub Space, not a module's.
      plan.design.push("design");
      // Docs (D-S12): the repo's README and docs/, through the same
      // seam and the same gate as Design -- so the same tier and tracker.
      plan.docs.push("docs");
    }
    return plan;
  }

  // Active. PR Comments reads from the file cache: Tier 1 and Tier 2.
  if (tier !== undefined && tier <= 2) plan.cards.push("comments");
  if (tier === 1) plan.cards.push("prs");
  plan.cards.push("status");
  if (tier === 1) plan.cards.push("work");
  // Env not loaded yet reads as the list, nothing guessed; a known active
  // space has the Board beside its Focus.
  if (env) plan.board.push("board");
  if (tier === 1) plan.sprint.push("engagement-summary", "work-breakdown");
  if (env?.features?.sprintAwareness) plan.sprint.push("sprint-velocity");
  if (tier === 1) plan.sprint.push("dashboard");
  if (tier === 1) plan.actions.push("actions");
  return plan;
}

/**
 * The drawer's filters (filter text, repo, state, type) only reach a card
 * that reads them as props -- PR Comments, My Pull Requests, Active Prompts
 * and My Work (`homeTabs()` in index.tsx). Every other card on the plan takes
 * none, so a tab whose cards are all outside this set is a tab the drawer
 * cannot filter.
 */
const FILTERABLE_CARD_IDS: ReadonlySet<HomeCardId> = new Set<HomeCardId>([
  "board",
  "comments",
  "prs",
  "status",
  "work",
]);

/**
 * The drawer's SECTIONS, per tab. The owner's rule: "we support ToolKit filters
 * always in the drawer, or we support ADO linked Space in the drawer ... we
 * open to other opportunities making the drawer useful for other things like
 * Stats or Design perhaps in the future." The rule is the drawer's own, one
 * level down: a section appears on a tab only when it reaches a card on that
 * tab -- the same rule that decides whether the drawer shows at all.
 *
 *   search  the text box. On a tab with any filterable card.
 *   cards   ToolKit's own card filters -- type, tracker link, lane. Wherever
 *           cards are drawn (Focus, the Board), on every tracker.
 *   ado     the org's projects (the repo row). An Azure DevOps Space's; it
 *           matches a card's ADO link, so it is never drawn on GitHub soil.
 *   issues  the GitHub issue filters -- state, assignee, worked by, and the
 *           labels (kind, sev, milestone). The Issues tab of a GitHub Space.
 *
 *   kind    Design's kind -- design note | spec. The Design tab.
 *   folder  Docs' folder -- the folders the tree has. The Docs tab.
 *
 * Stats holds nothing a section would narrow -- a reader of Stats wants the
 * whole picture -- so its slot is the strip's disabled control.
 * A tab's sections are what the drawer draws; no tab has a control of its own.
 */
export type DrawerSection = "search" | "cards" | "ado" | "issues" | "kind" | "folder";

const CARD_HOLDING_IDS: ReadonlySet<HomeCardId> = new Set<HomeCardId>([
  "board",
  "comments",
  "prs",
  "status",
]);

export function drawerSections(env: HomePlanInput | undefined, tab: HomeTabId): DrawerSection[] {
  const ids = homeTabPlan(env)[tab];
  // Design and Docs filter the lists they hold: text, then one axis.
  if (ids.includes("design")) return ["search", "kind"];
  if (ids.includes("docs")) return ["search", "folder"];
  if (!ids.some((id) => FILTERABLE_CARD_IDS.has(id))) return [];
  const github = env?.tracker === "github";
  const sections: DrawerSection[] = ["search"];
  if (ids.some((id) => CARD_HOLDING_IDS.has(id))) {
    sections.push("cards");
    if (!github) sections.push("ado");
  }
  if (ids.includes("work")) {
    // On Azure DevOps My Work sits beside the cards and answers the same
    // repo and lane rows; on GitHub the Issues list has filters of its own.
    if (github) sections.push("issues");
    else if (!sections.includes("ado")) sections.push("ado");
  }
  return sections;
}

/** Whether the given tab, under this plan, holds a card the drawer reaches. */
export function tabHasFilterableCard(env: HomePlanInput | undefined, tab: HomeTabId): boolean {
  return drawerSections(env, tab).length > 0;
}
