import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { DeckPlayer } from "./DeckPlayer";
import { Say } from "./PresenterNoteKit";
import { SLIDE_DWELL_SECONDS } from "./deckDuration";
import { NARRATION_VOICES } from "./narrationConstants";
import { slideSpokenText } from "./sayText";
import { speechSeconds } from "./useSpeechNarration";
import type { Deck, Slide } from "../decks/types";

// The audiobook hint (decks/types.ts `audiobook`; docs/modules/solitaire-agile.md,
// "The played view"): Suitcase Mode at any width, prev and next kept beside the
// transport, and the browser's voice reading a slide's Say text when it has no
// clip. Everything here is about a deck that SETS the hint, plus the one
// assertion that a deck which does not is untouched -- the shipped decks'
// own behaviour stays pinned by DeckPlayer.test.tsx, which this file does not
// edit.

class BroadcastChannelStub {
  onmessage: ((e: MessageEvent) => void) | null = null;
  constructor(public name: string) {}
  postMessage() {}
  close() {}
}

class AudioStub {
  onplay: (() => void) | null = null;
  onpause: (() => void) | null = null;
  onended: (() => void) | null = null;
  onerror: (() => void) | null = null;
  src = "";
  paused = true;
  currentTime = 0;
  ended = false;
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

/** Desktop width: no media query matches (useCompactLayout reads max-width). */
function installDesktopMatchMedia() {
  (globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
    matches: false,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  });
}

beforeAll(() => {
  (globalThis as unknown as { BroadcastChannel: unknown }).BroadcastChannel = BroadcastChannelStub;
  (globalThis as unknown as { Audio: unknown }).Audio = AudioStub;
});

beforeEach(() => {
  installDesktopMatchMedia();
  jest.useFakeTimers();
});
afterEach(() => {
  jest.useRealTimers();
  delete (window as unknown as { speechSynthesis?: unknown }).speechSynthesis;
  delete (globalThis as unknown as { SpeechSynthesisUtterance?: unknown }).SpeechSynthesisUtterance;
});

const slides: Slide[] = [
  { id: "a1", title: "One", copy: <p>one</p>, notes: <Say>The first tile speaks.</Say> },
  { id: "a2", title: "Two", copy: <p>two</p>, notes: <Say>The second tile speaks.</Say> },
  { id: "a3", title: "Three", copy: <p>three</p>, notes: <Say>The queue again.</Say> },
];

function deckOf(audiobook: boolean): Deck {
  return { id: "book", title: "Book", summary: "", slides: () => slides, audiobook };
}

/** The ritual host's wiring: one voice, "live" (hasApi), and no clip anywhere. */
function mount(audiobook: boolean) {
  const deck = deckOf(audiobook);
  return render(
    <MemoryRouter>
      <DeckPlayer
        deckId="book"
        deck={deck}
        slides={slides}
        mode="audience"
        voices={NARRATION_VOICES.slice(0, 1)}
        hasApi
        resolveNarrationUrl={() => null}
        narrateByDefault
        suitcaseMode
      />
    </MemoryRouter>,
  );
}

const counterless = () => screen.queryByText(/\d+ \/ 3/);
const onSlide = (title: string) => screen.getByText(title.toLowerCase());

describe("an audiobook deck -- Suitcase on the desktop", () => {
  it("draws the transport at desktop width, with prev and next beside it", () => {
    mount(true);
    expect(screen.getByRole("button", { name: "Pause" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Previous slide" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Next slide" })).toBeTruthy();
    // The transport replaced the counter, as Suitcase always does.
    expect(counterless()).toBeNull();
  });

  it("next and prev page by hand without leaving the mode", () => {
    mount(true);
    fireEvent.click(screen.getByRole("button", { name: "Next slide" }));
    expect(onSlide("Two")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Previous slide" }));
    expect(onSlide("One")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Pause" })).toBeTruthy();
  });

  it("the same wiring WITHOUT the hint keeps the desktop rule: paging arrows, no transport", () => {
    mount(false);
    expect(screen.queryByRole("button", { name: "Pause" })).toBeNull();
    expect(screen.getByText("1 / 3")).toBeTruthy();
  });
});

describe("an audiobook deck -- the voice", () => {
  it("with no speech API, a slide lives for its read time plus the dwell, silently, then advances", () => {
    mount(true);
    const seconds = speechSeconds(slideSpokenText(slides[0]));
    act(() => {
      jest.advanceTimersByTime(seconds * 1000);
    });
    expect(onSlide("One")).toBeTruthy();
    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });
    expect(onSlide("Two")).toBeTruthy();
  });

  it("pause holds the slide; play resumes it", () => {
    mount(true);
    fireEvent.click(screen.getByRole("button", { name: "Pause" }));
    act(() => {
      jest.advanceTimersByTime(120 * 1000);
    });
    expect(onSlide("One")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Play" }));
    act(() => {
      jest.advanceTimersByTime(
        (speechSeconds(slideSpokenText(slides[0])) + SLIDE_DWELL_SECONDS) * 1000,
      );
    });
    expect(onSlide("Two")).toBeTruthy();
  });

  it("with speechSynthesis, reads the slide's title and Say text, and advances on its end", () => {
    const spoken: { text: string; onend: (() => void) | null }[] = [];
    class Utterance {
      onstart: (() => void) | null = null;
      onend: (() => void) | null = null;
      onerror: (() => void) | null = null;
      constructor(public text: string) {}
    }
    (globalThis as unknown as { SpeechSynthesisUtterance: unknown }).SpeechSynthesisUtterance =
      Utterance;
    (window as unknown as { speechSynthesis: unknown }).speechSynthesis = {
      speak: (u: Utterance) => spoken.push(u),
      cancel: jest.fn(),
      pause: jest.fn(),
      resume: jest.fn(),
    };
    mount(true);
    expect(spoken.map((u) => u.text)).toEqual(["One. The first tile speaks."]);
    act(() => {
      spoken[0].onend?.();
    });
    act(() => {
      jest.advanceTimersByTime(SLIDE_DWELL_SECONDS * 1000);
    });
    expect(onSlide("Two")).toBeTruthy();
    expect(spoken.map((u) => u.text)).toEqual([
      "One. The first tile speaks.",
      "Two. The second tile speaks.",
    ]);
  });

  it("a deck without the hint never reaches speechSynthesis", () => {
    const synth = { speak: jest.fn(), cancel: jest.fn(), pause: jest.fn(), resume: jest.fn() };
    (globalThis as unknown as { SpeechSynthesisUtterance: unknown }).SpeechSynthesisUtterance =
      class {};
    (window as unknown as { speechSynthesis: unknown }).speechSynthesis = synth;
    const { unmount } = mount(false);
    fireEvent.click(screen.getByRole("button", { name: "Next slide" }));
    unmount();
    expect(synth.speak).not.toHaveBeenCalled();
    expect(synth.cancel).not.toHaveBeenCalled();
  });
});
