/**
 * The packaged `CHANGELOG.md`, parsed -- the one module that reads it.
 *
 * Like `consts.json` it sits at the PACKAGE root, above `web/`, and is read at
 * BUILD time through an alias (`@changelog`, in `vite.config.ts`, `jest.config.mjs`
 * and, as an ambient module, `vite-env.d.ts`): no fetch, no agent, and the build
 * image copies the file in (`Dockerfile`). It is text of some size and growing, so
 * nothing imports this module statically: `WhatsNew.tsx` loads it with `import()`
 * only when a version has not been shown or the menu asks, and a steady-state
 * page load never fetches it.
 */
import changelogText from "@changelog";
import { parseChangelog } from "./changelogParse";

/** Every released section, newest first. */
export const RELEASES = parseChangelog(changelogText);
