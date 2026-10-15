import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Goals } from "./Goals";
import { ReviewArchive } from "./ReviewArchive";

// Axe's button-name (critical): the Growth page's two header filters are
// Fluent Dropdowns whose only text is their value ("All"), so a screen reader
// heard an unnamed combobox. Each carries an aria-label for what it filters --
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
  useCreateGrowthMutation: () => [jest.fn(), { isLoading: false }],
  useGetEngagementReviewsQuery: () => ({
    data: [],
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useGetResumeQuery: () => ({ data: undefined, isFetching: false }),
  useGenerateReviewMutation: () => [jest.fn(), { isLoading: false }],
}));

describe("the Growth page's header filters", () => {
  it("Goals names its status filter", () => {
    render(
      <MemoryRouter>
        <Goals />
      </MemoryRouter>,
    );
    expect(screen.getByRole("combobox", { name: "Status" })).toBeTruthy();
  });

  it("the review archive names its Space-or-type filter", () => {
    render(
      <MemoryRouter>
        <ReviewArchive />
      </MemoryRouter>,
    );
    expect(screen.getByRole("combobox", { name: "Space or type" })).toBeTruthy();
  });
});
