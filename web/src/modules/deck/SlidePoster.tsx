import { useLayoutEffect, useRef, useState } from "react";
import { SlideRenderer, DECK_BG } from "./engine/SlideRenderer";
import type { Slide } from "./decks/types";

// Ported from the Wasteland (src/SlidePoster.tsx)
// unchanged; here it is the first-run banner's poster (HomeBanner.tsx).
//
// SlidePoster — renders a REAL deck slide, shrunk to fit its box (spec: "put a
// slide in each box that scales and transforms to fit the spaces of the boxes").
//
// A slide is authored to fill a presentation viewport (SlideRenderer flexes to
// fill; visuals size against the whole frame). So we render it at a fixed
// "virtual viewport" (the deck's native 16:9) and CSS-transform:scale the whole
// thing down to fit the actual card. The slide's own layout never changes —
// it's the same frame the player shows, just smaller. Non-interactive:
// pointer-events off + aria-hidden, so the poster is pure decoration and the
// card itself owns the click.

// The deck's native canvas. 16:9 matches the fullscreen presentation aspect the
// slides are composed for; SlideRenderer splits it 60/40 content/copy.
const STAGE_W = 1280;
const STAGE_H = 720;

export function SlidePoster({
  slide,
  bleedLeft = 0,
}: {
  slide: Slide;
  /**
   * Stage pixels to crop off the LEFT edge, so the art meets the card's
   * border instead of showing the stage's own gutter. The home hero passes
   * the renderer's CONTENT_PANEL_INSET; everything else leaves it at 0 and
   * shows the whole authored frame. The overflow lands on the right, inside
   * the copy panel's own padding, so nothing readable is lost.
   */
  bleedLeft?: number;
}) {
  const boxRef = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState({ scale: 0.2, left: 0, top: 0 });

  useLayoutEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const measure = () => {
      const { width, height } = box.getBoundingClientRect();
      if (!width || !height) return;
      // Cover the box: fill on the tighter axis so no letterbox gap shows
      // through the card. The overflow is clipped by the box. With a left
      // bleed the region being fitted is the stage MINUS that strip, and
      // the strip is then pushed off the left edge.
      const visibleW = STAGE_W - bleedLeft;
      const scale = Math.max(width / visibleW, height / STAGE_H);
      const left = (width - visibleW * scale) / 2 - bleedLeft * scale;
      const top = (height - STAGE_H * scale) / 2;
      setFit({ scale, left, top });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(box);
    return () => ro.disconnect();
  }, [bleedLeft]);

  return (
    <div
      ref={boxRef}
      aria-hidden="true"
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        backgroundColor: DECK_BG,
        pointerEvents: "none",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: `${fit.top}px`,
          left: `${fit.left}px`,
          width: `${STAGE_W}px`,
          height: `${STAGE_H}px`,
          transform: `scale(${fit.scale})`,
          transformOrigin: "top left",
          // SlideRenderer is a flex row that fills its parent; give it the
          // fixed stage to fill so its 60/40 split resolves to real px.
          display: "flex",
        }}
      >
        <SlideRenderer slide={slide} slideIndex={0} isFullscreen={false} />
      </div>
    </div>
  );
}
