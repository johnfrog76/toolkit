import type { ReactNode } from "react";
import { makeStyles, tokens } from "@fluentui/react-components";

const useStyles = makeStyles({
  fill: {
    display: "flex",
    alignItems: "center",
    flexGrow: 1,
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalXS,
    width: "100%",
  },
});

export function ContentFlexFillWrapper({ children }: { children: ReactNode }) {
  const styles = useStyles();
  return <div className={styles.fill}>{children}</div>;
}
