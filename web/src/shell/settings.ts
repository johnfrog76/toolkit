import { createContext, useContext, useSyncExternalStore } from "react";

// The two things a settings SECTION needs from the drawer that hosts it, and
// the one thing the shell needs back. A section may come from a module (the
// registry's `settingsSections`), and a module may import from the shell --
// never the other way round -- so both directions go through this file.

// ── The footer outlet ────────────────────────────────────────────────────────
// The drawer's body scrolls; its foot does not. A section that batches edits
// portals its Save / Discard and its feedback into this node, so they stay in
// reach however long the list above them grows. Null while the drawer is
// closed, or before its footer has mounted.
export const SettingsFooterContext = createContext<HTMLElement | null>(null);

export function useSettingsFooter(): HTMLElement | null {
  return useContext(SettingsFooterContext);
}

// ── Unsaved edits ────────────────────────────────────────────────────────────
// The wasteland's drawer closes freely because its switches apply at once:
// "there's nothing here to lose by dismissing". A batched form is different. A
// section keeps its own drafts OUTSIDE its component so a close cannot lose
// them, and reports how many it is holding here -- which is all the shell
// needs to put a dot on the avatar. An instant setting (Face) never reports:
// a face change is never "unsaved".
const counts = new Map<string, number>();
const listeners = new Set<() => void>();
let total = 0;

export function reportUnsaved(sectionId: string, count: number): void {
  if ((counts.get(sectionId) ?? 0) === count) return;
  if (count > 0) counts.set(sectionId, count);
  else counts.delete(sectionId);
  total = 0;
  counts.forEach((n) => {
    total += n;
  });
  listeners.forEach((fn) => fn());
}

function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** How many edits, across every section, are waiting on a Save. */
export function useUnsavedTotal(): number {
  return useSyncExternalStore(
    subscribe,
    () => total,
    () => 0,
  );
}
