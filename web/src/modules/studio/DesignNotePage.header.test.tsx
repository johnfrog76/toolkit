import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { fileLineValue } from "../../shared/fileLineValue.testHelper";
import { DesignNotePage } from "./DesignNotePage";
import type { DesignNoteDetail } from "./api.studio";

// A hub design note's header: the hub-relative path stays as meta (it says which
// of the four folders the note is in), and the File line holds the note's
// absolute path on this machine when the agent sends one -- else no line.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre>{content}</pre>,
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: undefined }),
}));
jest.mock("../ado/api.ado", () => ({
  useGetIssueDetailQuery: () => ({ data: undefined }),
}));
const note: { data: DesignNoteDetail } = {
  data: {
    name: "board-ideas.md",
    title: "Board ideas",
    description: "",
    space: "",
    thread: "https://github.com/owner/repo/issues/9",
    thread_number: 9,
    thread_repo: "owner/repo",
    thread_space: "",
    path: "design/board-ideas.md",
    kind: "note",
    archived: false,
    body: "# Board ideas",
  },
};
jest.mock("./api.studio", () => ({
  useGetDesignNoteQuery: () => ({
    data: note.data,
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
  useRunPromoteDesignMutation: () => [jest.fn(), { isLoading: false }],
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/studio/design/board-ideas.md"]}>
      <Routes>
        <Route path="/studio/design/*" element={<DesignNotePage />} />
      </Routes>
    </MemoryRouter>,
  );

afterEach(() => {
  delete note.data.file_path;
});

describe("the design note page header", () => {
  it("shows the File line with the note's path on this machine", async () => {
    note.data.file_path = "/hub/design/board-ideas.md";
    open();
    expect(screen.getByRole("heading", { level: 1, name: "Board ideas" })).toBeTruthy();
    expect(screen.getByText("design/board-ideas.md")).toBeTruthy();
    expect(await fileLineValue()).toBe("/hub/design/board-ideas.md");
    expect(screen.getByRole("button", { name: "Copy the file path" })).toBeTruthy();
  });

  it("draws no File line when the agent sends no path, as before", () => {
    open();
    expect(screen.getByText("design/board-ideas.md")).toBeTruthy();
    expect(screen.queryByTestId("file-path")).toBeNull();
  });
});
