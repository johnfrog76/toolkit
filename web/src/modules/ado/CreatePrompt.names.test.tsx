import { fireEvent, render, screen } from "@testing-library/react";
import { PromptActions } from "./CreatePrompt";

// Every field on every tab has a programmatic name that matches its visible
// caption; before, a screen reader announced the placeholder ("e.g. 223061").
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker: "ado" } }),
}));
jest.mock("./api.ado", () => ({
  useCreatePromptMutation: () => [jest.fn()],
  useCreatePRMutation: () => [jest.fn()],
  useFetchPrCommentsMutation: () => [jest.fn()],
  useResolveBugMutation: () => [jest.fn()],
  useCreateAdoItemMutation: () => [jest.fn()],
}));

function openTab(name: string) {
  fireEvent.click(screen.getByRole("radio", { name }));
}

describe("PromptActions fields are named by their captions", () => {
  it("Create from Work Item", () => {
    render(<PromptActions />);
    openTab("Create from Work Item");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Assignment" })).toBeTruthy();
  });

  it("Fetch PR Comments", () => {
    render(<PromptActions />);
    openTab("Fetch PR Comments");
    expect(screen.getByRole("textbox", { name: "PR ID" })).toBeTruthy();
  });

  it("Resolve Work Item", () => {
    render(<PromptActions />);
    openTab("Resolve Work Item");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Reason" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Comment" })).toBeTruthy();
  });

  it("Create PR", () => {
    render(<PromptActions />);
    openTab("Create PR");
    expect(screen.getByRole("textbox", { name: "Work Item ID" })).toBeTruthy();
    expect(screen.getByRole("textbox", { name: "Target Branch" })).toBeTruthy();
  });

  it("New ADO Item", () => {
    render(<PromptActions />);
    openTab("New ADO Item");
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
});
