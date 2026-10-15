import { makeStyles, tokens } from "@fluentui/react-components";

/** The house list row: the box a collection card draws around each of its
 *  rows and the header line inside it. One source, so a list of rows has one
 *  density (Reminders, Spaces): change it here and every such card follows. */
export const useListRowStyles = makeStyles({
  row: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  rowHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
});

/** The exposed filter row above a card's list (FilterBadge chips). */
export const useFilterRowStyles = makeStyles({
  chips: {
    display: "flex",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalXS,
    marginBottom: tokens.spacingVerticalXS,
  },
});
