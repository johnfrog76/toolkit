import { Body1, makeStyles, tokens } from "@fluentui/react-components";
import { useGetGrowthQuery } from "./api.growth";
import type { TrainingQuarter } from "./api.growth";

const useStyles = makeStyles({
  line: {
    color: tokens.colorNeutralForeground2,
    paddingBottom: tokens.spacingVerticalS,
  },
});

const WORDS = [
  "zero",
  "one",
  "two",
  "three",
  "four",
  "five",
  "six",
  "seven",
  "eight",
  "nine",
  "ten",
];

/** How long is left, in the words a person would say: days inside two weeks, weeks after. */
export function timeLeft(days: number): string {
  if (days <= 0) return "last day";
  if (days === 1) return "1 day left";
  if (days < 14) return `${days} days left`;
  const weeks = Math.round(days / 7);
  return `${WORDS[weeks] ?? String(weeks)} weeks left`;
}

/** "Q3: 6 of 8 hours, two weeks left" -- planned hours are added only when there are some. */
export function quarterLineText(q: TrainingQuarter): string {
  const label = q.quarter.split(" ")[0];
  const planned = q.planned > 0 ? `, ${q.planned} planned` : "";
  return `${label}: ${q.hours} of ${q.required} hours${planned}, ${timeLeft(q.daysLeft)}`;
}

/**
 * The one line at the top of the Growth page: where the quarter's training
 * requirement stands. The agent answers `trainingQuarter: null` when the active
 * Space states no requirement, and then nothing is drawn -- off means absent.
 * It reads the same `/growth` the goals card does, so it costs no second fetch.
 */
export function QuarterLine() {
  const styles = useStyles();
  const { data } = useGetGrowthQuery();
  const quarter = data?.trainingQuarter;
  if (!quarter) return null;
  return (
    <Body1 as="p" className={styles.line} data-testid="training-quarter">
      {quarterLineText(quarter)}
    </Body1>
  );
}
