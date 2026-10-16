import type { ReactElement } from "react";
import {
  Button,
  Menu,
  MenuTrigger,
  MenuPopover,
  MenuList,
  MenuItem,
  MenuDivider,
  Spinner,
  Tooltip,
  tokens,
} from "@fluentui/react-components";
import { MoreHorizontalRegular } from "@fluentui/react-icons";

export interface CardAction {
  icon: ReactElement;
  label: string;
  onClick?: () => void;
  href?: string;
  disabled?: boolean;
  /**
   * Why a disabled action cannot be taken yet, in words a person can act on. Drawn
   * beside the item in the menu (`secondaryContent`) and in the flat button's
   * tooltip -- an unavailable action is shown and explained, not removed. An
   * action that can NEVER apply is not given a reason; it is left out.
   */
  whyNot?: string;
  /** Draw a divider above this item in the menu. Ignored for a flat button. */
  dividerBefore?: boolean;
}

// The row's action grammar, one for every surface: ONE exposed action --
// the one that goes somewhere in the app, or, where the tracker has no page of
// ours for the thing, the tracker's own page -- and a `...` menu that holds
// every other action, the external link LAST behind a divider. A row
// with one secondary action once drew it as a second flat button
// (the PR row's Fetch comments, the goal row's Retire), so the same grammar
// read two ways depending on a count. Now any secondary action goes in the menu.

interface CardActionsProps {
  primaryAction?: CardAction;
  secondaryActions?: CardAction[];
  /** Draw the `...` menu even with no secondary action (a card whose menu may fill later). */
  forceOverflow?: boolean;
  /** The `...` trigger's accessible name: "Actions for <the row's title>". Default "More actions". */
  menuLabel?: string;
  /** A write on this card is running: the trigger spins and cannot be opened. */
  busy?: boolean;
}

function FlatButton({ action }: { action: CardAction }) {
  // disabledFocusable, not disabled, when there is a reason: a disabled button
  // takes no pointer or focus, so its tooltip -- the reason -- could never show.
  const disabledProps = action.disabled
    ? action.whyNot
      ? { disabledFocusable: true }
      : { disabled: true }
    : {};
  const btn = action.href ? (
    <Button
      as="a"
      href={action.href}
      target="_blank"
      rel="noopener noreferrer"
      icon={action.icon}
      size="small"
      appearance="subtle"
      aria-label={action.label}
      {...disabledProps}
    />
  ) : (
    <Button
      icon={action.icon}
      size="small"
      appearance="subtle"
      aria-label={action.label}
      {...disabledProps}
      onClick={action.onClick}
    />
  );
  return (
    <Tooltip
      content={
        action.disabled && action.whyNot ? `${action.label} -- ${action.whyNot}` : action.label
      }
      relationship="label"
    >
      {btn}
    </Tooltip>
  );
}

export function CardActions({
  primaryAction,
  secondaryActions = [],
  forceOverflow = false,
  menuLabel = "More actions",
  busy = false,
}: CardActionsProps) {
  const useOverflow = forceOverflow || secondaryActions.length > 0;

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: tokens.spacingHorizontalXS,
        flexShrink: 0,
      }}
    >
      {primaryAction && <FlatButton action={primaryAction} />}
      {useOverflow && (
        <Menu>
          <MenuTrigger disableButtonEnhancement>
            <Button
              icon={busy ? <Spinner size="extra-tiny" aria-label="Working..." /> : <MoreHorizontalRegular />}
              size="small"
              appearance="subtle"
              aria-label={menuLabel}
              aria-busy={busy || undefined}
              disabled={busy}
            />
          </MenuTrigger>
          <MenuPopover>
            <MenuList>
              {secondaryActions.flatMap((a, i) => [
                ...(a.dividerBefore && i > 0 ? [<MenuDivider key={`${a.label}--divider`} />] : []),
                <MenuItem
                  key={a.label}
                  icon={a.icon}
                  disabled={a.disabled}
                  secondaryContent={a.disabled ? a.whyNot : undefined}
                  onClick={
                    a.href ? () => window.open(a.href!, "_blank", "noopener,noreferrer") : a.onClick
                  }
                >
                  {a.label}
                </MenuItem>,
              ])}
            </MenuList>
          </MenuPopover>
        </Menu>
      )}
    </div>
  );
}
