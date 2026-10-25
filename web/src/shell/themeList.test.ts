import { FIRST_DARK, FIRST_LIGHT, SKIN_THEMES, THEMES, themeById } from "./themeList";
import { brandRamp, fluentThemeFor } from "./theme";
import { ACCENT } from "../shared/accent";

function luminance(hex: string): number {
  const n = parseInt(hex.slice(1, 7), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** A ramp step as the luminance of its RGB: a hex (the product's ramp,
 *  shared/accent.ts) or `hsl(h s% l%)` (a skin's, theme.ts). */
function stepLuminance(step: string): number {
  if (step.startsWith("#")) return luminance(step);
  const hsl = step;
  const [h, s, l] = (/hsl\((\d+) (\d+)% (\d+)%\)/.exec(hsl) ?? []).slice(1).map(Number);
  const a = (s / 100) * Math.min(l / 100, 1 - l / 100);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    return l / 100 - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  const hex =
    "#" +
    [f(0), f(8), f(4)]
      .map((v) =>
        Math.round(v * 255)
          .toString(16)
          .padStart(2, "0"),
      )
      .join("");
  return luminance(hex);
}

describe("themes", () => {
  it("is a flat list of named themes, some dark and some light", () => {
    expect(new Set(THEMES.map((t) => t.id)).size).toBe(THEMES.length);
    expect(THEMES.some((t) => t.mode === "dark")).toBe(true);
    expect(THEMES.some((t) => t.mode === "light")).toBe(true);
    // Both kinds are wanted: the translucent look, and functional classic.
    for (const mode of ["dark", "light"] as const) {
      const kinds = THEMES.filter((t) => t.mode === mode).map((t) => t.kind);
      expect(kinds).toEqual(expect.arrayContaining(["glass", "flat"]));
    }
  });

  it("a flat theme is opaque all the way down; a glass theme has a gradient", () => {
    for (const t of THEMES) {
      if (t.kind === "flat") {
        expect(t.page.image).toBe("none");
        expect(t.grain).toBe(0);
        expect(t.card).toMatch(/^#[0-9a-f]{6}$/i);
      } else {
        expect(t.page.image).toMatch(/gradient/);
      }
    }
  });

  // The one number that cannot be left to taste: the text on the primary
  // button -- the product's accent at rest, hovered and pressed in every named
  // theme, and a Lounge skin's own at rest.
  it("the text on every theme's primary button passes AA", () => {
    for (const t of [...THEMES, ...Object.values(SKIN_THEMES)]) {
      const fluent = fluentThemeFor(t);
      const text = luminance(fluent.colorNeutralForegroundOnBrand);
      const fills = t.ramp
        ? [t.brand.background, t.brand.hover, t.brand.pressed]
        : [t.brand.background];
      for (const fill of fills) {
        const [hi, lo] = [text, luminance(fill)].sort((x, y) => y - x);
        const contrast = (hi + 0.05) / (lo + 0.05);
        expect({ theme: t.id, fill, ok: contrast >= 4.5 }).toEqual({ theme: t.id, fill, ok: true });
      }
    }
  });

  // A tint badge (appearance="tint" color="brand") is colorBrandForeground2
  // on colorBrandBackground2, at 10px -- axe's color-contrast wants 4.5:1. It
  // failed in seaglass (3.35) and aurora (4.32) until their foreground2 moved.
  it("a brand tint badge's text passes AA on its background in every theme", () => {
    for (const t of THEMES) {
      const fluent = fluentThemeFor(t);
      const [hi, lo] = [
        luminance(fluent.colorBrandForeground2),
        stepLuminance(fluent.colorBrandBackground2),
      ].sort((x, y) => y - x);
      const contrast = (hi + 0.05) / (lo + 0.05);
      expect({ theme: t.id, ok: contrast >= 4.5 }).toEqual({ theme: t.id, ok: true });
    }
  });

  it("what the key held before themes had names still means a theme", () => {
    expect(themeById("dark")?.mode).toBe("dark");
    expect(themeById("light")?.mode).toBe("light");
    expect(themeById("no-such-theme")).toBeUndefined();
    expect(themeById(null)).toBeUndefined();
    expect(themeById(FIRST_DARK)?.mode).toBe("dark");
    expect(themeById(FIRST_LIGHT)?.mode).toBe("light");
  });

  it("the whole accent follows the theme, not five tokens of it", () => {
    // A named theme wears the product's ramp, every step of it.
    const basement = fluentThemeFor(themeById("basement")!);
    expect(basement.colorBrandBackground2).toBe(ACCENT[20]);
    expect(basement.colorBrandBackground).toBe(ACCENT[80]);
    expect(basement.colorNeutralBackgroundAlpha).toBe("#232326");
    expect(fluentThemeFor(themeById("basement")!)).toBe(basement); // built once
    // A Lounge skin keeps its scene's accent, its ramp generated from it.
    const ramp = brandRamp(SKIN_THEMES.temple.brand.background);
    expect(Object.keys(ramp)).toHaveLength(16);
    const temple = fluentThemeFor(SKIN_THEMES.temple);
    // Fluent's own blue is hue 206-212. A tinted badge must not be.
    expect(temple.colorBrandBackground2).toBe(ramp[20]);
    expect(temple.colorBrandBackground2).toMatch(/^hsl\(0 /); // lacquer red, hue zero
  });
});
