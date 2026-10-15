import { DateTime } from "luxon";
import {
  CONNECT_ADO,
  CONNECT_GITHUB,
  CONNECT_NONE,
  SPACES_FILTERS,
  cardsLine,
  cardsPhrase,
  dayAge,
  deployPhrase,
  filterSpaces,
  foyerLine,
  foyerSpaces,
  githubRowLine,
  isGithubRow,
  isSpacesFilter,
  issuesPhrase,
  readsCards,
  readsVisibility,
  spaceBucket,
  spaceKind,
  spaceLifecycleActions,
  spacesFilterEmpty,
} from "./foyer";
import type { SpaceBucket, SpaceLifecycleAction, SpacesFilter } from "./foyer";
import { STUDIO_PAGE_SIZE } from "./paths";
import { visibilityLabel } from "../../shared/visibility";
import type { EnvStatus, SpaceInfo } from "../../shell/api";
import type { DeploysResponse, IssueReport, StatusResponse } from "../ado/api.ado";

// The foyer's words, as a table (Studio S2b; D-S13 for the rows that are not
// GitHub's). One row per shape the rule distinguishes; the spec's own example
// is the first row of foyerLine.
const NOW = DateTime.fromISO("2026-10-01T10:00:00");

function report(o: Partial<IssueReport> = {}): IssueReport {
  return {
    supported: true,
    open: 0,
    closed: 0,
    closed_recent: 0,
    sev: {},
    kind: {},
    milestones: [],
    ...o,
  };
}
function deploys(
  runs: Partial<DeploysResponse["runs"][number]>[],
  o: Partial<DeploysResponse> = {},
): DeploysResponse {
  return {
    supported: true,
    runs: runs.map((r) => ({
      repo: "r",
      title: "CI",
      status: "completed",
      conclusion: "success",
      branch: "main",
      when: "2026-09-28",
      url: "",
      ...r,
    })),
    ...o,
  };
}

describe("which Spaces get a row", () => {
  it("every one /env offers, in its order (D-S13); only a GitHub one reads the tracker, and nothing is derived here", () => {
    const env = {
      config: {
        spaces: [
          { slug: "toolkit", name: "Toolkit", status: "active", tracker: "github" },
          { slug: "acme", name: "Acme", status: "active", tracker: "ado" },
          { slug: "demo", name: "Demo", status: "local", tracker: "none" },
          { slug: "wasteland", name: "Wasteland", status: "active", tracker: "github" },
          // An older agent sends no tracker: no row, rather than a guess from the address.
          { slug: "old", name: "Old", status: "active", org: "https://github.com/o/r" },
        ],
      },
    } as unknown as EnvStatus;
    const rows = foyerSpaces(env);
    expect(rows.map((s) => s.slug)).toEqual(["toolkit", "acme", "demo", "wasteland", "old"]);
    expect(rows.filter(isGithubRow).map((s) => s.slug)).toEqual(["toolkit", "wasteland"]);
    expect(rows.map(spaceKind)).toEqual([
      "GitHub",
      "Azure DevOps",
      "Your own cards",
      "GitHub",
      "Your own cards",
    ]);
    expect(foyerSpaces(undefined)).toEqual([]);
  });
});

// The end of a Space's life on its row: Retire unless it is archived,
// Remove unless you are in it -- the verb refuses the rest in its own words.
describe("what a row's menu offers for the end of a Space's life", () => {
  it.each<[string, Partial<SpaceInfo>, boolean, SpaceLifecycleAction[]]>([
    ["a Space you are not in", { status: "active" }, false, ["retire", "remove"]],
    ["the Space you are in: no Remove", { status: "active" }, true, ["retire"]],
    ["an archived Space: no Retire", { status: "archive" }, false, ["remove"]],
    ["archived, and the one you are in: neither", { status: "archive" }, true, []],
    [
      "a shipped demo: both offered, the verb says why it stays",
      { status: "local", example: true },
      false,
      ["retire", "remove"],
    ],
  ])("%s", (_why, partial, here, actions) => {
    expect(
      spaceLifecycleActions(
        { slug: "s", name: "S", status: "active", ...partial } as SpaceInfo,
        here,
      ),
    ).toEqual(actions);
  });
});

// The Spaces card's filter: one Space, one bucket, the first rule that
// fits. One row per kind of Space the rule tells apart.
describe("which bucket a Space is in", () => {
  it.each<[string, Partial<SpaceInfo>, SpaceBucket]>([
    ["a GitHub Space, connected", { tracker: "github", status: "active" }, "products"],
    ["a GitHub Space, local", { tracker: "github", status: "local" }, "products"],
    [
      "an archived GitHub Space is Archive, not Products",
      { tracker: "github", status: "archive" },
      "archive",
    ],
    [
      "an archived example is Archive, not Out of box",
      { tracker: "none", status: "archive", example: true },
      "archive",
    ],
    [
      "a local GitHub example is Out of box, not Products",
      { tracker: "github", status: "local", example: true },
      "outOfBox",
    ],
    [
      "an example with no tracker (Demo)",
      { tracker: "none", status: "local", example: true },
      "outOfBox",
    ],
    [
      "example: false is not an example",
      { tracker: "github", status: "active", example: false },
      "products",
    ],
    ["an Azure DevOps Space", { tracker: "ado", status: "active" }, "work"],
    ["an Azure DevOps Space, archived", { tracker: "ado", status: "archive" }, "archive"],
    ["your own cards, no tracker", { tracker: "none", status: "local" }, "work"],
    ["an older agent sent no tracker", { tracker: undefined, status: "active" }, "work"],
  ])("%s", (_why, o, want) => {
    expect(spaceBucket(space(o))).toBe(want);
  });

  const HUB = [
    space({ slug: "toolkit", tracker: "github" }),
    space({ slug: "globex", tracker: "ado", status: "archive" }),
    space({ slug: "demo", tracker: "none", status: "local", example: true }),
    space({ slug: "demoorg", tracker: "none", status: "local" }),
  ];

  it.each<[SpacesFilter, string[]]>([
    ["all", ["toolkit", "globex", "demo", "demoorg"]],
    ["products", ["toolkit"]],
    ["work", ["demoorg"]],
    ["outOfBox", ["demo"]],
    ["archive", ["globex"]],
  ])("the %s filter shows its Spaces, in the list's order", (filter, want) => {
    expect(filterSpaces(HUB, filter).map((s) => s.slug)).toEqual(want);
  });

  it("the dropdown: five entries, All first, no Hidden", () => {
    expect(SPACES_FILTERS.map((f) => f.label)).toEqual([
      "All",
      "Products",
      "Work",
      "Out of box",
      "Archive",
    ]);
  });

  it.each<[string, boolean]>([
    ["all", true],
    ["archive", true],
    ["outOfBox", true],
    ["hidden", false],
    ["Products", false],
    ["", false],
  ])("a stored %p is a filter the tags offer: %p", (value, want) => {
    expect(isSpacesFilter(value)).toBe(want);
  });

  it.each<[SpacesFilter, string]>([
    ["all", "No Spaces"],
    ["products", "No product Spaces"],
    ["work", "No work Spaces"],
    ["outOfBox", "No out-of-box Spaces"],
    ["archive", "No archived Spaces"],
  ])("an empty %s filter names itself", (filter, want) => {
    expect(spacesFilterEmpty(filter)).toBe(want);
  });
});

describe("the issues half", () => {
  it.each([
    ["still reading", undefined, null],
    ["not connected: what connecting would show", report({ supported: false }), CONNECT_GITHUB],
    ["gh's own sentence", report({ reason: "o/r: gh did not answer" }), "o/r: gh did not answer"],
    ["nothing open", report(), "no open issues"],
    [
      "open and closed this week",
      report({ open: 4, closed_recent: 2 }),
      "4 open, 2 closed this week",
    ],
    ["a sev1 is named", report({ open: 3, sev: { sev1: 1, sev2: 2 } }), "3 open, 1 sev1 open"],
  ])("%s", (_why, r, want) => {
    expect(issuesPhrase(r)).toBe(want);
  });
});

describe("the deploy half", () => {
  it.each([
    ["no answer yet", undefined, ""],
    ["unsupported", deploys([], { supported: false }), ""],
    ["gh did not answer", deploys([], { reason: "nope" }), ""],
    ["no runs", deploys([]), "no deploys yet"],
    ["green, three days ago", deploys([{ when: "2026-09-28" }]), "last deploy 3 days ago, green"],
    [
      "red, yesterday",
      deploys([{ when: "2026-09-30", conclusion: "failure" }]),
      "last deploy yesterday, red",
    ],
    [
      "running, today",
      deploys([{ when: "2026-10-01", conclusion: "", status: "in_progress" }]),
      "last deploy today, running",
    ],
    [
      "cancelled",
      deploys([{ when: "2026-10-01", conclusion: "cancelled" }]),
      "last deploy today, cancelled",
    ],
  ])("%s", (_why, d, want) => {
    expect(deployPhrase(d, NOW)).toBe(want);
  });

  it("a day in words", () => {
    expect(dayAge("2026-10-01", NOW)).toBe("today");
    expect(dayAge("2026-09-30", NOW)).toBe("yesterday");
    expect(dayAge("2026-09-21", NOW)).toBe("10 days ago");
    expect(dayAge("not a day", NOW)).toBe("not a day");
  });
});

describe("the whole line", () => {
  it("the spec's own example: a product with nothing to say says so in one line", () => {
    expect(foyerLine(report(), deploys([{ when: "2026-09-28" }]), NOW)).toBe(
      "no open issues; last deploy 3 days ago, green",
    );
  });

  it("no deploy half when the issues were not read", () => {
    expect(foyerLine(report({ supported: false }), deploys([{ when: "2026-09-28" }]), NOW)).toBe(
      CONNECT_GITHUB,
    );
  });

  it("null while the issues are still being read", () => {
    expect(foyerLine(undefined, deploys([]), NOW)).toBeNull();
  });
});

// A GitHub row's line leads with its repository's visibility, as the
// word the shared label gives for the agent's answer -- one row per shape.
describe("a GitHub row's line, led by its visibility", () => {
  it.each<[string, string, string | null]>([
    ["public", "no open issues", "Public; no open issues"],
    ["private", "4 open; last deploy today, green", "Private; 4 open; last deploy today, green"],
    ["unknown", CONNECT_GITHUB, `Visibility unknown; ${CONNECT_GITHUB}`],
    ["", "no open issues", "no open issues"],
  ])("%p", (word, facts, line) => {
    expect(githubRowLine(visibilityLabel(word), facts)).toBe(line);
  });

  it("null while either half is still being read", () => {
    expect(githubRowLine(null, "no open issues")).toBeNull();
    expect(githubRowLine("Public", null)).toBeNull();
  });
});

// Which rows ask their repository's visibility: a connected GitHub Space
// only. One not connected yet is not asked, so its line has no visibility word.
describe("which rows ask their visibility", () => {
  it.each<[string, Partial<SpaceInfo>, boolean]>([
    ["a connected GitHub Space", { tracker: "github", status: "active" }, true],
    ["a GitHub Space not connected yet", { tracker: "github", status: "local" }, false],
    ["an archived GitHub Space", { tracker: "github", status: "archive" }, false],
    ["an Azure DevOps Space", { tracker: "ado", status: "active" }, false],
    ["a Space with no tracker", { tracker: "none", status: "local" }, false],
    ["an older agent's Space, no tracker field", { tracker: undefined, status: "active" }, false],
  ])("%s", (_why, o, asks) => {
    expect(readsVisibility(space(o))).toBe(asks);
  });

  it("a row that is not asked leads with nothing", () => {
    expect(githubRowLine("", CONNECT_GITHUB)).toBe(CONNECT_GITHUB);
  });

  it("the three Studio cards page five at a time", () => {
    expect(STUDIO_PAGE_SIZE).toBe(5);
  });
});

function status(lanes: string[]): StatusResponse {
  return {
    count: lanes.length,
    prompts: lanes.map((l) => ({ status: l })),
  } as unknown as StatusResponse;
}
function space(o: Partial<SpaceInfo>): SpaceInfo {
  return { slug: "s", name: "S", status: "active", tracker: "ado", ...o };
}

describe("the cards half (an Azure DevOps row, or one with no tracker)", () => {
  it.each([
    ["no cards", status([]), undefined, "no cards in play"],
    ["one card", status(["Active"]), undefined, "1 card in play: 1 Active"],
    [
      "by lane, in board order",
      status(["Code Review", "Active", "Active"]),
      undefined,
      "3 cards in play: 2 Active, 1 Code Review",
    ],
    [
      "under the Space's own lane names",
      status(["Active", "In Progress"]),
      { Active: "To do", "In Progress": "Doing" },
      "2 cards in play: 1 To do, 1 Doing",
    ],
    [
      "a lane the contract does not know is counted, not named",
      status(["Odd"]),
      undefined,
      "1 card in play",
    ],
  ])("%s", (_why, st, names, want) => {
    expect(cardsPhrase(st, names)).toBe(want);
  });
});

describe("which non-GitHub rows read their cards", () => {
  it.each<[string, Partial<SpaceInfo>, boolean, boolean]>([
    ["the Space you are in", { status: "active" }, true, true],
    ["the Space you are in, archived", { status: "archive" }, true, true],
    ["another Space, connected", { status: "active" }, false, true],
    ["another Space, local", { status: "local", tracker: "none" }, false, true],
    ["another Space, archived: not asked", { status: "archive" }, false, false],
  ])("%s", (_why, o, here, want) => {
    expect(readsCards(space(o), here)).toBe(want);
  });
});

describe("a row that is not GitHub's", () => {
  it.each<[string, SpaceInfo, boolean, StatusResponse | undefined, string]>([
    ["ADO, connected", space({}), true, status(["Active"]), "1 card in play: 1 Active"],
    [
      "ADO, not connected",
      space({ status: "local" }),
      true,
      status([]),
      `no cards in play; ${CONNECT_ADO}`,
    ],
    [
      "no tracker",
      space({ tracker: "none", status: "local" }),
      true,
      status(["Active"]),
      `1 card in play: 1 Active; ${CONNECT_NONE}`,
    ],
    [
      "not read, not connected: still taught",
      space({ status: "local" }),
      false,
      undefined,
      `go in to see its cards; ${CONNECT_ADO}`,
    ],
    [
      "archived and not read: no teaching",
      space({ tracker: "none", status: "archive" }),
      false,
      undefined,
      "go in to see its cards",
    ],
    [
      "archived and read (you are in it): its cards, no teaching",
      space({ tracker: "none", status: "archive" }),
      true,
      status([]),
      "no cards in play",
    ],
    [
      "an older agent sent no tracker: no guess",
      space({ tracker: undefined }),
      true,
      status(["Code Review"]),
      "1 card in play: 1 Code Review",
    ],
  ])("%s", (_why, sp, reads, st, want) => {
    expect(cardsLine(sp, reads, st)).toBe(want);
  });

  it("another Space's cards under ITS lane names", () => {
    const demo = space({
      tracker: "none",
      status: "local",
      laneNames: { Active: "To do", "In Progress": "Doing" },
    });
    expect(cardsLine(demo, true, status(["Active", "In Progress"]), demo.laneNames)).toBe(
      `2 cards in play: 1 To do, 1 Doing; ${CONNECT_NONE}`,
    );
  });

  it("null while a row's cards are still being read", () => {
    expect(cardsLine(space({}), true, undefined)).toBeNull();
  });
});
