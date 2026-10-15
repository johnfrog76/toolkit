// `node tests/smoke.mjs --a11y` -- axe over every page the registry mounts,
//in a real browser.
//
// On servers the mode owns (smokeStack.mjs), against Tests/fixtures/hub, four
// passes: every module flag OFF and every module flag ON (each set through
// PUT /api/config, the one writer), each in the first light theme (seaglass)
// and the dark one (aurora). A theme is a persisted choice, so each pass is a
// new browser context whose localStorage holds it before the app's code runs --
// the way a person who chose it arrives. On every page of the pass it runs
// axe-core (@axe-core/playwright, its default rule set, Fluent's focus
// sentinels left out -- TABSTER_DUMMY below) and keeps every violation.
//
// The pages are the registry's routes: the core's (the ado module's table and
// the Studio's) in both passes, and each opt-in module's descriptor routes in
// the ON pass, a route with a parameter opened on the fixture hub's own file.
// A route the registry adds is a row to add to PAGES below.
//
// It prints the findings grouped by impact -- critical, serious, moderate,
// minor -- one line per rule on a page in a theme and a mode, with the selector
// of every element it named (and the element, cut short) and the rule's help
// URL, then one summary line:
//
//   smoke: a11y -- <n> critical, <n> serious, <n> moderate, <n> minor over <pages> pages
//
// IT IS A GATE ON SERIOUS AND CRITICAL (once the fix PRs had them at
// zero): one such finding, on any page in either theme and either mode, fails
// the run (exit 1). Moderate and minor are listed and counted, never failed.
// It also exits 1 when the run itself broke (the servers would not start, a
// pass threw). It is not part of the default `npm run smoke` -- ten minutes a
// run is too long for that -- and stays its own script, `npm run smoke:a11y`.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { answerWithAgents, launchChromium, openRoute, setFlags, startStack } from "./smokeStack.mjs";

const FIXTURE_HUB = "Tests/fixtures/hub";
const SPACE = "test";
const VIEWPORT = { width: 1400, height: 900 };
const SETTLE_MS = 1500;
const LOADING_GRACE_MS = 60000;
const IMPACTS = ["critical", "serious", "moderate", "minor"];

// Left out of every analysis: Fluent's own focus sentinels. Fluent UI v9 manages
// focus through tabster, which brackets its focus roots (the FluentProvider's
// root, each Mover and Modalizer) with an `<i tabindex="0" aria-hidden="true"
// role="none" data-tabster-dummy>` -- an invisible element that catches Tab at
// the edge and passes focus on, never where a person's focus stays. axe reads it
// as aria-hidden-focus (serious), on every page: 100 of the first audit's 132
// serious findings, and not a line of ours to change -- Fluent inserts it at
// runtime. Excluding the attribute is the decision (the shell step), and
// it is reversible: if a Fluent or tabster version stops inserting the
// sentinels, this line and its sentence in docs/TESTING.md go with them.
const TABSTER_DUMMY = "[data-tabster-dummy]";

// The six opt-in modules' feature keys -- the flags --matrix walks one at a
// time; this mode sets them all at once.
const FLAGS = ["growth", "communication", "organize", "deck", "lounge", "solitaireAgile"];

// The theme key and the two themes, read from the source rather than retyped:
// THEME_KEY in useCurrentTheme.ts, FIRST_LIGHT in themeList.ts, and aurora --
// the dark theme the issue names (theme.ts).
const WEB_SRC = join(dirname(fileURLToPath(import.meta.url)), "..", "src");
const themeKey = /const THEME_KEY = "([^"]+)"/.exec(readFileSync(join(WEB_SRC, "hooks", "useCurrentTheme.ts"), "utf8"))?.[1];
const firstLight = /FIRST_LIGHT = "([^"]+)"/.exec(readFileSync(join(WEB_SRC, "shell", "themeList.ts"), "utf8"))?.[1];
const THEMES = [firstLight, "aurora"];

// Every page, by group (the fix PRs' groups) and the module that mounts it
// (null: core, mounted in both passes). Parameters are the fixture hub's files.
const PAGES = [
  // shell and Home -- Home's tabs and the System page
  { group: "shell and Home", route: "/" },
  { group: "shell and Home", route: "/sprint" },
  { group: "shell and Home", route: "/actions" },
  { group: "shell and Home", route: "/system" },
  { group: "shell and Home", route: "/daily" },
  { group: "shell and Home", route: "/connect/test" },
  // the board and cards
  { group: "the board and cards", route: "/board" },
  { group: "the board and cards", route: "/backlog" },
  { group: "the board and cards", route: "/prompts/Task401-add-retry-to-upload.prompt.md" },
  { group: "the board and cards", route: "/prompts/402-timeout-on-large-files.prompt.md" },
  { group: "the board and cards", route: "/pr-comments/402-timeout-on-large-files.prompt.md" },
  { group: "the board and cards", route: "/review" },
  { group: "the board and cards", route: "/issue/1" },
  // design and docs (Home's tabs and their reading rooms)
  { group: "design and docs", route: "/design" },
  { group: "design and docs", route: "/design/design/board-ideas.md" },
  { group: "design and docs", route: "/docs" },
  { group: "design and docs", route: "/docs/README.md" },
  // Studio (core)
  { group: "Studio", route: "/studio" },
  { group: "Studio", route: "/studio/design/board-ideas.md" },
  // the Prompts card's reading room: a shipped prompt, read from the package's agentic/
  { group: "Studio", route: "/studio/prompts/pr-ship" },
  // the opt-in modules
  { group: "growth", module: "growth", route: "/growth" },
  { group: "growth", module: "growth", route: "/growth/goals/goal-2026-improve-test-coverage-patterns.prompt.md" },
  { group: "growth", module: "growth", route: "/skills" },
  { group: "communication", module: "communication", route: "/communication" },
  { group: "communication", module: "communication", route: "/communication/1on1/2026-02-05.md" },
  { group: "communication", module: "communication", route: "/communication/sessions/2026-02-05.md" },
  { group: "communication", module: "communication", route: "/communication/sessions/new" },
  { group: "organize", module: "organize", route: "/organize" },
  { group: "deck", module: "deck", route: "/decks" },
  { group: "deck", module: "deck", route: "/deck/the-toolkit" },
  { group: "deck", module: "deck", route: "/deck/the-toolkit/notes" },
  { group: "lounge", module: "lounge", route: "/lounge" },
  { group: "solitaireAgile", module: "solitaireAgile", route: "/solitaire-agile" },
  { group: "solitaireAgile", module: "solitaireAgile", route: "/solitaire-agile/triage" },
  { group: "solitaireAgile", module: "solitaireAgile", route: "/deck/ritual/standup" },
];

/** An element's markup, one line, no class list, cut short. */
const elementText = (html) =>
  html
    .replace(/\s+class="[^"]*"/g, "")
    .replace(/\s+style="[^"]*"/g, "")
    .replace(/\s+/g, " ")
    .slice(0, 200);

/** What a page showed that says it did not draw -- noted, never fixed here. */
const NOT_DRAWN = /\b(Not Found|404)\b|Something went wrong|Unexpected Application Error/i;

async function auditPass(browser, stack, { mode, theme }, findings, notes, AxeBuilder) {
  const ctx = await browser.newContext({ viewport: VIEWPORT });
  await ctx.addInitScript(
    ({ key, id }) => {
      try {
        localStorage.setItem(key, id);
      } catch {
        /* a context that refuses storage is the matrix's case, not this one */
      }
    },
    { key: themeKey, id: theme },
  );
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e).split("\n")[0]));
  const pages = PAGES.filter((p) => !p.module || mode === "on");
  try {
    for (const p of pages) {
      errors.length = 0;
      try {
        await openRoute(page, stack.base, p.route);
      } catch (err) {
        notes.push(`${p.route} [${theme}, modules ${mode}]: did not open -- ${String(err.message ?? err).split("\n")[0]}`);
        continue;
      }
      // Settle before axe looks: a page draws in phases (a badge arrives with its
      // data, a transition runs), and a rule read mid-phase came and went between
      // two runs of the same tree. The network quiet, then a beat for the paint.
      await page.waitForLoadState("networkidle", { timeout: 8000 }).catch(() => {});
      await page.waitForTimeout(SETTLE_MS);
      // A page still loading is audited as its shell alone -- a whole pass once
      // came back with half its findings that way, on a busy machine. So give a
      // slow agent longer, and if the page never finishes, say so beside its
      // findings rather than let a short list pass as a clean one.
      const stillLoading = () => page.evaluate(() => /\bLoading\b/.test(document.body.innerText));
      if (await stillLoading()) {
        await page
          .waitForFunction(() => !/\bLoading\b/.test(document.body.innerText), null, { timeout: LOADING_GRACE_MS })
          .then(() => page.waitForTimeout(SETTLE_MS))
          .catch(() => {});
        if (await stillLoading()) notes.push(`${p.route} [${theme}, modules ${mode}]: still loading when axe ran`);
      }
      const text = await page.evaluate(() => document.body.innerText);
      if (NOT_DRAWN.test(text)) notes.push(`${p.route} [${theme}, modules ${mode}]: drew "${NOT_DRAWN.exec(text)[0]}"`);
      if (errors.length > 0) notes.push(`${p.route} [${theme}, modules ${mode}]: page error -- ${errors.join(" | ")}`);
      let result;
      try {
        result = await new AxeBuilder({ page }).exclude(TABSTER_DUMMY).analyze();
      } catch (err) {
        notes.push(`${p.route} [${theme}, modules ${mode}]: axe did not run -- ${String(err.message ?? err).split("\n")[0]}`);
        continue;
      }
      for (const v of result.violations) {
        findings.push({
          impact: v.impact ?? "minor",
          rule: v.id,
          help: v.help,
          helpUrl: v.helpUrl,
          group: p.group,
          route: p.route,
          theme,
          mode,
          // The selector, and the element itself cut short with its class list
          // dropped -- Fluent's generated class names make a selector alone hard to
          // read back to a component, and the attributes and text are what do.
          targets: v.nodes.map((n) => `${n.target.join(" ")}   <- ${elementText(n.html)}`),
        });
      }
    }
  } finally {
    await ctx.close();
  }
  return pages.length;
}

export async function runA11y({ repoRoot, agentPort, webPort, python }) {
  if (!themeKey || !firstLight) {
    console.error("FAIL  could not read the theme key or FIRST_LIGHT from the web source -- nothing to set the theme with.");
    return 1;
  }
  // Imported here, not at the top: smoke.mjs imports this file for every mode,
  // and a checkout whose node_modules predates the package must still run the
  // others. This one says what to run instead.
  let AxeBuilder;
  try {
    ({ AxeBuilder } = await import("@axe-core/playwright"));
  } catch {
    console.error("FAIL  @axe-core/playwright is not installed. Run `npm install` (or `npm ci`) in web/, then re-run.");
    return 1;
  }
  const browser = await launchChromium();
  console.log(`smoke: a11y -- starting a scratch agent and Vite on ${FIXTURE_HUB}`);
  let stack;
  try {
    stack = await startStack({ repoRoot, hub: join(repoRoot, FIXTURE_HUB), space: SPACE, agentPort, webPort, python });
  } catch (err) {
    console.error(`FAIL  ${err.message}`);
    await browser.close();
    return 1;
  }
  console.log(`smoke: ${stack.base} (agent ${stack.agentPort}, scratch package ${stack.pkg})`);
  const findings = [];
  const notes = [];
  let visited = 0;
  let broke = false;
  try {
    for (const mode of ["off", "on"]) {
      if (mode === "on") {
        // Team Agile's pages mount only where the Space is answered With agents,
        // so the ON pass runs on the fixture's Space answered so.
        const answered = await answerWithAgents(stack.base, SPACE);
        if (answered.status !== "success") throw new Error(`answer the Space With agents: ${answered.error ?? answered.status}`);
      }
      const wrote = await setFlags(stack.base, Object.fromEntries(FLAGS.map((f) => [f, mode === "on"])));
      if (wrote.status !== "success") throw new Error(`Config -Set every module flag ${mode}: ${wrote.error ?? wrote.status}`);
      for (const theme of THEMES) {
        console.log(`smoke: a11y -- modules ${mode}, ${theme}`);
        visited += await auditPass(browser, stack, { mode, theme }, findings, notes, AxeBuilder);
      }
    }
  } catch (err) {
    broke = true;
    console.error(`FAIL  a11y: the run did not finish -- ${String(err && err.stack ? err.stack : err)}`);
    console.error(stack.logs());
  } finally {
    await browser.close();
    await stack.stop();
  }

  for (const impact of IMPACTS) {
    const hits = findings.filter((f) => f.impact === impact);
    console.log("");
    console.log(`== ${impact} (${hits.length}) ==`);
    hits.sort((a, b) => a.group.localeCompare(b.group) || a.route.localeCompare(b.route) || a.rule.localeCompare(b.rule));
    for (const f of hits) {
      console.log(`${impact}  ${f.group}  ${f.route}  [${f.theme}, modules ${f.mode}]  ${f.rule} -- ${f.help}`);
      console.log(`    ${f.helpUrl}`);
      for (const t of f.targets) console.log(`    ${t}`);
    }
  }
  if (notes.length > 0) {
    console.log("");
    console.log(`== notes: pages that did not draw cleanly (${notes.length}) ==`);
    for (const n of notes) console.log(`NOTE  ${n}`);
  }
  const count = (i) => findings.filter((f) => f.impact === i).length;
  console.log("");
  console.log(
    `smoke: a11y -- ${count("critical")} critical, ${count("serious")} serious, ${count("moderate")} moderate, ${count("minor")} minor over ${visited} pages`,
  );
  const blocking = count("critical") + count("serious");
  if (blocking > 0) console.error(`FAIL  a11y: ${blocking} serious or critical finding(s) -- listed above`);
  return broke || blocking > 0 ? 1 : 0;
}
