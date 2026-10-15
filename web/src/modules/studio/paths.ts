/** This module's route paths, in one place (see communication/paths.ts for why). */
export const STUDIO_HOME = "/studio";

/** How many rows each Studio card shows a page: the Foyer, Hub Designs and
 *  Prompts page alike, the shared pager in the foot's centre. */
export const STUDIO_PAGE_SIZE = 5;

export const ROUTES = {
  home: STUDIO_HOME,
  /** One hub design's reading room: a bare note name (the live note, as the
   *  address always read), or the hub path -- design/archive/old.md,
   *  spec/x.spec.md (design lifecycle L2). The splat carries the slashes. */
  note: `${STUDIO_HOME}/design/*`,
  /** One agentic prompt's reading room: a shipped prompt's name, or the
   *  `ref` the agent gives one of yours (yours/<name>). The splat carries it. */
  prompt: `${STUDIO_HOME}/prompts/*`,
} as const;

/** The reading room's address for one hub design: a live note's name, or a
 *  hub-relative path into one of the four folders. */
export function notePath(nameOrPath: string): string {
  return `${STUDIO_HOME}/design/${nameOrPath.split("/").map(encodeURIComponent).join("/")}`;
}

/** The reading room's address for one prompt, by the `ref` its row carries. */
export function promptPath(ref: string): string {
  return `${STUDIO_HOME}/prompts/${ref.split("/").map(encodeURIComponent).join("/")}`;
}
