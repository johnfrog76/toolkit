import { Caption1, Spinner, makeStyles, tokens } from "@fluentui/react-components";

const BOOT_LABEL = "Loading toolkit...";

const useStyles = makeStyles({
  pageSpinner: {
    display: "flex",
    flexDirection: "column" as const,
    alignItems: "center",
    justifyContent: "center",
    minHeight: "60vh",
    gap: tokens.spacingVerticalL,
  },
});

// The first-load view. The spinner is a progressbar, and a progressbar with no
// name is announced as nothing; the caption beside it is what a sighted reader
// sees, so the same words name the spinner.
export function BootSpinner() {
  const styles = useStyles();
  return (
    <div className={styles.pageSpinner} style={{ minHeight: "100vh" }}>
      <Spinner size="huge" aria-label={BOOT_LABEL} />
      <Caption1>{BOOT_LABEL}</Caption1>
    </div>
  );
}
