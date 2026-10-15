import { useRef, useState } from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { ImageDropZone, imageFrom, imageProblem, namedFile } from "./ImageDropZone";

// A place you can see and aim at (C2): the three ways in -- drop, paste,
// choose a file -- hand the caller ONE image; what the verb would refuse is
// refused here first in its words; the zone keeps its box either way.

const png = (name = "shot.png", size = 16) =>
  new File([new Uint8Array(size)], name, { type: "image/png" });

function transfer(files: File[]): DataTransfer {
  return {
    files,
    items: files.map((f) => ({ kind: "file", type: f.type, getAsFile: () => f })),
  } as unknown as DataTransfer;
}

describe("the rules", () => {
  it("a type the verb takes, under the limit, is no problem; the rest say the verb's sentence", () => {
    expect(imageProblem({ name: "shot.png", size: 10 })).toBeNull();
    expect(imageProblem({ name: "shot.WEBP", size: 10 })).toBeNull();
    expect(imageProblem({ name: "notes.txt", size: 10 })).toBe(
      "notes.txt is not an image type Cover accepts (png, jpg, jpeg, webp, gif).",
    );
    expect(imageProblem({ name: "big.png", size: 5 * 1024 * 1024 + 1 })).toBe(
      "big.png is 5,242,881 bytes; Cover copies at most 5,242,880.",
    );
  });

  it("takes the one image among what was dropped or pasted", () => {
    const a = png("a.png");
    expect(imageFrom(transfer([new File(["x"], "notes.txt", { type: "text/plain" }), a]))).toBe(a);
    expect(imageFrom(transfer([]))).toBeNull();
    expect(imageFrom(null)).toBeNull();
  });

  it("a pasted snap with no name gets one the verb can take, from its type", () => {
    expect(namedFile(new File(["x"], "", { type: "image/png" })).name).toBe("pasted.png");
    expect(namedFile(new File(["x"], "", { type: "image/jpeg" })).name).toBe("pasted.jpg");
    expect(namedFile(png("kept.png")).name).toBe("kept.png");
  });
});

describe("the zone", () => {
  let held: File | null = null;
  const onFile = (f: File | null) => {
    held = f;
  };

  beforeEach(() => {
    held = null;
  });

  // The zone is a named group, not a button -- a button holding the
  // Choose a file button was axe's nested-interactive. The Button inside is
  // the one thing a keyboard reaches.
  it("is a visible, named zone with the three ways in, and the file picker is its fallback", () => {
    render(<ImageDropZone label="Add cover" file={null} onFile={onFile} />);
    expect(screen.getByRole("group", { name: "Add cover" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Add cover" })).toBeNull();
    expect(screen.getByRole("group", { name: "Add cover" }).hasAttribute("tabindex")).toBe(false);
    expect(screen.getByText("Drop an image here, paste one, or")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Choose a file" })).toBeTruthy();
    const input = screen.getByLabelText("Add cover: choose a file") as HTMLInputElement;
    expect(input.getAttribute("accept")).toBe(".png,.jpg,.jpeg,.webp,.gif");
    fireEvent.change(input, { target: { files: [png("picked.png")] } });
    expect(held?.name).toBe("picked.png");
  });

  it("a drop hands over the image", () => {
    render(<ImageDropZone label="Add cover" file={null} onFile={onFile} />);
    fireEvent.drop(screen.getByRole("group", { name: "Add cover" }), {
      dataTransfer: transfer([png("dropped.png")]),
    });
    expect(held?.name).toBe("dropped.png");
  });

  it("a paste hands over the image, named when the clipboard gave none", () => {
    render(<ImageDropZone label="Add cover" file={null} onFile={onFile} />);
    // Pasted with the zone's Button focused: the event bubbles to the zone.
    fireEvent.paste(screen.getByRole("button", { name: "Choose a file" }), {
      clipboardData: transfer([new File([new Uint8Array(8)], "", { type: "image/png" })]),
    });
    expect(held?.name).toBe("pasted.png");
  });

  it("a file the verb would refuse is refused here, in its words, and not handed over", () => {
    render(<ImageDropZone label="Add cover" file={null} onFile={onFile} />);
    fireEvent.drop(screen.getByRole("group", { name: "Add cover" }), {
      dataTransfer: transfer([new File(["x"], "notes.txt", { type: "text/plain" })]),
    });
    expect(held).toBeNull();
    expect(screen.getByRole("alert").textContent).toBe(
      "notes.txt is not an image type Cover accepts (png, jpg, jpeg, webp, gif).",
    );
  });

  it("holding a file it names it, keeps its box, and Remove gives it back", () => {
    const file = png("shot.png");
    render(<ImageDropZone label="Add cover" file={file} onFile={onFile} />);
    const zone = screen.getByRole("group", { name: "Add cover: shot.png" });
    expect(zone.getAttribute("data-image-drop-zone")).toBe("");
    expect(screen.getByText("shot.png")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Choose a file" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Remove shot.png" }));
    expect(held).toBeNull();
  });

  // A drop stages the file; the caller's button acts on it. The zone reads
  // that button's label rather than being told it, so the two never drift.
  describe("what happens next", () => {
    function Staged({ action, disabled = false }: { action: string; disabled?: boolean }) {
      const [file, setFile] = useState<File | null>(null);
      const ref = useRef<HTMLButtonElement>(null);
      return (
        <>
          <ImageDropZone label="A picture" file={file} onFile={setFile} next={ref} />
          <button ref={ref} disabled={disabled || !file}>
            {action}
          </button>
        </>
      );
    }
    const drop = (name: string, from = "A picture") =>
      fireEvent.drop(screen.getByRole("group", { name: from }), {
        dataTransfer: transfer([png(name)]),
      });

    it("names the file, says which button to press in its own words, and hands it focus", () => {
      render(<Staged action="Make it so" />);
      drop("one.png");
      expect(screen.getByText("one.png")).toBeTruthy();
      expect(screen.getByRole("status").textContent).toBe("Press Make it so to attach it.");
      expect(document.activeElement).toBe(screen.getByRole("button", { name: "Make it so" }));
    });

    it("a second drop replaces the first, and says so", () => {
      render(<Staged action="Attach" />);
      drop("one.png");
      drop("two.png", "A picture: one.png");
      expect(screen.getByRole("group", { name: "A picture: two.png" })).toBeTruthy();
      expect(screen.getByRole("status").textContent).toBe(
        "Replaced one.png. Press Attach to attach it.",
      );
    });

    it("Remove takes the sentence with the file; a button that cannot act is not focused", () => {
      render(<Staged action="Attach" disabled />);
      drop("one.png");
      expect(document.activeElement).not.toBe(screen.getByRole("button", { name: "Attach" }));
      fireEvent.click(screen.getByRole("button", { name: "Remove one.png" }));
      expect(screen.queryByRole("status")).toBeNull();
      drop("two.png");
      expect(screen.getByRole("status").textContent).toBe("Press Attach to attach it.");
    });

    it("with no button named, the zone holds the file and says nothing more", () => {
      render(<ImageDropZone label="A picture" file={png("one.png")} onFile={onFile} />);
      expect(screen.queryByRole("status")).toBeNull();
    });
  });

  it("disabled takes nothing", () => {
    render(<ImageDropZone label="Add cover" file={null} onFile={onFile} disabled />);
    fireEvent.drop(screen.getByRole("group", { name: "Add cover" }), {
      dataTransfer: transfer([png()]),
    });
    expect(held).toBeNull();
  });
});
