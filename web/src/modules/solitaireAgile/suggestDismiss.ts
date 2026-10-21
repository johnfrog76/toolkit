// The suggestion's dismiss (D-AR8; docs/modules/solitaire-agile.md, "The
// suggestion: one next move, derived"): per SURFACE, per ITEM, per SESSION, kept
// in this browser's localStorage as a per-viewer convenience. Nothing reaches the
// agent or the CLI -- the CLI has no dismiss (a line in a terminal is already gone).
//
// Per session: a dismissal lasts while this tab's session does. The session is an
// id in sessionStorage; the localStorage entry carries the id it was written
// under, and an entry from another session reads as nothing dismissed.
//
// Storage can be empty, refused or throwing (a private window, site data off): every
// read and write is wrapped, and a refusal falls back to this page's memory, so the
// line still draws and a dismiss still holds until the page goes.

/** The browser's key for the dismissed refs, all surfaces. */
export const DISMISS_KEY = "p20.solitaireAgile.suggest.dismissed";
/** This tab's session id, in sessionStorage. */
export const SESSION_KEY = "p20.solitaireAgile.suggest.session";
/** The surfaces that show a suggestion; the chair's line is the first (AR-3). */
export const SURFACE_CHAIR = "chair";

type Stored = { session: string; surfaces: Record<string, string[]> };

// What holds when storage will not: this page's memory.
let memorySession = "";
let memory: Stored | null = null;

function newSessionId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** This tab's session id: sessionStorage's, else one for this page's life. */
export function sessionId(): string {
  try {
    const have = window.sessionStorage?.getItem(SESSION_KEY);
    if (have) return have;
    const made = memorySession || newSessionId();
    window.sessionStorage?.setItem(SESSION_KEY, made);
    memorySession = made;
    return made;
  } catch {
    if (!memorySession) memorySession = newSessionId();
    return memorySession;
  }
}

function read(): Stored {
  const session = sessionId();
  let parsed: Stored | null = null;
  try {
    const raw = window.localStorage?.getItem(DISMISS_KEY);
    parsed = raw ? (JSON.parse(raw) as Stored) : memory;
  } catch {
    parsed = memory;
  }
  if (!parsed || parsed.session !== session || typeof parsed.surfaces !== "object" || !parsed.surfaces)
    return { session, surfaces: {} };
  return parsed;
}

/** The refs dismissed on a surface in this session. Never throws. */
export function dismissedRefs(surface: string): string[] {
  const list = read().surfaces[surface];
  return Array.isArray(list) ? list.filter((r) => typeof r === "string") : [];
}

/** Dismiss one ref on one surface for this session. Never throws. */
export function dismissRef(surface: string, ref: string): string[] {
  const stored = read();
  const list = Array.from(new Set([...(stored.surfaces[surface] ?? []), ref]));
  const next: Stored = { session: stored.session, surfaces: { ...stored.surfaces, [surface]: list } };
  memory = next;
  try {
    window.localStorage?.setItem(DISMISS_KEY, JSON.stringify(next));
  } catch {
    // Private mode / storage disabled / quota: this page's memory holds it.
  }
  return list;
}

/** Forget this page's memory -- for the tests. */
export function resetDismissMemory(): void {
  memory = null;
  memorySession = "";
}
