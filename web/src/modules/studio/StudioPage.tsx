import { PageGrid, PanelRow } from "../../shell/cards";
import { DesignsCard } from "./DesignsCard";
import { FoyerCard } from "./FoyerCard";
import { PromptsCard } from "./PromptsCard";

/**
 * The Studio tab, `/studio` (docs/modules/studio.md, "The web UI"), in two
 * rows the page groups itself. The first is the foyer -- one row per product --
 * and beside it the Designs, the hub's seed drawer. The second is the Prompts
 * -- the agentic prompts, the same on every Space -- alone, at half width like
 * any lone panel.
 */
export function StudioPage() {
  return (
    <PageGrid>
      <PanelRow>
        <FoyerCard />
        <DesignsCard />
      </PanelRow>
      <PanelRow>
        <PromptsCard />
      </PanelRow>
    </PageGrid>
  );
}
