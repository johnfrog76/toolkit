import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { DesignNotePage } from "./DesignNotePage";

// One h1 per page: the header's title, with a body that opens with a note then its title.
jest.mock("./api.studio", () => ({
  useGetDesignNoteQuery: () => ({
    data: {
      name: "board-ideas.md",
      title: "Board ideas",
      description: "",
      space: "",
      thread: "",
      thread_number: null,
      thread_repo: "",
      thread_space: "",
      path: "design/board-ideas.md",
      kind: "note",
      archived: false,
      body: "---\nid: abc\n---\n\n> A note first.\n\n# Board ideas\n\n## A\nx\n",
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
