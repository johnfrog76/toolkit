import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { PromptDetailPage } from "./PromptDetailPage";

// One h1 per page: the header's title. A card whose body opens with a note
// and then its own title must not draw it as a second h1.
jest.mock("./CardCover", () => ({ CardPictures: () => null, imageLine: () => null }));
jest.mock("./AttachCover", () => ({ AttachActions: () => null, AttachZone: () => null }));
let content = "";
jest.mock("./api.ado", () => ({
  useGetPromptDetailQuery: () => ({
    data: {
      filename: "Task401-add-retry-to-upload.prompt.md",
      path: "/hub/test/current/Task401-add-retry-to-upload.prompt.md",
      title: "Task 401: Add retry to upload",
      status: "Active",
      content,
      checked: 0,
      total: 0,
      progress: "",
    },
    isLoading: false,
    isError: false,
    refetch: jest.fn(),
  }),
}));

const open = () =>
  render(
    <MemoryRouter initialEntries={["/prompts/Task401-add-retry-to-upload.prompt.md"]}>
      <Routes>
        <Route path="/prompts/:filename" element={<PromptDetailPage />} />
      </Routes>
    </MemoryRouter>,
  );

describe("a card page's h1", () => {
  it("is the header's alone when the body opens with a note then its title", () => {
    content =
      "> Commands below use the default prefix.\n\n# Task 401: Add retry to upload\n\n## A\nx\n";
    open();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
  });

  it("is the header's alone when the body's h1 says something else, which reads as level 2", () => {
    content = "# Something else\n\n## A\nx\n";
    open();
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    expect(screen.getByRole("heading", { level: 2, name: "Something else" })).toBeTruthy();
  });
});
