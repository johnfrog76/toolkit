import type { ReactNode } from "react";
import { Tooltip } from "@fluentui/react-components";
import { InfoRegular } from "@fluentui/react-icons";

/**
 * The house's info tip: a small info icon whose tooltip DESCRIBES the thing
 * beside it -- a card's header, a form section's title. One component, so a
 * card that has something to say about itself says it the way the Create
 * page's sections do rather than in a footer sentence under its list.
 *
 * The relationship is `description`: Fluent renders the content hidden at all
 * times so `aria-describedby` on the icon resolves, and shows it on hover or
 * focus. The icon takes focus so a keyboard reaches it.
 */
export function InfoTip({ content, label = "About this" }: { content: ReactNode; label?: string }) {
  return (
    <Tooltip content={{ children: content }} relationship="description">
      <InfoRegular
        role="img"
        aria-label={label}
        tabIndex={0}
        style={{ fontSize: "16px", cursor: "pointer", flexShrink: 0 }}
      />
    </Tooltip>
  );
}
