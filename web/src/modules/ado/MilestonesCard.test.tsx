import { render, screen } from "@testing-library/react";
import { MilestonesCard } from "./MilestonesCard";
import { orderMilestones, milestoneStateWords } from "./milestones";
import type { Milestone } from "./api.ado";

// The Milestones card on a GitHub Space's Stats tab. The example is this
// repo's own milestones at the time, as the issue gave them -- two reached
// and never closed, which is the second thing the card is for.
function ms(
  number: number,
  title: string,
  closed: number,
  open: number,
  extra: Partial<Milestone> = {},
): Milestone {
  return {
    number,
    title,
    repo: "toolkit",
    url: `https://github.com/johnfrog76/toolkit/milestone/${number}`,
    state: "open",
    open,
    closed,
    due: "",
    closed_at: "",
    reached: closed > 0 && open === 0,
    ...extra,
  };
}

const REPO: Milestone[] = [
  ms(1, "Next three: GitHub tracker", 7, 0),
  ms(2, "Next three: the Lounge", 1, 1),
  ms(3, "Next three: workflow settings", 3, 2),
  ms(4, "Phase 5: the first run", 1, 3),
  ms(5, "Phase 6: ledgers", 0, 1),
  ms(6, "Phase 8: the rename", 1, 0),
  ms(7, "Going public", 0, 1),
];

const useGetMilestonesQuery = jest.fn();
jest.mock("./api.ado", () => ({
  useGetMilestonesQuery: () => useGetMilestonesQuery(),
}));

function answer(milestones: Milestone[], extra: object = {}) {
  useGetMilestonesQuery.mockReturnValue({
    data: { supported: true, milestones, reason: null },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
    ...extra,
  });
}

describe("orderMilestones: in flight (most complete first), then reached, then empty", () => {
  it("orders the repo's own milestones", () => {
    expect(orderMilestones(REPO).map((m) => m.title)).toEqual([
      "Next three: workflow settings", // 3 of 5
      "Next three: the Lounge", // 1 of 2
      "Phase 5: the first run", // 1 of 4
      "Going public", // 0 of 1 -- title breaks the tie
      "Phase 6: ledgers", // 0 of 1
      "Next three: GitHub tracker", // reached, not closed
      "Phase 8: the rename", // reached, not closed
    ]);
  });

  it("puts a reached milestone still open on GitHub before the closed ones, then newest closed first; empty last", () => {
    const list = [
      ms(10, "empty", 0, 0),
      ms(11, "closed long ago", 2, 0, { state: "closed", closed_at: "2026-08-01" }),
      ms(12, "closed lately", 2, 0, { state: "closed", closed_at: "2026-09-20" }),
      ms(13, "reached, open", 2, 0),
      ms(14, "half", 1, 1),
    ];
    expect(orderMilestones(list).map((m) => m.title)).toEqual([
      "half",
      "reached, open",
      "closed lately",
      "closed long ago",
      "empty",
    ]);
  });

  it("names what is left: reached-not-closed, a closed date, or nothing", () => {
    expect(milestoneStateWords(ms(1, "a", 7, 0))).toBe("reached, not closed");
    expect(
      milestoneStateWords(ms(1, "a", 7, 0, { state: "closed", closed_at: "2026-09-03" })),
    ).toBe("closed 2026-09-03");
    expect(milestoneStateWords(ms(1, "a", 1, 1))).toBe("");
  });
});

describe("the Milestones card", () => {
  it("counts reached, in flight and issues left in the shared tile, then lists the rows in order", () => {
    answer(REPO);
    const { container } = render(<MilestonesCard />);
    const tiles = Array.from(container.querySelectorAll("[data-stat-tile]")).map(
      (t) => t.textContent,
    );
    expect(tiles).toEqual(["2reached", "5in flight", "8issues left"]);
    const rows = Array.from(container.querySelectorAll("[data-milestone]")).map((r) =>
      r.getAttribute("data-milestone"),
    );
    expect(rows[0]).toBe("Next three: workflow settings");
    expect(rows.slice(-2)).toEqual(["Next three: GitHub tracker", "Phase 8: the rename"]);
    expect(screen.getAllByText("reached, not closed")).toHaveLength(2);
  });

  it("links each milestone to GitHub, last in its row", () => {
    answer([ms(1, "Next three: GitHub tracker", 7, 0)]);
    render(<MilestonesCard />);
    const link = screen.getByRole("link", { name: "Open Next three: GitHub tracker on GitHub" });
    expect(link.getAttribute("href")).toBe("https://github.com/johnfrog76/toolkit/milestone/1");
  });

  it("says where milestones are made when there are none", () => {
    answer([]);
    render(<MilestonesCard />);
    expect(screen.getByText("No GitHub milestones yet")).toBeTruthy();
    expect(screen.getByText(/Milestones are made on GitHub/)).toBeTruthy();
  });

  it("is absent where the route says unsupported", () => {
    useGetMilestonesQuery.mockReturnValue({
      data: { supported: false, milestones: [] },
      isLoading: false,
      isFetching: false,
      refetch: jest.fn(),
    });
    const { container } = render(<MilestonesCard />);
    expect(container.innerHTML).toBe("");
  });
});
