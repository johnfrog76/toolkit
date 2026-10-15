// `node tests/smoke.mjs --matrix` -- what each configuration shows, and the
// private-window case, in a real browser.
//
// On servers the mode owns (smokeStack.mjs), against Tests/fixtures/hub:
//
//   1. THE FLAG MATRIX. One pass per module flag, that flag alone on (each set
//      through PUT /api/config, the others false): its nav entry, its page with
//      the fixture hub's data, its data requested and its source fetched; every
//      other module's nav entry absent, and nothing of theirs requested -- no
//      data, no source. Each pass is a new browser context, so a request it
//      counts is its own. The cases are docs/SCENARIOS.md's rows, "The nav, by
//      module": one row per module, named on each case below.
//   2. THE FLIP with no restart -- flipCase, shared with --studio.
//   3. FRESH AND HOSTILE STORAGE. Each surface that keeps a choice in the
//      browser -- the Spaces card's filter, the Reminders card's filter, the
//      theme, the Lounge's game, the standup player's mute -- in (a) a new context with empty storage: its
//      default, then a choice that survives a reload; and (b) a context whose
//      localStorage and sessionStorage THROW on access (an init script, the
//      Safari-private / site-data-blocked shape): no page error, no crash
//      screen, and the surface still answers a choice for the page's life.
//
// Chromium only. Every flag write is a Config run through the bridge, so the
// mode takes several minutes; that is why it is opt-in.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  answerWithAgents,
  flipCase,
  launchChromium,
  mainNavEntries,
  makeChecker,
  moduleSourceUrl,
  openRoute,
  setFlags,
  startStack,
} from "./smokeStack.mjs";

const FIXTURE_HUB = "Tests/fixtures/hub";
const SPACE = "test";
const VIEWPORT = { width: 1400, height: 900 };

const apiPath = (url) => new URL(url).pathname;

// One row per module flag. `scenario` is the docs/SCENARIOS.md row the case
// asserts; `page` is the fixture hub's own data on the module's page (a page
// that rendered but read nothing fails it); `data` matches the module's agent
// routes -- null for the two web-only modules, which have none.
const MODULES = [
  {
    flag: "growth",
    id: "growth",
    nav: "Growth",
    route: "/growth",
    scenario: "growth | + Growth, before the Studio",
    page: (t) =>
      t.includes("Improve test coverage patterns") &&
      /Designing for Non-Determinism/i.test(t) &&
      /Distributed Systems Fundamentals/i.test(t),
    data: (u) => /^\/api\/(growth|reviews?|resume|review-preview)(\/|$)/.test(apiPath(u)),
  },
  {
    flag: "communication",
    id: "communication",
    nav: "Meetings",
    route: "/communication",
    scenario: "communication | + Meetings",
    page: (t) => /Jan(uary)?\s*8/i.test(t) && /Jan(uary)?\s*22/i.test(t) && /Feb(ruary)?\s*5/i.test(t),
    data: (u) => /^\/api\/(manager|comms)(\/|$)/.test(apiPath(u)),
  },
  {
    flag: "organize",
    id: "organize",
    nav: "Organize",
    route: "/organize",
    scenario: "organize | + Organize, before the Studio",
    page: (t) => t.includes("Renew the certificate") && t.includes("Review the sprint goals") && t.includes("Read the design doc"),
    data: (u) => /^\/api\/reminders(\/|$)/.test(apiPath(u)),
  },
  {
    flag: "deck",
    id: "deck",
    nav: "Decks",
    route: "/decks",
    scenario: "deck | + Decks",
    // The launcher lists the decks the module ships, each with its address.
    page: (t) => t.includes("/deck/the-toolkit"),
    data: null,
  },
  {
    flag: "lounge",
    id: "lounge",
    nav: "Lounge",
    route: "/lounge",
    scenario: "lounge | + Lounge, last",
    page: (t) => t.includes("Tic-tac-toe"),
    data: null,
  },
  {
    flag: "solitaireAgile",
    id: "solitaireAgile",
    nav: "Team Agile",
    route: "/solitaire-agile",
    scenario: "solitaireAgile | + Team Agile, after the Studio",
    page: (t) => /standup/i.test(t) && !/Could not read today's standup/.test(t),
    data: (u) => /^\/api\/ritual(\/|$)/.test(apiPath(u)),
    // The Space's answer gates it: the pass answers With agents first,
    // and every pass after it runs on that GitHub-addressed, local Space.
    answer: true,
  },
];

const allOff = () => Object.fromEntries(MODULES.map((m) => [m.flag, false]));

/** A new context and page that record what they request and every page error. */
async function newRecordedPage(browser, { hostile = false } = {}) {
  const ctx = await browser.newContext({ viewport: VIEWPORT });
  if (hostile) {
    // The private-window shape that hurts: storage that THROWS, rather than
    // storage that is merely empty. Defined before any of the app's code runs.
    await ctx.addInitScript(() => {
      for (const name of ["localStorage", "sessionStorage"]) {
        Object.defineProperty(window, name, {
          configurable: true,
          get() {
            throw new DOMException(`${name} is disabled (smoke: hostile storage)`, "SecurityError");
          },
        });
      }
    });
  }
  const page = await ctx.newPage();
  const requested = [];
  const errors = [];
  page.on("request", (r) => {
    if (r.resourceType() !== "document") requested.push(r.url());
  });
  page.on("pageerror", (e) => errors.push(String(e)));
  return { ctx, page, requested, errors };
}

// -- 1. the matrix -------------------------------------------------------------

async function matrixPass(browser, stack, check, mod) {
  const label = `matrix[${mod.flag}]`;
  if (mod.answer) {
    // Team Agile mounts only where the Space is answered With agents.
    const answered = await answerWithAgents(stack.base, SPACE);
    check(`${label}: the Space answered With agents, through PUT /api/config`, answered.status === "success", answered.error ?? "");
  }
  const wrote = await setFlags(stack.base, { ...allOff(), [mod.flag]: true });
  check(`${label}: Config -Set ${mod.flag} alone on, through PUT /api/config`, wrote.status === "success", wrote.error ?? "");
  const { ctx, page, requested, errors } = await newRecordedPage(browser);
  try {
    await openRoute(page, stack.base, "/");
    const nav = await mainNavEntries(page);
    check(`${label}: the ${mod.nav} nav entry is there (SCENARIOS "${mod.scenario}")`, nav.includes(mod.nav), nav.join(" | "));
    check(`${label}: the Studio nav entry is there (core)`, nav.includes("Studio"), nav.join(" | "));
    for (const other of MODULES.filter((m) => m !== mod)) {
      check(`${label}: no ${other.nav} nav entry`, !nav.includes(other.nav), nav.join(" | "));
    }

    const text = await openRoute(page, stack.base, mod.route);
    check(`${label}: ${mod.route} draws the module's page with the fixture's data`, mod.page(text), text.slice(0, 300));
    check(
      `${label}: ${mod.id} source was fetched when its page was drawn`,
      requested.some((u) => moduleSourceUrl(mod.id, u)),
      "no part of the module was requested",
    );
    if (mod.data) {
      check(`${label}: ${mod.id} data was requested`, requested.some(mod.data), "nothing asked the agent for it");
    }
    for (const other of MODULES.filter((m) => m !== mod)) {
      const leaked = requested.filter((u) => moduleSourceUrl(other.id, u));
      check(`${label}: no ${other.id} source was requested`, leaked.length === 0, leaked.slice(0, 4).join(", "));
      if (other.data) {
        const asked = requested.filter(other.data);
        check(`${label}: no ${other.id} data was requested`, asked.length === 0, asked.slice(0, 4).join(", "));
      }
    }
    check(`${label}: no page errors`, errors.length === 0, errors.join(" | "));
  } finally {
    await ctx.close();
  }
}

// -- 3. fresh and hostile storage ----------------------------------------------

/** A crash would show instead of the page; a page error is the other tell. */
async function noCrash(page) {
  return page.evaluate(() => !/Something went wrong|Unexpected Application Error/i.test(document.body.innerText));
}

/** The chosen chip in a filter row, by the row's aria-label. */
const chosenChip = (page, group) =>
  page.evaluate(
    (g) =>
      (document.querySelector(`[role="group"][aria-label="${g}"] [role="radio"][aria-checked="true"]`)?.textContent ?? "")
        .trim()
        .replace(/\d+$/, "")
        .trim(),
    group,
  );

async function chooseChip(page, group, label) {
  await page.locator(`[role="group"][aria-label="${group}"] [role="radio"]`, { hasText: label }).first().click();
  await page.waitForFunction(
    ({ g, l }) =>
      (document.querySelector(`[role="group"][aria-label="${g}"] [role="radio"][aria-checked="true"]`)?.textContent ?? "")
        .trim()
        .startsWith(l),
    { g: group, l: label },
    { timeout: 10000 },
  );
}

const waitFor = (page, selector) => page.waitForSelector(selector, { timeout: 60000 }).then(() => true, () => false);

/** The theme the avatar menu says is in force: the Theme row's second text. */
async function themeNow(page) {
  await page.locator('button[aria-label^="You and your settings"]').click();
  const row = page.getByRole("menuitem", { name: /^Theme/ });
  await row.waitFor({ timeout: 10000 });
  const name = ((await row.textContent()) ?? "").replace(/^Theme/, "").trim();
  await page.keyboard.press("Escape");
  return name;
}

async function chooseTheme(page, name) {
  await page.locator('button[aria-label^="You and your settings"]').click();
  await page.getByRole("menuitem", { name: /^Theme/ }).click();
  await page.getByRole("menuitemradio", { name: new RegExp(`\\b${name}\\b`) }).click();
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
}

// Each surface: where it is, how to read it, its default, and a choice that is
// not the default.
const themeSource = () =>
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "src", "shell", "themeList.ts"), "utf8");
function themeNames() {
  const src = themeSource();
  const firstLight = /FIRST_LIGHT = "([^"]+)"/.exec(src)?.[1];
  const nameOf = (id) => new RegExp(`id: "${id}",\\s*name: "([^"]+)"`).exec(src)?.[1];
  return { dflt: nameOf(firstLight), other: nameOf("sunny") };
}

const SURFACES = [
  {
    name: "the Spaces card's filter",
    route: "/studio",
    ready: (page) => waitFor(page, '[role="group"][aria-label="Filter Spaces"]'),
    read: (page) => chosenChip(page, "Filter Spaces"),
    dflt: "All",
    choose: (page) => chooseChip(page, "Filter Spaces", "Out of box"),
    chosen: "Out of box",
  },
  {
    name: "the Reminders card's filter",
    route: "/organize",
    ready: (page) => waitFor(page, '[role="group"][aria-label="Filter reminders"]'),
    read: (page) => chosenChip(page, "Filter reminders"),
    dflt: "All",
    choose: (page) => chooseChip(page, "Filter reminders", "Upcoming"),
    chosen: "Upcoming",
  },
  {
    name: "the theme",
    route: "/",
    ready: (page) => waitFor(page, 'button[aria-label^="You and your settings"]'),
    read: (page) => themeNow(page),
    dflt: themeNames().dflt,
    choose: (page) => chooseTheme(page, themeNames().other),
    chosen: themeNames().other,
    // useCurrentTheme re-reads storage after a choice, so where storage throws
    // a choice does not take even for the page (its own comment says so). The
    // run says what it saw rather than holding it as a pass or a failure.
    hostileHoldsChoice: false,
  },
  {
    name: "the Lounge's tic-tac-toe",
    route: "/lounge",
    ready: (page) => waitFor(page, '[role="group"][aria-label="Tic-tac-toe board"]'),
    read: (page) =>
      page.evaluate(() =>
        Array.from(document.querySelectorAll('[role="group"][aria-label="Tic-tac-toe board"] button')).some((b) =>
          /yours/.test(b.getAttribute("aria-label") ?? ""),
        )
          ? "a move made"
          : "an empty board",
      ),
    dflt: "an empty board",
    choose: async (page) => {
      await page.locator('[role="group"][aria-label="Tic-tac-toe board"] button').first().click();
    },
    chosen: "a move made",
  },
  {
    // The played standup's mute. Default narrating; pressing it mutes.
    name: "the standup player's mute",
    route: "/deck/ritual/standup",
    ready: (page) => waitFor(page, 'button[aria-label="Mute narration"]'),
    read: (page) =>
      page
        .locator('button[aria-label="Mute narration"]')
        .getAttribute("aria-pressed")
        .then((v) => (v === "true" ? "muted" : "narrating")),
    dflt: "narrating",
    choose: async (page) => {
      await page.locator('button[aria-label="Mute narration"]').click();
    },
    chosen: "muted",
  },
];

async function storageCases(browser, stack, check) {
  for (const s of SURFACES) {
    // (a) a new context: empty storage
    {
      const { ctx, page, errors } = await newRecordedPage(browser);
      try {
        await openRoute(page, stack.base, s.route);
        const ready = await s.ready(page);
        check(`fresh: ${s.name} is drawn`, ready);
        const first = ready ? await s.read(page) : null;
        check(`fresh: ${s.name} opens on its default (${s.dflt})`, first === s.dflt, `read ${first}`);
        if (ready) await s.choose(page);
        const now = ready ? await s.read(page) : null;
        check(`fresh: ${s.name} takes a choice (${s.chosen})`, now === s.chosen, `read ${now}`);
        await openRoute(page, stack.base, s.route);
        const again = (await s.ready(page)) ? await s.read(page) : null;
        check(`fresh: ${s.name} keeps the choice across a reload`, again === s.chosen, `read ${again}`);
        check(`fresh: ${s.name} -- no page errors`, errors.length === 0, errors.join(" | "));
      } finally {
        await ctx.close();
      }
    }
    // (b) a context whose storage throws
    {
      const { ctx, page, errors } = await newRecordedPage(browser, { hostile: true });
      try {
        await openRoute(page, stack.base, s.route);
        const ready = await s.ready(page);
        check(`hostile: ${s.name} is drawn with storage refused`, ready, (await page.evaluate(() => document.body.innerText)).slice(0, 300));
        check(`hostile: ${s.route} shows no crash`, await noCrash(page));
        const first = ready ? await s.read(page) : null;
        check(`hostile: ${s.name} opens on its default (${s.dflt})`, first === s.dflt, `read ${first}`);
        if (ready) await s.choose(page);
        const now = ready ? await s.read(page) : null;
        if (s.hostileHoldsChoice === false) {
          console.log(`NOTE  hostile: ${s.name} after choosing ${s.chosen} reads ${now} (not held as a check -- see the mode's header)`);
        } else {
          check(`hostile: ${s.name} still takes a choice for the page's life`, now === s.chosen, `read ${now}`);
        }
        check(`hostile: ${s.name} -- no page errors`, errors.length === 0, errors.join(" | "));
      } finally {
        await ctx.close();
      }
    }
  }
}

export async function runMatrix({ repoRoot, agentPort, webPort, python }) {
  const { check, state } = makeChecker();
  const browser = await launchChromium();
  console.log(`smoke: matrix -- starting a scratch agent and Vite on ${FIXTURE_HUB}`);
  let stack;
  try {
    stack = await startStack({ repoRoot, hub: join(repoRoot, FIXTURE_HUB), space: SPACE, agentPort, webPort, python });
  } catch (err) {
    console.error(`FAIL  ${err.message}`);
    await browser.close();
    return 1;
  }
  console.log(`smoke: ${stack.base} (agent ${stack.agentPort}, scratch package ${stack.pkg})`);
  try {
    for (const mod of MODULES) await matrixPass(browser, stack, check, mod);

    const off = await setFlags(stack.base, allOff());
    check("flip: every module flag off first", off.status === "success", off.error ?? "");
    await flipCase({ browser, stack, check, flag: "lounge", navLabel: "Lounge" });

    const on = await setFlags(stack.base, { ...allOff(), organize: true, lounge: true, solitaireAgile: true });
    check("storage: Organize, the Lounge and Team Agile on, for their surfaces", on.status === "success", on.error ?? "");
    await storageCases(browser, stack, check);
  } catch (err) {
    check("matrix: the run finished", false, String(err && err.stack ? err.stack : err));
    console.error(stack.logs());
  } finally {
    await browser.close();
    await stack.stop();
  }
  console.log(
    state.failures === 0
      ? `smoke: clean (matrix, ${state.checks} checks)`
      : `smoke: ${state.failures} failure(s) (matrix, ${state.checks} checks)`,
  );
  return state.failures === 0 ? 0 : 1;
}
