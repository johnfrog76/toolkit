// `node tests/render-cast.mjs [--preview]` -- draws the cast's nine-seat stage to
// docs/images/stage.png, the picture the README's first screen shows.
//
// Run by hand when the cast (web/src/modules/solitaireAgile/stage/cast.tsx) or
// the seats (seats.ts) change, and commit the PNG. Never part of a build or a
// test run: a render needs a browser, and the README needs a file.
//
// The page is the cast's own components -- the tiles, the scenes, the palette
// -- mounted by a throwaway Vite server in a page of this script's making. No
// agent, no hub, no network. Nothing is drawn by hand.
//
// Same source, same bytes: the figures are parked (Super Dev's desk holds
// still), reduced motion is on, so no animation is in flight; the viewport,
// the scale and the theme are fixed; the shot waits for fonts and for two
// frames. The one input a script cannot pin is the machine's own font for the
// plates' monospace stack (Cascadia Code, Fira Code, Consolas), so the bytes
// are identical per machine and may differ in the plates' lettering across
// machines.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { chromium } from "playwright";
import { createServer } from "vite";

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PACKAGE_ROOT = path.resolve(WEB_ROOT, "..");
const OUT = path.join(PACKAGE_ROOT, "docs", "images", "stage.png");

const PORT = 5192;
const PAGE = "/render-cast.html";
const VIRTUAL = "virtual:render-cast";
const STAGE_WIDTH = 960;
const SCALE = 2;

/** The page's one module: the nine seats in the card's order, none speaking. */
const ENTRY = `
import { createElement as h } from "react";
import { createRoot } from "react-dom/client";
import {
  CAST,
  CastScene,
  STAGE_CLASS,
  StandupKeyframes,
  ZoomTile,
  pf,
  mono,
} from "/src/modules/solitaireAgile/stage/cast.tsx";
import { SEATS, plateFor } from "/src/modules/solitaireAgile/stage/seats.ts";

const plates = new Map(SEATS.map((s) => [s.castId, plateFor(s)]));
const tiles = CAST.map((c) =>
  h(
    "div",
    { key: c.id, "data-seat": c.id, style: { position: "relative", minHeight: 0 } },
    h(
      ZoomTile,
      { tint: c.tint, label: plates.get(c.id) ?? c.label, look: "speaking" },
      h(CastScene, { id: c.id, parked: true }),
    ),
  ),
);
const stage = h(
  "div",
  {
    id: "stage",
    className: STAGE_CLASS,
    style: {
      width: "${STAGE_WIDTH}px",
      height: "640px",
      boxSizing: "border-box",
      overflow: "hidden",
      background: pf.bg,
      borderRadius: "10px",
      display: "flex",
      flexDirection: "column",
      fontFamily: mono,
    },
  },
  h(StandupKeyframes),
  h(
    "div",
    { style: { flex: 1, minHeight: 0, margin: "18px", display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gridAutoRows: "1fr", gap: "10px" } },
    tiles,
  ),
);
createRoot(document.getElementById("root")).render(stage);
// No tile is speaking: the speaker's frame is the played stage's, not the roster's.
const style = document.createElement("style");
style.textContent = '[data-testid="stage-frame"] { display: none !important; }';
document.head.append(style);
window.__ready = Promise.all([
  document.fonts.ready,
  new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
]).then(() => true);
`;

// `--preview`: the landing page's banner at 1280x640, GitHub's social preview,
// to docs/images/social-preview.png. It builds the page (`npm run build:landing`),
// serves dist/landing on a throwaway port and shoots the first screen with
// everything under the banner hidden, so nothing is cut off at the bottom edge.
if (process.argv.includes("--preview")) {
  const { spawnSync } = await import("node:child_process");
  const http = await import("node:http");
  const built = spawnSync("npm", ["run", "build:landing"], {
    cwd: WEB_ROOT,
    stdio: "ignore",
    shell: process.platform === "win32",
  });
  if (built.status !== 0) throw new Error("npm run build:landing failed");
  const site = path.join(WEB_ROOT, "dist", "landing");
  const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };
  const static_ = http.createServer((req, res) => {
    const file = path.join(site, req.url === "/" ? "index.html" : req.url.split("?")[0]);
    if (!file.startsWith(site) || !fs.existsSync(file)) return void res.writeHead(404).end();
    res
      .writeHead(200, { "Content-Type": types[path.extname(file)] ?? "application/octet-stream" })
      .end(fs.readFileSync(file));
  });
  await new Promise((r) => static_.listen(0, "127.0.0.1", r));
  const out = path.join(PACKAGE_ROOT, "docs", "images", "social-preview.png");
  const b = await chromium.launch();
  try {
    const ctx = await b.newContext({
      viewport: { width: 1280, height: 640 },
      deviceScaleFactor: 1,
      reducedMotion: "reduce",
    });
    const pg = await ctx.newPage();
    await pg.goto(`http://127.0.0.1:${static_.address().port}/`);
    await pg.waitForSelector(".lp-banner");
    await pg.addStyleTag({ content: ".lp main, .lp footer { display: none !important; }" });
    await pg.evaluate(() => document.fonts.ready);
    const png = await pg.screenshot({ type: "png", animations: "disabled" });
    fs.writeFileSync(out, png);
    console.log(`wrote ${path.relative(process.cwd(), out)} (${png.length} bytes)`);
  } finally {
    await b.close();
    static_.close();
  }
  process.exit(0);
}

const server = await createServer({
  root: WEB_ROOT,
  configFile: false,
  logLevel: "warn",
  // The shell's two aliases (vite.config.ts), which the cast's imports reach.
  resolve: {
    alias: {
      "@consts": path.join(PACKAGE_ROOT, "consts.json"),
      "@workflows": path.join(PACKAGE_ROOT, "Config", "settings-workflows.json"),
    },
  },
  plugins: [
    react(),
    {
      name: "render-cast-page",
      resolveId: (id) => (id === VIRTUAL ? `\0${VIRTUAL}` : undefined),
      load: (id) => (id === `\0${VIRTUAL}` ? ENTRY : undefined),
      configureServer(s) {
        s.middlewares.use(async (req, res, next) => {
          if (req.url !== PAGE) return next();
          const html = await s.transformIndexHtml(
            PAGE,
            `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Cast</title>` +
              `<style>html,body{margin:0;background:transparent}#root{display:inline-block}</style></head>` +
              `<body><div id="root"></div><script type="module" src="/@id/${VIRTUAL}"></script></body></html>`,
          );
          res.setHeader("Content-Type", "text/html");
          res.end(html);
        });
      },
    },
  ],
  server: { host: "127.0.0.1", port: PORT, strictPort: true, hmr: false },
});

let browser;
try {
  await server.listen();
  browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: STAGE_WIDTH + 40, height: 700 },
    deviceScaleFactor: SCALE,
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(`http://127.0.0.1:${PORT}${PAGE}`);
  await page.waitForSelector("#stage");
  await page.evaluate(() => window.__ready);
  const seats = await page.locator("[data-seat]").count();
  if (seats !== 9) throw new Error(`the stage drew ${seats} seats, not nine`);
  if (errors.length) throw new Error(`the page threw: ${errors.join("; ")}`);
  const png = await page
    .locator("#stage")
    .screenshot({ type: "png", omitBackground: true, animations: "disabled" });
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, png);
  console.log(`wrote ${path.relative(process.cwd(), OUT)} (${png.length} bytes)`);
} finally {
  if (browser) await browser.close();
  await server.close();
}
