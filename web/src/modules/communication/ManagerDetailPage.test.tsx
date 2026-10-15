import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { ManagerDetailPage } from "./ManagerDetailPage";

// The Carried-from check is the agent's to state (docs/hub/manager.md, "Which
// session a record carries from"); the page draws its sentence for the three
// verdicts that carry one, and nothing for `ok` or an agent that sends none.

let detail: Record<string, unknown>;

jest.mock("./api.communication", () => ({
  useGetManagerDetailQuery: () => ({
    data: detail,
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useUpdateManagerSessionMutation: () => [jest.fn(), { isLoading: false }],
  useRewriteTextMutation: () => [jest.fn()],
}));
jest.mock("../../shell/api", () => ({ useGetEnvQuery: () => ({ data: undefined }) }));
jest.mock("./CloseMeeting", () => ({ CloseMeetingButton: () => null }));
jest.mock("./Timer", () => ({ Timer: () => null }));
jest.mock("../../shared/MarkdownViewer", () => ({ MarkdownViewer: () => null }));

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
    <MemoryRouter initialEntries={["/communication/1on1/2026-03-10.md"]}>
      <Routes>
        <Route path="/communication/1on1/:filename" element={<ManagerDetailPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the session page's Carried-from note", () => {
  it("draws the sentence for a stale heading", () => {
    draw({ carried_from_verdict: "stale", carried_from_note: "Carried from A, but latest is B." });
    expect(screen.getByText("Carried from A, but latest is B.")).toBeTruthy();
  });

  it("draws the sentence for a missing heading target", () => {
    draw({ carried_from_verdict: "missing", carried_from_note: "Carried from A, which is not." });
    expect(screen.getByText("Carried from A, which is not.")).toBeTruthy();
  });

  it("draws the sentence for an absent heading", () => {
    draw({ carried_from_verdict: "absent", carried_from_note: "This session has no heading." });
    expect(screen.getByText("This session has no heading.")).toBeTruthy();
  });

  it("draws nothing for ok", () => {
    draw({ carried_from_verdict: "ok", carried_from_note: "" });
    expect(screen.queryByText(/Carried from|no heading/)).toBeNull();
  });

  it("draws nothing when the fields are absent", () => {
    draw({});
    expect(screen.queryByText(/Carried from|no heading/)).toBeNull();
  });
});
