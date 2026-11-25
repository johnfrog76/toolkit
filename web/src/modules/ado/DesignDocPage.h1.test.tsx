import { render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { DesignDocPage } from "./DesignDocPage";

// One h1 per page: the header's title, with a body that opens with a note then its title.
jest.mock("./api.ado", () => ({
  useGetDesignDocQuery: () => ({
    data: {
      supported: true,
      reason: "",
      folder: "design",
      name: "scale.md",
      title: "Scale a recipe",
      id: "4c9c2aee-fced-4114-8cb2-e3a8582251c0",
      description: "Change the servings",
      repo: "acme/kit",
      path: "design/scale.md",
      url: "https://github.com/acme/kit/blob/main/design/scale.md",
      thread: "",
      thread_number: null,
      thread_repo: "",
      body: "---\nid: 4c9c2aee\n---\n\n> A note first.\n\n# Scale a recipe\n\n## A\nx\n",
    },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
  useGetIssueDetailQuery: () => ({ data: undefined }),
}));

it("a design document shows its description under the title, not in the meta", () => {
  render(
    <MemoryRouter initialEntries={["/design/design/scale.md"]}>
      <Routes>
        <Route path="/design/:folder/:name" element={<DesignDocPage />} />
      </Routes>
    </MemoryRouter>,
  );
  const header = screen.getByTestId("detail-header");
  expect(within(header).getByTestId("detail-description").textContent).toBe("Change the servings");
  expect(
    within(within(header).getByTestId("detail-meta")).queryByText("Change the servings"),
  ).toBeNull();
});

it("a design document whose body opens with a note then its title has exactly one h1", () => {
  render(
    <MemoryRouter initialEntries={["/design/design/scale.md"]}>
      <Routes>
        <Route path="/design/:folder/:name" element={<DesignDocPage />} />
      </Routes>
    </MemoryRouter>,
  );
  expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
});
