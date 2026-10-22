import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { Board } from "./Board";
import { countInPlay, inPlayLine } from "./inPlay";
import type { PromptInfo } from "./api.ado";

// The WIP line: a count in the Active column's head, amber past limits.inPlay.
// A line the board says, never a gate -- the table below is the rule (the CLI's
// twin is Tests/Test-Status.ps1), and the render proves the head wears it.

function card(n: number, status: string): PromptInfo {
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
    pinned: false,
  };
}

let limit: number | null | undefined;
let prompts: PromptInfo[] = [];

jest.mock("../../shell/api", () => ({
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: {
      tier: 1,
      tracker: "github",
      ado: { enabled: true, explicit: false },
      config: { inPlayLimit: limit },
    },
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

describe("inPlayLine", () => {
  // Every input the rule distinguishes, one row each.
  const rows: Array<[string, number, number | null | undefined, string | null, boolean]> = [
    ["unset", 7, undefined, null, false],
    ["null", 7, null, null, false],
    ["zero is no limit", 7, 0, null, false],
    ["under", 4, 5, "in play 4", false],
    ["at", 5, 5, "in play 5", false],
    ["past", 7, 5, "in play 7 of 5", true],
    ["past by one", 6, 5, "in play 6 of 5", true],
    ["nothing in play", 0, 5, "in play 0", false],
  ];
  it.each(rows)("%s", (_name, count, lim, text, past) => {
    const line = inPlayLine(count, lim);
    expect(line?.text ?? null).toBe(text);
    expect(line?.past ?? false).toBe(past);
  });

  it("counts current/ in every lane, and not the backlog or Done", () => {
    expect(
      countInPlay([
        card(1, "Active"),
        card(2, "In Progress"),
        card(3, "Code Review"),
        card(4, "Backlog"),
        card(5, "Done"),
      ]),
    ).toBe(3);
  });
});

describe("the board's WIP line", () => {
  const draw = () => {
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    return container.querySelector("[data-in-play]");
  };

  it("is absent while no limit is set", () => {
    limit = undefined;
    prompts = [card(1, "Active"), card(2, "In Progress")];
    expect(draw()).toBeNull();
  });

  it("reads the count under the limit, quietly", () => {
    limit = 5;
    prompts = [card(1, "Active"), card(2, "In Progress"), card(3, "Backlog")];
    const badge = draw();
    expect(badge?.textContent).toBe("in play 2");
    expect(badge?.getAttribute("data-in-play")).toBe("within");
  });

  it("goes amber past the limit, counting every lane and no backlog, and still shows every card", () => {
    limit = 2;
    prompts = [
      card(1, "Active"),
      card(2, "In Progress"),
      card(3, "Code Review"),
      card(4, "Backlog"),
    ];
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    const badge = container.querySelector("[data-in-play]");
    expect(badge?.textContent).toBe("in play 3 of 2");
    expect(badge?.getAttribute("data-in-play")).toBe("past");
    // Nothing is hidden or blocked: all four cards are drawn.
    expect(container.querySelectorAll("[draggable]").length).toBe(4);
  });
});
