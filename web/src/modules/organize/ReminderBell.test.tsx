/**
 * The header bell: asleep with nothing past due, awake with a count when
 * something is, named in words in both states, and a click hands off to the
 * Organize tab. The data half (`overdueOf`) is pure and tested alone; the view
 * takes a state, so no store or agent is needed.
 */
import { render, screen, fireEvent } from "@testing-library/react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { ReminderBellView, bellLabel } from "./ReminderBell";
import { overdueOf } from "./useOverdueReminders";
import type { OverdueState } from "./useOverdueReminders";
import type { Reminder, RemindersResponse } from "./api.organize";

// The view needs no store; this keeps RTK Query's fetch probe out of jsdom.
jest.mock("./api.organize", () => ({ useGetRemindersQuery: jest.fn() }));

const reminder = (id: string, bucket: Reminder["bucket"]): Reminder => ({
  id,
  filename: `${id}-x.md`,
  title: id,
  due: "2026-09-24T09:00",
  bucket,
  source: "manual",
  ref: "",
  created: "2026-09-23",
});

const response = (items: Reminder[]): RemindersResponse => ({
  count: items.length,
  buckets: {
    overdue: items.filter((r) => r.bucket === "overdue").length,
    today: items.filter((r) => r.bucket === "today").length,
    upcoming: items.filter((r) => r.bucket === "upcoming").length,
  },
  items,
  asOf: "2026-09-24T09:21",
});

describe("overdueOf", () => {
  it("is checking before the first answer, and unknown when the read failed", () => {
    expect(overdueOf(undefined, false)).toEqual({ status: "checking" });
    expect(overdueOf(undefined, true)).toEqual({ status: "unknown" });
  });

  it("takes the agent's overdue bucket and nothing else", () => {
    const s = overdueOf(response([reminder("A1B2", "overdue"), reminder("C3D4", "today")]), false);
    expect(s.status).toBe("known");
    if (s.status !== "known") return;
    expect(s.count).toBe(1);
    expect(s.items.map((r) => r.id)).toEqual(["A1B2"]);
  });

  it("keeps the last answer when a later poll fails", () => {
    expect(overdueOf(response([]), true)).toEqual({ status: "known", count: 0, items: [] });
  });
});

describe("bellLabel", () => {
  const rows: [OverdueState, string][] = [
    [{ status: "checking" }, "Checking reminders"],
    [{ status: "unknown" }, "Could not check reminders"],
    [{ status: "known", count: 0, items: [] }, "No past-due reminders"],
    [{ status: "known", count: 1, items: [] }, "1 past-due reminder"],
    [{ status: "known", count: 3, items: [] }, "3 past-due reminders"],
  ];
  it.each(rows)("%o reads %s", (state, words) => {
    expect(bellLabel(state)).toBe(words);
  });
});

describe("ReminderBellView", () => {
  const show = (state: OverdueState, onOpen = jest.fn()) =>
    render(
      <FluentProvider theme={webLightTheme}>
        <ReminderBellView state={state} onOpen={onOpen} />
      </FluentProvider>,
    );

  it("sleeps with no badge when nothing is past due", () => {
    const { container } = show({ status: "known", count: 0, items: [] });
    const bell = screen.getByRole("button", { name: "No past-due reminders" });
    expect(bell.getAttribute("data-bell")).toBe("asleep");
    expect(container.textContent).not.toMatch(/\d/);
  });

  it("sleeps, and says so, while it cannot know", () => {
    show({ status: "unknown" });
    expect(
      screen.getByRole("button", { name: "Could not check reminders" }).getAttribute("data-bell"),
    ).toBe("asleep");
  });

  it("wakes with the count when something is past due", () => {
    const { container } = show({ status: "known", count: 2, items: [] });
    const bell = screen.getByRole("button", { name: "2 past-due reminders" });
    expect(bell.getAttribute("data-bell")).toBe("awake");
    expect(container.textContent).toContain("2");
  });

  it("hands off on a click", () => {
    const onOpen = jest.fn();
    show({ status: "known", count: 1, items: [] }, onOpen);
    fireEvent.click(screen.getByRole("button", { name: "1 past-due reminder" }));
    expect(onOpen).toHaveBeenCalledTimes(1);
  });
});
