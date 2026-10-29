import { createElement } from "react";
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
import {
  ArchiveRegular,
  ArrowRightRegular,
  CheckmarkRegular,
  CopyRegular,
  DeleteRegular,
  DocumentTextRegular,
  MoreHorizontalRegular,
  OpenRegular,
} from "@fluentui/react-icons";
import type { FluentIcon } from "@fluentui/react-icons";

export interface CardAction {
  /**
   * Which move this is: a vocabulary key (`archive`, `external`...) or a module's
   * own move (`reminder.snooze`). Required, so an action can only be built from
   * the vocabulary below -- `ROW.<move>.action()` or a `defineRowMoves` table --
   * and never typed by hand with a word of its own.
   */
  move: string;
  icon: ReactElement;
  label: string;
  /** The move's tooltip, from the vocabulary. The flat button shows it; a menu item carries it as its title. */
  tooltip?: string;
  /** The external link: drawn LAST in the menu, behind a divider, whatever order it was given in. */
  external?: boolean;
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

// ---------------------------------------------------------------------------
// The row-action vocabulary (#153): every row's menu in the product names a
// move with the SAME word, icon and tooltip. Each standard move is defined here
// once, in ROW; a module builds its rows from these entries and adds only the
// moves that are its own, each declared once in a `defineRowMoves` table.
//
//   Adding a standard move: add an entry to ROW (and a synonym list to
//     ROW_SYNONYMS), and a row to web/README.md's vocabulary table.
//   Adding a module's own move: add it to that module's `defineRowMoves` table
//     and a row to web/README.md's exceptions table. Its word may not be a
//     vocabulary word or a synonym of one, and its icon may not be a
//     vocabulary icon -- unless it declares `differentMove` with the reason it
//     is a different thing (a Space's Retire is not an archive).
//
// shared/rowVocabulary.test.ts reads every row menu in the source and holds
// all of this; the README is the list a person reads.
// ---------------------------------------------------------------------------

export interface RowMoveDef {
  /** The label's first words. A detail, where the move takes one, follows after a space. */
  word: string;
  /** The ONE icon this move wears everywhere. */
  icon: FluentIcon;
  /** The tooltip. `{detail}` is the detail, "it" when there is none. Defaults to the label. */
  tooltip?: string;
  /**
   * An own move whose word or icon is close to a vocabulary move's but which is a
   * different thing, and why. The static test refuses a synonym or a shared icon
   * without it.
   */
  differentMove?: string;
}

export interface RowActionOptions {
  /** Appended to the word after a space: "the note", "as shipped", "GitHub". */
  detail?: string;
  onClick?: () => void;
  href?: string;
  disabled?: boolean;
  whyNot?: string;
  dividerBefore?: boolean;
  /** The action is running: a spinner with this accessible name stands in for the icon. */
  busy?: string;
}

export interface RowMove {
  readonly key: string;
  readonly word: string;
  readonly icon: FluentIcon;
  readonly differentMove?: string;
  /** The label, word then detail. */
  label(detail?: string): string;
  tooltip(detail?: string): string;
  action(options?: RowActionOptions): CardAction;
}

function rowMove(key: string, def: RowMoveDef, external = false): RowMove {
  const label = (detail?: string) => (detail ? `${def.word} ${detail}` : def.word);
  const tooltip = (detail?: string) =>
    def.tooltip ? def.tooltip.replace("{detail}", detail || "it") : label(detail);
  return {
    key,
    word: def.word,
    icon: def.icon,
    differentMove: def.differentMove,
    label,
    tooltip,
    action: ({ detail, busy, ...rest } = {}) => ({
      move: key,
      icon: busy ? <Spinner size="tiny" aria-label={busy} /> : createElement(def.icon),
      label: label(detail),
      tooltip: tooltip(detail),
      ...(external ? { external: true } : {}),
      ...rest,
    }),
  };
}

/** The standard moves. Each names one move once: its word, its icon, its tooltip. */
export const ROW = {
  /** Opens something INSIDE ToolKit -- a note, a card, a goal. Detail: what ("the note"). */
  open: rowMove("open", {
    word: "Open",
    icon: DocumentTextRegular,
    tooltip: "Open {detail} here, in ToolKit",
  }),
  /** The move to an archive. Detail, where there are two: what it archives as ("as shipped"). */
  archive: rowMove("archive", {
    word: "Archive",
    icon: ArchiveRegular,
    tooltip: "Move it to the archive, stamped closed",
  }),
  complete: rowMove("complete", {
    word: "Complete",
    icon: CheckmarkRegular,
    tooltip: "Mark it complete",
  }),
  /** Detail: what ("the cover"). */
  delete: rowMove("delete", {
    word: "Delete",
    icon: DeleteRegular,
    tooltip: "Delete {detail} for good",
  }),
  /** Detail: where to ("In Progress"). */
  move: rowMove("move", {
    word: "Move to",
    icon: ArrowRightRegular,
    tooltip: "Move it to {detail}",
  }),
  /** Detail: what ("reference"). */
  copy: rowMove("copy", {
    word: "Copy",
    icon: CopyRegular,
    tooltip: "Copy the {detail} to the clipboard",
  }),
  /** The external link. Detail: the tracker's or system's NAME ("GitHub", "Azure DevOps"). Always last. */
  external: rowMove(
    "external",
    { word: "Open on", icon: OpenRegular, tooltip: "Open it on {detail}, outside ToolKit" },
    true,
  ),
} as const;

export type RowMoveKey = keyof typeof ROW;

/**
 * Words that mean a vocabulary move. An own move whose first word is one of these
 * is the same move under another name -- the static test refuses it unless it
 * declares `differentMove`.
 */
export const ROW_SYNONYMS: Record<RowMoveKey, string[]> = {
  open: ["view", "show", "see", "visit", "read", "browse"],
  archive: ["retire", "drop", "shelve", "stash", "bury", "file"],
  complete: ["done", "finish", "resolve", "close", "achieve"],
  delete: ["remove", "erase", "trash", "discard", "destroy"],
  move: ["send", "shift", "transfer", "relocate"],
  copy: ["duplicate", "clone"],
  external: [],
};

/**
 * A module's own moves -- a move that exists on one kind of record only, or one
 * that is a different thing from every vocabulary move. `record` names the record
 * ("reminder"); each key is listed in web/README.md as `record.key`. Write the
 * table as a literal: the static test reads it from the source.
 */
export function defineRowMoves<K extends string>(
  record: string,
  table: Record<K, RowMoveDef>,
): Record<K, RowMove> {
  const out = {} as Record<K, RowMove>;
  for (const key of Object.keys(table) as K[]) {
    out[key] = rowMove(`${record}.${key}`, table[key]);
  }
  return out;
}

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
  const tip = action.tooltip ?? action.label;
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
      content={action.disabled && action.whyNot ? `${action.label} -- ${action.whyNot}` : tip}
      // The button's name is its label (aria-label); a tooltip that says more describes it.
      relationship={
        tip === action.label || (action.disabled && action.whyNot) ? "label" : "description"
      }
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
  // The external link last, always, behind its divider.
  const inside = secondaryActions.filter((a) => !a.external);
  const outside = secondaryActions.filter((a) => a.external);
  const ordered = [
    ...inside,
    ...outside.map((a, i) => (i === 0 ? { ...a, dividerBefore: true } : a)),
  ];

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
              icon={
                busy ? (
                  <Spinner size="extra-tiny" aria-label="Working..." />
                ) : (
                  <MoreHorizontalRegular />
                )
              }
              size="small"
              appearance="subtle"
              aria-label={menuLabel}
              aria-busy={busy || undefined}
              disabled={busy}
            />
          </MenuTrigger>
          <MenuPopover>
            <MenuList>
              {ordered.flatMap((a, i) => [
                ...(a.dividerBefore && i > 0 ? [<MenuDivider key={`${a.label}--divider`} />] : []),
                <MenuItem
                  key={a.label}
                  icon={a.icon}
                  title={a.tooltip && a.tooltip !== a.label ? a.tooltip : undefined}
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
