import fs from "node:fs";
import path from "node:path";

import { defineConfig } from "vite";
import type { Plugin } from "vite";
import react from "@vitejs/plugin-react";

// With its extension, as Vite's native config loader will require.

// import.meta.dirname, not __dirname: Vite 8 warns that the CommonJS name will
// not exist once its native config loader becomes the default.
const PACKAGE_ROOT = path.resolve(import.meta.dirname, "..");
const readJson = (name: string) =>
  JSON.parse(fs.readFileSync(path.join(PACKAGE_ROOT, name), "utf8"));

// The contract file, for the name of the one environment variable this config
// reads (env.agentPort). The value is configuration; the NAME is what the
// launcher that sets it and this file that reads it have to agree on.
const consts = readJson("consts.json");

/**
 * Where /api is proxied to: the agent's port.
 *
 * The launcher (`tkWeb -Dev`, Scripts/Start-Web.ps1) resolves `web.agentPort`
 * from the merged config and exports it under the contract's variable name
 * before Vite starts, so that wins. `npm run dev` typed by hand has no
 * launcher, so the same two files are read here in the same order -- the
 * shipped default, patched by the machine's -- and the answer agrees with
 * `tkAgent -Status`. Nothing here types a port number: this used to
 * say 4100, and `tkAgent -Port <n>` produced a dev server that could not reach
 * its agent.
 *
 * CALLED ONLY WHEN VITE IS SERVING. A proxy is the dev server's; the production
 * image has nginx, which is handed the same port at CONTAINER START by envsubst
 * (web/nginx.conf.template, docker-compose.yml's `environment:`). The image's
 * build context is the package root but copies only consts.json and web/, and
 * compose passes the port as `environment:` rather than `args:` -- so inside
 * the builder neither config file nor the variable exists, and calling this
 * unconditionally threw where its answer was never going to be used.
 *
 */
function agentPort(): number {
  const envName: string = consts.env.agentPort;
  const fromEnv = process.env[envName];
  if (fromEnv && /^\d+$/.test(fromEnv)) return Number(fromEnv);
  let port = 0;
  for (const name of ["config.default.json", "config.local.json"]) {
    try {
      const value = readJson(name)?.web?.agentPort;
      if (value) port = Number(value);
    } catch {
      // Absent or unreadable: the other file decides.
    }
  }
  if (!port) {
    throw new Error(
      `web.agentPort is not set in config.default.json or config.local.json, and ${envName} ` +
        "is not in the environment -- nowhere to proxy /api to.",
    );
  }
  return port;
}

/**
 * The landing page's build: `vite build --mode landing` (`npm run build:landing`).
 *
 * The page is the web half's second entry, web/landing.html, and it is built on
 * its own rather than beside the app because the two differ in the three things
 * a build is: where it is served and what it emits. It is served from a GitHub
 * Pages subpath, so its asset addresses are relative, and it emits a site,
 * dist/landing/, whose page is index.html and which carries none of public/.
 * Its words are its own (src/landing/copy.ts); nothing is read at build.
 */
const LANDING_MODE = "landing";
const LANDING_OUT = "dist/landing";

/** Pages serves a folder's index.html, so the entry's page is renamed once written. */
function landingAsIndex(): Plugin {
  return {
    name: "landing-as-index",
    apply: "build",
    closeBundle() {
      const out = path.resolve(import.meta.dirname, LANDING_OUT);
      const page = path.join(out, "landing.html");
      if (fs.existsSync(page)) fs.renameSync(page, path.join(out, "index.html"));
    },
  };
}

/** What the landing mode changes; nothing at all in any other mode. */
function landingOptions() {
  return {
    base: "./",
    publicDir: false as const,
    build: {
      outDir: LANDING_OUT,
      emptyOutDir: true,
      rollupOptions: { input: path.resolve(import.meta.dirname, "landing.html") },
    },
  };
}

// A FUNCTION, so `command` and `mode` are available: `serve` for `vite dev`
// and `vite preview`, `build` for `vite build`. The proxy block is what makes
// the difference -- see agentPort(). The landing mode serves no agent, so it
// never asks for one either.
export default defineConfig(({ command, mode }) => ({
  plugins: mode === LANDING_MODE ? [react(), landingAsIndex()] : [react()],
  ...(mode === LANDING_MODE ? landingOptions() : { build: { outDir: "dist/client" } }),
  resolve: {
    alias: {
      // The package's contract file, one level above web/. An alias rather
      // than a "../../../consts.json" climb, so the depth of the importing
      // file stops mattering. Declared in three places -- here, tsconfig's
      // `paths`, and jest's `moduleNameMapper` -- because each resolver has
      // its own; web/src/shell/consts.ts is the one module that imports it.
      "@consts": path.join(PACKAGE_ROOT, "consts.json"),
      // The settings-by-workflow entries, the same file the CLI reads (D-W8).
      "@workflows": path.join(PACKAGE_ROOT, "Config", "settings-workflows.json"),
    },
  },
  server: {
    // Start-Web.ps1 and Show-ConfigHelp.ps1 read this number back out of the
    // file (`port:\s*(\d+)`, first match wins) -- one to know which port to
    // sweep for an orphaned dev server, the other to resolve `{devPort}` in a
    // help line. Keep it literal, and keep it the only `port:` digits here.
    port: 5174,
    ...(command === "serve" && mode !== LANDING_MODE
      ? {
          proxy: {
            "/api": {
              target: `http://localhost:${agentPort()}`,
              changeOrigin: true,
            },
          },
        }
      : {}),
  },
}));
