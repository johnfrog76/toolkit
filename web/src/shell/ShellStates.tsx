import { Body1, Button, Caption1, Subtitle1, makeStyles, tokens } from "@fluentui/react-components";
import { ArrowClockwiseRegular, PlugDisconnectedRegular } from "@fluentui/react-icons";
import { Link } from "react-router";

// The two things the SHELL has to say for itself, because no module can: "the
// agent is not there", and "there is no such page". Both used to be a blank
// page under the nav bar -- or worse, a card reporting "no activity found" when
// the truth was that nothing had been asked.

const useStyles = makeStyles({
  panel: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    textAlign: "center",
    gap: tokens.spacingVerticalM,
    maxWidth: "34rem",
    marginLeft: "auto",
    marginRight: "auto",
    marginTop: "12vh",
    padding: tokens.spacingHorizontalXXL,
    backgroundColor: tokens.colorSubtleBackground,
    borderRadius: tokens.borderRadiusLarge,
  },
  icon: { fontSize: "40px", color: tokens.colorNeutralForeground3 },
  command: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase300,
    backgroundColor: tokens.colorNeutralBackground3,
    padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalM}`,
    borderRadius: tokens.borderRadiusMedium,
    userSelect: "all",
  },
  banner: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    marginBottom: tokens.spacingVerticalM,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    backgroundColor: tokens.colorPaletteYellowBackground1,
    color: tokens.colorNeutralForeground1,
    border: `1px solid ${tokens.colorPaletteYellowBorder1}`,
    borderRadius: tokens.borderRadiusMedium,
  },
  bannerText: { flex: "1 1 16rem", minWidth: 0 },
});

// The prefix is config, and config comes from the agent -- which is the thing
// that is down. So the shell remembers the last prefix the agent told it, and a
// browser that has never heard one names the verb without inventing a prefix.
const PREFIX_KEY = "toolkit-cli-prefix";

export function rememberCliPrefix(prefix: string | undefined): void {
  if (!prefix) return;
  try {
    localStorage.setItem(PREFIX_KEY, prefix);
  } catch {
    /* a private window: the panel falls back to the bare verb */
  }
}

function rememberedCliPrefix(): string {
  try {
    return localStorage.getItem(PREFIX_KEY) ?? "";
  } catch {
    return "";
  }
}

interface AgentProps {
  onRetry: () => void;
  retrying: boolean;
}

function StartCommand() {
  const styles = useStyles();
  const prefix = rememberedCliPrefix();
  return prefix ? (
    <code className={styles.command}>{prefix}Agent</code>
  ) : (
    <Caption1>
      Run the <strong>Agent</strong> verb with your command prefix. docs/QUICKSTART.md has the line.
    </Caption1>
  );
}

/** Nothing has ever loaded: the whole page is this. */
export function AgentUnreachable({ onRetry, retrying }: AgentProps) {
  const styles = useStyles();
  return (
    <div className={styles.panel} role="alert">
      <PlugDisconnectedRegular className={styles.icon} aria-hidden />
      <Subtitle1 as="h1">The Toolkit agent is not running</Subtitle1>
      <Body1>
        This page reads your cards through a small local service, and it is not answering. Start it
        from a terminal:
      </Body1>
      <StartCommand />
      <Caption1>This page checks again every few seconds and fills in by itself.</Caption1>
      <Button
        appearance="primary"
        icon={<ArrowClockwiseRegular />}
        onClick={onRetry}
        disabled={retrying}
      >
        {retrying ? "Checking..." : "Check now"}
      </Button>
    </div>
  );
}

/** It was working and stopped: what is on screen is the last thing it said. */
export function AgentLostBanner({ onRetry, retrying }: AgentProps) {
  const styles = useStyles();
  return (
    <div className={styles.banner} role="alert">
      <PlugDisconnectedRegular aria-hidden />
      <span className={styles.bannerText}>
        <strong>The agent stopped answering.</strong> What you see is the last thing it said, and
        nothing can be saved. Start it again: <StartCommand />
      </span>
      <Button size="small" icon={<ArrowClockwiseRegular />} onClick={onRetry} disabled={retrying}>
        {retrying ? "Checking..." : "Check now"}
      </Button>
    </div>
  );
}

interface NotFoundProps {
  pathname: string;
  /** Set when the path belongs to a module that is switched off. */
  dormant?: { id: string; feature?: string };
  onOpenSettings: () => void;
}

export function NotFound({ pathname, dormant, onOpenSettings }: NotFoundProps) {
  const styles = useStyles();
  return (
    <div className={styles.panel}>
      <Subtitle1 as="h1">
        {dormant ? "That page is switched off" : "There is no page here"}
      </Subtitle1>
      <Body1>
        {dormant ? (
          <>
            <code>{pathname}</code> belongs to the <strong>{dormant.id}</strong> module, which is
            off on this machine. Turn it on in Settings and the page comes back.
          </>
        ) : (
          <>
            Nothing in the Toolkit answers to <code>{pathname}</code>. The address may be mistyped,
            or the card it pointed to has moved.
          </>
        )}
      </Body1>
      <div style={{ display: "flex", gap: tokens.spacingHorizontalS }}>
        {dormant ? (
          <Button appearance="primary" onClick={onOpenSettings}>
            Open Settings
          </Button>
        ) : null}
        <Link to="/" style={{ textDecoration: "none" }}>
          <Button appearance={dormant ? "secondary" : "primary"}>Go to Home</Button>
        </Link>
      </div>
    </div>
  );
}
