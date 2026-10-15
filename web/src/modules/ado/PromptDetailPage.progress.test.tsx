import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { PromptDetailPage } from "./PromptDetailPage";

// Axe's aria-progressbar-name (serious): the card header's checklist
// ProgressBar had no name. It carries the sentence its tooltip already said,
// so a screen reader hears what the bar shows. The body's renderer and the
// picture slots are stand-ins; this is about the header.

jest.mock("../../shared/MarkdownViewer", () => ({ MarkdownViewer: () => null }));
jest.mock("./CardCover", () => ({ CardPictures: () => null, imageLine: () => null }));
jest.mock("./AttachCover", () => ({ AttachActions: () => null, AttachZone: () => null }));
jest.mock("../../shared/BackButton", () => ({ BackButton: () => null }));
jest.mock("./api.ado", () => ({
  useGetPromptDetailQuery: () => ({
    data: {
      filename: "Task401-add-retry-to-upload.prompt.md",
      path: "/hub/test/current/Task401-add-retry-to-upload.prompt.md",
      title: "Task 401: Add retry to upload",
      status: "Active",
      content: "- [x] one\n- [ ] two\n- [ ] three\n",
      checked: 1,
      total: 3,
      progress: "1/3",
    },
    isLoading: false,
    isError: false,
    refetch: jest.fn(),
  }),
}));

describe("PromptDetailPage's checklist bar", () => {
  it("is named by what it counts", () => {
    render(
      <MemoryRouter initialEntries={["/prompts/Task401-add-retry-to-upload.prompt.md"]}>
        <Routes>
          <Route path="/prompts/:filename" element={<PromptDetailPage />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(
      screen.getByRole("progressbar", { name: "1 of 3 checklist items completed" }),
    ).toBeTruthy();
  });
});
