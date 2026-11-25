import { useEffect, useRef, useState } from "react";
import { Button, Caption1, Tooltip, makeStyles, tokens } from "@fluentui/react-components";
import { CheckmarkRegular, CopyRegular } from "@fluentui/react-icons";
import { FILE_LINE } from "../shell/fileLine";
import { copyText } from "./copyText";

/**
 * The compact File line: a short fixed label and the copy icon, the address in
 * the tooltip (hover and keyboard focus), and a click that copies it.
 *
 * On every page that shows one record -- a card, a training, a talk, a goal, a
 * 1:1 session, an issue. The file is the record, and the thing a person hands to
 * an assistant in a chat window is its address. The line is the same width
 * however long the address is, because the address is not drawn: it is the
 * tooltip and the description, the exact value the click copies.
 *
 * "Copy the file path" for a local file, "Copy the file link" for a URL (a
 * record that is not a hub file: an issue, a document read from the tracker).
 * The path is the AGENT's machine's, normally this one; an older agent sends
 * none and the line is simply absent.
 */
const useStyles = makeStyles({
  root: {
    display: "inline-flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
    flexShrink: 0,
    whiteSpace: "nowrap",
  },
  button: { minWidth: "auto", color: tokens.colorNeutralForeground3 },
  copied: { color: tokens.colorPaletteGreenForeground1 },
});

const isLink = (address: string) => /^https?:\/\//i.test(address);

export function FilePath({ path }: { path?: string }) {
  const styles = useStyles();
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  if (!path) return null;
  const label = isLink(path) ? FILE_LINE.copyLink : FILE_LINE.copyPath;
  const copy = async () => {
    await copyText(path);
    setCopied(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 2000);
  };
  return (
    <span className={styles.root} data-testid="file-path">
      <Tooltip content={path} relationship="description">
        <Button
          size="small"
          appearance="subtle"
          className={copied ? styles.copied : styles.button}
          icon={copied ? <CheckmarkRegular /> : <CopyRegular />}
          iconPosition="after"
          onClick={copy}
        >
          {label}
        </Button>
      </Tooltip>
      {copied ? (
        <Caption1 className={styles.copied} aria-live="polite">
          {FILE_LINE.copied}
        </Caption1>
      ) : null}
    </span>
  );
}
