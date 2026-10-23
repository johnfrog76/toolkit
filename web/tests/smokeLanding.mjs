// `npm run smoke:landing` -- the built landing page, in a browser. Needs no
// agent, no dev server and no network: it builds the page
// (`vite build --mode landing`), serves dist/landing on a throwaway local
// port, and holds three things.
//
//   1. Links. Every link on the page is followed to where it ends.
//      - A link that stays on the page's own origin is requested and must
//        answer 200.
//      - A link to the repository or into it is NOT requested: a smoke that
//        waits on a third party fails for reasons that are not the page's.
//        It is held by what can be proved locally -- the repository address
//        has the shape of one and is the one copy.ts names, and each file
//        link resolves, under /blob/HEAD/, to a file that exists in this tree
//        (the tree the page is built from, so on main it is the file the link
//        opens). A link that is neither shape fails.
//      - The app's Home foot links the page by consts.json's docs.landingUrl
//        (routes.homeFoot.test.tsx holds the link itself). Here that address
//        must be the one this repository's Pages site serves --
//        <owner>.github.io/<repo>/ -- and the page it names is the one served
//        below at its root.
//   2. A phone, 390 px wide: no horizontal scroll, and the banner reads top
//      to bottom -- wordmark, offering, call to action, then the figures.
//   3. GitHub's social preview, 1280x640: the banner is the first screen,
//      whole, with its call to action in view.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { launchChromium } from "./smokeStack.mjs";

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PACKAGE_ROOT = path.resolve(WEB_ROOT, "..");
const SITE = path.join(WEB_ROOT, "dist", "landing");
const TYPES = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".mp3": "audio/mpeg",
  ".png": "image/png",
  ".woff2": "font/woff2",
};

const failures = [];
const check = (ok, what) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures.push(what);
};

if (!process.argv.includes("--no-build")) {
  const built = spawnSync("npm", ["run", "build:landing"], {
    cwd: WEB_ROOT,
    stdio: "ignore",
    shell: process.platform === "win32",
  });
  if (built.status !== 0) throw new Error("npm run build:landing failed");
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  let file = path.join(SITE, decodeURIComponent(url.pathname));
  if (!file.startsWith(SITE)) return void res.writeHead(403).end();
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  if (!fs.existsSync(file)) return void res.writeHead(404).end();
  res
    .writeHead(200, { "Content-Type": TYPES[path.extname(file)] ?? "application/octet-stream" })
    .end(fs.readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await launchChromium();
try {
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(`${origin}/`);
  await page.waitForSelector(".lp-banner");
  check(errors.length === 0, `the page throws nothing (${errors.join("; ")})`);

  // 1. Links.
  const hrefs = await page.$$eval("a[href]", (as) => as.map((a) => a.href));
  check(hrefs.length > 10, `the page has links (${hrefs.length})`);
  const shape = /^https:\/\/[a-z.]+\/([^/]+)\/([^/]+)$/;
  const consts = JSON.parse(fs.readFileSync(path.join(PACKAGE_ROOT, "consts.json"), "utf8"));
  const copy = fs.readFileSync(path.join(WEB_ROOT, "src", "landing", "copy.ts"), "utf8");
  const repoUrl = /repository: "([^"]+)"/.exec(copy)?.[1];
  check(shape.test(repoUrl ?? ""), `copy.ts names the repository: ${repoUrl}`);
  let sawRepo = false;
  for (const href of hrefs) {
    if (href.startsWith(origin)) {
      const r = await fetch(href);
      check(r.status === 200, `${href} answers 200`);
    } else if (href === repoUrl) {
      sawRepo = true;
      check(true, `${href} is the repository address`);
    } else if (href.startsWith(`${repoUrl}/blob/HEAD/`)) {
      const rel = href.slice(`${repoUrl}/blob/HEAD/`.length);
      check(
        !rel.includes("..") && fs.existsSync(path.join(PACKAGE_ROOT, rel)),
        `${href} is a file in the tree (${rel})`,
      );
    } else {
      check(false, `${href} is a link the smoke can not account for`);
    }
  }
  check(sawRepo, "the page links the repository");
  const [, owner, name] = shape.exec(repoUrl) ?? [];
  check(
    consts.docs.landingUrl === `https://${owner}.github.io/${name}/`,
    `the Home foot's address (docs.landingUrl) is this repository's Pages site: ${consts.docs.landingUrl}`,
  );
  check((await fetch(`${origin}/`)).status === 200, "the page that address names is served at its root");

  // 2. A phone.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(150);
  const phone = await page.evaluate(() => {
    const box = (s) => document.querySelector(s).getBoundingClientRect();
    return {
      scroll: document.documentElement.scrollWidth,
      inner: window.innerWidth,
      wide: [...document.querySelectorAll(".lp-banner *")]
        .filter((e) => e.getBoundingClientRect().right > window.innerWidth + 1)
        .map((e) => String(e.className?.baseVal ?? e.className)),
      title: box(".lp-title").top,
      offer: box(".lp-offer").top,
      cta: box(".lp-cta").top,
      wordsBottom: box(".lp-banner-words").bottom,
      figureTop: box(".lp-banner-figure").top,
    };
  });
  check(phone.scroll <= phone.inner, `390px: no horizontal scroll (${phone.scroll} <= ${phone.inner})`);
  check(phone.wide.length === 0, `390px: nothing in the banner passes the right edge (${phone.wide.join(",")})`);
  check(
    phone.title < phone.offer && phone.offer < phone.cta,
    "390px: wordmark, offering, call to action stack in that order",
  );
  check(
    phone.figureTop >= phone.wordsBottom - 1,
    `390px: the figures drop below the words (${phone.figureTop} >= ${phone.wordsBottom})`,
  );

  // 3. The social preview.
  await page.setViewportSize({ width: 1280, height: 640 });
  await page.waitForTimeout(150);
  const preview = await page.evaluate(() => {
    const box = (s) => document.querySelector(s).getBoundingClientRect();
    const b = box(".lp-banner");
    return {
      top: b.top,
      bottom: b.bottom,
      cta: box(".lp-cta-button").bottom,
      figure: box(".lp-banner-figure").bottom,
      scroll: document.documentElement.scrollWidth,
    };
  });
  check(
    preview.top >= 0 && preview.bottom <= 640,
    `1280x640: the banner fits the first screen (${Math.round(preview.top)}..${Math.round(preview.bottom)} of 640)`,
  );
  check(preview.cta <= 640 && preview.figure <= 640, "1280x640: the call to action and the figures are in view");
  check(preview.scroll <= 1280, "1280x640: no horizontal scroll");
} finally {
  await browser.close();
  server.close();
}
if (failures.length) {
  console.error(`\n${failures.length} check(s) failed`);
  process.exit(1);
}
console.log("\nlanding smoke: all checks passed");
