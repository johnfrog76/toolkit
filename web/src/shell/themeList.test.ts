import { FIRST_DARK, FIRST_LIGHT, THEMES, themeById } from "./themeList";
import { brandRamp, fluentThemeFor } from "./theme";

function luminance(hex: string): number {
  const n = parseInt(hex.slice(1, 7), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** A ramp step (`hsl(h s% l%)`, theme.ts) as the luminance of its RGB. */
function hslLuminance(hsl: string): number {
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

  // The one number that cannot be left to taste: white on the primary button.
  it("white text on every theme's primary button passes AA", () => {
    for (const t of THEMES) {
      const contrast = 1.05 / (luminance(t.brand.background) + 0.05);
      expect({ theme: t.id, ok: contrast >= 4.5 }).toEqual({ theme: t.id, ok: true });
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
        hslLuminance(fluent.colorBrandBackground2),
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
    const ramp = brandRamp("#b45309");
    expect(Object.keys(ramp)).toHaveLength(16);
    const basement = fluentThemeFor(themeById("basement")!);
    // Fluent's own blue is hue 206-212. A tinted badge must not be.
    expect(basement.colorBrandBackground2).not.toMatch(/^#0[0-9a-f]{5}$/i);
    expect(basement.colorBrandBackground2).toMatch(/^hsl\(2\d /); // amber, hue in the twenties
    expect(basement.colorNeutralBackgroundAlpha).toBe("#232326");
    expect(fluentThemeFor(themeById("basement")!)).toBe(basement); // built once
  });
});
