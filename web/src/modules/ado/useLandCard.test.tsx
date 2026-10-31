import { act, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react";
import type { PromptInfo } from "./api.ado";
import { useLandCard } from "./useLandCard";

// Land asks first, then runs the CLI's Land verb through the bridge with the
// card's file, and says once that it landed. A refusal keeps the confirm open
// with the verb's own sentence; Cancel runs nothing.

const land = jest.fn();
jest.mock("./api.ado", () => ({
  useLandCardMutation: () => [land, { isLoading: false }],
}));

const card = {
  file: "Task146-a-merged-card.prompt.md",
  id: "146",
  name: "A merged card",
  title: "Task 146: A merged card",
  status: "Code Review",
  merged: true,
} as PromptInfo;

function answer(status: string, extra: Record<string, unknown> = {}) {
  return {
    unwrap: () =>
      Promise.resolve({
        command: "Land",
        status,
        exit_code: status === "success" ? 0 : 2,
        output: null,
        error: null,
        duration: 1,
        ...extra,
      }),
  };
}

function drawn() {
  const hook = renderHook(() => useLandCard());
  act(() => hook.result.current.open(card));
  const view = render(<>{hook.result.current.dialog}</>);
  return { hook, view };
}

beforeEach(() => land.mockReset());

it("asks first, naming the card and the three things that follow", () => {
  drawn();
  expect(screen.getByText("A merged card")).toBeTruthy();
  expect(screen.getByRole("dialog").textContent).toMatch(/issue behind it is closed/);
  expect(land).not.toHaveBeenCalled();
});

it("Land runs the verb with the card's file, and says it landed", async () => {
  land.mockReturnValue(answer("success"));
  const { hook } = drawn();
  fireEvent.click(screen.getByRole("button", { name: "Land" }));
  await waitFor(() =>
    expect(hook.result.current.landed).toBe(
      "Landed A merged card -- recorded, closed and archived.",
    ),
  );
  expect(land).toHaveBeenCalledWith({ file: card.file });
  expect(hook.result.current.dialog).toBeNull();
});

it("a refusal keeps the confirm open with the verb's own sentence", async () => {
  land.mockReturnValue(
    answer("error", { error: "Pull request #175 (o/r) is open, not merged. Nothing was written." }),
  );
  const { hook } = drawn();
  fireEvent.click(screen.getByRole("button", { name: "Land" }));
  expect(await screen.findByRole("alert")).toHaveProperty(
    "textContent",
    expect.stringContaining("is open, not merged"),
  );
  expect(hook.result.current.landed).toBeNull();
});

it("Cancel runs nothing", () => {
  const { hook } = drawn();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(land).not.toHaveBeenCalled();
  expect(hook.result.current.landed).toBeNull();
});
