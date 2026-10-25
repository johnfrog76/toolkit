import { createDarkTheme, createLightTheme } from "@fluentui/react-components";
import type { BrandVariants, Theme } from "@fluentui/react-components";
import { RAMP_STEPS, readableOn } from "../shared/accent";
import { themeById } from "./themeList";
import type { ToolkitTheme } from "./themeList";

// A named theme (themeList.ts, plain data) made into a Fluent theme. Fluent's
// own web themes carry everything; a Toolkit theme changes the accent and, for
// a FLAT theme, what a card is made of. Every card in the app is
// `colorNeutralBackgroundAlpha` (shared/PageCard.tsx), so one token is the
// whole difference between glass and flat -- no component knows which it is.

// Fluent derives some forty tokens from a sixteen-step brand ramp -- tinted
// badges, focus rings, links, a switch that is on. Overriding the five obvious
// ones left the rest Fluent's own blue, which is how a teal page grew a blue
// "demo" badge. So the whole ramp follows the accent. A named theme carries
// the product's ramp (shared/accent.ts, generated from one key); a Lounge
// skin, whose accent is its scene's, has one generated here from its button
// colour: same hue, sixteen lightnesses. The five named colours are then set
// on top, and the text on the brand fill is whichever of the theme's own text
// colours reads best on it -- by number, not by eye.
const LIGHTNESS = [5, 9, 13, 17, 21, 26, 31, 37, 43, 49, 55, 62, 69, 77, 85, 93];

function hexToHsl(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1, 7), 16);
  const r = ((n >> 16) & 255) / 255;
  const g = ((n >> 8) & 255) / 255;
  const b = (n & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l * 100];
  const d = max - min;
  const sat = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h *= 60;
  return [h, sat * 100, l * 100];
}

export function brandRamp(accent: string): BrandVariants {
  const [h, sat] = hexToHsl(accent);
  const ramp = {} as Record<(typeof RAMP_STEPS)[number], string>;
  RAMP_STEPS.forEach((step, i) => {
    // The ends of the ramp are nearly black and nearly white; full saturation
    // there reads as neon, so it eases off.
    const edge = Math.abs(i - 7.5) / 7.5;
    ramp[step] = `hsl(${h.toFixed(0)} ${(sat * (1 - 0.35 * edge)).toFixed(0)}% ${LIGHTNESS[i]}%)`;
  });
  return ramp;
}

const built = new Map<string, Theme>();

export function fluentThemeFor(t: ToolkitTheme): Theme {
  const hit = built.get(t.id);
  if (hit) return hit;
  const ramp = t.ramp ?? brandRamp(t.brand.background);
  const base = t.mode === "dark" ? createDarkTheme(ramp) : createLightTheme(ramp);
  const theme: Theme = {
    ...base,
    colorBrandBackground: t.brand.background,
    colorBrandBackgroundHover: t.brand.hover,
    colorBrandBackgroundPressed: t.brand.pressed,
    colorBrandForeground1: t.brand.foreground1,
    colorBrandForeground2: t.brand.foreground2,
    colorCompoundBrandBackground: t.brand.background,
    colorCompoundBrandBackgroundHover: t.brand.hover,
    colorCompoundBrandBackgroundPressed: t.brand.pressed,
    colorCompoundBrandStroke: t.brand.background,
    colorCompoundBrandForeground1: t.brand.foreground1,
    colorNeutralForegroundOnBrand: readableOn(t.brand.background, [
      base.colorNeutralForeground1,
      base.colorNeutralBackground1,
    ]),
    ...(t.card
      ? { colorNeutralBackgroundAlpha: t.card, colorNeutralBackgroundAlpha2: t.card }
      : {}),
  };
  built.set(t.id, theme);
  return theme;
}

// A deck is a room of its own and its stage is always dark, whatever the page
// is wearing -- so it asks for a theme by name, not for "the current one".
export const darkTheme: Theme = fluentThemeFor(themeById("aurora")!);

export const noiseSvgUrl =
  `data:image/svg+xml,` +
  encodeURIComponent(
    `<svg viewBox='0 0 50 50' xmlns='http://www.w3.org/2000/svg'>` +
      `<filter id='noiseFilter'>` +
      `<feTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/>` +
      `</filter>` +
      `<rect width='100%' height='100%' filter='url(#noiseFilter)'/>` +
      `</svg>`,
  );
