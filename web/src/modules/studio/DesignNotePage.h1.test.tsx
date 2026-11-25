import { render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { DesignNotePage } from "./DesignNotePage";

// One h1 per page: the header's title, with a body that opens with a note then its title.
jest.mock("./api.studio", () => ({
  useGetDesignNoteQuery: () => ({
    data: {
      name: "board-ideas.md",
      title: "Board ideas",
      description: "What the board could show next",
      space: "",
      thread: "",
      thread_number: null,
      thread_repo: "",
      thread_space: "",
      path: "design/board-ideas.md",
      kind: "note",
      archived: false,
      body: "---\nid: b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11\nstatus: draft\n---\n\n> A note first.\n\n# Board ideas\n\n## A\nx\n",
    },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
  useRunPromoteDesignMutation: () => [jest.fn(), { isLoading: false }],
}));
jest.mock("../ado/api.ado", () => ({ useGetIssueDetailQuery: () => ({ data: undefined }) }));
jest.mock("../../shell/api", () => ({ useGetEnvQuery: () => ({ data: {} }) }));

it("a design note shows its description under the title and a short id in its meta", () => {
  render(
    <MemoryRouter initialEntries={["/studio/design/board-ideas.md"]}>
      <Routes>
        <Route path="/studio/design/*" element={<DesignNotePage />} />
      </Routes>
    </MemoryRouter>,
  );
  const header = screen.getByTestId("detail-header");
  expect(within(header).getByTestId("detail-description").textContent).toBe(
    "What the board could show next",
  );
  const meta = within(header).getByTestId("detail-meta");
  expect(within(meta).getByText("b0a4d1de").getAttribute("title")).toBe(
    "b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11",
  );
  expect(within(meta).queryByText("What the board could show next")).toBeNull();
  // What is left of the front matter is the collapsed row.
  const details = within(header).getByTestId("front-matter-details");
  expect(details.textContent).toContain("status");
  expect(details.textContent).not.toContain("b0a4d1de");
});

it("a design note whose body opens with a note then its title has exactly one h1", () => {
  render(
    <MemoryRouter initialEntries={["/studio/design/board-ideas.md"]}>
      <Routes>
        <Route path="/studio/design/*" element={<DesignNotePage />} />
      </Routes>
    </MemoryRouter>,
  );
  expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
});
