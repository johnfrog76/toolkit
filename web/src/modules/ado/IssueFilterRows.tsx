/**
 * The GitHub issue filters, in the filter drawer. The owner's rule: "there is no
 * reason why GitHub issues tags and filters not live in here -- we cannot have
 * ADO and Issues in the same space and so it is conditional logic." The drawer
 * draws this section on a GitHub Space's Issues tab (`drawerSections` in
 * homeTabs.ts); the list under it reads the same choices (useIssueChoices), so
 * the chips live in ONE place and the tab shows a one-line summary of them.
 *
 * Three chip groups -- state, assignee, worked by -- then GitHub's own
 * label vocabulary: kind, severity, milestone. Rows, not Selects, so
 * every choice reads the same way as the drawer's other rows.
 */
import { makeStyles, tokens } from "@fluentui/react-components";
import { FilterBadge } from "../../shared/FilterBadge";
import { useGetWorkItemsQuery } from "./api.ado";
import { ASSIGNEE_CHIPS, KIND_CHOICES, SEV_CHOICES, STATE_CHIPS, issueKind } from "./issueAxes";
import { effectiveIssueChoice, useIssueChoices } from "./useIssueChoices";

const useStyles = makeStyles({
  row: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    justifyContent: "center",
    marginBottom: tokens.spacingVerticalS,
  },
});

export function IssueFilterRows() {
  const styles = useStyles();
  const c = useIssueChoices();
  // The same cache entry the list reads -- no second fetch.
  const { data, isFetching } = useGetWorkItemsQuery(c.queryArg);
  const items = data?.items ?? [];
  const { choice, workers, milestones } = effectiveIssueChoice(c.stored, items);
  // The state and assignee chips are the agent's questions, and only the answer to the one
  // asked is held, so they carry no count (null, on purpose). Every other chip counts the
  // rows that answer holds.
  const n = (keep: (i: (typeof items)[number]) => boolean) => items.filter(keep).length;
  return (
    <div data-issue-filters="">
      <div className={styles.row} role="radiogroup" aria-label="Issue state">
        {STATE_CHIPS.map((s) => (
          <FilterBadge
            key={s.value}
            label={s.label}
            count={null}
            active={choice.state === s.value}
            onClick={() => {
              if (!isFetching) c.setState(s.value);
            }}
          />
        ))}
      </div>
      <div className={styles.row} role="radiogroup" aria-label="Assigned to">
        {ASSIGNEE_CHIPS.map((a) => (
          <FilterBadge
            key={a.value}
            label={a.label}
            count={null}
            active={choice.assignee === a.value}
            onClick={() => {
              if (!isFetching) c.setAssignee(a.value);
            }}
          />
        ))}
      </div>
      {workers.length > 0 && (
        <div className={styles.row} role="radiogroup" aria-label="Worked by">
          <FilterBadge
            label="all"
            count={items.length}
            active={choice.worker === "all"}
            onClick={() => c.setWorker("all")}
          />
          {workers.map((w) => (
            <FilterBadge
              key={w}
              label={w}
              count={n((i) => i.worker === w)}
              appearance="tabColorThree"
              active={choice.worker === w}
              onClick={() => c.setWorker(choice.worker === w ? "all" : w)}
            />
          ))}
        </div>
      )}
      <div className={styles.row} role="radiogroup" aria-label="Kind">
        <FilterBadge
          label="any kind"
          count={items.length}
          appearance="tabColorTwo"
          active={choice.kind === "all"}
          onClick={() => c.setKind("all")}
        />
        {KIND_CHOICES.map((k) => (
          <FilterBadge
            key={k}
            label={k}
            count={n((i) => issueKind(i) === k)}
            appearance="tabColorTwo"
            active={choice.kind === k}
            onClick={() => c.setKind(choice.kind === k ? "all" : k)}
          />
        ))}
      </div>
      <div className={styles.row} role="radiogroup" aria-label="Severity">
        <FilterBadge
          label="any sev"
          count={items.length}
          appearance="tabColorTwo"
          active={choice.sev === "all"}
          onClick={() => c.setSev("all")}
        />
        {SEV_CHOICES.map((s) => (
          <FilterBadge
            key={s}
            label={s}
            count={n((i) => (i.labels ?? []).includes(s))}
            appearance="tabColorTwo"
            active={choice.sev === s}
            onClick={() => c.setSev(choice.sev === s ? "all" : s)}
          />
        ))}
      </div>
      {milestones.length > 0 && (
        <div className={styles.row} role="radiogroup" aria-label="Milestone">
          <FilterBadge
            label="any milestone"
            count={items.length}
            active={choice.milestone === "all"}
            onClick={() => c.setMilestone("all")}
          />
          {milestones.map((m) => (
            <FilterBadge
              key={m}
              label={m}
              count={n((i) => i.sprint === m)}
              active={choice.milestone === m}
              onClick={() => c.setMilestone(choice.milestone === m ? "all" : m)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
