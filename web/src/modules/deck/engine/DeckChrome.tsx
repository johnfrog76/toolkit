import { useState } from "react";
import {
  Button,
  Dropdown,
  Option,
  tokens,
  OverlayDrawer,
  DrawerHeader,
  DrawerHeaderTitle,
  DrawerBody,
  RadioGroup,
  Radio,
  Switch,
} from "@fluentui/react-components";
import {
  ChevronLeftRegular,
  ChevronRightRegular,
  DismissRegular,
  SettingsRegular,
  Speaker0Regular,
  Speaker2Filled,
  SpeakerMuteRegular,
  SpeakerOffRegular,
} from "@fluentui/react-icons";
import type { Slide } from "../decks/types";
import type { VoiceAvailability } from "./voiceCoverage";
import { SuitcaseTransport } from "./SuitcaseTransport";
import {
  MUTE_NARRATION_LABEL,
  NO_NARRATION_TITLE,
  UNMUTE_NARRATION_LABEL,
  VOICE_PICKER_TITLE,
  voiceOptionLabel,
} from "./narrationConstants";

const NAV_BG = "#060710";
const BORDER = "#1e2030";

/**
 * In-player narration controls state (a play/pause toggle + voice picker),
 * shown when the host wires narration (CSS Wasteland's baked audio). Omitted on
 * web, which narrates in the notes popout instead.
 */
export interface NarrationControls {
  /** Does the CURRENT slide have a clip in the current voice? Gates the toggle. */
  available: boolean;
  /** Is a clip actually sounding right now? (swaps the icon). */
  playing: boolean;
  /** Is narration mode on? (auto-play as slides arrive). */
  enabled: boolean;
  toggle: () => void;
  /**
   * Transport hold — playback held by the listener, narration mode still ON.
   * The Suitcase transport button drives THIS, not `toggle`: pausing is "hold
   * the audiobook", not "make this viewing silent", so it must not collapse
   * the Suitcase chrome back to paging arrows under the thumb that pressed it.
   * `toggle` (the mode change) belongs to the sheet's Narration switch.
   */
  paused: boolean;
  togglePause: () => void;
  /**
   * Current clip progress 0..1 for the transport's ring — a getter so the
   * ring's ~5×/s sampling stays inside SuitcaseTransport instead of
   * re-rendering the player at the audio clock's rate.
   */
  getSlideProgress: () => number;
  /**
   * Voices WITH their deck-wide coverage (voiceCoverage.ts). Uncovered voices
   * are rendered disabled rather than dropped, so the audience can see that a
   * voice exists but wasn't baked for this deck — a missing option looks like a
   * feature that doesn't exist, a disabled one reads as "not for this deck".
   */
  voices: readonly VoiceAvailability[];
  voiceId: string;
  onVoiceChange: (voiceId: string) => void;
  /**
   * True if at least one voice covers the deck end to end. False → nothing can
   * narrate this deck, so the whole group renders disabled: the toggle AND the
   * picker, since there is no valid choice left to make inside it.
   */
  hasAnyNarration: boolean;
}

/** The host's mute: a speaker button in the bar, pressed when muted. */
export interface MuteControl {
  muted: boolean;
  onToggle: () => void;
}

interface DeckChromeProps {
  slideIndex: number;
  slides: Slide[];
  deckId: string;
  isFullscreen: boolean;
  stepNext: () => void;
  stepPrev: () => void;
  toggleFullscreen: () => void;
  onExit: () => void;
  narration?: NarrationControls;
  /**
   * Whether this host has a speaker-notes surface. The notes button opens a
   * popout at {notesUrlBase}/:id/notes — a PRESENTER feature
   * (BroadcastChannel-synced second window with live narration). Defaults
   * true for web.
   */
  hasNotesSurface?: boolean;
  /**
   * Base path for the notes popout, host-specific since the URL scheme
   * differs by router: web uses BrowserRouter ("/deck"), Wasteland uses
   * HashRouter and needs the hash prefix baked in ("/#/decks"). Defaults to
   * web's path so web needs no change.
   */
  notesUrlBase?: string;
  /**
   * Portrait-phone chrome (DeckPlayer passes useCompactLayout): medium
   * buttons instead of small (a 24px target is a miss factory under a
   * thumb), tighter paddings plus home-bar safe-area, icon-only Exit.
   */
  compact?: boolean;
  /**
   * Audiobook mode (CSS Wasteland's Suitcase Mode — mobile-only, so this is
   * meaningless without `compact` too). Replaces the paging group (prev /
   * counter / next) with one large, centered play/pause button — the one
   * control that matters with your eyes closed on a bus. Exit and the gear
   * sheet (voice picker, exit-suitcase-mode) stay exactly where they are;
   * only the paging middle changes. Requires `narration` — Suitcase Mode
   * has nothing to play/pause without it.
   */
  suitcaseMode?: boolean;
  /**
   * Flip Suitcase Mode on/off from the gear sheet — the one surface always
   * reachable even while the transport bar is down to one button. Without
   * this, someone who wants to page manually again (or go back into
   * Suitcase Mode) has no way to say so short of leaving the deck for
   * Settings. A toggle, not a one-way exit — the three real mobile states
   * (paging silent, paging narrated, full Suitcase Mode) should all be
   * reachable from here.
   */
  onToggleSuitcaseMode?: () => void;
  /**
   * The compact sheet opened or closed. DeckPlayer holds narration playback
   * while it's open — a voice reading over you while you're trying to read a
   * switch is rude, and in Suitcase Mode the deck would otherwise auto-advance
   * out from under the sheet. Desktop never fires it: its controls are inline,
   * so there's nothing to open.
   */
  onSettingsOpenChange?: (open: boolean) => void;
  /**
   * The deck is an audiobook (decks/types.ts): Suitcase Mode may show at any
   * width, and when it does, prev and next stay drawn either side of the
   * transport -- prev / play-pause ring / next -- so a tile can be skipped
   * without leaving the mode. Unset for every hand-written deck, whose bar is
   * exactly as it was.
   */
  audiobook?: boolean;
  /** A mute toggle, drawn at any width and in the transport form too. */
  mute?: MuteControl;
}

// Feature-detected once: iPhone Safari has no Fullscreen API, so the button
// would be a silent no-op there — a control that does nothing reads as
// broken, so it isn't rendered at all when the API is absent.
const CAN_FULLSCREEN = typeof document !== "undefined" && !!document.fullscreenEnabled;

// Compact touch metrics. 44px is the Apple HIG floor (Fluent "medium" is
// only 32); the paging arrows are the most-pressed controls on the phone,
// so they get wider still and a bigger glyph.
const TOUCH = { minHeight: "44px", minWidth: "44px" } as const;
// Exit is the one compact control whose glyph is bare TEXT, not an icon
// component — so unlike the gear button beside it, a 44px box left it drawing a
// ~14px ✕ floating in the middle of a big empty target. Sized to match the
// paging chevrons' 18px so the bar's three glyph sizes agree, then a little
// past it: this is the control you reach for one-handed, in a hurry, to get
// out.
const TOUCH_EXIT = { ...TOUCH, fontSize: "22px", lineHeight: 1 } as const;
const TOUCH_ARROW = {
  minHeight: "44px",
  minWidth: "56px",
  fontSize: "18px",
} as const;

export function DeckChrome({
  slideIndex,
  slides,
  deckId,
  isFullscreen,
  stepNext,
  stepPrev,
  toggleFullscreen,
  onExit,
  hasNotesSurface = true,
  notesUrlBase = "/deck",
  narration,
  compact = false,
  suitcaseMode = false,
  onToggleSuitcaseMode,
  onSettingsOpenChange,
  audiobook = false,
  mute,
}: DeckChromeProps) {
  const voiceName = narration?.voices.find((v) => v.id === narration.voiceId)?.name ?? "";
  const buttonSize = compact ? "medium" : "small";
  // Requires narration that can ACTUALLY PLAY, not merely narration that was
  // wired. On a deck with no covered voice, `narration` is a live object whose
  // hasAnyNarration is false — truthy enough to pass a `!!narration` check,
  // which put a dead play button where the paging group belongs and left the
  // reader stranded with no way to move through the deck at all. Suitcase Mode
  // is a promise this deck can't keep, so the bar stays in its paging form.
  const showSuitcaseTransport =
    (compact || audiobook) && suitcaseMode && !!narration && narration.hasAnyNarration;
  // Compact overflow sheet — everything except the basic controls lives here.
  const [moreOpen, setMoreOpenState] = useState(false);

  // One place that both moves the sheet and tells the player, so the two can't
  // disagree — a sheet that opened without suspending playback would talk over
  // the reader, and a suspend that outlived the sheet would leave a deck
  // silently paused with nothing on screen explaining why.
  const setMoreOpen = (open: boolean) => {
    setMoreOpenState(open);
    onSettingsOpenChange?.(open);
  };

  const openNotes = () => {
    const NOTES_WIDTH = 500;
    const NOTES_HEIGHT = 850;
    const left = window.screenX + (window.innerWidth - NOTES_WIDTH) / 2;
    const top = window.screenY + (window.innerHeight - NOTES_HEIGHT) / 2;
    window.open(
      // Hand the notes window the slide the deck is currently on, so
      // opening notes late (already past slide 1) follows the deck
      // instead of resetting to slide 1.
      `${notesUrlBase}/${deckId}/notes?slide=${slideIndex}`,
      // A deck-scoped name, not "_blank" — clicking this a second
      // time (double-click, or re-opening after alt-tabbing away)
      // refocuses the SAME window instead of stacking a new one on
      // top of it. No surprise extra popups.
      `toolkit-notes-${deckId}`,
      `width=${NOTES_WIDTH},height=${NOTES_HEIGHT},left=${Math.round(left)},top=${Math.round(top)}`,
    );
  };

  return (
    <>
      <div
        style={{
          flexShrink: 0,
          backgroundColor: NAV_BG,
          borderTop: `1px solid ${BORDER}`,
          // The bottom padding rides the home-bar inset on phones; env() is 0
          // where there is no inset, so desktop is unchanged.
          padding: compact ? "8px 10px calc(8px + env(safe-area-inset-bottom))" : "10px 24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: compact ? "6px" : "12px",
        }}
      >
        {/* Left: exit — icon-only when compact; the word costs width the
          center group needs for real tap targets. */}
        <Button
          size={buttonSize}
          appearance="subtle"
          onClick={onExit}
          aria-label="Exit deck"
          style={compact ? TOUCH_EXIT : undefined}
        >
          {compact ? "✕" : "✕ Exit"}
        </Button>

        {/* Center: prev / counter / next — OR, in Suitcase Mode, one big
          play/pause and nothing else. Paging and the slide counter are the
          wrong controls for a listening-not-watching mode; the one thing
          worth a 44px target with your eyes closed is play/pause.

          The button drives the transport HOLD (togglePause), never the
          narration mode (toggle). Pause means "hold the audiobook", so the
          transport stays put with a Play glyph; if it flipped the mode
          instead, DeckPlayer's session gate would hand the bar back to the
          paging arrows and the button would delete itself under the thumb
          that pressed it. The way OUT of the transport is a mode change, and
          that lives in the sheet behind the gear. */}
        {showSuitcaseTransport && narration && audiobook ? (
          // An audiobook keeps its paging either side of the one big button.
          <div style={{ display: "flex", alignItems: "center", gap: compact ? "6px" : "12px" }}>
            <Button
              size={buttonSize}
              appearance="subtle"
              disabled={slideIndex === 0}
              onClick={stepPrev}
              aria-label="Previous slide"
              style={compact ? TOUCH_ARROW : undefined}
              icon={<ChevronLeftRegular />}
            />
            <SuitcaseTransport
              paused={narration.paused}
              onTogglePause={narration.togglePause}
              getProgress={narration.getSlideProgress}
            />
            <Button
              size={buttonSize}
              appearance="subtle"
              disabled={slideIndex === slides.length - 1}
              onClick={stepNext}
              aria-label="Next slide"
              style={compact ? TOUCH_ARROW : undefined}
              icon={<ChevronRightRegular />}
            />
          </div>
        ) : showSuitcaseTransport && narration ? (
          <SuitcaseTransport
            paused={narration.paused}
            onTogglePause={narration.togglePause}
            getProgress={narration.getSlideProgress}
          />
        ) : (
          <div style={{ display: "flex", alignItems: "center", gap: compact ? "6px" : "12px" }}>
            {/* Chevrons on compact (the collection's pager grammar), text arrows
            on desktop — unchanged there. */}
            <Button
              size={buttonSize}
              appearance="subtle"
              disabled={slideIndex === 0}
              onClick={stepPrev}
              aria-label="Previous slide"
              style={compact ? TOUCH_ARROW : undefined}
              icon={compact ? <ChevronLeftRegular /> : undefined}
            >
              {compact ? undefined : "←"}
            </Button>
            <span
              style={{
                fontFamily: "monospace",
                fontSize: "13px",
                // was "#666" (~3.5:1 on the near-black nav) — token clears WCAG AA.
                color: tokens.colorNeutralForeground3,
                minWidth: compact ? "48px" : "60px",
                textAlign: "center",
              }}
            >
              {slideIndex + 1} / {slides.length}
            </span>
            <Button
              size={buttonSize}
              appearance="subtle"
              disabled={slideIndex === slides.length - 1}
              onClick={stepNext}
              aria-label="Next slide"
              style={compact ? TOUCH_ARROW : undefined}
              icon={compact ? <ChevronRightRegular /> : undefined}
            >
              {compact ? undefined : "→"}
            </Button>

            {/* Narration controls — toggle + voice picker. Shown only when the host
            wires narration (CSS Wasteland's baked audio). The toggle disables on
            slides with no baked clip in the current voice, so it never silently
            does nothing. Mirrors connected-deck's DeckChrome voice group.
            Desktop only — the compact bar exposes exactly three things (exit,
            paging, the drawer), and voice lives IN the drawer. */}
            {narration && !compact && (
              <>
                <Button
                  size={buttonSize}
                  appearance={narration.enabled ? "primary" : "subtle"}
                  // Two independent reasons to disable, and the deck-wide one wins:
                  // no voice covers this deck at all, or this slide has no clip in
                  // the (covered) voice currently selected.
                  disabled={!narration.hasAnyNarration || !narration.available}
                  icon={
                    narration.playing ? (
                      <Speaker2Filled />
                    ) : narration.available ? (
                      <SpeakerMuteRegular />
                    ) : (
                      <SpeakerOffRegular />
                    )
                  }
                  onClick={narration.toggle}
                  title={
                    !narration.hasAnyNarration
                      ? NO_NARRATION_TITLE
                      : narration.available
                        ? narration.enabled
                          ? "Stop narration"
                          : "Play with narration"
                        : "No narration for this slide"
                  }
                />
                <Dropdown
                  size="small"
                  // Nothing narrates this deck ⇒ the picker is dead too. Every
                  // option inside it would be disabled, so a dropdown that still
                  // opens would just be a menu of things you can't pick.
                  disabled={!narration.hasAnyNarration}
                  value={voiceName}
                  selectedOptions={[narration.voiceId]}
                  onOptionSelect={(_, data) => {
                    if (data.optionValue) narration.onVoiceChange(data.optionValue);
                  }}
                  style={{ minWidth: "84px" }}
                  title={narration.hasAnyNarration ? VOICE_PICKER_TITLE : NO_NARRATION_TITLE}
                >
                  {narration.voices.map((v) => (
                    <Option key={v.id} value={v.id} text={v.name} disabled={!v.available}>
                      {voiceOptionLabel(v.name, v.available)}
                    </Option>
                  ))}
                </Dropdown>
              </>
            )}
          </div>
        )}

        {/* Right: notes + fullscreen on desktop; on compact one gear that opens
          the settings sheet holding everything non-basic. */}
        <div style={{ display: "flex", alignItems: "center", gap: compact ? "6px" : "10px" }}>
          {mute && (
            <Button
              size={buttonSize}
              appearance={mute.muted ? "primary" : "subtle"}
              aria-label={MUTE_NARRATION_LABEL}
              aria-pressed={mute.muted}
              title={mute.muted ? UNMUTE_NARRATION_LABEL : MUTE_NARRATION_LABEL}
              icon={mute.muted ? <SpeakerOffRegular /> : <Speaker2Filled />}
              onClick={mute.onToggle}
              style={compact ? TOUCH : undefined}
            />
          )}
          {compact ? (
            (narration || hasNotesSurface) && (
              // A gear, not a ⋯: this sheet IS the settings surface on a phone
              // (voice, narration, Suitcase Mode), and in Suitcase Mode it's the
              // only route back to manual paging once the transport bar is down
              // to one button. "⋯" promises unspecified extras; a gear names
              // what's behind it, which is what someone hunting for the way out
              // is actually looking for.
              <Button
                size="medium"
                appearance="subtle"
                aria-label="Settings"
                icon={<SettingsRegular />}
                onClick={() => setMoreOpen(true)}
                style={TOUCH}
              />
            )
          ) : (
            <>
              {hasNotesSurface && (
                <Button
                  size="small"
                  appearance="subtle"
                  title="Open speaker notes"
                  icon={<Speaker0Regular />}
                  onClick={openNotes}
                />
              )}
              {CAN_FULLSCREEN && (
                <Button
                  size="small"
                  appearance="subtle"
                  title={isFullscreen ? "Exit fullscreen (F)" : "Fullscreen (F)"}
                  onClick={toggleFullscreen}
                >
                  {isFullscreen ? "⊡" : "⛶"}
                </Button>
              )}
            </>
          )}
        </div>
      </div>

      {/* The compact overflow sheet — same bottom-sheet grammar as the
        collection's tag filter. Neutral player theme, deliberately: no host
        brand follows a deck in. */}
      {compact && (
        <OverlayDrawer
          open={moreOpen}
          position="bottom"
          size="small"
          onOpenChange={(_, { open: next }) => {
            if (!next) setMoreOpen(false);
          }}
        >
          <DrawerHeader>
            <DrawerHeaderTitle
              action={
                <Button
                  appearance="subtle"
                  aria-label="Close voice controls"
                  icon={<DismissRegular />}
                  onClick={() => setMoreOpen(false)}
                />
              }
            >
              Voice
            </DrawerHeaderTitle>
          </DrawerHeader>
          <DrawerBody
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "20px",
              paddingBottom: "calc(20px + env(safe-area-inset-bottom))",
            }}
          >
            {/* No fullscreen here on purpose — mobile browsers already give the
              deck the screen; a fourth control is chrome for chrome's sake.
              The drawer is the voice home: the narration switch and the voice
              choice, nothing else (plus notes for the rare phone presenter). */}
            {narration && (
              <>
                <Switch
                  checked={narration.enabled}
                  onChange={narration.toggle}
                  disabled={!narration.hasAnyNarration}
                  label="Narration"
                />
                {/* The three real states a mobile visitor picks between: paging
                  silent, paging narrated, or full Suitcase Mode (narrated +
                  auto-advance, no paging). This switch is the only way back
                  from the third once the transport bar is down to one button —
                  a toggle, not a one-way exit.

                  Sits BELOW Narration and goes dead with it: auto-advance
                  fires when a clip ENDS, so a silent deck never produces the
                  event. Rendering it live over silence offers a mode the deck
                  won't enter, and putting it first put the dependent control
                  above the thing it depends on. */}
                {onToggleSuitcaseMode && (
                  <Switch
                    checked={suitcaseMode}
                    onChange={onToggleSuitcaseMode}
                    disabled={!narration.enabled || !narration.hasAnyNarration}
                    label={suitcaseMode ? "Suitcase mode" : "Manual paging"}
                  />
                )}
                {/* No visible section label — the drawer's own title already
                  says Voice; the group keeps the name for assistive tech. */}
                <RadioGroup
                  aria-label={VOICE_PICKER_TITLE}
                  value={narration.voiceId}
                  // Same rule as the desktop picker: nothing narrates this deck
                  // ⇒ the whole group is dead, not just its options.
                  disabled={!narration.hasAnyNarration}
                  onChange={(_, data) => narration.onVoiceChange(data.value)}
                >
                  {narration.voices.map((v) => (
                    <Radio
                      key={v.id}
                      value={v.id}
                      label={voiceOptionLabel(v.name, v.available)}
                      disabled={!v.available}
                    />
                  ))}
                </RadioGroup>
              </>
            )}
            {hasNotesSurface && (
              <Button
                appearance="secondary"
                icon={<Speaker0Regular />}
                onClick={() => {
                  setMoreOpen(false);
                  openNotes();
                }}
              >
                Speaker notes
              </Button>
            )}
          </DrawerBody>
        </OverlayDrawer>
      )}
    </>
  );
}
