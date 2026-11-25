// The Releases timeline in a real browser (docs/modules/solitaire-agile.md,
// "Releases: the timeline"), for the two modes that run Team Agile on a smoke
// stack of their own: --matrix walks the page (releasesTimelineCase), and
// --a11y scans it with the panel open (openReleasePanel).
//
// The timeline reads a Space's CHECKOUT, so the run gives the fixture's Space
// one: a small git repository built in the scratch package (removed with it),
// whose origin is the Space's GitHub address (SMOKE_GITHUB), with three release
// tags and the entries waiting in changelog.d/, and spaceCheckouts.<slug>.path
// set to it through PUT /api/config -- the one writer, into the scratch's
// config.local.json. The Space stays `local`, so no tracker is asked: the stops
// carry no flag and the issues keep their numbers. git runs with no global or
// system configuration, on fixed dates.
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { devNull } from "node:os";
import { dirname, join } from "node:path";
import { openRoute, SMOKE_GITHUB } from "./smokeStack.mjs";

const RELEASES_ROUTE = "/solitaire-agile/releases";
// The phone the timeline's clipping was seen at.
const PHONE = { width: 390, height: 844 };
const DESKTOP = { width: 1400, height: 900 };

const COMMITS = [
  { day: "2026-09-01", subject: "Start the widgets" },
  { day: "2026-09-10", subject: "Add the widget list (#3)", body: "Refs #1", tag: "v0.1.0" },
  { day: "2026-10-01", subject: "Sort the list by name (#5)", body: "Closes #4", tag: "v0.2.0" },
  { day: "2026-10-12", subject: "Search by tag (#7)", body: "Refs #6", tag: "v0.3.0" },
  {
    day: "2026-10-20",
    subject: "Export the list (#9)",
    body: "Refs #8",
    files: {
      "CHANGELOG.md":
        "# Changelog\n\n## [Unreleased]\n\n## [0.3.0] - 2026-10-12\n\n### Added\n\n- Search the list by tag.\n\n" +
        "## [0.2.0] - 2026-10-01\n\n### Changed\n\n- The list is sorted by name.\n\n" +
        "## [0.1.0] - 2026-09-10\n\n### Added\n\n- The widget list.\n",
      "changelog.d/9.added.md": "- Export the list as `widgets.csv`, **in order**.\n",
    },
  },
];

function git(cwd, args, day = "") {
  const env = {
    ...process.env,
    GIT_CONFIG_GLOBAL: devNull,
    GIT_CONFIG_SYSTEM: devNull,
    GIT_AUTHOR_NAME: "Smoke",
    GIT_AUTHOR_EMAIL: "smoke@example.invalid",
    GIT_COMMITTER_NAME: "Smoke",
    GIT_COMMITTER_EMAIL: "smoke@example.invalid",
  };
  if (day) env.GIT_AUTHOR_DATE = env.GIT_COMMITTER_DATE = `${day}T12:00:00Z`;
  const r = spawnSync("git", args, { cwd, env, encoding: "utf8", windowsHide: true });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${(r.stderr || r.error || "").toString().trim()}`);
}

/** Build the Space's clone in the scratch package and point the Space at it. Answers the verb's CommandResponse. */
export async function seedReleasesCheckout(stack, space) {
  const root = join(stack.pkg, "releases-clone");
  mkdirSync(root, { recursive: true });
  git(root, ["init", "-q", "-b", "main"]);
  git(root, ["config", "core.autocrlf", "false"]);
  git(root, ["remote", "add", "origin", `${SMOKE_GITHUB}.git`]);
  for (const c of COMMITS) {
    for (const [rel, text] of Object.entries(c.files ?? {})) {
      mkdirSync(dirname(join(root, rel)), { recursive: true });
      writeFileSync(join(root, rel), text, "utf8");
    }
    if (c.files) git(root, ["add", "-A"]);
    git(root, ["commit", "-q", "--allow-empty", "-m", c.body ? `${c.subject}\n\n${c.body}` : c.subject], c.day);
    if (c.tag) git(root, ["tag", c.tag], c.day);
  }
  const r = await fetch(`${stack.base}/api/config`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ set: { [`spaceCheckouts.${space}.path`]: root } }),
  });
  const body = await r.json().catch(() => ({}));
  return body.result ?? { status: `http ${r.status}`, error: JSON.stringify(body).slice(0, 300) };
}

const stopButton = (page, n) => page.locator('[data-testid="release-stop"] button').nth(n);
const panelHeading = (page) =>
  page
    .locator('[data-testid="release-panel"] h2')
    .textContent({ timeout: 5000 })
    .catch(() => "");
const focusedLabel = (page) => page.evaluate(() => document.activeElement?.getAttribute("aria-label") ?? "");

/** Open the timeline and wait for its stops; false when none was drawn. */
async function openTimeline(page, base) {
  await openRoute(page, base, RELEASES_ROUTE);
  return page
    .waitForSelector('[data-testid="release-stop"]', { timeout: 30000 })
    .then(() => true)
    .catch(() => false);
}

/** The --a11y row's way in: the timeline with the panel open on its third release. */
export async function openReleasePanel(page, base) {
  if (!(await openTimeline(page, base))) return false;
  await stopButton(page, 2).click();
  return page
    .waitForSelector('[data-testid="release-panel"]', { timeout: 5000 })
    .then(() => true)
    .catch(() => false);
}

/** Whether the track's left edge sits on a stop's edge, and the selected stop is wholly in view. */
const trackFits = (page) =>
  page.evaluate(() => {
    const stops = Array.from(document.querySelectorAll('[data-testid="release-stop"]'));
    const view = stops[0]?.parentElement?.parentElement;
    if (!view) return { ok: false, why: "no track" };
    const v = view.getBoundingClientRect();
    const boxes = stops.map((s) => s.getBoundingClientRect());
    const cut = boxes.find((b) => b.left < v.left - 1 && b.right > v.left + 1);
    const selected = stops.findIndex((s) => s.querySelector('button[aria-current="true"]'));
    const sb = boxes[selected];
    const whole = sb && sb.left >= v.left - 1 && sb.right <= v.right + 1;
    return {
      ok: !cut && !!whole,
      why: `scrollLeft ${view.scrollLeft}, view ${Math.round(v.width)}, stops ${boxes
        .map((b) => `${Math.round(b.left - v.left)}..${Math.round(b.right - v.left)}`)
        .join(" ")}, selected ${selected}`,
    };
  });

/**
 * The walk: the track renders, a click opens the panel, Left and Right step and
 * focus follows, Escape closes and gives focus back; an entry's code span is
 * drawn; at phone width, the panel open on the third release, no stop is cut at
 * the track's left edge.
 */
export async function releasesTimelineCase({ browser, stack, check, label = "releases" }) {
  for (const viewport of [DESKTOP, PHONE]) {
    const ctx = await browser.newContext({ viewport });
    const page = await ctx.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e).split("\n")[0]));
    const at = `${label}[${viewport.width}]`;
    try {
      const drawn = await openTimeline(page, stack.base);
      const count = await page.locator('[data-testid="release-stop"]').count();
      check(`${at}: the track draws one stop a release, the one in progress first`, drawn && count === 4, `${count} stops`);
      if (!drawn) continue;

      await stopButton(page, 2).click();
      check(`${at}: a click opens the side panel on that release`, (await panelHeading(page)) === "v0.2.0", await panelHeading(page));
      if (viewport === PHONE) {
        const fits = await trackFits(page);
        check(`${at}: the panel open on the third release, no stop is cut at the track's left edge`, fits.ok, fits.why);
      }
      await page.keyboard.press("ArrowRight");
      check(
        `${at}: Right steps to the next release, focus and the panel following`,
        (await focusedLabel(page)).startsWith("v0.1.0") && (await panelHeading(page)) === "v0.1.0",
        `${await focusedLabel(page)} / ${await panelHeading(page)}`,
      );
      if (viewport === PHONE) {
        const fits = await trackFits(page);
        check(`${at}: stepped to the last release, no stop is cut at the track's left edge`, fits.ok, fits.why);
      }
      await page.keyboard.press("ArrowLeft");
      check(
        `${at}: Left steps back`,
        (await focusedLabel(page)).startsWith("v0.2.0") && (await panelHeading(page)) === "v0.2.0",
        `${await focusedLabel(page)} / ${await panelHeading(page)}`,
      );
      await page.keyboard.press("Escape");
      const closed = (await page.locator('[data-testid="release-panel"]').count()) === 0;
      check(
        `${at}: Escape closes the panel and gives focus back to the stop`,
        closed && (await focusedLabel(page)).startsWith("v0.2.0"),
        `panel ${closed ? "closed" : "open"}, focus ${await focusedLabel(page)}`,
      );

      await stopButton(page, 0).click();
      const code = await page
        .locator('[data-testid="release-panel"] li code')
        .first()
        .textContent({ timeout: 5000 })
        .catch(() => "");
      check(`${at}: an entry's code span is drawn as code, not as backticks`, code === "widgets.csv", `code "${code}"`);
      check(`${at}: no page errors`, errors.length === 0, errors.join(" | "));
    } finally {
      await ctx.close();
    }
  }
}
