import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import {
  StandupRemindSettings,
  STANDUP_REMIND_ANCHOR,
  defaultDays,
  describeDue,
} from "./StandupRemindSettings";

// Team Agile's settings section (D-TA15): the reminder to attend. It
// reads GET /api/ritual/standup/remind and saves through Standup -Remind on the
// bridge -- the argv is buildStandupRemindParams (cliBridge.test.ts); here, that
// the row sends it, and what it shows for each answer.

let answer: { data?: unknown; error?: unknown; isLoading?: boolean } = {};
const run = jest.fn();
jest.mock("./api.solitaireAgile", () => ({
  useGetStandupRemindQuery: () => ({ isLoading: false, ...answer }),
  useRunStandupRemindMutation: () => [run, { isLoading: false }],
}));

beforeEach(() => {
  answer = {};
  run.mockReset();
  run.mockReturnValue({
    unwrap: () =>
      Promise.resolve({
        command: "Standup",
        status: "success",
        exit_code: 0,
        output: "",
        duration: 1,
      }),
  });
});

describe("the reminder to attend, in the drawer", () => {
  it("marks the anchor the How do I entry opens", () => {
    answer = { data: { organize: true, reminder: null } };
    const { container } = render(<StandupRemindSettings />);
    expect(
      container.querySelector(`[data-settings-anchor="${STANDUP_REMIND_ANCHOR}"]`),
    ).not.toBeNull();
    expect(STANDUP_REMIND_ANCHOR).toBe("standup.remind");
  });

  it("with Organize off, says it needs Organize and offers nothing to set", () => {
    answer = { data: { organize: false, reminder: null } };
    render(<StandupRemindSettings />);
    expect(screen.getByText(/needs Organize/)).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("not set: 09:00 Mon-Fri, and Remind me sends Standup -Remind", async () => {
    answer = { data: { organize: true, reminder: null } };
    render(<StandupRemindSettings />);
    expect(screen.getByText(/Not set/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Remind me" }));
    await waitFor(() => expect(run).toHaveBeenCalledTimes(1));
    expect(run).toHaveBeenCalledWith({
      params: ["-Remind", "09:00", "-Days", "Mon,Tue,Wed,Thu,Fri"],
    });
  });

  it("set: starts from the reminder's own cadence, says when it is next due, and Update sends the change", async () => {
    answer = {
      data: {
        organize: true,
        reminder: {
          id: "K7M2",
          due: "2026-10-05T17:30",
          ref: "17:30 Mon,Wed,Fri",
          time: "17:30",
          days: ["Mon", "Wed", "Fri"],
        },
      },
    };
    render(<StandupRemindSettings />);
    expect(screen.getByText(/Next: Mon 5 Oct, 17:30 \(17:30 Mon,Wed,Fri\)/)).toBeTruthy();
    fireEvent.click(screen.getByRole("checkbox", { name: "Sat" }));
    fireEvent.click(screen.getByRole("button", { name: "Update" }));
    await waitFor(() => expect(run).toHaveBeenCalledTimes(1));
    expect(run).toHaveBeenCalledWith({ params: ["-Remind", "17:30", "-Days", "Mon,Wed,Fri,Sat"] });
  });

  it("no days ticked: nothing to send", () => {
    answer = { data: { organize: true, reminder: null } };
    render(<StandupRemindSettings />);
    for (const d of ["Mon", "Tue", "Wed", "Thu", "Fri"])
      fireEvent.click(screen.getByRole("checkbox", { name: d }));
    expect((screen.getByRole("button", { name: "Remind me" }) as HTMLButtonElement).disabled).toBe(
      true,
    );
  });

  it("the agent away: says so", () => {
    answer = { error: { status: "FETCH_ERROR" } };
    render(<StandupRemindSettings />);
    expect(screen.getByText(/did not answer/)).toBeTruthy();
  });
});

describe("its two helpers", () => {
  it("the default days are the contract's remindDays", () => {
    expect(defaultDays()).toEqual(["Mon", "Tue", "Wed", "Thu", "Fri"]);
  });
  it("a due reads as a day, a date and a time", () => {
    expect(describeDue("2026-10-02T09:00")).toBe("Fri 2 Oct, 09:00");
    expect(describeDue("2026-10-02")).toBe("Fri 2 Oct");
    expect(describeDue("")).toBe("");
  });
});
