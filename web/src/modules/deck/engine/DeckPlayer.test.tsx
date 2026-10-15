import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { webDarkTheme } from "@fluentui/react-components";
import { DeckPlayer } from "./DeckPlayer";
import { darkTheme } from "../../../shell/theme";
import { SLIDE_DWELL_SECONDS } from "./deckDuration";
import { NARRATION_VOICES, NO_NARRATION_TITLE, VOICE_PICKER_TITLE } from "./narrationConstants";
import type { Slide } from "../decks/types";

// The consolidation contract, pinned at the component seam. DeckPlayer is the
// ONE player both apps mount (web's PresentationDeck and Wasteland's
// WastelandDeck) — the two hosts diverge only in the facts they pass, and
// `mode` owns the differences:
//
//   presenter — web's only mode. The notes surface is available; in-player
//     Voice/mute NEVER renders, even when a host wires voices, because the
//     presenter's own voice is the point and a synthesized one would compete.
//   audience — Wasteland's sofa. Voice controls render; no notes surface
//     exists AT ALL (absent, not hidden — nothing to escalate to on a link
//     someone shared with you).
//
// If a future consolidation collapses the hosts onto this player, these tests
// are what keeps web from silently growing audience controls (or the audience
// from growing a presenter escalation). The theme test pins the third shared
// fact: the player's chrome defaults to plain webDarkTheme — neither host's
// brand follows a deck in.

// jsdom has no BroadcastChannel (useDeckController's cross-window sync); a
// silent stub is enough — cross-window behavior is Playwright's job.
class BroadcastChannelStub {
  onmessage: ((e: MessageEvent) => void) | null = null;
  constructor(public name: string) {}
  postMessage() {}
  close() {}
}

// jsdom's HTMLMediaElement can't play. The stub mirrors the real element's
// shape closely enough for the hook's state machine: constructed ONCE with no
// src (useSlideNarration reuses one element and retargets .src per slide, to
// keep iOS's gesture blessing), then driven by assigning .src and calling
// play(). `audioInstances` lets a test reach the live element and fire "ended".
const audioInstances: AudioStub[] = [];
class AudioStub {
  onplay: (() => void) | null = null;
  onpause: (() => void) | null = null;
  onended: (() => void) | null = null;
  onerror: (() => void) | null = null;
  // Modelled because suspend/resume depends on them. `src` is a real setter:
  // assigning a new source RESETS currentTime and clears `ended`, exactly as
  // the DOM does. A plain field here would leave a stale currentTime behind
  // and hide the bug where switching voice mid-suspend leaves the deck paused
  // on a clip that never started.
  #src = "";
  get src() {
    return this.#src;
  }
  set src(next: string) {
    if (next === this.#src) return;
    this.#src = next;
    this.currentTime = 0;
    this.ended = false;
  }
  paused = true;
  currentTime = 0;
  ended = false;
  constructor() {
    audioInstances.push(this);
  }
  play() {
    this.paused = false;
    this.onplay?.();
    return Promise.resolve();
  }
  pause() {
    this.paused = true;
    this.onpause?.();
  }
}

// jsdom has no matchMedia, which is why useCompactLayout reports desktop in
// tests. This stub lets a test choose a width — and RESIZE mid-mount, which is
// the only way to exercise Suitcase Mode's breakpoint behaviour.
//
// Listeners are keyed by their query and handed a real event-shaped object when
// fired: useCompactLayout reads `event.matches`, and so does Fluent's own
// useIsReducedMotion, which subscribes from inside the component tree and
// throws on a bare call. The stub has to behave like matchMedia for everything
// in the tree, not just for the code under test.
let viewportIsCompact = false;
type Listener = (event: { matches: boolean; media: string }) => void;
const viewportListeners = new Map<Listener, string>();

/** What a given media query evaluates to at the current stubbed width. */
function queryMatches(query: string): boolean {
  // useCompactLayout asks (max-width: 575px) — true only on a phone.
  if (query.includes("max-width")) return viewportIsCompact;
  // Everything else (prefers-reduced-motion, prefers-color-scheme, …) is a
  // question about the environment rather than the width — default false.
  return false;
}

function installMatchMedia() {
  (globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
    matches: queryMatches(query),
    media: query,
    addEventListener: (_: string, fn: Listener) => {
      viewportListeners.set(fn, query);
    },
    removeEventListener: (_: string, fn: Listener) => {
      viewportListeners.delete(fn);
    },
  });
}

function setViewport(kind: "compact" | "desktop") {
  viewportIsCompact = kind === "compact";
  installMatchMedia();
  // Let anything already mounted observe the change, the way a real resize
  // does. Copied before iterating: a listener that re-subscribes mid-loop
  // would otherwise mutate the map being walked.
  act(() => {
    [...viewportListeners].forEach(([fn, query]) => {
      fn({ matches: queryMatches(query), media: query });
    });
  });
}

// jsdom implements neither PointerEvent nor setPointerCapture, and both gaps
// fail SILENTLY in a way that looks like a working feature: without the
// constructor, fireEvent.pointerDown builds a plain Event whose isPrimary and
// clientX are undefined, so every synthesized swipe is discarded and the "must
// not page" assertions all pass for the wrong reason.
class PointerEventStub extends MouseEvent {
  pointerId: number;
  isPrimary: boolean;
  constructor(type: string, init: PointerEventInit = {}) {
    super(type, init);
    this.pointerId = init.pointerId ?? 0;
    this.isPrimary = init.isPrimary ?? true;
  }
}

beforeAll(() => {
  (globalThis as unknown as { BroadcastChannel: unknown }).BroadcastChannel = BroadcastChannelStub;
  (globalThis as unknown as { Audio: unknown }).Audio = AudioStub;
  if (!("PointerEvent" in globalThis)) {
    (globalThis as unknown as { PointerEvent: unknown }).PointerEvent = PointerEventStub;
    (globalThis as unknown as { window: { PointerEvent: unknown } }).window.PointerEvent =
      PointerEventStub;
  }
  // A no-op is the honest stub: capture only affects WHERE later events are
  // delivered, and these tests fire both ends at the same element anyway.
  Element.prototype.setPointerCapture ??= function setPointerCapture() {};
  Element.prototype.releasePointerCapture ??= function releasePointerCapture() {};
});

beforeEach(() => {
  audioInstances.length = 0;
  viewportListeners.clear();
  setViewport("desktop");
});

const slides: Slide[] = [
  { id: "s1", copy: null },
  { id: "s2", copy: null },
];

/** Every slide baked in every voice — narration is fully wired and covered. */
const allBaked = (slide: Slide, voiceId: string) => `/voices/fake-deck/${slide.id}-${voiceId}.mp3`;

/** Mount the shared player exactly as a host would, with narration wired. */
function mountPlayer(
  mode: "presenter" | "audience",
  extra?: {
    narrateByDefault?: boolean;
    suitcaseMode?: boolean;
    resolveNarrationUrl?: (slide: Slide, voiceId: string) => string | null;
  },
) {
  return render(
    <MemoryRouter>
      <DeckPlayer
        deckId="fake-deck"
        slides={slides}
        mode={mode}
        voices={NARRATION_VOICES}
        hasApi={false}
        resolveNarrationUrl={extra?.resolveNarrationUrl ?? allBaked}
        narrateByDefault={extra?.narrateByDefault}
        suitcaseMode={extra?.suitcaseMode}
      />
    </MemoryRouter>,
  );
}

describe("DeckPlayer — mode owns the host differences", () => {
  it("audience: voice controls render, the notes surface does not exist", () => {
    mountPlayer("audience");

    expect(screen.getByTitle("Play with narration")).toBeTruthy();
    expect(screen.getByTitle(VOICE_PICKER_TITLE)).toBeTruthy();
    // Absent, not disabled — an audience window has nothing to escalate to.
    expect(screen.queryByTitle("Open speaker notes")).toBeNull();
  });

  it("presenter: the notes surface renders, voice controls never do — even fully wired", () => {
    // SAME narration wiring as the audience mount above. Locking a host into
    // presenter mode must drop the in-player voice group entirely, not merely
    // disable it: mode owns this, not the presence of the props.
    mountPlayer("presenter");

    expect(screen.getByTitle("Open speaker notes")).toBeTruthy();
    expect(screen.queryByTitle("Play with narration")).toBeNull();
    expect(screen.queryByTitle(VOICE_PICKER_TITLE)).toBeNull();
    // Not even the disabled/empty variant of the group:
    expect(screen.queryByTitle(NO_NARRATION_TITLE)).toBeNull();
  });
});

describe("DeckPlayer — Suitcase Mode", () => {
  // Which slide the deck is on. Suitcase Mode REPLACES the counter with its
  // one-button transport (that's the point of the mode), so there's no "1 / 2"
  // to read — the live element's src is the honest signal, since the player
  // retargets it per slide from the resolved narration URL.
  const currentSlideId = () => {
    const src = audioInstances[audioInstances.length - 1]?.src ?? "";
    return src.match(/\/(s\d+)-/)?.[1] ?? "";
  };

  /** Fire the live element's "ended", then run out the post-clip dwell. */
  function endCurrentClip() {
    const audio = audioInstances[audioInstances.length - 1];
    act(() => {
      audio.onended?.();
    });
    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });
  }

  // Suitcase Mode is mobile-only, so these run phone-width unless a test says
  // otherwise. Asserting auto-advance from a desktop mount would be asserting
  // behaviour the feature is not supposed to have.
  beforeEach(() => {
    jest.useFakeTimers();
    setViewport("compact");
  });
  afterEach(() => jest.useRealTimers());

  it("advances to the next slide a dwell after the clip ends", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    expect(currentSlideId()).toBe("s1");

    endCurrentClip();

    expect(currentSlideId()).toBe("s2");
  });

  it("waits out the dwell — it does not advance the instant audio stops", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    act(() => {
      audioInstances[audioInstances.length - 1].onended?.();
    });
    expect(currentSlideId()).toBe("s1");

    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });
    expect(currentSlideId()).toBe("s2");
  });

  it("stops at the last slide rather than running off the end", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    endCurrentClip(); // 1 -> 2
    expect(currentSlideId()).toBe("s2");

    endCurrentClip(); // stepNext clamps; no third slide to reach
    expect(currentSlideId()).toBe("s2");
  });

  it("off by default: a clip ending does not advance anything", () => {
    mountPlayer("audience", { narrateByDefault: true });

    endCurrentClip();

    expect(currentSlideId()).toBe("s1");
  });

  it("reuses ONE audio element across slides (the iOS gesture blessing)", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    endCurrentClip();

    // Two slides played, one element — a fresh `new Audio()` per slide would
    // start each slide unblessed and get muted by the autoplay policy.
    expect(audioInstances).toHaveLength(1);
    expect(audioInstances[0].src).toContain("s2");
  });

  it("desktop: does not auto-advance, even with the preference on", () => {
    // Suitcase Mode is a mobile affordance — the desktop chrome shows ordinary
    // paging arrows, so a deck advancing on its own here would be moving with
    // nothing on screen explaining why. Widening past the breakpoint has to
    // stop the advance, not merely re-skin the chrome around it.
    setViewport("desktop");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    endCurrentClip();

    expect(currentSlideId()).toBe("s1");
  });

  it("resized wide mid-slide and back: catches up instead of stranding", () => {
    // Suitcase Mode on a phone, widen past the breakpoint (which un-arms
    // auto-advance), the clip finishes while wide, then narrow back. The
    // "ended" that should have advanced the deck fired into nothing and is
    // long gone, so re-arming has to act on the slide being SPENT — otherwise
    // the deck sits on a finished slide showing a Pause button, playing
    // nothing, advancing never.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    expect(currentSlideId()).toBe("s1");

    setViewport("desktop");
    endCurrentClip();
    expect(currentSlideId()).toBe("s1");

    setViewport("compact");

    expect(currentSlideId()).toBe("s2");
  });

  it("opening the settings sheet holds playback, closing resumes", () => {
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true });
    const audio = audioInstances[audioInstances.length - 1];
    audio.currentTime = 3;
    expect(audio.paused).toBe(false);

    fireEvent.click(screen.getByLabelText("Settings"));
    // A voice reading over you while you're trying to read a switch is rude.
    expect(audio.paused).toBe(true);

    fireEvent.click(screen.getByLabelText("Close voice controls"));
    // Resumed, and from where it left off rather than restarting the sentence.
    expect(audio.paused).toBe(false);
    expect(audio.currentTime).toBe(3);
  });

  it("stays held when the deck re-renders under an open sheet", () => {
    // The main narration effect re-runs on slide/voice changes AND whenever
    // its `stop` callback is re-created, calling play() each time. The suspend
    // effect has already run by then and won't run again, so a re-render while
    // the sheet is open used to start the voice talking underneath it.
    // Suitcase Mode reaches this on its own — the deck can auto-advance to a
    // new slide while the sheet sits open.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    const audio = audioInstances[audioInstances.length - 1];
    audio.currentTime = 3;

    fireEvent.click(screen.getByLabelText("Settings"));
    expect(audio.paused).toBe(true);

    act(() => {
      audio.onended?.();
    });
    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });

    expect(audio.paused).toBe(true);
  });

  it("switching voice while held plays the new one on close", () => {
    // Changing voice mid-suspend swaps the element's src, so it sits at
    // currentTime 0 with the guard blocking play(). A resume that only handled
    // "mid-clip" left the deck silently paused on a clip that never started —
    // recoverable only by toggling narration off and on again.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true });
    const audio = audioInstances[audioInstances.length - 1];
    audio.currentTime = 3;

    fireEvent.click(screen.getByLabelText("Settings"));
    expect(audio.paused).toBe(true);

    const other = NARRATION_VOICES.find((v) => !audio.src.includes(v.id))!;
    fireEvent.click(screen.getByRole("radio", { name: new RegExp(other.name) }));
    expect(audio.src).toContain(other.id);

    fireEvent.click(screen.getByLabelText("Close voice controls"));

    expect(audio.paused).toBe(false);
  });

  it("nothing baked: no transport bar to strand the reader on", () => {
    // A deck with no clips and no synthesizer. Suitcase Mode asked for the
    // one-button transport, but with nothing to play it would be a dead button
    // where the paging arrows used to be — leaving no way through the deck.
    setViewport("compact");
    mountPlayer("audience", {
      narrateByDefault: true,
      suitcaseMode: true,
      resolveNarrationUrl: () => null,
    });

    expect(screen.queryByLabelText(/^(Play|Pause)$/)).toBeNull();
    expect(audioInstances).toHaveLength(0);
  });

  it("switching Narration off in the sheet hands back the paging controls", () => {
    // The bus repro this pins: Suitcase on, narrated deck, phone width. Flip
    // the sheet's Narration switch off and close. "Requires narration, both
    // directions" holds at the SESSION layer too, not just the stored prefs —
    // a silent viewing has no clip-ends to advance on, so the transport must
    // give way to the arrows. It used to stay: a play button over a deck that
    // would never move, with no way to page by hand.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    expect(screen.getByLabelText(/^(Play|Pause)$/)).toBeTruthy();

    fireEvent.click(screen.getByLabelText("Settings"));
    fireEvent.click(screen.getByRole("switch", { name: "Narration" }));
    fireEvent.click(screen.getByLabelText("Close voice controls"));

    expect(screen.queryByLabelText(/^(Play|Pause)$/)).toBeNull();
    expect(screen.getByLabelText("Next slide")).toBeTruthy();
  });

  it("transport pause is a hold — the transport stays", () => {
    // Pause and silent are different acts on the same quiet. Pause holds
    // playback with narration still ON, so the bar keeps its one button (now
    // showing Play) — if pausing flipped the narration mode instead, the
    // session gate above would swap the transport for paging arrows under the
    // thumb that pressed it.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    const audio = audioInstances[audioInstances.length - 1];
    audio.currentTime = 3;
    expect(audio.paused).toBe(false);

    fireEvent.click(screen.getByLabelText("Pause"));
    expect(audio.paused).toBe(true);
    expect(screen.queryByLabelText("Next slide")).toBeNull();

    fireEvent.click(screen.getByLabelText("Play"));
    // Resumed from where it was held, not restarted.
    expect(audio.paused).toBe(false);
    expect(audio.currentTime).toBe(3);
  });

  it("a paused transport does not survive Narration off → on", () => {
    // Flipping Narration back on is a request to HEAR the deck. A pause
    // pressed during some earlier narrated stretch must not outlive the mode
    // change — honoring it would leave the deck silently stopped behind a
    // switch claiming it reads aloud, with a Play button as the only clue.
    setViewport("compact");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    const audio = audioInstances[audioInstances.length - 1];

    fireEvent.click(screen.getByLabelText("Pause"));
    expect(audio.paused).toBe(true);

    fireEvent.click(screen.getByLabelText("Settings"));
    const narrationSwitch = () => screen.getByRole("switch", { name: "Narration" });
    fireEvent.click(narrationSwitch()); // off
    fireEvent.click(narrationSwitch()); // on again
    fireEvent.click(screen.getByLabelText("Close voice controls"));

    expect(audio.paused).toBe(false);
  });
});

describe("DeckPlayer — swipe paging", () => {
  // What the gesture must never do is disturb Suitcase Mode's auto-advance.
  // These pin the seam: a swipe goes through the controller's own stepNext/stepPrev
  // — the same path the arrows and arrow keys use — so the dwell timer, the
  // clip restart and the transport hold all behave exactly as they do for a
  // manual page. If someone reimplements the gesture against narration state
  // directly, these fail.
  const currentSlideId = () => {
    const src = audioInstances[audioInstances.length - 1]?.src ?? "";
    return src.match(/\/(s\d+)-/)?.[1] ?? "";
  };

  /** The slide area — the one swipe target, wrapping SlideRenderer. */
  const slideSurface = () => document.querySelector("[data-swipe-surface]")!;

  /** One gesture, start to finish, in the shape the hook reads. */
  function drag(
    el: Element,
    {
      dx,
      dy = 0,
      ms = 200,
      pointerId = 1,
    }: { dx: number; dy?: number; ms?: number; pointerId?: number },
  ) {
    act(() => {
      fireEvent.pointerDown(el, {
        pointerId,
        isPrimary: true,
        button: 0,
        clientX: 200,
        clientY: 400,
      });
      fireEvent.pointerUp(el, {
        pointerId,
        isPrimary: true,
        button: 0,
        clientX: 200 + dx,
        clientY: 400 + dy,
      });
    });
    // The gesture's clock is event.timeStamp, which jsdom stamps from the real
    // clock — under fake timers both events land at the same instant, so a
    // gesture is instantaneous unless a test says otherwise. `ms` documents the
    // intent; the duration rule is exercised in its own test below.
    void ms;
  }

  beforeEach(() => {
    jest.useFakeTimers();
    setViewport("compact");
  });
  afterEach(() => jest.useRealTimers());

  it("a left swipe pages forward, a right swipe pages back", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    expect(currentSlideId()).toBe("s1");

    drag(slideSurface(), { dx: -120 });
    expect(currentSlideId()).toBe("s2");

    drag(slideSurface(), { dx: 120 });
    expect(currentSlideId()).toBe("s1");
  });

  it("one target reads BOTH directions — travel decides, not which half was touched", () => {
    // The whole reason there's no left-zone/right-zone: direction is the sign
    // of dx. Both gestures below start at the same x; only the travel differs.
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    const surface = slideSurface();

    drag(surface, { dx: -120 });
    expect(currentSlideId()).toBe("s2");
    drag(surface, { dx: 120 });
    expect(currentSlideId()).toBe("s1");
  });

  it("ignores a vertical drag — that's a scroll, not a page turn", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    drag(slideSurface(), { dx: -60, dy: 200 });

    expect(currentSlideId()).toBe("s1");
  });

  it("ignores a short drag — that's a tap", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    drag(slideSurface(), { dx: -20 });

    expect(currentSlideId()).toBe("s1");
  });

  it("desktop: no swipe handlers at all", () => {
    setViewport("desktop");
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    drag(slideSurface(), { dx: -120 });

    expect(currentSlideId()).toBe("s1");
  });

  it("swiping mid-dwell does not double-advance", () => {
    // THE invariant. The clip ends and a dwell timer is queued to advance the
    // deck; the reader swipes during that gap. Without stop()'s timer cancel
    // the queued stepNext lands on top of the swipe's and the deck jumps two.
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    expect(currentSlideId()).toBe("s1");

    act(() => {
      audioInstances[audioInstances.length - 1].onended?.();
    });
    // Mid-dwell: clip spent, advance still pending.
    expect(currentSlideId()).toBe("s1");

    drag(slideSurface(), { dx: -120 });
    expect(currentSlideId()).toBe("s2");

    // Run the dwell out. The queued advance must be gone, not merely late.
    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });
    expect(currentSlideId()).toBe("s2");
  });

  it("auto-advance still works after a swipe", () => {
    // The other half of the invariant: cancelling the queued advance must not
    // leave the mode dead. The swiped-to slide plays, ends, and advances on
    // its own like any other.
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    drag(slideSurface(), { dx: 120 }); // clamped at the first slide
    expect(currentSlideId()).toBe("s1");

    endCurrentClipOn(audioInstances);

    expect(currentSlideId()).toBe("s2");
  });

  it("a swipe restarts the new slide's clip from the beginning", () => {
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });
    const audio = audioInstances[0];
    audio.currentTime = 12;

    drag(slideSurface(), { dx: -120 });

    expect(audio.src).toContain("s2");
    expect(audio.currentTime).toBe(0);
  });

  it("a gesture starting on a control INSIDE the slide belongs to the control", () => {
    // Slides carry their own links and buttons (a deck's give-away repo link,
    // for one), and those sit inside the swipe surface. A drag begun on one
    // is that control's gesture, not a page turn.
    //
    // Note the player's own chrome is NOT what this protects: DeckChrome is a
    // SIBLING of the swipe surface, so Suitcase Mode's transport is already
    // out of reach structurally. This guard is for controls in slide content.
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    const link = document.createElement("button");
    link.textContent = "in-slide control";
    slideSurface().appendChild(link);

    act(() => {
      fireEvent.pointerDown(link, {
        pointerId: 1,
        isPrimary: true,
        button: 0,
        clientX: 200,
        clientY: 400,
      });
      fireEvent.pointerUp(link, {
        pointerId: 1,
        isPrimary: true,
        button: 0,
        clientX: 60,
        clientY: 400,
      });
    });

    expect(currentSlideId()).toBe("s1");
  });

  it("the player's own chrome sits outside the swipe surface", () => {
    // Structural guarantee behind the note above — if a refactor ever moved
    // DeckChrome inside the wrapper, a drag off the transport button would
    // start paging the deck and only the guard above would stand between.
    mountPlayer("audience", { narrateByDefault: true, suitcaseMode: true });

    expect(slideSurface().contains(screen.getByLabelText("Pause"))).toBe(false);
  });
});

/** Fire the live element's "ended", then run out the post-clip dwell. */
function endCurrentClipOn(instances: { onended: (() => void) | null }[]) {
  const audio = instances[instances.length - 1];
  act(() => {
    audio.onended?.();
  });
  act(() => {
    jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
  });
}

describe("DeckPlayer — the shared player's chrome is host-neutral", () => {
  // FluentProvider writes its theme as CSS custom properties into injected
  // stylesheets; jsdom exposes them via document.styleSheets/style tags.
  function injectedCss(): string {
    const fromSheets = Array.from(document.styleSheets)
      .flatMap((sheet) => {
        try {
          return Array.from(sheet.cssRules);
        } catch {
          return [];
        }
      })
      .map((rule) => rule.cssText)
      .join("\n");
    const fromTags = Array.from(document.querySelectorAll("style"))
      .map((el) => el.textContent ?? "")
      .join("\n");
    return fromSheets + fromTags;
  }

  it("defaults to plain webDarkTheme, not web's branded presenter theme", () => {
    mountPlayer("presenter");

    const css = injectedCss();
    // The neutral default is actually applied...
    expect(css).toContain(webDarkTheme.colorBrandBackground);
    // ...and web's indigo brand did not follow the deck in.
    expect(css).not.toContain(darkTheme.colorBrandBackground);
  });
});

// The host's one seam into navigation. Everything below exists because a
// watch-history feature is built on this callback, and two of the failure
// modes here are silent and permanent rather than loud: a progress bar that
// reads 100% forever, or a deck that never records at all.
describe("DeckPlayer — onAfterSlideNavCallback", () => {
  /** n slides, ids s1..sn. */
  const deckOf = (n: number): Slide[] =>
    Array.from({ length: n }, (_, i) => ({ id: `s${i + 1}`, copy: null }));

  /** The player wired exactly as a host wires it, re-renderable in place. */
  function mountWithCallback(
    deckId: string,
    deckSlides: Slide[],
    onAfterSlideNavCallback?: (slideIndex: number, totalSlides: number) => void,
  ) {
    const ui = (id: string, s: Slide[], cb?: (slideIndex: number, totalSlides: number) => void) => (
      <MemoryRouter>
        <DeckPlayer deckId={id} slides={s} mode="audience" onAfterSlideNavCallback={cb} />
      </MemoryRouter>
    );
    const view = render(ui(deckId, deckSlides, onAfterSlideNavCallback));
    return {
      ...view,
      /** Re-render WITHOUT unmounting — what a route param change does. */
      rerenderWith: (
        id: string,
        s: Slide[],
        cb?: (slideIndex: number, totalSlides: number) => void,
      ) => view.rerender(ui(id, s, cb)),
    };
  }

  it("fires on mount at slide 0, and again on each navigation", () => {
    const onNav = jest.fn();
    mountWithCallback("deck-a", deckOf(3), onNav);

    // Arriving at a deck counts as having started it.
    expect(onNav).toHaveBeenCalledWith(0, 3);

    onNav.mockClear();
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    expect(onNav).toHaveBeenCalledWith(1, 3);

    onNav.mockClear();
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowLeft" });
    });
    // Paging BACKWARD reports too — the engine reports position, and what a
    // high-water mark does with that is the host's business, not this one's.
    expect(onNav).toHaveBeenCalledWith(0, 3);
  });

  it("omitting the prop changes nothing", () => {
    expect(() => {
      mountWithCallback("deck-a", deckOf(3));
      act(() => {
        fireEvent.keyDown(window, { key: "ArrowRight" });
      });
    }).not.toThrow();
  });

  // THE case. WastelandDeck routes at /decks/:deckId and does not remount when
  // only the param changes, so a deck-to-deck navigation commits one render
  // carrying the OUTGOING deck's slideIndex beside the INCOMING deck's slide
  // count. Reporting that pair would attribute deck A's index to deck B, and
  // because a host records a high-water mark, deck B would read as fully
  // watched forever after.
  it("never reports the outgoing deck's index against the incoming deck", () => {
    const onNav = jest.fn();
    const view = mountWithCallback("deck-a", deckOf(8), onNav);

    // Page deep into deck A.
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    expect(onNav).toHaveBeenCalledWith(5, 8);

    onNav.mockClear();
    act(() => {
      view.rerenderWith("deck-b", deckOf(3), onNav);
    });

    // The corrupted pairing: deck A's index 5 against deck B's 3 slides.
    expect(onNav).not.toHaveBeenCalledWith(5, 3);
    // And the correct arrival did happen.
    expect(onNav).toHaveBeenCalledWith(0, 3);
  });

  // The second half of that fix, and the reason the guard FIRES rather than
  // returning early. If the outgoing deck was already on slide 0, the
  // controller's reset effect sets slideIndex to the value it already holds,
  // React bails out of the re-render, and a skip-and-wait guard would never
  // run again — the incoming deck would go unrecorded entirely. Deleting this
  // test is how that hole gets quietly reopened.
  it("reports the incoming deck even when the outgoing deck was on slide 0", () => {
    const onNav = jest.fn();
    const view = mountWithCallback("deck-a", deckOf(8), onNav);
    expect(onNav).toHaveBeenCalledWith(0, 8);

    onNav.mockClear();
    act(() => {
      view.rerenderWith("deck-b", deckOf(3), onNav);
    });

    expect(onNav).toHaveBeenCalledWith(0, 3);
  });

  // The case the naive fix — reusing the existing slide-change broadcast
  // effect, whose deps are [slideIndex, slides.length] — would silently miss:
  // with equal slide counts, neither dep appears to change on the switch.
  it("reports a switch between two decks of the same length", () => {
    const onNav = jest.fn();
    const view = mountWithCallback("deck-a", deckOf(4), onNav);

    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    onNav.mockClear();

    act(() => {
      view.rerenderWith("deck-b", deckOf(4), onNav);
    });

    expect(onNav).toHaveBeenCalledWith(0, 4);
  });

  // Not about the callback at all — about the commit the callback exposed.
  // The same render that carries the outgoing deck's slideIndex beside the
  // incoming deck's slides also DRAWS, and slides[5] of a 3-slide deck is
  // undefined. This crashed the player (SlideRenderer dereferences it) before
  // useDeckController began clamping the index it hands back, and it is
  // reachable with no callback in sight — browser back/forward between two
  // deck URLs never remounts the route element.
  it("survives switching to a shorter deck while paged past its end", () => {
    const view = mountWithCallback("deck-a", deckOf(8));
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });

    expect(() => {
      act(() => {
        view.rerenderWith("deck-b", deckOf(3));
      });
    }).not.toThrow();
  });

  // Hosts pass an inline arrow (WastelandDeck does), so the prop's identity
  // changes every render. With the callback in the effect's deps this would
  // re-fire on each render — and since the host's handler writes state, that
  // is an infinite render loop, not a stray extra call. The controller reads
  // it through a ref for exactly this reason.
  it("does not re-fire when only the callback's identity changes", () => {
    const spy = jest.fn();
    const view = mountWithCallback("deck-a", deckOf(3), (i, t) => spy(i, t));
    expect(spy).toHaveBeenCalledTimes(1);

    spy.mockClear();
    // Three renders, a brand-new arrow each time, nothing else changed.
    act(() => {
      view.rerenderWith("deck-a", deckOf(3), (i, t) => spy(i, t));
    });
    act(() => {
      view.rerenderWith("deck-a", deckOf(3), (i, t) => spy(i, t));
    });
    act(() => {
      view.rerenderWith("deck-a", deckOf(3), (i, t) => spy(i, t));
    });

    expect(spy).not.toHaveBeenCalled();
  });
});

// Opening somewhere other than slide 0 — the engine half of "continue where
// you left off". The host supplies the number; the engine holds no opinion
// about where it came from.
describe("DeckPlayer — initialSlideIndex", () => {
  const deckOf = (n: number): Slide[] =>
    Array.from({ length: n }, (_, i) => ({ id: `s${i + 1}`, copy: null }));

  function mountAt(
    deckId: string,
    deckSlides: Slide[],
    initialSlideIndex: number,
    onNav?: (slideIndex: number, totalSlides: number) => void,
  ) {
    const ui = (id: string, s: Slide[], initial: number) => (
      <MemoryRouter>
        <DeckPlayer
          deckId={id}
          slides={s}
          mode="audience"
          initialSlideIndex={initial}
          onAfterSlideNavCallback={onNav}
        />
      </MemoryRouter>
    );
    const view = render(ui(deckId, deckSlides, initialSlideIndex));
    return {
      ...view,
      rerenderWith: (id: string, s: Slide[], initial: number) => view.rerender(ui(id, s, initial)),
    };
  }

  it("opens on the slide the host asks for", () => {
    const onNav = jest.fn();
    mountAt("deck-a", deckOf(10), 4, onNav);
    expect(onNav).toHaveBeenCalledWith(4, 10);
  });

  it("defaults to slide 0 when the host says nothing", () => {
    const onNav = jest.fn();
    render(
      <MemoryRouter>
        <DeckPlayer
          deckId="deck-a"
          slides={deckOf(10)}
          mode="audience"
          onAfterSlideNavCallback={onNav}
        />
      </MemoryRouter>,
    );
    expect(onNav).toHaveBeenCalledWith(0, 10);
  });

  it("pages forward from where it opened, not from the start", () => {
    const onNav = jest.fn();
    mountAt("deck-a", deckOf(10), 4, onNav);
    onNav.mockClear();
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    expect(onNav).toHaveBeenCalledWith(5, 10);
  });

  // THE trap. A host computes this from its own stored progress, so recording
  // a slide change hands back a NEW initialSlideIndex on the very next render.
  // If the engine treated it as live rather than as an input at mount, every
  // step forward would snap the visitor back and the deck could not be paged
  // at all. The engine reads it through a ref for exactly this reason.
  it("ignores a changing initialSlideIndex while staying on the same deck", () => {
    const onNav = jest.fn();
    const view = mountAt("deck-a", deckOf(10), 4, onNav);

    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    onNav.mockClear();

    // The host now says "resume at 5" because it just recorded slide 5.
    act(() => {
      view.rerenderWith("deck-a", deckOf(10), 5);
    });
    act(() => {
      view.rerenderWith("deck-a", deckOf(10), 6);
    });

    // No snap-back, and no phantom navigation reported.
    expect(onNav).not.toHaveBeenCalled();

    // Still paging from where the visitor actually is.
    act(() => {
      fireEvent.keyDown(window, { key: "ArrowRight" });
    });
    expect(onNav).toHaveBeenCalledWith(6, 10);
  });

  it("clamps a resume point past the end of a deck edited shorter", () => {
    const onNav = jest.fn();
    mountAt("deck-a", deckOf(3), 19, onNav);
    // Last real slide, not a crash and not an index nothing can render.
    expect(onNav).toHaveBeenCalledWith(2, 3);
  });

  it("clamps a negative resume point to the start", () => {
    const onNav = jest.fn();
    mountAt("deck-a", deckOf(5), -3, onNav);
    expect(onNav).toHaveBeenCalledWith(0, 5);
  });

  // Deck-to-deck without a remount still lands where the host wants the NEW
  // deck opened — the arrival is reported as the resume point, not a
  // hardcoded 0, or a host would record the wrong position for it.
  it("resumes the incoming deck on a deck switch", () => {
    const onNav = jest.fn();
    const view = mountAt("deck-a", deckOf(10), 4, onNav);
    onNav.mockClear();

    act(() => {
      view.rerenderWith("deck-b", deckOf(8), 3);
    });

    expect(onNav).toHaveBeenCalledWith(3, 8);
    expect(onNav).not.toHaveBeenCalledWith(4, 8);
  });
});
