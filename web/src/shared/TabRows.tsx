import type { ReactNode } from "react";
import { makeStyles } from "@fluentui/react-components";
import { tabRowGap, tabRowsPadding } from "../shell/layoutTokens";

/** The class on the wrapper, for the structural tests. `data-tab-rows` marks
 *  the same element. */
export const TAB_ROWS_CLASS = "tabRows";

const useStyles = makeStyles({
  // The wrapper owns the space: padding above and below, a gap between two
  // rows. A tab row inside it has no margin and no padding of its own.
  root: {
    display: "flex",
    flexDirection: "column",
    rowGap: tabRowGap,
    paddingTop: tabRowsPadding,
    paddingBottom: tabRowsPadding,
  },
});

export interface TabRowsProps {
  /** One tab row (a Fluent `TabList`), or two stacked. */
  children: ReactNode;
}

/** The one wrapper every in-page tab row sits in. */
export function TabRows({ children }: TabRowsProps) {
  const styles = useStyles();
  return (
    <div className={`${TAB_ROWS_CLASS} ${styles.root}`} data-tab-rows="">
      {children}
    </div>
  );
}
