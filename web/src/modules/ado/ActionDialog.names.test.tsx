import { render, screen } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";
import type { ActionDialogTab } from "./ActionDialog";

// Every field in every door has a programmatic name that matches its visible
// caption. Without one a screen reader announces the placeholder ("e.g.
// 223061") instead, and the read-only Completed field has no name at all.
let tracker = "ado";
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker } }),
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
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

function mount(tab: ActionDialogTab, type = "", id = "") {
  tracker = "ado";
  return render(
    <ActionDialog
      open
      onClose={() => {}}
      tab={tab}
      initialWorkItemId={id}
      initialWorkItemType={type}
    />,
  );
}

describe("ActionDialog fields are named by their captions", () => {
  it("the work item door", () => {
    mount("create", "", "55");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Assignment" })).toBeTruthy();
  });

  it("the resolve door for a bug", () => {
    mount("resolve", "Bug", "73");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Reason" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Comment" })).toBeTruthy();
  });

  it("the resolve door for anything else names the read-only Completed field", () => {
    mount("resolve", "Feature", "73");
    expect(screen.getByRole("textbox", { name: "Resolution" })).toHaveProperty(
      "value",
      "Completed",
    );
    expect(screen.getByRole("textbox", { name: "Comment" })).toBeTruthy();
  });

  it("the pull request door", () => {
    mount("pr", "", "55");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Target Branch" })).toBeTruthy();
  });

  it("the new item door", () => {
    mount("new-item");
    expect(screen.getByRole("combobox", { name: "Type" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: /^Title/ })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Project" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Sprint" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Parent ID" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Acceptance Criteria" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Description" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Priority" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Points" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Tags" })).toBeTruthy();
  });

  it("no two captions in a door share an id", () => {
    mount("new-item");
    const ids = Array.from(document.querySelectorAll("[id]")).map((e) => e.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
