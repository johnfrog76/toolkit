import { useCallback, useSyncExternalStore } from "react";
import { FIRST_DARK, FIRST_LIGHT, themeById } from "../shell/themeList";
import type { ToolkitTheme } from "../shell/themeList";

export type Theme = "dark" | "light";

const THEME_KEY = "toolkit-theme";

// ── Shared store (singleton) ────────────────────────────────────────────────

const listeners = new Set<() => void>();

// This module is imported OUTSIDE a browser. The voice-bake script pulls a
// deck's whole import graph into vite-node to read its Say text, and a
// connected deck that embeds a real web component -- git-weather-forecast does
// exactly that, which is the point of the format -- drags the theme store in
// with it. Unguarded, the module-scope reads below threw at import time and the
// deck couldn't be baked at all.
//
// Unlike the Face picker (see useFacePref), the fix here is a guard rather than
// cutting the dependency: theme is real app infrastructure and the deck's use
// of the live component is deliberate. Outside a browser we answer the first
// dark theme, which is what the deck stage is anyway. It is also why this file
// imports themeList (plain data) and never shell/theme (Fluent).
const hasDom = typeof window !== "undefined";

function osPrefersDark(): boolean {
  if (!hasDom) return true;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

// The session's choice when the browser would not keep it (a private window
// with site data blocked, a policy, an iframe): memory is the session's truth
// and storage only the persistence, the shape useSharedPersistedValue has
// (shared/usePersistedState.ts). Lost on reload. Cleared whenever a write is
// kept, so storage stays the answer wherever there is storage.
let sessionThemeId: string | null = null;

// A theme is CHOSEN, by name; there is no "auto". The one time the system is
// asked is for a browser that has never chosen -- and it keeps being asked
// until someone does, so a first visit at night is not a white page.
function readTheme(): ToolkitTheme {
  let stored: string | null = null;
  if (hasDom) {
    try {
      stored = localStorage.getItem(THEME_KEY);
    } catch {
      /* a private window: the session's choice, else the system's answer */
    }
  }
  return (
    themeById(stored) ??
    themeById(sessionThemeId) ??
    themeById(osPrefersDark() ? FIRST_DARK : FIRST_LIGHT)!
  );
}

/** Never throws; true when the browser kept it. */
function writeTheme(id: string): boolean {
  try {
    localStorage.setItem(THEME_KEY, id);
    return true;
  } catch {
    return false;
  }
}

/** Snapshot object — recreated on every change so useSyncExternalStore detects it */
let snapshot = { active: readTheme() };

function notify() {
  snapshot = { active: readTheme() };
  listeners.forEach((fn) => fn());
}

if (hasDom) {
  // Only matters until a theme is chosen -- see readTheme.
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", notify);

  // React to cross-tab localStorage changes
  window.addEventListener("storage", (e) => {
    if (e.key === THEME_KEY || e.key === null) notify();
  });
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

function getSnapshot() {
  return snapshot;
}

// ── Hook ────────────────────────────────────────────────────────────────────

/**
 * Single source of truth for theme state. All consumers share one store.
 *
 * - `theme`      — "dark" | "light": what a chart or a face needs to know
 * - `active`     — the named theme in force
 * - `setThemeId` — choose one. Applies at once, everywhere: choosing IS the
 *                  preview, and there is nothing to save -- it is this
 *                  browser's preference, like the Face, and never config.
 */
export function useCurrentTheme() {
  const { active } = useSyncExternalStore(subscribe, getSnapshot);

  const setThemeId = useCallback((id: string) => {
    if (!themeById(id)) return;
    // A refused write keeps the choice for the session (sessionThemeId), so
    // the re-read in notify() answers it rather than the default.
    sessionThemeId = writeTheme(id) ? null : id;
    notify();
  }, []);

  return { theme: active.mode as Theme, active, setThemeId };
}
