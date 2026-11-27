// `node tests/smoke.mjs --org` -- the Org tab's first write, in a browser.
//
// On a preset, "Use this org" saves it as a draft through the bridge (Staff
// -Preset), and the Active dropdown puts it in use (Staff -Activate)
// (docs/modules/solitaire-agile.md, "The web UI"). This mode does both and reads
// the hub's org.json back after each.
//
// Both WRITE the hub, so, like --first-run, it starts its own servers
// (smokeStack.mjs) over a COPY of samples/hub in the OS temp folder -- the
// package's samples are never used in place -- and turns Team Agile on through
// the one writer, into the scratch package's config. Both are removed when the
// run ends.
import { cpSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  answerWithAgents,
  launchChromium,
  makeChecker,
  openRoute,
  setFlags,
  startStack,
} from "./smokeStack.mjs";

const SPACE = "demo";
const SMALL = "Executive Suite (S)";
const SMALL_TITLE = "The Executive Suite";
const SMALL_ID = "executive-suite";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The hub's org.json as it is on disk now, or null when it does not parse. */
function readOrg(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

/** Wait for org.json to say something -- the bridge runs Staff in a child pwsh. */
async function waitForOrg(path, test, ms = 90000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const doc = readOrg(path);
    if (doc && test(doc)) return doc;
    await sleep(500);
  }
  return readOrg(path);
}

/** Pick an option of one of the header's two dropdowns. */
async function pick(page, testId, name) {
  await page.getByTestId(testId).click();
  await page.getByRole("option", { name, exact: true }).click();
}

export async function runOrg({ repoRoot, agentPort, webPort, python }) {
  const { check, state } = makeChecker();
  const scratch = mkdtempSync(join(tmpdir(), "p20-org-"));
  const hub = join(scratch, "hub");
  cpSync(join(repoRoot, "samples", "hub"), hub, { recursive: true });
  const orgPath = join(hub, "org.json");
  const before = readOrg(orgPath);
  const activeTitle = before.trees.find((t) => t.id === before.activeTree).title;

  const browser = await launchChromium();
  console.log(`smoke: org -- starting a scratch agent and Vite on a copy of samples/hub (${hub})`);
  let stack;
  try {
    stack = await startStack({ repoRoot, hub, space: SPACE, agentPort, webPort, python });
  } catch (err) {
    console.error(`FAIL  ${err.message}`);
    await browser.close();
    rmSync(scratch, { recursive: true, force: true });
    return 1;
  }
  console.log(`smoke: ${stack.base} (agent ${stack.agentPort}, scratch package ${stack.pkg})`);
  const pageErrors = [];

  try {
    const flags = await setFlags(stack.base, { solitaireAgile: true });
    const agents = await answerWithAgents(stack.base, SPACE);
    check(
      "org: Team Agile on, the Space answered with agents",
      flags.status === "success" && agents.status === "success",
      `${flags.status} ${flags.error ?? ""} / ${agents.status} ${agents.error ?? ""}`,
    );

    const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
    page.on("pageerror", (e) => pageErrors.push(String(e)));
    await openRoute(page, stack.base, "/solitaire-agile/org");
    await page.getByTestId("org-active-select").waitFor({ timeout: 30000 });
    check(
      "org: the page opens on the hub's active org, with Active beside View",
      (await page.getByTestId("org-heading").textContent()) === activeTitle,
    );

    // Save Small: the preview, the steps, Save.
    await pick(page, "org-preset-select", SMALL);
    check(
      "org: the Small preview says it is a preview, naming the active org",
      (await page.getByTestId("org-not-active").textContent()) ===
        `A preview. Your active org is ${activeTitle}.`,
    );
    await page.getByTestId("org-use").click();
    await page.getByTestId("org-use-dialog").waitFor();
    await page.getByTestId("org-use-save").click();
    const saved = await waitForOrg(orgPath, (d) => d.trees.some((t) => t.id === SMALL_ID));
    const small = saved && saved.trees.find((t) => t.id === SMALL_ID);
    check(
      "org: Save wrote the preset into org.json as a draft, the active org unchanged",
      Boolean(small) && small.preset === SMALL_ID && saved.activeTree === before.activeTree,
      JSON.stringify(saved && { activeTree: saved.activeTree, trees: saved.trees.map((t) => t.id) }),
    );
    await page
      .waitForFunction(
        (title) => document.querySelector('[data-testid="org-heading"]')?.textContent === title,
        SMALL_TITLE,
        { timeout: 30000 },
      )
      .catch(() => {});
    check(
      "org: the page shows the saved draft, and says it is one",
      (await page.getByTestId("org-heading").textContent()) === SMALL_TITLE &&
        (await page.getByTestId("org-not-active").textContent()) ===
          `A draft. Your active org is ${activeTitle}.`,
    );

    // Make it active.
    await pick(page, "org-active-select", SMALL_TITLE);
    const activated = await waitForOrg(orgPath, (d) => d.activeTree === SMALL_ID);
    check(
      "org: Active ran Staff -Activate: org.json's activeTree is the saved org",
      Boolean(activated) && activated.activeTree === SMALL_ID,
      JSON.stringify(activated && activated.activeTree),
    );
    await page
      .waitForFunction(() => !document.querySelector('[data-testid="org-not-active"]'), null, {
        timeout: 30000,
      })
      .catch(() => {});
    check(
      "org: the page shows it as the active org, with no line under the heading",
      (await page.getByTestId("org-heading").textContent()) === SMALL_TITLE &&
        (await page.getByTestId("org-not-active").count()) === 0,
    );
    check("org: no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    await page.close();
  } catch (err) {
    check("org: the run finished", false, String(err && err.stack ? err.stack : err));
    console.error(stack.logs());
  } finally {
    await browser.close();
    await stack.stop();
    rmSync(scratch, { recursive: true, force: true });
  }

  console.log(
    state.failures === 0
      ? `smoke: clean (org, ${state.checks} checks)`
      : `smoke: ${state.failures} failure(s) (org, ${state.checks} checks)`,
  );
  return state.failures === 0 ? 0 : 1;
}
