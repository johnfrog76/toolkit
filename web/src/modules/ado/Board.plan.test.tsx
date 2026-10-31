import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";
import type { PromptInfo } from "./api.ado";

// Plan milestone, Plan sprint and Tag on a board card's menu: each opens one form,
// and the form runs the CLI's verb through the bridge (POST /api/cmd/Plan,
// /api/cmd/Tag) -- the argv is cliBridge.ts's, and nothing here writes a card.
// The board's filter row gains a Milestone and a Tag dropdown beside Sprint.

const card: PromptInfo = {
  file: "Task401-add-retry.prompt.md",
  id: "401",
  type: "Task",
  name: "Add retry to the upload client",
  linked: false,
  tracker: "none",
  billable: true,
  title: "Task 401: Add retry to the upload client",
  sprint: "Sprint 9",
  milestone: "M2 -- 1.2.0",
  tags: ["docs"],
  progress: "--",
  checked: 0,
  total: 0,
  modified: "",
  ado_url: null,
  pr_url: null,
  status: "Active",
};

jest.mock("../../shell/api", () => ({
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: {
      tier: 3,
      tracker: "none",
      ado: { enabled: false, explicit: false },
      config: {},
      features: {},
    },
  }),
}));
const planCard = jest.fn();
const tagCard = jest.fn();
jest.mock("./api.ado", () => {
  const mutation = () => [jest.fn(), { isLoading: false }];
  return {
    useGetStatusQuery: () => ({
      data: { count: 1, prompts: [card] },
      isLoading: false,
      isFetching: false,
      isError: false,
      refetch: jest.fn(),
    }),
    useArchivePromptMutation: mutation,
    useMoveCardMutation: mutation,
    useSetBillableMutation: mutation,
    useWriteConfigMutation: mutation,
    useCreatePromptMutation: mutation,
    useUploadAssetMutation: mutation,
    useCreatePRMutation: mutation,
    useResolveBugMutation: mutation,
    useCreateAdoItemMutation: mutation,
    usePlanCardMutation: () => [planCard, { isLoading: false }],
    useTagCardMutation: () => [tagCard, { isLoading: false }],
  };
});

const ok = (command: string, output: string) => ({
  unwrap: () =>
    Promise.resolve({ command, status: "success", exit_code: 0, output, error: null, duration: 0 }),
});

function draw() {
  return render(
    <MemoryRouter>
      <Board />
    </MemoryRouter>,
  );
}

async function choose(item: string) {
  fireEvent.click(screen.getByRole("button", { name: `Actions for ${card.name}` }));
  fireEvent.click(await screen.findByRole("menuitem", { name: item }));
  return screen.findByRole("dialog");
}

beforeEach(() => {
  planCard.mockReset().mockImplementation(() => ok("Plan", "[+] 401 is planned into M3."));
  tagCard.mockReset().mockImplementation(() => ok("Tag", "[+] 401 is tagged sev3."));
});

describe("planning a card from its row menu", () => {
  it("offers the three moves on the card's menu", async () => {
    draw();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${card.name}` }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent ?? "");
    expect(items).toEqual(expect.arrayContaining(["Plan milestone", "Plan sprint", "Tag"]));
  });

  it("Plan milestone shows the milestone it has, and Save runs Plan -Milestone", async () => {
    draw();
    const dialog = await choose("Plan milestone");
    expect(within(dialog).getByText("M2 -- 1.2.0")).toBeTruthy();
    const box = within(dialog).getByRole("textbox", { hidden: true });
    fireEvent.change(box, { target: { value: "M3" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save", hidden: true }));
    await waitFor(() =>
      expect(planCard).toHaveBeenCalledWith({ file: card.file, line: "milestone", title: "M3" }),
    );
    expect(await screen.findByText("[+] 401 is planned into M3.")).toBeTruthy();
  });

  it("Plan sprint's Clear takes the card out of its sprint only", async () => {
    draw();
    const dialog = await choose("Plan sprint");
    fireEvent.click(within(dialog).getByRole("button", { name: "Clear sprint", hidden: true }));
    await waitFor(() =>
      expect(planCard).toHaveBeenCalledWith({ file: card.file, line: "sprint", remove: true }),
    );
  });

  it("Tag adds the tags typed, split on commas, through Tag", async () => {
    draw();
    const dialog = await choose("Tag");
    fireEvent.change(within(dialog).getByRole("textbox", { hidden: true }), {
      target: { value: "sev3, sonnet" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Add", hidden: true }));
    await waitFor(() =>
      expect(tagCard).toHaveBeenCalledWith({ file: card.file, tags: ["sev3", "sonnet"] }),
    );
  });

  it("a refusal stays in the form, in the verb's own words", async () => {
    tagCard.mockImplementation(() => ({
      unwrap: () =>
        Promise.resolve({
          command: "Tag",
          status: "error",
          exit_code: 2,
          output: null,
          error: "No card with id '401' in current/ or backlog/.",
          duration: 0,
        }),
    }));
    draw();
    const dialog = await choose("Tag");
    fireEvent.change(within(dialog).getByRole("textbox", { hidden: true }), {
      target: { value: "x" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Take off", hidden: true }));
    expect(await within(dialog).findByText(/No card with id '401'/)).toBeTruthy();
    expect(tagCard).toHaveBeenCalledWith({ file: card.file, tags: ["x"], remove: true });
  });
});

describe("the board's filters", () => {
  it("draws a Milestone and a Tag dropdown beside Sprint when a card names one", () => {
    draw();
    expect(screen.getByRole("combobox", { name: "Milestone" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Sprint" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Tag" })).toBeTruthy();
  });
});
