import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { ManagerSessionPage } from "./ManagerSessionPage";

// A 1:1 session is a hub file, so its page carries the File line like every
// record page: the absolute path the agent sends, or no line for an older agent.
let detail: Record<string, unknown>;
jest.mock("./api.communication", () => {
  const mutation = () => [jest.fn(), { isLoading: false }];
  return {
    useGetManagerDetailQuery: () => ({ data: detail, isLoading: false, isError: false }),
    useCreateManagerSessionMutation: mutation,
    useUpdateManagerSessionMutation: mutation,
    useSendCommsMutation: mutation,
    useRunMeetingAgendaMutation: mutation,
  };
});
jest.mock("../../shell/api", () => ({ useGetEnvQuery: () => ({ data: undefined }) }));
jest.mock("../../shared/MarkdownBlock", () => ({
  MarkdownBlock: ({ children }: { children: string }) => <pre>{children}</pre>,
}));

const SESSION = {
  filename: "2026-03-10.md",
  date: "2026-03-10",
  folder: "current",
  title: "1:1",
  content: "## Stage\ndraft\n",
  since: "",
  forward: "",
  retro_input: "",
  sent: "",
};

function draw(extra: Record<string, unknown>) {
  detail = { ...SESSION, ...extra };
  render(
    <MemoryRouter initialEntries={["/communication/session/2026-03-10.md"]}>
      <Routes>
        <Route path="/communication/session/:filename" element={<ManagerSessionPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the session page header", () => {
  it("shows the File line with the session's absolute path", () => {
    draw({ path: "/hub/manager/current/2026-03-10.md" });
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    expect(screen.getByTestId("file-path").textContent).toContain(
      "/hub/manager/current/2026-03-10.md",
    );
  });

  it("shows no File line when the agent sends no path", () => {
    draw({});
    expect(screen.queryByTestId("file-path")).toBeNull();
  });
});
