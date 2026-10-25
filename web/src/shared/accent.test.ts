import fs from "node:fs";
import path from "node:path";
import { webLightTheme } from "@fluentui/react-components";
import {
  AA_TEXT,
  ACCENT,
  ACCENT_KEY,
  ACCENT_STEPS,
  RAMP_STEPS,
  accentFor,
  accentRamp,
  contrastRatio,
  readableOn,
} from "./accent";
import { FIRST_DARK, FIRST_LIGHT, THEMES, themeById } from "../shell/themeList";
import { fluentThemeFor } from "../shell/theme";
import { LANDING_ACCENT } from "../landing/Landing";

// The accent is one key colour and a ramp generated from it, and this file is
// what holds it to that: the ramp's shape, where each of the three places the
// accent shows reads from it, the text on the call to action chosen by number,
// and no accent hex typed anywhere in src/ but shared/accent.ts.

const SRC_DIR = path.resolve(__dirname, "..");
const hex = /^#[0-9a-f]{6}$/;

/** Distance between two colours, channel by channel, 0..255. */
function apart(a: string, b: string): number {
  const ch = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const [x, y] = [ch(a), ch(b)];
  return Math.max(...x.map((v, i) => Math.abs(v - y[i])));
}

describe("the accent", () => {
  it("is one key, the ramp's 80, and a ramp of sixteen generated from it", () => {
    expect(Object.keys(ACCENT).map(Number)).toEqual([...RAMP_STEPS]);
    for (const step of RAMP_STEPS)
      expect({ step, ok: hex.test(ACCENT[step]) }).toEqual({ step, ok: true });
    expect(ACCENT[80]).toBe(ACCENT_KEY);
    expect(accentRamp(ACCENT_KEY)).toEqual(ACCENT); // generated, so regenerated the same
    // Dark at 10, light at 160, and every step lighter than the one before.
    for (let i = 1; i < RAMP_STEPS.length; i++) {
      const [lo, hi] = [ACCENT[RAMP_STEPS[i - 1]], ACCENT[RAMP_STEPS[i]]];
      expect({
        step: RAMP_STEPS[i],
        lighter: contrastRatio(hi, "#000000") > contrastRatio(lo, "#000000"),
      }).toEqual({
        step: RAMP_STEPS[i],
        lighter: true,
      });
    }
  });

  it("lands where product asked: rose at 80, wine at 40, the pale rose at 110", () => {
    expect(ACCENT_KEY).toBe("#c0285e");
    // "About" -- the ramp is generated, so its steps are near the asked-for
    // values rather than typed to them.
    expect(apart(ACCENT[40], "#6a2446")).toBeLessThanOrEqual(8);
    expect(apart(ACCENT[110], "#f27ab0")).toBeLessThanOrEqual(8);
  });

  it("the face, the dots and the button read from the ramp by mode", () => {
    expect(ACCENT_STEPS.dark).toMatchObject({ face: 40, dot: 110, button: 80 });
    expect(ACCENT_STEPS.light).toMatchObject({ dot: 80, button: 80 });
    for (const t of THEMES) {
      const a = accentFor(t.mode);
      expect({
        id: t.id,
        logo: t.logo,
        button: t.brand.background,
        dot: t.brand.foreground1,
      }).toEqual({
        id: t.id,
        logo: a.face,
        button: ACCENT_KEY,
        dot: t.mode === "light" ? ACCENT_KEY : ACCENT[110],
      });
      // The dot is a checked radio's: Fluent's compound brand foreground.
      expect(fluentThemeFor(t).colorCompoundBrandForeground1).toBe(a.dot);
      expect(fluentThemeFor(t).colorBrandBackground).toBe(ACCENT_KEY);
    }
    expect(LANDING_ACCENT).toMatchObject({
      "--lp-blob": ACCENT[40],
      "--lp-dot": ACCENT[110],
      "--lp-cta": ACCENT_KEY,
    });
  });

  // On a light page the wordmark's ink is dark, so wine under it would hide
  // the o's. The light face is the deepest step the ink still reads on at AA,
  // computed here rather than picked.
  it("the light face is the deepest step a light theme's ink reads on at AA", () => {
    const ink = webLightTheme.colorNeutralForeground1;
    const deepest = RAMP_STEPS.find((s) => contrastRatio(ink, ACCENT[s]) >= AA_TEXT);
    expect(ACCENT_STEPS.light.face).toBe(deepest);
  });

  // The call to action's text is whichever of the theme's text colours reads
  // on the key -- computed, and held at 4.5:1.
  it("the app's call to action: the theme's readable text on the key, at AA", () => {
    for (const id of [FIRST_LIGHT, FIRST_DARK]) {
      const fluent = fluentThemeFor(themeById(id)!);
      const text = fluent.colorNeutralForegroundOnBrand;
      expect(text).toBe(
        readableOn(ACCENT_KEY, [
          id === FIRST_LIGHT ? webLightTheme.colorNeutralForeground1 : "#ffffff",
          fluent.colorNeutralBackground1,
          "#ffffff",
        ]),
      );
      const ratio = contrastRatio(text, ACCENT_KEY);
      expect({ id, text, ratio: Number(ratio.toFixed(2)), ok: ratio >= AA_TEXT }).toEqual({
        id,
        text: "#ffffff",
        ratio: 5.67,
        ok: true,
      });
    }
  });

  it("the landing's call to action: the page's readable ink on the key, at AA", () => {
    const css = fs.readFileSync(path.join(SRC_DIR, "landing", "landing.css"), "utf8");
    const value = (name: string) => new RegExp(`${name}:\\s*([^;]+);`).exec(css)![1].trim();
    const inks = { "--lp-text": value("--lp-text"), "--lp-bg": value("--lp-bg") };
    const best = readableOn(ACCENT_KEY, Object.values(inks));
    const chosen = Object.entries(inks).find(([, v]) => v === best)![0];
    expect(value("--lp-cta-text")).toBe(`var(${chosen})`);
    const ratio = contrastRatio(best, ACCENT_KEY);
    expect({ ratio: Number(ratio.toFixed(2)), ok: ratio >= AA_TEXT }).toEqual({
      ratio: 4.63,
      ok: true,
    });
    // Hovered, the button goes deeper and the same ink still reads.
    expect(contrastRatio(best, accentFor("dark").hover)).toBeGreaterThanOrEqual(AA_TEXT);
  });
});

describe("one place for the accent", () => {
  function walk(dir: string, out: string[] = []): string[] {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full, out);
      else if (/\.(tsx?|css)$/.test(entry.name)) out.push(full);
    }
    return out;
  }

  // Not the accent, though they share a colour with it:
  //   accent.ts and this file -- the one place, and the test that names it.
  //   modules/deck/decks/ -- the commercial's art quotes the themes as they
  //     were when it was drawn; a deck's picture is its own.
  //   landing/Faces.tsx -- the many faces' palette, six moods cycling, one of
  //     them cyan.
  const EXEMPT = ["shared/accent.ts", "shared/accent.test.ts", "landing/Faces.tsx"];
  const EXEMPT_DIRS = ["modules/deck/decks/"];

  // Every step of the ramp, the values product asked for, and the cyan and
  // teal the accent was before (a Lounge skin's own accent is its scene's).
  const RETIRED = [
    "#0e7490",
    "#0891b2",
    "#155e75",
    "#67e8f9",
    "#22d3ee",
    "#0f766e",
    "#0d9488",
    "#115e59",
    "#7dd3c8",
    "#62e6ff",
    "#c4768a",
    "#6a2446",
    "#f27ab0",
  ];
  const LITERALS = [...new Set([...Object.values(ACCENT), ...RETIRED])];

  it("no accent hex is typed outside shared/accent.ts", () => {
    const hexes = new RegExp(`#(?:${LITERALS.map((h) => h.slice(1)).join("|")})(?![0-9a-f])`, "i");
    // Today's cyan as rgba() -- how the face's blob was typed.
    const rgba = /34,\s*211,\s*238/;
    const found: string[] = [];
    for (const file of walk(SRC_DIR)) {
      const rel = path.relative(SRC_DIR, file).split(path.sep).join("/");
      if (EXEMPT.includes(rel) || EXEMPT_DIRS.some((d) => rel.startsWith(d))) continue;
      fs.readFileSync(file, "utf8")
        .split("\n")
        .forEach((line, i) => {
          if (hexes.test(line) || rgba.test(line)) found.push(`${rel}:${i + 1}: ${line.trim()}`);
        });
    }
    expect(found).toEqual([]);
  });
});
