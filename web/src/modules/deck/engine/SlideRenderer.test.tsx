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

// The content panel remounts on every slide unless the slides say they are one
// scene (decks/types.ts `contentKey`). Node identity is the proof either way: a
// remount is a new DOM node, a kept panel is the same one.
describe("the content panel's key", () => {
  const scene = (id: string, contentKey?: string): Slide =>
    ({
      id,
      contentKey,
      content: <div data-testid="art">{id}</div>,
      copy: <p data-testid="copy">{id}</p>,
    }) as Slide;
  function advance(from: Slide, to: Slide) {
    const view = render(<SlideRenderer slide={from} slideIndex={0} isFullscreen={false} />);
    const art = screen.getByTestId("art");
    const panel = art.parentElement;
    const copy = screen.getByTestId("copy").parentElement;
    view.rerender(<SlideRenderer slide={to} slideIndex={1} isFullscreen={false} />);
    const result = {
      sameArt: screen.getByTestId("art") === art,
      samePanel: screen.getByTestId("art").parentElement === panel,
      sameCopyPanel: screen.getByTestId("copy").parentElement === copy,
      text: screen.getByTestId("art").textContent,
    };
    view.unmount();
    return result;
  }

  it("without a content key, the content remounts on every slide, as it always has", () => {
    const moved = advance(scene("a"), scene("b"));
    expect(moved.samePanel).toBe(false);
    expect(moved.sameArt).toBe(false);
    expect(moved.text).toBe("b");
  });

  it("with the same content key, the content stays mounted and is reconciled", () => {
    const moved = advance(scene("a", "room"), scene("b", "room"));
    expect(moved.samePanel).toBe(true);
    expect(moved.sameArt).toBe(true);
    expect(moved.text).toBe("b");
  });

  it("with a different content key, the content remounts", () => {
    const moved = advance(scene("a", "room"), scene("b", "hall"));
    expect(moved.samePanel).toBe(false);
    expect(moved.sameArt).toBe(false);
  });

  it("a keyed slide beside an unkeyed one remounts, both ways", () => {
    expect(advance(scene("a", "room"), scene("b")).samePanel).toBe(false);
    expect(advance(scene("a"), scene("b", "room")).samePanel).toBe(false);
  });

  it("a content key that looks like an index is still its own key", () => {
    // Slide 0 unkeyed has the index's key; slide 1 keyed "content-0" must not be taken for it.
    expect(advance(scene("a"), scene("b", "content-0")).samePanel).toBe(false);
  });

  it("the copy panel is not the content's: it persists either way", () => {
    expect(advance(scene("a"), scene("b")).sameCopyPanel).toBe(true);
    expect(advance(scene("a", "room"), scene("b", "room")).sameCopyPanel).toBe(true);
  });
});
