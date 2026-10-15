/**
 * The registry contract, from the Organize add-on's side: its flag is the one
 * /env carries, it contributes nothing when the flag is off, and when it is on
 * it contributes its own tab -- one route, one nav entry -- the header bell,
 * and no card on anybody else's page.
 *
 * Every module registry test mocks EVERY module (AGENTS.md): a sibling's real
 * tree pulls in react-markdown, which is ESM and which this runner cannot take.
 * The card and the bell are stubbed for the same reason as communication's pages.
 */
jest.mock("../ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../studio", () => ({ studioModule: { id: "studio", routes: [] } }));
jest.mock("../solitaireAgile", () => ({
  solitaireAgileModule: { id: "solitaireAgile", feature: "solitaireAgile", routes: [] },
}));
jest.mock("../lounge", () => ({ loungeModule: { id: "lounge", feature: "lounge", routes: [] } }));
jest.mock("../growth", () => ({ growthModule: { id: "growth", feature: "growth", routes: [] } }));
jest.mock("../communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));
jest.mock("./RemindersCard", () => ({ RemindersCard: () => null }));
jest.mock("./ReminderBell", () => ({ ReminderBell: () => null }));

import {
  activeModules,
  moduleCards,
  moduleHeaderItems,
  moduleNav,
  moduleRoutes,
} from "../../shell/registry";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";
import { organizeModule } from "./index";

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

const all = [organizeModule];

describe("the organize module's registry contract", () => {
  it("is gated on features.organize", () => {
    expect(organizeModule.id).toBe("organize");
    expect(organizeModule.feature).toBe("organize");
  });

  it("contributes nothing when the flag is off", () => {
    const active = activeModules(all, env({ organize: false }));
    expect(active).toHaveLength(0);
    expect(moduleRoutes(active)).toEqual([]);
    expect(moduleNav(active, ctx)).toEqual([]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleHeaderItems(active, ctx)).toEqual([]);
  });

  it("reads a missing features map as off", () => {
    expect(activeModules(all, {} as EnvStatus)).toHaveLength(0);
    expect(activeModules(all, undefined)).toHaveLength(0);
  });

  it("contributes its own tab when the flag is on, and no card elsewhere", () => {
    const active = activeModules(all, env({ organize: true }));
    expect(moduleRoutes(active).map((r) => r.path)).toEqual(["/organize"]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Organize"]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
    expect(organizeModule.slotCards).toBeUndefined();
  });

  it("puts one thing in the header when the flag is on: the reminder bell", () => {
    const active = activeModules(all, env({ organize: true }));
    expect(moduleHeaderItems(active, ctx).map((e) => e.key)).toEqual(["organize-bell"]);
  });
});
