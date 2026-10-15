/**
 * The registry decides what the app even mounts, so "off means absent" gets a
 * test rather than a convention. Every clause here is a way the old shell
 * could not fail and the new one can: a module that is switched off leaking a
 * route, a nav link to a page that does not exist, a card from a module whose
 * backend is not there -- and card order, which is what puts the operational
 * cards on page one of a four-card pager.
 */
import type { ReactElement } from "react";

// The real ADO module drags the whole card tree (and react-markdown's ESM
// build) in behind it. What is under test is how the shell treats a module,
// not which cards that one contains, so it is stubbed and the fixtures below
// stand in for real modules.
jest.mock("../modules/ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../modules/deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../modules/organize", () => ({
  organizeModule: { id: "organize", feature: "organize", routes: [] },
}));
jest.mock("../modules/lounge", () => ({
  loungeModule: { id: "lounge", feature: "lounge", routes: [] },
}));
jest.mock("../modules/studio", () => ({ studioModule: { id: "studio", routes: [] } }));
jest.mock("../modules/solitaireAgile", () => ({
  solitaireAgileModule: { id: "solitaireAgile", feature: "solitaireAgile", routes: [] },
}));
jest.mock("../modules/growth", () => ({
  growthModule: { id: "growth", feature: "growth", routes: [] },
}));
jest.mock("../modules/communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));

import {
  activeModules,
  isChromeless,
  dormantOwner,
  moduleSettingsLinks,
  moduleCards,
  moduleNav,
  moduleNavSplit,
  moduleRoutes,
  moduleSettings,
  moduleSlot,
  moduleHomeTabs,
  homeTabFor,
  homeTabLabel,
  homeTabOrder,
} from "./registry";
import type { CardContext, ToolkitModule } from "./registry";
import type { EnvStatus } from "./api";

const ctx: CardContext = {
  env: undefined,
  filterValue: "",
  stateFilter: "All",
  stateOptions: ["All"],
  activeRepo: null,
  typeFilter: "All",
  linkFilter: "All",
  activeSkillTag: null,
  setActiveSkillTag: () => {},
};

function env(features: Record<string, boolean>): EnvStatus {
  return { features } as unknown as EnvStatus;
}

function card(id: string): ReactElement {
  return <div key={id} data-testid={id} />;
}

const core: ToolkitModule = {
  id: "ado",
  routes: [{ path: "/", element: card("core-home") }],
  nav: [{ label: "Home", to: "/", match: (p) => p === "/" }],
  homeCards: () => [card("core-card")],
  systemCards: () => [card("core-system")],
  settingsSections: () => [card("core-settings")],
  settingsLinks: () => [{ label: "Core place", anchor: "core-place" }],
};

const optional: ToolkitModule = {
  id: "growth",
  feature: "growth",
  routes: [{ path: "/growth", element: card("growth-home") }],
  nav: [{ label: "Growth", to: "/growth", match: (p) => p.startsWith("/growth") }],
  homeCards: () => [card("growth-card")],
  systemCards: () => [card("growth-system")],
  settingsSections: () => [card("growth-settings")],
  settingsLinks: () => [{ label: "Growth place", anchor: "growth-place" }],
  slotCards: { home: () => [card("growth-on-home")] },
  chromeless: (p) => p.startsWith("/growth/full/"),
};

const all = [core, optional];

describe("module registry", () => {
  it("drops a module whose feature flag is false", () => {
    const active = activeModules(all, env({ growth: false }));
    expect(active.map((m) => m.id)).toEqual(["ado"]);
  });

  it("a module with feature false contributes no routes, no nav and no cards", () => {
    const active = activeModules(all, env({ growth: false }));
    expect(moduleRoutes(active).map((r) => r.path)).toEqual(["/"]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Home"]);
    expect(moduleCards(active, ctx, "home")).toHaveLength(1);
    expect(moduleCards(active, ctx, "system")).toHaveLength(1);
  });

  it("treats a missing features map the same as false", () => {
    // Tier 3 / an older agent can answer /env without a features map at all.
    expect(activeModules(all, {} as EnvStatus).map((m) => m.id)).toEqual(["ado"]);
    expect(activeModules(all, undefined).map((m) => m.id)).toEqual(["ado"]);
  });

  it("a module without a feature is always on", () => {
    for (const e of [env({}), env({ growth: true }), undefined]) {
      expect(activeModules(all, e).map((m) => m.id)).toContain("ado");
    }
  });

  it("includes a module whose feature flag is true", () => {
    const active = activeModules(all, env({ growth: true }));
    expect(active.map((m) => m.id)).toEqual(["ado", "growth"]);
    expect(moduleRoutes(active).map((r) => r.path)).toEqual(["/", "/growth"]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Home", "Growth"]);
  });

  it("preserves module order in routes, nav and cards", () => {
    const reversed = activeModules([optional, core], env({ growth: true }));
    expect(moduleRoutes(reversed).map((r) => r.path)).toEqual(["/growth", "/"]);
    expect(moduleNav(reversed, ctx).map((n) => n.label)).toEqual(["Growth", "Home"]);
    expect(moduleCards(reversed, ctx, "home").map((c) => c.key)).toEqual([
      "growth-card",
      "core-card",
    ]);
  });

  it("honours a nav entry that hides itself for this context", () => {
    const hiding: ToolkitModule = {
      id: "ado",
      routes: [],
      nav: [
        { label: "Home", to: "/", match: (p) => p === "/" },
        { label: "Daily", to: "/daily", match: (p) => p === "/daily", hidden: () => true },
      ],
    };
    expect(moduleNav([hiding], ctx).map((n) => n.label)).toEqual(["Home"]);
  });

  // The shell draws the core's first entry -- Home -- as the Space
  // anchor, and only the rest as tabs. The data model still lists Home.
  it("splits the core's first entry off as the anchor, whatever the module order", () => {
    const on = activeModules(all, env({ growth: true }));
    const split = moduleNavSplit(on, ctx);
    expect(split.anchor?.label).toBe("Home");
    expect(split.tabs.map((n) => n.label)).toEqual(["Growth"]);
    const reversed = moduleNavSplit(activeModules([optional, core], env({ growth: true })), ctx);
    expect(reversed.anchor?.label).toBe("Home");
    expect(reversed.tabs.map((n) => n.label)).toEqual(["Growth"]);
    // No core entry, no anchor: nothing is promoted in its place.
    expect(moduleNavSplit([optional], ctx)).toEqual({
      anchor: undefined,
      tabs: [optional.nav![0]],
    });
  });

  // The settings drawer is shell chrome and may not import a module, so a
  // module's settings reach it the way its cards reach a page -- and are gated
  // the same way. A flagged-off module must not leave a section behind.
  it("settings sections follow the same flag as everything else", () => {
    const off = activeModules(all, env({ growth: false }));
    expect(moduleSettings(off, ctx).map((c) => c.key)).toEqual(["core-settings"]);
    const on = activeModules(all, env({ growth: true }));
    expect(moduleSettings(on, ctx).map((c) => c.key)).toEqual(["core-settings", "growth-settings"]);
  });

  // One module appearing on another's page, without either importing the other:
  // the host page asks for its slot by name. The deck launcher on the Growth
  // page is the case. Gated like everything else, and an unknown slot is empty.
  it("slot cards follow the flag, and a slot nobody fills is empty", () => {
    const off = activeModules(all, env({ growth: false }));
    expect(moduleSlot(off, ctx, "home")).toEqual([]);
    const on = activeModules(all, env({ growth: true }));
    expect(moduleSlot(on, ctx, "home").map((c) => c.key)).toEqual(["growth-on-home"]);
    expect(moduleSlot(on, ctx, "nobody-renders-this")).toEqual([]);
  });

  // A path a module wants the whole screen for -- a deck. Only while that
  // module is ON: a flagged-off module must not be able to strip the nav bar.
  it("a chromeless path counts only while its module is on", () => {
    const off = activeModules(all, env({ growth: false }));
    expect(isChromeless(off, "/growth/full/x")).toBe(false);
    const on = activeModules(all, env({ growth: true }));
    expect(isChromeless(on, "/growth/full/x")).toBe(true);
    expect(isChromeless(on, "/growth")).toBe(false);
  });

  // The avatar menu's destinations. Same flag as everything else: a module that
  // is off must not leave a menu entry that opens the drawer at nothing.
  it("settings links follow the flag, in module order", () => {
    const off = activeModules(all, env({ growth: false }));
    expect(moduleSettingsLinks(off, ctx).map((l) => l.anchor)).toEqual(["core-place"]);
    const on = activeModules(all, env({ growth: true }));
    expect(moduleSettingsLinks(on, ctx).map((l) => l.anchor)).toEqual([
      "core-place",
      "growth-place",
    ]);
  });

  // "No such page" and "that page is switched off" are different truths, and
  // only the registry knows which: the shell asks, and names no module.
  it("names the switched-off module that owns a path, and nobody for a stray one", () => {
    const off = activeModules(all, env({ growth: false }));
    expect(dormantOwner(all, off, "/growth")?.id).toBe("growth");
    expect(dormantOwner(all, off, "/nobody-owns-this")).toBeUndefined();
    const on = activeModules(all, env({ growth: true }));
    expect(dormantOwner(all, on, "/growth")).toBeUndefined();
  });

  it("a module contributing nothing is not an error", () => {
    const empty: ToolkitModule = { id: "deck", routes: [] };
    expect(moduleNav([empty], ctx)).toEqual([]);
    expect(moduleCards([empty], ctx, "home")).toEqual([]);
    expect(moduleCards([empty], ctx, "system")).toEqual([]);
    expect(moduleSettings([empty], ctx)).toEqual([]);
    expect(moduleSlot([empty], ctx, "growth")).toEqual([]);
    expect(isChromeless([empty], "/deck/x")).toBe(false);
  });
});

describe("Home's named tabs", () => {
  const tabbed: ToolkitModule = {
    id: "ado",
    routes: [],
    homeCards: () => [card("untabbed")],
    homeTabs: () => ({ sprint: [card("velocity"), card("dashboard")], actions: [card("actions")] }),
  };
  const growthOnCards: ToolkitModule = {
    id: "growth",
    routes: [],
    homeTabs: () => ({ cards: [card("growth-card")] }),
  };

  it("groups cards by the tab they declare, in strip order, module order within a tab", () => {
    const tabs = moduleHomeTabs([tabbed, growthOnCards], ctx);
    expect(tabs.map((t) => t.id)).toEqual(["cards", "sprint", "actions"]);
    expect(tabs.map((t) => t.cards.map((c) => c.key))).toEqual([
      ["untabbed", "growth-card"],
      ["velocity", "dashboard"],
      ["actions"],
    ]);
    expect(tabs.map((t) => [t.label, t.path])).toEqual([
      ["Focus", "/"],
      ["Sprint", "/sprint"],
      ["Actions", "/actions"],
    ]);
  });

  it("leaves out a tab with no cards -- absent, not empty", () => {
    const onlyCards: ToolkitModule = {
      id: "ado",
      routes: [],
      homeTabs: () => ({ cards: [card("x")], sprint: [] }),
    };
    expect(moduleHomeTabs([onlyCards], ctx).map((t) => t.id)).toEqual(["cards"]);
    expect(moduleHomeTabs([], ctx)).toEqual([]);
  });

  it("moduleCards('home') is every tab's cards, flattened", () => {
    expect(moduleCards([tabbed], ctx, "home").map((c) => c.key)).toEqual([
      "untabbed",
      "velocity",
      "dashboard",
      "actions",
    ]);
  });

  it("reads the tab from the address; / is the first tab; a tab Home lacks is none", () => {
    const tabs = moduleHomeTabs([tabbed], ctx);
    expect(homeTabFor("/", tabs)?.id).toBe("cards");
    // No Board tab declared: /board is no tab here, not Focus in disguise.
    expect(homeTabFor("/board", tabs)).toBeUndefined();
    expect(homeTabFor("/sprint", tabs)?.id).toBe("sprint");
    expect(homeTabFor("/actions", tabs)?.id).toBe("actions");
    expect(homeTabFor("/daily", tabs)).toBeUndefined();
    const noSprint = moduleHomeTabs([growthOnCards], ctx);
    expect(homeTabFor("/sprint", noSprint)).toBeUndefined();
    expect(homeTabFor("/backlog", tabs)).toBeUndefined();
  });

  // The owner's rule: "remove the toggle ... in-page tabs: Focus |
  // Board | Sprint | Actions". The Board is a tab like the others; a space that
  // declares only the Board lands on it at `/`, with no strip.
  it("an ADO space reads Focus | Board | Sprint | Actions; a board-only space lands on the Board", () => {
    const full: ToolkitModule = {
      id: "ado",
      routes: [],
      homeTabs: () => ({
        cards: [card("status")],
        board: [card("board")],
        sprint: [card("v")],
        actions: [card("a")],
      }),
    };
    const tabs = moduleHomeTabs([full], ctx);
    expect(tabs.map((t) => [t.id, t.label, t.path])).toEqual([
      ["cards", "Focus", "/"],
      ["board", "Board", "/board"],
      ["sprint", "Sprint", "/sprint"],
      ["actions", "Actions", "/actions"],
    ]);
    expect(homeTabFor("/", tabs)?.id).toBe("cards");
    expect(homeTabFor("/board", tabs)?.id).toBe("board");
    const boardOnly = moduleHomeTabs(
      [{ id: "ado", routes: [], homeTabs: () => ({ board: [card("board")] }) }],
      ctx,
    );
    expect(boardOnly.map((t) => [t.id, t.path])).toEqual([["board", "/board"]]);
    expect(homeTabFor("/", boardOnly)?.id).toBe("board");
    expect(homeTabFor("/board", boardOnly)?.id).toBe("board");
  });

  it("a gh space's strip wears Issues | Board | Stats; ids never change", () => {
    expect(homeTabLabel("board", "github")).toBe("Board");
    expect(homeTabLabel("backlog", "github")).toBe("Issues");
    expect(homeTabLabel("sprint", "github")).toBe("Stats");
    expect(homeTabLabel("actions", "github")).toBe("Actions");
    expect(homeTabLabel("cards", "ado")).toBe("Focus");
    expect(homeTabLabel("sprint", undefined)).toBe("Sprint");
  });

  // The owner's rule: "Issues tab is first and Board second and Stats
  // 3rd". The first tab owns `/`, so the Board keeps its `/board` address.
  it("on a gh space the issues come first, Home lands on them, and /board is still the Board", () => {
    const gh: ToolkitModule = {
      id: "ado",
      routes: [],
      homeTabs: () => ({
        board: [card("board")],
        backlog: [card("work")],
        sprint: [card("report")],
        design: [card("design")],
        docs: [card("docs")],
      }),
    };
    const ghCtx: CardContext = { ...ctx, env: { ...env({}), tracker: "github" } };
    expect(homeTabOrder("github")).toEqual([
      "backlog",
      "cards",
      "board",
      "sprint",
      "actions",
      "design",
      "docs",
    ]);
    expect(homeTabOrder(undefined)).toEqual([
      "cards",
      "board",
      "backlog",
      "sprint",
      "actions",
      "design",
      "docs",
    ]);
    const tabs = moduleHomeTabs([gh], ghCtx);
    // Design (Studio S2, D-S11), then Docs (D-S12) last, each on its own address.
    expect(tabs.map((t) => [t.id, t.label, t.path])).toEqual([
      ["backlog", "Issues", "/backlog"],
      ["board", "Board", "/board"],
      ["sprint", "Stats", "/sprint"],
      ["design", "Design", "/design"],
      ["docs", "Docs", "/docs"],
    ]);
    expect(homeTabFor("/design", tabs)?.id).toBe("design");
    expect(homeTabFor("/docs", tabs)?.id).toBe("docs");
    expect(homeTabFor("/", tabs)?.id).toBe("backlog");
    expect(homeTabFor("/backlog", tabs)?.id).toBe("backlog");
    expect(homeTabFor("/board", tabs)?.id).toBe("board");
    expect(homeTabFor("/sprint", tabs)?.id).toBe("sprint");
    // A gh space below Tier 1 has no issues tab: `/` falls to the Board, and
    // nothing is guessed.
    const boardOnly = moduleHomeTabs(
      [{ id: "ado", routes: [], homeTabs: () => ({ board: [card("board")] }) }],
      ghCtx,
    );
    expect(boardOnly.map((t) => [t.id, t.path])).toEqual([["board", "/board"]]);
    expect(homeTabFor("/", boardOnly)?.id).toBe("board");
  });
});
