import { useNavigate } from "react-router";
import { Tab, TabList, makeStyles, tokens } from "@fluentui/react-components";
import { StandupPage } from "./StandupPage";
import { TriagePage } from "./TriagePage";
import { ROUTES } from "./paths";

// The Team Agile tab's two ceremonies, Standup | Triage: one nav entry,
// and under it a strip of in-page tabs, each an ADDRESS -- the shape Home's
// Focus | Board | Sprint | Actions strip has, so a tab can be linked and
// Back walks between them. The pages themselves know nothing about the strip:
// StandupPage is drawn exactly as it was, Play and the attend call with it.

export type Ceremony = "standup" | "triage";

const CEREMONIES: { id: Ceremony; label: string; to: string }[] = [
  { id: "standup", label: "Standup", to: ROUTES.home },
  { id: "triage", label: "Triage", to: ROUTES.triage },
];

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalS, width: "100%" },
  // The strip's text starts flush with the card under it -- Home's rule (routes.tsx).
  bar: { paddingLeft: tokens.spacingHorizontalS },
  tabs: {
    marginLeft: `calc(-1 * (${tokens.spacingHorizontalSNudge} + ${tokens.spacingHorizontalXXS}))`,
  },
});

export function RitualTabs({ current }: { current: Ceremony }) {
  const styles = useStyles();
  const navigate = useNavigate();
  return (
    <div className={styles.bar}>
      <TabList
        className={styles.tabs}
        size="small"
        selectedValue={current}
        onTabSelect={(_e, d) => {
          const next = CEREMONIES.find((c) => c.id === d.value);
          if (next && next.id !== current) navigate(next.to);
        }}
        aria-label="Team Agile ceremonies"
      >
        {CEREMONIES.map((c) => (
          <Tab key={c.id} value={c.id}>
            {c.label}
          </Tab>
        ))}
      </TabList>
    </div>
  );
}

export function RitualPage({ ceremony }: { ceremony: Ceremony }) {
  const styles = useStyles();
  return (
    <div className={styles.page}>
      <RitualTabs current={ceremony} />
      {ceremony === "triage" ? <TriagePage /> : <StandupPage />}
    </div>
  );
}
