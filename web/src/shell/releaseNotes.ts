/**
 * What's new: which release notes the dialog shows, and the browser's mark of
 * the version it last showed. Pure but for the mark; the dialog is
 * `WhatsNewDialog.tsx`, the hook that decides when it opens is `WhatsNew.tsx`.
 *
 * The mark is one version string in this browser's localStorage. It is a
 * per-viewer convenience that can be empty, refused or throwing (a private
 * window, site data off), so every read and write is wrapped and a refusal
 * falls back to this page's memory: the dialog then holds for the page's
 * life instead of forever, and nothing breaks.
 */
import { findRelease } from "./changelogParse";
import type { ChangelogRelease } from "./changelogParse";

/** The browser's key for the last version whose notes were shown on their own. */
export const WHATS_NEW_SEEN_KEY = "p20.whatsNew.seen";

// What holds when storage will not.
let memory: string | null = null;

/** The version last shown in this browser, or null when none was. Never throws. */
export function readSeenVersion(): string | null {
  try {
    const raw = window.localStorage?.getItem(WHATS_NEW_SEEN_KEY);
    if (raw) return raw;
  } catch {
    // Refused or unreadable: this page's memory answers.
  }
  return memory;
}

/** Remember the version as shown. Never throws. */
export function writeSeenVersion(version: string): void {
  memory = version;
  try {
    window.localStorage?.setItem(WHATS_NEW_SEEN_KEY, version);
  } catch {
    // Private mode / storage disabled / quota: this page's memory holds it.
  }
}

/** Forget this page's memory -- for the tests. */
export function resetWhatsNewMemory(): void {
  memory = null;
}

/**
 * The sections to show on their own when the web UI opens on `running`,
 * newest first, given the version last shown (null: none ever).
 *
 *  - the running version has no released section (an unreleased build): none;
 *  - it was already shown, or a newer one was: none;
 *  - nothing was shown before, or the last one shown is not in the file: the
 *    running section alone;
 *  - otherwise every section from the running one down to, not including, the
 *    last one shown -- the versions skipped in between.
 */
export function onLoadReleases(
  releases: ChangelogRelease[],
  running: string,
  lastSeen: string | null,
): ChangelogRelease[] {
  const at = releases.findIndex((r) => r.version === running);
  if (at < 0) return [];
  if (lastSeen === null) return [releases[at]];
  const seenAt = releases.findIndex((r) => r.version === lastSeen);
  if (seenAt < 0) return [releases[at]];
  return seenAt > at ? releases.slice(at, seenAt) : [];
}

/**
 * What the menu item shows: the running version's section, or on an
 * unreleased build the newest released one. Empty only when the file has none.
 */
export function menuReleases(releases: ChangelogRelease[], running: string): ChangelogRelease[] {
  const own = findRelease(releases, running);
  if (own) return [own];
  return releases.length > 0 ? [releases[0]] : [];
}
