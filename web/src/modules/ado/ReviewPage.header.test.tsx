import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { ReviewPage } from "./ReviewPage";

// The review page wears the goal page's header -- Back, a kind badge,
// the review's own title, and FilePath with the file's path. A pending
// commit keeps its own title and shows no single path.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre>{content}</pre>,
}));
jest.mock("../../shared/MarkdownBlock", () => ({
  MarkdownBlock: ({ children }: { children: string }) => <pre>{children}</pre>,
}));
let pending: { file: string; content: string }[] = [];
jest.mock("./api.ado", () => ({
  useGetReviewPreviewQuery: () => ({
    data: { files: pending },
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useGetReviewDetailQuery: () => ({
    data: {
      folder: "2026-04-01_2026-04-30",
      period: "2026-04-01 – 2026-04-30",
      title: "April work review",
      content: "# April work review",
      path: "/hub/reviews/first/2026/2026-04-01_2026-04-30/review.md",
    },
    isLoading: false,
    isFetching: false,
  }),
  useRunCommandMutation: () => [jest.fn(), { isLoading: false }],
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/review/2026-04-01_2026-04-30"]}>
      <Routes>
        <Route path="/review/:folder" element={<ReviewPage />} />
      </Routes>
    </MemoryRouter>,
  );

describe("the review page header", () => {
  it("shows the kind, the review's title and the file path", () => {
    pending = [];
    open();
    expect(screen.getByText("Review")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "April work review" })).toBeTruthy();
    expect(screen.getByTestId("file-path").textContent).toContain(
      "/hub/reviews/first/2026/2026-04-01_2026-04-30/review.md",
    );
  });

  it("keeps the Pending Review title, with no single path", () => {
    pending = [{ file: "review.md", content: "pending" }];
    open();
    expect(screen.getByRole("heading", { name: "Pending Review" })).toBeTruthy();
    expect(screen.queryByTestId("file-path")).toBeNull();
  });
});
