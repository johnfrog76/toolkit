import { useEffect, useRef, useState } from "react";
import { FluentProvider, Button, webDarkTheme } from "@fluentui/react-components";
import type { Theme } from "@fluentui/react-components";
import { useNavigate } from "react-router";
import type { Deck, Slide } from "../decks/types";
import { DeckContext } from "./deckContext";
import { useDeckController } from "./DeckController";
import { SlideRenderer, DECK_BG } from "./SlideRenderer";
import { DeckChrome } from "./DeckChrome";
import { useCompactLayout } from "./useCompactLayout";
import { useSlideNarration } from "./useSlideNarration";
import type { SlideNarration } from "./useSlideNarration";
import { useSpeechNarration } from "./useSpeechNarration";
import { slideSpokenText } from "./sayText";
import { useSwipeNavigation } from "./useSwipeNavigation";
import { useVoiceControls } from "./useVoiceControls";
import type { NarrationVoice } from "./narrationConstants";

// NarrationVoice now lives with the rest of the narration contract
// (narrationConstants.ts). Re-exported here so existing importers keep working.
export type { NarrationVoice };

// What a window IS, declared per viewing rather than reconciled from a pile of
// independent flags — and which of the two bars it gets.
//
//   "audience" — the viewer: Sofa, or Audiobook mode when the host turns it
//     on. The viewer's bar (Exit | the transport | settings, fullscreen, the
//     sound) at every width; NO notes surface exists. Absent, not hidden: a
//     link someone shared with you has nothing to escalate to.
//   "presenter" — the podium. The presenter's bar, everything inline, with the
//     notes popout; never at the phone width, where the bar can't fold.
export type DeckMode = "presenter" | "audience";

/**
 * The modes a host offers, when it says nothing: both. A host that only ever
 * plays to a viewer passes ["audience"] and gets no Podium anywhere — no
 * presenter's bar, no notes button — whatever `mode` says.
 */
export const ALL_DECK_MODES: readonly DeckMode[] = ["audience", "presenter"];

// DeckPlayer — the presentational, backend-free core of the deck player.
// Extracted from PresentationDeck (spec: "move the player up to a shared path")
// so a host without the FastAPI backend (CSS Wasteland) can play a deck too.
//
// What's different from PresentationDeck: nothing about state or rendering.
// Every host renders identically; only the wiring (and `mode`) differs. There is
// no org concept here at all — a deck needing live host data reads it from that
// host's own runtime (see engineering-os.tsx), so nothing is threaded through
// the player.
export function DeckPlayer({
  deckId,
  deck,
  slides,
  mode,
  notesUrlBase,
  voices,
  hasApi = false,
  resolveNarrationUrl,
  narrateByDefault = false,
  mute,
  audiobook = false,
  onAudiobookChange,
  offeredModes = ALL_DECK_MODES,
  onAfterSlideNavCallback,
  initialSlideIndex = 0,
  theme = webDarkTheme,
}: {
  deckId: string | undefined;
  /**
   * The deck itself, when the host has it — provided to the slides through
   * DeckContext so a slide's content can learn its owner's project (the
   * giveaway button's target). Optional: a host that only has slides still
   * plays, and every consumer of the context answers null sensibly.
   */
  deck?: Deck;
  slides: Slide[];
  /**
   * What this window IS — required, no default. Every host must declare it
   * explicitly rather than inheriting behavior from a pile of independent
   * flags. See the DeckMode doc comment above.
   */
  mode: DeckMode;
  /**
   * The modes this host offers (ALL_DECK_MODES by default). Podium is drawn
   * only where it is offered AND the window is wider than a phone; anything
   * else plays on the viewer's bar. A host that never presents passes
   * ["audience"], and locking a player to one mode is just that.
   */
  offeredModes?: readonly DeckMode[];
  /**
   * Base path for the notes popout — host-specific since the URL scheme
   * differs by router (web: BrowserRouter "/deck"; Wasteland: HashRouter
   * "/#/decks"). Only meaningful when mode="presenter"; defaults to web's path.
   */
  notesUrlBase?: string;
  /** Pair with resolveNarrationUrl. Wired, both bars carry the sound and the voice. */
  voices?: readonly NarrationVoice[];
  /**
   * True when this host has a live /api/narrate (the prompts web UI). Voices are
   * then never disabled for missing assets — anything can be synthesized on
   * demand. Leave false on backend-free hosts, where the baked files are all
   * there is. See voiceCoverage.ts: the same deck can be fully narratable in one
   * host and silent in another.
   */
  hasApi?: boolean;
  /**
   * Resolve the audio URL for a slide in a given voice, or null if none exists.
   * CSS Wasteland backs this with its baked-mp3 registry (static assets). The
   * player auto-plays the current slide's clip while narration is toggled on.
   */
  resolveNarrationUrl?: (slide: Slide, voiceId: string) => string | null;
  /**
   * Start narration ON when this window mounts, instead of the visitor
   * having to reach for the sound control first. The viewer's bar only:
   * Podium opens silent, since a presenter's own voice is usually the point,
   * and its sound button is there when it isn't.
   *
   * Real caveat, not a bug to "fix" here: browser autoplay policy blocks
   * `<audio>.play()` without a prior user gesture, so on a cold page load
   * the FIRST clip can silently fail to sound (useSlideNarration's own
   * `.catch()` swallows it) even though the toggle shows on. Once the
   * visitor taps anything, that gesture blesses the element and playback
   * behaves normally from the next slide on. Not solvable by trying harder
   * here — it's the same reason a muted-autoplay video needs a tap to gain
   * sound on iOS.
   */
  narrateByDefault?: boolean;
  /**
   * A host-kept mute. Muted, no clip is fetched and speechSynthesis is
   * handed nothing, but each slide keeps the clock it has when no voice is
   * available, so Audiobook mode still advances. Passed, it is the viewer's
   * bar's sound button; unset, that button is the narration toggle.
   * The viewer's bar with narration wired only.
   */
  mute?: { muted: boolean; onToggle: () => void };
  /**
   * Audiobook mode: read the deck aloud and advance when the current slide's
   * narration ends, stopping at the last slide. A host fact like `mode` — the
   * player is told, and never reads a preference itself. Turns narration on
   * with it; ignored in Podium, where a presenter turns their own slides.
   */
  audiobook?: boolean;
  /**
   * Choose Sofa (false) or Audiobook (true) from the viewer's settings sheet.
   * The host stores the choice and passes it back as `audiobook`. Omitted, the
   * sheet has no mode row: the host has fixed the mode itself.
   */
  onAudiobookChange?: (next: boolean) => void;
  /** Fires after the visitor lands on a slide: (slideIndex, totalSlides).
   *  The one seam into navigation a host gets — see useDeckController. */
  onAfterSlideNavCallback?: (slideIndex: number, totalSlides: number) => void;
  /** Which slide to OPEN on. Read once per deck, not live — see
   *  useDeckController. Defaults to 0; a host with stored progress passes a
   *  resume point. Clamped to the deck, so a stale number is safe. */
  initialSlideIndex?: number;
  /**
   * Theme override; defaults to Fluent's plain webDarkTheme. The player is the
   * ONE shared application between hosts, so its chrome is deliberately
   * unbranded — neither prompts-indigo nor wasteland-teal follows a deck in.
   */
  theme?: Theme;
}) {
  const navigate = useNavigate();
  const { slideIndex, isFullscreen, stepNext, stepPrev, toggleFullscreen, exitDeck } =
    useDeckController(slides, deckId, onAfterSlideNavCallback, initialSlideIndex);
  // Portrait-phone layout (≤575px): the
  // renderer stacks art over copy and the chrome grows thumb targets.
  // Rotating to landscape crosses the boundary and restores the split live.
  const compact = useCompactLayout();
  // The mode this window plays in: Podium only where the host offers it and
  // never at the phone width (the presenter's bar does not fold). The engine
  // enforces this itself, so a host that forgets the phone rule can't strand a
  // phone on a bar it can't use.
  const playMode: DeckMode =
    mode === "presenter" && offeredModes.includes("presenter") && !compact
      ? "presenter"
      : "audience";

  // A notes popout outlives the mode that opened it. A host can flip presenter
  // off mid-session — the player itself does once the viewport crosses into
  // the phone width — and the popout, being a separate window with its own React
  // tree, has no way to notice. It keeps following slide changes on the shared
  // BroadcastChannel while the parent has already switched to audience chrome:
  // two windows disagreeing about what the session is.
  //
  // Reuses the channel and the message exitDeck already broadcasts, because
  // this IS that situation from the popout's point of view — the thing it was
  // attached to is gone. Widen the window again and Podium comes back, so the
  // notes button is there to reopen it.
  const wasPresenterRef = useRef(playMode === "presenter");
  useEffect(() => {
    const wasPresenter = wasPresenterRef.current;
    wasPresenterRef.current = playMode === "presenter";
    if (!wasPresenter || playMode === "presenter" || !deckId) return;
    const channel = new BroadcastChannel(`toolkit-deck-${deckId}`);
    channel.postMessage({ type: "deck-closed" });
    channel.close();
  }, [playMode, deckId]);

  // In-player narration, wherever the host wired it: the viewer's bar carries
  // the sound and the sheet, and the presenter's bar carries the sound and the
  // voice dropdown inline.
  const wantsNarration = !!voices?.length && !!resolveNarrationUrl;

  // Which voices this deck can actually be narrated in, and which is selected —
  // the same hook the notes popout uses, so both surfaces agree by construction.
  const {
    voices: surveyedVoices,
    voiceId,
    setVoiceId,
    hasAnyNarration,
  } = useVoiceControls({
    slides,
    voices: voices ?? [],
    hasApi,
    resolveUrl: resolveNarrationUrl,
    enabled: wantsNarration,
  });

  // The controls RENDER whenever this host wired narration — coverage decides
  // whether they're enabled, not whether they exist (rule 2a: no covered voice
  // ⇒ toggle and picker both disabled, in DeckChrome). Present-but-disabled says
  // "this deck wasn't baked"; absent would say "this player can't narrate",
  // which is a different and wrong claim.
  const currentSlide = slides[slideIndex];
  const muted = wantsNarration && playMode === "audience" && !!mute?.muted;
  const narrationUrl =
    wantsNarration && !muted && hasAnyNarration && currentSlide && voiceId
      ? resolveNarrationUrl!(currentSlide, voiceId)
      : null;
  // AUDIOBOOK MODE runs at every width on the viewer's bar, whose counter
  // gives way to the play ring while it is on: the ring is what says, on any
  // screen, why the deck is moving on its own, previous and next either side
  // of it skip a slide without leaving the mode, and the sheet behind the gear
  // is the way back to paging. Never in Podium: a presenter turns their own
  // slides.
  //
  // Gated on the LIVE mode rather than on a stored flag, so narrowing a Podium
  // window into the viewer's bar picks the mode up, and widening it again
  // stops the advance. The host's choice itself is left alone.
  const audiobookActive = wantsNarration && audiobook && playMode === "audience";
  // A deck MADE to be listened to (decks/types.ts's `audiobook` hint) is a
  // different fact from the mode: it lets the browser's voice read a slide
  // that has no clip (below).
  const audiobookDeck = deck?.audiobook === true;
  // Audiobook mode turns narration on with it: a deck that turns its own
  // slides on a clip's end needs clips to end. Podium opens silent.
  const narrateOnArrival =
    wantsNarration && playMode === "audience" && (narrateByDefault || audiobook);
  // Held while the viewer's settings sheet is open — see onSettingsOpenChange.
  // Not `enabled`: suspending leaves narration ON, so the sheet's own switch
  // still reads as narrating and playback picks up mid-clip on close.
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Thumb paging, compact tiers only (the owner's call: "fine to apply it if
  // isMobile, otherwise noop"). Gated on `compact` rather than on the mode, so
  // a phone-width deck pages by swipe whether it's reading itself in
  // Audiobook mode or paged by hand — the gesture means the same thing either
  // way.
  //
  // Handed the controller's OWN stepNext/stepPrev, which is what keeps
  // Audiobook mode's auto-advance intact: a swipe is then indistinguishable
  // from an arrow press, and the dwell-timer cancellation, clip restart, and
  // pause-survives-navigation behaviour all come along for free (the details
  // are in useSwipeNavigation's header).
  const swipe = useSwipeNavigation({ onNext: stepNext, onPrev: stepPrev, enabled: compact });

  const audioNarration = useSlideNarration({
    url: narrationUrl,
    suspended: settingsOpen,
    enabledDefault: narrateOnArrival,
    onEnded: audiobookActive ? stepNext : undefined,
  });

  // An audiobook's slide with no clip is read by the browser's voice from its
  // Say text (useSpeechNarration; D-TA7's no-key fallback). `null` everywhere
  // else, which leaves that hook inert: a deck without the hint never reaches
  // speechSynthesis, and a slide with a clip plays the clip.
  const speechText =
    audiobookDeck && wantsNarration && hasAnyNarration && currentSlide && !narrationUrl
      ? slideSpokenText(currentSlide) || null
      : null;
  const speechNarration = useSpeechNarration({
    text: speechText,
    suspended: settingsOpen,
    silent: muted,
    enabledDefault: narrateOnArrival,
    onEnded: audiobookActive ? stepNext : undefined,
  });
  // The two voices share ONE set of controls: the mode and the hold are
  // flipped on both together, so they never disagree, and the one that is
  // speaking this slide is the one the chrome reads.
  const narration: SlideNarration = audiobookDeck
    ? {
        ...(speechText ? speechNarration : audioNarration),
        toggle: () => {
          audioNarration.toggle();
          speechNarration.toggle();
        },
        togglePause: () => {
          audioNarration.togglePause();
          speechNarration.togglePause();
        },
      }
    : audioNarration;

  if (slides.length === 0) {
    return (
      <FluentProvider theme={theme}>
        <div
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 9999,
            backgroundColor: DECK_BG,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: "16px",
            color: "#fff",
          }}
        >
          <p style={{ fontSize: "1.4rem", margin: 0 }}>Deck &ldquo;{deckId}&rdquo; not found</p>
          <Button onClick={() => navigate(-1)}>← Back</Button>
        </div>
      </FluentProvider>
    );
  }

  return (
    <FluentProvider
      theme={theme}
      style={{ colorScheme: "dark", height: "100%", display: "contents" }}
    >
      <div
        style={{
          position: "fixed",
          inset: 0,
          zIndex: 9999,
          backgroundColor: DECK_BG,
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
        }}
      >
        {/* ONE swipe target for both directions — the slide area itself.
            Direction comes from the gesture's travel (dx sign), not from
            which half of the screen the thumb landed on, so there's no
            left-zone/right-zone to miss. Empty handlers on desktop.

            A REAL box, not display:contents. The wrapper has to carry
            touch-action, and touch-action needs a box to apply to — on a
            boxless element the browser drops the declaration and the phone
            keeps claiming horizontal pans, which is the whole thing this
            has to prevent. So the wrapper takes over SlideRenderer's own
            slot in the column (flex:1, minHeight:0, overflow:hidden) and
            SlideRenderer's root then fills IT — same layout, one more
            element deep.

            touch-action:none, not pan-y. The player is a FIXED, non-scrolling
            surface — position:fixed inset:0, the slide scaled to fit, nothing
            under here scrolls (measured: clientHeight === scrollHeight, zero
            scrollable descendants). pan-y was written for a scrolling page
            this isn't, and it actively broke the feature: the browser decides
            a gesture's axis from its first few pixels, so a real drag that
            starts a touch off-axis got claimed as a pan and the pointer
            stream was CANCELLED mid-swipe — every swipe after the first
            couple silently died. `none` says the deck owns its gestures.

            If a slide ever becomes genuinely scrollable, this has to become
            pan-y again AND the cancel path has to be handled — see the
            pointercancel note in useSwipeNavigation. Compact only; on desktop
            there's no touch gesture to negotiate. */}
        <div
          data-swipe-surface=""
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            minHeight: 0,
            overflow: "hidden",
            touchAction: compact ? "none" : undefined,
          }}
          {...swipe}
        >
          <DeckContext.Provider value={deck ?? null}>
            <SlideRenderer
              slide={slides[slideIndex]}
              slideIndex={slideIndex}
              isFullscreen={isFullscreen}
              stacked={compact}
            />
          </DeckContext.Provider>
        </div>
        <DeckChrome
          slideIndex={slideIndex}
          slides={slides}
          deckId={deckId ?? ""}
          isFullscreen={isFullscreen}
          stepNext={stepNext}
          stepPrev={stepPrev}
          toggleFullscreen={toggleFullscreen}
          onExit={exitDeck}
          bar={playMode === "presenter" ? "presenter" : "viewer"}
          compact={compact}
          hasNotesSurface={playMode === "presenter"}
          notesUrlBase={notesUrlBase}
          mute={wantsNarration && playMode === "audience" ? mute : undefined}
          // "Requires narration in both directions" applies to the SESSION
          // layer too: the sound button and the sheet's Narration row drive
          // narration.enabled, and a viewing declared silent has no clip-ends
          // for Audiobook mode to advance on. Without this gate the bar kept
          // the play ring over a silent deck — a play control for a mode that
          // could no longer mean anything. Transport PAUSE is not this: pause
          // holds playback with narration still on (see useSlideNarration), so
          // the ring survives its own button.
          audiobookMode={audiobookActive && narration.enabled}
          onAudiobookChange={wantsNarration ? onAudiobookChange : undefined}
          onSettingsOpenChange={setSettingsOpen}
          narration={
            wantsNarration
              ? {
                  available: narration.available,
                  playing: narration.playing,
                  enabled: narration.enabled,
                  toggle: narration.toggle,
                  paused: narration.paused,
                  togglePause: narration.togglePause,
                  getSlideProgress: narration.getSlideProgress,
                  voices: surveyedVoices,
                  voiceId,
                  onVoiceChange: setVoiceId,
                  hasAnyNarration,
                }
              : undefined
          }
        />
      </div>
    </FluentProvider>
  );
}
