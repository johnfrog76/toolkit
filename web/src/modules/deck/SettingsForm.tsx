import { Label, Radio, RadioGroup, Switch, useId } from "@fluentui/react-components";
import {
  NARRATION_SWITCH_LABEL,
  VOICE_PICKER_TITLE,
  voiceOptionLabel,
} from "./engine/narrationConstants";

// The form inside the viewer's settings sheet (engine/DeckChromeViewer.tsx).
//
// Connected Deck's engine imports a SettingsForm from its host app, one level
// above the engine folder, and this is the Toolkit's: the same props, so the
// engine's bar is carried unchanged, and the Toolkit's own rows. Connected Deck
// renders the same form in a launch page's Settings drawer and reads that
// page's stored preferences; the Toolkit has no launch page and keeps no
// viewing preference, so there is one surface (the sheet), it drives the live
// player only, and there is no hint under a row.
//
// Three rows, in the order they depend on each other:
//   - Mode, Sofa or Audiobook -- only when the host passes onAudiobookChange.
//     Podium is not here: it is chosen before a deck opens, and has its own bar.
//   - Narration, on or off for this viewing -- the same setting as the bar's
//     sound button.
//   - The voice.

/** The two modes the sheet offers, by the name the bar and the docs use. */
export const SHEET_MODES = { sofa: "Sofa", audiobook: "Audiobook" } as const;
type SheetMode = keyof typeof SHEET_MODES;

/** The mode row's label. */
export const MODE_LABEL = "Mode";

export interface SettingsFormProps {
  /** The one surface this form has here: the viewer's bottom sheet. */
  variant?: "sheet";
  /** Is narration on for this viewing (the player's session state). */
  narrationValue?: boolean;
  onNarrationChange?: () => void;
  /** Nothing narrates this deck at all: the rows go dead, not just unchecked. */
  narrationDisabled?: boolean;
  /** Voices with this deck's coverage (voiceCoverage.ts). */
  voices?: readonly { id: string; name: string; available: boolean }[];
  voiceId?: string;
  onVoiceChange?: (id: string) => void;
  /** Whether Audiobook mode is driving this viewing. */
  audiobookValue?: boolean;
  /** Choose Sofa (false) or Audiobook (true). Omitted, there is no mode row. */
  onAudiobookChange?: (next: boolean) => void;
}

export function SettingsForm({
  narrationValue = false,
  onNarrationChange,
  narrationDisabled = false,
  voices = [],
  voiceId,
  onVoiceChange,
  audiobookValue = false,
  onAudiobookChange,
}: SettingsFormProps) {
  const modeLabelId = useId("deck-mode");
  const mode: SheetMode = audiobookValue ? "audiobook" : "sofa";

  const chooseMode = (next: SheetMode) => {
    // Audiobook advances on a clip's END, so choosing it turns this viewing's
    // narration on too -- the listener's own act, as in Connected Deck.
    if (next === "audiobook" && !narrationValue) onNarrationChange?.();
    onAudiobookChange?.(next === "audiobook");
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
      {onAudiobookChange && (
        <div style={{ display: "flex", flexDirection: "column" }}>
          <Label id={modeLabelId}>{MODE_LABEL}</Label>
          <RadioGroup
            aria-labelledby={modeLabelId}
            value={mode}
            onChange={(_, data) => chooseMode(data.value as SheetMode)}
          >
            {(Object.keys(SHEET_MODES) as SheetMode[]).map((m) => (
              <Radio
                key={m}
                value={m}
                label={SHEET_MODES[m]}
                disabled={m === "audiobook" && narrationDisabled}
              />
            ))}
          </RadioGroup>
        </div>
      )}
      <Switch
        checked={narrationValue}
        onChange={() => onNarrationChange?.()}
        disabled={narrationDisabled}
        label={NARRATION_SWITCH_LABEL}
      />
      {/* No visible label: the sheet's title and the Narration row above say
          what this is; the group keeps the name for assistive tech. */}
      <RadioGroup
        aria-label={VOICE_PICKER_TITLE}
        value={voiceId}
        disabled={narrationDisabled}
        onChange={(_, data) => onVoiceChange?.(data.value)}
      >
        {voices.map((v) => (
          <Radio
            key={v.id}
            value={v.id}
            label={voiceOptionLabel(v.name, v.available)}
            disabled={!v.available}
          />
        ))}
      </RadioGroup>
    </div>
  );
}
