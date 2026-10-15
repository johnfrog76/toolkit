import { Body1, Button, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { PlugConnectedRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { useNavigate } from "react-router";

// What a LOCAL org shows where My Work and My Pull Requests would be. Off means
// absent -- but on a first run "absent" reads as "this product has two cards",
// and nothing says there is more or how to get it. So the gap says what it is,
// honestly: no pretend work items, no sample pull requests. One sentence, and
// the way to the setting that fills it.

const useStyles = makeStyles({
  body: {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    gap: tokens.spacingVerticalM,
    padding: `${tokens.spacingVerticalM} 0`,
  },
  header: { display: "flex", alignItems: "center", gap: tokens.spacingHorizontalS },
  quiet: { color: tokens.colorNeutralForeground3 },
});

export function ConnectAdoCard({ slug, orgName }: { slug: string; orgName: string }) {
  const styles = useStyles();
  const navigate = useNavigate();
  return (
    <PageCard
      headerLeft={
        <span className={styles.header}>
          <PlugConnectedRegular aria-hidden />
          <Subtitle2 as="h2">Your work items and pull requests</Subtitle2>
        </span>
      }
    >
      <div className={styles.body}>
        <Body1>
          <strong>{orgName}</strong> works from the cards in your hub alone, so there is nothing to
          list here. Connect it to a GitHub repo or an Azure DevOps organisation and this becomes My
          Work and My Pull Requests -- and a card can be started from an item&apos;s number.
        </Body1>
        <Button appearance="primary" onClick={() => navigate(`/connect/${slug}`)}>
          Connect this Space
        </Button>
        <Caption1 className={styles.quiet}>
          Four steps, each named as whose it is: the address, your sign-in, what it holds, sprint
          awareness. Everything else on this page works without it.
        </Caption1>
      </div>
    </PageCard>
  );
}
