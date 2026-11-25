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
