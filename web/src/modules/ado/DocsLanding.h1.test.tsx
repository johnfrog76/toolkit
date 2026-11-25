import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { DocsLanding } from "./DocsLanding";

// One h1 on the Docs tab, whatever the README opens with: the page's own title.
// The README's `# Title` is dropped when it is the title and read as level 2
// when it is not; a badge before it changes neither.
const REPO = "acme/kit";
let body = "";
jest.mock("./api.ado", () => ({
  useGetDocsQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    data: {
      supported: true,
      repo: REPO,
      readme: { path: "README.md", name: "README.md", folder: "", url: "https://x/README.md" },
      items: [],
    },
  }),
  useGetDocQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    data: {
      supported: true,
      repo: REPO,
      path: "README.md",
      name: "README.md",
      folder: "",
      url: "https://x/README.md",
      title: "Toolkit",
      body,
    },
  }),
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/docs"]}>
      <Routes>
        <Route path="/docs" element={<DocsLanding />} />
      </Routes>
    </MemoryRouter>,
  );

describe("the Docs tab's h1", () => {
  it("is one when the README opens with a badge then its title", () => {
    body = "[![build](https://x/b.svg)](https://x)\n\n# Toolkit\n\n## A\nx\n";
    open();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
  });
  it("is one when the README opens with its title, and one when its h1 says something else", () => {
    body = "# Toolkit\n\n## A\nx\n";
    const first = open();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    first.unmount();
    body = "# Something else\n\n## A\nx\n";
    open();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
  });
});
