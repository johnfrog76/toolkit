import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { fileLineValue } from "../../shared/fileLineValue.testHelper";
import { PRCommentsDetail } from "./PRCommentsDetail";
import type { DetailResponse } from "./api.ado";

// The PR comments page's header: the File line holds the card's absolute path on
// this machine, from the same answer the comments came in -- no second request.
jest.mock("react-markdown", () => ({
  __esModule: true,
  default: ({ children }: { children: string }) => <div>{children}</div>,
}));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));
jest.mock("./logError", () => ({ logWebError: jest.fn() }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { anthropicConfigured: false }, isLoading: false }),
}));
const answer: { data: DetailResponse } = {
  data: {
    file: "Task1-card.prompt.md",
    title: "The card",
    pr_id: 77,
    round_num: 1,
    open_count: 0,
    total_count: 0,
    comments: [],
  },
};
const detailQuery = jest.fn();
jest.mock("./api.ado", () => ({
  useGetPrCommentDetailQuery: (...args: unknown[]) => {
    detailQuery(...args);
    return {
      data: answer.data,
      isLoading: false,
      isError: false,
      isFetching: false,
      refetch: jest.fn(),
    };
  },
  useRunCommandMutation: () => [jest.fn()],
  useSuggestReplyMutation: () => [jest.fn()],
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/pr-comments/Task1-card.prompt.md"]}>
      <Routes>
        <Route path="/pr-comments/:filename" element={<PRCommentsDetail hideGuide />} />
      </Routes>
    </MemoryRouter>,
  );

afterEach(() => {
  delete answer.data.file_path;
});

describe("the PR comments page header", () => {
  it("shows the File line with the card's path on this machine", async () => {
    answer.data.file_path = "/hub/test/current/Task1-card.prompt.md";
    open();
    expect(screen.getByRole("heading", { level: 1, name: "The card" })).toBeTruthy();
    expect(await fileLineValue()).toBe("/hub/test/current/Task1-card.prompt.md");
    expect(screen.getByRole("button", { name: "Copy the file path" })).toBeTruthy();
    // One query, the detail itself: the path rides in it.
    expect(new Set(detailQuery.mock.calls.map((c) => JSON.stringify(c[0]))).size).toBe(1);
  });

  it("draws no File line when the answer has no path, as before", () => {
    open();
    expect(screen.getByRole("heading", { level: 1, name: "The card" })).toBeTruthy();
    expect(screen.queryByTestId("file-path")).toBeNull();
  });
});
