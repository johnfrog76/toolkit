import { act, fireEvent, render, screen } from "@testing-library/react";
import { GoalActions, canComplete } from "./GoalActions";
import type { GoalActionsItem } from "./GoalActions";

// A goal's moves, the same on its row and its page: Complete while the agent
// does not read it as complete, Archive either way; a training or a talk is
// offered Archive only. Complete runs `NewGrowth -Complete <file>`.
const run = jest.fn((_arg: { params: string[] }) => ({
  unwrap: () => Promise.resolve({ status: "success" }),
}));
jest.mock("./api.growth", () => ({
  useRunNewGrowthMutation: () => [run, { isLoading: false }],
}));

beforeEach(() => run.mockClear());

const goal = (over: Partial<GoalActionsItem> = {}): GoalActionsItem => ({
  filename: "goal-2026-learn-rust.prompt.md",
  title: "Learn Rust",
  type: "goal",
  status: "active",
  ...over,
});

async function menuItems(item: GoalActionsItem): Promise<string[]> {
  render(<GoalActions item={item} />);
  fireEvent.click(screen.getByRole("button", { name: `Actions for ${item.title}` }));
  return (await screen.findAllByRole("menuitem")).map((m) => m.textContent ?? "");
}

describe("a goal's moves", () => {
  it("a goal that is not complete is offered Complete and Archive", async () => {
    expect(await menuItems(goal())).toEqual(["Complete", "Archive"]);
  });

  it("a new goal is offered Complete too", async () => {
    expect(await menuItems(goal({ status: "new" }))).toEqual(["Complete", "Archive"]);
  });

  it("a complete goal is offered Archive only", async () => {
    expect(await menuItems(goal({ status: "complete" }))).toEqual(["Archive"]);
  });

  it("a training or a presentation keeps Archive only", () => {
    expect(canComplete({ type: "training", status: "active" })).toBe(false);
    expect(canComplete({ type: "presentation", status: "new" })).toBe(false);
  });

  it("Complete asks, then runs NewGrowth -Complete with the file", async () => {
    render(<GoalActions item={goal()} />);
    fireEvent.click(screen.getByRole("button", { name: "Actions for Learn Rust" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Complete" }));
    expect(run).not.toHaveBeenCalled();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(run).toHaveBeenCalledWith({
      params: ["-Complete", "goal-2026-learn-rust.prompt.md"],
    });
  });

  it("Archive asks, then runs NewGrowth -Close with the file", async () => {
    const onArchived = jest.fn();
    render(<GoalActions item={goal()} onArchived={onArchived} />);
    fireEvent.click(screen.getByRole("button", { name: "Actions for Learn Rust" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Archive" }));
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(run).toHaveBeenCalledWith({ params: ["-Close", "goal-2026-learn-rust.prompt.md"] });
    expect(onArchived).toHaveBeenCalled();
  });
});
