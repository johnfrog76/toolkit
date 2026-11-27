import type { CSSProperties, ReactNode } from "react";
import type { Deck, Slide } from "./types";
import { DeckState } from "./types";
import { GiveawayButton } from "../engine/GiveawayButton";
import { createMakeSlide } from "../engine/makeSlide";
import { useCompactLayout } from "../engine/useCompactLayout";
import { Say, Beat, Context } from "../engine/PresenterNoteKit";

// ── The Prompt Poet Works the Board ─────────────────────────────────────────
// The basement coffee house is back, and the slips on the poet's table are
// Azure DevOps work items. One card, one prompt: the poet writes the poem on
// the card, the card carries what the pull request needs, and the poem only
// counts when it rhymes with the card.
//
// Act I (1-3) is the room, the slip and the card, slow and calm. Act II (4-6)
// is the band, the cutting and the reading, snapped beats. Act III (7-8) is
// the held breath and the pull request, no easing. Act IV (9-12) is the
// room's answer, the reply, the page held to the light and the morning.
//
// WHAT IS COPIED, AND FROM WHERE. This deck is the sequel to The Prompt Poet
// (src/decks/the-prompt-poet.tsx), whose art has shipped. Its room, smoke,
// spotlight, chessboards, band, poet, typewriter, verse strips, snapping
// hands and windshield are COPIED from that file, the same paths, numbers and
// colours, so they draw the same; only placement, scale and the posture
// chosen per slide differ. Each copied block is marked where it starts. The
// keyframe and gradient names carry this deck's own prefix (pb-) so the two
// decks never share a name on one page. A slide number inside a copied
// comment is the first deck's.
//
// The work item arriving, RequestSlip, is drawn as the Envelope of the
// commercial (src/decks/the-toolkit.tsx), copied the same way, in its own
// colours, which are this deck's sixth token (design note, Holds 9).
//
// This deck is built here and shown from the Toolkit's repository, so it
// imports nothing from another deck: react, ./types and the engine only.

// The typed word is the physics. Everything the poet writes — the card, the
// verse strips in the air, the page held to the light — is set in a typewriter
// face, and a cut is an overstrike (xxxx through the word), never a
// strikethrough rule. (Copied from the-prompt-poet.tsx.)
const typed = "'Courier New', Courier, 'Liberation Mono', monospace";
// A typewriter face advances exactly 0.6em per character; the overstrike
// layer relies on it to land its x's on the word beneath.
const ADV = 0.6;
// The envelope's id is set in the commercial's own face. (Copied from the-toolkit.tsx.)
const MONO = "'Cascadia Code', 'Fira Code', 'Consolas', monospace";

// Six palette tokens, named for what they mean (design note, section 4), defined once.
const palette = {
  brickwarm: "#a9553a", // the room's warmth, the gathered crowd — Accumulation, Equilibrium
  smokegreen: "#8fd3a9", // the hanging smoke and the verse in flight — Flow
  spotgold: "#f2c45e", // the spotlight and the moment of delivery — Equilibrium, Resonance
  inkblack: "#121018", // the typed word, the card, the settled poem, the night — Crystallization
  signalflare: "#ff6a3d", // the poem becoming action; only when the deed lands — Transmutation
  // envelope — the commercial's work-item envelope, in that deck's own colours
  // exactly as src/decks/the-toolkit.tsx draws it (its paper, ink and shade,
  // and its type tabs), so the envelope stays pixel-identical — Accumulation
  envelope: {
    paper: "#f4f2ec",
    ink: "#1c1c1f",
    inkSoft: "#5b5a60",
    shade: "#000",
    tabRule: "rgba(28,28,31,0.14)",
    tab: {
      bug: "#b9e0c4",
      task: "#f4c2cc",
      story: "#f6e39b",
      meeting: "#c6dbf2",
      feature: "#d8c7ec",
      spike: "#dcefb7",
    },
  },
  // Derived shades of the first five, never another hue. (Copied from the-prompt-poet.tsx.)
  brickDeep: "#6a3323",
  brickLit: "#c8704f",
  mortar: "#3d2219",
  tin: "#3a2a20",
  tinLit: "#5a4330",
  wood: "#4a2c1a",
  woodLit: "#6b4226",
  woodDeep: "#2a1a12",
  paper: "#efe4cc",
  paperShade: "#d9cbae",
  ink: "#1c1a22",
  skin: "#e0b08a",
  smokeDeep: "#4c7a60",
  goldDeep: "#b98a2e",
  dawnSky: "#f6cfa0",
  dawnHigh: "#2a2444",
  muted: "#b7aa9b",
  text: "#f4efe6",
} as const;

// Copied from src/decks/the-prompt-poet.tsx: the four-act tempo, the copy-panel
// chrome (house values) and the slide factory.
const tempo = {
  act1: { ease: "cubic-bezier(0.25, 0.25, 0.75, 0.75)", slow: "1200ms", calm: "800ms" },
  act2: { ease: "cubic-bezier(0.34, 1.56, 0.64, 1)", snap: "300ms", beat: "600ms" },
  act3: { ease: "linear", hold: "1200ms" },
  act4: { ease: "cubic-bezier(0.25, 0.46, 0.45, 0.94)", quick: "400ms", warm: "800ms" },
} as const;

const fs = {
  eyebrow: "0.75rem",
  lead: "1.25rem",
  title: "2.5rem",
} as const;

// ── Copy-panel chrome (house values, see eu-nomes-figures.tsx) ─────────────
function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        fontSize: fs.eyebrow,
        fontWeight: 700,
        letterSpacing: "0.16em",
        textTransform: "uppercase",
        color: palette.spotgold,
        margin: "0 0 16px 0",
        display: "flex",
        alignItems: "center",
        gap: "10px",
      }}
    >
      <span
        style={{
          display: "inline-block",
          width: "22px",
          height: "2px",
          backgroundColor: palette.spotgold,
          borderRadius: "1px",
          flexShrink: 0,
        }}
      />
      {children}
    </p>
  );
}

function SlideTitle({ children }: { children: ReactNode }) {
  return (
    <h2
      style={{
        fontSize: `clamp(1.45rem, 6vw, ${fs.title})`,
        fontWeight: 800,
        lineHeight: "1.22em",
        margin: "0 0 20px 0",
        background: `linear-gradient(160deg, #ffffff 0%, ${palette.spotgold} 55%, ${palette.smokegreen} 100%)`,
        WebkitBackgroundClip: "text",
        WebkitTextFillColor: "transparent",
        backgroundClip: "text",
        filter: "drop-shadow(0 0 18px rgba(242,196,94,0.2))",
        whiteSpace: "pre-line",
      }}
    >
      {children}
    </h2>
  );
}

function Lead({ children }: { children: ReactNode }) {
  return (
    <p style={{ fontSize: fs.lead, lineHeight: 1.75, color: palette.muted, margin: 0 }}>
      {children}
    </p>
  );
}

function CopyPanel({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        height: "100%",
        padding: "40px 88px 40px 48px",
      }}
    >
      {children}
    </div>
  );
}

const makeSlide = createMakeSlide({ CopyPanel, Eyebrow, SlideTitle, Lead });

// ▼ Copied from src/decks/the-prompt-poet.tsx — its keyframes, with this deck's own added at the foot. Same paths, numbers and colours.
// ── Keyframes — one block, mounted inside every Stage ───────────────────────
// Every keyframe that touches `transform` runs on an element with no inline
// transform of its own (placement lives on a wrapper), per slide-deck-traps.
// Entrances animate FROM a hidden keyframe with `backwards` fill and the
// visible state as the base style; anything invisible at rest carries
// `opacity: 0` in its static style, for the frozen poster wall.
function PoetKeyframes() {
  return (
    <style>{`
      /* the room settling into place — furniture arrives, then stays */
      @keyframes pb-settle   { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
      @keyframes pb-fade     { from { opacity: 0; } to { opacity: 1; } }
      @keyframes pb-vanish   { from { opacity: 1; } to { opacity: 0; } }
      /* GreenSmoke: a slow drift under the tin, four seconds out and four back */
      @keyframes pb-smoke    { from { transform: translateX(-26px); } to { transform: translateX(26px); } }
      /* SpotlightCone: a gentle sway that never leaves the stage */
      @keyframes pb-sway     { from { transform: rotate(-2.4deg); } to { transform: rotate(2.4deg); } }
      /* the bulbs' filaments, breathing */
      @keyframes pb-glint    { 0%, 100% { opacity: 0.7; } 50% { opacity: 1; } }
      /* VerseLine: a loose word drifts in from the smoke and settles into meter, green to ink */
      @keyframes pb-word-in  { from { opacity: 0; transform: translate(var(--dx), var(--dy)); fill: ${palette.smokegreen}; } 70% { fill: ${palette.smokegreen}; } to { opacity: 1; transform: none; fill: ${palette.inkblack}; } }
      /* a word in flight, staying smoke-coloured (the draft before the cut) */
      @keyframes pb-word-air { from { opacity: 0; transform: translate(var(--dx), var(--dy)); } to { opacity: 1; transform: none; } }
      /* a cut word dissolving — overstruck, then gone */
      @keyframes pb-word-cut { from { opacity: 1; transform: translateY(0); } to { opacity: 0; transform: translateY(16px); } }
      /* a strip typing itself out, left to right, one character a step */
      @keyframes pb-typeline { from { transform: scaleX(0); } to { transform: scaleX(1); } }
      /* RequestSlip: tossed up from the tables, it tumbles and lands, ease-in */
      @keyframes pb-slip-fall { from { opacity: 0; transform: translate(var(--sx), -520px) rotate(var(--sr)); } 12% { opacity: 1; } to { opacity: 1; transform: none; } }
      /* the next slip, already on its way down */
      @keyframes pb-slip-descend { from { transform: translate(0, -560px) rotate(-14deg); } to { transform: translate(0, 0) rotate(6deg); } }
      /* SnapChorus: the snap's ring, out from the fingers and gone; the chorus repeats on a three-second wave */
      @keyframes pb-snap     { 0% { opacity: 0.95; transform: scale(0.3); } 10% { opacity: 0; transform: scale(1.7); } 100% { opacity: 0; transform: scale(1.7); } }
      @keyframes pb-spark    { 0% { opacity: 1; } 8% { opacity: 1; } 12% { opacity: 0; } 100% { opacity: 0; } }
      /* a hand going up to be ready */
      @keyframes pb-hand-up  { from { opacity: 0; transform: translateY(46px) rotate(12deg); } to { opacity: 1; transform: none; } }
      /* HeldBreath's one motion: the signal point where the deed will land, pulsing on a slow triangle, no easing */
      @keyframes pb-pulse    { 0%, 100% { opacity: 0.3; transform: scale(1); } 50% { opacity: 1; transform: scale(1.6); } }
      /* AgentAct: the confirmation landing under the cone */
      @keyframes pb-land     { from { opacity: 0; transform: translateY(-36px) scale(0.92); } to { opacity: 1; transform: none; } }
      @keyframes pb-flare    { 0%, 100% { opacity: 0.5; } 50% { opacity: 0.9; } }
      /* the band leaning in — the whole set tilts toward the mic, once */
      @keyframes pb-lean     { from { transform: rotate(0deg); } to { transform: rotate(-5deg); } }
      /* the robot's one note: the trumpet lifts and three rings go out */
      @keyframes pb-trumpet  { from { transform: rotate(0deg); } to { transform: rotate(40deg); } }
      @keyframes pb-ring     { 0% { opacity: 0; transform: scale(0.4); } 20% { opacity: 0.9; } 100% { opacity: 0; transform: scale(2.2); } }
      /* two heads turning to trade a look */
      @keyframes pb-look     { from { transform: rotate(0deg); } to { transform: rotate(var(--turn)); } }
      /* the typewriter: the carriage walks left a line's worth, then returns */
      @keyframes pb-carriage { 0% { transform: translateX(0); } 88% { transform: translateX(-22px); } 100% { transform: translateX(0); } }
      /* the poet walking on with the page */
      @keyframes pb-walk-on  { from { opacity: 0; transform: translateX(-260px); } to { opacity: 1; transform: none; } }
      @keyframes pb-step     { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-5px); } }
      /* a small bow at the hips when the room answers */
      @keyframes pb-bow      { 0%, 20% { transform: rotate(0deg); } 45% { transform: rotate(7deg); } 70%, 100% { transform: rotate(0deg); } }
      /* breathing — the only idle the figure has */
      @keyframes pb-breathe  { 0%, 100% { transform: scaleY(1); } 50% { transform: scaleY(1.012); } }
      /* dawn: the sky brightening, the smoke thinning into it */
      @keyframes pb-dawn     { from { opacity: 0.35; } to { opacity: 1; } }
      @keyframes pb-thin     { from { opacity: 0.55; } to { opacity: 0.06; } }
      /* the steam off the mug */
      @keyframes pb-steam    { 0% { opacity: 0; transform: translateY(0) scaleX(1); } 30% { opacity: 0.5; } 100% { opacity: 0; transform: translateY(-40px) scaleX(1.6); } }
      /* ── this deck's own, beside the first deck's ── */
      /* PromptCard: a line the card gathers, settling onto the page */
      @keyframes pb-line-settle { from { opacity: 0; transform: translateY(-12px); } to { opacity: 1; transform: none; } }
      /* LedgerPair: a line out of place on its page, settling into the order the other page keeps */
      @keyframes pb-row-settle { from { opacity: 0; transform: translateY(var(--dy)); } 30% { opacity: 1; } to { opacity: 1; transform: none; } }
    `}</style>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the Stage, the Scene and its gradients, the Pivot and the Camera. Same paths, numbers and colours.
// ── Stage and Scene ─────────────────────────────────────────────────────────
// Scene is one SVG, 1600×900, sliced to the panel: the desktop crops ~230px off
// each side, so load-bearing atoms live inside x≈320–1280 and only the room's
// walls, smoke and floor bleed past it. On-art text is centre-weighted.
const VW = 1600;
const VH = 900;

function Stage({ children, bg = palette.inkblack }: { children: ReactNode; bg?: string }) {
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        background: bg,
      }}
    >
      <PoetKeyframes />
      {children}
    </div>
  );
}

function Scene({ children, bg = palette.inkblack }: { children: ReactNode; bg?: string }) {
  return (
    <svg
      viewBox={`0 0 ${VW} ${VH}`}
      width="100%"
      height="100%"
      preserveAspectRatio="xMidYMid slice"
      style={{ position: "absolute", inset: 0, display: "block", background: bg }}
    >
      <defs>
        {/* the cone: gold at the lamp, thinning to the pool */}
        <linearGradient id="pb-cone" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={palette.spotgold} stopOpacity="0.62" />
          <stop offset="100%" stopColor={palette.spotgold} stopOpacity="0.16" />
        </linearGradient>
        <radialGradient id="pb-pool">
          <stop offset="0%" stopColor={palette.spotgold} stopOpacity="0.55" />
          <stop offset="60%" stopColor={palette.spotgold} stopOpacity="0.18" />
          <stop offset="100%" stopColor={palette.spotgold} stopOpacity="0" />
        </radialGradient>
        {/* a bulb's halo on the tin and the smoke */}
        <radialGradient id="pb-bulb">
          <stop offset="0%" stopColor={palette.spotgold} stopOpacity="0.5" />
          <stop offset="100%" stopColor={palette.spotgold} stopOpacity="0" />
        </radialGradient>
        {/* the room's edges fall away into the night */}
        <radialGradient id="pb-vignette" cx="50%" cy="48%" r="70%">
          <stop offset="55%" stopColor={palette.inkblack} stopOpacity="0" />
          <stop offset="100%" stopColor={palette.inkblack} stopOpacity="0.7" />
        </radialGradient>
        {/* the deed's glow */}
        <radialGradient id="pb-flare">
          <stop offset="0%" stopColor={palette.signalflare} stopOpacity="0.8" />
          <stop offset="55%" stopColor={palette.signalflare} stopOpacity="0.22" />
          <stop offset="100%" stopColor={palette.signalflare} stopOpacity="0" />
        </radialGradient>
        {/* the van's lamp */}
        <radialGradient id="pb-lamp">
          <stop offset="0%" stopColor={palette.spotgold} stopOpacity="0.45" />
          <stop offset="100%" stopColor={palette.spotgold} stopOpacity="0" />
        </radialGradient>
        {/* dawn through the windshield */}
        <linearGradient id="pb-dawn" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={palette.dawnHigh} />
          <stop offset="48%" stopColor="#8a5a62" />
          <stop offset="74%" stopColor={palette.dawnSky} />
          <stop offset="100%" stopColor={palette.spotgold} />
        </linearGradient>
        {/* the light through the page, held up to the lamp */}
        <radialGradient id="pb-through" cx="50%" cy="18%" r="80%">
          <stop offset="0%" stopColor="#fff6dc" stopOpacity="0.9" />
          <stop offset="60%" stopColor={palette.paper} stopOpacity="0" />
        </radialGradient>
        <linearGradient id="pb-plank" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#3a2518" />
          <stop offset="100%" stopColor={palette.woodDeep} />
        </linearGradient>
        <filter id="pb-smokeblur" x="-20%" y="-200%" width="140%" height="500%">
          <feGaussianBlur stdDeviation="9" />
        </filter>
        <filter id="pb-soft" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="12" />
        </filter>
        <filter id="pb-glow" x="-30%" y="-30%" width="160%" height="160%">
          <feGaussianBlur stdDeviation="3" result="b" />
          <feMerge>
            <feMergeNode in="b" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      {children}
    </svg>
  );
}

/** A pivot for a transform animation: the animated group carries no inline transform, so it rotates/scales about (x, y). */
function Pivot({
  x,
  y,
  style,
  children,
}: {
  x: number;
  y: number;
  style?: CSSProperties;
  children: ReactNode;
}) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <g style={style}>
        <g transform={`translate(${-x} ${-y})`}>{children}</g>
      </g>
    </g>
  );
}

/** The camera: the room is drawn once in world coordinates; each slide frames it. */
function Camera({
  x = VW / 2,
  y = VH / 2,
  zoom = 1,
  children,
}: {
  x?: number;
  y?: number;
  zoom?: number;
  children: ReactNode;
}) {
  return (
    <g transform={`translate(${VW / 2} ${VH / 2}) scale(${zoom}) translate(${-x} ${-y})`}>
      {children}
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — typed text with overstrikes. Same paths, numbers and colours.
// ── Typed text with overstrikes ─────────────────────────────────────────────
// A line is a list of segments; a segment marked `cut` gets a run of x's typed
// over it at the same advance, the way a typewriter kills a word. The x's are
// a second layer, so the word stays legible under them — that is the point.
interface Seg {
  t: string;
  cut?: boolean;
}

function TypedLine({
  x,
  y,
  size,
  segs,
  color,
  xColor,
  xDelay,
  anchorMiddle = false,
}: {
  x: number;
  y: number;
  size: number;
  segs: Seg[];
  color: string;
  xColor?: string;
  xDelay?: number;
  anchorMiddle?: boolean;
}) {
  const full = segs.map((s) => s.t).join("");
  const x0 = anchorMiddle ? x - (full.length * size * ADV) / 2 : x;
  let idx = 0;
  const strikes: ReactNode[] = [];
  for (const s of segs) {
    if (s.cut) {
      strikes.push(
        <text
          key={idx}
          x={x0 + idx * size * ADV}
          y={y}
          fontFamily={typed}
          fontSize={size}
          fill={xColor ?? color}
          xmlSpace="preserve"
          style={
            xDelay !== undefined
              ? { animation: `pb-fade 160ms linear ${xDelay}s backwards` }
              : undefined
          }
        >
          {"x".repeat(s.t.length)}
        </text>,
      );
    }
    idx += s.t.length;
  }
  return (
    <g>
      <text x={x0} y={y} fontFamily={typed} fontSize={size} fill={color} xmlSpace="preserve">
        {full}
      </text>
      {strikes}
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the Typewriter. Same paths, numbers and colours.
// ── The Typewriter — a portable, drawn once, on knees or a table ────────────
// Origin at the bottom centre of the body. The page rises out of the platen;
// `lines` is how many typed lines it carries, and `typing` walks the carriage.
// It faces the room, keys toward the viewer, while he types at it from behind
// the page (slides 2 and 6): the same cartoon beat as the sleeper at the wheel,
// kept on purpose. Not a facing to correct.
function Typewriter({
  x,
  y,
  scale = 1,
  lines = 4,
  typing = false,
  pageLines,
}: {
  x: number;
  y: number;
  scale?: number;
  lines?: number;
  typing?: boolean;
  pageLines?: ReactNode;
}) {
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`}>
      {/* the page, behind the carriage */}
      <g transform="translate(0 -56)">
        <rect x={-36} y={-96} width={72} height={100} fill={palette.paper} />
        <rect
          x={-36}
          y={-96}
          width={72}
          height={100}
          fill="none"
          stroke={palette.paperShade}
          strokeWidth={1}
        />
        {pageLines ??
          Array.from({ length: lines }, (_, i) => (
            <line
              key={i}
              x1={-26}
              y1={-82 + i * 12}
              x2={-26 + 40 - ((i * 7) % 18)}
              y2={-82 + i * 12}
              stroke={palette.ink}
              strokeWidth={2.2}
              strokeDasharray="3 2"
              opacity={0.75}
              style={{ animation: `pb-fade 200ms linear ${0.6 + i * 1.1}s backwards` }}
            />
          ))}
      </g>
      {/* the carriage: platen, knobs, the paper bail */}
      <g style={typing ? { animation: "pb-carriage 3.6s linear infinite" } : undefined}>
        <rect x={-68} y={-66} width={136} height={16} rx={6} fill="#2b2b33" />
        <circle cx={-72} cy={-58} r={7} fill="#1a1a20" stroke="#55555f" strokeWidth={1.5} />
        <circle cx={72} cy={-58} r={7} fill="#1a1a20" stroke="#55555f" strokeWidth={1.5} />
        <line x1={-40} y1={-70} x2={40} y2={-70} stroke="#8d8d99" strokeWidth={2} />
      </g>
      {/* the body: a muted teal portable with a dark rim */}
      <path d="M -62 -50 L 62 -50 L 66 -8 Q 66 0 58 0 L -58 0 Q -66 0 -66 -8 Z" fill="#5d7a73" />
      <path d="M -62 -50 L 62 -50 L 64 -36 L -64 -36 Z" fill="#4a6159" />
      <rect x={-20} y={-46} width={40} height={6} rx={2} fill="#1d1d24" />
      {/* three rows of round keys, and the space bar */}
      {[0, 1, 2].map((r) =>
        Array.from({ length: 9 - r }, (_, c) => (
          <circle
            key={`${r}-${c}`}
            cx={-44 + r * 6 + c * 11}
            cy={-28 + r * 8}
            r={3.4}
            fill="#16161c"
            stroke="#6f6f7c"
            strokeWidth={0.8}
          />
        )),
      )}
      <rect x={-30} y={-10} width={60} height={5} rx={2.5} fill="#16161c" />
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the Poet, his six poses and the page he holds. Same paths, numbers and colours.
// ── The Poet — the deck's one built figure, posed per slide ─────────────────
// One construction: a turtleneck, dark glasses, short hair and a goatee, with
// the page or the typewriter as his prop. Local frame: feet at (0, 0), up is
// negative y. A pose is a table of part positions, never a second drawing:
// legs standing, crossed, seated on a ledge or stretched out; a torso lean
// about the hips; a head tilt about the neck; two arms given as angles from
// straight down (positive = away from the body); and which prop the cuff
// holds. No hands — a sleeve ends in a round cuff, and the prop begins there.
type PoseName = "typing" | "carrying" | "standing" | "reading" | "listening" | "asleep" | "writing";

interface Pose {
  legs: "stand" | "cross" | "sit" | "slump";
  hipY: number;
  lean: number;
  headTilt: number;
  armL: [number, number];
  armR: [number, number];
  prop: "page-low" | "page-chest" | "slip-up" | "typewriter" | "none";
  /** The head sunk into the shoulders, in units: the slump. */
  headDrop?: number;
}

const POSES: Record<PoseName, Pose> = {
  // cross-legged on the carpet, the typewriter on his knees (slides 2 and 6)
  typing: {
    legs: "cross",
    hipY: -74,
    lean: 0,
    headTilt: 11,
    armL: [22, -16],
    armR: [22, -16],
    prop: "typewriter",
  },
  // bringing the page to the stage (slide 4)
  carrying: {
    legs: "stand",
    hipY: -110,
    lean: -3,
    headTilt: 2,
    armL: [-8, 6],
    armR: [22, 58],
    prop: "page-low",
  },
  // in the cone at the mic, the page held low in one hand (slides 7, 9, 10)
  standing: {
    legs: "stand",
    hipY: -110,
    lean: 0,
    headTilt: 0,
    armL: [8, 10],
    armR: [16, 36],
    prop: "page-low",
  },
  // at his table, leaning over the pile, a slip raised to the glasses (slide 5)
  reading: {
    legs: "stand",
    hipY: -110,
    lean: -5,
    headTilt: 14,
    armL: [12, 24],
    armR: [42, -162],
    prop: "slip-up",
  },
  // the page lowered, the head up: the held breath (slide 8)
  listening: {
    legs: "stand",
    hipY: -110,
    lean: 0,
    headTilt: -8,
    armL: [6, 4],
    armR: [8, 6],
    prop: "page-low",
  },
  // asleep at the wheel at dawn, the page on his chest (slide 12). He is turned toward the room, not the
  // windshield: a cartoon beat, kept on purpose -- the slump and the closed eyes say asleep, the turn says
  // he fell asleep mid-sentence. Not a mistake to correct.
  asleep: {
    legs: "slump",
    hipY: 0,
    lean: -16,
    headTilt: -36,
    armL: [26, 40],
    armR: [-4, 14],
    prop: "page-chest",
    headDrop: 10,
  },
  // THIS DECK'S ONE ADDED ROW (slide 10), not in the-prompt-poet.tsx: at his table, bent to the card that lies
  // on it, the far cuff down to the pen, nothing in the other. The same parts at new angles, nothing redrawn.
  writing: {
    legs: "stand",
    hipY: -110,
    lean: -6,
    headTilt: 14,
    armL: [16, 26],
    armR: [8, 6],
    prop: "none",
  },
};

const UA = 46;
const FA = 44;
const ARM_W = 15;
const rad = (d: number) => (d * Math.PI) / 180;

function armPoints(sign: 1 | -1, shoulder: [number, number], a: number, b: number) {
  const elbow: [number, number] = [
    shoulder[0] + sign * Math.sin(rad(a)) * UA,
    shoulder[1] + Math.cos(rad(a)) * UA,
  ];
  const cuff: [number, number] = [
    elbow[0] + sign * Math.sin(rad(b)) * FA,
    elbow[1] + Math.cos(rad(b)) * FA,
  ];
  return { elbow, cuff };
}

function Sleeve({
  shoulder,
  elbow,
  cuff,
}: {
  shoulder: [number, number];
  elbow: [number, number];
  cuff: [number, number];
}) {
  return (
    <path
      d={`M ${shoulder[0]} ${shoulder[1]} L ${elbow[0]} ${elbow[1]} L ${cuff[0]} ${cuff[1]}`}
      fill="none"
      stroke={palette.inkblack}
      strokeWidth={ARM_W}
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  );
}

/** A typed page, 46×64, a few dashed lines; `rot` tilts it in the hand. */
function HeldPage({
  x,
  y,
  rot = -10,
  w = 46,
  h = 64,
}: {
  x: number;
  y: number;
  rot?: number;
  w?: number;
  h?: number;
}) {
  return (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <rect
        x={-w / 2}
        y={-h / 2}
        width={w}
        height={h}
        fill={palette.paper}
        stroke={palette.paperShade}
        strokeWidth={1}
      />
      {[0, 1, 2, 3, 4].map((i) => (
        <line
          key={i}
          x1={-w / 2 + 7}
          y1={-h / 2 + 11 + i * 10}
          x2={-w / 2 + 7 + (w - 18) * (i % 2 === 0 ? 0.9 : 0.6)}
          y2={-h / 2 + 11 + i * 10}
          stroke={palette.ink}
          strokeWidth={1.8}
          strokeDasharray="2.5 1.5"
          opacity={0.7}
        />
      ))}
    </g>
  );
}

function Poet({
  pose,
  x,
  y,
  scale = 1,
  flip = false,
  motion,
  breathe = false,
  bow = false,
  typing = false,
  pageLines,
  sleeping = false,
}: {
  pose: PoseName;
  x: number;
  y: number;
  scale?: number;
  flip?: boolean;
  /** CSS animation for the motion wrapper (never on the placement group). */
  motion?: CSSProperties;
  breathe?: boolean;
  bow?: boolean;
  typing?: boolean;
  pageLines?: ReactNode;
  /** Eyes closed behind the dark glasses, and no glint on them: nobody has a light on him. */
  sleeping?: boolean;
}) {
  const p = POSES[pose];
  const hip = p.hipY;
  const shoulderY = hip - 96;
  const shL: [number, number] = [-30, shoulderY];
  const shR: [number, number] = [30, shoulderY];
  const L = armPoints(-1, shL, p.armL[0], p.armL[1]);
  const R = armPoints(1, shR, p.armR[0], p.armR[1]);
  const neck: [number, number] = [0, hip - 112];

  const legs = (() => {
    switch (p.legs) {
      case "stand":
        return (
          <g>
            <line
              x1={-12}
              y1={hip}
              x2={-15}
              y2={-6}
              stroke={palette.inkblack}
              strokeWidth={22}
              strokeLinecap="round"
            />
            <line
              x1={12}
              y1={hip}
              x2={15}
              y2={-6}
              stroke={palette.inkblack}
              strokeWidth={22}
              strokeLinecap="round"
            />
            <ellipse cx={-20} cy={-3} rx={16} ry={5} fill="#08080c" />
            <ellipse cx={20} cy={-3} rx={16} ry={5} fill="#08080c" />
          </g>
        );
      case "cross":
        return (
          <g>
            {/* thighs out to the knees, shins crossing back in */}
            <line
              x1={-10}
              y1={hip + 6}
              x2={-56}
              y2={-36}
              stroke={palette.inkblack}
              strokeWidth={24}
              strokeLinecap="round"
            />
            <line
              x1={10}
              y1={hip + 6}
              x2={56}
              y2={-36}
              stroke={palette.inkblack}
              strokeWidth={24}
              strokeLinecap="round"
            />
            <line
              x1={-56}
              y1={-36}
              x2={28}
              y2={-10}
              stroke={palette.inkblack}
              strokeWidth={20}
              strokeLinecap="round"
            />
            <line
              x1={56}
              y1={-36}
              x2={-28}
              y2={-10}
              stroke={palette.inkblack}
              strokeWidth={20}
              strokeLinecap="round"
            />
            <ellipse cx={-36} cy={-8} rx={14} ry={5} fill="#08080c" />
            <ellipse cx={36} cy={-8} rx={14} ry={5} fill="#08080c" />
          </g>
        );
      case "slump":
        return (
          <g>
            <line
              x1={-6}
              y1={-2}
              x2={74}
              y2={6}
              stroke={palette.inkblack}
              strokeWidth={24}
              strokeLinecap="round"
            />
            <line
              x1={10}
              y1={2}
              x2={84}
              y2={16}
              stroke={palette.inkblack}
              strokeWidth={22}
              strokeLinecap="round"
            />
            <ellipse cx={92} cy={6} rx={6} ry={13} fill="#08080c" />
            <ellipse cx={100} cy={17} rx={6} ry={13} fill="#08080c" />
          </g>
        );
      case "sit":
        return (
          <g>
            <line
              x1={-12}
              y1={-4}
              x2={-26}
              y2={16}
              stroke={palette.inkblack}
              strokeWidth={24}
              strokeLinecap="round"
            />
            <line
              x1={12}
              y1={-4}
              x2={26}
              y2={16}
              stroke={palette.inkblack}
              strokeWidth={24}
              strokeLinecap="round"
            />
            <line
              x1={-26}
              y1={16}
              x2={-24}
              y2={58}
              stroke={palette.inkblack}
              strokeWidth={19}
              strokeLinecap="round"
            />
            <line
              x1={26}
              y1={16}
              x2={24}
              y2={58}
              stroke={palette.inkblack}
              strokeWidth={19}
              strokeLinecap="round"
            />
            <ellipse cx={-26} cy={64} rx={11} ry={6} fill="#08080c" />
            <ellipse cx={26} cy={64} rx={11} ry={6} fill="#08080c" />
          </g>
        );
    }
  })();

  const prop = (() => {
    switch (p.prop) {
      case "page-low":
        return <HeldPage x={R.cuff[0] + 6} y={R.cuff[1] + 24} rot={-12} />;
      case "page-chest":
        return <HeldPage x={2} y={hip - 40} rot={14} />;
      case "slip-up":
        return (
          <g transform={`translate(${R.cuff[0] - 4} ${R.cuff[1] - 10}) rotate(-8)`}>
            <rect
              x={-20}
              y={-13}
              width={40}
              height={26}
              fill={palette.paper}
              stroke={palette.paperShade}
              strokeWidth={1}
            />
            <path
              d="M -13 -4 q 6 -3 12 0 t 12 0"
              fill="none"
              stroke={palette.ink}
              strokeWidth={1.6}
              opacity={0.75}
            />
            <path
              d="M -13 5 q 6 -3 12 0 t 8 0"
              fill="none"
              stroke={palette.ink}
              strokeWidth={1.6}
              opacity={0.75}
            />
          </g>
        );
      default:
        return null;
    }
  })();

  const place = `translate(${x} ${y}) scale(${flip ? -scale : scale} ${scale})`;
  const breath: CSSProperties | undefined = breathe
    ? { transformOrigin: "0px 0px", animation: "pb-breathe 4.6s ease-in-out infinite" }
    : undefined;

  return (
    <g transform={place}>
      <g style={motion}>
        <g style={breath}>
          {legs}
          {/* the upper body leans at the hips; a bow is the same pivot, in motion */}
          <Pivot
            x={0}
            y={hip}
            style={bow ? { animation: `pb-bow 5s ${tempo.act4.ease} 0.8s infinite` } : undefined}
          >
            <g transform={`rotate(${p.lean} 0 ${hip})`}>
              {/* the arm behind the body */}
              <Sleeve shoulder={shL} elbow={L.elbow} cuff={L.cuff} />
              {/* the turtleneck: a tapered torso and a rolled collar */}
              <path
                d={`M -34 ${shoulderY - 2} Q 0 ${shoulderY - 14} 34 ${shoulderY - 2} L 26 ${hip + 2} L -26 ${hip + 2} Z`}
                fill={palette.inkblack}
              />
              <path
                d={`M 10 ${shoulderY - 4} L 26 ${hip}`}
                stroke="#2a2733"
                strokeWidth={5}
                opacity={0.6}
              />
              <rect x={-17} y={neck[1] - 6} width={34} height={20} rx={8} fill="#1f1c27" />
              {/* the head, on the neck */}
              <g
                transform={`translate(${neck[0]} ${neck[1] + (p.headDrop ?? 0)}) rotate(${p.headTilt})`}
              >
                {
                  <>
                    <ellipse cx={0} cy={-16} rx={24} ry={27} fill={palette.skin} />
                    {/* hair: a short dark cap with a fringe */}
                    <path
                      d="M -25 -22 Q -26 -56 0 -58 Q 26 -56 25 -22 L 20 -26 Q 14 -36 8 -30 Q 0 -38 -8 -30 Q -16 -36 -20 -26 Z"
                      fill="#1a1510"
                    />
                    <path d="M -25 -22 L -24 -6 L -20 -6 L -20 -22 Z" fill="#1a1510" />
                    <path d="M 25 -22 L 24 -6 L 20 -6 L 20 -22 Z" fill="#1a1510" />
                    {/* the dark glasses, and the one gold glint that says there is a light on him */}
                    <rect x={-22} y={-24} width={19} height={13} rx={5} fill="#07070a" />
                    <rect x={3} y={-24} width={19} height={13} rx={5} fill="#07070a" />
                    <line x1={-3} y1={-18} x2={3} y2={-18} stroke="#07070a" strokeWidth={2.5} />
                    {sleeping ? (
                      <>
                        {/* closed lids, just visible through the lenses */}
                        <path
                          d="M -18 -17 q 6 4 12 0"
                          fill="none"
                          stroke="#3a3a46"
                          strokeWidth={1.6}
                        />
                        <path
                          d="M 7 -17 q 6 4 12 0"
                          fill="none"
                          stroke="#3a3a46"
                          strokeWidth={1.6}
                        />
                      </>
                    ) : (
                      <>
                        <line
                          x1={-17}
                          y1={-21}
                          x2={-10}
                          y2={-14}
                          stroke={palette.spotgold}
                          strokeWidth={1.8}
                          opacity={0.85}
                        />
                        <line
                          x1={8}
                          y1={-21}
                          x2={15}
                          y2={-14}
                          stroke={palette.spotgold}
                          strokeWidth={1.8}
                          opacity={0.85}
                        />
                      </>
                    )}
                    {/* the goatee */}
                    <path d="M -7 4 Q 0 16 7 4 Z" fill="#1a1510" />
                  </>
                }
              </g>
              {/* the arm in front of the body, and what the cuff holds */}
              <Sleeve shoulder={shR} elbow={R.elbow} cuff={R.cuff} />
              {prop}
            </g>
          </Pivot>
          {p.prop === "typewriter" && (
            <Typewriter x={0} y={-42} scale={1} typing={typing} pageLines={pageLines} />
          )}
        </g>
      </g>
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the band, the maracas and the trumpet. Same paths, numbers and colours.
// ── The band — three silhouettes on the back wall ───────────────────────────
// A surfer on congas, an alien on maracas, a robot with a trumpet: dark shapes
// against the brick with a rim of stage light on the side that faces the mic,
// and shades drawn as one gold glint each. The set changes only three times
// in the deck: it leans in (slide 7), the robot plays one note (slide 9), and
// two of them trade a look (slide 10). At the held breath their hands are off
// their instruments.
type BandMode = "set" | "lean" | "note" | "look" | "rest";

const SIL = "#22140f";
const RIM = palette.spotgold;

function Band({
  x,
  y,
  scale = 0.9,
  mode = "set",
}: {
  x: number;
  y: number;
  scale?: number;
  mode?: BandMode;
}) {
  const rest = mode === "rest";
  const leanStyle: CSSProperties | undefined =
    mode === "lean"
      ? { animation: `pb-lean ${tempo.act2.beat} ${tempo.act2.ease} 0.9s both` }
      : undefined;
  const lookL: CSSProperties | undefined =
    mode === "look"
      ? ({
          "--turn": "14deg",
          animation: `pb-look ${tempo.act4.warm} ${tempo.act4.ease} 1.6s both`,
        } as CSSProperties)
      : undefined;
  const lookR: CSSProperties | undefined =
    mode === "look"
      ? ({
          "--turn": "-14deg",
          animation: `pb-look ${tempo.act4.warm} ${tempo.act4.ease} 1.6s both`,
        } as CSSProperties)
      : undefined;
  const noteStyle: CSSProperties | undefined =
    mode === "note" ? { animation: `pb-trumpet 320ms ${tempo.act3.ease} 1.8s both` } : undefined;
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`}>
      {/* the whole set pivots at the floor when it leans toward the mic */}
      <Pivot x={0} y={0} style={leanStyle}>
        {/* ── the surfer, behind two congas ── */}
        <g transform="translate(-120 0)">
          {/* congas: tall tapered barrels, chrome rims, a few lugs */}
          {[-26, 26].map((cx) => (
            <g key={cx} transform={`translate(${cx} 0)`}>
              <path d="M -20 -112 L 20 -112 L 16 0 L -16 0 Z" fill="#3a1f14" />
              <path
                d="M -20 -112 L 20 -112 L 16 0 L -16 0 Z"
                fill="none"
                stroke={RIM}
                strokeWidth={1.2}
                opacity={0.35}
              />
              <ellipse
                cx={0}
                cy={-112}
                rx={21}
                ry={6}
                fill="#6a5a48"
                stroke="#b7a98f"
                strokeWidth={2}
              />
              {[-14, 0, 14].map((lx) => (
                <rect key={lx} x={lx - 2} y={-108} width={4} height={14} fill="#8a8a92" />
              ))}
            </g>
          ))}
          {/* the surfer: shaggy hair, shoulders, arms over the drums */}
          <g>
            <path d="M -28 -118 L -22 -196 L 22 -196 L 28 -118 Z" fill={SIL} />
            <path d="M -30 -124 L -64 -112 L -56 -100 L -26 -110 Z" fill={SIL} />
            <path d="M 30 -124 L 64 -112 L 56 -100 L 26 -110 Z" fill={SIL} />
            <Pivot x={0} y={-196} style={lookL}>
              <path
                d="M -24 -196 Q -36 -236 -10 -250 Q 0 -256 12 -250 Q 36 -238 26 -196 L 22 -200 Q 20 -214 14 -222 Q 4 -216 -6 -222 Q -16 -214 -20 -200 Z"
                fill={SIL}
              />
              <ellipse cx={0} cy={-220} rx={21} ry={24} fill={SIL} />
              <path
                d="M 26 -196 Q 36 -238 12 -250"
                fill="none"
                stroke={RIM}
                strokeWidth={2}
                opacity={0.5}
              />
              <line
                x1={-14}
                y1={-224}
                x2={14}
                y2={-224}
                stroke={RIM}
                strokeWidth={2.2}
                opacity={0.8}
              />
            </Pivot>
            {/* rim light on the side toward the mic */}
            <path d="M 22 -196 L 28 -118" stroke={RIM} strokeWidth={2} opacity={0.5} />
          </g>
        </g>

        {/* ── the alien, maracas up ── */}
        <g transform="translate(0 0)">
          <path d="M -16 -112 L -12 -196 L 12 -196 L 16 -112 Z" fill={SIL} />
          <line
            x1={-12}
            y1={-110}
            x2={-18}
            y2={0}
            stroke={SIL}
            strokeWidth={14}
            strokeLinecap="round"
          />
          <line
            x1={12}
            y1={-110}
            x2={18}
            y2={0}
            stroke={SIL}
            strokeWidth={14}
            strokeLinecap="round"
          />
          {/* arms: raised with the maracas, or down at rest */}
          {rest ? (
            <>
              <line
                x1={-12}
                y1={-188}
                x2={-30}
                y2={-120}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <line
                x1={12}
                y1={-188}
                x2={30}
                y2={-120}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <Maraca x={-34} y={-112} rot={160} />
              <Maraca x={34} y={-112} rot={200} />
            </>
          ) : (
            <>
              <line
                x1={-12}
                y1={-188}
                x2={-44}
                y2={-214}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <line
                x1={12}
                y1={-188}
                x2={44}
                y2={-214}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <Maraca x={-48} y={-222} rot={-30} />
              <Maraca x={48} y={-222} rot={30} />
            </>
          )}
          <Pivot x={0} y={-196} style={lookR}>
            <line x1={0} y1={-196} x2={0} y2={-212} stroke={SIL} strokeWidth={8} />
            <ellipse cx={0} cy={-236} rx={22} ry={30} fill={SIL} />
            <line
              x1={-14}
              y1={-238}
              x2={14}
              y2={-238}
              stroke={RIM}
              strokeWidth={2.2}
              opacity={0.8}
            />
          </Pivot>
          <path d="M 12 -196 L 16 -112" stroke={RIM} strokeWidth={2} opacity={0.5} />
        </g>

        {/* ── the robot, trumpet to the light ── */}
        <g transform="translate(118 0)">
          <rect x={-22} y={-196} width={44} height={86} rx={4} fill={SIL} />
          <rect
            x={-10}
            y={-180}
            width={20}
            height={14}
            rx={2}
            fill="none"
            stroke={RIM}
            strokeWidth={1.2}
            opacity={0.5}
          />
          <rect x={-18} y={-112} width={14} height={112} fill={SIL} />
          <rect x={4} y={-112} width={14} height={112} fill={SIL} />
          <rect x={-22} y={-2} width={22} height={6} fill={SIL} />
          <rect x={0} y={-2} width={22} height={6} fill={SIL} />
          {/* head: a box, an antenna, the shades as a visor glint */}
          <rect x={-20} y={-244} width={40} height={42} rx={5} fill={SIL} />
          <line x1={0} y1={-244} x2={0} y2={-262} stroke={SIL} strokeWidth={4} />
          <circle
            cx={0}
            cy={-266}
            r={4}
            fill={RIM}
            opacity={0.9}
            style={{ animation: "pb-glint 2.6s ease-in-out infinite" }}
          />
          <line
            x1={-13}
            y1={-226}
            x2={13}
            y2={-226}
            stroke={RIM}
            strokeWidth={2.6}
            opacity={0.85}
          />
          {/* the trumpet, raised from the mouth; at rest it hangs at the chest */}
          {rest ? (
            <g>
              <line
                x1={-18}
                y1={-186}
                x2={-44}
                y2={-134}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <line
                x1={-18}
                y1={-186}
                x2={-44}
                y2={-134}
                stroke={RIM}
                strokeWidth={1.5}
                opacity={0.45}
              />
              <Trumpet x={-44} y={-128} rot={-80} />
            </g>
          ) : (
            <Pivot x={-2} y={-212} style={noteStyle}>
              <line
                x1={-14}
                y1={-186}
                x2={-34}
                y2={-206}
                stroke={SIL}
                strokeWidth={9}
                strokeLinecap="round"
              />
              <Trumpet x={-4} y={-212} rot={-14} />
            </Pivot>
          )}
          {mode === "note" && (
            <g style={{ opacity: 0 }}>
              {[0, 1, 2].map((i) => (
                <Pivot
                  key={i}
                  x={-63}
                  y={-297}
                  style={{ animation: `pb-ring 1100ms ease-out ${2.1 + i * 0.22}s both` }}
                >
                  <circle
                    cx={-63}
                    cy={-297}
                    r={18 + i * 10}
                    fill="none"
                    stroke={palette.spotgold}
                    strokeWidth={2.5}
                  />
                </Pivot>
              ))}
            </g>
          )}
        </g>
      </Pivot>
    </g>
  );
}

function Maraca({ x, y, rot }: { x: number; y: number; rot: number }) {
  return (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <line x1={0} y1={0} x2={0} y2={22} stroke={SIL} strokeWidth={4} strokeLinecap="round" />
      <ellipse cx={0} cy={-10} rx={9} ry={12} fill={SIL} />
      <ellipse
        cx={0}
        cy={-10}
        rx={9}
        ry={12}
        fill="none"
        stroke={RIM}
        strokeWidth={1}
        opacity={0.4}
      />
    </g>
  );
}

/** The trumpet: a tube from the mouthpiece to a flared bell, the bell catching the gold. */
function Trumpet({ x, y, rot }: { x: number; y: number; rot: number }) {
  return (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <line
        x1={0}
        y1={0}
        x2={-70}
        y2={-10}
        stroke={palette.goldDeep}
        strokeWidth={6}
        strokeLinecap="round"
      />
      <line
        x1={-20}
        y1={2}
        x2={-50}
        y2={-2}
        stroke={palette.goldDeep}
        strokeWidth={10}
        strokeLinecap="round"
      />
      {[-30, -38, -46].map((vx) => (
        <line
          key={vx}
          x1={vx}
          y1={-4}
          x2={vx}
          y2={-14}
          stroke={palette.spotgold}
          strokeWidth={3}
          strokeLinecap="round"
        />
      ))}
      <path
        d="M -70 -10 C -84 -14, -94 -28, -102 -36 Q -108 -16 -102 6 C -94 -2, -84 -8, -70 -10 Z"
        fill={palette.spotgold}
        opacity={0.95}
      />
      <path
        d="M -70 -10 C -84 -14, -94 -28, -102 -36 Q -108 -16 -102 6 C -94 -2, -84 -8, -70 -10 Z"
        fill="none"
        stroke={palette.goldDeep}
        strokeWidth={1.5}
      />
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the room's furniture: ceiling, bulbs, brick, string lights, GreenSmoke, SpotlightCone, floor, stage, the poet's table, Chessboard, cup, café tables and chairs. Same paths, numbers and colours.
// ── The room's furniture ────────────────────────────────────────────────────
const LAMP: [number, number] = [1000, 128];
const POOL: [number, number] = [1000, 606];
const STAGE_FRONT_Y = 668;

/** The pressed-tin ceiling, two hanging bulbs, and the string of lights over the stage. */
function Ceiling() {
  return (
    <g>
      <rect x={-200} y={-100} width={2000} height={250} fill={palette.tin} />
      {Array.from({ length: 26 }, (_, c) =>
        [0, 1].map((r) => (
          <g key={`${c}-${r}`} transform={`translate(${-160 + c * 80} ${r * 72})`}>
            <rect
              x={4}
              y={4}
              width={72}
              height={64}
              fill="none"
              stroke={palette.tinLit}
              strokeWidth={1.2}
              opacity={0.6}
            />
            <path
              d="M 40 14 L 62 36 L 40 58 L 18 36 Z"
              fill="none"
              stroke={palette.tinLit}
              strokeWidth={1}
              opacity={0.5}
            />
            <circle cx={40} cy={36} r={6} fill={palette.tinLit} opacity={0.35} />
          </g>
        )),
      )}
      {/* a cornice where tin meets brick */}
      <rect x={-200} y={146} width={2000} height={8} fill="#2a1c14" />
    </g>
  );
}

function Bulb({ x, drop, still = false }: { x: number; drop: number; still?: boolean }) {
  return (
    <g>
      <line x1={x} y1={0} x2={x} y2={drop - 18} stroke="#17110d" strokeWidth={2} />
      <rect x={x - 5} y={drop - 20} width={10} height={12} fill="#1a1410" />
      <circle cx={x} cy={drop + 8} r={64} fill="url(#pb-bulb)" />
      <ellipse
        cx={x}
        cy={drop + 2}
        rx={9}
        ry={13}
        fill="#ffe7a8"
        style={still ? undefined : { animation: "pb-glint 3.2s ease-in-out infinite" }}
      />
      <path
        d={`M ${x - 3} ${drop + 6} L ${x} ${drop - 2} L ${x + 3} ${drop + 6}`}
        fill="none"
        stroke={palette.spotgold}
        strokeWidth={1.2}
      />
    </g>
  );
}

/** The brick back wall, deterministic courses, a darker band where the stage lights don't reach. */
function BrickWall() {
  const rows = 20;
  const tones = [palette.brickwarm, palette.brickDeep, "#93492f", "#7f3e2a"];
  return (
    <g>
      <rect x={-200} y={150} width={2000} height={470} fill={palette.mortar} />
      {Array.from({ length: rows }, (_, r) =>
        Array.from({ length: 30 }, (_, c) => {
          const off = r % 2 === 0 ? 0 : 36;
          const tone = tones[(r * 7 + c * 3) % tones.length];
          return (
            <rect
              key={`${r}-${c}`}
              x={-220 + c * 72 + off}
              y={154 + r * 23.5}
              width={68}
              height={20}
              fill={tone}
              opacity={0.92}
            />
          );
        }),
      )}
      {/* the wall falls off into shadow at its edges and foot */}
      <rect x={-200} y={150} width={2000} height={470} fill="url(#pb-vignette)" opacity={0.7} />
    </g>
  );
}

function StringLights({ still = false }: { still?: boolean }) {
  const pts = Array.from({ length: 11 }, (_, i) => {
    const t = i / 10;
    return [700 + t * 640, 196 + Math.sin(t * Math.PI) * 42] as [number, number];
  });
  return (
    <g>
      <path
        d={`M ${pts.map((p) => p.join(" ")).join(" L ")}`}
        fill="none"
        stroke="#1a1410"
        strokeWidth={1.5}
      />
      {pts.map((p, i) => (
        <g key={i}>
          <circle cx={p[0]} cy={p[1] + 8} r={14} fill="url(#pb-bulb)" />
          <circle
            cx={p[0]}
            cy={p[1] + 8}
            r={3.5}
            fill="#ffe7a8"
            style={
              still
                ? undefined
                : {
                    animation: `pb-glint ${2.2 + (i % 3) * 0.7}s ease-in-out ${-(i % 5) * 0.4}s infinite`,
                  }
            }
          />
        </g>
      ))}
    </g>
  );
}

/** GreenSmoke: four ribbons under the tin, blurred, drifting; `still` freezes them mid-curl. */
function GreenSmoke({ still = false, thin = false }: { still?: boolean; thin?: boolean }) {
  const ribbons = [
    { y: 112, w: 34, o: 0.26, d: 0 },
    { y: 150, w: 44, o: 0.2, d: -1.3 },
    { y: 190, w: 28, o: 0.22, d: -2.4 },
    { y: 236, w: 20, o: 0.14, d: -3.1 },
    { y: 282, w: 16, o: 0.12, d: -0.8 },
  ];
  return (
    <g
      filter="url(#pb-smokeblur)"
      style={thin ? { animation: "pb-thin 8s linear both" } : undefined}
    >
      {ribbons.map((r, i) => (
        <g
          key={i}
          style={
            still
              ? undefined
              : { animation: `pb-smoke 4000ms ease-in-out ${r.d}s infinite alternate` }
          }
        >
          <path
            d={`M -300 ${r.y} C 0 ${r.y - 50}, 260 ${r.y + 60}, 560 ${r.y} S 1060 ${r.y - 60}, 1360 ${r.y} S 1800 ${r.y + 60}, 2000 ${r.y}`}
            fill="none"
            stroke={palette.smokegreen}
            strokeWidth={r.w}
            opacity={still ? Math.min(0.5, r.o * 1.7) : r.o}
            strokeLinecap="round"
          />
        </g>
      ))}
      {/* where the bulbs catch it */}
      <ellipse cx={440} cy={210} rx={120} ry={30} fill={palette.spotgold} opacity={0.12} />
      <ellipse cx={1180} cy={210} rx={120} ry={30} fill={palette.spotgold} opacity={0.12} />
    </g>
  );
}

/** SpotlightCone: the lamp at the ceiling, the beam, and the pool it leaves on the stage. */
function SpotlightCone({ still = false, opacity = 1 }: { still?: boolean; opacity?: number }) {
  const [lx, ly] = LAMP;
  const [px, py] = POOL;
  return (
    <g opacity={opacity}>
      <Pivot
        x={lx}
        y={ly}
        style={still ? undefined : { animation: "pb-sway 2000ms ease-in-out infinite alternate" }}
      >
        <polygon
          points={`${lx - 16},${ly} ${lx + 16},${ly} ${px + 200},${py} ${px - 200},${py}`}
          fill="url(#pb-cone)"
        />
        <ellipse cx={px} cy={py} rx={230} ry={46} fill="url(#pb-pool)" />
      </Pivot>
      {/* the lamp housing, hung from the tin */}
      <line x1={lx} y1={0} x2={lx} y2={ly - 26} stroke="#17110d" strokeWidth={3} />
      <path
        d={`M ${lx - 22} ${ly - 26} L ${lx + 22} ${ly - 26} L ${lx + 30} ${ly} L ${lx - 30} ${ly} Z`}
        fill="#1a1410"
      />
      <ellipse cx={lx} cy={ly} rx={30} ry={6} fill="#ffe7a8" opacity={0.9} />
    </g>
  );
}

function Floor() {
  return (
    <g>
      <rect x={-200} y={620} width={2000} height={400} fill="url(#pb-plank)" />
      {[650, 690, 736, 790, 850, 920].map((y) => (
        <line
          key={y}
          x1={-200}
          y1={y}
          x2={1800}
          y2={y}
          stroke="#1a100a"
          strokeWidth={1.5}
          opacity={0.7}
        />
      ))}
    </g>
  );
}

/** The small raised stage: a top face and a dark front, with the mic stand. */
function StagePlatform({ mic = true }: { mic?: boolean }) {
  return (
    <g>
      <polygon points="740,560 1320,560 1340,628 720,628" fill={palette.woodLit} />
      {[780, 860, 940, 1020, 1100, 1180, 1260].map((x) => (
        <line
          key={x}
          x1={x}
          y1={560}
          x2={x - 6}
          y2={628}
          stroke={palette.wood}
          strokeWidth={1.2}
          opacity={0.8}
        />
      ))}
      <rect x={720} y={628} width={620} height={40} fill={palette.wood} />
      <rect x={720} y={628} width={620} height={4} fill="#8a5a33" opacity={0.7} />
      <rect x={720} y={STAGE_FRONT_Y} width={620} height={10} fill="#1a100a" opacity={0.6} />
      {mic && (
        <g>
          <ellipse cx={1052} cy={620} rx={18} ry={5} fill="#1a1410" />
          <line x1={1052} y1={620} x2={1052} y2={440} stroke="#2c2c34" strokeWidth={4} />
          <line x1={1052} y1={440} x2={1026} y2={400} stroke="#2c2c34" strokeWidth={3} />
          <g transform="translate(1022 396) rotate(32)">
            <rect x={-7} y={-16} width={14} height={28} rx={6} fill="#3a3a44" />
            <rect x={-7} y={-16} width={14} height={14} rx={6} fill="#6a6a78" />
          </g>
        </g>
      )}
    </g>
  );
}

/** The poet's table, on the stage's left: the slips land here. */
function PoetTable({ x, y }: { x: number; y: number }) {
  return (
    <g>
      <rect x={x - 3} y={y} width={6} height={60} fill="#2a1a12" />
      <ellipse cx={x} cy={y + 60} rx={28} ry={7} fill="#1a100a" />
      <ellipse cx={x} cy={y} rx={60} ry={18} fill={palette.woodLit} />
      <ellipse cx={x} cy={y - 3} rx={60} ry={18} fill="#8a5a33" />
    </g>
  );
}

/** A chessboard mid-game on a table top, flattened by the room's view of it. Nothing moves. */
function Chessboard({ x, y, seed = 0 }: { x: number; y: number; seed?: number }) {
  const cell = 6;
  const pieces = [
    [1, 1, "d"],
    [3, 1, "d"],
    [6, 0, "d"],
    [4, 2, "d"],
    [2, 4, "l"],
    [5, 4, "l"],
    [1, 6, "l"],
    [6, 6, "l"],
    [3, 7, "l"],
  ] as Array<[number, number, "d" | "l"]>;
  return (
    <g transform={`translate(${x} ${y}) scale(1 0.5)`}>
      <rect
        x={-cell * 4 - 3}
        y={-cell * 4 - 3}
        width={cell * 8 + 6}
        height={cell * 8 + 6}
        fill="#2a1a12"
      />
      {Array.from({ length: 8 }, (_, r) =>
        Array.from({ length: 8 }, (_, c) => (
          <rect
            key={`${r}-${c}`}
            x={-cell * 4 + c * cell}
            y={-cell * 4 + r * cell}
            width={cell}
            height={cell}
            fill={(r + c) % 2 === 0 ? palette.paper : "#3b2416"}
          />
        )),
      )}
      {pieces.map(([c, r, k], i) => {
        const cc = (c + seed) % 8;
        return (
          <g
            key={i}
            transform={`translate(${-cell * 4 + cc * cell + cell / 2} ${-cell * 4 + r * cell + cell / 2}) scale(1 2)`}
          >
            <circle cx={0} cy={-5} r={2.2} fill={k === "d" ? "#1a1410" : "#f3ead8"} />
            <rect x={-2} y={-3} width={4} height={3.5} fill={k === "d" ? "#1a1410" : "#f3ead8"} />
          </g>
        );
      })}
    </g>
  );
}

function Cup({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <ellipse cx={0} cy={2} rx={9} ry={3} fill="#1a100a" opacity={0.5} />
      <path d="M -7 -10 L -6 2 L 6 2 L 7 -10 Z" fill={palette.paper} />
      <ellipse cx={0} cy={-10} rx={7} ry={2.4} fill="#6a4a2e" />
      <path d="M 7 -7 q 6 0 6 4 q 0 4 -6 4" fill="none" stroke={palette.paper} strokeWidth={1.6} />
    </g>
  );
}

/** A café table seen from behind the room, with a bentwood chair's back in front of it. */
function CafeTable({
  x,
  y,
  chess = false,
  seed = 0,
  chairs = 2,
}: {
  x: number;
  y: number;
  chess?: boolean;
  seed?: number;
  chairs?: number;
}) {
  return (
    <g>
      <rect x={x - 4} y={y} width={8} height={70} fill="#2a1a12" />
      <ellipse cx={x} cy={y + 70} rx={34} ry={8} fill="#1a100a" />
      <ellipse cx={x} cy={y + 2} rx={78} ry={24} fill={palette.wood} />
      <ellipse cx={x} cy={y - 3} rx={78} ry={24} fill={palette.woodLit} />
      {chess ? <Chessboard x={x} y={y - 6} seed={seed} /> : <Cup x={x + 20} y={y - 2} />}
      {chess && <Cup x={x - 54} y={y + 4} />}
      {Array.from({ length: chairs }, (_, i) => (
        <ChairBack key={i} x={x + (i === 0 ? -46 : 46)} y={y + 44} />
      ))}
    </g>
  );
}

function ChairBack({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <path
        d="M -26 40 L -24 -30 Q 0 -52 24 -30 L 26 40"
        fill="none"
        stroke="#3b2416"
        strokeWidth={6}
        strokeLinecap="round"
      />
      <path d="M -24 -30 Q 0 -52 24 -30" fill="none" stroke="#5a3a24" strokeWidth={2} />
      {[-12, 0, 12].map((sx) => (
        <line
          key={sx}
          x1={sx}
          y1={-36 + Math.abs(sx) * 0.3}
          x2={sx}
          y2={30}
          stroke="#3b2416"
          strokeWidth={3.5}
        />
      ))}
      <rect x={-30} y={30} width={60} height={10} rx={3} fill="#3b2416" />
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — SnapChorus. Same paths, numbers and colours.
// ── SnapChorus — glyph hands at the tables ──────────────────────────────────
// A hand mid-snap: the sleeve, a palm, the index up, the thumb and middle
// finger pressed in a loop, two fingers curled. Drawn as a pictogram at a
// small size, never a studied hand. The snap's ring and spark go out from
// the loop; the chorus runs on a three-second wave, delayed by each hand's
// distance from the stage, so approval ripples outward across the room.
type HandMode = "none" | "poised" | "raised" | "snap" | "rest";

const SKINS = ["#d9a37e", "#b97a55", "#efc9a6", "#8f5a3c"];
const SLEEVES = ["#4a3a36", "#5a4a3c", "#3a3a44", "#6a3a30"];

function SnapHand({
  x,
  y,
  i,
  mode,
  flip = false,
  delay = 0,
}: {
  x: number;
  y: number;
  i: number;
  mode: HandMode;
  flip?: boolean;
  delay?: number;
}) {
  const skin = SKINS[i % SKINS.length];
  const sleeve = SLEEVES[(i * 3) % SLEEVES.length];
  const s = flip ? -1 : 1;
  const snapping = mode === "snap";
  const up: CSSProperties | undefined =
    mode === "raised"
      ? { animation: `pb-hand-up 400ms ${tempo.act2.ease} ${0.6 + delay * 0.4}s backwards` }
      : undefined;
  const resting = mode === "rest";
  return (
    <g transform={`translate(${x} ${y}) scale(${s} 1) rotate(${resting ? 64 : -8})`}>
      <g style={up}>
        {/* the sleeve, from below the frame */}
        <line
          x1={0}
          y1={0}
          x2={4}
          y2={190}
          stroke={sleeve}
          strokeWidth={16}
          strokeLinecap="round"
        />
        <rect x={-8} y={0} width={16} height={10} fill={skin} />
        {/* the palm */}
        <path d="M -10 -4 Q -12 -30 0 -32 Q 12 -30 10 -4 Z" fill={skin} />
        {/* the index, up */}
        <line
          x1={-5}
          y1={-28}
          x2={-10}
          y2={-52}
          stroke={skin}
          strokeWidth={6}
          strokeLinecap="round"
        />
        {/* thumb and middle finger, pressed in the loop */}
        <path
          d="M 4 -30 Q 16 -42 22 -30 Q 22 -22 12 -22"
          fill="none"
          stroke={skin}
          strokeWidth={5.5}
          strokeLinecap="round"
        />
        {/* ring and little finger, curled */}
        <path
          d="M 8 -14 q 8 -2 8 6"
          fill="none"
          stroke={skin}
          strokeWidth={5}
          strokeLinecap="round"
        />
        <path
          d="M 6 -6 q 7 -1 7 5"
          fill="none"
          stroke={skin}
          strokeWidth={4.5}
          strokeLinecap="round"
        />
        {/* the snap: a ring and a spark from the loop, on the wave */}
        {snapping && (
          <g>
            <Pivot
              x={18}
              y={-32}
              style={{
                opacity: 0,
                animation: `pb-snap 3000ms cubic-bezier(0, 0, 0.2, 1) ${delay}s infinite`,
              }}
            >
              <circle
                cx={18}
                cy={-32}
                r={16}
                fill="none"
                stroke={palette.spotgold}
                strokeWidth={2.5}
              />
            </Pivot>
            <g
              style={{ opacity: 0, animation: `pb-spark 3000ms linear ${delay}s infinite` }}
              stroke={palette.spotgold}
              strokeWidth={2.2}
              strokeLinecap="round"
            >
              <line x1={22} y1={-44} x2={28} y2={-56} />
              <line x1={30} y1={-34} x2={42} y2={-36} />
              <line x1={26} y1={-22} x2={34} y2={-12} />
            </g>
          </g>
        )}
      </g>
    </g>
  );
}

/** Where the hands are: beside each chair, by each table. The wave starts at the stage and travels outward. */
function SnapChorus({ mode, poised = false }: { mode: HandMode; poised?: boolean }) {
  if (mode === "none") return null;
  const hands: Array<[number, number, boolean]> = [
    [330, 760, false],
    [470, 772, true],
    [596, 826, false],
    [742, 834, true],
    [900, 812, false],
    [1030, 820, true],
    [1150, 836, false],
    [1296, 846, true],
  ];
  const stageX = 1000;
  const stageY = 640;
  return (
    <g>
      {hands.map(([x, y, flip], i) => {
        const dist = Math.hypot(x - stageX, y - stageY);
        const delay = (dist / 900) * 1.4 + ((i * 7) % 3) * 0.08;
        if (mode === "rest" && flip) return null;
        return (
          <SnapHand
            key={i}
            x={x}
            y={y + (mode === "rest" ? 10 : 0)}
            i={i}
            mode={poised ? "poised" : mode}
            flip={flip}
            delay={delay}
          />
        );
      })}
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — VerseLine, the cutting's clock and the words helper. Same paths, numbers and colours.
// ── VerseLine — words settling into meter on typed strips ───────────────────
// A line in flight is loose smokegreen words; a line settled is inkblack type
// on a strip of paper, as if pulled from the typewriter. `settle` drifts the
// words in from the smoke and lands them, green to ink, with the strip
// arriving under the first landing. `hang` types each word in place on its
// strip, as spoken. `shed` is the cutting: words drift in, a round of them is
// overstruck and dissolves, then a second round, and the survivors lock to
// ink; the poem then types itself on a strip beneath. `fade` is a hang that
// dissolves at `fadeAt` — the crossfade of the deed.
type Word = { t: string; cut?: 1 | 2 };
type VerseMode = "settle" | "hang" | "shed" | "fade";

function VerseLine({
  x,
  y,
  lines,
  size = 22,
  mode,
  start = 0.4,
  lineGap = 46,
  fadeAt = 1.2,
  poem,
}: {
  x: number;
  y: number;
  lines: Word[][];
  size?: number;
  mode: VerseMode;
  start?: number;
  lineGap?: number;
  fadeAt?: number;
  poem?: string[];
}) {
  const adv = size * ADV;
  let n = 0;
  const strip = (lx: number, ly: number, w: number, delay: number, typeIn = false) => (
    <g
      style={
        mode === "fade" ? { animation: `pb-vanish 600ms ease-in-out ${fadeAt}s both` } : undefined
      }
    >
      <g
        style={
          typeIn
            ? {
                transformOrigin: `${lx - 12}px ${ly}px`,
                transformBox: "view-box",
                animation: `pb-typeline 900ms steps(24, end) ${delay}s backwards`,
              }
            : { animation: `pb-fade 500ms ease-out ${delay}s backwards` }
        }
      >
        <rect
          x={lx - 12}
          y={ly - size * 0.95}
          width={w + 24}
          height={size * 1.4}
          fill={palette.paper}
        />
        <rect
          x={lx - 12}
          y={ly - size * 0.95}
          width={w + 24}
          height={size * 1.4}
          fill="none"
          stroke={palette.paperShade}
          strokeWidth={1}
        />
      </g>
    </g>
  );
  const rendered = lines.map((words, li) => {
    const text = words.map((w) => w.t).join(" ");
    const w = text.length * adv;
    const lx = x - w / 2;
    const ly = y + li * lineGap;
    let col = 0;
    const items = words.map((word, wi) => {
      const wx = lx + col * adv;
      col += word.t.length + 1;
      const i = n++;
      const vars = {
        "--dx": `${((i * 37) % 90) - 45}px`,
        "--dy": `${-20 - ((i * 53) % 70)}px`,
      } as CSSProperties;
      let style: CSSProperties;
      let fill: string = palette.inkblack;
      let strike: ReactNode = null;
      switch (mode) {
        case "settle":
          style = {
            ...vars,
            animation: `pb-word-in 700ms ease-in-out ${start + i * 0.12}s backwards`,
          };
          break;
        case "hang":
          style = { animation: `pb-fade 120ms linear ${start + i * 0.12}s backwards` };
          break;
        case "fade":
          style = {
            animation: `pb-fade 120ms linear ${start + i * 0.12}s backwards, pb-vanish 600ms ease-in-out ${fadeAt}s both`,
          };
          break;
        case "shed": {
          fill = palette.smokegreen;
          const cutAt = word.cut === 1 ? SHED.cut1 : word.cut === 2 ? SHED.cut2 : 0;
          if (word.cut) {
            style = {
              ...vars,
              animation: `pb-word-air 700ms ease-in-out ${start + i * 0.06}s backwards, pb-word-cut 1000ms ${tempo.act2.ease} ${cutAt + 0.7}s both`,
            };
            strike = (
              <text
                x={wx}
                y={ly}
                fontFamily={typed}
                fontSize={size}
                fill={palette.inkblack}
                xmlSpace="preserve"
                style={{ animation: `pb-fade 160ms linear ${cutAt}s backwards` }}
              >
                {"x".repeat(word.t.length)}
              </text>
            );
          } else {
            // a survivor stays in the air until the poem types in its place
            style = {
              ...vars,
              animation: `pb-word-air 700ms ease-in-out ${start + i * 0.06}s backwards, pb-vanish 600ms ease-in-out ${SHED.lock}s both`,
            };
          }
          break;
        }
      }
      return (
        <g key={wi}>
          <text
            x={wx}
            y={ly}
            fontFamily={typed}
            fontSize={size}
            fill={fill}
            xmlSpace="preserve"
            style={style}
          >
            {word.t}
          </text>
          {strike && (
            <g
              style={
                word.cut
                  ? {
                      animation: `pb-word-cut 1000ms ${tempo.act2.ease} ${(word.cut === 1 ? SHED.cut1 : SHED.cut2) + 0.7}s both`,
                    }
                  : undefined
              }
            >
              {strike}
            </g>
          )}
        </g>
      );
    });
    const stripDelay = mode === "settle" ? start + 0.5 : start - 0.1;
    return (
      <g key={li}>
        {mode !== "shed" && strip(lx, ly, w, stripDelay)}
        {items}
      </g>
    );
  });
  // the poem the survivors become, typed onto strips where the draft hung
  const poemLines = poem?.map((line, pi) => {
    const w = line.length * adv;
    const lx = x - w / 2;
    const ly = y + pi * lineGap;
    const d = SHED.lock + 0.5 + pi * 0.9;
    return (
      <g key={`p${pi}`}>
        {strip(lx, ly, w, d, true)}
        <g style={{ animation: `pb-fade 60ms linear ${d}s backwards` }}>
          <clipPath id={`pb-type-${pi}-${Math.round(x)}`}>
            <rect
              x={lx - 12}
              y={ly - size}
              width={w + 24}
              height={size * 1.6}
              style={{
                transformOrigin: `${lx - 12}px ${ly}px`,
                transformBox: "view-box",
                animation: `pb-typeline 900ms steps(24, end) ${d}s backwards`,
              }}
            />
          </clipPath>
          <text
            x={lx}
            y={ly}
            fontFamily={typed}
            fontSize={size}
            fill={palette.inkblack}
            xmlSpace="preserve"
            clipPath={`url(#pb-type-${pi}-${Math.round(x)})`}
          >
            {line}
          </text>
        </g>
      </g>
    );
  });
  return (
    <g>
      {rendered}
      {poemLines}
    </g>
  );
}

// the cutting's clock: the first cut, the second, and the moment the survivors give way to the poem
const SHED = { cut1: 2.4, cut2: 3.7, lock: 5.0 } as const;

const words = (s: string, cuts: Record<string, 1 | 2> = {}): Word[] =>
  s.split(" ").map((t) => ({ t, cut: cuts[t] }));

// ── RequestSlip — a work item arriving, drawn as the commercial's Envelope ──
// Copied from src/decks/the-toolkit.tsx ("Atom: Envelope"): paper, an ink
// border, the V of the flap, its type on a post-it at the corner, its id small
// in the corner. The same geometry and numbers; the colours are read from the
// envelope token, which holds that deck's own values. Its Postmarks are left
// behind with the commercial: no envelope in this deck is stamped.
type CardType = keyof typeof palette.envelope.tab;

function Envelope({
  x,
  y,
  w = 110,
  type,
  id,
}: {
  x: number;
  y: number;
  w?: number;
  type?: CardType;
  id?: string;
}) {
  const E = palette.envelope;
  const h = Math.round(w * 0.62);
  const tab = Math.max(18, Math.round(w * 0.22));
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x={3} y={3} width={w} height={h} fill={E.shade} opacity="0.28" />
      <rect x={0} y={0} width={w} height={h} fill={E.paper} stroke={E.ink} strokeWidth="2" />
      <polyline
        points={`2,2 ${w / 2},${h * 0.5} ${w - 2},2`}
        fill="none"
        stroke={E.ink}
        strokeWidth="2"
      />
      {type && (
        <g transform={`translate(-5 -7) rotate(-8 ${tab / 2} ${tab / 2})`}>
          <rect x={2} y={2} width={tab} height={tab} fill={E.shade} opacity="0.18" />
          <rect x={0} y={0} width={tab} height={tab} fill={E.tab[type]} />
          <rect
            x={tab * 0.18}
            y={tab * 0.34}
            width={tab * 0.6}
            height={tab * 0.1}
            fill={E.tabRule}
          />
          <rect
            x={tab * 0.18}
            y={tab * 0.56}
            width={tab * 0.42}
            height={tab * 0.1}
            fill={E.tabRule}
          />
        </g>
      )}
      {id && (
        <text
          x={8}
          y={h - 6}
          fontFamily={MONO}
          fontSize={Math.max(8, w * 0.085)}
          letterSpacing="0.06em"
          fill={E.inkSoft}
        >
          {id}
        </text>
      )}
    </g>
  );
}

/** One slip: the Envelope, placed by its centre and turned. Motion goes on the inner group, never the placement. */
function RequestSlip({
  x,
  y,
  rot = 0,
  w = 70,
  type,
  id,
  style,
}: {
  x: number;
  y: number;
  rot?: number;
  w?: number;
  type?: CardType;
  id?: string;
  style?: CSSProperties;
}) {
  const h = Math.round(w * 0.62);
  return (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <g style={style}>
        <Envelope x={-w / 2} y={-h / 2} w={w} type={type} id={id} />
      </g>
    </g>
  );
}

// The work items the room sees, in the order they come down. 4127 is the one the deck follows.
const WORK_ITEMS: Array<{ id: string; type: CardType }> = [
  { id: "4119", type: "bug" },
  { id: "4123", type: "story" },
  { id: "4125", type: "bug" },
  { id: "4127", type: "story" },
  { id: "4131", type: "bug" },
  { id: "4135", type: "story" },
];

// Where the poet's table stands on the stage (the Room draws it), and where a stack sits on it.
const TABLE: [number, number] = [850, 556];
const STACK_X = TABLE[0] - 14;
const SLIP_W = 70;

/** Where the nth slip of a stack rests: each a little higher than the one under it, never quite square. */
function stackSpot(n: number) {
  return { x: STACK_X + ((n * 37) % 9) - 4, y: TABLE[1] - 15 - n * 5, rot: ((n * 53) % 7) - 3 };
}

/** Slips resting on the poet's table; the last `fall` of them drift down and land, ease-in. */
function SlipStack({
  items,
  fall = 0,
  start = 0.8,
}: {
  items: number[];
  fall?: number;
  start?: number;
}) {
  return (
    <g>
      {items.map((item, n) => {
        const spot = stackSpot(n);
        const falling = n >= items.length - fall;
        const k = n - (items.length - fall);
        const vars = {
          "--sx": `${((n * 71) % 120) - 60}px`,
          "--sr": `${((n * 29) % 50) - 25}deg`,
        } as CSSProperties;
        return (
          <RequestSlip
            key={item}
            x={spot.x}
            y={spot.y}
            rot={spot.rot}
            w={SLIP_W}
            type={WORK_ITEMS[item].type}
            id={WORK_ITEMS[item].id}
            style={
              falling
                ? { ...vars, animation: `pb-slip-fall 500ms ease-in ${start + k * 0.9}s backwards` }
                : undefined
            }
          />
        );
      })}
    </g>
  );
}

// ── PromptCard — the work item's one prompt file, the record ────────────────
// The poet's typed page and the card are one object (design note, Holds 3):
// paper, typed lines, a typed rule and a footer line at its foot. It gathers
// its lines as the slides go; a line marked `at` settles onto the page then.
interface CardLine {
  segs: Seg[];
  /** Extra air above the line, in line-heights. */
  gap?: number;
  /** Seconds in: the line settles onto the page at this moment. Omit for a line already there. */
  at?: number;
}

const line = (t: string, more: Omit<CardLine, "segs"> = {}): CardLine => ({
  segs: [{ t }],
  ...more,
});

function PromptCard({
  x,
  y,
  w,
  h,
  size,
  rot = 0,
  lines,
  footer,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  size: number;
  rot?: number;
  lines: CardLine[];
  footer: CardLine[];
}) {
  const pad = size * 2;
  const pitch = size * 1.5;
  const left = -w / 2 + pad;
  const settle = (at: number | undefined): CSSProperties | undefined =>
    at === undefined
      ? undefined
      : { animation: `pb-line-settle 700ms ease-in-out ${at}s backwards` };
  const top = -h / 2 + pad + size * 0.4;
  const body = lines.map((l, i) => {
    // a line sits one pitch under the last, plus whatever air the lines so far asked for
    const air = lines.slice(0, i + 1).reduce((sum, each) => sum + (each.gap ?? 0), 0);
    return (
      <g key={i} style={settle(l.at)}>
        <TypedLine
          x={left}
          y={top + (i + air) * pitch}
          size={size}
          segs={l.segs}
          color={palette.ink}
        />
      </g>
    );
  });
  const footTop = h / 2 - pad - (footer.length - 1) * pitch;
  const ruleChars = Math.floor((w - pad * 2) / (size * ADV));
  return (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <rect
        x={-w / 2}
        y={-h / 2}
        width={w}
        height={h}
        fill={palette.inkblack}
        opacity={0.45}
        transform="translate(8 10)"
      />
      <rect
        x={-w / 2}
        y={-h / 2}
        width={w}
        height={h}
        fill={palette.paper}
        stroke={palette.paperShade}
        strokeWidth={1}
      />
      {body}
      {/* the card's foot: a typed rule, and the link lines under it */}
      <TypedLine
        x={left}
        y={footTop - pitch}
        size={size}
        segs={[{ t: "-".repeat(ruleChars) }]}
        color={palette.paperShade}
      />
      {footer.map((l, i) => (
        <g key={i} style={settle(l.at)}>
          <TypedLine
            x={left}
            y={footTop + i * pitch}
            size={size}
            segs={l.segs}
            color={palette.inkblack}
          />
        </g>
      ))}
    </g>
  );
}

/** The same card at the room's scale: the first deck's typed page (its HeldPage), with the rule and the link line at its foot. */
function CardPage({
  x,
  y,
  rot = 0,
  lines = 4,
  flat = false,
}: {
  x: number;
  y: number;
  rot?: number;
  lines?: number;
  flat?: boolean;
}) {
  const w = 46;
  const h = 64;
  // `flat` lays the page on a surface seen from the room: squashed the way the Chessboard is on its table
  return (
    <g transform={`translate(${x} ${y})${flat ? " scale(1 0.42)" : ""} rotate(${rot})`}>
      <rect
        x={-w / 2}
        y={-h / 2}
        width={w}
        height={h}
        fill={palette.paper}
        stroke={palette.paperShade}
        strokeWidth={1}
      />
      {Array.from({ length: lines }, (_, i) => (
        <line
          key={i}
          x1={-w / 2 + 7}
          y1={-h / 2 + 11 + i * 9}
          x2={-w / 2 + 7 + (w - 18) * (i % 2 === 0 ? 0.9 : 0.6)}
          y2={-h / 2 + 11 + i * 9}
          stroke={palette.ink}
          strokeWidth={1.8}
          strokeDasharray="2.5 1.5"
          opacity={0.7}
        />
      ))}
      <line
        x1={-w / 2 + 7}
        y1={h / 2 - 15}
        x2={w / 2 - 7}
        y2={h / 2 - 15}
        stroke={palette.paperShade}
        strokeWidth={1.4}
      />
      <line
        x1={-w / 2 + 7}
        y1={h / 2 - 8}
        x2={w / 2 - 13}
        y2={h / 2 - 8}
        stroke={palette.inkblack}
        strokeWidth={1.8}
        strokeDasharray="2.5 1.5"
        opacity={0.85}
      />
    </g>
  );
}

/** The card in the typewriter (slide 5): the draft, its two rounds of cuts overstruck as they are made, the poem under them, the foot. */
function CardInTypewriter() {
  const row = (i: number, len: number, at: number, cutAt?: number) => (
    <g key={i}>
      <line
        x1={-26}
        y1={-84 + i * 9}
        x2={-26 + len}
        y2={-84 + i * 9}
        stroke={palette.ink}
        strokeWidth={2.2}
        strokeDasharray="3 2"
        opacity={0.75}
        style={{ animation: `pb-fade 200ms linear ${at}s backwards` }}
      />
      {cutAt !== undefined && (
        <text
          x={-26}
          y={-84 + i * 9 + 2.4}
          fontFamily={typed}
          fontSize={8}
          fill={palette.inkblack}
          xmlSpace="preserve"
          style={{ animation: `pb-fade 160ms linear ${cutAt}s backwards` }}
        >
          {"x".repeat(Math.round(len / (8 * ADV)))}
        </text>
      )}
    </g>
  );
  return (
    <g>
      {row(0, 44, 0.4, SHED.cut1)}
      {row(1, 50, 0.9, SHED.cut2)}
      {row(2, 38, 1.4, SHED.cut1)}
      {row(4, 46, SHED.lock + 0.5)}
      {row(5, 52, SHED.lock + 1.4)}
      <line x1={-26} y1={-24} x2={26} y2={-24} stroke={palette.paperShade} strokeWidth={1.4} />
      <line
        x1={-26}
        y1={-16}
        x2={14}
        y2={-16}
        stroke={palette.inkblack}
        strokeWidth={2.2}
        strokeDasharray="3 2"
        opacity={0.85}
      />
    </g>
  );
}

/** The pen: a dark barrel and a gold nib, from the poet's cuff down to the line he is writing. */
function Pen({ from, to }: { from: [number, number]; to: [number, number] }) {
  const [x1, y1] = from;
  const [x2, y2] = to;
  const nx = x1 + (x2 - x1) * 0.72;
  const ny = y1 + (y2 - y1) * 0.72;
  return (
    <g>
      <line
        x1={x1}
        y1={y1}
        x2={nx}
        y2={ny}
        stroke={palette.inkblack}
        strokeWidth={5}
        strokeLinecap="round"
      />
      <line
        x1={x1 + (x2 - x1) * 0.2}
        y1={y1 + (y2 - y1) * 0.2}
        x2={x1 + (x2 - x1) * 0.28}
        y2={y1 + (y2 - y1) * 0.28}
        stroke={palette.spotgold}
        strokeWidth={5}
      />
      <line
        x1={nx}
        y1={ny}
        x2={x2}
        y2={y2}
        stroke={palette.spotgold}
        strokeWidth={2.6}
        strokeLinecap="round"
      />
    </g>
  );
}

// ── LedgerPair — the card beside the board's page, line for line ────────────
// Two ruled pages: the PromptCard's, typed, and the board's, an accounts page
// with its column rule. A row is one fact, written on both. A row marked `at`
// starts out of place on each page and settles into the same order; a row
// marked `agree` is underlined in signalflare the moment it does. The pages
// are only as tall as their rows. `big` is the phone's type; `stacked` sets
// the board's page under the card's where there is no room beside it.
interface LedgerRow {
  card: string;
  boardKey: string;
  board: string;
  at?: number;
  agree?: boolean;
}

function LedgerPair({
  x,
  y,
  rows,
  enter,
  cardW,
  boardW,
  big = false,
  stacked = false,
}: {
  x: number;
  y: number;
  rows: LedgerRow[];
  enter?: number;
  cardW: number;
  boardW: number;
  big?: boolean;
  stacked?: boolean;
}) {
  const D = big
    ? {
        size: 16,
        head: 14,
        headY: 26,
        rule: 38,
        top: 66,
        pitch: 38,
        under: 10,
        key: 74,
        pad: 12,
        foot: 14,
      }
    : {
        size: 10.5,
        head: 12,
        headY: 22,
        rule: 32,
        top: 52,
        pitch: 26,
        under: 7,
        key: 53,
        pad: 10,
        foot: 2,
      };
  const gap = 8;
  const h = D.top + (rows.length - 1) * D.pitch + D.under + D.foot + 6;
  const cardX = x;
  const cardY = y;
  const boardX = stacked ? x : x + cardW + gap;
  const boardY = stacked ? y + h + gap : y;
  const page = (px: number, py: number, w: number, title: string, board: boolean) => (
    <g>
      <rect x={px + 5} y={py + 6} width={w} height={h} fill={palette.inkblack} opacity={0.4} />
      <rect
        x={px}
        y={py}
        width={w}
        height={h}
        fill={palette.paper}
        stroke={palette.paperShade}
        strokeWidth={1}
      />
      <text
        x={px + D.pad}
        y={py + D.headY}
        fontFamily={typed}
        fontSize={D.head}
        fontWeight={700}
        letterSpacing="0.12em"
        fill={palette.brickDeep}
      >
        {title}
      </text>
      <line
        x1={px}
        y1={py + D.rule}
        x2={px + w}
        y2={py + D.rule}
        stroke={palette.brickwarm}
        strokeWidth={1.4}
        opacity={0.75}
      />
      {/* the page's ruling: a line under every row, and on the board's page the account's double column rule */}
      {rows.map((_, i) => (
        <line
          key={i}
          x1={px}
          y1={py + D.top + D.under + i * D.pitch}
          x2={px + w}
          y2={py + D.top + D.under + i * D.pitch}
          stroke={palette.paperShade}
          strokeWidth={1}
        />
      ))}
      {board && (
        <>
          <line
            x1={px + D.key - 3}
            y1={py + D.rule}
            x2={px + D.key - 3}
            y2={py + h}
            stroke={palette.brickwarm}
            strokeWidth={1}
            opacity={0.7}
          />
          <line
            x1={px + D.key}
            y1={py + D.rule}
            x2={px + D.key}
            y2={py + h}
            stroke={palette.brickwarm}
            strokeWidth={1}
            opacity={0.7}
          />
        </>
      )}
    </g>
  );
  const settle = (at: number | undefined, dy: number): CSSProperties | undefined =>
    at === undefined
      ? undefined
      : ({
          "--dy": `${dy}px`,
          animation: `pb-row-settle 700ms ease-in-out ${at}s backwards`,
        } as CSSProperties);
  return (
    <g
      style={
        enter === undefined
          ? undefined
          : { animation: `pb-fade 500ms ease-out ${enter}s backwards` }
      }
    >
      {page(cardX, cardY, cardW, "THE CARD", false)}
      {page(boardX, boardY, boardW, "THE BOARD", true)}
      {rows.map((r, i) => {
        const dRow = D.top + i * D.pitch;
        // each page's line starts somewhere else: the stagger is 120ms a line
        const at = r.at === undefined ? undefined : r.at + i * 0.12;
        const dy = ((i * 2 + 1) % 3 === 0 ? -1 : 1) * (22 + i * 9);
        return (
          <g key={i}>
            <g style={settle(at, dy)}>
              <text
                x={cardX + D.pad}
                y={cardY + dRow}
                fontFamily={typed}
                fontSize={D.size}
                fill={palette.inkblack}
                xmlSpace="preserve"
              >
                {r.card}
              </text>
            </g>
            <g style={settle(at, -dy)}>
              <text
                x={boardX + D.pad - 2}
                y={boardY + dRow}
                fontFamily={typed}
                fontSize={D.size}
                fill={palette.inkblack}
                xmlSpace="preserve"
              >
                {r.boardKey}
              </text>
              <text
                x={boardX + D.key + 6}
                y={boardY + dRow}
                fontFamily={typed}
                fontSize={D.size}
                fill={palette.inkblack}
                xmlSpace="preserve"
              >
                {r.board}
              </text>
            </g>
            {r.agree && (
              <g
                style={
                  at === undefined
                    ? undefined
                    : { animation: `pb-fade 400ms ease-out ${at + 0.8}s backwards` }
                }
              >
                <line
                  x1={cardX + 6}
                  y1={cardY + dRow + D.under}
                  x2={cardX + cardW - 6}
                  y2={cardY + dRow + D.under}
                  stroke={palette.signalflare}
                  strokeWidth={2.6}
                  strokeLinecap="round"
                />
                <line
                  x1={boardX + 6}
                  y1={boardY + dRow + D.under}
                  x2={boardX + boardW - 6}
                  y2={boardY + dRow + D.under}
                  stroke={palette.signalflare}
                  strokeWidth={2.6}
                  strokeLinecap="round"
                />
                {/* the one mark that crosses the gutter: the same line, on both pages */}
                {!stacked && (
                  <line
                    x1={cardX + cardW - 6}
                    y1={cardY + dRow + D.under}
                    x2={boardX + 6}
                    y2={boardY + dRow + D.under}
                    stroke={palette.signalflare}
                    strokeWidth={2.6}
                    strokeDasharray="2 4"
                    strokeLinecap="round"
                  />
                )}
              </g>
            )}
          </g>
        );
      })}
    </g>
  );
}

// What the two ledgers hold. The first row was there since NewPrompt made the card (slide 3); the pull request writes the second (slide 8); the review adds the rest (slide 10).
const ROW_ITEM: LedgerRow = {
  card: "ADO Link: .../edit/4127",
  boardKey: "4127",
  board: "User Story",
};
const ROW_PR: LedgerRow = {
  card: "PR URL: .../pullrequest/212",
  boardKey: "State",
  board: "Code Review",
};
const ROW_THREAD: LedgerRow = {
  card: "Comment: add a login test",
  boardKey: "Thread",
  board: "add a login test",
};
const ROW_REPLY: LedgerRow = {
  card: "Reply: Fixed. Tests green.",
  boardKey: "Reply",
  board: "Fixed. Tests green.",
};

// Where the deed lands: in the beam, under the lamp, over the poet's raised head. Slide 7's pulse waits at the same point.
const DEED_AT: [number, number] = [1000, 266];
// Where the ledgers hang on the wall at the stage's left, clear of the beam: low where the verse hung (slide 8), high where the wall is free (slide 10).
const PAIR_X = 552;
// Where the poem hangs while it is read: on the wall beside him, left of the beam.
const VERSE_AT: [number, number] = [752, 300];

/**
 * The ledgers on the stage's wall. On a phone the pair keeps only the rows that carry the slide's argument,
 * at the phone's type, the board's page under the card's; the desktop's rows and placement do not move.
 */
function StageLedgers({
  y,
  boardW,
  rows,
  phoneRows,
  enter,
}: {
  y: number;
  boardW: number;
  rows: LedgerRow[];
  phoneRows: LedgerRow[];
  enter?: number;
}) {
  const compact = useCompactLayout();
  return compact ? (
    <LedgerPair
      x={PAIR_X + 10}
      y={270}
      cardW={282}
      boardW={282}
      rows={phoneRows}
      enter={enter}
      big
      stacked
    />
  ) : (
    <LedgerPair x={PAIR_X} y={y} cardW={184} boardW={boardW} rows={rows} enter={enter} />
  );
}

/** The deed, landing in the beam. On a phone the ticket is drawn a third larger, so its three lines can be read. */
function Deed({ delay }: { delay: number }) {
  const compact = useCompactLayout();
  return compact ? (
    <g transform={`translate(${DEED_AT[0] + 10} ${DEED_AT[1] - 8}) scale(1.3)`}>
      <AgentActTicket x={0} y={0} delay={delay} />
    </g>
  ) : (
    <AgentActTicket x={DEED_AT[0]} y={DEED_AT[1]} delay={delay} />
  );
}

// The poem the deck follows, and its two lines as words for the verse strips.
const POEM = ["Fix the login, Tuesday bright —", "one card, one prompt, the deed in sight."];
const POEM_WORDS: Word[][] = POEM.map((l) => words(l));

// ▼ Copied from src/decks/the-prompt-poet.tsx — the AgentAct ticket and the point where it lands; only the ticket's three typed lines are this deck's. Same paths, numbers and colours.
// ── AgentAct — the deed, as a ticket in signalflare ─────────────────────────
function AgentActTicket({ x, y, delay = 1.6 }: { x: number; y: number; delay?: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <g style={{ animation: `pb-land ${tempo.act2.beat} ease-out ${delay}s backwards` }}>
        <circle
          cx={0}
          cy={10}
          r={150}
          fill="url(#pb-flare)"
          style={{ animation: "pb-flare 3s ease-in-out infinite" }}
        />
        <rect
          x={-118}
          y={-34}
          width={236}
          height={78}
          fill={palette.paper}
          stroke={palette.signalflare}
          strokeWidth={2.5}
        />
        <path
          d="M -118 -34 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6 l 8 6 l 8 -6"
          fill="none"
          stroke={palette.paperShade}
          strokeWidth={1}
        />
        <text
          x={-100}
          y={-8}
          fontFamily={typed}
          fontSize={13}
          fill={palette.signalflare}
          fontWeight={700}
        >
          PULL REQUEST OPENED
        </text>
        <path
          d="M 72 -18 l 8 8 l 18 -20"
          fill="none"
          stroke={palette.signalflare}
          strokeWidth={3.5}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <text x={-100} y={14} fontFamily={typed} fontSize={13} fill={palette.ink}>
          pull request 212
        </text>
        <text x={-100} y={34} fontFamily={typed} fontSize={13} fill={palette.ink}>
          4127 · Code Review
        </text>
      </g>
    </g>
  );
}

/** The point where the deed will land: HeldBreath's one allowed motion. */
function FlarePoint({ x, y }: { x: number; y: number }) {
  return (
    <Pivot x={x} y={y} style={{ animation: `pb-pulse 2400ms ${tempo.act3.ease} infinite` }}>
      <circle cx={x} cy={y} r={64} fill="url(#pb-flare)" />
      <circle cx={x} cy={y} r={9} fill={palette.signalflare} filter="url(#pb-glow)" />
      <circle cx={x} cy={y} r={4} fill="#fff1c2" />
    </Pivot>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the room, assembled. Same paths, numbers and colours.
// ── The room, assembled ─────────────────────────────────────────────────────
// One floor plan every room slide shares (sheets 1, 4 and 8 of the research):
// the stage against the brick at centre-right, the band at its rear corner,
// the tables in front seen from behind the room. `onStage` is drawn between
// the stage and the smoke; `front` after the tables.
function Room({
  still = false,
  band = "set",
  hands = "none",
  bandOn = true,
  handsPoised = false,
  onStage,
  front,
  table = false,
  tables = true,
  mic = true,
  cone = 1,
}: {
  still?: boolean;
  band?: BandMode;
  hands?: HandMode;
  /** The band is on the wall from slide 3; the opening room's stage is empty. */
  bandOn?: boolean;
  handsPoised?: boolean;
  onStage?: ReactNode;
  front?: ReactNode;
  table?: boolean;
  /** The foreground tables; off for a camera that is on the stage alone. */
  tables?: boolean;
  mic?: boolean;
  cone?: number;
}) {
  return (
    <g>
      <Ceiling />
      <BrickWall />
      <Floor />
      <StringLights still={still} />
      <Bulb x={440} drop={236} still={still} />
      <Bulb x={1180} drop={236} still={still} />
      <StagePlatform mic={mic} />
      {bandOn && <Band x={1200} y={572} mode={band} />}
      {table && <PoetTable x={850} y={556} />}
      <SpotlightCone still={still} opacity={cone} />
      {onStage}
      <GreenSmoke still={still} />
      {/* the room: tables, chairs, the hands */}
      {tables && (
        <>
          <CafeTable x={380} y={760} chess seed={1} />
          <CafeTable x={650} y={822} />
          <CafeTable x={960} y={806} chairs={1} />
          <CafeTable x={1230} y={836} chess seed={3} />
        </>
      )}
      <SnapChorus mode={hands} poised={handsPoised} />
      {front}
      <rect x={-200} y={-100} width={2000} height={1200} fill="url(#pb-vignette)" />
    </g>
  );
}

// ▼ Copied from src/decks/the-prompt-poet.tsx — the windshield at dawn. Same paths, numbers and colours.
// ── The windshield at dawn (slide 12) ───────────────────────────────────────
function Windshield() {
  return (
    <g>
      {/* the sky, brightening; the road; a low skyline */}
      <g style={{ animation: "pb-dawn 6s ease-out both" }}>
        <rect x={0} y={0} width={VW} height={VH} fill="url(#pb-dawn)" />
        <circle
          cx={640}
          cy={596}
          r={120}
          fill={palette.spotgold}
          opacity={0.5}
          filter="url(#pb-soft)"
        />
        <circle cx={640} cy={600} r={46} fill="#fff1c2" />
      </g>
      <path
        d="M -100 600 L 120 598 L 180 560 L 260 566 L 330 540 L 400 556 L 470 536 L 560 560 L 640 548 L 700 566 L 900 566 L 980 540 L 1040 556 L 1120 532 L 1200 560 L 1300 548 L 1400 568 L 1500 556 L 1700 600 L 1700 700 L -100 700 Z"
        fill="#2a1f2a"
      />
      <rect x={-100} y={598} width={1800} height={200} fill="#231c24" />
      <polygon points="560,700 1040,700 1500,900 100,900" fill="#2d2330" />
      <line
        x1={800}
        y1={700}
        x2={800}
        y2={900}
        stroke={palette.spotgold}
        strokeWidth={4}
        strokeDasharray="30 30"
        opacity={0.4}
      />
      {/* the last of the smoke, thinning into the morning */}
      <g filter="url(#pb-smokeblur)" style={{ animation: "pb-thin 8s linear both" }}>
        <path
          d="M 200 200 C 500 150, 700 260, 1000 200 S 1500 150, 1700 210"
          fill="none"
          stroke={palette.smokegreen}
          strokeWidth={26}
          strokeLinecap="round"
        />
      </g>
      {/* the frame: pillars, the header with the visors, the dash */}
      <path d="M 0 0 L 0 900 L 150 900 L 110 0 Z" fill="#1a1410" />
      <path d="M 1600 0 L 1600 900 L 1450 900 L 1490 0 Z" fill="#1a1410" />
      <rect x={0} y={0} width={VW} height={72} fill="#1a1410" />
      {/* the rearview mirror: the coffee house's warm windows small in it */}
      <line x1={690} y1={72} x2={690} y2={100} stroke="#1a1410" strokeWidth={6} />
      <rect
        x={570}
        y={96}
        width={250}
        height={84}
        rx={10}
        fill="#2a2630"
        stroke="#111"
        strokeWidth={4}
      />
      <rect x={578} y={104} width={234} height={68} rx={6} fill="#0d0a12" />
      {/* in it, the street behind: the coffee house's brick front, a door and three windows still warm, the sign's glow */}
      <rect x={606} y={118} width={150} height={54} fill="#3a221b" />
      <rect x={606} y={118} width={150} height={6} fill="#4a2e24" />
      <rect x={616} y={128} width={14} height={16} fill={palette.spotgold} opacity={0.9} />
      <rect x={640} y={128} width={14} height={16} fill={palette.spotgold} opacity={0.75} />
      <rect x={664} y={128} width={14} height={16} fill={palette.brickLit} opacity={0.9} />
      <rect x={706} y={132} width={22} height={40} fill="#f2c45e" opacity={0.85} />
      <rect x={690} y={120} width={54} height={8} fill={palette.signalflare} opacity={0.6} />
      <circle cx={717} cy={150} r={34} fill="url(#pb-pool)" />
      {/* a last faint snap from the room behind */}
      <Pivot x={623} y={136} style={{ animation: "pb-pulse 4s linear infinite" }}>
        <circle cx={623} cy={136} r={2.5} fill="#fff6dc" />
      </Pivot>
      {/* the smoke, thinning over its roof */}
      <path
        d="M 600 116 C 640 100, 680 124, 720 108 S 780 100, 810 112"
        fill="none"
        stroke={palette.smokegreen}
        strokeWidth={5}
        opacity={0.5}
        filter="url(#pb-glow)"
        style={{ animation: "pb-thin 8s linear both" }}
      />
      {/* the driver's visor, folded up; the passenger's, down, a long flap of dark fabric with its mirror */}
      <rect x={160} y={72} width={360} height={34} rx={6} fill="#2b221c" />
      <path d="M 1060 72 L 1600 72 L 1600 560 L 1110 530 Z" fill="#2b221c" />
      <path
        d="M 1078 90 L 1584 90 L 1584 542 L 1126 514 Z"
        fill="none"
        stroke="#4a3a30"
        strokeWidth={3}
        strokeDasharray="6 8"
      />
      <rect
        x={1130}
        y={150}
        width={190}
        height={104}
        rx={8}
        fill="#1c1a22"
        stroke="#4a3a30"
        strokeWidth={3}
      />
      <rect x={1140} y={160} width={170} height={84} rx={4} fill="#262330" />
      {/* the dash and the wheel */}
      <path d="M -100 760 Q 800 700 1700 760 L 1700 900 L -100 900 Z" fill="#1f1713" />
      <path d="M -100 760 Q 800 700 1700 760" fill="none" stroke="#3a2d26" strokeWidth={6} />
      {[720, 800, 880].map((cx, i) => (
        <g key={cx}>
          <circle
            cx={cx}
            cy={800}
            r={i === 1 ? 30 : 22}
            fill="#0f0c0e"
            stroke="#4a3a30"
            strokeWidth={3}
          />
          <line
            x1={cx}
            y1={800}
            x2={cx + 10}
            y2={800 - (i === 1 ? 20 : 14)}
            stroke={palette.signalflare}
            strokeWidth={2}
            opacity={0.7}
          />
        </g>
      ))}
    </g>
  );
}

/** The poem on the wall beside him (slides 6 to 8). On a phone it is set further in and a little higher, at the same type, so both strips keep a margin from the frame's left edge and clear his head. */
function StageVerse({ mode, start, fadeAt }: { mode: VerseMode; start: number; fadeAt?: number }) {
  const compact = useCompactLayout();
  return compact ? (
    <VerseLine
      x={VERSE_AT[0] + 26}
      y={VERSE_AT[1] - 20}
      lines={POEM_WORDS}
      size={16}
      mode={mode}
      start={start}
      lineGap={40}
      fadeAt={fadeAt}
    />
  ) : (
    <VerseLine
      x={VERSE_AT[0]}
      y={VERSE_AT[1]}
      lines={POEM_WORDS}
      size={16}
      mode={mode}
      start={start}
      lineGap={40}
      fadeAt={fadeAt}
    />
  );
}

// ── The poet's table from above (slide 3) ───────────────────────────────────
// The one change of camera in the deck: straight down onto the table the Room
// draws at the stage's left, because a card is a page and a page is whole only
// from above. The same warm top and darker rim as that table, the stage's
// boards under it, the lamp's pool on it.
function TableTop({ children }: { children: ReactNode }) {
  const cx = 800;
  const cy = 530;
  const r = 500;
  return (
    <g>
      <rect x={0} y={0} width={VW} height={VH} fill={palette.wood} />
      {Array.from({ length: 12 }, (_, i) => (
        <line
          key={i}
          x1={0}
          y1={34 + i * 78}
          x2={VW}
          y2={34 + i * 78}
          stroke={palette.woodDeep}
          strokeWidth={2.5}
          opacity={0.8}
        />
      ))}
      <circle cx={cx + 14} cy={cy + 20} r={r} fill={palette.inkblack} opacity={0.55} />
      <circle cx={cx} cy={cy} r={r} fill={palette.woodLit} />
      <circle cx={cx} cy={cy} r={r - 14} fill="#8a5a33" />
      {/* the grain, running the way the boards do */}
      {Array.from({ length: 11 }, (_, i) => {
        const gy = cy - 440 + i * 88;
        const half = Math.sqrt((r - 14) ** 2 - (gy - cy) ** 2) - 26;
        return (
          <path
            key={i}
            d={`M ${cx - half} ${gy} Q ${cx} ${gy + (i % 2 === 0 ? 9 : -7)} ${cx + half} ${gy}`}
            fill="none"
            stroke={palette.woodLit}
            strokeWidth={2}
            opacity={0.45}
          />
        );
      })}
      <ellipse cx={cx} cy={cy - 40} rx={560} ry={440} fill="url(#pb-pool)" />
      {children}
      <rect x={0} y={0} width={VW} height={VH} fill="url(#pb-vignette)" />
    </g>
  );
}

/** Slide 3's table: the slip the card was made from, the card, and the poem settling above it. */
function CardOnTheTable() {
  // On a phone the card keeps its heading and its ADO Link, at a size that can be read there; the template's
  // sections are the desktop's.
  const compact = useCompactLayout();
  const body: CardLine[] = compact
    ? [line("# User Story 4127:"), line("  Fix the login")]
    : [
        line("# User Story 4127: Fix the login"),
        line("## Branch", { gap: 0.7 }),
        line("poet/4127/fix-the-login"),
        line("## Git", { gap: 0.7 }),
        line("Commits:"),
        line("- (pending)"),
        line("## Described Changes", { gap: 0.7 }),
        line("- (TBD)"),
        line("## Acceptance Criteria", { gap: 0.7 }),
        line("- [ ] the login works by Tuesday"),
      ];
  return (
    <>
      {/* the slip the card was made from, its corner under the page */}
      {compact ? (
        <RequestSlip x={482} y={372} rot={-11} w={250} type="story" id="4127" />
      ) : (
        <RequestSlip x={500} y={356} rot={-11} w={250} type="story" id="4127" />
      )}
      {compact ? (
        <PromptCard
          x={836}
          y={560}
          w={600}
          h={400}
          size={26}
          rot={2}
          lines={body}
          footer={[line("ADO Link: .../edit/4127", { at: 2.8 })]}
        />
      ) : (
        <PromptCard
          x={820}
          y={572}
          w={440}
          h={560}
          size={16}
          rot={2}
          lines={body}
          footer={[line("ADO Link: .../_workitems/edit/4127", { at: 2.8 })]}
        />
      )}
      {/* the poem, out of the smoke and into meter above the page */}
      <VerseLine
        x={800}
        y={150}
        lines={POEM_WORDS}
        size={22}
        mode="settle"
        start={0.9}
        lineGap={50}
      />
    </>
  );
}

// ── The page held to the light (slide 11) ───────────────────────────────────
// Two asks, two fates: the wordy ask overstruck the typewriter's way beside
// its poem, and under the pairs the card's two link lines. On the desktop the
// pairs sit in two columns. On a phone the stage is a third the size, so each
// pair stacks and the wordy ask keeps only its first line, at larger type; the
// link lines stay (design note, Mobile Stance). The page, its light and its
// tilt are copied from the first deck's CraftPage.
const STORY_ASK: Seg[][] = [
  [{ t: "Hi! Sorry to bother you, but when", cut: true }],
  [{ t: "you get a chance could you maybe", cut: true }],
  [{ t: "take a look and ", cut: true }, { t: "fix the login" }, { t: "?", cut: true }],
  [{ t: "No rush, though ", cut: true }, { t: "Tuesday" }, { t: " would be", cut: true }],
  [{ t: "great if that works. Thanks!!", cut: true }],
];
const REVIEW_ASK: Seg[][] = [
  [{ t: "So I think this is probably fine", cut: true }],
  [{ t: "now? I had a go at the ", cut: true }, { t: "thread" }, { t: " and", cut: true }],
  [{ t: "it should be ", cut: true }, { t: "fixed" }, { t: ", I believe,", cut: true }],
  [{ t: "and the ", cut: true }, { t: "tests" }, { t: " came back ", cut: true }, { t: "green" }],
  [{ t: "on my machine, fingers crossed.", cut: true }],
];
const REVIEW_POEM = [
  "Thread is fixed, tests are green —",
  "the card now holds what the board has seen.",
];
const LINK_LINES = ["ADO Link: .../_workitems/edit/4127", "PR URL:   .../pullrequest/212"];

function CraftPage() {
  const compact = useCompactLayout();
  const xColor = "#2a2030";
  const L = compact
    ? {
        label: 20,
        ask: 22,
        poem: 24,
        link: 24,
        pitch: 30,
        poemPitch: 38,
        tops: [-290, -62],
        rules: [-104, 126],
        links: 180,
        linkPitch: 42,
      }
    : {
        label: 15,
        ask: 17,
        poem: 18,
        link: 18,
        pitch: 31,
        poemPitch: 34,
        tops: [-292, -50],
        rules: [-84, 164],
        links: 208,
        linkPitch: 34,
      };
  const pair = (title: string, lines: Seg[][], verse: string[], top: number, strikeAt: number) => {
    const asks = compact ? lines.slice(0, 1) : lines;
    return (
      <>
        <TypedLine
          x={compact ? -410 : -400}
          y={top}
          size={L.label}
          segs={[{ t: title }]}
          color={palette.ink}
        />
        {asks.map((segs, i) => (
          <TypedLine
            key={i}
            x={-410}
            y={top + 46 + i * L.pitch}
            size={L.ask}
            segs={segs}
            color={palette.ink}
            xColor={xColor}
            xDelay={strikeAt + i * 0.35}
          />
        ))}
        {verse.map((v, i) =>
          compact ? (
            <TypedLine
              key={`v${i}`}
              x={-390}
              y={top + 100 + i * L.poemPitch}
              size={L.poem}
              segs={[{ t: v }]}
              color={palette.ink}
            />
          ) : (
            <TypedLine
              key={`v${i}`}
              x={-52}
              y={top + 92 + i * L.poemPitch}
              size={L.poem}
              segs={[{ t: v }]}
              color={palette.ink}
            />
          ),
        )}
      </>
    );
  };
  return (
    <g style={{ animation: `pb-settle ${tempo.act4.warm} ${tempo.act4.ease} both` }}>
      <g transform="translate(800 480) rotate(-2.5)">
        <rect
          x={-450}
          y={-340}
          width={900}
          height={680}
          fill={palette.inkblack}
          opacity={0.45}
          transform="translate(10 12)"
        />
        <rect x={-450} y={-340} width={900} height={680} fill={palette.paper} />
        <rect x={-450} y={-340} width={900} height={680} fill="url(#pb-through)" />
        {/* pair one: the work item */}
        {pair("i. the work item", STORY_ASK, POEM, L.tops[0], 1.0)}
        <TypedLine
          x={-400}
          y={L.rules[0]}
          size={15}
          segs={[{ t: "-".repeat(70) }]}
          color={palette.paperShade}
        />
        {/* pair two: the review */}
        {pair("ii. the review", REVIEW_ASK, REVIEW_POEM, L.tops[1], 3.4)}
        {/* the card's foot: the two link lines, the proof the poem and the card agree */}
        <TypedLine
          x={-400}
          y={L.rules[1]}
          size={15}
          segs={[{ t: "-".repeat(70) }]}
          color={palette.paperShade}
        />
        {LINK_LINES.map((t, i) => (
          <TypedLine
            key={i}
            x={-410}
            y={L.links + i * L.linkPitch}
            size={L.link}
            segs={[{ t }]}
            color={palette.inkblack}
          />
        ))}
      </g>
    </g>
  );
}

// ── Slide eyebrows ──────────────────────────────────────────────────────────
const ACT = {
  I: "Act I · The Room",
  II: "Act II · The Poem",
  III: "Act III · The Held Breath",
  IV: "Act IV · The Morning",
} as const;

// One camera for the stage from the reading to the reply (slides 6, 7, 8 and 10): the table, the poet, the band and the wall above them.
const STAGE_CAM = { x: 950, y: 500, zoom: 1.2 } as const;

// ── Deck definition ─────────────────────────────────────────────────────────
export const thePromptPoetWorksTheBoardDeck: Deck = {
  id: "the-prompt-poet-works-the-board",
  project: "toolkit",
  // Complete: passed UAT, the QA loop, the content review, the bake and the listen to
  // the baked narration. Built in this studio and shipped to the Toolkit whole.
  state: DeckState.Complete,
  title: "The Prompt Poet Works the Board",
  summary:
    "The basement coffee house is back, but the slips on the poet's table are no longer pizza orders — they are Azure DevOps work items, and the room is a connected space in the Toolkit. One card, one prompt: the poet writes the poem on the card, the card carries every detail the pull request needs, and the poem only counts when it rhymes with the card. This is the First Run Experience for prompt engineering in ADO — walk in, order a prompt, watch it become a pull request.",
  tags: ["product", "toolkit", "azure-devops", "prompting", "poetry"],
  slides: (): Slide[] => [
    makeSlide({
      id: "the-basement-opens",
      title: "The Basement Opens",
      eyebrow: <>Slide 1 · {ACT.I}</>,
      lead: "The same basement coffee house, low and warm. Brick walls, wood tables, chessboards frozen mid-game — and now the slips on the poet's table are work items, and the room is a connected space.",
      content: (
        <Stage>
          <Scene>
            <g style={{ animation: `pb-settle ${tempo.act1.slow} ${tempo.act1.ease} both` }}>
              <Camera>
                {/* the empty stage, and on the poet's table a neat stack of slips, waiting */}
                <Room hands="none" bandOn={false} table onStage={<SlipStack items={[0, 1, 2]} />} />
              </Camera>
            </g>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Let the smoke drift a full loop before the next slide.</Beat>
          <Say>
            The room is an Azure DevOps Space in the Toolkit. You walk in, you connect it to your
            Azure DevOps organisation, and the room is where the prompting happens — before any card
            moves.
          </Say>
          <Context>
            Establish the room, the palette, and the offering — the ADO connected space is the
            product, and the basement is how a stranger first meets it.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-slip-arrives",
      title: "The Slip Arrives",
      eyebrow: <>Slide 2 · {ACT.I}</>,
      lead: "A slip drifts down onto the poet's table: a user story, a bug. In ADO, the work is laser focused on the code and requirements — you work the story or the bug and move the card. So the slip arrives first, and the thinking happens before the moving.",
      content: (
        <Stage>
          <Scene>
            <g style={{ animation: `pb-settle ${tempo.act1.slow} ${tempo.act1.ease} both` }}>
              <Camera x={1000} y={496} zoom={1.5}>
                <Room
                  table
                  tables={false}
                  onStage={
                    <>
                      {/* he reaches the page out over the table as the slip comes down onto the stack: the card starts from the slip */}
                      <Poet pose="carrying" x={980} y={614} scale={1} flip breathe />
                      <SlipStack items={[0, 1, 2, 3]} fall={1} start={1.3} />
                    </>
                  }
                />
              </Camera>
            </g>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Let the slip land before continuing.</Beat>
          <Say>
            A work item arrives as a slip. NewPrompt scaffolds a card from it — the card is born
            from the slip, not beside it.
          </Say>
          <Context>
            The slip is the work item, and the card starts from it — the workflow begins with the
            board&apos;s ask, not with a blank page.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-card",
      title: "The Card",
      eyebrow: <>Slide 3 · {ACT.I}</>,
      lead: "One card, one prompt. The card is the record — not the chat, not memory. All context for the pull request lives in the card, and the card keeps what the chat forgets.",
      content: (
        <Stage>
          <Scene>
            <g style={{ animation: `pb-settle ${tempo.act1.slow} ${tempo.act1.ease} both` }}>
              <TableTop>
                <GreenSmoke />
                <CardOnTheTable />
              </TableTop>
            </g>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Hold on the typed page.</Beat>
          <Say>
            A work item has one prompt file at a time, and that file is the record. The diagnosis,
            the decision, the commits — the card holds them, and the pull request&apos;s description
            is written from the card.
          </Say>
          <Context>
            The card is the engineer&apos;s record — 1 card, 1 prompt, all context at card level.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-band-set",
      title: "The Band, Set",
      eyebrow: <>Slide 4 · {ACT.II}</>,
      lead: "Back corner of the stage: a surfer, an alien, and a robot with a trumpet. The examples, the constraints, the voice you want back — set them before the poem, so the ask can be short.",
      content: (
        <Stage>
          <Scene>
            <Camera x={1130} y={580} zoom={1.6}>
              {/* the trio against the brick, the trumpet in the gold, the hands poised below; the set leans in, once */}
              <Room band="lean" hands="poised" handsPoised />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Let the trumpet catch the light.</Beat>
          <Say>
            Set the band before the poem: the examples, the constraints, the voice you want back.
            The card holds them, so the prompt itself stays short.
          </Say>
          <Context>
            The band is the prompt&apos;s scaffolding — examples, constraints, voice — written into
            the card before the ask, so the ask can be short.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "cut-it-twice",
      title: "Cut It Twice",
      eyebrow: <>Slide 5 · {ACT.II}</>,
      lead: "The poet reads the slip, then cuts. Then cuts again. What survives is the poem — fewer words, sharper edges — and the card keeps the cuts and the reason each one was made.",
      content: (
        <Stage>
          <Scene>
            <Camera x={960} y={470} zoom={1.45}>
              <Room
                table
                tables={false}
                onStage={
                  <>
                    {/* the draft in the air: the first cut takes the manners, the second the hedging, and the survivors lock */}
                    <VerseLine
                      x={1000}
                      y={262}
                      size={21}
                      lineGap={42}
                      mode="shed"
                      start={0.3}
                      lines={[
                        words("could you please maybe take a look and fix", {
                          could: 1,
                          you: 1,
                          please: 1,
                          maybe: 1,
                          take: 2,
                          a: 2,
                          look: 2,
                          and: 2,
                        }),
                        words("the login thing, ideally by Tuesday or so,", {
                          "thing,": 1,
                          ideally: 2,
                          by: 2,
                          or: 2,
                          "so,": 2,
                        }),
                        words("if that works for everyone, thanks so much", {
                          if: 1,
                          that: 1,
                          works: 1,
                          for: 1,
                          "everyone,": 1,
                          thanks: 1,
                          so: 1,
                          much: 1,
                        }),
                      ]}
                      poem={POEM}
                    />
                    {/* cross-legged on the stage boards, the card in the typewriter keeping every cut, the slip folded small beside it */}
                    <Poet
                      pose="typing"
                      x={980}
                      y={614}
                      scale={1.05}
                      typing
                      breathe
                      pageLines={<CardInTypewriter />}
                    />
                    <RequestSlip x={900} y={606} rot={-6} w={40} type="story" id="4127" />
                    <SlipStack items={[0, 1, 2]} />
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Hold on the final short line.</Beat>
          <Say>
            A prompt earns its keep by what it leaves out. The draft is where the thinking happens —
            the card keeps the draft, the cuts, and why each cut was made, so the next reader can
            follow the reasoning.
          </Say>
          <Context>
            Crystallization on stage — order emerging from the wordy draft, and the card recording
            the reasoning, not just the result.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "read-aloud",
      title: "Read Aloud",
      eyebrow: <>Slide 6 · {ACT.II}</>,
      lead: "He reads the poem to the room, against the card. If a detail in the poem disagrees with a detail on the card, the poem is not finished. Rhyme is agreement, and the card is what it has to agree with.",
      content: (
        <Stage>
          <Scene>
            <Camera {...STAGE_CAM}>
              <Room
                table
                hands="raised"
                onStage={
                  <>
                    <SlipStack items={[0, 1, 2]} />
                    {/* the poem hangs in the air before him, a word at a time, as spoken; the card is the page in his hand, in the same light */}
                    <StageVerse mode="hang" start={1.2} />
                    <Poet pose="standing" x={985} y={612} scale={1} flip breathe />
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>A breath before the reading begins.</Beat>
          <Say>
            Read it aloud against the card. If a detail in the poem disagrees with a detail on the
            card, the poem is not finished — rhyme is agreement, and the card is the thing it has to
            agree with.
          </Say>
          <Context>
            The read-aloud test, with the card as the judge — the human ear as the first eval, the
            card as the second.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-held-breath",
      title: "The Held Breath",
      eyebrow: <>Slide 7 · {ACT.III}</>,
      lead: "The poem is spoken. The room holds its breath. Beside him, the agent is deciding — and the card waits, untouched, because NewPrompt never overwrites a card being worked on.",
      content: (
        <Stage>
          <Scene>
            <Camera {...STAGE_CAM}>
              {/* everything at rest: the smoke mid-curl, the cone held, every slip where it lay, the band's hands off their instruments, the page lowered; one pulse, in the beam over him, and his head is up to it */}
              <Room
                still
                table
                band="rest"
                hands="rest"
                onStage={
                  <>
                    <SlipStack items={[0, 1, 2, 4]} />
                    <StageVerse mode="hang" start={-9} />
                    <Poet pose="listening" x={985} y={612} scale={1} flip />
                    <FlarePoint x={DEED_AT[0]} y={DEED_AT[1]} />
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Hold three full seconds — the stillness is the slide.</Beat>
          <Say>
            The pause is the test. A good prompt makes the outcome feel inevitable before it arrives
            — and while it waits, the card is protected: NewPrompt never overwrites a card being
            worked on.
          </Say>
          <Context>
            Equilibrium at its peak — the balance point before the change, and NewPrompt&apos;s rule
            for current/, that it never overwrites a card being worked on: context in the card is
            the product.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "it-ships",
      title: "It Ships",
      eyebrow: <>Slide 8 · {ACT.III}</>,
      lead: "The poem became the pull request. One event posts to both ledgers — the card gets its PR URL line, the work item moves to Code Review, and the board knows.",
      content: (
        <Stage>
          <Scene>
            <Camera {...STAGE_CAM}>
              <Room
                table
                band="note"
                hands="rest"
                onStage={
                  <>
                    <SlipStack items={[0, 1, 2, 4]} />
                    {/* the verse dissolves and the deed lands where the pulse was, in the beam — the deck's one change of nature */}
                    <StageVerse mode="fade" start={-9} fadeAt={1.2} />
                    <Deed delay={1.7} />
                    {/* and where the verse hung, smaller and out of the beam, the two ledgers: the card's page and the board's, settling into one order */}
                    <StageLedgers
                      y={322}
                      boardW={136}
                      enter={2.0}
                      rows={[ROW_ITEM, { ...ROW_PR, at: 2.3, agree: true }]}
                      phoneRows={[{ ...ROW_PR, at: 2.3, agree: true }]}
                    />
                    <Poet pose="standing" x={985} y={612} scale={1} flip />
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>The note, then let the confirmation glow sit.</Beat>
          <Say>
            Verse in, pull request out. NewPR posts to both ledgers at once — the card records the
            PR URL, the work item moves to Code Review, and the board and the card say the same
            thing.
          </Say>
          <Context>
            Transmutation — the change of nature the whole deck was building toward, and the
            two-ledger rule: the card is the engineer&apos;s record, ADO is the organisation&apos;s,
            one event posts to both.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-room-snaps-back",
      title: "The Room Snaps Back",
      eyebrow: <>Slide 9 · {ACT.IV}</>,
      lead: "Fingers snap across the basement — no clapping here. Review comes back as rounds in the card, and the next slip is already on its way down.",
      content: (
        <Stage>
          <Scene>
            <Camera x={850} y={470} zoom={1.08}>
              <Room
                table
                band="look"
                hands="snap"
                onStage={
                  <>
                    <SlipStack items={[0, 1, 2, 4]} />
                    <Poet pose="standing" x={985} y={612} scale={1} flip bow />
                    {/* the next work item, already falling toward the top of the stack */}
                    <g transform={`translate(${stackSpot(4).x} ${stackSpot(4).y})`}>
                      <g style={{ animation: "pb-slip-descend 7s linear both" }}>
                        <RequestSlip
                          x={0}
                          y={0}
                          rot={0}
                          w={SLIP_W}
                          type={WORK_ITEMS[5].type}
                          id={WORK_ITEMS[5].id}
                        />
                      </g>
                    </g>
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Ride the ripple across the room.</Beat>
          <Say>
            Feedback is the loop. GetPRComments appends each review thread to the card —
            append-only, and it can run again without doubling a comment — and the card keeps every
            round, so the room&apos;s snaps are never lost.
          </Say>
          <Context>
            Resonance as eval — the loop closes, the review rounds accumulate in the card, the next
            request begins.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-reply",
      title: "The Reply",
      eyebrow: <>Slide 10 · {ACT.IV}</>,
      lead: "The poet answers the thread, in place. The reply goes to the tracker and into the card's own slot, so the card and the board agree — line for line.",
      content: (
        <Stage>
          <Scene>
            <Camera {...STAGE_CAM}>
              <Room
                table
                hands="rest"
                onStage={
                  <>
                    <SlipStack items={[0, 1, 2, 4, 5]} />
                    {/* the card lies on his table beside the stack; he bends to it, the pen at its Reply slot */}
                    <CardPage x={TABLE[0] + 34} y={TABLE[1] - 5} rot={-8} lines={5} flat />
                    <Poet pose="writing" x={954} y={614} scale={1} breathe />
                    <Pen from={[891, 498]} to={[882, 550]} />
                    {/* beside him the two ledgers: the review's lines already in both, and the reply settling into both at once */}
                    <StageLedgers
                      y={162}
                      boardW={186}
                      rows={[ROW_ITEM, ROW_PR, ROW_THREAD, { ...ROW_REPLY, at: 1.4, agree: true }]}
                      phoneRows={[{ ...ROW_REPLY, at: 1.4, agree: true }]}
                    />
                  </>
                }
              />
            </Camera>
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Let the line settle in both pages before continuing.</Beat>
          <Say>
            Answer the thread in place. ReplyPR posts the reply to the tracker and fills the Reply
            slot in the card — so the card and the board say the same thing, and the agreement is
            written down, not remembered.
          </Say>
          <Context>
            The reply is the agreement made visible — the LedgerPair atom doing its work, the card
            and the board aligned.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-craft-plainly",
      title: "The Craft, Plainly",
      eyebrow: <>Slide 11 · {ACT.IV}</>,
      lead: "The poet's page, held up to the light. Two asks, two fates — the wordy one struck through beside the poem. Below them, the card's two link lines: the ADO Link and the PR URL, the proof the poem and the card agree.",
      content: (
        <Stage>
          <Scene>
            {/* the lamp above, the page in its light (copied from the first deck's slide 11) */}
            <rect x={0} y={0} width={VW} height={VH} fill={palette.inkblack} />
            <polygon points="760,0 840,0 1300,900 300,900" fill="url(#pb-cone)" />
            <line x1={800} y1={0} x2={800} y2={60} stroke="#17110d" strokeWidth={3} />
            <path d="M 770 60 L 830 60 L 842 92 L 758 92 Z" fill="#1a1410" />
            <ellipse cx={800} cy={92} rx={42} ry={8} fill="#ffe7a8" opacity={0.95} />
            <CraftPage />
          </Scene>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Let each pair be read before the Say lands.</Beat>
          <Say>
            The wordy ask buries the order under manners. The poem keeps only what the agent needs —
            the thing, the time, the deed. And the card proves it: the ADO Link ties it to the work
            item, the PR URL ties it to the pull request.
          </Say>
          <Context>
            Field notes — the mechanism as verse pairs on the poet&apos;s page, plus the link lines
            as the proof of agreement; the Say narrates the diff because narration cannot see the
            screen.
          </Context>
        </>
      ),
    }),
    makeSlide({
      id: "the-van-at-dawn",
      title: "The Van at Dawn",
      eyebrow: <>Slide 12 · {ACT.IV}</>,
      lead: "Take the poems — they work, and they rhyme.",
      content: (
        <Stage bg="#1a1410">
          <Scene bg="#1a1410">
            <Windshield />
            {/* a last faint SnapChorus from the room behind: two small gold rings at the coffee house's windows in the mirror */}
            {[
              [647, 134, 0.6],
              [671, 138, 2.1],
            ].map(([sx, sy, d], i) => (
              <Pivot
                key={i}
                x={sx}
                y={sy}
                style={{
                  opacity: 0,
                  animation: `pb-snap 3000ms cubic-bezier(0, 0, 0.2, 1) ${d}s infinite`,
                }}
              >
                <circle
                  cx={sx}
                  cy={sy}
                  r={7}
                  fill="none"
                  stroke={palette.spotgold}
                  strokeWidth={1.2}
                />
              </Pivot>
            ))}
            {/* cards along the top of the dash, lying flat where he left them */}
            <CardPage x={700} y={726} rot={-12} lines={4} flat />
            <CardPage x={930} y={726} rot={9} lines={5} flat />
            <CardPage x={1150} y={730} rot={-5} lines={3} flat />
            {/* the driver's seat, and him asleep in it, turned to the room: the card on his chest, one more
                on his lap, the wheel in front of him (copied from the first deck's slide 12; the turn
                toward the viewer is that deck's cartoon beat, kept on purpose). */}
            <rect x={380} y={600} width={250} height={320} rx={40} fill="#4a3328" />
            <rect
              x={396}
              y={616}
              width={218}
              height={300}
              rx={32}
              fill="none"
              stroke="#5e4334"
              strokeWidth={4}
            />
            <Poet pose="asleep" x={500} y={900} scale={1.5} sleeping />
            <path
              d="M 300 960 A 190 190 0 0 1 680 960"
              fill="none"
              stroke="#141010"
              strokeWidth={26}
            />
            <path
              d="M 300 960 A 190 190 0 0 1 680 960"
              fill="none"
              stroke="#2a2220"
              strokeWidth={4}
            />
            <CardPage x={596} y={856} rot={16} lines={4} />
          </Scene>
          {/* the slip pinned to the visor: the one thing in the scene you can take. It carries the button and no words. */}
          <div
            style={{
              position: "absolute",
              right: "28px",
              top: "60%",
              padding: "14px 14px 12px",
              background: palette.paper,
              transform: "rotate(-4deg)",
              boxShadow: "0 6px 14px rgba(0,0,0,0.45)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <span
              aria-hidden
              style={{
                position: "absolute",
                top: "-7px",
                left: "50%",
                width: "12px",
                height: "12px",
                marginLeft: "-6px",
                borderRadius: "50%",
                background: palette.signalflare,
                boxShadow: "0 2px 3px rgba(0,0,0,0.5)",
              }}
            />
            <GiveawayButton inline />
          </div>
        </Stage>
      ),
      notes: (
        <>
          <Beat>Hold on the dawn light, then end.</Beat>
          <Say>
            The room is closed, but the poems still work. Take them with you — and take the room,
            one card, one prompt.
          </Say>
          <Context>
            Payoff scene — the aftermath of the gift; the button lives inside the scene as the slip
            on the visor.
          </Context>
        </>
      ),
    }),
  ],
};
