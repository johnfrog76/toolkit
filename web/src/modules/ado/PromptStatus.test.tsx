import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, useLocation } from "react-router";
import { PromptStatus } from "./PromptStatus";
import type { PromptInfo } from "./api.ado";
import { expectListPanelShape } from "../../shell/kinds/panelShapeAssert";

// Active Cards as a list panel: each prompt file is a card item -- its name,
// its kind and id, and its facts in the meta band with the checklist's
// progress -- one page of four, and Open the way into the card.
jest.mock("./ActionDialog", () => ({ ActionDialog: () => null }));
jest.mock("./useRemindAbout", () => ({
  useRemindAbout: () => ({ open: jest.fn(), dialog: null, added: null, clearAdded: jest.fn() }),
}));
jest.mock("./useLandCard", () => ({
  useLandCard: () => ({ open: jest.fn(), dialog: null, landed: null, clearLanded: jest.fn() }),
}));
jest.mock("./PlanCardDialog", () => ({
  usePlanCard: () => ({ open: jest.fn(), dialog: null, done: null, clearDone: jest.fn() }),
}));
jest.mock("./useBillableToggle", () => ({
  billableOutcomeMessage: () => "",
  useBillableToggle: () => ({
    toggle: jest.fn(),
    busyFile: null,
    outcome: null,
    clearOutcome: jest.fn(),
  }),
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker: "github", cliPrefix: "tk", features: {} } }),
}));

let prompts: PromptInfo[] = [];
let failed = false;
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({
    data: failed ? undefined : { count: prompts.length, prompts },
    isLoading: false,
    isFetching: false,
    isError: failed,
    refetch: jest.fn(),
  }),
  useArchivePromptMutation: () => [jest.fn()],
  useMoveCardMutation: () => [jest.fn()],
}));

function card(n: number, over: Partial<PromptInfo> = {}): PromptInfo {
  return {
    file: `Task${n}-card.prompt.md`,
    name: `Card ${n}`,
    title: `Card ${n}`,
    type: "Task",
    id: String(n),
    status: "Active",
    sprint: "S1",
    modified: "2026-10-01",
    progress: "0/0",
    checked: 0,
    total: 0,
    billable: true,
    pr_url: null,
    ado_url: null,
    tracker: "none",
    cover: null,
    ...over,
  } as PromptInfo;
}

function Where() {
  return <span data-testid="where">{useLocation().pathname}</span>;
}

function mount(props: Parameters<typeof PromptStatus>[0] = {}) {
  return render(
    <MemoryRouter initialEntries={["/"]}>
      <PromptStatus {...props} />
      <Where />
    </MemoryRouter>,
  );
}

const panel = (container: HTMLElement) =>
  container.querySelector<HTMLElement>("[data-panel-kind]")!;

beforeEach(() => {
  prompts = [];
  failed = false;
});

describe("Active Cards, as a list panel", () => {
  it("four card items a page, the pager at the foot, the count the whole list", () => {
    prompts = Array.from({ length: 7 }, (_, i) => card(i + 1));
    const { container } = mount();
    expectListPanelShape(panel(container), {
      titles: ["Card 1", "Card 2", "Card 3", "Card 4"],
      total: 7,
    });
    expect(panel(container).querySelector("[data-panel-count]")!.textContent).toBe("7");
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expectListPanelShape(panel(container), {
      titles: ["Card 5", "Card 6", "Card 7"],
      total: 7,
    });
  });

  it("an item says what kind of thing it is and its id, and carries its facts in the meta band", () => {
    prompts = [
      card(141, {
        type: "Bug",
        status: "Code Review",
        tracker: "github",
        billable: false,
        checked: 3,
        total: 4,
        progress: "3/4",
        cover: "/api/cover/141.png",
      }),
    ];
    const { container } = mount();
    const [item] = expectListPanelShape(panel(container), { titles: ["Card 141"], total: 1 });
    expect(item.querySelector("[data-row-description]")!.textContent).toBe("Bug 141");
    const meta = item.querySelector("[data-row-meta]")!;
    expect(meta.textContent).toBe("3/4ghSprint: S1Modified: 2026-10-01Code ReviewNot billable");
    // The checklist's progress is the item's own slot: a bar and its count.
    expect(meta.querySelector("[role='progressbar']")).not.toBeNull();
    expect(screen.getByRole("img", { name: "Cover of Card 141" })).toBeTruthy();
  });

  it("a card with no checklist draws no bar", () => {
    prompts = [card(1)];
    mount();
    expect(screen.queryByRole("progressbar")).toBeNull();
  });

  it("Open is the way into the card; the title is text", () => {
    prompts = [card(1)];
    mount();
    fireEvent.click(screen.getByText("Card 1"));
    expect(screen.getByTestId("where").textContent).toBe("/");
    fireEvent.click(screen.getByRole("button", { name: "Open the card" }));
    expect(screen.getByTestId("where").textContent).not.toBe("/");
  });

  it("the state picker narrows the list, and a state with no card says which", () => {
    prompts = [card(1), card(2, { status: "In Progress" })];
    const { container } = mount({ stateOptions: ["All", "Active", "In Progress", "Code Review"] });
    fireEvent.change(screen.getByRole("combobox", { name: "State" }), {
      target: { value: "In Progress" },
    });
    expectListPanelShape(panel(container), { titles: ["Card 2"], total: 1 });
    fireEvent.change(screen.getByRole("combobox", { name: "State" }), {
      target: { value: "Code Review" },
    });
    expect(screen.getByText("No cards are Code Review")).toBeTruthy();
    expect(screen.getByText("2 hidden by the filter.")).toBeTruthy();
  });

  it("no cards, and a failed read, are two different sentences", () => {
    const first = mount();
    expect(screen.getByText("No cards in progress")).toBeTruthy();
    first.unmount();
    failed = true;
    mount();
    expect(screen.getByRole("alert").textContent).toContain("Could not load your cards");
  });
});
