import { useEffect, useRef, useState } from "react";
import { Button, Caption1, Tooltip, makeStyles, tokens } from "@fluentui/react-components";
import { CheckmarkRegular, CopyRegular } from "@fluentui/react-icons";
import { copyText } from "./copyText";

/**
 * "File: <absolute path>", with a click to copy.
 *
 * On every page that shows one hub file -- a card, a training, a talk, a goal, a
 * 1:1 session. The file is the record, and the thing a person hands to an
 * assistant in a chat window is its address; the owner: "the most useful
 * is every detail view has the file where it lives, so I can share the path
 * with an agent easily." The path is the AGENT's machine's, which is normally
 * this one; an older agent sends none and the line is simply absent.
 *
 * A record that is not a hub file wears the same line with its own address and
 * says what it is: an issue's is its URL (`what="issue link"`).
 */
const useStyles = makeStyles({
  root: {
    display: "inline-flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
    minWidth: 0,
    maxWidth: "100%",
  },
  path: {
    color: tokens.colorNeutralForeground3,
    fontFamily: tokens.fontFamilyMonospace,
    overflowWrap: "anywhere",
    cursor: "pointer",
    ":hover": { color: tokens.colorNeutralForeground1 },
  },
  copied: { color: tokens.colorPaletteGreenForeground1 },
  button: { minWidth: "auto", flexShrink: 0 },
});

export function FilePath({ path, what = "file path" }: { path?: string; what?: string }) {
  const styles = useStyles();
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  if (!path) return null;
  const copy = async () => {
    await copyText(path);
    setCopied(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 2000);
  };
  return (
    <span className={styles.root} data-testid="file-path">
      <Tooltip content={`Copy the ${what}`} relationship="label">
        <Caption1 as="span" className={styles.path} onClick={copy}>
          {path}
        </Caption1>
      </Tooltip>
      <Button
        size="small"
        appearance="subtle"
        className={copied ? styles.copied : styles.button}
        icon={copied ? <CheckmarkRegular /> : <CopyRegular />}
        aria-label={copied ? "Copied" : `Copy the ${what}`}
        onClick={copy}
      />
      {copied ? (
        <Caption1 className={styles.copied} aria-live="polite">
          Copied
        </Caption1>
      ) : null}
    </span>
  );
}
