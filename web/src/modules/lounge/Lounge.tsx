/**
 * The Lounge -- the room where a single thread of consciousness is restored
 * (docs/modules/lounge.md).
 *
 * Since M3 the room is A TAB STYLED LIKE THE GUI:
 * drawn in the theme in force -- "you have Sunny theme you have sunny
 * lounge" -- and when a skin is worn it wears the skin exactly as every
 * other page does, because the skin owns the palette (D-L13). No scene
 * slot, no skin of its own, no toolbar. Its ONE exposed action is Skins,
 * which opens the dialog where a skin is chosen and worn product-wide
 * (D-L18); that is the whole of the room's relation to skins.
 *
 * The room asks nothing: no counts, no inputs, no digit in its visible
 * text -- held by Lounge.test.tsx. What it holds is the Face card first
 * (D-L24: its home is the room) and then the coffee table: the small games
 * of D-L21, each a card on the house grid.
 */
import { useState } from "react";
import { Body1, Button, makeStyles, tokens } from "@fluentui/react-components";
import { PageGrid } from "../../shell/cards";
// A module may import another module's card; it may not fork one
// (web/README.md). The Face card is the ADO module's; its home is here.
import { FacePicker } from "../ado/FacePicker";
import { GoBoard } from "./GoBoard";
import { SkinsDialog } from "./SkinsDialog";
import { TicTacToe } from "./TicTacToe";
import { WordRing } from "./WordRing";

const useStyles = makeStyles({
  // Home's explain row, the same row doing the same job: one line saying
  // what the page is for, and the button that belongs to it at its end.
  explainRow: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    marginBottom: tokens.spacingVerticalM,
  },
  explain: {
    color: tokens.colorNeutralForeground3,
    flex: "1 1 20rem",
    minWidth: 0,
    padding: `${tokens.spacingVerticalL} ${tokens.spacingHorizontalS}`,
  },
  gamesNote: {
    display: "block",
    color: tokens.colorNeutralForeground3,
    padding: `${tokens.spacingVerticalL} ${tokens.spacingHorizontalS}`,
  },
});

// One sentence saying what the games are: they keep no score and do not
// play back yet. Product voice -- no numeral, the room has none.
const GAMES_NOTE = "The games are here for the mood. Ones that play back are on the way.";

export function Lounge() {
  const styles = useStyles();
  const [skinsOpen, setSkinsOpen] = useState(false);
  return (
    <>
      <div className={styles.explainRow}>
        <Body1 className={styles.explain}>
          A place to look up from the work. Nothing here counts anything.
        </Body1>
        <Button appearance="secondary" onClick={() => setSkinsOpen(true)}>
          Skins
        </Button>
      </div>
      {/* Face first, then the games -- two by two on a
          desktop, a column on a phone. */}
      <PageGrid>
        <FacePicker />
        <GoBoard />
        <WordRing />
        <TicTacToe />
      </PageGrid>
      <Body1 className={styles.gamesNote}>{GAMES_NOTE}</Body1>
      <SkinsDialog open={skinsOpen} onClose={() => setSkinsOpen(false)} />
    </>
  );
}
