import { useId } from "react";
import type { ReactNode } from "react";
import type { LandingPerson } from "./people";

// The landing page's three people in the refined cast style: soft shapes, no
// outlines, a single right-side shade, light from the top left and one soft
// drop shadow. Each is a bust on a tinted picture, the picture a testimonial
// card's top. The shapes and colours are the refined cast's own, ported as
// they are; only the landing page draws them, so a shared cast can replace
// this file whole.

type CastId = LandingPerson["castId"];

/** One person's colours and the parts that are theirs alone. */
interface Refined {
  /** The picture behind the bust. */
  tint: string;
  /** The card's opening quote mark. */
  quote: string;
  shirt: string;
  shirtShade: string;
  skin: string;
  skinShade: string;
  /** The left ear, a step lighter than the shaded right. */
  earLeft: string;
  /** Eyes and mouth. */
  ink: string;
  mouth: "calm" | "grin";
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
const MOUTH = {
  calm: "M 54.5 49.5 Q 60 52.8 65.5 49.5",
  grin: "M 52.5 48.5 Q 60 55.5 67.5 48.5",
};

const REFINED: Record<CastId, Refined> = {
  minimalist: {
    tint: "#e8ecef",
    quote: "#6c727c",
    shirt: "#454b54",
    shirtShade: "#373d48",
    skin: "#e8b88a",
    skinShade: "#c59d79",
    earLeft: "#d6ab82",
    ink: "#3c3537",
    mouth: "calm",
    hair: (
      <path
        d="M 38.2 33 C 37 11 83 11 81.8 33 C 76 24.5 68 21.5 60 21.5 C 52 21.5 44 24.5 38.2 33 Z"
        fill="#2c2c2c"
        opacity="0.78"
      />
    ),
  },
  pm: {
    tint: "#f29a9a",
    quote: "#916067",
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
    quote: "#586d9c",
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
};

/** The colour of a person's opening quote mark, for the card to wear. */
export function quoteColour(castId: CastId): string {
  return REFINED[castId].quote;
}

// The picture: 240 by 250, the bust 208 wide, standing on the bottom edge.
const W = 240;
const H = 250;
const BUST_W = 208;
const BUST_H = (BUST_W * 124) / 120;

/**
 * One person's portrait: the bust on its tinted picture. Decoration: the card
 * around it carries the person's title and their line in text.
 */
export function RefinedPortrait({ castId }: { castId: CastId }) {
  const r = REFINED[castId];
  const id = `rf${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const ink = {
    fill: "none",
    stroke: r.ink,
    strokeWidth: 1.9,
    strokeLinecap: "round" as const,
  };
  return (
    <svg
      className="lp-card-portrait"
      data-refined={castId}
      viewBox={`0 0 ${W} ${H}`}
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <filter id={`${id}-sh`} x="-20%" y="-20%" width="150%" height="150%">
          <feDropShadow dx="4" dy="3.5" stdDeviation="3" floodColor="#040814" floodOpacity="0.3" />
        </filter>
        <linearGradient id={`${id}-wall`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.16" />
          <stop offset="0.55" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.16" />
        </linearGradient>
        <clipPath id={`${id}-torso`}>
          <path d={TORSO} />
        </clipPath>
        <clipPath id={`${id}-head`}>
          <ellipse cx="60" cy="38" rx="22" ry="24" />
        </clipPath>
      </defs>
      <rect width={W} height={H} fill={r.tint} />
      <rect width={W} height={H} fill={`url(#${id}-wall)`} />
      <svg
        x={(W - BUST_W) / 2}
        y={H - BUST_H + 3}
        width={BUST_W}
        height={BUST_H}
        viewBox="0 -10 120 124"
        overflow="hidden"
      >
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
          <circle cx="52" cy="40" r="2.2" fill={r.ink} />
          <circle cx="68" cy="40" r="2.2" fill={r.ink} />
          <path d={MOUTH[r.mouth]} {...ink} />
        </g>
      </svg>
    </svg>
  );
}
