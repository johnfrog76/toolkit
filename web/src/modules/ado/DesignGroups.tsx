import { useState } from "react";
import type { ReactNode } from "react";
import {
  Badge,
  Button,
  Caption1,
  Link,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { ChevronDownRegular, ChevronRightRegular } from "@fluentui/react-icons";
import { DESIGN } from "../../shell/consts";
import { FilterBadge } from "../../shared/FilterBadge";
import type { Design, DesignNotShown } from "./api.ado";

// The Design tab's ONE list, grouped by state (docs/hub/design.md,
// "State -- derived, never stored"): Design, Spec, Complete, Archived, in that order -- the road's
// order, DESIGN.states. Complete and Archived are collapsed to a count until
// opened or searched. The rows are the caller's (a repo's row links github.com,
// the hub's wears a Space chip); the grouping, the collapse and the "not shown"
// line are drawn here once, so a repo's tab and the hub's drawer read the same.
//
// Non-compliance teaches (D-DL11): a file with no id is COUNTED under the list
// with the fix named (StampDesign) and Learn more to the contract. Never
// inference, never a blank.

/** The contract, as a page on GitHub: what the four folders and the id are for. */
export const DESIGN_LEARN_MORE =
  "https://github.com/johnfrog76/toolkit/blob/main/docs/hub/design.md";

/** The groups a person sees closed until they open them or type a search. */
const COLLAPSED_BY_DEFAULT = new Set([DESIGN.states[2], DESIGN.states[3]]);

const useStyles = makeStyles({
  group: { marginTop: tokens.spacingVerticalM },
  groupHeader: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    minHeight: "28px",
  },
  toggle: { minWidth: "auto", padding: `0 ${tokens.spacingHorizontalXS}` },
  outcomes: {
    display: "flex",
    gap: tokens.spacingHorizontalXS,
    flexWrap: "wrap",
    marginLeft: tokens.spacingHorizontalS,
  },
  notShown: {
    display: "block",
    marginTop: tokens.spacingVerticalM,
    color: tokens.colorNeutralForeground3,
  },
});

/** The badge colour a state wears, the same on every row and group. */
export function stateColor(state: string): "brand" | "informative" | "success" | "subtle" {
  const [design, spec, complete] = DESIGN.states;
  if (state === design) return "brand";
  if (state === spec) return "informative";
  if (state === complete) return "success";
  return "subtle";
}

/** The designs grouped by state in road order; a state with none is left out. */
export function groupByState(designs: Design[]): Array<{ state: string; designs: Design[] }> {
  return DESIGN.states
    .map((state) => ({ state, designs: designs.filter((d) => d.state === state) }))
    .filter((g) => g.designs.length > 0);
}

/** The one line under the list about the files that are not designs, or "" when
 *  every file is one. Counts by reason: the stamp fixes "no id"; a shared id a
 *  person has to resolve. */
export function notShownLine(notShown: DesignNotShown[], stampHint: string): string {
  if (notShown.length === 0) return "";
  const noId = notShown.filter((n) => n.reason === "no id").length;
  const conflicts = notShown.length - noId;
  const parts: string[] = [];
  if (noId > 0)
    parts.push(
      `${noId} ${noId === 1 ? "file" : "files"} not shown: no id. Give ${noId === 1 ? "it one" : "them ids"} with ${stampHint}.`,
    );
  if (conflicts > 0)
    parts.push(
      `${conflicts} ${conflicts === 1 ? "file" : "files"} not shown: two notes or two specs carry one id.`,
    );
  return parts.join(" ");
}

interface DesignGroupsProps {
  designs: Design[];
  notShown: DesignNotShown[];
  /** The row for one design: the caller's, so each place keeps its own actions. */
  renderRow: (design: Design) => ReactNode;
  /** The stamp as a person types it here: `tkStampDesign`, or `tkStampDesign -Hub`. */
  stampHint: string;
  /** The whole list when `designs` is one page of it: a group's badge counts
   *  the list, not the page. Absent, `designs` is the whole list. */
  counted?: Design[];
  /** A search in the box opens the collapsed groups that have a match. */
  searching?: boolean;
}

/** The Archived group's outcome filter (L2b): what became of a note archived
 *  without a spec -- shipped, dropped, or nothing said. "all" is off. */
export const ALL_OUTCOMES = "all";
export const NO_OUTCOME = "none";

/** The Archived rows an outcome chip leaves: all, one outcome, or those with none. */
export function archivedByOutcome(rows: Design[], outcome: string): Design[] {
  if (outcome === ALL_OUTCOMES) return rows;
  if (outcome === NO_OUTCOME) return rows.filter((d) => !d.outcome);
  return rows.filter((d) => d.outcome === outcome);
}

export function DesignGroups({
  designs,
  notShown,
  renderRow,
  stampHint,
  searching = false,
  counted,
}: DesignGroupsProps) {
  const styles = useStyles();
  const [opened, setOpened] = useState<Record<string, boolean>>({});
  const [outcome, setOutcome] = useState<string>(ALL_OUTCOMES);
  const groups = groupByState(designs);
  const totals = counted ? groupByState(counted) : groups;
  const line = notShownLine(notShown, stampHint);
  const archivedState = DESIGN.states[3];
  return (
    <>
      {groups.map(({ state, designs: rows }) => {
        const collapsible = COLLAPSED_BY_DEFAULT.has(state);
        const open = !collapsible || searching || !!opened[state];
        const isArchived = state === archivedState;
        const shown = isArchived ? archivedByOutcome(rows, outcome) : rows;
        return (
          <section key={state} className={styles.group} aria-label={`${state} designs`}>
            <div className={styles.groupHeader}>
              {collapsible ? (
                <Button
                  className={styles.toggle}
                  size="small"
                  appearance="subtle"
                  icon={open ? <ChevronDownRegular /> : <ChevronRightRegular />}
                  aria-expanded={open}
                  aria-label={`${open ? "Hide" : "Show"} ${state}`}
                  onClick={() => setOpened((o) => ({ ...o, [state]: !open }))}
                />
              ) : null}
              <Subtitle2>{state}</Subtitle2>
              <Badge appearance="tint" size="small" color={stateColor(state)}>
                {isArchived && outcome !== ALL_OUTCOMES
                  ? `${shown.length} of ${rows.length}`
                  : (totals.find((t) => t.state === state)?.designs.length ?? rows.length)}
              </Badge>
              {isArchived && open ? (
                <div role="radiogroup" aria-label="Archived outcome" className={styles.outcomes}>
                  <FilterBadge
                    label="any outcome"
                    appearance="pink"
                    active={outcome === ALL_OUTCOMES}
                    onClick={() => setOutcome(ALL_OUTCOMES)}
                  />
                  {DESIGN.outcomes.map((o) => (
                    <FilterBadge
                      key={o}
                      label={o}
                      appearance="pink"
                      active={outcome === o}
                      onClick={() => setOutcome(outcome === o ? ALL_OUTCOMES : o)}
                    />
                  ))}
                  <FilterBadge
                    label="nothing said"
                    appearance="pink"
                    active={outcome === NO_OUTCOME}
                    onClick={() => setOutcome(outcome === NO_OUTCOME ? ALL_OUTCOMES : NO_OUTCOME)}
                  />
                </div>
              ) : null}
            </div>
            {open ? shown.map((d) => renderRow(d)) : null}
            {open && isArchived && shown.length === 0 && rows.length > 0 ? (
              <Caption1 role="status">No archived design with that outcome.</Caption1>
            ) : null}
          </section>
        );
      })}
      {line ? (
        <Caption1 role="status" className={styles.notShown}>
          {line}{" "}
          <Link href={DESIGN_LEARN_MORE} target="_blank" rel="noopener noreferrer">
            Learn more
          </Link>
        </Caption1>
      ) : null}
    </>
  );
}

/** What a product (or the hub) gets from the four folders -- the shared empty
 *  state's words, with Learn more to the contract (D-DL11). */
export const NO_STRUCTURE = {
  title: "No design/ folder yet",
  detail:
    "A design/ folder beside spec/, each with an archive/, gives a product a Design tab: notes, the specs they became, and what was finished or dropped -- each read in its own room, grouped by state. Every file carries an id in its frontmatter; StampDesign gives the files theirs.",
};

export function LearnMoreLink() {
  return (
    <Link href={DESIGN_LEARN_MORE} target="_blank" rel="noopener noreferrer">
      Learn more
    </Link>
  );
}
