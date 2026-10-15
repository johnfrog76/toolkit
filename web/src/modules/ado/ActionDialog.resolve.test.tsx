import { fireEvent, render, screen, within } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";

// Closing asks first. The owner's sketch: "Are you sure? Close issue
// #<n>." [Cancel] [Submit]. The resolve tab says what happens and names its
// button for the act; that button opens the confirm; only Submit runs the
// verb, and Cancel runs nothing.
let tracker = "github";
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker } }),
  // The public line is ActionDialog.titles.test.tsx's subject.
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));

const resolveBug = jest.fn(() => ({
  unwrap: () => Promise.resolve({ status: "success", output: "closed" }),
}));
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: undefined }),
  useCreatePromptMutation: () => [jest.fn()],
  useUploadAssetMutation: () => [jest.fn()],
  useResolveBugMutation: () => [resolveBug],
  useCreatePRMutation: () => [jest.fn()],
  useCreateAdoItemMutation: () => [jest.fn()],
}));

function mount() {
  return render(
    <ActionDialog
      open
      onClose={() => {}}
      tab="resolve"
      initialWorkItemId="73"
      initialWorkItemType="Feature"
    />,
  );
}

function fillComment() {
  fireEvent.change(screen.getByPlaceholderText("e.g. Fixed in PR 141234"), {
    target: { value: "done in a4bd74d" },
  });
}

// The confirm opens OVER the form, so its buttons are found inside it.
function confirmDialog(): HTMLElement {
  return screen.getByText("Are you sure?").closest('[role="dialog"]') as HTMLElement;
}

beforeEach(() => resolveBug.mockClear());

describe("closing an issue asks first", () => {
  // The confirm was a CHILD of the form's Dialog, which made Fluent read
  // the form's surface as a trigger -- drawn on every page, closed or not.
  it("a closed dialog draws nothing at all", () => {
    tracker = "github";
    render(<ActionDialog open={false} onClose={() => {}} tab="resolve" initialWorkItemId="73" />);
    expect(screen.queryByText("Close issue #73")).toBeNull();
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("the form's dismiss closes it", () => {
    tracker = "github";
    const onClose = jest.fn();
    render(<ActionDialog open onClose={onClose} tab="resolve" initialWorkItemId="73" />);
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("says what it does, and the button names the act", () => {
    tracker = "github";
    mount();
    expect(screen.getByText("Close issue #73")).toBeTruthy();
    expect(screen.getByText(/can be reopened on GitHub/)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Close issue" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Submit" })).toBeNull();
  });

  it("Cancel on the confirm runs nothing", () => {
    tracker = "github";
    mount();
    fillComment();
    fireEvent.click(screen.getByRole("button", { name: "Close issue" }));
    const confirm = confirmDialog();
    expect(within(confirm).getByText("Close issue #73.")).toBeTruthy();
    fireEvent.click(within(confirm).getByRole("button", { name: "Cancel" }));
    expect(screen.queryByText("Are you sure?")).toBeNull();
    expect(resolveBug).not.toHaveBeenCalled();
  });

  it("the dismiss top right runs nothing either", () => {
    tracker = "github";
    mount();
    fillComment();
    fireEvent.click(screen.getByRole("button", { name: "Close issue" }));
    fireEvent.click(within(confirmDialog()).getByRole("button", { name: "Close" }));
    expect(screen.queryByText("Are you sure?")).toBeNull();
    expect(resolveBug).not.toHaveBeenCalled();
  });

  it("Submit on the confirm closes it, once", () => {
    tracker = "github";
    mount();
    fillComment();
    fireEvent.click(screen.getByRole("button", { name: "Close issue" }));
    expect(resolveBug).not.toHaveBeenCalled();
    fireEvent.click(within(confirmDialog()).getByRole("button", { name: "Submit" }));
    expect(resolveBug).toHaveBeenCalledTimes(1);
  });

  it("on ADO the same step says Resolve work item", () => {
    tracker = "ado";
    mount();
    fillComment();
    fireEvent.click(screen.getByRole("button", { name: "Resolve work item" }));
    expect(within(confirmDialog()).getByText("Resolve work item #73.")).toBeTruthy();
  });
});
