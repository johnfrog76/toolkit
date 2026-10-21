import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";

// The Board's intro says what the Board IS -- ToolKit's cards -- and on
// a tracker Space ends with where a card comes FROM. It never says the tracker's
// items are on it.

let tracker = "github";
let tier = 1;
jest.mock("../../shell/api", () => ({
  // The repository's visibility is the write surfaces' subject, not this one's.
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: { tier, tracker, ado: { enabled: true, explicit: false }, config: {} },
  }),
}));
jest.mock("./api.ado", () => {
  const mutation = () => [jest.fn(), { isLoading: false }];
  return {
    useGetStatusQuery: () => ({
      data: { count: 0, prompts: [] },
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

const OPENING = "ToolKit cards move by themselves: a new card is Backlog, a commit is";

function intro(): string {
  const { container } = render(
    <MemoryRouter>
      <Board />
    </MemoryRouter>,
  );
  return (container.textContent ?? "").replace(/\s+/g, " ");
}

describe("the board's intro", () => {
  it("on a GitHub Space ends with where an issue's card comes from", () => {
    tracker = "github";
    const text = intro();
    expect(text).toContain(OPENING);
    expect(text).toContain("to archive it. An issue gets a card from the Issues tab: Make a card.");
    expect(text).not.toContain("Cards from");
  });
  it("on an Azure DevOps Space ends with the Focus tab's Make a card", () => {
    tracker = "ado";
    const text = intro();
    expect(text).toContain(OPENING);
    expect(text).toContain(
      "to archive it. A work item gets a card from the Focus tab: Make a card.",
    );
    expect(text).not.toContain("Cards from");
  });
  it("with the tracker signed out names no door: the tab it would point at is not there", () => {
    for (const t of ["github", "ado"]) {
      tracker = t;
      tier = 2;
      const text = intro();
      expect(text).toContain("ToolKit cards move by themselves");
      expect(text).not.toContain("gets a card from");
    }
    tier = 1;
  });

  it("on a Space with no tracker says only how cards move", () => {
    tracker = "none";
    const text = intro();
    expect(text).toContain(OPENING);
    expect(text).not.toContain("gets a card from");
  });
});
