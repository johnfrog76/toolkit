import { render, screen } from "@testing-library/react";
import { EMPTY_DESK_CSS, EMPTY_DESK_TINT, EmptyDesk, MUG_LOOKS } from "./EmptyDesk";
import { RefinedDesk } from "./RefinedDesk";

// The standup room's empty desk, in the refined cast. The deal and the names of
// the drinks are ./EmptyDesk.tsx's and are tested there; this is the drawing.

describe("the eight drinks, refined", () => {
  it("draws every look the deal can hand it, each differently", () => {
    const drawn = MUG_LOOKS.map((look) => {
      const { unmount } = render(<RefinedDesk look={look} />);
      expect(screen.getByTestId("empty-desk").getAttribute("data-look")).toBe(look);
      const html = screen
        .getByTestId("empty-desk-mug")
        .innerHTML.replace(/id="[^"]*"|url\(#[^)]*\)/g, "");
      unmount();
      return html;
    });
    expect(new Set(drawn).size).toBe(MUG_LOOKS.length);
  });

  it("has no outline on a drink's body: a fill, a shade and a highlight", () => {
    for (const look of MUG_LOOKS) {
      const { unmount } = render(<RefinedDesk look={look} />);
      const mug = screen.getByTestId("empty-desk-mug");
      // What is stroked is a line of its own (a handle, a straw, a tea string): never a filled shape's edge.
      for (const el of mug.querySelectorAll("[stroke]")) {
        expect(el.getAttribute("fill") ?? "none").toBe("none");
      }
      // One shade crescent, clipped to the body it shades.
      expect(mug.querySelectorAll("clipPath").length).toBeGreaterThan(0);
      unmount();
    }
  });

  it("keeps the straw drink's steam, and every other drink's", () => {
    for (const look of MUG_LOOKS) {
      const { unmount } = render(<RefinedDesk look={look} />);
      expect(screen.getByTestId("empty-desk-steam").querySelectorAll(".ed-wisp")).toHaveLength(3);
      unmount();
    }
  });
});

describe("the empty desk, refined", () => {
  it("draws a flat-backed chair, a drink and steam, and says which look it is", () => {
    render(<RefinedDesk look="enamel" />);
    expect(screen.getByTestId("empty-desk").getAttribute("data-look")).toBe("enamel");
    const chair = screen.getByTestId("empty-desk-chair");
    // The flat back: one rounded panel and its three lines, two arms and a post.
    expect(chair.querySelector('rect[width="72"][height="68"]')).not.toBeNull();
    expect(chair.querySelectorAll("rect")).toHaveLength(5);
    expect(screen.queryByTestId("empty-desk-mug")).not.toBeNull();
  });

  it("is in full colour: its window's tint under it, and no filter that greys or dims it", () => {
    const { unmount, container } = render(<RefinedDesk look="heart" tint="#f2994a" />);
    const desk = screen.getByTestId("empty-desk");
    expect(desk.style.background).toBe("rgb(242, 153, 74)");
    expect(desk.style.filter).toBe("");
    for (const el of container.querySelectorAll<HTMLElement>("*")) {
      expect(el.style.filter).not.toMatch(/grayscale|brightness|saturate|contrast/);
    }
    unmount();
    render(<RefinedDesk look="heart" />);
    const slate = document.createElement("div");
    slate.style.background = EMPTY_DESK_TINT;
    expect(screen.getByTestId("empty-desk").style.background).toBe(slate.style.background);
  });

  it("two desks on one stage share no ids", () => {
    const { container } = render(
      <>
        <RefinedDesk look="tall" />
        <RefinedDesk look="tall" />
      </>,
    );
    const ids = [...container.querySelectorAll("[id]")].map((el) => el.id);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
    // And every clip, filter and gradient a desk points at is its own.
    const html = container.innerHTML;
    for (const ref of html.matchAll(/url\(#([^)]+)\)/g)) expect(ids).toContain(ref[1]);
  });

  it("is one picture to a screen reader, and no face", () => {
    const { container } = render(<RefinedDesk look="classic" />);
    expect(screen.queryByRole("img", { name: "An empty desk with a steaming mug" })).not.toBeNull();
    expect(container.querySelector("[data-refined]")).toBeNull();
  });

  it("moves its steam as the stage always has, and stills it under reduced motion", () => {
    const { container } = render(<RefinedDesk look="straw" />);
    // The one rule, the stage's own: the same keyframes and the same reduced-motion line.
    expect(container.querySelector("style")?.textContent).toBe(EMPTY_DESK_CSS);
    const clocks = (root: HTMLElement) =>
      [...root.querySelectorAll<SVGPathElement>(".ed-wisp")].map(
        (w) => `${w.style.animationDuration} ${w.style.animationDelay}`,
      );
    const refined = clocks(screen.getByTestId("empty-desk-steam"));
    for (const wisp of screen.getByTestId("empty-desk-steam").querySelectorAll(".ed-wisp")) {
      // The resting opacity is the drawn one, so a stilled wisp is still visible.
      expect(Number(wisp.getAttribute("opacity"))).toBeGreaterThan(0);
    }
    container.remove();
    const earlier = render(<EmptyDesk look="straw" />);
    expect(refined).toEqual(clocks(earlier.getByTestId("empty-desk-steam")));
  });
});
