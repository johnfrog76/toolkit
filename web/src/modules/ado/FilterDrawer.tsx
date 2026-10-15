import { useState, useMemo } from "react";
import { Badge, SearchBox, Button, Tooltip, makeStyles, tokens } from "@fluentui/react-components";
import { FilterRegular } from "@fluentui/react-icons";
import { FilterBadge } from "../../shared/FilterBadge";
import { getProjectTag } from "./repoTags";
import { useGetEnvQuery } from "../../shell/api";
import { useGetStatusQuery } from "./api.ado";
import { linkRowOf, showLinkRow, typeRowOf } from "./promptFilters";
import type { DrawerSection } from "./homeTabs";
import { IssueFilterRows } from "./IssueFilterRows";
import { DesignKindRow, DocsFolderRow } from "./DocFilterRows";
import { useDesignFilters, useDocsFilters } from "./docFilters";

const useStyles = makeStyles({
  root: {
    marginBottom: tokens.spacingVerticalL,
  },
  toggle: {
    display: "flex",
    justifyContent: "flex-end",
  },
  panel: {
    display: "grid",
    transitionProperty: "grid-template-rows, opacity",
    transitionTimingFunction: tokens.curveEasyEase,
    transitionDuration: tokens.durationNormal,
  },
  panelOpen: {
    gridTemplateRows: "1fr",
    opacity: 1,
    paddingTop: tokens.spacingVerticalM,
    paddingBottom: tokens.spacingVerticalS,
  },
  panelClosed: {
    gridTemplateRows: "0fr",
    opacity: 0,
  },
  panelInner: {
    overflow: "hidden",
  },
  searchRow: {
    display: "flex",
    justifyContent: "center",
    gap: tokens.spacingHorizontalM,
    alignItems: "center",
    marginBottom: tokens.spacingVerticalM,
  },
  searchBox: {
    width: "300px",
  },
  repoRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    justifyContent: "center",
    marginBottom: tokens.spacingVerticalS,
  },
  stateRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    justifyContent: "center",
  },
  typeRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    justifyContent: "center",
    marginBottom: tokens.spacingVerticalS,
  },
  tagBadge: {
    fontWeight: tokens.fontWeightSemibold,
    fontSize: tokens.fontSizeBase100,
    letterSpacing: "0.5px",
  },
});

interface FilterDrawerProps {
  value: string;
  onChange: (value: string) => void;
  activeRepo: string | null;
  onRepoChange: (repo: string | null) => void;
  stateFilter: string;
  onStateChange: (value: string) => void;
  stateOptions: string[];
  /** What a state is CALLED here -- the org's lane name; the value stays the contract's word. */
  stateLabel?: (state: string) => string;
  /** A card type, "Untyped", or "All". */
  typeFilter: string;
  onTypeChange: (type: string) => void;
  /** "Linked", "Custom", or "All". Optional, so a caller that predates
   *  the row gets All and no row. */
  linkFilter?: string;
  onLinkChange?: (link: string) => void;
  /** Which sections this tab's drawer holds (`drawerSections` in
   *  homeTabs.ts). Absent is the card drawer as it always was. */
  sections?: DrawerSection[];
}

const CARD_DRAWER: DrawerSection[] = ["search", "cards", "ado"];

/** What the slot says on a tab with nothing to filter by: the control
 *  stays, disabled, and this is its tooltip. One constant, so the test and the
 *  documents read the same words. */
export const NO_FILTERS = "No filters on this tab";

export function FilterDrawer({
  value,
  onChange,
  activeRepo,
  onRepoChange,
  stateFilter,
  onStateChange,
  stateOptions,
  stateLabel = (s) => s,
  typeFilter,
  onTypeChange,
  linkFilter = "All",
  onLinkChange,
  sections = CARD_DRAWER,
}: FilterDrawerProps) {
  const styles = useStyles();
  const [open, setOpen] = useState(false);
  const has = (s: DrawerSection) => sections.includes(s);
  // The toolbar slot is drawn on EVERY tab of the strip: a tab with no
  // sections keeps the same control, in the same place and size, disabled.
  const none = sections.length === 0;
  // Design and Docs each keep their own text: it is theirs alone, so
  // words typed on the Issues never hide a design note behind a closed drawer.
  const design = useDesignFilters();
  const docs = useDocsFilters();
  const text = has("kind")
    ? { value: design.text, set: design.setText, hint: "Title" }
    : has("folder")
      ? { value: docs.text, set: docs.setText, hint: "Title or path" }
      : null;

  const { data: env } = useGetEnvQuery();
  // The type row is counted from the CARDS -- the same /api/status the list
  // and the board read, so the badges are what is on screen and move when it
  // does. (The repo row below counts configuration, and its numbers never
  // move.)
  const { data: status } = useGetStatusQuery();
  const typeRow = useMemo(
    () => typeRowOf(status?.prompts ?? [], env?.cardTypes ?? []),
    [status?.prompts, env?.cardTypes],
  );
  const cardCount = status?.prompts.length ?? 0;
  // Linked or custom, counted from the same cards. Drawn only in a MIXED
  // Space -- see showLinkRow for why an all-custom Space grows no control.
  const linkRow = useMemo(() => linkRowOf(status?.prompts ?? []), [status?.prompts]);
  const linkRowShown = !!onLinkChange && showLinkRow(status?.prompts ?? [], linkFilter);

  const projects = useMemo(() => {
    const seen = new Set<string>();
    return (env?.config?.projects ?? []).filter((p) => {
      if (seen.has(p.name)) return false;
      seen.add(p.name);
      return true;
    });
  }, [env?.config?.projects]);

  const repoCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const p of env?.config?.projects ?? []) {
      counts[p.name] = (counts[p.name] ?? 0) + 1;
    }
    return counts;
  }, [env?.config?.projects]);

  const totalCount = Object.values(repoCounts).reduce((s, c) => s + c, 0);

  return (
    <div className={styles.root}>
      <div className={styles.toggle}>
        {/* disabledFocusable, not disabled: the button stays in the tab order
            and keeps aria-disabled, so the tooltip is reachable by keyboard
            and read by a screen reader; the click does nothing. */}
        <Tooltip content={NO_FILTERS} relationship="description" visible={none ? undefined : false}>
          <Button
            appearance="subtle"
            icon={<FilterRegular />}
            onClick={() => setOpen((o) => !o)}
            title={none ? undefined : "Filters"}
            aria-label="Filters"
            aria-expanded={none ? undefined : open}
            aria-controls={none ? undefined : "filter-panel"}
            disabledFocusable={none}
          />
        </Tooltip>
      </div>
      <div
        id="filter-panel"
        role="region"
        className={`${styles.panel} ${open && !none ? styles.panelOpen : styles.panelClosed}`}
      >
        <div className={styles.panelInner}>
          <div className={styles.searchRow}>
            {/* Dual entry: an exact card id, or words from the title or the
                file, in any order (promptFilters.ts). It said "Work Item ID",
                which is Azure DevOps's name for a box that matches four
                other things. */}
            {/* On the Issues it searches the issues: a number is that
                issue, words match the title and the labels (issueMatches). */}
            <SearchBox
              className={styles.searchBox}
              placeholder={
                text?.hint ??
                (has("issues") ? "Issue number, title or label" : "Card id, title or file")
              }
              value={text?.value ?? value}
              onChange={(_e, data) => (text ? text.set(data.value) : onChange(data.value))}
            />
          </div>
          {/* The GitHub issue filters: state, assignee, worked by, and
              GitHub's labels -- only where the Issues list is. */}
          {has("issues") && <IssueFilterRows />}
          {/* Design's kind and Docs' folder: chip rows, like every
              other axis here -- one control kind, not a second one. */}
          {has("kind") && <DesignKindRow />}
          {has("folder") && <DocsFolderRow />}
          {/* Type is a coarse cut, not a way to find one card: the measured
              payoff is "hide the half that are Bugs". Text finds one card. A
              card whose heading names no configured type is "Untyped", its own
              badge and inside All. Only an active badge ever hides a card. */}
          {has("cards") && cardCount > 0 && (
            <div className={styles.typeRow} role="radiogroup" aria-label="Card type">
              <FilterBadge
                label="All"
                count={cardCount}
                active={typeFilter === "All"}
                appearance="pink"
                onClick={() => onTypeChange("All")}
              />
              {typeRow.map((t) => (
                <FilterBadge
                  key={t.label}
                  label={t.label}
                  count={t.count}
                  active={typeFilter === t.label}
                  appearance="pink"
                  onClick={() => onTypeChange(typeFilter === t.label ? "All" : t.label)}
                />
              ))}
            </div>
          )}
          {/* Linked or custom: does a tracker's ledger stand behind the card?.
             From the card's own tracker link, never from the Space --
              so it never cares WHICH tracker; the card's gh / ado badge
              answers that. */}
          {has("cards") && linkRowShown && onLinkChange && (
            <div className={styles.typeRow} role="radiogroup" aria-label="Tracker link">
              <FilterBadge
                label="All"
                count={cardCount}
                active={linkFilter === "All"}
                onClick={() => onLinkChange("All")}
              />
              <FilterBadge
                label="Linked"
                count={linkRow.linked}
                active={linkFilter === "Linked"}
                onClick={() => onLinkChange(linkFilter === "Linked" ? "All" : "Linked")}
              />
              <FilterBadge
                label="Custom"
                count={linkRow.custom}
                active={linkFilter === "Custom"}
                onClick={() => onLinkChange(linkFilter === "Custom" ? "All" : "Custom")}
              />
            </div>
          )}
          {/* THE RULE: the repo row appears only when the org declares projects
              -- an Azure DevOps org. A card with no ADO repo is never hidden
              by it: it stays in view under every project. */}
          {has("ado") && projects.length > 0 && (
            <div className={styles.repoRow}>
              <FilterBadge
                label="All"
                count={totalCount}
                active={activeRepo === null}
                onClick={() => onRepoChange(null)}
              />
              {projects.map((p) => (
                <FilterBadge
                  key={p.name}
                  label={p.name}
                  count={repoCounts[p.name] ?? 0}
                  active={activeRepo === p.name}
                  onClick={() => onRepoChange(activeRepo === p.name ? null : p.name)}
                >
                  <Badge
                    className={styles.tagBadge}
                    appearance="outline"
                    color="informative"
                    size="small"
                  >
                    {getProjectTag(p.name)}
                  </Badge>
                </FilterBadge>
              ))}
            </div>
          )}
          {has("cards") && stateOptions.length > 1 && (
            <div className={styles.stateRow}>
              <FilterBadge
                label="All"
                active={stateFilter === "All"}
                appearance="orange"
                onClick={() => onStateChange("All")}
              />
              {stateOptions
                .filter((s) => s !== "All")
                .map((s) => (
                  <FilterBadge
                    key={s}
                    label={stateLabel(s)}
                    active={stateFilter === s}
                    appearance="orange"
                    onClick={() => onStateChange(stateFilter === s ? "All" : s)}
                  />
                ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
