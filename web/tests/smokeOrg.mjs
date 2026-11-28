// `node tests/smoke.mjs --org` -- the Org tab's first write, in a browser.
//
// On a preset, "Use this org" saves it as a draft through the bridge (Staff
// -Preset), and the Active dropdown puts it in use (Staff -Activate)
// (docs/modules/solitaire-agile.md, "The web UI"). This mode does both and reads
// the hub's org.json back after each.
//
// Before them, on the hub's own saved org: axe over the page and over the seat
// dialog, then Assign on a vacant seat, Save, and org.json read back -- the
// seat staffed through the bridge (Staff -Seat, with the chart's etag).
//
// All of it WRITES the hub, so, like --first-run, it starts its own servers
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
import { TABSTER_DUMMY } from "./smokeA11y.mjs";

const SPACE = "demo";
const SMALL = "Executive Suite (S)";
const SMALL_TITLE = "The Executive Suite";
const SMALL_ID = "executive-suite";
// The sample hub's vacant seat: its second team lead's.
const VACANT_SEAT = "github-demo";
const SEAT_SESSION = "smoke-lead";

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

    // axe on a saved org, and on the seat dialog open over it: nothing serious or critical.
    const { AxeBuilder } = await import("@axe-core/playwright");
    const blocking = async () =>
      (await new AxeBuilder({ page }).exclude(TABSTER_DUMMY).analyze()).violations
        .filter((v) => v.impact === "critical" || v.impact === "serious")
        .map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).join(", ")}`);
    const onPage = await blocking();
    check(
      "org: axe on a saved org finds nothing serious or critical",
      onPage.length === 0,
      onPage.join(" | "),
    );

    // Assign a vacant seat: the second team lead's, whose model the position states.
    const lead = page.locator('[data-testid="org-office"][data-position="team-lead"]');
    await lead.getByRole("button", { name: "Assign Team lead" }).click();
    const dialog = page.getByTestId("org-seat-dialog");
    await dialog.waitFor();
    // Past the dialog's fade-in: a colour read mid-animation is not the colour drawn.
    await sleep(1000);
    const inDialog = await blocking();
    check(
      "org: axe on the seat dialog finds nothing serious or critical",
      inDialog.length === 0,
      inDialog.join(" | "),
    );
    check(
      "org: the dialog opens with the position's model chosen",
      await dialog.getByRole("radio", { name: "Opus" }).isChecked(),
    );
    await page.getByTestId("org-seat-session").fill(SEAT_SESSION);
    await page.getByTestId("org-seat-save").click();
    const opus = JSON.parse(readFileSync(join(repoRoot, "Config", "models.json"), "utf8")).current
      .opus;
    const seatOf = (d) =>
      d.trees
        .find((t) => t.id === before.activeTree)
        ?.positions.find((p) => p.id === "team-lead")
        ?.seats.find((x) => x.id === VACANT_SEAT);
    const staffed = await waitForOrg(orgPath, (d) => seatOf(d)?.session === SEAT_SESSION);
    check(
      "org: Assign ran Staff -Seat: org.json's seat has the model's id and the session",
      Boolean(staffed) &&
        seatOf(staffed)?.model === opus &&
        seatOf(staffed)?.session === SEAT_SESSION,
      JSON.stringify(staffed && seatOf(staffed)),
    );
    await dialog.waitFor({ state: "detached", timeout: 30000 }).catch(() => {});
    await lead
      .getByRole("button", { name: /^Change Team lead, / })
      .nth(1)
      .waitFor({ timeout: 30000 })
      .catch(() => {});
    const focused = await page
      .waitForFunction(
        (seat) =>
          document.activeElement?.getAttribute("data-seat") === seat &&
          document.activeElement?.textContent === "Change",
        `team-lead.${VACANT_SEAT}`,
        { timeout: 30000 },
      )
      .then(() => true)
      .catch(() => false);
    check("org: after the save, focus is on the seat's new Change button", focused);
    check(
      "org: the seat's plate now offers Change, naming the model",
      (await lead.getByRole("button", { name: /^Change Team lead, Opus/ }).count()) === 2,
    );

    // Vacate the same seat from its Change: the model and the session go, its Space stays.
    const spaceBefore = seatOf(staffed)?.space;
    await lead
      .locator(`[data-testid="org-seat-action"][data-seat="team-lead.${VACANT_SEAT}"]`)
      .click();
    await dialog.waitFor();
    await sleep(1000);
    const withVacate = await blocking();
    check(
      "org: axe on the Change dialog with Vacate this seat finds nothing serious or critical",
      withVacate.length === 0,
      withVacate.join(" | "),
    );
    await page.getByTestId("org-seat-vacate").click();
    await page.getByTestId("org-seat-vacate-question").waitFor();
    const asking = await blocking();
    check(
      "org: axe on Vacate's question finds nothing serious or critical",
      asking.length === 0,
      asking.join(" | "),
    );
    await page.getByTestId("org-seat-vacate-confirm").click();
    const emptied = await waitForOrg(orgPath, (d) => seatOf(d) && !seatOf(d).model);
    check(
      "org: Vacate ran Staff -Seat -Vacate: the model and the session gone, the Space kept",
      Boolean(emptied) &&
        !("model" in seatOf(emptied)) &&
        !("session" in seatOf(emptied)) &&
        seatOf(emptied).space === spaceBefore,
      JSON.stringify(emptied && seatOf(emptied)),
    );
    const backOnAssign = await page
      .waitForFunction(
        (seat) =>
          document.activeElement?.getAttribute("data-seat") === seat &&
          document.activeElement?.textContent === "Assign",
        `team-lead.${VACANT_SEAT}`,
        { timeout: 30000 },
      )
      .then(() => true)
      .catch(() => false);
    check("org: after Vacate, focus is on the seat's Assign button", backOnAssign);

    // The owner's portrait: axe over the Change dialog with the picker, the choice moved
    // with the arrow keys as one radio group, Save, org.json read back, the card redrawn.
    const owner = page.locator('[data-testid="org-office"][data-position="owner"]');
    await owner.locator('[data-testid="org-seat-action"]').click();
    await dialog.waitFor();
    await sleep(1000);
    const withPicker = await blocking();
    check(
      "org: axe on the owner's Change dialog with the portrait picker finds nothing serious or critical",
      withPicker.length === 0,
      withPicker.join(" | "),
    );
    const portraits = dialog.getByRole("radiogroup", { name: "Portrait" });
    await portraits.getByRole("radio", { name: "Default" }).focus();
    await page.keyboard.press("ArrowRight");
    const secondName = await page.evaluate(
      () => document.activeElement?.closest("label")?.textContent,
    );
    check(
      "org: an arrow key moves the portrait choice within the one group",
      Boolean(secondName) && (await portraits.getByRole("radio", { name: secondName }).isChecked()),
      String(secondName),
    );
    await portraits.getByRole("radio", { name: "Robot" }).check();
    await page.getByTestId("org-seat-save").click();
    const ownerOf = (d) =>
      d.trees.find((t) => t.id === before.activeTree)?.positions.find((p) => !p.reportsTo)
        ?.seats[0];
    const pictured = await waitForOrg(orgPath, (d) => ownerOf(d)?.portrait === "robot");
    check(
      "org: Save ran Staff -Seat -Portrait: org.json's owner seat carries robot, its name as it was",
      Boolean(pictured) &&
        ownerOf(pictured)?.portrait === "robot" &&
        ownerOf(pictured)?.person === ownerOf(before)?.person,
      JSON.stringify(pictured && ownerOf(pictured)),
    );
    const drawn = await owner
      .locator('svg[data-refined="robot"]')
      .waitFor({ timeout: 30000 })
      .then(() => true)
      .catch(() => false);
    check("org: the owner's card draws the robot", drawn);

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
      JSON.stringify(
        saved && { activeTree: saved.activeTree, trees: saved.trees.map((t) => t.id) },
      ),
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
