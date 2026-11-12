import { useLayoutEffect, useRef, useState } from "react";
import type { ReactElement, ReactNode } from "react";
import {
  Badge,
  Button,
  Caption1,
  Input,
  Select,
  Subtitle2,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { CardSpinner } from "../../shared/CardSpinner";
import { CreateButton } from "../../shared/CreateButton";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";
import { FilterBadge } from "../../shared/FilterBadge";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { InfoTip } from "../../shared/InfoTip";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { StatusMessage } from "../../shared/StatusMessage";
import { CardItem, CompactItem, LineItem } from "../CardItem";
import type { CardItemData, CompactItemData, LineItemData } from "../CardItem";
import { listPageSize, pageSizeForRoom } from "../pageSize";
import { measureListRoom } from "./listRoom";
import { cardListGap, cardListPaddingTop, filterRowGap, filtersSpaceBelow } from "../layoutTokens";
import { PANEL_BODY } from "../panelHeight";
import type { ListChrome, ListDensity } from "../pageSize";
import { ListPager } from "./ListPager";
import { usePanelMinHeightClass } from "./panelMinHeight";

// The list panel: records you act on. A panel fills these slots and nothing
// else -- it has no way to set a height, a class or an item style of its own,
// it cannot draw its own card item (`item` returns data), and it says nothing
// about paging: the page size is the shell's sum over the panel's own chrome
// and density, and the pager, the page state and its reset are here. A list
// panel is one fixed height on a wide page, and its body is paged, never
// scrolled: a full page always fits.

/** The class the item list wears, so the collection can be found by name. */
export const CARD_LIST_CLASS = "cardList";

const useStyles = makeStyles({
  // The panel root: the grid's child. It carries the kind and its minimum
  // height; the frame inside fills it.
  root: { display: "flex", flexDirection: "column", minWidth: 0 },
  frame: { flex: "1 1 auto", minHeight: 0 },
  // The body: the items, a page at a time. It takes what the header and the
  // foot leave and never scrolls -- the page is sized to fit it.
  body: { display: "flex", flexDirection: "column", flex: "1 1 auto", minHeight: 0, minWidth: 0 },
  // The filters: the chip rows in one column, spaced by its gap. A row has no
  // margin, so the space between two rows is there only while both are.
  // The wrapper owns the space under the rows (filtersSpaceBelow); the space
  // above is the frame's gap under the header rule, the same 12 px.
  filters: {
    display: "flex",
    flexDirection: "column",
    rowGap: filterRowGap,
    paddingBottom: filtersSpaceBelow,
    minWidth: 0,
    flexShrink: 0,
  },
  chips: {
    display: "flex",
    flexWrap: "nowrap",
    overflowX: "auto",
    gap: tokens.spacingHorizontalXS,
    flexShrink: 0,
    // The chips are tight and never wrap: at the narrowest width the row
    // scrolls sideways inside the panel instead.
    "& > [role='radio'], & > [role='checkbox']": {
      flexShrink: 0,
      whiteSpace: "nowrap",
      columnGap: tokens.spacingHorizontalXS,
      paddingLeft: tokens.spacingHorizontalS,
      paddingRight: tokens.spacingHorizontalS,
    },
  },
  // The item list: the collection owns the space between its items and over
  // the first. A card item has no margin.
  // A real list: a <ul> with each item in an <li>, the browser's own list
  // styles reset so the only spacing is the tokens'.
  list: {
    display: "flex",
    flexDirection: "column",
    minWidth: 0,
    flexShrink: 0,
    listStyleType: "none",
    marginTop: 0,
    marginRight: 0,
    marginBottom: 0,
    marginLeft: 0,
    paddingRight: 0,
    paddingBottom: 0,
    paddingLeft: 0,
  },
  listItem: { display: "block", minWidth: 0 },
  listFull: { rowGap: cardListGap.full, paddingTop: cardListPaddingTop.full },
  listCompact: {
    rowGap: cardListGap.compact,
    paddingTop: cardListPaddingTop.compact,
  },
  listLine: { rowGap: cardListGap.line, paddingTop: cardListPaddingTop.line },
  // Directly under the filters, the list adds no space of its own over its
  // first item: the filters' wrapper has given it.
  listUnderFilters: { paddingTop: 0 },
  search: { minWidth: 0 },
  picker: { minWidth: 0 },
  foot: { color: tokens.colorNeutralForeground3 },
});

/** One filter chip. */
export interface FilterChip {
  id: string;
  label: string;
  /** Left out, the chip draws no number. */
  count?: number;
  active: boolean;
  onSelect: () => void;
}

/** One row of filter chips: one line, scrolling sideways where it cannot fit. */
export interface FilterRow {
  /** The row's accessible name: "Filter prompts". */
  label: string;
  chips: FilterChip[];
}

export interface SelectOption {
  value: string;
  label: string;
}

/** A small select in the header: a period, a tag. */
export interface SelectSlot {
  /** The select's accessible name. */
  label: string;
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  disabled?: boolean;
}

/** The header's search box. The panel filters; the template resets the page. */
export interface SearchSlot {
  label: string;
  placeholder?: string;
  value: string;
  onChange: (value: string) => void;
}

export interface RefreshSlot {
  onClick: () => void;
  isFetching?: boolean;
  disabled?: boolean;
}

/** The foot's +. The label is the title of the dialog it opens. */
export interface CreateSlot {
  label: string;
  onClick: () => void;
}

/** One header button for a thing the whole panel does. */
export interface ActionSlot {
  label: string;
  glyph: ReactElement;
  onClick: () => void;
  disabled?: boolean;
  title?: string;
}

export interface LoadingSlot {
  label: string;
}

/** A chart, drawn by the panel's own chart component. */
export interface ChartSpec {
  /** What the chart shows, for a screen reader. */
  label: string;
  chart: ReactElement;
}

/** One summary figure above the items, as data: the kind draws it as a stat tile. */
export interface StatSpec {
  /** Stable among its row: a data-stat attribute, for a test. */
  id: string;
  count: string | number;
  label: string;
  /** Green, red or orange; left out, the theme's text colour. */
  tone?: "pass" | "fail" | "warn";
  /** A sentence about the figure, as its native title (the kinds carry no tooltip). */
  detail?: string;
}

/** One row of summary figures. */
export interface StatRow {
  /** The row's accessible name: "Last run". */
  label: string;
  stats: StatSpec[];
}

/** What sits above the items: rows of summary figures, then a chart, either or both. */
export interface ListLead {
  stats?: StatRow[];
  chart?: ChartSpec;
}

const TONE_COLOR: Record<NonNullable<StatSpec["tone"]>, string> = {
  pass: tokens.colorPaletteGreenForeground1,
  fail: tokens.colorPaletteRedForeground1,
  warn: tokens.colorPaletteDarkOrangeForeground1,
};

function LeadStat({ spec }: { spec: StatSpec }) {
  return (
    <StatTile
      count={spec.count}
      label={spec.label}
      data-stat={spec.id}
      title={spec.detail}
      color={spec.tone ? TONE_COLOR[spec.tone] : undefined}
    />
  );
}

/** What a write on the panel came to, or what it is doing now. */
export type PanelStatus =
  | { tone: "success" | "error"; text: string; onDismiss: () => void }
  | { tone: "busy"; text: string };

interface ListPanelBase<T> {
  title: string;
  icon?: ReactElement;
  /** What the panel holds, behind the info icon beside its title. */
  info?: ReactNode;
  /** The info icon's accessible name. */
  infoLabel?: string;
  items: T[];
  lead?: ListLead;
  filters?: FilterRow[];
  pickers?: SelectSlot[];
  search?: SearchSlot;
  action?: ActionSlot;
  refresh?: RefreshSlot;
  /** The header's count chip. A string is a count that needs a word: "latest 500". */
  count?: number | string;
  /** The count chip's accessible name: "12 prompts". */
  countLabel?: string;
  create?: CreateSlot;
  /** Shown when there are no items. */
  empty: EmptyMessage;
  /** Shown instead of `empty` when a filter or a search hid every item. */
  filteredEmpty?: EmptyMessage;
  status?: PanelStatus;
  footLeft?: string;
  footNote?: ReactElement;
  /** Present while the panel is reading. */
  loading?: LoadingSlot;
  // No className, no style, no height, no children.
  // No pageSize and no pager slot: the template works the page size out from
  // the shell's table for this panel's chrome and density, and draws the pager.
}

export interface FullListPanelProps<T> extends ListPanelBase<T> {
  density?: "full";
  /** Data, not JSX: a panel cannot draw its own card item. */
  item: (entry: T) => CardItemData;
}

/** A panel whose items never have a description: every item is the shorter one. */
export interface CompactListPanelProps<T> extends ListPanelBase<T> {
  density: "compact";
  item: (entry: T) => CompactItemData;
}

export interface LineListPanelProps<T> extends ListPanelBase<T> {
  density: "line";
  item: (entry: T) => LineItemData;
}

export type ListPanelProps<T> =
  FullListPanelProps<T> | CompactListPanelProps<T> | LineListPanelProps<T>;

/** What the template watches to send the list back to its first page. */
function filterSignature<T>(props: ListPanelProps<T>): string {
  return JSON.stringify([
    props.filters?.map((row) => row.chips.filter((c) => c.active).map((c) => c.id)),
    props.pickers?.map((p) => p.value),
    props.search?.value,
  ]);
}

export function ListPanel<T>(props: ListPanelProps<T>) {
  const styles = useStyles();
  const minHeight = usePanelMinHeightClass("list");
  const {
    title,
    icon,
    info,
    items,
    lead,
    filters,
    pickers,
    search,
    action,
    refresh,
    count,
    create,
    status,
    footLeft,
    footNote,
    loading,
  } = props;
  const density: ListDensity = props.density ?? "full";
  // The page: as many items as fit under this panel's own chrome.
  const chrome: ListChrome = {
    density,
    filterRows: loading ? 0 : (filters?.length ?? 0),
    lead: lead != null && !loading,
    footNote: footNote != null,
    status: status != null,
  };
  // The static sum is the first paint's answer and the answer where nothing
  // can be measured; once the list is laid out, the room it really has decides.
  const [room, setRoom] = useState<number | null>(null);
  const pageSize = room === null ? listPageSize(chrome) : pageSizeForRoom(density, room);

  // The page is held as the index of its first item, so when a resize changes
  // the page size the item at the top of the page stays in view. It goes back
  // to the first item when a filter, a picker or the search changes, and is
  // clamped when the list shrinks.
  const signature = filterSignature(props);
  const [chosenFirst, setChosenFirst] = useState(0);
  const [seen, setSeen] = useState(signature);
  if (seen !== signature) {
    setSeen(signature);
    setChosenFirst(0);
  }
  const totalPages = Math.max(1, Math.ceil(items.length / pageSize));
  const page = Math.min(
    seen === signature ? Math.floor(chosenFirst / pageSize) : 0,
    totalPages - 1,
  );
  const pageItems = items.slice(page * pageSize, (page + 1) * pageSize);
  const hasFoot = Boolean(footLeft) || create != null || (totalPages > 1 && !loading);

  // Measure after every draw, and again whenever the panel or anything above
  // the list changes size by itself (a result block that loads, a window that
  // narrows the header into two lines).
  const rootRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  useLayoutEffect(() => {
    const root = rootRef.current;
    const list = listRef.current;
    const frame = root?.firstElementChild as HTMLElement | null;
    const frameBody = frame?.querySelector<HTMLElement>(":scope > [data-panel-frame-body]");
    if (!root || !list || !frame || !frameBody) return;
    const measure = () => {
      const next = measureListRoom(root, frame, frameBody, list, hasFoot);
      setRoom((was) => (was === next ? was : next));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(root);
    for (const el of Array.from(frame.children)) if (el !== frameBody) observer.observe(el);
    const body = list.parentElement;
    for (const el of Array.from(body?.children ?? [])) if (el !== list) observer.observe(el);
    return () => observer.disconnect();
  });

  // One entry, drawn at the panel's density from the data its `item` returns.
  const drawItem = (entry: T): { id?: string; element: ReactElement } => {
    if (props.density === "line") {
      const data = props.item(entry);
      return { id: data.id, element: <LineItem data={data} /> };
    }
    if (props.density === "compact") {
      const data = props.item(entry);
      return { id: data.id, element: <CompactItem data={data} /> };
    }
    const data = props.item(entry);
    return { id: data.id, element: <CardItem data={data} /> };
  };

  // The list sits right under the chips: the chips' wrapper owns that space.
  const underFilters = !loading && (filters?.length ?? 0) > 0 && !lead;
  const none = items.length === 0 ? (props.filteredEmpty ?? props.empty) : null;

  return (
    <div
      ref={rootRef}
      className={mergeClasses(styles.root, minHeight)}
      data-panel-kind="list"
      data-panel-density={density}
      data-panel-foot-note={chrome.footNote ? "" : undefined}
    >
      <PanelFrame
        className={styles.frame}
        headerLeft={
          <>
            {icon}
            <Subtitle2>{title}</Subtitle2>
            {info != null ? (
              <InfoTip label={props.infoLabel ?? `About ${title}`} content={info} />
            ) : null}
          </>
        }
        headerRight={
          <>
            {pickers?.map((p) => (
              <Select
                key={p.label}
                size="small"
                className={styles.picker}
                aria-label={p.label}
                value={p.value}
                disabled={p.disabled}
                onChange={(_e, d) => p.onChange(d.value)}
              >
                {p.options.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </Select>
            ))}
            {search ? (
              <Input
                size="small"
                type="search"
                className={styles.search}
                aria-label={search.label}
                placeholder={search.placeholder}
                value={search.value}
                onChange={(_e, d) => search.onChange(d.value)}
              />
            ) : null}
            {action ? (
              <Button
                size="small"
                appearance="subtle"
                icon={action.glyph}
                title={action.title}
                disabled={action.disabled}
                onClick={action.onClick}
              >
                {action.label}
              </Button>
            ) : null}
            {refresh ? (
              <RefreshButton
                onClick={refresh.onClick}
                isFetching={refresh.isFetching}
                disabled={refresh.disabled}
              />
            ) : null}
            {count != null ? (
              <Badge
                color="informative"
                appearance="filled"
                size="large"
                aria-label={props.countLabel}
                data-panel-count
              >
                {count}
              </Badge>
            ) : null}
          </>
        }
        footerLeft={footLeft ? <Caption1 className={styles.foot}>{footLeft}</Caption1> : undefined}
        footerCenter={
          totalPages > 1 && !loading ? (
            <ListPager
              page={page}
              totalPages={totalPages}
              onPageChange={(to) => setChosenFirst(to * pageSize)}
            />
          ) : undefined
        }
        footerRight={
          create ? <CreateButton label={create.label} onClick={create.onClick} /> : undefined
        }
        footNote={footNote}
        body={
          <div className={styles.body} data-panel-body={PANEL_BODY.list}>
            {status ? (
              <div data-panel-status>
                {status.tone === "busy" ? (
                  <Caption1 role="status">{status.text}</Caption1>
                ) : (
                  <StatusMessage status={status.tone} onDismiss={status.onDismiss}>
                    {status.text}
                  </StatusMessage>
                )}
              </div>
            ) : null}
            {loading ? (
              <CardSpinner label={loading.label} />
            ) : (
              <>
                {filters?.length ? (
                  <div className={styles.filters} data-panel-filters>
                    {filters.map((row) => (
                      <div
                        key={row.label}
                        className={styles.chips}
                        role="group"
                        aria-label={row.label}
                      >
                        {row.chips.map((chip) => (
                          <FilterBadge
                            key={chip.id}
                            label={chip.label}
                            count={chip.count}
                            active={chip.active}
                            onClick={chip.onSelect}
                          />
                        ))}
                      </div>
                    ))}
                  </div>
                ) : null}
                {lead ? (
                  <>
                    <div data-panel-lead>
                      {lead.stats?.map((row) => (
                        <div key={row.label} role="group" aria-label={row.label}>
                          <StatTiles>
                            {row.stats.map((spec) => (
                              <LeadStat key={spec.id} spec={spec} />
                            ))}
                          </StatTiles>
                        </div>
                      ))}
                      {lead.chart ? (
                        <div role="group" aria-label={lead.chart.label}>
                          {lead.chart.chart}
                        </div>
                      ) : null}
                    </div>
                    <HairlineDivider />
                  </>
                ) : null}
                {none ? <EmptyState {...none} /> : null}
                {pageItems.length > 0 ? (
                  <ul
                    ref={listRef}
                    role="list"
                    className={mergeClasses(
                      CARD_LIST_CLASS,
                      styles.list,
                      density === "line"
                        ? styles.listLine
                        : density === "compact"
                          ? styles.listCompact
                          : styles.listFull,
                      underFilters && styles.listUnderFilters,
                    )}
                    data-card-list=""
                  >
                    {pageItems.map((entry, i) => {
                      const drawn = drawItem(entry);
                      return (
                        <li key={drawn.id ?? `${page}-${i}`} className={styles.listItem}>
                          {drawn.element}
                        </li>
                      );
                    })}
                  </ul>
                ) : null}
              </>
            )}
          </div>
        }
      />
    </div>
  );
}
