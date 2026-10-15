import { useCallback, useSyncExternalStore } from "react";
import { DEFAULT_FACE_ID, FACES } from "../shared/faces";

export const FACE_KEY = "toolkit-face";

const listeners = new Set<() => void>();

// Browser-only by design: this personalizes the ToolKit logo in prompts web,
// which is the only place the Face card exists (in the Lounge). Module-scope
// localStorage is fine here BECAUSE nothing outside that app imports it -- a
// deck figure once did, and the import alone (no browser in the bake script)
// made four decks unbakeable. If something outside web ever needs a face, give
// it a constant rather than reaching for this.
//
// Fine to reach, never fine to throw: ToolKitLogo puts this module in the
// shell, so the module-scope read below runs while the shell is evaluated. A
// browser that refuses storage (a private window with site data blocked, a
// policy, an iframe) THROWS on localStorage access rather than answering null,
// and an unguarded read here blanked the whole web UI. Refused storage
// reads as "nothing stored" -- the default face -- and a choice still holds
// for the session, the shape useSharedPersistedValue has
// (shared/usePersistedState.ts).

/** Never throws. A browser that refuses storage reads as "nothing stored". */
function readStored(): string | null {
  try {
    return localStorage.getItem(FACE_KEY);
  } catch {
    return null;
  }
}

/** Never throws; true when the browser kept it. */
function writeStored(id: string): boolean {
  try {
    localStorage.setItem(FACE_KEY, id);
    return true;
  } catch {
    return false;
  }
}

// The session's choice when the browser would not keep it; lost on reload.
let sessionFaceId: string | null = null;

function readFaceId(): string {
  const v = readStored() ?? sessionFaceId;
  return FACES.some((f) => f.id === v) ? v! : DEFAULT_FACE_ID;
}

let snapshot = { faceId: readFaceId() };

function notify() {
  snapshot = { faceId: readFaceId() };
  listeners.forEach((fn) => fn());
}

window.addEventListener("storage", (e) => {
  if (e.key === FACE_KEY || e.key === null) notify();
});

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

function getSnapshot() {
  return snapshot;
}

export function useFacePref() {
  const { faceId } = useSyncExternalStore(subscribe, getSnapshot);

  const setFaceId = useCallback((id: string) => {
    sessionFaceId = writeStored(id) ? null : id;
    notify();
  }, []);

  return { faceId, setFaceId };
}
