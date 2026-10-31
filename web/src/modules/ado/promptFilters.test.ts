import {
  UNTYPED,
  filterPrompts,
  linkRowOf,
  milestonesOf,
  showLinkRow,
  sprintsOf,
  tagsOf,
  typeRowOf,
} from "./promptFilters";
import type { PromptInfo } from "./api.ado";

function card(over: Partial<PromptInfo>): PromptInfo {
  return {
    file: "x.prompt.md",
    id: null,
    type: null,
    name: "",
    linked: false,
    billable: true,
    title: "",
    sprint: "--",
    progress: "--",
    checked: 0,
    total: 0,
    modified: "",
    ado_url: null,
    pr_url: null,
    status: "Active",
    ...over,
  };
}

const cards = [
  card({
    file: "141-search.prompt.md",
    id: "141",
    title: "Bug 141: Search",
    status: "Active",
    sprint: "Sprint 8",
    ado_url: "https://dev.azure.com/o/RecipesApp/_workitems/edit/141",
    linked: true,
    billable: true,
    type: "Bug",
  }),
  card({
    file: "Spike-K7M2-wallet.prompt.md",
    id: "K7M2",
    title: "Spike K7M2: Wallet ticket",
    status: "In Progress",
    sprint: "POC wk 38",
    type: "Spike",
  }),
  card({
    file: "US-Q4TN-cashier.prompt.md",
    id: "Q4TN",
    title: "User Story Q4TN: Cashier screen",
    status: "Code Review",
    sprint: "POC wk 38",
    type: "User Story",
  }),
  // A card whose heading names no configured type -- "Learn all about Signals
  // in Angular" made by hand, or a team's old vocabulary. It has to be findable.
  card({
    file: "learn-signals.prompt.md",
    id: null,
    title: "Learn all about Signals in Angular",
    status: "Active",
    type: null,
  }),
];
const all = { activeRepo: null, status: "All", text: "" };

describe("filterPrompts", () => {
  it("with no filter, shows every card", () => {
    expect(filterPrompts(cards, all)).toHaveLength(4);
  });

  it("filters by state, by sprint and by text", () => {
    expect(filterPrompts(cards, { ...all, status: "In Progress" }).map((c) => c.id)).toEqual([
      "K7M2",
    ]);
    expect(filterPrompts(cards, { ...all, sprint: "POC wk 38" }).map((c) => c.id)).toEqual([
      "K7M2",
      "Q4TN",
    ]);
    expect(filterPrompts(cards, { ...all, text: "wallet" }).map((c) => c.id)).toEqual(["K7M2"]);
  });

  it("finds a card by its exact id, in any case", () => {
    expect(filterPrompts(cards, { ...all, text: "k7m2" }).map((c) => c.id)).toEqual(["K7M2"]);
  });

  // "Signals in Angular" is the title; a person types "angular signals". The
  // words match in any order, and one word still matches as a substring.
  it("matches the words typed, in any order", () => {
    const titles = (text: string) => filterPrompts(cards, { ...all, text }).map((c) => c.title);
    expect(titles("angular signals")).toEqual(["Learn all about Signals in Angular"]);
    expect(titles("signals angular")).toEqual(["Learn all about Signals in Angular"]);
    expect(titles("Signals")).toEqual(["Learn all about Signals in Angular"]);
    expect(titles("  signals   angular  ")).toEqual(["Learn all about Signals in Angular"]);
    // Every word has to be there: no typo tolerance, no "any word".
    expect(titles("angular signls")).toEqual([]);
    expect(titles("wallet angular")).toEqual([]);
  });

  it("filters by type, and an untyped card is its own bucket inside All", () => {
    const ids = (type: string) => filterPrompts(cards, { ...all, type }).map((c) => c.id);
    expect(ids("Bug")).toEqual(["141"]);
    expect(ids("User Story")).toEqual(["Q4TN"]);
    expect(ids(UNTYPED)).toEqual([null]);
    expect(ids("All")).toHaveLength(4);
    expect(filterPrompts(cards, all)).toHaveLength(4);
  });

  // A card with no ADO repository is never hidden by the repo filter.
  it("keeps a card with no ADO link under a repo filter", () => {
    const r = filterPrompts(cards, { ...all, activeRepo: "RecipesApp" });
    expect(r.map((c) => c.id)).toEqual(["141", "K7M2", "Q4TN", null]);
  });

  it("keeps a GitHub-linked card under a repo filter, and filters an ADO card of another project", () => {
    const gh = card({
      file: "GH-9-x.prompt.md",
      id: "9",
      ado_url: "https://github.com/o/other/issues/9",
      linked: true,
      tracker: "github",
    });
    const elsewhere = card({
      file: "7-y.prompt.md",
      id: "7",
      ado_url: "https://dev.azure.com/o/Wallet/_workitems/edit/7",
      linked: true,
      tracker: "ado",
    });
    const ids = filterPrompts([...cards, gh, elsewhere], { ...all, activeRepo: "RecipesApp" }).map(
      (c) => c.id,
    );
    expect(ids).toContain("9");
    expect(ids).not.toContain("7");
    expect(ids).toContain("141");
  });
});

describe("typeRowOf", () => {
  it("counts the cards on screen, in config's order, then what config does not name, then Untyped", () => {
    expect(typeRowOf(cards, ["Bug", "User Story", "Task"])).toEqual([
      { label: "Bug", count: 1 },
      { label: "User Story", count: 1 },
      { label: "Task", count: 0 },
      { label: "Spike", count: 1 },
      { label: UNTYPED, count: 1 },
    ]);
  });

  it("lists no Untyped badge when every card has a type", () => {
    const typed = cards.filter((c) => c.type !== null);
    expect(typeRowOf(typed, ["Bug"]).map((r) => r.label)).toEqual(["Bug", "Spike", "User Story"]);
  });
});

describe("sprintsOf", () => {
  it("lists the sprints cards name, and not the words for 'none'", () => {
    const withNone = [...cards, card({ sprint: "(not linked)" }), card({ sprint: "--" })];
    expect(sprintsOf(withNone)).toEqual(["POC wk 38", "Sprint 8"]);
  });
});

// Linked or custom, as a table. The fact is the card model's `linked` --
// the agent's one tracker-link rule -- and the filter never asks WHICH tracker,
// so a GitHub-born card is Linked exactly as an ADO-born one is.
describe("the linkedness filter", () => {
  const gh = card({
    file: "Task54-badge.prompt.md",
    id: "54",
    ado_url: "https://github.com/johnfrog76/toolkit/issues/54",
    linked: true,
  });
  const mixed = [...cards, gh];
  const custom = cards.filter((c) => !c.linked);
  const linked = [cards[0], gh];
  const ids = (link: string) => filterPrompts(mixed, { ...all, link }).map((c) => c.id ?? c.file);

  it.each([
    ["All", ["141", "K7M2", "Q4TN", "learn-signals.prompt.md", "54"]],
    ["Linked", ["141", "54"]],
    ["Custom", ["K7M2", "Q4TN", "learn-signals.prompt.md"]],
  ])("%s shows %j", (link, expected) => {
    expect(ids(link)).toEqual(expected);
  });

  it("with no link filter given, hides nothing", () => {
    expect(filterPrompts(mixed, all)).toHaveLength(5);
  });

  it("composes with the other filters", () => {
    const r = filterPrompts(mixed, { ...all, link: "Custom", sprint: "POC wk 38", text: "wallet" });
    expect(r.map((c) => c.id)).toEqual(["K7M2"]);
  });

  it("counts the row from the cards", () => {
    expect(linkRowOf(mixed)).toEqual({ linked: 2, custom: 3 });
    expect(linkRowOf([])).toEqual({ linked: 0, custom: 0 });
  });

  // The row is for a MIXED Space. All-custom (a local Space) and all-linked
  // would draw a badge equal to All beside one at 0 -- a control that can only
  // hide everything -- unless a filter is active, which keeps the way back.
  it.each<[string, PromptInfo[], string, boolean]>([
    ["a mixed Space", mixed, "All", true],
    ["every card custom", custom, "All", false],
    ["every card linked", linked, "All", false],
    ["no cards", [], "All", false],
    ["every card custom, Custom still active", custom, "Custom", true],
    ["every card linked, Linked still active", linked, "Linked", true],
  ])("draws the row for %s: %#", (_label, prompts, active, shown) => {
    expect(showLinkRow(prompts, active)).toBe(shown);
  });
});

describe("the milestone and tag filters", () => {
  // The board's two new dropdowns read the card model's `milestone` (whole: its own
  // line, else an old card's sprint line) and `tags` (docs/hub/cards.md).
  const planned = [
    card({
      file: "a.prompt.md",
      milestone: "M2 -- 1.2.0",
      sprint: "Sprint 9",
      tags: ["docs", "sev3"],
    }),
    card({ file: "b.prompt.md", milestone: "M3 -- 1.3.0", sprint: "Sprint 9", tags: ["Docs"] }),
    card({ file: "c.prompt.md", milestone: "", tags: [] }),
    // An older agent sends neither field.
    card({ file: "d.prompt.md" }),
  ];
  const all = { activeRepo: null, status: "All", text: "" };

  it("lists the milestones the cards name, whole, none for a card with none", () => {
    expect(milestonesOf(planned)).toEqual(["M2 -- 1.2.0", "M3 -- 1.3.0"]);
  });

  it("lists each tag once, whatever case a card spells it in", () => {
    expect(tagsOf(planned)).toEqual(["docs", "sev3"]);
  });

  it("filters by milestone, and All shows every card", () => {
    const f = (milestone: string) =>
      filterPrompts(planned, { ...all, milestone }).map((p) => p.file);
    expect(f("M2 -- 1.2.0")).toEqual(["a.prompt.md"]);
    expect(f("All")).toEqual(["a.prompt.md", "b.prompt.md", "c.prompt.md", "d.prompt.md"]);
  });

  it("filters by tag ignoring case", () => {
    const f = (tag: string) => filterPrompts(planned, { ...all, tag }).map((p) => p.file);
    expect(f("docs")).toEqual(["a.prompt.md", "b.prompt.md"]);
    expect(f("SEV3")).toEqual(["a.prompt.md"]);
  });

  it("composes with the sprint filter: a card in a sprint AND a milestone", () => {
    expect(
      filterPrompts(planned, { ...all, sprint: "Sprint 9", milestone: "M3 -- 1.3.0" }).map(
        (p) => p.file,
      ),
    ).toEqual(["b.prompt.md"]);
  });
});
