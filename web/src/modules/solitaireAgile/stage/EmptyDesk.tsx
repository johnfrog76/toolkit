import type { ReactNode } from "react";
import { pf } from "./cast";

// ── The empty desk ───────────────────────────────────────────────────────────
//
// A window with nobody in it: an empty chair, a desk and a steaming mug. It is
// never a face and it never speaks; the standup's round passes it.
//
// Two things live here and nothing else: the deal (MUG_LOOKS and dealMugLooks),
// which says which mug each of the standup's empty windows gets, and the scene
// (EmptyDesk) the Org page draws in a vacant seat, picking its mug itself. The
// standup's room takes the deal, the mugs' names and the steam's rule from
// here and draws its own desk in the refined cast (./RefinedDesk.tsx); this
// scene is the Org page's, and is left as that page has always drawn it.
//
// The scene is one flat SVG in the stage's own palette (./cast.tsx `pf`), on
// the tint of the window it sits in. The stage is a picture of a video call and
// is drawn the same in every theme, so the desk follows the stage, not the
// shell's theme.

/** The mugs, in the order the deal shuffles. Add a look here and it is dealt. */
export const MUG_LOOKS = [
  "classic",
  "tall",
  "enamel",
  "straw",
  "espresso",
  "stripes",
  "heart",
  "teabag",
] as const;

export type MugLook = (typeof MUG_LOOKS)[number];

/** A small seeded generator (mulberry32): the same seed always gives the same run. */
function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * The mugs for one standup's empty windows, in window order.
 *
 * The day shuffles the looks; the windows take them in turn. So the same day
 * always deals the same mugs, and no look repeats until every look is out --
 * with eight looks and at most eight empty windows, never inside one room.
 * Past the number of looks it goes round again in the same order.
 *
 * @param dayOfYear the standup's day of the year (1-based, as the fill counts it)
 * @param emptyWindows how many windows have nobody in them
 */
export function dealMugLooks(dayOfYear: number, emptyWindows: number): MugLook[] {
  const order: MugLook[] = [...MUG_LOOKS];
  const next = seeded(Math.trunc(dayOfYear));
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(next() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  const count = Math.max(0, Math.trunc(emptyWindows));
  return Array.from({ length: count }, (_, i) => order[i % order.length]);
}

// ── The mugs ─────────────────────────────────────────────────────────────────
// Each is drawn standing on y = 0 and centred on x = 0, so the desk places it
// with one translate. `top` is where its rim is, which is where the steam starts.

const ink = "#0e1422";
const coffee = "#3b2415";
const cream = "#fff6e2";

interface MugArt {
  /** The rim's height above the desk, in the scene's units. */
  top: number;
  /** How far the steam sits from the centre line (a straw or a tag is in the way). */
  steamX?: number;
  art: ReactNode;
}

/** A side handle: an open ring on the right of a mug whose body ends at x. */
function Handle({ x, y, r, color }: { x: number; y: number; r: number; color: string }) {
  return (
    <path
      d={`M ${x} ${y - r} a ${r} ${r} 0 0 1 0 ${2 * r}`}
      fill="none"
      stroke={color}
      strokeWidth={2.4}
      strokeLinecap="round"
    />
  );
}

/** The coffee seen at the rim. */
function Rim({ w, y, liquid = coffee }: { w: number; y: number; liquid?: string }) {
  return (
    <>
      <ellipse cx={0} cy={y} rx={w} ry={1.9} fill={ink} opacity={0.55} />
      <ellipse cx={0} cy={y + 0.3} rx={w - 1.2} ry={1.2} fill={liquid} />
    </>
  );
}

const MUGS: Record<MugLook, MugArt> = {
  // The plain one: sand, a handle, a soft highlight.
  classic: {
    top: 17,
    art: (
      <>
        <Handle x={8} y={-9} r={4.6} color={pf.sand} />
        <rect x={-8} y={-17} width={16} height={17} rx={2.6} fill={pf.sand} />
        <rect x={-6} y={-14} width={2.2} height={11} rx={1.1} fill="#fff" opacity={0.35} />
        <Rim w={8} y={-17} />
      </>
    ),
  },
  // A tall travel cup: a lid, a sleeve, no handle.
  tall: {
    top: 28,
    art: (
      <>
        <path d="M -7 -26 L 7 -26 L 5.4 0 L -5.4 0 Z" fill={pf.sky} />
        <path d="M -6.6 -17 L 6.6 -17 L 6 -8 L -6 -8 Z" fill="#a9744a" />
        <path d="M -6.6 -17 L 6.6 -17 L 6.5 -15.6 L -6.5 -15.6 Z" fill="#000" opacity={0.18} />
        <rect x={-8} y={-28.4} width={16} height={3.2} rx={1.4} fill="#2a3350" />
        <rect x={-2.2} y={-29.6} width={4.4} height={1.6} rx={0.8} fill="#2a3350" />
        <path d="M -5 -25 L -4.2 -2" stroke="#fff" strokeWidth={1.2} opacity={0.3} />
      </>
    ),
  },
  // A green enamel camp mug: a dark lip and speckles.
  enamel: {
    top: 15,
    art: (
      <>
        <Handle x={9} y={-8} r={4.2} color={pf.green} />
        <path d="M -9 -15 L 9 -15 L 8 0 L -8 0 Z" fill={pf.green} />
        {[
          [-5, -11],
          [-1, -6],
          [4, -11.5],
          [5.5, -4],
          [-6, -3.5],
          [1, -2.5],
          [-2.5, -12.5],
        ].map(([x, y]) => (
          <circle key={`${x}:${y}`} cx={x} cy={y} r={0.65} fill="#fff" opacity={0.8} />
        ))}
        <Rim w={9} y={-15} />
        <ellipse cx={0} cy={-15} rx={9} ry={1.9} fill="none" stroke="#1d3b2c" strokeWidth={1.1} />
      </>
    ),
  },
  // A glass with a striped straw.
  straw: {
    top: 23,
    steamX: -3,
    art: (
      <>
        <path d="M 2 -21 L 8.5 -33" stroke={cream} strokeWidth={2.2} strokeLinecap="round" />
        <path
          d="M 2 -21 L 8.5 -33"
          stroke={pf.pink}
          strokeWidth={2.2}
          strokeLinecap="butt"
          strokeDasharray="2 2.4"
        />
        <path d="M -6.6 -17 L 6.6 -17 L 5.6 -1 L -5.6 -1 Z" fill="#8a5a36" />
        <path d="M -6.6 -17 L 6.6 -17 L 6.5 -15.4 L -6.5 -15.4 Z" fill={cream} opacity={0.75} />
        <path
          d="M -7.4 -23 L 7.4 -23 L 6 0 L -6 0 Z"
          fill="#cfe6ff"
          fillOpacity={0.16}
          stroke="#dcecff"
          strokeOpacity={0.75}
          strokeWidth={0.9}
        />
        <path d="M -5.2 -21 L -4.4 -3" stroke="#fff" strokeWidth={1.1} opacity={0.45} />
      </>
    ),
  },
  // An espresso cup on its saucer.
  espresso: {
    top: 10.5,
    art: (
      <>
        <ellipse cx={0} cy={-0.6} rx={12} ry={2.2} fill="#d9dfeb" />
        <ellipse cx={0} cy={-1.1} rx={8} ry={1.3} fill="#b9c2d4" />
        <Handle x={6} y={-6} r={2.6} color="#f3f5fa" />
        <path d="M -6.5 -10.5 L 6.5 -10.5 Q 6 -1.5 0 -1.5 Q -6 -1.5 -6.5 -10.5 Z" fill="#f3f5fa" />
        <Rim w={6.5} y={-10.5} liquid="#5a3418" />
      </>
    ),
  },
  // A wide mug in orange and cream stripes.
  stripes: {
    top: 14,
    art: (
      <>
        <Handle x={10} y={-7} r={4.2} color={pf.orange} />
        <rect x={-10} y={-14} width={20} height={14} rx={3} fill={pf.orange} />
        <rect x={-10} y={-10.6} width={20} height={2.4} fill={cream} />
        <rect x={-10} y={-5.8} width={20} height={2.4} fill={cream} />
        <Rim w={10} y={-14} />
      </>
    ),
  },
  // A pink mug with a heart on it.
  heart: {
    top: 17,
    art: (
      <>
        <Handle x={8} y={-9} r={4.6} color={pf.pink} />
        <rect x={-8} y={-17} width={16} height={17} rx={2.6} fill={pf.pink} />
        <path
          d="M 0 -5.4 C -6.4 -9.8 -3.2 -13.6 0 -10.6 C 3.2 -13.6 6.4 -9.8 0 -5.4 Z"
          fill={cream}
        />
        <Rim w={8} y={-17} />
      </>
    ),
  },
  // Tea: a purple mug with the string and tag over the side.
  teabag: {
    top: 16,
    steamX: 2,
    art: (
      <>
        <Handle x={8.5} y={-8.5} r={4.4} color={pf.purple} />
        <path d="M -8.5 -16 L 8.5 -16 L 7.4 0 L -7.4 0 Z" fill={pf.purple} />
        <Rim w={8.5} y={-16} liquid="#a8611f" />
        <path d="M -4 -16 Q -6.5 -17.5 -6.4 -9" fill="none" stroke={cream} strokeWidth={0.7} />
        <rect x={-8.8} y={-9} width={4.8} height={5.4} rx={0.8} fill={cream} />
        <rect x={-7.7} y={-7.6} width={2.6} height={1} fill={pf.red} />
      </>
    ),
  },
};

// ── The scene ────────────────────────────────────────────────────────────────

const CLASS = "ed-desk";

/**
 * The steam's motion, and the one rule that stills it. A wisp rests at the
 * opacity it is drawn with, so under reduced motion the steam is still there,
 * just not moving.
 */
export const EMPTY_DESK_CSS = `
@keyframes ed-steam {
  0% { transform: translate(0, 3px) scaleY(0.55); opacity: 0; }
  30% { opacity: 0.75; }
  100% { transform: translate(2.5px, -9px) scaleY(1.15); opacity: 0; }
}
.${CLASS} .ed-wisp { transform-box: fill-box; transform-origin: 50% 100%; animation: ed-steam 3.2s ease-out infinite; }
@media (prefers-reduced-motion: reduce) { .${CLASS} .ed-wisp { animation: none !important; } }
`;

/** Three wisps rising from a mug's rim, each on its own clock. */
function Steam({ x, y, scale }: { x: number; y: number; scale: number }) {
  const wisps = [
    { dx: -3.2, h: 13, delay: 0, dur: 3.2 },
    { dx: 0.4, h: 17, delay: -1.3, dur: 3.9 },
    { dx: 3.6, h: 12, delay: -2.2, dur: 3.5 },
  ];
  return (
    <g data-testid="empty-desk-steam" transform={`translate(${x} ${y}) scale(${scale})`}>
      {wisps.map((w, i) => (
        <path
          key={w.dx}
          className="ed-wisp"
          d={`M ${w.dx} -2 c -2.6 -${w.h / 4} 2.6 -${w.h / 2} 0 -${(3 * w.h) / 4} s -1.6 -${w.h / 5} 0.4 -${w.h / 3}`}
          fill="none"
          stroke="#fff"
          strokeWidth={1.7}
          strokeLinecap="round"
          opacity={0.42}
          style={{
            filter: "blur(0.7px)",
            animationDelay: `${w.delay}s`,
            animationDuration: `${w.dur}s`,
          }}
          data-wisp={i}
        />
      ))}
    </g>
  );
}

/** The tint an empty desk takes when its window gives it none: the stage's own slate. */
export const EMPTY_DESK_TINT = "#3d4a66";

/**
 * A window with nobody in it: fills its tile. `look` picks the mug -- deal a
 * room's empty windows with dealMugLooks so each gets a different one.
 *
 * The room is flat, like the cast's tiles: the window's `tint`, dimmed, with
 * the chair and the desk as darker and lighter cuts of it. Only the mug keeps
 * its full colour, so the mug is what tells one empty desk from the next.
 */
export function EmptyDesk({ look, tint = EMPTY_DESK_TINT }: { look: MugLook; tint?: string }) {
  const mug = MUGS[look];
  // Where the mug stands on the desk, in the scene's 160 x 90 space.
  const mugX = 108;
  const deskTop = 62;
  const mugY = deskTop + 9;
  // The mug is the subject, so it is drawn larger than the room around it.
  const scale = 1.5;
  return (
    <div
      className={CLASS}
      data-testid="empty-desk"
      data-look={look}
      role="img"
      aria-label="An empty desk with a steaming mug"
      style={{ position: "absolute", inset: 0, background: tint }}
    >
      <style>{EMPTY_DESK_CSS}</style>
      <svg
        viewBox="0 0 160 90"
        preserveAspectRatio="xMidYMid slice"
        width="100%"
        height="100%"
        style={{ display: "block" }}
        aria-hidden
      >
        {/* the room, dimmed: nobody has the light on */}
        <rect data-testid="empty-desk-dim" width="160" height="90" fill="#0d121e" opacity={0.5} />

        {/* the chair, pushed back and turned a little: nobody is in it. A headrest
            and arms, and no lines across the back: lines read as a page of text. */}
        <g data-testid="empty-desk-chair" transform="translate(-9 0) rotate(-7 66 50)">
          <rect x={63.5} y={52} width={5} height={22} rx={1.5} fill="#000" opacity={0.45} />
          {/* the arms, each on its post */}
          <rect x={40.5} y={50} width={3} height={14} rx={1.2} fill="#000" opacity={0.42} />
          <rect x={88.5} y={50} width={3} height={14} rx={1.2} fill="#000" opacity={0.42} />
          <rect x={36} y={47.5} width={12} height={4} rx={2} fill="#000" opacity={0.55} />
          <rect x={84} y={47.5} width={12} height={4} rx={2} fill="#000" opacity={0.55} />
          {/* the seat, seen just over the desk's edge, joining the arms */}
          <rect x={41} y={58} width={50} height={7} rx={3.5} fill="#000" opacity={0.4} />
          {/* the headrest on its neck */}
          <rect x={64} y={11} width={4} height={10} rx={1.2} fill="#000" opacity={0.45} />
          <rect x={53} y={3.5} width={26} height={11} rx={5.5} fill="#000" opacity={0.36} />
          <rect x={56.5} y={6} width={19} height={6} rx={3} fill="#fff" opacity={0.09} />
          {/* the back, wider at the shoulders than at the seat */}
          <path
            d="M 47 26 Q 47 18 55 18 L 77 18 Q 85 18 85 26 L 82.5 53 Q 82 58 77 58 L 55 58 Q 50 58 49.5 53 Z"
            fill="#000"
            opacity={0.34}
          />
          <path
            d="M 51 27 Q 51 22 56 22 L 76 22 Q 81 22 81 27 L 79 51 Q 78.6 54 75.5 54 L 56.5 54 Q 53.4 54 53 51 Z"
            fill="#fff"
            opacity={0.09}
          />
        </g>

        {/* the desk */}
        <rect x={0} y={deskTop} width={160} height={90 - deskTop} fill="#0b0f19" opacity={0.62} />
        <rect x={0} y={deskTop} width={160} height={1.4} fill="#fff" opacity={0.2} />

        {/* a closed laptop, its light still on */}
        <path d="M 24 67.5 L 60 67.5 L 63 72.5 L 21 72.5 Z" fill="#aab3c6" />
        <path d="M 21 72.5 L 63 72.5 L 63 74 L 21 74 Z" fill="#6f7990" />
        <circle cx={58} cy={73.2} r={0.7} fill={pf.green} />

        {/* the mug, its shadow and its steam */}
        <ellipse cx={mugX + 1.5} cy={mugY + 0.8} rx={18} ry={3.2} fill="#000" opacity={0.35} />
        <g data-testid="empty-desk-mug" transform={`translate(${mugX} ${mugY}) scale(${scale})`}>
          {mug.art}
        </g>
        <Steam x={mugX + (mug.steamX ?? 0) * scale} y={mugY - mug.top * scale} scale={scale} />
      </svg>
    </div>
  );
}
