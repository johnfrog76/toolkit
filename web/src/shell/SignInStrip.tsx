import { useState } from "react";
import { Body1, Button, makeStyles, tokens } from "@fluentui/react-components";
import {
  ArrowSyncRegular,
  CheckmarkRegular,
  CopyRegular,
  InfoRegular,
} from "@fluentui/react-icons";
import { copyText } from "../shared/copyText";
import { useRefreshEnvMutation } from "./api";
import type { EnvStatus } from "./api";

// "Sign in to Azure DevOps": a next step, not a failure. It is drawn in the
// NEUTRAL, informational style -- the page's own surface and stroke, an info icon,
// role="status" -- and never the error or warning colour: error is reserved for
// the agent being lost or a serious failure, and being signed out is neither.
//
// The strip only SHOWS the command and offers to copy it. Signing in is the
// person's, said and checked and never run: nothing here starts `az`, and "Check
// again" asks the agent to look again (GET /api/env?refresh=1, the System card's
// own refresh), so the strip goes once the person has signed in elsewhere.

const useStyles = makeStyles({
  strip: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    marginBottom: tokens.spacingVerticalM,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    backgroundColor: tokens.colorNeutralBackground3,
    color: tokens.colorNeutralForeground1,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
  },
  icon: { color: tokens.colorNeutralForeground3, fontSize: "20px", flexShrink: 0 },
  text: { flex: "1 1 16rem", minWidth: 0 },
  command: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase300,
    backgroundColor: tokens.colorNeutralBackground1,
    padding: `${tokens.spacingVerticalXXS} ${tokens.spacingHorizontalS}`,
    borderRadius: tokens.borderRadiusSmall,
    userSelect: "all",
    overflowWrap: "anywhere",
  },
  actions: { display: "flex", gap: tokens.spacingHorizontalS, flexWrap: "wrap" },
});

/** The command the strip shows, or null where the strip is absent. The agent decides
 *  (`azSignIn.needed`); this only reads it. */
export function signInCommand(env: EnvStatus | undefined): string | null {
  const sign = env?.azSignIn;
  return sign?.needed ? sign.command : null;
}

export function SignInStrip({ env }: { env: EnvStatus | undefined }) {
  const styles = useStyles();
  const [refreshEnv, { isLoading }] = useRefreshEnvMutation();
  const [copied, setCopied] = useState(false);
  const command = signInCommand(env);
  if (!command) return null;
  return (
    <div className={styles.strip} role="status" data-testid="sign-in-strip">
      <InfoRegular className={styles.icon} aria-hidden />
      <Body1 className={styles.text}>
        <strong>Sign in to Azure DevOps.</strong> Run this in a terminal, then check again:{" "}
        <code className={styles.command}>{command}</code>
      </Body1>
      <div className={styles.actions}>
        <Button
          size="small"
          icon={copied ? <CheckmarkRegular /> : <CopyRegular />}
          onClick={() => {
            void copyText(command).then(() => setCopied(true));
          }}
        >
          {copied ? "Copied" : "Copy"}
        </Button>
        <Button
          size="small"
          icon={<ArrowSyncRegular />}
          onClick={() => void refreshEnv()}
          disabled={isLoading}
        >
          {isLoading ? "Checking..." : "Check again"}
        </Button>
      </div>
    </div>
  );
}
