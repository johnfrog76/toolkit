import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { OneOnOne } from "./OneOnOne";

// A Meetings row follows the app's one row grammar: one exposed action, the
// rest in a `...` menu named for the row. Archive is offered only by a
// complete, unclosed session, and goes through its confirm to
// MeetingAgenda -Close. The data hooks are stand-ins; the row, its menu and
// the confirm are real.

const run = jest.fn();
const navigate = jest.fn();

const ITEMS = [
  { filename: "2026-03-10.md", date: "2026-03-10", stage: "draft", folder: "current", series: "" },
  { filename: "2026-03-17.md", date: "2026-03-17", stage: "retro", folder: "current", series: "" },
  { filename: "2026-03-03.md", date: "2026-03-03", stage: "retro", folder: "archive", series: "" },
];

jest.mock("react-router", () => ({
  ...jest.requireActual("react-router"),
  useNavigate: () => navigate,
}));
jest.mock("./api.communication", () => ({
  useGetManagerQuery: () => ({
    data: { items: ITEMS },
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useCreateManagerSessionMutation: () => [jest.fn(), { isLoading: false }],
  useRunMeetingAgendaMutation: () => [run, { isLoading: false }],
}));

function draw() {
  render(
    <MemoryRouter>
      <OneOnOne />
    </MemoryRouter>,
  );
}

const menuOf = (title: RegExp) => screen.getByRole("button", { name: title });

describe("a meeting row", () => {
  beforeEach(() => {
    run.mockReset();
    navigate.mockReset();
  });

  it("shows one exposed button and a menu named for the row", () => {
    draw();
    const menu = menuOf(/^Actions for 1:1 — .*March 10/);
    const row = menu.closest("[data-card-item]") as HTMLElement;
    expect(within(row).getAllByRole("button")).toHaveLength(2);
    expect(within(row).getByRole("button", { name: /Open the meeting/ })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /Edit or send/ })).toBeNull();
  });

  it("puts Edit or send in the menu and goes to the session page", () => {
    draw();
    fireEvent.click(menuOf(/^Actions for 1:1 — .*March 10/));
    expect(screen.queryByRole("menuitem", { name: /Archive/ })).toBeNull();
    fireEvent.click(screen.getByRole("menuitem", { name: /Edit or send/ }));
    expect(navigate).toHaveBeenCalledWith(expect.stringContaining("2026-03-10.md"));
  });

  it("offers Archive on a complete, unclosed session", () => {
    draw();
    fireEvent.click(menuOf(/^Actions for 1:1 — .*March 17/));
    expect(screen.getByRole("menuitem", { name: /Archive/ })).toBeTruthy();
  });

  it("offers no Archive on a closed session", () => {
    draw();
    fireEvent.click(menuOf(/^Actions for 1:1 — .*March 3/));
    expect(screen.getByRole("menuitem", { name: /Edit or send/ })).toBeTruthy();
    expect(screen.queryByRole("menuitem", { name: /Archive/ })).toBeNull();
  });

  it("asks first, then closes through the bridge", async () => {
    run.mockReturnValue({ unwrap: () => Promise.resolve({ status: "success" }) });
    draw();
    fireEvent.click(menuOf(/^Actions for 1:1 — .*March 17/));
    fireEvent.click(screen.getByRole("menuitem", { name: /Archive/ }));
    expect(await screen.findByText(/Close this meeting/)).toBeTruthy();
    expect(run).not.toHaveBeenCalled();
    fireEvent.click(await screen.findByRole("button", { name: "Submit" }));
    await waitFor(() => expect(run).toHaveBeenCalledTimes(1));
    expect(JSON.stringify(run.mock.calls[0][0])).toContain("-Close");
  });
});
