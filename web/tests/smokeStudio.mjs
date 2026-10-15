// `node tests/smoke.mjs --studio` -- the Studio's contract in a browser.
//
// What the Gate 12 walks proved by hand, and jsdom
// cannot: a leftover config line being ignored by a running agent, a flag
// changing under that agent, and the Spaces card's boxes holding still.
//
// The mode starts its own servers (smokeStack.mjs says why): a scratch package
// seeded with Tests/fixtures/hub-spaces/config.local.json -- the dead
// `"features": { "studio": false }` line -- and an agent on
// Tests/fixtures/hub-spaces/hub, one Space of each kind. Three cases:
//
//   (a) the leftover line leaves the Studio tab and its Spaces card in place
//   (b) a module flag set true then false through PUT /api/config, with the
//       agent running: its nav entry appears on a reload and goes on the next
//   (c) the Spaces card's tags and filter: the counts, each filter's rows, the
//       tags and header holding their boxes as the filter changes, the choice
//       kept after a reload, and a fresh browser context opening on All
//
// Not built: the New Space dialog (repositories already imported shown
// disabled, an add drawn without a reload). It needs a `gh` stand-in, and the tracker
// leaves it open as its own issue.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { envFeatures, flipCase, launchChromium, makeChecker, navText, openRoute, startStack } from "./smokeStack.mjs";

const FIXTURE = "Tests/fixtures/hub-spaces";
const SPACE = "work";

/** Which rows each tag should list, from the fixture and the shipped config
 *  -- written out, not derived with the rule under test. */
function expectedBuckets(repoRoot) {
  const shipped = JSON.parse(readFileSync(join(repoRoot, "config.default.json"), "utf8")).spaces ?? [];
  const nonExample = shipped.filter((s) => s.example !== true).map((s) => s.slug);
  const buckets = {
    products: ["Product Space"],
    work: ["Work Space"],
    outOfBox: ["Sample Space", ...shipped.map((s) => s.name || s.slug)],
    archive: ["Retired Space"],
  };
  buckets.all = [...buckets.products, ...buckets.work, ...buckets.outOfBox, ...buckets.archive];
  return { buckets, nonExample };
}

const TAGS = [
  ["all", "All"],
  ["products", "Products"],
  ["work", "Work"],
  ["outOfBox", "Out of box"],
  ["archive", "Archive"],
];

/** The card once it is drawn: its tags (label, count, chosen), its rows' names,
 *  and the boxes that must not move. */
async function readCard(page) {
  await page.waitForFunction(
    () => document.querySelector('[role="group"][aria-label="Filter Spaces"]') && !document.body.innerText.includes("Reading the Spaces"),
    null,
    { timeout: 60000 },
  );
  return page.evaluate(() => {
    const box = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    };
    const group = document.querySelector('[role="group"][aria-label="Filter Spaces"]');
    const tags = Array.from(group.querySelectorAll('[role="radio"]')).map((t) => {
      const text = (t.textContent ?? "").trim();
      const m = /^(.*?)(\d+)?$/.exec(text);
      return { label: m[1].trim(), count: m[2] === undefined ? null : Number(m[2]), chosen: t.getAttribute("aria-checked") === "true", box: box(t) };
    });
    const chip = document.querySelector('[aria-label$=" Spaces"]');
    const header = chip?.parentElement?.parentElement ?? null;
    const title = header?.firstElementChild ?? null;
    const rows = Array.from(group.parentElement.querySelectorAll("strong")).map((s) => s.textContent?.trim());
    return { tags, rows, chip: chip?.textContent?.trim() ?? null, boxes: { group: box(group), header: box(header), title: box(title), chip: box(chip) } };
  });
}

const sameBox = (a, b) =>
  a && b && Math.abs(a.x - b.x) < 0.5 && Math.abs(a.y - b.y) < 0.5 && Math.abs(a.w - b.w) < 0.5 && Math.abs(a.h - b.h) < 0.5;

async function chooseTag(page, label) {
  await page.locator('[role="group"][aria-label="Filter Spaces"] [role="radio"]', { hasText: label }).first().click();
  await page.waitForFunction(
    (l) =>
      Array.from(document.querySelectorAll('[role="group"][aria-label="Filter Spaces"] [role="radio"]')).some(
        (t) => (t.textContent ?? "").trim().startsWith(l) && t.getAttribute("aria-checked") === "true",
      ),
    label,
    { timeout: 10000 },
  );
}

const sorted = (xs) => [...xs].sort();
const sameSet = (a, b) => JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));

export async function runStudio({ repoRoot, agentPort, webPort, python }) {
  const { check, state } = makeChecker();
  const browser = await launchChromium();
  console.log(`smoke: studio -- starting a scratch agent and Vite on ${FIXTURE}`);
  let stack;
  try {
    stack = await startStack({
      repoRoot,
      hub: join(repoRoot, FIXTURE, "hub"),
      space: SPACE,
      seedFile: join(repoRoot, FIXTURE, "config.local.json"),
      agentPort,
      webPort,
      python,
    });
  } catch (err) {
    console.error(`FAIL  ${err.message}`);
    await browser.close();
    return 1;
  }
  console.log(`smoke: ${stack.base} (agent ${stack.agentPort}, scratch package ${stack.pkg})`);
  const pageErrors = [];
  const track = (page) => page.on("pageerror", (e) => pageErrors.push(String(e)));

  try {
    // -- (a) a leftover features.studio: false --------------------------------
    const before = await envFeatures(stack.base);
    check("studio: the agent read the leftover line (/api/env echoes features.studio false)", before.studio === false, JSON.stringify(before));
    const page = await browser.newPage();
    track(page);
    await openRoute(page, stack.base, "/");
    check("studio: the Studio nav entry is there with features.studio false", /\bStudio\b/.test(await navText(page)));
    await openRoute(page, stack.base, "/studio");
    const first = await readCard(page).catch(() => null);
    check("studio: /studio draws its Spaces card", first !== null);
    await page.close();

    // -- (b) the flip, with the agent running ---------------------------------
    await flipCase({ browser, stack, check, flag: "growth", navLabel: "Growth" });
    const kept = JSON.parse(readFileSync(stack.localConfigPath, "utf8"));
    check(
      "studio: the writer left the leftover line as it was (read, not written)",
      kept.features?.studio === false,
      JSON.stringify(kept.features),
    );
    const after = await browser.newPage();
    track(after);
    await openRoute(after, stack.base, "/");
    check("studio: the Studio nav entry is still there after the flip", /\bStudio\b/.test(await navText(after)));
    await after.close();

    // -- (c) the Spaces card's tags and filter --------------------------------
    const { buckets, nonExample } = expectedBuckets(repoRoot);
    check(
      "studio: every Space config.default.json ships is an example (the expected counts assume it)",
      nonExample.length === 0,
      `not examples: ${nonExample.join(", ")} -- update expectedBuckets`,
    );
    const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    const p = await ctx.newPage();
    track(p);
    await openRoute(p, stack.base, "/studio");
    const all = await readCard(p);
    for (const [key, label] of TAGS) {
      const tag = all.tags.find((t) => t.label === label);
      const want = buckets[key].length;
      check(`spaces: the ${label} tag reads ${want}`, tag?.count === want, JSON.stringify(all.tags.map((t) => [t.label, t.count])));
    }
    check(`spaces: the header's chip is the total, ${buckets.all.length}`, all.chip === String(buckets.all.length), all.chip ?? "no chip");
    check("spaces: a fresh browser opens on All", all.tags.find((t) => t.chosen)?.label === "All", JSON.stringify(all.tags.map((t) => [t.label, t.chosen])));
    check("spaces: All lists every Space", sameSet(all.rows, buckets.all), all.rows.join(", "));

    for (const [key, label] of TAGS.slice(1).concat([TAGS[0]])) {
      await chooseTag(p, label);
      const now = await readCard(p);
      check(`spaces: ${label} lists ${buckets[key].join(", ")}`, sameSet(now.rows, buckets[key]), now.rows.join(", "));
      check(
        `spaces: ${label} is the one tag marked`,
        now.tags.filter((t) => t.chosen).map((t) => t.label).join() === label,
        JSON.stringify(now.tags.map((t) => [t.label, t.chosen])),
      );
      const moved = ["group", "header", "title", "chip"].filter((k) => !sameBox(now.boxes[k], all.boxes[k]));
      const tagMoved = now.tags.filter((t, i) => !sameBox(t.box, all.tags[i]?.box)).map((t) => t.label);
      check(
        `spaces: on ${label} the tags and the header hold their boxes`,
        moved.length === 0 && tagMoved.length === 0,
        `moved: ${[...moved, ...tagMoved].join(", ")}`,
      );
    }

    await chooseTag(p, "Archive");
    await openRoute(p, stack.base, "/studio");
    const reloaded = await readCard(p);
    check("spaces: Archive is still chosen after a reload", reloaded.tags.find((t) => t.chosen)?.label === "Archive", JSON.stringify(reloaded.tags.map((t) => [t.label, t.chosen])));
    check("spaces: ...and lists only the archived Space", sameSet(reloaded.rows, buckets.archive), reloaded.rows.join(", "));
    await ctx.close();

    const fresh = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    const fp = await fresh.newPage();
    track(fp);
    await openRoute(fp, stack.base, "/studio");
    const clean = await readCard(fp);
    check("spaces: a new browser context opens on All, whatever another chose", clean.tags.find((t) => t.chosen)?.label === "All", JSON.stringify(clean.tags.map((t) => [t.label, t.chosen])));
    check("spaces: ...with every Space showing", sameSet(clean.rows, buckets.all), clean.rows.join(", "));
    await fresh.close();

    check("studio: no page errors", pageErrors.length === 0, pageErrors.join(" | "));
  } catch (err) {
    check("studio: the run finished", false, String(err && err.stack ? err.stack : err));
    console.error(stack.logs());
  } finally {
    await browser.close();
    await stack.stop();
  }
  console.log(
    state.failures === 0
      ? `smoke: clean (studio, ${state.checks} checks)`
      : `smoke: ${state.failures} failure(s) (studio, ${state.checks} checks)`,
  );
  return state.failures === 0 ? 0 : 1;
}
