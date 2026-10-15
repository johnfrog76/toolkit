/**
 * Which tab each Home card is on, as a TABLE: every org status and tier the
 * rule distinguishes, with the flags that change it, one row each. The cards a
 * row produces are the ones Home drew before the tabs.
 * What the table adds is where each one goes.
 */
import { drawerSections, homeTabPlan, tabHasFilterableCard } from "./homeTabs";
import type { DrawerSection, HomePlanInput } from "./homeTabs";
import type { HomeTabId } from "../../shell/registry";

const rows: [string, HomePlanInput | undefined, ReturnType<typeof homeTabPlan>][] = [
  [
    "a GitHub space, Tier 1 -- Issues, Board, Stats, Design, Docs; no Focus, no ADO furniture, no Actions",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    {
      cards: [],
      board: ["board"],
      backlog: ["work"],
      sprint: ["issue-report", "milestones", "deploys"],
      actions: [],
      design: ["design"],
      docs: ["docs"],
    },
  ],
  [
    "a GitHub space, Tier 2 (gh not signed in) -- the Board alone",
    { spaceStatus: "active", tier: 2, tracker: "github" },
    { cards: [], board: ["board"], backlog: [], sprint: [], actions: [], design: [], docs: [] },
  ],
  [
    "active, Tier 1, sprint awareness on -- the full Home: Focus | Board | Sprint | Actions",
    { spaceStatus: "active", tier: 1, features: { sprintAwareness: true } },
    {
      cards: ["comments", "prs", "status", "work"],
      board: ["board"],
      backlog: [],
      sprint: ["engagement-summary", "work-breakdown", "sprint-velocity", "dashboard"],
      actions: ["actions"],
      design: [],
      docs: [],
    },
  ],
  [
    "active, Tier 1, sprint awareness off -- Sprint has three, nothing moves tab",
    { spaceStatus: "active", tier: 1, features: {} },
    {
      cards: ["comments", "prs", "status", "work"],
      board: ["board"],
      backlog: [],
      sprint: ["engagement-summary", "work-breakdown", "dashboard"],
      actions: ["actions"],
      design: [],
      docs: [],
    },
  ],
  [
    "active, Tier 2 (Azure DevOps unreachable) -- no Actions",
    { spaceStatus: "active", tier: 2, features: { sprintAwareness: true } },
    {
      cards: ["comments", "status"],
      board: ["board"],
      backlog: [],
      sprint: ["sprint-velocity"],
      actions: [],
      design: [],
      docs: [],
    },
  ],
  [
    "active, Tier 2, sprint awareness off -- Focus and Board",
    { spaceStatus: "active", tier: 2, features: {} },
    {
      cards: ["comments", "status"],
      board: ["board"],
      backlog: [],
      sprint: [],
      actions: [],
      design: [],
      docs: [],
    },
  ],
  [
    "active, Tier 3 -- Active Cards and the Board",
    { spaceStatus: "active", tier: 3, features: {} },
    {
      cards: ["status"],
      board: ["board"],
      backlog: [],
      sprint: [],
      actions: [],
      design: [],
      docs: [],
    },
  ],
  [
    "local -- the Board alone: no Focus (the list is the ADO worklist), no Sprint, even with sprint awareness",
    { spaceStatus: "local", tier: 3, features: { sprintAwareness: true } },
    { cards: [], board: ["board"], backlog: [], sprint: [], actions: [], design: [], docs: [] },
  ],
  [
    "archive, growth on -- the retrospective, all Focus, no board: nothing is in flight",
    { spaceStatus: "archive", tier: 1, features: { growth: true, sprintAwareness: true } },
    {
      cards: ["engagement-summary", "work-breakdown", "review-archive", "skills-snapshot"],
      board: [],
      backlog: [],
      sprint: [],
      actions: [],
      design: [],
      docs: [],
    },
  ],
  [
    "archive, growth off -- the two ADO cards",
    { spaceStatus: "archive", tier: 1, features: {} },
    {
      cards: ["engagement-summary", "work-breakdown"],
      board: [],
      backlog: [],
      sprint: [],
      actions: [],
      design: [],
      docs: [],
    },
  ],
  [
    "env not loaded yet -- Active Cards, nothing guessed, no board",
    undefined,
    { cards: ["status"], board: [], backlog: [], sprint: [], actions: [], design: [], docs: [] },
  ],
];

describe("homeTabPlan: which tab each Home card is on", () => {
  it.each(rows)("%s", (_why, env, want) => {
    expect(homeTabPlan(env)).toEqual(want);
  });

  it("puts no card on two tabs", () => {
    for (const [, env] of rows) {
      const plan = homeTabPlan(env);
      const all = [...plan.cards, ...plan.sprint, ...plan.actions];
      expect(new Set(all).size).toBe(all.length);
    }
  });
});

// The drawer's filters
// reach PR Comments, My Pull Requests, Active Prompts and My Work only, so a
// tab whose plan holds none of those is a tab where the drawer changes
// nothing and must not show.
const filterableRows: [string, HomePlanInput | undefined, HomeTabId, boolean][] = [
  [
    "ADO active, Tier 1: Cards holds all four filterable cards",
    { spaceStatus: "active", tier: 1, features: { sprintAwareness: true } },
    "cards",
    true,
  ],
  [
    "ADO active, Tier 1: Sprint holds none of them",
    { spaceStatus: "active", tier: 1, features: { sprintAwareness: true } },
    "sprint",
    false,
  ],
  [
    "ADO active, Tier 1: Actions holds none of them",
    { spaceStatus: "active", tier: 1, features: { sprintAwareness: true } },
    "actions",
    false,
  ],
  [
    "GitHub space, Tier 1: the Board tab holds the board, which the drawer reaches",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    "board",
    true,
  ],
  [
    "ADO active, Tier 1: the Board tab holds the board, which the drawer reaches",
    { spaceStatus: "active", tier: 1, features: {} },
    "board",
    true,
  ],
  [
    "GitHub space, Tier 1: Backlog holds My Work",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    "backlog",
    true,
  ],
  [
    "GitHub space, Tier 1: Stats (Sprint) holds neither",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    "sprint",
    false,
  ],
  [
    "GitHub space, Tier 1: Design holds the document list, which the drawer's own sections reach but no card filter does",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    "design",
    true,
  ],
  [
    "GitHub space, Tier 1: Docs holds the README and the docs/ tree, which the drawer's own sections reach but no card filter does",
    { spaceStatus: "active", tier: 1, tracker: "github" },
    "docs",
    true,
  ],
  [
    "archive: Cards holds only the retrospective's own cards",
    { spaceStatus: "archive", tier: 1, features: { growth: true } },
    "cards",
    false,
  ],
];

describe("tabHasFilterableCard: whether the drawer's filters reach anything on this tab", () => {
  it.each(filterableRows)("%s", (_why, env, tab, want) => {
    expect(tabHasFilterableCard(env, tab)).toBe(want);
  });
});

// The drawer's SECTIONS, per tab -- ToolKit's card filters wherever cards
// are drawn, the ADO repo row on an Azure DevOps Space, the GitHub issue
// filters on a GitHub Space's Issues tab. None anywhere a section reaches no
// card (Stats, Design, Sprint, Actions): no drawer there.
const ADO1 = { spaceStatus: "active" as const, tier: 1, features: {} };
const GH1 = { spaceStatus: "active" as const, tier: 1, tracker: "github" };
const sectionRows: [string, HomePlanInput | undefined, HomeTabId, DrawerSection[]][] = [
  [
    "ADO Focus: search, the card filters, the repo row -- as it always was",
    ADO1,
    "cards",
    ["search", "cards", "ado"],
  ],
  ["ADO Board: the same", ADO1, "board", ["search", "cards", "ado"]],
  ["ADO Sprint: none", ADO1, "sprint", []],
  [
    "GitHub Issues: search and the issue filters, no card rows",
    GH1,
    "backlog",
    ["search", "issues"],
  ],
  [
    "GitHub Board: search and the card filters -- no ADO repo row on gh soil",
    GH1,
    "board",
    ["search", "cards"],
  ],
  ["GitHub Stats stays unfiltered by design: the slot is the disabled control", GH1, "sprint", []],
  ["GitHub Design: search over the titles and the kind", GH1, "design", ["search", "kind"]],
  [
    "GitHub Docs: search over titles and paths and the folder, for the folded tree",
    GH1,
    "docs",
    ["search", "folder"],
  ],
  [
    "local Board: search and the card filters",
    { spaceStatus: "local", tier: 3 },
    "board",
    ["search", "cards", "ado"],
  ],
];

describe("drawerSections: which filters the drawer holds on this tab", () => {
  it.each(sectionRows)("%s", (_why, env, tab, want) => {
    expect(drawerSections(env, tab)).toEqual(want);
  });
});
