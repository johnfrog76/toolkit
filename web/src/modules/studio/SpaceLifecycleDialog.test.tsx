import { act, fireEvent, render, screen } from "@testing-library/react";
import { SpaceLifecycleDialog } from "./SpaceLifecycleDialog";
import type { SpaceInfo } from "../../shell/api";

// Retire and Remove from a Space's row: the house confirm over
// RetireSpace / RemoveSpace through the bridge. The verb's -WhatIf is shown
// before Submit can be pressed; a confirmed Remove carries -Force (the bridge
// cannot answer the verb's own question); a refusal stays in the dialog in the
// verb's words. The verbs themselves are tkTestToolkit -NewSpace's.
type Reply = { status: string; output: string | null; error: string | null };
let previewReply: Reply = { status: "success", output: "", error: null };
let runReply: Reply = { status: "success", output: "", error: null };
const previews: { verb: string; params: string[] }[] = [];
const runs: { verb: string; params: string[] }[] = [];
// Stable triggers, as RTK Query's are: the preview runs once, on open.
function mockPreview(arg: { verb: string; params: string[] }) {
  previews.push(arg);
  return {
    unwrap: () =>
      Promise.resolve({ command: arg.verb, exit_code: 0, duration: 1, ...previewReply }),
  };
}
function mockRun(arg: { verb: string; params: string[] }) {
  runs.push(arg);
  return {
    unwrap: () => Promise.resolve({ command: arg.verb, exit_code: 0, duration: 1, ...runReply }),
  };
}
jest.mock("./api.studio", () => ({
  usePreviewSpaceLifecycleMutation: () => [mockPreview, { isLoading: false }],
  useRunSpaceLifecycleMutation: () => [mockRun, { isLoading: false }],
}));

const ACME: SpaceInfo = { slug: "acme", name: "Acme", status: "active" };

async function mount(verb: "RetireSpace" | "RemoveSpace", onDone = jest.fn(), onClose = jest.fn()) {
  await act(async () => {
    render(
      <SpaceLifecycleDialog target={{ space: ACME, verb }} onClose={onClose} onDone={onDone} />,
    );
  });
  return { onDone, onClose };
}

const submit = (label: string) => screen.getByRole("button", { name: label }) as HTMLButtonElement;

beforeEach(() => {
  previews.length = 0;
  runs.length = 0;
  previewReply = { status: "success", output: "", error: null };
  runReply = { status: "success", output: "", error: null };
});

describe("retiring or removing a Space from its row", () => {
  it("Remove shows the verb's -WhatIf -- the key that goes, the folder that stays -- then runs with -Force", async () => {
    previewReply = {
      status: "success",
      output:
        "[WhatIf] tkConfig -Unset spaces.acme -Hub\n[WhatIf] its folder stays as it is: /hub/acme -- 3 cards (2 current, 1 archive)",
      error: null,
    };
    const { onDone } = await mount("RemoveSpace");
    expect(previews).toEqual([{ verb: "RemoveSpace", params: ["acme", "-WhatIf"] }]);
    expect(screen.getByTestId("space-lifecycle-preview").textContent).toContain(
      "3 cards (2 current, 1 archive)",
    );
    expect(screen.getByText(/Its folder and every card in it stay in the hub/)).toBeTruthy();
    await act(async () => {
      fireEvent.click(submit("Remove"));
    });
    expect(runs).toEqual([{ verb: "RemoveSpace", params: ["acme", "-Force"] }]);
    expect(onDone).toHaveBeenCalledWith(
      "Removed Acme. Its folder and every card in it stay in the hub.",
    );
  });

  it("Retire runs the verb with the slug alone", async () => {
    previewReply = {
      status: "success",
      output: "[WhatIf] tkConfig -Set spaces.acme.status=archive -Hub",
      error: null,
    };
    const { onDone } = await mount("RetireSpace");
    expect(screen.getByText(/It stays a Space, archived/)).toBeTruthy();
    await act(async () => {
      fireEvent.click(submit("Retire"));
    });
    expect(runs).toEqual([{ verb: "RetireSpace", params: ["acme"] }]);
    expect(onDone).toHaveBeenCalledWith("Retired Acme. It is under Archive, its cards kept.");
  });

  it("a refused preview is said in the verb's words, and Submit stays shut while Cancel works", async () => {
    previewReply = {
      status: "error",
      output: null,
      error:
        "Azure demo (azure-demo) ships in config.default.json, so it is the team's and cannot be removed -- only hidden or retired.",
    };
    const { onClose } = await mount("RemoveSpace");
    expect(screen.getByRole("alert").textContent).toContain("cannot be removed");
    expect(submit("Remove").disabled).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onClose).toHaveBeenCalled();
    expect(runs).toEqual([]);
  });

  it("a refused run stays in the dialog, and nothing is said on the card", async () => {
    previewReply = { status: "success", output: "[WhatIf] x", error: null };
    runReply = {
      status: "error",
      output: null,
      error: "Acme (acme) is the Space you are in; switch to another before removing it.",
    };
    const { onDone } = await mount("RemoveSpace");
    await act(async () => {
      fireEvent.click(submit("Remove"));
    });
    expect(screen.getByRole("alert").textContent).toContain("the Space you are in");
    expect(onDone).not.toHaveBeenCalled();
  });

  it("closed, it draws nothing and asks nothing", async () => {
    await act(async () => {
      render(<SpaceLifecycleDialog target={null} onClose={jest.fn()} onDone={jest.fn()} />);
    });
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(previews).toEqual([]);
  });
});
