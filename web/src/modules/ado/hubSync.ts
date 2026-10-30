// The words for the hub's sync state -- one reader for the System page's
// store-sync row and the foot line on the cards that write into the hub, so the
// two can never say the same state two ways (docs/CONFIGURATION.md, "Syncing the
// hub from the web app").
//
// The agent decides everything (agent/core/hub_sync.py); this only phrases it.
// The rule the words keep: `behind` is never shown without the time it was
// read, and before the first fetch the answer is "not checked yet" -- never
// "in step", which only a fetch can say.

import { DateTime } from "luxon";
import type { HubSync } from "../../shell/api";

/** HH:MM on this machine's clock, from the agent's ISO time. */
export function checkedTime(iso: string): string {
  const t = DateTime.fromISO(iso);
  return t.isValid ? t.toLocal().toFormat("HH:mm") : iso;
}

/** What a hub under storeSync none is told, in place of a button and numbers. */
export const OFF_WORDS =
  "The hub syncs by whatever carries its folder -- a synced drive, a share. There is nothing here to push or pull.";

export interface HubSyncWords {
  /** The parts, in order: the ahead half, then the behind half. */
  parts: string[];
  /** Fully in step, and a fetch has said so. The foot line draws nothing. */
  inStep: boolean;
  /** Something is wrong to read -- a failed check or a local read that failed. */
  warn: boolean;
}

/**
 * The state as words. Null under any storeSync but git: there is nothing to say
 * beyond the setting itself.
 */
export function hubSyncWords(sync: HubSync | undefined | null): HubSyncWords | null {
  if (!sync || sync.state !== "on") return null;
  if (sync.error) return { parts: [sync.error], inStep: false, warn: true };

  const parts: string[] = [];
  const ahead = sync.ahead ?? 0;
  if (ahead > 0) parts.push(`ahead by ${ahead}`);

  let inStep = false;
  if (sync.checking) {
    parts.push("checking the remote...");
  } else if (!sync.checkedAt) {
    parts.push(
      sync.checkFailed ? `check failed: ${sync.checkFailed}` : "not checked against the remote yet",
    );
  } else {
    const at = checkedTime(sync.checkedAt);
    const behind = sync.behind ?? 0;
    if (sync.checkFailed) {
      parts.push(
        behind > 0
          ? `behind by ${behind}, last checked ${at}; the latest check failed: ${sync.checkFailed}`
          : `check failed, last checked ${at}: ${sync.checkFailed}`,
      );
    } else if (behind > 0) {
      parts.push(`behind by ${behind}, checked ${at}`);
    } else if (ahead > 0) {
      parts.push(`not behind, checked ${at}`);
    } else {
      parts.push(`in step, checked ${at}`);
      inStep = true;
    }
  }
  return { parts, inStep, warn: Boolean(sync.checkFailed) };
}
