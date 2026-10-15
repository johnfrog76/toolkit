import type { CSSProperties, ReactNode } from "react";
import { createMakeSlide } from "../engine/makeSlide";

// Toolkit — shared figures: the series' atom vocabulary, palette, keyframes,
// Stage, copy kit, and the product's surfaces redrawn. Both Toolkit decks
// (Meet the Toolkit, First Shift) import from here and contribute only their
// own stage compositions and Deck export.
// Revised against agentic/product-intro-deck-contract.prompt.md.
//
// Register: Swiss Design. A 12-column grid on the 768×720 stage (64px columns,
// 32px margins), one sans-serif flush left and ragged right, flat colour, depth
// by overlap, and one break per composition — the Done bin is a chute that
// bleeds off the bottom edge. Two choices borrowed from the plates: flat
// vertical bars that start and stop on grid divisions (the Bins), and
// close-tone overlaps whose intersections become their own shapes (the pile
// on slide 1).
//
// The forces are the wasteland's: Flow (an Envelope moves), Crystallization
// (a Postmark presses and a state is true), Accumulation (marks gather, the
// bag fills, the ledger writes itself), Gravity (the one slot a hand uses),
// Inertia (a card travels one way and is never overwritten). They live in the
// drawn office, not in the screens; the screens are evidence.
//
// The product's surfaces are QUOTED, not designed: redrawn in the Seaglass
// theme's own colours with the sample hub's own cards, never recoloured into
// the deck's palette. The five tokens below are the office around them.

/** The product's repo — defined once in the engine (deckLinks), re-exported for the family. */
export { TOOLKIT_REPO_URL } from "../engine/deckLinks";

export const SANS = "'Helvetica Neue', Helvetica, Arial, sans-serif";
export const MONO = "'Cascadia Code', 'Fira Code', 'Consolas', monospace";

export const STAGE_W = 768;
export const STAGE_H = 720;
/** One grid column. Twelve across the stage, 32px margins either side. */
export const COL = 64;
/** The bench top: the horizontal the whole office stands on. */
export const BENCH_Y = 600;

// ── Palette — named for what the colours MEAN in this office ─────────────────
export const C = {
  // paper — the file, the record, the thing that persists
  paper: "#f4f2ec",
  paperDeep: "#e8e5dd",
  // ink — a state made true by writing it; also every silhouette, the goldfish included
  ink: "#1c1c1f",
  inkSoft: "#5b5a60",
  // bin — the places work waits and settles
  bin: "#d6dcda",
  binDeep: "#b7c1be",
  // slot — the one action a person takes; the product's own pink (its logo
  // disc, `logo` in the Seaglass theme), so the host is the colour of the
  // one thing that acts
  slot: "#c4768a",
  // shade — depth and what sits behind: a hard offset, never a blur
  shade: "#c9c6cf",
} as const;

/**
 * The post-it colours — one per card type, the product's own vocabulary
 * (Bug, Task, User Story, Feature, Spike, Meeting), pastel so they sit on
 * paper. The owner's rule: green is a bug, pink a task, yellow a story,
 * purple a feature, light green a spike; blue is the meeting.
 */
export const TYPE = {
  bug: "#b9e0c4",
  task: "#f4c2cc",
  story: "#f6e39b",
  meeting: "#c6dbf2",
  feature: "#d8c7ec",
  spike: "#dcefb7",
} as const;
export type CardType = keyof typeof TYPE;

/** The product's Seaglass theme, quoted from web/src/shell/themeList.ts. */
export const SEAGLASS = {
  page: "#ffffff",
  image: "linear-gradient(210deg, #34c5b845 0%, #5a25c175 100%)",
  brand: "#0F766E",
  logo: "#c4768a",
  text: "#242424",
  muted: "#605e5c",
  card: "rgba(255,255,255,0.62)",
  lane: "rgba(255,255,255,0.34)",
  rule: "rgba(0,0,0,0.08)",
} as const;

/** The six named themes, quoted — page, card, accent and the face's disc. */
export const THEMES = [
  {
    id: "atlantis",
    name: "Atlantis",
    mode: "dark",
    page: "#0e171f",
    image: "linear-gradient(33deg, #0f766e52 0%, #0f548c8a 55%, #1e3a8a70 100%)",
    card: "rgba(255,255,255,0.10)",
    brand: "#0e7490",
    logo: "rgba(34, 211, 238, 0.38)",
  },
  {
    id: "aurora",
    name: "Aurora",
    mode: "dark",
    page: "#1f1f1f",
    image: "linear-gradient(33deg, #5a25c147 0%, #0f548c8a 62%, #10b9812e 100%)",
    card: "rgba(255,255,255,0.10)",
    brand: "#4F46E5",
    logo: "rgba(129, 140, 248, 0.45)",
  },
  {
    id: "basement",
    name: "Basement",
    mode: "dark",
    page: "#19191b",
    image: "none",
    card: "#232326",
    brand: "#b45309",
    logo: "rgba(245, 158, 11, 0.50)",
  },
  {
    id: "seaglass",
    name: "Seaglass",
    mode: "light",
    page: "#ffffff",
    image: "linear-gradient(210deg, #34c5b845 0%, #5a25c175 100%)",
    card: "rgba(255,255,255,0.55)",
    brand: "#0F766E",
    logo: "#c4768a",
  },
  {
    id: "sunny",
    name: "Sunny",
    mode: "light",
    page: "#fffaf0",
    image: "linear-gradient(200deg, #fde68a70 0%, #fdba7452 50%, #fda4af5c 100%)",
    card: "rgba(255,255,255,0.55)",
    brand: "#be123c",
    logo: "#f4a533",
  },
  {
    id: "office",
    name: "Office",
    mode: "light",
    page: "#f3f2f1",
    image: "none",
    card: "#ffffff",
    brand: "#0F766E",
    logo: "#7dd3c8",
  },
] as const;

/**
 * Kit's faces — the product's own, quoted from web/src/shared/faces.ts. A
 * face is a glyph on the disc, rotated: not a setting to get right but a mood
 * to pick. The deck gives Kit one per slide, for the situation he is in.
 */
export const FACES = {
  smile: { glyph: ")", pct: 54, rotate: 90, name: "Classic" },
  curly: { glyph: "{", pct: 81, rotate: 97, name: "Fancy" },
  squiggle: { glyph: "~", pct: 90, rotate: 15, name: "Dizzy" },
  cat: { glyph: "ω", pct: 55, rotate: 0, name: "Kitty" },
  gasp: { glyph: "o", pct: 55, rotate: 0, name: "Shocked" },
  smirk: { glyph: ">", pct: 65, rotate: 90, name: "Sly" },
  wink: { glyph: ";", pct: 54, rotate: 90, name: "Cheeky" },
  flat: { glyph: "—", pct: 65, rotate: 0, name: "Stoic" },
  kiss: { glyph: "3", pct: 55, rotate: 0, name: "Smooch" },
  sharp: { glyph: "V", pct: 55, rotate: 0, name: "Edge" },
  wave: { glyph: "S", pct: 55, rotate: 0, name: "Groovy" },
  square: { glyph: "□", pct: 45, rotate: 0, name: "Boxy" },
} as const;
export type FaceId = keyof typeof FACES;

/** The sample hub's Demo org, as the board draws it. Real cards, real ids. */
export const DEMO_CARDS = {
  active: [
    {
      title: "Can we import a recipe from a photo?",
      kind: "Spike K7M2",
      sprint: "Sprint 9",
      progress: "0/2",
    },
    {
      title: "Extract unit conversion into a pure module",
      kind: "Task 211",
      sprint: "Sprint 8",
      progress: "0/3",
    },
    {
      title: "Scale a recipe by servings",
      kind: "User Story 216",
      sprint: "Sprint 9",
      progress: "0/3",
    },
  ],
  inProgress: [
    {
      title: "Search returns duplicates when tags overlap",
      kind: "Bug 214",
      sprint: "Sprint 8",
      progress: "1/3",
    },
  ],
  codeReview: [
    {
      title: "Paginate the recipe list",
      kind: "User Story 209",
      sprint: "Sprint 8",
      progress: "2/4",
    },
  ],
} as const;

/**
 * Two cards this deck adds to the Demo org so the office holds a life as well
 * as a sprint: a Task with no ticket and a Spike with no ticket, ids by the
 * product's own rule (four characters, no look-alikes). Proposed for
 * samples/hub/demo in the product repo.
 */
export const LIFE_CARDS = {
  dryCleaning: {
    id: "D4RY",
    file: "TaskD4RY-pick-up-the-dry-cleaning.prompt.md",
    title: "Pick up the dry cleaning",
    kind: "Task D4RY",
  },
  goldfish: {
    id: "G8FZ",
    file: "Spike-G8FZ-feed-the-goldfish-from-the-pi-while-away.prompt.md",
    title: "Feed the goldfish from the Pi while away",
    kind: "Spike G8FZ",
  },
} as const;

export const abs = (s: CSSProperties): CSSProperties => ({ position: "absolute", ...s });

// ── Copy-panel kit — one sans, flush left, hierarchy by size and weight ──────

export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        fontFamily: SANS,
        fontSize: "0.72rem",
        fontWeight: 700,
        letterSpacing: "0.14em",
        textTransform: "lowercase",
        color: C.slot,
        margin: "0 0 18px 0",
      }}
    >
      {children}
    </p>
  );
}

export function SlideTitle({ children }: { children: ReactNode }) {
  return (
    <h2
      style={{
        fontFamily: SANS,
        fontSize: "clamp(1.45rem, 6vw, 2.4rem)",
        fontWeight: 700,
        letterSpacing: "-0.015em",
        lineHeight: "1.15em",
        color: "#f4f2ec",
        margin: "0 0 20px 0",
        whiteSpace: "pre-line",
      }}
    >
      {children}
    </h2>
  );
}

export function Lead({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        fontFamily: SANS,
        fontSize: "1.15rem",
        lineHeight: 1.6,
        color: "#b9b7bf",
        margin: "0 0 24px 0",
        whiteSpace: "pre-line",
      }}
    >
      {children}
    </p>
  );
}

export function CopyPanel({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        height: "100%",
        padding: "40px 80px 40px 48px",
      }}
    >
      {children}
    </div>
  );
}

export const makeSlide = createMakeSlide({ CopyPanel, Eyebrow, SlideTitle, Lead });

// ── Keyframes — shared by every Stage; a deck adds its own choreography ──────
// A Postmark's press is 370ms in every act (250ms press + 120ms settle): the
// mechanism does not speed up or slow down, so neither does the stamp.
export function TKKeyframes() {
  return (
    <style>{`
      @keyframes tk-window-in { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
      @keyframes tk-press { 0% { transform: scale(1.7) rotate(-12deg); opacity: 0; } 68% { transform: scale(0.94) rotate(-12deg); opacity: 1; } 100% { transform: scale(1) rotate(-12deg); opacity: 1; } }
      @keyframes tk-blink { 0%, 93%, 100% { transform: scaleY(1); } 95.5%, 97% { transform: scaleY(0.12); } }
      @keyframes tk-nod { 0%, 100% { transform: rotate(0deg); } 50% { transform: rotate(7deg); } }
      @keyframes tk-breathe { 0%, 100% { transform: scaleX(1); } 50% { transform: scaleX(1.14); } }
      @keyframes tk-inkin { from { width: 0; } to { width: 100%; } }
      @keyframes tk-type { from { width: 0; } to { width: 100%; } }
      @keyframes tk-cursor { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0; } }
      @keyframes tk-land { from { opacity: 0; transform: translate(-36px, -40px); } to { opacity: 1; transform: none; } }
      @keyframes tk-fade-in { from { opacity: 0; } to { opacity: 1; } }
      @keyframes tk-rise { from { opacity: 0; transform: translateY(26px); } to { opacity: 1; transform: none; } }
      @keyframes tk-from-right { from { opacity: 0; transform: translateX(60px); } to { opacity: 1; transform: none; } }
      @keyframes tk-wave { 0%, 100% { transform: rotate(-8deg); } 50% { transform: rotate(22deg); } }
      @keyframes tk-point { from { transform: scaleX(0.2); } to { transform: scaleX(1); } }
      @keyframes tk-swim { 0%, 100% { transform: translateX(0) scaleX(1); } 45% { transform: translateX(18px) scaleX(1); } 50% { transform: translateX(18px) scaleX(-1); } 95% { transform: translateX(0) scaleX(-1); } }
      @keyframes tk-leaf { 0%, 100% { transform: rotate(-2deg); } 50% { transform: rotate(2deg); } }
      @keyframes tk-puff-up { 0% { transform: translateY(0); opacity: 0.9; } 100% { transform: translateY(-12px); opacity: 0; } }
      @keyframes tk-spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      @keyframes tk-flake { 0% { transform: translateY(-14px); opacity: 0; } 30% { opacity: 1; } 100% { transform: translateY(10px); opacity: 0; } }
    `}</style>
  );
}

// ── Stage — paper, the grid underneath, nothing drawn on it ─────────────────
export function Stage({ children, bg = C.paper }: { children: ReactNode; bg?: string }) {
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        background: bg,
        fontFamily: SANS,
      }}
    >
      <TKKeyframes />
      {children}
    </div>
  );
}

// ── Atom: Bench — the hub, the folder everything sits in. Never moves. ───────
export function Bench({ label = "toolkit-hub", y = BENCH_Y }: { label?: string; y?: number }) {
  return (
    <>
      <div style={abs({ left: 0, right: 0, top: `${y}px`, bottom: 0, background: C.paperDeep })} />
      <div style={abs({ left: 0, right: 0, top: `${y}px`, height: "4px", background: C.ink })} />
      {label && (
        <div
          style={abs({
            left: "32px",
            top: `${y + 14}px`,
            fontSize: "11px",
            letterSpacing: "0.08em",
            color: C.inkSoft,
            fontFamily: MONO,
          })}
        >
          {label}
        </div>
      )}
    </>
  );
}

// ── Atom: Kit — the host. The logo redrawn as a face: the disc, the two o's
// as eyes, and a mouth that is one of the product's own twelve faces — a
// glyph, rotated, exactly as the web nav draws it. He turns, nods, blinks,
// points, and changes face with the situation.
export function Kit({
  x,
  y,
  size = 96,
  face = "smile",
  look = "reader",
  point,
  nod,
  wave,
  still = false,
  delay = 0,
  disc = C.slot,
}: {
  x: string | number;
  y: string | number;
  size?: number;
  face?: FaceId;
  /** The disc's colour: `slot` pink by contract; a theme's own logo colour when he stands in one. */
  disc?: string;
  /** Where the eyes look. */
  look?: "reader" | "left" | "right";
  /** An ink bar out of the disc, toward what the Say line names. */
  point?: "left" | "right";
  /** A deck-supplied nod cycle (a CSS animation), or true for one 200ms nod on enter. */
  nod?: boolean | string;
  wave?: boolean;
  /** Held frame: no blink, nothing moves. */
  still?: boolean;
  delay?: number;
}) {
  const dx = look === "left" ? -4 : look === "right" ? 4 : 0;
  const f = FACES[face];
  const nodAnim =
    typeof nod === "string" ? nod : nod ? `tk-nod 0.2s ease-in-out ${delay + 0.5}s 1` : undefined;
  // the product sets the mouth at pct% of a 32px wordmark inside a 1.4em disc;
  // scaled to this 92-unit disc that is 0.71 × pct
  const mouthSize = 92 * (f.pct / 100) * 0.71;
  return (
    <div
      style={abs({
        left: typeof x === "number" ? `${x}px` : x,
        top: typeof y === "number" ? `${y}px` : y,
        width: `${size}px`,
        height: `${size}px`,
      })}
    >
      {/* nod on the wrapper, size on the inner — an animation that owns
          `transform` would discard any static transform on the same node */}
      <div
        style={{ width: "100%", height: "100%", animation: nodAnim, transformOrigin: "50% 80%" }}
      >
        <svg
          viewBox="0 0 100 100"
          width={size}
          height={size}
          style={{ display: "block", overflow: "visible" }}
          aria-hidden
        >
          <circle cx="50" cy="50" r="46" fill={disc} />
          <g
            style={{
              transformBox: "fill-box",
              transformOrigin: "center",
              animation: still ? undefined : `tk-blink 7.4s linear ${delay + 1.2}s infinite`,
            }}
          >
            <circle cx={36 + dx} cy="44" r="11" fill="none" stroke={C.ink} strokeWidth="8" />
            <circle cx={64 + dx} cy="44" r="11" fill="none" stroke={C.ink} strokeWidth="8" />
          </g>
          <text
            x="50"
            y="70"
            textAnchor="middle"
            dominantBaseline="central"
            fontFamily="'Segoe UI', system-ui, -apple-system, sans-serif"
            fontSize={mouthSize}
            fill={C.ink}
            transform={`rotate(${f.rotate} 50 70)`}
          >
            {f.glyph}
          </text>
          {point === "right" && (
            <rect
              x="92"
              y="47"
              width="30"
              height="7"
              fill={C.ink}
              style={{
                transformOrigin: "92px 50px",
                animation: `tk-point 0.4s ease-out ${delay + 0.6}s backwards`,
              }}
            />
          )}
          {point === "left" && (
            <rect
              x="-22"
              y="47"
              width="30"
              height="7"
              fill={C.ink}
              style={{
                transformOrigin: "8px 50px",
                animation: `tk-point 0.4s ease-out ${delay + 0.6}s backwards`,
              }}
            />
          )}
          {wave && (
            <rect
              x="90"
              y="18"
              width="7"
              height="34"
              rx="2"
              fill={C.ink}
              style={{
                transformOrigin: "93px 50px",
                animation: "tk-wave 1.1s ease-in-out infinite",
              }}
            />
          )}
        </svg>
      </div>
    </div>
  );
}

// ── Atom: Postmark — a token written into the file; the moment a state
// becomes true. Presses down, settles, and never fades.
/** The stamps' inks — the colours a commit, a pull request and a close wear on a board. */
export const STAMP = {
  commit: "#2f9e5b",
  pr: "#6f5bd6",
  closed: C.ink,
} as const;
export type StampKind = keyof typeof STAMP;

export function Postmark({
  text,
  kind,
  x,
  y,
  size = 36,
  delay,
  animation,
}: {
  text?: string;
  kind?: StampKind;
  x?: string | number;
  y?: string | number;
  size?: number;
  delay?: number;
  animation?: string;
}) {
  const ink = kind ? STAMP[kind] : C.ink;
  const glyph =
    kind === "commit" ? (
      // a commit: the green check in a circle
      <svg viewBox="0 0 24 24" width={size * 0.56} height={size * 0.56} aria-hidden>
        <path
          d="M5 12.5 L10 17 L19 7"
          fill="none"
          stroke={ink}
          strokeWidth="3.2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    ) : kind === "pr" ? (
      // a pull request: the merge glyph
      <svg viewBox="0 0 24 24" width={size * 0.56} height={size * 0.56} aria-hidden>
        <circle cx="6" cy="5" r="2.6" fill="none" stroke={ink} strokeWidth="2.4" />
        <circle cx="6" cy="19" r="2.6" fill="none" stroke={ink} strokeWidth="2.4" />
        <circle cx="18" cy="19" r="2.6" fill="none" stroke={ink} strokeWidth="2.4" />
        <path
          d="M6 7.6 V16.4 M18 16.4 V13 C18 9 13 9 9.5 9"
          fill="none"
          stroke={ink}
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      </svg>
    ) : kind === "closed" ? (
      // closed: the check, inked and heavier
      <svg viewBox="0 0 24 24" width={size * 0.56} height={size * 0.56} aria-hidden>
        <path
          d="M4 12.5 L10 18 L20 6"
          fill="none"
          stroke={ink}
          strokeWidth="4"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    ) : (
      text
    );
  const style: CSSProperties = {
    // a rubber stamp: paper under it so it never sinks into the envelope, a
    // double ring, the ink at stamp density
    width: `${size}px`,
    height: `${size}px`,
    borderRadius: "50%",
    border: `2.5px solid ${ink}`,
    color: ink,
    background: C.paper,
    boxShadow: `inset 0 0 0 2px ${C.paper}, inset 0 0 0 3.5px ${ink}, 2px 2px 0 ${C.shade}`,
    fontFamily: SANS,
    fontSize: `${Math.max(7.5, size * 0.21)}px`,
    fontWeight: 800,
    letterSpacing: "0.06em",
    textTransform: "uppercase",
    whiteSpace: "nowrap",
    opacity: 0.92,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    textAlign: "center",
    lineHeight: 1,
    boxSizing: "border-box",
    transform: "rotate(-12deg)",
    animation:
      animation ??
      (delay != null
        ? `tk-press 0.37s cubic-bezier(0.2, 0.8, 0.2, 1) ${delay}s backwards`
        : undefined),
  };
  if (x != null || y != null) {
    return (
      <div
        style={abs({
          left: typeof x === "number" ? `${x}px` : x,
          top: typeof y === "number" ? `${y}px` : y,
          ...style,
        })}
      >
        {glyph}
      </div>
    );
  }
  return <div style={style}>{glyph}</div>;
}

// ── Atom: PostIt — a reminder, an invite, a due date; or, stuck to an
// Envelope's corner, the card's type. Pastel, a curl at one corner, a
// degree or two off square. The analog office.
export function PostIt({
  x,
  y,
  w = 190,
  text,
  sub,
  type,
  tilt = -2,
  delay,
  animation,
  skeleton = 0,
}: {
  x?: number;
  y?: number;
  w?: number;
  text?: ReactNode;
  sub?: string;
  type?: CardType;
  tilt?: number;
  delay?: number;
  animation?: string;
  /** Skeleton content: this many translucent bars, the colour showing through. */
  skeleton?: number;
}) {
  const fill = type ? TYPE[type] : C.paper;
  const h = text ? undefined : w;
  const positioned = x != null || y != null;
  return (
    <div
      style={{
        ...(positioned ? abs({ left: `${x ?? 0}px`, top: `${y ?? 0}px` }) : {}),
        width: `${w}px`,
        height: h != null ? `${h}px` : undefined,
        animation:
          animation ??
          (delay != null
            ? `tk-land 0.18s cubic-bezier(0.34, 1.56, 0.64, 1) ${delay}s backwards`
            : undefined),
      }}
    >
      {/* tilt on the inner, entrance on the outer — the two-div split */}
      <div
        style={{
          position: "relative",
          transform: `rotate(${tilt}deg)`,
          transformOrigin: "50% 50%",
          background: fill,
          boxShadow: `3px 3px 0 ${C.shade}`,
          padding: text ? "10px 12px 14px 12px" : 0,
          boxSizing: "border-box",
          width: "100%",
          height: h != null ? `${h}px` : undefined,
        }}
      >
        {text && <div style={{ fontSize: "12px", color: C.ink, lineHeight: 1.25 }}>{text}</div>}
        {sub && (
          <div
            style={{
              fontSize: "9px",
              color: C.inkSoft,
              marginTop: "4px",
              textTransform: "lowercase",
              letterSpacing: "0.06em",
            }}
          >
            {sub}
          </div>
        )}
        {skeleton > 0 && (
          // skeleton content — what would be written here, at loading-state
          // opacity, so the post-it's colour comes through the lines
          <div
            style={{
              position: text ? "relative" : "absolute",
              inset: text ? undefined : "18% 14%",
              marginTop: text ? "8px" : 0,
              display: "flex",
              flexDirection: "column",
              gap: text ? "5px" : "16%",
              justifyContent: "center",
            }}
          >
            {Array.from({ length: skeleton }, (_, i) => (
              <div
                key={i}
                style={{
                  height: text ? "6px" : "18%",
                  width: `${[78, 56, 66, 44][i % 4]}%`,
                  background: "rgba(28,28,31,0.13)",
                  borderRadius: "2px",
                }}
              />
            ))}
          </div>
        )}
        {/* the curl: the bottom-right corner lifting off the paper */}
        <svg
          viewBox="0 0 24 24"
          width={Math.max(14, Math.round(w * 0.12))}
          height={Math.max(14, Math.round(w * 0.12))}
          style={abs({ right: 0, bottom: 0, display: "block" })}
          aria-hidden
        >
          <path d="M24 0 L24 24 L0 24 Z" fill={C.paper} />
          <path d="M24 0 L0 24 L24 24 Z" fill="rgba(0,0,0,0.10)" />
          <path d="M24 0 C14 6 6 14 0 24 L16 24 C18 16 20 8 24 0 Z" fill={fill} />
        </svg>
      </div>
    </div>
  );
}

// ── Atom: Envelope — one card, one file. Moves only when a Postmark lands,
// and keeps every mark it collects.
export function Envelope({
  x,
  y,
  w = 112,
  id,
  type,
  marks,
  animation,
  opacity,
  delay,
  children,
}: {
  x?: string | number;
  y?: string | number;
  w?: number;
  id?: string;
  /** The card's type: a small post-it stuck on the corner, in its colour. */
  type?: CardType;
  marks?: ReactNode;
  animation?: string;
  opacity?: number;
  delay?: number;
  children?: ReactNode;
}) {
  const h = Math.round(w * 0.62);
  const positioned = x != null || y != null;
  return (
    <div
      style={{
        ...(positioned
          ? abs({
              left: typeof x === "number" ? `${x}px` : x,
              top: typeof y === "number" ? `${y}px` : y,
            })
          : {}),
        width: `${w}px`,
        height: `${h}px`,
        opacity,
        animation:
          animation ??
          (delay != null
            ? `tk-rise 0.6s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${delay}s backwards`
            : undefined),
      }}
    >
      <div
        style={abs({
          inset: 0,
          background: C.paper,
          border: `2px solid ${C.ink}`,
          boxShadow: `3px 3px 0 ${C.shade}`,
          boxSizing: "border-box",
        })}
      />
      <svg viewBox={`0 0 ${w} ${h}`} width={w} height={h} style={abs({ inset: 0 })} aria-hidden>
        <polyline
          points={`2,2 ${w / 2},${h * 0.5} ${w - 2},2`}
          fill="none"
          stroke={C.ink}
          strokeWidth="2"
        />
      </svg>
      {type && (
        <div style={abs({ left: "-6px", top: "-8px" })}>
          <PostIt w={Math.max(20, Math.round(w * 0.22))} type={type} tilt={-8} skeleton={2} />
        </div>
      )}
      {id && (
        <div
          style={abs({
            left: "8px",
            bottom: "5px",
            fontFamily: MONO,
            fontSize: "9px",
            color: C.inkSoft,
            letterSpacing: "0.06em",
          })}
        >
          {id}
        </div>
      )}
      {marks && (
        <div style={abs({ right: "-12px", top: "-16px", display: "flex", gap: "-6px" })}>
          {marks}
        </div>
      )}
      {children}
    </div>
  );
}

// ── Atom: Bin — a lane, a derived state, stored nowhere. Three receive
// Envelopes that arrive by themselves; Done is a chute with a slot, and it
// is the one bar that bleeds off the frame.
export function Bin({
  x,
  h,
  label,
  chute = false,
  breathing = false,
  children,
  width = 96,
}: {
  x: number;
  h?: number;
  label: string;
  chute?: boolean;
  breathing?: boolean;
  children?: ReactNode;
  width?: number;
}) {
  if (chute) {
    return (
      <div
        style={abs({
          left: `${x}px`,
          top: `${BENCH_Y - (h ?? 230)}px`,
          bottom: 0,
          width: `${width}px`,
          background: C.binDeep,
        })}
      >
        <div
          style={abs({
            left: "10px",
            top: "12px",
            fontSize: "11px",
            letterSpacing: "0.06em",
            color: C.ink,
            textTransform: "lowercase",
          })}
        >
          {label}
        </div>
        {/* the slot — the one place a hand puts an envelope */}
        <div
          style={abs({
            left: "12px",
            top: "34px",
            width: `${width - 24}px`,
            height: "7px",
            background: C.ink,
            transformOrigin: "50% 50%",
            animation: breathing ? "tk-breathe 1.2s ease-in-out infinite" : undefined,
          })}
        />
        {children}
      </div>
    );
  }
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${BENCH_Y - (h ?? 200)}px`,
        height: `${h ?? 200}px`,
        width: `${width}px`,
        background: C.bin,
      })}
    >
      <div
        style={abs({
          left: "10px",
          top: "12px",
          fontSize: "11px",
          letterSpacing: "0.06em",
          color: C.ink,
          textTransform: "lowercase",
        })}
      >
        {label}
      </div>
      {children}
    </div>
  );
}

// ── Atom: Vault — the archive. Everything done, kept, never rewritten,
// behind a door with a dial. The tag on its handle is where the payoff
// button lives. Drawn open, so a card can be seen arriving.
export function Vault({
  x,
  y,
  scale = 1,
  tag = false,
  delay,
  count = 2,
}: {
  x: number;
  y: number;
  scale?: number;
  tag?: boolean;
  delay?: number;
  count?: number;
}) {
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${112 * scale}px`,
        height: `${108 * scale}px`,
        animation:
          delay != null
            ? `tk-rise 0.6s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${delay}s backwards`
            : undefined,
      })}
    >
      <svg
        viewBox="0 0 112 108"
        width={112 * scale}
        height={108 * scale}
        aria-hidden
        style={{ display: "block", overflow: "visible" }}
      >
        <rect
          x="2"
          y="2"
          width="96"
          height="104"
          rx="6"
          fill={C.binDeep}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        {/* the inside: the cards already kept */}
        <rect
          x="14"
          y="14"
          width="72"
          height="80"
          fill={C.paperDeep}
          stroke={C.ink}
          strokeWidth="1.5"
        />
        {Array.from({ length: count }, (_, i) => (
          <g key={i} transform={`translate(${22 + (i % 2) * 8} ${70 - i * 16})`}>
            <rect width="30" height="18" fill={C.paper} stroke={C.ink} strokeWidth="1.5" />
            <polyline points="1,1 15,10 29,1" fill="none" stroke={C.ink} strokeWidth="1.2" />
          </g>
        ))}
        {/* the door, swung open: its edge, the dial on it */}
        <rect
          x="96"
          y="2"
          width="14"
          height="104"
          rx="3"
          fill={C.bin}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <circle cx="103" cy="54" r="8" fill={C.paper} stroke={C.ink} strokeWidth="2" />
        <line x1="103" y1="54" x2="103" y2="48" stroke={C.ink} strokeWidth="2" />
        {tag && (
          <>
            <line x1="103" y1="30" x2="118" y2="12" stroke={C.ink} strokeWidth="2" />
            <rect
              x="112"
              y="-8"
              width="30"
              height="20"
              fill={C.slot}
              stroke={C.ink}
              strokeWidth="2"
            />
          </>
        )}
      </svg>
    </div>
  );
}

// ── Scene-dressing: Pipe and HubScene — the run under the bench, the whole
// width. The HubScene is the hub itself: any folder you own, a repo, a
// synced drive (it might be OneDrive) — a cloud factory in three greys, the
// Steam Barons' plant made friendly. The Done chute drops a card into a
// funnel, a belt on little wheels carries it left under the bins to the
// stamping gantry (Archive writes the Closed date there) and on to the
// Vault at the far left, under a soft portico; a floor line runs from the
// archive to the plant and up to two sheets — the year's review, generated
// from the archived cards, and the resume, which lives in the same hub.
export function Pipe({ x, y, w, h = 26 }: { x: number; y: number; w: number; h?: number }) {
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${w}px`,
        height: `${h}px`,
        background: C.bin,
        border: `2.5px solid ${C.ink}`,
        boxSizing: "border-box",
        borderLeft: "none",
        borderRight: "none",
      })}
    >
      <div
        style={abs({
          left: 0,
          right: 0,
          top: "40%",
          height: "3px",
          background: C.paper,
          opacity: 0.8,
        })}
      />
    </div>
  );
}

export function HubScene({
  stamp,
  shake,
  sub = "any folder. a repo. a synced drive.",
}: {
  stamp?: string;
  shake?: string;
  sub?: string;
}) {
  // The desktop content panel is unscaled and as wide as 60% of the viewport
  // (768 wide is the phone's virtual panel only), so this scene is fluid: the
  // box spans the stage and the clouds are drawn far past any stage width.
  const line = {
    fill: "none",
    stroke: C.ink,
    strokeWidth: 2,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };
  return (
    <div style={abs({ left: 0, right: 0, top: `${BENCH_Y + 4}px`, bottom: 0 })}>
      <svg width="100%" height="100%" aria-hidden style={{ display: "block", overflow: "visible" }}>
        {/* far cloud: the lightest grey, no line, one long calm horizon */}
        <path
          d="M-30 40 C40 10 120 12 180 36 C240 6 330 8 380 34 C440 4 520 6 570 32 C630 6 720 10 800 40 C860 12 940 14 1000 38 C1060 10 1140 12 1200 38 C1260 8 1360 10 1420 40 C1480 14 1560 16 1620 40 L1620 700 L-30 700 Z"
          fill={C.paperDeep}
        />
        {/* mid clouds: bin grey, one ink line, the masses the machine sits in */}
        <path
          d="M-30 80 C-10 46 50 40 90 58 C120 34 190 36 210 62 C240 50 280 58 300 84 L300 700 L-30 700 Z"
          {...line}
          fill={C.bin}
        />
        <path
          d="M280 88 C290 52 340 44 380 60 C400 38 460 38 480 60 C510 46 550 56 560 86 L560 700 L280 700 Z"
          {...line}
          fill={C.bin}
        />
        <path
          d="M540 96 C550 60 600 50 640 66 C660 40 720 40 740 66 C770 56 800 64 820 96 C840 62 900 56 940 72 C960 50 1020 50 1040 72 C1070 60 1120 66 1140 100 C1160 66 1220 60 1260 78 C1290 56 1350 58 1370 84 C1400 70 1450 76 1460 104 C1500 80 1580 84 1620 104 L1620 700 L540 700 Z"
          {...line}
          fill={C.bin}
        />
        {/* the floor trunk: the hub's file tree as pipes — one trunk, a joint
            under every branch, and an artifact at the end of each */}
        <path d="M164 96 H870" {...line} />
        {[164, 560, 668, 719, 755, 806, 822, 838].map((jx) => (
          <circle key={jx} cx={jx} cy="96" r="3" fill={C.paper} stroke={C.ink} strokeWidth="2" />
        ))}
        {/* the portico around the vault: soft architecture, reassuring */}
        <path d="M22 20 Q92 -4 162 20" {...line} />
        <rect x="18" y="20" width="10" height="100" fill={C.paper} stroke={C.ink} strokeWidth="2" />
        <rect
          x="156"
          y="20"
          width="10"
          height="100"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        {/* the funnel under the Done chute, and the drop into the belt */}
        <path
          d="M400 0 L480 0 L452 30 L428 30 Z"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
          strokeLinejoin="round"
        />
        <rect x="432" y="30" width="16" height="14" fill={C.paper} stroke={C.ink} strokeWidth="2" />
        {/* the conveyor: a belt on little wheels, running left under the bins into the vault */}
        <rect
          x="96"
          y="44"
          width="384"
          height="8"
          rx="4"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        {[120, 172, 224, 276, 328, 380, 432].map((wx) => (
          <g key={wx}>
            <circle cx={wx} cy="61" r="7" fill={C.paper} stroke={C.ink} strokeWidth="2" />
            <circle cx={wx} cy="61" r="1.6" fill={C.ink} />
          </g>
        ))}
        <line x1="96" y1="69" x2="480" y2="69" {...line} />
        {/* the stamping gantry: Archive writes the Closed date here */}
        <g style={{ animation: shake }}>
          <rect x="236" y="12" width="4" height="34" fill={C.ink} />
          <rect x="268" y="12" width="4" height="34" fill={C.ink} />
          <rect x="230" y="8" width="48" height="5" rx="2" fill={C.ink} />
          <g style={{ animation: stamp }}>
            <rect x="250" y="13" width="8" height="14" fill={C.ink} />
            <rect
              x="241"
              y="25"
              width="26"
              height="7"
              rx="2"
              fill={C.paper}
              stroke={C.ink}
              strokeWidth="2"
            />
          </g>
          <circle cx="288" cy="20" r="4" fill={STAMP.commit} stroke={C.ink} strokeWidth="1.5" />
        </g>
        {/* the plant: two stacks, the pipes, a gauge, a gear turning slowly */}
        <rect
          x="598"
          y="14"
          width="18"
          height="44"
          rx="2"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        <rect
          x="594"
          y="10"
          width="26"
          height="6"
          rx="2"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        <rect
          x="644"
          y="26"
          width="16"
          height="32"
          rx="2"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        <rect
          x="640"
          y="22"
          width="24"
          height="6"
          rx="2"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2"
        />
        {[0, 1, 2].map((i) => (
          <circle
            key={i}
            cx={607 + (i - 1) * 5}
            cy={12}
            r={4 + i}
            fill={C.paperDeep}
            stroke={C.ink}
            strokeWidth="1.5"
            style={{ animation: `tk-puff-up 3s ease-out ${i}s infinite` }}
          />
        ))}
        {[0, 1].map((i) => (
          <circle
            key={i}
            cx={652 + (i - 0.5) * 6}
            cy={24}
            r={3.5 + i}
            fill={C.paperDeep}
            stroke={C.ink}
            strokeWidth="1.5"
            style={{ animation: `tk-puff-up 3.6s ease-out ${i * 1.4 + 0.6}s infinite` }}
          />
        ))}
        <path d="M616 58 H668 V70 M668 96 V98" {...line} />
        <circle cx="668" cy="84" r="14" fill={C.paper} stroke={C.ink} strokeWidth="2" />
        <line
          x1="668"
          y1="84"
          x2="675"
          y2="75"
          stroke={C.ink}
          strokeWidth="2.5"
          strokeLinecap="round"
        />
        <circle cx="668" cy="84" r="2" fill={C.ink} />
        <g
          style={{
            transformBox: "fill-box",
            transformOrigin: "center",
            animation: "tk-spin 9s linear infinite",
          }}
        >
          <circle cx="560" cy="100" r="11" fill={C.paper} stroke={C.ink} strokeWidth="2" />
          {[0, 45, 90, 135].map((a) => (
            <rect
              key={a}
              x="557.5"
              y="86"
              width="5"
              height="28"
              rx="1"
              fill={C.paper}
              stroke={C.ink}
              strokeWidth="1.5"
              transform={`rotate(${a} 560 100)`}
            />
          ))}
          <circle cx="560" cy="100" r="2.5" fill={C.ink} />
        </g>
        {/* the artifacts at the ends of the branches, inside the cloud, unlabelled:
            the year's review, the resume, and a fan of growth sheets — a
            training, a presentation, a goal. Only the stacks break the line. */}
        <path d="M719 96 V60 M755 96 V60 M806 96 V64 M822 96 V60 M838 96 V56" {...line} />
        <g transform="translate(704 22)">
          <rect
            x="0"
            y="0"
            width="30"
            height="40"
            rx="2"
            fill={C.paper}
            stroke={C.ink}
            strokeWidth="2"
          />
          {[9, 16, 23, 30].map((ly) => (
            <line
              key={ly}
              x1="6"
              y1={ly}
              x2={ly === 30 ? 17 : 24}
              y2={ly}
              stroke={C.inkSoft}
              strokeWidth="1.5"
              strokeLinecap="round"
            />
          ))}
        </g>
        <g transform="translate(740 22)">
          <rect
            x="0"
            y="0"
            width="30"
            height="40"
            rx="2"
            fill={C.paper}
            stroke={C.ink}
            strokeWidth="2"
          />
          <circle cx="10" cy="10" r="4" fill="none" stroke={C.inkSoft} strokeWidth="1.5" />
          {[20, 27, 34].map((ly) => (
            <line
              key={ly}
              x1="6"
              y1={ly}
              x2={ly === 34 ? 16 : 24}
              y2={ly}
              stroke={C.inkSoft}
              strokeWidth="1.5"
              strokeLinecap="round"
            />
          ))}
        </g>
        {[
          [791, 26, -6],
          [807, 22, 0],
          [823, 18, 6],
        ].map(([gx, gy, tilt]) => (
          <g key={gx} transform={`translate(${gx} ${gy}) rotate(${tilt} 15 20)`}>
            <rect
              x="0"
              y="0"
              width="30"
              height="40"
              rx="2"
              fill={C.paper}
              stroke={C.ink}
              strokeWidth="2"
            />
            {[9, 16, 23].map((ly) => (
              <line
                key={ly}
                x1="6"
                y1={ly}
                x2={ly === 23 ? 16 : 24}
                y2={ly}
                stroke={C.inkSoft}
                strokeWidth="1.5"
                strokeLinecap="round"
              />
            ))}
          </g>
        ))}
        {/* the label: what this is */}
        <text x="300" y="110" fontFamily={SANS} fontSize="11" letterSpacing="0.08em" fill={C.ink}>
          the hub
        </text>
        <text
          x="352"
          y="110"
          fontFamily={SANS}
          fontSize="8.5"
          letterSpacing="0.06em"
          fill={C.inkSoft}
        >
          {sub}
        </text>
      </svg>
    </div>
  );
}

// ── Atom: Ledger — Daily. The week, built only from the marks the Envelopes
// carry; lines ink in as Postmarks land, never from anything else.
export function Ledger({
  x,
  y,
  rows,
  w = 250,
  animate = true,
  delay = 0,
}: {
  x: number;
  y: number;
  rows: Array<[string, string]>;
  w?: number;
  animate?: boolean;
  delay?: number;
}) {
  return (
    <div style={abs({ left: `${x}px`, top: `${y}px`, width: `${w}px` })}>
      <div
        style={{
          fontSize: "11px",
          letterSpacing: "0.08em",
          textTransform: "lowercase",
          color: C.inkSoft,
          marginBottom: "10px",
        }}
      >
        daily
      </div>
      {rows.map(([label, value], i) => (
        <div
          key={label}
          style={{
            display: "flex",
            gap: "12px",
            alignItems: "baseline",
            marginBottom: "7px",
            borderBottom: `1px solid ${C.shade}`,
            paddingBottom: "5px",
          }}
        >
          <span
            style={{
              width: "58px",
              flexShrink: 0,
              fontSize: "11px",
              color: C.inkSoft,
              textTransform: "lowercase",
            }}
          >
            {label}
          </span>
          <span
            style={{
              display: "inline-block",
              overflow: "hidden",
              whiteSpace: "nowrap",
              fontSize: "12px",
              color: C.ink,
              animation: animate
                ? `tk-inkin 0.3s ease-out ${delay + i * 0.08}s backwards`
                : undefined,
            }}
          >
            {value}
          </span>
        </div>
      ))}
    </div>
  );
}

// ── Scene-dressing: the life on the bench. A goldfish (ink, one white eye —
// Gillbert from the Shelf Guardians, on a visit; here he is a Spike card), a
// plant, and the Pi that will feed him. They set the room; they never argue.
export function Bowl({
  x,
  y,
  scale = 1,
  fed = false,
  still = false,
}: {
  x: number;
  y: number;
  scale?: number;
  fed?: boolean;
  still?: boolean;
}) {
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${96 * scale}px`,
        height: `${84 * scale}px`,
      })}
    >
      <svg
        viewBox="0 0 96 84"
        width={96 * scale}
        height={84 * scale}
        aria-hidden
        style={{ display: "block", overflow: "visible" }}
      >
        {/* the water: a flat band inside the glass */}
        <path d="M14 28 C4 44 6 66 20 78 L76 78 C90 66 92 44 82 28 Z" fill={C.bin} />
        <g
          style={{
            transformBox: "fill-box",
            transformOrigin: "center",
            animation: still ? undefined : "tk-swim 9s ease-in-out infinite",
          }}
        >
          <path d="M30 52 C36 44 50 44 56 52 C50 60 36 60 30 52 Z" fill={C.ink} />
          <path d="M30 52 L20 45 L22 52 L20 59 Z" fill={C.ink} />
          <circle cx="50" cy="50" r="2.4" fill={C.paper} />
        </g>
        {fed &&
          [0, 1, 2, 3].map((i) => (
            <circle
              key={i}
              cx={30 + i * 11}
              cy={32}
              r="1.8"
              fill={C.ink}
              style={{
                animation: still ? undefined : `tk-flake 2.6s ease-in ${i * 0.5}s infinite`,
              }}
            />
          ))}
        {/* the glass: one ink line, flat */}
        <path
          d="M22 10 L74 10 L82 28 C92 44 90 66 76 78 L20 78 C6 66 4 44 14 28 Z"
          fill="none"
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <line x1="14" y1="28" x2="82" y2="28" stroke={C.ink} strokeWidth="1.5" />
      </svg>
    </div>
  );
}

export function Plant({
  x,
  y,
  scale = 1,
  still = false,
}: {
  x: number;
  y: number;
  scale?: number;
  still?: boolean;
}) {
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${72 * scale}px`,
        height: `${96 * scale}px`,
      })}
    >
      <svg
        viewBox="0 0 72 96"
        width={72 * scale}
        height={96 * scale}
        aria-hidden
        style={{ display: "block", overflow: "visible" }}
      >
        <g
          style={{
            transformBox: "fill-box",
            transformOrigin: "50% 100%",
            animation: still ? undefined : "tk-leaf 5s ease-in-out infinite",
          }}
        >
          <path
            d="M36 62 C20 52 12 30 22 12 C38 22 40 44 36 62 Z"
            fill={C.binDeep}
            stroke={C.ink}
            strokeWidth="2"
          />
          <path
            d="M36 62 C52 50 62 32 54 10 C40 20 34 44 36 62 Z"
            fill={C.bin}
            stroke={C.ink}
            strokeWidth="2"
          />
          <path
            d="M36 64 C30 48 34 30 36 26 C40 30 42 48 36 64 Z"
            fill={C.binDeep}
            stroke={C.ink}
            strokeWidth="2"
          />
        </g>
        <path d="M14 62 L58 62 L52 94 L20 94 Z" fill={C.paper} stroke={C.ink} strokeWidth="2.5" />
        <rect
          x="12"
          y="58"
          width="48"
          height="8"
          fill={C.paperDeep}
          stroke={C.ink}
          strokeWidth="2.5"
        />
      </svg>
    </div>
  );
}

// ── Scene-dressing: Sofa — the payoff's chair. Sofa mode: the office at the
// end of the day, Kit off his feet. Flat, one outline, two arms, four feet.
export function Sofa({ x, y, w = 150, h = 84 }: { x: number; y: number; w?: number; h?: number }) {
  return (
    <div style={abs({ left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` })}>
      <svg viewBox="0 0 150 84" width={w} height={h} aria-hidden style={{ display: "block" }}>
        {/* line art, like the bowl: paper inside, one ink line */}
        <rect
          x="20"
          y="8"
          width="110"
          height="46"
          rx="10"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <rect
          x="30"
          y="44"
          width="45"
          height="26"
          rx="5"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <rect
          x="75"
          y="44"
          width="45"
          height="26"
          rx="5"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <rect
          x="2"
          y="30"
          width="28"
          height="42"
          rx="13"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        <rect
          x="120"
          y="30"
          width="28"
          height="42"
          rx="13"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        {[14, 40, 106, 132].map((fx) => (
          <rect key={fx} x={fx} y="72" width="5" height="11" fill={C.ink} />
        ))}
      </svg>
    </div>
  );
}

export function PiBoard({ x, y, scale = 1 }: { x: number; y: number; scale?: number }) {
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${88 * scale}px`,
        height: `${40 * scale}px`,
      })}
    >
      <svg
        viewBox="0 0 88 40"
        width={88 * scale}
        height={40 * scale}
        aria-hidden
        style={{ display: "block" }}
      >
        <rect
          x="1.5"
          y="1.5"
          width="85"
          height="37"
          fill={C.paper}
          stroke={C.ink}
          strokeWidth="2.5"
        />
        {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
          <rect key={i} x={8 + i * 9} y={5} width="5" height="5" fill={C.ink} />
        ))}
        <rect x="8" y="16" width="22" height="16" fill={C.bin} stroke={C.ink} strokeWidth="1.5" />
        <rect x="62" y="20" width="18" height="12" fill={C.bin} stroke={C.ink} strokeWidth="1.5" />
        <text x="36" y="30" fontFamily={MONO} fontSize="7" fill={C.inkSoft}>
          pi zero
        </text>
      </svg>
    </div>
  );
}

// ── Atom: Terminal — where a line is typed and a Postmark is made. Types one
// command at a time, 40ms a character, half a second between lines.
export interface TermLine {
  text: string;
  /** Printed output rather than typed input: appears whole. */
  out?: boolean;
  tone?: "cyan" | "white" | "grey" | "green" | "yellow";
}

const TONE: Record<NonNullable<TermLine["tone"]>, string> = {
  cyan: "#7fd9e0",
  white: "#f4f2ec",
  grey: "#a9a7ad",
  green: "#8fd694",
  yellow: "#e9c46a",
};

/** When each line starts and how long it types — computed once, not during render. */
function schedule(
  lines: TermLine[],
  charMs: number,
  gapMs: number,
  start: number,
): Array<{ delay: number; dur: number }> {
  const out: Array<{ delay: number; dur: number }> = [];
  let t = start;
  for (const l of lines) {
    const dur = l.out ? 0.001 : (l.text.length * charMs) / 1000;
    out.push({ delay: t, dur });
    t += dur + (l.out ? 0.12 : gapMs / 1000);
  }
  return out;
}

export function Terminal({
  lines,
  x,
  y,
  w = 448,
  h,
  charMs = 40,
  gapMs = 500,
  start = 0,
  fontSize = 12,
  prompt = "PS>",
  cursor = true,
}: {
  lines: TermLine[];
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  charMs?: number;
  gapMs?: number;
  start?: number;
  fontSize?: number;
  prompt?: string;
  cursor?: boolean;
}) {
  const times = schedule(lines, charMs, gapMs, start);
  const last = times[times.length - 1];
  const end = last ? last.delay + last.dur : start;
  const rendered = lines.map((l, i) => (
    <div
      key={i}
      style={{
        display: "flex",
        whiteSpace: "pre",
        lineHeight: 1.6,
        minHeight: `${fontSize * 1.6}px`,
      }}
    >
      {!l.out && <span style={{ color: TONE.grey, marginRight: "8px" }}>{prompt}</span>}
      <span
        style={{
          display: "inline-block",
          overflow: "hidden",
          whiteSpace: "pre",
          color: l.out ? TONE[l.tone ?? "white"] : C.paper,
          animation: l.out
            ? `tk-fade-in 0.15s linear ${times[i].delay}s backwards`
            : `tk-type ${times[i].dur}s steps(${Math.max(1, l.text.length)}, end) ${times[i].delay}s backwards`,
        }}
      >
        {l.text}
      </span>
      {cursor && i === lines.length - 1 && (
        <span
          style={{
            display: "inline-block",
            width: `${fontSize * 0.6}px`,
            height: `${fontSize * 1.2}px`,
            background: C.paper,
            marginLeft: "2px",
            alignSelf: "center",
            animation: `tk-cursor 1s steps(1, end) ${end}s infinite`,
          }}
        />
      )}
    </div>
  ));
  const box: CSSProperties = {
    width: `${w}px`,
    height: h != null ? `${h}px` : undefined,
    background: C.ink,
    color: C.paper,
    fontFamily: MONO,
    fontSize: `${fontSize}px`,
    padding: "14px 16px",
    boxSizing: "border-box",
    overflow: "hidden",
  };
  return x != null || y != null ? (
    <div style={abs({ left: `${x ?? 0}px`, top: `${y ?? 0}px`, ...box })}>{rendered}</div>
  ) : (
    <div style={box}>{rendered}</div>
  );
}

// ── Atom: Window — a real screen of the product, framed on the grid. Slides
// into its cell once and holds while the room moves around it.
export function Window({
  x,
  y,
  w,
  h,
  children,
  delay = 0,
  crop,
  compact = false,
  title,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  children: ReactNode;
  delay?: number;
  /** The phone crop: the same screen, tighter on the thing the Say line names. */
  crop?: { scale: number; ox: number; oy: number };
  compact?: boolean;
  title?: string;
}) {
  const inner: CSSProperties =
    compact && crop
      ? {
          transform: `scale(${crop.scale}) translate(${-crop.ox}px, ${-crop.oy}px)`,
          transformOrigin: "0 0",
        }
      : {};
  return (
    <div
      style={abs({
        left: `${x}px`,
        top: `${y}px`,
        width: `${w}px`,
        height: `${h}px`,
        animation: `tk-window-in 0.7s ease-in-out ${delay}s backwards`,
      })}
    >
      {title && (
        <div
          style={abs({
            left: 0,
            top: "-18px",
            fontSize: "10px",
            letterSpacing: "0.08em",
            textTransform: "lowercase",
            color: C.inkSoft,
          })}
        >
          {title}
        </div>
      )}
      <div
        style={{
          width: "100%",
          height: "100%",
          border: `1.5px solid ${C.ink}`,
          boxSizing: "border-box",
          overflow: "hidden",
          background: "#fff",
          position: "relative",
        }}
      >
        <div
          style={{
            width: `${w - 3}px`,
            height: `${h - 3}px`,
            position: "absolute",
            left: 0,
            top: 0,
            ...inner,
          }}
        >
          {children}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// The product's surfaces, redrawn. Seaglass colours, the sample hub's cards,
// the app's own wording. A quotation, held to a quotation's accuracy.
// ═════════════════════════════════════════════════════════════════════════════

const UI: CSSProperties = {
  fontFamily: "'Segoe UI', system-ui, -apple-system, sans-serif",
  color: SEAGLASS.text,
};

/**
 * The identity, as SVG — the same mark as `Wordmark` below, for decks that
 * compose inside an SVG scene (the Commercial's payoff wall). One
 * construction in two mediums: the disc 1.4em wide, 11.5% in and 8% down
 * from the text box, behind the two o's, and the face's mouth on it exactly
 * as Kit wears it — so the two o's are the eyes. Colours come from THEMES,
 * never from a deck's palette: the identity is the product's. Change this and
 * `Wordmark` together or neither. Anchor: the text's left edge and baseline.
 */
export function WordmarkMark({
  x,
  y,
  em = 20,
  theme = "seaglass",
  face = "smile",
}: {
  x: number;
  y: number;
  em?: number;
  theme?: (typeof THEMES)[number]["id"];
  face?: FaceId;
}) {
  const th = THEMES.find((t) => t.id === theme) ?? THEMES[3];
  const text = th.mode === "dark" ? "#f4f2ec" : SEAGLASS.text;
  const f = FACES[face];
  // the word measures ~2.77em in the UI stack; the box is 1em tall with the
  // baseline ~0.8em down, so the disc's centre sits just above the baseline
  // (tuned by eye in DevTools: 6px up at 32px)
  const cx = x + 0.115 * 2.77 * em + 0.7 * em;
  const cy = y - 0.19 * em;
  // Kit's construction: a 92-unit disc in a 100-unit box, the mouth at (50,70)
  const k = (1.4 * em) / 92;
  const mouth = 92 * (f.pct / 100) * 0.71 * k;
  return (
    <g>
      <circle cx={cx} cy={cy} r={0.7 * em} fill={th.logo} />
      <text
        x={cx}
        y={cy + 20 * k}
        textAnchor="middle"
        dominantBaseline="central"
        fontFamily="'Segoe UI', system-ui, -apple-system, sans-serif"
        fontSize={mouth}
        fill={text}
        transform={`rotate(${f.rotate} ${cx} ${cy + 20 * k})`}
      >
        {f.glyph}
      </text>
      <text
        x={x}
        y={y}
        fontFamily="'Segoe UI', system-ui, -apple-system, sans-serif"
        fontSize={em}
        fontWeight="700"
        letterSpacing="-0.05em"
        fill={text}
      >
        ToolKit
      </text>
    </g>
  );
}

/** The wordmark: the face's disc behind the two o's. The same face as Kit. */
export function Wordmark({
  size = 20,
  disc = SEAGLASS.logo,
  color = SEAGLASS.text,
}: {
  size?: number;
  disc?: string;
  color?: string;
}) {
  return (
    <span
      style={{
        position: "relative",
        display: "inline-block",
        fontWeight: 700,
        fontSize: `${size}px`,
        letterSpacing: "-0.05em",
        lineHeight: 1,
        color,
        ...UI,
      }}
    >
      <span
        style={abs({
          left: "11.5%",
          top: "8%",
          width: "1.4em",
          height: "1.4em",
          borderRadius: "50%",
          background: disc,
        })}
      />
      <span style={{ position: "relative" }}>ToolKit</span>
    </span>
  );
}

/** The app shell: page, nav, avatar. `nav` is the active tab. */
export function AppFrame({
  children,
  nav = "Home",
  w,
  h,
}: {
  children: ReactNode;
  nav?: string;
  w: number;
  h: number;
}) {
  const tabs = ["Home", "System", "Daily", "Growth", "Meetings"];
  return (
    <div
      style={{
        width: `${w}px`,
        height: `${h}px`,
        background: `${SEAGLASS.image}, ${SEAGLASS.page}`,
        position: "relative",
        overflow: "hidden",
        ...UI,
      }}
    >
      <div
        style={{ display: "flex", alignItems: "center", padding: "10px 16px 0 16px", gap: "18px" }}
      >
        <Wordmark size={17} />
        <span
          style={{
            fontSize: "7px",
            fontWeight: 700,
            color: SEAGLASS.brand,
            border: `1px solid ${SEAGLASS.brand}`,
            borderRadius: "8px",
            padding: "1px 5px",
            marginLeft: "-8px",
          }}
        >
          demo
        </span>
        <div style={{ display: "flex", gap: "4px", marginLeft: "auto", marginRight: "auto" }}>
          {tabs.map((t) => (
            <span
              key={t}
              style={{
                fontSize: "8.5px",
                padding: "3px 8px",
                borderRadius: "3px",
                background: t === nav ? SEAGLASS.brand : "transparent",
                color: t === nav ? "#fff" : SEAGLASS.text,
                fontWeight: t === nav ? 600 : 400,
              }}
            >
              {t}
            </span>
          ))}
        </div>
        <span
          style={{
            width: "16px",
            height: "16px",
            borderRadius: "50%",
            background: "#e3e0ea",
            fontSize: "8px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontWeight: 600,
          }}
        >
          Y
        </span>
      </div>
      <div style={{ padding: "8px 16px 0 16px" }}>{children}</div>
    </div>
  );
}

function Pill({ children, on }: { children: ReactNode; on?: boolean }) {
  return (
    <span
      style={{
        fontSize: "8px",
        padding: "2px 8px",
        borderRadius: "3px",
        background: on ? SEAGLASS.brand : "transparent",
        color: on ? "#fff" : SEAGLASS.text,
        fontWeight: on ? 600 : 400,
      }}
    >
      {children}
    </span>
  );
}

function Tag({ children }: { children: ReactNode }) {
  return (
    <span
      style={{
        fontSize: "6px",
        color: SEAGLASS.brand,
        border: `1px solid ${SEAGLASS.brand}`,
        borderRadius: "6px",
        padding: "0 4px",
        marginLeft: "4px",
        fontWeight: 600,
      }}
    >
      {children}
    </span>
  );
}

export function BoardCard({
  card,
  style,
}: {
  card: { title: string; kind: string; sprint: string; progress: string };
  style?: CSSProperties;
}) {
  const [done, total] = card.progress.split("/").map(Number);
  return (
    <div
      style={{
        background: "#fff",
        borderRadius: "3px",
        padding: "5px 6px 4px 6px",
        boxShadow: "0 1px 2px rgba(0,0,0,0.06)",
        ...style,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", gap: "4px" }}>
        <span style={{ fontSize: "7.5px", fontWeight: 600, lineHeight: 1.25 }}>{card.title}</span>
        <span style={{ fontSize: "7px", color: SEAGLASS.muted }}>···</span>
      </div>
      <div style={{ fontSize: "6.5px", color: SEAGLASS.muted, marginTop: "3px" }}>
        {card.kind}
        <Tag>{card.sprint}</Tag>
      </div>
      <div
        style={{ height: "2px", background: SEAGLASS.rule, marginTop: "4px", position: "relative" }}
      >
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            height: "2px",
            width: `${(done / total) * 100}%`,
            background: SEAGLASS.brand,
          }}
        />
      </div>
      <div style={{ fontSize: "6.5px", color: SEAGLASS.muted, marginTop: "2px" }}>
        {card.progress}
      </div>
    </div>
  );
}

/**
 * The board, as the sample hub draws it. `walk` names a CSS animation the
 * deck supplies for the third Active card (Scale a recipe by servings) to
 * cross the lanes by itself; the lane pitch is `BOARD_LANE_PITCH`.
 */
export const BOARD_LANE_PITCH = 108;

export function BoardSurface({ w, h, walk }: { w: number; h: number; walk?: string }) {
  const lane = (
    label: string,
    count: number | null,
    sub: string,
    cards: ReadonlyArray<{ title: string; kind: string; sprint: string; progress: string }>,
  ) => (
    <div
      style={{
        width: "100px",
        flexShrink: 0,
        background: SEAGLASS.lane,
        borderRadius: "4px",
        padding: "6px",
        boxSizing: "border-box",
        minHeight: "150px",
        position: "relative",
      }}
    >
      <div style={{ fontSize: "8.5px", fontWeight: 700 }}>
        {label}{" "}
        {count != null && (
          <span style={{ fontSize: "6.5px", color: SEAGLASS.muted, fontWeight: 400 }}>{count}</span>
        )}
      </div>
      <div
        style={{ fontSize: "6px", color: SEAGLASS.muted, margin: "3px 0 5px 0", lineHeight: 1.3 }}
      >
        {sub}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: "5px" }}>
        {cards.map((c) => (
          <BoardCard key={c.title} card={c} />
        ))}
      </div>
    </div>
  );
  const activeCards = walk ? DEMO_CARDS.active.slice(0, 2) : DEMO_CARDS.active;
  return (
    <AppFrame w={w} h={h}>
      <div style={{ display: "flex", gap: "4px", alignItems: "center" }}>
        <Pill>List</Pill>
        <Pill on>Boards</Pill>
      </div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          margin: "5px 0 6px 0",
        }}
      >
        <span style={{ fontSize: "6.5px", color: SEAGLASS.text }}>
          Cards move by themselves: a commit is In Progress, a pull request is Code Review. Drop a
          card on Done to archive it.
        </span>
        <span
          style={{
            fontSize: "6.5px",
            border: `1px solid ${SEAGLASS.rule}`,
            borderRadius: "3px",
            padding: "2px 6px",
            background: "#fff",
          }}
        >
          All sprints ⌄
        </span>
      </div>
      <div style={{ display: "flex", gap: "8px", position: "relative" }}>
        {lane("Active", walk ? 2 : 3, "A card is Active from the moment it is made.", activeCards)}
        {lane("In Progress", 1, "Entered by a commit, not by hand.", DEMO_CARDS.inProgress)}
        {lane("Code Review", 1, "Entered by a pull request, not by hand.", DEMO_CARDS.codeReview)}
        <div
          style={{
            width: "100px",
            flexShrink: 0,
            border: `1px dashed ${SEAGLASS.brand}`,
            borderRadius: "4px",
            padding: "6px",
            boxSizing: "border-box",
            minHeight: "150px",
            background: SEAGLASS.lane,
          }}
        >
          <div style={{ fontSize: "8.5px", fontWeight: 700 }}>Done</div>
          <div style={{ textAlign: "center", marginTop: "18px" }}>
            <div
              style={{
                width: "12px",
                height: "12px",
                borderRadius: "50%",
                border: `1px solid ${SEAGLASS.brand}`,
                margin: "0 auto 4px auto",
                fontSize: "7px",
                color: SEAGLASS.brand,
                lineHeight: "12px",
              }}
            >
              ✓
            </div>
            <div style={{ fontSize: "7.5px", fontWeight: 600 }}>Drop a card here</div>
            <div
              style={{ fontSize: "6px", color: SEAGLASS.muted, marginTop: "3px", lineHeight: 1.3 }}
            >
              It is archived, with today&apos;s date. Done is a place cards go, not a list this page
              keeps.
            </div>
          </div>
        </div>
        {walk && (
          // the walking card: the third Active card, on its own layer, crossing
          // lanes by itself — no cursor in frame
          <div style={abs({ left: "6px", top: "128px", width: "88px", animation: walk })}>
            <BoardCard card={DEMO_CARDS.active[2]} />
          </div>
        )}
      </div>
    </AppFrame>
  );
}

/** The Home page's card for a local org: the product saying what it is not. */
export function ConnectCard({ w }: { w: number }) {
  return (
    <div
      style={{
        width: `${w}px`,
        background: SEAGLASS.card,
        borderRadius: "4px",
        padding: "10px 12px",
        boxSizing: "border-box",
        ...UI,
      }}
    >
      <div style={{ fontSize: "9px", fontWeight: 700, marginBottom: "6px" }}>
        Your work items and pull requests
      </div>
      <div style={{ fontSize: "7px", lineHeight: 1.45, marginBottom: "8px" }}>
        <b>Demo</b> works from the cards in your hub and does not talk to Azure DevOps, so there is
        nothing to list here. Connect the Space and this becomes My Work and My Pull Requests -- and
        a card can be started from a work item&apos;s number.
      </div>
      <span
        style={{
          fontSize: "7.5px",
          fontWeight: 600,
          background: SEAGLASS.brand,
          color: "#fff",
          padding: "4px 8px",
          borderRadius: "3px",
          display: "inline-block",
        }}
      >
        Connect Azure DevOps
      </span>
    </div>
  );
}

/** Home with a Space connected: My Work, My Pull Requests, Open in ADO. */
export function HomeConnectedSurface({ w, h }: { w: number; h: number }) {
  const work = [
    { id: "216", title: "Scale a recipe by servings", kind: "User Story" },
    { id: "214", title: "Search returns duplicates when tags overlap", kind: "Bug" },
    { id: "209", title: "Paginate the recipe list", kind: "User Story" },
  ];
  const row = (id: string, title: string, kind: string) => (
    <div
      key={id}
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        background: "#fff",
        borderRadius: "3px",
        padding: "4px 6px",
        marginBottom: "4px",
      }}
    >
      <span style={{ fontSize: "7px", flex: 1, minWidth: 0 }}>
        <b>{id}</b> {title} <span style={{ color: SEAGLASS.muted }}>· {kind}</span>
      </span>
      <span
        style={{
          fontSize: "6.5px",
          color: SEAGLASS.brand,
          fontWeight: 600,
          whiteSpace: "nowrap",
          marginLeft: "6px",
        }}
      >
        Open in ADO ↗
      </span>
    </div>
  );
  return (
    <AppFrame w={w} h={h}>
      <div style={{ display: "flex", gap: "4px", alignItems: "center", marginBottom: "6px" }}>
        <Pill on>List</Pill>
        <Pill>Boards</Pill>
      </div>
      <div style={{ display: "flex", gap: "8px" }}>
        <div
          style={{
            flex: 1,
            background: SEAGLASS.card,
            borderRadius: "4px",
            padding: "8px",
            boxSizing: "border-box",
          }}
        >
          <div style={{ fontSize: "9px", fontWeight: 700, marginBottom: "5px" }}>My Work</div>
          {work.map((x) => row(x.id, x.title, x.kind))}
        </div>
        <div
          style={{
            flex: 1,
            background: SEAGLASS.card,
            borderRadius: "4px",
            padding: "8px",
            boxSizing: "border-box",
          }}
        >
          <div style={{ fontSize: "9px", fontWeight: 700, marginBottom: "5px" }}>
            My Pull Requests
          </div>
          {row("140123", "Paginate the recipe list", "active")}
          <div
            style={{ fontSize: "6.5px", color: SEAGLASS.muted, marginTop: "6px", lineHeight: 1.4 }}
          >
            Review threads you fetch for a pull request land in the card, and in the PR Comments
            card below.
          </div>
        </div>
      </div>
    </AppFrame>
  );
}

/** Daily Activity — the week, built from the cards' own dates. */
export function DailySurface({ w, h, delay = 0 }: { w: number; h: number; delay?: number }) {
  const days: Array<[string, number, string[] | null]> = [
    [
      "Friday",
      4,
      [
        "User Story 216 Scale a recipe by servings",
        "Bug 214 Search returns duplicates when tags overlap",
        "User Story 209 Paginate the recipe list",
        "User Story 198 Import a recipe from a URL -- closed today",
      ],
    ],
    ["Thursday", 3, null],
    ["Wednesday", 3, null],
    ["Tuesday", 2, null],
    ["Monday", 2, null],
  ];
  return (
    <AppFrame w={w} h={h} nav="Daily">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ fontSize: "10px", fontWeight: 700 }}>Daily Activity</span>
        <span
          style={{
            fontSize: "6.5px",
            border: `1px solid ${SEAGLASS.rule}`,
            borderRadius: "3px",
            padding: "2px 6px",
            background: "#fff",
          }}
        >
          This week ⌄
        </span>
      </div>
      <div style={{ marginTop: "6px" }}>
        {days.map(([name, n, items], i) => (
          <div
            key={name}
            style={{
              background: SEAGLASS.card,
              borderRadius: "3px",
              marginBottom: "3px",
              padding: "4px 8px",
              animation: `tk-fade-in 0.3s linear ${delay + i * 0.08}s backwards`,
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: "8px", fontWeight: 600 }}>
                {items ? "⌄ " : "› "}
                {name}{" "}
                <span
                  style={{
                    fontSize: "6px",
                    background: "#e6e3ee",
                    borderRadius: "6px",
                    padding: "0 4px",
                    fontWeight: 600,
                  }}
                >
                  {n}
                </span>
              </span>
              <span style={{ fontSize: "6.5px", color: SEAGLASS.brand, fontWeight: 600 }}>
                ⧉ Copy Day
              </span>
            </div>
            {items && (
              <ul
                style={{
                  margin: "4px 0 2px 0",
                  paddingLeft: "12px",
                  fontSize: "6.8px",
                  lineHeight: 1.5,
                }}
              >
                {items.map((it) => (
                  <li key={it}>{it}</li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginTop: "6px",
        }}
      >
        <span style={{ fontSize: "6.5px", color: SEAGLASS.muted }}>
          Built from the cards&apos; own dates. 1 card marked not billable is left off.
        </span>
        <span
          style={{
            fontSize: "7px",
            fontWeight: 600,
            background: SEAGLASS.brand,
            color: "#fff",
            padding: "3px 7px",
            borderRadius: "3px",
          }}
        >
          ⧉ Copy All
        </span>
      </div>
    </AppFrame>
  );
}

/** Growth: trainings, presentations, goals — the sample hub's own three. */
export function GrowthSurface({ w, h, cols = 3 }: { w: number; h: number; cols?: 2 | 3 }) {
  const col = (title: string, item: string, meta: string, status: string) => (
    <div
      style={{
        flex: 1,
        background: SEAGLASS.card,
        borderRadius: "4px",
        padding: "8px",
        boxSizing: "border-box",
      }}
    >
      <div style={{ fontSize: "9px", fontWeight: 700, marginBottom: "5px" }}>{title}</div>
      <div style={{ background: "#fff", borderRadius: "3px", padding: "5px 6px" }}>
        <div style={{ fontSize: "7.5px", fontWeight: 600, lineHeight: 1.25 }}>{item}</div>
        <div style={{ fontSize: "6.5px", color: SEAGLASS.muted, marginTop: "3px" }}>
          {meta}
          <Tag>{status}</Tag>
        </div>
      </div>
    </div>
  );
  return (
    <AppFrame w={w} h={h} nav="Growth">
      <div style={{ display: "flex", gap: "8px" }}>
        {col("Trainings", "Distributed Systems Fundamentals", "2026-03-02 · Voluntary", "planned")}
        {col("Presentations", "Designing for Non-Determinism", "2026-05-14", "drafting")}
        {cols === 3 && col("Goals", "Improve test coverage patterns", "2026", "in progress")}
      </div>
    </AppFrame>
  );
}

/** Meetings: the 1:1, carried forward — the sample hub's session. */
export function MeetingsSurface({ w, h }: { w: number; h: number }) {
  return (
    <AppFrame w={w} h={h} nav="Meetings">
      <div
        style={{
          background: SEAGLASS.card,
          borderRadius: "4px",
          padding: "8px 10px",
          boxSizing: "border-box",
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={{ fontSize: "9px", fontWeight: 700 }}>1:1 · 2026-02-05</span>
          <span style={{ fontSize: "6.5px", color: SEAGLASS.muted }}>stage: retro</span>
        </div>
        <div
          style={{
            fontSize: "6.5px",
            color: SEAGLASS.muted,
            marginTop: "5px",
            textTransform: "uppercase",
            letterSpacing: "0.06em",
          }}
        >
          Carried from 2026-01-22
        </div>
        <div style={{ fontSize: "7px", lineHeight: 1.45 }}>
          Reporting spike needs a decision before it becomes a project by accident.
        </div>
        <div
          style={{
            fontSize: "6.5px",
            color: SEAGLASS.muted,
            marginTop: "5px",
            textTransform: "uppercase",
            letterSpacing: "0.06em",
          }}
        >
          Since last session
        </div>
        <div style={{ fontSize: "7px", lineHeight: 1.45 }}>
          Spike written up and circulated. Waiting on a call.
        </div>
      </div>
    </AppFrame>
  );
}

/** One theme in miniature: its page, three lanes on it, its accent, its face. */
export function ThemeTile({
  theme,
  w,
  h,
  lamp = false,
}: {
  theme: (typeof THEMES)[number];
  w: number;
  h: number;
  lamp?: boolean;
}) {
  const dark = theme.mode === "dark";
  const text = dark ? "#f0f0f0" : "#242424";
  return (
    <div
      style={{
        width: `${w}px`,
        height: `${h}px`,
        background: theme.image === "none" ? theme.page : `${theme.image}, ${theme.page}`,
        position: "relative",
        overflow: "hidden",
        ...UI,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: "6px", padding: "7px 8px 0 8px" }}>
        <Wordmark size={11} disc={theme.logo} color={text} />
        <span
          style={{
            marginLeft: "auto",
            fontSize: "5.5px",
            padding: "1px 5px",
            borderRadius: "2px",
            background: theme.brand,
            color: "#fff",
          }}
        >
          Home
        </span>
      </div>
      <div style={{ display: "flex", gap: "4px", padding: "8px" }}>
        {[2, 1, 1].map((n, i) => (
          <div
            key={i}
            style={{
              flex: 1,
              background: theme.card,
              borderRadius: "2px",
              padding: "4px",
              minHeight: `${h - 48}px`,
            }}
          >
            {Array.from({ length: n }, (_, k) => (
              <div
                key={k}
                style={{
                  height: "10px",
                  background: dark ? "rgba(255,255,255,0.14)" : "#fff",
                  borderRadius: "1px",
                  marginBottom: "3px",
                }}
              />
            ))}
          </div>
        ))}
      </div>
      {/* the lamp: the basement's one warm light, on once the ring settles */}
      {lamp && (
        <div
          style={abs({
            inset: 0,
            background:
              "radial-gradient(ellipse at 30% 20%, rgba(245,158,11,0.32) 0%, transparent 60%)",
            animation: "tk-lamp-on 0.8s ease-out 2.4s backwards",
          })}
        />
      )}
    </div>
  );
}

/** The hub in a plain file browser, and one card in a bare editor. */
export function FilesSurface({ w, h }: { w: number; h: number }) {
  const files = [
    "214-search-returns-duplicates-when-tags-overlap.prompt.md",
    "Meeting-N4WQ-sprint-review-with-the-client.prompt.md",
    LIFE_CARDS.goldfish.file,
    "Spike-K7M2-can-we-import-a-recipe-from-a-photo.prompt.md",
    "Task211-extract-unit-conversion-into-a-pure-module.prompt.md",
    LIFE_CARDS.dryCleaning.file,
    "US-209-paginate-the-recipe-list.prompt.md",
    "US-216-scale-a-recipe-by-servings.prompt.md",
  ];
  const editor = [
    "# User Story 216: Scale a recipe by servings",
    "",
    "## Branch",
    "you/216-scale-a-recipe-by-servings",
    "",
    "## Git",
    "Commits:",
    "- (pending)",
    "",
    "## Summary",
    "Depends on Task 211: scaling is conversion plus",
    "rounding, and it should not be the fourth copy.",
    "",
    "## Acceptance Criteria",
    "- [ ] Changing servings rescales every quantity",
    "- [ ] Quantities stay readable: 1 1/2 cups, not 1.4999",
    "- [ ] 'A pinch' is left alone",
    "",
    "---",
    "",
    "**Sprint:** RecipeBox\\Sprint 9",
    "**Story Points:** 5",
    "**Created:** 2026-09-17",
  ];
  const life = (f: string) => f === LIFE_CARDS.goldfish.file || f === LIFE_CARDS.dryCleaning.file;
  return (
    <div
      style={{ width: `${w}px`, height: `${h}px`, display: "flex", background: "#fafafa", ...UI }}
    >
      <div
        style={{
          width: "44%",
          borderRight: "1px solid #e0e0e0",
          padding: "8px 10px",
          boxSizing: "border-box",
          fontSize: "6.8px",
        }}
      >
        <div style={{ color: "#777", marginBottom: "6px" }}>toolkit-hub › demo › current</div>
        {files.map((f) => (
          <div
            key={f}
            style={{
              padding: "2.5px 0",
              borderBottom: "1px solid #eee",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
              fontWeight: f.startsWith("US-216") || life(f) ? 700 : 400,
            }}
          >
            ▤ {f}
          </div>
        ))}
        <div style={{ color: "#777", marginTop: "8px" }}>toolkit-hub › growth › current</div>
        <div
          style={{
            padding: "2.5px 0",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          ▤ training-2026-03-02-distributed-systems-fundamentals.prompt.md
        </div>
        <div
          style={{
            padding: "2.5px 0",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          ▤ presentation-2026-05-14-designing-for-non-determinism.prompt.md
        </div>
        <div
          style={{
            padding: "2.5px 0",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          ▤ goal-2026-improve-test-coverage-patterns.prompt.md
        </div>
      </div>
      <div
        style={{
          flex: 1,
          padding: "8px 10px",
          boxSizing: "border-box",
          fontFamily: MONO,
          fontSize: "6.6px",
          lineHeight: 1.5,
          color: "#333",
          whiteSpace: "pre",
          overflow: "hidden",
        }}
      >
        {editor.join("\n")}
      </div>
    </div>
  );
}

/** The three lines, and what tkStart prints — quoted from Scripts/Start-Toolkit.ps1. */
export const THREE_LINES: TermLine[] = [
  { text: "Import-Module ./utilities.psm1 -Force" },
  { text: "tkInstallAutoload" },
  { text: "tkStart" },
];

export const START_OUTPUT: TermLine[] = [
  { text: "", out: true },
  { text: "First run", out: true, tone: "cyan" },
  { text: "  Your hub:   ~/toolkit-hub", out: true },
  {
    text: "  Sample Space: Demo -- works from its own files. No account, no login, no network.",
    out: true,
  },
  { text: "  Copying:    18 sample files", out: true, tone: "grey" },
  { text: "  Copied.", out: true, tone: "green" },
  { text: "Web UI:", out: true, tone: "cyan" },
  { text: "  Opening http://localhost:5173 ...", out: true, tone: "grey" },
];

/**
 * The held frame's transcript: the tests, the status, the log. Test figures
 * from docs/TESTING.md; the status layout from Scripts/Get-PromptStatus.ps1;
 * the log line shape from usage.<machine>.log.
 */
export const ACCOUNTED_FOR: TermLine[] = [
  { text: "tkTestToolkit" },
  { text: "  30 suites, 3633 assertions -- all passed", out: true, tone: "green" },
  { text: "tkStatus" },
  { text: "Active prompts (5):", out: true, tone: "cyan" },
  { text: "  1. Scale a recipe by servings", out: true },
  { text: "     Sprint:   Sprint 9   Progress: 0/3   Status: Active", out: true, tone: "grey" },
  { text: "  2. Search returns duplicates when tags overlap", out: true },
  {
    text: "     Sprint:   Sprint 8   Progress: 1/3   Status: In Progress",
    out: true,
    tone: "grey",
  },
  { text: "  3. Paginate the recipe list", out: true },
  {
    text: "     Sprint:   Sprint 8   Progress: 2/4   Status: Code Review",
    out: true,
    tone: "grey",
  },
  { text: "  4. Feed the goldfish from the Pi while away", out: true },
  {
    text: "     Sprint:   (not linked)   Progress: 3/3   Status: In Progress",
    out: true,
    tone: "grey",
  },
  { text: "  5. Sprint review with the client", out: true },
  { text: "     Sprint:   (not linked)   Progress: 2/2   Status: Active", out: true, tone: "grey" },
  { text: "tkLog", out: false },
  { text: "2026-09-25T17:02:11  INFO  this-machine  tkArchive  D4RY", out: true, tone: "grey" },
  {
    text: "2026-09-25T17:02:40  INFO  this-machine  tkEnv      Tier 2 (local mode)",
    out: true,
    tone: "grey",
  },
];
