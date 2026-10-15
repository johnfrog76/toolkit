import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { FoyerCard, SPACES_FILTER_KEY } from "./FoyerCard";

// The foyer (Studio S2b, D-S2 as amended by D-S13): one row per Space -- every
// Space, whatever its tracker. A GitHub row is read for THAT Space
// through the `space` argument; any other row reads its cards from the core's
// /api/status, for the Space you are in only. A row is the switch into it. The
// words are foyer.test.ts's; here the rows, the reads and the door.
const askedReport: string[] = [];
const askedDeploys: string[] = [];
const askedStatus: boolean[] = [];
const askedSpaceStatus: string[] = [];
let failingSpaceStatus: string[] = [];
const switched: string[] = [];
let switchFails = false;
// The repository's visibility per Space: an answer, or a failed read.
const askedVisibility: string[] = [];
let visibilityOf: Record<string, string> = {};
let failingVisibility: string[] = [];

// One clean load: a read named here has not answered yet.
let pending: string[] = [];
// Refresh: what was asked again.
const refetched: string[] = [];
const refreshedVisibility: string[] = [];
// A GitHub Space whose tracker has nothing to say (not connected yet).
let unsupportedReport: string[] = [];

let envAnswer: unknown;
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: envAnswer, isLoading: false }),
  useGetSpaceVisibilityQuery: (space: string, opts?: { skip?: boolean }) => {
    if (opts?.skip) return { data: undefined };
    askedVisibility.push(space);
    if (pending.includes(`visibility:${space}`)) return { data: undefined, isFetching: true };
    if (failingVisibility.includes(space)) return { data: undefined, error: { status: 500 } };
    return { data: { supported: true, visibility: visibilityOf[space] ?? "unknown", repos: [] } };
  },
  useRefreshSpaceVisibilityMutation: () => [
    (space: string) => refreshedVisibility.push(space),
    { isLoading: false },
  ],
  useSwitchModeMutation: () => [
    ({ mode }: { mode: string }) => {
      switched.push(mode);
      return {
        unwrap: () => (switchFails ? Promise.reject(new Error("no")) : Promise.resolve({})),
      };
    },
    { isLoading: false },
  ],
}));
jest.mock("./api.studio", () => ({
  useGetSpaceIssueReportQuery: (space: string) => {
    askedReport.push(space);
    const refetch = () => refetched.push(`report:${space}`);
    if (pending.includes(`report:${space}`)) return { data: undefined, isFetching: true, refetch };
    if (unsupportedReport.includes(space)) return { data: { supported: false }, refetch };
    return {
      data: {
        supported: true,
        open: space === "toolkit" ? 4 : 0,
        closed: 0,
        closed_recent: 0,
        sev: {},
        kind: {},
        milestones: [],
      },
      // A refetch in flight keeps the answer it had, as RTK Query does.
      isFetching: pending.includes(`refetching:report:${space}`),
      refetch,
    };
  },
  useGetSpaceDeploysQuery: (space: string) => {
    askedDeploys.push(space);
    return {
      data: { supported: true, runs: [] },
      refetch: () => refetched.push(`deploys:${space}`),
    };
  },
  useGetSpaceStatusQuery: (space: string, opts: { skip?: boolean }) => {
    if (opts?.skip) return { data: undefined };
    askedSpaceStatus.push(space);
    const refetch = () => refetched.push(`status:${space}`);
    if (pending.includes(`status:${space}`)) return { data: undefined, isFetching: true, refetch };
    if (failingSpaceStatus.includes(space))
      return { data: undefined, error: { status: 500 }, refetch };
    return {
      data: {
        count: 3,
        prompts: [{ status: "Active" }, { status: "Active" }, { status: "Code Review" }],
      },
      refetch,
    };
  },
  // The + and its dialog are NewSpaceDialog.test.tsx's subject; here they
  // only have to be there, closed.
  useGetSpaceCandidatesQuery: () => ({}),
  useGetTypedSpaceCandidateQuery: () => ({}),
  useRunNewSpaceMutation: () => [jest.fn(), { isLoading: false }],
  // Retire and Remove: the confirm is SpaceLifecycleDialog.test.tsx's
  // subject; here the preview answers so the dialog can be seen to open.
  usePreviewSpaceLifecycleMutation: () => [mockPreviewLifecycle, { isLoading: false }],
  useRunSpaceLifecycleMutation: () => [jest.fn(), { isLoading: false }],
}));
const lifecycleAsked: string[] = [];
// A stable trigger, as RTK Query's is: the preview runs once, on open.
function mockPreviewLifecycle({ verb }: { verb: string }) {
  lifecycleAsked.push(verb);
  return {
    unwrap: () => Promise.resolve({ status: "success", output: `[WhatIf] ${verb}`, error: null }),
  };
}

jest.mock("../ado/api.ado", () => ({
  useGetStatusQuery: (_arg: unknown, opts: { skip?: boolean }) => {
    askedStatus.push(!opts?.skip);
    return opts?.skip
      ? { data: undefined }
      : {
          data: { count: 2, prompts: [{ status: "Active" }, { status: "In Progress" }] },
          refetch: () => refetched.push("status:here"),
        };
  },
}));

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname}</div>;
}

function tree() {
  return (
    <MemoryRouter initialEntries={["/studio"]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              <FoyerCard />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>
  );
}

function mount() {
  return render(tree());
}

const SPACES = [
  {
    slug: "toolkit",
    name: "Toolkit",
    status: "active",
    tracker: "github",
    org: "https://github.com/johnfrog76/toolkit",
  },
  {
    slug: "acme",
    name: "Acme",
    status: "active",
    tracker: "ado",
    org: "https://dev.azure.com/acme",
  },
  {
    slug: "wasteland",
    name: "Wasteland",
    status: "active",
    tracker: "github",
    org: "https://github.com/johnfrog76/wasteland",
  },
];

// The three demo Spaces a cold Start lands with: Demo (cards only), the GitHub
// demo (an address, not yet connected), the Azure demo (no address yet).
const DEMO = [
  { slug: "azure-demo", name: "Azure demo", status: "local", tracker: "none", org: "" },
  { slug: "demo", name: "Demo", status: "local", tracker: "none", org: "" },
  {
    slug: "github-demo",
    name: "GitHub demo",
    status: "local",
    tracker: "github",
    org: "https://github.com/johnfrog76/recipe-box-demo",
  },
];

describe("the foyer", () => {
  beforeEach(() => {
    askedReport.length = 0;
    askedDeploys.length = 0;
    askedStatus.length = 0;
    askedSpaceStatus.length = 0;
    failingSpaceStatus = [];
    switched.length = 0;
    switchFails = false;
    askedVisibility.length = 0;
    visibilityOf = { toolkit: "public", wasteland: "private" };
    failingVisibility = [];
    pending = [];
    refetched.length = 0;
    refreshedVisibility.length = 0;
    unsupportedReport = [];
    window.localStorage.clear();
    envAnswer = { config: { activeSpace: "acme", spaces: SPACES } };
  });

  it("draws a row for EVERY Space (D-S13), and reads the tracker only for a GitHub one", () => {
    mount();
    expect(screen.getByText("Toolkit")).toBeTruthy();
    expect(screen.getByText("Wasteland")).toBeTruthy();
    expect(screen.getByText("Acme")).toBeTruthy();
    expect(new Set(askedReport)).toEqual(new Set(["toolkit", "wasteland"]));
    expect(new Set(askedDeploys)).toEqual(new Set(["toolkit", "wasteland"]));
    expect(screen.getByText("Public; 4 open; no deploys yet")).toBeTruthy();
    expect(screen.getByText("Private; no open issues; no deploys yet")).toBeTruthy();
    // Acme is the Space you are in: its cards, from /api/status.
    expect(screen.getByText("2 cards in play: 1 Active, 1 In Progress")).toBeTruthy();
    expect(screen.getAllByText("GitHub")).toHaveLength(2);
    expect(screen.getByText("Azure DevOps")).toBeTruthy();
    expect(screen.getByLabelText("3 Spaces").textContent).toBe("3");
  });

  it("a GitHub row's line leads with its repository's visibility; no other row has one", () => {
    mount();
    expect(new Set(askedVisibility)).toEqual(new Set(["toolkit", "wasteland"]));
    // The word is in the meta line, not a pill beside the name.
    expect(screen.queryByText("Public")).toBeNull();
    expect(screen.queryByText("Private")).toBeNull();
    // Acme, Azure DevOps, is not asked and its line says nothing about it.
    expect(screen.getByText("2 cards in play: 1 Active, 1 In Progress")).toBeTruthy();
  });

  it("a tracker that did not answer says the visibility is unknown, never guessed", () => {
    visibilityOf = { toolkit: "unknown" };
    failingVisibility = ["wasteland"];
    mount();
    expect(screen.getByText("Visibility unknown; 4 open; no deploys yet")).toBeTruthy();
    expect(screen.getByText("Visibility unknown; no open issues; no deploys yet")).toBeTruthy();
  });

  it("another Space's row counts its cards in place, by its slug, under ITS lane names", () => {
    const acme = {
      ...SPACES[1],
      laneNames: { Active: "Queued", "In Progress": "Doing", "Code Review": "Checking" },
    };
    envAnswer = {
      config: {
        activeSpace: "toolkit",
        spaces: [SPACES[0], acme, SPACES[2]],
        laneNames: { Active: "Mine" },
      },
    };
    mount();
    // Not the active Space's read: the Space's own, once.
    expect(askedStatus.every((asked) => !asked)).toBe(true);
    expect(new Set(askedSpaceStatus)).toEqual(new Set(["acme"]));
    expect(screen.getByText("3 cards in play: 2 Queued, 1 Checking")).toBeTruthy();
    expect(screen.queryByText(/go in to see its cards/)).toBeNull();
  });

  it("the Space you are in reads the core's own /api/status, not the space argument", () => {
    mount();
    expect(askedStatus.some((asked) => asked)).toBe(true);
    expect(askedSpaceStatus).toEqual([]);
  });

  it("an archived Space you are not in is not asked", () => {
    const globex = {
      slug: "globex",
      name: "Globex",
      status: "archive",
      tracker: "ado",
      org: "https://dev.azure.com/globex",
    };
    envAnswer = { config: { activeSpace: "toolkit", spaces: [SPACES[0], globex] } };
    mount();
    expect(askedSpaceStatus).toEqual([]);
    expect(screen.getByText("go in to see its cards")).toBeTruthy();
  });

  it("a failed read says so on that row only", () => {
    const beta = { slug: "beta", name: "Beta", status: "local", tracker: "none", org: "" };
    failingSpaceStatus = ["acme"];
    envAnswer = { config: { activeSpace: "toolkit", spaces: [SPACES[0], SPACES[1], beta] } };
    mount();
    expect(
      screen.getAllByText("Could not read this Space's cards -- the agent did not answer."),
    ).toHaveLength(1);
    expect(screen.getByText(/^3 cards in play: 2 Active, 1 Code Review; no tracker/)).toBeTruthy();
  });

  it("a cold first run: the three demo Spaces, and nothing reads as an error", () => {
    envAnswer = { config: { activeSpace: "demo", spaces: DEMO } };
    mount();
    expect(screen.getByText("Azure demo")).toBeTruthy();
    expect(screen.getByText("Demo")).toBeTruthy();
    expect(screen.getByText("GitHub demo")).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.queryByText(/could not|error|failed/i)).toBeNull();
  });

  it("a Space that is not connected offers the connect wizard", async () => {
    envAnswer = { config: { activeSpace: "demo", spaces: DEMO } };
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Actions for GitHub demo" }));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: "Connect GitHub demo" }));
    });
    expect(screen.getByTestId("where").textContent).toBe("/connect/github-demo");
  });

  it("a row's menu offers Retire and Remove, the external link still last", async () => {
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Actions for Toolkit" }));
    });
    const items = screen.getAllByRole("menuitem").map((i) => i.textContent);
    expect(items).toEqual(["Retire Toolkit", "Remove Toolkit", "Open on GitHub"]);
  });

  it("the Space you are in offers Retire, never Remove; an archived one Remove, never Retire", async () => {
    envAnswer = {
      config: {
        activeSpace: "acme",
        spaces: [
          ...SPACES,
          { slug: "old", name: "Old", status: "archive", tracker: "none", org: "" },
        ],
      },
    };
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Actions for Acme" }));
    });
    expect(screen.getByRole("menuitem", { name: "Retire Acme" })).toBeTruthy();
    expect(screen.queryByRole("menuitem", { name: "Remove Acme" })).toBeNull();
    await act(async () => {
      fireEvent.keyDown(document.activeElement ?? document.body, { key: "Escape" });
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Actions for Old" }));
    });
    expect(screen.getByRole("menuitem", { name: "Remove Old" })).toBeTruthy();
    expect(screen.queryByRole("menuitem", { name: "Retire Old" })).toBeNull();
  });

  it("Remove opens the house confirm with the verb's own -WhatIf, asked once", async () => {
    lifecycleAsked.length = 0;
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Actions for Wasteland" }));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: "Remove Wasteland" }));
    });
    expect(screen.getByText("Are you sure?")).toBeTruthy();
    expect(screen.getByText("[WhatIf] RemoveSpace")).toBeTruthy();
    expect(lifecycleAsked).toEqual(["RemoveSpace"]);
  });

  it("a row is the switch into its Space, landing on its Issues", async () => {
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Go into Wasteland" }));
    });
    expect(switched).toEqual(["wasteland"]);
    expect(screen.getByTestId("where").textContent).toBe("/");
  });

  it("the Space you are in is marked, and its row goes home without a switch", async () => {
    envAnswer = { config: { activeSpace: "toolkit", spaces: SPACES } };
    mount();
    expect(screen.getByText("you are here")).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Open Toolkit" }));
    });
    expect(switched).toEqual([]);
    expect(screen.getByTestId("where").textContent).toBe("/");
  });

  it("a switch that fails says so, and stays", async () => {
    switchFails = true;
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Go into Toolkit" }));
    });
    expect(screen.getByRole("alert").textContent).toContain("Could not switch to Toolkit");
    expect(screen.getByTestId("where").textContent).toBe("/studio");
  });

  it("with only an Azure DevOps Space, the room is not empty (D-S13)", () => {
    envAnswer = { config: { activeSpace: "acme", spaces: [SPACES[1]] } };
    mount();
    expect(screen.getByText("Acme")).toBeTruthy();
    expect(screen.queryByText("No Spaces yet")).toBeNull();
  });

  it("with no Space at all, says so and nothing more", () => {
    envAnswer = { config: { activeSpace: "", spaces: [] } };
    mount();
    expect(screen.getByText("No Spaces yet")).toBeTruthy();
    expect(screen.queryByText(/A Space is/)).toBeNull();
  });
});

// The card is Spaces, with one filter over the list. The bucket rule
// is foyer.test.ts's table; here the exposed tags (the Reminders card's FilterBadge row), the counts, the empty sentence
// and the remembered choice.
const MIXED = [
  ...SPACES,
  {
    slug: "globex",
    name: "Globex",
    status: "archive",
    tracker: "ado",
    org: "https://dev.azure.com/globex",
  },
  { slug: "demo", name: "Demo", status: "local", tracker: "none", org: "", example: true },
];

describe("the Spaces card's filter", () => {
  const LABELS: Record<string, string> = {
    all: "All",
    products: "Products",
    work: "Work",
    outOfBox: "Out of box",
    archive: "Archive",
  };
  const tag = (value: string) =>
    screen.getByRole("radio", { name: new RegExp(`^${LABELS[value]}( \\d+)?$`) });
  const tags = () => screen.getAllByRole("radio");
  const chosen = () =>
    tags()
      .filter((t) => t.getAttribute("aria-checked") === "true")
      .map((t) => t.textContent?.replace(/\d+$/, "").trim());
  const chip = () => screen.getByLabelText(/^\d+ Spaces$/);
  const choose = (value: string) => fireEvent.click(tag(value));

  beforeEach(() => {
    window.localStorage.clear();
    envAnswer = { config: { activeSpace: "acme", spaces: MIXED } };
  });

  it("is titled Spaces, and opens on All: every Space, the chip the total", () => {
    mount();
    expect(screen.getByText("Spaces")).toBeTruthy();
    expect(screen.queryByText("Products", { selector: "span, h2, h3" })).toBeNull();
    expect(chosen()).toEqual(["All"]);
    // Each tag carries its count; the five are exposed, in order.
    expect(tags().map((t) => t.textContent)).toEqual([
      "All5",
      "Products2",
      "Work1",
      "Out of box1",
      "Archive1",
    ]);
    expect(chip().textContent).toBe("5");
    for (const name of ["Toolkit", "Acme", "Wasteland", "Globex", "Demo"])
      expect(screen.getByText(name)).toBeTruthy();
  });

  it("a populated card carries no helper sentence: the title, the tags and the rows say it", () => {
    mount();
    expect(screen.queryByText(/One row per Space/)).toBeNull();
    expect(screen.queryByText(/A Space is/)).toBeNull();
    expect(screen.queryByText(/all your Spaces/i)).toBeNull();
  });

  it("Products: the GitHub Spaces only, and the header chip stays the total", () => {
    mount();
    choose("products");
    expect(screen.getByText("Toolkit")).toBeTruthy();
    expect(screen.getByText("Wasteland")).toBeTruthy();
    expect(screen.queryByText("Globex")).toBeNull();
    expect(screen.queryByText("Demo")).toBeNull();
    expect(chosen()).toEqual(["Products"]);
    expect(chip().textContent).toBe("5");
  });

  it("is honest: Archive leaves out the Space you are in", () => {
    mount();
    choose("archive");
    expect(screen.getByText("Globex")).toBeTruthy();
    expect(screen.queryByText("Acme")).toBeNull();
    expect(screen.queryByText("you are here")).toBeNull();
  });

  it("an empty filter says so under the tags, an empty bucket shows no number, and the tags and chip stay", () => {
    envAnswer = { config: { activeSpace: "acme", spaces: SPACES } };
    mount();
    choose("archive");
    expect(screen.getByText("No archived Spaces")).toBeTruthy();
    expect(screen.getByText("3 Spaces are under All.")).toBeTruthy();
    expect(screen.queryByText("No Spaces yet")).toBeNull();
    expect(chosen()).toEqual(["Archive"]);
    expect(tag("archive").textContent).toBe("Archive");
    expect(tag("all").textContent).toBe("All3");
    expect(chip().textContent).toBe("3");
  });

  it("the choice is remembered in this browser", () => {
    const first = mount();
    choose("outOfBox");
    first.unmount();
    mount();
    expect(chosen()).toEqual(["Out of box"]);
    expect(screen.getByText("Demo")).toBeTruthy();
    expect(screen.queryByText("Toolkit")).toBeNull();
  });

  it.each([["hidden"], ["Products"], ["nonsense"]])(
    "a stored %p it does not offer reads as All",
    (stored) => {
      window.localStorage.setItem(SPACES_FILTER_KEY, stored);
      mount();
      expect(chosen()).toEqual(["All"]);
      expect(chip().textContent).toBe("5");
    },
  );

  it("a browser that refuses storage still filters, and opens on All", () => {
    const get = jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    const set = jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("denied");
    });
    try {
      mount();
      expect(chosen()).toEqual(["All"]);
      choose("work");
      expect(screen.getByText("Acme")).toBeTruthy();
      expect(screen.queryByText("Toolkit")).toBeNull();
    } finally {
      get.mockRestore();
      set.mockRestore();
    }
  });
});

// The card loads once and whole, reads again only on its Refresh, and
// pages its rows ten at a time.
describe("the Spaces card's load, Refresh and pager", () => {
  const many = (n: number) =>
    Array.from({ length: n }, (_, i) => ({
      slug: `s${String(i + 1).padStart(2, "0")}`,
      name: `Space ${String(i + 1).padStart(2, "0")}`,
      status: "active",
      tracker: "ado",
      org: "https://dev.azure.com/acme",
    }));

  beforeEach(() => {
    window.localStorage.clear();
    pending = [];
    refetched.length = 0;
    refreshedVisibility.length = 0;
    askedVisibility.length = 0;
    unsupportedReport = [];
    failingSpaceStatus = [];
    failingVisibility = [];
    visibilityOf = { toolkit: "public", wasteland: "private" };
    envAnswer = { config: { activeSpace: "acme", spaces: SPACES } };
  });

  it("holds its loading state until every row's reads settle, then draws the list once", () => {
    pending = ["report:wasteland"];
    const view = mount();
    expect(screen.getByText("Reading the Spaces...")).toBeTruthy();
    // Not one row, not even the ones whose reads are in.
    expect(screen.queryByText("Toolkit")).toBeNull();
    expect(screen.queryByText("Acme")).toBeNull();
    pending = [];
    view.rerender(tree());
    expect(screen.queryByText("Reading the Spaces...")).toBeNull();
    expect(screen.getByText("Public; 4 open; no deploys yet")).toBeTruthy();
    expect(screen.getByText("Private; no open issues; no deploys yet")).toBeTruthy();
    expect(screen.getByText("2 cards in play: 1 Active, 1 In Progress")).toBeTruthy();
  });

  it("waits on a visibility read and another Space's cards read too", () => {
    envAnswer = { config: { activeSpace: "toolkit", spaces: SPACES } };
    pending = ["visibility:wasteland", "status:acme"];
    const view = mount();
    expect(screen.getByText("Reading the Spaces...")).toBeTruthy();
    expect(screen.queryByText("Toolkit")).toBeNull();
    pending = [];
    view.rerender(tree());
    expect(screen.getByText("Wasteland")).toBeTruthy();
    expect(screen.getByText("3 cards in play: 2 Active, 1 Code Review")).toBeTruthy();
  });

  it("a failed read settles too: the list draws and that row says so", () => {
    envAnswer = { config: { activeSpace: "toolkit", spaces: SPACES } };
    failingSpaceStatus = ["acme"];
    mount();
    expect(screen.queryByText("Reading the Spaces...")).toBeNull();
    expect(
      screen.getAllByText("Could not read this Space's cards -- the agent did not answer."),
    ).toHaveLength(1);
  });

  it("no row ever shows a placeholder line", () => {
    pending = ["report:toolkit"];
    const view = mount();
    expect(screen.queryByText(/^Reading the (issues|cards)/)).toBeNull();
    pending = [];
    view.rerender(tree());
    expect(screen.queryByText(/^Reading the (issues|cards)/)).toBeNull();
  });

  it("Refresh sits in the header's right slot, before the count chip", () => {
    mount();
    const refresh = screen.getByTitle("Refresh");
    const chip = screen.getByLabelText("3 Spaces");
    expect(refresh.parentElement).toBe(chip.parentElement);
    expect(refresh.compareDocumentPosition(chip) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("Refresh reads every row again -- issues, deploys, cards, and visibility past the agent's cache", () => {
    mount();
    expect(refetched).toEqual([]);
    expect(refreshedVisibility).toEqual([]);
    fireEvent.click(screen.getByTitle("Refresh"));
    expect(new Set(refetched)).toEqual(
      new Set([
        "report:toolkit",
        "deploys:toolkit",
        "report:wasteland",
        "deploys:wasteland",
        "status:here",
      ]),
    );
    expect(new Set(refreshedVisibility)).toEqual(new Set(["toolkit", "wasteland"]));
    expect(screen.queryByText("Reading the Spaces...")).toBeNull();
    expect(screen.getByText("Toolkit")).toBeTruthy();
  });

  it("while a read is fetching again, the list stays drawn and the button shows it", () => {
    const view = mount();
    expect((screen.getByTitle("Refresh") as HTMLButtonElement).disabled).toBe(false);
    pending = ["refetching:report:toolkit"];
    view.rerender(tree());
    expect(screen.queryByText("Reading the Spaces...")).toBeNull();
    expect(screen.getByText("Public; 4 open; no deploys yet")).toBeTruthy();
    expect((screen.getByTitle("Refresh") as HTMLButtonElement).disabled).toBe(true);
  });

  it("pages at five: the pager is at the foot, the chip is the total, the + stays", () => {
    envAnswer = { config: { activeSpace: "s01", spaces: many(12) } };
    mount();
    expect(screen.getByText("Space 05")).toBeTruthy();
    expect(screen.queryByText("Space 06")).toBeNull();
    expect(screen.getByText("1 / 3")).toBeTruthy();
    expect(screen.getByLabelText("12 Spaces").textContent).toBe("12");
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("Space 06")).toBeTruthy();
    expect(screen.getByText("Space 10")).toBeTruthy();
    expect(screen.queryByText("Space 01")).toBeNull();
    expect(screen.getByLabelText("12 Spaces").textContent).toBe("12");
    expect(screen.getByRole("button", { name: /New Space/ })).toBeTruthy();
  });

  it("the filter applies first, and changing it returns to page 1", () => {
    const products = Array.from({ length: 11 }, (_, i) => ({
      slug: `p${i + 1}`,
      name: `Product ${i + 1}`,
      status: "active",
      tracker: "github",
      org: `https://github.com/johnfrog76/p${i + 1}`,
    }));
    envAnswer = { config: { activeSpace: "s01", spaces: [...many(12), ...products] } };
    mount();
    expect(screen.getByText("1 / 5")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("2 / 5")).toBeTruthy();
    fireEvent.click(screen.getByRole("radio", { name: /^Products/ }));
    expect(screen.getByText("1 / 3")).toBeTruthy();
    expect(screen.getByText("Product 1")).toBeTruthy();
    expect(screen.queryByText("Space 01")).toBeNull();
    expect(screen.getByLabelText("23 Spaces").textContent).toBe("23");
  });

  it("one page: no pager, as the Reminders card", () => {
    envAnswer = { config: { activeSpace: "s01", spaces: many(5) } };
    mount();
    expect(screen.getByText("Space 05")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
    expect(screen.queryByText("1 / 1")).toBeNull();
  });

  it("a GitHub Space not connected says nothing about visibility, and is not asked", () => {
    envAnswer = { config: { activeSpace: "demo", spaces: DEMO } };
    unsupportedReport = ["github-demo"];
    mount();
    expect(askedVisibility).not.toContain("github-demo");
    expect(
      screen.getByText(
        "not connected yet -- connect it, and this row shows its open issues and last deploy",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/Visibility unknown/)).toBeNull();
    fireEvent.click(screen.getByTitle("Refresh"));
    expect(refreshedVisibility).toEqual([]);
  });

  it("a connected one whose read did not answer still says Visibility unknown", () => {
    failingVisibility = ["toolkit"];
    mount();
    expect(screen.getByText("Visibility unknown; 4 open; no deploys yet")).toBeTruthy();
  });
});
