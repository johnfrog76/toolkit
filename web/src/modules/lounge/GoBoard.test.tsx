/**
 * The Go grid is a placement sandbox that asks nothing: stones go down in
 * turn, a double-click lifts one, nothing is counted, and the board is
 * there tomorrow (per browser). D-L21.
 */
import { render, screen, fireEvent } from "@testing-library/react";
import { GO_KEY, GO_SIZE, GoBoard, isGoState, lineGlyph } from "./GoBoard";

beforeEach(() => {
  window.localStorage.clear();
});

function visibleText(container: HTMLElement): string {
  const clone = container.cloneNode(true) as HTMLElement;
  clone.querySelectorAll("style, svg").forEach((el) => el.remove());
  return clone.textContent ?? "";
}

describe("the coffee-house Go grid", () => {
  it("draws nine by nine intersections as lines, and no digit anywhere", () => {
    const { container } = render(<GoBoard />);
    const board = screen.getByRole("group", { name: "Go board" });
    expect(board.querySelectorAll("button")).toHaveLength(GO_SIZE * GO_SIZE);
    // An empty intersection carries only its ghost, hidden from readers; the
    // lines are drawn, not typed (lineGlyph stays for whoever wants a text board).
    expect(screen.getByRole("button", { name: "aA" }).querySelector("[aria-hidden]")).toBeTruthy();
    expect(visibleText(container)).not.toMatch(/\d/);
    expect(container.querySelectorAll("input, textarea, a")).toHaveLength(0);
  });

  it("black then white in turn; a double-click lifts a stone; the pass swaps the turn", () => {
    render(<GoBoard />);
    expect(screen.getByRole("button", { name: /black to play/ })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "dD" }));
    expect(screen.getByRole("button", { name: "dD, black" })).toBeTruthy();
    expect(screen.getByRole("button", { name: /white to play/ })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "fF" }));
    expect(screen.getByRole("button", { name: "fF, white" })).toBeTruthy();
    // A click on a stone does nothing; a double-click lifts it.
    fireEvent.click(screen.getByRole("button", { name: "dD, black" }));
    expect(screen.getByRole("button", { name: "dD, black" })).toBeTruthy();
    fireEvent.doubleClick(screen.getByRole("button", { name: "dD, black" }));
    expect(screen.getByRole("button", { name: "dD" }).querySelector("[aria-hidden]")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: /black to play; pass/ }));
    expect(screen.getByRole("button", { name: /white to play/ })).toBeTruthy();
  });

  it("the board is there tomorrow, and Clear board empties it", () => {
    const first = render(<GoBoard />);
    fireEvent.click(screen.getByRole("button", { name: "bB" }));
    const stored = JSON.parse(window.localStorage.getItem(GO_KEY) ?? "null");
    expect(isGoState(stored)).toBe(true);
    expect(stored.board.filter(Boolean)).toHaveLength(1);
    first.unmount();
    render(<GoBoard />);
    expect(screen.getByRole("button", { name: "bB, black" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Clear board" }));
    expect(screen.queryByRole("button", { name: "bB, black" })).toBeNull();
    expect(
      JSON.parse(window.localStorage.getItem(GO_KEY) ?? "null").board.filter(Boolean),
    ).toHaveLength(0);
  });

  it("an unreadable saved board reads as empty, never as a crash", () => {
    window.localStorage.setItem(GO_KEY, JSON.stringify({ board: ["x"], next: "z" }));
    render(<GoBoard />);
    expect(screen.getByRole("group", { name: "Go board" }).querySelectorAll("button")).toHaveLength(
      GO_SIZE * GO_SIZE,
    );
    expect(lineGlyph(0, 4)).toBe("┬");
    expect(lineGlyph(4, 0)).toBe("├");
  });
});
