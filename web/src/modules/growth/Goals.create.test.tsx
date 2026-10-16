import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Goals } from "./Goals";
import type { GrowthItem } from "./api.growth";

// The New Growth Item dialog runs `NewGrowth` through the bridge: the verb the
// terminal types is the one writer. Its answer is a CommandResponse, so the new
// item's name comes off the verb's `FILE:` line; a refusal, and an item that was
// already there, stay in the dialog in the verb's own words.

const navigate = jest.fn();
jest.mock("react-router", () => ({
  ...jest.requireActual("react-router"),
  useNavigate: () => navigate,
}));

let items: GrowthItem[] = [];
let answer: { status: string; error?: string | null; output?: string | null } = {
  status: "success",
};
const run = jest.fn((_arg: { params: string[] }) => ({ unwrap: () => Promise.resolve(answer) }));
jest.mock("./api.growth", () => ({
  useGetGrowthQuery: () => ({
    data: { items },
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useRunNewGrowthMutation: () => [run, { isLoading: false }],
}));

const EXISTING = "training-2026-03-02-clean-architecture.prompt.md";

beforeEach(() => {
  run.mockClear();
  navigate.mockClear();
  items = [];
});

async function createTraining() {
  render(
    <MemoryRouter>
      <Goals />
    </MemoryRouter>,
  );
  fireEvent.click(screen.getByRole("button", { name: /New Growth Item/ }));
  fireEvent.change(screen.getByPlaceholderText("Course or talk title"), {
    target: { value: "Clean Architecture" },
  });
  const dates = document.querySelectorAll<HTMLInputElement>('input[type="date"]');
  fireEvent.change(dates[0], { target: { value: "2026-03-02" } });
  fireEvent.change(dates[1], { target: { value: "2026-04-30" } });
  await act(async () => {
    fireEvent.click(screen.getByRole("button", { name: "Submit" }));
  });
}

describe("creating a growth item from the browser", () => {
  it("runs NewGrowth with the dialog's fields and opens the file the verb names", async () => {
    answer = {
      status: "success",
      output: `Created ${EXISTING}\n    FILE: C:\\hub\\growth\\current\\${EXISTING}`,
    };
    await createTraining();
    expect(run).toHaveBeenCalledTimes(1);
    expect(run.mock.calls[0][0].params).toEqual([
      "-Type",
      "training",
      "-Title",
      "Clean Architecture",
      "-Date",
      "2026-03-02",
      "-DueDate",
      "2026-04-30",
    ]);
    expect(navigate).toHaveBeenCalledWith(`/growth/goals/${encodeURIComponent(EXISTING)}`);
  });

  it("a refusal stays in the dialog, in the verb's words", async () => {
    answer = {
      status: "error",
      error: "invalid date '2026-13-01' -- expected YYYY-MM-DD.",
      output: null,
    };
    await createTraining();
    expect(screen.getByRole("alert").textContent).toContain("expected YYYY-MM-DD");
    expect(navigate).not.toHaveBeenCalled();
  });

  it("an item already in growth/current/ is not opened as if it were new", async () => {
    items = [
      {
        filename: EXISTING,
        type: "training",
        title: "Clean Architecture",
        date: "2026-03-02 to 2026-04-30",
        due_date: "2026-04-30",
        status: "new",
        provider: null,
        hours: "TBD",
      },
    ];
    answer = {
      status: "success",
      output: `Already there: /hub/growth/current/${EXISTING}\n    FILE: /hub/growth/current/${EXISTING}`,
    };
    await createTraining();
    expect(screen.getByRole("alert").textContent).toContain("Already there");
    expect(navigate).not.toHaveBeenCalled();
  });
});
