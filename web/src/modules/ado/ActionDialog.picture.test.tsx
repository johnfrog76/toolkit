import { act, fireEvent, render, screen } from "@testing-library/react";
import { ActionDialog } from "./ActionDialog";

// The + dialog takes a picture at birth (docs/hub/cards.md, "A card's pictures"): a visible zone on the New ToolKit Card door, the upload
// first -- a temp file, nothing in the hub -- then NewPrompt with -Cover, or
// -Before when the snap shows what is wrong. A refusal from the upload is said
// and no card is made.

jest.mock("../../shell/api", () => ({
  // A local Space: no Azure DevOps, so the only door is the new card's.
  useGetEnvQuery: () => ({
    data: {
      tracker: "none",
      spaceStatus: "local",
      tier: 2,
      ado: { enabled: false },
      cardTypes: ["Task", "Bug"],
    },
  }),
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));

const uploaded: File[] = [];
let uploadReply: { path: string } | { reject: string } = { path: "p20-upload-7/shot.png" };
const created: string[][] = [];
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: undefined }),
  useCreatePromptMutation: () => [
    ({ params }: { params: string[] }) => {
      created.push(params);
      return {
        unwrap: () =>
          Promise.resolve({
            command: "NewPrompt",
            status: "success",
            exit_code: 0,
            output: "Created K7M2",
            error: null,
            duration: 1,
          }),
      };
    },
  ],
  useUploadAssetMutation: () => [
    ({ file }: { file: File }) => {
      uploaded.push(file);
      return {
        unwrap: () =>
          "reject" in uploadReply
            ? Promise.reject({ data: { detail: uploadReply.reject } })
            : Promise.resolve(uploadReply),
      };
    },
  ],
  useResolveBugMutation: () => [jest.fn()],
  useCreatePRMutation: () => [jest.fn()],
  useCreateAdoItemMutation: () => [jest.fn()],
}));

const png = (name = "shot.png") => new File([new Uint8Array(16)], name, { type: "image/png" });

function mount() {
  render(<ActionDialog open onClose={() => {}} tab="create" />);
  fireEvent.change(screen.getByPlaceholderText("e.g. Wallet ticket from a QR code"), {
    target: { value: "A card with a picture" },
  });
}

beforeEach(() => {
  uploaded.length = 0;
  created.length = 0;
  uploadReply = { path: "p20-upload-7/shot.png" };
});

describe("the + dialog's picture", () => {
  it("offers a visible zone, and without a picture NewPrompt gets no -Cover", async () => {
    mount();
    expect(screen.getByText("A picture, if you have one")).toBeTruthy();
    // A named group, not a button (nested-interactive).
    expect(
      screen
        .getByRole("group", { name: "A picture for the card" })
        .getAttribute("data-image-drop-zone"),
    ).toBe("");
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(uploaded).toEqual([]);
    expect(created).toEqual([["-Title", "A card with a picture", "-Type", "Task"]]);
  });

  it("with a picture: the upload first, then NewPrompt -Cover with the path it answered", async () => {
    mount();
    fireEvent.change(screen.getByLabelText("A picture for the card: choose a file"), {
      target: { files: [png()] },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(uploaded.map((f) => f.name)).toEqual(["shot.png"]);
    expect(created).toEqual([
      ["-Title", "A card with a picture", "-Type", "Task", "-Cover", "p20-upload-7/shot.png"],
    ]);
  });

  it("a chosen picture names the dialog's button, and the button takes focus", () => {
    mount();
    const submit = screen.getByRole("button", { name: /submit|create/i });
    fireEvent.change(screen.getByLabelText("A picture for the card: choose a file"), {
      target: { files: [png()] },
    });
    expect(screen.getByRole("status").textContent).toBe(
      `Press ${submit.textContent} to attach it.`,
    );
    expect(document.activeElement).toBe(submit);
  });

  it("marked as what is wrong, it is the before", async () => {
    mount();
    fireEvent.change(screen.getByLabelText("A picture for the card: choose a file"), {
      target: { files: [png("wrong.png")] },
    });
    fireEvent.click(
      screen.getByRole("checkbox", { name: "It shows what is wrong (a before, not the cover)" }),
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(created).toEqual([
      ["-Title", "A card with a picture", "-Type", "Task", "-Before", "p20-upload-7/shot.png"],
    ]);
  });

  it("the upload's refusal is said, and no card is made", async () => {
    uploadReply = { reject: "shot.png is 6,000,000 bytes; Cover copies at most 5,242,880." };
    mount();
    fireEvent.change(screen.getByLabelText("A picture for the card: choose a file"), {
      target: { files: [png()] },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /submit|create/i }));
    });
    expect(created).toEqual([]);
    expect(screen.getByText(/Cover copies at most 5,242,880/)).toBeTruthy();
  });
});
