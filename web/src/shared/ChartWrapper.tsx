import { makeStyles, tokens } from "@fluentui/react-components";

const useStyles = makeStyles({
  chartWrapper: {
    paddingLeft: tokens.spacingHorizontalXXXL,
    paddingRight: tokens.spacingHorizontalXXXL,
    paddingTop: tokens.spacingVerticalL,
    paddingBottom: tokens.spacingVerticalL,
  },
});

export const ChartWrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const styles = useStyles();
  return <div className={styles.chartWrapper}>{children}</div>;
};
