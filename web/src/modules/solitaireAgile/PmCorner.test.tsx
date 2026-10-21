import { act, fireEvent, render, screen } from "@testing-library/react";
import { RITUALS } from "../../shell/consts";
import type { Corner } from "./api.solitaireAgile";
import { resetCelebrateMemory } from "./celebrate";
import { CONFETTI_PIECES } from "./Confetti";
import { CORNER_SEEN_KEY } from "./corner";
import { PmCorner } from "./PmCorner";

// The PM Corner (AR-4): the agent's line verbatim, the chevron where it names a pick,
// and the confetti once per milestone per viewer. react-confetti draws on a canvas
// jsdom does not have, so it is stood in for by a marker that records its props and
// can finish its burst.

const bursts: Record<string, unknown>[] = [];
jest.mock("react-confetti", () => ({
  __esModule: true,
  default: (props: Record<string, unknown> & { onConfettiComplete?: () => void }) => {
    bursts.push(props);
    return (
      <button type="button" data-testid="confetti" onClick={() => props.onConfettiComplete?.()}>
        burst
      </button>
    );
  },
}));

const [ONE_LEFT, MANY_LEFT, REACHED, NOTHING] = RITUALS.cornerShapes;

const many: Corner = {
  shape: MANY_LEFT,
  milestone: "B",
  remaining: 3,
  ref: "#5",
  number: 5,
  id: null,
  kind: "issue",
  noun: "issues",
  line: "3 more issues to get milestone B - start #5 now",
  command: "StartWork 5",
  brief: "Corner: 3 more issues to get milestone B - start #5 now > (tkStartWork 5)",
};
const reached: Corner = {
  ...many,
  shape: REACHED,
  remaining: 0,
  ref: "",
  number: null,
  noun: "",
  line: "milestone B reached",
  command: "",
  brief: "Corner: milestone B reached",
};

let reduced = false;
beforeEach(() => {
  localStorage.clear();
  resetCelebrateMemory();
  bursts.length = 0;
  reduced = false;
  window.matchMedia = ((q: string) => ({
    matches: reduced && q.includes("prefers-reduced-motion"),
    media: q,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
  })) as unknown as typeof window.matchMedia;
});

describe("PmCorner", () => {
  it("shows the line verbatim, and the chevron opens the hand-off for the pick", () => {
    const onStart = jest.fn();
    render(<PmCorner corner={many} space="widgets" onStart={onStart} />);
    expect(screen.getByTestId("pm-corner").textContent).toContain(many.line);
    fireEvent.click(screen.getByRole("button", { name: "Start work on #5" }));
    expect(onStart).toHaveBeenCalledWith("5");
    expect(screen.getByRole("button", { name: "Start work on #5" }).textContent).toBe(RITUALS.text.cornerChevron);
    expect(screen.queryByTestId("confetti")).toBeNull();
  });

  it("a card's pick is its id; one left carries the chevron too", () => {
    const onStart = jest.fn();
    const card: Corner = { ...many, shape: ONE_LEFT, remaining: 1, ref: "23A3", number: null, id: "23A3", kind: "card" };
    render(<PmCorner corner={card} space="widgets" onStart={onStart} />);
    fireEvent.click(screen.getByRole("button", { name: "Start work on 23A3" }));
    expect(onStart).toHaveBeenCalledWith("23A3");
  });

  it("nothing in reach and reached have no chevron", () => {
    const nothing: Corner = { ...reached, shape: NOTHING, milestone: "", line: RITUALS.text.cornerNothingInReach };
    const { rerender } = render(<PmCorner corner={nothing} space="widgets" onStart={() => undefined} />);
    expect(screen.queryByRole("button", { name: /Start work/ })).toBeNull();
    rerender(<PmCorner corner={reached} space="widgets" onStart={() => undefined} />);
    expect(screen.queryByRole("button", { name: /Start work/ })).toBeNull();
  });

  it("reached, first seen with no mark: one burst over the viewport, recycle off, and the mark is set", () => {
    render(<PmCorner corner={reached} space="widgets" onStart={() => undefined} />);
    expect(screen.getAllByTestId("confetti")).toHaveLength(1);
    expect(bursts[0]).toMatchObject({
      recycle: false,
      numberOfPieces: CONFETTI_PIECES,
      width: window.innerWidth,
      height: window.innerHeight,
    });
    expect(JSON.parse(localStorage.getItem(CORNER_SEEN_KEY) ?? "[]")).toEqual(["widgets:B"]);
    // The burst ends itself and leaves the line.
    fireEvent.click(screen.getByTestId("confetti"));
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(screen.getByTestId("pm-corner").textContent).toContain("milestone B reached");
  });

  it("a reload with the mark set: the line, and no burst", () => {
    localStorage.setItem(CORNER_SEEN_KEY, JSON.stringify(["widgets:B"]));
    render(<PmCorner corner={reached} space="widgets" onStart={() => undefined} />);
    expect(screen.getByTestId("pm-corner").textContent).toContain("milestone B reached");
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(bursts).toHaveLength(0);
  });

  it("the transition to reached while the page watches: one burst, even with the mark set", () => {
    localStorage.setItem(CORNER_SEEN_KEY, JSON.stringify(["widgets:B"]));
    const { rerender } = render(<PmCorner corner={many} space="widgets" onStart={() => undefined} />);
    expect(screen.queryByTestId("confetti")).toBeNull();
    act(() => {
      rerender(<PmCorner corner={reached} space="widgets" onStart={() => undefined} />);
    });
    expect(screen.getAllByTestId("confetti")).toHaveLength(1);
    // A re-draw of the same reached line does not throw it again.
    fireEvent.click(screen.getByTestId("confetti"));
    act(() => {
      rerender(<PmCorner corner={{ ...reached }} space="widgets" onStart={() => undefined} />);
    });
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(bursts).toHaveLength(1);
  });

  it("another Space's milestone of the same title is its own", () => {
    localStorage.setItem(CORNER_SEEN_KEY, JSON.stringify(["widgets:B"]));
    render(<PmCorner corner={reached} space="toolkit" onStart={() => undefined} />);
    expect(screen.getAllByTestId("confetti")).toHaveLength(1);
  });

  it("under prefers-reduced-motion: the line says reached, and nothing rains", () => {
    reduced = true;
    render(<PmCorner corner={reached} space="widgets" onStart={() => undefined} />);
    expect(screen.getByTestId("pm-corner").textContent).toContain("milestone B reached");
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(bursts).toHaveLength(0);
  });
});
