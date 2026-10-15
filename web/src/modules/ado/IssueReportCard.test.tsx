import { render } from "@testing-library/react";
import { IssueReportCard } from "./IssueReportCard";

// The Issue Report counts in the house's stat tiles -- the
// engagement summary's boxed costume -- not in bare numbers of its own.
// The severity and kind counts underneath draw in the SAME tile, not a
// second, smaller costume of their own (a tinted Badge and a monospace
// caption).
const DEFAULT_DATA = {
  supported: true,
  open: 60,
  closed: 5,
  closed_recent: 3,
  sev: { sev1: 1, sev2: 0, sev3: 4 },
  kind: { bug: 2, feat: 1 },
  milestones: [],
  reason: null,
};
const useGetIssueReportQuery = jest.fn();
jest.mock("./api.ado", () => ({
  useGetIssueReportQuery: () => useGetIssueReportQuery(),
}));

beforeEach(() => {
  useGetIssueReportQuery.mockReturnValue({
    data: DEFAULT_DATA,
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
  });
});

describe("the Issue Report", () => {
  it("counts open, closed and closed this week in stat tiles", () => {
    const { container } = render(<IssueReportCard />);
    const rows = container.querySelectorAll("[data-stat-tiles]");
    const topTiles = Array.from(rows[0].querySelectorAll("[data-stat-tile]")).map(
      (t) => t.textContent,
    );
    expect(topTiles).toEqual(["60open", "5closed", "3closed this week"]);
  });

  // "these items should match style of the other top three stats ...
  // they should have same styles as open, closed, closed this week" (the owner).
  // GitHub's own vocabulary (sev1/sev3, bug, feat) stays the label; a zero
  // count (sev2 here) is still absent, same as before.
  it("draws severity and kind counts as a second row of the SAME tile", () => {
    const { container } = render(<IssueReportCard />);
    const rows = container.querySelectorAll("[data-stat-tiles]");
    expect(rows).toHaveLength(2);

    const topTile = rows[0].querySelector("[data-stat-tile]") as HTMLElement;
    const sevTiles = Array.from(rows[1].querySelectorAll("[data-stat-tile]")) as HTMLElement[];

    // The shared style pin: both rows draw the identical StatTile class, not
    // a Badge in one and a tile in the other.
    expect(sevTiles.length).toBeGreaterThan(0);
    for (const tile of sevTiles) expect(tile.className).toBe(topTile.className);

    expect(sevTiles.map((t) => t.textContent)).toEqual(["1sev1", "4sev3", "2bug", "1feat"]);
  });

  // The severity colour signal itself -- which tile gets which token, and
  // that a kind tile gets none -- is pinned in `IssueReportCard.severityColor.test.tsx`
  // against the React prop rather than a rendered CSS value: the colour is a
  // design token (`var(--colorPaletteRedForeground1)`), and jsdom's `cssstyle`
  // rejects a `var(...)` value for `color` outright (it never reaches
  // `style.color`, `style.cssText` or `getAttribute("style")`, empty on all
  // three) -- a jsdom limitation, not a real-browser one, and not this card's.

  it("draws nothing of the second row when every severity and kind is zero", () => {
    useGetIssueReportQuery.mockReturnValue({
      data: {
        ...DEFAULT_DATA,
        sev: { sev1: 0, sev2: 0, sev3: 0 },
        kind: { bug: 0, feat: 0 },
      },
      isLoading: false,
      isFetching: false,
      refetch: jest.fn(),
    });
    const { container } = render(<IssueReportCard />);
    expect(container.querySelectorAll("[data-stat-tiles]")).toHaveLength(1);
  });
});
