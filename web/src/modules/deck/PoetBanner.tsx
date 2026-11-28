import { FirstRunBanner } from "./FirstRunBanner";
import { thePromptPoetWorksTheBoardDeck } from "./decks/the-prompt-poet-works-the-board";

// The Prompt Poet's first-run offer, made on the shipped Azure demo Space and
// ended by `firstRun.poet=false`. Same banner, same answer as the commercial's.
export const FIRST_RUN_POET_KEY = "firstRun.poet";

export function PoetBanner() {
  return (
    <FirstRunBanner
      deck={thePromptPoetWorksTheBoardDeck}
      configKey={FIRST_RUN_POET_KEY}
      dismissLabel="Hide the Prompt Poet banner"
    />
  );
}

export default PoetBanner;
