import { ArchiveArrowBackRegular, PlayRegular } from "@fluentui/react-icons";
import { defineRowMoves } from "../../shared/CardActions";

/**
 * A deck's own moves (web/README.md, "One vocabulary for row actions"). Open
 * and Archive are the vocabulary's (`ROW.open`, `ROW.archive`); these two exist
 * on a deck only:
 *   - Play opens the player, the page's one exposed action;
 *   - Unarchive takes a deck off this machine's put-away list (`deck.archived`).
 * Shared by the Decks card's row and the deck's page.
 */
export const DECK_MOVES = defineRowMoves("deck", {
  play: { word: "Play", icon: PlayRegular, tooltip: "Play the deck, full screen" },
  unarchive: {
    word: "Unarchive",
    icon: ArchiveArrowBackRegular,
    tooltip: "Bring it back to the Decks list on this machine",
  },
});
