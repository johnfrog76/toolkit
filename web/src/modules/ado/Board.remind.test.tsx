import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";
import type { PromptInfo } from "./api.ado";

// "Remind me about this" on a board card's menu: there only while the organize
// module is on, and choosing it opens organize's New Reminder dialog with the
// card's title and its id as the ref. Off means absent -- the item is not in
// the menu, and the organize module's dialog is never drawn.

const card: PromptInfo = {
  file: "Task401-add-retry.prompt.md",
  id: "401",
  type: "Task",
  name: "Add retry to the upload client",
  linked: false,
  tracker: "none",
  billable: true,
  title: "Task 401: Add retry to the upload client",
  sprint: "--",
  progress: "--",
  checked: 0,
  total: 0,
  modified: "",
  ado_url: null,
  pr_url: null,
  status: "Active",
};

let features: Record<string, boolean> = {};
jest.mock("../../shell/api", () => ({
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: {
      tier: 3,
      tracker: "none",
      ado: { enabled: false, explicit: false },
      config: {},
      features,
    },
  }),
}));
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
  };
});
const runNewReminder = jest.fn();
jest.mock("../organize/api.organize", () => ({
  useRunNewReminderMutation: () => [runNewReminder, { isLoading: false }],
}));

function draw() {
  return render(
    <MemoryRouter>
      <Board />
    </MemoryRouter>,
  );
}

async function menuItems(): Promise<string[]> {
  fireEvent.click(screen.getByRole("button", { name: `Actions for ${card.name}` }));
  return (await screen.findAllByRole("menuitem")).map((m) => m.textContent ?? "");
}

beforeEach(() => {
  runNewReminder.mockReset().mockImplementation(() => ({
    unwrap: () =>
      Promise.resolve({
        command: "NewReminder",
        status: "success",
        exit_code: 0,
        output: "",
        error: null,
        duration: 0,
      }),
  }));
});

describe("Remind me about this, on a board card", () => {
  it("is absent with the organize module off", async () => {
    features = {};
    draw();
    expect(await menuItems()).not.toContain("Remind me about this");
  });

  it("is the last item with the organize module on", async () => {
    features = { organize: true };
    draw();
    const items = await menuItems();
    expect(items[items.length - 1]).toBe("Remind me about this");
  });

  it("opens the New Reminder dialog with the card's title and its id as the ref, and adds it", async () => {
    features = { organize: true };
    draw();
    await menuItems();
    fireEvent.click(screen.getByRole("menuitem", { name: "Remind me about this" }));
    const dialog = await screen.findByRole("dialog");
    const what = within(dialog).getByRole("textbox", { name: /What/ }) as HTMLInputElement;
    const ref = within(dialog).getByRole("textbox", { name: /Ref/ }) as HTMLInputElement;
    expect(what.value).toBe("Add retry to the upload client");
    expect(ref.value).toBe("401");
    fireEvent.click(within(dialog).getByRole("button", { name: "Submit" }));
    await waitFor(() =>
      expect(runNewReminder).toHaveBeenCalledWith({
        params: ["-Title", "Add retry to the upload client", "-Ref", "401"],
      }),
    );
    expect(
      await screen.findByText(
        "Reminder added about Add retry to the upload client. It is on the Organize tab.",
      ),
    ).toBeTruthy();
  });
});
