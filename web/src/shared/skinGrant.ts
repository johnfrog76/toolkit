/**
 * The skin GRANT -- the one browser preference two surfaces share (D-L11;
 * docs/modules/lounge.md, "The Skins dialog, and the grant"): the Lounge writes it, the shell wears it,
 * and the wearing must follow the writing LIVE -- "apply to toolkit" that
 * did nothing until a reload would be a button that lies.
 *
 * usePersistedState is deliberately not a sync layer (its own words), so
 * this file is the one place that owns the key, the shape and the change
 * event, with a useSyncExternalStore hook over localStorage plus the
 * 'storage' event (another tab granting) and a local CustomEvent (this tab
 * granting). Both the Lounge and shared/GrantedSkin read through here;
 * nobody else touches the key.
 */
import { useMemo, useSyncExternalStore } from "react";

export const SKIN_GRANT_KEY = "toolkit-skin-grant";
const CHANGE_EVENT = "p20-skin-grant-changed";

export interface SkinGrant {
  /** WHICH skin is worn -- the key into themeList's SKIN_THEMES, so the
   *  grant dresses the whole product (FULL SKIN: the Fluent theme is the
   *  skin's while worn, locked to it). */
  skinId: "temple" | "tank";
  /** The self-contained, zero-JavaScript document the shell mounts. */
  src: string;
  /** The scene's caption -- the iframe's title, for whoever asks. */
  caption: string;
  /** The scene's slow clocks RUN (spec D-L19: Animate is a switch, default
   *  off). Absent means off: the wearer loads `src#still`, and every clock in
   *  the document stops at its resting pose (the body:target contract every
   *  scene carries). */
  animate?: boolean;
  /** The shape before D-L19 said the opposite thing: `still` frozen it. An
   *  older grant carrying it reads as its inverse (isAnimated); a new grant
   *  never writes it. */
  still?: boolean;
}

/** Whether a worn grant runs its clocks. `animate` decides; an older grant
 *  that only said `still` reads as its inverse; one that said neither is
 *  off, the D-L19 default. */
export function isAnimated(grant: SkinGrant): boolean {
  if (typeof grant.animate === "boolean") return grant.animate;
  if (typeof grant.still === "boolean") return !grant.still;
  return false;
}

function readRaw(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage?.getItem(SKIN_GRANT_KEY) ?? null;
  } catch {
    return null; // a browser that refuses storage reads as "no grant"
  }
}

export function parseSkinGrant(raw: string | null): SkinGrant | null {
  if (!raw) return null;
  try {
    const v: unknown = JSON.parse(raw);
    const g = v as SkinGrant;
    if (
      v &&
      typeof v === "object" &&
      (g.skinId === "temple" || g.skinId === "tank") &&
      typeof g.src === "string" &&
      typeof g.caption === "string"
    ) {
      return g;
    }
  } catch {
    /* an unreadable grant is no grant */
  }
  return null; // a grant from an older shape reads as none, never as a crash
}

/** Write (or, with null, remove) the grant, and tell this tab's wearers. */
export function writeSkinGrant(grant: SkinGrant | null): void {
  if (typeof window === "undefined") return;
  try {
    if (grant) window.localStorage?.setItem(SKIN_GRANT_KEY, JSON.stringify(grant));
    else window.localStorage?.removeItem(SKIN_GRANT_KEY);
  } catch {
    // Private mode / storage disabled: wearers re-read and find nothing, so
    // the grant simply does not take -- degraded, never crashed.
  }
  window.dispatchEvent(new CustomEvent(CHANGE_EVENT));
}

function subscribe(onChange: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  window.addEventListener(CHANGE_EVENT, onChange);
  window.addEventListener("storage", onChange);
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onChange);
  };
}

/** The current grant, live: re-renders on this tab's writes and other tabs'. */
export function useSkinGrant(): SkinGrant | null {
  // The snapshot is the RAW string (stable equality); the parse is derived.
  const raw = useSyncExternalStore(subscribe, readRaw, () => null);
  return useMemo(() => parseSkinGrant(raw), [raw]);
}
