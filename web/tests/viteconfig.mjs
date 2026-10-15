/**
 * The build contract of web/vite.config.ts -- five assertions, no browser and
 * no servers, so this runs anywhere `npm ci` has.
 *
 * It exists because of one defect: the dev server's `/api` proxy target is
 * resolved from `web.agentPort`, and resolving it was unconditional, so `vite
 * build` demanded a value it was never going to use. Inside the production
 * image there is no value to find -- the build context copies consts.json and
 * web/, not config.default.json, and docker-compose passes the port as
 * `environment:` (read by nginx at container start) rather than `args:` -- so
 * the image stopped building the day the port became configurable. Nothing
 * caught it because every suite here exercises the SERVE path: jest never loads
 * this file, and the smoke test drives a dev server.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { resolveConfig } from "vite";

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_FILE = path.join(WEB_ROOT, "vite.config.ts");
const consts = JSON.parse(
  fs.readFileSync(path.join(WEB_ROOT, "..", "consts.json"), "utf8"),
);

let failures = 0;
const check = (label, ok, detail) => {
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${label}`);
  if (!ok) {
    failures += 1;
    if (detail !== undefined) console.log(`        ${detail}`);
  }
};

// resolveConfig bundles the file afresh per call, so the environment set just
// before one is the environment that call reads.
const load = (command) =>
  resolveConfig({ configFile: CONFIG_FILE, root: WEB_ROOT }, command);

console.log("-- vite.config.ts: what each command needs --------------------");

const built = await load("build");
check(
  "a build declares no /api proxy, so it never asks for the agent's port",
  built.server?.proxy?.["/api"] === undefined,
  JSON.stringify(built.server?.proxy),
);

const envName = consts.env.agentPort;
const saved = process.env[envName];
delete process.env[envName];
const served = await load("serve");
check(
  "serving proxies /api at the port the config files resolve to",
  /^http:\/\/localhost:\d+$/.test(served.server?.proxy?.["/api"]?.target ?? ""),
  served.server?.proxy?.["/api"]?.target,
);

process.env[envName] = "4321";
const overridden = await load("serve");
check(
  `serving prefers ${envName} over the files -- the launcher's channel`,
  overridden.server?.proxy?.["/api"]?.target === "http://localhost:4321",
  overridden.server?.proxy?.["/api"]?.target,
);
if (saved === undefined) delete process.env[envName];
else process.env[envName] = saved;

// Start-Web.ps1 sweeps this port for an orphan and Show-ConfigHelp.ps1 expands
// {devPort} with it, both by taking the FIRST `port:\s*(\d+)` in the file.
// Neither imports anything; a port moved into a constant would read as absent
// and both would silently fall back to a hardcoded 5174.
const source = fs.readFileSync(CONFIG_FILE, "utf8");
const firstPort = /port:\s*(\d+)/.exec(source);
check(
  "the dev port is a literal the PowerShell readers can still find",
  firstPort !== null && Number(firstPort[1]) === served.server.port,
  `file says ${firstPort?.[1]}, vite resolved ${served.server.port}`,
);

// 5. Every alias that points OUTSIDE web/ is copied into the image at the path
// it resolves to. The build context is the package root and the Dockerfile
// copies only what it names; the @workflows alias (Config/settings-workflows.json)
// broke the image the day it landed, because the Dockerfile still named only
// consts.json and web/ -- a build that passed on every developer machine.
const PACKAGE_ROOT = path.join(WEB_ROOT, "..");
const dockerfile = fs.readFileSync(path.join(WEB_ROOT, "Dockerfile"), "utf8");
const outside = (built.resolve?.alias ?? [])
  .map((a) => a.replacement)
  .filter((r) => typeof r === "string" && path.isAbsolute(r) && !r.startsWith(WEB_ROOT + path.sep) && r.startsWith(PACKAGE_ROOT + path.sep))
  .map((r) => path.relative(PACKAGE_ROOT, r).split(path.sep).join("/"));
const missing = outside.filter((rel) => !dockerfile.includes(`COPY ${rel} /${rel}`));
check(
  "every alias outside web/ is copied into the image at the path it resolves to",
  outside.length > 0 && missing.length === 0,
  missing.length ? `Dockerfile lacks: ${missing.map((m) => `COPY ${m} /${m}`).join("; ")}` : `aliases: ${outside.join(", ")}`,
);

console.log(
  failures === 0
    ? "vite.config.ts: 5 checks, clean"
    : `vite.config.ts: ${failures} of 5 checks FAILED`,
);
process.exit(failures === 0 ? 0 : 1);
