import type { ReactNode } from "react";

export interface Slide {
  id: string;
  /**
   * Plain-text slide title, shown full-sized in the presenter-notes window so
   * the speaker can connect their notes to the slide the room is seeing.
   * Should match the visible title inside `copy`.
   */
  title?: string;
  copy: ReactNode;
  content?: ReactNode;
  /**
   * Presenter notes. Plain strings are still supported (rendered as markdown,
   * for older decks) but new decks should compose Say/Context/Beat from
   * "../deck-components/PresenterNoteKit" so verbatim lines, background
   * context, and delivery cues are visually distinct on the presenter screen.
   */
  notes?: ReactNode;
  /**
   * Optional authored override for this slide's approximate on-screen time,
   * as "mm:ss". When set it wins over the computed estimate (narration read
   * time + per-slide dwell); leave unset to let the deck-duration estimator
   * derive it from the Say text. See "../deck-components/deckDuration".
   */
  approximateTime?: string;
}

/**
 * Lifecycle: is this deck DONE? Orthogonal to `deployed` (may strangers see it?)
 * and to `audience` (is it web-internal?). Keeping the three separate is what
 * lets a finished deck sit unpublished, or a published deck go back under
 * revision without anyone having to mislabel it as unfinished.
 */
export enum DeckState {
  Draft = "draft",
  InProgress = "in-progress",
  Complete = "complete",
  Archive = "archive",
}

/**
 * Who a deck is for — an audience/access axis, independent of DeckState
 * lifecycle. A deck can be finished (Complete) yet still Private.
 *   Public  — may appear in the public app (CSS Wasteland), subject to the
 *             lifecycle gate. The default when audience is omitted.
 *   Private — web-internal only; never surfaces publicly, whatever its state.
 *             e.g. engineering-os, which exists to demo that live Redux-backed
 *             components hydrate a deck — it only works inside web's runtime.
 */
export enum DeckAudience {
  Public = "public",
  Private = "private",
}

/**
 * Where a deck ships — the studio's axis, ridden along on this copy of the
 * type. `wasteland` publishes from the studio; `toolkit` and `connected-deck`
 * are shown from their own repos, which hold a byte-identical played copy.
 * OPTIONAL and unread here except by the giveaway button, which uses it to
 * pick the repo it opens. A deck with no project is nobody's.
 */
export const DECK_PROJECTS = ["wasteland", "toolkit", "connected-deck"] as const;
export type DeckProject = (typeof DECK_PROJECTS)[number];

export interface Deck {
  id: string;
  title: string;
  /** Which home this deck ships to — see DeckProject. */
  project?: DeckProject;
  /**
   * Lifecycle state (Draft | InProgress | Complete | Archive) — "is it done?".
   * Omit defaults to Draft. Prompts Web shows all decks regardless of state.
   */
  state?: DeckState;
  /**
   * May strangers see it? — the publish switch, independent of `state`.
   * Omit defaults to FALSE, so a deck is never public by accident; publishing is
   * always a deliberate edit. Public eligibility is
   * `deployed === true && state === Complete` (plus audience Public).
   *
   * Two fields rather than one, because "finished" and "published" are different
   * questions and both change independently:
   *   - Complete + deployed:false   — done, but awaiting its turn in a release
   *                                   batch, or retired from the site later
   *   - Complete + deployed:true    — live
   *   - InProgress + deployed:true  — live deck under revision; drops off the
   *                                   public site until it's Complete again, so
   *                                   strangers never see a half-reworked deck
   * Archive and audience:Private are hard excludes regardless of this flag.
   */
  deployed?: boolean;
  /**
   * Subject-matter tags for filtering/search, e.g. ["css", "scss", "bem"] or
   * ["azure", "serverless"]. Lowercase kebab-case, normalized across decks so
   * the same topic always uses the same tag (e.g. always "typescript", never
   * "ts"). Ordered roughly general → specific.
   */
  tags?: string[];
  /**
   * Audience/access for this deck (Public | Private). Omit for the common case
   * (Public). Private decks are web-internal and are filtered out of the public
   * app regardless of lifecycle state — see DeckAudience.
   */
  audience?: DeckAudience;
  /**
   * Short, spoiler-free description of what the deck is about — a few
   * sentences a reader can use to decide whether to open it, without giving
   * away the twist, punchline, or narrative payoff inside.
   * @example
   * "A tour of CSS specificity told through a haunted house metaphor, from
   * the front door (element selectors) to the attic (!important)."
   */
  summary: string;
  /**
   * The deck's slides. Takes no arguments: a deck is a self-contained artifact,
   * and org is not a concept the deck path carries. A deck that genuinely needs
   * live host data reads it from the host's own runtime (as engineering-os.tsx
   * does, via useGetEnvQuery) rather than having it threaded through here — that
   * coupling belongs to the one Private, web-only deck that wants it, not to the
   * interface every deck implements.
   */
  slides: () => Slide[];
  /**
   * An audiobook: a deck meant to be LISTENED to, end to end, at any width
   * (Team Agile's ritual decks; docs/modules/solitaire-agile.md, "The played view").
   * Three things follow, all in the engine and none of them for a deck that
   * leaves this unset, which is every hand-written deck:
   *   - Suitcase Mode is allowed on the desktop too (DeckPlayer's gate drops
   *     its phone-width requirement for this deck only);
   *   - the transport keeps prev and next beside the one big button
   *     (DeckChrome), so a tile can be skipped without leaving Suitcase;
   *   - a slide with no baked clip is read by the browser's speechSynthesis
   *     from its Say text (useSpeechNarration) -- D-TA7's no-key fallback.
   */
  audiobook?: boolean;
}
