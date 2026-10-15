import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { RemindersCard } from "./RemindersCard";
import type { Reminder } from "./api.organize";

// A reminder's ref, as the card draws it: a ref the agent resolved to a card in
// current/ is a link to that card's page; one resolved to an archived card is
// named, not linked (the card page reads current/); any other ref stays in the
// tag as written. And both dialogs carry a Ref field beside Source.

const runReminders = jest.fn();
const runNewReminder = jest.fn();
let items: Reminder[] = [];

jest.mock("./api.organize", () => ({
  useGetRemindersQuery: () => ({
    data: {
      count: items.length,
      buckets: { overdue: 0, today: 0, upcoming: items.length },
      items,
      asOf: "2026-09-23T10:00",
    },
    isLoading: false,
    isError: false,
    isFetching: false,
    refetch: jest.fn(),
  }),
  useRunRemindersMutation: () => [runReminders, { isLoading: false }],
  useRunNewReminderMutation: () => [runNewReminder, { isLoading: false }],
}));

function reminder(id: string, extra: Partial<Reminder> = {}): Reminder {
  return {
    id,
    filename: `${id}-x.md`,
    title: `Reminder ${id}`,
    due: "",
    bucket: "upcoming",
    source: "ado",
    ref: "",
    created: "2026-09-20",
    card: null,
    ...extra,
  };
}

const ok = (command: string) => ({
  unwrap: () =>
    Promise.resolve({
      command,
      status: "success",
      exit_code: 0,
      output: "",
      error: null,
      duration: 0,
    }),
});

function draw() {
  return render(
    <MemoryRouter>
      <RemindersCard />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  runReminders.mockReset().mockImplementation(() => ok("Reminders"));
  runNewReminder.mockReset().mockImplementation(() => ok("NewReminder"));
  items = [];
});

describe("a reminder's ref", () => {
  it("is a link to the card when it names a card in current/", () => {
    items = [
      reminder("T6RA", {
        ref: "401",
        card: {
          id: "401",
          title: "Add retry",
          folder: "current",
          file: "Task401-add-retry.prompt.md",
        },
      }),
    ];
    draw();
    const link = screen.getByRole("link", { name: "401 Add retry" });
    expect(link.getAttribute("href")).toBe("/prompts/Task401-add-retry.prompt.md");
    // The tag keeps the source; the ref is the link, not repeated in the tag.
    expect(screen.getByText("ado")).toBeTruthy();
    expect(screen.queryByText("ado 401")).toBeNull();
  });

  it("names an archived card without linking it", () => {
    items = [
      reminder("T6RA", {
        ref: "388",
        card: {
          id: "388",
          title: "Old work",
          folder: "archive",
          file: "Task388-old-work.prompt.md",
        },
      }),
    ];
    draw();
    expect(screen.queryByRole("link")).toBeNull();
    expect(screen.getByText("388 Old work (done)")).toBeTruthy();
  });

  it("stays the plain tag it always was when it names no card", () => {
    items = [
      reminder("Q4TN", { ref: "41" }),
      reminder("W3X7", { ref: "daily at 09:00", source: "standup" }),
    ];
    draw();
    expect(screen.queryByRole("link")).toBeNull();
    expect(screen.getByText("ado 41")).toBeTruthy();
    expect(screen.getByText("standup daily at 09:00")).toBeTruthy();
  });

  it("is read as plain from an older agent that sends no card", () => {
    const older = reminder("Q4TN", { ref: "41" });
    delete older.card;
    items = [older];
    draw();
    expect(screen.getByText("ado 41")).toBeTruthy();
  });
});

describe("the Ref field", () => {
  it("is in the New Reminder dialog, and what is typed there goes to NewReminder as -Ref", async () => {
    draw();
    fireEvent.click(screen.getByRole("button", { name: "New Reminder" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByRole("textbox", { name: /What/ }), {
      target: { value: "Chase the review" },
    });
    fireEvent.change(within(dialog).getByRole("textbox", { name: /Ref/ }), {
      target: { value: "K7M2" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Submit" }));
    await waitFor(() =>
      expect(runNewReminder).toHaveBeenCalledWith({
        params: ["-Title", "Chase the review", "-Ref", "K7M2"],
      }),
    );
  });

  it("is in the Edit dialog beside Source, filled in, and an emptied ref is sent as an empty -Ref", async () => {
    items = [reminder("Q4TN", { ref: "41" })];
    draw();
    fireEvent.click(screen.getByRole("button", { name: "Actions for Reminder Q4TN" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Edit" }));
    const dialog = await screen.findByRole("dialog");
    const ref = within(dialog).getByRole("textbox", { name: /Ref/ }) as HTMLInputElement;
    expect(ref.value).toBe("41");
    fireEvent.change(ref, { target: { value: "" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(runReminders).toHaveBeenCalledWith({ params: ["-Id", "Q4TN", "-Ref", ""] }),
    );
  });
});
