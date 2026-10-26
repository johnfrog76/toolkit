import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { RITUALS } from "../../shell/consts";
import type { Corner } from "./api.solitaireAgile";
import { resetCelebrateMemory } from "./celebrate";
import { PmCorner, SEE_MILESTONES } from "./PmCorner";
import { ROUTES } from "./paths";

// The PM Corner (AR-4): the agent's line verbatim, the chevron where it names a pick --
// and NO confetti, ever. A reached line says where the celebration is instead: a link
// to the Milestones tab, whose award dialog is the module's one celebration. The
// package is stood in for by a marker, so a burst would be seen if one were drawn.

const bursts: unknown[] = [];
jest.mock("react-confetti", () => ({
  __esModule: true,
  default: (props: unknown) => {
    bursts.push(props);
    return <i data-testid="confetti" />;
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

function draw(corner: Corner, onStart: (arg: string) => void = () => undefined) {
  return render(
    <MemoryRouter initialEntries={[ROUTES.home]}>
      <Routes>
        <Route path={ROUTES.home} element={<PmCorner corner={corner} onStart={onStart} />} />
        <Route path={ROUTES.milestones} element={<p>the milestones tab</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => {
  localStorage.clear();
  resetCelebrateMemory();
  bursts.length = 0;
});

describe("PmCorner", () => {
  it("shows the line verbatim, and the chevron opens the hand-off for the pick", () => {
    const onStart = jest.fn();
    draw(many, onStart);
    expect(screen.getByTestId("pm-corner").textContent).toContain(many.line);
    fireEvent.click(screen.getByRole("button", { name: "Start work on #5" }));
    expect(onStart).toHaveBeenCalledWith("5");
    expect(screen.getByRole("button", { name: "Start work on #5" }).textContent).toBe(
      RITUALS.text.cornerChevron,
    );
    expect(screen.queryByRole("link", { name: SEE_MILESTONES })).toBeNull();
  });

  it("a card's pick is its id; one left carries the chevron too", () => {
    const onStart = jest.fn();
    const card: Corner = {
      ...many,
      shape: ONE_LEFT,
      remaining: 1,
      ref: "23A3",
      number: null,
      id: "23A3",
      kind: "card",
    };
    draw(card, onStart);
    fireEvent.click(screen.getByRole("button", { name: "Start work on 23A3" }));
    expect(onStart).toHaveBeenCalledWith("23A3");
  });

  it("nothing in reach has no chevron and no link", () => {
    const nothing: Corner = {
      ...reached,
      shape: NOTHING,
      milestone: "",
      line: RITUALS.text.cornerNothingInReach,
    };
    draw(nothing);
    expect(screen.queryByRole("button", { name: /Start work/ })).toBeNull();
    expect(screen.queryByRole("link", { name: SEE_MILESTONES })).toBeNull();
  });

  it("reached: the line, then 'see Milestones' linking the tab -- no chevron", () => {
    draw(reached);
    expect(screen.getByTestId("pm-corner").textContent).toBe(
      `milestone B reached: ${SEE_MILESTONES}`,
    );
    expect(screen.queryByRole("button", { name: /Start work/ })).toBeNull();
    const link = screen.getByRole("link", { name: SEE_MILESTONES });
    expect(link.getAttribute("href")).toBe(ROUTES.milestones);
    fireEvent.click(link);
    expect(screen.getByText("the milestones tab")).toBeTruthy();
  });

  it("the corner never fires confetti: not on first sight, not on the transition, not with no mark", () => {
    const { rerender } = draw(many);
    rerender(
      <MemoryRouter initialEntries={[ROUTES.home]}>
        <PmCorner corner={reached} onStart={() => undefined} />
      </MemoryRouter>,
    );
    expect(screen.getByTestId("pm-corner").textContent).toContain("milestone B reached");
    expect(screen.queryByTestId("confetti")).toBeNull();
    expect(bursts).toHaveLength(0);
    expect(localStorage.length).toBe(0);
  });
});
