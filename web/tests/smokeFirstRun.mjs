// `node tests/smoke.mjs --first-run` -- the first run's first move, in a browser.
//
// A fresh `Start` copies samples/hub out and lands on Demo's board, where the
// first tutorial card, *Start here: pull me onto the board*, is the one card in
// Backlog and four more wait in To do (docs/QUICKSTART.md, "The first run: one
// command"). This mode does what that card asks: it drags the card from Backlog
// to To do, and reads the moved file back from the hub.
//
// The drag WRITES (it runs Move through the bridge, which renames the file), so
// it cannot run against the committed fixture hub or a hub someone started.
// Like --studio, it starts its own servers (smokeStack.mjs): a scratch package,
// and a hub that is a COPY of samples/hub in the OS temp folder -- exactly what
// Start does, so the package's own samples are never used in place. Both are
// removed when the run ends.
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { launchChromium, makeChecker, openRoute, startStack } from "./smokeStack.mjs";

const SPACE = "demo";
const CARD_FILE = "TaskH3RE-start-here-pull-me-onto-the-board.prompt.md";
const CARD_NAME = "Start here: pull me onto the board";
const TO_DO = [
  "Open me and tick my boxes",
  "Find out one thing and write it down",
  'Say "look at this"',
  "Drop me on Done",
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The board's lanes: each group's aria-label and its text. */
const readLanes = (page) =>
  page.evaluate(() =>
    Array.from(document.querySelectorAll('section[aria-label="Board"] [role="group"]')).map(
      (g) => ({
        label: g.getAttribute("aria-label") ?? "",
        text: g.textContent ?? "",
      }),
    ),
  );

export async function runFirstRun({ repoRoot, agentPort, webPort, python }) {
  const { check, state } = makeChecker();
  const scratch = mkdtempSync(join(tmpdir(), "p20-first-run-"));
  const hub = join(scratch, "hub");
  cpSync(join(repoRoot, "samples", "hub"), hub, { recursive: true });
  const backlogPath = join(hub, SPACE, "backlog", CARD_FILE);
  const currentPath = join(hub, SPACE, "current", CARD_FILE);
  const original = readFileSync(backlogPath, "utf8");

  const browser = await launchChromium();
  console.log(
    `smoke: first-run -- starting a scratch agent and Vite on a copy of samples/hub (${hub})`,
  );
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
    const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
    page.on("pageerror", (e) => pageErrors.push(String(e)));
    await openRoute(page, stack.base, "/");
    await page
      .waitForFunction((name) => document.body.innerText.includes(name), CARD_NAME, {
        timeout: 30000,
      })
      .catch(() => {});

    const before = await readLanes(page);
    const backlog = before.find((l) => l.label.startsWith("Backlog"));
    const toDo = before.find((l) => l.label.startsWith("To do"));
    check(
      "first-run: Demo's board opens with the first tutorial card in Backlog, alone",
      Boolean(backlog) &&
        backlog.text.includes(CARD_NAME) &&
        /^Backlog, 1 cards?$/.test(backlog.label),
      JSON.stringify(before.map((l) => l.label)),
    );
    check(
      "first-run: and the other four in To do, with nothing else there",
      Boolean(toDo) &&
        TO_DO.every((n) => toDo.text.includes(n)) &&
        /^To do, 4 cards$/.test(toDo.label),
      toDo ? toDo.label : "no To do lane",
    );

    // The drag a person makes: the card's face onto the To do lane.
    const card = page
      .locator(
        'section[aria-label="Board"] [role="group"][aria-label^="Backlog"] div[draggable="true"]',
      )
      .filter({ hasText: CARD_NAME })
      .first();
    const target = page
      .locator('section[aria-label="Board"] [role="group"][aria-label^="To do"]')
      .first();
    await card.dragTo(target);

    // Move runs in a child pwsh through the bridge: wait for the file, not for a timer.
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline && !existsSync(currentPath)) await sleep(500);
    const moved = existsSync(currentPath);
    check(
      "first-run: the drag moved the file from demo/backlog/ to demo/current/",
      moved && !existsSync(backlogPath),
      `current/: ${moved}, backlog/: ${existsSync(backlogPath)}`,
    );
    check(
      "first-run: read back, the moved file is the card, byte for byte -- a pull is a rename",
      moved && readFileSync(currentPath, "utf8") === original,
    );

    await page
      .waitForFunction(
        (name) => {
          const lane = Array.from(
            document.querySelectorAll('section[aria-label="Board"] [role="group"]'),
          ).find((g) => (g.getAttribute("aria-label") ?? "").startsWith("To do"));
          return Boolean(lane && (lane.textContent ?? "").includes(name));
        },
        CARD_NAME,
        { timeout: 30000 },
      )
      .catch(() => {});
    const after = await readLanes(page);
    const toDoAfter = after.find((l) => l.label.startsWith("To do"));
    const backlogAfter = after.find((l) => l.label.startsWith("Backlog"));
    check(
      "first-run: the board draws it in To do, and Backlog is empty",
      Boolean(toDoAfter) &&
        toDoAfter.text.includes(CARD_NAME) &&
        Boolean(backlogAfter) &&
        !backlogAfter.text.includes(CARD_NAME),
      JSON.stringify(after.map((l) => l.label)),
    );
    check("first-run: no page errors", pageErrors.length === 0, pageErrors.join(" | "));
    await page.close();
  } catch (err) {
    check("first-run: the run finished", false, String(err && err.stack ? err.stack : err));
    console.error(stack.logs());
  } finally {
    await browser.close();
    await stack.stop();
    rmSync(scratch, { recursive: true, force: true });
  }

  console.log(
    state.failures === 0
      ? `smoke: clean (first-run, ${state.checks} checks)`
      : `smoke: ${state.failures} failure(s) (first-run, ${state.checks} checks)`,
  );
  return state.failures === 0 ? 0 : 1;
}
