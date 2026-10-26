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
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { THEMES } from "../shell/themeList";
import { fluentThemeFor } from "../shell/theme";
import { LANDING_ACCENT, landingAccent } from "../landing/Landing";
import { Wordmark } from "./Wordmark";

// The product's accent is one key colour and a ramp generated from it, and
// this file is what holds it to that: the ramp's shape, where the two places
// the accent shows (the landing page and the wordmark's default blob) read
// from it, the text on the landing's call to action chosen by number, that no
// app theme wears it, and no accent hex typed anywhere in src/ but
// shared/accent.ts.

/** Cyan, the accent before rose: the key the "swap it in one place" check uses. */
const CYAN_KEY = "#0e7490";

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

  it("the landing page and the wordmark's default read from the ramp", () => {
    expect(ACCENT_STEPS.dark).toMatchObject({ face: 40, dot: 110, button: 80 });
    expect(ACCENT_STEPS.light).toMatchObject({ dot: 80, button: 80 });
    expect(LANDING_ACCENT).toEqual({
      "--lp-accent": ACCENT[110],
      "--lp-dot": ACCENT[110],
      "--lp-blob": ACCENT[40],
      "--lp-cta": ACCENT_KEY,
      "--lp-cta-hover": ACCENT[70],
      "--lp-glow": `${ACCENT_KEY}1a`,
    });
    // The wordmark drawn with no blob given wears wine, the dark face.
    const svg = renderToStaticMarkup(createElement(Wordmark));
    expect(svg).toContain(`fill="${ACCENT[40]}"`);
  });

  // Every accent property the landing page has comes from the key: built
  // from a cyan ramp instead, each is the same step of THAT ramp and none is
  // rose. So swapping ACCENT_KEY -- one line -- repaints the whole page, and
  // nothing in landing.css or Landing.tsx holds a colour of its own for these.
  it("swapping the key in one place repaints every landing accent property", () => {
    const cyan = accentRamp(CYAN_KEY);
    const rose = landingAccent() as Record<string, string>;
    const swapped = landingAccent(cyan) as Record<string, string>;
    expect(swapped).toEqual({
      "--lp-accent": cyan[110],
      "--lp-dot": cyan[110],
      "--lp-blob": cyan[40],
      "--lp-cta": CYAN_KEY,
      "--lp-cta-hover": cyan[70],
      "--lp-glow": `${CYAN_KEY}1a`,
    });
    for (const [name, value] of Object.entries(swapped))
      expect({ name, same: value === rose[name] }).toEqual({ name, same: false });
    // The page draws with every one of these (landing.css, or the wordmark's
    // blob in Landing.tsx), and the stylesheet never sets one itself.
    const read = (f: string) => fs.readFileSync(path.join(SRC_DIR, "landing", f), "utf8");
    const css = read("landing.css");
    const page = css + read("Landing.tsx");
    for (const name of Object.keys(rose)) {
      expect({ name, set: new RegExp(`${name}\\s*:`).test(css) }).toEqual({ name, set: false });
      expect({ name, used: page.includes(`var(${name})`) }).toEqual({ name, used: true });
    }
  });

  // The app's themes each keep their own accent: the product's is not worn
  // by any of them, in the record or in the Fluent theme made of it.
  it("no app theme wears the product's accent", () => {
    const ramp = new Set(Object.values(ACCENT));
    for (const t of THEMES) {
      const fluent = fluentThemeFor(t) as unknown as Record<string, string>;
      const worn = [t.logo, ...Object.values(t.brand), ...Object.values(fluent)].filter(
        (v) => typeof v === "string" && ramp.has(v.toLowerCase()),
      );
      expect({ id: t.id, worn }).toEqual({ id: t.id, worn: [] });
    }
  });

  // On a light page the wordmark's ink is dark, so wine under it would hide
  // the o's. The light face is the deepest step the ink still reads on at AA,
  // computed here rather than picked.
  it("the light face is the deepest step a light theme's ink reads on at AA", () => {
    const ink = webLightTheme.colorNeutralForeground1;
    const deepest = RAMP_STEPS.find((s) => contrastRatio(ink, ACCENT[s]) >= AA_TEXT);
    expect(ACCENT_STEPS.light.face).toBe(deepest);
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

  // Every step of the ramp and the values product asked for: typed nowhere
  // in src/ but accent.ts. The app's themes keep their own accents
  // (shell/themeList.ts), so their hexes -- cyan, teal, amber and the rest --
  // are not on this list; themeList.test.ts holds them to how they were.
  const LITERALS = [...new Set([...Object.values(ACCENT), "#6a2446", "#f27ab0"])];

  // What the landing page and the wordmark's default wore before the product
  // had one accent: the landing's cyan, its amber call to action and blob, and
  // the wordmark's cyan blob. Those two places read accent.ts now, so none of
  // these may come back THERE. (Atlantis's own logo blob is the same cyan, and
  // stays in themeList.ts, which this list does not read.)
  const FORMER_HERE = ["landing/", "shared/Wordmark.tsx"];
  const FORMER = [/#(?:62e6ff|d97706|f59e0b)(?![0-9a-f])/i, /34,\s*211,\s*238/, /245,\s*158,\s*11/];

  it("no accent hex is typed outside shared/accent.ts", () => {
    const hexes = new RegExp(`#(?:${LITERALS.map((h) => h.slice(1)).join("|")})(?![0-9a-f])`, "i");
    const found: string[] = [];
    for (const file of walk(SRC_DIR)) {
      const rel = path.relative(SRC_DIR, file).split(path.sep).join("/");
      if (EXEMPT.includes(rel) || EXEMPT_DIRS.some((d) => rel.startsWith(d))) continue;
      const former = FORMER_HERE.some((p) => rel.startsWith(p));
      fs.readFileSync(file, "utf8")
        .split("\n")
        .forEach((line, i) => {
          if (hexes.test(line) || (former && FORMER.some((re) => re.test(line))))
            found.push(`${rel}:${i + 1}: ${line.trim()}`);
        });
    }
    expect(found).toEqual([]);
  });
});
