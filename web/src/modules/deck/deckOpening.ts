import { usePersistedFlag } from "../../shared/usePersistedState";
import { DECK_AUDIOBOOK_STORAGE_KEY, DECK_PODIUM_STORAGE_KEY } from "./engine/narrationConstants";
import { SHEET_MODES } from "./SettingsForm";

// How a listed deck opens, per browser: the one place the deck's page (its
// settings dialog) and the player's host (DeckHost.tsx) read it from, so the
// two cannot disagree about what was chosen.
//
// Two flags, not one value, because Paging-or-Audiobook was already a flag the
// viewer's sheet writes (DECK_AUDIOBOOK_STORAGE_KEY) and must keep reading. The
// Podium flag sits beside it. A phone never gets Podium -- the engine's rule --
// so a remembered Podium opens on the viewer's bar there.

/** The three ways a listed deck can open, by the words on screen. */
export const OPENING_MODES = { ...SHEET_MODES, podium: "Podium" } as const;
export type OpeningMode = keyof typeof OPENING_MODES;

export function useDeckOpening(): {
  mode: OpeningMode;
  setMode: (next: OpeningMode) => void;
  audiobook: boolean;
  setAudiobook: (next: boolean) => void;
  podium: boolean;
} {
  const { value: audiobook, setValue: setAudiobook } = usePersistedFlag(DECK_AUDIOBOOK_STORAGE_KEY);
  const { value: podium, setValue: setPodium } = usePersistedFlag(DECK_PODIUM_STORAGE_KEY);
  const mode: OpeningMode = podium ? "podium" : audiobook ? "audiobook" : "paging";
  const setMode = (next: OpeningMode) => {
    setPodium(next === "podium");
    // Podium leaves the viewer's choice as it was, so a deck played on the
    // viewer's bar later still opens the way the sheet last left it.
    if (next !== "podium") setAudiobook(next === "audiobook");
  };
  return { mode, setMode, audiobook, setAudiobook, podium };
}

/**
 * Whether this viewing is the podium. The address wins for one viewing --
 * `?present=1` and `?present=0` -- and otherwise the remembered choice does.
 */
export function isPodiumViewing(present: string | null, remembered: boolean): boolean {
  if (present === "1") return true;
  if (present === "0") return false;
  return remembered;
}
