/**
 * The registry contract, from the Lounge's side: gated on features.lounge,
 * off means absent -- no route, no nav entry, no card, nothing anywhere --
 * and on means exactly one tab and NOTHING else: no home card, no system
 * card, no slot card, no header item. The room contributes a place, not
 * surfaces (docs/modules/lounge.md, "Turn it on").
 *
 * Every module registry test mocks EVERY module (AGENTS.md); the scene is
 * stubbed so this stays a registry test, not a render test.
 */
jest.mock("../ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../studio", () => ({ studioModule: { id: "studio", routes: [] } }));
jest.mock("../solitaireAgile", () => ({
  solitaireAgileModule: { id: "solitaireAgile", feature: "solitaireAgile", routes: [] },
}));
jest.mock("../growth", () => ({ growthModule: { id: "growth", feature: "growth", routes: [] } }));
jest.mock("../organize", () => ({
  organizeModule: { id: "organize", feature: "organize", routes: [] },
}));
jest.mock("../communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));
jest.mock("./Lounge", () => ({ Lounge: () => null }));

import {
  activeModules,
  moduleCards,
  moduleHeaderItems,
  moduleNav,
  moduleRoutes,
  modules,
} from "../../shell/registry";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";
import { loungeModule } from "./index";

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

const all = [loungeModule];

describe("the lounge module's registry contract", () => {
  it("is gated on features.lounge", () => {
    expect(loungeModule.id).toBe("lounge");
    expect(loungeModule.feature).toBe("lounge");
  });

  it("contributes nothing when the flag is off", () => {
    const active = activeModules(all, env({ lounge: false }));
    expect(active).toHaveLength(0);
    expect(moduleRoutes(active)).toEqual([]);
    expect(moduleNav(active, ctx)).toEqual([]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
  });

  it("reads a missing features map as off", () => {
    expect(activeModules(all, {} as EnvStatus)).toHaveLength(0);
    expect(activeModules(all, undefined)).toHaveLength(0);
  });

  it("contributes one tab when on, and NOTHING else -- the room asks nothing", () => {
    const active = activeModules(all, env({ lounge: true }));
    expect(moduleRoutes(active).map((r) => r.path)).toEqual(["/lounge"]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Lounge"]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
    expect(moduleHeaderItems(active, ctx)).toEqual([]);
    expect(loungeModule.slotCards).toBeUndefined();
    expect(loungeModule.homeCards).toBeUndefined();
    expect(loungeModule.settingsSections).toBeUndefined();
  });

  it("stands LAST in module order -- you look up from the work", () => {
    expect(modules[modules.length - 1].id).toBe("lounge");
  });
});
