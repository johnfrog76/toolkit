import { act, render, screen, waitFor } from "@testing-library/react";
import { StrictMode } from "react";
import { ConfettiLayer } from "./ConfettiLayer";
import { onConfetti, resetConfetti, throwConfetti, useConfetti } from "./useConfetti";

// The confetti's one mount and its one hook (D-AR14; docs/modules/solitaire-agile.md,
// "Milestones: the tab and the award"): the root layer draws nothing until a burst is
// thrown, fetches the confetti component (and the package behind it) only then, draws
// one burst per throw, and nothing at all under prefers-reduced-motion.

// Counts the times the confetti chunk is LOADED, not drawn: the factory runs when the
// layer's lazy import first asks for the module.
let mockLoads = 0;
const mockDone: Array<() => void> = [];
jest.mock("./Confetti", () => {
  mockLoads += 1;
  return {
    Confetti: ({ onDone }: { onDone?: () => void }) => {
      if (onDone) mockDone.push(onDone);
      return <i data-testid="confetti" />;
    },
  };
});

let reduced = false;
beforeEach(() => {
  resetConfetti();
  mockDone.length = 0;
  reduced = false;
  window.matchMedia = ((q: string) => ({
    matches: reduced && q.includes("prefers-reduced-motion"),
    media: q,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
  })) as unknown as typeof window.matchMedia;
});

const flush = () =>
  act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });

describe("the confetti channel (useConfetti.ts)", () => {
  it("one throw is one call to the mount, and the hook hands back the throw", () => {
    const calls: number[] = [];
    const off = onConfetti(() => calls.push(1));
    // The hook is a plain hook: it can be called in a component; here, through one.
    let thrown: (() => void) | undefined;
    function Caller() {
      thrown = useConfetti();
      return null;
    }
    render(<Caller />);
    expect(thrown).toBe(throwConfetti);
    thrown!();
    expect(calls).toHaveLength(1);
    throwConfetti();
    expect(calls).toHaveLength(2);
    off();
  });

  it("a throw before the mount is listening is held, and handed over once", () => {
    throwConfetti();
    throwConfetti();
    const calls: number[] = [];
    const off = onConfetti(() => calls.push(1));
    expect(calls).toHaveLength(1);
    off();
    const again: number[] = [];
    onConfetti(() => again.push(1));
    expect(again).toHaveLength(0);
  });

  it("under prefers-reduced-motion a throw does nothing, and holds nothing", () => {
    reduced = true;
    const calls: number[] = [];
    const off = onConfetti(() => calls.push(1));
    throwConfetti();
    expect(calls).toHaveLength(0);
    off();
    reduced = false;
    onConfetti(() => calls.push(1));
    expect(calls).toHaveLength(0);
  });
});

describe("the root mount (ConfettiLayer.tsx)", () => {
  it("draws nothing and loads nothing until a burst is thrown; then one burst, over the viewport", async () => {
    const before = mockLoads;
    render(<ConfettiLayer />);
    await flush();
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(mockLoads).toBe(before);
    act(() => throwConfetti());
    await waitFor(() => expect(screen.getAllByTestId("confetti")).toHaveLength(1));
    expect(mockLoads).toBe(before + 1);
    // The burst ends itself, and nothing is drawn again until the next throw.
    act(() => mockDone[mockDone.length - 1]());
    await waitFor(() => expect(screen.queryByTestId("confetti")).toBeNull());
    act(() => throwConfetti());
    await waitFor(() => expect(screen.getAllByTestId("confetti")).toHaveLength(1));
  });

  it("a throw that lands before the layer has mounted still rains, once", async () => {
    throwConfetti();
    render(
      <StrictMode>
        <ConfettiLayer />
      </StrictMode>,
    );
    await waitFor(() => expect(screen.getAllByTestId("confetti")).toHaveLength(1));
    act(() => mockDone[mockDone.length - 1]());
    await waitFor(() => expect(screen.queryByTestId("confetti")).toBeNull());
  });

  it("under prefers-reduced-motion nothing rains", async () => {
    reduced = true;
    render(<ConfettiLayer />);
    act(() => throwConfetti());
    await flush();
    expect(screen.queryByTestId("confetti")).toBeNull();
  });
});
