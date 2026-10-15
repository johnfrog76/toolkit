import { tokens } from "@fluentui/react-components";
import type { GriffelStyle } from "@fluentui/react-components";

// The one themed scrollbar. Spread it into the makeStyles block of anything
// that scrolls:
//
//   scrollArea: { overflowY: "auto", ...thinScrollbar },
//
// It was typed out three times, identically (PageCard, StatusMessage,
// TestHealth), and the board's lanes -- the fourth thing that scrolls -- had
// none at all.
//
// Two dialects, on purpose:
//   - `::-webkit-scrollbar` is what Chromium and Safari draw: 6px, a rounded
//     thumb in the neutral stroke, a transparent track.
//   - The standard `scrollbar-width` / `scrollbar-color`, from the same tokens,
//     for an engine that cannot read the first -- Firefox. They sit behind
//     `@supports not selector(::-webkit-scrollbar)` because Chromium 121+ reads
//     BOTH, and once the standard pair is set it ignores the pseudo-elements and
//     draws its own `thin` bar. The guard keeps one look per engine.
export const thinScrollbar = {
  "&::-webkit-scrollbar": { width: "6px", height: "6px" },
  "&::-webkit-scrollbar-track": { backgroundColor: "transparent" },
  "&::-webkit-scrollbar-thumb": {
    backgroundColor: tokens.colorNeutralStroke2,
    borderRadius: "3px",
  },
  "&::-webkit-scrollbar-thumb:hover": {
    backgroundColor: tokens.colorNeutralStroke1,
  },
  "@supports not selector(::-webkit-scrollbar)": {
    scrollbarWidth: "thin",
    scrollbarColor: `${tokens.colorNeutralStroke2} transparent`,
  },
} satisfies GriffelStyle;
