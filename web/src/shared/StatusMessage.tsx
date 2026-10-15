import { useState, useEffect } from "react";
import { makeStyles, tokens } from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";
import { thinScrollbar } from "./thinScrollbar";

type StatusMessageProps = {
  status: "success" | "error";
  children: React.ReactNode;
  onDismiss?: () => void;
  autoHideMs?: number;
};

const DEFAULT_AUTO_HIDE_MS = 30000;

const useStyles = makeStyles({
  container: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    borderRadius: tokens.borderRadiusMedium,
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  content: {
    fontFamily: "monospace",
    fontSize: tokens.fontSizeBase200,
    whiteSpace: "pre-wrap" as const,
    flex: 1,
    minWidth: 0,
    maxHeight: "200px",
    overflowY: "auto" as const,
    ...thinScrollbar,
  },
  dismiss: {
    background: "none",
    border: "none",
    cursor: "pointer",
    padding: "2px",
    display: "flex",
    alignItems: "center",
    color: "inherit",
    opacity: 0.7,
    flexShrink: 0,
    ":hover": {
      opacity: 1,
    },
  },
});

export function StatusMessage({ status, children, onDismiss, autoHideMs }: StatusMessageProps) {
  const styles = useStyles();
  const [visible, setVisible] = useState(true);
  // A live region is only announced when its text changes after it is in the
  // page, so the region mounts empty and the message arrives one tick later.
  const [shown, setShown] = useState(false);

  useEffect(() => {
    setShown(true); // eslint-disable-line react-hooks/set-state-in-effect
  }, []);

  const hide = () => {
    setVisible(false);
    onDismiss?.();
  };

  useEffect(() => {
    const ms = autoHideMs ?? (status === "success" ? DEFAULT_AUTO_HIDE_MS : 0);
    if (ms <= 0) return;
    const timer = setTimeout(() => {
      setVisible(false);
      onDismiss?.();
    }, ms);
    return () => clearTimeout(timer);
  }, [autoHideMs, status, onDismiss]);

  if (!visible) return null;

  return (
    <div
      role={status === "error" ? "alert" : "status"}
      className={styles.container}
      style={{
        backgroundColor:
          status === "success"
            ? tokens.colorPaletteGreenBackground1
            : tokens.colorPaletteRedBackground1,
      }}
    >
      <div className={styles.content}>{shown ? children : null}</div>
      <button className={styles.dismiss} onClick={hide} aria-label="Dismiss" type="button">
        <DismissRegular fontSize={14} />
      </button>
    </div>
  );
}
