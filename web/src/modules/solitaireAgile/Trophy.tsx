// The award's picture (docs/modules/solitaire-agile.md, "Milestones: the tab and the
// award"): a gold trophy -- a cup with two handles, a stem and a plinth -- drawn as an
// inline SVG, no raster and no package. It is the gold podium trophy the studio drew
// for its bowling decks, ported as a standalone picture: the cup, handles, stem and
// plinth in the studio's own geometry and golds, without the deck's coordinates, its
// silver and ball tiers or its "2nd" label.
//
// The golds are named once, here, and do not follow the theme: a gold trophy is gold
// in every theme. They hold up on both surfaces -- the deep gold outlines the cup and
// the plinth, so the shape still reads on a dark dialog where the plinth's brown alone
// would sink into it.

/** The cup's and handles' gold. */
export const TROPHY_GOLD = "#e2b44a";
/** The deep gold: the cup's outline, the stem, and the plinth's outline. */
export const TROPHY_GOLD_DEEP = "#a87f2c";
/** The plinth's wood. */
export const TROPHY_PLINTH = "#6e5638";

/** What a screen reader hears for the picture. */
export const TROPHY_NAME = "A gold trophy";

/** The trophy in a `size` px square -- 200, the award's picture box. */
export function Trophy({ size = 200 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="-26 -38 52 52"
      role="img"
      aria-label={TROPHY_NAME}
      data-testid="trophy"
      // A block, so the box is exactly size x size -- an inline SVG adds a baseline gap.
      style={{ display: "block" }}
    >
      <title>{TROPHY_NAME}</title>
      <path
        d="M -13 -34 L 13 -34 L 10 -12 C 8 -4 -8 -4 -10 -12 Z"
        fill={TROPHY_GOLD}
        stroke={TROPHY_GOLD_DEEP}
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path
        d="M -13 -30 C -22 -30 -22 -16 -11 -14"
        fill="none"
        stroke={TROPHY_GOLD}
        strokeWidth="3"
      />
      <path d="M 13 -30 C 22 -30 22 -16 11 -14" fill="none" stroke={TROPHY_GOLD} strokeWidth="3" />
      <rect x="-4" y="-4" width="8" height="8" fill={TROPHY_GOLD_DEEP} />
      <rect
        x="-12"
        y="4"
        width="24"
        height="7"
        rx="2"
        fill={TROPHY_PLINTH}
        stroke={TROPHY_GOLD_DEEP}
        strokeWidth="1"
      />
    </svg>
  );
}
