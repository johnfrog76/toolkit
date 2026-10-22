import type { CSSProperties, ReactNode } from "react";
import { GiveawayButton } from "../engine/GiveawayButton";
import { createMakeSlide } from "../engine/makeSlide";
import { Beat, Context, Say } from "../engine/PresenterNoteKit";
import type { Deck, Slide } from "./types";
import { DeckState } from "./types";
import {
  C as TK,
  STAMP,
  THEMES,
  WordmarkMark,
  TYPE,
  type CardType,
  type StampKind,
} from "./toolkit-figures";

// The Toolkit — The Commercial. A Nordic living room, rendered in SVG, that
// behaves the way the product does: an Envelope drifts in because work
// arrived, settles into the Cabinet lane its own file decides, the Ledger
// Wall inks itself from the dates the cards carry, the Evidence Shelf fills
// from what already closed, and the room's one window opens twice without the
// room changing shape: first on GitHub, where issues rest on the sill and the
// crew stands up through the glass, then — Nimbus, the Azure Butler — on
// Azure DevOps, where the cards move on their board.
//
// The order is the product's: your own cards first, then GitHub issues and
// orchestrating agents, then Azure DevOps, the previous stop, still there and
// still honest, last. The room, the register and the physics did not change
// when the order did.
//
// Register: the house default, CSS as an artform — a built world, light with a
// source, gradients allowed. Deliberately NOT the Swiss register the two
// sibling Toolkit decks use (toolkit-figures.tsx): a room made of light cannot
// be flat, and the owner wanted this one "in the house style of the wasteland".
//
// What is shared and what is quoted:
//   - The Envelope, the Postmark and the card-type tabs QUOTE the sibling
//     decks' geometry and import their colour tokens (TK, TYPE, STAMP), so one
//     object means one thing across the family; the SVG port lives here
//     because this deck composes in a 1600×900 Scene and the sibling's atoms
//     are HTML in px space.
//   - Nimbus QUOTES the Shelf Guardians' ButlerGlyph (chrome dome, recessed
//     visor, one lit LED eye that sweeps, the bow tie) and dresses it. Drawn
//     here rather than added to shelf-guardians-figures.tsx because that file
//     is under five published decks (the owner: don't disrupt them).
//   - Gillbert, the goldfish, is QUOTED too (the Shelf Guardians' Fish, redrawn
//     small): the same universe, on a visit.
//   - The crew in the first window QUOTES the Remote Standup's cast
//     (remote-standup-cast.tsx): the nine tints and each bust's own geometry,
//     redrawn small in this Scene, the way the product's own standup stage
//     seats them. Nothing of theirs is imported, for the reason below.
//
// This deck is built here and shown from somewhere else (the owner:
// "this deck will never be deployed here"). So it imports nothing from the
// wasteland's other deck families and nothing from the engine but the player
// contract every deck uses — it and toolkit-figures.tsx lift out together.

// ── Palette — named for what the colours MEAN in this room ───────────────────
const P = {
  // calmwood — the room's own surfaces: the Cabinet, the frames, the floor
  calmwood: "#c99f76",
  calmwoodLit: "#e3c096",
  calmwoodDeep: "#8f6a4b",
  calmwoodEdge: "#5a3f2e",
  // ink — a fact written down: the Ledger's lines, the Envelope's border
  ink: TK.ink,
  // glow — light that moves: the Aquarium, the Aurora, Nimbus's one eye
  glow: "#5fd8ff",
  glowDeep: "#1e7ea6",
  // frost — the surfaces that carry a record: the Ledger paper, the Shelf's documents
  frost: "#eef2f4",
  frostDeep: "#c9d3d9",
  // dusk — depth, shadow, and the tone the room settles into at the payoff
  dusk: "#232842",
  duskDeep: "#12152a",
  // the room at evening: a blue-grey wall, an oak floor, one warm lamp
  wall: "#4b5270",
  wallLit: "#5f6786",
  floor: "#7d5f45",
  floorDeep: "#553f2e",
  lamp: "#ffd9a0",
  night: "#0a0f22",
  water: "#0f3d52",
  waterLit: "#1f6f88",
} as const;

const MONO = "'Cascadia Code', 'Fira Code', 'Consolas', monospace";

// CSS custom properties in inline styles need one widening cast.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const v = (o: Record<string, string | number>) => o as any as CSSProperties;

// ── Copy-panel kit — house chrome (eu-nomes-figures values), this room's colours
function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        fontFamily: MONO,
        fontSize: "0.75rem",
        fontWeight: 700,
        letterSpacing: "0.16em",
        textTransform: "uppercase",
        color: P.glow,
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
          backgroundColor: P.glow,
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
        fontSize: "clamp(1.45rem, 6vw, 2.5rem)",
        fontWeight: 800,
        lineHeight: "1.22em",
        margin: "0 0 20px 0",
        background: `linear-gradient(172deg, #ffffff 0%, ${P.frost} 30%, ${P.calmwoodLit} 62%, ${P.glow} 100%)`,
        WebkitBackgroundClip: "text",
        WebkitTextFillColor: "transparent",
        backgroundClip: "text",
        filter: "drop-shadow(0 0 14px rgba(95,216,255,0.25))",
        whiteSpace: "pre-line",
      }}
    >
      {children}
    </h2>
  );
}

function Lead({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        fontSize: "1.25rem",
        lineHeight: 1.75,
        color: "#d9e0e6",
        margin: "0 0 24px 0",
        whiteSpace: "pre-line",
      }}
    >
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

// ── Keyframes — one block, mounted inside every Stage ────────────────────────
// Every entrance animates FROM a hidden keyframe with `backwards` fill and the
// visible state as the base style, so a phone frame that skips the active
// window still lands the element (slide-deck-traps.md). Anything invisible at
// rest carries `opacity: 0` in its static style, for the frozen poster wall.
function DeckKeyframes() {
  return (
    <style>{`
      /* the room settling into place — furniture arrives, then stays */
      @keyframes tc-settle   { from { opacity: 0; transform: translateY(18px); } to { opacity: 1; transform: none; } }
      @keyframes tc-fade     { from { opacity: 0; } to { opacity: 1; } }
      /* the aurora through the high window — slow, indifferent to the room */
      @keyframes tc-aurora   { 0%, 100% { transform: translateX(-28px); } 50% { transform: translateX(28px); } }
      /* the aquarium's light on the far wall and the cabinet — drifting, never still */
      @keyframes tc-spill    { 0%, 100% { opacity: 0.32; transform: translateX(0); } 50% { opacity: 0.5; transform: translateX(26px); } }
      /* an Envelope arriving: x carries it in, y is the sine it rides — two
         wrappers so the two transforms never fight */
      @keyframes tc-driftx   { from { transform: translateX(var(--dx)); } to { transform: translateX(0); } }
      @keyframes tc-drifty   { 0% { transform: translateY(-140px); } 34% { transform: translateY(22px); } 68% { transform: translateY(-34px); } 100% { transform: translateY(0); } }
      /* the formation, holding: every Envelope on the same breath */
      @keyframes tc-hover    { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-7px); } }
      /* a Postmark pressing — the same 370ms as the sibling decks' stamp */
      @keyframes tc-press    { 0% { transform: scale(1.8) rotate(-12deg); opacity: 0; } 68% { transform: scale(0.94) rotate(-12deg); opacity: 1; } 100% { transform: scale(1) rotate(-12deg); opacity: 1; } }
      /* an Envelope gliding into the lane its file already chose */
      @keyframes tc-glide    { from { transform: translate(var(--gx), var(--gy)); } to { transform: translate(0, 0); } }
      /* a line inking itself onto the wall */
      @keyframes tc-inkin    { from { stroke-dashoffset: 1; } to { stroke-dashoffset: 0; } }
      /* the pipe under the floor, carrying what closed */
      @keyframes tc-flow     { to { stroke-dashoffset: -48; } }
      /* a document settling onto the shelf */
      @keyframes tc-land     { from { opacity: 0; transform: translateY(-80px); } to { opacity: 1; transform: none; } }
      /* Nimbus stepping in at the room's edge */
      @keyframes tc-walk     { from { opacity: 0; transform: translateX(-340px); } to { opacity: 1; transform: none; } }
      /* a tile of the crew popping in, as the standup's own tiles do */
      @keyframes tc-pop      { 0% { transform: scale(0.7); opacity: 0; } 70% { transform: scale(1.04); opacity: 1; } 100% { transform: scale(1); opacity: 1; } }
      /* the sash lifting — the base state is open; this plays it from closed */
      @keyframes tc-sash     { from { transform: translateY(104px); } to { transform: translateY(0); } }
      /* Nimbus's breath — slower than anything else moving in the room */
      @keyframes tc-breathe  { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.02); } }
      /* the LED sweeping the visor — watching is a verb */
      @keyframes tc-eyescan  { 0%, 100% { transform: translateX(-16px); } 50% { transform: translateX(16px); } }
      /* the eye brightening one step when he opens the window — never more */
      @keyframes tc-eyestep  { 0%, 30% { opacity: 0.4; } 44%, 80% { opacity: 1; } 96%, 100% { opacity: 0.4; } }
      /* the tracker's own cloud, outside the glass */
      @keyframes tc-cloud    { 0%, 100% { transform: translateX(0); } 50% { transform: translateX(18px); } }
      /* leaves answering the room's air */
      @keyframes tc-leaf     { 0%, 100% { transform: rotate(-2deg); } 50% { transform: rotate(2deg); } }
      /* the ward — the one motion no schedule owns; he turns at the far end */
      @keyframes tc-fishdrift { 0%, 100% { transform: translate(0, 0) scaleX(1); } 46% { transform: translate(var(--fx), -6px) scaleX(1); } 50% { transform: translate(var(--fx), -6px) scaleX(-1); } 96% { transform: translate(0, 0) scaleX(-1); } }
      @keyframes tc-bubble    { 0% { transform: translateY(0); opacity: 0; } 15% { opacity: 0.7; } 85% { opacity: 0.5; } 100% { transform: translateY(var(--by)); opacity: 0; } }
      /* water catching the hood light */
      @keyframes tc-shimmer  { 0%, 100% { opacity: 0.35; transform: translateX(0); } 50% { opacity: 0.7; transform: translateX(10px); } }
    `}</style>
  );
}

// ── Stage and Scene ──────────────────────────────────────────────────────────
// Every composition draws on one 1600×900 canvas, sliced to the panel: the
// desktop crops ~260px off each side, the phone ~315px, so load-bearing atoms
// live inside x≈320–1280 and only atmosphere bleeds past it. No on-art text
// but the ids and numbers the objects themselves wear.
const EVENING_BG = `linear-gradient(180deg, #2b3050 0%, #3a4060 100%)`;
const DUSK_BG = `linear-gradient(180deg, #171b30 0%, ${P.dusk} 100%)`;

function Stage({ children, bg = EVENING_BG }: { children: ReactNode; bg?: string }) {
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
      <DeckKeyframes />
      {children}
    </div>
  );
}

function Scene({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 1600 900"
      preserveAspectRatio="xMidYMid slice"
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}
    >
      <defs>
        {/* the chrome of a small steward — the Shelf Guardians' gradient, quoted */}
        <linearGradient id="tc-chrome" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="#5c7280" />
          <stop offset="45%" stopColor="#b9ccd6" />
          <stop offset="60%" stopColor="#8ba2ae" />
          <stop offset="100%" stopColor="#3f525c" />
        </linearGradient>
        {/* the tank's water: lit at the surface by the hood, deep at the gravel */}
        <linearGradient id="tc-water" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={P.waterLit} />
          <stop offset="100%" stopColor={P.water} />
        </linearGradient>
        {/* the aquarium's light on everything to its right */}
        <radialGradient id="tc-spill" cx="0%" cy="50%" r="100%">
          <stop offset="0%" stopColor={P.glow} stopOpacity="0.55" />
          <stop offset="55%" stopColor={P.glow} stopOpacity="0.12" />
          <stop offset="100%" stopColor={P.glow} stopOpacity="0" />
        </radialGradient>
        {/* one warm lamp, somewhere above the room */}
        <radialGradient id="tc-lamp" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor={P.lamp} stopOpacity="0.22" />
          <stop offset="100%" stopColor={P.lamp} stopOpacity="0" />
        </radialGradient>
        {/* the small wall light over the reminder that is due today */}
        <radialGradient id="tc-pin" cx="50%" cy="0%" r="100%">
          <stop offset="0%" stopColor={P.lamp} stopOpacity="0.55" />
          <stop offset="100%" stopColor={P.lamp} stopOpacity="0" />
        </radialGradient>
        {/* the night outside the window */}
        <linearGradient id="tc-night" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#060a1a" />
          <stop offset="100%" stopColor="#12203a" />
        </linearGradient>
        {/* the one warm arc in the water — Gillbert's colour, quoted */}
        <linearGradient id="tc-fish" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="#e8853c" />
          <stop offset="100%" stopColor="#c25a26" />
        </linearGradient>
        <filter id="tc-blur" x="-60%" y="-60%" width="220%" height="220%">
          <feGaussianBlur stdDeviation="18" />
        </filter>
        <filter id="tc-soft" x="-30%" y="-30%" width="160%" height="160%">
          <feGaussianBlur stdDeviation="6" />
        </filter>
        {/* a crew tile that is not speaking: grayscale, as the standup's stage ghosts a seat */}
        <filter id="tc-grey">
          <feColorMatrix type="saturate" values="0" />
        </filter>
      </defs>
      {children}
    </svg>
  );
}

// ── The room ─────────────────────────────────────────────────────────────────
// One floor plan, every slide. Left to right: the window (and, under it, the
// aquarium), Nimbus's place by the window, the Cabinet, then the wall unit —
// the Ledger, the reminder rail under it, the Evidence Shelf — with the Sofa
// beneath and a plant at the far right. The aurora runs through a high band
// of glass along the top. Acts are lighting, not new rooms.
const FLOOR_Y = 690;
const CABINET_X = 630;
const CABINET_W = 240;
const CABINET_TOP = 366;
const LANE_H = 60;
const LANE_PITCH = 64;
const LANE_Y = (i: number) => CABINET_TOP + 16 + i * LANE_PITCH;
/** Where a card stands in lane `lane`, slot `slot`: on the lip, from the left post. */
const inLane = (lane: number, slot: number, w = 64) => ({
  x: CABINET_X + 40 + slot * (w + 8),
  y: LANE_Y(lane) + LANE_H - 8 - Math.round(w * 0.62),
});

// The lanes as open pigeonholes, top to bottom, each wearing the colour a
// card's stamp wears when it belongs there — the colour echo is the only
// label. Open, not drawers: a pulled drawer hides the one below it, and a
// sorting cabinet keeps every card in sight. The cabinet never moves.
const LANES = [
  { key: "active", lamp: P.frost },
  { key: "in-progress", lamp: STAMP.commit },
  { key: "code-review", lamp: STAMP.pr },
  { key: "done", lamp: "#0d1018" },
] as const;

// The room sits 50 canvas px lower than its own coordinates say: air above
// the high glass, less bare floor below the furniture. Cameras frame in
// post-shift canvas coordinates.
const ROOM_DY = 50;
function Room({ children }: { children: ReactNode }) {
  return <g transform={`translate(0 ${ROOM_DY})`}>{children}</g>;
}

function Wall({ dusk = false }: { dusk?: boolean }) {
  return (
    <g>
      <rect x={-40} y={-140} width={1680} height={FLOOR_Y + 140} fill={dusk ? P.dusk : P.wall} />
      {/* the wall's own light: brighter at the middle, where the lamp is */}
      <rect
        x={-40}
        y={-140}
        width={1680}
        height={FLOOR_Y + 140}
        fill={dusk ? "#2b3050" : P.wallLit}
        opacity={0.5}
      />
      <ellipse cx={820} cy={430} rx={760} ry={420} fill="url(#tc-lamp)" opacity={dusk ? 0.55 : 1} />
      {/* skirting, floor, boards */}
      <rect x={-40} y={FLOOR_Y - 10} width={1680} height={12} fill={P.calmwoodEdge} />
      <rect x={-40} y={FLOOR_Y} width={1680} height={340} fill={dusk ? "#4a3729" : P.floor} />
      {Array.from({ length: 12 }, (_, i) => (
        <line
          key={i}
          x1={-40 + i * 150}
          y1={FLOOR_Y + 2}
          x2={-40 + i * 150 - 90}
          y2={FLOOR_Y + 340}
          stroke={P.floorDeep}
          strokeWidth="3"
          opacity="0.45"
        />
      ))}
      <rect x={-40} y={FLOOR_Y} width={1680} height={340} fill="url(#tc-lamp)" opacity={0.6} />
    </g>
  );
}

// The aurora, through a band of glass high on the wall — a Nordic room's
// second light source, slow and indifferent to anything happening below it.
function AuroraBand({ still = false, dim = false }: { still?: boolean; dim?: boolean }) {
  const ribbon =
    "M -60 112 C 180 40 360 136 620 78 C 860 24 1060 130 1300 70 C 1440 36 1560 96 1680 66";
  return (
    <g transform="translate(0 -32)">
      <rect x={-40} y={28} width={1680} height={116} fill="url(#tc-night)" />
      {Array.from({ length: 22 }, (_, i) => (
        <circle
          key={i}
          cx={((i * 173) % 1640) - 20}
          cy={40 + ((i * 53) % 90)}
          r={i % 5 === 0 ? 1.8 : 1.1}
          fill="#dfe9ff"
          opacity={0.55}
        />
      ))}
      <g
        style={{ animation: still ? undefined : "tc-aurora 16s ease-in-out infinite" }}
        opacity={dim ? 0.7 : 1}
      >
        <path
          d={ribbon}
          fill="none"
          stroke={P.glow}
          strokeWidth="46"
          strokeLinecap="round"
          opacity="0.22"
          filter="url(#tc-blur)"
        />
        <path
          d={ribbon}
          fill="none"
          stroke={P.glow}
          strokeWidth="16"
          strokeLinecap="round"
          opacity="0.45"
          filter="url(#tc-soft)"
        />
        <path
          d={ribbon}
          fill="none"
          stroke="#dffaff"
          strokeWidth="3"
          strokeLinecap="round"
          opacity="0.6"
        />
      </g>
      {/* mullions and rails — oak, the room's own wood */}
      <rect x={-40} y={22} width={1680} height={8} fill={P.calmwoodDeep} />
      <rect x={-40} y={142} width={1680} height={10} fill={P.calmwoodDeep} />
      {Array.from({ length: 9 }, (_, i) => (
        <rect key={i} x={-40 + i * 210} y={22} width={8} height={130} fill={P.calmwoodDeep} />
      ))}
    </g>
  );
}

// The window on the left wall: double-hung, oak, the night and the tracker's
// own cloud outside it. `open` draws the lower sash lifted; `lifting` plays
// the lift from closed on entry. `view` is what is outside the glass instead
// of the night: the first window shows the crew through it.
function Window({
  open = false,
  lifting = false,
  still = false,
  cloud = 0.35,
  view,
}: {
  open?: boolean;
  lifting?: boolean;
  still?: boolean;
  cloud?: number;
  view?: ReactNode;
}) {
  const x = 330,
    y = 190,
    w = 170,
    h = 260;
  const lower = (
    <g>
      <rect
        x={x + 8}
        y={y + h / 2}
        width={w - 16}
        height={h / 2 - 8}
        fill="url(#tc-night)"
        opacity={0.55}
      />
      <rect
        x={x + 8}
        y={y + h / 2}
        width={w - 16}
        height={h / 2 - 8}
        fill="none"
        stroke={P.calmwoodLit}
        strokeWidth="8"
      />
      <rect x={x + w / 2 - 3} y={y + h / 2} width={6} height={h / 2 - 8} fill={P.calmwoodLit} />
      <rect x={x + 8} y={y + h / 2 - 4} width={w - 16} height={10} fill={P.calmwood} />
    </g>
  );
  return (
    <g>
      {/* the night outside, and a cloud — Nimbus's cloud — drifting past;
          or, through the first window, the crew */}
      <rect x={x} y={y} width={w} height={h} fill="url(#tc-night)" />
      {view}
      <g style={{ animation: still || view ? undefined : "tc-cloud 18s ease-in-out infinite" }}>
        <ellipse
          cx={x + 70}
          cy={y + 150}
          rx={54}
          ry={26}
          fill={P.glow}
          opacity={view ? 0 : cloud}
          filter="url(#tc-blur)"
        />
        <ellipse
          cx={x + 60}
          cy={y + 156}
          rx={40}
          ry={18}
          fill="#bfefff"
          opacity={view ? 0 : cloud * 0.8}
          filter="url(#tc-soft)"
        />
      </g>
      {!view &&
        [
          [22, 28],
          [120, 46],
          [66, 70],
          [140, 110],
          [30, 210],
          [110, 236],
        ].map(([sx, sy], i) => (
          <circle
            key={i}
            cx={x + sx}
            cy={y + sy}
            r={i % 3 === 0 ? 1.8 : 1.2}
            fill="#dfe9ff"
            opacity="0.7"
          />
        ))}
      {/* the upper sash, fixed */}
      <rect
        x={x + 8}
        y={y + 8}
        width={w - 16}
        height={h / 2 - 8}
        fill="none"
        stroke={P.calmwoodLit}
        strokeWidth="8"
      />
      <rect x={x + w / 2 - 3} y={y + 8} width={6} height={h / 2 - 8} fill={P.calmwoodLit} />
      {/* the lower sash — lifted when open; the lift is played from closed */}
      {open ? (
        <g transform="translate(0 -104)">
          <g
            style={{
              animation: lifting
                ? "tc-sash 1.1s cubic-bezier(0.25, 0.46, 0.45, 0.94) 1.9s backwards"
                : undefined,
            }}
          >
            {lower}
          </g>
        </g>
      ) : (
        lower
      )}
      {/* the frame and the sill */}
      <rect x={x} y={y} width={w} height={h} fill="none" stroke={P.calmwood} strokeWidth="14" />
      <rect x={x - 14} y={y + h} width={w + 28} height={14} fill={P.calmwood} />
      <rect x={x - 14} y={y + h + 14} width={w + 28} height={5} fill={P.calmwoodEdge} />
    </g>
  );
}

// Gillbert — the Shelf Guardians' goldfish, quoted small: the body's warm
// arc, the tail trailing, one wide-open eye, a smile, bubbles on his own
// time. Anchor: body centre; he drifts on --fx and turns at the far end.
function Goldfish({
  x,
  y,
  s = 1,
  driftX = 44,
  dur = 12,
  still = false,
}: {
  x: number;
  y: number;
  s?: number;
  driftX?: number;
  dur?: number;
  still?: boolean;
}) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <g
        style={
          still
            ? undefined
            : v({
                "--fx": `${driftX}px`,
                animation: `tc-fishdrift ${dur}s ease-in-out infinite`,
                transformOrigin: "0px 0px",
              })
        }
      >
        <path
          d="M -22 0 C -38 -14 -46 -12 -52 -18 C -48 -6 -48 6 -52 18 C -46 12 -38 14 -22 0 Z"
          fill="#c25a26"
          opacity="0.9"
        />
        <ellipse cx="0" cy="0" rx="26" ry="13" fill="url(#tc-fish)" />
        <path d="M -6 -11 C -2 -20 8 -20 12 -13 Z" fill="#c25a26" />
        <path d="M 2 11 C 4 17 10 17 12 12 Z" fill="#c25a26" opacity="0.8" />
        <path
          d="M 10 -8 C 14 -3 14 3 10 8"
          fill="none"
          stroke="#5e2c12"
          strokeWidth="1.8"
          opacity="0.6"
        />
        <circle cx="16" cy="-4" r="4.6" fill="#fdf6e8" />
        <circle cx="17.2" cy="-3.6" r="2.4" fill={P.night} />
        <circle cx="18" cy="-4.6" r="0.9" fill="#ffffff" />
        <path
          d="M 21 4 C 24 7.5 27.5 6.5 29 2.5"
          fill="none"
          stroke={P.night}
          strokeWidth="1.8"
          strokeLinecap="round"
          opacity="0.75"
        />
        {!still &&
          [0, 1, 2].map((i) => (
            <g
              key={i}
              style={v({
                "--by": `-${34 + i * 14}px`,
                animation: `tc-bubble ${3.4 + i * 0.9}s ease-out ${-i * 1.3}s infinite`,
              })}
            >
              <circle
                cx={31 + i * 4}
                cy={-6 - i * 2}
                r={2.2 + (i % 2)}
                fill="none"
                stroke="#a8cbd8"
                strokeWidth="1.4"
                opacity="0.8"
              />
            </g>
          ))}
      </g>
    </g>
  );
}

// The aquarium under the window: a planted tank on a low oak stand, one
// resident — Gillbert, on a visit — and a hood light that is where the
// room's blue comes from. Its spill is drawn separately, over the furniture.
function Aquarium({ still = false }: { still?: boolean }) {
  const x = 335,
    w = 160,
    top = 490,
    bottom = 640;
  return (
    <g>
      {/* the stand */}
      <rect x={320} y={bottom} width={190} height={14} rx={3} fill={P.calmwood} />
      <rect
        x={334}
        y={bottom + 14}
        width={12}
        height={FLOOR_Y - bottom - 14}
        fill={P.calmwoodDeep}
      />
      <rect
        x={484}
        y={bottom + 14}
        width={12}
        height={FLOOR_Y - bottom - 14}
        fill={P.calmwoodDeep}
      />
      <rect x={334} y={bottom + 40} width={162} height={8} fill={P.calmwoodDeep} />
      {/* the water */}
      <rect x={x} y={top + 14} width={w} height={bottom - top - 14} fill="url(#tc-water)" />
      {/* gravel and plants */}
      <ellipse cx={x + w / 2} cy={bottom - 6} rx={w / 2 - 6} ry={10} fill="#2e2c22" />
      {Array.from({ length: 8 }, (_, i) => (
        <circle
          key={i}
          cx={x + 16 + i * 18}
          cy={bottom - 8 + ((i * 7) % 6)}
          r={3 + (i % 3)}
          fill={i % 2 ? "#3f3b2c" : "#4a4536"}
        />
      ))}
      <g
        style={{
          transformOrigin: `${x + 34}px ${bottom - 10}px`,
          animation: still ? undefined : "tc-leaf 7s ease-in-out infinite",
        }}
      >
        <path
          d={`M ${x + 34} ${bottom - 10} C ${x + 26} ${bottom - 60} ${x + 40} ${bottom - 96} ${x + 30} ${bottom - 120}`}
          fill="none"
          stroke="#3f8a54"
          strokeWidth="5"
          strokeLinecap="round"
        />
        <path
          d={`M ${x + 34} ${bottom - 10} C ${x + 46} ${bottom - 50} ${x + 58} ${bottom - 74} ${x + 66} ${bottom - 100}`}
          fill="none"
          stroke="#2f6b42"
          strokeWidth="4.5"
          strokeLinecap="round"
        />
        <path
          d={`M ${x + 34} ${bottom - 10} C ${x + 20} ${bottom - 40} ${x + 8} ${bottom - 60} ${x + 4} ${bottom - 84}`}
          fill="none"
          stroke="#2f6b42"
          strokeWidth="4"
          strokeLinecap="round"
        />
      </g>
      <g
        style={{
          transformOrigin: `${x + 132}px ${bottom - 10}px`,
          animation: still ? undefined : "tc-leaf 8s ease-in-out 1.2s infinite",
        }}
      >
        <path
          d={`M ${x + 132} ${bottom - 10} C ${x + 128} ${bottom - 40} ${x + 140} ${bottom - 62} ${x + 138} ${bottom - 82}`}
          fill="none"
          stroke="#3f8a54"
          strokeWidth="4.5"
          strokeLinecap="round"
        />
        <path
          d={`M ${x + 132} ${bottom - 10} C ${x + 120} ${bottom - 34} ${x + 112} ${bottom - 52} ${x + 116} ${bottom - 70}`}
          fill="none"
          stroke="#2f6b42"
          strokeWidth="4"
          strokeLinecap="round"
        />
      </g>
      {/* Gillbert — at home in any water */}
      <Goldfish x={x + 60} y={top + 78} s={0.75} driftX={44} dur={12} still={still} />
      {/* the surface, and the hood light on it */}
      <rect x={x} y={top + 12} width={w} height={4} fill="#bfefff" opacity="0.5" />
      <rect
        x={x + 30}
        y={top + 20}
        width={70}
        height={3}
        fill="#dffaff"
        opacity="0.5"
        style={{ animation: still ? undefined : "tc-shimmer 4s ease-in-out infinite" }}
      />
      {/* glass and hood */}
      <rect
        x={x}
        y={top + 12}
        width={w}
        height={bottom - top - 12}
        fill="none"
        stroke="#a8cbd8"
        strokeWidth="3"
        opacity="0.5"
      />
      <rect x={x - 4} y={top} width={w + 8} height={14} rx={3} fill="#2a3340" />
      <rect x={x + 6} y={top + 12} width={w - 12} height={3} fill={P.glow} opacity="0.9" />
      <path
        d={`M ${x + 2} ${top + 26} C ${x + 8} ${top + 60} ${x + 8} ${top + 100} ${x + 4} ${bottom - 20}`}
        fill="none"
        stroke="#dceef6"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.3"
      />
    </g>
  );
}

// The aquarium's light, landing on everything to its right — the cabinet
// most of all. Light with a source: it lives over the furniture, screened.
function AquariumSpill({ still = false }: { still?: boolean }) {
  return (
    <g
      style={{
        mixBlendMode: "screen",
        animation: still ? undefined : "tc-spill 9s ease-in-out infinite",
      }}
      opacity={0.4}
    >
      <ellipse cx={500} cy={560} rx={560} ry={240} fill="url(#tc-spill)" />
    </g>
  );
}

// ── Atom: Envelope — one card, one file. The sibling decks' object, ported to
// SVG: paper, an ink border, the V of the flap, its type on a post-it at the
// corner, its id small in the corner — and every Postmark it has collected.
function Envelope({
  x,
  y,
  w = 110,
  type,
  id,
  marks = [],
  still = false,
  markDelay,
}: {
  x: number;
  y: number;
  w?: number;
  type?: CardType;
  id?: string;
  marks?: Array<{ kind?: StampKind; text?: string }>;
  still?: boolean;
  /** stamps press on entry, this many seconds in; omit for stamps already dry */
  markDelay?: number;
}) {
  const h = Math.round(w * 0.62);
  const tab = Math.max(18, Math.round(w * 0.22));
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x={3} y={3} width={w} height={h} fill="#000" opacity="0.28" />
      <rect x={0} y={0} width={w} height={h} fill={TK.paper} stroke={TK.ink} strokeWidth="2" />
      <polyline
        points={`2,2 ${w / 2},${h * 0.5} ${w - 2},2`}
        fill="none"
        stroke={TK.ink}
        strokeWidth="2"
      />
      {type && (
        <g transform={`translate(-5 -7) rotate(-8 ${tab / 2} ${tab / 2})`}>
          <rect x={2} y={2} width={tab} height={tab} fill="#000" opacity="0.18" />
          <rect x={0} y={0} width={tab} height={tab} fill={TYPE[type]} />
          <rect
            x={tab * 0.18}
            y={tab * 0.34}
            width={tab * 0.6}
            height={tab * 0.1}
            fill="rgba(28,28,31,0.14)"
          />
          <rect
            x={tab * 0.18}
            y={tab * 0.56}
            width={tab * 0.42}
            height={tab * 0.1}
            fill="rgba(28,28,31,0.14)"
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
          fill={TK.inkSoft}
        >
          {id}
        </text>
      )}
      {marks.map((m, i) => (
        <Postmark
          key={i}
          x={w - 14 + i * 22}
          y={5}
          size={Math.round(w * (m.text ? 0.48 : 0.34))}
          kind={m.kind}
          text={m.text}
          delay={markDelay != null ? markDelay + i * 0.5 : undefined}
          still={still}
        />
      ))}
    </g>
  );
}

// ── Atom: Postmark — a token written into the file, the moment a state
// becomes true. A rubber stamp: paper face, double ring, ink at stamp density.
// A commit is the green check; a pull request the purple merge glyph; a
// close the heavier check; a tracker number is its number.
function Postmark({
  x,
  y,
  size = 36,
  kind,
  text,
  delay,
  still = false,
}: {
  x: number;
  y: number;
  size?: number;
  kind?: StampKind;
  text?: string;
  delay?: number;
  still?: boolean;
}) {
  const ink = kind ? STAMP[kind] : TK.ink;
  const r = size / 2;
  const g = size * 0.56;
  const glyph =
    kind === "commit" ? (
      <path
        d="M5 12.5 L10 17 L19 7"
        fill="none"
        stroke={ink}
        strokeWidth="3.2"
        strokeLinecap="round"
        strokeLinejoin="round"
        transform={`translate(${-g / 2} ${-g / 2}) scale(${g / 24})`}
      />
    ) : kind === "pr" ? (
      <g transform={`translate(${-g / 2} ${-g / 2}) scale(${g / 24})`}>
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
      </g>
    ) : kind === "closed" ? (
      <path
        d="M4 12.5 L10 18 L20 6"
        fill="none"
        stroke={ink}
        strokeWidth="4"
        strokeLinecap="round"
        strokeLinejoin="round"
        transform={`translate(${-g / 2} ${-g / 2}) scale(${g / 24})`}
      />
    ) : (
      <text
        x={0}
        y={0}
        textAnchor="middle"
        dominantBaseline="central"
        fontFamily="'Helvetica Neue', Helvetica, Arial, sans-serif"
        fontWeight="800"
        fontSize={Math.max(7, size * 0.2)}
        letterSpacing="0.04em"
        fill={ink}
      >
        {text}
      </text>
    );
  return (
    <g transform={`translate(${x} ${y})`}>
      <g
        style={{
          transformBox: "fill-box",
          transformOrigin: "center",
          transform: "rotate(-12deg)",
          animation:
            delay != null && !still
              ? `tc-press 0.37s cubic-bezier(0.2, 0.8, 0.2, 1) ${delay}s backwards`
              : undefined,
        }}
      >
        <circle cx={r * 0.08} cy={r * 0.08} r={r} fill="#000" opacity="0.22" />
        <circle cx={0} cy={0} r={r} fill={TK.paper} stroke={ink} strokeWidth="2.5" />
        <circle cx={0} cy={0} r={r - 4} fill="none" stroke={ink} strokeWidth="1.4" />
        <g opacity="0.92">{glyph}</g>
      </g>
    </g>
  );
}

// ── Atom: Cabinet — the board's lanes as open pigeonholes in a tall
// Scandinavian chest on tapered legs; each lane's lamp, on its post, wears
// the colour of the stamp that sends a card there. A card settles into a
// lane because of what its file says, never because a hand placed it, and
// every card stays in sight. The cabinet itself never moves.
function Cabinet({ children }: { children?: ReactNode }) {
  const x = CABINET_X,
    w = CABINET_W;
  return (
    <g>
      {/* shadow on the wall, the legs, the carcass */}
      <rect
        x={x + 10}
        y={CABINET_TOP + 10}
        width={w}
        height={FLOOR_Y - CABINET_TOP - 40}
        fill="#000"
        opacity="0.22"
        filter="url(#tc-soft)"
      />
      <path
        d={`M ${x + 14} ${FLOOR_Y - 40} L ${x + 30} ${FLOOR_Y - 40} L ${x + 24} ${FLOOR_Y} L ${x + 4} ${FLOOR_Y} Z`}
        fill={P.calmwoodDeep}
      />
      <path
        d={`M ${x + w - 14} ${FLOOR_Y - 40} L ${x + w - 30} ${FLOOR_Y - 40} L ${x + w - 24} ${FLOOR_Y} L ${x + w - 4} ${FLOOR_Y} Z`}
        fill={P.calmwoodDeep}
      />
      <rect
        x={x}
        y={CABINET_TOP}
        width={w}
        height={FLOOR_Y - CABINET_TOP - 40}
        rx={4}
        fill={P.calmwood}
      />
      <rect x={x - 6} y={CABINET_TOP - 8} width={w + 12} height={12} rx={3} fill={P.calmwoodLit} />
      <rect x={x} y={CABINET_TOP + 4} width={w} height={6} fill={P.calmwoodDeep} opacity="0.5" />
      {LANES.map((lane, i) => {
        const dy = LANE_Y(i);
        return (
          <g key={lane.key}>
            {/* the pigeonhole: its dark back, the lip a card stands on, and
                the lane's lamp on the post beside it */}
            <rect x={x + 34} y={dy} width={w - 48} height={LANE_H} fill="#4a3628" />
            <rect x={x + 34} y={dy} width={w - 48} height={6} fill="#2e2118" />
            <rect
              x={x + 34}
              y={dy + LANE_H - 8}
              width={w - 48}
              height={8}
              fill={P.calmwoodLit}
              stroke={P.calmwoodDeep}
              strokeWidth="1.2"
            />
            <circle
              cx={x + 24}
              cy={dy + LANE_H / 2}
              r={6}
              fill={lane.lamp}
              stroke={P.calmwoodEdge}
              strokeWidth="1.5"
            />
          </g>
        );
      })}
      {children}
    </g>
  );
}

// ── Atom: Ledger Wall — Daily. A framed, ruled board on the wall: five rows,
// one per working day, and on each a segment per card that was open that day,
// in the card's own type colour — ink from facts the Envelopes already carry.
type LedgerRow = { cards: CardType[]; closed?: boolean };

const WEEK: LedgerRow[] = [
  { cards: ["story", "task"] },
  { cards: ["story", "bug"] },
  { cards: ["bug", "story", "spike"] },
  { cards: ["bug", "story", "story"] },
  { cards: ["story", "bug", "story", "story"], closed: true },
];

// The payoff wall wears the product's Sunny theme — the one the owner drew: its
// cream page as the paper, its disc on the mark. The identity's colours are
// the theme's, never this room's.
const SUNNY = THEMES.find((t) => t.id === "sunny") ?? THEMES[4];
const SANS = "'Helvetica Neue', Helvetica, Arial, sans-serif";
function LedgerWall({
  rows,
  inking = false,
  delay = 0.6,
  empty = false,
  titleCard = false,
}: {
  rows?: LedgerRow[];
  inking?: boolean;
  delay?: number;
  empty?: boolean;
  /** the payoff: the wall is the title card — the wordmark on its disc and
   *  the three beats writing themselves under it (the owner's sketch).
   *  No rule runs through the logo or a word; a row's rule continues only to
   *  the right of it. */
  titleCard?: boolean;
}) {
  const x = 1000,
    y = 150,
    w = 250,
    h = 210;
  const rowH = 34;
  const fade = (d: number): CSSProperties => ({
    animation: `tc-fade 0.6s ease-out ${d}s backwards`,
  });
  if (titleCard) {
    return (
      <g>
        <rect
          x={x + 6}
          y={y + 8}
          width={w}
          height={h}
          fill="#000"
          opacity="0.25"
          filter="url(#tc-soft)"
        />
        <rect x={x} y={y} width={w} height={h} fill={P.calmwood} />
        <rect x={x + 10} y={y + 10} width={w - 20} height={h - 20} fill={SUNNY.page} />
        <g style={fade(delay)}>
          <WordmarkMark x={x + 26} y={y + 62} em={32} theme="sunny" />
        </g>
        {["your spaces", "your work", "your studio"].map((line, i) => {
          const ry = y + 110 + i * 30;
          return (
            <g key={line} style={fade(delay + 0.7 + i * 0.45)}>
              <rect x={x + 22} y={ry - 5} width={10} height={10} fill={P.ink} opacity="0.75" />
              <text
                x={x + 44}
                y={ry + 6}
                fontFamily={SANS}
                fontSize="18"
                fontWeight="700"
                fill={P.ink}
              >
                {line}
              </text>
              <line
                x1={x + 150}
                y1={ry}
                x2={x + w - 20}
                y2={ry}
                stroke={P.frostDeep}
                strokeWidth="1.5"
              />
            </g>
          );
        })}
      </g>
    );
  }
  return (
    <g>
      <rect
        x={x + 6}
        y={y + 8}
        width={w}
        height={h}
        fill="#000"
        opacity="0.25"
        filter="url(#tc-soft)"
      />
      <rect x={x} y={y} width={w} height={h} fill={P.calmwood} />
      <rect x={x + 10} y={y + 10} width={w - 20} height={h - 20} fill={P.frost} />
      {Array.from({ length: 5 }, (_, i) => {
        const ry = y + 28 + i * rowH;
        return (
          <g key={i}>
            {/* the day's tick, and its rule */}
            <rect x={x + 22} y={ry - 5} width={10} height={10} fill={P.ink} opacity="0.75" />
            <line
              x1={x + 40}
              y1={ry}
              x2={x + w - 20}
              y2={ry}
              stroke={P.frostDeep}
              strokeWidth="1.5"
            />
            {!empty &&
              (rows ?? WEEK)[i]?.cards.map((t, j) => (
                <line
                  key={j}
                  x1={x + 44 + j * 42}
                  y1={ry}
                  x2={x + 44 + j * 42 + 32}
                  y2={ry}
                  stroke={TYPE[t]}
                  strokeWidth="9"
                  strokeLinecap="round"
                  pathLength={1}
                  strokeDasharray={1}
                  style={{
                    strokeDashoffset: 0,
                    animation: inking
                      ? `tc-inkin 0.32s ease-out ${delay + i * 0.34 + j * 0.09}s backwards`
                      : undefined,
                  }}
                />
              ))}
            {!empty && (rows ?? WEEK)[i]?.closed && (
              <path
                d={`M ${x + w - 44} ${ry} L ${x + w - 38} ${ry + 6} L ${x + w - 28} ${ry - 8}`}
                fill="none"
                stroke={P.ink}
                strokeWidth="3.5"
                strokeLinecap="round"
                strokeLinejoin="round"
                pathLength={1}
                strokeDasharray={1}
                style={{
                  strokeDashoffset: 0,
                  animation: inking
                    ? `tc-inkin 0.3s ease-out ${delay + 5 * 0.34 + 0.2}s backwards`
                    : undefined,
                }}
              />
            )}
          </g>
        );
      })}
    </g>
  );
}

// ── Atom: Reminder Rail — a brass rail under the Ledger with three hooks:
// overdue, today, later. A reminder hangs on the hook its due date puts it
// on, worked out when the wall is read; a small light over the middle hook
// is the one thing due today. Nothing here nags.
function ReminderRail({ tagOn = 1, lit = false }: { tagOn?: 0 | 1 | 2; lit?: boolean }) {
  const x = 1010,
    y = 392,
    w = 230;
  const hooks = [x + 40, x + w / 2, x + w - 40];
  return (
    <g>
      {/* the wall light — invisible at rest, steady when it is on */}
      <g opacity={lit ? 1 : 0}>
        <path
          d={`M ${hooks[1] - 60} ${y + 8} L ${hooks[1] + 60} ${y + 8} L ${hooks[1] + 90} ${y + 110} L ${hooks[1] - 90} ${y + 110} Z`}
          fill="url(#tc-pin)"
        />
        <rect x={hooks[1] - 16} y={y - 34} width={32} height={10} rx={3} fill="#2a3340" />
        <path
          d={`M ${hooks[1] - 20} ${y - 24} L ${hooks[1] + 20} ${y - 24} L ${hooks[1] + 14} ${y - 12} L ${hooks[1] - 14} ${y - 12} Z`}
          fill="#cfa75c"
        />
        <ellipse cx={hooks[1]} cy={y - 10} rx={12} ry={4} fill={P.lamp} opacity="0.9" />
      </g>
      <rect x={x} y={y} width={w} height={6} rx={3} fill="#cfa75c" />
      <rect x={x + 8} y={y - 3} width={6} height={12} rx={2} fill="#8a6d38" />
      <rect x={x + w - 14} y={y - 3} width={6} height={12} rx={2} fill="#8a6d38" />
      {hooks.map((hx, i) => (
        <path
          key={i}
          d={`M ${hx} ${y + 6} v 8 a 6 6 0 0 0 12 0`}
          fill="none"
          stroke="#cfa75c"
          strokeWidth="3"
          strokeLinecap="round"
        />
      ))}
      {/* the one tag, on its hook, with a string */}
      <g transform={`translate(${hooks[tagOn] + 12} ${y + 20})`}>
        <line x1={0} y1={0} x2={0} y2={14} stroke={P.frostDeep} strokeWidth="1.5" />
        <path
          d="M -14 14 L 14 14 L 14 44 L -14 44 Z"
          fill={P.frost}
          stroke={P.ink}
          strokeWidth="1.5"
        />
        <circle cx={0} cy={20} r={2.2} fill="none" stroke={P.ink} strokeWidth="1.2" />
        <rect x={-8} y={28} width={16} height={3} fill={P.ink} opacity="0.35" />
        <rect x={-8} y={35} width={10} height={3} fill={P.ink} opacity="0.35" />
      </g>
    </g>
  );
}

// ── Atom: Evidence Shelf — Reporting. A picture ledge with the period's
// documents standing on it: By the Numbers (bars), Completed Work (ticks).
// Built from what already closed; the pipe under the floor feeds it.
function Document({
  x,
  y,
  kind,
  delay,
  still = false,
}: {
  x: number;
  y: number;
  kind: "numbers" | "completed";
  delay?: number;
  still?: boolean;
}) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <g
        style={{
          animation:
            delay != null && !still
              ? `tc-land 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${delay}s backwards`
              : undefined,
        }}
      >
        <rect x={3} y={3} width={62} height={80} fill="#000" opacity="0.25" />
        <rect x={0} y={0} width={62} height={80} fill={P.frost} stroke={P.ink} strokeWidth="1.5" />
        <rect x={9} y={9} width={30} height={4} fill={P.ink} opacity="0.7" />
        {kind === "numbers" ? (
          <>
            {[26, 14, 34, 20].map((bh, i) => (
              <rect
                key={i}
                x={10 + i * 12}
                y={62 - bh}
                width={8}
                height={bh}
                fill={[TYPE.story, TYPE.bug, STAMP.commit, STAMP.pr][i]}
                stroke={P.ink}
                strokeWidth="1"
              />
            ))}
            <line x1={9} y1={63} x2={54} y2={63} stroke={P.ink} strokeWidth="1.2" />
          </>
        ) : (
          <>
            {[22, 34, 46, 58].map((ly, i) => (
              <g key={i}>
                <path
                  d={`M 10 ${ly} L 13 ${ly + 3} L 18 ${ly - 3}`}
                  fill="none"
                  stroke={STAMP.commit}
                  strokeWidth="2"
                  strokeLinecap="round"
                />
                <rect
                  x={23}
                  y={ly - 2}
                  width={[26, 18, 22, 14][i]}
                  height={3.5}
                  fill={P.ink}
                  opacity="0.3"
                />
              </g>
            ))}
          </>
        )}
      </g>
    </g>
  );
}

function Shelf({
  docs = 0,
  landing = false,
  delay = 0.8,
  still = false,
}: {
  docs?: 0 | 1 | 2;
  landing?: boolean;
  delay?: number;
  still?: boolean;
}) {
  const x = 1000,
    y = 520,
    w = 270;
  return (
    <g>
      {docs >= 1 && (
        <Document
          x={x + 40}
          y={y - 82}
          kind="numbers"
          delay={landing ? delay : undefined}
          still={still}
        />
      )}
      {docs >= 2 && (
        <Document
          x={x + 180}
          y={y - 82}
          kind="completed"
          delay={landing ? delay + 0.9 : undefined}
          still={still}
        />
      )}
      {/* the ledge's lip holds the documents upright */}
      <rect x={x} y={y - 8} width={w} height={8} fill={P.calmwoodDeep} />
      <rect x={x} y={y} width={w} height={14} rx={2} fill={P.calmwood} />
      <path
        d={`M ${x + 12} ${y + 14} L ${x + 44} ${y + 14} L ${x + 12} ${y + 46} Z`}
        fill={P.calmwoodDeep}
      />
      <path
        d={`M ${x + w - 12} ${y + 14} L ${x + w - 44} ${y + 14} L ${x + w - 12} ${y + 46} Z`}
        fill={P.calmwoodDeep}
      />
    </g>
  );
}

// ── Scene-dressing: the Pipe Run — under the floor, unseen until it needs to
// be: from the Done lane, down, along, and up into the shelf's bracket.
function PipeRun({ still = false }: { still?: boolean }) {
  // the riser climbs beside the shelf's bracket and ends under the plank,
  // where PipeFlange bolts it on (drawn after the Shelf, so it sits in front)
  const d = `M ${CABINET_X + CABINET_W / 2} ${FLOOR_Y - 40} V ${FLOOR_Y + 70} H 1004 V 528`;
  return (
    <g>
      {/* the cutaway: the floor opened along the run */}
      <rect
        x={CABINET_X + 60}
        y={FLOOR_Y + 2}
        width={1012 - CABINET_X - 40}
        height={98}
        fill={P.duskDeep}
        opacity="0.85"
      />
      <path d={d} fill="none" stroke={P.calmwoodEdge} strokeWidth="18" strokeLinejoin="round" />
      <path d={d} fill="none" stroke="#3a3f55" strokeWidth="10" strokeLinejoin="round" />
      <path
        d={d}
        fill="none"
        stroke={P.glow}
        strokeWidth="3"
        strokeLinejoin="round"
        strokeDasharray="10 14"
        opacity="0.8"
        style={{ animation: still ? undefined : "tc-flow 1.6s linear infinite" }}
      />
      {/* joints */}
      {[
        [CABINET_X + CABINET_W / 2, FLOOR_Y + 70],
        [1004, FLOOR_Y + 70],
      ].map(([jx, jy]) => (
        <circle
          key={jx}
          cx={jx}
          cy={jy}
          r={11}
          fill={P.calmwoodDeep}
          stroke={P.calmwoodEdge}
          strokeWidth="3"
        />
      ))}
    </g>
  );
}

// The flange where the pipe meets the shelf's underside — the joint that
// says the pipe feeds the shelf. Drawn after the Shelf.
function PipeFlange() {
  return (
    <g>
      <rect x={988} y={530} width={32} height={13} rx={3} fill={P.calmwoodEdge} />
      <rect x={992} y={533} width={24} height={4} rx={2} fill="#3a3f55" />
      <circle cx={992} cy={540} r={1.6} fill="#cfa75c" />
      <circle cx={1016} cy={540} r={1.6} fill="#cfa75c" />
    </g>
  );
}

// ── Scene-dressing: Sofa — low, Nordic, oak legs; where nobody has to sit
// and watch a board. And a plant, because the room was a room first.
function Sofa() {
  const x = 1050,
    w = 240,
    top = 596;
  return (
    <g>
      <rect
        x={x + 8}
        y={top + 12}
        width={w}
        height={FLOOR_Y - top - 12}
        fill="#000"
        opacity="0.2"
        filter="url(#tc-soft)"
      />
      <rect x={x} y={top} width={w} height={54} rx={14} fill="#6d7d92" />
      <rect x={x - 12} y={top + 30} width={26} height={54} rx={10} fill="#5f6f84" />
      <rect x={x + w - 14} y={top + 30} width={26} height={54} rx={10} fill="#5f6f84" />
      <rect x={x + 8} y={top + 44} width={w / 2 - 12} height={34} rx={8} fill="#8a9ab0" />
      <rect x={x + w / 2 + 4} y={top + 44} width={w / 2 - 12} height={34} rx={8} fill="#8a9ab0" />
      <rect x={x - 4} y={top + 76} width={w + 8} height={8} fill={P.calmwood} />
      <path
        d={`M ${x + 8} ${top + 84} L ${x + 18} ${top + 84} L ${x + 2} ${FLOOR_Y} L ${x - 8} ${FLOOR_Y} Z`}
        fill={P.calmwoodDeep}
      />
      <path
        d={`M ${x + w - 8} ${top + 84} L ${x + w - 18} ${top + 84} L ${x + w - 2} ${FLOOR_Y} L ${x + w + 8} ${FLOOR_Y} Z`}
        fill={P.calmwoodDeep}
      />
    </g>
  );
}

function Plant({
  x,
  y = FLOOR_Y,
  s = 1,
  still = false,
}: {
  x: number;
  y?: number;
  s?: number;
  still?: boolean;
}) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx={0} cy={2} rx={34} ry={5} fill={P.night} opacity="0.4" />
      <g
        style={{
          transformOrigin: "0px -40px",
          animation: still ? undefined : "tc-leaf 6.5s ease-in-out infinite",
        }}
      >
        <path
          d="M 0 -44 C -6 -90 -30 -120 -70 -130"
          fill="none"
          stroke="#2f6b42"
          strokeWidth="5"
          strokeLinecap="round"
        />
        <path
          d="M -70 -130 C -104 -118 -116 -150 -96 -176 C -78 -196 -46 -190 -40 -164 C -36 -146 -50 -132 -70 -130 Z"
          fill="#3f8a54"
        />
        <path
          d="M 0 -44 C 4 -100 14 -140 36 -170"
          fill="none"
          stroke="#2f6b42"
          strokeWidth="5"
          strokeLinecap="round"
        />
        <path
          d="M 36 -170 C 8 -186 10 -222 40 -236 C 66 -246 92 -222 84 -196 C 78 -176 58 -162 36 -170 Z"
          fill="#4a9d5f"
        />
        <path
          d="M 0 -44 C 12 -76 34 -96 62 -104"
          fill="none"
          stroke="#2f6b42"
          strokeWidth="5"
          strokeLinecap="round"
        />
        <path
          d="M 62 -104 C 60 -134 88 -150 110 -136 C 130 -122 124 -94 100 -86 C 82 -80 66 -88 62 -104 Z"
          fill="#3f8a54"
        />
      </g>
      <path d="M -30 -44 L 30 -44 L 22 0 L -22 0 Z" fill="#8a6a55" />
      <rect x={-34} y={-52} width={68} height={10} rx={3} fill="#6e4f3e" />
    </g>
  );
}

// ── Nimbus — the Azure Butler. The Shelf Guardians' steward, quoted: chrome
// dome, recessed visor, one lit LED eye sweeping slowly, the bow tie; and
// dressed for the work he keeps — a charcoal tailcoat over the collared
// shirt, a dove waistcoat with brass buttons, white gloves. The gloves are
// mittens, no fingers: at this register a hand has no good reading. Anchor:
// body centre; the plinth's base sits at local y≈96.
export function Nimbus({
  x,
  y,
  s = 1,
  eye = 0.45,
  acting = false,
  still = false,
  gloves = "sides",
  entering = false,
}: {
  x: number;
  y: number;
  s?: number;
  eye?: number;
  acting?: boolean;
  still?: boolean;
  gloves?: "sides" | "folded";
  entering?: boolean;
}) {
  const coat = "#1b2129";
  const coatEdge = "#3a4450";
  const waistcoat = "#5b6873";
  const glove = "#eef1f3";
  const gloveEdge = "#b9c4ca";
  const brass = "#cfa75c";
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <g
        style={{
          animation: entering
            ? "tc-walk 1.3s cubic-bezier(0.25, 0.46, 0.45, 0.94) 0.4s backwards"
            : undefined,
        }}
      >
        {/* grounding shadow — outside the breathing group so it holds still */}
        <ellipse cx="0" cy="100" rx="60" ry="9" fill={P.night} opacity="0.6" />
        <g
          style={{
            animation: still ? undefined : "tc-breathe 3200ms ease-in-out infinite",
            transformOrigin: "0px 20px",
          }}
        >
          {/* shell — dome-topped chrome */}
          <path
            d="M -44 82 L -44 -30 C -44 -74 -20 -96 0 -96 C 20 -96 44 -74 44 -30 L 44 82 Z"
            fill="url(#tc-chrome)"
            stroke="#546a76"
            strokeWidth="2.5"
          />
          {/* the tails of the coat, over the plinth's top edge */}
          <path d="M -44 60 L -16 60 L -22 100 C -34 102 -44 98 -46 90 Z" fill={coat} />
          <path d="M 44 60 L 16 60 L 22 100 C 34 102 44 98 46 90 Z" fill={coat} />
          <rect x="-52" y="82" width="104" height="14" rx="5" fill="#33434c" />
          {/* the visor, and the eye that never stops */}
          <rect
            x="-31"
            y="-53"
            width="62"
            height="19"
            rx="9.5"
            fill="#22303a"
            stroke="#546a76"
            strokeWidth="2"
          />
          <rect x="-27" y="-49" width="54" height="11" rx="5.5" fill={P.night} />
          <g style={{ animation: still ? undefined : "tc-eyescan 3400ms ease-in-out infinite" }}>
            <circle
              cx="0"
              cy="-43.5"
              r="4.4"
              fill={P.glow}
              opacity={eye}
              style={acting && !still ? { animation: "tc-eyestep 6s linear infinite" } : undefined}
            />
            {eye > 0.3 && (
              <circle
                cx="0"
                cy="-43.5"
                r="4.4"
                fill={P.glow}
                opacity={eye * 0.6}
                filter="url(#tc-blur)"
              />
            )}
          </g>
          <path
            d="M -23 -50 L -11 -50"
            stroke="#dceef6"
            strokeWidth="2"
            strokeLinecap="round"
            opacity="0.3"
          />
          {/* the shirt: collar and bib */}
          <path
            d="M -26 0 L 26 0 C 30 24 30 48 26 68 L -26 68 C -30 48 -30 24 -26 0 Z"
            fill="#e9edf0"
            stroke="#b9c4ca"
            strokeWidth="1.5"
          />
          {/* the waistcoat over the bib, the coat over the waistcoat */}
          <path
            d="M -18 14 L 18 14 C 22 34 22 54 18 74 L -18 74 C -22 54 -22 34 -18 14 Z"
            fill={waistcoat}
            stroke="#3f4a53"
            strokeWidth="1.2"
          />
          <path
            d="M -44 -2 L -14 12 L -18 82 L -44 82 Z"
            fill={coat}
            stroke={coatEdge}
            strokeWidth="1.2"
          />
          <path
            d="M 44 -2 L 14 12 L 18 82 L 44 82 Z"
            fill={coat}
            stroke={coatEdge}
            strokeWidth="1.2"
          />
          {/* lapels — the notch that says tailcoat from across the room */}
          <path
            d="M -34 -2 L -8 14 L -16 34 L -30 22 Z"
            fill="#2a323c"
            stroke={coatEdge}
            strokeWidth="1"
          />
          <path
            d="M 34 -2 L 8 14 L 16 34 L 30 22 Z"
            fill="#2a323c"
            stroke={coatEdge}
            strokeWidth="1"
          />
          {/* the collar points, and the bow tie at the collar */}
          <path d="M -26 0 L -3 3 L -16 18 Z" fill="#f7fafb" stroke="#b9c4ca" strokeWidth="1.5" />
          <path d="M 26 0 L 3 3 L 16 18 Z" fill="#f7fafb" stroke="#b9c4ca" strokeWidth="1.5" />
          <path d="M -1 10 L -17 3 L -17 19 Z" fill={P.night} />
          <path d="M 1 10 L 17 3 L 17 19 Z" fill={P.night} />
          <circle cx="0" cy="10" r="4" fill={brass} />
          {/* brass buttons down the waistcoat */}
          {[34, 46, 58].map((by) => (
            <circle
              key={by}
              cx="0"
              cy={by}
              r="2.6"
              fill={brass}
              stroke="#8a6d38"
              strokeWidth="0.8"
            />
          ))}
          {/* the gloves — at his sides, or folded at the waistcoat */}
          {gloves === "sides" ? (
            <>
              <ellipse
                cx="-50"
                cy="52"
                rx="9"
                ry="12"
                fill={glove}
                stroke={gloveEdge}
                strokeWidth="1.5"
              />
              <ellipse
                cx="50"
                cy="52"
                rx="9"
                ry="12"
                fill={glove}
                stroke={gloveEdge}
                strokeWidth="1.5"
              />
            </>
          ) : (
            <>
              <ellipse
                cx="-7"
                cy="62"
                rx="10"
                ry="8"
                fill={glove}
                stroke={gloveEdge}
                strokeWidth="1.5"
                transform="rotate(-18 -7 62)"
              />
              <ellipse
                cx="7"
                cy="60"
                rx="10"
                ry="8"
                fill={glove}
                stroke={gloveEdge}
                strokeWidth="1.5"
                transform="rotate(18 7 60)"
              />
            </>
          )}
        </g>
      </g>
    </g>
  );
}

// The small plant on the cabinet's top — the room was a room first.
function CabinetPlant({ still = false }: { still?: boolean }) {
  return <Plant x={CABINET_X + 26} y={CABINET_TOP - 8} s={0.34} still={still} />;
}

// ── The crew — the Remote Standup's cast, quoted small ───────────────────────
// The studio's own nine (remote-standup-cast.tsx), seen through the first
// window the way the product's Team Agile stage seats them: nine webcam tiles
// in the cast's tints, a bust in each — head, shoulders, the hair that is each
// one's identity — quoted from Person's own 120×100 geometry. The props stay
// home: at this distance a face and a tint are the whole character, the way
// Gillbert is an arc and an eye. One tile speaks and wears the stage's green;
// the rest are ghosted, grayscale and dim, exactly the look the played standup
// gives a seat that is not speaking. No bios, no catchphrases: the only words
// out there are the standup's own, in the bubble.
type Hair = "crop" | "bun" | "headphones" | "cap" | "curls" | "long" | "buzz" | "coif" | "spikes";
type Mood = "calm" | "grin" | "awe" | "zen";
type CrewMember = {
  id: string;
  tint: string;
  shirt: string;
  skin: string;
  hairColor: string;
  hair: Hair;
  mood: Mood;
};
const CREW: CrewMember[] = [
  {
    id: "dev-hero",
    tint: "#4f7de9",
    shirt: "#2d5bd0",
    skin: "#e8b88a",
    hairColor: "#3a2a22",
    hair: "coif",
    mood: "grin",
  },
  {
    id: "ops-dev",
    tint: "#26303f",
    shirt: "#26303f",
    skin: "#c68863",
    hairColor: "#1c1611",
    hair: "buzz",
    mood: "calm",
  },
  {
    id: "minimalist",
    tint: "#e8ecef",
    shirt: "#454b54",
    skin: "#e8b88a",
    hairColor: "#2c2c2c",
    hair: "buzz",
    mood: "calm",
  },
  {
    id: "new-hire",
    tint: "#f7d96f",
    shirt: "#d9a12f",
    skin: "#f2c9a0",
    hairColor: "#6a4a1a",
    hair: "spikes",
    mood: "awe",
  },
  {
    id: "vibemancer",
    tint: "#171226",
    shirt: "#31264d",
    skin: "#f2c9a0",
    hairColor: "#231a38",
    hair: "headphones",
    mood: "zen",
  },
  {
    id: "ultrawide",
    tint: "#4fc6e9",
    shirt: "#223047",
    skin: "#8d5a3b",
    hairColor: "#14100c",
    hair: "crop",
    mood: "awe",
  },
  {
    id: "qa",
    tint: "#f2994a",
    shirt: "#f2f4f6",
    skin: "#e8b88a",
    hairColor: "#5a3a20",
    hair: "bun",
    mood: "calm",
  },
  {
    id: "pm",
    tint: "#e94f4f",
    shirt: "#2a3142",
    skin: "#f2c9a0",
    hairColor: "#7a4a20",
    hair: "long",
    mood: "grin",
  },
  {
    id: "designer",
    tint: "#6fcf97",
    shirt: "#efe6d6",
    skin: "#c68863",
    hairColor: "#241a12",
    hair: "curls",
    mood: "zen",
  },
];
// the stage's own green — the speaker's frame and the signal dot, quoted
const CREW_GREEN = "#6fcf97";
const CREW_INK = "#1c2434";

// A webcam bust, Person's geometry at its own viewBox: bottom-anchored, so
// the shoulders are cut by the tile the way a real camera frames them.
function Bust({ x, y, w, c }: { x: number; y: number; w: number; c: CrewMember }) {
  const h = (w * 100) / 120;
  const hc = c.hairColor;
  return (
    <svg x={x} y={y} width={w} height={h} viewBox="0 0 120 100">
      <rect x="22" y="64" width="76" height="40" rx="17" fill={c.shirt} />
      <circle cx="60" cy="38" r="24" fill={c.skin} />
      {c.hair === "crop" && (
        <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 28 A 24 26 0 0 0 36 28 Z" fill={hc} />
      )}
      {c.hair === "buzz" && (
        <path
          d="M 37 30 A 24 22 0 0 1 83 30 L 83 26 A 24 24 0 0 0 37 26 Z"
          fill={hc}
          opacity="0.7"
        />
      )}
      {c.hair === "bun" && (
        <g fill={hc}>
          <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 26 A 24 26 0 0 0 36 26 Z" />
          <circle cx="60" cy="12" r="8" />
        </g>
      )}
      {c.hair === "long" && (
        <g fill={hc}>
          <path d="M 36 34 A 24 24 0 0 1 84 34 L 84 26 A 24 26 0 0 0 36 26 Z" />
          <rect x="32" y="30" width="9" height="34" rx="4.5" />
          <rect x="79" y="30" width="9" height="34" rx="4.5" />
        </g>
      )}
      {c.hair === "curls" && (
        <g fill={hc}>
          <circle cx="44" cy="20" r="9" />
          <circle cx="60" cy="15" r="10" />
          <circle cx="76" cy="20" r="9" />
        </g>
      )}
      {c.hair === "coif" && (
        <path d="M 34 30 Q 44 6 66 12 Q 88 18 86 32 Q 74 18 56 20 Q 40 22 34 30 Z" fill={hc} />
      )}
      {c.hair === "spikes" && (
        <g fill={hc}>
          <path d="M 40 26 L 44 12 L 50 24 Z" />
          <path d="M 52 22 L 58 8 L 64 22 Z" />
          <path d="M 66 24 L 74 12 L 78 26 Z" />
        </g>
      )}
      {c.hair === "cap" && (
        <g fill={hc}>
          <path d="M 36 30 A 24 22 0 0 1 84 30 L 84 26 A 24 24 0 0 0 36 26 Z" />
          <rect x="30" y="27" width="34" height="7" rx="3.5" />
        </g>
      )}
      {c.hair === "headphones" && (
        <g fill={hc}>
          <path d="M 34 34 A 26 26 0 0 1 86 34 L 80 34 A 20 20 0 0 0 40 34 Z" />
          <rect x="30" y="32" width="10" height="16" rx="5" />
          <rect x="80" y="32" width="10" height="16" rx="5" />
        </g>
      )}
      {c.mood === "zen" ? (
        <g stroke="#2b2018" strokeWidth="2.4" strokeLinecap="round">
          <line x1="49" y1="38" x2="57" y2="38" />
          <line x1="63" y1="38" x2="71" y2="38" />
        </g>
      ) : (
        <g fill="#2b2018">
          <circle cx="52" cy="37" r={c.mood === "awe" ? 3.6 : 2.6} />
          <circle cx="68" cy="37" r={c.mood === "awe" ? 3.6 : 2.6} />
        </g>
      )}
      {c.mood === "grin" && (
        <path
          d="M 52 47 Q 60 54 68 47"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
      {c.mood === "calm" && (
        <path
          d="M 54 48 Q 60 51 66 48"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
      {c.mood === "awe" && <ellipse cx="60" cy="49" rx="4" ry="5" fill="#2b2018" />}
      {c.mood === "zen" && (
        <path
          d="M 54 48 Q 60 50 66 48"
          fill="none"
          stroke="#2b2018"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      )}
    </svg>
  );
}

// One tile of the call: the tint, the bust, the signal dot; ghosted unless it
// is the one speaking, which wears the stage's green frame.
function CrewTile({
  x,
  y,
  w,
  h,
  c,
  speaking = false,
  delay,
  still = false,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  c: CrewMember;
  speaking?: boolean;
  delay?: number;
  still?: boolean;
}) {
  const bw = w * 0.78;
  const bh = (bw * 100) / 120;
  return (
    <g
      style={v({
        transformBox: "fill-box",
        transformOrigin: "center",
        animation: delay != null && !still ? `tc-pop 0.5s ease-out ${delay}s backwards` : "none",
      })}
    >
      <g filter={speaking ? undefined : "url(#tc-grey)"}>
        <rect x={x} y={y} width={w} height={h} rx={4} fill={c.tint} />
        <rect
          x={x}
          y={y + h * 0.55}
          width={w}
          height={h * 0.45}
          rx={4}
          fill="#000"
          opacity="0.14"
        />
        <Bust x={x + (w - bw) / 2} y={y + h - bh + 2} w={bw} c={c} />
        <circle cx={x + 6} cy={y + h - 6} r={2.2} fill={CREW_GREEN} />
      </g>
      {!speaking && <rect x={x} y={y} width={w} height={h} rx={4} fill={P.night} opacity="0.5" />}
      {speaking && (
        <rect
          x={x + 1}
          y={y + 1}
          width={w - 2}
          height={h - 2}
          rx={4}
          fill="none"
          stroke={CREW_GREEN}
          strokeWidth="3"
        />
      )}
    </g>
  );
}

// The call, seen through the window: three by three inside the glass, as the
// stage always seats nine. `speaker` is the one lit tile.
function Crew({
  x,
  y,
  w,
  h,
  speaker,
  delay = 0,
  still = false,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  speaker: string;
  delay?: number;
  still?: boolean;
}) {
  const gap = 4;
  const tw = (w - gap * 2) / 3;
  const th = (h - gap * 2) / 3;
  return (
    <g>
      <rect x={x - 3} y={y - 3} width={w + 6} height={h + 6} fill="#131a2b" />
      {CREW.map((c, i) => (
        <CrewTile
          key={c.id}
          x={x + (i % 3) * (tw + gap)}
          y={y + Math.floor(i / 3) * (th + gap)}
          w={tw}
          h={th}
          c={c}
          speaking={c.id === speaker}
          delay={delay + i * 0.1}
          still={still}
        />
      ))}
    </g>
  );
}

// The speech bubble, the stage's own: white, rounded, the sentence in ink, a
// tail to the face that is speaking. Four lines, as the played standup clamps
// it. It comes out of the window into the room, which is the point: the
// standup plays back where you are.
function CrewBubble({
  x,
  y,
  w,
  lines,
  tail,
  delay,
}: {
  x: number;
  y: number;
  w: number;
  lines: string[];
  tail: { x: number; y: number };
  delay?: number;
}) {
  const pad = 11;
  const lh = 16;
  const h = pad * 2 + lines.length * lh;
  return (
    <g
      style={v({
        transformBox: "fill-box",
        transformOrigin: "left bottom",
        animation: delay != null ? `tc-pop 0.45s ease-out ${delay}s backwards` : "none",
      })}
    >
      <rect x={x + 3} y={y + 5} width={w} height={h} rx={10} fill="#000" opacity="0.3" />
      <path
        d={`M ${x + 4} ${y + h - 26} L ${tail.x} ${tail.y} L ${x + 4} ${y + h - 8} Z`}
        fill="#ffffff"
      />
      <rect x={x} y={y} width={w} height={h} rx={10} fill="#ffffff" />
      <text
        x={x + pad}
        y={y + pad + 11}
        fontFamily={SANS}
        fontSize="12"
        fontWeight="700"
        fill={CREW_INK}
      >
        {lines.map((line, i) => (
          <tspan key={i} x={x + pad} dy={i === 0 ? 0 : lh}>
            {line}
          </tspan>
        ))}
      </text>
    </g>
  );
}

// ── Choreography helpers ─────────────────────────────────────────────────────

// An Envelope drifting in on a sine: x on the outer wrapper, y on the inner.
function DriftIn({
  dx,
  dur = 2.6,
  delay = 0.4,
  children,
}: {
  dx: number;
  dur?: number;
  delay?: number;
  children: ReactNode;
}) {
  return (
    <g
      style={v({
        "--dx": `${dx}px`,
        animation: `tc-driftx ${dur}s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${delay}s backwards`,
      })}
    >
      <g style={{ animation: `tc-drifty ${dur}s ease-in-out ${delay}s backwards` }}>{children}</g>
    </g>
  );
}

// An Envelope gliding from where it hovered to where its file says it goes.
function Glide({
  gx,
  gy,
  delay,
  dur = 0.9,
  children,
}: {
  gx: number;
  gy: number;
  delay: number;
  dur?: number;
  children: ReactNode;
}) {
  return (
    <g
      style={v({
        "--gx": `${gx}px`,
        "--gy": `${gy}px`,
        animation: `tc-glide ${dur}s cubic-bezier(0.34, 1.56, 0.64, 1) ${delay}s backwards`,
      })}
    >
      {children}
    </g>
  );
}

// The formation: five envelopes over the cabinet in Galaga's own shape — a
// row of two over a row of three — each on its own arc, all settling on one
// breath.
const FORMATION: Array<{ ox: number; oy: number; id: string; type: CardType }> = [
  { ox: -50, oy: 0, id: "214", type: "bug" },
  { ox: 50, oy: 0, id: "209", type: "story" },
  { ox: -100, oy: 58, id: "211", type: "task" },
  { ox: 0, oy: 58, id: "216", type: "story" },
  { ox: 100, oy: 58, id: "K7M2", type: "spike" },
];
const FORM_X = 754,
  FORM_Y = 148,
  FORM_W = 76;

function Formation({ hover = true }: { hover?: boolean }) {
  return (
    <g>
      {FORMATION.map((f, i) => (
        <g key={f.id} transform={`translate(${FORM_X + f.ox - FORM_W / 2} ${FORM_Y + f.oy})`}>
          <g
            style={v({
              "--dx": `${f.ox < 0 ? -700 : f.ox > 0 ? 700 : 0}px`,
              animation: `tc-driftx 1.9s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${0.3 + i * 0.3}s backwards`,
            })}
          >
            <g style={{ animation: `tc-drifty 1.9s ease-in-out ${0.3 + i * 0.3}s backwards` }}>
              <g
                style={{
                  animation: hover ? `tc-hover 3.2s ease-in-out ${2.4}s infinite` : undefined,
                }}
              >
                <Envelope x={0} y={0} w={FORM_W} id={f.id} type={f.type} />
              </g>
            </g>
          </g>
        </g>
      ))}
    </g>
  );
}

// The camera: the same room, framed closer. Scales about the canvas so a
// close-up is the room, not a second drawing.
function Camera({
  cx,
  cy,
  k,
  children,
}: {
  cx: number;
  cy: number;
  k: number;
  children: ReactNode;
}) {
  return <g transform={`translate(${800 - cx * k} ${450 - cy * k}) scale(${k})`}>{children}</g>;
}

function Veil({ opacity }: { opacity: number }) {
  return <rect x={-40} y={-40} width={1680} height={980} fill={P.duskDeep} opacity={opacity} />;
}

// ── Slide stages ─────────────────────────────────────────────────────────────

// 1. The Room Appears — the whole room, settling in: the aquarium's light on
// the cabinet, the aurora through the high glass, nothing asked of anyone.
function RoomAppearsStage() {
  const settle = (d: number): CSSProperties => ({
    animation: `tc-settle 0.9s cubic-bezier(0.25, 0.46, 0.45, 0.94) ${d}s backwards`,
  });
  return (
    <Stage>
      <Scene>
        <Room>
          <Wall />
          <g style={settle(0.2)}>
            <AuroraBand />
          </g>
          <g style={settle(0.5)}>
            <Window />
          </g>
          <g style={settle(0.8)}>
            <Cabinet />
            <CabinetPlant />
          </g>
          <g style={settle(1.0)}>
            <LedgerWall empty />
            <ReminderRail />
          </g>
          <g style={settle(1.2)}>
            <Shelf />
          </g>
          <g style={settle(1.4)}>
            <Sofa />
          </g>
          <g style={settle(0.65)}>
            <Aquarium />
          </g>
          <AquariumSpill />
        </Room>
      </Scene>
    </Stage>
  );
}

// 2. The First Drift — closer, on the left of the room: one envelope rides a
// sine in from the edge and comes to rest on the cabinet's top, its id on it.
function FirstDriftStage() {
  return (
    <Stage>
      <Scene>
        <Camera cx={560} cy={520} k={1.3}>
          <Room>
            <Wall />
            <AuroraBand />
            <Window />
            <Cabinet />
            <CabinetPlant />
            <Aquarium />
            <AquariumSpill />
            <DriftIn dx={-760} dur={2.8} delay={0.5}>
              <Envelope x={722} y={CABINET_TOP - 8 - 68} w={110} id="K7M2" type="spike" />
            </DriftIn>
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 3. Galaga Arrival — five envelopes on five arcs, from both edges, landing
// in a V over the cabinet and holding on one breath.
function GalagaStage() {
  return (
    <Stage>
      <Scene>
        <Room>
          <Wall />
          <AuroraBand />
          <Window />
          <Cabinet />
          <CabinetPlant />
          <LedgerWall empty />
          <ReminderRail />
          <Shelf />
          <Sofa />
          <Aquarium />
          <AquariumSpill />
          <Formation />
        </Room>
      </Scene>
    </Stage>
  );
}

// 4. Formation in the Cabinet — close on the chest. A stamp presses on two of
// the envelopes; each of the five glides into the lane whose
// lamp is its stamp's colour. Nothing drags them.
function CabinetStage() {
  const w = FORM_W;
  const dest = (lane: number, slot: number, cw: number) => inLane(lane, slot, cw);
  // three plain cards into Active, one per stamp into the other two lanes:
  // only two of the five mutate; three simply wait
  const cards: Array<{
    id: string;
    type: CardType;
    lane: number;
    slot: number;
    ox: number;
    oy: number;
    mark?: StampKind;
  }> = [
    { id: "216", type: "story", lane: 0, slot: 0, ox: 0, oy: 58 },
    { id: "211", type: "task", lane: 0, slot: 1, ox: -100, oy: 58 },
    { id: "K7M2", type: "spike", lane: 0, slot: 2, ox: 100, oy: 58 },
    { id: "214", type: "bug", lane: 1, slot: 0, ox: -50, oy: 0, mark: "commit" },
    { id: "209", type: "story", lane: 2, slot: 0, ox: 50, oy: 0, mark: "pr" },
  ];
  return (
    <Stage>
      <Scene>
        <Camera cx={680} cy={520} k={1.45}>
          <Room>
            <Wall />
            <AuroraBand />
            <Window />
            <LedgerWall empty />
            <ReminderRail />
            <Shelf />
            <Aquarium />
            <Cabinet>
              {cards.map((c, i) => {
                const cw = c.lane === 0 ? 56 : 64;
                const d = dest(c.lane, c.slot, cw);
                const from = { x: FORM_X + c.ox - w / 2, y: FORM_Y + c.oy };
                return (
                  <Glide
                    key={c.id}
                    gx={from.x - d.x}
                    gy={from.y - d.y}
                    delay={1.9 + i * 0.45}
                    dur={1.0}
                  >
                    <Envelope
                      x={d.x}
                      y={d.y}
                      w={cw}
                      id={c.id}
                      type={c.type}
                      marks={c.mark ? [{ kind: c.mark }] : []}
                      markDelay={0.9 + i * 0.3}
                    />
                  </Glide>
                );
              })}
            </Cabinet>
            <CabinetPlant />
            <AquariumSpill />
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 6. The Second Window — Nimbus steps in at the room's edge, stands at the
// window; the sash lifts; two envelopes come through it, each already wearing
// its work-item number, and settle into the Active lane: the cards move on
// their board. His eye brightens one step. Nothing else in the room hurries.
function ButlerStage() {
  const w = 64;
  const windowMouth = { x: 415 - w / 2, y: 330 };
  const dests = [
    { ...inLane(0, 0, w), id: "216", type: "story" as const, delay: 3.4 },
    { ...inLane(0, 1, w), id: "214", type: "bug" as const, delay: 4.3 },
  ];
  return (
    <Stage>
      <Scene>
        <Camera cx={610} cy={520} k={1.3}>
          <Room>
            <Wall />
            <AuroraBand />
            <Window open lifting cloud={0.5} />
            <Aquarium />
            <Cabinet>
              {dests.map((d) => (
                <Glide
                  key={d.id}
                  gx={windowMouth.x - d.x}
                  gy={windowMouth.y - d.y}
                  delay={d.delay}
                  dur={1.4}
                >
                  <Envelope
                    x={d.x}
                    y={d.y}
                    w={w}
                    id={d.id}
                    type={d.type}
                    marks={[{ text: `#${d.id}` }]}
                  />
                </Glide>
              ))}
            </Cabinet>
            <CabinetPlant />
            <Nimbus x={570} y={608} s={0.85} eye={0.45} acting entering />
            <AquariumSpill />
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 5. The First Window — the window opened on GitHub. No butler: GitHub
// answers on its own. Issues arrive already numbered and REST ON THE SILL,
// read in place. Through the glass, the crew is standing up: the nine tiles of
// the standup, one speaking, its bubble coming out of the window into the
// room. One of the issues — the work with weight — glides into the cabinet
// as a card. The Space is the drawer that window belongs to.
function FirstWindowStage() {
  const w = 64;
  const windowMouth = { x: 415 - w / 2, y: 330 };
  const fade = (d: number): CSSProperties => ({
    animation: `tc-fade 0.6s ease-out ${d}s backwards`,
  });
  // the issues stand ON the sill, upright in the opening, their feet on its top
  // edge -- in front of the crew's bottom row, which is where a sill is
  const sill = [
    { x: 340, y: 411, id: "61", type: "feature" as const, delay: 2.2 },
    { x: 426, y: 411, id: "57", type: "bug" as const, delay: 2.9 },
  ];
  const picked = { ...inLane(0, 0, w), id: "67", type: "task" as const, delay: 5.2 };
  // the glass, inside the frame's stroke; the speaking seat is the top-right tile
  const glass = { x: 337, y: 197, w: 156, h: 246 };
  const speakerFace = { x: glass.x + glass.w - 26, y: glass.y + 50 };
  return (
    <Stage>
      <Scene>
        <Camera cx={545} cy={450} k={1.85}>
          <Room>
            <Wall />
            <AuroraBand />
            <Window
              open
              lifting
              cloud={0}
              view={<Crew {...glass} speaker="minimalist" delay={3.1} />}
            />
            <Aquarium />
            {sill.map((d) => (
              <g key={d.id} style={fade(d.delay)}>
                <Envelope
                  x={d.x}
                  y={d.y}
                  w={w}
                  id={d.id}
                  type={d.type}
                  marks={[{ text: `#${d.id}` }]}
                />
              </g>
            ))}
            <Cabinet>
              <Glide
                gx={windowMouth.x - picked.x}
                gy={windowMouth.y - picked.y}
                delay={picked.delay}
                dur={1.4}
              >
                <Envelope
                  x={picked.x}
                  y={picked.y}
                  w={w}
                  id={picked.id}
                  type={picked.type}
                  marks={[{ text: `#${picked.id}` }]}
                />
              </Glide>
            </Cabinet>
            <CabinetPlant />
            <CrewBubble
              x={518}
              y={178}
              w={178}
              lines={[
                "Yesterday I closed two.",
                "Today, the pull request.",
                "No blockers.",
                "Over to you.",
              ]}
              tail={speakerFace}
              delay={4.4}
            />
            <AquariumSpill />
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 7. The Studio Holds Still — the room at dusk, nothing moving. The week on
// the wall, every card in its lane, one small light over the
// hook for today. Nimbus stands at the window and does not breathe.
function HoldsStillStage() {
  return (
    <Stage bg={DUSK_BG}>
      <Scene>
        <Room>
          <Wall dusk />
          <AuroraBand still dim />
          <Window still />
          <Cabinet>
            <Envelope {...inLane(0, 0, 56)} w={56} id="216" type="story" />
            <Envelope {...inLane(0, 1, 56)} w={56} id="211" type="task" />
            <Envelope {...inLane(0, 2, 56)} w={56} id="K7M2" type="spike" />
            <Envelope {...inLane(1, 0)} w={64} id="214" type="bug" marks={[{ kind: "commit" }]} />
            <Envelope {...inLane(2, 0)} w={64} id="209" type="story" marks={[{ kind: "pr" }]} />
          </Cabinet>
          <CabinetPlant still />
          <LedgerWall />
          <ReminderRail tagOn={1} lit />
          <Shelf still />
          <Sofa />
          <Aquarium still />
          <Nimbus x={570} y={608} s={0.85} eye={0.3} still />
          <Veil opacity={0.28} />
          <g opacity={0.55}>
            <AquariumSpill still />
          </g>
        </Room>
      </Scene>
    </Stage>
  );
}

// 8. Daily Writes Itself — close on the wall. Three envelopes lie on the
// cabinet's top with their type tabs; on the Ledger, one segment per card
// per day inks in, in the card's own colour. The wall already knew.
function DailyStage() {
  return (
    <Stage>
      <Scene>
        <Camera cx={960} cy={440} k={1.42}>
          <Room>
            <Wall />
            <AuroraBand />
            <Cabinet>
              <Envelope
                x={CABINET_X + 24}
                y={CABINET_TOP - 8 - 46}
                w={68}
                id="216"
                type="story"
                marks={[{ kind: "closed" }]}
              />
              <Envelope
                x={CABINET_X + 96}
                y={CABINET_TOP - 8 - 46}
                w={68}
                id="214"
                type="bug"
                marks={[{ kind: "commit" }]}
              />
              <Envelope
                x={CABINET_X + 168}
                y={CABINET_TOP - 8 - 46}
                w={68}
                id="209"
                type="story"
                marks={[{ kind: "pr" }]}
              />
              <Envelope {...inLane(0, 0, 56)} w={56} id="211" type="task" />
              <Envelope {...inLane(0, 1, 56)} w={56} id="K7M2" type="spike" />
            </Cabinet>
            <LedgerWall inking delay={0.9} />
            <ReminderRail />
            <Shelf />
            <Sofa />
            <Nimbus x={570} y={608} s={0.85} eye={0.3} />
            <AquariumSpill />
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 9. Reporting Gathers Evidence — the floor opened along the pipe from the
// Done lane to the shelf's bracket; what closed flows along it, and the
// period's two documents settle onto the ledge. Dusk deepens.
function ReportingStage() {
  return (
    <Stage bg={DUSK_BG}>
      <Scene>
        <Camera cx={930} cy={640} k={1.25}>
          <Room>
            <Wall dusk />
            <AuroraBand dim />
            <PipeRun />
            <Cabinet>
              <Envelope {...inLane(0, 0, 56)} w={56} id="211" type="task" />
              <Envelope {...inLane(0, 1, 56)} w={56} id="K7M2" type="spike" />
              <Envelope {...inLane(1, 0)} w={64} id="214" type="bug" marks={[{ kind: "commit" }]} />
              <Envelope {...inLane(2, 0)} w={64} id="209" type="story" marks={[{ kind: "pr" }]} />
              <Envelope
                {...inLane(3, 0)}
                w={64}
                id="216"
                type="story"
                marks={[{ kind: "closed" }]}
              />
            </Cabinet>
            <CabinetPlant />
            <LedgerWall />
            <ReminderRail />
            <Shelf docs={2} landing delay={1.2} />
            <PipeFlange />
            <Sofa />
            <Nimbus x={570} y={608} s={0.85} eye={0.3} />
            <Veil opacity={0.18} />
            <AquariumSpill />
          </Room>
        </Camera>
      </Scene>
    </Stage>
  );
}

// 10. The Studio, Yours — the room slide 1 opened on, at dusk, full: every
// lane holding something, the week inked, the shelf carrying its evidence,
// Nimbus at rest by the window with his gloves folded, the aurora drifting.
// The button, bottom-right, is how you take it.
function YoursStage() {
  return (
    <Stage bg={DUSK_BG}>
      <Scene>
        <Room>
          <Wall dusk />
          <AuroraBand />
          <Window open cloud={0.4} />
          <Cabinet>
            <Envelope {...inLane(0, 0, 56)} w={56} id="211" type="task" />
            <Envelope {...inLane(0, 1, 56)} w={56} id="K7M2" type="spike" />
            <Envelope {...inLane(1, 0)} w={64} id="214" type="bug" marks={[{ kind: "commit" }]} />
            <Envelope {...inLane(2, 0)} w={64} id="209" type="story" marks={[{ kind: "pr" }]} />
            <Envelope {...inLane(3, 0)} w={64} id="216" type="story" marks={[{ kind: "closed" }]} />
          </Cabinet>
          <CabinetPlant />
          <LedgerWall titleCard delay={1.2} />
          <ReminderRail />
          <Shelf docs={2} />
          <Sofa />
          <Aquarium />
          <Nimbus x={570} y={608} s={0.85} eye={0.22} gloves="folded" />
          <Veil opacity={0.22} />
          <AquariumSpill />
        </Room>
      </Scene>
      <GiveawayButton />
    </Stage>
  );
}

// ── Deck ─────────────────────────────────────────────────────────────────────

export const theToolkitDeck: Deck = {
  id: "the-toolkit",
  project: "toolkit",
  // Complete once: passed the Design Review Gate and the QA loop (six desktop
  // rounds, one phone pass). Never `deployed` here — Private on purpose, like
  // its sibling: a product commercial is built in this studio but is not the
  // wasteland's to ship.
  // Re-opened for the offering as it now stands: slide 1 says the sentence
  // the product opens on, the first window is GitHub issues and the crew's
  // standup, the second is Nimbus and Azure DevOps. The desktop loop has run
  // clean over the three slides that changed; back to Complete when the
  // phone pass has.
  state: DeckState.Complete,
  title: "Introducing ToolKit",
  summary:
    "A Nordic living room rendered in SVG becomes a calm studio for powerful work. Files drift in like Galaga formations, settling into place with quiet physics. The room's one window opens first on GitHub: issues rest on the sill, the crew stands up through the glass, and the standup plays back what moved; then Nimbus, the Azure Butler, opens it again on Azure DevOps, where the cards move on their board. Daily and Reporting appear as a ruled wall and an evidence shelf. This is the pitch: not software you operate, but a room you keep. Your Space, your work, your studio, and the cards are the record either way.",
  tags: ["product", "toolkit"],
  slides: (): Slide[] => [
    makeSlide({
      id: "the-room-appears",
      title: "Introducing ToolKit",
      eyebrow: "Slide 1 · Baseline",
      lead: "Your Space. Your Work. Your Studio.\nHow you work is up to you.",
      notes: (
        <>
          <Beat>Hold two seconds before the first line; let the room be a room first.</Beat>
          <Say>
            Introducing ToolKit. Your Space. Your Work. Your Studio. How you work is up to you.
          </Say>
          <Say>
            ToolKit is a studio where you work on software by yourself, on a team, or orchestrating
            agents, and the cards are the record either way.
          </Say>
          <Say>
            By yourself: plain Markdown prompt cards, one per piece of work. It works offline, with
            no login, no network call and no tracker. On a team: the same cards, linked one to one
            with the items on your GitHub or Azure DevOps board. Orchestrating agents: the standup
            and triage over the repository&apos;s issues, so a crew of agents can take issues, open
            pull requests and report back while you decide.
          </Say>
          <Say>
            It is not software you operate. It is a room you work inside. The light is on, the
            cabinet is waiting, and the week has not been written down yet. Watch what happens when
            work arrives.
          </Say>
          <Context>
            The sentence and the three ways of working are the product&apos;s own first screen
            (README.md, the tagline and &quot;How you work is up to you&quot;), spoken as written:
            one story, three tellings, and a word that is off here is off in all three. Establish
            baseline calm and the palette: calmwood, ink, glow, frost, dusk. No product mechanism
            yet, on purpose: the cold open sets the room, the way Meet the Toolkit slide 1 sets the
            pain before either deck names how anything works. The last line is the forward promise
            slides 2 to 4 keep.
          </Context>
        </>
      ),
      content: <RoomAppearsStage />,
    }),
    makeSlide({
      id: "the-first-drift",
      title: "The First Drift",
      eyebrow: "Slide 2 · Baseline",
      lead: "A single envelope drifts into the room, following a soft arc. It lands on the cabinet, waiting to be placed.",
      notes: (
        <>
          <Beat>Let the envelope settle fully before speaking.</Beat>
          <Say>
            Every piece of work arrives as one file. Nothing needs a ticket to exist. This one has
            an id of its own, and that is enough.
          </Say>
          <Say>
            It is a plain file, in a folder you own. Open it in anything. What it is, what you
            decided, what changed, all in the one place.
          </Say>
          <Say>
            It lands on the cabinet and waits. Nobody has to tell it where it belongs. That part is
            next.
          </Say>
          <Context>
            A card with no work item gets a short id of its own: four characters, at least one
            letter and one digit, from an alphabet with no look-alikes (docs/hub/cards.md, the id
            row; docs/CLI.md, &quot;The id&quot;). K7M2 is the sample hub&apos;s own Spike. A card
            is one markdown file in the hub folder and opens in any editor (docs/hub/cards.md,
            &quot;Inside the file&quot;). Introduces Flow and Growth.
          </Context>
        </>
      ),
      content: <FirstDriftStage />,
    }),
    makeSlide({
      id: "galaga-arrival",
      title: "Galaga Arrival",
      eyebrow: "Slide 3 · Formation",
      lead: "More envelopes appear at the edges of the room. They fly in like Galaga formations, synchronized and calm.",
      notes: (
        <>
          <Beat>Let the formation complete and take one breath before the first line.</Beat>
          <Say>
            None of this is performed for you. However much lands in a day, it arrives the same way
            it always does. The room does not hurry, and it does not fall behind either.
          </Say>
          <Say>
            A bug, a story, a task, a spike. Each one is a file. Each one already carries what it
            is, on the corner.
          </Say>
          <Say>
            They hold in formation for a moment. The order they came in does not matter. What is
            written on them does.
          </Say>
          <Context>
            Introduces Resonance and Accumulation. The formation is the visual argument, not a claim
            about the product: no rate or count is stated. The five ids are the sample hub&apos;s:
            216, 214, 209, 211, K7M2; the pastel tab on each corner is its type, the product&apos;s
            own vocabulary (Bug, Task, User Story, Feature, Spike, Meeting). The third line hands
            off to slide 4.
          </Context>
        </>
      ),
      content: <GalagaStage />,
    }),
    makeSlide({
      id: "formation-in-the-cabinet",
      title: "Formation in the Cabinet",
      eyebrow: "Slide 4 · Formation",
      lead: "A stamp presses, and each envelope glides into the lane its own marks decide. Everything finds its place.",
      notes: (
        <>
          <Beat>
            Hold one second after the last envelope settles, then the second line while pointing at
            the lamps.
          </Beat>
          <Say>
            No one drags an envelope into its lane. Whatever is written on it decides where it
            settles. A commit. A review. A date. Checked in the same order every time.
          </Say>
          <Say>
            A commit on the card, and it is in progress. A pull request on the card, and it is in
            review. Nothing on it yet, and it waits in Active. Three of these five simply wait.
          </Say>
          <Say>
            The lamps on the cabinet are the only labels. Green is a commit. Purple is a review. The
            card&apos;s stamp and the lane&apos;s lamp always match, because they are the same fact.
          </Say>
          <Context>
            State is derived, never stored: a card&apos;s lane is worked out from the file itself,
            the first matching fact wins, and nobody edits a status field by hand
            (docs/hub/cards.md, &quot;State is derived, never stored&quot;): a PR URL line outranks
            a commit bullet, which outranks nothing. The lane lamps are the stamp colours: a green
            check is a commit and In Progress, the purple merge glyph is a pull request and Code
            Review; a plain card stays Active. Don&apos;t overstate: a card with no commit and no
            pull request stays Active. Crystallization lands visually.
          </Context>
        </>
      ),
      content: <CabinetStage />,
    }),
    makeSlide({
      id: "the-first-window-github",
      title: "The First Window: GitHub",
      eyebrow: "Slide 5 · Formation",
      lead: "The window opens on GitHub. Issues arrive already numbered and rest on the sill, read where they are. Through the glass, the crew is standing up, one tile speaking; and one issue, the work with weight, glides into the cabinet as a card.",
      notes: (
        <>
          <Beat>
            Let the sash lift and both issues settle on the sill before the first line; the crew
            pops in under the second, and the bubble lands with it. The third line is the card
            gliding in.
          </Beat>
          <Say>
            The first window opens on GitHub. A drawer of the cabinet is a Space: one board, and at
            most one tracker. Issues come through as they are and rest on the sill. Read them here,
            triage them here, close them here.
          </Say>
          <Say>
            Through the window, the crew is standing up. Orchestrating agents is a loop: issues
            arrive, the crew takes them, pull requests open, and the standup plays back what moved,
            one voice at a time, so you can keep up.
          </Say>
          <Say>
            You decide. When an issue is work with weight, it becomes a card, and the board takes it
            from there. Your own cards and your GitHub issues: one room, one cabinet.
          </Say>
          <Context>
            A Space is one board and at most one tracker, and the tracker is derived from the
            Space&apos;s address (D-G11: a space per product). Issues are read in place, on the
            Issues tab, and never enter the cabinet on their own (D-G10: the card is optional at
            pickup, by the work&apos;s weight); create, edit and close run through the same verbs
            the CLI types. The crew through the glass is the product&apos;s Team Agile stage as it
            ships (docs/modules/solitaire-agile.md): the standup is played on the Remote
            Standup&apos;s nine tiles, one lit tile a worker, the sentence in a four-line bubble
            over the face, the rest of the seats ghosted; the queue it opens and closes on is what
            only the person can do, which is the whole of &quot;you decide&quot;. The standup is
            built from the tracker&apos;s own issues, pull requests and labels, so the loop in the
            Say is the loop in the product. The three numbers on the sill are real issues of the
            toolkit&apos;s own tracker, picked because they are closed. No butler: GitHub answers
            through its own CLI, which is the visual argument for &quot;another counter, nothing
            more&quot;. Never a model&apos;s name, and &quot;orchestrating agents&quot;, not a
            formation of them. Equilibrium, and the first of the two windows.
          </Context>
        </>
      ),
      content: <FirstWindowStage />,
    }),
    makeSlide({
      id: "the-second-window-azure",
      title: "The Second Window: Azure DevOps",
      eyebrow: "Slide 6 · Formation",
      lead: "A small steward steps in at the edge of the room: tailcoat, waistcoat, white gloves, one lit eye. His name is Nimbus, and he opens the window again, on Azure DevOps. The cards move on their board, each one already carrying its own number.",
      notes: (
        <>
          <Beat>
            Let Nimbus step in and the sash lift before the first line; the envelopes are already on
            their way as it lands. The third line is the quiet one.
          </Beat>
          <Say>
            If your team lives in Azure DevOps, the same room grows a second window, and Nimbus
            opens it. The board stays on its shelf, and the cards move on it. The room does not
            change shape to allow him.
          </Say>
          <Say>
            A work item comes through the window as a card and keeps its number. Open the pull
            request from the card, and the board finds out by itself.
          </Say>
          <Say>
            He does his one job quietly. With the window shut, the room is exactly the room it was.
          </Say>
          <Context>
            A continuation, not the opening: Azure DevOps is the previous stop, still there, still
            honest, last, and the Space with the most of the product switched on (cards, the board,
            PR review, Daily, 1:1s, Growth). The humans hold the rituals in person there, so there
            is no standup in this window; the window is additive, as it always was, and Nimbus keeps
            his dignity. &quot;The shelf&quot; is the register, not an object: the Evidence Shelf
            stays Reporting&apos;s furniture. Connecting a Space is additive, not a rescue: work
            items arrive as cards and keep their numbers (docs/hub/cards.md, &quot;Where it
            lives&quot;). NewPR is genuinely one verb: it opens the pull request, moves the work
            item to Code Review and writes the PR URL into the card (docs/modules/ado.md, &quot;The
            verbs&quot;); keep &quot;the board finds out by itself&quot; pinned to opening a PR,
            because closing is two verbs and nothing reconciles them (docs/CLI.md). If asked what
            happens with nothing connected: a local Space reads &quot;not configured
            (expected)&quot;, never a warning; only a Space that tried Azure DevOps and failed reads
            amber (docs/modules/ado.md, the tiers table). Equilibrium: an external system handled
            without disturbing the room. Nimbus is a cousin of the Shelf Guardians&apos; Gillbert,
            the Goldfish Butler: the same small-steward grammar, the same patient beat, a different
            one job; named for the cloud he tends the way Gillbert is named for the gill, and
            dressed more formally because Azure DevOps is the business he is dressed for.
          </Context>
        </>
      ),
      content: <ButlerStage />,
    }),
    makeSlide({
      id: "the-studio-holds-still",
      title: "The Studio Holds Still",
      eyebrow: "Slide 7 · Stillness",
      lead: "The room pauses. Nothing is nagging you. One thing waits for today; everything else is exactly where it should be, waiting its own turn.",
      notes: (
        <>
          <Beat>
            Hold three seconds of silence before the first line. Nothing on this slide moves.
          </Beat>
          <Say>
            The room does not nag. A reminder waits in one of three places, overdue, due today, or
            later, and nothing forces your attention before its time.
          </Say>
          <Say>
            One small light, over the one thing due today. Everything else is exactly where it
            should be, waiting its own turn.
          </Say>
          <Say>
            This is what calm looks like when it is earned. Nothing is idle. Nothing is lost. The
            room is simply not asking.
          </Say>
          <Context>
            A reminder&apos;s bucket, overdue, today, upcoming, is worked out at read time from a
            due date the file carries, never stored as a separate flag (docs/hub/reminders.md,
            &quot;How it is read&quot;). The rail under the ledger is those three hooks; the one lit
            hook is today. Deliberately not the status-readout beat Meet the Toolkit slide 7
            carries: this stillness is about what waits calmly, not what already ran. Act III, the
            stillness moment.
          </Context>
        </>
      ),
      content: <HoldsStillStage />,
    }),
    makeSlide({
      id: "daily-writes-itself",
      title: "Daily Writes Itself",
      eyebrow: "Slide 8 · Restoration",
      lead: "The ledger wall inks itself line by line. The week was never a mystery. It just had not been written down yet.",
      notes: (
        <>
          <Beat>Let the ink finish before speaking; the third line is brisk.</Beat>
          <Say>
            Every card already carries the day it started and the day it closed. The wall does not
            ask you what you did this week. It already knows.
          </Say>
          <Say>
            Monday to Friday, one line per card, in the card&apos;s own colour. The check on Friday
            is the one that closed.
          </Say>
          <Say>Copy a day. Paste it where the timesheet lives. Go home.</Say>
          <Context>
            Daily is built from the cards&apos; own Created and Closed dates: a card is on every
            working day between the two, or today if it is still open (docs/CLI.md, &quot;The two
            dates a card carries&quot;). Each inked segment is one card on one day, in the
            card&apos;s type colour; the check on Friday is the close. Copy Day puts one day on the
            clipboard (web/src/modules/ado/Billing.tsx). Don&apos;t overclaim: Daily shows this week
            and last week, not a history. Crystallization and Growth.
          </Context>
        </>
      ),
      content: <DailyStage />,
    }),
    makeSlide({
      id: "reporting-gathers-evidence",
      title: "Reporting Gathers Evidence",
      eyebrow: "Slide 9 · Restoration",
      lead: "The evidence shelf fills with calm documents. By the numbers, and the work completed. Gathered, not remembered.",
      notes: (
        <>
          <Beat>
            Pause after the last document settles; say the second line while the pipe is still
            flowing.
          </Beat>
          <Say>
            When a period closes, the shelf already has the evidence. The numbers. The work
            completed. All of it built from what is already sitting in the cabinet&apos;s archive.
            Nobody sits down the night before to reconstruct a quarter from memory.
          </Say>
          <Say>
            The pipe runs under the floor, from the Done lane to the shelf. Close a card, and it is
            already where the review will read it from.
          </Say>
          <Say>
            By the numbers. Completed work. Two documents that wrote themselves from what you
            already finished.
          </Say>
          <Context>
            A period&apos;s review is generated from the cards already closed and dated: its own
            &quot;By the Numbers&quot; and &quot;Completed Work&quot; sections read straight off the
            archive (samples/hub/reviews/.../review.md; docs/hub/growth.md, reviews). Archive writes
            the Closed date into the card and moves it to the archive folder (docs/hub/cards.md,
            footer table). The review is generated on demand, not pushed: &quot;already where the
            review will read it from&quot; is the honest phrasing. The pipe under the floor runs
            from the Done lane to the shelf: the one slide where it is seen. Accumulation.
          </Context>
        </>
      ),
      content: <ReportingStage />,
    }),
    makeSlide({
      id: "the-studio-yours",
      title: "The Studio, Yours",
      eyebrow: "Slide 10 · Restoration",
      lead: "The room rests at dusk. The cabinet full, the ledger written, the shelf gathered. An import, an install, a start, and it is already yours.",
      notes: (
        <>
          <Beat>
            Let the three lines on the wall write themselves before the first line; let the button
            sit for a moment before closing.
          </Beat>
          <Say>
            Three lines built this room. An import, an install, a start, and you get a cabinet
            already settling, a wall already keeping the week, a shelf ready for the first thing you
            close.
          </Say>
          <Say>Your spaces. Your work. Your studio.</Say>
          <Say>This studio is yours. Take it home.</Say>
          <Context>
            The three-line install, import the module, install the autoload, start it, is the first
            three lines of the product&apos;s own quick start (README.md, &quot;Quick start&quot;).
            Payoff: the gift is the room itself, the same room slide 1 opened on, filled; the wall
            carries the identity and the three beats. The button is the repo link; say it out loud,
            do not say &quot;click here&quot;.
          </Context>
        </>
      ),
      content: <YoursStage />,
    }),
  ],
};
