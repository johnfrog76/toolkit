import type { ReactNode } from "react";
import { pf } from "./cast";
import { EMPTY_DESK_CSS, EMPTY_DESK_TINT } from "./EmptyDesk";
import type { MugLook } from "./EmptyDesk";
import { Soft, dark, useDrawingId } from "./refined";

// ── The empty desk, in the refined cast ──────────────────────────────────────
//
// What the standup's room draws in a window with nobody in it: a flat-backed
// chair pushed back, a shut laptop, and a steaming drink, in full colour. The
// room's light is off -- a wash in the drawing, under the wall's own light --
// so the steam shows on any tint; nothing is filtered, and the drink is what
// says the seat is empty.
//
// The eight drinks keep the names and the deal the stage has always had
// (./EmptyDesk.tsx MUG_LOOKS and dealMugLooks), and the steam keeps its motion:
// the same three wisps on the same clocks, under the same rule
// (EMPTY_DESK_CSS), which stills them under reduced motion.
//
// Drawn in the refined style (./refined.tsx): a fill, what is printed on it, one
// shade crescent on the right, one highlight on the left, and no outlines.

const coffee = "#3b2415";
const cream = "#fff6e2";

/** Two decimals, so a computed coordinate reads the same wherever it is rendered. */
const f = (n: number) => +n.toFixed(2);

interface MugArt {
  /** The rim's height above the desk, in the drink's own units. */
  top: number;
  /** Half the drink's width on the desk: its shadow's reach. */
  half: number;
  /** How far the steam sits from the centre line (a straw or a tag is in the way). */
  steamX?: number;
  /** The drawing, standing on y = 0 and centred on x = 0; `id` prefixes its clips. */
  art: (id: string) => ReactNode;
}

/** A side handle: an open ring on the right of a mug whose body ends at x, a step darker than the mug. */
function Handle({ x, y, r, color }: { x: number; y: number; r: number; color: string }) {
  return (
    <path
      d={`M ${x} ${y - r} a ${r} ${r} 0 0 1 0 ${2 * r}`}
      fill="none"
      stroke={dark(color, 0.2)}
      strokeWidth={2.5}
      strokeLinecap="round"
    />
  );
}

/** The drink seen at the rim: the lip's shade, then the liquid. */
function Rim({ w, y, liquid, color }: { w: number; y: number; liquid: string; color: string }) {
  return (
    <>
      <ellipse cx={0} cy={y} rx={w} ry={1.9} fill={dark(color, 0.45)} />
      <ellipse cx={0} cy={y + 0.3} rx={w - 1.2} ry={1.2} fill={liquid} />
    </>
  );
}

/**
 * A drink's body: its shape in one fill, whatever is printed on it, the shade
 * crescent down the right side, and (unless it has one of its own) the
 * highlight down the left.
 */
function Body({
  id,
  fill,
  x0,
  x1,
  top,
  bottom,
  over,
  highlight = true,
  children,
}: {
  id: string;
  fill: string;
  x0: number;
  x1: number;
  top: number;
  bottom: number;
  over?: ReactNode;
  highlight?: boolean;
  /** The shape, with no fill of its own. */
  children: ReactNode;
}) {
  const w = x1 - x0;
  const bx = x1 - w * 0.2;
  const my = (top + bottom) / 2;
  return (
    <>
      <clipPath id={id}>{children}</clipPath>
      <g fill={fill}>{children}</g>
      <g clipPath={`url(#${id})`}>
        {over}
        <path
          d={`M ${f(bx)} ${top - 3} Q ${f(bx - w * 0.13)} ${f(my)} ${f(bx)} ${bottom + 3} H ${x1 + 4} V ${top - 3} Z`}
          fill="#000"
          opacity={0.16}
        />
      </g>
      {highlight && (
        <rect
          x={f(x0 + 1.7)}
          y={f(top + 3.2)}
          width={1.8}
          height={f(Math.max(2, bottom - top - 7))}
          rx={0.9}
          fill="#fff"
          opacity={0.36}
        />
      )}
    </>
  );
}

const MUGS: Record<MugLook, MugArt> = {
  // The plain one: sand, a handle, a soft highlight.
  classic: {
    top: 17,
    half: 13.5,
    art: (id) => (
      <>
        <Handle x={8} y={-9} r={4.6} color={pf.sand} />
        <Body id={`${id}-b`} fill={pf.sand} x0={-8} x1={8} top={-17} bottom={0}>
          <rect x={-8} y={-17} width={16} height={17} rx={2.6} />
        </Body>
        <Rim w={8} y={-17} liquid={coffee} color={pf.sand} />
      </>
    ),
  },
  // A tall travel cup: a lid, a sleeve, no handle.
  tall: {
    top: 30,
    half: 9,
    art: (id) => (
      <>
        <Body
          id={`${id}-b`}
          fill={pf.sky}
          x0={-7}
          x1={7}
          top={-26}
          bottom={0}
          over={
            <>
              <path d="M -7 -17 L 7 -17 L 7 -8 L -7 -8 Z" fill="#a9744a" />
              <path d="M -7 -17 H 7 V -15.8 H -7 Z" fill="#000" opacity={0.14} />
            </>
          }
        >
          <path d="M -7 -26 L 7 -26 L 5.4 0 L -5.4 0 Z" />
        </Body>
        <Soft id={`${id}-l`} fill="#3a4670" shade="#232b47" dx={-3.4} dy={0}>
          <rect x={-8} y={-28.4} width={16} height={3.2} rx={1.4} />
          <rect x={-2.4} y={-30} width={4.8} height={2.4} rx={1} />
        </Soft>
      </>
    ),
  },
  // A green enamel camp mug: a dark lip and speckles.
  enamel: {
    top: 15,
    half: 14.5,
    art: (id) => (
      <>
        <Handle x={9} y={-8} r={4.2} color={pf.green} />
        <Body
          id={`${id}-b`}
          fill={pf.green}
          x0={-9}
          x1={9}
          top={-15}
          bottom={0}
          over={
            <>
              <path d="M -9 -15 H 9 V -13.3 H -9 Z" fill="#1d3b2c" />
              {[
                [-5, -10.5],
                [-1, -6],
                [3.4, -10.8],
                [4.6, -4],
                [-6, -3.5],
                [0.6, -2.2],
                [-2.5, -11.8],
                [-3.8, -7.2],
              ].map(([x, y]) => (
                <circle key={`${x}:${y}`} cx={x} cy={y} r={0.65} fill="#fff" opacity={0.85} />
              ))}
            </>
          }
        >
          <path d="M -9 -15 L 9 -15 L 8 0 L -8 0 Z" />
        </Body>
        <Rim w={9} y={-15} liquid={coffee} color="#1d3b2c" />
      </>
    ),
  },
  // A glass with a striped straw.
  straw: {
    top: 23,
    half: 9.5,
    steamX: -3,
    art: (id) => (
      <>
        <path d="M 2 -20 L 8.5 -33" stroke={cream} strokeWidth={2.3} strokeLinecap="round" />
        <path d="M 2 -20 L 8.5 -33" stroke={pf.pink} strokeWidth={2.3} strokeDasharray="2 2.4" />
        <Body
          id={`${id}-d`}
          fill="#8a5a36"
          x0={-6.7}
          x1={6.7}
          top={-17.5}
          bottom={-1}
          highlight={false}
          over={<path d="M -7 -17.5 H 7 V -14.6 H -7 Z" fill={cream} opacity={0.9} />}
        >
          <path d="M -6.7 -17.5 L 6.7 -17.5 L 5.6 -1 L -5.6 -1 Z" />
        </Body>
        <Body id={`${id}-b`} fill="rgba(207,230,255,0.2)" x0={-7.4} x1={7.4} top={-23} bottom={0}>
          <path d="M -7.4 -23 L 7.4 -23 L 6 0 L -6 0 Z" />
        </Body>
        <rect x={-7.4} y={-23.4} width={14.8} height={1.2} rx={0.6} fill="#eaf3ff" opacity={0.75} />
      </>
    ),
  },
  // An espresso cup on its saucer.
  espresso: {
    top: 10.5,
    half: 13.5,
    art: (id) => (
      <>
        <Soft id={`${id}-s`} fill="#e3e8f2" shade="#b4bdcf" dx={-3.4} dy={-0.3}>
          <ellipse cx={0} cy={-0.6} rx={12} ry={2.2} />
        </Soft>
        <ellipse cx={-0.6} cy={-1.2} rx={7.4} ry={1.1} fill="#000" opacity={0.14} />
        <Handle x={6} y={-6.4} r={2.6} color="#f3f5fa" />
        <Body
          id={`${id}-b`}
          fill="#f3f5fa"
          x0={-6.5}
          x1={6.5}
          top={-10.5}
          bottom={-2}
          highlight={false}
        >
          <path d="M -6.5 -10.5 L 6.5 -10.5 Q 6 -1.5 0 -1.5 Q -6 -1.5 -6.5 -10.5 Z" />
        </Body>
        <Rim w={6.5} y={-10.5} liquid="#6b3d1c" color="#b9c2d4" />
      </>
    ),
  },
  // A wide mug in orange and cream stripes.
  stripes: {
    top: 14,
    half: 15.5,
    art: (id) => (
      <>
        <Handle x={10} y={-7} r={4.2} color={pf.orange} />
        <Body
          id={`${id}-b`}
          fill={pf.orange}
          x0={-10}
          x1={10}
          top={-14}
          bottom={0}
          over={
            <>
              <rect x={-10} y={-10.6} width={20} height={2.4} fill={cream} />
              <rect x={-10} y={-5.8} width={20} height={2.4} fill={cream} />
            </>
          }
        >
          <rect x={-10} y={-14} width={20} height={14} rx={3} />
        </Body>
        <Rim w={10} y={-14} liquid={coffee} color={pf.orange} />
      </>
    ),
  },
  // A pink mug with a round belly and a heart on it.
  heart: {
    top: 17,
    half: 15,
    art: (id) => (
      <>
        <Handle x={9.2} y={-8.6} r={4.4} color={pf.pink} />
        <Body
          id={`${id}-b`}
          fill={pf.pink}
          x0={-9.6}
          x1={9.6}
          top={-17}
          bottom={0}
          highlight={false}
          over={
            <path
              d="M 0 -4.2 C -7.2 -9.2 -3.6 -13.6 0 -10.2 C 3.6 -13.6 7.2 -9.2 0 -4.2 Z"
              fill={cream}
            />
          }
        >
          <path d="M -7.6 -17 L 7.6 -17 C 11 -11.5 10 -3 6 0 L -6 0 C -10 -3 -11 -11.5 -7.6 -17 Z" />
        </Body>
        <rect x={-7} y={-13.6} width={1.8} height={8.4} rx={0.9} fill="#fff" opacity={0.36} />
        <Rim w={7.6} y={-17} liquid={coffee} color={pf.pink} />
      </>
    ),
  },
  // Tea: a purple mug with the string and tag over the side.
  teabag: {
    top: 16,
    half: 14,
    steamX: 2,
    art: (id) => (
      <>
        <Handle x={8.5} y={-8.5} r={4.4} color={pf.purple} />
        <Body
          id={`${id}-b`}
          fill={pf.purple}
          x0={-8.5}
          x1={8.5}
          top={-16}
          bottom={0}
          highlight={false}
        >
          <path d="M -8.5 -16 L 8.5 -16 L 7.4 0 L -7.4 0 Z" />
        </Body>
        <Rim w={8.5} y={-16} liquid="#b8702a" color={pf.purple} />
        <path
          d="M -4 -16 Q -6.8 -17.8 -6.4 -9"
          fill="none"
          stroke={cream}
          strokeWidth={0.8}
          strokeLinecap="round"
        />
        <Soft id={`${id}-t`} fill={cream} shade={dark(cream, 0.2)} dx={-1.2} dy={0}>
          <rect x={-9} y={-9.2} width={5.2} height={6} rx={0.9} />
        </Soft>
        <rect x={-8} y={-7.6} width={2.6} height={1.1} rx={0.3} fill={pf.red} />
      </>
    ),
  },
};

/** Three wisps rising from a drink's rim, each on its own clock: the stage's steam, as it has always moved. */
function Steam({ x, y, scale }: { x: number; y: number; scale: number }) {
  const wisps = [
    { dx: -3.2, h: 13, delay: 0, dur: 3.2 },
    { dx: 0.4, h: 17, delay: -1.3, dur: 3.9 },
    { dx: 3.6, h: 12, delay: -2.2, dur: 3.5 },
  ];
  return (
    <g data-testid="empty-desk-steam" transform={`translate(${f(x)} ${f(y)}) scale(${scale})`}>
      {wisps.map((w, i) => (
        <path
          key={w.dx}
          className="ed-wisp"
          d={`M ${w.dx} -2 c -2.6 -${w.h / 4} 2.6 -${w.h / 2} 0 -${(3 * w.h) / 4} s -1.6 -${f(w.h / 5)} 0.4 -${f(w.h / 3)}`}
          fill="none"
          stroke="#fff"
          strokeWidth={2.1}
          strokeLinecap="round"
          opacity={0.75}
          style={{
            filter: "blur(0.5px)",
            animationDelay: `${w.delay}s`,
            animationDuration: `${w.dur}s`,
          }}
          data-wisp={i}
        />
      ))}
    </g>
  );
}

// The scene's own space: 250 by 145, the desk's edge at y = 104. A window shows
// the 170 units in the middle of it, and keeps the desk when it is cut short.
const W = 250;
const H = 145;
const DESK = 104;
const VIEW = `40 0 170 ${H}`;
/** Where the drink stands, and how large: it is the subject, so it is drawn larger than the room. */
const MUG_X = 169;
const MUG_Y = 125;
const MUG_SCALE = 2.3;
/** How far the room's light is down. Part of the drawing: no filter is involved. */
const LIGHT_OFF = 0.42;

/**
 * A window with nobody in it: fills its tile. `look` picks the drink -- deal a
 * room's empty windows with dealMugLooks so each gets a different one.
 */
export function RefinedDesk({ look, tint = EMPTY_DESK_TINT }: { look: MugLook; tint?: string }) {
  const id = useDrawingId("rd");
  const mug = MUGS[look];
  return (
    <div
      className="ed-desk"
      data-testid="empty-desk"
      data-look={look}
      role="img"
      aria-label="An empty desk with a steaming mug"
      style={{ position: "absolute", inset: 0, background: tint }}
    >
      <style>{EMPTY_DESK_CSS}</style>
      <svg
        viewBox={VIEW}
        preserveAspectRatio="xMidYMax slice"
        width="100%"
        height="100%"
        style={{ display: "block" }}
        aria-hidden
      >
        <defs>
          <filter id={`${id}-sh`} x="-20%" y="-20%" width="150%" height="150%">
            <feDropShadow
              dx="2.2"
              dy="1.9"
              stdDeviation="1.6"
              floodColor="#040814"
              floodOpacity="0.3"
            />
          </filter>
          <filter id={`${id}-soft`} x="-30%" y="-60%" width="160%" height="220%">
            <feGaussianBlur stdDeviation="0.9" />
          </filter>
          <linearGradient id={`${id}-wall`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#fff" stopOpacity="0.16" />
            <stop offset="0.55" stopColor="#fff" stopOpacity="0" />
            <stop offset="1" stopColor="#000" stopOpacity="0.16" />
          </linearGradient>
          <clipPath id={`${id}-back`}>
            <rect x={56} y={22} width={72} height={68} rx={15} />
          </clipPath>
        </defs>

        {/* the room, its light off, and the wall's own light over it */}
        <rect
          data-testid="empty-desk-dim"
          width={W}
          height={H}
          fill="#0d121e"
          opacity={LIGHT_OFF}
        />
        <rect width={W} height={H} fill={`url(#${id}-wall)`} />

        {/* the chair, pushed back and turned a little: a flat back, two arms, one post */}
        <g data-testid="empty-desk-chair" transform="rotate(-6 92 70)" filter={`url(#${id}-sh)`}>
          <rect x={88} y={84} width={8} height={34} rx={2} fill="#0a0e18" opacity={0.7} />
          <rect x={43} y={82} width={17} height={6.4} rx={3.2} fill="#0a0e18" opacity={0.74} />
          <rect x={124} y={82} width={17} height={6.4} rx={3.2} fill="#0a0e18" opacity={0.74} />
          <rect x={56} y={22} width={72} height={68} rx={15} fill="#0e1422" opacity={0.62} />
          <rect x={62} y={28} width={60} height={56} rx={10} fill="#fff" opacity={0.1} />
          <path
            d="M 71 44 H 113 M 71 56 H 113 M 71 68 H 113"
            stroke="#000"
            strokeWidth={2}
            opacity={0.26}
            strokeLinecap="round"
          />
          <path
            d="M 112 18 Q 103 56 112 94 H 132 V 18 Z"
            fill="#000"
            opacity={0.2}
            clipPath={`url(#${id}-back)`}
          />
        </g>

        {/* the desk */}
        <rect x={0} y={DESK} width={W} height={H - DESK} fill="#0b0f19" opacity={0.66} />
        <rect x={0} y={DESK} width={W} height={1} fill="#fff" opacity={0.22} />

        {/* a shut laptop, its light still on */}
        <path d="M 53 109.5 L 101 109.5 L 106 116 L 48 116 Z" fill="#aab3c6" />
        <path d="M 90 109.5 L 101 109.5 L 106 116 L 93 116 Z" fill="#000" opacity={0.12} />
        <rect x={48} y={116} width={58} height={2.4} rx={1.2} fill="#6f7990" />
        <circle cx={100.5} cy={117.2} r={0.9} fill={pf.green} />

        {/* the drink, its shadow and its steam */}
        <ellipse
          cx={f(MUG_X + 3.2 * MUG_SCALE)}
          cy={f(MUG_Y + 0.6 * MUG_SCALE)}
          rx={f(mug.half * MUG_SCALE)}
          ry={f(2.1 * MUG_SCALE)}
          fill="#000"
          opacity={0.32}
          filter={`url(#${id}-soft)`}
        />
        <g
          data-testid="empty-desk-mug"
          transform={`translate(${MUG_X} ${MUG_Y}) scale(${MUG_SCALE})`}
        >
          {mug.art(id)}
        </g>
        <Steam
          x={MUG_X + (mug.steamX ?? 0) * MUG_SCALE}
          y={MUG_Y - mug.top * MUG_SCALE}
          scale={MUG_SCALE}
        />
      </svg>
    </div>
  );
}
