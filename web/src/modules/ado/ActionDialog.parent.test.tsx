import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";
import type { NewAdoItemFields } from "./cliBridge";

// The new-item door with a parent: Team Agile's Split opens it with the issue in
// front named (initialParent), on a GitHub Space as on Azure DevOps. The parent
// travels as -Parent through POST /api/cmd/NewItem; the CLI makes the link (a
// sub-issue on GitHub) and says so, and the dialog shows what it said.
let tracker = "github";
const created: NewAdoItemFields[] = [];
let output = "";
const createAdoItem = (fields: NewAdoItemFields) => {
  created.push(fields);
  return {
    unwrap: () =>
      Promise.resolve({
        command: "NewItem",
        status: "success",
        exit_code: 0,
        output,
        error: null,
        duration: 0,
      }),
  };
};
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
  useCreateAdoItemMutation: () => [createAdoItem],
}));

beforeEach(() => {
  tracker = "github";
  created.length = 0;
  output = "";
});

function parentField(name: string): HTMLInputElement {
  return screen.getByRole("textbox", { name }) as HTMLInputElement;
}

describe("the new-item door names a parent", () => {
  it("on a GitHub Space the parent issue is offered, and Split's parent fills it", () => {
    render(<ActionDialog open onClose={() => {}} tab="new-item" initialParent={140} />);
    expect(parentField("Parent issue").value).toBe("140");
  });

  it("opened with no parent, the field is there and empty", () => {
    render(<ActionDialog open onClose={() => {}} tab="new-item" />);
    expect(parentField("Parent issue").value).toBe("");
  });

  it("the create sends the parent, and the CLI's link is shown as it said it", async () => {
    output =
      "[+] Created: issue #141 -- The read half\n[+] Linked: #141 is a sub-issue of #140 -- https://github.com/acme/widgets/issues/140";
    render(<ActionDialog open onClose={() => {}} tab="new-item" initialParent={140} />);
    fireEvent.change(screen.getByPlaceholderText("e.g. Add dark mode toggle"), {
      target: { value: "The read half" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    await waitFor(() => expect(created).toHaveLength(1));
    expect(created[0]).toMatchObject({ title: "The read half", parent: 140 });
    expect(await screen.findByText(/is a sub-issue of #140/)).toBeTruthy();
    // The parent stays for the next piece of the split; the title is cleared.
    expect(parentField("Parent issue").value).toBe("140");
    expect(
      (screen.getByPlaceholderText("e.g. Add dark mode toggle") as HTMLInputElement).value,
    ).toBe("");
  });

  it("on Azure DevOps the field keeps its own name", () => {
    tracker = "ado";
    render(<ActionDialog open onClose={() => {}} tab="new-item" initialParent={195551} />);
    expect(parentField("Parent ID").value).toBe("195551");
  });
});
