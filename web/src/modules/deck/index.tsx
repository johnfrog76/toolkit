import { Suspense, lazy } from "react";
import { Spinner } from "@fluentui/react-components";
import { HOME_BANNER_SLOT } from "../../shell/slots";
import type { ToolkitModule } from "../../shell/registry";

/**
 * The deck module: a presentation engine where a slide is a React component.
 *
 * Opt in with `features.deck`. Off means absent -- no route, no card, no nav
 * entry -- and ON stays light: everything below is `lazy`, so the engine, the
 * deck and its 38 voice files are a chunk the browser fetches when a deck card
 * or a deck route is actually shown, never part of the first load.
 *
 * Where it shows. The owner's rule: the list of decks "can live under growth
 * tab" -- a presentation is already one of growth's item types, and a deck is
 * what a presentation produces. So the launcher fills the Growth page's slot.
 * A slot nobody renders is invisible, and a switch that does nothing is the
 * defect this module was filed to fix -- so with growth OFF the module has a
 * tab of its own instead.
 *
 * docs/modules/deck.md is the short document; the engine is Connected Deck's.
 */

const DeckHost = lazy(() => import("./DeckHost"));
const DeckNotesHost = lazy(() => import("./DeckHost").then((m) => ({ default: m.DeckNotesHost })));
const DeckLauncher = lazy(() =>
  import("./DeckPickerCard").then((m) => ({ default: m.DeckPickerCard })),
);

// The first-run banner, lazy like the rest: it carries the tour deck's first
// slide, and a person who has dismissed it should never download it.
const HomeBanner = lazy(() => import("./HomeBanner"));

const loading = <Spinner size="tiny" label="Loading decks..." />;

function Launcher() {
  return (
    <Suspense fallback={loading}>
      <DeckLauncher />
    </Suspense>
  );
}

export const DECKS_HOME = "/decks";

export const deckModule: ToolkitModule = {
  id: "deck",
  feature: "deck",
  routes: [
    {
      path: "/deck/:deckId",
      element: (
        <Suspense fallback={loading}>
          <DeckHost />
        </Suspense>
      ),
    },
    {
      path: "/deck/:deckId/notes",
      element: (
        <Suspense fallback={loading}>
          <DeckNotesHost />
        </Suspense>
      ),
    },
    { path: DECKS_HOME, element: <Launcher /> },
  ],
  nav: [
    {
      label: "Decks",
      to: DECKS_HOME,
      match: (p) => p === DECKS_HOME,
      // Under the Growth tab when there is one; a tab of its own when there is not.
      hidden: (ctx) => ctx.env?.features?.growth === true,
    },
  ],
  slotCards: {
    growth: () => [<Launcher key="deck-launcher" />],
    // Home's banner, above its tabs, while `firstRun.welcome` is on. Asked for
    // only once /env has answered true, so it never flashes and never loads for
    // a machine that was not started from the sample hub.
    [HOME_BANNER_SLOT]: (ctx) =>
      ctx.env?.config?.firstRunWelcome
        ? [
            <Suspense key="first-run-banner" fallback={null}>
              <HomeBanner />
            </Suspense>,
          ]
        : [],
  },
  // A deck is a room of its own: the player and its notes window take the screen.
  chromeless: (pathname) => pathname.startsWith("/deck/"),
};
