import type { MouseEvent } from "react";
import { Caption1, Link, tokens } from "@fluentui/react-components";
import { useNavigate } from "react-router";
import { useGetEnvQuery } from "../../shell/api";
import { hubSyncWords } from "./hubSync";
import { SYSTEM_PATH } from "./paths";

// The one foot line every card that writes into the hub draws -- the Spaces,
// Hub Designs, Reminders and the Reviews -- through PageCard's `footNote`
// (docs/CONFIGURATION.md, "Syncing the hub from the web app").
//
// It READS. The state is /env's `hubSync`, already in the cache every page
// gates on; this line never asks for a fetch, so the only fetches are the
// System page's own (once when it opens, and Sync the hub). Absent under any
// storeSync but git, and absent once a fetch has found the hub in step.

export function HubSyncLine() {
  const { data: env } = useGetEnvQuery();
  const navigate = useNavigate();
  const words = hubSyncWords(env?.hubSync);
  if (!words || words.inStep) return null;

  const open = (e: MouseEvent) => {
    e.preventDefault();
    navigate(SYSTEM_PATH);
  };
  return (
    <Caption1
      data-testid="hub-sync-line"
      style={{
        display: "block",
        paddingTop: tokens.spacingVerticalXS,
        color: words.warn ? tokens.colorPaletteRedForeground1 : tokens.colorNeutralForeground3,
      }}
    >
      The hub is {words.parts.join(" and ")}.{" "}
      <Link href={SYSTEM_PATH} onClick={open} inline>
        Sync on the System page
      </Link>
    </Caption1>
  );
}
