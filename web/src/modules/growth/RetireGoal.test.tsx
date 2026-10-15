import { act, fireEvent, render, screen } from "@testing-library/react";
import { RetireGoalDialog } from "./RetireGoal";

// Retiring a growth item asks through the house's one confirm, and a
// refusal from `NewGrowth -Close` stays in it, in the verb's own words.
let answer: { status: string; error?: string | null; output?: string | null } = {
  status: "success",
};
const run = jest.fn(() => ({ unwrap: () => Promise.resolve(answer) }));
jest.mock("./api.growth", () => ({
  useRunNewGrowthMutation: () => [run, { isLoading: false }],
}));

beforeEach(() => run.mockClear());

function mount(onOpenChange = jest.fn()) {
  render(
    <RetireGoalDialog
      filename="goal-rust.md"
      title="Learn Rust"
      open
      onOpenChange={onOpenChange}
    />,
  );
  return onOpenChange;
}

describe("retiring a growth item", () => {
  it("asks the house question and names the item", () => {
    mount();
    expect(screen.getByText("Are you sure?")).toBeTruthy();
    expect(screen.getByText("Learn Rust")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Submit" })).toBeTruthy();
  });

  it("Cancel runs nothing", () => {
    const onOpenChange = mount();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(run).not.toHaveBeenCalled();
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("a refusal stays in the dialog, in the verb's words", async () => {
    answer = { status: "error", error: "Already retired.", output: null };
    const onOpenChange = mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(run).toHaveBeenCalledTimes(1);
    expect(screen.getByRole("alert").textContent).toContain("Already retired.");
    expect(onOpenChange).not.toHaveBeenCalledWith(false);
  });
});
