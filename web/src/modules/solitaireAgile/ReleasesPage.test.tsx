import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen, within } from "@testing-library/react";
import type {
  Release,
  ReleaseMilestone,
  ReleaseTitlesResponse,
  ReleasesResponse,
} from "./api.solitaireAgile";
import {
  ReleasesPage,
  milestoneWords,
  scrollToShow,
  stopLabel,
  titlesCapWords,
  trackSpacer,
} from "./ReleasesPage";

// The Releases timeline (docs/modules/solitaire-agile.md, "Releases: the
// timeline"), drawn from the route's own table: Tests/fixtures/releases/repo.json,
// whose `expected` is what GET /api/ritual/releases serves for its repository
// (Tests/test_ritual_releases.py holds the agent to it). The GitHub milestones
// list under the timeline is a stand-in here; MilestonesPage.test.tsx is about it.

interface GhRow {
  number: number;
  title: string;
  state: string;
  open_issues: number;
  closed_issues: number;
  html_url: string;
  created_at: string;
  updated_at: string;
  closed_at: string | null;
}
interface Table {
  repo: string;
  milestones: GhRow[];
  issueTitles: Record<string, string>;
  source: { ok: boolean; reason: string; ref: string };
  expected: (Omit<Release, "pulls" | "issues" | "milestones"> & {
    pulls: number[];
    issues: number[];
    milestones: string[];
  })[];
}
const FIXTURE = path.resolve(__dirname, "../../../../Tests/fixtures/releases/repo.json");
const table = JSON.parse(fs.readFileSync(FIXTURE, "utf8")) as Table;
const base = `https://github.com/${table.repo}`;

// gh's row as the route serves it (the core's Milestone, plus the day it was reached).
function served(row: GhRow): ReleaseMilestone {
  const reached = row.open_issues === 0 && row.closed_issues > 0;
  const closed = (row.closed_at ?? "").slice(0, 10);
  return {
    title: row.title,
    number: row.number,
    repo: table.repo.split("/")[1],
    url: row.html_url,
    state: row.state,
    open: row.open_issues,
    closed: row.closed_issues,
    due: "",
    closed_at: closed,
    closed_time: row.closed_at ?? "",
    created_at: row.created_at.slice(0, 10),
    updated_at: row.updated_at.slice(0, 10),
    reached,
    reachedOn: reached ? closed || row.updated_at.slice(0, 10) : "",
  };
}
const releases: Release[] = table.expected.map((r) => ({
  ...r,
  pulls: r.pulls.map((n) => ({ number: n, title: `Pull ${n}`, url: `${base}/pull/${n}` })),
  issues: r.issues.map((n) => ({ number: n, title: "", url: `${base}/issues/${n}` })),
  milestones: r.milestones.map((t) => served(table.milestones.find((m) => m.title === t)!)),
}));

const ok = (over: Partial<ReleasesResponse> = {}): ReleasesResponse => ({
  ceremony: "releases",
  space: "widgets",
  repo: table.repo,
  source: table.source,
  tracker: { ok: true, reason: "" },
  releases,
  ...over,
});

// The titles read as the route answers it for the numbers asked (Tests/test_ritual_releases.py
// holds the agent to the same table's issueTitles).
const titlesFor = (
  numbers: number[],
  over: Partial<ReleaseTitlesResponse> = {},
): ReleaseTitlesResponse => ({
  space: "widgets",
  repo: table.repo,
  tracker: { ok: true, reason: "" },
  asked: numbers.length,
  limit: 50,
  titles: numbers
    .filter((n) => table.issueTitles[String(n)])
    .map((n) => ({ number: n, title: table.issueTitles[String(n)] })),
  ...over,
});

let response: { data?: ReleasesResponse; isLoading: boolean; error?: unknown } = {
  isLoading: false,
};
let asked: string[] = [];
let titlesAsked: { space: string; numbers: number[]; skip: boolean }[] = [];
let titles: (numbers: number[]) => ReleaseTitlesResponse | undefined = (n) => titlesFor(n);
jest.mock("./api.solitaireAgile", () => ({
  useGetRitualReleasesQuery: (space: string) => {
    asked.push(space);
    return response;
  },
  useGetRitualReleaseTitlesQuery: (
    arg: { space: string; numbers: number[] },
    opts: { skip?: boolean } = {},
  ) => {
    titlesAsked.push({ ...arg, skip: !!opts.skip });
    return { data: opts.skip ? undefined : titles(arg.numbers) };
  },
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: "widgets" } } }),
}));
jest.mock("./MilestonesPage", () => ({ MilestonesPage: () => <p>the milestones list</p> }));

beforeEach(() => {
  asked = [];
  titlesAsked = [];
  titles = (n) => titlesFor(n);
  response = { isLoading: false, data: ok() };
});

const stops = () =>
  within(screen.getByRole("group", { name: "Releases, newest first" })).getAllByRole("button", {
    name: /^(In progress|v\d)/,
  });
const panel = () => screen.queryByTestId("release-panel");

describe("the Releases timeline", () => {
  it("asks about the Space you are in, and draws one h1 and the list under it", () => {
    render(<ReleasesPage />);
    expect(asked[0]).toBe("widgets");
    expect(screen.getAllByRole("heading", { level: 1 }).map((h) => h.textContent)).toEqual([
      "Releases",
    ]);
    expect(screen.getByTestId("releases-repo").textContent).toBe(table.repo);
    expect(screen.getByText("the milestones list")).toBeTruthy();
  });

  it("one stop a release, the one in progress first, each named by the whole fact", () => {
    render(<ReleasesPage />);
    expect(stops().map((b) => b.getAttribute("aria-label"))).toEqual([
      "In progress, since v0.3.0, 3 entries, 1 milestone reached, 2 milestones open",
      "v0.3.0, shipped 12 October 2026, 1 entry, 2 milestones reached",
      "v0.2.0, shipped 1 October 2026, 2 entries, 1 milestone reached",
      "v0.1.0, shipped 10 September 2026, 1 entry, 1 milestone reached",
    ]);
    expect(stops().map((b) => b.getAttribute("tabindex"))).toEqual(["0", "-1", "-1", "-1"]);
  });

  it("a milestone reached is a filled flag over its release; one still aimed at is outlined", () => {
    render(<ReleasesPage />);
    const flags = screen.getAllByTestId("release-flag");
    expect(
      flags.map((f) => [f.getAttribute("aria-label"), f.getAttribute("data-reached")]),
    ).toEqual([
      ["Export, GitHub milestone open, 1 of 3 closed", "false"],
      ["Polish, GitHub milestone reached 22 October 2026", "true"],
      ["Parking lot, GitHub milestone open, no issues yet", "false"],
      ["Search, GitHub milestone reached 5 October 2026", "true"],
      ["Empty state, GitHub milestone reached 1 October 2026", "true"],
      ["Sorting, GitHub milestone reached 1 October 2026", "true"],
      ["First list, GitHub milestone reached 8 September 2026", "true"],
    ]);
    // Not a second tab stop: the track is the keyboard's way in, the panel lists them.
    expect(flags.every((f) => f.getAttribute("tabindex") === "-1")).toBe(true);
  });

  it("a click opens the side panel: dates, milestones, notes, pull requests, issues", () => {
    render(<ReleasesPage />);
    expect(panel()).toBeNull();
    fireEvent.click(stops()[2]);
    const p = within(panel()!);
    expect(p.getByRole("heading", { level: 2 }).textContent).toBe("v0.2.0");
    expect(p.getByText("From v0.1.0 (10 September 2026) to 1 October 2026")).toBeTruthy();
    expect(p.getByRole("link", { name: /Release on GitHub/ }).getAttribute("href")).toBe(
      `${base}/releases/tag/v0.2.0`,
    );
    expect(p.getByRole("link", { name: "Sorting" })).toBeTruthy();
    expect(p.getByText("The list is sorted by name.")).toBeTruthy();
    expect(p.getByText("An empty list says so, instead of showing nothing.")).toBeTruthy();
    expect(p.getAllByRole("link", { name: /^#\d+$/ }).map((a) => a.textContent)).toEqual([
      "#5",
      "#7",
      "#2",
      "#4",
      "#6",
    ]);
    expect(stops()[2].getAttribute("aria-expanded")).toBe("true");
    expect(stops()[2].getAttribute("aria-controls")).toBe(panel()!.id);
  });

  it("the release in progress: its notes so far and the compare view", () => {
    render(<ReleasesPage />);
    fireEvent.click(stops()[0]);
    const p = within(panel()!);
    expect(p.getByRole("heading", { level: 2 }).textContent).toBe("In progress");
    expect(p.getByText("Notes so far")).toBeTruthy();
    expect(p.getByText("Export the list as a file.")).toBeTruthy();
    expect(p.getByRole("link", { name: /Compare on GitHub/ }).getAttribute("href")).toBe(
      `${base}/compare/v0.3.0...main`,
    );
  });

  it("an entry's inline markdown is drawn: a code span and bold, no backticks, no block", () => {
    render(<ReleasesPage />);
    fireEvent.click(stops()[0]);
    const item = within(panel()!)
      .getAllByRole("listitem")
      .find((li) => li.textContent?.startsWith("The export's columns"))!;
    expect(item.querySelector("code")?.textContent).toBe("export.csv");
    expect(item.querySelector("strong")?.textContent).toBe("in order");
    expect(item.textContent).toBe("The export's columns are named in export.csv, in order.");
    expect(item.querySelector("p, h1, h2, h3, h4")).toBeNull();
  });

  it("the panel's issues carry their titles from one read of that release's numbers", () => {
    render(<ReleasesPage />);
    fireEvent.click(stops()[2]);
    expect(titlesAsked[titlesAsked.length - 1]).toEqual({
      space: "widgets",
      numbers: [2, 4, 6],
      skip: false,
    });
    expect(screen.getAllByTestId("release-issue").map((li) => li.textContent)).toEqual([
      "#2 Say what an empty list means",
      "#4 Sort the list",
      "#6 The empty list shows nothing",
    ]);
    expect(screen.queryByTestId("release-titles-cap")).toBeNull();
  });

  it("no tracker, or the read not answered yet: the numbers alone, and nothing drawn as an error", () => {
    titles = (n) =>
      titlesFor(n, { tracker: { ok: false, reason: "gh is not installed." }, titles: [] });
    const { unmount } = render(<ReleasesPage />);
    fireEvent.click(stops()[2]);
    expect(screen.getAllByTestId("release-issue").map((li) => li.textContent)).toEqual([
      "#2",
      "#4",
      "#6",
    ]);
    expect(screen.queryByText(/gh is not installed/)).toBeNull();
    unmount();
    titles = () => undefined;
    render(<ReleasesPage />);
    fireEvent.click(stops()[1]);
    expect(screen.getAllByTestId("release-issue").map((li) => li.textContent)).toEqual([
      "#8",
      "#10",
    ]);
  });

  it("a release with no issue asks for no title", () => {
    response = {
      isLoading: false,
      data: ok({ releases: releases.map((r, i) => (i === 3 ? { ...r, issues: [] } : r)) }),
    };
    render(<ReleasesPage />);
    fireEvent.click(stops()[3]);
    expect(titlesAsked[titlesAsked.length - 1]).toEqual({
      space: "widgets",
      numbers: [],
      skip: true,
    });
    expect(screen.queryAllByTestId("release-issue")).toHaveLength(0);
  });

  it("past the read's cap, the panel says how many of the titles it read", () => {
    titles = (n) => titlesFor(n, { asked: 73, limit: 50 });
    render(<ReleasesPage />);
    fireEvent.click(stops()[2]);
    expect(screen.getByTestId("release-titles-cap").textContent).toBe(
      "Titles read for the first 50 of 73 issues.",
    );
    expect(titlesCapWords(73, 50)).toBe("Titles read for the first 50 of 73 issues.");
  });

  it("Left and Right step between releases, Home and End jump, focus follows and so does the panel", () => {
    render(<ReleasesPage />);
    const group = screen.getByRole("group", { name: "Releases, newest first" });
    stops()[0].focus();
    fireEvent.keyDown(group, { key: "ArrowRight" });
    expect(document.activeElement).toBe(stops()[1]);
    expect(stops()[1].getAttribute("tabindex")).toBe("0");
    fireEvent.click(stops()[1]);
    fireEvent.keyDown(group, { key: "ArrowRight" });
    expect(document.activeElement).toBe(stops()[2]);
    expect(within(panel()!).getByRole("heading", { level: 2 }).textContent).toBe("v0.2.0");
    fireEvent.keyDown(group, { key: "End" });
    expect(document.activeElement).toBe(stops()[3]);
    fireEvent.keyDown(group, { key: "ArrowRight" });
    expect(document.activeElement).toBe(stops()[3]);
    fireEvent.keyDown(group, { key: "Home" });
    expect(document.activeElement).toBe(stops()[0]);
    fireEvent.keyDown(group, { key: "ArrowLeft" });
    expect(document.activeElement).toBe(stops()[0]);
    expect(within(panel()!).getByRole("heading", { level: 2 }).textContent).toBe("In progress");
  });

  it("Escape and Close shut the panel, and focus goes back to the stop", () => {
    render(<ReleasesPage />);
    fireEvent.click(stops()[1]);
    fireEvent.keyDown(screen.getByRole("group", { name: "Releases, newest first" }), {
      key: "Escape",
    });
    expect(panel()).toBeNull();
    expect(document.activeElement).toBe(stops()[1]);
    fireEvent.click(stops()[1]);
    fireEvent.click(within(panel()!).getByRole("button", { name: "Close the release" }));
    expect(panel()).toBeNull();
  });

  it("a click on a flag opens its release with that milestone marked", () => {
    render(<ReleasesPage />);
    fireEvent.click(screen.getByRole("button", { name: /^Search, GitHub milestone/ }));
    expect(within(panel()!).getByRole("heading", { level: 2 }).textContent).toBe("v0.3.0");
    expect(document.activeElement).toBe(stops()[1]);
  });

  it("no tracker: every release, no flag, and one plain line saying why", () => {
    response = {
      isLoading: false,
      data: ok({
        tracker: { ok: false, reason: "gh is not installed, so the tracker was not asked." },
        releases: releases.map((r) => ({ ...r, milestones: [] })),
      }),
    };
    render(<ReleasesPage />);
    expect(stops()).toHaveLength(4);
    expect(screen.queryAllByTestId("release-flag")).toHaveLength(0);
    expect(screen.getByTestId("releases-tracker").textContent).toBe(
      "GitHub milestones not read: gh is not installed, so the tracker was not asked.",
    );
  });

  it("no checkout: the setting's own sentence, drawn plainly, and no stop", () => {
    const reason =
      "spaceCheckouts.widgets.path is not set: the releases are read from acme/widgets's clone on this machine.";
    response = { isLoading: false, data: ok({ source: { ok: false, reason }, releases: [] }) };
    render(<ReleasesPage />);
    expect(screen.getByText("No releases read")).toBeTruthy();
    expect(screen.getByText(reason)).toBeTruthy();
    expect(screen.queryByText("Could not read the releases")).toBeNull();
    expect(screen.queryAllByTestId("release-stop")).toHaveLength(0);
  });

  it("the agent away: an error, never an empty timeline", () => {
    response = { isLoading: false, error: { status: 500 } };
    render(<ReleasesPage />);
    expect(screen.getByText("Could not read the releases")).toBeTruthy();
  });
});

describe("the track's scroll", () => {
  // Four stops of 132 in a 358-wide view: the 390 phone, its gutters taken off.
  const edges = [0, 1, 2, 3].map((i) => ({ left: i * 132, right: (i + 1) * 132 }));

  it("a stop already wholly in view does not move the track", () => {
    expect(scrollToShow(edges, 1, 0, 358)).toBeNull();
    expect(scrollToShow(edges, 3, 264, 358)).toBeNull();
  });

  it("a stop cut at the right brings in the fewest stops, on a stop's edge", () => {
    // The third ends at 396: 38 past the view, so the track starts at the second stop.
    expect(scrollToShow(edges, 2, 0, 358)).toBe(132);
    expect(scrollToShow(edges, 3, 0, 358)).toBe(264);
  });

  it("a stop off to the left goes to the left edge", () => {
    expect(scrollToShow(edges, 0, 132, 358)).toBe(0);
    expect(scrollToShow(edges, 1, 200, 358)).toBe(132);
  });

  it("the room after the last stop is what a whole number of stops leaves of the view", () => {
    expect(trackSpacer(358, 132)).toBe(94);
    expect(trackSpacer(396, 132)).toBe(0);
    expect(trackSpacer(0, 132)).toBe(0);
    // With it the farthest scroll is a stop's edge: 4 * 132 + 94 - 358 = 264.
    expect(4 * 132 + trackSpacer(358, 132) - 358).toBe(264);
  });

  it("stepping scrolls the track itself: focus never scrolls it first", () => {
    render(<ReleasesPage />);
    const spy = jest.spyOn(HTMLElement.prototype, "focus");
    stops()[0].focus();
    spy.mockClear();
    fireEvent.keyDown(screen.getByRole("group", { name: "Releases, newest first" }), {
      key: "ArrowRight",
    });
    expect(spy).toHaveBeenCalledWith({ preventScroll: true });
    spy.mockRestore();
  });
});

describe("the words", () => {
  it("a milestone's line and a stop's name", () => {
    const m = releases[0].milestones[0];
    expect(milestoneWords(m)).toBe("open, 1 of 3 closed");
    expect(stopLabel({ ...releases[0], previous: "", milestones: [], notes: [] })).toBe(
      "In progress, 0 entries",
    );
  });
});
