import { fireEvent, render, screen, within } from "@testing-library/react";
import { BurnCard, costText, machinesText } from "./BurnCard";
import type { BurnResponse, BurnWindow } from "./api.usage";

// The System page's Claude Code burn tile: the verb's figures, facts only.

const refresh = jest.fn();
let data: BurnResponse | undefined;
let isError = false;

jest.mock("./api.usage", () => ({
  useGetBurnQuery: () => ({ data, isLoading: false, isError }),
  useRefreshBurnMutation: () => [refresh, { isLoading: false }],
}));

function win(o: Partial<BurnWindow> = {}): BurnWindow {
  return {
    from: "2026-10-30T12:00:00.000Z",
    to: "2026-11-04T17:00:00.000Z",
    totals: {
      input: 10,
      output: 20,
      thinking: 0,
      cacheWrite5m: 0,
      cacheWrite1h: 0,
      cacheRead: 0,
      messages: 7,
      costUsdDerived: 1.234,
    },
    byModel: [
      {
        model: "claude-haiku-5-5",
        input: 1500,
        output: 2000,
        thinking: 0,
        cacheWrite5m: 100,
        cacheWrite1h: 0,
        cacheRead: 0,
        messages: 7,
        costUsdDerived: 1.234,
      },
    ],
    unpriced: [],
    machines: [
      { machine: "mini", source: "session-files", days: [], messages: 4, costUsdDerived: 1 },
      {
        machine: "laptop",
        source: "usage-records",
        days: ["2026-10-31", "2026-11-01"],
        messages: 3,
        costUsdDerived: 0.234,
      },
    ],
    ...o,
  };
}

function answer(o: Partial<BurnResponse> = {}): BurnResponse {
  return {
    burn: 1,
    machine: "mini",
    timezone: "UTC",
    utcOffset: "+00:00",
    asOf: "2026-11-04T17:00:00.000Z",
    nextBoundaryAt: "2026-11-05T00:00:00.000Z",
    weekStarts: "Monday 09:00 local",
    sessionFiles: true,
    hub: true,
    today: win({ totals: { ...win().totals, messages: 2, costUsdDerived: null }, byModel: [] }),
    week: win(),
    cost: {
      derived: true,
      currency: "USD",
      priceTableAsOf: "2026-10-06",
      note: "list prices; not the plan's allocation",
      priceNotes: [{ model: "claude-haiku-5-5", note: "priced at its lower rate card" }],
    },
    skipped: { lines: 0, records: 0 },
    fetchedAt: "2026-11-04T17:00:00.000Z",
    fromCache: true,
    ...o,
  };
}

beforeEach(() => {
  refresh.mockReset();
  data = answer();
  isError = false;
});

describe("the burn tile", () => {
  it("shows today and this week, the cost marked derived", () => {
    render(<BurnCard />);
    const week = document.querySelector('[data-burn-window="This week"]') as HTMLElement;
    const today = document.querySelector('[data-burn-window="Today"]') as HTMLElement;
    expect(within(today).getByText("2")).toBeTruthy();
    expect(within(today).getByText("no priced model")).toBeTruthy();
    expect(within(week).getByText("7", { selector: "[data-stat-tile] span" })).toBeTruthy();
    expect(within(week).getAllByText("Cost, derived")).toHaveLength(1);
    expect(within(week).getByText("claude-haiku-5-5")).toBeTruthy();
    expect(within(week).getByText("mini (session files); laptop (2 day records)")).toBeTruthy();
  });

  it("says Haiku is priced at its lower rate card, and never the plan's share", () => {
    render(<BurnCard />);
    expect(screen.getByText("claude-haiku-5-5 is priced at its lower rate card.")).toBeTruthy();
    expect(screen.getByText(/not the plan's\s+allocation/)).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/%/);
  });

  it("names the week start the answer was read under, not a fixed day", () => {
    render(<BurnCard />);
    expect(
      screen.getByText(/The week starts Monday 09:00 local \(burn\.weekStarts\)/),
    ).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/Friday/);
  });

  it("is facts only: no number is coloured", () => {
    const { container } = render(<BurnCard />);
    expect(container.querySelectorAll("[data-stat-tile] span[style]")).toHaveLength(0);
  });

  it("Refresh is the only re-read, and it is the refresh=1 mutation", () => {
    render(<BurnCard />);
    fireEvent.click(screen.getByTitle("Read again, past the agent's hour"));
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("says when nothing could be read", () => {
    data = undefined;
    isError = true;
    render(<BurnCard />);
    expect(screen.getByText("Could not read the burn")).toBeTruthy();
  });
});

describe("the tile's words", () => {
  it("a cost, or that none is priced", () => {
    expect(costText(null)).toBe("no priced model");
    expect(costText(1.234)).toBe("$1.23");
  });

  it("one day record is singular", () => {
    expect(
      machinesText(
        win({
          machines: [
            {
              machine: "laptop",
              source: "usage-records",
              days: ["2026-11-01"],
              messages: 1,
              costUsdDerived: 0,
            },
          ],
        }),
      ),
    ).toBe("laptop (1 day record)");
  });
});
