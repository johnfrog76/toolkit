/**
 * The growth module contributes nothing at all when its flag is off.
 *
 * `registry.test.tsx` proves the registry HONOURS a feature flag, using
 * fixtures that stand in for modules. This proves the real growth export is
 * shaped so that it does: that its `feature` key is the one /env actually
 * answers with, that the routes it declares are the ones the spec names, and
 * that turning the flag off removes the route, the nav entry and the chunk
 * rather than leaving a link to a page that will 404 on its own data.
 *
 * The three page components are stubbed. What is under test is the module's
 * declaration, not its card tree -- and importing the real tree drags in
 * react-markdown's ESM build for no benefit.
 */
// The registry imports every module, and the ADO one drags in the whole card
// tree behind it. This file is about growth's entry, so ADO is stubbed the same
// way registry.test.tsx stubs it.
jest.mock("../ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../studio", () => ({ studioModule: { id: "studio", routes: [] } }));
jest.mock("../solitaireAgile", () => ({
  solitaireAgileModule: { id: "solitaireAgile", feature: "solitaireAgile", routes: [] },
}));
jest.mock("../lounge", () => ({ loungeModule: { id: "lounge", feature: "lounge", routes: [] } }));
jest.mock("../organize", () => ({
  organizeModule: { id: "organize", feature: "organize", routes: [] },
}));

jest.mock("./GrowthPage", () => ({ GrowthPage: () => null }));
jest.mock("./GoalDetailPage", () => ({ GoalDetailPage: () => null }));
jest.mock("./SkillsPage", () => ({ SkillsPage: () => null }));
jest.mock("./ReviewArchive", () => ({ ReviewArchive: () => null }));
jest.mock("./SkillsSnapshot", () => ({ SkillsSnapshot: () => null }));
jest.mock("../communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));

import { growthModule } from "./index";
import { activeModules, moduleCards, moduleNav, moduleRoutes } from "../../shell/registry";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";

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

describe("the growth module's registry entry", () => {
  it("is gated on the flag /env reports, not on an org", () => {
    // Engineer-scoped: the key is top-level in the features map, and the
    // module says so by naming it here.
    expect(growthModule.feature).toBe("growth");
    expect(growthModule.id).toBe("growth");
  });

  it("declares the three routes the spec names", () => {
    expect(moduleRoutes([growthModule]).map((r) => r.path)).toEqual([
      "/growth",
      "/growth/goals/:filename",
      "/skills",
    ]);
  });

  it("contributes one nav entry, which claims /skills as well as /growth", () => {
    const nav = moduleNav([growthModule], ctx);
    expect(nav.map((n) => n.label)).toEqual(["Growth"]);
    expect(nav[0].match("/growth")).toBe(true);
    expect(nav[0].match("/growth/goals/goal-2026-x.prompt.md")).toBe(true);
    expect(nav[0].match("/skills")).toBe(true);
    expect(nav[0].match("/")).toBe(false);
    expect(nav[0].match("/billing")).toBe(false);
  });

  it("contributes no home or system cards of its own", () => {
    // ReviewArchive and SkillsSnapshot are exported for the ADO module's
    // archive-mode home to import. They are that module's to place, so growth
    // must not also push them onto every home page.
    expect(moduleCards([growthModule], ctx, "home")).toEqual([]);
    expect(moduleCards([growthModule], ctx, "system")).toEqual([]);
  });

  it("contributes nothing when the flag is false", () => {
    const active = activeModules([growthModule], env({ growth: false }));
    expect(active).toEqual([]);
    expect(moduleRoutes(active)).toEqual([]);
    expect(moduleNav(active, ctx)).toEqual([]);
  });

  it("contributes nothing when /env has no features map at all", () => {
    for (const e of [{} as EnvStatus, undefined]) {
      expect(activeModules([growthModule], e)).toEqual([]);
    }
  });

  it("contributes nothing when some OTHER module's flag is on", () => {
    expect(activeModules([growthModule], env({ communication: true }))).toEqual([]);
  });

  it("contributes its routes and nav when the flag is true", () => {
    const active = activeModules([growthModule], env({ growth: true }));
    expect(active.map((m) => m.id)).toEqual(["growth"]);
    expect(moduleRoutes(active)).toHaveLength(3);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Growth"]);
  });

  it("exports the two cards the ADO archive home imports", () => {
    // A module may import another module's card; it may not fork one. That
    // only works while these two are exported by name.
    const growth = jest.requireActual("./index");
    expect(typeof growth.ReviewArchive).toBe("function");
    expect(typeof growth.SkillsSnapshot).toBe("function");
  });
});
