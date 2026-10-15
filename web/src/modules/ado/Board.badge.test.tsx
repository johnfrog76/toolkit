import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";
import type { PromptInfo } from "./api.ado";

// The tracker badge on the board's card face, in a MIXED Space: a GitHub-born card, an
// ADO-born card and a custom card side by side. Each wears its own tracker's
// chip, and the custom card wears none.

function card(file: string, name: string, tracker: PromptInfo["tracker"]): PromptInfo {
  return {
    file,
    id: null,
    type: "Task",
    name,
    linked: tracker !== "none",
    tracker,
    billable: true,
    title: name,
    sprint: "--",
    progress: "--",
    checked: 0,
    total: 0,
    modified: "",
    ado_url: null,
    pr_url: null,
    status: "Active",
  };
}

const prompts = [
  card("Task4-filter.prompt.md", "Filter by linkedness", "github"),
  card("Task141-search.prompt.md", "Recipe search", "ado"),
  card("Task-K7M2-wallet.prompt.md", "Wallet ticket", "none"),
];

jest.mock("../../shell/api", () => ({
  // The repository's visibility is the write surfaces' subject, not this one's.
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: { tier: 3, tracker: "none", ado: { enabled: false, explicit: false }, config: {} },
  }),
}));
jest.mock("./api.ado", () => {
  const mutation = () => [jest.fn(), { isLoading: false }];
  return {
    useGetStatusQuery: () => ({
      data: { count: prompts.length, prompts },
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

describe("the board's card face", () => {
  it("badges each card with its own tracker, and a custom card with nothing", () => {
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    const worn = Array.from(container.querySelectorAll("[data-tracker-badge]")).map((b) => [
      b.closest("[draggable]")?.querySelector("button")?.textContent,
      b.textContent,
    ]);
    expect(worn).toEqual([
      ["Filter by linkedness", "gh"],
      ["Recipe search", "ado"],
    ]);
    expect(container.textContent).toContain("Wallet ticket");
  });
});
