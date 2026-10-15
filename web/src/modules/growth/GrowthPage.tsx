import { ReviewArchive } from "./ReviewArchive";
import { Goals } from "./Goals";
import { QuarterLine } from "./QuarterLine";
import { PageGrid, useShellSlot } from "../../shell/cards";

/**
 * `/growth` -- two cards: the review archive and the growth items themselves.
 *
 * It used to be four. `OneOnOne` went to the communication module with the rest
 * of the 1:1 workflow, and the deck picker went with the deck engine; both were
 * on this page because it was the only page that was not the ADO home, not
 * because they belonged to growth.
 */
export function GrowthPage() {
  // Cards other modules put on this page -- today the deck launcher, when
  // `features.deck` is on. This page does not know what they are and imports
  // none of them: a presentation is a growth item, and its deck belongs beside it.
  const slotCards = useShellSlot("growth");

  return (
    <>
      {/* One line, and only while the active Space states a training requirement. */}
      <QuarterLine />
      <PageGrid>
        <ReviewArchive activeTag={null} />
        <Goals />
        {slotCards}
      </PageGrid>
    </>
  );
}
