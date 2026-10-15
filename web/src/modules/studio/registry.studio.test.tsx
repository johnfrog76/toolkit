/**
 * The registry contract, from the Studio's side (D-S13 amending D-S1;
 * docs/modules/studio.md, "No switch: the Studio is core"): the Studio is core, from day one. It declares no
 * flag, so the registry mounts it whatever /env says -- including a
 * `features.studio` line left in a machine's config, true or false -- and it
 * contributes its own tab, one route per page and one nav entry, and no card on
 * anybody else's page.
 *
 * Every module registry test mocks EVERY module (AGENTS.md): a sibling's real
 * tree pulls in react-markdown, which is ESM and which this runner cannot take.
 */
jest.mock("../ado", () => ({ adoModule: { id: "ado", routes: [] } }));
jest.mock("../deck", () => ({ deckModule: { id: "deck", feature: "deck", routes: [] } }));
jest.mock("../lounge", () => ({ loungeModule: { id: "lounge", feature: "lounge", routes: [] } }));
jest.mock("../growth", () => ({ growthModule: { id: "growth", feature: "growth", routes: [] } }));
jest.mock("../organize", () => ({
  organizeModule: { id: "organize", feature: "organize", routes: [] },
}));
jest.mock("../solitaireAgile", () => ({
  solitaireAgileModule: { id: "solitaireAgile", feature: "solitaireAgile", routes: [] },
}));
jest.mock("../communication", () => ({
  communicationModule: { id: "communication", feature: "communication", routes: [] },
}));
jest.mock("./StudioPage", () => ({ StudioPage: () => null }));
jest.mock("./DesignNotePage", () => ({ DesignNotePage: () => null }));
jest.mock("./PromptPage", () => ({ PromptPage: () => null }));

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
import { studioModule } from "./index";

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

const all = [studioModule];

describe("the studio's registry contract", () => {
  it("is core: it declares no flag (D-S13)", () => {
    expect(studioModule.id).toBe("studio");
    expect(studioModule.feature).toBeUndefined();
  });

  it("is mounted whatever /env says -- no features map, none at all, or a leftover features.studio", () => {
    for (const e of [
      undefined,
      {} as EnvStatus,
      env({}),
      env({ studio: false }),
      env({ studio: true }),
    ]) {
      expect(activeModules(all, e)).toEqual([studioModule]);
    }
  });

  it("contributes its own tab, and no card elsewhere", () => {
    const active = activeModules(all, env({}));
    // The room's address is a splat since L2: a live note's name, or a hub path into one of the four folders.
    expect(moduleRoutes(active).map((r) => r.path)).toEqual([
      "/studio",
      "/studio/design/*",
      "/studio/prompts/*",
    ]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Studio"]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
    expect(moduleHeaderItems(active, ctx)).toEqual([]);
    expect(studioModule.slotCards).toBeUndefined();
    expect(studioModule.headerItems).toBeUndefined();
  });

  it("sits before Team Agile and the Lounge, which stays last", () => {
    const ids = modules.map((m) => m.id);
    expect(ids.indexOf("studio")).toBe(ids.indexOf("solitaireAgile") - 1);
    expect(ids.indexOf("solitaireAgile")).toBe(ids.indexOf("lounge") - 1);
    expect(ids[ids.length - 1]).toBe("lounge");
  });
});
