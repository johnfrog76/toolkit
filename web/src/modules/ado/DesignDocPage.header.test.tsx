import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { fileLineValue } from "../../shared/fileLineValue.testHelper";
import { DesignDocPage } from "./DesignDocPage";
import type { DesignDocDetail } from "./api.ado";

// A repo's design document: read from the Space's ready checkout, the File line
// holds the file's path on this machine; read from GitHub, its link, as before.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre>{content}</pre>,
}));
const URL = "https://github.com/owner/repo/blob/main/design/x.md";
const doc = {
  data: {
    supported: true,
    repo: "owner/repo",
    folder: "design",
    name: "x.md",
    path: "design/x.md",
    url: URL,
    title: "The board",
    description: "",
    thread: "",
    thread_number: null,
    thread_repo: "",
    body: "# The board",
  } as unknown as DesignDocDetail,
};
jest.mock("./api.ado", () => ({
  useGetDesignDocQuery: () => ({
    data: doc.data,
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
  useGetIssueDetailQuery: () => ({ data: undefined }),
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/design/design/x.md"]}>
      <Routes>
        <Route path="/design/:folder/:name" element={<DesignDocPage />} />
      </Routes>
    </MemoryRouter>,
  );

afterEach(() => {
  delete doc.data.file_path;
});

describe("the design document page header", () => {
  it("holds the file's path on this machine when it was read from the checkout", async () => {
    doc.data.file_path = "/clones/repo/design/x.md";
    open();
    expect(await fileLineValue()).toBe("/clones/repo/design/x.md");
    expect(screen.getByRole("button", { name: "Copy the file path" })).toBeTruthy();
  });

  it("holds the GitHub link when it was read from GitHub", async () => {
    open();
    expect(await fileLineValue()).toBe(URL);
    expect(screen.getByRole("button", { name: "Copy the file link" })).toBeTruthy();
  });
});
