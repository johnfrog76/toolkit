// Ported from the Wasteland (src/stillPosters.tsx) unchanged;
// here it freezes the first-run banner's poster (HomeBanner.tsx).
//
import { useEffect } from "react";

// Still posters — the Wasteland's wall holds still. Always.
//
// WHY THIS EXISTS: a poster is a REAL deck slide (SlidePoster), rendered at the
// full 1280x720 stage and scaled down. transform:scale shrinks the pixels, not
// the work — the browser still runs every @keyframes in that slide at full
// size, forever, for every card on the page. The collection shows a dozen at
// once. That is a lot of laptop fan for decoration nobody is looking at.
//
// This USED to be a setting (a persisted flag, a context, a switch in the
// settings drawer, defaulting to still). It isn't any more: animated cards
// are neat to see once and were never worth a control. The wall is still,
// full stop; a deck animates when you PLAY it, which is the whole point of
// the player and renders one slide, not a dozen.
//
// WHY IT'S CSS AND NOT A PROP: decks author their animations as INLINE style
// props (`style={{ animation: "qj-spin 4s infinite" }}`) — 1300+ of them across
// 40+ deck files. Nothing a React parent passes down can override an inline
// style on a descendant. The only thing that outranks an inline style is a
// stylesheet rule marked !important, so that's the lever: one class on the
// poster's container, one !important rule underneath it. This is also why the
// freeze is all-or-nothing per card — we're overriding the cascade, not
// negotiating with the deck.
//
// SCOPE: posters only. Freezing a card does NOT touch the deck when you open
// it.

// The class the freeze rule hangs off. Applied by every PosterCard, defined
// in the stylesheet injected below.
export const STILL_POSTERS_CLASS = "wl-still-posters";

// The freeze itself. `*` plus the container so a slide's own root is caught
// too, not just its descendants.
//
// - animation: none         kills @keyframes outright
// - transition: none        stops hover/enter transitions from re-triggering paint
// - !important              outranks the decks' inline style props
//
// What a card then shows is each element's STATIC style — `animation: none`
// removes the animation, it does NOT hold frame 0. Usually that's the same
// picture, because a deck's pre-animation state is the designed one (things
// fly in TO their positions, not away from them). Where it differs it bites:
// an element kept invisible ONLY by its 0% keyframe has no resting style to
// fall back to and renders at full strength — League Night's per-window cut
// flash was a white panel over two windows of its first slide until each such
// element got an explicit `opacity: 0`. The rule for deck authors: invisible
// at rest must live in the static style, not just in the keyframes. The
// inverse is the accepted tradeoff — a slide that animates a 0-opacity intro
// stays hidden on a frozen card, and a poster can read darker than the live
// one. That's the price of a cascade override; the alternative is editing 40
// deck files.
//
// THE ONE PLACE `*` CANNOT REACH: SVG <use>. A deck that builds its art from
// <symbol> defs and <use> instances (the Aquarium Rest Habitat, lifted from
// aquarium-saver) renders every instance in a browser-internal shadow tree.
// Selectors from the document still match an instance by ITS OWN features
// (that is how `.aq-hang { animation }` reaches it at all), but a descendant
// combinator can't walk up out of that tree, so `.wl-still-posters *` never
// matches and the tank keeps swimming on a frozen wall. Verified in Chrome
// 152. Custom properties DO inherit across that boundary, so the freeze also
// publishes one, and a <use>-based deck opts in with a self-matching rule:
//
//   [class*="aq-"][class*="aq-"] { animation-play-state: var(--wl-still-posters, running); }
//
// (doubled so it outranks the deck's own `animation:` shorthand, which would
// otherwise reset play-state to running). Unset outside a poster, so the
// player is untouched. Paused rather than none: an instance can't be reached
// with `none` anyway, and a held mid-cycle frame is a fine still.
export const STILL_POSTERS_VAR = "--wl-still-posters";

const FREEZE_CSS = `
.${STILL_POSTERS_CLASS},
.${STILL_POSTERS_CLASS} * {
  animation: none !important;
  transition: none !important;
}
.${STILL_POSTERS_CLASS} {
  ${STILL_POSTERS_VAR}: paused;
}
`;

// Injected once rather than per-card: a dozen cards must not mean a dozen
// <style> tags. Guarded for SSR/test environments with no document.
let injected = false;
function injectFreezeCss() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const style = document.createElement("style");
  style.dataset.wasteland = "still-posters";
  style.textContent = FREEZE_CSS;
  document.head.appendChild(style);
}

// Called by PosterCard: makes sure the freeze stylesheet is in the document
// before the first poster paints. Idempotent, so every card can call it.
export function useStillPostersCss() {
  useEffect(() => {
    injectFreezeCss();
  }, []);
}
