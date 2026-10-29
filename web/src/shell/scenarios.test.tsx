/**
 * THE SCENARIO GRID, executable (docs/SCENARIOS.md is the same grid in words).
 *
 * The owner's rule: "we need to make sure all the different tier states and
 * configurations still solid and if you turn off and on modules" -- and "do
 * we have a definition or grid that shows all the different scenarios --
 * tests -- what our expectations are". This is it for the web half: the REAL
 * module registry (nothing mocked but two ESM markdown packages and the
 * browser's matchMedia), one row per configuration, and for each row what a
 * person sees -- which modules run, what the Space anchor at the left of the
 * nav is (Home, drawn as the Space pill), which nav tabs follow it,
 * what Home's strip reads, what System holds. A module is turned on and off by changing one
 * flag in the row's env, which is exactly what the settings drawer does.
 *
 * The other halves' grids: the ADO-enabled table (Tests/fixtures/ado-enabled/
 * table.json, read by tkTestToolkit -Setup and Tests/test_ado_enabled.py), the
 * tier parity table (Tests/test_tier_parity.py), and the flag scope rules
 * (Tests/test_features.py).
 */
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
});
jest.mock("react-markdown", () => ({ __esModule: true, default: () => null }));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));

import {
  activeModules,
  isChromeless,
  moduleCards,
  moduleHomeTabs,
  moduleNavSplit,
  moduleRoutes,
  modules,
} from "./registry";
import type { CardContext } from "./registry";
import type { EnvStatus, HowIWork, SpaceInfo } from "./api";
import { drawerSections } from "../modules/ado/homeTabs";
import { cardActions } from "../modules/ado/cardActions";
import { LANES, legalMoves, whyNotAMove } from "../modules/ado/legalMoves";
import { LANE_FIELD_KEY, laneLabel } from "../modules/ado/laneNames";
import { countInPlay, inPlayLine } from "../modules/ado/inPlay";
import type { StatusResponse } from "../modules/ado/api.ado";
import { fireEvent, render, screen } from "@testing-library/react";
import { AvatarMenu } from "./AvatarMenu";
import { SPACE_QUICK_MENU_THRESHOLD } from "./SpaceQuickMenu";
import {
  SPACES_FILTERS,
  cardsPhrase,
  filterSpaces,
  githubRowLine,
  readsVisibility,
  spaceBucket,
  spaceLifecycleActions,
} from "../modules/studio/foyer";
import { visibilityLabel } from "../shared/visibility";
import { STATUS, VISIBILITY } from "./consts";
import { WORKFLOW_ENTRIES, answerLive, answerTarget } from "./settingsWorkflows";
import type { SpaceBucket, SpaceLifecycleAction } from "../modules/studio/foyer";
import { promptSets, spaceWorkflow } from "../modules/studio/prompts";
import type { PromptRow, PromptWorkflow } from "../modules/studio/api.studio";
import { itemFacts, itemRef, itemSpoken } from "../modules/solitaireAgile/itemRef";
import { chairSuggestion } from "../modules/solitaireAgile/suggestion";
import { briefSansCorner, cornerOf, hasChevron, isReached } from "../modules/solitaireAgile/corner";
import { pendingAwards, awardStage, AWARD_SEEN_KEY } from "../modules/solitaireAgile/award";
import { resetCelebrateMemory } from "../modules/solitaireAgile/celebrate";
import type { Milestone } from "../modules/ado/api.ado";
import type { AgendaItem, StandupResponse } from "../modules/solitaireAgile/api.solitaireAgile";
import { agendaArg, agendaFact, sinceHeading } from "../modules/solitaireAgile/agenda";
import fs from "node:fs";
import path from "node:path";

type Status = EnvStatus["spaceStatus"];
type Tracker = NonNullable<EnvStatus["tracker"]>;

function env(o: {
  status: Status;
  tier: number;
  tracker: Tracker;
  features?: Record<string, boolean>;
}): EnvStatus {
  return {
    machine: "m",
    os: "macOS",
    container: false,
    tier: o.tier,
    tierLabel: `Tier ${o.tier}`,
    spaceStatus: o.status,
    features: o.features ?? {},
    tracker: o.tracker,
    anthropicConfigured: false,
    uptime: 1,
    checks: {},
    config: {
      org: null,
      projects: [],
      promptsFolder: "x",
      activeSpace: "x",
      spaces: [{ slug: "x", name: "X", status: o.status } as never],
    },
  };
}

function see(e: EnvStatus | undefined) {
  const ctx: CardContext = {
    env: e,
    filterValue: "",
    stateFilter: "All",
    stateOptions: ["All"],
    activeRepo: null,
    typeFilter: "All",
    linkFilter: "All",
    activeSkillTag: null,
    setActiveSkillTag: () => {},
  };
  const active = activeModules(modules, e);
  const { anchor, tabs } = moduleNavSplit(active, ctx);
  return {
    modules: active.map((m) => m.id),
    anchor: anchor?.label,
    nav: tabs.map((n) => n.label),
    home: moduleHomeTabs(active, ctx).map((t) => t.label),
    system: moduleCards(active, ctx, "system").map((c) => String(c.key)),
  };
}

const ALL_ON = {
  growth: true,
  communication: true,
  deck: true,
  organize: true,
  solitaireAgile: true,
  lounge: true,
};
// Home is not a tab: it is the anchor every row names. The tabs after
// the divider start at System.
const CORE_NAV = ["System", "Daily"];
// The core: the cards (the ado module) and, since D-S13, the Studio --
// no flag, on every Space. Its tab keeps its place among the modules' tabs:
// after Growth and Organize, before Team Agile and the Lounge.
const CORE: ReturnType<typeof see>["modules"] = ["ado", "studio"];
const SYSTEM = ["env", "modules", "log"];

// [name, env, what you see]
const rows: [string, EnvStatus | undefined, ReturnType<typeof see>][] = [
  [
    "env not loaded: the core alone, nothing guessed",
    undefined,
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus"],
      system: SYSTEM,
    },
  ],
  [
    "ADO active, Tier 1, no modules: Focus | Board | Sprint | Actions; System has Test Health",
    env({ status: "active", tier: 1, tracker: "ado" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "ADO active, Tier 2 (Azure DevOps unreachable): no Actions, Sprint only with sprint awareness",
    env({ status: "active", tier: 2, tracker: "ado" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "ADO active, Tier 2, sprint awareness on: Sprint comes back",
    env({ status: "active", tier: 2, tracker: "ado", features: { sprintAwareness: true } }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board", "Sprint"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "ADO active, Tier 3 (no az at all): Focus and Board; System loses Test Health",
    env({ status: "active", tier: 3, tracker: "ado" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board"],
      system: SYSTEM,
    },
  ],
  [
    "local space (Demo), Tier 3: the Board alone -- one tab, no strip",
    env({ status: "local", tier: 3, tracker: "none" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Board"],
      system: SYSTEM,
    },
  ],
  [
    "GitHub space, Tier 1: Issues | Board | Stats | Design | Docs -- Design reads the repo's design/ and spec/ (Studio S2), Docs its README and docs/",
    env({ status: "active", tier: 1, tracker: "github" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Issues", "Board", "Stats", "Design", "Docs"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "GitHub space, Tier 2 (gh signed out): the Board alone",
    env({ status: "active", tier: 2, tracker: "github" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Board"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "archived space: Focus holds the retrospective, no Board, no Daily",
    env({ status: "archive", tier: 1, tracker: "ado" }),
    {
      anchor: "Home",
      modules: CORE,
      nav: ["System", "Studio"],
      home: ["Focus"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "every module switched on, ADO active Tier 1: the whole nav but Team Agile (the Space is on a team); Decks hides under Growth, Meetings under Organize",
    env({
      status: "active",
      tier: 1,
      tracker: "ado",
      features: { ...ALL_ON, solitaireAgile: false },
    }),
    {
      anchor: "Home",
      modules: ["ado", "growth", "communication", "deck", "organize", "studio", "lounge"],
      nav: [...CORE_NAV, "Growth", "Organize", "Studio", "Lounge"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "growth alone: its nav entry, nothing else changes",
    env({ status: "active", tier: 1, tracker: "ado", features: { growth: true } }),
    {
      anchor: "Home",
      modules: ["ado", "growth", "studio"],
      nav: [...CORE_NAV, "Growth", "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "communication alone: Meetings shows (Organize is off, so nothing hides it)",
    env({ status: "active", tier: 1, tracker: "ado", features: { communication: true } }),
    {
      anchor: "Home",
      modules: ["ado", "communication", "studio"],
      nav: [...CORE_NAV, "Meetings", "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "deck alone: Decks shows (Growth is off, so nothing hides it)",
    env({ status: "active", tier: 1, tracker: "ado", features: { deck: true } }),
    {
      anchor: "Home",
      modules: ["ado", "deck", "studio"],
      nav: [...CORE_NAV, "Decks", "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "organize alone: Organize shows",
    env({ status: "active", tier: 1, tracker: "ado", features: { organize: true } }),
    {
      anchor: "Home",
      modules: ["ado", "organize", "studio"],
      nav: [...CORE_NAV, "Organize", "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "lounge alone: Lounge shows, LAST; System is unchanged (the Face card lives in the room)",
    env({ status: "active", tier: 1, tracker: "ado", features: { lounge: true } }),
    {
      anchor: "Home",
      modules: ["ado", "studio", "lounge"],
      nav: [...CORE_NAV, "Studio", "Lounge"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "the Studio is core (D-S13): a features.studio left in config, true or false, changes nothing -- the tab is there either way",
    env({ status: "active", tier: 1, tracker: "github", features: { studio: false } }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Issues", "Board", "Stats", "Design", "Docs"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "the Studio on an ADO Space, with a leftover features.studio true: the same tab, and Home's strip is unchanged (the foyer is its own tab)",
    env({ status: "active", tier: 1, tracker: "ado", features: { studio: true } }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "solitaireAgile alone, on a GitHub Space answered With agents: Team Agile shows, after the Studio's place and before the Lounge's; Home's strip is unchanged (the standup is its own tab, reading the Space's issues and its cards, joined on the id)",
    env({ status: "active", tier: 1, tracker: "github", features: { solitaireAgile: true } }),
    {
      anchor: "Home",
      modules: ["ado", "studio", "solitaireAgile"],
      nav: [...CORE_NAV, "Studio", "Team Agile"],
      home: ["Issues", "Board", "Stats", "Design", "Docs"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "solitaireAgile switched on, on an ADO Space: the Space is on a team, so the agent serves the flag off -- no tab; their board holds the rituals",
    env({ status: "active", tier: 1, tracker: "ado", features: { solitaireAgile: false } }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "a flag answered NO is the same as absent: off means absent",
    env({
      status: "active",
      tier: 1,
      tracker: "ado",
      features: {
        growth: false,
        lounge: false,
        deck: false,
        organize: false,
        communication: false,
        solitaireAgile: false,
      },
    }),
    {
      anchor: "Home",
      modules: CORE,
      nav: [...CORE_NAV, "Studio"],
      home: ["Focus", "Board", "Sprint", "Actions"],
      system: [...SYSTEM, "test-health"],
    },
  ],
  [
    "modules on a local space: the add-ons are the engineer's, so they show on Demo too -- all but Team Agile, which a Space with no tracker answers alone",
    env({
      status: "local",
      tier: 3,
      tracker: "none",
      features: { ...ALL_ON, solitaireAgile: false },
    }),
    {
      anchor: "Home",
      modules: ["ado", "growth", "communication", "deck", "organize", "studio", "lounge"],
      nav: [...CORE_NAV, "Growth", "Organize", "Studio", "Lounge"],
      home: ["Board"],
      system: SYSTEM,
    },
  ],
  [
    "modules on a GitHub space: the same add-ons, the gh strip -- and Team Agile, the Space answered With agents",
    env({ status: "active", tier: 1, tracker: "github", features: ALL_ON }),
    {
      anchor: "Home",
      modules: [
        "ado",
        "growth",
        "communication",
        "deck",
        "organize",
        "studio",
        "solitaireAgile",
        "lounge",
      ],
      nav: [...CORE_NAV, "Growth", "Organize", "Studio", "Team Agile", "Lounge"],
      home: ["Issues", "Board", "Stats", "Design", "Docs"],
      system: [...SYSTEM, "test-health"],
    },
  ],
];

describe("the scenario grid: what each configuration shows", () => {
  it.each(rows)("%s", (_name, e, expected) => {
    expect(see(e)).toEqual(expected);
  });

  it("turning a module on and off is one flag, and the product follows at once", () => {
    const off = env({ status: "active", tier: 1, tracker: "ado", features: { lounge: false } });
    const on = env({ status: "active", tier: 1, tracker: "ado", features: { lounge: true } });
    expect(see(off).nav).not.toContain("Lounge");
    expect(see(on).nav).toContain("Lounge");
    expect(see(off).system).toEqual(see(on).system);
  });

  // The Stats cell on a GitHub Space: the Issue Report, the Milestones
  // card beside it, then the deploys. An ADO Space has no Stats tab to hold
  // one, and a Tier 2 GitHub Space no tab at all -- so nothing fetches there.
  it("Stats on a GitHub Space, Tier 1, holds the Issue Report, Milestones and Deploys", () => {
    const stats = (e: EnvStatus) => {
      const ctx: CardContext = {
        env: e,
        filterValue: "",
        stateFilter: "All",
        stateOptions: ["All"],
        activeRepo: null,
        typeFilter: "All",
        linkFilter: "All",
        activeSkillTag: null,
        setActiveSkillTag: () => {},
      };
      const tab = moduleHomeTabs(activeModules(modules, e), ctx).find((t) => t.id === "sprint");
      return tab ? tab.cards.map((c) => String(c.key)) : [];
    };
    expect(stats(env({ status: "active", tier: 1, tracker: "github" }))).toEqual([
      "issue-report",
      "milestones",
      "deploys",
    ]);
    expect(stats(env({ status: "active", tier: 2, tracker: "github" }))).toEqual([]);
    expect(stats(env({ status: "active", tier: 1, tracker: "ado" }))).not.toContain("milestones");
  });

  // The filter drawer, by tab: ToolKit's card filters wherever cards are
  // drawn, the ADO repo row on an Azure DevOps Space, the GitHub issue filters
  // on a GitHub Space's Issues tab -- and no drawer where no section reaches a card.
  it("the filter drawer holds what reaches the tab: cards, ADO's repos, or the Issues", () => {
    const ado = env({ status: "active", tier: 1, tracker: "ado" });
    const gh = env({ status: "active", tier: 1, tracker: "github" });
    expect(drawerSections(ado, "cards")).toEqual(["search", "cards", "ado"]);
    expect(drawerSections(ado, "board")).toEqual(["search", "cards", "ado"]);
    expect(drawerSections(gh, "backlog")).toEqual(["search", "issues"]);
    expect(drawerSections(gh, "board")).toEqual(["search", "cards"]);
    // Design filters by kind, Docs by folder; Stats by nothing, by design.
    expect(drawerSections(gh, "design")).toEqual(["search", "kind"]);
    expect(drawerSections(gh, "docs")).toEqual(["search", "folder"]);
    expect(drawerSections(gh, "sprint")).toEqual([]);
    expect(drawerSections(ado, "sprint")).toEqual([]);
  });

  // Team Agile's played standup is Team Agile's route, not the deck
  // module's: it plays with features.deck off, and it is absent with
  // features.solitaireAgile off whatever the deck flag says.
  it("the played standup follows Team Agile's flag, not the deck's", () => {
    const at = (features: Record<string, boolean>) => {
      const active = activeModules(
        modules,
        env({ status: "active", tier: 1, tracker: "github", features }),
      );
      return {
        route: moduleRoutes(active).some((r) => r.path === "/deck/ritual/standup"),
        chromeless: isChromeless(active, "/deck/ritual/standup"),
      };
    };
    expect(at({ solitaireAgile: true, deck: false })).toEqual({ route: true, chromeless: true });
    expect(at({ solitaireAgile: false, deck: true }).route).toBe(false);
    expect(at({ solitaireAgile: false, deck: false })).toEqual({ route: false, chromeless: false });
  });

  // The joined source (source: both) puts cards among the issues, and the page
  // and the played deck read an item one way: a number is an issue (#n, linked),
  // otherwise a card (its id, no link). Held in full by stage/standupDeck.test.tsx.
  it("the played standup names an issue #<n> and a card by its id, never #null", () => {
    const issue = { number: 143, title: "A", url: "https://example.test/143" };
    const card = { number: null, id: "2HNU", title: "B", url: "", path: "current/x.md" };
    expect([itemRef(issue), itemRef(card)]).toEqual(["#143", "2HNU"]);
    expect([itemSpoken(issue), itemSpoken(card)]).toEqual(["issue 143, A", "card 2HNU, B"]);
    expect(itemFacts(issue).url).toBe("https://example.test/143");
    expect(itemFacts(card)).toEqual({ title: "B", label: "2HNU", path: "current/x.md" });
  });

  // Team Agile's Triage is a second page under the ONE Team Agile
  // entry: the nav does not grow, the page has the chrome, and it is absent
  // with features.solitaireAgile off.
  it("Triage is a page under Team Agile's one nav entry, there only with the flag", () => {
    const at = (features: Record<string, boolean>) => {
      const e = env({ status: "active", tier: 1, tracker: "github", features });
      const active = activeModules(modules, e);
      const ctx = { env: e } as CardContext;
      return {
        route: moduleRoutes(active).some((r) => r.path === "/solitaire-agile/triage"),
        chromeless: isChromeless(active, "/solitaire-agile/triage"),
        nav: moduleNavSplit(active, ctx)
          .tabs.filter((n) => n.match("/solitaire-agile/triage"))
          .map((n) => n.label),
      };
    };
    expect(at({ solitaireAgile: true })).toEqual({
      route: true,
      chromeless: false,
      nav: ["Team Agile"],
    });
    expect(at({ solitaireAgile: false })).toEqual({ route: false, chromeless: false, nav: [] });
  });

  // The chair's suggestion (docs/SCENARIOS.md, "Team Agile's standup"): the
  // agent attaches it only where the Space's switch is on (spaces[].features.
  // suggestions, unset is on), and the brief's Next line is it only when nothing
  // waits. The page draws a suggestion row exactly when the brief's last line IS
  // the first candidate's line -- over the suggestion table's three generated goldens.
  it("the chair's suggestion: a row where the switch is on and nothing waits; today's line otherwise", () => {
    const dir = path.resolve(__dirname, "../../../Tests/fixtures/suggestion");
    const brief = (name: string) =>
      fs.readFileSync(path.join(dir, `suggestion-${name}.brief.txt`), "utf8");
    const last = (text: string) => text.split("\n").filter(Boolean).pop() ?? "";
    const first = {
      ref: "#141",
      number: 141,
      id: null,
      kind: "issue" as const,
      shape: "delegate",
      sentence: "",
      command: "StartWork 141",
      line: last(brief("suggested")),
    };
    const at = (name: string, on: boolean) =>
      chairSuggestion(
        {
          brief: brief(name),
          suggestions: on ? [first] : [],
          suggestion: on ? first : null,
        } as unknown as StandupResponse,
        [],
      ).standing;
    expect([at("suggested", true), at("waiting", true), at("switched-off", false)]).toEqual([
      true,
      false,
      false,
    ]);
    expect(last(brief("switched-off"))).toBe("Next: nothing is waiting on you.");
  });

  // The PM Corner (docs/SCENARIOS.md, "Team Agile's standup"): the agent attaches it
  // where the suggestion is on, as the brief's LAST line; the page draws it at the
  // head instead. Reached is the line and a link to the Milestones tab -- the Corner
  // throws no confetti (PmCorner.test.tsx holds that); the award dialog does.
  // Over corner.json's generated goldens.
  it("the PM Corner: reached is the line and a way to Milestones; several left the chevron; no Corner off GitHub", () => {
    const dir = path.resolve(__dirname, "../../../Tests/fixtures/rituals");
    const brief = (name: string) =>
      fs.readFileSync(path.join(dir, `corner-${name}.brief.txt`), "utf8");
    const last = (text: string) => text.split("\n").filter(Boolean).pop() ?? "";
    const reachedCorner = {
      shape: "reached",
      milestone: "B",
      remaining: 0,
      ref: "",
      number: null,
      id: null,
      kind: "",
      noun: "",
      line: "milestone B reached",
      command: "",
      brief: last(brief("reached")),
    };
    const data = { brief: brief("reached"), corner: reachedCorner } as unknown as StandupResponse;
    const corner = cornerOf(data)!;
    expect(corner.brief).toBe("Corner: milestone B reached");
    expect([isReached(corner), hasChevron(corner)]).toEqual([true, false]);
    // The brief the page draws below the Corner stops above its line.
    expect(briefSansCorner(data).includes("Corner:")).toBe(false);
    // Several left: the line and its chevron.
    expect(last(brief("many-left"))).toBe(
      "Corner: 3 more issues to get milestone B - start #5 now > (tkStartWork 5)",
    );
    // The switch off -- or an Azure DevOps Space, where the agent attaches nothing --
    // no Corner, and the brief is today's.
    expect(
      cornerOf({ brief: brief("switched-off"), corner: null } as unknown as StandupResponse),
    ).toBeNull();
    expect(brief("switched-off").includes("Corner:")).toBe(false);
  });

  // The Agenda (docs/SCENARIOS.md, "Team Agile's standup"): the page opens on it.
  // Two lanes the agent derives (agent/solitaire/agenda.py) -- what moved since the
  // window's day, and what is waiting on you -- each tile one fact with a long date,
  // never a relative day, and at most one action: none on what moved, Work it now
  // on what waits, Review it on what waits on a review.
  it("the Agenda: Since <day> and the queue's heading; one fact a tile, a long date, no Yesterday or Today", () => {
    const tile = (over: Partial<AgendaItem>): AgendaItem => ({
      ref: "#1",
      number: 1,
      id: null,
      kind: "issue",
      title: "",
      url: "",
      path: "",
      file: "",
      lane: "",
      day: "2026-10-23",
      review: false,
      cover: null,
      checked: 0,
      total: 0,
      progress: "--",
      ...over,
    });
    expect(sinceHeading("2026-10-23T00:00:00-04:00")).toBe("Since Friday 23 October");
    const facts = [
      agendaFact(tile({}), true),
      agendaFact(tile({ kind: "card", number: null, id: "K7M2", lane: STATUS.done }), true),
      agendaFact(tile({ kind: "card", lane: STATUS.active }), false),
      agendaFact(tile({ lane: STATUS.codeReview, review: true, day: "2026-10-24" }), false),
      agendaFact(tile({}), false),
      agendaFact(tile({ lane: STATUS.codeReview, review: true, day: "" }), false),
    ];
    expect(facts).toEqual([
      "Closed Friday 23 October",
      "Archived Friday 23 October",
      "Active since Friday 23 October",
      "In review since Saturday 24 October",
      "Open since Friday 23 October",
      "In review",
    ]);
    for (const f of facts) expect(f).not.toMatch(/yesterday|today/i);
    expect([agendaArg(tile({})), agendaArg(tile({ number: null, id: "K7M2" }))]).toEqual([
      "1",
      "K7M2",
    ]);
  });

  // Team Agile's Milestones (docs/SCENARIOS.md, "Team Agile's milestones"): a third
  // page under the ONE Team Agile entry, absent with the flag off; over the shared
  // table (Tests/fixtures/rituals/milestones.json) a reached milestone first seen in
  // this browser is the award -- once -- and then reads awarded; an empty one is
  // never awarded.
  it("Milestones: a page under Team Agile's one entry; reached is the award once, then awarded; empty never", () => {
    const at = (features: Record<string, boolean>) => {
      const e = env({ status: "active", tier: 1, tracker: "github", features });
      const active = activeModules(modules, e);
      const ctx = { env: e } as CardContext;
      return {
        route: moduleRoutes(active).some((r) => r.path === "/solitaire-agile/milestones"),
        chromeless: isChromeless(active, "/solitaire-agile/milestones"),
        nav: moduleNavSplit(active, ctx)
          .tabs.filter((n) => n.match("/solitaire-agile/milestones"))
          .map((n) => n.label),
      };
    };
    expect(at({ solitaireAgile: true })).toEqual({
      route: true,
      chromeless: false,
      nav: ["Team Agile"],
    });
    expect(at({ solitaireAgile: false })).toEqual({ route: false, chromeless: false, nav: [] });

    const table = JSON.parse(
      fs.readFileSync(
        path.resolve(__dirname, "../../../Tests/fixtures/rituals/milestones.json"),
        "utf8",
      ),
    ) as { expected: Milestone[] };
    localStorage.clear();
    resetCelebrateMemory();
    const reached = pendingAwards("widgets", table.expected);
    expect(reached.map((m) => m.title)).toEqual(["M4b -- 1.5.0", "M2 -- 1.3.0"]);
    localStorage.setItem(AWARD_SEEN_KEY, JSON.stringify(["widgets:M4b -- 1.5.0"]));
    expect(awardStage("widgets", reached[0])).toBe("awarded");
    expect(pendingAwards("widgets", table.expected).map((m) => m.title)).toEqual(["M2 -- 1.3.0"]);
    const empty = table.expected.filter((m) => m.open + m.closed === 0);
    expect(empty.map((m) => awardStage("widgets", m))).toEqual(["empty", "empty"]);
    localStorage.clear();
    resetCelebrateMemory();
  });

  // "How do you want to work in <Space>?" (docs/SCENARIOS.md, the "How do
  // I…" section): one row per kind of Space, Team Agile's own switch on. The
  // agent resolves the answer and serves features.solitaireAgile with the gate
  // applied (Tests/fixtures/how-i-work/table.json, both halves); the web draws
  // the radios from /env howIWork and mounts the tab from the flag it is served.
  it("How do you want to work in <Space>?: the tracker says which answers there are, and the tab follows", () => {
    const entry = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    const cases: [string, Tracker, string, boolean][] = [
      ["GitHub, nobody has answered", "github", "alone", false],
      ["GitHub, With agents", "github", "agents", false],
      ["GitHub, Alone", "github", "alone", false],
      ["Azure DevOps", "ado", "team", true],
      ["no tracker", "none", "alone", true],
    ];
    const grid = cases.map(([name, tracker, answer, locked]) => {
      const e = env({
        status: "active",
        tier: 1,
        tracker,
        // What the agent serves: the switch is on, the gate is applied.
        features: { solitaireAgile: answer === "agents" },
      });
      const checked = entry.answers!.find((a) => a.value === answer)!.label;
      const live = entry.answers!.filter((a) => answerLive(a, tracker, locked)).map((a) => a.label);
      const writes = live.length ? `${answerTarget(entry, "x")}=<answer> -Hub` : "nothing";
      return [name, checked, live, entry.why?.[tracker], writes, see(e).nav.includes("Team Agile")];
    });
    expect(grid).toEqual([
      [
        "GitHub, nobody has answered",
        "Alone",
        ["With agents", "Alone"],
        "On a team in Azure is an Azure DevOps Space's answer; this Space's tracker is GitHub.",
        "spaces.x.howIWork=<answer> -Hub",
        false,
      ],
      [
        "GitHub, With agents",
        "With agents",
        ["With agents", "Alone"],
        "On a team in Azure is an Azure DevOps Space's answer; this Space's tracker is GitHub.",
        "spaces.x.howIWork=<answer> -Hub",
        true,
      ],
      [
        "GitHub, Alone",
        "Alone",
        ["With agents", "Alone"],
        "On a team in Azure is an Azure DevOps Space's answer; this Space's tracker is GitHub.",
        "spaces.x.howIWork=<answer> -Hub",
        false,
      ],
      [
        "Azure DevOps",
        "On a team in Azure",
        [],
        "Their board holds the rituals; Team Agile is off here.",
        "nothing",
        false,
      ],
      [
        "no tracker",
        "Alone",
        [],
        "Connect a tracker to unlock working with agents.",
        "nothing",
        false,
      ],
    ]);
  });

  it("every module with a flag is named by the Modules card's list, on or off", () => {
    const flagged = modules.filter((m) => m.feature).map((m) => m.feature);
    expect(flagged).toEqual([
      "growth",
      "communication",
      "deck",
      "organize",
      "solitaireAgile",
      "lounge",
    ]);
  });
});

// The avatar menu's Space entry, by how many Spaces there are
// (docs/SCENARIOS.md, "The avatar menu's Space entry, by count"). The detail --
// typing, Enter, View all, Escape -- is AvatarMenu.test.tsx's.
describe("the scenario grid: the avatar menu's Space entry, by count", () => {
  const at = async (n: number) => {
    const spaces = Array.from({ length: n }, (_, i) => ({ slug: `s${i}`, name: `Space ${i}` }));
    const view = render(
      <AvatarMenu
        unsaved={0}
        spaces={spaces}
        activeSpace="s0"
        onSwitchSpace={() => {}}
        links={[]}
        onOpenSettings={() => {}}
        restoreFocusTarget={{}}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "You and your settings" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Space/ }));
    await screen.findAllByRole(n > SPACE_QUICK_MENU_THRESHOLD ? "combobox" : "menuitemradio");
    const seen = {
      submenu: screen.queryAllByRole("menuitemradio").length,
      quickMenu: screen.queryByRole("combobox") !== null,
      rows: screen.queryAllByRole("option").length,
      viewAll: screen.queryByRole("button", { name: "View all" }) !== null,
    };
    view.unmount();
    return seen;
  };

  it("at the threshold: today's submenu, one radio row per Space", async () => {
    expect(await at(SPACE_QUICK_MENU_THRESHOLD)).toEqual({
      submenu: SPACE_QUICK_MENU_THRESHOLD,
      quickMenu: false,
      rows: 0,
      viewAll: false,
    });
  });

  it("past it: the quick menu, a short list of the threshold's rows and View all", async () => {
    expect(await at(SPACE_QUICK_MENU_THRESHOLD + 1)).toEqual({
      submenu: 0,
      quickMenu: true,
      rows: SPACE_QUICK_MENU_THRESHOLD,
      viewAll: true,
    });
  });
});

// The Studio's Spaces card, by kind of Space (docs/SCENARIOS.md, "The
// Studio's foyer"): which tag of the card's filter row lists a Space.
// One row per kind the rule tells apart; the card itself is FoyerCard.test.tsx's.
describe("the scenario grid: the Spaces card's filter, by kind of Space", () => {
  const sp = (o: Partial<SpaceInfo>): SpaceInfo => ({
    slug: "s",
    name: "S",
    status: "active",
    ...o,
  });
  it.each<[string, SpaceInfo, SpaceBucket]>([
    ["a GitHub Space of your own", sp({ tracker: "github" }), "products"],
    ["an Azure DevOps Space", sp({ tracker: "ado" }), "work"],
    ["your own cards, no tracker", sp({ tracker: "none", status: "local" }), "work"],
    [
      "a shipped demo, GitHub's included",
      sp({ tracker: "github", status: "local", example: true }),
      "outOfBox",
    ],
    ["an archived Space, of any kind", sp({ tracker: "github", status: "archive" }), "archive"],
  ])("%s", (_why, space, bucket) => {
    expect(spaceBucket(space)).toBe(bucket);
    // All lists it too, and no other entry does.
    for (const f of SPACES_FILTERS) {
      expect(filterSpaces([space], f.value)).toHaveLength(
        f.value === "all" || f.value === bucket ? 1 : 0,
      );
    }
  });
});

// The end of a Space's life, on its row (docs/SCENARIOS.md, "The Studio's
// foyer"): what the row's `...` offers. The confirm is SpaceLifecycleDialog.test.tsx's.
describe("the scenario grid: Retire and Remove in a Space's row menu", () => {
  const sp = (o: Partial<SpaceInfo>): SpaceInfo => ({
    slug: "s",
    name: "S",
    status: "active",
    ...o,
  });
  it.each<[string, SpaceInfo, boolean, SpaceLifecycleAction[]]>([
    ["another Space, active or local", sp({ status: "local" }), false, ["retire", "remove"]],
    ["the Space you are in", sp({}), true, ["retire"]],
    ["an archived Space you are not in", sp({ status: "archive" }), false, ["remove"]],
    ["an archived Space you are in", sp({ status: "archive" }), true, []],
  ])("%s", (_why, space, here, actions) => {
    expect(spaceLifecycleActions(space, here)).toEqual(actions);
  });
});

// A GitHub row's meta line, by its repository's visibility (docs/SCENARIOS.md,
// "The Studio's foyer"): the agent's word leads the line. One row per answer; an
// Azure DevOps row, or one with no tracker, is never given one (FoyerCard.test.tsx).
describe("the scenario grid: a GitHub row's line, by its repository's visibility", () => {
  it.each<[string, string, string]>([
    ["a public repository", VISIBILITY.public, "Public; 4 open"],
    ["a private one (gh's INTERNAL included)", VISIBILITY.private, "Private; 4 open"],
    ["a tracker that did not answer", VISIBILITY.unknown, "Visibility unknown; 4 open"],
  ])("%s", (_why, word, line) => {
    expect(githubRowLine(visibilityLabel(word), "4 open")).toBe(line);
  });

  // A GitHub Space not connected yet was never asked, so its line has no
  // visibility word at all; `Visibility unknown` is for a connected one.
  it.each<[string, SpaceInfo, boolean]>([
    [
      "connected (active): asked",
      { slug: "s", name: "S", status: "active", tracker: "github" },
      true,
    ],
    [
      "not connected yet (local): not asked, no word",
      { slug: "s", name: "S", status: "local", tracker: "github" },
      false,
    ],
  ])("%s", (_why, space, asks) => {
    expect(readsVisibility(space)).toBe(asks);
  });
});

// The Studio's Prompts card, by how you work on the Space (docs/SCENARIOS.md,
// "The Studio's Prompts card"): the Space's answer, as /env's howIWork carries
// it, picks the ToolKit filter's rows out of the REAL index, agentic/prompts.json;
// the rest are counted in the card's info tip. The add-ons' prompts follow their
// flags in the agent (Tests/test_studio_prompts.py), so the grid reads the core's.
describe("the scenario grid: the Studio's Prompts card, by how you work", () => {
  type Entry = { workflows: PromptWorkflow[]; module: string; sender: string };
  const index = JSON.parse(
    fs.readFileSync(path.join(__dirname, "..", "..", "..", "agentic", "prompts.json"), "utf8"),
  ).prompts as Record<string, Entry>;
  const rows = Object.entries(index)
    .filter(([, e]) => e.module === "core")
    .map(
      ([name, e]) =>
        ({ name, ref: name, group: "toolkit", workflows: e.workflows }) as unknown as PromptRow,
    );
  // A Space as /env serves it: its tracker, and the answer the agent worked out for it.
  const space = (
    tracker: Tracker,
    answer: HowIWork["answer"],
    source: HowIWork["source"],
    features: Record<string, boolean> = {},
  ): EnvStatus => ({
    ...env({ status: "active", tier: 1, tracker, features }),
    howIWork: { answer, source, tracker, locked: tracker !== "github" },
  });
  const ALONE = ["build", "new-issue", "pr-review", "pr-suggest"];
  const TEAM = [
    "ado-comments",
    "build",
    "new-bug",
    "new-user-story",
    "pr-publish",
    "pr-review",
    "pr-ship",
    "pr-suggest",
  ];

  it.each<[string, EnvStatus, string, string[], number]>([
    [
      "a GitHub Space nobody has answered for: alone",
      space("github", "alone", "default"),
      "alone",
      ALONE,
      5,
    ],
    ["a GitHub Space answered alone", space("github", "alone", "chosen"), "alone", ALONE, 5],
    [
      "a GitHub Space answered with agents",
      space("github", "agents", "chosen"),
      "agents",
      ALONE,
      5,
    ],
    ["an Azure DevOps Space: on a team in Azure", space("ado", "team", "derived"), "team", TEAM, 1],
    ["your own cards: alone", space("none", "alone", "derived"), "alone", ALONE, 5],
    [
      "Team Agile's switch on, a GitHub Space answered alone: the answer decides",
      space("github", "alone", "chosen", { solitaireAgile: true }),
      "alone",
      ALONE,
      5,
    ],
  ])("%s", (_why, e, workflow, shown, others) => {
    const sets = promptSets(rows, spaceWorkflow(e));
    expect(spaceWorkflow(e)).toBe(workflow);
    expect(sets.toolkit.map((r) => r.name).sort()).toEqual(shown);
    expect(sets.others).toBe(others);
  });
});

// A card's `...`, by the Organize flag (docs/SCENARIOS.md, "A card's menu, by the
// Organize flag"): the one action model the board and the list both draw. The
// dialog the item opens is Board.remind.test.tsx's.
describe("the scenario grid: a card's menu, by the Organize flag", () => {
  const card = {
    status: "Active",
    linked: false,
    ado_url: null,
    pr_url: null,
    billable: true,
    commits: 0,
  };
  it.each<[string, EnvStatus, string]>([
    [
      "organize off",
      env({ status: "local", tier: 3, tracker: "none", features: {} }),
      "Mark not billable",
    ],
    [
      "organize on",
      env({ status: "local", tier: 3, tracker: "none", features: { organize: true } }),
      "Remind me about this",
    ],
  ])("%s", (_why, e, last) => {
    const menu = cardActions(card, {
      adoEnabled: false,
      cliPrefix: "tk",
      organize: Boolean(e.features?.organize),
    }).secondary.map((a) => a.label);
    expect(menu[menu.length - 1]).toBe(last);
    expect(menu.filter((l) => l === "Remind me about this")).toHaveLength(
      e.features?.organize ? 1 : 0,
    );
  });
});

// The board's lanes, by a card's status (docs/SCENARIOS.md, "The board's lanes,
// by a card's status"): five lanes, Backlog first, and what a drop may do from
// each -- the one rule the drop targets and the "Move to" menu both read.
describe("the scenario grid: the board's lanes, by a card's status", () => {
  it("five lanes, Backlog first, Done last", () => {
    expect([...LANES]).toEqual(["Backlog", "Active", "In Progress", "Code Review", "Done"]);
  });
  it.each<[string, string[], Array<[string, string]>]>([
    ["Backlog", ["Active", "In Progress", "Code Review", "Done"], []],
    ["Active", ["Backlog", "In Progress", "Code Review", "Done"], []],
    [
      "In Progress",
      ["Code Review", "Done"],
      [
        ["Backlog", "Threaded work is in play, not backlog."],
        ["Active", "A card travels one way."],
      ],
    ],
    [
      "Code Review",
      ["Done"],
      [
        ["Backlog", "Threaded work is in play, not backlog."],
        ["Active", "A card travels one way."],
        ["In Progress", "A card travels one way."],
      ],
    ],
    ["Done", [], [["Backlog", "A card travels one way."]]],
  ])("a %s card", (status, moves, refused) => {
    expect(legalMoves(status)).toEqual(moves);
    for (const [lane, why] of refused) {
      expect(whyNotAMove(status, lane as (typeof LANES)[number])).toBe(why);
    }
  });
  it("the foyer counts the cards in play, and says the planned ones after the count", () => {
    const st = {
      count: 3,
      prompts: [{ status: "Backlog" }, { status: "Active" }, { status: "Backlog" }],
    } as unknown as StatusResponse;
    expect(cardsPhrase(st)).toBe("1 card in play: 1 Active; 2 in Backlog");
  });
});

// The Demo board on a fresh Start (docs/SCENARIOS.md, "The Demo board on a fresh
// Start"): five tutorial cards, the first in Backlog and four in To do, each
// finished by a move the board already allows. The lanes' names are the sample
// hub's own (samples/hub/hub.json); the statuses are what the agent serves for
// an untouched copy (Tests/test_first_run.py) and the CLI derives
// (Tests/Test-Start.ps1, which also walks each act).
describe("the scenario grid: the Demo board on a fresh Start", () => {
  const sampleHub = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "../../../samples/hub/hub.json"), "utf8"),
  ) as { spaces: Array<{ slug: string; laneNames?: Record<string, string> }> };
  const field = sampleHub.spaces.find((sp) => sp.slug === "demo")?.laneNames ?? {};
  // /env serves laneNames keyed by the contract's word; the hub writes the field's.
  const names = Object.fromEntries(
    Object.entries(LANE_FIELD_KEY)
      .filter(([, key]) => field[key] !== undefined)
      .map(([word, key]) => [word, field[key]]),
  );
  it.each<[string, string, string, string, string]>([
    ["Start here: pull me onto the board", "Backlog", "Backlog", "Active", "To do"],
    ["Open me and tick my boxes", "Active", "To do", "Done", "Done"],
    ["Find out one thing and write it down", "Active", "To do", "Done", "Done"],
    ['Say "look at this"', "Active", "To do", "Code Review", "Waiting"],
    ["Drop me on Done", "Active", "To do", "Done", "Done"],
  ])(
    "%s: a fresh Start draws it in %s (%s); its move to %s (%s) is one the board allows",
    (_card, status, shown, to, toShown) => {
      expect(laneLabel(names, status)).toBe(shown);
      expect(legalMoves(status)).toContain(to);
      expect(laneLabel(names, to)).toBe(toShown);
    },
  );
});

// The WIP line on the board's Active column, by `limits.inPlay` and the cards in
// play (docs/SCENARIOS.md, "The board's Active column, by the WIP limit"): a line
// the board says, never a gate. The render is Board.inPlay.test.tsx's.
describe("the scenario grid: the Active column's WIP line, by the limit", () => {
  const inPlay = (n: number) =>
    Array.from({ length: n }, (_v, i) => ({
      status: ["Active", "In Progress", "Code Review"][i % 3],
    }));
  it.each<[string, number, number | null | undefined, string | null, boolean]>([
    ["no limit set", 7, undefined, null, false],
    ["under the limit", 4, 5, "in play 4", false],
    ["at the limit", 5, 5, "in play 5", false],
    ["past the limit", 7, 5, "in play 7 of 5", true],
  ])("%s", (_name, cards, limit, text, past) => {
    const line = inPlayLine(countInPlay(inPlay(cards)), limit);
    expect(line?.text ?? null).toBe(text);
    expect(line?.past ?? false).toBe(past);
  });
  it("the backlog and Done are not in play", () => {
    expect(countInPlay([{ status: "Backlog" }, { status: "Done" }, { status: "Active" }])).toBe(1);
  });
});
