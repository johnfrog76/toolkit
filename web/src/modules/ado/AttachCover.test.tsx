import { act, fireEvent, render, screen } from "@testing-library/react";
import { STAMPS } from "../../shell/consts";
import { AttachActions, AttachZone } from "./AttachCover";

// Attach a card's picture from the browser (C2): the bytes go to the
// upload route, the path comes back, and the Cover verb runs through the
// bridge with it -- one writer. With no cover the zone IS the cover's box;
// with one, the header offers Replace cover, Add before, Remove cover.

const uploaded: File[] = [];
let uploadReply: { path: string } | { error: { status: number; data: { detail: string } } } = {
  path: "p20-upload-1/shot.png",
};
const ran: string[][] = [];
let coverReply: { status: string; output: string | null; error: string | null } = {
  status: "success",
  output: "Attached cover.png to K7M2-a-card.prompt.md",
  error: null,
};
jest.mock("./api.ado", () => ({
  useUploadAssetMutation: () => [
    ({ file }: { file: File }) => {
      uploaded.push(file);
      return {
        unwrap: () =>
          "error" in uploadReply
            ? Promise.reject({ data: uploadReply.error.data })
            : Promise.resolve(uploadReply),
      };
    },
    { isLoading: false },
  ],
  useAttachCoverMutation: () => [
    ({ params }: { params: string[] }) => {
      ran.push(params);
      return {
        unwrap: () =>
          Promise.resolve({ command: "Cover", exit_code: 0, duration: 1, ...coverReply }),
      };
    },
    { isLoading: false },
  ],
}));

const png = (name = "shot.png") => new File([new Uint8Array(16)], name, { type: "image/png" });
// The stamps come from the contract, never typed (the consts suite's guard).
const BARE = `# K7M2: a card\n\n${STAMPS.created} 2026-10-01\n`;
const COVERED = `# K7M2: a card\n\n${STAMPS.cover} ../assets/K7M2/cover.png\n${STAMPS.created} 2026-10-01\n`;
const FILE = "K7M2-a-card.prompt.md";

beforeEach(() => {
  uploaded.length = 0;
  ran.length = 0;
  uploadReply = { path: "p20-upload-1/shot.png" };
  coverReply = {
    status: "success",
    output: "Attached cover.png to K7M2-a-card.prompt.md",
    error: null,
  };
});

describe("the zone for a card with no cover", () => {
  it("uploads the picture, then runs Cover with the card's file and the path, and says the verb's line", async () => {
    const done = jest.fn();
    render(<AttachZone filename={FILE} content={BARE} kind="cover" onDone={done} />);
    // Two things answer to "Add cover": the zone (a group you drop on -- no
    // longer a second button) and the button that runs the verb.
    expect(
      screen.getByRole("group", { name: "Add cover" }).getAttribute("data-image-drop-zone"),
    ).toBe("");
    const attach = screen.getByRole("button", { name: "Add cover" });
    expect(attach.tagName).toBe("BUTTON");
    expect(attach.hasAttribute("disabled")).toBe(true);
    fireEvent.change(screen.getByLabelText("Add cover: choose a file"), {
      target: { files: [png()] },
    });
    expect(attach.hasAttribute("disabled")).toBe(false);
    await act(async () => {
      fireEvent.click(attach);
    });
    expect(uploaded.map((f) => f.name)).toEqual(["shot.png"]);
    expect(ran).toEqual([[FILE, "p20-upload-1/shot.png"]]);
    expect(done).toHaveBeenCalledTimes(1);
    expect(screen.getByText("Attached cover.png to K7M2-a-card.prompt.md")).toBeTruthy();
  });

  it("a before goes with -Before, and the zone can be cancelled when it was asked for", async () => {
    const close = jest.fn();
    render(
      <AttachZone
        filename={FILE}
        content={COVERED}
        kind="before"
        onDone={jest.fn()}
        onClose={close}
      />,
    );
    fireEvent.change(screen.getByLabelText("Add before: choose a file"), {
      target: { files: [png("wrong.png")] },
    });
    await act(async () => {
      fireEvent.click(
        screen.getAllByRole("button", { name: "Add before" }).find((b) => b.tagName === "BUTTON")!,
      );
    });
    expect(ran).toEqual([[FILE, "p20-upload-1/shot.png", "-Before"]]);
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(close).toHaveBeenCalled();
  });

  it("the upload's refusal is said in the route's words, and Cover never runs", async () => {
    uploadReply = {
      error: {
        status: 413,
        data: { detail: "shot.png is 6,000,000 bytes; Cover copies at most 5,242,880." },
      },
    };
    render(<AttachZone filename={FILE} content={BARE} kind="cover" onDone={jest.fn()} />);
    fireEvent.change(screen.getByLabelText("Add cover: choose a file"), {
      target: { files: [png()] },
    });
    await act(async () => {
      fireEvent.click(
        screen.getAllByRole("button", { name: "Add cover" }).find((b) => b.tagName === "BUTTON")!,
      );
    });
    expect(ran).toEqual([]);
    expect(screen.getByRole("alert").textContent).toBe(
      "shot.png is 6,000,000 bytes; Cover copies at most 5,242,880.",
    );
  });

  // A drop STAGES the picture; the button attaches it. So the zone says which
  // button, in that button's own words, and the button takes focus.
  it("a dropped picture names the button to press, and the button takes focus", () => {
    render(<AttachZone filename={FILE} content={BARE} kind="cover" onDone={jest.fn()} />);
    const attach = screen.getByRole("button", { name: "Add cover" });
    fireEvent.drop(screen.getByRole("group", { name: "Add cover" }), {
      dataTransfer: { files: [png("first.png")], items: [] },
    });
    expect(screen.getByRole("group", { name: "Add cover: first.png" })).toBeTruthy();
    expect(screen.getByRole("status").textContent).toBe("Press Add cover to attach it.");
    expect(document.activeElement).toBe(attach);
    // A second drop replaces the staged picture, and says so.
    fireEvent.drop(screen.getByRole("group", { name: "Add cover: first.png" }), {
      dataTransfer: { files: [png("second.png")], items: [] },
    });
    expect(screen.getByRole("group", { name: "Add cover: second.png" })).toBeTruthy();
    expect(screen.getByRole("status").textContent).toBe(
      "Replaced first.png. Press Add cover to attach it.",
    );
  });

  it("the verb's refusal is said in its words", async () => {
    coverReply = {
      status: "error",
      output: "Error: No card matches 'K7M2-a-card.prompt.md'.",
      error: "exit code 2",
    };
    render(<AttachZone filename={FILE} content={BARE} kind="cover" onDone={jest.fn()} />);
    fireEvent.change(screen.getByLabelText("Add cover: choose a file"), {
      target: { files: [png()] },
    });
    await act(async () => {
      fireEvent.click(
        screen.getAllByRole("button", { name: "Add cover" }).find((b) => b.tagName === "BUTTON")!,
      );
    });
    expect(screen.getByRole("alert").textContent).toContain("No card matches");
  });
});

describe("the header's actions for a card with a cover", () => {
  it("draws nothing for a card without one", () => {
    render(<AttachActions filename={FILE} content={BARE} onDone={jest.fn()} onAsk={jest.fn()} />);
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("offers Replace cover, Add before and Remove cover", async () => {
    const ask = jest.fn();
    render(<AttachActions filename={FILE} content={COVERED} onDone={jest.fn()} onAsk={ask} />);
    fireEvent.click(screen.getByRole("button", { name: "Replace cover" }));
    expect(ask).toHaveBeenCalledWith("cover");
    fireEvent.click(screen.getByRole("button", { name: "Actions for the cover" }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Add before", "Remove cover"]);
    fireEvent.click(screen.getByRole("menuitem", { name: "Add before" }));
    expect(ask).toHaveBeenCalledWith("before");
  });

  it("Remove asks first, then runs Cover -Remove", async () => {
    const done = jest.fn();
    render(<AttachActions filename={FILE} content={COVERED} onDone={done} onAsk={jest.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Actions for the cover" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Remove cover" }));
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(ran).toEqual([]);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Remove" }));
    });
    expect(ran).toEqual([[FILE, "-Remove"]]);
    expect(done).toHaveBeenCalled();
  });
});
