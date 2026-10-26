import fs from "node:fs";
import path from "node:path";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import type { Milestone } from "../ado/api.ado";
import type { MilestonesResponse } from "./api.solitaireAgile";
import {
  AWARD_SEEN_KEY,
  awardKey,
  awardStage,
  awardTitle,
  dayWords,
  pendingAwards,
  tookLine,
} from "./award";
import { resetCelebrateMemory } from "./celebrate";
import { MilestonesPage, STAGE_WORDS, countWords } from "./MilestonesPage";

// The Milestones tab (docs/modules/solitaire-agile.md, "Milestones: the tab and the
// award"): one row per milestone with the tracker's own numbers on its bar, and the
// award dialog -- once per Space and milestone per browser -- the one place the
// module throws confetti. The rows are the SHARED fixture's `expected`
// (Tests/fixtures/rituals/milestones.json), the bytes Tests/test_ritual_milestones.py
// holds the agent to.
//
// The dialog is Fluent's: its focus manager (tabster) marks everything outside the
// active dialog -- and, until focus has moved in, the surface itself -- aria-hidden
// on a 250 ms timer, so under load a role query that skips hidden nodes can miss a
// node that is on screen. Every query that can meet the dialog is AWAITED and passes
// `hidden: true` (the archived flake of Board.remind.test.tsx is the precedent).

const FIXTURE = path.resolve(__dirname, "../../../../Tests/fixtures/rituals/milestones.json");
const table = JSON.parse(fs.readFileSync(FIXTURE, "utf8")) as { expected: Milestone[] };

const bursts: unknown[] = [];
jest.mock("react-confetti", () => ({
  __esModule: true,
  default: (props: { onConfettiComplete?: () => void }) => {
    bursts.push(props);
    return (
      <button type="button" data-testid="confetti" onClick={() => props.onConfettiComplete?.()}>
        burst
      </button>
    );
  },
}));

let response: { data?: MilestonesResponse; isLoading: boolean; error?: unknown } = {
  isLoading: false,
};
let asked: string[] = [];
jest.mock("./api.solitaireAgile", () => ({
  useGetRitualMilestonesQuery: (space: string) => {
    asked.push(space);
    return response;
  },
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: "widgets" } } }),
}));

const SPACE = "widgets";
const ok = (milestones: Milestone[], space = SPACE): MilestonesResponse => ({
  ceremony: "milestones",
  space,
  tracker: { ok: true, reason: "" },
  milestones,
});
const byTitle = (title: string) => table.expected.find((m) => m.title === title)!;
const REACHED_OPEN = "M4b -- 1.5.0"; // every issue closed, GitHub still shows it open
const REACHED_CLOSED = "M2 -- 1.3.0"; // every issue closed, closed on GitHub
const BOTH = () => [byTitle(REACHED_CLOSED), byTitle(REACHED_OPEN)]; // oldest reached first

let reduced = false;
beforeEach(() => {
  localStorage.clear();
  resetCelebrateMemory();
  bursts.length = 0;
  asked = [];
  reduced = false;
  response = { isLoading: false, data: ok(table.expected) };
  window.matchMedia = ((q: string) => ({
    matches: reduced && q.includes("prefers-reduced-motion"),
    media: q,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
  })) as unknown as typeof window.matchMedia;
});

/** The award dialog as it is now, found whatever the focus manager says. */
const dialog = () => screen.findByRole("dialog", { hidden: true });

async function closeDialog() {
  const d = await dialog();
  // Two buttons close it -- the title's X and the action row's Close; this is the latter.
  const buttons = await within(d).findAllByRole("button", { name: "Close", hidden: true });
  fireEvent.click(buttons.find((b) => b.textContent === "Close")!);
}

const stateOf = (title: string) =>
  within(
    screen.getAllByTestId("milestone-row").find((r) => r.dataset.milestone === title)!,
  ).getByTestId("milestone-state").textContent;

describe("the award's rule (award.ts), over the shared table", () => {
  it("a reached milestone is pending until its dialog has been seen, then awarded", () => {
    expect(pendingAwards(SPACE, table.expected).map((m) => m.title)).toEqual([
      REACHED_OPEN,
      REACHED_CLOSED,
    ]);
    localStorage.setItem(AWARD_SEEN_KEY, JSON.stringify([`${SPACE}:${REACHED_OPEN}`]));
    expect(pendingAwards(SPACE, table.expected).map((m) => m.title)).toEqual([REACHED_CLOSED]);
    expect(awardStage(SPACE, byTitle(REACHED_OPEN))).toBe("awarded");
    // Another Space's milestone of the same title is its own.
    expect(pendingAwards("toolkit", table.expected)).toHaveLength(2);
  });

  // The zero-issue decision, one row a shape: an empty milestone is never reached,
  // so never pending and never awarded -- open or closed on the tracker.
  it.each([
    ["Someday", "in flight"],
    ["M4c -- 1.6.0", "in flight"],
    [REACHED_OPEN, "reached"],
    [REACHED_CLOSED, "reached"],
    ["M3 -- the spike", "in flight"],
    ["Parking lot", "empty"],
    ["Abandoned", "empty"],
  ])("%s reads %s", (title, stage) => {
    localStorage.setItem(
      AWARD_SEEN_KEY,
      JSON.stringify(table.expected.map((m) => awardKey(SPACE, m))),
    );
    // Even with every mark set, only a reached one reads awarded.
    const m = byTitle(title);
    expect(awardStage(SPACE, m)).toBe(stage === "reached" ? "awarded" : stage);
    localStorage.clear();
    resetCelebrateMemory();
    expect(awardStage(SPACE, m)).toBe(stage);
  });

  it("says what it took: the issues, then the tracker's dates", () => {
    expect(awardTitle([byTitle(REACHED_OPEN)])).toBe("Congratulations: M4b -- 1.5.0 reached!");
    const named = (...t: string[]) =>
      awardTitle(t.map((title) => ({ ...byTitle(REACHED_OPEN), title })));
    expect(named("A", "B")).toBe("Congratulations: A and B reached!");
    expect(named("A", "B", "C")).toBe("Congratulations: A, B and C reached!");
    expect(tookLine(byTitle(REACHED_OPEN))).toBe(
      "12 issues closed, 1 October 2026 to 24 October 2026.",
    );
    expect(tookLine(byTitle(REACHED_CLOSED))).toBe(
      "9 issues closed, 20 August 2026 to 12 September 2026.",
    );
    expect(tookLine({ ...byTitle(REACHED_OPEN), closed: 1, created_at: undefined })).toBe(
      "1 issue closed, reached 24 October 2026.",
    );
    expect(dayWords("2026-11-15")).toBe("15 November 2026");
    expect(dayWords("")).toBe("");
  });
});

describe("the Milestones tab", () => {
  it("asks about the Space you are in", () => {
    localStorage.setItem(
      AWARD_SEEN_KEY,
      JSON.stringify(table.expected.map((m) => awardKey(SPACE, m))),
    );
    render(<MilestonesPage />);
    expect(asked[0]).toBe(SPACE);
  });

  it("one row per milestone, in the Stats card's order, each bar the tracker's own numbers", () => {
    localStorage.setItem(
      AWARD_SEEN_KEY,
      JSON.stringify(table.expected.map((m) => awardKey(SPACE, m))),
    );
    render(<MilestonesPage />);
    const rows = screen.getAllByTestId("milestone-row");
    // In flight, most complete first; then reached, the one GitHub still shows open
    // first; then empty -- ado/milestones.ts's orderMilestones.
    expect(rows.map((r) => r.dataset.milestone)).toEqual([
      "M3 -- the spike",
      "M4c -- 1.6.0",
      "Someday",
      REACHED_OPEN,
      REACHED_CLOSED,
      "Abandoned",
      "Parking lot",
    ]);
    for (const m of table.expected) {
      const bar = screen.getByRole("progressbar", { name: `${m.title}: ${countWords(m)}` });
      const total = m.open + m.closed;
      expect(Number(bar.getAttribute("aria-valuenow"))).toBeCloseTo(total ? m.closed / total : 0);
    }
    expect(countWords(byTitle("M4c -- 1.6.0"))).toBe("5 of 8 closed");
    // The due date where there is one, and none where there is not.
    const row = (t: string) => rows.find((r) => r.dataset.milestone === t)!;
    expect(row("M4c -- 1.6.0").textContent).toContain("due 15 November 2026");
    expect(row("Someday").textContent).not.toContain("due");
    // The states: open, awarded (its dialog seen), no issues yet.
    expect(stateOf("M4c -- 1.6.0")).toBe(STAGE_WORDS["in flight"]);
    expect(stateOf(REACHED_OPEN)).toBe(STAGE_WORDS.awarded);
    expect(stateOf("Parking lot")).toBe(STAGE_WORDS.empty);
    // Nothing waiting: no dialog, no confetti.
    expect(screen.queryByRole("dialog", { hidden: true })).toBeNull();
    expect(bursts).toHaveLength(0);
  });

  it("the award fires once per visit, naming every reached milestone, inside its dialog; closing it lands on the tab with them awarded", async () => {
    const { unmount } = render(<MilestonesPage />);
    // One dialog naming every reached milestone with no mark, oldest first, each with its
    // own line, its picture, one burst.
    const d = await dialog();
    expect(within(d).getByText(awardTitle(BOTH()))).toBeTruthy();
    const lines = within(d).getAllByTestId("award-line");
    expect(lines.map((l) => l.textContent)).toEqual(
      BOTH().map((m) => `${m.title}: ${tookLine(m)}`),
    );
    expect(within(d).getByTestId("award-picture")).toBeTruthy();
    // The confetti is the dialog's: drawn inside its surface, and nowhere else.
    await waitFor(() => expect(within(d).getAllByTestId("confetti")).toHaveLength(1));
    expect(screen.getAllByTestId("confetti")).toHaveLength(1);
    expect(stateOf(REACHED_OPEN)).toBe(STAGE_WORDS.reached);
    // The burst ends itself and is not thrown again while the dialog stays.
    fireEvent.click(within(d).getByTestId("confetti"));
    await waitFor(() => expect(screen.queryByTestId("confetti")).toBeNull());
    expect(bursts).toHaveLength(1);

    // Close: the backlog behind it was marked with it, so no second dialog follows.
    await closeDialog();
    await waitFor(() => expect(screen.queryByRole("dialog", { hidden: true })).toBeNull());
    expect(bursts).toHaveLength(1);
    expect(stateOf(REACHED_OPEN)).toBe(STAGE_WORDS.awarded);
    expect(stateOf(REACHED_CLOSED)).toBe(STAGE_WORDS.awarded);
    expect(JSON.parse(localStorage.getItem(AWARD_SEEN_KEY) ?? "[]")).toEqual([
      awardKey(SPACE, byTitle(REACHED_CLOSED)),
      awardKey(SPACE, byTitle(REACHED_OPEN)),
    ]);
    unmount();

    // The next visit: never again for the same Space and milestone.
    render(<MilestonesPage />);
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(screen.queryByRole("dialog", { hidden: true })).toBeNull();
    expect(bursts).toHaveLength(1);
    expect(stateOf(REACHED_OPEN)).toBe(STAGE_WORDS.awarded);
  });

  it("the mark is set when the dialog is shown: leaving mid-award never shows it again", async () => {
    const { unmount } = render(<MilestonesPage />);
    await dialog();
    unmount();
    render(<MilestonesPage />);
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(screen.queryByRole("dialog", { hidden: true })).toBeNull();
  });

  it("another Space's milestone of the same title is awarded on its own", async () => {
    localStorage.setItem(
      AWARD_SEEN_KEY,
      JSON.stringify([`${SPACE}:${REACHED_OPEN}`, `${SPACE}:${REACHED_CLOSED}`]),
    );
    response = { isLoading: false, data: ok(table.expected, "toolkit") };
    render(<MilestonesPage />);
    const d = await dialog();
    await within(d).findByText(awardTitle(BOTH()));
  });

  it("an empty milestone is never awarded", async () => {
    response = {
      isLoading: false,
      data: ok([byTitle("Parking lot"), byTitle("Abandoned"), byTitle("Someday")]),
    };
    render(<MilestonesPage />);
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(screen.queryByRole("dialog", { hidden: true })).toBeNull();
    expect(bursts).toHaveLength(0);
    expect(localStorage.getItem(AWARD_SEEN_KEY)).toBeNull();
  });

  it("under prefers-reduced-motion: the dialog says it, and nothing rains", async () => {
    reduced = true;
    render(<MilestonesPage />);
    const d = await dialog();
    await within(d).findByText(awardTitle(BOTH()));
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(bursts).toHaveLength(0);
  });

  it("no tracker: the reason, and no rows", () => {
    response = {
      isLoading: false,
      data: {
        ceremony: "milestones",
        space: SPACE,
        tracker: { ok: false, reason: "This Space's tracker is not GitHub." },
        milestones: [],
      },
    };
    render(<MilestonesPage />);
    expect(screen.getByText("Could not read the milestones")).toBeTruthy();
    expect(screen.getByText("This Space's tracker is not GitHub.")).toBeTruthy();
    expect(screen.queryAllByTestId("milestone-row")).toHaveLength(0);
  });

  it("no milestones: says so, as a fact rather than an error", () => {
    response = { isLoading: false, data: ok([]) };
    render(<MilestonesPage />);
    expect(screen.getByText("No milestones yet")).toBeTruthy();
  });

  it("the agent away: an error, never an empty list", () => {
    response = { isLoading: false, error: { status: 500 } };
    render(<MilestonesPage />);
    expect(screen.getByText("Could not read the milestones")).toBeTruthy();
  });
});

// Confetti.tsx is the one component, and the award dialog is its one caller: no other
// file in the web tree imports it, or the package behind it.
describe("the confetti's one caller", () => {
  const SRC = path.resolve(__dirname, "../..");
  const files = (dir: string): string[] =>
    fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) return files(p);
      return /\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) ? [p] : [];
    });
  it("is AwardDialog.tsx", () => {
    const rel = (p: string) => path.relative(SRC, p).split(path.sep).join("/");
    const callers = files(SRC)
      .filter((p) =>
        /from\s+["'](?:\.{1,2}\/)+(?:[\w/]*\/)?Confetti["']/.test(fs.readFileSync(p, "utf8")),
      )
      .map(rel);
    expect(callers).toEqual(["modules/solitaireAgile/AwardDialog.tsx"]);
    const pkg = files(SRC)
      .filter((p) => /from\s+["']react-confetti["']/.test(fs.readFileSync(p, "utf8")))
      .map(rel);
    expect(pkg).toEqual(["modules/solitaireAgile/Confetti.tsx"]);
  });
});
