/**
 * Tic-tac-toe asks nothing: you play ✕, a polite opponent answers at once
 * with ○ somewhere empty, the footer says how it stands in words, nothing is
 * tallied, and the board is there tomorrow. D-L21.
 */
import { render, screen, fireEvent } from "@testing-library/react";
import { EMPTY_TTT, TTT_KEY, TicTacToe, isTttState, politeReply, winner } from "./TicTacToe";

beforeEach(() => {
  window.localStorage.clear();
});

function visibleText(container: HTMLElement): string {
  const clone = container.cloneNode(true) as HTMLElement;
  clone.querySelectorAll("style, svg").forEach((el) => el.remove());
  return clone.textContent ?? "";
}

const marks = () => screen.getAllByRole("button", { name: /, (yours|theirs)$/ });

describe("tic-tac-toe", () => {
  it("draws an empty grid, your move, and no digit", () => {
    const { container } = render(<TicTacToe />);
    expect(
      screen.getByRole("group", { name: "Tic-tac-toe board" }).querySelectorAll("button"),
    ).toHaveLength(9);
    expect(screen.getByText("your move · ✕")).toBeTruthy();
    expect(visibleText(container)).not.toMatch(/\d/);
    expect(container.querySelectorAll("input, textarea, a")).toHaveLength(0);
  });

  it("your ✕ is answered at once by a ○ somewhere empty", () => {
    render(<TicTacToe />);
    fireEvent.click(screen.getByRole("button", { name: "bB" }));
    expect(screen.getByRole("button", { name: "bB, yours" }).textContent).toBe("✕");
    const all = marks();
    expect(all).toHaveLength(2);
    expect(all.some((b) => b.textContent === "○")).toBe(true);
    const saved = JSON.parse(window.localStorage.getItem(TTT_KEY) ?? "null");
    expect(isTttState(saved)).toBe(true);
    expect(saved.board.filter(Boolean)).toHaveLength(2);
  });

  it("a win is said in words, the board stops, New game clears it", () => {
    // ✕ at aA and aB, ○ elsewhere: aC wins.
    const board = [..."xx", null, "o", "o", null, null, null, null].map((m) =>
      m === "x" || m === "o" ? m : null,
    );
    window.localStorage.setItem(TTT_KEY, JSON.stringify({ board }));
    render(<TicTacToe />);
    fireEvent.click(screen.getByRole("button", { name: "aC" }));
    expect(screen.getByText("✕ wins")).toBeTruthy();
    expect(marks().filter((b) => b.textContent === "○")).toHaveLength(2);
    fireEvent.click(screen.getByRole("button", { name: "New game" }));
    expect(screen.getByText("your move · ✕")).toBeTruthy();
    expect(JSON.parse(window.localStorage.getItem(TTT_KEY) ?? "null")).toEqual(EMPTY_TTT);
  });

  it("the rules: lines win, a full board with no line is a draw, the polite reply is an empty cell", () => {
    expect(winner(["o", "o", "o", null, "x", "x", null, null, "x"])).toBe("o");
    expect(winner(["x", null, null, null, "x", null, null, null, "x"])).toBe("x");
    const drawn: ("x" | "o")[] = ["x", "o", "x", "x", "o", "o", "o", "x", "x"];
    expect(winner(drawn)).toBeNull();
    expect(politeReply(drawn)).toBe(-1);
    expect(politeReply(["x", null, "o", null, null, null, null, null, null], () => 0)).toBe(1);
    expect(politeReply(["x", null, "o", null, null, null, null, null, null], () => 0.999)).toBe(8);
  });

  it("an unreadable saved board reads as empty", () => {
    window.localStorage.setItem(TTT_KEY, JSON.stringify({ board: [1, 2] }));
    render(<TicTacToe />);
    expect(screen.getByText("your move · ✕")).toBeTruthy();
  });
});
