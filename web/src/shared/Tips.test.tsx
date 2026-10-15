import { render, screen, fireEvent } from "@testing-library/react";
import { Tips, resetTipRotation, tipsReady } from "./Tips";
import type { Tip } from "./Tips";

const tip = (id: string, onAction: () => void = jest.fn()): Tip => ({
  id,
  sentence: `Sentence ${id}.`,
  cta: "Try it",
  onAction,
});

describe("Tips", () => {
  beforeEach(() => resetTipRotation());

  it("renders nothing from an empty pool -- every condition met, nothing to teach", () => {
    const { container } = render(<Tips tips={[]} />);
    expect(container.innerHTML).toBe("");
  });

  it("shows one tip -- the Tips: label, the sentence, and a CTA that does the thing", () => {
    const doIt = jest.fn();
    render(<Tips tips={[tip("boards", doIt)]} />);
    expect(screen.getByText("Tips:")).toBeTruthy();
    expect(screen.getByText(/Sentence boards\./)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Try it" }));
    expect(doIt).toHaveBeenCalled();
  });

  it("rotates: each mount shows the next tip, wrapping at the end", () => {
    const pool = [tip("a"), tip("b")];
    const first = render(<Tips tips={pool} />);
    expect(screen.getByText(/Sentence a\./)).toBeTruthy();
    first.unmount();
    const second = render(<Tips tips={pool} />);
    expect(screen.getByText(/Sentence b\./)).toBeTruthy();
    second.unmount();
    render(<Tips tips={pool} />);
    expect(screen.getByText(/Sentence a\./)).toBeTruthy();
  });

  it("shows a sentence-only tip with no CTA -- the instruction is the sentence", () => {
    render(<Tips tips={[{ id: "switch", sentence: "Switch boards from your avatar menu." }]} />);
    expect(screen.getByText(/Switch boards from your avatar menu\./)).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Try it" })).toBeNull();
  });

  it("keeps its pick when the pool arrives after mount -- env loads late", () => {
    const pool = [tip("a"), tip("b")];
    const { rerender } = render(<Tips tips={[]} />);
    rerender(<Tips tips={pool} />);
    expect(screen.getByText(/Sentence a\./)).toBeTruthy();
    rerender(<Tips tips={pool} />);
    expect(screen.getByText(/Sentence a\./)).toBeTruthy();
  });
});

describe("tipsReady", () => {
  it("the tips wait for the Space's own env, like the cards do", () => {
    expect(tipsReady(true)).toBe(false);
    expect(tipsReady(false)).toBe(true);
  });
});
