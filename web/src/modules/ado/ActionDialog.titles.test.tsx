import { render, screen } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";
import { VISIBILITY } from "../../shell/consts";

// The string pass: the single dialog's title names the tracker and the
// thing made, door by door. The pickup door said "Create from Work Item" /
// "Create from Issue" -- the act, but not what it makes or from where.
let tracker = "github";
// The Space's repository visibility, as GET /api/visibility answers it.
let visibility = "private";
const askedVisibility: boolean[] = [];
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker } }),
  useGetSpaceVisibilityQuery: (_space: string, opts: { skip?: boolean }) => {
    askedVisibility.push(!opts?.skip);
    return opts?.skip ? { data: undefined } : { data: { supported: true, visibility, repos: [] } };
  },
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: undefined }),
  useCreatePromptMutation: () => [jest.fn()],
  useUploadAssetMutation: () => [jest.fn()],
  useResolveBugMutation: () => [jest.fn()],
  useCreatePRMutation: () => [jest.fn()],
  useCreateAdoItemMutation: () => [jest.fn()],
}));

function title(): string {
  return screen.getByRole("dialog").querySelector("h2")?.textContent ?? "";
}

describe("the single dialog's title says where and what", () => {
  it.each([
    ["github", "create", "Card from a GitHub Issue"],
    ["ado", "create", "Card from an ADO Work Item"],
    ["github", "new-item", "New GitHub Issue"],
    ["ado", "new-item", "New ADO Item"],
  ] as const)("%s, %s door: %s", (tr, tab, expected) => {
    tracker = tr;
    render(
      <ActionDialog
        open
        onClose={() => {}}
        tab={tab}
        initialWorkItemId={tab === "create" ? "73" : ""}
      />,
    );
    expect(title()).toBe(expected);
  });
});

// On stage: a write to a public repository carries one line, and asks
// nothing. The doors that write to the tracker -- a new issue, a close, a pull
// request -- carry it; the card's own door does not.
describe("a write to a public repository says so", () => {
  const LINE = VISIBILITY.publicLine;
  beforeEach(() => {
    tracker = "github";
    visibility = "public";
    askedVisibility.length = 0;
  });

  it.each(["new-item", "resolve", "pr"] as const)("the %s door carries the line", (tab) => {
    render(<ActionDialog open onClose={() => {}} tab={tab} initialWorkItemId="73" />);
    expect(screen.getByText(LINE)).toBeTruthy();
  });

  it("the card's door writes to the hub, not the tracker: no line", () => {
    render(<ActionDialog open onClose={() => {}} tab="create" initialWorkItemId="73" />);
    expect(screen.queryByText(LINE)).toBeNull();
  });

  it.each(["private", "unknown"])("a %s repository carries none", (v) => {
    visibility = v;
    render(<ActionDialog open onClose={() => {}} tab="new-item" />);
    expect(screen.queryByText(LINE)).toBeNull();
  });

  it("on Azure DevOps the question is not asked", () => {
    tracker = "ado";
    render(<ActionDialog open onClose={() => {}} tab="new-item" />);
    expect(screen.queryByText(LINE)).toBeNull();
    expect(askedVisibility.every((asked) => !asked)).toBe(true);
  });
});
