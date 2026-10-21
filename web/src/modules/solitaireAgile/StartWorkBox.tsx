import { useEffect, useRef, useState } from "react";
import {
  Button,
  Caption1,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { CheckmarkRegular, CopyRegular, RocketRegular } from "@fluentui/react-icons";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { copyText } from "../../shared/copyText";
import { useGetEnvQuery } from "../../shell/api";
import { STARTWORK } from "../../shell/consts";
import { useRunStartWorkMutation } from "./api.solitaireAgile";

// The hand-off block in a copy box (AR-1 of the agent in the room; docs/modules/
// solitaire-agile.md, "StartWork: the hand-off block"). Opened from an item's
// row; it asks the CLI's `StartWork` for the block through the bridge ONCE, and
// shows what came back verbatim, with one button: Copy. A refusal shows the
// sentence the verb stated and nothing else. No agent runs here (D-AR1): the
// block is text the person carries to their editor.
//
// Where the launch exists -- /env's `startWorkLaunch`, the derived surface D-AR13
// names -- the box offers a second button, Launch: the same verb with `-Launch`, one
// more POST /api/cmd/StartWork, and what it printed (the PID and the log) or the
// sentence it refused with, shown under the block. Absent or false, one button.

const useStyles = makeStyles({
  surface: { maxWidth: "min(960px, calc(100vw - 32px))", width: "100%" },
  // The block keeps its lines: a long one scrolls sideways inside the box.
  block: {
    margin: 0,
    maxHeight: "60vh",
    overflow: "auto",
    whiteSpace: "pre",
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    backgroundColor: tokens.colorNeutralBackground3,
    padding: tokens.spacingHorizontalM,
    borderRadius: tokens.borderRadiusMedium,
  },
  error: { color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" },
  launched: { display: "block", marginTop: tokens.spacingVerticalS, whiteSpace: "pre-wrap" },
});

/** The block's title: its first line, when it has the head line's shape. */
export function blockTitle(block: string): string | null {
  const first = block.split("\n", 1)[0] ?? "";
  const lead = STARTWORK.text.head.slice(0, STARTWORK.text.head.indexOf("{"));
  return lead && first.startsWith(lead) ? first.slice(lead.length) : null;
}

type Outcome = { ok: true; block: string } | { ok: false; sentence: string };

export function StartWorkBox({ id, onClose }: { id: string; onClose: () => void }) {
  const styles = useStyles();
  const [runStartWork] = useRunStartWorkMutation();
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [copied, setCopied] = useState(false);
  const { data: env } = useGetEnvQuery();
  const launchOn = env?.startWorkLaunch === true;
  const [launching, setLaunching] = useState(false);
  const [launched, setLaunched] = useState<Outcome | null>(null);
  // ONE call per box: React's strict mode mounts twice in development, and the
  // block is the same either way.
  const asked = useRef(false);

  useEffect(() => {
    if (asked.current) return;
    asked.current = true;
    void (async () => {
      try {
        const result = await runStartWork({ id }).unwrap();
        if (result.status === "success" && result.output?.trim()) {
          setOutcome({ ok: true, block: result.output.replace(/\s+$/, "") });
        } else {
          setOutcome({
            ok: false,
            sentence: result.error?.trim() || result.output?.trim() || "StartWork said nothing.",
          });
        }
      } catch {
        setOutcome({ ok: false, sentence: "The agent did not answer. Nothing was read." });
      }
    })();
  }, [id, runStartWork]);

  const copy = async () => {
    if (!outcome?.ok) return;
    await copyText(outcome.block);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const launch = async () => {
    setLaunching(true);
    try {
      const result = await runStartWork({ id, launch: true }).unwrap();
      setLaunched(
        result.status === "success"
          ? { ok: true, block: (result.output ?? "").trim() }
          : { ok: false, sentence: result.error?.trim() || result.output?.trim() || "StartWork said nothing." },
      );
    } catch {
      setLaunched({ ok: false, sentence: "The agent did not answer. Nothing was started." });
    } finally {
      setLaunching(false);
    }
  };

  const title = outcome?.ok ? (blockTitle(outcome.block) ?? `Start work: ${id}`) : `Start work: ${id}`;

  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && onClose()}>
      <DialogSurface className={styles.surface}>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>{title}</DialogTitle>
          <DialogContent>
            {outcome === null ? (
              <Spinner size="tiny" label="Loading the hand-off..." />
            ) : outcome.ok ? (
              <pre
                className={styles.block}
                data-testid="start-work-block"
                tabIndex={0}
                role="region"
                aria-label="Hand-off block"
              >
                {outcome.block}
              </pre>
            ) : (
              <Caption1 className={styles.error} role="alert" data-testid="start-work-refusal">
                {outcome.sentence}
              </Caption1>
            )}
            {launched && (
              <Caption1
                className={launched.ok ? styles.launched : `${styles.launched} ${styles.error}`}
                role={launched.ok ? "status" : "alert"}
                data-testid="start-work-launched"
              >
                {launched.ok ? launched.block : launched.sentence}
              </Caption1>
            )}
          </DialogContent>
          <DialogActions>
            {outcome?.ok && (
              <Button
                appearance="primary"
                icon={copied ? <CheckmarkRegular /> : <CopyRegular />}
                onClick={() => void copy()}
              >
                {copied ? "Copied!" : "Copy"}
              </Button>
            )}
            {outcome?.ok && launchOn && (
              <Button icon={<RocketRegular />} disabled={launching} onClick={() => void launch()}>
                {launching ? "Launching..." : "Launch"}
              </Button>
            )}
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
