import type { ReactNode } from "react";
import { CounterBadge, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { Enter, Space } from "@fluentui/keyboard-keys";

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
  pink: {
    borderTopColor: tokens.colorPaletteBerryBorderActive,
    borderRightColor: tokens.colorPaletteBerryBorderActive,
    borderBottomColor: tokens.colorPaletteBerryBorderActive,
    borderLeftColor: tokens.colorPaletteBerryBorderActive,
  },
  purple: {
    borderTopColor: tokens.colorPaletteCornflowerBorderActive,
    borderRightColor: tokens.colorPaletteCornflowerBorderActive,
    borderBottomColor: tokens.colorPaletteCornflowerBorderActive,
    borderLeftColor: tokens.colorPaletteCornflowerBorderActive,
  },
  orange: {
    borderTopColor: tokens.colorPalettePeachBorderActive,
    borderRightColor: tokens.colorPalettePeachBorderActive,
    borderBottomColor: tokens.colorPalettePeachBorderActive,
    borderLeftColor: tokens.colorPalettePeachBorderActive,
  },
});

export type FilterBadgeAppearance = "pink" | "purple" | "orange";

interface FilterBadgeProps {
  label: string;
  count?: number;
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
      {count != null && (
        <CounterBadge count={count} appearance="filled" color="informative" size="small" />
      )}
    </div>
  );
}
