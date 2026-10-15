import * as React from "react";
import {
  Button,
  Input,
  makeStyles,
  mergeClasses,
  tokens,
  useMenuContext_unstable,
} from "@fluentui/react-components";
import { CheckmarkRegular, SearchRegular } from "@fluentui/react-icons";
import type { SpaceChoice } from "./AvatarMenu";

// Past about eight Spaces a dropdown stops working (the owner: "dropdown menu
// works well until you hit about 8 or nine spaces"), so the avatar menu's Space
// submenu becomes a QUICK MENU -- the searchable switcher people already know
// from GitHub's branch picker and Slack's workspace list: a text box with the
// focus, a list that narrows as you type, Enter chooses. Up to the threshold
// the submenu is the plain list it always was.
//
// The one number, tuned by eye. At or below it: today's submenu. Above it: the
// quick menu, whose short list (nothing typed) shows this many rows.
export const SPACE_QUICK_MENU_THRESHOLD = 8;

// Row and box sizes are fixed so nothing moves while you type: the panel keeps
// its width, the list keeps its height (it scrolls), and the foot keeps its
// row whether or not "View all" is in it.
const ROW_HEIGHT = 32;
const PANEL_WIDTH = 280;

const useStyles = makeStyles({
  panel: {
    width: `${PANEL_WIDTH}px`,
    display: "flex",
    flexDirection: "column",
    gap: "4px",
    padding: "4px",
    boxSizing: "border-box",
  },
  list: {
    height: `${ROW_HEIGHT * SPACE_QUICK_MENU_THRESHOLD}px`,
    overflowY: "auto",
    margin: 0,
    padding: 0,
    listStyle: "none",
  },
  row: {
    display: "flex",
    alignItems: "center",
    gap: "8px",
    height: `${ROW_HEIGHT}px`,
    padding: "0 8px",
    boxSizing: "border-box",
    borderRadius: tokens.borderRadiusMedium,
    cursor: "pointer",
    color: tokens.colorNeutralForeground2,
    whiteSpace: "nowrap",
  },
  highlighted: {
    backgroundColor: tokens.colorNeutralBackground1Hover,
    color: tokens.colorNeutralForeground2Hover,
  },
  check: { width: "16px", flexShrink: 0, display: "inline-flex" },
  name: { overflow: "hidden", textOverflow: "ellipsis" },
  slug: {
    marginLeft: "auto",
    color: tokens.colorNeutralForeground3,
    fontSize: tokens.fontSizeBase200,
    overflow: "hidden",
    textOverflow: "ellipsis",
  },
  empty: {
    padding: "8px",
    color: tokens.colorNeutralForeground3,
  },
  foot: {
    height: `${ROW_HEIGHT}px`,
    display: "flex",
    alignItems: "center",
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
    paddingTop: "4px",
  },
});

/** Nothing typed: the active Space first, then the rest in declaration order. */
export function spaceShortList(
  spaces: SpaceChoice[],
  activeSpace: string,
  all: boolean,
): SpaceChoice[] {
  const active = spaces.filter((s) => s.slug === activeSpace);
  const ordered = [...active, ...spaces.filter((s) => s.slug !== activeSpace)];
  return all ? ordered : ordered.slice(0, SPACE_QUICK_MENU_THRESHOLD);
}

/** Typed: the display name OR the slug, case-insensitive, anywhere in it. */
export function filterSpaces(
  spaces: SpaceChoice[],
  activeSpace: string,
  query: string,
): SpaceChoice[] {
  const q = query.trim().toLowerCase();
  const ordered = spaceShortList(spaces, activeSpace, true);
  if (!q) return ordered;
  return ordered.filter(
    (s) => s.name.toLowerCase().includes(q) || s.slug.toLowerCase().includes(q),
  );
}

interface Props {
  spaces: SpaceChoice[];
  activeSpace: string;
  onSwitchSpace: (slug: string) => void;
}

/**
 * The panel drawn INSIDE the Space submenu's MenuPopover, in place of its
 * MenuList. The popover keeps what it already does: Escape closes it and
 * hands focus back to the Space entry, and it opens where the submenu opened.
 * ARIA's combobox-with-listbox: the box keeps the focus, the highlighted row
 * is its `aria-activedescendant`, the current Space is the selected option.
 */
export function SpaceQuickMenu({ spaces, activeSpace, onSwitchSpace }: Props) {
  const styles = useStyles();
  const setOpen = useMenuContext_unstable((c) => c.setOpen);
  const [query, setQuery] = React.useState("");
  const [showAll, setShowAll] = React.useState(false);
  const [highlight, setHighlight] = React.useState(0);
  const inputRef = React.useRef<HTMLInputElement>(null);
  const viewAllRef = React.useRef<HTMLButtonElement>(null);
  const listRef = React.useRef<HTMLUListElement>(null);
  const baseId = React.useId();
  const listId = `${baseId}-list`;
  const optionId = (slug: string) => `${baseId}-opt-${slug}`;

  const typed = query.trim() !== "";
  const rows = typed
    ? filterSpaces(spaces, activeSpace, query)
    : spaceShortList(spaces, activeSpace, showAll);
  const needsViewAll = !typed && !showAll && spaces.length > rows.length;
  const current = rows[Math.min(highlight, rows.length - 1)];

  React.useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Keep the highlighted row in view as the arrows move it (jsdom has no
  // scrollIntoView, hence the guard).
  React.useEffect(() => {
    if (!current) return;
    const el = listRef.current?.querySelector<HTMLElement>(`[id="${optionId(current.slug)}"]`);
    el?.scrollIntoView?.({ block: "nearest" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current?.slug]);

  const choose = (slug: string, e: React.SyntheticEvent) => {
    // Close the whole avatar menu, the way choosing a MenuItemRadio does
    // (bubble: the submenu asks its parent to close too).
    setOpen(e as unknown as React.MouseEvent<HTMLElement>, {
      open: false,
      bubble: true,
      type: "menuItemClick",
      event: e as unknown as React.MouseEvent<HTMLElement>,
    });
    if (slug !== activeSpace) onSwitchSpace(slug);
  };

  const onInputKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        if (rows.length) setHighlight((h) => (Math.min(h, rows.length - 1) + 1) % rows.length);
        return;
      case "ArrowUp":
        e.preventDefault();
        if (rows.length)
          setHighlight((h) => (Math.min(h, rows.length - 1) - 1 + rows.length) % rows.length);
        return;
      case "Enter":
        e.preventDefault();
        if (current) choose(current.slug, e);
        return;
      case "ArrowLeft":
      case "ArrowRight":
      case "Home":
      case "End":
        // Text editing keys stay in the box: the submenu would otherwise read
        // ArrowLeft as "close me".
        e.stopPropagation();
        return;
      case "Tab":
        // With View all in the foot, Tab reaches it rather than closing the menu.
        if (needsViewAll && !e.shiftKey) {
          e.preventDefault();
          e.stopPropagation();
          viewAllRef.current?.focus();
        }
        return;
    }
  };

  const onViewAllKeyDown = (e: React.KeyboardEvent<HTMLButtonElement>) => {
    if (e.key === "Tab") {
      e.preventDefault();
      e.stopPropagation();
      inputRef.current?.focus();
    }
  };

  return (
    <div className={styles.panel}>
      <Input
        ref={inputRef}
        value={query}
        onChange={(_e, d) => {
          setQuery(d.value);
          setHighlight(0);
        }}
        onKeyDown={onInputKeyDown}
        placeholder="Find a Space"
        contentBefore={<SearchRegular aria-hidden />}
        role="combobox"
        aria-label="Find a Space"
        aria-expanded
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={current ? optionId(current.slug) : undefined}
        autoComplete="off"
      />
      <ul ref={listRef} id={listId} role="listbox" aria-label="Spaces" className={styles.list}>
        {rows.length === 0 ? (
          <li role="presentation" className={styles.empty}>
            No Space matches &apos;{query.trim()}&apos;
          </li>
        ) : (
          rows.map((s, i) => (
            <li
              key={s.slug}
              id={optionId(s.slug)}
              role="option"
              aria-selected={s.slug === activeSpace}
              className={mergeClasses(styles.row, s === current && styles.highlighted)}
              onMouseEnter={() => setHighlight(i)}
              // Keep the focus in the box: a click chooses, it does not focus.
              onMouseDown={(e) => e.preventDefault()}
              onClick={(e) => choose(s.slug, e)}
            >
              <span className={styles.check} aria-hidden>
                {s.slug === activeSpace ? <CheckmarkRegular /> : null}
              </span>
              <span className={styles.name}>{s.name}</span>
              {s.name !== s.slug ? <span className={styles.slug}>{s.slug}</span> : null}
            </li>
          ))
        )}
      </ul>
      <div className={styles.foot}>
        {needsViewAll ? (
          <Button
            ref={viewAllRef}
            appearance="transparent"
            size="small"
            onKeyDown={onViewAllKeyDown}
            onClick={() => {
              setShowAll(true);
              inputRef.current?.focus();
            }}
          >
            View all
          </Button>
        ) : null}
      </div>
    </div>
  );
}
