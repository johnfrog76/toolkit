import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { PromptPage } from "./PromptPage";

// One h1 per page: the header's title, with a body that opens with a note then its title.
jest.mock("./PromptsCard", () => ({ promptReference: () => "" }));
jest.mock("./api.studio", () => ({
  useGetPromptQuery: () => ({
    data: {
      name: "build",
      title: "Build",
      description: "Build the card",
      group: "toolkit",
      category: "ship",
      module: "core",
      workflows: [],
      drives: "",
      changed: "",
      history: "",
      overrides: false,
      sender: "",
      by_hand: true,
      file_path: "/hub/agentic/build.prompt.md",
      body: '---\ndescription: "Build the card"\n---\n\n> Commands below use the default prefix.\n\n# Build\n\n## Steps\nx\n',
    },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
}));

it("a prompt whose body opens with a note then its title has exactly one h1", () => {
  render(
    <MemoryRouter initialEntries={["/studio/prompts/build"]}>
      <Routes>
        <Route path="/studio/prompts/*" element={<PromptPage />} />
      </Routes>
    </MemoryRouter>,
  );
  expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
});
