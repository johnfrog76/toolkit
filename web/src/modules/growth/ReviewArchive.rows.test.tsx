import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { ReviewArchive } from "./ReviewArchive";
import type { EngagementReviewItem } from "./api.growth";

// A review's row offers Archive and Delete (#148): each runs `WorkReview`
// through the bridge, Delete only after the house's one confirm, which names
// the range and the Spaces. Archived reviews are read under their own filter
// value and never on the default list. The data hooks are stand-ins.

const active: EngagementReviewItem = {
  period: "2026-01-01 – 2026-03-31",
  generatedDate: "2026-04-01",
  artifactsScanned: 0,
  link: "/reviews/2026-01-01_2026-03-31",
  summary: "**Period:** Q1",
  tags: [],
  spaces: ["first", "second"],
  review: "first+second/2026-01-01_2026-03-31",
  archived: false,
};
const archived: EngagementReviewItem = {
  ...active,
  period: "2025-10-01 – 2025-12-31",
  link: "/reviews/2025-10-01_2025-12-31",
  spaces: ["first"],
  review: "archive/first/2025-10-01_2025-12-31",
  archived: true,
};

let answer: { status: string; error?: string | null; output?: string | null } = {
  status: "success",
};
const run = jest.fn((_arg: { params: string[] }) => ({ unwrap: () => Promise.resolve(answer) }));
const reviewsQuery = jest.fn((arg: { slug: string; archived?: boolean }) => ({
  data: arg.archived ? [archived] : [active],
  isLoading: false,
  isFetching: false,
  isError: false,
  refetch: jest.fn(),
}));

jest.mock("react-redux", () => ({ useDispatch: () => jest.fn() }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({
    data: {
      config: {
        spaces: [
          { slug: "first", name: "First Space" },
          { slug: "second", name: "Second Space" },
        ],
        activeSpace: "first",
      },
    },
  }),
}));
jest.mock("./api.growth", () => ({
  growthApi: { util: { invalidateTags: jest.fn() } },
  useGetEngagementReviewsQuery: (arg: { slug: string; archived?: boolean }) => reviewsQuery(arg),
  useRunWorkReviewMutation: () => [run, { isLoading: false }],
  useGetResumeQuery: () => ({ data: undefined, isFetching: false }),
  useGenerateReviewMutation: () => [jest.fn(), { isLoading: false }],
}));

beforeEach(() => {
  run.mockClear();
  reviewsQuery.mockClear();
  answer = { status: "success" };
});

function mount() {
  render(
    <MemoryRouter>
      <ReviewArchive />
    </MemoryRouter>,
  );
}

function openMenu(period: string) {
  fireEvent.click(screen.getByRole("button", { name: `Actions for the review of ${period}` }));
}

describe("a review's row", () => {
  it("offers Archive and Delete, in the vocabulary's words", () => {
    mount();
    openMenu(active.period);
    expect(screen.getByRole("menuitem", { name: /^Archive/ })).toBeTruthy();
    expect(screen.getByRole("menuitem", { name: /^Delete the review/ })).toBeTruthy();
  });

  it("shows its Spaces as chips by name, and no raw orgs line", () => {
    mount();
    expect(screen.getByText("First Space")).toBeTruthy();
    expect(screen.getByText("Second Space")).toBeTruthy();
    expect(screen.queryByText(/orgs:/)).toBeNull();
  });

  it("Archive runs WorkReview -Archive at once, with no confirm", async () => {
    mount();
    openMenu(active.period);
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: /^Archive/ }));
    });
    expect(run).toHaveBeenCalledWith({
      params: ["first+second/2026-01-01_2026-03-31", "-Archive"],
    });
    expect(screen.queryByText("Are you sure?")).toBeNull();
  });

  it("a refused Archive says so on the row, in the verb's words", async () => {
    answer = { status: "error", error: "an archived review is already there", output: null };
    mount();
    openMenu(active.period);
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: /^Archive/ }));
    });
    expect(screen.getByRole("alert").textContent).toContain("an archived review is already there");
  });

  it("Delete asks first, naming the range and the Spaces; Cancel runs nothing", () => {
    mount();
    openMenu(active.period);
    fireEvent.click(screen.getByRole("menuitem", { name: /^Delete the review/ }));
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByText("Are you sure?")).toBeTruthy();
    expect(within(dialog).getByText(active.period)).toBeTruthy();
    expect(within(dialog).getByText("First Space, Second Space")).toBeTruthy();
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(run).not.toHaveBeenCalled();
  });

  it("Delete's Submit runs WorkReview -Delete", async () => {
    mount();
    openMenu(active.period);
    fireEvent.click(screen.getByRole("menuitem", { name: /^Delete the review/ }));
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(run).toHaveBeenCalledWith({
      params: ["first+second/2026-01-01_2026-03-31", "-Delete"],
    });
  });

  it("a review with no slug-set folder (legacy) offers no move", () => {
    reviewsQuery.mockImplementation((arg) => ({
      data: arg.archived ? [] : [{ ...active, review: "" }],
      isLoading: false,
      isFetching: false,
      isError: false,
      refetch: jest.fn(),
    }));
    mount();
    expect(
      screen.queryByRole("button", { name: `Actions for the review of ${active.period}` }),
    ).toBeNull();
    reviewsQuery.mockImplementation((arg) => ({
      data: arg.archived ? [archived] : [active],
      isLoading: false,
      isFetching: false,
      isError: false,
      refetch: jest.fn(),
    }));
  });
});

describe("the Archived filter", () => {
  it("the default list does not ask for archived reviews", () => {
    mount();
    expect(reviewsQuery).toHaveBeenCalledWith({ slug: "all", archived: false });
    expect(screen.queryByText(archived.period)).toBeNull();
  });

  it("Archived reads them, and an archived row offers Delete but not Archive", async () => {
    mount();
    fireEvent.click(screen.getByRole("combobox", { name: "Space or type" }));
    await act(async () => {
      fireEvent.click(screen.getByRole("option", { name: "Archived" }));
    });
    expect(reviewsQuery).toHaveBeenLastCalledWith({ slug: "all", archived: true });
    expect(screen.getByText(archived.period)).toBeTruthy();
    openMenu(archived.period);
    expect(screen.queryByRole("menuitem", { name: /^Archive/ })).toBeNull();
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: /^Delete the review/ }));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(run).toHaveBeenCalledWith({
      params: ["archive/first/2025-10-01_2025-12-31", "-Delete"],
    });
  });
});
