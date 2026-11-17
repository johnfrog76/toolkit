import fs from "node:fs";
import path from "node:path";
import {
  CHIP_APPEARANCES,
  chipToken,
  FIRST_DARK,
  FIRST_LIGHT,
  SKIN_THEMES,
  THEMES,
  themeById,
} from "./themeList";
import type { ToolkitTheme } from "./themeList";
import { brandRamp, fluentThemeFor } from "./theme";
import { AA_TEXT, contrastRatio } from "../shared/accent";

const EVERY_THEME: ToolkitTheme[] = [...THEMES, ...Object.values(SKIN_THEMES)];

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

  // Every named theme wears its OWN accent: the product's (shared/accent.ts)
  // is the landing page's and the wordmark's default, never a theme's. So a
  // theme changes only on purpose. fixtures/themes-364.json is the themes as
  // rendered when the filter chips' colours joined them (#364): every theme's
  // record and the whole Fluent theme fluentThemeFor() made of it, the six
  // named themes and the two skins, written by a throwaway jest test that
  // JSON.stringify'd `{ record: t, fluent: fluentThemeFor(t) }` for each. It
  // replaced themes-93d9d88.json (the 1.4.0 themes, before the one-accent
  // change), whose every value it holds, plus `chips` and the four chip tokens.
  // A theme that changes on purpose regenerates the fixture the same way and
  // says so in its commit.
  it("every theme renders exactly as the fixture says, chips included", () => {
    const before = JSON.parse(
      fs.readFileSync(path.join(__dirname, "fixtures", "themes-364.json"), "utf8"),
    ) as Record<string, { record: unknown; fluent: unknown }>;
    expect(EVERY_THEME.map((t) => t.id)).toEqual(Object.keys(before));
    for (const t of EVERY_THEME) {
      expect({ id: t.id, record: JSON.parse(JSON.stringify(t)) }).toEqual({
        id: t.id,
        record: before[t.id].record,
      });
      expect({ id: t.id, fluent: JSON.parse(JSON.stringify(fluentThemeFor(t))) }).toEqual({
        id: t.id,
        fluent: before[t.id].fluent,
      });
      // The four appearances, in all eight themes, on the record and on the Fluent theme.
      const fluent = fluentThemeFor(t) as unknown as Record<string, string>;
      for (const a of CHIP_APPEARANCES) expect(fluent[chipToken(a)]).toBe(t.chips[a]);
    }
  });

  it("no named theme reads the product's accent", () => {
    for (const file of ["themeList.ts", "theme.ts"]) {
      const src = fs.readFileSync(path.join(__dirname, file), "utf8");
      expect({ file, imports: /shared\/accent/.test(src) }).toEqual({ file, imports: false });
    }
  });
});

describe("brand foreground on a card", () => {
  // The issue popover's trigger is a Link painted with these two (the ramp's own
  // link step fails AA on a card in Seaglass and Aurora).
  it.each(THEMES.map((t) => [t.id, t] as const))(
    "%s: foreground1 and foreground2 clear AA on the card face",
    (_id, t) => {
      const f = fluentThemeFor(t);
      for (const ink of [f.colorBrandForeground1, f.colorBrandForeground2]) {
        expect(contrastRatio(ink, f.colorNeutralBackground1)).toBeGreaterThanOrEqual(AA_TEXT);
      }
    },
  );
});

// The filter chips' named appearances (shared/FilterBadge.tsx): a call site names a slot,
// and each theme says what the slot is. Eight themes: the six pickable and the two skins.
const HEX = /^#[0-9a-f]{6}$/i;

/** A chip's own backdrop in a theme: the page, and the card where it is an opaque hex. */
function chipBackdrops(t: ToolkitTheme): string[] {
  return [t.page.color, ...(t.card && HEX.test(t.card) ? [t.card] : [])];
}

/** How far apart two colours are in sRGB, 0 to about 441. */
function rgbDistance(a: string, b: string): number {
  const [x, y] = [a, b].map((h) => {
    const n = parseInt(h.slice(1, 7), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  });
  return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]);
}

describe("filter chip appearances", () => {
  it("there are eight themes, and the appearances are the four named ones", () => {
    expect(EVERY_THEME).toHaveLength(8);
    expect([...CHIP_APPEARANCES]).toEqual([
      "tabColorOne",
      "tabColorTwo",
      "tabColorThree",
      "tabColorFour",
    ]);
  });

  it.each(EVERY_THEME.map((t) => [t.id, t] as const))(
    "%s defines every appearance, and nothing else",
    (_id, t) => {
      expect(Object.keys(t.chips).sort()).toEqual([...CHIP_APPEARANCES].sort());
      for (const a of CHIP_APPEARANCES)
        expect({ a, hex: t.chips[a] }).toEqual({ a, hex: expect.stringMatching(HEX) });
    },
  );

  it("a theme that leaves an appearance out is caught", () => {
    const { tabColorFour: _four, ...three } = THEMES[0].chips;
    const broken = { ...THEMES[0], chips: three } as unknown as ToolkitTheme;
    expect(Object.keys(broken.chips).sort()).not.toEqual([...CHIP_APPEARANCES].sort());
  });

  // A selected chip's border is its colour against the page (and the card). 4.5:1, the bar
  // brand.foreground2 is held to above, though a border only needs 3:1 (WCAG 1.4.11): the
  // same colour is free to name the chip's text or an icon later and still hold.
  it.each(EVERY_THEME.map((t) => [t.id, t] as const))(
    "%s: every appearance clears 4.5:1 on its page and card",
    (_id, t) => {
      for (const a of CHIP_APPEARANCES) {
        for (const bg of chipBackdrops(t)) {
          expect({ a, bg, ok: contrastRatio(t.chips[a], bg) >= AA_TEXT }).toEqual({
            a,
            bg,
            ok: true,
          });
        }
      }
    },
  );

  it.each(EVERY_THEME.map((t) => [t.id, t] as const))(
    "%s: rows of different appearances still look different",
    (_id, t) => {
      for (const a of CHIP_APPEARANCES) {
        for (const b of CHIP_APPEARANCES) {
          if (a >= b) continue;
          expect({ a, b, far: rgbDistance(t.chips[a], t.chips[b]) >= 60 }).toEqual({
            a,
            b,
            far: true,
          });
        }
      }
    },
  );

  // The issue's first requirement: slot one IS the interactive colour, in every theme, on the
  // Fluent theme as well as the record -- the one its links and tab strip read.
  it.each(EVERY_THEME.map((t) => [t.id, t] as const))(
    "%s: tabColorOne is the theme's link and tab-strip colour",
    (_id, t) => {
      const f = fluentThemeFor(t);
      expect(t.chips.tabColorOne).toBe(t.brand.foreground1);
      expect(t.chips.tabColorOne).toBe(f.colorBrandForeground1);
      expect(t.chips.tabColorOne).toBe(f.colorCompoundBrandForeground1);
    },
  );

  it("a selected chip's colour follows the theme: a dark theme and a light one differ", () => {
    const dark = themeById("atlantis")!;
    const light = themeById("seaglass")!;
    for (const a of CHIP_APPEARANCES) expect(dark.chips[a]).not.toBe(light.chips[a]);
  });
});
