import { voiceCoverage } from "./voiceCoverage";
import { NARRATION_VOICES } from "./narrationConstants";
import type { Slide } from "../decks/types";

// The voice-availability contract, pinned. In one sentence:
//
//   A voice is offered only if it can narrate the deck END TO END on THIS host.
//
// Both halves matter and each is a real bug that shipped:
//   • "end to end" — a partly-baked voice used to be selectable, then went
//     silent mid-deck (museum-of-bugs: 9 Jenny clips, 28 slides).
//   • "on this host" — CSS Wasteland has no /api/narrate, so only committed
//     files play; the prompts web UI has one, so every voice always works there.
//     The SAME deck therefore answers differently in the two apps.
//
// Fixtures below use the real asset shapes found in web/public/voices, so these
// aren't hypotheticals — they're the decks as they actually sit on disk.

const JENNY = NARRATION_VOICES[0].id; // en-US-JennyNeural
const BRIAN = NARRATION_VOICES[1].id; // en-US-BrianNeural

function deck(slideCount: number): Slide[] {
  return Array.from({ length: slideCount }, (_, i) => ({
    id: `s${i + 1}`,
    copy: null,
  }));
}

/**
 * A resolver backed by an explicit set of "<slideId>-<voiceId>" keys — the same
 * shape as Wasteland's baked-file map, so a missing key means a missing mp3.
 */
function resolverFor(baked: Set<string>) {
  return (slide: Slide, voiceId: string) =>
    baked.has(`${slide.id}-${voiceId}`) ? `/voices/${slide.id}-${voiceId}.mp3` : null;
}

/** Bake `voice` for the first `n` slides of a `total`-slide deck. */
function bake(voice: string, n: number): string[] {
  return Array.from({ length: n }, (_, i) => `s${i + 1}-${voice}`);
}

describe("voiceCoverage — the complete-contract rule", () => {
  it("enables a voice baked for EVERY slide", () => {
    const slides = deck(5);
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set(bake(JENNY, 5))),
    });

    const jenny = coverage.voices.find((v) => v.id === JENNY)!;
    expect(jenny.available).toBe(true);
    expect(jenny.slideCount).toBe(5);
  });

  it("DISABLES a voice missing even one slide (partial bake is not an option)", () => {
    const slides = deck(5);
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      // 4 of 5 — one gap is still a gap.
      resolveUrl: resolverFor(new Set(bake(JENNY, 4))),
    });

    const jenny = coverage.voices.find((v) => v.id === JENNY)!;
    expect(jenny.available).toBe(false);
    // The count still reports how close it was, for diagnosis.
    expect(jenny.slideCount).toBe(4);
  });

  it("reports the real museum-of-bugs shape (9 Jenny / 28 slides) as unavailable", () => {
    const slides = deck(28);
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set(bake(JENNY, 9))),
    });

    expect(coverage.voices.find((v) => v.id === JENNY)!.available).toBe(false);
    expect(coverage.voices.find((v) => v.id === BRIAN)!.available).toBe(false);
    // Rule 2a: neither voice covers the deck ⇒ narration is off entirely.
    expect(coverage.hasAnyNarration).toBe(false);
  });
});

describe("voiceCoverage — one voice covered, the other not", () => {
  const slides = deck(20);
  // The garden-of-async / meet-the-team shape: Brian complete, Jenny absent.
  const coverage = voiceCoverage({
    slides,
    voices: NARRATION_VOICES,
    resolveUrl: resolverFor(new Set(bake(BRIAN, 20))),
  });

  it("disables only the uncovered voice", () => {
    expect(coverage.voices.find((v) => v.id === BRIAN)!.available).toBe(true);
    expect(coverage.voices.find((v) => v.id === JENNY)!.available).toBe(false);
  });

  it("keeps narration ON, since one voice can carry the deck", () => {
    expect(coverage.hasAnyNarration).toBe(true);
  });

  it("defaults to the covered voice, not the first-listed one", () => {
    // Jenny is NARRATION_VOICES[0] and the global default, but she can't narrate
    // this deck — starting on her would be silence out of the gate.
    expect(coverage.defaultVoiceId).toBe(BRIAN);
  });

  it("refuses a remembered preference that can't narrate this deck", () => {
    const withPref = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set(bake(BRIAN, 20))),
      preferredVoiceId: JENNY, // stored from some other deck
    });
    expect(withPref.defaultVoiceId).toBe(BRIAN);
  });

  it("honors a remembered preference that IS covered", () => {
    const bothBaked = new Set([...bake(JENNY, 20), ...bake(BRIAN, 20)]);
    const withPref = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(bothBaked),
      preferredVoiceId: BRIAN,
    });
    expect(withPref.defaultVoiceId).toBe(BRIAN);
  });
});

describe("voiceCoverage — both voices fully baked (owasp-threat-codex)", () => {
  it("enables both and picks the global default", () => {
    const slides = deck(30);
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set([...bake(JENNY, 30), ...bake(BRIAN, 30)])),
    });

    expect(coverage.voices.every((v) => v.available)).toBe(true);
    expect(coverage.hasAnyNarration).toBe(true);
    expect(coverage.defaultVoiceId).toBe(JENNY);
  });
});

describe("voiceCoverage — nothing baked at all (i-take-my-ruins)", () => {
  const slides = deck(12);
  const coverage = voiceCoverage({
    slides,
    voices: NARRATION_VOICES,
    resolveUrl: resolverFor(new Set()),
  });

  it("disables every voice", () => {
    expect(coverage.voices.every((v) => !v.available)).toBe(true);
  });

  it("turns narration off entirely, so the controls can go dead", () => {
    expect(coverage.hasAnyNarration).toBe(false);
  });

  it("selects no voice rather than a silent one", () => {
    expect(coverage.defaultVoiceId).toBe("");
  });
});

describe("voiceCoverage — hasApi: the same deck differs by HOST", () => {
  // This is the case that makes coverage a property of (deck, host). The deck is
  // identical in both blocks; only the app it's playing in changes.
  const slides = deck(28);
  const nothingBaked = resolverFor(new Set());

  it("keeps every voice available in the prompts web UI (live /api/narrate)", () => {
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      hasApi: true,
      resolveUrl: nothingBaked, // zero assets — irrelevant when we can synthesize
    });

    expect(coverage.voices.every((v) => v.available)).toBe(true);
    expect(coverage.hasAnyNarration).toBe(true);
    expect(coverage.defaultVoiceId).toBe(JENNY);
  });

  it("disables everything for the SAME deck in the Wasteland (no API)", () => {
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      hasApi: false,
      resolveUrl: nothingBaked,
    });

    expect(coverage.voices.every((v) => !v.available)).toBe(true);
    expect(coverage.hasAnyNarration).toBe(false);
  });

  it("ignores a partial bake when the API is live", () => {
    // 9-of-28 would disable Jenny in the Wasteland; with a synthesizer it's just
    // a warm cache, so she stays selectable.
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      hasApi: true,
      resolveUrl: resolverFor(new Set(bake(JENNY, 9))),
    });
    expect(coverage.voices.find((v) => v.id === JENNY)!.available).toBe(true);
  });

  it("treats a missing resolver as unlimited, never as empty", () => {
    // A host that simply didn't wire coverage must not silently lose narration.
    const coverage = voiceCoverage({ slides, voices: NARRATION_VOICES });
    expect(coverage.voices.every((v) => v.available)).toBe(true);
    expect(coverage.hasAnyNarration).toBe(true);
  });
});

describe("voiceCoverage — staleness composes as a cache miss", () => {
  // Coverage asks ONE question: "is there a usable clip for this pair?" It does
  // not, and should not, know why one is unusable. That leaves room for the
  // recapture problem this repo actually has today: museum-of-bugs.tsx was
  // committed after its mp3s were baked, so the audio is
  // three days behind the words. If the Say text changed, those clips say the
  // wrong thing.
  //
  // The fix does NOT belong here — it belongs behind resolveUrl: key each asset by a hash of the
  // Say text it was baked from, and an edited slide simply stops resolving. Note
  // that bakedVoices.ts cannot do this yet — import.meta.glob(query:"?url") hands
  // back URL strings with no timestamp or source hash, so staleness needs that
  // build-time manifest to exist first.
  //
  // What IS pinned here is that coverage degrades correctly WHEN a resolver
  // starts rejecting stale clips, so the bake pass can land without renegotiating
  // this contract.
  const slides = deck(28);
  const staleSlides = new Set(["s3", "s7", "s11"]); // Say text edited since bake

  /** Has every clip on disk, but refuses the ones baked before the last edit. */
  const freshOnly = (slide: Slide, voiceId: string) =>
    staleSlides.has(slide.id) ? null : `/voices/${slide.id}-${voiceId}.mp3`;

  it("treats a stale clip exactly like a missing one", () => {
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: freshOnly,
    });

    // 25 of 28 fresh — an incomplete contract, so the voice is not offered.
    // Better silent than confidently narrating superseded text.
    const jenny = coverage.voices.find((v) => v.id === JENNY)!;
    expect(jenny.available).toBe(false);
    expect(jenny.slideCount).toBe(25);
    expect(coverage.hasAnyNarration).toBe(false);
  });

  it("re-enables the voice once those slides are recaptured", () => {
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set(bake(JENNY, 28))), // rebaked, all fresh
    });
    expect(coverage.voices.find((v) => v.id === JENNY)!.available).toBe(true);
    expect(coverage.hasAnyNarration).toBe(true);
  });

  it("staleness is irrelevant when the host can re-synthesize", () => {
    // In the prompts web UI a stale asset is a cache miss, not a broken feature:
    // /api/narrate regenerates from current text, so the voice stays offered.
    const coverage = voiceCoverage({
      slides,
      voices: NARRATION_VOICES,
      hasApi: true,
      resolveUrl: freshOnly,
    });
    expect(coverage.voices.every((v) => v.available)).toBe(true);
    expect(coverage.hasAnyNarration).toBe(true);
  });
});

describe("voiceCoverage — degenerate inputs", () => {
  it("an empty deck narrates nothing, even with an API", () => {
    // Guards the 0 === 0 trap: zero clips for zero slides is not "full coverage".
    const coverage = voiceCoverage({
      slides: [],
      voices: NARRATION_VOICES,
      hasApi: true,
    });
    expect(coverage.hasAnyNarration).toBe(false);
    // And no voice claims to be available either — the two must never disagree.
    expect(coverage.voices.every((v) => !v.available)).toBe(true);
    expect(coverage.defaultVoiceId).toBe("");
  });

  it("an empty deck with a resolver also narrates nothing", () => {
    const coverage = voiceCoverage({
      slides: [],
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set()),
    });
    expect(coverage.hasAnyNarration).toBe(false);
  });

  it("no voices configured means no narration", () => {
    const coverage = voiceCoverage({ slides: deck(3), voices: [], hasApi: true });
    expect(coverage.voices).toHaveLength(0);
    expect(coverage.hasAnyNarration).toBe(false);
    expect(coverage.defaultVoiceId).toBe("");
  });

  it("preserves the declared voice order, so the picker is stable", () => {
    const coverage = voiceCoverage({
      slides: deck(2),
      voices: NARRATION_VOICES,
      resolveUrl: resolverFor(new Set(bake(BRIAN, 2))),
    });
    expect(coverage.voices.map((v) => v.id)).toEqual([JENNY, BRIAN]);
  });
});
