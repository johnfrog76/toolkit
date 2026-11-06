import { render, screen } from "@testing-library/react";
import { CONTENT_PANEL_INSET, SlideRenderer } from "./SlideRenderer";
import type { Slide } from "../decks/types";

const slide: Slide = {
  title: "A slide",
  content: <div data-testid="art">art</div>,
  copy: <p data-testid="copy">copy</p>,
} as Slide;

function panels() {
  render(<SlideRenderer slide={slide} slideIndex={0} isFullscreen={false} />);
  const content = screen.getByTestId("art").parentElement as HTMLElement;
  const copy = screen.getByTestId("copy").parentElement as HTMLElement;
  return { content, copy };
}

// jsdom does no layout, so the overflow itself was measured in a browser: at
// 1440 wide the copy panel was 40% of the stage beside a content panel of 60%
// PLUS its padding and border, and its text ended past the window's right
// edge. What can be pinned here is the rule that prevents it.
describe("the side-by-side split", () => {
  it("keeps the content panel's authored style: 60%, its inset padding", () => {
    const { content } = panels();
    expect(content.style.flex).toBe("0 0 60%");
    expect(content.style.padding).toBe(`${CONTENT_PANEL_INSET}px`);
  });

  it("gives the copy panel what is left, not a fixed 40% that overflows the stage", () => {
    const { copy } = panels();
    expect(copy.style.flexGrow).toBe("1");
    expect(copy.style.flexShrink).toBe("1");
    expect(copy.style.flexBasis).not.toMatch(/%$/);
    expect(copy.style.minWidth).toBe("0px");
  });
});
