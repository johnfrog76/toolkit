import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DocsLanding } from "./DocsLanding";
import { DocsDocPage } from "./DocsDocPage";
import type { DocDetail, DocsListResponse } from "./api.ado";
import type { DocLinkBase } from "../../shared/docLinks";

// The Docs tab (D-S12). The agent's reads are pinned in Tests/test_docs.py
// and the link kinds in docLinks.test.ts / DocLink.test.tsx; here the tab lands
// on the README with the docs/ tree folded beside it, and the room hands the
// viewer the document's place in the repo and the anchor its address carried.
// The viewer is mocked (react-markdown is ESM, the registry tests' rule) and
// shows what it was given.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({
    content,
    links,
    anchor,
  }: {
    content: string;
    links?: DocLinkBase;
    anchor?: string;
  }) => (
    <pre data-testid="viewer" data-base={links?.path ?? ""} data-anchor={anchor ?? ""}>
      {content}
    </pre>
  ),
}));

const REPO = "johnfrog76/toolkit";
const blob = (p: string) => `https://github.com/${REPO}/blob/main/${p}`;
const LIST: DocsListResponse = {
  supported: true,
  repo: REPO,
  readme: { path: "README.md", name: "README.md", folder: "", url: blob("README.md") },
  items: [
    { path: "docs/CLI.md", name: "CLI.md", folder: "docs", url: blob("docs/CLI.md") },
    {
      path: "docs/modules/ado.md",
      name: "ado.md",
      folder: "docs/modules",
      url: blob("docs/modules/ado.md"),
    },
  ],
};
const doc = (path: string, title: string, body: string): DocDetail => ({
  supported: true,
  repo: REPO,
  path,
  name: path.split("/").pop() ?? path,
  folder: path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "",
  url: blob(path),
  title,
  body,
});

let listAnswer: { data?: unknown; error?: unknown } = {};
const docAsked: string[] = [];
let docAnswer: (path: string) => { data?: unknown; error?: unknown } = () => ({});
jest.mock("./api.ado", () => ({
  useGetDocsQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    ...listAnswer,
  }),
  useGetDocQuery: (path: string, opts?: { skip?: boolean }) => {
    if (opts?.skip) return { isLoading: false, isFetching: false, refetch: jest.fn() };
    docAsked.push(path);
    return { isLoading: false, isFetching: false, refetch: jest.fn(), ...docAnswer(path) };
  },
}));

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname}</div>;
}

function mount(at: string) {
  return render(
    <MemoryRouter initialEntries={[at]}>
      <Routes>
        <Route
          path="/docs"
          element={
            <>
              <DocsLanding />
              <Where />
            </>
          }
        />
        <Route
          path="/docs/*"
          element={
            <>
              <DocsDocPage />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => {
  docAsked.length = 0;
  listAnswer = { data: LIST };
  docAnswer = (p) =>
    p === "README.md"
      ? { data: doc(p, "ToolKit", "# ToolKit\n\nSee [the CLI](docs/CLI.md).\n") }
      : { data: doc(p, "The CLI", "# The CLI\n\n## The workflow\n") };
});

describe("the Docs tab lands on the README", () => {
  it("renders the README in the room, its links resolved against README.md", () => {
    mount("/docs");
    expect(docAsked).toEqual(["README.md"]);
    const viewer = screen.getByTestId("viewer");
    expect(viewer.textContent).toContain("See [the CLI](docs/CLI.md).");
    expect(viewer.getAttribute("data-base")).toBe("README.md");
    expect(screen.getByText("ToolKit")).toBeTruthy();
  });

  it("folds the docs/ tree beside it, each document a room link", () => {
    mount("/docs");
    expect(screen.getByText(/Everything under docs\//)).toBeTruthy();
    fireEvent.click(screen.getByText("docs/modules/ado.md"));
    expect(screen.getByTestId("where").textContent).toBe("/docs/docs/modules/ado.md");
  });

  it("puts Open on GitHub last among the header's controls", () => {
    mount("/docs");
    const open = screen.getByTitle("Open on GitHub");
    expect(open.getAttribute("href")).toBe(blob("README.md"));
    expect(open.getAttribute("target")).toBe("_blank");
    const controls = open.parentElement?.querySelectorAll("a, button") ?? [];
    expect(controls[controls.length - 1]).toBe(open);
  });

  it("a Space that is not GitHub at Tier 1 says so, and asks for no README", () => {
    listAnswer = { data: { supported: false, repo: "", readme: null, items: [] } };
    mount("/docs");
    expect(screen.getByText("No docs in this Space")).toBeTruthy();
    expect(docAsked).toEqual([]);
  });
});

describe("one document's room", () => {
  it("reads the path after /docs/ and hands the viewer its place and its anchor", () => {
    mount("/docs/docs/CLI.md#the-workflow");
    expect(docAsked).toEqual(["docs/CLI.md"]);
    const viewer = screen.getByTestId("viewer");
    expect(viewer.getAttribute("data-base")).toBe("docs/CLI.md");
    expect(viewer.getAttribute("data-anchor")).toBe("the-workflow");
    expect(screen.getByText("The CLI")).toBeTruthy();
  });

  it("a missing document says so in the room", () => {
    docAnswer = () => ({ error: { status: 404 } });
    mount("/docs/docs/gone.md");
    expect(screen.getByText("No docs/gone.md")).toBeTruthy();
  });
});
