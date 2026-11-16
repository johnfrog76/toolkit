import { useId } from "react";
import type { ReactNode } from "react";

// The refined cast: soft shapes, no outlines, a single right-side shade, light
// from the top left and one soft drop shadow. Each face is a bust drawn in a
// 120 by 124 box (the viewBox 0 -10 120 124), the same shapes and colours for
// every face, with the parts that are a face's own -- hair, the mark on the
// shirt, the eyes and the mouth -- in its entry below.
//
// Two pages draw them. The landing page puts three on testimonial cards
// (RefinedPortrait, the bust on its tinted picture); the Team Agile org chart
// puts a bust in each office (RefinedBust, the bust alone, on the office's
// wall). Neither page's data names a face: the landing page picks one per
// person, and the org chart's map from position to face is the module's own.
//
// The first three (minimalist, pm, dev-hero) are drawn as the landing page
// first drew them. The others are ported from the cast-skin mock's direction A
// as its generator writes them, colour for colour.

/** Every face the refined cast has. */
export const FACE_IDS = [
  "minimalist",
  "pm",
  "dev-hero",
  "owner",
  "designer",
  "ultrawide",
  "ops-dev",
  "new-hire",
  "vibemancer",
  "qa",
] as const;

export type FaceId = (typeof FACE_IDS)[number];

/** One face's colours and the parts that are theirs alone. */
interface Refined {
  /** The picture behind the bust, where a page draws one. */
  tint: string;
  shirt: string;
  shirtShade: string;
  skin: string;
  skinShade: string;
  /** The left ear, a step lighter than the shaded right. */
  earLeft: string;
  /** Eyes and mouth. */
  ink: string;
  /** Open eyes (the default), wide open, or closed and content. */
  eyes?: "open" | "wide" | "closed";
  mouth: "calm" | "grin" | "awe";
  /** Drawn before the body: hair that falls behind the shoulders. */
  back?: ReactNode;
  /** Long hair covers the ears, so they are not drawn: their edge would show past it. */
  earsCovered?: boolean;
  /** On the shirt. */
  detail?: ReactNode;
  hair: ReactNode;
}

const TORSO = "M 16 114 C 16 87 28 75.5 47 72 L 73 72 C 92 75.5 104 87 104 114 Z";
// Long hair covers the crown: its outer edge is an arc a little larger than the
// head's own ellipse (60, 38, 22 by 24), so no skin shows above or beside it.
const CROP =
  "M 36.8 37.5 A 23.2 25.2 0 0 1 83.2 37.5 C 78 27 70 22.5 60 22.5 C 50 22.5 42 27 36.8 37.5 Z";
// The mock's own short crop, for the faces ported from it.
const SHORT_CROP =
  "M 37.6 37 C 35 9 85 9 82.4 37 C 78 27 70 22.5 60 22.5 C 50 22.5 42 27 37.6 37 Z";
const BUZZ =
  "M 38.2 33 C 37 11 83 11 81.8 33 C 76 24.5 68 21.5 60 21.5 C 52 21.5 44 24.5 38.2 33 Z";
const MOUTH = {
  calm: "M 54.5 49.5 Q 60 52.8 65.5 49.5",
  grin: "M 52.5 48.5 Q 60 55.5 67.5 48.5",
};
// The round marks the mock rounds and joins every stroke of a shirt's mark with.
const ROUND = { strokeLinecap: "round" as const, strokeLinejoin: "round" as const, fill: "none" };

const REFINED: Record<FaceId, Refined> = {
  minimalist: {
    tint: "#e8ecef",
    shirt: "#454b54",
    shirtShade: "#373d48",
    skin: "#e8b88a",
    skinShade: "#c59d79",
    earLeft: "#d6ab82",
    ink: "#3c3537",
    mouth: "calm",
    hair: <path d={BUZZ} fill="#2c2c2c" opacity="0.78" />,
  },
  pm: {
    tint: "#f29a9a",
    shirt: "#2a3142",
    shirtShade: "#23293a",
    skin: "#f2c9a0",
    skinShade: "#cdab8c",
    earLeft: "#e0ba96",
    ink: "#3e393c",
    mouth: "grin",
    earsCovered: true,
    back: <path d="M 38.5 30 C 28 50 30 68 35 82 L 85 82 C 90 68 92 50 81.5 30 Z" fill="#5e3c20" />,
    detail: (
      <>
        <path
          d="M 60 75 V 114"
          fill="none"
          stroke="#e94f4f"
          strokeWidth="2.2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <rect x="58.2" y="85" width="3.6" height="6" rx="1.2" fill="#d7dbe4" />
      </>
    ),
    hair: (
      <>
        <path d={CROP} fill="#7a4a20" />
        <path d="M 38.5 29 C 31 46 32 64 36 78 L 45 77 C 41 62 40.5 46 42 31 Z" fill="#7a4a20" />
        <path d="M 81.5 29 C 89 46 88 64 84 78 L 75 77 C 79 62 79.5 46 78 31 Z" fill="#7a4a20" />
      </>
    ),
  },
  "dev-hero": {
    tint: "#8fb0f5",
    shirt: "#2d5bd0",
    shirtShade: "#2549a6",
    skin: "#e8b88a",
    skinShade: "#c59d79",
    earLeft: "#d6ab82",
    ink: "#3c3537",
    mouth: "grin",
    detail: <path d="M 62 85 L 54 98 L 60 98 L 57 109 L 67 94 L 61 94 Z" fill="#f7d96f" />,
    hair: (
      <>
        <path
          d="M 37.4 37 C 33 17 46 6 63 7 C 80 8 89 21 82.6 37 C 80 28 74 24 66 24.5 C 54 25.5 44 26 37.4 37 Z"
          fill="#3a2a22"
        />
        <path
          d="M 44 20 C 50 12 62 10 72 14"
          fill="none"
          stroke="#5a4c45"
          strokeWidth="2"
          strokeLinecap="round"
        />
      </>
    ),
  },
  // Grey hair with a side part, a navy blazer over a white shirt and a green tie.
  owner: {
    tint: "#f4d7a1",
    shirt: "#2b3350",
    shirtShade: "#232b44",
    skin: "#e2ad84",
    skinShade: "#c09474",
    earLeft: "#d1a07c",
    ink: "#3a3336",
    mouth: "calm",
    detail: (
      <>
        <path d="M 49 72 L 60 102 L 71 72 Z" fill="#f4f6fa" />
        <path d="M 57.6 77 L 62.4 77 L 64 94 L 60 100 L 56 94 Z" fill="#6fcf97" />
        <path d="M 49 72 L 60 102 L 71 72" {...ROUND} stroke="#5a6077" strokeWidth="2" />
      </>
    ),
    hair: (
      <>
        <path d={SHORT_CROP} fill="#c9ced8" />
        <path
          d="M 49 13.5 C 50 18 52 22 55 24"
          fill="none"
          stroke="#9095a1"
          strokeWidth="1.4"
          strokeLinecap="round"
        />
      </>
    ),
  },
  // Curls, a cream shirt with three swatches on the pocket, eyes closed.
  designer: {
    tint: "#a5e2bf",
    shirt: "#efe6d6",
    shirtShade: "#b8b3aa",
    skin: "#c68863",
    skinShade: "#a87558",
    earLeft: "#b77e5e",
    ink: "#342a2f",
    eyes: "closed",
    mouth: "calm",
    detail: (
      <>
        <rect x="65" y="94" width="17" height="1.8" rx="0.9" fill="#cdbfa6" />
        <circle cx="68" cy="91" r="2.3" fill="#e96fb1" />
        <circle cx="73.5" cy="91" r="2.3" fill="#4fc6e9" />
        <circle cx="79" cy="91" r="2.3" fill="#9b6fe9" />
      </>
    ),
    hair: (
      <g fill="#241a12">
        <circle cx="41" cy="24" r="8.5" />
        <circle cx="51" cy="15.5" r="9.5" />
        <circle cx="65" cy="14" r="10" />
        <circle cx="78" cy="22" r="9" />
        <circle cx="37.5" cy="33" r="5.5" />
        <circle cx="82.5" cy="33" r="5.5" />
        <rect x="42" y="16" width="36" height="12" rx="5" />
      </g>
    ),
  },
  // A close crop, a dark shirt with a bar chart on it, eyes wide.
  ultrawide: {
    tint: "#8fdcf2",
    shirt: "#223047",
    shirtShade: "#1c283e",
    skin: "#8d5a3b",
    skinShade: "#784e37",
    earLeft: "#835439",
    ink: "#282026",
    eyes: "wide",
    mouth: "awe",
    detail: (
      <g fill="#4fc6e9">
        <rect x="50" y="98" width="5" height="7" rx="1" />
        <rect x="57.5" y="94" width="5" height="11" rx="1" />
        <rect x="65" y="89" width="5" height="16" rx="1" />
      </g>
    ),
    hair: <path d={SHORT_CROP} fill="#14100c" />,
  },
  // A buzz cut, a dark shirt with a terminal prompt on it.
  "ops-dev": {
    tint: "#8fa3c8",
    shirt: "#26303f",
    shirtShade: "#202838",
    skin: "#c68863",
    skinShade: "#a87558",
    earLeft: "#b77e5e",
    ink: "#342a2f",
    mouth: "calm",
    detail: (
      <g {...ROUND} stroke="#79d68a" strokeWidth="2.4">
        <path d="M 50 89 L 56 94 L 50 99" />
        <path d="M 60 100 L 69 100" />
      </g>
    ),
    hair: <path d={BUZZ} fill="#1c1611" opacity="0.78" />,
  },
  // Spiked hair, a mustard shirt with a name sticker, eyes wide.
  "new-hire": {
    tint: "#f7d96f",
    shirt: "#d9a12f",
    shirtShade: "#a87e2b",
    skin: "#f2c9a0",
    skinShade: "#cdab8c",
    earLeft: "#e0ba96",
    ink: "#3e393c",
    eyes: "wide",
    mouth: "awe",
    detail: (
      <>
        <rect x="64" y="90" width="18" height="12" rx="2" fill="#fff" />
        <path d="M 64 94.5 V 92 a 2 2 0 0 1 2 -2 H 80 a 2 2 0 0 1 2 2 V 94.5 Z" fill="#e94f4f" />
        <path d="M 67 98.3 H 79" {...ROUND} stroke="#8a93a6" strokeWidth="1.3" />
      </>
    ),
    hair: (
      <path
        d="M 38 35 L 40 19 L 46 22 L 50 9 L 57 19 L 62 6 L 67 19 L 74 9 L 76 22 L 81 18 L 82 35 C 76 26 68 22.5 60 22.5 C 52 22.5 44 26 38 35 Z"
        fill="#6a4a1a"
        stroke="#6a4a1a"
        strokeWidth="2.4"
        strokeLinejoin="round"
      />
    ),
  },
  // Headphones over a short crop, a hoodie with its strings, eyes closed.
  vibemancer: {
    tint: "#b99cf2",
    shirt: "#31264d",
    shirtShade: "#282142",
    skin: "#f2c9a0",
    skinShade: "#cdab8c",
    earLeft: "#e0ba96",
    ink: "#3e393c",
    eyes: "closed",
    mouth: "calm",
    detail: (
      <>
        <g stroke="#b99cf2" strokeWidth="1.8" {...ROUND}>
          <path d="M 55 78 V 96" />
          <path d="M 65 78 V 93" />
        </g>
        <circle cx="55" cy="97" r="1.9" fill="#b99cf2" />
        <circle cx="65" cy="94" r="1.9" fill="#b99cf2" />
      </>
    ),
    hair: (
      <>
        <path d={SHORT_CROP} fill="#231a38" />
        <path
          d="M 35.5 40 C 33 6 87 6 84.5 40"
          fill="none"
          stroke="#8f7bd6"
          strokeWidth="4"
          strokeLinecap="round"
        />
        <rect x="30.5" y="33" width="9.5" height="17" rx="4.7" fill="#8f7bd6" />
        <rect x="80" y="33" width="9.5" height="17" rx="4.7" fill="#6f5cb8" />
      </>
    ),
  },
  // A bun, a white lab coat over an orange shirt, a pen in the pocket.
  qa: {
    tint: "#f7bd8a",
    shirt: "#f2f4f6",
    shirtShade: "#bbbdc3",
    skin: "#e8b88a",
    skinShade: "#c59d79",
    earLeft: "#d6ab82",
    ink: "#3c3537",
    mouth: "calm",
    detail: (
      <>
        <path d="M 50 72 L 60 99 L 70 72 Z" fill="#f2994a" />
        <path d="M 50 72 L 60 99 L 70 72" {...ROUND} stroke="#c3cbd6" strokeWidth="1.6" />
        <path d="M 60 99 V 114" {...ROUND} stroke="#c3cbd6" strokeWidth="1.4" />
        <rect x="69" y="97" width="12" height="1.8" rx="0.9" fill="#c3cbd6" />
        <rect x="72" y="90" width="2.6" height="8" rx="1" fill="#4f7de9" />
      </>
    ),
    hair: (
      <>
        <circle cx="60" cy="8.5" r="8" fill="#5a3a20" />
        <path d={SHORT_CROP} fill="#5a3a20" />
      </>
    ),
  },
};

/** The bust's own box: what a page sizes it by. */
export const BUST_VIEWBOX = "0 -10 120 124";
/** A bust's height for its width. */
export const bustHeight = (width: number): number => (width * 124) / 120;

/** The bust's one soft drop shadow, light from the top left. */
function BustShadow({ id }: { id: string }) {
  return (
    <filter id={`${id}-sh`} x="-20%" y="-20%" width="150%" height="150%">
      <feDropShadow dx="4" dy="3.5" stdDeviation="3" floodColor="#040814" floodOpacity="0.3" />
    </filter>
  );
}

/** The torso and the head, each a clip for its own lit side. */
function BustClips({ id }: { id: string }) {
  return (
    <>
      <clipPath id={`${id}-torso`}>
        <path d={TORSO} />
      </clipPath>
      <clipPath id={`${id}-head`}>
        <ellipse cx="60" cy="38" rx="22" ry="24" />
      </clipPath>
    </>
  );
}

/** The bust itself, in its 120 by 124 box, under the shadow `id` names. */
function BustFigure({ face, id }: { face: FaceId; id: string }) {
  const r = REFINED[face];
  const ink = {
    fill: "none",
    stroke: r.ink,
    strokeWidth: 1.9,
    strokeLinecap: "round" as const,
  };
  return (
    <g filter={`url(#${id}-sh)`}>
      {r.back}
      <path d={TORSO} fill={r.shirtShade} />
      <g clipPath={`url(#${id}-torso)`}>
        <path d={TORSO} fill={r.shirt} transform="translate(-9 0)" />
      </g>
      {r.detail}
      <rect x="52" y="52" width="16" height="25" rx="8" fill={r.skinShade} />
      {!r.earsCovered && (
        <>
          <circle cx="38.6" cy="41" r="4" fill={r.earLeft} />
          <circle cx="81.4" cy="41" r="4" fill={r.skinShade} />
        </>
      )}
      <ellipse cx="60" cy="38" rx="22" ry="24" fill={r.skinShade} />
      <g clipPath={`url(#${id}-head)`}>
        <ellipse cx="56" cy="34.5" rx="22" ry="24" fill={r.skin} />
      </g>
      {r.hair}
      <circle cx="45.5" cy="47" r="3.6" fill="#e94f4f" opacity="0.13" />
      <circle cx="74.5" cy="47" r="3.6" fill="#e94f4f" opacity="0.13" />
      {r.eyes === "closed" ? (
        <>
          <path d="M 48.5 40 Q 52 42.6 55.5 40" {...ink} />
          <path d="M 64.5 40 Q 68 42.6 71.5 40" {...ink} />
        </>
      ) : (
        <>
          <circle cx="52" cy="40" r={r.eyes === "wide" ? "2.7" : "2.2"} fill={r.ink} />
          <circle cx="68" cy="40" r={r.eyes === "wide" ? "2.7" : "2.2"} fill={r.ink} />
        </>
      )}
      {r.mouth === "awe" ? (
        <ellipse cx="60" cy="50.5" rx="2.8" ry="3.4" fill={r.ink} />
      ) : (
        <path d={MOUTH[r.mouth]} {...ink} />
      )}
    </g>
  );
}

/** A unique, CSS-safe prefix for one drawing's ids. */
function useDrawingId(prefix: string): string {
  return `${prefix}${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
}

// The picture: 240 by 250, the bust 208 wide, standing on the bottom edge.
const W = 240;
const H = 250;
const BUST_W = 208;
const BUST_H = bustHeight(BUST_W);

/**
 * One face's portrait: the bust on its tinted picture, as the landing page's
 * testimonial cards draw it. Decoration: the card around it carries the
 * person's title and their line in text.
 */
export function RefinedPortrait({ face, className }: { face: FaceId; className?: string }) {
  const r = REFINED[face];
  const id = useDrawingId("rf");
  return (
    <svg
      className={className}
      data-refined={face}
      viewBox={`0 0 ${W} ${H}`}
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <BustShadow id={id} />
        <linearGradient id={`${id}-wall`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.16" />
          <stop offset="0.55" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.16" />
        </linearGradient>
        <BustClips id={id} />
      </defs>
      <rect width={W} height={H} fill={r.tint} />
      <rect width={W} height={H} fill={`url(#${id}-wall)`} />
      <svg
        x={(W - BUST_W) / 2}
        y={H - BUST_H + 3}
        width={BUST_W}
        height={BUST_H}
        viewBox={BUST_VIEWBOX}
        overflow="hidden"
      >
        <BustFigure face={face} id={id} />
      </svg>
    </svg>
  );
}

/**
 * One face's bust alone, with no picture behind it: for a page that stands it
 * on a wall of its own. Placed with `x`/`y` inside another svg, or on its own.
 * Decoration, like the portrait.
 */
export function RefinedBust({
  face,
  width,
  x,
  y,
}: {
  face: FaceId;
  width: number;
  x?: number;
  y?: number;
}) {
  const id = useDrawingId("rb");
  return (
    <svg
      x={x}
      y={y}
      width={width}
      height={bustHeight(width)}
      viewBox={BUST_VIEWBOX}
      overflow="hidden"
      data-refined={face}
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <BustShadow id={id} />
        <BustClips id={id} />
      </defs>
      <BustFigure face={face} id={id} />
    </svg>
  );
}
