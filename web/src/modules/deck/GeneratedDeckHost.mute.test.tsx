import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { GeneratedDeckHost } from "./GeneratedDeckHost";
import { Say } from "./engine/PresenterNoteKit";
import { SLIDE_DWELL_SECONDS } from "./engine/deckDuration";
import { NARRATION_MUTED_STORAGE_KEY } from "./engine/narrationConstants";
import { slideSpokenText } from "./engine/sayText";
import { speechSeconds } from "./engine/useSpeechNarration";
import type { Deck, Slide } from "./decks/types";

// The standup's mute: a speaker toggle on the generated deck's player,
// remembered per browser. Muted, speechSynthesis is handed nothing (not even
// cancel) and nothing is requested; the slide keeps the clock it has when no
// voice is available, so the deck still advances.

class BroadcastChannelStub {
  onmessage: ((e: MessageEvent) => void) | null = null;
  constructor(public name: string) {}
  postMessage() {}
  close() {}
}

beforeAll(() => {
  (globalThis as unknown as { BroadcastChannel: unknown }).BroadcastChannel = BroadcastChannelStub;
});

const synth = { speak: jest.fn(), cancel: jest.fn(), pause: jest.fn(), resume: jest.fn() };
const fetchSpy = jest.fn();

beforeEach(() => {
  (globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
    matches: false,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  });
  jest.useFakeTimers();
  window.localStorage.clear();
  Object.values(synth).forEach((f) => f.mockClear());
  fetchSpy.mockClear();
  (globalThis as unknown as { fetch: unknown }).fetch = fetchSpy;
  (globalThis as unknown as { SpeechSynthesisUtterance: unknown }).SpeechSynthesisUtterance =
    class {
      onstart: (() => void) | null = null;
      onend: (() => void) | null = null;
      onerror: (() => void) | null = null;
      constructor(public text: string) {}
    };
  (window as unknown as { speechSynthesis: unknown }).speechSynthesis = synth;
});
afterEach(() => {
  jest.useRealTimers();
  delete (window as unknown as { speechSynthesis?: unknown }).speechSynthesis;
  delete (globalThis as unknown as { SpeechSynthesisUtterance?: unknown }).SpeechSynthesisUtterance;
});

const slides: Slide[] = [
  { id: "m1", title: "One", copy: <p>one</p>, notes: <Say>The first tile speaks.</Say> },
  { id: "m2", title: "Two", copy: <p>two</p>, notes: <Say>The second tile speaks.</Say> },
];
const deck: Deck = {
  id: "mute",
  title: "Mute",
  summary: "",
  slides: () => slides,
  audiobook: true,
};

const mount = () =>
  render(
    <MemoryRouter>
      <GeneratedDeckHost resolution={{ deck, loading: false }} />
    </MemoryRouter>,
  );

const toggle = () => screen.getByRole("button", { name: "Mute narration" });

describe("the generated deck's mute", () => {
  it("defaults to narration on: the Say line is spoken, the toggle is not pressed", () => {
    mount();
    expect(toggle().getAttribute("aria-pressed")).toBe("false");
    expect(toggle().getAttribute("title")).toBe("Mute narration");
    expect(synth.speak).toHaveBeenCalledTimes(1);
  });

  it("remembered muted: nothing is spoken, cancelled or requested on open, and the deck still advances", () => {
    window.localStorage.setItem(NARRATION_MUTED_STORAGE_KEY, "1");
    mount();
    expect(toggle().getAttribute("aria-pressed")).toBe("true");
    expect(toggle().getAttribute("title")).toBe("Unmute narration");
    act(() => {
      jest.advanceTimersByTime(
        (speechSeconds(slideSpokenText(slides[0])) + SLIDE_DWELL_SECONDS) * 1000,
      );
    });
    expect(screen.getByText("two")).toBeTruthy();
    expect(synth.speak).not.toHaveBeenCalled();
    expect(synth.cancel).not.toHaveBeenCalled();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("pressing it mutes mid-slide, remembers, and survives a reload", () => {
    const first = mount();
    expect(synth.speak).toHaveBeenCalledTimes(1);
    fireEvent.click(toggle());
    expect(toggle().getAttribute("aria-pressed")).toBe("true");
    // The sentence already in the air stops: muting is not "quiet from the next slide".
    expect(synth.cancel).toHaveBeenCalledTimes(1);
    expect(synth.speak).toHaveBeenCalledTimes(1);
    expect(window.localStorage.getItem(NARRATION_MUTED_STORAGE_KEY)).toBe("1");
    first.unmount();
    synth.speak.mockClear();
    mount();
    expect(toggle().getAttribute("aria-pressed")).toBe("true");
    expect(synth.speak).not.toHaveBeenCalled();
  });

  it("unmuting speaks the Say line again and stores it", () => {
    window.localStorage.setItem(NARRATION_MUTED_STORAGE_KEY, "1");
    mount();
    fireEvent.click(toggle());
    expect(toggle().getAttribute("aria-pressed")).toBe("false");
    expect(window.localStorage.getItem(NARRATION_MUTED_STORAGE_KEY)).toBe("0");
    expect(synth.speak).toHaveBeenCalledTimes(1);
  });

  it("is a real button in the tab order, announcing its pressed state", () => {
    mount();
    expect(toggle().tagName).toBe("BUTTON");
    expect(toggle().getAttribute("tabindex")).not.toBe("-1");
    expect(toggle().hasAttribute("disabled")).toBe(false);
    toggle().focus();
    expect(document.activeElement).toBe(toggle());
  });

  it("works with storage refused: plays, toggles for the session, does not throw", () => {
    const real = Object.getOwnPropertyDescriptor(window, "localStorage");
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() {
        throw new Error("denied");
      },
    });
    try {
      mount();
      expect(toggle().getAttribute("aria-pressed")).toBe("false");
      fireEvent.click(toggle());
      expect(toggle().getAttribute("aria-pressed")).toBe("true");
    } finally {
      if (real) Object.defineProperty(window, "localStorage", real);
    }
  });
});
