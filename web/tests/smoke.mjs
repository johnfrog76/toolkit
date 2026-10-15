// Playwright smoke for the Toolkit web UI -- the web half of the cold-start
// gate (docs/TESTING.md). No ADO, no Docker: the dev
// server and the agent are up, and the agent's promptsRoot points at
// Tests/fixtures/hub (two cards -- one Active, one Code Review -- plus the two
// modules' fixtures).
//
//   node tests/smoke.mjs [--port=<n>] [--modules=off|on]
//                        [--viewport=desktop|mobile|both] [--shots=<dir>]
//   node tests/smoke.mjs --studio|--matrix|--a11y [--port=<n>] [--agent-port=<n>] [--python=<exe>]
//
// (`--studio`, `--matrix` and `--a11y` are modes that start and stop their OWN
// servers -- the Studio's contract, each module flag alone plus fresh and
// hostile browser storage, and axe on every page; see "A mode that
// owns its servers" below, smokeStudio.mjs, smokeMatrix.mjs and smokeA11y.mjs. Everything else in this header is about
// the first two.)
//
// TWO MODES, because "off means absent" has two halves and only one of them
// used to be proven in a browser.
//
//   --modules=off  (the default, and the original behaviour unchanged)
//                  Every feature flag is false. Growth AND communication
//                  contribute no nav entry, no page and no data request.
//                  Start the servers with `tkWeb -Dev -Fixture`.
//
//   --modules=on   features.growth and features.communication are both true,
//                  and the agent was started that way. Now the modules are
//                  expected to be there: nav entries, pages, the fixture hub's
//                  own data rendered, and the retro session's send button
//                  present, disabled, and naming the variable it wants.
//                  Start the servers with `tkWeb -Dev -Fixture -Modules on`.
//
// The mode does not configure the agent -- it asserts what the operator
// already started. `-Fixture` is the launcher's half of that bargain: it sets
// the fixture hub, its Space and the flags through the servers' environment, as
// a test run, so no config.local.json is written for a smoke. A mismatch fails loudly, which is the point: a smoke run
// that silently adapted to whatever was running would prove nothing. The one
// exception is Organize: `--modules=on`
// says nothing about `features.organize`, and every real machine the owner runs
// this against has it on, which moves Meetings off its own nav entry and onto
// the Organize tab BY DESIGN (communication/index.tsx). So the meetings check
// reads `features.organize` from `/api/env` (through the dev proxy, exactly as
// the app itself reads it) and asserts whichever shape that implies, rather
// than assuming a fixed configuration `--modules=on` never promised.
//
// Reuses qa/capture.mjs's shape from the wasteland: raw `playwright` (not
// @playwright/test),
// chromium, domcontentloaded, then wait for the app's own gate to clear.
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defaultPython, launchChromium, moduleSourceUrl } from "./smokeStack.mjs";
import { runA11y } from "./smokeA11y.mjs";
import { runMatrix } from "./smokeMatrix.mjs";
import { runStudio } from "./smokeStudio.mjs";

const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit === undefined ? fallback : hit.slice(name.length + 3);
};

// -- A mode that owns its servers -------------------------------------------
// `--studio` has to CHANGE the agent's configuration while it runs,
// which the two modes above must never do to servers someone else started. So
// it starts its own -- a scratch package, its agent and a Vite, on a committed
// fixture hub -- runs its cases, and stops them (smokeStack.mjs, smokeStudio.mjs).
// `--port=` and `--agent-port=` choose the ports it TAKES (a free one each
// otherwise), `--python=` the interpreter.
// `--matrix` is the second such mode: each module flag alone on, the
// flip, and fresh and storage-refusing browser contexts (smokeMatrix.mjs).
// `--a11y` is the third: axe on every page the registry mounts, every
// module flag off and then on, in the first light theme and aurora
// (smokeA11y.mjs). It lists every finding and fails on a serious or critical one.
const ownStackMode = process.argv.includes("--studio")
  ? runStudio
  : process.argv.includes("--matrix")
    ? runMatrix
    : process.argv.includes("--a11y")
      ? runA11y
      : null;
if (ownStackMode) {
  const ownRepoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  process.exit(
    await ownStackMode({
      repoRoot: ownRepoRoot,
      webPort: Number(arg("port", "0")),
      agentPort: Number(arg("agent-port", "0")),
      python: arg("python", defaultPython()),
    }),
  );
}

// The port Vite actually TOOK, not the one it asks for. `tkWeb -Dev` takes the
// next free port when 5174 is busy and logs the URL to web.log at the repo
// root (Scripts/Start-Web.ps1 reads the same line back); a fixed 5174 default
// then drove whatever else was on 5174 -- nothing, or a stale server -- and the
// run measured that instead. --port still wins; 5174 is the last
// resort, and the header line says which of the three it was.
// Only while .web.pid says a dev server is up: the log outlives the server, and
// a stale one beside a Docker build on 5174 would point the run at nothing.
const devServerPortFromLog = () => {
  const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  const log = join(repoRoot, "web.log");
  if (!existsSync(join(repoRoot, ".web.pid")) || !existsSync(log)) return null;
  const hits = readFileSync(log, "utf8").match(/https?:\/\/localhost:(\d+)/g);
  if (!hits) return null;
  return hits[hits.length - 1].split(":").pop();
};
const portArg = arg("port", undefined);
const loggedPort = portArg === undefined ? devServerPortFromLog() : null;
const port = Number(portArg ?? loggedPort ?? "5174");
const portSource = portArg !== undefined ? "--port" : loggedPort ? "web.log, from tkWeb -Dev" : "default";
const modulesArg = arg("modules", "off");
if (modulesArg !== "on" && modulesArg !== "off") {
  console.error(`--modules must be "on" or "off", got "${modulesArg}"`);
  process.exit(2);
}
const modulesOn = modulesArg === "on";
const base = `http://localhost:${port}`;
console.log(`smoke: ${base} (${portSource})`);

// The tier/org-status badge's words, read from envBadge.ts itself rather than
// retyped here -- a plain `node` run cannot `import` a .ts module, but it can
// read the source text envBadge() actually returns its `label`s from, which is
// the thing this check is answerable to. `ac65bf2` added "Offline" there and
// this regex went stale for it: every
// Offline org (an active one that tried ADO and failed -- routine on a machine
// with no fixture org logged in, or logged in with `az` and reaching for a
// board the fixture hub does not declare) failed a check built from an older
// list, on both of the owner's machines.
const envBadgeSource = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "..", "src/modules/ado/envBadge.ts"),
  "utf8",
);
const envBadgeLabels = [...envBadgeSource.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1]);
if (envBadgeLabels.length === 0) {
  console.error("smoke: could not read envBadge.ts's label set -- nothing to check the tier badge against.");
  process.exit(2);
}
const tierBadgeRegex = new RegExp(`\\b(${envBadgeLabels.join("|")})\\b`);

// A THIRD axis, after the two modes: which screen this is.
//
// The System page laid out 537px wide in a 430px viewport -- the Face card's
// fixed four-column grid was the widest thing on it, the nav row reached the
// edge, and the themed background stopped at the content's width so the
// overflow showed as a white band down every card. It was found by hand with a
// screenshot, which is the part that should not have to happen twice.
//
//
// `--viewport=mobile` is a 430x932 pass, `--viewport=both` runs desktop then
// mobile. Every check runs in whichever viewport is current, and one more is
// added per route: the document is never wider than the window. That is the
// whole class, not one card.
const VIEWPORTS = {
  desktop: { width: 1400, height: 900 },
  mobile: { width: 430, height: 932 },
};
const viewportArg = arg("viewport", "desktop");
if (!["desktop", "mobile", "both"].includes(viewportArg)) {
  console.error(`--viewport must be "desktop", "mobile" or "both", got "${viewportArg}"`);
  process.exit(2);
}
const viewportNames = viewportArg === "both" ? ["desktop", "mobile"] : [viewportArg];

// Where a PNG per visited route is written, if anywhere. Off by default: the
// smoke's job is to assert, and an image is evidence rather than a result.
const shotsArg = arg("shots", "");

// Never send. These two lines clear the webhooks from THIS process -- the
// runner and the browser it launches -- and from nothing else. The send button's
// state comes from the AGENT's environment (/api/env ->
// communication.recipients[].configured), a different process started by
// `tkWeb -Dev`, which imports the module, which reads the package's .env into
// the shell unless the test-run marker is set -- so a `delete` here, or an
// `unset` in the shell that runs `npm run smoke`, never reaches it. The
// agent is kept clean by how it is STARTED: `tkWeb -Dev -Fixture` gives it the
// marker and no TEAMS_WEBHOOK_* at all. The check just below refuses a run whose
// agent has one anyway.
delete process.env.TEAMS_WEBHOOK_MANAGER;
delete process.env.TEAMS_WEBHOOK_DEMO_CHANNEL;

// Before anything opens: does the agent hold a live webhook? If it does, the
// modules-on run would fail four assertions per viewport on an ENABLED send
// button -- correctly, and unhelpfully. Refuse once, up front, naming where the
// variable came from and the start that does not have it. Read through the dev
// proxy, the way the app reads it. An agent that does not answer is left to the
// checks below to report; this is about one known hazard, not about reachability.
const liveRecipients = await fetch(`${base}/api/env`)
  .then((r) => (r.ok ? r.json() : {}))
  .then((e) => (e?.communication?.recipients ?? []).filter((r) => r && r.configured === true))
  .catch(() => []);
if (liveRecipients.length > 0) {
  const names = liveRecipients.map((r) => r.webhookEnv || r.key).join(", ");
  console.error(`FAIL  the agent behind ${base} has a live Teams webhook configured: ${names}.`);
  console.error("      Nothing was run. The send button would be enabled, and a modules-on run");
  console.error("      is one stray click from a message someone receives.");
  console.error("");
  console.error("      It almost always comes from the package's .env, which the module reads into");
  console.error("      the shell at import -- unsetting it in this shell does not reach the agent.");
  console.error("      Restart the servers as a test run, which skips .env and carries no webhook:");
  console.error("");
  console.error(`        tkWeb -Dev -Fixture -Modules ${modulesArg}`);
  console.error("");
  console.error("      (tk is the default prefix; use yours.)");
  process.exit(2);
}

// `npm ci` installs the playwright LIBRARY; the chromium BINARY lives in a
// machine-level cache (~/Library/Caches/ms-playwright, %LOCALAPPDATA%\ms-playwright)
// and is downloaded by a separate command that nothing in this repo runs. On a
// machine that has ever used Playwright for anything the smoke just works,
// which is how it stayed undocumented -- so the failure is caught here and
// answered with the exact command, rather than left as a launch stack trace at
// the point the README says the install is finished. smokeStack.mjs's
// launchChromium is that catch, shared with the modes that own their servers.
const browser = await launchChromium();
let failures = 0;
let viewportLabel = "";
const check = (name, ok, detail = "") => {
  const label = viewportLabel ? `[${viewportLabel}] ${name}` : name;
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${ok || !detail ? "" : ` -- ${detail}`}`);
  if (!ok) failures++;
};

// A route's filename, for a screenshot: "/" is home, and everything else is its
// path with the separators flattened. No timestamps in the name -- the folder
// is the run, the file is the page, and a diff between two runs is the point.
const shotName = (route) => {
  const slug = route.replace(/^\/+|\/+$/g, "").replace(/[^a-zA-Z0-9]+/g, "-").toLowerCase();
  return `${slug || "home"}.png`;
};

async function runViewport(viewportName) {
  const viewport = VIEWPORTS[viewportName];
  viewportLabel = viewportNames.length > 1 ? viewportName : "";
  console.log(`smoke: modules=${modulesArg}, viewport=${viewportName} (${viewport.width}x${viewport.height}), port=${port}`);

  const page = await browser.newPage({ viewport });

  // Only code and data fetches count as "a chunk was requested"; the document
  // navigation to /growth itself is the thing under test, not a leak.
  // A URL that carries a module's SOURCE -- one of its parts, not its
  // descriptor. Dev serves the file itself (/src/modules/growth/GrowthPage.tsx);
  // a build serves the chunk Vite named after it (/assets/GrowthPage-<hash>.js).
  // The part names are read off the module's folder, so a new page is covered
  // the day it is added. index.tsx and paths.ts ARE the descriptor: the
  // registry reads them with the flag off, and that is the contract.
  // (moduleSourceUrl lives in smokeStack.mjs, shared with --matrix.)
  const webRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
  const requested = [];
  page.on("request", (r) => {
    if (r.resourceType() !== "document") requested.push(r.url());
  });
  const pageErrors = [];
  page.on("pageerror", (e) => pageErrors.push(String(e)));

  const shotDir = shotsArg ? resolve(shotsArg, viewportName) : "";
  if (shotDir) mkdirSync(shotDir, { recursive: true });

  const routesVisited = [];

  async function open(route) {
    await page.goto(base + route, { waitUntil: "domcontentloaded" });
    // The shell renders "Loading toolkit..." until /env answers; everything
    // below is meaningless before that gate clears.
    await page.waitForFunction(() => !document.body.innerText.includes("Loading toolkit"), null, { timeout: 20000 });
    // Then the page's own fetch. Every module page has its own "Loading ..."
    // state -- prompts, growth, session -- and asserting on the text before it
    // clears reads the spinner, not the data. Tolerated rather than required:
    // a page that never loads is what the assertions below are for, and failing
    // here would report a timeout instead of naming what was missing.
    try {
      await page.waitForFunction(() => !/\bLoading\b/.test(document.body.innerText), null, { timeout: 20000 });
    }
    catch {
      /* fall through and let the check say what it actually saw */
    }
    routesVisited.push(route);
    return page.evaluate(() => document.body.innerText);
  }

  // Every route, in every viewport: a page is never wider than its window. One
  // assertion for the whole class -- the Face grid, the nav row and anything
  // added later. innerWidth excludes a classic scrollbar, so the +1 is for a
  // fractional layout width rounding up, not slack for a real overflow.
  async function checkNoSidewaysScroll(route) {
    const box = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      inner: window.innerWidth,
    }));
    check(
      `${route} does not scroll sideways`,
      box.scroll <= box.inner + 1,
      `scrollWidth ${box.scroll} > innerWidth ${box.inner}`,
    );
  }

  // Evidence, not a result: a PNG per route when --shots names a folder.
  async function shoot(route) {
    if (!shotDir) return;
    const file = join(shotDir, shotName(route));
    mkdirSync(dirname(file), { recursive: true });
    await page.screenshot({ path: file, fullPage: true });
  }

  const navText = () =>
    page.evaluate(() => Array.from(document.querySelectorAll("a, button")).map((e) => e.textContent?.trim()).join("|"));

  // -- Always, in both modes ---------------------------------------------------

  // 1. Home renders PromptStatus with both fixture states. The card fetches
  // /status after the env gate, so wait for the data, not just the gate.
  await open("/");
  await page.waitForFunction(() => !document.body.innerText.includes("Loading prompts"), null, { timeout: 20000 });
  const home = await page.evaluate(() => document.body.innerText);
  check("/ renders both fixture prompts", home.includes("Task 401") && home.includes("Bug 402"), home.slice(0, 200));
  check("/ shows the Active and Code Review states", home.includes("Active") && home.includes("Code Review"));
  await checkNoSidewaysScroll("/");
  await shoot("/");

  // 1b. Home is named tabs, not pages. The
  // fixture's tier decides how many tabs there are, so the assertions hold for
  // any count: the pager is gone; two or more tabs make a strip that starts
  // with Cards, selected on `/`; one tab makes no strip. And a tab address this
  // Home does not have lands on `/` rather than an empty page.
  const tabNames = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[role="tab"]')).map((t) => ({
      name: t.textContent?.trim(),
      selected: t.getAttribute("aria-selected") === "true",
    })),
  );
  const pagerLeft = await page.evaluate(() => Boolean(document.querySelector('nav[aria-label^="Cards, page"]')));
  check("/ has no card pager -- a tab shows all its cards", !pagerLeft);
  // The first tab's NAME is the registry's, read off registry.ts rather than
  // retyped here: it said "Cards" until it was renamed Focus, and this line
  // went on asserting the old word. A tab's textContent may carry a badge
  // after the label, so the label is matched at the start.
  const registrySource = readFileSync(join(webRoot, "src", "shell", "registry.ts"), "utf8");
  const firstTabLabel = /id: "cards", label: "([^"]+)"/.exec(registrySource)?.[1] ?? "Focus";
  check(
    `/ shows a tab strip only with two or more tabs, ${firstTabLabel} first and selected`,
    tabNames.length === 0 || (tabNames.length >= 2 && tabNames[0].name?.startsWith(firstTabLabel) && tabNames[0].selected),
    JSON.stringify(tabNames),
  );
  for (const [route, name] of [["/sprint", "Sprint"], ["/actions", "Actions"]]) {
    await open(route);
    const landed = new URL(page.url()).pathname;
    const selected = await page.evaluate(
      () => document.querySelector('[role="tab"][aria-selected="true"]')?.textContent?.trim() ?? "",
    );
    const hasTab = tabNames.some((t) => t.name === name);
    check(
      `${route} is the ${name} tab when Home has one, and / when it does not`,
      hasTab ? landed === route && selected === name : landed === "/",
      `landed ${landed}, selected ${selected}`,
    );
  }

  // 2. System renders EnvCard with a tier badge.
  const system = await open("/system");
  // EnvCard's badge shows a WORD, not a number -- and the word is the org's state, not only the
  // tier: Full / Local / Minimal / Archive / Offline (envBadge.ts, tierBadgeRegex above -- read
  // from there so a new word cannot drift this check the way "Offline" did).
  check("/system renders EnvCard with the tier badge", system.includes("Environment") && tierBadgeRegex.test(system), system.slice(0, 200));
  await checkNoSidewaysScroll("/system");
  await shoot("/system");

  if (!modulesOn) {
    // -- modules=off: both modules are absent -----------------------------------

    // 3. Growth is not served when features.growth is false.
    const growth = await open("/growth");
    const offNav = await navText();
    check("no Growth nav entry", !/\bGrowth\b/.test(offNav), offNav.slice(0, 200));
    // The Studio is core, from day one (D-S13):
    // its tab is there with every module flag off.
    check("the Studio nav entry is present with every module off", /\bStudio\b/.test(offNav), offNav.slice(0, 200));
    check("/growth renders no growth page", !/Goals|Trainings|Presentations/.test(growth), growth.slice(0, 200));
    await checkNoSidewaysScroll("/growth");
    await shoot("/growth");

    // 4. The communication mirror of the same. It was missing entirely: the
    // module's absence was covered by registry.communication.test.tsx and by the
    // agent's 404s, but never from a browser.
    const comms = await open("/communication");
    const offNav2 = await navText();
    check("no Meetings nav entry", !/Meetings/.test(offNav2), offNav2.slice(0, 200));
    check("/communication renders no 1:1 page", !/Next up|ready to archive|New session/i.test(comms), comms.slice(0, 200));
    await checkNoSidewaysScroll("/communication");
    await shoot("/communication");

    // No module DATA is fetched: neither module contributes a route, a nav entry
    // or a card, so nothing asks the agent for growth or manager data -- and
    // those routes are 404 with the flag off anyway.
    const growthApiCalls = requested.filter((u) => /\/api\/(growth|reviews?|resume|review-preview)/.test(u));
    check("no growth data was requested", growthApiCalls.length === 0, growthApiCalls.join(", "));
    const commsApiCalls = requested.filter((u) => /\/api\/(manager|comms)/.test(u));
    check("no 1:1 data was requested", commsApiCalls.length === 0, commsApiCalls.join(", "));
    // The Docs tab is the core's, not a module's, so its code is in the
    // first load -- but its DATA is read only when the tab is drawn, and this run
    // never draws it: on any Space, nothing so far asked the agent for a README.
    const docsApiCalls = requested.filter((u) => /^\/api\/docs(\/|$)/.test(new URL(u).pathname));
    check("no docs data was requested", docsApiCalls.length === 0, docsApiCalls.join(", "));
    // Solitaire Agile's standup is read only by its own page, which off mode
    // never draws (docs/modules/solitaire-agile.md, "Turning it on").
    const ritualApiCalls = requested.filter((u) => /^\/api\/ritual(\/|$)/.test(new URL(u).pathname));
    check("no standup data was requested", ritualApiCalls.length === 0, ritualApiCalls.join(", "));

    // And no module SOURCE either -- the "no bytes" clause.
    // The registry reads
    // each module's descriptor (index.tsx, plus a paths file of route strings)
    // to know its flag and its addresses; everything else a module contributes
    // is a lazy part, a chunk Vite serves only when it is first drawn. With the
    // flag off nothing is drawn, so in dev no other file under the module's
    // folder is ever requested. This check used to be impossible to make.
    for (const id of ["growth", "communication", "organize", "solitaireAgile", "lounge"]) {
      const leaked = requested.filter((u) => moduleSourceUrl(id, u));
      check(`no ${id} source was requested`, leaked.length === 0, leaked.join(", "));
    }
    // The Studio is core but its pages are still lazy parts -- lazy is about
    // bytes, not about being optional -- and this run never opens /studio, so
    // nothing past its descriptor has been asked for either.
    const studioLeaked = requested.filter((u) => moduleSourceUrl("studio", u));
    check("no Studio page source was requested before /studio was opened", studioLeaked.length === 0, studioLeaked.join(", "));
  } else {
    // -- modules=on: both modules are present, and so is their data -------------

    // 3. Growth.
    const growth = await open("/growth");
    const onNav = await navText();
    check("Growth nav entry is present", /\bGrowth\b/.test(onNav), onNav.slice(0, 200));
    // The lazy half from the other side: drawing /growth is what fetches
    // the module's parts. Off-mode proves nothing was fetched; this proves the
    // fetch happens when it should, so a part that silently failed to load
    // would not pass as "absent".
    check(
      "growth source was requested when /growth was drawn",
      requested.some((u) => moduleSourceUrl("growth", u)),
      requested.filter((u) => /modules\/growth|\/assets\//.test(u)).slice(0, 6).join(", "),
    );
    // The three artifacts in the fixture hub's growth/current/ -- one per type.
    // Asserted by their own titles, so this fails if the page renders but reads
    // an empty or a different store.
    check(
      "/growth lists the three fixture artifacts",
      growth.includes("Improve test coverage patterns") &&
        /Designing for Non-Determinism/i.test(growth) &&
        /Distributed Systems Fundamentals/i.test(growth),
      growth.slice(0, 400),
    );
    await checkNoSidewaysScroll("/growth");
    await shoot("/growth");
    const growthApiCalls = requested.filter((u) => /\/api\/(growth|reviews?|resume|review-preview)/.test(u));
    check("growth data was requested", growthApiCalls.length > 0, "nothing asked the agent for growth data");

    const skills = await open("/skills");
    check("/skills renders", skills.trim().length > 0 && !/Not Found|404/.test(skills), skills.slice(0, 200));
    await checkNoSidewaysScroll("/skills");
    await shoot("/skills");

    // 4. Communication. Whether Meetings has its own nav entry or lives under
    // Organize depends on features.organize, which --modules=on does not pin --
    // read from /api/env, the same source the app itself reads.
    const envFeatures = await page.evaluate(() =>
      fetch("/api/env")
        .then((r) => r.json())
        .then((e) => e.features ?? {})
        .catch(() => ({})),
    );
    const organizeOn = envFeatures.organize === true;
    const comms = await open(organizeOn ? "/organize" : "/communication");
    const onNav2 = await navText();
    check(
      organizeOn ? "Organize nav entry is present, not a separate Meetings entry" : "Meetings nav entry is present",
      organizeOn ? /Organize/.test(onNav2) && !/Meetings/.test(onNav2) : /Meetings/.test(onNav2),
      onNav2.slice(0, 200),
    );
    // The fixture hub's manager/current/ holds three sessions, one per stage:
    // draft, prep and retro. The list renders the date and the stage badge, so
    // both are asserted -- a page that listed the files without deriving a stage
    // would pass on the dates alone.
    check(
      `/${organizeOn ? "organize" : "communication"} lists the three fixture sessions`,
      /Jan(uary)?\s*8/i.test(comms) && /Jan(uary)?\s*22/i.test(comms) && /Feb(ruary)?\s*5/i.test(comms),
      comms.slice(0, 400),
    );
    // The badge shows the WORKFLOW STAGE'S LABEL, not the raw value in the file:
    // the file's `draft` renders as "Plan", because that is the stage the session
    // is in rather than the state it is in. Asserting the raw values here passed
    // for the wrong reason on two of three and failed honestly on the first.
    check(
      "/communication shows each session's stage",
      /\bPlan\b/.test(comms) && /\bPrep\b/.test(comms) && /\bRetro\b/.test(comms),
      comms.slice(0, 400),
    );
    await checkNoSidewaysScroll("/communication");
    await shoot("/communication");
    const commsApiCalls = requested.filter((u) => /\/api\/manager/.test(u));
    check("1:1 data was requested", commsApiCalls.length > 0, "nothing asked the agent for manager data");

    // 5. The retro session's send button -- READ-ONLY. Its presence and its
    // disabled reason are the assertion; the button is never pressed, because a
    // press posts to a real webhook. A disabled button that names the variable is
    // the whole design: the alternative is a live button that fails on click and
    // only then tells you something is unset.
    const session = await open("/communication/sessions/2026-02-05.md");
    const sendBtn = await page.evaluate(() => {
      const el = Array.from(document.querySelectorAll("button")).find((b) => /send/i.test(b.textContent ?? ""));
      return el ? { found: true, disabled: el.disabled || el.getAttribute("aria-disabled") === "true" } : { found: false, disabled: false };
    });
    check("the retro session has a send button", sendBtn.found, session.slice(0, 300));
    check("the send button is disabled", sendBtn.disabled, "an enabled send button means a configured live webhook -- stop");
    check(
      "the send button names TEAMS_WEBHOOK_MANAGER",
      session.includes("TEAMS_WEBHOOK_MANAGER"),
      session.slice(0, 400),
    );
    await checkNoSidewaysScroll("/communication/sessions/2026-02-05.md");
    await shoot("/communication/sessions/2026-02-05.md");

    // 6. The page the send button is on can be REACHED. Once nothing
    // in the UI led to /communication/sessions/<file>: the card's rows and the
    // read view both went elsewhere, and a built, tested feature was findable
    // only by typing its URL. The row carries an "Edit / send" control, and the
    // read view's own "Edit / send" lands on the session page.
    await open("/communication");
    const rowEditSend = await page.evaluate(
      () => document.querySelectorAll('button[aria-label="Edit / send"]').length,
    );
    check("each meeting row offers Edit / send", rowEditSend >= 3, `found ${rowEditSend}`);
    await open("/communication/1on1/2026-02-05.md");
    const clicked = await page.evaluate(() => {
      const el = Array.from(document.querySelectorAll("button")).find((b) => /Edit \/ send/.test(b.textContent ?? ""));
      if (!el) return false;
      el.click();
      return true;
    });
    check("the read view offers Edit / send", clicked, "no button reading 'Edit / send' on /communication/1on1/2026-02-05.md");
    await page.waitForFunction(() => location.pathname.includes("/communication/sessions/"), null, { timeout: 10000 }).catch(() => {});
    check(
      "Edit / send lands on the session page",
      page.url().includes("/communication/sessions/2026-02-05.md"),
      page.url(),
    );

    // 7. A complete session offers Close -- READ-ONLY. Presence only: pressing
    // it runs MeetingAgenda -Close through the bridge, which MOVES the fixture
    // file into manager/archive/, and the fixture hub is the committed one.
    // The retro session is the only complete one of the three.
    await open("/communication");
    const closeButtons = await page.evaluate(
      () => document.querySelectorAll('button[aria-label="Close this meeting"]').length,
    );
    check("exactly the complete session offers Close", closeButtons === 1, `found ${closeButtons}`);
  }

  check(`no page errors across the ${routesVisited.length} routes`, pageErrors.length === 0, pageErrors.join(" | "));

  if (shotDir) console.log(`      shots: ${shotDir}`);
  await page.close();
}

for (const name of viewportNames) {
  await runViewport(name);
}

await browser.close();
console.log(failures === 0 ? `smoke: clean (modules=${modulesArg}, viewport=${viewportArg})` : `smoke: ${failures} failure(s) (modules=${modulesArg}, viewport=${viewportArg})`);
process.exit(failures === 0 ? 0 : 1);
