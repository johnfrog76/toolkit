import { render, screen } from "@testing-library/react";
import { EMPTY_DESK_CSS, EmptyDesk, MUG_LOOKS, dealMugLooks } from "./EmptyDesk";

describe("the mugs", () => {
  it("come in at least six looks, each named once", () => {
    expect(MUG_LOOKS.length).toBeGreaterThanOrEqual(6);
    expect(new Set(MUG_LOOKS).size).toBe(MUG_LOOKS.length);
  });

  it("are each drawn differently", () => {
    const drawn = MUG_LOOKS.map((look) => {
      const { unmount } = render(<EmptyDesk look={look} />);
      const html = screen.getByTestId("empty-desk-mug").innerHTML;
      unmount();
      return html;
    });
    expect(new Set(drawn).size).toBe(MUG_LOOKS.length);
  });
});

describe("the deal", () => {
  const days = Array.from({ length: 366 }, (_, i) => i + 1);

  it("gives one look per empty window, in window order", () => {
    for (const n of [0, 1, 3, 5, 8]) expect(dealMugLooks(320, n)).toHaveLength(n);
    // The first three windows keep their mugs when more windows are empty.
    expect(dealMugLooks(320, 8).slice(0, 3)).toEqual(dealMugLooks(320, 3));
  });

  it("deals the same day the same way", () => {
    for (const day of days) expect(dealMugLooks(day, 8)).toEqual(dealMugLooks(day, 8));
  });

  it("never repeats a look until every look is out, on any day", () => {
    for (const day of days) {
      for (let n = 1; n <= MUG_LOOKS.length; n++) {
        expect(new Set(dealMugLooks(day, n)).size).toBe(n);
      }
    }
  });

  it("deals every look once across a full round, then goes round again in the same order", () => {
    const round = dealMugLooks(41, MUG_LOOKS.length);
    expect([...round].sort()).toEqual([...MUG_LOOKS].sort());
    expect(dealMugLooks(41, MUG_LOOKS.length * 2)).toEqual([...round, ...round]);
  });

  it("changes with the day", () => {
    const deals = new Set(days.map((day) => dealMugLooks(day, 3).join(",")));
    // Three windows can be dealt 8 x 7 x 6 ways; a year uses a good many of them.
    expect(deals.size).toBeGreaterThan(100);
  });

  it("deals nothing for no window or a nonsense count", () => {
    expect(dealMugLooks(10, 0)).toEqual([]);
    expect(dealMugLooks(10, -2)).toEqual([]);
  });
});

describe("the empty desk", () => {
  it("draws a chair, a mug and steam, and says which look it is", () => {
    render(<EmptyDesk look="enamel" />);
    const desk = screen.getByTestId("empty-desk");
    expect(desk.getAttribute("data-look")).toBe("enamel");
    expect(screen.queryByTestId("empty-desk-chair")).not.toBeNull();
    expect(screen.queryByTestId("empty-desk-mug")).not.toBeNull();
    expect(screen.getByTestId("empty-desk-steam").querySelectorAll(".ed-wisp")).toHaveLength(3);
  });

  it("is one picture to a screen reader, and no face", () => {
    render(<EmptyDesk look="classic" />);
    expect(screen.queryByRole("img", { name: "An empty desk with a steaming mug" })).not.toBeNull();
  });

  it("stills the steam under reduced motion, and the steam stays drawn", () => {
    expect(EMPTY_DESK_CSS).toMatch(
      /@media \(prefers-reduced-motion: reduce\) \{ \.ed-desk \.ed-wisp \{ animation: none !important; \} \}/,
    );
    render(<EmptyDesk look="tall" />);
    for (const wisp of screen.getByTestId("empty-desk-steam").querySelectorAll(".ed-wisp")) {
      // The resting opacity is the drawn one, so a stilled wisp is still visible.
      expect(Number(wisp.getAttribute("opacity"))).toBeGreaterThan(0);
    }
  });

  it("carries its own steam rule, so it moves wherever it is mounted", () => {
    const { container } = render(<EmptyDesk look="straw" />);
    expect(container.querySelector("style")?.textContent).toContain("@keyframes ed-steam");
  });
});
