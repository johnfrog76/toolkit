import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";
import type { PromptInfo } from "./api.ado";

// A card whose issue is pinned wears "Pinned on GitHub" in its meta line
// and sorts first in its lane, each group keeping the order it had.

function card(n: number, pinned: boolean, status = "Active"): PromptInfo {
  return {
    file: `Task${n}-c${n}.prompt.md`,
    id: String(n),
    type: "Task",
    name: `c${n}`,
    linked: true,
    tracker: "github",
    billable: true,
    title: `c${n}`,
    sprint: "--",
    progress: "--",
    checked: 0,
    total: 0,
    modified: "",
    ado_url: `https://github.com/o/r/issues/${n}`,
    pr_url: null,
    status,
    pinned,
  };
}

const prompts = [
  card(1, false),
  card(2, true),
  card(3, false),
  card(4, true),
  card(5, true, "In Progress"),
];

jest.mock("../../shell/api", () => ({
  // The repository's visibility is the write surfaces' subject, not this one's.
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: { tier: 1, tracker: "github", ado: { enabled: true, explicit: false }, config: {} },
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

describe("the board's pinned cards", () => {
  it("wears the tracker's words on a pinned card only, and sorts pinned first within a lane", () => {
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    const order = Array.from(container.querySelectorAll("[draggable]")).map((el) => ({
      name: el.querySelector("button")?.textContent,
      pin: el.querySelector("[data-pinned]")?.textContent ?? null,
    }));
    expect(order).toEqual([
      { name: "c2", pin: "Pinned on GitHub" },
      { name: "c4", pin: "Pinned on GitHub" },
      { name: "c1", pin: null },
      { name: "c3", pin: null },
      { name: "c5", pin: "Pinned on GitHub" },
    ]);
  });
});
