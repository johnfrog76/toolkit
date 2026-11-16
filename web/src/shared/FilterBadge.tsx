import type { ReactNode } from "react";
import { CounterBadge, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { Enter, Space } from "@fluentui/keyboard-keys";
import { chipToken } from "../shell/themeList";
import type { ChipAppearance } from "../shell/themeList";

// A selected chip's border, in the colour its appearance has in the theme in force.
const border = (a: ChipAppearance) => {
  const c = `var(--${chipToken(a)})`;
  return { borderTopColor: c, borderRightColor: c, borderBottomColor: c, borderLeftColor: c };
};

const useStyles = makeStyles({
  root: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalM}`,
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderLeftWidth: "4px",
    borderLeftColor: tokens.colorNeutralStroke2,
    cursor: "pointer",
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    transitionProperty: "border-left-color, border-color",
    transitionTimingFunction: tokens.curveEasyEase,
    transitionDuration: tokens.durationFast,
    "&:hover": {
      backgroundColor: tokens.colorNeutralBackground1Hover,
    },
  },
  pink: border("pink"),
  purple: border("purple"),
  orange: border("orange"),
  blue: border("blue"),
});

/** The named appearances (shell/themeList.ts CHIP_APPEARANCES): the name is the call site's,
 *  the colour is the theme's. */
export type FilterBadgeAppearance = ChipAppearance;

export interface FilterBadgeProps {
  label: string;
  /** Required, so a missing count is a compile error. A number is drawn, zero included;
   *  `null` says "no count" on purpose, for a chip that is a tab and not a filter. */
  count: number | null;
  active: boolean;
  onClick: () => void;
  appearance?: FilterBadgeAppearance;
  children?: ReactNode;
  // Single-select chip rows are radios (one active at a time); multi-select
  // rows (several tags AND'd together) are checkboxes. Defaults to radio to
  // match every existing call site.
  multi?: boolean;
}

export function FilterBadge({
  label,
  count,
  active,
  onClick,
  appearance = "purple",
  children,
  multi = false,
}: FilterBadgeProps) {
  const styles = useStyles();

  return (
    <div
      className={mergeClasses(styles.root, active && styles[appearance])}
      onClick={onClick}
      role={multi ? "checkbox" : "radio"}
      aria-checked={active}
      tabIndex={0}
      // Space is the canonical key for a checkbox/radio (Enter kept as a
      // courtesy); preventDefault stops Space from also scrolling the page.
      onKeyDown={(e) => {
        if (e.key === Enter || e.key === Space) {
          e.preventDefault();
          onClick();
        }
      }}
    >
      {label}
      {children}
      {count !== null && (
        <CounterBadge count={count} showZero appearance="filled" color="informative" size="small" />
      )}
    </div>
  );
}
