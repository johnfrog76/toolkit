// The product's accent: ONE key colour, and everything else read from it. This
// file is the one place it is typed, and two places read it: the landing page
// (landing/Landing.tsx) and the wordmark's DEFAULT blob (shared/Wordmark.tsx),
// so changing ACCENT_KEY changes the landing page's face, call to action and
// dots, and the default mark, together. The app's named themes do NOT read it:
// each keeps its own accent (shell/themeList.ts), and the app's logo wears the
// theme's blob, not this one. accent.test.ts holds the rest of src/ to that:
// no ramp hex typed anywhere else, and no theme reading this file.
//
// No import from Fluent, on purpose: the landing page and the wordmark are
// drawn without Fluent, and this file keeps them that way.

/** The key: rose. It is the ramp's 80, the step Fluent's Theme Designer puts a key colour at. */
export const ACCENT_KEY = "#c0285e";

export const RAMP_STEPS = [
  10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160,
] as const;
export type RampStep = (typeof RAMP_STEPS)[number];
/** Fluent's BrandVariants, by shape: sixteen steps, dark at 10 and light at 160. */
export type Ramp = Record<RampStep, string>;

// ---------------------------------------------------------------------------
// The ramp, GENERATED from the key -- never a step edited by hand. The method
// is the Theme Designer's in outline: the key sits at 80, the steps below it
// walk down to a near-black and the steps above it up to a near-white, the
// colour easing off toward both ends and its hue turning a little as it goes.
// It is worked in OKLCH, where a step of lightness looks like a step, and a
// colour outside sRGB loses chroma until it fits rather than being clipped.
// Wine is not a second key: it is this ramp's deep end.

/** OKLab lightness at 10 and at 160. */
const DEEP_L = 0.25;
const PALE_L = 0.985;
/** Above the key the lightness rises fast and then settles (1 is a straight line). */
const PALE_EASE = 1.25;
/** The share of the key's chroma both ends keep, and how fast each side gives the rest up. */
const CHROMA_FLOOR = 0.15;
const DEEP_FADE = 0.8;
const PALE_FADE = 0.4;
/** How far the hue turns by either end, in degrees: the ends lean cooler. */
const HUE_TURN = -18;

const KEY_STEP = 80;

function toLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

function fromLinear(c: number): number {
  return c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
}

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1, 7), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** sRGB hex to OKLCH: [lightness 0..1, chroma, hue in degrees]. */
function toOklch(hex: string): [number, number, number] {
  const [r, g, b] = hexToRgb(hex).map((v) => toLinear(v / 255));
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return [L, Math.hypot(A, B), (Math.atan2(B, A) * 180) / Math.PI];
}

/** OKLCH to linear sRGB, which may fall outside 0..1. */
function oklchToLinear(L: number, C: number, H: number): [number, number, number] {
  const A = C * Math.cos((H * Math.PI) / 180);
  const B = C * Math.sin((H * Math.PI) / 180);
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

const fits = (rgb: number[]) => rgb.every((v) => v >= -1e-4 && v <= 1 + 1e-4);

function oklchToHex(L: number, C: number, H: number): string {
  let chroma = C;
  if (!fits(oklchToLinear(L, chroma, H))) {
    let [lo, hi] = [0, C];
    for (let i = 0; i < 30; i++) {
      const mid = (lo + hi) / 2;
      if (fits(oklchToLinear(L, mid, H))) lo = mid;
      else hi = mid;
    }
    chroma = lo;
  }
  return (
    "#" +
    oklchToLinear(L, chroma, H)
      .map((v) =>
        Math.round(Math.min(1, Math.max(0, fromLinear(v))) * 255)
          .toString(16)
          .padStart(2, "0"),
      )
      .join("")
  );
}

/** The sixteen-step ramp for a key colour, the key itself at 80. */
export function accentRamp(key: string): Ramp {
  const [keyL, keyC, keyH] = toOklch(key);
  const ramp = {} as Ramp;
  for (const step of RAMP_STEPS) {
    if (step === KEY_STEP) {
      ramp[step] = key.toLowerCase();
      continue;
    }
    const deep = step < KEY_STEP;
    // How far from the key toward this side's end, 0..1.
    const t = deep ? (KEY_STEP - step) / (KEY_STEP - 10) : (step - KEY_STEP) / (160 - KEY_STEP);
    const L = deep
      ? keyL + (DEEP_L - keyL) * t
      : keyL + (PALE_L - keyL) * (1 - (1 - t) ** PALE_EASE);
    const C =
      keyC * (CHROMA_FLOOR + (1 - CHROMA_FLOOR) * (1 - t) ** (deep ? DEEP_FADE : PALE_FADE));
    ramp[step] = oklchToHex(L, C, keyH + HUE_TURN * Math.sqrt(t));
  }
  return ramp;
}

/** The product's ramp. */
export const ACCENT: Ramp = accentRamp(ACCENT_KEY);

// ---------------------------------------------------------------------------
// Where the accent shows, as steps of the ramp, per mode.
//   face    -- the blob behind the wordmark's o's. Wine on dark: the ramp's 40.
//              On light it is the deepest step under which a light theme's
//              dark ink still reads at AA (accent.test.ts computes it).
//   dot     -- the way-of-working dot, and the links beside it: the key on
//              light, 110 on dark.
//   button  -- the call to action: the key in both modes; hover and pressed
//              go deeper, so the text chosen for the key holds on all three.
//   tint    -- a tint's text, the palest (dark) or deepest (light) of them.
// The landing page is dark and wears the dark steps, as does the wordmark's
// default blob. The light steps are kept, held by accent.test.ts, for a light
// page that wears the accent; none does today.
export type AccentMode = "light" | "dark";

export const ACCENT_STEPS: Record<
  AccentMode,
  Record<"face" | "dot" | "button" | "hover" | "pressed" | "tint", RampStep>
> = {
  light: { face: 100, dot: 80, button: 80, hover: 70, pressed: 60, tint: 70 },
  dark: { face: 40, dot: 110, button: 80, hover: 70, pressed: 60, tint: 120 },
};

export interface AccentColors {
  face: string;
  dot: string;
  button: string;
  hover: string;
  pressed: string;
  tint: string;
}

export function accentFor(mode: AccentMode, ramp: Ramp = ACCENT): AccentColors {
  const s = ACCENT_STEPS[mode];
  return {
    face: ramp[s.face],
    dot: ramp[s.dot],
    button: ramp[s.button],
    hover: ramp[s.hover],
    pressed: ramp[s.pressed],
    tint: ramp[s.tint],
  };
}

/** The key with an alpha, for a wash of it (`#rrggbbaa`). */
export function accentWash(alpha: number, color: string = ACCENT_KEY): string {
  return `${color}${Math.round(alpha * 255)
    .toString(16)
    .padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// Contrast, by WCAG 2's formula -- so a text colour on the accent is chosen
// by number and never assumed.

/** The text contrast WCAG AA asks of body text. */
export const AA_TEXT = 4.5;

export function relativeLuminance(hex: string): number {
  const [r, g, b] = hexToRgb(hex).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrastRatio(a: string, b: string): number {
  const [hi, lo] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/** Of a theme's text colours, the one that reads best on `fill`. */
export function readableOn(fill: string, candidates: readonly string[]): string {
  return candidates.reduce((best, c) =>
    contrastRatio(c, fill) > contrastRatio(best, fill) ? c : best,
  );
}
