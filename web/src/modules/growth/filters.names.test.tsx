import { render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Goals } from "./Goals";
import { ReviewArchive } from "./ReviewArchive";

// Axe's button-name (critical): a filter a screen reader cannot name is an
// unnamed control. The Growth page's two panels split their lists with chip
// rows, each a named group, and Reviews narrows by Space with a named select --
// a contract, held here. The data hooks are stand-ins.

jest.mock("react-redux", () => ({ useDispatch: () => jest.fn() }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({
    data: { config: { spaces: [{ slug: "test", name: "Test" }], activeSpace: "test" } },
  }),
}));
jest.mock("./api.growth", () => ({
  growthApi: { util: { invalidateTags: jest.fn() } },
  useGetGrowthQuery: () => ({
    data: { items: [] },
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useRunNewGrowthMutation: () => [jest.fn(), { isLoading: false }],
  useGetEngagementReviewsQuery: () => ({
    data: [],
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useRunWorkReviewMutation: () => [jest.fn(), { isLoading: false }],
  useGetResumeQuery: () => ({ data: undefined, isFetching: false }),
  useGenerateReviewMutation: () => [jest.fn(), { isLoading: false }],
}));

describe("the Growth page's filters", () => {
  it("Goals names its status chips", () => {
    render(
      <MemoryRouter>
        <Goals />
      </MemoryRouter>,
    );
    const group = screen.getByRole("group", { name: "Filter goals" });
    expect(within(group).getAllByRole("radio").length).toBe(4);
  });

  it("Reviews names its chips and its Space picker", () => {
    render(
      <MemoryRouter>
        <ReviewArchive />
      </MemoryRouter>,
    );
    expect(screen.getByRole("group", { name: "Filter reviews" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Space" })).toBeTruthy();
  });
});
