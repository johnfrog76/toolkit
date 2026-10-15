/**
 * The registry contract, from this module's side.
 *
 * The shell's own registry.test.tsx proves the filter works for a stand-in
 * module. This one proves THIS module satisfies it: that its flag is the one
 * /env carries, that it contributes nothing when the flag is off, and that what
 * it contributes when the flag is on is the route table the spec names rather
 * than whatever the file happens to export today.
 *
 * Three things are stubbed, all for the same reason: the ADO module and the two
 * detail pages pull react-markdown, whose published build is ESM and which this
 * runner does not transform. What is under test is the shape of the module's
 * contribution, not what its pages render, so the elements behind the routes do
 * not have to be real ones.
 */
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
jest.mock("./ManagerDetailPage", () => ({ ManagerDetailPage: () => null }));
jest.mock("./ManagerSessionPage", () => ({ ManagerSessionPage: () => null }));
jest.mock("../growth", () => ({ growthModule: { id: "growth", feature: "growth", routes: [] } }));

import {
  activeModules,
  moduleCards,
  moduleNav,
  moduleRoutes,
  moduleSlot,
} from "../../shell/registry";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";
import { communicationModule } from "./index";

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

const all = [communicationModule];

describe("the communication module's registry contract", () => {
  it("is gated on features.communication", () => {
    expect(communicationModule.feature).toBe("communication");
    expect(communicationModule.id).toBe("communication");
  });

  it("contributes nothing when the flag is off", () => {
    const active = activeModules(all, env({ communication: false }));
    expect(active).toHaveLength(0);
    expect(moduleRoutes(active)).toEqual([]);
    expect(moduleNav(active, ctx)).toEqual([]);
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
  });

  it("reads a missing features map as off", () => {
    expect(activeModules(all, {} as EnvStatus)).toHaveLength(0);
    expect(activeModules(all, undefined)).toHaveLength(0);
  });

  it("contributes its routes and its nav entry when the flag is on", () => {
    const active = activeModules(all, env({ communication: true }));
    expect(active).toHaveLength(1);
    expect(moduleRoutes(active).map((r) => r.path)).toEqual([
      "/communication",
      "/communication/1on1/:filename",
      "/communication/sessions/new",
      "/communication/sessions/:filename",
      "/growth/1on1/:filename",
      "/growth/sessions/new",
      "/growth/sessions/:filename",
    ]);
    expect(moduleNav(active, ctx).map((n) => n.label)).toEqual(["Meetings"]);
  });

  it("keeps the old growth paths working", () => {
    // Nothing outside the app links to these, but a bookmark is a promise and
    // three redirect routes are a cheap way to keep it.
    const paths = communicationModule.routes.map((r) => r.path);
    for (const old of [
      "/growth/1on1/:filename",
      "/growth/sessions/new",
      "/growth/sessions/:filename",
    ]) {
      expect(paths).toContain(old);
    }
  });

  it("puts no card on the home or system pages", () => {
    // A 1:1 workflow is something you go to. The home page is for what needs
    // doing today, and this module deliberately adds nothing to it.
    const active = activeModules(all, env({ communication: true }));
    expect(moduleCards(active, ctx, "home")).toEqual([]);
    expect(moduleCards(active, ctx, "system")).toEqual([]);
  });

  it("its nav entry is active for every one of its own routes", () => {
    const [entry] = communicationModule.nav ?? [];
    expect(entry.to).toBe("/communication");
    for (const path of [
      "/communication",
      "/communication/1on1/2026-01-08.md",
      "/communication/sessions/new",
    ]) {
      expect(entry.match(path)).toBe(true);
    }
    expect(entry.match("/")).toBe(false);
    expect(entry.match("/system")).toBe(false);
  });
});

describe("Meetings on the Organize tab", () => {
  // With features.organize on, the Meetings card lives on /organize through the
  // organize slot and its own nav entry steps aside -- the deck launcher's shape
  // under Growth. With organize off, nothing changes.
  const on = { ...ctx, env: env({ communication: true, organize: true }) };
  const off = { ...ctx, env: env({ communication: true, organize: false }) };
  const active = activeModules(all, env({ communication: true }));

  it("fills the organize slot with one card", () => {
    expect(moduleSlot(active, on, "organize")).toHaveLength(1);
  });

  it("hides its own tab when Organize is on", () => {
    expect(moduleNav(active, on).map((n) => n.label)).toEqual([]);
  });

  it("keeps its own tab when Organize is off", () => {
    expect(moduleNav(active, off).map((n) => n.label)).toEqual(["Meetings"]);
  });
});
