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

// A connected deck is always ONE of these — not a per-viewer choice, a fixed
// identity each host declares once. "audience" is the Wasteland's sofa: a
// silent-viewer window that owns its own Voice/mute controls, no notes
// surface exists (not hidden — absent; there's nothing to escalate to).
// "presenter" is the podium: the notes popout is available (still a
// deliberate click, never auto-opened — see DeckChrome's notes button), and
// the main window never shows Voice/mute, because the presenter owns their
// own voice, live or read from notes. web is ALWAYS "presenter" — it has no
// audience path. Wasteland's main deck window is ALWAYS "audience".
export type DeckMode = "presenter" | "audience";

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
  suitcaseMode = false,
  onToggleSuitcaseMode,
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
   * Base path for the notes popout — host-specific since the URL scheme
   * differs by router (web: BrowserRouter "/deck"; Wasteland: HashRouter
   * "/#/decks"). Only meaningful when mode="presenter"; defaults to web's path.
   */
  notesUrlBase?: string;
  /**
   * Selectable narration voices for the AUDIENCE window's own Voice/mute
   * control. Provide together with resolveNarrationUrl. Ignored entirely in
   * presenter mode — the presenter's voice (live or read from notes) is the
   * whole point; a synthesized one competing with it would be noise.
   */
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
   * having to reach for the Voice sheet first. A host's own persisted
   * preference (see CSS Wasteland's voicePreference.tsx), not a deck fact —
   * ignored entirely outside audience mode, same as voices/resolveNarrationUrl.
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
   * available, so Suitcase Mode still advances. Unset: no button, as before.
   * Audience mode with narration wired only.
   */
  mute?: { muted: boolean; onToggle: () => void };
  /**
   * Audiobook mode: advance to the next slide automatically when the
   * current one's narration clip ends, instead of waiting for a tap. A
   * host's own persisted preference (CSS Wasteland's voicePreference.tsx,
   * "Suitcase Mode"), not a deck
   * fact. Requires narration — there's nothing to auto-advance FROM if
   * nothing's playing — but does NOT force it on: a host that passes
   * suitcaseMode without narrateByDefault gets a silent, manually-paged deck,
   * because overriding a visitor's explicit "no audio" is worse than a
   * setting that quietly waits. Hosts are expected to keep the two in step
   * (see CSS Wasteland's voicePreference.tsx).
   */
  suitcaseMode?: boolean;
  /**
   * Flip the host's persisted Suitcase Mode preference. `suitcaseMode` above
   * is read-only from this component's own perspective (a prop, not local
   * state) — the host owns the preference (CSS Wasteland's
   * voicePreference.tsx), so turning it off from the in-player drawer has to
   * call back up rather than set anything here. DeckChrome renders no
   * escape-hatch switch at all when this is omitted.
   */
  onToggleSuitcaseMode?: () => void;
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

  // A notes popout outlives the mode that opened it. Hosts can flip presenter
  // off mid-session — WastelandDeck forces audience once the viewport crosses
  // into mobile — and the popout, being a separate window with its own React
  // tree, has no way to notice. It keeps following slide changes on the shared
  // BroadcastChannel while the parent has already switched to audience chrome:
  // two windows disagreeing about what the session is.
  //
  // Reuses the channel and the message exitDeck already broadcasts, because
  // this IS that situation from the popout's point of view — the thing it was
  // attached to is gone. Widen the window again and Podium comes back, so the
  // notes button is there to reopen it.
  const wasPresenterRef = useRef(mode === "presenter");
  useEffect(() => {
    const wasPresenter = wasPresenterRef.current;
    wasPresenterRef.current = mode === "presenter";
    if (!wasPresenter || mode === "presenter" || !deckId) return;
    const channel = new BroadcastChannel(`toolkit-deck-${deckId}`);
    channel.postMessage({ type: "deck-closed" });
    channel.close();
  }, [mode, deckId]);

  // In-player narration is an AUDIENCE-only concept — presenter mode never
  // shows it, full stop, regardless of whether voices/resolveNarrationUrl
  // were passed (mode owns this, not the presence of the props).
  const wantsNarration = mode === "audience" && !!voices?.length && !!resolveNarrationUrl;

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
  const muted = wantsNarration && !!mute?.muted;
  const narrationUrl =
    wantsNarration && !muted && hasAnyNarration && currentSlide && voiceId
      ? resolveNarrationUrl!(currentSlide, voiceId)
      : null;
  // `compact` too, not just the host's flag: Suitcase Mode is a MOBILE
  // affordance — the compact chrome trades the paging arrows for one big
  // play/pause to match. On a wide screen the chrome shows ordinary paging
  // arrows, so slides advancing on their own would be a deck moving with
  // nothing on screen saying why. Gated on the LIVE layout, so widening a
  // window mid-deck stops the advance rather than only re-skinning around it.
  //
  // Here rather than in each host: WastelandDeck can gate its own prop, but a
  // host that passes suitcaseMode ungated would otherwise still auto-advance
  // on a desktop. The player owns the behaviour, so the player owns the rule.
  //
  // One exception, and it is the deck's to claim, not the host's: an AUDIOBOOK
  // deck (decks/types.ts) is made to be listened to at any width, so for it
  // the gate drops `compact` -- and the chrome keeps prev and next beside the
  // transport, so the deck moving on its own always has something on screen
  // saying why and a way to skip. Every deck that does not set the hint keeps
  // the rule above exactly.
  const audiobook = deck?.audiobook === true;
  const wantsSuitcaseMode = wantsNarration && suitcaseMode && (compact || audiobook);
  // Held while the compact settings sheet is open — see onSettingsOpenChange.
  // Not `enabled`: suspending leaves narration ON, so the sheet's own switch
  // still reads as narrating and playback picks up mid-clip on close.
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Thumb paging, compact tiers only (the owner's call: "fine to apply it if
  // isMobile, otherwise noop"). Gated on `compact` rather than on Suitcase
  // Mode, so a phone-width deck pages by swipe whether it's narrating itself
  // or showing manual arrows — the gesture means the same thing either way.
  //
  // Handed the controller's OWN stepNext/stepPrev, which is what keeps Suitcase
  // Mode's auto-advance intact: a swipe is then indistinguishable from an
  // arrow press, and the dwell-timer cancellation, clip restart, and
  // pause-survives-navigation behaviour all come along for free (the details
  // are in useSwipeNavigation's header).
  const swipe = useSwipeNavigation({ onNext: stepNext, onPrev: stepPrev, enabled: compact });

  const audioNarration = useSlideNarration({
    url: narrationUrl,
    suspended: settingsOpen,
    // narrateByDefault ALONE decides whether audio starts. Suitcase Mode used
    // to force it on here too; that let a stale Suitcase flag override a
    // visitor who had just turned Voice off, and their deck read itself aloud
    // anyway. The host's preference module keeps the two in step (Suitcase
    // requires narration, both directions), so there is nothing left for this
    // to correct for.
    enabledDefault: wantsNarration && narrateByDefault,
    onEnded: wantsSuitcaseMode ? stepNext : undefined,
  });

  // An audiobook's slide with no clip is read by the browser's voice from its
  // Say text (useSpeechNarration; D-TA7's no-key fallback). `null` everywhere
  // else, which leaves that hook inert: a deck without the hint never reaches
  // speechSynthesis, and a slide with a clip plays the clip.
  const speechText =
    audiobook && wantsNarration && hasAnyNarration && currentSlide && !narrationUrl
      ? slideSpokenText(currentSlide) || null
      : null;
  const speechNarration = useSpeechNarration({
    text: speechText,
    suspended: settingsOpen,
    silent: muted,
    enabledDefault: wantsNarration && narrateByDefault,
    onEnded: wantsSuitcaseMode ? stepNext : undefined,
  });
  // The two voices share ONE set of controls: the mode and the hold are
  // flipped on both together, so they never disagree, and the one that is
  // speaking this slide is the one the chrome reads.
  const narration: SlideNarration = audiobook
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
          compact={compact}
          audiobook={audiobook}
          mute={wantsNarration ? mute : undefined}
          // "Suitcase requires narration, both directions" applies to the
          // SESSION layer too, not just the stored prefs the host keeps in
          // step (voicePreference.tsx): the sheet's Narration switch drives
          // narration.enabled, and a viewing switched to silent has no
          // clip-ends for Suitcase Mode to advance on. Without this gate the
          // chrome kept the one-button transport over a silent deck — a play
          // control for a mode that could no longer mean anything, with the
          // paging arrows nowhere. Transport PAUSE is not this: pause holds
          // playback with narration still on (see useSlideNarration), so the
          // transport survives its own button.
          suitcaseMode={wantsSuitcaseMode && narration.enabled}
          onSettingsOpenChange={setSettingsOpen}
          onToggleSuitcaseMode={wantsNarration ? onToggleSuitcaseMode : undefined}
          hasNotesSurface={mode === "presenter"}
          notesUrlBase={notesUrlBase}
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
