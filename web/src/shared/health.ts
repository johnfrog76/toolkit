import { tokens } from "@fluentui/react-components";

export type Health = "good" | "warn" | "danger";

export function healthColor(health: Health): string {
  switch (health) {
    case "danger":
      return tokens.colorPaletteRedForeground1;
    case "warn":
      return tokens.colorPaletteDarkOrangeForeground1;
    case "good":
      return tokens.colorPaletteGreenForeground1;
  }
}

// Lower is worse: value <= dangerAt is "danger", <= warnAt is "warn", else "good".
export function thresholdHealth(value: number, dangerAt: number, warnAt: number): Health {
  if (value <= dangerAt) return "danger";
  if (value <= warnAt) return "warn";
  return "good";
}

export function daysRemainingHealthColor(daysRemaining: number | null): string {
  if (daysRemaining === null) return healthColor("good");
  return healthColor(thresholdHealth(daysRemaining, 2, 5));
}

// Higher is worse: value >= dangerAt is "danger", >= warnAt is "warn", else "good".
export function deficitHealth(value: number, warnAt: number, dangerAt: number): Health {
  if (value >= dangerAt) return "danger";
  if (value >= warnAt) return "warn";
  return "good";
}
