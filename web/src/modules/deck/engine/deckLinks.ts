// Shared external links every deck's closing slide can point at.
//
// CONNECTED_DECK_REPO_URL was a literal `const` copy-pasted into 50+ deck
// files. That is fine while the URL never changes, but it also means a repo
// rename or org move is a 50-file find-and-replace instead of a one-line
// edit. New decks should import this instead of redeclaring the literal;
// existing decks can migrate opportunistically rather than in one sweep.

/** The public repo every deck's closing-slide GitHub button copies. */
export const CONNECTED_DECK_REPO_URL = "https://github.com/johnfrog76/connected-deck";

/** The standalone connected-deck demo site (not its repo). */
export const CONNECTED_DECK_DEMO_URL = "https://johnfrog76.github.io/connected-deck/";

/** The standalone juggling-engine demo site (not its repo). */
export const JUGGLING_ENGINE_URL = "https://johnfrog76.github.io/juggling-engine/";

/** The bowling-engine public repo — the giveaway both bowling decks' payoff slides point at. */
export const BOWLING_ENGINE_URL = "https://github.com/johnfrog76/bowling-engine";

/** The standalone bowling-engine demo site (not its repo). */
export const BOWLING_ENGINE_DEMO_URL = "https://johnfrog76.github.io/bowling-engine/";

/** The aquarium-saver public repo — the giveaway the rest-habitat deck's payoff slide points at. */
export const AQUARIUM_SAVER_URL = "https://github.com/johnfrog76/aquarium-saver";

/** The standalone aquarium-saver site (not its repo): seven tanks, pure SVG and CSS. */
export const AQUARIUM_SAVER_DEMO_URL = "https://johnfrog76.github.io/aquarium-saver/";

/** The Toolkit's repo — the giveaway for decks of the `toolkit` project. */
export const TOOLKIT_REPO_URL = "https://github.com/johnfrog76/toolkit";

/**
 * What the giveaway button opens for a deck of a given project. The button
 * reads the project off DeckContext and never takes a URL: one purpose per
 * project, decided here. Unknown or absent — a deck with no home yet — is
 * connected-deck, the engine's own giveaway.
 */
export function giveawayUrlFor(project: string | undefined): string {
  return project === "toolkit" ? TOOLKIT_REPO_URL : CONNECTED_DECK_REPO_URL;
}
