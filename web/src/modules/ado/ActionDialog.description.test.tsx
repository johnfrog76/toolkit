import { act, fireEvent, render, screen } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";

// CAE7: the New ToolKit Card door takes a description, optional, that fills
// the card's Context/Summary in place of (TBD) -- the same slot an ADO-linked
// card fills from the work item's own description. And its footer no longer
// claims a custom card is "in play as soon as it is made": NewPrompt lands a
// new card in backlog/ unless -Now is given (docs/hub/cards.md).

jest.mock("../../shell/api", () => ({
  // A local Space: no Azure DevOps, so the only door is the new card's.
  useGetEnvQuery: () => ({
    data: {
      tracker: "none",
      spaceStatus: "local",
      tier: 2,
      ado: { enabled: false },
      cardTypes: ["Task", "Bug"],
    },
  }),
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));

const created: string[][] = [];
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: undefined }),
  useCreatePromptMutation: () => [
    ({ params }: { params: string[] }) => {
      created.push(params);
      return {
        unwrap: () =>
          Promise.resolve({
            command: "NewPrompt",
            status: "success",
            exit_code: 0,
            output: "Created K7M2",
            error: null,
            duration: 1,
          }),
      };
    },
  ],
  useUploadAssetMutation: () => [jest.fn()],
  useResolveBugMutation: () => [jest.fn()],
  useCreatePRMutation: () => [jest.fn()],
  useCreateAdoItemMutation: () => [jest.fn()],
}));

function mount() {
  render(<ActionDialog open onClose={() => {}} tab="create" />);
  fireEvent.change(screen.getByPlaceholderText("e.g. Wallet ticket from a QR code"), {
    target: { value: "A card worth describing" },
  });
}

beforeEach(() => {
  created.length = 0;
});

describe("the New ToolKit Card door's description field", () => {
  it("renders, and is optional -- submitting without it still works", async () => {
    mount();
    expect(
      screen.getByPlaceholderText(
        "Optional context -- fills the card's Context/Summary in place of (TBD)",
      ),
    ).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(created).toEqual([["-Title", "A card worth describing", "-Type", "Task"]]);
  });

  it("given text, it travels through the bridge as -Description", async () => {
    mount();
    fireEvent.change(
      screen.getByPlaceholderText(
        "Optional context -- fills the card's Context/Summary in place of (TBD)",
      ),
      { target: { value: "Uploads over 2GB hang past the 60s gateway timeout." } },
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(created).toEqual([
      [
        "-Title",
        "A card worth describing",
        "-Type",
        "Task",
        "-Description",
        "Uploads over 2GB hang past the 60s gateway timeout.",
      ],
    ]);
  });

  it("the footer says the card starts in the Backlog, not that it is in play at once", () => {
    mount();
    expect(screen.queryByText(/is in\s*play as soon as it is made/)).toBeNull();
    expect(screen.getByText(/starts in the Backlog/)).toBeTruthy();
  });
});
