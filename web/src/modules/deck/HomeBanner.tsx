import { FirstRunBanner } from "./FirstRunBanner";
import { theToolkitDeck } from "./decks/the-toolkit";

// The commercial's first-run offer: Introducing ToolKit, ended by
// `firstRun.welcome=false` (tkStart is what sets it true). The banner itself,
// and how it is answered, is FirstRunBanner.tsx, shared with every other deck
// offered on a first run.
export const FIRST_RUN_WELCOME_KEY = "firstRun.welcome";

export function HomeBanner() {
  return (
    <FirstRunBanner
      deck={theToolkitDeck}
      configKey={FIRST_RUN_WELCOME_KEY}
      dismissLabel="Hide the Introducing ToolKit banner"
    />
  );
}

export default HomeBanner;
