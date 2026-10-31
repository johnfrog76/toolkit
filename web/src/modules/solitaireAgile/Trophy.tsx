import { useId } from "react";

// The award's picture (docs/modules/solitaire-agile.md, "Milestones: the tab and the
// award"): a gold trophy -- a cup with two handles, a stem and a plinth. It is the gold
// tier of the studio's bowling-deck trophy, drawn by the same owner and ported as it is:
// the same paths, the same coordinates, the same three colours, as a standalone <svg>
// rather than a group placed on a slide. The studio's silver and ball tiers, its "2nd"
// label and its font are not part of it.
//
// Contrast against the dialog's surface (white in a light theme, #292929 in a dark one):
// the cup's deep-gold outline is 3.7:1 on light and 4.0:1 on dark, so the cup's shape
// holds in both. The gold fill is 7.5:1 on dark; the handles, bare gold strokes, are
// 1.9:1 on light, and the plinth is 2.1:1 on dark -- both read as parts of a cup the
// outline already draws, and the picture's meaning is its accessible name.

/** The trophy's gold: the cup's fill and its two handles. */
export const TROPHY_GOLD = "#e2b44a";
/** The deep gold: the cup's outline and the stem. */
export const TROPHY_GOLD_DEEP = "#a87f2c";
/** The plinth the gold cup stands on. */
export const TROPHY_PLINTH = "#6e5638";

/** The words a screen reader says for the picture. */
export const TROPHY_NAME = "A gold trophy";

/** The drawn size, in pixels: the award's picture box. */
const TROPHY_SIZE = 200;

export function Trophy({ size = TROPHY_SIZE }: { size?: number }) {
  const titleId = useId();
  return (
    <svg
      role="img"
      aria-labelledby={titleId}
      viewBox="-24 -38 48 52"
      width={size}
      height={size}
      style={{ display: "inline-block" }}
    >
      <title id={titleId}>{TROPHY_NAME}</title>
      <path
        d="M -13 -34 L 13 -34 L 10 -12 C 8 -4 -8 -4 -10 -12 Z"
        fill={TROPHY_GOLD}
        stroke={TROPHY_GOLD_DEEP}
        strokeWidth="1.6"
      />
      <path
        d="M -13 -30 C -22 -30 -22 -16 -11 -14"
        fill="none"
        stroke={TROPHY_GOLD}
        strokeWidth="3"
      />
      <path d="M 13 -30 C 22 -30 22 -16 11 -14" fill="none" stroke={TROPHY_GOLD} strokeWidth="3" />
      <rect x="-4" y="-4" width="8" height="8" fill={TROPHY_GOLD_DEEP} />
      <rect x="-12" y="4" width="24" height="7" rx="2" fill={TROPHY_PLINTH} />
    </svg>
  );
}
