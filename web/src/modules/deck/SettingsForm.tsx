import { Label, Radio, RadioGroup, Switch, useId } from "@fluentui/react-components";
import {
  NARRATION_SWITCH_LABEL,
  VOICE_PICKER_TITLE,
  voiceOptionLabel,
} from "./engine/narrationConstants";

// The form inside the viewer's sheet (engine/DeckChromeViewer.tsx), which the
// engine imports from one level above its own folder, as Connected Deck's does.
// The same props shape as Connected Deck's form, so the bar is carried as it
// is; the rows, their order and their words are this product's.
//
// Three rows, in the order they depend on each other, and no hint under any of
// them -- the controls already say what they are:
//   - Narration, on or off: the same setting as the bar's sound button.
//   - Mode, Paging or Audiobook, side by side -- only when the host passes
//     onAudiobookChange. Dead while narration is off: Audiobook turns the slide
//     when narration ends, so a silent deck has nothing to offer it. "Paging"
//     because that is what the viewer does in it: turns the slides by hand.
//   - The voice.
// Podium is not here: it is chosen before a deck opens, and has its own bar.

/** The two modes the sheet offers, by the words on screen. */
export const SHEET_MODES = { paging: "Paging", audiobook: "Audiobook" } as const;
type SheetMode = keyof typeof SHEET_MODES;

/** The mode row's label. */
export const MODE_LABEL = "Mode";

export interface SettingsFormProps {
  /** The one surface this form has here: the viewer's bottom sheet. */
  variant?: "sheet";
  /** Is the sound on for this viewing (narration, or not muted). */
  narrationValue?: boolean;
  onNarrationChange?: () => void;
  /** Nothing narrates this deck at all: the rows go dead, not just unchecked. */
  narrationDisabled?: boolean;
  /** The mode row is dead (narration is off, or nothing narrates the deck). */
  audiobookDisabled?: boolean;
  /** Voices with this deck's coverage (voiceCoverage.ts). */
  voices?: readonly { id: string; name: string; available: boolean }[];
  voiceId?: string;
  onVoiceChange?: (id: string) => void;
  /** Whether Audiobook is driving this viewing. */
  audiobookValue?: boolean;
  /** Choose Paging (false) or Audiobook (true). Omitted, there is no mode row. */
  onAudiobookChange?: (next: boolean) => void;
}

export function SettingsForm({
  narrationValue = false,
  onNarrationChange,
  narrationDisabled = false,
  audiobookDisabled = false,
  voices = [],
  voiceId,
  onVoiceChange,
  audiobookValue = false,
  onAudiobookChange,
}: SettingsFormProps) {
  const modeLabelId = useId("deck-mode");
  const mode: SheetMode = audiobookValue ? "audiobook" : "paging";

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
      <Switch
        checked={narrationValue}
        onChange={() => onNarrationChange?.()}
        disabled={narrationDisabled}
        label={NARRATION_SWITCH_LABEL}
      />
      {onAudiobookChange && (
        <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
          <Label id={modeLabelId}>{MODE_LABEL}</Label>
          <RadioGroup
            aria-labelledby={modeLabelId}
            layout="horizontal"
            value={mode}
            disabled={audiobookDisabled}
            onChange={(_, data) => onAudiobookChange(data.value === "audiobook")}
          >
            {(Object.keys(SHEET_MODES) as SheetMode[]).map((m) => (
              <Radio key={m} value={m} label={SHEET_MODES[m]} />
            ))}
          </RadioGroup>
        </div>
      )}
      {/* No visible label: the sheet's title says Voice; the group keeps the
          name for assistive tech. */}
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
