import { PageGrid } from "../../shell/cards";
import { DesignsCard } from "./DesignsCard";
import { FoyerCard } from "./FoyerCard";
import { PromptsCard } from "./PromptsCard";

/**
 * The Studio tab, `/studio` (docs/modules/studio.md, "The web UI"): the foyer first -- one row per product -- then the Designs, the
 * hub's seed drawer, and beside it the Prompts -- the agentic prompts,
 * the same on every Space -- laid out like any other tab: cards in the shell's
 * grid at half width.
 */
export function StudioPage() {
  return (
    <PageGrid>
      <FoyerCard />
      <DesignsCard />
      <PromptsCard />
    </PageGrid>
  );
}
