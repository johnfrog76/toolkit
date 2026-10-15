import { Button, Tooltip } from "@fluentui/react-components";
import { AddRegular } from "@fluentui/react-icons";

/**
 * The card's footer **+** -- how every card that makes something says so.
 *
 * Six cards drew their own: two wore a tooltip that named the thing, three a
 * bare `title` ("New item", "New session"), one an aria-label and a title that
 * disagreed in case with the dialog it opened. One component now, and one rule
 * for its words: the `label` IS the title of the dialog it opens ("New Growth
 * Item" opens "New Growth Item"), so the button promises exactly what appears.
 * It is the tooltip and the accessible name at once.
 */
export function CreateButton({
  label,
  onClick,
  disabled,
}: {
  /** The dialog's own title, word for word. */
  label: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <Tooltip content={label} relationship="label">
      <Button
        icon={<AddRegular />}
        size="small"
        appearance="subtle"
        onClick={onClick}
        disabled={disabled}
      />
    </Tooltip>
  );
}
