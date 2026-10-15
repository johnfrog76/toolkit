import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { SkillsPage } from "./SkillsPage";

// The Resume page wears the goal page's header -- Back, a kind badge,
// the title, and FilePath with the file's path, the last-modified after it.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre>{content}</pre>,
}));
jest.mock("react-redux", () => ({ useDispatch: () => jest.fn() }));
jest.mock("./api.growth", () => ({
  growthApi: { util: { invalidateTags: jest.fn() } },
  useGetResumeQuery: () => ({
    data: {
      content: "# Resume",
      last_modified: "2026-10-01 09:00",
      path: "/hub/resume/resume.md",
    },
    isLoading: false,
    isFetching: false,
    isError: false,
  }),
}));

describe("the Resume page header", () => {
  it("shows the kind, the title, the file path and the last-modified", () => {
    render(
      <MemoryRouter>
        <SkillsPage />
      </MemoryRouter>,
    );
    expect(screen.getByTestId("file-path").textContent).toContain("/hub/resume/resume.md");
    expect(screen.getAllByText("Resume").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("Updated 2026-10-01 09:00")).toBeTruthy();
  });
});
