import { fireEvent, render, screen } from "@testing-library/react";
import { fileLineValue } from "../../shared/fileLineValue.testHelper";
import { MemoryRouter, Route, Routes } from "react-router";
import { DocsDocPage } from "./DocsDocPage";

// The docs viewer wears the house header: back, the title as the h1, the
// repository and path as meta, the File line (the document's link, which is its
// address when it is read from the tracker), and refresh then github.com last.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre>{content}</pre>,
}));
const copyText = jest.fn().mockResolvedValue(undefined);
jest.mock("../../shared/copyText", () => ({ copyText: (t: string) => copyText(t) }));
// The agent answers `file_path` only where the Space's checkout is ready here
// and holds the document; a test sets it to see the File line take it.
const local: { file_path?: string } = {};
jest.mock("./api.ado", () => ({
  useGetDocQuery: () => ({
    data: {
      ...local,
      supported: true,
      repo: "owner/repo",
      path: "docs/CONFIGURATION.md",
      name: "CONFIGURATION.md",
      folder: "docs",
      url: "https://github.com/owner/repo/blob/main/docs/CONFIGURATION.md",
      title: "Configuration",
      body: "# Configuration",
    },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/docs/docs/CONFIGURATION.md"]}>
      <Routes>
        <Route path="/docs/*" element={<DocsDocPage />} />
      </Routes>
    </MemoryRouter>,
  );

beforeEach(() => {
  delete local.file_path;
  copyText.mockClear();
});

describe("the docs page header", () => {
  it("shows the title, the repository and path, and the File line you can copy", async () => {
    open();
    expect(screen.getByRole("heading", { level: 1, name: "Configuration" })).toBeTruthy();
    expect(screen.getByText("owner/repo")).toBeTruthy();
    expect(await fileLineValue()).toBe(
      "https://github.com/owner/repo/blob/main/docs/CONFIGURATION.md",
    );
    fireEvent.click(screen.getByRole("button", { name: "Copy the file link" }));
    expect(copyText).toHaveBeenCalledWith(
      "https://github.com/owner/repo/blob/main/docs/CONFIGURATION.md",
    );
  });

  it("holds the file's path on this machine when the checkout is ready here", async () => {
    local.file_path = "/clones/repo/docs/CONFIGURATION.md";
    open();
    expect(await fileLineValue()).toBe("/clones/repo/docs/CONFIGURATION.md");
    fireEvent.click(screen.getByRole("button", { name: "Copy the file path" }));
    expect(copyText).toHaveBeenCalledWith("/clones/repo/docs/CONFIGURATION.md");
  });

  it("puts refresh before the github.com link, which is last", () => {
    open();
    const refresh = screen.getByTitle("Refresh");
    const github = screen.getByTitle("Open on GitHub");
    expect(refresh.compareDocumentPosition(github) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });
});
