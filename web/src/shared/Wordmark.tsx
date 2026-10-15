import { WORDMARK_FACES, WORDMARK_LETTERS, WORDMARK_WIDTH } from "./wordmarkPaths";
import { DEFAULT_FACE_ID } from "./faces";

// The wordmark as one SVG: the letters as outlines, the blob behind the two
// o's and a face under them, so the o's are the eyes. No font is needed to
// draw it, and the colours, the size and the face are the caller's. The faces
// are the app's own (faces.ts), each outlined from the same font; the blob's
// place is the one the owner set on the landing page by hand, in em units
// (100 = the em, baseline at y=0).

/** The blob behind the o's, and the point the face is centred on, in em units. */
const BLOB = { cx: 103, cy: -31, r: 65 };
const FACE_AT = { x: 103, y: 13 };

/** The drawing's frame: a little air around the word and the blob. */
const VIEW = { x: -4, y: -100, w: WORDMARK_WIDTH + 8, h: 138 };

export const WORDMARK_NAME = "ToolKit";

export function Wordmark({
  size = 240,
  ink = "currentColor",
  blob = "rgba(34, 211, 238, 0.38)",
  face = DEFAULT_FACE_ID,
  theme = "dark",
  faceInk,
  className,
  title = WORDMARK_NAME,
}: {
  /** The drawn width: a number of pixels, or any CSS length. */
  size?: number | string;
  /** The letters and, unless `faceInk` says otherwise, the face. */
  ink?: string;
  /** The blob behind the o's. */
  blob?: string;
  /** Which face, by the id faces.ts gives it; an unknown id draws the default. */
  face?: string;
  /** Some faces differ by theme, as the app's do. */
  theme?: "light" | "dark";
  /** The face's colour when it is not the ink's. */
  faceInk?: string;
  className?: string;
  /** The accessible name; an empty string hides the mark from readers. */
  title?: string;
}) {
  const width = typeof size === "number" ? `${size}px` : size;
  const labelled = title !== "";
  const shape = (WORDMARK_FACES.find((f) => f.id === face) ??
    WORDMARK_FACES.find((f) => f.id === DEFAULT_FACE_ID))![theme];
  return (
    <svg
      className={className}
      viewBox={`${VIEW.x} ${VIEW.y} ${VIEW.w} ${VIEW.h}`}
      style={{ width, height: "auto", display: "inline-block" }}
      role={labelled ? "img" : undefined}
      aria-label={labelled ? title : undefined}
      aria-hidden={labelled ? undefined : true}
    >
      <circle cx={BLOB.cx} cy={BLOB.cy} r={BLOB.r} fill={blob} />
      {WORDMARK_LETTERS.map((l, i) => (
        <path key={i} d={l.d} fill={ink} />
      ))}
      <path
        d={shape.d}
        fill={faceInk ?? ink}
        transform={`translate(${FACE_AT.x} ${FACE_AT.y}) rotate(${shape.rotate})`}
      />
    </svg>
  );
}
