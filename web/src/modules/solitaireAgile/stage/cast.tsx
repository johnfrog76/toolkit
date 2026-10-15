import { useState } from "react";
import type { CSSProperties, KeyboardEvent, ReactNode } from "react";
import { Popover, PopoverSurface, PopoverTrigger } from "@fluentui/react-components";

// ── The stage's cast, by copy ────────────────────────────────────────────────
//
// Ported from the Wasteland studio's Remote Standup
// (src/decks/remote-standup-cast.tsx) the way the trailer came over: by COPY,
// no dependency on that repo (docs/modules/deck.md, "Where the decks are
// made"). Team Agile's played view is that deck's stage with the engine's
// script on it (docs/modules/solitaire-agile.md, "The played view"; D-TA17): the nine tiles,
// the tints, the webcam scenes, the bubble.
//
// What came over: the palette, the keyframes, Person, ZoomTile, the bubbles, Mug,
// the nine scenes, CastScene and SceneZoom -- verbatim but for the export on
// Mug and the reduced-motion rule in StandupKeyframes. What did NOT: the
// cast's bios, dossiers, code styles and status lines, and Cat Dev. The
// Wasteland's lines are the satire; here every word a tile says comes from
// the Ritual Engine (the agent's standup route), and the plate under a tile is
// the seat's (./seats.ts), not the persona's alone.

export const pf = {
  bg: "#131a2b", // studio navy — bright tiles pop against it
  border: "#243250",
  muted: "#9aa8bc",
  brand: "#6fcf97", // it's the "all green" deck; green is the accent
  text: "#eef3fb",
  red: "#e94f4f",
  blue: "#4f7de9",
  yellow: "#f7d96f",
  green: "#6fcf97",
  orange: "#f2994a",
  purple: "#9b6fe9",
  teal: "#4fc6e9",
  pink: "#e96fb1",
  slate: "#8fa3c8",
  sand: "#f4d7a1",
  sky: "#9ed8ff",
  sea: "#57b8d8",
} as const;

export const mono = "'Cascadia Code', 'Fira Code', 'Consolas', monospace";

// ── Keyframes ─────────────────────────────────────────────────────────────────
// One <style> block per Stage mount; duplicate names across mounts are
// harmless — the browser keeps the first definition.
//
// Reduced motion (added in the port): under prefers-reduced-motion: reduce
// every animation inside a stage is stilled -- the tiles sit where they land,
// the steam does not rise, the bubble is simply there. The room's own
// reduced-animation switch is not the deck engine's to read today (the engine
// exposes none), so the media query is the one rule.
export const STAGE_CLASS = "sa-stage";

export const REDUCED_MOTION_RULE = `@media (prefers-reduced-motion: reduce) { .${STAGE_CLASS}, .${STAGE_CLASS} * { animation: none !important; transition: none !important; } }`;

export function StandupKeyframes() {
  return (
    <style>{`
      @keyframes rs-pop       { 0% { transform: scale(0.7); opacity: 0; } 70% { transform: scale(1.04); } 100% { transform: scale(1); opacity: 1; } }
      @keyframes rs-bubble    { 0% { transform: translateY(8px) scale(0.85); opacity: 0; } 100% { transform: translateY(0) scale(1); opacity: 1; } }
      @keyframes rs-float     { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-4px); } }
      @keyframes rs-pulse     { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.06); } }
      @keyframes rs-flicker   { 0%, 100% { opacity: 1; } 42% { opacity: 0.55; } 46% { opacity: 0.95; } 74% { opacity: 0.7; } }
      @keyframes rs-hue       { 0% { filter: hue-rotate(0deg); } 100% { filter: hue-rotate(360deg); } }
      @keyframes rs-smoke     { 0% { transform: translateY(0) translateX(0); opacity: 0.5; } 100% { transform: translateY(-46px) translateX(10px); opacity: 0; } }
      @keyframes rs-bob       { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-7px); } }
      @keyframes rs-wave      { 0%, 100% { transform: translateX(-2%); } 50% { transform: translateX(2%); } }
      @keyframes rs-frisbee   { 0% { transform: translate(-46px, 16px) rotate(0deg); } 100% { transform: translate(46px, -12px) rotate(280deg); } }
      @keyframes rs-alertring { 0%, 100% { box-shadow: inset 0 0 0 3px rgba(233,79,79,0); } 50% { box-shadow: inset 0 0 0 3px rgba(233,79,79,0.85); } }
      @keyframes rs-spin      { to { transform: rotate(360deg); } }
      @keyframes rs-zz        { 0% { transform: translateY(0); opacity: 0; } 25% { opacity: 0.8; } 100% { transform: translateY(-30px); opacity: 0; } }
      @keyframes rs-glowsip   { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }
      @keyframes rs-deskride  { 0%, 14% { transform: translateY(0); } 42%, 60% { transform: translateY(var(--ride, -36%)); } 86%, 100% { transform: translateY(0); } }
      @keyframes rs-press     { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-18px); } }
      @keyframes rs-breathe   { 0%, 100% { transform: scaleY(1); } 50% { transform: scaleY(1.045); } }
      ${REDUCED_MOTION_RULE}
    `}</style>
  );
}

// ── Shared atoms ─────────────────────────────────────────────────────────────

// A webcam bust — head + shoulders, bottom-anchored like a real Zoom framing.
// Hair variant + shirt/skin color are each character's identity, so the same
// person is recognizable later on the beach.
type Hair = "crop" | "bun" | "headphones" | "cap" | "curls" | "long" | "buzz" | "coif" | "spikes";

export function Person({
  shirt,
  skin = "#e8b88a",
  hairColor = "#3a2a22",
  hair = "crop",
  width = 150,
  mood = "calm",
  headwear,
}: {
  shirt: string;
  skin?: string;
  hairColor?: string;
  hair?: Hair;
  /** px, or a CSS length like "100%" so a host can size the bust relatively */
  width?: number | string;
  mood?: "calm" | "grin" | "awe" | "zen";
  /**
   * Anything worn on the head, drawn in this SVG's own "0 0 120 100" space so
   * it scales with the bust instead of being chased around in CSS. The head is
   * a circle at cx=60 cy=38 r=24, so a band sits near y=30 and a crown tops
   * out around y=14. Added for the Remote Control Hat deck (the Gadget Hat
   * mounts here); omit it and the bust renders exactly as it always has.
   */
  headwear?: ReactNode;
}) {
  // overflow must stay visible: headwear is drawn in this same coordinate space
  // and can legitimately extend above y=0 (a propeller on top of a cap), which
  // the default clip would silently cut off. Nothing changes for the scenes that
  // pass no headwear.
  return (
    <svg width={width} viewBox="0 0 120 100" style={{ display: "block", overflow: "visible" }}>
      {/* shoulders */}
      <rect x="22" y="64" width="76" height="40" rx="17" fill={shirt} />
      {/* head */}
      <circle cx="60" cy="38" r="24" fill={skin} />
      {/* hair variants */}
      {hair === "crop" && (
        <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 28 A 24 26 0 0 0 36 28 Z" fill={hairColor} />
      )}
      {hair === "buzz" && (
        <path
          d="M 37 30 A 24 22 0 0 1 83 30 L 83 26 A 24 24 0 0 0 37 26 Z"
          fill={hairColor}
          opacity="0.7"
        />
      )}
      {hair === "bun" && (
        <g fill={hairColor}>
          <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 26 A 24 26 0 0 0 36 26 Z" />
          <circle cx="60" cy="12" r="8" />
        </g>
      )}
      {hair === "long" && (
        <g fill={hairColor}>
          <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 26 A 24 26 0 0 0 36 26 Z" />
          <rect x="32" y="30" width="9" height="34" rx="4.5" />
          <rect x="79" y="30" width="9" height="34" rx="4.5" />
        </g>
      )}
      {hair === "curls" && (
        <g fill={hairColor}>
          <circle cx="44" cy="20" r="9" />
          <circle cx="60" cy="15" r="10" />
          <circle cx="76" cy="20" r="9" />
        </g>
      )}
      {hair === "coif" && (
        <path
          d="M 34 30 Q 44 6 66 12 Q 88 18 86 32 Q 74 18 56 20 Q 40 22 34 30 Z"
          fill={hairColor}
        />
      )}
      {hair === "spikes" && (
        <g fill={hairColor}>
          <path d="M 40 26 L 44 12 L 50 24 Z" />
          <path d="M 52 22 L 58 8 L 64 22 Z" />
          <path d="M 66 24 L 74 12 L 78 26 Z" />
        </g>
      )}
      {hair === "cap" && (
        <g fill={hairColor}>
          <path d="M 36 30 A 24 22 0 0 1 84 30 L 84 26 A 24 24 0 0 0 36 26 Z" />
          <rect x="30" y="27" width="34" height="7" rx="3.5" />
        </g>
      )}
      {hair === "headphones" && (
        <g fill={hairColor}>
          <path d="M 34 34 A 26 26 0 0 1 86 34 L 80 34 A 20 20 0 0 0 40 34 Z" />
          <rect x="30" y="32" width="10" height="16" rx="5" />
          <rect x="80" y="32" width="10" height="16" rx="5" />
        </g>
      )}
      {/* face */}
      {mood === "zen" ? (
        <g stroke="#2b2018" strokeWidth="2.4" strokeLinecap="round">
          <line x1="49" y1="38" x2="57" y2="38" />
          <line x1="63" y1="38" x2="71" y2="38" />
        </g>
      ) : (
        <g fill="#2b2018">
          <circle cx="52" cy="37" r={mood === "awe" ? 3.6 : 2.6} />
          <circle cx="68" cy="37" r={mood === "awe" ? 3.6 : 2.6} />
        </g>
      )}
      {mood === "grin" && (
        <path
          d="M 52 47 Q 60 54 68 47"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
      {mood === "calm" && (
        <path
          d="M 54 48 Q 60 51 66 48"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
      {mood === "awe" && <ellipse cx="60" cy="49" rx="4" ry="5" fill="#2b2018" />}
      {mood === "zen" && (
        <path
          d="M 54 48 Q 60 50 66 48"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
      {headwear}
    </svg>
  );
}

/**
 * The three looks of a tile on the played standup, and the contract the
 * three of them keep: one tile in colour, ever.
 *
 *  - `speaking` -- its bubble is open: colour, the speaker's frame, a green dot.
 *  - `named`    -- lit, no bubble (the queue's Walk / Decide / Look seats, the
 *                  tracker's alarm): black and white at full brightness, a green
 *                  dot. The dot is the signal light; colour is the speaker's alone.
 *  - `ghost`    -- everyone else: grayscale, dimmed, a grey dot. The outage register.
 */
export type TileLook = "speaking" | "named" | "ghost";

/** The speaker's frame: 3px, inside the tile's box so the grid does not move. */
export const SPEAKER_OUTLINE_WIDTH = "3px";
/**
 * The CSS variable the stage sets to its own green, `pf.green` -- the register badge's: a colour
 * of the room's palette, never a theme's brand token, so nothing of the app bleeds in.
 */
export const SPEAKER_COLOR_VAR = "--sa-speaker";

export const LOOK_FILTER: Record<TileLook, string | undefined> = {
  speaking: undefined,
  named: "grayscale(1)",
  ghost: "grayscale(1) brightness(0.6)",
};

// One Zoom window. Ghost mode is the outage register: grayscale, dimmed,
// signal gone. Named is the same in black and white at full brightness, with
// the signal on; speaking is colour in the speaker's frame.
export function ZoomTile({
  tint,
  label,
  children,
  look = "speaking",
  delay = 0,
  pillState,
}: {
  tint: string;
  label: string;
  children?: ReactNode;
  look?: TileLook;
  delay?: number;
  pillState?: "green" | "offline";
}) {
  const ghost = look === "ghost";
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        borderRadius: "14px",
        overflow: "hidden",
        boxShadow: "0 10px 26px rgba(0,0,0,0.35), inset 0 0 60px rgba(0,0,0,0.14)",
        animation: `rs-pop 0.5s ease-out ${delay}s both`,
      }}
    >
      {/* The look's filter is the picture's, not the whole tile's: a named tile is
          black and white and its dot must still be green, the signal light. */}
      <div
        data-testid="stage-layer"
        style={{
          position: "absolute",
          inset: 0,
          background: `linear-gradient(180deg, ${tint} 0%, ${tint}bb 100%)`,
          filter: LOOK_FILTER[look],
        }}
      >
        {children}
      </div>
      <div
        style={{
          position: "absolute",
          left: "10px",
          bottom: "10px",
          filter: ghost ? LOOK_FILTER.ghost : undefined,
          display: "flex",
          alignItems: "center",
          gap: "7px",
          background: "rgba(10,14,24,0.72)",
          borderRadius: "7px",
          padding: "4px 10px",
          fontFamily: mono,
          fontSize: "0.68rem",
          letterSpacing: "0.06em",
          color: pf.text,
        }}
      >
        <span
          data-testid="stage-dot"
          style={{
            width: "8px",
            height: "8px",
            borderRadius: "50%",
            background: ghost ? "#666" : pf.green,
            boxShadow: ghost ? undefined : `0 0 8px ${pf.green}`,
            flexShrink: 0,
          }}
        />
        {label}
      </div>
      {/* The frame is its own element over the tile: an outline on the tile itself is
          painted under the picture layer. Inside the box, so nothing moves. */}
      {look === "speaking" && (
        <div
          data-testid="stage-frame"
          aria-hidden
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "inherit",
            pointerEvents: "none",
            outline: `${SPEAKER_OUTLINE_WIDTH} solid var(${SPEAKER_COLOR_VAR}, ${pf.brand})`,
            outlineOffset: `-${SPEAKER_OUTLINE_WIDTH}`,
          }}
        />
      )}
      {pillState && (
        <div
          style={{
            position: "absolute",
            right: "10px",
            top: "10px",
            filter: ghost ? LOOK_FILTER.ghost : undefined,
            background: pillState === "green" ? pf.green : "#3a4152",
            color: pillState === "green" ? "#0c2417" : "#9aa3b5",
            borderRadius: "999px",
            padding: "3px 10px",
            fontFamily: mono,
            fontSize: "0.62rem",
            fontWeight: 700,
            letterSpacing: "0.08em",
            animation: pillState === "green" ? "rs-pulse 2.4s ease-in-out infinite" : undefined,
          }}
        >
          {pillState === "green" ? "ALL GREEN" : "OFFLINE"}
        </div>
      )}
    </div>
  );
}

// ── The bubbles ───────────────────────────────────────────────────────
// Two surfaces of one Fluent Popover, placed by the engine (`positioning`,
// `withArrow`: it flips and shifts and follows its anchor -- no fixed offset,
// the way IssuePopover.tsx does it). Both are `inline`, so they stay inside the
// tile that owns them. Neither is a Say line: the voice reads the slide's notes,
// and these live in the slide's content.

/**
 * Above everything a tile draws. Nothing in ZoomTile or CastScene sets a
 * z-index, but their animated and filtered layers paint over a z-index:auto
 * surface later in the tile, and a bubble flipped into a neighbour's row must
 * clear that tile's scene too.
 */
export const BUBBLE_Z_INDEX = 30;

/**
 * The speech bubble shows at most this many lines and ends the last in an
 * ellipsis: a fixed count, "because it is real" -- a listener takes in
 * about that much. The voice and the copy panel still carry every line, and
 * four lines always fit below the face, so the bubble never covers the speaker.
 * No scrollbar: a speech bubble that scrolls is not a shape anyone knows.
 */
export const SPEECH_MAX_LINES = 4;

/** The clamp itself: a line clamp on the text element, standard CSS for what browsers still spell with a prefix. */
export const speechTextClamp = {
  display: "-webkit-box",
  WebkitLineClamp: SPEECH_MAX_LINES,
  WebkitBoxOrient: "vertical",
  overflow: "hidden",
  fontSize: "0.6rem",
  whiteSpace: "pre-line",
} as const;

/**
 * A surface is never taller than the room beside a tile: the stage is a 3x3 grid
 * with overflow hidden, so a taller one has no side the engine can put it on and
 * the stage clips it. The thought cloud, which lists the detail, scrolls what
 * does not fit; the speech bubble clamps instead (above).
 */
export const THOUGHT_MAX_HEIGHT = "320px";

const bubbleSurface = {
  overflowY: "auto",
  boxSizing: "border-box",
  zIndex: BUBBLE_Z_INDEX,
  background: "#ffffff",
  opacity: 1,
  color: "#1c2434",
  padding: "10px 16px",
  fontSize: "0.98rem",
  fontWeight: 600,
  lineHeight: 1.4,
  boxShadow: "0 12px 28px rgba(0,0,0,0.35)",
  maxWidth: "260px",
  border: "none",
} as const;

/**
 * Where the speech bubble's tail points: the speaker's face, not the
 * tile's box. `target` is a small anchor element over the head of the scene
 * (centre-top; at the mug on a mug tile), so the bubble sits `above` it with the
 * tail at the person. A top-row tile has no room above, so the engine flips to
 * `below` -- the tail still at the face -- and `overflowBoundary` is the stage, so
 * the bubble is kept inside the grid rather than shifted sideways into a neighbour.
 */
export function speechPositioning(target: HTMLElement, boundary: HTMLElement | null) {
  return {
    target,
    position: "above" as const,
    align: "center" as const,
    fallbackPositions: ["below" as const],
    overflowBoundary: boundary,
  };
}

/** The speech bubble: open for as long as its tile speaks, its tail at the speaker's face. */
export function SpeechBubble({
  anchor,
  boundary = null,
  children,
}: {
  anchor: HTMLElement | null;
  boundary?: HTMLElement | null;
  children: ReactNode;
}) {
  if (!anchor) return null;
  return (
    <Popover open inline withArrow positioning={speechPositioning(anchor, boundary)}>
      {/* The surface does not clip: the tail is drawn outside its box. The
          four-line clamp is the text element's. */}
      <PopoverSurface
        aria-label="Says"
        role="status"
        data-testid="stage-speech"
        style={{ ...bubbleSurface, overflowY: "visible", borderRadius: "14px" }}
      >
        <div style={{ animation: "rs-bubble 0.45s ease-out 0.3s both" }}>
          <span data-testid="stage-speech-text" style={speechTextClamp}>
            {children}
          </span>
        </div>
      </PopoverSurface>
    </Popover>
  );
}

/**
 * The thought bubble: the same surface in the cloud's shape, with the dotted
 * trail down to its trigger. Opened by the tile's button (click, Enter or
 * Space), closed by Escape or by the slide changing. The cloud floats; reduced
 * motion stills it through the stage's own rule (REDUCED_MOTION_RULE).
 */
export function ThoughtBubble({ label, children }: { label: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  // The deck's own window listener (deck/engine/DeckController.tsx) takes Escape
  // as "exit" and Space as "next". While this surface has the keyboard those two
  // are the thought's: Escape closes it (here, so Fluent's own document-level
  // handler need not see the key) and neither reaches the deck. ArrowRight is
  // left alone -- advancing closes the thought by design.
  const keep = (e: KeyboardEvent) => {
    if (e.key === "Escape") {
      e.stopPropagation();
      setOpen(false);
    } else if (e.key === " ") {
      e.stopPropagation();
    }
  };
  return (
    <Popover
      inline
      open={open}
      onOpenChange={(_, d) => setOpen(d.open)}
      positioning={{ position: "above", align: "start" }}
    >
      <PopoverTrigger disableButtonEnhancement>
        <button
          type="button"
          data-testid="stage-thought-trigger"
          aria-label={label}
          onKeyDown={keep}
          style={{
            position: "absolute",
            left: "6px",
            bottom: "30px",
            zIndex: 4,
            width: "26px",
            height: "26px",
            borderRadius: "50%",
            border: "none",
            cursor: "pointer",
            background: "#ffffff",
            color: "#1c2434",
            fontWeight: 800,
            lineHeight: 1,
          }}
        >
          ...
        </button>
      </PopoverTrigger>
      <PopoverSurface
        aria-label={label}
        data-testid="stage-thought"
        onKeyDown={keep}
        style={{
          ...bubbleSurface,
          maxHeight: THOUGHT_MAX_HEIGHT,
          borderRadius: "28px",
          padding: "16px 22px",
        }}
      >
        <div style={{ animation: "rs-float 3.2s ease-in-out infinite" }} data-float="true">
          {children}
          <span
            aria-hidden
            style={{ display: "flex", gap: "4px", marginTop: "8px", paddingLeft: "6px" }}
          >
            {[8, 6, 4].map((d) => (
              <i
                key={d}
                style={{
                  width: d,
                  height: d,
                  borderRadius: "50%",
                  background: "#c9d1e0",
                  display: "block",
                }}
              />
            ))}
          </span>
        </div>
      </PopoverSurface>
    </Popover>
  );
}

// ── Character scenes (webcam register) ───────────────────────────────────────

export function Mug({
  left,
  bottom,
  size,
  color,
  steam = false,
}: {
  left: string;
  bottom: string;
  size: number;
  color: string;
  steam?: boolean;
}) {
  return (
    <div style={{ position: "absolute", left, bottom }}>
      {steam &&
        [0, 1].map((i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              top: `${-10 - i * 4}px`,
              left: `${3 + i * 5}px`,
              width: "7px",
              height: "7px",
              borderRadius: "50%",
              background: "#fff",
              opacity: 0.6,
              filter: "blur(2.5px)",
              animation: `rs-smoke ${1.8 + i * 0.5}s ease-out infinite`,
              animationDelay: `${-i * 0.7}s`,
            }}
          />
        ))}
      <svg width={size} height={size * 0.95} viewBox="0 0 20 19">
        <rect x="2" y="3" width="12" height="14" rx="2.5" fill={color} />
        <path d="M 14 6 A 4.5 4.5 0 0 1 14 14" fill="none" stroke={color} strokeWidth="2.6" />
      </svg>
    </div>
  );
}

// The Super Dev rig: motorized desk that takes him out of frame — exactly
// three rides per standup, then it rests — plus a ten-mug fleet riding along.
// In his status callout (`press`) the desk is PARKED and the 60-lb dumbbell
// comes out: arm out at 90°, forearm up, wrist turned 45°, pressing reps
// while reporting. One gag per register — the desk rides OR he lifts.
function DevHeroScene({
  ride = "-58%",
  press = false,
  headwear,
}: {
  ride?: string;
  press?: boolean;
  headwear?: ReactNode;
}) {
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* everything on the rig rides the motor together — 3 rides, not infinite */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          animation: press ? undefined : "rs-deskride 8s ease-in-out 3",
          ...({ "--ride": ride } as CSSProperties),
        }}
      >
        <div
          style={{
            position: "absolute",
            bottom: "19%",
            left: "50%",
            transform: "translateX(-50%)",
          }}
        >
          <Person shirt="#2d5bd0" hair="coif" mood="grin" headwear={headwear} />
        </div>
        {press && (
          /* shoulder presses mid-status: upper arm out 90°, forearm up,
             wrist at 45°, sixty pounds of commitment */
          <div
            style={{
              position: "absolute",
              bottom: "21%",
              left: "56%",
              animation: "rs-press 1.4s ease-in-out infinite",
            }}
          >
            <svg width="124" height="112" viewBox="0 0 124 112">
              <line
                x1="4"
                y1="88"
                x2="52"
                y2="86"
                stroke="#2d5bd0"
                strokeWidth="13"
                strokeLinecap="round"
              />
              <line
                x1="52"
                y1="86"
                x2="54"
                y2="40"
                stroke="#e8b88a"
                strokeWidth="11"
                strokeLinecap="round"
              />
              <circle cx="55" cy="35" r="8" fill="#e8b88a" />
              <line
                x1="38"
                y1="52"
                x2="72"
                y2="18"
                stroke="#3a3f4b"
                strokeWidth="6"
                strokeLinecap="round"
              />
              <rect
                x="30"
                y="35"
                width="17"
                height="36"
                rx="6"
                transform="rotate(-45 38.5 53)"
                fill="#242833"
              />
              <rect
                x="63"
                y="1"
                width="17"
                height="36"
                rx="6"
                transform="rotate(-45 71.5 19)"
                fill="#242833"
              />
            </svg>
          </div>
        )}
        {/* desk surface; legs long enough to stay grounded mid-ascent */}
        <div
          style={{
            position: "absolute",
            bottom: "16%",
            left: "8%",
            right: "8%",
            height: "9px",
            background: "#7d5a3a",
            borderRadius: "4px",
            boxShadow: "0 6px 12px rgba(0,0,0,0.3)",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: "-52%",
            left: "27%",
            width: "7px",
            height: "68%",
            background: "#5a4530",
            borderRadius: "3px",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: "-52%",
            right: "27%",
            width: "7px",
            height: "68%",
            background: "#5a4530",
            borderRadius: "3px",
          }}
        />
        {/* ten cups of coffee — all his, all active */}
        <Mug left="9%" bottom="17.4%" size={26} color={pf.red} />
        <Mug left="15%" bottom="17.4%" size={20} color={pf.yellow} />
        <Mug left="21%" bottom="17.4%" size={30} color={pf.green} steam />
        <Mug left="28%" bottom="17.4%" size={18} color={pf.slate} />
        <Mug left="33%" bottom="17.4%" size={24} color={pf.orange} />
        <Mug left="66%" bottom="17.4%" size={20} color={pf.sky} />
        <Mug left="72%" bottom="17.4%" size={26} color={pf.purple} steam />
        <Mug left="79%" bottom="17.4%" size={22} color={pf.teal} />
        <Mug left="85%" bottom="17.4%" size={28} color={pf.pink} />
        <Mug left="92%" bottom="17.4%" size={18} color={pf.yellow} />
      </div>
      {/* the motor console does not ride — it just reports */}
      <div
        style={{
          position: "absolute",
          top: "30%",
          left: "16%",
          background: "rgba(10,14,24,0.72)",
          borderRadius: "7px",
          padding: "5px 10px",
          fontFamily: mono,
          fontSize: "0.6rem",
          color: pf.yellow,
          letterSpacing: "0.08em",
        }}
      >
        {press ? "DESK MOTOR · PARKED" : "DESK MOTOR ▲ ENGAGED"}
      </div>
    </div>
  );
}

function OpsDevScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0, background: "#10141f" }}>
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)" }}>
        <Person
          shirt="#26303f"
          skin="#c68863"
          hair="buzz"
          hairColor="#1c1611"
          mood="calm"
          headwear={headwear}
        />
      </div>
      {/* terminal window, phosphor-lit from below. Props live inside the
          zoom-safe box (≥ 0.5 − 0.5/zoom from center, both axes) so the
          solo close-up never crops them. */}
      <div
        style={{
          position: "absolute",
          top: "36%",
          left: "20%",
          width: "44%",
          borderRadius: "8px",
          background: "#0a0f0a",
          border: "1px solid #1d3020",
          padding: "8px 10px",
          fontFamily: mono,
          fontSize: "0.58rem",
          color: "#79d68a",
          lineHeight: 1.7,
          animation: "rs-flicker 2.6s ease-in-out infinite",
        }}
      >
        <div>$ tail -f prod.log</div>
        <div style={{ opacity: 0.65 }}>[ok] heartbeat 200</div>
        <div style={{ opacity: 0.65 }}>[ok] heartbeat 200</div>
        <div style={{ opacity: 0.4 }}>▮</div>
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 70% 45% at 50% 100%, rgba(121,214,138,0.16) 0%, transparent 70%)",
        }}
      />
    </div>
  );
}

function VibemancerScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0, background: "#171226" }}>
      {/* RGB ambiance — the whole aura slowly cycles hue */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(circle 46% at 24% 30%, rgba(233,79,150,0.35) 0%, transparent 60%), radial-gradient(circle 46% at 78% 34%, rgba(79,125,233,0.35) 0%, transparent 60%), radial-gradient(circle 50% at 50% 92%, rgba(111,207,151,0.3) 0%, transparent 62%)",
          animation: "rs-hue 9s linear infinite",
        }}
      />
      {/* his Zoom virtual background: the utility black hole from the BEM
          deck (scss-bem-heroes slide 7), miniaturized — same #f2a94e/#ff6ec7
          accretion colors so the crossover reads. Centered high enough to
          survive the solo-zoom crop (top ≥ 1 − 1/zoom). */}
      <div style={{ position: "absolute", top: "42%", left: "50%" }}>
        {/* accretion disk */}
        <div
          style={{
            position: "absolute",
            top: "-95px",
            left: "-95px",
            width: "190px",
            height: "190px",
            transform: "scaleY(0.2)",
            filter: "blur(2px)",
          }}
        >
          <div
            style={{
              width: "100%",
              height: "100%",
              borderRadius: "50%",
              background:
                "conic-gradient(from 0deg, #f2a94e66 0deg, transparent 60deg, #f2a94e44 130deg, #ff6ec722 180deg, #f2a94e5e 250deg, transparent 310deg, #f2a94e66 360deg)",
              animation: "rs-spin 11s linear infinite",
            }}
          />
        </div>
        {/* photon ring */}
        <svg
          width="96"
          height="96"
          viewBox="0 0 96 96"
          style={{
            position: "absolute",
            top: "-48px",
            left: "-48px",
            overflow: "visible",
            filter: "blur(0.5px) drop-shadow(0 0 8px #f2a94e88)",
            animation: "rs-glowsip 5s ease-in-out infinite",
          }}
        >
          <path
            d="M 7 48 A 41 41 0 0 1 89 48"
            fill="none"
            stroke="#f2a94eaa"
            strokeWidth="2"
            strokeLinecap="round"
          />
        </svg>
        {/* event horizon */}
        <div
          style={{
            position: "absolute",
            top: "-36px",
            left: "-36px",
            width: "72px",
            height: "72px",
            borderRadius: "50%",
            background: "#000",
            boxShadow: "0 0 0 2px #f2a94e55, 0 0 26px #f2a94e33, inset 0 0 14px #000",
          }}
        />
      </div>
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)" }}>
        <Person
          shirt="#31264d"
          skin="#f2c9a0"
          hair="headphones"
          hairColor="#231a38"
          mood="zen"
          headwear={headwear}
        />
      </div>
      {[
        { top: "38%", left: "24%" },
        { top: "46%", left: "72%" },
        { top: "62%", left: "20%" },
      ].map((p, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            ...p,
            width: "7px",
            height: "7px",
            borderRadius: "50%",
            background: "#ffffff",
            opacity: 0.7,
            animation: `rs-glowsip ${2 + i * 0.7}s ease-in-out infinite`,
            animationDelay: `${-i * 0.9}s`,
          }}
        />
      ))}
    </div>
  );
}

function UltraWideScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0, background: "#1a2233" }}>
      {/* only the forehead survives behind three 50-inch displays — high
          enough that eyes peek over the monitor line even in the solo zoom */}
      <div
        style={{ position: "absolute", bottom: "38%", left: "50%", transform: "translateX(-50%)" }}
      >
        <Person
          shirt="#223047"
          skin="#8d5a3b"
          hair="crop"
          hairColor="#14100c"
          mood="awe"
          headwear={headwear}
        />
      </div>
      {[
        { left: "2%", rot: -8 },
        { left: "31%", rot: 0 },
        { left: "60%", rot: 8 },
      ].map(({ left, rot }, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            bottom: "2%",
            left,
            width: "38%",
            height: "46%",
            background: "linear-gradient(200deg, #2c3c58 0%, #1b2536 100%)",
            border: "3px solid #0d1420",
            borderRadius: "6px",
            transform: `rotate(${rot}deg)`,
            boxShadow: "0 10px 22px rgba(0,0,0,0.5)",
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: "10%",
              background: `repeating-linear-gradient(0deg, rgba(111,207,151,0.28) 0px, rgba(111,207,151,0.28) 2px, transparent 2px, transparent 7px)`,
            }}
          />
        </div>
      ))}
    </div>
  );
}

function QaScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={{ position: "absolute", bottom: 0, left: "44%", transform: "translateX(-50%)" }}>
        {/* labcoat */}
        <Person
          shirt="#f2f4f6"
          skin="#e8b88a"
          hair="bun"
          hairColor="#5a3a20"
          mood="calm"
          headwear={headwear}
        />
      </div>
      {/* flask of suspiciously stable green */}
      <div style={{ position: "absolute", bottom: "6%", right: "21%" }}>
        <svg width="52" height="64" viewBox="0 0 52 64">
          <path
            d="M 21 4 L 21 24 L 8 52 A 8 8 0 0 0 15 62 L 37 62 A 8 8 0 0 0 44 52 L 31 24 L 31 4 Z"
            fill="#dfe8ee"
            opacity="0.9"
          />
          <path
            d="M 13 42 L 39 42 L 44 52 A 8 8 0 0 1 37 62 L 15 62 A 8 8 0 0 1 8 52 Z"
            fill={pf.green}
          />
          <rect x="18" y="2" width="16" height="5" rx="2.5" fill="#b9c6d1" />
        </svg>
      </div>
      {/* smoke, rising from the flask: normal, apparently. The copy promises
          smoke in the frame — it has to be unmissable. */}
      {[0, 1, 2, 3].map((i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            bottom: `${34 + i * 7}%`,
            right: `${22 + (i % 2) * 3}%`,
            width: `${26 - i * 3}px`,
            height: `${26 - i * 3}px`,
            borderRadius: "50%",
            background: "#ffffff",
            opacity: 0.75,
            filter: "blur(4px)",
            animation: `rs-smoke ${2.2 + i * 0.4}s ease-out infinite`,
            animationDelay: `${-i * 0.7}s`,
          }}
        />
      ))}
    </div>
  );
}

function PmScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* controlled forward motion — inner wrapper owns the bob animation */}
      <div
        style={{ position: "absolute", bottom: "14%", left: "50%", transform: "translateX(-50%)" }}
      >
        <div style={{ animation: "rs-bob 1.1s ease-in-out infinite" }}>
          {/* charcoal athletic wear — a red shirt vanishes into the red tile */}
          <Person
            shirt="#2a3142"
            skin="#f2c9a0"
            hair="long"
            hairColor="#7a4a20"
            mood="grin"
            width={130}
            headwear={headwear}
          />
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: "6%",
          left: "18%",
          right: "18%",
          height: "12px",
          background: "#2a3142",
          borderRadius: "6px",
          boxShadow: "0 8px 14px rgba(0,0,0,0.35)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: "34%",
          left: "20%",
          background: "rgba(10,14,24,0.7)",
          borderRadius: "7px",
          padding: "5px 10px",
          fontFamily: mono,
          fontSize: "0.6rem",
          color: pf.green,
          letterSpacing: "0.08em",
        }}
      >
        ROADMAP ▲ STABLE
      </div>
    </div>
  );
}

function DesignerScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* beanbag blob, low in frame */}
      <div
        style={{
          position: "absolute",
          bottom: "-6%",
          left: "16%",
          width: "68%",
          height: "38%",
          borderRadius: "48% 52% 40% 60% / 62% 58% 42% 38%",
          background: "#b0563a",
          boxShadow: "inset 0 -12px 24px rgba(0,0,0,0.3)",
        }}
      />
      <div
        style={{ position: "absolute", bottom: "16%", left: "50%", transform: "translateX(-50%)" }}
      >
        {/* cream shirt + terracotta beanbag — green-on-green disappeared into the tile */}
        <Person
          shirt="#efe6d6"
          skin="#c68863"
          hair="curls"
          hairColor="#241a12"
          mood="zen"
          width={130}
          headwear={headwear}
        />
      </div>
      {/* floating design frames + cursor */}
      <div style={{ position: "absolute", top: "32%", right: "19%", width: "34%", height: "26%" }}>
        <div
          style={{
            position: "absolute",
            inset: 0,
            border: `2px solid ${pf.pink}`,
            borderRadius: "6px",
            opacity: 0.85,
          }}
        />
        <div
          style={{
            position: "absolute",
            inset: "22% 40% 20% 12%",
            border: `2px solid ${pf.teal}`,
            borderRadius: "4px",
            opacity: 0.85,
          }}
        />
        <svg
          width="16"
          height="18"
          viewBox="0 0 12 14"
          style={{ position: "absolute", right: "-6px", bottom: "-8px" }}
        >
          <path d="M 1 1 L 11 8 L 6 9 L 8 13 L 5 13 L 4 9 L 1 11 Z" fill="#ffffff" />
        </svg>
      </div>
    </div>
  );
}

function NewHireScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* framing is... a work in progress — half out of shot, waving */}
      <div
        style={{
          position: "absolute",
          bottom: "-4%",
          left: "24%",
          transform: "translateX(-50%) rotate(-4deg)",
        }}
      >
        <Person
          shirt="#d9a12f"
          skin="#f2c9a0"
          hair="spikes"
          hairColor="#6a4a1a"
          mood="awe"
          headwear={headwear}
        />
      </div>
      {/* the eager raised hand — 2x, shadowed, with a shirt-yellow cuff so
          it unmistakably belongs to him */}
      <svg
        width="80"
        height="88"
        viewBox="0 0 30 38"
        style={{
          position: "absolute",
          bottom: "34%",
          left: "45%",
          filter: "drop-shadow(0 6px 12px rgba(0,0,0,0.4))",
        }}
      >
        <g fill="#f2c9a0">
          <rect x="10" y="12" width="12" height="18" rx="6" />
          {[0, 1, 2, 3].map((i) => (
            <rect
              key={i}
              x={8 + i * 4.4}
              y={2 + (i === 0 ? 6 : i === 3 ? 4 : 0)}
              width="4"
              height="14"
              rx="2"
            />
          ))}
        </g>
        <rect x="9" y="28" width="14" height="9" rx="3.5" fill="#d9a12f" />
      </svg>
    </div>
  );
}

function MinimalistScene({ headwear }: { headwear?: ReactNode } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0, background: "#e8ecef" }}>
      {/* a perfectly empty room, one small person, zero clutter */}
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)" }}>
        <Person
          shirt="#454b54"
          skin="#e8b88a"
          hair="buzz"
          hairColor="#2c2c2c"
          mood="calm"
          width={96}
          headwear={headwear}
        />
      </div>
      <div
        style={{
          position: "absolute",
          bottom: "4%",
          right: "22%",
          width: "18%",
          height: "3px",
          background: "#c3cbd2",
          borderRadius: "2px",
        }}
      />
    </div>
  );
}

// Renders a character's webcam scene on demand, optionally with something on
// their head. CAST's own `scene` field stays a pre-built element because the
// first two decks never needed to vary one; the Remote Control Hat deck goes
// through here instead, so the hat mounts inside Person's SVG rather than being
// positioned over the tile in CSS (a hat that floats near a head fails the
// rigid-relations check, and nine hand-tuned offsets would drift anyway).
export function CastScene({
  id,
  headwear,
  parked = false,
}: {
  id: string;
  headwear?: ReactNode;
  /** Park Super Dev's motorized desk. Without this his rig rides him out of
      frame on a timer, so any slide that needs all nine faces present at once
      has to ask for it. On his rig, parking is also what brings the dumbbell
      out — the desk rides or he lifts, never both. */
  parked?: boolean;
}) {
  switch (id) {
    case "dev-hero":
      return <DevHeroScene press={parked} headwear={headwear} />;
    case "ops-dev":
      return <OpsDevScene headwear={headwear} />;
    case "minimalist":
      return <MinimalistScene headwear={headwear} />;
    case "new-hire":
      return <NewHireScene headwear={headwear} />;
    case "vibemancer":
      return <VibemancerScene headwear={headwear} />;
    case "ultrawide":
      return <UltraWideScene headwear={headwear} />;
    case "qa":
      return <QaScene headwear={headwear} />;
    case "pm":
      return <PmScene headwear={headwear} />;
    case "designer":
      return <DesignerScene headwear={headwear} />;
    default:
      throw new Error(`Unknown cast member: ${id}`);
  }
}

// ── The nine, in the Wasteland's grid order ──────────────────────────────────
// Only what the stage draws: the id the scenes are keyed by, the persona's
// name, the tile's tint. The grid order is the Remote Standup's, unchanged --
// "it always looks like that" (D-TA17): you learn where to look.
export interface CastMember {
  id: string;
  /** The persona, as the Wasteland's plate wrote it. */
  label: string;
  tint: string;
  /** The character's title, from the Wasteland's personnel file. */
  title: string;
  /** The character's motto, in their own voice -- who they are, never a status. */
  motto: string;
}

// The title and the motto are the Wasteland's own (the Remote Standup cast's
// profile: its role, and a line in the character's own voice from its bio),
// carried here for the played standup's copy panel, which shows who is
// speaking rather than repeating the bubble.
export const CAST: readonly CastMember[] = [
  {
    id: "dev-hero",
    label: "DEV-HERO",
    tint: pf.blue,
    title: "SUPER DEV · TEAM LEAD",
    motto: "I type on a mechanical keyboard and every key click is adding value you hear.",
  },
  {
    id: "ops-dev",
    label: "OPS-DEV",
    tint: "#26303f",
    title: "DEVOPS",
    motto: "I deployed during this standup. I did not tell anyone.",
  },
  {
    id: "minimalist",
    label: "MINIMALIST",
    tint: "#e8ecef",
    title: "IC",
    motto: "I like a clean canvas.",
  },
  {
    id: "new-hire",
    label: "NEW HIRE",
    tint: pf.yellow,
    title: "SUPPORT",
    motto: "I have fourteen open tickets. I have always had fourteen open tickets.",
  },
  {
    id: "vibemancer",
    label: "AI VIBEMANCER",
    tint: "#171226",
    title: "AI ENGINEER",
    motto: "I name my variables latent_vibe_tensor and the models understand me.",
  },
  {
    id: "ultrawide",
    label: "ULTRAWIDE OVERLORD",
    tint: pf.teal,
    title: "DATA",
    motto: "My desk is 42 inches wide to reduce variance. I graph your excuses.",
  },
  {
    id: "qa",
    label: "QA ALCHEMIST",
    tint: pf.orange,
    title: "QA",
    motto: "My monitor is grayscale because colours hide bugs. I trust nothing, especially you.",
  },
  {
    id: "pm",
    label: "PM (TREADMILL)",
    tint: pf.red,
    title: "PM",
    motto: "The treadmill is at 3.5 and the roadmap moves at exactly that speed.",
  },
  {
    id: "designer",
    label: "DESIGNER",
    tint: pf.green,
    title: "DESIGNER",
    motto: "I redesigned the sprint board for aesthetic reasons. Twice.",
  },
];

export function castById(id: string): CastMember {
  const m = CAST.find((c) => c.id === id);
  if (!m) throw new Error(`Unknown cast member: ${id}`);
  return m;
}

// Zooms a grid-sized scene for close-up registers (solos, profile pages).
export function SceneZoom({ zoom, children }: { zoom: number; children: ReactNode }) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        transform: `scale(${zoom})`,
        transformOrigin: "50% 96%",
      }}
    >
      {children}
    </div>
  );
}
