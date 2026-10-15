// The servers a smoke mode OWNS, for the cases that have to CHANGE the agent's
// configuration under it: a flag flipped with no restart, a
// leftover config line, a hub of one Space of each kind.
//
// Why not `tkWeb -Dev -Fixture`. That run carries the flags in the servers'
// ENVIRONMENT (consts.json env.features, P20_FEATURES), and the environment
// REPLACES config.local.json's features block on every read
// (agent/core/config.py, features_override). So a `Config -Set` through the
// bridge would land in the checkout's config.local.json and change nothing the
// agent serves -- and it would write the machine's own file, which a smoke never
// does. A flip has to be written by the one writer into a file the agent then
// reads, and that file must not be anybody's.
//
// So the smoke builds its own:
//
//   a SCRATCH PACKAGE   a copy of the package's runtime parts (the agent, the
//                       module, its scripts and config) in the OS temp folder.
//                       The agent reads config.local.json beside ITS OWN tree
//                       (REPO_ROOT, from __file__), and the bridge imports the
//                       manifest beside ITSELF (agent/ado/bridge.ps1), so every
//                       `Config -Set` the flip runs writes the scratch's
//                       config.local.json and nothing else.
//   its AGENT           `python -m uvicorn agent.app:app` in the scratch, as a
//                       test run: the run marker set, every TEAMS_WEBHOOK_*
//                       removed, PROMPTS_ROOT at a committed fixture hub and the
//                       Space through env.activeSpace -- the same stand-ins
//                       -Fixture uses -- and NO env.features, so the flags are
//                       the scratch file's.
//   its VITE            this checkout's web/, proxying /api to that agent
//                       (env.agentPort, which vite.config.ts reads).
//
// Both are stopped, and the scratch removed, when the run ends. The fixture hub
// is read where it is committed, as -Fixture reads Tests/fixtures/hub; the flag
// writes go to the package's config, never to the hub.
import { spawn, spawnSync } from "node:child_process";
import { closeSync, copyFileSync, cpSync, existsSync, mkdtempSync, openSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

// What a running agent and bridge need from the package -- and nothing that a
// write could reach back through. web/ is served from the checkout itself.
const PACKAGE_PARTS = [
  "agent",
  "agentic",
  "Config",
  "Prompt20Toolkit",
  "Scripts",
  "templates",
  "config.default.json",
  "consts.json",
  "utilities.psm1",
];

/** A port nothing is listening on, from the OS. */
export function freePort() {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function killTree(child) {
  if (!child || child.exitCode !== null || child.pid === undefined) return;
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore" });
  } else {
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch {
      child.kill("SIGTERM");
    }
  }
}

function tail(file, lines = 30) {
  if (!existsSync(file)) return "";
  return readFileSync(file, "utf8").split(/\r?\n/).slice(-lines).join("\n");
}

/**
 * Build the scratch package and start its agent and Vite.
 *
 *   repoRoot   the checkout (the package is copied from it, web/ served from it)
 *   hub        absolute path of the fixture hub (PROMPTS_ROOT)
 *   space      the Space slug the run is in (env.activeSpace)
 *   seedFile   a committed file COPIED in as the scratch's config.local.json
 *              before the agent starts -- the stand-in for a line a person typed
 *              by hand. Every change after that goes through PUT /api/config.
 *   agentPort, webPort   0 or undefined picks a free one
 *   python     the interpreter (python on Windows, python3 elsewhere)
 */
export async function startStack({ repoRoot, hub, space, seedFile, agentPort, webPort, python }) {
  const consts = JSON.parse(readFileSync(join(repoRoot, "consts.json"), "utf8"));
  const pkg = mkdtempSync(join(tmpdir(), "p20-smoke-"));
  for (const part of PACKAGE_PARTS) {
    cpSync(join(repoRoot, part), join(pkg, part), {
      recursive: true,
      filter: (src) => !/[\\/](__pycache__|\.pytest_cache)([\\/]|$)/.test(src),
    });
  }
  if (seedFile) copyFileSync(seedFile, join(pkg, "config.local.json"));

  const aPort = agentPort || (await freePort());
  const wPort = webPort || (await freePort());

  const env = { ...process.env };
  for (const k of Object.keys(env)) {
    if (k.toUpperCase().startsWith(consts.env.teamsWebhookPrefix)) delete env[k];
    if (k.toUpperCase() === consts.env.features) delete env[k];
  }
  env[consts.env.testRunMarker] = "smoke";
  env.PROMPTS_ROOT = hub;
  env[consts.env.activeSpace] = space;

  const agentLog = join(pkg, "smoke-agent.log");
  const viteLog = join(pkg, "smoke-vite.log");
  const detached = process.platform !== "win32";
  const aFd = openSync(agentLog, "a");
  const agent = spawn(python, ["-m", "uvicorn", "agent.app:app", "--host", "127.0.0.1", "--port", String(aPort)], {
    cwd: pkg,
    env,
    stdio: ["ignore", aFd, aFd],
    windowsHide: true,
    detached,
  });
  const vFd = openSync(viteLog, "a");
  const webRoot = join(repoRoot, "web");
  const vite = spawn(
    process.execPath,
    [join(webRoot, "node_modules", "vite", "bin", "vite.js"), "--port", String(wPort), "--strictPort"],
    { cwd: webRoot, env: { ...env, [consts.env.agentPort]: String(aPort) }, stdio: ["ignore", vFd, vFd], windowsHide: true, detached },
  );
  closeSync(aFd);
  closeSync(vFd);

  const base = `http://localhost:${wPort}`;
  const stack = {
    base,
    pkg,
    agent,
    vite,
    agentPort: aPort,
    webPort: wPort,
    localConfigPath: join(pkg, "config.local.json"),
    logs: () => `--- agent (${agentLog}) ---\n${tail(agentLog)}\n--- vite (${viteLog}) ---\n${tail(viteLog)}`,
    async stop() {
      killTree(vite);
      killTree(agent);
      // The children's handles on the scratch (the logs, a __pycache__) close
      // a moment after the kill on Windows.
      for (let i = 0; i < 10; i++) {
        try {
          rmSync(pkg, { recursive: true, force: true });
          return;
        } catch {
          await sleep(500);
        }
      }
      console.error(`smoke: could not remove the scratch package ${pkg}`);
    },
  };

  // Up when the agent answers THROUGH the proxy -- the path the app takes.
  const deadline = Date.now() + 120000;
  for (;;) {
    if (agent.exitCode !== null || vite.exitCode !== null) {
      const said = stack.logs();
      await stack.stop();
      throw new Error(`a smoke server exited before it answered\n${said}`);
    }
    try {
      const r = await fetch(`${base}/api/health`);
      if (r.ok) break;
    } catch {
      /* not yet */
    }
    if (Date.now() > deadline) {
      const said = stack.logs();
      await stack.stop();
      throw new Error(`the smoke servers did not answer ${base}/api/health within 120 s\n${said}`);
    }
    await sleep(500);
  }
  return stack;
}

/**
 * Set feature flags the way the settings drawer does: PUT /api/config, which
 * runs `Config -Set` through the bridge -- the one writer. Never the file.
 * Answers the verb's CommandResponse.
 */
export async function setFlags(base, flags) {
  const set = Object.fromEntries(Object.entries(flags).map(([k, v]) => [`features.${k}`, v]));
  const r = await fetch(`${base}/api/config`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ set }),
  });
  const body = await r.json().catch(() => ({}));
  return body.result ?? { status: `http ${r.status}`, error: JSON.stringify(body).slice(0, 300) };
}

/**
 * Answer the run's Space "With agents" -- the one answer Team Agile
 * mounts on -- through PUT /api/config, the one writer, into the scratch
 * package's local patch. The fixture hub's Space carries an Azure DevOps
 * address, which is on a team and never asked, so the patch gives it a GitHub
 * one first; the Space stays `local`, so the tracker is never contacted and the
 * standup fills from the fixture's cards. Answers the verb's CommandResponse.
 */
export const SMOKE_GITHUB = "https://github.com/p20-smoke/no-such-repo";
export async function answerWithAgents(base, space) {
  const set = { [`spaces.${space}.org`]: SMOKE_GITHUB, [`spaces.${space}.howIWork`]: "agents" };
  const r = await fetch(`${base}/api/config`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ set, local: true }),
  });
  const body = await r.json().catch(() => ({}));
  return body.result ?? { status: `http ${r.status}`, error: JSON.stringify(body).slice(0, 300) };
}

/** /api/env's features, read through the proxy as the app reads them. */
export async function envFeatures(base) {
  const r = await fetch(`${base}/api/env`);
  return r.ok ? ((await r.json()).features ?? {}) : {};
}

/** Open a route and wait for the shell's gate and the page's own loading to clear. */
export async function openRoute(page, base, route) {
  await page.goto(base + route, { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => !document.body.innerText.includes("Loading toolkit"), null, { timeout: 30000 });
  try {
    await page.waitForFunction(() => !/\bLoading\b/.test(document.body.innerText), null, { timeout: 30000 });
  } catch {
    /* the checks say what they saw */
  }
  return page.evaluate(() => document.body.innerText);
}

/** The nav's entries -- the text of the links and buttons in the header's nav. */
export const navText = (page) =>
  page.evaluate(() => Array.from(document.querySelectorAll("a, button")).map((e) => e.textContent?.trim()).join("|"));

/** The main nav's entries only (`nav[aria-label="Main"]`), each one -- so a
 *  tip or a card that names a module is never read as its tab. */
export const mainNavEntries = (page) =>
  page.evaluate(() =>
    Array.from(document.querySelectorAll('nav[aria-label="Main"] a, nav[aria-label="Main"] button')).map(
      (e) => e.textContent?.trim() ?? "",
    ),
  );

/**
 * The flip with no restart (-- built once, here): with the agent
 * running, set one module flag true through the one writer, reload, see its nav
 * entry; set it false, reload, see it gone. The agent's process is the same one
 * throughout -- the gate is read per request (AGENTS.md, "Off means absent").
 */
export async function flipCase({ browser, stack, check, flag, navLabel, label = flag }) {
  const pid = stack.agent.pid;
  const page = await browser.newPage();
  const navHas = async () => new RegExp(`\\b${navLabel}\\b`).test(await navText(page));
  try {
    await openRoute(page, stack.base, "/");
    check(`flip: the ${navLabel} nav entry is absent before the flip`, !(await navHas()));

    const on = await setFlags(stack.base, { [flag]: true });
    check(`flip: Config -Set features.${label}=true through PUT /api/config succeeds`, on.status === "success", on.error ?? "");
    await openRoute(page, stack.base, "/");
    check(`flip: the ${navLabel} nav entry appears on a reload, no restart`, await navHas(), (await navText(page)).slice(0, 200));

    const off = await setFlags(stack.base, { [flag]: false });
    check(`flip: Config -Set features.${label}=false through PUT /api/config succeeds`, off.status === "success", off.error ?? "");
    await openRoute(page, stack.base, "/");
    check(`flip: the ${navLabel} nav entry is gone on the next reload`, !(await navHas()), (await navText(page)).slice(0, 200));

    check(
      "flip: the agent is the same process throughout",
      stack.agent.exitCode === null && stack.agent.pid === pid,
      `pid ${pid} -> ${stack.agent.pid}, exit ${stack.agent.exitCode}`,
    );
  } finally {
    await page.close();
  }
}

/**
 * Chromium, or the one command that installs it. `npm ci` installs the
 * playwright LIBRARY; the browser BINARY is a machine-level download nothing in
 * this repo runs, so a missing one is answered with the command, not a stack.
 */
export async function launchChromium() {
  try {
    return await chromium.launch();
  } catch (err) {
    const msg = String(err && err.message ? err.message : err);
    if (/Executable doesn't exist|browserType\.launch/i.test(msg)) {
      console.error("FAIL  chromium is not installed for Playwright.");
      console.error("      Run this once, then re-run the smoke:");
      console.error("");
      console.error("        npx playwright install chromium");
      console.error("");
      console.error(`      (${msg.split("\n")[0]})`);
      process.exit(2);
    }
    throw err;
  }
}

/** PASS / FAIL lines and a count of each -- the smoke's own shape. */
export function makeChecker() {
  const state = { failures: 0, checks: 0 };
  const check = (name, ok, detail = "") => {
    state.checks++;
    console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok || !detail ? "" : ` -- ${detail}`}`);
    if (!ok) state.failures++;
  };
  return { check, state };
}

/**
 * Whether a requested URL carries a module's SOURCE -- one of its parts, not
 * its descriptor. Dev serves the file itself (/src/modules/growth/GrowthPage.tsx);
 * a build serves the chunk Vite named after it (/assets/GrowthPage-<hash>.js).
 * The part names are read off the module's folder, so a new page is covered the
 * day it is added. index.tsx and paths.ts ARE the descriptor: the registry reads
 * them with the flag off, and that is the contract.
 */
const WEB_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const modulePartNames = (id) =>
  readdirSync(join(WEB_ROOT, "src", "modules", id))
    .filter((f) => /\.tsx?$/.test(f) && !/\.test\./.test(f) && !/^(index|paths)\./.test(f))
    .map((f) => f.replace(/\.tsx?$/, ""));
export const moduleSourceUrl = (id, url) => {
  const path = new URL(url).pathname;
  if (new RegExp(`/src/modules/${id}/(?!index\\.tsx|paths\\.ts)`).test(path)) return true;
  return modulePartNames(id).some((name) => new RegExp(`/assets/${name}-[\\w-]+\\.js$`).test(path));
};

/** The interpreter the agent is started with: --python=, else the platform's. */
export const defaultPython = () => (process.platform === "win32" ? "python" : "python3");
