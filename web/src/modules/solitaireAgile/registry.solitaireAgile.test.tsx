/**
 * The registry contract, from Team Agile's side
 * (docs/modules/solitaire-agile.md, "The switch, and its scope"): its flag is the
 * one /env carries, it contributes nothing when the flag is off, and when it
 * is on it contributes its own tab -- the standup's route and, since V1,
 * its played view's, one nav entry -- after the Studio's and before the
 * Lounge's, and no card on anybody else's page.
 *
 * Every module registry test mocks EVERY module (AGENTS.md): a sibling's real
 * tree pulls in react-markdown, which is ESM and which this runner cannot take.
 * The Studio and the Lounge stand-ins carry a nav entry so the order can be read.
 */
jest.mock("../ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../growth", () => ({ growthModule: { id: "growth", feature: "growth", routes: [] } }));
jest.mock("../organize", () => ({
  organizeModule: { id: "organize", feature: "organize", routes: [] },
}));
jest.mock("../communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));
jest.mock("../studio", () => ({
  studioModule: { id: "studio", routes: [], nav: [{ label: "Studio", to: "/studio" }] },
}));
jest.mock("../lounge", () => ({
  loungeModule: {
    id: "lounge",
    feature: "lounge",
    routes: [],
    nav: [{ label: "Lounge", to: "/lounge" }],
  },
}));
jest.mock("./StandupPage", () => ({ StandupPage: () => null }));
jest.mock("./MilestonesPage", () => ({ MilestonesPage: () => null }));
jest.mock("./RitualPage", () => ({ RitualPage: () => null }));
jest.mock("./stage/StandupPlay", () => ({ StandupPlay: () => null }));
jest.mock("./ConfettiLayer", () => ({ ConfettiLayer: () => null }));

import {
  activeModules,
  isChromeless,
  moduleCards,
  moduleHeaderItems,
  moduleNav,
  moduleOverlays,
  moduleRoutes,
  modules,
} from "../../shell/registry";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";
import { solitaireAgileModule } from "./index";
import { WORKFLOW_ENTRIES } from "../../shell/settingsWorkflows";

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

const all = [solitaireAgileModule];

describe("the solitaireAgile module's registry contract", () => {
  it("is gated on features.solitaireAgile", () => {
    expect(solitaireAgileModule.id).toBe("solitaireAgile");
    expect(solitaireAgileModule.feature).toBe("solitaireAgile");
  });

  it("contributes nothing when the flag is off: no route, no nav entry", () => {
    const active = activeModules(all, env({ solitaireAgile: false }));
    expect(active).toHaveLength(0);
    expect(moduleRoutes(active)).toEqual([]);
    expect(moduleNav(active, ctx)).toEqual([]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleHeaderItems(active, ctx)).toEqual([]);
    // No confetti mount in the tree either: nothing to listen, nothing to fetch.
    expect(moduleOverlays(active, ctx)).toEqual([]);
  });

  it("reads a missing features map as off", () => {
    expect(activeModules(all, {} as EnvStatus)).toHaveLength(0);
    expect(activeModules(all, undefined)).toHaveLength(0);
  });

  it("contributes its own tab when the flag is on, and no card elsewhere", () => {
    const active = activeModules(all, env({ solitaireAgile: true }));
    expect(moduleRoutes(active).map((r) => r.path)).toEqual([
      "/solitaire-agile",
      "/solitaire-agile/triage",
      "/solitaire-agile/milestones",
      "/deck/ritual/standup",
    ]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Team Agile"]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
    expect(solitaireAgileModule.slotCards).toBeUndefined();
    expect(solitaireAgileModule.headerItems).toBeUndefined();
  });

  it("contributes ONE root overlay when on -- the confetti's one mount, a lazy part", () => {
    const overlays = moduleOverlays(activeModules(all, env({ solitaireAgile: true })), ctx);
    expect(overlays).toHaveLength(1);
    expect(overlays[0].key).toBe("solitaireAgile.confetti");
    // A lazy part, not the layer itself: the descriptor imports no component.
    expect((overlays[0].type as { name?: string }).name).toBe("LazyPart");
  });

  it("Triage and Milestones are pages under the ONE Team Agile entry, and not chromeless", () => {
    const [entry] = moduleNav(activeModules(all, env({ solitaireAgile: true })), ctx);
    for (const page of ["/solitaire-agile/triage", "/solitaire-agile/milestones"]) {
      expect(entry.match(page)).toBe(true);
      expect(solitaireAgileModule.chromeless?.(page)).toBe(false);
    }
  });

  it("the played standup is a room of its own (chromeless) only while the flag is on", () => {
    const on = activeModules(all, env({ solitaireAgile: true }));
    const off = activeModules(all, env({ solitaireAgile: false }));
    expect(isChromeless(on, "/deck/ritual/standup")).toBe(true);
    expect(isChromeless(on, "/solitaire-agile")).toBe(false);
    expect(isChromeless(off, "/deck/ritual/standup")).toBe(false);
  });

  // Settings asks "How do you want to work in <Space>?", and the answer is
  // the Space's -- the agent serves this flag with the answer applied, so only a
  // Space answered "With agents" mounts the tab; the entry's door still goes to
  // the switch itself.
  it("only the answer 'With agents' mounts the tab, and the door goes to the switch", () => {
    const entry = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    expect(entry.anchor).toBe("features.solitaireAgile");
    const nav = entry.answers!.map((a) => [
      a.label,
      moduleNav(activeModules(all, env({ solitaireAgile: a.value === "agents" })), ctx).map(
        (n) => n.label,
      ),
    ]);
    expect(nav).toEqual([
      ["With agents", ["Team Agile"]],
      ["Alone", []],
      ["On a team in Azure", []],
    ]);
  });

  it("sits after the Studio and before the Lounge, which stays last", () => {
    const ids = modules.map((m) => m.id);
    expect(ids.slice(-3)).toEqual(["studio", "solitaireAgile", "lounge"]);
    const active = activeModules(modules, env({ solitaireAgile: true, lounge: true }));
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Studio", "Team Agile", "Lounge"]);
  });
});
