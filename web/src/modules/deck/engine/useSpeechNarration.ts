import { useCallback, useEffect, useRef, useState } from "react";
import { NARRATION_CHARS_PER_SEC, SLIDE_DWELL_SECONDS } from "./deckDuration";
import type { SlideNarration } from "./useSlideNarration";

// The browser's own voice, for an AUDIOBOOK deck's slide that has no baked
// clip (decks/types.ts `audiobook`; D-TA7, D-SA7: "browser speech is the
// fallback with no key"). A ritual deck is written this morning by the tracker,
// so no clip can exist for it; this reads the slide's Say text instead.
//
// The same SlideNarration shape as useSlideNarration, so DeckPlayer and the
// chrome cannot tell which one is speaking: enabled / paused / playing mean the
// same three things, onEnded fires SLIDE_DWELL_SECONDS after the voice stops
// (Suitcase Mode's advance), and getSlideProgress reports the slide's life as
// read time + dwell -- deckDuration's model, so the ring and the deck's length
// estimate agree.
//
// No speechSynthesis (jsdom, a locked-down browser): the slide still LIVES for
// its estimated read time, silently, and then advances. "No voice" is said by
// nothing on screen -- the audiobook simply plays without sound, which is what
// a reader with the sound off would see anyway.
//
// INERT when `text` is null. A deck that is not an audiobook passes null on
// every slide and this hook then never touches speechSynthesis at all -- not
// even cancel() -- so the shipped decks are exactly as they were.

function synth(): SpeechSynthesis | null {
  if (typeof window === "undefined") return null;
  if (!("speechSynthesis" in window) || typeof SpeechSynthesisUtterance === "undefined")
    return null;
  return window.speechSynthesis;
}

/** Seconds the voice is expected to take over `text`: deckDuration's rate. */
export function speechSeconds(text: string): number {
  return Math.max(1, text.length / NARRATION_CHARS_PER_SEC);
}

export function useSpeechNarration({
  text,
  enabledDefault = false,
  onEnded,
  suspended = false,
  silent = false,
}: {
  /** The current slide's spoken text, or null: nothing to say (and inert). */
  text: string | null;
  enabledDefault?: boolean;
  /** Called a dwell after the voice finishes (Suitcase Mode's advance). */
  onEnded?: () => void;
  /** The player's own hold (the compact settings sheet is open). */
  suspended?: boolean;
  /**
   * Muted: the slide keeps its clock -- read time, then the dwell, then
   * onEnded -- and speechSynthesis is handed nothing, not even cancel().
   * The same path a browser with no speech API takes.
   */
  silent?: boolean;
}): SlideNarration {
  const [enabled, setEnabled] = useState(enabledDefault);
  const [paused, setPaused] = useState(false);
  const [playing, setPlaying] = useState(false);

  const onEndedRef = useRef(onEnded);
  useEffect(() => {
    onEndedRef.current = onEnded;
  }, [onEnded]);
  const heldRef = useRef(suspended || paused);
  useEffect(() => {
    heldRef.current = suspended || paused;
  }, [suspended, paused]);

  // The slide's clock. `expected` is the read time; `elapsed` accumulates while
  // the voice runs, so a hold mid-sentence resumes where it stopped.
  const expectedRef = useRef(0);
  const elapsedRef = useRef(0);
  const runningSinceRef = useRef<number | null>(null);
  const startedRef = useRef(false);
  const doneRef = useRef(false);
  const dwellStartedAtRef = useRef<number | null>(null);
  const speakTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const dwellTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);
  const textRef = useRef(text);
  useEffect(() => {
    textRef.current = text;
  }, [text]);
  const silentRef = useRef(silent);
  useEffect(() => {
    silentRef.current = silent;
  }, [silent]);

  const clearSpeakTimer = () => {
    if (speakTimerRef.current !== null) {
      clearTimeout(speakTimerRef.current);
      speakTimerRef.current = null;
    }
  };

  const finishSpeaking = useCallback(() => {
    clearSpeakTimer();
    if (runningSinceRef.current !== null) {
      elapsedRef.current += (Date.now() - runningSinceRef.current) / 1000;
      runningSinceRef.current = null;
    }
    doneRef.current = true;
    utteranceRef.current = null;
    setPlaying(false);
    dwellStartedAtRef.current = Date.now();
    dwellTimerRef.current = setTimeout(() => {
      dwellTimerRef.current = null;
      onEndedRef.current?.();
    }, SLIDE_DWELL_SECONDS * 1000);
  }, []);

  /** Start (or, with no speech API, stand in for) the voice from the top. */
  const start = useCallback(() => {
    const said = textRef.current;
    if (!said) return;
    startedRef.current = true;
    runningSinceRef.current = Date.now();
    const s = silentRef.current ? null : synth();
    if (s) {
      const u = new SpeechSynthesisUtterance(said);
      u.onstart = () => setPlaying(true);
      u.onend = finishSpeaking;
      // An utterance that cannot be spoken still ends the slide, rather than
      // stranding a Suitcase deck on it.
      u.onerror = finishSpeaking;
      utteranceRef.current = u;
      s.speak(u);
    } else {
      setPlaying(true);
      speakTimerRef.current = setTimeout(finishSpeaking, expectedRef.current * 1000);
    }
  }, [finishSpeaking]);

  const stop = useCallback(() => {
    clearSpeakTimer();
    if (dwellTimerRef.current !== null) {
      clearTimeout(dwellTimerRef.current);
      dwellTimerRef.current = null;
    }
    // Only an utterance THIS hook started is cancelled, and its handlers are
    // detached first: cancel() fires the old utterance's end/error, which
    // would otherwise start a dwell on the slide just arrived at.
    const u = utteranceRef.current;
    if (u) {
      u.onstart = null;
      u.onend = null;
      u.onerror = null;
      utteranceRef.current = null;
      synth()?.cancel();
    }
    startedRef.current = false;
    doneRef.current = false;
    elapsedRef.current = 0;
    runningSinceRef.current = null;
    dwellStartedAtRef.current = null;
    setPlaying(false);
  }, []);

  // The state machine: a new slide (text) or the mode (enabled) changing
  // starts the voice from the top, unless held -- then the hold effect below
  // starts it on release.
  useEffect(() => {
    if (!enabled || !text) {
      stop(); // eslint-disable-line react-hooks/set-state-in-effect
      return;
    }
    stop();
    expectedRef.current = speechSeconds(text);
    if (!heldRef.current) start();
    return stop;
  }, [enabled, text, silent, start, stop]);

  // Hold and release, mid-sentence. A dwell already counting is left alone,
  // as useSlideNarration leaves it: the advance it counts down to was asked for.
  useEffect(() => {
    if (!enabled || !text) return;
    const held = suspended || paused;
    if (held) {
      if (!startedRef.current || doneRef.current) return;
      if (runningSinceRef.current !== null) {
        elapsedRef.current += (Date.now() - runningSinceRef.current) / 1000;
        runningSinceRef.current = null;
      }
      const s = synth();
      if (s && utteranceRef.current) s.pause();
      else clearSpeakTimer();
      setPlaying(false);
      return;
    }
    if (!startedRef.current) {
      start();
      return;
    }
    if (doneRef.current || runningSinceRef.current !== null) return;
    runningSinceRef.current = Date.now();
    const s = synth();
    if (s && utteranceRef.current) {
      s.resume();
    } else {
      const remaining = Math.max(0, expectedRef.current - elapsedRef.current);
      speakTimerRef.current = setTimeout(finishSpeaking, remaining * 1000);
    }
    setPlaying(true);
  }, [suspended, paused, enabled, text, start, finishSpeaking]);

  useEffect(() => stop, [stop]);

  const toggle = useCallback(() => {
    setEnabled((on) => !on);
    setPaused(false);
  }, []);
  const togglePause = useCallback(() => setPaused((p) => !p), []);

  const getSlideProgress = useCallback(() => {
    const expected = expectedRef.current;
    if (!startedRef.current || expected <= 0) return 0;
    const total = expected + SLIDE_DWELL_SECONDS;
    if (doneRef.current) {
      const since = dwellStartedAtRef.current;
      const dwell = since === null ? 0 : Math.min((Date.now() - since) / 1000, SLIDE_DWELL_SECONDS);
      return Math.min(1, (expected + dwell) / total);
    }
    const running =
      runningSinceRef.current === null ? 0 : (Date.now() - runningSinceRef.current) / 1000;
    return Math.min(elapsedRef.current + running, expected) / total;
  }, []);

  return {
    available: !!text,
    enabled,
    playing,
    toggle,
    paused,
    togglePause,
    getSlideProgress,
  };
}
