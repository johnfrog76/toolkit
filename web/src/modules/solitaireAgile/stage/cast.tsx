import { useState } from "react";
import type { CSSProperties, KeyboardEvent, ReactNode } from "react";
import { Popover, PopoverSurface, PopoverTrigger } from "@fluentui/react-components";
import { RefinedBust } from "../../../shared/refinedFaces";
import type { FaceId } from "../../../shared/refinedFaces";
import type { BubbleSide } from "./geometry";
import {
  DRAWING_SHADOW,
  SOFT_SHADOW,
  Soft,
  dark,
  lite,
  sideShade,
  useDrawingId,
  wall,
} from "./refined";

// ── The stage's cast, by copy ────────────────────────────────────────────────
//
// Ported from the Wasteland studio's Remote Standup
// (src/decks/remote-standup-cast.tsx) the way the trailer came over: by COPY,
// no dependency on that repo (docs/modules/deck.md, "Where the decks are
// made"). Team Agile's played view is that deck's stage with the engine's
// script on it (docs/modules/solitaire-agile.md, "The played view"; D-TA17): the nine tiles,
// the tints, the webcam scenes, the bubble.
//
// What came over: the palette, the keyframes, ZoomTile, the bubbles, the nine
// scenes, CastScene and SceneZoom. What did NOT: the cast's bios, dossiers,
// code styles and status lines, and Cat Dev. The Wasteland's lines are the
// satire; here every word a tile says comes from the Ritual Engine (the
// agent's standup route), and the plate under a tile is the seat's
// (./seats.ts), not the persona's alone.
//
// The drawings are no longer the Wasteland's. The people are the refined cast
// (shared/refinedFaces.tsx, the faces the Org page and the landing page draw),
// matched by cast id, and every prop -- the desk and its mugs, the terminal,
// the monitors, the flask, the treadmill, the raised hand -- is drawn in that
// style (./refined.tsx). What a window holds, where its head is and what moves
// are as they were: the head of each bust is where ./geometry.ts says it is.

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
/** The stage's grid of nine windows, below its title row: the room a speech bubble is kept inside. */
export const STAGE_GRID_CLASS = "sa-stage-grid";

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

/**
 * A webcam bust: the refined face for a cast id, bottom-anchored like a real
 * Zoom framing.
 *
 * The box it stands in is the one the stage has always given a bust -- 120 by
 * 100 units, the head an ellipse centred on (60, 38) -- so a head is where
 * ./geometry.ts expects it. The refined bust's own box starts 10 units higher
 * (room for a bun or a spike) and its torso runs 14 lower, so it is hung 10 up
 * and overflows the bottom, where a desk or the window's edge cuts it.
 */
export function Bust({ id, width = 150 }: { id: FaceId; width?: number }) {
  return (
    <div data-bust={id} style={{ width, height: (width * 100) / 120 }}>
      <div style={{ display: "flex", position: "relative", top: -(width * 10) / 120 }}>
        <RefinedBust face={id} width={width} />
      </div>
    </div>
  );
}

/**
 * The four looks of a tile on the played standup, and the contract they keep:
 * every window is in full colour, one tile is framed, ever, and one more is
 * marked on the slide the chair calls a name. Nothing is black and white and
 * nothing is dimmed: a look is a frame, a mark or a dot, never a filter.
 *
 *  - `speaking` -- its bubble is open: the speaker's frame, a green dot.
 *  - `called`   -- the member the chair has just named, about to answer: a
 *                  green dot and the called mark (a dashed ring in the speaker's
 *                  colour, inset from the edge), but no frame and no bubble.
 *  - `named`    -- a face that is there and not speaking: a green dot, the
 *                  signal light, and neither frame nor mark.
 *  - `ghost`    -- a window with nobody in it, the empty desk: a grey dot. The
 *                  drink on the desk is what says the seat is empty.
 */
export type TileLook = "speaking" | "called" | "named" | "ghost";

/** The speaker's frame: 3px, inside the tile's box so the grid does not move. */
export const SPEAKER_OUTLINE_WIDTH = "3px";
/** The called mark: a dashed ring, inset from the window's edge so it never reads as the frame. */
export const CALLED_MARK_OUTLINE = "3px dashed";
export const CALLED_MARK_INSET = "7px";
/**
 * The CSS variable the stage sets to its own green, `pf.green` -- the register badge's: a colour
 * of the room's palette, never a theme's brand token, so nothing of the app bleeds in.
 */
export const SPEAKER_COLOR_VAR = "--sa-speaker";

// One Zoom window, in full colour whatever its look. The wall is the window's
// tint under the refined light: lit at the top left, shaded at the bottom right.
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
      <div
        data-testid="stage-layer"
        style={{
          position: "absolute",
          inset: 0,
          background: wall(tint),
        }}
      >
        {children}
      </div>
      <div
        data-testid="stage-plate-label"
        style={{
          position: "absolute",
          left: "10px",
          bottom: "10px",
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
      {look === "called" && (
        <div
          data-testid="stage-called-mark"
          aria-hidden
          style={{
            position: "absolute",
            inset: CALLED_MARK_INSET,
            borderRadius: "10px",
            pointerEvents: "none",
            outline: `${CALLED_MARK_OUTLINE} var(${SPEAKER_COLOR_VAR}, ${pf.brand})`,
          }}
        />
      )}
      {pillState && (
        <div
          style={{
            position: "absolute",
            right: "10px",
            top: "10px",
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
// Two surfaces on one white ground. The speech bubble is placed by the stage's
// own rule (./geometry.ts), which knows the faces and plates it must keep off; the
// thought cloud is a Fluent Popover opened from its window's button. Both live in
// the tile that owns them. Neither is a Say line: the voice reads the slide's
// notes, and these live in the slide's content.

/**
 * Above everything a tile draws. Nothing in ZoomTile or CastScene sets a
 * z-index, but their animated and filtered layers paint over a z-index:auto
 * surface later in the tile, and a bubble flipped into a neighbour's row must
 * clear that tile's scene too.
 */
export const BUBBLE_Z_INDEX = 30;

/**
 * The speech bubble shows at most this many lines and ends the last in an
 * ellipsis: a fixed count, "because it is real" -- a listener takes in about
 * that much. A turn's first lines show; the voice (the slide's Say lines)
 * carries every line of it. No scrollbar: a speech bubble that scrolls is not a
 * shape anyone knows.
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
 * The speech bubble's width: as wide as its lines need, up to 260px and never
 * wider than its own window -- the size it has always had (an inline popover
 * shrank to its window). Drawn at `max-content` within this cap, so where the
 * stage places it does not change how wide it is.
 */
export const SPEECH_MAX_WIDTH = "min(260px, 100%)";

/** The tail's size: a small square turned 45 degrees on the edge that faces the speaker. */
const TAIL = 12;

/**
 * The speech bubble: open for as long as its tile speaks, placed by the stage
 * (./geometry.ts placeBubble) and drawn here at that place, its tail on the edge
 * that faces the speaker, at the face. Until it is placed it is laid out
 * unseen, so the stage can measure it.
 */
export function SpeechBubble({
  bubbleRef,
  place,
  children,
}: {
  bubbleRef: (el: HTMLDivElement | null) => void;
  /** Where to draw it, relative to the speaking window; null while it is measured. */
  place: { left: number; top: number; side: BubbleSide; tail: number } | null;
  children: ReactNode;
}) {
  const tailEdge: Record<BubbleSide, CSSProperties> = {
    above: { bottom: -TAIL / 2, left: (place?.tail ?? 0) - TAIL / 2 },
    below: { top: -TAIL / 2, left: (place?.tail ?? 0) - TAIL / 2 },
    after: { left: -TAIL / 2, top: (place?.tail ?? 0) - TAIL / 2 },
    before: { right: -TAIL / 2, top: (place?.tail ?? 0) - TAIL / 2 },
  };
  return (
    <div
      ref={bubbleRef}
      aria-label="Says"
      role="status"
      data-testid="stage-speech"
      data-side={place?.side}
      style={{
        ...bubbleSurface,
        position: "absolute",
        left: place?.left ?? 0,
        top: place?.top ?? 0,
        visibility: place ? "visible" : "hidden",
        width: "max-content",
        maxWidth: SPEECH_MAX_WIDTH,
        overflowY: "visible",
        borderRadius: "14px",
      }}
    >
      {place && (
        <span
          aria-hidden
          data-testid="stage-speech-tail"
          style={{
            position: "absolute",
            width: TAIL,
            height: TAIL,
            background: "#ffffff",
            transform: "rotate(45deg)",
            ...tailEdge[place.side],
          }}
        />
      )}
      <div style={{ position: "relative", animation: "rs-bubble 0.45s ease-out 0.3s both" }}>
        <span data-testid="stage-speech-text" style={speechTextClamp}>
          {children}
        </span>
      </div>
    </div>
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
// Each scene is its window's picture: the bust, where it has always sat, and
// the props around it. A readout that is text (the desk motor's, the
// terminal's, the roadmap's) sits clear of the face, so the face is seen.

/** A small mug on a desk: a fill, a darker handle, one shade down the right and a highlight on the left. */
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
  const id = useDrawingId("mg");
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
      <svg width={size} height={size * 0.95} viewBox="0 0 20 19" style={{ display: "block" }}>
        <path
          d="M 14 6 A 4.5 4.5 0 0 1 14 14"
          fill="none"
          stroke={dark(color, 0.2)}
          strokeWidth="2.6"
          strokeLinecap="round"
        />
        <clipPath id={id}>
          <rect x="2" y="3" width="12" height="14" rx="2.5" />
        </clipPath>
        <rect x="2" y="3" width="12" height="14" rx="2.5" fill={color} />
        <path
          d="M 11.6 0 Q 10 10 11.6 20 H 18 V 0 Z"
          fill="#000"
          opacity="0.16"
          clipPath={`url(#${id})`}
        />
        <rect x="3.7" y="5.6" width="1.5" height="8" rx="0.75" fill="#fff" opacity="0.36" />
      </svg>
    </div>
  );
}

/** A status readout pinned in a window: the dark pill the plates use, in the stage's mono. */
function Readout({
  top,
  left,
  color,
  children,
}: {
  top: string;
  left: string;
  color: string;
  children: ReactNode;
}) {
  return (
    <div
      style={{
        position: "absolute",
        top,
        left,
        background: "rgba(10,14,24,0.72)",
        borderRadius: "7px",
        padding: "5px 10px",
        fontFamily: mono,
        fontSize: "0.6rem",
        color,
        letterSpacing: "0.08em",
      }}
    >
      {children}
    </div>
  );
}

// The Super Dev rig: motorized desk that takes him out of frame — exactly
// three rides per standup, then it rests — plus a ten-mug fleet riding along.
// In his status callout (`press`) the desk is PARKED and the 60-lb dumbbell
// comes out: arm out at 90°, forearm up, wrist turned 45°, pressing reps
// while reporting. One gag per register — the desk rides OR he lifts.
function DevHeroScene({ ride = "-58%", press = false }: { ride?: string; press?: boolean }) {
  const id = useDrawingId("dh");
  const shirt = "#2d5bd0";
  const skin = "#e8b88a";
  const iron = "#333a4b";
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
          <Bust id="dev-hero" />
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
            <svg
              width="124"
              height="112"
              viewBox="0 0 124 112"
              style={{ display: "block", overflow: "visible", filter: DRAWING_SHADOW }}
            >
              <Soft id={`${id}-sleeve`} fill={shirt} shade={dark(shirt, 0.24)} dx={-1} dy={-3}>
                <rect x="12" y="90" width="49" height="16" rx="8" transform="rotate(-17 20 98)" />
              </Soft>
              <Soft id={`${id}-arm`} fill={skin} shade={dark(skin, 0.16)} dx={-2.6} dy={0}>
                <rect
                  x="46.5"
                  y="34"
                  width="13"
                  height="58"
                  rx="6.5"
                  transform="rotate(2.5 53 63)"
                />
                <circle cx="55" cy="35" r="8.5" />
              </Soft>
              <path
                d="M 38 52 L 72 18"
                fill="none"
                stroke={iron}
                strokeWidth="6"
                strokeLinecap="round"
              />
              <Soft id={`${id}-iron`} fill={iron} shade={dark(iron, 0.4)} dx={-2.4} dy={-1.6}>
                <rect x="30" y="35" width="17" height="36" rx="6" transform="rotate(-45 38.5 53)" />
                <rect x="63" y="1" width="17" height="36" rx="6" transform="rotate(-45 71.5 19)" />
              </Soft>
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
            background: sideShade("#8a6644"),
            borderRadius: "4px",
            boxShadow: SOFT_SHADOW,
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: "-52%",
            left: "27%",
            width: "7px",
            height: "68%",
            background: sideShade("#5f4932", 0.3),
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
            background: sideShade("#5f4932", 0.3),
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
      {/* the motor console does not ride — it just reports, above his head */}
      <Readout top="5%" left="16%" color={pf.yellow}>
        {press ? "DESK MOTOR · PARKED" : "DESK MOTOR ▲ ENGAGED"}
      </Readout>
    </div>
  );
}

function OpsDevScene() {
  return (
    <div style={{ position: "absolute", inset: 0, background: wall("#10141f") }}>
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)" }}>
        <Bust id="ops-dev" />
      </div>
      {/* terminal window, phosphor-lit from below, up in the corner beside his head */}
      <div
        style={{
          position: "absolute",
          top: "6%",
          left: "6%",
          width: "44%",
          borderRadius: "8px",
          background: "#0a0f0a",
          boxShadow: SOFT_SHADOW,
          padding: "6px 10px",
          fontFamily: mono,
          fontSize: "0.58rem",
          color: "#79d68a",
          lineHeight: 1.5,
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
          pointerEvents: "none",
          background:
            "radial-gradient(ellipse 70% 45% at 50% 100%, rgba(121,214,138,0.16) 0%, transparent 70%)",
        }}
      />
    </div>
  );
}

function VibemancerScene() {
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
        <Bust id="vibemancer" />
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

function UltraWideScene() {
  const bezel = "#27344e";
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* three 50-inch displays, and a head above the monitor line */}
      <div
        style={{ position: "absolute", bottom: "38%", left: "50%", transform: "translateX(-50%)" }}
      >
        <Bust id="ultrawide" />
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
            background: sideShade(bezel, 0.36),
            borderRadius: "8px",
            transform: `rotate(${rot}deg)`,
            boxShadow: SOFT_SHADOW,
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: "8%",
              borderRadius: "4px",
              background: "#141c2c",
            }}
          />
          <div
            style={{
              position: "absolute",
              inset: "14%",
              background: `repeating-linear-gradient(0deg, rgba(111,207,151,0.34) 0px, rgba(111,207,151,0.34) 2px, transparent 2px, transparent 7px)`,
            }}
          />
        </div>
      ))}
    </div>
  );
}

function QaScene() {
  const id = useDrawingId("qa");
  const glass = "#e6eef3";
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={{ position: "absolute", bottom: 0, left: "44%", transform: "translateX(-50%)" }}>
        {/* labcoat */}
        <Bust id="qa" />
      </div>
      {/* flask of suspiciously stable green */}
      <div style={{ position: "absolute", bottom: "6%", right: "21%" }}>
        <svg
          width="52"
          height="64"
          viewBox="0 0 52 64"
          style={{ display: "block", overflow: "visible", filter: DRAWING_SHADOW }}
        >
          <Soft id={`${id}-glass`} fill={glass} shade={dark(glass, 0.22)} dx={-3.4} dy={0}>
            <path d="M 21 4 L 21 24 L 8 52 A 8 8 0 0 0 15 62 L 37 62 A 8 8 0 0 0 44 52 L 31 24 L 31 4 Z" />
          </Soft>
          <Soft id={`${id}-brew`} fill={pf.green} shade={dark(pf.green, 0.24)} dx={-3.4} dy={0}>
            <path d="M 13 42 L 39 42 L 44 52 A 8 8 0 0 1 37 62 L 15 62 A 8 8 0 0 1 8 52 Z" />
          </Soft>
          <Soft id={`${id}-lip`} fill="#c9d4dd" shade="#a3b0bc" dx={-3} dy={0}>
            <rect x="18" y="2" width="16" height="5" rx="2.5" />
          </Soft>
          <rect x="22.6" y="9" width="1.8" height="13" rx="0.9" fill="#fff" opacity="0.5" />
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

/** The PM's bust, in px: smaller than the others, as it has always been. */
const PM_BUST = 130;

function PmScene() {
  const id = useDrawingId("pm");
  const shirt = "#2a3142";
  const skin = "#f2c9a0";
  const rail = "#c9d0de";
  const grip = "#1c2434";
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div
        style={{ position: "absolute", bottom: "14%", left: "50%", transform: "translateX(-50%)" }}
      >
        {/* controlled forward motion — inner wrapper owns the bob animation */}
        <div style={{ animation: "rs-bob 1.1s ease-in-out infinite" }}>
          {/* charcoal athletic wear — a red shirt vanishes into the red tile */}
          <Bust id="pm" width={PM_BUST} />
        </div>
        {/* the treadmill, in the bust's own units and standing still while she
            walks: two rails with grips and her hands on them, the crossbar, and
            the console reading its speed */}
        <svg
          data-testid="stage-treadmill"
          viewBox="0 0 120 100"
          width={PM_BUST}
          height={(PM_BUST * 100) / 120}
          aria-hidden
          focusable="false"
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            overflow: "visible",
            filter: DRAWING_SHADOW,
          }}
        >
          <Soft id={`${id}-bar`} fill={dark(rail, 0.3)} shade={dark(rail, 0.5)} dx={0} dy={-1.8}>
            <rect x="-24" y="78" width="168" height="7" rx="3.5" />
          </Soft>
          <Soft id={`${id}-posts`} fill={rail} shade={dark(rail, 0.3)} dx={-3} dy={0}>
            <rect
              x="-33.5"
              y="72.5"
              width="10.4"
              height="92"
              rx="5.2"
              transform="rotate(5 -28.8 159)"
            />
            <rect
              x="143.1"
              y="72.5"
              width="10.4"
              height="92"
              rx="5.2"
              transform="rotate(-5 148.8 159)"
            />
          </Soft>
          <Soft id={`${id}-grips`} fill={lite(grip, 0.08)} shade={grip} dx={-2.3} dy={-1.8}>
            <rect x="-26.5" y="70.2" width="39.2" height="9.7" rx="4.85" />
            <rect x="107.3" y="70.2" width="39.2" height="9.7" rx="4.85" />
          </Soft>
          <Soft id={`${id}-sleeves`} fill={shirt} shade={dark(shirt, 0.24)} dx={-2.8} dy={-1.2}>
            <rect
              x="3.5"
              y="67.8"
              width="14.4"
              height="34.6"
              rx="7.2"
              transform="rotate(-52 10.4 74.8)"
            />
            <rect
              x="102.1"
              y="67.8"
              width="14.4"
              height="34.6"
              rx="7.2"
              transform="rotate(52 109.6 74.8)"
            />
          </Soft>
          <Soft id={`${id}-fists`} fill={skin} shade={dark(skin, 0.16)} dx={-2.1} dy={-1.4}>
            <rect x="-3.5" y="65" width="17.3" height="16.7" rx="7.15" />
            <rect x="106.2" y="65" width="17.3" height="16.7" rx="7.15" />
          </Soft>
          <Soft id={`${id}-console`} fill="#2b3550" shade="#1a2236" dx={-5} dy={0}>
            <rect x="31" y="71.5" width="58" height="17" rx="5" />
          </Soft>
          <rect x="35.5" y="74.5" width="28" height="11" rx="2.6" fill="#0b1020" />
          <text
            x="49.5"
            y="83.4"
            textAnchor="middle"
            fontFamily={mono}
            fontSize="8.6"
            fontWeight="700"
            fill={pf.green}
          >
            3.5
          </text>
          <circle cx="71.5" cy="78.3" r="2.1" fill={pf.green} />
          <circle cx="78" cy="78.3" r="2.1" fill={pf.yellow} />
          <rect x="68.6" y="82.6" width="12.2" height="2.6" rx="1.3" fill="#fff" opacity="0.3" />
        </svg>
      </div>
      {/* the belt, running under her */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: "calc(14% - 6px)",
          boxSizing: "border-box",
          borderTop: "1px solid rgba(255,255,255,0.22)",
          background:
            "repeating-linear-gradient(105deg, rgba(255,255,255,0.07) 0px, rgba(255,255,255,0.07) 3px, transparent 3px, transparent 26px), rgba(11,15,25,0.72)",
        }}
      />
      {/* the roadmap's readout, above her head */}
      <Readout top="20%" left="20%" color={pf.green}>
        ROADMAP ▲ STABLE
      </Readout>
    </div>
  );
}

function DesignerScene() {
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
          background: "linear-gradient(100deg, #b85c3f 0%, #b0563a 58%, #8c452f 100%)",
          boxShadow: SOFT_SHADOW,
        }}
      />
      <div
        style={{ position: "absolute", bottom: "16%", left: "50%", transform: "translateX(-50%)" }}
      >
        {/* cream shirt + terracotta beanbag — green-on-green disappeared into the tile */}
        <Bust id="designer" width={130} />
      </div>
      {/* the beanbag's near side, which she has sunk into */}
      <div
        style={{
          position: "absolute",
          bottom: "-6%",
          left: "21%",
          width: "58%",
          height: "17%",
          borderRadius: "50% 50% 0 0 / 100% 100% 0 0",
          background: "linear-gradient(100deg, #b85c3f 0%, #b0563a 58%, #8c452f 100%)",
        }}
      />
      {/* floating design frames + cursor, beside the head */}
      <div
        style={{
          position: "absolute",
          top: "6%",
          right: "5%",
          width: "29%",
          height: "22%",
          filter: DRAWING_SHADOW,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            border: `2px solid ${pf.pink}`,
            borderRadius: "6px",
            opacity: 0.9,
          }}
        />
        <div
          style={{
            position: "absolute",
            inset: "22% 40% 20% 12%",
            border: `2px solid ${pf.teal}`,
            borderRadius: "4px",
            opacity: 0.9,
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

/** The raised arm's shapes are drawn for the left of a bust; this puts them on the right. */
const MIRROR = "translate(120 0) scale(-1 1)";

function NewHireScene() {
  const id = useDrawingId("nh");
  const shirt = "#d9a12f";
  const skin = "#f2c9a0";
  const cuff = lite(shirt, 0.5);
  const sleeve = `${MIRROR} rotate(-12 19.5 112)`;
  const palm = `${MIRROR} translate(-5.6 -3.4) rotate(-12 11.5 49)`;
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
        {/* the eager raised hand, behind the shoulder it belongs to: a sleeve,
            a cuff and an open palm, in the bust's own units */}
        <svg
          data-testid="stage-raised-hand"
          viewBox="0 0 120 100"
          width={150}
          height={125}
          aria-hidden
          focusable="false"
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            overflow: "visible",
            filter: DRAWING_SHADOW,
          }}
        >
          <Soft id={`${id}-arm`} fill={shirt} shade={dark(shirt, 0.24)} dx={-3.4} dy={0}>
            <rect x="12" y="48" width="15" height="68" rx="7.5" transform={sleeve} />
          </Soft>
          <Soft id={`${id}-hand`} fill={skin} shade={dark(skin, 0.16)} dx={-1.8} dy={-1.2}>
            <rect x="1.8" y="30" width="19.4" height="19" rx="7" transform={palm} />
            {[
              [-15, 20.5],
              [-5, 17.5],
              [5, 18],
              [15, 21.5],
            ].map(([a, y], i) => (
              <rect
                key={a}
                x={1.6 + i * 5.1}
                y={y}
                width="4.3"
                height="17"
                rx="2.15"
                transform={`${palm} rotate(${a} 11.4 44)`}
              />
            ))}
            <rect
              x="19.2"
              y="31.5"
              width="4.6"
              height="13"
              rx="2.3"
              transform={`${palm} rotate(38 21.5 44)`}
            />
          </Soft>
          <Soft id={`${id}-cuff`} fill={cuff} shade={dark(cuff, 0.2)} dx={-3} dy={0}>
            <rect x="10.6" y="46" width="17.8" height="7.6" rx="3.8" transform={sleeve} />
          </Soft>
        </svg>
        <div style={{ position: "relative" }}>
          <Bust id="new-hire" />
        </div>
      </div>
    </div>
  );
}

function MinimalistScene() {
  return (
    <div style={{ position: "absolute", inset: 0, background: wall("#e8ecef") }}>
      {/* a perfectly empty room, one small person, zero clutter */}
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)" }}>
        <Bust id="minimalist" width={96} />
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

// Renders a character's webcam scene on demand.
export function CastScene({
  id,
  parked = false,
}: {
  id: string;
  /** Park Super Dev's motorized desk. Without this his rig rides him out of
      frame on a timer, so any slide that needs all nine faces present at once
      has to ask for it. On his rig, parking is also what brings the dumbbell
      out — the desk rides or he lifts, never both. */
  parked?: boolean;
}) {
  switch (id) {
    case "dev-hero":
      return <DevHeroScene press={parked} />;
    case "ops-dev":
      return <OpsDevScene />;
    case "minimalist":
      return <MinimalistScene />;
    case "new-hire":
      return <NewHireScene />;
    case "vibemancer":
      return <VibemancerScene />;
    case "ultrawide":
      return <UltraWideScene />;
    case "qa":
      return <QaScene />;
    case "pm":
      return <PmScene />;
    case "designer":
      return <DesignerScene />;
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
